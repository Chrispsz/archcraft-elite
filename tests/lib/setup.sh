# shellcheck shell=bash
# tests/lib/setup.sh — montagem da mesa do quebra-cabeça (sourced 1×, idempotente)
# Produz: $WORK/mocks (pacman/lspci/nvidia-smi/systemctl/…), $WORK/mocks-scoped
# (ls/grep de cenário — transparentes fora do toggle), $WORK/extract.sh
# (funções reais extraídas do elite-tune) e $WORK/upstream-src (clone-fixture
# do Archcraft) + registro git insteadOf sob HOME isolado — o apply-overlay
# roda SEM rede e SEM tocar na config global do usuário.
#
# v1.1: o fixture de boot é FIEL ao upstream real (entries 01–04 com options
# completas, syslinux com 4 LABELs + APPEND, grub/loopback com cmdline
# inteira) — clonado e conferido de archcraft-os/archcraft no dia da
# adaptação; os seds/awks da seção [6] da v1.1 (copytoram, amdgpu.
# ppfeaturemask, nvidia_drm.fbdev, remoção do OpenSource) casam nele de
# verdade. Calamares ganhou unpackfs.conf + settings.conf (E5a/E5b) e o
# airootfs ganhou /etc/environment upstream (E12).

command -v git >/dev/null || { echo "ERRO: git necessário"; exit 1; }

# ── 1. mocks ────────────────────────────────────────────────────────
mk() { mkdir -p "$(dirname "$1")"; cat > "$1"; chmod +x "$1"; }

mk "$WORK/mocks/pacman" <<'EOF'
#!/usr/bin/env bash
# mock pacman — estado: $MOCK_DIR/installed.txt · histórico: $MOCK_DIR/pacman.log
ST="${MOCK_DIR:?}"; INST="$ST/installed.txt"
mkdir -p "$ST"; touch "$INST" "$ST/pacman.log"
printf 'pacman %s\n' "$*" >> "$ST/pacman.log"
case "$1" in
  -Qq|-Qi)  grep -qxF -- "$2" "$INST" ;;
  -Qqs)     grep -qE -- "$2" "$INST" ;;
  -Rns|-R)  if [[ -f "$ST/refuse" ]]; then
              echo "mock pacman: remoção bloqueada (modo refuse)" >&2; exit 1
            fi
            shift
            for p in "$@"; do
              grep -vxF -- "$p" "$INST" > "$INST.new" && mv "$INST.new" "$INST"
            done
            exit 0 ;;
  -S)       # refuse também bloqueia instalação (p/ o caminho pascal sem nvidia-dkms)
            if [[ -f "$ST/refuse" ]]; then
              echo "mock pacman: instalação bloqueada (modo refuse)" >&2; exit 1
            fi
            exit 0 ;;
  *)        exit 0 ;;
esac
EOF

mk "$WORK/mocks/lspci" <<'EOF'
#!/usr/bin/env bash
[[ -n "${LSPCI_FIXTURE:-}" ]] && cat "$LSPCI_FIXTURE"
exit 0
EOF

mk "$WORK/mocks/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
if [[ -z "${NVIDIA_SMI:-}" ]]; then
  echo "nvidia-smi: no devices found" >&2; exit 1
fi
case "$1" in
  --query-gpu*) echo "$NVIDIA_SMI" ;;
  *)            echo "NVIDIA-SMI 615.71.09  Driver OK" ;;
esac
exit 0
EOF

mk "$WORK/mocks/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "${MOCK_DIR:-/tmp}/systemctl.log"
case "$1" in
  is-active)  echo "inactive" ;;
  is-enabled) echo "enabled"  ;;
esac
exit 0
EOF

mk "$WORK/mocks/curl" <<'EOF'
#!/usr/bin/env bash
# mock curl — SEMPRE falha ("mirror fora do ar"): usado para provar os
# fallbacks PINNED_* do elite-tune sem depender de rede. Só entra em cena
# via with_mocks; as fases de overlay/release usam o curl REAL.
echo "mock curl: rede desligada (modo hermético)" >&2
exit 1
EOF

