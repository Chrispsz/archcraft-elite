// ═════════════════════════════════════════════════════════════════════════
// elite-daemon — wayland.rs (2.0 Fase 2) — O CLIENTE WAYLAND NATIVO
// ═════════════════════════════════════════════════════════════════════════
// O craft-toplevel.c (o C de 3 gerações) MORRE AQUI: o daemon é AGORA o
// cliente nativo do labwc — fala zwlr-foreign-toplevel-management-v1
// (v2 — a lição E95: o v3 só somava o evento parent, a churn dos
// diálogos transitórios) e ext-idle-notify-v1 (a vigília e a trava
// automática — o swayidle aposenta).
//
// O QUE ESTE MÓDULO É:
//   · A SESSÃO DE JANELAS para TODA a casa: cada toplevel vira um
//     `WindowInfo` com id PRÓPRIO (contador da casa — o id do protocolo
//     nunca vaza), app_id, título, flags e a POSIÇÃO no anel MRU;
//     cada mudança PUBLICA `BusMsg::Windows` no bus (a ORDEM é o anel —
//     índice 0 = a mais recentemente focada; a dock v2 deriva o rank
//     daí). A janela que FECHA sai do snapshot NO MESMO evento — a
//     dock remove o botão no mesmo frame (zero espaços pretos).
//   · OS VERBOS por id de OUTRAS threads: activate / minimize / close
//     saem por request DIRETO no handle (o WM_DELETE gracioso — o app
//     confirma se tiver o que salvar) + flush. Os proxies são Send —
//     o pedido viaja SEM fila de comandos e SEM fork (o wlrctl das
//     JANELAS aposenta — ele segue vivo só na síntese da mesa).
//   · A VIGÍLIA (ext-idle-notify): notificação única em LOCK_MIN →
//     hyprlock + tela apagada (wlopm) NO MESMO GESTO (a lei E43 do
//     idle.conf); SUSPEND_MIN de TRAVADO → systemctl suspend (a
//     vigília E60); RESPEITA os inibidores — o jogo da casa arma um
//     inhibitor "idle" no logind e a mídia tocando (MPRIS) também
//     segura a mão (o pedido do dono: "respeitando inibidores de
//     jogos/mídia").
//   · O ÍDOLO da mesa: o foco que chega APÓS um pulo sintetizado crava
//     a mesa corrente (a heurística honesta do labwc sem protocolo de
//     mesa — ver workspace.rs).
//
// O FIO: UMA thread despachante (blocking_dispatch — o event queue
// dela), os pedidos de verbo chegam por request thread-safe e o flush
// segue na hora. Sem GTK, sem polling, sem fork por janela.
// ═════════════════════════════════════════════════════════════════════════

use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use wayland_client::protocol::wl_registry;
use wayland_client::{Connection, Dispatch, Proxy, QueueHandle};
use wayland_protocols::ext::idle_notify::v1::client as idle_mod;
use wayland_protocols_wlr::foreign_toplevel::v1::client as tl_mod;

use elite_core::{BusMsg, WindowInfo, WorkspaceInfo};

use crate::{idle as casa_idle, workspace};

/// o contador dos ids da casa (o mesmo id que cruza o bus).
fn proximo_id() -> u32 {
    NEXT_ID.fetch_add(1, Ordering::Relaxed)
}

static NEXT_ID: AtomicU32 = AtomicU32::new(1);

/// Um toplevel vivo da sessão (o handle mora MUDO aqui dentro).
struct Rec {
    handle: tl_mod::zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1,
    app_id: String,
    title: String,
    minimized: bool,
    focused: bool,
}

/// o lado compartilhado entre a despachante e as threads de verbo.
struct Wl {
    conn: Connection,
    seat: wayland_client::protocol::wl_seat::WlSeat,
    windows: Mutex<HashMap<u32, Rec>>,
    mru: Mutex<Vec<u32>>,
}

static SHARED: OnceLock<Arc<Wl>> = OnceLock::new();

/// O ponto de vista do bus: os windows em ORDEM MRU (índice 0 = topo).
pub fn windows_mru() -> Vec<WindowInfo> {
    let Some(sh) = SHARED.get() else { return Vec::new() };
    let mru = sh.mru.lock().unwrap().clone();
    let wins = sh.windows.lock().unwrap();
    mru.iter()
        .filter_map(|id| {
            wins.get(id).map(|r| WindowInfo {
                id: *id,
                app_id: r.app_id.clone(),
                title: if r.title.is_empty() { None } else { Some(r.title.clone()) },
                focused: r.focused,
                minimized: r.minimized,
                fullscreen: r.fullscreen,
            })
        })
        .collect()
}

