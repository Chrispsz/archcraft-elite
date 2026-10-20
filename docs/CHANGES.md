# CHANGES — Elite Edition vs. Archcraft upstream

Todo delta é aplicado pelo `scripts/apply-overlay.sh` em cima do clone fresco
do profile oficial. Nada é deletado do upstream — pacotes removidos são
**comentados** no `packages.x86_64`; arquivos Elite são sobrepostos.

## 🗺️ Visão por versão

- **v1.0.3** — sessão **ÚNICA labwc (Wayland)** com o rice Catppuccin Mocha
  (Waybar/SwayNC/Fuzzel/foot + helpers `craft-*` + fastfetch);
  **Openbox/BSPWM + satélites X11 removidos** (zero duplicação: um WM, um
  terminal, uma barra, um launcher — música de exemplo fora, a barra toca a
  SUA música via playerctl); fix 203/EXEC dos binários no live (0755 no
  `file_permissions`); `Slice=` no fg-booster; Calamares apontado p/ labwc;
  documentado o requisito **x86-64-v3** (ISO inteira, não só o kernel).
- **v1.0.2** — primeira pública (kernel BORE v3 + engine CachyOS + Vulkan + debloat).

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
| **v1.0.3** `labwc` | **A sessão default** (Wayland, clone do Openbox em gramática `rc.xml`) — o live autologa e o sistema instalado inicia nela |
| **v1.0.3** `waybar` `swaync` `fuzzel` `foot` | Barra floating pill + central de notificações + launcher + terminal (rice Catppuccin Mocha no skel) |
| **v1.0.3** `swaybg` `swaylock` `wl-clipboard` `grim` `slurp` | Wallpaper (cor sólida Base), bloqueio de tela (W-l/`craft-lock`), clipboard Wayland e screenshots (W-P/`craft-shot`) |
| **v1.0.3** `playerctl` `brightnessctl` `pulsemixer` | Teclas de mídia/brilho e o mixer W-a do `rc.xml` |
| **v1.0.3** `polkit-gnome` | Agente de senha da sessão labwc (o do Archcraft só sobe no Openbox) |
| **v1.0.3** `xdg-desktop-portal-wlr` | Screenshare/gravação no Wayland (sem isto OBS vê tela preta no labwc) |
| **v1.0.3** `mpv` `imv` | Player de vídeo/imagem minimalistas (mesmo set do zip Cockpit) |
| **v1.0.3** `fastfetch` | O `craft-hello` (W-S-h) mostra o sistema com ele |

## ➖ Removidos (`elite/packages.remove`) — restore: `sudo pacman -S <pkg>`

| Grupo | Pacotes | Por quê sai | Risco |
|---|---|---|---|
| WM Wayland | `archcraft-sway-free` | A edição Sway do Archcraft é OUTRA stack (sway+wlroots próprios); a sessão Wayland da Elite é o **labwc** com configs próprias | quem quiser Sway: `pacman -S archcraft-sway-free` |
| **v1.0.3** Sessões X11 | `archcraft-openbox` `archcraft-bspwm` | **Diretriz do dono: labwc é A sessão** (Wayland, leve, moderna). Temas OB ficam (`archcraft-openbox-themes`) — o labwc lê os mesmos temas | `pacman -S archcraft-openbox` (ou `archcraft-bspwm`) |
| **v1.0.3** Instalador TUI | `archcraft-installer` | Calamares é o instalador da Elite; o TUI tem dep dura de `alacritty` (removido) | `pacman -S archcraft-installer` |
| **v1.0.3** Satélites X11 | `polybar` `tint2` `rofi` `picom` `obmenu-generator` `lead-git` `skippy-xd-git` `plank` `ksuperkey` `wmname` `wmctrl` `nitrogen` `hsetroot` `maim` `slop` `xclip` `betterlockscreen` `i3lock-color` `dunst` `obconf-qt` `light` `archcraft-arandr` `archcraft-randr` `archcraft-dunst-icons` `networkmanager-dmenu-git` | Cada um tem par Wayland na sessão labwc: waybar (barra), fuzzel (launcher), swaybg (wallpaper), grim/slurp (screenshots), wl-clipboard, swaylock, swaync (notificações), brightnessctl (brilho), wdisplays (monitores), blueman/nm-applet (trays) | `pacman -S <pkg>` — o X11 continua utilizável via XWayland |
| **v1.0.3** Terminais | `alacritty` `kitty` `kitty-terminfo` `xfce4-terminal` | **Dedupe de duplicação** (diretriz do áudio): 4 terminais viram 1 — o `foot` dos keybinds do `rc.xml` | `pacman -S alacritty` (ou kitty/xfce4-terminal) |
| **v1.0.3** Música exemplo/console | `archcraft-music` `archcraft-config-music` `mpd` `ncmpcpp` `mpc` `mplayer` | **Diretriz do áudio**: nada de sample music no sistema; a barra/notificações tocam a SUA música (playerctl/MPRIS — YouTube/Spotify/mpv). `mpv` fica p/ arquivos locais | `pacman -S mpd ncmpcpp` (stack console) |
| **v1.0.3** X11 dev/test | `xorg-server-devel` `-src` `-xephyr` `-xnest` `-xvfb` `xorg-docs` `xorg-util-macros` `xorg-bdftopcf` `xorg-fonts-100dpi` `xorg-fonts-75dpi` `xorg-fonts-alias` `xorg-x11perf` | Vieram da expansão do grupo `xorg` no pacstrap CI; dev/test/bitmap-fonts não pertencem a um live de desktop. O `xorg-server` FICA (greeter SDDM x11 + fallback nomodeset) + `xorg-xwayland` | `pacman -S <pkg>` |
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
| **v1.0.3** Sessão do live (autologin SDDM) | `openbox` | **`labwc`** (Wayland, única sessão) — `state.conf` pré-seleciona labwc no greeter do instalado também |
| **v1.0.3** packagechooser do Calamares | openbox/bspwm/sway/everything | **item único `labwc`** (página Desktop apenas confirma) + `chrooted_autologin.sh --labwc` |
| ISO | `archcraft-<data>-x86_64.iso` | `archcraft-elite-<data>-x86_64.iso` |
| Unit scx | — | `scx-elite.service` (bpfland; `systemctl edit` troca o scheduler) |
| Unit dmemcg | — | `dmemcg-booster-system.service` habilitada via wants |
| **v1.0.3** fg-booster.service | — | `Slice=fg-boost.slice` (realiza o slice; sem isto o script saía na guarda e reiniciava em loop) |

