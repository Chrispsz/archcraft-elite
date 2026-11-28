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
// 1.0-106 — O PILL ACENDE NO PRIMEIRO FRAME: o censo INICIAL (a ordem
// do dono, rig da dose: o brave publicava PlaybackStatus="Playing" e
// o pill NÃO aparecia — o daemon só vestia o estado no PRIMEIRO
// PropertiesChanged, quem já tocava ao conectar ficava invisível). A
// thread NASCE com o censo: ListNames → org.mpris.MediaPlayer2.* →
// GetNameOwner de cada um (o nome com sufixo .instanceNNNN e o well-
// known name CASAM pelo owner — a FAMÍLIA inteira é o MESMO player
// para o contrato MediaState) → GetAll do estado INICIAL de cada
// player vivo → publica o ativo NA HORA (o pill da barra acende no
// snapshot de boas-vindas do bus).
//
// A IDENTIDADE: o player ativo é o ÚLTIMO que anunciou PlaybackStatus
// "Playing" (ou o único vivo); a janela dele (o clique direito da
// barra = focar) casa pelo Identity/nome contra o app_id/título no
// wayland.rs (o match benigno).
//
// 1.0-109 §2.2 — O PILL REATIVO E O FILTRO ANTI-RUÍDO: (1) o
// PropertiesChanged manda SÓ o que MUDOU — o CACHE DA FAIXA por player
// funde o sinal parcial (pausar com PlaybackStatus sozinho NUNCA mais
// derruba o título: o ícone travado do dump morre) e o dict Metadata
// PRESENTE sem xesam:* é a faixa LIMPA (veredito, não ausência); (2)
// o NameOwnerChanged do nome MORTO limpa o cache NA HORA e o censo
// ou veste o próximo elegível ou OCULTA o pill no MESMO instante do
// evento (a diretriz: < 200 ms); (3) o FILTRO: título genérico
// (WhatsApp/Audio/Voice message/…) é ruído; faixa curta (< 60s) com
// ficha vazia (sem artista OU sem controles) é ruído — a preferência
// é SEMPRE do elegível TOCANDO, sem tocando o último elegível vivo
// fica em Pausado.
// ═════════════════════════════════════════════════════════════════════════

use std::collections::HashMap;
use std::sync::Mutex;

use elite_core::{BusMsg, MediaState};


/// o estado vivo do player (None = sem mídia — o botão da barra some).
static MEDIA: Mutex<Option<MediaState>> = Mutex::new(None);

/// o nome de bus do player ativo (org.mpris.MediaPlayer2.<id>).
static PLAYER_ATIVO: Mutex<Option<String>> = Mutex::new(None);

/// 1.0-104 — O TRADUTOR ÚNICO→BEM-CONHECIDO (a cura do MPRIS MUDO): o
/// barramento D-Bus REESCREVE o campo sender dos sinais para o nome
/// ÚNICO do remetente (":1.42" — a especificação manda, o nome bem-
/// conhecido é um ALIASE do dono, não o envelope), então o juízo de
/// "starts_with(org.mpris.MediaPlayer2.)" sobre o sender NUNCA casou:
/// TODO PropertiesChanged de TODO player morria na porta e a barra
/// vivia sem mídia. A casa mantém o tradutor: o nome MPRIS mora na
/// POSSE (GetNameOwner), não no envelope — e os nomes com SUFIXO DE
/// INSTÂNCIA (org.mpris.MediaPlayer2.brave.instance10559 — o
/// YouTube Music no Brave) são o contrato do próprio MPRIS para
/// múltiplas instâncias: TODOS casam, nenhum é recusado. O cache é
/// permanente por desenho: nomes únicos não são reusados no barramento
/// e a fila de players de uma sessão é minúscula.
static NOMES_DE_BUS: Mutex<Option<HashMap<String, String>>> = Mutex::new(None);

/// 1.0-109 §2.2 — O CACHE DA FAIXA POR PLAYER (a cura do ÍCONE TRAVADO:
/// o PropertiesChanged manda SÓ o que MUDOU — pausar manda UM dict com
/// PlaybackStatus sozinho, e o título que NÃO vejo não pode sumir; sem
/// o merge o estado parcial virava None e o ícone ficava travado no
/// que era ANTES do clique). O cache morre com o player (NameOwnerChanged
/// limpa na hora — a faixa de um morto é ruído). O corpo é o RAW
/// FUNDIDO: o filtro anti-ruído lê o MESMO estado que o pill mostra.
#[derive(Debug, Clone, PartialEq)]
struct TrackCache {
    raw: PropsRaw,
}

static TRACKS: Mutex<Option<HashMap<String, TrackCache>>> = Mutex::new(None);

/// 1.0-109 §2.2 — A ORDEM DOS ANÚNCIOS (o "último elegível vivo" é o
/// player que anunciou por ÚLTIMO — o ListNames do censo é ordem
/// alfabética, não ordem de vida; a fila mora aqui, mais recente no
/// FIM para o juízo .rev() da escolhe_ativo).
static ORDEM: Mutex<Option<Vec<String>>> = Mutex::new(None);

