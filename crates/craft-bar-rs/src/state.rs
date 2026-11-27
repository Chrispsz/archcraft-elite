// ELITE · craft-bar-rs — state.rs (E140). O NÚCLEO PURO da top bar:
// TUDO que a barra decide mora aqui como função std-only testável em
// qualquer lugar (a lei do degrau da dock E132 — a UI apenas VESTE as
// decisões; nenhum juízo mora na camada GTK).
//
// O QUE MORA AQUI:
//   · O RELÓGIO pt_BR DE FÁBRICA (a cura A2 do dossiê): a data é
//     composta em pt_BR pelas TABELAS da casa ("Seg, 23 Nov · 19:30")
//     — não existe locale de processo, não existe format-alt, não
//     existe o texto que muda ao clicar. O dia/mês em inglês do waybar
//     (o strftime roda no locale DO PROCESSO) morre por desenho: as
//     palavras são da casa, o texto é UM só em qualquer clique.
//   · A CONTA DO CALENDÁRIO sem dependência: dias-desde-época →
//     civil (ano/mês/dia) + dia da semana (o algoritmo de Hinnant,
//     reinterpretado por days_from_civil — a prova é o teste contra
//     datas conhecidas, inclusive o limite de ano bissexto).
//   · OS PARSERS dos aliados da casa: `wpctl get-volume` (volume+MUDO
//     em UMA linha), `nmcli -t device` (o estado da rede SEM ícone que
//     some — Cabo/Wi-Fi/Desligado é SEMPRE um dos três, o botão é
//     PERSISTENTE por construção), `bluetoothctl show` (Powered:),
//     `craft-game pill` (o JSON mínimo do waybar: text/class/tooltip —
//     o contrato é ESTE e a barra é cliente dele, sem serde: o par
//     aspas-vírgula do "text" é o contrato estável da família).
//   · O JUÍZO DOS ÍCONES (E147 — NOMES DE ÍCONE GTK em vez dos
//     codepoints Nerd Font: a fonte GTK padrão não fala Nerd e o
//     '\uf085 2' da tela do dono era o réu — o tema Papirus/GNOME da
//     casa tem todos os nomes, o render NUNCA mais quebra).
//   · O DEBOUNCE DO DRAWER (a cura A1) MORREU com o próprio drawer: o
//     botão de apps dispara o fuzzel DIRETO (1.0-106 — o wrapper
//     craft-apps fica para o W-d do rc.xml, a barra não empurra
//     gaveta nenhuma);
//   · A BATERIA pelo /sys (capacity + status) — parâmetro path, a
//     porta dos testes.
//
// ESCOPO HONESTO (o que NÃO mora aqui — nomeado):
//   ✗ roteamento de áudio (a casa do roteador é o craft-audio-route,
//     shell, com o snapshot E139 — a barra só MOSTRA e muta);
//   ✗ o EDITOR COMPLETO de conexões (nm-connection-editor é a tela de
//     verdade — o SELETOR RÁPIDO de 1.0-106 é o craft-pick da casa,
//     armado pelos parses daqui); 
//   ✗ o veredito do modo de jogo (o elite-daemon é o dono; a barra
//     acende o pill no SIGRTMIN+8 que ELE manda).

use std::path::Path;

use elite_core::MediaState;

// ── O BUS 2.0 (os estados que o daemon publica — o juízo de VESTIR) ────

/// O TEXTO DO PLAYER pelo estado do bus (2.0: zero playerctl, o
/// PropertiesChanged do MPRIS chega pelo fio; o pill some sem mídia).
/// 1.0-101 — A PÍLULA REFINADA do audit 99: ícone de STATUS como NOME
/// de ícone GTK (media-playback-start/pause — o glifo Nerd \u{f047b}
/// era o réu da era E147 e morre aqui também: a fonte GTK não o tem),
/// o rótulo é "Artista - Título" (a ordem que o dono lê) TRUNCADO em
/// 28 caracteres com o texto INTEIRO no tooltip do hover.
pub struct PilulaMidia {
    /// o ícone de status GTK (tocando/pausado) para o Image da barra.
    pub icone: &'static str,
    /// "Artista - Título" ≤ 28 chars (a largura da barra manda).
    pub texto: String,
    /// o texto COMPLETO (a lei da casa: nada de recorte no tooltip).
    pub tooltip: String,
}

