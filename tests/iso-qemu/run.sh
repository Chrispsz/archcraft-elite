#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════
# tests/iso-qemu/run.sh — NÍVEL 3 DA SUTE REAL (a ISO BOOTADA no QEMU)
# ═════════════════════════════════════════════════════════════════════════
# O produto final validado COMO O DONO O RECEBE: a ISO boota no QEMU
# (KVM quando há; TCG quando não — a lei do gate do CI), a sessão
# gráfica labwc sobe pela primeira vez com a família 2.0 e O PAPEL sai
# de DENTRO da VM: o craft-dump v2 + o journalctl do boot, colhidos
# pelo console serial (a ISO da casa autologa no live; o ttyS0 é a
# porta de verdade para a perícia pós-build).
#
# O MÉTODO (a lição do gate verify do build.yml + scripts/qemu-boot-test):
#   · a cmdline REAL da entrada default da ISO (7z extrai o syslinux —
#     nunca inventar cmdline própria: a lição da build #43);
#   · só observabilidade muda (sem quiet/splash, loglevel=7, ttyS0);
#   · o serial é UM SOCKET UNIX (server=on,wait=off): um socat colhe o
#     LOG contínuo (os marcos do boot) e OUTRO injeta os comandos do
#     papel quando o autologin atende;
#   · veredito: boot até a família 2.0 de pé + o papel v2 colhido = GO.
#
# Uso: bash tests/iso-qemu/run.sh [caminho/para/archcraft-elite.iso]
#      (sem argumento: a ISO mais recente do out/ da árvore)
# Requer: qemu-system-x86_64, 7z/7zz, socat
# ═════════════════════════════════════════════════════════════════════════
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
REPO="$(pwd)"
WORK="$(mktemp -d /tmp/elite-isoq.XXXXXX)"
SERIAL="$WORK/serial.log"
PAPER="$WORK/papel.log"
CONSOLE="$WORK/console.sock"
trap 'rm -rf "$WORK"' EXIT

ISO="${1:-}"
if [ -z "$ISO" ]; then
    ISO="$(ls -t out/archcraft-elite-*.iso 2>/dev/null | head -1 || true)"
fi
[ -n "$ISO" ] && [ -f "$ISO" ] || { echo "uso: $0 <arquivo.iso> (ou uma ISO em out/)" >&2; exit 2; }
command -v qemu-system-x86_64 >/dev/null || { echo "✖ qemu-system-x86_64 ausente" >&2; exit 2; }
SEVENZ="$(command -v 7z || command -v 7zz || true)"
[ -n "$SEVENZ" ] || { echo "✖ 7z ausente (Arch: 7zip · Debian: p7zip-full)" >&2; exit 2; }
command -v socat >/dev/null || { echo "✖ socat ausente" >&2; exit 2; }

# ── 1. a cmdline REAL da ISO (a entrada default do syslinux) ─────────────
"$SEVENZ" x -y -o"$WORK" "$ISO" \
    'arch/boot/x86_64/vmlinuz-linux-cachyos-bore' \
    'arch/boot/x86_64/initramfs-linux-cachyos-bore.img' \
    'boot/syslinux/archiso_sys-linux.cfg' >/dev/null \
    || { echo "✖ extração 7z falhou (ISO íntegra?)" >&2; exit 2; }
ENTRY="$WORK/boot/syslinux/archiso_sys-linux.cfg"
APPEND="$(grep -m1 '^APPEND ' "$ENTRY" | sed 's/^APPEND //')"
[ -n "$APPEND" ] || { echo "✖ APPEND ausente em $ENTRY" >&2; exit 2; }
echo "── cmdline REAL da ISO (default, BORE): $APPEND"

# observabilidade (a mesma do gate): serial + loglevel; nada funcional
APPEND_GATE="$(printf '%s' "$APPEND" \
    | sed -e 's/quiet splash //' -e 's/loglevel=[0-9]*/loglevel=7/')"
