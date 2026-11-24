// ELITE · craft-dock-rs — main.rs (E132). A dock (taskbar) da casa em
// Rust: o corpo do craft-dock-gui (PyGObject, 2137 linhas) traduzido
// para gtk-rs + gtk4-layer-shell, ~40MB de RAM do Python fora.
//
// A ARQUITETURA (a lei do degrau — ver Cargo.toml):
//   · icons.rs  — identidade e ícone (PURE, testado local);
//   · procapp.rs — a sonda /proc do AppImage (PURE, testado local);
//   · sock.rs   — o protocolo do craft-toplevel + a gramática de
//     casamento de janelas (PURE + cliente UnixStream, testado local);
//   · ui.rs     — a camada GTK4/layer-shell (feature "gui" — compila
//     só onde há GTK dev; o CI do pacote é quem a valida).
//
// ESCOPO HONESTO DESTA v0.1 (o que foi PORTADO do Python):
//   ✓ pins (~/.config/elite/dock-pins — 1 desktop-id por linha, 2ª
//     coluna = hint de app_id, '#' é comentário; pin inválido é
//     ignorado com log, NUNCA crash — a lei da run #93);
//   ✓ a gramática UMA do clique: esquerdo foca/cicla (toggle MIN no
//     app focado, E89) · direito NOVA SESSÃO (o Exec do .desktop; no
//     raw, o argv[0] provado no /proc) · meio encerra (CLOSE por id,
//     strict E36);
//   ✓ o snapshot do toplevel.sock em leitura ASSÍNCRONA (thread de
//     fundo + glib MainContext channel — LIST de 5s de segurança E o
//     canal de eventos EVT do E38 com latência ~0);
//   ✓ indicador "running" pela JANELA REAL (v2.10.3), dinâmicos com o
//     índice comm→.desktop, botões RAW com a denylist E106;
//   ✓ A CADEIA DE ÍCONES E130 completa (tema/fold → steam → Gear
//     Lever → cache sha256 → .DirIcon do mount vivo → extração em
//     THREAD com atualização via MainContext → glifo honesto) E o
//     matching reverse-DNS dos Flatpaks com ícone oficial dos exports
//     (E132 — a ordem do dono); E133: o degrau WINE/PROTON (o .exe do
//     cmdline → o cache exe-icons → os caches de jogo Steam/Lutris/
//     Heroic/Hydra → o ícone adjacente → a extração do recurso PE
//     embutido em THREAD) e o degrau BINÁRIO CUSTOM (ícone adjacente
//     ao /proc/<pid>/exe de Electron/Snap/Nix/portables);
//   ✓ o guard de lançamento de 8s (E71: o clique no vão não duplica)
//     com a liberação no MAP (E88) e a ceifa dos filhos zumbis;
//   ✓ E134 — a SINCRONIZAÇÃO IMEDIATA com o snapshot real: a graça do
//     vazio E71 (LIST vazio segurado 2 rodadas) APOSENTADA — o
//     indicador preso após fechar janelas transitórias morreu com ela;
//   ✓ SIGUSR1 = toggle W-S-d · SIGUSR2 = reload dos pins (v2.5.0).
// O QUE NÃO FOI PORTADO (nomeado, nunca escondido):
//   ✗ o MENU do direito E74 (craft-menu/fuzzel): o direito é o verbo
//     DIRETO "nova sessão" da gramática v2.10.10 — sem menu nesta v1;
//   ✗ o FALLBACK wlrctl (daemon morto = /proc + wlrctl com as 3
//     formas canônicas): a dock Rust assume o craft-toplevel VIVO —
//     sem daemon os verbos de foco/fecho ficam sem rede NESTA v1;
//   ✗ a E101 completa (a graça de 3s da classe daemonizada): o guard
//     aposenta no MAP, no expiry de 8s ou na morte do lançador — sem
//     o meio-tempo recursivo do Python;
//   ✗ a transição suave v2.11 (GtkRevealer) e a higiene E129 de
//     pixbufs (a GTK4 usa texturas próprias — o leak da GTK3 não se
//     aplica igual, mas a transição animada falta);
//   ✗ o _dismiss_overlays (pkill nwg-drawer) e o casaco de terminal
//     "foot" nos TUI fica no exec_ready (ESSE foi portado).
// E134 — A DOCK É DEFINITIVAMENTE ESTA: o craft-dock-gui Python saiu do
// pacote e da árvore (a migração da ordem do dono — o craft-bars lança
// SÓ o binário Rust; o post_upgrade remove o arquivo velho e encerra o
// processo Python vivo dos rigs da dose anterior).
mod icons;
mod procapp;
mod sock;

#[cfg(feature = "gui")]
mod ui;

use std::path::PathBuf;

