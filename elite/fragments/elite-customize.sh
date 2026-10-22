#!/usr/bin/env bash
# (shebang pro shellcheck; ao ser anexado ao customize_airootfs.sh isto vira
#  apenas um comentário no meio do arquivo — sem efeito em runtime)
# shellcheck shell=bash disable=SC2016
#
# ════════════════════════════════════════════════════════════════════
# ── ELITE v2 ─────────────────────────────────────────────────────────
#  Roda DENTRO do airootfs no fim do customize_airootfs.sh do Archcraft
#  (fase de BUILD). Prepara o CachyOS p/ a sessão live E p/ o sistema
#  instalado (o Calamares/unpackfs copia este root inteiro p/ o disco),
#  e faz a cirurgia no Calamares p/ o kernel BORE também bootar no
#  sistema instalado (unpackfs + initcpio@elite).
# ════════════════════════════════════════════════════════════════════

ELITE_KEY="F3B607488DB35A47"
ELITE_MIRROR="https://us.cachyos.org"
ELITE_MIRROR2="https://cdn77.cachyos.org"
ELITE_KEYRING_PINNED="cachyos-keyring-20240331-1-any.pkg.tar.zst"
ELITE_V3ML_PINNED="cachyos-v3-mirrorlist-27-1-any.pkg.tar.zst"

## [E0] DNS no chroot (o fallback de rede do E2 usa curl; o arch-chroot
##      normalmente copia o resolv.conf, mas o symlink stub do
##      systemd-resolved pode estar morto)
if [[ ! -e /etc/resolv.conf ]]; then
    rm -f /etc/resolv.conf
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
fi

## [E1] chave CachyOS no keyring do chroot (fix #20: o chroot vem SEM gnupg —
##      pacstrap -G não copia o do host e nada o inicializa; sem isto,
##      recv/lsign morrem com "insufficient permissions" e o E2 entra em
##      chicken-and-egg: instalar o keyring precisa do keyring p/ verificar
##      a própria assinatura). Init ANTES de qualquer op de chave.
pacman-key --init >/dev/null 2>&1 || true
if ! pacman-key --list-keys "$ELITE_KEY" >/dev/null 2>&1; then
    pacman-key --recv-keys "$ELITE_KEY" --keyserver keyserver.ubuntu.com \
        || pacman-key --recv-keys "$ELITE_KEY" || true
    pacman-key --lsign-key "$ELITE_KEY" || true
fi

## [E2] keyring + mirrorlist v3 oficiais — OFFLINE-FIRST. O .ci/build.sh
##      baixa os dois (listing us → pin; download cdn77 → us) p/ o
##      [elite-local], que é o PRIMEIRO repo do conf de build: o pacman -S
##      resolve por file:// e o customize NÃO toca a rede (download aqui
##      era a última fonte potencial de curl errors do chroot — skew de
##      mirror não alcança mais esta fase). Camadas: [elite-local] →
##      pacman -U (mirror) → mirrorlist manual (a chave já caiu via E1;
##      o keyring empacotado é a forma canônica, atualizável pelo pacman).
elite_latest() {
    curl -fsSL --max-time 30 "${ELITE_MIRROR}/repo/x86_64/cachyos/" 2>/dev/null \
        | grep -oE "$1-[0-9][^\"]*\.pkg\.tar\.zst" | sort -Vu | tail -1 || true
}
if ! pacman -S --noconfirm cachyos-keyring cachyos-v3-mirrorlist; then
    ELITE_KEYRING_PKG="$(elite_latest cachyos-keyring)"
    [[ -n "$ELITE_KEYRING_PKG" ]] || ELITE_KEYRING_PKG="$ELITE_KEYRING_PINNED"
    ELITE_V3ML_PKG="$(elite_latest cachyos-v3-mirrorlist)"
    [[ -n "$ELITE_V3ML_PKG" ]] || ELITE_V3ML_PKG="$ELITE_V3ML_PINNED"
    if ! pacman -U --noconfirm \
            "${ELITE_MIRROR}/repo/x86_64/cachyos/${ELITE_KEYRING_PKG}" \
            "${ELITE_MIRROR}/repo/x86_64/cachyos/${ELITE_V3ML_PKG}"; then
        ## Fallback: escreve o mirrorlist na mão (a chave já caiu via E1)
        printf 'Server = %s/repo/x86_64_v3/$repo\nServer = %s/repo/x86_64_v3/$repo\n' \
            "$ELITE_MIRROR" "$ELITE_MIRROR2" > /etc/pacman.d/cachyos-v3-mirrorlist
    fi