mk "$WORK/mocks/dmidecode" <<'EOF'
#!/usr/bin/env bash
# mock dmidecode — 2 cenários de RAM: dual (saudável) e single/lenta (alertas)
case "${DMIDECODE_MODE:-dual}" in
  single) printf '%s\n' 'Size: 16 GB' 'Configured Clock Speed: 2666' ;;
  *)      printf '%s\n' 'Size: 16 GB' 'Size: 16 GB' \
                   'Configured Clock Speed: 3200' 'Configured Clock Speed: 3200' ;;
esac
exit 0
EOF

for m in grub-mkconfig mkinitcpio wall; do
  mk "$WORK/mocks/$m" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$m" "\$*" >> "\${MOCK_DIR:-/tmp}/$m.log"
exit 0
EOF
done

# ── 1b. mocks-scoped (v1.1/v4.6) ────────────────────────────────────
#  ls/grep transparentes que só interceptam as DUAS sondas de ambiente que
#  o elite-tune v4.6 faz e que o sandbox não consegue simular de verdade:
#   · ls /usr/lib/modules/<kver>/updates/dkms/nvidia.ko*  (NV_PREBUILT)
#   · grep -qw bbr /proc/sys/net/.../tcp_available_...    (guard BBR)
#  Toggle por env (ELITE_SCOPED_NVLS / ELITE_SCOPED_BBR) — sem toggle o
#  binário real roda: o mock é invisível para todos os outros cenários.
REAL_LS="$(command -v ls)"; REAL_GREP="$(command -v grep)"
mk "$WORK/mocks-scoped/ls" <<EOF
#!/usr/bin/env bash
# mock ls — transparente EXCETO no glob do NV_PREBUILT do elite-tune v4.6.
# ELITE_SCOPED_NVLS=1 → responde com um .ko de mentira: prova o caminho
# "driver dkms PRÉ-COMPILADO da ISO" (1º boot offline do rig NVIDIA).
if [[ "\${ELITE_SCOPED_NVLS:-}" == 1 && "\$1" == /usr/lib/modules/*/updates/dkms/nvidia.ko* ]]; then
  echo "/usr/lib/modules/\$(uname -r)/updates/dkms/nvidia.ko.xz"
  exit 0
fi
exec "$REAL_LS" "\$@"
EOF

mk "$WORK/mocks-scoped/grep" <<EOF
#!/usr/bin/env bash
# mock grep — transparente EXCETO no guard BBR do elite-tune v4.6.
# ELITE_SCOPED_BBR=absent  → kernel SEM bbr (ramo da limpeza do sysctl.d)
# ELITE_SCOPED_BBR=present → kernel COM bbr (ramo "bbr + fq ativos")
if [[ -n "\${ELITE_SCOPED_BBR:-}" && "\${1:-}" == -qw && "\${2:-}" == bbr \\
      && "\${3:-}" == /proc/sys/net/ipv4/tcp_available_congestion_control ]]; then
  [[ "\${ELITE_SCOPED_BBR}" == present ]] && exit 0
  exit 1
fi
exec "$REAL_GREP" "\$@"
EOF

: > "$STATE/installed.txt"

# ── 2. extract.sh — funções REAIS do elite-tune (fidelidade, não cópia) ──
T="$REPO/elite/airootfs/usr/local/bin/elite-tune"
{
  echo '#!/usr/bin/env bash'
  echo "G='[1;32m'; Y='[1;33m'; R='[1;31m'; B='[1m'; N='[0m'"
  echo 'DRY="${ECT_DRY:-0}"; YES=0'
  # funções de 1 linha (say/warn/err/run/backup) e blocos multi-linha (closes em ^})
  grep -E '^(say|warn|err|run|backup)\(\)' "$T"
  sed -n '/^BK=/p' "$T"
  sed -n '/^gpu_cleanup_foreign()/,/^}$/p' "$T"
  sed -n '/^detect_hw()/,/^}$/p'      "$T"
  sed -n '/^ensure_cmdline_token()/,/^}$/p' "$T"
  grep -E '^MIRROR=|^PINNED_KEYRING=|^PINNED_V3ML=' "$T"
  sed -n '/^discover_latest()/,/^}$/p' "$T"
  cat <<'EOF'
# gatilhos de teste (controlados por env)
if [[ -n "${CU_VENDOR:-}" ]]; then gpu_cleanup_foreign "$CU_VENDOR"; exit 0; fi
if [[ -n "${DETECT_ONLY:-}" ]]; then detect_hw; printf '%s %s\n' "$VENDOR" "$GEN"; exit 0; fi
if [[ -n "${DL_PROBE:-}" ]]; then v="$(discover_latest "$DL_PROBE")"; printf '[%s]\n' "$v"; exit 0; fi
if [[ -n "${ECT_FILE:-}" ]]; then ensure_cmdline_token "$ECT_FILE" "${ECT_TOKEN:-}"; exit 0; fi
EOF
} > "$WORK/extract.sh"

# ── 3. upstream-fixture: o "Archcraft oficial" sintético ───────────
UP="$WORK/upstream-src"
export HOME_FIX="$WORK/home"
mkdir -p "$HOME_FIX"
UPSTREAM_DIR="$UP" HOME_ISOLATED="$HOME_FIX" bash <<'EOF'
set -euo pipefail
UP="$UPSTREAM_DIR"; export HOME="$HOME_ISOLATED"
git config --global user.email  "tests@elite.local"
git config --global user.name   "Elite Test Fixture"
git config --global init.defaultBranch master

P="$UP/archcraft"
mkdir -p "$P"/{airootfs/root,airootfs/usr/local/bin,airootfs/etc/systemd/system/multi-user.target.wants,airootfs/etc/calamares/modules,airootfs/usr/bin,efiboot/loader/entries,syslinux,grub}
# v1.5: ufw.service habilitado no upstream (pesquisa: profile airootfs
# systemd wants) — o apply-overlay [7] tem que derrubar o symlink
ln -s /usr/lib/systemd/system/ufw.service "$P/airootfs/etc/systemd/system/multi-user.target.wants/ufw.service"

# profiledef (a sed do apply-overlay rebatiza a ISO) — file_permissions como
# no upstream real (só os scripts próprios) p/ o [9b] injetar os Elite
# shellcheck disable=SC2016
cat > "$P/profiledef.sh" <<'EOP'
#!/usr/bin/env bash
iso_name="archcraft"
iso_application="Archcraft Live/Installation/Rescue CD"
file_permissions=(
  ["/usr/bin/choose-mirror"]="0:0:755"
  ["/usr/bin/xflock4"]="0:0:755"
)
EOP

# packages: itens do packages.remove que EXISTEM upstream (kernel stock,
# nvidia-open/settings, firefox/thunar/tumbler/vim/blueman/pavucontrol,
# cups, sway-free, cjk, linux-firmware) + itens do packages.add já
# presentes (vulkan-radeon) para provar dedupe — SEM grupos (xorg etc.)
# para manter o teste offline. v1.1: linux-headers/tumbler/vim/blueman
# entraram (o packages.remove os referencia — comentados no resultado);
# mousepad/zathura/file-roller/xgps/xgpsspeed NÃO existem upstream (o
# remove os documenta como contrato; o overlay só avisa).
# shellcheck disable=SC2016
cat > "$P/packages.x86_64" <<'EOP'
base
linux
linux-headers
linux-firmware
nvidia-open
nvidia-utils
nvidia-settings
mesa
vulkan-radeon
cups
archcraft-sway-free
noto-fonts-cjk
steam
archcraft-openbox
archcraft-bspwm
archcraft-installer
polybar
rofi
alacritty
kitty
xfce4-terminal
mpd
archcraft-music
geany
geany-plugins
archcraft-config-geany
meld
catfish
viewnior
atril
galculator
xarchiver
yad
pastel
xcolor
xmlstarlet
trash-cli
ranger
ueberzug
highlight
mc
archcraft-vim
archcraft-scripts
archcraft-neofetch
archcraft-about
archcraft-artworks
archcraft-funscripts
archcraft-help
archcraft-welcome
archcraft-omz
archcraft-skeleton
xfce4-power-manager
xfce4-settings
xsettingsd
xfce-polkit
gtk-nocsd-git
perl-linux-desktopfiles
thunar-shares-plugin
thunar-media-tags-plugin
thunar
thunar-archive-plugin
thunar-volman
tumbler
gufw
ufw
pavucontrol
blueman
vim
gvfs
gvfs-mtp
gvfs-smb
gvfs-afc
gvfs-gphoto2
qt5ct
qt6ct
kvantum
kvantum-qt5
archcraft-config-qt
firefox
htop
nethogs
ncdu
powertop
screen
unarchiver
lrzip
lzop
bolt
dmraid
mmc-utils
ndisc6
usb_modeswitch
usbmuxd
sdparm
sg3_utils
lsscsi
inetutils
wireless_tools
libusb-compat
simplescreenrecorder
btrfs-assistant
EOP

# pacman.conf: [options] sem Architecture (a sed insere), com DownloadUser
# (a sed remove) e #ParallelDownloads (a sed reescreve) — [archcraft] com
# SigLevel TrustAll (vira Never)
cat > "$P/pacman.conf" <<'EOP'
[options]
HoldPkg = pacman glibc
DownloadUser = alpm
#ParallelDownloads = 5
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[archcraft]
SigLevel = Optional TrustAll
Server = https://packages.archcraft.io/$arch
EOP

# mkarchcraftiso com o pacstrap -i que o overlay remove
cat > "$P/mkarchcraftiso" <<'EOP'
#!/usr/bin/env bash
pacstrap -C "${work_dir}/${buildmode}.pacman.conf" -i -c -G -M "${airootfs_dir}"
EOP

# customize upstream com o bloco sway EXATO que a guarda [8.5] protege.
# v1.1 build #51: inclui VERBATIM também o bloco "Fix Initrd Generation
# in Installed System" — o cat > /etc/mkinitcpio.d/linux.preset que
# RESSUCITA o preset órfão dentro do chroot (o [6.3] do overlay só apaga
# o arquivo estático do profile; este cat roda DEPOIS, no customize).
# O E6 do fragmento Elite (anexado ao final) precisa matá-lo de novo.
cat > "$P/airootfs/root/customize_airootfs.sh" <<'EOP'
#!/usr/bin/env bash
set -e -u
cat > "/etc/mkinitcpio.d/linux.preset" <<- _EOF_
        # mkinitcpio preset file for the 'linux' package

        ALL_kver="/boot/vmlinuz-linux"
        ALL_config="/etc/mkinitcpio.conf"

        PRESETS=('default' 'fallback')

        #default_config="/etc/mkinitcpio.conf"
        default_image="/boot/initramfs-linux.img"
        #default_options=""

        #fallback_config="/etc/mkinitcpio.conf"
        fallback_image="/boot/initramfs-linux-fallback.img"
        fallback_options="-S autodetect"
_EOF_
rm -rf /etc/mkinitcpio.conf.d
rm -rf /etc/mkinitcpio.d/linux-nvidia.preset
sed -i -e '/## Welcome-App-Run-Once/Q' /etc/skel/.config/sway/scripts/startup
cat >> "/etc/skel/.config/sway/scripts/startup" <<- EOL
echo wayland
EOL
sed -i -e '/## Welcome-App-Run-Once/Q' /etc/skel/.config/openbox/autostart
cat >> "/etc/skel/.config/openbox/autostart" <<- EOL
echo openbox
EOL
sed -i -e '/## Welcome-App-Run-Once/Q' /etc/skel/.config/bspwm/bspwmrc
cat >> "/etc/skel/.config/bspwm/bspwmrc" <<- EOL
echo bspwm
EOL
ln -s /usr/share/archcraft/scripts/* /usr/local/bin/
chmod +x /etc/skel/.screenlayout/my-layout.sh
EOP

# ── /etc/environment upstream VERBATIM (conferido no repo oficial):
#    é o alvo dos seds do E12 (v1.1: helix/brave/foot; o restante preservado)
cat > "$P/airootfs/etc/environment" <<'EOP'
#
# This file is parsed by pam_env module
#
# Syntax: simple "KEY=VAL" pairs on separate lines
#
QT_QPA_PLATFORMTHEME=qt6ct
EDITOR=nano
BROWSER=firefox
TERMINAL=alacritty
EOP

# ── presets/conf.d do kernel stock upstream VERBATIM (conferidos no repo
#    oficial — build #48): são ARQUIVOS ESTÁTICOS do profile (não vêm de
#    pacote). O overlay [6.3] v1.1 os DELETA (kernel único BORE); sem isso
#    o hook mkinitcpio do build morre em 'vmlinuz-linux must be readable'
#    e o órfão vai pro squashfs → sistema instalado (gate verify-install).
mkdir -p "$P"/airootfs/etc/mkinitcpio.d "$P"/airootfs/etc/mkinitcpio.conf.d
cat > "$P/airootfs/etc/mkinitcpio.d/linux.preset" <<'EOP'
# mkinitcpio preset file for the 'linux' package on archiso

PRESETS=('archiso')

ALL_kver='/boot/vmlinuz-linux'
archiso_config='/etc/mkinitcpio.conf.d/archiso.conf'

archiso_image="/boot/initramfs-linux.img"
EOP
cat > "$P/airootfs/etc/mkinitcpio.d/linux-nvidia.preset" <<'EOP'
# mkinitcpio preset file for the 'linux' package on archiso (nvidia)

PRESETS=('nvidia')

ALL_kver='/boot/vmlinuz-linux'
nvidia_config='/etc/mkinitcpio.conf.d/archiso-nvidia.conf'

nvidia_image="/boot/initramfs-linux-nvidia.img"
EOP
cat > "$P/airootfs/etc/mkinitcpio.conf.d/archiso.conf" <<'EOP'
HOOKS=(base udev microcode plymouth modconf kms memdisk archiso archiso_loop_mnt block filesystems keyboard)
COMPRESSION="xz"
COMPRESSION_OPTIONS=(-9e)
EOP
cat > "$P/airootfs/etc/mkinitcpio.conf.d/archiso-nvidia.conf" <<'EOP'
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
HOOKS=(base udev microcode plymouth modconf memdisk archiso archiso_loop_mnt block filesystems keyboard)
COMPRESSION="xz"
COMPRESSION_OPTIONS=(-9e)
EOP

# ── Calamares fixture (v1.0.3/v1.1): arquivos REAIS do calamares-config /
# archcraft-install-scripts — o 40-integration executa o bloco E5 do
# fragmento contra estes arquivos e confere a cirurgia labwc + E5a/E5b ──
cat > "$P/airootfs/etc/calamares/modules/packagechooser.conf" <<'EOP'
---
mode: required
method: legacy
labels:
    step: "Desktop"
default: everything
items:
    - id: openbox
      name: "Openbox"
      description: "Only Install Openbox Window Manager."
      screenshot: "/etc/calamares/branding/archcraft/desktop/openbox.png"
    - id: bspwm
      name: "Bspwm"
      description: "Only Install Bspwm Window Manager."
      screenshot: "/etc/calamares/branding/archcraft/desktop/bspwm.png"
    - id: sway
      name: "Sway"
      description: "Only Install Sway Wayland Compositor."
      screenshot: "/etc/calamares/branding/archcraft/desktop/sway.png"
    - id: everything
      name: "Everything"
      description: "Install Everything (All Window Managers & Wayland Compositors)."
      screenshot: "/etc/calamares/branding/archcraft/desktop/everything.png"
EOP

cat > "$P/airootfs/etc/calamares/modules/contextualprocess_autologin.conf" <<'EOP'
---
dontChroot: false
timeout: 9999
packagechooser_packagechooser:
    openbox:
        - echo "Setting openbox as session for autologin..."
        - /usr/bin/chrooted_autologin.sh --openbox
    bspwm:
        - echo "Setting bspwm as session for autologin..."
        - /usr/bin/chrooted_autologin.sh --bspwm
    sway:
        - echo "Setting sway as session for autologin..."
        - /usr/bin/chrooted_autologin.sh --sway
    everything:
        - echo "Setting openbox as session for autologin..."
        - /usr/bin/chrooted_autologin.sh --everything
EOP

cat > "$P/airootfs/etc/calamares/modules/partition.conf" <<'EOP'
---
defaultFileSystemType:  "ext4"
EOP

# unpackfs.conf upstream (v1.1: a entrada vmlinuz-linux stock que o E5a
# substitui no lugar — kernel único BORE; initramfs/fallback seguem intactos)
cat > "$P/airootfs/etc/calamares/modules/unpackfs.conf" <<'EOP'
---
unpack:
    -   source: "/run/archiso/bootmnt/arch/boot/x86_64/initramfs-linux.img"
        sourcefs: "file"
        destination: "/boot/initramfs-linux.img"

    -   source: "/run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux"
        sourcefs: "file"
        destination: "/boot/vmlinuz-linux"

    -   source: "/run/archiso/bootmnt/arch/boot/x86_64/initramfs-linux-fallback.img"
        sourcefs: "file"
        destination: "/boot/initramfs-linux-fallback.img"
EOP

# settings.conf upstream (v1.1: o E5b insere initcpio@elite depois do
# shellprocess_btrfs e REMOVE o módulo stock '  - initcpio' — kernel único)
cat > "$P/airootfs/etc/calamares/settings.conf" <<'EOP'
---
modules-search: [ local ]

sequence:
  - show:
      - welcome
      - locale
      - keyboard
      - partition
      - users
      - summary

  - exec:
      - partition
      - mount
      - unpackfs
      - machineid
      - fstab
      - locale
      - keyboard
      - localecfg
      - users
      - displaymanager
      - networkcfg
      - hwclock
      - services-systemd
      - id:       shellprocess_btrfs
        module:   shellprocess
        config:   shellprocess_btrfs.conf
  - initcpio
      - grubcfg
      - bootloader
EOP

cat > "$P/airootfs/usr/bin/chrooted_autologin.sh" <<'EOP'
#!/bin/bash
DM_FILE='/etc/sddm.conf'
enable_autologin() {
        _session_name="$1"
        if [[ `cat $DM_FILE | grep 'Autologin'` ]]; then
                sed -i -e "/\[Autologin\]/{ n; n; s/Session=.*/Session=$_session_name/g }" "$DM_FILE"
        fi
}
if [[ "$1" == '--openbox' ]]; then
        enable_autologin 'openbox'