/// o estado atual (para o snapshot de boas-vindas e a vigília).
pub fn estado() -> Option<MediaState> {
    MEDIA.lock().unwrap().clone()
}

/// a mídia está TOCANDO? (o inibidor da vigília pergunta).
pub fn tocando() -> bool {
    MEDIA.lock().unwrap().as_ref().map(|m| m.playing).unwrap_or(false)
}

/// o JUÍZO puro de qual player é o ativo (a porta dos testes — e o
/// critério do CENSO de todos os varre_*): o último que tocou; sem
/// tocando, o último vivo; sem player, nada.
pub fn escolhe_ativo(players: &[(String, bool, Option<MediaState>)]) -> Option<&(String, bool, Option<MediaState>)> {
    players
        .iter()
        .rev()
        .find(|(_, tocando, _)| *tocando)
        .or_else(|| players.iter().rev().find(|(_, _, estado)| estado.is_some()))
}

/// 1.0-109 §2.2.6 — OS TÍTULOS DE RUÍDO DA DIRETRIZ (os áudios curtos
/// de WhatsApp Web / redes sociais sequestravam o pill com título
/// genérico): a lista da diretriz, comparada em minúsculas.
pub const TITULOS_RUIDO: [&str; 5] = [
    "whatsapp",
    "whatsapp web",
    "audio",
    "voice message",
    "mensagem de voz",
];

/// o teto do áudio curto (60s em µs — o contrato do mpris:length):
/// faixa mais curta QUE ISSO com ficha vazia é ruído de rede social.
pub const TETO_CURTO_US: i64 = 60_000_000;

/// os campos crus que a casa lê do PropertiesChanged (a normalização
/// de DOIS mundos: o dict do zvariant na produção, o serde_json nos
/// testes — o juízo mora em `estado_de_props`, UM lugar só).
/// 1.0-106 — O CONTRATO DE VERDADE DO MPRIS: o título e o artista moram
/// DENTRO do dict "Metadata" ("xesam:title"/"xesam:artist" — o brave
/// publicava xesam:title "Need 2" e xesam:artist ["Pinegrove"] e o
/// pill nascia vazio porque a casa lia "Title"/"Artist" de ERA no
/// TOPO do dict); a leitura é CHAVE POR CHAVE — mpris:length (i64/'x')
/// e mpris:trackid (ObjectPath/'o') NUNCA derrubam a extração (quem
/// não pedimos é silêncio, não erro).
#[derive(Debug, Default, Clone, PartialEq)]
pub struct PropsRaw {
    pub playback: Option<String>,
    pub title: Option<String>,
    pub artist: Option<String>,
    /// 1.0-109 §2.2.6 — o FILTRO ANTI-RUÍDO lê a ficha da faixa:
    /// mpris:length (i64, µs) · CanGoNext/CanGoPrevious (bool) e a
    /// PRESENÇA do dict Metadata (o dict PRESENTE sem xesam:* é a
    /// faixa LIMPA pelo player — o None DELE é veredito, não ausência).
    pub length: Option<i64>,
    pub can_next: Option<bool>,
    pub can_prev: Option<bool>,
    /// Some(true) quando o dict VEIO com a chave Metadata (o sinal de
    /// que a faixa foi LIMPA: o None de título/artista NELE é verdict,
    /// não ausência de informação).
    pub meta_limpa: Option<bool>,
}

impl PropsRaw {
    /// o dict VIVO do zvariant: PlaybackStatus no topo + o "Metadata"
    /// (a{sv}) lido CHAVE POR CHAVE — o campo que não pedimos (trackid
    /// ObjectPath) cai no `_` e não derruba NADA.
    pub fn do_dict(dict: &std::collections::HashMap<String, zbus::zvariant::OwnedValue>) -> Self {
        let playback = dict
            .get("PlaybackStatus")
            .and_then(|v| v.downcast_ref::<String>().ok());
        let can_next = dict
            .get("CanGoNext")
            .and_then(|v| v.downcast_ref::<bool>().ok());
        let can_prev = dict
            .get("CanGoPrevious")
            .and_then(|v| v.downcast_ref::<bool>().ok());
        let mut title = None;
        let mut artist = None;
        let mut length = None;
        let mut meta_limpa = None;
        if let Some(meta) = dict
            .get("Metadata")
            .and_then(|v| v.downcast_ref::<zbus::zvariant::Dict>().ok())
        {
            meta_limpa = Some(true);
            for (chave, valor) in meta.iter() {
                let Ok(chave) = chave.downcast_ref::<String>() else { continue };
                match chave.as_str() {
                    "xesam:title" => title = valor.downcast_ref::<String>().ok(),
                    "xesam:artist" => {
                        // o artista é ARRAY de string no contrato — com
                        // fallback para a string ÚNICA (player mesquinho)
                        artist = valor
                            .downcast_ref::<zbus::zvariant::Array>()
                            .ok()
                            .and_then(|a| {
                                let itens: Vec<String> = a
                                    .iter()
                                    .filter_map(|i| i.downcast_ref::<String>().ok())
                                    .collect();
                                if itens.is_empty() { None } else { Some(itens.join(", ")) }
                            })
                            .or_else(|| valor.downcast_ref::<String>().ok());
                    }
                    "mpris:length" => length = valor.downcast_ref::<i64>().ok(),
                    // mpris:trackid/artUrl: não pedimos — silêncio
                    _ => {}
                }
            }
        }
        PropsRaw { playback, title, artist, length, can_next, can_prev, meta_limpa }
    }

