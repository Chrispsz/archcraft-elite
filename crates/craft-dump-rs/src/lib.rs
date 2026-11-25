// ═════════════════════════════════════════════════════════════════════════
// craft-dump-rs — o NÚCLEO da telemetria v2 (2.0)
// ═════════════════════════════════════════════════════════════════════════
// O papel que se conhece: era nativa, a família de sessão esperada, a
// ausência TOTAL do legado, os serviços críticos e os parâmetros de boot.
// O núcleo é PURO (entrada = texto colhido; saída = veredito tipado) —
// testa em qualquer lugar; o main é a mão que colhe (systemctl/procfs/cmdline).
// FASE 1: os contratos e os juízos. A coleta completa (bus.sock, journal
// do PrepareForSleep) é Fase 2 — o bash craft-dump segue vivo até a v2
// cobrir os dois pés (a aposentadoria tem substituto antes de nascer).
// ═════════════════════════════════════════════════════════════════════════

/// O legado que NUNCA mais vive na casa 2.0 (processo, bin ou conf).
pub const LEGADO: &[&str] = &[
    "waybar",
    "craft-audio",       // a UI Python (o roteador era OUTRO papel — que também morreu)
    "craft-bars",        // o supervisor sh — o lançador único é elite-daemon session
    "craft-connect",     // os menus fuzzel de rede/bluetooth — iwgtk/blueman são a tela
    "craft-pin-pick",    // o picker fuzzel de pins — o popover da dock tomou o lugar
    "craft-menu",        // o painel fuzzel (2.0: o craft-pick GTK4 tomou o lugar)
    "craft-player",      // o poller de 1s — o MPRIS pelo bus tomou o lugar
    "craft-drawer",      // o wrapper sh — o nwg-drawer direto tomou o lugar
    "craft-power",       // o menu fuzzel de sessão — o popover + elite-sessao tomaram
    "craft-logout",      // o wrapper do power — idem
    "craft-menu-dismiss",// o fechar-por-pid — o GTK/labwc fecham sozinhos
    "craft-audio-route", // 2.0: o roteador Python — o audio.rs do daemon tomou
    "craft-toplevel",    // 2.0: o C de 3 gerações — o wayland.rs do daemon tomou
    "craft-bgapps",      // E147: o indicador de 2º planos — a ordem do dono o
                         // tirou da interface E do código (o post-upgrade o ceifa)
    "swayidle",          // 2.0: a vigília é do daemon (ext-idle-notify nativo)
];

/// A família de sessão 2.0 esperada de pé (comm).
pub const FAMILIA_SESSAO: &[&str] = &[
    "elite-daemon",   // o orquestrador único (session + game + supervise)
    "craft-dock-rs",  // a dock GTK4 nativa
    "craft-bar-rs",   // a top bar GTK4 nativa
];

/// Os serviços críticos do sistema 2.0 (o papel nomeia o ausente).
pub const SERVICOS_CRITICOS: &[&str] = &[
    "NetworkManager",
    "bluetooth",
    "coolercontrold",
    "scx_loader",
];

/// Juízo de um comm de processo contra a lista do legado.
/// EXATO (não prefixo): o réu 'craft-audio' (a UI aposentada) não pode
/// comer o 'craft-audio-route' (o roteador — tuning vivo da casa).
pub fn e_legado(comm: &str) -> bool {
    LEGADO.iter().any(|l| comm == *l)
}

/// O relatório de um serviço: presente/ausente a partir do texto do
/// `systemctl --no-legend --all list-unit-files` (cabeças de linha).
pub fn servico_presente(saida_systemctl: &str, unit: &str) -> bool {
    saida_systemctl.lines().any(|l| {
        let cabeca = l.split_whitespace().next().unwrap_or("");
        // o unit pode nascer 'coolercontrold.service' ou com o caminho cheio
        let nome = cabeca.split('/').last().unwrap_or(cabeca);
        nome == unit || nome == &format!("{unit}.service") || cabeca == &format!("{unit}.service")
    })
}

/// Juízo do kernel cmdline: o parâmetro pedido está lá (palavra inteira
/// ou com =valor — 'mitigations=off' casa, 'mitigations=100' NÃO casa).
pub fn cmdline_tem(cmdline: &str, parametro: &str) -> bool {
    cmdline.split_whitespace().any(|p| {
        p == parametro
            || p.strip_prefix(parametro)
                .map(|r| r.starts_with('='))
                .unwrap_or(false)
    })
}

/// A linha do relatório: honesta — PRESENTE/AUSENTE com o nome.
pub fn linha_servico(saida: &str, unit: &str) -> String {
    if servico_presente(saida, unit) {
        format!("serviço: {unit} PRESENTE")
    } else {
        format!("serviço: {unit} AUSENTE (o réu nomeado no papel)")
    }
}

