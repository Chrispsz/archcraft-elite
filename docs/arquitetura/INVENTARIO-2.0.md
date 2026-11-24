# INVENTÁRIO 2.0 — Antes → Destino (a Fase 1 da reconstrução)

A lei §7 da constituição: **o enterro tem SUBSTITUTO vivo antes da pá**.
Esta tabela é o mapa de cada peça da era 1.0 e o destino dela na 2.0 —
nada morre sem endereço. Fonte: a perícia da árvore na Fase 1
(E141a/E141b/E141c).

## A camada Rust (o workspace `crates/`)

| Peça (era 1.0) | Destino na 2.0 | Estado |
|---|---|---|
| `vendor/rust/` (morada) | `crates/` (git mv — a história preservada) | ✅ E141a |
| `elite-daemon` | continua — o orquestrador único (session/game/supervise); módulos Wayland nativo/PipeWire/S3/game na Fase 2 | ✅ E142b (wayland/idle/audio/mpris/workspace/nucleo nativos) |
| `craft-dock-rs` | continua — dock v2; pele = folha mestra; pins via `elite-core::persist` | ✅ E142c (fala o bus) |
| `craft-bar-rs` | continua — top bar nativa; pele = folha mestra | ✅ E142d (pílulas/título/mídia pelo fio) |
| `elite-core` | **NOVO** — contratos tipados, bus.sock IPC, persistência atômica, Design System | ✅ E141a+E142a (bus bidirecional) |
| `craft-dump-rs` | **NOVO** — telemetria v2 (núcleo puro; coleta completa na Fase 2) | ✅ E143 (o papel v2 completo: boot/serviços/família/bus/áudio/vigília) |
| `craft-tools` | **NOVO (Fase 2)** — as janelas nativas craft-update/craft-clean/craft-help + o seletor craft-pick (a gramática dmenu em GTK4 na folha mestra) | ✅ E143 |
| `craft-toplevel.c` | **MORTO E142b/E142c** — o daemon é o cliente `zwlr-foreign-toplevel` nativo; o pacote próprio, o hook elite-adopt e o toplevel.sock morreram juntos | ✅ sepultado |
| DEFAULT_CSS duplicado (bar+dock) | `crates/elite-core/assets/theme.css` — A FOLHA MESTRA ÚNICA embutida nos dois | ✅ E141a |

## A faxina (os fósseis)

| Peça (era 1.0) | Destino na 2.0 | Estado |
|---|---|---|
| `waybar` | morto na E140 (packages.add/remove + skel) — a barra é `craft-bar-rs` | ✅ zero spawn vivo |
| `craft-audio` (UI Python) | morto na E140 — wpctl direto + pwvucontrol | ✅ zero spawn vivo |
| `craft-pin-pick` | morto na E140 — o popover da dock tomou o lugar | ✅ zero spawn vivo |
| `craft-bars` (supervisor sh) | **aposentado E141b** — o autostart convoca `elite-daemon session` DIRETO (guard honesto no bars.log) | ✅ |
| `craft-connect` (fuzzel rede/BT) | **aposentado E141b** — iwgtk / nm-connection-editor / blueman-manager são as telas | ✅ |
| `craft-menu` + `craft-menu-dismiss` | **MORTOS E143** — os 12 chamadores rebobinados: os menus de escolha viram `craft-pick` (dmenu nativo GTK4), update/limpeza/ajuda viram as janelas `craft-tools`, sessão é o menu `elite-sessao` do labwc e o dismiss é lei do próprio compositor | ✅ zero chamada viva |
| `craft-player` (polling 1s) | **MORTO E143** — o MPRIS é nativo no daemon (zbus por evento) e a barra veste o `media_pill` pelo bus | ✅ |
| `craft-power` + `craft-logout` | **MORTOS E143** — os verbos são itens do menu `elite-sessao` (labwc nativo) e o popover da barra | ✅ |
| `craft-drawer` (wrapper) | **MORTO E143** — o W-d e o item Aplicativos convocam o `nwg-drawer` DIRETO | ✅ |
| `craft-audio-route` (python) | **MORTO E142b** — o roteador é o `audio.rs` do daemon (as 4 classes, o piso da voz, o pactl subscribe) | ✅ |
| `mousepad` | packages.remove (gnome-text-editor é o editor) | ✅ |
| `craft-dock-gui` (dock Python) | morto na E134 — ceifa de migração viva no post_upgrade/craft-update | ✅ |

## O tuning sagrado (preservado — §7: só se SOMA, idempotente)

| Peça | Estado |
|---|---|
| `sysctl.d/99-elite-performance.conf` (swappiness 180, BBR+fq, max_map_count, MGLRU) | ✅ intacto |
| `udev/rules.d/99-elite-zram.rules` (SYSCTL 180 vence o vendor) | ✅ intacta |
| `udev/rules.d/60-ntsync.rules` | ✅ intacta |
| `modprobe.d/99-elite-powersave.conf` | ✅ intacto |
| GRUB: `mitigations=off` + `nowatchdog` **SOMAM** nos 2 ramos (AMD/NVIDIA), ppfeaturemask/nvidia_drm preservados | ✅ E141b |
| wake-guard (91 system-sleep, classe áudio dorme), GameMode (PORTA 5), CoolerControl (override --disable-gpu + garante_ancoras_vivas) | ✅ intactos (E140) |

## As ferramentas dedicadas (a diretriz §4)

`iwgtk` · `nm-connection-editor` · `blueman` · `pwvucontrol` · `swaync` ·
`coolercontrol` · `nwg-drawer` · `gnome-text-editor` · `papers` ·
`brave-origin` · `udiskie` · `cliphist` · `swayosd` ·
Flatpaks adotados: `Bazaar` · `Warehouse` · `Gear Lever`.

O **swayidle** saiu da lista na Fase 2: a vigília (trava + DPMS +
suspend + inibidores) é o `ext-idle-notify-v1` NATIVO do elite-daemon
— o pacote vai ao packages.remove com voz (a fronteira é legível).

Réu que a porteira REAL pegou: a E138 pediu pavucontrol, a E140 rewired
a casa para **pwvucontrol** e a lista nunca acompanhou — a ISO nascia com
o mixer que os binds não chamam. ✅ curado (E141c).

## A suíte (a porteira)

| Peça (era 1.0) | Destino na 2.0 | Estado |
|---|---|---|
| `tests/phases/30-unit.sh` + `40-integration.sh` (7k linhas de mocks) | **aposentados** — os mocks que passavam com a tela quebrada | ✅ E141c |
| `tests/phases/10-estrutura` + `20-estatica` + `30-cargo` + `60-veredito` | **NOVA porteira real** (contratos sobre a árvore, zero mocks — 125 na Fase 2) | ✅ E141c → E143 |
| `tests/session_smoke/` | Nível 2 — a sessão viva: zero legado, família de pé, bus respondendo, áudio/tuning/boot no ferro | ✅ E143 (o run real é do rig/sessão de prova) |
| `tests/iso-qemu/` | Nível 3 — a ISO no QEMU: marcos do boot + o PAPEL (craft-dump v2 + journal) colhido DE DENTRO da VM pelo serial | ✅ E143 (o run real pede a ISO construída) |
