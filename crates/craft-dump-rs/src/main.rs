// ═════════════════════════════════════════════════════════════════════════
// craft-dump v2 — A MÃO QUE COLHE (o núcleo puro mora no lib.rs).
// FASE 2 COMPLETA: o papel que se conhece DE VERDADE — identidade do
// boot, kernel vivo (cmdline + sysctl + zram), serviços críticos,
// família nativa de pé, LEGADO ausente (a lista 2.0 inteira), o FIO
// vivo (bus.sock: janelas, mesa, mídia, jogo, áudio) e o áudio da
// mesa (o default do PipeWire).
// 1.0-93 — A TELEMETRIA PROFUNDA DE VOLTA (a ordem do dono, rig da
// 1.0-92): hardware (CPU/memória/GPU/VRAM), o cmdline e o RSS/CPU%
// dos processos da sessão, o sysctl vivo, o scx-lavd REAL, os
// sinks/sources do PipeWire, o wlr-randr, os erros do journal do
// boot, o pacman recente, o SUDO_UID resolvido (o dump do pkexec
// colhe a sessão do DONO, não do root) e o --upload (termbin.com —
// PÚBLICO, avisado antes de subir).
// Roda no RIG e na sessão de prova — sem systemd/bus o papel NOMEIA
// as ausências, nunca mente.
// ═════════════════════════════════════════════════════════════════════════
use std::io::Write as _;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let quer_upload = args.iter().any(|a| a == "--upload");
    let mut papel = String::new();
    let mut say = |linha: &str| {
        println!("{linha}");
        papel.push_str(linha);
        papel.push('\n');
    };
    if quer_upload {
        say("AVISO: o --upload sobe o papel NO termbin.com — PÚBLICO (redes sem\nsenhas vêm nomeadas; nada de segredo em papel de perícia).");
        say("");
    }

    // 1.0-93 — O UID DO DONO (o SUDO_UID do pkexec vence: o dump de
    // raiz colhe a SESSÃO de quem pediu, não a do root)
    let (uid, dono) = uid_e_dono();
    say(&format!(
        "═ ARCHCRAFT ELITE · craft-dump v2 · era nativa 2.0 (v{}) ═",
        env!("CARGO_PKG_VERSION")
    ));
    say(&format!(
        "sessão: bus.sock em {:?} (uid {uid}{}) · estado do dono em {:?}",
        elite_core::bus_sock_path(uid),
        dono.as_deref().map(|d| format!(" · {d}")).unwrap_or_default(),
        elite_core::elite_config_dir()
    ));
    // 1.0-93 — a versão do pacote da casa (o pacman fala; sem ele, calado)
    if let Some(versao) = colhe(&["pacman", "-Q", "elite-system"]) {
        say(&format!("pacote: {}", versao.trim()));
    }

    // ── HARDWARE (1.0-93): CPU, memória, GPU e VRAM ─────────────────────
    say("");
    say("hardware:");
    if let Ok(cpuinfo) = std::fs::read_to_string("/proc/cpuinfo") {
        if let Some(modelo) = craft_dump_rs::cpu_model(&cpuinfo) {
            say(&format!("  cpu: {modelo}"));
        }
    }
    if let Ok(mem) = std::fs::read_to_string("/proc/meminfo") {
        if let Some((tot, disp)) = craft_dump_rs::meminfo_gib(&mem) {
            say(&format!(
                "  memória: {tot:.1} GiB no total · {disp:.1} GiB disponível"
            ));
        }
    }
    if let Some(lspci) = colhe(&["lspci"]) {
        for linha in lspci.lines().filter(|l| {
            l.contains("VGA compatible") || l.contains("3D controller") || l.contains("Display")
        }) {
            say(&format!("  gpu: {}", linha.trim()));
        }
    }
    // a VRAM do amdgpu (o sysfs de cada card; GPU de outro driver é
    // NOMEADA honesta — o lspci acima já falou o modelo)
    if let Ok(dir) = std::fs::read_dir("/sys/class/drm") {
        for e in dir.flatten() {
            let nome = e.file_name();
            let Some(nome) = nome.to_str() else { continue };
            if !nome.starts_with("card") || nome.contains('-') {
                continue;
            }
            if let Ok(b) =
                std::fs::read_to_string(e.path().join("device/mem_info_vram_total"))
            {
                if let Some(mib) = craft_dump_rs::vram_mib(&b) {
                    say(&format!("  vram: {nome} · {mib} MiB (amdgpu)"));
                }
            }
        }
    }

    // ── BOOT: o cmdline do kernel vivo + o tuning vivo (sysctl/proc) ────
    let cmdline = std::fs::read_to_string("/proc/cmdline").unwrap_or_default();
    say("");
    say("boot (cmdline do kernel vivo):");
    for linha in craft_dump_rs::juizo_boot(&cmdline) {
        say(&format!("  {linha}"));
    }
    if craft_dump_rs::cmdline_tem(&cmdline, "ntsync") {
        say("  boot: ntsync PRESENTE");
    } else {
        say("  boot: ntsync AUSENTE");
    }
    say("sysctl vivo:");
    for (chave, rotulo) in [
        ("/proc/sys/vm/swappiness", "vm.swappiness (a lei da casa: 180)"),
        ("/proc/sys/vm/max_map_count", "vm.max_map_count (jogos: 2147483642)"),
        (
            "/proc/sys/net/ipv4/tcp_congestion_control",
            "tcp_congestion_control (a casa: bbr)",
        ),
    ] {
        let valor = std::fs::read_to_string(chave)
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|_| "?".into());
        say(&format!("  {rotulo} = {valor}"));
    }
    if let Ok(zram) = std::fs::read_to_string("/sys/block/zram0/disksize") {
        if zram.trim() != "0" {
            say(&format!("  tuning: zram0 vivo ({})", zram.trim()));
        } else {
            say("  tuning: zram0 de tamanho 0 (o réu nomeado: o módulo existe, a casa não armou)");
        }
    } else {
        say("  tuning: zram0 AUSENTE (o réu nomeado no papel)");
    }

    // ── SERVIÇOS: o systemctl colhido cru ────────────────────────────────
    let saida = colhe(&["systemctl", "--no-legend", "--all", "list-unit-files"])
        .unwrap_or_default();
    if saida.is_empty() {
        say("serviços: systemctl indisponível aqui — o papel não mente (rig real julga)");
    } else {
        say("");
        say("serviços críticos:");
        // 1.0-93 — o scx-lavd REAL entra na lista (a unit nova da casa)
        for unit in craft_dump_rs::SERVICOS_CRITICOS {
            say(&format!("  {}", craft_dump_rs::linha_servico(&saida, unit)));
        }
        say(&format!(
            "  {}",
            craft_dump_rs::linha_servico(&saida, "scx-lavd")
        ));
        // o ESTADO vivo do escalonador (a unit ligada ≠ o daemon ativo)
        if let Some(ativo) = colhe(&["systemctl", "is-active", "scx-lavd"]) {
            say(&format!("  scx-lavd.service: {}", ativo.trim()));
        }
        if let Ok(sched_ext) = std::fs::read_to_string("/sys/kernel/sched_ext") {
            say(&format!(
                "  sched_ext: {}",
                if sched_ext.trim() == "1" { "DISPONÍVEL" } else { "estado inesperado" }
            ));
        } else {
            say("  sched_ext: AUSENTE (kernel sem a interface)");
        }
    }

    // ── A FAMÍLIA NATIVA + O LEGADO (com RSS/CPU%/cmdline — 1.0-93) ─────
    say("");
    say("família nativa 2.0 (comms vivos · RSS · CPU% cumulativa · cmdline):");
    let uptime = uptime_segundos();
    let hz = 100.0f64; // USER_HZ do Linux (x86_64 — o valor de sempre)
    let mut comms: Vec<String> = Vec::new();
    let mut pids_familia: Vec<(u32, String)> = Vec::new();
    if let Ok(rd) = std::fs::read_dir("/proc") {
        for entry in rd.flatten() {
            let pid = match entry.file_name().to_string_lossy().parse::<u32>() {
                Ok(p) => p,
                Err(_) => continue,
            };
            let Ok(comm) = std::fs::read_to_string(format!("/proc/{pid}/comm")) else {
                continue;
            };
            let comm = comm.trim().to_string();
            if comm.is_empty() {
                continue;
            }
            if !comms.contains(&comm) {
                comms.push(comm.clone());
            }
            if craft_dump_rs::FAMILIA_SESSAO.contains(&comm.as_str()) {
                pids_familia.push((pid, comm));
            }
        }
    }
    for membro in craft_dump_rs::FAMILIA_SESSAO {
        if comms.iter().any(|c| c == membro) {
            say(&format!("  {membro} DE PÉ"));
        } else {
            say(&format!("  {membro} AUSENTE (a sessão não é 2.0 ou não subiu)"));
        }
    }
    for (pid, comm) in pids_familia {
        let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).unwrap_or_default();
        let status = std::fs::read_to_string(format!("/proc/{pid}/status")).unwrap_or_default();
        let cmdline_p =
            std::fs::read_to_string(format!("/proc/{pid}/cmdline")).unwrap_or_default();
        let (cpu, rss) = craft_dump_rs::proc_cpu_rss(&stat, &status, uptime, hz);
        say(&format!(
            "  · pid {pid} ({comm}): RSS {rss:.0} MiB · CPU {cpu:.1}% · cmdline: {}",
            craft_dump_rs::cmdline_junta(&cmdline_p)
        ));
    }
    let legados_vivos: Vec<&str> = comms
        .iter()
        .filter(|c| craft_dump_rs::e_legado(c))
        .map(|c| c.as_str())
        .collect();
    if legados_vivos.is_empty() {
        say("legado: NENHUMA era antiga viva (a lista 2.0 inteira limpa)");
    } else {
        say(&format!(
            "legado: AINDA VIVO — {legados_vivos:?} (o réu nomeado; a cura é a dose)"
        ));
    }

    // ── O FIO VIVO: o bus.sock (a fonte da verdade da sessão) ───────────
    say("");
    let caminho = elite_core::bus_sock_path(uid);
    match craft_dump_rs::colhe_do_bus(&caminho) {
        Some(colheita) => {
            say(&format!("bus.sock VIVO ({}):", caminho.display()));
            for linha in craft_dump_rs::linhas_bus(&colheita) {
                say(&format!("  {linha}"));
            }
        }
        None => say(&format!(
            "bus.sock MORTO em {} — o daemon não atende (a sessão segue sem fio; nomeado, não inventado)",
            caminho.display()
        )),
    }

    // ── ÁUDIO DA MESA: o default + os sinks/sources do PipeWire ─────────
    say("");
    match colhe(&["pactl", "info"]).map(|s| craft_dump_rs::pactl_default_sink(&s)) {
        Some(Some(sink)) => say(&format!("áudio: default do PipeWire = {sink}")),
        _ => say("áudio: pactl indisponível/sem resposta (rig real julga)"),
    }
    if let Some(sinks) = colhe(&["pactl", "list", "short", "sinks"]) {
        for linha in sinks.lines().take(8) {
            say(&format!("  sink: {linha}"));
        }
    }
    if let Some(sources) = colhe(&["pactl", "list", "short", "sources"]) {
        for linha in sources.lines().take(8) {
            say(&format!("  source: {linha}"));
        }
    }

    // ── A VIGÍLIA: o conf vivo (o daemon arma com ESTES valores) ─────────
    let conf_idle = elite_core::elite_config_dir().join("idle.conf");
    match std::fs::read_to_string(&conf_idle) {
        Ok(papel_conf) => {
            let lock = papel_conf
                .lines()
                .find(|l| l.starts_with("LOCK_MIN="))
                .and_then(|l| l.split('=').nth(1))
                .unwrap_or("?");
            say(&format!(
                "vigília: LOCK_MIN={lock} (o elite-daemon arma a trava com este papel)"
            ));
        }
        Err(_) => say("vigília: idle.conf ausente (a fábrica do daemon: 5 min)"),
    }

    // ── 1.0-93 · OS MONITORES (o wlr-randr cru) ──────────────────────────
    if let Some(randr) = colhe(&["wlr-randr"]) {
        say("");
        say("monitores (wlr-randr):");
        for linha in randr.lines().take(30) {
            say(&format!("  {linha}"));
        }
    }

    // ── 1.0-93 · OS ERROS DO BOOT (journalctl -p err -b) ─────────────────
    if let Some(journal) = colhe(&["journalctl", "-p", "err", "-b", "--no-pager", "-n", "30"]) {
        say("");
        say("erros do boot (journalctl -p err -b, os últimos 30):");
        for linha in journal.lines() {
            say(&format!("  {linha}"));
        }
    }

    // ── 1.0-93 · O PACMAN RECENTE (as doses que chegaram) ────────────────
    if let Ok(log_pacman) = std::fs::read_to_string("/var/log/pacman.log") {
        say("");
        say("pacman (as linhas recentes):");
        for linha in log_pacman.lines().rev().take(15).collect::<Vec<_>>() {
            say(&format!("  {linha}"));
        }
    }

    say("═ fim do papel — a sessão é o juiz, o papel é a testemunha ═");

    // ── 1.0-93 · O UPLOAD (termbin.com — PÚBLICO, avisado no topo) ──────
    if quer_upload {
        match sobe_termbin(&papel) {
            Ok(url) => {
                println!("upload: {url}");
            }
            Err(e) => {
                println!("upload: FALHOU ({e}) — o papel completo está acima, nada se perdeu");
                std::process::exit(1);
            }
        }
    }
}