    /// o dict de papel (os testes alimentam o mesmo juízo — a MESMA
    /// forma do MPRIS: PlaybackStatus no topo, xesam:* dentro do
    /// Metadata).
    #[cfg(test)]
    pub fn do_json(props: &serde_json::Value) -> Self {
        let meta = props.get("Metadata");
        let texto = |k: &str| meta.and_then(|m| m.get(k)).and_then(|v| v.as_str()).map(str::to_string);
        let lista = |k: &str| -> Option<String> {
            meta.and_then(|m| m.get(k)).and_then(|v| {
                v.as_array().map(|a| a.iter().filter_map(|x| x.as_str()).collect::<Vec<_>>().join(", "))
            })
        };
        PropsRaw {
            playback: props.get("PlaybackStatus").and_then(|v| v.as_str()).map(str::to_string),
            title: texto("xesam:title"),
            artist: texto("xesam:artist").or_else(|| lista("xesam:artist")),
            length: meta
                .and_then(|m| m.get("mpris:length"))
                .and_then(|v| v.as_i64()),
            can_next: props.get("CanGoNext").and_then(|v| v.as_bool()),
            can_prev: props.get("CanGoPrevious").and_then(|v| v.as_bool()),
            meta_limpa: meta.map(|_| true),
        }
    }
}

/// extrai o MediaState dos campos crus (o juízo puro da casa). 1.0-106 —
/// sem FAIXA (nem título nem artista) é o vazio honesto: o "Stopped"
/// com Metadata vazio não acende pill nenhum (o assento é da mídia que
/// o dono LÊ, não do player respirando).
/// 1.0-109 §2.2.6 — O FILTRO ANTI-RUÍDO (a diretriz: os áudios curtos de
/// WhatsApp Web / redes sociais NUNCA mais sequestram o player da barra):
/// (a) o título GENÉRICO da lista da diretriz é ruído (comparado em
/// minúsculas com o trim); (b) a faixa CURTA conhecida (mpris:length
/// < 60_000_000 µs) com ficha VAZIA (sem xesam:artist OU sem os controles
/// CanGoNext/CanGoPrevious) é ruído — o ping da rede social não é música.
pub fn estado_de_props(player: &str, raw: &PropsRaw) -> Option<MediaState> {
    if raw.title.is_none() && raw.artist.is_none() {
        return None;
    }
    // (a) o título genérico da rede social (a lista da diretriz)
    if let Some(t) = raw.title.as_deref() {
        if TITULOS_RUIDO.contains(&t.trim().to_lowercase().as_str()) {
            return None;
        }
    }
    // (b) a faixa curta com ficha vazia: <60s E (sem artista OU sem
    // controles) — o áudio do WhatsApp não é a mídia do dono
    let curta = matches!(raw.length, Some(l) if l > 0 && l < TETO_CURTO_US);
    if curta {
        let sem_artista = raw.artist.as_deref().map(str::is_empty).unwrap_or(true);
        let sem_controles =
            !raw.can_next.unwrap_or(true) && !raw.can_prev.unwrap_or(true);
        if sem_artista || sem_controles {
            return None;
        }
    }
    let playback = raw.playback.as_deref().unwrap_or("");
    let tocando = playback.eq_ignore_ascii_case("playing");
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

/// A THREAD: o ouvidor MPRIS. Nasce com o CENSO INICIAL (o pill acende
/// no frame 0 de quem já tocava), UMA match rule para o PropertiesChanged
/// de TODO player (arg0 = org.mpris.MediaPlayer2.Player) + o
/// NameOwnerChanged para o nascimento/morte (o botão da barra nasce e
/// morre com o player de verdade).
pub fn thread() {
    let Ok(c) = zbus::blocking::Connection::session() else {
        return;
    };
    // 1.0-106 — O CENSO INICIAL: quem já toca ao daemon nascer já é
    // notícia (o rig fotografou o brave Playing sem pill — a era só
    // vestia o estado no PRIMEIRO PropertiesChanged)
    varre_players();
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
    // o duplex: cada PropertiesChanged atualiza o estado; cada
    // nascimento/morte de nome MPRIS varre o ativo (o frame 0 do
    // botão nasce e morre com o player de verdade)
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
            match msg {
                Ok(msg) => on_owner(&msg),
                Err(_) => continue,
            }
        }
    }
}

