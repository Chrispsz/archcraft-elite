// ═════════════════════════════════════════════════════════════════════════
// craft-dump v2 — A MÃO QUE COLHE (o núcleo puro mora no lib.rs).
// FASE 2 COMPLETA: o papel que se conhece DE VERDADE — identidade do
// boot, kernel vivo (cmdline + sysctl + zram), serviços críticos,
// família nativa de pé, LEGADO ausente (a lista 2.0 inteira), o FIO
// vivo (bus.sock: janelas, mesa, mídia, jogo, áudio) e o áudio da
// mesa (o default do PipeWire).
// E150 — A AUDITORIA SISTÊMICA (a ordem do dono, base 1.0-98): o dump
// conectado a TODOS os subsistemas ativos — consumo GLOBAL de RAM/zram
// (free/swapon/zramctl), top RSS do sistema E da interface, timers e
// unidades failed do systemd, contagem total de pacotes, sockets do
// $XDG_RUNTIME_DIR, o CASAMENTO da persistência do monitor (displays.
// conf × wlr-randr com veredito), a ENTRADA de áudio (default source),
// os três tempos da vigília, o wake-guard e o veredito de XML do
// menu/rc no papel CURTO (não só no --full).
// 1.0-93 — A TELEMETRIA PROFUNDA DE VOLTA (a ordem do dono, rig da
// 1.0-92): hardware (CPU/memória/GPU/VRAM), o cmdline e o RSS/CPU%
// dos processos da sessão, o sysctl vivo, o scx-lavd REAL, os
// sinks/sources do PipeWire, o wlr-randr, os erros do journal do
// boot, o pacman recente, o SUDO_UID resolvido (o dump do pkexec
// colhe a sessão do DONO, não do root) e o --upload (termbin.com —
// PÚBLICO, avisado antes de subir).
// 1.0-95 — O MODO --full (E146/D: o relato do dono — o script de
// dump AD-HOC que rodava no rig concatenava *.bak-*, perfil do
// navegador e até PNGs BINÁRIOS como "linhas", 16 mil linhas de
// lixo que enterravam os logs de verdade; o modo --full é o
// CONSOLIDADO LIMPO da casa: filtro estrito (SÓ configs ativas),
// logs completos sem truncar, journal user+system, veredito de XML
// e um ÚNICO .txt + .tar.gz no fim).
// Roda no RIG e na sessão de prova — sem systemd/bus o papel NOMEIA
// as ausências, nunca mente.
// ═════════════════════════════════════════════════════════════════════════
use std::io::Write as _;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    // a lei E90 — a descoberta antes de qualquer colheita (o papel do
    // contrato 35-ajuda: 100% do mapa responde verbo seguro)
    if args.iter().any(|a| a == "-h" || a == "--help" || a == "uso") {
        println!(
            "uso: craft-dump [--full] [--upload] — o papel que se conhece (telemetria v2)\n\
             \n\
             \x20  (sem argumentos)  o retrato rápido da sessão (read-only)\n\
             \x20  --full            o consolidado limpo — configs ativas, logs\n\
             \x20                    completos, um .txt + um .tar.gz no fim\n\
             \x20  --upload          sobe o papel no termbin.com (PÚBLICO —\n\
             \x20                    avisado antes de subir)\n\
             \x20  -h | --help | uso  este papel"
        );
        return;
    }
    if args.iter().any(|a| a == "--full") {
        modo_full();
        return;
    }
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

    // ── E150 · O CONSUMO GLOBAL (free/swapon/zramctl — o mundo inteiro,
    //    não só a família): a RAM usada/cache/disponível, o swap com
    //    swapon e o zramctl VIVO (comprimindo de verdade?) ─────────────
    say("");
    say("consumo global (free -m · swapon · zramctl):");
    if let Some(free) = colhe(&["free", "-m"]) {
        if let Some((t, u, bc, a, st, su)) = craft_dump_rs::parse_free_m(&free) {
            say(&format!(
                "  RAM: {u} MiB usados · {bc} MiB cache · {a} MiB disponíveis (de {t} MiB)"
            ));
            if st > 0 {
                say(&format!(
                    "  swap: {su} MiB em uso de {st} MiB (o zram da casa, swappiness 180)"
                ));
            } else {
                say("  swap: NENHUM ativo (sem zram montado — nomeado, não inventado)");
            }
        } else {
            say("  free: formato inesperado (o papel cru segue calado — não mente)");
        }
    } else {
        say("  free indisponível (rig real julga)");
    }
    if let Some(sw) = colhe(&["swapon", "--show", "--bytes"]) {
        for linha in sw.lines() {
            say(&format!("  swapon: {linha}"));
        }
    }
    if let Some(zc) = colhe(&["zramctl"]) {
        match craft_dump_rs::zramctl_campos(&zc) {
            Some((disk, data, total)) => say(&format!(
                "  zramctl: disksize {disk} · dados {data} · comprimido em {total} (o zram trabalhando)"
            )),
            None => say("  zramctl: sem zram vivo (a colheita acima do sysfs nomeia o réu)"),
        }
    }

    // ── SERVIÇOS: o systemctl colhido cru ──────────────────────────────
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
            // 1.0-94 — o interplay nomeado: unit presente + kernel sem
            // sched_ext = o lavd DORME por desenho (não é defeito)
            if let Some(linha) = craft_dump_rs::linha_scx(false, true) {
                say(linha);
            }
        }
    }

    // ── E150 · TIMERS E FALHAS DO SYSTEMD (a ordem do dono: serviços E
    //    timers RODANDO + as unidades failed nomeadas) ─────────────────
    if !saida.is_empty() {
        say("");
        say("timers da casa (list-timers · os próximos 8):");
        if let Some(timers) = colhe(&["systemctl", "list-timers", "--all", "--no-pager"]) {
            let mut n = 0;
            for linha in timers.lines() {
                if linha.starts_with(' ') || linha.is_empty() {
                    continue; // as rodapés alinhados não são timers
                }
                say(&format!("  {linha}"));
                n += 1;
                if n >= 8 {
                    break;
                }
            }
        } else {
            say("  list-timers indisponível (nomeado, não inventado)");
        }
        if let Some(failed) = colhe(&["systemctl", "--failed", "--no-legend", "--plain"]) {
            let n_fail = failed.lines().filter(|l| !l.trim().is_empty()).count();
            if n_fail == 0 {
                say("unidades failed: NENHUMA (o boot limpo de sempre)");
            } else {
                say(&format!("unidades failed: {n_fail} (os réus: \u{2014} o journal abaixo conta o porquê)"));
                for linha in failed.lines() {
                    say(&format!("  {linha}"));
                }
            }
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

    // ── E150 · O TOP RSS (a ordem do dono: interface E sistema — o
    //    consumo que importa, ranqueado; 2 coletas: TODOS os processos
    //    e os do UID da SESSÃO) ─────────────────────────────────────
    say("");
    {
        let mut sistema: Vec<(u32, String, u64)> = Vec::new();
        let mut interface: Vec<(u32, String, u64)> = Vec::new();
        if let Ok(rd) = std::fs::read_dir("/proc") {
            for entry in rd.flatten() {
                let Ok(pid) = entry.file_name().to_string_lossy().parse::<u32>() else {
                    continue;
                };
                let Ok(comm) = std::fs::read_to_string(format!("/proc/{pid}/comm")) else {
                    continue;
                };
                let comm = comm.trim().to_string();
                if comm.is_empty() {
                    continue;
                }
                let status =
                    std::fs::read_to_string(format!("/proc/{pid}/status")).unwrap_or_default();
                let rss = craft_dump_rs::rss_kib_do_status(&status);
                if rss == 0 {
                    continue; // zumbi/kernel thread não paga RAM de usuário
                }
                sistema.push((pid, comm.clone(), rss));
                // a INTERFACE: os processos do DONO da sessão (o uid de
                // cima — o mesmo juízo da família: sessão de quem pediu)
                let uid_dele = status
                    .lines()
                    .find(|l| l.starts_with("Uid:"))
                    .and_then(|l| l.split_whitespace().nth(1))
                    .and_then(|v| v.parse::<u32>().ok())
                    .unwrap_or(u32::MAX);
                if uid_dele == uid {
                    interface.push((pid, comm, rss));
                }
            }
        }
        say("top RSS · o SISTEMA inteiro (os 10 maiores):");
        for (pid, comm, rss) in craft_dump_rs::rank_rss(sistema, 10) {
            say(&format!("  · pid {pid:>6} ({comm}): {:.0} MiB", rss as f64 / 1024.0));
        }
        say("top RSS · a INTERFACE (os processos do dono, os 10 maiores):");
        for (pid, comm, rss) in craft_dump_rs::rank_rss(interface, 10) {
            say(&format!("  · pid {pid:>6} ({comm}): {:.0} MiB", rss as f64 / 1024.0));
        }
    }

    // ── O FIO VIVO: o bus.sock (a fonte da verdade da sessão) ───────────
    // 1.0-94 — O VEREDITO DE 3 ESTADOS (o "MORTO" da 1.0-93 escondia
    // DOIS réus: o fóssil sem dono e o daemon engasgado)
    say("");
    let caminho = elite_core::bus_sock_path(uid);
    let arquivo_existe = caminho.exists();
    match craft_dump_rs::colhe_do_bus(&caminho) {
        craft_dump_rs::ColheitaBus::Vivo(colheita) => {
            say(&format!("bus.sock VIVO ({}):", caminho.display()));
            for linha in craft_dump_rs::linhas_bus(&colheita) {
                say(&format!("  {linha}"));
            }
        }
        craft_dump_rs::ColheitaBus::Calado => {
            say(&format!(
                "bus.sock CALADO em {} — conectou e o daemon NÃO respondeu \
                 (o núcleo do elite-daemon está engasgado: o SIGTERM dele \
                 renasce a sessão limpa; as caudas abaixo contam)",
                caminho.display()
            ));
        }
        craft_dump_rs::ColheitaBus::Recusado => {
            if arquivo_existe {
                say(&format!(
                    "bus.sock MORTO em {} — o arquivo existe mas NINGUÉM \
                     atende (fóssil de sessão morta ou o dono caiu — o \
                     relogin renasce o fio)",
                    caminho.display()
                ));
            } else {
                say(&format!(
                    "bus.sock AUSENTE em {} — o daemon nunca ligou o fio \
                     nesta sessão (nomeado, não inventado)",
                    caminho.display()
                ));
            }
        }
    }

    // ── ÁUDIO DA MESA: o default + os sinks/sources do PipeWire ─────────
    // 1.0-94 — O PACTL VESTE O RUNTIME DO DONO (o rig da 1.0-93: o dump
    // do pkexec vinha RAIZ e o pactl ficava SEM RESPOSTA — o socket do
    // PipeWire mora em /run/user/<uid>; o XDG_RUNTIME_DIR da corrida
    // aponta pro dono certo e o áudio aparece no papel de raiz também)
    say("");
    let mut pactl_env = std::process::Command::new("pactl");
    pactl_env.env("XDG_RUNTIME_DIR", format!("/run/user/{uid}"));
    match pactl_env
        .args(["info"])
        .stdin(std::process::Stdio::null())
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
        .and_then(|s| craft_dump_rs::pactl_default_sink(&s))
    {
        Some(sink) => say(&format!("áudio: default do PipeWire = {sink}")),
        None => say("áudio: pactl indisponível/sem resposta (rig real julga)"),
    }
    if let Some(sinks) = colhe_com_runtime(&["pactl", "list", "short", "sinks"], uid) {
        for linha in sinks.lines().take(8) {
            say(&format!("  sink: {linha}"));
        }
    }
    if let Some(sources) = colhe_com_runtime(&["pactl", "list", "short", "sources"], uid) {
        for linha in sources.lines().take(8) {
            say(&format!("  source: {linha}"));
        }
    }
    // E150 — a ENTRADA padrão também importa (o microfone da perícia:
    // o default source do pactl info, o mesmo parser da saída)
    let mut pactl_env2 = std::process::Command::new("pactl");
    pactl_env2.env("XDG_RUNTIME_DIR", format!("/run/user/{uid}"));
    match pactl_env2
        .args(["info"])
        .stdin(std::process::Stdio::null())
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
        .and_then(|s| craft_dump_rs::pactl_default_source(&s))
    {
        Some(source) => say(&format!("áudio: default de ENTRADA = {source}")),
        None => say("áudio: default de entrada indisponível (o pactl acima fala o resto)"),
    }

    // ── A VIGÍLIA: o conf vivo (o daemon arma com ESTES valores) ─────────
    // 1.0-94 — O CONF É DO DONO (o rig da 1.0-93: o dump do pkexec lia
    // o idle.conf de /root e dizia "ausente"; o papel agora resolve o
    // home de QUEM pediu). E150 — os TRÊS tempos no papel (LOCK/OFF/
    // SUSPEND — a fábrica 5/10/20 e o gesto separado; o 0 é NUNCA)
    let passwd = std::fs::read_to_string("/etc/passwd").unwrap_or_default();
    let home_dono = craft_dump_rs::home_do_uid(uid, &passwd)
        .or_else(|| std::env::var("HOME").ok())
        .unwrap_or_else(|| "/root".into());
    let conf_idle = std::path::PathBuf::from(&home_dono)
        .join(".config/elite/idle.conf");
    say("");
    say("vigília (idle.conf do dono · os três tempos):");
    match std::fs::read_to_string(&conf_idle) {
        Ok(papel_conf) => {
            for linha in craft_dump_rs::idle_conf_tres(&papel_conf) {
                say(&linha);
            }
            say(&format!("  conf: {conf_idle:?} (o daemon relê a cada armação)"));
        }
        Err(_) => say("  idle.conf ausente (a fábrica do daemon: trava 5 · apaga 10 · suspende 20)"),
    }

    // ── 1.0-94 · OS MONITORES (o wlr-randr cru) + E150 · O CASAMENTO DA
    //    PERSISTÊNCIA (displays.conf × wlr-randr — o juízo do '60 Hz
    //    sempre volta': CONFERE / DIVERGE / AUSENTE por tela) ─────────
    let randr = colhe(&["wlr-randr"]).unwrap_or_default();
    if !randr.is_empty() {
        say("");
        say("monitores (wlr-randr · os primeiros 30):");
        for linha in randr.lines().take(30) {
            say(&format!("  {linha}"));
        }
    }
    say("");
    say("persistência do monitor (displays.conf × wlr-randr):");
    let conf_display = std::path::PathBuf::from(&home_dono)
        .join(".config/elite/displays.conf");
    let papel_display = std::fs::read_to_string(&conf_display).unwrap_or_default();
    if !papel_display.is_empty() {
        for linha in papel_display.lines().filter(|l| !l.starts_with('#') && !l.trim().is_empty()) {
            say(&format!("  salvo: {linha}"));
        }
        for linha in craft_dump_rs::veredito_display(&papel_display, &randr) {
            say(&linha);
        }
        // o stamp do apply (a máquina de estados do craft-display)
        let stamp = std::path::PathBuf::from(format!("/run/user/{uid}/elite/display-applied"));
        match std::fs::read_to_string(&stamp) {
            Ok(s) => say(&format!("  stamp: {} ({:?})", s.trim(), stamp)),
            Err(_) => say("  stamp: ausente (o apply desta sessão ainda não escreveu — nomeado)"),
        }
    } else {
        for linha in craft_dump_rs::veredito_display("", &randr) {
            say(&linha);
        }
    }

    // ── E150 · O WAKE-GUARD (a política de despertar — a vista do
    //    próprio bin da casa; teclado acorda, o resto dorme) ─────────
    say("");
    say("wake-guard (a política de quem acorda a máquina):");
    if let Some(wg) = colhe(&["/usr/local/bin/craft-wake-guard", "status"]) {
        for linha in wg.lines().take(12) {
            say(&format!("  {linha}"));
        }
    } else {
        say("  craft-wake-guard status indisponível (rig de prova sem o bin — nomeado)");
    }

    // ── E150 · OS SOCKETS DO $XDG_RUNTIME_DIR (o chão da sessão: wayland,
    //    pipewire, o elite/ da casa — o fóssil que mente é réu nomeado) ─
    say("");
    say(&format!("runtime da sessão ($XDG_RUNTIME_DIR = /run/user/{uid}):"));
    {
        let dir = std::path::PathBuf::from(format!("/run/user/{uid}"));
        let mut entradas: Vec<(String, bool, bool)> = Vec::new();
        if let Ok(rd) = std::fs::read_dir(&dir) {
            for e in rd.flatten() {
                let nome = e.file_name().to_string_lossy().to_string();
                let (sock, is_dir) = match e.metadata() {
                    Ok(m) => {
                        use std::os::unix::fs::FileTypeExt;
                        (m.file_type().is_socket(), m.is_dir())
                    }
                    Err(_) => (false, false),
                };
                entradas.push((nome, sock, is_dir));
            }
        }
        if entradas.is_empty() {
            say("  ausente/vazio (sessão de prova sem systemd — nomeado, não inventado)");
        } else {
            entradas.sort();
            for linha in craft_dump_rs::linhas_runtime_dir(&entradas) {
                say(&linha);
            }
        }
    }

    // ── 1.0-93 · OS ERROS DO BOOT (journalctl -p err -b) ─────────────────
    // 1.0-94 — A PERÍCIA CONHECIDA NA CARA (o rig da 1.0-93 lia as linhas
    // benignas do bluetoothd/wpa/tdx como alarme mudo; as anotações
    // separam o benigno do réu de verdade)
    if let Some(journal) = colhe(&["journalctl", "-p", "err", "-b", "--no-pager", "-n", "30"]) {
        say("");
        say("erros do boot (journalctl -p err -b, os últimos 30 · os → são a perícia):");
        for linha in journal.lines() {
            say(&format!("  {linha}"));
            if let Some(nota) = craft_dump_rs::anota_conhecido(linha) {
                say(&format!("  {nota}"));
            }
        }
    }

    // ── 1.0-94 · AS CAUDAS DA SESSÃO (os papéis que o dono precisa ler ───
    //    quando algo quebra — o dump curto da 1.0-93 escondia os gritos
    //    do respawn da barra e o porquê da limpeza; caudas de 20 linhas,
    //    teto honesto, a objetividade segue)
    say("");
    say("as caudas da sessão (~/.cache/elite · os últimos 20 de cada):");
    let cache_dono = std::path::PathBuf::from(&home_dono).join(".cache/elite");
    for nome in ["bars.log", "bar.log", "dock.log", "clean.log", "update.log"] {
        let caminho_log = cache_dono.join(nome);
        let Ok(txt) = std::fs::read_to_string(&caminho_log) else {
            continue;
        };
        let linhas: Vec<&str> = txt.lines().collect();
        let cauda: Vec<&str> = if linhas.len() > 20 {
            linhas[linhas.len() - 20..].to_vec()
        } else {
            linhas
        };
        say(&format!("  ── {nome} (a cauda):"));
        for l in cauda {
            say(&format!("  {l}"));
        }
    }

    // ── 1.0-93 · O PACMAN RECENTE (as doses que chegaram) + E150 · O
    //    TOTAL DE PACOTES (o retrato do sistema: instaladas, explícitas,
    //    locais — a contagem que o dono lê) ─────────────────────────
    say("");
    {
        let q = colhe(&["pacman", "-Q"]).unwrap_or_default();
        let qe = colhe(&["pacman", "-Qe"]).unwrap_or_default();
        let qm = colhe(&["pacman", "-Qm"]).unwrap_or_default();
        if q.is_empty() {
            say("pacotes: pacman indisponível (rig de prova — nomeado)");
        } else {
            say(&format!(
                "pacotes: {} instalados · {} explícitos · {} locais/AUR",
                craft_dump_rs::conta_linhas(&q),
                craft_dump_rs::conta_linhas(&qe),
                craft_dump_rs::conta_linhas(&qm)
            ));
        }
    }
    if let Ok(log_pacman) = std::fs::read_to_string("/var/log/pacman.log") {
        say("pacman (as linhas recentes):");
        for linha in log_pacman.lines().rev().take(15).collect::<Vec<_>>() {
            say(&format!("  {linha}"));
        }
    }

    // ── E150 · O VEREDITO DE XML no papel CURTO (o menu.xml/rc.xml do
    //    dono: xmllint com o fallback python — o mesmo juiz do --full;
    //    o labwc REJEITA o menu inteiro quando o XML quebra) ─────────
    say("");
    say("XML da sessão (rc.xml · menu.xml):");
    for f in ["rc.xml", "menu.xml"] {
        let caminho = std::path::PathBuf::from(&home_dono)
            .join(".config/labwc")
            .join(f);
        if !caminho.exists() {
            say(&format!("  {f}: AUSENTE (o skel entrega na próxima dose)"));
            continue;
        }
        let cstr = caminho.to_string_lossy().to_string();
        if let Some(rc) = colhe_status(&["xmllint", "--noout", &cstr]) {
            if rc == 0 {
                say(&format!("  {f}: VÁLIDO (xmllint exit 0)"));
            } else {
                say(&format!("  {f}: INVÁLIDO — o heal E146 renova do mestre na próxima dose"));
            }
        } else if let Some(rc) = colhe_status(&[
            "python3", "-c", "import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])", &cstr,
        ]) {
            if rc == 0 {
                say(&format!("  {f}: VÁLIDO (python ET — o fallback julga)"));
            } else {
                say(&format!("  {f}: INVÁLIDO — o heal E146 renova do mestre na próxima dose"));
            }
        } else {
            say(&format!("  {f}: SEM JUIZ no sistema (nem xmllint nem python3) — não auditado"));
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

/// 1.0-94 — a colheita COM O RUNTIME DO DONO (o pactl como raiz sem o
/// XDG_RUNTIME_DIR não vê o PipeWire de ninguém — o socket mora em
/// /run/user/<uid> do dono da sessão).
fn colhe_com_runtime(argv: &[&str], uid: u32) -> Option<String> {
    let out = std::process::Command::new(argv[0])
        .args(&argv[1..])
        .env("XDG_RUNTIME_DIR", format!("/run/user/{uid}"))
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

// ═════════════════════════════════════════════════════════════════════════
// 1.0-95 · O MODO --full (E146/D) — O CONSOLIDADO LIMPO
// ═════════════════════════════════════════════════════════════════════════
// A FERIDA (o relato do dono): o dump ad-hoc do rig concatenava 28 arquivos
// .bak-*, o perfil do Brave INTEIRO e até wallpaper.png/avatar.png como
// "linhas" — 16.241 linhas de lixo que enterravam os logs reais antes da
// metade. A LEI daqui (item por item do pedido):
//   1. IGNORA ESTRITAMENTE *.bak*, *.old, dirs de navegador e binários;
//   2. COLETA SÓ as configs ativas (labwc + elite);
//   3. INTEIRO e sem truncar: git log -n 15 do repo (quando existe no
//      disco), processos da sessão (com os <defunct> NOMADOS — a coveira
//      E146/C é a cura, o papel é a prova), ~/.cache/elite/*.log COMPLETO,
//      journalctl system + user err..warning, veredito XML;
//   4. UM arquivo consolidado + UM .tar.gz (o tar da casa, sem dep).
/// A família que o papel do --full fotografa (processos da sessão).
const FAMILIA_FULL: &[&str] = &[
    "labwc",
    "elite-daemon",
    "craft-bar-rs",
    "craft-dock-rs",
    "swaync",
    "swaync-client",
    "waybar",
    "swayidle",
    "swaybg",
    "nwg-drawer",
    "swayosd",
    "swayosd-server",
    "udiskie",
    "pipewire",
    "wireplumber",
    "pipewire-pulse",
    "lxqt-policykit-agent",
    "craft-display",
    "craft-shot",
    "brave",
    "fuzzel",
];

/// As configs ativas que viajam no papel (whitelist — nada além entra).
const CONFIGS_ATIVAS: &[&str] = &[
    "labwc/rc.xml",
    "labwc/menu.xml",
    "labwc/autostart",
    "labwc/environment",
    "labwc/themerc-override",
    "elite/idle.conf",
    "elite/game.conf",
    "elite/dock-pins",
    "elite/dock.css",
    "elite/bar.css",
    "elite/displays.conf",
];

fn modo_full() {
    let (uid, dono) = uid_e_dono();
    let home_dono = craft_dump_rs::home_do_uid(uid, &std::fs::read_to_string("/etc/passwd").unwrap_or_default())
        .or_else(|| std::env::var("HOME").ok())
        .unwrap_or_else(|| "/root".into());
    let mut p = String::new();
    let mut say = |l: &str| {
        p.push_str(l);
        p.push('\n');
    };

    say("═ ARCHCRAFT ELITE · craft-dump --full · o consolidado limpo (1.0-95/E146) ═");
    say(&format!("gerado: {}", agora_iso()));
    say(&format!("uid corrente: {} · sessão do dono: uid {uid} ({})", uid_corrente(), dono.as_deref().unwrap_or("?")));

    // ── 1. IDENTIDADE & VERSÃO ──────────────────────────────────────────
    say("");
    say("═ 1. IDENTIDADE & VERSÃO ═");
    say(&format!("kernel: {}", std::fs::read_to_string("/proc/version").unwrap_or_default().trim()));
    for pkg in ["elite-system", "labwc", "fuzzel", "swaync", "pipewire", "wireplumber", "bluez", "networkmanager"] {
        if let Some(v) = colhe(&["pacman", "-Q", pkg]) {
            say(&format!("pacote: {}", v.trim()));
        }
    }
    say("uptime:");
    say(&format!("  {}", std::fs::read_to_string("/proc/uptime").unwrap_or_default().trim()));

    // o git do repo (rastreabilidade — quando o clone mora no disco)
    say("git do repo (git log -n 15 --oneline):");
    let mut achou_git = false;
    for cand in [
        format!("{home_dono}/archcraft-elite"),
        format!("{home_dono}/.local/src/archcraft-elite"),
        format!("{home_dono}/src/archcraft-elite"),
        "/root/archcraft-elite".to_string(),
        "/srv/archcraft-elite".to_string(),
    ] {
        if !std::path::Path::new(&cand).join(".git").exists() {
            continue;
        }
        if let Some(log) = colhe(&["git", "-C", &cand, "log", "-n", "15", "--oneline"]) {
            say(&format!("  repo: {cand}"));
            for l in log.lines() {
                say(&format!("  {l}"));
            }
            achou_git = true;
            break;
        }
    }
    if !achou_git {
        say("  clone do repo AUSENTE no disco (a versão acima é do pacman — a fronteira honesta)");
    }

    // ── 2. PROCESSOS DA SESSÃO (com os zumbis nomados) ──────────────────
    say("");
    say("═ 2. PROCESSOS DA SESSÃO (ps filtrado · <defunct> é réu nomeado) ═");
    let processos = processes_full();
    for (pid, ppid, st, comm, cmdline) in &processos {
        say(&format!(
            "  pid {pid:>6} · ppid {ppid:>6} · {comm}{}",
            if cmdline.is_empty() { String::new() } else { format!(" · {cmdline}") },
        ));
        if *st == 'Z' {
            say("    ↑ ZUMBI (a coveira E146/C da barra colhe os filhos: o binário novo não gera mais)");
        }
    }

    // ── 3. RUNTIME + 4. SOCKETS ─────────────────────────────────────────
    say("");
    say("═ 3. RUNTIME DA SESSÃO (/run/user/<uid>/elite) ═");
    let run = format!("/run/user/{uid}/elite");
    if let Ok(rd) = std::fs::read_dir(&run) {
        for e in rd.flatten() {
            let nome = e.file_name().to_string_lossy().to_string();
            match e.metadata() {
                Ok(m) => say(&format!("  {nome} · {} bytes", m.len())),
                Err(_) => say(&format!("  {nome} · (metadata indisponível)")),
            }
        }
    } else {
        say("  ausente (o daemon nunca abriu o tmpfs da sessão)");
    }
    say("");
    say("═ 4. SOCKETS ═");
    if let Some(ss) = colhe(&["ss", "-xlnp"]) {
        for l in ss.lines().filter(|l| l.contains("elite") || l.contains("wayland") || l.contains("bus.sock")) {
            say(&format!("  {l}"));
        }
    } else {
        say("  ss indisponível (a casa não inventa socket)");
    }

    // ── 5. CONFIGS ATIVAS (whitelist — .bak/old/binário JAMAIS) ────────
    say("");
    say("═ 5. CONFIGS ATIVAS (whitelist estrita: sem *.bak*, sem navegador) ═");
    let conf_base = std::path::Path::new(&home_dono).join(".config");
    for rel in CONFIGS_ATIVAS {
        let caminho = conf_base.join(rel);
        say(&format!(">>> {} <<<", caminho.display()));
        // binário não é papel: NUL = não-texto (a lei do filtro E146)
        if let Ok(bytes) = std::fs::read(&caminho) {
            if bytes.contains(&0u8) {
                say("  [ARQUIVO BINÁRIO — não viaja no papel (a lei do filtro E146)]");
                continue;
            }
            let txt = String::from_utf8_lossy(&bytes);
            for l in txt.lines() {
                say(&format!("  {l}"));
            }
        } else {
            say("  [AUSENTE]");
        }
    }

    // ── 6. LOGS COMPLETOS (~/.cache/elite — inteiro, sem truncar) ───────
    say("");
    say("═ 6. LOGS COMPLETOS (~/.cache/elite — sem truncamento) ═");
    let cache = std::path::Path::new(&home_dono).join(".cache/elite");
    if let Ok(rd) = std::fs::read_dir(&cache) {
        let mut logs: Vec<_> = rd.flatten().filter(|e| {
            let n = e.file_name().to_string_lossy().to_string();
            n.ends_with(".log") && !n.contains(".bak")
        }).collect();
        logs.sort_by_key(|e| e.file_name().to_string_lossy().to_string());
        for e in logs {
            let nome = e.file_name().to_string_lossy().to_string();
            let Ok(txt) = std::fs::read_to_string(e.path()) else {
                continue;
            };
            let n = txt.lines().count();
            say(&format!(">>> {cache:?}/{nome} (linhas: {n}) <<<"));
            for l in txt.lines() {
                say(&format!("{l}"));
            }
            say("");
        }
    } else {
        say("  ~/.cache/elite ausente");
    }

    // ── 7. JOURNAL (system + user) ──────────────────────────────────────
    say("═ 7. JOURNAL DO BOOT (err..warning · system + sessão do dono) ═");
    say("── journalctl -b -p err..warning --no-pager (system) ──");
    if let Some(j) = colhe(&["journalctl", "-b", "-p", "err..warning", "--no-pager"]) {
        for l in j.lines() {
            say(l);
        }
    } else {
        say("  [journalctl indisponível]");
    }
    say(&format!("── journalctl _UID={uid} -b -p err..warning --no-pager (sessão do dono) ──"));
    if let Some(j) = colhe(&["journalctl", &format!("_UID={uid}"), "-b", "-p", "err..warning", "--no-pager"]) {
        for l in j.lines() {
            say(l);
        }
    } else {
        say("  [journalctl indisponível]");
    }

    // ── 8. VEREDITO DE XML (xmllint ou python — a prova do heal) ────────
    say("");
    say("═ 8. VEREDITO DE XML (rc.xml · menu.xml) ═");
    for f in ["rc.xml", "menu.xml"] {
        let caminho = conf_base.join("labwc").join(f);
        say(&format!("── {caminho:?} ──"));
        if !caminho.exists() {
            say("  [AUSENTE]");
            continue;
        }
        let cstr = caminho.to_string_lossy().to_string();
        if let Some(rc) = colhe_status(&["xmllint", "--noout", &cstr]) {
            if rc == 0 {
                say("  xmllint: VÁLIDO (exit 0, sem erros)");
            } else {
                say("  xmllint: INVÁLIDO — o heal E146 renova do mestre na próxima dose");
            }
        } else if let Some(rc) = colhe_status(&[
            "python3", "-c", "import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])", &cstr,
        ]) {
            if rc == 0 {
                say("  python ET: VÁLIDO (sem xmllint no sistema — o fallback julga)");
            } else {
                say("  python ET: INVÁLIDO — o heal E146 renova do mestre na próxima dose");
            }
        } else {
            say("  [SEM JUIZ no sistema (nem xmllint nem python3) — não auditado]");
        }
    }

    // ── 9. DISPLAY / ÁUDIO / BLUETOOTH / REDE ───────────────────────────
    say("");
    say("═ 9. DISPLAY, ÁUDIO, BLUETOOTH & REDE ═");
    if let Some(r) = colhe(&["wlr-randr"]) {
        for l in r.lines() {
            say(l);
        }
    } else {
        say("  [wlr-randr indisponível]");
    }
    say("");
    if let Some(a) = colhe_com_runtime(&["pactl", "info"], uid) {
        for l in a.lines() {
            say(l);
        }
    }
    if let Some(s) = colhe_com_runtime(&["pactl", "list", "short", "sinks"], uid) {
        for l in s.lines() {
            say(l);
        }
    }
    say("");
    if let Some(b) = colhe(&["bluetoothctl", "show"]) {
        for l in b.lines() {
            say(l);
        }
    }
    say("");
    if let Some(n) = colhe(&["nmcli", "-t", "-f", "STATE,CONNECTIVITY", "general", "status"]) {
        say(&format!("nmcli: {n}"));
    }
    if let Some(n) = colhe(&["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"]) {
        for l in n.lines() {
            say(l);
        }
    }

    say("═ fim do consolidado — a sessão é o juiz, o papel é a testemunha ═");

    // ── O ARQUIVO ÚNICO + O TAR.GZ ──────────────────────────────────────
    let stamp = stamp_agora();
    let txt = format!("/tmp/elite-dump-full-{stamp}.txt");
    let tgz = format!("/tmp/elite-dump-full-{stamp}.tar.gz");
    if std::fs::write(&txt, &p).is_err() {
        println!("dump: FALHOU ao gravar {txt} (o consolidado completo segue no stdout)");
        print!("{p}");
        std::process::exit(1);
    }
    // o empacote é o tar da casa (gzip nativo do runner — zero dep nova)
    let ok = std::process::Command::new("tar")
        .args(["-czf", &tgz, "-C", "/tmp", &format!("elite-dump-full-{stamp}.txt")])
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    // o dono lê o próprio papel (o pkexec roda como root — o chown devolve)
    if let Some(d) = &dono {
        let _ = colhe(&["chown", &format!("{d}:{d}"), &txt]);
        if ok {
            let _ = colhe(&["chown", &format!("{d}:{d}"), &tgz]);
        }
    }
    println!("dump --full: {txt}");
    if ok {
        println!("dump --full: {tgz} (o consolidado ÚNICO — sem .bak, sem navegador)");
    } else {
        println!("dump --full: o tar falhou — o .txt acima é o consolidado completo");
    }
}

/// A hora local em ISO-ish (sem dep: os dígitos de /etc/localtime via `date`).
fn agora_iso() -> String {
    colhe(&["date", "+%Y-%m-%dT%H:%M:%S%:z"]).unwrap_or_else(|| "sem date no PATH".into()).trim().to_string()
}

fn stamp_agora() -> String {
    colhe(&["date", "+%Y%m%d-%H%M%S"])
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "sem-data".into())
}

fn uid_corrente() -> u32 {
    std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("Uid:"))
                .and_then(|l| l.split_whitespace().nth(1).and_then(|v| v.parse().ok()))
        })
        .unwrap_or(0)
}

/// O status de UM comando (None se nem nasceu; Some(rc) quando rodou).
fn colhe_status(argv: &[&str]) -> Option<i32> {
    let out = std::process::Command::new(argv[0])
        .args(&argv[1..])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .output()
        .ok()?;
    Some(out.status.code().unwrap_or(-1))
}

/// A tabela de processos da sessão (pid, ppid, state, comm, cmdline) —
/// a família + os zumbis pendurados nela (o ps aux filtrado da casa).
fn processes_full() -> Vec<(u32, u32, char, String, String)> {
    let mut v = Vec::new();
    let Ok(rd) = std::fs::read_dir("/proc") else {
        return v;
    };
    for e in rd.flatten() {
        let Ok(pid) = e.file_name().to_string_lossy().parse::<u32>() else {
            continue;
        };
        let Ok(stat) = std::fs::read_to_string(format!("/proc/{pid}/stat")) else {
            continue;
        };
        // comm está entre parênteses (o parser honesto: o ÚLTIMO par)
        let Some(abre) = stat.rfind('(') else { continue };
        let Some(fecha) = stat[abre..].find(')') else { continue };
        let comm = stat[abre + 1..abre + fecha].to_string();
        let resto = &stat[abre + fecha + 2..];
        let mut campos = resto.split_whitespace();
        let state = campos.next().unwrap_or("?").chars().next().unwrap_or('?');
        let ppid = campos.next().and_then(|s| s.parse().ok()).unwrap_or(0);
        let familia = FAMILIA_FULL.contains(&comm.as_str());
        let zumbi = state == 'Z';
        if familia || zumbi {
            let cmdline = std::fs::read_to_string(format!("/proc/{pid}/cmdline"))
                .map(|c| c.replace('\0', " ").trim().to_string())
                .unwrap_or_default();
            let comm_exib = if zumbi { format!("[{comm}] <defunct>") } else { comm };
            v.push((pid, ppid, state, comm_exib, cmdline));
        }
    }
    v.sort_by_key(|(pid, _, _, _, _)| *pid);
    v
}
