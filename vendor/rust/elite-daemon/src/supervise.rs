// ELITE · elite-daemon — o SUPERVISOR DOS RESIDENTES (E132). A ordem do
// dono ("espremer o limão") chega aos daemons de sessão que o craft-bars
// ressuscitava por pgrep a cada 5s: os residentes PUROS (swaync, udiskie,
// swayosd, craft-audio-route) viram FILHOS DIRETOS deste processo —
// try_wait(2) nativo, respawn com backoff de 2s por filho, stdout+stderr
// no MESMO bars.log da casa ($XDG_CACHE_HOME/elite/bars.log — a forense
// continua numa prova só). O craft-bars passa a DELEGAR quando este
// binário existe (o caminho bash velho segue como fallback dos rigs).
//
// ESCOPO HONESTO: NÃO moram aqui o craft-game watch (o jogo é NATIVO do
// próprio elite-daemon — modo game mode), nem o craft-display watch, nem
// a waybar/dock/toplevel (esses seguem no craft-bars: são clientes de
// display com lógica própria de gate E99 — nenhum half-promise de
// unificação pela metade). O conf /usr/local/share/elite/daemon.conf
// sobrepõe a lista DEFAULT quando existe (um residente por linha,
// `nome::comando ...`; linhas # e vazias ignoradas; KEY=VALUE sem '::' é
// aceito e ignorado — porta futura, nomeada honesta).
use std::io;
use std::os::unix::io::AsRawFd;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

/// a fila DEFAULT — os residentes PUROS do craft-bars (os que são só
/// `comando` vivo, sem gate de display): o mesmo papel, o mesmo bars.log.
pub const RESIDENTES_DEFAULT: &[(&str, &str)] = &[
    ("swaync", "swaync"),
    ("udiskie", "udiskie --automount --notify --no-tray"),
    ("swayosd", "swayosd-server"),
    ("craft-audio-route", "craft-audio-route"),
];

const CONF_PATH: &str = "/usr/local/share/elite/daemon.conf";
const BACKOFF: Duration = Duration::from_secs(2);

pub struct Residente {
    pub nome: String,
    pub comando: String,
}

