// ═════════════════════════════════════════════════════════════════════════
// craft-dump v2 — A MÃO QUE COLHE (o núcleo puro mora no lib.rs).
// FASE 2 COMPLETA: o papel que se conhece DE VERDADE — identidade do
// boot, kernel vivo (cmdline + swappiness + zram), serviços críticos,
// família nativa de pé, LEGADO ausente (a lista 2.0 inteira), o FIO
// vivo (bus.sock: janelas, mesa, mídia, jogo, áudio) e o áudio da
// mesa (o default do PipeWire). Roda no RIG e na sessão de prova —
// sem systemd/bus o papel NOMEIA as ausências, nunca mente.
// ═════════════════════════════════════════════════════════════════════════
fn main() {
    println!(
        "═ ARCHCRAFT ELITE · craft-dump v2 · era nativa 2.0 (v{}) ═",
        env!("CARGO_PKG_VERSION")
    );
    let uid = libc_like_uid();
    println!(
        "sessão: bus.sock em {:?} · estado do dono em {:?}",
        elite_core::bus_sock_path(uid),
        elite_core::elite_config_dir()
    );

    // ── BOOT: o cmdline do kernel vivo + o tuning vivo (sysctl/proc) ────
    let cmdline = std::fs::read_to_string("/proc/cmdline").unwrap_or_default();
    println!("boot (cmdline do kernel vivo):");
    for linha in craft_dump_rs::juizo_boot(&cmdline) {
        println!("  {linha}");
    }
    if craft_dump_rs::cmdline_tem(&cmdline, "ntsync") {
        println!("  boot: ntsync PRESENTE");
    } else {
        println!("  boot: ntsync AUSENTE");
    }
    let swappiness = std::fs::read_to_string("/proc/sys/vm/swappiness")
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|_| "?".into());
    println!("  tuning: vm.swappiness vivo = {swappiness} (a lei da casa: 180)");
    if let Ok(zram) = std::fs::read_to_string("/sys/block/zram0/disksize") {
        if zram.trim() != "0" {
            println!("  tuning: zram0 vivo ({})", zram.trim());
        } else {
            // o arquivo existe com 0: o bloco nasceu mas ninguém o armou
            println!("  tuning: zram0 de tamanho 0 (o réu nomeado: o módulo existe, a casa não armou)");
        }
    } else {
        println!("  tuning: zram0 AUSENTE (o réu nomeado no papel)");
    }

    // ── SERVIÇOS: o systemctl colhido cru ────────────────────────────────
    let saida = std::process::Command::new("systemctl")
        .args(["--no-legend", "--all", "list-unit-files"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
        .unwrap_or_default();
    if saida.is_empty() {
        println!("serviços: systemctl indisponível aqui — o papel não mente (rig real julga)");
    } else {
        println!("serviços críticos:");
        for unit in craft_dump_rs::SERVICOS_CRITICOS {
            println!("  {}", craft_dump_rs::linha_servico(&saida, unit));
        }
    }

    // ── A FAMÍLIA NATIVA + O LEGADO (os comms vivos do /proc) ────────────
    let mut comms: Vec<String> = Vec::new();
    if let Ok(rd) = std::fs::read_dir("/proc") {
        for entry in rd.flatten() {
            let pid = match entry.file_name().to_string_lossy().parse::<u32>() {
                Ok(p) => p,
                Err(_) => continue,
            };
            if let Ok(comm) = std::fs::read_to_string(format!("/proc/{pid}/comm")) {
                let comm = comm.trim().to_string();
                if !comm.is_empty() && !comms.contains(&comm) {
                    comms.push(comm);
                }
            }
        }
    }
    println!("família nativa 2.0 (comms vivos):");
    for membro in craft_dump_rs::FAMILIA_SESSAO {
        if comms.iter().any(|c| c == membro) {
            println!("  {membro} DE PÉ");
        } else {
            println!("  {membro} AUSENTE (a sessão não é 2.0 ou não subiu)");
        }
    }
    let legados_vivos: Vec<&str> = comms
        .iter()
        .filter(|c| craft_dump_rs::e_legado(c))
        .map(|c| c.as_str())
        .collect();
    if legados_vivos.is_empty() {
        println!("legado: NENHUMA era antiga viva (a lista 2.0 inteira limpa)");
    } else {
        println!("legado: AINDA VIVO — {legados_vivos:?} (o réu nomeado; a cura é a dose)");
    }

    // ── O FIO VIVO: o bus.sock (a fonte da verdade da sessão) ───────────
    let caminho = elite_core::bus_sock_path(uid);
    match craft_dump_rs::colhe_do_bus(&caminho) {
        Some(colheita) => {
            println!("bus.sock VIVO ({}):", caminho.display());
            for linha in craft_dump_rs::linhas_bus(&colheita) {
                println!("  {linha}");
            }
        }
        None => println!(
            "bus.sock MORTO em {} — o daemon não atende (a sessão segue sem fio; nomeado, não inventado)",
            caminho.display()
        ),
    }

    // ── ÁUDIO DA MESA: o default do PipeWire (o pactl info) ─────────────
    let pactl = std::process::Command::new("pactl")
        .arg("info")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string());
    match pactl.as_deref().and_then(craft_dump_rs::pactl_default_sink) {
        Some(sink) => println!("áudio: default do PipeWire = {sink}"),
        None => println!("áudio: pactl indisponível/sem resposta (rig real julga)"),
    }

    // ── A VIGÍLIA: o conf vivo (o daemon arma com ESTES valores) ─────────
    let conf_idle = elite_core::elite_config_dir().join("idle.conf");
    match std::fs::read_to_string(&conf_idle) {
        Ok(papel) => {
            let lock = papel
                .lines()
                .find(|l| l.starts_with("LOCK_MIN="))
                .and_then(|l| l.split('=').nth(1))
                .unwrap_or("?");
            println!("vigília: LOCK_MIN={lock} (o elite-daemon arma a trava com este papel)");
        }
        Err(_) => println!("vigília: idle.conf ausente (a fábrica do daemon: 5 min)"),
    }
    println!("═ fim do papel — a sessão é o juiz, o papel é a testemunha ═");
}

/// O uid REAL do processo (procfs — a casa não simula identidade).
fn libc_like_uid() -> u32 {
    std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("Uid:"))
                .and_then(|l| l.split_whitespace().nth(1).and_then(|v| v.parse().ok()))
        })
        .unwrap_or(1000)
}
