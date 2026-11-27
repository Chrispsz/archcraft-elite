// ELITE · elite-daemon — doctor.rs (1.0-107.2) — O DIAGNÓSTICO EM 1 COMANDO
// ═════════════════════════════════════════════════════════════════════════
// A diretriz do ciclo ("Inovação Fora da Caixa, Alto Valor, Zero Bloat"):
// uma ferramenta de verificação rápida que inspeciona e valida TODOS os
// invariantes vitais da máquina real — o dono aperta um comando e SABE se
// a sessão está inteira, sem varrer logs a olho.
//
// AS LEIS DO DESENHO:
//   · ZERO OVERHEAD EM IDLE — o doctor NÃO mora em nenhum loop: é um
//     processo de 1 tiro que nasce, julga e MORRE (a sessão não carrega
//     um único byte a mais por causa dele);
//   · <50ms de execução no caminho feliz: D-Bus persistente do zbus
//     (zero dbus-send fork), handshake do bus.sock com teto da casa
//     (IPC_CONNECT_TETO_MS), leitura DIRETA de /proc e /sys (a escola
//     do sinal_para_comms — nenhum pgrep), e o pactl SÓ quando o
//     socket do PipeWire existe no chão (um stat decide antes do fork);
//   · as duas portas: `elite-daemon doctor` e o elo `craft-doctor`
//     (mesmo binário, o argv0 decide — um symlink no pacote, zero
//     arquivo duplicado viajando);
//   · o juízo é PURO onde dá (julga_wakeup/relatório testam sem kernel;
//     as sonda de verdade só montam o Diag e reusam o mesmo render).
//
// O QUE JULGA (os invariantes vitais da casa):
//   1. o AMBIENTE WAYLAND no D-Bus (dbus-update-activation-environment —
//      WAYLAND_DISPLAY/XDG_CURRENT_DESKTOP no systemd do usuário);
//   2. o bus.sock VIVO (handshake Hello → o snapshot de boas-vindas);
//   3. o AGENTE POLKIT ativo (lxqt-policykit-agent com o polkit-gnome de
//      queda — a leitura de /proc/<pid>/comm, sem fork);
//   4. o DONO ÚNICO das notificações (org.freedesktop.Notifications com
//      dono no session bus — o swaync supervisionado da 1.0-107);
//   5. a TABELA /proc/acpi/wakeup (a família espúria dormindo, a mão do
//      dono — PWRB/SLPB/PBTN/PS2K/LID — armada);
//   6. a SAÍDA PADRÃO do PipeWire (o socket no chão + o default NUNCA
//      auto_null — o sequestro do monitor é doença nomeada);
//   7. o GAMEMODE (informativo: o gamemoded é sob demanda — o estado é
//      a notícia, não o veredito).
use std::collections::HashMap;
use std::io::Write;
use std::path::PathBuf;

use elite_core::ipc::{connect_bus, recv_frame, send_frame};
use elite_core::{bus_sock_path, BusMsg};

/// um veredito do doctor: ok, o nome do invariante e a nota honesta.
pub struct Diag {
    pub nome: &'static str,
    pub ok: bool,
    pub nota: String,
}

/// a família espúria da casa (a MESMA do elite-acpi-wakeup — uma lei só).
fn wakeup_espurio(nome: &str) -> bool {
    let bytes = nome.as_bytes();
    let casa = |p: &str| nome.starts_with(p);
    casa("XHC")
        || casa("PTXH")
        || casa("GPP")
        || (bytes.len() >= 2
            && bytes[0] == b'G'
            && bytes[1] == b'P'
            && bytes[2..].first().is_some_and(u8::is_ascii_digit))
        || (casa("X1")
            && bytes.len() > 2
            && (bytes[2].is_ascii_digit() || bytes[2] == b'_'))
}

/// a mão do dono (o allowlist universal da 1.0-107.2).
fn wakeup_mao(nome: &str) -> bool {
    matches!(nome, "PWRB" | "SLPB" | "PBTN" | "PS2K" | "LID")
}

