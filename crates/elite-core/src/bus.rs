// ═════════════════════════════════════════════════════════════════════════
// elite-core::bus — o BUS VIVO da sessão 2.0 (servidor + cliente)
// ═════════════════════════════════════════════════════════════════════════
// A Fase 2 da reconstrução: o bus.sock deixa de ser desenho no papel e
// ganha os dois lados do fio —
//
//   · `BusServer` (o lado do elite-daemon): aceita clientes no
//     `/run/user/$UID/elite/bus.sock`, registra quem chegou (o `Hello`
//     de apresentação é obrigatório — o daemon nomeia no papel do
//     dump), RECEBE os pedidos (`BusReq`) num canal para o núcleo do
//     daemon e PUBLICA os estados (`broadcast`) para todos de uma vez.
//     Cliente morto sai da lista sem drama (EPIPE é evento, não erro).
//
//   · `BusClient` (o lado da barra/dock/telemetria): UMA thread de
//     fundo que conecta, se apresenta e lê QUADROS PARA SEMPRE; cada
//     mensagem vira item de um `Receiver<BusMsg>` que a UI drena no
//     idle (a mesma lei do canal mpsc da casa — a thread NUNCA toca
//     GTK). A reconexão é com backoff exponencial 5→20→100ms (a lição
//     E135: o daemon pode renascer; o cliente honesto reaparece —
//     nunca estado inventado no vácuo). Pedidos (`send_req`) viajam
//     pela MESMA conexão (full-duplex: o leitor é dono da ponta de
//     leitura via try_clone, o escritor da de escrita).
//
// Leis que este módulo carrega:
//   · std-first: nada de GTK, nada de async — a UI drena o Receiver;
//   · o fio é o quadro do ipc.rs (4B LE + JSON, FRAME_MAX 1 MiB);
//   · o `Hello` é o PRIMEIRO quadro de todo cliente (o sem quadrado
//     do servidor não fala com anônimos — mas não desconecta: só
//     ignora até a apresentação; o cliente honesto sempre apresenta);
//   · Ack é dirigido (send_to) — nunca broadcast de veredito alheio.
// ═════════════════════════════════════════════════════════════════════════

