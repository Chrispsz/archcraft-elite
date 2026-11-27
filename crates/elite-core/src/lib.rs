// ═════════════════════════════════════════════════════════════════════════
// elite-core — os CONTRATOS da casa 2.0 (a fundação do workspace unificado)
// ═════════════════════════════════════════════════════════════════════════
// O único lugar onde o estado do desktop tem TIPO: os módulos gráficos
// (craft-bar-rs, craft-dock-rs), o elite-daemon e o craft-dump-rs falam
// a MESMA língua — AudioState, MediaState, NetworkState, BluetoothState,
// GameModeState, WindowInfo, WorkspaceInfo — pelo bus.sock da sessão
// (§elite-core::ipc), com persistência atômica em ~/.config/elite/
// (§elite-core::persist) e a pele única da casa (§THEME_CSS).
//
// Leis que este crate carrega:
//   · std-first: o núcleo compila e testa em QUALQUER lugar (o sandbox
//     sem gtk4 prova os contratos; a gui é feature dos módulos gráficos).
//   · serde + JSON no fio: novos campos são Option — a versão N+1 do
//     daemon nunca quebra a versão N da barra (o fio é lento o bastante).
//   · PT-BR nas faces do produto (L10) — os textos vivem nos módulos
//     gráficos; aqui só a estrutura.
// ═════════════════════════════════════════════════════════════════════════

pub mod bus;
pub mod ipc;
pub mod persist;
// 1.0-109 — A LEI DA REDE NA FUNDAÇÃO: o craft-net (o seletor de 1
// clique da diretriz) e o direito da top bar vestem o MESMO julgamento
// (a ethernet vence · o last-net.state guarda o par · a queda é o
// `nmcli device disconnect`, NUNCA `ip link set down`).
pub mod rede;

// a morada do estado do dono no contrato da raiz (os consumidores falam
// elite_core::elite_config_dir — o caminho é contrato, não detalhe)
pub use persist::elite_config_dir;

use serde::{Deserialize, Serialize};

/// A folha mestra única da casa (Design System ELITE).
/// Barra, dock e popovers embutem ESTE texto — uma pele só, zero drift.
pub const THEME_CSS: &str = include_str!("../assets/theme.css");

/// O caminho do bus da sessão: `/run/user/$UID/elite/bus.sock`.
/// O `ELITE_BUS_DIR` sobrepõe (testes e rigs fora do padrão XDG).
pub fn bus_dir(uid: u32) -> std::path::PathBuf {
    if let Ok(dir) = std::env::var("ELITE_BUS_DIR") {
        return std::path::PathBuf::from(dir);
    }
    let runtime = std::env::var("XDG_RUNTIME_DIR")
        .unwrap_or_else(|_| format!("/run/user/{uid}"));
    std::path::PathBuf::from(runtime).join("elite")
}

pub fn bus_sock_path(uid: u32) -> std::path::PathBuf {
    bus_dir(uid).join("bus.sock")
}

/// O caminho do LOCK DA SESSÃO do elite-daemon (1.0-93 — a ordem do
/// dono, rig da 1.0-92: o `/tmp/elite-daemon-session.lock` sofria
/// `os error 13` — /tmp é MUNDO COMPARTILHADO, com sticky bit e donos
/// de eras; o lock da sessão mora AGORA no tmpfs PRIVADO do dono:
/// `$XDG_RUNTIME_DIR/elite/session.lock` (`/run/user/<uid>/elite/…`).
/// O `ELITE_BUS_DIR` sobrepõe junto com o bus (os testes usam o mesmo
/// endereço; o `/tmp/elite-daemon-session.lock` segue como FALLBACK de
/// último recurso para ambientes sem XDG_RUNTIME_DIR — o daemon decide
/// ao abrir, nunca aqui).
pub fn session_lock_path(uid: u32) -> std::path::PathBuf {
    bus_dir(uid).join("session.lock")
}

/// O FALLBACK de `/tmp` (o último recurso quando o runtime privado
/// não abre — o mundo legado; quem lê decide qual está VIVO).
pub const SESSION_LOCK_FALLBACK: &str = "/tmp/elite-daemon-session.lock";

/// O teto de conexão ao bus (1.0-93 — a ordem do dono: nenhum cliente
/// da casa trava esperando o daemon ocupado; o UDS local conecta em
/// µs, o teto mata a classe dos 49s).
pub const IPC_CONNECT_TETO_MS: u64 = 500;

// ── Contratos de estado (a língua comum) ─────────────────────────────────

