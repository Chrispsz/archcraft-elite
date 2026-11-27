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

/// a mão do dono (o allowlist universal da 1.0-107.2).
fn wakeup_mao(nome: &str) -> bool {
    matches!(nome, "PWRB" | "SLPB" | "PBTN" | "PS2K" | "LID")
}

/// 1.0-108 — FORA DA MÃO DO DONO (a lei nova do /proc/acpi/wakeup): a
/// família espúria FIXA de era (XHC*/PTXH/GP*) deixava nomes FORA da
/// lista (SWUS, SWDS, GP12, GP13…) ACORDADOS sem dono — a regra agora
/// é PURA: tudo que NÃO é a mão do dono é espúrio (a mesma lei do
/// `elite-acpi-wakeup`/`craft-wake-guard` — uma lei só na casa).
fn wakeup_espurio(nome: &str) -> bool {
    !wakeup_mao(nome)
}

/// O JULGO DA TABELA (PURO — a sonda de teste alimenta tabela de mentira):
/// 1.0-108 — devolve (gatilhos espúrios ARMADOS, A MÃO DO DONO ARMADA?) —
/// saúde = família espúria dormindo E PELO MENOS UMA fonte válida do
/// dono (PWRB/SLPB/PBTN/PS2K/LID) *enabled. O falso positivo de era:
/// o julgo exigia a mão TODA armada e o desktop USB-only SEM PS2K/LID
/// no hardware nascia DOENTE no papel com a mesa sã (o PS2K *disabled
/// não é réu quando o PWRB acorda a máquina).
pub fn julga_wakeup(tabela: &str) -> (Vec<String>, bool) {
    let mut espurios = Vec::new();
    let mut mao_armada = false;
    for linha in tabela.lines() {
        let campos: Vec<&str> = linha.split_whitespace().collect();
        // a gramática do /proc/acpi/wakeup: Name S-state Status Sysfs
        // (o status é o 3º campo — o 2º é o S-state do sono)
        let &[nome, _s_state, estado, ..] = campos.as_slice() else {
            continue;
        };
        if estado != "*enabled" {
            continue; // *disabled não é réu (o PS2K ausente do hardware não conta)
        }
        if wakeup_espurio(nome) {
            espurios.push(nome.to_string()); // acordado sem dono: o dongle/PCIe da era
        } else {
            mao_armada = true; // a mão do dono armada — o despertar é DELA
        }
    }
    (espurios, mao_armada)
}

