// ELITE · elite-daemon v2 (E131→E132→1.0-107) — O ORQUESTRADOR ÚNICO DA
// SESSÃO. A ordem do dono ("espremer o limão"): os loops residentes de
// shell viram UM daemon em Rust — zero fork por tick, eventos de verdade
// (netlink, D-Bus, Wayland, ext-idle-notify).
//
// 1.0-107 — O MODO DE JOGO AUTOMÁTICO MORREU (a diretriz §6: "remover
// integralmente o modo automático… deixar o daemon LIVRE de varredura
// de processos"): o daemon_loop de era (a detecção /proc de jogo E132,
// o EPP dinâmico, o perfil de GPU, o debounce de 3s, a aposentadoria do
// gamemoded e o --once) sai INTEIRO com o watcher — o modo de jogo é o
// MANUAL do craft-game (menu + ícone da top bar: gamemoded holder +
// inhibitor idle:sleep + o pill pelo fio), e o daemon só PUBLICA o
// estado que o craft-game reporta (`game-notify` — o QueryStatus REAL
// no bus da sessão, a barra acende no MESMO instante do clique).
//
// ESCOPO HONESTO (o degrau é incrementado, a lei AGENTS.md §2):
//   · `session` — O LANÇADOR ÚNICO da sessão gráfica (clientes de
//     display + residentes com gate de posse E135; o craft-bars shell
//     vira `exec elite-daemon session` — zero /bin/sh residente) e os
//     OUVIDORES de evento (netlink som/drm, logind sono/unlock, o
//     wake-guard pré-sono, MPRIS, BlueZ, áudio);
//   · `supervise` — o supervisor dos residentes da sessão (swayosd,
//     swaync com dono único 1.0-107) com try_wait nativo e backoff de 2s;
//   · `game-notify` — o CLI do toggle manual do craft-game (publica o
//     QueryStatus REAL no bus — o pill da barra acende no mesmo clique);
//   · `desk N|left|right|…` — o SYNC da mesa (o rc.xml registra a
//     troca; a dock veste .other-workspace na hora);
//   · instância ÚNICA por flock de arquivo (a lei E30 — o 2º sai 0);
//   · SIGTERM/SIGINT/SIGHUP: filhos colhidos, locks soltos, saída limpa.
// NÃO É DEGRAU DESTA v2: as barras waybar/dock SEGUIEM corpos próprios
// (a waybar só RECEBE o sinal daqui; a dock é outro corpo — nenhum
// half-promise de unificação pela metade).
//
// Custos medidos no desenho: zero fork por tick; o D-Bus é conexão
// PERSISTENTE (não abre por chamada); o notify-send só nas notícias de
// verdade (zero toast de fantasma).
use std::os::unix::fs::{FileTypeExt, MetadataExt};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

mod audio;
mod bluetooth;
// E190 T4 — O AUTOMOUNT NATIVO UDISKS2 (o ouvidor do ObjectManager no
// system bus: cada bloco novo com Filesystem em drive removível monta
// pelo VERBO do D-Bus — o udiskie Python residente sai da sessão)
mod discos;
mod doctor;
mod idle;
mod mpris;
// 1.0-110 T1 — A REDE NO FIO (o publicador event-driven de
// BusMsg::Network: o censo NM no arranque + cada PropertiesChanged /
// StateChanged / DeviceAdded vale um censo novo — zero nmcli em loop)
mod network;
mod nucleo;
mod scan;
mod supervise;
mod wayland;
mod workspace;

const VERSION: &str = "2.2.0";

// ── o sinal de parada (SIGTERM/SIGINT → saída limpa) ─────────────────────
static STOP: AtomicBool = AtomicBool::new(false);

// 1.0-102 — A PORTEIRA SABE QUEM É: o modo `session` é o único que
// desce a casa INTEIRA quando o compositor cai (o audit 102: o daemon
// da sessão registrava `Broken pipe (os error 32)` no fio do Wayland e
// SEGUIA VIVO — ppid 1 — segurando o session.lock, os filhos morriam
// com `Lost connection to Wayland compositor` e o supervisor os
// RELANÇAVA às cegas a cada 2s; no login seguinte a instância nova
// batia no flock, saía 0 e o desktop acordava VAZIO). O jogo/supervise
// puros seguem o comportamento de sempre (o fio morre honesto, o
// corpo segue para as outras portas).
pub(crate) static PORTA_SESSION: AtomicBool = AtomicBool::new(false);

extern "C" fn ao_sinal(_sig: i32) {
    unsafe {
        // a casa salva o errno (o write do pipe pode pisar — a norma
        // async-signal-safe é a lei; o handler de era pisava calado)
        let e = libc::__errno_location();
        let salvo = *e;
        STOP.store(true, Ordering::SeqCst);
        wake_escreve();
        *e = salvo;
    }
}

// 1.0-107.2 — O SIGCHLD SEM STOP (a auditoria da filosofia: um filho
// que morre é EVENTO do kernel, não tick de relógio — o supervisor de
// era acordava 1×/s para adivinhar; agora o kernel TOCA a campainha).
extern "C" fn ao_chld(_sig: i32) {
    unsafe {
        let e = libc::__errno_location();
        let salvo = *e;
        wake_escreve();
        *e = salvo;
    }
}

// 1.0-110 T6 — O SIGUSR1 DO REEXEC (a ordem do dono: reexec in-place,
// mesmo PID, sem 2ª instância): o handler SÓ acende a bandeira e toca
// o pipe (async-signal-safe — o execve mora NA THREAD do supervisor,
// longe dos mallocs do handler; o corpo vive no reexec_in_place).
extern "C" fn ao_reexec(_sig: i32) {
    unsafe {
        let e = libc::__errno_location();
        let salvo = *e;
        REEXEC.store(true, Ordering::SeqCst);
        wake_escreve();
        *e = salvo;
    }
}

