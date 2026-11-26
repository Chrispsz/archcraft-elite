// ELITE · elite-daemon — a varredura de /proc (E131→E132). Zero fork por
// tick: cada processo é read(2) de /proc/<pid>/comm, /exe, /cmdline e
// /environ — o bash pagava um pgrep + um readlink + um tr POR RODADA.
// A família é a MESMA do craft-game (o padrão ERE do comm, traduzido
// 1:1; a âncora ^…$ impede o falso casamento do corte a 15 chars) mais
// as portas que a E126/E132 acrescentaram:
//   PORTA 1 (E131) — a família ERE sobre o comm;
//   PORTA 2 (E126) — o exe de dentro de steamapps/common;
//   PORTA 3 (E132) — o cmdline com token .exe (case-insensitive) OU o
//     environ carregando as marcas dos runtimes (WINEPREFIX=,
//     STEAM_COMPAT_DATA_PATH=, UMU_ID=, PROTON_VERSION=) — o jogo do
//     Hydra via Proton GE que NENHUMA porta anterior via. Os
//     AUXILIARES do Wine (wineserver, services.exe, explorer.exe,
//     steamwebhelper, hydra-plus…) são BLOQUEADOS ANTES das sondas 2/3:
//     eles TAMBÉM carregam as marcas e o .exe — sem o filtro o modo de
//     jogo ligaria para o wineserver eternamente vivo (a lição E132 do
//     craft-game, traduzida 1:1).
use regex::Regex;
use std::io::Read;
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use zbus::blocking::Proxy;

/// A família ERE sobre o comm (o GAME_PATS do craft-game, 1:1).
/// E140 — O WINE64 ENTRA (a ordem do dono do dossiê 1.0-88: o
/// `wine64-preloader` era citado NOMINALMENTE como o invisível — a
/// porta do .exe cobria o jogo, mas o LOADER de 64 bits é família
/// também: o corte a 15 chars do kernel nunca esconde ele de novo).
pub const GAME_PATS: &str = r"^wine(64)?6?-preload(er)?$|^wine64-preloader$|^gamescope$|^pcsx2$|^retroarch$|^duckstation$|^dolphin-emu$|^melonds$|^citra-qt$|^ryujinx$|^PPSSPPSDL$|^rpcs3$|^osu!$|^Cemu$";
pub const STEAM_EXE_MARK: &str = "/steamapps/common/";
/// E134 — o BLOQUEIO dos AUXILIARES do runtime Proton/Wine/UMU (a ordem
/// do dono, dump 1.0-80 — menus.log: o Hydra roda jogos via
/// `umu-run → srt-bwrap → pv-adverb → proton → [helpers + o jogo]`).
/// TODOS os elos dessa corrente carregam as MESMAS marcas de environ
/// (WINEPREFIX, STEAM_COMPAT_DATA_PATH, UMU_ID…) — sem o bloqueio, o
/// modo de jogo ligaria para o LOADER eternamente vivo e nunca para o
/// jogo. A lista cobre: os helpers internos do Wine (wineserver,
/// services.exe, explorer.exe…), o runtime UMU/Proton (umu-run,
/// srt-bwrap, pv-adverb, proton, umu.exe, pressure-vessel, reaper),
/// o helper de acessibilidade xalia.exe e o launcher hydra-plus (o
/// CLIENTE da loja não é o jogo — o Stardew Valley.exe DEPOIS dele é).
pub const WINE_HELPER_PATS: &str = r"^(wineserver|services\.exe|winedevice\.exe|plugplay\.exe|explorer\.exe|rpcss\.exe|svchost\.exe|conhost\.exe|tabtip\.exe|rundll32\.exe|wineboot\.exe|mscorsvw\.exe|steamwebhelper|hydra-plus|umu-run|umu\.exe|srt-bwrap|pv-adverb|proton|pressure-vessel|reaper|xalia\.exe)";
/// E132→E134 — as marcas dos runtimes no environ (token INICIANDO com
/// a marca, KEY=VALUE NUL-separado). E134 soma SteamGameId (o Steam
/// próprio marca o jogo no ambiente — a porta que vê o jogo Steam
/// cujo exe não mora em steamapps/common, ex.: o compatdata dele).
pub const WINE_ENV_MARKS: [&str; 5] = [
    "WINEPREFIX=",
    "STEAM_COMPAT_DATA_PATH=",
    "UMU_ID=",
    "PROTON_VERSION=",
    "SteamGameId=",
];

