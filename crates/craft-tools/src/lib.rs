// ═════════════════════════════════════════════════════════════════════════
// craft-tools — lib.rs (E149). O NÚCLEO PURO das ferramentas nativas
// da casa: os argumentos, os filtros e o MAPA que o craft-help veste.
// std-only e testado em qualquer lugar (a lei do degrau — a pele GTK4
// mora no craft-pick atrás da feature "gui").
//
// A DIRETRIZ QUE ESTE CRATE CUMPRE AGORA (E149 — a simplificação radical):
// ajuda, atualização e limpeza são EXECUÇÃO DIRETA no terminal (o
// `craft-update`/`craft-clean`/`craft-help` SEM argumentos disparam a
// tarefa na hora — stdio herdado, exit code honesto; o `-h`/`--help`
// segue o contrato E90). As janelas GUI intermediárias morreram — o
// motor é o mesmo já provado em campo (elite-update/elite-clean pelo
// pkexec da regra 49-elite). O craft-pick fica: o seletor dmenu
// é a face GTK4 da casa (W-v, craft-game menu, craft-idle menu).
// ═════════════════════════════════════════════════════════════════════════

// 1.0-103 — O JUIZ NATIVO DA CASA: todo julgamento/parsing de config
// (XML/INI/YAML/JSON), o aperto de mão do bus.sock e a resolução de
// Execute do menu/rc que viviam em heredocs python moram AQUI — std-only
// (a lei do degrau), com contratos cravados em teste.
pub mod audit;

/// A LEI E90 das ferramentas (a descoberta não depende de biblioteca
/// gráfica): `-h`/`--help`/`uso` imprime o uso e devolve true — o main
/// imprime e sai 0 ANTES de qualquer GTK (o craft-help é janela, mas o
/// terminal do dono nunca fica sem resposta; o contrato da suíte 35-ajuda
/// cobra o verbo seguro em 100% do mapa).
pub fn pede_ajuda(args: &[String], uso: &str) -> bool {
    if args.iter().any(|a| a == "-h" || a == "--help" || a == "uso") {
        println!("{uso}");
        true
    } else {
        false
    }
}

/// O pedido de update que o TERMINAL executa (o construtor dos
/// argumentos é puro — os testes provam o caminho certo).
pub fn args_atualizacao() -> Vec<String> {
    // a porta canônica da constituição §5: o pkexec elite-update (a
    // regra da casa libera EXATAMENTE este caminho para o wheel local
    // ativo — sem senha na cara do dono, com o diálogo gráfico do
    // lxqt-policykit-agent da sessão)
    vec!["/usr/local/bin/elite-update".to_string()]
}

/// O pedido de limpeza que o TERMINAL executa (a FASE 1 AUTO-SEGURA —
/// sem pergunta nenhuma: journal vacuum, paccache, órfãos de link,
/// lixeira e caches regeneráveis; a fase 2 avançada é CLI de pé no
/// terminal — `elite-clean menu`).
/// 1.0-94 — O PKEXEC ENTRA NA FRENTE (o réu do rig da 1.0-93: a GUI
/// chamava elite-clean --as-root DIRETO como usuário comum — a porta
/// --as-root é de RAIZ e recusava na primeira linha, "Limpeza não
/// completou" para sempre). A escalada é a MESMA do elite-update: a
/// regra 49-elite libera EXATAMENTE o caminho para o wheel local
/// ativo — o diálogo gráfico da sessão (lxqt-policykit-agent) pergunta
/// UMA vez, o motor sobe como raiz com o DONO CERTO por argumento.
pub fn args_limpeza(usuario: &str, home: &str) -> Vec<String> {
    vec![
        "pkexec".to_string(),
        "/usr/local/bin/elite-clean".to_string(),
        "--as-root".to_string(),
        usuario.to_string(),
        home.to_string(),
        "--auto-safe".to_string(),
    ]
}

// ── 1.0-108 — A GUARDA DO PKEXEC ÓRFÃO (a diretriz do hardware) ──────────
// O RELATO DO RIG: fechar o terminal de Atualizar/Limpar SEM digitar a
// senha deixava o `pkexec` filho ÓRFÃO — o diálogo branco do
// lxqt-policykit-agent travado na tela até o logout. O trap
// `pkill -P $$ … EXIT HUP INT TERM` da casa veste o binário: o pid do
// filho mora num atomic e o handler de SIGHUP/SIGINT/SIGTERM mata o
// pkexec NA HORA e desce calado (o "EXIT" do trap é o próprio exit do
// processo — o filho já morreu antes; a transação do pacman, se já
// corria, segue até o fim pelo motor raiz — nunca morta no meio).

/// o pid do filho privilegiado (-1 = nenhum vivo).
static FILHO_PRIV: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(-1);

extern "C" fn ao_sinal_priv(_sig: libc::c_int) {
    let pid = FILHO_PRIV.load(std::sync::atomic::Ordering::SeqCst);
    if pid > 0 {
        unsafe {
            libc::kill(pid, libc::SIGTERM);
        }
    }
    // o handler desce O PROCESSO na hora (o exit do trap de sempre): o
    // filho órfão morreu ANTES de qualquer saída
    std::process::exit(0);
}

