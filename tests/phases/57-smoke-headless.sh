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
# 1.0-108 — O ALVO DO JUÍZO (a prova da run 46054558327: a porteira exporta
# CARGO_TARGET_DIR para o cache do build compartilhado das fases — o build
# release daqui NASCE nele, não no target/ do repo; quem pergunta pelo
# binário honra o alvo do cargo que o pariu)
BINS="${CARGO_TARGET_DIR:-$CRATES/target}/release"

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
# o shim: os bins da casa resolvem para os BINÁRIOS COMPILADOS (a prova da
# run 46056062240: o daemon chamado por PATH morria 'command not found' —
# o shim precisa cobrir TODOS os executáveis que a sessão invoca por nome)
ln -sf "$BINS/craft-pick" "$SMOKE/shim/craft-pick"
ln -sf "$BINS/elite-daemon" "$SMOKE/shim/elite-daemon"
ln -sf "$BINS/elite-daemon" "$SMOKE/shim/craft-doctor"
ln -sf "$BINS/craft-bar-rs" "$SMOKE/shim/craft-bar-rs"
ln -sf "$BINS/craft-dock-rs" "$SMOKE/shim/craft-dock-rs"
export HOME="$HOMES"
export XDG_RUNTIME_DIR="$XDG"
export PATH="$SMOKE/shim:$REPO/elite/airootfs/usr/local/bin:$PATH"
export WLR_BACKENDS=headless
export WLR_LIBINPUT_NO_DEVICES=1
export WLR_RENDERER=pixman
export GSK_RENDERER=cairo
export NO_AT_BRIDGE=1
# 1.0-109 — o GTK4 sem o bus de acessibilidade do runner (a casa não usa
# o a11y no juízo; sem isso o GtkApplication chora o bus ausente)
export GTK_A11Y=none

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

# 1.0-109 — OS MESTRES DO SKEL NO $HOME (a validação REAL da diretriz:
# o config.json/style.css do swaync e o style.css do swayosd são julgados
# EM CARNE — inválido = o residente morre = o contrato da fase falha; o
# 'swaync SAIU exit status: 1' e o 'COULD NOT FIND CSS FILE!' do dump
# morrem aqui, com as peles do pacote na mesa)
mkdir -p "$HOMES/.config/swaync" "$HOMES/.config/swayosd" "$HOMES/.config/hypr"
cp -p "$REPO/elite/airootfs/etc/skel/.config/swaync/config.json" \
      "$HOMES/.config/swaync/config.json" 2>/dev/null || true
cp -p "$REPO/elite/airootfs/etc/skel/.config/swaync/style.css" \
      "$HOMES/.config/swaync/style.css" 2>/dev/null || true
cp -p "$REPO/elite/airootfs/etc/skel/.config/swayosd/style.css" \
      "$HOMES/.config/swayosd/style.css" 2>/dev/null || true
# 1.0-109-b — O MESTRE DO LOCK TAMBÉM (a prova da run 46084597503: o
# craft-lock corria o caminho SEM conf — no rig de verdade o $HOME tem o
# hyprlock.conf do skel/rice; o juízo de agora veste o caminho REAL: o
# sed do wallpaper, o conf efêmero e as flags auditadas em carne)
cp -p "$REPO/elite/airootfs/etc/skel/.config/hypr/hyprlock.conf" \
      "$HOMES/.config/hypr/hyprlock.conf" 2>/dev/null || true

# a sessão da casa (o daemon lança a família toda — o spawn da barra
# pode falhar sem layer-shell aqui, a sessão SEGUE de pé: o contrato
# desta fase é o DAEMON)
daemon_err="$SMOKE/daemon.err"
# 1.0-109 — A SESSÃO VESTE O BUS DE VERDADE (o juízo do swaync dono de
# org.freedesktop.Notifications e do ✓ ambiente do doctor precisa de uma
# session bus REAL): o dbus-run-session nasce o bus, o endereço mora no
# papel (as provas de fora falam com ELE) e o systemd do usuário (quando
# o runner o deixa subir) recebe o ambiente pelo
# dbus-update-activation-environment — a MESMA ordem do autostart da casa
TEM_DBUS=0
if command -v dbus-run-session >/dev/null 2>&1; then
    dbus-run-session -- bash -c '
        printf "%s\n" "$DBUS_SESSION_BUS_ADDRESS" > '"$XDG"'/dbus.addr
        # o MEJOR equivalente do berço no container (o systemd --user
        # recusa fora do boot dele: "not booted with systemd" — no rig
        # real o autostart veste o --systemd; aqui a ativação do dbus
        # recebe o ambiente da sessão — a MESMA ordem do arranque)
        dbus-update-activation-environment --systemd \
            WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=labwc:wlroots \
            >/dev/null 2>&1 || true
        exec elite-daemon session
    ' >"$daemon_err" 2>&1 &
    DAEMON_PID=$!
    TEM_DBUS=1
