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
//     `craft-game pill` / `craft-player state` / `craft-bgapps
//     status` (o JSON mínimo do waybar: text/class/tooltip — o
//     contrato é ESTE e a barra é cliente dele, sem serde: o par
//     aspas-vírgula do "text" é o contrato estável da família).
//   · O JUÍZO DOS GLIFOS (Nerd Font, os MESMOS codepoints da era
//     waybar — a família visual sobrevive à troca do motor).
//   · O DEBOUNCE DO DRAWER (a cura A1): o clique que abre a gaveta
//     nunca renasce a gaveta — 150ms de janela, contados do RELEASE
//     (o dossiê: "debounce real de 150ms, zero bloqueio"; o freio de
//     400ms + túmulo de 600ms do craft-drawer shell eram a paliativa
//     da era que spawnava/matava às cegas — aqui o FILHO é nosso e o
//     toggle é por pid, mas o eco do clique ainda morre na janela).
//   · A BATERIA pelo /sys (capacity + status) — parâmetro path, a
//     porta dos testes.
//
// ESCOPO HONESTO (o que NÃO mora aqui — nomeado):
//   ✗ roteamento de áudio (a casa do roteador é o craft-audio-route,
//     shell, com o snapshot E139 — a barra só MOSTRA e muta);
//   ✗ a lista de redes/conexões (iwgtk e nm-connection-editor são as
//     ferramentas de verdade que o clique abre — a barra não faz
//     papel de painel de controle, a diretriz do dossiê);
//   ✗ o veredito do modo de jogo (o elite-daemon é o dono; a barra
//     acende o pill no SIGRTMIN+8 que ELE manda).

use std::path::Path;

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
pub fn dia_semana(dias: i64) -> u32 {
    ((dias + 4).rem_euclid(7)) as u32
}

/// O INSTANTE INTEIRO em segundos-desde-época (a porta única da UI —
/// sem a feature "gui" ninguém chama: o allow é a cortesia do degrau).
#[cfg_attr(not(feature = "gui"), allow(dead_code))]
pub fn agora_epoch() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
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

/// O glifo do VOLUME (Nerd Font, os codepoints da era waybar):
/// mudo = uf026 · baixo (<0.34) = uf027 · alto = uf028.
pub fn glifo_volume(v: f64, mudo: bool) -> &'static str {
    if mudo {
        "\u{f026}"
    } else if v < 0.34 {
        "\u{f027}"
    } else {
        "\u{f028}"
    }
}

/// O glifo do MICROFONE: vivo = uf130 · mudo = uf131 (o realce visual
/// do mudo é a classe .muted do CSS — a mesma gramática vermelha).
pub fn glifo_mic(mudo: bool) -> &'static str {
    if mudo {
        "\u{f131}"
    } else {
        "\u{f130}"
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

/// O glifo do estado da rede (os codepoints da era waybar — a família
/// visual sobrevive).
pub fn glifo_rede(e: EstadoRede) -> &'static str {
    match e {
        EstadoRede::Cabo => "\u{f6ff}",
        EstadoRede::Wifi => "\u{f1eb}",
        EstadoRede::Desligado => "\u{f92d}",
    }
}

/// O tooltip do estado da rede (o que o dono lê ao parar o mouse).
pub fn tooltip_rede(e: EstadoRede, essid: Option<&str>) -> String {
    match e {
        EstadoRede::Cabo => "Cabo conectado — clique: iwgtk · direito: conexões".to_string(),
        EstadoRede::Wifi => format!(
            "{} — clique: iwgtk · direito: conexões",
            essid.unwrap_or("Wi-Fi conectado")
        ),
        EstadoRede::Desligado => "Sem conexão — clique: iwgtk (o botão nunca sai)".to_string(),
    }
}

// ── O BLUETOOTH (o par dedicated da diretriz) ──────────────────────────

/// O Bluetooth está LIGADO na saída do `bluetoothctl show`? (procura a
/// linha "Powered: yes" — a casa só lê o estado, quem liga/desliga é o
/// blueman-manager, a ferramenta de verdade que o clique abre).
pub fn bt_ligado(saida: &str) -> bool {
    saida
        .lines()
        .any(|l| l.trim().eq_ignore_ascii_case("powered: yes"))
}

// ── O JSON MÍNIMO da família (game/player/bgapps) ──────────────────────

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