/// Bloco de boot: os parâmetros da diretriz (o que já existe NÃO é tocado —
/// aqui só o JUÍZO; a escrita mora no elite-install-stage).
pub fn juizo_boot(cmdline: &str) -> Vec<String> {
    [
        "mitigations=off",
        "nowatchdog",
        "amdgpu.ppfeaturemask=0xffffffff",
    ]
    .iter()
    .map(|p| {
        if cmdline_tem(cmdline, p) {
            format!("boot: {p} PRESENTE")
        } else {
            format!("boot: {p} AUSENTE")
        }
    })
    .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn o_legado_e_nomeado_e_nada_mais() {
        for l in ["waybar", "craft-audio", "craft-bars", "craft-connect"] {
            assert!(e_legado(l), "{l} tem que ser legado");
        }
        assert!(!e_legado("craft-dock-rs"), "a dock é a casa, não legado");
        assert!(!e_legado("craft-bar-rs"), "a barra é a casa");
        assert!(!e_legado("elite-daemon"), "o daemon é a casa");
        // 2.0: o roteador python TAMBÉM aposentou (o audio.rs do daemon
        // é o roteador — a diretriz §7 na carne)
        assert!(e_legado("craft-audio-route"), "o roteador python é legado da 2.0");
    }

    #[test]
    fn servico_presente_le_o_list_unit_files_de_verdade() {
        let saida = "\
craft-dock-rs.service                        enabled         enabled
coolercontrold.service                       enabled         enabled
scx_loader.service                           enabled         enabled
NetworkManager.service                       enabled         enabled
bluetooth.service                            enabled         enabled
";
        for u in SERVICOS_CRITICOS {
            assert!(servico_presente(saida, u), "{u} presente na saída");
        }
        assert!(!servico_presente(saida, "paccache"));
        // a linha do serviço ausente vira réu nomeado
        assert!(linha_servico(saida, "coolercontrold").contains("PRESENTE"));
        assert!(linha_servico(saida, "fatorial").contains("AUSENTE"));
    }

    #[test]
    fn cmdline_julga_parametro_e_nao_prefixo_aleatorio() {
        let cmd = "quiet splash mitigations=off nowatchdog amdgpu.ppfeaturemask=0xffffffff ntsync=1";
        assert!(cmdline_tem(cmd, "mitigations=off"));
        assert!(cmdline_tem(cmd, "nowatchdog"));
        assert!(cmdline_tem(cmd, "amdgpu.ppfeaturemask"));
        assert!(cmdline_tem(cmd, "amdgpu.ppfeaturemask=0xffffffff"));
        assert!(!cmdline_tem(cmd, "mitigations=100"), "valor diferente não casa");
        assert!(!cmdline_tem(cmd, "mitigation"), "prefixo solto não é o parâmetro");
        let juizo = juizo_boot(cmd);
        assert!(juizo.iter().all(|l| l.contains("PRESENTE")));
        let juizo = juizo_boot("quiet splash");
        assert!(juizo.iter().all(|l| l.contains("AUSENTE")));
    }
}

// ── 2.0 Fase 2 — A COLETA PELO FIO (o bus vivo é a fonte da verdade) ─────

// ── O FIO VIVO — o diagnóstico de 3 estados (1.0-94: o "MORTO" da
//    1.0-93 escondia DOIS réus distintos — o fóssil sem dono e o
//    daemon engasgado que aceita o connect e nunca responde) ─────────

/// O veredito do fio: VIVO (o daemon atendeu), CALADO (conectou e não
/// respondeu — o daemon está engasgado: o núcleo/despacho travado é o
/// réu nomeado), RECUSADO (o connect falhou — fóssil de sessão morta
/// ou dono caído: ninguém escuta o caminho).
#[derive(Debug, Clone, PartialEq)]
pub enum ColheitaBus {
    /// o snapshot vivo (o daemon falou)
    Vivo(BusColheita),
    /// conectou, 2s sem uma linha (o réu: o núcleo do daemon engasgado)
    Calado,
    /// o connect recusou (o réu: o arquivo sem dono — fóssil ou queda)
    Recusado,
}

/// O snapshot de boas-vindas: conecta, pede, colhe (o veredito tipado
/// nomeia o réu — o papel nunca mente, nunca esconde a diferença entre
/// "ninguém escuta" e "escuta e não fala").
pub fn colhe_do_bus(caminho: &std::path::Path) -> ColheitaBus {
    let Some((cli, rx)) = elite_core::bus::BusClient::connect(caminho, "craft-dump") else {
        return ColheitaBus::Recusado;
    };
    let _ = cli.send_req(elite_core::BusReq::Snapshot);
    // as boas-vindas + o snapshot chegam em sequência; o teto de 2s é o
    // juízo (o daemon vivo responde em ms; morto não responde nunca)
    let prazo = std::time::Duration::from_secs(2);
    let mut colheita = BusColheita::default();
    let mut falou = false;
    let inicio = std::time::Instant::now();
    while inicio.elapsed() < prazo {
        match rx.recv_timeout(std::time::Duration::from_millis(200)) {
            Ok(elite_core::BusMsg::Windows { windows }) => {
                falou = true;
                colheita.janelas = windows.len() as u32;
                colheita.titulo = windows
                    .iter()
                    .find(|w| w.focused)
                    .and_then(|w| w.title.clone());
            }
            Ok(elite_core::BusMsg::Workspace(ws)) => {
                falou = true;
                colheita.mesa = Some(ws);
            }
            Ok(elite_core::BusMsg::Media(m)) => {
                falou = true;
                colheita.midia = Some(m);
            }
            Ok(elite_core::BusMsg::GameMode(g)) => {
                falou = true;
                colheita.jogo = Some(g);
            }
            Ok(elite_core::BusMsg::Audio(a)) => {
                falou = true;
                colheita.audio = Some(a);
            }
            Ok(elite_core::BusMsg::Ack { .. }) => {
                // o eco do Snapshot: a colheita já nasceu (as boas-vindas
                // precedem) — fecha o papel
                return ColheitaBus::Vivo(colheita);
            }
            Ok(_) => {}
            Err(_) => return ColheitaBus::if_calado(falou, colheita),
        }
    }
    ColheitaBus::if_calado(falou, colheita)
}

impl ColheitaBus {
    /// a linha do prazo: falou algo = VIVO (mesmo sem Ack — o estado
    /// parcial é verdade); mudo no teto = CALADO (o réu nomeado).
    fn if_calado(falou: bool, colheita: BusColheita) -> ColheitaBus {
        if falou {
            ColheitaBus::Vivo(colheita)
        } else {
            ColheitaBus::Calado
        }
    }
}

/// o que o bus entregou (a cara do estado vivo da sessão).
#[derive(Debug, Default, Clone, PartialEq)]
pub struct BusColheita {
    pub janelas: u32,
    pub titulo: Option<String>,
    pub mesa: Option<elite_core::WorkspaceInfo>,
    pub midia: Option<elite_core::MediaState>,
    pub jogo: Option<elite_core::GameModeState>,
    pub audio: Option<elite_core::AudioState>,
}

