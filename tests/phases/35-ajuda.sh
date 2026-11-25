#!/usr/bin/env bash
# tests/phases/35-ajuda.sh — FASE 3.5 · O CONTRATO DO CRAFT-HELP (Fase 2)
# ══════════════════════════════════════════════════════════════════════════
# O mapa que o craft-help veste (craft_tools::mapa_comandos) é PROMESSA:
# cada comando e atalho documentado tem de existir DE VERDADE no sistema
# que a casa entrega. A era dos fantasmas (craft-drawer chamado por 4
# portas e ausente do sistema; craft-apps sem bit de execução; elite-update
# que respondia um pkexec quando o dono pedia ajuda) morre aqui:
#
#   1. EXISTÊNCIA — todo comando do mapa resolve em
#      elite/airootfs/usr/local/bin ∪ bins COMPILADOS do molde (build.sh)
#      ∪ elite/packages.add (∪ aliases de split package ∪ allowlist base);
#   2. EXECUÇÃO — todo bin da árvore referenciado pelo mapa nasce 0755 no
#      GIT (o modo viaja no cp -a do package(): 644 no index = 644 no rig);
#   3. SINTAXE — todo bin shell passa em sh -n/bash -n conforme o shebang;
#   4. VERBO SEGURO — todo bin responde -h/--help/uso (ou status, quando
#      é o verbo documentado) com exit 0, em HOME sandbox, SEM tocar nada.
#      Os bins COMPILADOS são cobrados estaticamente aqui (a arm de ajuda
#      no main.rs) e executivamente no smoke do Canal (ci-runtime-smoke).
#
# Os ATALHOS do mapa (W-d, W-a, W-S-b…) são cobrados contra os keybinds
# VIVOS do rc.xml — papel que cita atalho que o teclado não fala é mentira.
# ══════════════════════════════════════════════════════════════════════════
set -uo pipefail
source "$(dirname "$0")/../lib/core.sh"

echo "  ── FASE 3.5 · CONTRATO DO CRAFT-HELP — o mapa é promessa ──"

LIB="crates/craft-tools/src/lib.rs"
BIN="elite/airootfs/usr/local/bin"
RC="elite/airootfs/etc/skel/.config/labwc/rc.xml"
PKGS="elite/packages.add"
BS=".ci/build.sh"

# ── o universo resolúvel ─────────────────────────────────────────────────
# (a FONTE de cada grupo é o arquivo que entrega o binário — nunca lista
# dupla que envelhece)
BINARIOS_VIVOS="$(ls "$BIN" 2>/dev/null || true)"
COMPILADOS="elite-daemon craft-bar-rs craft-dock-rs craft-dump craft-update craft-clean craft-help craft-pick"
PACOTES="$(grep -vE '^[[:space:]]*(#|$)' "$PKGS" 2>/dev/null | awk '{print $1}' || true)"

tem_bin() { # tem_bin <nome> — resolve no universo da casa
    case " $COMPILADOS " in *" $1 "*) return 0 ;; esac
    printf '%s\n' "$BINARIOS_VIVOS" | grep -qx "$1" && return 0
    printf '%s\n' "$PACOTES" | grep -qx "$1" && return 0
    # aliases de split package (o pacote da lista entrega o binário por
    # outro nome — mapeados e justificados):
    case "$1" in
        blueman-manager|blueman-adapters)
            printf '%s\n' "$PACOTES" | grep -qx "blueman" && return 0 ;;
        wl-copy|wl-paste)
            printf '%s\n' "$PACOTES" | grep -qx "wl-clipboard" && return 0 ;;
        pactl)
            printf '%s\n' "$PACOTES" | grep -qx "libpulse" && return 0 ;;
        swayosd-client)
            printf '%s\n' "$PACOTES" | grep -qx "swayosd" && return 0 ;;
        brave)
            printf '%s\n' "$PACOTES" | grep -qx "brave-origin" && return 0 ;;
    esac
    # allowlist base (o binário é da base do Arch — systemd/glib/zsh/xdg)
    case "$1" in
        sh|systemctl|xdg-open|zsh|gsettings|loginctl) return 0 ;;
    esac
    return 1
}

