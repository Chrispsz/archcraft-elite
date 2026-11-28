// ═════════════════════════════════════════════════════════════════════════
// elite-daemon — nucleo.rs (2.0 Fase 2) — O NÚCLEO DO BUS VIVO
// ═════════════════════════════════════════════════════════════════════════
// O Estado global da casa: o bus (quem liga é o `liga_bus` — a porta
// session E o modo game chamam; o segundo é no-op honesto) e a THREAD
// NÚCLEO, que fala com o mundo:
//   · Hello de cliente → o SNAPSHOT DE BOAS-VINDAS dirigido (janelas +
//     mesa + mídia + bluetooth + jogo — o frame 0 da barra e da dock
//     nasce cheio);
//   · Req → o VERBO certo no módulo certo + o Ack ecoado (o pedido
//     mora no módulo que É a verdade daquele domínio: janela no
//     wayland.rs, mídia no mpris.rs, mesa no workspace.rs, jogo no
//     motor de jogo — o craft-game CLI segue como o cérebro manual);
//   · nada de lógica de domínio AQUI (o núcleo é a mesa de despacho —
//     cada pedido nasce, é despachado e o Ack volta no mesmo giro).
//
// 1.0-94 — O DONO ÚNICO (a cura do bus.sock MORTO): `liga_bus` (o
// bind) é da porta `session` — o processo que quer falar SEM a posse
// chama o `BusClient` dele (a porta curta do game-notify, 1.0-107)
// e `pub_bus` publica PELO FIO (o servidor retransmite; o bind antigo
// fazia remove_file+bind e matava o socket do dono no caminho — o
// fóssil que o dump nomeava MORTO com os dois daemons vivos).
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
/// 1.0-94 — O DONO É UM SÓ: o modo game com SESSÃO viva NÃO chama aqui
/// (o game-notify publica pelo BusClient dele); o bind rebinda o caminho e mataria o fio do
/// dono (a classe do bus.sock MORTO do rig da 1.0-93).
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
/// 1.0-107 — o lado CLIENTE morreu com o daemon_loop de era (o
/// game-notify publica pelo BusClient DELE, curto como o desk); o bus
/// ausente segue silêncio honesto.
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
    // 1.0-106 — o BLUETOOTH no snapshot (o ícone da barra nasce com a
    // verdade do adaptador — o Powered do BlueZ consultado no arranque;
    // None = BlueZ calado, a barra conserva o cinto próprio dela)
    if let Some(bt) = crate::bluetooth::estado() {
        bus.send_to(cliente, &BusMsg::Bluetooth(bt));
    }
    // 1.0-110 T1 — O ÁUDIO E A REDE NO FRAME 0 (a barra sem belts:
    // TODO estado chega por PUSH do daemon — o boas-vindas é o frame 0
    // honesto, o ícone nasce com a verdade do pactl e do NM sem fork
    // nenhum do lado de lá)
    if let Some(audio) = crate::audio::estado() {
        bus.send_to(cliente, &BusMsg::Audio(audio));
    }
    if let Some(rede) = crate::network::estado() {
        bus.send_to(cliente, &BusMsg::Network(rede));
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
                    // 1.0-100 — O SYNC DA MESA (audit 99 §4): o rc.xml
                    // fez a troca (GoToDesktop/SendToDesktop + Execute do
                    // sync) e a casa SÓ registra e publica — nunca
                    // sintetiza tecla (o Workspace de cima é A síntese;
                    // sintetizar aqui fechava o loop W-<n> → sync → W-<n>)
                    BusReq::DeskSet { to } => crate::workspace::define(to),
                    BusReq::DeskStep { dir } => crate::workspace::passo(&dir),
                    // 1.0-110 T3 — O VERBO DA SUSPENSÃO NATIVA (o item
                    // "Suspender" da barra E o craft-suspend mandam AQUI):
                    // a thread própria segura o Ack NA HORA — o lock e a
                    // espera da superfície (teto 3s) moram no idle::suspende,
                    // longe do despacho (a fila do bus nunca espera o sono)
                    BusReq::Suspend => std::thread::Builder::new()
                        .name("elite-suspende".into())
                        .spawn(crate::idle::suspende)
                        .is_ok(),
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