else
    elite-daemon session >"$daemon_err" 2>&1 &
    DAEMON_PID=$!
fi
bus_sock="$XDG/elite/bus.sock"
_sock_ok=0
for _ in $(seq 1 40); do
    [ -S "$bus_sock" ] && { _sock_ok=1; break; }
    kill -0 "$DAEMON_PID" 2>/dev/null || break
    sleep 0.5
done
if [ "$_sock_ok" = 1 ]; then
    t_ok "elite-daemon session: o bus.sock ligou no headless"
    # 1.0-109 — O ENDEREÇO DO BUS na mão de TODO o resto da fase (o GTK
    # dos seletores precisa da session bus do dbus-run-session — sem ela
    # o GtkApplication tenta o autolaunch do X11 e morre)
    if [ "$TEM_DBUS" = 1 ] && [ -f "$XDG/dbus.addr" ]; then
        export DBUS_SESSION_BUS_ADDRESS
        DBUS_SESSION_BUS_ADDRESS="$(cat "$XDG/dbus.addr")"
    fi
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

# O CRAFT-DOCTOR na sessão viva (o elo argv0 vira o diagnóstico). Com o
# BUS DE VERDADE de pé, os diagnósticos da dose são VERDES NA CARNE: o
# ✓ ambiente (a canônica do systemctl/propriedade — o réu do dump) e o
# ✓ notify (o swaync dono das notificações) são CONTRATADOS
if [ "$TEM_DBUS" = 1 ] && [ -f "$XDG/dbus.addr" ]; then
    export DBUS_SESSION_BUS_ADDRESS
    DBUS_SESSION_BUS_ADDRESS="$(cat "$XDG/dbus.addr" 2>/dev/null || printf '%s' "$DBUS_SESSION_BUS_ADDRESS")"
    # o juízo do ambiente exige o systemd do usuário de pé (o container
    # do runner NÃO tem um — "not booted with systemd"; o rig real tem:
    # o contrato veste onde o juiz existe, o pulo é honesto onde não)
    if systemctl --user show-environment >/dev/null 2>&1; then
        _doc_out="$(craft-doctor 2>/dev/null || true)"
        case "$_doc_out" in
            *"✓ ambiente"*)
                t_ok "doctor: ✓ ambiente no bus de verdade (WAYLAND_DISPLAY/XDG_CURRENT_DESKTOP lidos — o réu do dump morre)"
                ;;
            *)
                t_fail "doctor: ✓ ambiente no bus de verdade" "a sonda não leu o ambiente: $(printf '%s' "$_doc_out" | grep ambiente | head -1)"
                ;;
        esac
    else
        t_skip "doctor: ✓ ambiente no bus de verdade" "sem systemd do usuário neste container (o rig real veste o juízo — o autostart exporta no boot dele)"
    fi
    _doc_out="$(craft-doctor 2>/dev/null || true)"
    case "$_doc_out" in
        *"✓ notify"*)
            t_ok "doctor: ✓ notify (org.freedesktop.Notifications tem dono — o swaync supervisionado)"
            ;;
        *"✗ notify"*)
            t_fail "doctor: ✓ notify" "$(printf '%s' "$_doc_out" | grep notify | head -1)"
            ;;
        *)
            t_skip "doctor: ✓ notify" "sem linha de notify no relatório (o ambiente não deixou)"
            ;;
    esac
fi
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

