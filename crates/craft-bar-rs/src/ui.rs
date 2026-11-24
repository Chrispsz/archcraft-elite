// ELITE · craft-bar-rs — ui.rs (E140). A camada GTK4 + gtk4-layer-shell
// da top bar. Este módulo SÓ compila com a feature "gui" (exige o GTK
// dev do ambiente de build do pacote — o CI valida; o sandbox sem GTK
// compila/testa o NÚCLEO: state/main).
//
// O DESENHO (a diretriz do dossiê 1.0-88, item por item):
//   · A FAIXA: layer-shell ancorada Top+Left+Right (a largura é da
//     tela; a zona exclusiva automática reserva os 36px — as janelas
//     maximizadas NASCEM abaixo da barra, como o waybar fazia);
//   · A LEI DO CLIQUE (a cura B1, da licção da dock): TODO botão
//     dispara EXCLUSIVAMENTE no GestureClick::released com tolerância
//     de arrasto < 5px — o conflito press/release que obrigava a
//     "segurar" o clique morre por construção (a dock ligava o verbo
//     no pressed E no clicked: clique rápido = dois verbos no mesmo
//     segundo, o dock.log do dump provou);
//   · O DRAWER (a cura A1): o filho é NOSSO (Option<Child>), o toggle
//     é por pid com varredura /proc de cortesia (a gaveta do W-d, da
//     porta do craft-drawer, também conta) e o eco do clique morre no
//     debounce de 150ms do state.rs. O stderr da gaveta vai para
//     /dev/null: o spawn/SIGTERM a cada 1-2s do bars.log do dump era
//     o grito da era shell, não evidência de nada;
//   · O RELÓGIO (a cura A2): UM Label com a palavra pt_BR da casa
//     ("Seg, 23 Nov · 19:30") — não existe texto alternativo, não existe
//     texto que muda ao clicar. Esquerdo = painel do swaync, direito
//     = DND;
//   · OS FILHOS CURTOS: wpctl/nmcli/bluetoothctl/craft-* rodam numa
//     ÚNICA thread de fundo (a UI NUNCA bloqueia — a lei da casa
//     desde a E132) e chegam como Msg pelo canal mpsc;
//   · OS SINAIS DO DAEMON: SIGRTMIN+8 acende/apaga o pill do modo de
//     jogo (o elite-daemon avisa a transição — o polling de 3s da
//     era waybar morre), SIGRTMIN+9 refresca os 2º planos, SIGUSR2
//     relê o bar.css;
//   · A SESSÃO (a cura A5): MenuButton + PopoverMenu NATIVO com
//     Bloquear / Suspender / Reiniciar / Desligar / Encerrar sessão —
//     sem fuzzel, sem can-suspend (AllowSuspend=yes é a palavra do
//     sleep.conf da casa, E122; o `systemctl suspend` é a palavra
//     final — o busctl do dump devolvia vazio e o menu antigo
//     apanhava disso).
use crate::state::{
    bt_ligado, bgapps_contagem, dentro_janela_ms, essid_nmcli, estado_rede_nmcli, glifo_mic,
    glifo_rede, glifo_volume, json_text, le_bateria, media_pill, parse_wifi_list,
    parse_wifi_radio, parse_volume_wpctl, relogio_ptbr, tooltip_rede, RedeWifi, EstadoRede,
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
    /// (volume, mudo) do sink padrão (None = wpctl engasgado — o
    /// estado anterior CONSERVADO, a barra não pisca no vácuo).
    Audio(Option<(f64, bool)>),
    /// (volume, mudo) da fonte padrão (o microfone).
    Mic(Option<(f64, bool)>),
    /// (estado, essid) da rede — o assento é PERSISTENTE por desenho.
    Rede(EstadoRede, Option<String>),
    /// Powered do adaptador (None = bluetoothctl ausente/sem adaptador).
    Bt(Option<bool>),
    /// (texto, tooltip) do player — None = o pill SAI da barra.
    Player(Option<(String, Option<String>)>),
    /// O texto do pill do modo de jogo — None = apagado.
    Game(Option<String>),
    /// O texto dos 2º planos — None = apagado.
    Bgapps(Option<String>),
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

/// A barra inteira (os widgets que mudam + o filho do drawer).
struct State {
    clock_label: gtk::Label,
    btn_audio: gtk::Button,
    btn_mic: gtk::Button,
    btn_rede: gtk::Button,
    btn_bt: gtk::Button,
    btn_game: gtk::Button,
    btn_player: gtk::Button,
    player_label: gtk::Label,
    btn_bat: Option<gtk::Button>,
    btn_bgapps: gtk::Button,
    /// 1.0-93 — o rótulo do nº de 2º planos (o ícone é GTK de verdade)
    bgapps_lbl: gtk::Label,
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
    let app = gtk::Application::new(Some("elite.craft.Bar"), Default::default());
    app.connect_activate(|app| build(app));
    app.run().get() as i32
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
    // o frame 0 do jogo/2º-planos: thread curta própria (o arranque
    // do daemon pode demorar um instante — 300ms de cortesia)
    std::thread::spawn({
        let tx = tx.clone();
        move || {
            std::thread::sleep(Duration::from_millis(300));
            if let Some(t) = um_longo("craft-game", &["pill"]) {
                let _ = tx.send(Msg::Game(json_text(&t)));
            }
            if let Some(t) = um_longo("craft-bgapps", &["status"]) {
                let _ = tx.send(Msg::Bgapps(json_text(&t)));
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
        btn_mic: gtk::Button::new(),
        btn_rede: gtk::Button::new(),
        btn_bt: gtk::Button::new(),
        btn_game: gtk::Button::new(),
        btn_player: gtk::Button::new(),
        player_label: gtk::Label::new(None),
        btn_bat: None,
        btn_bgapps: gtk::Button::new(),
        bgapps_lbl: gtk::Label::new(None),
        rede_lista: gtk::Box::new(gtk::Orientation::Vertical, 4),
        rede_switch: gtk::Switch::new(),
        drawer: None,
        drawer_ns: 0,
        minuto_desenhado: u32::MAX,
        rede: EstadoRede::Desligado,
        essid: None,
        bus_cli: Rc::new(RefCell::new(None)),
    }));

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
        let pop = pop_cal.clone();
        let mostrar = Rc::new(Cell::new(true));
        let motion = gtk::EventControllerMotion::new();
        motion.connect_enter(move |_, _, _| {
            let pop = pop.clone();
            let mostrar = mostrar.clone();
            mostrar.set(true);
            // UMA vez (once — o timer de repetição acumularia a cada
            // entrada; a cortesia é única)
            glib::timeout_add_local_once(Duration::from_millis(350), move || {
                if mostrar.get() {
                    pop.popup();
                }
            });
        });
        {
            let pop = pop.clone();
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

    // ── DIREITA: game → player → áudio → mic → bateria → rede →
    //    bluetooth → 2º planos → sessão ──────────────────────────────
    {
        let s = st.borrow();
        let btn_game = s.btn_game.clone();
        let btn_player = s.btn_player.clone();
        let player_label = s.player_label.clone();
        let btn_audio = s.btn_audio.clone();
        let btn_mic = s.btn_mic.clone();
        let btn_rede = s.btn_rede.clone();
        let btn_bt = s.btn_bt.clone();
        let btn_bgapps = s.btn_bgapps.clone();
        drop(s);

        // O MODO DE JOGO (E115/E126 intactos: o estado REAL do
        // GameMode no pill, clique DIREITO desliga na hora) — acende
        // no SIGRTMIN+8 que o elite-daemon manda na transição.
        btn_game.set_label("\u{f11b}");
        btn_game.set_has_frame(false);
        btn_game.set_visible(false);
        btn_game.set_tooltip_text(Some("Modo de jogo ativo — clique: central · direito: desligar"));
        clique_solto(&btn_game, move |botao| {
            if botao == 3 {
                solta(&["craft-game", "off"]);
            } else if botao == 1 {
                solta(&["craft-game"]);
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
        btn_player.set_tooltip_text(Some("Mídia — clique: play/pause · scroll: faixa · direito: focar o player"));
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

        // O ÁUDIO pelo wpctl (a cura A3: o mute é INSTANTÂNEO no
        // clique — nenhum menu de texto no caminho; o mixer de
        // verdade é o pwvucontrol no direito).
        btn_audio.set_has_frame(false);
        btn_audio.set_label("\u{f027}");
        btn_audio.set_tooltip_text(Some("Volume — clique: mudo · scroll: volume · direito: pwvucontrol"));
        {
            let tx = tx.clone();
            clique_solto(&btn_audio, move |botao| {
                if botao == 3 {
                    solta(&["pwvucontrol"]);
                } else if botao == 1 {
                    solta(&["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                    pede_audio(&tx); // a resposta é o gesto, não o belt
                }
            });
        }
        scroll(&btn_audio, move |dy| {
            let passo = if dy < 0.0 { "5%+" } else { "5%-" };
            solta(&["wpctl", "set-volume", "--limit", "1.5", "@DEFAULT_AUDIO_SINK@", passo]);
        });
        dir.append(&btn_audio);

        // O MICROFONE (a paridade v2.3.6: mudo instantâneo + realce
        // .muted quando mudo — a gramática vermelha da casa).
        btn_mic.set_has_frame(false);
        btn_mic.set_label("\u{f130}");
        btn_mic.set_tooltip_text(Some("Microfone — clique: mudo · direito: pwvucontrol"));
        {
            let tx = tx.clone();
            clique_solto(&btn_mic, move |botao| {
                if botao == 3 {
                    solta(&["pwvucontrol"]);
                } else if botao == 1 {
                    solta(&["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
                    pede_audio(&tx);
                }
            });
        }
        dir.append(&btn_mic);

        // A REDE PERSISTENTE (a cura A4: o botão NÃO EXISTE a estado
        // "sumido" — Cabo/Wi-Fi/Desligado, SEMPRE um glifo e um
        // clique que abre ferramenta DE VERDADE).
        // 1.0-93 — O SELETOR RÁPIDO (a ordem do dono): clique esquerdo
        // abre um POPOVER GTK4 — toggle Wi-Fi (Switch), redes ao
        // alcance para conectar DIRETO, status do cabo; o
        // nm-connection-editor fica como botão AVANÇADO opcional (o
        // clique direito segue direto nele)
        btn_rede.set_has_frame(false);
        btn_rede.set_label(glifo_rede(EstadoRede::Desligado));
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

        // O BLUETOOTH DEDICADO (a diretriz: o gerenciador gráfico de
        // verdade — o blueman-manager, que a dose adota; a barra só
        // mostra o estado e abre a porta).
        btn_bt.set_has_frame(false);
        btn_bt.set_label("\u{f293}");
        btn_bt.set_tooltip_text(Some("Bluetooth — clique: blueman"));
        clique_solto(&btn_bt, move |botao| {
            if botao == 1 {
                solta(&["blueman-manager"]);
            }
        });
        dir.append(&btn_bt);

        // OS 2º PLANOS (o evento E135: o elite-daemon manda o
        // SIGRTMIN+9 no NameOwnerChanged; o belt de 30s é a rede).
        // 1.0-93 — O GLIFO QUEBRADO '\uf085' SAI: o ícone é GTK DE
        // VERDADE (system-run-symbolic) com tooltip descritivo e o
        // rótulo fica com a CONTAGEM limpa; o clique abre o menu dos
        // apps em 2º plano (o popover da lista viva)
        btn_bgapps.set_widget_name("bgappsbtn");
        btn_bgapps.set_has_frame(false);
        btn_bgapps.set_visible(false);
        {
            let s = st.borrow();
            let img = gtk::Image::from_icon_name("system-run-symbolic");
            img.set_pixel_size(16);
            let linha = gtk::Box::new(gtk::Orientation::Horizontal, 5);
            linha.append(&img);
            linha.append(&s.bgapps_lbl.clone());
            drop(s);
            btn_bgapps.set_child(Some(&linha));
        }
        btn_bgapps.set_tooltip_text(Some("Aplicativos em segundo plano — clique: a lista"));
        clique_solto(&btn_bgapps, move |botao| {
            if botao == 1 {
                solta(&["craft-bgapps", "menu"]);
            }
        });
        dir.append(&btn_bgapps);
    }

    // A BATERIA (só quando EXISTE — desktop não paga o assento): o
    // frame 0 já nasce cheio, o belt de 30s renova pelo /sys (sem
    // fork nenhum — o /sys é barato).
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
        if let Some((cap, carregando)) = le_bateria(std::path::Path::new("/sys/class/power_supply/BAT0")) {
            btn_bat.set_label(&format!(
                "{}% {}",
                cap,
                if carregando { "\u{f0e7}" } else { "\u{f240}" }
            ));
        }
        dir.append(&btn_bat);
        st.borrow_mut().btn_bat = Some(btn_bat);
    }

    // ── A SESSÃO em popover NATIVO (a cura A5: sem fuzzel, sem
    //    can-suspend — o MenuButton é o par canônico do PopoverMenu;
    //    o clique/dismiss é TODO do GTK, zero gesture nosso aqui) ────
    let btn_power = gtk::MenuButton::new();
    btn_power.set_widget_name("powerbtn");
    btn_power.set_label("\u{f011}");
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

    // os SINAIS da casa (SIGRTMIN+8 jogo · +9 2º planos · SIGUSR2 CSS)
    unsafe {
        libc::signal(libc::SIGRTMIN() + 8, on_signal as libc::sighandler_t);
        libc::signal(libc::SIGRTMIN() + 9, on_signal as libc::sighandler_t);
        libc::signal(libc::SIGUSR2, on_signal as libc::sighandler_t);
    }

    load_css();
    desenha_relogio(&st); // o frame 0 já nasce com a hora certa
    window.show();

    log(&format!(
        "craft-bar-rs {VERSION} no ar: relógio pt_BR LOCAL no CenterBox · calendário no \
         hover · áudio/mic wpctl · seletor de rede em popover · bluetooth blueman · \
         sessão popover nativo · MPRIS/jogo PELO FIO DO BUS · SIGRTMIN+8/+9 do \
         daemon (o cinto) · clique EXCLUSIVAMENTE no released com tolerância \
         de 5px (a cura do press×click da dock, E140)"
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
            // bateria ido — cada lado é julgado sozinho)
            let bat = le_bateria(std::path::Path::new("/sys/class/power_supply/BAT0"));
            if let (Some(btn), Some((cap, carregando))) = (st.borrow().btn_bat.clone(), bat) {
                btn.set_label(&format!(
                    "{}% {}",
                    cap,
                    if carregando { "\u{f0e7}" } else { "\u{f240}" }
                ));
            }
            glib::ControlFlow::Continue
        });
    }
}

// ── a THREAD DE FUNDO (os filhos curtos nas cadências belt) ───────────

/// Roda PARA SEMPRE: player 1s · áudio/mic 2s · rede 5s · bluetooth
/// 10s · cinto 30s. Bloquear AQUI é de graça (a UI segue viva — a
/// thread é dona dos subprocessos, nunca do GTK).
fn poller(tx: Sender<Msg>) {
    // 2.0 — O PLAYER NÃO MORA MAIS AQUI: o MPRIS chega pelo fio do bus
    // (o daemon escuta o PropertiesChanged — o polling de 1s do
    // craft-player morreu com o playerctl); aqui ficam os belts que
    // NÃO têm evento ainda (áudio/mic/rede/bluetooth + o cinto do
    // jogo/2º-planos — os EVENTOS seguem sendo donos do reflexo)
    let mut t_audio = Instant::now();
    let mut t_rede = Instant::now();
    let mut t_bt = Instant::now();
    let mut t_cinto = Instant::now();
    loop {
        if t_audio.elapsed() >= Duration::from_secs(POLL_AUDIO_S) {
            t_audio = Instant::now();
            let _ = tx.send(Msg::Audio(
                um_longo("wpctl", &["get-volume", "@DEFAULT_AUDIO_SINK@"])
                    .and_then(|t| parse_volume_wpctl(&t)),
            ));
            let _ = tx.send(Msg::Mic(
                um_longo("wpctl", &["get-volume", "@DEFAULT_AUDIO_SOURCE@"])
                    .and_then(|t| parse_volume_wpctl(&t)),
            ));
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
            if let Some(t) = um_longo("craft-bgapps", &["status"]) {
                let _ = tx.send(Msg::Bgapps(json_text(&t)));
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

/// A UI pede o refresh de áudio/mic NA HORA (o clique de mute não
/// espera o belt de 2s — a resposta é o gesto; o belt é a rede).
fn pede_audio(tx: &Sender<Msg>) {
    let tx = tx.clone();
    std::thread::spawn(move || {
        let _ = tx.send(Msg::Audio(
            um_longo("wpctl", &["get-volume", "@DEFAULT_AUDIO_SINK@"])
                .and_then(|t| parse_volume_wpctl(&t)),
        ));
        let _ = tx.send(Msg::Mic(
            um_longo("wpctl", &["get-volume", "@DEFAULT_AUDIO_SOURCE@"])
                .and_then(|t| parse_volume_wpctl(&t)),
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
        let sig9 = libc::SIGRTMIN() + 9;
        if sig == sig8 {
            let tx = tx.clone();
            std::thread::spawn(move || {
                if let Some(t) = um_longo("craft-game", &["pill"]) {
                    let _ = tx.send(Msg::Game(json_text(&t)));
                }
            });
        } else if sig == sig9 {
            let tx = tx.clone();
            std::thread::spawn(move || {
                if let Some(t) = um_longo("craft-bgapps", &["status"]) {
                    let _ = tx.send(Msg::Bgapps(json_text(&t)));
                }
            });
        } else if sig == libc::SIGUSR2 {
            load_css();
            log("bar.css relido (SIGUSR2 — a pele da casa sem renascer)");
        }
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
        Msg::Audio(par) => {
            let s = st.borrow_mut();
            if let Some((v, m)) = par {
                s.btn_audio.set_label(glifo_volume(v, m));
                if m {
                    s.btn_audio.add_css_class("muted");
                } else {
                    s.btn_audio.remove_css_class("muted");
                }
                s.btn_audio.set_tooltip_text(Some(&format!(
                    "Volume {}%{} — clique: mudo · scroll: volume · direito: pwvucontrol",
                    (v * 100.0).round() as i64,
                    if m { " · MUDO" } else { "" }
                )));
            }
        }
        Msg::Mic(par) => {
            let s = st.borrow_mut();
            if let Some((v, m)) = par {
                s.btn_mic.set_label(glifo_mic(m));
                if m {
                    s.btn_mic.add_css_class("muted");
                } else {
                    s.btn_mic.remove_css_class("muted");
                }
                s.btn_mic.set_tooltip_text(Some(&format!(
                    "Microfone {}%{} — clique: mudo · direito: pwvucontrol",
                    (v * 100.0).round() as i64,
                    if m { " · MUDO" } else { "" }
                )));
            }
        }
        Msg::Rede(estado, essid) => {
            let mut s = st.borrow_mut();
            s.rede = estado;
            s.essid = essid.clone();
            s.btn_rede.set_label(glifo_rede(estado));
            s.btn_rede
                .set_tooltip_text(Some(&tooltip_rede(estado, essid.as_deref())));
        }
        Msg::Bt(estado) => {
            let s = st.borrow_mut();
            match estado {
                Some(true) => {
                    s.btn_bt.remove_css_class("off");
                    s.btn_bt.set_tooltip_text(Some("Bluetooth ligado — clique: blueman"));
                }
                Some(false) => {
                    s.btn_bt.add_css_class("off");
                    s.btn_bt.set_tooltip_text(Some("Bluetooth desligado — clique: blueman"));
                }
                None => {
                    s.btn_bt.add_css_class("off");
                    s.btn_bt.set_tooltip_text(Some("Sem adaptador Bluetooth"));
                }
            }
        }
        Msg::Player(dados) => {
            let s = st.borrow_mut();
            match dados {
                Some((txt, tip)) => {
                    s.player_label.set_text(&txt);
                    s.btn_player.set_tooltip_text(tip.as_deref());
                    s.btn_player.set_visible(true);
                }
                None => s.btn_player.set_visible(false),
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
        Msg::Bgapps(txt) => {
            let s = st.borrow_mut();
            match txt {
                Some(t) => {
                    // 1.0-93 — o '\uf085' quebrado já saiu no parse; o
                    // ícone GTK veste o botão e o rótulo é a contagem
                    // (a msg já vem com o "text" do JSON extraído)
                    s.bgapps_lbl.set_text(&bgapps_contagem(&t));
                    s.btn_bgapps.set_visible(true);
                }
                None => s.btn_bgapps.set_visible(false),
            }
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
            agora.day_of_month(),
            agora.month(),
            agora.hour(),
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

    // o AVANÇADO (o nm-connection-editor — a ferramenta completa)
    {
        let avancado = gtk::Button::with_label("Configurações avançadas");
        avancado.set_hexpand(true);
        avancado.set_tooltip_text(Some("Abrir o editor completo de conexões"));
        clique_solto(&avancado, move |botao| {
            if botao == 1 {
                solta(&["nm-connection-editor"]);
            }
        });
        corpo.append(&avancado);
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

fn solta(argv: &[&str]) {
    if argv.is_empty() {
        return;
    }
    let _ = Command::new(argv[0])
        .args(&argv[1..])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn();
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

