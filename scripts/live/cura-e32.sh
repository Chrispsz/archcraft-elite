#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Archcraft ELITE · cura-e32.sh — "deixe tudo atualizável" (o Brave solto)
# ═══════════════════════════════════════════════════════════════════════════
# O dono (pós-auditoria Task 8): "Deixe tudo atualizável, a distro não pode
# ficar velha com o tempo, tudo deve funcionar e o código da nossa overlay
# deve ser de qualidade total".
#
# AS 4 CURAS (cada uma com a prova da causa):
#   1. [elite-local] NO TERMINAL — o brave-origin (o navegador padrão!) era
#      o ÚNICO pacote congelado da distro: pinado no build, empacotado num
#      repo que só existia DURANTE o build (file:///var/cache/elite-local
#      efêmero) e AUSENTE do pacman.conf final (prova: heredoc E3 lido
#      inteiro). A partir da v2.10.20 a CI publica o repo como ASSETS da
#      release única viva e 'releases/latest/download' SEMPRE aponta para a
#      release no ar. Cura no rig: a seção entra no /etc/pacman.conf —
#      o MESMO 'sudo pacman -Syu' passa a atualizar o navegador.
#   2. craft-update v2 — compara kernel instalado antes/depois da transação
#      (aviso de reboot exato, sem adivinhar uname) e compara o marker
#      /usr/local/share/elite/VERSION com a release viva (scripts/configs
#      da casa não são pacotes — a defasagem é declarada, não escondida).
#      Offline-safe: falha de rede aqui é silêncio, nunca erro de update.
#   3. snapper-cleanup.timer — a lacuna que a auditoria flagrou: sem o
#      timer, o NUMBER_LIMIT (50) nunca é aplicado e snapshots manuais
#      acumulam CoW para sempre. O timer SÓ aplica limites do config —
#      criação de snapshot segue explícita (lei do rollback da casa).
#   4. marker VERSION — o rig passa a declarar sua base para o craft-update.
#
# PROVA POR TIPO (escola E31): prove_sh (bash -n) para SHELL; para dados
# (pacman.conf), marcadores + arquivo não-vazio + pós-checagem. makepkg
# na CI re-verifica o sha256 do zip do Brave contra o pin — pin errado
# = build vermelho, nunca navegador silenciosamente errado.
#
# Escola cura-viva (E25/E26/E30/E31): cada peça PROVADA antes de instalar,
# .bak do velho, sha256 impresso, sessão resolvida por /run/user/* (o sudo
# reseta HOME — lição E29.1). Idempotente: roda de novo sem estrago.
# ═══════════════════════════════════════════════════════════════════════════
set -u
RAW="https://raw.githubusercontent.com/Chrispsz/archcraft-elite/main"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