# ── 4. O SWAYNC DONO DAS NOTIFICAÇÕES NO BUS DE VERDADE (a diretriz:
#      validar em labwc headless até o busctl --user get-name-owner
#      responder SEM exit status 1 — o 'swaync SAIU exit status: 1' do
#      dump morre com as peles do skel julgadas em carne). 1.0-109-b — O
#      JUÍZO DE OBSERVAÇÃO VEM ANTES DO JUÍZO DO LOCK (a prova da run
#      46084597503: este contrato corria DEPOIS do lock e o réu vinha
#      POLUÍDO — o daemon.err terminava no craft-doctor (bus.cliente 4)
#      sem NENHUMA voz depois, e o rc≠0 do busctl não distinguia o nome
#      órfão do BUS morto; agora a diferença é cirúrgica: falha AQUI = o
#      réu é a central; passa aqui e a casa cai no lock adiante = o réu
#      mora no caminho do lock) ────────────────────────────────────────
if [ "$TEM_DBUS" = 1 ] && [ -f "$XDG/dbus.addr" ]; then
    export DBUS_SESSION_BUS_ADDRESS
    DBUS_SESSION_BUS_ADDRESS="$(cat "$XDG/dbus.addr" 2>/dev/null || printf '%s' "$DBUS_SESSION_BUS_ADDRESS")"
    if ! command -v busctl >/dev/null 2>&1; then
        t_skip "swaync: dono das notificações" "busctl ausente (o systemd do runner traz — o Canal veste o juízo)"
    elif command -v swaync >/dev/null 2>&1; then
        # o dono do nome (o residente supervisionado subiu com as peles do
        # skel — o config.json inválido o mataria e o nome ficaria órfão).
        # 1.0-109-c — O VERBO DE VERDADE DO BUSCTL (a prova da run
        # 46086860241: o 'get-name-owner' NUNCA foi verbo do busctl — 'Unknown
        # command verb' em TODAS as 40 tentadas, com dbus/daemon/swaync VIVOS
        # no instante; o contrato nascera TORTO na 1.0-109): o dono é o
        # MÉTODO GetNameOwner do org.freedesktop.DBus, chamado na CARNE —
        # rc 0 com o dono na mão, rc≠0 com 'no such name' no stderr. O
        # stderr da tentativa VIAJA com a falha (o rc nu não distingue
        # 'sem dono' de 'bus morto')
        _dono=1
        _berr=""
        for _ in $(seq 1 40); do
            if _berr="$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications 2>&1)"; then
                _dono=0
                break
            fi
            sleep 0.5
        done
        if [ "$_dono" = 0 ]; then
            t_ok "swaync: DONO de org.freedesktop.Notifications no bus de verdade ($(printf '%s' "$_berr" | head -c 40) — o config.json/style.css do skel são VÁLIDOS, a central não morre)"
        else
            # 1.0-109-b — O RÉU COM CARA E NOME: o stderr do busctl, os
            # VIVOS do instante e a última fala da central no bars.log (a
            # run 46084597503 julgava às cegas: 'segue rc≠0' e nada mais)
            _bus_vivo="MORTO"; pgrep -x dbus-daemon >/dev/null 2>&1 && _bus_vivo="vivo"
            _dae_vivo="MORTO"; pgrep -x elite-daemon >/dev/null 2>&1 && _dae_vivo="vivo"
            _swy_vivo="MORTO"; pgrep -x swaync >/dev/null 2>&1 && _swy_vivo="vivo"
            t_fail "swaync: dono de org.freedesktop.Notifications" \
                "busctl rc≠0 em 20s (stderr do busctl: $(printf '%s' "$_berr" | head -c 120)) · vivos no instante: dbus=${_bus_vivo} daemon=${_dae_vivo} swaync=${_swy_vivo} · daemon.err: $(tail -6 "$daemon_err" 2>/dev/null | tr '\n' ' ') · bars.log: $(tail -4 "$HOMES/.cache/elite/bars.log" 2>/dev/null | tr '\n' ' ')"
        fi
    else
        t_skip "swaync: dono das notificações" "swaync ausente — o Canal veste o juízo (tests.yml)"
    fi
    # o OSD com a PELE (o --style do $HOME só nasce quando o arquivo
    # existe — o 'COULD NOT FIND CSS FILE!' do dump é a ausência de pele)
    if command -v swayosd-server >/dev/null 2>&1; then
        sleep 1
        if pgrep -x swayosd-server >/dev/null 2>&1; then
            if grep -q "COULD NOT FIND CSS FILE" "$HOMES/.cache/elite/bars.log" 2>/dev/null; then
                t_fail "swayosd: o OSD vivo SEM o lamento do CSS" "o bars.log carrega o COULD NOT FIND CSS FILE de era"
            else
                t_ok "swayosd: o OSD vivo com a PELE do $HOME (o --style existe — o lamento do dump morre)"
            fi
        else
            t_skip "swayosd: o OSD vivo" "o swayosd-server não subiu neste ambiente (a falha da central acima nomeia o réu se for o caso)"
        fi
    fi