use std::collections::HashMap;
use std::io::Write;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::{Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use crate::ipc::{bind_bus, recv_frame, send_frame};
use crate::{BusMsg, BusReq};

/// O que chega ao núcleo do daemon pela porta do bus.
#[derive(Debug)]
pub enum Incoming {
    /// um cliente se apresentou (o snapshot de boas-vindas é pedido da
    /// porta — o núcleo manda o estado atual dirigido a ELE)
    Hello { id: u32, who: String },
    /// um cliente pediu um verbo da casa (o eco do Ack é dever do núcleo)
    Req { id: u32, req: BusReq },
}

/// A ficha de um cliente conectado (a ponta de escrita + a identidade).
struct Ficha {
    stream: Mutex<UnixStream>,
    who: String,
}

/// O SERVIDOR do bus (o lado do elite-daemon). Barato de clonar: tudo
/// mora em Arc — o núcleo publica e o accept-loop alimenta a lista.
pub struct BusServer {
    inner: Arc<Inner>,
}

struct Inner {
    clientes: Mutex<HashMap<u32, Arc<Ficha>>>,
    tx_incoming: Sender<Incoming>,
    path: PathBuf,
    /// contadores vivos para o papel do dump (conectados/desconectados)
    n_ligacoes: AtomicU32,
    n_quadros_enviados: AtomicU32,
    /// a vida do servidor: false no Drop — os atendentes fecham os
    /// fios e saem (a morte do bus é EVENTO para os clientes, nunca
    /// um socket aberto apontando para ninguém)
    viva: AtomicBool,
}

impl BusServer {
    /// Liga o bus no caminho e devolve (servidor, canal do núcleo).
    /// A thread de accept nasce AQUI e vive enquanto o servidor viver.
    pub fn start(path: &Path) -> std::io::Result<(Arc<BusServer>, Receiver<Incoming>)> {
        let listener = bind_bus(path)?;
        let (tx, rx) = std::sync::mpsc::channel::<Incoming>();
        let inner = Arc::new(Inner {
            clientes: Mutex::new(HashMap::new()),
            tx_incoming: tx,
            path: path.to_path_buf(),
            n_ligacoes: AtomicU32::new(0),
            n_quadros_enviados: AtomicU32::new(0),
            viva: AtomicBool::new(true),
        });
        let srv = Arc::new(BusServer { inner: Arc::clone(&inner) });
        std::thread::Builder::new()
            .name("elite-bus-accept".into())
            .spawn({
                let listener = listener;
                let inner = inner;
                move || {
                    let mut next_id = 1u32;
                    for conn in listener.incoming() {
                        let Ok(conn) = conn else { continue };
                        let _ = conn.set_read_timeout(Some(Duration::from_secs(120)));
                        let id = next_id;
                        next_id += 1;
                        let inner = Arc::clone(&inner);
                        std::thread::Builder::new()
                            .name(format!("elite-bus-client-{id}"))
                            .spawn(move || atende(inner, id, conn))
                            .ok();
                    }
                }
            })?;
        Ok((srv, rx))
    }

    /// PUBLICA para TODOS os clientes conectados (o fio é serializado
    /// UMA vez; quem morreu no meio sai da lista com voz nenhuma — EPIPE
    /// é evento de sessão, não erro para o núcleo).
    pub fn broadcast(&self, msg: &BusMsg) {
        let json = match serde_json::to_vec(msg) {
            Ok(j) => j,
            Err(_) => return, // BugMsg serializável é contrato dos tipos
        };
        let mut mortos: Vec<u32> = Vec::new();
        {
            let guard = self.inner.clientes.lock().unwrap();
            for (id, ficha) in guard.iter() {
                let mut w = ficha.stream.lock().unwrap();
                if write_quadro_cru(&mut *w, &json).is_err() {
                    mortos.push(*id);
                }
            }
        }
        if !mortos.is_empty() {
            let mut guard = self.inner.clientes.lock().unwrap();
            for id in mortos {
                guard.remove(&id);
            }
        }
        self.inner.n_quadros_enviados.fetch_add(1, Ordering::Relaxed);
    }

    /// Dirige UMA mensagem a UM cliente (o Ack e o snapshot de boas-
    /// vindas nunca são algazarra coletiva). Cliente id ausente = noop
    /// silencioso (morreu entre o pedido e a resposta — o estado
    /// público seguinte é a fonte da verdade).
    pub fn send_to(&self, id: u32, msg: &BusMsg) {
        let json = match serde_json::to_vec(msg) {
            Ok(j) => j,
            Err(_) => return,
        };
        let guard = self.inner.clientes.lock().unwrap();
        if let Some(ficha) = guard.get(&id) {
            let mut w = ficha.stream.lock().unwrap();
            if write_quadro_cru(&mut *w, &json).is_ok() {
                self.inner.n_quadros_enviados.fetch_add(1, Ordering::Relaxed);
            }
        }
    }

    /// Os clientes vivos agora (nomes — o papel do dump pergunta).
    pub fn clientes(&self) -> Vec<String> {
        self.inner
            .clientes
            .lock()
            .unwrap()
            .values()
            .map(|f| f.who.clone())
            .collect()
    }

    /// As contagens vivas (o papel do dump pergunta).
    pub fn contadores(&self) -> (u32, u32) {
        (
            self.inner.n_ligacoes.load(Ordering::Relaxed),
            self.inner.n_quadros_enviados.load(Ordering::Relaxed),
        )
    }

    /// O caminho do fio (o dump nomeia).
    pub fn path(&self) -> &Path {
        &self.inner.path
    }
}

impl Drop for BusServer {
    fn drop(&mut self) {
        // a morte do bus é EVENTO: os atendentes fecham os fios das
        // clientes na próxima fatia (≤500ms) — a reconexão delas é
        // para ISSO (o socket aberto apontando para ninguém nunca
        // existiu por desenho)
        self.inner.viva.store(false, Ordering::Relaxed);
    }
}

/// A tarefa por cliente: espera o `Hello` (primeiro quadro), registra
/// a ficha, avisa o núcleo e vira o LEITOR dos pedidos até o fim do
/// fio. O fim limpo é rotina (relogin/exit); o truncado é nomeado no
/// papel e o cliente sai da lista — nunca mistério mudo. O servidor
/// morrendo (viva=false) FECHA os fios: a morte do bus é evento para
/// o cliente (a reconexão E135 é para ISSO).
fn atende(inner: Arc<Inner>, id: u32, mut conn: UnixStream) {
    // o Hello tem teto de 30s; o loop de pedidos dorme em fatias de
    // 500ms para conferir a vida do servidor (idle CPU ~zero)
    let _ = conn.set_read_timeout(Some(Duration::from_secs(30)));
    let hello = match recv_frame(&mut conn) {
        Ok(Some(BusMsg::Hello { who })) => who,
        _ => return, // anônimo ou fio morto: a porta não fala
    };
    let Ok(out) = conn.try_clone() else {
        return; // sem clone não há full-duplex honesto
    };
    let ficha = Arc::new(Ficha {
        stream: Mutex::new(out),
        who: hello.clone(),
    });
    // (a ponta de leitura segue sendo a `conn`; a ficha ficou com o clone)
    inner
        .clientes
        .lock()
        .unwrap()
        .insert(id, Arc::clone(&ficha));
    inner.n_ligacoes.fetch_add(1, Ordering::Relaxed);
    let _ = inner.tx_incoming.send(Incoming::Hello { id, who: hello });
    // o LEITOR de pedidos (o mesmo fio, ponta oposta da ficha)
    let _ = conn.set_read_timeout(Some(Duration::from_millis(500)));
    loop {
        if !inner.viva.load(Ordering::Relaxed) {
            break; // o servidor morreu: o fio fecha com ele
        }
        match recv_frame(&mut conn) {
            Ok(Some(BusMsg::Req(req))) => {
                if inner.tx_incoming.send(Incoming::Req { id, req }).is_err() {
                    break; // o núcleo morreu: o fio inteiro cai junto
                }
            }
            Ok(Some(_)) => {} // publicações do cliente: o contrato é mudo
            Ok(None) => break, // fim de fio limpo
            Err(e) => {
                // timeout de fatia é ESPERA (a vida é re-conferida no
                // giro); erro real é o par morto no meio do quadro
                let eh_fatia = matches!(&e, crate::ipc::IpcError::Io(io)
                    if io.kind() == std::io::ErrorKind::WouldBlock
                        || io.kind() == std::io::ErrorKind::TimedOut);
                if !eh_fatia {
                    break;
                }
            }
        }
    }
    inner.clientes.lock().unwrap().remove(&id);
}

/// O quadro cru (len + json já serializado — a serialização Única do
/// broadcast; o ipc::send_frame serve quem tem a BusMsg inteira).
fn write_quadro_cru(w: &mut impl Write, json: &[u8]) -> std::io::Result<()> {
    let len = json.len() as u32;
    if len > crate::ipc::FRAME_MAX {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "quadro acima do teto",
        ));
    }
    w.write_all(&len.to_le_bytes())?;
    w.write_all(json)?;
    w.flush()
}