/// O PAPEL do bus (as linhas pt_BR do bloco "sessão viva").
pub fn linhas_bus(c: &BusColheita) -> Vec<String> {
    let mut out = Vec::new();
    out.push(format!("bus: {} janela(s) na sessão", c.janelas));
    match &c.titulo {
        Some(t) => out.push(format!("bus: janela focada — {t}")),
        None => out.push("bus: nenhuma janela focada (desktop puro)".into()),
    }
    if let Some(ws) = &c.mesa {
        out.push(format!(
            "bus: mesa {}/{}{}",
            ws.current,
            ws.count,
            ws.label.as_deref().map(|l| format!(" ({l})")).unwrap_or_default()
        ));
    }
    match &c.midia {
        Some(m) if m.player.is_some() => out.push(format!(
            "bus: mídia {} — {}{}",
            if m.playing { "tocando" } else { "pausada" },
            m.title.as_deref().unwrap_or("?"),
            m.artist.as_deref().map(|a| format!(" — {a}")).unwrap_or_default()
        )),
        Some(_) => out.push("bus: sem mídia (nenhum player MPRIS no ar)".into()),
        None => out.push("bus: mídia — SEM ESTADO no fio (o daemon fala?)".into()),
    }
    match &c.jogo {
        Some(g) if g.active => out.push(format!(
            "bus: modo de jogo ATIVO{} — GPU {}",
            g.game.as_deref().map(|j| format!(" ({j})")).unwrap_or_default(),
            if g.gpu_performance { "perfil 3D_FULL_SCREEN" } else { "sem perfil" }
        )),
        Some(_) => out.push("bus: modo de jogo inativo".into()),
        None => out.push("bus: modo de jogo — SEM ESTADO no fio".into()),
    }
    if let Some(a) = &c.audio {
        out.push(format!(
            "bus: áudio — saída {} ({}{})",
            a.sink_name.as_deref().unwrap_or("?"),
            a.sink_volume,
            if a.analog_preferred { " · analógica prioritária" } else { "" }
        ));
    }
    out
}

/// O PARSER do pactl info (a linha "Default Sink:" — o juízo puro).
pub fn pactl_default_sink(texto: &str) -> Option<String> {
    texto
        .lines()
        .find(|l| l.trim_start().starts_with("Default Sink:"))
        .map(|l| l.split_once(':').map(|(_, v)| v.trim().to_string()).unwrap_or_default())
        .filter(|s| !s.is_empty())
}

// ── 1.0-93 — A TELEMETRIA PROFUNDA (a ordem do dono: o papel volta a
//    se conhecer DE VERDADE — hardware/GPU/VRAM, cmdline, sysctl,
//    RSS/CPU% dos processos, PipeWire, journal, pacman) ──────────────

/// O MODELO da CPU (a primeira linha "model name" do /proc/cpuinfo).
pub fn cpu_model(cpuinfo: &str) -> Option<String> {
    cpuinfo
        .lines()
        .find(|l| l.trim_start().starts_with("model name"))
        .and_then(|l| l.split_once(':'))
        .map(|(_, v)| v.trim().to_string())
        .filter(|s| !s.is_empty())
}

/// (total, disponível) em GiB do /proc/meminfo (kB → GiB).
pub fn meminfo_gib(meminfo: &str) -> Option<(f64, f64)> {
    let val = |nome: &str| -> Option<f64> {
        meminfo
            .lines()
            .find(|l| l.trim_start().starts_with(nome))
            .and_then(|l| l.split_whitespace().nth(1))
            .and_then(|v| v.parse::<f64>().ok())
            .map(|kb| kb / 1_048_576.0)
    };
    Some((val("MemTotal:")?, val("MemAvailable:")?))
}

/// A VRAM da GPU amdgpu em MiB (o sysfs `mem_info_vram_total` em bytes;
/// None = arquivo ausente — GPU de outro driver, nomeada honesta).
pub fn vram_mib(bytes: &str) -> Option<u64> {
    bytes.trim().parse::<u64>().ok().map(|b| b / 1_048_576)
}

/// O cmdline do /proc/<pid>/cmdline (NUL → espaço; o recorte de
/// controle vira ponto — o papel é texto legível).
pub fn cmdline_junta(cmdline: &str) -> String {
    cmdline
        .replace('\u{0}', " ")
        .chars()
        .map(|c| if c.is_control() { '·' } else { c })
        .collect::<String>()
        .trim()
        .to_string()
}

/// (cpu%, rss_mib) de um processo: o /proc/<pid>/stat (utime+stime em
/// ticks desde o boot — o CPU% é o CUMULATIVO do processo contra o
/// uptime; honesto e barato, sem amostragem dupla) e o VmRSS do status.
pub fn proc_cpu_rss(stat: &str, status: &str, uptime_s: f64, hz: f64) -> (f64, f64) {
    // os campos do stat após o comm (que pode ter espaço — o parêntese
    // fecha o campo 2; os ticks são os campos 14+15 contados de lá)
    let ticks: f64 = stat
        .rsplit(')')
        .next()
        .and_then(|depois| {
            let c: Vec<&str> = depois.split_whitespace().collect();
            // comm) state(1º) ppid... utime = c[11], stime = c[12]
            let ut: f64 = c.get(11).and_then(|v| v.parse().ok()).unwrap_or(0.0);
            let st: f64 = c.get(12).and_then(|v| v.parse().ok()).unwrap_or(0.0);
            Some(ut + st)
        })
        .unwrap_or(0.0);
    let cpu = if uptime_s > 0.0 && hz > 0.0 {
        (ticks / hz / uptime_s * 100.0).min(999.0)
    } else {
        0.0
    };
    let rss_mib = status
        .lines()
        .find(|l| l.starts_with("VmRSS:"))
        .and_then(|l| l.split_whitespace().nth(1))
        .and_then(|v| v.parse::<f64>().ok())
        .map(|kb| kb / 1024.0)
        .unwrap_or(0.0);
    (cpu, rss_mib)
}

/// O nome do dono pelo uid do SUDO_UID (o dump sobe pelo pkexec — o
/// uid RAIZ colheria a sessão de ninguém; None = sem /etc/passwd).
pub fn nome_do_uid(uid: u32, passwd: &str) -> Option<String> {
    passwd
        .lines()
        .find(|l| {
            let c: Vec<&str> = l.split(':').collect();
            c.get(2).and_then(|u| u.parse::<u32>().ok()) == Some(uid)
        })
        .and_then(|l| l.split(':').next().map(|s| s.to_string()))
}

/// 1.0-94 — O HOME do dono pelo uid (o dump sobe como raiz pelo pkexec:
/// o $HOME da corrida é /root e os papéis da SESSÃO — bars.log,
/// idle.conf, o cache — moram no home de QUEM pediu; None = sem passwd).
pub fn home_do_uid(uid: u32, passwd: &str) -> Option<String> {
    passwd
        .lines()
        .find(|l| {
            let c: Vec<&str> = l.split(':').collect();
            c.get(2).and_then(|u| u.parse::<u32>().ok()) == Some(uid)
        })
        .and_then(|l| l.split(':').nth(5).map(|s| s.to_string()))
        .filter(|s| !s.is_empty())
}

