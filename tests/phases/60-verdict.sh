#!/usr/bin/env bash
# VEREDICTO — a última peça: a imagem completa do quebra-cabeça
source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"

tp=0; tf=0; ts=0; tb=0
declare -a ROWS=()
if [[ -f "$WORK/summary.txt" ]]; then
  while IFS=$'\t' read -r num title p f s; do
    if [[ "$num" == "BLOQUEADA" ]]; then
      tb=$((tb+1)); ROWS+=("BLOQUEADA|$title|—|—")
    else
      tp=$((tp+p)); tf=$((tf+f)); ts=$((ts+s))
      st="OK"; [[ $f -gt 0 ]] && st="FALHOU"
      ROWS+=("$num|$title|$p|$st")
    fi
  done < "$WORK/summary.txt"
fi

printf '\n'
printf '%s══════════════════════════════════════════════════════════════%s\n' "$C_BLD" "$C_RST"
printf '%s ARCHCRAFT-ELITE — QUEBRA-CABEÇA DE TESTES (cadeia completa) %s\n' "$C_BLD" "$C_RST"
printf '%s══════════════════════════════════════════════════════════════%s\n' "$C_BLD" "$C_RST"
for r in "${ROWS[@]}"; do
  IFS='|' read -r num title p st <<< "$r"
  if [[ "$num" == "BLOQUEADA" ]]; then
    printf '  %s▓▓ FASE %-28s BLOQUEADA (cadeia interrompida antes)%s\n' "$C_BAD" "$title" "$C_RST"
  elif [[ "$st" == "OK" ]]; then
    printf '  %s□ %s %-30s %s%3d peças%s\n' "$C_OK" "$num" "$title" "$C_OK" "$p" "$C_RST"
  else
    printf '  %s■ %s %-30s FALHOU%s\n' "$C_BAD" "$num" "$title" "$C_RST"
  fi
done
printf '%s──────────────────────────────────────────────────────────────%s\n' "$C_DIM" "$C_RST"
printf '  PEÇAS ENCAIXADAS: %d · falhas: %d · pulos: %d · bloqueadas: %d\n' "$tp" "$tf" "$ts" "$tb"

# v2.10.5 — A FASE QUE MORRE NÃO DEIXA LINHA: um kill/OOM na fase 5 não
# escreve summary e o veredito dava GO com 4 das 5 peças (a imagem
# incompleta passava por completa). A lei: GO só com AS CINCO fases na
# mesa — linha ausente é morte, e morte é NO-GO.
MISSING=0
# (o phase_end grava o NUM da fase — 1..5; nomes só aparecem nas linhas
# BLOQUEADA do runner — por isso a prova é numérica e com TAB)
for ph in 1 2 3 4 5; do
  if ! grep -q "^${ph}$(printf '\t')" "$WORK/summary.txt" 2>/dev/null; then
    MISSING=1
    printf '  %s✖ fase %s SEM LINHA no summary (morreu antes do phase_end?)%s\n' "$C_BAD" "$ph" "$C_RST"
  fi
done

if (( tf == 0 && tb == 0 && MISSING == 0 )); then
  printf '  %sVEREDICTO: GO — imagem completa, tudo encaixou%s\n' "$C_OK" "$C_RST"
  exit 0
else
  printf '  %sVEREDICTO: NO-GO — peça(ns) fora do lugar; conserte antes de montar%s\n' "$C_BAD" "$C_RST"
  exit 1
fi
