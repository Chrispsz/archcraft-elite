// ELITE · craft-dock-rs — ui.rs (E132). A camada GTK4 + gtk4-layer-shell
// da dock. Este módulo SÓ compila com a feature "gui" (exige o GTK dev
// do ambiente de build do pacote — o CI valida; o sandbox sem GTK
// compila/testa o NÚCLEO: icons/procapp/sock/main).
//
// O QUE ESTÁ PORTADO DO craft-dock-gui (e onde mora cada peça):
//   · a GEOMETRIA layer-shell (Python: ancorada SÓ na base — a
//     superfície TEM o tamanho da pílula, nada de faixa invisível
//     full-width comendo clique; zona exclusiva AUTOMÁTICA para as
//     maximizadas/tileadas). DIVERGÊNCIA HONESTA nomeada: a ordem
//     deste degrau pediu Layer::TOP + teclado on-demand (o Python usa
//     Layer::BOTTOM — com BOTTOM a tela cheia do app COBRE a dock).
//     O selo é de quem ordenou; se o rig reclamar do fullscreen, é
//     trocar UMA constante aqui;
//   · a leitura ASSÍNCRONA do toplevel.sock (a ordem do dono): UMA
//     thread de fundo é a DONA do socket — conecta, faz o handshake
//     "EVT ON" (E38, push com latência ~0) e serve o LIST de segurança
//     de 5s; a UI acorda por um canal mpsc drenado num idle de 200ms
//     (thread NUNCA toca GTK — a lei da casa);
//   · a gramática UMA do clique (v2.10.10): esquerdo foca/cicla (1
//     janela do app E ela é a FOCADA = MINIMIZA, o toggle E89) ·
//     direito NOVA SESSÃO (o Exec do .desktop; no raw, o argv[0]
//     PROVADO no /proc) · meio encerra (CLOSE por id, STRICT E36 — o
//     título nunca manda WM_DELETE);
//   · E71: A PROVA NO LANÇAMENTO (uma LIST FRESCA julga antes de
//     abrir — janela que apareceu agora é FOCADA, não duplicada), o
//     GUARD de 8s no gargalo único e o MAP que aposenta o guard (E88);
//   · E134: A SINCRONIZAÇÃO IMEDIATA com o snapshot real: a graça do
//     vazio E71 (LIST vazio segurado 2 rodadas) APOSENTADA — o
//     indicador preso após fechar janelas transitórias morreu com ela;
//   · a cadeia de ícones E130/E132 COMPLETA (tema com fold → steam →
//     Gear Lever → cache sha256 → .DirIcon do mount vivo → EXTRAÇÃO
//     EM THREAD com apply via canal → glifo honesto) e o ícone OFICIAL
//     dos EXPORTS do Flatpak (a busca em arquivo cobre /var/lib/
//     flatpak/exports/share/icons e ~/.local/share/flatpak/exports/
//     share/icons — a ordem do dono);
//   · os dinâmicos (comm→.desktop pelo índice COM as chaves
//     reverse-DNS — o io.github.kolunmi.Bazaar resolve como "bazaar",
//     nome "Bazaar", ícone oficial, NUNCA raw), os RAW com a denylist
//     E106 e o indicador "running" pela JANELA REAL (v2.10.3);
//   · SIGUSR1 (W-S-d toggle) e SIGUSR2 (reload dos pins): a glib 0.22
//     NÃO tem unix_signal_add — o handler cru (libc::signal + atomic
//     async-signal-safe) escreve a bandeira e o idle de 200ms drena
//     (latência ≤200ms, documentada);
//   · os pins são RE-LIDOS a cada tick e a pílula só remonta quando o
//     CONJUNTO muda (o craft-pin add/rm reflete no tick seguinte mesmo
//     sem sinal — a rede a mais que o Python não tinha).
//
// ESCOPO HONESTO DESTA v1 (o que FALTA, nomeado — ver main.rs também):
//   ✗ o MENU E74 do direito (craft-menu/fuzzel): o direito é o verbo
//     DIRETO "nova sessão" — sem menu contextual nesta v1;
//   ✗ o FALLBACK wlrctl (daemon morto = /proc + wlrctl): sem
//     craft-toplevel os verbos de foco/fecho ficam sem rede NESTA v1
//     (E134: o craft-dock-gui PYTHON saiu do pacote — sem fallback
//     por desenho; o respawn do craft-bars cobre o daemon em ≤5s);
//   ✗ a E101 completa (a graça de 3s da classe daemonizada): o guard
//     aposenta no MAP, no expiry de 8s ou na morte do lançador — sem
//     o meio-tempo recursivo do Python;
//   ✗ a transição suave v2.11 (GtkRevealer) e a higiene E129 de
//     pixbufs (a GTK4 usa texturas próprias — o leak da GTK3 não se
//     aplica igual, mas a animação de entrada/saída falta);
//   ✗ o indicador com daemon MORTO (o _fallback_alive do /proc): com
//     o daemon morto o indicador fica APAGADO nesta v1 (honesto — não
//     é a mentira de acender sem janela).
use crate::{appicon_cache_dir, css_path, icons, log, pins_path, procapp, read_pins, sock,
            toplevel_sock, VERSION};
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::rc::Rc;
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::mpsc::{Receiver, Sender, TryRecvError};
use std::time::{Duration, Instant};

use gtk4::prelude::*;
use gtk4::{gdk, glib};
// E-auditoria 2026-11-22 (a cura do Canal 44945339468): o crate gtk4 0.11
// NÃO re-exporta um módulo `gtk` — os widgets moram na RAIZ do crate; o
// alias abaixo mantém os ~120 caminhos `gtk::` do corpo intactos.
use gtk4 as gtk;
// E-auditoria: o gtk4-layer-shell 0.8 NÃO expõe funções livres — a API
// é o trait LayerShell (init_layer_shell/set_layer/set_anchor/...) e o
// is_supported continua função livre (re-export da raiz).
use gtk4_layer_shell::LayerShell;

/// Escala fixa de fábrica (spec M3.2 — o mesmo 36 do Python).
const ICON_SIZE: i32 = 36;
/// O float da pílula DENTRO da superfície (margem GTK — a zona
/// exclusiva cobre pílula + vão).
const PILL_FLOAT: i32 = 6;
/// O tick de segurança (o push EVT domina a latência; 5s = scan /proc
/// + ceifa + reload dos pins — o mesmo desenho v2.10.26 do Python).
const TICK_S: u64 = 5;
/// O dreno do canal da thread de fundo (e da bandeira de sinais).
const DRAIN_MS: u64 = 200;
/// E71 — o guard do lançamento em voo (o vão até a janela mapear).
const GUARD_S: f64 = 8.0;

// Linux x86-64 (o alvo da ISO): a glib 0.22 não traz unix_signal_add —
// o handler cru é a via (atomic async-signal-safe, drenado no idle).
const SIGUSR1: i32 = 10;
const SIGUSR2: i32 = 12;

static SIG: AtomicI32 = AtomicI32::new(0);
extern "C" fn on_signal(sig: i32) {
    SIG.store(sig, Ordering::SeqCst);
}

/// As mensagens da thread de fundo para a UI (canal mpsc — a thread
/// NUNCA toca GTK; a UI drena no idle de 200ms).
enum Msg {
    /// Um LIST respondido (None = transporte morto — a graça decide).
    Snapshot(Option<sock::Snapshot>),
    /// A extração em thread terminou: o ícone do raw está no cache.
    IconReady { key: String, path: PathBuf },
}

