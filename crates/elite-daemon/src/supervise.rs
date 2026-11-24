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
/// E140 — A TOP BAR É O CRAFT-BAR-RS (a aposentadoria do waybar, a
/// ordem do dono do dossiê 1.0-88: 100% Rust na interface própria).
/// Sem fallback waybar POR DESENHO: o binário e ESTE daemon viajam NO
/// MESMO PACOTE elite-system (a dose que traz um traz o outro — não
/// existe o rig com o E140 sem a barra; a lei do fallback nunca
/// dependeu de recurso que o próprio pacote carrega).
/// 2.0 Fase 2 — a fila APOSA dois heróis de era: o "toplevel" (o C
/// morreu — o cliente Wayland NATIVO mora no PRÓPRIO corpo deste
/// daemon agora, nenhuma vaga externa) e o "idle" (o swayidle morre —
/// a vigília ext-idle-notify + hyprlock é do daemon; o craft-idle vira
/// o escritor do conf, sem daemon externo).
pub const CLIENTES_DISPLAY: &[(&str, &str)] = &[
    ("topbar", "craft-bar-rs"),
    ("dock", "craft-dock-rs"),
    ("policykit", "lxqt-policykit-agent"),
];

const CONF_PATH: &str = "/usr/local/share/elite/daemon.conf";
const BACKOFF: Duration = Duration::from_secs(2);

#[derive(Default)]
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
// E138 — o veredito de posse é LEI DOS TESTES (o loop da produção inlina
// os gates por desempenho de ciclo; esta função PURA é o contrato que a
// suíte crava — cfg(test) livra o binário do warning de item morto).
#[cfg(test)]
pub enum Posse {
    /// a casa pode spawnar (trava livre E nome sem dono E sem comm vivo)
    Nossa,
    /// instância viva de fora (nome com dono, trava de irmão OU processo
    /// com o comm da vaga): adota
    Adotada,
}

/// E138 — a decisão estendida: o processo de FORA com o comm da vaga é
/// o terceiro gate de adoção (o udiskie do autostart fóssil do dump
/// v2.13: UDISKIE_COUNT=2 com a sessão viva — o autostart antigo do
/// home lança E o daemon relançava por cima; agora quem já está de pé
/// é ADOTADO, nunca duplicado).
#[cfg(test)]
pub fn decide_posse(nome_tem_dono: bool, trava_livre: bool, comm_vivo: bool) -> Posse {
    if nome_tem_dono || !trava_livre || comm_vivo {
        Posse::Adotada
    } else {
        Posse::Nossa
    }
}

/// E138 — o COMM esperado cortado no limite do kernel (TASK_COMM_LEN:
/// 15 chars + NUL — o comm de 'lxqt-policykit-agent' é
/// 'lxqt-policykit-'; comparar a string inteira nunca casaria).
pub fn comm_corta(esperado: &str) -> &str {
    if esperado.len() > 15 {
        &esperado[..15]
    } else {
        esperado
    }
}

/// E138 — existe um processo VIVO (não-zumbi, do NOSSO uid) com este
/// comm? A varredura é /proc pura (zero fork de pgrep — o daemon não
/// paga processo por ciclo); o zombie NÃO conta como vivo (o <defunct>
/// do dump não adota vaga nenhuma).
pub fn comm_vivo(esperado: &str) -> bool {
    let alvo = comm_corta(esperado);
    let meu_uid = unsafe { libc::getuid() };
    let Ok(dir) = std::fs::read_dir("/proc") else { return false };
    for e in dir.flatten() {
        let pid = match e.file_name().to_string_lossy().parse::<i32>() {
            Ok(p) => p,
            Err(_) => continue,
        };
        let Ok(comm) = std::fs::read_to_string(format!("/proc/{}/comm", pid)) else { continue };
        if comm.trim() != alvo {
            continue;
        }
        // estado: o 3º campo do stat (após o último ')' — o comm pode ter
        // espaço/parêntese); 'Z' = zumbi, não é vida
        let Ok(stat) = std::fs::read_to_string(format!("/proc/{}/stat", pid)) else { continue };
        let Some(depois) = stat.rsplit(')').next() else { continue };
        let estado = depois.trim().chars().next().unwrap_or('R');
        if estado == 'Z' {
            continue;
        }
        // dono: só o processo do NOSSO usuário prova a sessão daqui
        let Ok(status) = std::fs::read_to_string(format!("/proc/{}/status", pid)) else { continue };
        let uid_dele = status
            .lines()
            .find_map(|l| l.strip_prefix("Uid:").map(|r| r.to_string()))
            .and_then(|r| r.split_whitespace().next().and_then(|u| u.parse::<u32>().ok()))
            .unwrap_or(u32::MAX);
        if uid_dele == meu_uid {
            return true;
        }
    }
    false
}

