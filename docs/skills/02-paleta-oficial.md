# 02 · Paleta Oficial do Archcraft Elite (#HEX fixada)

> Ordem da Diretriz Mestre (Bloco 1/3). Base real: Catppuccin Mocha
> (catppuccin/catppuccin ★19.976, verificado 2026-11-25) — a casa já vestia
> 3 tokens Mocha desde a 1.0-93 — com acento primário Tailwind purple-500.
> Todos os ratios abaixo são WCAG 2.1 medidos por script em 2026-11-25
> (luminância relativa IEC), não estimados a olho.

## 1. Os tokens oficiais

| Papel | HEX | Herança | Ratio medido |
|---|---|---|---|
| **Base (superfície elevada)** | `#11111b` | Catppuccin Mocha *crust* | — |
| **Fundo de ilha (dock, popovers)** | `#181825` | Catppuccin Mocha *mantle* | texto sobre ela: **12.14:1 AAA** |
| **Acento primário (ações, seleção, switch ligado)** | `#a855f7` | Tailwind *purple-500* | texto `#11111b` sobre ela: **4.74:1 AA** |
| **Acento suave (hover de ação, foco, secondary)** | `#cba6f7` | Catppuccin Mocha *mauve* | como texto sobre base: **9.23:1 AAA**; texto escuro sobre ela: **9.23:1 AAA** |
| **Borda inativa (grafite)** | `#262637` | da casa (substitui `#3b3355`) | texto sobre ela (hover): **10.26:1 AAA** |
| **Texto principal** | `#cdd6f4` | Catppuccin Mocha *text* | sobre base: **12.97:1 AAA** |
| **Texto de título/nítido** | `#f8fafc` | Tailwind *slate-50* | sobre base: **17.92:1 AAA** |

Tokens secundários que **MANTÊM** (já Catppuccin Mocha e já em produção no
`theme.css`): perigo `#f38ba8` (*red*), desligado/ausente `#6c7086`
(*overlay0*), texto-dim `#a9a3c2` (da casa, 8.0:1 sobre a base).

**Proibido**: `#000000` puro chapado em qualquer superfície (a ordem do dono —
superfícies escuras ELEVADAS, a escola GNOME/COSMIC/rice end-4); texto cinza
apagado sobre fundo escuro abaixo de 4.5:1; roxo neon (saturação total) como
fundo — o acento é PONTO, não área.

## 2. Regras de transparência e blur (custo zero de CPU/RAM)

1. **Alpha é grátis, blur não.** O compositor da casa (labwc ★2.934) não faz
   blur de superfície — e o blur em compositor wlroots/Hyprland custa
   shader/GPU por frame. Regra da casa: **transparência = alpha no token**
   (ex.: `rgba(17, 17, 27, 0.96)` na barra, `rgba(24, 24, 37, 0.92)` na dock),
   **nunca backdrop-filter, nunca shader de blur**.
2. **Níveis de alpha por camada** (leitura do wallpaper sem perder contraste):
   barra 0.96 · dock 0.92 · popovers/janelas 0.97+ (quase opaco — o texto
   precisa da base estável). O alpha não altera o ratio medido acima até
   ~0.9 sobre wallpapers escuros; abaixo disso, re-medir.
3. **Zero repaint extra**: o alpha vive no `@define-color` do
   `crates/elite-core/assets/theme.css` (a pele viaja NO binário via
   `include_str!`) — nenhuma superfície nova, nenhum buffer novo, nenhum
   custo além do composite que o labwc já faz.
4. **Onde NÃO aplicar**: listas de texto longo (craft-help/update em modo
   terminal não têm pele — e janelas de leitura densa ganham opacidade cheia).

## 3. Mapa de migração do `crates/elite-core/assets/theme.css` (1.0-93 → nova)