/// O uid REAL do processo (procfs — a casa não simula identidade) +
/// o nome do dono quando o /etc/passwd fala.
fn uid_e_dono() -> (u32, Option<String>) {
    // 1.0-93 — O SUDO_UID VENCE: o dump sobe pelo pkexec (raiz); a
    // SESSÃO que interessa é a do DONO que pediu, não a do root
    if let Ok(sudo) = std::env::var("SUDO_UID") {
        if let Ok(uid) = sudo.trim().parse::<u32>() {
            let passwd = std::fs::read_to_string("/etc/passwd").unwrap_or_default();
            return (uid, craft_dump_rs::nome_do_uid(uid, &passwd));
        }
    }
    let uid = std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("Uid:"))
                .and_then(|l| l.split_whitespace().nth(1).and_then(|v| v.parse().ok()))
        })
        .unwrap_or(1000);
    (uid, None)
}

/// Colhe UM comando (stdout cru; None honesto em qualquer engasgo —
/// a ausência é nomeada, nunca inventada).
fn colhe(argv: &[&str]) -> Option<String> {
    let out = std::process::Command::new(argv[0])
        .args(&argv[1..])
        .stdin(std::process::Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// O uptime do sistema em segundos (/proc/uptime — a conta do CPU%).
fn uptime_segundos() -> f64 {
    std::fs::read_to_string("/proc/uptime")
        .ok()
        .and_then(|s| s.split_whitespace().next().and_then(|v| v.parse().ok()))
        .unwrap_or(0.0)
}

/// Sobe o papel no termbin.com via curl (stdin → URL curta na stdout;
/// o papel nunca toca o disco — nada de fóssil de perícia em /tmp).
fn sobe_termbin(papel: &str) -> Result<String, String> {
    use std::process::{Command, Stdio};
    let mut filho = Command::new("curl")
        .args(["--data-binary", "@-", "-s", "--max-time", "20", "https://termbin.com"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("o curl não nasceu: {e}"))?;
    if let Some(mut entrada) = filho.stdin.take() {
        entrada
            .write_all(papel.as_bytes())
            .map_err(|e| format!("o papel não coube no fio: {e}"))?;
    }
    let saida = filho
        .wait_with_output()
        .map_err(|e| format!("o curl morreu: {e}"))?;
    let url = String::from_utf8_lossy(&saida.stdout).trim().to_string();
    if url.starts_with("http") {
        Ok(url)
    } else {
        Err("o termbin não devolveu URL".into())
    }
}