/// E138 — o AUTO do game.conf (a chave do modo de jogo automático — o
/// toggle do craft-game escreve, ESTE ouvido lê): função PURA sobre o
/// caminho para o teste cravar a gramática.
pub fn auto_em(texto: &str) -> bool {
    texto.lines().any(|l| l.trim() == "AUTO=1")
}

fn auto_on() -> bool {
    let base = std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".config")
        });
    std::fs::read_to_string(base.join("elite/game.conf"))
        .map(|t| auto_em(&t))
        .unwrap_or(false)
}

/// E138 — o PEEK-LOCK do motor do jogo: o /tmp/elite-daemon.lock não
/// travável = um elite-daemon (modo game) VIVO de fora — a vaga é
/// ADOTADA sem spawn (o filho que nasceria morto pelo lock próprio
/// viraria churn de respawn a cada 2s; o peek corta a classe inteira).
/// O lock é PEGADO E SOLTO na hora (o filho pega o dele sozinho).
/// E139 — PUB: o modo game também dá o peek no LOCK DA SESSÃO para
/// decidir quem levanta os ouvidores (session vivo = ouvidores dele,
/// nunca dois donos).
pub fn peek_lock_livre(caminho: &std::path::Path) -> bool {
    let Ok(f) = std::fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(caminho)
    else {
        return true; // inobservável = livre (honesto nos dois mundos)
    };
    let rc = unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    rc == 0 // 0 = ninguém segura (livre); != 0 = motor de fora vivo
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
    /// E138 — processo de fora com este comm = vaga ADOTADA (o gate do
    /// udiskie duplicado: autostart fóssil lança, a sessão NUNCA soma o
    /// segundo — UDISKIE_COUNT=1 é lei).
    comm: Option<String>,
    /// E138 — condição de existência (falsa = sem spawn; filho nosso
    /// vivo é encerrado — o toggle do jogo vale NA HORA).
    cond: Option<Box<dyn Fn() -> bool + Send>>,
    /// E138 — peek-lock: não-travável = motor de fora vivo (adota).
    peek_lock: Option<PathBuf>,
}

/// E138 — A ESPECIFICAÇÃO DA VAGA (o que o conf não diz): os gates
/// extras que a SESSÃO conhece de cada filho — o comm que prova uma
/// instância de fora (adoção), a condição de existência (o jogo é vaga
/// condicionada ao AUTO do game.conf) e o peek-lock do motor externo.
/// `From<&Residente>` mantém a fila do conf com os gates de LARGA
/// (comm = 1º token do comando; 2.0: o caso especial do idle morreu —
/// a vigília é do PRÓPRIO daemon, o exec-swayidle é história).
struct VagaSpec {
    res: Residente,
    /// processo de fora com este comm = vaga ADOTADA (E138)
    comm: Option<String>,
    /// falsa = a vaga não deve existir (spawn proibido, filho nosso
    /// vivo é encerrado — o toggle do dono é imediato)
    cond: Option<Box<dyn Fn() -> bool + Send>>,
    /// lock não-travável = motor de fora vivo (peek: nunca spawn em cima)
    peek_lock: Option<PathBuf>,
}

impl Default for VagaSpec {
    fn default() -> Self {
        VagaSpec {
            res: Residente::default(),
            comm: None,
            cond: None,
            peek_lock: None,
        }
    }
}

impl From<Residente> for VagaSpec {
    fn from(res: Residente) -> Self {
        let comm = res
            .comando
            .split_whitespace()
            .next()
            .map(|t| t.to_string());
        VagaSpec {
            res,
            comm,
            cond: None,
            peek_lock: None,
        }
    }
}

/// E132 — a porta `supervise`: SÓ os residentes puros (a compat dos
/// rigs que chamam o daemon direto).
pub fn run() -> Result<(), String> {
    supervisa(
        "/tmp/elite-daemon-supervise.lock",
        fila_residentes().into_iter().map(VagaSpec::from).collect(),
        "supervise",
    )
}

