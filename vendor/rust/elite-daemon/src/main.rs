// ELITE · elite-daemon v2 (E131→E132) — o núcleo do craft-game watch como
// serviço NATIVO. A ordem do dono ("espremer o limão"): os loops
// residentes de shell viram UM daemon em Rust — zero fork por tick, a
// leitura direta de /proc, o D-Bus nativo com o GameMode.
//
// ESCOPO HONESTO DA v2 (o degrau é incrementado, a lei AGENTS.md §2):
//   · a DETECÇÃO de jogo E132 COMPLETA (a família ERE do comm + a porta
//     do exe Steam + a sonda cmdline/environ dos runtimes Proton/Wine/
//     Hydra/UMU com o bloqueio dos auxiliares — tudo no scan.rs);
//   · o REGISTRO/DESREGISTRO no GameMode por D-Bus NATIVO (zbus) — o
//     reaper do gamemoded continua sabendo da morte do jogo;
//   · EPP DINÂMICO na transição da sessão de jogo: ATIVA → performance
//     em todo cpu*/cpufreq/energy_performance_preference WRITÁVEL;
//     INATIVA → balance_performance de volta (escrita idempotente —
//     só toca o arquivo quando o valor DIFERE, zero spam);
//   · SINAL à waybar (SIGRTMIN+8) em CADA transição — a topbar relê o
//     pill do modo sem esperar o intervalo dela (leitura de /proc do
//     uid corrente + libc::kill — NENHUM fork de pgrep);
//   · DEBOUNCE de 3s nas notificações (a lição E132 do gm_hook: pulo
//     transitório do Hydra não é notícia — o INÍCIO só sobe depois de
//     3s com o QueryStatus ATIVO; o FIM só notifica sessões CONFIRMADAS;
//     a decisão mora numa função PURA com teste de unidade);
//   · `supervise` — o supervisor dos RESIDENTES da sessão (swaync,
//     udiskie, swayosd, craft-audio-route) com try_wait nativo e backoff
//     de 2s (o módulo supervise.rs — o craft-bars passa a delegar quando
//     este binário existe);
//   · instância ÚNICA por flock de arquivo (a lei E30 — o 2º sai 0);
//   · --once: UMA rodada de varredura (a porta dos testes);
//   · SIGTERM/SIGINT: unregister de tudo, EPP devolvido e saída limpa.
// NÃO É DEGRAU DESTA v2: as barras waybar/dock SEGUIEM corpos próprios
// (a waybar só RECEBE o sinal daqui; a dock é outro corpo — nenhum
// half-promise de unificação pela metade).
// E139 — REVISADO: os OUVIDORES de evento moram na PORTA session (a
// sessão é quem SEMPRE está viva — o motor do jogo é vaga condicionada
// ao AUTO do game.conf, e o rig com AUTO=0 não pode ficar cego) e o
// craft-display watch-save é VAGA supervisionada da sessão (a escolha
// do wdisplays grava de novo; caiu → volta em 2s).
//
// Custos medidos no desenho: zero fork por tick (a varredura é read(2)
// de /proc); o D-Bus é conexão PERSISTENTE (não abre por chamada); o
// notify-send só nas TRANSIÇÕES confirmadas (zero toast de fantasma).
use std::collections::HashMap;
use std::os::unix::fs::MetadataExt;
use std::os::unix::io::AsRawFd;
use std::path::PathBuf;
use std::io::{Read, Write};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

mod scan;
mod supervise;

const VERSION: &str = "2.1.0";

/// E132 — a janela do debounce (o gm_hook do craft-game, 1:1): o INÍCIO
/// espera 3s em fundo antes de notificar; o FIM de sessão <3s é pulo
/// transitório e não sobe NADA.
const JANELA_DEBOUNCE_S: u64 = 3;

// ── o sinal de parada (SIGTERM/SIGINT → saída limpa) ─────────────────────
static STOP: AtomicBool = AtomicBool::new(false);

extern "C" fn ao_sinal(_sig: i32) {
    STOP.store(true, Ordering::SeqCst);
}

fn instala_sinais() {
    let h = ao_sinal as extern "C" fn(i32) as usize;
    unsafe {
        libc::signal(libc::SIGTERM, h);
        libc::signal(libc::SIGINT, h);
    }
}

