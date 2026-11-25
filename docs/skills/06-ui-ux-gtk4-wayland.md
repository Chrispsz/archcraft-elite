# 06 · UI/UX GTK4 + Wayland — a superfície ÚNICA e o reset de estados

> Ordem do dono (E151, onda final 2/2). A gramática de UI que a era da
> identidade OBSIDIANA fixou, ancorada nos artefatos reais:
> `crates/elite-core/assets/theme.css` (a FOLHA MESTRA),
> `crates/craft-bar-rs/src/ui.rs` (`apaga_foco_da_barra`),
> `crates/craft-dock-rs/src/ui.rs` (`flush_superficie`), e os peles do
> skel (`~/.config/elite/{bar,dock}.css`). Complementa os guias 01–04 —
> onde este guia diverge, este vence (a ordem é mais recente).

## 1. A superfície obsidiana ÚNICA (barra e dock vestem IGUAL)

A identidade visual da casa é UMA superfície escura compartilhada:

| Papel | Valor | Onde vive |
|---|---|---|
| Barra (faixa topo) | `rgba(13, 13, 18, 0.96)` — #0d0d12 | token `elite-bg` |
| Dock (ilha base) | `rgba(19, 19, 26, 0.92)` — #13131a | token `elite-bg-dock` |
| Borda sutil (ambas) | `rgba(203, 166, 247, 0.16)` — mauve | token `elite-border` |

Leis derivadas:

1. **Zero drift bar≠dock** — mudou a superfície, mudam os TRÊS lugares no
   MESMO commit: o `theme.css` (embutido nos binários), a pele viva do
   skel (`bar.css`/`dock.css`) e o marcador de migração do post-upgrade
   (a pele de fábrica velha sai do home pela rede de marcadores).
2. **O brilho é uniforme** — TODOS os itens da barra vestem `#cdd6f4`
   (relógio/títulos: `#f8fafc` + `font-variant-numeric: tabular-nums`);
   estado ativo = acento suave `#cba6f7`; mutado/desligado = perigo
   `#f38ba8`. Ícone cinza-apagado em assento vivo é BUG, não estilo.
3. **Disciplina do token único (R1 do guia 03 continua)** — nenhuma regra
   escreve HEX literal; só `@define-color` define, só `@elite-*` consome.

## 2. O reset de estados GTK4 (o fim do seletor travado e do quadrado branco)

O tema externo (libadwaita/tema GTK) pinta `:checked`/`:focus` com
fundo de seleção e sombra — o "seletor roxo travado" e o "quadrado
branco" do MenuButton de energia eram ISSO. A cura é DUPLA e obrigatória:

1. **No Rust** — a pálida do foco corre sobre a árvore PRONTA no fim do
   build: `set_focus_on_click(false)` + `set_can_focus(false)` em TODO
   botão/menubutton da barra (`apaga_foco_da_barra`).
2. **No CSS** — a barra NÃO tem regra `:focus` (o R5 do guia 03 vale
   apenas onde o teclado CHEGA: popovers, dock, janelas); e o
   MenuButton veste `background: transparent; background-image: none;
   box-shadow: none; outline: none` nos estados `:checked`/`:active`/
   `:focus` — fechou o popover, o botão volta ao repouso SEM resíduo.
3. **A reação da barra é EXCLUSIVAMENTE `:hover` suave** (um degrau de
   superfície, R3 — nunca cor nova, nunca contorno).

## 3. O redimensionamento síncrono gtk4-layer-shell (a lei do frame)

Superfície de camada que muda de conteúdo comita NO MESMO FRAME —
atraso visual ou "faixa preta" é defeito, não natureza:

1. **O flush é ÚNICO** (`flush_superficie`): `queue_draw()` +
   `queue_resize()` da pílula E da janela + o flush do display — TODOS
   os caminhos terminam nele:
   - snapshot do bus (Closed · Minimize · Maximize — o dreno chama o
     flush SEMPRE, mesmo sem mudança de conjunto: o evento de flags
     não espera outra ação na tela);
   - repack (Pin · Unpin · abertura);
   - ouvidor de monitores (geometria/escala/hotplug).
2. **Resize é commit, não animação** (E144 do guia 04 continua) — a
   cortesia de 150ms vive SÓ no hover de fundo, nunca no resize.
3. **O enterro dos popovers antes do remove** (E148 continua) —
   `popdown()` + `unparent()` de qualquer popover filho antes do
   remove do botão; o flush fecha o ciclo no mesmo frame.

## 4. A convenção de cliques (o mapa do guia 04 refinado)

| Superfície | Esquerdo | Direito | Meio |
|---|---|---|---|
| Barra · Aplicativos | gaveta (craft-apps, toggle) | idem | — |
| Barra · Áudio (saída) | `pwvucontrol` | mute da saída | — |
| Barra · Microfone (entrada) | `pwvucontrol` | mute do mic | — |
| Barra · Rede | `iwgtk` (ausente = `nm-connection-editor`) | rádio Wi-Fi (o cabo NUNCA cai) | — |
| Barra · Bluetooth | `blueman-manager` | power do adaptador | — |
| Barra · Relógio | painel swaync (`-t -sw`) | DND (`-d -sw`) | calendário |
| Barra · Sessão | popover nativo | — | — |
| Dock · app | focar/ciclar/minimizar (toggle E89) | menu completo (Fixar · Nova janela · Fechar) | **NADA** (o meio morreu na E151 — um destino = um lugar) |

Leis derivadas: um gesto = um verbo (o clique dispara EXCLUSIVAMENTE no
`released` com tolerância de arrasto <5px); o verbo "encerrar" mora num
ÚNICO lugar (o menu) — nenhum clique escondido de meio; scroll é ajuste
fino (volume/ganho/faixa) e nunca verbo destrutivo.

## 5. O checklist da entrada (qualquer PR de pele)

1. Os valores novos moram nos tokens `@define-color`? (grep é o juiz)
2. A barra continua SEM `:focus` e SEM fundo de seleção no menubutton?
3. Todo caminho de evento termina no `flush_superficie`?
4. O meio não ganhou verbo novo? (o menu completo é o único destrutivo)
5. A pele viva do skel e o marcador do post-upgrade mudaram JUNTOS com o
   `theme.css`? (zero drift entre binário e home)
6. PT-BR em todo texto visível (L10) — o CSS pinta, não escreve.
