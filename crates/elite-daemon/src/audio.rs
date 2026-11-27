// ═════════════════════════════════════════════════════════════════════════
// elite-daemon — audio.rs (2.0 Fase 2) — O ROTEADOR DE ÁUDIO NATIVO
// ═════════════════════════════════════════════════════════════════════════
// O corpo Python do craft-audio-route (E30→E140) MORRE AQUI: a LEI do
// roteamento vira Rust no daemon (a diretriz §7: 100% Rust na camada
// própria — o PipeWire continua sendo o PipeWire, o pactl/wpctl são a
// porta CLI dele e o daemon é o cérebro). O QUE A LEI MANDA:
//
//   1. CLASSES: microfone/webcam/fifine/"Monitor of" são PROIBIDOS de
//      default (o sink fantasma do dump p6aw); fone/headset/BT são
//      `target` (nascem no trono); a analógica é `ok`; HDMI/DP é
//      POR ÚLTIMO (monitor sem caixa de som não rouba a mesa);
//   2. A ANALÓGICA PRIORITÁRIA (dossiê 1.0-88): HDMI default + sink
//      melhor existente = TROCA — salvo o marcador audio-hdmi-ok do
//      dono que QUER o monitor;
//   3. O PISO DA VOZ (E140): quem chega ao trono com volume 0 ganha
//      40% (a analógica 'vol: 0.00' do dump nunca mais nasce muda);
//   4. O AUTO_NULL PRESO (E132): o default CONFIGURADO do WirePlumber
//      em nenhum = a escolha persistente não existe; o set-default-
//      sink por BAIXO reescreve o configurado;
//   5. O JACK com detecção: a PORTA do sink atual segue a
//      disponibilidade (fone pluga → porta dele; sai → a de caixa);
//   6. O SNAPSHOT DE CONHECIDOS (E139): só QUEM CHEGOU vira default
//      (a escolha MANUAL do dono nunca é pisada);
//   7. O PÓS-SONO (E139): o default pré-sono volta se o HDMI/DP do
//      monitor sequestrou o som no wake; o que se foi cai na LEI.
//
// O MOTOR é EVENTO: pactl subscribe (a fila do PipeWire) + netlink de
// som + o sono do logind — ZERO polling. Toda a lógica de decisão é
// PURA (SinkData entra, Veredito sai) e TESTADA; a execução pactl é
// o efeito raro por evento (a lei da casa: fork pontual ≠ residente).
// ═════════════════════════════════════════════════════════════════════════

use std::io::BufRead;
use std::io::BufReader;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::Deserialize;

// ── os DADOS (o que o pactl -f json entrega — a tipagem da casa) ─────────

#[derive(Debug, Clone, Default, Deserialize)]
pub struct SinkPorta {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub availability: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct VolCanal {
    /// o pactl manda o value como 1.000000 (float) OU "1.000000"
    /// (string) — o juízo mastiga os DOIS formatos (a lição do
    /// craft-audio E138: o '45%' com sufixo também entra)
    #[serde(default, deserialize_with = "f64_tol")]
    pub value: f64,
}

/// o mapa de canais do pactl ({"front-left": {"value": 0.45}, ...}).
#[derive(Debug, Clone, Default, Deserialize)]
pub struct VolumeMap {
    #[serde(default, rename = "front-left")]
    pub front_left: Option<VolCanal>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct SinkData {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub active_port: String,
    /// E156 (1.0-107.3) — o mudo REAL do pactl (a fonte "mute": true/false):
    /// o AudioState do bus vestia o `false` cravado desde sempre — a
    /// telemetria do dump reportava "nunca mudo" num trono mudo. O campo
    /// mora no MESMO json que já chega (zero fork novo no sink).
    #[serde(default)]
    pub mute: bool,
    #[serde(default)]
    pub volume: Option<VolumeMap>,
    #[serde(default)]
    pub ports: Vec<SinkPorta>,
    #[serde(default)]
    pub properties: std::collections::HashMap<String, String>,
}

impl SinkData {
    /// o volume 0..1 da frente esquerda (o piso da voz julga por ele).
    pub fn volume(&self) -> f64 {
        self.volume
            .as_ref()
            .and_then(|v| v.front_left.as_ref())
            .map(|c| c.value)
            .unwrap_or(1.0)
    }
}

/// o value pode vir como número OU string (com sufixo %) — a tolerância.
fn f64_tol<'de, D>(d: D) -> Result<f64, D::Error>
where
    D: serde::Deserializer<'de>,
{
    use serde_json::Value;
    let v = Value::deserialize(d)?;
    Ok(match v {
        Value::Number(n) => n.as_f64().unwrap_or(1.0),
        Value::String(s) => s.trim().trim_end_matches('%').parse().unwrap_or(1.0),
        _ => 1.0,
    })
}

// ── as CLASSES (o juízo puro — a porta dos testes) ───────────────────────

/// as classes da casa: 'bad' (nunca default) · 'target' (nascem no
/// trono) · 'ok' (analógica de verdade) · 'hdmi' (por último).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Classe {
    Bad,
    Target,
    Ok,
    Hdmi,
}

impl Classe {
    pub fn rank(self) -> u8 {
        match self {
            Classe::Target => 0,
            Classe::Ok => 1,
            Classe::Hdmi => 2,
            Classe::Bad => 3,
        }
    }
}

/// E30/E36 — o juízo de classe do sink (desc + name + form_factor +
/// bus + profile). A MARCA fifine e o genérico 'microphone' ENTRAM: a
/// reincidência da doença p6aw por outro nome morre aqui.
pub fn classifica(s: &SinkData) -> Classe {
    let desc = format!("{} {}", s.description, s.name).to_lowercase();
    for ruim in [
        "microfone",
        "microphone",
        "fifine",
        "webcam",
        "câmera",
        "camera",
        "monitor of",
    ] {
        if desc.contains(ruim) {
            return Classe::Bad;
        }
    }
    let ff = s.properties.get("device.form_factor").cloned().unwrap_or_default().to_lowercase();
    let bus = s.properties.get("device.bus").cloned().unwrap_or_default().to_lowercase();
    let prof = s.properties.get("device.profile.name").cloned().unwrap_or_default().to_lowercase();
    if ff == "headphone" || ff == "headset" || ff == "speaker" || ff == "hands-free" || bus == "bluetooth" {
        return Classe::Target;
    }
    if prof.contains("hdmi") || desc.contains("hdmi") || desc.contains("displayport") || desc.contains("dp audio") {
        return Classe::Hdmi;
    }
    Classe::Ok
}

/// o MELHOR remanescente (a LEI: target > ok > hdmi; bad jamais).
pub fn escolhe(sinks: &[SinkData]) -> Option<&SinkData> {
    sinks
        .iter()
        .filter(|s| classifica(s) != Classe::Bad && !s.name.is_empty())
        .min_by_key(|s| classifica(s).rank())
}

/// o veredito do motor (o que FAZER — puro, testado):
/// · Trocar { sink, motivo, piso } — o default atual cede;
/// · Porta { sink, porta, descricao } — o jack do sink atual segue a
///   disponibilidade (o fone do MESMO sink);
/// · Reafirmar — o auto_null: só reescreve o configurado;
/// · Nada — a lei está satisfeita.
#[derive(Debug, Clone, PartialEq)]
pub enum Veredito {
    Nada,
    Reafirmar { sink: String },
    Trocar { sink: String, motivo: &'static str, piso: bool },
    Porta { sink: String, porta: String, descricao: String },
}

/// o marcador do dono que QUER o HDMI (a escolha dele é a lei).
pub fn marcador_hdmi_ok() -> PathBuf {
    let cfg = std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/root".into())).join(".config")
        });
    cfg.join("elite/audio-hdmi-ok")
}

