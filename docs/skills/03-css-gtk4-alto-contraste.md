# 03 · CSS GTK4 de Alto Contraste — as regras da casa

> Fontes: GNOME/libadwaita (HIG de estados), nextlevelbuilder/ui-ux-pro-max-skill
> ★153.987 (contraste medido), catppuccin/catppuccin ★19.976 (tokens). Alvo
> real: `crates/elite-core/assets/theme.css` (a FOLHA MESTRA ÚNICA, embutida
> via `include_str!` na bar/dock/tools com `STYLE_PROVIDER_PRIORITY_USER`).
> Bugs de origem real: `dump_1_0_96.txt` + capturas do dono.

## 1. As sete regras (ordem de constituição)

**R1 · Todo valor mora em `@define-color`.** Nenhuma regra escreve HEX/rgba
literal. Os 13 tokens oficiais (guia 02) são a única fonte; skins externos
(swaync/nwg-drawer) recebem os mesmos valores nos formatos deles. Hoje há 3
literais `#13111c` soltos no theme.css (textview, calendar:selected) — a
migração os tokeniza.

**R2 · Seletor por NOME da casa, nunca universal.** `#barbox`, `#dockbox`,
`#toolswin`, `#pickwin`, `popover > contents` — IDs e o seletor de popover.
Proibido: `* {}`, seleção por tipo solta (`button {}` global) que vaza para
widgets de terceiros dentro dos popovers.

**R3 · Hover sobe um degrau, nunca inverte para claro.** A cura da classe do
"hover branco sobre texto branco" (capturas: item de menu ilegível no hover):

```css
/* ERRADO (a doença do dump): */
menuitem:hover { background: #ffffff; }        /* texto claro some */

/* CERTO (a regra da casa): */
popover > contents button:hover { background: @elite-surface; }   /* #262637 */
popover > contents button:active { background: @elite-surface-strong; }
```

O texto NUNCA muda de cor no hover (só o fundo sobe) — exceto o caso
documentado do `#appbtn label` (dim → principal no hover), que sobe PARA MAIS
contraste, nunca para menos.

**R4 · Seleção/hover de ação usa "hover invertido" com texto escuro.** Quando
o hover É a ação (item selecionado de lista, calendário, switch ligado), o
fundo veste o acento suave `#cba6f7` com texto `#11111b` (**9.23:1 AAA
medido**) — o padrão libadwaita de `row:selected`. O `calendar:selected` do
theme.css atual já segue o padrão (com o literal a tokenizar).

**R5 · Foco de teclado VISÍVEL em toda superfície interativa.** O theme.css
atual não tem regra de foco — a fundação fixa:

```css
#barbox button:focus, #dockbox button:focus,
popover > contents button:focus, #toolswin button:focus {
  outline: 2px solid @elite-accent-strong;   /* #cba6f7 */
  outline-offset: -2px;
}
```

Foco invisível = navegação por teclado cega (acessibilidade MANDATÓRIA da
casa). O outline negativo mantém o raio da borda.

**R6 · Estados nomeados por classe, não por cor inline no Rust.** `button.muted`,
`button.off`, `button.running`, `.destructive` — o Rust alterna CLASSES
(`add_css_class`/`remove_css_class`), o CSS decide a cor. Nunca
`set_color()` pontual: cor inline no Rust é o caminho do drift entre eras.

**R7 · Transição ≤150ms e só em propriedades baratas.** `transition:
background 0.15s ease` (já na dock). Transição em `background`/`color` é
grátis; em `margin`/`padding`/`width` causa relayout — proibido em superfícies
layer-shell (ver guia 04: o resize da pílula é commit no MESMO frame, não
animado).

## 2. Cura por classe dos bugs de contraste do dump

| Réu real (dump/captura) | A classe da cura |
|---|---|
| Hover branco sobre texto branco nos menus | R3 (hover = degrau de superfície, texto imutável) |
| Itens escuros sem contraste no menu de energia | camada 1 do guia 01 (item ≠ fundo) + R4 na seleção |
| Relógio central e ícones apagados em cinza | token `elite-text-bright` (#f8fafc) no `#clockbtn` + texto principal #cdd6f4 nos módulos |
| `\uf085 2` quebrado | já morto pela lei E147 (`from_icon_name`) — R6 reforça: glifo nunca viaja como texto |
| Itens do craft-pick dim demais | `elite-text` no repouso, `#f8fafc` no selecionado (teclado-primeiro) |

## 3. Checklist de revisão (o porteiro visual de qualquer PR de pele)

1. Nenhum HEX/rgba literal fora do bloco `@define-color` (grep é o juiz).
2. Todo estado interativo tem as 4 formas: repouso, hover, active, focus
   (o focus é o que mais falta — R5).
3. Todo par texto/fundo novo passou no script de ratio (≥4.5:1 corpo,
   ≥3:1 grande) — o número vai no comentário da regra.
4. Nenhum hover claro (R3) e nenhum fundo `#000000` (guia 02).
5. Os skins externos sincronizados com o mapa do guia 02 (§3).
6. PT-BR em todo texto visível (L10) — o CSS pinta, não escreve.