/// uma mensagem de PropertiesChanged (o corpo é (interface, dict,
/// invalidadas) — o dict do zvariant vira os campos crus da casa; o
/// PLAYER é o nome MPRIS traduzido do sender ÚNICO do envelope —
/// 1.0-104: sem o tradutor, NENHUM sinal casava e a barra vivia sem
/// mídia).
fn on_props(msg: &zbus::Message) {
    let Ok(corpo) = msg
        .body()
        .deserialize::<(
            String,
            std::collections::HashMap<String, zbus::zvariant::OwnedValue>,
            Vec<String>,
        )>()
    else {
        return;
    };
    let (iface, dict, _invalidadas) = corpo;
    if iface != "org.mpris.MediaPlayer2.Player" {
        return;
    }
    // o player é o REMETENTE traduzido (o barramento assina o envelope
    // com o nome ÚNICO ":1.N" — o nome org.mpris.MediaPlayer2.<id>.
    // [<instância>] mora na POSSE do nome, não no envelope do sinal)
    let Some(sender) = msg.header().sender().map(|s| s.to_string()) else {
        return;
    };
    let Ok(c) = zbus::blocking::Connection::session() else {
        return;
    };
    let Some(player) = nome_do_player(&c, &sender) else {
        return;
    };
    let raw = PropsRaw::do_dict(&dict);
    // 1.0-109 §2.2 — O MERGE COM O CACHE DA FAIXA (o PropertiesChanged
    // manda SÓ o que MUDOU: pausar é UM dict com PlaybackStatus sozinho
    // — o título que NÃO veio mora no cache; sem o merge a faixa
    // parcial morria e o ícone TRAVAVA no estado anterior)
    let Some(estado) = funde_track(&player, raw) else {
        return;
    };
    if estado.playing {
        *PLAYER_ATIVO.lock().unwrap() = Some(player);
        publica(Some(estado));
        return;
    }
    // 1.0-109 §2.2.6 — o PAUSADO NÃO ROUBA O ASSENTO DE QUEM TOCA (a
    // preferência é SEMPRE do elegível tocando; o PRÓPRIO ativo pausado
    // renova o estado na hora — o ícone veste o ▶ no instante do clique)
    let ativo = PLAYER_ATIVO.lock().unwrap().clone();
    let veste = match ativo.as_deref() {
        None => true,
        Some(nome) if nome == player => true,
        Some(_) => !MEDIA.lock().unwrap().as_ref().map(|m| m.playing).unwrap_or(false),
    };
    if veste {
        *PLAYER_ATIVO.lock().unwrap() = Some(player);
        publica(Some(estado));
    }
}

/// 1.0-109 §2.2 — O MERGE COM O CACHE (a porta dos testes): o sinal
/// parcial casa com a FAIXA viva do player — o que veio vence, o que
/// não veio mora no cache; o dict Metadata PRESENTE sem xesam:* é a
/// faixa LIMPA (o None dele é veredito, não ausência). O cache morre
/// com a faixa (o juízo de elegibilidade é o MESMO da publicação).
pub fn funde_track(player: &str, novo: PropsRaw) -> Option<MediaState> {
    let mut tracks = TRACKS.lock().unwrap();
    let mapa = tracks.get_or_insert_with(HashMap::new);
    let base = mapa.get(player).map(|c| c.raw.clone());
    let fundido = match base {
        Some(base) => {
            let limpa = novo.meta_limpa == Some(true);
            PropsRaw {
                playback: novo.playback.or(base.playback),
                title: if limpa { None } else { novo.title.or(base.title) },
                artist: if limpa { None } else { novo.artist.or(base.artist) },
                length: if limpa { None } else { novo.length.or(base.length) },
                can_next: novo.can_next.or(base.can_next),
                can_prev: novo.can_prev.or(base.can_prev),
                meta_limpa: novo.meta_limpa.or(base.meta_limpa),
            }
        }
        None => novo.clone(),
    };
    let estado = estado_de_props(player, &fundido);
    match estado {
        Some(_) => {
            mapa.insert(player.to_string(), TrackCache { raw: fundido });
        }
        None => {
            mapa.remove(player);
        }
    }
    drop(tracks);
    bumpa_ordem(player);
    estado
}

/// 1.0-109 §2.2 — o anúncio do player toca a fila da ORDEM (o mais
/// recente no FIM — o "último elegível vivo" é o ÚLTIMO que anunciou,
/// não o alfabético do ListNames).
fn bumpa_ordem(player: &str) {
    let mut fila = ORDEM.lock().unwrap();
    let fila = fila.get_or_insert_with(Vec::new);
    fila.retain(|n| n != player);
    fila.push(player.to_string());
}

