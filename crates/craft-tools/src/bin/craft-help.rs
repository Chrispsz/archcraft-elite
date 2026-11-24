// ═════════════════════════════════════════════════════════════════════════
// craft-help (2.0 Fase 2) — O MAPA DOS COMANDOS COM CARA DE CASA.
// O foot -e craft-help morre como porta: o mapa (a família 2.0 viva,
// as ferramentas, o socorro CLI e os atalhos do rc.xml) veste a pele
// da casa numa janela com BUSCA (o filtro acento-írito do
// craft_tools::filtra_itens — o dono digita como pensa). O conteúdo
// mora em craft_tools::mapa_comandos (puro, testado — a fonte única
// do mapa; o CLI de 255 linhas vira carne nova).
// ═════════════════════════════════════════════════════════════════════════

#[cfg(not(feature = "gui"))]
fn main() {
    eprintln!("craft-help: a GUI precisa da feature 'gui' (o CI do pacote liga — a lei L6)");
    std::process::exit(1);
}

#[cfg(feature = "gui")]
fn main() {
    let app = gtk4::Application::new(Some("elite.craft.Help"), Default::default());
    app.connect_activate(|app| build(app));
    app.run().get() as i32;
}

#[cfg(feature = "gui")]
fn build(app: &gtk4::Application) {
    use craft_tools::janela;
    use gtk4::prelude::*;

    janela::load_css();
    let win = janela::janela_base(app, "toolswin", "Ajuda — comandos da Elite");
    let corpo = gtk4::Box::new(gtk4::Orientation::Vertical, 12);
    corpo.set_margin_top(18);
    corpo.set_margin_bottom(18);
    corpo.set_margin_start(20);
    corpo.set_margin_end(20);

    let titulo = gtk4::Label::new(Some("Comandos da Elite"));
    titulo.add_css_class("title");
    titulo.set_halign(gtk4::Align::Start);

    // a BUSCA (o mesmo filtro do pick — acento-írito, qualquer posição)
    let busca = gtk4::Entry::new();
    busca.set_placeholder_text(Some("Buscar comando ou descrição (ex.: dock, trava, snapshot)"));

    // o papel: as seções do mapa (remontado a cada busca — o mapa é
    // pequeno, a remontagem é honesta e barata)
    let scroll = gtk4::ScrolledWindow::new();
    let papel = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
    scroll.set_child(Some(&papel));
    scroll.set_min_content_height(320);
    scroll.set_vexpand(true);

    // a remontagem: a busca manda, o papel veste (Rc compartilhado —
    // zero set_data inseguro, os widgets andam de mão em mão)
    let papel = std::rc::Rc::new(papel);
    {
        let papel = papel.clone();
        busca.connect_changed(move |e| remonta(&papel, &e.text()));
    }
    remonta(&papel, "");

    corpo.append(&titulo);
    corpo.append(&busca);
    corpo.append(&scroll);
    win.set_child(Some(&corpo));
    win.present();
    busca.grab_focus();
}

/// remonta o papel com o filtro da busca (as seções sem itens somem —
/// o vazio de seção é honesto, nunca cabeça órfã).
#[cfg(feature = "gui")]
fn remonta(papel: &gtk4::Box, busca_txt: &str) {
    use gtk4::prelude::*;

    // limpa o papel
    while let Some(filho) = papel.first_child() {
        papel.remove(&filho);
    }
    for (secao, itens) in craft_tools::mapa_comandos() {
        // o alvo do filtro: comando + descrição (a busca acha os dois)
        let visiveis: Vec<(&&str, &&str)> = itens
            .iter()
            .filter(|(c, d)| {
                let alvo = format!("{c} {d}");
                craft_tools::filtra_itens(&[alvo], busca_txt).len() == 1
            })
            .collect();
        if visiveis.is_empty() {
            continue;
        }
        let cabeca = gtk4::Label::new(Some(secao));
        cabeca.set_halign(gtk4::Align::Start);
        cabeca.add_css_class("title");
        cabeca.set_margin_top(6);
        papel.append(&cabeca);
        for (comando, descricao) in visiveis {
            let linha = gtk4::Label::new(None);
            linha.set_markup(&format!(
                "<b>{}</b> — {}",
                escape(comando),
                escape(descricao)
            ));
            linha.set_halign(gtk4::Align::Start);
            linha.set_xalign(0.0);
            linha.set_wrap(true);
            linha.add_css_class("body");
            papel.append(&linha);
        }
    }
}

/// o escape de markup (o hábito de sempre — o cinto barato).
#[cfg(feature = "gui")]
fn escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}
