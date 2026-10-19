#!/usr/bin/env bash
# =====================================================================
#  apply-overlay.sh — Arquitetura "delta" da Elite Edition
#
#  Não é um fork: clona o profile OFICIAL do Archcraft (edição
#  Openbox/BSPWM) e aplica a camada Elite por cima. A cada build,
#  sincroniza automaticamente com o upstream (dotfiles, temas, calamares,
#  nvidia live) — zero manutenção de fork.
#
#  Uso (CI ou local, precisa: git, rsync, curl):
#    bash scripts/apply-overlay.sh
#  Saída: elite-build/ pronto para o mkarchcraftiso.
# =====================================================================
set -euo pipefail
G='\033[1;32m'; N='\033[0m'; B='\033[1m'
say() { echo -e "${G}==>${N} $1"; }
cd "$(dirname "$0")/.."

SRC="https://github.com/archcraft-os/archcraft.git"
OUT="elite-build"

command -v git    >/dev/null || { echo "ERRO: git necessário";    exit 1; }
command -v rsync  >/dev/null || { echo "ERRO: rsync necessário";  exit 1; }
command -v curl   >/dev/null || { echo "ERRO: curl necessário";   exit 1; }

# ── [1] Upstream fresco ─────────────────────────────────────────────
say "Clonando Archcraft upstream → $OUT/"
rm -rf "$OUT"
git clone --depth=1 "$SRC" "$OUT"

# ── [2] Raiz do profile (defensivo contra mudança de layout) ───────
PROFILE=$(dirname "$(find "$OUT" -maxdepth 3 -name profiledef.sh -print -quit)")
[[ -f "$PROFILE/packages.x86_64" && -f "$PROFILE/pacman.conf" ]] \
  || { echo "ERRO: profile Archcraft não encontrado"; exit 1; }
say "Profile detectado: $PROFILE"

# ── [3] Overlay airootfs (arquivos Elite vencem; nada deles é apagado)
say "Aplicando overlay airootfs/"
rsync -a elite/airootfs/ "$PROFILE/airootfs/"

# ── [4] Pacotes Elite (append com dedupe) ──────────────────────────
say "Mesclando elite/packages.add"
while IFS= read -r pkg; do
  [[ -z "${pkg// /}" || "${pkg:0:1}" == '#' ]] && continue
  grep -qxF "$pkg" "$PROFILE/packages.x86_64" || echo "$pkg" >> "$PROFILE/packages.x86_64"
done < elite/packages.add

# ── [5] Repos CachyOS no pacman.conf de BUILD ──────────────────────
#  Inseridos ANTES de [core] (precedência v3), logo após [archcraft].
#  DownloadUser do conf deles só existe no runner deles — removemos.
say "Mesclando repos CachyOS no pacman.conf (build)"
PC="$PROFILE/pacman.conf"
sed -i '/^DownloadUser/d' "$PC"
if ! grep -q '^\[cachyos-v3\]' "$PC"; then
  TMP=$(mktemp)
  awk -v block="$(cat elite/pacman-repos.build.add)" '
    /^\[core\]/ && !done { print block; print ""; done = 1 }
    { print }
    END { if (!done) { print ""; print block } }
  ' "$PC" > "$TMP"
  cat "$TMP" > "$PC"; rm -f "$TMP"
fi
# multilib (lib32-gamemode/lib32-mangohud)
grep -q '^\[multilib\]' "$PC" || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> "$PC"

# ── [6] Fragmento elite no customize_airootfs.sh ───────────────────
say "Anexando fragmento elite ao customize_airootfs.sh"
CF="$PROFILE/airootfs/root/customize_airootfs.sh"
mkdir -p "$(dirname "$CF")"
[[ -f "$CF" ]] || printf '#!/usr/bin/env bash\nset -e -u\n' > "$CF"
cat elite/fragments/elite-customize.sh >> "$CF"
chmod +x "$CF"

say "Overlay aplicado. Build:"
echo -e "  ${B}cd $PROFILE && ./mkarchcraftiso -v -w /tmp/iso-work -o out .${N}"