/// O NASCIMENTO/MORTE de players (o pill some quando o player morre):
/// o NameOwnerChanged de TODO org.mpris.MediaPlayer2.* (o sufixo
/// .instance* é o contrato do MPRIS para a FAMÍLIA — o well-known name
/// e a instância são o MESMO player pelos olhos do owner). O cache de
/// nomes é APAGADO nas duas pontas (o nome novo tem dono novo; o nome
/// morto nunca mais responde) e o censo re-veste o ativo.
fn on_owner(msg: &zbus::Message) {
    let Ok((nome, velho, novo)) = msg
        .body()
        .deserialize::<(String, String, String)>()
    else {
        return;
    };
    if !nome.starts_with("org.mpris.MediaPlayer2.") {
        return; // o aniversário dos outros não é notícia daqui
    }
    {
        let mut cache = NOMES_DE_BUS.lock().unwrap();
        if let Some(mapa) = cache.as_mut() {
            mapa.remove(&velho);
            mapa.remove(&novo);
        }
    }
    // 1.0-109 §2.2.2 — A FAIXA DO NOME MORTO MORRE JUNTO (a diretriz:
    // o nome perdeu o dono → o cache da faixa é limpo NA HORA e o
    // watcher daquele player é zerado — a faixa de um morto é ruído;
    // o censo a seguir ou veste o próximo elegível ou OCULTA o pill
    // no MESMO instante do evento, < 200 ms)
    {
        let mut tracks = TRACKS.lock().unwrap();
        if let Some(mapa) = tracks.as_mut() {
            mapa.remove(&nome);
        }
    }
    {
        let mut fila = ORDEM.lock().unwrap();
        if let Some(f) = fila.as_mut() {
            f.retain(|n| n != &nome);
        }
    }
    varre_players();
}

/// O CENSO (a varredura de TODOS os players — o censo inicial da
/// thread E a resposta ao nascimento/morte): lista os vivos, lê o
/// estado de cada um, publica o ativo. 1.0-109 §2.2.6 — a preferência
/// é SEMPRE do elegível TOCANDO; sem tocando, o ÚLTIMO elegível vivo
/// fica em Pausado; sem elegível NENHUM, o pill OCULTA na hora (a
/// diretriz: o pill some no mesmo instante do último player morrer).
pub fn varre_players() {
    let Ok(c) = zbus::blocking::Connection::session() else {
        return;
    };
    let players = varre_todos(&c);
    match escolhe_ativo(&players).cloned() {
        Some((nome, _, estado)) => {
            *PLAYER_ATIVO.lock().unwrap() = Some(nome);
            publica(estado);
        }
        None => {
            *PLAYER_ATIVO.lock().unwrap() = None;
            publica(None);
        }
    }
}

/// a FAMÍLIA dos vivos: cada org.mpris.MediaPlayer2.* com o estado lido
/// (GetAll) e o cache de tradução alimentado (o PropertiesChanged que
/// vier depois responde na hora, sem ir ao bus de novo). 1.0-109 §2.2 —
/// o GetAll VESTE O CACHE DA FAIXA (o sinal parcial de depois funde com
/// a leitura COMPLETA de agora) e a fila sai na ORDEM DOS ANÚNCIOS (o
/// "último elegível vivo" é o último que anunciou — o ListNames é
/// alfabético, não ordem de vida).
fn varre_todos(c: &zbus::blocking::Connection) -> Vec<(String, bool, Option<MediaState>)> {
    let mut out = Vec::new();
    for (nome, dono) in nomes_com_dono(c) {
        NOMES_DE_BUS
            .lock()
            .unwrap()
            .get_or_insert_with(HashMap::new)
            .insert(dono, nome.clone());
        let estado = le_player(c, &nome);
        let tocando = estado.as_ref().map(|e| e.playing).unwrap_or(false);
        out.push((nome, tocando, estado));
    }
    // a ordem dos ANÚNCIOS manda (o mais recente no fim — o .rev() do
    // escolhe_ativo casa o "último que anunciou"); quem nunca anunciou
    // fica na frente (o veterano anunciado ganha o desempate)
    if let Some(fila) = ORDEM.lock().unwrap().clone() {
        let pos = |n: &str| fila.iter().position(|x| x == n).unwrap_or(usize::MAX - 1);
        out.sort_by_key(|(n, _, _)| pos(n));
    }
    out
}

/// o estado INICIAL de UM player: GetAll do org.mpris.MediaPlayer2.
/// Player (o mesmo dict do PropertiesChanged — o MESMO juízo do
/// PropsRaw; quem nasce tocando nasce publicado). 1.0-109 §2.2 — a
/// leitura COMPLETA VESTE O CACHE da faixa (o sinal parcial que vier
/// depois funde com ela — a cura do ícone travado).
fn le_player(c: &zbus::blocking::Connection, player: &str) -> Option<MediaState> {
    let Ok(proxy) = zbus::blocking::Proxy::new(
        c,
        player,
        "/org/mpris/MediaPlayer2",
        "org.mpris.MediaPlayer2.Player",
    ) else {
        return None;
    };
    let Ok(dict) = proxy.call::<_, _, std::collections::HashMap<String, zbus::zvariant::OwnedValue>>(
        "GetAll",
        &("org.mpris.MediaPlayer2.Player"),
    ) else {
        return None;
    };
    let raw = PropsRaw::do_dict(&dict);
    // a leitura é COMPLETA: o cache da faixa veste ELA (não o merge — o
    // dict do GetAll é a verdade inteira do player neste instante)
    let estado = estado_de_props(player, &raw);
    {
        let mut tracks = TRACKS.lock().unwrap();
        let mapa = tracks.get_or_insert_with(HashMap::new);
        match estado {
            Some(_) => {
                mapa.insert(player.to_string(), TrackCache { raw });
            }
            None => {
                mapa.remove(player);
            }
        }
    }
    bumpa_ordem(player);
    estado
}