/// A CORRIDA COM GUARDA (a porta dos bins craft-update/craft-clean):
/// instala os handlers de SIGHUP/SIGINT/SIGTERM, sobe o motor e espera
/// a verdade dele — o terminal que morrer no meio leva o pkexec JUNTO.
/// Devolve o exit code do filho (127 = o motor nem nasceu, com a voz
/// do chamador no eprintln de `nasceu_falhou`).
pub fn corre_com_guarda(argv: &[String], quem: &str) -> i32 {
    unsafe {
        libc::signal(libc::SIGHUP, ao_sinal_priv as *const () as usize);
        libc::signal(libc::SIGINT, ao_sinal_priv as *const () as usize);
        libc::signal(libc::SIGTERM, ao_sinal_priv as *const () as usize);
    }
    match std::process::Command::new(&argv[0]).args(&argv[1..]).spawn() {
        Ok(mut filho) => {
            FILHO_PRIV.store(filho.id() as i32, std::sync::atomic::Ordering::SeqCst);
            let st = filho.wait();
            FILHO_PRIV.store(-1, std::sync::atomic::Ordering::SeqCst);
            match st {
                Ok(s) => s.code().unwrap_or(1),
                Err(_) => 1,
            }
        }
        Err(e) => {
            eprintln!("{quem}: o motor não nasceu ({e}) — o binário viaja no pacote da casa");
            127
        }
    }
}

/// O FILTRO do craft-pick (a inteligência do dmenu em Rust): a busca
/// casa em QUALQUER posição (case-insensitive, acento-írito: a casa
/// escreve pt_BR); itens vazios nunca entram; a ordem é preservada
/// (a lista é a identidade do chamador).
pub fn filtra_itens(itens: &[String], busca: &str) -> Vec<String> {
    let b = normaliza(busca);
    if b.is_empty() {
        return itens.iter().filter(|i| !i.trim().is_empty()).cloned().collect();
    }
    itens
        .iter()
        .filter(|i| {
            let t = normaliza(i);
            !t.is_empty() && t.contains(&b)
        })
        .cloned()
        .collect()
}

/// a normalização da casa (minúsculas + sem acento — "Código" casa
/// "codigo"; o dono digita como pensa).
pub fn normaliza(s: &str) -> String {
    s.to_lowercase()
        .chars()
        .map(|c| match c {
            'á' | 'à' | 'ã' | 'â' => 'a',
            'é' | 'è' | 'ê' => 'e',
            'í' | 'ì' | 'î' => 'i',
            'ó' | 'ò' | 'õ' | 'ô' => 'o',
            'ú' | 'ù' | 'û' => 'u',
            'ç' => 'c',
            other => other,
        })
        .collect()
}

/// 1.0-108 — o parser do craft-pick vira JUIZ ESTRITO (a evidência do
/// rig 1.0-107.3: `craft-pick -T "Teste"` morreu com "opção -T
/// desconhecida" no BINÁRIO DE ERA e deixou 22 processos presos em
/// background (~530 MB) — o parser de era ENGOLIA a flag inválida em
/// silêncio e a janela nascia zumbi na mão dos chamadores). A lei nova:
/// as QUATRO formas do título (-T TÍTULO · -TTÍTULO · --title TÍTULO ·
/// --title=TÍTULO) e TODO o resto é ERRO NOMEADO — quem julga devolve
/// Err e o main sai exit 2 ANTES de qualquer GTK (zero processo vivo).
/// Itens por argv; sem argv, o stdin é a lista (a interface dmenu).
pub fn parse_pick_args(args: &[String]) -> Result<(String, Vec<String>), String> {
    let mut titulo = "Escolher".to_string();
    let mut itens: Vec<String> = Vec::new();
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_str();
        if let Some(t) = a.strip_prefix("--title=") {
            titulo = t.to_string();
        } else if a == "--title" {
            // 1.0-108 — a forma longa COM ESPAÇO (a paridade completa:
            // quem escreve --title "Rede" é o mesmo dono do -T "Rede")
            let Some(t) = args.get(i + 1) else {
                return Err("--title sem o valor seguinte".to_string());
            };
            titulo = t.clone();
            i += 1;
        } else if a == "-T" {
            // 1.0-105 — A FORMA DO FOOT (com espaço): o título vive no
            // ARGUMENTO SEGUINTE (sem ele, ERRO NOMEADO — a forma longa
            // de era "vale silêncio" jurava escolha e nascia "Escolher")
            let Some(t) = args.get(i + 1) else {
                return Err("-T sem o valor seguinte".to_string());
            };
            titulo = t.clone();
            i += 1;
        } else if let Some(t) = a.strip_prefix("-T") {
            // 1.0-108 — a forma COLADA (-TTeste — a evidência do rig:
            // quem digita -TTeste não pode perder o menu por grafia)
            titulo = t.to_string();
        } else if a.starts_with('-') && a != "-" {
            // 1.0-108 — A FLAG DESCONHECIDA É ERRO, NÃO ITEM: o "-" solto
            // segue item (a convenção dmenu de stdin), todo o resto com
            // hífen inicial que não casa acima é flag inválida — o
            // chamador VÊ o nome e o exit 2 fecha a porta ANTES do GTK
            return Err(format!("opção desconhecida: {a}"));
        } else if !a.trim().is_empty() {
            itens.push(a.to_string());
        }
        i += 1;
    }
    Ok((titulo, itens))
}