APPEND_GATE="$APPEND_GATE console=ttyS0,115200 systemd.log_target=console systemd.log_level=info systemd.show_status=yes"

# ── 2. o QEMU: KVM quando há (a lição do verify: -cpu max no TCG matava
#       o handoff BORE; o serial é SOCKET — o log e o papel moram nele)
ACCEL=(-cpu max)
if [ -w /dev/kvm ]; then
    ACCEL=(-enable-kvm -cpu host)
fi
qemu-system-x86_64 "${ACCEL[@]}" \
    -machine q35 -m 4096 -smp 2 \
    -nographic -monitor none \
    -serial "unix:$CONSOLE,server=on,wait=off" \
    -cdrom "$ISO" \
    -append "$APPEND_GATE" \
    -kernel "$WORK/arch/boot/x86_64/vmlinuz-linux-cachyos-bore" \
    -initrd "$WORK/arch/boot/x86_64/initramfs-linux-cachyos-bore.img" &
QEMU_PID=$!

# o coletor contínuo do serial (conecta já: o boot começa em segundos)
socat -u "UNIX-CONNECT:$CONSOLE" - >>"$SERIAL" 2>/dev/null &
CAP_PID=$!

# ── 3. os marcos do boot (cada um nomeado; o teto é a lei do TCG) ────────
marco() { # marco <padrão> <teto_s>
    local padrao="$1" teto="${2:-180}"
    local alvo=$((SECONDS + teto))
    while [ $SECONDS -lt $alvo ]; do
        kill -0 $QEMU_PID 2>/dev/null || break
        if grep -q "$padrao" "$SERIAL" 2>/dev/null; then
            echo "  ✓ marco: $padrao"
            return 0
        fi
        sleep 3
    done
    echo "  ✗ marco: $padrao (teto ${teto}s — o serial em /tmp/elite-isoq-serial.log diz o porquê)"
    return 1
}

echo "── boota a ISO (TCG: teto de lei maior; KVM: ~2min)"
RC=0
marco 'archlive\|liveuser\|login' 420 || RC=1
marco 'elite-daemon: bus VIVO\|elite-daemon session' 420 || RC=1
marco 'craft-bar-rs' 180 || RC=1
marco 'craft-dock-rs' 180 || RC=1

# ── 4. O PAPEL DE DENTRO da VM (o autologin do live atende no ttyS0):
#       o craft-dump v2 + o journal do boot saem pelo MESMO socket
if [ $RC -eq 0 ]; then
    echo "── o papel da VM (craft-dump v2 + journalctl)"
    printf '\n/usr/local/bin/craft-dump 2>&1\njournalctl -b --no-pager 2>&1 | tail -n 120\n' \
        | timeout 90 socat - "UNIX-CONNECT:$CONSOLE" >>"$PAPER" 2>/dev/null
    if grep -q 'era nativa 2.0' "$PAPER" 2>/dev/null; then
        echo "  ✓ o papel v2 colhido de DENTRO da VM ($(wc -l <"$PAPER") linhas)"
    else
        echo "  ✗ o papel v2 não saiu (o autologin não atendeu no serial? o papel em /tmp/elite-isoq-papel.log)"
        RC=1
    fi
fi

# desliga a VM (a misericórdia do fim de prova) e o coletor
kill $QEMU_PID 2>/dev/null || true
kill $CAP_PID 2>/dev/null || true
wait $QEMU_PID 2>/dev/null || true

# ── 5. veredito (a evidência fica em /tmp para a perícia)
cp "$SERIAL" /tmp/elite-isoq-serial.log 2>/dev/null || true
[ -f "$PAPER" ] && cp "$PAPER" /tmp/elite-isoq-papel.log 2>/dev/null || true
if [ $RC -eq 0 ]; then
    echo "══ VEREDICTO: GO (a ISO boota até a família 2.0 — serial e papel em /tmp/elite-isoq-*)"
    exit 0
fi
echo "══ VEREDICTO: NO-GO (serial em /tmp/elite-isoq-serial.log — os marcos faltantes estão nomeados acima)"
exit 1
