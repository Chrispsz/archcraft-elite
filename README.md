# Archcraft Elite Edition 🏎️

**Archcraft (Openbox/BSPWM) com a camada completa de otimização CachyOS + Valve aplicada de fábrica** — kernel BORE x86-64-v3, sched-ext, ananicy-cpp, boosters de foreground/VRAM, zram, Vulkan de série, debloat cirúrgico e rollback real (btrfs + timeshift + grub-btrfs). Uma ISO tão enxuta e afiada quanto qualquer distro gamer por aí — sem abrir mão do rice lindo do Archcraft.

![Build](https://github.com/Chrispsz/archcraft-elite/actions/workflows/build.yml/badge.svg)
[![Release](https://img.shields.io/github/v/release/Chrispsz/archcraft-elite?label=Release)](../../releases)

> **Não é um fork.** É um *overlay delta*: a cada build, o GitHub Actions clona o profile oficial do Archcraft e aplica a camada Elite por cima — dotfiles, temas, Calamares e driver NVIDIA live sempre sincronizados com o upstream, zero manutenção de fork.

---

## ⚠️ Requisito de hardware

**CPU x86-64-v3 ou superior** (Haswell 2014+ / Zen+ / Excavator+). O kernel e os pacotes do repo `[cachyos-v3]` usam instruções AVX2/AVX-512 — em CPU mais antiga dá `illegal instruction`.
Verifique: `/lib64/ld-linux-x86-64.so.2 --help | grep -o 'x86-64-v[0-9]'`

| Máquina alvo | CPU | Veredicto |
|---|---|---|
| Elite A | Ryzen 7 5700X (Zen 3) | ✅ v3 |
| Elite B | (veterano — o próprio installer detecta) | ✅ se ≥ Zen+/Haswell |

## 📥 Download

Aba **[Releases](../../releases)** → `archcraft-elite-<data>-x86_64.iso` + `sha256sums.txt`.
Se a ISO vier dividida em partes (limite de 2 GiB por arquivo do GitHub): baixe todas e `cat archcraft-elite-*.part-* > arquivo.iso` (instruções dentro do `JUNTAR-ISO.md` que acompanha).

Verifique sempre: `sha256sum -c sha256sums.txt`

## 🔧 O que vem assado na ISO

| Camada | O quê | Fonte |
|---|---|---|
| Kernel | `linux-cachyos-bore` (BORE + patchset CachyOS, build v3) · `linux` do Arch como fallback no GRUB | CachyOS v3 |
| Repos v3 | `[cachyos]` + `[cachyos-v3\|core-v3\|extra-v3]` **antes** de `[core]` | wiki.cachyos.org |
| Scheduler plugável | `scx-scheds` + `scx-tools` + unidade própria `scx-elite.service` (bpfland; troque p/ `scx_lavd` com `systemctl edit`) | sched-ext |
| Prioridade dinâmica | `ananicy-cpp` + `cachyos-ananicy-rules` | CachyOS |
| Tuning de sistema | `cachyos-settings` (sysctl/udev/modprobe/limits) + `99-elite.conf` por cima | CachyOS + Elite |
| **VRAM mgmt** | `dmemcg-booster` (tetos de VRAM p/ apps em background — morde de verdade em AMD) | CachyOS |
| Foreground booster | `fg-booster` (nossa versão X11 do plasma-foreground-booster; cgroups v2, devolve ao leaf de origem) | este repo |
| Memória | zram zstd (½ RAM, teto 8 GB) + swappiness 180 + `max_map_count` Steam | SteamOS/Fedora style |
| Gaming | gamemode + gamescope + mangohud (lib32 incluso), LACT, nvtop, btop | multi |
| **Vulkan de série** | `vulkan-radeon` + `vulkan-intel` + pares lib32 (o ISO upstream **não** trazia!) | Arch |
| Rollback | GRUB + **btrfs default no installer** + timeshift + grub-btrfs | Arch |
| NVIDIA | live: entrada de boot dedicada (kernel stock + nvidia-open do próprio Archcraft) · instalado: `elite-firstboot` troca p/ `nvidia-open-dkms` e compila pros 2 kernels | este repo |
| Ricing | rice Archcraft intacto + 2 wallpapers Elite (`elite-wallpaper 1\|2`) + picom com fullscreen unredirect | upstream + Elite |

## 🚀 Fluxo do usuário (a "mágica")

1. **Live**: boota como Archcraft (entrada default = kernel BORE). GPU NVIDIA e quer aceleração no live? Use a entrada **"Nvidia"** (kernel stock + driver da ISO). AMD/Intel funcionam em qualquer entrada.
2. **Instala**: Calamares padrão — **btrfs já é o filesystem default** (escolha outro se quiser). Internet necessária.
3. **Primeiro boot**: `elite-firstboot.service` roda UMA vez → detecta a GPU (Turing+ → `nvidia-open-dkms`; AMD/Intel → nada a fazer), habilita scx/ananicy/fg-booster/dmemcg/grub-btrfsd/lact, insere os tokens GRUB (`amd_pstate=active nowatchdog zswap.enabled=0 transparent_hugepage=always`), se auto-desativa e pede **reboot**.
4. **Segundo boot**: sistema Elite completo. Certifique com `sudo elite-tune --status` (ou `elite-status`).
5. **Apps à la carte**: `sudo elite-tune --apps` (Steam, Lutris+Wine, OBS, criação, escritório — só instala o que você marcar).

## ✂️ Debloat (o que SAI da ISO)

~55 pacotes + firmware enterprise/nvidia-nouveau cortados ≈ **1 GB+ de payload**. Nada essencial: impressão, cloud-init, guest tools de VM, VPN/modem enterprise, resgate pesado, Sway (Wayland), fontes CJK, firmwares de SoC/servidor…

Tabela completa pacote-a-pacote com justificativa e comando de restore: **[docs/CHANGES.md](docs/CHANGES.md)**.
Tudo volta com 1 comando: `sudo pacman -S <pacote>` (ou `linux-firmware` p/ firmware completo).

## 🎮 Launch options recomendadas

```
PROTON_ENABLE_NVAPI=1 gamemoderun mangohud %command%
```
VRAM apertada (8 GB): `gamescope -W 1920 -H 1080 -w 1280 -h 720 -Y -f -- %command%` (NIS; troque `-Y` por `-U` para FSR).
Experimental (kernel 6.14+): adicionar `PROTON_USE_NTSYNC=1`.

## 🧬 BIOS — checklist Elite A (Ryzen 7 5700X + RTX 5060)

- [ ] **DOCP/XMP** a 3200 MHz (`elite-tune` reclama se a RAM estiver abaixo de 3000)
- [ ] **2 pentes** = dual-channel (1 pente = −10~15% fps — `dmidecode -t 17` pra conferir)
- [ ] **Above 4G Decoding + ReBAR** (ligar os DOIS juntos)
- [ ] **PBO + Curve Optimizer** negativo (−15 → −20, testar estabilidade)

## 🩺 Troubleshooting

| Sintoma | Causa | Solução |
|---|---|---|
| `illegal instruction` no boot | CPU < x86-64-v3 | Use a ISO oficial do Archcraft (o script/tuning ainda serve via `elite-tune`) |
| Tela preta NVIDIA no live | Blackwell + nouveau | Entrada **"Nvidia"** no menu de boot |
| GTX 900/1000 no instalado | branch open não suporta Maxwell/Pascal | `paru -S nvidia-580xx-dkms` e `sudo elite-tune --yes` (script orienta) |
| Janela não acelera ao ganhar foco | fg-booster | `systemd-cgls /fg-boost.slice` (app focado deve aparecer; some ao perder foco) |
| Snapshot não aparece no GRUB | grub-btrfsd × timeshift | `sudo systemctl status grub-btrfsd` — snapshots da timeshift são detectados automaticamente nas versões atuais |

## 🔒 Segurança / rollback

- Chave GPG CachyOS `F3B607488DB35A47` importada no build **e** no sistema instalado; pacman **stock** (o fork do CachyOS não é instalado)
- `elite-tune` aceita `--dry-run`; toda mudança em arquivo ganha `.bak.<timestamp>`
- Kernel `linux` do Arch permanece instalado → fallback no GRUB (Advanced options)
- Rollback dos repos: remover as seções `[cachyos*]` do `/etc/pacman.conf` + `sudo pacman -Qqn | pacman -S -`

## 🏗️ Build

**GitHub Actions (recomendado):** push na `main` (ou *Run workflow*) → job `lint` (shellcheck gate) → job `build` (~35–55 min) → artefato + release automático em tag `v*`.

**Local (em Arch, com archiso):**
```bash
bash scripts/apply-overlay.sh
cd elite-build/profile && sudo ./mkarchcraftiso -v -w /tmp/iso-work -o out .
```

## 📁 Estrutura

```
├── .github/workflows/build.yml      ← CI: lint (shellcheck) + build + release (split se >2GiB)
├── scripts/apply-overlay.sh         ← o "delta": clona upstream + aplica a camada Elite
└── elite/
    ├── packages.add                 ← kernel BORE, scx, boosters, gaming, Vulkan
    ├── packages.remove              ← debloat cirúrgico documentado
    ├── pacman-repos.build.add       ← repos CachyOS (cdn77+us) antes de [core]
    ├── fragments/elite-customize.sh ← E0–E7: chave, keyring, pacman.conf limpo,
    │                                  cirurgia no Calamares (BORE no /boot do alvo,
    │                                  initcpio@elite, btrfs default), preset pós-install
    └── airootfs/                    ← sysctl, zram, udev, units (scx-elite, fg-booster,
                                       dmemcg, firstboot), preset mkinitcpio BORE,
                                       MangoHud, wallpapers Elite, scripts usr/local/bin
```

Documentação por script (o quê / como rodar / como reverter / dependências): **[docs/SCRIPTS.md](docs/SCRIPTS.md)**.

## 🙏 Créditos

- **[Archcraft](https://github.com/archcraft-os/archcraft)** — Aditya Shakya (adi1090x): profile, rice, pacotes e o mkarchcraftiso. A Elite é um overlay; o mérito do sistema base é todo dele.
- **[CachyOS](https://cachyos.org)** — kernel BORE, repos v3, settings, boosters (dmemcg/plasma-foreground-booster) e a wiki que guia boa parte das decisões.
- **Arch Linux**, **[sched-ext/scx](https://github.com/sched-ext/scx)**, **Valve** (gamemode/gamescope/Proton), **SteamOS** (sysctl/zram), **Fedora** (zram-generator).

## 📄 Licença

MIT para os arquivos deste overlay (veja [LICENSE](LICENSE)). O profile do Archcraft clonado em build-time mantém a licença do upstream (GPL-3.0), assim como os respectivos softwares de cada projeto citado acima.