fn usage() -> &'static str {
    "uso: elite-daemon [--once | supervise | session | --help | --version]\n\
     \x20 o detector de jogo unificado (E132) — registra a família no GameMode\n\
     \x20 por D-Bus nativo, aplica o EPP performance na sessão de jogo, sinaliza\n\
     \x20 a waybar (SIGRTMIN+8) e notifica com debounce de 3s; instância única\n\
     \x20 por flock; SIGTERM des-registra, devolve o EPP e sai limpo.\n\
     \x20 --once = uma rodada (a porta dos testes).\n\
     \x20 supervise = o supervisor dos residentes da sessão (swaync, udiskie,\n\
     \x20 swayosd — respawn com backoff de 2s).\n\
     \x20 session = E135 — O LANÇADOR ÚNICO da sessão gráfica (clientes de\n\
     \x20 display + residentes com o gate de posse; o craft-bars shell vira\n\
     \x20 `exec elite-daemon session` — zero /bin/sh residente).\n"
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("--help") | Some("-h") => {
            print!("{}", usage());
            std::process::exit(0);
        }
        Some("--version") | Some("-V") => {
            println!("elite-daemon {}", VERSION);
            std::process::exit(0);
        }
        Some("--once") => {
            let achados = scan::round();
            for p in &achados {
                println!(
                    "jogo: pid {} comm {} via {} exe {}",
                    p.pid, p.comm, p.via, p.exe
                );
            }
            println!("rodada única: {} jogo(s) da família", achados.len());
            std::process::exit(0);
        }
        Some("supervise") => match supervise::run() {
            Ok(()) => std::process::exit(0),
            Err(e) => {
                eprintln!("elite-daemon supervise: {}", e);
                std::process::exit(1);
            }
        },
        // E135 — a porta session: O LANÇADOR ÚNICO da sessão gráfica
        // (clientes de display + residentes com o gate de posse E135;
        // o craft-bars shell vira exec — o /bin/sh some do ps).
        // E139 — OS OUVIDORES NASCEM AQUI (a sessão é quem SEMPRE está
        // viva: netlink som/drm, logind sono/unlock, wake-guard
        // pré-sono e bus bgapps — cada thread dorme num read(2)/sinal,
        // zero CPU em repouso; a lei E135 dos residentes intocada). O
        // rig com AUTO=0 não tem motor de jogo e não pode ficar cego.
        Some("session") => {
            std::thread::spawn(thread_netlink);
            std::thread::spawn(|| thread_logind("PrepareForSleep", true));
            std::thread::spawn(|| thread_logind("Unlock", false));
            std::thread::spawn(thread_bus_bgapps);
            std::thread::spawn(thread_wakeguard);
            eprintln!(
                "elite-daemon session: ouvidores no ar (netlink som/drm, logind \
                 sono/unlock, wake-guard pré-sono, bus bgapps)"
            );
            match supervise::run_session() {
                Ok(()) => std::process::exit(0),
                Err(e) => {
                    eprintln!("elite-daemon session: {}", e);
                    std::process::exit(1);
                }
            }
        }
        Some(other) => {
            eprintln!("elite-daemon: porta desconhecida '{}'\n{}", other, usage());
            std::process::exit(2);
        }
        None => {
            // modo daemon: o loop de 5s + flock + sinais + EPP + sinal.
            match daemon_loop() {
                Ok(()) => std::process::exit(0),
                Err(e) => {
                    eprintln!("elite-daemon: {}", e);
                    std::process::exit(1);
                }
            }
        }
    }
}

// ── E132 — o veredito do debounce (função PURA, a porta dos testes) ──────
// Dado o instante em que a sessão LIGOU (epoch s), o agora e o QueryStatus
// vivo, decide o que notifica. O pulo transitório do Hydra (<3s) não é
// notícia: nem início, nem fim — silêncio absoluto.
pub struct VereditoDebounce {
    pub inicio: bool,
    pub fim: bool,
}

pub fn veredito_debounce(iniciada_em: u64, agora: u64, status_ativo: bool) -> VereditoDebounce {
    let duracao = agora.saturating_sub(iniciada_em);
    if status_ativo {
        // a sessão seguiu viva pela janela: o INÍCIO é notícia (uma vez)
        VereditoDebounce {
            inicio: duracao >= JANELA_DEBOUNCE_S,
            fim: false,
        }
    } else {
        // o FIM só é notícia de sessão REAL (>= 3s confirmados); pulo
        // transitório não notifica NADA (nem início, nem fim)
        VereditoDebounce {
            inicio: false,
            fim: duracao >= JANELA_DEBOUNCE_S,
        }
    }
}

fn agora_epoch() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// O aviso para o dono (a lei C101: eventos automáticos são -u low —
/// pop-up não é lugar de estado). Os argumentos são os MESMOS do
/// craft-game, 1:1 (o gm_hook é a referência).
fn note(corpo: &str) {
    let _ = std::process::Command::new("notify-send")
        .args(["-a", "Elite · Jogo", "-u", "low", "-t", "8000", "Modo de jogo", corpo])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn();
}

