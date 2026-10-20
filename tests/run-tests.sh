#!/usr/bin/env bash
# tests/run-tests.sh — o quebra-cabeça completo, em cadeia:
#   FASE 1 A MESA → 2 QUALIDADE ESTÁTICA → 3 UNIDADE → 4 CADEIA → 5 USO/RELEASE
#   → VEREDICTO (a imagem completa)
# Regra da cadeia: fase que QUEBRA interrompe as seguintes (BLOQUEADA);
# o veredito só dá GO quando TODAS as peças encaixam. Exit 0 = GO.
#
# Uso: bash tests/run-tests.sh [--keep]
#   --keep  preserva o dir de trabalho (mocks, logs, fixture) p/ inspeção
set -uo pipefail
cd "$(dirname "$0")" || exit 1

source lib/core.sh
source lib/setup.sh

if [[ "${1:-}" == "--keep" ]]; then
  KEEP=1
else
  KEEP="${ELITE_TESTS_KEEP:-0}"
fi
(( KEEP )) || trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT

: > "$WORK/summary.txt"

printf '%s╭──────────────────────────────────────────────╮%s\n' "$C_BLD" "$C_RST"
printf '%s│  ARCHCRAFT ELITE — SUÍTE DE TESTES EM CADEIA  │%s\n' "$C_BLD" "$C_RST"
printf '%s╰──────────────────────────────────────────────╯%s\n' "$C_BLD" "$C_RST"
printf '  repo: %s\n  work: %s\n%s' "$REPO" "$WORK" "$C_RST"

PHASES=(10-env 20-static 30-unit 40-integration 50-release)
BROKEN=0
for name in "${PHASES[@]}"; do
  if (( BROKEN )); then
    printf 'BLOQUEADA\t%s\t0\t0\t0\n' "$name" >> "$WORK/summary.txt"
    printf '  %s▓▓ FASE %s — BLOQUEADA (a peça anterior quebrou a cadeia)%s\n' \
      "$C_BAD" "$name" "$C_RST"
    continue
  fi
  bash "phases/$name.sh" || BROKEN=1
done

bash phases/60-verdict.sh
exit $?