pub struct Jogo {
    pub pid: i32,
    pub comm: String,
    pub exe: String,
    /// E132 — a porta que o viu ("comm" | "exe" | "cmdline" | "environ"
    /// — o papel do daemon nomeia o porquê de cada registro).
    pub via: &'static str,
}

fn read_trim(p: &Path) -> Option<String> {
    let mut s = String::new();
    std::fs::File::open(p)
        .ok()?
        .read_to_string(&mut s)
        .ok()?;
    Some(s.trim_end().to_string())
}

/// Lê um arquivo de /proc com bytes crus (cmdline/environ são
/// NUL-separados e NÃO são UTF-8 válido — read_to_string morreria).
fn read_bytes(p: &Path) -> Option<Vec<u8>> {
    let mut buf = Vec::new();
    std::fs::File::open(p)
        .ok()?
        .read_to_end(&mut buf)
        .ok()?;
    Some(buf)
}

/// E132 — o bloqueio dos auxiliares do Wine (comm ancorado). Eles
/// carregam as MESMAS marcas de environ/cmdline que o jogo — sem o
/// filtro o modo de jogo ligaria para o wineserver eternamente vivo.
pub fn eh_auxiliar_wine(comm: &str, re: &Regex) -> bool {
    re.is_match(comm)
}

/// E132 — a PORTA 3a: QUALQUER token NUL-separado do cmdline terminando
/// em ".exe" (case-insensitive — o argv[0] do jogo é o próprio .exe; no
/// loader 'wine jogo.exe' é o argv[1]; as duas formas são o jogo).
pub fn cmdline_tem_exe(cmd: &[u8]) -> bool {
    cmd.split(|&b| b == 0).any(tem_sufixo_exe)
}

/// o sufixo ".exe" em bytes, sem caixa (o grep -Ei do bash casa .EXE).
fn tem_sufixo_exe(tok: &[u8]) -> bool {
    tok.len() >= 4
        && tok[tok.len() - 4..].eq_ignore_ascii_case(b".exe")
}

/// E132 — a PORTA 3b: QUALQUER token NUL-separado do environ INICIANDO
/// com uma marca de runtime (WINEPREFIX=, STEAM_COMPAT_DATA_PATH=,
/// UMU_ID=, PROTON_VERSION=, SteamGameId= — o molde do grep -Eq
/// "^($MARKS)" do bash).
pub fn environ_tem_marca(env: &[u8]) -> bool {
    env.split(|&b| b == 0)
        .any(|tok| WINE_ENV_MARKS.iter().any(|m| tok.starts_with(m.as_bytes())))
}

/// E134 — a PORTA do cmdline STEAM: QUALQUER token NUL-separado do
/// cmdline CONTENDO "/steamapps/common/" (o jogo lançado pelo Steam
/// que aponta o argv para lá — o exe link cobre o mesmo caminho, mas
/// o argv de launchers/scripts às vezes carrega o caminho sem ser o
/// /proc/<pid>/exe dele).
pub fn cmdline_tem_steam(cmd: &[u8]) -> bool {
    cmd.split(|&b| b == 0)
        .any(|tok| tok.windows(STEAM_EXE_MARK.len()).any(|w| w == STEAM_EXE_MARK.as_bytes()))
}

/// E140 — PORTA 5 — o app_id de JANELA é jogo? O padrão do Steam
/// através do Proton (a prova do dossiê: a janela `steam_app_413150`
/// do Stardew Valley via Hydra que o watcher antigo ignorava): o
/// prefixo `steam_app_` seguido de AO MENOS UM DÍGITO. Estrito por
/// desenho — app_id genérico NÃO é jogo (o brave não é, o foot não
/// é; só a convenção do Steam conta).
pub fn eh_app_janela_jogo(app_id: &str) -> bool {
    let Some(resto) = app_id.strip_prefix("steam_app_") else {
        return false;
    };
    !resto.is_empty() && resto.bytes().all(|b| b.is_ascii_digit())
}