/// E135 — a porta `session`: O LANÇADOR ÚNICO da sessão gráfica — os
/// clientes de display (toplevel, topbar E140, dock, idle, polkit) + os
/// residentes puros, todos na MESMA vaga com o MESMO gate de posse.
/// O craft-bars shell vira `exec elite-daemon session` — o /bin/sh
/// some do ps (os 8 do dump morrem) e a supervisão inteira é um corpo.
/// E138 — o motor do jogo é vaga da sessão (a ordem do dono, dump
/// v2.13: AUTO=1 ativo no game.conf mas `craft-game status` dizia
/// 'watch FORA — sem daemon vivo' — o `exec` do craft-bars MATOU o
/// respawn do motor que o corpo bash fazia; a sessão agora CARREGA o
/// loop: condicionado ao AUTO (o toggle do menu é imediato, sem
/// relogin), supervisionado (caiu → volta em 2s), adotado por
/// peek-lock quando um motor de fora vive).
pub fn run_session() -> Result<(), String> {
    let mut specs: Vec<VagaSpec> = CLIENTES_DISPLAY
        .iter()
        .map(|(n, c)| {
            let s: VagaSpec = Residente {
                nome: (*n).to_string(),
                comando: (*c).to_string(),
                bus: None,
            }
            .into();
            s
        })
        .collect();
    specs.extend(fila_residentes().into_iter().map(VagaSpec::from));
    // E138 — A VAGA DO JOGO: o próprio binário em modo game (sem args — o
    // daemon_loop com o lock /tmp/elite-daemon.lock e o pid no
    // game-watch.pid que o craft-game status lê). AUTO=0 = ausência
    // intencional (a escolha do dono é a lei, lei do idle E36).
    if let Ok(exe) = std::env::current_exe() {
        let jogo = VagaSpec {
            res: Residente {
                nome: "game".to_string(),
                comando: exe.to_string_lossy().to_string(),
                bus: None,
            },
            // NUNCA comm: o comm 'elite-daemon' é O PRÓPRIO session — o
            // gate certo é o peek no lock do modo game
            comm: None,
            cond: Some(Box::new(auto_on)),
            peek_lock: Some(PathBuf::from("/tmp/elite-daemon.lock")),
        };
        specs.push(jogo);
    }
    // E139 — A VAGA DO WATCH-SAVE (a tela que lembra SEMPRE): o
    // craft-display watch é vaga supervisionada da SESSÃO — a escolha
    // do wdisplays grava de novo sem depender do autostart ter nascido
    // antes, e caiu → volta em 2s (o mesmo contrato dos irmãos). O
    // verbo próprio tem o guard E135 intocado: a porta LEGADA `watch`
    // segue saindo 0 com o session vivo — quem residia de verdade é
    // ESTA vaga, pelo verbo watch-save.
    specs.push(VagaSpec {
        res: Residente {
            nome: "displaysave".to_string(),
            comando: "/usr/local/bin/craft-display watch-save".to_string(),
            bus: None,
        },
        // NUNCA comm: o craft-display apply bifurca por evento e vive
        // segundos — um gate por comm recusaria o spawn eternamente
        comm: None,
        cond: None,
        peek_lock: None,
    });
    // 1.0-93 — O LOCK DA SESSÃO MUDA DE CASA (a ordem do dono, rig da
    // 1.0-92: o `/tmp/elite-daemon-session.lock` sofria `os error 13` —
    // /tmp é MUNDO COMPARTILHADO com donos de eras passadas; o lock
    // mora AGORA no tmpfs PRIVADO do dono da sessão:
    // `$XDG_RUNTIME_DIR/elite/session.lock` (/run/user/<uid>/elite).
    // O FALLBACK `/tmp` só veste quando o runtime privado não abre
    // (ambiente sem XDG_RUNTIME_DIR — o mundo legado), e o peek do
    // daemon_loop confere OS DOIS caminhos (elite_core lê o contrato).
    let uid = unsafe { libc::getuid() };
    let lock_session = elite_core::session_lock_path(uid)
        .to_string_lossy()
        .into_owned();
    supervisa(&lock_session, specs, "session")
}