pub fn media_pill(m: &MediaState) -> Option<PilulaMidia> {
    if m.player.is_none() && m.title.is_none() {
        return None; // sem mídia: o botão SAI (o assento é da sessão)
    }
    let titulo = m.title.clone().unwrap_or_else(|| "mídia".into());
    let artista = m.artist.clone().unwrap_or_default();
    let inteiro = if artista.is_empty() {
        titulo.clone()
    } else {
        format!("{artista} - {titulo}")
    };
    // a largura da barra: 28 chars no TOTAL (o pill não empurra o
    // relógio para fora da tela; o hover diz o inteiro)
    let texto = if inteiro.chars().count() > 28 {
        let t: String = inteiro.chars().take(27).collect();
        format!("{t}…")
    } else {
        inteiro.clone()
    };
    let icone = if m.playing {
        "media-playback-start-symbolic"
    } else {
        "media-playback-pause-symbolic"
    };
    let estado = if m.playing { "tocando" } else { "pausado" };
    let tooltip = match m.player.as_deref() {
        Some(p) => format!("{inteiro} · {p} ({estado})"),
        None => format!("{inteiro} ({estado})"),
    };
    Some(PilulaMidia { icone, texto, tooltip })
}

// 1.0-93 — AS PÍLULAS DA MESA E O TÍTULO ATIVO SAIRAM DA BARRA (a ordem
// do dono, rig da 1.0-92: os botões '1 2 3 4' duplicavam o scroll/atalhos
// do labwc e o título duplicava a moldura da janela — a troca de mesa
// mora no scroll/atalhos W-1..4 do rc.xml, a barra fica LIMPA).

// ── O RELÓGIO pt_BR (a palavra é da casa, nunca do locale) ─────────────

/// Os dias da semana ABREVIADOS em pt_BR (índice = dias-desde-época
/// mod 7, com 1970-01-01 = quinta-feira = índice 4).
pub const DIAS_PT: [&str; 7] = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"];
/// Os meses ABREVIADOS em pt_BR (índice 1-12 — "Jan"… "Dez").
pub const MESES_PT: [&str; 12] = [
    "Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez",
];

/// A DATA da casa: "Seg, 23 Nov · 19:30" (a cura A2 — o texto é UM
/// só; clicar não alterna NADA). Os argumentos são o civil + o dia da
/// semana 0-6 (Dom=0) para a porta dos testes; a UI os tira do epoch.
pub fn relogio_ptbr(wday: u32, dia: u32, mes: u32, hora: u32, min: u32) -> String {
    let wd = DIAS_PT[(wday % 7) as usize];
    let mo = MESES_PT[(mes.clamp(1, 12) - 1) as usize];
    format!("{}, {:02} {} · {:02}:{:02}", wd, dia, mo, hora, min)
}

/// O civil (ano, mês, dia) a partir dos dias-desde-época (a via
/// canônica de Hinnant — a era antes de 1970 nunca é pedida aqui, mas
/// o algoritmo cobre; o teste crava as datas conhecidas).
/// E151 — cfg(test): o binário da barra lê o relógio do glib
/// (DateTime::now_local) — a aritmética civil é dos CONTRATOS (o teste
/// crava as datas conhecidas); no release ela não existe (zero
/// dead_code na gui, a diretriz do dono).
#[cfg(test)]
pub fn civil_de_dias(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64; // [0, 146096]
    let yoe = (doe - doe / 1460 - doe / 36524 + doe / 146_096) / 365; // [0, 399]
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32; // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32; // [1, 12]
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// O dia da semana (0-6, Dom=0) dos dias-desde-época: 1970-01-01 foi
/// quinta (4); o resto é a aritmética do calendário.
/// E151 — cfg(test) idem (o comentário da acima: os contratos são o
/// consumidor; o release não carrega aritmética que ninguém chama).
#[cfg(test)]
pub fn dia_semana(dias: i64) -> u32 {
    ((dias + 4).rem_euclid(7)) as u32
}

// ── O ÁUDIO pelo wpctl (a cura A3 do lado da barra) ────────────────────

/// O par (volume 0.0-1.0+over, MUDO) da linha do `wpctl get-volume`:
/// "Volume: 0.45" / "Volume: 1.50 [MUTED]". None = saída inesperada
/// (a barra CONSERVA o estado anterior — um wpctl engasgado nunca
/// apaga o que o dono vê).
pub fn parse_volume_wpctl(s: &str) -> Option<(f64, bool)> {
    let linha = s.lines().next()?.trim();
    let resto = linha.strip_prefix("Volume:")?.trim();
    let mudo = resto.contains("[MUTED]");
    let num: &str = resto
        .split_whitespace()
        .next()
        // o sufixo '%' nunca vem do wpctl — mas se VIER (a lição do
        // craft-audio: '45%' derrubou o Python com float('45%')), a
        // casa mastiga: o juízo não morre por causa de um sufixo
        .map(|t| t.trim_end_matches('%'))?;
    let v: f64 = num.parse().ok()?;
    Some((v, mudo))
}

// E147 — O FIM DOS GLIFOS NERD FONT NA BARRA (a evidência do dono: o
// '\uf085 2' na tela era o NOME do codepoint que a fonte GTK padrão
// não contém — Inter/Adwaita Sans não fala Nerd Font; o waybar da era
// antiga só acertava porque o CSS dele pede JetBrainsMono NF por
// nome). A casa agora veste SÓ NOMES DE ÍCONE GTK (Image::from_icon_name)
// — o Papirus/GNOME da casa tem todos os nomes abaixo, o render NUNCA
// quebra de novo, e a fonte da barra é a do sistema sem juramento de
// glyph.

/// O ÍCONE do VOLUME (nome de ícone GTK, não glifo): mudo = muted ·
/// baixo (<0.34) = low · alto = high.
pub fn icone_volume(v: f64, mudo: bool) -> &'static str {
    if mudo {
        "audio-volume-muted-symbolic"
    } else if v < 0.34 {
        "audio-volume-low-symbolic"
    } else {
        "audio-volume-high-symbolic"
    }
}

