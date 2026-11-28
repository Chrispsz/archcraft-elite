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
//     deste degrau pediu Layer::TOP (o Python usa Layer::BOTTOM — com
//     BOTTOM a tela cheia do app COBRE a dock; 1.0-105: o teclado
//     NUNCA é da dock — KeyboardMode::None, o anel roxo morreu no
//     CSS). O selo é de quem ordenou; se o rig reclamar do fullscreen,
//     é trocar UMA constante aqui;
//   · a assinatura do bus.sock (2.0 — o fio vivo do elite-daemon):
//     UMA thread de fundo é a DONA do BusClient persistente (Hello +
//     reconexão honesta 5→20→100ms E135 — o daemon renasce, a dock
//     reaparece); cada `Windows` publicado vira Snapshot num canal
//     mpsc (push de latência ~0; o toplevel.sock de era e o handshake
//     "EVT ON" E38 morreram com o C de 3 gerações); a UI acorda no
//     dreno de 50ms (thread NUNCA toca GTK — a lei da casa);
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
//     async-signal-safe) escreve a bandeira e o dreno de 50ms colhe
//     (latência ≤50ms, documentada no DRAIN_MS);
//   · os pins são RE-LIDOS a cada tick e a pílula só remonta quando o
//     CONJUNTO muda (o craft-pin add/rm reflete no tick seguinte mesmo
//     sem sinal — a rede a mais que o Python não tinha).
//
// ESCOPO HONESTO DESTA v1 (o que FALTA, nomeado — ver main.rs também):
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
// E140 — O QUE ENTROU (a Parte 2 do dossiê 1.0-88): o MENU E74 do
//   direito é REAL (Fixar/Desafixar da Dock + Nova janela + Fechar —
//   a gaveta fuzzel dos pins morreu; 1.0-109 §2.1: o menu de era em
//   PopoverMenu virou a JANELA DE CAMADA Overlay — SEMPRE acima da
//   gaveta), o clique
//   é EXCLUSIVAMENTE no released com tolerância de arrasto <5px (o
//   press×click duplicava o verbo) e a assinatura do fio não falece por
//   silêncio (o BusClient de hoje reconecta sozinho — zero espaço
//   preto no fecho; o "EVT ON" de era morreu com o toplevel.sock).
use crate::{appicon_cache_dir, css_path, icons, log, pins_path, procapp, read_pins, sock,
            bus_sock, VERSION};
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::rc::Rc;
use std::sync::atomic::{AtomicI32, Ordering};
use std::time::{Duration, Instant};

use gtk4::prelude::*;
use gtk4::{gdk, glib};
// E-auditoria 2026-11-22 (a cura do Canal 44945339468): o crate gtk4 0.11
// NÃO re-exporta um módulo `gtk` — os widgets moram na RAIZ do crate; o
// alias abaixo mantém os ~120 caminhos `gtk::` do corpo intactos.
use gtk4 as gtk;
// (2.0 E143-corrige: o import EXPLÍCITO do ActionMap saiu — o Canal 141
// provou ele REDUNDANTE: o gtk4::prelude desta versão já veste o trait
// do add_action; a lição E140-corrigido fica na história dos commits)
// E-auditoria: o gtk4-layer-shell 0.8 NÃO expõe funções livres — a API
// é o trait LayerShell (init_layer_shell/set_layer/set_anchor/...) e o
// is_supported continua função livre (re-export da raiz).
use gtk4_layer_shell::LayerShell;

/// Escala fixa de fábrica (spec M3.2 — o mesmo 36 do Python).
const ICON_SIZE: i32 = 36;
/// O float da pílula DENTRO da superfície (margem GTK — a zona
/// exclusiva cobre pílula + vão).
const PILL_FLOAT: i32 = 6;
/// O tick de segurança (o push do bus domina a latência do
/// snapshot; 5s = ceifa dos filhos + guard — o MESMO desenho
/// v2.10.26 do Python SEM o LIST de snapshot de era: o fio é push e o
/// reload dos pins é do VIGIA do arquivo desde a 1.0-110 T1).
const TICK_S: u64 = 5;
/// 1.0-110 T1 — O DRAIN_MS DE 50ms MORREU COM O CANAL mpsc (a entrega
/// é um idle POR QUADRO na ponte viva: zero cadência acordando a dock
/// em idle — a mesma lei da barra).
///
/// E140 — A TOLERÂNCIA DE ARRASTO: released a ≥5px do press é ARRASTO,
/// não clique (a ordem do dono, Parte 2 do dossiê — a mesma lei da
/// barra; o clique curto que o press×click duplicava nunca mais).
const ARRASTO_PX: f64 = 5.0;
/// E71 — o guard do lançamento em voo (o vão até a janela mapear).
const GUARD_S: f64 = 8.0;

// Linux x86-64 (o alvo da ISO): a glib 0.22 não traz unix_signal_add —
// o handler cru é a via (atomic async-signal-safe, drenado no idle).
const SIGUSR1: i32 = 10;
const SIGUSR2: i32 = 12;

static SIG: AtomicI32 = AtomicI32::new(0);
extern "C" fn on_signal(sig: i32) {
    SIG.store(sig, Ordering::SeqCst);
    // 1.0-110 T1 — O CANO acorda a leitora (write(2) é async-signal-safe;
    // o veredito mora no SIG de sempre e a entrega é por MENSAGEM)
    let w = CANO_W.load(Ordering::SeqCst);
    if w >= 0 {
        let byte: u8 = 1;
        unsafe {
            libc::write(w, &byte as *const u8 as *const libc::c_void, 1);
        }
    }
}

/// As mensagens da thread de fundo para a UI (a ENTREGA é um idle POR
/// quadro na ponte viva — 1.0-110 T1: a thread NUNCA toca GTK e a UI
/// NUNCA mais drena em cadência de 50ms).
enum Msg {
    /// Um snapshot do bus (None = transporte morto — a graça decide).
    Snapshot(Option<sock::Snapshot>),
    /// 1.0-109 — O FIO PERSISTENTE nasceu (a thread de fundo entrega o
    /// Arc do BusClient à UI: os VERBOS dos cliques viajam por ELE —
    /// uma conexão única para a vida da dock, zero `bus.cliente 3..7`
    /// por clique, zero IPC bloqueando a thread do GTK).
    Bus(std::sync::Arc<elite_core::bus::BusClient>),
    /// 1.0-109 — o eco do verbo (o Ack chega pelo fio persistente e a
    /// UI nomeia o resultado no papel — o clique nunca ESPEROU por ele).
    Ack { ok: bool },
    /// A extração em thread terminou: o ícone do raw está no cache.
    IconReady { key: String, path: PathBuf },
    /// 1.0-100 — A MESA CORRENTE mudou (o sync do rc.xml → o daemon
    /// publica `Workspace`): as classes .other-workspace re-julgadas
    /// NO MESMO idle, sem remontagem nenhuma (estado é classe, não
    /// árvore — a lei E139 do diff-guard).
    Mesa(u32),
    /// 1.0-110 T1 — OS SINAIS PELO CANO (self-pipe: o handler cru
    /// async-signal-safe escreve 1 byte; a leitora dedicada entrega o
    /// veredito do atomic POR MENSAGEM na ponte — W-S-d toggle · SIGUSR2
    /// reload dos pins). A glib 0.22 não tem unix_signal_add NEM
    /// MainContext::channel (provado no compilador da casa); o dreno
    /// de 50ms morreu com ele — a dock dorme até o fio/falar.
    Sinal(i32),
}