/// O JUÍZO PURO da tradução (a porta dos testes): dado o sender ÚNICO
/// (":1.42") e a lista de (nome MPRIS → dono único) que o barramento
/// responde, devolve o NOME DO PLAYER dele — inclusive os nomes com
/// sufixo de instância (o contrato do MPRIS: o brave.instance10559 é
/// um player COMO QUALQUER OUTRO).
pub fn traduz_sender<'a>(
    sender: &str,
    nomes_com_dono: &[(&'a str, &str)],
) -> Option<&'a str> {
    // o envelope já veio com o nome MPRIS (o remetente assinou com o
    // próprio nome — o barramento é quem costuma sobrescrever):
    if sender.starts_with("org.mpris.MediaPlayer2.") {
        return nomes_com_dono
            .iter()
            .find(|(n, _)| *n == sender)
            .map(|(n, _)| *n);
    }
    nomes_com_dono
        .iter()
        .find(|(_, dono)| *dono == sender)
        .map(|(nome, _)| *nome)
}

/// a lista (nome MPRIS, dono único) do barramento vivo — o GetNameOwner
/// de CADA org.mpris.MediaPlayer2.* (o nome mora na posse, não no
/// envelope do sinal).
fn nomes_com_dono(c: &zbus::blocking::Connection) -> Vec<(String, String)> {
    let Ok(proxy) = zbus::blocking::fdo::DBusProxy::new(c) else {
        return Vec::new();
    };
    let Ok(nomes) = proxy.list_names() else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for n in nomes {
        // o zbus 4 entrega OwnedBusName (a casa veste String — o nome é
        // dado, não tipo de fio; o get_name_owner casa por BusName<'_>)
        let n = n.to_string();
        if !n.starts_with("org.mpris.MediaPlayer2.") {
            continue;
        }
        if let Ok(bus) = zbus::names::BusName::try_from(n.as_str()) {
            if let Ok(dono) = proxy.get_name_owner(bus) {
                out.push((n, dono.to_string()));
            }
        }
    }
    out
}