## 🆕 Arquivos novos no airootfs

- `/etc/sysctl.d/99-elite.conf` — swappiness 180, vfs_cache_pressure 50, max_map_count Steam, page_lock_unfairness
- `/etc/systemd/zram-generator.conf` — zram0 zstd, ½ RAM (teto 8 GB)
- `/etc/udev/rules.d/60-io-elite.rules` — NVMe/SSD `none`, HDD `bfq`
- `/etc/systemd/system/{elite-firstboot,fg-booster,scx-elite}.service`, `fg-boost.slice` (+ wants)
- `/etc/mkinitcpio.d/linux-cachyos-bore.preset` — preset archiso p/ o live
- `/etc/skel/.config/MangoHud/MangoHud.conf` — overlay com VRAM
- `/usr/local/bin/{elite-tune,elite-status,fg-booster}`
- **v1.0.3** `/etc/skel/.config/labwc/{rc.xml,menu.xml,autostart}` — a sessão inteira no skel (o mkarchcraftiso copia o skel p/ o home do liveuser preservando modos; novos usuários do instalado herdam pelo `useradd -m`)
- **v1.0.3** `/etc/skel/.config/{waybar,swaync,fuzzel}/` — rice Catppuccin Mocha da barra/notificações/launcher
- **v1.0.3** `/usr/local/bin/craft-{hello,update,clean,rollback,lock,logout,shot,bat}` — helpers dos keybinds do `rc.xml` (mesmos comandos do zip Cockpit; `craft-rollback` aponta p/ Timeshift na ISO)
- **v1.0.3** `/etc/sddm.conf.d/kde_settings.conf` (overlay) — autologin `Session=labwc`
- **v1.0.3** `/var/lib/sddm/state.conf` — greeter do sistema instalado pré-seleciona labwc

## ⚠️ Requisito de CPU (v1.0.3 — documentado)

**A ISO inteira exige x86-64-v3 (AVX2/FMA/BMI2)** — não é só o kernel BORE:
792 dos 1203 pacotes da v1.0.2 são rebuilds v3 do CachyOS (glibc, sddm,
xorg-server, qt6, mesa…). Zen 3 (Ryzen 5000) e superior rodam com folga.
Verificação em qualquer máquina:

```bash
/lib64/ld-linux-x86-64.so.2 --help | grep supported
# x86_64 (baseline), x86-64-v2, x86-64-v3  ← precisa listar o v3
```

CPU sem AVX2 (ex.: Celeron Gemini Lake) → usar o zip irmão
`archcraft-labwc-lite` (repos oficiais da distro, zero CachyOS).

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

## v4.5 — triagem do feedback externo (só o real) + E2 offline-first