/// O alvo dos cliques de um botão: um app COM .desktop (pin/dinâmico)
/// ou um SEM-NOME (raw — AppImage/Steam sem .desktop instalado).
/// (E143-corrige: o hint (App) saiu — escrito e nunca lido; E106/5
/// DEVOLVE o name (Raw): a fixação do sem-nome gera o .desktop LOCAL
/// com o NOME DO BOTÃO — o tooltip nasce no botão, o pin nasce aqui)
#[derive(Clone)]
enum Act {
    App {
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
    // pins: os fixados (dock-pins, NA ORDEM do arquivo) · dyns/raws:
    // os dinâmicos por desktop-id e os SEM-NOME por chave de app_id
    pins: Vec<PinRow>,
    dyns: HashMap<String, PinRow>,
    raws: HashMap<String, RawRow>,
    entries: Vec<icons::DesktopEntry>,
    index: HashMap<String, usize>,
    /// 1.0-104 — o índice POR NOME (o fold do Name do .desktop → a
    /// rede do título da janela: o "Stardew Valley" da janela casa o
    /// Name do .desktop que nenhum app_id nomeia).
    name_index: HashMap<String, usize>,
    pin_ids: HashSet<String>,
    pins_txt: String,
    /// E139 — a chave estável do conjunto resolvido (o diff-guard dos
    /// botões: remontagem SÓ quando o conjunto muda — zero recriação
    /// por tick, a lei v2.10.0).
    pins_chave: String,
    /// E139 — as faltas CONSECUTIVAS de cada pin (2 passadas seguidas
    /// sem resolver = morte real; um acerto no meio zera — a poda só
    /// remove o .desktop que realmente não existe em nenhum dir XDG).
    pin_misses: HashMap<String, u32>,
    // o snapshot da sessão (a JANELA é a verdade — v2.10.3)
    snap: sock::Snapshot,
    tl_alive: bool,
    /// 1.0-100 — a mesa corrente da sessão (o bus `Workspace`): a régua
    /// do .other-workspace (audit 99 §4 — a dock isola visualmente as
    /// janelas das outras mesas).
    mesa: u32,
    last_act: HashMap<String, u64>,
    launching: HashMap<String, Instant>,
    children: Vec<(std::process::Child, Option<String>)>,
    home: PathBuf,
    uid: u32,
    /// 1.0-109 — O FIO PERSISTENTE (o Arc do BusClient da thread de
    /// fundo: os cliques pedem os verbos POR ELE — fire-and-forget com
    /// o teto de escrita de 500ms da fundação, NUNCA um round-trip
    /// bloqueando a main thread do GTK).
    bus: Option<std::sync::Arc<elite_core::bus::BusClient>>,
    /// 1.0-109 §2.1 — O MENU DE CAMADA (o clique direito veste a camada
    /// Overlay — SEMPRE acima da gaveta top do craft-apps; o popover de
    /// era era FILHO da superfície top da dock e a gaveta que nascia
    /// DEPOIS o cobria inteiro — a evidência do dump 1.0-108).
    menu: craft_tools::MenuCamada,
    /// 1.0-110 T1 — O VIGIA DO PAPEL DOS PINS (gio::FileMonitor/inotify
    /// no diretório do dock-pins: o craft-pin add/rm de FORA veste NO
    /// MESMO evento do arquivo — o tick de 5s segue só para ceifa e
    /// guard, a re-leitura periódica morreu com o vigia).
    pins_watch: Option<gtk4::gio::FileMonitor>,
}

// ── 1.0-110 T1 — A PONTE VIVA DA DOCK (o canal que a glib 0.22 não ───
//      tem — provado NO COMPILADOR: MainContext::channel morreu da
//      glib-rs e o unix_signal_add nunca morou lá. O EFEITO da
//      diretriz é o mesmo: a thread de fundo acorda o main loop SÓ
//      POR MENSAGEM (um glib::idle_add POR quadro — o closure Send
//      carrega a Msg; o corpo corre na MAIN THREAD e lê o estado Rc
//      da thread-local dEle) — ZERO dreno periódico, ZERO wakeup em
//      idle: a dock dorme até o bus/um sinal/um pin falar.
// ─────────────────────────────────────────────────────────────────────
thread_local! {
    static ESTADO_UI: RefCell<Option<Rc<RefCell<State>>>> = const { RefCell::new(None) };
}

/// A ENTREGA (chamada de QUALQUER thread: a Msg Send acorda UM idle
/// no main loop — a aplicação veste o estado Rc no corpo do idle).
fn entrega(msg: Msg) {
    let mut msg = Some(msg);
    glib::idle_add(move || {
        if let Some(msg) = msg.take() {
            ESTADO_UI.with(|caixa| {
                if let Some(st) = caixa.borrow().as_ref() {
                    aplica(st, msg);
                }
            });
        }
        glib::ControlFlow::Break
    });
}

/// A MÃE dos idles (a build registra o estado UMA vez).
fn registra_estado(st: &Rc<RefCell<State>>) {
    ESTADO_UI.with(|caixa| *caixa.borrow_mut() = Some(st.clone()));
}

pub fn run() -> i32 {
    arma_rt();
    let app = gtk::Application::new(Some("elite.craft.Dock"), Default::default());
    app.connect_activate(build);
    app.run().get() as i32
}

/// 1.0-94 — A ARMADURA RT (a mesma cura da barra): TODO sinal do
/// intervalo real-time (SIGRTMIN..SIGRTMAX) vira HANDLED no primeiro
/// instante — a disposição padrão do Linux para RT é TERMINAR o
/// processo, e nenhum sinal da casa (ou de fora) derruba mais a dock
/// (a instabilidade visual das trocas de resolução/refresh do rig da
/// 1.0-93 morria na mesma classe: qualquer RT perdido era processo
/// morto renascendo com a pílula da era anterior).
pub fn arma_rt() {
    unsafe {
        let mut s = libc::SIGRTMIN();
        let max = libc::SIGRTMAX();
        while s <= max {
            libc::signal(s, on_signal as *const () as libc::sighandler_t);
            s += 1;
        }
    }
}

/// E106/5 — A VARREDURA FRESCA dos .desktops (com os EXPORTS do
/// Flatpak e o ~/.local do dono, NoDisplay INCLUÍDO — a lei 1.0-104 da
/// identidade dos jogos): devolve as entradas e os DOIS índices (o de
/// chave/comm e o de nome/título). O arranque chama UMA vez; a fixação
/// do sem-nome chama DE NOVO na hora (o .desktop LOCAL gerado precisa
/// entrar no índice NO MESMO clique — nunca podado na 2ª passada).
fn varre_desktops(
    home: &Path,
) -> (
    Vec<icons::DesktopEntry>,
    HashMap<String, usize>,
    HashMap<String, usize>,
) {
    let mut entries = Vec::new();
    for dir in icons::desktop_dirs(home) {
        entries.extend(icons::scan_desktop_dir_todos(&dir));
    }
    let index = icons::desktop_index(&entries);
    let name_index = icons::name_index(&entries);
    (entries, index, name_index)
}

/// E106/5 — A RE-INDEXAÇÃO NA HORA (o par da fixação do sem-nome): o
/// .desktop LOCAL que acabou de nascer entra no índice ANTES do
/// rebuild_pins julgar o pin novo — o estado segue a verdade do disco,
/// nunca a memória do arranque.
fn reindexa_desktops(st: &Rc<RefCell<State>>) {
    let home = st.borrow().home.clone();
    let (entries, index, name_index) = varre_desktops(&home);
    let mut s = st.borrow_mut();
    s.entries = entries;
    s.index = index;
    s.name_index = name_index;
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
    // 1.0-105 — O TECLADO NUNCA É DA DOCK (KeyboardMode::None — a ordem
    // do dono: a dock JAMAIS rouba o foco de teclado no primeiro clique;
    // o OnDemand de era roubava o foco da janela real e o primeiro clique
    // só "acordava" a dock — o app abria no SEGUNDO. Os menus da dock
    // são mouse-first e veste o teclado exclusivo a janela PRÓPRIA do
    // menu de camada (1.0-109 §2.1 — a dock em si segue NONE); o contorno
    // :focus/:focus-visible morre no CSS (outline/box-shadow none) e o
    // anel roxo nunca mais acende).
    window.set_keyboard_mode(gtk4_layer_shell::KeyboardMode::None);
    window.set_namespace(Some("craft-dock"));

    let pill = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    pill.set_widget_name("dockbox");
    pill.set_margin_bottom(PILL_FLOAT);
    window.set_child(Some(&pill));
    // BLOCO 3 — O OUVIDOR DO MONITOR (a ordem do dono: GdkMonitor/
    // wl_output por EVENTO, zero polling): entra com a pílula já viva —
    // o ouvidor captura a janela e a pílula direto (o State ainda não
    // existe neste ponto).
    ouve_monitores(&window, &pill);

    // E149 — O TEARDOWN SEM ÓRFÃOS MORREU COM O POPOVER (1.0-109 §2.1: o
    // menu de camada é UMA janela TOPLEVEL própria — não é filho de
    // botão nenhum, o 'still has children left: GtkPopoverMenu' de era
    // era o enterro do repack E do EXIT; hoje nada mora pendurado: a
    // janela do menu desce com o processo da dock no mesmo tombamento).

    // o índice de .desktops (com os EXPORTS do Flatpak e as chaves
    // reverse-DNS — o "bazaar" do io.github.kolunmi.Bazaar.desktop)
    // 1.0-104 — A VARREDURA COMPLETA (com NoDisplay: a lei E21 é da
    // GAVETA, não da dock — o steam_app_413150.desktop do jogo Steam
    // NoDisplay entra no índice e a janela aberta veste o ÍCONE de
    // verdade) + O ÍNDICE POR NOME (a rede do título da janela)
    let home = crate::home_dir();
    let (entries, index, name_index) = varre_desktops(&home);
    log(&format!(
        "índice de .desktops: {} chave(s) resolvíveis + {} nome(s) de título",
        index.len(),
        name_index.len()
    ));

    // o canal mpsc MORREU INTEIRO na 1.0-110 T1 (a diretriz: o dreno de
    // 50ms acordava a dock 20 vezes por segundo para ver se o fio falou
    // — a entrega é AGORA um idle POR quadro na ponte viva: a thread de
    // fundo fala e a main thread acorda NO MESMO instante; sem nada a
    // dizer, a dock DORME). O fio do bus.sock segue DONO de um BusClient
    // persistente (reconexão 5→20→100ms E135) e o CANO dos sinais tem
    // leitora própria (self-pipe → entrega por mensagem).
    std::thread::spawn(move || bg_reader(bus_sock()));
    // a leitora do CANO dos sinais (self-pipe: o handler cru escreve 1
    // byte; a leitora dorme no read(2) e entrega o veredito do atomic
    // POR MENSAGEM — W-S-d toggle · SIGUSR2 reload dos pins)
    arma_cano_sinais();

    let st = Rc::new(RefCell::new(State {
        window,
        pill,
        shown: true,
        pins: Vec::new(),
        dyns: HashMap::new(),
        raws: HashMap::new(),
        entries,
        index,
        name_index,
        pin_ids: HashSet::new(),
        pins_txt: String::new(),
        snap: sock::Snapshot::default(),
        tl_alive: false,
        // 1.0-100 — a mesa inicial é a 1 (o labwc nasce na primeira;
        // o primeiro Workspace do bus corrige na hora)
        mesa: 1,
        last_act: HashMap::new(),
        launching: HashMap::new(),
        bus: None,
        menu: craft_tools::MenuCamada::novo("craft-dock-menu"),
        children: Vec::new(),
        pins_chave: String::new(),
        pin_misses: HashMap::new(),
        home,
        uid: procapp::current_uid(),
        pins_watch: None,
    }));
    // a PONTE registra a mãe dos idles (todo entrega tem a quem vestir)
    registra_estado(&st);

    // 1.0-109 §2.1 — O CLIQUE FORA QUE NÃO É ENGOLIDO: o press em
    // QUALQUER filho da dock fecha o menu ANTES do ícone agir — o
    // gesto mora na JANELA em fase de CAPTURA (vê o press primeiro, de
    // cima para baixo) e NUNCA reclama a sequência: o botão embaixo
    // recebe o MESMO evento (o clique destinado ao ícone passa DIRETO,
    // o menu desce no MESMO instante — o 1º clique engolido pelo grab
    // do popover de era morre aqui).
    {
        let st_clica = st.clone();
        let gesto_fora = gtk::GestureClick::new();
        gesto_fora.set_button(0);
        gesto_fora.set_propagation_phase(gtk::PropagationPhase::Capture);
        gesto_fora.connect_pressed(move |_g, _n, _x, _y| {
            if st_clica.borrow().menu.aberto() {
                st_clica.borrow().menu.fecha();
                log("menu da dock desceu pelo clique na mãe (o clique do ícone segue — nada é engolido)");
            }
        });
        let janela = st.borrow().window.clone();
        janela.add_controller(gesto_fora);
    }

    // os sinais da casa (W-S-d toggle · reload dos pins)
    unsafe {
        // (E143-corrige: o lint function_casts — o salto via ponteiro é o
        // caminho canônico do novo rustc)
        libc::signal(SIGUSR1, on_signal as *const () as libc::sighandler_t);
        libc::signal(SIGUSR2, on_signal as *const () as libc::sighandler_t);
    }

    rebuild_pins(&st);
    // 1.0-110 T1 — O VIGIA DO PAPEL DOS PINS (gio::FileMonitor/inotify):
    // o craft-pin add/rm de FORA veste NO MESMO evento do arquivo (a
    // escrita é tmp+rename NO MESMO dir — o vigia mora no DIRETÓRIO e
    // filtra o nome do papel; o evento de burst vira UM rebuild com a
    // geração trailing de 150ms). O tick de 5s segue VIVO só para
    // ceifa/guard (a diretriz: a re-leitura periódica dos pins morre
    // com o vigia).
    arma_vigia_pins(&st);
    load_css();
    st.borrow().window.show();

    log(&format!(
        "craft-dock-rs {VERSION} iniciada: {} pin(s) · bus.sock (BusClient \
         persistente com reconexão 5→20→100ms E135 + Windows por push + \
         verbos Req/Ack no mesmo fio · tick de segurança de 5s para \
         ceifa/guard/pins) · cadeia de \
         ícones E130/E132 ON (Flatpak reverse-DNS + Gear Lever + cache + \
         .DirIcon + extração em thread) · Layer::Top com teclado NUNCA \
         da dock (KeyboardMode::None — 1.0-105) · o MENU do direito na \
         camada Overlay (1.0-109 §2.1 — SEMPRE acima da gaveta, o clique \
         fora o desce SEM engolir o clique do ícone) · o ESCOPO HONESTO \
         mora no cabeçalho deste arquivo",
        st.borrow().pins.len(),
    ));

    // o dreno de 50ms MORREU COM O CANAL (1.0-110 T1: a entrega é um
    // idle por quadro na ponte — zero cadência acordando a dock);
    // o tick de 5s SEGUE VIVO (segurança — o push do bus domina a
    // latência do snapshot; aqui mora AGORA SÓ a ceifa dos filhos e o
    // guard dos lançamentos: o reload dos pins é do VIGIA do arquivo)
    {
        let st = st.clone();
        glib::timeout_add_seconds_local(TICK_S as u32, move || {
            poll_tick(&st);
            glib::ControlFlow::Continue
        });
    }
}

// ── a THREAD DE FUNDO — a dona do bus.sock ─────────────────────

/// A assinatura do bus.sock (2.0 — o fio vivo do elite-daemon): o
/// BusClient da fundação conecta, se apresenta ("craft-dock-rs") e lê
/// quadros PARA SEMPRE com a reconexão honesta 5→20→100ms E135
/// EMBUTIDA — o daemon renasce, a dock reaparece; o Hello novo arranca
/// as boas-vindas com o snapshot inteiro. Cada `Windows` publicado é
/// push de latência ~0; o snapshot NÃO tem tick nenhum (o tick de 5s
/// VIVO mora no poll_tick: ceifa dos filhos e guard — o reload dos
/// pins é do VIGIA do arquivo, 1.0-110 T1). NUNCA toca GTK: tudo pela
/// PONTE (um idle por quadro). Morreu o fio? O próximo giro reconecta
/// — a dock NUNCA depende dele (a lei v2.10.3).
fn bg_reader(sock_path: PathBuf) {
    loop {
        if let Some((cli, rx)) = elite_core::bus::BusClient::connect(&sock_path, "craft-dock-rs") {
            // 1.0-109 — O FIO PERSISTENTE NASCE: a UI guarda o Arc e os
            // VERBOS dos cliques viajam POR ELE (a conexão ÚNICA da dock
            // — o `bus.cliente 3..7` do dump era um ToplevelClient novo
            // POR CLIQUE; o BusClient da fundação RECONECTA sozinho quando
            // o daemon renasce: a mesma conexão para sempre)
            entrega(Msg::Bus(std::sync::Arc::clone(&cli)));
            for msg in rx {
                match msg {
                    elite_core::BusMsg::Windows { windows } => {
                        let snap = sock::de_bus_windows(&windows);
                        entrega(Msg::Snapshot(Some(snap)));
                    }
                    // 1.0-109 — o eco do verbo chega pelo MESMO fio: a UI
                    // nomeia o resultado no papel (o clique NUNCA esperou)
                    elite_core::BusMsg::Ack { ok, .. } => {
                        entrega(Msg::Ack { ok });
                    }
                    // 1.0-100 — A MESA CORRENTE (audit 99 §4): o sync do
                    // rc.xml publica Workspace — a dock re-julga a MESA
                    // CORRENTE no idle seguinte (classes, nunca remontagem)
                    elite_core::BusMsg::Workspace(w) => {
                        entrega(Msg::Mesa(w.current));
                    }
                    _ => {} // os estados dos outros domínios não são da dock
                }
            }
        }
        // daemon ausente: o backoff de 100ms do BusClient já segurou a
        // pressão; aqui um respiro maior evita a fila de reconexões
        std::thread::sleep(Duration::from_millis(300));
    }
}

/// 1.0-110 T1 — OS SINAIS PELO CANO (self-pipe): o handler cru guarda o
/// veredito no atomic E escreve 1 byte no pipe; a leitora dedicada dorme
/// no read(2) e entrega o sinal POR MENSAGEM na ponte — zero dreno de
/// 50ms acordando a dock em idle (o drain morreu com o canal mpsc).
fn arma_cano_sinais() {
    let mut fds = [0i32; 2];
    if unsafe { libc::pipe(fds.as_mut_ptr()) } != 0 {
        log("sinais: o cano não abriu — os sinais ficam no atomic (honesto)");
        return;
    }
    CANO_W.store(fds[1], Ordering::SeqCst);
    std::thread::Builder::new()
        .name("elite-cano-sinais".into())
        .spawn(move || {
            let leitura = fds[0];
            let mut byte = [0u8; 1];
            loop {
                let n = unsafe { libc::read(leitura, byte.as_mut_ptr().cast(), 1) };
                if n <= 0 {
                    return; // o cano fechou: a thread vai junto (honesto)
                }
                let sig = SIG.swap(0, Ordering::SeqCst);
                if sig != 0 {
                    entrega(Msg::Sinal(sig));
                }
            }
        })
        .ok();
}

/// o CANO DE ESCRITA dos sinais (o handler cru escreve 1 byte por sinal).
static CANO_W: AtomicI32 = AtomicI32::new(-1);

/// 1.0-110 T1 — O VIGIA DO PAPEL DOS PINS (gio::FileMonitor no DIRETÓRIO
/// do dock-pins: a escrita da casa é tmp+rename NO MESMO dir — o vigia
/// filtra o NOME do papel e o burst de eventos vira UM rebuild com a
/// geração trailing de 150ms; o tick de 5s segue só para ceifa/guard).
fn arma_vigia_pins(st: &Rc<RefCell<State>>) {
    let caminho = pins_path();
    let Some(dir) = caminho.parent() else { return };
    let Some(pasta) = gtk4::gio::File::for_path(dir)
        .monitor_directory(gtk4::gio::FileMonitorFlags::NONE, gtk4::gio::Cancellable::NONE)
        .ok()
    else {
        log("pins: o vigia do diretório não nasceu — o tick de segurança cobre (honesto)");
        return;
    };
    let nome = caminho
        .file_name()
        .and_then(|n| n.to_str().map(str::to_string))
        .unwrap_or_else(|| "dock-pins".to_string());
    let st = st.clone();
    let st_cb = st.clone();
    // a geração trailing: cada evento REARMA a janela de 150ms (a
    // última janela veste — as velhas calam; o burst inteiro é UM rebuild)
    let geracao = Rc::new(std::cell::Cell::new(0u64));
    let geracao_cb = geracao.clone();
    pasta.connect_changed(move |_m, arquivo, _outro, evento| {
        let da_vez = matches!(
            evento,
            gtk4::gio::FileMonitorEvent::Created
                | gtk4::gio::FileMonitorEvent::Moved
                | gtk4::gio::FileMonitorEvent::Changed
                | gtk4::gio::FileMonitorEvent::ChangesDoneHint
                | gtk4::gio::FileMonitorEvent::Deleted
        ) && arquivo
            .basename()
            .is_some_and(|b| b.to_string_lossy() == nome);
        if !da_vez {
            return; // evento do vizinho: o vigia é do papel dos pins só
        }
        geracao_cb.set(geracao_cb.get().wrapping_add(1));
        let minha = geracao_cb.get();
        // o clone do Rc atravessa o move do timer (o outer é Fn: os
        // clones nascem DENTRO do giro, nunca movidos do capturado)
        let geracao = geracao_cb.clone();
        let st = st_cb.clone();
        glib::timeout_add_local_once(Duration::from_millis(150), move || {
            if geracao.get() != minha {
                return; // a janela velha: o último evento veste (trailing)
            }
            log("pins: o papel mudou no disco — o vigia re-veste NA HORA (inotify, sem tick)");
            rebuild_pins(&st);
        });
    });
    st.borrow_mut().pins_watch = Some(pasta);
}

/// A APLICAÇÃO (a PONTE chama na main thread: uma mensagem vira widget —
/// o corpo do antigo drena de 50ms, acordado AGORA só por mensagem).
fn aplica(st: &Rc<RefCell<State>>, msg: Msg) {
    match msg {
        Msg::Snapshot(opt) => {
            let mut s = st.borrow_mut();
            apply_snapshot(&mut s, opt);
            update_indicators(&s);
            drop(s); // (o sync_dynamic pede o estado emprestado DE NOVO)
            sync_dynamic(st);
            // E135/E151 — O FLUSH SÍNCRONO UNIVERSAL no fim de TODA
            // rodada de evento (o recálculo real da superfície mora na
            // função única flush_superficie): TODO evento de janela
            // (Closed · Minimize · Maximize · abertura) vale no frame
            // corrente INDEPENDENTE de o conjunto ter mudado
            recalcula_superficie(st);
        }
        Msg::Bus(cli) => {
            // 1.0-109 — o fio persistente vestiu a UI: os cliques
            // daqui em diante falam por ELE (uma conexão só)
            st.borrow_mut().bus = Some(cli);
        }
        Msg::Ack { ok } => {
            log(if ok {
                "verbo ecoado pelo daemon (ok — o fio persistente falou)"
            } else {
                "verbo RECUSADO pelo daemon (o id não casa com janela viva — o snapshot corrige no frame seguinte)"
            });
        }
        Msg::IconReady { key, path } => {
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
        Msg::Mesa(n) => {
            // 1.0-100 — A MESA NOVA (sync do rc.xml): só CLASSES —
            // zero remontagem (o diff-guard E139 manda: o conjunto
            // de botões não mudou, a árvore é a mesma)
            {
                let mut s = st.borrow_mut();
                s.mesa = n.max(1);
            }
            update_indicators(&st.borrow());
        }
        Msg::Sinal(sig) => {
            // 1.0-110 T1 — o veredito do CANO (o handler cru guardou o
            // sinal no atomic e a leitora entregou por mensagem)
            match sig {
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
    }
}

/// E134 — A SINCRONIZAÇÃO IMEDIATA COM O SNAPSHOT REAL: a graça do
/// vazio E71 (o LIST vazio segurado 2 rodadas) e a graça do snapshot
/// morto (o miss segurado 2) foram APOSENTADAS pela ordem do dono
/// (dump 1.0-80): o indicador de app ficava PRESO quando janelas
/// transitórias fechavam — o botão seguia "aberto" depois do fecho
/// porque a dock segurava o snapshot velho POR DESENHO. O snapshot do
/// bus é a FONTE: o que ele diz É o estado, na hora — janela que
/// fechou, indicador que apaga no mesmo frame do evento (o bus entrega
/// o Windows fresco com latência ~0). Fio morto = sessão sem janelas
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

/// O TICK de 5s (segurança — o push do bus domina a latência do
/// snapshot; aqui mora a ceifa dos filhos e o guard dos lançamentos:
/// o reload dos pins é do VIGIA do arquivo desde a 1.0-110 T1 — a
/// re-leitura periódica morreu por desenho da diretriz).
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
            .retain(|_k, t| now.duration_since(*t).as_secs_f64() < GUARD_S);
    }
    // 1.0-110 T1 — O RELOAD PERIÓDICO DOS PINS MORREU COM O VIGIA: o
    // craft-pin add/rm acorda o FileMonitor do diretório NO MESMO
    // evento do arquivo (inotify) — o tick segue só para ceifa/guard.
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
                    // E101 (1) → 1.0-109 — A LIST FRESCA É O PUSH (o
                    // snapshot do Estado é sempre o ÚLTIMO quadro do
                    // compositor por EVENTO — a conexão de CLIQUE de era
                    // morreu com o with_client: a ceifa NUNCA abre fio
                    // nem espera IPC na main thread)
                    let mapped = sock::key_mapped(&s.snap, k);
                    if mapped {
                        log(&format!(
                            "guard aposentado: {k} mapeou (o push da morte do \
                             lançador) — clique é foco imediato"
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

/// E139 — A OPERAÇÃO NO PAPEL (dock-pins): o que a dock escreve quando o
/// juízo manda. Atualiza troca o id da linha (o hint da 2ª coluna e
/// qualquer comentário de cauda SOBREVIVEM); Remove poda a linha morta.
enum PodaOp {
    Atualiza { de: String, para: String },
    Remove(String),
}

/// E139 — A ESCRITA ATÔMICA DO dock-pins com RE-LEITURA NA HORA: o papel
/// é lido DE NOVO dentro da operação — o unpin do craft-pin que chegou
/// enquanto a dock julgava é respeitado NA HORA (a operação corre sobre
/// o conteúdo FRESCO; linha que o dono já tirou não é ressuscitada).
/// tmp+rename no MESMO dir: o corte de luz nunca deixa o arquivo pela
/// metade. Devolve true se o papel mudou.
fn pins_aplica(op: &PodaOp) -> bool {
    let path = pins_path();
    let Ok(txt) = std::fs::read_to_string(&path) else {
        return false;
    };
    let (alvo, nova): (&str, Option<&str>) = match op {
        PodaOp::Atualiza { de, para } => (de, Some(para)),
        PodaOp::Remove(id) => (id, None),
    };
    let mut out = String::new();
    let mut achou = false;
    for linha in txt.lines() {
        let t = linha.trim();
        let primeira = t.split_whitespace().next().unwrap_or("");
        if primeira == alvo {
            achou = true;
            // o resto da linha (o hint na 2ª coluna, comentário de cauda)
            // — a linha morta morre (o None da era era um braço vazio)
            if let Some(para) = nova {
                let resto = t.strip_prefix(primeira).unwrap_or("");
                out.push_str(para);
                out.push_str(resto);
                out.push('\n');
            }
            continue;
        }
        out.push_str(linha);
        out.push('\n');
    }
    if !achou {
        return false; // o unpin do dono chegou antes — nada a reescrever
    }
    let tmp = path.with_extension("elite-tmp");
    std::fs::write(&tmp, out.as_bytes()).is_ok() && std::fs::rename(&tmp, &path).is_ok()
}

/// Os PINS: re-lê o dock-pins (1 desktop-id por linha, 2ª coluna =
/// hint de app_id, '#' é comentário), resolve cada id pela ESCADA ÚNICA
/// (icons::resolve_pin — a MESMA régua que julga a poda) e cria os
/// botões NA ORDEM DO ARQUIVO.
///
/// E139 — A DOCK QUE CURA OS PRÓPRIOS PINS: o id que a escada resolveu
/// com o ARQUIVO REAL (variação de caixa ou de prefixo do Gear Lever) é
/// ATUALIZADO no papel (tmp+rename com re-leitura fresca) e MANTÉM —
/// nunca podado. O id que NÃO resolve em DUAS passadas seguidas é
/// PODADO (o .desktop não existe em nenhum dir XDG — o loop do "pin
/// ignorado (desktop inexistente)" morre por desenho). A remontagem é
/// DIFF-GUARD: só quando o conjunto resolvido muda (zero recriação por
/// tick — a lei v2.10.0).
fn rebuild_pins(st: &Rc<RefCell<State>>) {
    let mut resolved: Vec<(icons::DesktopEntry, String)> = Vec::new();
    let mut ops: Vec<PodaOp> = Vec::new();
    let mut falhas: Vec<String> = Vec::new();
    {
        let s = st.borrow();
        for pin in read_pins(&pins_path()) {
            let hit = icons::resolve_pin(&s.index, &s.entries, &pin.desktop_id).cloned();
            match hit {
                Some(e) => {
                    if e.id != pin.desktop_id {
                        // a escada achou o ARQUIVO REAL: atualiza e mantém
                        log(&format!(
                            "pin resolvido pela escada: {} → {} (atualizado no papel, mantido — E139)",
                            pin.desktop_id, e.id
                        ));
                        ops.push(PodaOp::Atualiza {
                            de: pin.desktop_id.clone(),
                            para: e.id.clone(),
                        });
                    }
                    resolved.push((e, pin.hint));
                }
                None => falhas.push(pin.desktop_id.clone()),
            }
        }
    }
    // o juízo das faltas: 2 passadas seguidas sem resolver = a poda
    // (fora do borrow — a escrita re-lê o papel fresco dentro dela)
    for id in &falhas {
        let n = {
            let mut s = st.borrow_mut();
            let n = s.pin_misses.entry(id.clone()).or_insert(0);
            *n += 1;
            *n
        };
        if n >= 2 {
            log(&format!(
                "pin morto podado: {id} (2 faltas seguidas — o .desktop não existe em nenhum dir XDG — E139)"
            ));
            ops.push(PodaOp::Remove(id.clone()));
        } else {
            log(&format!(
                "pin ignorado (desktop inexistente): {id} (falta {n}/2 — a poda espera a 2ª passada)"
            ));
        }
    }
    for (e, _) in &resolved {
        st.borrow_mut().pin_misses.remove(&e.id);
    }
    for op in &ops {
        pins_aplica(op);
    }
    // a remontagem é DIFF-GUARD: a chave estável do conjunto resolvido
    let mut chave = String::new();
    for (e, h) in &resolved {
        chave.push_str(&e.id);
        chave.push('\u{1}');
        chave.push_str(h);
        chave.push('\u{2}');
    }
    if st.borrow().pins_chave != chave {
        let mut rows: Vec<PinRow> = Vec::new();
        let mut pin_ids = HashSet::new();
        for (entry, hint) in &resolved {
            let btn = make_app_button(st, entry, hint);
            pin_ids.insert(entry.id.clone());
            rows.push(PinRow {
                button: btn,
                act: Act::App {
                    did: entry.id.clone(),
                    cmd: icons::exec_ready(entry),
                    cands: icons::focus_candidates(entry, ""),
                    name: entry.name.clone(),
                },
            });
        }
        let mut s = st.borrow_mut();
        s.pins = rows;
        s.pin_ids = pin_ids;
        s.pins_chave = chave;
        repack(&s);
        let n = s.pins.len();
        s.window.show();
        log(&format!("pins remontados: {n} fixado(s)"));
    } else {
        st.borrow_mut().pins_chave = chave;
    }
    // o papel que a dock enxerga é o do DISCO (as ops acima podem ter
    // mudado o arquivo — o estado segue a verdade, nunca a memória)
    st.borrow_mut().pins_txt = std::fs::read_to_string(pins_path()).unwrap_or_default();
    // 1.0-102 — A RECONCILIAÇÃO ATÔMICA DO CICLO (a duplicação
    // transitória do pin morre aqui): o pin promovido e o dinâmico que
    // o representava são julgados NO MESMO ciclo de renderização — o
    // sync_dynamic lê o pin_ids NOVO (o dinâmico do app fixado SAI da
    // pílula no mesmo frame, nunca dois botões do mesmo app por alguns
    // instantes) e o update_indicators acende o .running no botão NOVO
    // NA HORA (o indicador de estado aberto não espera o tick de 5s).
    // Todo caminho que remonta os pins — o menu de camada (Fixar/
    // Desafixar), o SIGUSR2 (craft-pin de fora), o tick de segurança — sai
    // daqui com a pílula COERENTE com o snapshot vivo, num ciclo só.
    sync_dynamic(st);
    update_indicators(&st.borrow());
}

/// A pílula REMONTA em ordem canônica (pins · fio · dinâmicos · raws)
/// — SÓ quando o conjunto muda (zero remontagem por tick; a lei
/// v2.10.0 do diff-guard na forma que a GTK4 simplifica: widgets são
/// REORDENADOS, nunca recriados — o flicker da recriação é o que o
/// dono rejeitou). A transição ANIMADA v2.11 é degrau seguinte.
/// E148 — O CICLO DE VIDA DOS POPOVERS MORREU COM ELES (1.0-109 §2.1:
/// o menu de camada é UMA janela TOPLEVEL — nunca filho de botão, o
/// 'Gtk-WARNING: Finalizing dockbtn … still has children left:
/// GtkPopoverMenu' e os ESPAÇOS PRETOS ÓRFÃOS de era eram o enterro
/// do popover pendurado; hoje o botão morto sai SECO da pílula).
/// O queue_resize da pílula E da JANELA fecha o ciclo no MESMO frame
/// (a largura nova do layer-shell nasce sem espaço residual).
fn repack(s: &State) {
    let pill = &s.pill;
    // solta todos (os widgets vivem nas maps — só a ORDEM muda; o botão
    // morto sai SECO da pílula: o menu de camada é janela própria, nada
    // mora pendurado nele — 1.0-109 §2.1)
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
    // E151 — o fecho do repack É o flush ÚNICO (o recálculo da superfície
    // mora numa função só; todo caminho que mexe na pílula — tick de 5s,
    // SIGUSR2, pin do menu de camada, snapshot do bus, abertura/fecho —
    // sai com a surface commitada no MESMO frame)
    flush_superficie(pill, &s.window);
}

/// E151 — O FLUSH ÚNICO DA SUPERFÍCIE (a diretriz: recálculo síncrono em
/// TODO evento de janela — Closed · Minimize · Maximize · Pin · Unpin ·
/// abertura): queue_draw + queue_resize da pílula E da janela + o ajuste
/// imediato da largura natural (a layer-shell só redimensiona quando a
/// árvore GTK comita — o trio no MESMO frame) e o flush do display. OS
/// CAMINHOS: o snapshot do bus (Closed/Minimize/Maximize — o dreno
/// chama recalcula_superficie SEMPRE, mesmo quando o conjunto não mudou:
/// o evento de flags NÃO pode esperar por outra ação na tela), o repack
/// (Pin/Unpin/abertura — os dinâmicos/pins remontam) e o ouvidor de
/// monitores (geometria/escala) — todos terminam AQUI, sem faixa preta
/// nem pílula defasada (a lei E144: resize é commit, não animação).
fn flush_superficie(pill: &gtk::Box, window: &gtk::ApplicationWindow) {
    pill.queue_draw();
    pill.queue_resize();
    // 1.0-100 — O RESIZE REAL DA SUPERFÍCIE (audit 99 §3 — a FAIXA
    // PRETA ao fechar apps): o gtk4-layer-shell SÓ comita o tamanho
    // novo quando a GtkWindow refaz o layout dela — e uma largura
    // explícita (set_default_size de era ou a última alocação
    // memorizada pela GTK) SEGURA a superfície no tamanho velho mesmo
    // com os ícones já fora. O par canônico da casa: set_default_size
    // (-1, -1) devolve a largura ao NATURAL da árvore e o queue_resize
    // força o relayout — o commit do layer-shell encolhe a superfície
    // NO MESMO frame da remoção (o flush de baixo dá a garantia de
    // pedido ao servidor; a lei E144 intacta: resize é commit).
    window.set_default_size(-1, -1);
    window.queue_resize();
    if let Some(d) = gdk::Display::default() {
        d.flush();
    }
}

/// E149 — O RECALCULO UNIVERSAL DA SUPERFÍCIE (a diretriz: force o
/// recálculo real da wl_surface ao fechar/remover ícones — a pílula
/// encolhe NO FRAME do evento, sem espaço preto à direita): o
/// queue_draw + o queue_resize da pílula E da janela e o flush do
/// display numa função única — o repack do tick de 5s, o SIGUSR2, a
/// ação do menu de camada e o snapshot do bus partilham o MESMO fecho (o
/// flush era só do caminho do snapshot — os outros deixavam o frame
/// velho respirar até o próximo repaint).
fn recalcula_superficie(st: &Rc<RefCell<State>>) {
    let s = st.borrow();
    flush_superficie(&s.pill, &s.window);
}

/// ── BLOCO 3 — O OUVIDOR DO MONITOR (a ordem do dono: GdkMonitor/
/// wl_output por EVENTO, zero polling ocioso) ──────────────────────
/// O gesto é EVENTO, nunca poll: `monitor-added`/`monitor-removed`/
/// `monitors-changed` (o display) e `invalidate` (CADA monitor — o sinal
/// de GEOMETRIA/ESCALA do wl_output; docs GDK: "emitted when the
/// monitor's geometry or scale changes") re-afirmam a âncora base e a
/// zona exclusiva e commit o resize NO MESMO frame via
/// recalcula_superficie (a lei E144: resize é commit, não animação) —
/// a pílula recalcula geometria em troca de resolução/Hz/escala e em
/// hotplug sem renascer (o DRM uevent do elite-daemon SIGUSR2 cuida do
/// refresh dos pins; ESTE ouvidor cuida da GEOMETRIA). O frame pacing
/// segue o frame clock do compositor (frame callbacks do Wayland) —
/// alinhado ao Hz nativo por desenho do protocolo, sem timer nenhum.
fn ouve_monitores(window: &gtk::ApplicationWindow, pill: &gtk::Box) {
    let Some(disp) = gdk::Display::default() else {
        return;
    };
    // o re-afirmar ÚNICO (âncora base + zona exclusiva + o MESMO flush
    // da pílula E151: queue_draw/queue_resize/flush)
    let reafirma = move |window: &gtk::ApplicationWindow, pill: &gtk::Box| {
        window.set_anchor(gtk4_layer_shell::Edge::Bottom, true);
        window.auto_exclusive_zone_enable();
        flush_superficie(pill, window);
    };
    // os monitores VIVOS no arranque: o invalidate é o sinal de
    // geometria/escala do wl_output (a troca de modo chega AQUI)
    let lista = disp.monitors();
    for i in 0..lista.n_items() {
        let Some(mon) = lista.item(i).and_downcast::<gdk::Monitor>() else {
            continue;
        };
        let w = window.clone();
        let p = pill.clone();
        mon.connect_invalidate(move |_| reafirma(&w, &p));
    }
    // hotplug/churn — O SUBSTITUTO CANÔNICO (a cura do Canal vermelho
    // #45632905510: o gdk4 0.11.5 NÃO gera os sinais monitor-added/
    // monitor-removed/monitors-changed — deprecated desde o GTK 4.16, o
    // gir do 0.11 os deixou FORA de DisplayExt e o E0599 julgou; o
    // comentário da era que dizia 'deprecated SÓ sob a feature v4_16, o
    // 0.11 o entrega sem aviso' MENTIA — a classe E33 morre junto). A
    // via viva do GDK ≥4.16 é o GListModel de monitors(): o items-changed
    // cobre hotplug E churn num ouvidor só (docs GDK: "use the list model
    // and monitor changes" — o mesmo modelo que a casa já percorre acima).
    {
        let w = window.clone();
        let p = pill.clone();
        let l = lista.clone();
        l.connect_items_changed(move |model, pos, removidos, adicionados| {
            // cada monitor NOVO ganha o próprio ouvidor de invalidate
            // (o gesto de GEOMETRIA/escala chega por ele, não por aqui)
            for i in pos..pos + adicionados {
                let Some(mon) = model.item(i).and_downcast::<gdk::Monitor>() else {
                    continue;
                };
                let novo_w = w.clone();
                let novo_p = p.clone();
                mon.connect_invalidate(move |_| reafirma(&novo_w, &novo_p));
            }
            if removidos > 0 || adicionados > 0 {
                // a saída de um monitor: a âncora sobrevive no output que
                // fica; o churn reafirma de qualquer forma
                reafirma(&w, &p);
                log("GdkDisplay: items-changed no modelo de monitores — âncora/zona exclusiva re-afirmadas");
            }
        });
    }
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
        "{name} — esquerdo: focar/abrir · direito: menu (fixar · nova janela · fechar)"
    )));
    let act = Act::App {
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
    let (home, uid) = {
        let s = st.borrow();
        (s.home.clone(), s.uid)
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
            let key = key.to_string();
            std::thread::spawn(move || {
                let dest = icons::appicon_cache_path(&appicon_cache_dir(), &ai.to_string_lossy());
                if let Some(got) = procapp::extract_diricon(&m, &dest) {
                    // 1.0-110 T1 — a extração entrega pela PONTE (o idle
                    // da main thread veste o ícone — sem canal, sem dreno)
                    entrega(Msg::IconReady { key, path: got });
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
            // 1.0-105 — a rede de era primeiro (quem já colheu não
            // re-extrai) e o MISS veste o caminho novo da dose
            let cached = crate::exeicon_cache_lookup(&exe.to_string_lossy());
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
                let key = key.to_string();
                std::thread::spawn(move || {
                    let dest = icons::exe_icon_cache_path(&crate::exeicon_cache_dir(), &exe.to_string_lossy());
                    if let Some(got) = icons::extract_pe_icon(&exe, &dest) {
                        // 1.0-110 T1 — a extração entrega pela PONTE
                        entrega(Msg::IconReady { key, path: got });
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
        "{name} — esquerdo: focar/ciclar · direito: menu (fixar · nova janela · fechar)"
    )));
    wire_clicks(
        st,
        &btn,
        Act::Raw { key: key.to_string(), name: name.to_string() },
    );
    btn
}

/// A GRAMÁTICA DO CLIQUE (v2.10.10, UMA para pin/dinâmico/raw) —
/// E140, REESCRITA PELO DOSSIÊ 1.0-88: o verbo dispara EXCLUSIVAMENTE
/// no GestureClick::released com tolerância de arrasto < 5px — o
/// conflito press×clicked (o verbo no `connect_pressed` E de novo no
/// `connect_clicked` do release) era o "clique rápido que foca E
/// minimiza no mesmo segundo" do dock.log: 'foco por id 10' seguido
/// de 'toggle: minimizado por id 10' em toda tentativa de clique
/// curto — o dono tinha que SEGURAR o botão para o release chegar
/// antes do segundo verbo. O `connect_clicked` segue vivo SÓ para o
/// TECLADO (Espaço/Enter): o eco do mouse morre na bandeira `eco`
/// (o release do gesto marca; o clicked que vem logo atrás do mouse
/// encontra a bandeira e sai — o do teclado encontra limpa e age).
fn wire_clicks(st: &Rc<RefCell<State>>, btn: &gtk::Button, act: Act) {
    // E140 — O MENU DO BOTÃO DIREITO (a gaveta fuzzel dos pins morreu
    // E140 atrás: Fixar/Desafixar mora AGORA no botão do próprio app,
    // com Nova janela e Fechar — a ordem do dono, Parte 2 do dossiê).
    // 1.0-109 §2.1 — O MENU VESTE A CAMADA: o PopoverMenu de era era
    // FILHO da superfície top da dock — a gaveta do craft-apps (a
    // MESMA camada top) que nascia DEPOIS o cobria inteiro, e o grab
    // dele engolia o 1º clique destinado ao ícone (o dump 1.0-108
    // fotografou os dois); o menu agora é UMA janela Overlay própria
    // (o MenuCamada da fundação) — SEMPRE acima da gaveta e o clique
    // fora o desce SEM engolir nada.
    let btn_c = btn.clone();
    let press = std::rc::Rc::new(std::cell::Cell::new((0.0f64, 0.0f64)));
    let eco = std::rc::Rc::new(std::cell::Cell::new(false));
    let gesture = gtk::GestureClick::new();
    gesture.set_button(0);
    {
        let press = press.clone();
        gesture.connect_pressed(move |_g, _n, x, y| {
            press.set((x, y));
        });
    }
    {
        let st = st.clone();
        let act = act.clone();
        let press = press.clone();
        let eco = eco.clone();
        gesture.connect_released(move |g, _n, x, y| {
            let (px, py) = press.get();
            if ((x - px) * (x - px) + (y - py) * (y - py)).sqrt() >= ARRASTO_PX {
                return; // ARRASTO, não clique (a tolerância do dossiê)
            }
            eco.set(true); // o eco do clicked do mouse morre aqui
            match g.current_button() {
                1 => on_left(&st, &act),
                // o direito é o MENU de camada (o verbo "nova sessão"
                // mora no item dele — o menu do botão que chamou)
                3 => abre_menu_dock(&st, &act, &btn_c),
                _ => {}
            }
            // E151 — O MEIO MORREU COM DIREITO: o verbo "encerrar"
            // escondido num clique do meio era redundância (o mesmo
            // verbo mora no item "Fechar" do menu completo do
            // direito — um destino = um lugar, a lição do dump);
            // cliques do meio não fazem NADA na dock da casa.
        });
    }
    btn.add_controller(gesture);
    // o TECLADO segue (Espaço/Enter = o verbo do esquerdo): o
    // clicked do mouse encontra a bandeira `eco` e sai calado
    {
        let st = st.clone();
        let act = act.clone();
        btn.connect_clicked(move |_| {
            if eco.get() {
                eco.set(false);
                return; // o eco do release do mouse — o gesto já falou
            }
            on_left(&st, &act);
        });
    }
}

/// 1.0-109 §2.1 — O DIREITO ABRE O MENU DE CAMADA: aberto FECHA
/// (toggle), fechado NASCE vestido para ESTE botão (a MESMA janela,
/// o conteúdo do act — o menu do botão que chamou, centrado nele,
/// ACIMA da pílula: a mãe mora na BASE e o menu sobe ATRÁS dela).
fn abre_menu_dock(st: &Rc<RefCell<State>>, act: &Act, btn: &gtk::Button) {
    let menu = st.borrow().menu.clone();
    if menu.aberto() {
        menu.fecha(); // o toggle de sempre: o direito de novo desce
        return;
    }
    menu.conteudo(&monta_menu_dock(st, act));
    menu.abre(btn, true); // a mãe mora na BASE: o menu sobe ATRÁS dela
}

/// O CONTEÚDO do menu do botão (Fixar/Desafixar conforme o estado VIVO
/// dos pins + Nova janela + Fechar — E140 intacto na carne nova).
/// E106/5 — O SEM-NOME TAMBÉM FIXA: com a PROVA de origem do /proc (ou
/// já fixado pelo .desktop LOCAL gerado), o par de pins nasce no raw —
/// a fixação gera o endereço e segue o fluxo normal; SEM prova o item
/// SOME (o menu não promete o que não lança — honestidade).
fn monta_menu_dock(st: &Rc<RefCell<State>>, act: &Act) -> gtk::Box {
    let corpo = gtk::Box::new(gtk::Orientation::Vertical, 2);
    corpo.set_margin_top(4);
    corpo.set_margin_bottom(4);
    match act {
        Act::App { did, name, .. } => {
            let fixado = st.borrow().pin_ids.contains(did);
            let rotulo = if fixado { "Desafixar da Dock" } else { "Fixar na Dock" };
            corpo.append(&linha_de_menu(rotulo, {
                let st = st.clone();
                let did = did.clone();
                let name = name.clone();
                move || {
                    let fixado = st.borrow().pin_ids.contains(&did);
                    if fixado {
                        if pins_aplica(&PodaOp::Remove(did.clone())) {
                            log(&format!(
                                "pin: {name} DESAFIXADO pelo menu de camada (E140 — escrita atômica + remontagem na hora)"
                            ));
                            rebuild_pins(&st);
                        }
                    } else if pins_adiciona(&did) {
                        log(&format!(
                            "pin: {name} FIXADO pelo menu de camada (E140 — a gaveta fuzzel dos pins morreu)"
                        ));
                        rebuild_pins(&st);
                    }
                    st.borrow().menu.fecha();
                }
            }));
        }
        // E106/5 — o par de pins do SEM-NOME (a prova do /proc decide;
        // sem prova o item NEM NASCE — o menu não promete o que não lança)
        Act::Raw { key, name } => {
            let id_local = icons::elite_desktop_id(key);
            let ja_fixado = st.borrow().pin_ids.contains(&id_local);
            let prova = procapp::raw_exec_provavel(Path::new("/proc"), key, st.borrow().uid);
            if ja_fixado || prova.is_some() {
                let rotulo = if ja_fixado { "Desafixar da Dock" } else { "Fixar na Dock" };
                corpo.append(&linha_de_menu(rotulo, {
                    let st = st.clone();
                    let key = key.clone();
                    let name = name.clone();
                    move || {
                        let id_local = icons::elite_desktop_id(&key);
                        let fixado = st.borrow().pin_ids.contains(&id_local);
                        if fixado {
                            if pins_aplica(&PodaOp::Remove(id_local.clone())) {
                                remove_desktop_gerado(&st, &id_local);
                                log(&format!(
                                    "pin: {name} DESAFIXADO pelo menu de camada (o .desktop \
                                     local gerado saiu junto — E106/5, escrita atômica + remontagem na hora)"
                                ));
                                reindexa_desktops(&st);
                                rebuild_pins(&st);
                            }
                        } else if fixa_raw(&st, &key, &name) {
                            log(&format!(
                                "pin: {name} FIXADO pelo menu de camada (o sem-nome ganhou \
                                 .desktop local — E106/5, o AppImage virou app de verdade)"
                            ));
                            reindexa_desktops(&st);
                            rebuild_pins(&st);
                        } else {
                            log(&format!(
                                "pin do sem-nome sem prova de origem ({key}) — nada fixado \
                                 (E106/5; instale o .desktop do app e ele vira dinâmico completo)"
                            ));
                        }
                        st.borrow().menu.fecha();
                    }
                }));
            }
        }
    }
    corpo.append(&separa_menu());
    // NOVA JANELA (o verbo do direito antigo) — 1.0-109 §2.1: a gaveta
    // aberta desce JUNTO (a diretriz: o menu fecha o craft-apps para a
    // janela nova nascer À VISTA na hora)
    corpo.append(&linha_de_menu("Nova janela", {
        let st = st.clone();
        let act = act.clone();
        move || {
            st.borrow().menu.fecha();
            dismiss_overlays();
            on_right_antigo(&st, &act);
        }
    }));
    // FECHAR (o verbo do meio antigo — CLOSE gracioso por id)
    corpo.append(&linha_de_menu("Fechar", {
        let st = st.clone();
        let act = act.clone();
        move || {
            st.borrow().menu.fecha();
            dismiss_overlays(); // a gaveta desce JUNTO do fecho (§2.1)
            on_middle(&st, &act);
        }
    }));
    corpo
}

/// 1.0-109 §2.1 — A LINHA DO MENU DE CAMADA (o botão puro da casa: a
/// pele mora no `#menuwin` da folha mestra, o rótulo mora à esquerda e
/// o verbo viaja no closure do clique — nada de grupo global com
/// estado velho).
fn linha_de_menu(rotulo: &str, verbo: impl Fn() + 'static) -> gtk::Button {
    let btn = gtk::Button::new();
    let rot = gtk::Label::new(Some(rotulo));
    rot.set_halign(gtk::Align::Start);
    btn.set_child(Some(&rot));
    btn.set_has_frame(false);
    btn.set_hexpand(true);
    btn.connect_clicked(move |_| verbo());
    btn
}

/// 1.0-109 §2.1 — o divisor sutil entre o grupo dos pins e os verbos
/// da janela (a mesma régua do §2.3: 1px na cor da borda, com o
/// respiro dos lados — a pele mora no `#menuwin separator` da mestra).
fn separa_menu() -> gtk::Separator {
    gtk::Separator::new(gtk::Orientation::Horizontal)
}


/// E140 — A FIXAÇÃO ATÔMICA (o par da pins_aplica): lê o papel FRESCO,
/// o id ausente entra NO FIM (a ordem do arquivo é a ordem da pílula),
/// tmp+rename no MESMO dir — o corte de luz nunca deixa pela metade.
/// false = já fixado ou papel inacessível (nada a reescrever).
fn pins_adiciona(id: &str) -> bool {
    let path = pins_path();
    let mut txt = std::fs::read_to_string(&path).unwrap_or_default();
    for linha in txt.lines() {
        if linha.split_whitespace().next() == Some(id) {
            return false; // já fixado — o estado não mente
        }
    }
    if !txt.is_empty() && !txt.ends_with('\n') {
        txt.push('\n');
    }
    txt.push_str(id);
    txt.push('\n');
    // 2.0 — a escrita cruza o contrato do elite-core (tmp na MESMA pasta +
    // fsync + rename; o mesmo gesto que cura os pins cura todo o estado)
    elite_core::persist::write_atomic(&path, txt.as_bytes()).is_ok()
}

/// E106/5 — A FIXAÇÃO DO SEM-NOME: gera o .desktop LOCAL em
/// ~/.local/share/applications/elite-<chave>.desktop (Name = o nome do
/// botão, Exec = a PROVA de origem do /proc — o MESMO lançamento que o
/// "Nova janela" usa, Icon = o ícone já colhido nos caches da casa
/// quando existe, StartupWMClass = a chave, NoDisplay=false) e fixa
/// pelo FLUXO NORMAL (pins_adiciona com o id novo). O papel é do DONO
/// (~/.local), nunca do sistema; sem prova de lançamento a fixação NEM
/// acontece (o item do menu já não nasce).
fn fixa_raw(st: &Rc<RefCell<State>>, key: &str, name: &str) -> bool {
    let (home, uid) = {
        let s = st.borrow();
        (s.home.clone(), s.uid)
    };
    let Some(exec) = procapp::raw_exec_provavel(Path::new("/proc"), key, uid) else {
        return false; // sem prova: a casa nunca fixa o que não lança
    };
    let id_local = icons::elite_desktop_id(key);
    let dir = home.join(".local/share/applications");
    let _ = std::fs::create_dir_all(&dir);
    let icon = raw_icon_caminho(key, uid);
    let corpo = icons::desktop_do_raw(key, name, &exec, icon.as_deref());
    // 2.0 — a escrita cruza o contrato do elite-core (tmp na MESMA pasta
    // + fsync + rename; o mesmo gesto que cura os pins cura o endereço)
    elite_core::persist::write_atomic(&dir.join(&id_local), corpo.as_bytes()).is_ok()
        && pins_adiciona(&id_local)
}

/// E106/5 — o ÍCONE do sem-nome para o .desktop gerado: o que a casa
/// JÁ colheu nos caches (o appimage-icons do AppImage · o icons do
/// .exe Wine/Proton) — o caminho de ARQUIVO vira Icon=; sem colheita o
/// campo omite (a cadeia completa mora no make_raw_button; aqui é só
/// o que o papel consegue prometer com verdade).
fn raw_icon_caminho(key: &str, uid: u32) -> Option<PathBuf> {
    if let Some((ai, _)) = procapp::proc_appimage(Path::new("/proc"), key, uid) {
        let c = icons::appicon_cache_path(&appicon_cache_dir(), &ai.to_string_lossy());
        if c.is_file() {
            return Some(c);
        }
    }
    if let Some(exe) = procapp::proc_wine_exe(Path::new("/proc"), key, uid) {
        let c = crate::exeicon_cache_lookup(&exe.to_string_lossy());
        if c.is_file() {
            return Some(c);
        }
    }
    None
}

/// E106/5 — O DESAFIXAR APAGA SÓ O QUE A CASA GEROU: o .desktop local
/// com a assinatura da primeira linha sai com o pin; o .desktop do
/// dono, colocado à mão com o mesmo nome, FICA (o papel é dele — a
/// assinatura é o contrato).
fn remove_desktop_gerado(st: &Rc<RefCell<State>>, id_local: &str) {
    let path = st
        .borrow()
        .home
        .join(".local/share/applications")
        .join(id_local);
    match std::fs::read_to_string(&path) {
        Ok(txt) if icons::eh_desktop_da_casa(&txt) => {
            let _ = std::fs::remove_file(&path);
        }
        _ => {} // não é da casa (ou já saiu): o papel do dono fica
    }
}

// ── os VERBOS (a gramática UMA da casa) ───────────────────────────────

/// As janelas REAIS de um alvo no snapshot atual (strict = o verbo
/// DESTRUTIVO: o título nunca manda WM_DELETE — a lei E36).
/// 1.0-110 T6 — A DOCK É DA MESA CORRENTE (a diretriz: o espelho do
/// Alt+Tab — as janelas que contam são as DA MESA ATUAL, s.mesa): a
/// janela de mesa CONHECIDA ≠ corrente não acende o indicador, não
/// conta no clique e não nasce botão dinâmico; o desk None segue
/// PRESUMIDO VISÍVEL (a convenção 1.0-100: o desconhecido não mentiu).
fn janela_da_mesa(s: &State, id: u64) -> bool {
    s.snap
        .windows
        .get(&id)
        .and_then(|w| w.desk)
        .map(|d| d == s.mesa)
        .unwrap_or(true)
}

/// 1.0-110 T6 — as janelas do alvo NA MESA CORRENTE (o casamento de
/// sempre do sock::windows_of_key filtrado pela mesa — on_left,
/// on_middle e update_indicators vestem TODOS a mesma régua: 0 janelas
/// na mesa atual = SEM bolinha de aberto e o esquerdo LANÇA nova
/// instância na mesa atual em vez de pular para outra).
fn windows_of_state(s: &State, act: &Act, strict: bool) -> Vec<u64> {
    let todos = match act {
        Act::App { cands, name, .. } => {
            sock::windows_of_key(&s.snap, cands, name, strict)
        }
        Act::Raw { key, .. } => sock::raw_windows(&s.snap, key, strict),
    };
    todos.into_iter().filter(|id| janela_da_mesa(s, *id)).collect()
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
/// E146/C — A COVEIRA (a mesma lição da solta da barra): o pkill
/// abandonado no Drop virava <defunct> pendurado na dock; a thread
/// dedicada colhe o exit ANTES do escopo morrer.
fn dismiss_overlays() {
    std::thread::spawn(|| {
        if let Ok(mut filho) = Command::new("pkill")
            .args(["-x", "nwg-drawer"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .process_group(0)
            .spawn()
        {
            let _ = filho.wait();
        }
    });
}

/// 1.0-109 — O VERBO PELO FIO PERSISTENTE (a diretriz da dose: UMA
/// conexão única para a vida da dock — o `bus.cliente 3..7` do dump era
/// um ToplevelClient NOVO por clique, cada um com a própria thread
/// leitora de 1s; e NENHUMA operação de IPC bloqueia a thread
/// principal do GTK durante os cliques). O send_req da fundação é
/// fire-and-forget com o teto de ESCRITA de 500ms (o fio surdo não
/// congela o lock do bus e o shutdown limpo envenena nada); o eco chega
/// pelo MESMO fio como Msg::Ack (nomeado no papel pelo dreno) e o daemon
/// publica o snapshot NOVO a seguir — quem corrige um verbo perdido é
/// sempre o frame seguinte, nunca uma espera do clique.
fn pede_verbo(st: &Rc<RefCell<State>>, req: elite_core::BusReq) -> bool {
    let Some(cli) = st.borrow().bus.clone() else {
        return false; // o daemon ainda não nasceu (o belt de 5s cobre)
    };
    let ok = cli.send_req(req).is_some();
    if !ok {
        log("o fio persistente recusou a escrita (a reconexão E135 já vem — o clique segue pelo snapshot)");
    }
    ok
}

/// O ESQUERDO — foca/cicla (v2.10.1 + E71 + E89): 1 janela →
/// foca/restaura (ou MINIMIZA se ela é a focada — o toggle); N → cicla
/// ENTRE elas (o anel por id, a memória é de quem clicou); 0 → UMA
/// LIST FRESCA julga (a prova no lançamento) e só então abre (com o
/// guard de 8s no gargalo único).
fn on_left(st: &Rc<RefCell<State>>, act: &Act) {
    dismiss_overlays();
    let key = act_key(act);
    let wids = windows_of_state(&st.borrow(), act, false);
    if !st.borrow().tl_alive {
        // daemon morto: o fallback wlrctl é ESCOPO NÃO PORTADO (ver
        // cabeçalho) — o lançar segue, o focar degrada honesto com log
        launch(st, act, Some(&key));
        return;
    }
    if wids.is_empty() {
        // 1.0-109 — A PROVA NO CLIQUE É O PUSH (a ordem E135 contra o
        // snapshot VELHO nasce CURADA por desenho: o daemon publica
        // `Windows` por EVENTO — o snap da dock é sempre o último
        // quadro do compositor, não uma leitura de rodada passada; o
        // round-trip de LIST de era bloqueava a main thread até 1s).
        // O guard E71 do lançamento segue sendo a rede do vão de foco.
        launch(st, act, Some(&key));
        return;
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
            && pede_verbo(st, elite_core::BusReq::Minimize { id: id as u32 })
        {
            log(&format!("toggle: minimizado por id {id} (o eco chega pelo fio — o clique não esperou)"));
            return;
        }
        if pede_verbo(st, elite_core::BusReq::Activate { id: id as u32 }) {
            st.borrow_mut().last_act.insert(key, id);
            log(&format!("foco por id {id} (fire-and-forget no fio persistente)"));
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
        if pede_verbo(st, elite_core::BusReq::Activate { id: n as u32 }) {
            st.borrow_mut().last_act.insert(key.clone(), n);
            log(&format!("ciclo do app: id {n} ({} janelas — pelo fio persistente)", wids.len()));
            return;
        }
    }
    launch(st, act, Some(&key));
}

/// O DIREITO ANTIGO — NOVA SESSÃO (v2.10.10, agora o item "Nova
/// janela" do menu E140): o verbo EXPLÍCITO de duplicar NÃO passa
/// chave (o guard é para o vão do foco, não para o pedido claro do
/// dono). No SEM-NOME, a PROVA de origem do /proc é quem lança (o
/// argv[0] executável → o AppImage do environ — E106/5: o MESMO
/// Exec que o .desktop local da fixação carrega); sem prova, o log
/// ensina (nunca adivinha).
fn on_right_antigo(st: &Rc<RefCell<State>>, act: &Act) {
    dismiss_overlays();
    match act {
        Act::App { .. } => launch(st, act, None),
        Act::Raw { key, .. } => {
            let uid = st.borrow().uid;
            match procapp::raw_exec_provavel(Path::new("/proc"), key, uid) {
                Some(exec) => {
                    log(&format!("nova sessão do sem-nome via /proc: {exec}"));
                    launch_cmd(st, &exec, None);
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
    // 1.0-109 — os verbos viajam PELO FIO PERSISTENTE (um por janela,
    // fire-and-forget: o clique nunca espera o Ack — o daemon publica o
    // snapshot novo e os botões somem no MESMO frame do evento)
    if !st.borrow().tl_alive {
        log("encerrar: sem fio do daemon (o wlrctl é degrau seguinte)");
        return;
    }
    for id in &wids {
        if pede_verbo(st, elite_core::BusReq::Close { id: *id as u32 }) {
            log(&format!("encerrado por id {id} (o eco chega pelo fio)"));
        }
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
        let s = st.borrow_mut();
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
    // (1) AS CHAVES VIVAS: os comms do usuário E os app_ids das JANELAS
    // do snapshot (1.0-102 — A FONTE UNIFICADA: a JANELA é a verdade do
    // "aberto", o comm é o proxy; o app cujo comm não casa com nenhum
    // .desktop (casca truncada de 15, nome de runtime) mas cujo app_id
    // casa (StartupWMClass indexado, lowercase no fold, alternativas
    // reverse-DNS, stems de id composto) agora resolve NA HORA — a
    // MESMA régua do matching do ícone fixado: o botão do app aberto
    // nasce do evento da janela no frame seguinte, sem esperar o
    // scan de /proc do tick).
    let uid = st.borrow().uid;
    let mut chaves: Vec<String> = procapp::scan_user_comms(Path::new("/proc"), uid);
    {
        let s = st.borrow();
        for w in s.snap.windows.values() {
            // 1.0-110 T6 — O PORTAL NUNCA NASCE BOTÃO (a diretriz: o
            // xdg-desktop-portal-gtk dos diálogos de arquivo era o
            // ícone temporário que PISCA na dock — o prefixo é a cerca)
            if w.app_id.starts_with("xdg-desktop-portal") {
                continue;
            }
            if !w.app_id.is_empty() && !chaves.contains(&w.app_id) {
                chaves.push(w.app_id.clone());
            }
        }
    }
    // (2) current: did → (entry, comm) — resolve PELO ÍNDICE (o
    // comm "bazaar" acha o io.github.kolunmi.Bazaar.desktop: nome
    // "Bazaar", ícone oficial, NUNCA raw — a ordem do dono E132)
    let mut current: Vec<(String, icons::DesktopEntry)> = Vec::new();
    {
        let s = st.borrow();
        for chave in &chaves {
            let Some(entry) = icons::resolve_desktop(&s.index, &s.entries, chave) else {
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
            // v2.10.3 — daemon vivo: SEM janela real não é "aberto";
            // 1.0-110 T6 — e a janela tem que ser DA MESA CORRENTE (o
            // dinâmico de OUTRA mesa não nasce botão na dock daqui)
            if s.tl_alive
                && sock::windows_of_key(
                    &s.snap,
                    &icons::focus_candidates(entry, ""),
                    &entry.name,
                    false,
                )
                .iter()
                .all(|id| !janela_da_mesa(&s, *id))
            {
                continue;
            }
            current.push((did, entry.clone()));
        }
    }
    // (2b) 1.0-104 — O TÍTULO NORMALIZADO DA JANELA (a rede dos jogos
    // Proton/Hydra: quando NEM o comm NEM o app_id casam — o app_id
    // steam_app_* casa o .desktop NoDisplay do ~/.local/share/
    // applications pelo índice de cima; o que SOBRA casa o TÍTULO da
    // janela pelo Name do .desktop — o "Stardew Valley" da janela é a
    // identidade de verdade e o ícone de verdade nasce dela)
    {
        let s = st.borrow();
        if s.tl_alive {
            for w in s.snap.windows.values() {
                if w.title.trim().is_empty() {
                    continue;
                }
                let Some(entry) =
                    icons::resolve_por_titulo(&s.name_index, &s.entries, &w.title)
                else {
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
                // (o windows_of_key casa título×nome no não-strict);
                // 1.0-110 T6 — e a janela tem que ser DA MESA CORRENTE
                if sock::windows_of_key(
                    &s.snap,
                    &icons::focus_candidates(entry, ""),
                    &entry.name,
                    false,
                )
                .iter()
                .all(|id| !janela_da_mesa(&s, *id))
                {
                    continue;
                }
                current.push((did, entry.clone()));
            }
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
                // 1.0-110 T6 — janela de OUTRA mesa não nasce botão NA
                // MESA CORRENTE (a diretriz: os dinâmicos e raws são da
                // mesa de quem OLHA — o espelho do Alt+Tab)
                if !janela_da_mesa(&s, w.id) {
                    continue;
                }
                // 1.0-110 T6 — O PORTAL NÃO PISCA (o xdg-desktop-portal-gtk
                // dos diálogos de arquivo nunca veste ícone temporário)
                if w.app_id.starts_with("xdg-desktop-portal") {
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
            row.button.remove_css_class("other-workspace");
        }
        for row in s.raws.values() {
            row.button.remove_css_class("running");
            row.button.remove_css_class("other-workspace");
        }
        return;
    }
    for row in s.pins.iter().chain(s.dyns.values()) {
        let wids = windows_of_state(s, &row.act, false);
        let on = !wids.is_empty();
        if on {
            row.button.add_css_class("running");
        } else {
            row.button.remove_css_class("running");
        }
        // 1.0-100 — O ISOLAMENTO VISUAL DE MESA (audit 99 §4): o botão
        // veste .other-workspace quando TEM janelas e TODAS elas moram
        // em mesa CONHECIDA ≠ a corrente (o desconhecido não mentiu —
        // None é presumido vivo aqui, a dock nunca apaga por falta de
        // informação). O clique segue COERENTE: ativa a janela e o
        // compositor traz a mesa dela para a frente (a tag da casa
        // acerta no foco que chega — workspace::aprende).
        let outra = on
            && wids.iter().all(|id| {
                s.snap
                    .windows
                    .get(id)
                    .and_then(|w| w.desk)
                    .map(|d| d != s.mesa)
                    .unwrap_or(false)
            });
        if outra {
            row.button.add_css_class("other-workspace");
        } else {
            row.button.remove_css_class("other-workspace");
        }
    }
    // os RAW também julgam (a mesma régua da casa)
    for (key, row) in s.raws.iter() {
        let wids = sock::raw_windows(&s.snap, key, false);
        let on = !wids.is_empty();
        if on {
            row.button.add_css_class("running");
        } else {
            row.button.remove_css_class("running");
        }
        let outra = on
            && wids.iter().all(|id| {
                s.snap
                    .windows
                    .get(id)
                    .and_then(|w| w.desk)
                    .map(|d| d != s.mesa)
                    .unwrap_or(false)
            });
        if outra {
            row.button.add_css_class("other-workspace");
        } else {
            row.button.remove_css_class("other-workspace");
        }
    }
}

// ── a pele (o MESMO CSS da casa — ~/.config/elite/dock.css) ───────────

/// A pele da pílula: o CSS do usuário (~/.config/elite/dock.css) veste
/// POR CIMA da folha mestra embutida (elite-core::THEME_CSS — a MESMA
/// fundação de bar/pick: a mestra nunca sai, o override SOMA por baixo
/// do cascade — o dono vence em empate, a casa nunca fica pelada).
/// 1.0-104 — A MESTRA NUNCA MAIS MORRE NO OVERRIDE (a cura do menu de
/// contexto BRANCO: o dock.css de era SUBSTITUÍA a folha inteira e as
/// regras `#menuwin` da mestra — a pele escura dos menus —
/// morriam com ela; o menu de clique direito nascia com o fundo DEFAULT
/// do tema externo. A mestra entra PRIMEIRO, o override vence os
/// empates — o menu de camada é da casa em QUALQUER rig, com ou sem override).
fn load_css() {
    let mestra = elite_core::THEME_CSS;
    let css = std::fs::read_to_string(css_path()).map(|extra| format!("{mestra}\n{extra}"));
    if css.is_err() {
        log(&format!("CSS ausente ({}) — usando a folha mestra embutida", css_path().display()));
    }
    let css = css.unwrap_or_else(|_| mestra.to_string());
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
            gtk::STYLE_PROVIDER_PRIORITY_USER,
        );
    }
}