/// o NOME do player que emitiu a mensagem (o tradutor com cache: o
/// cache da casa responde; omissão → a lista + o GetNameOwner vestem
/// e a resposta entra no cache para os próximo sinais — a tradução
/// custa UMA vez por player vivo, não uma por PropertiesChanged).
fn nome_do_player(c: &zbus::blocking::Connection, sender: &str) -> Option<String> {
    let mut cache = NOMES_DE_BUS.lock().unwrap();
    if let Some(nome) = cache.as_ref().and_then(|m| m.get(sender)) {
        return Some(nome.clone());
    }
    let lista = nomes_com_dono(c);
    let pares: Vec<(&str, &str)> = lista
        .iter()
        .map(|(n, d)| (n.as_str(), d.as_str()))
        .collect();
    let nome = traduz_sender(sender, &pares)?.to_string();
    cache
        .get_or_insert_with(HashMap::new)
        .insert(sender.to_string(), nome.clone());
    Some(nome)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn o_estado_nasce_do_propertieschanged() {
        // 1.0-106 — A FORMA DE VERDADE DO MPRIS: o título/artista moram
        // DENTRO do dict "Metadata" (xesam:*) — o juízo da casa lê por
        // CHAVE, nunca o dict inteiro
        let props = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "Metadata": {
                "xesam:title": "Need 2",
                "xesam:artist": ["Pinegrove"],
                "mpris:length": 213000000,
                "mpris:trackid": "/dev/null"
            }
        }));
        let est = estado_de_props("org.mpris.MediaPlayer2.brave.instance1868", &props).unwrap();
        assert_eq!(est.title.as_deref(), Some("Need 2"));
        assert_eq!(est.artist.as_deref(), Some("Pinegrove"));
        assert!(est.playing);
        assert_eq!(
            est.player.as_deref(),
            Some("org.mpris.MediaPlayer2.brave.instance1868")
        );
    }

    #[test]
    fn o_artist_pode_ser_string_unica() {
        // o player mesquinho manda string ÚNICA — o fallback veste
        let props = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "Metadata": {"xesam:title": "Spring", "xesam:artist": "ConcernedApe"}
        }));
        let est = estado_de_props("org.mpris.MediaPlayer2.firefox", &props).unwrap();
        assert_eq!(est.title.as_deref(), Some("Spring"));
        assert_eq!(est.artist.as_deref(), Some("ConcernedApe"));
        assert!(est.playing);
    }

    #[test]
    fn os_campos_auxiliares_nunca_derrubam_a_extracao() {
        // mpris:length (i64/'x') e mpris:trackid (ObjectPath/'o') são
        // vizinhos de quem pedimos — a leitura CHAVE POR CHAVE nunca
        // morre por causa deles (o juízo pediu 3 chaves, o resto é
        // silêncio)
        let props = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "Metadata": {
                "xesam:title": "X",
                "mpris:length": 213000000,
                "mpris:trackid": "/org/mpris/MediaPlayer2/track/1",
                "mpris:artUrl": "file:///tmp/capa.jpg"
            }
        }));
        let est = estado_de_props("p", &props).unwrap();
        assert_eq!(est.title.as_deref(), Some("X"));
        assert_eq!(est.artist, None, "sem xesam:artist = None honesto");
    }

    #[test]
    fn pausado_e_um_estado_de_verdade() {
        let props = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Paused",
            "Metadata": {"xesam:title": "X"}
        }));
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
        // o Metadata VAZIO (player vivo sem faixa) é o None honesto
        let props = PropsRaw::do_json(&json!({"PlaybackStatus": "Stopped", "Metadata": {}}));
        assert!(estado_de_props("org.mpris.MediaPlayer2.x", &props).is_none());
    }

    #[test]
    fn o_artist_pode_ser_lista() {
        // o MPRIS manda array às vezes (vários artistas) — a casa junta
        let props = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "Metadata": {"xesam:artist": ["A", "B"]}
        }));
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
        // 1.0-106 — o censo INICIAL: quem já toca ao conectar é o ativo
        // (o pill nasce ACESO — o brave.instance* é a família inteira)
        let familia = vec![
            ("org.mpris.MediaPlayer2.brave.instance1868".to_string(), true, Some(MediaState {
                player: Some("org.mpris.MediaPlayer2.brave.instance1868".into()),
                title: Some("Need 2".into()), artist: Some("Pinegrove".into()), playing: true,
            })),
            ("org.mpris.MediaPlayer2.mpd".to_string(), false, None),
        ];
        assert_eq!(escolhe_ativo(&familia).unwrap().0, "org.mpris.MediaPlayer2.brave.instance1868");
    }

    // ── 1.0-104 — o TRADUTOR do envelope (o sender único → nome MPRIS) ──

    #[test]
    fn o_tradutor_casa_o_nome_pela_posse() {
        // o cenário DO DND do rig: o barramento assina o envelope com o
        // nome ÚNICO ":1.42" — o nome MPRIS mora na posse (GetNameOwner)
        let pares = [
            ("org.mpris.MediaPlayer2.firefox", ":1.42"),
            ("org.mpris.MediaPlayer2.brave.instance10559", ":1.77"),
            ("org.mpris.MediaPlayer2.mpv", ":1.90"),
        ];
        // o nome com SUFIXO DE INSTÂNCIA é o CONTRATO do MPRIS para
        // múltiplas instâncias (o YouTube Music no Brave): casa COMO
        // QUALQUER OUTRO — nenhum player é recusado por ter instância
        assert_eq!(
            traduz_sender(":1.77", &pares),
            Some("org.mpris.MediaPlayer2.brave.instance10559")
        );
        // o player comum idem (a posse é o juízo, nunca o envelope)
        assert_eq!(
            traduz_sender(":1.42", &pares),
            Some("org.mpris.MediaPlayer2.firefox")
        );
        // o envelope JÁ assinado com o nome MPRIS (o remetente mandou):
        // o nome é a própria identidade — devolve o nome CONFIRMADO
        assert_eq!(
            traduz_sender("org.mpris.MediaPlayer2.mpv", &pares),
            Some("org.mpris.MediaPlayer2.mpv")
        );
        // o sender que não é dono de NENHUM player MPRIS: nada honesto
        assert_eq!(traduz_sender(":1.99", &pares), None);
        // lista vazia (o bus sem players): nada — a barra segue sem mídia
        assert_eq!(traduz_sender(":1.42", &[]), None);
    }

    // ── 1.0-109 §2.2 — O ÍCONE REATIVO E O FILTRO ANTI-RUÍDO ──────────

    #[test]
    fn o_sinal_parcial_funde_com_o_cache_da_faixa() {
        // A EVIDÊNCIA DO RIG: o pill ficava TRAVADO em ⏸ — pausar manda
        // UM dict com PlaybackStatus SOZINHO e a faixa parcial virava
        // None (o título morava no sinal que NÃO veio)
        let bravo = "org.mpris.MediaPlayer2.brave.instance15578";
        let inteiro = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "CanGoNext": true,
            "CanGoPrevious": true,
            "Metadata": {
                "xesam:title": "Need 2",
                "xesam:artist": ["Pinegrove"],
                "mpris:length": 213000000
            }
        }));
        let tocando = funde_track(bravo, inteiro).unwrap();
        assert!(tocando.playing);
        assert_eq!(tocando.title.as_deref(), Some("Need 2"));
        // o PAUSAR chega PARCIAL (só o status): o título mora no CACHE
        let parcial = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Paused"
        }));
        let pausado = funde_track(bravo, parcial).unwrap();
        assert!(!pausado.playing, "o ícone veste o ▶ NA HORA do clique");
        assert_eq!(pausado.title.as_deref(), Some("Need 2"), "a faixa não morre com o sinal parcial");
        assert_eq!(pausado.artist.as_deref(), Some("Pinegrove"));
    }

    #[test]
    fn a_faixa_limpa_pelo_player_mata_o_cache() {
        // o player LIMPOU o Metadata (Stopped de verdade): o dict PRESENTE
        // sem xesam:* é veredito — o None dele não é ausência de informação
        let mpv = "org.mpris.MediaPlayer2.mpv";
        let tocando = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "Metadata": {"xesam:title": "X", "mpris:length": 213000000}
        }));
        assert!(funde_track(mpv, tocando).is_some());
        let limpa = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Stopped",
            "Metadata": {}
        }));
        assert!(funde_track(mpv, limpa).is_none(), "a faixa limpa é o None honesto");
        // e o cache MORRE: o próximo sinal parcial não ressuscita fantasma
        let eco = PropsRaw::do_json(&json!({"PlaybackStatus": "Paused"}));
        assert!(funde_track(mpv, eco).is_none());
    }

    #[test]
    fn o_filtro_anti_ruido_do_whatsapp_e_da_rede_social() {
        // (a) os TÍTULOS GENÉRICOS da diretriz — em qualquer caixa
        for titulo in ["WhatsApp", "whatsapp web", "Audio", "Voice message", "Mensagem de voz"] {
            let raw = PropsRaw::do_json(&json!({
                "PlaybackStatus": "Playing",
                "Metadata": {"xesam:title": titulo, "mpris:length": 30000000}
            }));
            assert!(
                estado_de_props("org.mpris.MediaPlayer2.brave.instance1", &raw).is_none(),
                "o título genérico '{titulo}' é ruído, nunca mídia do dono"
            );
        }
        // (b) a faixa CURTA com ficha VAZIA: 15s SEM artista e SEM
        // controles — o ping da rede social
        let curto = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "CanGoNext": false,
            "CanGoPrevious": false,
            "Metadata": {"xesam:title": "Uma nota de voz real", "mpris:length": 15000000}
        }));
        assert!(estado_de_props("org.mpris.MediaPlayer2.firefox", &curto).is_none());
        // o curto com ficha COMPLETA é música (artista E controles — o
        // jingle de 40s do player que navega faixas)
        let curto_completo = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "CanGoNext": true,
            "CanGoPrevious": true,
            "Metadata": {"xesam:title": "Jingle", "xesam:artist": ["A Casa"], "mpris:length": 40000000}
        }));
        assert!(estado_de_props("org.mpris.MediaPlayer2.firefox", &curto_completo).is_some());
        // o curto SEM controles é ruído MESMO com artista (o ping da
        // rede social tem título de música e nome de canal como artista)
        let curto_sem_controles = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "CanGoNext": false,
            "CanGoPrevious": false,
            "Metadata": {"xesam:title": "Clipe", "xesam:artist": ["Canal"], "mpris:length": 45000000}
        }));
        assert!(estado_de_props("org.mpris.MediaPlayer2.firefox", &curto_sem_controles).is_none());
        // o curto SEM artista é ruído MESMO com controles (a ficha
        // vazia denuncia o áudio de rede social)
        let curto_sem_artista = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "CanGoNext": true,
            "CanGoPrevious": true,
            "Metadata": {"xesam:title": "Single curto", "mpris:length": 45000000}
        }));
        assert!(estado_de_props("org.mpris.MediaPlayer2.firefox", &curto_sem_artista).is_none());
        // a faixa NORMAL (>60s) sem artista é MÚSICA de verdade
        let longo = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "Metadata": {"xesam:title": "Missa em Ré", "mpris:length": 300000000}
        }));
        assert!(estado_de_props("org.mpris.MediaPlayer2.mpv", &longo).is_some());
        // o teto é 60s EM µs: 59.9s curto · 60.0s já é música
        let quase = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "Metadata": {"xesam:title": "T", "mpris:length": 59900000}
        }));
        assert!(estado_de_props("org.mpris.MediaPlayer2.mpv", &quase).is_none());
        let exato = PropsRaw::do_json(&json!({
            "PlaybackStatus": "Playing",
            "Metadata": {"xesam:title": "T", "mpris:length": 60000000}
        }));
        assert!(estado_de_props("org.mpris.MediaPlayer2.mpv", &exato).is_some());
    }
}
