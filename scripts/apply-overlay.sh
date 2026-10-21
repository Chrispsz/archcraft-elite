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

# ── [6] Entradas de boot → kernel BORE ─────────────────────────────
#  default/opensource/nomodeset bootam o BORE (v3). A entrada NVIDIA
#  continua no kernel stock (o nvidia-open pré-compilado só existe p/
#  ele — e o initramfs-linux-nvidia.img é gerado pelo preset deles).
say "Patch das entradas de boot → kernel $BORE (default/opensource/nomodeset)"

# ── [6.1] Entrada extra "Copy to RAM" (live rápido em USB lento) ───
#  Padrão upstream: copytoram=n — o live lê TUDO do USB o tempo todo.
#  Em pendrive lento (USB 2.0 / Ventoy) cada leitura aleatória custa
#  caro e os serviços Type=notify podem escalar os timeouts (v1.0.2
#  congelava nisso). Esta entrada copia o airootfs p/ RAM no início
#  (leitura SEQUENCIAL — rápida até em USB 2.0) e o live voa. Requer
#  ~8GB de RAM (2.9GB de ISO + 5G de cow). Nomes stock: os loops [6]
#  abaixo convertem p/ BORE junto com as demais.
say "Entrada de boot extra: Copy to RAM (copytoram=y)"

cat > "$PROFILE/efiboot/loader/entries/05-archiso-linux-ram.conf" <<'RAM'
title   Boot Archcraft Elite (%ARCH%, UEFI, Copy to RAM)
sort-key 05
linux   /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
initrd  /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
options archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=y nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
RAM

SL="$PROFILE/syslinux/archiso_sys-linux.cfg"
if [[ -f "$SL" ]]; then
  cat >> "$SL" <<'RAM'

# Copy to RAM
LABEL archram
TEXT HELP
Boot Archcraft Elite with the airootfs copied to RAM (fast live session).
It allows you to install Archcraft or perform system maintenance.
ENDTEXT
MENU LABEL Boot Archcraft Elite (%ARCH%, BIOS, Copy to RAM)
LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=y nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
RAM
fi

for GF in "$PROFILE/grub/grub.cfg" "$PROFILE/grub/loopback.cfg"; do
  [[ -f "$GF" ]] || continue
  cat >> "$GF" <<'RAM'
menuentry "Boot Archcraft Elite (%ARCH%, ${archiso_platform}, Copy to RAM)" --class archcraft --class arch --class gnu-linux --class gnu --class os --id 'archcraftram' {
    set gfxpayload=keep
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=5G copytoram=y nvme_load=yes lsm=landlock,lockdown,yama,integrity,apparmor,bpf
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}
RAM
done

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
           /etc/skel/.config/labwc/autostart; do
    grep -qF "[\"$p\"]" "$PD" || sed -i "s|^file_permissions=(|file_permissions=(\n  [\"$p\"]=\"0:0:755\"|" "$PD"
  done
  grep -A14 '^file_permissions=' "$PD"
else
  echo "AVISO: file_permissions não encontrado no profiledef — binários Elite ficarão 0644!" >&2
fi

say "Overlay aplicado com sucesso."
echo -e "  ${B}kernel live:${N} $BORE nas entradas default/opensource/nomodeset"
echo -e "  ${B}nvidia live:${N} entrada 'Nvidia' no kernel stock (módulo pré-compilado)"
echo -e "  ${B}build:${N} cd $PROFILE && ./mkarchcraftiso -v -w /mnt/iso-work -o out ."
