// ═════════════════════════════════════════════════════════════════════════
// craft-pick (2.0 Fase 2) — O SELETOR NATIVO DA CASA.
// O craft-menu (fuzzel + gaiola de state + âncoras calibradas à mão)
// MORRE AQUI: a gramática dmenu vira GTK4 com a pele da casa — itens
// por argv OU stdin (1 linha = 1 item), a busca filtra no tugar
// (normalização acento-írito), Enter devolve o ESCOLHIDO no stdout e
// exit 0, Esc fecha com exit 1 (o contrato 0/1 que os chamadores
// conhecem — SEM toggle de pid, SEM cross-dismiss: a janela É o foco;
// o clique fora é lei do gerenciador de janelas do GTK, não estado
// gravado em /run).
//
// E150 — O PROCESSO NUNCA FICA ZUMBI: a telemetria do dono (base
// 1.0-98) fotografou craft-pick parado na RAM (~24 MB) com a janela
// esquecida — o Enter/Esc/clique já escapavam IMEDIATO (exit(0) dentro
// do closure), mas PERDER O FOCO deixava o corpo vivo para sempre. A
// lei agora é QUATRO portas de fuga: escolheu (stdout+0), Esc (1),
// PERDEU O FOCO (1 — o notify::is-active da janela) e o fim do
// app.run() sem escolha (1). Nenhum caminho espera o GTK: o processo
// morre no MESMO instante da decisão.
//
// 1.0-109 — A CAMADA DE SOBREPOSIÇÃO + A INSTÂNCIA ÚNICA COM TOGGLE (a
// evidência real do dump 1.0-108: o ps fotografou 24 processos
// craft-pick presos em background (~24 MB cada) e NENHUM menu
// (craft-game/craft-idle/craft-rollback) apareceu na tela do labwc —
// o GtkApplicationWindow COMUM não recebe camada de sobreposição nem
// foco automático no compositor. A diretriz do dono, palavra por
// palavra: (1) o pick veste gtk4-layer-shell — Layer::Overlay,
// KeyboardMode::Exclusive, SEM âncoras (centralizado na tela), igual
// ao calendário da top bar: exibição imediata acima de qualquer
// janela e captura direta de Escape/setas/Enter; (2) a instância
// única lê ${XDG_RUNTIME_DIR}/elite/craft-pick.pid — outro pick VIVO
// cai com SIGTERM (MESMO título = toggle que sai limpo com exit 0;
// OUTRO menu = substituição na hora), o próprio PID é gravado e o
// arquivo sai com o dono; (3) Escape fecha IMEDIATO com exit 0 e o
// perder foco APÓS mapeado fecha sem nunca ficar invisível
// capturando ponteiro.
//
// 1.0-107 — O SELETOR NÃO-BLOQUEANTE (a cura dos menus travados: o
// craft-idle/craft-game/etc. abriam o pick e o SEGUNDO pedido nascia
// MORTO — a instância única `elite.craft.Pick` deixava o 2º chamador
// sem janela e o menu da casa parecia travado): o GtkApplication nasce
// G_APPLICATION_NON_UNIQUE — cada pedido é UM processo com a própria
// janela; o foco decide quem vive (o is-active FALSE do de cima o
// colhe NA HORA, exit 1 com o stdout fechado — SEM zumbi pendurado).
// ═════════════════════════════════════════════════════════════════════════

#[cfg(feature = "gui")]
use std::io::Read;


// ── 1.0-109 — A INSTÂNCIA ÚNICA (o pidfile da diretriz) ─────────────

