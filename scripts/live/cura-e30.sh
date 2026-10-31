#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Archcraft ELITE · cura-e30.sh — o papel p6aw falou; o rig obedece
# ═══════════════════════════════════════════════════════════════════════════
# O dump p6aw (v2.5, 31/out 2026 — 1325 linhas) + as fotos do dono nomearam
# as doenças da v2.10.17 que nenhum CI viu (rig real ≠ QEMU):
#   1. BELL MISTERIOSO no terminal: o `wall` do elite-tune --firstboot
#      ("primeiro boot concluído") transmitiu às 16:14:45 — o MESMO segundo
#      do 'Finished elite-firstboot' no journal. Cura: os 3 wall morrem;
#      NVIDIA segue com toast crítico na sessão viva.
#   2. ÁUDIO SAINDO PELO MICROFONE: o sink PADRÃO era o "fifine Microphone
#      Estéreo analógico" (o microfone USB expõe sink fantasma). Cura:
#      craft-audio-route (novo, event-driven) — classe microfone JAMAIS é
#      default, fone no jack muda a PORTA, BT/USB novo muda o DEFAULT,
#      saída que some tem fallback. Supervisão no craft-bars.
#   3. DOIS swayidle VIVOS (pid 937 conf velho + pid 21282 conf novo): o
#      pkill+exec do craft-idle sem exclusão mútua. Cura: MUTEX do spawn
#      (lock no XDG_RUNTIME_DIR + /proc/pid/comm distingue spawn de daemon).
#   4. hyprlock FANTASMA ("got yeeten" no bars.log, pid 3666 vivo com a
#      sessão destravada). Cura: craft-lock mata o velho antes do exec —
#      SEMPRE exatamente um locker.
#   5. NOTIFICAÇÕES "Encerrado" ao encerrar programas (3 toasts na foto):
#      o craft-bgapps avisava a morte de cada processo — inclusive do
#      notify-send (pid 11463/11464: avisou a morte do próprio aviso).
#      Cura: encerrar fica MUDO (a janela sumindo é o feedback), toast só
#      em falha real; notify-send/tumblerd/xfconfd saem da lista.
#   6. SEGUNDO SOBTADO NO PAPEL: o craft-dump cortava o wpctl em head -30 —
#      exatamente a seção dos Sinks (o réu quase escapou). Cura: papel v2.6
#      completo.
#   7. PLAYER: passar/retroceder JÁ EXISTIAM (meio/dir) — o dono não sabia;
#      agora scroll ↑↓ também troca faixa, tooltip DIZ os controles e os
#      segundos correm em tempo real (interval 1 — leitura DBus interna do
#      waybar, zero fork).
#   8. CAPTURA RÁPIDA no menu do desktop (pedido do dono): "Captura de tela
#      (região)" → craft-shot.
#   9. BOTÕES macOS no Brave: o flag WaylandWindowDecorations forçava CSD;
#      sem ele o labwc desenha SSD igual às outras janelas.
# Escola cura-viva (E25/E26): cada peça PROVADA (bash -n / py_compile +
# marcadores) ANTES de instalar, .bak do velho, sha256 impresso.
# NOTA E29.1: sudo reseta HOME — o usuário de sessão é resolvido por
# /run/user/*, não por $HOME (o $HOME de root enganaria o script).
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
RU="$(ls /run/user/ 2>/dev/null | grep -E '^[0-9]+$' | head -1)"
[ -n "$RU" ] || die "nenhuma sessão de usuário viva (/run/user/*) — rode DENTRO da sessão"
UHOME="$(getent passwd "$RU" | cut -d: -f6)"
[ -n "$UHOME" ] && [ -d "$UHOME" ] || die "home do uid $RU não encontrada"
ok "sessão alvo: uid $RU · home $UHOME"

fetch() { # $1=arquivo no repo  $2=destino
    curl -fsSL "$RAW/$1" -o "$2" 2>/dev/null || wget -q "$RAW/$1" -O "$2" || return 1
}

prove_sh() { # $1=arquivo  $2...=marcadores
    local f="$1"; shift
    bash -n "$f" || die "sintaxe quebrada em $f — nada foi instalado"
    local m
    for m in "$@"; do
        grep -q "$m" "$f" || die "marcador '$m' ausente em $f — origem errada? abortado"
    done
}

