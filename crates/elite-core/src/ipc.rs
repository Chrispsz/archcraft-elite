// ═════════════════════════════════════════════════════════════════════════
// elite-core::ipc — o protocolo do bus.sock (o fio da casa 2.0)
// ═════════════════════════════════════════════════════════════════════════
// UDS da sessão em /run/user/$UID/elite/bus.sock. O fio é simples e
// determinístico: 4 bytes little-endian de comprimento + o JSON da msg.
// Sem servidor de middleware: o elite-daemon é O dono do socket (bind),
// os módulos gráficos são clientes que assinam; o craft-dump lê por
// conexão única. Bloqueio puro do std — epoll/ZMQ viria depois de
// PROVADO que o bloqueio dói (a lei da casa: zero polling, o resto é
// evento).
// ═════════════════════════════════════════════════════════════════════════

use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;

use crate::BusMsg;

/// O comprimento máximo de um quadro (1 MiB) — o fio não é lixeira;
/// msg maior é bug de quem enviou, não cabeça para o leitor.
pub const FRAME_MAX: u32 = 1024 * 1024;

#[derive(Debug)]
pub enum IpcError {
    Io(std::io::Error),
    Json(serde_json::Error),
    /// quadro maior que o FRAME_MAX — a mensagem nunca entra
    FrameTooBig(u32),
    /// o par fechou no meio do quadro (a sessão morrendo é evento, não erro mudo)
    Truncated,
}

impl std::fmt::Display for IpcError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            IpcError::Io(e) => write!(f, "io: {e}"),
            IpcError::Json(e) => write!(f, "json: {e}"),
            IpcError::FrameTooBig(n) => write!(f, "quadro {n} > {FRAME_MAX}"),
            IpcError::Truncated => write!(f, "quadro truncado (par morreu no meio)"),
        }
    }
}

impl std::error::Error for IpcError {}

impl From<std::io::Error> for IpcError {
    fn from(e: std::io::Error) -> Self {
        IpcError::Io(e)
    }
}

impl From<serde_json::Error> for IpcError {
    fn from(e: serde_json::Error) -> Self {
        IpcError::Json(e)
    }
}

/// Escreve um quadro completo (len LE + json).
pub fn send_frame(w: &mut impl Write, msg: &BusMsg) -> Result<(), IpcError> {
    let json = serde_json::to_vec(msg)?;
    let len = json.len() as u32;
    if len > FRAME_MAX {
        return Err(IpcError::FrameTooBig(len));
    }
    w.write_all(&len.to_le_bytes())?;
    w.write_all(&json)?;
    w.flush()?;
    Ok(())
}

/// Lê um quadro completo (len LE + json) — `Ok(None)` = o par fechou LIMPO
/// antes de qualquer byte (fim de fio legítimo).
pub fn recv_frame(r: &mut impl Read) -> Result<Option<BusMsg>, IpcError> {
    let mut len_buf = [0u8; 4];
    match r.read_exact(&mut len_buf) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(e.into()),
    }
    let len = u32::from_le_bytes(len_buf);
    if len > FRAME_MAX {
        return Err(IpcError::FrameTooBig(len));
    }
    if len == 0 {
        return Err(IpcError::Truncated);
    }
    let mut json = vec![0u8; len as usize];
    r.read_exact(&mut json).map_err(|_| IpcError::Truncated)?;
    Ok(Some(serde_json::from_slice(&json)?))
}

/// LIGA o socket da sessão: bind no caminho (o tmpfs da sessão já existe),
/// com o cleanup honesto do fóssil (socket órfão de sessão morta é
/// desconectado — o labwc relogin deixa o fio morto no disco).
pub fn bind_bus(path: &Path) -> std::io::Result<UnixListener> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let _ = std::fs::remove_file(path); // fóssil órfão sai (errno tolerado)
    UnixListener::bind(path)
}

/// CONECTA como cliente (None = o daemon ainda não subiu — o cliente
/// honesto reaparece; a casa não inventa estado).
/// 1.0-93 — O TETO DE 500ms (a ordem do dono, rig da 1.0-92: nenhum
/// CLI/cliente da casa pode TRAVAR esperando um daemon ocupado — o
/// `connect_timeout` com o `IPC_CONNECT_TETO_MS` corta a classe dos
/// 49s no osso; o UDS local sadio conecta em µs, o teto só morde o
/// mundo doente). A ESCRITA também veste o teto: um daemon engasgado
/// com o buffer cheio recebe `WouldBlock` honesto em vez de segurar o
/// chamador para sempre (o leitor NÃO veste — o timeout de leitura
/// seria lido como QUEDA pelo BusClient e viraria churn de reconexão).
pub fn connect_bus(path: &Path) -> Option<UnixStream> {
    use std::time::Duration;
    let teto = Duration::from_millis(crate::IPC_CONNECT_TETO_MS);
    // (o SocketAddr::from_pathname é estável desde o 1.70; o caminho
    // abstract/inválido cai no connect cru — o honesto de sempre)
    let stream = match std::os::unix::net::SocketAddr::from_pathname(path) {
        Ok(addr) => UnixStream::connect_timeout(&addr, teto).ok(),
        Err(_) => UnixStream::connect(path).ok(),
    }?;
    let _ = stream.set_write_timeout(Some(teto));
    Some(stream)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::GameModeState;
    use std::io::Cursor;

    #[test]
    fn quadro_vai_e_volta_pelo_fio() {
        let msg = BusMsg::Hello { who: "craft-bar-rs".into() };
        let mut wire = Vec::new();
        send_frame(&mut wire, &msg).unwrap();
        let mut cur = Cursor::new(wire);
        let back = recv_frame(&mut cur).unwrap().unwrap();
        assert_eq!(back, msg);
    }

    #[test]
    fn fim_de_fio_limpo_e_nenhum_menos_que_um_erro_mudo() {
        let mut cur = Cursor::new(Vec::<u8>::new());
        assert!(matches!(recv_frame(&mut cur), Ok(None)));
    }

    #[test]
    fn quadro_monstro_e_rejeitado_na_porta() {
        let len = (FRAME_MAX + 1).to_le_bytes();
        let mut cur = Cursor::new(len.to_vec());
        let err = recv_frame(&mut cur).unwrap_err();
        assert!(matches!(err, IpcError::FrameTooBig(_)));
    }

    #[test]
    fn par_morto_no_meio_do_quadro_e_nomeado() {
        let msg = BusMsg::Hello { who: "x".into() };
        let mut wire = Vec::new();
        send_frame(&mut wire, &msg).unwrap();
        wire.pop(); // o último byte morre com o par
        let mut cur = Cursor::new(wire);
        let err = recv_frame(&mut cur).unwrap_err();
        assert!(matches!(err, IpcError::Truncated));
    }

    #[test]
    fn bind_e_connect_real_no_tmpfs_de_teste() {
        let dir = std::env::temp_dir().join(format!(
            "elite-bus-teste-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let sock = dir.join("bus.sock");
        let listener = bind_bus(&sock).unwrap();
        // o bind limpa o fóssil: segundo bind no MESMO caminho também nasce
        drop(listener);
        let listener2 = bind_bus(&sock).unwrap();
        let mut client = connect_bus(&sock).expect("cliente conecta no socket vivo");
        let msg = BusMsg::GameMode(GameModeState {
            active: true,
            game: Some("steam_app_413150".into()),
            gpu_performance: true,
        });
        send_frame(&mut client, &msg).unwrap();
        let (mut server, _) = listener2.accept().unwrap();
        let back = recv_frame(&mut server).unwrap().unwrap();
        assert_eq!(back, msg);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