else
    t_skip "swaync: dono das notificações" "dbus-run-session ausente — o Canal veste o juízo (tests.yml)"
fi

# ── 5. O TOGGLE DA INSTÂNCIA ÚNICA DO PICK (a diretriz 1.0-109: outro
#      pick VIVO cai com SIGTERM — MESMO título = toggle que sai LIMPO,
#      OUTRO menu = substituição na hora) ─────────────────────────────────
"$BINS/craft-pick" -T "Teste" a b >/dev/null 2>&1 &
for _ in $(seq 1 40); do pgrep -x craft-pick >/dev/null 2>&1 && break; sleep 0.25; done
if pgrep -x craft-pick >/dev/null 2>&1; then
    _tog_rc=0
    "$BINS/craft-pick" -T "Teste" a b >/dev/null 2>&1 || _tog_rc=$?
    sleep 0.4
    if [ "$_tog_rc" = 0 ] && ! pgrep -x craft-pick >/dev/null 2>&1; then
        t_ok "pick: o MESMO título é TOGGLE (o 2º fecha o 1º e sai limpo exit 0 — zero pick no /proc)"
    else
        t_fail "pick: o MESMO título é toggle" "rc=$_tog_rc e $(pgrep -x craft-pick | wc -l | tr -d ' ') pick(s) vivo(s) — o toggle da diretriz não vestiu"
        pkill -TERM -x craft-pick 2>/dev/null || true
    fi
else
    t_fail "pick: o TOGGLE parte do 1º vivo" "o pick de mesmo título não nasceu (o contrato de abertura acima nomeia o réu)"
fi
# OUTRO título: SUBSTITUI — o velho cai, o novo fica VIVO na tela
"$BINS/craft-pick" -T "Teste" a b >/dev/null 2>&1 &
for _ in $(seq 1 40); do pgrep -x craft-pick >/dev/null 2>&1 && break; sleep 0.25; done
"$BINS/craft-pick" -T "OutroMenu" c d >/dev/null 2>&1 &
sleep 0.8
if pgrep -x craft-pick >/dev/null 2>&1; then
    t_ok "pick: OUTRO menu é SUBSTITUIÇÃO (o velho cai, o novo veste na hora)"
    pkill -TERM -x craft-pick 2>/dev/null || true
else
    t_fail "pick: OUTRO menu é substituição" "nenhum pick vivo após o 2º pedido de outro título"
fi
sleep 0.4

# ── 6. A VIDA DA CASA ANTES DO LOCK (1.0-109-b — a rede da run
#      46084597503: a morte do daemon era SILENCIOSA — nenhum 'SAIU',
#      nenhum 'COMPOSITOR caiu', o daemon.err parava no craft-doctor;
#      três postes de vida separam os suspeitos: os menus do pick, o
#      caminho do lock e o silêncio de depois) ──────────────────────────
if pgrep -x elite-daemon >/dev/null 2>&1; then
    t_ok "sessão: o elite-daemon vivo antes do lock (os menus do pick não derrubam a casa)"
else
    t_fail "sessão: o elite-daemon vivo antes do lock" \
        "o daemon já morreu no caminho dos menus (as últimas 8 do daemon.err: $(tail -8 "$daemon_err" 2>/dev/null | tr '\n' ' '))"
fi

