# ARQUITETURA 2.0 — o mapa canônico da casa

> Este é o **mapa canônico** da arquitetura do Archcraft ELITE 2.0: o
> que cada peça é, onde mora e como conversa. Ele **consolida** (não
> duplica): a lei suprema é o **`AGENTS.md`** (constituição — em
> conflito, ele vence); os detalhes de estilo visual vivem em
> **`docs/skills/`** (a folha mestra viva é
> `crates/elite-core/assets/theme.css`); o inventário da migração da
> era 1.0 → 2.0 está em `docs/arquitetura/INVENTARIO-2.0.md`; o mapa do
> repositório, em `docs/ESTRUTURA.md`.

## 1 · O workspace Rust (`crates/`)

| Crate | O papel |
|---|---|
| **`elite-core`** | a fundação: contratos tipados do estado, o protocolo do `bus.sock`, persistência atômica e o Design System (a folha mestra embutida) |
| **`elite-daemon`** | o orquestrador único da sessão (`elite-daemon session`): supervisiona as superfícies, escuta Wayland/D-Bus/netlink nativamente e publica o estado no bus |
| **`craft-bar-rs`** | a top bar GTK4 + layer-shell (pílulas, título, mídia, relógio/calendário, rádio de rede) |
| **`craft-dock-rs`** | a dock GTK4 + layer-shell (ícones, pins, popover do botão direito) |
| **`craft-tools`** | as janelas nativas (`craft-update`, `craft-clean`, `craft-help`, o seletor `craft-pick`) + o juiz `craft-audit` |
| **`craft-dump-rs`** | a telemetria v2 (o retrato do rig para o diagnóstico da casa) |

Toda a superfície gráfica é **uma família visual**: os ícones são NOMES
GTK (zero glifo Nerd), os popovers fecham com `popdown`+`unparent` antes
do `remove`, e a armadura RT (`fn arma_rt`) veste as duas janelas.

## 2 · O protocolo do bus (`/run/user/$UID/elite/bus.sock`)

Uma fonte de verdade, um enum no fio (`elite-core::BusMsg`):

- **publicação** — `Audio` · `Media` · `Network` · `Bluetooth` ·
  `GameMode` · `Window` · `Windows` (o snapshot inteiro, ordem MRU) ·
  `Workspace` · `Hello`;
- **pedido/veredito (2.0, bidirecional)** — o cliente manda
  `Req { id, req }` (`Activate`/`Minimize`/`Close` por id, `Snapshot`,
  `Media`, `Game`, `Workspace`, `DeskSet`, `DeskStep`) e o daemon ecoa
  `Ack { id, ok }` — o efeito mora no estado publicado a seguir;
- **snapshot de boas-vindas** — quem conecta recebe o estado inteiro no
  frame 0 (`BusReq::Snapshot` internamente): a barra acende e a dock
  lista janelas sem polling nenhum;
- a instância única é lei do fonte: `flock` + recusa com papel (a 2ª
  instância sai 0, o lock mora no tmpfs privado).

## 3 · A pele única (Design System)

`crates/elite-core/assets/theme.css` é a **folha mestra** — paleta,
raios, estados, tipografia — **embutida** nos binários (barra e dock
vestem a MESMA pele). `nwg-drawer` e `swayosd` recebem os mesmos
valores nos formatos deles. Nenhum componente parece bloco desconexo; o
relógio é hora/calendário (o sino DND morreu com o swaync — dispensado
pelo dono, nunca volta à árvore).

## 4 · O fluxo de boot da sessão

```
SDDM (tema elite, 100% pt_BR — Bem-vindo!/Entrar/Desligar…)
  └─ labwc (compositor; menu elite-sessao; W-f fullscreen)
      └─ autostart: elite-daemon session &   ← o ÚNICO lançador (E146)
          ├─ topbar  (craft-bar-rs)
          ├─ dock    (craft-dock-rs)
          └─ residentes + vagas supervisionadas (respawn 2s, try_wait
             nativo — o supervisor shell de era morreu)
```

O greeter é o tema `/usr/share/sddm/themes/elite` (QML puro, fundo
`#111116`, acento `#a855f7`, zero binário no repo) fixado por
`/etc/sddm.conf.d/elite.conf` (`Current=elite` + `CursorTheme=Bibata`).

## 5 · O sono S3 (a máquina que dorme e NÃO acorda sozinha)

1. **`mem_sleep_default=deep`** no GRUB — SÓ quando o hardware lista
   `deep` em `/sys/power/mem_sleep` (o rig AM4/ASUS sem LPS0: o deep é
   o único sono; notebook s2idle fica fora). Idempotente, 1× — a dose
   (`elite-post-upgrade`) e o `elite-tune`/`elite-install-stage` ouvem
   o MESMO `/sys`.
2. **`elite-acpi-wakeup`** — desarma no boot os gatilhos espúrios do
   journal (`GPP0 GPP8 XHC0 XHC1 XHCI PTXH`) em `/proc/acpi/wakeup` (o
   arquivo é toggle: só escreve quem está `*enabled`; a 2ª passada é
   silêncio). O teclado é a mão do dono: a política do `craft-wake-guard`
   (E122) rearma o controlador dele — nunca tocada aqui.