/// 1.0-109 — A SAÚDE DO DESPERTAR COM O BOTÃO DO KERNEL (a evidência do
/// dump 1.0-108: o falso positivo em `wakeup` — na placa desktop AM4 o
/// botão físico de ligar é ACPI FIXED HARDWARE e deixa o /proc/acpi/
/// wakeup SEM *enabled NENHUM quando os espúrios USB/PCIe estão
/// desligados; a tabela vazia não é doença, é o botão morando em OUTRO
/// lugar do kernel). A saúde segue a LEI PURA (zero espúrios *enabled
/// fora da allowlist) e aceita a fonte do dono ARMADA na tabela OU o
/// DRIVER do botão presente no kernel (/sys/bus/acpi/drivers/button ·
/// /proc/acpi/button/power — o hardware fixo é a fonte de sempre).
pub fn wakeup_saudavel(espurios: &[String], mao_armada: bool, botao_no_kernel: bool) -> bool {
    espurios.is_empty() && (mao_armada || botao_no_kernel)
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

/// (1) o ambiente Wayland da sessão: o `systemctl --user
/// show-environment` é a via canônica (1.0-109 — a diretriz: validar
/// via systemctl com o fallback D-Bus na PROPRIEDADE `Environment` do
/// org.freedesktop.systemd1.Manager; a 1.0-108 lia a propriedade
/// primeiro e a queda de CLI nunca rodava) — a mesma leitura, duas
/// portas, o PAPEL primeiro.
fn diag_dbus_env(conn: &Option<zbus::blocking::Connection>) -> Diag {
    let Some(c) = conn.as_ref() else {
        return Diag {
            nome: "ambiente",
            ok: false,
            nota: "sem session bus (a sessão não existe aqui?)".into(),
        };
    };
    // 1.0-109 — O PAPEL PRIMEIRO (a diretriz da dose: o systemctl é a
    // canônica — o CLI roda em QUALQUER ambiente de sessão com o
    // systemd do usuário de pé; a PROPRIEDADE D-Bus é a queda para o
    // canto onde o binário do systemctl não mora)
    let env: std::collections::HashMap<String, String> = ambiente_do_systemctl()
        .or_else(|_| ambiente_do_dbus(c))
        .unwrap_or_default();
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

/// O PAPEL DO SYSTEMCTL (o `show-environment` KEY=VALUE) vira o MESMO
/// mapa da propriedade — o PARSE é PURO (a sonda de teste alimenta papel
/// de mentira); a saída sem nada é honesta: o mapa vazio nomeia o réu.
fn le_ambiente_do_papel(papel: &str) -> std::collections::HashMap<String, String> {
    let mut env = std::collections::HashMap::new();
    for linha in papel.lines() {
        if let Some((k, v)) = linha.split_once('=') {
            env.insert(k.to_string(), v.to_string());
        }
    }
    env
}

/// A CANÔNICA DA DOSE (1.0-109): o `systemctl --user show-environment`
/// serve o ambiente do systemd do usuário — a porta que TODO rig tem.
fn ambiente_do_systemctl() -> zbus::Result<std::collections::HashMap<String, String>> {
    use std::process::Command;
    let out = Command::new("systemctl")
        .args(["--user", "show-environment"])
        .output()
        .map_err(|e| zbus::Error::Failure(format!("systemctl --user show-environment: {e}")))?;
    if !out.status.success() {
        return Err(zbus::Error::Failure(format!(
            "systemctl --user show-environment: rc {}",
            out.status.code().unwrap_or(-1)
        )));
    }
    Ok(le_ambiente_do_papel(&String::from_utf8_lossy(&out.stdout)))
}

/// A QUEDA D-BUS (a PROPRIEDADE `Environment` do org.freedesktop.systemd1.
/// Manager — o `a{ss}` do zvariant vira o MESMO mapa do papel): o
/// canto sem o binário do systemctl continua lendo a verdade.
fn ambiente_do_dbus(
    c: &zbus::blocking::Connection,
) -> zbus::Result<std::collections::HashMap<String, String>> {
    let p = zbus::blocking::Proxy::new(
        c,
        "org.freedesktop.systemd1",
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
    )?;
    let val = p.get_property::<zbus::zvariant::OwnedValue>("Environment")?;
    let mut env = std::collections::HashMap::new();
    if let zbus::zvariant::Value::Dict(d) = zbus::zvariant::Value::from(val) {
        for (k, v) in d {
            if let (Ok(k), Ok(v)) = (<String>::try_from(k), <String>::try_from(v)) {
                env.insert(k, v);
            }
        }
    }
    Ok(env)
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

/// (5) a tabela /proc/acpi/wakeup: a família espúria dormindo + a mão
/// do dono armada (o julgamento PURO é o mesmo do elite-acpi-wakeup).
fn diag_wakeup() -> Diag {
    let Ok(tabela) = std::fs::read_to_string("/proc/acpi/wakeup") else {
        return Diag {
            nome: "wakeup",
            ok: false,
            nota: "/proc/acpi/wakeup não existe (container/exótico)".into(),
        };
    };
    let (espurios, mao_armada) = julga_wakeup(&tabela);
    // 1.0-109 — O BOTÃO DE HARDWARE FIXO do desktop AM4 (a ACPI Fixed
    // Hardware não mora no /proc/acpi/wakeup: o driver do botão no
    // kernel é a prova de que a máquina acorda com o botão físico)
    let botao_no_kernel = std::path::Path::new("/sys/bus/acpi/drivers/button").exists()
        || std::path::Path::new("/proc/acpi/button/power").exists();
    if wakeup_saudavel(&espurios, mao_armada, botao_no_kernel) {
        let de_onde = if mao_armada {
            "PWRB/SLPB/PBTN/PS2K/LID armados"
        } else {
            "o botão do kernel (ACPI Fixed Hardware do desktop — a tabela não lista o que é fixo)"
        };
        Diag {
            nome: "wakeup",
            ok: true,
            nota: format!("toda a família fora da mão do dono dormindo · {de_onde}"),
        }
    } else {
        let mut nota = String::new();
        if !espurios.is_empty() {
            nota.push_str(&format!("espúrios ACORDADOS: {}", espurios.join(",")));
        }
        if !mao_armada && !botao_no_kernel {
            if !nota.is_empty() {
                nota.push_str(" · ");
            }
            nota.push_str("NENHUMA fonte do dono (a tabela não tem PWRB/SLPB/PBTN/PS2K/LID e o kernel não tem o driver do botão — a máquina nem com o botão físico acorda)");
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
    fn e108_o_julgo_da_tabela_wakeup() {
        // 1.0-108 — A LEI NOVA: todo *enabled FORA da mão do dono é
        // espúrio (SWUS/SWDS/GP12/GP13 incluídos — a família fixa de era
        // deixava-os acordados) e a saúde exige PELO MENOS UMA fonte da
        // mão armada (o desktop USB-only sem PS2K/LID não é réu)
        let (e, mao) = julga_wakeup(
            "Device  S-state   Status\n\
             XHC0      S4      *disabled\n\
             SWUS      S4      *disabled\n\
             GP12      S4      *disabled\n\
             PWRB      S4      *enabled\n\
             PS2K      S3      *disabled\n",
        );
        assert!(e.is_empty() && mao, "tabela sadia: nada fora da mão acordado, o PWRB acorda a máquina (e={e:?})");
        // o falso positivo de era CURADO: o desktop USB-only SEM PS2K/LID
        // no hardware, com o PWRB armado — é SAÚDE (o PS2K *disabled não
        // é réu; a exigência da mão TODA armada era a doença)
        let (e, mao) = julga_wakeup(
            "PWRB      S4      *enabled\n\
             PS2K      S3      *disabled\n\
             LID       S3      *disabled\n",
        );
        assert!(e.is_empty() && mao, "o PS2K/LID desarmado sem hardware não é réu (o PWRB manda)");
        // os réus nomeados: o dongle USB, a ponte PCIe e as SOBRAS de era
        let (e, mao) = julga_wakeup(
            "XHC0      S4      *enabled\n\
             GP30      S4      *enabled\n\
             SWDS      S4      *enabled\n\
             GP12      S4      *enabled\n\
             PWRB      S4      *enabled\n",
        );
        assert_eq!(e, vec!["XHC0", "GP30", "SWDS", "GP12"], "todo *enabled fora da allowlist é nomeado");
        assert!(mao, "a mão armada segue armada");
        // o DESERTO: nenhuma fonte do dono armada — a máquina nem com o
        // botão acorda (o réu que a exigência da mão TODA não via)
        let (e, mao) = julga_wakeup("XHC0      S4      *disabled\nPWRB      S4      *disabled\n");
        assert!(e.is_empty() && !mao, "sem NENHUMA mão armada o sono é armadilha");
    }

    #[test]
    fn e109_a_saude_do_wakeup_aceita_o_botao_do_kernel() {
        // A EVIDÊNCIA DO DUMP 1.0-108 (a placa desktop AM4): o botão
        // físico de ligar é ACPI FIXED HARDWARE — o /proc/acpi/wakeup
        // fica SEM *enabled NENHUM com os espúrios desligados e o
        // doctor de era nomeava a mesa sã de réu. A saúde exige ZERO
        // espúrios e aceita a mão do dono NA TABELA ou o DRIVER do
        // botão NO KERNEL
        let nenhum: Vec<String> = Vec::new();
        // a mão armada na tabela: saúde de sempre
        assert!(wakeup_saudavel(&nenhum, true, false));
        // o desktop AM4 SEM fonte na tabela mas COM o driver do botão:
        // SAÚDE (o hardware fixo é a fonte de sempre)
        assert!(wakeup_saudavel(&nenhum, false, true));
        // nem a tabela nem o kernel: a máquina nem com o botão acorda
        assert!(!wakeup_saudavel(&nenhum, false, false));
        // espúrio ACORDADO: o réu segue nomeado COM ou SEM o botão
        assert!(!wakeup_saudavel(&["XHC0".to_string()], true, true));
    }

    #[test]
    fn e109_o_papel_do_systemctl_vira_o_mapa_do_ambiente() {
        // o PARSE PURO do `systemctl --user show-environment` (a
        // canônica da diretriz): KEY=VALUE por linha, o resto é silêncio
        let mapa = le_ambiente_do_papel(
            "WAYLAND_DISPLAY=wayland-0
XDG_CURRENT_DESKTOP=labwc:wlroots
LIXO_SEM_IGUAL
",
        );
        assert_eq!(mapa.get("WAYLAND_DISPLAY").map(String::as_str), Some("wayland-0"));
        assert_eq!(mapa.get("XDG_CURRENT_DESKTOP").map(String::as_str), Some("labwc:wlroots"));
        assert!(!mapa.contains_key("LIXO_SEM_IGUAL"), "linha sem = não é ambiente");
        assert!(le_ambiente_do_papel("").is_empty());
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
    fn e108_as_familias_do_wakeup_sao_as_das_scripts() {
        // a lei UMA: o julgo do doctor é o MESMO do elite-acpi-wakeup (o
        // espúrio é "fora da mão do dono" — a allowlist decide, não a
        // família fixa de era; SWUS/SWDS/GP12/GP13 inclusos)
        assert!(wakeup_espurio("XHC0") && wakeup_espurio("PTXH") && wakeup_espurio("GPP8"));
        assert!(wakeup_espurio("GP30") && wakeup_espurio("X161") && wakeup_espurio("X1_1"));
        assert!(wakeup_espurio("SWUS") && wakeup_espurio("SWDS") && wakeup_espurio("GP12"));
        assert!(wakeup_espurio("PS2M"));
        assert!(!wakeup_espurio("PWRB") && !wakeup_espurio("PS2K") && !wakeup_espurio("LID"));
        assert!(!wakeup_espurio("SLPB") && !wakeup_espurio("PBTN"));
        assert!(wakeup_mao("PWRB") && wakeup_mao("SLPB") && wakeup_mao("PBTN") && wakeup_mao("PS2K") && wakeup_mao("LID"));
        assert!(!wakeup_mao("XHC0") && !wakeup_mao("PS2M"));
    }
}