# ── 7. O HYPRLOCK VIVO NO HEADLESS (a auditoria das flags de 1.0-109
#      paga o juízo EXECUTIVO: o réu do idle.log era a flag inválida que
#      abortava ANTES de mapear — 'lock não nasceu em 15s'. O labwc fala
#      ext-session-lock-v1: o craft-lock tem que pôr o hyprlock VIVO no
#      /proc com as flags auditadas do --help). 1.0-109-b — O STDERR DO
#      NASCIMENTO NA MESA (a run 46084597503 corria o craft-lock com o
#      stderr no /dev/null: o 'não nasceu em 8s' não nomeava réu NENHUM
#      — o choro do próprio hyprlock morava no vácuo; agora ele viaja
#      com a falha, junto com a PROVA NUA do binário isolado) ────────────
if command -v hyprlock >/dev/null 2>&1; then
    # a AUDITORIA em si (o --help do binário responde — o juiz das flags)
    if hyprlock --help >/dev/null 2>&1; then
        t_ok "lock: o hyprlock --help responde (o juiz das flags auditadas)"
    else
        t_fail "lock: o hyprlock --help responde" "o juiz das flags nem nasceu (hyprlock quebrado no runner?)"
    fi
    lock_err="$SMOKE/lock.err"
    craft-lock >"$lock_err" 2>&1 &
    _lock_vivo=0
    for _ in $(seq 1 32); do
        if pgrep -x hyprlock >/dev/null 2>&1; then _lock_vivo=1; break; fi
        sleep 0.25
    done
    if [ "$_lock_vivo" = 1 ]; then
        t_ok "lock: o hyprlock MAPA no headless (as flags auditadas não abortam — o 'lock não nasceu em 15s' do dump morre)"
        # o assento da superfície (o mesmo juízo do craft-suspend) e a
        # colheita limpa da família do lock
        sleep 0.6
        pkill -TERM -x hyprlock 2>/dev/null || true
        pkill -TERM -x craft-vigil 2>/dev/null || true
        sleep 0.4
    else
        pkill -TERM -x craft-vigil 2>/dev/null || true
        # A PROVA NUA DO BINÁRIO (isola o réu: o hyprlock morre SOZINHO no
        # headless ou é o caminho do craft-lock?): o MESMO conf efêmero
        # que o craft-lock gerou (a falta dele nomeia o home), teto de 3s
        # com o KILL de resposta — vivo ao teto = o réu é o caminho do
        # craft-lock; morto antes = o stderr abaixo é a confissão do
        # PRÓPRIO binário (EGL/seat/protocolo nomeado na cara)
        _pconf="$XDG/elite-hyprlock.conf"
        [ -r "$_pconf" ] || _pconf="$HOMES/.config/hypr/hyprlock.conf"
        _prc=0
        _probe_out="$(timeout -s TERM -k 2 3 hyprlock -c "$_pconf" 2>&1)" || _prc=$?
        if pgrep -x elite-daemon >/dev/null 2>&1; then _dae_txt="vivo"; else _dae_txt="MORTO"; fi
        t_fail "lock: o hyprlock MAPA no headless" \
            "não nasceu em 8s (lock.log: $(tail -2 "$HOMES/.cache/elite/lock.log" 2>/dev/null | tr '\n' ' ') · stderr do nascimento: $(tail -4 "$lock_err" 2>/dev/null | tr '\n' ' ') · a prova nua 3s rc=$_prc: $(printf '%s' "$_probe_out" | head -c 200) · daemon: $_dae_txt)"
    fi
else
    t_skip "lock: o hyprlock vivo no headless" "hyprlock ausente — o Canal veste o juízo (tests.yml)"
fi

# ── 8. A SESSÃO SOBREVIVE AO JUÍZO DO LOCK (1.0-109-b — a rede da run
#      46084597503: o daemon terminou SEM VOZ (a última linha do
#      daemon.err era o craft-doctor de bus.cliente 4) e o BUS morreu
#      JUNTO — o dbus-run-session desce com o filho; com o poste de vida
#      de ANTES e este de DEPOIS, a janela da queda fica cercada dos
#      dois lados e o réu do lock.err acima é o mesmo crime) ─────────────
sleep 1
if pgrep -x elite-daemon >/dev/null 2>&1; then
    t_ok "sessão: o elite-daemon sobrevive ao juízo do lock (a família e o bus seguem de pé)"