/// O ÍCONE do MICROFONE: vivo = sensitivity-high · mudo = muted (o
/// realce visual do mudo é a classe .muted do CSS — a gramática vermelha).
pub fn icone_mic(mudo: bool) -> &'static str {
    if mudo {
        "microphone-sensitivity-muted-symbolic"
    } else {
        "microphone-sensitivity-high-symbolic"
    }
}

// ── A REDE PERSISTENTE (a cura A4 — o botão NUNCA sai da barra) ────────

/// O estado da rede da casa: exatamente TRÊS estados, TODOS com glifo
/// e tooltip — não existe o estado "ícone sumiu" (o waybar escondia o
/// módulo no off; aqui o assento é por construção).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EstadoRede {
    /// cabo ethernet conectado (glifo uf6ff, o network-wired FA).
    Cabo,
    /// Wi-Fi conectado (glifo uf1eb — o tooltip leva o nome da rede).
    Wifi,
    /// sem rede NENHUMA (cabo fora + Wi-Fi desligado/sem sinal — o
    /// glifo uf92d da E134, o "Wi-Fi desligado" que o dono pediu).
    Desligado,
}

/// O estado da rede da saída do `nmcli -t -f DEVICE,TYPE,STATE,CONNECTION
/// device status` (uma linha por placa, campos por ':'). O julgamento:
/// lo não é rede; qualquer ethernet connected = Cabo; senão qualquer
/// wifi connected = Wifi; todo o resto (unavailable/disconnected/off)
/// desemboca no Desligado PERSISTENTE — o tooltip nomeia o estado e o
/// clique abre o iwgtk (Wi-Fi) / nm-connection-editor (conexões), as
/// ferramentas DE VERDADE da diretriz do dossiê.
pub fn estado_rede_nmcli(saida: &str) -> EstadoRede {
    let mut wifi = false;
    for linha in saida.lines() {
        let c: Vec<&str> = linha.split(':').collect();
        if c.len() < 3 {
            continue;
        }
        let (dev, tipo, estado) = (c[0], c[1], c[2]);
        if dev == "lo" || tipo == "loopback" {
            continue;
        }
        if tipo == "ethernet" && estado == "connected" {
            return EstadoRede::Cabo;
        }
        if tipo == "wifi" && estado == "connected" {
            wifi = true;
        }
    }
    if wifi {
        EstadoRede::Wifi
    } else {
        EstadoRede::Desligado
    }
}

/// O NOME da conexão Wi-Fi ativa (para o tooltip) — None quando não há.
pub fn essid_nmcli(saida: &str) -> Option<String> {
    for linha in saida.lines() {
        let c: Vec<&str> = linha.split(':').collect();
        if c.len() >= 4 && c[1] == "wifi" && c[2] == "connected" && !c[3].is_empty() {
            return Some(c[3].to_string());
        }
    }
    None
}

/// O ÍCONE do estado da rede (nomes GTK — a família visual sobrevive
/// sem Nerd Font: o cabo tem fio, o Wi-Fi tem sinal, o off é o offline).
pub fn icone_rede(e: EstadoRede) -> &'static str {
    match e {
        EstadoRede::Cabo => "network-wired-symbolic",
        EstadoRede::Wifi => "network-wireless-signal-excellent-symbolic",
        EstadoRede::Desligado => "network-wireless-offline-symbolic",
    }
}

/// O tooltip do estado da rede (o que o dono lê ao parar o mouse).
/// 1.0-106 — O MAPA NOVO DO CLIQUE (a ordem do dono: esquerdo é o
/// SELETOR RÁPIDO da casa, meio o editor completo, direito alterna a
/// CONEXÃO ATIVA — a ação de 1 clique sem janela nenhuma).
pub fn tooltip_rede(e: EstadoRede, essid: Option<&str>, wifi_on: Option<bool>) -> String {
    let radio = match wifi_on {
        Some(true) => " · Wi-Fi ligado",
        Some(false) => " · Wi-Fi DESLIGADO",
        None => "",
    };
    let mapa = "clique: seletor rápido · meio: editor · direito: ligar/desligar a conexão ativa";
    match e {
        EstadoRede::Cabo => format!("Rede cabeada conectada{radio} — {mapa}"),
        EstadoRede::Wifi => format!("{}{radio} — {mapa}", essid.unwrap_or("Wi-Fi conectado")),
        EstadoRede::Desligado => match wifi_on {
            Some(false) => format!("Wi-Fi desligado — {mapa}"),
            _ => format!("Sem conexão{radio} — {mapa}"),
        },
    }
}

