// ELITE · elite-daemon — a varredura de /proc (E131). Zero fork por
// tick: cada processo é read(2) de /proc/<pid>/comm e /proc/<pid>/exe —
// o bash pagava um pgrep + um readlink POR RODADA (fork ×2 no mínimo).
// A família é a MESMA do craft-game (o padrão ERE do comm, traduzido
// 1:1; a âncora ^…$ impede o falso casamento do corte a 15 chars) mais
// a SEGUNDA PORTA: o exe de dentro de steamapps/common (o jogo Steam —
// nativo ou Proton — que o comm nunca nomeia).
use regex::Regex;
use std::io::Read;
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use zbus::blocking::Proxy;

/// A família ERE sobre o comm (o GAME_PATS do craft-game, 1:1).
pub const GAME_PATS: &str = r"^wine6?-preload(er)?$|^gamescope$|^pcsx2$|^retroarch$|^duckstation$|^dolphin-emu$|^melonds$|^citra-qt$|^ryujinx$|^PPSSPPSDL$|^rpcs3$|^osu!$|^Cemu$";
pub const STEAM_EXE_MARK: &str = "/steamapps/common/";

pub struct Jogo {
    pub pid: i32,
    pub comm: String,
    pub exe: String,
}

fn read_trim(p: &Path) -> Option<String> {
    let mut s = String::new();
    std::fs::File::open(p)
        .ok()?
        .read_to_string(&mut s)
        .ok()?;
    Some(s.trim_end().to_string())
}

/// UMA rodada: os jogos vivos do usuário corrente.
pub fn round() -> Vec<Jogo> {
    let uid = unsafe { libc::getuid() };
    let re = Regex::new(GAME_PATS).expect("GAME_PATS é ERE constante válida");
    let mut out = Vec::new();
    let dir = match std::fs::read_dir("/proc") {
        Ok(d) => d,
        Err(_) => return out,
    };
    let entries: Vec<std::fs::DirEntry> = dir.flatten().collect();

    // PORTA 1: a família ERE sobre o comm (pgrep -u $uid SEM -x era o bash)
    for entry in &entries {
        let fname = entry.file_name();
        let Some(name) = fname.to_str() else { continue };
        let Ok(pid) = name.parse::<i32>() else { continue };
        let base = Path::new("/proc").join(name);
        let Some(meta) = std::fs::metadata(base.join("stat")).ok() else { continue };
        if meta.uid() != uid {
            continue;
        }
        let Some(comm) = read_trim(&base.join("comm")) else { continue };
        if !re.is_match(&comm) {
            continue;
        }
        let exe = std::fs::read_link(base.join("exe"))
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default();
        out.push(Jogo { pid, comm, exe });
    }

    // PORTA 2 (E126): o jogo Steam pelo CAMINHO do exe — inclui quem o
    // comm nunca nomeia ('Stardew Valley' via Proton).
    for entry in &entries {
        let fname = entry.file_name();
        let Some(name) = fname.to_str() else { continue };
        let Ok(pid) = name.parse::<i32>() else { continue };
        if out.iter().any(|j| j.pid == pid) {
            continue;
        }
        let base = Path::new("/proc").join(name);
        let Some(meta) = std::fs::metadata(base.join("stat")).ok() else { continue };
        if meta.uid() != uid {
            continue;
        }
        let exe = match std::fs::read_link(base.join("exe")) {
            Ok(p) => p.to_string_lossy().into_owned(),
            Err(_) => continue,
        };
        if exe.contains(STEAM_EXE_MARK) {
            let comm = read_trim(&base.join("comm")).unwrap_or_default();
            out.push(Jogo { pid, comm, exe });
        }
    }
    out.sort_by_key(|j| j.pid);
    out
}

// ── o cliente GameMode (D-Bus NATIVO — zbus blocking) ────────────────────
// A conexão é PERSISTENTE (o bash abria dbus-send por chamada — um fork
// por registro e um por status, cinco vezes mais caro que o daemon vivo).
pub type GmConn = Option<zbus::blocking::Connection>;

pub fn gm_connect() -> GmConn {
    zbus::blocking::Connection::system().ok()
}

fn gm_proxy(c: &zbus::blocking::Connection) -> zbus::Result<Proxy<'_>> {
    Proxy::new(
        c,
        "com.feralinteractive.GameMode",
        "/com/feralinteractive/GameMode",
        "com.feralinteractive.GameMode",
    )
}

pub fn gm_register(conn: &GmConn, pid: i32) -> bool {
    let Some(c) = conn.as_ref() else { return false };
    let Ok(p) = gm_proxy(c) else { return false };
    let body = (pid, pid, 0i32);
    matches!(p.call::<_, _, i32>("RegisterGame", &body), Ok(1))
}

pub fn gm_unregister(conn: &GmConn, pid: i32) {
    if let Some(c) = conn.as_ref() {
        if let Ok(p) = gm_proxy(c) {
            let body = (pid, pid, 0i32);
            let _ = p.call::<_, _, i32>("UnregisterGame", &body);
        }
    }
}

pub fn gm_status(conn: &GmConn) -> i32 {
    let Some(c) = conn.as_ref() else { return 0 };
    let Ok(p) = gm_proxy(c) else { return 0 };
    let body = (std::process::id() as i32, std::process::id() as i32, 0i32);
    p.call::<_, _, i32>("QueryStatus", &body).unwrap_or(0)
}

pub fn gm_quit(conn: &GmConn) {
    if let Some(c) = conn.as_ref() {
        if let Ok(p) = gm_proxy(c) {
            let _: Result<(), _> = p.call_noreply("QuitGameMode", &());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn familia_casa_os_comms_da_casa() {
        let re = Regex::new(GAME_PATS).unwrap();
        // os CASOS que a era E106/E126 provou (o corte de 15 chars incluído)
        for vivo in [
            "wine-preloader",
            "wine6-preloader", // a porta ERE cobre o wine6 (o wine64 só pela porta do exe)
            "gamescope",
            "pcsx2",
            "retroarch",
            "dolphin-emu",
            "PPSSPPSDL",
            "Cemu",
        ] {
            assert!(re.is_match(vivo), "deveria casar: {}", vivo);
        }
        // os FALSOS que a âncora impede
        for morto in ["gamescope-helper", "steamwebhelper", "craft-game", "systemd"] {
            assert!(!re.is_match(morto), "não deveria casar: {}", morto);
        }
    }

    #[test]
    fn steam_exe_mark_e_o_molde_da_segunda_porta() {
        assert!(
            "/home/user/.steam/steam/steamapps/common/Stardew Valley/Stardew Valley.exe"
                .contains(STEAM_EXE_MARK)
        );
        assert!(!"/usr/bin/steam".contains(STEAM_EXE_MARK));
    }

    #[test]
    fn round_nunca_panica_sem_permissao() {
        // a porta dos testes: a varredura roda em ambiente sem jogos —
        // 0 achados é a resposta honesta, não um crash.
        let _ = round();
    }
}
