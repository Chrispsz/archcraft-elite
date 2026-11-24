// ═════════════════════════════════════════════════════════════════════════
// craft-clean (2.0 Fase 2) — A LIMPEZA COM CARA DE CASA.
// O foot+pkexec do menu morre como porta: a limpeza sobe numa janela
// nativa com a pele da casa, a FASE 1 AUTO-SEGURA roda com o dono
// certo (o --as-root recebe usuário e home por ARGUMENTO — a lição
// E134 do polkit-agent-helper) e o relatório TOTAL LIBERADO chega em
// texto vivo. A FASE 2 avançada (órfãos/runtimes/miniaturas com
// perguntas [s/N]) é CLI de pé no terminal — NOMEADA no papel da
// janela, nunca escondida (o escopo honesto da diretriz).
// ═════════════════════════════════════════════════════════════════════════

#[cfg(not(feature = "gui"))]
fn main() {
    eprintln!("craft-clean: a GUI precisa da feature 'gui' (o CI do pacote liga — a lei L6)");
    std::process::exit(1);
}

#[cfg(feature = "gui")]
fn main() {
    use gtk4::prelude::*; // (Canal 146: o connect_activate/run do main vestem o prelude)
    let app = gtk4::Application::new(Some("elite.craft.Clean"), Default::default());
    app.connect_activate(|app| build(app));
    app.run().get() as i32;
}

#[cfg(feature = "gui")]
fn build(app: &gtk4::Application) {
    use craft_tools::janela;
    use gtk4::prelude::*;

    janela::load_css();
    let win = janela::janela_base(app, "toolswin", "Limpeza do sistema");
    let corpo = gtk4::Box::new(gtk4::Orientation::Vertical, 14);
    corpo.set_margin_top(18);
    corpo.set_margin_bottom(18);
    corpo.set_margin_start(20);
    corpo.set_margin_end(20);

    let titulo = gtk4::Label::new(Some("Limpeza do sistema"));
    titulo.add_css_class("title");
    titulo.set_halign(gtk4::Align::Start);
    // o corpo honesto: o que a fase 1 faz, o que ela NUNCA toca, e o
    // endereço da fase 2 (a avançada é CLI — nomeada, não escondida)
    let corpo_txt = gtk4::Label::new(Some(
        "A fase segura e automática: o journal enxuga (7 dias, teto 100M), o \
         cache de pacotes fica com 2 versões por app, os links quebrados \
         saem, os coredumps velhos e a lixeira também — e o cache do Brave \
         só com o navegador fechado.\n\
         NUNCA toca em pastas pessoais, perfis de navegador ou \
         configurações vivas.\n\
         A fase avançada (órfãos, runtimes de Flatpak, miniaturas) segue \
         sendo CLI: foot -e elite-clean --avancada.",
    ));
    corpo_txt.add_css_class("body");
    corpo_txt.set_halign(gtk4::Align::Start);
    corpo_txt.set_xalign(0.0);
    corpo_txt.set_wrap(true);

    let (scroll, buffer) = janela::bloco_texto();
    buffer.set_text("— o relatório da limpeza aparece aqui —\n");

    let acoes = gtk4::Box::new(gtk4::Orientation::Horizontal, 10);
    let btn = gtk4::Button::with_label("Limpar agora");
    btn.add_css_class("executar");
    let pulso = gtk4::Spinner::new();
    pulso.set_visible(false);
    let rodando = std::rc::Rc::new(std::cell::Cell::new(false));

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
            btn.set_label("Limpar de novo");
            let veredito = if rc == 0 {
                "✓ Limpeza concluída — o total liberado está no relatório."
            } else {
                "✗ A limpeza não completou — as linhas acima e ~/.cache/elite/clean.log dizem o porquê."
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

    // o clique: a FASE 1 AUTO-SEGURA com o DONO CERTO (o --as-root
    // recebe usuário e home por argumento — o réu E134 do env injection)
    {
        let tx = tx.clone();
        let rodando = rodando.clone();
        // (Canal 147: a cópia do closure ganha NOME PRÓPRIO — idem update)
        let btn_c = btn.clone();
        let pulso = pulso.clone();
        btn.connect_clicked(move |_| {
            if rodando.get() {
                return;
            }
            rodando.set(true);
            btn_c.set_sensitive(false);
            btn_c.set_label("Limpando…");
            pulso.set_visible(true);
            pulso.start();
            let usuario = std::env::var("USER")
                .or_else(|_| std::env::var("LOGNAME"))
                .unwrap_or_else(|_| "root".into());
            let home = std::env::var("HOME").unwrap_or_else(|_| "/root".into());
            janela::executa(&craft_tools::args_limpeza(&usuario, &home), tx.clone());
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
