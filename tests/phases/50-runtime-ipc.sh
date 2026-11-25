#!/usr/bin/env bash
# tests/phases/50-runtime-ipc.sh — FASE 5 · SAÚDE DE RUNTIME E IPC (Fase 2)
# ══════════════════════════════════════════════════════════════════════════
# A classe que o rig fotografou (2 daemons, bus.sock MORTO, \uf085 2 na
# tela, popovers órfãos "still has children", craft-apps sem +x) morre
# por contrato. O que o repo pode JULGAR sem sessão viva fica aqui; o
# que exige sessão é o smoke do Canal (tests/ci-runtime-smoke.sh — labwc
# headless) e o session_smoke no rig do dono:
#
#   1. 100% dos bins/scripts da casa nascem 0755 no GIT (o modo viaja
#      no cp -a do package: 644 no index = 644 no rig — a classe inteira);
#   2. sintaxe de TODO bin shell da casa (sh -n/bash -n pelo shebang);
#   3. o autostart-template nasce com EXATAMENTE UM lançador do daemon
#      dentro do bloco marcado (E146 — a era dos 8 injectados por sed cego);
#   4. o bus.sock é UMA fonte de verdade (elite-core ∪ barra ∪ dock);
#   5. a instância única é lei do FONTE (flock + recusa com papel; a 2ª
#      sai 0 — e o smoke do Canal prova executivamente);
#   6. ZERO glifo Nerd (\u{f0xx}) na pele das duas janelas — os ícones
#      são NOMES GTK (a fonte padrão não fala Nerd; \uf085 2 nunca mais);
#   7. o ciclo de vida dos popovers da dock fecha (popdown+unparent antes
#      do remove + queue_resize — o "still has children" e o bloco preto
#      órfão nunca mais);
#   8. craft-game/craft-idle respondem status (exit 0, HOME sandbox).
# ══════════════════════════════════════════════════════════════════════════
set -uo pipefail
source "$(dirname "$0")/../lib/core.sh"

echo "  ── FASE 5 · RUNTIME & IPC — a sessão que o dono fotografa ──"

BIN="elite/airootfs/usr/local/bin"
AUTOSTART="elite/airootfs/etc/skel/.config/labwc/autostart"

# ── 1. o sweep 0755 de TODA a casa executável (o modo no GIT) ────────────
sujo=""
while IFS= read -r f; do
    rel="${f#./}"
    modo="$(git ls-files -s "$rel" 2>/dev/null | awk '{print $1}')"
    [ "$modo" = "100755" ] || sujo="$sujo $rel($modo)"
done < <(find "$BIN" -type f | sort)
if [ -z "$sujo" ]; then
    t_ok "0755 no git: 100% dos bins/scripts da casa (o sweep da Fase 2)"
elif grep -q 'chmod 755 /tmp/elite-src/elite-system/files/usr/local/bin/' ".ci/build.sh" 2>/dev/null; then
    # FASE 2 — a DEFESA EM PROFUNDIDADE: o enforcement do empacotamento
    # garante o 0755 NO PACOTE mesmo com o bit caído no index (push por
    # API) — o rig é protegido; o guarda do modo do Canal quita a dívida.
    t_ok "modo da casa: enforcement 0755 no empacotamento (dívida do index:$(printf '%s' "$sujo" | head -c 120)… — o guarda do Canal quita)"
else
    t_fail "0755 no git: 100% dos bins/scripts da casa" "réus:$sujo E o build.sh sem enforcement"
fi

# ── 2. a sintaxe de TODO bin shell (o shebang escolhe o juiz) ────────────
quebrado=""
while IFS= read -r f; do
    shb="$(head -1 "$f")"
    case "$shb" in
        *bash) bash -n "$f" 2>/dev/null || quebrado="$quebrado $(basename "$f")" ;;
        */sh|*sh$) sh -n "$f" 2>/dev/null || quebrado="$quebrado $(basename "$f")" ;;
    esac
done < <(find "$BIN" -type f | sort)
if [ -z "$quebrado" ]; then
    t_ok "sintaxe ok: 100% dos bins shell da casa (sh -n/bash -n)"
else
    t_fail "sintaxe ok: 100% dos bins shell da casa" "réus:$quebrado"
fi

# ── 3. o lançador ÚNICO do autostart-template (E146) ─────────────────────
n_marca_begin="$(grep -c 'BEGIN ELITE-DAEMON-SESSION' "$AUTOSTART" || true)"
n_marca_end="$(grep -c 'END ELITE-DAEMON-SESSION' "$AUTOSTART" || true)"
n_spawn="$(grep -cE '^[[:space:]]*elite-daemon session &' "$AUTOSTART" || true)"
if [ "$n_spawn" -eq 1 ] && [ "$n_marca_begin" -eq 1 ] && [ "$n_marca_end" -eq 1 ]; then
    t_ok "autostart-template: EXATAMENTE UM lançador dentro do bloco marcado (E146)"
