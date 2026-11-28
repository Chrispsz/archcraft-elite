#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Archcraft ELITE · cura-e31.sh — pt-BR completo + o suspend destratado
# ═══════════════════════════════════════════════════════════════════════════
# O dono (pós-v2.10.18): "mistura de inglês com ptbr… como a data e o open
# terminal here" + "ele vai pra tela de bloqueio e fica todo tempo ligado
# nela e só desligo quando coloco a senha… assim nunca entra em idle como
# o modo suspender faz e já funciona".
#
# AS 3 CURAS (cada uma com a prova da causa):
#   1. SUSPEND-VIA-IDLE DESTRAVADO NO RIG — o idle.conf do rig carrega
#      SUSPEND_MIN=0 que NUNCA foi escolha do dono: o menu pré-v2.10.12
#      regravava o conf com ${SUSPEND_MIN:-0} (o próprio craft-idle da
#      época documenta o defeito: quem trocava o tempo de travar selava o
#      suspend em 'nunca'). Somado aos DOIS swayidle do dump p6aw (o mutex
#      E30 cura a corrida), o rig travava a tela e ficava ACORDADO para
#      sempre — exatamente o que o dono descreveu. Cura: conf normalizado
#      (0/ausente → 20, .bak + sha256), OFF_MIN ≥ LOCK_MIN garantido,
#      binários vigentes reinstalados, daemon reciclado — o fluxo volta a
#      ser: lock 10min → tela apaga 15min → suspend 20min.
#   2. RELÓGIO PT-BR — o strftime do waybar roda no locale DO PROCESSO
#      (não herda a sessão): config.top da main com
#      "locale": "pt_BR.UTF-8" explícito — "seg 31 out" em toda superfície.
#   3. BELL MUDO — foot.ini da main com urgent/notify = no: morto o wall
#      (E30), o que sobraria é BEL de programa/zsh virando toast na
#      central. Terminal não é fonte de avisos (doutrina "só o essencial").
#
# PROVA POR TIPO (a lição da revisão E31): prove_sh (bash -n) é para SHELL;
# JSONC (config.top) e INI (foot.ini) NÃO são shell — o '(' de um comentário
# derrubaria o bash -n e abortaria a cura NA MÃO DO DONO (a cura-e30 da
# v2.10.18 tinha exatamente essa mina em config.top e menu.xml — corrigida
# na mesma leva). Para dados: marcadores + arquivo não-vazio + pós-checagem.
#
# Escola cura-viva (E25/E26/E30): cada peça PROVADA antes de instalar,
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
RU="$(ls /run/user/ 2>/dev/null | grep -E '^[0-9]+$' | head -1)"
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

prove_data() { # $1=arquivo NÃO-shell (JSONC/INI/XML)  $2...=marcadores
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

say "CURA E31 — pt-BR completo + o suspend destratado no rig"

# ── 1. O SUSPEND-VIA-IDLE DESTRAVADO (a doença do "lock eterno") ──────────
say "1/4 · IDLE — SUSPEND_MIN destratado + fluxo na ordem (daemon reciclado)"
CONF="$UHOME/.config/elite/idle.conf"
if [ -f "$CONF" ]; then
    cp -a "$CONF" "$CONF.bak-$(date +%Y%m%d-%H%M%S)"
    cur="$(sed -n 's/^SUSPEND_MIN=//p' "$CONF" | head -1)"
    case "$cur" in
        ''|*[!0-9]*|0)
            if grep -q '^SUSPEND_MIN=' "$CONF"; then
                sed -i 's/^SUSPEND_MIN=.*/SUSPEND_MIN=20/' "$CONF"
            else
                printf 'SUSPEND_MIN=20\n' >>"$CONF"
            fi
            ok "SUSPEND_MIN → 20 (era '${cur:-<ausente>}' — o 0 era o SELO DO MENU ANTIGO, não escolha do dono; o PC volta a dormir aos 20min de idle)"
            ;;
        *)
            ok "SUSPEND_MIN=$cur preservado (número >0 = escolha explícita vigente — intocada)"
            ;;
    esac
    lmin="$(sed -n 's/^LOCK_MIN=//p' "$CONF" | head -1)"
    omin="$(sed -n 's/^OFF_MIN=//p' "$CONF" | head -1)"
    case "$lmin" in ''|*[!0-9]*) lmin=10 ;; esac
    case "$omin" in ''|*[!0-9]*) omin=15 ;; esac
    if [ "$lmin" -gt 0 ] && [ "$omin" -lt "$lmin" ]; then
        sed -i "s/^OFF_MIN=.*/OFF_MIN=$((lmin + 5))/" "$CONF"
        ok "OFF_MIN < LOCK_MIN corrigido → $((lmin + 5)) (a tela NÃO PODE APAGAR ANTES DO LOCK — a ordem do fluxo é lei)"
    else
        ok "fluxo na ordem: lock ${lmin}min → tela ${omin}min → suspend $(sed -n 's/^SUSPEND_MIN=//p' "$CONF" | head -1)min"
    fi
    chown "$(stat -c %u:%g "$UHOME")" "$CONF" 2>/dev/null || true
    sha256sum "$CONF"
else
    ok "sem $CONF — o skel de fábrica (10/15/20) vale no próximo boot; nada a migrar"
fi

