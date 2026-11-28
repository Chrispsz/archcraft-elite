// ═════════════════════════════════════════════════════════════════════════
// elite-core::persist — a persistência ATÔMICA da casa (2.0)
// ═════════════════════════════════════════════════════════════════════════
// Toda escrita de estado do dono cruza ESTA função: tmp na MESMA pasta +
// fsync + rename. O crash no meio da escrita nunca corrompe o arquivo
// (o rename é atômico no mesmo filesystem — a lei da dock v2 dos pins,
// agora contrato de todos os papéis em ~/.config/elite/).
// ═════════════════════════════════════════════════════════════════════════

use std::collections::HashMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

/// A morada do estado do dono: `~/.config/elite/` (XDG_CONFIG_HOME honrado).
pub fn elite_config_dir() -> PathBuf {
    let base = std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_else(|_| "/root".into());
            PathBuf::from(home).join(".config")
        });
    base.join("elite")
}

/// Escreve `bytes` em `path` de forma ATÔMICA (tmp+fsync+rename).
/// Cria a pasta pai se ausente. O `.tmp` mora NO MESMO diretório (rename
/// cross-filesystem não é atômico — a lição do mv entre fs da casa).
/// 1.0-110 T5 — A GUARDA DE SEQUÊNCIA (a corrida das escritas: duas
/// threads escrevem o MESMO path — last-net.state da fundação e os
/// pins da dock — e a ESCRETA ATRASADA chegava DEPOIS da mais nova e o
/// rename dela ENTERRAVA o estado novo com o velho; o write de era só
/// era atômico por ESCRITA, nunca por ORDEM). Toda escrita RESERVA um
/// número da sequência global e o sufixo único do tmp é o número DELA;
/// antes do rename, quem chega ATRASADA (uma reserva mais nova para o
/// MESMO path já existe) é DESCARTADA — o tmp sai do chão e a última
/// escrita vence SEMPRE, em qualquer ordem de conclusão.
pub fn write_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let minha = reserva(path);
    write_atomic_seq(path, bytes, minha)
}

/// 1.0-110 T5 — o contador global das escritas (o sufixo único do tmp
/// é o número da reserva — tmp órfão de escritas descartadas nunca
/// colide com o da próxima).
static SEQUENCIA: AtomicU64 = AtomicU64::new(0);

/// 1.0-110 T5 — a ÚLTIMA reserva por path (a escrita que reserva DEPOIS
/// supersede a anterior do MESMO path — ver write_atomic_seq).
static ULTIMA: Mutex<Option<HashMap<PathBuf, u64>>> = Mutex::new(None);

/// reserva o número da sequência e registra a reserva MAIS NOVA do path.
fn reserva(path: &Path) -> u64 {
    let n = SEQUENCIA.fetch_add(1, Ordering::SeqCst);
    ULTIMA
        .lock()
        .unwrap()
        .get_or_insert_with(HashMap::new)
        .insert(path.to_path_buf(), n);
    n
}

/// o corpo da escrita com a reserva na mão (a porta dos testes: a
/// corrida é INJETADA — duas reservas, a atrasada escreve DEPOIS e é
/// descartada na cara do rename).
fn write_atomic_seq(path: &Path, bytes: &[u8], minha: u64) -> std::io::Result<()> {
    let dir = path
        .parent()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidInput, "caminho sem pasta pai"))?;
    std::fs::create_dir_all(dir)?;
    let tmp = dir.join(format!(
        ".{}.tmp-{}-{}",
        path.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("elite"),
        std::process::id(),
        minha
    ));
    {
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(bytes)?;
        f.sync_all()?;
    }
    // A GUARDA: uma reserva mais nova do MESMO path já existe — a
    // escrita daqui é ATRASADA (a mais nova vence) e é DESCARTADA com
    // o tmp fora do chão (o estado novo nunca é enterrado pelo velho)
    let superseded = {
        let ultima = ULTIMA.lock().unwrap();
        match ultima.as_ref().and_then(|m| m.get(path)) {
            Some(&n) => n != minha,
            None => false,
        }
    };
    if superseded {
        let _ = std::fs::remove_file(&tmp);
        return Ok(()); // a escrita mais NOVA vence (descartada, não falha)
    }
    std::fs::rename(&tmp, path)?;
    Ok(())
}

