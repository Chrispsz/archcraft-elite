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
| **`craft-bar-rs`** | a top bar GTK4 + layer-shell (pílulas, mídia reativa pelo MPRIS do daemon, relógio/calendário SÓ no clique, rede com a Lei da Conexão Principal, a gaveta única do `craft-apps` e os atalhos rápidos no menu de sessão) |
| **`craft-dock-rs`** | a dock GTK4 + layer-shell (ícones, pins, o menu do botão direito em janela de camada) |
| **`craft-tools`** | as janelas nativas (`craft-update`, `craft-clean`, `craft-help`, os seletores `craft-pick`/`craft-net`) + o juiz `craft-audit` + o `MenuCamada` (a janela Overlay dos menus da casa) |
| **`craft-dump-rs`** | a telemetria v2 (o retrato do rig para o diagnóstico da casa) |

Toda a superfície gráfica é **uma família visual**: os ícones são NOMES
GTK (zero glifo Nerd), os menus são **JANELAS DE CAMADA Overlay**
(1.0-109 §2.1 — o `MenuCamada` da fundação: SEMPRE acima da gaveta top do
`craft-apps`, com o Esc no teclado exclusivo e o clique fora que NUNCA
engole o clique do ícone — o gesto de captura na superfície mãe fecha o
menu sem reclamar a sequência; o popover pendurado `popdown`+`unparent`
de era morreu com o último popover) e a armadura RT (`fn arma_rt`) veste
as duas janelas.

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
vestem a MESMA pele). `nwg-drawer`, `swayosd` e o `swaync` (de volta na
1.0-107 com dono único: vaga supervisionada da sessão, unit do
`systemd --user` mascarado, lançamento explícito `-c`/`-s` nos arquivos
do `$HOME`) recebem os mesmos valores nos formatos deles. Nenhum
componente parece bloco desconexo; o relógio é hora/calendário com o
tooltip **desligado** e o calendário abre EXCLUSIVAMENTE no clique (1.0-108:
o hover/enter de era morreu inteiro — nenhum `EventControllerMotion` mora no
relógio).

## 4 · O fluxo de boot da sessão

```
SDDM (tema elite, 100% pt_BR — Bem-vindo!/Entrar/Desligar…;
      o chão técnico do 99-elite.conf: InputMethod vazio,
      CursorTheme=Adwaita, ReuseSession=false — 1.0-108)
  └─ labwc (compositor; menu elite-sessao; W-f fullscreen)
      └─ autostart — O ARRANQUE LIMPO 1.0-108 (o berço do frame 0):
          ├─ dbus-update-activation-environment (labwc:wlroots)
          ├─ ALICERCES do frame 0 (não dependem do supervisor): swaybg,
          │  lxqt-policykit-agent (guard pgrep),
          │  udiskie --automount --notify --no-tray, craft-fix-keys,
          │  cliphist
          └─ elite-daemon session &   ← o ÚNICO ORQUESTRADOR (E146)
              ├─ topbar  (craft-bar-rs)
              ├─ dock    (craft-dock-rs)
              ├─ swaync (dono único pelo gate de bus — NUNCA no autostart)
              ├─ swayosd (com --style do $HOME — 1.0-108)
              └─ residentes + vagas supervisionadas (respawn 2s, try_wait
                 nativo — 1.0-107.2: EVENTO puro do kernel; 1.0-108: a
                 vaga ADOTADA é invisível ao teto do respawn — o spin de
                 95,6% de CPU em idle morreu com o limbo)
```

O greeter é o tema `/usr/share/sddm/themes/elite` (QML puro, fundo
`#111116`, acento `#a855f7`, zero binário no repo) fixado por
`/etc/sddm.conf.d/elite.conf` (`Current=elite`) com o chão técnico no
`/etc/sddm.conf.d/99-elite.conf` (1.0-108: `InputMethod=` vazio +
`CursorTheme=Adwaita` garantido pelo `adwaita-icon-theme` +
`ReuseSession=false` — um dono por chave).

### 4.1 · Os verbos da interface 1.0-108 (o mapa do clique)

- **a gaveta é ÚNICA**: o botão Aplicativos abre o `craft-apps` (a MESMA
  porta da tecla Windows — o fuzzel segue vivo como launcher de
  terminal); o calendário do relógio abre EXCLUSIVAMENTE no clique;
- **os atalhos rápidos do menu de sessão da barra**: Modo de jogo
  (`craft-game menu`) · Trava automática (`craft-idle menu`) ·
  Monitores/120 Hz (`wdisplays`) · Atualizar sistema (`craft-update`) ·
  Limpar sistema (`craft-clean`) · Snapshots/Rollback (`craft-rollback`)
  — ao lado de Bloquear/Suspender/Reiniciar/Desligar/Encerrar;
- **a Lei da Conexão Principal** (o direito do botão de rede): a
  ethernet conectada VENCE; ao desligar o par `(DEVICE, CONNECTION)` é
  guardado em `${XDG_RUNTIME_DIR}/elite/last-net.state` e a queda é pelo
  `nmcli device disconnect` (NUNCA `ip link set down`); ao religar o par
  guardado (ou a ethernet com cabo, senão a Wi-Fi) volta com `ip link
  set up` + `nmcli device set managed yes` + `nmcli connection up` /
  `nmcli device connect`. O esquerdo abre o seletor rápido
  (`craft-pick -T "Rede"`); o editor `nm-connection-editor` é VISÍVEL
  na grade (o override `/usr/local/share/applications` — paridade com o
  blueman);
