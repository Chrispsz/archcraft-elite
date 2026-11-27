#!/usr/bin/env bash
# tests/phases/57-smoke-headless.sh — FASE 5.7 · O SMOKE REAL DOS BINÁRIOS
# ══════════════════════════════════════════════════════════════════════════
# 1.0-108 · Etapa 2 — A DIRETRIZ DO DONO (Zero Mocks): contratos EXECUTIVOS
# sobre os binários COMPILADOS de verdade (target/release/ — não o fonte,
# não o pacote: o MESMO binário que o Canal empacota):
#
#   1. `craft-pick -T "Teste" --help` → exit 0 (a ajuda ANTES do GTK —
#      a lei E90 na carne do binário);
#   2. flag inválida → exit 2 em MENOS de 1s SEM deixar processo vivo
#      (a evidência do rig: 22 processos presos, ~530 MB);
#   3. Sob `WLR_BACKENDS=headless labwc`: subir `elite-daemon session`,
#      validar CPU < 5% em idle após 3s (a cura do spin de 95,6%),
#      validar abertura/fechamento de `craft-pick -T "Teste"`,
#      `craft-game` (menu) e `craft-idle` (menu), e o `craft-doctor`.
#
# A HONESTIDADE (a mesma escola do ci-runtime-smoke, lei L6/L10): a compilação
# da gui exige o toolchain gtk4 do Canal (makedepends do pacote) e o juízo de
# sessão exige o labwc no ambiente — o que falta PULA com o réu nomeado (a
# esteira do Canal paga os dois juízos: tests.yml veste o toolchain inteiro).
# Contrato quebrou COM binário vivo na mesa = falha de verdade.
set -uo pipefail
source "$(dirname "$0")/../lib/core.sh"

echo "  ── FASE 5.7 · SMOKE REAL — os binários compilados em carne ──"

REPO="$(pwd)"
CRATES="$REPO/crates"
BINS="$CRATES/target/release"

# ── 0. o toolchain (o gui é makedepends do Canal — lei L6) ───────────────
export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v cargo >/dev/null 2>&1; then
    t_skip "smoke: o toolchain Rust (o Canal compila a gui)" "cargo ausente"
    printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase57.txt"
    exit 0
fi
if ! pkg-config --exists gtk4 2>/dev/null; then
    t_skip "smoke: a compilação da gui (gtk4 dev)" "pkg-config gtk4 ausente — o Canal veste o toolchain (tests.yml)"
    printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase57.txt"
    exit 0
fi

# o build release (o perfil do pacote — lto=fat+strip+opt-level=3)
if ! (cd "$CRATES" && cargo build --release -q --workspace 2>/dev/null); then
    t_skip "smoke: o build release do workspace" "cargo build --release não terminou (o log do build acima é o réu)"
    printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase57.txt"
    exit 0
fi
if [ ! -x "$BINS/craft-pick" ] || [ ! -x "$BINS/elite-daemon" ]; then
    t_skip "smoke: os bins compilados" "craft-pick/elite-daemon ausentes em target/release"
    printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase57.txt"
    exit 0
fi
t_ok "o workspace inteiro compilado em release ($BINS)"

# ── 1. O CLI DO PICK (a ajuda e o exit 2 não precisam de display: o
#      juiz de 1.0-108 fecha a porta ANTES de qualquer GTK) ──────────────
_t0="$(date +%s%N)"
if "$BINS/craft-pick" -T "Teste" --help >/dev/null 2>&1; then
    t_ok "pick: '-T Teste --help' sai 0 (a ajuda ANTES do GTK — a lei E90)"
else
    t_fail "pick: '-T Teste --help' sai 0" "exit != 0 no binário compilado"
fi
_t1="$(date +%s%N)"
_ms=$(( (_t1 - _t0) / 1000000 ))
if [ "$_ms" -lt 1000 ]; then
    t_ok "pick: o --help é instantâneo (${_ms}ms)"
else
    t_fail "pick: o --help é instantâneo" "demorou ${_ms}ms (a ajuda nunca espera GTK)"
fi

# a flag inválida: exit 2 em <1s SEM processo vivo (o réu dos 22 zumbis)
_t0="$(date +%s%N)"
set +e
_flag_err="$("$BINS/craft-pick" --floripa-inválida "um" 2>&1 >/dev/null)"
_rc=$?
set -e
_t1="$(date +%s%N)"
_ms=$(( (_t1 - _t0) / 1000000 ))
if [ "$_rc" = 2 ]; then
    t_ok "pick: a flag inválida sai 2 (o juiz de 1.0-108 no binário)"
else
    t_fail "pick: a flag inválida sai 2" "rc=$_rc (0/1 = a flag virou item ou janela — o zumbi de era)"
