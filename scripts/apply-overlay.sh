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
#    · entradas de boot→ menu limpo v1.1: AMD+NVIDIA+rescue, kernel BORE
#                        ÚNICO, copy-to-RAM no default e na NVIDIA
#    · mkinitcpio      → preset archiso do BORE (overlay) p/ o live +
#                        presets órfãos do kernel stock DELETADOS
#                        (arquivos estáticos do profile upstream)
#    · systemd         → remove wants de serviços debloatados
#    · customize       → anexa fragmento elite (E0–E12)
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
say "Aplicando overlay airootfs/ (sysctl, zram, udev, units, scripts, preset BORE)"
rsync -a elite/airootfs/ "$PROFILE/airootfs/"

# ── [4] Pacotes: add + debloat + firmware cirúrgico ────────────────
# Nota: as duas listas aceitam comentário inline ('pkg  # motivo') — o
# loop descasca tudo depois do '#' (v1.0.3; antes só linha 100% limpa).
say "Mesclando elite/packages.add"
while IFS= read -r pkg; do
  pkg="${pkg%%#*}"
  [[ -z "${pkg// /}" ]] && continue
  pkg="${pkg// /}"
  grep -qxF "$pkg" "$PROFILE/packages.x86_64" || echo "$pkg" >> "$PROFILE/packages.x86_64"
done < elite/packages.add

if [[ -f elite/packages.remove ]]; then
  say "Aplicando debloat (elite/packages.remove)"
  n=0
  while IFS= read -r pkg; do
    pkg="${pkg%%#*}"
    [[ -z "${pkg// /}" ]] && continue
    pkg="${pkg// /}"
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
  # SigLevel = Never: repo file:// SEM assinatura — Never elimina a sonda
  # do db.sig (curl 37 “Could not open file …db.sig”, 4× por sincronização)
  if grep -q '^\[archcraft\]' "$PC"; then
    sed -i '0,/^\[archcraft\]/s//[elite-local]\nSigLevel = Never\nServer = file:\/\/\/var\/cache\/elite-local\n\n&/' "$PC"
  else
    sed -i '0,/^\[core\]/s//[elite-local]\nSigLevel = Never\nServer = file:\/\/\/var\/cache\/elite-local\n\n&/' "$PC"
  fi
fi

# [archcraft] é UNSIGNED (packages.archcraft.io não publica .sig): com
# Optional TrustAll o pacman SONDA db.sig e <pkg>.sig em cada download →
# curl 404 (GitHub Pages) em toda sincronização — e na fase de pacotes o
# XferCommand falhando nessa sonda ABORTA a transação (“failed to commit
# transaction”). Never = zero sondas; mesma segurança p/ repo unsigned.
sed -i '/^\[archcraft\]$/{n;s/^SigLevel .*/SigLevel = Never/}' "$PC"
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
# Retries MODERADOS (5×5s, cap 120s): cobrem erro transitório de rede e
# janelas CURTAS de propagação durante o pacstrap. Janelas longas são
# curadas deterministicamente pela sonda+injeção de baseline do preflight
# na retentativa do build — esperar 300s às cegas só queimaria tempo.
# --retry-connrefused: edge CDN recusando conexão é erro retriable;
# --speed-time/-limit: transferência PARADA (hang sem timeout no curl)
# vira erro retriable em vez de travar o build até o timeout do job.
# SEM operadores de shell: o pacman executa o XferCommand via fork/execv
# (não sh -c) — flags apenas, sempre.
if ! grep -q '^XferCommand' "$PC"; then
  sed -i '/^\[options\]/a XferCommand = /usr/bin/curl -L -C - -f -o %o %u --retry 5 --retry-delay 5 --retry-connrefused --retry-all-errors --retry-max-time 120 --speed-time 60 --speed-limit 1024' "$PC"
fi

# Throughput de build: 10 downloads simultâneos no conf de BUILD (o conf
# do sistema instalado é reescrito pelo E3 com os defaults do pacman)
sed -i -E 's|^#?ParallelDownloads = .*|ParallelDownloads = 10|' "$PC"

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

