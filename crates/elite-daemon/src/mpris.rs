// ═════════════════════════════════════════════════════════════════════════
// elite-daemon — mpris.rs (2.0 Fase 2) — O PLAYER MPRIS NATIVO
// ═════════════════════════════════════════════════════════════════════════
// O playerctl-POLLING morre: o daemon escuta o PropertiesChanged do
// org.mpris.MediaPlayer2.* (UMA match rule — arg0 é o player) e o
// NameOwnerChanged de quem nasce/morre; a barra recebe o MediaState
// PELO BUS no instante da mudança (a diretriz: "zero polling playerctl,
// escutando PropertiesChanged"). Os VERBOS (PlayPause/Next/Previous)
// saem por D-Bus direto no player ATIVO — o cli do playerctl nunca
// mais é forkado pela interface da casa.
//
// A IDENTIDADE: o player ativo é o ÚLTIMO que anunciou PlaybackStatus
// "Playing" (ou o único vivo); a janela dele (o clique direito da
// barra = focar) casa pelo Identity/nome contra o app_id/título no
// wayland.rs (o match benigno).
// ═════════════════════════════════════════════════════════════════════════

use std::sync::Mutex;

use elite_core::{BusMsg, MediaState};


/// o estado vivo do player (None = sem mídia — o botão da barra some).
static MEDIA: Mutex<Option<MediaState>> = Mutex::new(None);

/// o nome de bus do player ativo (org.mpris.MediaPlayer2.<id>).
static PLAYER_ATIVO: Mutex<Option<String>> = Mutex::new(None);

/// o estado atual (para o snapshot de boas-vindas e a vigília).
pub fn estado() -> Option<MediaState> {
    MEDIA.lock().unwrap().clone()
}

/// a mídia está TOCANDO? (o inibidor da vigília pergunta).
pub fn tocando() -> bool {
    MEDIA.lock().unwrap().as_ref().map(|m| m.playing).unwrap_or(false)
}

/// o JUÍZO puro de qual player é o ativo (a porta dos testes): o último
/// que tocou; sem tocando, o último vivo; sem player, nada.
#[cfg(test)]
pub fn escolhe_ativo<'a>(players: &'a [(String, bool, Option<MediaState>)]) -> Option<&'a (String, bool, Option<MediaState>)> {
    players
        .iter()
        .rev()
        .find(|(_, tocando, _)| *tocando)
        .or_else(|| players.iter().rev().find(|(_, _, estado)| estado.is_some()))
}

/// os campos crus que a casa lê do PropertiesChanged (a normalização
/// de DOIS mundos: o dict do zvariant na produção, o serde_json nos
/// testes — o juízo mora em `estado_de_props`, UM lugar só).
#[derive(Debug, Default, Clone, PartialEq)]
pub struct PropsRaw {
    pub playback: Option<String>,
    pub title: Option<String>,
    pub artist: Option<String>,
}

impl PropsRaw {
    /// o dict VIVO do zvariant (OwnedValue: string OU array de string).
    pub fn do_dict(dict: &std::collections::HashMap<String, zbus::zvariant::OwnedValue>) -> Self {
        let dict = dict;
        let texto = |k: &str| -> Option<String> {
            match dict.get(k) {
                Some(v) => v.downcast_ref::<String>().ok(),
                _ => None,
            }
        };
        let lista = |k: &str| -> Option<String> {
            match dict.get(k) {
                Some(v) => v.downcast_ref::<zbus::zvariant::Array>().ok().and_then(|a| {
                    let itens: Vec<String> = a
                        .iter()
                        .filter_map(|i| i.downcast_ref::<String>().ok())
                        .collect();
                    if itens.is_empty() { None } else { Some(itens.join(", ")) }
                }),
                _ => None,
            }
        };
        PropsRaw {
            playback: texto("PlaybackStatus"),
            title: texto("Title"),
            artist: texto("Artist").or_else(|| lista("Artist")),
        }
    }

    /// o dict de papel (os testes alimentam o mesmo juízo).
    #[cfg(test)]
    pub fn do_json(props: &serde_json::Value) -> Self {
        let texto = |k: &str| props.get(k).and_then(|v| v.as_str()).map(str::to_string);
        let lista = |k: &str| -> Option<String> {
            props.get(k).and_then(|v| {
                v.as_array().map(|a| a.iter().filter_map(|x| x.as_str()).collect::<Vec<_>>().join(", "))
            })
        };
        PropsRaw {
            playback: texto("PlaybackStatus"),
            title: texto("Title"),
            artist: texto("Artist").or_else(|| lista("Artist")),
        }
    }
}