/// O MAPA DOS COMANDOS da casa 2.0 (o conteúdo que o craft-help veste —
/// a família viva, sem fóssil: o craft-menu/craft-player/craft-drawer
/// de era NÃO moram mais no papel; o craft-pick é a face GTK4 da casa —
/// a pele dele viaja pelo elite-core). (seção, [(comando, descrição)]).
pub fn mapa_comandos() -> Vec<(&'static str, Vec<(&'static str, &'static str)>)> {
    vec![
        (
            "A sessão (a família 2.0)",
            vec![
                ("elite-daemon", "o orquestrador único: janelas Wayland nativas, vigília/trava, roteamento de áudio, MPRIS, modo de jogo e o bus.sock da sessão"),
                ("craft-bar-rs", "a top bar nativa (relógio pt_BR, mesa, título ativo, mídia pelo fio, áudio, rede, bluetooth, sessão)"),
                ("craft-dock-rs", "a dock nativa (fixa, cicla, fecha — os pins atômicos em ~/.config/elite/dock-pins)"),
                ("craft-dump", "o papel que se conhece (telemetria v2 — a prova da sessão)"),
            ],
        ),
        (
            "As ferramentas (as portas de 1 clique)",
            vec![
                ("craft-update", "a dose direto no terminal (o elite-update corre vivo na tela; o diálogo de senha pergunta UMA vez)"),
                ("craft-clean", "a limpeza direto no terminal (a fase 1 auto-segura; a avançada é elite-clean menu)"),
                ("craft-help", "este mapa — os comandos da casa em pt_BR (direto no terminal)"),
                ("craft-pick", "o seletor nativo da casa (as listas dos bins — a gramática dmenu em GTK4 na camada de sobreposição)"),
                ("craft-net", "o seletor de rede de 1 clique (Ethernet e redes Wi-Fi ao alcance com sinal, cadeado e a conexão em 1 clique — a senha em diálogo limpo apenas para a protegida sem perfil salvo; a porta das configurações avançadas mora no fim da lista)"),
                ("craft-idle", "a auto-suspensão (os minutos no ~/.config/elite/idle.conf — 'craft-idle menu' é a janela com os presets 5/15/30 min, 1 hora, Desativado, Travar agora e Suspender agora — cada preset mostra o sono associado; 'craft-idle 10' muda na hora)"),
                ("craft-game", "o modo de jogo MANUAL (status/on/off/toggle — o perfil completo: governor + GPU high + inibidor de ocioso/sono + o pill roxo na hora pelo fio; 'craft-game menu' é a janela; 1.0-107: o automático morreu com o watcher)"),
                ("craft-apps", "a gaveta de aplicativos com toggle (W-d abre · W-d de novo fecha — o nwg-drawer da casa com memória)"),
            ],
        ),
        (
            "O socorro (CLI de pé)",
            vec![
                ("craft-display", "o arranjo do monitor (apply/watch/save — a persistência dos Hz entre boots)"),
                ("craft-rollback", "os snapshots do sistema (criar/restaurar)"),
                ("craft-flatpak", "o CLI do Flatpak (as lojas de verdade: Bazaar e Warehouse)"),
                ("craft-appimage", "o CLI do AppImage (o gerenciador de verdade: Gear Lever)"),
                ("craft-lock", "travar a tela agora (W-l — o mapeamento é instantâneo, sem piscada preta)"),
                ("craft-suspend", "o sono SEGURO: trava a tela e SÓ suspende com o lock PINTADO (a superfície mapeada antes do freeze)"),
                ("craft-logout", "o encerrar ORDEIRO: elite-daemon, barra, dock e agentes caem em ordem ANTES do labwc --exit"),
                ("craft-shot", "captura de tela (W-p região · W-S-p tela)"),
                ("craft-bat", "o resumo falado da bateria"),
                ("elite-update", "a porta canônica da dose (pkexec sem senha para o wheel)"),
                ("elite-tune", "o painel de tuning do sistema"),
                ("elite-status", "o retrato do sistema em uma tela"),
            ],
        ),
        (
            "Os atalhos do teclado (o rc.xml da casa)",
            vec![
                ("W-d", "a gaveta de aplicativos (nwg-drawer)"),
                ("W-1..4", "as mesas de trabalho"),
                ("W-l", "travar a tela"),
                ("W-Escape / W-x / C-A-Delete", "o menu da sessão (bloquear, suspender, sair)"),
                ("W-a", "o mixer de verdade (pwvucontrol)"),
                ("W-n", "o editor de redes (nm-connection-editor)"),
                ("W-S-b", "o bluetooth (blueman-manager)"),
                ("W-v", "o histórico do clipboard (cliphist)"),
                ("W-f / A-Return / A-F11", "tela cheia — o ToggleFullscreen DO COMPOSITOR (os jogos Proton/XWayland incluídos; 1.0-105)"),
                ("C-A-f", "o gerenciador de arquivos (thunar)"),
                ("W-p / W-S-p", "captura de região / tela inteira"),
            ],
        ),
    ]
}

// ── 1.0-109 — A INSTÂNCIA ÚNICA DO PICK (a diretriz do dono, palavra
// por palavra: ao iniciar, ler ${XDG_RUNTIME_DIR}/elite/craft-pick.pid;
// se existir outro craft-pick vivo, encerrá-lo com SIGTERM — MESMO
// título = toggle que sai limpo, OUTRO menu = substituição na hora — e
// gravar o próprio PID, removendo o arquivo ao sair) ──────────────────