/// OS VERBOS por id (qualquer thread — o request + flush na hora):
/// · ativa: focar E restaurar (o 1º clique da dock);
/// · minimiza: o toggle do 2º clique;
/// · fecha: o WM_DELETE gracioso (o clique do meio da dock).
/// id desconhecido = false honesto (janela já foi — o cliente segue o
/// snapshot seguinte, nunca estado de mentira).
pub fn ativa(id: u32) -> bool {
    aplica(id, |h, seat| {
        h.unset_minimized();
        h.activate(seat);
    })
}

pub fn minimiza(id: u32) -> bool {
    aplica(id, |h, _| h.set_minimized())
}

pub fn fecha(id: u32) -> bool {
    aplica(id, |h, _| h.close())
}

fn aplica(
    id: u32,
    verbo: impl FnOnce(
        &tl_mod::zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1,
        &wayland_client::protocol::wl_seat::WlSeat,
    ),
) -> bool {
    let Some(sh) = SHARED.get() else { return false };
    let handle = {
        let wins = sh.windows.lock().unwrap();
        wins.get(&id).map(|r| r.handle.clone())
    };
    let Some(handle) = handle else { return false };
    verbo(&handle, &sh.seat);
    sh.conn.flush().is_ok()
}

/// A janela do PLAYER (o clique direito do MPRIS): casa o app_id/título
/// contra a identidade do player e foca a mais recente que casa (o
/// match é benigno — só foca, nunca fecha).
pub fn foca_player(identidade: &str) -> bool {
    let Some(sh) = SHARED.get() else { return false };
    let alvo = identidade.to_lowercase();
    let id = {
        let wins = sh.windows.lock().unwrap();
        let mru = sh.mru.lock().unwrap().clone();
        mru.iter()
            .filter_map(|id| wins.get(id).map(|r| (*id, r)))
            .find(|(_, r)| {
                let a = r.app_id.to_lowercase();
                let t = r.title.to_lowercase();
                (!a.is_empty()
                    && (a.contains(&alvo)
                        || alvo.contains(a.as_str())
                        || a.split(['.', '-']).any(|p| !p.is_empty() && alvo.contains(p))))
                    || (!t.is_empty() && t.contains(&alvo))
            })
            .map(|(id, _)| id)
    };
    match id {
        Some(id) => ativa(id),
        None => false,
    }
}

// ── A THREAD DESPACHANTE (o event queue dela; o mundo entra por request)

/// Liga o cliente Wayland NATIVO. `None` honesto quando não há sessão
/// Wayland ou o compositor não fala foreign-toplevel (o --once de
/// teste, o rig sem display — o daemon segue vivo para as outras
/// portas).
pub fn start() -> Option<()> {
    if SHARED.get().is_some() {
        return Some(()); // já subiu (a sessão chama duas vezes por cinto)
    }
    let conn = Connection::connect_to_env().ok()?;
    let display = conn.display();
    let mut queue = conn.new_event_queue::<Estado>();
    let qh = queue.handle();
    let _registry = display.get_registry(&qh, ());
    let mut estado = Estado::default();
    queue.roundtrip(&mut estado).ok()?;
    let manager = estado.manager.clone()?;
    let seat = estado.seat.clone()?;
    let shared = Arc::new(Wl {
        conn: conn.clone(),
        seat,
        windows: Mutex::new(HashMap::new()),
        mru: Mutex::new(Vec::new()),
    });
    SHARED.set(Arc::clone(&shared)).ok()?;
    let mut arma_inicial = true;
    std::thread::Builder::new()
        .name("elite-wayland".into())
        .spawn(move || {
            let mut estado = Estado {
                manager: Some(manager),
                ..Default::default()
            };
            loop {
                if crate::STOP.load(Ordering::SeqCst) {
                    return;
                }
                if arma_inicial {
                    arma_inicial = false;
                    estado.arma_idle(&qh);
                }
                match queue.blocking_dispatch(&mut estado) {
                    Ok(_) => {}
                    Err(e) => {
                        eprintln!("elite-daemon: wayland dispatch {e} — o fio morre honesto (o supervisor reergue a sessão)");
                        return;
                    }
                }
            }
        })
        .ok()?;
    eprintln!("elite-daemon: cliente Wayland NATIVO no ar (foreign-toplevel + idle-notify)");
    Some(())
}

/// o instante do último pulo de mesa sintetizado (ms desde o arranque
/// da casa — o aprendizado da mesa lê daqui; quem marca é workspace.rs).
static PULO_EM: AtomicU64 = AtomicU64::new(0);

/// marca o pulo (a janela focada a seguir crava a mesa).
pub fn marca_pulo() {
    PULO_EM.store(agora_ms(), Ordering::Relaxed);
}

fn agora_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// o estado da thread despachante (os globais + o ofício de cada evento).
#[derive(Default)]
struct Estado {
    manager: Option<tl_mod::zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1>,
    seat: Option<wayland_client::protocol::wl_seat::WlSeat>,
    notifier: Option<idle_mod::ext_idle_notifier_v1::ExtIdleNotifierV1>,
    /// a trava da vigília está acesa (a 2ª notificação conta DE travado)
    trava_armada: bool,
}