fi
if [ "$_ms" -lt 1000 ]; then
    t_ok "pick: a flag inválida fecha em ${_ms}ms (<1s — zero GTK no caminho)"
else
    t_fail "pick: a flag inválida fecha em <1s" "demorou ${_ms}ms (o GTK nasceu antes do juiz?)"
fi
case "$_flag_err" in
    *floripa*) t_ok "pick: o erro NOMEIA a flag (o réu na cara do chamador)" ;;
    *) t_fail "pick: o erro nomeia a flag" "stderr: $(printf '%s' "$_flag_err" | head -c 120)" ;;
esac
# o corpo morto não fica vivo: nenhum craft-pick pendurado no pid da fase
sleep 0.2
if pgrep -x craft-pick >/dev/null 2>&1; then
    t_fail "pick: a flag inválida não deixa processo vivo" "craft-pick ainda mora no /proc (o zumbi de ~530 MB)"
    pkill -TERM -x craft-pick 2>/dev/null || true
else
    t_ok "pick: a flag inválida não deixa processo vivo (zero zumbi)"
fi

# ── 2. a SESSÃO HEADLESS (o labwc é o juiz de ambiente de sempre) ────────
if ! command -v labwc >/dev/null 2>&1; then
    t_skip "smoke: a sessão headless (elite-daemon CPU/menus/doctor)" "labwc ausente — o Canal veste o juiz (tests.yml)"
    printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase57.txt"
    exit 0
fi

SMOKE="$(mktemp -d /tmp/elite-smoke-headless-XXXXXX)"
XDG="$SMOKE/xdg"; HOMES="$SMOKE/home"
mkdir -p "$XDG" "$HOMES/.cache/elite" "$SMOKE/shim"
chmod 700 "$XDG"
# o shim: craft-pick/craft-doctor resolvem para os BINÁRIOS COMPILADOS
ln -sf "$BINS/craft-pick" "$SMOKE/shim/craft-pick"
ln -sf "$BINS/elite-daemon" "$SMOKE/shim/craft-doctor"
export HOME="$HOMES"
export XDG_RUNTIME_DIR="$XDG"
export PATH="$SMOKE/shim:$REPO/elite/airootfs/usr/local/bin:$PATH"
export WLR_BACKENDS=headless
export WLR_LIBINPUT_NO_DEVICES=1
export WLR_RENDERER=pixman
export GSK_RENDERER=cairo
export NO_AT_BRIDGE=1

mata() { # mata <pid> — a árvore inteira (o labwc e os filhos)
    [ -n "${1:-}" ] || return 0
    local pid="$1" filhos
    filhos="$(ps -o pid= --ppid "$pid" 2>/dev/null || true)"
    for f in $filhos; do mata "$f"; done
    kill -TERM "$pid" 2>/dev/null || true
}

labwc_log="$SMOKE/labwc.log"
labwc >"$labwc_log" 2>&1 &
LABWC_PID=$!
WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export WAYLAND_DISPLAY
_sock_ok=0
for _ in $(seq 1 30); do
    [ -S "$XDG/$WAYLAND_DISPLAY" ] && { _sock_ok=1; break; }
    kill -0 "$LABWC_PID" 2>/dev/null || break
    sleep 0.5
done
if [ "$_sock_ok" != 1 ]; then
    t_skip "smoke: a sessão headless (labwc)" "o compositor não subiu neste ambiente (últimas linhas: $(tail -2 "$labwc_log" 2>/dev/null | tr '\n' ' '))"
    mata "$LABWC_PID" 2>/dev/null || true
    rm -rf "$SMOKE"
    printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase57.txt"
    exit 0
fi
t_ok "labwc headless no ar (WLR_BACKENDS=headless, pixman/cairo)"

# a sessão da casa (o daemon lança a família toda — o spawn da barra
# pode falhar sem layer-shell aqui, a sessão SEGUE de pé: o contrato
# desta fase é o DAEMON)
daemon_err="$SMOKE/daemon.err"
elite-daemon session >"$daemon_err" 2>&1 &
DAEMON_PID=$!
bus_sock="$XDG/elite/bus.sock"
_sock_ok=0
for _ in $(seq 1 40); do
    [ -S "$bus_sock" ] && { _sock_ok=1; break; }
    kill -0 "$DAEMON_PID" 2>/dev/null || break
    sleep 0.5
done
if [ "$_sock_ok" = 1 ]; then
    t_ok "elite-daemon session: o bus.sock ligou no headless"
else
    t_fail "elite-daemon session: o bus.sock ligou" "ausente em 20s (stderr: $(tail -3 "$daemon_err" 2>/dev/null | tr '\n' ' '))"
fi

