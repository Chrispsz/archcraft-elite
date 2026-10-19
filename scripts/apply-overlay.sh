#!/usr/bin/env bash
# =====================================================================
#  apply-overlay.sh v2 — Arquitetura "delta" da Elite Edition
#
#  Não é um fork: clona o profile OFICIAL do Archcraft (Openbox/BSPWM)
#  e aplica a camada Elite por cima. A cada build, sincroniza com o
#  upstream (dotfiles, temas, calamares, nvidia live) — zero manutenção
#  de fork.
#
#  O que esta versão faz (além do overlay de arquivos):
#    · packages.add    → mescla pacotes Elite (dedupe)
#    · packages.remove → debloat cirúrgico (comenta no packages.x86_64)
#    · firmware        → meta linux-firmware → subpacotes (sem -nvidia/
#                        -other/-mellanox/-nfp/-qcom/-qlogic/-liquidio)
#    · pacman.conf     → repos CachyOS (cdn77+us) ANTES de [core]
#    · entradas de boot→ kernel BORE em default/opensource/nomodeset
#                        (a entrada NVIDIA fica no kernel stock: módulo
#                        pré-compilado só existe p/ ele)
#    · mkinitcpio      → preset archiso do BORE (overlay) p/ o live
#    · systemd         → remove wants de serviços debloatados
#    · customize       → anexa fragmento elite (E0–E7)
#    · profiledef      → ISO rebatizada archcraft-elite-<data>
#
#  Uso (CI ou local; precisa: git, rsync, curl):
#    bash scripts/apply-overlay.sh
#  Saída: elite-build/ pronto para o mkarchcraftiso.
# =====================================================================
set -euo pipefail
G='\033[1;32m'; N='\033[0m'; B='\033[1m'
say() { echo -e "${G}==>${N} $1"; }
cd "$(dirname "$0")/.."

SRC="https://github.com/archcraft-os/archcraft.git"
OUT="elite-build"
BORE="linux-cachyos-bore"
BORE_IMG="initramfs-linux-cachyos-bore.img"

command -v git   >/dev/null || { echo "ERRO: git necessário";   exit 1; }
command -v rsync >/dev/null || { echo "ERRO: rsync necessário"; exit 1; }
command -v curl  >/dev/null || { echo "ERRO: curl necessário";  exit 1; }

# ── [1] Upstream fresco ─────────────────────────────────────────────
say "Clonando Archcraft upstream → $OUT/"
rm -rf "$OUT"
git clone --depth=1 "$SRC" "$OUT"

# ── [2] Raiz do profile (defensivo contra mudança de layout) ───────
PROFILE=$(dirname "$(find "$OUT" -maxdepth 3 -name profiledef.sh -print -quit)")
[[ -f "$PROFILE/packages.x86_64" && -f "$PROFILE/pacman.conf" ]] \
  || { echo "ERRO: profile Archcraft não encontrado"; exit 1; }
say "Profile detectado: $PROFILE"

# ── [3] Overlay airootfs (arquivos Elite vencem; nada deles é apagado)
say "Aplicando overlay airootfs/ (sysctl, zram, udev, units, scripts, wallpapers, preset BORE)"
rsync -a elite/airootfs/ "$PROFILE/airootfs/"

# ── [4] Pacotes: add + debloat + firmware cirúrgico ────────────────
say "Mesclando elite/packages.add"
while IFS= read -r pkg; do
  [[ -z "${pkg// /}" || "${pkg:0:1}" == '#' ]] && continue
  grep -qxF "$pkg" "$PROFILE/packages.x86_64" || echo "$pkg" >> "$PROFILE/packages.x86_64"
done < elite/packages.add

if [[ -f elite/packages.remove ]]; then
  say "Aplicando debloat (elite/packages.remove)"
  n=0
  while IFS= read -r pkg; do
    [[ -z "${pkg// /}" || "${pkg:0:1}" == '#' ]] && continue
    if grep -qxF "$pkg" "$PROFILE/packages.x86_64"; then
      sed -i "s|^${pkg}$|#${pkg} # ELITE-REMOVED|" "$PROFILE/packages.x86_64"
      n=$((n+1))
    else
      echo "  (aviso: '$pkg' não está na lista upstream — ignorado)"
    fi
  done < elite/packages.remove
  say "Debloat: $n pacote(s) comentados"