elif [[ "$1" == '--bspwm' ]]; then
        enable_autologin 'bspwm'
elif [[ "$1" == '--sway' ]]; then
        enable_autologin 'sway'
elif [[ "$1" == '--everything' ]]; then
        enable_autologin 'openbox'
fi
EOP

# arquivos airootfs pré-existentes (o overlay soma, nunca apaga)
echo '#!/bin/sh' > "$P/airootfs/usr/local/bin/hello-upstream"

# wants: cups/vmtoolsd (debloatados → sumir) + sshd (sobrevivente)
ln -s /usr/lib/systemd/system/cups.service     "$P/airootfs/etc/systemd/system/multi-user.target.wants/cups.service"
ln -s /usr/lib/systemd/system/vmtoolsd.service "$P/airootfs/etc/systemd/system/multi-user.target.wants/vmtoolsd.service"
ln -s /usr/lib/systemd/system/sshd.service     "$P/airootfs/etc/systemd/system/multi-user.target.wants/sshd.service"

# ── efiboot (systemd-boot): 4 entradas VERBATIM upstream (options completas
#    com copytoram=n/nvme_load=yes/lsm — os seds da v1.1 casam nelas) ──────
cat > "$P/efiboot/loader/entries/01-archiso-linux.conf" <<'EOP'
title   Boot Archcraft (%ARCH%, UEFI, Default)
sort-key 01
linux    /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
initrd   /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
options  archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
EOP
cat > "$P/efiboot/loader/entries/02-archiso-linux-open-source.conf" <<'EOP'
title   Boot Archcraft (%ARCH%, UEFI, OpenSource)
sort-key 02
linux    /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
initrd   /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
options  archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n module_blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nouveau.modeset=1 radeon.modeset=1 i915.modeset=1 nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
EOP
cat > "$P/efiboot/loader/entries/03-archiso-linux-nvidia.conf" <<'EOP'
title   Boot Archcraft (%ARCH%, UEFI, Nvidia)
sort-key 03
linux    /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
initrd   /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux-nvidia.img
options  archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n nvidia nvidia-drm.modeset=1 nouveau.modeset=0 module_blacklist=nouveau radeon.modeset=1 i915.modeset=1 nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
EOP
cat > "$P/efiboot/loader/entries/04-archiso-linux-nomodeset.conf" <<'EOP'
title   Boot Archcraft (%ARCH%, UEFI, Nomodeset)
sort-key 04
linux    /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
initrd   /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
options  archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n nomodeset module_blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nouveau.modeset=0 radeon.modeset=0 i915.modeset=0 nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
EOP

