// ═════════════════════════════════════════════════════════════════════════
// elite-core::persist — a persistência ATÔMICA da casa (2.0)
// ═════════════════════════════════════════════════════════════════════════
// Toda escrita de estado do dono cruza ESTA função: tmp na MESMA pasta +
// fsync + rename. O crash no meio da escrita nunca corrompe o arquivo
// (o rename é atômico no mesmo filesystem — a lei da dock v2 dos pins,
// agora contrato de todos os papéis em ~/.config/elite/).
// ═════════════════════════════════════════════════════════════════════════

use std::io::Write;
use std::path::{Path, PathBuf};

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
pub fn write_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let dir = path
        .parent()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidInput, "caminho sem pasta pai"))?;
    std::fs::create_dir_all(dir)?;
    let tmp = dir.join(format!(
        ".{}.tmp-{}",
        path.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("elite"),
        std::process::id()
    ));
    {
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(bytes)?;
        f.sync_all()?;
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
}
