# shellcheck shell=bash
# tests/lib/core.sh — motor do quebra-cabeça (sourced, nunca executado direto)
# Contrato: cada fase roda num processo bash próprio; o estado global vive
# em $WORK (dir temporário compartilhado via ELITE_TESTS_WORK) e o placar
# da fase viaja até o veredito por $WORK/summary.txt.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$TESTS_DIR/.." && pwd)"

# $WORK sobrevive entre os processos das fases (uma peça alimenta a próxima)
if [[ -n "${ELITE_TESTS_WORK:-}" ]]; then
  WORK="$ELITE_TESTS_WORK"
else
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/elite-puzzle.XXXXXX")"
fi
export ELITE_TESTS_WORK="$WORK"
export WORK REPO TESTS_DIR

STATE="$WORK/state"
mkdir -p "$STATE" "$WORK/mocks"

if [[ -t 1 ]]; then
  C_OK=$'\e[32m'; C_BAD=$'\e[31m'; C_WARN=$'\e[33m'
  C_DIM=$'\e[2m';  C_BLD=$'\e[1m'; C_RST=$'\e[0m'
else
  C_OK=""; C_BAD=""; C_WARN=""; C_DIM=""; C_BLD=""; C_RST=""
fi

PHASE_PASS=0; PHASE_FAIL=0; PHASE_SKIP=0
LAST_FAIL=""

# ── peças ───────────────────────────────────────────────────────────
ok()   { PHASE_PASS=$((PHASE_PASS+1)); printf '  %s✔%s %s\n' "$C_OK" "$C_RST" "$1"; }
fail() {
  PHASE_FAIL=$((PHASE_FAIL+1)); LAST_FAIL="$1"
  printf '  %s✘%s %s\n' "$C_BAD" "$C_RST" "$1"
  [[ -n "${2:-}" ]] && printf '      %s└─ %s%s\n' "$C_DIM" "$2" "$C_RST"
}
skip() { PHASE_SKIP=$((PHASE_SKIP+1)); printf '  %s⊘%s %s %s— %s%s\n' "$C_WARN" "$C_RST" "$1" "$C_DIM" "${2:-"ignorado"}" "$C_RST"; }

# ── asserções (cada uma = 1 peça) ───────────────────────────────────
assert_eq()      { local got="$1" want="$2" n="$3"; [[ "$got" == "$want" ]] && ok "$n" || fail "$n" "esperado '$want' · obtido '$got'"; }
assert_match()   { local got="$1" re="$2" n="$3"; [[ "$got" =~ $re ]] && ok "$n" || fail "$n" "padrão '$re' não casa em: ${got:0:200}"; }
assert_grep()    { local f="$1" re="$2" n="$3"; grep -qE -- "$re" "$f" 2>/dev/null && ok "$n" || fail "$n" "padrão '$re' ausente em $f"; }
assert_nogrep()  { local f="$1" re="$2" n="$3"; grep -qE -- "$re" "$f" 2>/dev/null && fail "$n" "padrão '$re' PRESENTE em $f (não deveria)" || ok "$n"; }
assert_file()    { [[ -e "$1" ]] && ok "$2" || fail "$2" "caminho ausente: $1"; }
assert_nofile()  { [[ -e "$1" ]] && fail "$2" "caminho EXISTE (não deveria): $1" || ok "$2"; }
assert_rc0()     { local n="$1"; shift; local out rc; out="$("$@" 2>&1)"; rc=$?; (( rc == 0 )) && ok "$n" || fail "$n" "exit $rc · ${out:0:200}"; }

# ── mocks: PATH + MOCK_DIR isolados num subshell ────────────────────
with_mocks() {
  (
    export PATH="$WORK/mocks:$PATH" MOCK_DIR="$STATE"
    "$@"
  )
}

# ── fases ───────────────────────────────────────────────────────────
phase_start() {
  PHASE_NUM="$1"; PHASE_TITLE="$2"
  PHASE_PASS=0; PHASE_FAIL=0; PHASE_SKIP=0
  set +e   # uma peça quebrada não derruba as demais — quem para a cadeia é o runner
  printf '\n%s■ FASE %s — %s%s\n' "$C_BLD" "$PHASE_NUM" "$PHASE_TITLE" "$C_RST"
}

phase_end() {
  local total=$((PHASE_PASS+PHASE_FAIL+PHASE_SKIP))
  printf '%s\t%s\t%d\t%d\t%d\n' \
    "$PHASE_NUM" "$PHASE_TITLE" "$PHASE_PASS" "$PHASE_FAIL" "$PHASE_SKIP" \
    >> "$WORK/summary.txt"
  if (( PHASE_FAIL > 0 )); then
    printf '  %s□ %s: %d peças — %sFALHOU%s\n' "$C_BAD" "$PHASE_TITLE" "$total" "$C_BAD" "$C_RST"
    printf '\n%s⛓  CADEIA INTERROMPIDA na fase %s — peça defeituosa: %s%s\n' \
      "$C_BAD" "$PHASE_NUM" "${LAST_FAIL:-?}" "$C_RST"
    return 1
  fi
  printf '  %s□ %s: %d peças encaixadas%s\n' "$C_OK" "$PHASE_TITLE" "$total" "$C_RST"
  return 0
}
