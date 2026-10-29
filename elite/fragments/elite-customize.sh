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

## [E2] keyring + mirrorlist v3 oficiais — OFFLINE-FIRST (v1.5.1 REAL).
##      O .ci/build.sh baixa os dois (listing us → pin; download cdn77 →
##      us) p/ o [elite-local], entregue DENTRO do chroot via overlay
##      (build.sh: "file:// resolve relativo ao root ativo"). Escada:
##      [elite-local] → pacman -U (mirror) → mirrorlist manual (a chave
##      já caiu via E1; o keyring empacotado é a forma canônica,
##      atualizável pelo pacman).
##
##      v1.5.1 — CURA do run #40/#41, com as DUAS causas provadas nos logs
##      (a segunda presente DESDE a v1.4, onde falhava em silêncio e a ISO
##      saía sem keyring — causa-raiz do "unknown trust" do burn test):
##        (a) o /etc/pacman.conf DESTE momento é o do PACOTE pacman: o
##            pacstrap -C NÃO copia o conf p/ o chroot (só -P faria) →
##            SEM [elite-local] → o -S dava "target not found" em TODA
##            run (v1.4 incluída) e caía no -U de rede sem ninguém ver;
##        (b) o commit de QUALQUER install in-chroot morria no CheckSpace:
##            o mtab lido pelo pacman (/etc/mtab → /proc/self/mounts do
##            chroot) NÃO lista entrada "/" → "could not determine root
##            mount point /" + "not enough free disk space" com 84G
##            livres (fonte: diskspace.c/sync.c do pacman — check_diskspace
##            é gated pelo CheckSpace e SÓ existe no caminho de install;
##            -R/-Sy nunca passam por ele).
##      Cura: conf efêmero = /etc/pacman.conf + [elite-local] (file://)
##      SEM CheckSpace → -S offline determinístico (repo dentro do chroot)
##      + commit sem a sonda de mtab. O conf do sistema fica intocado (E3
##      o reescreve logo a seguir); o -U de rede segue como fallback.
elite_latest() {
    curl -fsSL --max-time 30 "${ELITE_MIRROR}/repo/x86_64/cachyos/" 2>/dev/null \
        | grep -oE "$1-[0-9][^\"]*\.pkg\.tar\.zst" | sort -Vu | tail -1 || true
}
ELITE_PC_KR="$(mktemp)"
{
    cat /etc/pacman.conf
    printf '\n[elite-local]\nSigLevel = Never\nServer = file:///var/cache/elite-local\n'
} >"$ELITE_PC_KR"
sed '/^[[:space:]]*CheckSpace[[:space:]]*$/d' "$ELITE_PC_KR" >"${ELITE_PC_KR}.nc"
if ! pacman --config "${ELITE_PC_KR}.nc" -S --noconfirm cachyos-keyring cachyos-v3-mirrorlist; then
    ELITE_KEYRING_PKG="$(elite_latest cachyos-keyring)"
    [[ -n "$ELITE_KEYRING_PKG" ]] || ELITE_KEYRING_PKG="$ELITE_KEYRING_PINNED"
    ELITE_V3ML_PKG="$(elite_latest cachyos-v3-mirrorlist)"
    [[ -n "$ELITE_V3ML_PKG" ]] || ELITE_V3ML_PKG="$ELITE_V3ML_PINNED"
    if ! pacman --config "${ELITE_PC_KR}.nc" -U --noconfirm \
            "${ELITE_MIRROR}/repo/x86_64/cachyos/${ELITE_KEYRING_PKG}" \
            "${ELITE_MIRROR}/repo/x86_64/cachyos/${ELITE_V3ML_PKG}"; then
        ## Fallback: escreve o mirrorlist na mão (a chave já caiu via E1)
        printf 'Server = %s/repo/x86_64_v3/$repo\nServer = %s/repo/x86_64_v3/$repo\n' \
            "$ELITE_MIRROR" "$ELITE_MIRROR2" > /etc/pacman.d/cachyos-v3-mirrorlist
    fi
fi
rm -f "$ELITE_PC_KR" "${ELITE_PC_KR}.nc"