- **o seletor `craft-pick` é juiz estrito**: as QUATRO formas do título
  (`-T T · -TT · --title T · --title=T`) e a flag inválida é **exit 2
  ANTES de qualquer GTK** (erro nomeado no stderr, zero processo vivo);
  a janela só cai por perda de foco DEPOIS do foco real + 300ms de
  carência (o primeiro frame do labwc é cortesia) — o ESC é imediato
  desde sempre.

## 5 · O sono S3 (a máquina que dorme e NÃO acorda sozinha)

1. **`mem_sleep_default=deep`** no GRUB — SÓ quando o hardware lista
   `deep` em `/sys/power/mem_sleep` (o rig AM4/ASUS sem LPS0: o deep é
   o único sono; notebook s2idle fica fora). Idempotente, 1× — a dose
   (`elite-post-upgrade`) e o `elite-tune`/`elite-install-stage` ouvem
   o MESMO `/sys`.
2. **`elite-acpi-wakeup`** (1.0-107 → 1.0-107.2) — desarma no boot a FAMÍLIA
   INTEIRA de gatilhos espúrios por PADRÃO (`XHC*`/`PTXH`/`GPP*`/
   `GP[0-9]*`/`X1[0-9]*`/`X1_[0-9]*` — controladores USB e pontes PCIe;
   o dongle 2.4G que acordava a máquina num pigarro não é a mão de
   ninguém) em `/proc/acpi/wakeup` (o arquivo é toggle: só escreve quem
   está `*enabled`; a 2ª passada é silêncio). O allowlist UNIVERSAL da
   mão do dono (1.0-107.2 — desktop E notebook em qualquer placa
   AMD/Intel) é explícito e ARMADO no boot: `PWRB`/`PBTN` (as duas
   grafias do botão do power), `SLPB` (o botão de sleep físico), `PS2K`
   (o teclado PS/2) e `LID` (a tampa) — o firmware que entrega o botão
   dormindo de fábrica não rouba o despertar do dono; o
   `craft-wake-guard` veste a MESMA lei (TODO o USB dorme, o mesmo
   cinto de 5 nomes rearmado no boot e re-julgado no limiar de cada
   sono; a exceção de teclado de era morreu com o dongle fingidor).
3. **`craft-display recover`** — o DisplayPort que volta sem sinal é
   curado com o ciclo `--off → 1s → --on --mode <persistido>` POR SAÍDA
   VIVA (varredura dinâmica do wlr-randr; o modo vem do
   `~/.config/elite/displays.conf`, multi-saída). QUATRO gatilhos
   disparam (daemon em `PrepareForSleep(false)` e `Unlock`, pós-unlock
   do `craft-lock`, hook `elite-resume-display`, pós-sono do
   `craft-vigil`) com guard de 10s = **um dono por veredito**.
   1.0-107 — A SEQUÊNCIA É LEI: no `PrepareForSleep(true)` o hyprlock
   nasce e o daemon espera a SUPERFÍCIE mapeada antes do `wlopm --off`;
   no retorno, o `wlopm --on` espera o backoff de 800ms do link DP/HDMI
   ANTES do recover (o hyprlock morto no sono renasce `--if-needed` — a
   tela nunca acorda nua). 1.0-108 — O SUSPEND MANUAL VESTE A MESMA LEI:
   o `craft-suspend` (novo) trava a tela e SÓ chama o `systemctl
   suspend` com o lock PINTADO (hyprlock vivo + assento de 400ms, teto
   3s); o lock nasce INSTANTÂNEO (`hyprlock --immediate` + `no_fade_in` +
   o wallpaper estático SEM passada lenta antes do map — a piscada preta
   morre) e o `craft-logout` (novo) encerra a família em ORDEM (daemon →
   superfícies → agentes, fóssil do /run varrido) ANTES do `labwc
   --exit`.

## 6 · A política de pacotes

- **`elite/packages.add` / `elite/packages.remove`** — o manifesto da
  ISO e o veto (o que nunca mais volta: waybar, swayidle, linux stock,
  okular…; o swaync VOLTOU na 1.0-107 com dono único);
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
| **porteira GO** | `bash tests/run-tests.sh` — cadeia de fases (estrutura → estática → cargo → ajuda → compositor → runtime/IPC → **hardware** → **smoke dos binários compilados (fase 57, 1.0-108)** → veredito); GO = zero falhas |
| **CI (GitHub)** | `tests.yml` (a suíte), `build.yml` (a ISO estável de tag), `publish-packages.yml` (o canal testing), `promover-testing.yml` (a promoção a estável) — nada entra sem porteira |
| **smoke vivo** | `tests/session_smoke` (o rig do dono) e `tests/iso-qemu` (a ISO bootada) |

## 7.1 · Os canais de publicação (testing × stable — 1.0-107.1)

- **testing (prerelease `testing`)**: todo push de casa publica a build
  de validação (makepkg + smoke headless + repo-add) na prerelease
  `testing` — NUNCA na estável; dieta automática de assets (só a build
  mais recente de cada pacote fica no ar);
- **stable (release de tag — `releases/latest`)**: o endereço que o
  `pacman.conf` de todo rig lê (`elite-customize.sh` E32). A build
  validada só chega ao rig pelo **fluxo explícito de promoção**
  (`promover-testing.yml`, gatilho humano) DEPOIS da validação no
  hardware real; a ISO de tag também regrava o db estável no release;
- **observabilidade**: cada workflow escreve o resumo técnico no
  `$GITHUB_STEP_SUMMARY` (canal, versão, duração por etapa, tamanhos,
  SHA256);
- **compressão calibrada**: ISO em `zstd -15 -T0 -b 512K` (a era -19
  pagava CPU máxima por ~2% sobre dados já comprimidos).

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
