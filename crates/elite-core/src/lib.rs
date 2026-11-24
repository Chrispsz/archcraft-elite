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

pub mod ipc;
pub mod persist;

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
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WindowInfo {
    /// o id do protocolo (a dock comuta por ele)
    pub id: u32,
    pub app_id: String,
    pub title: Option<String>,
    pub focused: bool,
    pub minimized: bool,
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
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "snake_case")]
pub enum BusMsg {
    Audio(AudioState),
    Media(MediaState),
    Network(NetworkState),
    Bluetooth(BluetoothState),
    GameMode(GameModeState),
    Window(WindowInfo),
    /// o snapshot INTEIRO da dock (a lista cruza de uma vez)
    Windows { windows: Vec<WindowInfo> },
    Workspace(WorkspaceInfo),
    /// o cliente diz quem é (o daemon nomeia no papel do dump)
    Hello { who: String },
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
}
