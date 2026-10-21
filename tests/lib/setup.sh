# shellcheck shell=bash
# tests/lib/setup.sh — montagem da mesa do quebra-cabeça (sourced 1×, idempotente)
# Produz: $WORK/mocks (pacman/lspci/nvidia-smi/systemctl/…), $WORK/extract.sh
# (funções reais extraídas do elite-tune) e $WORK/upstream-src (clone-fixture
# do Archcraft) + registro git insteadOf sob HOME isolado — o apply-overlay
# roda SEM rede e SEM tocar na config global do usuário.

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

: > "$STATE/installed.txt"

# ── 2. extract.sh — funções REAIS do elite-tune (fidelidade, não cópia) ──
T="$REPO/elite/airootfs/usr/local/bin/elite-tune"
{
  echo '#!/usr/bin/env bash'
  echo "G='[1;32m'; Y='[1;33m'; R='[1;31m'; B='[1m'; N='[0m'"
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

# packages: itens do packages.remove que EXISTEM upstream (cups, sway-free,
# cjk, linux-firmware) + itens do packages.add já presentes (vulkan-radeon)
# para provar dedupe — SEM grupos (xorg etc.) para manter o teste offline.
# v1.0.3: alvos da sessão única labwc (openbox/bspwm/satélites/terminais/
# música) também no fixture p/ provar o debloat + comentário inline.
# v1.0.3 CURADORIA: alvos do "brabos 2026" (apps simples/nicho/legado +
# os que FICAM e são assertados: thunar/gvfs/xdotool/qt6ct/firefox/
# pavucontrol) — mesmos nomes do packages.x86_64 real do stock.
# shellcheck disable=SC2016
cat > "$P/packages.x86_64" <<'EOP'
base
linux
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
archcraft-ranger
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
pavucontrol
gvfs
gvfs-mtp
gvfs-smb
gvfs-afc
gvfs-gphoto2
xdotool
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

# customize upstream com o bloco sway EXATO que a guarda [8.5] protege
cat > "$P/airootfs/root/customize_airootfs.sh" <<'EOP'
#!/usr/bin/env bash
set -e -u
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

# ── Calamares fixture (v1.0.3): arquivos REAIS do calamares-config /
# archcraft-install-scripts — o 40-integration executa o bloco E5 do
# fragmento contra estes arquivos e confere a cirurgia labwc ──────────
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

# efiboot: 01 (default → BORE) e 03 (NVIDIA → fica no kernel stock)
cat > "$P/efiboot/loader/entries/01-archiso-linux.conf" <<'EOP'
title   Boot Archcraft (%ARCH%, UEFI, Default)
linux   /arch/boot/x86_64/vmlinuz-linux
initrd  /arch/boot/x86_64/initramfs-linux.img
EOP
cat > "$P/efiboot/loader/entries/02-archiso-opensource.conf" <<'EOP'
title   Boot Archcraft (%ARCH%, UEFI, OpenSource)
linux   /arch/boot/x86_64/vmlinuz-linux
initrd  /arch/boot/x86_64/initramfs-linux.img
EOP
cat > "$P/efiboot/loader/entries/03-archiso-nvidia.conf" <<'EOP'
title   Boot Archcraft with the NVIDIA proprietary driver
linux   /arch/boot/x86_64/vmlinuz-linux
initrd  /arch/boot/x86_64/initramfs-linux.img
EOP

# syslinux (BIOS): bloco default + bloco archnonfree (intocado)
cat > "$P/syslinux/archiso_sys-linux.cfg" <<'EOP'
DEFAULT archsys
LABEL arch
  MENU LABEL Boot Archcraft (%ARCH%, BIOS, Default)
  LINUX /arch/boot/x86_64/vmlinuz-linux
  INITRD /arch/boot/x86_64/initramfs-linux.img
LABEL archnonfree
  MENU LABEL Boot Archcraft (NVIDIA)
  LINUX /arch/boot/x86_64/vmlinuz-linux
  INITRD /arch/boot/x86_64/initramfs-linux.img
EOP

# grub: espelho FIEL do upstream (4 entradas, ids aspasados, initramfs-nvidia) —
# default/opensource/nomodeset → BORE; archcraftpn (NVIDIA) → kernel stock
upstream_grub() { cat <<'EOP'
menuentry "Boot Archcraft (%ARCH%, ${archiso_platform}, Default)" --class archcraft --class arch --class gnu-linux --class gnu --class os --id 'archcraft' {
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% quiet splash
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}
menuentry "Boot Archcraft (%ARCH%, ${archiso_platform}, OpenSource)" --class archcraft --class arch --class gnu-linux --class gnu --class os --id 'archcraftos' {
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% module_blacklist=nvidia
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}
menuentry "Boot Archcraft (%ARCH%, ${archiso_platform}, Nvidia)" --class archcraft --class arch --class gnu-linux --class gnu --class os --id 'archcraftpn' {
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% nvidia nvidia-drm.modeset=1 nouveau.modeset=0
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux-nvidia.img
}
menuentry "Boot Archcraft (%ARCH%, ${archiso_platform}, Nomodeset)" --class archcraft --class arch --class gnu-linux --class gnu --class os --id 'archcraftnm' {
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% nomodeset
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}
EOP
}
upstream_grub > "$P/grub/grub.cfg"
upstream_grub > "$P/grub/loopback.cfg"

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