/// Áudio: saída padrão + microfone (o wpctl é a fonte; o contrato é o tipo).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AudioState {
    /// volume da saída 0..100 (o piso de 40% do roteador é política do daemon)
    pub sink_volume: u8,
    pub sink_muted: bool,
    pub source_muted: bool,
    /// 'Starship/Matisse HD Audio Controller' | 'Navi 31 HDMI/DP Audio' | …
    pub sink_name: Option<String>,
    /// o HDMI sem alto-falante cedeu para a analógica (marcador E140)
    pub analog_preferred: bool,
}

/// Mídia: o player MPRIS ativo (a barra v2 escuta PropertiesChanged —
/// zero polling; este tipo é o contrato do quadro que cruza o bus).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MediaState {
    /// org.mpris.MediaPlayer2.<ident> — ausente = sem mídia (botão some)
    pub player: Option<String>,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub playing: bool,
}

/// Rede: o botão NUNCA desaparece — estado offline é um estado tipado.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NetworkState {
    pub kind: NetworkKind,
    /// rótulo humano (a casa nunca mostra 'enp7s0'/'wlan0' cru)
    pub label: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NetworkKind {
    Cabo,
    Wifi,
    Offline,
}

/// Bluetooth: radio + conexões (a tela certa é o blueman; aqui só o estado).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BluetoothState {
    pub radio_on: bool,
    pub connected: u8,
}

/// GameMode: o pill da barra acende por ESTE contrato (SIGRTMIN+8 hoje;
/// o bus v2 cruza o mesmo estado pelo socket — a barra lê por onde chegar).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GameModeState {
    pub active: bool,
    /// o jogo nomeado (steam_app_413150 → 'Stardew Valley' quando o papel soube)
    pub game: Option<String>,
    /// GPU em performance (o sysfs 3D_FULL_SCREEN devolvido ao sair — Fase 2)
    pub gpu_performance: bool,
}

/// Janela: o toplevel visto pelo compositor (zwlr-foreign-toplevel).
/// O `fullscreen` entra com serde default (o fio tolera quem não fala —
/// a mesma lei dos campos novos como Option, sem quebrar leitores velhos).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WindowInfo {
    /// o id da CASA (a dock comuta por ele)
    pub id: u32,
    pub app_id: String,
    pub title: Option<String>,
    pub focused: bool,
    pub minimized: bool,
    #[serde(default)]
    pub fullscreen: bool,
    /// 1.0-100 — A MESA APRENDIDA da janela (a melhor hipótese da casa:
    /// o labwc não fala protocolo de mesas — o daemon marca a mesa onde
    /// a janela foi focada; None = nunca vista em mesa conhecida). O
    /// dock veste `.other-workspace` quando TODAS as janelas do botão
    /// têm mesa CONHECIDA ≠ a corrente; None é presumida visível (o
    /// desconhecido não mentiu). O `default` mantém o fio tolerante
    /// (daemon velho sem a mesa não quebra o dock novo e vice-versa).
    #[serde(default)]
    pub desk: Option<u32>,
}

/// Workspace atual (o labwc expõe via wayland; a barra v2 mostra por IPC).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkspaceInfo {
    pub current: u32,
    pub count: u32,
    /// nome humano quando o dono nomeou o workspace
    pub label: Option<String>,
}

/// A mensagem que cruza o bus (o único enum no fio — o daemon publica,
/// os clientes assinam; novos verbos entram como variantes novas).
///
/// 2.0 Fase 2 — o fio agora é BIDIRECIONAL: além dos estados publicados,
/// o cliente PEDE (`Req`) e o daemon confirma (`Ack`). O pedido viaja
/// com um `id` crescente por cliente — o Ack casa o pedido sem precisar
/// de correlação de conteúdo (o id é do cliente; o daemon ecoa cru).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "snake_case")]
pub enum BusMsg {
    Audio(AudioState),
    Media(MediaState),
    Network(NetworkState),
    Bluetooth(BluetoothState),
    GameMode(GameModeState),
    Window(WindowInfo),
    /// o snapshot INTEIRO da dock (a lista cruza de uma vez — a ORDEM é
    /// o anel MRU: índice 0 = janela mais recentemente focada; a dock v2
    /// deriva o rank daqui, sem campo extra no fio)
    Windows { windows: Vec<WindowInfo> },
    Workspace(WorkspaceInfo),
    /// o cliente diz quem é (o daemon nomeia no papel do dump)
    Hello { who: String },
    /// 2.0 — o veredito de um pedido do cliente (id do Req; ok = o
    /// comando foi ACEITO — o efeito mora no estado publicado a seguir)
    Ack { id: u32, ok: bool },
    /// 2.0 — um pedido do cliente para o daemon (verbos da casa). O
    /// `id` é do CLIENTE (crescente por conexão) — o daemon ecoa no
    /// Ack sem interpretar (a correlação é dever de quem pediu)
    Req { id: u32, req: BusReq },
}