fi

# Firmware: troca o meta linux-firmware pelos subpacotes que importam
# p/ hardware consumidor (GPU AMD/Intel/Radeon, WiFi broadcom/realtek/
# atheros/mediatek/marvell/ti, áudio cirrus/intel). Corta ~700MB-1GB
# brutos: -nvidia (só serve ao nouveau; driver proprietário traz o fw
# dele), -other (SoCs/enterprise), -mellanox, -nfp, -qcom, -qlogic,
# -liquidio. Restaurar tudo: pacman -S linux-firmware
if grep -qxF 'linux-firmware' "$PROFILE/packages.x86_64"; then
  say "Firmware cirúrgico: meta → subpacotes (sem nvidia/other/enterprise)"
  sed -i 's|^linux-firmware$|#linux-firmware # ELITE-REMOVED: subpacotes abaixo (restore: pacman -S linux-firmware)|' "$PROFILE/packages.x86_64"
  cat >> "$PROFILE/packages.x86_64" <<'EOF'
## ELITE: firmware cirúrgico — hardware consumidor coberto
linux-firmware-amd
linux-firmware-amdgpu
linux-firmware-atheros
linux-firmware-broadcom
linux-firmware-cirrus
linux-firmware-intel
linux-firmware-mediatek
linux-firmware-radeon
linux-firmware-realtek
linux-firmware-ti
linux-firmware-whence
EOF
fi

# ── [5] Repos no pacman.conf de BUILD ──────────────────────────────
say "Mesclando repos no pacman.conf (build)"
PC="$PROFILE/pacman.conf"
sed -i '/^DownloadUser/d' "$PC"

# [elite-local]: repo file:// construído pelo CI (.ci/build.sh) — resolve as
# dependências que o upstream Archcraft quebrou (python-pywal saiu dos repos
# oficiais; qt5-virtualkeyboard é vestígio Qt5 do archcraft-sddm-theme).
# O caminho /var/cache/elite-local existe no host E no chroot do pacstrap
# (via overlay) — e é removido da ISO final pelo customize [E8].
if ! grep -q '^\[elite-local\]' "$PC"; then
  # insere ANTES do primeiro repo ([archcraft]; fallback: antes de [core])
  if grep -q '^\[archcraft\]' "$PC"; then
    sed -i '0,/^\[archcraft\]/s//[elite-local]\nSigLevel = Optional TrustAll\nServer = file:\/\/\/var\/cache\/elite-local\n\n&/' "$PC"
  else
    sed -i '0,/^\[core\]/s//[elite-local]\nSigLevel = Optional TrustAll\nServer = file:\/\/\/var\/cache\/elite-local\n\n&/' "$PC"
  fi
fi
if ! grep -q '^\[cachyos-v3\]' "$PC"; then
  TMP=$(mktemp)
  awk -v block="$(cat elite/pacman-repos.build.add)" '
    /^\[core\]/ && !done { print block; print ""; done = 1 }
    { print }
    END { if (!done) { print ""; print block } }
  ' "$PC" > "$TMP"
  cat "$TMP" > "$PC"; rm -f "$TMP"
fi
# multilib (lib32-gamemode, lib32-mangohud, lib32-vulkan, steam no --apps)
grep -q '^\[multilib\]' "$PC" || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> "$PC"

# Arquitetura: os pacotes do cachyos-v3 são arch "x86_64_v3" — sem isto
# o pacstrap rejeita com "does not have a valid architecture" (o "auto"
# resolve só x86_64). Lista = aceita os dois (pacman 6.1+).
if ! grep -qE '^Architecture = .*\bx86_64_v3\b' "$PC"; then
  if grep -qE '^Architecture = ' "$PC"; then
    sed -i -E 's|^Architecture = .*$|Architecture = x86_64 x86_64_v3|' "$PC"
  else
    sed -i '/^\[options\]/a Architecture = x86_64 x86_64_v3' "$PC"
  fi
fi