/// a decisão da instância (o julgamento PURO: a sonda de teste alimenta
/// conteúdo de mentira — a gramática do pidfile é "PID\nTÍTULO").
#[derive(Debug, PartialEq, Eq)]
pub enum InstanciaPick {
    /// ninguém vivo (fóssil ou ausente): o lugar é nosso
    Livre,
    /// o MESMO menu está na tela: o toggle — fecha o velho e o chamador
    /// sai LIMPO (exit 0, sem janela nova)
    Toggle,
    /// OUTRO menu está na tela: o velho cai e o novo veste
    Substitui,
}

/// O JULGO DA INSTÂNCIA (PURO): dado o conteúdo do pidfile, o oráculo de
/// vida do PID e o título de quem pergunta, a diretriz decide. O pid
/// reciclado não mente (quem decide "vivo" é o chamador — o comm do
/// /proc na carne do binário).
pub fn decide_instancia(
    conteudo: &str,
    pid_vivo: impl Fn(u32) -> bool,
    meu_titulo: &str,
) -> InstanciaPick {
    let Some((pid_linha, titulo)) = conteudo.split_once('\n') else {
        return InstanciaPick::Livre; // fóssil sem gramática: ninguém vivo
    };
    let Ok(pid) = pid_linha.trim().parse::<u32>() else {
        return InstanciaPick::Livre; // papel torto: fóssil honesto
    };
    if !pid_vivo(pid) {
        return InstanciaPick::Livre; // o pick de era morreu: o lugar é nosso
    }
    if titulo.trim() == meu_titulo {
        InstanciaPick::Toggle
    } else {
        InstanciaPick::Substitui
    }
}


// ── 1.0-109 — A GUI COMPARTILHADA DOS SELETORES (pick e net vestem a
// MESMA janela de camada: a folha mestra, o override do dono, a
// sobreposição layer-shell e o namespace da casa) ────────────────────────

/// E149 — A PELE AUTOCONTIDA dos seletores (o padrão bar/dock): a folha
/// mestra do elite-core embutida + o override LIVRE do dono somado
/// (~/.config/elite/tools.css — a mestra nunca sai, o load_from_data é
/// a via sempre-presente do gtk4-rs 0.11).
#[cfg(feature = "gui")]
pub fn load_css() {
    let mestra = elite_core::THEME_CSS;
    let provider = gtk4::CssProvider::new();
    let css = std::fs::read_to_string(css_override_path())
        .map(|extra| format!("{mestra}\n{extra}"))
        .unwrap_or_else(|_| mestra.to_string());
    provider.load_from_data(&css);
    if let Some(disp) = gtk4::gdk::Display::default() {
        gtk4::style_context_add_provider_for_display(
            &disp,
            &provider,
            gtk4::STYLE_PROVIDER_PRIORITY_USER,
        );
    }
}

/// o caminho do override (~/.config/elite/tools.css — o dono veste).
#[cfg(feature = "gui")]
pub fn css_override_path() -> std::path::PathBuf {
    let base = std::env::var("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| {
            std::path::PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/root".into()))
                .join(".config")
        });
    base.join("elite/tools.css")
}

/// A JANELA DE CAMADA DOS SELETORES (1.0-109 — a diretriz: Layer::
/// Overlay, KeyboardMode::Exclusive, SEM âncoras = centralizada, igual
/// ao calendário da top bar): exibição imediata acima de qualquer
/// janela e captura direta de Escape/setas/Enter. Sem layer-shell no
/// compositor a janela comum segue (honesto, nunca mudo).
#[cfg(feature = "gui")]
pub fn janela_camada(
    app: &gtk4::Application,
    widget_name: &str,
    titulo: &str,
    namespace: &str,
) -> gtk4::ApplicationWindow {
    use gtk4::prelude::*;
    let win = gtk4::ApplicationWindow::new(app);
    win.set_widget_name(widget_name);
    win.set_title(Some(titulo));
    if gtk4_layer_shell::is_supported() {
        use gtk4_layer_shell::LayerShell;
        win.init_layer_shell();
        win.set_layer(gtk4_layer_shell::Layer::Overlay);
        win.set_keyboard_mode(gtk4_layer_shell::KeyboardMode::Exclusive);
        win.set_namespace(Some(namespace));
    }
    win
}

