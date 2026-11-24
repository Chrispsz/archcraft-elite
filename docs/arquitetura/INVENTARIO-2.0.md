# INVENTÁRIO 2.0 — Antes → Destino (a Fase 1 da reconstrução)

A lei §7 da constituição: **o enterro tem SUBSTITUTO vivo antes da pá**.
Esta tabela é o mapa de cada peça da era 1.0 e o destino dela na 2.0 —
nada morre sem endereço. Fonte: a perícia da árvore na Fase 1
(E141a/E141b/E141c).

## A camada Rust (o workspace `crates/`)

| Peça (era 1.0) | Destino na 2.0 | Estado |
|---|---|---|
| `vendor/rust/` (morada) | `crates/` (git mv — a história preservada) | ✅ E141a |
| `elite-daemon` | continua — o orquestrador único (session/game/supervise); módulos Wayland nativo/PipeWire/S3/game na Fase 2 | ✅ movido |
| `craft-dock-rs` | continua — dock v2; pele = folha mestra; pins via `elite-core::persist` | ✅ movido |
| `craft-bar-rs` | continua — top bar nativa; pele = folha mestra | ✅ movido |
| `elite-core` | **NOVO** — contratos tipados, bus.sock IPC, persistência atômica, Design System | ✅ E141a |
| `craft-dump-rs` | **NOVO** — telemetria v2 (núcleo puro; coleta completa na Fase 2) | ✅ E141a |
| `craft-toplevel.c` | vive até o daemon consumir `zwlr-foreign-toplevel` nativamente via `wayland-client` | Fase 2 |
| DEFAULT_CSS duplicado (bar+dock) | `crates/elite-core/assets/theme.css` — A FOLHA MESTRA ÚNICA embutida nos dois | ✅ E141a |

## A faxina (os fósseis)

| Peça (era 1.0) | Destino na 2.0 | Estado |
|---|---|---|
| `waybar` | morto na E140 (packages.add/remove + skel) — a barra é `craft-bar-rs` | ✅ zero spawn vivo |
| `craft-audio` (UI Python) | morto na E140 — wpctl direto + pwvucontrol | ✅ zero spawn vivo |
| `craft-pin-pick` | morto na E140 — o popover da dock tomou o lugar | ✅ zero spawn vivo |
| `craft-bars` (supervisor sh) | **aposentado E141b** — o autostart convoca `elite-daemon session` DIRETO (guard honesto no bars.log) | ✅ |
| `craft-connect` (fuzzel rede/BT) | **aposentado E141b** — iwgtk / nm-connection-editor / blueman-manager são as telas | ✅ |
| `craft-menu` + `craft-menu-dismiss` | **VIVOS nesta fase** (12 bins da casa invocam em ~30 linhas ativas — enterro sem rebobinar = função sem substituto); destino: popovers nativos + ferramentas dedicadas, rebobinados na Fase 2 | ⏳ Fase 2 |
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
`brave-origin` · `swayidle` · `udiskie` · `cliphist` · `swayosd` ·
Flatpaks adotados: `Bazaar` · `Warehouse` · `Gear Lever`.

Réu que a porteira REAL pegou: a E138 pediu pavucontrol, a E140 rewired
a casa para **pwvucontrol** e a lista nunca acompanhou — a ISO nascia com
o mixer que os binds não chamam. ✅ curado (E141c).

## A suíte (a porteira)

| Peça (era 1.0) | Destino na 2.0 | Estado |
|---|---|---|
| `tests/phases/30-unit.sh` + `40-integration.sh` (7k linhas de mocks) | **aposentados** — os mocks que passavam com a tela quebrada | ✅ E141c |
| `tests/phases/10-estrutura` + `20-estatica` + `30-cargo` + `60-veredito` | **NOVA porteira real** (105 contratos sobre a árvore, zero mocks) | ✅ E141c |
| `tests/session_smoke/` | Nível 2 — a sessão viva (Fase 2) | ⏳ esqueleto nomeado |
| `tests/iso-qemu/` | Nível 3 — a ISO no QEMU (Fase 2) | ⏳ esqueleto nomeado |