/// extrai o MediaState dos campos crus (o juízo puro da casa).
pub fn estado_de_props(player: &str, raw: &PropsRaw) -> Option<MediaState> {
    let playback = raw.playback.as_deref().unwrap_or("");
    let tocando = playback.eq_ignore_ascii_case("playing");
    let sem_midia = playback.is_empty() && raw.title.is_none() && raw.artist.is_none();
    if sem_midia {
        return None;
    }
    Some(MediaState {
        player: Some(player.to_string()),
        title: raw.title.clone(),
        artist: raw.artist.clone(),
        playing: tocando,
    })
}

/// publica o estado no bus (e guarda para o snapshot da boas-vindas).
fn publica(estado: Option<MediaState>) {
    *MEDIA.lock().unwrap() = estado.clone();
    crate::nucleo::pub_bus(&BusMsg::Media(estado.unwrap_or(MediaState {
        player: None,
        title: None,
        artist: None,
        playing: false,
    })));
}

/// OS VERBOS no player ativo (D-Bus direto — zero playerctl).
pub fn cmd(verb: elite_core::MediaCmd) -> bool {
    let player = PLAYER_ATIVO.lock().unwrap().clone();
    let Some(player) = player else { return false };
    // o clique direito: FOCAR a janela do player (o wayland casa)
    if let elite_core::MediaCmd::Focus = verb {
        let identidade = player
            .strip_prefix("org.mpris.MediaPlayer2.")
            .unwrap_or(&player)
            .to_string();
        return crate::wayland::foca_player(&identidade);
    }
    let metodo = match verb {
        elite_core::MediaCmd::PlayPause => "PlayPause",
        elite_core::MediaCmd::Next => "Next",
        elite_core::MediaCmd::Previous => "Previous",
        elite_core::MediaCmd::Focus => unreachable!(),
    };
    let Ok(c) = zbus::blocking::Connection::session() else {
        return false;
    };
    zbus::blocking::Proxy::new(
        &c,
        player.as_str(),
        "/org/mpris/MediaPlayer2",
        "org.mpris.MediaPlayer2.Player",
    )
    .and_then(|p| p.call_noreply::<_, _>(metodo, &()))
    .is_ok()
}

/// A THREAD: o ouvidor MPRIS. UMA match rule para o PropertiesChanged
/// de TODO player (arg0 = org.mpris.MediaPlayer2.Player) + o
/// NameOwnerChanged para o nascimento/morte (o botão da barra nasce e
/// morre com o player de verdade).
pub fn thread() {
    let Ok(c) = zbus::blocking::Connection::session() else {
        return;
    };
    // as propriedades de TODO player (UMA regra só — o arg0 é o player)
    let regra_props = match zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface("org.freedesktop.DBus.Properties")
        .and_then(|r| r.member("PropertiesChanged"))
        .and_then(|r| r.add_arg("org.mpris.MediaPlayer2.Player"))
        .map(|r| r.build())
    {
        Ok(r) => r,
        Err(_) => return,
    };
    let Ok(mut props_iter) = zbus::blocking::MessageIterator::for_match_rule(regra_props, &c, Some(8)) else {
        return;
    };
    // os nomes nascendo/morrendo no bus (a pílula some quando o player morre)
    let regra_owner = match zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender("org.freedesktop.DBus")
        .and_then(|r| r.interface("org.freedesktop.DBus"))
        .and_then(|r| r.member("NameOwnerChanged"))
        .map(|r| r.build())
    {
        Ok(r) => r,
        Err(_) => return,
    };
    let Ok(mut owner_iter) = zbus::blocking::MessageIterator::for_match_rule(regra_owner, &c, Some(64)) else {
        return;
    };
    // o duplex: cada PropertiesChanged atualiza o estado; cada morte de
    // nome no bus varre o ativo (o frame 0 do botão nasce e morre com o
    // player de verdade)
    loop {
        if crate::STOP.load(std::sync::atomic::Ordering::SeqCst) {
            return;
        }
        // as mensagens chegam nos DOIS iteradores — drena o que houver
        for msg in props_iter.by_ref() {
            match msg {
                Ok(msg) => on_props(&msg),
                Err(_) => continue,
            }
        }
        for msg in owner_iter.by_ref() {
            if msg.is_ok() {
                varre_players();
            }
        }
    }
}

