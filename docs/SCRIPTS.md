# SCRIPTS — documentação por script

Formato: **o quê faz / como rodar / como reverter / dependências**.

---

## elite-tune (v4.5) — `/usr/local/bin/elite-tune`

**O quê:** detecção de hardware (ISA x86-64, GPU+geração, RAM/pentes/MHz, discos) e aplicação da camada Elite: repos CachyOS (chave F3B607488DB35A47 + keyring + mirrorlist via `pacman -U`, sem pacman fork), kernel BORE, daemons (ananicy, scx-elite, dmemcg, fg-booster, grub-btrfsd, lactd), boot params GRUB (quote-safe), driver NVIDIA por geração (Turing+ → `nvidia-open-dkms`; Maxwell/Pascal → orientação AUR `nvidia-580xx-dkms`), zram/sysctl/udev idempotentes, shader cache NVIDIA. **v4.5 — firstboot anti-brick:** a troca de driver NVIDIA é `-S` → `-R` (instala o dkms ANTES de remover o pré-compilado); sem rede no 1º boot o driver do live fica **preservado**, o marker `firstboot-done` **não** é escrito e a unit re-tenta no boot seguinte — o wall avisa "pendente" em vez de "REINICIE".

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

## apply-overlay.sh — `scripts/apply-overlay.sh` (repo)

**O quê:** o "delta" inteiro. Clona o profile oficial do Archcraft, aplica o overlay `elite/airootfs`, mescla `packages.add`, comenta os de `packages.remove`, troca o firmware meta por subpacotes, insere os repos CachyOS (trio v3 + baseline) antes de `[core]`, patcha as entradas de boot (BORE em default/opensource/nomodeset; Nvidia fica no stock), adiciona a entrada "Copy to RAM" (`copytoram=y`, USB lento/Ventoy), injeta `systemd.default_timeout_start_sec=90 systemd.default_timeout_stop_sec=90` no cmdline de TODAS as entradas dos 3 bootloaders ([6.2] — no live o PID-1 vindo do initramfs não reavalia drop-ins de `/etc` após o switch_root; o cmdline é a única precedência que sempre vence), remove wants de serviços debloatados, patcha o mkarchcraftiso p/ pacstrap não-interativo, anexa o fragmento E0–E8 ao customize_airootfs, expande grupos em pacotes explícitos (CI), cria o mirrorlist do archcraft p/ o ambiente de build (root/CI) e rebatiza a ISO p/ `archcraft-elite-<data>`.

**Como rodar:** `bash scripts/apply-overlay.sh` → saída em `elite-build/`.

**Reverter:** inexistente por design — cada execução começa de um clone fresco (`rm -rf elite-build` se quiser).

**Depende de:** git, rsync, curl.

---

## elite-customize.sh (fragmento E0–E10) — anexado ao customize_airootfs do upstream

**O quê:** roda DENTRO do airootfs no fim do build. E0: DNS do chroot. E1: chave CachyOS no keyring (vale p/ live e instalado — o gnupg é copiado pelo unpackfs). E2: keyring+mirrorlist v3 via `pacman -U` (fallback: mirrorlist escrito na mão). E3: pacman.conf do sistema reescrito limpo (archcraft → cachyos → core/extra/multilib). E4: `pacman -Sy` valida os 6 repos no chroot. E5: cirurgia no Calamares (unpackfs copia o vmlinuz BORE; instância `initcpio@elite`; packagechooser só labwc; btrfs default). E6/E6b: presets default/fallback do BORE **e** do kernel stock p/ o instalado. E7: tira cups/avahi da lista de serviços do post-install do Archcraft. E8: remove o repo de build `[elite-local]` da ISO. E9: limpa do skel configs de sessões extintas. **E10 (v1.0.4): recopia TODOS os vmlinuz-\*** do pendrive p/ `/boot` do alvo (o rsync→btrfs do unpackfs truncava arquivos grandes — causa-raiz do `premature end of file` no rig B) **e regenera o initramfs do BORE no alvo** com hooks de sistema.

**Como rodar:** automático (mkarchcraftiso chama o customize_airootfs.sh no build).

**Reverter:** n/a (build-time; o resultado vai pra ISO).

---

## elite-firstboot.service — unit (airootfs overlay)

**O quê:** no primeiro boot do sistema **instalado** (nunca no live: `ConditionPathExists=!/run/archiso`), roda `elite-tune --firstboot` (driver GPU + serviços + tokens GRUB), loga em `/var/log/elite-firstboot.log`, cria o marker `/var/lib/elite/firstboot-done`, se auto-desativa e avisa via `wall` p/ reiniciar.

**Como rodar:** automático. Manual: `sudo systemctl start elite-firstboot`.

**Reverter:** `sudo systemctl disable elite-firstboot` + remover o marker p/ reexecutar: `sudo rm /var/lib/elite/firstboot-done`.
