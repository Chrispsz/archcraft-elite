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
use std::os::unix::fs::{FileTypeExt, MetadataExt};
use std::os::unix::io::AsRawFd;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

mod audio;
mod idle;
mod mpris;
mod nucleo;
mod scan;
mod supervise;
mod wayland;
mod workspace;

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
        // E150 — O SIGHUP DO RELOGIN: o labwc --exit despede os filhos do
        // autostart por SIGHUP (o terminal morre junto); o handler padrão
        // MATA na hora, mas o flock do session fica retido até o exit — e
        // a sessão NOVA que nasce no segundo seguinte topa o dono VELHO
        // ainda segurando a trava → 'elite-daemon session' sai 0 e o
        // desktop acorda vazio (só o menu.xml). O SIGHUP agora veste a
        // MESMA saída limpa do SIGTERM: unregister, EPP devolvido, filhos
        // colhidos, lock solto — o relogin nasce limpo.
        libc::signal(libc::SIGHUP, h);
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
        // pré-sono — cada thread dorme num read(2)/sinal, zero CPU em
        // repouso; a lei E135 dos residentes intocada). E147: o ouvidor
        // bus bgapps MORREU com o próprio módulo (a ordem do dono: o
        // indicador de 2º planos saiu da interface E do código). O rig
        // com AUTO=0 não tem motor de jogo e não pode ficar cego.
        Some("session") => {
            // 2.0 — O NÚCLEO VIVO: o bus.sock (a barra e a dock ganham
            // o fio), o cliente Wayland NATIVO (o craft-toplevel.c morre
            // — janelas, vigília e trava automática da casa), o MPRIS
            // (zero playerctl-polling) e o roteador de áudio Rust (o
            // python craft-audio-route morre com seu NameError herdado)
            // E150 — O RELOGIN LIMPO ANTES DE TUDO: o modo session COLHE
            // o fóssil da sessão anterior (daemon órfão que segurava o
            // lock) e só então veste o fio — a ordem importa (o bind do
            // bus no chão de um dono vivo seria o 'MORTO' de novo).
            if let Err(e) = supervise::colhe_relogin() {
                eprintln!("elite-daemon session: {e}");
            }
            // E150 — ESPERA O COMPOSITOR: o autostart pode nascer antes do
            // socket do labwc registrar (relogin rápido, boot frio); os
            // clientes de display morreriam no primeiro spawn e pagariam
            // o backoff inteiro. O teto é honesto (10s) e a espera é
            // barata (stat a cada 100ms) — a sessão só descola quando o
            // WAYLAND_DISPLAY EXISTE de verdade.
            espera_wayland(10);
            nucleo::liga_bus();
            wayland::start();
            std::thread::spawn(mpris::thread);
            std::thread::spawn(audio::thread_subscribe);
            std::thread::spawn(|| audio::rodada("start"));
            std::thread::spawn(thread_netlink);
            std::thread::spawn(|| thread_logind("PrepareForSleep", true));
            std::thread::spawn(|| thread_logind("Unlock", false));
            std::thread::spawn(thread_wakeguard);
            // E150 — A REAPLICAÇÃO DO MONITOR LOGO APÓS O WAYLAND (a cura
            // do '60 Hz no boot frio'): o apply-boot do autostart corre
            // no frame 0, mas no COLD BOOT as saídas podem registrar DEPOIS
            // dele (o amdgpu acorda lento) — o estado residual do driver
            // segurava os Hz no relogin e o boot frio perdia. ESTA thread é
            // o cinto: espera o socket, confere o arranjo vivo e re-aplica
            // com retry curto (3 passadas de 1.5s — o do_apply reconcilia
            // por dentro; a passada extra é no-op quando tudo confere).
            std::thread::spawn(thread_display_boot);
            eprintln!(
                "elite-daemon session: ouvidores no ar (bus.sock + wayland \
                 nativo + mpris + áudio + netlink som/drm + logind sono/unlock \
                 + wake-guard pré-sono + re-aplicação do monitor do boot)"
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

/// E132 — o sinal da topbar: SIGRTMIN+8 a TODO processo da BARRA do
/// uid corrente (leitura de /proc + libc::kill — NENHUM fork de pgrep;
/// o módulo relê o pill do modo no sinal).
/// E140 — a topbar agora é o craft-bar-rs (o waybar aposentou): o
/// sinal alcança OS DOIS comms — o rig da dose E140 já corre o
/// binário novo; o nome antigo segue na lista por honestidade de
/// transição (a barra velha de um relogin no meio da dose também
/// acende — nunca dois mundos mudos).
fn sinal_waybar() -> usize {
    sinal_waybar_sig(8)
}

/// E135 — o sinal da topbar com NÚMERO parametrizável: SIGRTMIN+N em
/// toda a barra do uid corrente. +8 = o pill do jogo (E147: o +9 dos
/// 2º planos MORREU com o próprio módulo — nenhum da casa manda mais
/// o +9; a função segue parametrizada para o futuro nomeado).
fn sinal_waybar_sig(offset: i32) -> usize {
    sinal_para_comms(&["craft-bar-rs", "waybar"], libc::SIGRTMIN() + offset)
}

/// 1.0-94 — O SINAL GENÉRICO da casa: um sinal a TODO processo vivo do
/// uid corrente cujo comm está na lista (a leitura de /proc + libc::kill
/// — NENHUM fork de pgrep; a barra e a dock vestem handlers/as armaduras
/// RT, o sinal nunca mais mata ninguém por disposição padrão).
/// E150 — pub(crate): a gaveta desce por ELE (o nwg-drawer vivo do uid
/// quando OUTRA janela ganha o palco — ver wayland.rs).
pub(crate) fn sinal_para_comms(comms: &[&str], sig: i32) -> usize {
    let uid = unsafe { libc::getuid() };
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
        let comm = comm.trim_end();
        if !comms.contains(&comm) {
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
//   · wayland NATIVO (2.0) — a mudança de janelas acorda o loop do
//     jogo (a detecção é por EVENTO + inspeção única de /proc; o tick
//     de 5s sobrevive só como cinto de segurança dos windowless).
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

/// E150 — O NOME do WAYLAND_DISPLAY corrente ("" = sem sessão gráfica:
/// CLI/probe/teste — a identidade que julga o órfão do relogin).
pub fn wayland_pronto_nome() -> String {
    std::env::var("WAYLAND_DISPLAY").unwrap_or_default()
}

/// E150 — A GAVETA DESCE COM O PALCO (a ordem do dono, base 1.0-98: o
/// nwg-drawer nunca fica sobreposto a janelas ou menus da barra): o
/// SIGTERM ao drawer vivo do uid (o nwg-drawer já desce sozinho ao
/// ABRIR app — MainQuit nativo; aqui é o caminho "perdeu o palco":
/// alt-tab, dock, janela nova). Um sinal por evento, zero residente.
pub(crate) fn gaveta_desce() {
    let n = sinal_para_comms(&["nwg-drawer"], libc::SIGTERM);
    if n > 0 {
        eprintln!(
            "elite-daemon: a gaveta desceu com o palco ({n} nwg-drawer colhido(s) — o overlay nunca fica por cima da casa)"
        );
    }
}

/// E150 — O SOCKET DO COMPOSITOR EXISTE? ($XDG_RUNTIME_DIR/$WAYLAND_DISPLAY
/// — o caminho absoluto também conta; sem WAYLAND_DISPLAY é a sessão de
/// teste, sempre pronta). Função PURA de ambiente — a porta dos testes.
pub fn wayland_pronto() -> bool {
    let Ok(nome) = std::env::var("WAYLAND_DISPLAY") else {
        return true; // sem variável = sem compositor esperado (prova)
    };
    if nome.starts_with('/') {
        return PathBuf::from(&nome).exists();
    }
    let runtime = std::env::var("XDG_RUNTIME_DIR")
        .unwrap_or_else(|_| format!("/run/user/{}", unsafe { libc::getuid() }));
    let socket = PathBuf::from(runtime).join(&nome);
    socket.metadata().map(|m| m.file_type().is_socket()).unwrap_or(false)
}

/// E150 — espera o compositor registrar o socket (teto em segundos,
/// sonda de 100ms — barata por desenho: um stat(2)).
fn espera_wayland(teto_s: u64) {
    let inicio = std::time::Instant::now();
    while !wayland_pronto() {
        if inicio.elapsed().as_secs() >= teto_s {
            eprintln!(
                "elite-daemon session: WAYLAND_DISPLAY não registrou em {teto_s}s — a sessão segue (os filhos pagam o backoff honesto)"
            );
            return;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}

/// E150 — O CINTO DO BOOT FRIO: o arranjo do monitor re-aplicado COM RETRY
/// logo após as saídas Wayland registrarem (o apply-boot do frame 0 pode
/// ter corrido antes do amdgpu acordar — o modo era RAM do driver e o 60
/// Hz voltava). Três passadas espaçadas; o `do_apply` reconcilia por
/// dentro (arranjo certo = no-op silencioso, arranjo divergente = aplica).
fn thread_display_boot() {
    let teto = std::time::Instant::now();
    while !wayland_pronto() && teto.elapsed().as_secs() < 10 {
        std::thread::sleep(Duration::from_millis(200));
    }
    if !wayland_pronto() {
        return; // sem compositor não há wlr-randr que valha (honesto)
    }
    for tentativa in 1..=3 {
        if STOP.load(Ordering::SeqCst) {
            return;
        }
        let ok = Command::new("/usr/local/bin/craft-display")
            .arg("apply")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if ok {
            if tentativa > 1 {
                eprintln!(
                    "elite-daemon session: arranjo do monitor aplicado na {tentativa}ª passada do boot (o 60 Hz do boot frio morre)"
                );
            }
            return;
        }
        std::thread::sleep(Duration::from_millis(1500));
    }
    eprintln!("elite-daemon session: a re-aplicação do arranjo não fechou (o watch e o heartbeat seguem de pé — a verdade mora no display.log)");
}

/// E150 — O DESPERTAR DE VERDADE: PrepareForSleep(false) OU Unlock (o
/// hyprlock encerrou) → as saídas RELIGAM EXPLICITAMENTE (wlopm --on — o
/// amdgpu perde o sinal no freeze e o modo de DPMS não volta sozinho) e
/// o relógio de idle RENASCE do zero (o tempo DORMIDO não conta como
/// inatividade — o lock logo após o acordar era a mentira do contador).
fn despertar() {
    dispara("/usr/local/bin/craft-display", &["apply"]);
    dispara("wlopm", &["--on", "*"]);
    wayland::reseta_idle();
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
            // SOM: hotplug de fone/BT/DAC/jack (o roteador decide o
            // resto — 2.0: o motor é o audio.rs DESTE binário; o python
            // craft-audio-route aposentou com o NameError herdado)
            if (data.contains("/sound/") || data.contains("SUBSYSTEM=sound"))
                && agora.saturating_sub(last_snd) > 800
            {
                last_snd = agora;
                std::thread::spawn(|| audio::rodada("event"));
            }
            // DRM: monitor plugado/desplugado → o arranjo do dono volta
            // 1.0-94 — e o RESPIRO DE PELE: o apply assenta (~400ms) e a
            // dock/barra recebem SIGUSR2 — a dock REMONTA os pins com os
            // ícones do modo novo (a dock preta/sem ícones do rig da
            // 1.0-93 nas trocas de resolução/refresh era a pílula pintada
            // no tamanho da era anterior) e a barra relê a pele CSS.
            if (data.contains("/drm") || data.contains("SUBSYSTEM=drm"))
                && agora.saturating_sub(last_drm) > 800
            {
                last_drm = agora;
                dispara("/usr/local/bin/craft-display", &["apply"]);
                std::thread::spawn(|| {
                    std::thread::sleep(Duration::from_millis(400));
                    sinal_para_comms(&["craft-dock-rs"], libc::SIGUSR2);
                    sinal_para_comms(&["craft-bar-rs"], libc::SIGUSR2);
                });
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
            // PrepareForSleep: o corpo é (b starting) — acordou é false:
            // o display volta E o som devolve o default pré-sono (a
            // dupla E139 anti-sequestro do HDMI/DP do monitor) E as saídas
            // religam + o idle renasce (E150 — o vídeo pós-suspensão)
            if let Ok((start,)) = m.body().deserialize::<(bool,)>() {
                if !start {
                    std::thread::spawn(audio::resume);
                    despertar();
                }
            }
        } else {
            // Unlock/Lock: o corpo é (s interface) — o hyprlock encerrou
            // (Unlock): o arranjo volta, as saídas religam, o idle renasce
            // (E150 — 'ao encerrar o hyprlock' é aqui)
            let _ = m.body().deserialize::<(String,)>();
            despertar();
        }
    }
}

/// E147 — O OUVIDOR BUS BGAPPS MORREU (o corpo removido): o ouvidor do
/// session bus mandava o SIGRTMIN+9 na transição de QUALQUER app do
/// bus (o consumidor era a pílula dos 2º planos da barra) — a ordem
/// do dono tirou o módulo da interface E do código: nenhuma thread,
/// nenhum fork de signal, nenhum consumidor. A armadura RT das barras
/// segue de pé para sinal de quem vier.
///
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
                // o PRÉ-SONO ATÔMICO (a diretriz 2.0: "sincronizar
                // bloqueio e retorno de forma atômica"): a foto do som
                // ANTES do freeze (ms quando o PipeWire vive), a trava
                // na tela no limiar do sono (o logind espera os
                // inhibitors — o hyprlock nasce antes do mergulho) e o
                // wake-guard reafirmado
                audio::sleep_save();
                idle::trava_pre_sono();
                dispara("/usr/local/bin/craft-wake-guard", &["apply"]);
            }
        }
    }
}

/// E140 — PORTA 5 — A JANELA É A PROVA (o dossiê 1.0-88: o Stardew
/// Valley do Hydra abria como janela `steam_app_413150` e o watcher
/// registrava SÓ o launcher <3s — a detecção por /proc é cega para o
/// jogo que troca de comm no caminho do Proton).
/// 2.0 — A PORTA 5 NATIVA: as janelas VIVAS do cliente Wayland DESTE
/// daemon (o toplevel.sock morreu com o craft-toplevel.c — a prova do
/// jogo invisível steam_app_* é o app_id no snapshot vivo).
fn janelas_de_jogo() -> Vec<String> {
    wayland::windows_mru()
        .into_iter()
        .filter(|w| scan::eh_app_janela_jogo(&w.app_id))
        .map(|w| w.app_id)
        .collect()
}

/// 2.0 — A THREAD DO FRETE morreu: o canal de eventos do jogo é o
/// cliente Wayland NATIVO (cada `Done`/`Closed` publica o snapshot no
/// bus e o loop do jogo acorda no frete de sempre).
fn thread_wakeup_frete(frete: Arc<(Mutex<bool>, Condvar)>) {
    // o cinto dos windowless: um toque suave a cada 5s no condvar (o
    // scan de /proc segue vivo para quem não tem janela) — as janelas
    // acendem o frete pelo publicador do wayland.rs
    loop {
        if STOP.load(Ordering::SeqCst) {
            return;
        }
        std::thread::sleep(Duration::from_secs(5));
        let (l, cv) = &*frete;
        let mut vivo = l.lock().unwrap();
        *vivo = true;
        cv.notify_all();
    }
}

/// o parse da tabela pp_power_profile_mode da AMD (a porta dos testes):
/// devolve (índice do 3D_FULL_SCREEN, índice atual marcado com '*').
/// A linha da casa: "  1  3D_FULL_SCREEN" / "  0  BOOTUP_DEFAULT *".
pub fn pp_parse_tabela(texto: &str) -> (Option<u32>, Option<u32>) {
    let mut alvo = None;
    let mut atual = None;
    for linha in texto.lines() {
        let t = linha.trim();
        let Some((idx, resto)) = t.split_once(char::is_whitespace) else { continue };
        let Ok(_idx) = idx.trim().parse::<u32>() else { continue };
        let nome = resto.trim();
        if nome.ends_with('*') {
            atual = Some(_idx);
        }
        if nome.starts_with("3D_FULL_SCREEN") {
            alvo = Some(_idx);
        }
    }
    (alvo, atual)
}

/// E135→2.0 — o PERFIL DE GPU (amdgpu sysfs): power_dpm_force_performance_level
/// → "high" na sessão de jogo + o PERFIL 3D_FULL_SCREEN da tabela
/// pp_power_profile_mode (a diretriz 2.0 — o perfil de jogo da AMD); os
/// valores ANTERIORES devolvidos ao sair (a memória é a lista; o parse
/// puro é testado). NVIDIA/Intel: os arquivos não existem — pulados em
/// silêncio (compatibilidade segura por ausência).
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

/// 2.0 — o PERFIL 3D_FULL_SCREEN da AMD (pp_power_profile_mode): aplica
/// o índice do perfil de jogo em todo card da casa e devolve a memória
/// (path + índice anterior) para o restauro simétrico. GPU sem a
/// tabela (NVIDIA/Intel) devolve vazia — compatibilidade segura.
fn gpu_profile_aplica() -> Vec<(PathBuf, String)> {
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
        let p = entry.path().join("device/pp_power_profile_mode");
        let Ok(tabela) = std::fs::read_to_string(&p) else { continue };
        let (Some(alvo), Some(atual)) = pp_parse_tabela(&tabela) else { continue };
        if alvo == atual {
            continue; // já é: idempotente
        }
        if std::fs::write(&p, alvo.to_string()).is_ok() {
            mem.push((p, atual.to_string()));
        }
    }
    mem
}