# ── syslinux (BIOS): VERBATIM upstream — 4 LABELs (arch/archfree/
#    archnonfree/archnomodeset) com TEXT HELP e APPEND completos ──────────
cat > "$P/syslinux/archiso_sys-linux.cfg" <<'EOP'
DEFAULT archsys
ONTIMEOUT archsys

LABEL arch
TEXT HELP
Boot Archcraft install medium on BIOS.
It allows you to install Archcraft or perform system maintenance.
ENDTEXT
MENU LABEL Boot Archcraft (%ARCH%, BIOS, Default)
LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf

# Open Source
LABEL archfree
TEXT HELP
Boot Archcraft install medium on BIOS with open source drivers.
It allows you to install Archcraft or perform system maintenance.
ENDTEXT
MENU LABEL Boot Archcraft (%ARCH%, BIOS, OpenSource)
LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n module_blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nouveau.modeset=1 radeon.modeset=1 i915.modeset=1 nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf

# NVIDIA Proprietary
LABEL archnonfree
TEXT HELP
Boot Archcraft install medium on BIOS with proprietary nvidia drivers.
It allows you to install Archcraft or perform system maintenance.
ENDTEXT
MENU LABEL Boot Archcraft (%ARCH%, BIOS, Nvidia)
LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux-nvidia.img
APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n nvidia nvidia-drm.modeset=1 nouveau.modeset=0 module_blacklist=nouveau radeon.modeset=1 i915.modeset=1 nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf

