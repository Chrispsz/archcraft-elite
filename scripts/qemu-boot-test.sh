#!/usr/bin/env bash
# =====================================================================
#  qemu-boot-test.sh — loop local RÁPIDO de boot da ISO (sem runner)
#
#  O gate `verify` do CI boota a ISO no QEMU TCG (runner público não tem
#  KVM) e espera até ~55 min. Numa máquina com KVM o MESMO teste fecha em
#  ~1-2 min. Este script replica o gate com fidelidade:
#    · extrai a cmdline REAL da entrada default (syslinux) da ISO —
#      a lição da build #43: nunca inventar cmdline própria
#    · só ajusta observabilidade (sem quiet/splash, loglevel=7, serial)
#    · veredito idêntico: Startup finished / sem shell de emergência /
#      sem 203/EXEC / timeout 90s presente ([6.2])
#
#  Uso:  scripts/qemu-boot-test.sh <caminho/para/archcraft-elite.iso>
#  Requer: qemu-system-x86_64, 7z (p7zip-full), root NÃO necessário.
#  Saída: serial salvo em /tmp/elite-serial.log + exit 0/1 (gate).
# =====================================================================
set -uo pipefail

ISO="${1:-}"
[[ -n "$ISO" && -f "$ISO" ]] || { echo "uso: $0 <arquivo.iso>" >&2; exit 2; }
command -v qemu-system-x86_64 >/dev/null || { echo "✖ qemu-system-x86_64 ausente" >&2; exit 2; }
# Arch: pacote 7zip fornece 7zz; Ubuntu/CI: p7zip-full fornece 7z
SEVENZ="$(command -v 7z || command -v 7zz || true)"
[[ -n "$SEVENZ" ]] || { echo "✖ 7z ausente (Arch: 7zip · Debian: p7zip-full)" >&2; exit 2; }

WORK="$(mktemp -d /tmp/elite-boot.XXXXXX)"
SERIAL="$WORK/serial.log"
trap 'rm -rf "$WORK"' EXIT

# kernel BORE + initrd + entrada default do syslinux (a que o usuário boota)
"$SEVENZ" x -y -o"$WORK" "$ISO" \
  'arch/boot/x86_64/vmlinuz-linux-cachyos-bore' \
  'arch/boot/x86_64/initramfs-linux-cachyos-bore.img' \
  'boot/syslinux/archiso_sys-linux.cfg' >/dev/null \
  || { echo "✖ extração 7z falhou (ISO íntegra?)" >&2; exit 2; }

ENTRY="$WORK/boot/syslinux/archiso_sys-linux.cfg"
APPEND_ISO="$(grep -m1 '^APPEND ' "$ENTRY" | sed 's/^APPEND //')"
[[ -n "$APPEND_ISO" ]] || { echo "✖ APPEND ausente em $ENTRY" >&2; exit 2; }
echo "── cmdline REAL da ISO (default, BORE): $APPEND_ISO"

# mesmo ajuste do gate: só observabilidade (serial), nada funcional
APPEND_GATE="$(printf '%s' "$APPEND_ISO" \
  | sed -e 's/quiet splash //' -e 's/loglevel=[0-9]*/loglevel=7/')"
APPEND_GATE="$APPEND_GATE console=ttyS0,115200 systemd.log_target=console systemd.log_level=info systemd.show_status=yes"

ACCEL=(-cpu max)
if [[ -w /dev/kvm ]]; then
  ACCEL=(-enable-kvm -cpu host)
  echo "── KVM detectado — boot em ~1-2 min"
else
  echo "── KVM ausente — TCG (lento; no CI leva até ~55 min)"
fi

qemu-system-x86_64 \
  -machine q35 -smp 2 -m 7168 "${ACCEL[@]}" \
  -kernel "$WORK/arch/boot/x86_64/vmlinuz-linux-cachyos-bore" \
  -initrd "$WORK/arch/boot/x86_64/initramfs-linux-cachyos-bore.img" \
  -append "$APPEND_GATE" \
  -cdrom "$ISO" \
  -nographic -no-reboot -nic user \
  > "$SERIAL" 2>&1 &
Q=$!

# espera ativa: sai no 'Startup finished' OU no shell de emergência
VERDICT=TIMEOUT
for _ in $(seq 1 720); do          # até 60 min no pior caso TCG
  grep -q 'Startup finished' "$SERIAL" 2>/dev/null && { VERDICT=BOOT_COMPLETO; break; }
  grep -q 'rootfs ~]#' "$SERIAL" 2>/dev/null && { VERDICT=EMERGENCIA; break; }
  kill -0 "$Q" 2>/dev/null || break
  sleep 5
