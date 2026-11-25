// ELITE · craft-bar-rs — ui.rs (E147 — A RECONSTRUÇÃO DA CAMADA DE UI,
// a ordem do dono do dossiê UI/UX: "abandone o que não funcionou e
// refaça a camada de interface, controles rápidos e integração de
// sessão com uma arquitetura limpa, coesa e bem pensada de UI/UX").
// Este módulo SÓ compila com a feature "gui" (exige o GTK dev do
// ambiente de build do pacote — o CI valida; o sandbox sem GTK
// compila/testa o NÚCLEO: state/main).
//
// O CONTRATO DE INTERAÇÃO ÚNICO (a lei nova da casa, válida para
// TODOS os módulos sem exceção):
//   · CLIQUE ESQUERDO = o CONTROLE PRINCIPAL — SEMPRE um popover
//     nativo GTK4 ancorado no próprio botão (áudio, rede, bluetooth,
//     notificações, sessão, apps). Nunca um fork cego, nunca um menu
//     de texto no terminal;
//   · CLIQUE DIREITO = a FERRAMENTA AVANÇADA de verdade (pwvucontrol,
//     nm-connection-editor, blueman-manager, DND) quando existe;
//   · SCROLL = o gesto de ajuste fino (volume);
//   · HOVER = o feedback visual da pele (theme.css) + o tooltip que
//     diz o que o clique faz.
//
// O QUE MORREU NESTA RECONSTRUÇÃO (o enterro com prova):
//   · O GLIFO NERD FONT NO LABEL (o '\uf085 2' da tela do dono era o
//     codepoint que a fonte GTK padrão não tem — Inter/Adwaita Sans não
//     fala Nerd): TODOS os ícones da barra são AGORA Image::from_icon_name
//     (audio-volume-*, network-*, bluetooth-*, input-gaming, battery-*
//     — o Papirus/GNOME da casa tem todos, o render NUNCA mais quebra);
//   · O MÓDULO DE 2º PLANOS (a pílula dos aplicativos de fundo): a ordem do dono
//     ("deve ser completamente removido — já havia sido solicitado
//     para sair, mas permaneceu na interface e no código") — o botão,
//     a Msg, o belt e o SIGRTMIN+9 saem daqui E do elite-daemon E do
//     pacote (o fóssil morre no post_upgrade com voz);
//   · OS DOIS BOTÕES DE ÁUDIO SOLTO (mute no esquerdo, mixer no
//     direito, zero seleção de dispositivo): o par veste UM botão que
//     abre A CENTRAL DE ÁUDIO unificada — Saída + Entrada com mute
//     imediato, volume por slider, troca de dispositivo a um clique e
//     o mixer completo (pwvucontrol) a um botão;
//   · O BLUETOOTH MUDO (o clique chamava o blueman-manager que o
//     elite-clean REMOVIA do sistema — o conflito estrutural que o
//     dono nomeou): o botão abre o PAINEL de dispositivos (power,
//     conectar/desconectar a um clique, pareados pelo bluetoothctl) e
//     o elite-clean PARA de remover o blueman (o gerenciador volta a
//     existir e o direito o abre).
//
// O QUE FICA (prova de campo da 1.0-94/95 — não se quebra o que funciona):
//   · a FAIXA layer-shell + a LEI DO CLIQUE no released (5px de
//     tolerância de arrasto);
//   · o DRAWER com debounce de 150ms e filho nosso (a gaveta nwg-drawer);
//   · o RELÓGIO pt_BR que nunca muda de texto + o calendário no hover;
//   · o SELETOR RÁPIDO DE REDE (Switch Wi-Fi, redes ao alcance, iwgtk,
//     nm-connection-editor);
//   · o MPRIS/jogo PELO FIO DO BUS + os sinais SIGRTMIN+8 (jogo) e
//     SIGUSR2 (a pele);
//   · a SESSÃO em PopoverMenu nativo e a COVEIRA dos filhos curtos
//     (E146/C — o spawn→wait, zero <defunct>).
use crate::state::{
    bt_conectados, bt_ligado, dentro_janela_ms, essid_nmcli, estado_rede_nmcli, icone_mic,
    icone_rede, icone_volume, json_text, le_bateria, media_pill, parse_bt_devices,
    parse_volume_wpctl, parse_wifi_list, parse_wifi_radio, parse_wpctl_status, relogio_ptbr,
    rotulo_dispositivo, tooltip_rede, BtDispositivo, DispositivoAudio, EstadoRede, RedeWifi,
};
use crate::{bus_sock, css_path, current_uid, log, VERSION};
use elite_core::MediaState;
use std::cell::{Cell, RefCell};
use std::os::unix::fs::MetadataExt;
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::rc::Rc;
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::mpsc::{Receiver, Sender, TryRecvError};
use std::time::{Duration, Instant};

use gtk4::prelude::*;
use gtk4::{gdk, glib};
use gtk4 as gtk;
use gtk4_layer_shell::LayerShell;

/// A altura da faixa (o mesmo 36 da era waybar — a zona exclusiva).
const ALTURA: i32 = 36;
/// O dreno do canal da thread de fundo (latência dos estados ≤100ms).
const DRAIN_MS: u64 = 100;
/// O DEBOUNCE do drawer (a ordem do dono: 150ms, zero bloqueio).
const DRAWER_MS: u64 = 150;
/// A tolerância de arrasto: released a >5px do press é ARRASTO, não
/// clique (a ordem do dono — a mesma lei da dock v2).
const ARRASTO_PX: f64 = 5.0;
/// As cadências da thread de fundo (segundos — o belt do polling; os
/// EVENTOS do daemon chegam por sinal/fio, o belt é a rede de segurança).
const POLL_AUDIO_S: u64 = 2;
const POLL_REDE_S: u64 = 5;
const POLL_BT_S: u64 = 10;
const POLL_CINTO_S: u64 = 30;

/// Os sinais da casa (o handler cru async-signal-safe + o dreno do
/// idle — a glib 0.22 não traz unix_signal_add; a via da dock E132).
static SIG: AtomicI32 = AtomicI32::new(0);
extern "C" fn on_signal(sig: i32) {
    SIG.store(sig, Ordering::SeqCst);
}

/// As mensagens da thread de fundo para a UI (a thread NUNCA toca
/// GTK — a lei da casa; a UI drena no idle de 100ms).
enum Msg {
    /// A FOTO COMPLETA do áudio (E147 — a central unificada): o padrão
    /// de saída e de entrada + as LISTAS dos dois lados. None = o wpctl
    /// engasgou — o estado anterior CONSERVADO, a barra não pisca no
    /// vácuo.
    AudioDet(Option<AudioDetalhe>),
    /// (estado, essid) da rede — o assento é PERSISTENTE por desenho.
    Rede(EstadoRede, Option<String>),
    /// Powered do adaptador (None = bluetoothctl ausente/sem adaptador).
    Bt(Option<bool>),
    /// E147 — a LISTA dos dispositivos pareados + os MACs conectados
    /// (o painel de Bluetooth do clique esquerdo).
    BtLista(Vec<BtDispositivo>, Vec<String>),
    /// O texto do pill do modo de jogo — None = apagado.
    Game(Option<String>),
    /// 2.0 — o estado MPRIS do bus (zero playerctl; o pill some sem mídia)
    Media(Option<MediaState>),
    /// 2.0 — o modo de jogo pelo FIO (o SIGRTMIN+8 é o cinto)
    BusGame(bool),
    /// 2.0 — o handle do bus vivo (o Arc do cliente — os cliques pedem
    /// por ele; chega por mensagem porque o Rc da UI não cruza threads)
    Bus(std::sync::Arc<elite_core::bus::BusClient>),
    /// 1.0-93 — a LISTA de redes do seletor rápido (o nmcli em fundo;
    /// vazia honesta quando não há nada ao alcance)
    RedeLista(Vec<RedeWifi>),
    /// 1.0-93 — o rádio do Wi-Fi (o estado do Switch do seletor; None
    /// honesto quando o nmcli não fala)
    RedeRadio(Option<bool>),
}

/// A FOTO COMPLETA do áudio da casa (o padrão de SAÍDA e o de ENTRADA
/// mais as LISTAS dos dois lados — a central unificada do E147 veste
/// tudo de uma vez, sem meio estado).
struct AudioDetalhe {
    sink: Option<DispositivoAudio>,
    fonte: Option<DispositivoAudio>,
    sinks: Vec<DispositivoAudio>,
    fontes: Vec<DispositivoAudio>,
}

/// A barra inteira (os widgets que mudam + o filho do drawer).
struct State {
    clock_label: gtk::Label,
    btn_audio: gtk::Button,
    /// E147 — o ícone de volume do botão (Image::from_icon_name — o
    /// glifo Nerd morreu com a fonte que não o tinha).
    audio_img: gtk::Image,
    btn_rede: gtk::Button,
    /// E147 — o ícone de rede (Image::from_icon_name).
    rede_img: gtk::Image,
    btn_bt: gtk::Button,
    /// E147 — o ícone de bluetooth (Image::from_icon_name).
    bt_img: gtk::Image,
    btn_game: gtk::Button,
    btn_player: gtk::Button,
    player_label: gtk::Label,
    btn_bat: Option<gtk::Button>,
    // ── E147 · a CENTRAL DE ÁUDIO (os widgets do popover unificado) ──
    /// o rótulo do sink padrão (o rótulo humano da lei §5)
    rot_sink: gtk::Label,
    /// o rótulo do source padrão (o microfone)
    rot_fonte: gtk::Label,
    /// os sliders 0-100 dos dois lados (a verdade do belt só veste
    /// quando o dono NÃO está arrastando)
    esc_sink: gtk::Scale,
    esc_fonte: gtk::Scale,
    /// as bandeiras de ARRASTO (o belt nunca briga com a mão do dono)
    arrasta_sink: Rc<Cell<bool>>,
    arrasta_fonte: Rc<Cell<bool>>,
    /// os debounces pendentes dos sliders (150ms — o wpctl corre UM
    /// vez por pausa do gesto, nunca por pixel)
    pende_sink: Rc<RefCell<Option<glib::SourceId>>>,
    pende_fonte: Rc<RefCell<Option<glib::SourceId>>>,
    /// as LISTAS de dispositivos dos dois lados (remontadas por foto)
    lista_sinks: gtk::Box,
    lista_fontes: gtk::Box,
    /// os ícones dos botões MUTE (a classe .muted é a gramática vermelha)
    img_mute_sink: gtk::Image,
    img_mute_fonte: gtk::Image,
    // ── E147 · o PAINEL DE BLUETOOTH (os widgets do popover) ────────
    /// a lista de pareados (remontada por foto)
    bt_lista: gtk::Box,
    /// o Switch do POWER (a verdade do bluetoothctl show)
    bt_switch: gtk::Switch,
    /// 1.0-93 — o seletor rápido de rede: a lista e o Switch do popover
    rede_lista: gtk::Box,
    rede_switch: gtk::Switch,
    /// O FILHO do drawer (None = gaveta fechada ou aberta por fora —
    /// a varredura /proc do toggle cobre os dois mundos).
    drawer: Option<Child>,
    /// O instante do último release ACEITO no drawer (o eco morre na
    /// janela de 150ms — state::dentro_janela_ms é o juiz).
    drawer_ns: u128,
    /// O último minuto desenhado no relógio (o label só toca na
    /// virada — nenhum gesto por segundo).
    minuto_desenhado: u32,
    rede: EstadoRede,
    essid: Option<String>,
    /// 2.0 — o handle do bus (o Arc do cliente vivo — os pedidos dos
    /// cliques: PlayPause/Next/Focus/mesa/jogo)
    bus_cli: Rc<RefCell<Option<std::sync::Arc<elite_core::bus::BusClient>>>>,
}

