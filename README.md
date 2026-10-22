# Archcraft Elite Edition

ISO live/installer baseada no Archcraft (Openbox/BSPWM) com a camada de otimização CachyOS + Valve aplicada de fábrica: kernel BORE x86-64-v3, sched-ext, Vulkan de série, gerenciamento de VRAM em primeiro plano e rollback nativo. Construída para dois alvos de hardware.

![Build](https://github.com/Chrispsz/archcraft-elite/actions/workflows/build.yml/badge.svg)
[![Release](https://img.shields.io/github/v/release/Chrispsz/archcraft-elite?label=Release)](../../releases)

## Alvos de hardware

| Alvo | CPU | GPU | RAM |
|---|---|---|---|
| **Elite A** | Ryzen 7 5700X (Zen 3) | NVIDIA RTX 5060 8 GB (Blackwell) | 16 GB |
| **Elite B** | Ryzen 5 5600 (Zen 3) | AMD RX 7600 (RDNA 3) | 32 GB |

Requisito: CPU x86-64-v3 ou superior. Ambos os alvos (Zen 3) atendem com folga.
Verificação em qualquer máquina: `/lib64/ld-linux-x86-64.so.2 --help | grep supported`

## Como a ISO se comporta em cada alvo

### Elite A — Ryzen 7 5700X + RTX 5060 (NVIDIA)

| Etapa | O que acontece |
|---|---|
| Live (pendrive) | Usar a entrada **Nvidia** do menu de boot (v1.1): mesmo kernel BORE, com o `nvidia-open-dkms` **pré-compilado contra o BORE no build** (E11) — driver proprietário + early-KMS desde o live, sem compilar nada e sem depender de rede; copy-to-RAM. A entrada default (AMD) também boota no rig A (sem driver proprietário — usar só como fallback). Se o vídeo travar no live, usar a entrada **Nomodeset** (rescue). |
| Instalação | Calamares padrão, btrfs como filesystem default. O E10 v1.1 detecta o vendor pela GPU e especializa o ALVO: rig NVIDIA nasce com `MODULES=(nvidia*)` + modeset/fbdev — zero contaminação do stack AMD. |
| Primeiro boot | `elite-firstboot.service` detecta NVIDIA e o dkms **já pré-compilado da ISO** (v4.6 NV_PREBUILT): **não instala nada** — offline total, marker na primeira passada (instalar via rede vira fallback só p/ sistema não-ISO). Escreve `nvidia-drm modeset=1 fbdev=1`, `NVreg_PreserveVideoMemoryAllocations=1`, habilita os serviços de tuning e insere os parâmetros GRUB (`amd_pstate=active nowatchdog zswap.enabled=0 transparent_hugepage=always`). Pede reboot. |
| Segundo boot | RTX 5060 com driver open/GSP no kernel BORE (único). Shader cache de 1 GB persistente configurado. Vulkan via NVIDIA, Steam/Feral GameMode e MangoHud prontos. |
| Rotina de jogo | `PROTON_ENABLE_NVAPI=1 gamemoderun mangohud %command%`. VRAM de 8 GB sob vigilância: `dmemcg-booster` limita aplicativos em segundo plano e o `fg-booster` promove o jogo em foco (peso de CPU/IO 900). Se apertar: `gamescope` com upscaling NIS/FSR subnativo. |
| BIOS recomendada | DOCP/XMP 3200 MHz, Above 4G Decoding + ReBAR (ligar os dois), PBO + Curve Optimizer −15 a −20. |

### Elite B — Ryzen 5 5600 + RX 7600 (AMD)

| Etapa | O que acontece |
|---|---|
| Live (pendrive) | Entrada default (kernel BORE v3), sessão labwc com aceleração desde o boot: a ISO traz `vulkan-radeon` (RADV) e mesa assados — 3D completo no live, sem instalar driver nenhum. |
| Instalação | Idêntica: Calamares, btrfs default. |
| Primeiro boot | Detecta AMD: nada a instalar (RADV já presente). O serviço grava `amdgpu ppfeaturemask=0xffffffff` (destrava undervolt/overclock para o LACT), habilita o stack de tuning e insere os mesmos parâmetros GRUB. Reboot. |
| Segundo boot | RX 7600 com RADV Vulkan. LACT disponível para undervolt/OC (ppfeaturemask destravado). |
| Rotina de jogo | `gamemoderun mangohud %command%`. O `dmemcg-booster` **enforça de verdade** os tetos de VRAM de aplicativos em segundo plano em AMD (era o comportamento que faltava no plasma-foreground-booster) — é aqui que a camada rende mais. |
| BIOS recomendada | DOCP/XMP 3600 MHz ( Ryzen 5 5600 escala bem até ~3600–3800 com FCLK 1:1), Above 4G + ReBAR, PBO + Curve Optimizer. |

### Comum aos dois alvos

- **Sessão única = labwc (Wayland)** com o rice Catppuccin Mocha do projeto: menu bar + **dock flutuante AUTO-OCULTANTE** estilo COSMIC (reveal no hover), Launchpad (nwg-drawer), SwayNC, Fuzzel, foot, keybinds `rc.xml` derivados do criador do Archcraft e helpers `craft-*` de fábrica (v1.0.3+). **Fixar apps na dock: `craft-pin add steam '' Steam steam green`** (v1.1 — gerencia a seção PINS do config com vírgulas/backup/reload por conta própria; `craft-pin rm/list/restore`). Openbox/BSPWM e seus satélites X11 foram **removidos da ISO** (diretriz: zero duplicação — um WM, um terminal, uma barra, um launcher). Quem quiser o Openbox de volta: `sudo pacman -S archcraft-openbox` (os temas OB ficam na ISO — o labwc lê os mesmos temas).
- Kernel `linux-cachyos-bore` v3 (BORE + patchset CachyOS, build x86-64-v3) **único** (v1.1 — o kernel stock saiu da ISO); rollback de kernel = snapshot btrfs/Timeshift no menu do GRUB.
- `scx-elite.service` (sched-ext bpfland) — trocar para `scx_lavd` com `sudo systemctl edit scx-elite`.
- `ananicy-cpp` + regras CachyOS para prioridade dinâmica.
- zram zstd (metade da RAM até o teto de 8 GB), `vm.swappiness=180`, `max_map_count` Steam, schedulers de I/O por tipo de disco.
- Rollback real: btrfs + Timeshift + grub-btrfs (snapshot no menu do GRUB).
- Aplicativos opcionais por demanda: `sudo elite-tune --apps` (Steam, Lutris, OBS, escritório — nada pré-instalado além do essencial).

## O que vem na ISO

| Camada | Componente | Origem |
|---|---|---|
| **Sessão (v1.0.3+)** | **labwc** (Wayland, única) + Waybar + SwayNC + Fuzzel + foot + swaybg/swaylock + grim/slurp + helpers `craft-*` + fastfetch | Arch [extra] + este repo |
| **Desktop v1.3 · AMOLED rice** | Escada de superfícies até o **preto REAL `#000000`** ("Mocha com o backlight desligado") nos 4 CSS + themerc + fuzzel + foot NOVO (`foot.ini`): acentos Catppuccin intactos, GTK apps Mocha por trás do chrome preto (macOS style). Dock com **logo do Arch (U+F303) em mauve** + Brave em peach (cores semânticas). Rodapé do Launchpad morto por CSS (sem fork). **Wallpaper 4K real da internet** — fractal mauve sobre preto, 37% de pixels desligados; fallback do swaybg `#000000` | este repo |
| Kernel (v1.1) | `linux-cachyos-bore` **único** — o kernel stock do Arch saiu da ISO | CachyOS v3 |
| Repositórios | `[cachyos-v3] [cachyos-core-v3] [cachyos-extra-v3]` antes de `[core]`, baseline `[cachyos]` para os pacotes exclusivos | CachyOS |
| Scheduler | `scx-scheds` + `scx-tools` + unidade própria | sched-ext / Arch |
| Prioridade dinâmica | `ananicy-cpp` + `cachyos-ananicy-rules` | CachyOS |
| Tuning de base | `cachyos-settings` + sysctl/zram/udev Elite | CachyOS + este repo |
| VRAM/foreground | `dmemcg-booster` (tetos p/ segundo plano) + `fg-booster` (peso p/ app em foco, X11/XWayland) | CachyOS + este repo |
| Gaming | `gamemode` `gamescope` `mangohud` (lib32 incluídos) `lact` `nvtop` `btop` | Arch / CachyOS |
| Vulkan | `vulkan-radeon` `vulkan-intel` + pares lib32 (a ISO upstream do Archcraft não trazia) | Arch |
| NVIDIA (v1.1) | **`nvidia-open-dkms` pré-compilado contra o BORE no build** (E11): early-KMS no live E no sistema instalado, nos DOIS rigs, sem rede no primeiro boot | Arch [extra] + este repo |
| Rede (v1.1) | **BBR + fq** (`sysctl.d` + `modules-load.d`) — throughput real em links de alta latência/perda | este repo |
| Rollback | btrfs default no installer, `timeshift`, `grub-btrfs` | Arch |

## O que foi removido da ISO (debloat)

Cerca de 170 pacotes e ~1,5 GB de payload: stack de impressão, cloud-init, guest tools de VM, VPN/modem enterprise, ferramentas de resgate pesadas, a edição Sway do Archcraft, **as sessões Openbox/BSPWM + satélites X11** (polybar/tint2/rofi/picom/plank…, v1.0.3), **3 dos 4 terminais** (fica o foot), **a música de exemplo/console** (mpd/ncmpcpp/mplayer — a barra mostra a SUA música via playerctl), fontes CJK e firmwares de servidor/NIC enterprise. A seleção completa, justificativa pacote a pacote e o comando de restauração de cada item está em [docs/CHANGES.md](docs/CHANGES.md). Tudo volta com um `pacman -S <pacote>`.

Aparência: a sessão labwc nasce com o rice Catppuccin Mocha do projeto (tema de janela via `themerc-override` próprio, Waybar/SwayNC/Fuzzel no mesmo tema). O resto do rice do Archcraft (temas GTK, ícones, cursores) permanece na ISO intacto.

### App-stack moderna (v1.1 — diretriz do dono)

A camada de aplicativos foi inteira trocada por equivalentes modernos e
Wayland-native (Rust/GTK4), herdando o tema Catppuccin:

| Categoria | Saiu (legado GTK3/X11) | Entrou (v1.1) |
|---|---|---|
| Navegador | firefox | **Brave** (`brave-bin`, flags Wayland/Vulkan no skel) |
| Arquivos | thunar + file-roller | **yazi** (TUI Rust, preview Sixel no foot) + `7zip` |
| Editor | mousepad + vim | **helix** (tema `catppuccin_mocha`) |
| PDF | zathura | **papers** (GTK4/libadwaita) |
| Áudio (GUI) | pavucontrol | **pwvucontrol** (GTK4/Rust) |
| Bluetooth | blueman | **bluetui** (TUI Rust, W-S-b) |
| Rede | nm-applet | **impala** (TUI Rust, W-n) |
| Notificações | — | swaync (já era v1.0.3) |
| GPU | — | LACT (já era v1.0.4) |

`brave-bin` e `pwvucontrol` são construídos no build (estágio AUR → repo
`[elite-local]`) e resolvidos **offline** pelo pacstrap selado, como
qualquer pacote oficial.

### Menu de boot (v1.1)

Três entradas, kernel único BORE, as duas principais carregando o live
inteiro na RAM (leitura sequencial — USB lento deixa de doer):

1. **Archcraft Elite (AMD · Copy to RAM)** — default; `amdgpu.ppfeaturemask=0xffffffff` (destrava undervolt/OC no LACT; inerte em GPU NVIDIA)
2. **Archcraft Elite (NVIDIA · Copy to RAM)** — early-KMS pelo dkms pré-compilado (`nvidia_drm.modeset=1 fbdev=1`)
3. **Archcraft Elite (Nomodeset · rescue)** — sem copy-to-RAM, para máquina com pouca memória

No rig AMD a instalação remove o stack NVIDIA inteiro (E10 + firstboot) —
cada disco nasce com o driver do SEU hardware, sem pacote estranho.

## Download e verificação

Aba [Releases](../../releases): `archcraft-elite-<data>-x86_64.iso` + `sha256sums.txt`.

```bash
sha256sum -c sha256sums.txt
```

Se a ISO vier dividida em partes (limite de 2 GB por arquivo do GitHub), as instruções de reconstrução acompanham o release (`JUNTAR-ISO.md`).

## Instalação

1. Boot pelo pendrive (Entrada default, ou **Nvidia** no Elite A).
2. Ícone do Calamares na sessão live — filesystem btrfs já vem como default.
3. Ao terminar, remover a mídia e reiniciar; o primeiro boot executa a configuração automática (ver tabelas por alvo acima) e pede um reboot.
4. Certificação do sistema: `elite-status`.

## Rollback e segurança

- Toda alteração de arquivo feita pelos scripts Elite gera backup `.bak.<timestamp>` junto ao original.
- `elite-tune` aceita `--dry-run` (simulação completa, nada é escrito).
- Kernel Arch sempre instalado como entrada de fallback no GRUB.
- Rollback do sistema: Timeshift + entrada de snapshot no GRUB (grub-btrfs).
- Rollback dos repositórios: remover as seções `[cachyos*]` do `/etc/pacman.conf` e `sudo pacman -Qqn | pacman -S -`.
- pacman original preservado (o fork do CachyOS não é instalado); chave GPG CachyOS `F3B607488DB35A47` importada no sistema instalado.

## Build

O build roda no GitHub Actions em cadeia de gates: `lint` (shellcheck bloqueante) → `build` (container Arch Linux privilegiado, `mkarchcraftiso` do upstream) → `verify` (boota a ISO em QEMU com a cmdline real e exige boot completo sem shell de emergência) → `verify-install` (reproduz a cadeia Calamares inteira — unpackfs→btrfs, initcpio, GRUB — e boota o disco instalado no QEMU; é o gate que caça o bug do rig B). A ISO só vira release com os dois boots verdes. Push em `main` ou *Run workflow* dispara o build (~1h com os gates); tags `v*` publicam release com ISO + checksums automaticamente.

Local (em Arch Linux, requer archiso e privilégios):

```bash
bash scripts/apply-overlay.sh
cd elite-build/profile && sudo ./mkarchcraftiso -v -w /tmp/iso-work -o out .
```

Este repositório é um *overlay delta*: a cada build ele clona o profile oficial do Archcraft e aplica a camada Elite por cima — sem fork, sempre sincronizado com o upstream.

## Estrutura

```
.github/workflows/build.yml     CI: lint + build + release
.ci/build.sh                    Lógica de build dentro do container Arch
scripts/apply-overlay.sh        O delta: clona o upstream e aplica a camada Elite
elite/packages.add              Pacotes adicionais
elite/packages.remove           Debloat (comentados, restauráveis)
elite/pacman-repos.build.add    Repositórios CachyOS para o build
elite/fragments/elite-customize.sh   E0–E10: keyring, pacman.conf, cirurgia no Calamares, fix btrfs do boot instalado
elite/airootfs/                 sysctl, zram, udev, units, preset mkinitcpio, scripts
elite/airootfs/etc/skel/.config/{labwc,waybar,swaync,nwg-drawer,fuzzel,foot}
                                v1.3 AMOLED rice: 4 CSS + themerc + foot.ini
                                NOVO + wallpaper.jpg 4K + autostart
docs/CHANGES.md                 Delta completo vs. upstream, com justificativas
docs/SCRIPTS.md                 Documentação por script (uso / reversão / dependências)
```

## Créditos

- [Archcraft](https://github.com/archcraft-os/archcraft) — Aditya Shakya (adi1090x): profile, rice, pacotes e mkarchcraftiso. Este projeto é um overlay; o sistema base é dele.
- [CachyOS](https://cachyos.org) — kernel BORE, repositórios v3, settings e boosters.
- Arch Linux, [sched-ext](https://github.com/sched-ext/scx), Valve (gamemode/gamescope/Proton), SteamOS e Fedora (referências de sysctl/zram).

## Licença

MIT para os arquivos deste repositório ([LICENSE](LICENSE)). O profile do Archcraft clonado em tempo de build e os pacotes instalados mantêm as licenças dos projetos de origem.
