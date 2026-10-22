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
sleep 20                            # logs pós-target (sessão/autologin)
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

echo "── veredito: $VERDICT (serial completo: /tmp/elite-serial.log)"
exit "$FAIL"