pub fn run() -> i32 {
    arma_rt();
    let app = gtk::Application::new(Some("elite.craft.Bar"), Default::default());
    app.connect_activate(|app| build(app));
    app.run().get() as i32
}

/// 1.0-94 — A ARMADURA RT (a cura da morte "zsh: real-time event N" /
/// TOPBAR_COUNT=0): TODO sinal do intervalo real-time (SIGRTMIN..
/// SIGRTMAX) vira HANDLED no PRIMEIRO instante do processo. O padrão do
/// Linux para RT é TERMINAR o processo — e o daemon sinaliza a barra
/// (SIGRTMIN+8: a transição do modo de jogo) e a própria REGISTRAÇÃO
/// do "elite.craft.Bar" no bus dispara sinais ANTES do build() armar os
/// handlers (a janela GTK-init era o cadafalso; o respawn em loop 2s →
/// sinal → morte era o TOPBAR_COUNT=0 do rig da 1.0-93 — a era waybar
/// era imune POR CONFIG, os módulos dela registravam os sinais).
/// E147 — o +9 dos 2º planos NÃO TEM mais emissor (o módulo morreu) e
/// o +8 segue HANDLED no drena; os demais RT viram ruído inofensivo na
/// bandeira (a disposição padrão nunca mais mata a barra, venha o
/// sinal de quem vier).
pub fn arma_rt() {
    unsafe {
        let mut s = libc::SIGRTMIN();
        let max = libc::SIGRTMAX();
        while s <= max {
            libc::signal(s, on_signal as libc::sighandler_t);
            s += 1;
        }
    }
}