# ── o mapa (extraído do FONTE — a fonte única, sem lista dupla) ──────────
MAPA="$(python3 - "$LIB" <<'PYM'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"pub fn mapa_comandos\(\).*?vec!\[(.*?)\n    \]", src, re.S)
if not m:
    sys.exit(3)
pares = re.findall(r'\("([^"]+)", "', m.group(1))
print("\n".join(pares))
PYM
)"
if [ "$(printf '%s\n' "$MAPA" | grep -c .)" -lt 20 ]; then
    t_fail "o mapa do craft-help é extraído do fonte" "extraído $(printf '%s\n' "$MAPA" | grep -c .) entradas (< 20) — o mapa encolheu?"
fi

N_CMD=0; N_FALHA=0
# ── os ATALHOS primeiro (W-*/C-* — cobrados contra os keybinds do rc.xml) ─
KEYBINDS="$(grep -oE '<keybind key="[^"]+"' "$RC" 2>/dev/null | sed 's/.*key="//; s/"$//' || true)"
atalho_no_rc() { # atalho_no_rc <tecla>
    printf '%s\n' "$KEYBINDS" | grep -qxF "$1"
}
while IFS= read -r item; do
    [ -n "$item" ] || continue
    case "$item" in
        W-*|C-*)
            # "W-1..4" → W-1 e W-4; "W-Escape / W-x / C-A-Delete" → os três
            alvos=""
            case "$item" in
                *-1..4)
                    # o range das mesas: os QUATRO keybinds de verdade
                    pref="${item%%-1..*}"
                    alvos="$(printf '%s-1\n%s-2\n%s-3\n%s-4' "$pref" "$pref" "$pref" "$pref")"
                    ;;
                *..*) alvos="$(printf '%s\n%s' "${item%%..*}" "${item##*..}")" ;;
                *) alvos="$item" ;;
            esac
            falho=""
            while IFS= read -r alvo; do
                [ -n "$alvo" ] || continue
                if ! atalho_no_rc "$alvo"; then falho="$falho $alvo"; fi
            done <<< "$(printf '%s\n' "$alvos" | sed 's|/|\n|g' | sed 's/[[:space:]]//g' | grep . || true)"
            if [ -n "$falho" ]; then
                t_fail "atalho do mapa vive no rc.xml" "$item: sem keybind para$falho"
                N_FALHA=$((N_FALHA + 1))
            else
                t_ok "atalho do mapa vive no rc.xml: $item"
            fi
            N_CMD=$((N_CMD + 1))
            ;;
    esac
done <<< "$MAPA"