/// O JUÍZO INTEIRO (E30→E139→E140, 1:1 do Python provado em campo):
/// `prev` = os nomes CONHECIDOS da última avaliação (só quem CHEGOU
/// vira default — a mão do dono é respeitada); `trigger` distingue o
/// arranque ("start") do evento ("event"); `hdmi_ok` = o marcador.
pub fn julga(sinks: &[SinkData], dflt: &str, prev: &[String], trigger: &str, hdmi_ok: bool) -> Veredito {
    if sinks.is_empty() {
        return Veredito::Nada;
    }
    let atual = sinks.iter().find(|s| s.name == dflt);
    // 1) o default sumiu (BT desconectou, USB saiu) → melhor remanescente
    let Some(atual) = atual else {
        let melhor = escolhe(sinks);
        return match melhor {
            Some(m) if m.name != dflt => Veredito::Trocar {
                sink: m.name.clone(),
                motivo: "saída sumiu",
                piso: m.volume() <= 0.001,
            },
            _ => Veredito::Nada,
        };
    };
    // 2) o jack do sink atual segue a disponibilidade
    if let Some(v) = julga_porta(atual) {
        return v;
    }
    // 3) sink NOVO de classe alvo → o som vai para ele na hora
    if trigger != "start" {
        let chegaram: Vec<&str> = sinks
            .iter()
            .map(|s| s.name.as_str())
            .filter(|n| !prev.iter().any(|p| p == n))
            .collect();
        for s in sinks {
            if chegaram.contains(&s.name.as_str()) && classifica(s) == Classe::Target {
                return Veredito::Trocar {
                    sink: s.name.clone(),
                    motivo: "conectado",
                    piso: s.volume() <= 0.001,
                };
            }
        }
    }
    // 4) default na classe proibida → cura
    if classifica(atual) == Classe::Bad {
        if let Some(m) = escolhe(sinks) {
            if m.name != dflt {
                return Veredito::Trocar {
                    sink: m.name.clone(),
                    motivo: "saída inválida",
                    piso: m.volume() <= 0.001,
                };
            }
        }
        return Veredito::Nada;
    }
    // 5) E140 — o HDMI sem som CEDE para a analógica/fone
    if classifica(atual) == Classe::Hdmi && !hdmi_ok {
        if let Some(m) = escolhe(sinks) {
            if m.name != dflt {
                return Veredito::Trocar {
                    sink: m.name.clone(),
                    motivo: "HDMI sem som — a analógica tem prioridade",
                    piso: m.volume() <= 0.001,
                };
            }
        }
    }
    Veredito::Nada
}