# Downloads resilientes: mirrors rolling (CachyOS) têm janelas em que o
# db anuncia versão que o arquivo ainda não propagou (404 transitório).
# curl com --retry-all-errors espera o mirror sincronizar.
if ! grep -q '^XferCommand' "$PC"; then
  sed -i '/^\[options\]/a XferCommand = /usr/bin/curl -L -C - -f -o %o %u --retry 4 --retry-delay 5 --retry-all-errors' "$PC"
fi

# ── [5.1] (CI/root) mirrorlist do repo [archcraft] p/ o ambiente de build
#          (o conf do profile referencia via Include; o pacstrap resolve)
if [[ $EUID -eq 0 && ! -f /etc/pacman.d/archcraft-mirrorlist ]]; then
  printf 'Server = https://packages.archcraft.io/$arch\n' > /etc/pacman.d/archcraft-mirrorlist
  say "Escrito /etc/pacman.d/archcraft-mirrorlist (ambiente de build)"
fi

# ── [5.2] (CI/root) expandir GRUPOS em pacotes explícitos ──────────
#  pacstrap não-interativo ABORTA em prompt de seleção de grupo (stdin
#  EOF ≠ default). O build oficial do Archcraft é interativo (TTY) —
#  aqui expandimos cada grupo nos mesmos membros que o default=all
#  escolheria, consultando os dbs reais (mesma seleção, zero prompts).
if [[ $EUID -eq 0 && -x /usr/bin/pacman ]]; then
  say "Sincronizando dbs do profile p/ expandir grupos (melhor esforço)"
  pacman -Sy --noconfirm --config "$PC" >/dev/null 2>&1 || true
  for g in xorg archcraft-cursors archcraft-icons archcraft-themes archcraft-wallpapers; do
    grep -qxF "$g" "$PROFILE/packages.x86_64" || continue
    members=$(pacman --config "$PC" -Sgq "$g" 2>/dev/null | sort -u) || members=""
    if [[ -n "$members" ]]; then
      say "Grupo '$g' → $(wc -l <<< "$members") pacote(s) explícito(s)"
      sed -i "s|^${g}\$|#${g} # ELITE-EXPANDED: grupo virou lista explícita (prompt quebra o pacstrap CI)|" "$PROFILE/packages.x86_64"
      printf '%s\n' "$members" >> "$PROFILE/packages.x86_64"
    else
      echo "  (aviso: não foi possível expandir '$g' — pacman -Sgq falhou; build CI vai travar no prompt deste grupo)"
    fi
  done
fi

# ── [6] Entradas de boot → kernel BORE ─────────────────────────────
#  default/opensource/nomodeset bootam o BORE (v3). A entrada NVIDIA
#  continua no kernel stock (o nvidia-open pré-compilado só existe p/
#  ele — e o initramfs-linux-nvidia.img é gerado pelo preset deles).
say "Patch das entradas de boot → kernel $BORE (default/opensource/nomodeset)"