/// 1.0-94 — A ANOTAÇÃO DOS ERROS CONHECIDOS do boot (a ordem do dono:
/// o papel curto NÃO pode virar alarme falso — as linhas benignas do
/// kernel/hardware ganham o veredito NA CARA; None = linha sem perícia
/// conhecida, segue crua como sempre).
pub fn anota_conhecido(linha: &str) -> Option<&'static str> {
    if linha.contains("bluetoothd")
        && (linha.contains("Refusing input device connect")
            || linha.contains("Refusing connection from"))
    {
        return Some(
            "→ conhecido: o bluetoothd recusando a reconexão antes do \
             pareamento assentar no boot — o áudio BT conecta depois (benigno)",
        );
    }
    if linha.contains("bluetoothd") && linha.contains("Fallback profile connection failed") {
        return Some(
            "→ conhecido: corrida bluetoothd×PipeWire no arranque (Device busy) \
             — o perfil cai e o roteador da casa religa depois (benigno)",
        );
    }
    if linha.contains("multicast RX registrations are not supported") {
        return Some(
            "→ conhecido: o driver sem registro multicast RX no nl80211 — o \
             wpa_supplicant segue funcional (benigno do driver)",
        );
    }
    if linha.contains("couldn't find an input interrupt endpoint") {
        return Some(
            "→ conhecido: interface de controle USB sem endpoint de \
             interrupção (dispositivo composto, p.ex. o microfone) — o \
             dispositivo segue funcional (benigno)",
        );
    }
    if linha.contains("TDX not supported") {
        return Some(
            "→ conhecido: a sonda Intel TDX em CPU AMD — ruído do kernel \
             (benigno em Ryzen)",
        );
    }
    if linha.contains("Overdrive is enabled") {
        return Some(
            "→ esperado: o amdgpu.ppfeaturemask=0xffffffff da casa acende o \
             overdrive (a lei do tuning, não defeito)",
        );
    }
    None
}

/// 1.0-94 — A LINHA DO SCX (o interplay nomeado): unit presente +
/// sched_ext ausente no kernel = o lavd DORME por desenho (a Condition
/// pula; o BO/EEVDF do kernel CachyOS segue mandando — o papel não deixa
/// o leitor achar que o escalonador quebrou).
pub fn linha_scx(sched_ext_ok: bool, unit_presente: bool) -> Option<&'static str> {
    if !sched_ext_ok && unit_presente {
        return Some(
            "  scx-lavd: DORME neste kernel (sem sched_ext a Condition pula a \
             unit — o escalonador do kernel segue; não é defeito da casa)"
        );
    }
    None
}

// ═════════════════════════════════════════════════════════════════════════
// E150 — A AUDITORIA SISTÊMICA (a ordem do dono, base 1.0-98: o dump
// conectado a TODOS os subsistemas ativos — um relatório único). Tudo
// aqui é PURO sobre o texto colhido (free/zramctl/pacman/wlr-randr/
// displays.conf/procfs): a mão que colhe mora no main, o juízo mora AQUI.
// ═════════════════════════════════════════════════════════════════════════

/// E150 — o parse do `free -m` (MiB): devolve (total, used, buff_cache,
/// available, swap_total, swap_used) — o consumo GLOBAL que o dono lê.
pub fn parse_free_m(texto: &str) -> Option<(u64, u64, u64, u64, u64, u64)> {
    let mut mem = None;
    let mut swap = None;
    for linha in texto.lines() {
        let c: Vec<&str> = linha.split_whitespace().collect();
        if c.first() == Some(&"Mem:") && c.len() >= 7 {
            // total used free shared buff/cache available
            mem = Some((
                c[1].parse().ok()?, c[2].parse().ok()?, c[5].parse().ok()?, c[6].parse().ok()?,
            ));
        } else if c.first() == Some(&"Swap:") && c.len() >= 4 {
            swap = Some((c[1].parse().ok()?, c[2].parse().ok()?));
        }
    }
    let (t, u, bc, a) = mem?;
    let (st, su) = swap.unwrap_or((0, 0));
    Some((t, u, bc, a, st, su))
}

/// E150 — os campos do `zramctl` (a linha de dados): devolve
/// (disksize, data, total) — o zram VIVO comprimindo ou None honesto.
pub fn zramctl_campos(texto: &str) -> Option<(String, String, String)> {
    // cabeça: NAME DISKSIZE DATA COMPR TOTAL STREAMS MOUNTPOINT
    let linha = texto.lines().nth(1)?;
    let c: Vec<&str> = linha.split_whitespace().collect();
    if c.len() < 5 {
        return None;
    }
    Some((c[1].to_string(), c[2].to_string(), c[4].to_string()))
}

/// E150 — o RSS (KiB) de um /proc/<pid>/status (0 = zumbi/kernel thread).
pub fn rss_kib_do_status(status: &str) -> u64 {
    status
        .lines()
        .find(|l| l.starts_with("VmRSS:"))
        .and_then(|l| l.split_whitespace().nth(1))
        .and_then(|v| v.parse().ok())
        .unwrap_or(0)
}

/// E150 — o ranking RSS (desc, empate pelo pid; n primeiros): a lista
/// de (pid, comm, rss_kib) vira o top do papel.
pub fn rank_rss(mut v: Vec<(u32, String, u64)>, n: usize) -> Vec<(u32, String, u64)> {
    v.sort_by(|a, b| b.2.cmp(&a.2).then(a.0.cmp(&b.0)));
    v.truncate(n);
    v
}

/// E150 — a contagem de pacotes (as linhas não-vazias do pacman -Q/-Qe/-Qm).
pub fn conta_linhas(texto: &str) -> usize {
    texto.lines().filter(|l| !l.trim().is_empty()).count()
}