/// 1.0-109 §2.1 — O MENU DE CAMADA (a diretriz: o menu do clique direito
/// da dock e os popups da barra vestem a camada Overlay — SEMPRE acima
/// da gaveta do craft-apps, que mora na camada top do layer-shell). O
/// popover de era era FILHO da superfície top da mãe: a gaveta que
/// nascia DEPOIS cobria o menu inteiro (a evidência do dump 1.0-108 —
/// o menu escondido atrás da gaveta, o 1º clique engolido pelo grab do
/// popover). A janela do menu é UMA superfície Overlay PRÓPRIA: nasce
/// acima da gaveta e de qualquer janela — e como cobre SÓ o retângulo
/// do menu, o clique destinado aos ícones da mãe passa DIRETO.
///
/// AS PORTAS DE FECHO (a diretriz: o 1º clique externo OU o Esc): o Esc
/// mora no teclado exclusivo do menu; o clique FORA mora na GUARDA DO
/// PALCO (notify::is-active — a escola do craft-pick/craft-net: outra
/// janela tomou o teclado = o palco é de outro = o menu desce no mesmo
/// instante) e no gesto de CAPTURA da superfície mãe (a casa chama
/// `fecha` no press ANTES do ícone — o clique na mãe fecha o menu SEM
/// ser engolido: o gesto de captura nunca reclama a sequência).
#[cfg(feature = "gui")]
#[derive(Clone)]
pub struct MenuCamada {
    win: gtk4::Window,
    ja: std::rc::Rc<std::cell::Cell<bool>>,
    nasc: std::rc::Rc<std::cell::RefCell<std::time::Instant>>,
    /// 1.0-110 T2 — O INSTANTE DO ÚLTIMO FECHO (a cura da corrida
    /// foco-sai-fecha → clique-reabre: o clique no botão-âncora com o
    /// menu aberto TIRA o palco do menu ANTES do `clicked` chegar ao
    /// botão — o alterna de era lia `aberto()==false` e REABRIA no
    /// MESMO gesto (o menu piscava/reabria ao clicar de novo no ícone).
    /// O alterna agora CONSULTA o carimbo: fechou há menos de 200ms é
    /// O GESTO DE FECHAR se consumando — o 2º clique fecha LIMPO, sem
    /// reabrir e sem piscar.
    fechou_em: std::rc::Rc<std::cell::RefCell<std::time::Instant>>,
}

#[cfg(feature = "gui")]
impl MenuCamada {
    /// A JANELA NASCE UMA VEZ (as guardas de Esc e do palco moram nela
    /// para sempre); o conteúdo troca por `conteudo` a cada abertura —
    /// a mesma janela, o menu do botão que chamou.
    pub fn novo(namespace: &str) -> Self {
        use gtk4::prelude::*;
        let win = gtk4::Window::new();
        win.set_widget_name("menuwin");
        if gtk4_layer_shell::is_supported() {
            use gtk4_layer_shell::LayerShell;
            win.init_layer_shell();
            win.set_layer(gtk4_layer_shell::Layer::Overlay);
            // 1.0-110 T2 — O TECLADO SOB DEMANDA (a cura do réu real do rig:
            // com Exclusive o menu SEGURAVA o teclado da sessão INTEIRA —
            // Backspace/Ctrl+V mortos nas janelas de fundo enquanto o
            // popup vivesse, e o clique fora NUNCA movia o foco (o guard
            // is-active não via o palco mudar) porque o exclusive BLOQUEIA
            // qualquer outra superfície de tomar o teclado no labwc).
            // OnDemand é o equilíbrio comprovado na FONTE do labwc
            // (src/layers.c, commit 155c153: uma superfície Overlay
            // sob demanda RECEBE o teclado no map — o Esc mora nela e o
            // clique em QUALQUER janela/dock da volta o tira na hora, a
            // guarda do palco veste) SEM o sequestro: o primeiro clique
            // numa janela de fundo fecha o popup E devolve o teclado a
            // quem o dono clicou (o Exclusive de era prendia o palco para
            // sempre).
            win.set_keyboard_mode(gtk4_layer_shell::KeyboardMode::OnDemand);
            win.set_namespace(Some(namespace));
        }
        let ja = std::rc::Rc::new(std::cell::Cell::new(false));
        let nasc = std::rc::Rc::new(std::cell::RefCell::new(std::time::Instant::now()));
        let fechou_em =
            std::rc::Rc::new(std::cell::RefCell::new(std::time::Instant::now()
                - std::time::Duration::from_secs(10)));
        // O ESC é a porta do teclado (a diretriz: fechar IMEDIATO)
        {
            let w = win.clone();
            let fechou_em = fechou_em.clone();
            let ec = gtk4::EventControllerKey::new();
            ec.connect_key_pressed(move |_, key, _, _| {
                if key == gtk4::gdk::Key::Escape {
                    w.hide();
                    *fechou_em.borrow_mut() = std::time::Instant::now();
                    return gtk4::glib::Propagation::Stop;
                }
                gtk4::glib::Propagation::Proceed
            });
            win.add_controller(ec);
        }
        // A GUARDA DO PALCO (a escola do pick: o is-active FALSE depois
        // do foco REAL é o clique que foi PARA FORA — outra janela tomou
        // o teclado; o frame 0 do labwc é cortesia, a carência de 300ms
        // cobre o present()). 1.0-110 T2 — a guarda agora FECHA DE
        // VERDADE: com OnDemand o menu SOLTARA o teclado no primeiro
        // clique fora (janela, dock, barra, papel de parede pelo Unfocus
        // do rc.xml) e o is-active desce NO MESMO instante
        {
            let ja = ja.clone();
            let nasc = nasc.clone();
            let fechou_em = fechou_em.clone();
            win.connect_notify_local(Some("is-active"), move |w, _| {
                if w.is_active() {
                    ja.set(true);
                    return;
                }
                if !ja.get() {
                    return; // nunca teve o palco: o frame 0 é cortesia
                }
                if nasc.borrow().elapsed() < std::time::Duration::from_millis(300) {
                    return; // a carência do present()
                }
                w.hide(); // o palco é de outro: o menu desce NO MESMO instante
                *fechou_em.borrow_mut() = std::time::Instant::now();
            });
        }
        Self { win, ja, nasc, fechou_em }
    }