#[cfg(feature = "gui")]
fn pick_pid_path() -> std::path::PathBuf {
    let dir = std::env::var("XDG_RUNTIME_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| std::path::PathBuf::from("/tmp"));
    dir.join("elite/craft-pick.pid")
}

/// o pick VIVO do /proc (o comm decide — pid reciclado não mente):
/// a sonda da casa, lida direto do procfs.
#[cfg(feature = "gui")]
fn pick_do_pid_vivo(pid: u32) -> bool {
    std::fs::read_to_string(format!("/proc/{pid}/comm"))
        .map(|c| c.trim() == "craft-pick")
        .unwrap_or(false)
}

/// O VELHO CAI (a diretriz: encerrá-lo com SIGTERM — o mesmo título é
/// toggle, outro é substituição): o TERM desce, a morte é esperada com
/// teto honesto de 500ms e o pidfile do velho é colhido (o velho não
/// roda cleanup de TERM — o assassino é o coveiro do papel dele).
#[cfg(feature = "gui")]
fn mata_o_pick_velho(pidfile: &std::path::Path) {
    let Ok(papel) = std::fs::read_to_string(pidfile) else { return };
    let Some((pid_linha, _)) = papel.split_once('\n') else { return };
    let Ok(pid) = pid_linha.trim().parse::<i32>() else { return };
    unsafe {
        libc::kill(pid, libc::SIGTERM);
    }
    for _ in 0..25 {
        if !pick_do_pid_vivo(pid as u32) {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    let _ = std::fs::remove_file(pidfile);
}

/// A SAÍDA ÚNICA (o pidfile sai com o dono — SEM processo invisível
/// capturando ponteiro): todo caminho de fuga do pick atravessa AQUI.
#[cfg(feature = "gui")]
fn sai(codigo: i32) -> ! {
    let pidfile = pick_pid_path();
    if let Ok(papel) = std::fs::read_to_string(&pidfile) {
        // só o DONO colhe (o substituto já nasceu com o próprio papel)
        if papel.lines().next() == Some(std::process::id().to_string().as_str()) {
            let _ = std::fs::remove_file(&pidfile);
        }
    }
    std::process::exit(codigo);
}

#[cfg(not(feature = "gui"))]
fn main() {
    eprintln!("craft-pick: o seletor precisa da feature 'gui' (o CI do pacote liga — a lei L6)");
    std::process::exit(1);
}

#[cfg(feature = "gui")]
fn main() {
    use gtk4::prelude::*; // (Canal 146: o connect_activate/run do main vestem o prelude)
    let args: Vec<String> = std::env::args().skip(1).collect();
    if craft_tools::pede_ajuda(
        &args,
        "uso: craft-pick [-T TÍTULO | -TTÍTULO | --title TÍTULO | --title=TÍTULO] [itens...]\n\
         \x20     — o seletor nativo da casa\n\
         \x20  itens por argv OU stdin (1 linha = 1 item); Enter devolve o\n\
         \x20  ESCOLHIDO no stdout + exit 0; Esc fecha com exit 1; flag\n\
         \x20  inválida fecha com exit 2 ANTES de qualquer janela (o nome\n\
         \x20  do réu vai no stderr — zero processo zumbi).\n\
         \x20  -h | --help | uso  este papel",
    ) {
        return; // a ajuda sai ANTES de qualquer GTK (lei E90)
    }
    // 1.0-108 — O JUIZ ANTES DO GTK (a evidência do rig 1.0-107.3: o
    // `craft-pick -T "Teste"` morria com "opção -T desconhecida" no
    // binário de ERA e deixava 22 processos presos em background
    // (~530 MB) — o parser engolia a flag inválida em silêncio e o
    // GTK nascia ZUMBI na mão dos chamadores). A flag inválida agora é
    // ERRO NOMEADO no stderr + exit 2 ANTES de qualquer init gráfico:
    // o processo morre no MESMO instante, zero corpo vivo pendurado.
    let (titulo, mut itens) = match craft_tools::parse_pick_args(&args) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("craft-pick: {e}");
            eprintln!(
                "uso: craft-pick [-T TÍTULO | -TTÍTULO | --title TÍTULO | --title=TÍTULO] [itens...] (-h ajuda)"
            );
            sai(2);
        }
    };
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
        sai(0);
    }

    // 1.0-109 — A INSTÂNCIA ÚNICA (a diretriz, palavra por palavra):
    // ler o pidfile ANTES de qualquer GTK — o MESMO menu vivo é TOGGLE
    // (o velho cai e o chamador sai LIMPO), outro menu é SUBSTITUIÇÃO e
    // o fóssil de um pick morto nunca trava o próximo (o comm do /proc
    // decide quem vive).
    let pidfile = pick_pid_path();
    match std::fs::read_to_string(&pidfile)
        .map(|papel| {
            craft_tools::decide_instancia(&papel, pick_do_pid_vivo, &titulo)
        })
        .unwrap_or(craft_tools::InstanciaPick::Livre)
    {
        craft_tools::InstanciaPick::Toggle => {
            // o mesmo menu na tela: o toggle da diretriz — fecha o velho
            // e sai LIMPO (exit 0, zero janela nova)
            mata_o_pick_velho(&pidfile);
            sai(0);
        }
        craft_tools::InstanciaPick::Substitui => {
            // outro menu: o velho cai e o novo veste NA HORA
            mata_o_pick_velho(&pidfile);
        }
        craft_tools::InstanciaPick::Livre => {} // o lugar é nosso
    }
    // grava o PRÓPRIO pid (o título na 2ª linha — o próximo pedido julga)
    if let Some(pai) = pidfile.parent() {
        let _ = std::fs::create_dir_all(pai);
    }
    let _ = std::fs::write(&pidfile, format!("{}\n{titulo}", std::process::id()));

    // 1.0-107 — NON_UNIQUE (a cura dos menus travados): a instância única
    // `elite.craft.Pick` matava o SEGUNDO pedido na hora (o craft-idle
    // aberto + o clique no craft-game = menu morto que parecia travado).
    // Cada pedido é UM processo com a própria janela — o app_id segue o
    // mesmo (a pele e as regras de janela da casa não mudam).
    let app = gtk4::Application::new(
        Some("elite.craft.Pick"),
        gtk4::gio::ApplicationFlags::NON_UNIQUE,
    );
    // o resultado viaja pelo canal do application (o exit code é DELE)
    let (tx, rx) = std::sync::mpsc::channel::<Option<String>>();
    let itens_c = itens.clone();
    let titulo_c = titulo.clone();
    // 1.0-108 — a guarda de foco do labwc vive no escopo do processo e
    // VIAJA por Rc ao build (o FALSE do primeiro frame é cortesia)
    let ja_teve_foco = std::rc::Rc::new(std::cell::Cell::new(false));
    let nasceu = std::rc::Rc::new(std::cell::RefCell::new(std::time::Instant::now()));
    {
        let tx = tx.clone();
        let ja = ja_teve_foco.clone();
        let nasc = nasceu.clone();
        app.connect_activate(move |app| {
            build(app, &titulo_c, &itens_c, tx.clone(), &ja, &nasc);
        });
    }
    // 1.0-109 — OS ARGUMENTOS SÃO DO PICK, NÃO DO GLIB: o app.run() de
    // era passava o argv inteiro ao g_application_run e o parser do GLib
    // RECUSAVA o '-T' ("Unknown option -T" — o menu morria na porta do
    // GTK em versões que abortam; o parser da CASA já consumiu tudo —
    // ao GLib sobra SOMENTE a palavra do processo)
    let codigo = app.run_with_args::<&str>(&[]);
    // o veredito: Some(escolha) → stdout + 0; None → 1 (o contrato)
    let escolha = rx.recv().ok().flatten();
    let _ = codigo;
    match escolha {
        Some(e) => {
            println!("{e}");
            sai(0);
        }
        None => sai(1),
    }
}