/// E132 — a versão do corpo Rust (o corpo Python v2.10.x foi APOSENTADO
/// pela E134: esta é a ÚNICA dock da casa).
pub const VERSION: &str = "0.1.0";

/// Um pin do dock-pins: o desktop-id (coluna 1) e o hint de app_id
/// opcional (coluna 2 — para apps que se apresentam com um id que nem
/// o StartupWMClass nem o binário adivinham).
#[derive(Debug, Clone, Default)]
pub struct Pin {
    pub desktop_id: String,
    pub hint: String,
}

/// Lê o arquivo de pins (PURE — o teste alimenta um arquivo de mentira
/// em temp dir). Pin inválido não derruba a dock: linha ruim é pulada,
/// '#' é comentário, arquivo ilegível = lista vazia (v2.1.1/v2.5.0).
pub fn read_pins(path: &std::path::Path) -> Vec<Pin> {
    let mut pins = Vec::new();
    let Ok(txt) = std::fs::read_to_string(path) else {
        return pins; // arquivo ausente/ilegível: dock VIVA e vazia
    };
    for line in txt.lines() {
        let parts: Vec<&str> = line.trim().split_whitespace().collect();
        if parts.is_empty() || parts[0].starts_with('#') {
            continue;
        }
        pins.push(Pin {
            desktop_id: parts[0].to_string(),
            hint: parts.get(1).unwrap_or(&"").to_string(),
        });
    }
    pins
}

// ── os caminhos da casa (os MESMOS que o craft-dock-gui APOSENTADO E134
//    usava: pins, CSS, log e cache de ícones ficam nos lugares que os
//    rigs já têm — nenhum outro binário os lê hoje) ───────────────────

pub fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/root"))
}

fn xdg_dir(fallback: &str) -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(fallback))
}

pub fn cache_dir() -> PathBuf {
    std::env::var_os("XDG_CACHE_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".cache"))
}

/// ~/.config/elite/dock-pins (gerido pelo craft-pin; skel de fábrica).
pub fn pins_path() -> PathBuf {
    xdg_dir(".config").join("elite/dock-pins")
}

/// ~/.config/elite/dock.css (a pele da pílula — a MESMA do Python).
pub fn css_path() -> PathBuf {
    xdg_dir(".config").join("elite/dock.css")
}

/// ~/.cache/elite/dock.log (evidência append-only, teto 1 MiB).
pub fn log_path() -> PathBuf {
    cache_dir().join("elite/dock.log")
}

/// ~/.cache/elite/appimage-icons (o cache E130 — o MESMO lugar que o
/// craft-dock-gui aposentado E134 usava: os rigs conservam os ícones
/// já extraídos pela era Python).
pub fn appicon_cache_dir() -> PathBuf {
    cache_dir().join("elite/appimage-icons")
}

/// ~/.cache/elite/exe-icons (E133 — o cache dos ícones extraídos do
/// .exe Wine/Proton: <sha256-do-caminho>.png, o MESMO formato do
/// appimage-icons; o recurso PE extraído uma vez serve para sempre).
pub fn exeicon_cache_dir() -> PathBuf {
    cache_dir().join("elite/exe-icons")
}

/// $XDG_RUNTIME_DIR/elite/toplevel.sock (o socket do craft-toplevel).
pub fn toplevel_sock() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            format!("/run/user/{}", procapp::current_uid()).into()
        })
        .join("elite/toplevel.sock")
}

/// A evidência append-only no dock.log (teto 1 MiB — recente vale
/// mais; log() NUNCA derruba a dock, OSError engolido de propósito).
pub fn log(msg: &str) {
    log_to(&log_path(), msg);
}

/// O corpo do log (path PARAMETRIZADO — o teste prova o teto em cima
/// de um arquivo de mentira em temp dir).
pub fn log_to(path: &std::path::Path, msg: &str) {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    if let Ok(meta) = std::fs::metadata(path) {
        if meta.len() > 1_048_576 {
            let _ = std::fs::write(path, b"");
        }
    }
    use std::io::Write;
    if let Ok(mut fh) = std::fs::OpenOptions::new().append(true).create(true).open(path) {
        let _ = writeln!(fh, "{msg}");
    }
}

// ── o main: com gui, a dock; sem gui, uma mensagem HONESTA ────────────