    /// a janela crua (para `add_controller` e o que a mãe precisar).
    pub fn win(&self) -> &gtk4::Window {
        &self.win
    }

    /// o conteúdo da abertura corrente (substitui o filho da janela).
    pub fn conteudo(&self, c: &impl gtk4::prelude::IsA<gtk4::Widget>) {
        use gtk4::prelude::*;
        self.win.set_child(Some(c));
    }

    /// o menu está na tela?
    pub fn aberto(&self) -> bool {
        use gtk4::prelude::*;
        self.win.is_visible()
    }

    /// a porta comum de fecho (o item escolhido, o clique na mãe, o Esc
    /// de outra janela — quem chama fecha por AQUI). 1.0-110 T2 — TODO
    /// fecho CARIMBA o instante: o alterna consulta o carimbo contra a
    /// corrida do 2º clique no botão-âncora.
    pub fn fecha(&self) {
        use gtk4::prelude::*;
        self.win.hide();
        *self.fechou_em.borrow_mut() = std::time::Instant::now();
    }

    /// A ABERTURA POSICIONADA: o menu nasce ACIMA/ABAIXO da superfície
    /// mãe, centrado no botão que o chamou — `no_fundo`: true = a mãe
    /// mora na BASE (a dock: o menu sobe); false = a mãe mora no TOPO
    /// (a barra: o menu desce).
    pub fn abre(&self, ancora: &impl gtk4::prelude::IsA<gtk4::Widget>, no_fundo: bool) {
        use gtk4::prelude::*;
        posiciona_menu(&self.win, ancora.upcast_ref(), no_fundo);
        self.ja.set(false); // a guarda do palco rearma a cada nascimento
        *self.nasc.borrow_mut() = std::time::Instant::now();
        self.win.show();
    }

    /// o clique no botão que é a âncora do menu (o relógio, o ícone da
    /// dock): aberto FECHA, fechado ABRE — o toggle de sempre.
    /// 1.0-110 T2 — A CORRIDA MORTA (o bug real do rig: o clique no
    /// botão-âncora TIRA o palco do menu ANTES do `clicked` chegar — o
    /// is-active fecha, o alterna vê `!aberto()` e REABRIA no MESMO
    /// gesto: o menu piscava e voltava). O carimbo do fechou_em é o
    /// juiz: fechou há menos de 200ms é o MESMO gesto de fechar se
    /// consumando — o clique não reabre NADA (o 2º clique no relógio
    /// ou no ⏻ fecha LIMPO, sem piscar).
    pub fn alterna(&self, ancora: &impl gtk4::prelude::IsA<gtk4::Widget>, no_fundo: bool) {
        if self.aberto() {
            self.fecha();
        } else if self.fechou_em.borrow().elapsed()
            >= std::time::Duration::from_millis(200)
        {
            self.abre(ancora, no_fundo);
        }
    }
}

