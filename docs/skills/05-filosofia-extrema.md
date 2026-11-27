# 05 · Filosofia Extrema — o zero desperdício da casa Elite

> Ordem do dono (E151, onda final 2/2). A filosofia que governa as doses
> desde a era do debloat cirúrgico, agora FIXADA como skill permanente.
> Ancorada nos artefatos reais: `elite/packages.{add,remove}`,
> `elite/airootfs/etc/skel/.config/labwc/autostart` (o arranque limpo
> 1.0-108), `crates/elite-daemon/src/supervise.rs` (RESIDENTES_DEFAULT),
> `elite/airootfs/usr/local/bin/elite-dose` (pacman_agil/cache_enxuga).

## 1. A lei do zero desperdício

Cada processo residente, cada megabyte de RAM e cada linha de código são
DÍVIDA que o dono paga a cada boot. A pergunta antes de qualquer adição:

> "Isto acorda POR EVENTO ou vive acordado por nada?"

| Princípio | A prova na casa |
|---|---|
| **Pacotes sob demanda = 0 MB idle** | a barra não embute mixer/rede/BT — os cliques abrem `pwvucontrol`/`iwgtk`/`blueman-manager` (fechado = 0 MB; aberto = o pacote maduro inteiro) |
| **Instância única de daemons** | o `elite-daemon session` é O lançador (a lei E137); cada vaga trava em flock + gate de bus/comm (E135/E138) — nunca dois swaync, nunca dois agentes |
| **Zero Xorg ocioso** | o greeter do SDDM veste `DisplayServer=wayland` + `CompositorCommand=labwc` (E151) — ~91 MB de RAM que o login não paga mais |
| **Cada alicoe no berço certo** | 1.0-108 (o ARRANQUE LIMPO, reversão da E151 pela diretriz do dono): o udiskie `--automount --notify --no-tray` é ALICOE DE FRAME 0 no autostart do labwc — o berço (wallpaper, polkit, automount, keyring, clipboard) NÃO depende do supervisor; o par udev oneshot de era (`91-elite-automount.rules` + `elite-automount@.service`) aposentou: um dono por domínio, zero corrida |
| **Zero polling** | eventos: netlink uevent, ext-idle-notify, `PrepareForSleep`, bus.sock push; os belts de segundos são cinto, nunca motor (§5 da AGENTS.md) |
| **Um agente por domínio** | polkit ÚNICO (lxqt-policykit supervisionado; o autostart duplicado amordaçado por Hidden=true — o /etc/xdg nunca é tocado) |

## 2. O enterro com substituto vivo (a §7 da constituição aplicada)

Nada sai da árvore sem destino nomeado no MESMO commit:

- `udiskie de era (daemon cego)` → `udiskie --automount --notify --no-tray` no arranque limpo (1.0-108 — a reversão da E151; o par udev oneshot de era `elite-automount` aposentou no mesmo commit);
- `xorg-server` na ISO → `elite_wayland.conf` (o greeter no labwc);
- `hyprpolkitagent` → `lxqt-policykit-agent` supervisionado (roda de
  verdade no labwc v4 — o hyprtoolkit pedia layer-shell v5);
- `xz -9e` da ISO → `COMPRESSION="zstd" (-19 -T0)` (compressão
  comparável, descompressão MUITO mais rápida — o boot do live agradece);
- o cache velho do pacman → `cache_enxuga` (`paccache -rk1` nas duas
  portas da dose, com o antes/depois MB no papel).

## 3. A manutenção automatizada é parte da filosofia

O rig NUNCA depende de vigilância manual:

- `.github/workflows/maintenance.yml` — todo dia 1: `cargo check
  --workspace --locked` + a suíte porteira contra o Arch mais recente
  (a quebra upstream de `gdk4`/`gtk4-layer-shell` é nomeada ANTES de
  custar uma dose vermelha);
- o `elite-dose` enxuga o próprio cache a cada dose (a casa não pede
  faxina ao dono — ela se limpa);
- o `post_upgrade` é IDEMPOTENTE por desenho (rodar 2× = mesmo estado,
  §4) — a migração é automática e repetível.

## 4. O tuning de baixo nível é SAGRADO (o limite da faxina)

A faxina NUNCA toca o que o dono usa para calibrar a própria máquina:
`lactd`, `coolercontrold`, `ananicy-cpp`, `dbus-broker`, `systemd-oomd`,
`snapper`, o `sysctl` consolidado, o zram zstd, o ntsync e as regras udev
de I/O (NVMe `none`, SSD SATA `mq-deadline` — E151). Só se SOMA, sempre
idempotente, sempre com voz no papel.

## 5. O checklist da entrada (qualquer PR que adiciona processo/pacote)

1. O que isto consome EM IDLE? (não é aceito "quando aberto" como custo
   permanente)
2. Tem evento? (o daemon dorme no epoll/uevent/sinal — nunca loop de pgrep)
3. Tem flock/bus gate? (instância única é lei — E135/E138)
4. O enterro do substituto está no mesmo commit? (§7: nada sem destino)
5. O rig JÁ INSTALADO recebe a cura pela dose? (§4: zero comando manual)
6. A suíte porteira contrata o contrato novo? (L2 — contrato sem teste é
   promessa sem prova)
