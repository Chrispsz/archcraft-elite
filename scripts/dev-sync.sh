#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════
# scripts/dev-sync.sh — O HOT-RELOAD DA CASA (Fase 2 do dono)
# ══════════════════════════════════════════════════════════════════════════
# A demanda: "compilar apenas os binários alterados e reiniciar apenas a
# barra e a dock na sessão Wayland ativa, permitindo testar ajustes
# visuais ou de clique em segundos, sem makepkg nem reboot".
#
# COMO FUNCIONA (sem briga com o pacman):
#   · o cargo decide O QUE mudou (o build incremental pula o que está
#     limpo — o cargo é o juiz do mtime, nunca uma lista dupla);
#   · os binários DEV vestem ~/.local/bin (NUNCA /usr/local/bin — o
#     pacote elite-system continua dono do sistema; o pacman -Syu de
#     amanhã não apaga o teu experimento e o teu experimento não suja
#     o pacote);
#   · a troca é QUIETA: SIGTERM no comm velho → spawn do bin novo com o
#     MESMO comm → o elite-daemon ADOTA pela lei E138 (nome tem dono +
#     comm vivo = vaga Adotada; zero respawn, zero duplicata);
#   · elite-core mudou? TODA a gui é recompilada (todos bebem dele).
#
# USO:
#   dev-sync                 compila o que mudou e reinicia barra + dock
#   dev-sync bar | dock      só um dos dois
#   dev-sync --all           também as ferramentas (tools/dump/daemon)
#   dev-sync --restart-only  sem compilar (só reiniciar do ~/.local/bin)
#   dev-sync --daemon        reinicia também o elite-daemon session
#                            (os filhos vivos são ADOTADOS pelo novo —
#                            a lei E138; nada de relogin)
#   dev-sync --smoke         roda tests/session_smoke/run.sh no fim
#
# REQUISITOS do rig (uma vez só): rustup (cargo no PATH), os headers da
# casa já na ISO (gtk4, gtk-layer-shell). Nada de root.
# ══════════════════════════════════════════════════════════════════════════
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CRATES="$REPO/crates"
TARGET="${ELITE_DEV_TARGET:-$CRATES/target}"
DEV_BIN="${ELITE_DEV_BIN:-$HOME/.local/bin}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/elite"

ALVO="gui"      # bar | dock | all | tools
DO_COMPILE=1
DO_DAEMON=0
DO_SMOKE=0

uso() {
    sed -n '2,40p' "$0" | grep -E '^#( |$)' | sed 's/^# \{0,3\}//'
    exit 0
}
case "${1:-}" in
    -h|--help|uso) uso ;;
    bar)           ALVO=bar ;;
    dock)          ALVO=dock ;;
    --all)         ALVO=all ;;
    --restart-only) DO_COMPILE=0 ;;
    --daemon)      DO_DAEMON=1 ;;
    --smoke)       DO_SMOKE=1 ;;
esac
# flags podem vir em qualquer posição (dev-sync bar --smoke etc.)
for a in "$@"; do
    case "$a" in
        --restart-only) DO_COMPILE=0 ;;
        --daemon)       DO_DAEMON=1 ;;
        --smoke)        DO_SMOKE=1 ;;
    esac
done

if [ "$DO_COMPILE" = 1 ] && ! command -v cargo >/dev/null 2>&1; then
    printf 'dev-sync: cargo ausente no PATH (rustup — o requisito do hot-reload)\n' >&2
    exit 1
fi

# ── o que compilar (o alvo escolhe a família; elite-core arrastra todos) ──
case "$ALVO" in
    bar)   CRATES_BUILD=(craft-bar-rs) ;;
    dock)  CRATES_BUILD=(craft-dock-rs) ;;
    all)   CRATES_BUILD=(elite-daemon craft-bar-rs craft-dock-rs craft-dump-rs craft-tools) ;;
esac

BINS_DE() { # BINS_DE <crate> — os binários que o crate pariu
    case "$1" in
        elite-daemon)  echo "elite-daemon" ;;
        craft-bar-rs)  echo "craft-bar-rs" ;;
        craft-dock-rs) echo "craft-dock-rs" ;;
        craft-dump-rs) echo "craft-dump" ;;
        craft-tools)   echo "craft-update craft-clean craft-help craft-pick" ;;
    esac
}

reinicia_vaga() { # reinicia_vaga <comm> <bin_novo> <log>
    # a troca QUIETA: mata o velho pelo comm, nasce o novo pelo CAMINHO
    # explícito (o comm é o mesmo — o daemon ADOTA pela lei E138: comm
    # vivo + vaga com dono = Adotada, zero respawn, zero duplicata)
    pkill -TERM -x "$1" 2>/dev/null && sleep 0.4 || sleep 0.1
    setsid "$2" </dev/null >>"$CACHE/$3" 2>&1 &
    disown 2>/dev/null || true
}

printf '══ DEV-SYNC · o hot-reload da casa (repo: %s) ══\n' "$REPO"

