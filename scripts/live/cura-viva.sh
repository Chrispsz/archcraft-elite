#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Archcraft ELITE · cura-viva (E25 — o rig se cura SEM reinstalar)
# ═══════════════════════════════════════════════════════════════════════════
# O problema do campo (out/2026): o rig 10.9 carrega craft-dump v2.1 que
# morre na linha 341 ('$CACHE: variável não associada' — seções 13/14
# NUNCA saem no papel) e a cura E24 do despertar imediato não existe lá.
# Reinstalar a ISO inteira para trocar 4 arquivos é custo indevido.
#
# ESTE script baixa DA MAIN do repo (raw público — sem credencial na
# máquina do dono), PROVA cada peça antes de instalar (bash -n + marcador
# de conteúdo), guarda o velho como .bak-<stamp>, instala as 4 peças e
# APLICA a cura a quente (regra udev recarregada + wake-guard off) — sem
# reboot. Um comando, auditável: todo sha256 fica no terminal.
#
# Uso (o one-liner do campo):
#   curl -fsSL https://raw.githubusercontent.com/Chrispsz/archcraft-elite/main/scripts/live/cura-viva.sh -o /tmp/cura-viva.sh && sudo bash /tmp/cura-viva.sh
#
# Peças instaladas (todas da main, na hora do run):
#   /usr/local/bin/craft-dump                          (v2.5+ — perícia viva)
#   /usr/local/bin/craft-wake-guard                    (E24 — status/off/on)
#   /etc/udev/rules.d/90-elite-wake-guard.rules        (E24 — desarma USB no boot)
#   /usr/lib/systemd/system-sleep/elite-sleep-report   (E24 — perícia do sono)
#
# Efeito da cura: o PC dorme de verdade (sem despertar sozinho via USB);
# acordar = BOTÃO DE POWER. Reversível: sudo craft-wake-guard on.
# Nada de comportamento às escondidas: idle.conf do dono NÃO é tocado.
# ═══════════════════════════════════════════════════════════════════════════
set -u

RAW="https://raw.githubusercontent.com/Chrispsz/archcraft-elite/main"
STAMP="$(date +%Y%m%d-%H%M%S)"

die() { printf 'cura-viva: %s\n' "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "precisa root — rode:
  curl -fsSL $RAW/scripts/live/cura-viva.sh -o /tmp/cura-viva.sh && sudo bash /tmp/cura-viva.sh"

fetch() { # fetch <caminho-no-repo> <destino>
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 30 "$RAW/$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 30 -O "$2" "$RAW/$1"
    else
        die "nem curl nem wget no sistema — nada mudou"
    fi
}

install_piece() { # install_piece <src-tmp> <dest> <mode> <marcador> <nome-humano>
    local src="$1" dst="$2" mode="$3" marker="$4" nome="$5"
    grep -q "$marker" "$src" || die "RECUSADO: $nome chegou sem a prova de conteúdo ('$marker') — abortado"
    [ -f "$dst" ] && cp -p "$dst" "${dst}.bak-${STAMP}"
    install -m "$mode" "$src" "$dst"
    printf '  ✓ %-46s (velho: %s.bak-%s)\n' "$dst" "$dst" "$STAMP"
    printf '      sha256: %s\n' "$(sha256sum "$dst" | cut -d' ' -f1)"
}

printf '═══ cura-viva · %s ═══\n' "$(date)"
printf '── 1/4 baixando as peças da main (raw público)…\n'
T="$(mktemp -d /tmp/cura-viva.XXXXXX)"
trap 'rm -rf "$T"' EXIT

fetch "elite/airootfs/usr/local/bin/craft-dump" "$T/craft-dump" \
    || die "download do craft-dump falhou (rede?) — NADA mudou no sistema"
fetch "elite/airootfs/usr/local/bin/craft-wake-guard" "$T/craft-wake-guard" \
    || die "download do craft-wake-guard falhou — NADA mudou no sistema"
fetch "elite/airootfs/etc/udev/rules.d/90-elite-wake-guard.rules" "$T/rule" \
    || die "download da regra udev falhou — NADA mudou no sistema"
fetch "elite/airootfs/usr/lib/systemd/system-sleep/elite-sleep-report" "$T/sleep-report" \
    || die "download do hook system-sleep falhou — NADA mudou no sistema"

printf '── 2/4 provando cada peça (bash -n + marcador de conteúdo)…\n'
bash -n "$T/craft-dump" || die "craft-dump baixado NÃO compila — abortado, nada instalado"
bash -n "$T/craft-wake-guard" || die "craft-wake-guard baixado NÃO compila — abortado, nada instalado"
bash -n "$T/sleep-report" || die "elite-sleep-report baixado NÃO compila — abortado, nada instalado"
grep -q 'ELITE DUMP' "$T/craft-dump" || die "craft-dump sem o banner ELITE DUMP — abortado"
grep -q 'ACTION=="add"' "$T/rule" || die "regra udev sem ACTION==\"add\" — abortado"
grep -q 'ATTR{power/wakeup}="disabled"' "$T/rule" || die "regra udev sem wakeup=disabled — abortado"

printf '── 3/4 instalando (o velho de cada peça vira .bak-%s)…\n' "$STAMP"
install_piece "$T/craft-dump" /usr/local/bin/craft-dump 755 'ELITE DUMP' 'craft-dump'
install_piece "$T/craft-wake-guard" /usr/local/bin/craft-wake-guard 755 'craft-wake-guard' 'craft-wake-guard'
install_piece "$T/rule" /etc/udev/rules.d/90-elite-wake-guard.rules 644 '90-elite-wake-guard' 'regra udev E24'
install_piece "$T/sleep-report" /usr/lib/systemd/system-sleep/elite-sleep-report 755 'elite-sleep' 'elite-sleep-report'

printf '── 4/4 aplicando a cura a quente (sem reboot)…\n'
if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --action=add --subsystem-match=pci 2>/dev/null || true
    printf '  ✓ regra udev recarregada + disparada para o PCI já presente\n'
else
    printf '  (udevadm ausente — a regra vale no próximo boot)\n'
fi

printf '\n── estado do wakeup AGORA (o próximo dump julga este mesmo papel):\n'
/usr/local/bin/craft-wake-guard status 2>/dev/null || true

printf '\n── desarmando os controladores USB (o mesmo gesto da regra em todo boot):\n'
/usr/local/bin/craft-wake-guard off 2>/dev/null || true

printf '\n═══ CURA APLICADA ═══\n'
printf '  · o próximo papel nasce COMPLETO: sudo craft-dump --upload  → mande a URL\n'
printf '    (o craft-dump novo tem --update: perícia nunca mais envelhece no rig)\n'
printf '  · efeito: o PC dorme de verdade; acordar = BOTÃO DE POWER\n'
printf '    (porta de volta: sudo craft-wake-guard on)\n'
printf '  · o idle.conf do dono não foi tocado (LOCK_MIN/OFF_MIN/SUSPEND_MIN seus)\n'