/// E150 — o modo ATUAL de cada output no wlr-randr (a marca "(current)"
/// da 0.5 — o mesmo parser de verdade do craft-display, agora no papel):
/// devolve (nome_do_output, "WxH@RATE") por tela viva.
pub fn randr_modos_atuais(randr: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut atual = String::new();
    for linha in randr.lines() {
        if linha.starts_with(char::is_whitespace) {
            if linha.contains("(current)") {
                if let Some(tok) = linha.split_whitespace().find(|t| modo_parece(t)) {
                    if !atual.is_empty() {
                        out.push((atual.clone(), tok.to_string()));
                    }
                }
            }
            continue;
        }
        // cabeça de output: o primeiro token sem indent é o NOME
        if let Some(nome) = linha.split_whitespace().next() {
            if !nome.is_empty() && !nome.contains(':') {
                atual = nome.to_string();
            }
        }
    }
    out
}

/// o token parece um modo? (WxH@RATE — os dígitos conferidos)
fn modo_parece(t: &str) -> bool {
    let Some((wh, r)) = t.split_once('@') else { return false };
    let Some((w, h)) = wh.split_once('x') else { return false };
    !w.is_empty()
        && !h.is_empty()
        && !r.is_empty()
        && w.bytes().all(|b| b.is_ascii_digit())
        && h.bytes().all(|b| b.is_ascii_digit())
}

/// E150 — os modos SALVOS do displays.conf (linha canônica
/// `NOME|mode:WxH@RATE|…` — o mesmo formato que o do_save escreve).
pub fn displays_conf_modos(conf: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    for linha in conf.lines() {
        let t = linha.trim();
        if t.is_empty() || t.starts_with('#') {
            continue;
        }
        let c: Vec<&str> = t.split('|').collect();
        if c.len() < 2 || c[0].is_empty() {
            continue;
        }
        let modo = c[1].strip_prefix("mode:").unwrap_or("-");
        out.push((c[0].to_string(), modo.to_string()));
    }
    out
}

/// E150 — O CASAMENTO DA PERSISTÊNCIA (o juízo do '60 Hz sempre volta'):
/// cada modo SALVO no displays.conf contra o VIVO do wlr-randr — CONFERE
/// (os Hz do dono de pé), DIVERGE (o apply/boot re-estabelece) ou
/// AUSENTE (tela desplugada / randr calado). Conf vazio = nada salvo.
pub fn veredito_display(conf: &str, randr: &str) -> Vec<String> {
    let salvos = displays_conf_modos(conf);
    if salvos.is_empty() {
        return vec![
            "persistência: displays.conf vazio/ausente (nada salvo — o EDID manda; o menu do craft-display guarda o primeiro arranjo)".into(),
        ];
    }
    let vivos = randr_modos_atuais(randr);
    let mut linhas = Vec::new();
    for (nome, salvo) in salvos {
        if salvo == "-" {
            linhas.push(format!(
                "  {nome}: conf DOENTE (mode:- no papel — o E108 do craft-display: o save novo cura)"
            ));
            continue;
        }
        match vivos.iter().find(|(n, _)| *n == nome) {
            Some((_, vivo)) if vivo == &salvo => linhas.push(format!(
                "  {nome}: CONFERE ({salvo} aplicado — os Hz escolhidos vivos no boot)"
            )),
            Some((_, vivo)) => linhas.push(format!(
                "  {nome}: DIVERGE (salvo {salvo} · vivo {vivo} — o apply-boot/E150 do daemon re-estabelece)"
            )),
            None => linhas.push(format!(
                "  {nome}: tela ausente no wlr-randr (desplugada ou randr calado — nomeado, não inventado)"
            )),
        }
    }
    linhas
}

/// E150 — o source padrão do pactl info (a ENTRADA de áudio da casa —
/// o papel tinha só a saída; o microfone importa na perícia).
pub fn pactl_default_source(texto: &str) -> Option<String> {
    texto
        .lines()
        .find(|l| l.starts_with("Default Source:"))
        .map(|l| l["Default Source:".len()..].trim().to_string())
}

/// E150 — os três tempos da vigília no papel (LOCK/OFF/SUSPEND — a
/// fábrica 5/10/20 e o gesto separado; o 0 é NUNCA, nomeado).
pub fn idle_conf_tres(conf: &str) -> Vec<String> {
    let mut valores: [Option<&str>; 3] = [None, None, None];
    for linha in conf.lines() {
        for (i, chave) in ["LOCK_MIN", "OFF_MIN", "SUSPEND_MIN"].iter().enumerate() {
            if let Some(v) = linha.trim().strip_prefix(&format!("{chave}=")) {
                valores[i] = Some(v.trim());
            }
        }
    }
    let mut out = Vec::new();
    match valores[0] {
        Some("0") => out.push("  trava: NUNCA sozinha (LOCK_MIN=0 — o W-l manual manda)".to_string()),
        Some(l) => out.push(format!("  trava: LOCK_MIN={l} min de inatividade")),
        None => out.push("  trava: (LOCK_MIN ausente — a fábrica do daemon: 5)".to_string()),
    }
    match valores[1] {
        Some(o) if o != valores[0].unwrap_or("") => out.push(format!("  apaga: OFF_MIN={o} (o gesto separado E150)")),
        Some(o) => out.push(format!("  apaga: OFF_MIN={o} (junto do lock — o gesto único E43)")),
        None => out.push("  apaga: (OFF_MIN ausente — junto do lock)".to_string()),
    }
    match valores[2] {
        Some("0") => out.push("  sono: SUSPEND_MIN=0 (desligado)".to_string()),
        Some(s) => out.push(format!("  sono: SUSPEND_MIN={s} de travado (a vigília E60)")),
        None => out.push("  sono: (SUSPEND_MIN ausente — a fábrica: 20)".to_string()),
    }
    out
}

/// E150 — os campos vivos do $XDG_RUNTIME_DIR (nome · tipo · dono): a
/// função PURA recebe a lista (nome, e_socket, e_dir) já colhida.
pub fn linhas_runtime_dir(entradas: &[(String, bool, bool)]) -> Vec<String> {
    entradas
        .iter()
        .map(|(nome, socket, dir)| {
            let tipo = if *socket {
                "socket"
            } else if *dir {
                "dir"
            } else {
                "arquivo"
            };
            format!("  {nome} · {tipo}")
        })
        .collect()
}

#[cfg(test)]
mod tests_profunda {
    use super::*;

