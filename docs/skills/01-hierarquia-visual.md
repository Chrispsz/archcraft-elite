# 01 · Hierarquia Visual — GNOME / COSMIC / macOS / Hyprland na casa Elite

> Fontes verificadas em 2026-11-25: GNOME/libadwaita (HIG), end-4/dots-hyprland
> ★16.720, hyprwm/Hyprland ★40.776, COSMIC (escola), macOS HIG (escola),
> nextlevelbuilder/ui-ux-pro-max-skill ★153.987 (método). Aplicação ancorada
> nos artefatos reais: `crates/craft-bar-rs`, `crates/craft-dock-rs`,
> `crates/craft-tools`, `crates/elite-core/assets/theme.css`,
> `elite/airootfs/etc/skel/.config/labwc/{rc,menu}.xml`.

## 1. O princípio único: superfícies elevadas por camada

GNOME (libadwaita), COSMIC e os rices Hyprland de referência (end-4) concordam
na MESMA lei de profundidade: **o preto chapado não existe — cada camada sobe
um degrau de lightness sobre a anterior**.

| Camada da casa | Superfície | Token oficial |
|---|---|---|
| Fundo do desktop (wallpaper, janelas de terceiros) | o wallpaper manda | — |
| Barra (`#barwindow`) | degrau 1 | `elite-bg` → `#11111b` @ 96% |
| Dock (`#dockbox` — a ilha) | degrau 2 | `elite-bg-dock` → `#181825` @ 92% |
| Popover / menu (`popover > contents`) | degrau 2 (mesma ilha da barra) | `elite-bg` + borda `#262637` |
| Janela de ferramenta (`#toolswin`, `#pickwin`) | degrau 2 | `elite-bg` |
| Hover dentro de uma ilha | +1 degrau local | `elite-surface` → `#262637` |
| Ativo/pressionado | +2 degraus locais | `elite-surface-strong` |

**Regra prática**: nunca duas camadas com a MESMA cor no mesmo eixo de visão.
O olho precisa ler "a barra está SOBRE o desktop" sem borda grossa. É a lição
dos itens escuros sem contraste do menu de energia (capturas do dono): o item
e o fundo tinham o mesmo degrau.

## 2. Ergonomia de dock (a escola macOS aplicada)

A `craft-dock-rs` já veste o essencial; o que fica FIXADO como lei:

- **Alvo mínimo 44×44px** por ícone (`#dockbox button { min-height/min-width: 44px }`
  — já no `theme.css`, mantém: é o alvo de toque do HIG Apple e o dono clicou
  reclamando de alvos pequenos antes).
- **A bolinha de execução é 6×3px centrada no fundo** (E36, já no
  `#dockbox button.running`) — estados por ACENTO (não por brilho), a leitura
  do macOS sem imitar o traço.
- **A pílula encolhe no MESMO frame** (`queue_resize` da pílula E da janela —
  a lei E144 contra o espaço preto à direita; ver guia 04).
- **Máximo de cortesia na animação: 150ms** (`transition: background 0.15s ease`
  já presente). Nada acima de 200ms: acima disso a interface parece lenta
  (medida do end-4 e do HIG Apple — o "não parecia apertado" do dono).

## 3. A barra: uma ação principal por módulo (a escola COSMIC/Hyprland)

COSMIC e os rices usabilidade-first compartilham o dogma que a Diretriz Mestre
fixou para a `craft-bar-rs`:

1. **O clique esquerdo abre a FERRAMENTA DEDICADA** do módulo (blueman-manager,
   pwvucontrol, interface de rede prática) — o popover custom só sobrevive onde
   há conversa rápida (mute, troca de dispositivo). Menus/popovers frágeis
   morrem onde o pacote dedicado já entrega controle completo (§7 da casa:
   enterro com substituto vivo).
2. **O clique direito é ação IMEDIATA** (mute/desmute, opções secundárias
   diretas) — nunca um segundo menu de navegação.
3. **O relógio é o centro EXATO** (`CenterBox`, E144) e o texto mais nítido da
   barra (`#f8fafc`, peso 600 — `#barbox #clockbtn` já veste o peso; a cor
   sobe com a paleta nova: o "relógio apagado em cinza" do dump morre pelo
   token, não por ajuste manual).
4. **Uma ação = um gesto** (a lição B1 da dock — dois GestureClick disputando
   a mesma sequência é bug, não feature).

## 4. Ordem de leitura e densidade

- **Zona quente**: o que o dono toca por hora (dock, apps, áudio, rede) vive nas
  bordas da tela; o que ele toca por dia (menus de sessão) vive nos cantos
  opostos — duplicar "Bloquear tela"/"Encerrar sessão" no menu rápido E no menu
  de energia foi o ruído apontado no dump: **um destino = um lugar**.
- **Densidade**: listas e menus usam padding 7-8px vertical por item
  (`popover > contents button { padding: 7px 14px }` — já no theme.css) e
  separador de 4px de margem. Itens de densidade "compatta" (o craft-pick)
  mantêm 8px — o craft-pick é teclado-primeiro.
- **Tipografia**: 15px na barra (corpo), 13px no dim/secundário, 14-16px em
  títulos de janela/painel. Peso: 400 corpo, 600 relógio/títulos, 700 título
  de ferramenta (`label.title`). Fonte da barra: JetBrainsMono NF já no CSS —
  mas os ÍCONES são `from_icon_name` (a lei E147: glifo Nerd quebrado nunca
  mais; o Papirus/GNOME da casa tem os simbólicos todos).

## 5. Estados: a gramática única da casa

| Estado | Tratamento | Onde já está |
|---|---|---|
| Repouso | transparente sobre a ilha | `#barbox > button` |
| Hover | `elite-surface` (#262637) | `button:hover` |
| Ativo | `elite-surface-strong` | `button:active` |
| Seleção (lista/menu) | `elite-surface-strong` | `row:selected` |
| Sucesso/ligado | acento `#a855f7` | `switch:checked` |
| Perigo | `#f38ba8` (texto, não fundo) | `button.muted`, `.destructive` |
| Desligado/ausente | `#6c7086` (overlay0) | `button.off` |
| Foco (teclado) | outline 2px `#cba6f7` | **fixado no guia 03** — falta no theme.css atual |

A mesma gramática em TODA superfície: barra, dock, popovers, janelas e os
skins externos (swaync, nwg-drawer recebem os mesmos tokens pelos skins do
pacote — o theme.css já promete isso no cabeçalho).