# Nomodeset
LABEL archnomodeset
TEXT HELP
Boot Archcraft install medium on BIOS with nomodeset.
It allows you to install Archcraft or perform system maintenance.
ENDTEXT
MENU LABEL Boot Archcraft (%ARCH%, BIOS, Nomodeset)
LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n nomodeset module_blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nouveau.modeset=0 radeon.modeset=0 i915.modeset=0 nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
EOP

# ── grub/loopback: FIEL ao upstream (4 entradas com --id, cmdline inteira,
#    set gfxpayload=keep; extras memtest/shutdown p/ provar que sobrevivem).
#    O loopback difere do grub.cfg pela forma img_dev/img_loop (real) ─────
cat > "$P/grub/grub.cfg" <<'EOP'
default=archcraft
timeout=10
timeout_style=menu

menuentry "Boot Archcraft (%ARCH%, ${archiso_platform}, Default)" --class archcraft --class arch --class gnu-linux --class gnu --class os --id 'archcraft' {
    set gfxpayload=keep
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}

menuentry "Boot Archcraft (%ARCH%, ${archiso_platform}, OpenSource)" --class archcraft --class arch --class gnu-linux --class gnu --class os --id 'archcraftos' {
    set gfxpayload=keep
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n module_blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nouveau.modeset=1 radeon.modeset=1 i915.modeset=1 nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}