    #[test]
    fn a_cpu_o_modelo_e_a_memoria_sao_lidos_do_papel() {
        let cpuinfo = "processor\t: 0\nvendor_id : AuthenticAMD\nmodel name\t: AMD Ryzen 7 5800X3D 8-Core Processor\nprocessor\t: 1\n";
        assert_eq!(
            cpu_model(cpuinfo).as_deref(),
            Some("AMD Ryzen 7 5800X3D 8-Core Processor")
        );
        assert!(cpu_model("nada").is_none());
        let mem = "MemTotal:       32783448 kB\nMemFree:         1234560 kB\nMemAvailable:   24567892 kB\n";
        let (tot, disp) = meminfo_gib(mem).unwrap();
        assert!((tot - 31.3).abs() < 0.2, "total: {tot}");
        assert!((disp - 23.4).abs() < 0.2, "disp: {disp}");
        assert!(meminfo_gib("lixo").is_none());
    }

    #[test]
    fn a_vram_da_amdgpu_e_o_cmdline_sao_mastigados() {
        assert_eq!(vram_mib("8589934592\n"), Some(8192));
        assert!(vram_mib("cat\n").is_none());
        let cmd = "elite-daemon\0session\0";
        assert_eq!(cmdline_junta(cmd), "elite-daemon session");
        assert_eq!(cmdline_junta("craft-bar\0-rs"), "craft-bar -rs");
    }

    #[test]
    fn o_cpu_e_rss_do_processo_pela_conta_do_stat() {
        // stat de mentira: comm com espaço (o rsplit(')') acerta);
        // utime=100 ticks, stime=100 ticks; uptime 100s, HZ 100 →
        // (100+100)/100/100*100 = 2% de CPU cumulativa
        // 1.0-94 — O CAMPO FALTANTE (a mentira tinha TRÊS zeros no
        // minflt..cmajflt — o utime comia o cmajflt e o stime o zero:
        // 100 ticks lidos, 2% nunca saía; o teste nasceu quebrado na
        // 1.0-93 e o CI nunca viu porque o Canal só COMPILA — a lição
        // de lei: o teste da conta confere a CONTA, campo por campo)
        let stat = "1234 (elite-daemon) S 1 1234 1234 0 -1 4194560 0 0 0 0 100 100 0 0 20 0 1 0";
        let status = "Name:\telite-daemon\nVmRSS:\t  10240 kB\n";
        let (cpu, rss) = proc_cpu_rss(stat, status, 100.0, 100.0);
        assert!((cpu - 2.0).abs() < 0.01, "cpu: {cpu}");
        assert!((rss - 10.0).abs() < 0.01, "rss: {rss}");
        // comm com parêntese dentro (o wine) — o rsplit ainda acerta
        // (idem 1.0-94: os QUATRO zeros do minflt..cmajflt, os 100 ticks)
        let stat2 = "99 (wine64-preload) R 1 99 99 0 -1 0 0 0 0 0 50 50 0 0 20 0 1 0";
        let (cpu2, _) = proc_cpu_rss(stat2, "VmRSS:\t1 kB\n", 100.0, 100.0);
        assert!((cpu2 - 1.0).abs() < 0.01, "cpu2: {cpu2}");
        // sem uptime: 0 honesto (nunca NaN)
        let (cpu3, _) = proc_cpu_rss(stat, "", 0.0, 100.0);
        assert_eq!(cpu3, 0.0);
    }

    #[test]
    fn o_nome_do_dono_vem_do_uid_do_sudo() {
        let passwd = "root:x:0:0:root:/root:/bin/bash\nchris:x:1000:1001::/home/chris:/bin/zsh\n";
        assert_eq!(nome_do_uid(1000, passwd).as_deref(), Some("chris"));
        assert_eq!(nome_do_uid(0, passwd).as_deref(), Some("root"));
        assert!(nome_do_uid(9999, passwd).is_none());
    }
}

#[cfg(test)]
mod tests_fase2 {
    use super::*;
    use elite_core::bus::{BusServer, Incoming};
    use elite_core::{BusMsg, WindowInfo};

    #[test]
    fn o_legado_da_fase_2_e_completo() {
        for l in ["craft-menu", "craft-player", "craft-drawer", "craft-power", "craft-audio-route", "craft-toplevel", "swayidle"] {
            assert!(e_legado(l), "{l} é legado da 2.0");
        }
        // a família nova NÃO é legado
        for viva in ["craft-pick", "craft-update", "elite-dose", "nwg-drawer", "hyprlock"] {
            assert!(!e_legado(viva), "{viva} é a casa viva");
        }
    }