# efiboot: arquivos por entrada — pular a 03 (nvidia)
for f in "$PROFILE"/efiboot/loader/entries/*.conf; do
  [[ -f "$f" ]] || continue
  case "$(basename "$f")" in
    03-*) continue ;; # NVIDIA: fica no kernel stock
  esac
  sed -i -e "s|\bvmlinuz-linux\b|vmlinuz-$BORE|g" \
         -e "s|\binitramfs-linux\.img\b|$BORE_IMG|g" "$f"
done
sed -i 's|Boot Archcraft (%ARCH%, UEFI, Default)|Boot Archcraft Elite (%ARCH%, UEFI, BORE kernel)|' \
  "$PROFILE/efiboot/loader/entries/01-archiso-linux.conf" 2>/dev/null || true

# syslinux (BIOS): um arquivo, 4 entradas — pular o bloco archnonfree
SL="$PROFILE/syslinux/archiso_sys-linux.cfg"
if [[ -f "$SL" ]]; then
  awk -v bore="vmlinuz-$BORE" -v img="$BORE_IMG" '
    /^LABEL / { innv = ($2 == "archnonfree") }
    !innv { gsub(/vmlinuz-linux/, bore); gsub(/initramfs-linux\.img/, img) }
    { print }
  ' "$SL" > "$SL.tmp" && mv "$SL.tmp" "$SL"
  sed -i 's|Boot Archcraft (%ARCH%, BIOS, Default)|Boot Archcraft Elite (%ARCH%, BIOS, BORE kernel)|' "$SL"
fi

# grub (BIOS/loopback): pular o menuentry --id archcraftpn (nvidia)
for GF in "$PROFILE/grub/grub.cfg" "$PROFILE/grub/loopback.cfg"; do
  [[ -f "$GF" ]] || continue
  awk -v bore="vmlinuz-$BORE" -v img="$BORE_IMG" '
    /menuentry .*--id .archcraftpn./ { skip = 1 }
    skip && /^}/ { print; skip = 0; next }
    !skip { gsub(/vmlinuz-linux/, bore); gsub(/initramfs-linux\.img/, img) }
    { print }
  ' "$GF" > "$GF.tmp" && mv "$GF.tmp" "$GF"
  sed -i '0,/Boot Archcraft (%ARCH%, ${archiso_platform}, Default)/s//Boot Archcraft Elite (%ARCH%, ${archiso_platform}, BORE kernel)/' "$GF"
done

# ── [7] systemd: remove wants de serviços debloatados ─────────────
say "Removendo wants de serviços debloatados (cloud-init, vbox, vmware, hyperv, modemmanager, cups, pcscd)"
SD="$PROFILE/airootfs/etc/systemd/system"
find "$SD" -type l \( -name '*cloud-init*' -o -name '*ModemManager*' \
  -o -name 'vbox*' -o -name 'vmtools*' -o -name 'vmware*' -o -name 'hv_*' \
  -o -name 'cups*' -o -name 'pcscd*' \) -delete 2>/dev/null || true
rm -rf "$SD/cloud-init.target.wants"

# ── [8] mkarchcraftiso NÃO-INTERATIVO ──────────────────────────────
#  O fork do Archcraft invoca 'pacstrap -i' (mudança CUSTOM deles: o adi
#  responde os prompts no TTY da máquina dele). Em CI, stdin EOF no
#  'Proceed with installation?' do pacstrap aborta o build. Sem o -i o
#  pacstrap passa --noconfirm ao pacman: todos os prompts (grupos,
#  providers, Y/n) resolvem pelo default — mesmo comportamento do
#  build oficial (default=all/default=1), sem interação.
say "Patch: pacstrap não-interativo no mkarchcraftiso (remove -i)"
sed -i 's|pacstrap -C "${work_dir}/${buildmode}.pacman.conf" -i -c -G -M|pacstrap -C "${work_dir}/${buildmode}.pacman.conf" -c -G -M|g' "$PROFILE/mkarchcraftiso"

# ── [9] Fragmento elite no customize_airootfs.sh ───────────────────
say "Anexando fragmento elite ao customize_airootfs.sh (E0–E8)"
CF="$PROFILE/airootfs/root/customize_airootfs.sh"
mkdir -p "$(dirname "$CF")"
[[ -f "$CF" ]] || printf '#!/usr/bin/env bash\nset -e -u\n' > "$CF"
cat elite/fragments/elite-customize.sh >> "$CF"
chmod +x "$CF"

# ── [9] Identidade da ISO ─────────────────────────────────────────
say "Rebatizando a ISO (archcraft-elite-<data>)"
sed -i -e 's|iso_name="archcraft"|iso_name="archcraft-elite"|' \
       -e 's|iso_application="Archcraft Live/Installation/Rescue CD"|iso_application="Archcraft Elite Edition - Gaming Tuned Live/Installer"|' \
       "$PROFILE/profiledef.sh"

say "Overlay aplicado com sucesso."
echo -e "  ${B}kernel live:${N} $BORE nas entradas default/opensource/nomodeset"
echo -e "  ${B}nvidia live:${N} entrada 'Nvidia' no kernel stock (módulo pré-compilado)"
echo -e "  ${B}build:${N} cd $PROFILE && ./mkarchcraftiso -v -w /mnt/iso-work -o out ."