/// O JULGO DA TABELA (PURO — a sonda de teste alimenta tabela de mentira):
/// devolve (gatilhos espúrios ARMADOS, nomes da mão do dono DORMINDO) —
/// ambos vazios é a saúde da casa.
pub fn julga_wakeup(tabela: &str) -> (Vec<String>, Vec<String>) {
    let mut espurios = Vec::new();
    let mut mao = Vec::new();
    for linha in tabela.lines() {
        let campos: Vec<&str> = linha.split_whitespace().collect();
        // a gramática do /proc/acpi/wakeup: Name S-state Status Sysfs
        // (o status é o 3º campo — o 2º é o S-state do sono)
        let &[nome, _s_state, estado, ..] = campos.as_slice() else {
            continue;
        };
        let enabled = estado == "*enabled";
        if enabled && wakeup_espurio(nome) {
            espurios.push(nome.to_string());
        }
        if !enabled && wakeup_mao(nome) {
            mao.push(nome.to_string());
        }
    }
    (espurios, mao)
}

/// O RELATÓRIO (PURO): render alinhado + o código de saída (0 = saúde
/// inteira, 1 = invariante quebrado — o dono vê O réu, não um dump).
pub fn relatorio(diags: &[Diag]) -> (String, i32) {
    let mut saida = String::from("── craft-doctor · os invariantes vitais da sessão ──\n");
    let mut falhas = 0usize;
    for d in diags {
        let sim = if d.ok { "✓" } else { "✗" };
        saida.push_str(&format!("  {sim} {:<12} {}\n", d.nome, d.nota));
        if !d.ok {
            falhas += 1;
        }
    }
    if falhas == 0 {
        saida.push_str("── saúde INTEIRA: os 6 invariantes vitais no ar ──\n");
    } else {
        saida.push_str(&format!("── {falhas} invariante(s) QUEBRADO(S): o réu está nomeado acima ──\n"));
    }
    (saida, i32::from(falhas > 0))
}

// ── as sondas (cada uma monta UM Diag; nenhuma panica — o honesto fala) ──

/// (1) o ambiente Wayland no D-Bus: o dbus-update-activation-environment
/// do autostart é o PRIMEIRO invariante da 1.0-107 — sem ele o systemd do
/// usuário nasce cego (swaync/polkit sem WAYLAND_DISPLAY).
fn diag_dbus_env(conn: &Option<zbus::blocking::Connection>) -> Diag {
    let Some(c) = conn.as_ref() else {
        return Diag {
            nome: "ambiente",
            ok: false,
            nota: "sem session bus (a sessão não existe aqui?)".into(),
        };
    };
    let Ok(p) = zbus::blocking::Proxy::new(
        c,
        "org.freedesktop.systemd1",
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
    ) else {
        return Diag { nome: "ambiente", ok: false, nota: "o systemd do usuário não atende".into() };
    };
    let Ok(env) = p.call::<_, _, HashMap<String, String>>("GetEnvironment", &()) else {
        return Diag { nome: "ambiente", ok: false, nota: "GetEnvironment recusado".into() };
    };
    let wl = env.get("WAYLAND_DISPLAY").map(String::as_str).unwrap_or("");
    let desk = env.get("XDG_CURRENT_DESKTOP").map(String::as_str).unwrap_or("");
    if !wl.is_empty() && !desk.is_empty() {
        Diag { nome: "ambiente", ok: true, nota: format!("WAYLAND_DISPLAY={wl} no D-Bus (desktop: {desk})") }
    } else {
        Diag {
            nome: "ambiente",
            ok: false,
            nota: "WAYLAND_DISPLAY/XDG_CURRENT_DESKTOP AUSENTES no D-Bus (o dbus-update-activation-environment do autostart não vestiu)".into(),
        }
    }
}