/// O alvo dos cliques de um botão: um app COM .desktop (pin/dinâmico)
/// ou um SEM-NOME (raw — AppImage/Steam sem .desktop instalado).
#[derive(Clone)]
enum Act {
    App {
        hint: String,
        did: String,
        cmd: String,
        cands: Vec<String>,
        name: String,
    },
    /// O SEM-NOME (AppImage sem .desktop): a chave é o stem do app_id.
    Raw { key: String, name: String },
}

struct PinRow {
    button: gtk::Button,
    act: Act,
}

struct RawRow {
    button: gtk::Button,
    image: gtk::Image,
}

/// O estado da dock (uma célula Rc<RefCell> na main thread — os
/// closures dos gestos clonam o Rc; NADA disto é Send).
struct State {
    window: gtk::ApplicationWindow,
    pill: gtk::Box,
    shown: bool,
    tx: Sender<Msg>,
    // pins: os fixados (dock-pins, NA ORDEM do arquivo) · dyns/raws:
    // os dinâmicos por desktop-id e os SEM-NOME por chave de app_id
    pins: Vec<PinRow>,
    dyns: HashMap<String, PinRow>,
    raws: HashMap<String, RawRow>,
    entries: Vec<icons::DesktopEntry>,
    index: HashMap<String, usize>,
    pin_ids: HashSet<String>,
    pins_txt: String,
    // o snapshot da sessão (a JANELA é a verdade — v2.10.3)
    snap: sock::Snapshot,
    tl_alive: bool,
    last_act: HashMap<String, u64>,
    launching: HashMap<String, Instant>,
    children: Vec<(std::process::Child, Option<String>)>,
    home: PathBuf,
    uid: u32,
}

pub fn run() -> i32 {
    let app = gtk::Application::new(Some("elite.craft.Dock"), Default::default());
    app.connect_activate(|app| build(app));
    app.run().get() as i32
}

fn build(app: &gtk::Application) {
    if !gtk4_layer_shell::is_supported() {
        // o labwc fala layer-shell; se isto aparecer, a sessão mudou.
        // E134: o craft-dock-gui Python foi APOSENTADO — não há fallback;
        // a dock sai com a verdade no papel (o respawn do craft-bars
        // re-tenta em ≤5s; sessão sem layer-shell não é a casa)
        log(&format!(
            "craft-dock-rs {VERSION}: o compositor NÃO fala layer-shell — \
             saindo (a dock da casa É esta; sem fallback por desenho E134)"
        ));
        return;
    }
    // E-auditoria 2026-11-22 (2ª camada da cura): o ApplicationWindow::new
    // do gtk4 0.11 toma &impl IsA<Application> — o Option<&App> do gtk3
    // era a API morta que a resolução abortada do 1º round escondeu.
    let window = gtk::ApplicationWindow::new(app);
    window.set_widget_name("dockwindow");
    // A GEOMETRIA da casa (Python v2.3.4): ancorada SÓ na base — a
    // layer-shell centra no eixo não-ancorado e a superfície TEM o
    // tamanho da pílula (nada de faixa invisível full-width comendo
    // clique ao lado dela). Zona exclusiva AUTOMÁTICA: maximizadas/
    // tileadas respeitam a faixa ("como funciona as outras distros").
    // DIVERGÊNCIA nomeada no cabeçalho: Layer::Top (a ordem deste
    // degrau) em vez do BOTTOM do Python.
    window.init_layer_shell();
    window.set_layer(gtk4_layer_shell::Layer::Top);
    window.set_anchor(gtk4_layer_shell::Edge::Bottom, true);
    window.auto_exclusive_zone_enable();
    window.set_keyboard_mode(gtk4_layer_shell::KeyboardMode::OnDemand);
    window.set_namespace(Some("craft-dock"));

    let pill = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    pill.set_widget_name("dockbox");
    pill.set_margin_bottom(PILL_FLOAT);
    window.set_child(Some(&pill));

    // o índice de .desktops (com os EXPORTS do Flatpak e as chaves
    // reverse-DNS — o "bazaar" do io.github.kolunmi.Bazaar.desktop)
    let home = crate::home_dir();
    let mut entries = Vec::new();
    for dir in icons::desktop_dirs(&home) {
        entries.extend(icons::scan_desktop_dir(&dir));
    }
    let index = icons::desktop_index(&entries);
    log(&format!("índice de .desktops: {} chave(s) resolvíveis", index.len()));

    // o canal da thread de fundo (a leitura ASSÍNCRONA do toplevel.sock)
    // E-auditoria 2026-11-22 (3ª camada): o tx.clone() DENTRO da closure
    // movia o tx e o Estado de baixo o usava de novo (E0382) — o clone
    // nasce ANTES do spawn e a thread fica com a cópia dona.
    let (tx, rx) = std::sync::mpsc::channel::<Msg>();
    let tx_bg = tx.clone();
    std::thread::spawn(move || bg_reader(toplevel_sock(), tx_bg));

    let st = Rc::new(RefCell::new(State {
        window,
        pill,
        shown: true,
        tx,
        pins: Vec::new(),
        dyns: HashMap::new(),
        raws: HashMap::new(),
        entries,
        index,
        pin_ids: HashSet::new(),
        pins_txt: String::new(),
        snap: sock::Snapshot::default(),
        tl_alive: false,
        last_act: HashMap::new(),
        launching: HashMap::new(),
        children: Vec::new(),
        home,
        uid: procapp::current_uid(),
    }));

    // os sinais da casa (W-S-d toggle · reload dos pins)
    unsafe {
        libc::signal(SIGUSR1, on_signal as libc::sighandler_t);
        libc::signal(SIGUSR2, on_signal as libc::sighandler_t);
    }

    rebuild_pins(&st);
    load_css();
    st.borrow().window.show();

    log(&format!(
        "craft-dock-rs {VERSION} iniciada: {} pin(s) · leitura ASSÍNCRONA do \
         toplevel.sock (thread de fundo + EVT push + tick de 5s) · cadeia de \
         ícones E130/E132 ON (Flatpak reverse-DNS + Gear Lever + cache + \
         .DirIcon + extração em thread) · Layer::Top com teclado on-demand \
         (a ordem do degrau — o Python usa BOTTOM) · o ESCOPO HONESTO mora \
         no cabeçalho deste arquivo",
        st.borrow().pins.len(),
    ));

    // o dreno do canal + a bandeira de sinais (200ms — latência do
    // push EVT e do W-Sd, documentada)
    {
        let st = st.clone();
        glib::timeout_add_local(Duration::from_millis(DRAIN_MS), move || {
            drain(&st, &rx);
            glib::ControlFlow::Continue
        });
    }
    // o tick de segurança (5s): ceifa, guard, pins, dinâmicos, raws,
    // indicadores (o scan /proc NÃO tem evento no kernel — é o preço).
    {
        let st = st.clone();
        glib::timeout_add_seconds_local(TICK_S as u32, move || {
            poll_tick(&st);
            glib::ControlFlow::Continue
        });
    }
}

// ── a THREAD DE FUNDO — a dona do toplevel.sock ───────────────────────