/// 1.0-110 T6 — a bandeira do reexec (o supervisor veste o gesto na
/// thread DELE, acordado pelo byte do self-pipe).
pub(crate) static REEXEC: AtomicBool = AtomicBool::new(false);

/// 1.0-110 T6 — o fd do FLOCK single-instance desta instância (o
/// reexec limpa o CLOEXEC dele e o entrega pelo env ELITE_LOCK_FD: a
/// instância renascida ADOTA o mesmo fd — ver supervisa).
pub(crate) static LOCK_FD: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(-1);

/// 1.0-110 T6 — O REEXEC IN-PLACE (o corpo do SIGUSR1): execve de SI
/// MESMO preservando o fd do flock single-instance (ELITE_LOCK_FD
/// contínuo — o CLOEXEC do fd da trava é LIMPO antes do exec): MESMO
/// PID, os clientes do bus.sock RECONECTAM no fio novo, SEM 2ª instância
/// (o flock é do open-file-description — o execve não solta o que o
/// MESMO processo segura; os filhos vivos são ADOTADOS pelos gates de
/// posse na renascida, os mortos são colhidos pelo dreno de lá).
pub(crate) fn reexec_in_place() {
    let fd = LOCK_FD.load(Ordering::SeqCst);
    if fd >= 0 {
        unsafe {
            let fl = libc::fcntl(fd, libc::F_GETFD);
            if fl >= 0 {
                // o CLOEXEC MORRE no fd da trava: o execve de si mesmo
                // PRESERVA a posse (o lock atravessa o nascimento)
                let _ = libc::fcntl(fd, libc::F_SETFD, fl & !libc::FD_CLOEXEC);
            }
        }
        std::env::set_var("ELITE_LOCK_FD", fd.to_string());
    }
    let exe = std::env::current_exe()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| "elite-daemon".to_string());
    let Ok(exe_c) = std::ffi::CString::new(exe.as_str()) else {
        eprintln!("elite-daemon: o reexec não vestiu o caminho próprio — a sessão segue viva (honesto)");
        return;
    };
    // o argv RENASCE igual (a porta "session" segue sendo a porta)
    let mut argv: Vec<std::ffi::CString> = vec![exe_c.clone()];
    for a in std::env::args().skip(1) {
        if let Ok(c) = std::ffi::CString::new(a) {
            argv.push(c);
        }
    }
    eprintln!(
        "elite-daemon: SIGUSR1 — reexec in-place (execve de si mesmo; PID {} e flock preservados)",
        std::process::id()
    );
    let mut ptrs: Vec<*const libc::c_char> = argv.iter().map(|c| c.as_ptr()).collect();
    ptrs.push(std::ptr::null());
    unsafe {
        libc::execv(exe_c.as_ptr(), ptrs.as_mut_ptr());
    }
    // execv só volta no ERRO: a sessão segue viva (honesto no papel)
    eprintln!(
        "elite-daemon: o reexec FALHOU ({}) — a sessão segue viva",
        std::io::Error::last_os_error()
    );
}

// ── 1.0-107.2 — O SELF-PIPE DOS EVENTOS (a lei do zero-tick) ────────────
// O pipe nasce em instala_sinais e NUNCA morre: o handler escreve um
// byte (async-signal-safe: write(2) de 1 byte num pipe O_NONBLOCK — a
// norma POSIX; pipe cheio = EAGAIN ignorado, o byte de sobra não faz
// falta) e quem esperava acorda no poll(2). O fim_da_sessao chama da
// THREAD dele (a via normal — sem sinal, mesmo destino).
static WAKE_R: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(-1);
static WAKE_W: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(-1);

fn wake_escreve() {
    let fd = WAKE_W.load(Ordering::SeqCst);
    if fd >= 0 {
        let byte = [1u8];
        unsafe {
            libc::write(fd, byte.as_ptr().cast(), 1);
        }
    }
}

fn instala_sinais() {
    // 1.0-107.2 — O PIPE DOS EVENTOS (antes dos handlers: o handler que
    // acorda antes do pipe nascer é silêncio perdido — o pipe vem 1º)
    let mut fds = [-1i32; 2];
    if unsafe { libc::pipe2(fds.as_mut_ptr(), libc::O_CLOEXEC | libc::O_NONBLOCK) } == 0 {
        WAKE_R.store(fds[0], Ordering::SeqCst);
        WAKE_W.store(fds[1], Ordering::SeqCst);
    }
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
        // 1.0-107.2 — O EVENTO DE FILHO: todo filho da casa que morre
        // toca o pipe (o supervisor acorda NO instante; o try_wait
        // dele colhe na mesma passada — o waitpid dos filhos ALHEIOS
        // das outras threads segue intocado: handler não colhe, só toca)
        libc::signal(libc::SIGCHLD, ao_chld as extern "C" fn(i32) as usize);
        // 1.0-110 T6 — O REEXEC IN-PLACE: o SIGUSR1 acorda o supervisor
        // pelo pipe (a bandeira REEXEC) — o mesmo PID renasce vestido
        libc::signal(libc::SIGUSR1, ao_reexec as extern "C" fn(i32) as usize);
    }
}