/// (2) o bus.sock VIVO: o handshake da casa (Hello → o snapshot de
/// boas-vindas responde) com o teto da fundação — sem thread, o doctor
/// é 1 tiro: conecta, fala, OUVE e derruba o fio.
fn diag_bus_sock() -> Diag {
    let uid = unsafe { libc::getuid() };
    let caminho = bus_sock_path(uid);
    let Some(mut s) = connect_bus(&caminho) else {
        return Diag {
            nome: "bus.sock",
            ok: false,
            nota: format!("{} não conecta (o elite-daemon session morreu?)", caminho.display()),
        };
    };
    let _ = s.set_read_timeout(Some(std::time::Duration::from_millis(elite_core::IPC_CONNECT_TETO_MS)));
    if send_frame(&mut s, &BusMsg::Hello { who: "craft-doctor".into() }).is_err() {
        return Diag { nome: "bus.sock", ok: false, nota: "o Hello não atravessou".into() };
    }
    match recv_frame(&mut s) {
        Ok(Some(_)) => Diag {
            nome: "bus.sock",
            ok: true,
            nota: "handshake vivo (o snapshot de boas-vindas respondeu)".into(),
        },
        _ => Diag {
            nome: "bus.sock",
            ok: false,
            nota: "o bus aceita o Hello mas o snapshot não volta (fio surdo)".into(),
        },
    }
}

/// (3) o agente Polkit: a leitura de /proc/<pid>/comm (zero fork — a
/// escola do sinal_para_comms); o lxqt da casa com o polkit-gnome de
/// queda — SEM agente, o pkexec do usuário não tem cara.
fn diag_polkit() -> Diag {
    let uid = unsafe { libc::getuid() };
    let mut achado = "";
    if let Ok(dir) = std::fs::read_dir("/proc") {
        for e in dir.flatten() {
            let Some(pid) = e.file_name().to_str().and_then(|s| s.parse::<u32>().ok()) else {
                continue;
            };
            let Ok(status) = std::fs::read_to_string(format!("/proc/{pid}/status")) else { continue };
            // o dono do agente é o usuário da sessão (Uid: no topo)
            let uid_linha = status.lines().find(|l| l.starts_with("Uid:"));
            let dono = uid_linha
                .and_then(|l| l.split_whitespace().nth(1))
                .and_then(|v| v.parse::<u32>().ok())
                .unwrap_or(u32::MAX);
            if dono != uid {
                continue;
            }
            let Ok(comm) = std::fs::read_to_string(format!("/proc/{pid}/comm")) else { continue };
            let comm = comm.trim();
            if comm.starts_with("lxqt-policykit-") {
                achado = "lxqt-policykit-agent";
                break;
            }
            if comm.starts_with("polkit-gnome-") {
                achado = "polkit-gnome-authentication-agent-1";
                break;
            }
        }
    }
    if achado.is_empty() {
        Diag { nome: "polkit", ok: false, nota: "NENHUM agente ativo (o pkexec fica sem cara)".into() }
    } else {
        Diag { nome: "polkit", ok: true, nota: format!("{achado} no ar") }
    }
}

/// (4) o dono único das notificações: o nome tem dono no session bus (o
/// swaync supervisionado da 1.0-107; sem dono = notificação some no vácuo).
fn diag_notifications(conn: &Option<zbus::blocking::Connection>) -> Diag {
    let Some(c) = conn.as_ref() else {
        return Diag { nome: "notify", ok: false, nota: "sem session bus".into() };
    };
    let Ok(p) = zbus::blocking::Proxy::new(
        c,
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
    ) else {
        return Diag { nome: "notify", ok: false, nota: "o driver do bus não atende".into() };
    };
    match p.call::<_, _, bool>("NameHasOwner", &"org.freedesktop.Notifications") {
        Ok(true) => Diag {
            nome: "notify",
            ok: true,
            nota: "org.freedesktop.Notifications tem dono (swaync único)".into(),
        },
        Ok(false) => Diag {
            nome: "notify",
            ok: false,
            nota: "NENHUM dono de org.freedesktop.Notifications (as notificações caem no vácuo)".into(),
        },
        Err(e) => Diag { nome: "notify", ok: false, nota: format!("NameHasOwner falhou: {e}") },
    }
}

