// ELITE · elite-daemon v1 (E131) — o núcleo do craft-game watch como
// serviço NATIVO. A ordem do dono ("espremer o limão"): os loops
// residentes de shell viram UM daemon em Rust — zero fork por tick, a
// leitura direta de /proc, o D-Bus nativo com o GameMode.
//
// ESCOPO HONESTO DA v1 (o degrau é incrementado, a lei AGENTS.md §2):
//   · a DETECÇÃO de jogo (a família ERE do comm + a porta do exe Steam
//     em steamapps/common — o molde do craft-game, traduzido 1:1);
//   · o REGISTRO/DESREGISTRO no GameMode por D-Bus NATIVO (zbus) — o
//     reaper do gamemoded continua sabendo da morte do jogo (o pid é o
//     DELE — zero estado duplicado, a mesma física do watch bash);
//   · instância ÚNICA por flock de arquivo (a lei E30 — o 2º sai 0);
//   · --once: UMA rodada de varredura (a porta dos testes — a suíte
//     julga a decisão sem daemon residente);
//   · SIGTERM/SIGINT: unregister de tudo e saída limpa.
// NÃO É DEGRAU DESTA v1: a troca dos daemons bash VIVOS (o craft-bars
// continua spawnando o craft-game watch; este bin chega NO PACOTE como
// a fundação e o corte do bash é o degrau seguinte, com a suíte
// portando os contratos — nunca pela metade).
//
// Custos medidos no desenho: zero fork por tick (a varredura é read(2)
// de /proc); o D-Bus é conexão PERSISTENTE (não abre por chamada).
use std::collections::HashMap;
use std::os::unix::io::AsRawFd;
use std::path::PathBuf;

mod scan;

const VERSION: &str = "1.0.0";

fn usage() -> &'static str {
    "uso: elite-daemon [--once | --help | --version]\n\
     \x20 o detector de jogo unificado (E131) — registra a família no GameMode\n\
     \x20 por D-Bus nativo; instância única por flock; SIGTERM des-registra\n\
     \x20 e sai limpo. --once = uma rodada (a porta dos testes).\n"
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
                println!("jogo: pid {} comm {} exe {}", p.pid, p.comm, p.exe);
            }
            println!("rodada única: {} jogo(s) da família", achados.len());
            std::process::exit(0);
        }
        Some(other) => {
            eprintln!("elite-daemon: porta desconhecida '{}'\n{}", other, usage());
            std::process::exit(2);
        }
        None => {
            // modo daemon: o loop de 5s + flock + sinais. (v1 fundação —
            // a integração com o supervisor vem no degrau do corte bash)
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

    let mut held: HashMap<i32, String> = HashMap::new();
    let mut retire = 0u32;
    let conn = scan::gm_connect();
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
                    held.insert(p.pid, p.comm.clone());
                }
            }
        }
        // a aposentadoria do daemon ocioso (a física do watch bash: 2
        // rodadas sem jogo e sem manual — o gamemoded renasce por D-Bus)
        if held.is_empty() && scan::gm_status(&conn) == 0 {
            retire += 1;
        } else {
            retire = 0;
        }
        if retire >= 2 {
            scan::gm_quit(&conn);
            retire = 0;
        }
        std::thread::sleep(std::time::Duration::from_secs(5));
    }
}