impl Estado {
    fn publica(&mut self) {
        crate::nucleo::pub_bus(&BusMsg::Windows { windows: windows_mru() });
        crate::nucleo::pub_bus(&BusMsg::Workspace(WorkspaceInfo {
            current: workspace::atual(),
            count: workspace::total(),
            label: workspace::nome(workspace::atual()),
        }));
    }

    /// a MESA aprende: o pulo sintetizado acendeu; o foco que chega
    /// DEPOIS do pulo crava a mesa corrente (a heurística honesta).
    fn aprende_mesa(&mut self) {
        let pulo = PULO_EM.load(Ordering::Relaxed);
        if pulo != 0 && agora_ms().saturating_sub(pulo) < 1500 {
            let focada = {
                let Some(sh) = SHARED.get() else { return };
                let mru = sh.mru.lock().unwrap().clone();
                let wins = sh.windows.lock().unwrap();
                mru.iter()
                    .filter_map(|id| wins.get(id).map(|r| (*id, r.focused)))
                    .find(|(_, focado)| *focado)
                    .map(|(id, _)| id)
            };
            if let Some(id) = focada {
                workspace::aprende(id);
            }
        }
    }

    /// A VIGÍLIA: (re)arma a notificação de idle com o conf VIVO (o
    /// dono muda LOCK_MIN no menu — a próxima armação já obedece; o
    /// conf é barato de ler por ciclo, zero watcher).
    fn arma_idle(&mut self, qh: &QueueHandle<Self>) {
        let Some(notifier) = &self.notifier else { return };
        let Some(seat) = &self.seat else { return };
        let conf = casa_idle::conf_vivo();
        if conf.lock_min == 0 {
            return; // nunca sozinho (W-l manual — a escolha explícita)
        }
        let _ = notifier.get_idle_notification(conf.lock_min * 60 * 1000, seat, qh, false);
    }
}

impl Dispatch<wl_registry::WlRegistry, ()> for Estado {
    fn event(
        estado: &mut Estado,
        registry: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _data: &(),
        _conn: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_registry::Event::Global { name, interface, version } = event {
            match interface.as_str() {
                // E95 — o manager NASCE em v2 (o v3 só somava o parent)
                "zwlr_foreign_toplevel_manager_v1" => {
                    let v = version.min(2);
                    let m = registry.bind::<
                        tl_mod::zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1,
                        _, _,
                    >(name, v, qh, ());
                    estado.manager = Some(m);
                }
                "ext_idle_notifier_v1" => {
                    let n = registry.bind::<
                        idle_mod::ext_idle_notifier_v1::ExtIdleNotifierV1,
                        _, _,
                    >(name, version, qh, ());
                    estado.notifier = Some(n);
                }
                "wl_seat" => {
                    let s = registry.bind::<
                        wayland_client::protocol::wl_seat::WlSeat,
                        _, _,
                    >(name, version.min(1), qh, ());
                    estado.seat = Some(s);
                }
                _ => {}
            }
        }
    }
}

impl Dispatch<tl_mod::zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1, ()> for Estado {
    // o toplevel nasce de EVENTO do servidor: o id da casa vira o udata
    // no MESMO instante da criação (a macro é a via oficial da casa)
    wayland_client::event_created_child!(Estado, tl_mod::zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1, [
        tl_mod::zwlr_foreign_toplevel_manager_v1::EVT_TOPLEVEL_OPCODE => (tl_mod::zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1, proximo_id()),
    ]);

    fn event(
        _estado: &mut Estado,
        _manager: &tl_mod::zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1,
        event: tl_mod::zwlr_foreign_toplevel_manager_v1::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        if let tl_mod::zwlr_foreign_toplevel_manager_v1::Event::Toplevel { toplevel } = event {
            let id = toplevel.data::<u32>().copied().unwrap_or(0);
            if id == 0 {
                return; // sem id não há contrato (nunca devia acontecer)
            }
            let Some(sh) = SHARED.get() else { return };
            sh.windows.lock().unwrap().insert(id, Rec {
                handle: toplevel,
                app_id: String::new(),
                title: String::new(),
                minimized: false,
                focused: false,
            });
        }
    }
}