fn build(app: &gtk::Application) {
    if !gtk4_layer_shell::is_supported() {
        // o labwc fala layer-shell; se isto aparecer, a sessão mudou.
        // A barra é ESTA (E140 — o waybar aposentou); sem fallback por
        // desenho: a verdade no papel e o respawn do session re-tenta.
        log(&format!(
            "craft-bar-rs {VERSION}: o compositor NÃO fala layer-shell — \
             saindo (a top bar da casa É esta; sem fallback por desenho E140)"
        ));
        return;
    }
    let window = gtk::ApplicationWindow::new(app);
    window.set_widget_name("barwindow");
    // A FAIXA: ancorada Top+Left+Right — a largura é da tela, a zona
    // exclusiva automática reserva a altura das maximizadas.
    window.init_layer_shell();
    window.set_layer(gtk4_layer_shell::Layer::Top);
    window.set_anchor(gtk4_layer_shell::Edge::Top, true);
    window.set_anchor(gtk4_layer_shell::Edge::Left, true);
    window.set_anchor(gtk4_layer_shell::Edge::Right, true);
    window.auto_exclusive_zone_enable();
    window.set_keyboard_mode(gtk4_layer_shell::KeyboardMode::OnDemand);
    window.set_namespace(Some("craft-bar"));
    window.set_default_size(-1, ALTURA);

    // O CORPO (1.0-93 — o CenterBox do dono: o RELÓGIO fica EXATAMENTE
    // no centro da tela, independente da largura dos lados; esquerda
    // minimalista · centro · direita funcional — a convenção 2.0 da casa)
    let corpo = gtk::CenterBox::new();
    corpo.set_widget_name("barbox");
    let esq = caixa_lateral(gtk::Align::Start);
    let centro = caixa_lateral(gtk::Align::Center);
    let dir = caixa_lateral(gtk::Align::End);
    corpo.set_start_widget(Some(&esq));
    corpo.set_center_widget(Some(&centro));
    corpo.set_end_widget(Some(&dir));
    window.set_child(Some(&corpo));

    // o CANAL da thread de fundo (criado ANTES dos botões: o clique
    // de áudio pede o refresh imediato pelo MESMO canal)
    let (tx, rx) = std::sync::mpsc::channel::<Msg>();
    std::thread::spawn({
        let tx = tx.clone();
        move || poller(tx)
    });
    // o frame 0 do jogo: thread curta própria (o arranque do daemon pode
    // demorar um instante — 300ms de cortesia). E147: o bgapps saiu do
    // frame 0 junto com o próprio módulo (a ordem do dono).
    std::thread::spawn({
        let tx = tx.clone();
        move || {
            std::thread::sleep(Duration::from_millis(300));
            if let Some(t) = um_longo("craft-game", &["pill"]) {
                let _ = tx.send(Msg::Game(json_text(&t)));
            }
        }
    });
    // 2.0 — O FIO VIVO: o BusClient persistente (Hello 'craft-bar-rs';
    // a reconexão 5→20→100ms é da fundação — o daemon renasce e a barra
    // reaparece com o snapshot das boas-vindas). O Arc fica com a UI
    // (os pedidos dos cliques); a thread lê QUADROS PARA SEMPRE e veste
    // cada estado na Msg da casa
    {
        let tx = tx.clone();
        let caminho = bus_sock();
        std::thread::spawn(move || {
            loop {
                if let Some((cli, rx)) =
                    elite_core::bus::BusClient::connect(&caminho, "craft-bar-rs")
                {
                    // o Arc chega à UI por mensagem (o Rc não cruza
                    // threads — a lei do GTK; o BusClient é Send+Sync)
                    let _ = tx.send(Msg::Bus(std::sync::Arc::clone(&cli)));
                    for msg in rx {
                        match msg {
                            elite_core::BusMsg::Media(m) => {
                                let _ = tx.send(Msg::Media(if m.player.is_none() && m.title.is_none() {
                                    None
                                } else {
                                    Some(m)
                                }));
                            }
                            elite_core::BusMsg::GameMode(gm) => {
                                let _ = tx.send(Msg::BusGame(gm.active));
                            }
                            _ => {} // áudio/rede da casa seguem nos belts próprios
                        }
                    }
                }
                // daemon ausente: o BusClient da fundação já esperou o
                // backoff dele; aqui o respiro evita a fila de renascimentos
                std::thread::sleep(Duration::from_millis(300));
            }
        });
    }

    let st = Rc::new(RefCell::new(State {
        clock_label: gtk::Label::new(None),
        btn_audio: gtk::Button::new(),
        audio_img: gtk::Image::from_icon_name("audio-volume-high-symbolic"),
        btn_rede: gtk::Button::new(),
        rede_img: gtk::Image::from_icon_name(icone_rede(EstadoRede::Desligado)),
        btn_bt: gtk::Button::new(),
        bt_img: gtk::Image::from_icon_name("bluetooth-disabled-symbolic"),
        btn_game: gtk::Button::new(),
        btn_player: gtk::Button::new(),
        player_label: gtk::Label::new(None),
        btn_bat: None,
        rot_sink: gtk::Label::new(Some("Sem saída")),
        rot_fonte: gtk::Label::new(Some("Sem entrada")),
        esc_sink: gtk::Scale::with_range(gtk::Orientation::Horizontal, 0.0, 100.0, 5.0),
        esc_fonte: gtk::Scale::with_range(gtk::Orientation::Horizontal, 0.0, 100.0, 5.0),
        arrasta_sink: Rc::new(Cell::new(false)),
        arrasta_fonte: Rc::new(Cell::new(false)),
        pende_sink: Rc::new(RefCell::new(None)),
        pende_fonte: Rc::new(RefCell::new(None)),
        lista_sinks: gtk::Box::new(gtk::Orientation::Vertical, 2),
        lista_fontes: gtk::Box::new(gtk::Orientation::Vertical, 2),
        img_mute_sink: gtk::Image::from_icon_name("audio-volume-high-symbolic"),
        img_mute_fonte: gtk::Image::from_icon_name("microphone-sensitivity-high-symbolic"),
        bt_lista: gtk::Box::new(gtk::Orientation::Vertical, 2),
        bt_switch: gtk::Switch::new(),
        rede_lista: gtk::Box::new(gtk::Orientation::Vertical, 4),
        rede_switch: gtk::Switch::new(),
        drawer: None,
        drawer_ns: 0,
        minuto_desenhado: u32::MAX,
        rede: EstadoRede::Desligado,
        essid: None,
        bus_cli: Rc::new(RefCell::new(None)),
    }));
    // os ícones da barra nascem no tamanho do assento (16px — a unidade
    // visual da casa; o label Nerd nunca mais entra aqui)
    st.borrow().audio_img.set_pixel_size(16);
    st.borrow().rede_img.set_pixel_size(16);
    st.borrow().bt_img.set_pixel_size(16);

    // ── ESQUERDA (1.0-93 — minimalista, a ordem do dono): o botão de
    //    apps com ÍCONE GTK de verdade + a palavra "Aplicativos" (sem
    //    siglas técnicas); esquerdo abre a gaveta (nwg-drawer), direito
    //    abre o MENU RÁPIDO do sistema em popover nativo. As pílulas da
    //    mesa (`1 2 3 4`) e o título ativo SAÍRAM da barra: a troca de
    //    mesa é o scroll/atalhos W-1..4 do labwc, o título mora na
    //    moldura da própria janela — a barra fica LIMPA
    let btn_apps = botao_apps(&st, &window);
    esq.append(&btn_apps);

    // ── CENTRO (1.0-93): o relógio em HORÁRIO LOCAL (a ordem do dono,
    //    rig da 1.0-92: o epoch puro vestia UTC — o glib::DateTime
    //    now_local veste o fuso DO SISTEMA), o TEXTO nunca muda ao
    //    clicar (a cura A2 intacta), o CALENDÁRIO nasce em popover GTK4
    //    no hover (a pele roxa/escuro da casa), esquerdo abre/fecha as
    //    notificações e direito alterna o Não Perturbe
    let btn_clock = gtk::Button::new();
    btn_clock.set_widget_name("clockbtn");
    btn_clock.set_has_frame(false);
    {
        let lbl = st.borrow().clock_label.clone();
        btn_clock.set_child(Some(&lbl));
    }
    btn_clock.set_tooltip_text(Some(
        "Notificações — clique: painel · hover: calendário · direito: não perturbe",
    ));
    // 1.0-93 — O CALENDÁRIO (a ordem do dono: popover GTK4 com o tema
    // roxo/escuro ao passar o mouse; some quando o mouse sai — o clique
    // do MEIO também alterna, para quem não quer hover)
    let pop_cal = {
        let cal = gtk::Calendar::new();
        let pop = gtk::Popover::new();
        pop.set_autohide(false);
        pop.set_child(Some(&cal));
        pop.set_parent(&btn_clock);
        pop
    };
    // o hover: 350ms de cortesia, cancelado na saída
    {
        let mostrar = Rc::new(Cell::new(true));
        let motion = gtk::EventControllerMotion::new();
        {
            let pop = pop_cal.clone();
            let mostrar = mostrar.clone();
            motion.connect_enter(move |_, _, _| {
                mostrar.set(true);
                // (o clone por chamada: o enter é Fn — o timeout_once
                // move os SEUS clones, os capturados seguem reusáveis)
                let pop = pop.clone();
                let mostrar = mostrar.clone();
                glib::timeout_add_local_once(Duration::from_millis(350), move || {
                    if mostrar.get() {
                        pop.popup();
                    }
                });
            });
        }
        {
            let pop = pop_cal.clone();
            let mostrar = mostrar.clone();
            motion.connect_leave(move |_| {
                mostrar.set(false);
                pop.popdown();
            });
        }
        btn_clock.add_controller(motion);
    }
    // UM gesture só para TODOS os botões do relógio (a lição da dock:
    // dois GestureClick no mesmo widget disputam a sequência)
    {
        let pop_cal = pop_cal.clone();
        clique_solto(&btn_clock, move |botao| {
            // esquerdo: o painel (toggle SEM sequestrar o foco -sw);
            // direito: o DND (idem -sw); meio: o calendário. O TEXTO
            // NÃO MUDA — o clique é ação, a data é a data (a cura do
            // "alterna o texto exibido").
            if botao == 1 {
                solta(&["swaync-client", "-t", "-sw"]);
            } else if botao == 3 {
                solta(&["swaync-client", "-d", "-sw"]);
            } else if botao == 2 {
                if pop_cal.is_visible() {
                    pop_cal.popdown();
                } else {
                    pop_cal.popup();
                }
            }
        });
    }
    centro.append(&btn_clock);

    // ── DIREITA (E147 — o contrato mouse-first: game → player → áudio →
    //    rede → bluetooth → bateria → sessão; o bgapps SAIOU da barra) ──
    {
        let s = st.borrow();
        let btn_game = s.btn_game.clone();
        let btn_player = s.btn_player.clone();
        let player_label = s.player_label.clone();
        let btn_audio = s.btn_audio.clone();
        let audio_img = s.audio_img.clone();
        let btn_rede = s.btn_rede.clone();
        let rede_img = s.rede_img.clone();
        let btn_bt = s.btn_bt.clone();
        let bt_img = s.bt_img.clone();
        drop(s);

        // O MODO DE JOGO (E115/E126 intactos: o estado REAL do
        // GameMode no pill, clique DIREITO desliga na hora) — acende
        // no SIGRTMIN+8 que o elite-daemon manda na transição. O ícone
        // é Image de ÍCONE (input-gaming — o tema da casa tem).
        {
            let img = gtk::Image::from_icon_name("input-gaming-symbolic");
            img.set_pixel_size(16);
            btn_game.set_child(Some(&img));
        }
        btn_game.set_has_frame(false);
        btn_game.set_visible(false);
        btn_game.set_tooltip_text(Some(
            "Modo de jogo ativo — clique: o painel · direito: desligar",
        ));
        clique_solto(&btn_game, move |botao| {
            if botao == 3 {
                solta(&["craft-game", "off"]);
            } else if botao == 1 {
                solta(&["craft-game", "menu"]);
            }
        });
        dir.append(&btn_game);

        // O PLAYER MPRIS NATIVO (2.0: o estado chega PELO FIO — o
        // PropertiesChanged que o daemon escuta; zero playerctl, zero
        // polling de 1s). As AÇÕES também viajam no fio: esquerdo =
        // Play/Pause, meio = próxima, direito = FOCAR a janela do
        // player (o match benigno do daemon), scroll = faixa
        btn_player.set_widget_name("playerbtn");
        btn_player.set_has_frame(false);
        btn_player.set_child(Some(&player_label));
        btn_player.set_visible(false);
        btn_player.set_tooltip_text(Some(
            "Mídia — clique: play/pause · scroll: faixa · direito: focar o player",
        ));
        {
            let bus = st.borrow().bus_cli.clone();
            clique_solto(&btn_player, move |botao| {
                pede_bus(&bus, match botao {
                    1 => elite_core::MediaCmd::PlayPause,
                    2 => elite_core::MediaCmd::Next,
                    3 => elite_core::MediaCmd::Focus,
                    _ => return,
                });
            });
        }
        {
            let bus = st.borrow().bus_cli.clone();
            scroll(&btn_player, move |dy| {
                pede_bus(&bus, if dy < 0.0 {
                    elite_core::MediaCmd::Next
                } else {
                    elite_core::MediaCmd::Previous
                });
            });
        }
        dir.append(&btn_player);

        // E147 — A CENTRAL DE ÁUDIO & MICROFONE (a ordem do dono: "um
        // painel unificado de Áudio (Saída + Entrada)… mute/desmute
        // imediato, controle de volume, seleção rápida de dispositivo e
        // acesso direto ao mixer completo"). O botão abre o popover
        // unificado no ESQUERDO; o direito leva ao pwvucontrol (o mixer
        // de verdade); o scroll ajusta a saída sem abrir nada.
        btn_audio.set_has_frame(false);
        btn_audio.set_child(Some(&audio_img));
        btn_audio.set_tooltip_text(Some(
            "Áudio — clique: a central (saída + microfone) · scroll: volume · direito: mixer",
        ));
        {
            let pop = popover_audio(&st, tx.clone());
            pop.set_parent(&btn_audio);
            let tx = tx.clone();
            clique_solto(&btn_audio, move |botao| match botao {
                1 => {
                    pop.popup();
                    pede_audio_detalhe(&tx);
                }
                3 => abre_mixer(),
                _ => {}
            });
        }
        scroll(&btn_audio, move |dy| {
            let passo = if dy < 0.0 { "5%+" } else { "5%-" };
            solta(&["wpctl", "set-volume", "--limit", "1.5", "@DEFAULT_AUDIO_SINK@", passo]);
        });
        dir.append(&btn_audio);

        // A REDE PERSISTENTE (a cura A4: o botão NUNCA sai — Cabo/
        // Wi-Fi/Desligado com ÍCONE GTK SEMPRE; o esquerdo é o seletor
        // rápido em popover, o direito o editor de conexões).
        btn_rede.set_has_frame(false);
        btn_rede.set_child(Some(&rede_img));
        btn_rede.set_tooltip_text(Some("Rede — clique: seletor rápido · direito: conexões"));
        {
            let pop = popover_rede(&st, tx.clone());
            pop.set_parent(&btn_rede);
            let tx = tx.clone();
            clique_solto(&btn_rede, move |botao| match botao {
                1 => {
                    pop.popup();
                    pede_rede_popover(&tx);
                }
                3 => solta(&["nm-connection-editor"]),
                _ => {}
            });
        }
        dir.append(&btn_rede);

        // E147 — O BLUETOOTH QUE RESPONDE (a ordem do dono: "Bluetooth
        // não responde a nada… alinhando de vez os pacotes instalados
        // com o elite-clean e o rc.xml para que nenhum script apague o
        // gerenciador usado pela interface"). O esquerdo abre o PAINEL
        // (power + conectar/desconectar a um clique); o direito abre o
        // blueman-manager SE ele existir — e o elite-clean PARA de
        // removê-lo (a cura do conflito está no script da casa).
        btn_bt.set_has_frame(false);
        btn_bt.set_child(Some(&bt_img));
        btn_bt.set_tooltip_text(Some(
            "Bluetooth — clique: o painel de dispositivos · direito: gerenciar (blueman)",
        ));
        {
            let pop = popover_bt(&st, tx.clone());
            pop.set_parent(&btn_bt);
            let tx = tx.clone();
            clique_solto(&btn_bt, move |botao| match botao {
                1 => {
                    pop.popup();
                    pede_bt_detalhe(&tx);
                }
                3 => {
                    if std::path::Path::new("/usr/bin/blueman-manager").exists() {
                        solta(&["blueman-manager"]);
                    } else {
                        // sem blueman (rig antigo que a dose ainda não
                        // curou): o painel É o gerenciador disponível
                        pop.popup();
                        pede_bt_detalhe(&tx);
                    }
                }
                _ => {}
            });
        }
        dir.append(&btn_bt);
    }

    // A BATERIA (só quando EXISTE — desktop não paga o assento): o
    // frame 0 já nasce cheio, o belt de 30s renova pelo /sys (sem
    // fork nenhum — o /sys é barato). E147: ícone GTK + percentual
    // (o glifo Nerd f0e7 morre com a fonte que não o tinha).
    if le_bateria(std::path::Path::new("/sys/class/power_supply/BAT0")).is_some() {
        let btn_bat = gtk::Button::new();
        btn_bat.set_widget_name("batbtn");
        btn_bat.set_has_frame(false);
        btn_bat.set_tooltip_text(Some("Bateria — clique: o resumo falado"));
        {
            clique_solto(&btn_bat, move |botao| {
                if botao == 1 {
                    solta(&["craft-bat"]);
                }
            });
        }
        {
            let linha = gtk::Box::new(gtk::Orientation::Horizontal, 5);
            let img = gtk::Image::from_icon_name("battery-good-symbolic");
            img.set_pixel_size(16);
            let rot = gtk::Label::new(None);
            if let Some((cap, _car)) = le_bateria(std::path::Path::new("/sys/class/power_supply/BAT0")) {
                rot.set_text(&format!("{cap}%"));
                img.set_icon_name(Some(bat_icone(cap)));
            }
            linha.append(&img);
            linha.append(&rot);
            btn_bat.set_child(Some(&linha));
        }
        dir.append(&btn_bat);
        st.borrow_mut().btn_bat = Some(btn_bat);
    }

    // ── A SESSÃO em popover NATIVO (a cura A5: sem fuzzel, sem
    //    can-suspend — o MenuButton é o par canônico do PopoverMenu;
    //    o clique/dismiss é TODO do GTK, zero gesture nosso aqui).
    //    E147: o ícone é Image de ÍCONE (system-shutdown — nunca mais
    //    codepoint Nerd no label) ─────────────────────────────────────
    let btn_power = gtk::MenuButton::new();
    btn_power.set_widget_name("powerbtn");
    btn_power.set_icon_name("system-shutdown-symbolic");
    btn_power.set_tooltip_text(Some("Sessão — Bloquear / Suspender / Reiniciar / Desligar / Encerrar"));
    {
        // as AÇÕES da casa (o grupo mora na window; o menu nomeia)
        let acoes = gtk::gio::SimpleActionGroup::new();
        for (nome, cmd) in [
            ("lock", &["craft-lock"][..]),
            ("suspend", &["systemctl", "suspend"][..]),
            ("reboot", &["systemctl", "reboot"][..]),
            ("poweroff", &["systemctl", "poweroff"][..]),
            ("logout", &["labwc", "--exit"][..]),
        ] {
            let act = gtk::gio::SimpleAction::new(nome, None);
            let cmd: Vec<String> = cmd.iter().map(|s| s.to_string()).collect();
            act.connect_activate(move |_, _| {
                let argv: Vec<&str> = cmd.iter().map(|s| s.as_str()).collect();
                solta(&argv);
            });
            acoes.add_action(&act);
        }
        window.insert_action_group("bar", Some(&acoes));
        let menu = gtk::gio::Menu::new();
        let s1 = gtk::gio::Menu::new();
        s1.append(Some("Bloquear tela"), Some("bar.lock"));
        s1.append(Some("Suspender"), Some("bar.suspend"));
        let s2 = gtk::gio::Menu::new();
        s2.append(Some("Reiniciar"), Some("bar.reboot"));
        s2.append(Some("Desligar"), Some("bar.poweroff"));
        s2.append(Some("Encerrar sessão"), Some("bar.logout"));
        menu.append_section(None, &s1);
        menu.append_section(None, &s2);
        let pop = gtk::PopoverMenu::from_model(Some(&menu));
        btn_power.set_popover(Some(&pop));
    }
    dir.append(&btn_power);

    // os SINAIS da casa (SIGRTMIN+8 jogo · SIGUSR2 CSS; o +9 dos 2º
    // planos morreu com o módulo E147 — o handler do intervalo RT
    // inteiro segue armado pela arma_rt: venha o sinal de quem vier,
    // a barra NUNCA morre pela disposição padrão)
    unsafe {
        libc::signal(libc::SIGRTMIN() + 8, on_signal as libc::sighandler_t);
        libc::signal(libc::SIGUSR2, on_signal as libc::sighandler_t);
    }

    load_css();
    desenha_relogio(&st); // o frame 0 já nasce com a hora certa
    window.show();

    log(&format!(
        "craft-bar-rs {VERSION} no ar (E147 — a UI reconstruída): contrato mouse-first \
         (esquerdo = popover nativo · direito = ferramenta avançada) · ícones SÓ por nome \
         de ícone GTK (o glifo Nerd quebrado morreu) · central de áudio unificada \
         (saída+mic: mute, volume, dispositivos, mixer) · painel de bluetooth com power \
         e conectar/desconectar · bgapps REMOVIDO da barra e do código · relógio pt_BR \
         + calendário no hover · rede persistente · sessão popover nativo · MPRIS/jogo \
         PELO FIO DO BUS · clique EXCLUSIVAMENTE no released (tolerância 5px, E140)"
    ));

    // o DRENO do canal + os sinais (100ms — a latência dos estados)
    {
        let st = st.clone();
        let rx = Rc::new(RefCell::new(rx));
        let tx = Rc::new(RefCell::new(tx));
        glib::timeout_add_local(Duration::from_millis(DRAIN_MS), move || {
            let rx = rx.borrow();
            let tx = tx.borrow();
            drena(&st, &rx, &tx);
            glib::ControlFlow::Continue
        });
    }
    // o RELÓGIO: 1s de olho, o label só toca na virada do minuto
    {
        let st = st.clone();
        glib::timeout_add_seconds_local(1, move || {
            desenha_relogio(&st);
            glib::ControlFlow::Continue
        });
    }
    // o BELT de 30s da bateria (o /sys é barato — sem fork na casa)
    if st.borrow().btn_bat.is_some() {
        let st = st.clone();
        glib::timeout_add_seconds_local(POLL_CINTO_S as u32, move || {
            // a TUPLA explícita casa o par (o botão pode ter nascido e a
            // bateria ido — cada lado é julgado sozinho); o ícone e o
            // percentual vestem juntos (Image + Label do filho)
            let bat = le_bateria(std::path::Path::new("/sys/class/power_supply/BAT0"));
            if let (Some(btn), Some((cap, carregando))) = (st.borrow().btn_bat.clone(), bat) {
                let linha = btn.child();
                if let Some(boxx) = linha.and_downcast::<gtk::Box>() {
                    let filhos: Vec<gtk::Widget> =
                        std::iter::successors(boxx.first_child(), |w| w.next_sibling()).collect();
                    if let Some(img) = filhos.first().and_then(|w| w.clone().downcast::<gtk::Image>().ok()) {
                        img.set_icon_name(Some(if carregando {
                            "battery-full-charging-symbolic"
                        } else {
                            bat_icone(cap)
                        }));
                    }
                    if let Some(rot) = filhos.get(1).and_then(|w| w.clone().downcast::<gtk::Label>().ok()) {
                        rot.set_text(&format!("{cap}%"));
                    }
                }
            }
            glib::ControlFlow::Continue
        });
    }
}

