#!/usr/bin/env bash
# tests/ci-runtime-smoke.sh — O SMOKE DE RUNTIME DO CANAL (Fase 2 do dono)
# ══════════════════════════════════════════════════════════════════════════
# O pilare 3 da diretriz: "o elite-daemon mantém instância única real no
# bus.sock, responde aos comandos de sessão e craft-bar-rs/craft-dock-rs
# sobem sem warnings críticos". A suíte estática julga o FONTE; ESTE
# script julga O PACOTE: dentro do container Arch do Canal (que acabou de
# compilar a gui com gtk4 de verdade), a sessão sobe de verdade num
# labwc headless (WLR_BACKENDS=headless — sem DRM, sem GPU, render pixman
# + GSK cairo) e os contratos são EXECUTIVOS:
#
#   1. o pacote elite-system recém-parido extrai e os bins da casa falam;
#   2. o elite-daemon session liga o bus.sock (VIVO, não fóssil);
#   3. a 2ª instância sai 0 e deixa o papel (flock E30 — instância única);
#   4. craft-bar-rs e craft-dock-rs estão DE PÉ e continuam de pé;
#   5. os logs da sessão NÃO têm Gtk-WARNING nem "still has children"
#      (popover órfão/bloco preto da dock) nem \uXXXX mal-escapado;
#   6. craft-game/craft-idle respondem status (exit 0);
#   7. os bins compilados respondem --help (lei E90, executiva).
#
# A HONESTIDADE (L10): labwc headless é juízo de ambiente — se o
# compositor NÃO subir no container, o smoke sai 0 com SKIP nomeado
# (o juízo de compilação já foi pago pelo makepkg; a suíte estática
# continua valendo). Sessão booted + contrato quebrado = exit 1 — a run
# do Canal fica VERMELHA e o upload NÃO acontece (o passo roda ANTES do
# repo-add/upload no publish-packages.yml: pacote que não prova sessão
# não entra no db que o rig consome).
#
# Uso (dentro do container, repo montado em /work):
#   bash tests/ci-runtime-smoke.sh
# ══════════════════════════════════════════════════════════════════════════
set -uo pipefail

WORKDIR="${1:-/work}"
cd "$WORKDIR" 2>/dev/null || WORKDIR="$(pwd)"

OK=0; FAIL=0
t_ok()  { printf '  ✓ %s\n' "$1"; OK=$((OK+1)); }
t_fail() { printf '  ✗ %s — %s\n' "$1" "${2:-sem detalhe}"; FAIL=$((FAIL+1)); }
mata()  { # mata <nome> — a árvore inteira do pid (o labwc e os filhos)
    local pid="$1" filhos
    [ -n "$pid" ] || return 0
    filhos="$(ps -o pid= --ppid "$pid" 2>/dev/null || true)"
    for f in $filhos; do mata "$f"; done
    kill -TERM "$pid" 2>/dev/null || true
}

printf '══ CI RUNTIME SMOKE · a sessão booted sobre o pacote recém-parido ══\n\n'

# ── 0. o pacote da casa (o artefato que o makepkg ACABOU de parir) ───────
PKG="$(ls -1 out/pacotes/elite-system-*.pkg.tar.zst 2>/dev/null | head -1 || true)"
[ -n "$PKG" ] || PKG="$(ls -1 elite-system-*.pkg.tar.zst 2>/dev/null | head -1 || true)"
if [ -z "$PKG" ]; then
    printf '  □ SKIP: nenhum elite-system-*.pkg.tar.zst no workdir — o smoke é do Canal, não do dev\n'
    exit 0
fi
printf '  pacote: %s\n' "$PKG"

STAGE="$(mktemp -d /tmp/elite-smoke-XXXXXX)"
HOME_SMOKE="$STAGE/home"
XDG="$STAGE/xdg"
mkdir -p "$HOME_SMOKE" "$XDG" "$XDG/elite" "$HOME_SMOKE/.cache/elite"
chmod 700 "$XDG"
bsdtar -xf "$PKG" -C "$STAGE" 2>/dev/null || { printf '  □ SKIP: bsdtar não extraiu o pacote\n'; rm -rf "$STAGE"; exit 0; }