// ── 1.0-106 — O SELETOR RÁPIDO DE REDE (o esquerdo da barra: o craft-pick
//    da casa armado pelos parses daqui — a conexão em 1 CLIQUE, sem
//    janela de editor para trocar de Wi-Fi) ──────────────────────

// ── 1.0-109 — A LEI DA CONEXÃO PRINCIPAL DESCEU PARA A FUNDAÇÃO ────────
//      O craft-net (o seletor de 1 clique da diretriz) e o direito da
//      top bar vestem o MESMO julgamento: conexao_principal /
//      conteudo_last_net / le_last_net / dev_para_religar (e os verbos
//      alterna/religa) moram em elite_core::rede — uma lei só.

// ── O BLUETOOTH (o par dedicated da diretriz) ──────────────────────────

/// O Bluetooth está LIGADO na saída do `bluetoothctl show`? (procura a
/// linha "Powered: yes" — a casa só lê o estado, quem liga/desliga é o
/// blueman-manager, a ferramenta de verdade que o clique abre).
pub fn bt_ligado(saida: &str) -> bool {
    saida
        .lines()
        .any(|l| l.trim().eq_ignore_ascii_case("powered: yes"))
}

// ── O JSON MÍNIMO da família (game) ──────────────────────

/// O valor de "text" do JSON do waybar que a família craft-* emite
/// ({"text": "…", "class": "…", "tooltip": "…"} — sem serde: o par
/// aspas é o contrato; scape de aspas não existe na família, os
/// textos são glifos e nomes). None/alguns vazio = o pill SAI (o
/// assento só existe com conteúdo — a lei da era waybar mantida).
pub fn json_text(s: &str) -> Option<String> {
    let i = s.find("\"text\"")?;
    let resto = &s[i + "\"text\"".len()..];
    let dp = resto.find(':')?;
    let depois = &resto[dp + 1..];
    let abre = depois.find('"')?;
    let conteudo = &depois[abre + 1..];
    let fecha = conteudo.find('"')?;
    let txt = &conteudo[..fecha];
    if txt.is_empty() {
        None
    } else {
        Some(txt.to_string())
    }
}

// ── E149 · O MAPA DIRETO (a diretriz do dono: o clique ESQUERDO abre
//    a FERRAMENTA de verdade do módulo — pwvucontrol/iwgtk/blueman — e
//    o DIREITO a ação rápida; os popovers customizados da casa morrem
//    com os seus parsers de LISTA — o rádio fica, o toggle o usa) ──

/// O PARSE do rádio do `nmcli radio wifi` ("enabled"/"disabled" — a
/// verdade que o toggle rápido do clique direito lê antes de inverter;
/// a saída inesperada é None honesto).
pub fn parse_wifi_radio(saida: &str) -> Option<bool> {
    let t = saida.trim();
    if t.eq_ignore_ascii_case("enabled") {
        Some(true)
    } else if t.eq_ignore_ascii_case("disabled") {
        Some(false)
    } else {
        None
    }
}

// ── E149 · A FOTO DE ÁUDIO (o NÚCLEO PURO que alimenta o ÍCONE do
//    botão e os toggles rápidos — o mixer completo mora no pwvucontrol,
//    a ferramenta dedicada que o clique esquerdo abre; os defaults dos
//    dois lados seguem sendo a verdade que a barra veste) ────────────

/// Um dispositivo de áudio do `wpctl status` (nome do nó, volume,
/// mudo, é o padrão? — o id PipeWire era da era das listas; o ícone
/// da barra só veste os defaults, E149).
#[derive(Debug, Clone, PartialEq)]
pub struct DispositivoAudio {
    pub nome: String,
    pub vol: f64,
    pub mudo: bool,
    pub padrao: bool,
}