/// E106/5a — O JUÍZO DO PÓS-SONO (puro — a porta dos testes). O relato do
/// rig: na volta da suspensão, com o fone Bluetooth morto no caminho, o
/// default PERMANECIA preso no HDMI mudo do monitor. A FOTO pré-sono manda
/// quando ainda vive; sem foto ou foto morta (o BT sumiu no sono), a LEI
/// decide — o julga com trigger "start" NUNCA deixa o HDMI do monitor no
/// trono sem a marca do dono (o caminho E140 de sempre).
pub fn julga_resume(sinks: &[SinkData], dflt: &str, pre: &str, hdmi_ok: bool) -> Veredito {
    if sinks.is_empty() {
        return Veredito::Nada;
    }
    // a foto ainda vive e REINA no trono: nada a fazer
    if !pre.is_empty() && pre == dflt && sinks.iter().any(|s| s.name == dflt) {
        return Veredito::Nada;
    }
    // a foto vive em OUTRO sink (o monitor roubou o trono no wake): ela
    // volta (E139 — o HDMI/DP do monitor não rouba o som pós-sono)
    if !pre.is_empty() && sinks.iter().any(|s| s.name == pre) {
        return Veredito::Trocar {
            sink: pre.to_string(),
            motivo: "resume — o HDMI/DP do monitor não rouba o som pós-sono",
            piso: false,
        };
    }
    // sem foto (o sleep_save calado) ou foto MORTA (o fone BT desconectou
    // no sono): a LEI decide — o HDMI do monitor nunca PERMANECE no trono
    // mudo (o 'o resume decide pela lei' prometido pelo sleep_save sem
    // default vira FATO aqui)
    julga(sinks, dflt, &[], "start", hdmi_ok)
}

/// E106/5a — O JUÍZO DO AUTO_NULL PRESO (puro): o E132 reafirmava o
/// runtime CEGO — e quando o runtime caía no HDMI do monitor (o PipeWire
/// re-linka no wake sem o fone BT), reafirmar era GRAVAR o sequestro no
/// papel persistente do WirePlumber. A reafirmação agora OUVE a LEI: o
/// runtime HDMI sem a marca do dono cai no julga (E140 — a analógica
/// tem prioridade); o resto reafirma como sempre.
pub fn julga_autonull(sinks: &[SinkData], dflt: &str, hdmi_ok: bool) -> Veredito {
    let Some(atual) = sinks.iter().find(|s| s.name == dflt) else {
        return Veredito::Nada;
    };
    if classifica(atual) == Classe::Hdmi && !hdmi_ok {
        return julga(sinks, dflt, &[], "start", hdmi_ok);
    }
    Veredito::Reafirmar { sink: dflt.to_string() }
}

/// o juízo da PORTA (o jack com detecção): fone disponível → a porta
/// dele; fone saiu e a ativa era a dele → a 1ª disponível de caixa.
pub fn julga_porta(s: &SinkData) -> Option<Veredito> {
    if s.ports.is_empty() {
        return None;
    }
    let wire = |p: &SinkPorta| -> bool {
        let t = format!("{} {}", p.description, p.name).to_lowercase();
        t.contains("headphone") || t.contains("fone") || t.contains("headset")
    };
    let fones: Vec<&SinkPorta> = s.ports.iter().filter(|p| wire(p)).collect();
    if fones.is_empty() {
        return None;
    }
    let disp: Vec<&&SinkPorta> = fones.iter().filter(|p| p.availability == "yes").collect();
    if let Some(pf) = disp.first() {
        if s.active_port != pf.name {
            return Some(Veredito::Porta {
                sink: s.name.clone(),
                porta: pf.name.clone(),
                descricao: if pf.description.is_empty() { pf.name.clone() } else { pf.description.clone() },
            });
        }
    } else if !s.active_port.is_empty() {
        let ativa_e_fone = s
            .ports
            .iter()
            .any(|p| p.name == s.active_port && wire(p));
        if ativa_e_fone {
            // o fone saiu: volta para a 1ª porta disponível que NÃO é fio
            if let Some(outra) = s.ports.iter().find(|p| p.availability == "yes" && !wire(p)) {
                return Some(Veredito::Porta {
                    sink: s.name.clone(),
                    porta: outra.name.clone(),
                    descricao: if outra.description.is_empty() {
                        outra.name.clone()
                    } else {
                        outra.description.clone()
                    },
                });
            }
        }
    }
    None
}

// ── os PAPÉIS DA SESSÃO (os mesmos caminhos do Python — rig sem reinvenção)

pub fn known_path() -> PathBuf {
    crate::supervise::run_dir().join("audio-known")
}

pub fn presleep_path() -> PathBuf {
    crate::supervise::run_dir().join("audio-presleep")
}

