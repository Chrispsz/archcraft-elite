#!/usr/bin/env bash
# FASE 4 — A CADEIA: integração (peças encaixando: a saída de uma é a entrada da outra)
source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"
phase_start 4 "CADEIA — peças encaixando"

# ════════════════════════════════════════════════════════════════════
# 4.A o overlay inteiro contra o upstream-fixture (apply-overlay REAL,
# clone redirecionado por git insteadOf — zero rede, zero config global)
# ════════════════════════════════════════════════════════════════════
RE="$WORK/repo"; rm -rf "$RE" "$RE-out"
mkdir -p "$RE"
cp -a "$REPO/elite" "$REPO/scripts" "$RE/"

if out="$( cd "$RE" && HOME="$WORK/home" bash scripts/apply-overlay.sh 2>&1 )" ; then
  ok "overlay: roda limpo contra o fixture"
else
  fail "overlay: roda limpo contra o fixture" "${out:0:300}"
fi

P="$RE/elite-build/archcraft"   # profile transformado
assert_file "$P/packages.x86_64" "cadeia A: elite-build/archcraft existe (profile detectado)"

PKG="$P/packages.x86_64"
assert_grep "$PKG" '^#cups # ELITE-REMOVED$' "cadeia A: cups comentado com marcador ELITE-REMOVED"
assert_nogrep "$PKG" '^cups$' "cadeia A: cups ativo sumiu"
assert_grep "$PKG" '^#archcraft-sway-free # ELITE-REMOVED$' "cadeia A: archcraft-sway-free debloatado"
assert_grep "$PKG" '^#linux-firmware # ELITE-REMOVED' "cadeia A: meta linux-firmware comentado"
assert_grep "$PKG" '^linux-firmware-amd$' "cadeia A: subpacote firmware amd presente"
assert_eq "$(grep -cx 'vulkan-radeon' "$PKG")" "1" "cadeia A: vulkan-radeon 1× (dedupe — add não duplica)"
assert_eq "$(grep -cx 'vulkan-intel'  "$PKG")" "1" "cadeia A: vulkan-intel 1× (append do packages.add)"
dups=$(sort "$PKG" | uniq -d | wc -l)
assert_eq "$dups" "0" "cadeia A: packages.x86_64 sem nenhuma duplicata"

PC="$P/pacman.conf"
assert_grep "$PC" '^\[elite-local\]' "cadeia A: repo [elite-local] injetado"
el=$(grep -n '^\[elite-local\]' "$PC" | cut -d: -f1); ac=$(grep -n '^\[archcraft\]' "$PC" | head -1 | cut -d: -f1)
[[ -n "$el" && -n "$ac" && "$el" -lt "$ac" ]] \
  && ok "cadeia A: [elite-local] ANTES de [archcraft] (file:// resolve primeiro)" \
  || fail "cadeia A: [elite-local] ANTES de [archcraft]" "el=$el ac=$ac"
assert_grep "$PC" '^SigLevel = Never$' "cadeia A: [archcraft] SigLevel → Never (zero sondas .sig)"
cv=$(grep -n '^\[cachyos-v3\]' "$PC" | head -1 | cut -d: -f1); co=$(grep -n '^\[core\]' "$PC" | head -1 | cut -d: -f1)
[[ -n "$cv" && -n "$co" && "$cv" -lt "$co" ]] \
  && ok "cadeia A: trio cachyos-v3 ANTES de [core] (v3 ganha a resolução)" \
  || fail "cadeia A: trio antes de [core]" "cv=$cv co=$co"
assert_grep "$PC" '^Architecture = x86_64 x86_64_v3$' "cadeia A: Architecture aceita v3"
assert_grep "$PC" '^XferCommand = /usr/bin/curl' "cadeia A: XferCommand resiliente"
assert_grep "$PC" '^ParallelDownloads = 10$' "cadeia A: ParallelDownloads = 10"
assert_nogrep "$PC" '^DownloadUser' "cadeia A: DownloadUser removido (o container não deixa)"

