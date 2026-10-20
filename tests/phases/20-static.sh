#!/usr/bin/env bash
# FASE 2 — A TAMPA DA CAIXA: qualidade estática (o desenho completo antes de abrir)
source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"
phase_start 2 "QUALIDADE ESTÁTICA — a tampa da caixa"

SHELLS=(
  scripts/apply-overlay.sh
  .ci/build.sh
  elite/fragments/elite-customize.sh
  elite/airootfs/usr/local/bin/elite-tune
  elite/airootfs/usr/local/bin/fg-booster
  elite/airootfs/usr/local/bin/elite-status
  tests/run-tests.sh
  tests/lib/core.sh
  tests/lib/setup.sh
  tests/phases/10-env.sh tests/phases/20-static.sh tests/phases/30-unit.sh
  tests/phases/40-integration.sh tests/phases/50-release.sh tests/phases/60-verdict.sh
)

# peças: sintaxe — bash -n em tudo (a suíte testa a si mesma: peças 7-12)
bashn=0; bashfail=0
for s in "${SHELLS[@]}"; do
  if bash -n "$REPO/$s" 2>/dev/null; then bashn=$((bashn+1)); else bashfail=$((bashfail+1)); echo "    sintaxe ruim: $s" >&2; fi
done
assert_eq "$bashfail" "0" "bash -n: $bashn/${#SHELLS[@]} scripts parseiam (repo + a própria suíte)"

# peça: shellcheck — mesmo gate do CI (warning ou acima); local pode não ter
if command -v shellcheck >/dev/null 2>&1; then
  sc_log="$WORK/shellcheck.log"; : > "$sc_log"
  for s in "${SHELLS[@]}"; do
    shellcheck -S warning -x "$REPO/$s" >> "$sc_log" 2>&1 || true
  done
  # o lint cobre também os mocks/extract gerados (padrão de qualidade da suíte)
  assert_eq "$(wc -l < "$sc_log")" "0" "shellcheck: 0 avisos em ${#SHELLS[@]} scripts (gate do CI)"
else
  skip "shellcheck: gate do CI" "binário ausente neste ambiente — o job de lint no GitHub o executa"
fi

# peças: YAML válido (os 3 workflows)
for y in build.yml agents.yml tests.yml; do
  if [[ -f "$REPO/.github/workflows/$y" ]]; then
    python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$REPO/.github/workflows/$y" 2>/dev/null \
      && ok "yaml: $y parseia" \
      || fail "yaml: $y" "YAML inválido"
  else
    fail "yaml: $y" "workflow ausente"
  fi
done

# peças: bits executáveis onde o runtime exige
for x in \
  elite/airootfs/usr/local/bin/elite-tune \
  elite/airootfs/usr/local/bin/fg-booster \
  elite/airootfs/usr/local/bin/elite-status \
  scripts/apply-overlay.sh
do
  [[ -x "$REPO/$x" ]] && ok "exec: $x" || fail "exec: $x" "sem bit de execução"
done

# peças: higiene — sem CRLF, shebang presente
crlf=0
for s in "${SHELLS[@]}" "$REPO"/.github/workflows/*.yml; do
  grep -qU $'\r' "$s" 2>/dev/null && crlf=$((crlf+1))
done
assert_eq "$crlf" "0" "higiene: 0 arquivos com CRLF"

sheb=0
for x in elite-tune fg-booster elite-status; do
  head -1 "$REPO/elite/airootfs/usr/local/bin/$x" | grep -q '^#!' && sheb=$((sheb+1))
done
assert_eq "$sheb" "3" "higiene: shebang nos 3 binários do airootfs"

phase_end