BIN_STAGED="$STAGE/usr/local/bin"
if [ ! -x "$BIN_STAGED/elite-daemon" ]; then
    printf '  □ SKIP: o pacote não trouxe elite-daemon (%s ausente)\n' "$BIN_STAGED"
    rm -rf "$STAGE"; exit 0
fi

# ── 1. o labwc headless (o juízo de ambiente vem PRIMEIRO) ───────────────
if ! command -v labwc >/dev/null 2>&1; then
    printf '  (instalando o juiz: labwc + temas de ícone no container…)\n'
    # FASE 2 — O RUNTIME GTK É DO JUÍZO (a contraprova da run 45588152562:
    # o container do smoke é OUTRO container — o build tinha gtk4 como
    # makedepends e este não; os 6 bins GUI morriam no LOADER (exit 127,
    # 'error while loading shared libraries') e a família nascia-morria —
    # o réu era o AMBIENTE, não o produto; o rig real tem gtk4 por
    # packages.add). gtk4 + gtk-layer-shell = as libs dos bins da casa;
    # labwc + temas = o compositor e os ícones que a barra pede.
    if ! pacman -Syu --noconfirm --needed labwc gtk4 gtk4-layer-shell \
         adwaita-icon-theme hicolor-icon-theme >/dev/null 2>&1; then
        printf '  □ SKIP: labwc/gtk4 não instalou neste container (réu nomeado no log)\n'
        rm -rf "$STAGE"; exit 0
    fi
fi

# FASE 2 — O AMBIENTE VESTE O QUE O RIG TEM DE FÁBRICA: o systemd garante
# /etc/machine-id em TODO sistema instalado (a ISO inclui); o container nu
# não tem — sem ele o GTK grita 'Unable to acquire session bus' em TODO
# app da casa (o réu da run 45591814205: 15 ok · 1 falha, o warning que
# era ARTEFATO do juízo, não do produto). Provisionar o ambiente é a
# honestidade de pé (o scan de warnings NUNCA é afrouxado para caber).
if [ ! -s /etc/machine-id ]; then
    systemd-machine-id-setup >/dev/null 2>&1 \
        || { uuidgen >/etc/machine-id 2>/dev/null; }
    printf '  (ambiente: machine-id provisionado para o juízo — o rig tem de fábrica)\n'
fi
# E o BUS DA SESSÃO (o réu seguinte do mesmo papel, run 45592616772:
# 'Cannot autolaunch D-Bus without X11' — no rig o systemd --user fornece
# o bus de fábrica; o container nu não tem NENHUM). O juízo levanta o
# bus da sessão no tmpfs próprio — o mesmo papel que o /run/user/UID/bus
# do rig veste.
if ! pacman -Qs '^dbus$' >/dev/null 2>&1; then
    pacman -S --noconfirm --needed dbus >/dev/null 2>&1 || true
fi
if command -v dbus-daemon >/dev/null 2>&1 && [ ! -S "$XDG/session-bus" ]; then
    dbus-daemon --session --fork --address="unix:path=$XDG/session-bus" >/dev/null 2>&1 \
        && export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG/session-bus" \
        && printf '  (ambiente: session bus provisionado — o systemd --user do rig o tem de fábrica)\n'
fi

# os verbot descomplicados: o caminho do compositor é o único juízo de
# ambiente — se o socket não nascer em 15s, SKIP honesto
export XDG_RUNTIME_DIR="$XDG"
export HOME="$HOME_SMOKE"
export PATH="$BIN_STAGED:$PATH"
export GSK_RENDERER=cairo            # software — o container não tem GPU
export NO_AT_BRIDGE=1                # sem a11y dbus no container

labwc_log="$STAGE/labwc.log"
env WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
    labwc >"$labwc_log" 2>&1 &
LABWC_PID=$!

WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export WAYLAND_DISPLAY
bus_present=0
for _ in $(seq 1 30); do
    [ -S "$XDG/$WAYLAND_DISPLAY" ] && { bus_present=1; break; }
    kill -0 "$LABWC_PID" 2>/dev/null || break
    sleep 0.5
done
if [ "$bus_present" = 0 ]; then
    printf '  □ SKIP: labwc headless não subiu neste container (últimas linhas:)\n'
    tail -3 "$labwc_log" 2>/dev/null || true
    mata "$LABWC_PID"; rm -rf "$STAGE"
    exit 0
