// ELITE · craft-bar-rs — ui.rs (E149 — O MAPA DIRETO, a simplificação
// radical da diretriz: a barra abre FERRAMENTAS DE VERDADE, não inventa
// controles que as ferramentas dedicadas já fazem melhor).
// Este módulo SÓ compila com a feature "gui" (exige o GTK dev do
// ambiente de build do pacote — o CI valida; o sandbox sem GTK
// compila/testa o NÚCLEO: state/main).
//
// O MAPA DE CLIQUES E149 (a lei nova da casa, válida para TODOS os
// botões da barra):
//   · CLIQUE ESQUERDO = a FERRAMENTA DEDICADA abre DIRETO — áudio →
//     pwvucontrol (pavucontrol honesto quando só ele existe), rede →
//     iwgtk (sem ele, o nm-connection-editor assume — nunca botão
//     morto), bluetooth → blueman-manager, notificações → o painel
//     swaync, apps → a gaveta (craft-apps), bateria → craft-bat;
//   · CLIQUE DIREITO = a AÇÃO RÁPIDA sem janela nenhuma — mute/desmute
//     da SAÍDA, rádio Wi-Fi liga/desliga, power do Bluetooth, Não
//     Perturbe;
//   · CLIQUE DO MEIO = o segundo lado (mudo do MICROFONE) / o
//     calendário;
//   · SCROLL = o gesto de ajuste fino (volume, faixa do player);
//   · HOVER = o feedback visual da pele (theme.css) + o tooltip que
//     diz o que cada clique faz.
//
// O QUE MORREU NESTA SIMPLIFICAÇÃO (o enterro com prova):
//   · OS POPOVERS CUSTOMIZADOS de áudio/rede/bluetooth (sliders,
//     listas e switches próprios — a fragilidade que o dump fotografou;
//     pwvucontrol, iwgtk e blueman-manager mandam);
//   · O MENU RÁPIDO do botão Aplicativos ("Bloquear tela" e "Encerrar
//     sessão" tinham DOIS endereços — menu do desktop e menu de
//     sessão; o dedupe da diretriz: a SESSÃO é o endereço único);
//   · O MÓDULO DE 2º PLANOS (a pílula dos aplicativos de fundo): a
//     ordem do dono ("deve ser completamente removido") — o botão, a
//     Msg, o belt e o SIGRTMIN+9 saem daqui E do elite-daemon E do
//     pacote (o fóssil morre no post_upgrade com voz);
//   · O GLIFO NERD FONT NO LABEL (o '\uf085 2' da tela do dono era o
//     codepoint que a fonte GTK padrão não tem — Inter/Adwaita Sans não
//     fala Nerd): TODOS os ícones da barra são Image::from_icon_name
//     (audio-volume-*, network-*, bluetooth-*, input-gaming, battery-*
//     — o Papirus/GNOME da casa tem todos, o render NUNCA mais quebra);
//   · O BLUETOOTH MUDO (o clique chamava o blueman-manager que o
//     elite-clean REMOVIA do sistema — o conflito estrutural que o
//     dono nomeou): o gerenciador DEVOLVEU ao sistema e o esquerdo o
//     abre; o direito alterna o power do adaptador.
//
// O QUE FICA (prova de campo da 1.0-93/94/95 — não se quebra o que
// funciona):
//   · a FAIXA layer-shell + a LEI DO CLIQUE no released (5px de
//     tolerância de arrasto, E140);
//   · a GAVETA com UM dono (o craft-apps da casa — o mesmo toggle do
//     W-d; a receita duplicada que se matava morreu) e o debounce de
//     150ms;
//   · o RELÓGIO pt_BR que nunca muda de texto + o calendário no hover;
//   · o MPRIS/jogo PELO FIO DO BUS + os sinais SIGRTMIN+8 (jogo) e
//     SIGUSR2 (a pele);
//   · a SESSÃO em PopoverMenu NATIVO (o MenuButton canônico do GTK — o
//     ÚNICO popover que resta, e é do GTK, não nosso) e a COVEIRA dos
//     filhos curtos (E146/C — o spawn→wait, zero <defunct>).
use crate::state::{
    bt_ligado, dentro_janela_ms, essid_nmcli, estado_rede_nmcli, icone_rede, icone_volume,
    json_text, le_bateria, media_pill, parse_volume_wpctl, parse_wifi_radio,
    parse_wpctl_status, relogio_ptbr, tooltip_rede, DispositivoAudio, EstadoRede,
};
use crate::{bus_sock, css_path, log, VERSION};
use elite_core::MediaState;
use std::cell::{Cell, RefCell};
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
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
    /// A FOTO DO ÁUDIO (E149 — o ÍCONE e o tooltip do botão; o mixer
    /// completo mora no pwvucontrol, a ferramenta que o esquerdo abre).
    /// None = o wpctl engasgou — o estado anterior CONSERVADO, a barra
    /// não pisca no vácuo.
    AudioDet(Option<AudioDetalhe>),
    /// (estado, essid) da rede — o assento é PERSISTENTE por desenho.
    Rede(EstadoRede, Option<String>),
    /// Powered do adaptador (None = bluetoothctl ausente/sem adaptador).
    Bt(Option<bool>),
    /// O texto do pill do modo de jogo — None = apagado.
    Game(Option<String>),
    /// 2.0 — o estado MPRIS do bus (zero playerctl; o pill some sem mídia)
    Media(Option<MediaState>),
    /// 2.0 — o modo de jogo pelo FIO (o SIGRTMIN+8 é o cinto)
    BusGame(bool),
    /// 2.0 — o handle do bus vivo (o Arc do cliente — os cliques pedem
    /// por ele; chega por mensagem porque o Rc da UI não cruza threads)
    Bus(std::sync::Arc<elite_core::bus::BusClient>),
}

