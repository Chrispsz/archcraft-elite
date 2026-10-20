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

mk "$WORK/mocks/dmidecode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' \
  'Size: 16 GB' 'Size: 16 GB' \
  'Configured Clock Speed: 3200' 'Configured Clock Speed: 3200'
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
  echo 'DRY=0; YES=0'
  # funções de 1 linha (say/warn/err/run) e blocos multi-linha (closes em ^})
  grep -E '^(say|warn|err|run)\(\)' "$T"
  sed -n '/^gpu_cleanup_foreign()/,/^}$/p' "$T"
  sed -n '/^detect_hw()/,/^}$/p'      "$T"
  cat <<'EOF'
# gatilhos de teste (controlados por env)
if [[ -n "${CU_VENDOR:-}" ]]; then gpu_cleanup_foreign "$CU_VENDOR"; exit 0; fi
if [[ -n "${DETECT_ONLY:-}" ]]; then detect_hw; printf '%s %s\n' "$VENDOR" "$GEN"; exit 0; fi
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
mkdir -p "$P"/{airootfs/root,airootfs/usr/local/bin,airootfs/etc/systemd/system/multi-user.target.wants,efiboot/loader/entries,syslinux,grub}

# profiledef (a sed do apply-overlay rebatiza a ISO)
cat > "$P/profiledef.sh" <<'EOP'
#!/usr/bin/env bash
iso_name="archcraft"
iso_application="Archcraft Live/Installation/Rescue CD"
EOP

# packages: itens do packages.remove que EXISTEM upstream (cups, sway-free,
# cjk, linux-firmware) + itens do packages.add já presentes (vulkan-radeon)
# para provar dedupe — SEM grupos (xorg etc.) para manter o teste offline
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
