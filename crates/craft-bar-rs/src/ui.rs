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
    json_text, le_bateria, media_pill, parse_dnd_swaync, parse_volume_wpctl, parse_wifi_radio,
    parse_wpctl_status, relogio_ptbr, tooltip_rede, DispositivoAudio, EstadoRede,
};
use crate::{bus_sock, css_path, log, VERSION};
use elite_core::MediaState;
use std::cell::{Cell, RefCell};
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::rc::Rc;
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::mpsc::{Receiver, Sender};
use std::time::{Duration, Instant};

use gtk4::prelude::*;
use gtk4::{gdk, glib};
use gtk4 as gtk;
use gtk4_layer_shell::LayerShell;

/// A altura da faixa (E151 — a ordem do dono: 28px, a proporção da
/// barra obsidiana; a zona exclusiva segue automática e honesta).
const ALTURA: i32 = 28;
/// O dreno do canal da thread de fundo (latência dos estados ≤100ms).
const DRAIN_MS: u64 = 100;
/// O DEBOUNCE do drawer (a ordem do dono: 150ms, zero bloqueio).
const DRAWER_MS: u64 = 150;
/// A tolerância de arrasto: released a >10px do press é ARRASTO, não
/// clique (a cura 1.0-101 do audit 99: 5px descartava cliques REAIS em
/// telas de 120Hz — o jitter do pointer entre pressed e released passa
/// da metade do frame; 10px é a folga que o dono pediu).
const ARRASTO_PX: f64 = 10.0;
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
    /// (estado, essid, rádio do Wi-Fi) da rede — o assento é
    /// PERSISTENTE por desenho; o rádio tem voz no tooltip MESMO com o
    /// cabo ligado (1.0-104).
    Rede(EstadoRede, Option<String>, Option<bool>),
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
    /// 1.0-104 — o DND REAL do swaync (`swaync-client -D`): o sino
    /// cortado acende/colore na barra no mesmo instante do clique
    /// direito (None = swaync calado — o estado anterior conserva).
    Dnd(Option<bool>),
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
    /// E151 — O MICROFONE É ASSENTO PRÓPRIO (a diretriz do dono: Áudio
    /// (saída) e Microfone (entrada) SEPARADOS, ícones de mudo
    /// distintos — o mudo do mic não é mais o clique do meio).
    btn_mic: gtk::Button,
    /// E151 — o ícone do microfone (microphone-sensitivity-*).
    mic_img: gtk::Image,
    btn_rede: gtk::Button,
    /// E147 — o ícone de rede (Image::from_icon_name).
    rede_img: gtk::Image,
    btn_bt: gtk::Button,
    /// E147 — o ícone de bluetooth (Image::from_icon_name).
    bt_img: gtk::Image,
    btn_game: gtk::Button,
    btn_player: gtk::Button,
    /// 1.0-101 — o ÍCONE DE STATUS da mídia (media-playback-start/pause
    /// — o glifo Nerd da pílula morre com a fonte que não o tem).
    player_img: gtk::Image,
    player_label: gtk::Label,
    /// 1.0-104 — O BOTÃO DE PRÓXIMA FAIXA (a ordem do dono: o pill do
    /// player mostra o título curto COM os botões de Play/Pause e
    /// Próxima faixa — o Próximo é assento próprio ao lado do pill,
    /// nasce e morre JUNTO com ele).
    btn_next: gtk::Button,
    /// 1.0-104 — O SINO CORTADO do Não Perturbe (visível quando o DND
    /// REAL do swaync está LIGADO — a mensagem do clique direito).
    dnd_img: gtk::Image,
    /// 1.0-104 — o rádio do Wi-Fi (None = nmcli calado — o tooltip não
    /// inventa o que não leu).
    wifi_radio: Option<bool>,
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
    app.connect_activate(build);
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
            libc::signal(s, on_signal as *const () as libc::sighandler_t);
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
        btn_mic: gtk::Button::new(),
        mic_img: gtk::Image::from_icon_name(crate::state::icone_mic(false)),
        btn_rede: gtk::Button::new(),
        rede_img: gtk::Image::from_icon_name(icone_rede(EstadoRede::Desligado)),
        btn_bt: gtk::Button::new(),
        bt_img: gtk::Image::from_icon_name("bluetooth-disabled-symbolic"),
        btn_game: gtk::Button::new(),
        btn_player: gtk::Button::new(),
        player_img: gtk::Image::from_icon_name("media-playback-start-symbolic"),
        player_label: gtk::Label::new(None),
        btn_next: gtk::Button::new(),
        dnd_img: gtk::Image::from_icon_name("notification-disabled-symbolic"),
        wifi_radio: None,
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
    st.borrow().mic_img.set_pixel_size(16);
    st.borrow().rede_img.set_pixel_size(16);
    st.borrow().bt_img.set_pixel_size(16);
    st.borrow().dnd_img.set_pixel_size(14);

    // E151 — ZERO VAZAMENTO DE TEMA GTK4 (a diretriz do dono: o seletor
    // roxo travado e o quadrado branco morrem pela RAIZ): nenhum botão
    // da barra fica com foco persistente (focus_on_click(false) +
    // can_focus(false)) — o contorno do tema nunca pinta; a reação é
    // EXCLUSIVAMENTE o :hover suave da pele da casa. A aplicação corre
    // sobre a árvore pronta no fim do build (apaga_foco_da_barra).

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
        let tx = tx.clone();
        clique_solto(&btn_clock, move |botao| {
            // esquerdo: o painel (toggle SEM sequestrar o foco -sw);
            // direito: o DND (idem -sw) COM o sino cortado acendendo NA
            // HORA (1.0-104: a thread lê o estado REAL do swaync e a
            // barra veste — o feedback nunca é o palpite, é o fato);
            // meio: o calendário. O TEXTO NÃO MUDA — o clique é ação, a
            // data é a data (a cura do "alterna o texto exibido").
            if botao == 1 {
                solta(&["swaync-client", "-t", "-sw"]);
            } else if botao == 3 {
                solta(&["swaync-client", "-d", "-sw"]);
                pede_dnd(&tx);
            } else if botao == 2 {
                if pop_cal.is_visible() {
                    pop_cal.popdown();
                } else {
                    pop_cal.popup();
                }
            }
        });
    }
    // 1.0-104 — O SINO CORTADO AO LADO DO RELÓGIO (o feedback visual do
    // DND REAL do swaync: o ícone mora no CENTRO junto da hora — quem
    // alterna o Não Perturbe lê o resultado no MESMO lugar do clique;
    // o estado chega pelo fio de fundo no frame seguinte ao gesto).
    {
        let dnd_img = st.borrow().dnd_img.clone();
        dnd_img.set_widget_name("dndimg");
        dnd_img.set_valign(gtk::Align::Center);
        dnd_img.set_visible(false);
        let caixa_rel = gtk::Box::new(gtk::Orientation::Horizontal, 4);
        caixa_rel.set_valign(gtk::Align::Center);
        caixa_rel.append(&btn_clock);
        caixa_rel.append(&dnd_img);
        centro.append(&caixa_rel);
        // o frame 0 do DND (a thread pergunta ao swaync e a resposta veste
        // o sino — sem palpite, o estado REAL)
        pede_dnd(&tx);
    }

    // ── DIREITA (E147 — o contrato mouse-first: game → player → áudio →
    //    microfone (E151) → rede → bluetooth → bateria → sessão) ──
    {
        let s = st.borrow();
        let btn_game = s.btn_game.clone();
        let btn_player = s.btn_player.clone();
        let btn_next = s.btn_next.clone();
        let player_img = s.player_img.clone();
        let player_label = s.player_label.clone();
        let btn_audio = s.btn_audio.clone();
        let audio_img = s.audio_img.clone();
        let btn_mic = s.btn_mic.clone();
        let mic_img = s.mic_img.clone();
        let btn_rede = s.btn_rede.clone();
        let rede_img = s.rede_img.clone();
        let btn_bt = s.btn_bt.clone();
        let bt_img = s.bt_img.clone();
        drop(s);

        // O MODO DE JOGO (E115/E126 intactos: o estado REAL do
        // GameMode no pill, clique DIREITO desliga na hora) — acende
        // no SIGRTMIN+8 que o elite-daemon manda na transição. O ícone
        // é Image de ÍCONE (input-gaming — o tema da casa tem) e veste
        // o ROXO da paleta (#a855f7 — 1.0-104: o assento do jogo é o
        // acento da casa, o indicador persistente lê-se de longe).
        {
            let img = gtk::Image::from_icon_name("input-gaming-symbolic");
            img.set_pixel_size(16);
            btn_game.set_child(Some(&img));
        }
        btn_game.set_widget_name("gamebtn");
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
        // Play/Pause, scroll cima/baixo = próxima/anterior, direito =
        // FOCAR a janela do player (o match benigno do daemon).
        // 1.0-101 — A PÍLULA REFINADA: ícone de STATUS + "Artista -
        // Título" truncado (≤28 — o juízo mora no state::pilula_midia);
        // oculta (0px) sem player no bus, visível tocando OU pausado.
        btn_player.set_widget_name("playerbtn");
        btn_player.set_has_frame(false);
        btn_player.set_valign(gtk::Align::Center);
        {
            let linha = gtk::Box::new(gtk::Orientation::Horizontal, 5);
            player_img.set_pixel_size(14);
            player_img.set_valign(gtk::Align::Center);
            player_label.set_valign(gtk::Align::Center);
            linha.set_valign(gtk::Align::Center);
            linha.append(&player_img);
            linha.append(&player_label);
            btn_player.set_child(Some(&linha));
        }
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

        // 1.0-104 — O BOTÃO DE PRÓXIMA FAIXA (a ordem do dono: o pill do
        // player mostra o título curto COM os botões de Play/Pause e
        // Próxima faixa). O play/pause é o clique do pill DE ALWAYS; o
        // PRÓXIMO é assento próprio — ícone media-skip-forward, nasce e
        // morre JUNTO com o pill (uma pílula só de mídia em cena).
        btn_next.set_widget_name("nextbtn");
        btn_next.set_has_frame(false);
        btn_next.set_valign(gtk::Align::Center);
        {
            let img = gtk::Image::from_icon_name("media-skip-forward-symbolic");
            img.set_pixel_size(14);
            img.set_valign(gtk::Align::Center);
            btn_next.set_child(Some(&img));
        }
        btn_next.set_visible(false);
        btn_next.set_tooltip_text(Some("Mídia — próxima faixa"));
        {
            let bus = st.borrow().bus_cli.clone();
            clique_solto(&btn_next, move |botao| {
                if botao == 1 {
                    pede_bus(&bus, elite_core::MediaCmd::Next);
                }
            });
        }
        dir.append(&btn_next);

        // E149/E151 — O MAPA DIRETO DO ÁUDIO: SAÍDA é o botão de
        // cima; o ESQUERDO abre a FERRAMENTA dedicada (pwvucontrol), o
        // DIREITO alterna o mudo da SAÍDA, o SCROLL ajusta o volume —
        // o mudo do MICROFONE morou no clique do meio e MORRE (o mic
        // ganhou assento próprio abaixo).
        btn_audio.set_has_frame(false);
        btn_audio.set_child(Some(&audio_img));
        btn_audio.set_tooltip_text(Some(
            "Áudio (saída) — clique: pwvucontrol · scroll: volume · direito: mudo",
        ));
        {
            let tx = tx.clone();
            clique_solto(&btn_audio, move |botao| match botao {
                1 => abre_mixer(),
                3 => {
                    solta(&["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                    pede_audio_detalhe(&tx);
                }
                _ => {}
            });
        }
        {
            let tx = tx.clone();
            scroll(&btn_audio, move |dy| {
                let passo = if dy < 0.0 { "5%+" } else { "5%-" };
                solta(&["wpctl", "set-volume", "--limit", "1.5", "@DEFAULT_AUDIO_SINK@", passo]);
                // 1.0-104 — O ÍCONE/PERCENTUAL VESTE NO GESTO (a ordem do
                // dono: a atualização é INSTANTÂNEA no scroll — sem
                // esperar o cinto de 2s; a thread curta pergunta ao wpctl
                // e o dreno veste no frame seguinte)
                pede_audio_detalhe(&tx);
            });
        }
        dir.append(&btn_audio);

        // E151 — O MICROFONE É ASSENTO PRÓPRIO (a diretriz: Áudio e
        // Microfone SEPARADOS com ícones de mudo distintos): o ESQUERDO
        // abre o mesmo mixer (aba de entrada), o DIREITO alterna o mudo
        // da ENTRADA, o SCROLL ajusta o ganho — nada do segundo lado
        // escondido num clique do meio que ninguém descobre.
        btn_mic.set_widget_name("micbtn");
        btn_mic.set_has_frame(false);
        btn_mic.set_child(Some(&mic_img));
        btn_mic.set_tooltip_text(Some(
            "Microfone (entrada) — clique: pwvucontrol · scroll: ganho · direito: mudo",
        ));
        {
            let tx = tx.clone();
            clique_solto(&btn_mic, move |botao| match botao {
                1 => abre_mixer(),
                3 => {
                    solta(&["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
                    pede_audio_detalhe(&tx);
                }
                _ => {}
            });
        }
        {
            let tx = tx.clone();
            scroll(&btn_mic, move |dy| {
                let passo = if dy < 0.0 { "3%+" } else { "3%-" };
                solta(&["wpctl", "set-volume", "--limit", "1.5", "@DEFAULT_AUDIO_SOURCE@", passo]);
                // 1.0-104 — idem do áudio: o ganho veste NO GESTO
                pede_audio_detalhe(&tx);
            });
        }
        dir.append(&btn_mic);

        // A REDE PERSISTENTE (a cura A4: o botão NUNCA sai — Cabo/
        // Wi-Fi/Desligado com ÍCONE GTK SEMPRE). 1.0-101 — O MAPA DO
        // AUDIT 99: o ESQUERDO abre o gerenciador de conexões de
        // VERDADE — "craft-connect se funcional, ou nm-connection-
        // editor como fallback GARANTIDO": o craft-connect é o fóssil
        // da era fuzzel (a E141b o aposentou; o disco não o tem mais),
        // então a barra PERGUNTA AO DISCO e o editor completo do
        // NetworkManager assume — nunca um botão morto. O DIREITO
        // segue a ação imediata: alterna o RÁDIO Wi-Fi.
        btn_rede.set_has_frame(false);
        btn_rede.set_child(Some(&rede_img));
        btn_rede.set_tooltip_text(Some(
            "Rede — clique: gerenciar as conexões · direito: ligar/desligar o Wi-Fi",
        ));
        clique_solto(&btn_rede, {
            // 1.0-104 — o clone do canal NASCE ANTES do move (a resposta da
            // rede é o gesto: o clique direito re-lê o rádio E as placas)
            let tx = tx.clone();
            move |botao| match botao {
                1 => {
                    // 1.0-104 — O GERENCIADOR COMPLETO E AMIGÁVEL (a ordem do
                    // dono: o esquerdo abre o seletor NATIVO — sem exigir a
                    // criação manual de perfil: o iwgtk é o Wi-Fi da casa
                    // (AGENTS §5, GTK nativo, redes ao alcance + conexões de
                    // um clique); sem ele, o editor completo do NetworkManager
                    // (Wi-Fi, cabo, VPN e banda larga) assume — nunca botão
                    // morto, nunca perfil na mão do dono).
                    if std::path::Path::new("/usr/bin/iwgtk").exists() {
                        solta(&["iwgtk"]);
                    } else {
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
                    // 1.0-104 — O TOOLTIP REFLETE O GESTO NA HORA (a thread
                    // curta re-lê o rádio + o estado das placas e o dreno
                    // veste o ícone/tooltip no frame seguinte — quem desligou
                    // o Wi-Fi com o cabo ligado lê o feito no MESMO instante)
                    pede_rede_foto(&tx);
                }
                _ => {}
            }
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
        libc::signal(libc::SIGRTMIN() + 8, on_signal as *const () as libc::sighandler_t);
        libc::signal(libc::SIGUSR2, on_signal as *const () as libc::sighandler_t);
    }

    load_css();
    desenha_relogio(&st); // o frame 0 já nasce com a hora certa
    // E151 — A PÁLIDA DO FOCO corre sobre a ÁRVORE PRONTA (todos os
    // botões/menubuttons já nasceram): nenhum tema externo veste
    // contorno/seleção aqui nunca mais.
    apaga_foco_da_barra(corpo.upcast_ref());
    window.show();

    log(&format!(
        "craft-bar-rs {VERSION} no ar (E151 — a barra obsidiana): 28px · a MESMA ilha escura da dock · \
         SAÍDA e MICROFONE em assentos próprios (esquerdo abre o pwvucontrol · direito muda) · \
         foco de tema DESATIVADO nos botões (zero seletor travado/quadrado branco — só hover) · \
         relógio esquerdo abre/fecha o painel swaync · rede/Bluetooth sob demanda (iwgtk · blueman) · \
         relógio pt_BR + calendário · MPRIS/jogo PELO FIO DO BUS"
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
                let radio = um_longo("nmcli", &["radio", "wifi"])
                    .and_then(|r| parse_wifi_radio(&r));
                let _ = tx.send(Msg::Rede(estado_rede_nmcli(&t), essid_nmcli(&t), radio));
            }
            // 1.0-104 — o DND REAL junto do cinto da rede (5s: quem alterna
            // pelo PAINEL do swaync também veste o sino na hora certa — o
            // belt é a rede de segurança, o clique é o gesto imediato)
            let _ = tx.send(Msg::Dnd(
                um_longo("swaync-client", &["-D"]).and_then(|t| parse_dnd_swaync(&t)),
            ));
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

/// 1.0-104 — A FOTO DA REDE NA HORA (o clique direito do rádio Wi-Fi não
/// espera o cinto de 5s — a resposta é o gesto): as placas E o rádio numa
/// resposta só (o tooltip do cabo fala do Wi-Fi no MESMO frame).
fn pede_rede_foto(tx: &Sender<Msg>) {
    let tx = tx.clone();
    std::thread::spawn(move || {
        let Some(t) = um_longo(
            "nmcli",
            &["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"],
        ) else {
            return;
        };
        let radio = um_longo("nmcli", &["radio", "wifi"])
            .and_then(|r| parse_wifi_radio(&r));
        let _ = tx.send(Msg::Rede(estado_rede_nmcli(&t), essid_nmcli(&t), radio));
    });
}

/// 1.0-104 — A PERGUNTA DO DND (o clique direito do relógio responde na
/// hora): a thread curta pergunta ao swaync (`-D`) e o dreno veste o sino
/// cortado no frame seguinte — o feedback é o estado REAL, nunca o
/// palpite do gesto (None = swaync calado: o estado anterior conserva).
fn pede_dnd(tx: &Sender<Msg>) {
    let tx = tx.clone();
    std::thread::spawn(move || {
        let _ = tx.send(Msg::Dnd(
            um_longo("swaync-client", &["-D"]).and_then(|t| parse_dnd_swaync(&t)),
        ));
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
    while let Ok(msg) = rx.try_recv() {
        aplica(st, msg);
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
            // E151 — OS DOIS ASSENTOS VESTEM JUNTOS: a SAÍDA (ícone de
            // volume + classe .muted própria) e a ENTRADA (ícone de mic
            // + classe própria) — um lado mudo NUNCA mais pinta o
            // botão do outro.
            if let Some(sink) = d.sink.as_ref() {
                s.audio_img.set_icon_name(Some(icone_volume(sink.vol, sink.mudo)));
                if sink.mudo {
                    s.btn_audio.add_css_class("muted");
                } else {
                    s.btn_audio.remove_css_class("muted");
                }
                veste_tooltip(
                    &s.btn_audio,
                    &format!(
                        "Áudio {}%{} — clique: pwvucontrol · scroll: volume · direito: mudo",
                        (sink.vol * 100.0).round() as i64,
                        if sink.mudo { " · MUDO" } else { "" },
                    ),
                );
            }
            if let Some(fonte) = d.fonte.as_ref() {
                s.mic_img.set_icon_name(Some(crate::state::icone_mic(fonte.mudo)));
                if fonte.mudo {
                    s.btn_mic.add_css_class("muted");
                } else {
                    s.btn_mic.remove_css_class("muted");
                }
                veste_tooltip(
                    &s.btn_mic,
                    &format!(
                        "Microfone {}%{} — clique: pwvucontrol · scroll: ganho · direito: mudo",
                        (fonte.vol * 100.0).round() as i64,
                        if fonte.mudo { " · MUDO" } else { "" },
                    ),
                );
            }
        }
        Msg::Rede(estado, essid, radio) => {
            let mut s = st.borrow_mut();
            s.rede = estado;
            s.essid = essid.clone();
            s.wifi_radio = radio;
            s.rede_img.set_icon_name(Some(icone_rede(estado)));
            veste_tooltip(&s.btn_rede, &tooltip_rede(estado, essid.as_deref(), radio));
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
            // 2.0 — o MPRIS pelo fio: o estado tipado vira a pílula
            // 1.0-101 (ícone de STATUS + Artista - Título ≤28; sem
            // player no bus o assento SAI — oculto 0px)
            // 1.0-104 — o PRÓXIMO nasce com o pill (a ordem do dono:
            // Play/Pause no clique do pill + Próxima faixa no assento
            // próprio — os DOIS botões da mídia em cena)
            let s = st.borrow_mut();
            match m.as_ref().and_then(media_pill) {
                Some(pill) => {
                    s.player_img.set_icon_name(Some(pill.icone));
                    s.player_label.set_text(&pill.texto);
                    s.btn_player.set_tooltip_text(Some(&pill.tooltip));
                    s.btn_player.set_visible(true);
                    s.btn_next.set_visible(true);
                }
                None => {
                    s.btn_player.set_visible(false);
                    s.btn_next.set_visible(false);
                }
            }
        }
        Msg::BusGame(ativa) => {
            let s = st.borrow_mut();
            s.btn_game.set_visible(ativa);
        }
        Msg::Dnd(estado) => {
            // 1.0-104 — O SINO CORTADO VESTE O FATO REAL (`swaync-client -D`):
            // Some(true) = o Não Perturbe LIGADO (o sino acende no centro);
            // Some(false) = desligado (o sino some); None = swaync calado
            // (o estado anterior conserva — a barra nunca palpite o DND)
            let s = st.borrow_mut();
            s.dnd_img.set_visible(estado == Some(true));
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

/// 1.0-104 — O TOOLTIP SÓ VESTE QUANDO MUDA (a ordem do dono: estável
/// enquanto o ponteiro mora no botão — o texto IGUAL não re-pincha o
/// popover do GTK a cada belt de 2s; o que muda veste, o que é igual
/// fica quieto no hover).
fn veste_tooltip<W: IsA<gtk::Widget>>(w: &W, texto: &str) {
    if w.tooltip_text().as_deref() != Some(texto) {
        w.set_tooltip_text(Some(texto));
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

/// E151 — A PÁLIDA DO FOCO (zero vazamento de tema GTK4): corre sobre
/// a árvore da barra e DESATIVA o foco persistente em TODO botão —
/// `focus_on_click(false)` (o clique não rouba a Banana do tema) e
/// `can_focus(false)` (o contorno `:focus` do tema externo nunca
/// pinta). O seletor roxo travado do popover de energia e o quadrado
/// branco do MenuButton `:checked` morrem aqui E no CSS (os estados
/// `:checked`/`:active`/`:focus` veste `background-image: none` +
/// `box-shadow: none`). A barra reage EXCLUSIVAMENTE ao `:hover`.
fn apaga_foco_da_barra(raiz: &gtk::Widget) {
    if let Ok(b) = raiz.clone().downcast::<gtk::Button>() {
        b.set_focus_on_click(false);
        b.set_can_focus(false);
    }
    if let Ok(mb) = raiz.clone().downcast::<gtk::MenuButton>() {
        mb.set_focus_on_click(false);
        mb.set_can_focus(false);
    }
    let mut c = raiz.first_child();
    while let Some(filho) = c {
        c = filho.next_sibling();
        apaga_foco_da_barra(&filho);
    }
}

/// E149 — O BOTÃO DE APPS (ícone GTK + palavra). UM dono do toggle: o
/// craft-apps da casa — o W-d e o botão partilham a MESMA porta (o
/// atraso intermitente do rig era a RECEITA DUPLICADA: a barra abria
/// a gaveta, o craft-apps a matava). O menu rápido do clique direito
/// MORRE (as ações dele já moram no menu do desktop e no de energia —
/// o dedupe da diretriz: "Bloquear tela" e "Encerrar sessão" tinham
/// dois endereços).
/// 1.0-101 — O GESTO É O CLIQUE ESQUERDO (a cura do audit 99: o toggle
/// disparava em QUALQUER botão — o direito (contexto de menu) abria a
/// gaveta sem o dono pedir; agora só o botão 1 manda). O alinhamento
/// vive nos 28px da faixa: Box verticalmente CENTRADO, ícone 16px e
/// label sem margem própria (o padding da pele manda — theme.css).
fn botao_apps(st: &Rc<RefCell<State>>) -> gtk::Button {
    let btn = gtk::Button::new();
    btn.set_widget_name("appbtn");
    btn.set_has_frame(false);
    btn.set_valign(gtk::Align::Center);
    let linha = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    linha.set_valign(gtk::Align::Center);
    let img = gtk::Image::from_icon_name("view-app-grid-symbolic");
    img.set_pixel_size(16);
    img.set_valign(gtk::Align::Center);
    img.set_margin_top(0);
    img.set_margin_bottom(0);
    let lbl = gtk::Label::new(Some("Aplicativos"));
    lbl.set_valign(gtk::Align::Center);
    lbl.set_margin_top(0);
    lbl.set_margin_bottom(0);
    linha.append(&img);
    linha.append(&lbl);
    btn.set_child(Some(&linha));
    btn.set_tooltip_text(Some(
        "Aplicativos — clique esquerdo: abre/fecha a gaveta (toggle de verdade)",
    ));
    {
        let st = st.clone();
        clique_solto(&btn, move |botao| {
            if botao == 1 {
                toggle_gaveta(&st);
            }
        });
    }
    btn
}

/// A LEI DO CLIQUE (a cura B1): o verbo dispara EXCLUSIVAMENTE no
/// GestureClick::released com tolerância de arrasto < 10px — nunca no
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
                acao(botao);
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
    // E151 — o Result do spawn é IGNORADO DE PROPÓSITO (a coveira é
    // best-effort: sem thread, o fork nem nasce — o log de baixo já
    // diz); o let _ cala o unused_must_use sem esconder nada.
    let _ = std::thread::Builder::new()
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
        let l = lista.clone();
        l.connect_items_changed(move |model, pos, removidos, adicionados| {
            // cada monitor NOVO ganha o próprio ouvidor de invalidate
            // (o gesto de GEOMETRIA/escala chega por ele, não por aqui)
            for i in pos..pos + adicionados {
                let Some(mon) = model.item(i).and_downcast::<gdk::Monitor>() else {
                    continue;
                };
                let novo = w.clone();
                mon.connect_invalidate(move |_| reafirma_geometria(&novo));
            }
            if removidos > 0 || adicionados > 0 {
                // a saída de um monitor: a âncora sobrevive no output que
                // fica; o churn reafirma de qualquer forma
                reafirma_geometria(&w);
                log("GdkDisplay: items-changed no modelo de monitores — âncoras/zona exclusiva re-afirmadas");
            }
        });
    }
}

/// A pele da casa: a FOLHA MESTRA embutida (elite-core) entra PRIMEIRO e
/// o override LIVRE do dono (~/.config/elite/bar.css) SOMA POR BAIXO do
/// cascade — o dono vence os empates, a mestra nunca morre (1.0-104 — a
/// MESMA cura da dock: o override de era SUBSTITUÍA a folha inteira e as
/// regras `popover > contents` da mestra — a pele escura do calendário e
/// do menu de sessão — morriam com ele; a mestra entra primeiro, o
/// popover é da casa em QUALQUER rig, com ou sem override). SIGUSR2
/// relê no mesmo gesto.
fn load_css() {
    let mestra = elite_core::THEME_CSS;
    let css = std::fs::read_to_string(css_path())
        .map(|extra| format!("{mestra}\n{extra}"))
        .unwrap_or_else(|_| mestra.to_string());
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

