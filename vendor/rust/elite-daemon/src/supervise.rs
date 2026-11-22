// ELITE · elite-daemon — o SUPERVISOR DOS RESIDENTES (E132→E135). A ordem
// do dono ("espremer o limão") chega aos daemons de sessão que o craft-bars
// ressuscitava por pgrep a cada 5s: os residentes PUROS viram FILHOS
// DIRETOS deste processo — try_wait(2) nativo, respawn com backoff de 2s
// por filho, stdout+stderr no MESMO bars.log da casa.
//
// E135 — O GATE DE POSSE (a cura do loop 809 do dump 101339): o swaync
// exit 1 ("An instance is already running!") era RELANÇADO às cegas a
// cada 2s — 809 mortes no bars.log de UM boot. O gate é DUPLO e cada
// respawn o atravessa antes de qualquer fork:
//   1. flock exclusivo em $XDG_RUNTIME_DIR/elite/resident-<nome>.lock —
//      a vaga é de quem segura a trava; o irmão do daemon não duplica;
//   2. o NOME no session bus (a gramática nova `nome::bus::comando`):
//      swaync dono de org.erikreider.swaync.cc — se o nome TEM dono
//      (instância lançada por fora — o craft-bars velho, o dono à mão),
//      A VAGA É ADOTADA: nenhum spawn, zero morte, zero relança.
// A adoção morre quando o dono morre: o próximo ciclo tenta a trava,
// o nome ficou livre e a casa cria o filho dela (a supervisão assume).
//
// ESCOPO HONESTO: NÃO moram aqui o craft-game watch (nativo do próprio
// elite-daemon — modo game), nem o craft-display watch, nem a waybar/
// dock/toplevel (clientes de display com gate próprio — nenhum
// half-promise). O conf /usr/local/share/elite/daemon.conf sobrepõe a
// lista DEFAULT quando existe (um residente por linha; `nome::comando`
// ou `nome::bus::comando`; linhas # e vazias ignoradas).
use std::io;
use std::os::unix::io::AsRawFd;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

/// a fila DEFAULT — os residentes PUROS do craft-bars (sem gate de
/// display): (nome, comando, nome no session bus que prova a posse).
/// E135 — o craft-audio-route SAI da fila: roteador de áudio vira
/// DISPARO POR EVENTO (o netlink uevent de som dispara um `--once` —
/// residente em python na sessão é a ordem do dono que morre).
pub const RESIDENTES_DEFAULT: &[(&str, &str, Option<&str>)] = &[
    (
        "swaync",
        "swaync",
        Some("org.erikreider.swaync.cc"),
    ),
    ("udiskie", "udiskie --automount --notify --no-tray", None),
    ("swayosd", "swayosd-server", None),
];

/// E135 — os CLIENTES DE DISPLAY da sessão: a porta `session` do daemon
/// é O LANÇADOR ÚNICO (o craft-bars shell vira `exec elite-daemon
/// session` — zero /bin/sh residente, o réu dos 8 do dump 101339
/// morre). Mesma vaga, mesmo gate, mesmo bars.log; o $HOME no comando
/// é expandido no spawn (a fila é genérica, o home do dono não).
pub const CLIENTES_DISPLAY: &[(&str, &str)] = &[
    ("toplevel", "craft-toplevel"),
    (
        "waybar",
        "waybar -c $HOME/.config/waybar/config.top -s $HOME/.config/waybar/style.top.css",
    ),
    ("dock", "craft-dock-rs"),
    ("idle", "craft-idle start"),
    ("policykit", "lxqt-policykit-agent"),
];

const CONF_PATH: &str = "/usr/local/share/elite/daemon.conf";
const BACKOFF: Duration = Duration::from_secs(2);

pub struct Residente {
    pub nome: String,
    pub comando: String,
    /// E135 — o nome no session bus que prova a posse (None = só flock).
    pub bus: Option<String>,
}

