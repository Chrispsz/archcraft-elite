# CHANGES — Elite Edition vs. Archcraft upstream

Todo delta é aplicado pelo `scripts/apply-overlay.sh` em cima do clone fresco
do profile oficial. Nada é deletado do upstream — pacotes removidos são
**comentados** no `packages.x86_64`; arquivos Elite são sobrepostos.

## ➕ Adicionados (`elite/packages.add`)

| Pacote | Por quê |
|---|---|
| `linux-cachyos-bore` + `-headers` | Kernel BORE build x86-64-v3 (patchset CachyOS: latência + throughput). `linux`/`linux-headers` do Arch ficam como fallback e alvo do dkms |
| `cachyos-settings` | sysctl/udev/modprobe/limits de fábrica (70-cachyos-settings.conf; sem pacman fork, sem zram — o nosso `/etc` vence) |
| `cachyos-ananicy-rules` + `ananicy-cpp` | Regras de prioridade dinâmica para jogos/DE |
| `scx-scheds` | **Os binários** sched-ext (`scx_bpfland`, `scx_lavd`, …) — pacote do Arch `extra`; o CachyOS não empacota mais os schedulers |
| `scx-tools` | `scxctl`/`scxtui`/`scx_loader` (troca de scheduler em runtime) |
| `dmemcg-booster` | Tetos de VRAM p/ apps em background (unit `dmemcg-booster-system.service`) |
| `gamemode` + `lib32-gamemode` | Governor/prioridade ao rodar jogos |
| `gamescope` | Compositor micro do Valve (subnativo NIS/FSR p/ VRAM apertada) |
| `mangohud` + `lib32-mangohud` | Overlay de fps/frametime/VRAM (config no skel com VRAM à mostra) |
| `vulkan-radeon` / `vulkan-intel` (+ lib32) | **Vulkan de série** — o upstream só traz mesa; sem isto RADV/ANV não existem |
| `lib32-mesa` | 32-bit GL p/ jogos Proton antigos |
| `nvtop`, `btop` | Monitor de GPU / TUI de sistema |
| `lact` | Controle de GPU (undervolt/OC; ppfeaturemask já desbloqueado no tune AMD) |
| `grub-btrfs`, `timeshift` | Rollback real (btrfs default no installer + grub-btrfsd) |
| `pciutils` | `lspci` para a detecção de hardware do `elite-tune` |

## ➖ Removidos (`elite/packages.remove`) — restore: `sudo pacman -S <pkg>`

| Grupo | Pacotes | Por quê sai | Risco |
|---|---|---|---|
| WM Wayland | `archcraft-sway-free` | Elite = X11 (Openbox/BSPWM); fg-booster é X11/EWMH. Item "Sway" removido do packagechooser do Calamares junto | quem quiser Sway: `pacman -S archcraft-sway-free` |
| Impressão | `cups` `cups-pdf` `cups-filters` `ghostscript` `gsfonts` `foomatic-db-engine` `foomatic-db` `gutenprint` | ~400 MB instalados com deps | impressora: `pacman -S cups cups-filters gutenprint foomatic-db` + `systemctl enable --now cups` |
| Cloud/VM | `cloud-init` `hyperv` `open-vm-tools` `virtualbox-guest-utils` `qemu-guest-agent` `xf86-input-vmmouse` | daemons de graça em bare-metal; cloud-init ainda atrasava o boot | VM: `pacman -S <guest-tools-do-hypervisor>` |
| Modem/VPN legacy | `modemmanager` `ppp` `pptpclient` `xl2tpd` `wvdial` `linux-atm` `open-iscsi` `openconnect` `vpnc` `networkmanager-{openconnect,pptp,vpnc,sstp,strongswan}` `b43-fwcutter` `broadcom-wl` | PPPoE/dial-up/iSCSI/VPN enterprise; **openvpn fica** | VPN corporativa: `pacman -S networkmanager-<flavor>`; Broadcom WiFi antigo: `pacman -S broadcom-wl` |
| Resgate pesado | `clonezilla` `partclone` `partimage` `fsarchiver` `gpart` `ddrescue` | ~150 MB; testdisk/photorec e gparted ficam | pendrive de resgate dedicado |
| Rede/servidor | `bind` `dnsmasq` `nbd` `nfs-utils` `mkinitcpio-nfs-utils` `darkhttpd` `lftp` `lynx` `irssi` `nmap` `ldns` `sequoia-sq` `openpgp-card-tools` `pcsclite` | servidor DNS/DHCP/PXE/IRC/smartcard num desktop gamer | `pacman -S <pkg>` |
| FS exóticos | `bcachefs-tools` `jfsutils` `nilfs-utils` `udftools` `refind` | JFS/NilFS/UDF/CoW experimental/second bootloader | `pacman -S <pkg>` |
| Fontes | `noto-fonts-cjk` | ~90 MB de CJK | leitura/jogos CJK: `pacman -S noto-fonts-cjk` |
| Initramfs | `mkinitcpio-firmware` | duplicava firmware dentro de cada initramfs (×2 kernels no ISO) | nenhum — hook `kms` já embute o necessário |
| Console/access. | `brltty` `gpm` | braille/mouse de console | `pacman -S <pkg>` |
| Instalador TUI | `archinstall` | redundante com Calamares + ABIF | `pacman -S archinstall` |
| Pywal | `python-pywal` | **saiu dos repos oficiais** (quebrava o resolve do pacstrap); só as cores dinâmicas do rice perdem o helper | `yay -S python-pywal` |
| p7zip | `p7zip` → `7zip` | `p7zip` virou pacote **virtual** de `7zip` (2 providers em repos distintos = prompt interativo no build) | já substituído |