/// UMA rodada: os jogos vivos do usuário corrente.
pub fn round() -> Vec<Jogo> {
    let uid = unsafe { libc::getuid() };
    let re = Regex::new(GAME_PATS).expect("GAME_PATS é ERE constante válida");
    let re_helper = Regex::new(WINE_HELPER_PATS).expect("WINE_HELPER_PATS é ERE constante válida");
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
        out.push(Jogo { pid, comm, exe, via: "comm" });
    }

    // PORTAS 2+3 (E126→E132) numa SÓ passada de /proc: o exe dentro de
    // steamapps/common (o jogo Steam que o comm nunca nomeia) e a sonda
    // cmdline/environ dos runtimes Proton/Wine/Hydra/UMU. O BLOQUEIO dos
    // auxiliares vem ANTES de qualquer sonda (eles carregam as mesmas
    // marcas — o molde E132 do craft-game, 1:1).
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
        let comm = read_trim(&base.join("comm")).unwrap_or_default();
        if comm.is_empty() || eh_auxiliar_wine(&comm, &re_helper) {
            continue; // auxiliar do Wine: as marcas dele NÃO são jogo
        }
        let exe = std::fs::read_link(base.join("exe"))
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default();
        if exe.contains(STEAM_EXE_MARK) {
            out.push(Jogo { pid, comm, exe, via: "exe" });
            continue;
        }
        if let Some(cmd) = read_bytes(&base.join("cmdline")) {
            if cmdline_tem_exe(&cmd) || cmdline_tem_steam(&cmd) {
                out.push(Jogo { pid, comm, exe, via: "cmdline" });
                continue;
            }
        }
        if let Some(env) = read_bytes(&base.join("environ")) {
            if environ_tem_marca(&env) {
                out.push(Jogo { pid, comm, exe, via: "environ" });
            }
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
            "wine64-preloader", // E140 — a ordem nominal do dossiê: o loader de 64 é família
            "wine64-preload",
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

    // ── E132 — o bloqueio dos auxiliares + as portas cmdline/environ ────

    #[test]
    fn bloqueio_casa_os_auxiliares_do_wine() {
        let re = Regex::new(WINE_HELPER_PATS).unwrap();
        // a lista do craft-game E132, 1:1 — os auxiliares que carregam as
        // MESMAS marcas de environ/cmdline que o jogo
        // E134 — a CORTE REAL do dump 1.0-80 (menus.log): o runtime
        // UMU/Proton inteiro entra no bloqueio (umu-run, srt-bwrap,
        // pv-adverb, proton, umu.exe, pressure-vessel, reaper, xalia.exe)
        for aux in [
            "wineserver",
            "services.exe",
            "winedevice.exe",
            "plugplay.exe",
            "explorer.exe",
            "rpcss.exe",
            "svchost.exe",
            "conhost.exe",
            "tabtip.exe",
            "rundll32.exe",
            "wineboot.exe",
            "mscorsvw.exe",
            "steamwebhelper",
            "hydra-plus",
            "umu-run",
            "umu.exe",
            "srt-bwrap",
            "pv-adverb",
            "proton",
            "pressure-vessel",
            "reaper",
            "xalia.exe",
        ] {
            assert!(eh_auxiliar_wine(aux, &re), "deveria bloquear: {}", aux);
        }
        // o jogo de verdade NUNCA cai no bloqueio (a âncora ^ segura)
        for vivo in [
            "wine-preloader",
            "gamescope",
            "Stardew Valley", // o comm DO .exe que a porta 3 caça
            "hydra",           // sem o sufixo -plus é OUTRO corpo
            "pcsx2",
            "stardew valley.", // o comm real do dump: minúsculo com o ponto final
        ] {
            assert!(!eh_auxiliar_wine(vivo, &re), "não deveria bloquear: {}", vivo);
        }
    }

    #[test]
    fn cmdline_casa_qualquer_token_exe_sem_caixa() {
        // o argv[0] do jogo É o .exe
        assert!(cmdline_tem_exe(b"/home/user/Stardew Valley.exe\0--flag\0"));
        // o loader: 'wine jogo.exe' — o .exe é o argv[1]
        assert!(cmdline_tem_exe(b"wine\0jogo.exe\0"));
        // sem caixa (o grep -Ei do bash casa .EXE também)
        assert!(cmdline_tem_exe(b"wine\0JOGO.EXE\0"));
        // NUL separa tokens: um .exe NO MEIO de token não é fim de token
        assert!(!cmdline_tem_exe(b"jogo.exe.bak\0wine\0"));
        // nenhum token termina em .exe
        assert!(!cmdline_tem_exe(b"/usr/bin/wine\0preload\0"));
        // E134 — a porta cmdline do Steam: o token COM steamapps/common
        assert!(cmdline_tem_steam(
            b"sh\0/home/user/.steam/steam/steamapps/common/Stardew Valley/run.sh\0"
        ));
        assert!(!cmdline_tem_steam(b"/usr/bin/foot\0-c\0steam\0"));
        // cmdline vazio/so-NUL: resposta honesta é false
        assert!(!cmdline_tem_exe(b""));
        assert!(!cmdline_tem_exe(b"\0\0"));
    }

    #[test]
    fn environ_casa_as_marcas_dos_runtimes() {
        // as 4 marcas da E132 (o jogo do Hydra via Proton GE)
        assert!(environ_tem_marca(b"PATH=/usr/bin\0WINEPREFIX=/home/user/.wine\0"));
        assert!(environ_tem_marca(
            b"STEAM_COMPAT_DATA_PATH=/home/user/.steam/steam/steamapps/compatdata/413150\0"
        ));
        assert!(environ_tem_marca(b"UMU_ID=stardewvalley\0"));
        assert!(environ_tem_marca(b"PROTON_VERSION=GE-Proton9-27\0"));
        // E134 — a marca do Steam próprio (o jogo Steam fora do steamapps/common do exe)
        assert!(environ_tem_marca(b"SteamGameId=413150\0"));
        // a marca tem que ser PREFIXO do token (KEY=VALUE, o molde ^$
        // do grep do bash — 'WINEPREFIXX=' NÃO é WINEPREFIX=)
        assert!(!environ_tem_marca(b"WINEPREFIXX=/outra\0"));
        assert!(!environ_tem_marca(b"PATH=/usr/bin\0HOME=/home/user\0"));
        // environ vazio: sem marcas, sem jogo
        assert!(!environ_tem_marca(b""));
        assert!(!environ_tem_marca(b"\0\0"));
    }

    #[test]
    fn round_nunca_panica_sem_permissao() {
        // a porta dos testes: a varredura roda em ambiente sem jogos —
        // 0 achados é a resposta honesta, não um crash.
        let _ = round();
    }

    // ── E140 — PORTA 5: a janela steam_app_* é a prova ────────────────

    #[test]
    fn a_janela_steam_app_e_jogo_a_prova_do_dossie() {
        // o caso NOMINAL do dossiê 1.0-88: o Stardew Valley do Hydra
        assert!(eh_app_janela_jogo("steam_app_413150"));
        // outros app_ids Steam
        assert!(eh_app_janela_jogo("steam_app_730"));
        assert!(eh_app_janela_jogo("steam_app_0"));
        // o falso MAIS PERIGOSO: o prefixo sem o dígito (app de outro)
        assert!(!eh_app_janela_jogo("steam_app_"));
        // apps comuns da sessão NÃO são jogo (o padrão é ESTRITO)
        assert!(!eh_app_janela_jogo("brave-browser"));
        assert!(!eh_app_janela_jogo("foot"));
        assert!(!eh_app_janela_jogo("steam"));
        assert!(!eh_app_janela_jogo("steamapp_123"));
        assert!(!eh_app_janela_jogo("steam_app_413150b")); // dígito no MEIO não: TODO o resto é dígito
        assert!(!eh_app_janela_jogo(""));
        assert!(!eh_app_janela_jogo("STEAM_APP_413150")); // maiúsculo não é a convenção
    }
}
