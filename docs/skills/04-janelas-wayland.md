# 04 · Janelas e Otimização Wayland — a sessão labwc da casa

> Fontes: wmww/gtk4-layer-shell ★349 (a biblioteca em uso real na bar/dock),
> labwc/labwc ★2.934 (o compositor da casa), end-4/dots-hyprland ★16.720 e
> hyprwm/Hyprland ★40.776 (escola rice), COSMIC/escola. Ancorado em:
> `crates/craft-bar-rs`, `crates/craft-dock-rs`, `crates/elite-daemon`,
> `elite/airootfs/etc/skel/.config/labwc/{rc,menu,autostart}`.

## 1. Layer-shell: a gramática fixa das superfícies da casa

A barra e a dock são superfícies de camada (gtk4-layer-shell) — a fundação
fixa o contrato:

| Superfície | Camada | Âncora | Exclusive zone | Keyboard |
|---|---|---|---|---|
| `craft-bar-rs` | TOP | NORTH (W/E) | sim (reserva a altura própria) | on-demand (popovers) |
| `craft-dock-rs` | TOP | SOUTH (W/E) | auto/exclusive | on-demand |
| popovers GTK4 | herdam a superfície do pai | — | — | on-demand durante aberto |

1. **Keyboard-interactivity on-demand**: a superfície só pede teclado quando
   tem popover/entrada aberta. Camada que rouba teclado fixo rouba o foco das
   janelas reais (o bug classe do "menu não fecha ao clicar fora" — o clique
   fora fecha porque o teclado voltou à janela).
2. **Exclusive zone honesta**: a barra reserva a ALTURA dela (o labwc empurra
   as janelas); a dock reserva a dela. Reserve menos = janela embaixo da
   barra; reserve mais = faixa morta. A pílula da dock NÃO é exclusive zone
   nova a cada frame — é a janela layer que se redimensiona (ver §3).
3. **Margem é arranjo fino, não layout**: âncora + margem posa a ilha; nunca
   usar margem para "empurrar" conteúdo (isso é do box interno).

## 2. Foreign-toplevel: a dock é LEITOR, nunca adivinhador

A dock lista janelas via wlr-foreign-toplevel (o wlrctl vendado ★ da casa é o
falante CLI da mesma gramática):

1. **Estado vem de EVENTO, não de poll**: `toplevel` chega/altera/morre por
   evento do protocolo. Nada de varrer a cada N segundos (a lei zero-polling
   da casa — o `elite-daemon` também só acorda por evento: NameOwnerChanged,
   uevent DRM, logind).
2. **Foco via wlr-foreign-toplevel/activate** (o `wlrctl` vendored: `focus =
   alias de activate`, `app_id` casa EXATO por strcmp, exit 1 sem match — o
   contrato que a dock usa para tentar o próximo candidato).
3. **O snapshot só é puxado na montagem inicial** (e no SIGUSR2 de troca de
   monitor); o resto do tempo é event-driven. Redesenho: `queue_draw()` +
   `queue_resize()` da pílula E da janela NO MESMO FRAME (a dupla cura E144
   do "fantasma"/espaço preto) — sem flush síncrono extra.

## 3. O frame discipline (por que a pílula não encolhe "sozinha")

O réu real (`dock.log` do rig: `Finalizing dockbtn … still has children left:
GtkPopoverMenu` ×20 + espaço preto à direita): remontar a pílula sem fechar o
ciclo de vida do popover órfão e sem comitar o resize no mesmo frame.

A lei fixa (já curada na 1.0-94/E144, formalizada aqui):

1. **popdown() + unparent() ANTES do remove()** de qualquer botão que tenha
   popover — o GtkPopoverMenu órfão é o vazamento nomeado; `queue_resize()` da
   janela fecha o ciclo no MESMO frame.
2. **Resize é commit, não animação**: superfície layer-shell que muda de
   tamanho comita no frame (`queue_resize`); animar width de superfície de
   camada = repaint storm + flicker. A cortesia de 150ms vive no HOVER de
   fundo (guia 03 R7), nunca no resize da pílula.
3. **Nenhum widget morto fica pendurado**: `wl_surface` só recalcula de
   verdade quando a ÁRVORE GTK reflete a remoção — unparent → remove →
   queue_resize, nessa ordem, no mesmo handler.

## 4. Janelas de ferramenta: o labwc manda na moldura

As janelas (`#toolswin`, `#pickwin`) e os menus XML são governados pelo
labwc (rc.xml/menu.xml + theme):

1. **O menu.xml do skel (`elite/airootfs/etc/skel/.config/labwc/menu.xml`)
   é VALIDADO antes de sair**: parse XML estrito + todo `<action
   name="Execute">` aponta para binário EXISTENTE (a porteira da suíte já
   contrata isso — o craft-drawer fantasma foi o réu desta classe).
2. **`rc.xml` define a moldura/window-rules**; o tema do labwc (cor de
   moldura) segue os MESMOS tokens (superfície `#11111b`, borda `#262637`,
   acento `#a855f7`) — coerência total ou nada.
3. **A sessão é o menu elite-sessao do labwc** (W-Escape/W-x/C-A-Del) — o
   menu do labwc fecha sozinho no clique fora (o craft-menu-dismiss morreu
   com direito: a E143 aposentou o wrapper e o clique-fora é do upstream).

## 5. Otimização: o custo zero é uma LEI, não uma preferência

| Prática | Custo | Status na casa |
|---|---|---|
| Alpha em `@define-color` | zero (composite que o labwc já faz) | LEI (guia 02 §2) |
| Blur de superfície (shader) | GPU por frame em TODA a tela | PROIBIDO (o labwc nem faz — honestidade §fronteira) |
| Polling de estado (X s em loop) | CPU acordando por nada | PROIBIDO (event-driven: bus.sock, uevent, logind) |
| Transição CSS de layout (width/margin) | relayout + repaint | PROIBIDO em layer-shell (resize é commit) |
| Redesenho parcial (queue_draw no widget) | zero vs redraw global | LEI nos handlers de toplevel |
| Delegar ao pacote maduro (pwvucontrol, blueman, nwg-drawer) | RAM do processo sob demanda | LEI §7 (o Rust da casa murcha quando a ferramenta morre) |

A delegação também é a porta de portabilidade futura (o bloco RPM da
Diretriz): a casa Rust fala protocolos padrão (layer-shell, foreign-toplevel,
PipeWire via wpctl, NM via nmcli) — nada de dependência de biblioteca
exótica que quebre fora do Arch.

## 6. O mapa de cliques (Diretriz Mestre, fixado para o Bloco 2)

| Módulo da barra | Clique esquerdo (principal) | Clique direito (rápido) |
|---|---|---|
| Áudio | `pwvucontrol` (controle completo) | mute/desmute da saída |
| Microfone | `pwvucontrol` (aba entrada) | mute/desmute do mic |
| Bluetooth | `blueman-manager` (gerenciador real) | alternar power do BT |
| Rede | interface prática do dia a dia (NUNCA o editor técnico de conexões salvas como fluxo principal) | alternar Wi-Fi |
| Relógio | calendário (popover nativo) | — |
| Notificações | `swaync-client -t -sw` | DND (`-d -sw`) |
| Sessão | menu nativo (PopoverMenu) | — |
| Aplicativos | gaveta (nwg-drawer, toggle) | menu rápido do sistema |

Um destino = um lugar (a duplicidade "Bloquear/Encerrar" em dois menus do
dump morre aqui).