menuentry "Boot Archcraft (%ARCH%, ${archiso_platform}, Nvidia)" --class archcraft --class arch --class gnu-linux --class gnu --class os --id 'archcraftpn' {
    set gfxpayload=keep
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n nvidia nvidia-drm.modeset=1 nouveau.modeset=0 module_blacklist=nouveau radeon.modeset=1 i915.modeset=1 nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux-nvidia.img
}

menuentry "Boot Archcraft (%ARCH%, ${archiso_platform}, Nomodeset)" --class archcraft --class arch --class gnu-linux --class gnu --class os --id 'archcraftnm' {
    set gfxpayload=keep
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n nomodeset module_blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nouveau.modeset=0 radeon.modeset=0 i915.modeset=0 nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}

menuentry 'Run Memtest86+ (RAM test)' --class memtest86 --class memtest --class gnu --class tool {
    set gfxpayload=800x600,1024x768
    linux /boot/memtest86+/memtest.efi
}

menuentry 'System shutdown' --class shutdown --class poweroff {
    halt
}
EOP

cat > "$P/grub/loopback.cfg" <<'EOP'
# https://www.supergrubdisk.org/wiki/Loopback.cfg
search --no-floppy --set=archiso_img_dev --file "${iso_path}"
probe --set archiso_img_dev_uuid --fs-uuid "${archiso_img_dev}"