/// (5) a tabela /proc/acpi/wakeup: a família espúria dormindo + a mão do
/// dono armada (o julgamento PURO é o mesmo do elite-acpi-wakeup).
fn diag_wakeup() -> Diag {
    let Ok(tabela) = std::fs::read_to_string("/proc/acpi/wakeup") else {
        return Diag {
            nome: "wakeup",
            ok: false,
            nota: "/proc/acpi/wakeup não existe (container/exótico)".into(),
        };
    };
    let (espurios, mao) = julga_wakeup(&tabela);
    if espurios.is_empty() && mao.is_empty() {
        Diag {
            nome: "wakeup",
            ok: true,
            nota: "família espúria dormindo · PWRB/SLPB/PBTN/PS2K/LID armados".into(),
        }
    } else {
        let mut nota = String::new();
        if !espurios.is_empty() {
            nota.push_str(&format!("espúrios ACORDADOS: {}", espurios.join(",")));
        }
        if !mao.is_empty() {
            if !nota.is_empty() {
                nota.push_str(" · ");
            }
            nota.push_str(&format!("mão do dono DORMINDO: {}", mao.join(",")));
        }
        Diag { nome: "wakeup", ok: false, nota }
    }
}

/// (6) a saída padrão do PipeWire: o socket no chão + o default NUNCA
/// auto_null (o sequestro do monitor é doença nomeada). O stat do socket
/// ANTES do fork é o <50ms (sem PipeWire vivo, o pactl nem nasce).
fn diag_pipewire() -> Diag {
    let uid = unsafe { libc::getuid() };
    let socket = PathBuf::from(format!("/run/user/{uid}/pipewire-0"));
    if !socket.exists() {
        return Diag {
            nome: "áudio",
            ok: false,
            nota: "o socket do PipeWire não está no chão (o servidor morreu?)".into(),
        };
    }
    let Ok(out) = std::process::Command::new("pactl").arg("get-default-sink").output() else {
        return Diag { nome: "áudio", ok: false, nota: "o pactl não executa".into() };
    };
    let sink = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if sink.is_empty() {
        return Diag { nome: "áudio", ok: false, nota: "sem default sink (o pactl calou)".into() };
    }
    if sink.starts_with("auto_null") {
        return Diag {
            nome: "áudio",
            ok: false,
            nota: "default = auto_null (a placa viva perdeu o trono — o roteador da casa decide)".into(),
        };
    }
    Diag { nome: "áudio", ok: true, nota: format!("default: {sink}") }
}

/// (7) o GameMode (INFORMATIVO: o gamemoded é sob demanda — a ausência
/// dele é a paz, não a doença; o estado é a notícia).
fn diag_gamemode(conn_sys: &Option<zbus::blocking::Connection>) -> Diag {
    let Some(c) = conn_sys.as_ref() else {
        return Diag { nome: "gamemode", ok: true, nota: "sem system bus (informativo)".into() };
    };
    let Ok(p) = zbus::blocking::Proxy::new(
        c,
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
    ) else {
        return Diag { nome: "gamemode", ok: true, nota: "o driver do bus não atende (informativo)".into() };
    };
    let Ok(true) = p.call::<_, _, bool>("NameHasOwner", &"com.feralinteractive.GameMode") else {
        return Diag {
            nome: "gamemode",
            ok: true,
            nota: "gamemoded sob demanda (acorda no craft-game — a paz)".into(),
        };
    };
    match crate::scan::gm_status(conn_sys) {
        1 => Diag { nome: "gamemode", ok: true, nota: "ATIVO (o holder manual segura idle:sleep)".into() },
        _ => Diag { nome: "gamemode", ok: true, nota: "gamemoded no ar, nenhum jogo segurando".into() },
    }
}

/// A CORRIDA: monta os 7 vereditos, imprime o relatório e devolve o
/// código de saída (0 = saúde inteira).
pub fn run() -> i32 {
    let conn = zbus::blocking::Connection::session().ok();
    let conn_sys = zbus::blocking::Connection::system().ok();
    let diags = vec![
        diag_dbus_env(&conn),
        diag_bus_sock(),
        diag_polkit(),
        diag_notifications(&conn),
        diag_wakeup(),
        diag_pipewire(),
        diag_gamemode(&conn_sys),
    ];
    let (texto, rc) = relatorio(&diags);
    let mut stdout = std::io::stdout();
    let _ = stdout.write_all(texto.as_bytes());
    let _ = stdout.flush();
    rc
}