else
    t_fail "sessão: o elite-daemon sobrevive ao juízo do lock" \
        "o daemon morreu SEM voz no daemon.err (as últimas 8 linhas: $(tail -8 "$daemon_err" 2>/dev/null | tr '\n' ' '))"
fi

# ── 9. O TERMINAL NÃO EMITE CARD NO SHELL SURDO (1.0-109 Etapa 2 — a
#      diretriz §2.4: scripts, pipes, subshells e testes da porteira
#      NUNCA recebem saída extra — o guarda triplo do .zshrc julga
#      interatividade ($-), TTY de verdade ([ -t 1 ]) e a fuga honesta
#      ELITE_NO_FETCH; aqui o juízo é na CARNE: o shell NÃO-interativo
#      com o .zshrc da casa acoplado NASCE MUDO) ────────────────────────
if command -v zsh >/dev/null 2>&1; then
    _fetch_casa=0
    _fetch_out=""
    # o .zshrc DO SKEL no home de juízo (o guarda da casa julgado em
    # CARNE — a MESMA escola dos mestres do swaync/swayosd/hyprlock
    # acima: o arquivo de verdade da árvore, não um mock)
    mkdir -p "$HOMES/.config/fastfetch"
    cp -p "$REPO/elite/airootfs/etc/skel/.zshrc" "$HOMES/.zshrc" 2>/dev/null || true
    cp -p "$REPO/elite/airootfs/usr/local/share/elite/fastfetch/config.jsonc" \
          "$HOMES/.config/fastfetch/config.jsonc" 2>/dev/null || true
    # o home de juízo TEM o .zshrc da casa acoplado (ZDOTDIR abaixo) — o
    # shell surdo lê ele e tem que sair SEM UMA LINHA de card
    _fetch_out="$(ZDOTDIR="$HOMES" zsh -c 'true' 2>&1)" || true
    if [ -z "$(printf '%s' "$_fetch_out" | tr -d '[:space:]')" ]; then
        t_ok "fetch: o shell NÃO-interativo nasce MUDO (o guarda do .zshrc segura o card — zero saída extra)"
    else
        t_fail "fetch: o shell NÃO-interativo nasce MUDO" "o shell surdo cospiu: $(printf '%s' "$_fetch_out" | head -c 200)"
    fi
    # o pipe também cala o card: shell INTERATIVO com stdout em PIPE não
    # é TTY — o [ -t 1 ] do guarda é o juiz (o craft-hello no PATH é a
    # PROVA de que o guarda segura: sem ele o card nasceria pelo fallback)
    _fetch_out="$(ZDOTDIR="$HOMES" PATH="$REPO/elite/airootfs/usr/local/bin:$PATH" zsh -ic 'true' 2>&1 | head -c 4000)" || true
    if ! printf '%s' "$_fetch_out" | grep -q 'Archcraft\|Arch Linux\|kernel'; then
        _fetch_casa=1
    fi
    if [ "$_fetch_casa" = 1 ]; then
        t_ok "fetch: o pipe cala o card (o [ -t 1 ] do guarda — o shell interativo SEM TTY não fala)"
    else
        t_fail "fetch: o pipe cala o card" "o shell interativo em PIPE emitiu o card (o guarda [ -t 1 ] não segurou)"
    fi
else
    t_skip "fetch: o shell surdo nasce mudo" "zsh ausente no runner — o Canal veste o juízo (tests.yml)"
fi

# a limpeza SEM órfãos (a lição do ci-runtime-smoke)
mata "$DAEMON_PID" 2>/dev/null || true
pkill -TERM -x craft-bar-rs 2>/dev/null || true
pkill -TERM -x craft-dock-rs 2>/dev/null || true
pkill -TERM -x craft-pick 2>/dev/null || true
pkill -TERM -x craft-net 2>/dev/null || true
pkill -TERM -x swaync 2>/dev/null || true
pkill -TERM -x swayosd-server 2>/dev/null || true
pkill -TERM -x hyprlock 2>/dev/null || true
pkill -TERM -x craft-vigil 2>/dev/null || true
mata "$LABWC_PID" 2>/dev/null || true
sleep 0.5
rm -rf "$SMOKE"

printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase57.txt"
exit 0