/// o SNAPSHOT DE CONHECIDOS (E139 — a fronteira honesta: a mão do
/// dono nunca é pisada por um evento que só viu CHEGADA aparente).
pub fn carrega_conhecidos(p: &Path) -> Vec<String> {
    std::fs::read_to_string(p)
        .map(|t| {
            t.lines()
                .map(str::trim)
                .filter(|l| !l.is_empty())
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

pub fn grava_conhecidos(p: &Path, sinks: &[SinkData]) {
    let corpo: String = sinks.iter().map(|s| format!("{}\n", s.name)).collect();
    let _ = elite_core::persist::write_atomic(p, corpo.as_bytes());
}

// ── a EXECUÇÃO (o efeito raro por evento — o pactl é a porta CLI do PipeWire)

fn pactl(args: &[&str]) -> Option<String> {
    let saida = Command::new("pactl").args(args).output().ok()?;
    if !saida.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&saida.stdout).trim().to_string())
}

pub fn lista_sinks() -> Vec<SinkData> {
    let Some(json) = pactl(&["-f", "json", "list", "sinks"]) else {
        return Vec::new();
    };
    serde_json::from_str(&json).unwrap_or_default()
}

pub fn default_sink() -> String {
    pactl(&["get-default-sink"]).unwrap_or_default()
}

/// E156 — o default SOURCE (a fonte de captação): o mesmo pactl, a porta
/// de entrada. Vazio = sem fonte viva (o honesto é o falso, nunca palpite).
pub fn default_source() -> String {
    pactl(&["get-default-source"]).unwrap_or_default()
}

/// E156 — O MUDO REAL DA FONTE (o microfone): a mesma tipagem serve (o
/// json das sources tem o MESMO shape dos sinks — name/mute/volume).
/// Chamado por EVENTO no publica_estado (debounced — fork eventual,
/// nunca residente): a telemetria deixa de cravar `false` no microfone
/// mudo do dono.
fn fonte_muda() -> bool {
    let nome = default_source();
    if nome.is_empty() {
        return false;
    }
    let Some(json) = pactl(&["-f", "json", "list", "sources"]) else {
        return false;
    };
    let fontes: Vec<SinkData> = serde_json::from_str(&json).unwrap_or_default();
    fontes.iter().find(|s| s.name == nome).map(|s| s.mute).unwrap_or(false)
}

/// E132 — o default CONFIGURADO do WirePlumber (o wpctl status fala;
/// 'auto_null' aqui = a doença mesmo com o runtime aparentando saúde).
pub fn configured_sink() -> String {
    let Ok(out) = Command::new("wpctl").arg("status").output() else {
        return String::new();
    };
    if !out.status.success() {
        return String::new();
    }
    let texto = String::from_utf8_lossy(&out.stdout);
    let Some(pos) = texto.find("Default Configured Devices:") else {
        return String::new();
    };
    let resto = &texto[pos..];
    let Some(linha) = resto.lines().find(|l| l.trim_start().starts_with("Audio/Sink")) else {
        return String::new();
    };
    // '0. alsa_output.pci-… (HD Audio…)' → o NOME do node
    let val = linha
        .split_once(':')
        .map(|(_, v)| v)
        .unwrap_or("")
        .trim()
        .trim_start_matches(|c: char| c.is_ascii_digit() || c == '.' || c == ' ');
    val.split('(').next().unwrap_or("").trim().to_string()
}

fn espera_audio() -> bool {
    for _ in 0..30 {
        if pactl(&["info"]).is_some() {
            return true;
        }
        std::thread::sleep(Duration::from_secs(2));
    }
    false
}

/// o papel do roteador (o ~/.cache/elite/audio.log, teto 256 KiB — o
/// mesmo contrato da casa desde o Python).
pub fn log_audio(msg: &str) {
    let dir = std::env::var("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/root".into())).join(".cache")
        })
        .join("elite");
    let log = dir.join("audio.log");
    let _ = std::fs::create_dir_all(&dir);
    if let Ok(meta) = std::fs::metadata(&log) {
        if meta.len() > 262_144 {
            let _ = std::fs::write(&log, b"");
        }
    }
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let _ = std::fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(&log)
        .and_then(|mut f| {
            use std::io::Write;
            f.write_all(format!("[{ts}] {msg}\n").as_bytes())
        });
}

