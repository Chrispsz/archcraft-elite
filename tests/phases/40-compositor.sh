#!/usr/bin/env bash
# tests/phases/40-compositor.sh — FASE 4 · INTEGRIDADE DO COMPOSITOR (Fase 2)
# ══════════════════════════════════════════════════════════════════════════
# O labwc REJEITA o menu.xml inteiro quando ele quebra (a era do menu de
# 3 itens: texto órfão fora de tag atravessou 4 eras porque o juízo era
# só "bem-formado") e o rc.xml com bind fantasma é tecla morta na cara do
# dono. Esta fase é o juízo ESTRITO que a casa prometeu no cabeçalho do
# menu.xml (regra 1 do contrato v1.6.3, agora executiva):
#
#   1. XML ESTRITO — menu.xml + rc.xml parseiam (parser real, não olho);
#      menu SEM texto órfão fora de tag (a gramática E146);
#   2. EXECUTE REAL — TODO <action name="Execute" command="X"> resolve o
#      binário principal em packages.add ∪ /usr/local/bin ∪ compilados do
#      molde (∪ aliases de split package ∪ allowlist base) — o debloat
#      nunca mais quebra item em silêncio (o réu craft-drawer da era não
#      volta);
#   3. ÍCONE PROIBIDO — nenhum <item> carrega atributo de ícone (regra 2
#      v2.2 do dono: o menu é TEXTO PURO);
#   4. FÓSSIL BANIDO — nenhum Execute aponta para a era aposentada
#      (craft-drawer/craft-bars/craft-connect/craft-menu/waybar…).
# ══════════════════════════════════════════════════════════════════════════
set -uo pipefail
source "$(dirname "$0")/../lib/core.sh"

echo "  ── FASE 4 · COMPOSITOR — o labwc nunca herda arquivo quebrado ──"

SKEL="elite/airootfs/etc/skel/.config/labwc"
MENU="$SKEL/menu.xml"
RC="$SKEL/rc.xml"
BIN="elite/airootfs/usr/local/bin"
PKGS="elite/packages.add"
BS=".ci/build.sh"

# ── o juízo estrito (o parser é o juiz — E146/E107) ──────────────────────
xml_ok "menu.xml parseia (parser real)" "$MENU"
xml_ok "rc.xml parseia (parser real)" "$RC"
menu_ok "menu.xml SEM texto órfão fora de tag (E146)" "$MENU"

# ── regra 2 v2.2: o menu é TEXTO PURO ────────────────────────────────────
if grep -qE '<item[^>]*icon[^=]*=' "$MENU"; then
    t_fail "menu: nenhum item carrega atributo de ícone (v2.2)" "$(grep -nE '<item[^>]*icon' "$MENU" | head -2)"
else
    t_ok "menu: nenhum item carrega atributo de ícone (v2.2 — texto puro)"
fi

# ── a resolução executiva de TODO Execute (1.0-103 — o heredoc python
#    morre; o JUIZ DE CASA veste a gramática inteira: sh -c, for b in,
#    foot -e, pipes — os wrappers não enganam o juízo) ────────────────
if [ -n "${ELITE_JUDGE:-}" ]; then
    RESOLUCAO="$("$ELITE_JUDGE" exec-resolve "$MENU" "$RC" "$BIN" "$PKGS" "$BS" 2>/dev/null)"
    if printf '%s' "$RESOLUCAO" | head -1 | grep -q '^EXECUTED='; then
        total="$(printf '%s\n' "$RESOLUCAO" | head -1 | cut -d= -f2)"
        if printf '%s\n' "$RESOLUCAO" | tail -n +2 | head -1 | grep -q '^CLEAN$'; then
            t_ok "integridade de Execute: $total comandos, TODOS resolvem binário real (menu ∪ rc)"
        else
            reus="$(printf '%s\n' "$RESOLUCAO" | tail -n +2 | head -6 | tr '\n' ' · ')"
            # 1.0-104 — o nome ASCII (a lente 0.11 lê "réus" como ${r}éus:
            # SC2154 + o réu cortado no meio da expansão — o nome da casa
            # veste ASCII no código, o sotaque fica na prosa)
            t_fail "integridade de Execute: $total comandos apontam para binário real" "$reus"
        fi
    else
        t_fail "integridade de Execute (o juiz de casa correu)" "falha no resolvedor: $(printf '%s' "$RESOLUCAO" | head -2)"
    fi
else
    t_skip "integridade de Execute (o juiz de casa)" "craft-audit ausente no ambiente (cargo fora — juízo do CI)"
fi

# ── o fantasma clássico NUNCA volta (a mordaça explícita do réu histórico)
if grep -q 'craft-drawer' "$MENU" "$RC" 2>/dev/null; then
    t_fail "comandos fantasmas: craft-drawer banido do menu/rc" "$(grep -n 'craft-drawer' "$MENU" "$RC" | head -2)"
else
    t_ok "comandos fantasmas: craft-drawer banido do menu/rc (o réu da era)"
fi

# ── o rc.xml fala os verbos da casa (amostra do contrato da interface) ───
for par in 'craft-apps|a gaveta com toggle' 'pwvucontrol|o mixer' \
           'nm-connection-editor|o editor de redes' 'blueman-manager|o bluetooth' \
           'craft-lock|o lock' 'craft-shot|a captura'; do
    bin="${par%%|*}"; papel="${par##*|}"
    if grep -q "$bin" "$RC"; then
        t_ok "rc.xml: $papel ($bin) é verbo de primeira classe"
    else
        t_fail "rc.xml: $papel ($bin)" "o bind morreu — tecla fantasma"
    fi
done

printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase40.txt"
exit 0