#[cfg(feature = "gui")]
fn main() {
    // o --help ANTES de qualquer GTK (a lei E90: a descoberta não
    // depende de biblioteca gráfica instalada)
    let args: Vec<String> = std::env::args().collect();
    if args.len() > 1 && ["-h", "--help", "uso"].contains(&args[1].as_str()) {
        println!(
            "uso: craft-dock — a DOCK nativa da casa (GTK4 + layer-shell; daemon\n\
             \x20    interno da sessão; sem argumentos)\n\
             \n\
             \x20  clique esquerdo: foca/cicla (app focado = MINIMIZA, toggle E89)\n\
             \x20  · meio: encerra · direito: nova janela/sessão\n\
             \x20  pins: ~/.config/elite/dock-pins (craft-pin) · W-S-d alterna\n\
             \x20  (SIGUSR1) · SIGUSR2 re-lê os pins · o papel mora em\n\
             \x20  ~/.cache/elite/dock.log. Chamada pelo craft-bars; rodar na\n\
             \x20  mão nasce dock duplicada (lei E30)."
        );
        return;
    }
    if std::env::var_os("WAYLAND_DISPLAY").is_none() {
        log("sem WAYLAND_DISPLAY — saindo (a dock só vive na sessão)");
        eprintln!("craft-dock: sem WAYLAND_DISPLAY — a dock só vive na sessão");
        std::process::exit(0);
    }
    std::process::exit(ui::run());
}

#[cfg(not(feature = "gui"))]
fn main() {
    // Compilado SEM a feature "gui": este binário é o NÚCLEO de
    // lógica (icons/procapp/sock) + os testes da casa — a camada GTK
    // (gtk4/gtk4-layer-shell) exige o pkg-config gtk4 do ambiente de
    // build do pacote. NUNCA uma dock fantasma silenciosa: quem rodar
    // isto recebe a verdade e um exit != 0.
    eprintln!(
        "craft-dock-rs {VERSION} — compilado SEM a feature 'gui': este binário\n\
         \x20é só o núcleo de lógica (protocolo/ícones//proc) e os testes da\n\
         \x20casa. A dock de verdade nasce com `cargo build --release` (feature\n\
         \x20gui ON — exige GTK4 dev no ambiente, o makedepends do PKGBUILD).\n\
         \x20elite-core: o bus da sessão vive em {:?} (o fio 2.0 que a dock\n\
         \x20assina quando a gui existir).",
        elite_core::bus_sock_path(uid_do_procfs())
    );
    std::process::exit(1);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pins_da_casa_com_hint_e_comentarios() {
        let dir = std::env::temp_dir().join(format!("craft-dock-rs-pins-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let f = dir.join("dock-pins");
        std::fs::write(
            &f,
            "# os fixados da casa\n\
             foot.desktop\n\
             thunar.desktop org.xfce.Thunar\n\
             \n\
             # um comentário no meio\n\
             io.github.kolunmi.Bazaar.desktop\n\
             linha-invalida-sem-ponto   \n",
        )
        .unwrap();
        let pins = read_pins(&f);
        assert_eq!(pins.len(), 4);
        assert_eq!(pins[0].desktop_id, "foot.desktop");
        assert_eq!(pins[0].hint, "");
        assert_eq!(pins[1].hint, "org.xfce.Thunar");
        assert_eq!(pins[3].desktop_id, "linha-invalida-sem-ponto");
        // arquivo ausente: lista VAZIA (a dock vive — run #93 nunca mais)
        assert!(read_pins(&dir.join("nao-existe")).is_empty());
    }

    #[test]
    fn caminhos_sao_os_do_python() {
        // pins/log/cache nos MESMOS lugares que o craft-dock-gui usava
        // (a compatibilidade de estado sobreviveu à aposentadoria E134)
        assert!(pins_path().ends_with("elite/dock-pins"));
        assert!(css_path().ends_with("elite/dock.css"));
        assert!(log_path().ends_with("elite/dock.log"));
        assert!(appicon_cache_dir().ends_with("elite/appimage-icons"));
        assert!(exeicon_cache_dir().ends_with("elite/exe-icons"));
        assert!(toplevel_sock().ends_with("elite/toplevel.sock"));
    }

    #[test]
    fn log_append_only_com_teto() {
        let dir = std::env::temp_dir().join(format!("craft-dock-rs-log-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let f = dir.join("dock.log");
        std::fs::write(&f, vec![b'x'; 1_048_577]).unwrap();
        // o teto de 1 MiB zera o arquivo e a linha nova entra sozinha
        log_to(&f, "a linha nova depois do teto");
        let txt = std::fs::read_to_string(&f).unwrap();
        assert_eq!(txt, "a linha nova depois do teto\n");
        // abaixo do teto: append puro
        log_to(&f, "a segunda linha");
        let txt2 = std::fs::read_to_string(&f).unwrap();
        assert_eq!(txt2.lines().count(), 2);
    }
}

/// O uid REAL do processo (procfs — a mesma leitura honesta da casa).
#[cfg(not(feature = "gui"))]
fn uid_do_procfs() -> u32 {
    std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("Uid:"))
                .and_then(|l| l.split_whitespace().nth(1).and_then(|v| v.parse().ok()))
        })
        .unwrap_or(1000)
}
