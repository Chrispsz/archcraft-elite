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

// ── E150 — A VIGÍLIA REARMÁVEL DE FORA ────────────────────────────
// O ouvido externo (logind: PrepareForSleep(false) e Unlock) precisa
// RENASCER o relógio de idle sem esperar evento do compositor: o
// tempo DORMIDO contava como inatividade e o desktop acordava para
// travar na cara do dono. O CONTROLE vive aqui: o notifier/seat/qh
// registados pela despachante + o registro das notificações VIVAS —
// o reset desarma TODAS (destroy honesto, sem fóssil de objeto) e
// arma a do LOCK de novo. As requisições wayland são thread-safe
// (o backend trava sozinho); o flush acorda o fio na hora.
struct IdleCtl {
    notifier: idle_mod::ext_idle_notifier_v1::ExtIdleNotifierV1,
    seat: wayland_client::protocol::wl_seat::WlSeat,
    qh: QueueHandle<Estado>,
}

static IDLE_CTL: OnceLock<IdleCtl> = OnceLock::new();

/// o registro das notificações VIVAS (lock/off/suspend — quem arma,
/// registra; quem dispara, desarma a sua; quem reseta, desarma todas).
static IDLE_ARMAS: Mutex<Vec<idle_mod::ext_idle_notification_v1::ExtIdleNotificationV1>> =
    Mutex::new(Vec::new());

/// E150 — arma UMA notificação (timeout em ms; tipo 0=lock 1=off
/// 2=suspend) e registra no controle. Ok=false = sem despachante (o
/// daemon de teste/probe — a vigília mora na sessão de verdade).
fn arma_idle_ms(timeout_ms: u32, tipo: u8) -> bool {
    let Some(ctl) = IDLE_CTL.get() else { return false };
    let notif = ctl
        .notifier
        .get_idle_notification(timeout_ms, &ctl.seat, &ctl.qh, tipo);
    IDLE_ARMAS.lock().unwrap().push(notif);
    if let Some(sh) = SHARED.get() {
        let _ = sh.conn.flush();
    }
    true
}

/// E150 — O RESET DA VIGÍLIA (a porta do logind: acordou do sono OU o
/// hyprlock encerrou): desarma TUDO que contava (o sono não é
/// inatividade — o contador antigo travava a cara do dono no despertar)
/// e rearma a cadeia do LOCK do zero. Conf 0 (nunca sozinho) desarma
/// e cala — a escolha do dono é a lei.
pub fn reseta_idle() {
    if IDLE_CTL.get().is_none() {
        return; // sem despachante não há relógio (honesto)
    }
    {
        let mut armas = IDLE_ARMAS.lock().unwrap();
        for n in armas.drain(..) {
            n.destroy();
        }
    }
    let conf = casa_idle::conf_vivo();
    if conf.lock_min > 0 {
        arma_idle_ms(conf.lock_min * 60 * 1000, 0);
    }
}

/// desarma UMA notificação (o dono do evento desarma a sua — o registro
/// nunca aponta para objeto morto).
fn desarma_idle(notif: &idle_mod::ext_idle_notification_v1::ExtIdleNotificationV1) {
    let id = notif.id();
    IDLE_ARMAS.lock().unwrap().retain(|n| n.id() != id);
    notif.destroy();
}

/// Um toplevel vivo da sessão (o handle mora MUDO aqui dentro).
struct Rec {
    handle: tl_mod::zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1,
    app_id: String,
    title: String,
    minimized: bool,
    focused: bool,
    fullscreen: bool,
}

/// o lado compartilhado entre a despachante e as threads de verbo.
/// 1.0-110 T2 — O ESTADO ÚNICO DE JANELAS: `windows` e `mru` de era
/// eram DOIS Mutexes independentes — todo leitor pegava UM e DEPOIS o
/// outro (a corrida lista×MRU: a janela fechava ENTRE os dois locks e o
/// anel apontava para id sem Rec, ou o anel novo nascia com a lista
/// velha; o foca_player e o aprende_mesa fotografavam estados que
/// NUNCA existiram juntos). UM Mutex<Janelas> — todo leitor e todo
/// escritor pega o MESMO lock: a lista e o anel nunca divergem, o
/// snapshot do bus é UMA foto atômica.
struct Wl {
    conn: Connection,
    seat: wayland_client::protocol::wl_seat::WlSeat,
    janelas: Mutex<Janelas>,
}

