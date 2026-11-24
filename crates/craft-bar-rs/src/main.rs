// ELITE · craft-bar-rs — main.rs (E140). A TOP BAR nativa da casa:
// a aposentadoria do waybar (a ordem do dono, dossiê 1.0-80→1.0-88 —
// "100% Rust Nativo na Interface Própria"). Um binário, GTK4 +
// gtk4-layer-shell, falando wpctl/nmcli/swaync-client pelos filhos
// curtos que a casa já tem e ouvindo o elite-daemon pelos sinais
// SIGRTMIN+8/+9 (o modo de jogo e os 2º planos acendem por EVENTO,
// nunca por polling dos 3s da era waybar).
//
// A ARQUITETURA (a lei do degrau — ver Cargo.toml):
//   · state.rs — o NÚCLEO PURO (datas pt_BR, parsers, glifos,
//     debounce): std-only, testado em qualquer lugar;
//   · ui.rs    — a camada GTK4/layer-shell (feature "gui" — o CI do
//     pacote valida; o sandbox sem GTK testa o núcleo).
//
// O QUE A BARRA FAZ (a diretriz do dossiê, item por item):
//   · APPS (nwg-drawer): abre/fecha NO released com debounce real de
//     150ms — o toggle é pelo FILHO próprio (nada de pgrep às cegas;
//     o stderr da gaveta vai para /dev/null: o spawn/kill a cada 1-2s
//     do bars.log do dump era o ECO da era shell, não a gaveta);
//   · RELÓGIO pt_BR FIXO ("Seg, 23 Nov · 19:30") que NUNCA muda de
//     texto ao clicar: esquerdo alterna o painel do swaync, direito
//     alterna o DND — o texto é UM só;
//   · ÁUDIO pelo wpctl: esquerdo = MUTE instantâneo do sink padrão,
//     scroll = volume, direito = pwvucontrol (o mixer de verdade);
//   · MIC: esquerdo = mute instantâneo da fonte padrão (realce .muted
//     quando mudo), direito = pwvucontrol;
//   · REDE PERSISTENTE: o botão NÃO EXISTE a estado "sumido" — Cabo /
//     Wi-Fi / Desligado têm glifo e tooltip SEMPRE; esquerdo abre o
//     iwgtk, direito o nm-connection-editor;
//   · BLUETOOTH dedicado: o estado pelo bluetoothctl, o clique abre o
//     blueman-manager (as ferramentas de verdade da diretriz);
//   · MODO DE JOGO: pill que acende no SIGRTMIN+8 do elite-daemon (o
//     mesmo contrato da era waybar — o daemon avisa, a barra acende);
//   · PLAYER: o craft-player state a cada 1s (a casa E124, intacta);
//   · 2º PLANOS: craft-bgapps no SIGRTMIN+9 (o evento E135, intacto);
//   · SESSÃO: GtkPopoverMenu NATIVO — Bloquear / Suspender / Reiniciar
//     / Desligar / Encerrar sessão. SEM fuzzel e SEM can-suspend: o
//     sleep.conf da casa já disse AllowSuspend=yes (E122), o
//     `systemctl suspend` é a palavra final.
//
// ESCOPO HONESTO DESTA v1 (o que FALTA, nomeado):
//   ✗ o CALENDÁRIO do tooltip do relógio (o swaync tem o próprio
//     painel com calendário — o clique esquerdo o abre; o tooltip da
//     barra mostra a data completa em pt_BR, sem o <tt>{calendar}</tt>
//     que era do waybar);
//   ✗ a TRAY SNI (a v2.3.6 aposentou por inconsistência de glifos —
//     o nm-applet era o único inquilino; a rede agora é botão próprio
//     com ferramentas de verdade);
//   ✗ o MODO CLARO/ESCURO dinâmico (a pele é o bar.css da casa, o
//     dono edita ~/.config/elite/bar.css e a barra relê no SIGUSR2).
mod state;

#[cfg(feature = "gui")]
mod ui;

use std::path::PathBuf;

/// A versão do corpo (a dose E140 — o waybar 0.16 foi o último
/// motor alheio da top bar da casa).
pub const VERSION: &str = "1.0.0";

// ── os caminhos da casa (os MESMOS lugares da família elite/) ──────────

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

/// ~/.config/elite/bar.css (a pele da barra — a MESMA gramática do
/// dock.css: o skel traz a da casa, o dono edita a dele e ela vence;
/// SIGUSR2 relê sem renascer).
/// 2.0 — o BUS VIVO do elite-daemon (o mesmo contrato do elite-core):
/// os estados (mesa, mídia, janelas, jogo) chegam pelo fio; os pedidos
/// (PlayPause, workspace, jogo) voltam por Req.
pub fn bus_sock() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| format!("/run/user/{}", current_uid()).into())
        .join("elite/bus.sock")
}

pub fn css_path() -> PathBuf {
    xdg_dir(".config").join("elite/bar.css")
}