# os binários vigentes da main: o mutex E30 impede o duplo swayidle de
# voltar; o craft-bars novo supervisiona idle E áudio. Idempotente, .bak.
for piece in craft-idle craft-bars; do
    fetch "elite/airootfs/usr/local/bin/$piece" "$T/$piece" || die "falha ao baixar $piece (sem rede?)"
done
prove_sh "$T/craft-idle" 'MUTEX DO SPAWN' 'idle-start.lock'
prove_sh "$T/craft-bars" 'SINGLETON' 'craft-idle start'
install_piece "$T/craft-idle" /usr/local/bin/craft-idle 755 'MUTEX DO SPAWN'
install_piece "$T/craft-bars" /usr/local/bin/craft-bars 755 'SINGLETON'

# ── 2. O RELÓGIO PT-BR (locale EXPLÍCITO no waybar) ───────────────────────
say "2/4 · RELÓGIO — data 'seg 31 out' (locale do processo, não da sessão)"
fetch "elite/airootfs/etc/skel/.config/waybar/config.top" "$T/config.top" || die "falha ao baixar config.top"
prove_data "$T/config.top" '"locale": "pt_BR.UTF-8"' '"interval": 1' 'on-scroll-up'
CT="$UHOME/.config/waybar/config.top"
install_piece "$T/config.top" "$CT" 644 '"locale": "pt_BR.UTF-8"'
chown "$(stat -c %u:%g "$UHOME")" "$CT" 2>/dev/null || true

# o locale do SISTEMA só nasce se não existir: no rig o calamares já
# escreveu pt_BR (dump nl3z:364 — o papel provou); sobrescrever o locale
# de quem escolheu outro idioma seria briga com escolha alheia
if [ ! -e /etc/locale.conf ]; then
    fetch "elite/airootfs/etc/locale.conf" "$T/locale.conf" || die "falha ao baixar locale.conf"
    prove_data "$T/locale.conf" 'LANG=pt_BR.UTF-8'
    install -m 644 "$T/locale.conf" /etc/locale.conf
    ok "/etc/locale.conf criado (LANG=pt_BR.UTF-8 — vale no próximo login)"
else
    ok "/etc/locale.conf já existe ($(sed -n 's/^LANG=//p' /etc/locale.conf | head -1)) — instalador escreveu; intocado"
fi

# ── 3. O BELL MUDO (foot sem toast/urgência) ──────────────────────────────
say "3/4 · TERMINAL — bell mudo (morto o wall E30, BEL não vira toast)"
fetch "elite/airootfs/etc/skel/.config/foot/foot.ini" "$T/foot.ini" || die "falha ao baixar foot.ini"
prove_data "$T/foot.ini" 'urgent = no' 'notify = no' 'shell = /usr/bin/zsh -l'
FT="$UHOME/.config/foot/foot.ini"
install_piece "$T/foot.ini" "$FT" 644 'notify = no'
chown "$(stat -c %u:%g "$UHOME")" "$FT" 2>/dev/null || true

# ── 4. RECICLAGEM DA SESSÃO (o supervisor novo renasce tudo em ≤5s) ───────
say "4/4 · RECICLAGEM — waybar + idle sob o supervisor novo"
pkill -x swayidle 2>/dev/null && ok "swayidle velho encerrado — o supervisor renasce UM com o conf corrigido" \
    || ok "nenhum swayidle vivo — o supervisor cuida do nascimento"
pkill -x waybar 2>/dev/null && ok "waybar velho encerrado — renasce com o relógio pt-BR" \
    || ok "nenhum waybar vivo — o supervisor cuida do nascimento"
pkill -f '/bin/sh /usr/local/bin/craft-bars' 2>/dev/null || true
sleep 1
if [ -n "${SUDO_USER:-}" ]; then
    runuser -u "${SUDO_USER}" -- env XDG_RUNTIME_DIR="/run/user/${RU}" HOME="$UHOME" \
        setsid /usr/local/bin/craft-bars >>"$UHOME/.cache/elite/bars.log" 2>&1 &
else
    sudo -n -u "#$RU" env XDG_RUNTIME_DIR="/run/user/${RU}" HOME="$UHOME" \
        setsid /usr/local/bin/craft-bars >>"$UHOME/.cache/elite/bars.log" 2>&1 &
fi
ok "craft-bars novo no ar (flock único) — waybar/idle/audio-route sob a MESMA supervisão"
ok "o foot vale nos PRÓXIMOS terminais (foot.ini é lido por janela, sem daemon)"

# ── LIMITES honestos ──────────────────────────────────────────────────────
say "LIMITES"
ok "jack sem detecção (availability unknown): limitação de hardware — software não adivinha plug; W-a/pavucontrol mandam lá"
ok "o 'Abrir terminal aqui' do Thunar no rig JÁ é pt-BR (o calamares escreveu LANG=pt_BR — dump nl3z:364); o inglês que o dono viu foi a SESSÃO LIVE, sem locale.conf — a ISO v2.10.19 nasce correta de fábrica"
ok "quem ESCOLHEU 'Suspender: Nunca' no menu NOVO (v2.10.12+): reponha pelo menu depois desta cura — aqui o 0 é tratado como selo da era antiga"
printf '\nCura E31 completa. Provas: marcadores por tipo + sha256 acima; reversão: os .bak ao lado de cada arquivo.\n'
printf 'Veredito visual: relógio em pt-BR em ≤5s; PC dorme aos 20min de inatividade (lock 10 → tela 15 → suspend 20).\n'
