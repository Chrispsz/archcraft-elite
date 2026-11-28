// ELITE · craft-bar-rs — ui.rs (E149 — O MAPA DIRETO, a simplificação
// radical da diretriz: a barra abre FERRAMENTAS DE VERDADE, não inventa
// controles que as ferramentas dedicadas já fazem melhor).
// Este módulo SÓ compila com a feature "gui" (exige o GTK dev do
// ambiente de build do pacote — o CI valida; o sandbox sem GTK
// compila/testa o NÚCLEO: state/main).
//
// O MAPA DE CLIQUES E149 (a lei nova da casa, válida para TODOS os
// botões da barra):
//   · CLIQUE ESQUERDO = o controle principal abre DIRETO — áudio →
//     pwvucontrol (pavucontrol honesto quando só ele existe), rede →
//     o SELETOR RÁPIDO da casa (craft-pick — 1.0-106: toggles de
//     Wi-Fi/Ethernet + redes ao alcance com sinal + a porta do editor
//     no fim; a conexão em 1 CLIQUE pelo nmcli), bluetooth →
//     blueman-manager, apps → o CRAFT-APPS (1.0-108 — a MESMA gaveta
//     da tecla Windows), bateria → craft-bat;
//   · CLIQUE DIREITO = a AÇÃO RÁPIDA sem janela nenhuma — mute/desmute
//     da SAÍDA, a CONEXÃO ATIVA liga/desliga (networking para o cabo,
//     rádio para o Wi-Fi — 1.0-106), power do Bluetooth;
//   · 1.0-105 — O ESQUERDO VESTE O `clicked` DO PRÓPRIO GtkButton: o
//     GestureClick externo NUNCA via o botão 1 (o botão consome o
//     gesto interno e emite `clicked` — o mesmo caminho do botão
//     Sessão que SEMPRE funcionou). O GestureClick fica EXCLUSIVO do
//     direito/meio e o EventControllerScroll da rolagem;
//   · CLIQUE DO MEIO = o segundo lado (mudo do MICROFONE) / o editor
//     completo de conexões (rede);
//   · SCROLL = o gesto de ajuste fino (volume, faixa do player);
//   · HOVER = o feedback visual da pele (theme.css) + o tooltip que
//     diz o que cada clique faz.
//
// 1.0-106 — O RELÓGIO É HORA/CALENDÁRIO: a central de notificações da
// era MORREU por ordem do dono (o rig fotografou o crash-loop do
// start-limit-hit e as chamadas travadas ao bus dela — dispensada
// INTEIRA, sem substituto): o esquerdo abre o CALENDÁRIO (o popover
// GTK4 que já existia no clique do meio), NENHUM timeout D-Bus em
// org.freedesktop.Notifications existe no caminho do clique — o
// relógio nunca mais trava em notificador nenhum.
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
//   · O CRAFT-APPS no botão de apps (1.0-108 — a MESMA gaveta da tecla
//     Windows; o fuzzel de era segue vivo como launcher de terminal);
//   · o RELÓGIO pt_BR que nunca muda de texto + o calendário SÓ no
//     clique (1.0-108 — o hover de era morreu);
//   · o MPRIS/jogo PELO FIO DO BUS + os sinais SIGRTMIN+8 (jogo) e
//     SIGUSR2 (a pele);
//   · a SESSÃO e o CALENDÁRIO em JANELAS DE CAMADA Overlay (1.0-109
//     §2.1: os menus vestem o MenuCamada — SEMPRE acima da gaveta top
//     do craft-apps; o PopoverMenu/MenuButton de era morreu com o
//     popover pendurado) e a COVEIRA dos filhos curtos (E146/C — o
//     spawn→wait, zero <defunct>).
use crate::state::{
    bt_ligado, estado_rede_nmcli, essid_nmcli, icone_rede, icone_volume, json_text, le_bateria,
    media_pill, parse_volume_wpctl, parse_wifi_radio, parse_wpctl_status, relogio_ptbr,
    tooltip_rede, DispositivoAudio, EstadoRede,
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
    /// Powered do adaptador (None = bluetoothctl ausente/sem adaptador;
    /// 1.0-106 — o fio do daemon também veste: o BluetoothState do bus
    /// chega com o Powered consultado NO ARRANQUE do BlueZ).
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
    /// 1.0-101 — o ÍCONE DE AÇÃO da mídia (media-playback-start/pause
    /// — o glifo Nerd da pílula morre com a fonte que não o tem).
    player_img: gtk::Image,
    player_label: gtk::Label,
    /// 1.0-104 — o rádio do Wi-Fi (None = nmcli calado — o tooltip não
    /// inventa o que não leu).
    wifi_radio: Option<bool>,
    btn_bat: Option<gtk::Button>,
    /// O último minuto desenhado no relógio (o label só toca na
    /// virada — nenhum gesto por segundo).
    minuto_desenhado: u32,
    rede: EstadoRede,
    essid: Option<String>,
    /// 2.0 — o handle do bus (o Arc do cliente vivo — os pedidos dos
    /// cliques: PlayPause/Next/Focus/mesa/jogo)
    bus_cli: Rc<RefCell<Option<std::sync::Arc<elite_core::bus::BusClient>>>>,
    /// 1.0-109 §2.1 — O CARD DO CALENDÁRIO VESTE A CAMADA (a janela
    /// Overlay — SEMPRE acima da gaveta top do craft-apps; o popover
    /// de era era FILHO da superfície top da barra e a gaveta o cobria
    /// inteiro — a evidência do dump 1.0-108)
    menu_cal: craft_tools::MenuCamada,
    /// 1.0-109 §2.1 — O CARDÁPIO DA SESSÃO na MESMA camada Overlay (o
    /// MenuButton/PopoverMenu de era morreu com o popover pendurado).
    menu_power: craft_tools::MenuCamada,
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
                            // 1.0-106 — o BlueZ do daemon (o Powered
                            // consultado no arranque + cada mudança): o
                            // ícone veste o fio ANTES do primeiro frame
                            elite_core::BusMsg::Bluetooth(bt) => {
                                let _ = tx.send(Msg::Bt(Some(bt.radio_on)));
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
        wifi_radio: None,
        btn_bat: None,
        minuto_desenhado: u32::MAX,
        rede: EstadoRede::Desligado,
        essid: None,
        bus_cli: Rc::new(RefCell::new(None)),
        menu_cal: craft_tools::MenuCamada::novo("craft-calendario"),
        menu_power: craft_tools::MenuCamada::novo("craft-sessao"),
    }));
    // os ícones da barra nascem no tamanho do assento (16px — a unidade
    // visual da casa; o label Nerd nunca mais entra aqui)
    st.borrow().audio_img.set_pixel_size(16);
    st.borrow().mic_img.set_pixel_size(16);
    st.borrow().rede_img.set_pixel_size(16);
    st.borrow().bt_img.set_pixel_size(16);

    // E151 — ZERO VAZAMENTO DE TEMA GTK4 (a diretriz do dono: o seletor
    // roxo travado e o quadrado branco morrem pela RAIZ): nenhum botão
    // da barra fica com foco persistente (focus_on_click(false) +
    // can_focus(false)) — o contorno do tema nunca pinta; a reação é
    // EXCLUSIVAMENTE o :hover suave da pele da casa. A aplicação corre
    // sobre a árvore pronta no fim do build (apaga_foco_da_barra).

    // ── ESQUERDA (E149 — minimalista, a ordem do dono): o botão de
    //    apps com ÍCONE GTK de verdade + a palavra "Aplicativos" (sem
    //    siglas técnicas); o clique dispara o CRAFT-APPS (1.0-108 — A
    //    MESMA PORTA DA TECLA WINDOWS: o botão abria o fuzzel enquanto o
    //    W-d abria a grade visual do craft-apps — a evidência do rig
    //    1.0-107.3; a casa tem UMA gaveta, o fuzzel segue vivo para quem
    //    o quiser no terminal). As pílulas da mesa (`1 2 3 4`) e o
    //    título ativo SAÍRAM da barra: a troca de mesa é o
    //    scroll/atalhos W-1..4 do labwc, o título mora na moldura da
    //    própria janela — a barra fica LIMPA
    let btn_apps = botao_apps();
    esq.append(&btn_apps);

    // ── CENTRO (1.0-93): o relógio em HORÁRIO LOCAL (a ordem do dono,
    //    rig da 1.0-92: o epoch puro vestia UTC — o glib::DateTime
    //    now_local veste o fuso DO SISTEMA), o TEXTO nunca muda ao
    //    clicar (a cura A2 intacta), o CALENDÁRIO nasce em popover GTK4
    //    (a pele roxa/escuro da casa) EXCLUSIVAMENTE NO CLIQUE — o relógio é
    //    HORA/CALENDÁRIO (1.0-106: a central de era morreu sem
    //    substituto, nenhum notificador no caminho do clique)
    let btn_clock = gtk::Button::new();
    btn_clock.set_widget_name("clockbtn");
    btn_clock.set_has_frame(false);
    {
        let lbl = st.borrow().clock_label.clone();
        btn_clock.set_child(Some(&lbl));
    }
    // 1.0-107/108 — O TOOLTIP DO RELÓGIO MORRE (a diretriz §9: "remover o
    // tooltip redundante de calendário no hover (tooltip: false),
    // mantendo a abertura do calendário exclusivamente no clique") e
    // 1.0-108 — O HOVER MORRE JUNTO: nenhum EventControllerMotion mora
    // no relógio (nenhuma cortesia de 350ms, nenhum popover por
    // proximidade do ponteiro — o clique é o ÚNICO gesto que abre o
    // calendário; a pele do hover do theme.css segue como sempre)
    btn_clock.set_has_tooltip(false);
    // 1.0-93 — O CALENDÁRIO (a ordem do dono: o card roxo/escuro da
    // casa; 1.0-108 — EXCLUSIVAMENTE NO CLIQUE; 1.0-109 §2.1 — O CARD
    // VESTE A CAMADA: o popover de era era FILHO da superfície top da
    // barra — a gaveta do craft-apps (a MESMA camada top) que nascia
    // DEPOIS o cobria inteiro; a janela Overlay do MenuCamada nasce
    // SEMPRE acima, o conteúdo nasce UMA vez (o card é estático)
    {
        let cal = gtk::Calendar::new();
        let corpo = gtk::Box::new(gtk::Orientation::Vertical, 0);
        corpo.set_margin_top(8);
        corpo.set_margin_bottom(8);
        corpo.set_margin_start(8);
        corpo.set_margin_end(8);
        corpo.append(&cal);
        st.borrow().menu_cal.conteudo(&corpo);
    }
    // 1.0-106 — O ESQUERDO ABRE O CALENDÁRIO (a ordem do dono: o relógio é
    // HORA/CALENDÁRIO — a central de notificações morreu SEM substituto, o
    // card que já existia no clique do meio é PROMOVIDO ao esquerdo; o
    // `clicked` do próprio botão é o caminho de sempre, ZERO D-Bus no
    // caminho — nenhum notificador trava o clique)
    // 1.0-108: o clique é o ÚNICO gesto — o hover/enter de era
    // (o card que saltava ao encostar o mouse) morreu inteiro
    {
        let st = st.clone();
        let btn = btn_clock.clone();
        btn_clock.connect_clicked(move |_| {
            abre_calendario(&st, &btn);
        });
    }
    // UM gesture só para os botões do MEIO/DIREITO do relógio (a lição da
    // dock: dois GestureClick no mesmo widget disputam a sequência — e o
    // botão 1 é do `clicked`, nunca do gesture): o calendário é o ÚNICO
    // lado que resta — o meio abre/fecha e o direito acompanha (quem
    // esperava o DND de era tem o calendário no gesto de qualquer forma)
    {
        let st = st.clone();
        let btn = btn_clock.clone();
        clique_solto(&btn_clock, move |_botao| {
            abre_calendario(&st, &btn);
        });
    }
    centro.append(&btn_clock);

    // ── DIREITA (E147 — o contrato mouse-first: game → player → áudio →
    //    microfone (E151) → rede → bluetooth → bateria → sessão.
    //    1.0-109 §2.3 — OS TRÊS GRUPOS LIDOS DE LONGE (a diretriz: Mídia
    //    (game+player) · Hardware (áudio/microfone/rede/bluetooth/
    //    bateria) · Sessão (⏻) separados CLARAMENTE pelo divisor sutil,
    //    padding UNIFORME entre os ícones de cada grupo — a faixa lê em
    //    grupos, não em 8 ícones soltos)) ──
    {
        let s = st.borrow();
        let btn_game = s.btn_game.clone();
        let btn_player = s.btn_player.clone();
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
        // 1.0-105 — o ESQUERDO pelo `clicked` (o painel do jogo); o
        // DIREITO no gesture (desliga na hora)
        btn_game.connect_clicked(move |_| {
            solta(&["craft-game", "menu"]);
        });
        clique_solto(&btn_game, move |botao| {
            if botao == 3 {
                solta(&["craft-game", "off"]);
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
        // 1.0-105 — o ESQUERDO (Play/Pause) pelo `clicked`; o MEIO/DIREITO
        // seguem no gesture (próxima faixa / focar o player)
        {
            let bus = st.borrow().bus_cli.clone();
            btn_player.connect_clicked(move |_| {
                pede_bus(&bus, elite_core::MediaCmd::PlayPause);
            });
        }
        {
            let bus = st.borrow().bus_cli.clone();
            clique_solto(&btn_player, move |botao| {
                let verbo = match botao {
                    2 => elite_core::MediaCmd::Next,
                    3 => elite_core::MediaCmd::Focus,
                    _ => return,
                };
                pede_bus(&bus, verbo);
            });
        }
        {
            let bus = st.borrow().bus_cli.clone();
            // 1.0-109 §2.2 — O SCROLL COM DEBOUNCE DE 250ms (a diretriz:
            // o gesto do trackpad/roda dispara VÁRIOS eventos no mesmo
            // toque — sem o freio a faixa saltava em DOBRO; o Instant
            // segura o segundo salto dentro da janela)
            let ultimo = std::rc::Rc::new(std::cell::Cell::new(
                std::time::Instant::now() - std::time::Duration::from_secs(10),
            ));
            scroll(&btn_player, move |dy| {
                let agora = std::time::Instant::now();
                if agora.duration_since(ultimo.get()) < std::time::Duration::from_millis(250) {
                    return; // o eco do MESMO gesto — o debounce come
                }
                ultimo.set(agora);
                // a diretriz: scroll para CIMA (dy<0) = PRÓXIMA faixa ·
                // para BAIXO (dy>0) = faixa ANTERIOR
                pede_bus(&bus, if dy < 0.0 {
                    elite_core::MediaCmd::Next
                } else {
                    elite_core::MediaCmd::Previous
                });
            });
        }
        dir.append(&btn_player);

        // 1.0-109 §2.2 — O PILL ÚNICO (a diretriz: ZERO botões extras —
        // o ⏭ avulso de era ocupava a faixa sem botão de retroceder; o
        // scroll do PRÓPRIO pill veste a faixa: cima = próxima, baixo =
        // anterior, com o DEBOUNCE de 250ms que mata o salto duplo do
        // gesto — os controles vivem TODOS no próprio pill).

        // 1.0-109 §2.3 — O DIVISOR ENTRE MÍDIA E HARDWARE (o grupo da
        // direita nasce: o divisor sutil separa os pílulas (game/mídia)
        // dos ícones de máquina (🔊 🎙 🌐 ᛒ / bateria) — o padding dos
        // ícones segue UNIFORME dentro de cada grupo)
        dir.append(&separa_grupo());

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
        // 1.0-105 — o ESQUERDO (o mixer dedicado) pelo `clicked`; o
        // DIREITO (mudo da saída) segue no gesture
        {
            btn_audio.connect_clicked(move |_| {
                abre_mixer();
            });
        }
        {
            let tx = tx.clone();
            clique_solto(&btn_audio, move |botao| if botao == 3 {
                solta(&["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                pede_audio_detalhe(&tx);
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
        // 1.0-105 — idem do áudio: o ESQUERDO (o mixer, aba de
        // entrada) pelo `clicked`; o DIREITO (mudo do mic) no gesture
        {
            btn_mic.connect_clicked(move |_| {
                abre_mixer();
            });
        }
        {
            let tx = tx.clone();
            clique_solto(&btn_mic, move |botao| if botao == 3 {
                solta(&["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
                pede_audio_detalhe(&tx);
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
        // Wi-Fi/Desligado com ÍCONE GTK SEMPRE). 1.0-106 — O ESQUERDO É
        // O SELETOR RÁPIDO DA CASA (a ordem do dono, rig da dose: o
        // clique abria o EDITOR inteiro para trocar de rede — o
        // craft-pick escuro com os toggles no início, as redes ao
        // alcance com sinal e status, o editor no fim; a conexão em 1
        // CLIQUE pelo nmcli). O MEIO abre o editor completo (o antigo
        // esquerdo). O DIREITO alterna a CONEXÃO ATIVA do momento:
        // `nmcli networking on/off` quando o cabo é o caminho, o rádio
        // Wi-Fi quando é o sem fio (o estado é o da própria foto — o
        // dreno re-veste o ícone/tooltip no frame seguinte ao gesto).
        btn_rede.set_has_frame(false);
        btn_rede.set_child(Some(&rede_img));
        btn_rede.set_tooltip_text(Some(
            "Rede — clique: seletor rápido · meio: editor de conexões · direito: ligar/desligar a conexão ativa",
        ));
        {
            let tx = tx.clone();
            btn_rede.connect_clicked(move |_| {
                // 1.0-106 — O SELETOR RÁPIDO na thread própria (o
                // craft-pick é modal — a barra NUNCA bloqueia no gesto;
                // o fallback honesto é o nm-connection-editor)
                let tx = tx.clone();
                std::thread::spawn(move || {
                    // 1.0-109 — o esquerdo abre o CRAFT-NET (o seletor
                    // de 1 clique da diretriz: as redes Wi-Fi próximas
                    // com sinal/cadeado, a conexão com 1 clique e a
                    // senha em diálogo limpo); a foto renasce no gesto
                    solta(&["craft-net"]);
                    pede_rede_foto(&tx);
                });
            });
        }
        clique_solto(&btn_rede, {
            // 1.0-108 — A LEI DA CONEXÃO PRINCIPAL (a evidência do rig
            // 1.0-107.3: o direito de era derrubava o Networking INTEIRO
            // com `nmcli networking off` — o enp7s0 ficava "não
            // disponível" SEM volta, o rádio Wi-Fi junto no escuro; a
            // ordem do dono, palavra por palavra: priorizar ethernet
            // sobre wifi, guardar o par (DEVICE, CONNECTION) no
            // last-net.state e desconectar SÓ a principal pelo `nmcli
            // device disconnect` — NUNCA `ip link set down`); na volta o
            // par guardado (ou a ethernet com cabo, senão o wifi) sobe
            // com `ip link set up` + `nmcli device set managed yes` +
            // `nmcli connection up` / `nmcli device connect`. A resposta
            // é o gesto: o dreno re-veste no frame seguinte.
            let tx = tx.clone();
            move |botao| if botao == 3 {
                let tx = tx.clone();
                std::thread::spawn(move || {
                    alterna_conexao_principal();
                    pede_rede_foto(&tx);
                });
            } else if botao == 2 {
                // o antigo esquerdo: o editor COMPLETO do NetworkManager
                solta(&["nm-connection-editor"]);
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
            // 1.0-105 — o ESQUERDO (blueman-manager) pelo `clicked` do
            // próprio botão; o DIREITO (power) segue no gesture
            btn_bt.connect_clicked(move |_| {
                if std::path::Path::new("/usr/bin/blueman-manager").exists() {
                    solta(&["blueman-manager"]);
                } else {
                    log("bluetooth: blueman-manager ausente — o pacote chega pelo elite-update (a cura da casa)");
                }
            });
        }
        {
            let tx = tx.clone();
            clique_solto(&btn_bt, move |botao| if botao == 3 {
                let tx = tx.clone();
                std::thread::spawn(move || {
                    let ligado = um_longo("bluetoothctl", &["show"]).map(|t| bt_ligado(&t));
                    if let Some(on) = ligado {
                        let cmd = if on { "off" } else { "on" };
                        solta(&["bluetoothctl", "power", cmd]);
                        let _ = tx.send(Msg::Bt(Some(!on)));
                    }
                });
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
        // 1.0-105 — o ESQUERDO pelo `clicked` (o resumo falado da bateria)
        btn_bat.connect_clicked(move |_| {
            solta(&["craft-bat"]);
        });
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

    // 1.0-109 §2.3 — O DIVISOR ENTRE HARDWARE E SESSÃO (o último grupo
    //    da faixa: o ⏻ da sessão lê-se DE LONGE, separado da máquina)
    dir.append(&separa_grupo());

    // ── A SESSÃO (a cura A5: sem fuzzel, sem can-suspend). E147: o
    //    ícone é Image de ÍCONE (system-shutdown — nunca mais codepoint
    //    Nerd no label). 1.0-109 §2.1 — O MENU VESTE A CAMADA: o
    //    MenuButton/PopoverMenu de era era FILHO da superfície top da
    //    barra — a gaveta do craft-apps (a MESMA camada top) que nascia
    //    DEPOIS o cobria inteiro; o menu agora é a janela Overlay do
    //    MenuCamada (SEMPRE acima, o clique no ⏻ é o toggle de sempre)
    //    e o CARDÁPIO nasce UMA vez (o conteúdo é estático) ─────────
    // 1.0-108 — OS ATALHOS RÁPIDOS NO TOPO (a ordem do dono: Modo de
    //    jogo, Auto-suspensão, Monitores/120 Hz, Atualizar, Limpar e
    //    Snapshots ganham PORTA DIRETA no menu — os essenciais de 1
    //    clique, sem terminal e sem gaveta no caminho)
    let btn_power = gtk::Button::new();
    btn_power.set_widget_name("powerbtn");
    btn_power.set_has_frame(false);
    {
        let img = gtk::Image::from_icon_name("system-shutdown-symbolic");
        img.set_pixel_size(16);
        btn_power.set_child(Some(&img));
    }
    btn_power.set_tooltip_text(Some("Sessão — Bloquear / Suspender / Reiniciar / Desligar / Encerrar"));
    // o CARDÁPIO nasce UMA vez na janela própria (o clone do RefCell
    // morre no mesmo fôlego — o borrow de dentro nunca disputa o de fora)
    let menu_sessao = st.borrow().menu_power.clone();
    menu_sessao.conteudo(&monta_menu_sessao(&menu_sessao));
    {
        let st = st.clone();
        let btn = btn_power.clone();
        btn_power.connect_clicked(move |_| {
            // a mãe mora no TOPO: o menu desce ABAIXO do ⏻
            st.borrow().menu_power.alterna(&btn, false);
        });
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

    // 1.0-109 §2.1 — O CLIQUE FORA QUE NÃO É ENGOLIDO: o press em
    // QUALQUER filho da barra fecha os menus de camada ANTES do botão
    // agir — o gesto mora na JANELA em fase de CAPTURA (vê o press
    // primeiro, de cima para baixo) e NUNCA reclama a sequência: o
    // botão embaixo recebe o MESMO evento (o clique destinado ao ícone
    // passa DIRETO, o menu desce no MESMO instante).
    {
        let st = st.clone();
        let gesto_fora = gtk::GestureClick::new();
        gesto_fora.set_button(0);
        gesto_fora.set_propagation_phase(gtk::PropagationPhase::Capture);
        gesto_fora.connect_pressed(move |_g, _n, _x, _y| {
            let cal = st.borrow().menu_cal.aberto();
            let power = st.borrow().menu_power.aberto();
            if cal || power {
                let s = st.borrow();
                s.menu_cal.fecha();
                s.menu_power.fecha();
                drop(s);
                crate::log("menus da barra desceram pelo clique na mãe (o clique do ícone segue — nada é engolido)");
            }
        });
        window.add_controller(gesto_fora);
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
         relógio HORA/CALENDÁRIO (o clique abre o calendário — zero notificador no caminho) · \
         apps no CRAFT-APPS (a gaveta da tecla Windows) · rede com SELETOR rápido (craft-pick) + editor no meio · \
         Bluetooth vestindo o fio do daemon + o belt próprio · relógio pt_BR + calendário · \
         MPRIS/jogo PELO FIO DO BUS"
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

/// Roda PARA SEMPRE: a foto 0 NA HORA (rede + bluetooth — o estado
/// inicial nunca mente) · áudio 2s · rede 5s · bluetooth 10s · cinto
/// 30s. Bloquear AQUI é de graça (a UI segue viva — a thread é dona
/// dos subprocessos, nunca do GTK). O bluetooth também veste o FIO do
/// daemon (1.0-106: o Powered do BlueZ consultado no arranque); este
/// belt é a rede de segurança.
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
    // 1.0-106 — O FRAME 0 NÃO MENTE: a PRIMEIRA foto de rede e bluetooth
    // sai NA HORA (a bandeira vale UM giro — o estado inicial mentiroso
    // do rig, ícone cortado com o adaptador ligado, morre aqui; o
    // bluetooth do fio do daemon é o complemento no frame 0 do bus)
    let mut primeira_foto = true;
    loop {
        if t_audio.elapsed() >= Duration::from_secs(POLL_AUDIO_S) {
            t_audio = Instant::now();
            let _ = tx.send(Msg::AudioDet(foto_audio()));
        }
        if primeira_foto || t_rede.elapsed() >= Duration::from_secs(POLL_REDE_S) {
            t_rede = Instant::now();
            if let Some(t) = um_longo(
                "nmcli",
                &["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"],
            ) {
                let radio = um_longo("nmcli", &["radio", "wifi"])
                    .and_then(|r| parse_wifi_radio(&r));
                let _ = tx.send(Msg::Rede(estado_rede_nmcli(&t), essid_nmcli(&t), radio));
            }
        }
        if primeira_foto || t_bt.elapsed() >= Duration::from_secs(POLL_BT_S) {
            t_bt = Instant::now();
            let _ = tx.send(Msg::Bt(
                um_longo("bluetoothctl", &["show"]).map(|t| bt_ligado(&t)),
            ));
        }
        if primeira_foto {
            primeira_foto = false;
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

// ── 1.0-109 — O SELETOR DE 1 CLIQUE É O CRAFT-NET (a diretriz) ────────
//      A evidência do dump 1.0-108: o clique esquerdo no ícone de Rede
//      não executava AÇÃO nenhuma e o seletor de era (craft-pick com
//      toggles abstratos) não listava as redes Wi-Fi próximas com 1
//      clique como o Bluetooth. O esquerdo agora abre o craft-net (o
//      seletor nativo com sinal/cadeado/marca de conectada, a conexão
//      em 1 clique e a senha em diálogo limpo); a LEI DA CONEXÃO
//      PRINCIPAL desceu para a FUNDAÇÃO (elite_core::rede — o direito
//      daqui de baixo veste o MESMO julgamento).

// ── 1.0-108 — A LEI DA CONEXÃO PRINCIPAL (o direito da rede) ───────────

/// O CAMINHO do last-net.state (o tmpfs da sessão — o par que volta a
/// viver no clique seguinte; o mesmo endereço da diretriz do dono).
fn last_net_path() -> std::path::PathBuf {
    let dir = std::env::var("XDG_RUNTIME_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| std::path::PathBuf::from("/tmp"));
    dir.join("elite/last-net.state")
}

/// O RELIGAR DA CONEXÃO PRINCIPAL (o caminho da ordem do dono, palavra
/// por palavra): o par do last-net.state (ou a ETHERNET com cabo, senão
/// a Wi-Fi — `dev_para_religar` julga no papel vivo) volta com o link DE
/// PÉ (`ip link set up`, best-effort — o polkit do rig decide), o
/// dispositivo DEVOLVIDO ao NetworkManager (`managed yes`) e a conexão
/// SALVA em cena (`nmcli connection up`) com a queda honesta para o
/// `nmcli device connect` quando o papel não casa mais.
fn religa_conexao_principal(foto: &str) {
    let last = std::fs::read_to_string(last_net_path())
        .ok()
        .and_then(|t| elite_core::rede::le_last_net(&t));
    let Some(dev) = elite_core::rede::dev_para_religar(foto, last.clone()) else {
        return; // nada a religar no hardware (honesto, sem gesto fantasma)
    };
    // o link DE PÉ (best-effort: sem root o nmcli abaixo ainda levanta)
    let _ = Command::new("ip")
        .args(["link", "set", &dev, "up"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    // o dispositivo VOLTA ao NetworkManager (o "não disponível" de era
    // morre: o manager é o dono do link)
    let _ = Command::new("nmcli")
        .args(["device", "set", &dev, "managed", "yes"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    // a conexão SALVA primeiro; sem papel casa, o device cru
    if let Some((_, con)) = last {
        if !con.is_empty() {
            let ok = Command::new("nmcli")
                .args(["connection", "up"])
                .arg(&con)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false);
            if ok {
                return;
            }
        }
    }
    let _ = Command::new("nmcli")
        .args(["device", "connect"])
        .arg(&dev)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// O DERRUBAR/RELIGAR DA CONEXÃO PRINCIPAL (a ethernet vence — a lei da
/// dose): a principal VIVA cai com o par GUARDADO no last-net.state e o
/// `nmcli device disconnect` (NUNCA `ip link set down` — o link do driver
/// não é do dono); SEM principal viva o mesmo clique RELIGA (o toggle de
/// 1 clique que o dono pediu — o estado de era "não disponível" sem
/// volta morre por desenho).
fn alterna_conexao_principal() {
    let Some(foto) = um_longo(
        "nmcli",
        &["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"],
    ) else {
        return; // nmcli calado: nada a julgar (o silêncio é honesto)
    };
    match elite_core::rede::conexao_principal(&foto) {
        Some((dev, con)) => {
            // o par fica no papel ANTES da queda (o clique seguinte tem
            // a quem chamar de volta mesmo com o status mudado)
            let caminho = last_net_path();
            if let Some(pai) = caminho.parent() {
                let _ = std::fs::create_dir_all(pai);
            }
            let _ = std::fs::write(&caminho, elite_core::rede::conteudo_last_net(&dev, &con));
            let _ = Command::new("nmcli")
                .args(["device", "disconnect"])
                .arg(&dev)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        }
        None => religa_conexao_principal(&foto),
    }
}

/// O CALENDÁRIO do relógio: o card que já existia no clique do meio
/// PROMOVIDO ao clique esquerdo (1.0-106 — o relógio é HORA/CALENDÁRIO,
/// nenhum notificador no caminho: o clique é TODO do GTK, zero D-Bus,
/// zero timeout — o card abre/fecha no MESMO instante do gesto).
/// 1.0-109 §2.1 — O CARD VESTE A CAMADA (a diretriz: a janela Overlay
/// nasce SEMPRE acima da gaveta top do craft-apps; o popover de era era
/// FILHO da superfície top da barra e a gaveta o cobria inteiro): o
/// clique é o TOGGLE de sempre — aberto FECHA, fechado ABRE ABAIXO do
/// relógio.
fn abre_calendario(st: &Rc<RefCell<State>>, btn: &gtk::Button) {
    st.borrow().menu_cal.alterna(btn, false); // a mãe mora no TOPO: o card desce
}

/// 1.0-109 §2.1 — O CARDÁPIO DA SESSÃO (a diretriz: o menu do ⏻ veste
/// a camada Overlay — SEMPRE acima da gaveta; o MenuButton/PopoverMenu
/// de era era FILHO da superfície top e a gaveta o cobria inteiro): os
/// ATALHOS RÁPIDOS de 1 clique no topo (1.0-108, a ordem do dono — com
/// o rótulo CURTO Auto-suspensão de 14 caracteres do §2.3), a sessão
/// no meio e a máquina embaixo — os mesmos verbos de sempre na pele
/// #menuwin da folha mestra.
fn monta_menu_sessao(menu: &craft_tools::MenuCamada) -> gtk::Box {
    let corpo = gtk::Box::new(gtk::Orientation::Vertical, 2);
    corpo.set_margin_top(4);
    corpo.set_margin_bottom(4);
    for (rotulo, argv) in [
        ("Modo de jogo", &["craft-game", "menu"][..]),
        ("Auto-suspensão", &["craft-idle", "menu"][..]),
        ("Monitores (120 Hz)", &["wdisplays"][..]),
        ("Atualizar sistema", &["craft-update"][..]),
        ("Limpar sistema", &["craft-clean"][..]),
        ("Snapshots (Rollback)", &["craft-rollback"][..]),
    ] {
        corpo.append(&linha_menu_bar(rotulo, argv, menu));
    }
    corpo.append(&separa_menu());
    // o sono pelo CRAFT-SUSPEND (1.0-108: o lock MAPEADO antes do
    // freeze — a superfície pintada ANTES do systemctl)
    for (rotulo, argv) in [
        ("Bloquear tela", &["craft-lock"][..]),
        ("Suspender", &["craft-suspend"][..]),
    ] {
        corpo.append(&linha_menu_bar(rotulo, argv, menu));
    }
    corpo.append(&separa_menu());
    for (rotulo, argv) in [
        ("Reiniciar", &["systemctl", "reboot"][..]),
        ("Desligar", &["systemctl", "poweroff"][..]),
        // o encerrar ORDEIRO (a família cai em ordem antes do labwc
        // --exit: daemon → superfícies → agentes)
        ("Encerrar sessão", &["craft-logout"][..]),
    ] {
        corpo.append(&linha_menu_bar(rotulo, argv, menu));
    }
    corpo
}

/// a linha do cardápio da sessão (o verbo viaja no closure do clique —
/// a MESMA escola da dock: o rótulo à esquerda, a pele no #menuwin da
/// mestra; o verbo parte com o menu FECHADO, a diretriz §2.1).
fn linha_menu_bar(rotulo: &str, argv: &[&str], menu: &craft_tools::MenuCamada) -> gtk::Button {
    let btn = gtk::Button::new();
    let rot = gtk::Label::new(Some(rotulo));
    rot.set_halign(gtk::Align::Start);
    btn.set_child(Some(&rot));
    btn.set_has_frame(false);
    btn.set_hexpand(true);
    let menu = menu.clone();
    let argv: Vec<String> = argv.iter().map(|s| s.to_string()).collect();
    btn.connect_clicked(move |_| {
        menu.fecha(); // o verbo parte com o menu fechado (§2.1)
        let argv: Vec<&str> = argv.iter().map(|s| s.as_str()).collect();
        solta(&argv);
    });
    btn
}

/// 1.0-109 §2.1 — o divisor sutil entre os grupos do cardápio (a
/// mesma régua do §2.3: 1px na cor da borda — a pele mora no
/// `#menuwin separator` da mestra).
fn separa_menu() -> gtk::Separator {
    gtk::Separator::new(gtk::Orientation::Horizontal)
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
            // 1.0-101 (ícone de AÇÃO + "Título — Artista" ≤28; sem
            // player no bus o assento SAI — oculto 0px)
            // 1.0-109 §2.2 — O PILL ÚNICO (o ⏭ avulso de era MORREU: o
            // scroll/cique do PRÓPRIO pill veste a faixa inteira — uma
            // pílula só de mídia em cena)
            let s = st.borrow_mut();
            match m.as_ref().and_then(media_pill) {
                Some(pill) => {
                    s.player_img.set_icon_name(Some(pill.icone));
                    s.player_label.set_text(&pill.texto);
                    s.btn_player.set_tooltip_text(Some(&pill.tooltip));
                    s.btn_player.set_visible(true);
                }
                None => {
                    s.btn_player.set_visible(false);
                }
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
            "{:02}/{:02}/{} — clique: calendário · hover: calendário",
            agora.day_of_month(),
            agora.month(),
            agora.year()
        )));
        s.minuto_desenhado = m;
    }
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

/// 1.0-109 §2.3 — O DIVISOR SUTIL DOS GRUPOS DA FAIXA (a diretriz: Mídia
/// · Hardware · Sessão lidos DE LONGE como blocos — o separador vertical
/// de 1px na cor da borda da casa com o respiro dos 6px dos lados; o
/// padding dos ícones DENTRO de cada grupo segue uniforme, o divisor é
/// o único que respira — a pele `#barbox separator` da folha mestra).
fn separa_grupo() -> gtk::Separator {
    let sep = gtk::Separator::new(gtk::Orientation::Vertical);
    sep.set_valign(gtk::Align::Center);
    sep
}

/// E151 — A PÁLIDA DO FOCO (zero vazamento de tema GTK4): corre sobre
/// a árvore da barra e DESATIVA o foco persistente em TODO botão —
/// `focus_on_click(false)` (o clique não rouba a Banana do tema) e
/// `can_focus(false)` (o contorno `:focus` do tema externo nunca
/// pinta). O seletor roxo travado do menu de energia de era e o
/// quadrado branco do MenuButton `:checked` morreram aqui E no CSS
/// (1.0-109 §2.1: o ⏻ é BOTÃO PURO — nenhum ToggleButton por dentro,
/// o cardápio é a janela de camada). A barra reage EXCLUSIVAMENTE ao
/// `:hover`.
fn apaga_foco_da_barra(raiz: &gtk::Widget) {
    if let Ok(b) = raiz.clone().downcast::<gtk::Button>() {
        b.set_focus_on_click(false);
        b.set_can_focus(false);
    }
    // 1.0-109 §2.1: o MenuButton MORREU (o cardápio é a janela de
    // camada) — o downcast de era saiu com ele (nenhum menubutton na
    // árvore da barra)
    let mut c = raiz.first_child();
    while let Some(filho) = c {
        c = filho.next_sibling();
        apaga_foco_da_barra(&filho);
    }
}

/// E149 — O BOTÃO DE APPS (ícone GTK + palavra). 1.0-108 — O CLIQUE
/// DISPARA O CRAFT-APPS (a evidência do rig 1.0-107.3: o botão abria o
/// fuzzel enquanto a tecla Windows abria a grade visual do craft-apps —
/// a casa tem UMA gaveta; o fuzzel segue vivo como launcher de
/// terminal, a barra veste a MESMA porta da tecla Windows). O menu rápido do clique direito MORREU (as
/// ações dele moram no menu do desktop e no de energia — o dedupe da
/// diretriz). O alinhamento vive nos 28px da faixa: Box verticalmente
/// CENTRADO, ícone 16px e label sem margem própria (o padding da pele
/// manda — theme.css).
fn botao_apps() -> gtk::Button {
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
        "Aplicativos — clique: a grade de apps (a MESMA porta da tecla Windows)",
    ));
    {
        // 1.0-108 — O CRAFT-APPS pelo `clicked` DO PRÓPRIO BOTÃO (a
        // MESMA gaveta da tecla Windows — a evidência do rig: o botão
        // abria o fuzzel enquanto o W-d abria a grade visual; UMA casa,
        // UMA gaveta; o fuzzel segue vivo como launcher de terminal)
        btn.connect_clicked(move |_| {
            solta(&["craft-apps"]);
        });
    }
    btn
}

/// A LEI DO CLIQUE (a cura B1 + 1.0-105): o verbo do MEIO/DIREITO
/// dispara EXCLUSIVAMENTE no GestureClick::released com tolerância
/// de arrasto < 10px — nunca no press, nunca no clicked (o par
/// press×clicked era o duplo verbo). O ESQUERDO NÃO MORA AQUI: o
/// GtkButton consome o botão 1 no gesto INTERNO e emite `clicked` —
/// o esquerdo de toda a barra veste `connect_clicked` (o MESMO
/// caminho do botão Sessão de sempre; o gesture externo nunca via o
/// botão 1 e o clique esquerdo morria calado).
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
/// (o rig 1.0-94 fotografou 6 zumbis pendurados no pid da barra — o
/// Linux deixa o morto na tabela até ALGUÉM colher). A thread
/// dedicada é a coveira: spawn → wait — o exit status é colhido
/// ANTES do Child morrer no escopo.
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