if [ "$DO_COMPILE" = 1 ]; then
    # elite-core mudou desde o último build? Todos os filhos recompilam
    # (a fundação é bebida por todos — o cargo detecta por si, mas o
    # alvo estreito de UM crate não veria a mudança da lib)
    CORE_LIB="$CRATES/elite-core/src"
    if [ -d "$CORE_LIB" ]; then
        core_novo="$(find "$CORE_LIB" -name '*.rs' -newer "$TARGET/.dev-sync-stamp" -print -quit 2>/dev/null || true)"
        if [ -n "${core_novo:-}" ]; then
            printf '  elite-core mudou (%s) — a gui inteira recompila\n' "${core_novo#$CRATES/}"
            case "$ALVO" in
                bar)  CRATES_BUILD=(craft-bar-rs craft-dock-rs) ;;
                dock) CRATES_BUILD=(craft-bar-rs craft-dock-rs) ;;
            esac
        fi
    fi

    printf '  compilando (release, gui ON — o default dos crates)…\n'
    build_rc=0
    for c in "${CRATES_BUILD[@]}"; do
        ( cd "$CRATES" && CARGO_TARGET_DIR="$TARGET" cargo build --release -p "$c" ) || build_rc=1
        [ "$build_rc" = 0 ] || { printf 'dev-sync: o build de %s falhou (o réu está acima)\n' "$c" >&2; exit 1; }
    done
    touch "$TARGET/.dev-sync-stamp" 2>/dev/null || true

    # instalação SÓ dos binários que realmente mudaram (o cmp é o juiz —
    # zero escrita desnecessária no ~/.local/bin)
    mkdir -p "$DEV_BIN"
    instalados=""
    for c in "${CRATES_BUILD[@]}"; do
        for b in $(BINS_DE "$c"); do
            novo="$TARGET/release/$b"
            [ -x "$novo" ] || { printf 'dev-sync: %s não nasceu no target (%s)\n' "$b" "$novo" >&2; exit 1; }
            if [ ! -f "$DEV_BIN/$b" ] || ! cmp -s "$novo" "$DEV_BIN/$b"; then
                install -m755 "$novo" "$DEV_BIN/$b"
                instalados="$instalados $b"
            fi
        done
    done
    [ -n "$instalados" ] && printf '  novos em %s:%s\n' "$DEV_BIN" "$instalados" \
        || printf '  nada mudou de binário (build limpo — só a suíte paga)\n'
else
    printf '  --restart-only: sem build (reinicia do %s)\n' "$DEV_BIN"
fi

# ── o restart (apenas a UI pedida; os demais residentes intocados) ───────
NA_POSSO=0
[ -n "${WAYLAND_DISPLAY:-}" ] || { printf 'dev-sync: sem WAYLAND_DISPLAY — rode DENTRO da sessão labwc\n' >&2; NA_POSSO=1; }
if [ "$NA_POSSO" = 0 ]; then
    case "$ALVO" in
        bar|all) [ -x "$DEV_BIN/craft-bar-rs" ] && reinicia_vaga craft-bar-rs "$DEV_BIN/craft-bar-rs" bars.log \
                     && printf '  barra: reiniciada (%s/craft-bar-rs — o daemon adota)\n' "$DEV_BIN" ;;
    esac
    case "$ALVO" in
        dock|all) [ -x "$DEV_BIN/craft-dock-rs" ] && reinicia_vaga craft-dock-rs "$DEV_BIN/craft-dock-rs" dock.log \
                      && printf '  dock: reiniciada (%s/craft-dock-rs — o daemon adota)\n' "$DEV_BIN" ;;
    esac
    if [ "$DO_DAEMON" = 1 ]; then
        # o daemon novo nasce do MESMO jeito do autostart (o elite-daemon
        # do PATH; os filhos vivos são adotados — nada morre além do pai)
        pkill -TERM -x elite-daemon 2>/dev/null && sleep 0.6 || true
        setsid elite-daemon session </dev/null >>"$CACHE/bars.log" 2>&1 &
        disown 2>/dev/null || true
        printf '  daemon: reiniciado (os residentes vivos foram adotados — E138)\n'
    fi
    sleep 1.5
    vivos=""
    if [ "$ALVO" != "dock" ] && pgrep -x craft-bar-rs >/dev/null 2>&1; then vivos="$vivos craft-bar-rs"; fi
    if [ "$ALVO" != "bar" ] && pgrep -x craft-dock-rs >/dev/null 2>&1; then vivos="$vivos craft-dock-rs"; fi
    if pgrep -x elite-daemon >/dev/null 2>&1; then vivos="$vivos elite-daemon"; fi
    printf '  de pé agora:%s\n' "${vivos:- (nada?! o cauda do log fala)}"
    [ -n "$vivos" ] || { printf '  cauda %s/bars.log:\n' "$CACHE"; tail -5 "$CACHE/bars.log" 2>/dev/null || true; }
fi

if [ "$DO_SMOKE" = 1 ]; then
    printf '\n  o fumo da sessão de verdade:\n'
    bash "$REPO/tests/session_smoke/run.sh"
fi

printf 'dev-sync: pronto (a pele nova está na sessão em segundos, não em reboots)\n'
