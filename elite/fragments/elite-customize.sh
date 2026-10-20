#!/usr/bin/env bash
# (shebang pro shellcheck; ao ser anexado ao customize_airootfs.sh isto vira
#  apenas um comentário no meio do arquivo — sem efeito em runtime)
# shellcheck shell=bash disable=SC2016
#
# ════════════════════════════════════════════════════════════════════
# ── ELITE v2 ─────────────────────────────────────────────────────────
#  Roda DENTRO do airootfs no fim do customize_airootfs.sh do Archcraft
#  (fase de BUILD). Prepara o CachyOS p/ a sessão live E p/ o sistema
#  instalado (o Calamares/unpackfs copia este root inteiro p/ o disco),
#  e faz a cirurgia no Calamares p/ o kernel BORE também bootar no
#  sistema instalado (unpackfs + initcpio@elite).
# ════════════════════════════════════════════════════════════════════

ELITE_KEY="F3B607488DB35A47"
ELITE_MIRROR="https://us.cachyos.org"
ELITE_MIRROR2="https://cdn77.cachyos.org"
ELITE_KEYRING_PINNED="cachyos-keyring-20240331-1-any.pkg.tar.zst"
ELITE_V3ML_PINNED="cachyos-v3-mirrorlist-27-1-any.pkg.tar.zst"

## [E0] DNS no chroot (o E2 usa curl; o arch-chroot normalmente copia o
##      resolv.conf, mas o symlink stub do systemd-resolved pode estar morto)
if [[ ! -e /etc/resolv.conf ]]; then
    rm -f /etc/resolv.conf
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
fi

## [E1] Chave CachyOS no keyring do airootfs (vale p/ live E p/ instalado:
##      o /etc/pacman.d/gnupg inteiro é copiado pelo unpackfs)
if ! pacman-key --list-keys "$ELITE_KEY" >/dev/null 2>&1; then
    pacman-key --recv-keys "$ELITE_KEY" --keyserver keyserver.ubuntu.com \
        || pacman-key --recv-keys "$ELITE_KEY" || true
    pacman-key --lsign-key "$ELITE_KEY" || true
fi

## [E2] keyring + mirrorlist v3 oficiais (pacman -U — SEM o pacman forkado)
elite_latest() {
    curl -fsSL --max-time 30 "${ELITE_MIRROR}/repo/x86_64/cachyos/" 2>/dev/null \
        | grep -oE "$1-[0-9][^\"]*\.pkg\.tar\.zst" | sort -Vu | tail -1 || true
}
ELITE_KEYRING_PKG="$(elite_latest cachyos-keyring)"
[[ -n "$ELITE_KEYRING_PKG" ]] || ELITE_KEYRING_PKG="$ELITE_KEYRING_PINNED"
ELITE_V3ML_PKG="$(elite_latest cachyos-v3-mirrorlist)"
[[ -n "$ELITE_V3ML_PKG" ]] || ELITE_V3ML_PKG="$ELITE_V3ML_PINNED"
if ! pacman -U --noconfirm \
        "${ELITE_MIRROR}/repo/x86_64/cachyos/${ELITE_KEYRING_PKG}" \
        "${ELITE_MIRROR}/repo/x86_64/cachyos/${ELITE_V3ML_PKG}"; then
    ## Fallback: escreve o mirrorlist na mão (a chave já caiu via E1)
    printf 'Server = %s/repo/x86_64_v3/$repo\nServer = %s/repo/x86_64_v3/$repo\n' \
        "$ELITE_MIRROR2" "$ELITE_MIRROR" > /etc/pacman.d/cachyos-v3-mirrorlist
fi