E01="$P/efiboot/loader/entries/01-archiso-linux.conf"
E02="$P/efiboot/loader/entries/02-archiso-opensource.conf"
E03="$P/efiboot/loader/entries/03-archiso-nvidia.conf"
assert_grep "$E01" 'vmlinuz-linux-cachyos-bore' "cadeia A: entrada default (UEFI) → kernel BORE"
assert_grep "$E01" 'BORE kernel' "cadeia A: título default rebatizado Elite"
assert_nogrep "$E01" 'initramfs-linux\.img' "cadeia A: initramfs default trocado (sem vestígio stock)"
assert_grep "$E02" 'vmlinuz-linux-cachyos-bore' "cadeia A: entrada opensource (UEFI) → kernel BORE"
assert_grep "$E03" 'vmlinuz-linux$' "cadeia A (A COROA): entrada NVIDIA permanece no kernel STOCK"
assert_nogrep "$E03" 'cachyos-bore' "cadeia A: entrada NVIDIA intocada pelo BORE"

SL="$P/syslinux/archiso_sys-linux.cfg"
assert_eq "$(grep -c 'vmlinuz-linux-cachyos-bore' "$SL")" "1" "cadeia A: syslinux default → BORE (1×)"
assert_grep "$SL" 'LABEL archnonfree' "cadeia A: bloco archnonfree preservado"
grep -A3 '^LABEL archnonfree' "$SL" | grep -q 'vmlinuz-linux$' \
  && ok "cadeia A: archnonfree segue no kernel stock (BIOS)" \
  || fail "cadeia A: archnonfree segue no kernel stock (BIOS)" "bloco foi reescrito"

GR="$P/grub/grub.cfg"
assert_grep "$GR" "--id 'archcraftpn'" "cadeia A: menuentry NVIDIA (archcraftpn) preservado"
# o bloco do pn precisa continuar em vmlinuz-linux + initramfs-linux-nvidia.img (stock)
if grep -A4 -- "--id 'archcraftpn'" "$GR" | grep -q 'nvidia nvidia-drm.modeset=1'; then
  ok "cadeia A: bloco NVIDIA segue no kernel stock (BIOS/loopback)"
else
  fail "cadeia A: bloco NVIDIA segue no kernel stock (BIOS/loopback)" "params nvidia sumiram do bloco"
fi
if grep -A4 -- "--id 'archcraftpn'" "$GR" | grep -q 'initramfs-linux-nvidia\.img'; then
  ok "cadeia A: initramfs-nvidia.img exclusivo do stock preservado"
else
  fail "cadeia A: initramfs-nvidia.img preservado" "linha ausente no bloco pn"
fi
assert_eq "$(grep -c 'vmlinuz-linux-cachyos-bore' "$GR")" "3" \
  "cadeia A: default+opensource+nomodeset → BORE (3×, NVIDIA fora)"
assert_grep "$GR" "--id 'archcraftos'" "cadeia A: menuentry opensource presente"
assert_grep "$GR" "--id 'archcraftnm'" "cadeia A: menuentry nomodeset presente"

W="$P/airootfs/etc/systemd/system/multi-user.target.wants"
[[ ! -L "$W/cups.service" && ! -L "$W/vmtoolsd.service" ]] \
  && ok "cadeia A: wants cups/vmtoolsd removidos (debloat de serviços)" \
  || fail "cadeia A: wants cups/vmtoolsd removidos" "sobrou link"
[[ -L "$W/sshd.service" ]] \
  && ok "cadeia A: sobrevivente sshd.service não foi punido por engano" \
  || fail "cadeia A: sobrevivente sshd.service" "link sumiu — padrão de delete largo demais"

CS="$P/airootfs/root/customize_airootfs.sh"
assert_eq "$(grep -c '\[\[ -f /etc/skel/.config/sway/scripts/startup \]\]' "$CS")" "2" \
  "cadeia A: guarda sway ×2 (o fix do run #17 aplicado no customize)"
assert_grep "$CS" 'ELITE_KEY=' "cadeia A: fragmento E0–E8 anexado ao customize"
cmp -s "$P/airootfs/usr/local/bin/elite-tune" "$REPO/elite/airootfs/usr/local/bin/elite-tune" \
  && ok "cadeia A: elite-tune idêntico ao overlay (rsync sem corrupção)" \
  || fail "cadeia A: elite-tune idêntico ao overlay" "diff no airootfs"
