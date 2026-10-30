#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Archcraft ELITE · cura-e26.sh — as NOVE CURAS do papel completo, no campo
# ═══════════════════════════════════════════════════════════════════════════
# O dump nl3z (primeiro papel COMPLETO da casa — v2.4, FIM presente) + o
# log de instalação 84wl nomearam NINE doenças que nenhuma simulação viu:
#   1. craft-power morria no set -e (loginctl sem o verbo can-suspend) =
#      "clico em suspender e nada acontece" — A cura é o arquivo novo.
#   2. polkit sem suspend-ignore-inhibit = o -i pediria senha (cura: regra).
#   3. fuzzel.ini com opção inexistente = err em TODO menu (cura: nome certo).
#   4. fantasma do instalador no drawer = cache do nwg-drawer + peso morto
#      (cura: remove .desktop sobrevivente + purga o cache).
#   5. menu do idle calado sobre o que faz (cura: craft-idle novo — Travar/
#      Suspender nomeados) — idle.conf do dono INTOCADO.
#   6. chaveiro GNOME vazio que o PAM jamais desbloqueia (cura: autostart
#      novo com gate de live + chaveiro vazio removido — o PAM recria com
#      a senha do login no próximo login; ATENÇÃO: senhas salvas no
#      chaveiro VELHO se perdem — no rig do dia-1 não há nada salvo).
#   7. sudo de sessão no escuro (cura: craft-fix-keys novo — live only).
#   8. corrida do /proc (cura: craft-bgapps novo).
#   9. delay da dock (cura: craft-dock-gui novo — tick 1s).
# Escola cura-viva (E25): cada peça PROVADA (bash -n + marcador) ANTES de
# instalar, .bak do velho, sha256 impresso. Reversível: os .bak ficam ao lado.
# ═══════════════════════════════════════════════════════════════════════════
set -u
RAW="https://raw.githubusercontent.com/Chrispsz/archcraft-elite/main"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