| Token atual | Valor atual | Valor oficial novo |
|---|---|---|
| `elite-bg` | `rgba(19,17,28,0.96)` (#13111c) | `rgba(17,17,27,0.96)` (#11111b) |
| `elite-bg-dock` | `rgba(27,24,41,0.92)` (#1b1829) | `rgba(24,24,37,0.92)` (#181825) |
| `elite-surface` | `rgba(27,24,41,0.95)` (#1b1829) | `rgba(38,38,55,0.95)` (#262637) |
| `elite-surface-strong` | `rgba(59,51,85,0.95)` (#3b3355) | `rgba(46,46,61,0.97)` (degrau acima do grafite) |
| `elite-border` | `rgba(59,51,85,0.9)` (#3b3355) | `rgba(38,38,55,0.9)` (#262637) |
| `elite-text` | `#e6e4f0` | `#cdd6f4` |
| *(novo)* `elite-text-bright` | — | `#f8fafc` (relógio, títulos) |
| `elite-accent` | `#9d7cd8` | `#a855f7` |
| `elite-accent-strong` | `#bb9af7` | `#cba6f7` |
| `elite-text-dim` | `#a9a3c2` | mantém |
| `elite-danger` | `#f38ba8` | mantém (já Mocha) |
| `elite-off` | `#6c7086` | mantém (já Mocha) |
| literais `#13111c` soltos (textview, calendar:selected) | 3 ocorrências | trocar pelo token (nada de valor fora do `@define-color`) |

**A disciplina do token único**: nenhuma regra do theme.css escreve HEX
direto — só `@define-color` define e só `@elite-*` consome. Os skins externos
(swaync, nwg-drawer) recebem os MESMOS valores nos seus formatos (a promessa
do cabeçalho da folha mestra, hoje cumprida à mão — manter sincronizado neste
mapa a cada mudança).

## 3b. Os consumidores fora do GTK (BLOCO 4, 1.0-98) — as DUAS TELAS DE ENTRADA

O lock e o greeter vestem a MESMA paleta (a promessa dos skins externos
estendida às telas de entrada da sessão):

| Superfície | Arquivo | Consumo |
|---|---|---|
| Lock (hyprlock v8) | `elite/airootfs/etc/skel/.config/hypr/hyprlock.conf` | relógio `#f8fafc` · data/campo `#cdd6f4` · ilha `rgba(24,24,37,…)` (#181825) · borda inativa `#262637` · foco/validando `#a855f7` · erro `#f38ba8` · rodapé `#a9a3c2` · raio 20 (o raio da dock) |
| Greeter (SDDM archcraft) | `elite/airootfs/usr/share/sddm/themes/archcraft/theme.conf` | relógio `#f8fafc` · data/campos `#cdd6f4` · borda inativa `#262637` · **borda roxa ATIVA em foco** `HighlightBorderColor #a855f7` · erro `#f38ba8` · botão/seleção `#a855f7` com texto `#11111b` · hover `#cba6f7` (nunca inverte para claro) · RoundCorners 20 / PopupRadius 12 |

Regras BLOCO 4: `HeaderText` vazio (uma voz por tela — zero saudação);
blur leve (lock: 3 passes/size 8 · greeter: FullBlur 1.0/BlurMax 64) — o
custo é do instante da tela, zero consumo residual na sessão ativa;
cursor único Bibata do greeter ao desktop (`kde_settings.conf`). A fonte
única dos valores é ESTE mapa: mudou aqui, mudam os dois arquivos no
MESMO commit.

## 4. Contraste: as 4 leis numéricas

1. Corpo de texto: **≥ 4.5:1** (AA) — todos os pares oficiais passam (mínimo
   medido 4.74:1 no texto sobre acento primário).
2. Texto grande/título (≥18px ou ≥14px bold): **≥ 3:1** — passa com folga
   (17.92:1 no título).
3. Borda separadora visível: **≥ 3:1 contra ambas as superfícies que separa**
   — `#262637` contra `#11111b` e `#181825` cumpre como LINE de borda; como
   FUNDO de hover cumpre com texto 10.26:1.
4. **Hover nunca inverte para claro** — a cura do "hover branco sobre texto
   branco" do dump: hover sobe a superfície um degrau (grafite), NUNCA
   pinta de branco/claro. Regra completa no guia 03.