3. **`craft-display recover`** — o DisplayPort que volta sem sinal é
   curado com o ciclo `--off → 1s → --on --mode <persistido>` POR SAÍDA
   VIVA (varredura dinâmica do wlr-randr; o modo vem do
   `~/.config/elite/displays.conf`, multi-saída). QUATRO gatilhos
   disparam (daemon em `PrepareForSleep(false)` e `Unlock`, pós-unlock
   do `craft-lock`, hook `elite-resume-display`, pós-sono do
   `craft-vigil`) com guard de 10s = **um dono por veredito**.

## 6 · A política de pacotes

- **`elite/packages.add` / `elite/packages.remove`** — o manifesto da
  ISO e o veto (o que nunca mais volta: waybar, swayidle, swaync,
  linux stock, okular…);
- **`elite-dose`** — a adoção de flatpaks e pacotes de rig
  (Bazaar/Warehouse/Gear Lever, mangohud/goverlay, rtkit, garantias
  `--needed` idempotentes);
- o build nasce do **`.ci/build.sh`** (fonte única dos PKGBUILDs, guard
  E41 do pkgrel) e a dose de migração é o **`elite-post-upgrade`**
  (idempotente por desenho — roda no `pacman -Syu` de todo rig).

## 7 · As portas de qualidade

| Porta | O que exige |
|---|---|
| **cargo · 2 portas** | `cargo test/clippy --workspace` no núcleo (sem gui) E com `--features gui` (prefix GTK4 do toolchain) — clippy `-D warnings` zero é lei |
| **porteira GO** | `bash tests/run-tests.sh` — cadeia de fases (estrutura → estática → cargo → ajuda → compositor → runtime/IPC → **hardware** → veredito); GO = zero falhas |
| **CI (GitHub)** | `tests.yml` (a suíte), `build.yml` (a ISO), `publish-packages.yml` (o canal diário) — nada entra sem porteira |
| **smoke vivo** | `tests/session_smoke` (o rig do dono) e `tests/iso-qemu` (a ISO bootada) |

## 8 · A MATRIZ DOS 6 PERFIS DE HARDWARE (o contrato vivo)

O tuning da casa é **condicionado ao hardware** — e a matriz é provada
BYTE A BYTE pelo simulador (`tests/hardware/run.sh`, fase 55 da
porteira: cada perfil roda a dose 2× num sandbox de root falso com
`/sys`/`/etc` falsos e stubs no PATH; as seams são as da casa —
`ELITE_ACPI_WAKEUP`, `ELITE_RANDR`).

| Perfil | Hardware | O que a casa SOMA |
|---|---|---|
| **Entrada 1** | Intel + iGPU, ext4, s2idle | GRUB **sem** `mem_sleep_default=deep` (o hardware não lista) · snapper/grub-btrfsd **colhidos** (ext4) · `elite-sensors.conf` de fábrica intacto (nenhum chip provou) · coolercontrol com `liquidctl_integration = false` |
| **Entrada 2** | AMD APU (k10temp), btrfs | snapper-cleanup + grub-btrfsd **ligados** · `elite-sensors.conf` = `k10temp` (o termômetro que PROVOU hwmon) · conf amdgpu (ppfeaturemask) |
| **Intermediário 1 — O RIG DO DONO** | Ryzen 5 5600 + ASUS (nct6775) + RX 7600, DP-1 1920x1080@119.88, btrfs, `[deep]` | GRUB **com** `mem_sleep_default=deep` (1×) · acpi-wakeup desarma os 6 gatilhos espúrios (idempotente) · sensores = `nct6775` · `craft-display recover` re-treina DP-1 com o modo **1920x1080@119.88** do displays.conf |
| **Intermediário 2** | Intel + RTX (nvidia), btrfs, deep | deep no GRUB · snapper ligado · o `config.toml` do dono ganha `liquidctl_integration = false` **dentro** da seção `[settings]` (nunca duplica) |
| **High-End 1** | Ryzen X3D (k10temp) + RX 7900, btrfs, multi-monitor DP-1 + HDMI-A-1 | recover cobre **as duas saídas** com seus modos persistidos · k10temp · deep |
| **High-End 2** | Intel + RTX 4080, btrfs, multi-monitor DP-1 + DP-2, deep | recover cobre **DP-1 e DP-2** com seus modos persistidos · nct6775 · deep |

Em todos: a 2ª dose é **byte-idêntica** (grub/sensors/coolercontrol) e o
`grub-mkconfig` NÃO roda de novo (o rebuild fantasma morreu, E130).

---

*Casa archcraft-elite · Lei suprema: `AGENTS.md` · Estilo:
`docs/skills/` · Mapa do repo: `docs/ESTRUTURA.md` · Prova da matriz:
`tests/hardware/` (fase 55 da porteira).*