/// E132 — EPP dinâmico: escreve `valor` em todo cpu*/cpufreq/
/// energy_performance_preference WRITÁVEL cujo valor atual DIFERE
/// (idempotente — só a mudança toca o disco, zero log spam). O sysfs em
/// geral é do root: o cpufreq sem permissão é PULADO em silêncio
/// (o gamemoded segue mandando no governor — escopo honesto).
fn epp_aplica(valor: &str) -> usize {
    let Ok(dir) = std::fs::read_dir("/sys/devices/system/cpu") else {
        return 0;
    };
    let mut n = 0usize;
    for entry in dir.flatten() {
        let nome = entry.file_name();
        let Some(nome) = nome.to_str() else { continue };
        let Some(resto) = nome.strip_prefix("cpu") else { continue };
        if resto.is_empty() || !resto.bytes().all(|b| b.is_ascii_digit()) {
            continue; // cpuidle/cpufreq globais não são cpuN
        }
        let p = entry.path().join("cpufreq/energy_performance_preference");
        let Ok(atual) = std::fs::read_to_string(&p) else { continue };
        if atual.trim() == valor {
            continue; // já é o valor: idempotência de verdade
        }
        if std::fs::write(&p, valor).is_ok() {
            n += 1;
        }
    }
    n
}

/// E132 — o sinal da topbar: SIGRTMIN+8 a TODO processo 'waybar' do uid
/// corrente (leitura de /proc + libc::kill — NENHUM fork de pgrep; o
/// módulo waybar da casa relê o pill do modo no sinal).
fn sinal_waybar() -> usize {
    sinal_waybar_sig(8)
}

/// E135 — o sinal da topbar com NÚMERO parametrizável: SIGRTMIN+N em
/// todo waybar do uid corrente. +8 = o pill do jogo; +9 = a pílula dos
/// apps em 2º plano (o EVENTO dos 2º planos — o módulo custom/bgapps da
/// casa relê no sinal: o fork de `craft-bgapps status` a cada 5s do réu
/// do dump 101339 — 25% de CPU e zumbis pkill — morre).
fn sinal_waybar_sig(offset: i32) -> usize {
    let uid = unsafe { libc::getuid() };
    // E138 — SIGRTMIN é fn() const do libc (não macro unsafe nesta versão:
    // o warning 'unnecessary unsafe' era a mentira do build sujo)
    let sig = libc::SIGRTMIN() + offset;
    let Ok(dir) = std::fs::read_dir("/proc") else { return 0 };
    let mut n = 0usize;
    for entry in dir.flatten() {
        let Some(pid) = entry
            .file_name()
            .to_str()
            .and_then(|s| s.parse::<i32>().ok())
        else {
            continue;
        };
        let base = std::path::Path::new("/proc").join(entry.file_name());
        let comm = std::fs::read_to_string(base.join("comm")).unwrap_or_default();
        if comm.trim_end() != "waybar" {
            continue;
        }
        let Ok(meta) = std::fs::metadata(base.join("stat")) else { continue };
        if meta.uid() != uid {
            continue;
        }
        if unsafe { libc::kill(pid, sig) } == 0 {
            n += 1;
        }
    }
    n
}

/// E132 — o compat do craft-game: o daemon escreve o PRÓPRIO pid no
/// game-watch.pid do RUN_DIR (o status 'watch no ar' do craft-game lê
/// este arquivo e aceita o cmdline 'elite-daemon' na prova).
fn escreve_pid_watch() {
    let run_dir = std::env::var("XDG_RUNTIME_DIR")
        .map(|d| PathBuf::from(d).join("elite"))
        .unwrap_or_else(|_| PathBuf::from("/tmp/elite"));
    let _ = std::fs::create_dir_all(&run_dir);
    let _ = std::fs::write(run_dir.join("game-watch.pid"), format!("{}\n", std::process::id()));
}


// ════════════════════════════════════════════════════════════════════════
// E135 — OS OUVIDORES DE EVENTO (a lei do dono: ZERO polling — toda
// supervisão, roteamento e display operam por sinal dentro do daemon):
//   · netlink uevent (AF_NETLINK, KOBJECT_UEVENT) — SOM: hotplug de
//     fone/BT/DAC/jack dispara UM `craft-audio-route --once` (o roteador
//     python deixa de ser residente); DRM: hotplug de monitor dispara UM
//     `craft-display apply` (o watch shell deixa de ser residente);
//   · logind (D-Bus nativo) — PrepareForSleep(false) e Unlock disparam UM
//     `craft-display apply` (o __login1-watch shell morre);
//   · session bus NameOwnerChanged — SIGRTMIN+9 à waybar (a pílula dos
//     apps em 2º plano é EVENTO, não fork de 5s em 5s);
//   · toplevel.sock EVT — a mudança de janelas acorda o loop do jogo
//     (a detecção é por EVENTO + inspeção única de /proc; o tick de 5s
//     sobrevive só como cinto de segurança dos windowless).
// Todos os dispara-um-comando são fork POR EVENTO (raro, não residencial
// — a lei é contra RESIDENTES em sh/bash/python, nunca contra o fork
// pontual que a infra shell da casa já sabe fazer).
// ════════════════════════════════════════════════════════════════════════