say()  { printf '\n\033[1;35m═══ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "rode com sudo: sudo bash $0"

# o usuário REAL da sessão gráfica (o sudo reseta HOME ao alvo — lição E29.1)
RU=""
for d in /run/user/[0-9]*; do
    [ -d "$d" ] || continue
    RU="${d##*/}"
    break
done
[ -n "$RU" ] || die "nenhuma sessão de usuário viva (/run/user/*) — rode DENTRO da sessão"
UHOME="$(getent passwd "$RU" | cut -d: -f6)"
[ -n "$UHOME" ] && [ -d "$UHOME" ] || die "home do uid $RU não encontrada"
ok "sessão alvo: uid $RU · home $UHOME"

fetch() { # $1=arquivo no repo  $2=destino
    curl -fsSL "$RAW/$1" -o "$2" 2>/dev/null || wget -q "$RAW/$1" -O "$2" || return 1
}

prove_sh() { # $1=arquivo SHELL  $2...=marcadores
    local f="$1"; shift
    bash -n "$f" || die "sintaxe quebrada em $f — nada foi instalado"
    local m
    for m in "$@"; do
        grep -q "$m" "$f" || die "marcador '$m' ausente em $f — origem errada? abortado"
    done
}

prove_data() { # $1=arquivo NÃO-shell  $2...=marcadores
    local f="$1"; shift
    [ -s "$f" ] || die "arquivo vazio: $f"
    local m
    for m in "$@"; do
        grep -q "$m" "$f" || die "marcador '$m' ausente em $f — origem errada? abortado"
    done
}

install_piece() { # $1=origem  $2=destino  $3=modo  $4=marcador pós-checagem
    local dst="$2"
    if [ -e "$dst" ]; then
        cp -a "$dst" "$dst.bak-$(date +%Y%m%d-%H%M%S)"
    fi
    install -m "$3" "$1" "$dst"
    sha256sum "$dst"
    grep -q "$4" "$dst" || die "pós-checagem falhou em $dst"
    ok "instalado: $dst"
}

say "CURA E32 — tudo atualizável (o Brave solto, a casa declarada)"

# ── 1. [elite-local] NO PACMAN.CONF (o navegador entra no -Syu) ───────────
say "1/4 · PACMAN.CONF — o repo da casa com Server = release viva"
PC="/etc/pacman.conf"
if grep -q '^\[elite-local\]' "$PC"; then
    ok "[elite-local] já presente em $PC — intocado (idempotente)"
else
    cp -a "$PC" "$PC.bak-$(date +%Y%m%d-%H%M%S)"
    cat >> "$PC" <<'EOF'

# >>> ELITE (cura-e32): os pacotes da casa atualizam pelo terminal também —
# brave-origin, pwvucontrol, craft-toplevel, wlrctl. A CI publica o repo
# como ASSETS da release única viva; 'releases/latest/download' SEMPRE
# aponta para a release no ar (a URL nunca apodrece). Sem rede: o sync
# falha só neste repo (o resto segue) — rode craft-update de novo depois.
[elite-local]
SigLevel = Never
Server = https://github.com/Chrispsz/archcraft-elite/releases/latest/download
# <<< ELITE
EOF
    prove_data "$PC" '^\[elite-local\]' 'releases/latest/download'
    sha256sum "$PC"
    ok "[elite-local] anexado ao fim de $PC (.bak ao lado)"
fi

# ── 2. craft-update v2 (kernel→reboot + casa→ISO, offline-safe) ───────────
say "2/4 · CRAFT-UPDATE v2 — atualiza TUDO e declara a defasagem da casa"
fetch "elite/airootfs/usr/local/bin/craft-update" "$T/craft-update" \
    || die "falha ao baixar craft-update (sem rede?)"
prove_sh "$T/craft-update" 'pacman -Syu' 'kbefore' 'kafter' 'releases/latest' 'ELITE_VERSION_MARKER'
install_piece "$T/craft-update" /usr/local/bin/craft-update 755 'kafter'

# ── 3. snapper-cleanup.timer (o limite que nunca era aplicado) ────────────
say "3/4 · SNAPPER — cleanup timer (limites aplicados; criação segue manual)"
if [ "$(findmnt -n -o FSTYPE / 2>/dev/null)" = "btrfs" ] && command -v snapper >/dev/null 2>&1; then
    if systemctl is-enabled snapper-cleanup.timer >/dev/null 2>&1; then
        ok "snapper-cleanup.timer já ativo — intocado (idempotente)"
    else
        systemctl enable --now snapper-cleanup.timer 2>/dev/null \
            && ok "snapper-cleanup.timer ativo (NUMBER_LIMIT volta a valer)" \
            || ok "timer indisponível nesta instalação (unidade ausente?) — nada quebrado"
    fi
else
    ok "raiz não-btrfs ou snapper ausente — cleanup não se aplica (rollback é lei do btrfs)"
fi

# ── 4. marker VERSION (a casa declarada) ─────────────────────────────────
say "4/4 · MARKER — esta máquina declara sua base"
mkdir -p /usr/local/share/elite
printf '%s\n' "v2.10.19+cura-e32" > /usr/local/share/elite/VERSION
sha256sum /usr/local/share/elite/VERSION
ok "marker escrito: v2.10.19+cura-e32 (o craft-update usa para avisar ISO nova)"

# ── LIMITES honestos ──────────────────────────────────────────────────────
say "LIMITES"
ok "o [elite-local] foi anexado ao FIM do pacman.conf (rank baixo — sem conflito: brave-origin/pwvucontrol/craft-toplevel não existem em nenhum outro repo; wlrctl segue o da ISO)"
ok "o repo da casa anda no ritmo da release mensal: o Brave sobe de versão a cada ISO (a CI bumpa o pin); zero-dia crítico fora do ciclo = ISO/cura extraordinária"
ok "a primeira execução de 'sudo pacman -Syu' depois desta cura SÓ traz o navegador/repo da casa se a release viva JÁ publicar os assets (v2.10.20+); antes disso o -Syu segue normal"
printf '\nCura E32 completa. Provas: marcadores por tipo + sha256 acima; reversão: os .bak ao lado de cada arquivo.\n'
printf 'Veredito: sudo craft-update agora atualiza o NAVEGADOR também e avisa kernel/ISO — a distro não envelhece mais em silêncio.\n'