/// 1.0-107.2 — A VIGIA DO SOCKET DO COMPOSITOR (inotify — a 2ª via do
/// fim da sessão vira EVENTO): o watchdog de era estatava o socket a
/// cada 1s para adivinhar o sumiço; o kernel agora avisa — IN_DELETE
/// no diretório do socket (o nome sai do chão). A checagem de verdade
/// continua no loop (o evento é a CAMPAINHA, wayland_pronto é o JUÍZO
/// — um arquivo alheio saindo do runtime dir acorda o vigia 1× e o
/// juiz diz "não era ele" com um stat de microssegundo).
fn liga_vigia_socket() {
    let Ok(nome) = std::env::var("WAYLAND_DISPLAY") else {
        return; // sem compositor esperado: sem vigia (a era idem)
    };
    if nome.is_empty() {
        return;
    }
    let dir: PathBuf = if nome.starts_with('/') {
        let p = PathBuf::from(&nome);
        match p.parent() {
            Some(d) if !d.as_os_str().is_empty() => d.to_path_buf(),
            _ => return,
        }
    } else {
        let runtime = std::env::var("XDG_RUNTIME_DIR")
            .unwrap_or_else(|_| format!("/run/user/{}", unsafe { libc::getuid() }));
        PathBuf::from(runtime)
    };
    let Some(c_dir) = std::ffi::CString::new(dir.as_os_str().as_encoded_bytes()).ok() else {
        return;
    };
    unsafe {
        let fd = libc::inotify_init1(libc::IN_CLOEXEC | libc::IN_NONBLOCK);
        if fd < 0 {
            return; // container exótico sem inotify: sem vigia (o SIGHUP/EPIPE seguem)
        }
        // IN_DELETE: o NOME saindo do chão do dir (o socket sumiu); a
        // vigia é de TODO o dir — o juiz do loop filtra (um arquivo
        // alheio custa 1 stat)
        let wd = libc::inotify_add_watch(fd, c_dir.as_ptr(), libc::IN_DELETE);
        if wd < 0 {
            libc::close(fd);
            return;
        }
        WATCH_FD.store(fd, Ordering::SeqCst);
    }
}

// a vigia do socket (fd do inotify; -1 = sem vigia no ambiente)
static WATCH_FD: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(-1);

/// 1.0-107.2 — A ESPERA DOS EVENTOS (o tick de 1s MORRE): bloqueia em
/// poll(2) até o KERNEL falar (SIGCHLD/STOP no self-pipe, o socket do
/// compositor sumindo na vigia inotify) ou o TETO do respawn bater (o
/// backoff de 2s de uma vaga morta — sem teto, o dormir da espera seria
/// eterno esperando um evento que não vem). teto_ms = -1 = sem teto.
/// Zero wake-up em idle: o loop de era pagava 86.400 syscalls/dia para
/// descobrir que nada aconteceu.
///
/// 1.0-108 — O FD MORTO SAI DO poll E DO CHÃO (a auditoria dos
/// descritores do loop — a perícia do spin de 95,6% de CPU em idle):
/// `poll(2)` num fd quebrado (POLLERR/POLLHUP/POLLNVAL) retorna
/// IMEDIATO com o erro em `revents` — o fd que não é tirado da mesa
/// vira busy-loop puro (o poll acorda no mesmo instante, o loop julga
/// que não há nada, dorme de novo e o kernel acorda de novo: spin).
/// O tratamento agora é o clássico de qualquer event loop: fd morto é
/// FECHADO e DESREGISTRADO da mesa (o atomic vira -1: o próximo giro
/// nem o lista). O dreno do inotify segue completo (o `read` em laço
/// até EAGAIN esvazia o buffer INTEIRO do kernel — um evento que
/// ficasse para trás acordaria o poll no instante seguinte sem nada
/// novo a julgar).
pub(crate) fn espera_evento(teto_ms: i32) {
    let pipe_r = WAKE_R.load(Ordering::SeqCst);
    let vigia = WATCH_FD.load(Ordering::SeqCst);
    let mut fds: Vec<libc::pollfd> = Vec::with_capacity(2);
    if pipe_r >= 0 {
        fds.push(libc::pollfd { fd: pipe_r, events: libc::POLLIN, revents: 0 });
    }
    if vigia >= 0 {
        fds.push(libc::pollfd { fd: vigia, events: libc::POLLIN, revents: 0 });
    }
    if fds.is_empty() {
        // pipe que não nasceu (impossível na prática — o honesto cai aqui):
        // dorme o teto em vez de girar
        if teto_ms > 0 {
            std::thread::sleep(Duration::from_millis(teto_ms as u64));
        }
        return;
    }
    unsafe {
        libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, teto_ms);
    }
    // 1.0-108 — o fd MORTO sai do poll e do chão NA HORA (POLLERR/POLLHUP/
    // POLLNVAL: continuar listando o fd morto seria spin — o poll retorna
    // imediato com o erro para sempre)
    for fd in &fds {
        if fd.revents & (libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) == 0 {
            continue;
        }
        if fd.fd == pipe_r {
            WAKE_R.store(-1, Ordering::SeqCst);
            eprintln!(
                "elite-daemon: o fd do self-pipe morreu no poll ({}) — desregistrado (o handler de sinal segue calado)",
                fd.revents
            );
        } else if fd.fd == vigia {
            WATCH_FD.store(-1, Ordering::SeqCst);
            eprintln!(
                "elite-daemon: o fd da vigia inotify morreu no poll ({}) — desregistrado (o SIGHUP/EPIPE seguem)",
                fd.revents
            );
        }
        unsafe {
            libc::close(fd.fd);
        }
    }
    // drena o pipe (o próximo evento acha a mesa limpa)
    let pipe_r = WAKE_R.load(Ordering::SeqCst);
    if pipe_r >= 0 {
        let mut buf = [0u8; 64];
        while unsafe { libc::read(pipe_r, buf.as_mut_ptr().cast(), 64) } > 0 {}
    }
    // drena a vigia (o loop de cima re-julga wayland_pronto — o juiz)
    let vigia = WATCH_FD.load(Ordering::SeqCst);
    if vigia >= 0 {
        let mut buf = [0u8; 8192];
        while unsafe { libc::read(vigia, buf.as_mut_ptr().cast(), 8192) } > 0 {}
    }
}