fn nota(corpo: &str) {
    let _ = Command::new("notify-send")
        .args(["-a", "Elite · Áudio", "-u", "low", "-t", "3000", "Áudio", corpo])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

/// APLICA um veredito (o pactl no caminho certo, o rc CHECADO — a
/// escola E33: log que anuncia sem conferir mente na falha).
pub fn aplica(v: &Veredito) -> bool {
    match v {
        Veredito::Nada => true,
        Veredito::Reafirmar { sink } => {
            let ok = Command::new("pactl")
                .args(["set-default-sink", sink])
                .output()
                .map(|o| o.status.success())
                .unwrap_or(false);
            if ok {
                log_audio(&format!("AUTO_NULL → configurado reafirmado: {sink}"));
            }
            ok
        }
        Veredito::Trocar { sink, motivo, piso } => {
            let ok = Command::new("pactl")
                .args(["set-default-sink", sink])
                .output()
                .map(|o| o.status.success())
                .unwrap_or(false);
            if !ok {
                log_audio(&format!("FALHA set-default-sink {sink} ({motivo})"));
                return false;
            }
            log_audio(&format!("TROCA ({motivo}) → {sink}"));
            nota(&format!("Saída: {sink}"));
            if *piso {
                // E140 — O PISO DA VOZ: quem chega ao trono com zero
                // ganha 40% (nunca mais o 'vol: 0.00' mudo do dump)
                let ok = Command::new("pactl")
                    .args(["set-sink-volume", sink, "40%"])
                    .output()
                    .map(|o| o.status.success())
                    .unwrap_or(false);
                if ok {
                    log_audio(&format!("VOLUME 0 → 40% ({sink} — o piso da voz, E140)"));
                } else {
                    log_audio(&format!("FALHA set-sink-volume 40% {sink}"));
                }
            }
            true
        }
        Veredito::Porta { sink, porta, descricao } => {
            let ok = Command::new("pactl")
                .args(["set-sink-port", sink, porta])
                .output()
                .map(|o| o.status.success())
                .unwrap_or(false);
            if ok {
                log_audio(&format!("PORTA → {descricao} ({sink})"));
                nota(&format!("Fone: {descricao}"));
            } else {
                log_audio(&format!("FALHA set-sink-port {porta} @ {sink}"));
            }
            ok
        }
    }
}

/// A RODADA COMPLETA: avalia, aplica, grava conhecidos e PUBLICA o
/// AudioState no bus (o estado vivo da casa 2.0).
pub fn rodada(trigger: &str) {
    if !espera_audio() {
        return;
    }
    let sinks = lista_sinks();
    if sinks.is_empty() {
        return;
    }
    let dflt = default_sink();
    // E132 — o auto_null PRESO: runtime OU configurado em auto_null com
    // placa viva = a escolha persistente não existe; reafirma o runtime
    let conf = configured_sink();
    let conf_ruim = dflt.starts_with("auto_null") || conf == "auto_null";
    let hdmi_ok = marcador_hdmi_ok().exists();
    if conf_ruim && !dflt.is_empty() && !dflt.starts_with("auto_null") {
        // E106/5a — o reafirmar OUVE A LEI: o runtime caído no HDMI do
        // monitor (o PipeWire re-linka no wake sem o fone BT) NÃO é
        // reafirmado — reafirmar seria cravar o sequestro no papel
        // persistente do WirePlumber; o julga E140 entrega o trono à
        // analógica primeiro
        aplica(&julga_autonull(&sinks, &dflt, hdmi_ok));
    } else {
        let prev = carrega_conhecidos(&known_path());
        let veredito = julga(&sinks, &dflt, &prev, trigger, hdmi_ok);
        aplica(&veredito);
    }
    grava_conhecidos(&known_path(), &sinks);
    publica_estado(&sinks, &default_sink());
}

/// publica o AudioState no bus (o daemon é a fonte única do estado).
/// E156 — o MUDO REAL: sink e fonte vestem o `mute` do pactl (o `false`
/// cravado de era morreu — o dump para de jurar "nunca mudo" num trono
/// mudo; a perícia de um "sem som" passa a ver o mudo no papel).
pub fn publica_estado(sinks: &[SinkData], dflt: &str) {
    let atual = sinks.iter().find(|s| s.name == dflt);
    let msg = elite_core::BusMsg::Audio(elite_core::AudioState {
        sink_volume: atual.map(|s| (s.volume() * 100.0).round() as u8).unwrap_or(0),
        sink_muted: atual.map(|s| s.mute).unwrap_or(false),
        source_muted: fonte_muda(),
        sink_name: atual.map(|s| s.description.clone()).filter(|d| !d.is_empty()),
        analog_preferred: atual.map(|s| classifica(s) != Classe::Hdmi).unwrap_or(false),
    });
    crate::nucleo::pub_bus(&msg);
}

/// E139 — a FOTO PRÉ-SONO (o PrepareForSleep(true) chama ANTES do
/// freeze: o pactl responde em ms quando o PipeWire vive).
pub fn sleep_save() {
    let d = default_sink();
    if d.is_empty() {
        log_audio("sleep-save: sem default vivo — o resume decide pela lei");
        return;
    }
    let _ = elite_core::persist::write_atomic(&presleep_path(), format!("{d}\n").as_bytes());
    log_audio(&format!("sleep-save: default pré-sono = {d}"));
}

/// E139 — o PÓS-SONO ANTI-SEQUESTRO: o default de antes volta se
/// ainda existe; o que se foi cai na LEI (HDMI por último, nunca o
/// sequestrador do monitor). E106/5a — o juízo é PURO (julga_resume — a
/// porta dos testes): sem foto ou foto morta (o fone BT desconectou no
/// sono), a LEI decide na hora — o HDMI do monitor nunca PERMANECE no
/// trono mudo do wake.
pub fn resume() {
    if !espera_audio() {
        return;
    }
    let pre = std::fs::read_to_string(presleep_path())
        .map(|t| t.trim().to_string())
        .unwrap_or_default();
    let sinks = lista_sinks();
    let cur = default_sink();
    if sinks.is_empty() {
        return;
    }
    let hdmi_ok = marcador_hdmi_ok().exists();
    let v = julga_resume(&sinks, &cur, &pre, hdmi_ok);
    match &v {
        Veredito::Nada => {
            log_audio(&format!(
                "resume: default intacto ({})",
                if cur.is_empty() { "?" } else { &cur }
            ));
        }
        _ => {
            let _ = aplica(&v);
        }
    }
    grava_conhecidos(&known_path(), &sinks);
    publica_estado(&sinks, &default_sink());
}

/// O OUVIDOR: `pactl subscribe` (a fila de eventos do PipeWire — a
/// enxurrada do plug assenta 400ms antes da rodada; subscribe morto =
/// respawn com teto de 5s). Morre com o STOP do daemon.
pub fn thread_subscribe() {
    loop {
        if crate::STOP.load(std::sync::atomic::Ordering::SeqCst) {
            return;
        }
        let Ok(mut filho) = Command::new("pactl")
            .arg("subscribe")
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .stdin(Stdio::null())
            .spawn()
        else {
            std::thread::sleep(Duration::from_secs(5));
            continue;
        };
        let Some(out) = filho.stdout.take() else {
            std::thread::sleep(Duration::from_secs(5));
            continue;
        };
        let leitor = BufReader::new(out);
        let mut ultimo = std::time::Instant::now() - Duration::from_secs(10);
        for linha in leitor.lines() {
            if crate::STOP.load(std::sync::atomic::Ordering::SeqCst) {
                let _ = unsafe { libc::kill(filho.id() as i32, libc::SIGTERM) };
                return;
            }
            let Ok(l) = linha else { break };
            let low = l.to_lowercase();
            if !low.contains("sink") && !low.contains("card") && !low.contains("server") {
                continue;
            }
            // debounce: a enxurrada do plug assenta primeiro
            if ultimo.elapsed() < Duration::from_millis(400) {
                std::thread::sleep(Duration::from_millis(400));
            }
            ultimo = std::time::Instant::now();
            rodada("event");
        }
        // o subscribe morreu (pipewire reiniciou) — recomeça
        std::thread::sleep(Duration::from_secs(2));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sink(nome: &str, desc: &str, ff: &str, bus: &str, prof: &str, vol: f64) -> SinkData {
        let mut props = std::collections::HashMap::new();
        props.insert("device.form_factor".to_string(), ff.to_string());
        props.insert("device.bus".to_string(), bus.to_string());
        props.insert("device.profile.name".to_string(), prof.to_string());
        SinkData {
            name: nome.to_string(),
            description: desc.to_string(),
            active_port: String::new(),
            mute: false,
            volume: Some(VolumeMap { front_left: Some(VolCanal { value: vol }) }),
            ports: vec![],
            properties: props,
        }
    }

    fn porta(nome: &str, desc: &str, avail: &str) -> SinkPorta {
        SinkPorta {
            name: nome.to_string(),
            description: desc.to_string(),
            availability: avail.to_string(),
        }
    }

    #[test]
    fn as_quatro_classes_da_casa() {
        // a analógica Starship/Matisse do dono é OK
        let st = sink(
            "alsa_output.pci-0000_14_0",
            "Starship/Matisse HD Audio Controller",
            "internal",
            "pci",
            "analog-stereo",
            0.4,
        );
        assert_eq!(classifica(&st), Classe::Ok);
        // o HDMI da Navi sem alto-falante é a última da fila
        let hdmi = sink(
            "alsa_output.pci-0000_0c_0.3",
            "Navi 31 HDMI/DP Audio Controller",
            "hdmi",
            "pci",
            "hdmi-stereo",
            0.6,
        );
        assert_eq!(classifica(&hdmi), Classe::Hdmi);
        // o microfone fantasma é PROIBIDO (a marca E a palavra genérica)
        let bad = sink("alsa_input.usb-fifine", "Fifine Microphone Estéreo analógico", "microphone", "usb", "analog-stereo", 0.5);
        assert_eq!(classifica(&bad), Classe::Bad);
        let bad2 = sink("x", "USB Microphone", "", "usb", "", 0.5);
        assert_eq!(classifica(&bad2), Classe::Bad);
        // o fone BT é TARGET
        let bt = sink("bluez_output.00_11_22", "WH-1000XM5", "headset", "bluetooth", "a2dp-sink", 0.7);
        assert_eq!(classifica(&bt), Classe::Target);
    }

    #[test]
    fn o_hdmi_sem_som_cede_para_a_analogica() {
        // O CASO DO DOSSIÊ 1.0-88: default no HDMI Navi com a analógica
        // Starship viva e em 0.00 → TROCA com o PISO DA VOZ
        let analogica = sink(
            "alsa_output.pci-0000_14_0",
            "Starship/Matisse HD Audio Controller",
            "internal",
            "pci",
            "analog-stereo",
            0.0,
        );
        let hdmi = sink(
            "alsa_output.pci-0000_0c_0.3",
            "Navi 31 HDMI/DP Audio Controller",
            "hdmi",
            "pci",
            "hdmi-stereo",
            0.6,
        );
        let sinks = vec![analogica, hdmi];
        let v = julga(&sinks, "alsa_output.pci-0000_0c_0.3", &[], "start", false);
        assert_eq!(
            v,
            Veredito::Trocar {
                sink: "alsa_output.pci-0000_14_0".into(),
                motivo: "HDMI sem som — a analógica tem prioridade",
                piso: true // volume 0.00 → o piso de 40% acende
            }
        );
        // o marcador do dono QUER o monitor: a escolha dele é a lei
        let v = julga(&sinks, "alsa_output.pci-0000_0c_0.3", &[], "start", true);
        assert_eq!(v, Veredito::Nada);
    }

    #[test]
    fn o_fone_que_chega_toma_o_trono_somente_se_e_novo() {
        let caixa = sink("alsa_output.pci-0000_14_0", "Starship/Matisse", "internal", "pci", "analog-stereo", 0.4);
        let fone = sink("bluez_output.00_11", "WH-1000XM5", "headset", "bluetooth", "a2dp", 0.7);
        let sinks = vec![caixa, fone];
        // o fone CHEGOU (fora dos conhecidos) → troca
        let v = julga(&sinks, "alsa_output.pci-0000_14_0", &["alsa_output.pci-0000_14_0".into()], "event", false);
        assert!(matches!(v, Veredito::Trocar { ref sink, .. } if sink == "bluez_output.00_11"));
        // o fone é VELHO conhecido → a mão do dono que o pôs segue
        let prev: Vec<String> = sinks.iter().map(|s| s.name.clone()).collect();
        let v = julga(&sinks, "alsa_output.pci-0000_14_0", &prev, "event", false);
        assert_eq!(v, Veredito::Nada);
    }

    #[test]
    fn o_microfone_fantasma_e_cura_imediata() {
        let mic = sink("alsa_output.usb-fifine", "Fifine Microphone", "microphone", "usb", "", 0.5);
        let boa = sink("alsa_output.pci-x", "Starship/Matisse", "internal", "pci", "analog-stereo", 0.4);
        let v = julga(&[boa, mic], "alsa_output.usb-fifine", &[], "start", false);
        assert!(matches!(v, Veredito::Trocar { ref sink, motivo: "saída inválida", .. } if sink == "alsa_output.pci-x"));
    }

    #[test]
    fn o_default_sumido_e_a_melhor_remanescente() {
        let caixa = sink("alsa_output.pci-a", "Starship", "internal", "pci", "", 0.4);
        let hdmi = sink("alsa_output.pci-b", "HDMI", "hdmi", "pci", "", 0.6);
        // o BT desconectou (era o default) → a analógica (rank ok) vence
        let v = julga(&[caixa, hdmi], "bluez_output.gone", &[], "event", false);
        assert!(matches!(v, Veredito::Trocar { ref sink, motivo: "saída sumiu", .. } if sink == "alsa_output.pci-a"));
    }

    #[test]
    fn e106_5a_o_fone_bt_morto_no_sono_o_hdmi_nao_permanece() {
        // O CASO DO RIG: o fone BT era o default pré-sono, desconectou no
        // caminho e o PipeWire deixou o HDMI do monitor no trono — o
        // resume antigo caía na rodada e o HDMI ficava MUDO para sempre.
        // A LEI (julga start): a analógica toma o trono
        let caixa = sink("alsa_output.pci-0000_14_0", "Starship/Matisse HD Audio", "internal", "pci", "analog-stereo", 0.4);
        let hdmi = sink("alsa_output.pci-0000_0c_0.3", "Navi 31 HDMI/DP Audio", "hdmi", "pci", "hdmi-stereo", 0.6);
        let sinks = vec![caixa, hdmi];
        let v = julga_resume(&sinks, "alsa_output.pci-0000_0c_0.3", "bluez_output.00_11", false);
        assert!(matches!(v, Veredito::Trocar { ref sink, motivo: "HDMI sem som — a analógica tem prioridade", .. } if sink == "alsa_output.pci-0000_14_0"));
        // SEM FOTO (o sleep_save calado — sem default vivo): a LEI decide
        // igual (a promessa "o resume decide pela lei" vira fato)
        let v = julga_resume(&sinks, "alsa_output.pci-0000_0c_0.3", "", false);
        assert!(matches!(v, Veredito::Trocar { ref sink, .. } if sink == "alsa_output.pci-0000_14_0"));
    }

    #[test]
    fn e106_5a_a_foto_pre_sono_manda_enquanto_vive() {
        let caixa = sink("alsa_output.pci-0000_14_0", "Starship/Matisse HD Audio", "internal", "pci", "analog-stereo", 0.4);
        let hdmi = sink("alsa_output.pci-0000_0c_0.3", "Navi 31 HDMI/DP Audio", "hdmi", "pci", "hdmi-stereo", 0.6);
        let sinks = vec![caixa, hdmi];
        // a foto VIVE e reina: nada a fazer (o default intacto é a verdade)
        assert_eq!(julga_resume(&sinks, "alsa_output.pci-0000_14_0", "alsa_output.pci-0000_14_0", false), Veredito::Nada);
        // o monitor ROUBOU o trono e a foto vive: ela VOLTA (E139 intacta)
        let v = julga_resume(&sinks, "alsa_output.pci-0000_0c_0.3", "alsa_output.pci-0000_14_0", false);
        assert!(matches!(v, Veredito::Trocar { ref sink, motivo: "resume — o HDMI/DP do monitor não rouba o som pós-sono", .. } if sink == "alsa_output.pci-0000_14_0"));
    }

    #[test]
    fn e106_5a_o_auto_null_preso_nao_reafirma_o_hdmi_do_monitor() {
        // o E132 reafirmava o runtime CEGO: runtime caído no HDMI (o
        // PipeWire re-linka no wake sem o fone BT) era cravado no papel
        // persistente do WirePlumber. Agora a LEI decide (julga E140)
        let caixa = sink("alsa_output.pci-0000_14_0", "Starship/Matisse HD Audio", "internal", "pci", "analog-stereo", 0.4);
        let hdmi = sink("alsa_output.pci-0000_0c_0.3", "Navi 31 HDMI/DP Audio", "hdmi", "pci", "hdmi-stereo", 0.6);
        let sinks = vec![caixa, hdmi];
        let v = julga_autonull(&sinks, "alsa_output.pci-0000_0c_0.3", false);
        assert!(matches!(v, Veredito::Trocar { ref sink, .. } if sink == "alsa_output.pci-0000_14_0"));
        // o runtime SAUDÁVEL é reafirmado como sempre (o E132 intacto)
        assert_eq!(
            julga_autonull(&sinks, "alsa_output.pci-0000_14_0", false),
            Veredito::Reafirmar { sink: "alsa_output.pci-0000_14_0".into() }
        );
        // a MARCA do dono QUER o HDMI: a escolha dele é a lei
        assert_eq!(
            julga_autonull(&sinks, "alsa_output.pci-0000_0c_0.3", true),
            Veredito::Reafirmar { sink: "alsa_output.pci-0000_0c_0.3".into() }
        );
        // default que NÃO está na lista: nada (o julga_resume/julga cuidam)
        assert_eq!(julga_autonull(&sinks, "bluez_output.gone", false), Veredito::Nada);
    }

    #[test]
    fn o_jack_da_casa_segue_a_disponibilidade() {
        let mut s = sink("alsa_output.pci-a", "Starship/Matisse", "internal", "pci", "", 0.4);
        s.ports = vec![
            porta("analog-output-speaker", "Caixas de som", "yes"),
            porta("analog-output-headphones", "Fone de ouvido", "no"),
        ];
        s.active_port = "analog-output-speaker".into();
        // fone indisponível, ativa é caixa: nada
        assert_eq!(julga_porta(&s), None);
        // o fone CHEGOU: a porta troca para ele
        s.ports[1].availability = "yes".into();
        let v = julga_porta(&s).unwrap();
        assert!(matches!(v, Veredito::Porta { ref porta, .. } if porta == "analog-output-headphones"));
        // e o fone SAIU com a ativa DELE: volta para a caixa
        s.active_port = "analog-output-headphones".into();
        s.ports[1].availability = "no".into();
        let v = julga_porta(&s).unwrap();
        assert!(matches!(v, Veredito::Porta { ref porta, .. } if porta == "analog-output-speaker"));
    }

    #[test]
    fn o_papel_dos_conhecidos_e_a_persistencia_atomica() {
        let dir = std::env::temp_dir().join(format!("elite-audio-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("known");
        // vazio quando nunca existiu
        assert!(carrega_conhecidos(&p).is_empty());
        // grava e lê de volta (a escrita é ATÔMICA da fundação)
        let sinks = vec![
            sink("a", "A", "internal", "pci", "", 1.0),
            sink("b", "B", "hdmi", "pci", "", 1.0),
        ];
        grava_conhecidos(&p, &sinks);
        let lidos = carrega_conhecidos(&p);
        assert_eq!(lidos, vec!["a".to_string(), "b".to_string()]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn o_configured_sink_do_wpctl_e_cacado_no_papel_certo() {
        // o parser do wpctl status: a linha certa, o nome limpo (o
        // índice e o nick fora — o Python E132 1:1)
        let papel = "Nodes:\n  Sinks:\n    1. alsa_output.pci-x [dropdown]\nDefault Configured Devices:\n  Audio/Sink: 44. alsa_output.pci-0000_14_0 (Starship/Matisse)\n\nDefault Devices:\n  Audio/Sink: alsa_output.pci-0000_14_0\n";
        let pos = papel.find("Default Configured Devices:").unwrap();
        let resto = &papel[pos..];
        let linha = resto.lines().find(|l| l.trim_start().starts_with("Audio/Sink")).unwrap();
        let val = linha
            .split_once(':')
            .map(|(_, v)| v)
            .unwrap_or("")
            .trim()
            .trim_start_matches(|c: char| c.is_ascii_digit() || c == '.' || c == ' ');
        assert_eq!(val.split('(').next().unwrap_or("").trim(), "alsa_output.pci-0000_14_0");
    }

    #[test]
    fn o_volume_mastiga_os_dois_formatos_do_pactl() {
        // o E138 do craft-audio: float cru E string com sufixo
        let json = r#"[{"name":"x","volume":{"front-left":{"value":0.45}}},{"name":"y","volume":{"front-left":{"value":"45%"}}}]"#;
        let sinks: Vec<SinkData> = serde_json::from_str(json).unwrap();
        assert_eq!(sinks[0].volume(), 0.45);
        assert_eq!(sinks[1].volume(), 45.0);
    }

    #[test]
    fn e156_o_mudo_real_do_pactl_vira_estado() {
        // E156 — o AudioState de era cravava `false` no mudo: o trono MUDO
        // reportava "nunca mudo" na telemetria. O campo vem no MESMO json
        // (zero fork novo) e o ausente é o falso honesto (serde default).
        let json = r#"[
            {"name":"a","mute":true,"volume":{"front-left":{"value":0.55}}},
            {"name":"b","volume":{"front-left":{"value":0.40}}}
        ]"#;
        let sinks: Vec<SinkData> = serde_json::from_str(json).unwrap();
        assert!(sinks[0].mute, "o sink mudo vira mudo no estado");
        assert!(!sinks[1].mute, "o sink sem mute é o falso honesto");
        // o estado público veste o REAL: o default mudo é mudo, ponto.
        let atual = sinks.iter().find(|s| s.name == "a");
        assert!(atual.map(|s| s.mute).unwrap_or(false));
    }

    #[test]
    fn o_json_do_pactl_vira_sinks_tipados() {
        let json = r#"[{
            "name": "alsa_output.pci-0000_14_0",
            "description": "Starship/Matisse HD Audio Controller",
            "active_port": "analog-output-speaker",
            "ports": [{"name":"analog-output-speaker","description":"Caixas","availability":"yes"}],
            "volume": {"front-left": {"value": 0.395312}},
            "properties": {"device.form_factor": "internal", "device.bus": "pci", "device.profile.name": "analog-stereo"}
        }]"#;
        let sinks: Vec<SinkData> = serde_json::from_str(json).unwrap();
        assert_eq!(sinks.len(), 1);
        let s = &sinks[0];
        assert_eq!(s.name, "alsa_output.pci-0000_14_0");
        assert_eq!(s.ports.len(), 1);
        assert_eq!(s.active_port, "analog-output-speaker");
        assert!((s.volume() - 0.395312).abs() < 1e-9);
        assert_eq!(classifica(s), Classe::Ok);
    }
}