/// uma mensagem de PropertiesChanged (o corpo é (interface, dict) — o
/// dict do zvariant vira os campos crus da casa).
fn on_props(msg: &zbus::Message) {
    let Ok(corpo) = msg
        .body()
        .deserialize::<(String, std::collections::HashMap<String, zbus::zvariant::OwnedValue>)>()
    else {
        return;
    };
    let (iface, dict) = corpo;
    if iface != "org.mpris.MediaPlayer2.Player" {
        return;
    }
    // o player é o SENDER (org.mpris.MediaPlayer2.<id>)
    let player = msg
        .header()
        .sender()
        .map(|s| s.to_string())
        .unwrap_or_default();
    if !player.starts_with("org.mpris.MediaPlayer2.") {
        return;
    }
    let raw = PropsRaw::do_dict(&dict);
    if let Some(estado) = estado_de_props(&player, &raw) {
        *PLAYER_ATIVO.lock().unwrap() = Some(player);
        publica(Some(estado));
    }
}

/// o NASCIMENTO/MORTE de players (a pílula some quando o player morre):
/// varre o bus UMA VEZ por evento do owner iter (chamado da thread).
pub fn varre_players() {
    let Ok(c) = zbus::blocking::Connection::session() else {
        return;
    };
    let Ok(proxy) = zbus::blocking::fdo::DBusProxy::new(&c) else {
        return;
    };
    let Ok(nomes) = proxy.list_names() else {
        return;
    };
    let ativo_existe = nomes
        .iter()
        .any(|n| PLAYER_ATIVO.lock().unwrap().as_deref() == Some(n.as_str()));
    if !ativo_existe {
        *PLAYER_ATIVO.lock().unwrap() = None;
        publica(None);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn o_estado_nasce_do_propertieschanged() {
        let props = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "Title": "Stardew Valley OST — Spring",
            "Artist": "ConcernedApe"
        }));
        let est = estado_de_props("org.mpris.MediaPlayer2.firefox", &props).unwrap();
        assert_eq!(est.title.as_deref(), Some("Stardew Valley OST — Spring"));
        assert_eq!(est.artist.as_deref(), Some("ConcernedApe"));
        assert!(est.playing);
        assert_eq!(est.player.as_deref(), Some("org.mpris.MediaPlayer2.firefox"));
    }

    #[test]
    fn pausado_e_um_estado_de_verdade() {
        let props = PropsRaw::do_json(&json!({"PlaybackStatus": "Paused", "Title": "X"}));
        let est = estado_de_props("org.mpris.MediaPlayer2.mpv", &props).unwrap();
        assert!(!est.playing);
        assert!(est.title.is_some());
    }

    #[test]
    fn sem_propriedades_relevantes_e_nada_honesto() {
        let props = PropsRaw::do_json(&json!({"Volume": 0.8}));
        assert!(estado_de_props("org.mpris.MediaPlayer2.x", &props).is_none());
        // dicionário vazio idem (o player nasceu sem tocar nada)
        assert!(estado_de_props("org.mpris.MediaPlayer2.x", &PropsRaw::default()).is_none());
    }

    #[test]
    fn o_artist_pode_ser_lista() {
        // o MPRIS manda array às vezes (vários artistas) — a casa junta
        let props = PropsRaw::do_json(&json!({"PlaybackStatus": "Playing", "Artist": ["A", "B"]}));
        let est = estado_de_props("p", &props).unwrap();
        assert_eq!(est.artist.as_deref(), Some("A, B"));
    }

    #[test]
    fn o_ativo_e_o_ultimo_que_tocou() {
        let players = vec![
            ("a".to_string(), false, Some(MediaState { player: Some("a".into()), title: None, artist: None, playing: false })),
            ("b".to_string(), true, Some(MediaState { player: Some("b".into()), title: None, artist: None, playing: true })),
            ("c".to_string(), false, Some(MediaState { player: Some("c".into()), title: None, artist: None, playing: false })),
        ];
        assert_eq!(escolhe_ativo(&players).unwrap().0, "b");
        // ninguém tocando: o último COM estado vence
        let calados = vec![
            ("a".to_string(), false, Some(MediaState { player: Some("a".into()), title: None, artist: None, playing: false })),
            ("b".to_string(), false, None),
        ];
        assert_eq!(escolhe_ativo(&calados).unwrap().0, "a");
        // vazio total: nada (o botão da barra some)
        assert!(escolhe_ativo(&[]).is_none());
    }
}