/// Os verbos que o cliente pode pedir ao daemon (2.0). Janela é por id
/// do protocolo (o mesmo id que viaja no `Windows`); mídia fala com o
/// player MPRIS ativo; jogo é o modo manual; workspace é o pulo de
/// mesa (a síntese do bind W-<n> — ver elite-daemon::workspace).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BusReq {
    /// focar/restaurar a janela (activate + unset_minimized)
    Activate { id: u32 },
    /// minimizar a janela (o toggle do 2º clique da dock)
    Minimize { id: u32 },
    /// fechar a janela (WM_DELETE gracioso pelo handle Wayland)
    Close { id: u32 },
    /// pedir o snapshot INTEIRO agora (o daemon manda Windows + estados)
    Snapshot,
    /// os verbos do player MPRIS ativo (zero playerctl, zero polling)
    Media(MediaCmd),
    /// o modo de jogo manual (o pill da barra clica AQUI)
    Game(GameCmd),
    /// pular para a mesa N (1-based; a síntese é da casa)
    Workspace { to: u32 },
    /// 1.0-100 — O SYNC DA MESA (o audit 99 §4): o labwc fez a troca
    /// (bind do rc.xml com o Execute do sync) — o daemon REGISTRA e
    /// publica, NUNCA sintetiza tecla (o Workspace de cima É a síntese;
    /// sintetizar aqui fechava o loop W-n → sync → W-n para sempre).
    DeskSet { to: u32 },
    /// 1.0-100 — O passo RELATIVO da mesa ("left" | "right" |
    /// "left-occupied" | "right-occupied"): quem sabe a mesa corrente
    /// é o daemon (o CLI do rc.xml não sabe) — o cálculo com wrap e a
    /// ocupação aprendida moram no workspace.rs.
    DeskStep { dir: String },
}

/// Os verbos de mídia (MPRIS) no fio do bus.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaCmd {
    PlayPause,
    Next,
    Previous,
    /// trazer a janela do player para a frente (o clique direito)
    Focus,
}

