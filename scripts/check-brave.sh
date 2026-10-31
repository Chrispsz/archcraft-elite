#!/usr/bin/env bash
# check-brave — mantém o pin do brave-origin COLADO na release oficial
# ═══════════════════════════════════════════════════════════════════════════
# E32 (dono: "a distro não pode ficar velha"): o brave-origin é pinado no
# PKGBUILD heredoc do .ci/build.sh (pkgver + sha256 do zip — determinismo,
# filosofia Elite). Sem este guardião o pin envelheceria para sempre: o
# rebuild mensal reusaria a MESMA versão via cache. Este script:
#   1. lê o pin atual (pkgver) do build.sh;
#   2. pergunta à API do Brave a release latest;
#   3. versão nova → baixa o zip, confere contra o .sha256 PUBLICADO pela
#      Brave (a CI re-verifica no makepkg — pin errado = build vermelho);
#   4. atualiza pkgver + sha + a linha do 'say' (single source: build.sh);
#   5. imprime o que o agente precisa fazer (commit → tag → CI).
# O cache do Actions usa '.ci/build.sh' na chave (E32) — bump invalida o
# cache sozinho; ninguém precisa limpar nada à mão.
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$REPO/.ci/build.sh"
API="https://api.github.com/repos/brave/brave-browser/releases/latest"

command -v curl >/dev/null 2>&1 || { echo "ERRO: curl ausente"; exit 1; }

# API do GitHub SEMPRE autenticada quando há token (leição da casa: rate
# limit de IP compartilhado engole chamadas anônimas); sem token, tenta nu
AUTH=()
if [[ -n "${GH_TOKEN:-}" || -n "${GITHUB_TOKEN:-}" ]]; then
    AUTH=(-H "Authorization: Bearer ${GH_TOKEN:-$GITHUB_TOKEN}")
fi

# ESCOPADO na seção do Brave: o build.sh tem OUTROS PKGBUILDs (python-pywal
# 3.3.1 etc.) — o primeiro 'pkgver=' do arquivo NÃO é o do navegador
cur="$(sed -n "/^pkgname=brave-origin$/,/^EOPKGBUILD$/p" "$BUILD" \
    | sed -n 's/^pkgver=\([0-9.]*\)$/\1/p' | head -1)"
[[ -n "$cur" ]] || { echo "ERRO: pin pkgver não encontrado em $BUILD"; exit 1; }

latest="$(curl -fsSL --max-time 20 "${AUTH[@]}" "$API" 2>/dev/null \
    | sed -n 's/^ *"tag_name": *"v\([0-9.]*\)".*/\1/p' | head -1 || true)"
[[ -n "$latest" ]] || { echo "ERRO: API do Brave não respondeu (rede?)"; exit 1; }

echo "pin atual : $cur"
echo "latest    : $latest"

ver_ge() { # $1 >= $2 ? (split por ponto, comparação numérica)
    local a b
    IFS=. read -r -a a <<< "$1"
    IFS=. read -r -a b <<< "$2"
    for ((i=0; i<${#b[@]} || i<${#a[@]}; i++)); do
        local x="${a[i]:-0}" y="${b[i]:-0}"
        (( 10#$x > 10#$y )) && return 0
        (( 10#$x < 10#$y )) && return 1
    done
    return 0
}

if [[ "$latest" == "$cur" ]]; then
    echo "✔ pin em dia — nada a fazer."
    exit 0
fi
if ! ver_ge "$latest" "$cur"; then
    echo "• latest ($latest) < pin ($cur) — pin é mais novo? nada a fazer (nunca rebaixo)."
    exit 0
fi

echo "==> versão nova: baixando .sha256 publicado pela Brave…"
zip="brave-origin-${latest}-linux-amd64.zip"
pub="$(curl -fsSL --max-time 30 \
    "https://github.com/brave/brave-browser/releases/download/v${latest}/${zip}.sha256" 2>/dev/null \
    | awk '{print $1}' | head -1 || true)"
[[ "$pub" =~ ^[0-9a-f]{64}$ ]] || { echo "ERRO: .sha256 publicado ausente/inválido para $zip"; exit 1; }
echo "sha256 publicado: $pub"

oldsha="$(sed -n "/^pkgname=brave-origin$/,/^EOPKGBUILD$/p" "$BUILD" \
    | grep -oE "'[0-9a-f]{64}'" | sed -n '3p' | tr -d "'")"
[[ -n "$oldsha" ]] || { echo "ERRO: sha do zip do pin não encontrado"; exit 1; }

# prova local OPCIONAL (barata só se o zip já estiver em cache/http proxy):
# o makepkg da CI é a prova real — ele valida o sha contra os bytes baixados.
echo "==> atualizando o pin em $BUILD (pkgver + sha + says)"
sed -i "/^pkgname=brave-origin$/,/^EOPKGBUILD$/ s/^pkgver=.*/pkgver=${latest}/" "$BUILD"
sed -i "s/${oldsha}/${pub}/" "$BUILD"
sed -i "s/Brave ORIGIN ${cur}/Brave ORIGIN ${latest}/" "$BUILD"
sed -i "s/brave-origin ${cur}/brave-origin ${latest}/" "$BUILD"

grep -q "pkgver=${latest}" "$BUILD" && grep -q "${pub}" "$BUILD" \
    && echo "✔ pin atualizado: ${cur} → ${latest}" \
    || { echo "ERRO: pós-checagem falhou — confira o $BUILD"; exit 1; }

cat <<'EOF'

PRÓXIMOS PASSOS (agente do ciclo mensal):
  1. git add .ci/build.sh && git commit -m "E: bump brave-origin ${latest}" (inclua no commit do ciclo)
  2. a tag do ciclo dispara a CI — o makepkg valida o sha no build;
     o cache do Actions invalida sozinho (build.sh está na chave)
  3. a release nova leva o pkg novo como asset do [elite-local]
EOF