assert_file "$P/airootfs/usr/local/bin/hello-upstream" "cadeia A: arquivo upstream pré-existente não apagado"
assert_grep "$P/profiledef.sh" 'iso_name="archcraft-elite"' "cadeia A: ISO rebatizada archcraft-elite"
assert_nogrep "$P/mkarchcraftiso" 'pacstrap.* -i ' "cadeia A: pacstrap não-interativo (sem -i)"

# ════════════════════════════════════════════════════════════════════
# 4.B o ciclo split → hash → reassemble → conferir (o caminho da release,
# em miniatura: 5 MiB, mesmas regras do build.yml)
# ════════════════════════════════════════════════════════════════════
CH="$WORK/chain"; rm -rf "$CH"; mkdir -p "$CH"
head -c 5242880 /dev/urandom > "$CH/mini.bin"
ISO="mini.bin"
( cd "$CH" && sha256sum -- "$ISO" > sha256sums.txt )
( cd "$CH" && split -b 2097152 -d "$ISO" "${ISO}.part-" && rm -f "$ISO" )
( cd "$CH" && sha256sum -- "${ISO}.part-"* >> sha256sums.txt )
assert_file "$CH/mini.bin.part-00" "cadeia B: split produziu part-00"
parts=("$CH"/mini.bin.part-*)
assert_eq "${#parts[@]}" "3" "cadeia B: 3 partes (2 MiB + 2 MiB + 1 MiB)"
# o usuário final: junta e confere EXATAMENTE como o JUNTAR-ISO.md manda
( cd "$CH" && cat "${ISO}.part-"* > "$ISO" )
verif=$( cd "$CH" && sha256sum -c <(grep -E "part|$ISO\$" sha256sums.txt) 2>&1 )
assert_match "$verif" 'mini\.bin: OK' "cadeia B: sha256sum -c aprova (usuário confere antes de gravar)"
assert_match "$verif" 'part-00: OK' "cadeia B: partes conferem individualmente"
joined=$(sha256sum "$CH/mini.bin" | cut -d' ' -f1)
whole=$(grep ' mini.bin$' "$CH/sha256sums.txt" | cut -d' ' -f1)
assert_eq "$joined" "$whole" "cadeia B: ISO remontada é bit-a-bit a original"
# anti-tamper: 1 byte corrompido TEM que ser detectado
printf 'X' | dd of="$CH/mini.bin.part-01" bs=1 seek=100 conv=notrunc 2>/dev/null
if ( cd "$CH" && sha256sum -c <(grep -E 'part' sha256sums.txt) ) >/dev/null 2>&1; then
  fail "cadeia B: tamper detectado" "sha256sum -c passou com parte corrompida!"
else
  ok "cadeia B: 1 byte corrompido é rejeitado (a cadeia pega adulteração)"
fi

# ════════════════════════════════════════════════════════════════════
# 4.C elite-tune --firstboot --dry-run: os DOIS setups, ponta a ponta,
# sem tocar em nada (wfile/run são dry-guarded — a peça prova isso)
# ════════════════════════════════════════════════════════════════════
TUNE="$REPO/elite/airootfs/usr/local/bin/elite-tune"

# o elite-tune exige root (menos --status): local usa user-namespace (unshare -r),
# CI roda como root no container — se nenhum dos dois, pula sem quebrar a cadeia
if [[ $EUID -eq 0 ]]; then
  ROOTWRAP=()
elif unshare -r true 2>/dev/null; then
  ROOTWRAP=(unshare -r)
else
  ROOTWRAP=("SKIP")
fi
firstboot() { # encaminha p/ o wrapper de root escolhido; saída SEM códigos ANSI
  if [[ ${ROOTWRAP[0]} == SKIP ]]; then return 99; fi
  local out rc
  out=$(with_mocks "${ROOTWRAP[@]}" env "$@" 2>&1); rc=$?
  printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g'
  return $rc
}