// ── a THREAD DE FUNDO (os filhos curtos nas cadências belt) ───────────

/// Roda PARA SEMPRE: áudio 2s · rede 5s · bluetooth 10s · cinto 30s.
/// Bloquear AQUI é de graça (a UI segue viva — a thread é dona dos
/// subprocessos, nunca do GTK). E147: o áudio manda A FOTO COMPLETA
/// (wpctl status + a verdade do padrão) e o cinto só carrega o jogo
/// (o bgapps morreu com o próprio módulo).
fn poller(tx: Sender<Msg>) {
    // 2.0 — O PLAYER NÃO MORA MAIS AQUI: o MPRIS chega pelo fio do bus
    // (o daemon escuta o PropertiesChanged — o polling de 1s do
    // craft-player morreu com o playerctl); aqui ficam os belts que
    // NÃO têm evento ainda (áudio/rede/bluetooth + o cinto do jogo —
    // os EVENTOS seguem sendo donos do reflexo)
    let mut t_audio = Instant::now();
    let mut t_rede = Instant::now();
    let mut t_bt = Instant::now();
    let mut t_cinto = Instant::now();
    loop {
        if t_audio.elapsed() >= Duration::from_secs(POLL_AUDIO_S) {
            t_audio = Instant::now();
            let _ = tx.send(Msg::AudioDet(foto_audio()));
        }
        if t_rede.elapsed() >= Duration::from_secs(POLL_REDE_S) {
            t_rede = Instant::now();
            if let Some(t) = um_longo(
                "nmcli",
                &["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"],
            ) {
                let _ = tx.send(Msg::Rede(estado_rede_nmcli(&t), essid_nmcli(&t)));
            }
        }
        if t_bt.elapsed() >= Duration::from_secs(POLL_BT_S) {
            t_bt = Instant::now();
            let _ = tx.send(Msg::Bt(
                um_longo("bluetoothctl", &["show"]).map(|t| bt_ligado(&t)),
            ));
        }
        if t_cinto.elapsed() >= Duration::from_secs(POLL_CINTO_S) {
            t_cinto = Instant::now();
            if let Some(t) = um_longo("craft-game", &["pill"]) {
                let _ = tx.send(Msg::Game(json_text(&t)));
            }
        }
        std::thread::sleep(Duration::from_millis(200));
    }
}