/// Lê o arquivo (None = ainda não existe — estado legítimo, não erro).
pub fn read_if_exists(path: &Path) -> Option<Vec<u8>> {
    std::fs::read(path).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn workdir(nome: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "elite-persist-{nome}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn escrita_atomica_nasce_lida_igual() {
        let dir = workdir("nasce");
        let p = dir.join("dock-pins");
        write_atomic(&p, b"gearlever_Hydra\n").unwrap();
        assert_eq!(read_if_exists(&p).unwrap(), b"gearlever_Hydra\n");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn reescrita_nao_deixa_tmp_para_tras() {
        let dir = workdir("tmp");
        let p = dir.join("dock-pins");
        write_atomic(&p, b"a\n").unwrap();
        write_atomic(&p, b"b\n").unwrap();
        assert_eq!(read_if_exists(&p).unwrap(), b"b\n");
        let lixo: Vec<_> = std::fs::read_dir(&dir)
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().contains(".tmp"))
            .collect();
        assert!(lixo.is_empty(), "tmp órfão: {lixo:?}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn pasta_pai_e_criada_sem_choro() {
        let dir = workdir("pai");
        let p = dir.join("fundo").join("mais-fundo").join("estado.json");
        write_atomic(&p, b"{}").unwrap();
        assert!(p.exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn leitura_do_inexistente_e_estado_legitimo() {
        assert!(read_if_exists(Path::new("/tmp/elite-persist-inexistente-definitiva")).is_none());
    }

    // ── 1.0-110 T5 — A GUARDA DE SEQUÊNCIA ─────────────────────────────

    #[test]
    fn a_escrita_atrasada_e_descartada_na_cara_do_rename() {
        // A CORRIDA INJETADA: a escrita VELHA é reservada primeiro,
        // a NOVA reserva DEPOIS (e supersede), a VELHA só CONCLUI depois
        // — de era o rename dela ENTERRAVA o estado novo (a corrida do
        // last-net.state com os pins da dock)
        let dir = workdir("guarda");
        let p = dir.join("last-net.state");
        let velha = reserva(&p);
        let nova = reserva(&p);
        assert!(nova > velha, "a reserva é CRESCENTE (o número do tmp é único)");
        // a VELHA conclui DEPOIS da nova reservar: DESCARTADA
        write_atomic_seq(&p, b"estado-velho\n", velha).unwrap();
        assert_eq!(read_if_exists(&p), None, "a atrasada NÃO passou do rename");
        // a NOVA conclui e vence
        write_atomic_seq(&p, b"estado-novo\n", nova).unwrap();
        assert_eq!(read_if_exists(&p).unwrap(), b"estado-novo\n");
        // e o tmp da descartada saiu do chão (o sufixo único nunca deixa
        // lixo — o próximo writeAtomic não colide com o órfão)
        let lixo: Vec<_> = std::fs::read_dir(&dir)
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().contains(".tmp"))
            .collect();
        assert!(lixo.is_empty(), "tmp órfão da descartada: {lixo:?}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn escritas_sequenciais_segues_com_a_ultima_vencendo() {
        // sem corrida nenhuma, o contrato de SEMPRE segue: escrever 2× é
        // a última vencendo (a guarda só julga a ATRASADA, nunca a fila
        // ordeira — path diferente NÃO supersede path diferente)
        let dir = workdir("fila");
        let p1 = dir.join("pins");
        let p2 = dir.join("last-net.state");
        write_atomic(&p1, b"a\n").unwrap();
        write_atomic(&p2, b"b\n").unwrap(); // path DIFERENTE não descarta o p1
        write_atomic(&p1, b"c\n").unwrap(); // a última do MESMO path vence
        assert_eq!(read_if_exists(&p1).unwrap(), b"c\n");
        assert_eq!(read_if_exists(&p2).unwrap(), b"b\n");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