/// A FOTO do áudio da casa (o padrão de SAÍDA e o de ENTRADA — os dois
/// defaults são a verdade que o botão veste; o resto é do pwvucontrol).
struct AudioDetalhe {
    sink: Option<DispositivoAudio>,
    fonte: Option<DispositivoAudio>,
}

/// A barra inteira (os widgets que mudam de cara).
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
    /// O instante do último release ACEITO na gaveta (o eco morre na
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
    // BLOCO 3 — O OUVIDOR DO MONITOR (a ordem do dono: GdkMonitor/
    // wl_output por EVENTO, zero polling ocioso): resolução/Hz/escala/
    // hotplug recalculam âncoras e zona exclusiva NO EVENTO.
    ouve_monitores(&window);

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

    // ── ESQUERDA (E149 — minimalista, a ordem do dono): o botão de
    //    apps com ÍCONE GTK de verdade + a palavra "Aplicativos" (sem
    //    siglas técnicas); AMBOS os cliques são o toggle do craft-apps
    //    (o menu rápido MORREU — "Bloquear tela" e "Encerrar sessão"
    //    têm endereço ÚNICO na sessão e no menu do desktop). As pílulas da
    //    mesa (`1 2 3 4`) e o título ativo SAÍRAM da barra: a troca de
    //    mesa é o scroll/atalhos W-1..4 do labwc, o título mora na
    //    moldura da própria janela — a barra fica LIMPA
    let btn_apps = botao_apps(&st);
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

        // E149 — O MAPA DIRETO DO ÁUDIO (a diretriz do dono: o clique
        // ESQUERDO abre a FERRAMENTA dedicada — o pwvucontrol é o mixer
        // de verdade, a central de controle completa; o DIREITO é a ação
        // imediata: mute/desmute da SAÍDA; o MEIO, o do MICROFONE; o
        // scroll ajusta o volume sem abrir nada).
        btn_audio.set_has_frame(false);
        btn_audio.set_child(Some(&audio_img));
        btn_audio.set_tooltip_text(Some(
            "Áudio — clique: pwvucontrol · scroll: volume · direito: mudo da saída · meio: mudo do microfone",
        ));
        {
            let tx = tx.clone();
            clique_solto(&btn_audio, move |botao| match botao {
                1 => abre_mixer(),
                2 => {
                    solta(&["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
                    pede_audio_detalhe(&tx);
                }
                3 => {
                    solta(&["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                    pede_audio_detalhe(&tx);
                }
                _ => {}
            });
        }
        scroll(&btn_audio, move |dy| {
            let passo = if dy < 0.0 { "5%+" } else { "5%-" };
            solta(&["wpctl", "set-volume", "--limit", "1.5", "@DEFAULT_AUDIO_SINK@", passo]);
        });
        dir.append(&btn_audio);

        // A REDE PERSISTENTE (a cura A4: o botão NUNCA sai — Cabo/
        // Wi-Fi/Desligado com ÍCONE GTK SEMPRE). E149 — O MAPA DIRETO:
        // o ESQUERDO abre o gerenciador PRÁTICO do dia a dia (o iwgtk,
        // a janela de redes própria da casa; ausente = o editor de
        // conexões assume — honesto, nunca um botão morto) e o DIREITO
        // alterna o RÁDIO Wi-Fi na hora (a ação imediata — nada de
        // editor técnico como fluxo principal).
        btn_rede.set_has_frame(false);
        btn_rede.set_child(Some(&rede_img));
        btn_rede.set_tooltip_text(Some(
            "Rede — clique: gerenciar as redes (iwgtk) · direito: ligar/desligar o Wi-Fi",
        ));
        clique_solto(&btn_rede, move |botao| match botao {
            1 => {
                if std::path::Path::new("/usr/bin/iwgtk").exists() {
                    solta(&["iwgtk"]);
                } else {
                    // rig sem iwgtk (a dose entrega via pacote — mas a
                    // barra nunca promete o que o sistema não tem)
                    solta(&["nm-connection-editor"]);
                }
            }
            3 => {
                std::thread::spawn(|| {
                    let on = um_longo("nmcli", &["radio", "wifi"])
                        .and_then(|t| parse_wifi_radio(&t));
                    if let Some(on) = on {
                        let cmd = if on { "off" } else { "on" };
                        let _ = Command::new("nmcli")
                            .args(["radio", "wifi", cmd])
                            .stdin(Stdio::null())
                            .stdout(Stdio::null())
                            .stderr(Stdio::null())
                            .status();
                    }
                });
            }
            _ => {}
        });
        dir.append(&btn_rede);

        // E149 — O BLUETOOTH DIRETO (a diretriz: o clique ESQUERDO abre
        // o gerenciador de VERDADE — o blueman-manager da casa, que o
        // elite-clean não remove mais; o DIREITO alterna o POWER do
        // adaptador na hora — a ação imediata sem janela).
        btn_bt.set_has_frame(false);
        btn_bt.set_child(Some(&bt_img));
        btn_bt.set_tooltip_text(Some(
            "Bluetooth — clique: gerenciar dispositivos (blueman) · direito: ligar/desligar",
        ));
        {
            let tx = tx.clone();
            clique_solto(&btn_bt, move |botao| match botao {
                1 => {
                    if std::path::Path::new("/usr/bin/blueman-manager").exists() {
                        solta(&["blueman-manager"]);
                    } else {
                        log("bluetooth: blueman-manager ausente — o pacote chega pelo elite-update (a cura da casa)");
                    }
                }
                3 => {
                    let tx = tx.clone();
                    std::thread::spawn(move || {
                        let ligado = um_longo("bluetoothctl", &["show"]).map(|t| bt_ligado(&t));
                        if let Some(on) = ligado {
                            let cmd = if on { "off" } else { "on" };
                            solta(&["bluetoothctl", "power", cmd]);
                            let _ = tx.send(Msg::Bt(Some(!on)));
                        }
                    });
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
        "craft-bar-rs {VERSION} no ar (E149 — o mapa direto): clique ESQUERDO abre a FERRAMENTA \
         de verdade (pwvucontrol · iwgtk · blueman-manager) · DIREITO é a ação rápida (mudo, \
         rádio Wi-Fi, power do Bluetooth) · MEIO muda o microfone · popovers customizados \
         REMOVIDOS (as ferramentas dedicadas mandam) · a gaveta tem UM dono (craft-apps, a \
         mesma porta do W-d) · ícones SÓ por nome de ícone GTK · relógio pt_BR + calendário \
         no hover · sessão popover nativo · MPRIS/jogo PELO FIO DO BUS · clique EXCLUSIVAMENTE \
         no released (tolerância 5px, E140)"
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
    Some(AudioDetalhe { sink, fonte })
}

/// A UI pede a FOTO do áudio NA HORA (o clique de mute/slide/dispositivo
/// não espera o belt de 2s — a resposta é o gesto; o belt é a rede).
fn pede_audio_detalhe(tx: &Sender<Msg>) {
    let tx = tx.clone();
    std::thread::spawn(move || {
        let _ = tx.send(Msg::AudioDet(foto_audio()));
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
    // o FILHO do drawer não mora mais aqui (E149 — a gaveta é do
    // craft-apps, um processo de UM tiro: o solta() é o coveiro dele)
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
            let s = st.borrow_mut();
            // o ÍCONE do botão da barra (muted/low/high pela verdade) +
            // o tooltip com o estado dos DOIS lados (E149 — o resto é
            // do pwvucontrol que o esquerdo abre)
            let mic_txt = d.fonte.as_ref().map(|f| {
                format!(" · mic {}", if f.mudo { "MUDO" } else { "ativo" })
            });
            if let Some(sink) = d.sink.as_ref() {
                s.audio_img.set_icon_name(Some(icone_volume(sink.vol, sink.mudo)));
                if sink.mudo {
                    s.btn_audio.add_css_class("muted");
                } else {
                    s.btn_audio.remove_css_class("muted");
                }
                s.btn_audio.set_tooltip_text(Some(&format!(
                    "Áudio {}%{}{} — clique: pwvucontrol · scroll: volume · direito: mudo · meio: mudo do microfone",
                    (sink.vol * 100.0).round() as i64,
                    if sink.mudo { " · MUDO" } else { "" },
                    mic_txt.as_deref().unwrap_or("")
                )));
            }
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
                    s.btn_bt.set_tooltip_text(Some(
                        "Bluetooth ligado — clique: gerenciar dispositivos (blueman) · direito: desligar",
                    ));
                }
                Some(false) => {
                    s.bt_img.set_icon_name(Some("bluetooth-disabled-symbolic"));
                    s.btn_bt.add_css_class("off");
                    s.btn_bt.set_tooltip_text(Some(
                        "Bluetooth desligado — clique: gerenciar dispositivos (blueman) · direito: ligar",
                    ));
                }
                None => {
                    s.bt_img.set_icon_name(Some("bluetooth-disabled-symbolic"));
                    s.btn_bt.add_css_class("off");
                    s.btn_bt.set_tooltip_text(Some("Sem adaptador Bluetooth"));
                }
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

// ── O DRAWER (E149 — UM dono: o craft-apps da casa) ──────────────────

/// Abre/fecha a gaveta pela porta ÚNICA (craft-apps — o mesmo toggle
/// do W-d: o bin mata a gaveta viva DO DONO ou abre uma nova; a barra
/// NUNCA DUPLICA a receita — o atraso/falha intermitente do rig morria
/// na receita duplicada que se matava). O eco do mesmo gesto morre na
/// janela de 150ms (a cura A1 intacta — o juízo puro segue no state).
fn toggle_gaveta(st: &Rc<RefCell<State>>) {
    let agora = agora_ns();
    {
        let mut s = st.borrow_mut();
        if s.drawer_ns > 0 && dentro_janela_ms(s.drawer_ns, agora, DRAWER_MS) {
            return; // o eco do mesmo gesto — a janela fala
        }
        s.drawer_ns = agora;
    }
    solta(&["craft-apps"]);
    log("drawer: toggle pela porta única (craft-apps — o mesmo verbo do W-d)");
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

/// E149 — O BOTÃO DE APPS (ícone GTK + palavra). UM dono do toggle: o
/// craft-apps da casa — o W-d e o botão partilham a MESMA porta (o
/// atraso intermitente do rig era a RECEITA DUPLICADA: a barra abria
/// a gaveta, o craft-apps a matava). O menu rápido do clique direito
/// MORRE (as ações dele já moram no menu do desktop e no de energia —
/// o dedupe da diretriz: "Bloquear tela" e "Encerrar sessão" tinham
/// dois endereços); o direito alterna IGUAL.
fn botao_apps(st: &Rc<RefCell<State>>) -> gtk::Button {
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
    btn.set_tooltip_text(Some("Aplicativos — clique: abre/fecha a gaveta (toggle de verdade)"));
    {
        let st = st.clone();
        clique_solto(&btn, move |_| {
            toggle_gaveta(&st);
        });
    }
    btn
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

/// ── BLOCO 3 — O OUVIDOR DO MONITOR (a ordem do dono: GdkMonitor/
/// wl_output por EVENTO, zero polling ocioso) ──────────────────────
/// O gesto é EVENTO, nunca poll: `monitor-added`/`monitor-removed`/
/// `monitors-changed` (o display) e `invalidate` (CADA monitor — o sinal
/// de GEOMETRIA/ESCALA do wl_output; docs GDK: "emitted when the
/// monitor's geometry or scale changes") re-afirmam as âncoras e a zona
/// exclusiva e commit o resize NO MESMO frame (a lei E144: resize é
/// commit, não animação) — a barra recalcula geometria em troca de
/// resolução/Hz/escala e em hotplug sem renascer (o DRM uevent do
/// elite-daemon SIGUSR2 cuida do refresh de pele; ESTE ouvidor cuida da
/// GEOMETRIA). O frame pacing segue o frame clock do compositor (frame
/// callbacks do Wayland) — alinhado ao Hz nativo por desenho do
/// protocolo, sem timer nenhum.
fn reafirma_geometria(window: &gtk::ApplicationWindow) {
    window.set_anchor(gtk4_layer_shell::Edge::Top, true);
    window.set_anchor(gtk4_layer_shell::Edge::Left, true);
    window.set_anchor(gtk4_layer_shell::Edge::Right, true);
    window.auto_exclusive_zone_enable();
    window.queue_resize();
}

fn ouve_monitores(window: &gtk::ApplicationWindow) {
    let Some(disp) = gdk::Display::default() else {
        return;
    };
    // os monitores VIVOS no arranque: o invalidate é o sinal de
    // geometria/escala do wl_output (a troca de modo chega AQUI)
    let lista = disp.monitors();
    for i in 0..lista.n_items() {
        let Some(mon) = lista.item(i).and_downcast::<gdk::Monitor>() else {
            continue;
        };
        let w = window.clone();
        mon.connect_invalidate(move |_| reafirma_geometria(&w));
    }
    // hotplug: o monitor NOVO ganha o próprio ouvidor de invalidate
    {
        let w = window.clone();
        disp.connect_monitor_added(move |_, mon| {
            let novo = w.clone();
            mon.connect_invalidate(move |_| reafirma_geometria(&novo));
            reafirma_geometria(&w);
            log("GdkMonitor: monitor adicionado — âncoras/zona exclusiva re-afirmadas");
        });
    }
    // a saída de um monitor: a âncora sobrevive no output que fica
    {
        let w = window.clone();
        disp.connect_monitor_removed(move |_, _mon| {
            reafirma_geometria(&w);
            log("GdkMonitor: monitor removido — âncoras/zona exclusiva re-afirmadas");
        });
    }
    // o gatilho do CHURN do conjunto de outputs (o Wayland emite
    // monitors-changed na troca de arranjo; deprecated SÓ sob a feature
    // v4_16 — a casa não liga features de versão, o gtk4-rs 0.11 o
    // entrega sem aviso)
    {
        let w = window.clone();
        disp.connect_monitors_changed(move |_| {
            reafirma_geometria(&w);
            log("GdkDisplay: monitors-changed — geometria re-afirmada");
        });
    }
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