/// O valor de "tooltip" do mesmo JSON (None = sem tooltip, o botão
/// fica calado).
pub fn json_tooltip(s: &str) -> Option<String> {
    let i = s.find("\"tooltip\"")?;
    let resto = &s[i + "\"tooltip\"".len()..];
    let dp = resto.find(':')?;
    let depois = &resto[dp + 1..];
    let abre = depois.find('"')?;
    let conteudo = &depois[abre + 1..];
    let fecha = conteudo.find('"')?;
    if conteudo[..fecha].is_empty() {
        None
    } else {
        Some(conteudo[..fecha].to_string())
    }
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

// ── O DEBOUNCE DO DRAWER (a cura A1 — o eco do clique morre aqui) ──────

/// O clique está DENTRO da janela do debounce? (150ms contados do
/// último release aceito — o eco do segundo clique do mesmo gesto não
/// renasce a gaveta que o primeiro acabou de fechar).
pub fn dentro_janela_ms(ultimo_ns: u128, agora_ns: u128, janela_ms: u64) -> bool {
    agora_ns.saturating_sub(ultimo_ns) < u128::from(janela_ms) * 1_000_000
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

    // ── o wpctl: volume + MUDO em uma linha ───────────────────────────

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
    fn glifos_de_audio_e_mic() {
        assert_eq!(glifo_volume(0.45, true), "\u{f026}");
        assert_eq!(glifo_volume(0.20, false), "\u{f027}");
        assert_eq!(glifo_volume(0.80, false), "\u{f028}");
        assert_eq!(glifo_mic(false), "\u{f130}");
        assert_eq!(glifo_mic(true), "\u{f131}");
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
    fn glifos_e_tooltips_da_rede() {
        assert_eq!(glifo_rede(EstadoRede::Cabo), "\u{f6ff}");
        assert_eq!(glifo_rede(EstadoRede::Wifi), "\u{f1eb}");
        assert_eq!(glifo_rede(EstadoRede::Desligado), "\u{f92d}");
        assert!(tooltip_rede(EstadoRede::Wifi, Some("Casa 5G")).starts_with("Casa 5G"));
        assert!(tooltip_rede(EstadoRede::Desligado, None).contains("nunca sai"));
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
        assert_eq!(json_tooltip(jogo_on).as_deref(), Some("Modo de jogo ativo"));
        // text vazio = o pill SAI (o assento só existe com conteúdo)
        let off = r#"{"text":"","class":"","tooltip":""}"#;
        assert_eq!(json_text(off), None);
        assert_eq!(json_tooltip(off), None);
        // sem o campo: None honesto
        assert_eq!(json_text("não é json"), None);
        assert_eq!(json_tooltip("não é json"), None);
        // o player com o tempo no texto (a gramática da E124)
        let player = r#"{"text":" ♪ Faixa 1 · 1:23/3:45","class":"playing","tooltip":"Artista — Faixa"}"#;
        assert!(json_text(player).unwrap().contains("1:23/3:45"));
        // chaves fora de ordem (o contrato é o PAR, não a posição)
        let trocado = r#"{"class":"on","tooltip":"T","text":"X"}"#;
        assert_eq!(json_text(trocado).as_deref(), Some("X"));
        assert_eq!(json_tooltip(trocado).as_deref(), Some("T"));
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

    // ── o debounce do drawer ──────────────────────────────────────────

    #[test]
    fn debounce_do_drawer_o_eco_morre_na_janela() {
        let t0: u128 = 1_000_000_000;
        // 100ms depois: DENTRO (o eco do mesmo gesto — ignorado)
        assert!(dentro_janela_ms(t0, t0 + 100 * 1_000_000, 150));
        // 149ms: ainda dentro (a fronteira é aberta — 150 é FORA)
        assert!(dentro_janela_ms(t0, t0 + 149 * 1_000_000, 150));
        // 150ms: FORA (um gesto NOVO — a gaveta responde)
        assert!(!dentro_janela_ms(t0, t0 + 150 * 1_000_000, 150));
        // relógio que andou para trás (NTP/ajuste): o saturando devolve 0 =
        // DENTRO da janela — o eco ignorado é o lado SEGURO (o relógio
        // doido nunca abre gaveta dupla)
        assert!(dentro_janela_ms(t0, t0 - 1, 150));
    }
}