# Setup A (RTX 5060) herdando ICDs Vulkan AMD/Intel da ISO:
: > "$STATE/installed.txt"; : > "$STATE/pacman.log"; rm -f "$STATE/refuse"
for p in vulkan-radeon lib32-vulkan-radeon vulkan-intel lib32-vulkan-intel \
         mesa steam linux-cachyos-bore nvidia-open nvidia-utils; do
  echo "$p" >> "$STATE/installed.txt"
done
if outA="$(firstboot LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rtx-5060.txt" \
  NVIDIA_SMI='NVIDIA GeForce RTX 5060' \
  bash "$TUNE" --firstboot --dry-run --yes 2>&1)"; then rcA=0; else rcA=$?; fi
assert_eq "$rcA" "0" "cadeia C (Setup A): firstboot dry-run exit 0"
assert_match "$outA" 'NVIDIA blackwell → nvidia-open-dkms' "cadeia C (Setup A): plano do driver certo p/ Blackwell"
assert_match "$outA" 'Auto-limpeza: GPU nvidia → removendo stack do outro vendor' "cadeia C (Setup A): auto-limpeza anunciada"
assert_match "$outA" '\[arquivo\] /etc/modprobe\.d/00-elite-nvidia\.conf' "cadeia C (Setup A): modeset/VRAM planejados (wfile)"
assert_match "$outA" '\$ systemctl enable --now scx-elite\.service' "cadeia C (Setup A): serviços ecoados, não executados (dry)"
assert_match "$outA" 'FIRSTBOOT CONCLUÍDO' "cadeia C (Setup A): chegou ao fim sem abortar"
grep -q -- '-Rns' "$STATE/pacman.log" \
  && fail "cadeia C (Setup A): dry-run NÃO executa remoção" "log trouxe -Rns" \
  || ok "cadeia C (Setup A): dry-run não executou -Rns (só -Qq consultou)"
assert_nofile "/etc/modprobe.d/00-elite-nvidia.conf" "cadeia C (Setup A): nada escrito em /etc (dry é seco)"
assert_nofile "/etc/systemd/system/scx-elite.service" "cadeia C (Setup A): unit não criada fora do dry"

# Setup B (RX 7600) herdando o stack NVIDIA inteiro:
: > "$STATE/installed.txt"; : > "$STATE/pacman.log"
for p in nvidia-open nvidia-utils nvidia-settings lib32-nvidia-utils \
         mesa steam linux-cachyos-bore; do
  echo "$p" >> "$STATE/installed.txt"
done
if outB="$(firstboot LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rx-7600.txt" \
  bash "$TUNE" --firstboot --dry-run --yes 2>&1)"; then rcB=0; else rcB=$?; fi
assert_eq "$rcB" "0" "cadeia C (Setup B): firstboot dry-run exit 0"
assert_match "$outB" 'AMD → mesa/RADV' "cadeia C (Setup B): plano AMD certo (RADV assado = no-op)"
assert_match "$outB" 'Auto-limpeza: GPU amd → removendo stack do outro vendor \(nvidia-open' "cadeia C (Setup B): ~500MB de NVIDIA inertes anunciados p/ sair"
assert_match "$outB" '\[arquivo\] /etc/modprobe\.d/00-elite-amdgpu\.conf' "cadeia C (Setup B): ppfeaturemask planejado (undervolt/OC)"

# GPU desconhecida: firstboot não morre, só avisa
: > "$STATE/installed.txt"; : > "$STATE/pacman.log"
if outU="$(firstboot LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/matrox-unknown.txt" \
  bash "$TUNE" --firstboot --dry-run --yes 2>&1)"; then rcU=0; else rcU=$?; fi
assert_eq "$rcU" "0" "cadeia C (exótica): Matrox → exit 0 (nunca trava o firstboot)"
assert_match "$outU" 'GPU não identificada' "cadeia C (exótica): aviso explícito de GPU desconhecida"

# modo --status (uso diário): certifica sem alterar nada
outS="$(with_mocks env LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rtx-5060.txt" \
  NVIDIA_SMI='NVIDIA GeForce RTX 5060' \
  bash "$TUNE" --status 2>&1)"; rcS=$?
assert_eq "$rcS" "0" "cadeia C (uso): --status exit 0"
assert_match "$outS" 'scx-elite' "cadeia C (uso): --status lista os serviços elite"

phase_end
