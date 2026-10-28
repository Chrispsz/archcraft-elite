# Archcraft Elite

Distribuição live/installer baseada no [Archcraft](https://github.com/archcraft-os/archcraft)
com a camada de otimização do [CachyOS](https://cachyos.org) aplicada de
fábrica: kernel `linux-cachyos-bore` (x86-64-v3), Vulkan de série,
filesystem btrfs com rollback e sessão única labwc (Wayland).

É um *overlay delta*: cada build clona o profile oficial do Archcraft e aplica
a camada `elite/` por cima — sem fork, sempre sincronizada com o upstream.

![Build](https://github.com/Chrispsz/archcraft-elite/actions/workflows/build.yml/badge.svg)
[![Release](https://img.shields.io/github/v/release/Chrispsz/archcraft-elite?label=Release)](../../releases)

## Requisitos

| Requisito | Mínimo |
|---|---|
| CPU | x86-64-v3 (verificação: `/lib64/ld-linux-x86-64.so.2 --help \| grep supported`) |
| RAM | 4 GB (8 GB recomendado; o live pode rodar com *copy to RAM*) |
| Armazenamento | 20 GB para instalação |
| Firmware | Boot UEFI ou BIOS legado |

Alvos de referência testados: **Elite A** (Ryzen 7 5700X + RTX 5060) e
**Elite B** (Ryzen 5 5600 + RX 7600). Qualquer máquina x86-64-v3 é suportada.

## Download e verificação de integridade

Baixe em [Releases](../../releases): `archcraft-elite-<data>-x86_64.iso`
(+ `sha256sums.txt`). Se a ISO vier dividida em partes (limite de 2 GiB por
arquivo do GitHub), as instruções de reconstrução acompanham o release
(`JUNTAR-ISO.md`).

```bash
sha256sum -c sha256sums.txt
```

A integridade não é só recomendação: o CI **re-baixa os assets publicados e
confere os hashes antes de dar a run por encerrada** (GATE 2). Release
truncada não publica.

## Instalação

1. Grave a ISO em pendrive (Ventoy, Rufus, `dd`).
2. Boot pela entrada desejada (abaixo).
3. Abra o **Archcraft Installer** (Calamares) na sessão live — btrfs é o
   filesystem default.
4. Ao terminar, remova a mídia e reinicie. O primeiro boot executa a
   configuração automática por hardware (`elite-firstboot.service`) e pede
   um reboot.
5. Certificação do sistema: `elite-status`.

### Menu de boot

| Entrada | Uso |
|---|---|
| **Archcraft Elite (AMD · Copy to RAM)** | Default; `amdgpu.ppfeaturemask=0xffffffff` (destrava undervolt/OC no LACT; inerte em NVIDIA) |
| **Archcraft Elite (NVIDIA · Copy to RAM)** | Driver `nvidia-open` **pré-compilado contra o kernel BORE no build** — early-KMS desde o live, sem rede |
| **Archcraft Elite (Nomodeset · rescue)** | Sem copy-to-RAM, para máquina com pouca memória |

No rig AMD, a instalação remove o stack NVIDIA inteiro — cada disco nasce com
o driver do próprio hardware.

## O que a ISO contém

| Camada | Componente |
|---|---|
| Kernel | `linux-cachyos-bore` x86-64-v3 (único; rollback via snapshot btrfs no GRUB) |
| Sessão | labwc (Wayland, única) + waybar + swaync + fuzzel + foot + nwg-drawer |
| Dock | `craft-dock-gui` — GTK3 + wlr-layer-shell, ícones reais do tema, SEMPRE visível (layer BOTTOM + zona exclusiva — maximizadas respeitam a faixa); esconder em qualquer momento é **W-S-d**, inclusive em tela cheia |
| Top bar | menu bar estilo macOS — app focado, relógio, volume/rede/sessão + botão de apps em 2º plano (`craft-bgapps`, some quando não há nada a encerrar); conector Wi-Fi em TEXTO no menu de rede (`craft-connect`: redes do entorno + senha oculta — sem tray, sem applet) |
| Diagnóstico | `craft-dump` — o "btop completão": hardware, pacotes, serviços, caça ao despertar, logs da Elite e caches num arquivo (com `--upload` p/ URL curta) |
| Scheduler | `ananicy-cpp` com regras CachyOS — o scheduler é o BORE do kernel (scx userspace saiu na v2.2) |
| Tuning | `cachyos-settings`, zram zstd, sysctl/udev próprios, BBR + fq |
| Gaming | gamemode, gamescope, mangohud, Vulkan RADV/Intel (lib32 sobe on-demand no firstboot), LACT, btop |
| GPU | NVIDIA open pré-compilado no build (rig A) / RADV (rig B) |
| Arquivos | Thunar + tumbler (GUI), craft-connect para rede/bluetooth |
| Navegador | Brave Origin (release oficial, versão e sha256 fixados no build) |
| Rollback | btrfs + timeshift + grub-btrfs (snapshot no menu do GRUB) |

Debloat do upstream no teto do que não quebra o sistema (impressão,
cloud-init, sessões Openbox/BSPWM/X11, terminais extras, fontes CJK…,
e o teto extra da v2.3.0: temas de ícones/GTK/cursors, wallpapers,
xorg, GStreamer, DDX). Lista completa, pacote a
pacote, com justificativa e comando de restauração: [docs/CHANGES.md](docs/CHANGES.md).

## Teclas principais

| Combinação | Ação |
|---|---|
| `Super` | Launchpad (grade de aplicativos) |
| `W-Enter` | Terminal (foot) |
| `W-f` | Gerenciador de arquivos |
| `W-n` | Editor de conexões de rede (edição avançada) |
| `W-Shift-b` | Bluetooth (blueman-manager) |
| `W-a` | Mixer de áudio |
| `W-p` / `W-Shift-p` | Screenshot (região / tela inteira) |
| `W-l` | Tela de bloqueio (hyprlock) |
| `W-Shift-d` | Dock: mostrar/esconder (a dock é SEMPRE visível — esconder é escolha do usuário, v2.3.4) |
| `Alt-Tab` | Alternar janelas |

Menu bar: lançador + app focado à esquerda, relógio no centro exato,
volume/rede/sessão à direita.

## Gerenciamento e rollback

- `elite-status` — certificação do sistema (drivers, serviços, tuning).
- `elite-tune` — tuning interativo; `--dry-run` simula sem escrever; `--apps`
  instala aplicativos opcionais (Steam, Lutris, OBS, escritório).
- Toda alteração de arquivo gera backup `.bak.<timestamp>` junto ao original.
- Rollback do sistema: Timeshift + entrada de snapshot no GRUB.
- Rollback dos repositórios: remover as seções `[cachyos*]` do
  `/etc/pacman.conf` e `sudo pacman -Qqn | pacman -S -`.
- Chave GPG CachyOS importada; o pacman original do Arch é preservado
  (o fork do CachyOS não é instalado).

## Build

### CI (GitHub Actions)

O pipeline completo roda em **tag `v*`** (ou *Run workflow*):

```
lint → build → verify → verify-install → release (GATE 1 + GATE 2)
```

- **lint** — shellcheck bloqueante em todos os scripts shell.
- **build** — container Arch privilegiado; o log é varrido pela forense
  (`scripts/log-forensics.sh`) e erro silencioso derruba a run.
- **verify** — boota a ISO no QEMU com a cmdline REAL da entrada default e
  exige: boot completo, zero shell de emergência, zero binário não-executável,
  **zero unidade systemd em failed** e **sessão gráfica viva com as 2 barras**
  (probe obrigatório quando o runner tem KVM).
- **verify-install** — reproduz a cadeia Calamares inteira (unpackfs → btrfs,
  hash do vmlinuz, mkinitcpio, GRUB) e boota o disco instalado no QEMU.
- **release** — GATE 1: o artifact bate com o `sha256sums.txt` selado dentro
  dele; GATE 2: re-download dos assets publicados e nova conferência.

Push de branch **não** constrói ISO — roda a suíte de contratos
(`tests.yml`, ~1.4 min, 5 fases). Isso é intencional: build de ISO é evento
de release, não de commit.

O cache de pacotes (`.ci-cache`) persiste entre runs — a lista de pacotes em
`elite/packages.*` é a chave; os índices de repositório (`.db`) nunca são
cacheados (lição de mirror skew dos runs #17-#19).

### Local (Arch Linux, requer archiso e privilégios)

```bash
bash scripts/apply-overlay.sh
cd elite-build/profile && sudo ./mkarchcraftiso -v -w /tmp/iso-work -o out .
```

## Estrutura do repositório

```
.github/workflows/build.yml          CI: lint → build → verify → verify-install → release
.github/workflows/tests.yml          Suíte de contratos (5 fases; roda em todo push que toca código — e a suíte é GATE do release via build.yml desde v2.10.5)
.github/workflows/verify-install.yml Gate de instalação (QEMU, workflow_call)
.github/workflows/agents.yml         Auditoria por IA sob demanda (Token Harbor)
.github/workflows/publish-artifact.yml  Publicação manual de artifact como release
.ci/build.sh                         Lógica de build dentro do container Arch
scripts/apply-overlay.sh             O delta: clona o upstream e aplica a camada Elite
scripts/log-forensics.sh             Varredura fatal do log de build
elite/                               A camada Elite (packages, airootfs, fragments)
tests/                               5 fases de contratos (estáticos → release)
agents/                              Relay de IA (deepseek = Builder, mimo = Auditor)
docs/                                Documentação técnica (ver abaixo)
```

## Documentação

| Documento | Conteúdo |
|---|---|
| [docs/CHANGES.md](docs/CHANGES.md) | Delta completo vs. upstream, versão a versão, com justificativas |
| [docs/SCRIPTS.md](docs/SCRIPTS.md) | Uso, dependências e reversão de cada script |
| [docs/BUILDING.md](docs/BUILDING.md) | Pipeline de build em detalhe: estágios, cache, tempos, diagnóstico |
| [docs/VERIFICATION.md](docs/VERIFICATION.md) | O que cada gate PROVA — e o que não prova (contrato de honestidade) |
| [docs/AGENTS.md](docs/AGENTS.md) | Auditoria por IA: relay, cota e protocolo de consenso entre 3 modelos |

## Créditos e licença

- [Archcraft](https://github.com/archcraft-os/archcraft) — Aditya Shakya
  (adi1090x): profile, rice e `mkarchcraftiso`. Este projeto é um overlay; o
  sistema base é dele.
- [CachyOS](https://cachyos.org) — kernel BORE, repositórios v3, settings e
  boosters.
- Arch Linux, Valve (gamemode/gamescope/Proton).

MIT para os arquivos deste repositório ([LICENSE](LICENSE)). O profile do
Archcraft clonado em tempo de build e os pacotes instalados mantêm as licenças
dos projetos de origem.