impl Dispatch<tl_mod::zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1, u32> for Estado {
    fn event(
        estado: &mut Estado,
        handle: &tl_mod::zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1,
        event: tl_mod::zwlr_foreign_toplevel_handle_v1::Event,
        id: &u32,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        use tl_mod::zwlr_foreign_toplevel_handle_v1::Event as E;
        let Some(sh) = SHARED.get() else { return };
        match event {
            E::AppId { app_id } => {
                if let Some(r) = sh.windows.lock().unwrap().get_mut(id) {
                    r.app_id = app_id;
                }
            }
            E::Title { title } => {
                if let Some(r) = sh.windows.lock().unwrap().get_mut(id) {
                    r.title = title;
                }
            }
            // o estado vem como ARRAY DE BYTES (0=max 1=min 2=act 3=full)
            E::State { state } => {
                let mut min = false;
                let mut act = false;
                for byte in state {
                    match byte {
                        1 => min = true,
                        2 => act = true,
                        _ => {}
                    }
                }
                let focou;
                {
                    let mut wins = sh.windows.lock().unwrap();
                    let Some(r) = wins.get_mut(id) else { return };
                    let era_focado = r.focused;
                    r.minimized = min;
                    r.focused = act;
                    focou = act && !era_focado;
                }
                if act {
                    // o anel MRU: quem ganha foco sobe para o TOPO
                    let mut mru = sh.mru.lock().unwrap();
                    mru.retain(|x| *x != *id);
                    mru.insert(0, *id);
                }
                if focou {
                    estado.aprende_mesa();
                }
            }
            // o marco de consistência: publica o snapshot do momento
            E::Done => {
                estado.publica();
            }
            // a janela FECHOU: sai do snapshot NO MESMO evento (a dock
            // remove o botão no mesmo frame — zero espaço preto)
            E::Closed => {
                {
                    let mut wins = sh.windows.lock().unwrap();
                    wins.remove(id);
                    sh.mru.lock().unwrap().retain(|x| *x != *id);
                }
                handle.destroy();
                estado.publica();
            }
            E::OutputEnter { .. } | E::OutputLeave { .. } => {}
            _ => {}
        }
    }
}

impl Dispatch<idle_mod::ext_idle_notifier_v1::ExtIdleNotifierV1, ()> for Estado {
    fn event(
        _estado: &mut Estado,
        _notifier: &idle_mod::ext_idle_notifier_v1::ExtIdleNotifierV1,
        _event: idle_mod::ext_idle_notifier_v1::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

/// udata da notificação: false = a do LOCK; true = a do SUSPEND-de-travado.
impl Dispatch<idle_mod::ext_idle_notification_v1::ExtIdleNotificationV1, bool> for Estado {
    fn event(
        estado: &mut Estado,
        notif: &idle_mod::ext_idle_notification_v1::ExtIdleNotificationV1,
        event: idle_mod::ext_idle_notification_v1::Event,
        suspende: &bool,
        _conn: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        match event {
            idle_mod::ext_idle_notification_v1::Event::Idled => {
                if !*suspende {
                    // A VIGÍLIA BATEU: trava + apaga NO MESMO GESTO (E43)
                    // se os inibidores deixarem (jogo/mídia seguram)
                    if casa_idle::inibidores_seguram() {
                        eprintln!("elite-daemon: idle batido — inibidores de jogo/mídia seguram (a trava espera)");
                    } else {
                        casa_idle::trava_e_apaga();
                        estado.trava_armada = true;
                        // o próximo degrau: SUSPEND_MIN de TRAVADO (E60)
                        let conf = casa_idle::conf_vivo();
                        if conf.suspend_min > 0 {
                            if let (Some(notifier), Some(seat)) = (&estado.notifier, &estado.seat) {
                                let _ = notifier.get_idle_notification(
                                    conf.suspend_min * 60 * 1000,
                                    seat,
                                    qh,
                                    true,
                                );
                            }
                        }
                    }
                    notif.destroy();
                    // rearma o relógio do LOCK (o ciclo continua)
                    estado.arma_idle(qh);
                } else {
                    // TRAVADO há SUSPEND_MIN: dorme de verdade (E60)
                    if estado.trava_armada && !casa_idle::inibidores_seguram() {
                        eprintln!(
                            "elite-daemon: vigília E60 — travado {}min, dormindo",
                            casa_idle::conf_vivo().suspend_min
                        );
                        let _ = std::process::Command::new("systemctl")
                            .arg("suspend")
                            .stdout(std::process::Stdio::null())
                            .stderr(std::process::Stdio::null())
                            .status();
                    }
                    notif.destroy();
                    estado.trava_armada = false;
                    estado.arma_idle(qh);
                }
            }
            // VOLTOU da inatividade (o input acordou): rearma o relógio
            idle_mod::ext_idle_notification_v1::Event::Resumed => {
                if !*suspende {
                    estado.trava_armada = false;
                }
                notif.destroy();
                estado.arma_idle(qh);
            }
            _ => {}
        }
    }
}

impl Dispatch<wayland_client::protocol::wl_seat::WlSeat, ()> for Estado {
    fn event(
        _estado: &mut Estado,
        _seat: &wayland_client::protocol::wl_seat::WlSeat,
        _event: wayland_client::protocol::wl_seat::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}
