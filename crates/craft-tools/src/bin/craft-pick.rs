// ═════════════════════════════════════════════════════════════════════════
// craft-pick (2.0 Fase 2) — O SELETOR NATIVO DA CASA.
// O craft-menu (fuzzel + gaiola de state + âncoras calibradas à mão)
// MORRE AQUI: a gramática dmenu vira GTK4 com a pele da casa — itens
// por argv OU stdin (1 linha = 1 item), a busca filtra no tugar
// (normalização acento-írito), Enter devolve o ESCOLHIDO no stdout e
// exit 0, Esc fecha com exit 1 (o contrato 0/1 que os 12 chamadores
// conhecem — SEM toggle de pid, SEM cross-dismiss: a janela É o foco;
// o clique fora é lei do gerenciador de janelas do GTK, não estado
// gravado em /run).
// ═════════════════════════════════════════════════════════════════════════

#[cfg(feature = "gui")]
use std::io::Read;

#[cfg(not(feature = "gui"))]
fn main() {
    eprintln!("craft-pick: o seletor precisa da feature 'gui' (o CI do pacote liga — a lei L6)");
    std::process::exit(1);
}

#[cfg(feature = "gui")]
fn main() {
    use gtk4::prelude::*; // (Canal 146: o connect_activate/run do main vestem o prelude)
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (titulo, mut itens) = craft_tools::parse_pick_args(&args);
    // stdin é a interface dmenu (listas dinâmicas dos chamadores: os
    // processos vivos do craft-bgapps, os snapshots do rollback)
    if itens.is_empty() && !atty_stdin() {
        let mut papel = String::new();
        let _ = std::io::stdin().read_to_string(&mut papel);
        itens = papel
            .lines()
            .map(str::to_string)
            .filter(|l| !l.trim().is_empty())
            .collect();
    }
    if itens.is_empty() {
        // nada a mostrar: o contrato do craft-menu (exit 0 silencioso —
        // lista vazia não é erro, é nada a escolher)
        std::process::exit(0);
    }

    let app = gtk4::Application::new(Some("elite.craft.Pick"), Default::default());
    // o resultado viaja pelo canal do application (o exit code é DELE)
    let (tx, rx) = std::sync::mpsc::channel::<Option<String>>();
    let itens_c = itens.clone();
    let titulo_c = titulo.clone();
    {
        let tx = tx.clone();
        app.connect_activate(move |app| build(app, &titulo_c, &itens_c, tx.clone()));
    }
    let codigo = app.run();
    // o veredito: Some(escolha) → stdout + 0; None → 1 (o contrato)
    let escolha = rx.recv().ok().flatten();
    match escolha {
        Some(e) => {
            println!("{e}");
            let _ = codigo;
            std::process::exit(0);
        }
        None => std::process::exit(1),
    }
}