/// 1.0-108 — OS ARGUMENTOS DA GUARDA DE FOCO (as QUATRO formas do
/// título no parser + o FALSE do primeiro frame do labwc): o build
/// recebe do main o par (ja_teve_foco, nasceu) porque a guarda vive no
/// ESCOPO DO PROCESSO — o present() do fim de build CRAVA o instante
/// do nascimento e o notify::is-active da janela CONSULTA a guarda (Rc/
/// Cell do escopo do build — o closure do notify é Fn, as cópias viajam
/// por referência contada).
#[cfg(feature = "gui")]
fn build(
    app: &gtk4::Application,
    titulo: &str,
    itens: &[String],
    tx: std::sync::mpsc::Sender<Option<String>>,
    ja_teve_foco: &std::rc::Rc<std::cell::Cell<bool>>,
    nasceu: &std::rc::Rc<std::cell::RefCell<std::time::Instant>>,
) {
    use gtk4::prelude::*;

    craft_tools::load_css();
    let win = craft_tools::janela_camada(app, "pickwin", titulo, "craft-pick");
    win.set_default_size(560, 420);
    let corpo = gtk4::Box::new(gtk4::Orientation::Vertical, 10);
    corpo.set_margin_top(14);
    corpo.set_margin_bottom(14);
    corpo.set_margin_start(16);
    corpo.set_margin_end(16);

    // a BUSCA: o foco nasce AQUI (o dedo do dono já digita)
    // 1.0-110 T5 — A BARRA "Digite para filtrar" SOME SEM RESERVAR
    // ESPAÇO quando a lista tem ≤ 8 opções (a diretriz: a busca é das
    // listas LONGAS — a curta nasce LIMPA e o teclado segue INTEIRO:
    // Enter escolhe, as setas andam a seleção, Esc cancela)
    let lista_curta = itens.len() <= 8;
    let busca = gtk4::Entry::new();
    busca.set_placeholder_text(Some("Digite para filtrar — Enter escolhe, Esc cancela"));
    if lista_curta {
        busca.set_visible(false);
    }

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
                // 1.0-109 — a diretriz: fechar IMEDIATO com exit 0 (o
                // toggle de novo pedido também sai limpo — fechar menu
                // não é erro, é o gesto do dono)
                let _ = tx.send(None);
                win_c.close();
                return gtk4::glib::Propagation::Stop;
            }
            gtk4::glib::Propagation::Proceed
        });
        win.add_controller(ec);
    }
    // E150 → 1.0-108 — PERDEU O PALCO (o notify::is-active da JANELA, não
    // o focus-controller do widget — a ordem do dono, palavra por
    // palavra): a janela de ESCOLHA não sobrevive ao palco de outra — o
    // dono clicou fora/alt-tab (o seletor que ficava era o zumbi de
    // ~24 MB da telemetria; o EventControllerFocus de era só via o
    // leave do WIDGET — a janela que NASCIA sem foco ou que o compositor
    // rebaixava em silêncio ficava viva para sempre). O is-active é a
    // VERDADE do compositor: FALSE = o palco é de outro = stdin calado,
    // stdout calado, exit 1 NO MESMO INSTANTE (sem zumbi pendurado).
    //
    // 1.0-108 — A GUARDA DE FOCO DO LABWC (a evidência do rig: no labwc
    // o GTK4 dispara notify::is-active = FALSE no PRIMEIRO frame, ANTES
    // de ativar a janela — o seletor de era MORRIA no frame 0 e os
    // chamadores (craft-game/craft-idle/craft-display/craft-flatpak/
    // craft-rollback) nasciam sem menu nenhum). A lei nova: o FALSE só
    // COLHE depois de DOIS fatos — a janela JÁ TEVE foco REAL
    // (ja_teve_foco: o primeiro is-active=TRUE liga a guarda) E a
    // carência inicial de 300ms após o present() venceu (o primeiro
    // frame do labwc é cortesia, não veredito). O ESC segue IMEDIATO
    // desde o primeiro frame (o contrato dos chamadores nunca muda).
    {
        // E151-cura — a cópia ganha NOME PRÓPRIO ANTES do closure (a
        // mesma cura do Canal 147 no ESC de cima: o tx movido pelo
        // closure deixava o clone de baixo emprestando morto — o E0382
        // que o 1º build da era fotografou). O 1º argumento do notify É
        // a própria janela — o is_active DELE é a verdade do compositor.
        let tx_leave = tx.clone();
        let ja_teve_foco = ja_teve_foco.clone();
        let nasceu = nasceu.clone();
        win.connect_notify_local(Some("is-active"), move |w, _| {
            if w.is_active() {
                // o foco REAL chegou: a guarda arma (o FALSE seguinte é
                // a verdade do compositor, não o primeiro frame do labwc)
                ja_teve_foco.set(true);
                return;
            }
            // FALSE sem foco REAL ainda: o primeiro frame do labwc é
            // CORTESIA — a janela ainda nem foi ativa uma vez (não é
            // alt-tab do dono, é o nascer do próprio GTK)
            if !ja_teve_foco.get() {
                return;
            }
            // FALSE com foco já vivido, mas dentro da carência de 300ms
            // do present(): a janela acabou de nascer — o compositor
            // ainda assenta o palco (a carência cobre o frame 0..1)
            if nasceu.borrow().elapsed() < std::time::Duration::from_millis(300) {
                return;
            }
            // a partir daqui o FALSE é a VERDADE do compositor: o palco
            // é de OUTRA janela — stdin calado, stdout calado, exit 1
            // (a saída única colhe o pidfile: nenhum invisível captura
            // ponteiro, a diretriz 1.0-109)
            let _ = tx_leave.send(None);
            sai(1);
        });
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
                        sai(0); // o contrato: stdout + 0
                    }
                }
            }
            let _ = tx.send(None);
            sai(1);
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
                    sai(0);
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
                    sai(0);
                });
                lista.append(&btn);
                montados.borrow_mut().push(btn);
            }
        });
    }

    // 1.0-110 T5 — O TECLADO DA LISTA CURTA (sem a busca não há campo
    // de digitar — as SETAS andam a seleção e o ENTER escolhe a
    // marcada; a ativação é CLIQUE ÚNICO de sempre nos botões — o Enter
    // veste a MESMA saída única stdout+0)
    if lista_curta {
        let lista = lista.clone();
        let tx = tx.clone();
        let ec = gtk4::EventControllerKey::new();
        ec.connect_key_pressed(move |_, key, _, _| {
            // as linhas do ListBox (os filhos DIRETOS são os rows — a
            // contagem vive na árvore, não em índice de API)
            let linhas: Vec<gtk4::Widget> =
                std::iter::successors(lista.first_child(), |w| w.next_sibling()).collect();
            match key {
                gtk4::gdk::Key::Down | gtk4::gdk::Key::Up => {
                    let passo = if key == gtk4::gdk::Key::Down { 1 } else { -1 };
                    let agora = linhas
                        .iter()
                        .position(|w| w.downcast_ref::<gtk4::ListBoxRow>().is_some_and(|r| r.is_selected()))
                        .unwrap_or(0) as i32
                        + passo;
                    let proximo = agora.clamp(0, (linhas.len() as i32 - 1).max(0));
                    if let Some(row) = linhas
                        .get(proximo as usize)
                        .and_then(|w| w.downcast_ref::<gtk4::ListBoxRow>())
                    {
                        lista.select_row(Some(row));
                    }
                    gtk4::glib::Propagation::Stop
                }
                gtk4::gdk::Key::Return | gtk4::gdk::Key::KP_Enter => {
                    // a marcada (senão a PRIMEIRA) veste a saída única
                    let escolhida = linhas
                        .iter()
                        .find(|w| w.downcast_ref::<gtk4::ListBoxRow>().is_some_and(|r| r.is_selected()))
                        .or(linhas.first())
                        .and_then(|w| w.downcast_ref::<gtk4::ListBoxRow>())
                        .and_then(|r| r.child())
                        .and_downcast::<gtk4::Button>()
                        .and_then(|b| b.label());
                    if let Some(txt) = escolhida {
                        println!("{txt}");
                        let _ = tx.send(Some(txt.to_string()));
                        sai(0);
                    }
                    gtk4::glib::Propagation::Stop
                }
                _ => gtk4::glib::Propagation::Proceed,
            }
        });
        win.add_controller(ec);
    }

    corpo.append(&busca);
    corpo.append(&scroll);
    win.set_child(Some(&corpo));
    win.present();
    // 1.0-108 — O INSTANTE DO NASCIMENTO (a carência de 300ms conta DA
    // apresentação da janela — o primeiro frame do labwc vem DEPOIS do
    // present(), a cortesia cobre o frame 0..1 dele)
    *nasceu.borrow_mut() = std::time::Instant::now();
    // 1.0-110 T5 — a lista CURTA nasce com a PRIMEIRA linha marcada (o
    // Enter de quem não tocou nas setas veste a primeira); a LONGA
    // segue com o dedo do dono NA BUSCA de sempre
    if lista_curta {
        if let Some(row) = lista.row_at_index(0) {
            lista.select_row(Some(&row));
        }
    } else {
        busca.grab_focus();
    }
}

/// o stdin é pipe ou terminal? (sem pipe não há leitura — o argv manda)
#[cfg(feature = "gui")]
fn atty_stdin() -> bool {
    unsafe { libc::isatty(0) == 1 }
}