/// Os verbos do modo de jogo no fio do bus.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GameCmd {
    On,
    Off,
    Toggle,
    Status,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bus_path_tem_o_uid_do_usuario() {
        // sem env override o caminho mora no /run/user/$UID da casa
        let p = bus_sock_path(1000);
        assert!(p.ends_with("elite/bus.sock"), "caminho errado: {p:?}");
        assert!(p.starts_with("/run/user/1000"));
    }

    #[test]
    fn o_lock_da_sessao_mora_no_tmpfs_do_dono() {
        // 1.0-93 — o lock ISOLADO: /run/user/<uid>/elite/session.lock
        // (o /tmp compartilhado era o os error 13 do rig)
        let p = session_lock_path(1000);
        assert!(p.ends_with("elite/session.lock"), "caminho errado: {p:?}");
        assert!(p.starts_with("/run/user/1000"));
        assert!(!SESSION_LOCK_FALLBACK.contains("run/user"));
        assert_eq!(IPC_CONNECT_TETO_MS, 500);
    }

    #[test]
    fn bus_path_respeita_o_override_de_teste() {
        std::env::set_var("ELITE_BUS_DIR", "/tmp/elite-bus-teste");
        let p = bus_sock_path(0);
        std::env::remove_var("ELITE_BUS_DIR");
        assert_eq!(p, std::path::PathBuf::from("/tmp/elite-bus-teste/bus.sock"));
    }

    #[test]
    fn contratos_cruzam_o_fio_e_voltam_iguais() {
        let audio = AudioState {
            sink_volume: 40,
            sink_muted: false,
            source_muted: true,
            sink_name: Some("Starship/Matisse HD Audio Controller".into()),
            analog_preferred: true,
        };
        let msg = BusMsg::Audio(audio.clone());
        let json = serde_json::to_string(&msg).unwrap();
        let back: BusMsg = serde_json::from_str(&json).unwrap();
        assert_eq!(back, msg);

        let win = WindowInfo {
            id: 10,
            app_id: "steam_app_413150".into(),
            title: Some("Stardew Valley".into()),
            focused: true,
            minimized: false,
            fullscreen: false,
            desk: Some(3),
        };
        let msg = BusMsg::Windows { windows: vec![win.clone()] };
        let json = serde_json::to_string(&msg).unwrap();
        let back: BusMsg = serde_json::from_str(&json).unwrap();
        assert_eq!(back, msg);
        // o fio é tolerante: campo novo desconhecido não quebra o leitor velho
        let with_extra = json.replacen(
            "\"windows\":[",
            "\"futuro\":null,\"windows\":[",
            1,
        );
        let back: BusMsg = serde_json::from_str(&with_extra).unwrap();
        assert!(matches!(back, BusMsg::Windows { .. }));
    }

    #[test]
    fn rede_offline_e_um_estado_tipado_e_nao_um_botao_sumido() {
        let st = NetworkState { kind: NetworkKind::Offline, label: None };
        let json = serde_json::to_string(&BusMsg::Network(st)).unwrap();
        assert!(json.contains("offline"));
    }

    #[test]
    fn folha_mestra_tem_os_tokens_da_casa() {
        // a pele única: a paleta e as três famílias vivem no mesmo papel
        for token in [
            "@define-color elite-bg",
            "@define-color elite-danger",
            "#barwindow",
            "#dockbox",
            "popover > contents",
            "button.running",
        ] {
            assert!(
                THEME_CSS.contains(token),
                "folha mestra sem o token '{token}'"
            );
        }
        assert!(!THEME_CSS.contains("waybar"), "a era waybar não volta");
    }

    #[test]
    fn os_pedidos_e_acks_cruzam_o_fio_e_voltam_iguais() {
        // 2.0 — o fio bidirecional: os verbos da casa (janela, mídia,
        // jogo, mesa, snapshot) e o eco do veredito
        let pedidos = vec![
            BusReq::Activate { id: 42 },
            BusReq::Minimize { id: 42 },
            BusReq::Close { id: 7 },
            BusReq::Snapshot,
            BusReq::Media(MediaCmd::PlayPause),
            BusReq::Media(MediaCmd::Next),
            BusReq::Media(MediaCmd::Previous),
            BusReq::Media(MediaCmd::Focus),
            BusReq::Game(GameCmd::On),
            BusReq::Game(GameCmd::Off),
            BusReq::Game(GameCmd::Toggle),
            BusReq::Game(GameCmd::Status),
            BusReq::Workspace { to: 3 },
        ];
        for r in pedidos {
            let msg = BusMsg::Req { id: 77, req: r.clone() };
            let json = serde_json::to_string(&msg).unwrap();
            let back: BusMsg = serde_json::from_str(&json).unwrap();
            assert_eq!(back, msg, "o pedido não sobreviveu ao fio: {json}");
        }
        let ack = BusMsg::Ack { id: 9, ok: true };
        let json = serde_json::to_string(&ack).unwrap();
        let back: BusMsg = serde_json::from_str(&json).unwrap();
        assert_eq!(back, ack);
        // a tag do fio é a língua da casa (json minúsculo, sem Rust no fio)
        assert!(json.contains("\"ack\""));
    }

    #[test]
    fn a_ordem_do_windows_e_o_anel_mru_do_contrato() {
        // a dock deriva o rank da ORDEM — índice 0 é o topo do MRU; o
        // contrato prova que a lista preserva a ordem no fio
        let snap = BusMsg::Windows {
            windows: vec![
                WindowInfo { id: 1, app_id: "foot".into(), title: None, focused: true, minimized: false, fullscreen: false, desk: None },
                WindowInfo { id: 2, app_id: "brave-browser".into(), title: Some("Brave".into()), focused: false, minimized: false, fullscreen: false, desk: None },
                WindowInfo { id: 3, app_id: "foot".into(), title: None, focused: false, minimized: true, fullscreen: true, desk: None },
            ],
        };
        let json = serde_json::to_string(&snap).unwrap();
        // a ordem id 1,2,3 preservada no texto do fio
        assert!(json.find("\"id\":1").unwrap() < json.find("\"id\":2").unwrap());
        let back: BusMsg = serde_json::from_str(&json).unwrap();
        let BusMsg::Windows { windows } = back else { panic!("não é Windows") };
        assert_eq!(windows[0].id, 1);
        assert!(windows[2].minimized);
        assert!(windows[2].fullscreen);
    }
}