/// ~/.cache/elite/bar.log (a evidência append-only da barra, teto
/// 1 MiB — a lei E36 da família; o stderr da barra segue indo para o
/// bars.log pelo pai elite-daemon session, este papel é o DIÁRIO
/// PRÓPRIO das decisões de UI: toggle do drawer, trocas de estado).
pub fn log_path() -> PathBuf {
    cache_dir().join("elite/bar.log")
}

/// A evidência append-only (teto 1 MiB — recente vale mais; NUNCA
/// derruba a barra, erro engolido de propósito).
pub fn log(msg: &str) {
    log_to(&log_path(), msg);
}

/// O corpo do log (path PARAMETRIZADO — o teste prova o teto em cima
/// de um arquivo de mentira em temp dir; herda a gramática da dock).
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

/// O uid corrente (o scanner do drawer mata só a gaveta DO DONO).
pub fn current_uid() -> u32 {
    std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("Uid:"))
                .and_then(|l| l.split_whitespace().nth(1).and_then(|u| u.parse().ok()))
        })
        .unwrap_or(0)
}

// ── o main: com gui, a barra; sem gui, uma mensagem HONESTA ───────────

#[cfg(feature = "gui")]
fn main() {
    // o --help ANTES de qualquer GTK (a lei E90: a descoberta não
    // depende de biblioteca gráfica instalada)
    let args: Vec<String> = std::env::args().collect();
    if args.len() > 1 && ["-h", "--help", "uso"].contains(&args[1].as_str()) {
        println!(
            "uso: craft-bar-rs — a TOP BAR nativa da casa (GTK4 + layer-shell; a\n\
             \x20    aposentadoria do waybar, E140; sem argumentos)\n\
             \n\
             \x20  esquerdo: o verbo principal de cada botão · direito: a ferramenta\n\
             \x20  completa (pwvucontrol/iwgtk/nm-connection-editor/DND)\n\
             \x20  · apps: abre/fecha a gaveta (150ms de debounce)\n\
             \x20  · relógio: painel do swaync (esq) / DND (dir) — o texto NUNCA\n\
             \x20    muda ao clicar\n\
             \x20  · áudio/mic: wpctl mute no clique · sessão: popover nativo\n\
             \x20  (Bloquear/Suspender/Reiniciar/Desligar/Encerrar)\n\
             \x20  SIGRTMIN+8: pill do modo de jogo (o elite-daemon avisa) ·\n\
             \x20  SIGRTMIN+9: apps em 2º plano · SIGUSR2: relê o bar.css.\n\
             \x20  Chamada pelo elite-daemon session; rodar na mão nasce barra\n\
             \x20  duplicada (lei E30)."
        );
        return;
    }
    // 2.0 — sem gui, a mensagem honesta nomeia o fio da sessão (o contrato
    // do elite-core): onde a barra assina quando a gui existir
    let uid = crate::state::uid_do_processo();
    println!(
        "elite-core: o bus da sessão vive em {:?}",
        elite_core::bus_sock_path(uid)
    );
    if std::env::var_os("WAYLAND_DISPLAY").is_none() {
        log("sem WAYLAND_DISPLAY — saindo (a barra só vive na sessão)");
        eprintln!("craft-bar: sem WAYLAND_DISPLAY — a barra só vive na sessão");
        std::process::exit(0);
    }
    std::process::exit(ui::run());
}

#[cfg(not(feature = "gui"))]
fn main() {
    // Compilado SEM a feature "gui": este binário é o NÚCLEO de
    // lógica (state.rs) + os testes da casa — a camada GTK exige o
    // pkg-config gtk4 do ambiente de build do pacote. NUNCA uma
    // barra fantasma silenciosa: quem rodar isto recebe a verdade e
    // um exit != 0.
    eprintln!(
        "craft-bar-rs {VERSION} — compilado SEM a feature 'gui': este binário\n\
         \x20é só o núcleo de lógica (datas pt_BR/parsers/glifos/debounce) e os\n\
         \x20testes da casa. A barra de verdade nasce com `cargo build --release`\n\
         \x20(feature gui ON — exige GTK4 dev no ambiente, o makedepends do PKGBUILD)."
    );
    std::process::exit(1);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn caminhos_sao_os_da_familia_elite() {
        assert!(css_path().ends_with("elite/bar.css"));
        assert!(log_path().ends_with("elite/bar.log"));
    }

    #[test]
    fn log_append_only_com_teto() {
        let dir = std::env::temp_dir().join(format!("craft-bar-log-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let f = dir.join("bar.log");
        std::fs::write(&f, vec![b'x'; 1_048_577]).unwrap();
        // o teto de 1 MiB zera o arquivo e a linha nova entra sozinha
        log_to(&f, "a linha nova depois do teto");
        let txt = std::fs::read_to_string(&f).unwrap();
        assert_eq!(txt, "a linha nova depois do teto\n");
        // abaixo do teto: append puro
        log_to(&f, "a segunda linha");
        let txt2 = std::fs::read_to_string(&f).unwrap();
        assert_eq!(txt2.lines().count(), 2);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
