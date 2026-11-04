#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# .ci/guard-pkgrel.sh — A LEI E41 EM CADA PUSH (automatizada)
# ───────────────────────────────────────────────────────────────────────────
# A E41 (o pkgrel que não subiu) provou: pacman compara VERSÃO, nunca bytes
# — conteúdo de casa mudou e pkgrel parado = o -Syu PULA e a cura nunca
# chega a rig nenhum. A lei nasceu escrita no comentário do template; a
# partir daqui ela é EXECUTADA: push que mexe no conteúdo de UM pacote tem
# de ter subido o pkgrel DELE — comparado contra a ÚLTIMA TAG. Falhou =
# push vermelho = o mantenedor sobe o pkgrel NO MESMO commit.
#
# O mapa conteúdo→pacote (E43, refinamento: o guard grosso cobraria o
# craft-toplevel por mudança de craft-bars — réu errado):
#   vendor/craft-toplevel.c                                   → craft-toplevel
#   elite/airootfs/usr/local/bin/* (menos craft-toplevel)     → elite-craft
#
# Roda no publish-packages.yml (fetch-depth: 0 — precisa de história).
# Sem tag ou sem delta do pacote → sai 0 (nada a cobrar).
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
if [ -z "$LAST_TAG" ]; then
    echo "guard-pkgrel: nenhuma tag no repo — nada a comparar (ok)"
    exit 0
fi

pkgrel_of() { # $1 = commit/tree ("HEAD" ou tag)  $2 = pkgname → pkgrel do template no build.sh
    # index() e não $0==pkg: o template do elite-craft nasce DENTRO do
    # f-string python ('pkg = f"""pkgname=elite-craft') — linha exata nunca casa
    awk -v pkg="pkgname=$2" '
        index($0, pkg) { found=1; next }
        found && /^pkgrel=/ { sub(/^pkgrel=/, ""); print; exit }
        found && index($0, "pkgname=") && !index($0, pkg) { exit }   # entrou outro pacote: não achou
    ' < <(git show "$1:.ci/build.sh")
}

check() { # $1=pacote  $2=delta (nomes de arquivo)
    local pkg="$1" delta="$2" cur old
    [ -n "$delta" ] || { echo "guard-pkgrel: $pkg — conteúdo intocado desde $LAST_TAG (ok)"; return 0; }
    echo "guard-pkgrel: conteúdo de $pkg mudou desde $LAST_TAG:"
    while IFS= read -r f; do printf '  %s\n' "$f"; done <<< "$delta"
    cur="$(pkgrel_of HEAD "$pkg" || true)"
    old="$(pkgrel_of "$LAST_TAG" "$pkg" || true)"
    # template inexistente na tag (ex.: elite-craft nasceu depois) = 0
    cur="${cur:-0}"; old="${old:-0}"
    if [ "$cur" -le "$old" ]; then
        echo "guard-pkgrel: FALHA — $pkg: pkgrel $cur ≤ $old (na $LAST_TAG) com conteúdo mudado."
        echo "  A LEI E41: conteúdo do pacote muda → pkgrel sobe NO MESMO commit."
        echo "  Cure: suba pkgrel= no template de $pkg em .ci/build.sh e recommita."
        return 1
    fi
    echo "guard-pkgrel: $pkg pkgrel $old → $cur ✓"
}

fail=0
# craft-toplevel: o C vendado É o conteúdo do pacote
VENDOR_DELTA="$(git diff --name-only "$LAST_TAG" HEAD -- vendor/ || true)"
check craft-toplevel "$VENDOR_DELTA" || fail=1

# elite-craft: todo o /usr/local/bin da casa MENOS o arquivo dono do pacote
# próprio + as units de sistema da casa (E46 — o payload /etc do pacote;
# unit mudada sem pkgrel = o -Syu pula a cadência em silêncio)
BIN_DELTA="$(git diff --name-only "$LAST_TAG" HEAD -- elite/airootfs/usr/local/bin | grep -vx 'craft-toplevel' || true)"
UNIT_DELTA="$(git diff --name-only "$LAST_TAG" HEAD -- 'elite/airootfs/etc/systemd/system/elite-*' || true)"
DELTA="$(printf '%s\n%s\n' "$BIN_DELTA" "$UNIT_DELTA" | sed '/^$/d' | sort -u)"
check elite-craft "$DELTA" || fail=1

exit "$fail"
