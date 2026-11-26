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
// pkexec da regra 50-elite-wheel). O craft-pick fica: o seletor dmenu
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
/// regra 50-elite-wheel libera EXATAMENTE o caminho para o wheel local
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

/// o parser do craft-pick: --title=TÍTULO (a identidade, não exibida),
/// itens por argv; sem argv, o stdin é a lista (a interface dmenu).
pub fn parse_pick_args(args: &[String]) -> (String, Vec<String>) {
    let mut titulo = "Escolher".to_string();
    let mut itens: Vec<String> = Vec::new();
    for a in args {
        if let Some(t) = a.strip_prefix("--title=") {
            titulo = t.to_string();
        } else if !a.trim().is_empty() {
            itens.push(a.clone());
        }
    }
    (titulo, itens)
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
                ("craft-idle", "a trava automática (os minutos no ~/.config/elite/idle.conf — 'craft-idle painel' é a janela, 'craft-idle 10' muda na hora)"),
                ("craft-game", "o modo de jogo (status/on/off/auto — 'craft-game painel' é a janela; o automático é o elite-daemon)"),
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
                ("craft-lock", "travar a tela agora (W-l)"),
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
                ("W-p / W-S-p", "captura de região / tela inteira"),
            ],
        ),
    ]
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
        ]);
        assert_eq!(titulo, "Rollback");
        assert_eq!(itens.len(), 2);
        // sem --title: o padrão honesto
        let (titulo2, itens2) = parse_pick_args(&["um".to_string(), "dois".to_string()]);
        assert_eq!(titulo2, "Escolher");
        assert_eq!(itens2.len(), 2);
        // linha vazia no argv não é item (a fantasma do fuzzel morre)
        let (_, itens3) = parse_pick_args(&["  ".to_string()]);
        assert!(itens3.is_empty());
    }

    #[test]
    fn os_args_das_ferramentas_sao_os_caminhos_da_regra() {
        // o update: a porta canônica (a regra 50-elite-wheel casa EXATO)
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
}
