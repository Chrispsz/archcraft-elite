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
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

/// a fila DEFAULT — os residentes PUROS do craft-bars (sem gate de
/// display): (nome, comando, nome no session bus que prova a posse).
/// E135 — o craft-audio-route SAI da fila: roteador de áudio vira
/// DISPARO POR EVENTO (o netlink uevent de som dispara um `--once` —
/// residente em python na sessão é a ordem do dono que morre).
/// E151 — O UDISKIE SAI DA FILA (a diretriz do debloat extremo: o
/// interpretador Python residente de 58,5 MB morre — o automount é a
/// regra udev 91-elite-automount + a unit elite-automount@.service:
/// oneshot POR EVENTO de plug, zero daemon, o udisksctl do usuário
/// ativo monta em /run/media/$USER via o udisksd nativo).
pub const RESIDENTES_DEFAULT: &[(&str, &str, Option<&str>)] = &[
    (
        "swaync",
        "swaync",
        Some("org.erikreider.swaync.cc"),
    ),
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

/// 1.0-100 — A VARREDURA DOS LOCKS ÓRFÃOS DE /tmp (o audit-99.txt §2
/// fotografou `/tmp/elite-daemon.lock` e `/tmp/elite-daemon-session.lock`
/// parados no chão entre relogins): o flock é estado do INODE — o dono
/// morre, a trava se solta, mas o ARQUIVO continua no /tmp mundial
/// (sticky bit, donos de eras) mentindo à sessão nova e ao probe. A
/// varredura é SEGURA por dois portões:
///   1. o FLOCK primeiro: travável = ninguém vivo segura — o arquivo é
///      fóssil por definição (dono vivo = flock recusa = PULA, o dono
///      nem sente);
///   2. o PID registrado (as gerações novas deixam o número; a era
///      legada deixava 0 bytes): PID existente em /proc = conservador
///      NÃO toca (a lei do dono: só sai o órfão cujo PID não existe
///      mais, ou o arquivo vazio de era sem dono algum).
///
/// Quem chama: a porta `session` ANTES do colhe_relogin (o chão do
/// /tmp sem dono nenhum — nenhum filho de vaga nasceu ainda, a corrida
/// de µs entre varredura e spawn não existe) e o daemon_loop ANTES do
/// lock próprio (o peek do supervisor disse LIVRE — não há segundo
/// corpo para disputar o arquivo).
/// Devolve quantos fósseis saíram (o papel nomeia).
pub fn limpa_locks_orfos() -> usize {
    limpa_locks_orfos_em(std::path::Path::new("/tmp"))
}

/// O corpo parametrizado (a porta dos testes — o teste alimenta um dir
/// de mentira e crava o veredito sem tocar o /tmp de ninguém).
pub fn limpa_locks_orfos_em(dir: &std::path::Path) -> usize {
    let Ok(leitura) = std::fs::read_dir(dir) else {
        return 0;
    };
    let mut saidos = 0usize;
    for e in leitura.flatten() {
        let nome = e.file_name();
        let nome = nome.to_string_lossy();
        // a família inteira da casa: elite-daemon*.lock (o motor, o
        // fallback da sessão, o do supervise — era legada inclusive)
        if !(nome.starts_with("elite-daemon") && nome.ends_with(".lock")) {
            continue;
        }
        let caminho = e.path();
        // portão 1 — o FLOCK (abre SEM create: arquivo que não abre é
        // de outro dono ou sumiu; os dois casos pulam sem drama)
        let Ok(f) = std::fs::OpenOptions::new()
            .truncate(false)
            .write(true)
            .open(&caminho)
        else {
            continue;
        };
        let rc = unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
        if rc != 0 {
            continue; // dono VIVO segurando — o arquivo é dele, de pé
        }
        // portão 2 — o PID: registrado e vivo = conservador (não toca);
        // vazio (era legada) ou PID morto em /proc = o órfão da lei
        let pid = std::fs::read_to_string(&caminho)
            .ok()
            .and_then(|t| t.trim().parse::<i32>().ok());
        let vivo = pid
            .map(|p| p > 1 && std::path::Path::new(&format!("/proc/{p}")).exists())
            .unwrap_or(false);
        if vivo {
            continue;
        }
        if std::fs::remove_file(&caminho).is_ok() {
            saidos += 1;
        }
        // o fd morre no fim do escopo: o flock de varredura se solta
        // junto (o arquivo já saiu do chão — o inode morre com ele)
    }
    saidos
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
/// E147 — O ARGV0 HONESTO DA VAGA DO JOGO: o motor do modo game é o
/// PRÓPRIO binário elite-daemon em modo game — e o ps do rig mostrava
/// DOIS 'elite-daemon' (a duplicidade que o dono fotografou). O spawn
/// da vaga `game` veste argv0 "elite-daemon-game": o ps/comm dizem o
/// PAPEL (session × motor de jogo), o dono lê a árvore SEM dívida,
/// e o flock E30/peek de lock seguem provando a instância única.
fn lanca(comando: &str, log: &PathBuf, nome_vaga: &str) -> io::Result<Child> {
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
    let mut cmd = Command::new(prog);
    cmd.args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::from(f.try_clone()?))
        .stderr(Stdio::from(f));
    if nome_vaga == "game" {
        cmd.arg0("elite-daemon-game");
    }
    cmd.spawn()
}

/// E149 — A PELE DO RESIDENTE ANTES DO FORK (a cura do "Config not
/// found!" do dump): o rig que antecedeu a dose acorda o swaync SEM o
/// conf do dono — o painel nasce cego e o journal nasce vermelho. O
/// daemon session é o ÚLTIMO portão antes do spawn: o conf do skel é
/// entregue UMA vez; o PRESENTE é domínio do dono e NUNCA tocado (a
/// mesma lei do sync_skel do post-upgrade). Função PURA sobre caminhos
/// (a porta do contrato) — 0 entregas = nada mudou, nada no papel.
/// 1.0-102 — A CADEIA DE MESTRES (a cura do "Config not found!" do
/// audit 102): o skel é VEÍCULO DA ISO — o rig instalado NEM O TEM em
/// /etc/skel; o mestre que VIAJA NA DOSE é o do pacote
/// (/usr/local/share/elite/swaync), com o /etc/xdg/swaync da casa e o
/// skel como redes (nessa ordem — o primeiro que TEM a peça veste).
fn entrega_pele_swaync(mestres: &[PathBuf], conf_dir: &std::path::Path) -> usize {
    let mut entregues = 0;
    for arquivo in ["config.json", "style.css"] {
        let alvo = conf_dir.join(arquivo);
        if alvo.exists() {
            continue; // o dono veste o que é dele
        }
        for mestre in mestres {
            let Ok(bytes) = std::fs::read(mestre.join(arquivo)) else {
                continue; // este mestre sem a peça: a rede seguinte veste
            };
            if std::fs::create_dir_all(conf_dir).is_ok() && std::fs::write(&alvo, &bytes).is_ok() {
                entregues += 1;
            }
            break; // o primeiro mestre com a peça decidiu (vestiu OU falhou na escrita — as redes não reescrevem)
        }
    }
    entregues
}

/// E151 — A MORDAÇA DO AUTOSTART DUPLICADO DO AGENTE POLKIT (a diretriz
/// do polkit ÚNICO): o lxqt-policykit instala o
/// /etc/xdg/autostart/lxqt-policykit-agent.desktop e o XDG autostart
/// lança um SEGUNDO agente ao lado do supervisionado (~37,7 MB de Qt6
/// vivo à toa). A cura é o SUPRESSOR POR USUÁRIO da gramática XDG:
/// ~/.config/autostart/lxqt-policykit-agent.desktop com Hidden=true —
/// o mesmo basename vence o do sistema e o lança-agente pula a entrada;
/// o arquivo DO PACOTE nunca é tocado (zero conflito pacman, zero sed
/// em /etc na sessão). O AGENTE da casa é o da vaga supervisionada —
/// UM só. true = o supressor foi gravado (idempotente: presente = no-op).
fn entrega_mordaca_polkit(conf_base: &std::path::Path) -> bool {
    let alvo = conf_base.join("autostart").join("lxqt-policykit-agent.desktop");
    if alvo.exists() {
        return false; // já amordaçado (ou o dono escreveu o dele — intocado)
    }
    let corpo = "[Desktop Entry]\n\
                Type=Application\n\
                Name=lxqt-policykit-agent\n\
                Hidden=true\n\
                NoDisplay=true\n\
                X-GNOME-Autostart-enabled=false\n\
                # E151 (archcraft-elite): o agente polkit da casa é o da\n\
                # vaga supervisionada do elite-daemon — UM só na sessão.\n";
    std::fs::create_dir_all(conf_base.join("autostart")).is_ok() && std::fs::write(&alvo, corpo).is_ok()
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
#[derive(Default)]
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
/// E150 — O RELOGIN LIMPO (a ordem do dono, base 1.0-98): o `labwc
/// --exit` deixava o daemon da sessão ANTERIOR vivo por instantes
/// (órfão de relogin — o SIGHUP da era matava sem a saída limpa) e o
/// `/run/user/$UID/elite` carregava locks/sockets órfãos que MENTIAM
/// à sessão nova: o `elite-daemon session` recusado pelo flock do
/// irmão morto-vivo saía 0 e o desktop acordava VAZIO (só o menu.xml).
/// A colheita é DUPLO:
///   · o DAEMON ÓRFÃO: o lock da sessão traz o PID do dono — se o
///     dono do flock é um elite-daemon VIVO cujo WAYLAND_DISPLAY já é
///     OUTRO (a sessão dele morreu), ele recebe SIGTERM (a saída limpa
///     dele despeja os filhos e solta a trava) e a espera curta (3s)
///     confere a entrega;
///   · os FÓSSEIS do chão: com o lock NOSSO na mão, o resto órfão do
///     dir (bus.sock, resident-*.lock, *.pid) é de sessão MORTA por
///     definição — sai (o bind do bus refaz o fio; os residentes ganham
///     locks novos no próximo spawn). A varredura corre ANTES do
///     liga_bus da própria sessão (o sweep não pode comer o fio que
///     ainda nem nasceu) e PRESERVA os stamps display-* do frame 0
///     (o apply-boot desta sessão acabou de escrevê-los — a máquina de
///     estados do craft-display confia neles).
/// Err = o irmão recusa morrer (sessão REALMENTE viva — a 2ª instância
/// sai 0 como sempre, o papel do supervise.rs já fala isso).
pub fn colhe_relogin() -> Result<(), String> {
    let uid = unsafe { libc::getuid() };
    let lock = elite_core::session_lock_path(uid);
    // o lock PRIVADO não existe ainda? o chão pode TER fóssil de crash
    // (o daemon morreu sem saída limpa) — a varredura segue do mesmo
    // jeito (não há dono vivo para mentir)
    if lock.exists() && !peek_lock_livre(&lock) {
        // o NOSSO WAYLAND_DISPLAY é a prova da sessão VIVA: sem ele
        // (CLI/probe/teste) ninguém aqui pode julgar o dono do lock —
        // a recusa honesta vale (a 2ª instância sai 0 como sempre)
        let nosso = crate::wayland_pronto_nome();
        if nosso.is_empty() {
            return Err(format!(
                "o lock {} tem dono e este corpo não é sessão gráfica — sai 0 (flock E30)",
                lock.display()
            ));
        }
        // o dono do flock: lê o PID que ele deixou no arquivo
        let pid = std::fs::read_to_string(&lock)
            .ok()
            .and_then(|t| t.trim().parse::<i32>().ok());
        let mut colhido = false;
        // 1.0-102 — O JULGAMENTO PELA IDENTIDADE DA SESSÃO (audit 102: a
        // sessão nova batia no flock do irmão de sessão MORTA e acordava
        // VAZIA): o XDG_SESSION_ID é a identidade de verdade — muda a
        // CADA login; no mesmo rig o WAYLAND_DISPLAY é wayland-0 EM
        // TODAS as sessões e o julgamento só dele deixava o órfão vivo).
        // Órfão de sessão encerrada = SIGTERM (a saída limpa dele entrega
        // a vaga); teimoso = o lock do chão SAI (a trava é do inode, o
        // ARQUIVO não pode mentir à sessão nova — assumir imediatamente).
        let mut orfao = false;
        if let Some(pid) = pid {
            if pid > 1
                && unsafe { libc::kill(pid, 0) } == 0
                && comm_do_pid(pid) == "elite-daemon"
            {
                let veredito = julga_orfao_relogin(
                    &var_do_pid(pid, "XDG_SESSION_ID"),
                    &std::env::var("XDG_SESSION_ID").unwrap_or_default(),
                    &wayland_do_pid(pid),
                    &nosso,
                );
                if veredito {
                    orfao = true;
                    eprintln!(
                        "elite-daemon: o irmão pid {pid} segurava o lock de uma sessão ENCERRADA (identidade divergente) — SIGTERM (a saída limpa dele entrega a vaga)"
                    );
                    unsafe { libc::kill(pid, libc::SIGTERM) };
                    for _ in 0..30 {
                        if peek_lock_livre(&lock) {
                            colhido = true;
                            break;
                        }
                        std::thread::sleep(Duration::from_millis(100));
                    }
                }
            }
        }
        if !colhido && !peek_lock_livre(&lock) {
            if orfao {
                // 1.0-102 — O ÓRFÃO TEIMOSO: a sessão dele MORREU (a
                // identidade divergiu) — o lock do chão sai e a sessão
                // NOVA o assume imediatamente (o flock velho morre com o
                // inode velho; o irmão já recebeu o SIGTERM e desce pelo
                // fim_da_sessao dele)
                let _ = std::fs::remove_file(&lock);
                eprintln!(
                    "elite-daemon: o irmão órfão não soltou em 3s — o lock {} saiu do chão e a sessão nova o ASSUME (audit 102)",
                    lock.display()
                );
            } else {
                return Err(format!(
                    "o lock {} segue com dono vivo da MESMA sessão — a 2ª instância sai 0 (flock E30; a sessão REAL não é colhida)",
                    lock.display()
                ));
            }
        }
    }
    // o chão é NOSSO: varre os fósseis (bus.sock, resident-*.lock,
    // *.pid — os stamps display-* do frame 0 desta sessão ficam)
    let mut varridos = 0usize;
    if let Ok(dir) = std::fs::read_dir(run_dir()) {
        for e in dir.flatten() {
            let nome = e.file_name();
            let nome = nome.to_string_lossy().to_string();
            if nome == "session.lock" || nome.starts_with("display-") {
                continue;
            }
            if std::fs::remove_file(e.path()).is_ok() {
                varridos += 1;
            }
        }
    }
    if varridos > 0 {
        eprintln!(
            "elite-daemon: {varridos} fóssil(eis) da sessão anterior varrido(s) de {} (bus.sock/locks/pid — o relogin nasce limpo)",
            run_dir().display()
        );
    }
    Ok(())
}

/// o comm de um PID (vazio = inobservável).
fn comm_do_pid(pid: i32) -> String {
    std::fs::read_to_string(format!("/proc/{pid}/comm"))
        .unwrap_or_default()
        .trim_end()
        .to_string()
}

/// 1.0-102 — o valor de CHAVE no environ NUL-separado de um PID (vazio =
/// ausente/inobservável; o root e o morto não têm — o imune de sempre).
fn var_do_pid(pid: i32, chave: &str) -> String {
    match std::fs::read(format!("/proc/{pid}/environ")) {
        Ok(bytes) => var_de_environ(&bytes, chave),
        Err(_) => String::new(),
    }
}

/// 1.0-102 — o parse do environ de um PID (função PURA, a porta dos
/// testes): NUL-separado, CHAVE=valor, o primeiro casamento vence.
pub fn var_de_environ(bytes: &[u8], chave: &str) -> String {
    let prefix = format!("{chave}=");
    bytes
        .split(|b| *b == 0)
        .filter_map(|kv| std::str::from_utf8(kv).ok())
        .find_map(|kv| kv.strip_prefix(&prefix))
        .unwrap_or("")
        .to_string()
}

/// o WAYLAND_DISPLAY de um PID (vazio = inobservável; o root e o morto
/// não têm — o imune de sempre).
fn wayland_do_pid(pid: i32) -> String {
    var_do_pid(pid, "WAYLAND_DISPLAY")
}

/// 1.0-102 — O VEREDITO DO ÓRFÃO DO RELOGIN (função PURA, a porta dos
/// testes): o dono do lock é órfão quando a IDENTIDADE da sessão dele
/// diverge da nossa.
///   · o XDG_SESSION_ID é a identidade de verdade: muda a CADA login (o
///     logind crava um por sessão); PRESENTE nos dois lados e DIVERGENTE
///     = a sessão do dono do lock ENCERROU — o relogin do mesmo rig é
///     sessão OUTRA, mesmo com o WAYLAND_DISPLAY de mesmo nome;
///   · o WAYLAND_DISPLAY é a REDE da era E150: no mesmo rig o nome é
///     wayland-0 em TODAS as sessões (o julgamento só dele era o buraco
///     que o audit 102 fotografou — o órfão ficava vivo no lock e a
///     sessão nova nascia vazia); identidade AUSENTA de um lado = o
///     mundo sem logind/ambiente e a régua de sempre manda (só o fio).
pub fn julga_orfao_relogin(dele_sessao: &str, nosso_sessao: &str, dele_wl: &str, nosso_wl: &str) -> bool {
    if !dele_sessao.is_empty() && !nosso_sessao.is_empty() {
        return dele_sessao != nosso_sessao;
    }
    dele_wl != nosso_wl
}

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
    // E150 — A VAGA DO WALLPAPER (a garantia de TODO login): o swaybg
    // deixou de ser spawn do autostart (UM lançador só — a lei E137 de
    // sempre) e vira vaga supervisionada: caiu → volta em 2s, o guard
    // por comm ADOTA o que já está de pé (a sessão nunca soma o
    // segundo) e o comando nasce do MESMO endereço de sempre — o PNG
    // curado da casa, o JPG do dono como queda e o preto AMOLED de
    // fábrica quando nenhum existe (a gramática do autostart velho,
    // agora supervisionada).
    let home = std::env::var("HOME").unwrap_or_default();
    let comando_wall = if !home.is_empty()
        && PathBuf::from(&home).join(".config/labwc/wallpaper.png").exists()
    {
        "swaybg -m fill -i $HOME/.config/labwc/wallpaper.png".to_string()
    } else if !home.is_empty()
        && PathBuf::from(&home).join(".config/labwc/wallpaper.jpg").exists()
    {
        "swaybg -m fill -i $HOME/.config/labwc/wallpaper.jpg".to_string()
    } else {
        "swaybg -m fill -c #000000".to_string()
    };
    specs.push(VagaSpec {
        res: Residente {
            nome: "wallpaper".to_string(),
            comando: comando_wall,
            bus: None,
        },
        comm: Some("swaybg".to_string()),
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
    // E150 — O PID NO LOCK (a identidade do dono da vaga: o relogin
    // lê este número para julgar o órfão — ver colhe_relogin; a
    // varredura dos fósseis do chão já correu LÁ, antes do liga_bus).
    if porta == "session" {
        use std::io::Write;
        let _ = f.set_len(0);
        if let Ok(mut fh) = f.try_clone() {
            let _ = writeln!(fh, "{}", std::process::id());
        }
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

    // 1.0-102 — O CÃO DE GUARDA DO COMPOSITOR (a 2ª via do fim da sessão):
    // a 1ª via é o EPIPE/EOF do fio Wayland (fim_da_sessao no wayland.rs);
    // ESTA é a rede — o fio pode morrer SEM erro visível (dispatch que
    // não acorda, sessão nascida antes do socket) e o socket do
    // WAYLAND_DISPLAY SUMIR do chão é a prova do chão: visto VIVO uma
    // vez, o sumiço é o compositor encerrado — a casa desce INTEIRA
    // (relogin limpo: filhos encerrados, lock fora do chão, exit 0).
    let mut viu_wayland = crate::wayland_pronto();

    loop {
        if porta == "session" {
            if crate::wayland_pronto() {
                viu_wayland = true;
            } else if viu_wayland {
                crate::fim_da_sessao(
                    "o socket do WAYLAND_DISPLAY SUMIU do chão (compositor encerrado)",
                );
                viu_wayland = false; // o vigia de teto do fim já nasceu
            }
        }
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
            let trava = tenta_trava(&v.res.nome).ok();
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
            //    (c') E149 — a pele do swaync ANTES do fork: o rig que
            //        antecedeu a dose acorda o painel SEM o conf — o
            //        "Config not found!" do dump morre no ÚLTIMO portão
            //        (o skel entrega; o presente do dono nunca é tocado).
            if v.res.nome == "swaync" {
                let conf_base = std::env::var("XDG_CONFIG_HOME")
                    .map(PathBuf::from)
                    .unwrap_or_else(|_| {
                        PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".config")
                    });
                // 1.0-102→1.0-104 — A CADEIA DE MESTRES: o pacote primeiro
                // (o mestre da dose), o skel do rig de segundo (o pacote
                // o entrega desde a 1.0-104) e o /etc/xdg como a ÚLTIMA
                // rede (o DEFAULT do próprio swaync upstream — a casa
                // não disputa o caminho do alheio, mas quem existe veste)
                let mestres = [
                    PathBuf::from("/usr/local/share/elite/swaync"),
                    PathBuf::from("/etc/skel/.config/swaync"),
                    PathBuf::from("/etc/xdg/swaync"),
                ];
                let entregues = entrega_pele_swaync(&mestres, &conf_base.join("swaync"));
                if entregues > 0 {
                    eprintln!(
                        "elite-daemon supervise: swaync pele ENTREGUE do mestre da dose ({}) — o \"Config not found!\" morre no último portão",
                        entregues
                    );
                }
            }
            //    (c'') E151 — A MORDAÇA DO AUTOSTART DO AGENTE (a diretriz
            //        do polkit ÚNICO): o lxqt-policykit traz o
            //        /etc/xdg/autostart/lxqt-policykit-agent.desktop —
            //        a sessão nascia com DOIS agentes (o do XDG autostart
            //        + o supervisionado, ~37 MB de Qt6 duplicado). O
            //        supressor POR USUÁRIO (~/.config/autostart com o
            //        MESMO basename e Hidden=true — a gramática XDG) mata
            //        o duplo SEM tocar o arquivo do pacote (zero conflito
            //        pacman); o AGENTE da casa é o da vaga supervisionada.
            if v.res.nome == "policykit" {
                let conf_base = std::env::var("XDG_CONFIG_HOME")
                    .map(PathBuf::from)
                    .unwrap_or_else(|_| {
                        PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".config")
                    });
                if entrega_mordaca_polkit(&conf_base) {
                    eprintln!(
                        "elite-daemon supervise: agente polkit ÚNICO (o autostart duplicado do lxqt-policykit amordaçado por usuário — E151)"
                    );
                }
            }
            match lanca(&v.res.comando, &log, &v.res.nome) {
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
        // SIGTERM/SIGINT (e o SIGHUP do relogin E150, e o STOP do
        // fim_da_sessao 1.0-102): SIGTERM aos filhos NOSSOS, espera a
        // colheita, e — na porta session — o LOCK SAI DO CHÃO (a
        // sentença do audit 102: o flock é estado do INODE, o processo
        // morto solta a trava, mas o ARQUIVO parado no chão MENTIA à
        // sessão nova; a saída limpa remove o que criou), sai limpo
        // (os adotados morrem com a sessão — não são filhos).
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
            if porta == "session" {
                // 1.0-102 — o lock da SESSÃO sai do CHÃO na saída limpa
                // (o path REAL que esta porta travou — privado OU o
                // fallback; o fim_da_sessao do audit 102 pediu o chão
                // varrido para o relogin que nasce no segundo seguinte)
                let _ = std::fs::remove_file(&lock);
                eprintln!(
                    "elite-daemon session: saída limpa — filhos encerrados, session.lock fora do chão ({} — 1.0-102)",
                    lock.display()
                );
            } else {
                eprintln!("elite-daemon supervise: SIGTERM — filhos encerrados, saída limpa");
            }
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
             swayosd::swayosd-server\n",
        );
        assert_eq!(r.len(), 2, "comentário e linha vazia não são residentes");
        assert_eq!(r[0].nome, "swaync");
        assert_eq!(r[0].comando, "swaync");
        assert_eq!(r[0].bus, None, "gramática velha = sem gate de bus");
        assert_eq!(r[1].comando, "swayosd-server");
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
        assert!(nomes.contains(&"swayosd"));
        // E151 — o udiskie SAI da fila (o debloat extremo: o Python
        // residente de 58,5 MB morre — o automount é a regra udev
        // 91-elite-automount, oneshot POR EVENTO, zero daemon)
        assert!(
            !nomes.contains(&"udiskie"),
            "udiskie não é mais residente (E151 — automount por regra udev)"
        );
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

    // ── 1.0-100 — A VARREDURA DOS LOCKS ÓRFÃOS (audit 99 §2) ─────────

    fn dir_teste(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!(
            "elite-lock-orfao-{tag}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn a_varredura_tira_o_orfao_vazio_e_o_pid_morto() {
        // as DUAS classes do audit 99: o lock vazio da era legada
        // (0 bytes, dono já morto) e o lock com PID que não existe mais
        let d = dir_teste("vazio-morto");
        std::fs::write(d.join("elite-daemon-session.lock"), b"").unwrap();
        std::fs::write(d.join("elite-daemon.lock"), b"999999\n").unwrap(); // PID improvável
        // um NÃO-da-casa no mesmo dir: não é da família, fica
        std::fs::write(d.join("outro.lock"), b"").unwrap();
        let saidos = limpa_locks_orfos_em(&d);
        assert_eq!(saidos, 2, "vazio + PID morto saem; o estranho fica");
        assert!(!d.join("elite-daemon-session.lock").exists());
        assert!(!d.join("elite-daemon.lock").exists());
        assert!(d.join("outro.lock").exists());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn a_varredura_respeita_o_dono_vivo() {
        // um lock FLOCKADO por este mesmo processo: portão 1 recusa —
        // o arquivo fica (mesmo com o PID de outro morto dentro)
        let d = dir_teste("dono-vivo");
        let caminho = d.join("elite-daemon.lock");
        let f = std::fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .write(true)
            .open(&caminho)
            .unwrap();
        let rc = unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
        assert_eq!(rc, 0);
        std::fs::write(&caminho, b"999999\n").unwrap();
        let saidos = limpa_locks_orfos_em(&d);
        assert_eq!(saidos, 0, "dono vivo = intocado");
        assert!(caminho.exists());
        drop(f); // o flock morre com o fd
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn a_varredura_respeita_o_pid_vivo_registrado() {
        // lock TRAVÁVEL (sem dono de flock) mas com o PID de um processo
        // VIVO (este teste): o portão 2 é conservador — não toca
        let d = dir_teste("pid-vivo");
        let caminho = d.join("elite-daemon-game.lock");
        std::fs::write(&caminho, format!("{}\n", std::process::id())).unwrap();
        let saidos = limpa_locks_orfos_em(&d);
        assert_eq!(saidos, 0, "PID vivo registrado = conservador não toca");
        assert!(caminho.exists());
        let _ = std::fs::remove_dir_all(&d);
    }

    // ── 1.0-102 — O JULGAMENTO DO ÓRFÃO DO RELOGIN (audit 102) ──────────

    #[test]
    fn e102_o_environ_do_pid_e_parseado_nul_separado() {
        // o environ do kernel é NUL-separado: a chave certa vence, a
        // ausente é vazia, o valor vazio não inventa
        let env = b"HOME=/home/dono\0XDG_SESSION_ID=42\0WAYLAND_DISPLAY=wayland-0\0\0";
        assert_eq!(var_de_environ(env, "XDG_SESSION_ID"), "42");
        assert_eq!(var_de_environ(env, "WAYLAND_DISPLAY"), "wayland-0");
        assert_eq!(var_de_environ(env, "DBUS_SESSION_BUS_ADDRESS"), "");
        assert_eq!(var_de_environ(b"", "XDG_SESSION_ID"), "");
    }

    #[test]
    fn e102_o_relogin_de_mesmo_wayland_e_orfao_pela_identidade() {
        // O CASO do audit 102: no mesmo rig o WAYLAND_DISPLAY é
        // wayland-0 EM TODAS as sessões — só o XDG_SESSION_ID distingue
        // a sessão morta da viva (muda a cada login)
        assert!(
            julga_orfao_relogin("41", "42", "wayland-0", "wayland-0"),
            "sessão de IDENTIDADE outra = órfão, mesmo wayland-0 nos dois lados"
        );
        // a MESMA sessão (identidade igual): o dono é legítimo — nunca colhido
        assert!(
            !julga_orfao_relogin("42", "42", "wayland-0", "wayland-0"),
            "identidade IGUAL = a MESMA sessão: o flock E30 manda (2ª instância sai 0)"
        );
    }

    #[test]
    fn e102_sem_identidade_a_regua_do_wayland_manda() {
        // o mundo sem logind (identidade ausente de um lado): a régua da
        // era E150 decide sozinha — o WAYLAND_DISPLAY divergente é órfão
        assert!(
            julga_orfao_relogin("", "42", "wayland-1", "wayland-0"),
            "sem identidade + WAYLAND outro = órfão (a régua de sempre)"
        );
        assert!(
            !julga_orfao_relogin("41", "", "wayland-0", "wayland-0"),
            "sem identidade + mesmo WAYLAND = o dono segue vivo e legítimo"
        );
        // a sessão de teste (sem nada): o WAYLAND vazio do irmão de CLI
        // segue divergente como na era de sempre
        assert!(julga_orfao_relogin("", "", "", "wayland-0"));
    }
}
