
# ════════════════════════════════════════════════════════════════════
# ── ELITE ────────────────────────────────────────────────────────────
# Roda DENTRO do airootfs durante o build (anexado ao customize do
# Archcraft). Prepara o CachyOS para a sessão live E para o sistema
# instalado (o Calamares/unpackfs copia este root inteiro para o disco).
# Padrão validado do archcraft-cachyos-elite (01-system-core.sh).
# ════════════════════════════════════════════════════════════════════

ELITE_KEY="F3B607488DB35A47"
ELITE_MIRROR="https://mirror.cachyos.org"
ELITE_KEYRING_PINNED="cachyos-keyring-20240331-1-any.pkg.tar.zst"
ELITE_V3ML_PINNED="cachyos-v3-mirrorlist-27-1-any.pkg.tar.zst"

## [E1] Chave CachyOS no keyring do airootfs (live + instalado)
if ! pacman-key --list-keys "$ELITE_KEY" >/dev/null 2>&1; then
    pacman-key --recv-keys "$ELITE_KEY" --keyserver keyserver.ubuntu.com \
        || pacman-key --recv-keys "$ELITE_KEY"
    pacman-key --lsign-key "$ELITE_KEY"
fi

## [E2] keyring + mirrorlist v3 oficiais (pacman -U — SEM o pacman forkado)
elite_latest() {
    curl -fsSL --max-time 30 "${ELITE_MIRROR}/repo/x86_64/cachyos/" 2>/dev/null \
        | grep -oE "$1-[0-9][^\"]*\.pkg\.tar\.zst" | sort -Vu | tail -1 || true
}
ELITE_KEYRING_PKG="$(elite_latest cachyos-keyring)"; [[ -n "$ELITE_KEYRING_PKG" ]] || ELITE_KEYRING_PKG="$ELITE_KEYRING_PINNED"
ELITE_V3ML_PKG="$(elite_latest cachyos-v3-mirrorlist)"; [[ -n "$ELITE_V3ML_PKG" ]] || ELITE_V3ML_PKG="$ELITE_V3ML_PINNED"
pacman -U --noconfirm \
    "${ELITE_MIRROR}/repo/x86_64/cachyos/${ELITE_KEYRING_PKG}" \
    "${ELITE_MIRROR}/repo/x86_64/cachyos/${ELITE_V3ML_PKG}"

## [E3] pacman.conf do sistema: reescrito LIMPO (o bloco acima do Archcraft
##      duplica [core]/[extra]; aqui fica canônico, sem duplicatas).
##      Prioridade: archcraft > cachyos(v2+v3) > core/extra > multilib
ELITE_PC="/etc/pacman.conf"
awk '/^\[/ {exit} {print}' "$ELITE_PC" > /tmp/elite-pc-options
{
    cat /tmp/elite-pc-options
    cat <<'EOL'

[archcraft]
SigLevel = Optional TrustAll
Include = /etc/pacman.d/archcraft-mirrorlist

# >>> ELITE: CachyOS — wiki.cachyos.org/features/optimized_repos
# v2: meta-pacotes (cachyos-settings, dmemcg-booster, cachyos-ananicy-rules)
[cachyos]
Server = https://mirror.cachyos.org/repo/x86_64/cachyos

# v3: kernels (linux-cachyos-bore), gamescope, nvidia-open-dkms
[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

# v3: rebuilds do [core]
[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

# v3: rebuilds do [extra] (ananicy-cpp, scx-tools, gamemode, mangohud, lact)
[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist
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

## [E4] Refresh DBs com o conf novo (confirma que tudo resolve dentro do chroot)
pacman -Sy --noconfirm || true