say()  { printf '\n\033[1;35m═══ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "rode com sudo: sudo bash $0"

fetch() { # $1=arquivo no repo  $2=destino
    curl -fsSL "$RAW/$1" -o "$2" 2>/dev/null || wget -q "$RAW/$1" -O "$2" || return 1
}

prove() { # $1=arquivo  $2...=marcadores obrigatórios
    local f="$1"; shift
    bash -n "$f" || die "sintaxe quebrada em $f — nada foi instalado"
    local m
    for m in "$@"; do
        grep -q "$m" "$f" || die "marcador '$m' ausente em $f — arquivo da origem errada? abortado"
    done
}

install_piece() { # $1=origem  $2=destino  $3=modo  $4=marcador
    local dst="$2"
    if [ -e "$dst" ]; then
        cp -a "$dst" "$dst.bak-$(date +%Y%m%d-%H%M%S)"
    fi
    install -m "$3" "$1" "$dst"
    sha256sum "$dst"
    grep -q "$4" "$dst" || die "pós-checagem falhou em $dst"
    ok "instalado: $dst"
}

say "CURA E26 — o papel completo falou; o rig obedece"

# ── 1. Os 6 binários curados (bin → marcador de conteúdo) ──────────────────
say "1/6 · BINÁRIOS (power, idle, fix-keys, bgapps, dock, elite-tune)"
for piece in craft-power craft-idle craft-fix-keys craft-bgapps craft-dock-gui elite-tune; do
    fetch "elite/airootfs/usr/local/bin/$piece" "$T/$piece" || die "falha ao baixar $piece (sem rede?)"
done
prove "$T/craft-power"      'v2.10.12' '|| can=""'
prove "$T/craft-idle"       'Travar: 2 minutos' 'Suspender: 20 min'
prove "$T/craft-fix-keys"   'A CAMADA DE SESSÃO SÓ AGE NO LIVE'
prove "$T/craft-bgapps"     'A CORRIDA DO PROCESSO MORRENDO'
prove "$T/craft-dock-gui"   'timeout_add(1000'
prove "$T/elite-tune"       'O FANTASMA NO DRAWER'
install_piece "$T/craft-power"      /usr/local/bin/craft-power      755 '|| can=""'
install_piece "$T/craft-idle"       /usr/local/bin/craft-idle       755 'Travar: 2 minutos'
install_piece "$T/craft-fix-keys"   /usr/local/bin/craft-fix-keys   755 'SÓ AGE NO LIVE'
install_piece "$T/craft-bgapps"     /usr/local/bin/craft-bgapps     755 'CORRIDA DO PROCESSO'
install_piece "$T/craft-dock-gui"   /usr/local/bin/craft-dock-gui   755 'timeout_add(1000'
install_piece "$T/elite-tune"       /usr/local/bin/elite-tune       755 'FANTASMA NO DRAWER'

# ── 2. A regra polkit (o -i sem prompt) ────────────────────────────────────
say "2/6 · POLKIT (suspend -i sem pedir senha)"
fetch "elite/airootfs/etc/polkit-1/rules.d/49-elite-desktop.rules" "$T/49.rules" || die "falha ao baixar a regra polkit"
prove "$T/49.rules" 'suspend-ignore-inhibit'
install_piece "$T/49.rules" /etc/polkit-1/rules.d/49-elite-desktop.rules 644 'suspend-ignore-inhibit'
ok "polkitd recarrega a regra sozinho (inotify)"

# ── 3. O autostart com o gate do chaveiro (arquivo do USUÁRIO — .bak) ──────
say "3/6 · AUTOSTART (bootstrap do chaveiro só no live)"
AS="$HOME/.config/labwc/autostart"
fetch "elite/airootfs/etc/skel/.config/labwc/autostart" "$T/autostart" || die "falha ao baixar o autostart"
prove "$T/autostart" 'SÓ NO LIVE' '/run/archiso'
cp -a "$AS" "$AS.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
install -m 644 "$T/autostart" "$AS"
chown "$(stat -c %u:%g "$HOME")" "$AS" 2>/dev/null || true
grep -q 'SÓ NO LIVE' "$AS" || die "pós-checagem falhou no autostart"
sha256sum "$AS"
ok "instalado: $AS (.bak do velho ao lado)"

# ── 4. O fuzzel.ini do usuário (o nome certo da opção) ─────────────────────
say "4/6 · FUZZEL.INI (fim do err em todo menu)"
FZ="$HOME/.config/fuzzel/fuzzel.ini"
if [ -f "$FZ" ] && grep -q '^exit-on-focus-loss=yes' "$FZ"; then
    cp -a "$FZ" "$FZ.bak-$(date +%Y%m%d-%H%M%S)"
    sed -i 's/^exit-on-focus-loss=yes$/exit-on-keyboard-focus-loss=yes/' "$FZ"
    grep -q '^exit-on-keyboard-focus-loss=yes' "$FZ" && ok "opção corrigida em $FZ"
elif [ -f "$FZ" ] && grep -q '^exit-on-keyboard-focus-loss=yes' "$FZ"; then
    ok "já estava com o nome certo — nada a fazer"
else
    ok "sem linha defeituosa em $FZ — nada a fazer"
fi

# ── 5. O fantasma do instalador (desktop sobrevivente + cache do drawer) ───
say "5/6 · FANTASMA DO INSTALADOR (.desktop + cache do drawer)"
GHOST=0
for g in /usr/local/share/applications/calamares.desktop /usr/local/share/applications/abif.desktop; do
    if [ -e "$g" ]; then rm -f "$g" && ok "removido: $g" && GHOST=1; fi
done
[ "$GHOST" -eq 0 ] && ok "nenhum .desktop do instalador no disco (o cleanup da fábrica já passou)"
for cdb in /home/*/.cache/nwg-drawer/cache.db*; do
    if [ -e "$cdb" ]; then rm -f "$cdb" && ok "cache do drawer purgado: $cdb"; fi
done 2>/dev/null || true
ok "se o ícone AINDA aparecer, o dump v2.5 (seção 13) nomeia de onde ele vem"

# ── 6. O chaveiro vazio que o PAM jamais desbloqueia ────────────────────────
say "6/6 · CHAVEIRO GNOME (o PAM recria com a senha do login)"
for kr in "$HOME/.local/share/keyrings/login.keyring" \
          "$HOME/.local/share/keyrings/login.keyring.user"; do
    if [ -e "$kr" ]; then
        mkdir -p "$HOME/.local/share/keyrings.bak-e26" 2>/dev/null || true
        mv "$kr" "$HOME/.local/share/keyrings.bak-e26/" && ok "movido: $kr → keyrings.bak-e26/"
    fi
done
ok "AVISO HONESTO: senhas salvas no chaveiro velho ficam no .bak — o rig do dia-1 não tem nada salvo"
ok "no PRÓXIMO login o PAM cria o chaveiro com a senha do login (o mismatch morre)"

# ── epílogo: a dock nova sobe supervisionada, o idle segue intocado ────────
say "EPÍLOGO"
pkill -f '^/usr/bin/python3 /usr/local/bin/craft-dock-gui$' 2>/dev/null || true
ok "dock encerrada — o craft-bars a ressuscita com o código novo em ≤5s (tick 1s)"
ok "idle.conf do dono NÃO foi tocado (LOCK/OFF/SUSPEND_MIN são escolha dele — o menu novo agora diz o que faz)"
printf '\nCura E26 completa. Provas: marcadores + sha256 acima; reversão: os .bak ao lado de cada arquivo.\n'
printf 'O próximo papel (sudo craft-dump --upload) já sai da main como v2.5 — com o fantasma e a E23 nomeáveis.\n'
