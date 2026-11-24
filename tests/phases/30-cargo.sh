#!/usr/bin/env bash
# tests/phases/30-cargo.sh — FASE 3: o NÚCLEO RUST (os contratos reais)
# `cargo test --workspace --no-default-features`: IPC, persistência
# atômica, parsers, juízos — o núcleo std-only testa em QUALQUER lugar.
# A camada gui (gtk4) é o juízo do CANAL no CI (lei L6 da casa: o
# pkg-config gtk4 não existe no sandbox e no runner da suíte).
set -uo pipefail
source "$(dirname "$0")/../lib/core.sh"

echo "  ── FASE 3 · NÚCLEO RUST — os contratos do elite-core e da família ──"

# o PATH da casa pode carregar a toolchain fora do PATH padrão
export PATH="$HOME/.cargo/bin:$PATH"

if ! command -v cargo >/dev/null 2>&1; then
    t_skip "cargo test --workspace (os 90+ contratos do núcleo)" \
        "toolchain rust ausente — o juízo de compilação é o Canal do CI (L6)"
    printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase30.txt"
    exit 0
fi

cd "$REPO/crates" || { t_fail "crates/ acessível" "cd crates falhou"; exit 0; }

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/elite-suite-cargo}"
out="$(timeout 420 cargo test --workspace --no-default-features 2>&1)"
rc=$?
if [ $rc -eq 0 ]; then
    totais="$(printf '%s\n' "$out" | grep -oE 'test result: ok\. [0-9]+ passed' \
        | grep -oE '[0-9]+' | awk '{t+=$1} END {print t+0}')"
    t_ok "cargo test --workspace --no-default-features: ${totais:-0} contratos reais, 0 falhas (exit 0)"
else
    t_fail "cargo test --workspace --no-default-features" \
        "$(printf '%s\n' "$out" | grep -E 'error|FAILED|panicked' | head -3 | tr '\n' ' ')"
fi

# zero avisos no BUILD TESTE (a casa não carrega aviso nenhum — §3 +
# E140-corrigido). O check SEM testes sinaliza os itens que a gui
# consome (mortos por desenho sem a feature) — feição documentada do
# design gui-gated; o gate honesto é o build que os testes compilam.
warnings="$(printf '%s\n' "$out" | grep -c '^warning:' || true)"
if [ "$warnings" = "0" ]; then
    t_ok "cargo test build: zero avisos no núcleo"
else
    t_fail "cargo test build: zero avisos no núcleo" "$warnings aviso(s)"
fi

printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase30.txt"
exit 0