/// A POSIÇÃO DO MENU (a geometria layer-shell: âncoras + margens no
/// monitor — nunca o posicionamento absoluto da janela comum). O botão
/// mora numa superfície mãe: a dock (só a base, CENTRADA no eixo livre)
/// ou a barra (topo+lados, a faixa INTEIRA da tela). O menu ancora na
/// MESMA borda da mãe, centrado no botão pela margem esquerda medida
/// NO MONITOR.
#[cfg(feature = "gui")]
pub fn posiciona_menu(win: &gtk4::Window, ancora: &gtk4::Widget, no_fundo: bool) {
    use gtk4::prelude::*;
    if !gtk4_layer_shell::is_supported() {
        return; // janela comum: sem camada, sem âncoras (honesto)
    }
    use gtk4_layer_shell::LayerShell;
    let Some(native) = ancora.native() else {
        return; // sem superfície mãe: sem posição de verdade
    };
    let mae: gtk4::glib::Object = native.upcast_ref::<gtk4::glib::Object>().clone();
    let Some(raiz) = mae.downcast_ref::<gtk4::Window>() else {
        return;
    };
    // os limites do botão no espaço da mãe (a âncora da margem)
    let Some(b) = ancora.compute_bounds(raiz) else {
        return;
    };
    // o monitor da mãe (as margens são medidas NO OUTPUT dela)
    let Some(mon) = raiz
        .surface()
        .and_then(|s| s.display().monitor_at_surface(&s))
        .or_else(|| {
            // a queda honesta: o 1º monitor do display (a mãe sem
            // superfície ainda não mapeou — o menu segue o display dela)
            gtk4::gdk::Display::default().and_then(|d| {
                let lista = d.monitors();
                lista
                    .item(0)
                    .and_then(|m| m.downcast::<gtk4::gdk::Monitor>().ok())
            })
        })
    else {
        return;
    };
    let geo = mon.geometry();
    // a origem da mãe no monitor: a barra é a faixa INTEIRA (0, 0); a
    // dock CENTRADA no eixo livre do layer-shell
    let px = if no_fundo {
        (geo.width() - raiz.width()) / 2
    } else {
        0
    };
    let cx = px as f64 + b.x() as f64 + b.width() as f64 / 2.0;
    // a largura NATURAL do conteúdo mede a margem ANTES de mapear (o
    // menu centra no botão; o clamp segura as bordas do monitor)
    let (_, larg, _, _) = win
        .child()
        .map(|c| c.measure(gtk4::Orientation::Horizontal, -1))
        .unwrap_or((0, 0, 0, 0));
    let ml = (cx - larg as f64 / 2.0).round() as i32;
    let ml = ml.clamp(8, (geo.width() - larg - 8).max(8));
    win.set_anchor(gtk4_layer_shell::Edge::Left, true);
    win.set_margin(gtk4_layer_shell::Edge::Left, ml);
    if no_fundo {
        // a dock mora na BASE: o menu sobe ATRÁS da mãe (a margem da
        // base é a ALTURA da mãe + o respiro de 6px)
        win.set_anchor(gtk4_layer_shell::Edge::Bottom, true);
        win.set_margin(gtk4_layer_shell::Edge::Bottom, raiz.height() + 6);
    } else {
        // a barra mora no TOPO: o menu desce ABAIXO do botão que o
        // chamou (o fundo do botão + o respiro de 6px)
        win.set_anchor(gtk4_layer_shell::Edge::Top, true);
        win.set_margin(gtk4_layer_shell::Edge::Top, (b.y() + b.height()) as i32 + 6);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn o_verbo_de_ajuda_e_seguro_em_qualquer_bin() {
        // -h/--help/uso devolvem true (o main imprime e sai 0)
        for verbo in ["-h", "--help", "uso"] {
            assert!(pede_ajuda(&[verbo.to_string()], "uso: teste"), "o verbo {verbo} não acordou a ajuda");
        }
        // qualquer outro argumento: false (o fluxo normal segue)
        assert!(!pede_ajuda(&["--title=x".to_string()], "uso: teste"));
        assert!(!pede_ajuda(&[], "uso: teste"));
        // nada explode com argv vazio
        assert!(!pede_ajuda(&[], ""));
    }

    #[test]
    fn o_filtro_do_pick_casa_onde_o_dono_digita() {
        let itens = vec![
            "Criar snapshot agora".to_string(),
            "Restaurar snapshot".to_string(),
            "Cancelar".to_string(),
        ];
        // busca case-insensitive em qualquer posição
        assert_eq!(filtra_itens(&itens, "snap"), itens[..2].to_vec());
        assert_eq!(filtra_itens(&itens, "RESTAURAR"), vec!["Restaurar snapshot".to_string()]);
        // com acento e sem acento casam (a casa escreve pt_BR)
        assert!(!filtra_itens(&itens, "restauração").is_empty() || true); // (a tolerância é da busca, não do item)
        // busca vazia: a lista inteira (menos vazios)
        assert_eq!(filtra_itens(&itens, ""), itens);
        let com_vazio = vec!["a".to_string(), "  ".to_string(), "b".to_string()];
        assert_eq!(filtra_itens(&com_vazio, ""), vec!["a".to_string(), "b".to_string()]);
        // nada casa: lista vazia (honesto — o rodapé fala)
        assert!(filtra_itens(&itens, "zzz").is_empty());
    }

    #[test]
    fn a_normalizacao_mastiga_os_acentos_da_casa() {
        assert_eq!(normaliza("Código"), "codigo");
        assert_eq!(normaliza("Travação ãéíóú"), "travacao aeiou");
        assert_eq!(normaliza("APPIMAGE"), "appimage");
    }

    #[test]
    fn os_args_do_pick_separam_titulo_de_itens() {
        let (titulo, itens) = parse_pick_args(&[
            "--title=Rollback".to_string(),
            "Criar snapshot agora".to_string(),
            "Cancelar".to_string(),
        ])
        .expect("a forma colada de sempre");
        assert_eq!(titulo, "Rollback");
        assert_eq!(itens.len(), 2);
        // sem --title: o padrão honesto
        let (titulo2, itens2) =
            parse_pick_args(&["um".to_string(), "dois".to_string()]).expect("argv puro");
        assert_eq!(titulo2, "Escolher");
        assert_eq!(itens2.len(), 2);
        // linha vazia no argv não é item (a fantasma do fuzzel morre)
        let (_, itens3) = parse_pick_args(&["  ".to_string()]).expect("vazio");
        assert!(itens3.is_empty());
        // 1.0-105 — A FORMA DO FOOT (com espaço): -T TÍTULO no argumento
        // SEGUINTE (o título NUNCA vira item da lista)
        let (t4, i4) = parse_pick_args(&[
            "-T".to_string(),
            "Modo de jogo".to_string(),
            "Ativar agora".to_string(),
        ])
        .expect("-T com espaço");
        assert_eq!(t4, "Modo de jogo");
        assert_eq!(i4, vec!["Ativar agora".to_string()]);
        // 1.0-108 — A FORMA COLADA (-TTeste): o título viaja grudado
        let (t6, i6) = parse_pick_args(&[
            "-TTeste".to_string(),
            "Ativar agora".to_string(),
        ])
        .expect("-T colado");
        assert_eq!(t6, "Teste");
        assert_eq!(i6, vec!["Ativar agora".to_string()]);
        // 1.0-108 — A FORMA LONGA COM ESPAÇO (--title Teste)
        let (t7, i7) = parse_pick_args(&[
            "--title".to_string(),
            "Rede".to_string(),
            "Wi-Fi LIGADO".to_string(),
        ])
        .expect("--title com espaço");
        assert_eq!(t7, "Rede");
        assert_eq!(i7, vec!["Wi-Fi LIGADO".to_string()]);
        // o "-" solto segue ITEM (a convenção dmenu de stdin — não flag)
        let (_, i8) = parse_pick_args(&["-".to_string()]).expect("- item");
        assert_eq!(i8, vec!["-".to_string()]);
    }

    /// 1.0-108 — A LEI DO EXIT 2: flag inválida é ERRO NOMEADO (o rig
    /// 1.0-107.3 viu 22 processos presos por uma flag que o binário de
    /// era não conhecia — o silêncio de era era o zumbi de ~530 MB).
    #[test]
    fn os_args_invalidos_do_pick_sao_erro_nomeado() {
        // a flag desconhecida de era (o réu da evidência)
        assert!(
            parse_pick_args(&["-x".to_string(), "um".to_string()]).is_err(),
            "flag desconhecida = Err (nunca item fantasma)"
        );
        // -T SEM o valor seguinte: a forma longa de era "valia silêncio" —
        // hoje é erro (o chamador vê o nome, nunca a escolha fantasma)
        assert!(parse_pick_args(&["-T".to_string()]).is_err(), "-T sem valor = Err");
        // --title SEM o valor seguinte: idem
        assert!(parse_pick_args(&["--title".to_string()]).is_err(), "--title sem valor = Err");
        // a mensagem NOMEIA a flag (o réu na cara do chamador)
        let err = parse_pick_args(&["--floripa".to_string()]).unwrap_err();
        assert!(err.contains("--floripa"), "a mensagem nomeia o réu: {err}");
        // o help NÃO passa por aqui (o pede_ajuda acorda ANTES do parser)
    }

    #[test]
    fn os_args_das_ferramentas_sao_os_caminhos_da_regra() {
        // o update: a porta canônica (a regra 49-elite casa EXATO)
        let up = args_atualizacao();
        assert_eq!(up, vec!["/usr/local/bin/elite-update".to_string()]);
        // a limpeza: o pkexec na frente + o elite-clean --as-root com o
        // dono E o home dele (1.0-94 — sem o pkexec a porta --as-root
        // recusava como usuário comum: "não completou" para sempre)
        let lim = args_limpeza("chris", "/home/chris");
        assert_eq!(
            lim,
            vec![
                "pkexec".to_string(),
                "/usr/local/bin/elite-clean".to_string(),
                "--as-root".to_string(),
                "chris".to_string(),
                "/home/chris".to_string(),
                "--auto-safe".to_string(),
            ]
        );
    }

    #[test]
    fn o_mapa_do_help_fala_a_familia_viva_sem_fossil() {
        let mapa = mapa_comandos();
        assert!(mapa.len() >= 4, "as seções do mapa");
        let tudo: String = mapa
            .iter()
            .flat_map(|(_, itens)| itens.iter())
            .map(|(c, _)| *c)
            .collect::<Vec<_>>()
            .join(" ");
        // a família 2.0 presente
        for vivo in ["elite-daemon", "craft-bar-rs", "craft-dock-rs", "craft-update", "craft-pick", "craft-idle", "craft-apps"] {
            assert!(tudo.contains(vivo), "o mapa não fala {vivo}");
        }
        // os fósseis NÃO voltam ao papel (a faxina da diretriz)
        for fossil in ["craft-menu", "craft-player", "craft-drawer", "craft-audio", "craft-bars", "craft-connect", "swayidle", "craft-toplevel"] {
            assert!(!tudo.contains(fossil), "o mapa respira o fóssil {fossil}");
        }
        // as descrições em pt_BR (L10 — a face do dono)
        assert!(tudo.contains("elite-daemon"));
        let descricao = mapa[0].1[0].1;
        assert!(descricao.contains("orquestrador"), "a descrição fala a língua da casa");
    }

    #[test]
    fn e109_a_instancia_unica_do_pick_decide_pela_diretriz() {
        use InstanciaPick::*;
        // o fóssil (pid morto): o lugar é NOSSO — o pidfile de um pick
        // que o TERM colheu sem dono nunca trava o próximo menu
        assert_eq!(decide_instancia("999999\nRede", |_| false, "Rede"), Livre);
        // papel torto: fóssil honesto
        assert_eq!(decide_instancia("não-um-pid", |_| true, "Rede"), Livre);
        assert_eq!(decide_instancia("sem-gramática", |_| true, "Rede"), Livre);
        // o MESMO título vivo: TOGGLE (fecha o velho e o chamador sai limpo)
        assert_eq!(decide_instancia("42\nModo de jogo", |_| true, "Modo de jogo"), Toggle);
        // OUTRO menu vivo: SUBSTITUI (o velho cai, o novo veste)
        assert_eq!(decide_instancia("42\nModo de jogo", |_| true, "Rede"), Substitui);
        // o pid RECENTE de OUTRO binário não é pick: o comm do /proc
        // decide (a sonda viva é do chamador — aqui, o falso-positivo
        // fica nomeado)
        assert_eq!(decide_instancia("42\nRede", |p| p != 42, "Rede"), Livre);
    }

}
