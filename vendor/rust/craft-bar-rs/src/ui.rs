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
    bt_ligado, civil_de_dias, dia_semana, dentro_janela_ms, estado_rede_nmcli, essid_nmcli,
    glifo_mic, glifo_rede, glifo_volume, json_text, json_tooltip, le_bateria, agora_epoch,
    parse_volume_wpctl, relogio_ptbr, tooltip_rede, EstadoRede,
};
use crate::{css_path, current_uid, log, VERSION};
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
// o ActionMap (o add_action do SimpleActionGroup) mora na RAIZ do gio
// (gio::ActionMap — o re-export do auto::action_map; NÃO está no prelude
// do gio 0.22 nem no gtk4::prelude — provado no Canal 45302713969)
use gtk4::gio::ActionMap;
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
/// EVENTOS do daemon chegam por sinal, o belt é a rede de segurança).
const POLL_PLAYER_S: u64 = 1;
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

    // O CORPO: esquerda (apps) · centro (relógio) · direita (status) —
    // o mesmo arranjo da era waybar (a convenção v2.0 da casa).
    let corpo = gtk::Box::new(gtk::Orientation::Horizontal, 4);
    corpo.set_widget_name("barbox");
    let esq = caixa_lateral(gtk::Align::Start);
    let centro = caixa_lateral(gtk::Align::Center);
    let dir = caixa_lateral(gtk::Align::End);
    corpo.append(&esq);
    corpo.append(&centro);
    corpo.append(&dir);
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
        drawer: None,
        drawer_ns: 0,
        minuto_desenhado: u32::MAX,
        rede: EstadoRede::Desligado,
        essid: None,
    }));

    // ── ESQUERDA: o ARCH que abre o Launchpad (o modelo menu-bar) ────
    let btn_apps = botao_glifo("\u{f303}", "Aplicativos (W-d)");
    {
        let st = st.clone();
        clique_solto(&btn_apps, move |botao| {
            if botao == 1 {
                toggle_drawer(&st);
            }
        });
    }
    esq.append(&btn_apps);

    // ── CENTRO: o relógio pt_BR que NUNCA muda de texto (a cura A2) ──
    let btn_clock = gtk::Button::new();
    btn_clock.set_widget_name("clockbtn");
    btn_clock.set_has_frame(false);
    {
        let lbl = st.borrow().clock_label.clone();
        btn_clock.set_child(Some(&lbl));
    }
    btn_clock.set_tooltip_text(Some("Notificações — clique: painel · direito: não perturbe"));
    {
        clique_solto(&btn_clock, move |botao| {
            // esquerdo: o painel (toggle SEM sequestrar o foco -sw);
            // direito: o DND. O TEXTO NÃO MUDA — o clique é ação, a
            // data é a data (a cura do "alterna o texto exibido").
            if botao == 1 {
                solta(&["swaync-client", "-t", "-sw"]);
            } else if botao == 3 {
                solta(&["swaync-client", "-d"]);
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

        // O PLAYER da casa (E124: o texto com o tempo da faixa; E122:
        // o juízo mensagem-não-é-mídia mora no craft-player).
        btn_player.set_widget_name("playerbtn");
        btn_player.set_has_frame(false);
        btn_player.set_child(Some(&player_label));
        btn_player.set_visible(false);
        clique_solto(&btn_player, move |botao| match botao {
            1 => solta(&["craft-player", "play-pause"]),
            2 => solta(&["craft-player", "next"]),
            3 => solta(&["craft-player", "previous"]),
            _ => {}
        });
        // o scroll do player: ↑ próxima · ↓ anterior (a era waybar)
        scroll(&btn_player, move |dy| {
            if dy < 0.0 {
                solta(&["craft-player", "next"]);
            } else {
                solta(&["craft-player", "previous"]);
            }
        });
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
        // clique que abre a ferramenta DE VERDADE).
        btn_rede.set_has_frame(false);
        btn_rede.set_label(glifo_rede(EstadoRede::Desligado));
        btn_rede.set_tooltip_text(Some("Sem conexão — clique: iwgtk (o botão nunca sai)"));
        clique_solto(&btn_rede, move |botao| match botao {
            1 => solta(&["iwgtk"]),
            3 => solta(&["nm-connection-editor"]),
            _ => {}
        });
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
        btn_bgapps.set_widget_name("bgappsbtn");
        btn_bgapps.set_has_frame(false);
        btn_bgapps.set_visible(false);
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
            let st = st.clone();
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
        "craft-bar-rs {VERSION} no ar: relógio pt_BR fixo · áudio/mic wpctl · \
         rede persistente (iwgtk/nm-connection-editor) · bluetooth blueman · \
         sessão popover nativo · SIGRTMIN+8/+9 do daemon ouvidos · clique \
         EXCLUSIVAMENTE no released com tolerância de 5px (a cura do \
         press×click da dock, E140)"
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
    let mut t_player = Instant::now();
    let mut t_audio = Instant::now();
    let mut t_rede = Instant::now();
    let mut t_bt = Instant::now();
    let mut t_cinto = Instant::now();
    loop {
        if t_player.elapsed() >= Duration::from_secs(POLL_PLAYER_S) {
            t_player = Instant::now();
            if let Some(t) = um_longo("craft-player", &["state"]) {
                let _ = tx.send(Msg::Player(
                    json_text(&t).map(|txt| (txt, json_tooltip(&t))),
                ));
            } else {
                let _ = tx.send(Msg::Player(None));
            }
        }
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
            let mut s = st.borrow_mut();
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
            let mut s = st.borrow_mut();
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
            let mut s = st.borrow_mut();
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
            let mut s = st.borrow_mut();
            match dados {
                Some((txt, tip)) => {
                    s.player_label.set_text(&txt);
                    s.btn_player.set_tooltip_text(tip.as_deref());
                    s.btn_player.set_visible(true);
                }
                None => s.btn_player.set_visible(false),
            }
        }
        Msg::Game(txt) => {
            let mut s = st.borrow_mut();
            s.btn_game.set_visible(txt.is_some());
        }
        Msg::Bgapps(txt) => {
            let mut s = st.borrow_mut();
            match txt {
                Some(t) => {
                    s.btn_bgapps.set_label(&t);
                    s.btn_bgapps.set_visible(true);
                }
                None => s.btn_bgapps.set_visible(false),
            }
        }
    }
}

// ── o RELÓGIO (a palavra pt_BR da casa, na virada do minuto) ───────────

fn desenha_relogio(st: &Rc<RefCell<State>>) {
    let ep = agora_epoch() as i64;
    let dias = ep.div_euclid(86_400);
    let seg_dia = ep.rem_euclid(86_400);
    let (h, m) = ((seg_dia / 3600) as u32, ((seg_dia % 3600) / 60) as u32);
    let (ano, mes, dia) = civil_de_dias(dias);
    let wd = dia_semana(dias);
    let mut s = st.borrow_mut();
    if s.minuto_desenhado != m {
        s.clock_label.set_text(&relogio_ptbr(wd, dia, mes, h, m));
        s.clock_label.set_tooltip_text(Some(&format!(
            "{:02}/{:02}/{} — clique: notificações · direito: não perturbe",
            dia, mes, ano
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

/// O botão-glifo da casa: sem moldura, com nome para o CSS e o
/// tooltip informado.
fn botao_glifo(glifo: &str, tooltip: &str) -> gtk::Button {
    let b = gtk::Button::new();
    b.set_label(glifo);
    b.set_has_frame(false);
    b.set_tooltip_text(Some(tooltip));
    b
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
            gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }
}

/// O fallback embutido (a cara escura da era waybar, na gramática
/// GTK4 — o glifo é JetBrainsMono NF, a família da casa; o fundo é a
/// faixa INTEIRA: a barra top do modelo menu-bar não é pílula).
const DEFAULT_CSS: &str = "
#barwindow { background: rgba(5, 5, 8, 0.92); }
#barbox { padding: 2px 10px; min-height: 34px; }
#barbox > button, #barbox > menubutton {
  background: transparent;
  border: none;
  border-radius: 8px;
  padding: 2px 9px;
  color: #cdd6f4;
  font-family: \"JetBrainsMono NF\", \"Symbols Nerd Font\", monospace;
  font-size: 15px;
}
#barbox button:hover, #barbox menubutton:hover {
  background: rgba(49, 50, 68, 0.95);
}
#barbox button:active, #barbox menubutton:active {
  background: rgba(88, 91, 112, 0.95);
}
#barbox button.muted { color: #f38ba8; }
#barbox button.off { color: #6c7086; }
#barbox #playerbtn label { color: #a6adc8; font-size: 13px; }
#barbox #clockbtn { font-weight: 600; }
";
