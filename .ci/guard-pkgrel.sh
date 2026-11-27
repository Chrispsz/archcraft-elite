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
# O mapa conteúdo→pacote (E43→E50→2.0 Fase 2 — a era do PACOTE ÚNICO):
#   elite/airootfs/usr/local/bin/*                            → elite-system (os bins COMPILADOS também vivem aqui)
#   elite/airootfs/etc/systemd/system/elite-*                 → elite-system
#   vendor/                                                   → elite-system (história: a ponte velha e as deleções)
#   crates/**                                                 → elite-system (E131: o workspace compila NO pacote —
#                                                                mudou Rust, mudou conteúdo, sobe pkgrel — a lei E41)
# (o elite-craft parou na E50 e o craft-toplevel parou na 2.0 Fase 2 —
# o cliente Wayland é o próprio elite-daemon; o guard não cobra mais
# NENHUM dos dois: o replaces do elite-system limpa o par legado dos
# rigs na transição do pacman — a mesma lei do mapa antigo)
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
    # 1.0-107.1 — comparação de VERSÃO (não de inteiro): o ciclo
    # intermediário usa pkgrel com ponto (107.1) — sort -V julga
    # "107.1 > 107" do jeito que o pacman lê (107.1 é uma revisão do 107).
    if [ "$cur" = "$old" ] || \
       [ "$(printf '%s\n%s\n' "$cur" "$old" | sort -V | head -n1)" = "$cur" ]; then
        echo "guard-pkgrel: FALHA — $pkg: pkgrel $cur ≤ $old (na $LAST_TAG) com conteúdo mudado."
        echo "  A LEI E41: conteúdo do pacote muda → pkgrel sobe NO MESMO commit."
        echo "  Cure: suba pkgrel= no template de $pkg em .ci/build.sh e recommita."
        return 1
    fi
    echo "guard-pkgrel: $pkg pkgrel $old → $cur ✓"
}

fail=0
# 2.0 Fase 2 — A PONTE MORREU (E143): o pacote craft-toplevel aposentou
# com o C de 3 gerações (o cliente Wayland é o elite-daemon; o toplevel.
# sock e o hook elite-adopt morreram juntos) — o check DELE sai do guard
# (a mesma aposentadoria do elite-craft E50) e o vendor/ inteiro vira
# HISTÓRIA do elite-system (a deleção da ponte conta pro ÚNICO, como a
# do listener E132). O buraco que a E142 deixou aberto fecha junto: o
# crates/ compila NO build do elite-system (a fundação E131) — Rust
# mudando sem pkgrel é a MESMA lei E41 do shell; as doses E142a–d
# passaram pelo guard porque crates/ não caía em delta NENHUM — agora
# cai no do ÚNICO (pkgrel 92 da E143 cobre a era inteira contra a tag).
BIN_DELTA="$(git diff --name-only "$LAST_TAG" HEAD -- elite/airootfs/usr/local/bin || true)"
UNIT_DELTA="$(git diff --name-only "$LAST_TAG" HEAD -- 'elite/airootfs/etc/systemd/system/elite-*' || true)"
VENDOR_DELTA="$(git diff --name-only "$LAST_TAG" HEAD -- vendor/ || true)"
RUST_DELTA="$(git diff --name-only "$LAST_TAG" HEAD -- 'crates/**' ':(exclude)crates/target/**' || true)"
DELTA="$(printf '%s\n%s\n%s\n%s\n' "$BIN_DELTA" "$UNIT_DELTA" "$VENDOR_DELTA" "$RUST_DELTA" | sed '/^$/d' | sort -u)"
check elite-system "$DELTA" || fail=1

exit "$fail"