/// E132 — o parser do daemon.conf (função PURA, a porta dos testes).
/// Formato: um residente por linha `nome::comando ...` (split na 1ª
/// dupla de ':'; o comando é o resto cru, tokens por espaço — SEM shell,
/// sem aspas, o contrato é simples e nomeado). Linhas vazias, só-espaço
/// e comentários '#' são ignoradas; `KEY=VALUE` sem '::' é reconhecido
/// como chave de config e NÃO vira residente (porta futura, escopo
/// honesto — nada de promessa pela metade).
pub fn parse_conf(texto: &str) -> Vec<Residente> {
    let mut out = Vec::new();
    for linha in texto.lines() {
        let linha = linha.trim();
        if linha.is_empty() || linha.starts_with('#') {
            continue;
        }
        let Some((nome, comando)) = linha.split_once("::") else {
            continue; // KEY=VALUE ou ruído: não é residente
        };
        let nome = nome.trim();
        let comando = comando.trim();
        if nome.is_empty() || comando.is_empty() {
            continue;
        }
        out.push(Residente {
            nome: nome.to_string(),
            comando: comando.to_string(),
        });
    }
    out
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
        .map(|(n, c)| Residente {
            nome: (*n).to_string(),
            comando: (*c).to_string(),
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

/// o spawn: stdin /dev/null, stdout+stderr em APPEND no bars.log
/// (tokens por espaço — SEM shell no meio; o parser segue o contrato).
fn lanca(comando: &str, log: &PathBuf) -> io::Result<Child> {
    let mut partes = comando.split_whitespace();
    let prog = partes.next().unwrap_or("");
    let args: Vec<&str> = partes.collect();
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
    /// o instante da MORTE (ou do arranque recusado) — o backoff de 2s
    /// conta daqui (um respawn por filho, nunca uma rajada).
    desde: Instant,
    /// o arranque inicial já correu: da morte em diante é TODO respawn
    /// com backoff (a 1ª subida não espera — a sessão quer a fila no ar).
    nasceu: bool,
    /// binário ausente no sistema: sem respawn eterno de fantasma (o
    /// craft-bars fazia 'command -v' antes — aqui o erro do spawn fala).
    ausente: bool,
}

pub fn run() -> Result<(), String> {
    // instância única (E30): flock PRÓPRIO do supervise — o modo game e
    // o supervisor são corpos distintos, locks distintos (o 2º sai 0).
    let lock = PathBuf::from("/tmp/elite-daemon-supervise.lock");
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

    let mut vagas: Vec<Vaga> = fila_residentes()
        .into_iter()
        .map(|res| Vaga {
            res,
            filho: None,
            desde: Instant::now(),
            nasceu: false,
            ausente: false,
        })
        .collect();
    eprintln!(
        "elite-daemon supervise: no ar ({} residente(s) — o papel segue em {})",
        vagas.len(),
        log.display()
    );

    loop {
        for v in &mut vagas {
            // 1) a colheita: filho que MORREU é logado e vira vaga
            if let Some(filho) = v.filho.as_mut() {
                match filho.try_wait() {
                    Ok(Some(st)) => {
                        eprintln!(
                            "elite-daemon supervise: {} SAIU {} — relança em 2s",
                            v.res.nome, st
                        );
                        v.filho = None;
                        v.desde = Instant::now();
                    }
                    Ok(None) => {}
                    Err(e) => {
                        eprintln!("elite-daemon supervise: {} try_wait falhou: {}", v.res.nome, e);
                        v.filho = None;
                        v.desde = Instant::now();
                    }
                }
            }
            // 2) o (re)arranque: a 1ª subida é IMEDIATA (a sessão quer a
            // fila no ar); da morte em diante TODO respawn espera o
            // backoff de 2s — nunca uma rajada de fork por segundo
            if v.filho.is_none() && !v.ausente && (!v.nasceu || v.desde.elapsed() >= BACKOFF) {
                match lanca(&v.res.comando, &log) {
                    Ok(filho) => {
                        eprintln!(
                            "elite-daemon supervise: {} no ar (pid {})",
                            v.res.nome,
                            filho.id()
                        );
                        v.filho = Some(filho);
                        v.nasceu = true;
                    }
                    Err(e) if e.kind() == io::ErrorKind::NotFound => {
                        // ausência intencional da casa: o pacote não
                        // trouxe o binário — sem respawn de fantasma
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
                    }
                }
            }
        }
        // SIGTERM/SIGINT: SIGTERM aos filhos, espera a colheita, sai limpo
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
        assert_eq!(r[1].nome, "udiskie");
        assert_eq!(r[1].comando, "udiskie --automount --notify --no-tray");
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
        assert_eq!(r[0].nome, "swayosd");
        assert_eq!(r[0].comando, "swayosd-server");
    }

    #[test]
    fn default_e_os_residentes_puros_do_craft_bars() {
        // a fila DEFAULT é a DOS residentes puros do craft-bars — SEM o
        // game watch (nativo do próprio daemon), SEM o display watch e
        // SEM waybar/dock (esses seguem no craft-bars: escopo honesto)
        for (nome, _) in RESIDENTES_DEFAULT {
            assert!(
                !matches!(*nome, "craft-game" | "craft-display" | "waybar" | "craft-dock-gui" | "craft-toplevel"),
                "{} não é residente do supervise (escopo honesto)",
                nome
            );
        }
        let nomes: Vec<&str> = RESIDENTES_DEFAULT.iter().map(|(n, _)| *n).collect();
        assert!(nomes.contains(&"swaync"));
        assert!(nomes.contains(&"udiskie"));
        assert!(nomes.contains(&"swayosd"));
        assert!(nomes.contains(&"craft-audio-route"));
    }
}
