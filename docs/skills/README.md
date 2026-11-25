# docs/skills — Fundação Visual do Archcraft Elite

> Bloco 1/3 da Diretriz Mestre (sobre `c8e0035`, era 1.0-97) + os guias
> permanentes da era E151 (onda final 2/2). Pesquisa em fontes REAIS da
> comunidade + a fundação visual fixada em números, não opinião. Nada aqui
> é improviso genérico: cada guia cita arquivos e crates reais desta casa
> (`crates/elite-core/assets/theme.css`, `crates/craft-bar-rs`,
> `crates/craft-dock-rs`, `crates/craft-tools`,
> `elite/airootfs/etc/skel/.config/labwc/`) e bugs reais do rig do dono
> (`dump_1_0_96.txt` + capturas).
>
> **A LEI DE ENTRADA (E151):** qualquer agente ou mantenedor DEVE ler
> TODOS os arquivos `docs/skills/*.md` (e a `AGENTS.md` da raiz) ANTES de
> editar qualquer código deste repositório — a paleta, a tipografia e as
> regras inegociáveis (zero `--` em comentário XML, itens do menu em
> texto puro, botões de janela à direita, zero `Co-Authored-By`, zero
> tag de trabalho) moram aqui e na constituição.

## Os guias

| Arquivo | O que fixa |
|---|---|
| [`01-hierarquia-visual.md`](01-hierarquia-visual.md) | A gramática visual GNOME / COSMIC / macOS / Hyprland aplicada à barra, dock, popovers e janelas da casa |
| [`02-paleta-oficial.md`](02-paleta-oficial.md) | A paleta oficial em `#HEX` (com ratios de contraste WCAG medidos + mapa de migração do `theme.css` atual) |
| [`03-css-gtk4-alto-contraste.md`](03-css-gtk4-alto-contraste.md) | As regras de CSS GTK4 de alto contraste — incluindo a cura dos bugs de contraste do dump |
| [`04-janelas-wayland.md`](04-janelas-wayland.md) | Organização de janelas e otimização Wayland (layer-shell, foreign-toplevel, zero-polling, transparência de custo zero) |
| [`05-filosofia-extrema.md`](05-filosofia-extrema.md) | **E151** — o zero desperdício: pacotes sob demanda = 0 MB idle, instância única, zero Xorg/Python ocioso, enterro com substituto e manutenção automatizada |
| [`06-ui-ux-gtk4-wayland.md`](06-ui-ux-gtk4-wayland.md) | **E151** — a superfície obsidiana ÚNICA entre barra e dock, o reset de estados GTK4 (`:checked`/`:focus`), o redimensionamento síncrono `gtk4-layer-shell` e a convenção de clique esquerdo vs. direito |

> **Divergência entre guias:** o guia mais recente vence (02 fixou a
> paleta Mocha da era 1.0-98; 06 fixa a identidade OBSIDIANA da E151 —
> os tokens `elite-bg`/`elite-bg-dock`/`elite-border` da folha mestra
> (`crates/elite-core/assets/theme.css`) são a FONTE DE VERDADE VIVA).

## O método (por que estas fontes e não outras)

Toda referência abaixo foi **verificada viva via API autenticada do GitHub
em 2026-11-25** (HTTP 200, estrelas reais do dia) ou acessada diretamente
(HTTP 200). A busca bruta da sessão irmã sobreviveu ao reset do sandbox
(`upload/skills-search-irma-2026-11-25-1129.json`, 121.945 resultados — o
achado dela, `ui-ux-pro-max-skill`, é a peça central) e o
[TrendShift](https://trendshift.io) foi consultado diretamente no mesmo dia
(HTTP 200 — trending geral consultado; os repos temáticos abaixo vieram da
verificação por nome, porque o leaderboard do dia não era temático).

### Fontes verificadas (2026-11-25)

| Fonte | ★ (dia da verificação) | O que emprestamos |
|---|---|---|
| [`nextlevelbuilder/ui-ux-pro-max-skill`](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | 153.987 | O método: design intelligence com contraste MEDIDO, hierarquia por papel, zero decoração sem função — a estrutura destes guias segue esta escola |
| [`catppuccin/catppuccin`](https://github.com/catppuccin/catppuccin) | 19.976 | A base da paleta: `#11111b`/`#181825`/`#cba6f7`/`#cdd6f4` são os tokens Mocha (crust/mantle/mauve/text). A casa JÁ vestia mauve/red/overlay0 desde a 1.0-93 (`#bb9af7`, `#f38ba8`, `#6c7086` no `theme.css`) — esta fundação formaliza o resto |
| [`end-4/dots-hyprland`](https://github.com/end-4/dots-hyprland) | 16.720 | A rice de referência "usability-first": superfícies elevadas em vez de preto chapado, ilha/canto arredondado, animação de 150ms como limite de cortesia |
| [`hyprwm/Hyprland`](https://github.com/hyprwm/Hyprland) | 40.776 | O ecossistema de rices e o vocabulário de acabamento (cantos, bordas, gap) que o dono reconhece como "rice moderno" |
| [`labwc/labwc`](https://github.com/labwc/labwc) | 2.934 | O compositor da casa: rc.xml/menu.xml/theme — os limites HONESTOS do que o skin da casa controla (o labwc não faz blur: a regra de transparência é alpha, nunca blur — ver guia 04) |
| [`wmww/gtk4-layer-shell`](https://github.com/wmww/gtk4-layer-shell) | 349 | A biblioteca que a barra e a dock já usam: âncoras, exclusive zone, keyboard-interactivity — a fundação técnica do guia 04 |
| [`GNOME/libadwaita`](https://gitlab.gnome.org/GNOME/libadwaita) (mirror no GitHub) | 120 | O HIG do GNOME: estados de hover/foco com delta de lightness, listas de densidade, diálogos — a gramática de estados do guia 03 |
| COSMIC (System76) | — | O princípio de superfícies elevadas por camada (desktop→painel→popover) e tipografia nítida; citado como escola de design, não como API |
| macOS (HIG da Apple) | — | Ergonomia de dock (alvo de 44px, bolinha de app em execução) e contenção visual — citado como escola de ergonomia |

### A regra anti-genérico (constituição destes guias)

1. **Todo conselho cita onde vive no código da casa** — arquivo, crate, seletor CSS
   ou caminho do skel. Conselho sem âncora na casa não entra.
2. **Todo número é medido, não sentido** — contraste em ratio WCAG, tempo de
   animação em ms, custo de memória em decisão explícita (alpha vs blur).
3. **Todo bug citado veio de prova real** — o `dump_1_0_96.txt` e as capturas
   do rig do dono nomeiam os réus; os guias curam por classe, não por instância.
4. **Zero descontinuidade com as leis da casa** — §7 (enterro com substituto),
   zero-polling, `queue_resize` no mesmo frame, PT-BR no produto (L10).