## [E3] pacman.conf do SISTEMA: reescrito canônico e limpo (o customize do
##      Archcraft duplica [core]/[extra] no fim; aqui fica sem duplicatas).
##      Ordem: archcraft > cachyos(v2) > cachyos-v3 trio > core/extra/multilib
ELITE_PC="/etc/pacman.conf"
awk '/^\[/ {exit} {print}' "$ELITE_PC" > /tmp/elite-pc-options
{
    cat /tmp/elite-pc-options
    cat <<'EOL'

[archcraft]
# packages.archcraft.io é UNSIGNED (nenhum .sig no repo): Never = zero
# sondas db.sig/pacote.sig (curl 404 no primeiro -Sy do sistema instalado);
# mesma segurança que TrustAll para um repo sem assinaturas.
SigLevel = Never
Include = /etc/pacman.d/archcraft-mirrorlist

# >>> ELITE: CachyOS — wiki.cachyos.org/features/optimized_repos
# Ordem: trio v3 ANTES do baseline (kernel linux-cachyos-bore existe nos dois:
# baseline 7.2.7 x86_64 vs v3 7.2.11 x86-64-v3 — pacman prefere o primeiro repo)
# v3: kernels, nvidia-open-dkms, gamescope
[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

# v3: rebuilds do [core]
[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

# v3: rebuilds do [extra]
[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

# v2 (baseline): keyring, cachyos-settings, dmemcg-booster, rules (exclusivos)
[cachyos]
Server = https://cdn77.cachyos.org/repo/x86_64/cachyos
Server = https://us.cachyos.org/repo/x86_64/cachyos
# <<< ELITE

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOL
} > "$ELITE_PC"
rm -f /tmp/elite-pc-options

## [E3b] Arquitetura: pacotes cachyos-v3 são arch "x86_64_v3" — o conf
##       do sistema precisa aceitar as duas (senão 'pacman -Syu' quebra)
if ! grep -qE '^Architecture = .*\bx86_64_v3\b' "$ELITE_PC"; then
    if grep -qE '^Architecture = ' "$ELITE_PC"; then
        sed -i -E 's|^Architecture = .*$|Architecture = x86_64 x86_64_v3|' "$ELITE_PC"
    else
        sed -i '/^\[options\]/a Architecture = x86_64 x86_64_v3' "$ELITE_PC"
    fi
fi

## [E4] Refresh das DBs (valida que os 6 repos resolvem dentro do chroot)
pacman -Sy --noconfirm || true

## [E5] Cirurgia no Calamares (efeito na INSTALAÇÃO, no sistema alvo):
##   a) unpackfs copia também o vmlinuz do BORE p/ /boot do instalado
##      (upstream só copia o vmlinuz-linux — sem isto o BORE nunca bootaria)
##   b) instância initcpio@elite gera o initramfs do BORE no alvo
##   c) packagechooser sem a opção Sway (pacote removido da ISO Elite)
##   d) btrfs como filesystem default (timeshift + grub-btrfs = rollback real)
CC="/etc/calamares"
if [[ -d "$CC" ]]; then
    # a) unpackfs
    if [[ -f "$CC/modules/unpackfs.conf" ]] && ! grep -q 'vmlinuz-linux-cachyos-bore' "$CC/modules/unpackfs.conf"; then
        printf '%s\n' \
            '    -   source: "/run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux-cachyos-bore"' \
            '        sourcefs: "file"' \
            '        destination: "/boot/vmlinuz-linux-cachyos-bore"' \
            >> "$CC/modules/unpackfs.conf"
    fi
    # b) initcpio@elite
    if [[ -f "$CC/settings.conf" ]] && ! grep -q 'initcpio@elite' "$CC/settings.conf"; then
        sed -i '/config:   shellprocess_btrfs.conf/s/$/\n- id:       elite\n  module:   initcpio\n  config:   initcpio_elite.conf/' "$CC/settings.conf"
        sed -i '/^  - initcpio$/s/$/\n  - initcpio@elite/' "$CC/settings.conf"
        printf '%s\n' '---' 'kernel: linux-cachyos-bore' 'be_unsafe: false' \
            > "$CC/modules/initcpio_elite.conf"
    fi
    # c) packagechooser: remove o item Sway
    if [[ -f "$CC/modules/packagechooser.conf" ]]; then
        sed -i '/- id: sway/,/sway\.png/d' "$CC/modules/packagechooser.conf"
    fi
    # d) btrfs default
    if [[ -f "$CC/modules/partition.conf" ]]; then
        sed -i 's|defaultFileSystemType: *"ext4"|defaultFileSystemType:  "btrfs"|' "$CC/modules/partition.conf"
    fi
fi

## [E6] Preset do BORE p/ o sistema INSTALADO (default/fallback). No live ele
##      nasceu com hooks archiso (overlay); o initcpio@elite do E5b usa ESTE
##      preset no alvo — espelha o que o upstream faz com o linux.preset.
cat > /etc/mkinitcpio.d/linux-cachyos-bore.preset <<'EOL'
# mkinitcpio preset file for the 'linux-cachyos-bore' package (Elite)
ALL_kver="/boot/vmlinuz-linux-cachyos-bore"
ALL_config="/etc/mkinitcpio.conf"

PRESETS=('default' 'fallback')

default_image="/boot/initramfs-linux-cachyos-bore.img"

fallback_image="/boot/initramfs-linux-cachyos-bore-fallback.img"
fallback_options="-S autodetect"
EOL

## [E7] post-install do Archcraft: tira da lista de serviços habilitados
##      os que a Elite debloatou (cups via cups-filters→avahi) — evita
##      erro de "unit inexistente" no log da instalação
ELITE_PIS="/usr/bin/chrooted_post_install.sh"
if [[ -f "$ELITE_PIS" ]]; then
    sed -i -e "s/'cups.service'//" -e "s/'avahi-daemon.service'//" "$ELITE_PIS"
fi

## [E8] Remove o repo local [elite-local] da ISO (só é necessário durante
##      o pacstrap; os pacotes instalados ficam, o repo não)
rm -rf /var/cache/elite-local
