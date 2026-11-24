// ═════════════════════════════════════════════════════════════════════════
// craft-tools — janela.rs (a camada GUI compartilhada — feature "gui").
// A PELE de todas as ferramentas: o THEME_CSS do elite-core embutido
// (a mesma cara da barra e da dock — a diretriz "no mesmo THEME_CSS"),
// a janela com o widget_name "toolswin"/"pickwin" que a folha mestra
// conhece, e o EXECUTOR do motor: o pkexec corre em thread de fundo,
// cada linha de output viaja ao TextView pelo canal (a UI NUNCA
// bloqueia — a mesma lei da barra desde E140).
// ═════════════════════════════════════════════════════════════════════════

#![cfg(feature = "gui")]

use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::mpsc::Receiver;

use gtk4::glib;
use gtk4::prelude::*;

/// a folha mestra + o override do dono (o mesmo contrato da barra e
/// da dock: a mestra é o FALLBACK; ~/.config/elite/tools.css é livre).
pub fn load_css() {
    let provider = gtk4::CssProvider::new();
    let mestra = elite_core::THEME_CSS;
    provider.load_from_data(mestra.as_bytes());
    // o override LIVRE do dono (se existe, soma — a mestra nunca sai)
    let caminho = crate::caminho_override();
    if let Ok(extra) = std::fs::read_to_string(&caminho) {
        provider.load_from_data(format!("{mestra}\n{extra}").as_bytes());
    }
    if let Some(disp) = gtk4::gdk::Display::default() {
        gtk4::style_context_add_provider_for_display(
            &disp,
            &provider,
            gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }
}

/// o caminho do override (~/.config/elite/tools.css — o dono veste).
pub fn caminho_override() -> std::path::PathBuf {
    let base = std::env::var("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| {
            std::path::PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/root".into()))
                .join(".config")
        });
    base.join("elite/tools.css")
}

/// O EXECUTOR: corre o comando em thread de fundo, cada LINHA de saída
/// (stdout+stderr) chega ao canal; o Fim traz o código de retorno.
/// A UI drena no idle (a mesma lei do dreno da barra — nunca bloqueia).
pub enum Linha {
    Texto(String),
    Fim(i32),
}

pub fn executa(
    argv: &[String],
    tx: std::sync::mpsc::Sender<Linha>,
) {
    let argv: Vec<String> = argv.to_vec();
    std::thread::spawn(move || {
        let filho = Command::new(&argv[0])
            .args(&argv[1..])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .stdin(Stdio::null())
            .spawn();
        match filho {
            Ok(f) => {
                let pid = f.id();
                // o dreno duplo (stdout E stderr): duas threads curtas,
                // o Fim espera o processo e avisa UMA vez
                let mut asas = Vec::new();
                for stream in [f.stdout, f.stderr] {
                    if let Some(s) = stream {
                        let tx = tx.clone();
                        asas.push(std::thread::spawn(move || {
                            let leitor = BufReader::new(s);
                            for linha in leitor.lines() {
                                if let Ok(l) = linha {
                                    if tx.send(Linha::Texto(l)).is_err() {
                                        return;
                                    }
                                }
                            }
                        }));
                    }
                }
                for asa in asas {
                    let _ = asa.join();
                }
                // o rc pelo wait (o pid guarda o dono do processo morto
                // no Linux — o status chega pelo waitpid do libc)
                let mut status = 0i32;
                unsafe {
                    let mut w: libc::c_int = 0;
                    loop {
                        let r = libc::waitpid(pid as libc::pid_t, &mut w, 0);
                        if r == -1 && *libc::__errno_location() == libc::EINTR {
                            continue;
                        }
                        if r == pid as libc::pid_t && libc::WIFEXITED(w) {
                            status = libc::WEXITSTATUS(w);
                        }
                        break;
                    }
                }
                let _ = tx.send(Linha::Fim(status));
            }
            Err(e) => {
                let _ = tx.send(Linha::Texto(format!(
                    "não nasceu: {argv:?} — {e}"
                )));
                let _ = tx.send(Linha::Fim(127));
            }
        }
    });
}

/// o dreno do executor (idle de 80ms — a latência do texto vivo). O
/// `rodando` trava o botão enquanto a dose corre; o fim dispara o
/// callback ÚNICO (consumido aqui — a janela veste o veredito).
pub fn drena_linhas(
    rx: &Receiver<Linha>,
    buffer: &gtk4::TextBuffer,
    rodando: &std::rc::Rc<std::cell::Cell<bool>>,
    fim: &std::rc::Rc<std::cell::RefCell<Option<Box<dyn FnOnce(i32) + 'static>>>>,
) -> glib::ControlFlow {
    loop {
        match rx.try_recv() {
            Ok(Linha::Texto(l)) => {
                let mut fim_iter = buffer.end_iter();
                buffer.insert(&mut fim_iter, &format!("{l}\n"));
            }
            Ok(Linha::Fim(rc)) => {
                rodando.set(false);
                // o callback único do fim (consumido AQUI — a janela decide)
                if let Some(cb) = fim.borrow_mut().take() {
                    cb(rc);
                }
                return glib::ControlFlow::Continue;
            }
            Err(_) => break,
        }
    }
    glib::ControlFlow::Continue
}

/// a janela-base das ferramentas (800x520, a cara da casa).
pub fn janela_base(app: &gtk4::Application, nome: &str, titulo: &str) -> gtk4::ApplicationWindow {
    let win = gtk4::ApplicationWindow::new(app);
    win.set_widget_name(nome);
    win.set_title(Some(titulo));
    win.set_default_size(800, 520);
    win
}

/// o bloco de texto vivo (o "terminal" da casa — monospace, escuro,
/// a fonte da barra; o dono copia, o texto rola).
pub fn bloco_texto() -> (gtk4::ScrolledWindow, gtk4::TextBuffer) {
    let buffer = gtk4::TextBuffer::new(None::<gtk4::TextTagTable>);
    let view = gtk4::TextView::with_buffer(&buffer);
    view.set_editable(false);
    view.set_cursor_visible(false);
    view.set_monospace(true);
    view.set_wrap_mode(gtk4::WrapMode::WordChar);
    view.set_top_margin(10);
    view.set_left_margin(10);
    let scroll = gtk4::ScrolledWindow::new();
    scroll.set_child(Some(&view));
    scroll.set_min_content_height(240);
    (scroll, buffer)
}

/// auto-scroll para o fim quando o texto cresce (o vadjustment do
/// scrolled — a descida é cortesia visual).
pub fn rola_para_o_fim(scroll: &gtk4::ScrolledWindow) {
    if let Some(adj) = scroll.vadjustment() {
        adj.set_value(adj.upper() - adj.page_size());
    }
}

/// o dreno do texto vivo (idle — a latência da casa).
pub const IDLE_MS: u64 = 80;