/// E132/E135 — o parser do daemon.conf (função PURA, a porta dos testes).
/// Formato: um residente por linha `nome::comando` ou
/// `nome::bus-name::comando` (split nas duplas ':' na ordem; o comando é
/// o resto cru, tokens por espaço — SEM shell, sem aspas). Linhas vazias,
/// só-espaço e comentários '#' ignoradas; `KEY=VALUE` sem '::' não vira
/// residente (porta futura, nomeada honesta).
pub fn parse_conf(texto: &str) -> Vec<Residente> {
    let mut out = Vec::new();
    for linha in texto.lines() {
        let linha = linha.trim();
        if linha.is_empty() || linha.starts_with('#') {
            continue;
        }
        let Some((nome, resto)) = linha.split_once("::") else {
            continue; // KEY=VALUE ou ruído: não é residente
        };
        let nome = nome.trim();
        // E135 — a 2ª dupla ':' nomeia o bus (o gate de posse); sem ela o
        // resto é TODO o comando (a gramática velha segue inteira)
        let (bus, comando) = match resto.split_once("::") {
            Some((bus, cmd)) => (Some(bus.trim().to_string()), cmd.trim().to_string()),
            None => (None, resto.trim().to_string()),
        };
        if nome.is_empty() || comando.is_empty() {
            continue;
        }
        out.push(Residente {
            nome: nome.to_string(),
            comando,
            bus,
        });
    }
    out
}

/// E135 — a DECISÃO DE POSSE (função PURA, a porta dos testes). O gate é
/// duplo e a ordem importa: o nome no bus prova quem SERVE a sessão (a
/// instância do craft-bars velho ou do dono à mão é DONA legítima) e a
/// trava prova quem a casa já escolheu; posse de outro = ADOTA (nunca
/// relança por cima — o loop 809 morre aqui).
pub enum Posse {
    /// a casa pode spawnar (trava livre E nome sem dono)
    Nossa,
    /// instância viva de fora (nome com dono OU trava de irmão): adota
    Adotada,
}

pub fn decide_posse(nome_tem_dono: bool, trava_livre: bool) -> Posse {
    if nome_tem_dono || !trava_livre {
        Posse::Adotada
    } else {
        Posse::Nossa
    }
}

/// a lista viva: o conf da casa quando existe e tem residentes; senão o
/// DEFAULT (o mesmo critério de "presente" do craft-bars — o arquivo
/// lido é a fonte única).
fn fila_residentes() -> Vec<Residente> {
    if let Ok(texto) = std::fs::read_to_string(CONF_PATH) {
        let r = parse_conf(&texto);
        if !r.is_empty() {
            return r;
        }
    }
    RESIDENTES_DEFAULT
        .iter()
        .map(|(n, c, b)| Residente {
            nome: (*n).to_string(),
            comando: (*c).to_string(),
            bus: (*b).map(str::to_string),
        })
        .collect()
}

/// o papel da casa: $XDG_CACHE_HOME/elite/bars.log (ou ~/.cache/...) —
/// o MESMO arquivo do craft-bars (uma prova forense só, teto lá).
fn log_path() -> PathBuf {
    let base = std::env::var("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into())).join(".cache")
        });
    base.join("elite/bars.log")
}

/// E135 — o dir das travas por residente: $XDG_RUNTIME_DIR/elite (RAM —
/// a lei do dono: caches de sessão moram em /run/user/$UID/).
fn run_dir() -> PathBuf {
    std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
        .join("elite")
}

/// E135 — o gate do nome no session bus: NATIVO (zbus, conexão
/// persistente — o mesmo cliente do GameMode, zero fork de busctl).
/// Sem session bus (sandbox de teste, container) o gate devolve false
/// e a trava sozinha decide — honesto nos DOIS mundos.
fn nome_tem_dono(conn: &Option<zbus::blocking::Connection>, bus: &str) -> bool {
    let Some(c) = conn.as_ref() else { return false };
    let Ok(p) = zbus::blocking::Proxy::new(
        c,
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
    ) else {
        return false;
    };
    p.call::<_, _, bool>("NameHasOwner", &(bus)).unwrap_or(false)
}