/// A leitura ASSÍNCRONA (a ordem do dono): mantém a conexão, o
/// handshake EVT (E38 — push com latência ~0) e o LIST de segurança de
/// 5s. NUNCA toca GTK: tudo via canal mpsc. Morreu o daemon? O próximo
/// giro reconecta — a dock NUNCA depende dele (a lei v2.10.3).
fn bg_reader(sock_path: PathBuf, tx: Sender<Msg>) {
    let mut evt: Option<std::os::unix::net::UnixStream> = None;
    let mut last_list = Instant::now()
        .checked_sub(Duration::from_secs(TICK_S + 1))
        .unwrap_or_else(Instant::now);
    // E135 — O BACKOFF DA RECONEXÃO (a ordem do dono: o fallback lento
    // morre — a reconexão é exponencial 5ms → 20ms → 100ms, teto na
    // lei; daemon vivo de volta = canal EVT vivo em ≤100ms)
    let mut back = 5u64;
    loop {
        // (re)conecta o canal de eventos — daemon ausente custa o backoff
        if evt.is_none() {
            match std::os::unix::net::UnixStream::connect(&sock_path) {
                Ok(mut s) => {
                    if sock::evt_handshake(&mut s) {
                        let _ = s.set_read_timeout(Some(Duration::from_millis(200)));
                        evt = Some(s);
                        back = 5;
                    }
                }
                Err(_) => {
                    std::thread::sleep(Duration::from_millis(back));
                    back = (back * 4).min(100);
                }
            }
        }
        let mut forced = false;
        if let Some(s) = evt.as_mut() {
            let mut buf = [0u8; 4096];
            match std::io::Read::read(s, &mut buf) {
                Ok(0) | Err(_) => {
                    evt = None; // caiu: o backoff seguinte reconecta
                    std::thread::sleep(Duration::from_millis(back));
                    back = (back * 4).min(100);
                }
                Ok(n) => {
                    if sock::is_event(&buf[..n]) {
                        forced = true; // mudança de janelas: LIST NA HORA
                    }
                }
            }
        }
        if last_list.elapsed() >= Duration::from_secs(TICK_S) || forced {
            let msg = match sock::ToplevelClient::connect(&sock_path)
                .as_mut()
                .and_then(|c| c.list())
            {
                Some(snap) => Msg::Snapshot(Some(snap)),
                None => Msg::Snapshot(None), // transporte morto (a graça decide)
            };
            if tx.send(msg).is_err() {
                return; // a UI morreu: a thread vai junto
            }
            last_list = Instant::now();
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}

/// O dreno (idle de 200ms): aplica snapshots, ícones extraídos em
/// thread e a bandeira dos sinais (SIGUSR1 toggle · SIGUSR2 reload).
fn drain(st: &Rc<RefCell<State>>, rx: &Receiver<Msg>) {
    loop {
        match rx.try_recv() {
            Ok(Msg::Snapshot(opt)) => {
                let mut s = st.borrow_mut();
                apply_snapshot(&mut s, opt);
                update_indicators(&s);
                drop(s); // (o sync_dynamic pede o estado emprestado DE NOVO)
                sync_dynamic(st);
                // E135 — O FLUSH SÍNCRONO (a ordem do dono: toda ação de
                // UI de pílula/indicadores completa NO MESMO ciclo): o
                // layout é requeado e o display é drenado aqui — a
                // surface layer-shell commita a nova largura no frame
                // corrente, zero retângulo residual do frame velho.
                st.borrow().pill.queue_resize();
                if let Some(d) = gdk::Display::default() {
                    d.flush();
                }
            }
            Ok(Msg::IconReady { key, path }) => {
                // o botão vivo ganha a cara nova (idle = main thread)
                let s = st.borrow();
                if let Some(row) = s.raws.get(&key) {
                    row.image.set_from_file(Some(&path));
                    row.image.set_pixel_size(ICON_SIZE);
                    log(&format!(
                        "raw ícone: '{key}' EXTRAÍDO em thread para o cache ({})",
                        path.display()
                    ));
                }
            }
            Err(TryRecvError::Empty) | Err(TryRecvError::Disconnected) => break,
        }
    }
    // os sinais da casa (a bandeira atômica do handler cru)
    match SIG.swap(0, Ordering::SeqCst) {
        SIGUSR1 => {
            let mut s = st.borrow_mut();
            if s.shown {
                s.window.hide();
                s.shown = false;
                log("toggle: dock escondida (W-S-d)");
            } else {
                s.window.show();
                s.shown = true;
                log("toggle: dock visível (W-S-d)");
            }
        }
        SIGUSR2 => rebuild_pins(st),
        _ => {}
    }
}

/// E134 — A SINCRONIZAÇÃO IMEDIATA COM O SNAPSHOT REAL: a graça do
/// vazio E71 (o LIST vazio segurado 2 rodadas) e a graça do snapshot
/// morto (o miss segurado 2) foram APOSENTADAS pela ordem do dono
/// (dump 1.0-80): o indicador de app ficava PRESO quando janelas
/// transitórias fechavam — o botão seguia "aberto" depois do fecho
/// porque a dock segurava o snapshot velho POR DESENHO. O snapshot do
/// craft-toplevel é a FONTE: o que ele diz É o estado, na hora —
/// janela que fechou, indicador que apaga no mesmo frame do evento
/// (o canal EVT entrega o LIST fresco com latência ~0; o tick de 5s
/// é a rede de segurança). Socket morto = sessão sem janelas
/// conhecidas: indicadores apagados, tl_alive falso (a dock segue
/// VIVA — o respawn do craft-bars a devolve ao ar em ≤5s).
fn apply_snapshot(s: &mut State, opt: Option<sock::Snapshot>) {
    match opt {
        Some(snap) => {
            if snap.windows.is_empty() && !s.snap.windows.is_empty() {
                log("toplevel: LIST vazio — snapshot zerado NA HORA (o fecho de janela vale no frame do evento, sem graça)");
            }
            s.snap = snap;
            s.tl_alive = true;
        }
        None => {
            if s.tl_alive && !s.snap.windows.is_empty() {
                log("toplevel: LIST falhou — snapshot zerado (o transporte morto não segura indicador)");
            }
            s.snap = sock::Snapshot::default();
            s.tl_alive = false;
        }
    }
}

/// O TICK de 5s (segurança — o push EVT domina a latência): ceifa os
/// filhos, aposenta os guards mapeados, EXPIRA os guards velhos,
/// re-lê os pins (a rede que o Python não tinha) e sincroniza tudo.
fn poll_tick(st: &Rc<RefCell<State>>) {
    {
        let mut s = st.borrow_mut();
        reap_children(&mut s);
        // E88 — o MAP libera o guard: a janela APARECEU = o vão acabou
        if !s.launching.is_empty() && !s.snap.windows.is_empty() {
            let mapped: Vec<String> = s
                .launching
                .keys()
                .filter(|k| sock::key_mapped(&s.snap, k))
                .cloned()
                .collect();
            for k in mapped {
                s.launching.remove(&k);
                log(&format!("guard aposentado: {k} mapeou — clique é foco imediato"));
            }
        }
        // E71 — os lançamentos em voo EXPIRAM (8s): mapeou ou falhou,
        // o guard se aposenta e o estado não acumula chave morta.
        let now = Instant::now();
        s.launching
            .retain(|k, t| now.duration_since(*t).as_secs_f64() < GUARD_S);
    }
    // os pins: re-leitura por tick — o CONJUNTO muda, a pílula remonta
    let txt = std::fs::read_to_string(pins_path()).unwrap_or_default();
    if txt != st.borrow().pins_txt {
        rebuild_pins(st);
    }
    sync_dynamic(st);
    let s = st.borrow();
    update_indicators(&s);
}

/// A ceifa dos zumbis (v2.10.3): todo app lançado pela dock é filho
/// DELA; saído sem colheita vira zumbi com comm vivo no /proc — o
/// indicador "continuava" depois do fecho. E88: a morte sem mapear
/// LIBERA o clique na hora. A E101 (a graça de 3s da classe
/// daemonizada — o lançador morre rc=0 e a janela mapeia DEPOIS) é
/// NOMEADA como não portada: a LIST fresca na morte cobre a corrida
/// vencida; a não-vencida libera o guard (o meio-tempo falta).
fn reap_children(s: &mut State) {
    let mut vivos = Vec::new();
    for (mut child, key) in s.children.drain(..) {
        match child.try_wait() {
            Ok(Some(_)) => {
                if let Some(k) = &key {
                    // E101 (1) — a LIST fresca: mapeou na corrida?
                    let mapped = sock::ToplevelClient::connect(&toplevel_sock())
                        .as_mut()
                        .and_then(|c| c.list())
                        .map(|snap| sock::key_mapped(&snap, k))
                        .unwrap_or(false);
                    if mapped {
                        log(&format!(
                            "guard aposentado: {k} mapeou (a LIST fresca da morte \
                             do lançador) — clique é foco imediato"
                        ));
                        continue; // (o guard segue — o MAP do tick aposenta)
                    }
                    s.launching.remove(k);
                    log(&format!(
                        "guard liberado: {k} morreu sem mapear (E88; a graça de \
                         3s da E101 é degrau seguinte — nomeada, não fingida)"
                    ));
                }
            }
            _ => vivos.push((child, key)),
        }
    }
    s.children = vivos;
}

// ── os PINS e a pílula ────────────────────────────────────────────────

/// Os PINS: re-lê o dock-pins (1 desktop-id por linha, 2ª coluna =
/// hint de app_id, '#' é comentário), resolve cada id no índice e
/// cria os botões NA ORDEM DO ARQUIVO. Pin sem .desktop é ignorado
/// com log (a lei da run #93: pin ruim NUNCA derrubou a dock).
fn rebuild_pins(st: &Rc<RefCell<State>>) {
    let txt = std::fs::read_to_string(pins_path()).unwrap_or_default();
    // 1ª passada (borrow curto): resolve os entries — os botões nascem
    // FORA do borrow (make_app_button pede o estado emprestado).
    let mut resolved: Vec<(icons::DesktopEntry, String)> = Vec::new();
    {
        let s = st.borrow();
        for pin in read_pins(&pins_path()) {
            let hit = icons::resolve_desktop(&s.index, &s.entries, &pin.desktop_id)
                .or_else(|| {
                    // o id exato (com .desktop) também é chave do índice
                    s.index
                        .get(&icons::fold(&pin.desktop_id))
                        .map(|i| &s.entries[*i])
                })
                .cloned();
            match hit {
                Some(e) => resolved.push((e, pin.hint)),
                None => {
                    log(&format!("pin ignorado (desktop inexistente): {}", pin.desktop_id))
                }
            }
        }
    }
    // 2ª passada: os botões (cada um com o seu gesto e o seu Act)
    let mut rows: Vec<PinRow> = Vec::new();
    let mut pin_ids = HashSet::new();
    for (entry, hint) in resolved {
        let btn = make_app_button(st, &entry, &hint);
        pin_ids.insert(entry.id.clone());
        rows.push(PinRow {
            button: btn,
            act: Act::App {
                hint,
                did: entry.id.clone(),
                cmd: icons::exec_ready(&entry),
                cands: icons::focus_candidates(&entry, ""),
                name: entry.name.clone(),
            },
        });
    }
    let mut s = st.borrow_mut();
    s.pins = rows;
    s.pin_ids = pin_ids;
    s.pins_txt = txt;
    repack(&s);
    let n = s.pins.len();
    s.window.show();
    log(&format!("pins remontados: {n} fixado(s)"));
}

/// A pílula REMONTA em ordem canônica (pins · fio · dinâmicos · raws)
/// — SÓ quando o conjunto muda (zero remontagem por tick; a lei
/// v2.10.0 do diff-guard na forma que a GTK4 simplifica: widgets são
/// REORDENADOS, nunca recriados — o flicker da recriação é o que o
/// dono rejeitou). A transição ANIMADA v2.11 é degrau seguinte.
fn repack(s: &State) {
    let pill = &s.pill;
    // solta todos (os widgets vivem nas maps — só a ORDEM muda)
    let kids: Vec<gtk::Widget> = std::iter::successors(pill.first_child(), |w| w.next_sibling())
        .collect();
    for w in kids {
        pill.remove(&w);
    }
    for row in &s.pins {
        pill.append(&row.button);
    }
    if !s.dyns.is_empty() || !s.raws.is_empty() {
        // o fio só existe quando há os dois lados (v2.10.9: raw também
        // mora do lado direito do fio)
        let sep = gtk::Separator::new(gtk::Orientation::Vertical);
        sep.set_widget_name("dynsep");
        sep.set_margin_top(8);
        sep.set_margin_bottom(8);
        pill.append(&sep);
    }
    for did in sorted_keys(&s.dyns) {
        pill.append(&s.dyns[&did].button);
    }
    for key in sorted_keys(&s.raws) {
        pill.append(&s.raws[&key].button);
    }
    pill.show();
}

/// As chaves de uma map de linhas, ORDENADAS (a ordem canônica da
/// casa: a remontagem é estável tick a tick).
fn sorted_keys<V>(m: &HashMap<String, V>) -> Vec<String> {
    let mut ks: Vec<String> = m.keys().cloned().collect();
    ks.sort();
    ks
}

/// O botão de um app COM .desktop (pin ou dinâmico — a gramática é UMA
/// desde a v2.10.10): ícone, tooltip que ENSINA os verbos, gestos.
fn make_app_button(st: &Rc<RefCell<State>>, entry: &icons::DesktopEntry, hint: &str) -> gtk::Button {
    let btn = gtk::Button::new();
    btn.set_has_frame(false);
    btn.set_widget_name("dockbtn");
    let img = app_icon_image(st, entry);
    btn.set_child(Some(&img));
    let name = if entry.name.is_empty() { entry.id.clone() } else { entry.name.clone() };
    btn.set_tooltip_text(Some(&format!(
        "{name} — esquerdo: focar/abrir · direito: nova sessão · meio: encerrar programa"
    )));
    let act = Act::App {
        hint: hint.to_string(),
        did: entry.id.clone(),
        cmd: icons::exec_ready(entry),
        cands: icons::focus_candidates(entry, hint),
        name,
    };
    wire_clicks(st, &btn, act);
    btn
}

/// O ícone de um app COM .desktop — a cadeia da casa para os que TÊM
/// identidade: (1) caminho ABSOLUTO do Icon= quando existe em disco;
/// (2) o TEMA do GTK (o Papirus-Dark da casa); (3) a BUSCA EM ARQUIVO
/// nas raízes E132 (os exports do Flatpak system+user — o ícone
/// OFICIAL do Flatpak mora lá — /usr/share/icons, o Gear Lever
/// ~/.local/share/icons e o pixmaps); (4) o glifo honesto. Os nomes
/// consultados: o Icon= E as alternativas REVERSE-DNS do id (o id
/// COMPLETO é o nome oficial de ícone do Flatpak).
fn app_icon_image(st: &Rc<RefCell<State>>, entry: &icons::DesktopEntry) -> gtk::Image {
    let img = gtk::Image::new();
    img.set_pixel_size(ICON_SIZE);
    if !entry.icon.is_empty() {
        let p = Path::new(&entry.icon);
        if p.is_absolute() && p.is_file() {
            img.set_from_file(Some(p));
            return img;
        }
    }
    let display = match gdk::Display::default() {
        Some(d) => d,
        None => {
            log("sem display GDK — o glifo honesto entra");
            img.set_icon_name(Some("application-x-executable"));
            return img;
        }
    };
    let theme = gtk::IconTheme::for_display(&display);
    let home = st.borrow().home.clone();
    let mut names: Vec<String> = Vec::new();
    if !entry.icon.is_empty() {
        names.extend(icons::theme_icon_candidates(&entry.icon));
    }
    names.extend(icons::reverse_dns_alternates(&entry.id));
    for n in &names {
        if theme.has_icon(n) {
            img.set_icon_name(Some(n));
            return img;
        }
    }
    // a busca em arquivo: os EXPORTS do Flatpak e o Gear Lever (E132)
    let roots = icons::icon_roots(&home);
    for n in &names {
        if let Some(hit) = icons::find_icon_file(n, &roots) {
            img.set_from_file(Some(&hit));
            return img;
        }
    }
    // o glifo honesto: sem ícone real, a promessa é a verdade
    img.set_icon_name(Some("application-x-executable"));
    img
}

/// O botão do SEM-NOME (raw — AppImage/Steam sem .desktop): a CADEIA
/// E130 COMPLETA, 1:1 do Python E126/E130:
///   (1) o TEMA com as variantes fold ('_'↔'-' da casa);
///   (2) o STEAM (steam_app_<id> → steam_icon_<id> / steam);
///   (3) o que o GEAR LEVER já extraiu (~/.local/share/icons + o
///       Icon= do .desktop de usuário) e a BUSCA nas raízes E132;
///   (4) o CACHE da casa (~/.cache/elite/appimage-icons/<sha256-do-
///       caminho> — o lugar que a era Python usava; rigs conservam);
///   (5) o .DirIcon do mount VIVO (o squashfs montado é legível —
///       vale mesmo sob --no-sandbox, o /proc/exe aponta para dentro);
///   (6) a EXTRAÇÃO EM THREAD de fundo (a UI não bloqueia no walk do
///       squashfs): o .DirIcon/maior PNG vai para o cache PERSISTENTE
///       e o botão vivo ganha a cara via canal (o dreno no idle aplica);
///   (6a) E133 — WINE/PROTON: o .exe do cmdline → o cache exe-icons
///       da casa → os caches de jogo (Steam/Lutris/Heroic/Hydra) → o
///       ícone adjacente → a extração do recurso PE em THREAD;
///   (6b) E133 — BINÁRIO CUSTOM (Electron/Snap/Nix/portable): o ícone
///       adjacente ao /proc/<pid>/exe (as raízes por nome — pixmaps e
///       ~/.local/share/icons incluídos — já caíram nos passos acima);
///   (7) o GLIFO honesto — sem NADA de verdade, a promessa é essa.
fn make_raw_button(st: &Rc<RefCell<State>>, key: &str, name: &str) -> gtk::Button {
    let btn = gtk::Button::new();
    btn.set_has_frame(false);
    btn.set_widget_name("dockbtn");
    let img = gtk::Image::new();
    img.set_pixel_size(ICON_SIZE);

    let display = gdk::Display::default().expect("sem display GDK");
    let theme = gtk::IconTheme::for_display(&display);
    let (home, uid, tx) = {
        let s = st.borrow();
        (s.home.clone(), s.uid, s.tx.clone())
    };

    let mut done = false;
    // (1) o TEMA com as variantes fold
    for cand in icons::theme_icon_candidates(key) {
        if theme.has_icon(&cand) {
            img.set_icon_name(Some(&cand));
            done = true;
            break;
        }
    }
    // (2) o STEAM
    if !done {
        for cand in icons::steam_icon_candidates(key) {
            if theme.has_icon(&cand) {
                img.set_icon_name(Some(&cand));
                done = true;
                break;
            }
        }
    }
    // (3) o GEAR LEVER + a BUSCA nas raízes E132 (flatpak exports incl.)
    if !done {
        if let Some(hit) = icons::gearlever_icon(key, &home) {
            img.set_from_file(Some(&hit));
            done = true;
            log(&format!("raw ícone: '{key}' veio do Gear Lever ({})", hit.display()));
        }
    }
    if !done {
        let roots = icons::icon_roots(&home);
        if let Some(hit) = icons::find_icon_file(key, &roots) {
            img.set_from_file(Some(&hit));
            done = true;
        }
    }
    // (4) o CACHE da casa + a sonda /proc (environ APPIMAGE=, cmdline,
    // exe → o mount /tmp/.mount_*; o maps é a rede do procapp)
    let mut appimg: Option<PathBuf> = None;
    let mut mount: Option<PathBuf> = None;
    if !done {
        if let Some((ai, m)) = procapp::proc_appimage(Path::new("/proc"), key, uid) {
            let cached = icons::appicon_cache_path(&appicon_cache_dir(), &ai.to_string_lossy());
            if cached.is_file() {
                img.set_from_file(Some(&cached));
                done = true;
                log(&format!(
                    "raw ícone: '{key}' veio do cache da casa ({})",
                    cached.display()
                ));
            }
            appimg = Some(ai);
            mount = m;
        }
    }
    // (5) o .DirIcon do mount VIVO
    if !done {
        if let Some(m) = &mount {
            if let Some(diricon) = procapp::diricon_of_mount(m) {
                img.set_from_file(Some(&diricon));
                done = true;
                log(&format!(
                    "raw ícone: '{key}' ganhou o .DirIcon do AppImage montado ({})",
                    diricon.display()
                ));
            }
        }
    }
    // (6) a EXTRAÇÃO EM THREAD
    if !done {
        if let (Some(ai), Some(m)) = (appimg.clone(), mount.clone()) {
            let tx = tx.clone();
            let key = key.to_string();
            std::thread::spawn(move || {
                let dest = icons::appicon_cache_path(&appicon_cache_dir(), &ai.to_string_lossy());
                if let Some(got) = procapp::extract_diricon(&m, &dest) {
                    let _ = tx.send(Msg::IconReady { key, path: got });
                }
            });
        }
    }
    // (6a) E133 — WINE/PROTON: o .exe do cmdline + o ícone embutido. A
    // ordem da casa: o CACHE da casa (extraindo 1x serve p/ sempre) →
    // os CACHES DE JOGO que a loja já baixou (Steam/Lutris/Heroic/
    // Hydra — o .ico/.jpg da capa vale antes de extrair) → o ícone
    // ADJACENTE ao .exe (jogos portable) → a EXTRAÇÃO EM THREAD do
    // recurso PE (RT_GROUP_ICON → RT_ICON; PNG como está, DIB → PNG).
    if !done {
        if let Some(exe) = procapp::proc_wine_exe(Path::new("/proc"), key, uid) {
            let cached = icons::exe_icon_cache_path(&crate::exeicon_cache_dir(), &exe.to_string_lossy());
            if cached.is_file() {
                img.set_from_file(Some(&cached));
                done = true;
                log(&format!(
                    "raw ícone: '{key}' veio do cache de exe ({})",
                    cached.display()
                ));
            }
            if !done {
                let stem = exe
                    .file_stem()
                    .map(|s| s.to_string_lossy().into_owned())
                    .unwrap_or_default();
                let roots = icons::game_cache_roots(&home);
                if let Some(hit) = icons::find_image_file(&stem, &roots) {
                    img.set_from_file(Some(&hit));
                    done = true;
                    log(&format!(
                        "raw ícone: '{key}' veio do cache de jogo ({})",
                        hit.display()
                    ));
                }
            }
            if !done {
                if let Some(hit) = procapp::adjacent_icon(&exe) {
                    img.set_from_file(Some(&hit));
                    done = true;
                    log(&format!(
                        "raw ícone: '{key}' ganhou o ícone adjacente ao .exe ({})",
                        hit.display()
                    ));
                }
            }
            if !done {
                let tx = tx.clone();
                let key = key.to_string();
                std::thread::spawn(move || {
                    let dest = icons::exe_icon_cache_path(&crate::exeicon_cache_dir(), &exe.to_string_lossy());
                    if let Some(got) = icons::extract_pe_icon(&exe, &dest) {
                        let _ = tx.send(Msg::IconReady { key, path: got });
                    }
                });
            }
        }
    }
    // (6b) E133 — BINÁRIO CUSTOM (Electron/Snap/Nix/portable): o ícone
    // ADJACENTE ao /proc/<pid>/exe — as raízes por NOME (tema, Gear
    // Lever e a busca E132 com pixmaps e ~/.local/share/icons) já
    // foram consultadas nos passos de cima; aqui é o exe que CARREGA
    // a própria cara junto.
    if !done {
        if let Some(exe) = procapp::proc_argv0_executable(Path::new("/proc"), key, uid) {
            if let Some(hit) = procapp::adjacent_icon(&exe) {
                img.set_from_file(Some(&hit));
                done = true;
                log(&format!(
                    "raw ícone: '{key}' ganhou o ícone adjacente ao binário ({})",
                    hit.display()
                ));
            }
        }
    }
    // (7) o GLIFO honesto
    if !done {
        img.set_icon_name(Some("application-x-executable"));
    }
    btn.set_child(Some(&img));
    btn.set_tooltip_text(Some(&format!(
        "{name} — esquerdo: focar/ciclar · direito: nova sessão · meio: encerrar"
    )));
    wire_clicks(st, &btn, Act::Raw { key: key.to_string(), name: name.to_string() });
    btn
}

/// A GRAMÁTICA DO CLIQUE (v2.10.10, UMA para pin/dinâmico/raw):
/// esquerdo foca/cicla · direito nova sessão · meio encerra. O
/// GestureClick com button=0 enxerga TODOS os botões (a GTK4
/// aposentou o button-press-event da GTK3 — o current_button no
/// instante do press é quem decide); o "clicked" segue para o teclado
/// (Espaço/Enter = o mesmo verbo do esquerdo).
fn wire_clicks(st: &Rc<RefCell<State>>, btn: &gtk::Button, act: Act) {
    let gesture = gtk::GestureClick::new();
    gesture.set_button(0);
    {
        let st = st.clone();
        let act = act.clone();
        gesture.connect_pressed(move |g, _n, _x, _y| match g.current_button() {
            1 => on_left(&st, &act),
            2 => on_middle(&st, &act),
            3 => on_right(&st, &act),
            _ => {}
        });
    }
    btn.add_controller(gesture);
    {
        let st = st.clone();
        let act = act.clone();
        btn.connect_clicked(move |_| on_left(&st, &act));
    }
}

// ── os VERBOS (a gramática UMA da casa) ───────────────────────────────

/// As janelas REAIS de um alvo no snapshot atual (strict = o verbo
/// DESTRUTIVO: o título nunca manda WM_DELETE — a lei E36).
fn windows_of_state(s: &State, act: &Act, strict: bool) -> Vec<u64> {
    match act {
        Act::App { cands, name, .. } => {
            sock::windows_of_key(&s.snap, cands, name, strict)
        }
        Act::Raw { key, .. } => sock::raw_windows(&s.snap, key, strict),
    }
}

/// A chave do guard/anel de um alvo (did do .desktop ou "raw:<key>").
fn act_key(act: &Act) -> String {
    match act {
        Act::App { did, .. } => did.clone(),
        Act::Raw { key, .. } => format!("raw:{key}"),
    }
}

/// E89 — a gaveta aberta não sobrepõe o que a dock acorda (o drawer é
/// efêmero por desenho; sem gaveta viva é um fork de µs).
fn dismiss_overlays() {
    let _ = Command::new("pkill")
        .args(["-x", "nwg-drawer"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn();
}

/// Um cliente do toplevel.sock por verbo (connect a unix socket custa
/// µs — a conexão PERSISTENTE é da thread de fundo; os verbos da UI
/// usam a própria, curta e à prova de daemon morto).
fn with_client<T>(f: impl FnOnce(&mut sock::ToplevelClient) -> T) -> Option<T> {
    let mut c = sock::ToplevelClient::connect(&toplevel_sock())?;
    Some(f(&mut c))
}

/// O ESQUERDO — foca/cicla (v2.10.1 + E71 + E89): 1 janela →
/// foca/restaura (ou MINIMIZA se ela é a focada — o toggle); N → cicla
/// ENTRE elas (o anel por id, a memória é de quem clicou); 0 → UMA
/// LIST FRESCA julga (a prova no lançamento) e só então abre (com o
/// guard de 8s no gargalo único).
fn on_left(st: &Rc<RefCell<State>>, act: &Act) {
    dismiss_overlays();
    let key = act_key(act);
    let mut wids = windows_of_state(&st.borrow(), act, false);
    if !st.borrow().tl_alive {
        // daemon morto: o fallback wlrctl é ESCOPO NÃO PORTADO (ver
        // cabeçalho) — o lançar segue, o focar degrada honesto com log
        launch(st, act, Some(&key));
        return;
    }
    if wids.is_empty() {
        // E71 — A PROVA NO LANÇAMENTO: abrir é o único verbo
        // irreversível e NUNCA parte de snapshot velho.
        // E-auditoria 2026-11-22: list() já devolve Option<Snapshot> e o
        // with_client envolve em OUTRA camada Option — o braço vivo é
        // Some(Some(snap)); qualquer outro (conexão morta OU cmd falho)
        // degrada ao fallback honesto.
        match with_client(|c| c.list()) {
            Some(Some(snap)) => {
                let mut s = st.borrow_mut();
                s.snap = snap;
                s.tl_alive = true;
                drop(s);
                wids = windows_of_state(&st.borrow(), act, false);
            }
            _ => {
                // a conexão morreu NO MEIO do clique: degradar ao
                // fallback honesto da v1 (launch com guard — nunca
                // às cegas duplo)
                launch(st, act, Some(&key));
                return;
            }
        }
    }
    if wids.is_empty() {
        launch(st, act, Some(&key));
        return;
    }
    // E135 — A PROVA NO CLIQUE (a ordem do dono do dump 101339: os
    // ACT repetidos e os timeouts de 2s do toplevel.log nasciam de
    // snapshot VELHO — o bitmask decidia MIN com estado de rodada
    // passada): UMA list fresca decide (o socket unix local custa
    // µs — o clique não espera nada; o fallback honesto segue).
    if st.borrow().tl_alive {
        if let Some(Some(snap)) = with_client(|c| c.list()) {
            st.borrow_mut().snap = snap;
        }
    }
    if wids.len() == 1 {
        let id = wids[0];
        let flags = st
            .borrow()
            .snap
            .windows
            .get(&id)
            .map(|w| w.flags)
            .unwrap_or(0);
        // E89 — O TOGGLE: 1 janela do app E ela é a FOCADA da sessão
        // (não minimizada, não fullscreen — sair de fullscreen é o Esc
        // do próprio app) → o clique MINIMIZA. O 2º clique deixa de
        // ser "nada acontece".
        if flags & sock::F_ACTIVATED != 0
            && flags & sock::F_MINIMIZED == 0
            && flags & sock::F_FULLSCREEN == 0
            && with_client(|c| c.min(id)).unwrap_or(false)
        {
            log(&format!("toggle: minimizado por id {id}"));
            return;
        }
        if with_client(|c| c.act(id)).unwrap_or(false) {
            st.borrow_mut().last_act.insert(key, id);
            log(&format!("foco por id {id}"));
            return;
        }
        // v2.10.6 — a morte no meio do clique degrada ao fallback da
        // v1 (o wlrctl do Python é degrau seguinte, nomeado)
        launch(st, act, Some(&key));
        return;
    }
    // N janelas: o anel do alt-tab DENTRO do botão do app
    let nxt = {
        let s = st.borrow();
        sock::cycle_next(&s.snap, &wids, s.last_act.get(&key).copied())
    };
    if let Some(n) = nxt {
        if with_client(|c| c.act(n)).unwrap_or(false) {
            st.borrow_mut().last_act.insert(key.clone(), n);
            log(&format!("ciclo do app: id {n} ({} janelas)", wids.len()));
            return;
        }
    }
    launch(st, act, Some(&key));
}

/// O DIREITO — NOVA SESSÃO (a gramática UMA, v2.10.10): o verbo
/// EXPLÍCITO de duplicar NÃO passa chave (o guard é para o vão do
/// foco, não para o pedido claro do dono). No SEM-NOME, o argv[0] do
/// processo vivo é a PROVA de origem — só lança o que existe e é
/// executável; sem prova, o log ensina (nunca adivinha).
fn on_right(st: &Rc<RefCell<State>>, act: &Act) {
    dismiss_overlays();
    match act {
        Act::App { cmd, .. } => launch(st, act, None),
        Act::Raw { key, .. } => {
            let uid = st.borrow().uid;
            match procapp::proc_argv0_executable(Path::new("/proc"), key, uid) {
                Some(argv0) => {
                    log(&format!("nova sessão do sem-nome via /proc: {}", argv0.display()));
                    let cmd = argv0.to_string_lossy().into_owned();
                    launch_cmd(st, &cmd, None);
                }
                None => log(&format!(
                    "nova sessão sem prova de origem ({key}) — instale o \
                     .desktop do app e ele vira dinâmico completo"
                )),
            }
        }
    }
}

/// O MEIO — encerra o programa (CLOSE por id, gracioso WM_DELETE — o
/// app confirma se tiver o que salvar): STRICT por app_id (a lei E36:
/// o título nunca manda fechar — a aba "Arquivos do Windows" do Brave
/// não morre porque casa com o Thunar pt-BR).
fn on_middle(st: &Rc<RefCell<State>>, act: &Act) {
    let wids = windows_of_state(&st.borrow(), act, true);
    if wids.is_empty() {
        log("encerrar sem janelas do app — nada feito (strict)");
        return;
    }
    let ok = with_client(|c| {
        let mut any = false;
        for id in &wids {
            if c.close_win(*id) {
                any = true;
                log(&format!("encerrado por id {id}"));
            }
        }
        any
    });
    if !ok.unwrap_or(false) {
        log("encerrar: o daemon não respondeu (o wlrctl é degrau seguinte)");
    }
}

/// O lançamento com o guard E71 no gargalo único (todo verbo de abrir
/// passa aqui — só o DIREITO não passa chave).
fn launch(st: &Rc<RefCell<State>>, act: &Act, key: Option<&str>) {
    let cmd = match act {
        Act::App { cmd, .. } => cmd.clone(),
        // o raw não tem .desktop: o esquerdo sem janela NÃO lança às
        // cegas (o Python tenta o wlrctl; a v1 ensina no log)
        Act::Raw { key, .. } => {
            log(&format!("raw '{key}' sem janelas e sem wlrctl nesta v1 — nada lançado"));
            return;
        }
    };
    launch_cmd(st, &cmd, key);
}

fn launch_cmd(st: &Rc<RefCell<State>>, cmd: &str, key: Option<&str>) {
    dismiss_overlays();
    if cmd.is_empty() {
        return;
    }
    if let Some(k) = key {
        let mut s = st.borrow_mut();
        if let Some(t0) = s.launching.get(k) {
            let age = t0.elapsed().as_secs_f64();
            if age < GUARD_S {
                log(&format!(
                    "lançamento em voo ({k}) — clique ignorado (a janela ainda \
                     mapeia; guard por {:.1}s)",
                    GUARD_S - age
                ));
                return;
            }
        }
    }
    // shell=True do Python 1:1 (o Exec do .desktop é uma linha de
    // comando, não um argv) + start_new_session (process_group(0))
    match Command::new("sh")
        .arg("-c")
        .arg(cmd)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn()
    {
        Ok(child) => {
            let mut s = st.borrow_mut();
            s.children.push((child, key.map(|k| k.to_string())));
            if let Some(k) = key {
                s.launching.insert(k.to_string(), Instant::now());
            }
            log(&format!("lançado: {cmd}"));
        }
        Err(e) => log(&format!("falha ao lançar {cmd}: {e}")),
    }
}

// ── dinâmicos, raws e o indicador ─────────────────────────────────────

/// Os DINÂMICOS (comm→.desktop pelo índice, com as chaves REVERSE-DNS
/// dos Flatpaks) e os RAW (janelas não cobertas, com a denylist E106):
/// diff por CONJUNTO — nada remonta a pílula quando nada mudou (a lei
/// v2.10.0; a animação v2.11 é degrau seguinte, nomeada).
fn sync_dynamic(st: &Rc<RefCell<State>>) {
    // (1) os comms vivos do usuário (o MESMO scan alimenta tudo)
    let uid = st.borrow().uid;
    let comms = procapp::scan_user_comms(Path::new("/proc"), uid);
    // (2) current: did → (entry, comm) — resolve PELO ÍNDICE (o
    // comm "bazaar" acha o io.github.kolunmi.Bazaar.desktop: nome
    // "Bazaar", ícone oficial, NUNCA raw — a ordem do dono E132)
    let mut current: Vec<(String, icons::DesktopEntry)> = Vec::new();
    {
        let s = st.borrow();
        for comm in &comms {
            let Some(entry) = icons::resolve_desktop(&s.index, &s.entries, comm) else {
                continue;
            };
            let did = entry.id.clone();
            if did.is_empty()
                || entry.exec.is_empty()
                || s.pin_ids.contains(&did)
                || current.iter().any(|(d, _)| d == &did)
            {
                continue;
            }
            // v2.10.3 — daemon vivo: SEM janela real não é "aberto"
            if s.tl_alive
                && sock::windows_of_key(
                    &s.snap,
                    &icons::focus_candidates(entry, ""),
                    &entry.name,
                    false,
                )
                .is_empty()
            {
                continue;
            }
            current.push((did, entry.clone()));
        }
    }
    // (3) os RAW: janelas do snapshot não cobertas por pin/dinâmico
    let mut raws: Vec<(String, String)> = Vec::new();
    {
        let s = st.borrow();
        if s.tl_alive {
            let mut covered: Vec<u64> = Vec::new();
            for row in s.pins.iter().chain(s.dyns.values()) {
                covered.extend(windows_of_state(&s, &row.act, false));
            }
            // os dinâmicos DESTA rodada também cobrem (antes de existirem)
            for (_, e) in &current {
                covered.extend(sock::windows_of_key(
                    &s.snap,
                    &icons::focus_candidates(e, ""),
                    &e.name,
                    false,
                ));
            }
            for w in s.snap.windows.values() {
                if covered.contains(&w.id) {
                    continue;
                }
                if let Some((key, name)) = icons::raw_key(&w.app_id, &w.title) {
                    if !raws.iter().any(|(k, _)| k == &key) {
                        raws.push((key, name));
                    }
                } else if !w.app_id.is_empty() || !w.title.trim().is_empty() {
                    log(&format!(
                        "raw DENYLIST/sem nome: '{}' é diálogo de daemon — \
                         sem botão (E106)",
                        if w.app_id.is_empty() { &w.title } else { &w.app_id }
                    ));
                }
            }
        }
    }
    // (4) o diff: nada remonta quando nada mudou
    let (dyn_set, raw_set): (HashSet<String>, HashSet<String>) = (
        current.iter().map(|(d, _)| d.clone()).collect(),
        raws.iter().map(|(k, _)| k.clone()).collect(),
    );
    let (old_dyn, old_raw) = {
        let s = st.borrow();
        (
            s.dyns.keys().cloned().collect::<HashSet<_>>(),
            s.raws.keys().cloned().collect::<HashSet<_>>(),
        )
    };
    if dyn_set == old_dyn && raw_set == old_raw {
        return;
    }
    // (5) remonta o que mudou (os botões nascem FORA do borrow_mut)
    let mut new_dyns: HashMap<String, PinRow> = HashMap::new();
    for (did, entry) in current {
        let btn = make_app_button(st, &entry, "");
        new_dyns.insert(
            did.clone(),
            PinRow {
                button: btn,
                act: Act::App {
                    hint: String::new(),
                    did: did.clone(),
                    cmd: icons::exec_ready(&entry),
                    cands: icons::focus_candidates(&entry, ""),
                    name: entry.name.clone(),
                },
            },
        );
    }
    let mut new_raws: HashMap<String, RawRow> = HashMap::new();
    for (key, name) in raws {
        let btn = make_raw_button(st, &key, &name);
        let img = btn
            .child()
            .and_downcast::<gtk::Image>()
            .unwrap_or_else(gtk::Image::new);
        new_raws.insert(key.clone(), RawRow { button: btn, image: img });
    }
    let mut s = st.borrow_mut();
    for gone in old_dyn.difference(&dyn_set) {
        log(&format!("dinâmico saiu: {gone}"));
    }
    for fresh in dyn_set.difference(&old_dyn) {
        log(&format!("dinâmico entrou: {fresh}"));
    }
    for gone in old_raw.difference(&raw_set) {
        log(&format!("raw saiu: {gone}"));
    }
    for fresh in raw_set.difference(&old_raw) {
        log(&format!("raw entrou: {fresh}"));
    }
    s.dyns = new_dyns;
    s.raws = new_raws;
    repack(&s);
    s.window.show();
}

/// O INDICADOR "running" — a JANELA REAL é o critério (v2.10.3: o
/// processo em 2º plano SEM janela não acende; com o daemon morto o
/// indicador fica APAGADO nesta v1 — o _fallback_alive do /proc é
/// degrau seguinte, nomeado no cabeçalho).
fn update_indicators(s: &State) {
    if !s.tl_alive {
        for row in s.pins.iter().chain(s.dyns.values()) {
            row.button.remove_css_class("running");
        }
        return;
    }
    for row in s.pins.iter().chain(s.dyns.values()) {
        let on = !windows_of_state(s, &row.act, false).is_empty();
        if on {
            row.button.add_css_class("running");
        } else {
            row.button.remove_css_class("running");
        }
    }
}

// ── a pele (o MESMO CSS da casa — ~/.config/elite/dock.css) ───────────

/// A pele da pílula: o CSS do usuário (~/.config/elite/dock.css) ou o
/// fallback embutido (espelho do skel — a bolinha 6x3px centrada que
/// o dono desenhou, E36).
fn load_css() {
    let css = std::fs::read_to_string(css_path()).unwrap_or_else(|_| {
        log(&format!("CSS ausente ({}) — usando fallback embutido", css_path().display()));
        DEFAULT_CSS.to_string()
    });
    let provider = gtk::CssProvider::new();
    // E-auditoria 2026-11-22: o load_from_string mora atrás da feature
    // v4_12 no gtk4-rs 0.11 (o CI não liga features de versão) — o
    // load_from_data é a via sempre-presente (deprecated apenas SOB a
    // feature, que não está ligada).
    provider.load_from_data(&css);
    if let Some(display) = gdk::Display::default() {
        gtk::style_context_add_provider_for_display(
            &display,
            &provider,
            gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }
}

/// O fallback embutido (o DEFAULT_CSS do Python, na gramática GTK4 —
/// os seletores #name e a bolinha do .running seguem os mesmos).
const DEFAULT_CSS: &str = "
#dockwindow { background: transparent; }
#dockbox {
  background: rgba(5, 5, 8, 0.88);
  border: 1px solid rgba(22, 22, 31, 0.8);
  border-radius: 20px;
  padding: 4px 10px;
}
#dockbox button {
  padding: 4px;
  min-height: 44px;
  min-width: 44px;
  border-radius: 12px;
  background: transparent;
  border: none;
  transition: background 0.15s ease;
}
#dockbox button:hover { background: rgba(22, 22, 31, 0.95); }
#dockbox button:active { background: rgba(46, 46, 61, 0.95); }
#dockbox button.running {
  /* E36 — a BOLINHA 6x3px centrada do dono */
  background-image: linear-gradient(rgba(205, 214, 244, 0.9), rgba(205, 214, 244, 0.9));
  background-size: 6px 3px;
  background-position: center bottom;
  background-repeat: no-repeat;
}
#dockbox separator {
  min-width: 1px;
  margin: 8px 7px;
  background: rgba(108, 112, 134, 0.45);
}
";