# ── [6] Entradas de boot — menu LIMPO, kernel BORE único, copy-to-RAM ─
#  v1.1 (diretriz do dono — MEGA PROMPT): "limpa aquelas entradas de boot
#  deixando amd e a nvidia moderna apenas, ambos carregando já na ram".
#  Com o nvidia-open-dkms pré-compilado contra o BORE (E11) e o hook kms
#  no initramfs do live, UMA initramfs serve aos dois rigs (early-KMS:
#  o módulo do vendor ausente apenas não binda). Menu final (3 entradas):
#    01/default · AMD/auto · copytoram=y (o padrão que o usuário boota)
#    03/nvidia  · NVIDIA moderna · copytoram=y (nvidia_drm.modeset+fbdev)
#    04/rescue  · nomodeset · copytoram=n (máquina com pouca RAM)
#  Saem do menu: 'OpenSource' (02 — redundante: nouveau não existe no
#  Blackwell e o default já cobre AMD) e a antiga entrada '05 Copy to RAM'
#  (o default AGORA copia p/ RAM). O kernel stock linux sai da ISO
#  inteira (packages.remove) — não há mais entrada nenhuma nele.
say "Menu de boot v1.1: AMD(auto)/NVIDIA/rescue — kernel $BORE único, copy-to-RAM"