## 🧩 Firmware cirúrgico (apply-overlay)

O meta `linux-firmware` é trocado pelos subpacotes que cobrem **hardware
consumidor**: `amd amdgpu atheros broadcom cirrus intel mediatek radeon
realtek ti whence` (+ `linux-firmware-marvell` que já vinha no upstream).

Saem (~700 MB–1 GB brutos):

| Subpacote | Conteúdo | Por quê sai |
|---|---|---|
| `linux-firmware-nvidia` | GSP/nouveau p/ NVIDIA | só serve ao **nouveau**; o driver proprietário (nvidia-open) embute o firmware dele |
| `linux-firmware-other` | SoCs ARM, NICs antigas, DSPs… | desktop x86 não usa |
| `linux-firmware-mellanox` / `-nfp` / `-qlogic` / `-liquidio` / `-qcom` | NICs enterprise / smartNIC / ARM | fora do alvo |

Restore total: `sudo pacman -S linux-firmware`.

## ⚙️ Modificações de comportamento

| O quê | Antes (upstream) | Depois (Elite) |
|---|---|---|
| Entradas de boot default/opensource/nomodeset | kernel `linux` | kernel `linux-cachyos-bore` (a entrada **Nvidia** fica no kernel stock — módulo pré-compilado) |
| Filesystem default do Calamares | ext4 | **btrfs** (rollback: timeshift + grub-btrfsd) |
| unpackfs do Calamares | copia só `vmlinuz-linux` p/ o alvo | copia também `vmlinuz-linux-cachyos-bore` |
| initcpio do Calamares | gera initramfs só do `linux` | instância extra `initcpio@elite` gera também do BORE |
| packagechooser | Openbox/Bspwm/Sway/Everything | Openbox/Bspwm/Everything (Sway fora da ISO) |
| Serviços no post-install | `cups`/`avahi-daemon` na lista | removidos da lista (pacotes fora) |
| pacman.conf do sistema | [archcraft]+[core]+[extra] duplicados no fim | reescrito limpo: archcraft → cachyos(v2+v3 trio) → core/extra/multilib |
| mkinitcpio preset BORE | — | nasce archiso (live) e vira default/fallback no instalado (mesmo padrão do upstream p/ o linux.preset) |
| systemd wants | cloud-init/vbox/vmware/hv/ModemManager/cups/pcscd | symlinks removidos |
| ISO | `archcraft-<data>-x86_64.iso` | `archcraft-elite-<data>-x86_64.iso` |
| Unit scx | — | `scx-elite.service` (bpfland; `systemctl edit` troca o scheduler) |
| Unit dmemcg | — | `dmemcg-booster-system.service` habilitada via wants |

## 🆕 Arquivos novos no airootfs

- `/etc/sysctl.d/99-elite.conf` — swappiness 180, vfs_cache_pressure 50, max_map_count Steam, page_lock_unfairness
- `/etc/systemd/zram-generator.conf` — zram0 zstd, ½ RAM (teto 8 GB)
- `/etc/udev/rules.d/60-io-elite.rules` — NVMe/SSD `none`, HDD `bfq`
- `/etc/systemd/system/{elite-firstboot,fg-booster,scx-elite}.service`, `fg-boost.slice` (+ wants)
- `/etc/mkinitcpio.d/linux-cachyos-bore.preset` — preset archiso p/ o live
- `/etc/skel/.config/MangoHud/MangoHud.conf` — overlay com VRAM
- `/usr/local/bin/{elite-tune,elite-status,fg-booster}`

## v4.4 — zero-curl ×2 + preflight execv-safe (runs #14/#15)

- **Causa raiz dos runs #14–#15 (prova binária)**: `libalpm.so` importa
  `execv`+`fork`, não `system()` — o pacman executa o XferCommand via
  fork/execv, SEM shell. O `|| echo "ELITE-FAIL %u" >> …` do preflight
  virava argumento literal do curl → "failed to synchronize all
  databases" em TODA transferência → 4-5 rounds inúteis.
- **Preflight v3**: XferCommand plano (flags apenas); mapeamento de
  falhas por SONDA pós-round (`pacman -Sp --print-uris` → HEAD paralelo
  16× via xargs -n1); 3 rounds (não 5); ABORTA com diagnóstico em vez
  de "seguir mesmo assim"; mkarchcraftiso 2 tentativas sem sleeps de
  90s; -Syw SEM --needed (cache = transação inteira do chroot).
- **E6b**: linux.preset reescrito para default/fallback no customize —
  no alvo, o chrooted_post_install_nvidia.sh do Archcraft DELETA
  /etc/mkinitcpio.conf.d/ antes do initcpio do Calamares; o preset
  'archiso' apontava para o conf deletado → `mkinitcpio -p linux`
  morreria em "must be readable" (check_path r, fonte 42.2) e o kernel
  stock (entrada NVIDIA: nvidia-open pré-compilado) ficaria sem
  initramfs no sistema instalado.
- **BORE não shipa preset** (MTREE verificado: 0 arquivos etc/) — sem
  conflito com o overlay; o hook 90-mkinitcpio-install gera os 3
  initramfs do live num `mkinitcpio -P` único. O `linux` do Arch idem
  (7752 arquivos, 0 mkinitcpio).
- ParallelDownloads 10 no conf de build; -n1 no xargs (sem ele, só a
  1ª URL era sondada); Never nos repos unsigned (archcraft/elite-local).