    #[test]
    fn a_colheita_do_bus_contra_o_daemon_falso() {
        let dir = std::env::temp_dir().join(format!("dump-bus-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let sock = dir.join("bus.sock");
        let (srv, rx) = BusServer::start(&sock).unwrap();
        // o daemon de mentira: boas-vindas completas + Ack
        std::thread::spawn(move || {
            for msg in rx {
                match msg {
                    Incoming::Hello { id, who } => {
                        assert!(who.starts_with("craft"));
                        srv.send_to(id, &BusMsg::Windows {
                            windows: vec![
                                WindowInfo { id: 1, app_id: "foot".into(), title: Some("foot".into()), focused: false, minimized: false, fullscreen: false },
                                WindowInfo { id: 2, app_id: "brave-browser".into(), title: Some("Arch Wiki".into()), focused: true, minimized: false, fullscreen: false },
                            ],
                        });
                        srv.send_to(id, &BusMsg::Workspace(elite_core::WorkspaceInfo {
                            current: 2, count: 4, label: None,
                        }));
                        srv.send_to(id, &BusMsg::Media(elite_core::MediaState {
                            player: Some("org.mpris.MediaPlayer2.mpv".into()),
                            title: Some("Stardew OST".into()),
                            artist: None,
                            playing: true,
                        }));
                        srv.send_to(id, &BusMsg::GameMode(elite_core::GameModeState {
                            active: true, game: Some("steam_app_413150".into()), gpu_performance: true,
                        }));
                        srv.send_to(id, &BusMsg::Audio(elite_core::AudioState {
                            sink_volume: 40, sink_muted: false, source_muted: false,
                            sink_name: Some("Starship/Matisse".into()), analog_preferred: true,
                        }));
                    }
                    Incoming::Req { cliente, req_id, .. } => {
                        srv.send_to(cliente, &BusMsg::Ack { id: req_id, ok: true });
                    }
                }
            }
        });
        let ColheitaBus::Vivo(c) = colhe_do_bus(&sock) else {
            panic!("o bus falso não respondeu")
        };
        assert_eq!(c.janelas, 2);
        assert_eq!(c.titulo.as_deref(), Some("Arch Wiki"));
        assert_eq!(c.mesa.as_ref().unwrap().current, 2);
        assert!(c.midia.as_ref().unwrap().playing);
        assert!(c.jogo.as_ref().unwrap().active);
        assert_eq!(c.audio.as_ref().unwrap().sink_volume, 40);
        // o papel fala tudo em pt_BR
        let papel = linhas_bus(&c);
        let tudo = papel.join("\n");
        assert!(tudo.contains("2 janela(s)"));
        assert!(tudo.contains("mesa 2/4"));
        assert!(tudo.contains("tocando"));
        assert!(tudo.contains("3D_FULL_SCREEN"));
        assert!(tudo.contains("Starship/Matisse"));
        // bus morto: RECUSADO honesto (o papel nomeia, nunca inventa)
        assert_eq!(
            colhe_do_bus(&dir.join("nao-existe.sock")),
            ColheitaBus::Recusado
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn o_papel_do_bus_vazio_e_honrado() {
        let c = BusColheita::default();
        let papel = linhas_bus(&c);
        assert!(papel[0].contains("0 janela(s)"));
        assert!(papel[1].contains("desktop puro"));
        assert!(papel.join("\n").contains("SEM ESTADO no fio"));
        assert!(papel.join("\n").contains("SEM ESTADO no fio"));
    }

    #[test]
    fn o_default_sink_do_pactl_e_cacado_na_linha_certa() {
        let papel = "Server String: /run/user/1000/pulse/native\nLibrary Protocol Version: 35\nDefault Sink: alsa_output.pci-0000_14_0.analog-stereo\nDefault Source: alsa_input.pci-0000_14_0.analog-stereo\n";
        assert_eq!(
            pactl_default_sink(papel).as_deref(),
            Some("alsa_output.pci-0000_14_0.analog-stereo")
        );
        assert!(pactl_default_sink("sem nada").is_none());
    }

    #[test]
    fn os_erros_conhecidos_do_boot_ganham_o_veredito_na_cara() {
        // 1.0-94 — o rig da 1.0-93: as linhas benignas do journal viravam
        // alarme mudo no papel curto; a perícia conhecida entra NA CARA
        assert!(anota_conhecido(
            "bluetoothd[891]: Refusing input device connect: No such file or directory (2)"
        )
        .unwrap()
            .contains("benigno"));
        assert!(anota_conhecido(
            "bluetoothd[891]: Refusing connection from ED:25:F0:0E:B7:A4: unknown device"
        )
        .is_some());
        assert!(anota_conhecido(
            "bluetoothd[891]: Fallback profile connection failed: Device or resource busy (16)"
        )
        .is_some());
        assert!(anota_conhecido(
            "wpa_supplicant[812]: nl80211: kernel reports: multicast RX registrations are not supported"
        )
        .is_some());
        assert!(anota_conhecido(
            "kernel: usbhid 3-4:1.4: couldn't find an input interrupt endpoint"
        )
        .is_some());
        assert!(anota_conhecido("kernel: virt/tdx: TDX not supported by the host platform").is_some());
        // o overdrive é a LEI da casa, não defeito
        assert!(anota_conhecido("amdgpu: Overdrive is enabled").unwrap().contains("esperado"));
        // linha desconhecida: None (segue crua — o papel não inventa)
        assert!(anota_conhecido("systemd[1]: Failed to start FancyService.service").is_none());
    }

    #[test]
    fn o_lavd_que_dorme_e_nomeado_nao_assustador() {
        // unit presente + kernel sem sched_ext = o lavd dorme por DESENHO
        assert!(linha_scx(false, true).unwrap().contains("DORME"));
        // kernel com sched_ext: nada a dizer (o lavd sobe)
        assert!(linha_scx(true, true).is_none());
        // unit ausente: o papel do serviço já nomeou
        assert!(linha_scx(false, false).is_none());
    }

    #[test]
    fn o_home_do_dono_e_resolvido_no_passwd() {
        // 1.0-94 — o dump do pkexec lê os papéis da SESSÃO de quem pediu
        let passwd = "root:x:0:0:root:/root:/bin/bash\nchris:x:1000:1000:Chris:/home/chris:/bin/zsh\n";
        assert_eq!(home_do_uid(1000, passwd).as_deref(), Some("/home/chris"));
        assert_eq!(home_do_uid(0, passwd).as_deref(), Some("/root"));
        assert!(home_do_uid(999, passwd).is_none());
        // o nome segue na mesma gramática
        assert_eq!(nome_do_uid(1000, passwd).as_deref(), Some("chris"));
    }
}

#[cfg(test)]
mod tests_e150_sistemico {
    use super::*;

    #[test]
    fn e150_o_free_m_e_parseado_nos_6_campos() {
        let papel = "               total        used        free      shared  buff/cache   available\n\
                     Mem:          15920        4510        9800         220        1610       10850\n\
                     Swap:          7679         200        7479\n";
        let (t, u, bc, a, st, su) = parse_free_m(papel).unwrap();
        assert_eq!((t, u, bc, a, st, su), (15920, 4510, 1610, 10850, 7679, 200));
        // sem Swap (rig sem zram): o zero honesto, a Mem segue
        let so_mem = "Mem: 100 10 80 1 9 90\n";
        let (t, _, _, _, st, _) = parse_free_m(so_mem).unwrap();
        assert_eq!(t, 100);
        assert_eq!(st, 0, "sem linha Swap o papel não inventa swap");
        // lixo: None
        assert!(parse_free_m("lixo total\n").is_none());
    }

    #[test]
    fn e150_o_zramctl_fala_os_campos_vivos() {
        let papel = "NAME       DISKSIZE   DATA  COMPR  TOTAL STREAMS MOUNTPOINT\n\
                     /dev/zram0     7.5G 120.4M  21.3M  32.5M      16 [SWAP]\n";
        let (disk, data, total) = zramctl_campos(papel).unwrap();
        assert_eq!((disk.as_str(), data.as_str(), total.as_str()), ("7.5G", "120.4M", "32.5M"));
        // sem zram montado (zramctl vazio): None honesto
        assert!(zramctl_campos("").is_none());
    }

    #[test]
    fn e150_o_ranking_rss_ordena_e_corta() {
        let v = vec![
            (1, "a".into(), 100u64),
            (2, "b".into(), 900u64),
            (3, "c".into(), 500u64),
        ];
        let top = rank_rss(v, 2);
        assert_eq!(top[0].0, 2, "o maior RSS primeiro");
        assert_eq!(top.len(), 2, "o corte de N");
        // empate: o pid menor na frente (estabilidade legível)
        let v2 = vec![(9, "x".into(), 50u64), (4, "y".into(), 50u64)];
        let top2 = rank_rss(v2, 5);
        assert_eq!(top2[0].0, 4);
    }

    #[test]
    fn e150_o_rss_do_status_e_o_vmrss() {
        let status = "Name: brave\nVmPeak: 1000 kB\nVmRSS: 24000 kB\n";
        assert_eq!(rss_kib_do_status(status), 24000);
        // zumbi/kernel thread: 0 (sem VmRSS)
        assert_eq!(rss_kib_do_status("Name: kworker\n"), 0);
    }

    #[test]
    fn e150_a_contagem_de_pacotas_conta_linhas_vivas() {
        assert_eq!(conta_linhas("a 1\nb 2\nc 3\n"), 3);
        assert_eq!(conta_linhas("\n\na\n\n"), 1);
        assert_eq!(conta_linhas(""), 0);
    }

    #[test]
    fn e150_os_modos_atuais_do_randr_pela_marca_current() {
        // o papel REAL do wlr-randr 0.5 (a marca da casa é "(current)",
        // isolada — a mesma gramática que o awk do craft-display casa)
        let randr = "DP-1 (AMD Radeon RX 7600 [DRM])\n  Physical: 530x300 mm\n  Enabled: yes\n  Modes:\n    1920x1080@60.000\n    1920x1080@200.000 (current) (preferred)\n  Position: 0,0\n  Transform: normal\n  Scale: 1.000000\n  Adaptive sync: enabled\n";
        let vivos = randr_modos_atuais(randr);
        assert_eq!(vivos.len(), 1);
        assert_eq!(vivos[0], ("DP-1".to_string(), "1920x1080@200.000".to_string()));
        // duas telas, uma sem modo atual: só a com marca entra
        let dois = "DP-1 (A)\n  Modes:\n    1920x1080@144.000 (current)\nHDMI-A-1 (B)\n  Modes:\n    1920x1080@60.000\n";
        assert_eq!(randr_modos_atuais(dois).len(), 1);
        // a 0.4 (Current mode: na linha própria): o parser honesto não casa
        // (a casa toda casa a 0.5 do rig — a fronteira nomeada no modo_parece)
        let v04 = "DP-1 (A)\n  Current mode: 1920x1080@144.000\n";
        assert_eq!(randr_modos_atuais(v04).len(), 0);
        // sem randr: vazio (a ausência é nomeada no main)
        assert!(randr_modos_atuais("").is_empty());
    }

    #[test]
    fn e150_o_veredito_da_persistencia_casa_salvo_com_vivo() {
        let conf = "# cabeça da casa\nDP-1|mode:1920x1080@200.000|pos:0,0|scale:1|transform:normal|adaptive:enabled\n";
        let conf_doente = "DP-2|mode:-|pos:0,0\n";
        let randr = "DP-1 (A)\n  Modes:\n    1920x1080@200.000 (current)\n";
        let v = veredito_display(conf, randr);
        assert!(v.iter().any(|l| l.contains("CONFERE")), "o Hz salvo aplicado: {v:?}");
        // divergiu (o 60 Hz do boot frio antes da re-aplicação)
        let randr_60 = "DP-1 (A)\n  Modes:\n    1920x1080@60.000 (current)\n";
        let v2 = veredito_display(conf, randr_60);
        assert!(v2.iter().any(|l| l.contains("DIVERGE")), "{v2:?}");
        // conf doente nomeado
        let v3 = veredito_display(conf_doente, randr);
        assert!(v3.iter().any(|l| l.contains("DOENTE")), "{v3:?}");
        // conf vazio
        assert!(veredito_display("", randr)[0].contains("vazio/ausente"));
    }

    #[test]
    fn e150_os_tres_tempos_da_vigilia_no_papel() {
        let conf = "LOCK_MIN=5\nOFF_MIN=10\nSUSPEND_MIN=20\n";
        let l = idle_conf_tres(conf);
        assert!(l.iter().any(|x| x.contains("LOCK_MIN=5")));
        assert!(l.iter().any(|x| x.contains("OFF_MIN=10") && x.contains("gesto separado")));
        // o gesto único de sempre
        let l2 = idle_conf_tres("LOCK_MIN=5\nOFF_MIN=5\n");
        assert!(l2.iter().any(|x| x.contains("junto do lock")));
        // nunca sozinho
        let l3 = idle_conf_tres("LOCK_MIN=0\n");
        assert!(l3.iter().any(|x| x.contains("NUNCA")));
    }

    #[test]
    fn e150_o_source_padrao_do_pactl() {
        let info = "Server Name: PulseAudio (on PipeWire 1.0.0)\nDefault Sink: alsa_output.pci-0000_11_00.4.analog-stereo\nDefault Source: alsa_input.usb-Fifine_Microphone_0000\n";
        assert_eq!(
            pactl_default_source(info).as_deref(),
            Some("alsa_input.usb-Fifine_Microphone_0000")
        );
        assert!(pactl_default_source("sem nada").is_none());
    }

    #[test]
    fn e150_as_linhas_do_runtime_dir_dizem_o_tipo() {
        let l = linhas_runtime_dir(&[
            ("wayland-0".into(), true, false),
            ("pipewire-0".into(), true, false),
            ("dconf".into(), false, true),
            ("elite".into(), false, true),
        ]);
        assert!(l.iter().any(|x| x.contains("wayland-0 · socket")));
        assert!(l.iter().any(|x| x.contains("dconf · dir")));
    }
}