## [E2b] v1.5 — POPULAR o keyring do chroot (build/live/instalado).
##       Causa-raiz do "signature from CachyOS unknown trust" do burn
##       test: o E1 fazia recv+lsign da chave MESTRA (F3B6…) apenas — o
##       gnupg do airootfs nascia com UMA chave confiável, e os pacotes
##       do repo CachyOS vêm assinados pelos PACKAGER keys do keyring
##       completo. No LIVE isso é auto-curado (pacman-init.service do
##       archiso/archcraft roda `pacman-key --populate` SEM argumentos
##       sobre um tmpfs — popula TODOS os keyrings em
##       /usr/share/pacman/keyrings/, e o cachyos-keyring instalado
##       pelo E2 deposita os seus lá). Mas o SISTEMA INSTALADO copia o
##       gnupg DO SQUASHFS via unpackfs — e só a população AQUI coloca
##       as chaves CachyOS no disco do alvo. Belt-and-suspenders: o E10
##       re-popula no chroot do alvo na instalação.
##       GATE DURO: sem /usr/share/pacman/keyrings/cachyos.gpg o live
##       também quebraria (populate sem argumentos só popula o que
##       existe) — falha AQUI, no build, nunca no boot (filosofia Elite).
if [[ ! -f /usr/share/pacman/keyrings/cachyos.gpg ]]; then
    echo "ELITE-FAIL: cachyos-keyring não instalado (cachyos.gpg ausente) —" >&2
    echo "  o populate do live (pacman-init) E do instalado dependem dele" >&2
    exit 1
fi
pacman-key --populate archlinux cachyos || true

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

# v2 (baseline): keyring, cachyos-settings, rules (exclusivos)
# [v2.2: o dmemcg-booster saiu da ISO na fusão dos boosters]
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
##   f) btrfs como filesystem default (snapper + grub-btrfs = rollback real — v2.3.6: o rig provou que timeshift era promessa pela metade)
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
    # a2) launch.sh × copytoram — A CAUSA-RAIZ DO BURN TEST v1.5 (provada
    #     com fonte primária): o launch.sh do Archcraft, ao detectar
    #     /run/archiso/copytoram, REESCREVE o unpackfs.conf com
    #       sed "s|…/x86_64/vmlinuz-linux|/usr/lib/modules/$KERNEL/vmlinuz|g"
    #     O padrão 'vmlinuz-linux' casa como PREFIXO do nosso kernel
    #     renomeado e deixa o sufixo órfão → source vira
    #     "/usr/lib/modules/<kver>/vmlinuz-cachyos-bore" — arquivo que NÃO
    #     existe (o real é 'vmlinuz', sem sufixo, no mesmo diretório).
    #     Resultado no rig do dono: "Configuração incorreta do unpackfs"
    #     (log termbin 9z69; ISO íntegra — sha256 conferido; conf correto
    #     DENTRO do squashfs). Alinhamos o padrão do sed do launch.sh com
    #     o kernel único BORE; o replacement segue apontando pro arquivo
    #     REAL ('vmlinuz', sem sufixo — localização canônica do pacote
    #     de kernel, verificada no squashfs da v1.5).
    if [[ -f "$CC/launch.sh" ]] && grep -q 'x86_64/vmlinuz-linux|/usr/lib/modules' "$CC/launch.sh"; then
        sed -i 's#boot/x86_64/vmlinuz-linux|#boot/x86_64/vmlinuz-linux-cachyos-bore|#' "$CC/launch.sh"
        echo "==> E5a2: launch.sh (copytoram) alinhado ao kernel BORE (fix do burn test v1.5)"
    elif [[ -f "$CC/launch.sh" ]] && ! grep -q 'x86_64/vmlinuz-linux-cachyos-bore|/usr/lib/modules' "$CC/launch.sh"; then
        echo "==> E5a2 AVISO: padrão do launch.sh mudou no upstream — conferir copytoram×BORE" >&2
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
for d in openbox bspwm polybar tint2 rofi dunst alacritty kitty zathura mousepad file-roller blueman pavucontrol yazi helix; do
    rm -rf "/etc/skel/.config/$d"