#[cfg(test)]
mod tests {
    use super::*;

    fn diag(nome: &'static str, ok: bool, nota: &str) -> Diag {
        Diag { nome, ok, nota: nota.into() }
    }

    #[test]
    fn e1072_o_julgo_da_tabela_wakeup() {
        // a saúde: família dormindo, mão armada
        let (e, m) = julga_wakeup(
            "Device  S-state   Status\n\
             XHC0      S4      *disabled\n\
             GPP3      S4      *disabled\n\
             PTXH      S4      *disabled\n\
             PWRB      S4      *enabled\n\
             SLPB      S4      *enabled\n\
             PBTN      S4      *enabled\n\
             PS2K      S3      *enabled\n\
             LID       S3      *enabled\n",
        );
        assert!(e.is_empty() && m.is_empty(), "tabela sadia: nada a apontar (e={e:?} m={m:?})");
        // o dongle acordando a máquina + a tampa dormindo (os dois réus)
        let (e, m) = julga_wakeup(
            "XHC0      S4      *enabled\n\
             GPP3      S4      *enabled\n\
             X1_2      S4      *enabled\n\
             GP30      S4      *enabled\n\
             PTXH      S4      *disabled\n\
             PWRB      S4      *enabled\n\
             LID       S3      *disabled\n\
             PS2K      S3      *disabled\n",
        );
        assert_eq!(e, vec!["XHC0", "GPP3", "X1_2", "GP30"], "a família espúria armada é nomeada");
        assert_eq!(m, vec!["LID", "PS2K"], "a mão do dono dormindo é nomeada");
        // o X1 com dígito é espúrio, o XHC12 idem — e o PS2K NUNCA é espúrio
        let (e, _) = julga_wakeup("X123     S4      *enabled\nXHC12    S4    *enabled\nPS2K     S3    *enabled\n");
        assert_eq!(e.len(), 2, "as grafias da família casam as duas");
    }

    #[test]
    fn e1072_o_relatorio_nomes_o_reu_e_o_codigo() {
        // saúde inteira: rc 0 e o veredito fechando
        let (txt, rc) = relatorio(&[diag("ambiente", true, "ok"), diag("bus.sock", true, "vivo")]);
        assert_eq!(rc, 0);
        assert!(txt.contains("saúde INTEIRA"), "o relatório fecha com saúde: {txt}");
        assert!(txt.contains('✓'));
        // o réu nomeado: rc 1 e o invariante quebrado na primeira linha
        let (txt, rc) = relatorio(&[diag("ambiente", true, "ok"), diag("polkit", false, "sem agente")]);
        assert_eq!(rc, 1);
        assert!(txt.contains("1 invariante(s) QUEBRADO(S)"), "{txt}");
        assert!(txt.contains('✗'), "o réu veste a marca: {txt}");
    }

    #[test]
    fn e1072_as_familias_do_wakeup_sao_as_das_scripts() {
        // a lei UMA: o julgo do doctor é o MESMO do elite-acpi-wakeup (o
        // espúrio e a mão não divergem entre as portas da casa)
        assert!(wakeup_espurio("XHC0") && wakeup_espurio("PTXH") && wakeup_espurio("GPP8"));
        assert!(wakeup_espurio("GP30") && wakeup_espurio("X161") && wakeup_espurio("X1_1"));
        assert!(!wakeup_espurio("PWRB") && !wakeup_espurio("PS2K") && !wakeup_espurio("LID"));
        assert!(!wakeup_espurio("SLPB") && !wakeup_espurio("PBTN"));
        assert!(wakeup_mao("PWRB") && wakeup_mao("SLPB") && wakeup_mao("PBTN") && wakeup_mao("PS2K") && wakeup_mao("LID"));
        assert!(!wakeup_mao("XHC0") && !wakeup_mao("PS2M"));
    }
}
