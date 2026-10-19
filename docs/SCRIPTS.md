# SCRIPTS — documentação por script

Formato: **o quê faz / como rodar / como reverter / dependências**.

---

## elite-tune (v4.2) — `/usr/local/bin/elite-tune`

**O quê:** detecção de hardware (ISA x86-64, GPU+geração, RAM/pentes/MHz, discos) e aplicação da camada Elite: repos CachyOS (chave F3B607488DB35A47 + keyring + mirrorlist via `pacman -U`, sem pacman fork), kernel BORE, daemons (ananicy, scx-elite, dmemcg, fg-booster, grub-btrfsd, lactd), boot params GRUB (quote-safe), driver NVIDIA por geração (Turing+ → `nvidia-open-dkms`; Maxwell/Pascal → orientação AUR `nvidia-580xx-dkms`), zram/sysctl/udev idempotentes, shader cache NVIDIA.

**Modos:**
```bash
sudo elite-tune                 # interativo (dossiê + confirmação)
sudo elite-tune --dry-run      # simula (nada é escrito; pacotes não executam)
sudo elite-tune --yes          # sem confirmações
sudo elite-tune --firstboot    # não-interativo (usado pela unit elite-firstboot)
sudo elite-tune --apps         # menu de apps: Steam / Lutris+Wine / OBS / criação / escritório
elite-tune --status            # certificação (sem root) — alias: elite-status
```

**Reverter:** todo arquivo editado ganha `.bak.<timestamp>` junto ao original. Repos: remova as seções `[cachyos*]` do `/etc/pacman.conf`. Kernel: `pacman -R linux-cachyos-bore` (o `linux` do Arch nunca sai).

**Depende de:** pacman, lspci (pciutils), dmidecode, curl, GRUB (grub-mkconfig).

---

## fg-booster (v4.1.1) — `/usr/local/bin/fg-booster` (unit `fg-booster.service`)

**O quê:** a cada segundo, identifica a janela em foco (xdotool, EWMH — Openbox/BSPWM ok) e promove a árvore de processos dela para `fg-boost.slice` (CPUWeight/IOWeight 900, **sem teto de VRAM** — os tetos são do dmemcg-booster). Ao perder o foco, devolve cada processo ao **cgroup leaf de origem** (registrado no momento da promoção; escrita em leaf é sempre permitida pelo cgroup v2 — o bug da v4.0, que devolvia p/ um slice interno e era rejeitado, morreu). PIDs mortos são limpos do mapa a cada 30 polls.

**Como rodar:** já vem habilitado (`graphical.target.wants`). Manual: `sudo systemctl enable --now fg-booster`.

**Validar:** `systemd-cgls /fg-boost.slice` — o app focado aparece no slice e some ao perder o foco. `elite-tune --status` mostra quantos PIDs estão no slice.

**Reverter:** `sudo systemctl disable --now fg-booster`.

**Depende de:** xdotool, cgroup v2, X11 com WM EWMH (não serve p/ Wayland).

---

## elite-status — `/usr/local/bin/elite-status`

**O quê:** alias de `elite-tune --status` (kernel, driver cpufreq, cmdline, zram, THP, repos, estado dos serviços Elite, GPU/BAR1, contador do fg-boost.slice).

**Como rodar:** `elite-status` (sem root).

---

## elite-wallpaper — `/usr/local/bin/elite-wallpaper`

**O quê:** aplica um wallpaper da coleção Elite (`/usr/share/backgrounds/elite/`): `feh` imediato + `nitrogen` persistente; dica de `betterlockscreen`.

**Como rodar:** `elite-wallpaper` (elite-01) ou `elite-wallpaper 2` (elite-02), dentro da sessão X11.

**Reverter:** `nitrogen` (GUI) ou `feh --bg-fill <arquivo>`.

**Depende de:** feh e/ou nitrogen (já no Archcraft).

---

## apply-overlay.sh — `scripts/apply-overlay.sh` (repo)

**O quê:** o "delta" inteiro. Clona o profile oficial do Archcraft, aplica o overlay `elite/airootfs`, mescla `packages.add`, comenta os de `packages.remove`, troca o firmware meta por subpacotes, insere os repos CachyOS antes de `[core]`, patcha as entradas de boot (BORE em default/opensource/nomodeset; Nvidia fica no stock), remove wants de serviços debloatados, anexa o fragmento E0–E7 ao customize_airootfs, cria o mirrorlist do archcraft p/ o ambiente de build (root/CI) e rebatiza a ISO p/ `archcraft-elite-<data>`.

**Como rodar:** `bash scripts/apply-overlay.sh` → saída em `elite-build/`.

**Reverter:** inexistente por design — cada execução começa de um clone fresco (`rm -rf elite-build` se quiser).

**Depende de:** git, rsync, curl.

---

## elite-customize.sh (fragmento E0–E7) — anexado ao customize_airootfs do upstream

**O quê:** roda DENTRO do airootfs no fim do build. E0: DNS do chroot. E1: chave CachyOS no keyring (vale p/ live e instalado — o gnupg é copiado pelo unpackfs). E2: keyring+mirrorlist v3 via `pacman -U` (fallback: mirrorlist escrito na mão). E3: pacman.conf do sistema reescrito limpo (archcraft → cachyos → core/extra/multilib). E4: `pacman -Sy` valida os 6 repos no chroot. E5: cirurgia no Calamares (unpackfs copia o vmlinuz BORE; instância `initcpio@elite`; packagechooser sem Sway; btrfs default). E6: preset do BORE vira default/fallback p/ o sistema instalado. E7: tira cups/avahi da lista de serviços do post-install do Archcraft.

**Como rodar:** automático (mkarchcraftiso chama o customize_airootfs.sh no build).

**Reverter:** n/a (build-time; o resultado vai pra ISO).

---

## elite-firstboot.service — unit (airootfs overlay)

**O quê:** no primeiro boot do sistema **instalado** (nunca no live: `ConditionPathExists=!/run/archiso`), roda `elite-tune --firstboot` (driver GPU + serviços + tokens GRUB), loga em `/var/log/elite-firstboot.log`, cria o marker `/var/lib/elite/firstboot-done`, se auto-desativa e avisa via `wall` p/ reiniciar.

**Como rodar:** automático. Manual: `sudo systemctl start elite-firstboot`.

**Reverter:** `sudo systemctl disable elite-firstboot` + remover o marker p/ reexecutar: `sudo rm /var/lib/elite/firstboot-done`.
