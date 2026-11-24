#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════
# tests/session_smoke/run.sh — NÍVEL 2 DA SUTE REAL (a sessão VIVA)
# ═════════════════════════════════════════════════════════════════════════
# O fumo da sessão de verdade: roda NO RIG (ou sessão labwc de prova) com
# o sistema ACORDADO — nada de mock. O MOTOR é o craft-dump v2 (a
# telemetria 2.0 que fala o bus da casa) + os asserts finos que o papel
# não julga sozinho (comms de /proc, socket respondendo, sink analógico).
#
# O CONTRATO (o README da pasta é a lei):
#   1. ZERO legado vivo (a lista 2.0 inteira);
#   2. família nativa DE PÉ e o bus.sock RESPONDENDO ao Hello;
#   3. serviços críticos ativos (systemctl is-active);
#   4. áudio: sink default analógico (ou a escolha EXPLÍCITA do dono) e
#      volume > 0 (o piso da voz);
#   5. boot flags preservados + mitigations=off; swappiness VIVO = 180;
#      zram0 ativo;
#   6. a pele única aceita (sem erro de parse no journal da sessão).
#
# Saída: GO/NO-GO (exit 0/1) — cada réu nomeado com a linha do papel.
# Uso: bash tests/session_smoke/run.sh   (no rig do dono ou sessão de prova)
# ═════════════════════════════════════════════════════════════════════════
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
REPO="$(pwd)"

OK=0; FAIL=0
t_ok()  { printf '  ✓ %s\n' "$1"; OK=$((OK+1)); }
t_fail() { printf '  ✗ %s — %s\n' "$1" "${2:-sem detalhe}"; FAIL=$((FAIL+1)); }

printf '══ SESSION SMOKE · a sessão viva (nível 2 da suíte real) ══\n'
printf '  repo: %s · uid: %s\n\n' "$REPO" "$(id -u)"

# ── 0. o motor: o craft-dump v2 (binário da casa — sem ele, o fumo não finge)
DUMP=""
for c in /usr/local/bin/craft-dump "$HOME/.cargo/bin/craft-dump"; do
    [ -x "$c" ] && DUMP="$c" && break
done
if [ -z "$DUMP" ] && command -v cargo >/dev/null 2>&1; then
    # a via do cargo local (desenvolvimento): o rig usa o do pacote
    printf '  (compilando o craft-dump v2 da árvore — o rig usa o do pacote)\n'
    ( cd crates && CARGO_TARGET_DIR=/tmp/elite-smoke cargo build -q -p craft-dump-rs --no-default-features 2>/dev/null ) || true
    [ -x /tmp/elite-smoke/debug/craft-dump ] && DUMP=/tmp/elite-smoke/debug/craft-dump
fi
[ -n "$DUMP" ] && [ -x "$DUMP" ] \
    && t_ok "o motor da telemetria v2 existe ($DUMP)" \
    || { t_fail "o motor da telemetria v2" "craft-dump ausente — a dose não instalou?"; }

# ── 1. ZERO legado (a lista 2.0 inteira contra os comms VIVOS)
LEGADOS_VIVOS=""
for alvo in waybar craft-audio craft-bars craft-connect craft-pin-pick craft-menu craft-player craft-drawer craft-power craft-logout craft-menu-dismiss craft-audio-route craft-toplevel swayidle; do
    if pgrep -x "$alvo" >/dev/null 2>&1; then
        LEGADOS_VIVOS="$LEGADOS_VIVOS $alvo"
    fi
done
[ -z "$LEGADOS_VIVOS" ] \
    && t_ok "zero legado vivo (a lista 2.0 inteira)" \
    || t_fail "zero legado vivo" "réus:$LEGADOS_VIVOS"

# ── 2. a família nativa de pé + o bus RESPONDENDO
FALTA_FAMILIA=""
for membro in elite-daemon craft-bar-rs craft-dock-rs; do
    pgrep -x "$membro" >/dev/null 2>&1 || FALTA_FAMILIA="$FALTA_FAMILIA $membro"
done
[ -z "$FALTA_FAMILIA" ] \
    && t_ok "família nativa de pé (daemon + barra + dock)" \
    || t_fail "família nativa de pé" "ausentes:$FALTA_FAMILIA"

BUS="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/elite/bus.sock"
if [ -S "$BUS" ]; then
    t_ok "o bus.sock existe ($BUS)"
    # o Hello responde? (o quadro 4B+JSON — o probe é o próprio dump v2:
    # a linha 'bus.sock VIVO' do papel é a resposta de verdade)
    if [ -n "$DUMP" ] && "$DUMP" 2>/dev/null | grep -q 'bus.sock VIVO'; then
        t_ok "o bus.sock RESPONDE (o snapshot chegou ao papel)"
    else
        t_fail "o bus.sock responde" "o socket existe mas o dump não colheu estado (daemon mudo?)"
    fi