menuentry "Boot Archcraft (%ARCH%, ${archiso_platform}, Default)" --class archcraft --class arch --class gnu-linux --class gnu --class os --id 'archcraft' {
    set gfxpayload=keep
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% img_dev=UUID=${archiso_img_dev_uuid} img_loop="${iso_path}" quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}

menuentry "Boot Archcraft (%ARCH%, ${archiso_platform}, OpenSource)" --class archcraft --class arch --class gnu-linux --class gnu --class os --id 'archcraftos' {
    set gfxpayload=keep
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% img_dev=UUID=${archiso_img_dev_uuid} img_loop="${iso_path}" quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n module_blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nouveau.modeset=1 radeon.modeset=1 i915.modeset=1 nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}

menuentry "Boot Archcraft (%ARCH%, ${archiso_platform}, Nvidia)" --class archcraft --class arch --class gnu-linux --class gnu --class os --id 'archcraftpn' {
    set gfxpayload=keep
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% img_dev=UUID=${archiso_img_dev_uuid} img_loop="${iso_path}" quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n nvidia nvidia-drm.modeset=1 nouveau.modeset=0 module_blacklist=nouveau radeon.modeset=1 i915.modeset=1 nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux-nvidia.img
}

menuentry "Boot Archcraft (%ARCH%, ${archiso_platform}, Nomodeset)" --class archcraft --class arch --class gnu-linux --class gnu --class os --id 'archcraftnm' {
    set gfxpayload=keep
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% img_dev=UUID=${archiso_img_dev_uuid} img_loop="${iso_path}" quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=n nomodeset module_blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm nouveau.modeset=0 radeon.modeset=0 i915.modeset=0 nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}

menuentry 'System shutdown' --class shutdown --class poweroff {
    halt
}
EOP

git -C "$UP" init -q
git -C "$UP" add -A
git -C "$UP" commit -qm "fixture upstream archcraft"
EOF

# ── 4. insteadOf: o apply-overlay clona o fixture SEM saber ─────────
(
  export HOME="$HOME_FIX"
  git config --global url."$UP".insteadOf "https://github.com/archcraft-os/archcraft.git"
)
echo "setup: mocks/extract/upstream prontos em $WORK"