fn gpu_profile_restaura(mem: Vec<(PathBuf, String)>) -> usize {
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

    // o frete: o cinto dos windowless (o jogo SEM janela segue caçado
    // no /proc; o evento das janelas chega pelo publicador do wayland)
    let frete = Arc::new((Mutex::new(false), Condvar::new()));
    {
        let f = Arc::clone(&frete);
        std::thread::spawn(move || thread_wakeup_frete(f));
    }
    // E139 — OS OUVIDORES MUDARAM PARA A PORTA DA SESSÃO (a vaga do jogo
    // é condicionada ao AUTO do game.conf — o rig com AUTO=0 não tem
    // daemon_loop e a sessão ficava CEGA: display sem apply no
    // despertar, áudio sem roteamento no hotplug). A porta session é
    // quem SEMPRE está viva e ela levanta os ouvidores. O CINTO: se
    // NÃO há session vivo (rig legado, watch à mão), ESTE corpo os
    // levanta — o peek no lock da sessão decide, nunca dois donos.
    // 1.0-94 — O DONO ÚNICO DO BUS (a cura do bus.sock MORTO do rig da
    // 1.0-93): o peek no lock da sessão decide QUEM serve o fio. Sessão
    // viva = o modo game vira CLIENTE ("elite-daemon-game" publica as
    // transições pelo fio; o servidor retransmite) — o bind antigo fazia
    // remove_file+bind e MATIA o socket do dono da sessão no caminho (o
    // fóssil que o dump nomeava MORTO com os dois daemons vivos; pior: o
    // craft-game watch de fora nascia depois e roubava o caminho —
    // morrendo, deixava o fóssil no chão e a sessão cega para sempre).
    // 2.0 — sem sessão viva, ESTE corpo é o dono: liga o servidor E o
    // cliente Wayland (as janelas do jogo são a PORTA 5 NATIVA; a barra
    // acende o pill pelo fio além do sinal).
    // 1.0-93 — o peek confere os DOIS endereços do lock da sessão (o
    // PRIVADO novo `$XDG_RUNTIME_DIR/elite/session.lock` E o fallback
    // /tmp da era legada — o session pode ter caído no fallback quando
    // o runtime privado não abriu; um dono só, em qualquer casa)
    let (privado_livre, fallback_livre) = {
        let uid = unsafe { libc::getuid() };
        (
            supervise::peek_lock_livre(&elite_core::session_lock_path(uid)),
            supervise::peek_lock_livre(&PathBuf::from(elite_core::SESSION_LOCK_FALLBACK)),
        )
    };
    if privado_livre && fallback_livre {
        nucleo::liga_bus();
        eprintln!(
            "elite-daemon: sem session vivo — o bus E os ouvidores sobem AQUI (o cinto do modo game)"
        );
    } else {
        nucleo::liga_cliente();
    }
    wayland::start();
    if privado_livre && fallback_livre {
        std::thread::spawn(thread_netlink);
        std::thread::spawn(|| thread_logind("PrepareForSleep", true));
        std::thread::spawn(|| thread_logind("Unlock", false));
        std::thread::spawn(thread_wakeguard);
    }
    eprintln!("elite-daemon: no ar (toplevel EVT no corpo; os ouvidores de sessão vivem na porta session — E139)");

    let mut held: HashMap<i32, String> = HashMap::new();
    let mut retire = 0u32;
    let conn = scan::gm_connect();
    // E140 — O PROXY DA PORTA 5: janela steam_app_* viva SEM processo
    // caçado = o daemon registra o PRÓPRIO pid no GameMode (a sessão
    // de jogo conta enquanto a janela existir; a janela que fecha é o
    // unregister — o fim é por EVENTO do toplevel, o mesmo frete do
    // jogo de processo)
    let mut proxy = false;

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
    let mut gpu_perf_mem: Vec<(PathBuf, String)> = Vec::new();
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

        // E140 — A PORTA 5 NO LOOP: a janela steam_app_* viva é a prova
        // que o /proc não nomeou. O proxy só nasce quando NÃO há jogo
        // caçado (quem o /proc viu já registrou o pid DELE — o proxy é
        // o cinto do jogo invisível, nunca o segundo registro do visto)
        let janelas = janelas_de_jogo();
        if !janelas.is_empty() && held.is_empty() && !proxy {
            if scan::gm_register(&conn, std::process::id() as i32) {
                proxy = true;
                eprintln!(
                    "elite-daemon: janela de jogo VIVA ({} — a PORTA 5 do dossiê E140) → daemon PROXY no gamemode",
                    janelas.join(", ")
                );
            }
        }
        if proxy && janelas.is_empty() && held.is_empty() {
            scan::gm_unregister(&conn, std::process::id() as i32);
            proxy = false;
            eprintln!("elite-daemon: a janela de jogo fechou — proxy liberado");
        }

        // E132 — a SESSÃO: ATIVA com jogo nosso OU modo aceso por fora
        // (o manual do dono também é sessão — o EPP segue o estado REAL)
        // E140 — ou janela steam_app_* viva (o proxy da PORTA 5).
        let status = scan::gm_status(&conn);
        let ativa = !held.is_empty() || proxy || status == 1;

        if ativa && !sessao_ativa {
            // transição INATIVO→ATIVO: EPP performance, sinal à waybar e
            // a thread do debounce (3s em fundo — o pulo transitório do
            // Hydra morre na janela, não na tela do dono)
            let n = epp_aplica("performance");
            gpu_mem = gpu_aplica("high");
            gpu_perf_mem = gpu_profile_aplica();
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
            // 2.0 — o pill da barra acende PELO FIO (o sinal é o cinto)
            nucleo::pub_bus(&elite_core::BusMsg::GameMode(elite_core::GameModeState {
                active: true,
                game: held.values().next().cloned().or_else(|| janelas.first().cloned()),
                gpu_performance: true,
            }));
            eprintln!(
                "elite-daemon: sessão de jogo ATIVA — EPP performance em {} cpu(s) + GPU high em {} card(s) + perfil 3D_FULL_SCREEN em {} card(s) + DND {} + {} waybar(s) avisada(s) + inhibitor logind {}",
                n,
                gpu_mem.len(),
                gpu_perf_mem.len(),
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
            let perf_devolvida = gpu_profile_restaura(std::mem::take(&mut gpu_perf_mem));
            nucleo::pub_bus(&elite_core::BusMsg::GameMode(elite_core::GameModeState {
                active: false,
                game: None,
                gpu_performance: false,
            }));
            if dnd_era.take() == Some(false) {
                // só DEVOLVE quem a casa ligou (o toggles são simétricos)
                let _ = dnd_troca();
            }
            drop(inhibitor.take());
            eprintln!(
                "elite-daemon: sessão de jogo FIM — EPP balance_performance em {} cpu(s) + GPU restaurada em {} card(s) + perfil devolvido em {} card(s) + {} waybar(s) avisada(s){}",
                n,
                gpu_devolvida,
                perf_devolvida,
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
        // tudo (o proxy também — a casa não deixa o gamemode aceso),
        // EPP devolvido se a sessão estava acesa, saída limpa.
        if STOP.load(Ordering::SeqCst) {
            for pid in held.keys() {
                scan::gm_unregister(&conn, *pid);
            }
            if proxy {
                scan::gm_unregister(&conn, std::process::id() as i32);
            }
            if sessao_ativa {
                let n = epp_aplica("balance_performance");
                let gpu_devolvida = gpu_restaura(std::mem::take(&mut gpu_mem));
                let perf_devolvida = gpu_profile_restaura(std::mem::take(&mut gpu_perf_mem));
                if dnd_era.take() == Some(false) {
                    let _ = dnd_troca();
                }
                drop(inhibitor.take());
                nucleo::pub_bus(&elite_core::BusMsg::GameMode(elite_core::GameModeState {
                    active: false,
                    game: None,
                    gpu_performance: false,
                }));
                eprintln!(
                    "elite-daemon: SIGTERM — {} jogo(s) liberado(s), EPP devolvido em {} cpu(s), GPU restaurada em {} card(s), perfil devolvido em {} card(s)",
                    held.len(),
                    n,
                    gpu_devolvida,
                    perf_devolvida
                );
            }
            return Ok(());
        }
        // E135 — o SLEEP MORREU: o loop dorme no condvar e o frete do
        // cliente Wayland o acorda (a detecção é POR EVENTO — a janela
        // que nasce é o jogo anunciando; o teto de 5s sobrevive como
        // cinto dos processos windowless).
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
        // E147: o relê de 6 rodadas dos 2º planos (SIGRTMIN+9 a cada
        // 30s) MORREU com o próprio módulo — o cinto de 5s do loop é
        // só dos processos windowless do jogo, nada mais.
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_tabela_do_pp_da_amd_e_parseada_certa() {
        // o papel REAL de um amdgpu (rig do dono): o BOOTUP_DEFAULT é o
        // atual; o 3D_FULL_SCREEN é o alvo da diretriz 2.0
        let tabela = "  0  BOOTUP_DEFAULT *\n  1  3D_FULL_SCREEN\n  2  POWER_SAVING\n  3  VIDEO\n  4  VR\n  5  COMPUTE\n  6  CUSTOM\n";
        let (alvo, atual) = pp_parse_tabela(tabela);
        assert_eq!(alvo, Some(1));
        assert_eq!(atual, Some(0));
        // com o 3D já marcado: idempotência de verdade
        let tabela2 = tabela.replace("BOOTUP_DEFAULT *", "BOOTUP_DEFAULT").replace("3D_FULL_SCREEN", "3D_FULL_SCREEN *");
        let (alvo2, atual2) = pp_parse_tabela(&tabela2);
        assert_eq!(alvo2, Some(1));
        assert_eq!(atual2, Some(1));
        // sem a tabela (NVIDIA/Intel): nada — compat por ausência
        assert_eq!(pp_parse_tabela(""), (None, None));
        assert_eq!(pp_parse_tabela("lixo total\nsem numeros"), (None, None));
    }

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

    #[test]
    fn e150_o_socket_wayland_e_julgado_pelo_tipo() {
        // sem WAYLAND_DISPLAY (prova/CLI): sempre pronto (nada a esperar)
        // — e o NOME vazio (a identidade do relogin julga por ele)
        std::env::remove_var("WAYLAND_DISPLAY");
        assert!(wayland_pronto());
        assert_eq!(wayland_pronto_nome(), "");
        // caminho absoluto: o próprio arquivo é a prova
        let t = std::env::temp_dir().join("elite-prova-wayland-socket");
        std::fs::write(&t, b"").unwrap();
        std::env::set_var("WAYLAND_DISPLAY", &t);
        assert!(wayland_pronto());
        std::fs::remove_file(&t).ok();
        std::env::remove_var("WAYLAND_DISPLAY");
    }
}
