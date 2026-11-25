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

# ── a resolução executiva de TODO Execute (python = a gramática inteira:
#    sh -c, for b in, foot -e, pipes — os wrappers não enganam o juízo) ──
RESOLUCAO="$(python3 - "$MENU" "$RC" "$BIN" "$PKGS" "$BS" <<'PYC'
import re, shlex, sys, xml.etree.ElementTree as ET
from pathlib import Path

menu, rc, bindir, pkgfile, buildfile = sys.argv[1:6]

airootfs = {p.name for p in Path(bindir).iterdir()} if Path(bindir).is_dir() else set()
pacotes = {ln.split()[0] for ln in Path(pkgfile).read_text(encoding="utf-8").splitlines()
           if ln.strip() and not ln.strip().startswith("#")}
compilados = {"elite-daemon", "craft-bar-rs", "craft-dock-rs", "craft-dump",
              "craft-update", "craft-clean", "craft-help", "craft-pick"}
src = Path(buildfile).read_text(encoding="utf-8")
for m in re.finditer(r"for b in ([a-z0-9 \-]+) do", src):
    compilados |= set(m.group(1).split())
aliases = {
    "blueman-manager": "blueman", "blueman-adapters": "blueman",
    "wl-copy": "wl-clipboard", "wl-paste": "wl-clipboard",
    "pactl": "libpulse", "swayosd-client": "swayosd", "brave": "brave-origin",
    "xauth": "xorg-xauth", "xhost": "xorg-xhost", "7z": "7zip",
    "paccache": "pacman-contrib",
}
base = {"sh", "systemctl", "xdg-open", "zsh", "gsettings", "loginctl", "env"}

def resolve(b):
    return (b in airootfs or b in compilados or b in pacotes
            or b in aliases and aliases[b] in pacotes or b in base)

PALAVRAS = {"for", "in", "do", "done", "if", "then", "else", "elif", "fi",
            "exec", "export", "command", "local", "return", "while", "case", "esac"}

def candidatos(cmd):
    cmd = cmd.strip()
    toks = shlex.split(cmd)
    # foot sozinho É o binário; foot -e ... : o terminal é wrapper, o
    # alvo é o resto (a aspa é SAGRADA — o strip("'\"") comia o fechamento
    # do exec "${TERMINAL:-foot}" e o shlex morria: lição da run local)
    if toks and toks[0] == "foot":
        if len(toks) == 1:
            yield "foot"
            return
        toks = toks[1:]
        if toks and toks[0] == "-e":
            toks = toks[1:]
    corpo = " ".join(toks)
    m = re.match(r"sh\s+-c\s+(.*)$", corpo)
    if m:
        corpo = m.group(1)
    # a indireção do terminal da casa: ${TERMINAL:-foot} — o default é
    # o binário real (a variável é wrapper, o foot é a promessa)
    term = re.search(r"\$\{TERMINAL:-(\w[\w\-]*)\}", corpo)
    if term:
        yield term.group(1)
        return
    # cadeia de fallback (for b in X Y Z): o PRIMEIRO da lista é a casa
    chain = re.search(r"for\s+\w+\s+in\s+([\w\.\-]+(?:\s+[\w\.\-]+)*)\s*;", corpo)
    if chain:
        yield chain.group(1).split()[0]
        return
    # senão: o primeiro token que não é gramática do shell
    for t in shlex.split(corpo.replace("&&", " ").replace("||", " ").replace(";", " ").replace("|", " ")):
        if t in PALAVRAS or t.startswith("-") or "=" in t or "/" in t or t.startswith("$"):
            continue
        yield t
        return
    yield None

réus, comandos = [], 0
for arq in (menu, rc):
    try:
        root = ET.parse(arq).getroot()
    except Exception as e:
        réus.append(f"{Path(arq).name}: XML quebrado ({e})")
        continue
    for a in root.iter("action"):
        if a.get("name") != "Execute":
            continue
        cmd = a.get("command") or ""
        comandos += 1
        prim = next(candidatos(cmd), None)
        if prim is None:
            réus.append(f"{Path(arq).name}: Execute sem binário principal: {cmd[:60]}")
        elif not resolve(prim):
            réus.append(f"{Path(arq).name}: '{prim}' não existe na casa (command='{cmd[:60]}')")

FOSSEIS = ("craft-drawer", "craft-bars", "craft-connect", "craft-menu",
           "craft-player", "craft-power", "craft-logout", "craft-audio-route",
           "craft-dock-gui", "craft-pin-pick", "craft-toplevel")
for arq in (menu, rc):
    texto = Path(arq).read_text(encoding="utf-8")
    for f in FOSSEIS:
        for m in re.finditer(rf'command="([^"]*\b{f}\b[^"]*)"', texto):
            réus.append(f"{Path(arq).name}: fóssil '{f}' em Execute (command='{m.group(1)[:50]}')")

print(f"EXECUTED={comandos}")
print("\n".join(réus) if réus else "CLEAN")
sys.exit(1 if réus else 0)
PYC
)"
if python3 -c "import sys" >/dev/null 2>&1 && printf '%s' "$RESOLUCAO" | head -1 | grep -q '^EXECUTED='; then
    total="$(printf '%s\n' "$RESOLUCAO" | head -1 | cut -d= -f2)"
    if printf '%s\n' "$RESOLUCAO" | tail -n +2 | head -1 | grep -q '^CLEAN$'; then
        t_ok "integridade de Execute: $total comandos, TODOS resolvem binário real (menu ∪ rc)"
    else
        réus="$(printf '%s\n' "$RESOLUCAO" | tail -n +2 | head -6 | tr '\n' ' · ')"
        t_fail "integridade de Execute: $total comandos apontam para binário real" "$réus"
    fi
else
    t_fail "integridade de Execute (o juízo python correu)" "falha no resolvedor: $(printf '%s' "$RESOLUCAO" | head -2)"
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