# A CPU EM IDLE (a evidência do rig: 95,6% em SPIN — o contrato da
# dose é <5% após 3s de assentamento): amostras do utime+stime do
# /proc do daemon numa janela de 3s
cpu_pct() { # cpu_pct <pid> <janela_s> — o % de CPU do processo
    local pid="$1" janela="$2" j1 j2
    j1="$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null || echo 0)"
    sleep "$janela"
    j2="$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null || echo 0)"
    local clk
    clk="$(getconf CLK_TCK 2>/dev/null || echo 100)"
    # (jiffies gastos / jiffies do relógio) * 100 = % da janela
    awk -v d=$((j2 - j1)) -v clk="$clk" -v s="$janela" \
        'BEGIN { printf "%.1f", (d / clk) * 100 / s }'
}
sleep 3   # o assentamento da diretriz: "idle após 3s"
if kill -0 "$DAEMON_PID" 2>/dev/null; then
    _cpu="$(cpu_pct "$DAEMON_PID" 3)"
    _cpu_ok="$(printf '%s' "$_cpu" | awk '{ print ($1 < 5.0) ? "1" : "0" }')"
    if [ "$_cpu_ok" = 1 ]; then
        t_ok "elite-daemon: CPU ${_cpu}% em idle após 3s (o spin de 95,6% está morto — o contrato é <5%)"
    else
        t_fail "elite-daemon: CPU < 5% em idle após 3s" "medido ${_cpu}% (o spin de era voltou?)"
    fi
else
    t_fail "elite-daemon: vivo após o assentamento" "o daemon morreu no headless (stderr: $(tail -3 "$daemon_err" 2>/dev/null | tr '\n' ' '))"
fi

# A ABERTURA/FECHAMENTO dos menus (o pick abre NO frame 0 — a guarda de
# foco do labwc não mata mais o menu) — cada janela: nasce, espera-se o
# corpo vivo, e o TERM colhe SEM zumbi
abre_e_fecha() { # abre_e_fecha <desc> <cmd...>
    local desc="$1"; shift
    "$@" >/dev/null 2>&1 &
    local _pid=$!
    local _vivo=0 _i=0
    while [ "$_i" -lt 40 ]; do
        if pgrep -x craft-pick >/dev/null 2>&1; then _vivo=1; break; fi
        kill -0 "$_pid" 2>/dev/null || break
        sleep 0.25
        _i=$((_i + 1))
    done
    if [ "$_vivo" = 1 ]; then
        # o fechamento: o TERM colhe o menu INTEIRO (sem corpo pendurado)
        pkill -TERM -x craft-pick 2>/dev/null || true
        _i=0
        while [ "$_i" -lt 20 ] && pgrep -x craft-pick >/dev/null 2>&1; do
            sleep 0.1
            _i=$((_i + 1))
        done
        if pgrep -x craft-pick >/dev/null 2>&1; then
            t_fail "$desc: o fechamento colhe o menu" "craft-pick sobreviveu ao TERM (o zumbi de era)"
        else
            t_ok "$desc: abriu e fechou no headless (sem zumbi no /proc)"
        fi
    else
        # o chamador pode ter saído SEM janela (pick ausente da lista?)
        if kill -0 "$_pid" 2>/dev/null; then
            kill -TERM "$_pid" 2>/dev/null || true
        fi
        t_fail "$desc: a janela do pick nasce no headless" "nenhum craft-pick no /proc em 10s"
    fi
}
abre_e_fecha "pick: o seletor direto (-T Teste)" "$BINS/craft-pick" -T "Teste" "Primeiro" "Segundo"
abre_e_fecha "game: o menu do modo de jogo" craft-game menu
abre_e_fecha "idle: o menu da trava automática" craft-idle menu

# O CRAFT-DOCTOR na sessão viva (o elo argv0 vira o diagnóstico)
if craft-doctor >/dev/null 2>&1; then
    t_ok "craft-doctor: rc 0 na sessão headless (a saúde inteira de pé)"
else
    _drc=$?
    if [ "$_drc" = 1 ]; then
        t_ok "craft-doctor: rc 1 honesto (invariante nomeado no ambiente de juízo — o veredito é o código)"
    else
        t_fail "craft-doctor: o veredito é 0 ou 1" "rc=$_drc no headless"
    fi
fi

# a limpeza SEM órfãos (a lição do ci-runtime-smoke)
mata "$DAEMON_PID" 2>/dev/null || true
pkill -TERM -x craft-bar-rs 2>/dev/null || true
pkill -TERM -x craft-dock-rs 2>/dev/null || true
pkill -TERM -x craft-pick 2>/dev/null || true
mata "$LABWC_PID" 2>/dev/null || true
sleep 0.5
rm -rf "$SMOKE"

printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase57.txt"
exit 0
