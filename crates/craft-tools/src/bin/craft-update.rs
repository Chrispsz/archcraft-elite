// ═════════════════════════════════════════════════════════════════════════
// craft-update (2.0 Fase 2) — A ATUALIZAÇÃO COM CARA DE CASA.
// O terminal morre como porta do dono: a dose sobe numa janela nativa
// com a pele da casa (THEME_CSS), o output do motor corre em TEXTO
// VIVO (cada linha do pacman chega no mesmo frame) e o veredito final
// fala pt_BR. O motor é o de sempre (elite-update → pkexec → a dose
// completa com snapshot PRE/POST do snapper — provado em campo desde
// E128; a GUI é a FACE, a delegação é a lei §4: o pacman é o motor).
// ═════════════════════════════════════════════════════════════════════════

#[cfg(not(feature = "gui"))]
fn main() {
    // a lei do degrau: sem GTK não há face — a mensagem honesta e
    // exit 1 (nunca uma janela fantasma silenciosa)
    eprintln!("craft-update: a GUI precisa da feature 'gui' (o CI do pacote liga — a lei L6)");
    std::process::exit(1);
}

#[cfg(feature = "gui")]
fn main() {
    use gtk4::prelude::*; // (Canal 146: o connect_activate/run do main vestem o prelude)
    let app = gtk4::Application::new(Some("elite.craft.Update"), Default::default());
    app.connect_activate(|app| build(app));
    app.run().get() as i32;
}

#[cfg(feature = "gui")]
fn build(app: &gtk4::Application) {
    use craft_tools::janela;
    use gtk4::prelude::*;

    janela::load_css();
    let win = janela::janela_base(app, "toolswin", "Atualizar o sistema");
    let corpo = gtk4::Box::new(gtk4::Orientation::Vertical, 14);
    corpo.set_margin_top(18);
    corpo.set_margin_bottom(18);
    corpo.set_margin_start(20);
    corpo.set_margin_end(20);

    // o TÍTULO e o corpo honesto (o que a dose faz — sem promessa de
    // menos, sem susto de mais)
    let titulo = gtk4::Label::new(Some("Atualizar o sistema"));
    titulo.add_css_class("title");
    titulo.set_halign(gtk4::Align::Start);
    let corpo_txt = gtk4::Label::new(Some(
        "A dose completa: repositórios, pacotes e Flatpaks — com snapshot de \
         segurança antes (o rollback é um reboot se algo quebrar).\n\
         A senha é o diálogo gráfico da sessão (uma vez, para o wheel).",
    ));
    corpo_txt.add_css_class("body");
    corpo_txt.set_halign(gtk4::Align::Start);
    corpo_txt.set_xalign(0.0);
    corpo_txt.set_wrap(true);

    let (scroll, buffer) = janela::bloco_texto();
    buffer.set_text("— o diário da dose aparece aqui, linha por linha —\n");

    // o BOTÃO e o pulso de espera (discreto, nunca modal)
    let acoes = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
    let btn = gtk4::Button::with_label("Atualizar agora");
    btn.add_css_class("executar");
    let pulso = gtk4::Spinner::new();
    pulso.set_visible(false);
    let rodando = std::rc::Rc::new(std::cell::Cell::new(false));

    // o canal do executor + o dreno no idle (a UI NUNCA bloqueia)
    let (tx, rx) = std::sync::mpsc::channel::<janela::Linha>();
    let rx = std::rc::Rc::new(std::cell::RefCell::new(rx));
    {
        let buffer = buffer.clone();
        let scroll = scroll.clone();
        let rodando = rodando.clone();
        let pulso = pulso.clone();
        let btn = btn.clone();
        let buffer_c = buffer.clone();
        let scroll_c = scroll.clone();
        let fim: std::rc::Rc<
            std::cell::RefCell<Option<Box<dyn FnOnce(i32) + 'static>>>,
        > = std::rc::Rc::new(std::cell::RefCell::new(Some(Box::new(move |rc: i32| {
            pulso.stop();
            pulso.set_visible(false);
            btn.set_sensitive(true);
            btn.set_label("Atualizar de novo");
            let veredito = if rc == 0 {
                "✓ Sistema atualizado."
            } else {
                "✗ A dose não completou — as linhas acima e ~/.cache/elite/update.log dizem o porquê."
            };
            let mut it = buffer_c.end_iter();
            buffer_c.insert(&mut it, &format!("\n{veredito}\n"));
            janela::rola_para_o_fim(&scroll_c);
        }))));
        gtk4::glib::timeout_add_local(
            std::time::Duration::from_millis(janela::IDLE_MS),
            move || {
                let rx = rx.borrow();
                janela::drena_linhas(&rx, &buffer, &rodando, &fim);
                janela::rola_para_o_fim(&scroll);
                gtk4::glib::ControlFlow::Continue
            },
        );
    }

    // o clique: SOBE A DOSE (o pkexec da regra 50-elite-wheel; o
    // diálogo gráfico do polkit nasce da sessão — zero terminal)
    {
        let tx = tx.clone();
        let rodando = rodando.clone();
        let btn = btn.clone();
        let pulso = pulso.clone();
        btn.connect_clicked(move |_| {
            if rodando.get() {
                return; // a dose já está no ar — o clique não re-sobe
            }
            rodando.set(true);
            btn.set_sensitive(false);
            btn.set_label("Atualizando…");
            pulso.set_visible(true);
            pulso.start();
            janela::executa(&craft_tools::args_atualizacao(), tx.clone());
        });
    }
    acoes.append(&btn);
    acoes.append(&pulso);

    corpo.append(&titulo);
    corpo.append(&corpo_txt);
    corpo.append(&scroll);
    corpo.append(&acoes);
    win.set_child(Some(&corpo));
    win.present();
}
