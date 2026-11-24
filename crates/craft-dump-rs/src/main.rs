// craft-dump-rs — a mão que colhe (o núcleo puro está no lib.rs).
// FASE 1: o binário nomeia a era e os juízes do núcleo contra o que a
// sessão real responde — colheita mínima honesta (cmdline + systemctl).
// A coleta v2 completa (bus.sock, journal PrepareForSleep, latência) é Fase 2.
fn main() {
    let cabecalho = format!(
        "═ ARCHCRAFT ELITE · craft-dump-rs v2 · era nativa 2.0 (pkgrel {}) ═",
        env!("CARGO_PKG_VERSION")
    );
    println!("{cabecalho}");

    // a morada do fio da sessão (o contrato do elite-core — o dump v2 fala
    // a língua da casa: o bus.sock onde a barra e a dock assinam)
    let uid = libc_like_uid();
    println!(
        "sessão: bus.sock em {:?} · estado do dono em {:?}",
        elite_core::bus_sock_path(uid),
        elite_core::elite_config_dir()
    );

    // boot: o cmdline real do kernel vivo
    let cmdline = std::fs::read_to_string("/proc/cmdline").unwrap_or_default();
    println!("boot (cmdline do kernel vivo):");
    for linha in craft_dump_rs::juizo_boot(&cmdline) {
        println!("  {linha}");
    }

    // serviços: o systemctl é colhido cru (sem systemd → papel honesto e vazio)
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

    // legado: os comms vivos do /proc contra a lista da casa
    let mut legados_vivos = Vec::new();
    if let Ok(rd) = std::fs::read_dir("/proc") {
        for entry in rd.flatten() {
            let nome = entry.file_name();
            let pid = match nome.to_string_lossy().parse::<u32>() {
                Ok(p) => p,
                Err(_) => continue,
            };
            if let Ok(comm) = std::fs::read_to_string(format!("/proc/{pid}/comm")) {
                let comm = comm.trim();
                if craft_dump_rs::e_legado(comm) && !legados_vivos.contains(&comm.to_string()) {
                    legados_vivos.push(comm.to_string());
                }
            }
        }
    }
    if legados_vivos.is_empty() {
        println!("legado: NENHUMA era antiga viva na sessão (waybar/craft-audio/craft-bars/craft-connect)");
    } else {
        println!("legado: AINDA VIVO — {legados_vivos:?} (o réu nomeado; a cura é a dose)");
    }
}

/// O uid REAL do processo (procfs — a casa não simula identidade).
fn libc_like_uid() -> u32 {
    // getuid sem libc: a leitura honesta é o /proc/self/status (UId:)
    std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| {
            s.lines().find(|l| l.starts_with("Uid:"))
                .and_then(|l| l.split_whitespace().nth(1).and_then(|v| v.parse().ok()))
        })
        .unwrap_or(1000)
}
