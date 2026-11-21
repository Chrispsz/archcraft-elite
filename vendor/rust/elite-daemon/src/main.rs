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
// NÃO É DEGRAU DESTA v2: o craft-display watch e as barras waybar/dock
// SEGUIEM no craft-bars (a waybar só RECEBE o sinal daqui; a dock é
// outro corpo — nenhum half-promise de unificação pela metade).
//
// Custos medidos no desenho: zero fork por tick (a varredura é read(2)
// de /proc); o D-Bus é conexão PERSISTENTE (não abre por chamada); o
// notify-send só nas TRANSIÇÕES confirmadas (zero toast de fantasma).
use std::collections::HashMap;
use std::os::unix::fs::MetadataExt;
use std::os::unix::io::AsRawFd;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

mod scan;
mod supervise;

const VERSION: &str = "2.0.0";

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
    "uso: elite-daemon [--once | supervise | --help | --version]\n\
     \x20 o detector de jogo unificado (E132) — registra a família no GameMode\n\
     \x20 por D-Bus nativo, aplica o EPP performance na sessão de jogo, sinaliza\n\
     \x20 a waybar (SIGRTMIN+8) e notifica com debounce de 3s; instância única\n\
     \x20 por flock; SIGTERM des-registra, devolve o EPP e sai limpo.\n\
     \x20 --once = uma rodada (a porta dos testes).\n\
     \x20 supervise = o supervisor dos residentes da sessão (swaync, udiskie,\n\
     \x20 swayosd, craft-audio-route — respawn com backoff de 2s).\n"
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
    let uid = unsafe { libc::getuid() };
    let sig = unsafe { libc::SIGRTMIN() } + 8;
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

    let mut held: HashMap<i32, String> = HashMap::new();
    let mut retire = 0u32;
    let conn = scan::gm_connect();

    // E132 — o estado da SESSÃO de jogo (a máquina das transições):
    // ativa = jogo registrado OU QueryStatus 1 (o manual do dono conta);
    // confirmada = os 3s do debounce passaram com o modo ATIVO (o fim de
    // uma sessão confirmada é notícia; pulo transitório não é).
    let mut sessao_ativa = false;
    let mut iniciada_em = 0u64;
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
            eprintln!(
                "elite-daemon: sessão de jogo ATIVA — EPP performance em {} cpu(s) writável(is) + {} waybar(s) avisada(s)",
                n,
                sinal_waybar()
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
            eprintln!(
                "elite-daemon: sessão de jogo FIM — EPP balance_performance em {} cpu(s) writável(is) + {} waybar(s) avisada(s){}",
                n,
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
                eprintln!(
                    "elite-daemon: SIGTERM — {} jogo(s) liberado(s), EPP devolvido em {} cpu(s)",
                    held.len(),
                    n
                );
            }
            return Ok(());
        }
        std::thread::sleep(std::time::Duration::from_secs(5));
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
