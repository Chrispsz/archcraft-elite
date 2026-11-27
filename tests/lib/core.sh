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

# ── 1.0-103 — O JUIZ DE CASA (a erradicação do python): o craft-audit
#    (núcleo std do craft-tools) é o juiz de XML/INI da suíte — a porteira
#    o PRE-BUILDA no arranque (tests/run-tests.sh, quando há cargo no
#    ambiente) e o exporta como $ELITE_JUDGE; xmllint segue como rede.
julga() { # julga <verbo> <arquivo> — o juiz de casa, com a rede do xmllint
    if [ -n "${ELITE_JUDGE:-}" ] && [ -x "$ELITE_JUDGE" ]; then
        "$ELITE_JUDGE" "$1" "$2"
    elif command -v craft-audit >/dev/null 2>&1; then
        craft-audit "$1" "$2"
    elif [ "$1" = "xml" ] && command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$2" >/dev/null 2>&1
    else
        echo "  □ (julga: juiz ausente — cargo/xmllint fora do ambiente)" >&2
        return 2 # sem juiz: o chamador veste t_skip
    fi
}

# o XML nasce bem-formado (menu/rc da casa)
xml_ok() { # xml_ok <desc> <arquivo>
    julga xml "$2" 2>/dev/null
    local rc=$?
    if [ "$rc" = "2" ]; then
        t_skip "$1" "juiz XML ausente (sem cargo e sem xmllint no ambiente)"
    elif [ -f "$2" ] && [ "$rc" = "0" ]; then
        t_ok "$1"
    else
        t_fail "$1" "XML mal-formado ou ausente: $2"
    fi
}

# E146 — o MENU nasce SEM texto órfão fora de tag (a gramática da casa:
# só elementos; o libxml2 até aceita mixed content e o labwc pula o
# texto no parse, mas arquivo com membro fora de tag é arquivo amputado
# — o órfão do E103 atravessou 4 eras porque o juízo era só bem-formado)
menu_ok() { # menu_ok <desc> <arquivo>
    julga menu "$2" 2>/dev/null
    local rc=$?
    if [ "$rc" = "2" ]; then
        t_skip "$1" "juiz do menu ausente (sem cargo no ambiente)"
    elif [ -f "$2" ] && [ "$rc" = "0" ]; then
        t_ok "$1"
    else
        t_fail "$1" "texto órfão fora de tag (ou XML quebrado): $2"
    fi
}

# o INI nasce com seção (a lição do fuzzel.ini quebrado E137)
ini_ok() { # ini_ok <desc> <arquivo>
    julga ini "$2" 2>/dev/null
    local rc=$?
    if [ "$rc" = "2" ]; then
        t_skip "$1" "juiz INI ausente (sem cargo no ambiente)"
    elif [ -f "$2" ] && [ "$rc" = "0" ]; then
        t_ok "$1"
    else
        t_fail "$1" "INI sem seção ou ausente: $2"
    fi
}

# a linha EXATA está AUSENTE do arquivo (o grep -x com -F — a âncora
# ^nome$ de era nunca foi casada pelo file_hasnt -qF: contratos VACUOS
# morrem aqui; a linha inteira, sem âncora regex, é o contrato honesto)
file_line_absent() { # file_line_absent <desc> <arquivo> <linha>
    if [ ! -f "$2" ] || ! grep -qxF -- "$3" "$2"; then t_ok "$1"
    else t_fail "$1" "linha '$3' AINDA em $2"; fi
}

# a linha EXATA mora no arquivo (grep -x — âncoras regex não confundem)
file_line_exact() { # file_line_exact <desc> <arquivo> <linha>
    if [ -f "$2" ] && grep -qxF -- "$3" "$2"; then t_ok "$1"
    else t_fail "$1" "linha '$3' não achada em $2"; fi
}
