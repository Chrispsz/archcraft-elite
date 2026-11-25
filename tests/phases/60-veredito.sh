#!/usr/bin/env bash
# tests/phases/60-veredito.sh — FASE 4: o VEREDICTO (a imagem completa)
set -uo pipefail
source "$(dirname "$0")/../lib/core.sh"

OK=0; FAIL=0; SKIP=0
for f in "$WORK"/fase*.txt; do
    [ -f "$f" ] || continue
    read -r o fl sk < "$f"
    OK=$((OK + o)); FAIL=$((FAIL + fl)); SKIP=$((SKIP + sk))
done

{
    printf '%s\n' "══════════════════════════════════════════════════════════"
    printf '%s\n' " ARCHCRAFT ELITE 2.0 — PORTEIRA REAL (cadeia completa) "
    printf '%s\n' "══════════════════════════════════════════════════════════"
    if [ "$FAIL" -eq 0 ]; then
        printf '  CONTRATOS: %s · falhas: 0 · pulos: %s\n' "$OK" "$SKIP"
        printf '%s\n' "  VEREDICTO: GO — a porteira real encaixou inteira"
    else
        printf '  CONTRATOS: %s · falhas: %s · pulos: %s\n' "$OK" "$FAIL" "$SKIP"
        printf '%s\n' "  VEREDICTO: NO-GO — os réus estão nomeados acima"
    fi
    printf '%s\n' "══════════════════════════════════════════════════════════"
} | tee "$WORK/verdict.txt"

printf '%s\n' "$OK $FAIL $SKIP" > "$WORK/fase60.txt"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