/// O PARSE do `wpctl status` (as seções Sinks: e Sources: da árvore;
/// as linhas de dados têm a forma `│ ├─ * 76. nome [vol: 0.60]` — o
/// '*' é o padrão, o id é o primeiro número do texto, o nome vai até o
/// `[vol:`; `[MUTED]` quando presente é a verdade do mudo). As linhas
/// "Monitor of" (loopback de sink dentro de Sources) SAEM — não são
/// dispositivo escolhível, é o eco da saída.
pub fn parse_wpctl_status(saida: &str) -> (Vec<DispositivoAudio>, Vec<DispositivoAudio>) {
    let mut sinks: Vec<DispositivoAudio> = Vec::new();
    let mut fontes: Vec<DispositivoAudio> = Vec::new();
    let mut secao = 0u8; // 0 = fora · 1 = Sinks · 2 = Sources
    for linha in saida.lines() {
        let t = linha.trim();
        // a árvore do wpctl veste os dois lados da linha (│ ├─ … ─): o
        // CABEÇALHO é julgado pelos glifos FORA (os dados entram pela
        // porta da parse_linha_dispositivo, que lê a linha crua)
        let fim = t
            .trim_start_matches(|c: char| {
                c == '│' || c == '├' || c == '└' || c == '─' || c == ' '
            })
            .trim_end_matches(|c: char| {
                c == '│' || c == '├' || c == '└' || c == '─' || c == ' '
            });
        let fim = fim.trim();
        if fim == "Sinks:" {
            secao = 1;
            continue;
        }
        if fim == "Sources:" {
            secao = 2;
            continue;
        }
        if fim == "Devices:"
            || fim == "Endpoints:"
            || fim == "Streams:"
            || fim == "Audio"
            || fim == "Video"
            || fim == "Settings"
        {
            secao = 0;
            continue;
        }
        if secao == 0 {
            continue;
        }
        if let Some(d) = parse_linha_dispositivo(linha) {
            if d.nome.starts_with("Monitor of") {
                continue;
            }
            if secao == 1 {
                sinks.push(d);
            } else {
                fontes.push(d);
            }
        }
    }
    (sinks, fontes)
}

/// UMA linha de dispositivo do wpctl status (a porta dos testes):
/// devolve o DispositivoAudio ou None quando a linha não é de dados.
pub fn parse_linha_dispositivo(linha: &str) -> Option<DispositivoAudio> {
    // o id é o PRIMEIRO número seguido de ponto (os glifos da árvore
    // nunca são dígitos — a fronteira é honesta)
    let chars: Vec<char> = linha.chars().collect();
    let mut i = 0usize;
    while i < chars.len() && !chars[i].is_ascii_digit() {
        i += 1;
    }
    if i >= chars.len() {
        return None;
    }
    while i < chars.len() && chars[i].is_ascii_digit() {
        i += 1;
    }
    // o ponto + o espaço fecham o id ("76. "); sem eles é lixo (ex.: um
    // número no meio de um cabeçalho). O NÚMERO em si era o id PipeWire
    // das listas — o ícone da barra não o usa mais (E149), mas a
    // VALIDAÇÃO do formato segue: o ponto é a fronteira honesta.
    if i + 1 > chars.len() || chars.get(i) != Some(&'.') {
        return None;
    }
    i += 1; // o ponto
    while i < chars.len() && chars[i] == ' ' {
        i += 1;
    }
    let limite = chars[..i].iter().map(|c| c.len_utf8()).sum::<usize>();
    let padrao = linha[..limite.min(linha.len())].contains('*');
    let resto: String = chars[i..].iter().collect();
    let resto = resto.trim();
    // o nome vai até o "[vol:" (sem ele a linha não é de dispositivo)
    let (nome, vol, mudo) = {
        let k = resto.find("[vol:")?;
        let nome = resto[..k].trim();
        let depois = &resto[k..];
        let mudo = depois.contains("[MUTED]");
        let num: String = depois
            .trim_start_matches("[vol:")
            .trim_start()
            .chars()
            .take_while(|c| c.is_ascii_digit() || *c == '.')
            .collect();
        (nome.to_string(), num.parse::<f64>().unwrap_or(0.0), mudo)
    };
    if nome.is_empty() {
        return None;
    }
    Some(DispositivoAudio {
        nome,
        vol,
        mudo,
        padrao,
    })
}

// ── A BATERIA pelo /sys (a porta path-parametrizada dos testes) ────────