# [6.1] efiboot (systemd-boot): 02 sai, 03 vira BORE+NVIDIA, 01/04 patch
rm -f "$PROFILE/efiboot/loader/entries/02-archiso-linux-open-source.conf"
rm -f "$PROFILE/efiboot/loader/entries/05-archiso-linux-ram.conf"
# 03 — reescrita íntegra (conteúdo 100% Elite; sort-key mantém a ordem)
NV03="$PROFILE/efiboot/loader/entries/03-archiso-linux-nvidia.conf"
cat > "$NV03" <<'NVCONF'
title   Boot Archcraft Elite (%ARCH%, UEFI, NVIDIA · Copy to RAM)
sort-key 03
linux    /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux-cachyos-bore
initrd   /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux-cachyos-bore.img
options  archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=y nvidia_drm.modeset=1 nvidia_drm.fbdev=1 nouveau.modeset=0 module_blacklist=nouveau radeon.modeset=1 i915.modeset=1 nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
NVCONF
# 01/04: kernel BORE (todos os .conf restantes — não há mais exceção 03)
for f in "$PROFILE"/efiboot/loader/entries/*.conf; do
  [[ -f "$f" ]] || continue
  sed -i -e "s|\bvmlinuz-linux\b|vmlinuz-$BORE|g" \
         -e "s|\binitramfs-linux\.img\b|$BORE_IMG|g" "$f"
done
# 01 default: copytoram=y + particularidade AMD (ppfeaturemask destrava
# undervolt/OC no LACT; em máquina NVIDIA o param é inerte — amdgpu não
# carrega). Título diz o que a entrada É.
E01="$PROFILE/efiboot/loader/entries/01-archiso-linux.conf"
if [[ -f "$E01" ]]; then
  sed -i -e 's|copytoram=n|copytoram=y|' \
         -e 's|nvme_load=yes|nvme_load=yes amdgpu.ppfeaturemask=0xffffffff|' \
         -e 's|Boot Archcraft (%ARCH%, UEFI, Default)|Boot Archcraft Elite (%ARCH%, UEFI, AMD · Copy to RAM)|' \
         -e 's|Boot Archcraft Elite (%ARCH%, UEFI, BORE kernel)|Boot Archcraft Elite (%ARCH%, UEFI, AMD · Copy to RAM)|' "$E01"
fi

# [6.1b] syslinux (BIOS): um arquivo, blocos por LABEL — archfree sai,
#        archnonfree vira BORE+NVIDIA, arch ganha copytoram+AMD
SL="$PROFILE/syslinux/archiso_sys-linux.cfg"
if [[ -f "$SL" ]]; then
  awk '
    /^LABEL / { lbl = $2; del = (lbl == "archfree"); nv = (lbl == "archnonfree") }
    del { next }                                  # bloco OpenSource fora
    nv && /^LINUX /  { $0 = "LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux-cachyos-bore" }
    nv && /^INITRD / { $0 = "INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux-cachyos-bore.img" }
    nv && /^APPEND / {
      gsub(/copytoram=n/, "copytoram=y")
      gsub(/nvidia nvidia-drm\.modeset=1/, "nvidia_drm.modeset=1 nvidia_drm.fbdev=1")
    }
    lbl == "arch" && /^APPEND / {
      gsub(/copytoram=n/, "copytoram=y")
      gsub(/nvme_load=yes/, "nvme_load=yes amdgpu.ppfeaturemask=0xffffffff")
    }
    { print }
  ' "$SL" > "$SL.tmp" && mv "$SL.tmp" "$SL"
  sed -i -e 's|Boot Archcraft (%ARCH%, BIOS, Nvidia)|Boot Archcraft Elite (%ARCH%, BIOS, NVIDIA · Copy to RAM)|' \
         -e 's|Boot Archcraft Elite (%ARCH%, BIOS, BORE kernel)|Boot Archcraft Elite (%ARCH%, BIOS, AMD · Copy to RAM)|' \
         -e 's|Boot Archcraft (%ARCH%, BIOS, Default)|Boot Archcraft Elite (%ARCH%, BIOS, AMD · Copy to RAM)|' "$SL"
fi

# [6.1c] grub (BIOS/loopback): bloco archcraftos sai; archcraftpn vira
#        BORE+NVIDIA; archcraft ganha copytoram+AMD; archcraftnm fica rescue
for GF in "$PROFILE/grub/grub.cfg" "$PROFILE/grub/loopback.cfg"; do
  [[ -f "$GF" ]] || continue
  awk -v img="$BORE_IMG" '
    /menuentry .*--id / {
      cur = ""
      if ($0 ~ /--id .archcraftos./)    cur = "del"
      if ($0 ~ /--id .archcraftpn./)    cur = "nv"
      if ($0 ~ /--id .archcraft[^p]/)   cur = "def"
      if ($0 ~ /--id .archcraftnm./)    cur = "nm"
    }
    cur == "del" && /^}/ { cur = ""; next }
    cur == "del" { next }
    cur == "nv" && /^    linux / {
      gsub(/vmlinuz-linux/, "vmlinuz-linux-cachyos-bore")
      gsub(/copytoram=n/, "copytoram=y")
      gsub(/nvidia nvidia-drm\.modeset=1/, "nvidia_drm.modeset=1 nvidia_drm.fbdev=1")
    }
    cur == "nv" && /^    initrd / { gsub(/initramfs-linux-nvidia\.img/, img) }
    cur == "def" && /^    linux / {
      gsub(/vmlinuz-linux/, "vmlinuz-linux-cachyos-bore")
      gsub(/copytoram=n/, "copytoram=y")
      gsub(/nvme_load=yes/, "nvme_load=yes amdgpu.ppfeaturemask=0xffffffff")
    }
    cur == "def" && /^    initrd / { gsub(/initramfs-linux\.img/, img) }
    cur == "nm" && /^    linux / { gsub(/vmlinuz-linux/, "vmlinuz-linux-cachyos-bore") }
    cur == "nm" && /^    initrd / { gsub(/initramfs-linux\.img/, img) }
    { print }
  ' "$GF" > "$GF.tmp" && mv "$GF.tmp" "$GF"
  sed -i -e 's|Boot Archcraft (%ARCH%, ${archiso_platform}, Nvidia)|Boot Archcraft Elite (%ARCH%, ${archiso_platform}, NVIDIA · Copy to RAM)|' \
         -e 's|Boot Archcraft (%ARCH%, ${archiso_platform}, Default)|Boot Archcraft Elite (%ARCH%, ${archiso_platform}, AMD · Copy to RAM)|' \
         -e 's|Boot Archcraft Elite (%ARCH%, ${archiso_platform}, BORE kernel)|Boot Archcraft Elite (%ARCH%, ${archiso_platform}, AMD · Copy to RAM)|' "$GF"
  # prova: o bloco opensource foi consumido (padrão upstream mudou?)
  grep -q -- "--id 'archcraftos'" "$GF" \
    && say "AVISO: bloco archcraftos NÃO removido (padrão upstream mudou?) — conferir"
done

# guarda de sanidade: NENHUMA entrada pode ter sobrado apontando pro kernel
# stock (ele não existe mais na ISO — boot de entrada órfã = kernel panic)
for f in "$PROFILE/grub/grub.cfg" "$PROFILE/grub/loopback.cfg" \
         "$PROFILE/syslinux/archiso_sys-linux.cfg" \
         "$PROFILE"/efiboot/loader/entries/*.conf; do
  [[ -f "$f" ]] || continue
  if grep -qE 'vmlinuz-linux([^-]|$)' "$f"; then
    say "AVISO: $(basename "$f") ainda referencia o kernel stock — não existirá na ISO!"
  fi
done

# ── [6.3] Presets órfãos do kernel stock (v1.1) ─────────────────────
#  O profile upstream entrega /etc/mkinitcpio.d/{linux,linux-nvidia}
#  .preset como ARQUIVOS ESTÁTICOS do airootfs (não vêm de pacote): o
#  mkarchcraftiso copia o airootfs do profile ANTES do pacstrap, e o hook
#  90-mkinitcpio-install do fim da transação itera TODOS os presets de
#  /etc/mkinitcpio.d. Com o kernel stock fora da lista de pacotes, eles
#  viram órfãos com efeito duplo:
#    · no BUILD: o hook morre em "Invalid option -k -- '/boot/vmlinuz-
#      linux' must be readable" (erro tolerado pelo pacman — build segue
#      com ruído no log; visto na build #48);
#    · no PRODUTO: o arquivo entra no squashfs → unpackfs o copia pro
#      sistema INSTALADO → contrato "kernel único BORE" quebrado (foi
#      exatamente o que o gate verify-install derrubou na build #48:
#      '✖ preset stock PRESENTE').
#  O archiso-nvidia.conf do conf.d perde o único consumidor (o preset
#  deletado) — sai junto. O archiso.conf FICA: é a config da 1ª geração
#  do initramfs live do BORE (o E11 a recria e apaga o conf.d inteiro
#  no final do customize).
say "Kernel único: deletando presets órfãos do kernel stock do profile"
for orphan in linux.preset linux-nvidia.preset; do
  if [[ -f "$PROFILE/airootfs/etc/mkinitcpio.d/$orphan" ]]; then
    rm -f "$PROFILE/airootfs/etc/mkinitcpio.d/$orphan"
    say "  preset órfão removido: airootfs/etc/mkinitcpio.d/$orphan"
  fi
done
if [[ -f "$PROFILE/airootfs/etc/mkinitcpio.conf.d/archiso-nvidia.conf" ]]; then
  rm -f "$PROFILE/airootfs/etc/mkinitcpio.conf.d/archiso-nvidia.conf"
  say "  conf órfão removido: airootfs/etc/mkinitcpio.conf.d/archiso-nvidia.conf"
fi
# ── [6.2] Timeouts de boot à prova de USB lento/emulador (v1.0.4) ──
#  O cachyos-settings impõe DefaultTimeoutStartSec=15s via /usr/lib/
#  systemd/system.conf.d/00-timeout.conf. Em boot a frio por USB lento
#  (ou TCG), serviços Type=notify não ficam prontos em 15s → timeout →
#  restart → loop → splash congela (causa-raiz do v1.0.2, diag-boot3).
#  O drop-in /etc (00-elite-timeout.conf, 90s) cobre o sistema
#  INSTALADO — mas no LIVE o PID-1, que nasceu no initramfs e atravessa
#  o switch_root, NÃO reavalia drop-ins de /etc: os jobs seguem com o
#  15s do /usr/lib (comprovado no serial: 'Resource Manager (4s / 15s)'
#  nas builds v1.0.3 E v1.0.4). A linha de comando do kernel é a única
#  precedência que sempre vence no live. A/B local (QEMU idêntico ao
#  gate): SEM o param = nsresourced em restart-loop eterno + tmpfiles
#  travado 28min + boot nunca completa (run #42); COM o param = 0
#  falhas, tmpfiles ok, boot completo na fase final em ~5min.
#  Idempotente (guard grep) e kernel-agnóstico (vale p/ BORE, stock e
#  nvidia — robustez de boot, não recurso de kernel).
ELITE_TMO="systemd.default_timeout_start_sec=90 systemd.default_timeout_stop_sec=90"
for f in "$PROFILE"/efiboot/loader/entries/*.conf; do
  [[ -f "$f" ]] || continue
  grep -q 'systemd.default_timeout_start_sec=' "$f" || \
    sed -i "/^options /s/\$/ $ELITE_TMO/" "$f"
done
if [[ -f "$SL" ]] && ! grep -q 'systemd.default_timeout_start_sec=' "$SL"; then
  sed -i "/^APPEND /s/\$/ $ELITE_TMO/" "$SL"
fi
for GF in "$PROFILE/grub/grub.cfg" "$PROFILE/grub/loopback.cfg"; do
  [[ -f "$GF" ]] || continue
  grep -q 'systemd.default_timeout_start_sec=' "$GF" || \
    sed -i "/^[[:space:]]*linux \//s/\$/ $ELITE_TMO/" "$GF"
done
say "Timeouts de boot 90s no cmdline de TODAS as entradas (fix live freeze)"

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

# ── [8.5] customize_airootfs.sh: guarda do bloco sway ──────────────
#  O upstream do customize trata as 3 edições como presentes (openbox/
#  bspwm/sway). O debloat Elite remove o archcraft-skeleton-wayland →
#  /etc/skel/.config/sway NÃO existe no airootfs → o 'sed -i' do upstream
#  morre com 'can't read' (set -e aborta o script inteiro — foi exata-
#  mente o que derrubou o run #17 no ÚLTIMO passo do build) e o 'cat >>'
#  criaria um arquivo órfão no skel. A guarda [[ -f ]] preserva o com-
#  portamento upstream quando a edição existe e vira no-op quando não.
say "Patch: guarda do bloco sway no customize_airootfs.sh (edição wayland debloatada)"
CS="$PROFILE/airootfs/root/customize_airootfs.sh"
# delimitador @ (o replacement contém '|| true' — '|' colidiria);
# \. casa o ponto literal; \$ protege o anchor do bash em aspas duplas
sed -i \
  -e "s@^sed -i -e '/## Welcome-App-Run-Once/Q' /etc/skel/\.config/sway/scripts/startup\$@[[ -f /etc/skel/.config/sway/scripts/startup ]] \&\& sed -i -e '/## Welcome-App-Run-Once/Q' /etc/skel/.config/sway/scripts/startup || true@" \
  -e 's@^cat >> "/etc/skel/\.config/sway/scripts/startup" <<- EOL$@[[ -f /etc/skel/.config/sway/scripts/startup ]] \&\& cat >> "/etc/skel/.config/sway/scripts/startup" <<- EOL || true@' \
  "$CS"
if ! grep -q '\[\[ -f /etc/skel/.config/sway/scripts/startup \]\]' "$CS"; then
  say "AVISO: bloco sway não encontrado no customize (upstream mudou o padrão?) — conferir manualmente"
fi

# ── [8.6] customize: guards p/ sessões extintas + pacotes da curadoria ─
#  v1.0.3 sessão ÚNICA labwc: openbox/bspwm/archcraft-scripts/
#  archcraft-skeleton/archcraft-help saíram — e o customize upstream
#  toca TODOS eles como se existissem (set -e derruba o build exata-
#  mente no último passo: foi o que matou o run da 2256d0a no
#  'sed: can't read /etc/skel/.config/openbox/autostart').
#  Mesma técnica do [8.5]: [[ -f/-d ]] preserva upstream se o alvo
#  voltar a existir; no-op quando não existe.
say "Patch: guards openbox/bspwm/scripts/screenlayout no customize (curadoria v1.0.3)"
sed -i \
  -e "s@^sed -i -e '/## Welcome-App-Run-Once/Q' /etc/skel/\.config/openbox/autostart\$@[[ -f /etc/skel/.config/openbox/autostart ]] \&\& sed -i -e '/## Welcome-App-Run-Once/Q' /etc/skel/.config/openbox/autostart || true@" \
  -e 's@^cat >> "/etc/skel/\.config/openbox/autostart" <<- EOL$@[[ -f /etc/skel/.config/openbox/autostart ]] \&\& cat >> "/etc/skel/.config/openbox/autostart" <<- EOL || true@' \
  -e "s@^sed -i -e '/## Welcome-App-Run-Once/Q' /etc/skel/\.config/bspwm/bspwmrc\$@[[ -f /etc/skel/.config/bspwm/bspwmrc ]] \&\& sed -i -e '/## Welcome-App-Run-Once/Q' /etc/skel/.config/bspwm/bspwmrc || true@" \
  -e 's@^cat >> "/etc/skel/\.config/bspwm/bspwmrc" <<- EOL$@[[ -f /etc/skel/.config/bspwm/bspwmrc ]] \&\& cat >> "/etc/skel/.config/bspwm/bspwmrc" <<- EOL || true@' \
  -e "s@^ln -s /usr/share/archcraft/scripts/\* /usr/local/bin/\$@[[ -d /usr/share/archcraft/scripts ]] \&\& ln -s /usr/share/archcraft/scripts/* /usr/local/bin/ || true@" \
  -e "s@^chmod +x /etc/skel/\.screenlayout/my-layout\.sh\$@[[ -f /etc/skel/.screenlayout/my-layout.sh ]] \&\& chmod +x /etc/skel/.screenlayout/my-layout.sh || true@" \
  "$CS"
# prova de que as 6 guards entraram (upstream pode mudar o texto → avisa)
for alvo in \
  '\[\[ -f /etc/skel/\.config/openbox/autostart \]\]' \
  '\[\[ -f /etc/skel/\.config/bspwm/bspwmrc \]\]' \
  '\[\[ -d /usr/share/archcraft/scripts \]\]' \
  '\[\[ -f /etc/skel/\.screenlayout/my-layout\.sh \]\]'; do
  grep -q "$alvo" "$CS" || say "AVISO: guard $alvo não aplicada (upstream mudou o padrão?) — conferir manualmente"
done

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

# ── [9b] Permissões exec dos binários Elite (fix diag-boot2: 203/EXEC)
#  O mkarchcraftiso copia o airootfs custom com `cp --no-preserve=mode`
#  (mkarchcraftiso:318) → TODO arquivo custom vira 0644 no squashfs. Sem
#  entrada em file_permissions, /usr/local/bin/{elite-tune,elite-status,
#  fg-booster} ficam não-executáveis no live: elite-firstboot.service e
#  fg-booster.service morrem com 203/EXEC (comprovado no boot QEMU do
#  diag-boot2, tests A/B, "Unable to locate executable: Permission denied").
#  O upstream só registra os PRÓPRIOS scripts (choose-mirror, xflock4).
#  v1.0.3: + craft-* (keybinds do rc.xml labwc) + autostart do labwc
#  (o skel→home do mkarchcraftiso preserva o modo → liveuser herda 0755).
say "Registrando 0755 dos binários Elite no file_permissions do profiledef"
PD="$PROFILE/profiledef.sh"
if grep -q '^file_permissions=(' "$PD"; then
  for p in /usr/local/bin/elite-tune /usr/local/bin/elite-status /usr/local/bin/fg-booster \
           /usr/local/bin/craft-hello /usr/local/bin/craft-update /usr/local/bin/craft-clean \
           /usr/local/bin/craft-rollback /usr/local/bin/craft-lock /usr/local/bin/craft-logout \
           /usr/local/bin/craft-shot /usr/local/bin/craft-bat \
           /usr/local/bin/craft-drawer /usr/local/bin/craft-power /usr/local/bin/craft-pin \
           /etc/skel/.config/labwc/autostart; do
    grep -qF "[\"$p\"]" "$PD" || sed -i "s|^file_permissions=(|file_permissions=(\n  [\"$p\"]=\"0:0:755\"|" "$PD"
  done
  grep -A15 '^file_permissions=' "$PD"
else
  echo "AVISO: file_permissions não encontrado no profiledef — binários Elite ficarão 0644!" >&2
fi

say "Overlay aplicado com sucesso."
echo -e "  ${B}kernel live:${N} $BORE em TODAS as entradas (AMD default · NVIDIA dkms · rescue)"
echo -e "  ${B}copy-to-RAM:${N} default e NVIDIA bootam com o live inteiro na RAM"
echo -e "  ${B}build:${N} cd $PROFILE && ./mkarchcraftiso -v -w /mnt/iso-work -o out ."