/// Roda UM comando curto e devolve a stdout (None em qualquer erro —
/// a UI CONSERVA o estado anterior: um engasgo nunca apaga o que o
/// dono vê). Custo: um fork; o dono é a thread de fundo.
fn um_longo(prog: &str, args: &[&str]) -> Option<String> {
    let out = Command::new(prog)
        .args(args)
        .stdin(Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// A FOTO COMPLETA do áudio (E147): o `wpctl status` alimenta as
/// LISTAS e o `wpctl get-volume` dá A VERDADE do mudo/volume dos dois
/// padrões (o status pode não marcar o MUTED — a porta que sempre
/// falou verdade vence). None no todo = wpctl ausente/engasgado (a UI
/// CONSERVA o estado anterior).
fn foto_audio() -> Option<AudioDetalhe> {
    let saida = um_longo("wpctl", &["status"])?;
    let (mut sinks, mut fontes) = parse_wpctl_status(&saida);
    if let Some((v, m)) = um_longo("wpctl", &["get-volume", "@DEFAULT_AUDIO_SINK@"])
        .and_then(|t| parse_volume_wpctl(&t))
    {
        if let Some(d) = sinks.iter_mut().find(|d| d.padrao) {
            d.vol = v;
            d.mudo = m;
        }
    }
    if let Some((v, m)) = um_longo("wpctl", &["get-volume", "@DEFAULT_AUDIO_SOURCE@"])
        .and_then(|t| parse_volume_wpctl(&t))
    {
        if let Some(d) = fontes.iter_mut().find(|d| d.padrao) {
            d.vol = v;
            d.mudo = m;
        }
    }
    let sink = sinks.iter().find(|d| d.padrao).cloned();
    let fonte = fontes.iter().find(|d| d.padrao).cloned();
    Some(AudioDetalhe {
        sink,
        fonte,
        sinks,
        fontes,
    })
}

/// A UI pede a FOTO do áudio NA HORA (o clique de mute/slide/dispositivo
/// não espera o belt de 2s — a resposta é o gesto; o belt é a rede).
fn pede_audio_detalhe(tx: &Sender<Msg>) {
    let tx = tx.clone();
    std::thread::spawn(move || {
        let _ = tx.send(Msg::AudioDet(foto_audio()));
    });
}

/// A UI pede a FOTO do Bluetooth na hora (a lista de pareados + os
/// conectados + o Powered — a verdade de três chamadas curtas).
fn pede_bt_detalhe(tx: &Sender<Msg>) {
    let tx = tx.clone();
    std::thread::spawn(move || {
        let ligado = um_longo("bluetoothctl", &["show"]).map(|t| bt_ligado(&t));
        let _ = tx.send(Msg::Bt(ligado));
        let pares = um_longo("bluetoothctl", &["devices", "Paired"])
            .map(|t| parse_bt_devices(&t))
            .unwrap_or_default();
        let vivos = um_longo("bluetoothctl", &["devices", "Connected"])
            .map(|t| bt_conectados(&t))
            .unwrap_or_default();
        let _ = tx.send(Msg::BtLista(pares, vivos));
    });
}

// ── o DRENO (as mensagens viram widgets) ──────────────────────────────

fn drena(st: &Rc<RefCell<State>>, rx: &Receiver<Msg>, tx: &Sender<Msg>) {
    // os SINAIS do daemon (o atomic cru → o gesto aqui; o refresh
    // pedido nasce em thread própria — o dreno NUNCA espera)
    let sig = SIG.swap(0, Ordering::SeqCst);
    if sig != 0 {
        let sig8 = libc::SIGRTMIN() + 8;
        if sig == sig8 {
            let tx = tx.clone();
            std::thread::spawn(move || {
                if let Some(t) = um_longo("craft-game", &["pill"]) {
                    let _ = tx.send(Msg::Game(json_text(&t)));
                }
            });
        } else if sig == libc::SIGUSR2 {
            load_css();
            log("bar.css relido (SIGUSR2 — a pele da casa sem renascer)");
        }
        // E147: o SIGRTMIN+9 dos 2º planos NÃO TEM mais consumidor (o
        // módulo morreu com a ordem do dono) — o sinal é engolido
        // silenciosamente (a arma_rt já impediu a morte pela disposição).
    }
    // o FILHO do drawer: colhido se já saiu (zero zumbi na barra)
    {
        let mut s = st.borrow_mut();
        if let Some(filho) = s.drawer.as_mut() {
            if matches!(filho.try_wait(), Ok(Some(_))) {
                s.drawer = None;
            }
        }
    }
    loop {
        match rx.try_recv() {
            Ok(msg) => aplica(st, msg),
            Err(TryRecvError::Empty) | Err(TryRecvError::Disconnected) => break,
        }
    }
}

/// Uma mensagem vira widget (emprestimos CURTOS — o gesto mora no
/// clone, nunca no borrow aninhado; a lição da dock E-auditoria).
fn aplica(st: &Rc<RefCell<State>>, msg: Msg) {
    match msg {
        Msg::AudioDet(detalhe) => {
            let Some(d) = detalhe else {
                return; // wpctl engasgou — o estado anterior CONSERVADO
            };
            let mut s = st.borrow_mut();
            // o ÍCONE do botão da barra (muted/low/high pela verdade)
            if let Some(sink) = d.sink.as_ref() {
                s.audio_img.set_icon_name(Some(icone_volume(sink.vol, sink.mudo)));
                if sink.mudo {
                    s.btn_audio.add_css_class("muted");
                } else {
                    s.btn_audio.remove_css_class("muted");
                }
                s.btn_audio.set_tooltip_text(Some(&format!(
                    "Áudio {}%{} — clique: a central · scroll: volume · direito: mixer",
                    (sink.vol * 100.0).round() as i64,
                    if sink.mudo { " · MUDO" } else { "" }
                )));
            }
            // A CENTRAL: os dois sliders (SÓ sem mão do dono no gesto)
            if let Some(sink) = d.sink.as_ref() {
                s.rot_sink.set_text(&rotulo_dispositivo(&sink.nome));
                s.img_mute_sink.set_icon_name(Some(icone_volume(sink.vol, sink.mudo)));
                s.rot_sink.set_sensitive(true);
                if !s.arrasta_sink.get() {
                    let alvo = (sink.vol * 100.0).clamp(0.0, 100.0);
                    if (s.esc_sink.value() - alvo).abs() > 0.5 {
                        s.esc_sink.set_value(alvo);
                    }
                }
            } else {
                s.rot_sink.set_text("Sem saída");
                s.rot_sink.set_sensitive(false);
            }
            if let Some(fonte) = d.fonte.as_ref() {
                s.rot_fonte.set_text(&rotulo_dispositivo(&fonte.nome));
                s.img_mute_fonte
                    .set_icon_name(Some(icone_mic(fonte.mudo)));
                s.rot_fonte.set_sensitive(true);
                if !s.arrasta_fonte.get() {
                    let alvo = (fonte.vol * 100.0).clamp(0.0, 100.0);
                    if (s.esc_fonte.value() - alvo).abs() > 0.5 {
                        s.esc_fonte.set_value(alvo);
                    }
                }
            } else {
                s.rot_fonte.set_text("Sem entrada");
                s.rot_fonte.set_sensitive(false);
            }
            // as LISTAS de dispositivos (remontadas por foto — a UI
            // remove o filho morto antes de vestir o novo)
            remonta_dispositivos(&s.lista_sinks, &d.sinks);
            remonta_dispositivos(&s.lista_fontes, &d.fontes);
        }
        Msg::Rede(estado, essid) => {
            let mut s = st.borrow_mut();
            s.rede = estado;
            s.essid = essid.clone();
            s.rede_img.set_icon_name(Some(icone_rede(estado)));
            s.btn_rede
                .set_tooltip_text(Some(&tooltip_rede(estado, essid.as_deref())));
        }
        Msg::Bt(estado) => {
            let s = st.borrow_mut();
            match estado {
                Some(true) => {
                    s.bt_img.set_icon_name(Some("bluetooth-active-symbolic"));
                    s.btn_bt.remove_css_class("off");
                    s.bt_switch.set_active(true);
                    s.bt_switch.set_sensitive(true);
                    s.btn_bt.set_tooltip_text(Some(
                        "Bluetooth ligado — clique: o painel · direito: gerenciar (blueman)",
                    ));
                }
                Some(false) => {
                    s.bt_img.set_icon_name(Some("bluetooth-disabled-symbolic"));
                    s.btn_bt.add_css_class("off");
                    s.bt_switch.set_active(false);
                    s.bt_switch.set_sensitive(true);
                    s.btn_bt.set_tooltip_text(Some(
                        "Bluetooth desligado — clique: o painel · direito: gerenciar (blueman)",
                    ));
                }
                None => {
                    s.bt_img.set_icon_name(Some("bluetooth-disabled-symbolic"));
                    s.btn_bt.add_css_class("off");
                    s.bt_switch.set_sensitive(false);
                    s.btn_bt.set_tooltip_text(Some("Sem adaptador Bluetooth"));
                }
            }
        }
        Msg::BtLista(pares, vivos) => {
            // E147 — o painel veste a lista (a thread colheu; a UI
            // remonta AGORA; o conectado acende sugerido + o clique
            // alterna a conexão)
            let s = st.borrow();
            while let Some(filho) = s.bt_lista.first_child() {
                s.bt_lista.remove(&filho);
            }
            if pares.is_empty() {
                let aviso = gtk::Label::new(Some("Nenhum dispositivo pareado"));
                aviso.add_css_class("body");
                s.bt_lista.append(&aviso);
            }
            for dev in &pares {
                let btn = gtk::Button::new();
                btn.set_has_frame(false);
                btn.set_hexpand(true);
                let rotulo = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                let nome = gtk::Label::new(Some(&dev.nome));
                nome.set_halign(gtk::Align::Start);
                nome.set_hexpand(true);
                nome.set_ellipsize(gtk::pango::EllipsizeMode::End);
                rotulo.append(&nome);
                let vivo = vivos.contains(&dev.mac);
                let estado_lbl = gtk::Label::new(Some(if vivo { "conectado" } else { "" }));
                estado_lbl.add_css_class("dim");
                rotulo.append(&estado_lbl);
                btn.set_child(Some(&rotulo));
                if vivo {
                    btn.add_css_class("suggested-action");
                }
                let mac = dev.mac.clone();
                btn.set_tooltip_text(Some(if vivo {
                    "Conectado — clique: desconectar"
                } else {
                    "Pareado — clique: conectar"
                }));
                clique_solto(&btn, move |botao| {
                    if botao == 1 {
                        let verb = if vivo { "disconnect" } else { "connect" };
                        solta(&["bluetoothctl", verb, &mac]);
                    }
                });
                s.bt_lista.append(&btn);
            }
        }
        Msg::Media(m) => {
            // 2.0 — o MPRIS pelo fio: o estado tipado vira pill
            let s = st.borrow_mut();
            match m.as_ref().and_then(media_pill) {
                Some((txt, tip)) => {
                    s.player_label.set_text(&txt);
                    s.btn_player.set_tooltip_text(tip.as_deref());
                    s.btn_player.set_visible(true);
                }
                None => s.btn_player.set_visible(false),
            }
        }
        Msg::BusGame(ativa) => {
            let s = st.borrow_mut();
            s.btn_game.set_visible(ativa);
        }
        Msg::Bus(cli) => {
            // o fio (re)nasceu: o handle fica com a UI para os pedidos
            *st.borrow_mut().bus_cli.borrow_mut() = Some(cli);
        }
        Msg::Game(txt) => {
            let s = st.borrow_mut();
            s.btn_game.set_visible(txt.is_some());
        }
        Msg::RedeLista(redes) => {
            // 1.0-93 — o seletor rápido veste a lista (a thread de
            // fundo colheu; a UI remonta os botões AGORA)
            let s = st.borrow();
            while let Some(filho) = s.rede_lista.first_child() {
                s.rede_lista.remove(&filho);
            }
            if redes.is_empty() {
                let aviso = gtk::Label::new(Some("Nenhuma rede Wi-Fi ao alcance"));
                aviso.add_css_class("body");
                s.rede_lista.append(&aviso);
            }
            for r in &redes {
                let btn = gtk::Button::new();
                btn.set_has_frame(false);
                btn.set_hexpand(true);
                let rotulo = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                let nome = gtk::Label::new(Some(&format!(
                    "{}{}",
                    if r.segura { "🔒 " } else { "" },
                    r.ssid
                )));
                nome.set_halign(gtk::Align::Start);
                nome.set_hexpand(true);
                nome.set_ellipsize(gtk::pango::EllipsizeMode::End);
                let sinal = gtk::Label::new(Some(&format!("{}%", r.sinal)));
                sinal.add_css_class("dim");
                rotulo.append(&nome);
                rotulo.append(&sinal);
                btn.set_child(Some(&rotulo));
                let ssid = r.ssid.clone();
                let conectada = st.borrow().essid.as_deref() == Some(r.ssid.as_str());
                if conectada {
                    btn.add_css_class("suggested-action");
                    btn.set_tooltip_text(Some("Rede conectada — clique: conectar de novo"));
                } else {
                    btn.set_tooltip_text(Some(&format!(
                        "Conectar em {}{}",
                        r.ssid,
                        if r.segura { " (pede senha no diálogo do sistema)" } else { "" }
                    )));
                }
                clique_solto(&btn, move |botao| {
                    if botao == 1 {
                        conecta_wifi(&ssid);
                    }
                });
                s.rede_lista.append(&btn);
            }
        }
        Msg::RedeRadio(estado) => {
            // o Switch do popover veste o estado REAL do rádio (sem
            // estado = calado, sem mentira)
            let s = st.borrow();
            if let Some(on) = estado {
                s.rede_switch.set_active(on);
            }
        }
    }
}

/// E147 — a remontagem de UMA lista de dispositivos da central (o
/// rótulo é o humano da lei §5; o padrão acende sugerido; o clique
/// troca o default pelo id e pede a foto na hora).
fn remonta_dispositivos(lista: &gtk::Box, devs: &[DispositivoAudio]) {
    while let Some(filho) = lista.first_child() {
        lista.remove(&filho);
    }
    if devs.is_empty() {
        let aviso = gtk::Label::new(Some("Nenhum dispositivo"));
        aviso.add_css_class("dim");
        aviso.set_halign(gtk::Align::Start);
        lista.append(&aviso);
        return;
    }
    for d in devs {
        let btn = gtk::Button::new();
        btn.set_has_frame(false);
        btn.set_hexpand(true);
        let rotulo = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        let nome = gtk::Label::new(Some(&rotulo_dispositivo(&d.nome)));
        nome.set_halign(gtk::Align::Start);
        nome.set_hexpand(true);
        nome.set_ellipsize(gtk::pango::EllipsizeMode::End);
        let vol = gtk::Label::new(Some(&format!(
            "{}%",
            (d.vol * 100.0).round() as i64
        )));
        vol.add_css_class("dim");
        rotulo.append(&nome);
        rotulo.append(&vol);
        btn.set_child(Some(&rotulo));
        if d.padrao {
            btn.add_css_class("suggested-action");
        }
        let id = d.id;
        clique_solto(&btn, move |botao| {
            if botao == 1 {
                solta(&["wpctl", "set-default", &id.to_string()]);
            }
        });
        lista.append(&btn);
    }
}

/// E147 — O MIXER COMPLETO da central (a diretriz: pwvucontrol é a
/// ferramenta de verdade; pavucontrol é o irmão que o rig pode ter —
/// a barra nunca promete o que o sistema não tem).
fn abre_mixer() {
    if std::path::Path::new("/usr/bin/pwvucontrol").exists() {
        solta(&["pwvucontrol"]);
    } else if std::path::Path::new("/usr/bin/pavucontrol").exists() {
        solta(&["pavucontrol"]);
    } else {
        log("mixer: nem pwvucontrol nem pavucontrol no sistema — nada a abrir (honesto)");
    }
}

/// O ícone da bateria pelo nível (os nomes do tema — nunca glifo Nerd).
fn bat_icone(cap: u8) -> &'static str {
    match cap {
        0..=15 => "battery-empty-symbolic",
        16..=35 => "battery-low-symbolic",
        36..=70 => "battery-good-symbolic",
        _ => "battery-full-symbolic",
    }
}

// ── o RELÓGIO (a palavra pt_BR da casa, na virada do minuto) ───────────

/// 1.0-93 — O HORA LOCAL DE VERDADE (a ordem do dono, rig da 1.0-92:
/// o epoch puro vestia UTC — 3 horas erradas no Brasil): o
/// `glib::DateTime::now_local()` veste o FUSO DO SISTEMA e a casa
/// compõe a palavra pt_BR com as TABELAS de sempre ("Seg, 23 Nov ·
/// 19:30"). O label só toca na virada do minuto (nenhum gesto por
/// segundo); o calendário do hover nasce do MESMO relógio.
fn desenha_relogio(st: &Rc<RefCell<State>>) {
    let Ok(agora) = glib::DateTime::now_local() else {
        return; // sem fuso conhecido a barra fica CALADA (nunca mente hora)
    };
    let m = agora.minute() as u32;
    let mut s = st.borrow_mut();
    if s.minuto_desenhado != m {
        s.clock_label.set_text(&relogio_ptbr(
            (agora.day_of_week().rem_euclid(7)) as u32,
            agora.day_of_month() as u32,
            agora.month() as u32,
            agora.hour() as u32,
            m,
        ));
        s.clock_label.set_tooltip_text(Some(&format!(
            "{:02}/{:02}/{} — clique: notificações · hover: calendário · direito: não perturbe",
            agora.day_of_month(),
            agora.month(),
            agora.year()
        )));
        s.minuto_desenhado = m;
    }
}

// ── O DRAWER (a cura A1: o filho é NOSSO, o eco morre nos 150ms) ───────

/// Abre/fecha a gaveta: 2º release dentro de 150ms é ECO (ignorado);
/// a gaveta viva morre por SIGTERM (a NOSSA pelo pid do filho, a de
/// fora pela varredura /proc — o W-d da porta craft-drawer também é
/// gaveta de verdade, o toggle é UM). O stderr da gaveta: /dev/null
/// (os grilos da era shell não são evidência de nada).
fn toggle_drawer(st: &Rc<RefCell<State>>) {
    let agora = agora_ns();
    {
        let mut s = st.borrow_mut();
        if s.drawer_ns > 0 && dentro_janela_ms(s.drawer_ns, agora, DRAWER_MS) {
            return; // o eco do mesmo gesto — a janela fala
        }
        s.drawer_ns = agora;
    }
    if mata_gaveta(st) {
        log("drawer: fechado (toggle por release — o eco morreu no debounce de 150ms)");
        return;
    }
    match Command::new("nwg-drawer")
        .args([
            "-fm", "thunar", "-term", "foot", "-is", "64", "-c", "8", "-spacing", "16", "-nocats",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn()
    {
        Ok(filho) => {
            st.borrow_mut().drawer = Some(filho);
            log("drawer: aberto (release + debounce 150ms — sem freio/túmulo da era shell)");
        }
        Err(e) => {
            log(&format!("drawer: nwg-drawer não nasceu ({e}) — a verdade no papel"));
        }
    }
}

/// Mata a gaveta viva (a nossa pelo pid; a de fora pela varredura do
/// /proc pelo comm do dono — zero fork de pkill, a lição E135).
/// true = havia gaveta (o chamador decide se abre outra).
fn mata_gaveta(st: &Rc<RefCell<State>>) -> bool {
    let uid = current_uid();
    let mut havia = false;
    let mut s = st.borrow_mut();
    if let Some(filho) = s.drawer.as_mut() {
        if matches!(filho.try_wait(), Ok(None)) {
            let _ = unsafe { libc::kill(filho.id() as i32, libc::SIGTERM) };
            havia = true;
        } else {
            s.drawer = None;
        }
    }
    if let Ok(dir) = std::fs::read_dir("/proc") {
        for e in dir.flatten() {
            let Some(pid) = e.file_name().to_str().and_then(|p| p.parse::<i32>().ok()) else {
                continue;
            };
            let base = std::path::Path::new("/proc").join(e.file_name());
            let Ok(comm) = std::fs::read_to_string(base.join("comm")) else { continue };
            if comm.trim() != "nwg-drawer" {
                continue;
            }
            let Ok(meta) = std::fs::metadata(base.join("stat")) else { continue };
            if meta.uid() != uid {
                continue;
            }
            let _ = unsafe { libc::kill(pid, libc::SIGTERM) };
            havia = true;
        }
    }
    havia
}

fn agora_ns() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0)
}

// ── OS WIDGETS da casa ────────────────────────────────────────────────

/// Uma das três zonas (esquerda/centro/direita) com o alinhamento e
/// o hexpand que dá o centrar EXATO do meio (a gramática waybar).
fn caixa_lateral(halign: gtk::Align) -> gtk::Box {
    let b = gtk::Box::new(gtk::Orientation::Horizontal, 4);
    b.set_hexpand(true);
    b.set_halign(halign);
    b.set_valign(gtk::Align::Center);
    b
}

/// 1.0-93 — O BOTÃO DE APPS (a ordem do dono): ícone GTK de verdade
/// (`view-app-grid-symbolic`) + a palavra "Aplicativos" (sem siglas
/// técnicas); esquerdo abre a GAVETA (nwg-drawer, o toggle com debounce
/// de sempre), direito abre o MENU RÁPIDO do sistema em popover
/// nativo (as ações canônicas da casa — a mesma gramática da sessão).
fn botao_apps(st: &Rc<RefCell<State>>, window: &gtk::ApplicationWindow) -> gtk::Button {
    let btn = gtk::Button::new();
    btn.set_widget_name("appbtn");
    btn.set_has_frame(false);
    let linha = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    let img = gtk::Image::from_icon_name("view-app-grid-symbolic");
    img.set_pixel_size(16);
    let lbl = gtk::Label::new(Some("Aplicativos"));
    linha.append(&img);
    linha.append(&lbl);
    btn.set_child(Some(&linha));
    btn.set_tooltip_text(Some("Aplicativos — clique: gaveta · direito: menu rápido"));
    // o MENU RÁPIDO (o clique direito): as ações de 1 toque da casa —
    // o mesmo padrão do popover da sessão (SimpleActionGroup +
    // PopoverMenu, TODO do GTK — zero gesture nosso aqui)
    let acoes = gtk::gio::SimpleActionGroup::new();
    for (nome, cmd) in [
        ("terminal", &["foot"][..]),
        ("arquivos", &["thunar"][..]),
        ("navegador", &["brave"][..]),
        ("captura", &["craft-shot"][..]),
        ("bloquear", &["craft-lock"][..]),
        ("sair", &["labwc", "--exit"][..]),
    ] {
        let act = gtk::gio::SimpleAction::new(nome, None);
        let cmd: Vec<String> = cmd.iter().map(|s| s.to_string()).collect();
        act.connect_activate(move |_, _| {
            let argv: Vec<&str> = cmd.iter().map(|s| s.as_str()).collect();
            solta(&argv);
        });
        acoes.add_action(&act);
    }
    window.insert_action_group("aplicativos", Some(&acoes));
    let menu = gtk::gio::Menu::new();
    let s1 = gtk::gio::Menu::new();
    s1.append(Some("Terminal"), Some("aplicativos.terminal"));
    s1.append(Some("Arquivos"), Some("aplicativos.arquivos"));
    s1.append(Some("Navegador"), Some("aplicativos.navegador"));
    s1.append(Some("Captura de tela"), Some("aplicativos.captura"));
    let s2 = gtk::gio::Menu::new();
    s2.append(Some("Bloquear tela"), Some("aplicativos.bloquear"));
    s2.append(Some("Encerrar sessão"), Some("aplicativos.sair"));
    menu.append_section(None, &s1);
    menu.append_section(None, &s2);
    let pop = gtk::PopoverMenu::from_model(Some(&menu));
    pop.set_parent(&btn);
    // (UM gesture só: o clique esquerdo abre a gaveta, o direito o
    // menu rápido — dois GestureClick no MESMO botão disputariam a
    // sequência e o segundo nunca dispararia; a lição da dock B1)
    {
        let st = st.clone();
        let pop = pop.clone();
        clique_solto(&btn, move |botao| {
            if botao == 1 {
                toggle_drawer(&st);
            } else if botao == 3 {
                pop.popup();
            }
        });
    }
    btn
}

/// 1.0-93 — O SELETOR RÁPIDO DE REDE (a ordem do dono): popover GTK4
/// com o Switch do Wi-Fi (nmcli radio), o STATUS do cabo, a LISTA de
/// redes para conectar DIRETO e o botão AVANÇADO (nm-connection-
/// editor). A lista é alimentada pela thread de fundo (Msg::RedeLista)
/// e o clique pede o refresh na hora (pede_rede_popover).
fn popover_rede(st: &Rc<RefCell<State>>, tx: Sender<Msg>) -> gtk::Popover {
    let pop = gtk::Popover::new();
    pop.set_autohide(true);
    let corpo = gtk::Box::new(gtk::Orientation::Vertical, 8);
    corpo.set_margin_top(10);
    corpo.set_margin_bottom(10);
    corpo.set_margin_start(10);
    corpo.set_margin_end(10);
    corpo.set_size_request(320, -1);

    // a cabeça: o Switch do Wi-Fi + o rótulo
    let cabeca = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let titulo = gtk::Label::new(Some("Rede"));
    titulo.add_css_class("title");
    titulo.set_hexpand(true);
    titulo.set_halign(gtk::Align::Start);
    {
        let s = st.borrow();
        let sw = s.rede_switch.clone();
        sw.set_valign(gtk::Align::Center);
        sw.set_tooltip_text(Some("Ligar ou desligar o Wi-Fi"));
        {
            let tx = tx.clone();
            sw.connect_state_set(move |_, on| {
                let cmd = if on { "on" } else { "off" };
                let tx = tx.clone();
                std::thread::spawn(move || {
                    let _ = Command::new("nmcli")
                        .args(["radio", "wifi", cmd])
                        .stdin(Stdio::null())
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .status();
                    // o rádio trocou: a lista NOVA chega pelo canal
                    pede_rede_popover(&tx);
                });
                glib::Propagation::Proceed
            });
        }
        cabeca.append(&titulo);
        cabeca.append(&sw);
    }
    corpo.append(&cabeca);

    // o status do cabo (o texto vive da última leitura do belt)
    {
        let s = st.borrow();
        let status = gtk::Label::new(None);
        let txt = match s.rede {
            EstadoRede::Cabo => "Rede cabeada conectada".to_string(),
            EstadoRede::Wifi => format!(
                "Wi-Fi conectado{}",
                s.essid.as_deref().map(|e| format!(" · {e}")).unwrap_or_default()
            ),
            EstadoRede::Desligado => "Sem conexão".to_string(),
        };
        status.set_text(&txt);
        status.add_css_class("body");
        status.set_halign(gtk::Align::Start);
        drop(s);
        corpo.append(&status);
    }

    // a LISTA de redes (rolável — o max-h da casa para listas longas)
    let scroll = gtk::ScrolledWindow::new();
    scroll.set_max_content_height(280);
    scroll.set_propagate_natural_height(true);
    {
        let s = st.borrow();
        let lista = s.rede_lista.clone();
        drop(s);
        scroll.set_child(Some(&lista));
    }
    corpo.append(&scroll);

    // o AVANÇADO (o nm-connection-editor — a ferramenta completa) e o
    // IWGTK (1.0-94 — a diretriz do dono: o rádio Wi-Fi de verdade em
    // tela própria; instalado = botão, ausente = nem nasce, a barra
    // nunca promete o que o sistema não tem)
    {
        let ferramentas = gtk::Box::new(gtk4::Orientation::Horizontal, 8);
        ferramentas.set_hexpand(true);
        let avancado = gtk4::Button::with_label("Conexões avançadas");
        avancado.set_hexpand(true);
        avancado.set_tooltip_text(Some("Abrir o editor completo de conexões"));
        clique_solto(&avancado, move |botao| {
            if botao == 1 {
                solta(&["nm-connection-editor"]);
            }
        });
        ferramentas.append(&avancado);
        if std::path::Path::new("/usr/bin/iwgtk").exists() {
            let iwgtk = gtk4::Button::with_label("Wi-Fi (iwgtk)");
            iwgtk.set_hexpand(true);
            iwgtk.set_tooltip_text(Some("Abrir o rádio Wi-Fi em tela própria"));
            clique_solto(&iwgtk, move |botao| {
                if botao == 1 {
                    solta(&["iwgtk"]);
                }
            });
            ferramentas.append(&iwgtk);
        }
        corpo.append(&ferramentas);
    }
    pop.set_child(Some(&corpo));
    pop
}

/// E147 — A CENTRAL DE ÁUDIO & MICROFONE (a ordem do dono: "um painel
/// unificado de Áudio (Saída + Entrada)… mute/desmute imediato,
/// controle de volume, seleção rápida de dispositivo e acesso direto
/// ao mixer completo"). Um popover, duas seções espelhadas:
///   · SAÍDA — mute a um clique (o ícone é a verdade), slider 0-100
///     com commit debounce de 150ms (um wpctl por pausa do gesto) e a
///     lista dos sinks para trocar o padrão a um clique;
///   · ENTRADA — o mesmo para o microfone (o Fifine do dump do dono
///     troca de assento aqui, não no pavucontrol);
///   · MIXER — o pwvucontrol de verdade (pavucontrol é o irmão que o
///     rig pode ter; a barra nunca promete o que o sistema não tem).
/// A FOTO (Msg::AudioDet) veste TUDO: rótulos, ícones, sliders (só
/// sem a mão do dono no gesto) e listas.
fn popover_audio(st: &Rc<RefCell<State>>, tx: Sender<Msg>) -> gtk::Popover {
    let pop = gtk::Popover::new();
    pop.set_autohide(true);
    let corpo = gtk::Box::new(gtk::Orientation::Vertical, 8);
    corpo.set_margin_top(12);
    corpo.set_margin_bottom(12);
    corpo.set_margin_start(12);
    corpo.set_margin_end(12);
    corpo.set_size_request(340, -1);

    // o cabeçalho: o título da central
    let titulo = gtk::Label::new(Some("Áudio"));
    titulo.add_css_class("title");
    titulo.set_halign(gtk::Align::Start);
    corpo.append(&titulo);

    // ── SAÍDA ─────────────────────────────────────────────────────────
    let sec_sink = gtk::Label::new(Some("Saída"));
    sec_sink.add_css_class("dim");
    sec_sink.set_halign(gtk::Align::Start);
    corpo.append(&sec_sink);

    let linha_sink = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    {
        let s = st.borrow();
        let btn_mute = gtk::Button::new();
        btn_mute.set_has_frame(false);
        let img = s.img_mute_sink.clone();
        btn_mute.set_child(Some(&img));
        btn_mute.set_tooltip_text(Some("Mudo/desmudo da saída"));
        let tx = tx.clone();
        clique_solto(&btn_mute, move |botao| {
            if botao == 1 {
                solta(&["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                pede_audio_detalhe(&tx);
            }
        });
        linha_sink.append(&btn_mute);
        let esc = s.esc_sink.clone();
        esc.set_hexpand(true);
        esc.set_valign(gtk::Align::Center);
        esc.set_tooltip_text(Some("Volume da saída — 0 a 100"));
        // o commit do slider: debounce de 150ms — UM wpctl por pausa
        // do gesto (o arrastar contínuo não enfileira forks; o release
        // confirma o valor final NA HORA)
        {
            let pende = s.pende_sink.clone();
            let esc = esc.clone();
            esc.connect_value_changed(move |_e| {
                if let Some(id) = pende.borrow_mut().take() {
                    id.remove();
                }
                let esc = esc.clone();
                let novo = glib::timeout_add_local_once(Duration::from_millis(150), move || {
                    let v = esc.value() / 100.0;
                    solta(&[
                        "wpctl",
                        "set-volume",
                        "--limit",
                        "1.5",
                        "@DEFAULT_AUDIO_SINK@",
                        &format!("{v:.2}"),
                    ]);
                });
                *pende.borrow_mut() = Some(novo);
            });
        }
        // a bandeira de ARRASTO (o belt nunca briga com a mão do dono)
        {
            let arr = s.arrasta_sink.clone();
            let ges = gtk::GestureClick::new();
            ges.connect_pressed(move |_, _, _, _| arr.set(true));
            let arr = s.arrasta_sink.clone();
            let esc = esc.clone();
            let pende = s.pende_sink.clone();
            ges.connect_released(move |_, _, _, _| {
                arr.set(false);
                // o release confirma o valor final NA HORA (o debounce
                // pendente morre — o wpctl novo já leva o valor certo)
                if let Some(id) = pende.borrow_mut().take() {
                    id.remove();
                }
                let v = esc.value() / 100.0;
                solta(&[
                    "wpctl",
                    "set-volume",
                    "--limit",
                    "1.5",
                    "@DEFAULT_AUDIO_SINK@",
                    &format!("{v:.2}"),
                ]);
            });
            esc.add_controller(ges);
        }
        linha_sink.append(&esc);
        drop(s);
    }
    corpo.append(&linha_sink);
    {
        let s = st.borrow();
        let rot = s.rot_sink.clone();
        rot.add_css_class("dim");
        rot.set_halign(gtk::Align::Start);
        rot.set_ellipsize(gtk::pango::EllipsizeMode::End);
        let sc = gtk::ScrolledWindow::new();
        sc.set_max_content_height(110);
        sc.set_propagate_natural_height(true);
        let lista = s.lista_sinks.clone();
        sc.set_child(Some(&lista));
        drop(s);
        corpo.append(&rot);
        corpo.append(&sc);
    }

    // ── ENTRADA (o microfone — a mesma gramática espelhada) ───────────
    let sep1 = gtk::Separator::new(gtk::Orientation::Horizontal);
    corpo.append(&sep1);
    let sec_fonte = gtk::Label::new(Some("Entrada (microfone)"));
    sec_fonte.add_css_class("dim");
    sec_fonte.set_halign(gtk::Align::Start);
    corpo.append(&sec_fonte);

    let linha_fonte = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    {
        let s = st.borrow();
        let btn_mute = gtk::Button::new();
        btn_mute.set_has_frame(false);
        let img = s.img_mute_fonte.clone();
        btn_mute.set_child(Some(&img));
        btn_mute.set_tooltip_text(Some("Mudo/desmudo do microfone"));
        let tx = tx.clone();
        clique_solto(&btn_mute, move |botao| {
            if botao == 1 {
                solta(&["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
                pede_audio_detalhe(&tx);
            }
        });
        linha_fonte.append(&btn_mute);
        let esc = s.esc_fonte.clone();
        esc.set_hexpand(true);
        esc.set_valign(gtk::Align::Center);
        esc.set_tooltip_text(Some("Volume do microfone — 0 a 100"));
        {
            let pende = s.pende_fonte.clone();
            let esc = esc.clone();
            esc.connect_value_changed(move |_e| {
                if let Some(id) = pende.borrow_mut().take() {
                    id.remove();
                }
                let esc = esc.clone();
                let novo = glib::timeout_add_local_once(Duration::from_millis(150), move || {
                    let v = esc.value() / 100.0;
                    solta(&[
                        "wpctl",
                        "set-volume",
                        "--limit",
                        "1.5",
                        "@DEFAULT_AUDIO_SOURCE@",
                        &format!("{v:.2}"),
                    ]);
                });
                *pende.borrow_mut() = Some(novo);
            });
        }
        {
            let arr = s.arrasta_fonte.clone();
            let ges = gtk::GestureClick::new();
            ges.connect_pressed(move |_, _, _, _| arr.set(true));
            let arr = s.arrasta_fonte.clone();
            let esc = esc.clone();
            let pende = s.pende_fonte.clone();
            ges.connect_released(move |_, _, _, _| {
                arr.set(false);
                if let Some(id) = pende.borrow_mut().take() {
                    id.remove();
                }
                let v = esc.value() / 100.0;
                solta(&[
                    "wpctl",
                    "set-volume",
                    "--limit",
                    "1.5",
                    "@DEFAULT_AUDIO_SOURCE@",
                    &format!("{v:.2}"),
                ]);
            });
            esc.add_controller(ges);
        }
        linha_fonte.append(&esc);
        drop(s);
    }
    corpo.append(&linha_fonte);
    {
        let s = st.borrow();
        let rot = s.rot_fonte.clone();
        rot.add_css_class("dim");
        rot.set_halign(gtk::Align::Start);
        rot.set_ellipsize(gtk::pango::EllipsizeMode::End);
        let sc = gtk::ScrolledWindow::new();
        sc.set_max_content_height(110);
        sc.set_propagate_natural_height(true);
        let lista = s.lista_fontes.clone();
        sc.set_child(Some(&lista));
        drop(s);
        corpo.append(&rot);
        corpo.append(&sc);
    }

    // ── MIXER (a porta da ferramenta completa) ────────────────────────
    let sep2 = gtk::Separator::new(gtk::Orientation::Horizontal);
    corpo.append(&sep2);
    let mixer = gtk::Button::with_label(if std::path::Path::new("/usr/bin/pwvucontrol").exists() {
        "Mixer completo (pwvucontrol)"
    } else {
        "Mixer completo"
    });
    mixer.set_hexpand(true);
    mixer.set_tooltip_text(Some("Abrir o mixer completo do sistema"));
    clique_solto(&mixer, move |botao| {
        if botao == 1 {
            abre_mixer();
        }
    });
    corpo.append(&mixer);

    pop.set_child(Some(&corpo));
    pop
}

/// E147 — O PAINEL DE BLUETOOTH (a ordem do dono: "Bluetooth não
/// responde a nada" — a cura é DUPLA: o popover nativo com power e
/// conectar/desconectar a um clique PELO bluetoothctl, e o elite-clean
/// PARANDO de remover o blueman-manager que o direito abre). A FOTO
/// (Msg::BtLista) veste a lista; o Switch veste o Powered verdadeiro.
fn popover_bt(st: &Rc<RefCell<State>>, tx: Sender<Msg>) -> gtk::Popover {
    let pop = gtk::Popover::new();
    pop.set_autohide(true);
    let corpo = gtk::Box::new(gtk::Orientation::Vertical, 8);
    corpo.set_margin_top(12);
    corpo.set_margin_bottom(12);
    corpo.set_margin_start(12);
    corpo.set_margin_end(12);
    corpo.set_size_request(320, -1);

    // a cabeça: o título + o Switch do POWER (a verdade do show)
    let cabeca = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let titulo = gtk::Label::new(Some("Bluetooth"));
    titulo.add_css_class("title");
    titulo.set_hexpand(true);
    titulo.set_halign(gtk::Align::Start);
    {
        let s = st.borrow();
        let sw = s.bt_switch.clone();
        sw.set_valign(gtk::Align::Center);
        sw.set_tooltip_text(Some("Ligar ou desligar o Bluetooth"));
        let tx = tx.clone();
        sw.connect_state_set(move |_, on| {
            let cmd = if on { "on" } else { "off" };
            let tx = tx.clone();
            std::thread::spawn(move || {
                solta(&["bluetoothctl", "power", cmd]);
                pede_bt_detalhe(&tx);
            });
            glib::Propagation::Proceed
        });
        cabeca.append(&titulo);
        cabeca.append(&sw);
    }
    corpo.append(&cabeca);

    // a LISTA de pareados (rolável; o conectado acende e o clique
    // alterna a conexão pelo bluetoothctl — a ação DE VERDADE)
    let sc = gtk::ScrolledWindow::new();
    sc.set_max_content_height(200);
    sc.set_propagate_natural_height(true);
    {
        let s = st.borrow();
        let lista = s.bt_lista.clone();
        drop(s);
        sc.set_child(Some(&lista));
    }
    corpo.append(&sc);

    // o AVANÇADO: o gerenciador de verdade QUANDO existe (o elite-clean
    // da cura não o remove mais — o rig da dose o tem de volta)
    if std::path::Path::new("/usr/bin/blueman-manager").exists() {
        let ger = gtk::Button::with_label("Gerenciar dispositivos (blueman)");
        ger.set_hexpand(true);
        ger.set_tooltip_text(Some("Abrir o gerenciador completo do Bluetooth"));
        clique_solto(&ger, move |botao| {
            if botao == 1 {
                solta(&["blueman-manager"]);
            }
        });
        corpo.append(&ger);
    }
    pop.set_child(Some(&corpo));
    pop
}

/// Pede a lista de redes + o rádio AGORA (a thread de fundo colhe o
/// nmcli e devolve por Msg — a UI NUNCA bloqueia, a lei de sempre).
fn pede_rede_popover(tx: &Sender<Msg>) {
    let tx = tx.clone();
    std::thread::spawn(move || {
        let lista = um_longo(
            "nmcli",
            &["-t", "-f", "SSID,SIGNAL,SECURITY", "device", "wifi", "list"],
        )
        .map(|t| parse_wifi_list(&t))
        .unwrap_or_default();
        let _ = tx.send(Msg::RedeLista(lista));
        let radio = um_longo("nmcli", &["radio", "wifi"])
            .and_then(|t| parse_wifi_radio(&t));
        let _ = tx.send(Msg::RedeRadio(radio));
    });
}

/// Conecta em UMA rede (a ordem do dono: conectar direto). O pedido
/// corre em fundo; a rede com senha que o nmcli não sabe abre o
/// EDITOR para o dono digitar (a senha nunca é pedida na cara).
fn conecta_wifi(ssid: &str) {
    let ssid = ssid.to_string();
    std::thread::spawn(move || {
        let ok = Command::new("nmcli")
            .args(["device", "wifi", "connect", &ssid])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if !ok {
            // sem senha salva: o editor assume (o diálogo dele é a via
            // certa — a barra não inventa teclado de senha)
            solta(&["nm-connection-editor"]);
            log(&format!(
                "rede: conectar em {ssid} direto não deu — o editor assumiu"
            ));
        }
    });
}

/// A LEI DO CLIQUE (a cura B1): o verbo dispara EXCLUSIVAMENTE no
/// GestureClick::released com tolerância de arrasto < 5px — nunca no
/// press, nunca no clicked (o par press×clicked era o duplo verbo).
fn clique_solto<W: IsA<gtk::Widget>>(btn: &W, acao: impl Fn(u32) + 'static) {
    let gesture = gtk::GestureClick::new();
    gesture.set_button(0);
    let press = Rc::new(Cell::new((0.0f64, 0.0f64)));
    {
        let press = press.clone();
        gesture.connect_pressed(move |_g, _n, x, y| {
            press.set((x, y));
        });
    }
    {
        let press = press.clone();
        gesture.connect_released(move |g, _n, x, y| {
            let (px, py) = press.get();
            let dist = ((x - px) * (x - px) + (y - py) * (y - py)).sqrt();
            if dist >= ARRASTO_PX {
                return; // ARRASTO, não clique (a tolerância do dossiê)
            }
            let botao = g.current_button();
            if botao != 0 {
                acao(botao as u32);
            }
        });
    }
    btn.add_controller(gesture);
}

/// O SCROLL da casa (áudio: volume · player: faixa): vertical, com
/// o gesto calado (Propagation::Stop — o evento é da barra).
fn scroll<W: IsA<gtk::Widget>>(btn: &W, acao: impl Fn(f64) + 'static) {
    let sc = gtk::EventControllerScroll::new(gtk::EventControllerScrollFlags::VERTICAL);
    sc.connect_scroll(move |_s, _dx, dy| {
        acao(dy);
        glib::Propagation::Stop
    });
    btn.add_controller(sc);
}

/// O filho FORK-AND-FORGET da casa: stdout/stderr no vazio, grupo
/// próprio (o processo sobrevive à barra por desenho — ferramentas
/// de verdade não são filhos que a barra colhe).
/// 2.0 — o pedido MPRIS pelo fio (o verbo viaja ao daemon que fala
/// D-Bus com o player ativo — zero playerctl na interface da casa).
fn pede_bus(
    bus: &Rc<RefCell<Option<std::sync::Arc<elite_core::bus::BusClient>>>>,
    verbo: elite_core::MediaCmd,
) {
    if let Some(cli) = bus.borrow().as_ref() {
        let _ = cli.send_req(elite_core::BusReq::Media(verbo));
    }
}

/// O filho FORK-AND-FORGET da casa: stdout/stderr no vazio, grupo
/// próprio (o processo sobrevive à barra por desenho — ferramentas
/// de verdade não são filhos que a barra colhe).
/// E146/C — A COVEIRA: o Child abandonado no Drop virava <defunct>
/// (o rig 1.0-94 fotografou 6 zumbis pendurados no pid da barra:
/// swaync-client ×4, brave e craft-shot — o Linux deixa o morto na
/// tabela até ALGUÉM colher). A thread dedicada é a coveira: spawn →
/// wait — o exit status é colhido ANTES do Child morrer no escopo.
/// O grupo próprio SEGUE (a ferramenta não morre com a coveira nem
/// com a barra; o wait só COLHE, não espera viver).
fn solta(argv: &[&str]) {
    if argv.is_empty() {
        return;
    }
    // argv emprestado não atravessa o move: a cópia própria da thread
    let argv: Vec<String> = argv.iter().map(|s| (*s).to_string()).collect();
    std::thread::Builder::new()
        .name("solta-coveira".into())
        .spawn(move || {
            match Command::new(&argv[0])
                .args(&argv[1..])
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .process_group(0)
                .spawn()
            {
                Ok(mut filho) => {
                    // A COLHEITA: sem este wait o kernel guarda o morto
                    // como Z até a barra morrer (a tabela do ps inchava
                    // a cada clique de notificação/print/app).
                    let _ = filho.wait();
                }
                Err(e) => {
                    crate::log(&format!("solta: {} não nasceu ({e})", argv[0]));
                }
            }
        });
}

/// A pele da casa: ~/.config/elite/bar.css quando existe (o dono é o
/// dono), senão o DEFAULT embutido (a MESMA gramática do dock.css —
/// o load_from_data é a via sempre-presente do gtk4-rs 0.11, a lição
/// da E-auditoria do Canal: o load_from_string mora atrás da v4_12).
fn load_css() {
    let css = std::fs::read_to_string(css_path()).unwrap_or_else(|_| DEFAULT_CSS.to_string());
    let provider = gtk::CssProvider::new();
    provider.load_from_data(&css);
    if let Some(display) = gdk::Display::default() {
        gtk::style_context_add_provider_for_display(
            &display,
            &provider,
            gtk::STYLE_PROVIDER_PRIORITY_USER,
        );
    }
}

/// O fallback embutido AGORA É A FOLHA MESTRA ÚNICA (2.0 — Design System
/// ELITE): a pele da casa mora no elite-core (assets/theme.css) e a barra
/// o embute — uma identidade só para barra, dock e popovers, zero drift;
/// o override do dono segue arquivo LIVRE relido no SIGUSR2.
const DEFAULT_CSS: &str = elite_core::THEME_CSS;

