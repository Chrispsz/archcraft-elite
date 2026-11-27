#!/usr/bin/env bash
# tests/phases/55-hardware.sh — FASE 5.5 · A MATRIZ DOS 6 PERFIS (E106/5c)
# ══════════════════════════════════════════════════════════════════════════
# O tuning condicionado ao hardware (o deep do S3, o snapper do btrfs,
# o sensor que a placa TEM, o liquidctl que não existe, a tela que
# volta com o modo do dono) agora é CONTRATO VIVO: tests/hardware/
# simula os 6 perfis reais da matriz num sandbox de root falso
# (unshare -rm + bind mounts + stubs no PATH — as seams da casa
# ELITE_ACPI_WAKEUP/ELITE_RANDR) e compara BYTE A BYTE os arquivos
# resultantes contra o esperado de cada perfil. Sem userns no ambiente
# (runner restrito): pulo HONESTO — a matriz nunca mente GO sem provar.
# ══════════════════════════════════════════════════════════════════════════
set -uo pipefail
source "$(dirname "$0")/../lib/core.sh"

echo "  ── FASE 5.5 · HARDWARE — a matriz dos 6 perfis no sandbox de root ──"

OUT="$(bash "$(dirname "$0")/../hardware/run.sh" 2>/dev/null)"; RC=$?

if [ "$RC" = 3 ]; then
    # o sandbox é impossível AQUI (userns bloqueado): pulo honesto L6 —
    # a matriz roda no rig do dono e nos runners que falam userns
    t_skip "matriz dos 6 perfis (sandbox --root)" \
        "unshare/mount indisponível no ambiente (userns bloqueado — a dose seria simulação sem prova)"
elif [ "$RC" = 0 ] || [ "$RC" = 1 ]; then
    while IFS=$'\t' read -r tag desc reu; do
        [ -n "${tag:-}" ] || continue
        case "$tag" in
            OK)      t_ok "$desc" ;;
            FAIL)    t_fail "$desc" "${reu:-?}" ;;
            SUMMARY) : ;;   # o total do simulador (o veredito é da porteira)
            *)       printf '  %s %s\n' "$tag" "$desc" ;;   # INFO: eco sem contar
        esac
    done <<< "$OUT"
else
    t_fail "matriz dos 6 perfis (sandbox --root)" "o simulador morreu com rc=$RC (não é veredito — é defeito): $(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"
fi

printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase55.txt"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