done

## [E12] v1.1 — /etc/environment: app-layer moderna (MEGA PROMPT).
##       O upstream seta EDITOR=nano / BROWSER=firefox / TERMINAL=alacritty
##       (stale: alacritty saiu na v1.0.3, firefox sai na v1.1). Sed no lugar
##       (drift-friendly: só as 3 chaves mudam, o resto do arquivo upstream
##       é preservado — nunca overlay inteiro de arquivo alheio).
ENVF="/etc/environment"
if [[ -f "$ENVF" ]]; then
    sed -i -e 's|^EDITOR=.*|EDITOR=nano|'   \
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
##       v1.5 — pesquisa de fontes primárias confirma a dependência:
##       archlinux.org/packages/extra/x86_64/waybar (0.15.0-3, "Dependencies
##       (47)" inclui gpsd; módulo GPS compilado desde o waybar 0.13.0,
##       meson 'gps' feature auto). Remover o gpsd = dock/menu bar mortas.
if command -v pacman >/dev/null 2>&1; then
    if pacman -Qq gpsd >/dev/null 2>&1; then
        pacman -Rns --noconfirm gpsd 2>/dev/null \
            || echo "ELITE E13: gpsd é dependência do waybar (libgps) — fica; xgps/xgpsspeed ocultos via NoDisplay" >&2
    fi
fi

## [E14] v1.5 — gufw/ufw FORA (spec do dono: bloatware). O upstream
##       archcraft lista ufw+gufw no packages.x86_64 E habilita
##       ufw.service no boot (multi-user.target.wants/ufw.service).
##       O apply-overlay [7] já derruba o symlink do wants no PROFILE;
##       este bloco varre o que porventura existir no chroot final e
##       remove os pacotes com seus órfãos (se algum outro pacote os
##       puxar de volta, a remoção falha segura e o NoDisplay do gufw
##       — overlay — esconde o atalho).
rm -f /etc/systemd/system/multi-user.target.wants/ufw.service
if command -v pacman >/dev/null 2>&1; then
    pacman -Rns --noconfirm gufw ufw 2>/dev/null \
        || echo "ELITE E14: gufw/ufw não removíveis (dependência?) — serviço derrubado, atalho oculto via NoDisplay" >&2
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
# ELITE v1.1→v1.7 — fix do boot instalado em btrfs (recopia TODOS os
# vmlinuz + regenera o initramfs do BORE) + ESPECIALIZAÇÃO POR GPU NA
# INSTALAÇÃO (AMD remove NVIDIA do alvo · NVIDIA modeset/fbdev · unknown
# não toca).
#
# v1.7 — A CLASSE DO BUG DO INSTALADOR MORTA POR CONTRATO: o Calamares
#   expande TODO $var/${var} de um `command:` inline contra ROOT/USER/LANG
#   + global storage ANTES de rodar o shell (doc oficial no header do
#   shellprocess_kms.conf: "It is not possible to get an un-escaped $ in
#   the shell command — either the command will fail because of undefined
#   variables, or you get a shell-escaped \$"). O YAML antigo usava
#   variáveis DE SHELL (${kv}/${kbase}/$v/$ELITE_GPU) → na máquina real:
#   "Could not run command. The commands use variables that are not
#   defined. Missing variables are: kv,kbase,kv,kbase,v,v." → Installation
#   Failed. O gate do CI não via porque reproduz a cadeia FORA do
#   Calamares. Toda a lógica agora vive no elite-install-stage (arquivo
#   real = semântica de shell de verdade, shellcheck+bash -n na suíte) e
#   o contrato da suíte varre os heredocs de .conf do Calamares com uma
#   allowlist de $ (tests/phases/40-integration.sh) — a classe não volta.
---
dontChroot: true
timeout: 9999
verbose: false
script:
    - command: "/usr/local/bin/elite-install-stage ${ROOT}"
i18n:
     name: "Elite: GPU profile + kernels + BORE initramfs (btrfs boot fix)..."
EOSB
fi