#[cfg(feature = "gui")]
fn build(
    app: &gtk4::Application,
    titulo: &str,
    itens: &[String],
    tx: std::sync::mpsc::Sender<Option<String>>,
) {
    use craft_tools::janela;
    use gtk4::prelude::*;

    janela::load_css();
    let win = janela::janela_base(app, "pickwin", titulo);
    win.set_default_size(560, 420);
    let corpo = gtk4::Box::new(gtk4::Orientation::Vertical, 10);
    corpo.set_margin_top(14);
    corpo.set_margin_bottom(14);
    corpo.set_margin_start(16);
    corpo.set_margin_end(16);

    // a BUSCA: o foco nasce AQUI (o dedo do dono já digita)
    let busca = gtk4::Entry::new();
    busca.set_placeholder_text(Some("Digite para filtrar — Enter escolhe, Esc cancela"));

    // a LISTA: um botão por item (o clique escolhe DIRETO — mouse é
    // primeira classe na casa; o teclado navega com as setas nativas
    // do ListBox)
    let lista = gtk4::ListBox::new();
    lista.set_selection_mode(gtk4::SelectionMode::Single);
    let scroll = gtk4::ScrolledWindow::new();
    scroll.set_child(Some(&lista));
    scroll.set_min_content_height(260);
    scroll.set_vexpand(true);

    // o estado do filtro (a remontagem é honesta — listas de pick são
    // pequenas; o mapa é o widget inteiro)
    let todos: Vec<String> = itens.to_vec();
    let montados: std::rc::Rc<std::cell::RefCell<Vec<gtk4::Button>>> =
        std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));

    // o ESC: cancela (exit 1 — o contrato dos chamadores)
    // (Canal 147: a cópia do closure ganha NOME PRÓPRIO — a sombra era
    // movida pelo closure e emprestada pelo add_controller no mesmo fôlego)
    {
        let tx = tx.clone();
        let win_c = win.clone();
        let ec = gtk4::EventControllerKey::new();
        ec.connect_key_pressed(move |_, key, _, _| {
            if key == gtk4::gdk::Key::Escape {
                let _ = tx.send(None);
                win_c.close();
                return gtk4::glib::Propagation::Stop;
            }
            gtk4::glib::Propagation::Proceed
        });
        win.add_controller(ec);
    }
    // o Enter na busca: escolhe o PRIMEIRO visível (o dmenu de sempre)
    {
        let tx = tx.clone();
        let busca = busca.clone();
        let montados = montados.clone();
        busca.connect_activate(move |_| {
            for btn in montados.borrow().iter() {
                if btn.is_visible() {
                    if let Some(txt) = btn.label() {
                        println!("{txt}");
                        let _ = tx.send(Some(txt.to_string()));
                        std::process::exit(0); // o contrato: stdout + 0
                    }
                }
            }
            let _ = tx.send(None);
            std::process::exit(1);
        });
    }

    // a remontagem por busca
    {
        let busca = busca.clone();
        let lista = lista.clone();
        let todos = todos.clone();
        let tx = tx.clone();
        let montados = montados.clone();
        busca.connect_changed(move |e| {
            let visiveis = craft_tools::filtra_itens(&todos, &e.text());
            // limpa a lista
            while let Some(filho) = lista.first_child() {
                lista.remove(&filho);
            }
            montados.borrow_mut().clear();
            for item in visiveis {
                let tx = tx.clone();
                let btn = gtk4::Button::with_label(&item);
                btn.set_has_frame(false);
                btn.set_halign(gtk4::Align::Start);
                let valor = item.clone();
                btn.connect_clicked(move |_| {
                    println!("{valor}");
                    let _ = tx.send(Some(valor.clone()));
                    std::process::exit(0);
                });
                lista.append(&btn);
                montados.borrow_mut().push(btn);
            }
        });
    }
    // o frame 0: a lista inteira (a busca vazia mostra tudo)
    {
        let lista = lista.clone();
        let tx = tx.clone();
        let montados = montados.clone();
        let todos = todos.clone();
        gtk4::glib::idle_add_local_once(move || {
            let visiveis = craft_tools::filtra_itens(&todos, "");
            for item in visiveis {
                let tx = tx.clone();
                let btn = gtk4::Button::with_label(&item);
                btn.set_has_frame(false);
                btn.set_halign(gtk4::Align::Start);
                let valor = item.clone();
                btn.connect_clicked(move |_| {
                    println!("{valor}");
                    let _ = tx.send(Some(valor.clone()));
                    std::process::exit(0);
                });
                lista.append(&btn);
                montados.borrow_mut().push(btn);
            }
        });
    }

    corpo.append(&busca);
    corpo.append(&scroll);
    win.set_child(Some(&corpo));
    win.present();
    busca.grab_focus();
}

/// o stdin é pipe ou terminal? (sem pipe não há leitura — o argv manda)
#[cfg(feature = "gui")]
fn atty_stdin() -> bool {
    unsafe { libc::isatty(0) == 1 }
}