prove_py() { # o roteador é python3 — a prova dele NÃO é bash -n
    local f="$1"; shift
    python3 -m py_compile "$f" || die "python quebrado em $f — nada foi instalado"
    local m
    for m in "$@"; do
        grep -q "$m" "$f" || die "marcador '$m' ausente em $f — origem errada? abortado"
    done
}

# E31 — A PROVA DOS NÃO-SHELL (a mina da v2.10.18, achado da revisão
# caractere a caractere): prove_sh rodava bash -n em config.top (JSONC)
# e menu.xml (XML) — o '(' do comentário derruba o parser e a cura
# ABORTAVA na mão do dono no passo 2/5 ('sintaxe quebrada'), depois de
# instalar os binários e antes dos configs. Dados provam por MARCADOR +
# arquivo não-vazio + a pós-checagem do install_piece; bash -n é só shell.
prove_data() { # $1=arquivo NÃO-shell  $2...=marcadores
    local f="$1"; shift
    [ -s "$f" ] || die "arquivo vazio: $f"
    local m
    for m in "$@"; do
        grep -q "$m" "$f" || die "marcador '$m' ausente em $f — origem errada? abortado"
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

say "CURA E30 — o papel p6aw falou; o rig obedece"

# ── 1. Os 7 binários curados (bin → marcador de conteúdo) ──────────────────
say "1/5 · BINÁRIOS (lock, idle, bgapps, bars, dump, audio-route, elite-tune)"
for piece in craft-lock craft-idle craft-bgapps craft-bars craft-dump craft-audio-route elite-tune; do
    fetch "elite/airootfs/usr/local/bin/$piece" "$T/$piece" || die "falha ao baixar $piece (sem rede?)"
done
prove_sh "$T/craft-lock"        'INSTÂNCIA ÚNICA' 'pkill -x hyprlock'
prove_sh "$T/craft-idle"        'MUTEX DO SPAWN' 'idle-start.lock'
prove_sh "$T/craft-bgapps"      'O ENCERRAR FICA MUDO' 'notify-send\*'
prove_sh "$T/craft-bars"        'O ROTEADOR DE ÁUDIO ENTRA NA SUPERVISÃO' 'craft-audio-route FORA'
prove_sh "$T/craft-dump"        'ELITE DUMP v2.6'
prove_py "$T/craft-audio-route" 'craft-audio-route' 'pactl' 'microphone' 'subscribe'
# o wall não volta NEM pela cura: o elite-tune novo não pode ter invocação
if grep -q 'wall "' "$T/elite-tune"; then die "elite-tune da main ainda invoca wall — origem errada"; fi
prove_sh "$T/elite-tune" 'O BELL MISTERIOSO MORRE'
install_piece "$T/craft-lock"         /usr/local/bin/craft-lock         755 'INSTÂNCIA ÚNICA'
install_piece "$T/craft-idle"         /usr/local/bin/craft-idle         755 'MUTEX DO SPAWN'
install_piece "$T/craft-bgapps"       /usr/local/bin/craft-bgapps       755 'O ENCERRAR FICA MUDO'
install_piece "$T/craft-bars"         /usr/local/bin/craft-bars         755 'ROTEADOR DE ÁUDIO'
install_piece "$T/craft-dump"         /usr/local/bin/craft-dump         755 'ELITE DUMP v2.6'
install_piece "$T/craft-audio-route"  /usr/local/bin/craft-audio-route  755 'subscribe'
install_piece "$T/elite-tune"         /usr/local/bin/elite-tune         755 'O BELL MISTERIOSO MORRE'

# ── 2. Configs do USUÁRIO (barra · menu · brave-flags) — .bak ao lado ──────
say "2/5 · CONFIGS DO USUÁRIO (mpris tempo real · captura no menu · SSD no Brave)"
fetch "elite/airootfs/etc/skel/.config/waybar/config.top" "$T/config.top" || die "falha ao baixar config.top"
prove_data "$T/config.top" 'segundos em TEMPO REAL' '"interval": 1' 'on-scroll-up'
CT="$UHOME/.config/waybar/config.top"
cp -a "$CT" "$CT.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
install -m 644 "$T/config.top" "$CT"
chown "$(stat -c %u:%g "$UHOME")" "$CT" 2>/dev/null || true
grep -q '"interval": 1' "$CT" || die "pós-checagem falhou no config.top"
sha256sum "$CT"
ok "instalado: $CT (waybar recarrega o módulo sozinho no próximo tick)"

fetch "elite/airootfs/etc/skel/.config/labwc/menu.xml" "$T/menu.xml" || die "falha ao baixar menu.xml"
prove_data "$T/menu.xml" 'Captura de tela'
MX="$UHOME/.config/labwc/menu.xml"
cp -a "$MX" "$MX.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
install -m 644 "$T/menu.xml" "$MX"
chown "$(stat -c %u:%g "$UHOME")" "$MX" 2>/dev/null || true
grep -q 'Captura de tela' "$MX" || die "pós-checagem falhou no menu.xml"
sha256sum "$MX"
ok "instalado: $MX (labwc lê o menu a cada abertura — sem reconfig)"

BF="$UHOME/.config/brave-flags.conf"
if [ -f "$BF" ] && grep -q 'WaylandWindowDecorations' "$BF"; then
    cp -a "$BF" "$BF.bak-$(date +%Y%m%d-%H%M%S)"
    sed -i 's/,WaylandWindowDecorations//' "$BF"
    grep -q 'WaylandWindowDecorations' "$BF" && die "flag ainda presente em $BF"
    chown "$(stat -c %u:%g "$UHOME")" "$BF" 2>/dev/null || true
    ok "WaylandWindowDecorations removido de $BF (o labwc passa a decorar o Brave — botões macOS)"
    ok "efeito no PRÓXIMO fechamento do Brave (feche e reabra o navegador)"
elif [ -f "$BF" ]; then
    ok "$BF já vive sem o flag — nada a fazer"
else
    ok "sem $BF — nada a fazer"
fi

# ── 3. O daemon duplo do idle morre — o mutex escolhe UM ───────────────────
say "3/5 · IDLE ÚNICO (os dois swayidle do dump morrem; um renasce com o conf do dono)"
pkill -x swayidle 2>/dev/null && ok "swayidle encerrado(s) — o supervisor renasce UM com o conf atual" \
    || ok "nenhum swayidle vivo — o supervisor cuida do nascimento"

# ── 4. O supervisor novo assume (e nasce o roteador de áudio) ──────────────
say "4/5 · SUPERVISOR RECICLADO (craft-bars novo → audio-route nasce em ≤5s)"
pkill -f '/bin/sh /usr/local/bin/craft-bars' 2>/dev/null || true
sleep 1
if [ -n "${SUDO_USER:-}" ]; then
    runuser -u "${SUDO_USER}" -- env XDG_RUNTIME_DIR="/run/user/${RU}" HOME="$UHOME" \
        setsid /usr/local/bin/craft-bars >>"$UHOME/.cache/elite/bars.log" 2>&1 &
else
    sudo -n -u "#$RU" env XDG_RUNTIME_DIR="/run/user/${RU}" HOME="$UHOME" \
        setsid /usr/local/bin/craft-bars >>"$UHOME/.cache/elite/bars.log" 2>&1 &
fi
ok "craft-bars novo no ar (flock único) — waybar/dock/idle/audio-route sob a MESMA supervisão"
ok "o craft-audio-route nasce em ≤5s e conserta o default fantasma (fifine) no primeiro ciclo"

# ── 5. O que a cura NÃO toca (os limites honestos) ─────────────────────────
say "5/5 · LIMITES"
ok "hyprlock fantasma (pid velho): NÃO é morto aqui — o craft-lock novo o mata no PRÓXIMO lock (matar o locker com a tela travada destravaria a sessão)"
ok "firstboot/bell: no rig é passado (one-shot por instalação) — a cura vale para as PRÓXIMAS instalações"
ok "jack sem detecção (availability unknown): limitação de hardware — o W-a/pavucontrol mandam lá"
printf '\nCura E30 completa. Provas: marcadores + sha256 acima; reversão: os .bak ao lado de cada arquivo.\n'
printf 'O próximo papel (sudo craft-dump --upload) já sai da main como v2.6 — com o áudio inteiro no papel.\n'
