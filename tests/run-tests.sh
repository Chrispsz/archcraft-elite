#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════
# tests/run-tests.sh — A PORTEIRA REAL (2.0)
#
# O quebra-cabeça em cadeia, nível REAL por nível (a diretriz do dono:
# a suíte antiga de mocks que passavam enquanto a tela quebrava morre —
# a porteira nova só contrata o que a árvore entrega DE VERDADE):
#
#   FASE 1  ESTRUTURA — o workspace 2.0 e os moradores (crates/, bins,
#           moldes, o E41)
#   FASE 2  ESTÁTICA REAL — os contratos sobre os ARQUIVOS: tuning
#           sagrado (sysctl/udev/grub/modprobe), configs (menu/rc/
#           autostart), pacotes da diretriz, legado AUSENTE, shellcheck
#   FASE 3  NÚCLEO RUST — `cargo test --workspace` dos contratos reais
#           (IPC/persistência/parsers) — com toolchain presente; sem ela,
#           SKIP HONESTO (o juízo de compilação da gui é o Canal do CI,
#           lei L6 da casa)
#   FASE 4  VEREDICTO — GO exige todas as peças encaixadas (exit 0)
#
#
# Os níveis da Fase 2 que exigem AMBIENTE VIVO:
#   - tests/ci-runtime-smoke.sh — o pacote do Canal sobe a sessão no
#     labwc headless do CI (barra/dock SEM Gtk-WARNING, bus RESPONDENDO,
#     a 2ª instância sai 0 — executivo, sobre o pacote que vai subir);
#   - tests/session_smoke/run.sh — o rig do dono (a sessão de verdade).
#
# Uso: bash tests/run-tests.sh [--keep]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"
export REPO WORK

WORK="${ELITE_TESTS_WORK:-/tmp/elite-suite-2.0-$$}"
KEEP="${ELITE_TESTS_KEEP:-0}"
[[ "${1:-}" == "--keep" ]] && KEEP=1
(( KEEP )) || trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT
mkdir -p "$WORK"


printf '%b╭──────────────────────────────────────────────────╮%b\n' "\e[1m" "\e[0m"
printf '%b│  ARCHCRAFT ELITE 2.0 — PORTEIRA REAL EM CADEIA     │%b\n' "\e[1m" "\e[0m"
printf '%b╰──────────────────────────────────────────────────╯%b\n' "\e[1m" "\e[0m"
printf '  repo: %s\n  work: %s\n\n' "$REPO" "$WORK"

# ── 1.0-103 — O PRE-BUILD DO JUIZ DE CASA (a erradicação do python): a
#    suíte julgava XML/INI/Execute por heredocs python — agora o juiz é o
#    craft-audit (núcleo std do craft-tools), PRE-BUILDADO uma única vez no
#    arranque da porteira e exportado como $ELITE_JUDGE para as fases. Sem
#    cargo no ambiente (e sem xmllint): t_skip HONESTO nas peças de juízo.
export ELITE_JUDGE="${ELITE_JUDGE:-}"
if [ -z "$ELITE_JUDGE" ]; then
    if command -v cargo >/dev/null 2>&1; then
        export PATH="$HOME/.cargo/bin:$PATH"
        # o target COMPARTILHADO com a fase 30 (o cargo compila UMA vez)
        export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/elite-suite-cargo}"
        if cargo build -q -p craft-tools --no-default-features --bin craft-audit 2>/dev/null \
           && [ -x "$CARGO_TARGET_DIR/debug/craft-audit" ]; then
            ELITE_JUDGE="$CARGO_TARGET_DIR/debug/craft-audit"
            export ELITE_JUDGE
            printf '  juiz de casa: craft-audit pré-buildado (%s)\n' "$ELITE_JUDGE"
        fi
    fi
fi
[ -n "$ELITE_JUDGE" ] || printf '  juiz de casa: AUSENTE (cargo fora do ambiente — as peças de juízo pulam HONESTO)\n'

BROKEN=0
# 1.0-108 — a fase 57 (smoke headless dos binários compilados) roda DEPOIS
# do hardware: o juízo executivo do rig (o CPU <5% do idle e os menus do
# pick) é o PENÚLTIMO degrau antes do veredito; a 1.0-110 (E189 T7)
# acrescenta a fase 58 — a suíte executiva do IPC VIVO (o player mock
# D-Bus de verdade, os verbos do bus com Ack, o reexec do USR1 preservando
# o PID e os contratos vivos da dose no último degrau antes do veredito)
for name in 10-estrutura 20-estatica 30-cargo 35-ajuda 40-compositor 50-runtime-ipc 55-hardware 57-smoke-headless 58-ipc-vivo 60-veredito; do
    if (( BROKEN )); then
        printf '  ▓▓ FASE %s — BLOQUEADA (a peça anterior quebrou a cadeia)\n' "$name"
        continue
    fi
    bash "tests/phases/$name.sh" || BROKEN=1
done

# o veredito já foi impresso pelo tee do 60-veredito — aqui só o exit
if [ -f "$WORK/verdict.txt" ]; then
    verdict="$(grep -o 'GO\|NO-GO' "$WORK/verdict.txt" | tail -1)"
    [ "$verdict" = "GO" ] || exit 1
    exit 0
fi
echo "ERRO: veredito ausente (60-veredito não rodou)"
exit 1
