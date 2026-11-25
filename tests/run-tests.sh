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
#   FASE 3.5 CONTRATO DO CRAFT-HELP (Fase 2 do dono) — 100% do mapa do
#           craft-help existe, nasce 0755 no git, passa em sh -n e responde
#           verbo seguro; os atalhos vivem nos keybinds reais do rc.xml
#   FASE 4  INTEGRIDADE DO COMPOSITOR (Fase 2) — XML estrito de menu/rc
#           + TODO Execute aponta binário REAL (sem fantasma craft-drawer,
#           sem ícone em item, sem fóssil de era)
#   FASE 5  SAÚDE DE RUNTIME & IPC (Fase 2) — 0755 sweep de toda a casa,
#           lançador ÚNICO no autostart-template, bus.sock UMA fonte,
#           instância única no fonte, ZERO glifo Nerd, popovers fechando
#           o ciclo, painéis respondendo
#   FASE 6  VEREDICTO — GO exige todas as peças encaixadas (exit 0)
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

# a suíte é sensível a ambiente sujo: os fakes órfãos de sessões mortas
# e o __pycache__ legado saem no arranque (a lição E47/E134-h/a71414b)
find tests -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true

printf '%b╭──────────────────────────────────────────────────╮%b\n' "\e[1m" "\e[0m"
printf '%b│  ARCHCRAFT ELITE 2.0 — PORTEIRA REAL EM CADEIA     │%b\n' "\e[1m" "\e[0m"
printf '%b╰──────────────────────────────────────────────────╯%b\n' "\e[1m" "\e[0m"
printf '  repo: %s\n  work: %s\n\n' "$REPO" "$WORK"

BROKEN=0
for name in 10-estrutura 20-estatica 30-cargo 35-ajuda 40-compositor 50-runtime-ipc 60-veredito; do
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
