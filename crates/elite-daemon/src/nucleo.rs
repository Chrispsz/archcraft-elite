// ═════════════════════════════════════════════════════════════════════════
// elite-daemon — nucleo.rs (2.0 Fase 2) — O NÚCLEO DO BUS VIVO
// ═════════════════════════════════════════════════════════════════════════
// O Estado global da casa: o bus (quem liga é o `liga_bus` — a porta
// session E o modo game chamam; o segundo é no-op honesto) e a THREAD
// NÚCLEO, que fala com o mundo:
//   · Hello de cliente → o SNAPSHOT DE BOAS-VINDAS dirigido (janelas +
//     mesa + mídia + jogo — o frame 0 da barra e da dock nasce cheio);
//   · Req → o VERBO certo no módulo certo + o Ack ecoado (o pedido
//     mora no módulo que É a verdade daquele domínio: janela no
//     wayland.rs, mídia no mpris.rs, mesa no workspace.rs, jogo no
//     motor de jogo — o craft-game CLI segue como o cérebro manual);
//   · nada de lógica de domínio AQUI (o núcleo é a mesa de despacho —
//     cada pedido nasce, é despachado e o Ack volta no mesmo giro).
// ═════════════════════════════════════════════════════════════════════════

use std::sync::{Arc, OnceLock};

use elite_core::bus::{BusServer, Incoming};
use elite_core::{bus_sock_path, BusMsg, BusReq};

/// o estado global (o bus vivo da sessão).
pub struct Estado {
    bus: Arc<BusServer>,
}

static STATE: OnceLock<Estado> = OnceLock::new();

/// liga o bus da sessão (a porta session e o modo game chamam; o
/// segundo chamador é no-op — UMA instância é a lei de sempre).
pub fn liga_bus() {
    if STATE.get().is_some() {
        return;
    }
    let uid = unsafe { libc::getuid() };
    let caminho = bus_sock_path(uid);
    let Ok((bus, rx)) = BusServer::start(&caminho) else {
        eprintln!("elite-daemon: o bus.sock não ligou em {caminho:?} (a sessão segue sem fio — honesto no papel)");
        return;
    };
    STATE.set(Estado { bus: Arc::clone(&bus) }).ok();
    eprintln!("elite-daemon: bus VIVO no ar ({})", caminho.display());
    std::thread::Builder::new()
        .name("elite-nucleo".into())
        .spawn(move || despacho(bus, rx))
        .ok();
}

/// PUBLICA de qualquer thread da casa (a via curta dos módulos: o bus
/// ausente é silêncio honesto — a sessão sem fio não trava ninguém).
pub fn pub_bus(msg: &BusMsg) {
    if let Some(e) = STATE.get() {
        e.bus.broadcast(msg);
    }
}

/// o SNAPSHOT DE BOAS-VINDAS (o frame 0 do cliente nasce cheio).
fn boas_vindas(bus: &BusServer, cliente: u32) {
    bus.send_to(cliente, &BusMsg::Windows { windows: crate::wayland::windows_mru() });
    bus.send_to(cliente, &BusMsg::Workspace(elite_core::WorkspaceInfo {
        current: crate::workspace::atual(),
        count: crate::workspace::total(),
        label: crate::workspace::nome(crate::workspace::atual()),
    }));
    if let Some(media) = crate::mpris::estado() {
        bus.send_to(cliente, &BusMsg::Media(media));
    }
    // o modo de jogo do momento (o QueryStatus é a verdade de sempre)
    let gm = match zbus::blocking::Connection::session() {
        Ok(c) => {
            let conn = Some(c);
            crate::scan::gm_status(&conn) == 1
        }
        Err(_) => false,
    };
    bus.send_to(cliente, &BusMsg::GameMode(elite_core::GameModeState {
        active: gm,
        game: None,
        gpu_performance: gm,
    }));
}

/// a mesa de despacho (um pedido nasce, vai ao módulo certo, o Ack volta).
fn despacho(bus: Arc<BusServer>, rx: std::sync::mpsc::Receiver<Incoming>) {
    for msg in rx {
        match msg {
            Incoming::Hello { id, who } => {
                eprintln!("elite-daemon: bus.cliente {id} = {who} (a sessão ganhou olhos)");
                boas_vindas(&bus, id);
            }
            Incoming::Req { cliente, req_id, req } => {
                let ok = match req {
                    BusReq::Activate { id } => crate::wayland::ativa(id),
                    BusReq::Minimize { id } => crate::wayland::minimiza(id),
                    BusReq::Close { id } => crate::wayland::fecha(id),
                    BusReq::Snapshot => {
                        boas_vindas(&bus, cliente);
                        true
                    }
                    BusReq::Media(verb) => crate::mpris::cmd(verb),
                    BusReq::Game(verb) => jogo_manual(verb),
                    BusReq::Workspace { to } => crate::workspace::pula(to),
                };
                bus.send_to(cliente, &BusMsg::Ack { id: req_id, ok });
            }
        }
    }
}

/// o jogo MANUAL pelo bus (o pill da barra clica AQUI): o cérebro é o
/// craft-game (o mesmo motor do menu — os verbos on/off/toggle com o
/// feedback na tela E106); um fork por clique (raro por desenho).
fn jogo_manual(verb: elite_core::GameCmd) -> bool {
    let arg = match verb {
        elite_core::GameCmd::On => "on",
        elite_core::GameCmd::Off => "off",
        elite_core::GameCmd::Toggle => "toggle",
        elite_core::GameCmd::Status => "status",
    };
    std::process::Command::new("/usr/local/bin/craft-game")
        .arg(arg)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}