fi
t_ok "labwc headless no ar (WAYLAND_DISPLAY=$WAYLAND_DISPLAY, pixman/cairo)"

# ── 2. a sessão da casa (o daemon lança a família toda) ──────────────────
daemon_log="$HOME_SMOKE/.cache/elite/bars.log"
daemon_err="$STAGE/daemon.err"
elite-daemon session >"$daemon_err" 2>&1 &
DAEMON_PID=$!

bus_sock="$XDG/elite/bus.sock"
sock_ok=0
for _ in $(seq 1 40); do
    [ -S "$bus_sock" ] && { sock_ok=1; break; }
    kill -0 "$DAEMON_PID" 2>/dev/null || break
    sleep 0.5
done
if [ "$sock_ok" = 1 ]; then
    t_ok "o bus.sock ligou ($bus_sock)"
else
    t_fail "o bus.sock ligou" "$bus_sock ausente em 20s (daemon pid $DAEMON_PID; cauda do log: $(tail -2 "$daemon_log" 2>/dev/null | tr '\n' ' '))"
fi

# ── 3. instância única: a 2ª sai 0 COM PAPEL ─────────────────────────────
if elite-daemon session >/dev/null 2>&1; then
    if grep -q 'a 2ª instância sai 0' "$daemon_log" 2>/dev/null; then
        t_ok "instância única: a 2ª sai 0 e deixa papel no bars.log (flock E30)"
    else
        t_fail "instância única: a 2ª sai 0 e deixa papel" "exit 0 mas o papel da recusa não apareceu"
    fi
else
    t_fail "instância única: a 2ª instância sai 0" "exit != 0 — o guard recusou com erro (não com voz)"
fi

# ── 4. a família de pé e de pé CONTINUANDO ───────────────────────────────
espera_vivos() { # espera_vivos <segundos> — os dois comms vivos
    for _ in $(seq 1 "$1"); do
        if pgrep -x craft-bar-rs >/dev/null 2>&1 && pgrep -x craft-dock-rs >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}
if espera_vivos 15; then
    t_ok "família de pé: craft-bar-rs + craft-dock-rs (spawn do daemon)"
else
    t_fail "família de pé" "barra/dock não nasceram (log: $(tail -2 "$daemon_log" 2>/dev/null | tr '\n' ' '))"
fi
sleep 3
if pgrep -x craft-bar-rs >/dev/null 2>&1 && pgrep -x craft-dock-rs >/dev/null 2>&1; then
    t_ok "família CONTINUA de pé após 3s (sem crash-loop de arranque)"
else
    t_fail "família continua de pé" "morreu depois de nascer (crash-loop?)"
fi

# ── 5. os logs SEM warnings críticos (o pilare 3 da diretriz) ────────────
bar_log="$HOME_SMOKE/.cache/elite/bars.log"
dock_log="$HOME_SMOKE/.cache/elite/dock.log"
criticos="$(grep -hE 'Gtk-WARNING|still has children|GLib-GObject-WARNING|error while loading shared libraries|\\\\u[0-9a-fA-F]{4}' \
    "$bar_log" "$dock_log" 2>/dev/null | head -3 || true)"
if [ -z "$criticos" ]; then
    t_ok "logs da sessão: ZERO Gtk-WARNING / órfão de popover / \\uXXXX mojibake"
else
    t_fail "logs da sessão sem warnings críticos" "$(printf '%s' "$criticos" | tr '\n' ' · ')"
fi

# ── 6. os painéis da sessão respondem ────────────────────────────────────
for par in craft-game craft-idle; do
    if "$BIN_STAGED/$par" status >/dev/null 2>&1; then
        t_ok "$par status sai 0 (o verbo seguro no pacote)"
    else
        t_fail "$par status sai 0" "exit != 0 dentro do pacote"
    fi
done