fi

## [E3] pacman.conf do SISTEMA: reescrito canônico e limpo (o customize do
##      Archcraft duplica [core]/[extra] no fim; aqui fica sem duplicatas).
##      Ordem: archcraft > cachyos(v2) > cachyos-v3 trio > core/extra/multilib
ELITE_PC="/etc/pacman.conf"
# [options] INTEIRO (header + diretivas) até a próxima seção. O awk
# antigo ('/^\[/{exit}') capturava os COMENTÁRIOS acima de [options] —
# o conf saía SEM seção nenhuma ("line 9: All directives must belong
# to a section" — matou o run #21; no #20 o mesmo bug se manifestou
# como "$arch sem Architecture"). Latente desde sempre: E3 só rodou
# de verdade no #20 (primeiro build a chegar ao customize).
awk '/^\[options\]/{opt=1; print; next}
     opt && /^\[/{exit}
     opt{print}' "$ELITE_PC" > /tmp/elite-pc-options
# fix #20: garante Architecture p/ o mirror $arch do [archcraft]
# (pacman fatal: "contains the '$arch' variable, but no 'Architecture'
# is defined"). Append dentro do bloco [options] (arquivo é só-options).
grep -q '^Architecture' /tmp/elite-pc-options \
    || printf 'Architecture = x86_64 x86_64_v3\n' >> /tmp/elite-pc-options
{
    cat /tmp/elite-pc-options
    cat <<'EOL'

[archcraft]
# packages.archcraft.io é UNSIGNED (nenhum .sig no repo): Never = zero
# sondas db.sig/pacote.sig (curl 404 no primeiro -Sy do sistema instalado);
# mesma segurança que TrustAll para um repo sem assinaturas.
SigLevel = Never
Include = /etc/pacman.d/archcraft-mirrorlist

# >>> ELITE: CachyOS — wiki.cachyos.org/features/optimized_repos
# Ordem: trio v3 ANTES do baseline (kernel linux-cachyos-bore existe nos dois:
# baseline 7.2.7 x86_64 vs v3 7.2.11 x86-64-v3 — pacman prefere o primeiro repo)
# v3: kernels, nvidia-open-dkms, gamescope
[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

# v3: rebuilds do [core]
[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

# v3: rebuilds do [extra]
[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

# v2 (baseline): keyring, cachyos-settings, dmemcg-booster, rules (exclusivos)
[cachyos]
Server = https://us.cachyos.org/repo/x86_64/cachyos
Server = https://cdn77.cachyos.org/repo/x86_64/cachyos
# <<< ELITE

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOL
} > "$ELITE_PC"
rm -f /tmp/elite-pc-options

## [E3b] Arquitetura: pacotes cachyos-v3 são arch "x86_64_v3" — o conf
##       do sistema precisa aceitar as duas (senão 'pacman -Syu' quebra)
if ! grep -qE '^Architecture = .*\bx86_64_v3\b' "$ELITE_PC"; then
    if grep -qE '^Architecture = ' "$ELITE_PC"; then
        sed -i -E 's|^Architecture = .*$|Architecture = x86_64 x86_64_v3|' "$ELITE_PC"
    else
        sed -i '/^\[options\]/a Architecture = x86_64 x86_64_v3' "$ELITE_PC"
    fi
fi

## [E4] Refresh das DBs (valida que os 6 repos resolvem dentro do chroot)
pacman -Sy --noconfirm || true

## [E11] v1.1 — NVIDIA dkms pré-compilado: VERIFICA + regenera o initramfs do live
##      ═════════════════════════════════════════════════════════════════
##      O pacstrap instalou nvidia-open-dkms (packages.add) e o hook do
##      dkms compilou os módulos contra o kernel BORE. Dois passos aqui:
##       1. GATE DURO: os módulos nvidia TÊM que existir para o kver BORE —
##          sem eles a entrada NVIDIA do live é um bootloader de mentira
##          (fail no build, nunca no boot do rig A).
##       2. REGEN do initramfs do live: o hook 90-mkinitcpio-install do
##          pacstrap roda ANTES do hook do dkms na mesma transação (ordem
##          alfabética: "90-..." < "dkms...") → a 1ª geração sai SEM
##          nvidia. Regeneramos aqui com o conf archiso recriado (o
##          customize upstream DELETOU /etc/mkinitcpio.conf.d antes deste
##          fragmento rodar — recriamos verbatim e limpamos depois: o
##          conf.d NÃO pode ir pro alvo, senão o drop-in archiso vence o
##          ALL_config do initcpio@elite na instalação — armadilha que o
##          E6b antigo documentava). Com o hook kms + módulos presentes,
##          UMA initramfs dá early-KMS nos DOIS rigs (o módulo do vendor
##          ausente apenas não binda — inerte).
ELITE_KVER=""
for _d in /usr/lib/modules/*cachyos-bore*; do
    [[ -d "$_d" ]] || continue
    ELITE_KVER="${_d##*/}"
    break
done
if [[ -n "$ELITE_KVER" ]]; then
    if ! ls /usr/lib/modules/"$ELITE_KVER"/updates/dkms/nvidia.ko* >/dev/null 2>&1; then
        echo "ELITE-FAIL: dkms NÃO compilou o nvidia para '$ELITE_KVER' —" >&2
        echo "  ver logs do pacstrap acima (headers ausentes? toolchain? fonte?)" >&2
        exit 1
    fi
    echo "E11: módulos nvidia presentes p/ $ELITE_KVER — regenerando initramfs do live (kms)"
    mkdir -p /etc/mkinitcpio.conf.d
    cat > /etc/mkinitcpio.conf.d/archiso.conf <<'EOARC'
HOOKS=(base udev microcode plymouth modconf kms memdisk archiso archiso_loop_mnt block filesystems keyboard)
COMPRESSION="xz"
COMPRESSION_OPTIONS=(-9e)
EOARC
    mkinitcpio -p linux-cachyos-bore
    rm -rf /etc/mkinitcpio.conf.d
else
    echo "ELITE-FAIL: kernel BORE não encontrado em /usr/lib/modules" >&2
    exit 1
fi

## [E5] Cirurgia no Calamares (efeito na INSTALAÇÃO, no sistema alvo):
##   a) unpackfs: a entrada do vmlinuz-linux stock vira a do BORE
##      (kernel único v1.1 — sem isto o alvo nasce sem kernel nenhum)
##   b) instância initcpio@elite gera o initramfs do BORE no alvo
##   c) packagechooser: sessão ÚNICA labwc (v1.0.3 — openbox/bspwm/sway fora
##      da ISO; a página "Desktop" apenas confirma o labwc)
##   d) autologin contextual: única escolha possível = labwc
##   e) chrooted_autologin.sh: branch --labwc (herda o slot do --everything)
##   f) btrfs como filesystem default (timeshift + grub-btrfs = rollback real)
CC="/etc/calamares"
if [[ -d "$CC" ]]; then
    # a) unpackfs: a entrada upstream copia o vmlinuz-linux (stock) — que
    #    NÃO existe mais na ISO (kernel único BORE, v1.1). Substituímos a
    #    entrada no lugar (mesma linha, kernel BORE); fallback: append.
    if [[ -f "$CC/modules/unpackfs.conf" ]]; then
        if grep -qF 'vmlinuz-linux"' "$CC/modules/unpackfs.conf" \
           && ! grep -qF 'vmlinuz-linux-cachyos-bore' "$CC/modules/unpackfs.conf"; then
            sed -i 's|vmlinuz-linux"|vmlinuz-linux-cachyos-bore"|g' "$CC/modules/unpackfs.conf"
        elif ! grep -q 'vmlinuz-linux-cachyos-bore' "$CC/modules/unpackfs.conf"; then
            printf '%s\n' \
                '    -   source: "/run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux-cachyos-bore"' \
                '        sourcefs: "file"' \
                '        destination: "/boot/vmlinuz-linux-cachyos-bore"' \
                >> "$CC/modules/unpackfs.conf"
        fi
    fi
    # b) initcpio@elite + REMOÇÃO do initcpio stock: o módulo upstream
    #    regenera o initramfs do kernel 'linux' no alvo — kernel que não
    #    existe mais (v1.1 single-kernel). Sem isto o Calamares ABORTA a
    #    instalação no mkinitcpio de um kernel ausente.
    if [[ -f "$CC/settings.conf" ]] && ! grep -q 'initcpio@elite' "$CC/settings.conf"; then
        sed -i '/config:   shellprocess_btrfs.conf/s/$/\n- id:       elite\n  module:   initcpio\n  config:   initcpio_elite.conf/' "$CC/settings.conf"
        sed -i '/^  - initcpio$/s/$/\n  - initcpio@elite/' "$CC/settings.conf"
        printf '%s\n' '---' 'kernel: linux-cachyos-bore' 'be_unsafe: false' \
            > "$CC/modules/initcpio_elite.conf"
    fi
    if grep -q '^  - initcpio$' "$CC/settings.conf"; then
        sed -i '/^  - initcpio$/d' "$CC/settings.conf"
    fi
    # c) packagechooser: itens openbox/bspwm/sway fora; everything vira labwc
    if [[ -f "$CC/modules/packagechooser.conf" ]]; then
        sed -i -e '/- id: openbox/,/openbox\.png/d' \
               -e '/- id: bspwm/,/bspwm\.png/d' \
               -e '/- id: sway/,/sway\.png/d' \
               -e 's|- id: everything|- id: labwc|' \
               -e 's|^      name: "Everything"|      name: "Archcraft Elite"|' \
               -e 's|^      description: "Install Everything.*|      description: "labwc (Wayland), rice Catppuccin Mocha — a sessão única da Elite, já instalada."|' \
               -e 's|^default: everything|default: labwc|' \
               "$CC/modules/packagechooser.conf"
    fi
    # d) autologin contextual: só existe uma escolha — labwc
    if [[ -f "$CC/modules/contextualprocess_autologin.conf" ]]; then
        awk '
          /^packagechooser_packagechooser:/ {
            print
            print "    labwc:"
            print "        - echo \"Setting labwc as session for autologin...\""
            print "        - /usr/bin/chrooted_autologin.sh --labwc"
            exit
          }
          { print }
        ' "$CC/modules/contextualprocess_autologin.conf" > /tmp/elite-cpa.conf
        cat /tmp/elite-cpa.conf > "$CC/modules/contextualprocess_autologin.conf"
        rm -f /tmp/elite-cpa.conf
    fi
    # e) chrooted_autologin.sh: --labwc (o slot --everything vira labwc;
    #    o corpo 'openbox' também vira 'labwc' — qualquer caminho legado
    #    configura a sessão certa). No-op de qualquer forma se /etc/sddm.conf
    #    não tem [Autologin] (o autologin real do live vem do drop-in .d/).
    if [[ -f /usr/bin/chrooted_autologin.sh ]]; then
        sed -i -e "s|--everything' ]]; then|--labwc' ]]; then|" \
               -e "s|enable_autologin 'openbox'|enable_autologin 'labwc'|g" \
               /usr/bin/chrooted_autologin.sh
    fi
    # f) btrfs default
    if [[ -f "$CC/modules/partition.conf" ]]; then
        sed -i 's|defaultFileSystemType: *"ext4"|defaultFileSystemType:  "btrfs"|' "$CC/modules/partition.conf"
    fi
fi

## [E6] Preset do BORE p/ o sistema INSTALADO (default/fallback). No live ele
##      nasceu com hooks archiso (overlay + regen do E11); o initcpio@elite
##      do E5b usa ESTE preset no alvo — kernel ÚNICO da Elite (v1.1: o
##      linux.preset stock foi aposentado junto com o kernel stock).
cat > /etc/mkinitcpio.d/linux-cachyos-bore.preset <<'EOL'
# mkinitcpio preset file for the 'linux-cachyos-bore' package (Elite)
ALL_kver="/boot/vmlinuz-linux-cachyos-bore"
ALL_config="/etc/mkinitcpio.conf"

PRESETS=('default' 'fallback')

default_image="/boot/initramfs-linux-cachyos-bore.img"

fallback_image="/boot/initramfs-linux-cachyos-bore-fallback.img"
fallback_options="-S autodetect"
EOL
## v1.1 (build #51): o bloco upstream "Fix Initrd Generation in Installed
## System" que RODA ANTES deste fragmento recria o /etc/mkinitcpio.d/
## linux.preset incondicionalmente (cat > heredoc no customize deles) —
## o [6.3] do overlay apaga o arquivo ESTÁTICO do profile, mas este cat
## o ressuscita DENTRO do chroot na hora do build. Kernel único: o órfão
## morre aqui de novo (o gate verify-install das builds #48/#51 pega
## exatamente isso no squashfs → sistema instalado).
rm -f /etc/mkinitcpio.d/linux.preset

## [E7] post-install do Archcraft: tira da lista de serviços habilitados
##      os que a Elite debloatou (cups via cups-filters→avahi) — evita
##      erro de "unit inexistente" no log da instalação
ELITE_PIS="/usr/bin/chrooted_post_install.sh"
if [[ -f "$ELITE_PIS" ]]; then
    sed -i -e "s/'cups.service'//" -e "s/'avahi-daemon.service'//" "$ELITE_PIS"
fi

## [E8] Remove o repo local [elite-local] da ISO (só é necessário durante
##      o pacstrap; os pacotes instalados ficam, o repo não)
rm -rf /var/cache/elite-local

## [E9] Sessão única labwc (v1.0.3): remove do skel as configs órfãs das
##      sessões/satélites que saíram (openbox, bspwm, polybar, tint2, rofi,
##      dunst, alacritty, kitty vieram do archcraft-skeleton). Sem isto o
##      home do liveuser nasce com diretórios mortos de apps que não existem.
##      Os configs Elite (labwc/waybar/swaync/fuzzel) permanecem; v1.1
##      também varre os configs órfãos da purga GTK3 (thunar/zathura/
##      mousepad/file-roller/blueman/pavucontrol vieram do skeleton).
for d in openbox bspwm polybar tint2 rofi dunst alacritty kitty thunar zathura mousepad file-roller blueman pavucontrol; do
    rm -rf "/etc/skel/.config/$d"
done

## [E12] v1.1 — /etc/environment: app-layer moderna (MEGA PROMPT).
##       O upstream seta EDITOR=nano / BROWSER=firefox / TERMINAL=alacritty
##       (stale: alacritty saiu na v1.0.3, firefox sai na v1.1). Sed no lugar
##       (drift-friendly: só as 3 chaves mudam, o resto do arquivo upstream
##       é preservado — nunca overlay inteiro de arquivo alheio).
ENVF="/etc/environment"
if [[ -f "$ENVF" ]]; then
    sed -i -e 's|^EDITOR=.*|EDITOR=helix|'   \
           -e 's|^BROWSER=.*|BROWSER=brave|' \
           -e 's|^TERMINAL=.*|TERMINAL=foot|' "$ENVF"
fi

## [E13] v1.2 — gpsd no live (burn test do dono: xgps/xgpsspeed no menu).
##       EVIDÊNCIA do pacman db da ISO v1.1: gpsd é dependência DURA do
##       waybar 0.15 (módulo gps compilado; remover com -Rdd mataria a
##       libgps e a barra NÃO abriria). A TENTATIVA -Rns abaixo falha
##       segura (transação inválida, nada é removido) e cobre o futuro:
##       se o waybar um dia deixar de depender, o gpsd some sozinho. A
##       cura REAL hoje: overrides NoDisplay p/ xgps/xgpsspeed no overlay
##       (/usr/local/share/applications — precedência XDG).
if command -v pacman >/dev/null 2>&1; then
    if pacman -Qq gpsd >/dev/null 2>&1; then
        pacman -Rns --noconfirm gpsd 2>/dev/null \
            || echo "ELITE E13: gpsd é dependência do waybar (libgps) — fica; xgps/xgpsspeed ocultos via NoDisplay" >&2
    fi
fi

## [E10] FIX DO BOOT DO SISTEMA INSTALADO (v1.0.4 · bug reportado no rig B)
##      ══════════════════════════════════════════════════════════════════
##      SINTOMA (GRUB, pós-instalação em btrfs):
##        error: kern/verifiers.c:grub_verifiers_open:156:
##               premature end of file /boot/vmlinuz-linux-cachyos-bore.
##        error: loader/i386/linux.c:grub_cmd_initrd:1882:
##               you need to load the kernel first.
##      CAUSA RAIZ (2 camadas, ambas do fluxo upstream do Calamares):
##       1. O install é UNPACKFS: o airootfs.sfs do LIVE é desempacotado
##          direto pro disco do alvo. Em btrfs, arquivos grandes podem
##          chegar TRUNCADOS — o próprio Archcraft já tem um workaround
##          (shellprocess@btrfs: "Copying kernel to target to fix BTRFS
##          boot issue") que recopia o vmlinuz-linux do pendrive… mas SÓ
##          o kernel STOCK. Nossa ISO boota o linux-cachyos-bore por
##          default → o vmlinuz do BORE ficava truncado no alvo → GRUB
##          "premature end of file" → sistema instalado não boota.
##       2. O initramfs-linux-cachyos-bore.img que o unpackfs copia é o
##          do LIVE (hooks ARCHISO — feitos pra achar a ISO de boot, não
##          o disco instalado). O módulo initcpio do Calamares regenera
##          APENAS o initramfs do kernel stock; o do BORE chegava ao alvo
##          com hooks de live → mesmo com o vmlinuz inteiro, o boot morria.
##      FIX (2 comandos no mesmo job, ANTES do grubcfg/bootloader — a
##      sequência do settings.conf upstream já executa shellprocess@btrfs
##      nesse ponto):
##       1. Recopia TODOS os vmlinuz-* do pendrive (fonte íntegra — é dela
##          que o live bootou) para os que existem no /boot do alvo.
##       2. Regenera o initramfs do BORE NO ALVO (arch-chroot + preset E6:
##          default/fallback com ALL_config=/etc/mkinitcpio.conf — o conf
##          que o módulo initcpiocfg do Calamares escreveu com hooks de
##          sistema). || true: best-effort, nunca aborta o install.
##      O marcador .kernel-copy-success do upstream é preservado.
if [[ -f /etc/calamares/modules/shellprocess_btrfs.conf ]]; then
    cat > /etc/calamares/modules/shellprocess_btrfs.conf <<'EOSB'
# SPDX-FileCopyrightText: no
# SPDX-License-Identifier: CC0-1.0
#
# ELITE v1.1 — fix do boot instalado em btrfs (v1.0.4: recopia TODOS os
# vmlinuz + regenera o initramfs do BORE) + ESPECIALIZAÇÃO POR GPU NA
# INSTALAÇÃO (v1.1, MEGA PROMPT: "sem influenciar um ao outro ou sujar,
# principalmente na instalação"):
#   · AMD     → remove o stack NVIDIA inteiro do alvo (dkms+utils+ módulos),
#               MODULES=(amdgpu) + amdgpu.ppfeaturemask no GRUB → early-KMS
#               limpo, zero pacote estranho no disco
#   · NVIDIA  → MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm) +
#               nvidia_drm.modeset=1 fbdev=1 no GRUB + modprobe.d (o driver
#               dkms pré-compilado da ISO já está no alvo via unpackfs —
#               belt-and-suspenders: o shellprocess@kms upstream também seda
#               o MODULES quando o live usou o driver)
#   · unknown → nenhum toque (VM/garanta neutra; o initcpiocfg decide)
# Roda DEPOIS de unpackfs/packages (alvo completo) e ANTES de grubcfg/
# bootloader (o GRUB gerado já nasce com os params certos). Ver
# elite-customize [E10].
---
dontChroot: true
timeout: 9999
verbose: false
script:
    - command: >
        if [ "$(findmnt -n -o FSTYPE "${ROOT}")" = "btrfs" ]; then
          for kv in /run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-*; do
            kbase="$(basename "${kv}")"
            if [ -f "${ROOT}/boot/${kbase}" ]; then
              cp -f "${kv}" "${ROOT}/boot/${kbase}" &&
              touch "${ROOT}/boot/.kernel-copy-success"
            fi
          done
        fi
    - command: >
        ELITE_GPU=unknown;
        for v in /sys/class/drm/card*/device/vendor; do
          [ -r "$v" ] || continue;
          case "$(cat "$v" 2>/dev/null)" in
            0x10de) ELITE_GPU=nvidia ;;
            0x1002) [ "$ELITE_GPU" != "nvidia" ] && ELITE_GPU=amd ;;
          esac;
        done;
        echo "ELITE: GPU do alvo = $ELITE_GPU";
        if [ "$ELITE_GPU" = "amd" ]; then
          arch-chroot "${ROOT}" pacman -Rdd --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils 2>/dev/null || true;
          rm -f "${ROOT}"/usr/lib/modules/*/updates/dkms/nvidia*.ko* 2>/dev/null || true;
          sed -i 's|^MODULES=.*|MODULES=(amdgpu)|' "${ROOT}/etc/mkinitcpio.conf" 2>/dev/null || true;
          printf '%s\n' '# ELITE: AMD - destrava undervolt/OC p/ LACT' 'options amdgpu ppfeaturemask=0xffffffff' > "${ROOT}/etc/modprobe.d/00-elite-amdgpu.conf";
          if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "${ROOT}/etc/default/grub" 2>/dev/null; then
            grep -q 'amdgpu.ppfeaturemask' "${ROOT}/etc/default/grub" ||
              sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/s/"$/ amdgpu.ppfeaturemask=0xffffffff"/' "${ROOT}/etc/default/grub";
          else
            printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet amdgpu.ppfeaturemask=0xffffffff"\n' >> "${ROOT}/etc/default/grub";
          fi
        elif [ "$ELITE_GPU" = "nvidia" ]; then
          grep -q '^MODULES=(nvidia' "${ROOT}/etc/mkinitcpio.conf" 2>/dev/null ||
            sed -i 's|^MODULES=.*|MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)|' "${ROOT}/etc/mkinitcpio.conf" 2>/dev/null || true;
          printf '%s\n' '# ELITE: NVIDIA (modeset+fbdev p/ Wayland; VRAM preservada em suspend)' 'options nvidia-drm modeset=1 fbdev=1' 'options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp' > "${ROOT}/etc/modprobe.d/00-elite-nvidia.conf";
          if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "${ROOT}/etc/default/grub" 2>/dev/null; then
            grep -q 'nvidia_drm.fbdev' "${ROOT}/etc/default/grub" ||
              sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/s/"$/ nvidia_drm.modeset=1 nvidia_drm.fbdev=1"/' "${ROOT}/etc/default/grub";
          else
            printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet nvidia_drm.modeset=1 nvidia_drm.fbdev=1"\n' >> "${ROOT}/etc/default/grub";
          fi
        fi
    - command: >
        if [ -f "${ROOT}/boot/vmlinuz-linux-cachyos-bore" ] &&
           [ -x "${ROOT}/usr/bin/mkinitcpio" ]; then
          arch-chroot "${ROOT}" mkinitcpio -p linux-cachyos-bore || true
        fi
i18n:
     name: "Elite: GPU profile + kernels + BORE initramfs (btrfs boot fix)..."
EOSB
fi