/// E135 — a trava da vaga: LOCK_EX|LOCK_NB no arquivo resident-<nome>.
/// Ok(dir de trava) = a vaga é NOSSA; Err = irmão vivo (ADOTA).
fn tenta_trava(nome: &str) -> io::Result<std::fs::File> {
    let dir = run_dir();
    std::fs::create_dir_all(&dir)?;
    let f = std::fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(dir.join(format!("resident-{}.lock", nome)))?;
    let rc = unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if rc != 0 {
        return Err(io::Error::new(
            io::ErrorKind::WouldBlock,
            "trava em posse de irmão",
        ));
    }
    Ok(f)
}

/// o spawn: stdin /dev/null, stdout+stderr em APPEND no bars.log
/// (tokens por espaço — SEM shell no meio; o parser segue o contrato).
/// E135 — o $HOME inicial de cada token é expandido (a fila de display
/// é genérica; nenhum sh no meio para expandir por nós).
fn lanca(comando: &str, log: &PathBuf) -> io::Result<Child> {
    let home = std::env::var("HOME").unwrap_or_default();
    let partes: Vec<String> = comando
        .split_whitespace()
        .map(|t| {
            if let Some(resto) = t.strip_prefix("$HOME") {
                format!("{}{}", home, resto)
            } else {
                t.to_string()
            }
        })
        .collect();
    let mut it = partes.iter();
    let prog = it.next().cloned().unwrap_or_default();
    let args: Vec<&str> = it.map(String::as_str).collect();
    let f = std::fs::OpenOptions::new().create(true).append(true).open(log)?;
    Command::new(prog)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::from(f.try_clone()?))
        .stderr(Stdio::from(f))
        .spawn()
}

struct Vaga {
    res: Residente,
    filho: Option<Child>,
    /// E135 — a trava da vaga SEGURA enquanto o filho nosso vive (a
    /// prova de posse que o outro processo vê; solta quando ele morre).
    trava: Option<std::fs::File>,
    /// o instante da MORTE (ou do arranque recusado) — o backoff de 2s
    /// conta daqui (um respawn por filho, nunca uma rajada).
    desde: Instant,
    /// o arranque inicial já correu: da morte em diante é TODO respawn
    /// com backoff (a 1ª subida não espera — a sessão quer a fila no ar).
    nasceu: bool,
    /// binário ausente no sistema: sem respawn eterno de fantasma.
    ausente: bool,
}

/// E132 — a porta `supervise`: SÓ os residentes puros (a compat dos
/// rigs que chamam o daemon direto).
pub fn run() -> Result<(), String> {
    supervisa(
        "/tmp/elite-daemon-supervise.lock",
        fila_residentes(),
        "supervise",
    )
}

/// E135 — a porta `session`: O LANÇADOR ÚNICO da sessão gráfica — os
/// clientes de display (toplevel, waybar, dock, idle, polkit) + os
/// residentes puros, todos na MESMA vaga com o MESMO gate de posse.
/// O craft-bars shell vira `exec elite-daemon session` — o /bin/sh
/// some do ps (os 8 do dump morrem) e a supervisão inteira é um corpo.
pub fn run_session() -> Result<(), String> {
    let mut vagas: Vec<Residente> = CLIENTES_DISPLAY
        .iter()
        .map(|(n, c)| Residente {
            nome: (*n).to_string(),
            comando: (*c).to_string(),
            bus: None,
        })
        .collect();
    vagas.extend(fila_residentes());
    supervisa("/tmp/elite-daemon-session.lock", vagas, "session")
}