// ── O CLIENTE (a barra, a dock, a telemetria) ───────────────────────────

/// O cliente do bus da sessão: uma thread de fundo lê quadros para
/// sempre (com reconexão honesta) e entrega cada `BusMsg` no Receiver.
/// Os PEDIDOS viajam pelo MESMO fio (a escrita é serializada por Mutex;
/// a leitura mora na thread — full-duplex de UnixStream).
pub struct BusClient {
    out: Mutex<UnixStream>,
    next_req_id: AtomicU32,
    path: PathBuf,
    who: String,
}

impl BusClient {
    /// Conecta, se apresenta e devolve (cliente, canal das mensagens).
    /// `None` honesto quando o daemon ainda não existe (o chamador
    /// reaparece — a casa não inventa estado no vácuo).
    pub fn connect(
        path: &Path,
        who: &str,
    ) -> Option<(Arc<BusClient>, Receiver<BusMsg>)> {
        let mut stream = crate::ipc::connect_bus(path)?;
        send_frame(&mut stream, &BusMsg::Hello { who: who.to_string() }).ok()?;
        let out = stream.try_clone().ok()?;
        let (tx, rx) = std::sync::mpsc::channel::<BusMsg>();
        let cli = Arc::new(BusClient {
            out: Mutex::new(out),
            next_req_id: AtomicU32::new(1),
            path: path.to_path_buf(),
            who: who.to_string(),
        });
        // a thread leitora: vive no fio, reconecta com backoff (a lição
        // E135 da dock: 5 → 20 → 100ms; o daemon pode renascer)
        {
            let cli = Arc::clone(&cli);
            let stream = stream;
            std::thread::Builder::new()
                .name("elite-bus-leitor".into())
                .spawn(move || {
                    let mut s = stream;
                    let mut back = 5u64;
                    'conexao: loop {
                        loop {
                            match recv_frame(&mut s) {
                                Ok(Some(msg)) => {
                                    if cli.envia_canal(&tx, msg).is_err() {
                                        return; // a UI foi embora: fim
                                    }
                                }
                                Ok(None) | Err(_) => break, // o fio caiu
                            }
                        }
                        // reconexão honesta: o fio renasce quando o
                        // daemon renascer (nunca estado inventado)
                        loop {
                            std::thread::sleep(Duration::from_millis(back));
                            back = (back * 4).min(100);
                            if let Some(mut nova) = crate::ipc::connect_bus(&cli.path) {
                                if send_frame(
                                    &mut nova,
                                    &BusMsg::Hello { who: cli.who.clone() },
                                )
                                .is_ok()
                                {
                                    // a ponta de escrita troca junto
                                    if let Ok(clone) = nova.try_clone() {
                                        *cli.out.lock().unwrap() = clone;
                                    }
                                    s = nova;
                                    back = 5;
                                    continue 'conexao;
                                }
                            }
                        }
                    }
                })
                .ok()?;
        }
        Some((cli, rx))
    }

    fn envia_canal(&self, tx: &Sender<BusMsg>, msg: BusMsg) -> Result<(), ()> {
        tx.send(msg).map_err(|_| ())
    }

    /// Envia um pedido ao daemon. O `id` do Ack é o retorno (o eco cru
    /// — a correlação é dever de quem pediu). `None` = fio morto AGORA
    /// (a reconexão vem; o chamador decide repetir ou esperar estado).
    pub fn send_req(&self, req: BusReq) -> Option<u32> {
        let id = self.next_req_id.fetch_add(1, Ordering::Relaxed);
        let msg = BusMsg::Req(req);
        let mut w = self.out.lock().unwrap();
        send_frame(&mut *w, &msg).ok()?;
        Some(id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{BusMsg, BusReq, GameModeState, WindowInfo};
    use std::path::PathBuf;

    fn tmpdir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!(
            "elite-bus-{tag}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn o_bus_vivo_completo_hello_broadcast_req_ack() {
        // O CIRCUITO INTEIRO da Fase 2: o daemon liga o bus, dois
        // clientes se apresentam, o daemon PUBLICA para os dois, um
        // cliente PEDE, o núcleo ecoa o Ack dirigido — e o papel
        // nomeia os clientes vivos.
        let dir = tmpdir("circuito");
        let sock = dir.join("bus.sock");
        let (srv, rx_nucleo) = BusServer::start(&sock).unwrap();

        // os DOIS clientes (barra e dock)
        let (bar, rx_bar) = BusClient::connect(&sock, "craft-bar-rs").unwrap();
        let (_dock, rx_dock) = BusClient::connect(&sock, "craft-dock-rs").unwrap();

        // o núcleo vê os dois Hellos (com identidade — o id é do
        // SERVIDOR; quem é quem mora no `who`, nunca na ordem de chegada)
        let mut ids = HashMap::new();
        let mut esperando = 2;
        while esperando > 0 {
            match rx_nucleo.recv_timeout(Duration::from_secs(2)).unwrap() {
                Incoming::Hello { id, who } => {
                    assert!(!who.is_empty());
                    ids.insert(who, id);
                    esperando -= 1;
                }
                Incoming::Req { .. } => panic!("pedido antes da hora"),
            }
        }
        let id_bar = *ids.get("craft-bar-rs").expect("a barra se apresentou");
        // o snapshot de boas-vindas é DIRIGIDO (send_to, nunca broadcast)
        srv.send_to(id_bar, &BusMsg::Windows { windows: vec![] });
        let Ok(BusMsg::Windows { windows }) = rx_bar.recv_timeout(Duration::from_secs(2))
        else {
            panic!("a barra não recebeu o snapshot dirigido")
        };
        assert!(windows.is_empty());
        assert!(
            rx_dock.recv_timeout(Duration::from_millis(50)).is_err(),
            "o snapshot dirigido não vaza para a dock"
        );

        // o BROADCAST alcança os DOIS no mesmo instante
        srv.broadcast(&BusMsg::GameMode(GameModeState {
            active: true,
            game: Some("steam_app_413150".into()),
            gpu_performance: true,
        }));
        for rx in [&rx_bar, &rx_dock] {
            let msg = rx.recv_timeout(Duration::from_secs(2)).unwrap();
            assert!(matches!(msg, BusMsg::GameMode(_)), "chegou {msg:?}");
        }

        // o PEDIDO da dock cruza e o Ack DIRIGIDO volta
        let id_ack = bar.send_req(BusReq::Close { id: 42 }).unwrap();
        match rx_nucleo.recv_timeout(Duration::from_secs(2)).unwrap() {
            Incoming::Req { id, req: BusReq::Close { id: janela } } => {
                assert_eq!(janela, 42);
                srv.send_to(id, &BusMsg::Ack { id: id_ack, ok: true });
            }
            other => panic!("o pedido não chegou como esperado: {other:?}"),
        }
        let msg = rx_bar.recv_timeout(Duration::from_secs(2)).unwrap();
        assert_eq!(msg, BusMsg::Ack { id: id_ack, ok: true });

        // o papel nomeia os clientes vivos
        let mut nomes = srv.clientes();
        nomes.sort();
        assert_eq!(nomes, vec!["craft-bar-rs".to_string(), "craft-dock-rs".to_string()]);

        // contadores vivos (o dump pergunta)
        let (lig, quadros) = srv.contadores();
        assert!(lig >= 2 && quadros >= 3, "contadores: {lig}/{quadros}");
        assert!(srv.path().ends_with("bus.sock"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn cliente_morre_e_o_broadcast_segue_para_os_vivos() {
        // a barra cai (relogin): EPIPE é evento; o broadcast seguinte
        // alcança quem ficou e a lista de vivos fala a verdade
        let dir = tmpdir("morte");
        let sock = dir.join("bus.sock");
        let (srv, rx_nucleo) = BusServer::start(&sock).unwrap();
        let (bar, rx_bar) = BusClient::connect(&sock, "bar").unwrap();
        {
            let (_dock, _rx) = BusClient::connect(&sock, "dock").unwrap();
            // os Hellos assentam no servidor ANTES do broadcast (o
            // registro é assíncrono: quem ainda não se apresentou ao
            // núcleo não está na lista — o contrato do fio vivo)
            let mut faltam = 2;
            while faltam > 0 {
                if let Ok(Incoming::Hello { .. }) = rx_nucleo.recv_timeout(Duration::from_secs(2)) {
                    faltam -= 1;
                }
            }
            srv.broadcast(&BusMsg::Workspace(crate::WorkspaceInfo {
                current: 1,
                count: 4,
                label: None,
            }));
            let _ = rx_bar.recv_timeout(Duration::from_secs(2)).unwrap();
            // a dock cai AQUI (o escopo fecha): o fio morre com ela
        }
        // deixa a morte assentar no leitor do servidor
        std::thread::sleep(Duration::from_millis(100));
        // o broadcast para os VIVOS segue limpo (a barra sobreviveu)
        srv.broadcast(&BusMsg::Window(WindowInfo {
            id: 1,
            app_id: "foot".into(),
            title: None,
            focused: false,
            minimized: false,
        }));
        assert!(rx_bar.recv_timeout(Duration::from_secs(2)).is_ok());
        let _ = bar; // a barra segue viva até aqui
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn o_anonimo_sem_hello_e_ignorado_sem_misterio() {
        // o contrato: o primeiro quadro é o Hello; quem fala outra
        // coisa primeiro não entra na lista (a porta não conversa com
        // anônimos) — o fio simplesmente não registra ninguém
        let dir = tmpdir("anonimo");
        let sock = dir.join("bus.sock");
        let (srv, rx_nucleo) = BusServer::start(&sock).unwrap();
        let mut s = crate::ipc::connect_bus(&sock).unwrap();
        send_frame(
            &mut s,
            &BusMsg::Req(BusReq::Activate { id: 99 }),
        )
        .unwrap();
        std::thread::sleep(Duration::from_millis(120));
        assert!(srv.clientes().is_empty(), "anônimo registrado!?");
        assert!(rx_nucleo.try_recv().is_err(), "pedido de anônimo aceito!?");
        // e o fio do anônimo morre sozinho (o servidor corta na 1ª msg)
        drop(s);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn cliente_reconecta_quando_o_daemon_renasce() {
        // A LIÇÃO E135: o daemon cai (relogin do bus), o cliente volta
        // com o MESMO canal para a UI — a reconexão é transparente para
        // quem drena o Receiver
        let dir = tmpdir("reconecta");
        let sock = dir.join("bus.sock");
        let (srv, rx1) = BusServer::start(&sock).unwrap();
        let (_bar, rx_bar) = BusClient::connect(&sock, "bar").unwrap();
        // o Hello assenta no servidor antes da 1ª publicação (o registro
        // é assíncrono — mesmo contrato dos outros testes)
        assert!(matches!(
            rx1.recv_timeout(Duration::from_secs(2)),
            Ok(Incoming::Hello { .. })
        ));
        srv.broadcast(&BusMsg::Workspace(crate::WorkspaceInfo {
            current: 2,
            count: 4,
            label: None,
        }));
        assert!(rx_bar.recv_timeout(Duration::from_secs(2)).is_ok());
        // o daemon MORRE: o servidor cai inteiro (threads e clientes)
        drop(srv);
        drop(rx1);
        std::thread::sleep(Duration::from_millis(150));
        // o daemon RENASCE no MESMO caminho
        let (srv2, rx2) = BusServer::start(&sock).unwrap();
        // o cliente reaparece sozinho (backoff ≤100ms) e o Hello chega
        let mut achou = false;
        for _ in 0..40 {
            if let Ok(Incoming::Hello { who, .. }) = rx2.try_recv() {
                assert_eq!(who, "bar");
                achou = true;
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        assert!(achou, "o cliente não reconectou no daemon novo");
        // e o broadcast do daemon novo alcança o cliente velho (mesmo
        // canal rx_bar — a UI nunca soube do intervalo)
        srv2.broadcast(&BusMsg::Media(crate::MediaState {
            player: None,
            title: None,
            artist: None,
            playing: false,
        }));
        assert!(rx_bar.recv_timeout(Duration::from_secs(2)).is_ok());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