fn supervisa(
    lock_path: &str,
    vagas_iniciais: Vec<VagaSpec>,
    porta: &str,
) -> Result<(), String> {
    // instância única (E30): flock PRÓPRIO da porta — o modo game, o
    // supervise e o session são corpos distintos, locks distintos (o
    // 2º sai 0).
    let mut lock = PathBuf::from(lock_path);
    // 1.0-93 — o endereço PRIVADO precisa existir (o tmpfs do dono
    // quase sempre já existe — o bind do bus cria; aqui o cinto)
    if let Some(pai) = lock.parent() {
        let _ = std::fs::create_dir_all(pai);
    }
    let f = std::fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(&lock)
        .or_else(|_| {
            // o runtime privado não abriu (o error 13 da era /tmp ao
            // contrário): o FALLBACK de /tmp veste UMA vez, com a voz
            // no papel — o peek do daemon_loop confere os DOIS
            eprintln!(
                "elite-daemon: o lock privado {} não abriu — o fallback /tmp veste (mundo sem XDG_RUNTIME_DIR)",
                lock.display()
            );
            lock = PathBuf::from(elite_core::SESSION_LOCK_FALLBACK);
            std::fs::OpenOptions::new()
                .create(true)
                .truncate(false)
                .write(true)
                .open(&lock)
        })
        .map_err(|e| format!("lock {}: {}", lock.display(), e))?;
    let rc = unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if rc != 0 {
        // E146 — A SAÍDA SILENCIOSA GANHA VOZ: o rig da 1.0-94 mostrou o
        // AUTOSTART CORROMPIDO disparando `elite-daemon session &` OITO
        // vezes (sed cego de agente fora do repo) — o flock segurou o
        // dano (UM só dono de pé, os sete excedentes saíram 0 calados),
        // mas o silêncio escondia o SINTOMA: agora cada recusa deixa a
        // linha no papel do daemon — a contagem alta é a assinatura da
        // corrupção que o elite-heal-sessao cura.
        let log_r = log_path();
        if let Ok(mut fh) = std::fs::OpenOptions::new().append(true).create(true).open(&log_r) {
            use std::io::Write;
            let _ = writeln!(
                fh,
                "elite-daemon: a porta {porta} já tem dono — a 2ª instância sai 0 (flock E30; recusas repetidas = autostart corrompido, o elite-heal-sessao cura)"
            );
        }
        eprintln!(
            "elite-daemon: a porta {porta} já tem dono — a 2ª instância sai 0 (flock E30)"
        );
        return Ok(()); // o irmão está no ar — a casa segue com UM dono
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
        .map(|spec| Vaga {
            res: spec.res,
            filho: None,
            trava: None,
            desde: Instant::now(),
            nasceu: false,
            ausente: false,
            comm: spec.comm,
            cond: spec.cond,
            peek_lock: spec.peek_lock,
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
            // 0) E138 — A CONDIÇÃO DA VAGA: falsa = a vaga não deve
            //    existir (spawn proibido; filho NOSSO vivo é encerrado
            //    com SIGTERM e colhido — o AUTO=0 do jogo vale NA HORA,
            //    sem relogin, sem órfão)
            if let Some(cond) = v.cond.as_ref() {
                if !cond() {
                    if let Some(mut filho) = v.filho.take() {
                        unsafe { libc::kill(filho.id() as i32, libc::SIGTERM) };
                        let _ = filho.wait();
                        v.trava = None;
                        v.desde = Instant::now();
                        eprintln!(
                            "elite-daemon supervise: {} condição DESLIGADA — filho encerrado (a escolha do dono é imediata)",
                            v.res.nome
                        );
                    }
                    continue;
                }
            }
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
            //    (a') E138 — o gate por COMM: um processo de FORA vivo
            //        com o comm da vaga = instância adotada (o udiskie
            //        do autostart fóssil do dump v2.13 — a sessão nunca
            //        soma o segundo; UDISKIE_COUNT=1 é lei)
            if v
                .comm
                .as_deref()
                .map(comm_vivo)
                .unwrap_or(false)
            {
                continue; // adotada de fora — o <defunct> não conta, o uid conta
            }
            //    (a'') E138 — o gate por PEEK-LOCK: o lock de motor
            //        (modo game) não-travável = motor de fora VIVO →
            //        adota (nunca spawn em cima de quem já é dono)
            if v
                .peek_lock
                .as_deref()
                .map(|p| !peek_lock_livre(p))
                .unwrap_or(false)
            {
                continue;
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
                !matches!(*nome, "craft-game" | "craft-display" | "waybar" | "craft-dock-gui"),
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
        // moram na fila própria da porta session (E140: a topbar é o
        // craft-bar-rs — o waybar aposentou pela ordem do dono)
        let display: Vec<&str> = CLIENTES_DISPLAY.iter().map(|(n, _)| *n).collect();
        assert!(display.contains(&"topbar") && display.contains(&"dock") && display.contains(&"policykit"),
            "a porta session carrega a família de display 2.0 (topbar + dock + polkit)");
        assert!(!display.contains(&"waybar"),
            "o waybar NÃO é mais cliente da sessão (E140 — a top bar é o craft-bar-rs)");
        // 2.0 — o toplevel de C APOSENTOU: o cliente Wayland mora no
        // PRÓPRIO daemon (a vaga externa morreu com o binário)
        assert!(!display.contains(&"toplevel"),
            "o craft-toplevel de C não é mais vaga (2.0: o wayland nativo é do daemon)");
        // 2.0 — o idle APOSENTOU: a vigília é do daemon (ext-idle-notify)
        assert!(!display.contains(&"idle"),
            "o swayidle/craft-idle não é mais vaga (2.0: a vigília é do daemon)");
    }

    #[test]
    fn e135_o_gate_de_posse_adota_quem_ja_e_dono() {
        // o nome no bus com dono = instância de fora viva: ADOTA mesmo
        // com a trava livre (o réu do loop 809 — swaync exit 1 relançado
        // às cegas — morre exatamente aqui)
        assert!(matches!(
            decide_posse(true, true, false),
            Posse::Adotada
        ));
        // a trava em posse de irmão (nosso 2º daemon): idem, adota
        assert!(matches!(
            decide_posse(false, false, false),
            Posse::Adotada
        ));
        // nem nome nem trava nem comm: a vaga é NOSSA
        assert!(matches!(
            decide_posse(false, true, false),
            Posse::Nossa
        ));
    }

    #[test]
    fn e138_o_comm_de_fora_adota_a_vaga() {
        // o udiskie do autostart fóssil do dump v2.13 (UDISKIE_COUNT=2):
        // processo de fora vivo com o comm da vaga = ADOTADA, mesmo com
        // trava livre e sem bus — a sessão NUNCA soma o segundo
        assert!(matches!(
            decide_posse(false, true, true),
            Posse::Adotada
        ));
    }

    #[test]
    fn e138_o_comm_corta_no_limite_do_kernel() {
        // TASK_COMM_LEN = 16 (15 chars + NUL): o comm do
        // lxqt-policykit-agent nasce CORTADO — comparar a string inteira
        // nunca casaria e a vaga duplicaria o agente
        assert_eq!(comm_corta("udiskie"), "udiskie");
        assert_eq!(comm_corta("swayosd-server"), "swayosd-server");
        assert_eq!(comm_corta("lxqt-policykit-agent"), "lxqt-policykit-");
        assert_eq!(comm_corta("craft-dock-rs"), "craft-dock-rs");
    }

    #[test]
    fn e138_o_auto_do_game_conf_e_a_condicao_do_motor() {
        // dump v2.13: AUTO=1 com o watch FORA — a vaga do jogo na sessão
        // lê ESTE arquivo; a gramática é EXATA (AUTO=1, sem espaço extra)
        assert!(auto_em("AUTO=1\n"), "AUTO=1 liga o motor");
        assert!(auto_em("# comentário\nAUTO=1\n"), "comentário não atrapalha");
        assert!(!auto_em("AUTO=0\n"), "AUTO=0 é ausência intencional");
        assert!(!auto_em(""), "sem conf = ausência intencional (lei do idle E36)");
        assert!(!auto_em("AUTO=10\n"), "AUTO=10 NÃO é AUTO=1 (match exato)");
    }

    #[test]
    fn e138_a_sessao_carrega_o_jogo_com_condicao_e_peek() {
        // a vaga do jogo NÃO usa o comm (o comm 'elite-daemon' é o
        // PRÓPRIO session — o gate certo é o peek no lock do modo game):
        // o spec da fila do conf ganha comm de LARGA (1º token) e NUNCA
        // cond/peek (o conf não tem como expressá-los)
        let r = Residente {
            nome: "udiskie".into(),
            comando: "udiskie --automount --notify --no-tray".into(),
            bus: None,
        };
        let spec: VagaSpec = r.into();
        assert_eq!(spec.comm.as_deref(), Some("udiskie"));
        assert!(spec.cond.is_none(), "conf não tem condição");
        assert!(spec.peek_lock.is_none(), "conf não tem peek");
        // gramática com bus: o comm continua sendo o 1º token do comando
        let r2 = Residente {
            nome: "swaync".into(),
            comando: "swaync".into(),
            bus: Some("org.erikreider.swaync.cc".into()),
        };
        let spec2: VagaSpec = r2.into();
        assert_eq!(spec2.comm.as_deref(), Some("swaync"));
    }
}