else
    t_fail "o bus.sock existe" "$BUS ausente — o elite-daemon não ligou o fio"
fi

# ── 3. serviços críticos ATIVOS (is-active — o estado de verdade)
if command -v systemctl >/dev/null 2>&1; then
    SERVICO_MORTO=""
    for svc in NetworkManager bluetooth coolercontrold scx_loader; do
        estado="$(systemctl is-active "$svc" 2>/dev/null || echo dead)"
        [ "$estado" = "active" ] || SERVICO_MORTO="$SERVICO_MORTO $svc($estado)"
    done
    [ -z "$SERVICO_MORTO" ] \
        && t_ok "serviços críticos ativos (NM · BT · cooler · scx)" \
        || t_fail "serviços críticos ativos" "réus:$SERVICO_MORTO"
else
    printf '  ⚠ systemctl ausente (sessão de prova sem systemd) — pulado HONESTO\n'
fi

# ── 4. áudio: o default analógico (ou a escolha EXPLÍCITA) e volume > 0
if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    SINK="$(pactl info 2>/dev/null | sed -n 's/^Default Sink: //p' | head -1)"
    if [ -f "$HOME/.config/elite/audio-hdmi-ok" ]; then
        t_ok "áudio: o dono QUER o HDMI (o marcador fala — a escolha dele é a lei)"
    elif echo "$SINK" | grep -qi 'analog'; then
        t_ok "áudio: a analógica é o default ($SINK)"
    else
        t_fail "áudio: a analógica é o default" "default atual: ${SINK:-?}"
    fi
    VOL="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print $2}')"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$VOL" <<'PYV' && t_ok "áudio: volume > 0 (o piso da voz)" || t_fail "áudio: volume > 0 (o piso da voz)" "vol=${VOL:-?}"
import sys
try:
    v = float(sys.argv[1].rstrip('%'))
    sys.exit(0 if v > 0.001 else 1)
except Exception:
    sys.exit(1)
PYV
    else
        case "${VOL:-}" in 0.00|0.0|"") t_fail "áudio: volume > 0" "vol=${VOL:-?}" ;; *) t_ok "áudio: volume > 0 ($VOL)" ;; esac
    fi
else
    printf '  ⚠ pactl indisponível — áudio pulado HONESTO (rig real julga)\n'
fi

# ── 5. boot + tuning vivos (o cmdline E o sysctl de verdade)
CMDLINE="$(cat /proc/cmdline 2>/dev/null || true)"
for par in mitigations=off nowatchdog amdgpu.ppfeaturemask=0xffffffff ntsync; do
    echo "$CMDLINE" | grep -qw "${par%%=*}" || true
    if echo "$CMDLINE" | tr ' ' '\n' | grep -q "^${par}$" || echo "$CMDLINE" | tr ' ' '\n' | grep -q "^${par%%=*}="; then
        t_ok "boot: $par PRESENTE"
    else
        t_fail "boot: $par" "ausente do cmdline vivo"
    fi
done
SWAP="$(cat /proc/sys/vm/swappiness 2>/dev/null || echo ?)"
[ "$SWAP" = "180" ] \
    && t_ok "tuning: vm.swappiness vivo = 180" \
    || t_fail "tuning: vm.swappiness vivo = 180" "atual: $SWAP"
[ -e /sys/block/zram0/disksize ] && [ "$(cat /sys/block/zram0/disksize 2>/dev/null)" != "0" ] \
    && t_ok "tuning: zram0 ativo" \
    || t_fail "tuning: zram0 ativo" "ausente ou tamanho 0"

# ── 6. a pele única: sem erro de parse CSS no journal da sessão
if command -v journalctl >/dev/null 2>&1 && journalctl -b --no-pager >/dev/null 2>&1; then
    if journalctl -b --no-pager 2>/dev/null | grep -qE 'craft-(bar|dock)-rs.*(failed to parse|CSS parse|does not exist)'; then
        t_fail "a pele única parseia" "erro de parse no journal (ver journalctl -b | grep -i css)"
    else
        t_ok "a pele única parseia (zero erro de CSS no journal do boot)"
    fi
else
    printf '  ⚠ journalctl indisponível — pele pulada HONESTO\n'
fi

# ── veredito
printf '\n══ VEREDICTO: %d ok · %d falhas ══\n' "$OK" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
    printf 'GO\n'
    exit 0
fi
printf 'NO-GO\n'
exit 1