/// (capacidade %, carregando) da fonte — None sem bateria (desktop:
/// o pill NEM NASCE, o assento não existe por desenho).
pub fn le_bateria(base: &Path) -> Option<(u8, bool)> {
    let cap: u8 = std::fs::read_to_string(base.join("capacity"))
        .ok()?
        .trim()
        .parse()
        .ok()?;
    let status = std::fs::read_to_string(base.join("status"))
        .unwrap_or_default()
        .trim()
        .to_string();
    Some((cap, status == "Charging" || status == "Full"))
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── o relógio pt_BR: a PALAVRA é da casa ──────────────────────────

    #[test]
    fn relogio_ptbr_a_data_que_nunca_muda_de_texto() {
        // 2026-11-23 é segunda-feira; 19:30 — a cara exata do dossiê
        assert_eq!(relogio_ptbr(1, 23, 11, 19, 30), "Seg, 23 Nov · 19:30");
        assert_eq!(relogio_ptbr(0, 4, 7, 9, 5), "Dom, 04 Jul · 09:05");
        assert_eq!(relogio_ptbr(6, 31, 12, 23, 59), "Sáb, 31 Dez · 23:59");
        // o dia da semana fora do range não pânico (clamp honesto do
        // índice — a UI nunca manda lixo, mas o núcleo não morre por ele)
        // 8 % 7 = 1 = Seg (o clamp do índice é honesto)
        assert_eq!(relogio_ptbr(8, 1, 1, 0, 0), "Seg, 01 Jan · 00:00");
    }

    #[test]
    fn o_radio_do_wifi_e_lido_com_honestidade() {
        assert_eq!(parse_wifi_radio("enabled"), Some(true));
        assert_eq!(parse_wifi_radio("disabled\n"), Some(false));
        assert_eq!(parse_wifi_radio("wi-fi habilitado?"), None);
    }

    #[test]
    fn civil_e_dia_semana_as_datas_conhecidas() {
        // 1970-01-01 (quinta) até 2026-11-23 (segunda): o par civil ×
        // dia-da-semana provado nas duas pontas e no bissexto 2024
        assert_eq!(civil_de_dias(0), (1970, 1, 1));
        assert_eq!(dia_semana(0), 4); // quinta
        // 2026-11-23 = dia 20.780 desde a época (o dump 192038 é a testemunha)
        let (a, m, d) = civil_de_dias(20_780);
        assert_eq!((a, m, d), (2026, 11, 23));
        assert_eq!(dia_semana(20_780), 1); // segunda
        // 2024-02-29 (o bissexto que separa os que sabem dos que chutam)
        let (a2, m2, d2) = civil_de_dias(19_782);
        assert_eq!((a2, m2, d2), (2024, 2, 29));
        // vésperas de mês/ano: 1999-12-31 e 2000-01-01
        assert_eq!(civil_de_dias(10_956), (1999, 12, 31));
        assert_eq!(civil_de_dias(10_957), (2000, 1, 1));
        assert_eq!(dia_semana(10_957), 6); // sábado
    }

    // ── E147 · o wpctl status: a central de áudio pelo parse PURO ──────

    #[test]
    fn wpctl_status_o_parse_dos_dois_lados() {
        // o cenário DO DUMP do dono (20261124-204130): analógico interno,
        // HDMI e o sink do microfone USB; fonte mono do Fifine
        let saida = "Audio\n ├─ API: v4\n │\n ├─ Sinks:\n │  │\n \
            │  ├─ * 80. alsa_output.pci-0000_0c_00.4.analog-stereo [vol: 0.60]\n \
            │  ├─ 76. alsa_output.pci-0000_0a_00.1.hdmi-stereo-extra3 [vol: 0.74]\n \
            │  │\n ├─ Sources:\n │  │\n \
            │  ├─ * 1101. alsa_input.usb-MV-SILICON_fifine_Microphone_20190808-00.mono-fallback [vol: 0.80]\n \
            │  ├─ 1102. Monitor of alsa_output.pci-0000_0c_00.4.analog-stereo [vol: 0.60]\n \
            │  │\n ├─ Devices:\n │\n └─ Settings:";
        let (sinks, fontes) = parse_wpctl_status(saida);
        assert_eq!(sinks.len(), 2, "monitor NUNCA entra em sinks");
        assert_eq!(fontes.len(), 1, "o Monitor of é o eco da saída — fora");
        let padrao = sinks.iter().find(|d| d.padrao).unwrap();
        assert_eq!(
            padrao.nome,
            "alsa_output.pci-0000_0c_00.4.analog-stereo"
        );
        assert_eq!(padrao.vol, 0.60);
        let hdmi = sinks.iter().find(|d| !d.padrao).unwrap();
        assert!(hdmi.nome.contains("hdmi-stereo-extra3"));
        assert!(!hdmi.padrao);
        let mic = &fontes[0];
        assert!(mic.nome.contains("fifine"));
    }

    #[test]
    fn wpctl_status_o_mudo_e_a_arvore_vazia() {
        let saida = "Sinks:\n * 9. nome [vol: 0.50] [MUTED]\n 10. outro [vol: 1.50]\n";
        let (sinks, fontes) = parse_wpctl_status(saida);
        assert!(fontes.is_empty());
        assert_eq!(sinks.len(), 2);
        assert!(sinks[0].mudo);
        assert_eq!(sinks[0].vol, 0.50);
        assert_eq!(sinks[1].vol, 1.50);
        assert!(!sinks[1].mudo);
        // linhas de cabeçalho/árvore nunca viram dispositivo
        let (s, f) = parse_wpctl_status("Sinks:\n │  │\n\nSources:\n");
        assert!(s.is_empty() && f.is_empty());
    }

    // ── o wpctl: volume + MUDO em uma linha ─────────────────────────

    #[test]
    fn wpctl_volume_e_mudo_nas_duas_caras() {
        assert_eq!(parse_volume_wpctl("Volume: 0.45\n"), Some((0.45, false)));
        assert_eq!(
            parse_volume_wpctl("Volume: 1.50 [MUTED]\n"),
            Some((1.50, true))
        );
        // a lição do craft-audio E138: um sufixo '%' NUNCA mais derruba
        // o juízo (o Python morreu de float('45%'))
        assert_eq!(parse_volume_wpctl("Volume: 45%\n"), Some((45.0, false)));
        // lixo absoluto: None (o estado anterior CONSERVADO pela UI)
        assert_eq!(parse_volume_wpctl(""), None);
        assert_eq!(parse_volume_wpctl("erro: nenhum dispositivo\n"), None);
        assert_eq!(parse_volume_wpctl("Volume: abc\n"), None);
    }

    #[test]
    fn icones_de_audio_e_mic_sao_nomes_gtk() {
        assert_eq!(icone_volume(0.45, true), "audio-volume-muted-symbolic");
        assert_eq!(icone_volume(0.20, false), "audio-volume-low-symbolic");
        assert_eq!(icone_volume(0.80, false), "audio-volume-high-symbolic");
        assert_eq!(icone_mic(false), "microphone-sensitivity-high-symbolic");
        assert_eq!(icone_mic(true), "microphone-sensitivity-muted-symbolic");
    }

    // ── a rede: TRÊS estados, o botão NUNCA some ──────────────────────

    #[test]
    fn nmcli_os_tres_estados_e_o_lo_ignorado() {
        // o cenário DO DUMP (cabo ativo + Wi-Fi em baixo)
        let cabo = "enp7s0:ethernet:connected:Conexão cabeada 1\n\
                    wlp5s0:wifi:unavailable:\n\
                    lo:loopback:connected (externally):lo\n";
        assert_eq!(estado_rede_nmcli(cabo), EstadoRede::Cabo);
        // Wi-Fi no ar (o cabo fora)
        let wifi = "wlp5s0:wifi:connected:Casa 5G\nlo:loopback:ignored\n";
        assert_eq!(estado_rede_nmcli(wifi), EstadoRede::Wifi);
        assert_eq!(essid_nmcli(wifi).as_deref(), Some("Casa 5G"));
        // o OFF PERSISTENTE do dossiê: cabo desligado pelo menu + Wi-Fi
        // desligado — o ícone FICA (uf92d), o dono nunca fica trancado
        let off = "enp7s0:ethernet:unavailable:\nwlp5s0:wifi:unavailable:\n";
        assert_eq!(estado_rede_nmcli(off), EstadoRede::Desligado);
        assert_eq!(essid_nmcli(off), None);
        // ethernet disconnected (cabo fora, placa viva) também é OFF
        let cabo_fora = "enp7s0:ethernet:disconnected:\n";
        assert_eq!(estado_rede_nmcli(cabo_fora), EstadoRede::Desligado);
        // vazio/erro do nmcli: OFF honesto (o botão persiste mesmo assim)
        assert_eq!(estado_rede_nmcli(""), EstadoRede::Desligado);
        // o CABO vence o Wi-Fi (ambos conectados: o fio é o caminho)
        let ambos = "enp7s0:ethernet:connected:X\nwlp5s0:wifi:connected:Y\n";
        assert_eq!(estado_rede_nmcli(ambos), EstadoRede::Cabo);
    }

    #[test]
    fn icones_e_tooltips_da_rede() {
        assert_eq!(icone_rede(EstadoRede::Cabo), "network-wired-symbolic");
        assert_eq!(
            icone_rede(EstadoRede::Wifi),
            "network-wireless-signal-excellent-symbolic"
        );
        assert_eq!(
            icone_rede(EstadoRede::Desligado),
            "network-wireless-offline-symbolic"
        );
        assert!(tooltip_rede(EstadoRede::Wifi, Some("Casa 5G"), None).starts_with("Casa 5G"));
        // 1.0-106 — O MAPA NOVO DO CLIQUE no tooltip (seletor/editor/toggle)
        assert!(tooltip_rede(EstadoRede::Desligado, None, None).contains("seletor rápido"));
        // 1.0-104 — O RÁDIO DO Wi-Fi TEM VOZ MESMO COM O CABO (o dono lê o
        // estado do rádio no tooltip do ícone do fio — sem adivinhar)
        let cabo_wifi_off = tooltip_rede(EstadoRede::Cabo, None, Some(false));
        assert!(cabo_wifi_off.contains("Wi-Fi DESLIGADO"), "{cabo_wifi_off}");
        let cabo_wifi_on = tooltip_rede(EstadoRede::Cabo, None, Some(true));
        assert!(cabo_wifi_on.contains("Wi-Fi ligado"), "{cabo_wifi_on}");
        // sem a verdade do rádio (nmcli calado): o tooltip segue honesto —
        // sem AFIRMAR estado do rádio (só o gesto de sempre segue na frase)
        assert!(
            !tooltip_rede(EstadoRede::Cabo, None, None).contains("Wi-Fi ligado"),
            "sem leitura não há afirmação"
        );
        assert!(
            !tooltip_rede(EstadoRede::Cabo, None, None).contains("Wi-Fi DESLIGADO"),
            "sem leitura não há afirmação"
        );
        // o off com o rádio desligado NOMEIA o réu (quem clicou lê o feito)
        let off_radio = tooltip_rede(EstadoRede::Desligado, None, Some(false));
        assert!(off_radio.contains("Wi-Fi desligado"), "{off_radio}");
    }

    // ── o Bluetooth: só o estado, o gerenciador é o blueman ───────────

    #[test]
    fn bluetooth_o_powered_da_verdade() {
        let on = "Controller 00:11:22:33:44:55\n\tPowered: yes\n\tDiscovering: no\n";
        assert!(bt_ligado(on));
        let off = "Controller 00:11:22:33:44:55\n\tPowered: no\n";
        assert!(!bt_ligado(off));
        assert!(!bt_ligado("No default controller available"));
        assert!(!bt_ligado(""));
    }

    // ── o JSON mínimo da família ──────────────────────────────────────

    #[test]
    fn json_da_familia_text_e_tooltip() {
        let jogo_on = r#"{"text":"🎮","class":"on","tooltip":"Modo de jogo ativo"}"#;
        assert_eq!(json_text(jogo_on).as_deref(), Some("🎮"));
        // text vazio = o pill SAI (o assento só existe com conteúdo)
        let off = r#"{"text":"","class":"","tooltip":""}"#;
        assert_eq!(json_text(off), None);
        // sem o campo: None honesto
        assert_eq!(json_text("não é json"), None);
        // o player com o tempo no texto (a gramática da E124)
        let player = r#"{"text":" ♪ Faixa 1 · 1:23/3:45","class":"playing","tooltip":"Artista — Faixa"}"#;
        assert!(json_text(player).unwrap().contains("1:23/3:45"));
        // chaves fora de ordem (o contrato é o PAR, não a posição)
        let trocado = r#"{"class":"on","tooltip":"T","text":"X"}"#;
        assert_eq!(json_text(trocado).as_deref(), Some("X"));
    }

    // ── a bateria pelo /sys ────────────────────────────────────────────

    #[test]
    fn bateria_do_sys_pela_porta_path() {
        let dir = std::env::temp_dir().join(format!("craft-bar-bat-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("capacity"), "76\n").unwrap();
        std::fs::write(dir.join("status"), "Discharging\n").unwrap();
        assert_eq!(le_bateria(&dir), Some((76, false)));
        std::fs::write(dir.join("status"), "Charging\n").unwrap();
        assert_eq!(le_bateria(&dir), Some((76, true)));
        // sem o arquivo: None (desktop — o pill nem nasce)
        assert_eq!(le_bateria(&dir.join("nao-existe")), None);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn o_pill_da_midia_do_bus() {
        let m = MediaState {
            player: Some("org.mpris.MediaPlayer2.firefox".into()),
            title: Some("Stardew OST".into()),
            artist: Some("ConcernedApe".into()),
            playing: true,
        };
        let pill = media_pill(&m).unwrap();
        // 1.0-101 — a ordem é "Artista - Título" e o ícone é GTK
        assert!(pill.texto.contains("ConcernedApe - Stardew OST"));
        assert_eq!(pill.icone, "media-playback-start-symbolic");
        assert!(pill.tooltip.contains("firefox"));
        assert!(pill.tooltip.contains("Stardew OST"));
        // pausado: o estado tem voz no ícone e no tooltip
        let pausado = MediaState { playing: false, ..m.clone() };
        let pill2 = media_pill(&pausado).unwrap();
        assert_eq!(pill2.icone, "media-playback-pause-symbolic");
        assert!(pill2.tooltip.contains("pausado"));
        // sem mídia: o pill NÃO NASCE (o botão sai da barra)
        let vazio = MediaState { player: None, title: None, artist: None, playing: false };
        assert!(media_pill(&vazio).is_none());
        // o texto é truncado em 28; o tooltip guarda o INTEIRO
        let longo = MediaState {
            player: Some("x".into()),
            title: Some("Uma música muito comprida cujo nome não cabe na barra de jeito nenhum".into()),
            artist: None,
            playing: true,
        };
        let pill3 = media_pill(&longo).unwrap();
        assert!(pill3.texto.chars().count() <= 28, "pill largo: {:?}", pill3.texto);
        assert!(pill3.tooltip.contains("de jeito nenhum"));
    }

}