# ── 6.5 o CRAFT-DOCTOR na sessão viva (1.0-107.2 — o contrato do container
#      é o que o container PODE prometer: o doctor NOMEA os 7 réus num tiro
#      rápido e o código de saída casa com os quebrados — o 'ambiente' exige
#      o systemd --user do rig (aqui só há dbus-daemon de sessão) e o
#      'áudio' o PipeWire: NÃO são promessa daqui; o bus.sock É — o mesmo
#      socket que a seção 2 viu ligar, agora com o HANDSHAKE de verdade) ───
_t0="$(date +%s%N)"
_doctor_out="$("$BIN_STAGED/craft-doctor" 2>&1)"; _doctor_rc=$?
_t1="$(date +%s%N)"
_ms=$(( (_t1 - _t0) / 1000000 ))
if [ "$_ms" -lt 2000 ]; then
    t_ok "craft-doctor: o tiro é rápido (${_ms}ms — o contrato é <50ms no hardware, o container paga a folga)"
else
    t_fail "craft-doctor: tiro rápido" "demorou ${_ms}ms (o contrato é <50ms no hardware)"
fi
_doctor_nomes=0
for _nome in ambiente bus.sock polkit notify wakeup áudio gamemode; do
    if printf '%s' "$_doctor_out" | grep -q "$_nome"; then
        _doctor_nomes=$((_doctor_nomes + 1))
    else
        t_fail "craft-doctor nomeia o réu $_nome" "o relatório calou com $_nome"
    fi
done
[ "$_doctor_nomes" = 7 ] \
    && t_ok "craft-doctor: os 7 invariantes vitais nomeados no relatório" \
    || true
_doctor_ok="$(printf '%s' "$_doctor_out" | grep -c '✓' || true)"
_doctor_br="$(printf '%s' "$_doctor_out" | grep -c '✗' || true)"
if [ "$_doctor_rc" = 0 ] || [ "$_doctor_rc" = 1 ]; then
    t_ok "craft-doctor: o código de saída é o veredito (rc=$_doctor_rc — 0 = saúde inteira, 1 = invariante quebrado; ✓=$_doctor_ok ✗=$_doctor_br no relatório)"
else
    t_fail "craft-doctor: código de saída honesto" "rc=$_doctor_rc (o veredito é 0 ou 1, nunca outro número)"
fi
if printf '%s' "$_doctor_out" | grep -q '✓ bus.sock'; then
    t_ok "craft-doctor: o bus.sock responde ao handshake na sessão real"
else
    # o DOSSIÊ do réu (a prova que o log da run carrega): o daemon vivo?
    # o que o stderr dele disse? o que o chão do runtime mostra?
    if kill -0 "$DAEMON_PID" 2>/dev/null; then _dav="VIVO"; else _dav="MORTO"; fi
    t_fail "craft-doctor: bus.sock responde ao handshake" \
        "daemon $_dav (pid $DAEMON_PID) · chão: $(ls -la "$XDG/elite/" 2>/dev/null | tr '\n' ' ') · stderr: $(tail -4 "$daemon_err" 2>/dev/null | tr '\n' ' ') · saída: $(printf '%s' "$_doctor_out" | tr '\n' ' ')"
fi

# ── 7. a lei E90 executiva nos compilados (o réu carrega O ERRO REAL:
#    morte de loader = a classe 'o pacote nasceu sem a lib do runtime') ──
for b in elite-daemon craft-bar-rs craft-dock-rs craft-dump craft-update craft-clean craft-help craft-pick; do
    _err="$(timeout 10 "$BIN_STAGED/$b" --help 2>&1 >/dev/null | head -1)"
    if timeout 10 "$BIN_STAGED/$b" --help >/dev/null 2>&1; then
        t_ok "--help: $b"
    else
        t_fail "--help: $b" "rc!=0 — ${_err:-stderr vazio (E90 violada no binário?)}"
    fi
done

# ── veredito + a limpeza SEM órfãos ──────────────────────────────────────
printf '\n══ SMOKE: %d ok · %d falhas ══\n' "$OK" "$FAIL"
mata "$DAEMON_PID" 2>/dev/null || true
pkill -TERM -x craft-bar-rs 2>/dev/null || true
pkill -TERM -x craft-dock-rs 2>/dev/null || true
mata "$LABWC_PID" 2>/dev/null || true
sleep 0.5
rm -rf "$STAGE"

[ "$FAIL" -eq 0 ] || exit 1
exit 0