fn usage() -> &'static str {
    "uso: elite-daemon [session | supervise | game-notify | desk … | suspend | doctor | --help | --version]\n\
     \x20 o orquestrador ÚNICO da sessão (1.0-107 — o daemon LIVRE de varredura\n\
     \x20 de processos: o modo de jogo é o MANUAL do craft-game, o daemon só\n\
     \x20 publica o estado que o CLI reporta no bus da sessão).\n\
     \x20 session = E135 — O LANÇADOR ÚNICO da sessão gráfica (clientes de\n\
     \x20 display + residentes com o gate de posse; o craft-bars shell vira\n\
     \x20 `exec elite-daemon session` — zero /bin/sh residente) e os ouvidores\n\
     \x20 de evento (bus.sock + wayland + mpris + áudio + netlink + logind).\n\
     \x20 supervise = o supervisor dos residentes da sessão (swayosd, swaync\n\
     \x20 — respawn com backoff exponencial e teto).\n\
     \x20 game-notify = 1.0-104 — o craft-game CLI reporta o toggle manual: publica\n\
     \x20 o estado REAL (QueryStatus) no bus da sessão e a barra acende o pill\n\
     \x20 do jogo no MESMO instante (o cinto do 30s é a rede, o fio é o gesto).\n\
     \x20 desk N|left|right|left-occupied|right-occupied = o SYNC da mesa\n\
     \x20 (1.0-100 — o rc.xml registra a troca; a dock veste .other-workspace).\n\
     \x20 suspend = 1.0-110 — a PORTA CURTA DO SONO (o verbo SUSPEND no bus da\n\
     \x20 sessão: o daemon trava desacoplado, espera a superfície do lock e\n\
     \x20 chama login1.Manager.Suspend nativo — o caminho do craft-suspend).\n\
     \x20 doctor = 1.0-107.2 — O DIAGNÓSTICO EM 1 COMANDO (o elo craft-doctor é\n\
     \x20 este mesmo binário): julga os invariantes vitais da máquina real —\n\
     \x20 o ambiente Wayland no D-Bus, o bus.sock, o agente Polkit, o dono\n\
     \x20 único das notificações, a tabela /proc/acpi/wakeup, o default do\n\
     \x20 PipeWire e o gamemoded — em <50ms, zero overhead em idle.\n"
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    // 1.0-107.2 — O ELO CRAFT-DOCTOR (o symlink do pacote veste este mesmo
    // binário: o argv0 decide a porta — um arquivo a menos viajando, a
    // mesma face de sempre)
    let argv0 = args.first().map(|s| s.rsplit('/').next().unwrap_or(s));
    if argv0 == Some("craft-doctor") {
        std::process::exit(doctor::run());
    }
    match args.get(1).map(String::as_str) {
        Some("--help") | Some("-h") => {
            print!("{}", usage());
            std::process::exit(0);
        }
        Some("--version") | Some("-V") => {
            println!("elite-daemon {}", VERSION);
            std::process::exit(0);
        }
        // 1.0-107.2 — O DIAGNÓSTICO EM 1 COMANDO: os invariantes vitais
        // da máquina real julgados em <50ms (o elo craft-doctor chega
        // aqui pelo argv0)
        Some("doctor") => {
            std::process::exit(doctor::run());
        }
        // 1.0-107 — O MODO AUTOMÁTICO MORREU COM O WATCHER (a diretriz
        // §6: "--once" era a porta dos testes da varredura de /proc que
        // NÃO existe mais — sem corpo de detecção, a porta vira eco
        // honesto do uso; o gamemoded sobe por D-Bus activation na mão
        // do craft-game `on`, nunca mais por varredura).
        Some("supervise") => match supervise::run() {
            Ok(()) => std::process::exit(0),
            Err(e) => {
                eprintln!("elite-daemon supervise: {}", e);
                std::process::exit(1);
            }
        },
        // 1.0-100 — O CLI DO SYNC DA MESA (audit 99 §4): `elite-daemon
        // desk N|left|right|left-occupied|right-occupied` — o rc.xml
        // chama nos binds de mesa (o Execute ao lado do GoToDesktop/
        // SendToDesktop) e o daemon da sessão REGISTRA a mesa corrente
        // e publica no bus (a dock veste .other-workspace na hora).
        // CORPO CURTO: conecta no bus.sock, manda UM Req, espera o Ack
        // (teto de 1s) e sai — zero residente, zero lock (a lei E30 não
        // tem dono aqui: o sync é mensagem, não vaga).
        Some("desk") => {
            let alvo = args.get(2).map(String::as_str).unwrap_or("");
            let req = match alvo {
                "left" | "right" | "left-occupied" | "right-occupied" => {
                    elite_core::BusReq::DeskStep { dir: alvo.to_string() }
                }
                other => match other.parse::<u32>() {
                    Ok(n) => elite_core::BusReq::DeskSet { to: n },
                    Err(_) => {
                        eprintln!(
                            "uso: elite-daemon desk <N|left|right|left-occupied|right-occupied>"
                        );
                        std::process::exit(2);
                    }
                },
            };
            // o round-trip curto: conecta no bus da sessão, manda o
            // pedido, espera o Ack com teto de 1s e MORRE — zero
            // residente, zero lock. Sem bus (relogin cedo, daemon
            // renascendo) = saída 0 honesta: o sync não pode travar
            // nunca (o GoToDesktop do labwc já fez o feito visível).
            let uid = unsafe { libc::getuid() };
            let sock = elite_core::bus_sock_path(uid);
            let Some((cli, rx)) =
                elite_core::bus::BusClient::connect(&sock, "elite-daemon-desk")
            else {
                std::process::exit(0);
            };
            let _ = cli.send_req(req);
            let teto = std::time::Instant::now() + std::time::Duration::from_millis(1000);
            let mut ok = false;
            while std::time::Instant::now() < teto {
                match rx.recv_timeout(std::time::Duration::from_millis(100)) {
                    Ok(elite_core::BusMsg::Ack { ok: veredito, .. }) => {
                        ok = veredito;
                        break;
                    }
                    Ok(_) => continue, // boas-vindas do frame 0: segue
                    Err(_) => break,   // o fio caiu: o estado publicado decide
                }
            }
            std::process::exit(if ok { 0 } else { 1 });
        }
        // 1.0-110 T3 — A PORTA CURTA DO SONO (o craft-suspend veste ESTA
        // porta: o verbo SUSPEND viaja pelo bus da sessão e o daemon
        // desce o caminho NATIVO — lock desacoplado, superfície mapeada
        // e login1.Manager.Suspend pela conexão COMPARTILHADA, com o
        // fallback systemctl). CORPO CURTO como o desk: manda o pedido,
        // espera o Ack com teto de 3s (a espera da superfície do lock)
        // e MORRE — zero residente, zero lock. Sem bus vivo = queda
        // honesta 1 (o craft-suspend veste o caminho local dele).
        Some("suspend") => {
            let uid = unsafe { libc::getuid() };
            let sock = elite_core::bus_sock_path(uid);
            let Some((cli, rx)) =
                elite_core::bus::BusClient::connect(&sock, "elite-daemon-suspend")
            else {
                eprintln!("elite-daemon suspend: sem bus da sessão — o caminho local do craft-suspend veste (honesto)");
                std::process::exit(1);
            };
            let _ = cli.send_req(elite_core::BusReq::Suspend);
            let teto = std::time::Instant::now() + std::time::Duration::from_millis(3000);
            let mut ok = false;
            while std::time::Instant::now() < teto {
                match rx.recv_timeout(std::time::Duration::from_millis(100)) {
                    Ok(elite_core::BusMsg::Ack { ok: veredito, .. }) => {
                        ok = veredito;
                        break;
                    }
                    Ok(_) => continue,
                    Err(_) => break,
                }
            }
            std::process::exit(if ok { 0 } else { 1 });
        }
        // 1.0-104 — O CLI DO TOGGLE MANUAL (a ordem do dono: o craft-game
        // on/off reporta o PERFIL COMPLETO — governor, DND, inibidor de
        // ocioso — e o ESTADO viaja no fio do elite-daemon: a barra acende
        // o pill roxo no MESMO instante do clique, sem esperar o cinto de
        // 30s do craft-game pill). CORPO CURTO como o desk: conecta no
        // bus.sock COMO CLIENTE, consulta o QueryStatus REAL (gamemode é
        // o juiz de sempre) e PUBLICA o GameMode — zero residente, zero
        // lock (a lei E30 não tem dono aqui: o aviso é mensagem, não
        // vaga). Sem bus vivo = saída 0 honesta (a barra segue com o
        // cinto; o estado é o mesmo, só o timing degrada).
        Some("game-notify") => {
            let uid = unsafe { libc::getuid() };
            let sock = elite_core::bus_sock_path(uid);
            if let Some((cli, _rx)) =
                elite_core::bus::BusClient::connect(&sock, "elite-daemon-game")
            {
                let conn = scan::gm_connect();
                let ativo = scan::gm_status(&conn) == 1;
                cli.publish(&elite_core::BusMsg::GameMode(elite_core::GameModeState {
                    active: ativo,
                    game: None,
                    gpu_performance: ativo,
                }));
            }
            std::process::exit(0);
        }
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
            // 1.0-102 — A PORTEIRA SABE QUEM É: este corpo é a SESSÃO
            // (o único que desce a casa inteira quando o compositor cai
            // — ver fim_da_sessao; o audit 102: o Broken pipe do fio
            // Wayland não podia mais deixar o dono vivo no lock).
            PORTA_SESSION.store(true, Ordering::SeqCst);
            // 2.0 — O NÚCLEO VIVO: o bus.sock (a barra e a dock ganham
            // o fio), o cliente Wayland NATIVO (o craft-toplevel.c morre
            // — janelas, vigília e trava automática da casa), o MPRIS
            // (zero playerctl-polling) e o roteador de áudio Rust (o
            // python craft-audio-route morre com seu NameError herdado)
            // 1.0-100 — OS LOCKS ÓRFÃOS DE /tmp SAEM PRIMEIRO (o audit
            // 99 §2: `/tmp/elite-daemon.lock` e o fallback da sessão
            // parados no chão entre relogins — flock é estado do inode,
            // o arquivo fica): a varredura flock-gated roda ANTES do
            // colhe_relogin (nenhum filho de vaga nasceu — a corrida de
            // µs não existe; o dono vivo de qualquer lock é PULADO pelo
            // portão do flock, ele nem sente a varredura).
            let orfos = supervise::limpa_locks_orfos();
            if orfos > 0 {
                eprintln!(
                    "elite-daemon session: {orfos} lock(s) órfão(s) de /tmp saíram \
                     (flock livre + PID ausente em /proc — o audit 99 §2 morre)"
                );
            }
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
            // 1.0-107.2 — O GUARDA DO BUS: o pretendente com a porta
            // ocupada sai 0 ANTES do liga_bus (o bind de era da 2ª
            // instância matava o socket do dono PELO PATH — o
            // craft-doctor nomeou o réu no smoke do Canal)
            if supervise::guarda_bus() {
                std::process::exit(0);
            }
            nucleo::liga_bus();
            wayland::start();
            // 1.0-106 — o MPRIS nasce com o CENSO INICIAL (o pill acende no
            // frame 0 de quem já tocava) e o BlueZ entra com o Powered
            // consultado NO ARRANQUE (o ícone da barra nasce com a verdade)
            std::thread::spawn(mpris::thread);
            std::thread::spawn(audio::thread_subscribe);
            std::thread::spawn(|| audio::rodada("start"));
            std::thread::spawn(thread_netlink);
            std::thread::spawn(bluetooth::thread);
            // 1.0-110 T1 — A REDE NO FIO (o ícone da barra reage ao
            // plug/unplug <500ms PELO EVENTO do NM — o belt de 5s de
            // nmcli da barra morre na fonte: o daemon é o único ouvidor)
            std::thread::spawn(network::thread);
            // E190 T4 — O AUTOMOUNT NO FIO (o udiskie residente morre: o
            // pen drive monta no EVENTO do UDisks2 — o mesmo gesto do
            // áudio e da rede: a thread dorme no iterator do bus)
            std::thread::spawn(discos::thread);
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
                 nativo + mpris + áudio + netlink som/drm + bluetooth + rede \
                 NM por evento + discos UDisks2 por evento + logind \
                 sono/unlock + wake-guard pré-sono \
                 + re-aplicação do monitor do boot)"
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
            // 1.0-107 — O CORPO NÚ (o daemon_loop de era) MORREU COM O
            // MODO AUTOMÁTICO (a diretriz §6: "deixando o daemon livre
            // de varredura de processos"): SEM porta nomeada não há
            // ofício — o eco é o USO com a verdade (a sessão é
            // `elite-daemon session`, o supervisor é `supervise`).
            eprintln!("{}", usage());
            std::process::exit(2);
        }
    }
}

