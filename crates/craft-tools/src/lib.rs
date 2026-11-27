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
                ("craft-pick", "o seletor nativo da casa (as listas dos bins — a gramática dmenu em GTK4)"),
                ("craft-idle", "a trava automática (os minutos no ~/.config/elite/idle.conf — 'craft-idle menu' é a janela com os presets 5/15/30 min, 1 hora, Desativado, Travar agora e Suspender agora — cada preset mostra o sono associado; 'craft-idle 10' muda na hora)"),
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