Triagem de uma análise externa do repo — 3 alegações, 2 procedentes
(1 parcialmente), 1 falsa/perigosa:

- **REAL — checkout@v4 em Node 20**: warning de deprecação confirmado
  nos logs de TODO run (`##[warning]Node.js 20 is deprecated … forced to
  run on Node.js 24: actions/checkout@v4`). Bump para `actions/checkout@v5`
  (Node 24 nativo) nos 2 jobs. `upload-artifact@v4` não gera warning
  (4.x atual já é Node 24).
- **PARCIAL — XferCommand com mais retries**: o conf de build sobe para
  `--retry 5 --retry-delay 5 --retry-connrefused --retry-all-errors
  --retry-max-time 120 --speed-time 60 --speed-limit 1024`.
  O que foi REJEITADO da sugestão (10×10s/300s): janelas reais de skew
  duram MINUTOS (run #13: 216×404) — esperar 300s às cegas não cura nada,
  só queima tempo; e no preflight a espera cegaria a sonda HEAD que
  injeta o baseline Arch em segundos (determinístico). Preflight continua
  fail-fast 3×3 (saída já vai p/ /tmp/elite-pf.log, console limpo).
  Acréscimos próprios: `--retry-connrefused` (edge CDN recusando é
  retriable) e `--speed-time/-limit` (transferência PARADA vira erro
  retriable — sem isso o curl não tem timeout e travaria até o limite
  do job).
- **FALSA — .sig dummy no [elite-local]**: o curl (37) do `elite-local.db.sig`
  era real no run #13 (12×), mas já foi eliminado NA RAIZ pelo
  `SigLevel = Never` (v4.4, runs #14/#15 com 0 curl errors na fase que
  rodou): Never = pacman não sonda .sig NENHUM. O fix sugerido seria
  nocivo: `.sig` presente + `Optional` = assinatura inválida = erro FATAL
  do pacman ("invalid or corrupted database"); sob Never o arquivo nem
  é lido. Nada aplicado — problema não existe mais.
- **E2 offline-first (além do feedback, mata a última rede do customize)**:
  `.ci/build.sh` baixa `cachyos-keyring` + `cachyos-v3-mirrorlist`
  (listing do us → pin; download cdn77 → us → pin) p/ o `[elite-local]`
  ANTES do repo-add; o E2 vira `pacman -S` file:// (primeiro repo do
  conf de build) — o chroot não toca a rede no customize. Escada de
  fallback: `[elite-local]` → `pacman -U` mirror → mirrorlist manual
  (chave via E1 keyserver). Validado ao vivo: escada executada de
  verdade (cdn77 primeiro, 200/200), pacotes abertos e conferidos
  (`usr/share/pacman/keyrings/cachyos.gpg`; `etc/pacman.d/cachyos-v3-mirrorlist`).

## v4.6 — run #16: causa raiz do preflight surdo (prova binária)

- **Run #16**: execv-safe funcionou (dbs sincronizaram; round 1 baixou
  440 pacotes em 239s), mas **2 pacotes 404aram em TODOS os 6 rounds**
  e o preflight nunca injetou baseline: `pacman -Sp --print-uris`
  morreu em TUDO com saída vazia ("db sync quebrado?" — diagnóstico
  errado).
- **Prova binária**: `--print-uris` foi REMOVIDO no pacman 6.0 (2021) —
  `strings` no binário real do core (pacman 7.1.0): 0 ocorrências de
  `print-uris`, `--print-format <string>` presente. getopt mata o
  comando com "unrecognized option" (stderr silenciado pelo 2>/dev/null)
  → zero URLs → sonda cega → injeção nunca dispara → abort.
- **Fix (2 call sites)**: `-Sp --print-uris` → `-Sp --print-format '%l'`.
  Semântica do substituto (lida no fonte 6.0.2, `pkg_get_location`):
  URL p/ pacote fora do cache, `file://<caminho>` p/ cacheado — o grep
  `^https?` filtra os locais e a sonda recebe EXATAMENTE o conjunto
  não-cacheado (o que interessa). Fonte: sync.c + util.c do pacman.
- **Diagnóstico honesto**: stderr do -Sp agora vai p/ arquivo e, se a
  lista vier vazia, o ERRO REAL do -Sp aparece no console (antes só o
  tail do -Syw — que apontava p/ lugar errado).
- **Sweep dos repos (agora)**: CachyOS 4 dbs × listing do us = 0 faltando;
  archcraft 190/190 HEADs = 200. Os 2× 404 do #16 eram janela transitória
  de propagação (02:19–02:28 UTC), já curada — a sonda+baseline é o
  remédio permanente p/ quando a janela reabrir.