// ── 1.0-107 — O DEBOUNCE DE ERA MORREU COM O MODO AUTOMÁTICO (o juiz
// das transições do watcher de /proc; o manual do dono notifica NA HORA
// no clique do craft-game — não há transição fantasma para julgar) ──

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

pub(crate) fn agora_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// o fork pontual por evento: stdin/stdout/stderr nulos (nada de filho
/// falando no papel do daemon).
/// 1.0-100 — A COVEIRA (o audit 99 §1 fotografou DOIS
/// `[craft-display] <defunct>` pendurados como filhos DESTE daemon): o
/// spawn sem colheita deixa o filho morto esperando wait(2) para
/// sempre — zumbi no ps de cada boot. A thread dedicada colhe o exit
/// ANTES de morrer (o mesmo gesto da dock E146/C): o processo curto
/// nasce, roda, é COLHIDO — o ps da sessão fica limpo.
fn dispara(comando: &str, args: &[&str]) {
    let cmd = comando.to_string();
    let owned: Vec<String> = args.iter().map(|a| a.to_string()).collect();
    // 1.0-103 — if let (a clippy-lente): o braço vazio do Err não paga match
    if let Ok(mut filho) = Command::new(&cmd)
        .args(&owned)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        // a COVEIRA: o wait acontece NUMA thread de 1 filho — o
        // processo curto é colhido na hora da morte e o zumbi
        // <defunct> do audit 99 não nasce mais (o daemon não
        // trava esperando: o spawn segue pontual por evento)
        std::thread::Builder::new()
            .name("elite-coveira".into())
            .spawn(move || {
                let _ = filho.wait();
            })
            .ok();
    } // o fork falhou: evento perdido, papel honesto acima
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