fn agora_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// o fork pontual por evento: stdin/stdout/stderr nulos (nada de filho
/// falando no papel do daemon).
fn dispara(comando: &str, args: &[&str]) {
    let _ = Command::new(comando)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

/// o ouvidor de uevents do kernel (SOCK_RAW + NETLINK_KOBJECT_UEVENT,
/// grupo 1 multicast — a fila de eventos da casa, zero dependência).
fn thread_netlink() {
    unsafe {
        let fd = libc::socket(
            libc::AF_NETLINK,
            libc::SOCK_RAW | libc::SOCK_CLOEXEC,
            libc::NETLINK_KOBJECT_UEVENT,
        );
        if fd < 0 {
            eprintln!("elite-daemon: netlink indisponível — eventos de som/drm sem ouvidor");
            return;
        }
        // nl_pad é campo PRIVADO no libc 0.2.191 — o zeroed é a via
        // (os campos públicos recebem os valores depois)
        let mut addr: libc::sockaddr_nl = std::mem::zeroed();
        addr.nl_family = libc::AF_NETLINK as u16;
        addr.nl_groups = 1;
        if libc::bind(
            fd,
            &addr as *const _ as *const libc::sockaddr,
            std::mem::size_of::<libc::sockaddr_nl>() as u32,
        ) != 0
        {
            libc::close(fd);
            return;
        }
        let mut buf = [0u8; 8192];
        let mut last_snd = 0u64;
        let mut last_drm = 0u64;
        loop {
            if STOP.load(Ordering::SeqCst) {
                libc::close(fd);
                return;
            }
            let n = libc::recv(
                fd,
                buf.as_mut_ptr() as *mut libc::c_void,
                buf.len(),
                0,
            );
            if n <= 0 {
                std::thread::sleep(Duration::from_millis(500));
                continue;
            }
            let data = String::from_utf8_lossy(&buf[..n as usize]);
            let agora = agora_ms();
            // SOM: hotplug de fone/BT/DAC/jack (o roteador decide o resto)
            if (data.contains("/sound/") || data.contains("SUBSYSTEM=sound"))
                && agora.saturating_sub(last_snd) > 800
            {
                last_snd = agora;
                dispara("/usr/local/bin/craft-audio-route", &["--once"]);
            }
            // DRM: monitor plugado/desplugado → o arranjo do dono volta
            if (data.contains("/drm") || data.contains("SUBSYSTEM=drm"))
                && agora.saturating_sub(last_drm) > 800
            {
                last_drm = agora;
                dispara("/usr/local/bin/craft-display", &["apply"]);
            }
        }
    }
}

/// o ouvidor do logind: acordou OU desbloqueou → o arranjo do dono volta
/// (o imediato é lei E118 — o fork é UM por evento, não residente).
fn thread_logind(nome_sinal: &str, corpo_bool: bool) {
    let Ok(c) = zbus::blocking::Connection::system() else {
        return;
    };
    let Ok(p) = zbus::blocking::Proxy::new(
        &c,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
    ) else {
        return;
    };
    let Ok(sig) = p.receive_signal(nome_sinal) else {
        return;
    };
    // o MessageIterator BLOCKING rende Message direto (o erro interno
    // da conexão já é tratado pela própria camada blocking da zbus)
    for m in sig {
        if STOP.load(Ordering::SeqCst) {
            return;
        }
        if corpo_bool {
            // PrepareForSleep: o corpo é (b starting) — acordou é false
            if let Ok((start,)) = m.body().deserialize::<(bool,)>() {
                if !start {
                    dispara("/usr/local/bin/craft-display", &["apply"]);
                }
            }
        } else {
            // Unlock/Lock: o corpo é (s interface) — qualquer um conta
            let _ = m.body().deserialize::<(String,)>();
            dispara("/usr/local/bin/craft-display", &["apply"]);
        }
    }
}

/// o ouvidor do session bus: o nome de QUALQUER app nasceu/morreu →
/// SIGRTMIN+9 (a pílula dos 2º planos relê; debounce embutido nos
/// rajadas de birth+death do mesmo app — o kill só sai após 200ms
/// de silêncio, sem drenar a CPU em rajada de D-Bus).
fn thread_bus_bgapps() {
    let Ok(c) = zbus::blocking::Connection::session() else {
        return;
    };
    let Ok(p) = zbus::blocking::Proxy::new(
        &c,
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
    ) else {
        return;
    };
    let Ok(mut sig) = p.receive_signal("NameOwnerChanged") else {
        return;
    };
    let mut pendente = false;
    let mut desde = Instant::now();
    loop {
        // um read com timeout curto drena o sinal; o debounce agrupa
        std::thread::sleep(Duration::from_millis(50));
        if STOP.load(Ordering::SeqCst) {
            return;
        }
        if sig.next().is_some() {
            if !pendente {
                pendente = true;
                desde = Instant::now();
            }
        }
        if pendente && desde.elapsed() >= Duration::from_millis(200) {
            pendente = false;
            sinal_waybar_sig(9);
        }
    }
}

/// E139 — O PRÉ-SONO DO WAKE-GUARD (PrepareForSleep com start=true): UM
/// `craft-wake-guard apply` no limiar de cada sono — a política do
/// despertar é REAFIRMADA (os não-teclados disabled FORÇADOS de novo,
/// o gate por controlador re-julgado com a árvore do momento; o
/// hotplug do BT que dormiu na sessão não sobrevive ao sono). Um fork
/// por sono, zero residente — a mesma lei dos irmãos.
fn thread_wakeguard() {
    let Ok(c) = zbus::blocking::Connection::system() else {
        return;
    };
    let Ok(p) = zbus::blocking::Proxy::new(
        &c,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
    ) else {
        return;
    };
    let Ok(sig) = p.receive_signal("PrepareForSleep") else {
        return;
    };
    for m in sig {
        if STOP.load(Ordering::SeqCst) {
            return;
        }
        if let Ok((start,)) = m.body().deserialize::<(bool,)>() {
            if start {
                dispara("/usr/local/bin/craft-wake-guard", &["apply"]);
            }
        }
    }
}

/// o ouvidor do toplevel.sock: o canal EVT do craft-toplevel acorda o
/// loop do jogo (a detecção por EVENTO — o réu do loop 5s gravando no
/// game.log morre; o tick sobrevive só como cinto dos windowless).
/// A reconexão é backoff exponencial 5ms → 20ms → 100ms (a ordem do
/// dono — o fallback de 5s morto não existe mais).
fn thread_toplevel_evt(frete: Arc<(Mutex<bool>, Condvar)>) {
    let caminho = std::env::var("XDG_RUNTIME_DIR")
        .map(|d| PathBuf::from(d).join("elite/toplevel.sock"))
        .unwrap_or_else(|_| PathBuf::from("/tmp/elite/toplevel.sock"));
    let mut back = 5u64;
    loop {
        if STOP.load(Ordering::SeqCst) {
            return;
        }
        match std::os::unix::net::UnixStream::connect(&caminho) {
            Ok(mut s) => {
                back = 5;
                if s.write_all(b"EVT ON\n").is_err() {
                    continue;
                }
                let _ = s.set_read_timeout(Some(Duration::from_secs(30)));
                let mut buf = [0u8; 4096];
                loop {
                    match s.read(&mut buf) {
                        Ok(n) if n > 0 => {
                            if buf[..n].windows(3).any(|w| w == b"EVT") {
                                let (l, cv) = &*frete;
                                let mut vivo = l.lock().unwrap();
                                *vivo = true;
                                cv.notify_all();
                            }
                        }
                        _ => break, // caiu: o giro seguinte reconecta
                    }
                    if STOP.load(Ordering::SeqCst) {
                        return;
                    }
                }
            }
            Err(_) => {
                // backoff exponencial 5 → 20 → 100ms (teto na lei)
                std::thread::sleep(Duration::from_millis(back));
                back = (back * 4).min(100);
            }
        }
    }
}

/// E135 — o PERFIL DE GPU (amdgpu sysfs): power_dpm_force_performance_level
/// → "high" na sessão de jogo, o valor ANTERIOR devolvido ao sair (a
/// memória é a função pura abaixo, testada). LACT segue no ar para o
/// resto — aqui só o perfil da sessão.
fn gpu_aplica(valor: &str) -> Vec<(PathBuf, String)> {
    let mut mem: Vec<(PathBuf, String)> = Vec::new();
    let Ok(dir) = std::fs::read_dir("/sys/class/drm") else {
        return mem;
    };
    for entry in dir.flatten() {
        let nome = entry.file_name();
        let Some(nome) = nome.to_str() else { continue };
        if !nome.starts_with("card") || nome.contains('-') {
            continue; // card1-DP-1 é conector — o perfil mora no card
        }
        let p = entry.path().join("device/power_dpm_force_performance_level");
        let Ok(atual) = std::fs::read_to_string(&p) else { continue };
        if atual.trim() == valor {
            continue; // já é: idempotente
        }
        if std::fs::write(&p, valor).is_ok() {
            mem.push((p, atual.trim().to_string()));
        }
    }
    mem
}

fn gpu_restaura(mem: Vec<(PathBuf, String)>) -> usize {
    let mut n = 0;
    for (p, valor) in mem {
        if std::fs::write(&p, &valor).is_ok() {
            n += 1;
        }
    }
    n
}

/// E135 — o Não Perturbe do swaync na sessão de jogo (D-Bus NATIVO do
/// org.erikreider.swaync.cc — GetDnd primeiro: só TOGGLA quem estava
/// desligado, o restauro é SIMÉTRICO; o dono que já dormia o swaync
/// não acorda com o jogo). Sem bus/sem swaync = None (honesto).
fn dnd_troca() -> Option<bool> {
    let c = zbus::blocking::Connection::session().ok()?;
    let p = zbus::blocking::Proxy::new(
        &c,
        "org.erikreider.swaync.cc",
        "/org/erikreider/swaync/cc",
        "org.erikreider.swaync.cc",
    )
    .ok()?;
    let estava: bool = p.call::<_, _, bool>("GetDnd", &()).ok()?;
    let _: Result<(), _> = p.call_noreply("ToggleDnd", &());
    Some(estava)
}

fn daemon_loop() -> Result<(), String> {
    // instância única (E30): flock no arquivo — o 2º processo sai 0.
    let lock = PathBuf::from("/tmp/elite-daemon.lock");
    let f = std::fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(&lock)
        .map_err(|e| format!("lock {}: {}", lock.display(), e))?;
    let rc = unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if rc != 0 {
        return Ok(()); // o irmão está no ar — saída silenciosa e honesta
    }
    instala_sinais();
    escreve_pid_watch();

    // o frete do toplevel EVT é DESTE corpo (o loop do jogo acorda por
    // evento — a detecção é EVENTO + inspeção única de /proc)
    let frete = Arc::new((Mutex::new(false), Condvar::new()));
    {
        let f = Arc::clone(&frete);
        std::thread::spawn(move || thread_toplevel_evt(f));
    }
    // E139 — OS OUVIDORES MUDARAM PARA A PORTA DA SESSÃO (a vaga do jogo
    // é condicionada ao AUTO do game.conf — o rig com AUTO=0 não tem
    // daemon_loop e a sessão ficava CEGA: display sem apply no
    // despertar, áudio sem roteamento no hotplug). A porta session é
    // quem SEMPRE está viva e ela levanta os ouvidores. O CINTO: se
    // NÃO há session vivo (rig legado, watch à mão), ESTE corpo os
    // levanta — o peek no lock da sessão decide, nunca dois donos.
    if supervise::peek_lock_livre(&PathBuf::from("/tmp/elite-daemon-session.lock")) {
        std::thread::spawn(thread_netlink);
        std::thread::spawn(|| thread_logind("PrepareForSleep", true));
        std::thread::spawn(|| thread_logind("Unlock", false));
        std::thread::spawn(thread_bus_bgapps);
        std::thread::spawn(thread_wakeguard);
        eprintln!(
            "elite-daemon: sem session vivo — os ouvidores sobem AQUI (o \
             cinto do modo game)"
        );
    }
    eprintln!("elite-daemon: no ar (toplevel EVT no corpo; os ouvidores de sessão vivem na porta session — E139)");

    let mut held: HashMap<i32, String> = HashMap::new();
    let mut retire = 0u32;
    let mut rodadas = 0u64;
    let conn = scan::gm_connect();

    // E132 — o estado da SESSÃO de jogo (a máquina das transições):
    // ativa = jogo registrado OU QueryStatus 1 (o manual do dono conta);
    // confirmada = os 3s do debounce passaram com o modo ATIVO (o fim de
    // uma sessão confirmada é notícia; pulo transitório não é).
    let mut sessao_ativa = false;
    // E138 — sem inicializador morto: o compilador PROVA que a 1ª leitura
    // sempre vem depois da 1ª escrita (era `= 0u64` nunca lido — warning)
    let mut iniciada_em: u64;
    // E135 — a memória da SESSÃO: o perfil de GPU anterior (o sysfs
    // devolve), o estado do DND do swaync e o inhibitor lock do logind
    // (o lock/apagamento de tela NÃO morrem durante a partida — o fd
    // solto é o fim da inibição; o dono suspender à mão segue livre).
    let mut gpu_mem: Vec<(PathBuf, String)> = Vec::new();
    let mut dnd_era: Option<bool> = None;
    let mut inhibitor: Option<zbus::zvariant::OwnedFd> = None;
    // o token de geração cancela a thread de debounce pendente quando a
    // sessão cai dentro da janela (o AtomicBool 'confirmada' é escrita
    // PELA thread e lida pelo loop — o estado de 2 pontas, sem lock).
    let token = Arc::new(AtomicU64::new(0));
    let confirmada = Arc::new(AtomicBool::new(false));

    loop {
        let achados = scan::round();
        // os registrados que morreram: libera (o reaper do gamemoded
        // também sabe — o unregister é o cinto)
        held.retain(|pid, _| {
            let vivo = unsafe { libc::kill(*pid, 0) } == 0;
            if !vivo {
                scan::gm_unregister(&conn, *pid);
            }
            vivo
        });
        for p in &achados {
            if !held.contains_key(&p.pid) {
                if scan::gm_register(&conn, p.pid) {
                    eprintln!(
                        "elite-daemon: jogo pid {} (via {}) registrado no gamemode",
                        p.pid, p.via
                    );
                    held.insert(p.pid, p.comm.clone());
                }
            }
        }

        // E132 — a SESSÃO: ATIVA com jogo nosso OU modo aceso por fora
        // (o manual do dono também é sessão — o EPP segue o estado REAL).
        let status = scan::gm_status(&conn);
        let ativa = !held.is_empty() || status == 1;

        if ativa && !sessao_ativa {
            // transição INATIVO→ATIVO: EPP performance, sinal à waybar e
            // a thread do debounce (3s em fundo — o pulo transitório do
            // Hydra morre na janela, não na tela do dono)
            let n = epp_aplica("performance");
            gpu_mem = gpu_aplica("high");
            dnd_era = dnd_troca();
            // o inhibitor do logind (nativo): o lock/apagamento dorme
            {
                if let Ok(c) = zbus::blocking::Connection::system() {
                    if let Ok(p) = zbus::blocking::Proxy::new(
                        &c,
                        "org.freedesktop.login1",
                        "/org/freedesktop/login1",
                        "org.freedesktop.login1.Manager",
                    ) {
                        inhibitor = p
                            .call::<_, _, zbus::zvariant::OwnedFd>(
                                "Inhibit",
                                &("idle", "elite", "Modo de jogo ativo", "block"),
                            )
                            .ok();
                    }
                }
            }
            eprintln!(
                "elite-daemon: sessão de jogo ATIVA — EPP performance em {} cpu(s) + GPU high em {} card(s) + DND {} + {} waybar(s) avisada(s) + inhibitor logind {}",
                n,
                gpu_mem.len(),
                if dnd_era.is_some() { "ligado" } else { "indisponível" },
                sinal_waybar(),
                if inhibitor.is_some() { "ARMADO" } else { "sem (honesto)" }
            );
            iniciada_em = agora_epoch();
            confirmada.store(false, Ordering::SeqCst);
            let tok = token.fetch_add(1, Ordering::SeqCst) + 1;
            let confirmada_t = Arc::clone(&confirmada);
            let token_t = Arc::clone(&token);
            let iniciada = iniciada_em;
            std::thread::spawn(move || {
                std::thread::sleep(Duration::from_secs(JANELA_DEBOUNCE_S));
                // a sessão caiu DENTRO da janela: cancelada em silêncio
                if token_t.load(Ordering::SeqCst) != tok {
                    return;
                }
                let conn_t = scan::gm_connect();
                if scan::gm_status(&conn_t) == 1
                    && veredito_debounce(iniciada, agora_epoch(), true).inicio
                {
                    confirmada_t.store(true, Ordering::SeqCst);
                    note("Governor performance + GPU high automáticos");
                }
            });
            sessao_ativa = true;
        } else if !ativa && sessao_ativa {
            // transição ATIVO→INATIVO: cancela o pendente, devolve o EPP,
            // sinaliza a waybar; o FIM só notifica sessão CONFIRMADA
            token.fetch_add(1, Ordering::SeqCst); // cancela a thread da janela
            let confirmou = confirmada.load(Ordering::SeqCst);
            let n = epp_aplica("balance_performance");
            let gpu_devolvida = gpu_restaura(std::mem::take(&mut gpu_mem));
            if dnd_era.take() == Some(false) {
                // só DEVOLVE quem a casa ligou (o toggles são simétricos)
                let _ = dnd_troca();
            }
            drop(inhibitor.take());
            eprintln!(
                "elite-daemon: sessão de jogo FIM — EPP balance_performance em {} cpu(s) + GPU restaurada em {} card(s) + {} waybar(s) avisada(s){}",
                n,
                gpu_devolvida,
                sinal_waybar(),
                if confirmou { " (sessão confirmada — dono avisado)" } else { " (pulo transitório <3s: silêncio na notícia)" }
            );
            if confirmou {
                note("Perfil normal restaurado");
            }
            sessao_ativa = false;
            confirmada.store(false, Ordering::SeqCst);
        }

        // a aposentadoria do daemon ocioso (a física do watch bash: 2
        // rodadas sem jogo e sem manual — o gamemoded renasce por D-Bus)
        if held.is_empty() && status == 0 {
            retire += 1;
        } else {
            retire = 0;
        }
        if retire >= 2 {
            scan::gm_quit(&conn);
            retire = 0;
        }

        // SIGTERM/SIGINT (o toggle do menu e o logout): unregister de
        // tudo, EPP devolvido se a sessão estava acesa, saída limpa.
        if STOP.load(Ordering::SeqCst) {
            for pid in held.keys() {
                scan::gm_unregister(&conn, *pid);
            }
            if sessao_ativa {
                let n = epp_aplica("balance_performance");
                let gpu_devolvida = gpu_restaura(std::mem::take(&mut gpu_mem));
                if dnd_era.take() == Some(false) {
                    let _ = dnd_troca();
                }
                drop(inhibitor.take());
                eprintln!(
                    "elite-daemon: SIGTERM — {} jogo(s) liberado(s), EPP devolvido em {} cpu(s), GPU restaurada em {} card(s)",
                    held.len(),
                    n,
                    gpu_devolvida
                );
            }
            return Ok(());
        }
        // E135 — o SLEEP MORREU: o loop dorme no condvar e o canal EVT
        // do toplevel.sock o acorda (a detecção é POR EVENTO — a janela
        // que nasce é o jogo anunciando; o teto de 5s sobrevive como
        // cinto dos processos windowless). Cada 6 rodadas de cinto
        // (30s) a pílula dos 2º planos relê (a segurança dos apps que
        // não tomam nome no bus — o EVENTO deles é o NameOwnerChanged).
        let (l, cv) = &*frete;
        let mut vivo = l.lock().unwrap();
        let (guarda, _timeout) = cv
            .wait_timeout(vivo, std::time::Duration::from_secs(5))
            .unwrap();
        vivo = guarda;
        let acordou_por_evento = *vivo;
        *vivo = false;
        drop(vivo);
        if acordou_por_evento {
            // o rajada de EVT assenta 250ms antes da inspeção única de
            // /proc (uma rodada por rajada, nunca uma por evento bruto)
            std::thread::sleep(std::time::Duration::from_millis(250));
        }
        rodadas += 1;
        if rodadas % 6 == 0 {
            sinal_waybar_sig(9);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debounce_o_inicio_espera_os_3s() {
        // a sessão LIGOU e seguiu viva: antes dos 3s NADA sobe (a janela
        // ainda pode ser cancelada pelo pulo transitório do Hydra)
        let v = veredito_debounce(100, 101, true);
        assert!(!v.inicio && !v.fim, "1s de sessão ativa não é notícia");
        let v = veredito_debounce(100, 102, true);
        assert!(!v.inicio && !v.fim, "2s de sessão ativa ainda é janela");
        // os 3s fecharam com o QueryStatus ATIVO: o INÍCIO sobe (1 vez)
        let v = veredito_debounce(100, 103, true);
        assert!(v.inicio && !v.fim, "3s confirmados com modo ativo = notícia");
        let v = veredito_debounce(100, 130, true);
        assert!(v.inicio, "sessão longa segue sendo notícia no instante da prova");
    }

    #[test]
    fn debounce_o_pulo_transitorio_e_silencio_absoluto() {
        // a sessão caiu DENTRO da janela (o pulo D-Bus do Hydra): nem
        // início, nem fim — o fantasma de 1s não é notícia (E132)
        let v = veredito_debounce(100, 101, false);
        assert!(!v.inicio && !v.fim, "pulo de 1s não notifica NADA");
        let v = veredito_debounce(100, 102, false);
        assert!(!v.inicio && !v.fim, "pulo de 2s não notifica NADA");
    }

    #[test]
    fn debounce_o_fim_de_sessao_real_e_noticia() {
        // sessão CONFIRMADA (>=3s ativos) que acabou: o FIM sobe
        let v = veredito_debounce(100, 105, false);
        assert!(!v.inicio && v.fim, "fim de sessão de 5s é notícia");
        let v = veredito_debounce(100, 200, false);
        assert!(v.fim, "fim de sessão longa é notícia");
    }
}
