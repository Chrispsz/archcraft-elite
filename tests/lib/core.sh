#!/usr/bin/env bash
# tests/lib/core.sh — os MODOMENTOS da porteira real (2.0)
# Contadores + asserções de arquivo (o contrato é sobre a árvore REAL,
# nunca sobre mock: o arquivo que a casa entrega é a prova).
#   GO = 0 falhas · o veredito é o 60-veredito.sh
set -uo pipefail

OK_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
WORK="${WORK:-/tmp/elite-suite-default}"
mkdir -p "$WORK" 2>/dev/null || true
: > "$WORK/summary.txt"

t_ok() { # t_ok <descrição>
    (( OK_COUNT++ )) || true
    printf '  ✔ %s\n' "$1"
    printf 'OK\t%s\n' "$1" >> "$WORK/summary.txt"
}

t_fail() { # t_fail <descrição> <réu>
    (( FAIL_COUNT++ )) || true
    printf '  ✘ %s\n       réu: %s\n' "$1" "$2"
    printf 'FAIL\t%s\t%s\n' "$1" "$2" >> "$WORK/summary.txt"
}

t_skip() { # t_skip <descrição> <motivo>
    (( SKIP_COUNT++ )) || true
    printf '  □ %s (pulo: %s)\n' "$1" "$2"
    printf 'SKIP\t%s\t%s\n' "$1" "$2" >> "$WORK/summary.txt"
}

# passa/falha por exit code de um comando REAL
t_cmd() { # t_cmd <descrição> <cmd...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then t_ok "$desc"; else t_fail "$desc" "$*"; fi
}

# o arquivo existe (caminho absoluto ou relativo ao REPO)
file_exists() { # file_exists <desc> <caminho>
    if [ -e "$2" ]; then t_ok "$1"; else t_fail "$1" "inexistente: $2"; fi
}

# o arquivo NÃO existe (o fóssil que nunca volta)
file_absent() { # file_absent <desc> <caminho>
    if [ ! -e "$2" ]; then t_ok "$1"; else t_fail "$1" "fóssil presente: $2"; fi
}

# o arquivo CONTÉM a agulha (contrato literal)
file_has() { # file_has <desc> <arquivo> <agulha>
    if [ -f "$2" ] && grep -qF -- "$3" "$2"; then t_ok "$1"
    else t_fail "$1" "'$3' não achado em $2"; fi
}

# o arquivo NÃO contém a agulha (o legado que nunca volta)
file_hasnt() { # file_hasnt <desc> <arquivo> <agulha>
    if [ ! -f "$2" ] || ! grep -qF -- "$3" "$2"; then t_ok "$1"
    else t_fail "$1" "'$3' AINDA em $2"; fi
}

# o XML nasce bem-formado (menu/rc da casa)
xml_ok() { # xml_ok <desc> <arquivo>
    if [ -f "$2" ] && python3 - "$2" << 'PYX' >/dev/null 2>&1
import sys, xml.dom.minidom
xml.dom.minidom.parse(sys.argv[1])
PYX
    then t_ok "$1"; else t_fail "$1" "XML mal-formado ou ausente: $2"; fi
}

# E146 — o MENU nasce SEM texto órfão fora de tag (a gramática da casa:
# só elementos; o libxml2 até aceita mixed content e o labwc pula o
# texto no parse, mas arquivo com membro fora de tag é arquivo amputado
# — o órfão do E103 atravessou 4 eras porque o juízo era só bem-formado)
menu_ok() { # menu_ok <desc> <arquivo>
    if [ -f "$2" ] && python3 - "$2" << 'PYM' >/dev/null 2>&1
import sys, xml.etree.ElementTree as ET
t = ET.parse(sys.argv[1])
for el in t.getroot().iter():
    if (el.text or "").strip() or (el.tail or "").strip():
        sys.exit(1)  # texto fora de tag: o membro órfão
sys.exit(0)
PYM
    then t_ok "$1"; else t_fail "$1" "texto órfão fora de tag (ou XML quebrado): $2"; fi
}

# o INI nasce com seção (a lição do fuzzel.ini quebrado E137)
ini_ok() { # ini_ok <desc> <arquivo>
    if [ -f "$2" ] && python3 - "$2" << 'PYI' >/dev/null 2>&1
import sys, configparser
cp = configparser.ConfigParser(strict=False)
cp.read(sys.argv[1])
sys.exit(0 if cp.sections() else 1)
PYI
    then t_ok "$1"; else t_fail "$1" "INI sem seção ou ausente: $2"; fi
}

# a linha EXATA mora no arquivo (grep -x — âncoras regex não confundem)
file_line_exact() { # file_line_exact <desc> <arquivo> <linha>
    if [ -f "$2" ] && grep -qxF -- "$3" "$2"; then t_ok "$1"
    else t_fail "$1" "linha '$3' não achada em $2"; fi
}
