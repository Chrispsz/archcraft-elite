#!/usr/bin/env bash
# =====================================================================
#  .ci/build.sh — roda DENTRO do container Arch Linux PRIVILEGIADO
#  (o pacstrap precisa montar /proc & cia. no chroot — containers
#  comuns do GitHub Actions não têm permissão de mount).
#
#  Entrada: /work = checkout do repo (montado), /mnt = disco grande
#  Saída:   /work/out/archcraft-elite-<data>-x86_64.iso + sha256sums
# =====================================================================
set -euo pipefail

say() { echo -e "\033[1;32m==>\033[0m $1"; }

say "Disco disponível:"
df -h / /mnt || true

say "Preparando container (archiso + deps do mkarchcraftiso)"
sed -i 's/^#ParallelDownloads/ParallelDownloads/; s/^#Color/Color/' /etc/pacman.conf
pacman -Syu --noconfirm --needed \
    git rsync curl archiso xorriso mtools dosfstools \
    e2fsprogs squashfs-tools openssl arch-install-scripts

say "Importando chave CachyOS (ambiente de build)"
# a imagem archlinux não traz chave secreta no keyring — init primeiro
pacman-key --init
if ! pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com 2>/dev/null \
   && ! pacman-key --recv-keys F3B607488DB35A47 2>/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDs/master/cachyos-keyring/cachyos.gpg \
        | pacman-key --add -
fi
pacman-key --lsign-key F3B607488DB35A47

say "Aplicando overlay Elite sobre o profile Archcraft"
cd /work
bash scripts/apply-overlay.sh

say "Construindo ISO (mkarchcraftiso — fork oficial do Archcraft)"
mkdir -p /mnt/iso-work /work/out
cd elite-build/profile
./mkarchcraftiso -v -w /mnt/iso-work -o /work/out .

say "Checksums + relatório de tamanho"
cd /work/out
sha256sum -- * > sha256sums.txt
cat sha256sums.txt
ls -lh --si