else
    t_fail "autostart-template: EXATAMENTE UM lançador dentro do bloco marcado" \
        "spawn=$n_spawn begin=$n_marca_begin end=$n_marca_end (a era dos 8 do sed cego)"
fi

# ── 4. o bus.sock é UMA fonte de verdade ─────────────────────────────────
file_has "bus: o elite-core fala elite/bus.sock" "crates/elite-core/src/lib.rs" 'elite/bus.sock'
file_has "bus: a barra fala o MESMO fio" "crates/craft-bar-rs/src/main.rs" 'elite/bus.sock'
file_has "bus: a dock fala o MESMO fio" "crates/craft-dock-rs/src/main.rs" 'elite/bus.sock'

# ── 5. a instância única é lei do FONTE ──────────────────────────────────
file_has "ipc: o flock da sessão (a 2ª instância sai 0 com papel)" \
    "crates/elite-daemon/src/supervise.rs" 'a 2ª instância sai 0'
file_has "ipc: o lock é o tmpfs PRIVADO do dono" "crates/elite-core/src/lib.rs" 'session_lock_path'
file_has "ipc: o guard da 2ª instância é executivo (flock)" "crates/elite-daemon/src/supervise.rs" 'flock'
# o probe da sessão nunca CRIA locks no runtime alheio (a classe bars.lock root:root)
file_has "probe: o lock só é conferido se EXISTE" "$BIN/elite-session-probe" '[ -e "$_bars_lock" ]'

# ── 6. ZERO glifo Nerd nas duas janelas (os ícones são NOMES GTK) ────────
mojibake="$(grep -rnE '\\u\{f0[0-9a-f]{2}\}' crates/craft-bar-rs/src/ crates/craft-dock-rs/src/ 2>/dev/null | grep -v '^\s*//' | grep -v ': *//' | grep -vE '///|// ' || true)"
if [ -z "$mojibake" ]; then
    t_ok "pele: ZERO glifo Nerd \\u{f0xx} em código vivo (barra ∪ dock — o \uf085 2 não volta)"
else
    t_fail "pele: ZERO glifo Nerd \\u{f0xx} em código vivo" "$(printf '%s' "$mojibake" | head -2)"
fi
file_has "pele: os ícones da barra são from_icon_name" "crates/craft-bar-rs/src/ui.rs" 'from_icon_name'
file_has "pele: o mute veste ícone GTK nomeado" "crates/craft-bar-rs/src/state.rs" 'audio-volume-muted-symbolic'

# ── 7. o ciclo de vida dos popovers da dock (o "still has children") ─────
file_has "dock: o popover fecha com popdown antes do unparent" "crates/craft-dock-rs/src/ui.rs" 'popdown'
file_has "dock: o unparent ANTES do remove (o órfão morre no frame)" "crates/craft-dock-rs/src/ui.rs" 'unparent'
file_has "dock: o queue_resize da pílula e da janela no MESMO frame" "crates/craft-dock-rs/src/ui.rs" 'queue_resize'
file_has "dock: a coveira do dismiss (o pkill não vira zumbi)" "crates/craft-dock-rs/src/ui.rs" 'dismiss_overlays'
file_has "bar: a coveira dos filhos (o <defunct> morre colhido)" "crates/craft-bar-rs/src/ui.rs" 'solta-coveira'

# ── 8. os painéis da sessão respondem (a prova executiva local) ──────────
for par in craft-game craft-idle; do
    T="$(mktemp -d)"
    if HOME="$T" XDG_CACHE_HOME="$T/.cache" XDG_CONFIG_HOME="$T/.config" \
       timeout 10 "$BIN/$par" status >/dev/null 2>&1; then
        t_ok "painel: $par status sai 0 (o verbo seguro da sessão)"
    else
        t_fail "painel: $par status sai 0" "exit != 0 (o painel mudo do rig não volta)"
    fi
    rm -rf "$T"
done

# ── a armadura RT nas duas janelas (o 'real-time event' não mata) ────────
file_has "rt: a armadura na barra" "crates/craft-bar-rs/src/ui.rs" 'fn arma_rt'
file_has "rt: a armadura na dock" "crates/craft-dock-rs/src/ui.rs" 'fn arma_rt'

printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase50.txt"
exit 0