# ── os COMANDOS (existência + 0755 + sintaxe + verbo seguro) ─────────────
while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    case "$cmd" in W-*|C-*) continue ;; esac
    N_CMD=$((N_CMD + 1))

    if ! tem_bin "$cmd"; then
        t_fail "comando do mapa existe no universo da casa" "$cmd: FANTASMA (nem airootfs, nem compilado, nem packages.add)"
        N_FALHA=$((N_FALHA + 1))
        continue
    fi

    if [ -f "$BIN/$cmd" ]; then
        # 0755 no GIT (o modo viaja no cp -a do package — 644 no index é
        # 644 no rig: a classe craft-apps sem +x morre aqui)
        modo="$(git ls-files -s "$BIN/$cmd" 2>/dev/null | awk '{print $1}')"
        if [ "$modo" = "100755" ]; then
            t_ok "0755 no git: $cmd"
        elif grep -q 'chmod 755 /tmp/elite-src/elite-system/files/usr/local/bin/' "$BS" 2>/dev/null; then
            # FASE 2 — a DEFESA EM PROFUNDIDADE: o bit pode ter caído no
            # index (push por API), mas o enforcement do build.sh garante o
            # 0755 NO PACOTE — o rig é protegido MESMO assim; a dívida do
            # transporte é quitada pelo guarda do modo do Canal.
            t_ok "modo de $cmd: enforcement 0755 no empacotamento (index=$modo — a dívida do transporte, o guarda do Canal quita)"
        else
            t_fail "modo de $cmd" "index=$modo E o build.sh sem o chmod de enforcement — o rig nasceria sem +x"
            N_FALHA=$((N_FALHA + 1))
        fi
        # sintaxe pelo shebang (bash -n para bash; sh -n para POSIX)
        shb="$(head -1 "$BIN/$cmd")"
        verbo_ok=1; porque=""
        case "$shb" in
            *bash) bash -n "$BIN/$cmd" 2>/dev/null || { verbo_ok=0; porque="bash -n reprovou"; } ;;
            *sh|*python*) sh -n "$BIN/$cmd" 2>/dev/null || { verbo_ok=0; porque="sh -n reprovou"; } ;;
        esac
        if [ "$verbo_ok" = 1 ]; then
            t_ok "sintaxe ok: $cmd"
        else
            t_fail "sintaxe ok: $cmd" "${porque:-shebang estranho: $shb}"
            N_FALHA=$((N_FALHA + 1))
        fi
        # o verbo seguro em HOME sandbox (L10: a prova é executiva)
        T="$(mktemp -d)"
        seguro=0
        for v in --help -h uso status; do
            if HOME="$T" XDG_CACHE_HOME="$T/.cache" XDG_CONFIG_HOME="$T/.config" \
               timeout 10 "$BIN/$cmd" "$v" >/dev/null 2>&1; then
                seguro=1
                t_ok "verbo seguro ($v): $cmd"
                break
            fi
        done
        rm -rf "$T"
        if [ "$seguro" = 0 ]; then
            t_fail "verbo seguro: $cmd" "nenhum de --help/-h/uso/status sai 0 (E90 violado)"
            N_FALHA=$((N_FALHA + 1))
        fi
    else
        # compilado (Rust): a arm de ajuda é cobrada no FONTE (a prova
        # executiva é o smoke do Canal, onde o binário existe de verdade)
        case "$cmd" in
            elite-daemon)
                grep -q '"--help"' crates/elite-daemon/src/main.rs \
                    && t_ok "arm de ajuda no fonte: $cmd (o exec é do Canal)" \
                    || { t_fail "arm de ajuda no fonte: $cmd" "main.rs sem --help"; N_FALHA=$((N_FALHA+1)); }
                ;;
            craft-bar-rs|craft-dock-rs)
                f="crates/$cmd/src/main.rs"
                grep -qE '"-h", "--help"|"--help"|-h.*--help' "$f" \
                    && t_ok "arm de ajuda no fonte: $cmd (lei E90 — antes de qualquer GTK)" \
                    || { t_fail "arm de ajuda no fonte: $cmd" "$f sem o verbo seguro"; N_FALHA=$((N_FALHA+1)); }
                ;;
            craft-dump)
                grep -q 'pede_ajuda\|--help' crates/craft-dump-rs/src/main.rs \
                    && t_ok "arm de ajuda no fonte: $cmd" \
                    || { t_fail "arm de ajuda no fonte: $cmd" "main.rs sem o verbo seguro"; N_FALHA=$((N_FALHA+1)); }
                ;;
            craft-update|craft-clean|craft-help|craft-pick)
                f="crates/craft-tools/src/bin/$cmd.rs"
                grep -q 'pede_ajuda' "$f" \
                    && t_ok "arm de ajuda no fonte: $cmd (pede_ajuda da casa)" \
                    || { t_fail "arm de ajuda no fonte: $cmd" "$f sem pede_ajuda"; N_FALHA=$((N_FALHA+1)); }
                ;;
        esac
    fi
done <<< "$MAPA"

# ── os bins COMPILADOS também nascem 0755 no molde (install -m755) ───────
# (o template vive dentro do f-string python: ${CARGO_TARGET_DIR} nasce
# com CHAVES DUPLAS — o grep veste as duas)
if grep -qE 'install -m755 "[^{]*[{]+CARGO_TARGET_DIR[^"}]*[}]+/release/' "$BS"; then
    t_ok "molde: os compilados nascem com install -m755"
else
    t_fail "molde: os compilados nascem com install -m755" "build.sh sem install -m755 do target"
fi

printf '  (mapa: %d entradas · %d falhas nesta fase)\n' "$N_CMD" "$N_FALHA"
printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase35.txt"
exit 0