done
# v1.7.1 — PROBE DA SESSÃO GRÁFICA: o gate antigo parava no LOGIN e nunca
# viu a sessão (a classe "barras mortas" atravessou v1.6.2→v1.7.0 invisível).
# O elite-session-probe.service roda 60s pós-graphical.target e imprime o
# estado REAL da sessão no console (= serial aqui). Espera o bloco marcado.
if [ "$VERDICT" = "BOOT_COMPLETO" ]; then
  for _ in $(seq 1 48); do         # até +240s pela sessão (autologin→labwc→probe)
    grep -q 'ELITE_PROBE_END' "$SERIAL" 2>/dev/null && break
    kill -0 "$Q" 2>/dev/null || break
    sleep 5
  done
fi
sleep 5                            # logs finais (flush do probe)
kill "$Q" 2>/dev/null; wait "$Q" 2>/dev/null

echo "════════ ÚLTIMAS 30 LINHAS DO SERIAL (cópia em $SERIAL — apaga com o EXIT trap) ════════"
tail -30 "$SERIAL" || true
cp "$SERIAL" /tmp/elite-serial.log 2>/dev/null || true

FAIL=0
chk() { # $1=condição(0=ok) $2=ok $3=falha
  if [ "$1" -eq 0 ]; then echo "✔ $2"; else echo "✖ $3"; FAIL=1; fi
}
grep -q 'Startup finished' "$SERIAL"
chk $? "boot COMPLETO (Startup finished)" "boot NÃO completou (ver /tmp/elite-serial.log)"
! grep -q 'rootfs ~]#' "$SERIAL"
chk $? "sem shell de emergência" "initramfs caiu em shell de emergência"
! grep -qE 'code=203/EXEC|Unable to locate executable' "$SERIAL"
chk $? "binários Elite executáveis (sem 203/EXEC)" "203/EXEC no live: binário 0644 no squashfs"
grep -q 'systemd.default_timeout_start_sec=90' "$ENTRY"
chk $? "cmdline real com timeout 90s ([6.2] presente)" "ISO SEM timeout 90s no cmdline — fix [6.2] regrediu"

# v1.7.1 — GATE DA SESSÃO: o que o dono vê NÃO é o login, é a sessão. Desde
# a v2.0 a sessão é waybar top + dock NATIVA (craft-dock-gui, GTK) — o probe
# reporta WAYBAR_COUNT e DOCK_COUNT, e o gate cobra os dois ≥1 e zero mortes
# (BARS_EXITS conta os 'SAIU exit=' do craft-bars — cada morte deixa linha
# com hora+exit code). O "-ge 2" da era waybar-dock era contrato defasado: a
# #93 flagrou 1/2 com a dock crash-loopando por pin inexistente. Se o probe
# NÃO chegou (QEMU headless sem sessão), informativo — o gate não cobra o
# que não pode ver.
if grep -q 'ELITE_PROBE_END' "$SERIAL" 2>/dev/null; then
  echo "── bloco do probe da sessão:"
  sed -n '/ELITE_PROBE_BEGIN/,/ELITE_PROBE_END/p' "$SERIAL" | sed 's/^/   /'
  WC="$(sed 's/\x1b\[[0-9;]*m//g' "$SERIAL" | grep -oE 'WAYBAR_COUNT=[0-9]+' | head -1 | cut -d= -f2)"
  DK="$(sed 's/\x1b\[[0-9;]*m//g' "$SERIAL" | grep -oE 'DOCK_COUNT=[0-9]+' | head -1 | cut -d= -f2)"
  BE="$(sed 's/\x1b\[[0-9;]*m//g' "$SERIAL" | grep -oE 'BARS_EXITS=[0-9]+' | head -1 | cut -d= -f2)"
  [ -n "$WC" ] && [ "$WC" -ge 1 ] 2>/dev/null
  chk $? "sessão gráfica VIVA: waybar top vivo (probe: WAYBAR_COUNT=${WC:-0})" "PROBLEMA REAL DE SESSÃO: waybar top não está vivo (${WC:-0}) — classe 'subiu só o wallpaper' (ver BARS| acima)"
  [ -n "$DK" ] && [ "$DK" -ge 1 ] 2>/dev/null
  chk $? "sessão gráfica VIVA: dock nativa viva (probe: DOCK_COUNT=${DK:-0})" "PROBLEMA REAL DE SESSÃO: dock craft-dock-gui NÃO está viva (${DK:-0}) — pin quebrado/crash (ver BARS| acima)"
  [ -n "$BE" ] && [ "$BE" -eq 0 ] 2>/dev/null
  chk $? "barras sem NENHUMA morte na sessão (BARS_EXITS=${BE:-?})" "barra(s) morreram ${BE:-?}× na sessão — crash/race/pin quebrado (exit code no BARS| acima)"
else
  echo "· informativo: probe da sessão NÃO chegou (QEMU sem sessão gráfica?) — gate não cobra o que não vê"
fi

echo "── veredito: $VERDICT (serial completo: /tmp/elite-serial.log)"
exit "$FAIL"