/// 1.0-110 T2 — a tabela e o anel MORAM JUNTOS (a mesma foto).
#[derive(Default)]
struct Janelas {
    windows: HashMap<u32, Rec>,
    /// o anel MRU (índice 0 = a mais recentemente focada)
    mru: Vec<u32>,
}

static SHARED: OnceLock<Arc<Wl>> = OnceLock::new();

/// O ponto de vista do bus: os windows em ORDEM MRU (índice 0 = topo).
/// 1.0-100 — cada janela leva a MESA APRENDIDA (workspace::mesa_da_janela
/// — None quando a casa nunca a viu focar; o dock veste .other-workspace
/// só com mesa CONHECIDA ≠ a corrente: o desconhecido é presumido vivo).
pub fn windows_mru() -> Vec<WindowInfo> {
    let Some(sh) = SHARED.get() else { return Vec::new() };
    // 1.0-110 T2 — UM lock só: a lista e o anel são a MESMA foto (a
    // corrida lista×MRU morre com o estado único)
    let j = sh.janelas.lock().unwrap();
    j.mru
        .iter()
        .filter_map(|id| {
            j.windows.get(id).map(|r| WindowInfo {
                id: *id,
                app_id: r.app_id.clone(),
                title: if r.title.is_empty() { None } else { Some(r.title.clone()) },
                focused: r.focused,
                minimized: r.minimized,
                fullscreen: r.fullscreen,
                desk: crate::workspace::mesa_da_janela(*id),
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
        let j = sh.janelas.lock().unwrap();
        j.windows.get(&id).map(|r| r.handle.clone())
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
        // 1.0-110 T2 — UM lock: o anel e a lista na MESMA foto (o match
        // de era atravessava DOIS mundos que podiam divergir)
        let j = sh.janelas.lock().unwrap();
        j.mru.iter()
            .filter_map(|id| j.windows.get(id).map(|r| (*id, r)))
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
    // E150 — O NOTIFIER E O SEAT ATRAVESSAM O SPAWN: a era perdia os dois
    // no `..Default::default()` (a despachante nascia SEM o ouvido do
    // ext-idle-notify — a armação era um no-op eterno e a trava
    // automática da casa nunca armou de verdade; o pre-sleep do logind
    // era a única trava que o dono via). Agora a vigília nasce ARMADA.
    let notifier = estado.notifier.clone()?;
    let shared = Arc::new(Wl {
        conn: conn.clone(),
        seat: seat.clone(),
        janelas: Mutex::new(Janelas::default()),
    });
    SHARED.set(Arc::clone(&shared)).ok()?;
    let mut arma_inicial = true;
    std::thread::Builder::new()
        .name("elite-wayland".into())
        .spawn(move || {
            // E150 — o CONTROLE da vigília registra AQUI (notifier + seat
            // + qh): o reseta_idle de FORA (logind) arma por estes
            // punhos — as requisições são thread-safe e o flush acorda
            // a despachante.
            IDLE_CTL
                .set(IdleCtl {
                    notifier: notifier.clone(),
                    seat: seat.clone(),
                    qh: qh.clone(),
                })
                .ok();
            let mut estado = Estado {
                manager: Some(manager),
                seat: Some(seat),
                notifier: Some(notifier),
                ..Default::default()
            };
            loop {
                if crate::STOP.load(Ordering::SeqCst) {
                    return;
                }
                if arma_inicial {
                    arma_inicial = false;
                    reseta_idle();
                }
                match queue.blocking_dispatch(&mut estado) {
                    Ok(_) => {}
                    Err(e) => {
                        // 1.0-102 — O COMPOSITOR CAIU (EPIPE/Broken pipe,
                        // EOF, desconexão): o fio morria "honesto" e o
                        // CORPO seguia vivo segurando o session.lock — o
                        // audit 102 fotografou o relogin vazio (a sessão
                        // nova batia no flock do morto-vivo e saía 0). O
                        // erro do fio agora é a SENTENÇA da sessão: o
                        // fim_da_sessao acende o STOP, encerra os filhos
                        // gerenciados (bar, dock, swayosd, polkit,
                        // wallpaper, jogo), remove o session.lock do chão
                        // e finaliza (exit 0) — o relogin nasce LIMPO.
                        crate::fim_da_sessao(&format!("wayland dispatch {e}"));
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
    PULO_EM.store(crate::agora_ms(), Ordering::Relaxed);
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
        if pulo != 0 && crate::agora_ms().saturating_sub(pulo) < 1500 {
            let focada = {
                let Some(sh) = SHARED.get() else { return };
                let j = sh.janelas.lock().unwrap();
                j.mru.iter()
                    .filter_map(|id| j.windows.get(id).map(|r| (*id, r.focused)))
                    .find(|(_, focado)| *focado)
                    .map(|(id, _)| id)
            };
            if let Some(id) = focada {
                workspace::aprende(id);
            }
        }
    }

    // A VIGÍLIA mora no controle global (E150): `reseta_idle` arma a
    // cadeia com o conf VIVO de qualquer thread (o dono muda LOCK_MIN
    // no menu — o próximo reset/Resumed já obedece; o conf é barato de
    // ler, zero watcher). O método por-Estado morreu com o no-op da era
    // (o notifier nunca atravessava o spawn — ver start()).
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
            sh.janelas.lock().unwrap().windows.insert(id, Rec {
                handle: toplevel,
                app_id: String::new(),
                title: String::new(),
                minimized: false,
                focused: false,
                fullscreen: false,
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
                if let Some(r) = sh.janelas.lock().unwrap().windows.get_mut(id) {
                    r.app_id = app_id;
                }
            }
            E::Title { title } => {
                if let Some(r) = sh.janelas.lock().unwrap().windows.get_mut(id) {
                    r.title = title;
                }
            }
            // o estado vem como ARRAY DE BYTES (0=max 1=min 2=act 3=full)
            E::State { state } => {
                let mut min = false;
                let mut act = false;
                let mut full = false;
                for byte in state {
                    match byte {
                        1 => min = true,
                        2 => act = true,
                        3 => full = true,
                        _ => {}
                    }
                }
                let focou;
                {
                    // 1.0-110 T2 — UM lock: a flag, o anel MRU e a lista
                    // mudam JUNTOS (o estado único)
                    let mut j = sh.janelas.lock().unwrap();
                    let Some(r) = j.windows.get_mut(id) else { return };
                    let era_focado = r.focused;
                    r.minimized = min;
                    r.focused = act;
                    r.fullscreen = full;
                    focou = act && !era_focado;
                    if act {
                        // o anel MRU: quem ganha foco sobe para o TOPO
                        j.mru.retain(|x| *x != *id);
                        j.mru.insert(0, *id);
                    }
                }
                if focou {
                    estado.aprende_mesa();
                    // E150 — A GAVETA DESCE COM O PALCO: uma janela que
                    // GANHA foco com o nwg-drawer vivo = o dono escolheu
                    // outro endereço (alt-tab, dock, janela nova — o
                    // overlay da gaveta nunca fica por cima da casa). O
                    // drawer que lançou app já se foi sozinho (MainQuit
                    // nativo); o SIGTERM aqui só colhe quem ficou.
                    crate::gaveta_desce();
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
                    // 1.0-110 T2 — UM lock: a janela sai da lista E do
                    // anel no MESMO gesto (o fantasma do anel morto)
                    let mut j = sh.janelas.lock().unwrap();
                    j.windows.remove(id);
                    j.mru.retain(|x| *x != *id);
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

/// udata da notificação (E150 — a cadeia agora tem TRÊS tempos):
/// 0 = o LOCK (LOCK_MIN) · 1 = o APAGAR (OFF_MIN > LOCK_MIN — o gesto
/// separado da fábrica nova 5/10) · 2 = o SUSPEND de travado (E60).
impl Dispatch<idle_mod::ext_idle_notification_v1::ExtIdleNotificationV1, u8> for Estado {
    fn event(
        estado: &mut Estado,
        notif: &idle_mod::ext_idle_notification_v1::ExtIdleNotificationV1,
        event: idle_mod::ext_idle_notification_v1::Event,
        tipo: &u8,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        match event {
            idle_mod::ext_idle_notification_v1::Event::Idled => match tipo {
                0 => {
                    // A VIGÍLIA BATEU (LOCK_MIN): os inibidores de
                    // jogo/mídia seguram (a espera é a lei); sem eles:
                    // o LOCK agora — e o APAGAR no tempo DELE (OFF_MIN
                    // > LOCK_MIN = o gesto separado; igual = o MESMO
                    // instante, a lei E43 de sempre)
                    if casa_idle::inibidores_seguram() {
                        eprintln!(
                            "elite-daemon: idle batido — inibidores de jogo/mídia seguram (a trava espera — o retry de 30s renasce armado, 1.0-110)"
                        );
                        // 1.0-110 T3 — O RETRY DE 30s (a cadeia NUNCA
                        // para: de era o inibido só LOGAVA e DESARMAVA —
                        // o lock morria junto e o dono que pausasse o
                        // jogo/mídia ficava SEM vigília nenhuma até o
                        // próximo Resumed; o relógio de 30s re-julga o
                        // mundo a cada meia volta)
                        arma_idle_ms(30_000, 0);
                    } else {
                        let conf = casa_idle::conf_vivo();
                        if conf.off_min > conf.lock_min {
                            casa_idle::trava();
                            // o próximo tempo: o APAGAR sozinho — armado com
                            // o QUE FALTA (E106/5a: o tipo-1 nasce no instante
                            // LOCK_MIN de idleness; armado com o tempo inteiro
                            // disparava LOCK_MIN TARDE — o protocolo conta da
                            // ARMAÇÃO, o alvo conta do ÚLTIMO INPUT)
                            arma_idle_ms(casa_idle::faltam_ms(conf.off_min, conf.lock_min), 1);
                        } else {
                            casa_idle::trava_e_apaga();
                        }
                        estado.trava_armada = true;
                        // o degrau de sempre: SUSPEND_MIN de travado (E60) — o
                        // MESMO juízo do tipo-1: armado com o QUE FALTA, o sono
                        // acontece aos SUSPEND_MIN de OCIOSIDADE (a semântica
                        // swayidle da casa — LOCK/SUSPEND do MESMO zero; o
                        // rig provou: SUSPEND_MIN=20 com LOCK_MIN=10 nunca
                        // dormia aos 20min)
                        if conf.suspend_min > 0 {
                            arma_idle_ms(casa_idle::faltam_ms(conf.suspend_min, conf.lock_min), 2);
                        }
                    }
                    desarma_idle(notif);
                    // NÃO rearma o LOCK aqui: o timer já passou do
                    // limite — a rearmação nasce do RESUMED (o input do
                    // dono zera o relógio do compositor) ou do reset
                    // externo (E150); rearmar no Idled seria o loop
                    // imediato do lock na cara do dono.
                }
                1 => {
                    // OFF_MIN bateu (o gesto separado): a tela apaga — o
                    // lock já está de pé desde o LOCK_MIN
                    casa_idle::apaga();
                    desarma_idle(notif);
                }
                _ => {
                    // TRAVADO há SUSPEND_MIN: dorme de verdade (E60) —
                    // 1.0-110 T3: o inibido REARMA o retry de 30s COM
                    // a trava viva (de era só desarmava calado: a
                    // cadeia MORRIA no inibidor — o dono que pausasse
                    // a mídia travado nunca mais dormia)
                    if estado.trava_armada && casa_idle::inibidores_seguram() {
                        eprintln!(
                            "elite-daemon: vigília E60 — travado, inibidores seguram o sono (o retry de 30s mantém a trava armada — 1.0-110)"
                        );
                        arma_idle_ms(30_000, 2);
                        desarma_idle(notif);
                        return; // trava_armada MANTIDA — a cadeia segue
                    }
                    if estado.trava_armada {
                        eprintln!(
                            "elite-daemon: vigília E60 — travado {}min, dormindo",
                            casa_idle::conf_vivo().suspend_min
                        );
                        // 1.0-110 T3 — A SUSPENSÃO NATIVA (o fork do
                        // systemctl morre: o journalctl -b -u
                        // systemd-logind de era registrava ZERO chamadas
                        // de suspensão — o verbo login1.Manager.Suspend
                        // desce pela conexão COMPARTILHADA, com o hyprlock
                        // DESACOPLADO e MAPEADO antes do freeze)
                        casa_idle::suspende();
                    }
                    desarma_idle(notif);
                    estado.trava_armada = false;
                }
            },
            // VOLTOU da inatividade (o input acordou): o relógio do
            // compositor zera — a cadeia RENASCE inteira do LOCK (o
            // reset desarma o resto que contava velho)
            idle_mod::ext_idle_notification_v1::Event::Resumed => {
                if *tipo == 0 {
                    estado.trava_armada = false;
                }
                desarma_idle(notif);
                reseta_idle();
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