## [E15] v1.8.1 — DEBLOAT SISTÊMICO (conteúdo morto, não pacotes).
##      Pedido do dono ("debloat pra ir além, não só em pacotes"). As 4
##      podas abaixo são provadamente inertes em runtime:
##        a) /usr/share/locale fora de pt*/en* — a sessão do dono roda
##           pt/en; todo o resto é tradução de app morta no disco.
##           locale.alias (arquivo) e l10n/ (dados por-país) ficam.
##        b) locale.gen → EXATAMENTE en_US.UTF-8 + pt_BR.UTF-8 e re-gen:
##           o archive de locales (locale-archive) nasce do locale.gen
##           corrente — podar a lista e regenerar encolhe o arquivo de
##           ~100-200 MB (todas as locales) para ~1-2 MB. O dono ganha
##           pt_BR disponível de fábrica (LANG continua o do upstream —
##           o rice não muda). AUTO-CURA: se o locale-gen falhar, o
##           locale.gen upstream volta e re-gen; ELITE-FAIL se ainda
##           assim faltar locale (falha no build, nunca no boot).
##        c) man/info/doc/gtk-doc fora — nenhum binário lê isso em
##           runtime; licenças (/usr/share/licenses) FICAM (compliance).
##           Páginas voltam reinstalando o pacote (pacman -S <pkg>).
##        d) journald cap = drop-in estático 99-elite-cap.conf (overlay).
if [[ -f /etc/locale.gen ]]; then
    { grep -hE '^#?[[:space:]]*en_US\.UTF-8' /etc/locale.gen | head -1
      grep -hE '^#?[[:space:]]*pt_BR\.UTF-8' /etc/locale.gen | head -1
    } | sed 's/^#[[:space:]]*//' > /etc/locale.gen.elite
    if [[ $(grep -c '.' /etc/locale.gen.elite) -eq 2 ]]; then
        cp /etc/locale.gen /etc/locale.gen.upstream
        mv /etc/locale.gen.elite /etc/locale.gen
        locale-gen >/dev/null 2>&1 || true
        if ! locale -a 2>/dev/null | grep -qi 'en_US.utf8' \
           || ! locale -a 2>/dev/null | grep -qi 'pt_BR.utf8'; then
            echo "E15: locale-gen falhou com a lista podada — restaurando locale.gen upstream" >&2
            mv /etc/locale.gen.upstream /etc/locale.gen
            locale-gen >/dev/null 2>&1 || true
            locale -a 2>/dev/null | grep -qi 'en_US.utf8' \
                || { echo "ELITE-FAIL: locale ausente após auto-cura do E15 (locale-gen quebrado)" >&2; exit 1; }
        fi
        rm -f /etc/locale.gen.upstream
        echo "E15: locales = en_US.UTF-8 + pt_BR.UTF-8 (archive regenerado)"
    else
        rm -f /etc/locale.gen.elite
        echo "E15 AVISO: locale.gen sem as 2 entradas padrão — intocado (upstream mudou?)" >&2
    fi
fi
find /usr/share/locale -mindepth 1 -maxdepth 1 -type d \
    ! -name 'en*' ! -name 'pt*' ! -name 'l10n' -exec rm -rf {} + 2>/dev/null || true
rm -rf /usr/share/man /usr/share/info /usr/share/doc /usr/share/gtk-doc 2>/dev/null || true
echo "E15: locale/man/info/doc/gtk-doc podados (licenses intactas)"