/// 1.0-102 — O FIM DA SESSÃO NO GESTO DO COMPOSITOR (a cura central do
/// audit 102): ao labwc encerrar, o fio Wayland deste daemon morre com
/// EPIPE/EOF — e o corpo da sessão desce JUNTO, GRACIOSAMENTE:
///   1. STOP acende (o supervisor da sessão vê no ciclo de ≤1s: SIGTERM
///      aos filhos NOSSOS via handle — craft-bar-rs, craft-dock-rs,
///      swayosd-server, agente polkit, wallpaper, o motor de jogo — e
///      os COLHE com wait);
///   2. o sinal por COMM é o cinto imediato (o filho que nasceu fora do
///      mapa do supervisor na janela da queda também é alcançado);
///   3. o vigia de teto: se algum filho recusar morrer e o supervisor
///      pendurar no wait, ESTE processo finaliza sozinho (exit 0) — o
///      chão nunca fica com o dono morto-vivo segurando a trava.
///
/// O modo NÃO-session (jogo puro, supervise) segue o comportamento de
/// sempre: o fio morre honesto e o corpo segue vivo para as outras
/// portas (o motor de jogo é vaga supervisionada da sessão — quem o
/// colhe é o STOP do pai).
pub(crate) fn fim_da_sessao(motivo: &str) {
    if !PORTA_SESSION.load(Ordering::SeqCst) {
        // o corpo de sempre (modo jogo/supervise): o fio morre honesto,
        // o daemon segue para as outras portas
        eprintln!(
            "elite-daemon: {motivo} — o fio morre honesto (o supervisor reergue a sessão)"
        );
        return;
    }
    eprintln!(
        "elite-daemon: {motivo} — o COMPOSITOR caiu: a sessão desce INTEIRA e LIMPA \
         (STOP → filhos encerrados → session.lock fora do chão → exit 0 — 1.0-102)"
    );
    STOP.store(true, Ordering::SeqCst);
    // 1.0-107.2 — A CAMPAINHA DIRETA (o STOP nasce de uma THREAD, não
    // de um sinal: sem o byte do pipe, o supervisor dormindo no poll(2)
    // esperaria até o teto — o STOP ACORDA quem espera)
    wake_escreve();
    // o cinto imediato por comm (o comm do agente lxqt é cortado pelo
    // kernel em 15: 'lxqt-policykit-' — TASK_COMM_LEN de sempre)
    let n = sinal_para_comms(
        &[
            "craft-bar-rs",
            "craft-dock-rs",
            "swayosd-server",
            "lxqt-policykit-",
            "swaybg",
            "craft-display",
        ],
        libc::SIGTERM,
    );
    eprintln!(
        "elite-daemon: fim da sessão — SIGTERM aos filhos gerenciados ({n} sinalizado(s) por comm; o supervisor colhe os NOSSOS pelo handle no ciclo seguinte)"
    );
    // o vigia de teto: o supervisor (STOP no ciclo — acordado pelo byte
    // do pipe) encerra os filhos, remove o session.lock e sai 0; se um
    // filho recusar morrer e o wait dele pendurar o supervisor, o teto
    // de 8s finaliza o processo NA MESMA SAÍDA (exit 0 — o chão nunca
    // fica retido)
    std::thread::Builder::new()
        .name("elite-fim-sessao".into())
        .spawn(|| {
            std::thread::sleep(Duration::from_secs(8));
            eprintln!(
                "elite-daemon: o teto do fim de sessão bateu (8s) — exit 0 com o flock \
                 solto (o lock do chão saiu pelo caminho do supervisor ou sai no relogin)"
            );
            std::process::exit(0);
        })
        .ok();
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
/// 1.0-110 T5 — O DESPERTAR SEQUENCIAL E DEDUPLICADO: o acordar de uma
/// suspensão DISPARA Unlock E PrepareForSleep(false) quase NO MESMO
/// instante (o despertar de era nascia DUAS vezes — cada um com os DOIS
/// forks de recover+apply soltos ao vento: a corrida de modo de era era
/// uma roleta: o apply lia o wlr-randr ANTES do recover religar o link
/// e o 60 Hz voltava por sorte). A janela de 3s DEDUPLICA o gêmeo e a
/// sequência é LEI dentro da thread: wlopm → assento → recover
/// BLOQUEANTE (status()) → SÓ ENTÃO apply (o modo confere DEPOIS do
/// link re-treinado, nunca na carona de um fork solto).
fn despertar() {
    // 1.0-100 — A ORDEM DO DESPERTAR (o audit 99 §4: ao acordar do
    // suspend às 20:35 a sessão caiu para o greeter do SDDM — o
    // despertar precisa RELIGAR o vídeo sem nunca derrubar o display
    // Wayland nem o labwc):
    //   1º  wlopm --on '*'  — o DPMS volta ANTES de qualquer mudança de
    //       modo: wlr-randr contra saída desligada no-opa/falha e o
    //       apply da casa perderia a rodada;
    //   2º  o BACKOFF do link (1.0-107 — a ordem do dono, palavra por
    //       palavra: "reativar explicitamente as saídas… com pequeno
    //       backoff de estabilização de link HDMI/DP para GPU AMD"):
    //       o amdgpu precisa do assento entre o DPMS acordar e o
    //       re-treino do link — o recover correndo COLADO no wlopm
    //       nascia antes da saída aceitar o modo (o "DisplayPort sem
    //       sinal de entrada" pós-unlock de era);
    //   3º  craft-display recover + apply — o ciclo off→1s→on COM O
    //       MODO PERSISTIDO por saída viva (E106/5a), varredura
    //       DINÂMICA do wlr-randr (zero hardcoded) e o guard de 10s
    //       casa UM dono por veredito com as outras redes;
    //   4º  O LOCK DE PÉ (1.0-107: "garantir que o hyprlock esteja
    //       ativo e recebendo foco de teclado para desbloqueio
    //       imediato"): o hyprlock sobrevive ao freeze pelo protocolo
    //       ext-session-lock-v1 (o foco de teclado é DELE por lei do
    //       compositor); se ele MORREU no sono (crash raro), o
    //       --if-needed renasce NA HORA — a tela nunca acorda nua;
    //   5º  reseta_idle — o tempo DORMIDO não é inatividade (o lock na
    //       cara do dono logo após acordar era a mentira do contador).
    // NENHUM destes gestos mata o compositor: wlopm fala o protocolo
    // wlr-output-power (estado de DPMS), o apply fala wlr-randr (modos)
    // — os dois são clientes Wayland comuns; o labwc continua de pé.
    // 1.0-110 T5 — A DEDUPLICAÇÃO: Unlock + PrepareForSleep(false) são
    // O MESMO acordar (chegam colados no despertar do sono); a janela
    // de 3s colhe UM gesto só — o gêmeo que chegar no intervalo é eco.
    {
        static ULTIMO: std::sync::Mutex<Option<std::time::Instant>> = std::sync::Mutex::new(None);
        let mut ultimo = ULTIMO.lock().unwrap();
        if let Some(t) = *ultimo {
            if t.elapsed() < Duration::from_secs(3) {
                eprintln!(
                    "elite-daemon: o despertar JÁ corre há {:.1}s (Unlock+PrepareForSleep são O MESMO acordar — o gêmeo é eco, 1.0-110)",
                    t.elapsed().as_secs_f64()
                );
                return;
            }
        }
        *ultimo = Some(std::time::Instant::now());
    }
    std::thread::spawn(|| {
        dispara("wlopm", &["--on", "*"]);
        // o assento do link DP/HDMI do amdgpu (a GPU precisa dele entre
        // o DPMS acordar e o re-treino do modo)
        std::thread::sleep(Duration::from_millis(800));
        // 1.0-110 T5 — A SEQUÊNCIA É LEI (recover BLOQUEANTE ANTES do
        // apply: de era os dois forks soltos corriam em paralelo e o
        // apply lia o modo do link AINDA morto — a corrida de modo de
        // era era uma roleta; o recover termina, o link está re-treinado,
        // SÓ ENTÃO o apply veste o arranjo do dono)
        let _ = Command::new("/usr/local/bin/craft-display")
            .arg("recover")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        dispara("/usr/local/bin/craft-display", &["apply"]);
        // 1.0-107 — A REDE REAVALIADA NO ACORDAR (a ordem do dono: "no
        // evento PrepareForSleep(false)… o estado de conectividade
        // seja reavaliado SEM travar o módulo da barra"): o check é um
        // fork PONTUAL por evento (nunca residente — a lei E135), o
        // NetworkManager re-avalia os perfis e o estado publicado no
        // bus veste o ícone da barra NO CICLO dela (o módulo nunca
        // espera o nmcli — a fila é do daemon).
        dispara("nmcli", &["networking", "connectivity", "check"]);
        // o lock de pé no acordar (o hyprlock vivo segue vivo; o morto
        // no sono renasce — a tela nunca acorda sem a trava)
        if !supervise::comm_vivo("hyprlock") {
            eprintln!(
                "elite-daemon: o hyprlock não sobreviveu ao sono — o --if-needed renasce o lock NA HORA (a tela nunca acorda nua)"
            );
            idle::trava();
        }
        // E190 T3 — A MARCA DE PÓS-SONO cobre o acordar que só viu o
        // Unlock (o sinal PrepareForSleep do logind PERDIDO no limbo:
        // sem a marca o áudio seguia no sequestro do HDMI/DP do monitor
        // pós-sono; com ela a foto pré-sono veste o default de volta)
        if idle::sono_recente() {
            eprintln!(
                "elite-daemon: a marca de pós-sono está FRESCA — o áudio veste a foto pré-sono (E190 T3)"
            );
            audio::resume();
        }
        wayland::reseta_idle();
    });
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
                // 1.0-110 T5 — O ENOBUFS RESSINCRONIZA (o kernel descarta
                // a fila multicast de uevents quando o buffer enche — o
                // sono de 500ms de era DEVOLVIA o estado VELHO: o monitor
                // plugado na janela perdida ficava sem o arranjo até o
                // PRÓXIMO evento): o estado completo é REFEITO (a rodada
                // de áudio + o apply do display) com o guard de 800ms da
                // casa — a rajada de resyncs nunca vira fork-storm
                let enobufs = n < 0 && *libc::__errno_location() == libc::ENOBUFS;
                if enobufs {
                    let agora = agora_ms();
                    if agora.saturating_sub(last_drm) > 800 {
                        last_drm = agora;
                        eprintln!(
                            "elite-daemon: netlink ENOBUFS — a fila do kernel transbordou, o estado é RESSINCRONIZADO (áudio + display, 1.0-110)"
                        );
                        std::thread::spawn(|| audio::rodada("enobufs"));
                        dispara("/usr/local/bin/craft-display", &["apply"]);
                    }
                }
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

// ── 1.0-107 — O MOTOR DE JOGO DE ERA MORREU INTEIRO (a diretriz §6:
//    a detecção /proc PORTA 5 (janelas steam_app_*), o freto do condvar,
//    o parse do pp_power_profile_mode, o EPP/GPU dinâmico e o
//    daemon_loop INTEIRO saem com o modo automático — o daemon é o
//    orquestrador da SESSÃO, nunca um detetive de processos; o perfil
//    de jogo (CPU governor performance + GPU amd_performance_level
//    high) é o gamemoded NATIVO na mão do craft-game `on`) ──────────

#[cfg(test)]
mod tests {
    use super::*;

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

    #[test]
    fn e1072_o_self_pipe_toca_e_acorda_na_hora() {
        // 1.0-107.2 — a CAMPAINHA do kernel: o byte escrito acorda o
        // poll NA HORA — teto de 5.000ms de prova: sem o byte o poll
        // dorme os 5s inteiros; com ele, volta em microssegundos. O
        // SIGCHLD de filhos ALHEIOS dos testes paralelos pode escrever
        // o PRÓPRIO byte (é o contrato vivo do handler!) — por isso a
        // prova é o CAMINHO CURTO com byte na mesa, nunca o caminho
        // longo sem (este último é da vida real, sem paralelos).
        instala_sinais();
        wake_escreve();
        wake_escreve(); // dois bytes, UMA mesa (o dreno varre tudo)
        let inicio = std::time::Instant::now();
        espera_evento(5_000);
        let custo = inicio.elapsed().as_millis();
        assert!(
            custo < 4_500,
            "o byte acordou o poll na hora ({custo}ms — sem o byte seriam 5.000)"
        );
    }

    #[test]
    fn e1072_a_vigia_do_socket_nasce_e_calada() {
        // sem WAYLAND_DISPLAY: a vigia nem nasce (o fd segue -1)
        std::env::remove_var("WAYLAND_DISPLAY");
        liga_vigia_socket();
        assert!(WATCH_FD.load(Ordering::SeqCst) < 0, "sem compositor esperado, sem vigia");
        // com um dir de verdade: a vigia nasce (e morre com o teste)
        let dir = std::env::temp_dir().join(format!("elite-prova-vigia-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::env::set_var("XDG_RUNTIME_DIR", &dir);
        std::env::set_var("WAYLAND_DISPLAY", "labwc-0");
        liga_vigia_socket();
        let fd = WATCH_FD.load(Ordering::SeqCst);
        assert!(fd >= 0, "com runtime dir de verdade, a vigia nasce");
        // o evento de verdade: o NOME sumindo do chão acorda o poll — e
        // a leitura do inotify devolve o buffer com o nome de dentro
        let socket = dir.join("labwc-0");
        std::fs::write(&socket, b"").ok();
        std::thread::sleep(Duration::from_millis(50));
        std::fs::remove_file(&socket).ok();
        std::thread::sleep(Duration::from_millis(50));
        let mut buf = [0u8; 256];
        let n = unsafe { libc::read(fd, buf.as_mut_ptr().cast(), 256) };
        assert!(n > 0, "o IN_DELETE do socket chega no inotify da vigia");
        let eventos = String::from_utf8_lossy(&buf[..n as usize]);
        assert!(eventos.contains("labwc-0"), "o nome do socket viaja no evento (achei: {eventos:?})");
        unsafe { libc::close(fd) };
        WATCH_FD.store(-1, Ordering::SeqCst);
        std::env::remove_var("WAYLAND_DISPLAY");
        std::env::remove_var("XDG_RUNTIME_DIR");
        let _ = std::fs::remove_dir(&dir);
    }
}
