# Archcraft Elite Edition 🏎️

ISO do Archcraft (Openbox/BSPWM) com a camada completa de otimização **CachyOS + Valve** aplicada de fábrica — kernel BORE, sched-ext, ananicy-cpp, gerenciamento de VRAM (dmemcg-booster), zram, fg-booster e NVIDIA pronto para o primeiro boot.

**Não é um fork.** É um *overlay delta*: a cada build, o GitHub Actions clona o profile oficial do Archcraft e aplica a camada Elite por cima — dotfiles, temas, Calamares e driver NVIDIA live sempre sincronizados com o upstream, zero manutenção de fork.

## O que vem assado na ISO

| Camada | Pacote/Config | Fonte |
|---|---|---|
| Kernel | `linux-cachyos-bore` (+ `linux` do Arch como fallback de boot) | CachyOS v3 |
| Tuning de sistema | `cachyos-settings` (sysctl/udev upstream) | CachyOS v2 |
| Prioridade dinâmica | `ananicy-cpp` + `cachyos-ananicy-rules` | CachyOS |
| Scheduler plugável | `scx-tools` (bpfland default) | CachyOS v3 |
| **VRAM management** | `dmemcg-booster` (tetos p/ background — morde de verdade em AMD) | CachyOS v2 |
| Foreground booster | `fg-booster` (nossa versão X11 do plasma-foreground-booster) | este repo |
| Memória | zram zstd 8GB + sysctl elite (swappiness 180 etc.) | SteamOS/Fedora style |
| Gaming | gamemode, gamescope, mangohud (lib32 incl.), LACT | multi |
| Rollback | grub-btrfs + timeshift | Arch |
| Repos v3 | `[cachyos]` + `[cachyos-v3|core-v3|extra-v3]` antes de `[core]` | wiki.cachyos.org |

## Fluxo do usuário (a "mágica")

1. **Live**: ISO boota como Archcraft puro (nvidia-open da própria ISO + entradas open-source/nvidia/nomodeset)
2. **Instala**: Calamares padrão (btrfs recomendado) — unpackfs copia o root inteiro (configs + keyring + repos)
3. **Primeiro boot**: `elite-firstboot.service` roda UMA vez → troca `nvidia-open` por `nvidia-open-dkms` (compila para os 2 kernels), habilita scx/ananicy/fg-booster/dmemcg/grub-btrfsd, insere tokens GRUB (`amd_pstate=active nowatchdog zswap.enabled=0 transparent_hugepage=always`), se auto-desativa e avisa: **reboot**
4. **Segundo boot**: sistema Elite completo. Apps opcionais: `sudo elite-tune --apps` (Steam/Lutris/OBS/...)

Certificação: `sudo elite-tune --status` (ou `elite-status`).

## Build

**GitHub Actions (recomendado):**
1. Push deste repo para o GitHub → aba **Actions** → *Build Elite ISO* → **Run workflow**
2. Build: ~35–55 min (container archlinux + mkarchcraftiso). Artefato = ISO + sha256
3. Tag `v*` → cria Release automaticamente (GITHUB_TOKEN nativo, sem PAT)

**Local (em Arch):**
```bash
bash scripts/apply-overlay.sh
cd elite-build/profile && sudo ./mkarchcraftiso -v -w /tmp/iso-work -o out .
```

## Estrutura

```
├── .github/workflows/build.yml     ← CI: clona Archcraft + overlay + mkarchcraftiso + release
├── scripts/apply-overlay.sh        ← o "delta": overlay elite sobre o profile upstream
└── elite/
    ├── packages.add                ← pacotes extras (kernel BORE, scx, dmemcg, stack gaming)
    ├── pacman-repos.build.add      ← repos CachyOS (Servers diretos, inseridos antes de [core])
    ├── fragments/elite-customize.sh← anexado ao customize_airootfs: chave F3B607488DB35A47,
    │                                  keyring+mirrorlist v3 (pacman -U, sem pacman fork),
    │                                  pacman.conf limpo com v3 + [multilib]
    └── airootfs/                   ← sysctl, zram, udev, fg-boost.slice, fg-booster.service,
                                       elite-firstboot.service (+ enable), skel MangoHud,
                                       elite-tune v4.1, fg-booster v4.1, elite-status
```

## Segurança / rollback

- Chave GPG CachyOS: `F3B607488DB35A47` (keyserver.ubuntu.com) — importada no build E no sistema
- pacman **stock** preservado (o fork do pacman do CachyOS **não** é instalado)
- Kernel `linux` do Arch permanece instalado → fallback no GRUB (Advanced options)
- `elite-tune` aceita `--dry-run`; toda mudança em arquivo ganha `.bak.<timestamp>`
- Rollback completo dos repos: remover as seções `[cachyos*]` do pacman.conf + `pacman -Qqn | pacman -S -`

## Notas de hardware

- **Requer x86-64-v3** (Haswell 2014+ / Excavator+ / Zen+). Elite A (5700X) ✓. Para CPU mais antiga, avise — variante v2 = troca de 3 linhas.
- NVIDIA: firstboot instala `nvidia-open-dkms` (Turing+; Blackwell = único caminho). Maxwell/Pascal: tenta `nvidia-dkms` (branch 580) com instrução de fallback AUR.
- AMD: driver nada a fazer (mesa/RADV na ISO); dmemcg-booster **enforça** tetos de VRAM de verdade.
- 16GB RAM: zram 8GB zstd essencial. Verifique dual-channel (`dmidecode -t 17`) — 1 pente = -10-15% fps.

## PAT (só para o push inicial do repo)

O build/release no Actions usa o `GITHUB_TOKEN` nativo — **nenhum PAT necessário para buildar**. PAT só para eu fazer o push inicial por você:

1. Crie o repo vazio no GitHub (ex.: `SEU_USER/archcraft-elite`)
2. Settings → Developer settings → Fine-grained tokens → Generate: escopo **só esse repo**, permissão **Contents: Read/Write**, expiração **7 dias**
3. Passe o token; após o push confirmado, **revogue**