## [E16] v2.2 — SEM TEMA DE ÍCONES (leveza radical, diretriz do dono).
##      O tema de ícones do upstream SAIU do packages.add — não há nada a podar.
##      O antigo E16 (v1.8.1) podava as 4 variantes mortas desse tema e
##      falhava a build sem as 2 vivas; hoje o único tema de
##      ícones do sistema é o fallback base (Adwaita — dep dura de
##      gtk3/gtk4, <1 MB) e cada app traz o próprio ícone no hicolor.
##      Guarda INFORMATIVA (nomes de tema variam entre versões de pacote —
##      o contrato de ausência vive na suíte, onde é exato): qualquer dir
##      fora da base (Adwaita*/Bibata*/hicolor) é avisado no log.
for _iv in /usr/share/icons/*; do
    [[ -d "$_iv" ]] || continue
    case "$(basename "$_iv")" in
        Adwaita*|Bibata*|hicolor|locolor) ;;
        *) echo "E16 AVISO: tema de ícones não-base detectado: $(basename "$_iv") (o pacote mudou?)" >&2 ;;
    esac
done
echo "E16: sem tema de ícones de terceiros — fallback base (Adwaita/hicolor) cobre"


## [E17] v1.8.2 — LACT: o daemon habilitado DE FÁBRICA.
##      Burn test da v1.8.1 (fotos do dono IMG_20261024_115839 + áudio):
##      abrir o LACT mostrava "Service Setup · Service Status: inactive" —
##      o app instava o usuário a configurar serviço à mão. O ppfeaturemask
##      do amdgpu (E10/elite-install-stage) já destrava undervolt/OC; o que
##      faltava era o lactd subindo. Habilitar no BUILD = o symlink nasce
##      no /etc do airootfs → o LIVE e o INSTALADO (unpackfs) herdam — um
##      comando cobre os dois. Guard: sem o unit (pacote mudou), avisa e
##      segue — o LACT continua abrindo em modo leitura, como hoje.
if [[ -f /usr/lib/systemd/system/lactd.service ]]; then
    # ln -sf DIRETO (o que o systemctl enable faz): o build roda em
    # container SEM PID 1 — o systemctl pode recusar verbs, o ln nunca.
    mkdir -p /etc/systemd/system/multi-user.target.wants
    ln -sf /usr/lib/systemd/system/lactd.service \
        /etc/systemd/system/multi-user.target.wants/lactd.service
    if [[ -e /etc/systemd/system/multi-user.target.wants/lactd.service ]]; then
        echo "E17: lactd habilitado (LACT abre com controle total, sem Service Setup)"
    else
        echo "ELITE-FAIL: symlink do wants do lactd não criado (fs somente-leitura?)" >&2
        exit 1
    fi
else
    echo "E17 AVISO: lactd.service ausente — LACT segue em modo leitura (pacote mudou?)"
fi


## [E18] v2.3.2 — HIGIENE DO post_install UPSTREAM (log do Calamares do
##      dono, 25/out — três ruídos que se repetem EM TODA instalação):
##   a) "Failed to enable unit: Unit ufw.service does not exist" — o
##      script upstream habilita ufw, mas o ufw SAIU da ISO (E14, spec do
##      dono). Mesma cura do E7 (cups/avahi): some da lista de units.
##   b) "error: target not found: nvidia-open" — o caminho "sem NVIDIA"
##      tenta remover o pacote 'nvidia-open' (nome pré-compilado do
##      kernel stock, packages.remove v1.1); o real da Elite é
##      nvidia-open-dkms. Nome trocado = a transação -Rns inteira volta
##      a remover de primeira (e o log fica limpo).
##   c) "which: command not found" (chrooted_post_install.sh:315 e o
##      grubcfg do Calamares: `which dracut/plymouth` → exit 127) — a
##      ISO não traz o binário `which`; entrou no packages.add (core,
##      ~20 KB — dependência de fato dos scripts do upstream).
ELITE_PIS="/usr/bin/chrooted_post_install.sh"
ELITE_PIL="/usr/bin/post_install.sh"
for _pis in "$ELITE_PIS" "$ELITE_PIL"; do
    [[ -f "$_pis" ]] || continue
    if grep -q "'ufw.service'" "$_pis"; then
        sed -i "s/'ufw.service'//g" "$_pis"
        echo "E18a: ufw.service fora da lista de units do post_install ($(basename "$_pis")) — o pacote saiu no E14"
    fi
    if grep -qE 'nvidia-open([^-a-zA-Z0-9_]|$)' "$_pis"; then
        sed -i -E 's/nvidia-open([^-a-zA-Z0-9_]|$)/nvidia-open-dkms\1/g' "$_pis"
        echo "E18b: nvidia-open → nvidia-open-dkms no post_install ($(basename "$_pis")) — nome real do pacote"
    fi
done


## [E19] v2.3.2 — POLIMENTO DO CALAMARES (warnings/banner do log 25/out):
##   a) partition.conf: *defaultPartitionTableType* unset gera warning a
##      cada install. A lista ["gpt","msdos"] REPRODUZ EXATAMENTE o
##      comportamento automático atual (GPT em UEFI, msdos em BIOS) —
##      zero mudança de comportamento, warning morto.
##   b) users.conf: 'nonempty: true' é IGNORADO na 3.4 (o Calamares avisa;
##      pede minLength: 1 — semântica idêntica, warning morto).
##   c) branding: o slideshow default gira "Next slide" a cada 5s durante
##      a instalação inteira (CPU + spam de log — diretriz do dono:
##      debloat dos banners). Slide ÚNICO estático, zero dependências
##      além do QtQuick, nas cores do rice (Catppuccin Mocha).
if [[ -f "$CC/modules/partition.conf" ]] && ! grep -q '^defaultPartitionTableType:' "$CC/modules/partition.conf"; then
    printf '\n# ELITE E19a: explícito e idêntico ao automático (GPT em UEFI, msdos em BIOS)\ndefaultPartitionTableType: [ "gpt", "msdos" ]\n' >> "$CC/modules/partition.conf"
    echo "E19a: defaultPartitionTableType explícito (gpt/msdos) — warning morto"
fi
if [[ -f "$CC/modules/users.conf" ]] && grep -q 'nonempty: true' "$CC/modules/users.conf" \
    && ! grep -q 'minLength:' "$CC/modules/users.conf"; then
    sed -i 's/nonempty: true/minLength: 1/' "$CC/modules/users.conf"
    echo "E19b: users.conf nonempty → minLength: 1 (semântica idêntica na 3.4)"
fi
if [[ -d "$CC/branding/archcraft" ]]; then
    # slide único (sem $ no corpo — heredoc quoted; QML sem dependência de
    # calamares.slideshow: carrega com qualquer slideshowAPI)
    cat > "$CC/branding/archcraft/show.qml" <<'EOQML'
// ELITE E19c: banner único estático (o slideshow default girava "Next
// slide" a cada 5s durante a instalação — CPU e spam de log à toa).
import QtQuick 2.15;
Rectangle {
    id: root
    color: "#1e1e2e"
    Text {
        anchors.centerIn: parent
        color: "#cdd6f4"
        font.pixelSize: 26
        text: qsTr("Archcraft Elite — instalando o sistema…")
    }
}
EOQML
    if [[ -f "$CC/branding/archcraft/branding.desc" ]]; then
        if grep -q '^slideshow:' "$CC/branding/archcraft/branding.desc"; then
            sed -i 's|^slideshow:.*|slideshow: "show.qml"|' "$CC/branding/archcraft/branding.desc"
        else
            sed -i '/^slideshowAPI:/i slideshow: "show.qml"' "$CC/branding/archcraft/branding.desc"
        fi
        if python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' \
            "$CC/branding/archcraft/branding.desc" 2>/dev/null; then
            echo "E19c: slideshow do Calamares = banner único estático (branding.desc YAML válido)"
        else
            echo "E19c AVISO: branding.desc não parseou como YAML (pyyaml ausente ou mudou?) — conferir no build" >&2
        fi
    else
        echo "E19c: show.qml mínimo escrito (branding.desc ausente — upstream mudou o layout?)"
    fi
fi


## [E20] v2.3.5 — FIM DA PALESTRA DO SUDO (print do dono, out/2026: o
##      "Presumimos que você recebeu as instruções de sempre do
##      administrador local…" no primeiro sudo de cada boot/TTY é ruído,
##      não segurança — o dono pediu limpo: "eu não quero isso"). O
##      `Defaults !lecture` mata a lição sem tocar no resto do sudoers.
##      Validado com visudo -cf (arquivo ruim NUNCA entra no sudoers.d —
##      um sudoers quebrado derruba TODA a elevação do sistema).
if [[ -d /etc/sudoers.d ]] && ! grep -qs '!lecture' /etc/sudoers.d/*; then
    printf '%s\n' '# ELITE E20: sem a palestra do sudo (ruído, não segurança)' \
        'Defaults !lecture' > /etc/sudoers.d/99-elite-lecture
    chmod 0440 /etc/sudoers.d/99-elite-lecture
    if command -v visudo >/dev/null 2>&1; then
        if visudo -cf /etc/sudoers.d/99-elite-lecture >/dev/null 2>&1; then
            echo "E20: palestra do sudo desligada (Defaults !lecture — visudo OK)"
        else
            echo "ELITE-FAIL: sudoers.d/99-elite-lecture inválido (visudo)" >&2
            rm -f /etc/sudoers.d/99-elite-lecture
            exit 1
        fi
    else
        echo "E20: Defaults !lecture escrito (visudo ausente no chroot — conferir no build)"
    fi
fi


## [E21] v2.9.0 — A GAVETA LIMPA (pedido do dono, rig v2.8.0: "oculta esses
##      programas como xarchiver, gtk settings e etc que não precisa ficar
##      na gaveta de aplicativos pois tem um acesso melhor de alguma forma
##      ou são extensões, tipo o programa de documentos abrir pelo
##      explorador de arquivos"). Helpers/extensões/demos saem DA GAVETA
##      sem morrer: NoDisplay=true esconde do drawer (nwg-drawer respeita)
##      e de TODOS os menus de aplicativo, mas Exec/Icon/MimeType ficam
##      INTACTOS — abrir um .7z no Thunar, um PDF pelo explorador ou o
##      editor avançado de rede (W-n) segue funcionando IGUAL. É BUILD-TIME
##      (o customize roda no chroot após o pacstrap): o sed insere a chave
##      DENTRO do grupo [Desktop Entry] (appending no fim do arquivo cairia
##      num grupo [Desktop Action …] e seria ignorado). Idempotente (grep).
if [[ -d /usr/share/applications ]]; then
    _elite_hidden=0
    for _dd in \
        /usr/share/applications/xarchiver.desktop \
        /usr/share/applications/thunar-bulk-rename.desktop \
        /usr/share/applications/papers.desktop \
        /usr/share/applications/nm-connection-editor.desktop \
        /usr/share/applications/gtk3-demo.desktop \
        /usr/share/applications/gtk3-widget-factory.desktop \
        /usr/share/applications/gtk3-icon-browser.desktop; do
        [[ -f "$_dd" ]] || continue
        grep -qs '^NoDisplay=true' "$_dd" && continue
        sed -i '/^\[Desktop Entry\]/a NoDisplay=true' "$_dd"
        _elite_hidden=$((_elite_hidden + 1))
        echo "E21: oculto da gaveta (NoDisplay): $_dd"
    done
    echo "E21: gaveta limpa — $_elite_hidden helper(s)/demo(s) fora da grade de apps"
else
    echo "E21 AVISO: /usr/share/applications ausente no chroot — gaveta NÃO limpa" >&2
fi

## [E22] v2.10.8 — A IDENTIDADE DA ELITE NO PAPEL (dump d33o: o instalado
##      responde PRETTY_NAME="Archcraft" seco — o dono não vê a distro em
##      lugar NENHUM, nem hostname de marca, e o forense julga 'sistema
##      alheio'). O os-release do chroot é o do BASE Archcraft; aqui a
##      marca entra (PRETTY_NAME + VARIANT) — o unpackfs copia o root
##      inteiro, o INSTALADO herda a identidade. Sem número de versão no
##      PRETTY_NAME: número muda por release e o papel não mente nem aqui.
if [[ -f /usr/lib/os-release ]]; then
    sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Archcraft Elite"/' /usr/lib/os-release
    grep -q '^VARIANT=' /usr/lib/os-release || \
        printf 'VARIANT="Elite Edition"\nVARIANT_ID="elite"\n' >> /usr/lib/os-release
    echo "E22: os-release marcado — $(grep PRETTY_NAME /usr/lib/os-release)"
else
    echo "E22 AVISO: /usr/lib/os-release ausente — identidade NÃO marcada" >&2
fi
