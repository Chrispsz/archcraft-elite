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