fn supervisa(
    lock_path: &str,
    vagas_iniciais: Vec<Residente>,
    porta: &str,
) -> Result<(), String> {
    // instância única (E30): flock PRÓPRIO da porta — o modo game, o
    // supervise e o session são corpos distintos, locks distintos (o
    // 2º sai 0).
    let lock = PathBuf::from(lock_path);
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
    super::instala_sinais();

    let log = log_path();
    if let Some(pai) = log.parent() {
        let _ = std::fs::create_dir_all(pai);
    }

    // E135 — a conexão ao session bus nasce UMA vez (persistente — o
    // gate de nome por RPC é O(1) sem fork; sem bus, trava sozinha).
    let bus_conn: Option<zbus::blocking::Connection> =
        zbus::blocking::Connection::session().ok();

    let mut vagas: Vec<Vaga> = vagas_iniciais
        .into_iter()
        .map(|res| Vaga {
            res,
            filho: None,
            trava: None,
            desde: Instant::now(),
            nasceu: false,
            ausente: false,
        })
        .collect();
    eprintln!(
        "elite-daemon {}: no ar ({} vaga(s) — gate de posse E135 ativo; papel em {})",
        porta,
        vagas.len(),
        log.display()
    );

    loop {
        for v in &mut vagas {
            // 1) a colheita: filho que MORREU é logado e vira vaga (a
            // trava da vaga solta junto — o nome no bus morre com ele)
            if let Some(filho) = v.filho.as_mut() {
                match filho.try_wait() {
                    Ok(Some(st)) => {
                        eprintln!(
                            "elite-daemon supervise: {} SAIU {} — relança em 2s",
                            v.res.nome, st
                        );
                        v.filho = None;
                        v.trava = None;
                        v.desde = Instant::now();
                    }
                    Ok(None) => {}
                    Err(e) => {
                        eprintln!("elite-daemon supervise: {} try_wait falhou: {}", v.res.nome, e);
                        v.filho = None;
                        v.trava = None;
                        v.desde = Instant::now();
                    }
                }
            }
            if v.filho.is_some() || v.ausente {
                continue;
            }
            // 2) E135 — O GATE DE POSSE antes de QUALQUER fork:
            //    (a) o nome no bus com dono = instância de fora VIVA →
            //        adota (o respawn cego que gerou o loop 809 morre);
            let bus_dono = v
                .res
                .bus
                .as_deref()
                .map(|b| nome_tem_dono(&bus_conn, b))
                .unwrap_or(false);
            if bus_dono {
                continue; // adotada: nem log por ciclo (o papel não vira spam)
            }
            //    (b) a trava em posse de irmão = o outro daemon da casa
            //        já criou o filho → adota silencioso (idem).
            let trava = match tenta_trava(&v.res.nome) {
                Ok(f) => Some(f),
                Err(_) => None,
            };
            if trava.is_none() {
                continue;
            }
            //    (c) a vaga é NOSSA: a 1ª subida é IMEDIATA; da morte em
            //        diante TODO respawn espera o backoff de 2s.
            if v.nasceu && v.desde.elapsed() < BACKOFF {
                // guarda a trava até a hora do spawn (a posse não vaga
                // durante o backoff — nenhum irmão entra no meio)
                v.trava = trava;
                continue;
            }
            match lanca(&v.res.comando, &log) {
                Ok(filho) => {
                    eprintln!(
                        "elite-daemon supervise: {} no ar (pid {})",
                        v.res.nome,
                        filho.id()
                    );
                    v.filho = Some(filho);
                    v.trava = trava;
                    v.nasceu = true;
                }
                Err(e) if e.kind() == io::ErrorKind::NotFound => {
                    // ausência intencional da casa: o pacote não trouxe o
                    // binário — sem respawn de fantasma (honesto)
                    eprintln!(
                        "elite-daemon supervise: {} AUSENTE no sistema — fora da fila (honesto)",
                        v.res.nome
                    );
                    v.ausente = true;
                }
                Err(e) => {
                    eprintln!(
                        "elite-daemon supervise: {} não subiu ({}) — tenta em 2s",
                        v.res.nome, e
                    );
                    v.nasceu = true;
                    v.desde = Instant::now();
                    v.trava = trava;
                }
            }
        }
        // SIGTERM/SIGINT: SIGTERM aos filhos NOSSOS, espera a colheita,
        // sai limpo (os adotados morrem com a sessão — não são filhos).
        if super::STOP.load(std::sync::atomic::Ordering::SeqCst) {
            for v in &mut vagas {
                if let Some(filho) = v.filho.as_ref() {
                    unsafe { libc::kill(filho.id() as i32, libc::SIGTERM) };
                }
            }
            for v in &mut vagas {
                if let Some(mut filho) = v.filho.take() {
                    let _ = filho.wait();
                }
            }
            eprintln!("elite-daemon supervise: SIGTERM — filhos encerrados, saída limpa");
            return Ok(());
        }
        std::thread::sleep(Duration::from_secs(1));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn conf_casa_os_residentes_nome_comando() {
        let r = parse_conf(
            "# a fila da casa (E132)\n\
             \n\
             swaync::swaync\n\
             udiskie::udiskie --automount --notify --no-tray\n",
        );
        assert_eq!(r.len(), 2, "comentário e linha vazia não são residentes");
        assert_eq!(r[0].nome, "swaync");
        assert_eq!(r[0].comando, "swaync");
        assert_eq!(r[0].bus, None, "gramática velha = sem gate de bus");
        assert_eq!(r[1].comando, "udiskie --automount --notify --no-tray");
    }

    #[test]
    fn conf_e135_gramatica_do_bus() {
        // a gramática nova: nome::bus::comando — o gate de posse viaja
        // no conf da casa (o dono edita à vontade)
        let r = parse_conf("swaync::org.erikreider.swaync.cc::swaync\n");
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].nome, "swaync");
        assert_eq!(r[0].bus.as_deref(), Some("org.erikreider.swaync.cc"));
        assert_eq!(r[0].comando, "swaync");
    }

    #[test]
    fn conf_key_value_e_ruido_nao_sao_residentes() {
        // KEY=VALUE sem '::' é porta FUTURA: aceito no arquivo, ignorado
        // na fila (nada de residente fantasma)
        let r = parse_conf("BARS_LOG=/outro.log\nWINE_PREFIX=x\n");
        assert!(r.is_empty(), "KEY=VALUE não vira residente");
        // linhas malformadas caem fora SEM pânico (split com lado vazio)
        let r = parse_conf("::sem nome\nnome::\n::\n   \n");
        assert!(r.is_empty(), "linhas malformadas são ignoradas");
        // o espaço em volta do separador é tolerado (o parser aparados)
        let r = parse_conf("  swayosd  ::  swayosd-server  \n");
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].comando, "swayosd-server");
    }

    #[test]
    fn default_e_os_residentes_puros_do_craft_bars() {
        // a fila DEFAULT é DOS residentes puros do craft-bars — SEM o
        // game watch (nativo do próprio daemon), SEM o display watch e
        // SEM waybar/dock (esses seguem no craft-bars: escopo honesto)
        for (nome, _, _) in RESIDENTES_DEFAULT {
            assert!(
                !matches!(*nome, "craft-game" | "craft-display" | "waybar" | "craft-dock-gui" | "craft-toplevel"),
                "{} não é residente do supervise (escopo honesto)",
                nome
            );
        }
        let nomes: Vec<&str> = RESIDENTES_DEFAULT.iter().map(|(n, _, _)| *n).collect();
        assert!(nomes.contains(&"swaync"));
        assert!(nomes.contains(&"udiskie"));
        assert!(nomes.contains(&"swayosd"));
        // E135 — o roteador de áudio SAI da fila (disparo por evento:
        // netlink uevent de som → `craft-audio-route --once` — residente
        // python na sessão é a ordem do dono que morre)
        assert!(
            !nomes.contains(&"craft-audio-route"),
            "audio-route não é mais residente (E135 — evento --once)"
        );
        // e os clientes de display NUNCA foram residentes puros — agora
        // moram na fila própria da porta session
        let display: Vec<&str> = CLIENTES_DISPLAY.iter().map(|(n, _)| *n).collect();
        assert!(display.contains(&"toplevel") && display.contains(&"waybar") && display.contains(&"dock"),
            "a porta session carrega os clientes de display");
    }

    #[test]
    fn e135_o_gate_de_posse_adota_quem_ja_e_dono() {
        // o nome no bus com dono = instância de fora viva: ADOTA mesmo
        // com a trava livre (o réu do loop 809 — swaync exit 1 relançado
        // às cegas — morre exatamente aqui)
        assert!(matches!(
            decide_posse(true, true),
            Posse::Adotada
        ));
        // a trava em posse de irmão (nosso 2º daemon): idem, adota
        assert!(matches!(
            decide_posse(false, false),
            Posse::Adotada
        ));
        // nem nome nem trava: a vaga é NOSSA
        assert!(matches!(decide_posse(false, true), Posse::Nossa));
    }
}
