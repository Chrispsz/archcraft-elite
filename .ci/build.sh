#!/usr/bin/env bash
# =====================================================================
#  .ci/build.sh — roda DENTRO do container Arch Linux PRIVILEGIADO
#  (o pacstrap precisa montar /proc & cia. no chroot — containers
#  comuns do GitHub Actions não têm permissão de mount).
#
#  Entrada: /work = checkout do repo (montado), /mnt = disco grande
#  Saída:   /work/out/archcraft-elite-<data>-x86_64.iso + sha256sums
# =====================================================================
set -euo pipefail

say() { echo -e "\033[1;32m==>\033[0m $1"; }

say "Disco disponível:"
df -h / /mnt || true

say "Preparando container (archiso + deps do mkarchcraftiso)"
sed -i 's/^#ParallelDownloads/ParallelDownloads/; s/^#Color/Color/' /etc/pacman.conf
# E43 — o canal diário (PACKAGES_ONLY) precisa só do toolchain de makepkg:
# sem archiso/xorriso/pacstrap (nenhum mount acontece no modo pacotes).
if [[ "${PACKAGES_ONLY:-0}" == "1" ]]; then
    # E75.1 — o wlopm é DEPENDÊNCIA do elite-system (a rede do resume sem
    # o binário era imaginária) — o makepkg do container EXIGE o pacote
    # instalado, senão a transação do canal morre em 'Missing dependencies'.
    # E103 — o polkit entra pelos HEADERS do listener (libpolkit-agent-1 —
    # o agente sob demanda da casa; sem o pacote, o makepkg morre igual).
    # E132 — o RUST/CARGO entra pelo MAKENDEPENDS do elite-system (a ordem
    # do dono: espremer o limão — o workspace compila NO build; o builder
    # do makepkg abaixo não tem sudo NESTE trecho, o toolchain mora no
    # container e ZERO Rust viaja na ISO ou no pacote final).
    # E138 — O PAR X É DEPENDÊNCIA DURA (a ordem do dono, dump v2.13): o
    # cinto xhost + o cookie xauth do elite-gparted nascem COM o pacote.
    pacman -Syu --noconfirm --needed git rsync curl base-devel sudo python \
        wayland wayland-protocols libxkbcommon wlopm polkit rust cargo \
        gtk4 gtk4-layer-shell xorg-xhost xorg-xauth
else
    pacman -Syu --noconfirm --needed \
        git rsync curl archiso xorriso mtools dosfstools \
        e2fsprogs squashfs-tools openssl arch-install-scripts \
        base-devel sudo rust cargo gtk4 gtk4-layer-shell \
        meson ninja wayland wayland-protocols libxkbcommon wlopm polkit
fi

say "Importando chave CachyOS (ambiente de build)"
# a imagem archlinux não traz chave secreta no keyring — init primeiro
pacman-key --init
if ! pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com 2>/dev/null \
   && ! pacman-key --recv-keys F3B607488DB35A47 2>/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDs/master/cachyos-keyring/cachyos.gpg \
        | pacman-key --add -
fi
pacman-key --lsign-key F3B607488DB35A47

say "Construindo repo local [elite-local] (python-pywal real + stub qt5-virtualkeyboard)"
# O upstream do Archcraft está hoje inbuildável: archcraft-openbox/bspwm
# dependem de python-pywal (que saiu dos repos oficiais) e o
# archcraft-sddm-theme depende de qt5-virtualkeyboard (módulo Qt5 removido
# do Arch; o sddm-git do próprio Archcraft é base Qt6 — dependência
# vestigial). Construímos os dois e servimos num repo file:// local que
# existe no host E dentro do chroot do pacstrap (mesmo caminho).
pacman -S --needed --noconfirm python >/dev/null
mkdir -p /var/cache/elite-local
rm -rf /tmp/elite-src && mkdir -p /tmp/elite-src/python-pywal /tmp/elite-src/qt5-virtualkeyboard /tmp/elite-src/wlrctl

cd /tmp/elite-src/python-pywal
# PIN de commit (R6 da revisão v1.6): a URL branch-driven (refs/heads/master)
# pode mudar sem aviso; o tarball de commit é imutável. Extração vira
# pywal-<sha> → o cd do package() usa glob.
PYWAL_PIN="236aa48e741ff8d65c4c3826db2813bf2ee6f352" # master @ 2026-10-20
curl -fsSL -o pywal-master.tar.gz "https://codeload.github.com/dylanaraps/pywal/tar.gz/${PYWAL_PIN}"
cat > PKGBUILD <<'EOPKGBUILD'
pkgname=python-pywal
pkgver=3.3.1
pkgrel=1
pkgdesc="Generate and change color-schemes on the fly (build local Elite — saiu dos repos oficiais; snapshot do master, py3.13-safe)"
arch=(any)
url="https://github.com/dylanaraps/pywal"
license=(MIT)
depends=(python)
source=("pywal-master.tar.gz")
sha256sums=('SKIP')
package() {
    cd pywal-*/  # barra final: só diretórios (o tarball pywal-master.tar.gz NÃO casa)
    _site=$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')
    install -d "${pkgdir}${_site}"
    cp -a pywal "${pkgdir}${_site}/"
    install -Dm755 /dev/stdin "${pkgdir}/usr/bin/wal" <<'EOS'
#!/usr/bin/python
from pywal.__main__ import main
if __name__ == "__main__":
    main()
EOS
    install -Dm644 LICENSE.md "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}
EOPKGBUILD

cd /tmp/elite-src/qt5-virtualkeyboard
cat > PKGBUILD <<'EOPKGBUILD'
pkgname=qt5-virtualkeyboard
pkgver=5.15.16
pkgrel=1
pkgdesc="Stub Elite: dependência vestigial do archcraft-sddm-theme (sddm-git é Qt6)"
arch=(any)
url="https://github.com/Chrispsz/archcraft-elite"
license=(GPL3)
package() {
    install -Dm644 /dev/null "${pkgdir}/usr/share/doc/${pkgname}/STUB-ELITE.txt"
    printf '%s\n' \
        "Stub criado pelo build da Archcraft Elite." \
        "O archcraft-sddm-theme declara dependência de qt5-virtualkeyboard" \
        "(resquício da era sddm-Qt5); o sddm-git do Archcraft é base Qt6 e usa" \
        "qt6-virtualkeyboard (disponível nos repos). Este stub satisfaz o solver" \
        "de dependências sem qualquer impacto em runtime." \
        > "${pkgdir}/usr/share/doc/${pkgname}/STUB-ELITE.txt"
}
EOPKGBUILD

# ── v2.7.0: WLRCTL (o foco da dock) — FONTE VENDADA, sha256 PINADO ────
#  O wlrctl (wlr-foreign-toplevel — o mecanismo que faz a dock FOCAR a
#  janela do programa que já roda) NUNCA esteve nos repos oficiais do
#  Arch (a build #110 provou: 'target not found: wlrctl' — a suposição
#  errada foi pega pelo gate, como manda a casa). O upstream mora no
#  sourcehut (git.sr.ht/~brocellous/wlrctl), que está fora do ar em
#  502 no dia da cura — então a FONTE INTEIRA vem vendada no repo
#  (vendor/wlrctl-0.2.2.tar.gz): snapshot do mirror público
#  ralphptorres/wlrctl @ commit 5872fa6a42b90f08b89cb61f81a12d3886cf382d
#  (v0.2.2 + 3 commits de texto de --help; version no meson.build =
#  0.2.2, código revisado: foco = alias de activate, app_id casa EXATO
#  por strcmp, e exit 1 quando nenhuma janela casa — o contrato que a
#  dock usa para tentar o próximo candidato). Zero rede no build: o
#  tarball vem do próprio checkout (/work/vendor) e o sha256 abaixo
#  é dos bytes EXATOS do arquivo vendado — mudou o tarball, o makepkg
#  PARA (determinismo — filosofia Elite). Deps de runtime: wayland
#  (já vai na ISO pelo labwc) + libxkbcommon.
cp /work/vendor/wlrctl-0.2.2.tar.gz /tmp/elite-src/wlrctl/
cat > /tmp/elite-src/wlrctl/PKGBUILD <<'EOPKGBUILD'
pkgname=wlrctl
pkgver=0.2.2
pkgrel=1
pkgdesc='Controle de extensões wlroots — foco de janelas via wlr-foreign-toplevel (a dock da Elite foca o programa que já roda)'
arch=(x86_64)
url=https://git.sr.ht/~brocellous/wlrctl
license=(MIT)
depends=(wayland libxkbcommon)
makedepends=(meson wayland-protocols)
source=("wlrctl-0.2.2.tar.gz")
sha256sums=('4022de02f987a659eac3f910c355c8efca60d0b759e3100456e7fb80c530b9ce')
build() {
    cd wlrctl-*/
    meson setup build -Dwerror=false -Dman-pages=disabled
    meson compile -C build
}
package() {
    cd wlrctl-*/
    DESTDIR="$pkgdir" meson install --no-rebuild -C build
    install -Dm644 LICENSE "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}
EOPKGBUILD

# 2.0 Fase 2 — O CRAFT-TOPLEVEL APOSENTOU (o cliente Wayland é o
#  PRÓPRIO elite-daemon agora: zwlr-foreign-toplevel v2 NATIVO no
#  wayland.rs + o snapshot no bus.sock — o C de 3 gerações, o pacote
#  próprio e o hook elite-adopt morreram juntos; os rigs que ainda o
#  têm perdem o pacote na higiene da dose e o binário na ceifa).
# ═════════════════════════════════════════════════════════════════════
# E50 — O PACOTE ÚNICO: elite-system
# O dono: "a atualização do sistema como um todo deveria ser em um só
# pacote — assim fica até mais organizado o repositório e já atualizava
# todo o sistema com um só pacote". A era dos DOIS veículos (elite-craft
# E43 + craft-toplevel E32) se ENCERRA: TODO o código de casa — scripts
# (craft-*, elite-*, exo-open), o daemon de janelas compilado do C
# vendado, as units da cadência — viaja em UM pacote com UM número para
# olhar. O pacman substitui o par legado na transação (replaces/
# conflicts) e o craft-toplevel 1.0-5 é a ponte dos rigs que nunca
# tiveram pacote (o hook dele puxa o elite-system). Na ISO o pacote nasce
# INSTALADO (packages.add); nos rigs, o craft-update v5 o usa como alvo
# explícito ÚNICO. Lei E41: pkgrel sobe NO MESMO commit (o guard cobra).
say "Gerando o PKGBUILD do elite-system (O PACOTE ÚNICO — E50)"
mkdir -p /tmp/elite-src/elite-system/files/usr/local/bin
mkdir -p /tmp/elite-src/elite-system/files/etc/systemd/system
# E132 — O LISTENER CUSTOM APOSENTA (a ordem do dono, dump pós-1.0-78: os
# transient services 'polkit-agent-helper@…' nasciam FAILED e o desafio
# morria — o lxqt-policykit-agent NATIVO, compatível com o polkit 128,
# é o agente da casa eleito no craft-bars; o C vendado não compila nem
# viaja mais — o vendor/elite-polkit-listener.c sai do repo COM VOZ no
# commit, o makedepends polkit sai junto: nada de toolchain que o pacote
# não usa).
# E132 — O WORKSPACE RUST NO PACOTE ÚNICO (a ordem do dono: espremer o
# limão): o daemon nativo compila NO build com makedepends rust+cargo
# EXCLUSIVO — zero toolchain Rust na ISO ou no pacote final (o binário
# compilado é o que viaja; o tar mantém o makepkg feliz: source=() não
# aceita diretórios). O target/ e o .gitignore ficam FORA (o tar é a
# fonte limpa — e o .cargo/ idem: os RUSTFLAGS do build vêm do próprio
# PKGBUILD, a lição E131 do embed-bitcode). O RUST_CRATES é o guard da
# orquestração: o agente-irmão cria o craft-dock-rs CONCORRENTEMENTE —
# presente o crate, ele entra no tar; ausente, o workspace segue só com
# o elite-daemon (a variável é a ponte entre os DOIS agentes).
# 2.0 — o workspace mora em crates/ (a FASE 1 da reconstrução: a fundação
# elite-core e a telemetria craft-dump-rs entram na família — o guard de
# presença continua: crate presente entra no tar, ausente não quebra).
RUST_CRATES="elite-core elite-daemon"
[ -d /work/crates/craft-dock-rs ] && RUST_CRATES="$RUST_CRATES craft-dock-rs"
[ -d /work/crates/craft-bar-rs ] && RUST_CRATES="$RUST_CRATES craft-bar-rs"
[ -d /work/crates/craft-dump-rs ] && RUST_CRATES="$RUST_CRATES craft-dump-rs"
# 2.0 Fase 2 — AS FERRAMENTAS NATIVAS: craft-update/craft-clean/craft-help
# (as janelas GTK4 da diretriz) e o craft-pick (o seletor dmenu nativo —
# o motor craft-menu aposentou com o fuzzel)
[ -d /work/crates/craft-tools ] && RUST_CRATES="$RUST_CRATES craft-tools"
tar -C /work/crates \
    --exclude='target' --exclude='.gitignore' --exclude='.cargo' \
    -czf /tmp/elite-src/elite-system/rust-workspace.tar.gz \
    $RUST_CRATES Cargo.toml Cargo.lock
RUST_TAR_SHA="$(sha256sum /tmp/elite-src/elite-system/rust-workspace.tar.gz | cut -d' ' -f1)"
export RUST_TAR_SHA   # o python do molde lê via os.environ (a sha entra no sha256sums=)
# caminho ABSOLUTO: aqui o CWD é /tmp/elite-src/<pkg> (o cd da seção pywal
# acima) — o relativo nasceria vazio (a lição vai no próprio comentário).
for f in /work/elite/airootfs/usr/local/bin/*; do
    b="${f##*/}"
    # 2.0 — os bins COMPILADOS não vêm do overlay (nascem do cargo no
    # build()): as ferramentas GTK4 (craft-update/craft-clean/craft-help/
    # craft-pick) e a telemetria v2 (craft-dump). O elite-daemon e as
    # superfícies (craft-bar-rs/craft-dock-rs) idem — o molde instala
    # todos da esteira Rust lá embaixo.
    case "$b" in
        craft-update|craft-clean|craft-help|craft-pick|craft-dump|elite-daemon|craft-bar-rs|craft-dock-rs) continue ;;
    esac
    printf '%s\n' "$b"
done > /tmp/elite-src/elite-system/files/MANIFEST
while read -r f; do
    cp -p "/work/elite/airootfs/usr/local/bin/$f" /tmp/elite-src/elite-system/files/usr/local/bin/
done < /tmp/elite-src/elite-system/files/MANIFEST
# FASE 2 — O MODO É CONTEÚDO DUAS VEZES: o bit viaja no git (o guarda do
# modo do Canal recoloca) E é reforçado AQUI no empacotamento — o rig
# recebe 0755 MESMO que um push externo derrube o bit no index (a classe
# craft-apps sem +x do rig do dono morre na fonte e no destino).
chmod 755 /tmp/elite-src/elite-system/files/usr/local/bin/* 2>/dev/null || true
# as units de SISTEMA da casa entram no pacote: sem elas, o rig instalado
# nunca recebe a cadência — a mesma classe da ferida dos bins. Só as
# units de topo da casa (elite-*); wants symlinks e drop-ins de terceiros
# seguem de overlay.
shopt -s nullglob
for u in /work/elite/airootfs/etc/systemd/system/elite-*.service \
         /work/elite/airootfs/etc/systemd/system/elite-*.timer \
         /work/elite/airootfs/etc/systemd/system/scx-lavd.service; do
    cp -p "$u" /tmp/elite-src/elite-system/files/etc/systemd/system/
done
shopt -u nullglob
# 1.0-93 — O SUDOERS LIMPO NO PACOTE (a ordem do dono: os 'insults' do
# sudo saem da casa — Defaults !insults; dono pacman, visudo -c na dose)
mkdir -p /tmp/elite-src/elite-system/files/etc/sudoers.d
cp -p /work/elite/airootfs/etc/sudoers.d/99-elite-clean \
      /tmp/elite-src/elite-system/files/etc/sudoers.d/99-elite-clean
# E63 — A VOLTA DA IMAGEM viaja NO PACOTE: o hook de resume é a rede de
# sistema que religa o display no wake (o monitor 'sem sinal, luz
# vermelha' do dono) — fora do pacote ele NUNCA chegaria ao rig pelo
# canal (system-sleep nunca foi veículo de adoção; este hook NASCE
# empacotado, a lei de um dono por caminho).
# E91 — A LISTA FIXA DEIXOU O SELO FORA DO RIG: o build copiava DOIS hooks
# por nome (resume-display + resume-usb) e o elite-sleep-report (O SELO
# ACPI da E88 — a cura do 'suspendeu e voltou em 7s') ficou na ISO nova e
# NUNCA no pacote: o rig 1.0-33 continuou com o hook VELHO que só nomeava
# suspeitos (o dump 231955 provou no journal — GP12/GP13/SWUS/SWDS
# armadas na porta do sono, sono de 7s/9s). A lição estrutural é a mesma
# da ferida dos bins (E46): LISTA FIXA ENFERRUJA — a cópia passa a ser a
# VARREDURA do diretório (todo elite-* de system-sleep nasce no pacote; o
# pre_install adota o que existia sem dono no rig — o python daqui gera a
# lista de rm a partir do que está em files/, fonte única).
mkdir -p /tmp/elite-src/elite-system/files/usr/lib/systemd/system-sleep
shopt -s nullglob
for h in /work/elite/airootfs/usr/lib/systemd/system-sleep/elite-*; do
    cp -p "$h" /tmp/elite-src/elite-system/files/usr/lib/systemd/system-sleep/
done
shopt -u nullglob
# E73 — o retrato do terminal viaja NO PACOTE (lição E63: fora do pacote
# nunca chega ao rig pelo canal). O craft-hello aponta pra cá; o usuário
# que quiser a própria cara cria ~/.config/fastfetch/config.jsonc e o
# dele VENCE (config de usuário intocado — lei do domínio v3).
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/fastfetch
cp -p /work/elite/airootfs/usr/local/share/elite/fastfetch/config.jsonc \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/fastfetch/config.jsonc
# E91 — A LOCK SKIN NO PACOTE: o hyprlock.conf v3 (E88) morava só no skel
# — home VIVO nunca o recebia (o dono: "o bloqueio de tela não mudou
# nada"). A pele-mestra viaja AQUI e o craft-rice a entrega ao home com a
# gramática do rice (marcador/fóssil/personalizado — ver craft-rice E91).
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/hyprlock
cp -p /work/elite/airootfs/etc/skel/.config/hypr/hyprlock.conf \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/hyprlock/hyprlock.conf
# BLOCO 4 (1.0-98) — A PELE DO GREETER NO PACOTE: o theme.conf da casa
# (a paleta oficial no tema archcraft do SDDM) viaja como mestre em
# /usr/local/share/elite/sddm/ e o elite-post-upgrade o entrega ao rig
# vivo em /usr/share/sddm/themes/archcraft/theme.conf (cmp divergente =
# renova com .bak; igual = no-op — E150). O kde_settings.conf do cursor
# Bibata viaja JUNTO (a dose entrega em /etc/sddm.conf.d preservando o
# Autologin do dono). Na ISO a mesma fonte chega pelo overlay do airootfs
# (usr/share/sddm/themes/archcraft/theme.conf) — UMA fonte, dois
# veículos, zero drift.
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/sddm
cp -p /work/elite/airootfs/usr/share/sddm/themes/archcraft/theme.conf \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/sddm/theme.conf
cp -p /work/elite/airootfs/etc/sddm.conf.d/kde_settings.conf \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/sddm/kde_settings.conf
# E151 — O MESTRE DO GREETER WAYLAND VIAJA JUNTO (o drop-in
# DisplayServer=wayland + CompositorCommand=labwc — o post-upgrade o
# entrega em /etc/sddm.conf.d SÓ com o labwc em disco; sem ele o SDDM
# volta ao X11 de sempre — a rede anti-tela-preta é a lei)
cp -p /work/elite/airootfs/etc/sddm.conf.d/elite_wayland.conf \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/sddm/elite_wayland.conf
# E150 — O TEMA GRUB DA CASA NO PACOTE (a pele roxa no boot: o wallpaper
# escuro/roxo + a barra de seleção #a855f7): o mestre mora em
# /usr/local/share/elite/grub/ e o elite-post-upgrade entrega ao rig
# vivo em /usr/share/grub/themes/archcraft E /boot/grub/themes/archcraft
# (+ GRUB_THEME/GRUB_DISTRIBUTOR no /etc/default/grub, com o mkconfig
# guardado pela lei E130). O WALLPAPER bebe do skel (a MESMA fonte
# binária da sessão — UMA fonte, zero binário novo no git) e a BARRA
# viaja decodificada do select_bar.png.b64 do overlay (o git da casa é
# TEXT-ONLY; o base64 -d do coreutils materializa no staging).
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/grub
cp -p /work/elite/airootfs/usr/share/grub/themes/archcraft/theme.txt \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/grub/theme.txt
cp -p /work/elite/airootfs/etc/skel/.config/labwc/wallpaper.png \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/grub/wallpaper.png
base64 -d /work/elite/airootfs/usr/share/grub/themes/archcraft/select_bar.png.b64 \
      > /tmp/elite-src/elite-system/files/usr/local/share/elite/grub/select_bar.png
# E103 — AS PELES rc.xml + swayosd NO PACOTE (a gramática E91 generalizada):
# o rc.xml do rig (binds E103 do OSD) e o config.toml do swayosd (a barra
# acima da dock) alcançam homes vivos via craft-rice (marcador/fóssil) —
# a mesma via da lock skin (E91).
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/labwc
cp -p /work/elite/airootfs/etc/skel/.config/labwc/rc.xml \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/labwc/rc.xml
# E104 — A PELE DO MENU NO PACOTE (a gramática E91 na 3ª pele): o menu v2
# (rótulos sem nome de pacote + a porta do desafixar) alcança homes VIVOS
# via craft-rice (fóssil = a velha da casa → renova com backup;
# personalizado → intocável). O menu do rig deixa de ser fóssil da ISO —
# o caminho é NOVO (nenhum rig tem /usr/local/share/elite/labwc/menu.xml
# sem dono — sem dança de pre_install).
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/labwc
cp -p /work/elite/airootfs/etc/skel/.config/labwc/menu.xml \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/labwc/menu.xml
# E130 — AS PELES DO TEMA E DO GTK NO PACOTE (a ordem do dono 2026-11-21):
# o themerc-override (destaque mauve) e os settings.ini GTK (Papirus-Dark)
# alcançam homes VIVOS via craft-rice (marcador/fóssil — a gramática E91)
# e o post_upgrade (o elite-post-upgrade chama o rice a cada dose). O rig
# da ISO velha sai do tema de 3/nov e o GTK ganha família de ícones.
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/labwc
cp -p /work/elite/airootfs/etc/skel/.config/labwc/themerc-override \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/labwc/themerc-override
# E146 — O AUTOSTART-MESTRE NO PACOTE (a ferida do rig 1.0-94: o sed cego
# de um agente FORA do repo injetou `elite-daemon session &` 8× no meio
# de comentários do autostart do home; o skel é veículo da ISO e NUNCA
# alcança o rig instalado — a cura não tinha fonte de verdade no disco).
# O mestre mora agora ao lado dos irmãos XML e o elite-heal-sessao o usa
# para RECONSTRUIR o arquivo corrompido (backup único, sh -n de guarda).
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/labwc
cp -p /work/elite/airootfs/etc/skel/.config/labwc/autostart \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/labwc/autostart
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/gtk-3.0
cp -p /work/elite/airootfs/etc/skel/.config/gtk-3.0/settings.ini \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/gtk-3.0/settings.ini
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/gtk-4.0
cp -p /work/elite/airootfs/etc/skel/.config/gtk-4.0/settings.ini \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/gtk-4.0/settings.ini
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/swayosd
cp -p /work/elite/airootfs/etc/skel/.config/swayosd/config.toml \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/swayosd/config.toml
# E126 — o CSS do OSD embarca junto (a pele gráfica do popup de volume:
# escada AMOLED + acento mauve — o craft-rice entrega os DOIS arquivos
# como UMA pele; o swayosd lê style.css do dir de config automaticamente)
cp -p /work/elite/airootfs/etc/skel/.config/swayosd/style.css \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/swayosd/style.css
# E126 — A REGRA DO DESPERTAR EMBARCA NO PACOTE (o buraco de entrega que o
# dump 173137 fotografou: a regra E122 morava só no airootfs da ISO — os
# rigs instalados seguiam com o fóssil E24 de 3/nov desarmando TODO o USB
# a cada coldplug, e a unit elite-wake-guard.service chegava SEM o symlink
# de wants: nunca rodou, o teclado do dono nunca acordou a máquina). Viaja
# como /usr/lib/udev/rules.d/91-* — nome 91 vence o fóssil /etc/90-* do
# rig pela ordem lexical do udev (nomes diferentes SOMAM, não substituem)
# e o elite-post-transaction aposenta o fóssil com voz na 1ª dose.
mkdir -p /tmp/elite-src/elite-system/files/usr/lib/udev/rules.d
# E137 — A FONTE ÚNICA: a regra mora no airootfs já no caminho CANÔNICO
# /usr/lib/udev/rules.d/91-* (a cópia /etc/90- do airootfs morreu — era
# DUPLICATA na ISO: a 90 do overlay E a 91 do pacote rodavam JUNTAS no
# mesmo evento; os fósseis /etc/90 dos rigs seguem aposentados pelo
# post-transaction como sempre)
cp -p /work/elite/airootfs/usr/lib/udev/rules.d/91-elite-wake-guard.rules \
      /tmp/elite-src/elite-system/files/usr/lib/udev/rules.d/91-elite-wake-guard.rules
# E151 — A REGRA DO AUTOMOUNT EMBARCA (o substituto do udiskie: a regra
# agenda a unit elite-automount@.service no evento do plug — a unit viaja
# pelo varredura elite-*.service do staging de cima; o helper viaja no
# MANIFEST dos bins)
mkdir -p /tmp/elite-src/elite-system/files/usr/lib/udev/rules.d
cp -p /work/elite/airootfs/usr/lib/udev/rules.d/91-elite-automount.rules \
      /tmp/elite-src/elite-system/files/usr/lib/udev/rules.d/91-elite-automount.rules
# E151 — A REVISÃO DE I/O EMBARCA (o escalonador por classe de disco:
# NVMe none · SSD SATA mq-deadline · HDD intocado)
mkdir -p /tmp/elite-src/elite-system/files/etc/udev/rules.d
cp -p /work/elite/airootfs/etc/udev/rules.d/99-elite-io.rules \
      /tmp/elite-src/elite-system/files/etc/udev/rules.d/99-elite-io.rules
# E128 — A AUTORIZAÇÃO DA CASA NO PACOTE: a regra 50-elite-wheel.rules
# (pkexec de craft-clean / elite-update / craft-update SEM senha para
# usuário LOCAL ATIVO do grupo wheel — narrow por desenho, sem wildcard)
# viaja NO elite-system: rig que só chega pelo pacman recebe a regra com
# dono — a dança E43 de adoção (o pre_install remove o caminho sem dono
# antes da extração).
mkdir -p /tmp/elite-src/elite-system/files/etc/polkit-1/rules.d
cp -p /work/elite/airootfs/etc/polkit-1/rules.d/50-elite-wheel.rules \
      /tmp/elite-src/elite-system/files/etc/polkit-1/rules.d/50-elite-wheel.rules
# E129 — O TEMA QT VESTE O RICE: o qt6ct.conf da casa viaja no pacote
# (icon_theme=Papirus-Dark — o MESMO dos settings.ini GTK) e o
# elite-post-upgrade o entrega aos homes vivos SE AUSENTE (personalizado
# do dono é intocável — a gramática E101). O skel da ISO nasce com ele.
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/qt6ct
cp -p /work/elite/airootfs/usr/local/share/elite/qt6ct/qt6ct.conf \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/qt6ct/qt6ct.conf
# E136 — O KERNEL MODERNO DA PARTE 2/2 NO PACOTE: os confs da casa viajam
# COM DONO (a lição E63: fora do pacote nunca chega ao rig pelo canal) —
# o sysctl consolidado (99-elite-performance.conf; o post_upgrade aposenta
# os fósseis 99-elite.conf/99-elite-net.conf com voz), os módulos do boot
# (ntsync + sensores), a regra udev do /dev/ntsync (0666), o tmpfiles do
# MGLRU, o /etc/default/scx (scx_lavd) e a drop-in da Condition (kernel
# sem sched_ext = unit PULADA, nunca FAILED).
# E138 — O ESTÁGIO NÃO É PACOTE: a E136/E137 staged esta família em
# files/etc/… e o MOLDE nunca a installou — o rig 1.0-85 provou no dump
# v2.13 (sem 99-elite-performance.conf, sem /etc/default/scx, sem regra
# zram: o canal entregava versões com a promessa empacotada no ar). O
# install mora AGORA no package() do molde (mesma fonte única files/).
mkdir -p /tmp/elite-src/elite-system/files/etc/sysctl.d \
         /tmp/elite-src/elite-system/files/etc/modules-load.d \
         /tmp/elite-src/elite-system/files/etc/udev/rules.d \
         /tmp/elite-src/elite-system/files/etc/tmpfiles.d \
         /tmp/elite-src/elite-system/files/etc/default \
         /tmp/elite-src/elite-system/files/etc/systemd/system/scx_loader.service.d
cp -p /work/elite/airootfs/etc/sysctl.d/99-elite-performance.conf \
      /tmp/elite-src/elite-system/files/etc/sysctl.d/99-elite-performance.conf
# E137→E138 — A REGRA DO SWAPPINESS SEM DRIFT NO PACOTE: a
# 99-elite-zram.rules (a /etc, COM DONO — o pacman a atualiza em toda
# dose; o nome 99 é A ORDEM do dono: vence o 30-zram/70-cachyos-settings
# do vendor NO MESMO evento do zram0 por ordem lexical, em qualquer
# versão do cachyos-settings). O post-transaction faz o udevd relê-la
# na hora — a dose vale sem reboot.
cp -p /work/elite/airootfs/etc/udev/rules.d/99-elite-zram.rules \
      /tmp/elite-src/elite-system/files/etc/udev/rules.d/99-elite-zram.rules
cp -p /work/elite/airootfs/etc/modules-load.d/elite-ntsync.conf \
      /tmp/elite-src/elite-system/files/etc/modules-load.d/elite-ntsync.conf
cp -p /work/elite/airootfs/etc/modules-load.d/elite-sensors.conf \
      /tmp/elite-src/elite-system/files/etc/modules-load.d/elite-sensors.conf
cp -p /work/elite/airootfs/etc/udev/rules.d/60-ntsync.rules \
      /tmp/elite-src/elite-system/files/etc/udev/rules.d/60-ntsync.rules
cp -p /work/elite/airootfs/etc/tmpfiles.d/elite-mglru.conf \
      /tmp/elite-src/elite-system/files/etc/tmpfiles.d/elite-mglru.conf
cp -p /work/elite/airootfs/etc/default/scx \
      /tmp/elite-src/elite-system/files/etc/default/scx
cp -p /work/elite/airootfs/etc/systemd/system/scx_loader.service.d/elite.conf \
      /tmp/elite-src/elite-system/files/etc/systemd/system/scx_loader.service.d/elite.conf
# E136 — OS MESTRES DO MANGOHUD NO PACOTE (os 3 perfis zero-config da
# PARTE 2/2): /usr/local/share/elite/mangohud/*.conf — o elite-mangohud
# troca o symlink do home para cá (o toggle sem editor; o skel nasce com
# o balanceado de fábrica).
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/mangohud
cp -p /work/elite/airootfs/usr/local/share/elite/mangohud/minimal.conf \
      /work/elite/airootfs/usr/local/share/elite/mangohud/balanceado.conf \
      /work/elite/airootfs/usr/local/share/elite/mangohud/diagnostico.conf \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/mangohud/
# E132 — O CONF DO DAEMON NO PACOTE: o elite-daemon supervise lê
# /usr/local/share/elite/daemon.conf (`nome::comando` por linha). O
# arquivo viaja COM OS DEFAULTS COMENTADOS — os builtins da casa valem
# quando ele não existe; presente, o dono edita à vontade (linhas '#'
# e vazias são ignoradas pelo daemon). Mesma dança da família E91: o
# pre_install adota a via sem dono antes da extração.
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite
cat > /tmp/elite-src/elite-system/files/usr/local/share/elite/daemon.conf <<'EODCONF'
# ── ELITE (E132→E135): os residentes do elite-daemon supervise ──────
# Um residente por linha: `nome::comando` ou `nome::bus::comando` (a
# gramática E135 — o nome no session bus que prova a posse: se o nome
# TEM dono, a vaga é ADOTADA, nunca relançada por cima — o gate que
# matou o loop de 809 relanças do swaync no dump 101339). Edite à
# vontade; linhas '#' e vazias são ignoradas. SEM este arquivo os
# defaults da casa valem (swaync com gate de bus, swayosd,
# craft-audio-route — o udiskie SAIU da fila na E151: o automount é a
# regra udev 91-elite-automount, oneshot por evento, zero daemon). Cada
# vaga também trava em flock exclusivo no
# $XDG_RUNTIME_DIR/elite/resident-<nome>.lock — a posse dupla.
#swaync::org.erikreider.swaync.cc::swaync
#swayosd::swayosd-server
#craft-audio-route::craft-audio-route
EODCONF
# E114 — O CONFO DO NAVEGADOR NO PACOTE: o brave-flags.conf era SKEL — rig
# vivo nunca recebia (a cura do vídeo branco do YouTube — o réu Vulkan da
# era v1.1 fora — morria sem veículo). Viaja em /usr/local/share/elite/
# chromium-flags/ e o elite-post-transaction sincroniza ao home (dono do
# arquivo = o usuário; idempotente, com linha no papel).
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/chromium-flags
cp -p /work/elite/airootfs/etc/skel/.config/brave-flags.conf \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/chromium-flags/brave-flags.conf
# E134 — O CODE-FLAGS TAMBÉM VIAJA (a ordem do dono 1.0-81: --password-store=
# basic nos apps Chromium/Electron — Brave já tinha o flag da E115; o
# VSCodium ganha o SEU conf de pacote e o elite-post-transaction sincroniza
# ao home dos rigs vivos, a mesma escola do brave-flags).
cp -p /work/elite/airootfs/etc/skel/.config/code-flags.conf \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/chromium-flags/code-flags.conf
# E140 — O OVERRIDE DO COOLERCONTROL NO PACOTE (a ordem do dono, dossiê
# 1.0-88: o CoolerControl de qt6-webengine abre em TELA BRANCA sob
# Wayland/amdgpu sem o --disable-gpu — o override mora em /usr/local/
# share/applications, que VENCE o /usr/share do pacote sem tocar no
# arquivo do dono do pacote; o nwg-drawer indexa ESTE. As SKINS da
# topbar morreram com o waybar: a top bar da casa é o craft-bar-rs — a
# pele mora NO binário (DEFAULT_CSS) e o override do dono é arquivo
# livre em ~/.config/elite/bar.css, sem pipeline de adoção).
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/applications
cp -p /work/elite/airootfs/usr/local/share/applications/org.coolercontrol.CoolerControl.desktop \
      /tmp/elite-src/elite-system/files/usr/local/share/applications/org.coolercontrol.CoolerControl.desktop
# E103 — OS APPS PADRÃO COMO VARIÁVEIS (a abstração XDG): o profile.d da
# casa crava TERMINAL/FILEMANAGER/EDITOR/VISUAL/BROWSER com os defaults —
# o usuário vence exportando (a variável PRESENTE não é tocada).
mkdir -p /tmp/elite-src/elite-system/files/etc/profile.d
cp -p /work/elite/airootfs/etc/profile.d/10-elite-defaults.sh \
      /tmp/elite-src/elite-system/files/etc/profile.d/10-elite-defaults.sh
# E103 — O MUSCULO DO MODO DE JOGO (gamemode.ini da casa): governor
# performance + GPU high + hooks do craft-game. O gamemode do Arch NÃO
# entrega /etc/gamemode.ini (só o example) — o caminho é dono único do
# pacote (sem conflito); o rig com arquivo sem dono adota no pre_install.
cp -p /work/elite/airootfs/etc/gamemode.ini \
      /tmp/elite-src/elite-system/files/etc/gamemode.ini
# E90 — O MAPA VIAJA NO PACOTE: a doc completa (SCRIPTS.md — a linha de
# cada peça) morava só no repo; o craft-help aponta para ela e o dono
# ganha o mapa DENTRO do sistema (a fonte única continua sendo o repo —
# o build injeta, o airootfs em pé não duplica).
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/docs
cp -p /work/docs/SCRIPTS.md \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/docs/SCRIPTS.md
# E95 — O OVERRIDE DO GPARTED NO PACOTE: a mesma desktop-id na FRENTE do
# XDG_DATA_DIRS (o environment da sessão labwc põe /usr/local/share
# primeiro) — dock, gaveta e fuzzel resolvem gparted.desktop para AQUI,
# e o Exec veste o root com a sessão (elite-gparted: pkexec env +
# WAYLAND_DISPLAY — o pkexec nu despe o ambiente e a GDK root morre rc=1
# com a senha JÁ aceita, a prova do dump 225119). O upstream em
# /usr/share/applications fica intocado (o override é a nossa fronteira;
# desinstalar o elite-system devolve o comportamento cru do Arch).
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/applications
# E98 — o trilho único da E95 vira VARREDURA: todo .desktop de override
# embarca sozinho (gparted E95 · octopi-notifier/octopi-repoeditor/qt6ct/
# nwg-look E98) — override novo é ARQUIVO NOVO NO DIR, zero cirurgia aqui.
# E106 — O FANTASMA NÃO VIAJA MAIS (o dump 20261112 + o journal do drawer:
# "Cannot load icon 'calamares' for 'Install Archcraft'" — o calamares.
# desktop da ISO embarcava NO PACOTE, e a dose com --overwrite
# /usr/local/share/applications/* REINSTALAVA o instalador morto em todo
# rig instalado — o elite-sweep o remove 1× no firstboot e a dose o
# RESSUSCITAVA na primeira dose seguinte; a gaveta indexava um instalador
# que não existe (sem ícone, sem função — o 'Starchcraft' que o dono viu
# nascer do nada). O abif (o irmão de ferramenta de gravação) sai junto:
# são FERRAMENTAS DA SESSÃO LIVE, não do instalado).
for dsk in /work/elite/airootfs/usr/local/share/applications/*.desktop; do
    case "$(basename "$dsk")" in
        calamares.desktop|abif.desktop) continue ;;
    esac
    cp -p "$dsk" /tmp/elite-src/elite-system/files/usr/local/share/applications/
done
# E75 — O HOOK DA CASA NO PACMAN (a auditoria do dono: 'estruturar hooks
# nativos do pacman para disparar checagens de hardware... após qualquer
# pacman -Syu'). O gap provado no papel: a pedagogia de reboot do kernel
# só existia na porta do craft-update — um pacman -Syu cru trocava o
# kernel em silêncio. O bin elite-post-transaction viaja pelo MANIFEST
# (é um bin do airootfs); ESTE .hook é quem o convoca no fim de TODA
# transação (mesma escola do elite-adopt.hook: heredoc aqui, dono ÚNICO
# no pacote — nunca dois por caminho).
cat > /tmp/elite-src/elite-system/elite-post-transaction.hook <<'EOPT'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = *

[Action]
Description = Elite: pós-transação (aviso de kernel novo + vigília do wake-guard E24)
When = PostTransaction
Exec = /usr/local/bin/elite-post-transaction
EOPT
# E97 — O HOOK DO FLATHUB: o remote nasce com o pacote (mesma escola do
# elite-post-transaction — Target estreito: dispara SÓ quando o flatpak
# entra na transação; na build da ISO o pacstrap o convoca NO CHROOT e a
# ISO nasce com o remote; no rig, o craft-update adota o flatpak e o hook
# dispara no mesmo gesto — dois mundos, um arquivo).
cat > /tmp/elite-src/elite-system/elite-flathub.hook <<'EOFH'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = flatpak

[Action]
Description = Elite: remote Flathub no flatpak (idempotente)
When = PostTransaction
Exec = /usr/local/bin/elite-flathub
EOFH
python3 - /tmp/elite-src/elite-system <<'PYE50'
import os, sys, pathlib
# E132 — a sha do tar Rust viaja pelo ENV (a variável BASH não entra no
# escopo do python; o export lá atrás no staging é a ponte — sem ela o
# molde morre em KeyError, a build inteira depende do par)
rust_sha = os.environ["RUST_TAR_SHA"]
d = pathlib.Path(sys.argv[1])
files = (d / 'files/MANIFEST').read_text().split()
units = sorted(p.name for p in (d / 'files/etc/systemd/system').iterdir())
# E63 — os hooks de system-sleep que o pacote entrega (fonte única: o
# que está em files/, o mesmo padrão das units)
hooks = sorted(p.name for p in (d / 'files/usr/lib/systemd/system-sleep').iterdir())
names = chr(10).join(f'        "{f}" \\' for f in files)   # cada item com \ de continuação — a lista do for NÃO aceita quebra simples
unames = chr(10).join(f'        "/etc/systemd/system/{u}" \\' for u in units)
unit_loop = f"""    for f in \\
{unames}
    ; do
        [ -e "$f" ] && rm -f "$f"
    done
""" if units else ""
unit_install = f"""    install -d "${{pkgdir}}/etc/systemd/system"
    cp -a "${{startdir}}/files/etc/systemd/system/." "${{pkgdir}}/etc/systemd/system/"
""" if units else ""
hnames = chr(10).join(f'        "/usr/lib/systemd/system-sleep/{h}" \\' for h in hooks)
hook_rm = f"""    for f in \\
{hnames}
    ; do
        [ -e "$f" ] && rm -f "$f"
    done
""" if hooks else ""
hook_install = f"""    install -d "${{pkgdir}}/usr/lib/systemd/system-sleep"
    cp -a "${{startdir}}/files/usr/lib/systemd/system-sleep/." "${{pkgdir}}/usr/lib/systemd/system-sleep/"
""" if hooks else ""
# E73 — o config do retrato (instalação + a remoção da via sem dono da
# ISO no pre_install — a mesma dança dos bins desde a adoção E43)
ff_install = '    install -d "${pkgdir}/usr/local/share/elite/fastfetch"\n    install -m644 "${startdir}/files/usr/local/share/elite/fastfetch/config.jsonc" "${pkgdir}/usr/local/share/elite/fastfetch/config.jsonc"\n'
ff_rm = '    [ -e "/usr/local/share/elite/fastfetch/config.jsonc" ] && rm -f "/usr/local/share/elite/fastfetch/config.jsonc"\n'
# E91 — a lock skin (mesma dança do fastfetch: o rig da ISO velha pode ter
# o caminho sem dono — o pre_install adota antes da extração)
lock_install = '    install -d "${pkgdir}/usr/local/share/elite/hyprlock"\n    install -m644 "${startdir}/files/usr/local/share/elite/hyprlock/hyprlock.conf" "${pkgdir}/usr/local/share/elite/hyprlock/hyprlock.conf"\n'
lock_rm = '    [ -e "/usr/local/share/elite/hyprlock/hyprlock.conf" ] && rm -f "/usr/local/share/elite/hyprlock/hyprlock.conf"\n'
# BLOCO 4 (1.0-98) — a pele do greeter (mesma dança da família E91;
# caminho novo = criação limpa, sem dança de pre_install)
sddm_install = '    install -d "${pkgdir}/usr/local/share/elite/sddm"\n    install -m644 "${startdir}/files/usr/local/share/elite/sddm/theme.conf" "${pkgdir}/usr/local/share/elite/sddm/theme.conf"\n    install -m644 "${startdir}/files/usr/local/share/elite/sddm/kde_settings.conf" "${pkgdir}/usr/local/share/elite/sddm/kde_settings.conf"\n    install -m644 "${startdir}/files/usr/local/share/elite/sddm/elite_wayland.conf" "${pkgdir}/usr/local/share/elite/sddm/elite_wayland.conf"\n'
sddm_rm = '    [ -e "/usr/local/share/elite/sddm/theme.conf" ] && rm -f "/usr/local/share/elite/sddm/theme.conf"\n    [ -e "/usr/local/share/elite/sddm/kde_settings.conf" ] && rm -f "/usr/local/share/elite/sddm/kde_settings.conf"\n    [ -e "/usr/local/share/elite/sddm/elite_wayland.conf" ] && rm -f "/usr/local/share/elite/sddm/elite_wayland.conf"\n'
# E150 — o tema GRUB da casa (mesma dança da família E91: mestre no
# pacote, o post-upgrade entrega ao rig)
grub_install = '    install -d "${pkgdir}/usr/local/share/elite/grub"\n    install -m644 "${startdir}/files/usr/local/share/elite/grub/theme.txt" "${pkgdir}/usr/local/share/elite/grub/theme.txt"\n    install -m644 "${startdir}/files/usr/local/share/elite/grub/wallpaper.png" "${pkgdir}/usr/local/share/elite/grub/wallpaper.png"\n    install -m644 "${startdir}/files/usr/local/share/elite/grub/select_bar.png" "${pkgdir}/usr/local/share/elite/grub/select_bar.png"\n'
grub_rm = '    [ -e "/usr/local/share/elite/grub/theme.txt" ] && rm -f "/usr/local/share/elite/grub/theme.txt"\n    [ -e "/usr/local/share/elite/grub/wallpaper.png" ] && rm -f "/usr/local/share/elite/grub/wallpaper.png"\n    [ -e "/usr/local/share/elite/grub/select_bar.png" ] && rm -f "/usr/local/share/elite/grub/select_bar.png"\n'
# E103 — as peles rc.xml + swayosd (mesma dança da adoção E43)
rc_install = '    install -d "${pkgdir}/usr/local/share/elite/labwc"\n    install -m644 "${startdir}/files/usr/local/share/elite/labwc/rc.xml" "${pkgdir}/usr/local/share/elite/labwc/rc.xml"\n'
rc_rm = '    [ -e "/usr/local/share/elite/labwc/rc.xml" ] && rm -f "/usr/local/share/elite/labwc/rc.xml"\n'
osd_install = '    install -d "${pkgdir}/usr/local/share/elite/swayosd"\n    install -m644 "${startdir}/files/usr/local/share/elite/swayosd/config.toml" "${pkgdir}/usr/local/share/elite/swayosd/config.toml"\n    install -m644 "${startdir}/files/usr/local/share/elite/swayosd/style.css" "${pkgdir}/usr/local/share/elite/swayosd/style.css"\n'
osd_rm = '    [ -e "/usr/local/share/elite/swayosd/config.toml" ] && rm -f "/usr/local/share/elite/swayosd/config.toml"\n    [ -e "/usr/local/share/elite/swayosd/style.css" ] && rm -f "/usr/local/share/elite/swayosd/style.css"\n'
# E104 — a pele do menu (mesma dança da família E91)
menu_install = '    install -d "${pkgdir}/usr/local/share/elite/labwc"\n    install -m644 "${startdir}/files/usr/local/share/elite/labwc/menu.xml" "${pkgdir}/usr/local/share/elite/labwc/menu.xml"\n'
menu_rm = '    [ -e "/usr/local/share/elite/labwc/menu.xml" ] && rm -f "/usr/local/share/elite/labwc/menu.xml"\n'
# E114/E117 — O CONFO DO NAVEGADOR EMBARCA DE VERDADE: o staging existia
# desde a E114 e o molde NUNCA o installou (o réu-mãe do dump 163548 —
# o hook sincronizador fazia [ -r $SRC_FLAGS ] falha silenciosa e o rig
# do dono vivia sem --password-store=basic e sem os flags Ozone/GPU) —
# a mesma dança da família E91 (caminho novo = criação limpa).
flags_install = '    install -d "${pkgdir}/usr/local/share/elite/chromium-flags"\n    install -m644 "${startdir}/files/usr/local/share/elite/chromium-flags/brave-flags.conf" "${pkgdir}/usr/local/share/elite/chromium-flags/brave-flags.conf"\n    install -m644 "${startdir}/files/usr/local/share/elite/chromium-flags/code-flags.conf" "${pkgdir}/usr/local/share/elite/chromium-flags/code-flags.conf"\n'
flags_rm = '    [ -e "/usr/local/share/elite/chromium-flags/brave-flags.conf" ] && rm -f "/usr/local/share/elite/chromium-flags/brave-flags.conf"\n    [ -e "/usr/local/share/elite/chromium-flags/code-flags.conf" ] && rm -f "/usr/local/share/elite/chromium-flags/code-flags.conf"\n'
# E115/E117 — AS SKINS DA TOPBAR EMBARCAM DE VERDADE (o mesmo réu-mãe:
# staged e nunca installado — o craft-rice das skins lia um caminho que
# o pacote nunca entregou ao rig vivo).
# E140 — O OVERRIDE DO COOLERCONTROL (o .desktop da casa com o
# --disable-gpu que cura a tela branca do qt6-webengine no Wayland)
apps_install = '    install -d "${pkgdir}/usr/local/share/applications"\n    install -m644 "${startdir}/files/usr/local/share/applications/org.coolercontrol.CoolerControl.desktop" "${pkgdir}/usr/local/share/applications/org.coolercontrol.CoolerControl.desktop"\n'
apps_rm = '    [ -e "/usr/local/share/applications/org.coolercontrol.CoolerControl.desktop" ] && rm -f "/usr/local/share/applications/org.coolercontrol.CoolerControl.desktop"\n'
# E103 — os defaults XDG (arquivo de pacote: dono único, sem dança de adoção)
pd_install = '    install -d "${pkgdir}/etc/profile.d"\n    install -m644 "${startdir}/files/etc/profile.d/10-elite-defaults.sh" "${pkgdir}/etc/profile.d/10-elite-defaults.sh"\n'
# E103 — o gamemode.ini (adoção: o rig com o arquivo SEM dono o perde no
# pre_install e o pacote o entrega com dono — a dança E43 da casa)
gm_install = '    install -Dm644 "${startdir}/files/etc/gamemode.ini" "${pkgdir}/etc/gamemode.ini"\n'
gm_rm = '    [ -e "/etc/gamemode.ini" ] && ! pacman -Qo "/etc/gamemode.ini" >/dev/null 2>&1 && rm -f "/etc/gamemode.ini"\n'
pd_rm = ''
# E90 — o mapa dos comandos (SCRIPTS.md no pacote — mesma dança)
doc_install = '    install -d "${pkgdir}/usr/local/share/elite/docs"\n    install -m644 "${startdir}/files/usr/local/share/elite/docs/SCRIPTS.md" "${pkgdir}/usr/local/share/elite/docs/SCRIPTS.md"\n'
doc_rm = '    [ -e "/usr/local/share/elite/docs/SCRIPTS.md" ] && rm -f "/usr/local/share/elite/docs/SCRIPTS.md"\n'
# E95 — o override do gparted (mesma dança: o rig da ISO velha pode ter
# um gparted.desktop sem dono por lá — o pre_install adota antes da
# extração; caminho NOVO em rig comum = criação limpa).
# E98 — O TRILHO VIROU VARREDURA: TODO .desktop em files/usr/local/share/
# applications/ embarca sozinho (gparted E95 + octopi-notifier,
# octopi-repoeditor, qt6ct, nwg-look E98) com a sua linha de install E a
# sua linha de adoção no pre_install — a lição E95 generalizada: override
# novo é arquivo novo no dir, zero cirurgia neste PKGBUILD.
ovr = sorted(p.name for p in (d / 'files/usr/local/share/applications').glob('*.desktop'))
gp_install = '    install -d "${pkgdir}/usr/local/share/applications"\n'
gp_rm = ''
for o in ovr:
    gp_install += f'    install -m644 "${{startdir}}/files/usr/local/share/applications/{o}" "${{pkgdir}}/usr/local/share/applications/{o}"\n'
    gp_rm += f'    [ -e "/usr/local/share/applications/{o}" ] && rm -f "/usr/local/share/applications/{o}"\n'
# E75 — o hook libalpm da casa (dono ÚNICO no pacote; pacman remove sozinho
# na desinstalação — arquivo pertence ao pacote, sem dança de adoção)
pt_install = '    install -Dm644 "${startdir}/elite-post-transaction.hook" "${pkgdir}/usr/share/libalpm/hooks/elite-post-transaction.hook"\n'
# 1.0-93 — o sudoers da casa (dono pacman; arquivo de pacote — sem dança
# de adoção, o caminho /etc/sudoers.d/99-elite-clean é NOVO nos rigs)
# 1.0-94 — o DIR VESTE 750 (o rig da 1.0-93: o install -d nascia 755 e o
# pacman avisava "directory permissions differ from filesystem" no
# upgrade e na instalação do iwgtk — o /etc/sudoers.d do Arch é 750;
# casar com o distro é calar o aviso SEM frouxar a permissão)
sudoers_install = '    install -dm750 "${pkgdir}/etc/sudoers.d"\n    install -m440 "${startdir}/files/etc/sudoers.d/99-elite-clean" "${pkgdir}/etc/sudoers.d/99-elite-clean"\n'
sudoers_rm = '    [ -e "/etc/sudoers.d/99-elite-clean" ] && rm -f "/etc/sudoers.d/99-elite-clean"\n'
# E97 — o hook do flathub (mesma escola do post-transaction: heredoc no
# build, dono ÚNICO no pacote — o libalpm remove sozinho na saída)
ef_install = '    install -Dm644 "${startdir}/elite-flathub.hook" "${pkgdir}/usr/share/libalpm/hooks/elite-flathub.hook"\n'
# E126 — a regra udev do despertar (mesma escola das peles: staging acima,
# install aqui; caminho NOVO em rig comum = criação limpa, sem dança de
# adoção — o fóssil /etc/90-* do rig é aposentado pelo elite-post-transaction
# com voz, nunca sobrescrito às cegas pelo pacman)
udev_install = '    install -d "${pkgdir}/usr/lib/udev/rules.d"\n    install -m644 "${startdir}/files/usr/lib/udev/rules.d/91-elite-wake-guard.rules" "${pkgdir}/usr/lib/udev/rules.d/91-elite-wake-guard.rules"\n    install -m644 "${startdir}/files/usr/lib/udev/rules.d/91-elite-automount.rules" "${pkgdir}/usr/lib/udev/rules.d/91-elite-automount.rules"\n    install -m644 "${startdir}/files/etc/udev/rules.d/99-elite-io.rules" "${pkgdir}/etc/udev/rules.d/99-elite-io.rules"\n'
# E128 — a regra polkit da casa (mesma dança da família E91/E98)
# 1.0-94 — o DIR VESTE 750 (idem sudoers: o /etc/polkit-1/rules.d do
# polkit é 750 no Arch — o aviso de permissão do pacman cala na fonte)
pk_install = '    install -dm750 "${pkgdir}/etc/polkit-1/rules.d"\n    install -m644 "${startdir}/files/etc/polkit-1/rules.d/50-elite-wheel.rules" "${pkgdir}/etc/polkit-1/rules.d/50-elite-wheel.rules"\n'
pk_rm = '    [ -e "/etc/polkit-1/rules.d/50-elite-wheel.rules" ] && ! pacman -Qo "/etc/polkit-1/rules.d/50-elite-wheel.rules" >/dev/null 2>&1 && rm -f "/etc/polkit-1/rules.d/50-elite-wheel.rules"\n'
# E129 — o tema Qt da casa (mesma dança da família E91)
q6_install = '    install -d "${pkgdir}/usr/local/share/elite/qt6ct"\n    install -m644 "${startdir}/files/usr/local/share/elite/qt6ct/qt6ct.conf" "${pkgdir}/usr/local/share/elite/qt6ct/qt6ct.conf"\n'
q6_rm = '    [ -e "/usr/local/share/elite/qt6ct/qt6ct.conf" ] && rm -f "/usr/local/share/elite/qt6ct/qt6ct.conf"\n'
# E132 — o conf dos residentes do elite-daemon supervise (mesma dança da
# família E91: staging acima, install aqui, adoção no pre_install — o
# caminho é NOVO em rig comum, o rm é cinto contra a via sem dono da ISO)
dc_install = '    install -Dm644 "${startdir}/files/usr/local/share/elite/daemon.conf" "${pkgdir}/usr/local/share/elite/daemon.conf"\n'
dc_rm = '    [ -e "/usr/local/share/elite/daemon.conf" ] && rm -f "/usr/local/share/elite/daemon.conf"\n'
# E151 — OS MESTRES DO MANGOHUD EMBARCAM DE VERDADE (staged desde a E136 e
# NUNCA installados — a classe E103: o overlay era o único dono na ISO e o
# rig vivo seguia sem os perfis; agora o molde instala E o overlay cala —
# um dono por caminho)
mh_install = '    install -d "${pkgdir}/usr/local/share/elite/mangohud"\n    install -m644 "${startdir}/files/usr/local/share/elite/mangohud/minimal.conf" "${pkgdir}/usr/local/share/elite/mangohud/minimal.conf"\n    install -m644 "${startdir}/files/usr/local/share/elite/mangohud/balanceado.conf" "${pkgdir}/usr/local/share/elite/mangohud/balanceado.conf"\n    install -m644 "${startdir}/files/usr/local/share/elite/mangohud/diagnostico.conf" "${pkgdir}/usr/local/share/elite/mangohud/diagnostico.conf"\n'
mh_rm = '    [ -e "/usr/local/share/elite/mangohud/minimal.conf" ] && rm -f "/usr/local/share/elite/mangohud/minimal.conf"\n    [ -e "/usr/local/share/elite/mangohud/balanceado.conf" ] && rm -f "/usr/local/share/elite/mangohud/balanceado.conf"\n    [ -e "/usr/local/share/elite/mangohud/diagnostico.conf" ] && rm -f "/usr/local/share/elite/mangohud/diagnostico.conf"\n'
# E130 — o tema do labwc e os settings GTK da casa (mesma dança da família
# E91: caminho NOVO em rig comum = criação limpa, sem dança de adoção)
theo_install = '    install -d "${pkgdir}/usr/local/share/elite/labwc"\n    install -m644 "${startdir}/files/usr/local/share/elite/labwc/themerc-override" "${pkgdir}/usr/local/share/elite/labwc/themerc-override"\n'
theo_rm = '    [ -e "/usr/local/share/elite/labwc/themerc-override" ] && rm -f "/usr/local/share/elite/labwc/themerc-override"\n'
gtk_install = '    install -d "${pkgdir}/usr/local/share/elite/gtk-3.0"\n    install -d "${pkgdir}/usr/local/share/elite/gtk-4.0"\n    install -m644 "${startdir}/files/usr/local/share/elite/gtk-3.0/settings.ini" "${pkgdir}/usr/local/share/elite/gtk-3.0/settings.ini"\n    install -m644 "${startdir}/files/usr/local/share/elite/gtk-4.0/settings.ini" "${pkgdir}/usr/local/share/elite/gtk-4.0/settings.ini"\n'
gtk_rm = '    [ -e "/usr/local/share/elite/gtk-3.0/settings.ini" ] && rm -f "/usr/local/share/elite/gtk-3.0/settings.ini"\n    [ -e "/usr/local/share/elite/gtk-4.0/settings.ini" ] && rm -f "/usr/local/share/elite/gtk-4.0/settings.ini"\n'
# E138 — A FAMÍLIA DO KERNEL MODERNO EMBARCA DE VERDADE (o estágio E136/E137
# existia e o molde NUNCA installou — o dump v2.13 provou no rig 1.0-85:
# sysctl consolidado ausente, /etc/default/scx ausente, regra zram ausente,
# swappiness vivo em 150). Mesma escola das peles: staging em files/etc/…,
# install AQUI, adoção no pre_install (rigs com a via sem dono da ISO: o
# pacote adota antes da extração — a dança da casa; a ISO nova entrega os
# caminhos SÓ pelo pacote, a remoção E138 do profile mata o par).
kmod_install = '    install -d "${pkgdir}/etc/sysctl.d"\n    install -m644 "${startdir}/files/etc/sysctl.d/99-elite-performance.conf" "${pkgdir}/etc/sysctl.d/99-elite-performance.conf"\n    install -d "${pkgdir}/etc/udev/rules.d"\n    install -m644 "${startdir}/files/etc/udev/rules.d/99-elite-zram.rules" "${pkgdir}/etc/udev/rules.d/99-elite-zram.rules"\n    install -m644 "${startdir}/files/etc/udev/rules.d/60-ntsync.rules" "${pkgdir}/etc/udev/rules.d/60-ntsync.rules"\n    install -d "${pkgdir}/etc/modules-load.d"\n    install -m644 "${startdir}/files/etc/modules-load.d/elite-ntsync.conf" "${pkgdir}/etc/modules-load.d/elite-ntsync.conf"\n    install -m644 "${startdir}/files/etc/modules-load.d/elite-sensors.conf" "${pkgdir}/etc/modules-load.d/elite-sensors.conf"\n    install -d "${pkgdir}/etc/tmpfiles.d"\n    install -m644 "${startdir}/files/etc/tmpfiles.d/elite-mglru.conf" "${pkgdir}/etc/tmpfiles.d/elite-mglru.conf"\n    install -Dm644 "${startdir}/files/etc/default/scx" "${pkgdir}/etc/default/scx"\n'
kmod_rm = '    for f in /etc/sysctl.d/99-elite-performance.conf /etc/udev/rules.d/99-elite-zram.rules /etc/udev/rules.d/60-ntsync.rules /etc/udev/rules.d/99-elite-io.rules /usr/lib/udev/rules.d/91-elite-automount.rules /etc/modules-load.d/elite-ntsync.conf /etc/modules-load.d/elite-sensors.conf /etc/tmpfiles.d/elite-mglru.conf /etc/default/scx; do\n        [ -e "$f" ] && rm -f "$f"\n    done\n'
pkg = f"""pkgname=elite-system
pkgver=1.0
# E50 — O SISTEMA EM UM PACOTE SÓ (diretriz do dono). Todo o código de
# casa viaja aqui: os scripts, o daemon de janelas compilado do C vendado
# (sha256 pinado), as units da cadência. O pacman SUBSTITUI o par legado
# (elite-craft + craft-toplevel) na transação — o rig antigo acorda com
# UM dono para /usr/local/bin e UM número para olhar.
# E51 — A CADÊNCIA AO LIGAR: o payload /etc troca o timer de relógio
# (elite-channel, 11:30) pelo timer de BOOT (elite-bootupdate, OnBootSec
# 3min) — o dono: 'atualizar a cada vez que iniciar'; a casa atualiza
# quando a máquina acorda, não quando um relógio aposta que ela está on.
# E51.1 — A PONTE VOLTA (a aposentadoria foi um ERRO DE CÁLCULO, 05/nov):
# com a ponte fora do db, o rig da era v2 (craft-update sem alvos, sem
# --canal) ficou SEM PORTA NENHUMA — o -Syu dele não tem alvo novo, a
# ponte era a ÚNICA transação que disparava o hook da adoção (o dono
# perguntou 'as atualizações funcionam de verdade? nenhum método funcionou
# na 28' e a perícia provou: a cura da pergunta era a ponte, e eu a tinha
# cortado). O custo aceito do retorno: o rig raro 'adotado e fora da era'
# (elite-craft 6 + toplevel 4, sem elite-system) pode ver UMA dose v4.2
# recusada (conflito alvo-contra-alvo) até a porta manual trocar o
# craft-toplevel e o hook puxar o pacote único — uma notificação honesta é
# o preço; um beco sem saída não é. O template segue: a ponte vive no db
# ATÉ que nenhum rig da era v2 exista mais.
# E53 — A DOCK VÊ O SEM-NOME (v2.10.9, relato do dono: "a dock não está
# mostrando todo tipo de pacote — estou com um app image aberto e só
# consigo acessar pelo alttab"): o AppImage sem .desktop não virava botão
# (o dinâmico nascia do casamento comm→.desktop e o None traga a janela
# real que o daemon já via). A cura viaja AQUI (o craft-dock-gui entra no
# MANIFEST do pacote único) — pkgrel 3→4 NO MESMO COMMIT (lei E41).
# E54 — A SENTINELA DA BASE + O DIREITO QUE SERVE + O RICE NO PACOTE:
# (1) o dono colheu o erro cru do pacman ("não foi possível travar a base
#     de dados") — a dose ao ligar aos 3min do boot briga com o manual e o
#     lock órfão de desligamento prende a base para sempre; a sentinela
#     (esperar/limpar órfão/recusa honesta) vai em craft-update v5.2.
# (2) a gramática da dock fica UMA (o dono: "com o direito deve abrir outra
#     sessão/guia"): esquerdo foca · direito nova sessão em TUDO —
#     craft-dock-gui v2.10.10; o fixar segue vivo no craft-pin-pick.
# (3) o rice da casa passa a viajar COMO CÓDIGO (craft-rice novo: drop-ins
#     rc.xml.d do labwc — hoje, a decoração de volta nos jogos Proton que
#     "não desenha o maximizar, minimizar e fechar") — o fragmento chega
#     ao rig do dono SEM tocar no rc.xml dele, a mesma lei do domínio.
# Tudo no MANIFEST do pacote único — pkgrel 4→5 NO MESMO COMMIT (lei E41).
# E55 — O GUARDIÃO NÃO PODE VIRAR REFÉM: o craft-fix-keys que viaja neste
#     pacote ganhou TETO (timeout 300s no pacman -Sy da cura do keyring).
#     O timer elite-keyring-fix roda 2min após CADA boot e um pacman
#     pendurado em conexão travada segurava o db.lck para sempre — cada
#     pacman manual do dono morria em 3s ("não foi possível travar a base
#     de dados") e NENHUMA transação (nem a ponte) atravessava.
#     (correção E56 — a prova do rig: passos 1-3 mostraram ZERO holders e
#     ZERO pacmans vivos; o desbloqueio veio do rm do lock ÓRFÃO — a tese
#     E54 confirmada. O timeout segue como cinto e suspensório.)
# E56 — O ALVO CONDICIONAL + O SEGUNDO GLOB (a prova crua do rig): (1)
#     nomear elite-system junto do -Syu num rig com craft-toplevel vivo é
#     conflito não solucionável (o pacman não substitui o que a MESMA
#     transação atualiza) — o craft-update v5.3 deixa o replaces adotar;
#     (2) as units elite-* órfãs do /etc derrubaram a transação em
#     'arquivos conflitantes' — o segundo glob '/etc/systemd/system/elite-*'
#     escopa a segunda família da casa, nos quatros portas.
# E58 — O ROLLING TROCA O JOGO EMBAIXO (verify da ISO 05/nov): (1) o
#     hyprpolkitagent 0.2.0 (02/nov) nasceu reescrito em hyprtoolkit —
#     layer-shell v5 contra o v4 do labwc: 17 mortes na sessão do live; o
#     craft-bars agora escolhe o agente POR CONTEÚDO (probe 'hyprtoolkit'):
#     lxqt-policykit na frente, era-Qt de fallback, polkit-gnome de lenha —
#     o packages.add ganhou o lxqt-policykit. (2) o craft-fix-keys da
#     sessão agora ESPERA (craft-keyring-wait) antes de tocar no chaveiro
#     — o 'pacman-init.service: Failed with result' do primeiro confronto
#     (sessão ~40s × pacman-init --updatedb) não existe mais: quem chega
#     segundo, espera. Tudo viaja no pacote único — pkgrel 7→8 NO MESMO
#     COMMIT (lei E41).
# E59 — A DOSE É DO SISTEMA INSTALADO (verify da ISO #4: elite-bootupdate
#     'Failed with result exit-code' aos 3min do LIVE — mídia descartável,
#     copy-to-RAM, nada persiste; a causa exata do exit 1 é inobservável
#     por desenho: o stderr morre no update.log do live). Cura na UNIT:
#     ConditionPathExists=!/run/archiso (o mesmo marcador v2.10.12 da
#     camada de sessão) — o live PULA a dose honestamente; o instalado
#     (rig do dono) segue com o E51 intacto. pkgrel 8→9 NO MESMO COMMIT
#     (lei E41 — a unit do pacote único mudou de conteúdo).
# E60 — A VIGÍLIA (relato do dono pós-update: 'bloqueia e NUNCA suspende
#     sozinho'): o suspend deixa de depender do relógio de idle — o lock
#     ARMA o vigia (craft-vigil novo: tempo TRAVADO decide dormir, réu
#     nomeado no idle.log) e o braço do lock no swayidle virou idempotente
#     (--if-needed: o hyprlock vivo rearmava o relógio e o relock infinito
#     comia o suspend de 20min). Viaja no pacote único (MANIFEST adota o
#     bin novo do airootfs). pkgrel 9→10 NO MESMO COMMIT (lei E41).
# E61 — A ORDEM CERTA (o dono esclareceu: 'ele até suspendia, mas SÓ
#     DEPOIS que eu colocava a senha — a suspensão tá no lugar errado'):
#     a arma do sintoma era o BRAÇO IDLE do suspend — o deadline de idle
#     não vê a digitação quando o compositor não conta input travado, e
#     o timeout vencia com a senha NO MEIO (o PC dormia em vez de
#     desbloquear; o dono ligava e digitava de novo). Duas curas:
#     (1) craft-idle: o braço idle DEFERE com lock vivo + vigia no ar —
#         enquanto travado, o tempo TRAVADO é a autoridade; vigia morto =
#         o braço volta a ser rede de fundo (E47/E30 intactos); e os
#         braços do daemon SAEM DE IMEDIATO (cair no menu pendurava o
#         callback num 'read' com stdin vivo — achado do smoke test);
#     (2) craft-vigil ganhou OUVIDOS: CPU do próprio hyprlock (a única
#         voz da mão em compositor que não conta input travado) + marca
#         de atividade que o resume do swayidle renova — dormir EXIGE
#         ticks quietos; nunca mais suspende sob o dono digitando.
#     pkgrel 10→11 NO MESMO COMMIT (lei E41 — craft-idle e craft-vigil
#     mudaram de conteúdo).
# E62 — O PAPEL É DO DONO TAMBÉM (a foto do rig, 05/nov): o craft-update
#     gritava 'linha 154: /var/log/elite-update.log: Permissão negada' na
#     cara do dono — o log nasce root:root 644 (a dose ao ligar é a 1ª a
#     escrever) e a porta MANUAL do dono escrevia contra a parede: o bash
#     grita (erro de redirecionamento é do shell — não morre no '|| true')
#     e as linhas do manual se perdiam inteiras. Cura no ulog: root mantém
#     o papel aberto (666), o dono cura o próprio pelo sudo já autorizado
#     da porta (sudo -n — NUNCA prompt por causa de log; frio = silêncio
#     honesto) e o append viaja em subshell calado.
#     pkgrel 11→12 NO MESMO COMMIT (lei E41 — craft-update mudou de
#     conteúdo).
# E63 — A VOLTA DA IMAGEM (relato do dono 06/nov: 'suspendeu, voltou sem
#     sinal no monitor — luz vermelha; cliquei Power e o PC desligou'):
#     o SUSPEND finalmente acontece (E60/E61 venceram o timing) e o
#     RESUME é a doença nova — o output morre DESLIGADO no DRM com o
#     sistema já de pé. Três caminhos de religar, todos idempotentes:
#     (1) craft-idle screenon virou SONDA (6 tentativas × 2s) e RE-ARMA
#         a vigília quando o lock sobrevive ao sono (o vigia morre no
#         próprio suspend e o braço idle só DEFERE com vigia no ar —
#         o ciclo de sono reintroduzia o bug da E61);
#     (2) craft-vigil chama o screenon no retorno do SUSPEND que ela
#         mesma disparou (sobrevive ao sono — primeiro usuário de pé);
#     (3) elite-resume-display NOVO, hook de system-sleep no 'post'
#         (roda como root, TODOS os caminhos atravessam): espera o
#         driver assentar e religa os outputs de cada usuário com
#         labwc vivo. Viaja NO PACOTE (a lei de um dono por caminho —
#         fora dele o rig nunca receberia pelo canal) + a remoção E57
#         correspondente no build. Mais: craft-power espera o lock
#         NASCER (sonda 2s — o 0.6s fixo era aposta), o
#         elite-install-stage habilita os serviços nvidia-suspend/resume
#         (VRAM preservada exige os serviços — sem eles o resume
#         NVIDIA nasce preto) e o craft-dump coleta idle.log + o réu
#         de kernel (amdgpu/drm/fence/nvrm) — a próxima ocorrência tem
#         réu nomeado no papel.
#     pkgrel 12→13 NO MESMO COMMIT (lei E41 — craft-idle, craft-vigil,
#     craft-power, elite-install-stage e craft-dump mudaram de
#     conteúdo; o hook novo entra no MANIFEST estendido).
# E64 — A ATUALIZAÇÃO FINA (os 5 curáveis do AUD-B, num degrau só):
#     craft-update v5.5 = prova de rede ANTES de qualquer transação
#     (curl 8s no db da casa — falha de rede deixa de virar notify
#     CRITICAL a cada boot e de gastar snapshot PRE da semanal) +
#     sentinela nas TRÊS portas (canal/sistema esperam com teto em vez
#     de morrer calados na briga com o keyring aos 120s do boot; órfão
#     curado nas 3) + checagem horária sem pop-up (notify só com
#     novidade — OnUnitInactiveSec do timer multiplicaria o 'canal em
#     dia' por 24). Units irmãs: elite-bootupdate.service TimeoutStartSec
#     15min (herdava 90s — dose morta por SIGTERM), elite-bootupdate.timer
#     OnUnitInactiveSec=1h (a dose morta do boot volta na hora seguinte),
#     elite-sysupdate.service ConditionPathExists=!/run/archiso (a doença
#     E59 curada na irmã e esquecida na semanal — live >1 semana levaria
#     -Syu na mídia), elite-keyring-fix.service TimeoutStartSec=15min
#     (pacman-key de minutos de parede morto aos 90s = selo que nunca
#     nasce).
#     pkgrel 13→14 NO MESMO COMMIT (lei E41 — craft-update + 4 units
#     mudaram de conteúdo).
# E64.1 — A ETIQUETA É CONTEÚDO (a lição da casa, craft-dump v2.6): a
#     perícia por download do 1.0-14 flagrou o banner da linha 2 ainda
#     em v5.4 (o bloco de changelog v5.5 entrou, o banner não foi batido).
#     pkgrel 14→15 NO MESMO COMMIT (lei E41 — o banner muda de conteúdo).
# E65 — A REUNIFICAÇÃO DOS MENUS DE SESSÃO (ARQUITETURA nº 9, a promessa
#     do polimento desde 11-02): o craft-logout VIROU WRAPPER do
#     craft-power (−69 linhas — o mlog, a gramática 0/1/143 e as ações
#     copiadas morrem; a mecânica mora em UM lugar). O teclado
#     (W-x/W-Escape/C-A-Delete) herda o Sessão inteiro — 'Suspender' com
#     o gate logind/kernel + lock primeiro + -i, e 'Tempo de idle…' —
#     que o menu curto de 3 itens nunca entregou. E a lei v2.9.0
#     (recusa NUNCA é silêncio) chegou ao 'Sair da sessão' do
#     craft-power, que ficou de fora quando reboot/poweroff ganharam a
#     cinta (o labwc --exit falho morria calado no set -e; o guard de
#     labwc ausente do craft-logout absorvido era stderr que tecla
#     nenhuma vê — agora é log + toast).
#     pkgrel 15→16 NO MESMO COMMIT (lei E41 — craft-logout e craft-power
#     mudaram de conteúdo).
#
# 06/nov — A SPEC UNIFICADA DO DONO (as 3 curas do dia):
#     craft-rice entrega o fragmento 20-elite-ssd.xml (a decoração ÚNICA:
#     Brave/família Chromium/imv FORÇADOS à moldura do tema — serverDecoration
#     yes; o dono abriu-os sem botões);
#     craft-dock-gui ganha a GRAÇA DO SNAPSHOT (1 LIST falho não derruba o
#     último — o marcador não pisca no flap do socket; morte real na 3ª
#     falha seguida);
#     craft-bgapps cobra o crashpad PELO NOME (o handler do Chromium não
#     leva --type=; órfão virava programa fantasma na lista).
#     pkgrel 16→17 NO MESMO COMMIT (lei E41 — os 3 scripts mudaram de
#     conteúdo).
#
# 06/nov — E68: A REDE DE RESUME GANHA A FILA DE SOCKETS (relato do dono
#     já no 1.0-17: 'meio que liga mas sem imagem no monitor'): o
#     WAYLAND_DISPLAY do elite-resume-display era um CHUTE FIXO em
#     wayland-0 — sessão respawnada herda outro número (wayland-1,
#     wayland-2…) e o wlopm moria calado DENTRO das 5 tentativas. A fila
#     agora vem dos sockets que EXISTEM em /run/user/$uid (wayland-*,
#     por usuário, idempotente). O réu que a rede não alcança segue
#     nomeado no craft-dump seção 10 — perícia antes de cura.
#     pkgrel 17→18 NO MESMO COMMIT (lei E41 — o hook mudou de conteúdo).
#
# 06/nov — E69: O DESPERTAR DOS DISPOSITIVOS (relato do dono NO 1.0-18:
#     'o suspender volta sem despertar os dispositivos USB — não consigo
#     sequer desbloquear'): a classe 'xHC error in resume, Reinit' (prova
#     a4h8/E24) era LATENTE — antes da E60 o PC quase não dormia; agora
#     que o sono é diário, ela morde. elite-resume-usb NOVO, viaja NO
#     PACOTE: re-bind (unbind+bind) de cada controlador USB PCI no post
#     do sono (re-inicialização determinística — o custo em controlador
#     sadio é ~1s de re-enumeracao; no morto, É o despertar) + re-aplicação
#     da política E24 (wakeup=disabled nos 0x0c03 — o bind pode re-nascer
#     'enabled' e reabrir o despertar sozinho). craft-dump ganha o réu USB
#     (journal xhci/usb + craft-wake-guard status). Relato de teste > papel.
#     pkgrel 18→19 NO MESMO COMMIT (lei E41 — o pacote mudou de conteúdo).
#
# 06/nov — E70: A MOLDURA ÚNICA + A ÁREA QUE SE ORGANIZA (o PRINT do dono,
#     shot-20261106-204606: 'varrendo as inconsistências principalmente na
#     moldura das janelas… e completamente consistente seja appimage, seja
#     só wayland ou qualquer tipo de pacote'): o campo provou DUAS rachas
#     que o papel escondia — o xdg-decoration é NEGOCIADO (app que pede
#     CSD vence o default server do rc.xml: LACT/libadwaita e
#     VS Code/Electron desenharam moldura própria) e a libadwaita NÃO lê
#     settings.ini (o LACT abriu CLARO: ela lê o color-scheme do dconf).
#     Cura arquitetural (doutrina E54, rc.xml do dono intocável): a regra
#     UNIVERSAL identifier=".*" serverDecoration=yes no fragmento
#     20-elite-ssd do craft-rice (a moldura é propriedade do COMPOSITOR
#     para TODA janela que negocia — libadwaita, GTK3, Qt, Electron,
#     AppImage) + fragmento 30-elite-organize NOVO (brave e Code nascem
#     MAXIMIZADOS — a área se organiza no lançamento) + code-flags.conf
#     NOVO no skel (VS Code Wayland nativo) + ELECTRON_OZONE_PLATFORM_HINT
#     no environment (todo Electron ≥28/AppImage nasce Wayland) +
#     color-scheme prefer-dark no autostart (o escuro alcança a
#     libadwaita) + seção [8] NOVA no elite-tune (o rig vivo recebe: skel
#     para as homes, gsettings AGORA, craft-rice vivo — escola 2g, lição
#     E68 sem chute wayland-0).
#     pkgrel 19→20 NO MESMO COMMIT (lei E41 — craft-rice e o skel da
#     sessão mudaram o pacote).
#
# 06/nov — E70.1 (addendum): A PERÍCIA POR DOWNLOAD do 1.0-20 flagrou a
#     cura que não alcançaria o rig antigo: o elite-system NUNCA carregou
#     skel (64 membros = bins/units — o skel é veículo da ISO) e o
#     /etc/skel do rig instalado é da ÉPOCA DA INSTALAÇÃO (o pacote nunca
#     o atualiza) — a 8a copiaria code-flags.conf de um skel velho SEM o
#     arquivo e o VS Code ficaria XWayland com titlebar própria (a ferida
#     do print persistiria). A lição do dono de novo: parecia certo no
#     papel (o contrato lia o skel do REPO) e não funcionaria no campo.
#     Cura: o CONTEÚDO mora no BIN (padrão craft-rice — heredoc na seção
#     [8]); o skel segue para a ISO (instalações novas nascem com o
#     arquivo e a 8a é no-op nelas). +1 contrato.
#     pkgrel 20→21 NO MESMO COMMIT (lei E41 — elite-tune mudou de
#     conteúdo).
# 06/nov — E71: A DOCK QUE NÃO MENTE VAZIA (relato do dono NO 1.0-21:
#     'a dock ainda é bugada — o indicativo de aplicativos abertos somem
#     do nada e as ações se comportam como se o programa não estivesse
#     aberto'; dump e8xl: craft-toplevel em LOOP de morte — 449 SAIU
#     exit=1 / BARS_RESTARTS=488 em 1h36, o socket respondendo OK com
#     'janelas=0' e o ps mostrando Brave/Thunar/foot abertos). A doença
#     INTEIRA: o evento parent era declarado não-nulável no C vendado —
#     o parent(NULL) do compositor (legal pelo XML oficial, que é
#     allow-null="true") matava a conexão Wayland, e o renascido servia
#     LIST vazio VÁLIDO em loop; a graça da E70 só cobria LIST FALHO,
#     nunca a resposta VÁLIDA que mente. DUAS pontas NO MESMO COMMIT:
#     (1) vendor/ (o C do toplevel, era): o parent vira '?o' (nulável — 1
#         caractere que acaba com a classe inteira) + EVT_PARENT nomeado
#         no enum e ignorado de graça (log uma-vida);
#     (2) craft-dock-gui v2.10.11 — as TRÊS REDES da lógica que não
#         mente vazia: A PROVA NO LANÇAMENTO (antes de abrir, UMA LIST
#         fresca julga; janela que aparece agora é FOCADA, não duplicada,
#         e o estado se auto-cura), O DEDUP EM VOO (guard de 8s no
#         _launch — o gargalo único; o direito 'nova sessão' segue
#         livre, aquele é o verbo explícito de duplicar) e A GRAÇA DO
#         VAZIO (LIST válido-vazio que contradiz snapshot vivo é
#         segurado 2 rodadas; na 3ª é verdade aceita).
#     pkgrel 21→22 NO MESMO COMMIT (lei E41 — o C do daemon e a dock
#     mudaram de conteúdo).
#     pkgrel 22→23 NO MESMO COMMIT (lei E41 — o Comprimir morreu com
#     honra na E72: verbo fora do uca.xml do skel, craft-compress
#     extinto do tree, elite-tune [9] entrega a remoção às homes vivas).
# 07/nov — E73: O TERMINAL ABRE COM O RETRATO (o dono: "faz o terminal
#     abrir por padrao com aquelas paradas que mostra o kernel e etc"):
#     o craft-hello existia desde a v1.0.3 mas ninguém o chamava quando o
#     terminal abre (só o W-S-h — que executava o script SEM terminal: a
#     saída se perdia no journal do labwc). Três pontas NO MESMO COMMIT:
#     (1) craft-hello ganha o CONFIG DA CASA (share/elite/fastfetch/
#         config.jsonc — logo "Archcraft" builtin do fastfetch, nome
#         provado no fonte oficial; o usuário que quiser a própria cara
#         cria ~/.config/fastfetch/config.jsonc e o dele VENCE);
#     (2) o .zshrc do skel chama o hello a cada shell interativo novo e
#         a seção [10] do elite-tune injeta o MESMO bloco nas homes
#         vivas (skel nunca viaja no pacote — lição E70.1) e dá terminal
#         de verdade ao W-S-h das homes;
#     (3) o config do retrato viaja NO PACOTE (lição E63: fora do pacote
#         nunca chega — pre_install remove a via da ISO sem dono).
#     pkgrel 23→24 NO MESMO COMMIT (lei E41 — craft-hello, o config e a
#     seção [10] mudaram o pacote).
# 07/nov — E74 — O PROTOCOLO DE OURO (as 7 fases da spec LabWC/Wayland do
#     dono). O pacote mudou em CINCO pontas NO MESMO COMMIT:
#     (1) DOCK: o direito ganhou MENU contextual (craft-dock-gui: _dock_menu
#         + _close_all como fonte única do fecho E36; 'Nova janela' é o 1º
#         item — a gramática UMA v2.10.10 sobrevive dentro do menu; o
#         craft-menu ganhou o slot 'dock' — âncora bottom-center);
#     (2) MOLDURA: GTK_CSD=0 no environment do skel + elite-tune 8e (o GTK3
#         entrega a decoração ao compositor; a regra universal do craft-rice
#         é a lei geral);
#     (3) OSD: swayosd na ISO + binds swayosd-client com fallback
#         pactl/brightnessctl no skel + elite-tune [11] (daemon elite-osd-1
#         no autostart + reescrita das 5 homes vivas);
#     (4) RAM: elite-optimize NOVO — matemática por MemTotal (≤4 GB zram×2/
#         swappiness 150 · 8 GB 60 · 16 GB+ 15) em 99-elite-ram.conf (vence
#         por ordem lexical); elite-tune [5] chama e o 2i pergunta ao perfil;
#     (5) FERRAMENTAS: elite-drivers NOVO (perfis AMD/Intel/NVIDIA por lspci;
#         purga nunca silenciosa) + elite-ferramentas NOVO (paru/octopi/
#         appimagelauncher; a promessa do AUR vira porta).
#     pkgrel 24→25 NO MESMO COMMIT (lei E41 — 3 bins novos + dock-gui +
#     elite-tune mudaram o pacote).
# 07/nov — E75 — O CICLO QUE O --ON SOZINHO NÃO FAZ (a cura do relato
#     recorrente 'suspende, volta e o monitor fica SEM SINAL — PC e
#     periféricos vivos, obrigou a reinicialização forçada') + o 1º lote
#     da AUDITORIA ARQUITETURAL. A perícia do papel: os DOIS caminhos de
#     religar (craft-idle screenon e o hook elite-resume-display) mandam
#     só 'wlopm --on' — que é NO-OP com rc=0 quando o compositor JÁ crê
#     o output aceso, estado comum no wake (o labwc re-habilita na
#     atividade de input que volta com o rebind do elite-resume-usb; o
#     'Suspender' do menu não apaga antes de dormir). Quando a doença
#     mora no DRM (driver não re-assentou o link — a classe amdgpu/KMS
#     que o craft-dump seção 10 caça), o rc=0 do no-op convive com o
#     monitor morto PARA SEMPRE: os dois cures reportam sucesso e
#     NENHUM estado muda. O pacote mudou em SEIS pontas NO MESMO COMMIT:
#     (1) craft-idle screenon: CICLO off→1s→on em cada tentativa (a
#         troca real de estado que força o re-commit no DRM e o
#         re-treino do link; custo honesto: 1 blink no resume sadio —
#         na doença a tela já está preta);
#     (2) elite-resume-display: o MESMO ciclo por socket + FIM DO EXIT
#         CALADO (wlopm ausente agora deixa FALHA no journal — a lei:
#         até a decisão de NÃO agir deixa rastro);
#     (3) craft-dump seção 10: o journal do hook (tag elite-resume-
#         display — logger não aparece no tail -u systemd-suspend) + o
#         estado dos conectores DRM SEMPRE (status/enabled/dpms — a
#         tríade que separa 'driver apagou o conector' de 'conector
#         aceso, monitor não re-trinou'; antes só entrava no fallback
#         sem sessão);
#     (4) craft-rescue-screen NOVO — a escotilha SEM reboot: TTY
#         (Ctrl+Alt+F3) → login → o ciclo nos sockets → volta (o lock do
#         hyprlock está lá); root varre todas as sessões, usuário o
#         próprio runtime; rc no papel (idle.log/journal);
#     (5) elite-post-transaction NOVO + elite-post-transaction.hook
#         (libalpm, /usr/share/libalpm/hooks — heredoc no build, dono
#         ÚNICO no pacote): a auditoria do dono virou código — pacman
#         -Syu cru agora AVISA kernel novo na cara de quem rodou (o
#         carimbo /var/lib/elite/kernel-seen dispara UMA vez por troca;
#         a 1ª execução é linha de base) e observa o wake-guard E24 no
#         papel (/var/log/elite-post-transaction.log; zero rede, zero
#         lock — inofensivo na transação do próprio craft-update);
#     (6) AUDITORIA-ARQUITETURA.md NOVO em docs/gestao — o plano de
#         elevação pedido pelo dono (pipeline, repos híbridos, painéis,
#         provisionamento) com o que JÁ era lei da casa separado do que
#         é proposta.
#     pkgrel 25→26 NO MESMO COMMIT (lei E41 — craft-idle, craft-dump,
#     elite-resume-display mudaram de conteúdo; craft-rescue-screen,
#     elite-post-transaction e o .hook libalpm são NOVOS no pacote).
# E75.1 — A PORTEIRA DO CI EM FLAGRANTE (07/nov, run 42338856744/42338856804):
#     (1) o canal morreu em 'Missing dependencies: wlopm' — o makepkg do
#         container EXIGE o pacote; wlopm entrou nos DOIS ramos do
#         preflight (a dependência nova do depends= exige o pacote no
#         ambiente de build — lição cravada);
#     (2) a SUÍTE vermelha era HERDADA: o SC2034 (ITEM="" morto) nasceu no
#         elite-ferramentas do E74 e o canal daquele push publicou 1.0-25
#         MESMO com a suíte vermelha (a classe conhecida 'canal publica com
#         suíte vermelha') — a linha morta saiu; o gate shellcheck
#         reproduzido LOCALMENTE com o binário estático v0.10.0: ZERO
#         avisos no repo inteiro.
#     pkgrel 26→27 NO MESMO COMMIT (lei E41 — elite-ferramentas mudou de
#     conteúdo; o 1.0-26 nunca chegou a publicar — o container recusou).
# 07/nov — E76 (POLIMENTO, ÁREA 3 DA ROTAÇÃO — craft-drawer/craft-pin/
#     craft-pin-pick): a varredura inteira da área achou a morte silenciosa
#     de VOLTA no picker: 'out="$(craft-pin add …)"; addrc=$?' morria no
#     set -euo pipefail ANTES do addrc quando o craft-pin devolvia rc≠0 —
#     e a duplicata É rc 1 desde o E36, logo o desfecho "'$choice' já
#     estava na dock" era INALCANÇÁVEL (prova: script com stub rc 1 morre
#     sem chegar ao eco seguinte). Cura na gramática da casa
#     '|| addrc=$?' (a MESMA do fuzzel no próprio arquivo) + o help do
#     craft-pin deixou de vazar código (o range mágico '2,22p' imprimia
#     PINS_DIR/DESKTOP_DIRS/ensure_file cru depois do ═ — o awk agora
#     imprime ENQUANTO a linha é comentário) + o inventário do picker
#     enxerga o XDG_DATA_HOME do usuário PRIMEIRO (a precedência do
#     resolve do irmão: .desktop do usuário — ex. AppImage registrada pelo
#     appimagelauncher do E74 — é fixável pelo mesmo fluxo mouse-first).
#     Prova FUNCIONAL de ponta a ponta no 30-unit 3.O: pick REAL +
#     craft-pin REAL + stubs — os TRÊS desfechos E36 saem com toast, e a
#     duplicata não morre calada.
#     pkgrel 27→28 NO MESMO COMMIT (lei E41 — craft-pin e craft-pin-pick
#     mudaram de conteúdo).
# E77 — O PORTÃO E A AUTORIDADE ÚNICA (a spec do dono: corrida de estado
#     no bloqueio/suspensão — timers estritamente sequenciais e
#     mutuamente exclusivos; resume não re-suspende até o destravo):
#     craft-idle ganhou o braço sleep-hook (o choke point universal do
#     before-sleep: portão fecha PRIMEIRO, lock --if-needed desapegado
#     depois), o braço suspend virou autoridade única sob lock vivo
#     (defere SEMPRE e re-arma a vigília morta — a janela 'suspende no
#     meio da senha' morreu) e obedece ao portão; craft-vigil obedece ao
#     portão (teto estourado + portão fechado = espera o destravo),
#     fecha-o antes do próprio suspend e abre-o na saída natural
#     (destravo) e na graça que falha. Prova FUNCIONAL no 30-unit: 27
#     peças novas com processos reais e stubs de papel.
#     pkgrel 28→29 NO MESMO COMMIT (lei E41 — craft-idle e craft-vigil
#     mudaram de conteúdo).
#
# 07/nov — E78: O CICLO PERSISTENTE (a EMENDA do dono ao isolamento E77:
#     "tirar do modo suspensão e continuar na tela de bloqueio reinicia o
#     ciclo para uma nova contagem — persistência, lógica correta para
#     TODAS as formas de uso"). A prisão perpétua do suspend morre: o wake
#     travado deixa de ficar acordado para sempre. craft-vigil mudou de
#     conteúdo: (1) O PAGAMENTO — a vigília renascida no wake nasce
#     DEPOIS do portão fechado e o período completo que ela conta É o
#     'novo período' da spec: no teto com orelhas quietas ela PAGA o
#     portão e suspende de novo (dorme/acorda parado/conta/dorme — cada
#     rodada com o período INTEIRO, nunca loop apertado); (2) A VIGÍLIA
#     OBSOLETA SE APOSENTA — portão com mtime DEPOIS do nascimento = sono
#     sob a minha vigília (menu/tampa): saio sem dormir e armo a sucessora
#     com a contagem nova (o ciclo não herda tempo pré-sono; o marco é a
#     guard anti-loop); (3) AS MÃOS RENOVAM A CONTAGEM — o teto vira
#     PERÍODO CONTÍNUO sem mãos (a spec: T3 só corre continuamente idle,
#     input reseta T3): a pausa de pensamento do dono com o tempo total
#     estourado não dorme mais no meio da senha. O destravo segue abrindo
#     o portão na hora (E77 intacta); o screenon segue intocável (quem
#     paga é a contagem nova, nunca o wake sozinho). craft-idle: só o
#     papel do header (a emenda documentada — nenhum braço mudou).
#     pkgrel 29→30 NO MESMO COMMIT (lei E41 — craft-vigil mudou de
#     conteúdo: o ciclo persistente E78).
# E79 — A SUCESSORA DO PRÓPRIO CICLO (o dump 4nsos do rig: o wake travado
#     das 14:11:35 acordou SEM vigia no ar — o screenon do próprio ciclo
#     executa o pgrep de re-arme com o CHAMADOR ainda vivo (vê a si
#     mesmo, nunca um sucessor) e o callback resume do swayidle perde a
#     corrida contra o exit — o wake pagou e a máquina ficou ESCURA,
#     TRAVADA e ACORDADA por 2h08min até o Power do dono desligar (boot
#     16:35:59). Cura no craft-vigil: a sucessora nasce EXPLÍCITA no fim
#     do ciclo, no sucesso E no FALHA do sono — no sucesso ela é a
#     contagem nova do wake (dorme/acorda/conta/dorme sem fim, cada
#     rodada com o período INTEIRO); no FALHA é a anti-prisão (o sono que
#     não veio re-tenta a cada período, réu nomeado no papel).
#     craft-idle: só a verdade no papel do screenon (o comentário E63
#     vendia 'vê o próprio sucessor no ar' — o pgrep vê o CHAMADOR).
#     pkgrel 30→31 NO MESMO COMMIT (lei E41 — craft-vigil e craft-idle
#     mudaram de conteúdo: a sucessora E79).
# E88 — O DESPERTAR QUE NÃO CONGELA + O SISTEMA INSTANTÂNEO (a perícia do
#     dump elite-dump-20261107-181747 do rig provou TRÊS réus do resume e
#     o dono sentiu o quarto): (1) elite-resume-display REESCRITO — o
#     runuser (PAM) contra user.slice congelado prendia o systemd-suspend
#     90s até o TimeoutStartSec (o journal: Varlink CreateSession
#     UnitAllocationFailed) = tela/mouse/teclado mortos no wake; agora é
#     zero-PAM (setpriv+timeout), sai em <1s e a imagem religa num waiter
#     desapegado que ESPERA o thaw — e o ciclo E75 só usa o --off quando
#     o sono foi ESCURO (a flag dark do pre; menu-suspend não pisca).
#     (2) elite-resume-usb v2 — o rebind cego da E69 virou rebind COM
#     PROVA: foto do inventário HID no pre, graça de 3s, alvejado só no
#     controlador hospedeiro do morto, martelo E69 como reserva, FALHA
#     nomeada — o caminho sadio não desce o martelo (o mouse que morria
#     no rebind cego morre de causa). (3) elite-sleep-report — o papel
#     virou ATO: o selo ACPI desarma TODO *enabled do /proc/acpi/wakeup
#     (GP12/GP13/SWUS/SWDS — os GPEs que dormiram o PC em 7 segundos: 'ele
#     sequer suspendeu' curado; o botão do power é o despertar ÚNICO, E24
#     completa). (4) craft-idle screenon lê a flag dark (zero blink sob as
#     mãos). E a responsividade que o dono mandou ao máximo: dock com
#     guard que se aposenta no map/morte (fim do 'clique ignorado 8s'),
#     craft-drawer com freio de 400ms (fim do abre-fecha-abre), craft-clean
#     v2 (--yes, tamanhos, lixeira, flatpak), elite-optimize v2 (governor
#     performance + EPP — o clock sobe com o PRIMEIRO clique), pacman com
#     ParallelDownloads=5 (a atualização ágil) e a tela de lock v3
#     (relógio com sombra, saudação, card, dica, fade ágil).
#     pkgrel 31→32 NO MESMO COMMIT (lei E41 — 2 hooks reescritos, 1 hook
#     vira ator, craft-idle/craft-dock-gui/craft-drawer/craft-clean/
#     elite-optimize/craft-update/hyprlock.conf mudaram de conteúdo).
# E89 — A TELA QUE LEMBRA + A DOCK QUE OBEDECE AO CLIQUE + O WAKE QUE PROVA
#     INPUT (o dono, dump elite-dump-20261107-190719 do rig 1.0-31 + a
#     lista de UX): (1) craft-display NOVO — a persistência que o sistema
#     não tinha ("eu coloco 200 hertz e toda vez que eu reinicio o PC tem
#     que estar colocando os 200 hertz… porque ele some"): apply no
#     autostart (o arranjo salvo nasce aplicado), watch que grava sozinho
#     a mudança estável feita por QUALQUER porta (wdisplays, menu,
#     wlr-randr) e o menu "Displays…" com TODOS os modos do EDID no fuzzel
#     (aplicado+salvo no mesmo clique — "deveria ser todas as detectadas");
#     wdisplays explicitada na ISO e o item novo no menu.xml do desktop.
#     (2) craft-toplevel ganhou o verbo MIN + a blindagem do SIGSEGV do
#     dump (4× exit=139 em wl_display_read_events em 4 minutos — o réu da
#     "dock com delays absurdos": POLLHUP sem POLLIN sai limpo, get_error
#     julga cada conversa, flush com veredito — core dump nunca mais é
#     desfecho possível). (3) craft-dock-gui: o TOGGLE da dock (clique no
#     app focado MINIMIZA — o 2º clique era ACT no já-ativo = "nada
#     acontece") + o dismiss do nwg-drawer (janela que a dock acorda
#     nasce atrás da gaveta aberta — o dono tinha que fechar o menu à
#     mão). (4) elite-resume-usb: a foto do pre ganha a terceira dimensão
#     (inputs contados por HID — o caso usbhid 3-4:1.4 'couldn't find an
#     input interrupt endpoint' ENUMERAVA e não mexia, a lista crua via
#     vivo) e o BLUETOOTH re-assenta no wake (hci0 reset failed -19).
#     (5) craft-idle: a ORDEM É LEI — SUSPEND ≤ LOCK não nasce mais no
#     conf (o rig dormia DESBLOQUEADO e ACESO aos 5min com lock aos 30).
#     pkgrel 32→33 NO MESMO COMMIT (lei E41 — o C do toplevel recompila,
#     craft-dock-gui/craft-idle mudaram de conteúdo, craft-display é bin
#     novo, elite-resume-usb/autostart/menu.xml/packages.add mudaram).
# E90/E91 — A ÁREA 4 DA ROTAÇÃO + AS CURAS DAS REGRESSÕES DO 1.0-33 (o
#     dump 231955 do rig flagrou o que a entrega prometeu e o canal não
#     carregou): (R1) O TYPO QUE MATOU A DOCK — a E89 escreveu
#     "__main_" no craft-dock-gui: main() nunca rodava, exit=0 em loop de
#     5s, DOCK_COUNT=0 ("a dock sumiu" palavra por palavra no bars.log).
#     Um caractere cura. (R2) O SELO ACPI FORA DO VEÍCULO — o build
#     copiava 2 hooks POR NOME e o elite-sleep-report (o selo E88 do
#     'suspendeu e voltou em 7s') nunca viajou: o rig 1.0-33 seguiu com o
#     hook VELHO (journal provou: GP12/GP13/SWUS/SWDS armadas na porta do
#     sono, sono de 7s/9s). A cópia vira VARREDURA do diretório (todo
#     elite-* de system-sleep nasce no pacote; o pre_install adota — a
#     mesma lição da ferida dos bins E46). (R3) O LOCK QUE NÃO CHEGOU —
#     o hyprlock.conf v3 morava só no skel e home VIVO nunca o recebe
#     (lei do domínio v3): a LOCK SKIN viaja no pacote
#     (/usr/local/share/elite/hyprlock/) e o craft-rice a entrega com a
#     gramática do rice (marcador/fóssil/personalizado + --lock-adopt).
#     E A ÁREA 4 + AS 3 LACUNAS DO UX-ROADMAP no mesmo degrau: craft-dump
#     v2.7 (modos COMPLETOS no wlr-randr — o teto 30 cortava o 200 Hz do
#     papel; WOL/ethtool + PME na caça ao despertar; displays.conf +
#     craft-display status na seção 7; coredumps do toplevel na seção 6;
#     o relato do elite-resume-usb na seção 10), craft-help NOVO (o mapa
#     dos comandos + atalhos reais + estado do canal — a descoberta de
#     dentro do sistema), --help/uso: em TODOS os bins da casa (20
#     nus, a auditoria E66), SCRIPTS.md viaja NO PACOTE (a doc completa
#     em /usr/local/share/elite/docs/), craft-update --check (o veredito
#     READ-ONLY: zero -Sy, zero root — a porta barata de 'tem
#     atualização?'), craft-hello v2 (o onboarding: versão + dose +
#     craft-help após o retrato), elite-tune --status ganha o estado do
#     canal (elite-system/última dose/pendências com a idade da base),
#     ethtool na ISO (a prova do WOL), menu.xml com "Verificar
#     atualizações" + "Ajuda — comandos da Elite", craft-vigil recusa
#     argumentos (a 2ª vigília acidental morre na porta, lei E30).
#     pkgrel 33→34 NO MESMO COMMIT (lei E41 — craft-dock-gui/craft-dump/
#     craft-update/craft-hello/craft-rice/craft-vigil/craft-idle/
#     elite-tune/elite-status/hyprlock.conf/menu.xml/packages.add/
#     apply-overlay/build.sh mudaram; craft-help é bin novo; o pacote
#     ganha elite-sleep-report + hyprlock/ + docs/ no payload).
#     pkgrel 34→35 NO MESMO COMMIT (E-atualização 08-11: craft-update
#     --check sobrevive a pacman vivo sem os pacotes da casa — pipefail
#     não mata mais a pergunta barata; classe flagrada pelo run 42473609437).
#     pkgrel 35→36 NO MESMO COMMIT (E92, relato do dono 08-11: o rig flagrou
#     'elite-sleep-report existe no sistema de arquivos' — o --overwrite da
#     casa ganhou a FONTE ÚNICA HOUSE_OVERWRITE (system-sleep + share/elite
#     + libalpm hooks nas famílias) e a remoção E57 vira VARREDURA do
#     profile — o pacstrap da build mensal não recusa o mesmo conflito).
#     pkgrel 36→37 NO MESMO COMMIT (E93, o paste do dono 08-11: o 1.0-36
#     publicado foi RECUSADO na máquina — o craft-update que rodou é o
#     VELHO (o novo viaja DENTRO do pacote que o conflito bloqueia —
#     bootstrap da cura). A sentinela agora ENSINA a classe órfã com o
#     caminho exato do pacman nas TRÊS portas (canal/semanal no papel;
#     manual com o cru de volta à tela) — bak- para fora do dir de sono,
#     verificação do sem-dono antes de mover, nunca destruição).
#     pkgrel 37→38 NO MESMO COMMIT (E94, relato do dono 08-11, dois réus:
#     (1) 'btop não abre pela dock' — a dock da casa (Popen shell=True, sem
#     tty) nunca vestiu o Terminal=true do .desktop: o TUI nasce e morre em
#     milissegundos. Cura: exec_of veste o foot da casa com app-id
#     determinístico num SÓ lugar, com a origem preservada no raw_of/
#     binary_of (o casamento de janelas fala o nome do app, não o do
#     terminal). (2) 'gparted não vem funcionando por padrão' — a cabeça da
#     fila E58 (lxqt-policykit) nunca chegou a rigs: packages.add só nutre a
#     ISO e o -Syu não instala o que não é dependência. Cura: ADOÇÃO DE
#     ÂNCORAS (ADOCAO/adota_ancoras) nas três portas, transação separada e
#     best-effort que nunca bloqueia a dose principal).
#     pkgrel 38→39 NO MESMO COMMIT (E95, perícia dos dois dumps do dono
#     08/11 — 16:50 e 22:51: os cinco exit=139 do craft-toplevel + o
#     gparted que morre DEPOIS da senha + o trono polkit duplo à espera):
#     (1) O DEMARSHAL SEM MILITARES — 9 coredumps (4 no dia 07, 5 no dia
#     08, offsets IDÊNTICOS libwayland-client+0x9ae3, um deles na rodada
#     do STARTUP via wl_display_roundtrip_queue): a libwayland lê
#     events[opcode] CEGO (sem conferir event_count) e um opcode além da
#     mesa vira wl_message de lixo — a signature vira ponteiro selvagem e
#     o parser de argumentos SEGVa dentro de wl_display_read_events.
#     Cura dupla: o ACOLCHOADO (pads com assinatura vazia no fim das
#     tabelas de eventos do handle E do manager — opcode selvagem cai em
#     memória NOSSA, closure sã, dispatcher ignora) + o manager nasce
#     em v2 (o evento parent, o da churn dos diálogos transitórios,
#     some do fio — a dock nunca o usou; o '?o' da E71 segue declarado
#     de cinto). (2) O GPARTED QUE MORRE COM A SENHA VIVA (o dump prova
#     o agente pedindo E aceitando a senha — 'raw entrou/saiu:
#     polkit-gnome-authentication-agent-1' e gparted 'morreu sem
#     mapear (rc=1)' DUAS vezes no mesmo boot): o pkexec despe o
#     ambiente do root por lei, a GDK sem WAYLAND_DISPLAY não acha o
#     labwc e morre — 'não abre a interface mesmo depois de eu colocar
#     a senha'. Cura: o override gparted.desktop (/usr/local/share/
#     applications, na FRENTE do XDG_DATA_DIRS da sessão) aponta o Exec
#     para o bin NOVO elite-gparted — 'pkexec env' veste o root com a
#     sessão ANTES de ele nascer (e o gparted já-root não re-pede nada:
#     UMA senha, a interface abre). (3) UM TRONO POLKIT — os homes
#     vivos sobem o polkit-gnome às cegas pelo autostart do skel velho
#     (domínio do dono — update não toca) e a âncora lxqt da E94 criaria
#     DOIS agentes registrados (o diálogo da senha nascendo 2× por
#     pedido): o craft-bars aposenta o perdedor na hora — a fila única
#     E58 reina de verdade. Junto no arranque: o chaveiro que o PAM
#     nunca abriu ('gkr-pam: couldn't unlock' em TODO login, o
#     gcr-prompter 2× no dump) recebe o unlock best-effort de senha
#     vazia NO CHAVEIRO EXISTENTE — canal craft-bars, o que alcança rigs
#     vivos. Craft-dump v2.7.1 fotografa o 'SIGSEGV, address' do
#     coredumpctl — a prova que faltava se um 139 resistir ao acolchoado.
# 09/nov — E96: O CANAL QUE NÃO CORTA + A TELA QUE LEMBRA CHEGA AO RIG +
#     A LIMPEZA QUE MOSTRA A CARA (dump 150829 do rig 1.0-39 julgando a
#     E95 e o relato novo do dono). (1) O reply() do C cortava o cliente
#     no PRIMEIRO EAGAIN — um instante de buffer cheio (a dock
#     redesenhando sob CPU saturada do Brave) derrubava o canal em ciclo
#     ('canal de eventos caiu → tick de 5s reconecta' em série no
#     dock.log) e o push virava o delay que o dono sentiu; agora EAGAIN
#     espera poll POLLOUT 2s e só corta cliente REALMENTE morto, com log
#     honesto. (2) O displays.conf NUNCA nasceu no rig (dump L436: 'sem
#     displays.conf' + zero craft-display nos processos) — o autostart do
#     home vivo é fóssil sem as linhas E89 (classe E90/E95); o
#     craft-bars sobe apply+watch (o canal do pacote que alcança rigs
#     vivos — polkit/chaveiro vieram antes) e o apply ganha stamp
#     anti-duplo em XDG_RUNTIME_DIR + passa o modo salvo INTEIRO (sem
#     reformat %.3f e sem sufixo Hz — o parse_mode do wlr-randr antigo
#     exigia número puro; a string do EDID volta idêntica). (3) O botão
#     'Limpeza do sistema' não funcionava: o pacman-contrib (o paccache)
#     nunca esteve na ISO (o passo vivia '(pulado)') e o foot -e fechava
#     antes de o relatório aparecer — entra na ISO (contrato do menu
#     v1.6.3) e o craft-clean interativo PAUSA no fim ('Enter para
#     fechar'). (4) Craft-dump v2.7.2: display.log no papel + o status
#     rodado DENTRO da sessão (o 'agora' vazio do dump era artefato do
#     env do coletor, não doença). Quatro réus, um pacote só —
#     pkgrel 39→40 NO MESMO COMMIT (lei E41).
# 09/nov (tarde) — E97: O SONO QUE SE PAGA SOZINHO + A LOJA DE FÁBRICA +
#     A PELE LIMPA (o mea-culpa do dono: "acho estranho você ter falado
#     que funcionou — funcionou, mas não funcionou com a lógica que
#     deveria"). (1) A orelha de CPU da vigília gritava 'mãos no lock'
#     com o PRÓPRIO RELÓGIO do hyprlock (+1/+2 jiffies a cada tick de
#     render — 62 min de 'CONTAGEM RENOVADA' com o dono AUSENTE no dump
#     163423: o sono automático nunca foi pago travado; a máquina só
#     dormia na hora da senha): o limiar vira PIKE de verdade (≥8
#     jiffies num tick = senha/PAM; o relógio é ruído); a lei E30 ganha
#     flock (duas vigílias vivas no mesmo lock, pids 37301+59893 — o
#     kernel decide, o pgrep perdia a corrida); e o sleep-hook passa a
#     ESPERAR o lock vivo antes do sono (o desapegado perdia a corrida
#     do S3, o lock nascia DEPOIS do wake e o dono digitava a senha
#     duas vezes — 'acorda no lock, senha UMA vez' vira fato). (2) A
#     LOJA DE FÁBRICA (a diretriz do dono): octopi+yay+flatpak na ISO E
#     na ADOCAO (procedência provada: octopi 0.19.0-2 no repo [cachyos],
#     lido no espelho; o pacman-contrib do E96 ganha o canal que E96
#     esqueceu), o hook elite-flathub em TODO install/upgrade do flatpak
#     (ISO e rigs num gesto), o craft-appimage (o registrador da casa —
#     o AppImage baixado ganha rosto no menu sem daemon AUR) e o
#     elite-ferramentas v2 (o mapa do que já está na mão). (3) A PELE
#     LIMPA do lock (v4): saudação, nome e dica SAEM (o dono: "redundante
#     as mensagens — poderia ter um relógio"); relógio+data+card, só.
#     (4) O Comprimir chega ao rig vivo pelo SUPERVISOR (a E72 curou com
#     chegada manual — o elite-tune nunca rodou; o craft-bars remove o
#     bloco do uca.xml fóssil no arranque, o canal E58/E95).
#     Quatro frentes, um pacote — pkgrel 40→41 NO MESMO COMMIT (lei E41).
# 09/nov (noite) — E97.1: O CANAL CAÇOU O QUE A SUÍTE LOCAL NÃO VIU (o
#     'sudo craft-update' do dono respondeu 'nada para fazer' — e a
#     perícia do CI provou PORQUÊ: NENHUM pacote publicou desde a E96).
#     Três réus, todos do mantenedor: (1) o sha do C no TEMPLATE do
#     elite-system ficou da era E95 (o E96 re-pinou só a PONTE — o mesmo
#     C, dois pins, e um deles velho: o makepkg do canal recusou a fonte,
#     run 42693926097 da era: a fonte vendada FALHOU no makepkg); (2) o craft-appimage
#     nasceu 100644 NO INDEX (a lição E95.1 pela SEGUNDA vez — arquivo em
#     disco +x é inócuo se o index grava 100644: o CI e o squashfs herdam
#     o modo do index — a suíte local não tem a peça exec contra ele
#     porque... tinha: 'exec: craft-appimage' pegou no CI e não aqui, a
#     peça roda no ambiente dela); (3) o trap do craft-appimage carregava
#     um SC2154 (o gate do shellcheck do CI: atribuição dentro da STRING
#     do trap não é seguida — a captura do rc mora numa FUNÇÃO agora).
#     E a peça do sha na suíte ganha os DOIS pins (o ponto cego morre).
#     pkgrel 41→42 NO MESMO COMMIT (lei E41 — o conteúdo do pacote muda:
#     o bin do appimage e o PKGBUILD do pacote único).
# 10/nov — E98: O MENU QUE NÃO FECHA + A LOJA LIMPA + A DOSE NO PAPEL — o
#     dia do julgamento dos dumps 202112/203201 (o relogin do dono às
#     20:27:45 e o baile da gaveta às 20:31: B morta às :37, C NASCIDA às
#     :38 — o clique-eco de 'fechar de novo' achava o processo morto e
#     reabria; o relato 'menu de aplicativos que não fecha' era a cara
#     da REABERTURA). Cinco frentes: (1) craft-drawer v1.7 — A MORTE
#     ESPERADA (o toggle que mata agora ESPERA a morte: pkill assíncrono
#     era a porta) + O TÚMULO (600ms de silêncio contados da MORTE — o
#     freio E88 cobria o vão do nascer, o túmulo cobre o do morrer) + O
#     CÃO DE GUARDA (300s e a gaveta presa encerra sozinha, pid+comm
#     provado — o 'timer dos menus' da fila E98 feito carne sem matar
#     gaveta em uso); (2) craft-menu-dismiss v1.1 — O MARTELO ALCANÇA A
#     GAVETA (clique no desktop encerra qualquer gaveta aberta, comm
#     exato, linha no menus.log); (3) A LOJA LIMPA — o monólito octopi
#     0.19.0-2 do [cachyos] carrega os QUATRO .desktop de uma vez (não
#     há sub-pacote a tirar; o -Q do rig lista só 'octopi'): notifier
#     (a tray morreu na E33 e avisar update é papel da casa) e
#     repoeditor (repos são curadoria, não GUI de leigo) ficam OCULTOS
#     por overrides NoDisplay na frente do XDG_DATA_DIRS — o trilho
#     xgps/gparted, e o drawer do rig JÁ esconde 26 entradas por ele
#     (prova viva no dump 203201); QT6CT e NWG-LOOK idem (pedido do
#     dono: 'o sistema utiliza, mas pode ser ocultado' — pacotes ficam,
#     a UI sai do menu, roda na mão); (4) O TRILHO VIROU VARREDURA no
#     build — todo .desktop do dir embarca sozinho (lição E95
#     generalizada); (5) A DOSE NO PAPEL — craft-dump v2.8 (seção 12
#     ganha o elite-update.log + as linhas elite-system do pacman.log:
#     o minuto da aterrissagem deixa de ser janela; o ps da seção 3
#     filtra nwg-drawer/lxqt-policykit) + elite-session-probe v2.2 (a
#     LENTE: DRAWER_OPEN/FUZZEL_OPEN com pid+argv — o réu da gaveta
#     aparece lavado no próximo dump).
#     pkgrel 42→43 NO MESMO COMMIT (lei E41 — 4 overrides novos, 4 bins
#     de conteúdo mudado, o trilho do build generalizado).
# 10/nov — E100: A PELE IRMÃ DO GREETER + O SINAL QUE ESCONDEU O RELÓGIO
#     POR TRÊS ERAS — o relato do dono de novo ('a tela de bloqueio não
#     mudou nada... ela é muito simples... ter um relógio') e a perícia no
#     FONTE do hyprlock (IWidget::posFromHVAlign + Mat3x3::outputProjection
#     + o transform FLIPPED_180 do render: o eixo Y do plano é PRA CIMA —
#     y=0 é o PÉ da tela, y=H é a CABEÇA) cravaram o réu silencioso: os
#     +290/+300/+440/+505 da era v1.7→v4 plantavam relógio, data e
#     saudação ACIMA da borda de cima — JAMAIS renderizaram (a ISO que o
#     rig instalou nunca mostrou relógio NENHUM: o dono pede o relógio
#     desde a v1.7 e a suíte, que lê STRINGS, não enxergava pixels).
#     Quatro frentes: (1) A PELE v5 — irmã do GREETER (archcraft-sddm-
#     theme 2.0, a tela de saída de sessão que o dono aplaudiu): Iosevka
#     Nerd Font (a fonte do greeter + o glifo do usuário na mesma
#     família), a paleta do tema (#D8D8D8/#ABB2BF/#5a6477/#1E2128/
#     #5294E2/#E06B74), relógio 120px BOLD a -240 (PRA BAIXO desta vez),
#     data no esquema do greeter ('%A, %-d de %B' — 'domingo, 9 de
#     novembro'), O USUÁRIO FICA NA TELA (a pílula do greeter: glifo
#     fa-user + nome real via getent, fallback no login — o pedido
#     'permanecer ali'), pílulas 380×54 rounding 27 (o card crust
#     470×120 se aposenta), placeholder UMA voz ('Senha'), pontos ● do
#     greeter, fundo = o wallpaper borrado (lei v2.5.0 intacta);
#     (2) A LEI DO SINAL na suíte (40-integration): todo valign=top com
#     position y positivo CRAVA (e valign=bottom negativo idem) — o conf
#     que nascer com o sinal torto não passa da porteira nunca mais;
#     (3) A PELE SEGUE O LOCK — craft-lock v2.1 chama craft-rice
#     --lock-quiet (a gramática E91 SEM papel) ANTES de cada lock novo:
#     a dose da casa vale no PRÓXIMO LOCK, não no próximo relogin (o
#     'não mudou nada' morre de vez; --if-needed intacto — lock vivo sai
#     cedo antes da renovação); a rede de fósseis ganha o sha da v4
#     (e53fbf2c — quem adotou a v4 renova pela marcada, o fóssil é o
#     cinto); (4) A FOTO DA PELE — craft-dump v2.9: a seção 12 ganha o
#     par home vs mestre (sha256 + 1ª linha de cada) + o veredito da
#     gramática (pele da casa em uso / fóssil aguardando / personalizado
#     com a porta no papel) — a lacuna que deixou o 'não mudou nada'
#     andar às cegas por três eras fecha: o próximo dump NOMEIA o estado
#     do lock skin do home.
#     pkgrel 43→44 NO MESMO COMMIT (lei E41 — o skel da pele v5 + 3 bins
#     de conteúdo mudado: craft-rice, craft-lock, craft-dump).
# E103 — A ABSTRAÇÃO (a missão de polimento do dono): a dose com AUTO-CURA
#     (cura_orfao + classe 404 com retry — o papel de 10/nov provou a
#     recusa com comandos manuais; a lei nova: atualização que chega
#     INSTALA), o -debug fora da dose, o canal com verificação db↔assets,
#     o POLKIT SOB DEMANDA (elite-polkit-listener.c vendado + eleito no
#     craft-bars — idle ~1–2 MB, diálogo zenity só no desafio), o OSD
#     completo (swayosd na ADOCAO, binds --output-volume/--input-volume,
#     config acima da dock via craft-rice), a SKINS GRAMMAR generalizada
#     (rc.xml + swayosd config via craft-rice com rede de fósseis),
#     a PELE v6 (avatar 1:1, gap 24px, rodapé 0.6), os XDG DEFAULTS
#     (profile.d + exo-open + menu sem binário hardcoded), o MODO DE JOGO
#     (craft-game + gamemode.ini — o músculo feral nativo, RAM zero no
#     idle), a vigília do sysctl no post-transaction, a dock com o guard
#     delegado (duping de daemonizado morto) e a central de notificações
#     com a lei low→história.
#     pkgrel 44→45 NO MESMO COMMIT (lei E41 — bins novos (craft-game),
#     C novo (elite-polkit-listener.c), bins de conteúdo mudado
#     (craft-update, craft-bars, craft-rice, craft-lock, craft-pin-pick,
#     exo-open, elite-post-transaction), skel novo (swayosd/config.toml,
#     rc.xml E103, menu.xml, profile.d, gamemode.ini) e vendor C novo).
#     pkgrel 45→46 NO MESMO COMMIT (lei E41 — E104: a PELE DO MENU viaja
#     no pacote (usr/local/share/elite/labwc/menu.xml) e três bins mudam
#     de conteúdo: craft-rice (a 3ª pele + backup nas renovações),
#     craft-pin-pick (o modo --rm — o desafixar com porta visível) e o
#     menu.xml v2 do skel (rótulos sem nome de pacote, a ordem do dono).
#     pkgrel 46→47 NO MESMO COMMIT (a cura do gate: o shellcheck do CI
#     cobrou SC2209 no MODO=rm do craft-pin-pick — bytes mudam, a
#     etiqueta acompanha; a 1.0-46 da run #71 nunca chega ao rig, a
#     1.0-47 é a pele do menu inteira).
#     E105 (o dump 195332 periciado): o subject EXPLÍCITO do listener (o
#     polkit novo cobrava e o arranque morria exit=1 em loop a cada 5s —
#     a sessão sem agente), a demição honesta no craft-bars (3 arranques
#     mortos = o fallback da fila assume o trono), o sed do lock PRESO ao
#     bloco background (o avatar mostrava o wallpaper — 'a fotinha
#     cortada e o preview feio'), a reconciliação do display (o stamp não
#     é fé: realidade em 60 Hz com conf em 200 Hz volta ao arranjo do
#     dono), o format-stopped vazio na top bar (o fantasma parado sai) e
#     a foto do nascimento do lock (lock.log + MPRIS no dump). pkgrel
#     47→48 NO MESMO COMMIT (lei E41).
#     E106 (polimento área 5): o refresh de sessão do craft-update
#     JAMAIS reiniciou o roteador de áudio — o pgrep -x casa COMM e o
#     comm do daemon é 'python3' (shebang env; a doutrina E48 aplicada
#     à dock, esquecida do áudio) — a forma -f do supervisor assume
#     (craft-update, bins de conteúdo mudado: craft-update,
#     craft-audio-route (o unplug anuncia FALHA quando o pactl falha +
#     o help aponta o papel certo), craft-wake-guard (a taxonomia
#     verdadeira da serial bus — comentário)). pkgrel 48→49 NO MESMO COMMIT (lei E41).
#     E106 (O DUMP DO DONO PERICIADO, elite-dump-20261112-161718): a
#     colheita completa — (a) a âncora do game watch no craft-bars
#     JAMAIS casou ('^/usr/local/bin/craft-game watch$' vs o cmdline real
#     'bash /usr/local/bin/craft-game watch': 1540 restarts, 12 pares
#     vivos no ps, o log em loop de 5s desde o boot — E48 a 3ª vez) e o
#     watch ganhou flock singleton no corpo; (b) o agente polkit morria
#     em TODO arranque com assertion POLKIT_IS_SUBJECT (XDG_SESSION_ID
#     ausente na sessão SDDM+labwc — o lançador injeta a sessão wayland
#     do logind) e a aposentadoria do lxqt JAMAIS mordeu (comm cortado
#     em 15: 'lxqt-policykit-'); (c) a DUPLA SENHA do lock (suspend em
#     voo × destravo no mesmo segundo: o sleep-hook recriava o lock e a
#     máquina congelava pedindo a senha DE NOVO) — termômetro
#     unlock.stamp no vigia + recheck de nascimento no craft-lock +
#     porteira que solta o exec (o flock é do parto, não da vida) + os
#     braços do idle com guard de destravo fresco; (d) o vigia ganhou a
#     última olhada antes do sono (suspend sobre destravo nunca mais);
#     (e) os 200 Hz: o stamp 'fail' era TERMINAL e escrito ANTES do
#     apply (um boot de link frio muteava a sessão inteira) — stamp
#     honesto ok/fail:N com retry de 6, o watch NÃO grava a reversão do
#     resume (marco display-resume do hook) e o status nomeia as seções
#     vazias; (f) o menu do desktop enxugado 21→17 (Editor/PDF mortos,
#     Verificar atualizações morta — o atualizar já verifica, Sair da
#     sessão direto, a gaveta unificada com marcadores no laço, o help
#     com a pausa do E96, a calculadora avisa no ramo vazio); (g) o
#     contador de processos honesto (swayosd/lxqt-policykit/gcr/zenity
#     na casca, interval 5, aviso no clique vazio); (h) o fantasma
#     'Install Archcraft' morto nas três mãos (build não embala,
#     post-transaction remove, sweep purga o cache sempre); (i) a dock
#     com denylist de diálogos de daemon no raw + case-insensitive no
#     launch + menu que fica de pé após fixar/desafixar; (j) o ciclo de
#     wake com mutex (fim da corrida off/on dos três braços — o 'perde
#     a imagem ao despertar'). Bins de conteúdo mudado: craft-bars,
#     craft-game, craft-lock, craft-idle, craft-vigil, craft-menu,
#     craft-pin-pick, craft-help, craft-bgapps, craft-dock-gui,
#     craft-display, craft-dump, elite-post-transaction, elite-sweep,
#     elite-resume-display, menu.xml, hyprlock.conf (a pele v7 — SEM
#     avatar/pílula/nome: a ordem do dono), config.top. pkgrel 49→50 NO MESMO COMMIT (lei E41).
#     E107 (O DUMP DO DONO PERICIADO, elite-dump-20261112-200537): a bomba
#     do menu + as três cargas dos 200 Hz + as duas portas de pacote —
#     (1) O MENU DE 3 ITENS ('de 21 para 3', o dono): o comentário da
#     v2.11.4 citou um verbo de CLI com dois hífens de prefixo — a espec
#     XML PROÍBE dois hífens em comentário, o libxml2 do labwc rejeitou
#     o ARQUIVO INTEIRO e todo rig da dose 1.0-50 caiu no menu de
#     fábrica (Terminal/Reconfigure/Exit — o 'Reconfigurar que não faz
#     nada' do dono é o labwc de fábrica, não a casa); provado por parse
#     (not well-formed line 74) + pacote baixado byte a byte igual ao
#     repo; A CURA em três mãos: o menu.xml v3 parseia (contrato E107 na
#     fase 2: o juiz é o parser, não o olho), o craft-rice RECUSA pele
#     XML doente na porta do rig (a pele viva segue no lugar) e a
#     curadoria do dono no v3: programas SAEM (Navegador/Arquivos/
#     Calculadora — a gaveta Aplicativos cobre), ações de sistema FICAM
#     (print/telas/atualizar/limpar/dock/jogo/idle/lock/sair) e as
#     portas de pacote ENTRAM (AppImages… e Flatpaks…); (2) O RETRY
#     MENTIROSO (E33): o do_apply anunciava 'RE-TENTANDO (1/6)' e a
#     aplicadora recusava DENTRO com o guarda anti-duplo E96 ('nada a
#     fazer') matando o processo com exit 0 — o contador congelado em
#     1/6 PARA SEMPRE (o eco duplo de 5s no display.log, o rig a 60 Hz
#     desde o boot); a aplicadora agora é PURA e a máquina de estados
#     mora SÓ no do_apply (o contador ANDA: fail:1, fail:2, teto 6);
#     (3) O SAVE DE LIXO: no meio da troca de modo o wlr-randr some com
#     a marca '(current)', o parser devolve 'mode:-' e a v2.11.4
#     GRAVOU isso — o displays.conf do rig amanheceu com um traço no
#     lugar do 200 Hz (19:57:08 — o 'tá salvando lixo' na letra do
#     dono); o save RECUSA estado sem marca (espera assentar 5s, recusa
#     com prova no papel), o watch SÓ grava com o apply da sessão
#     assentado (o default do boot NÃO é escolha), transição não conta
#     como estabilidade e o gesto do menu assenta o stamp e avisa;
#     (4) O DUMP CEGO: o env do dono escapado expandia VAZIO no filho
#     (status cego 'HOME=<não setado>') — o pai expande agora + A FOTO
#     DO MENU no papel (parse com veredito, a pele vs a mestre com
#     sha256): o ponto cego que escondeu o réu morre; (5) AS PORTAS DE
#     PACOTE do dono ('a integração entre os formatos'):
#     craft-appimage ganha o braço menu (registrar/remover/ver com
#     desfecho na tela — o registrador da E97 era CLI invisível) e
#     craft-flatpak NASCE (a gestão SEM TERMINAL: busca+instala, remove,
#     limpa runtimes e DADOS órfãos com --delete-data, atualiza — o
#     flatpak/Flathub já viajavam desde a E97); craft-clean v3 ganha os
#     caches de USUÁRIO (octopi/yay/thumbnails medidos no relatório).
#     Bins de conteúdo mudado: menu.xml, craft-rice, craft-display,
#     craft-dump, craft-clean, craft-appimage, craft-help, SCRIPTS.md +
#     bin NOVO craft-flatpak. pkgrel 50→51 NO MESMO COMMIT (lei E41).
# E99 — A FILA DO LOGOUT CHEGA (polimento do dia): o gate do COMPOSITOR no
#     craft-bars — sem labwc o supervisor DORME (a janela morta do logout
#     respawnava clientes de display a cada 5s; cada um morria em
#     coredump — o réu 181504) + o espelho do clamp E33 (lm=10 → 5, o
#     comentário jurava espelho com o craft-idle e o número era outro) +
#     o soft-hyphen invisível e a lista do uso() que faltava 3 membros.
#     Bin de conteúdo mudado: craft-bars. pkgrel 51→52 NO MESMO COMMIT
#     (lei E41).
# E108 — O DUMP 180302 PERICIADO (o dono: "analisa tudo minuciosamente e
#     corrige tudo que está errado, mal feito ou com lógica ruim"): (1)
#     craft-display — o CONF DOENTE (mode:- no disco, veneno do save
#     antigo) dorme a persistência com aviso nomeado UMA vez por sessão
#     (o '60 Hz sempre volta' era o reconcile lutando 30s contra um conf
#     que nunca restaura o modo — FALHA ×6 fotografada) e o FALHA do apply
#     agora carrega rc+stderr (o antigo CHUTAVA a causa com stderr
#     engolido); (2) craft-idle/craft-vigil — o papel não clama mais ciclo
#     que não houve ('suspend voltou (ciclo completo)' logado NO MESMO
#     SEGUNDO do 'suspendindo' com o journal provando sono REAL 40min — o
#     relógio de parede julga: sono de verdade avança date +%s); (3)
#     craft-dump v2.11 — os 3 carimbos divergentes (v2.9/v2.10/v2.9) viram
#     UM, o can-suspend MORTO (verbo inexistente no systemd 26x) vira a
#     propriedade CanSuspend via busctl, as temperaturas ganham o hwmon
#     que o thermal_zone não tem (a seção amanhecia VAZIA em desktop AMD)
#     + critical-chain (o '1min35s' sem réu) + o LÍDER de cada sessão
#     logind (a 2ª 'unspecified' fecha a perícia) + zram-generator.conf (o
#     suspeito do swappiness 150×180) + o veredito do E101 no papel (o
#     elite-post-transaction.log que o dump não coletava) + a honestidade
#     do /var/log/journal; (4) elite-post-transaction — O JORNAL QUE
#     SOBREVIVE AO REBOOT (o journal VOLÁTIL do rig matava a perícia
#     cross-boot inteira; /var/log/journal nasce na primeira dose).
#     Bins de conteúdo mudado: craft-display, craft-idle, craft-vigil,
#     craft-dump, elite-post-transaction. pkgrel 52→53 NO MESMO COMMIT
#     (lei E41).
# E109 — o dump 181701 (18:17 do rig) periciado e os réus curados: (1)
#     menu.xml — AppImages… e Flatpaks… SAEM do botão direito (a ordem do
#     dono: 'eu esperava um gerenciador de app images como um pacote
#     realmente instalado no sistema e não isso… Por mim, poderia ser
#     removido ambos do menu' — menus de comando não são pacote; os bins
#     seguem CLI e os gerenciadores reais (Gear Lever/Warehouse, Flathub)
#     ficam como candidatos QUANDO o dono ratificar); (2) craft-pin-pick —
#     O MARCADOR QUE NUNCA ACENDIA (o case ' $pins ' contra o arquivo
#     multilinha: o newline quebrava o casamento e NENHUM pin acendia o ✓
#     — o dono não conseguia remover NADA, 'só tá detectando que o Thunar
#     tá na dock'; comparação por linha no $1, a gramática do rm); (3)
#     craft-display — A MORTE CALADA DO SINGLE-OUTPUT ('Telas e resolução,
#     eu clico e não acontece nada': o alvo da 1ª tela nascia de cut -f1
#     (TAB!) e recebia A LINHA INTEIRA — o filtro awk nunca casava e o
#     menu saía exit 0 SEM JANELA e SEM PALAVRA em toda máquina de UM
#     monitor; cut -d'|' + morte nomeada); (4) craft-idle — O ZUMBI DO
#     ANTES-SONO (a DUPLA SENHA provada de ponta a ponta: o sleep-hook
#     nasceu 17:20:50 e o S3 congelou-o antes do primeiro ilog; completou
#     18:01:16 — 10s pós-wake — com o termômetro do destravo VELHO (a
#     vigília só o tocou 18:01:29) e re-travou a tela em cima do dono que
#     ACABAVA de digitar a senha; o mesmo zumbi no braço suspend = o
#     'pc suspendendo depois de colocar a senha'; o relógio de nascimento
#     T_INICIO julga — braço que atravessou sono NÃO re-trava, NÃO
#     suspende, NÃO pisca a tela, com linha nomeada no papel); (5)
#     craft-clean — O PAPEL DA LIMPEZA ('limpeza do sistema também não
#     funciona' e a casa NÃO TINHA LOG para julgar: clean.log família E36
#     com o veredito de cada passo); (6) craft-update — A ADOÇÃO NOMEADA
#     (o rig SEM o pacman-contrib e o papel SEM UMA linha de adoção em 3
#     doses de canal — o 'presente = silêncio' virou ponto-cego; veredito
#     por âncora + --asexplicit contra o varredor de órfãos) e (7)
#     craft-game — o Status ABRE O PAPEL INTEIRO no foot (o dono: 'clico
#     em status, ele gera um log… não sei como funciona isso') + o resumo
#     honesto de como o gamemode funciona. Lição nova da periciagem (sem
#     cura cega): o padrao "\\[multilib\\]" do build/apply-overlay/packages.add
#     SEMPRE esteve inteiro no disco — o 'ultilib]' era ARTEFATO DE
#     EXIBIÇÃO (a renderização come a sequência colchete-m; od provou; o
#     POLIMENTO 4nsos já dizia e a cura de hoje quase quebrou código
#     sadio 4× — a prova é o byte, não a tela). craft-help — O MAPA EM
#     DUAS VOZES ('Tem muito comando… nem sei se precisa de tanto': 13
#     PORTAS DO DONO + o resto rotulado 'O QUE RODA SOZINHO').
#     Bins de conteúdo mudado: menu.xml (pele), craft-pin-pick,
#     craft-display, craft-idle, craft-clean, craft-update, craft-help,
#     craft-game. pkgrel 53→54 NO MESMO COMMIT (lei E41).
#
#     E110 (54→55) — O DUMP elite-dump-20261115-114852 PERICIADO e a dupla
#     senha morta PELO ESTADO (o dono: 'ao despertar da suspensao tenho
#     que colocar a senha duas vezes na tela de bloqueio ou seja o erro
#     persiste'): (1) O JUÍZ É O ESTADO DO LOGIND — o fork do swayidle foi
#     congelado pelo S3 ANTES de executar UMA linha do sleep-hook: o
#     T_INICIO=$(date +%s) do E109 rodou SÓ NO THAW (relógio FRESCO,
#     11:48:25) e o zumbi ficou CEGO ao réu real (o hook fechou o portão e
#     convocou craft-lock --if-needed NO MESMO SEGUNDO do fini do hyprlock
#     original — o lock renasceu e a senha foi pedida de novo); o hook
#     agora julga pelo systemd-suspend.service (active/activating = o sono
#     é AGORA; inactive = carta do passado — nada a fazer; consulta falha
#     = o E109 decide, defesa em camadas); (2) O CARIMBO DO DESPERTAR — o
#     elite-sleep-report escreve /run/elite/sleep-returned no post (os
#     braços do user julgam o pós-wake pelo ESTADO real, o journal não é
#     consultável sem bus); (3) O MUNDO PÓS-WAKE NÃO APAGA A TELA QUE O
#     RESUME ACENDEU — o timer pendente do OFF_MIN apagou a tela 19s pós-
#     wake COM O DONO digitando ('escurece por um tempo e abre'); o
#     screenoff adia com carimbo fresco <120s e o próximo tick de quietude
#     cumpre o gesto; (4) O DESTRAVO É INSTANTÂNEO — o fadeOut 5→1 da pele
#     do lock (o dono: 'poderia ser praticamente instantânea… só coloca a
#     senha e ele já abre muito rápido').
#     E110/pacote-2 — AS CURAS DA UX DO DUMP 114852 (o dono palavra por
#     palavra): (5) craft-clean — O MODO MENU PAUSA INCONDICIONAL ('limpeza
#     do sistema, ele tenta abrir uma tela que fecha na hora, terminal' —
#     o item lança craft-clean menu: o papel fica até o Enter, MESMO que um
#     passo morra no meio); (6) craft-update — GAMEMODE+GAMESCOPE ENTRAM NA
#     ADOÇÃO (o músculo do modo de jogo NUNCA chegou ao rig: a ISO tem os
#     pacotes desde a E103 e a ADOCAO não os carregava — o dono clicava
#     'Ativar agora' num sistema sem gamemode) + AS LOJAS DA CASA CHEGAM
#     (a ratificação do dono: 'o certo seria ter um pacote no próprio
#     sistema que vai gerenciar isso… uma ferramenta que já existe no
#     mundo Linux' — Flathub entra como remote e WAREHOUSE (a loja de
#     Flatpaks com navegação real do FlatHub) + GEAR LEVER (o gerenciador
#     de AppImages: launcher e atalho sem instalação manual pelo terminal)
#     sobem best-effort com veredito nomeado, nunca bloqueiam a dose);
#     (7) craft-game — O FEEDBACK QUE O DONO NUNCA VIU (o ramo ausente só
#     ecoava no fuzzel sumido e NENHUM note subia: 'clico para ativar
#     agora manual e ele não dá o indicador se ativou ou não, só fecha o
#     menu... o manual fica com um risquinho na janela do status' — o
#     note E106 chega no ramo ausente e o item do menu DIZ O ESTADO:
#     'Manual: ATIVO (desativar)') + O STATUS NÃO CITA RELATO DO DONO
#     ('imagina outra pessoa abrindo isso daqui, ela não vai entender
#     nada' — o texto citado vira linguagem neutra e ganha o caminho
#     manual nomeado); (8) craft-display — O MENU QUE O DONO LÊ ('a tela
#     é bem poluída e não é fácil ter os indicadores do que está marcado…
#     Salvar arrangement atual, inclusive isso não é nem autoexplicativo')
#     — ordena por resolução desc / taxa desc com o atual marcado no topo
#     do seu tamanho + rótulos leigos (Melhor qualidade do monitor / Duas
#     telas: posição-escala / Guardar como está agora); (9) craft-help —
#     O MAPA SÓ COM O ÚTIL ('removendo desses comandos que não são úteis…
#     só comandos úteis') — craft-appimage/craft-flatpak saem da voz do
#     dono (os bins seguem CLI honesto, a doc SCRIPTS.md os cobre) + a
#     seção AS LOJAS DA CASA acende SÓ quando Warehouse/Gear Lever
#     existirem (o papel nunca anuncia o que não está na mão);
#     (10) craft-dump — O PAPEL DA LIMPEZA E DO JOGO ENTRA NO DUMP (a
#     seção 12 coleta clean.log e game.log — o réu do 'fecha na hora'
#     morre com prova no próximo dump); (11) elite-post-transaction — A
#     FALHA NOMEADA (seis 're-aplicação FALHOU' em três dias SEM UMA prova
#     do porquê: o rc+stderr do systemd-sysctl entra no papel — o réu do
#     swappiness 150×180 fica nomeado para o próximo dump julgar).
#     Bins/pele de conteúdo mudado: craft-idle (sleep-hook + screenoff),
#     elite-sleep-report (o carimbo), hyprlock.conf (pele, fadeOut),
#     craft-clean (modo menu), menu.xml (pele: Limpeza lança o modo menu),
#     craft-update (adoção gamemode/gamescope + as lojas), craft-game
#     (feedback + estado + texto neutro), craft-display (ordenação +
#     rótulos), craft-help (mapa limpo + as lojas), craft-dump (coleta),
#     elite-post-transaction (FALHA nomeada). pkgrel 54→55 NO MESMO
#     COMMIT (lei E41).
#     E111: craft-update — O ATRASO DE UMA DOSE NOMEADO (a pergunta do
#     dono no rig 1.0-55: 'os programas de app image etc, não foram
#     adicionados igual ao sistema? Talvez você tenha adicionado a ISO,
#     mas não adicionou aí no pacote de atualização' — o réu é a
#     natureza do binário que se atualiza: a dose que ENTREGA o
#     craft-update novo RODOU com o binário ANTERIOR — o código das
#     lojas (Flathub + Warehouse + Gear Lever) e da ADOCAO ampliada
#     (gamemode+gamescope) entra na PRÓXIMA dose; a dose ao ligar
#     (elite-bootupdate) e a porta manual já nascem com o código novo;
#     o papel NUNCA deixa o dono adivinhar — nomeia_fila_nova nos 3
#     fluxos). Bin de conteúdo mudado: craft-update. pkgrel 55→56 NO
#     MESMO COMMIT (lei E41).
#     E112: o dump 195015 periciado — O ID DO GEAR LEVER MENTIA (o E110
#     usou 'io.github.mijorus.smile', ID que NÃO existe no Flathub — a
#     API do próprio Flathub nomeia: it.mijorus.gearlever — e o papel
#     culpava 'sem rede?' com a rede perfeita: réu renomeado, família E33
#     no nosso próprio papel); a falha da loja agora carrega rc+stderr
#     (a escola do sysctl E110 — o réu tem nome). O DUMP GANHA OS OLHOS
#     QUE A SEÇÃO JURAVA: /usr/lib/sysctl.d + /run/sysctl.d listados e
#     greppados (o réu do swappiness 150×180 mora lá — cachyos-settings —
#     e o drift que SOBREVIVEU ao reboot do 19:48 voltou numa janela sem
#     ator nomeável: 17:12:35 sem drift (hook viu 180) → 19:50 com 150 —
#     a caça agora é no papel) + o journal do systemd-sysctl do boot +
#     o tail COMPLETO de upgrades do pacman.log (um cachyos-settings às
#     19:49 passava invisível). O STATUS DO JOGO JULGA O WATCH (o papel
#     dizia ON lendo o conf enquanto o daemon podia estar FORA — o boot2
#     de 16:06 não recebeu NENHUM 'no ar' no game.log: pid vivo + cmdline
#     julgam, reutilização de pid não engana). Bins de conteúdo mudado:
#     craft-update, craft-dump, craft-game. pkgrel 56→57 NO MESMO COMMIT
#     (lei E41).
#     E-auditoria (2026-11-16): O HELP REPETIA O ID MENTIROSO — a 2ª
#     instância do réu da E112: o craft-help consultava o app inexistente
#     no Flathub e a linha 'Gear Lever' do help NUNCA acendia. E A GUARDA
#     1095 DA SUÍTE PASSAVA VERDE POR COMENTÁRIO desde a E112 (o padrão
#     que ela certificava no craft-update morava só num comentário).
#     Cura: o ID real no craft-help + a guarda re-apontada para onde o
#     réu morava + anti-regressão (assert_nogrep). Bin de conteúdo
#     mudado: craft-help. pkgrel 57→58 NO MESMO COMMIT (lei E41).
#     E113 (2026-11-16): O DUMP 170720 PERICIADO — o rig pós-dose 1.0-57
#     em quatro réus com nome no papel: (1) O RC=127 DA CURA DO E110 —
#     'systemd-sysctl: comando não encontrado' em TODA re-aplicação desde
#     11-15: o systemd-sysctl não é comando de PATH (o binário é
#     /usr/lib/systemd/systemd-sysctl) e a cura do E110 nunca executou —
#     família E33 na cura; o padrão do firstboot (systemctl restart
#     systemd-sysctl.service || sysctl --system) assume + VERIFICAÇÃO por
#     chave no kernel vivo (o valor VIVO é o veredito, não o rc) + o
#     '0\\n? fonte(s)' do wake-guard morre (o '|| echo ?' disparava em
#     zero-matches do grep -c). (2) A TELA QUE O BOOT ESQUECE — o
#     craft-display aplicava '--scale-exact' e o wlr-randr do rig NÃO
#     TEM (unrecognized option, 6 FALHAS por boot, o dono a 60 Hz até
#     abrir o wdisplays na mão): o probe do --help decide a bandeira que
#     a máquina local aceita (--scale-exact ou --scale) — a promessa E89
#     de pé em qualquer geração. (3) O WATCH DO JOGO FORA + SUPERVISOR
#     CALADO + O ÚLTIMO CLIQUE DO MENU EM AUTO=0 — o toggle do menu era
#     invisível para a perícia: o toggle deixa linha no game.log e o
#     supervisor nomeia o porquê do silêncio UMA vez por boot (ausência
#     intencional ou o match do pgrep com cmdline no papel) + o dump
#     fotografa o veredito AO VIVO (conf + status E112 + família no ps —
#     não mais cliques antigos no tail). (4) AS SENHAS QUE O LOCK
#     RECUSOU — 'Authentication failed for hyprlock' ×2 às 17:02 no
#     bars.log: contagem + últimas recusas entram no papel. E os olhos
#     que faltavam: /usr/local/lib/sysctl.d (o ÚLTIMO dir que o
#     systemd-sysctl lê e o papel nunca abriu — o ator do 150 pré-Elite)
#     + os atores executáveis do sysctl + brave-origin instalado×db (o
#     canal diário não traz o Brave: 1.99.55 no rig com o pin em 1.99.57
#     e check-brave celebrando — a distância no papel). O dump etiqueta
#     v2.12 (etiqueta = conteúdo). Bins de conteúdo mudado:
#     elite-post-transaction, craft-display, craft-bars, craft-game,
#     craft-dump. pkgrel 58→59 NO MESMO COMMIT (lei E41).
#
#     pkgrel 59→60 NO MESMO COMMIT (lei E41) — E114: o dump 183150
#     periciado + a palavra do dono de 16/11. (1) O SUSPEND SOB A SENHA
#     QUE O DONO DIGITOU — o papel fotografou o crime inteiro
#     (17:18:07 mãos no lock; 17:27:42 o deadline do braço idle chegou
#     NO MESMO segundo da morte do hyprlock: pgrep morto, stamp do
#     destravo ainda por nascer — a vigília tica a cada 30s — portão
#     aberto, systemctl suspendeu na cara do dono): o braço do idle
#     agora DEFERE enquanto a vigília estiver no ar (a lei E77 na letra
#     inteira: o destravo formal é DELA; o dono ausente segue dormindo
#     pelo teto DELA — a corrida morre pelo ESTADO) + o juiz E110 do
#     sleep-hook ganha retry de 1s (o papel 17:27:43 fotografou
#     'inactive' NO MEIO do sono real — o PrepareForSleep do logind
#     dispara antes do flip da unit). craft-idle. (2) O VÍDEO BRANCO DO
#     YOUTUBE — o réu é a linha Vulkan do brave-flags.conf da era v1.1
#     (compositing Vulkan do Chromium sobre RADV: o frame não desenha, o
#     preview da timeline desenha por outro caminho — a assinatura exata
#     do relato): o conf da casa vira v1.2 (GL compositing, o padrão
#     estável) e GANHA VEÍCULO até o rig vivo: o conf viaja no pacote
#     (/usr/local/share/elite/chromium-flags/) e o elite-post-transaction
#     sincroniza ao home de cada usuário real. brave-flags.conf +
#     elite-post-transaction + build.sh (empacotamento). (3) A LIMPEZA
#     QUE NÃO LIMPAVA — o relato do dono ('clico e não abre nada… tenta
#     abrir uma tela, mas não executa uma limpeza realmente') tinha dois
#     réus: o sudo no escuro do terminal (a parede invisível) e o MAIOR
#     cache do disco fora da varredura (Brave 1,6 GB no papel). Cura: o
#     item do menu pede raiz pelo polkit GRÁFICO (pkexec env HOME — o
#     diálogo que o dono já conhece) e o craft-clean v4 ganha o passo do
#     Brave (só com o navegador fechado, só os regeneráveis Cache/Code
#     Cache/GPUCache) + a lixeira certa no modo root. menu.xml +
#     craft-clean. (4) A PORTA DAS TELAS SAI DO BOTÃO DIREITO — a ordem
#     do dono ('já tem o programa para mexer nos hertz e tal, então acho
#     que nem precisa dessa opção aqui'): o wdisplays é a porta e a
#     persistência E89 é do watch (que grava a mudança por QUALQUER
#     porta); o craft-display segue vivo como CLI do socorro. menu.xml.
#     (5) O EDITOR GRÁFICO DA CASA — mousepad entra na ISO (packages.add)
#     e na ADOÇÃO do canal (rigs recebem na próxima dose) + a associação
#     text/plain quando o dono não escolheu outra (elite-post-transaction;
#     a escolha existente é intocável) + mimeapps do skel. craft-update +
#     packages.add + mimeapps.list + elite-post-transaction. (6) O BRAVE
#     NO CANAL DIÁRIO — o buraco nomeado pela E113 fechado: o
#     publish-packages.yml baixa o brave-origin do asset da release viva
#     (zero rebuild, zero upload de 186 MB por push), repo-add entrega o
#     pin 1.99.57 ao rig, a loja sem pilha cobre o nome, o selo cobre o
#     conjunto, a verificação db↔assets prova. publish-packages.yml. (7)
#     OS OLHOS DO DUMP — o conf do navegador entra na seção 13 (o réu do
#     vídeo mora no papel; a etiqueta sobe para v2.13). craft-dump. (8) O
#     MAPA DIZ A VERDADE — a linha do craft-clean nomeia o cache do
#     navegador (o passo novo). craft-help. Bins de conteúdo mudado:
#     craft-idle, craft-clean, elite-post-transaction, craft-update,
#     craft-dump, craft-help, menu.xml (pele), brave-flags.conf
#     (skel→pacote).
# E115 — O DUMP 224713 PERICIADO + A PALAVRA DO DONO DE 16/11 À NOITE, OS
#     RÉUS COM NOME E CURA (o rig parou na 1.0-59 — a E114 não chegou; a
#     cadeia dos réus que JÁ TEM cura no repo segue viva: o vídeo branco
#     do Brave morre no GL do conf v1.2 que a dose sincroniza ao home; a
#     limpeza pede raiz pelo pkexec GRÁFICO; a porta das telas segue
#     fora; o mousepad o dono confirmou: 'já subiu o mousepad, boa'):
#     (1) O ASSENTO DO MODO DE JOGO — a resposta VISÍVEL ao 'não sei se
#         funciona' (dito TRÊS vezes seguidas): o módulo custom/game na
#         topbar consulta o ESTADO REAL (pgrep gamemoded — o daemon só
#         está vivo com jogo OU manual, a física D-Bus do músculo) e o
#         glifo verde só existe QUANDO o modo está ligado, some quando
#         sai; clique abre o Modo de jogo… — o estado que não se vê não
#         existe para quem usa. craft-game (verbo pill) + config.top +
#         style.top.css.
#     (2) O PLAYER CADA VEZ MELHOR (o pedido: 'quão bom poderia ser o
#         nosso player… sem nenhum bug e cada vez melhor'): o placeholder
#         icon no formato é a porta do mapa player-icons — cada player
#         com o PRÓPRIO glifo (brave/chromium/mpv/vlc/spotify) e o
#         tooltip diz a FAIXA INTEIRA (artista — título). Atalhos de
#         clique e o placeholder dynamic intocados. (E115-corrige: o
#         comentário anterior escrevia os placeholders COM CHAVES e o
#         f-string deste gerador os leu como SUBSTITUIÇÃO — o mesmo réu
#         do E114-corrige, a mesma cura: o papel da casa não brinca com
#         a sintaxe do próprio molde.)
#     (3) AS SKINS DA TOPBAR — a ferida que a topbar repetia do menu
#         E104: config.top/style.top.css moravam SÓ no skel e a barra do
#         rig vivo ficava congelada na era da ISO (nenhum módulo novo
#         chegava NUNCA). Viajam NO PACOTE (/usr/local/share/elite/
#         waybar/) e o craft-rice entrega com a gramática fóssil/
#         marcador (fósseis do git: 25dcb816/56a6e056/74ab03f2 +
#         7b9100f4; personalizado = intocável) e ressuscita o waybar
#         com a pele nova (≤5s — a física do OSD). craft-rice + build.sh.
#     (4) O CHAVEIRO GANHA A RESPOSTA E O FIM DOS POPUPS (o dono: 'eu
#         não sei por que tem o chaveiro do GNOME, sendo que nosso
#         sistema não é GNOME… nem era para ter esse chaveiro'): o
#         gnome-keyring É o provedor da API Secret Service (senhas de
#         apps; NÃO é o desktop GNOME) e nasce na ISO pela BASE upstream;
#         o réu dos popups do navegador é a física: autologin sddm não
#         digita senha (gkr-pam 'could not unlock' no papel — dump
#         seção 11) e o Brave pede o chaveiro a cada boot (o ×2 = a
#         senha do login no chaveiro que não a aceita). CURA DUPLA: o
#         brave-flags.conf ganha --password-store=basic (o Brave NUNCA
#         mais toca o chaveiro — zero popup, senhas no perfil do
#         navegador, o cargo honesto no comentário) e a ISO deixa de
#         nascer com o daemon (packages.remove; o rig vivo o mantém
#         como encanamento de compat até a ISO nova — ninguém mais o
#         acorda). brave-flags.conf + packages.remove + fragmento.
#     (5) O P11-KIT-SERVER some da lista de 2º plano E GANHA RESPOSTA:
#         é o servidor PKCS11 do p11-kit (certificados/confiança TLS —
#         dep do gnutls/mesa: NÃO é removível e NÃO é app — encanamento
#         de sessão). A casca do craft-bgapps o recebe (p11-kit* +
#         gcr*) — o menu encerra PROGRAMA, não encanamento (a lei
#         v2.6.0). craft-bgapps.
#     (6) A LIMPEZA QUE O PAPEL NÃO CONTOU ATÉ O FIM (o clean.log: 5
#         'iniciado' e ZERO 'fim' — o dono fechava a janela no meio e a
#         perícia só tinha a abertura): cada passo deixa linha ANTES de
#         correr (o trace sobrevive à morte no meio) + a linha de
#         abertura nomeia uid/HOME (o modo pkexec fica no papel) + o
#         aviso de duração (cache grande leva até 1 min — a janela não
#         parece morta). craft-clean.
#     (7) O STAMP DA TELA MORRE COM A DOSE: o apply com falha dorme no
#         teto E106 (fail:6 — o rig do dump passou o boot TODO no
#         fail:6, a tela no modo errado até o dono abrir o wdisplays);
#         a cura E113 ficava presa atrás do stamp velho até o reboot.
#         O elite-post-transaction apaga o stamp fail:* dos usuários
#         vivos — o heartbeat do craft-bars re-aplica com o binário NOVO
#         em ≤5s, SEM reboot (os hertz que o dono salvou valem na dose,
#         não no reinício — a pergunta 'vai ficar salvo quando
#         reiniciar?' fica SIM pela física: o watch grava a escolha por
#         QUALQUER porta e o apply a restaura no boot). elite-post-
#         transaction.
#     Skins/skel de conteúdo mudado: config.top, style.top.css
#     (skel→pacote). Bins: craft-game, craft-rice, craft-bgapps,
#     craft-clean, elite-post-transaction.
#     pkgrel 60→61 NO MESMO COMMIT (lei E41).
#     pkgrel 61→62 NO MESMO COMMIT (lei E41) — E116-POLIMENTO (17/11), E33
#     ×2 CURADAS SEM FÍSICA: (1) craft-game gm_off — o rm do game-watch.pids
#     era FANTASMA (o arquivo nunca foi escrito: a fila do watch mora na
#     MEMÓRIA do daemon) e o log jurava 'fila do watch limpa'; o papel diz
#     a verdade (registros do watch saem sozinhos com o jogo — reaper +
#     rodada). (2) craft-menu — o cabeçalho jurava 'contrato com os 6
#     chamadores' e a suíte dizia 'os 7': a contagem real é 12; a prosa
#     fica SEM número que possa apodrecer (o contrato é a gramática
#     0/1/2/143). Bins: craft-menu, craft-game. Suíte: 40-integration
#     (prosa sem número ×2, âncora refrescada).
#     pkgrel 62→63 NO MESMO COMMIT (lei E41) — E117-POLIMENTO (18/11), o
#     dump 163548 (pós-reboot, pós-dose 62) periciado com CINCO réus de
#     nome: (1) O EMBARQUE QUE NUNCA SAIU (a mãe dos réus): o molde do
#     PKGBUILD instalava fastfetch/hyprlock/rc/menu/swayosd/docs/desktops
#     mas NUNCA installou files/usr/local/share/elite/chromium-flags/
#     (E114) nem files/usr/local/share/elite/waybar/ (E115) — os dois
#     foram STAGED no build.sh e ficaram FORA do pacote; o hook
#     sincronizador do post-transaction fazia [ -r $SRC_FLAGS ] → falha
#     SILenciosa → o rig do dono nunca recebeu --password-store=basic
#     (os popups do chaveiro VIVOS: a enchente gcr-prompter do dock.log
#     com lançamentos de brave intercalados) nem os flags Ozone/GPU
#     (o terreno do vídeo branco do YouTube) nem as skins da topbar;
#     cura: as DUAS linhas de install + remoção no molde (a dança da
#     família E91) — a dose seguinte entrega tudo ao rig vivo.
#     (2) craft-display — o apply com adaptive:disabled manda
#     --adaptive-sync off e ESTE wlr-randr (0.5.0) recusa 'invalid
#     adaptive sync state: off' com rc=1: 6/6 tentativas por sessão,
#     stamp fail:6, 150KB de papel de FALHA para um arranjo que na
#     verdade ESTÁ aplicado (200Hz vivo == conf salvo); cura: no ramo
#     da falha, se o stderr nomeia o adaptive sync, o flag morre e o
#     apply RE-RODA sem ele (modo/pos/scale aplicam) e o papel diz a
#     física (o VRR já nasce off no compositor deste build — o estado
#     pedido é o estado default); física do conf/stamp intocada.
#     (3) elite-post-transaction — o veredito do sysctl nunca podia
#     passar: o _want extraído por ##*≠ deixava o PARÊNTESE de fecho no
#     valor ('180)' ≠ '180') e o papel imprimia FALHOU (rc=0 …)
#     (agora:180) — FALHA declarada com o kernel JÁ no alvo (o dump
#     fotografou); cura: o parêntese morre na extração (uma linha).
#     (4) O SEGUNDO TRONO DO SWAYNC (journal: 'Failed to start Swaync
#     notification daemon' ×5 a CADA boot — a ativação corre 4s antes
#     da sessão existir, o craft-bars é quem sobe o swaync vivo): a
#     unit de usuário morre com systemctl --global mask (E58 — um
#     trono só), fail-safe e logado só na mudança.
#     (5) craft-update — a dose do canal usava pacman -Sy --needed:
#     INSTALA peça ausente mas NUNCA ATUALIZA peça atrasada — o pywal
#     do rig ficou 3.3.0-11 contra o 3.3.1-1 do db da casa (o papel
#     jurou 'a casa já estava em dia' — mentira que o dump fotografou;
#     a lei E101 do próprio papel: atualização que CHEGA INSTALA);
#     cura: verificação de versão (vercmp, locale-safe LC_ALL=C) sobre
#     a lista da casa — peça atrasada entra numa segunda passada SEM
#     --needed (atualiza SÓ a casa, o sistema inteiro segue na
#     cadência semanal), log nomeado com o de→para.
#     (6) O PAPEL (família E33-cosmético, curados no mesmo corpo):
#     elite-session-probe WAYBAR_PROCS mostrava a LISTA (pid + cmdline)
#     onde o rótulo jurava contagem — hoje conta e lista em linhas
#     separadas; craft-dump chamava craft-display VIVO de 'ausente —
#     sistema anterior ao 1.0-33' quando o rc≠0 era só sessão ausente
#     (o probe root sem WAYLAND_DISPLAY) e o probe do brave-origin
#     grepava 'Version' contra pacman em pt_BR ('Versão') e imprimia
#     VAZIO — os dois falam a verdade hoje (command -v antes do
#     'ausente'; LC_ALL=C antes do grep).
#     Bins/moldes com conteúdo mudado: craft-display, craft-update,
#     craft-dump, elite-session-probe, elite-post-transaction, o molde
#     do PKGBUILD (2 installs novos). Suíte: 40-integration (âncora
#     refrescada + contratos novos da dose E117).
#     pkgrel 63→64 NO MESMO COMMIT (lei E41) — E118-POLIMENTO (18/11), o
#     dump 210305 (pós-dose-63, a casa SÃ: 0 units failed, suspend ×2
#     limpos, ACK ×6, dose no ar) periciado com o veredito das filas do
#     polimento 13/14 e DOIS réus novos de nome:
#     (1) O PÓS-SONO QUE DORMIA NO IMEDIATO (craft-display — a ordem do
#         dono no papel 210305: 'demorou um tempo aí para aplicar e
#         aplicou do nada… deve reiniciar o que… fica imediato, fica
#         fixo… e que nunca volte para o padrão, seja realmente a
#         configuração que o usuário setou'): o reconcile via a marca
#         fresca do resume e DORMIA a janela de 45s inteira (exit 0 a
#         cada heartbeat — o próprio comentário jurava 'o apply
#         re-assegura o conf salvo' e o código só esperava) e ainda
#         pagava os 6 ticks de estabilidade: o papel fotografou ~74s de
#         tela errada (resume 20:27:00, diverge 20:27:11, REAPLICANDO
#         20:28:14, save 20:28:21). Cura: a marca fresca NOMEIA a
#         divergência ('a reversão do driver não é escolha') e o
#         reconcile REAPLICA no PRIMEIRO heartbeat divergente do
#         pós-sono (≤10s do resume — o imediato é lei); o apply falho
#         re-tenta com UM tick de assento (RESUME_TICKS novo em
#         $RUN_E) e o teto E106 intacto; o save guarda a janela de 45s
#         INTEIRA (a reversão do driver nunca vira escolha do dono —
#         'nunca volte para o padrão' pela física do conf). O boot
#         segue imediato pelo braço que já existia (craft-bars chama
#         apply no arranque; a E117 tirou o flag morto — o papel 210305
#         provou o apply falho 6/6 do boot 15:11 morrer COM o flag e o
#         18:37:04 aplicar OK sem ele: a tela de 200 Hz nasce aplicada
#         no próximo boot, sem clique).
#     (2) O PAPEL SEM BURACO (craft-clean — o papel 210305: DOIS
#         'iniciado' às 21:00:16/18 e ZERO trace depois; a v5 loga o
#         primeiro passo 1 linha após a abertura e o papel mostrou
#         NADA entre eles): (a) a medida do cache (du sob
#         set -euo pipefail) podia matar o script ENTRE a abertura e o
#         primeiro passo — hoje a medida falha e devolve 0 (a medida
#         ruim não vale morte calada); (b) MORTE DEIXA TESTEMUNHO — o
#         trap EXIT registra qualquer saída que não passou pelo 'fim:'
#         (cabeçalho órfão extinto por construção); (c) A PORTA SE
#         NOMEIA — o pai (ppid + cmdline) entra na abertura: o papel
#         210305 mostrou uid 1000 e NENHUMA porta da casa corre
#         craft-clean como usuário (o item do menu é pkexec→raiz) — a
#         próxima corrida entrega a porta dela no papel (fuzzel,
#         terminal, .desktop sobrevivente); (d) o botão não empilha
#         corridas — flock no dir do papel (o mesmo arquivo para as
#         duas portas), a segunda corrida sai com testemunho.
#     (3) O OLHO DA TOPBAR (craft-dump — a fila (e) do 15b sem papel):
#         o papel comparava o menu (200537) e ficava CEGO para a
#         topbar — seção nova: config.top/style.top.css do home vs o
#         mestre do pacote (cmp + sha256) + a contagem do custom/game
#         na pele viva — o assento do modo de jogo ganha prova direta
#         no próximo dump.
#     Confirmações do papel 210305 (ZERO réu novo nelas): dose 63 no
#     ar (elite-system 1.0-63 às 18:37:00) com componentes renascidos
#     ≤3s; E117-2 provado (apply 18:37:04 SEM o flag: 1 aplicado 0
#     falha); resume das 20:27 fotografou a física honesta; status
#     salvo==agora 200Hz; game watch estável (pid 10248, AUTO=1, zero
#     respawn); 0 units failed, 0 coredump; suspend ×2 limpos (selo
#     E88, USB intacto, WoL d); E110 (sysctl 180 vivo) e E101 (casa em
#     dia) confirmados; pywal 3.3.0-11 = esperado (a passada fina da
#     63 entrega 3.3.1-1 na dose 64); toplevel ACK ×6; lock/menu na
#     pele atual; popups/YouTube = juiz ainda é o 1º brave nascido
#     APÓS a morte dos processos de 15:11 (reboot — os flags não mudam
#     processo rodando; as 3 linhas gcr-prompter do dock.log são do
#     brave VELHO recebendo janelas nova); swaync ×5 do boot 15:11 foi
#     PRÉ-mask (18:37) — o próximo boot prova; órfão granite7 nomeado
#     para a limpeza; e o item 'Telas' do menu segue EXTINTO (E114 —
#     o dono ratificou: 'não acho que preciso, pois já tem o programa
#     lá para gerenciar isso').
#     Bins com conteúdo mudado: craft-display, craft-clean, craft-dump.
#     Suíte: 40-integration (contratos E118 novos: imediato do
#     pós-sono ×2, porta/testemunho/travamento da limpeza, olho da
#     topbar; âncora E41 refrescada 63→64).
#     pkgrel 64→65 NO MESMO COMMIT (lei E41) — E118-CORRIGE (18/11): o
#     gate do shellcheck 0.11 do CI pegou o SC2154 do trap do craft-clean
#     ('rc is referenced but not assigned' — o rc=$? dentro da STRING do
#     trap não conta como atribuição para o linter; a suíte LOCAL pulara
#     o gate por binário ausente — a lição: o shellcheck agora corre
#     LOCAL na mesma versão do CI ANTES de qualquer push). Cura: o $?
#     direto no corpo do trap diz o MESMO número e o réu morre; o
#     witness 'MORTE no meio' provado de novo com kill real, e o fim
#     normal segue silencioso. craft-clean mudou de conteúdo.
#     pkgrel 65→66 NO MESMO COMMIT (lei E41) — E119-POLIMENTO (18/11), o
#     dump 221647 (o rig PÓS-reboot com o uso do dono, o julgamento que
#     as filas 13/14/15 esperavam) periciado com a casa SÃ provada e o
#     dono na mesa apontando QUATRO réus, todos com cura:
#     (1) O TOKEN QUE NÃO EXISTIA (config.top mpris): o E115 nasceu com
#         o placeholder ENTRE CHAVES 'icon' e o man do waybar 0.16 nomeia os únicos
#         válidos 'player_icon'/'status_icon' (UNDERSCORE) — o
#         desconhecido renderizava VAZIO e o mapa player-icons era
#         config morta DE NOVO (o rig: 'ele não tem o íconezinho que
#         indica do que é que ele está tocando'). Cura: o token
#         player_icon no format e no format-paused — o mapa acende (brave \uf268,
#         mpv/vlc \uf04b, spotify \uf1bc, default \uf001).
#     (2) O PILLAR QUE NÃO FICA (a ordem do dono: 'quando fechar abas
#         que reproduzem mídias ele suma… só quando ele for chamado e
#         quando for encerrado também ser encerrado na hora'): o
#         chromium MANTÉM o player MPRIS registrado e PAUSADO depois do
#         fecho da aba — a barra mostrava o conteúdo morto com a
#         marcação de tempo congelada (o remanescente que o dono
#         fotografou; a casa já havia curado o stopped no E105, o
#         pausado ficou). Cura: hide-on-paused:true — a resposta NATIVA
#         do man do waybar; o pillar vive SÓ enquanto toca de verdade.
#     (3) A PORTA NO PAPEL (craft-game): o dono clicou 'Ativar agora' e
#         o game.log NÃO TEM UMA linha — o gm_on tem quatro ramos e
#         todos logam, logo o clique morreu ANTES do despacho (o caminho
#         fuzzel→case era cego: o || exit 0 engolia rc≠0 calado). Cura:
#         o despacho entra no papel (a escolha logada + o rc anômalo
#         nomeado; 1/2/143 seguem benignos na lei dos menus) e o ramo do
#         já-ativo (o único sem linha) também deixa testemunho. A
#         próxima perícia vê ONDE a porta falhou.
#     (4) O CANCELAR FALA (craft-shot): 'se aperto o Esc, também ele
#         tira o screenshot… não tem a forma de cancelar nem nada' — o
#         ESC do slurp (rc=1 sem saída, provado no upstream) descia
#         para o grim com geometria vazia e o set -e matava o script
#         SEM voz. Cura: geometria capturada com desfecho nomeado — o
#         cancelar avisa NA TELA ('nada foi salvo'), zero arquivo,
#         zero clipboard.
#     (5) A TELA QUE NÃO ESTOURA (craft-help): 'um monte de comandos…
#         fica cortada pelo tamanho que abre, algumas coisas chegam
#         quebradas' — a lista de internos (22 linhas dim que o dono
#         nunca chama) vira DUAS linhas com a contagem; a lista inteira
#         segue VIVA no filtro (craft-help <termo>) e na doc do pacote;
#         as descrições das portas encurtadas (o wrap quebrava o
#         encaixe). O casamento do filtro e os atalhos REAIS intactos.
#     A CASA SÃ NO PAPEL 221647 (o julgamento pós-reboot): o BOOT APPLY
#     21:29:14 OK NO PRIMEIRO TENTO (a física E117/E118 — os 200 Hz
#     nascem aplicados, sem clique, sem espera); ZERO 'Failed to start
#     Swaync' no journal do boot (a máscara E117-4 PROVADA — o boot
#     anterior tinha ×5); suspend do dono limpo; MPRIS sem player vivo
#     no papel (a lente do E119-2 fotografa o remanescente que ele viu);
#     o elite-system ainda 1.0-63 no rig ('nada para atualizar' — a dose
#     64/65 publicou DEPOIS do bootupdate dele; a próxima dose ao ligar
#     entrega o E118+E119) e o olho da topbar (E118) chega com ela.
#     Bins/moldes com conteúdo mudado: config.top (o mpris), craft-game,
#     craft-shot, craft-help. Suíte: contratos E119 novos + âncora
#     refrescada 65→66 + o contrato E115 do token refrescado (com o
#     nogrep do token morto).
#     pkgrel 66→67 NO MESMO COMMIT (lei E41) — E120-POLIMENTO (18/11), a
#     varredura E33 do craft-rice (o único bin da era E115 que a varredura
#     não tinha visitado — a fila nomeada pelos polimentos 15/15b/15c,
#     cumprida porque o dump novo do dono não chegou) com DOIS réus de
#     papel e UM guard ausente, todos curados SEM mudança de comportamento
#     no caminho feliz:
#     (1) O USO QUE MENTIA POR OMISSÃO: o código entrega TRÊS fragmentos,
#         SEIS peles e SEIS portas; o --help nomeava DOIS fragmentos (o
#         30-elite-organize não existia para o dono que só lê o help),
#         TRÊS peles (as DUAS da topbar E115 nunca foram apresentadas) e
#         DUAS portas (as adoções rc/menu/topbar/skin eram portas sem
#         papel). Cura: o inventário INTEIRO no papel, na ordem da casa.
#     (2) O CONTRATO QUE O PRÓPRIO CÓDIGO VIOLAVA (skin_ensure): o
#         RETORNO jurava '1 = ... cp falhou' e TRÊS ramos (adopt, marcador,
#         fóssil) devolviam 0 COM o cp falho — a renovação morta no disco
#         saía no papel como 'pele mexeu' (o reconfigure corria para nada;
#         o erro engolido sem voz). Cura: cp falho = say honesto nomeado +
#         return 1 — o contrato agora vale em TODOS os ramos (a feliz
#         via permanece byte a byte: mesmo cmp, mesmo cp, mesmo say).
#     (3) O GUARD AUSENTE NO ADOPT (a rede de backup): o --*-adopt gravava
#         a pele da casa POR CIMA do arquivo do dono MESMO com o backup
#         falhado (o cp 2>/dev/null engolido) — a perda de dados do dono
#         esperando o disco cheio. Cura: backup falhou = adoção RECUSADA
#         (o arquivo do dono segue intocado e o papel nomeia a recusa).
#         ACHADO NOMEADO SEM CURA NESTE DEGRAU (a fila do próximo): o
#         fragmento 10-elite-games e a lista da família no 20-ssd estão
#         SOMBREADOS pela regra universal identifier=".*" do próprio
#         20-ssd (mesmo valor 'yes', mesmo alvo) — mortos sob
#         last-match-wins, VENENOSOS sob first-match-wins (defeataria o
#         drop-in do dono); a remoção exige o man do labwc citado + os
#         contratos E54 (2626-2660) reescritos — degrau próprio.
#     Bins com conteúdo mudado: craft-rice. Suíte: âncora refrescada 66→67.
#     E121-POLIMENTO (18/11 — dump 173257): o listener (a corrida
#     request↔diálogo — o réu do terminal em branco da Limpeza), o
#     craft-game (o holder que engasgava o 'Ativar agora' — o manual
#     nunca rodou no rig) e o menu.xml (o item Captura tela inteira).
#     Bins/peles com conteúdo mudado: craft-game, menu.xml, listener.c.
#     Suíte: âncora refrescada 67→68.
# E122 — O PLAYER COM JUÍZO + A POLÍTICA DO DESPERTAR (o relato do dono no
#     dump pós-dose-67 + o relato na mesa do mesmo dia): (1) O PILLAR PEGOU
#     UM RECADO DE WHATSAPP ('ele pegou o áudio do WhatsApp, contou o tempo,
#     botou o ícone do Chrome… e ficou. Eu fechei a página do WhatsApp e
#     ficou lá em cima' + 'tem que saber os sites que são reprodução
#     realmente de necessários para um player, tipo YouTube Music… e tirar
#     isso do WhatsApp, entre outros' + 'assim que encerrar a reprodução ou
#     a página atrelada à reprodução seja fechada… já cortasse essa
#     conexão… um on e off, zeros e uns, conforme o uso'): o módulo mpris
#     interno do waybar só filtra por NOME (ignored-players) — o juízo de
#     ORIGEM e o de ESTADO MORIBUNDO não existem como opção. Cura: BIN NOVO
#     craft-player (a porta do módulo custom/player no config.top) com as
#     três leis — mensagem não é mídia (WhatsApp/Telegram/Messenger/Signal
#     pelo host da url, inclusive blob:, e pelo título QUANDO não há url —
#     o vídeo do YouTube "signal and the noise" não cai no filtro), o ZUMBI
#     morre (browser Playing com posição congelada 2 ticks = aba fechada,
#     MPRIS órfão — sai da barra com linha no papel player.log) e o custo é
#     o MESMO tick de 1s que o módulo interno já polia (agora externo porque
#     o juízo mora fora). A porta de ENTRADA fica intacta: tudo que toca de
#     verdade continua aparecendo (a ordem 'não tem que mexer no que tá
#     quieto'). (2) O DESPERTAR QUE NÃO EXISTIA ('eu tentava fazer ação no
#     teclado, ação no mouse e nada despertava o computador… cliquei no
#     botão de power e aí o computador desligou' + 'que uma ação, por
#     exemplo, no teclado libere… não necessariamente no mouse — pode ter
#     mouse sensível que qualquer toque na mesa ativa'): a perícia do dump
#     182602 seção 10 provou /proc/acpi/wakeup com XHC0/PS2K/PS2M TODOS
#     *disabled — a E24 desarmou TODO controlador USB e o dono fotografou o
#     preço (dormiu e nada acordava; o único wake era o power button que o
#     logind atende como poweroff). E a E108 do idle.log mentiu dias a fio
#     ('systemctl voltou em 0s SEM sono' seguido 1s depois de 'tela:
#     ACORDOU' — a chamada é ASSÍNCRONA, o sono era REAL, ninguém podia
#     acordá-la). CURA ×3: craft-wake-guard v2 com A POLÍTICA (teclado USB
#     HID protocolo 01 + PS2K acorda; mouse e o resto do bus dormem;
#     controlador 0x0c03 armado — a porta do teclado; PS2M dorme; WoL segue
#     morto E90), a regra udev v2 (0x0c03 enabled + RUN do gancho
#     usb-apply) e a UNIT NOVA elite-wake-guard.service (apply a cada boot,
#     multi-user.wants — quem cura os rigs da era E24, cuja .rules velha
#     segue no disco; a varredura pós-coldplug vence porque suspende só
#     minutos depois); craft-vigil + craft-idle: o veredito do sono é O QUE
#     O JOURNAL MOSTRA NA JANELA (Suspending→Awake com duração de parede —
#     'voltou em 0s' nunca provou insônia). E a pécela que o E121 deixou
#     nomeada: o ExecStopPost do elite-firstboot imprimia 'resultado:
#     /bin/bash (exit=/bin/bash)' no rig (dump 184815) — a linha ${{VAR}}
#     atravessava duas expansões; '$$' entrega '$' literal ao sh (uma
#     expansão só, a que lê o env que o systemd.service(5) garante).
#     Bins com conteúdo mudado: craft-wake-guard, craft-vigil, craft-idle,
#     config.top, style.top.css, 90-elite-wake-guard.rules,
#     elite-firstboot.service. Bin NOVO: craft-player. Unit NOVA:
#     elite-wake-guard.service (+wants). pkgrel 68→69 NO MESMO COMMIT (lei
#     E41).
# E123-POLIMENTO (19/11 — a fila E120 fechada e a fonte pedida abriu um
#     abismo): os três drop-ins rc.xml.d (10-elite-games/20-elite-ssd/
#     30-elite-organize) eram FICÇÃO — o labwc NUNCA leu o diretório (o
#     repo inteiro 0.20.3-12 sem uma ocorrência de rc.xml.d; a única
#     porta para múltiplos rc.xml é o --merge-config, commit 698c7ace0
#     de 2024-01, que itera os dirs XDG — não é um .d), as regras eram
#     REGEX num casador que é GLOB (fnmatch(3) FNM_CASEFOLD,
#     src/common/match.c, man 'shell wildcard patterns (see glob(7))' —
#     '^steam_app_[0-9]+$', '^(brave-browser|…)$' e a 'universal' '.*'
#     nunca casaram nenhum app_id; a universal de verdade é a regra SEM
#     identifier — query_str_match sem condition devolve true) e o
#     maximized é CRITÉRIO, não propriedade (quem maximiza é a AÇÃO
#     Maximize no primeiro mapa). AS TRÊS FERIDAS ORIGINAIS (E54 jogos
#     sem botões, 06/nov janelas nuas, E70 área desorganizada) NUNCA
#     foram curadas no rig. Cura: as regras moram NO rc.xml mestre (skel
#     v1.3 — <windowRule serverDecoration="yes"/> sem identifier +
#     <action name="Maximize"/> para brave-browser e Code, com o man
#     citado no comentário) que a pele E101 renova; a LEI DE REMOÇÃO
#     (o marcador é a senha) apaga os fósseis do rc.xml.d nos rigs COM
#     VOZ; o ensure_fragment morto saiu; craft-bars/environment/
#     code-flags.conf/SCRIPTS.md citam o rc.xml mestre.
#     Bins/peles com conteúdo mudado: craft-rice, craft-bars, rc.xml,
#     environment, code-flags.conf. pkgrel 69→70 NO MESMO COMMIT (lei
#     E41).
# E124-POLIMENTO (19/11 — o polimento do uso real, os quatro réus do
#     relato do dono): (1) A LIMPEZA QUE AUTENTICAVA E MORRIA — o item do
#     menu chamava 'pkexec env HOME=… craft-clean' e A FONTE PROVOU
#     (pkexec.c, 'Set PATH to a safe list'): o PATH do alvo raiz é
#     /usr/sbin:/usr/bin:/sbin:/bin:/root/bin — SEM /usr/local/bin, onde
#     moram os bins da casa; o env não achava o craft-clean, o terminal
#     imprimia 'No such file or directory' DEPOIS da senha aceita e a
#     mensagem de fallback MENTIA ('a senha não foi aceita') — o
#     clean.log não recebeu NENHUMA entrada hoje (o réu morreu antes do
#     papel) e ZERO uid:0 desde o nascimento do caminho pkexec (a camada
#     de baixo do congelamento que a E121 curou). Cura ×2: caminho
#     ABSOLUTO /usr/local/bin/craft-clean no item (a classe morre) e a
#     mensagem fala o rc honesto + o papel (a mentira E33 sai).
#     (2) O PLAYER QUE MATAVA O PRÓPRIO BOTÃO — a lei do E119 (só o que
#     toca ocupa a barra) expulsava o PAUSADO: o dono clicava
#     play/pause, a mídia pausava, o pillar sumia E o play não tinha
#     mais onde voltar ('pausou e fechou… não consigo retornar').
#     Cura ×3: pausado com CORPO (título/artista) FICA (glifo pause +
#     classe .paused com cor apagada no style.top.css, o clique retoma);
#     sessão MORTA pausada (metadata vazia — a aba dona fechou e o MPRIS
#     esvaziou, o zumbi da lei 2 no status Paused) SAI; a lei 1 (mensagem
#     não é mídia) migrou para ANTES do juízo de estado (o recado pausado
#     continua não sendo mídia). E o TEMPO DE REPRODUÇÃO entra no pillar
#     (o dono: 'que tenha, por exemplo, o tempo de reprodução'):
#     {{mpris:length}} (µs) entra como campo 7 da leitura do bus,
#     decorrido/total 'm:ss/m:ss' no teto de 40 chars — o título cede o
#     espaço, o total nunca estoura a largura; tooltip fala a faixa
#     inteira + tempo + 'pausado' nomeado. O log do zumbi vira TRANSIÇÃO
#     (uma linha no corte, não uma por tick enquanto o MPRIS órfão
#     durasse — a gramática dos papéis da casa).
#     (3) O STATUS DO JOGO SEM A AULA — o dono: 'esse status é bem sujo…
#     veredito, como o modo de jogo funciona, um monte de sujeira que
#     sinceramente não tem para quê': o banner 'veredito' + as 12 linhas
#     de como-funciona SAIEM do status (a aula mora no --help, que já a
#     tinha); a mesa de fatos fica — gamemode/automático/watch/manual/
#     gamemoded/jogos/log, uma linha cada (o detector E112 do watch FORA
#     segue de pé, com a frase que a suíte ancora).
#     (4) O MENU SEM RECORTE E SEM REDUNDÂNCIA — o dono: 'nomes curtos,
#     resumidos e entendíveis': 'Captura (tela inteira)' cortava em
#     '(tela int…' e 'Ajuda — comandos da Elite' em 'comandos…' na
#     largura do menu — os DOIS itens de captura viram UM submenu
#     (Captura de tela → Região (arrastar) / Tela inteira; os contratos
#     da suíte 'Captura de tela' e command="craft-shot" seguem vivos), a
#     ajuda é 'Ajuda', o idle é 'Trava automática…' (os 4 irmãos de
#     referência — idle.conf, autostart, craft-idle ×2 — seguem a nova
#     voz, E33).
#     Bins/peles com conteúdo mudado: craft-player, craft-game,
#     craft-idle, menu.xml, style.top.css, idle.conf, autostart. Tests:
#     o assert do pausado segue a lei nova do dono + cenários morta e
#     tempo. pkgrel 70→71 NO MESMO COMMIT (lei E41).
# E124-CORRIGE (19/11 — o gate do shellcheck 0.11 do CI pegou o
#     SC2088 do uso() do craft-player: a reescrita do texto deixou o
#     '~/.cache/elite/player.log.' na CABEÇA de uma linha citada — tilde
#     em posição expansível dentro de aspas; o texto ORIGINAL tinha a
#     frase antes do tilde e era verde. A suíte LOCAL pulou o gate por
#     binário ausente (o pulo nomeado no commit fe532c7 — o CI o cobrou
#     na hora). Cura: a frase volta a preceder o tilde; o shellcheck
#     0.11.0 EXATO do CI instalado nesta sessão e o gate EXATO da casa
#     (a lista glob-driven da 20-static) corre LOCAL: 0 avisos. Nota
#     honesta: o '~' não expande em aspas mesmo — a 1.0-71 publicada
#     FUNCIONA (o help imprimia o literal que o usuário devia ler); a
#     cura é para o GATE ficar verde. pkgrel 71→72 NO MESMO COMMIT (lei
#     E41 — craft-player mudou de conteúdo de novo).
# E125 (19/11 — o dump 161746 + o relato do dono em vivo: 'os botões
#     de captura continuam separados', 'o sistema continua tendo muito
#     os três pontinhos assim para completar', 'o status mudou, mas não
#     mudou tudo que eu pedi'). TRÊS réus de nome:
#     (1) O MENU QUE NUNCA CHEGOU — a dose 1.0-72 aterrissou 16:14:31
#     com o submenu 'Captura de tela' NO DISCO e o labwc serviu o menu
#     VELHO o dia inteiro (o dono viu 'separado' o que a casa já tinha
#     unificado). A perícia do dump provou: o rice do boot correu NO
#     autostart (menu renovado 16:15:15, waybar 16:15:15) e o reconfigure
#     de tiro único morreu CALADO — a linha 'reconfigure aplicado' nunca
#     chegou ao bars.log; o labwc lê o menu no PRÓPRIO arranque e o rice
#     corre DEPOIS dele. Cura ×2: o craft-rice re-tenta o labwc-msg até
#     6× (0.5s entre elas) com veredito honesto nos DOIS desfechos (o
#     papel nunca chama de aplicado o que não respondeu — E33) e nomeia
#     o env sem WAYLAND_DISPLAY e o labwc-msg ausente; o craft-update
#     refresh_session renova as peles + reconfigure NA DOSE VIVA (o
#     mesmo esquema do notify_users: raiz via runuser, o próprio usuário
#     direto; WAYLAND_DISPLAY descoberto no /run/user/$uid; guard do
#     craft-bars de pé — o pkill do waybar sem supervisor seria dano —
#     a escola E48: a cura que espera reboot é cura adiada).
#     (2) OS TRÊS PONTINHOS MORREM (a ordem do dono: 'textos completos
#     sem recortes ou sem três pontinhos' — todo '…' de convenção lido
#     como recorte): menu.xml — 'Apps da dock', 'Modo de jogo', 'Trava
#     automática'; fuzzel — 'Tempo de idle', 'Redes Wi-Fi', 'Conexões
#     salvas', 'Bluetooth: dispositivos', 'Editor de conexões',
#     'Atualizar', 'Alterar senha', 'Esquecer', 'Registrar AppImage',
#     'Remover registro', 'Instalar aplicativo', 'Remover aplicativo',
#     'Restaurar snapshot'; terminal/notificações — 'Enter para fechar',
#     'Validando' (hyprlock), 'Extraindo', 'e mais N', 'a transação
#     refaz', o verbo 'Comprimir' (elite-tune + craft-bars, E33 de voz),
#     e o craft-display que mandava o dono para 'Telas…' — porta EXTINTA
#     desde a E114: a mentira E33 sai e a mensagem aponta o wdisplays +
#     o watch que grava. A FONTE do labwc (0.20.3 theme.c) provou o
#     CORTADOR de rótulo: menu.width.max = 200px é o réu do '(tela
#     int…' — todo rótulo da casa agora cabe no cap (o dono nunca mais
#     vê pontinho de recorte no menu). O help do craft-help ainda
#     citava os 'drop-ins do labwc' que a E123 aposentou (E33).
#     (3) O STATUS DO JOGO SEM A ÚLTIMA SUJEIRA — os PIDs e a versão do
#     pacote saem da mesa de fatos (o dono lê ESTADO, não números de
#     processo; a versão mora no pacman; o pid do watch já tem linha no
#     papel desde o nascimento dele). E O PAPEL RECEBE UMA LINHA: o
#     bloco INTEIRO do status a cada clique engolia o game.log (a E121
#     nomeou o réu e o teto E36 só segurava o tamanho) — agora o papel
#     guarda 'status: consultado (estado em uma linha)' e a tela o
#     estado completo. Bins/peles com conteúdo mudado: menu.xml,
#     craft-rice, craft-update, craft-power, craft-connect, craft-game,
#     craft-clean, craft-help, craft-idle, craft-appimage,
#     craft-flatpak, craft-extract, elite-tune, craft-bars, craft-display,
#     craft-rollback, elite-install-stage, exo-open, hyprlock.conf.
#     Tests: âncoras 'Apps da dock'/'Comprimir' refrescadas ×4.
# E126 — O POLIMENTO DOS 12 ITENS (o backlog do dono com protocolo de
#     cobertura total: o print decodificou o tempo do player — o
#     {{position}} do playerctl é MICROSEGUNDO, o '1517519:46' era
#     91051186µs = 1:31 de uma faixa de 2:15; o pill do jogo consultava
#     'pgrep gamemoded' e o daemon que sobrevive ao último cliente deixava
#     o ícone aceso SEM jogo — agora o QueryStatus manda, o watch registra
#     o jogo Steam pelo EXE em steamapps/common, aposenta o gamemoded idle
#     e o clique direito desativa; o despertar fecha a CADEIA (controlador
#     PCI + fonte ACPI do MESMO endereço — o elo que faltava; a regra v2
#     EMBARCA no pacote como /usr/lib/udev/rules.d/91-* e a unit é
#     enable+start pelo elite-post-transaction em TODA transação: o rig
#     nunca mais fica com a política só na ISO); o watchdog do compositor
#     no craft-bars (labwc VIVO E MUDO = 3 strikes, o journal no papel e a
#     sessão encerrada com o greeter na tela — o botão de power descansa);
#     o mutex+timeout do craft-display (a tempestade de contadores
#     duplicados) e a desculpa do stamp fail que EXPIRA (a resolução
#     escolhida volta a gravar); o ícone real do AppImage na dock (o
#     .DirIcon do /tmp/.mount_* pelo /proc — o que o Gear Lever lê) e o
#     steam_icon_* do jogo Steam; a moldura de volta ao sair do fullscreen
#     (o xprop -remove _MOTIF_WM_HINTS da janela steam_app_* — o
#     xorg-xprop entra na ADOCAO); o Papirus-Dark de volta por ordem do
#     dono (packages.add + ADOCAO + settings.ini + guarda E16) com o
#     destaque MAUVE do menu; a pele CSS do OSD de volume; o LACT só em
#     AMD (NVIDIA/Intel perdem o daemon e o pacote no install-stage e no
#     firstboot); a LOJA Flathub gráfica (craft-flatpak loja + a porta
#     'Loja de apps' no botão direito + o Okular); o craft-help adaptativo
#     à largura do foot (initial-window-size-chars=88x28); os rótulos
#     fuzzel ao cap de 26. pkgrel 73→74 NO MESMO COMMIT (lei E41).
#     A cadeia E125 (o menu que nunca chegou + os três pontinhos + o
#     status sem pids): pkgrel 72→73 NO MESMO COMMIT (lei E41).
# E126-corrige — O GATE QUE O LOCAL NÃO TINHA: o shellcheck 0.11 do CI
#     pegou o SC2154 na vitrine da loja (o cifrão grudado no sufixo
#     FALSE no lugar do expandidor do ACUMULADOR com chaves — a
#     concatenação perdia a lista e a vitrine mostrava SÓ a última
#     linha da busca); a suíte local pulou o gate
#     por binário ausente (o pulo nomeado de sempre) — o shellcheck
#     0.11.0 EXATO do CI instalado NESTA sessão e o gate EXATO da casa
#     (a lista glob-driven da 20-static) corre LOCAL: 0 avisos em 66
#     scripts. Uma linha de cura. pkgrel 74→75 NO MESMO COMMIT (lei E41
#     — o craft-flatpak mudou de conteúdo de novo).
# E128 — A CONSTITUIÇÃO ENTRA EM AÇÃO NO PACOTE (2026-11-20): (1) A
#     CADÊNCIA NO BOOT MORRE — a família elite-channel/bootupdate/sysupdate
#     (service E timer, as três eras do automatismo) sai da ÁRVORE (rigs
#     novos não nascem com ela), é disabled+MASCARADA pela elite_cadencia
#     do craft-update (toda porta) e pelo elite-post-upgrade (o post_upgrade
#     do pacote, commit seguinte) — a revogação da E51 por AGENTS.md §5;
#     a dose sob demanda ganha a porta canônica elite-update (pkexec);
#     (2) A REGRA POLKIT DA CASA embarca (50-elite-wheel.rules — wheel
#     local ativo sobe craft-clean/elite-update SEM senha, sem wildcard);
#     (3) O OKULAR SAI e o BAZAAR NASCE adotado (apenas Papers + Bazaar
#     moram na casa — org.kde.okular uninstall + --unused idempotentes).
# E129 — A MIGRAÇÃO AUTÔNOMA + O FRAME 0 (2026-11-20): (1) O
#     elite-post-upgrade NASCE (o corpo do post_upgrade/post_install do
#     PKGBUILD — AGENTS.md §4: o dono NUNCA roda comando manual de
#     pós-instalação; o rig já instalado RECEBE a cura no pacman -Syu SEM
#     depender do firstboot-done): daemon-reload, a cadência E128
#     disable+mask no rig vivo, o systemd-time-wait-sync MASCARADO (o -31s
#     do arranque morre), systemd-tmpfiles --create, sysctl --system, os
#     tokens de GRUB (zswap=0 + THP madvise com o fóssil always SAINDO —
#     grub-mkconfig SÓ se mudou), o helper do polkit com 4755 de fábrica +
#     reset-failed, o okular fora e o qt6ct.conf da casa nascendo SE
#     AUSENTE nos homes vivos (Papirus-Dark) com o rice + labwc
#     --reconfigure na sessão — IDEMPOTENTE por desenho (rodar 2× = mesmo
#     estado); (2) O FRAME 0 DO RELogin: o autostart limpa os órfãos do
#     o dir elite do XDG_RUNTIME_DIR (sockets/stamps/locks que mentem à sessão
#     nova) e roda o craft-display apply-boot SÍNCRONO (uma passada — os
#     27s/6 ticks de retry eram tela errada no relogin; o do_apply do
#     supervisor mantém o teto E106 por baixo); (3) A DOCK DEVOLVE O
#     GDKPIXBUF (o .DirIcon do AppImage decodificado não fica agarrado a
#     botão morto — o clear() na saída suave e no rebuild); (4) as FLAGS
#     VA-API do Brave entram em PRODUÇÃO (decode por GPU de fábrica — o
#     compositing Vulkan segue fora pela prova E114 do próprio rig); (5)
#     o THP madvise no elite-tune (a mesma migração da porta do tune).
#     pkgrel 76→77 NO MESMO COMMIT (lei E41 — elite-post-upgrade nasceu,
#     craft-display/dock-gui/tune/brave-flags/autostart mudaram de
#     conteúdo, qt6ct mestre novo no pacote).
# E130 (lei E41, âncora viva refrescada): pkgrel 77→78 NO MESMO COMMIT
#     (lei E41) — a ordem do dono de 2026-11-21 em DUAS etapas
#     de engenharia convergindo nesta dose: (1) A HARMONIZAÇÃO DO SONO
#     E88↔E122 (elite-sleep-report isenta a cadeia do teclado — XHC0/PTXH
#     e as portas 1-8/1-9/3-3 — e
#     sela só os réus espúrios; elite-resume-usb chama o craft-wake-guard
#     apply; a sonda do craft-dump verifica a regra 91 viva); (2) AS PELES
#     EM HOMES VIVOS (themerc-override mauve + settings GTK Papirus-Dark +
#     qt6ct como peles E91 no craft-rice, mestres no pacote, e a linha de
#     ícones garantida pelo post-transaction); (3) O OKULAR NÃO RENASCE
#     (uninstall em TODA transação); (4) O REBUILD FANTASMA DO GRUB MORRE
#     (mkconfig só se mudou) e os HEADERS do kernel acompanham o dkms
#     NVIDIA nas três portas; (5) A CADEIA COMPLETA de ícones AppImage na
#     dock (Gear Lever → cache → extração em thread) e o gm_whois no hook
#     do jogo. Bins com conteúdo mudado: elite-sleep-report,
#     elite-resume-usb, craft-dump, craft-wake-guard (comentário),
#     craft-rice, elite-post-transaction, craft-game, elite-tune,
#     elite-install-stage, craft-dock-gui. Mestres novos no pacote:
#     themerc-override + settings GTK3/GTK4 (theo_install/gtk_install).
# E132 (lei E41, âncora viva refrescada): pkgrel 78→79 NO MESMO COMMIT
#     (lei E41) — A FUNDAÇÃO RUST DA CASA (a ordem do dono: espremer o
#     limão): o workspace crates/ compila NO build deste pacote (2.0: a
#     fundação crates/elite-core + crates/craft-dump-rs entram com os irmãos)
#     (makedepends rust+cargo EXCLUSIVO — zero toolchain na ISO e no
#     pacote final, o binário é o que viaja; o tar é a fonte do makepkg
#     porque source=() não aceita diretórios; a lição E131 no comentário
#     do build(): lto=fat/codegen-units=1/strip=symbols moram no
#     [profile.release] do Cargo.toml, NUNCA no RUSTFLAGS — o
#     embed-bitcode do lto quebra a build). O elite-daemon nasce:
#     craft-game watch e craft-bars DELEGAM a ele (detecção /proc +
#     GameMode + EPP + debounce de 3s; supervise dos QUATRO residentes
#     com backoff 2s + o daemon.conf mestre no pacote). O .cargo/config.toml
#     do workspace casa o build local com o CI (SÓ target-cpu=x86-64-v3).
#     Bins com conteúdo mudado: craft-game, craft-bars. Mestres novos no
#     pacote: daemon.conf (dc_install) + rust-workspace.tar.gz (fonte).
# E135 — A MISSÃO DO DONO (dump 101339, lei E41: o bump viaja NO MESMO
#     COMMIT do conteúdo): o motor nativo zero-latência —
#     (1) O LOOP DE 809 RELANÇAS MORRE: o supervise ganha O GATE DE
#         POSSE (flock por vaga em $XDG_RUNTIME_DIR/elite/ + o nome no
#         session bus pela gramática nova `nome::bus::comando` — o
#         swaync dono de org.erikreider.swaync.cc é ADOTADO, nunca
#         relançado por cima; a cura da chave morta image-visibility
#         vai no skel E no elite-post-transaction dos rigs);
#     (2) O LANÇADOR ÚNICO: a porta `elite-daemon session` (clientes de
#         display + residentes na mesma vaga, gate duplo) — o craft-bars
#         shell vira `exec elite-daemon session` (os 8 /bin/sh do ps
#         morrem no exec(2); o corpo bash segue como fallback dos rigs
#         sem o binário);
#     (3) ZERO POLLING: os ouvidores NATIVOS dormem no daemon — netlink
#         uevent (som → craft-audio-route --once; drm → craft-display
#         apply), logind PrepareForSleep(false)/Unlock → craft-display
#         apply, session bus NameOwnerChanged → SIGRTMIN+9 na waybar (o
#         fork do craft-bgapps a cada 5s — 25% CPU + zumbis pkill do
#         dump — morre; o módulo custom/bgapps vira signal 9/interval 0)
#         e o toplevel.sock EVT acorda o loop do jogo (a detecção por
#         EVENTO + inspeção única de /proc; o tick de 5s sobrevive só
#         como cinto dos windowless);
#     (4) O MODO DE JOGO COMPLETO NO NATIVO: GPU power_dpm_force_
#         performance_level=high (o valor anterior devolvido ao sair),
#         Não Perturbe do swaync por D-Bus nativo (GetDnd/ToggleDnd
#         simétricos) e o inhibitor lock do logind (o lock/apagamento
#         de tela não morre na partida — solto no fim);
#     (5) O DRIFT 150≠180 MORRE NA FONTE: `swappiness = 180` no
#         zram-generator.conf (a opção do gerador é a última palavra no
#         swapon — o systemd-zram-setup não recoloca o 150 DEPOIS);
#     (6) A DOCK: snapshot FRESCO antes da decisão ACT/MIN (os ACT
#         repetidos e timeouts de 2s do toplevel.log do dump morrem), o
#         backoff de reconexão 5→20→100ms no canal EVT e o flush
#         síncrono do frame (queue_resize + display flush no mesmo
#         ciclo do snapshot).
#     Provas: cargo test 53/53 (39+14); cargo check da camada gui com
#     GTK4 4.18.6 real (o prefixo pkg-config sem root); shellcheck 0
#     avisos; suíte completa GO.
# E-auditoria 2026-11-22 — A CURA DO CANAL 44945339468 (lei E41: o bump
#     viaja NO MESMO COMMIT do conteúdo): a craft-dock-rs do E134 NUNCA
#     compilou no CI (o Test Suite passa porque a camada lógica é
#     std-only atrás da feature gui) — o ui.rs foi escrito contra API
#     inexistente e a build do pacote morreu com 9 erros Rust:
#     (1) 'use gtk4::{{gdk, glib, gtk}}' — o gtk4 0.11 NÃO re-exporta um
#         módulo 'gtk' (os widgets moram na RAIZ do crate): o alias
#         'use gtk4 as gtk' mantém os ~120 caminhos 'gtk::' do corpo;
#     (2) o gtk4-layer-shell 0.8 NÃO expõe funções livres
#         (init_for_window/set_layer/set_anchor/auto_exclusive_zone_enable/
#         set_keyboard_mode/set_namespace tomavam &window) — a API é o
#         TRAIT LayerShell com métodos no window (is_supported segue
#         função livre, re-export da raiz; a fonte 0.8.1 baixada provou
#         cada assinatura — set_namespace(Some(&str)) inclusive);
#     (3) TICK_S (u64) → timeout_add_seconds_local espera u32 (o cast
#         nomeado no ponto; os Duration::from_secs(TICK_S) inteiros);
#     (4) o duplo Option de with_client(|c| c.list()) — list() já
#         devolve Option<Snapshot> e o with_client envolve em OUTRA
#         camada: o braço vivo é Some(Some(snap)), o resto degrada ao
#         fallback honesto do lançamento (E71 intacta).
#     Provas: shellcheck 0.11.0 0 avisos em 67 scripts; cargo test
#     --no-default-features 51/51 (39 daemon + 12 dock); os 13 caminhos
#     gtk:: e o trait verificados contra o fonte gtk4-0.11.5 e
#     gtk4-layer-shell-0.8.1 baixados; o GO canônico da camada gui é o
#     CI (sandbox sem pkg-config gtk4 — a lei do degrau do Cargo.toml).
# E133 — O FECHAMENTO DO DONO (lei E41: o bump viaja NO MESMO COMMIT do
#     conteúdo): a dose 1.0-79 foi PUBLICADA (o asset elite-system-1.0-79
#     está na release v2.11.3 com o elite-local.db listando ela) — o
#     fechamento leva pkgrel 80: os rótulos PT-BR naturais de TODOS os
#     menus (menu.xml/craft-power/craft-connect), o craft-clean v6 (DUAS
#     FASES com perguntas [s/N] e --auto-safe), a cadeia de ícones
#     UNIVERSAL da craft-dock-rs (.exe Wine/Proton com extrator PE/ICO
#     std-only + caches de jogo Steam/Lutris/Heroic/Hydra + adjacente ao
#     binário) e a decoração de janela garantida no rc.xml (XWayland na
#     tela cheia).
# E136 — A MISSÃO PARTE 2/2 DO DONO (lei E41: o bump viaja NO MESMO
#     COMMIT do conteúdo): a migração e a otimização extrema do sistema
#     instalado, partindo do dump 101339 (a PARTE 1/2 do E135 entregou o
#     motor nativo; ESTA fecha a mesa):
#     (1) O KERNEL MODERNO — scx_loader com scx_lavd sob demanda (a
#         drop-in ConditionPathExists=/sys/kernel/sched_ext: kernel sem
#         sched_ext = unit PULADA, não FAILED; o loader é o watchdog, o
#         BORE é o chão), ntsync no boot + udev 0666 (o Proton/Wine
#         moderno sem esync/fsync), nct6775 + lm_sensors + sensors-detect
#         no firstboot, MGLRU enabled=7 via tmpfiles e THP madvise (a
#         E132 já o tinha; agora com o MGLRU ao lado);
#     (2) O SYSCTL CONSOLIDADO — 99-elite-performance.conf ÚNICO (a ordem
#         do dono nomeou o arquivo): swappiness 15 com zram zstd ativo,
#         BBR+fq dentro, régua 180/160/150 MORTA pela ordem nova nos DOIS
#         donos do número (conf e zram-generator — a lição E135 com 15);
#     (3) MANGOHUD 3 PERFIS zero-config (minimalista/balanceado/
#         diagnostico em /usr/local/share/elite/mangohud + o toggle
#         elite-mangohud de symlink) e o OPTISCALER da casa (o wrapper
#         elite-optiscaler inject/remove/run — binário de terceiro NUNCA
#         no pacote, o release do dono é a fonte);
#     (4) A CURADORIA — gnome-text-editor é o editor gráfico padrão
#         (mousepad ao packages.remove), overskride+bluetooth.service
#         limpos, lm_sensors/nvme-cli/usbutils/dmidecode na ISO, gparted
#         com o cinto xhost X11, snap-pac+btrfs-assistant no Btrfs opt-in;
#     (5) O MENU ≤16 (rótulos de no máximo 16 caracteres, a lei dos 16)
#         e os ATALHOS UNIVERSAIS 60%/75% do Aula F75 Max (W-Print,
#         W-S-s, W-bracketleft/right, W-S-Up/Down/m, W-S-space/Left/
#         Right — nenhum gesto depende de tecla ausente);
#     (6) O craft-clean ganha o pulso do fim (systemctl --failed) e o
#         craft-dump fotografa o kernel moderno inteiro (scx/ntsync/
#         sensores/MGLRU/BBR/cmdline).
# E139 — A DOSE DA AUDITORIA DO 1.0-86 (lei E41: o bump viaja NO MESMO
#     commit do conteúdo; as 8 freias da auditoria aprovada com os DOIS
#     ajustes cirúrgicos do dono):
#     (1) A DOCK QUE CURA OS PRÓPRIOS PINS (craft-dock-rs): a escada de
#         normalização ÚNICA (resolve_pin: id fold → stem → cauda sem o
#         prefixo gearlever_ → tokens com fronteira → O ARQUIVO REAL nos
#         dirs XDG) serve EXIBIR E JULGAR — o pin "gearlever_Hydra" cujo
#         .desktop real é "gearlever_9f2a_Hydra" resolve, ATUALIZA e
#         MANTÉM (nunca podado); morto de verdade = 2 faltas seguidas e
#         PODOADO com escrita atômica tmp+rename — o loop do 'pin
#         ignorado (desktop inexistente)' morre; o unpin do craft-pin é
#         respeitado NA HORA (re-leitura antes de escrever);
#     (2) A DOSE SOBREVIVE AO TERMINAL (craft-update --sistema): o
#         precheck limpo (checkupdates em db TEMPORÁRIO — sem pendências
#         = 'Sistema já atualizado.' e SAÍDA, sem snapshot PRE gasto, sem
#         -Syu, sem linha no log), trap '' HUP + wait (o pacman herda a
#         surdez ao terminal que morreu) e o papel calado no sucesso (a
#         dose boa é do pacman.log); o pavucontrol SAI da ADOCAO (pacote
#         opcional não é âncora — a ISO já o traz e o botão tem fallback
#         honesto);
#     (3) A DETECÇÃO DE SESSÃO DE VERDADE (elite-post-upgrade +
#         craft-update refresh_session): o pgrep -x craft-bars nunca
#         casou desde a E135 (o craft-bars EXECA o elite-daemon) — o
#         falso positivo 'supervisor AUSENTE' em toda dose e o respawn
#         que não acontecia; agora as DUAS eras pelo comm certo, o
#         SIGTERM limpo colhe o daemon com os filhos e UM novo nasce;
#     (4) O SCX ALINHADO + (5) A TELA QUE LEMBRA SEMPRE: os ouvidores
#         (netlink som/drm, logind sono/unlock, bus bgapps) mudam para a
#         PORTA session (viviam SÓ no corpo do jogo, vaga condicionada
#         ao AUTO — o rig com AUTO=0 acordava cego: display sem
#         save/apply, áudio sem roteamento) e o watch-save é VAGA
#         supervisionada (a escolha do wdisplays grava de novo);
#     (6) O DESPERTAR CIRÚRGICO POR CONTROLADOR (craft-wake-guard v3 +
#         regra 91 sem o armo cego): só PERMANECE armado o controlador
#         0x0c03 com TECLADO HID 01 na própria árvore (o XHC0 do
#         Bluetooth Intel desarma), os não-teclados USB disabled
#         FORÇADOS no apply E reafirmados no pré-sono, o SELO de pontes
#         (GP12/GP13/SWUS/SWDS) passa a valer NO BOOT e o WoL morre por
#         FORÇA (sysfs + ethtool);
#     (7) O SOM QUE NÃO SE DEIXA ROUBAR (craft-audio-route): o --once
#         ganha snapshot de conhecidos (só QUEM CHEGOU vira default — a
#         escolha manual do dono nunca é pisada) e a dupla nova
#         --sleep-save/--resume devolve o default pré-sono quando o
#         HDMI/DP do monitor sequestra o som no wake (o daemon dispara
#         com colheita e teto de 3s antes do freeze); o ppfeaturemask
#         AMD é VERIFICADO na dose (conf nasce se ausente + initramfs
#         quando nasceu);
#     (8) O PAPEL QUE SE CONHECE (craft-dump + a rotação): boot id +
#         uptime + versão do elite-system na cabeça do papel (a
#         fronteira entre a história velha e ESTA sessão), o bloco
#         RUNTIME DA CASA (swappiness vivo × lei 180, zramctl,
#         scx_loader, ppfeaturemask, o status do wake-guard com o gate
#         por controlador, a família de sessão) e a ROTAÇÃO integrada:
#         o post_upgrade poda ~/.cache/elite/*.log de cada usuário +
#         /var/log/elite-*.log (256 KiB) e CEIFA os atalhos appimage-*
#         mortos (Exec sem alvo); o craft-clean fecha o trio na mão.
# E140 (a dose do DOSSIÊ 1.0-88 — o desktop nativo): pkgrel 87→88 NO
#         MESMO COMMIT (lei E41). A TOP BAR É O CRAFT-BAR-RS (novo crate
#         do workspace: relógio pt_BR FIXO que nunca muda de texto, o
#         áudio pelo wpctl com mute instantâneo no clique, a rede com
#         ícone PERSISTENTE abrindo iwgtk/nm-connection-editor, o
#         bluetooth dedicado no blueman, o pill do jogo no SIGRTMIN+8 e
#         a sessão em PopoverMenu NATIVO — o waybar aposenta: sai do
#         packages.add, entra no remove, o daemon troca o cliente de
#         display e o post_upgrade encerra o processo velho); A DOCK
#         v2 (o clique EXCLUSIVAMENTE no released com tolerância de
#         arrasto <5px — o press×click duplicava o verbo no mesmo
#         segundo; a assinatura EVT não falece por silêncio — timeout
#         NÃO é queda, o 'espaço preto' do dossiê morre; o botão
#         direito ganha o popover Fixar/Desafixar/Nova janela/Fechar —
#         a gaveta fuzzel dos pins aposenta com o craft-pin-pick); O
#         JOGO VISTO PELA JANELA (a PORTA 5: steam_app_* viva no
#         toplevel = o daemon é PROXY no GameMode — o Stardew do Hydra
#         que o /proc não nomeava; o wine64-preloader entra na família
#         ERE); O DESPERTAR SEM FALSO TECLADO (o áudio USB classe 01
#         dorme SEMPRE — o Fifine com interface HID de volume armava o
#         XHC0 inteiro); O COOLERCONTROL DE VERDADE (coolercontrold na
#         dose + o override .desktop com --disable-gpu que cura a tela
#         branca do qt6-webengine); O SCX QUE CHEGOU (scx-scheds na
#         ADOCAO + garante_ancoras_vivas — a unit que a adoção acabou
#         de trazer ganha o enable --now na MESMA corrida); O SUSPENDER
#         NO MENU do desktop + o timing do sleep-hook (a vigília espera
#         o veredito do journal ≤5s — o screenon não dispara no limbo);
#         o HDMI cede para a analógica com o piso de volume 40% no zero
#         (o marcador audio-hdmi-ok respeita quem QUER o monitor); o
#         mousepad sai dos rigs e o fóssil zram 150 de /usr/lib idem.
# E144 (a dose da RECONSTRUÇÃO VISUAL — pkgrel 93, a ordem do dono nos
#      testes reais da 1.0-92): a identidade roxo/escuro ELITE unificada
#      (THEME_CSS com a paleta #13111c/#1b1829/#3b3355/#9d7cd8/#bb9af7/
#      #e6e4f0, carregada com STYLE_PROVIDER_PRIORITY_USER em barra,
#      dock e craft-tools — nenhum cinza claro do GTK sobrevive); a top
#      bar no CenterBox com relógio em HORÁRIO LOCAL (glib now_local —
#      o epoch puro vestia UTC) + CALENDÁRIO GTK4 no hover + notificações
#      no esquerdo e DND no direito; a esquerda minimalista (botão
#      Aplicativos com ícone GTK + menu rápido no direito; as pílulas
#      1 2 3 4 e o título ativo SAEM — a mesa é scroll/atalho do labwc,
#      o título é da moldura); o seletor rápido de REDE em popover GTK4
#      (toggle Wi-Fi, redes para conectar direto, status do cabo,
#      nm-connection-editor avançado); o bgapps veste ícone real
#      (system-run-symbolic — o '\uf085' quebrado sai); o IPC com lock
#      de sessão no tmpfs PRIVADO ($XDG_RUNTIME_DIR/elite/session.lock —
#      o os error 13 do /tmp morre) e teto de 500ms no connect (a classe
#      dos 49s morre); a dock requeia draw+resize no evento do toplevel
#      (o espaço preto fantasma morre); o craft-dump PROFUNDO de volta
#      (hardware/GPU/VRAM, RSS/CPU%/cmdline, sysctl, scx-lavd, PipeWire,
#      wlr-randr, journal -p err, pacman, SUDO_UID, --upload termbin);
#      o scx-lavd.service DIRETO (o scx-scheds não traz .service — a
#      unit da casa roda o /usr/bin/scx_lavd, desligando o loader
#      genérico); o post_upgrade migra o autostart dos homes vivos,
#      aplica mitigations=off nowatchdog no GRUB, debloat waybar/gpsd e
#      oculta os .desktop órfãos; o sudoers 99-elite-clean (!insults).
# 1.0-94 (E145 — a dose dos testes reais da 1.0-93 no rig do dono): a
#      ARMADURA RT na barra/dock (todo SIGRTMIN..SIGRTMAX handled desde
#      o 1º instante — a morte "real-time event" e o TOPBAR_COUNT=0 do
#      respawn em loop); o DONO ÚNICO do bus (o modo game vira CLIENTE
#      publicante: o bind duplo matava o socket da sessão no caminho —
#      o "bus.sock MORTO" com os dois daemons vivos); o pkexec na
#      frente do elite-clean da GUI (a porta --as-root recusava como
#      usuário: "Limpeza não completou"); o probe nunca mais CRIA o
#      bars.lock root:root no runtime do dono; os menus "Modo de jogo"/
#      "Trava automática" abrem os PAINÉIS (craft-game menu já existia
#      — o menu.xml chamava o toggle mudo; craft-idle menu nasce); o
#      craft-apps dá à gaveta MEMÓRIA (W-d de novo fecha); o dump v2.1
#      (bus de 3 estados, pactl/idle.conf do dono no pkexec, perícia
#      dos erros benignos do boot, caudas dos papéis, lavd dorme
#      nomeado); os dirs de sudoers/polkit vestem 750 (o aviso do
#      pacman cala).
# 1.0-95 (E146 — O RELATORIO-FINAL periciado, causa raiz por causa
#      raiz): (1) A COVEIRA — os 6 <defunct> pendurados no pid da barra
#      (swaync-client ×4, brave, craft-shot): a solta() abandonava o
#      Child no Drop; a thread dedicada agora colhe o wait (o
#      process_group segue — a ferramenta não morre com a coveira); o
#      dismiss_overlays da dock idem (o pkill solto virava zumbi);
#      (2) A CURA DOS ARQUIVOS DE SESSÃO — o autostart do home do dono
#      com 8 lançadores `elite-daemon session &` injetados por sed cego
#      FORA do repo (o literal com caminho completo NUNCA existiu no
#      git — o pickaxe prova; o flock E30 segurou o dano em 1 dono):
#      nasce o elite-heal-sessao (audita nº de lançadores + sh -n +
#      XML; corrompido = reconstrução do MESTRE do pacote com prova
#      pós-escrita e restauração em falha; o mestre do autostart
#      viaja no pacote pela 1ª vez — skel é veículo da ISO); o
#      post-upgrade chama por /home/* (a migração 1.0-93 por append
#      morre: append não detecta corrupção); (3) O MENU — o texto
#      órfão fora de tag desde o E103 (a abertura do comentário foi
#      amputada por edição de era; periciado no fonte: o labwc
#      PULA texto no parse — lab_xml_skip_text — mas a casa não
#      entrega membro fora de tag): template curado + julgamento
#      ESTrito no heal e na suíte (menu_ok); (4) A ROTAÇÃO — os 28
#      .bak-* acumulados no rig (craft-rice nascia um por renovação):
#      bak_unica (1 por base) + saneia_baks no heal; o xmllint vira o
#      juiz principal do XML no rice (python3 fallback); (5) O RICE
#      ALCANÇA TODO HOME — a lacuna loginctl list-users (dose com o
#      dono deslogado = peles nunca renovadas — o menu do rig ficou
#      UMA era atrás): /home/* uid>=1000 é a fonte; (6) O DUMP --full
#      — o consolidado limpo (o script ad-hoc do rig enterrava os
#      logs reais sob 16 mil linhas de .bak/Brave/PNG): whitelist
#      estrita de configs ativas, logs COMPLETOS, journal user+
#      system, veredito de XML, zumbis nomados, UM .txt + .tar.gz;
#      (7) O GUARD COM VOZ — a 2ª instância do daemon sai 0 DEIXANDO
#      PAPEL (a recusa repetida é a assinatura do autostart doente).
# E147 (A DOSE 1.0-96 — A RECONSTRUÇÃO DA CAMADA DE UI/UX, a ordem do
#      dono: "abandone o que não funcionou e refaça a camada de
#      interface, controles rápidos e integração de sessão com uma
#      arquitetura limpa, coesa e bem pensada de UI/UX"):
#      (1) O CONTRATO DE INTERAÇÃO ÚNICO da craft-bar-rs — clique
#          ESQUERDO abre SEMPRE o popover nativo do módulo (a central
#          de áudio unificada Saída+Entrada com mute imediato, slider
#          com commit debounce de 150ms, troca de dispositivo a um
#          clique e o mixer completo; o painel de Bluetooth com power
#          e conectar/desconectar a um clique pelo bluetoothctl) e o
#          DIREITO abre a ferramenta avançada de verdade (pwvucontrol,
#          nm-connection-editor, blueman-manager);
#      (2) O GLIFO NERD QUEBRADO MORRE PELA RAIZ — a fonte GTK padrão
#          não fala Nerd (o texto de escape na barra era o codepoint
#          sem fonte): TODOS os ícones da barra vêm AGORA de
#          Image::from_icon_name (audio-volume-*, network-*,
#          bluetooth-*, input-gaming, battery-*, system-shutdown);
#      (3) O MÓDULO DE 2º PLANOS MORRE INTEIRO (a ordem do dono: "deve
#          ser completamente removido") — o botão e a Msg da barra, o
#          ouvidor bus bgapps e o SIGRTMIN+9 do daemon, o bin
#          craft-bgapps do pacote (o post-upgrade ceifa o fóssil com
#          voz e a suíte proíbe a volta);
#      (4) O CONFLITO BLUEMAN MORRE — o elite-clean PARA de remover o
#          blueman (a constituição §7 o nomeou como a ferramenta de
#          Bluetooth da casa; o rc.xml e a barra o chamam) e DEVOLVE o
#          pacote ao rig que já o perdeu (pacman -S --needed; o rig do
#          dump o tinha AUSENTE e o clique não respondia a nada);
#      (5) A DOCK VESTE O CICLO DE VIDA DOS POPOVERS (a evidência: o
#          'Gtk-WARNING: Finalizing dockbtn … still has children left:
#          GtkPopoverMenu' e os espaços pretos órfãos) — o repack
#          popdown()+unparent() o popover de TODO botão morto antes da
#          remoção e queue_resize() fecha o ciclo no mesmo frame;
#      (6) O PS HONESTO — o motor do modo game veste argv0
#          "elite-daemon-game" (a duplicidade 'elite-daemon x2' do
#          rig era o session + o motor com o MESMO nome: o ps agora
#          diz o papel de cada um);
#      (7) AS PELES DO SKEL CHEGAM AOS RIGS VIVOS — o post-upgrade
#          entrega o que o dono NÃO tem de /etc/skel/.config (swaync,
#          gtk-3.0, gtk-4.0, fuzzel), arquivo presente = intocável,
#          idempotente por desenho; os bins craft-apps e
#          elite-heal-sessao vestem 0755 no git (o pacote copiava o
#          modo 644 — o craft-apps sem +x do rig do dono era ESTE
#          buraco); os 2º planos saem da ajuda nativa e do dump;
#      (8) A SUÍTE veste os contratos novos: parse do wpctl status
#          (a central), dispositivos BT, rótulos humanos §5, ícones
#          por nome, bgapps proibido de voltar, skel sync, blueman
#          devolvido. Provas: cargo test --workspace --no-default-
#          features 144/144 ZERO avisos (rustc 1.100.0 no sandbox),
#          bash -n nos scripts, XML parseando, pkgrel 95→96 NO MESMO
#          COMMIT (E41). Sem tag (L4).
# BLOCO 4 (1.0-98) — A TELA DE BLOQUEIO E A TELA DE LOGIN VESTEM A PALETA
#      OFICIAL (a diretriz: unificar lock + greeter com a linguagem do
#      desktop/docs/skills/ e publicar a 1.0-98):
#      (1) A LOCK SKIN v8 — o hyprlock.conf aposenta a aproximação da era
#          v5/v7 (a paleta antiga do theme.conf do SDDM: #D8D8D8/#ABB2BF/
#          #5a6477/#1E2128/#5294E2/#E06B74) e veste OS TOKENS OFICIAIS
#          (docs/skills/02-paleta-oficial.md): relógio #f8fafc (o mesmo
#          do relógio da barra) · data e texto #cdd6f4 · campo na ilha
#          #181825 translúcida com borda INATIVA #262637 e
#          foco/validando #a855f7 (o acento é PONTO) · erro #f38ba8 ·
#          rodapé #a9a3c2 · sombras #11111b (nunca preto puro) · RAIO 20
#          (O RAIO DA DOCK — a pílula-27 da era greeter antigo se
#          aposenta). A lei do sinal E100 e o blur leve (3 passes/size 8)
#          intactos; a fonte Iosevka NF mantida.
#      (2) A PELE DO GREETER — theme.conf OVERRIDE do tema archcraft do
#          SDDM (o stack NATIVO mantido: sddm-git Qt6 + greeter X11 +
#          xorg-server modesetting; NENHUM daemon novo, NENHUMA dep
#          extra — a filosofia enxuta): estrutura COMPLETA do upstream
#          2.0 (todas as chaves — nada órfão no QML) com os MESMOS
#          valores da paleta: TimeTextColor #f8fafc · DateTextColor
#          #cdd6f4 · campos transparentes com borda inativa #262637 e
#          A BORDA ROXA ATIVA em foco (HighlightBorderColor #a855f7 —
#          verificado no Components/Input.qml: activeFocus ? Highlight
#          BorderColor : *FieldBorderColor) · WarningColor #f38ba8 ·
#          botão de login #a855f7 com texto #11111b (4.74:1 AA) ·
#          hover em #cba6f7 (NUNCA inverte para claro) · RoundCorners 20
#          (o raio da dock) · PopupRadius 12 (o raio dos popovers) ·
#          HeaderText vazio (zero saudação — uma voz por tela) ·
#          FullBlur true + Blur 1.0/BlurMax 64 + DimBackground 0.3 (o
#          blur leve — custo só do instante do greeter, zero residual) ·
#          UseRealName/ForceLastUser/PasswordFocus intactos ·
#          HourFormat HH:mm + DateFormat "dddd, MMMM d" (o esquema que o
#          dono aplaudiou) · sessão labwc direta (Session=labwc +
#          state.conf — sem ruído de seletor). Fonte ÚNICA: a ISO veste
#          pelo overlay do airootfs, o rig vivo pelo MESTRE no pacote
#          (/usr/local/share/elite/sddm/theme.conf) entregue pelo
#          elite-post-upgrade (fóssil upstream = renova com backup;
#          personalizado = intocável — a lei do domínio v3 até no
#          /usr/share).
#      (3) O ÚLTIMO SOTAQUE DO PONTEIRO MORRE — o CursorTheme do greeter
#          veste Bibata (kde_settings.conf): a era E36 mantinha Qogirr
#          "por ser outro domínio" — a paleta unificou as telas, o cursor
#          idem; o archcraft-cursor-qogirr sai da ISO (packages.add, com
#          voz) e o environment documenta o fim.
#      (4) A ENTREGA: craft-rice ganha o fóssil da v7 (6e459724 — quem
#          adotou a v7 renova para a v8 PELO FÓSSIL, sem --lock-adopt);
#          o post-upgrade entrega o theme.conf do greeter na transação.
#      pkgrel 97→98 NO MESMO COMMIT (lei E41 — peles de conteúdo mudado:
#      hyprlock.conf v8 no skel E mestre do pacote + theme.conf do
#      greeter mestre novo; bins: craft-rice e elite-post-upgrade).
# E151 (ONDA FINAL 2/2 — a diretriz do dono sobre a base 1.0-98): pkgrel
#      98→99 NO MESMO CICLO (lei E41, o bump no fecho da era como sempre):
#      (1) A IDENTIDADE OBSIDIANA (docs/skills/06): a barra 28px veste a
#          MESMA superfície da dock (#0d0d12/#13131a, borda mauve
#          rgba(203,166,247,.16)), TODOS os itens no brilho da casa
#          (#cdd6f4/#f8fafc), o estado ativo no acento suave #cba6f7 e
#          o mutado/desligado no perigo #f38ba8; Áudio (saída) e
#          MICROFONE (entrada) em assentos próprios (o mudo do mic deixa
#          de ser o clique do meio escondido); o relógio veste
#          tabular-nums e abre/fecha o painel swaync; o calendário
#          header veste #f8fafc; ZERO vazamento de tema GTK4 (a pálida
#          do foco: focus_on_click/can_focus false + :checked/:focus
#          com background-image none/box-shadow none no MenuButton — o
#          seletor roxo travado e o quadrado branco morrem pela raiz).
#      (2) A DOCK INSTANTÂNEA: o flush_superficie ÚNICO em TODO evento
#          (Closed/Minimize/Maximize/Pin/Unpin/abertura — o dreno comita
#          o recálculo SEMPRE, o evento de flags não espera outra ação
#          na tela) e o clique do MEIO morto com direito (o Fechar mora
#          no menu completo do direito).
#      (3) O DEBLOAT EXTREMO: o greeter do SDDM veste WAYLAND NATIVO
#          (elite_wayland.conf: DisplayServer=wayland +
#          CompositorCommand=labwc, entregue SÓ com labwc em disco — a
#          rede anti-tela-preta); o xorg-server sai da ISO (os rigs
#          conservam como rede); o POLKIT ÚNICO (lxqt-policykit eleito,
#          hyprpolkitagent fora, o autostart duplicado amordaçado por
#          Hidden=true por usuário); o UDISKIE morre (58,5 MB de Python
#          residente) pelo trio udev/unit/bin elite-automount (oneshot
#          por plug, mount no usuário ativo); NoExtract man/doc/gtk-doc
#          na ISO e no sistema; ISO em zstd -19 -T0 (o xz -9e aposenta);
#          ParallelDownloads=10 e a cache_enxuga (paccache -rk1) nas
#          duas portas da dose; a regra 99-elite-io.rules (NVMe none,
#          SSD mq-deadline); panic=abort no release; blur do lock em
#          CACHE por evento (wall-blur.png); gtk-decoration-layout com
#          os botões à direita; os mestres do mangohud EMBARCAM de
#          verdade (mh_install — a classe E103 da era) e a classe E57
#          latente (overlay↔pacote) curada antes de custar pacstrap.
#      (4) AS SKILLS PERMANENTES: docs/skills/05-filosofia-extrema.md e
#          06-ui-ux-gtk4-wayland.md + a LEI DE ENTRADA no README das
#          skills e o §0 na constituição (ler docs/skills antes de
#          editar); a MANUTENÇÃO MENSAL no CI (maintenance.yml, dia 1:
#          cargo check --all-features + a suíte contra o Arch do dia).
#      Notas da era: docs/releases/1.0-99.md.
# 1.0-100 (AS 4 CURAS ESTRUTURAIS DO AUDIT 99 — a diretriz do dono):
#      (1) O AUTOSTART E O RELOGIN: o heal-sessao julga o FÓSSIL DE ERA
#          (arquivo da casa sem elite-daemon session = corpo legado do
#          guard waybar — audit §7; a cura anterior não o via com o
#          bloco anexado) e reconstrói do mestre COM O SKEL COMO REDE
#          (o mestre do pacote nunca existiu no disco — o buraco
#          fotográfico); o elite-daemon varre os locks órfãos de /tmp
#          (flock livre + PID ausente em /proc — audit §2) na porta
#          session e no motor de jogo, e o lock do motor registra o
#          PID; o dispara() colhe os filhos curtos (os 2 <defunct> do
#          audit §1 morrem).
#      (2) O SUSPEND/RESUME: o despertar (PrepareForSleep(false)/Unlock)
#          religa o vídeo em ORDEM — wlopm --on '*' PRIMEIRO (DPMS antes
#          de modo: wlr-randr contra saída desligada perde a rodada),
#          craft-display apply depois (audit §4 — sem derrubar o display
#          Wayland nem o labwc).
#      (3) A DOCK: o flush_superficie faz set_default_size(-1,-1) +
#          queue_resize na GtkWindow (a largura memorizada segurava o
#          commit do layer-shell — a faixa preta do fecho morre, audit
#          §3); o vazamento GtkPopoverMenu segue coberto pelo enterro
#          E148 (contratos da porteira) e o estado por CLASSE (E139)
#          nunca remonta a barra.
#      (4) AS MESAS: o rc.xml carrega Execute `elite-daemon desk` em
#          TODO bind de troca (o labwc não fala protocolo de mesas — o
#          daemon aprende por este fio e publica no bus.sock, audit §4);
#          BusReq DeskSet/DeskStep novos (registram, nunca sintetizam
#          tecla — o loop W-n→sync→W-n não nasce); WindowInfo ganha a
#          mesa aprendida (desk, fio tolerante) e a dock veste
#          .other-workspace (ícone semiapagado + bolinha mutada; o
#          desconhecido é presumido visível; o clique ativa e o
#          compositor traz a mesa).
#      Suíte: GO 422 · 0 · 1 (porteira local) · cargo test 163 · 0
#      (o núcleo std-first; o juízo da gui é o Canal — lei L6).
#      Notas da dose: docs/releases/1.0-100.md.
#      pkgrel 99→100 NO MESMO COMMIT (lei E41).
pkgrel=100
pkgdesc='O sistema da Elite em um pacote só — craft-*, elite-*, exo-open, daemon de janelas e units da sessão; substitui elite-craft/craft-toplevel'
arch=(x86_64)
url=https://github.com/Chrispsz/archcraft-elite
license=(GPL3)
# E138 — O PAR X É DEPENDÊNCIA DURA (a ordem do dono, dump v2.13: o rc=127
# do elite-gparted — a adoção best-effort só convergia quando o dono
# rodava a dose; o pacote NASCE com o cinto). xorg-xhost abre o
# +SI:localuser:root do XWayland; xorg-xauth extrai o cookie do usuário.
depends=(bash python wayland wlopm xorg-xhost xorg-xauth)
# E138 — o sysctl consolidado é EDITÁVEL pelo dono (a régua da casa o
# regenera; a edição manual sobrevive como .pacnew, nunca perdida)
backup=(etc/sysctl.d/99-elite-performance.conf)
# E103 — o listener C aposentou (E132): o makedepends polkit sai junto
# (nada compila contra o libpolkitagent neste pacote desde a E132).
# E132 — o toolchain Rust entra como makedepends EXCLUSIVO do BUILD
# (a ordem do dono: espremer o limão — compila AQUI e SOMENTE aqui;
# zero rust na ISO e no pacote final: o binário é o que viaja)
makedepends=(rust cargo gtk4 gtk4-layer-shell)
# E50 — A SUBSTITUIÇÃO DE ERA: conflita e substitui os DOIS veículos
# legados — o -Syu do craft-update (alvo elite-system) remove o par e
# instala o único na MESMA transação; configs de usuário (~) NUNCA são
# tocados (o domínio da casa continua sendo /usr/local/bin + /etc/systemd).
replaces=('elite-craft' 'craft-toplevel')
conflicts=('elite-craft' 'craft-toplevel')
# sem -debug (shell/python + binário já compilado com -s; nada a tirar
# símbolo)
options=(!debug !strip)
# E132 — o WORKSPACE RUST como fonte em TAR (source=() não aceita
# diretórios; o tar é gerado no estágio de staging com o guard do
# craft-dock-rs — a sha viaja pelo env RUST_TAR_SHA, lida no python).
# 2.0 Fase 2 — A ÚNICA FONTE é o tar do workspace (o C do toplevel
#     morreu com o C de 3 gerações: o cliente Wayland é o próprio
#     elite-daemon — nada de fonte vendada, nada de sha dupla).
source=("rust-workspace.tar.gz")
sha256sums=('{rust_sha}')
build() {{
    # 2.0 Fase 2 — O gcc DO C MORREU (o C de 3 gerações
    # aposentou: o cliente Wayland é o PRÓPRIO elite-daemon no wayland.rs;
    # aqui só o toolchain Rust fala)
    # E132 — o elite-polkit-listener NÃO COMPILE MAIS (a ordem do dono,
    # dump pós-1.0-78: os transient 'polkit-agent-helper@…' FAILED — o
    # lxqt-policykit-agent NATIVO, compatível com o polkit 128, é o agente
    # da casa; a gcc daqui e o C vendado aposentaram no mesmo gesto)
    # E132 — O WORKSPACE RUST COMPILA AQUI (a ordem do dono: espremer o
    # limão): o tar carrega os membros SEM diretório comum — a extração
    # mora no subdir rust/ (tar de membros soltos no topo do srcdir
    # sujaria a fonte do C). A LIÇÃO E131 MORA AQUI: o lto=fat, o
    # codegen-units=1 e o strip=symbols moram no [profile.release] do
    # Cargo.toml do workspace — NUNCA no RUSTFLAGS (o embed-bitcode do
    # lto no RUSTFLAGS QUEBRA a build); o RUSTFLAGS leva SÓ o alvo da
    # ISA (x86-64-v3 — o mesmo valor do .cargo/config.toml do workspace,
    # o build local casa com o CI). --locked: o Cargo.lock viaja no tar.
    export RUSTFLAGS="-C target-cpu=x86-64-v3"
    mkdir -p rust
    tar -xzf rust-workspace.tar.gz -C rust
    # E132 — o DAEMON é OBRIGATÓRIO (falha = build vermelha); E134 — A
    # DOCK TAMBÉM (a UI compila com o pkg-config gtk4 + layer-shell do
    # makedepends; a dose sem dock é uma dose SEM DOCK — o fallback
    # Python morreu com a migração definitiva da ordem do dono)
    cargo build --release --locked --manifest-path rust/Cargo.toml -p elite-daemon
    # E134 — A DOCK RUST É OBRIGATÓRIA: a dose 1.0-80 nasceu SEM o binário
    # porque o '|| echo AVISO' deixava a build VERDE sem ele — e o rig
    # seguiu na dock Python com o supervisor novo esperando o Rust (o dump
    # 1.0-80 fotografou o /usr/bin/python3 craft-dock-gui VIVO). Sem o
    # binário a build morre VERMELHA: não existe mais dock Python no
    # pacote, uma dose sem o craft-dock-rs é uma dose SEM DOCK.
    cargo build --release --locked --manifest-path rust/Cargo.toml -p craft-dock-rs
    # E140 — A TOP BAR É OBRIGATÓRIA (a ordem do dono, dossiê 1.0-88: o
    # waybar aposentou — a dose sem o craft-bar-rs é uma dose SEM top
    # bar; a build morre vermelha antes do install mentir verde)
    cargo build --release --locked --manifest-path rust/Cargo.toml -p craft-bar-rs
    # 2.0 — A TELEMETRIA v2 É OBRIGATÓRIA (o núcleo puro compila em
    # qualquer lugar — std-only; a coleta completa é Fase 2, o bin
    # honesto já nomeia era/serviços/boot)
    cargo build --release --locked --manifest-path rust/Cargo.toml -p craft-dump-rs
    # 2.0 Fase 2 — AS FERRAMENTAS NATIVAS são OBRIGATÓRIAS (a diretriz:
    # as janelas craft-update/craft-clean/craft-help e o craft-pick
    # aposentam o craft-menu — dose sem ferramentas é dose SEM a face
    # nova; a build morre vermelha antes do install mentir verde)
    cargo build --release --locked --manifest-path rust/Cargo.toml -p craft-tools
}}
# ADOÇÃO (a herança do elite-craft): nos rigs, estes arquivos nasceram SEM
# dono (overlay da ISO) — o pacman recusa sobrescrever não-dono ANTES de
# qualquer scriptlet; o pre_install remove exatamente os caminhos que
# ESTE pacote entrega (a lista vem do MANIFEST de geração — fonte única).
# O par legado INSTALADO não entra nesta dança: o replaces do pacman o
# remove ANTES da extração deste pacote (remoções precedem instalações).
pre_install() {{
    local f
    for f in \\
{names}
    ; do
        [ -e "/usr/local/bin/$f" ] && rm -f "/usr/local/bin/$f"
    done
{unit_loop}{hook_rm}{kmod_rm}{mh_rm}{ff_rm}{lock_rm}{sddm_rm}{rc_rm}{osd_rm}{menu_rm}{gm_rm}{doc_rm}{gp_rm}{flags_rm}{apps_rm}{pk_rm}{q6_rm}{dc_rm}{sudoers_rm}    return 0
}}
# E129 — A MIGRAÇÃO AUTÔNOMA (AGENTS.md §4, 2026-11-20): o usuário final
# NUNCA roda comando manual de pós-instalação — toda correção de /etc,
# Polkit, systemd, sysctl, GRUB, Flatpaks e dotfiles corre AQUI, no
# pacman -Syu, SEM depender do firstboot-done (que só roda na instalação
# inicial). O corpo mora no elite-post-upgrade (bin do pacote — o
# post_upgrade corre DEPOIS da extração, o bin novo já vive) e é
# IDEMPOTENTE por desenho (rodar 2× = mesmo estado final, §4).
post_install() {{
    if [ -x /usr/local/bin/elite-post-upgrade ]; then
        /usr/local/bin/elite-post-upgrade post_install || true
    fi
}}
post_upgrade() {{
    if [ -x /usr/local/bin/elite-post-upgrade ]; then
        /usr/local/bin/elite-post-upgrade post_upgrade || true
    fi
}}
package() {{
    install -d "${{pkgdir}}/usr/local/bin"
    cp -a "${{startdir}}/files/usr/local/bin/." "${{pkgdir}}/usr/local/bin/"
    # 2.0 Fase 2 — O C DO CRAFT-TOPLEVEL MORREU (o cliente Wayland é o
    # PRÓPRIO elite-daemon: zwlr-foreign-toplevel v2 + ext-idle-notify
    # nativos, o snapshot no bus.sock — a fonte de 3 gerações aposenta
    # com o pacote próprio e o hook)
    # E132 — os binários RUST da fundação. E134: o craft-dock-rs é
    # OBRIGATÓRIO (a build dele falhou = build vermelha antes de chegar
    # aqui; o fallback Python não existe mais — dose sem dock é build
    # vermelha, e o install abaixo prova o arquivo com a verdade)
    for b in elite-daemon craft-dock-rs craft-bar-rs; do
        [ -f "${{CARGO_TARGET_DIR:-rust/target}}/release/$b" ] && install -m755 "${{CARGO_TARGET_DIR:-rust/target}}/release/$b" "${{pkgdir}}/usr/local/bin/$b"
    done
    # 2.0 Fase 2 — AS FERRAMENTAS NATIVAS + A TELEMETRIA v2: o
    # craft-dump v2 É o craft-dump (o shell v1 aposentou — a telemetria
    # da casa fala a língua nova: bus vivo, família nativa, boot flags)
    for b in craft-update craft-clean craft-help craft-pick craft-dump; do
        [ -f "${{CARGO_TARGET_DIR:-rust/target}}/release/$b" ] && install -m755 "${{CARGO_TARGET_DIR:-rust/target}}/release/$b" "${{pkgdir}}/usr/local/bin/$b"
    done
    # E132 — o elite-polkit-listener NÃO viaja mais (o agente da casa é o
    # lxqt-policykit-agent NATIVO, eleito no craft-bars; um bin a menos no
    # pacote, um agente a menos na fila — o C vendado aposentou do repo)
{unit_install}{hook_install}{kmod_install}{mh_install}{ff_install}{lock_install}{sddm_install}{grub_install}{rc_install}{osd_install}{menu_install}{pd_install}{gm_install}{doc_install}{gp_install}{pt_install}{ef_install}{flags_install}{apps_install}{udev_install}{pk_install}{q6_install}{theo_install}{gtk_install}{dc_install}{sudoers_install}}}
"""
(d / 'PKGBUILD').write_text(pkg)
PYE50

# makepkg se recusa a rodar como root — usuário builder descartável
useradd -m builder 2>/dev/null || true
chown -R builder /tmp/elite-src
# 1.0-93 — O TARGET DO CARGO MORA NO WORKSPACE (a ordem do dono: cache
# Cargo nos workflows — as deps pagam o compile 1x): o CARGO_TARGET_DIR
# aponta para /work/crates/target (o volume MONTADO do runner — o actions/
# cache persiste entre runs; a chave lá no workflow é o Cargo.lock). O
# builder precisa da porta aberta (chown) e o runner recupera a posse no
# fim (o bloco HOST_UID do fim da build).
export ELITE_CARGO_TARGET_DIR="${ELITE_CARGO_TARGET_DIR:-/work/crates/target}"
mkdir -p "$ELITE_CARGO_TARGET_DIR" 2>/dev/null || true
chown -R builder "$ELITE_CARGO_TARGET_DIR" 2>/dev/null || true
# E43 — PACKAGES_ONLY=1 (canal diário, publish-packages.yml): só os
# pacotes de CÓDIGO DE CASA — pywal/qt5vk/wlrctl não mudam no dia a dia
# (o repo completo do release vivo entra no job por download+repo-add).
# 2.0 Fase 2 — O craft-toplevel SAIU DA FILA (o pacote morreu com o C:
# o replaces do elite-system segue limpando o legado dos rigs velhos).
PKG_LIST=(python-pywal qt5-virtualkeyboard wlrctl elite-system)
if [[ "${PACKAGES_ONLY:-0}" == "1" ]]; then
    PKG_LIST=(elite-system)
fi
for pkgdir in "${PKG_LIST[@]}"; do
    (cd "/tmp/elite-src/$pkgdir" && runuser -l builder -c "cd /tmp/elite-src/$pkgdir && CARGO_TARGET_DIR=${ELITE_CARGO_TARGET_DIR} makepkg -f --noconfirm") \
        || { echo "FALHA ao construir $pkgdir"; exit 1; }
    # E101 — O FÓSSIL DO CACHE MORRE ANTES DO PACOTE NOVO CHEGAR: o
    # .ci-cache restaurado de uma era anterior pode carregar versão VELHA
    # deste mesmo pacote ao lado da recém-nascida (a run #153: o
    # elite-system-1.0-7 de 5 dias atrás derrotou o 1.0-44 no repo-add e o
    # pacstrap instalou o PASSADO na ISO de hoje — o elite-bootupdate sem
    # o skip do live rodou no QEMU, o craft-bars sem a fila E58 elegeu o
    # hyprpolkitagent e crash-loopou 21×: AS DUAS falhas do verify, UM
    # réu). A casa acabou de parir a versão VIVA: qualquer outra do mesmo
    # nome é fóssil e não pode existir no repo no momento do repo-add.
    rm -f /var/cache/elite-local/"$pkgdir"-*.pkg.tar.zst
    cp "/tmp/elite-src/$pkgdir/"*.pkg.tar.zst /var/cache/elite-local/
done
# E114.2 — O BRAVE DO PIN VAI AO CANAL (a 2ª camada do buraco nomeado pela
# E113: o canal baixava o ASSET da release viva — que é do ESTÁGIO da ISO,
# preso no pin da era do último build completo — e o rig recebia o navegador
# velho com 'already existed' no papel). O fluxo do canal agora PARTE O
# BRAVE DO PIN ATUAL (o mesmo estágio do build completo) ANTES de sair:
# pin movido = asset novo na release = o rig recebe o navegador vivo na
# dose seguinte. O pulo honesto: keyring/mirrorlist (o canal não os muda)
# ficam para o build completo.
PKG_ONLY_SKIP_REST=0
if [[ "${PACKAGES_ONLY:-0}" == "1" ]]; then
    PKG_ONLY_SKIP_REST=1
    # 1.0-93 — o target do cargo volta para o uid do runner AQUI TAMBÉM (o
    # cache do Canal mora nele; sem o chown o actions/cache não salva)
    if [[ -n "${HOST_UID:-}" ]]; then
        chown -R "${HOST_UID}:${HOST_GID:-$HOST_UID}" "$ELITE_CARGO_TARGET_DIR" 2>/dev/null || true
    fi
    say "PACKAGES_ONLY=1 — pacotes de casa prontos; o estágio do BRAVE segue (E114.2: o canal parte o pin) e a ISO não é construída"
fi
if [[ "$PKG_ONLY_SKIP_REST" != 1 ]]; then
# cachyos-keyring + cachyos-v3-mirrorlist também entram no [elite-local]:
# o E2 do customize instala os dois por file:// (PRIMEIRO repo do conf) —
# o chroot não toca a rede no customize (era a última fonte potencial de
# curl errors do build; skew de mirror não alcança mais esta fase).
# Escada: nome = listing do us (único mirror com listing; cdn77 devolve
# 404 em diretório) → pin; download = cdn77 → us → pin de novo (o listing
# pode anunciar nome que ainda não propagou). Tudo falhou: avisa e segue
# (E1 cobre a chave via keyserver; E2 tem fallback manual de mirrorlist).
say "Buscando cachyos-keyring + cachyos-v3-mirrorlist (E2 offline-first)"
elite_latest() {
    curl -fsSL --max-time 30 "https://us.cachyos.org/repo/x86_64/cachyos/" 2>/dev/null \
        | grep -oE "$1-[0-9][^\"]*\.pkg\.tar\.zst" | sort -Vu | tail -1 || true
}
elite_fetch() { # $1 = nome do arquivo → /var/cache/elite-local/
    local m
    # us PRIMEIRO: é o mirror completo (listing + arquivos); o cdn77 está
    # cronicamente desincronizado nos v3 (db na frente dos arquivos por
    # HORAS — runs #17/#19). Listing continua do us (cdn77 não lista).
    for m in https://us.cachyos.org/repo/x86_64/cachyos \
             https://cdn77.cachyos.org/repo/x86_64/cachyos; do
        if curl -fsSL --retry 3 --retry-delay 3 --retry-all-errors \
                -o "/var/cache/elite-local/$1" "$m/$1"; then
            say "  ok: $1 (${m#https://})"
            return 0
        fi
        rm -f "/var/cache/elite-local/$1"
    done
    return 1
}
KR_LATEST="$(elite_latest cachyos-keyring)"
ML_LATEST="$(elite_latest cachyos-v3-mirrorlist)"
elite_fetch "${KR_LATEST:-cachyos-keyring-20240331-1-any.pkg.tar.zst}" \
    || elite_fetch "cachyos-keyring-20240331-1-any.pkg.tar.zst" \
    || echo "  (aviso: cachyos-keyring fora do ar nos 2 mirrors — E2 usará fallback de rede)"
elite_fetch "${ML_LATEST:-cachyos-v3-mirrorlist-27-1-any.pkg.tar.zst}" \
    || elite_fetch "cachyos-v3-mirrorlist-27-1-any.pkg.tar.zst" \
    || echo "  (aviso: cachyos-v3-mirrorlist fora do ar nos 2 mirrors — E2 usará fallback de rede)"


fi  # fim do pulo do PACKAGES_ONLY (keyring/mirrorlist ficam para o build completo)

# ── v1.4: BRAVE ORIGIN (release oficial) → [elite-local] ─────────────
#  Diretriz do dono (burn test da v1.3 AO VIVO no rig dele, 2026-10-22):
#  o navegador padrão da Elite passa a ser o BRAVE ORIGIN — o build
#  oficial brave-origin-*.zip das releases da Brave (produto de primeira
#  classe: linux amd64/arm64 + darwin; o PROFILE do usuário segue o do
#  Brave de sempre: BraveSoftware/Brave-Browser — o preseed de
#  custom_chrome_frame mora lá; verificado no binário: app_id continua
#  "brave-browser"). Empacotado AQUI (mesmo padrão dos stubs acima) em
#  vez de clonar o AUR: versão PINADA (determinismo —
#  filosofia Elite), sha256 do source verificado pelo makepkg, e o
#  empacotamento espelha o brave-bin upstream: launcher /usr/bin/brave
#  lendo brave-flags.conf (padrão chromium-flags.conf), /opt, sandbox
#  suid, ícones hicolor do product_logo e desktop 'brave-browser.desktop'
#  — nome exigido pelo mimeapps.list do skel e pelo app_id do taskbar.
#  BROWSER=brave, W-w/W-b, dock e menu raiz seguem abrindo o MESMO
#  comando 'brave' — zero regressão no rice; o que muda é o PRODUTO.
#  makepkg --nodeps: pacote binário; as deps (gtk3 nss alsa-lib…) são
#  resolvidas pelo pacstrap no airootfs, não precisam existir no
#  container de build.
# E101 — O PIN É ÚNICO E EXATO: BRAVE_PIN acompanha o pkgver do heredoc
#  (o check-brave.sh sobe os DOIS no mesmo bump — contrato anti-drift na
#  suíte cobra a igualdade). O guard de cache antigo aceitava QUALQUER
#  brave-origin-* e o fóssil de uma era anterior (1.98.63) derrotava o
#  pin novo (1.99.55) sem nem tentar: a ISO nascia com o navegador velho
#  e a chave E32 do cache não salvava — o restore-keys devolve o cache
#  antigo de qualquer jeito (a run #153 flagrou: 'cache hit:
#  brave-origin-1.98.63' com o pin em 1.99.55). O pin manda: cache serve
#  quando É o pin; fóssil de outra era morre.
BRAVE_PIN="1.100.59"
BRAVE_PKG="brave-origin-${BRAVE_PIN}-1-x86_64.pkg.tar.zst"
say "Estágio Brave ORIGIN ${BRAVE_PIN} (release oficial) → /var/cache/elite-local/"
# v2.1 — cache do Actions persiste /var/cache/elite-local entre runs
#  (build.yml monta .ci-cache/elite-local no container): pkg.tar.zst
#  presente = bits cujos sources passaram no sha256 da run que o
#  construiu. Cache miss = download/rebuild (comportamento original).
if [ -f "/var/cache/elite-local/$BRAVE_PKG" ]; then
    say "  cache hit: $BRAVE_PKG (o pin exato — E101) — download/rebuild pulados"
    # fósseis de outras eras não sobrevivem ao cache hit (o repo-add
    # adiante processa o dir INTEIRO — dois brave-origin = o velho pode
    # vencer, a mesma doença do elite-system da #153)
    find /var/cache/elite-local -maxdepth 1 -name 'brave-origin-*.pkg.tar.zst' ! -name "$BRAVE_PKG" -delete
    sha256sum "/var/cache/elite-local/$BRAVE_PKG"
else
    # sem o pin no cache: qualquer brave-origin que exista é fóssil — fora
    rm -f /var/cache/elite-local/brave-origin-*.pkg.tar.zst
mkdir -p /tmp/elite-src/brave-origin
cat > /tmp/elite-src/brave-origin/PKGBUILD <<'EOPKGBUILD'
pkgname=brave-origin
pkgver=1.100.59
pkgrel=1
pkgdesc='Brave Origin — navegador que bloqueia ads e trackers por padrão (release oficial brave-origin)'
arch=(x86_64)
url=https://github.com/brave/brave-browser
license=(MPL2 BSD custom:chromium)
depends=(alsa-lib gtk3 libxss nss ttf-font)
optdepends=('cups: suporte a impressão'
            'libnotify: notificações nativas')
provides=("brave=$pkgver" 'brave-browser')
conflicts=(brave brave-bin)
options=(!strip)
_brave_zip="brave-origin-${pkgver}-linux-amd64.zip"
# brave-origin.sh + brave-browser.desktop: sources LOCAIS (heredocs acima)
# — makepkg só copia p/ $srcdir o que está em source=() (a run #57 ensinou:
# "install: cannot stat 'brave-origin.sh'"). Os sha256 abaixo são dos bytes
# EXATOS dos heredocs — mudou o launcher/desktop ⇒ recalcule (padrão do
# empacotamento upstream do brave, que também pinsha os próprios scripts).
source=(brave-origin.sh
        brave-browser.desktop
        "${_brave_zip}::https://github.com/brave/brave-browser/releases/download/v${pkgver}/brave-origin-${pkgver}-linux-amd64.zip")
noextract=("${_brave_zip}")
sha256sums=('ba01b127ffbedae6956b8e0f1565170cdecfbba9c19f3fcf76cbf7d6a566bea4'
            '2187fb69be1ebfbc29f8dbd55d2c98d7b5a8b677f247258b43480b894cdac82b'
            '1b07d2dca20d8bc49dc00c9f22e8b9138feb71ca12b450cf8607f7d6497e9ad7')

prepare() {
    mkdir -p brave
    bsdtar -xf "$_brave_zip" -C brave
    chmod +x brave/brave
}

package() {
    install -dm0755 "$pkgdir/opt"
    cp -a brave "$pkgdir/opt/brave-origin"
    # sandbox suid (padrão do empacotamento upstream do brave)
    chmod 4755 "$pkgdir/opt/brave-origin/chrome-sandbox"

    install -Dm0755 brave-origin.sh "$pkgdir/usr/bin/brave"
    # nome 'brave-browser.desktop' é CONTRATO: mimeapps.list do skel e o
    # app_id "brave-browser" do taskbar da waybar resolvem por ele
    install -Dm0644 brave-browser.desktop "$pkgdir/usr/share/applications/brave-browser.desktop"
    install -Dm0644 brave/LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    pushd "$pkgdir/usr/" >/dev/null
    for size in 16 24 32 48 64 128 256; do
        install -Dm0644 "$pkgdir/opt/brave-origin/product_logo_${size}.png" \
            "share/icons/hicolor/${size}x${size}/apps/brave-desktop.png"
    done
    popd >/dev/null
}
EOPKGBUILD
cat > /tmp/elite-src/brave-origin/brave-origin.sh <<'EOSH'
#!/usr/bin/env bash
# brave-origin launcher — padrão chromium-flags.conf (idêntico ao brave-bin
# upstream: lê $XDG_CONFIG_HOME/brave-flags.conf; a Elite entrega o arquivo
# no skel com flags Wayland/Vulkan/VA-API)
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-"${HOME}/.config"}"
CONF_FILE="${XDG_CONFIG_HOME}/brave-flags.conf"
if
        test -f "${CONF_FILE}"
then
        mapfile -t CONF_LIST < "${CONF_FILE}"
fi
for CONF_LINE in "${CONF_LIST[@]}"
do
        if ! [[
                "${CONF_LINE}" =~ ^[[:space:]]*(#|$)
        ]]
        then
                FLAG_LIST+=("${CONF_LINE}")
        fi
done
export CHROME_VERSION_EXTRA='stable'
exec /opt/brave-origin/brave "${FLAG_LIST[@]}" "${@}"
EOSH
cat > /tmp/elite-src/brave-origin/brave-browser.desktop <<'EODESK'
[Desktop Entry]
Version=1.0
Name=Brave Origin
GenericName=Web Browser
Comment=Access the Internet
StartupNotify=true
StartupWMClass=brave-browser
TryExec=brave
Exec=brave %U
Terminal=false
Icon=brave-desktop
Type=Application
Categories=Network;WebBrowser;
MimeType=application/pdf;application/rdf+xml;application/rss+xml;application/xhtml+xml;application/xhtml_xml;application/xml;image/gif;image/jpeg;image/png;image/webp;text/html;text/xml;x-scheme-handler/http;x-scheme-handler/https;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=brave

[Desktop Action new-private-window]
Name=New Incognito Window
Exec=brave --incognito
EODESK
# makepkg se recusa a rodar como root — builder descartável (já existe p/ stubs)
chown -R builder /tmp/elite-src/brave-origin
if runuser -l builder -c "cd /tmp/elite-src/brave-origin && makepkg -f --noconfirm --nodeps"; then
    cp /tmp/elite-src/brave-origin/*.pkg.tar.zst /var/cache/elite-local/
    say "  ok: brave-origin ${BRAVE_PIN} (Brave ORIGIN oficial, sha256 verificado)"
else
    echo "ELITE-FAIL: makepkg do brave-origin (fonte/CDN fora?) — sem retry: fonte é GitHub Releases da Brave" >&2
    exit 1
fi
fi  # v2.1 — fim do guard de cache do estágio brave-origin

# E114.2 — A SAÍDA DO CANAL (o cp que morava no branch do PACKAGES_ONLY
# antes da reestruturação): com o Brave do pin já em /tmp/elite-src, a
# cópia pega TODOS os pacotes paridos nesta run — o rig recebe a dose
# inteira (elite-system 1.0-60 + o brave do pin) numa transação só.
if [[ "$PKG_ONLY_SKIP_REST" == 1 ]]; then
    mkdir -p /work/out/pacotes
    cp /tmp/elite-src/*/*.pkg.tar.zst /work/out/pacotes/
    ( cd /work/out/pacotes && sha256sum *.pkg.tar.zst > sha256sums-pacotes.txt )
    ls -la /work/out/pacotes/
    chown -R "${HOST_UID:-1000}:${HOST_GID:-1000}" /work/out 2>/dev/null || true
    exit 0
fi

# E138 — O ESTÁGIO AUR MORRE DE VEZ (a ordem do dono, PROMPT 4/dump v2.13:
#  'mantendo um botão direto para abrir o mixer completo (pavucontrol)' —
#  o pwvucontrol era o ÚLTIMO filho do estágio AUR e não existe nos repos
#  oficiais; o pavucontrol do [cachyos-extra-v3] cobre o roteamento/ajustes
#  avançados SEM estágio de rede, SEM sudoers descartável, SEM elo frágil —
#  a mesma morte do overskride na E137, agora completa: ZERO AUR no build.
#  Rigs com pwvucontrol instalado o CONSERVAM (escolha do dono, nada de
#  remoção forçada de app em uso — a higiene da casa nunca desinstala o
#  que o dono abriu ontem).
rm -f /etc/sudoers.d/builder

# E101 — O db NASCE DE NOVO TODO BUILD: o db restaurado do cache carrega
#  entradas de eras mortas, e o gosto do repo-add por elas (a comparação
#  que recusou o 1.0-44 recém-nascido dizendo 'A newer version for
#  elite-system is already present in database' com o 1.0-7 no db) deixava
#  o repo apontando pro PASSADO. O db é DERIVADO dos arquivos — destruí-lo
#  e recriar custa segundos e mata a classe inteira: nenhuma entrada
#  defasada sobrevive para ser preferida.
rm -f /var/cache/elite-local/elite-local.db \
      /var/cache/elite-local/elite-local.db.tar.gz \
      /var/cache/elite-local/elite-local.db.tar.gz.old \
      /var/cache/elite-local/elite-local.files \
      /var/cache/elite-local/elite-local.files.tar.gz \
      /var/cache/elite-local/elite-local.files.tar.gz.old
repo-add --quiet /var/cache/elite-local/elite-local.db.tar.gz /var/cache/elite-local/*.pkg.tar.zst
# E32 — pacman consulta <repo>.db SEM sufixo: o repo-add JÁ cria um SYMLINK
# elite-local.db → elite-local.db.tar.gz (a run 41254942475 flagrou: cp
# contra o próprio symlink = 'are the same file', exit 1 no set -e). O
# rm -f antes do cp garante ARQUIVO REAL (o symlink não viaja bem no
# artifact; o E8 preserva estes 2 arquivos na ISO p/ o file:// do conf)
rm -f /var/cache/elite-local/elite-local.db && cp /var/cache/elite-local/elite-local.db.tar.gz /var/cache/elite-local/elite-local.db

# E101 — SELO 1 · O db APONTA PRO PACOTE DE HOJE: o repo-add já preferiu o
#  fóssil uma vez; o selo garante que o db que o pacstrap vai sincronizar
#  referencia EXATAMENTE o arquivo que o makepkg acabou de parir.
#  Divergência = build morto AGORA, com o réu nomeado — não daqui a 40
#  min no QEMU do verify (o custo da #153: 35 min de ISO + 8 de verify
#  para descobrir no serial que o elite-system era de 5 dias atrás).
ES_STAGED="$(ls /var/cache/elite-local/elite-system-*.pkg.tar.zst 2>/dev/null | head -1)"
ES_STAGED="${ES_STAGED##*/}"
ES_DB="$(bsdtar -xOf /var/cache/elite-local/elite-local.db.tar.gz \
           "$(bsdtar -tf /var/cache/elite-local/elite-local.db.tar.gz | grep -m1 '^elite-system[^/]*/desc$')" \
         | awk '/^%FILENAME%$/{getline; print; exit}')"
if [ -z "$ES_STAGED" ] || [ "$ES_DB" != "$ES_STAGED" ]; then
    echo "ELITE-FAIL: selo E101 — o db do [elite-local] diz elite-system='${ES_DB:-?}' mas o build pariu '${ES_STAGED:-?}' (o fóssil do cache venceu o repo-add? — classe da run #153)" >&2
    exit 1
fi
say "E101 selo 1: db do [elite-local] referencia o elite-system de hoje ($ES_DB)"
ls -la /var/cache/elite-local/

## E32 — marker da versão do código da casa: o craft-update compara com a
## release viva e aponta ISO/cura quando defasa. ELITE_VERSION vem do
## build.yml (= tag); fallback git/describe p/ build manual, 'dev' por fim.
ELITE_VER="${ELITE_VERSION:-}"
if [[ -z "$ELITE_VER" ]]; then
    git config --global --add safe.directory /work 2>/dev/null || true
    ELITE_VER="$(git -C /work describe --tags --exact-match HEAD 2>/dev/null \
        || git -C /work rev-parse --short HEAD 2>/dev/null \
        || echo dev)"
fi
mkdir -p elite/airootfs/usr/local/share/elite
printf '%s\n' "$ELITE_VER" > elite/airootfs/usr/local/share/elite/VERSION
say "Marker da casa: $(cat elite/airootfs/usr/local/share/elite/VERSION)"

say "Aplicando overlay Elite sobre o profile Archcraft"
cd /work
# o repo local também precisa existir DENTRO do chroot do pacstrap no
# mesmo caminho (file:// resolve relativo ao root ativo: host na fase 1,
# chroot na fase 2) — entregamos via overlay airootfs e limpamos no
# customize (E8) para não ir parar na ISO final
mkdir -p elite/airootfs/var/cache/elite-local
cp /var/cache/elite-local/* elite/airootfs/var/cache/elite-local/
bash scripts/apply-overlay.sh

# ─────────────────────────────────────────────────────────────────────
# E57 — O PACOTE É O ÚNICO DONO NA ISO (a prova crua do build de ISO,
# 05/nov 03:17): o overlay entrega os 35 bins + 9 units NO DISCO e o
# pacstrap tenta instalar o elite-system POR CIMA — o pacman recusa
# não-dono antes de qualquer scriptlet ('existe no sistema de arquivos'
# em 44 caminhos) e a ISO morre na MESMA doença que derrubou a adoção
# do rig (o E56 curou o craft-update; a esteira ficava doente). O
# pacstrap NÃO encaminha --overwrite (só nomes de pacote atravessam a
# linha de comando dele — _make_packages do mkarchcraftiso upstream),
# então a cura é na ORIGEM: o par overlay↔pacote vira PACOTE SOZINHO —
# UM dono por caminho, a mesma lei da casa. Os modos não se perdem: os
# bins são 100755 e as units 100644 no git index (a lição E54.1) — o
# cp -p do template e o pacman entregam 0755/0644 nativos. As entradas
# file_permissions destes caminhos saem do profiledef junto (o fork só
# AVISA em caminho ausente — mas log honesto não ladra 35 vezes por
# desenho; os caminhos fora do pacote ficam — E63: EXCETO o hook de
# resume elite-resume-display, que passou a viajar NO PACOTE porque o
# rig só o recebe pelo canal — a remoção abaixo cobre o dele).
# As wants symlinks ficam: eles APONTAM para units que o pacote entrega.
# ─────────────────────────────────────────────────────────────────────
PD_E57=$(find elite-build -maxdepth 3 -name profiledef.sh -print -quit)
[[ -n "$PD_E57" ]] || { echo "ELITE-FAIL: profiledef não encontrado pós-overlay (E57)" >&2; exit 1; }
MF_E57=/tmp/elite-src/elite-system/files/MANIFEST
if grep -qxF 'elite-system' "${PD_E57%profiledef.sh}packages.x86_64"; then
    [[ -s "$MF_E57" ]] || { echo "ELITE-FAIL: MANIFEST do elite-system ausente — a remoção E57 é cega sem ele (nunca)" >&2; exit 1; }
    say "E57: elite-system é o ÚNICO dono na ISO — o par overlay↔pacote sai do disco ($(wc -l <"$MF_E57") bins + as units elite-*)"
    while read -r b; do
        rm -f "${PD_E57%profiledef.sh}airootfs/usr/local/bin/$b"
    done < "$MF_E57"
    # E63 — os hooks de system-sleep agora são DO PACOTE (a rede de sistema
    # que o rig recebe pelo canal): sai do airootfs antes do pacstrap (a
    # MESMA lei E57 de um dono por caminho — o pacstrap recusa não-dono).
    # E69 — a cura do RETORNO dos dispositivos USB viaja NO PACOTE
    # (o mesmo veículo de adoção: o rig instalado só a recebe por ele).
    # E92 — a remoção vira VARREDURA (a lista POR NOME enferrujou a 3ª vez:
    # o sweep da E90/E91 pôs elite-sleep-report no pacote e estas duas
    # linhas rm -f não o removiam do profile — o pacstrap da build mensal
    # ia recusar o MESMO conflito que o rig do dono flagrou no craft-update
    # de 08/11). TODO elite-* do system-sleep sai do profile; quem
    # sobreviver ABORTA o build ANTES do pacstrap (nunca seguir sabendo).
    for h in "${PD_E57%profiledef.sh}airootfs/usr/lib/systemd/system-sleep"/elite-*; do
        [[ -e "$h" ]] && rm -f "$h" || true
    done
    for h in "${PD_E57%profiledef.sh}airootfs/usr/lib/systemd/system-sleep"/elite-*; do
        [[ ! -e "$h" ]] || { echo "ELITE-FAIL: hook $(basename "$h") sobreviveu à remoção E57/E92 — o pacote é o ÚNICO dono (nunca dois)" >&2; exit 1; }
    done
    # E92 — a mesma lei para a família share/elite (o fastfetch config era
    # do airootfs e o pacote agora o entrega — o pacstrap recusaria igual).
    rm -rf "${PD_E57%profiledef.sh}airootfs/usr/local/share/elite/fastfetch"
    [[ ! -e "${PD_E57%profiledef.sh}airootfs/usr/local/share/elite/fastfetch" ]] || { echo "ELITE-FAIL: fastfetch config sobreviveu à remoção E57/E92 — o pacote é o ÚNICO dono (nunca dois)" >&2; exit 1; }
    # E101.2 — A FAMÍLIA .desktop NA LEI E57 (a build #154 morreu nela):
    # a E98 pôs os overrides de menu NO PACOTE (a varredura gp_install —
    # 14 .desktop de calamares/foot/gparted/octopi-notifier/octopi-
    # repoeditor/qt6ct/nwg-look/xgps e cia) e a remoção E57 não ganhou a
    # família: o overlay seguia entregando os MESMOS caminhos no disco e o
    # pacstrap recusava não-dono em todos ('exists in filesystem' — 14
    # caminhos × 2 tentativas = 28 réus no log; a #153 não viu a classe
    # porque instalou o fóssil 1.0-7 pré-E98, sem a família). A lei de
    # sempre: UM dono por caminho — o pacote entrega, o overlay cala.
    # TODO .desktop da casa sai do profile; quem sobreviver ABORTA antes
    # do pacstrap (a mesma regra E92 da família fastfetch).
    shopt -s nullglob
    desk_e57=( "${PD_E57%profiledef.sh}"airootfs/usr/local/share/applications/*.desktop )
    shopt -u nullglob
    say "E101.2: ${#desk_e57[@]} .desktop de casa saem do overlay (o pacote entrega a família E98 — um dono por caminho)"
    rm -f "${desk_e57[@]}"
    shopt -s nullglob
    sobd_e57=( "${PD_E57%profiledef.sh}"airootfs/usr/local/share/applications/*.desktop )
    shopt -u nullglob
    (( ${#sobd_e57[@]} == 0 )) || { echo "ELITE-FAIL: ${#sobd_e57[@]} .desktop sobreviveram à remoção E57/E101.2 — o pacstrap morreria neles (nunca seguir sabendo)" >&2; exit 1; }
    # E57.1 — o glob das units nasceu com um PONTO LITERAL ('elite-'.*.service
    # exige um ponto depois de elite- — glob não é regex) e removeu ZERO na
    # prova de 16:27 (build 2): os 35 bins saíram, as 9 units ficaram no
    # disco e o pacstrap morreu SÓ nelas — réus 44→9, a cura provada pela
    # metade errada. Correção do glob + a regra da casa: quem sobreviver à
    # remoção ABORTA o build ANTES do pacstrap (nunca seguir sabendo).
    shopt -s nullglob
    units_e57=( "${PD_E57%profiledef.sh}"airootfs/etc/systemd/system/elite-*.service \
                "${PD_E57%profiledef.sh}"airootfs/etc/systemd/system/elite-*.timer )
    shopt -u nullglob
    say "E57: ${#units_e57[@]} units elite-* saem do overlay (o pacote entrega as 9 da casa)"
    rm -f "${units_e57[@]}"
    shopt -s nullglob
    sob_e57=( "${PD_E57%profiledef.sh}"airootfs/etc/systemd/system/elite-*.service \
              "${PD_E57%profiledef.sh}"airootfs/etc/systemd/system/elite-*.timer )
    shopt -u nullglob
    (( ${#sob_e57[@]} == 0 )) || { echo "ELITE-FAIL: ${#sob_e57[@]} units elite-* sobreviveram à remoção E57 — o pacstrap morreria nelas (nunca seguir sabendo)" >&2; exit 1; }
    while read -r b; do
        if [[ -e "${PD_E57%profiledef.sh}airootfs/usr/local/bin/$b" ]]; then
            echo "ELITE-FAIL: bin sobrevivente à remoção E57 ($b) — o pacstrap morreria nele (nunca seguir sabendo)" >&2; exit 1
        fi
    done < "$MF_E57"
    # E138 — A FAMÍLIA DO KERNEL MODERNO NA LEI E57 (o mesmo buraco da E57
    # original, agora nos /etc de tuning): o pacote passa a instalar o
    # sysctl consolidado, a regra 99-elite-zram, os modules-load (ntsync +
    # sensores), o tmpfiles do MGLRU e o /etc/default/scx — se o overlay
    # seguir entregando os MESMOS caminhos, o pacstrap recusa não-dono em
    # todos ('exists in filesystem', a doença E57 crua). UM dono por
    # caminho: o overlay cala, o pacote entrega, quem sobreviver ABORTA.
    # (A drop-in do scx_loader JÁ viajava pelo cp -a das units — a lei
    # valia para ela desde a E136; os confs é que eram órfãos de install.)
    kmod_e57=( "${PD_E57%profiledef.sh}"airootfs/etc/sysctl.d/99-elite-performance.conf \
               "${PD_E57%profiledef.sh}"airootfs/etc/udev/rules.d/99-elite-zram.rules \
               "${PD_E57%profiledef.sh}"airootfs/etc/udev/rules.d/60-ntsync.rules \
               "${PD_E57%profiledef.sh}"airootfs/etc/udev/rules.d/99-elite-io.rules \
               "${PD_E57%profiledef.sh}"airootfs/usr/lib/udev/rules.d/91-elite-wake-guard.rules \
               "${PD_E57%profiledef.sh}"airootfs/usr/lib/udev/rules.d/91-elite-automount.rules \
               "${PD_E57%profiledef.sh}"airootfs/etc/sudoers.d/99-elite-clean \
               "${PD_E57%profiledef.sh}"airootfs/etc/polkit-1/rules.d/50-elite-wheel.rules \
               "${PD_E57%profiledef.sh}"airootfs/usr/local/share/elite/qt6ct/qt6ct.conf \
               "${PD_E57%profiledef.sh}"airootfs/etc/modules-load.d/elite-ntsync.conf \
               "${PD_E57%profiledef.sh}"airootfs/etc/modules-load.d/elite-sensors.conf \
               "${PD_E57%profiledef.sh}"airootfs/etc/tmpfiles.d/elite-mglru.conf \
               "${PD_E57%profiledef.sh}"airootfs/etc/default/scx )
    say "E138: ${#kmod_e57[@]} confs de tuning saem do overlay (o pacote entrega a família do kernel moderno + as regras udev 91/99 + sudoers + polkit + qt6ct — um dono por caminho)"
    rm -f "${kmod_e57[@]}"
    # E151 — O MANGOHUD ENTRA NA LEI E57 (os 3 mestres staged desde a E136
    # estavam SEM install no molde — o réu-mãe E103 da era: e o overlay
    # entregava os MESMOS caminhos; agora o pacote instala E o overlay cala)
    rm -rf "${PD_E57%profiledef.sh}airootfs/usr/local/share/elite/mangohud"
    for k in "${kmod_e57[@]}"; do
        [[ ! -e "$k" ]] || { echo "ELITE-FAIL: conf de tuning sobreviveu à remoção E138 ($k) — o pacstrap morreria nele (nunca seguir sabendo)" >&2; exit 1; }
    done
    [[ ! -e "${PD_E57%profiledef.sh}airootfs/usr/local/share/elite/mangohud" ]] || { echo "ELITE-FAIL: mangohud sobreviveu à remoção E151 — o pacstrap morreria nele (nunca seguir sabendo)" >&2; exit 1; }
    python3 - "$PD_E57" "$MF_E57" <<'PYE57'
import sys, pathlib
pd, mf = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
bins = {'["/usr/local/bin/%s"]="0:0:755"' % b for b in mf.read_text().split()}
linhas = pd.read_text().splitlines(True)
out = [l for l in linhas if l.strip() not in bins]
pd.write_text(''.join(out))
print(f"E57: {len(linhas) - len(out)} entrada(s) file_permissions virou responsabilidade do elite-system (profiledef limpo — sem 35 avisos por desenho)")
PYE57
else
    say "E57: elite-system fora do pacstrap — overlay fica inteiro (sem pacote único a ISO não teria quem entregue os bins)"
fi

# ─────────────────────────────────────────────────────────────────────
# Preflight v3 — EXECV-SEGURO. O pacman executa o XferCommand via
# fork/execv (libalpm importa execv+fork, NÃO system()): operadores de
# shell ("|| echo … >>") viram argumentos literais do curl e matam TODA
# transferência — "failed to synchronize all databases", a falha que
# custou os runs #14 e #15. Agora:
#   1. pacman -Syw baixa a transação INTEIRA p/ o cache (download-only;
#      SEM --needed: o cache tem de cobrir tudo que o pacstrap pede no
#      chroot — o host já tem base+deps instalados e --needed pularia)
#   2. round falhou → pacman -Sp --print-format '%l' lista as URLs → sonda
#      HEAD paralela → os 404 reais (janela de desync db↔arquivo dos
#      mirrors rolling: db anuncia, mirror ainda não propagou)
#   3. 404 no cdn77 E no gêmeo us → injeta o BASELINE Arch oficial no
#      [elite-local] (primeiro repo do conf) e refaz o round
#   4. 3 rounds sem fechar o cache → ABORTA com diagnóstico — nunca
#      entra num build com cache sabidamente quebrado
# Cache completo → pacstrap offline (não baixa nada da rede).
#
# NOTA pacman 6+/7: --print-uris FOI REMOVIDO (pacman 6.0, 2021) — o
# binário 7.1 nem contém a string (verificado com strings; exit 1
# silencioso "unrecognized option" custou o run #16 inteiro). O
# substituto é --print-format '%l': URL p/ pacote fora do cache,
# caminho local file:// p/ cacheado (o grep ^https? filtra — sobra
# exatamente o conjunto NÃO-cacheado, que é o que a sonda quer).
# ─────────────────────────────────────────────────────────────────────

# v1.1 — injeção de baseline com BUMP de versão. O CachyOS é rolling: às
# vezes o db anuncia uma versão cujo arquivo NUNCA propaga (skew travado —
# ex.: libcdio-paranoia 10.2+2.0.2-3.1, 404 nos 2 mirrors por >24h, run
# #47). A injeção de baseline antiga não resolve: pacman prefere a versão
# NOVA (quebrada) — repo order só decide EMPATE. Último recurso
# determinístico: repack do baseline Arch com pkgrel +0.1 no [elite-local]
# (1º repo + versão maior = vence o resolve; o mirror sara e o próximo
# -Syu normaliza). Registrado com ELITE-BUMP no log — nunca silencioso.
elite_inject_bumped() { # $1 = filename quebrado (cachyos) $2 = path do baseline .pkg.tar.zst
    local broken="$1" basepkg="$2"
    # name-ver-rel: strip arch/ext, rev/cut como no preflight (ver não tem '-')
    local nb nb_name nb_verrel bverrel
    nb=$(printf '%s' "$broken" | sed -E 's/-(any|x86_64(_v3)?)\.pkg\.tar\.zst$//')
    nb_name=$(printf '%s' "$nb" | rev | cut -d- -f3- | rev)
    nb_verrel=$(printf '%s' "$nb" | rev | cut -d- -f1-2 | rev)     # ver-rel quebrada
    bverrel=$(printf '%s' "${basepkg##*/}" | sed -E 's/-(any|x86_64(_v3)?)\.pkg\.tar\.zst$//' | rev | cut -d- -f1-2 | rev)
    if [[ "$(vercmp "$bverrel" "$nb_verrel")" -ge 0 ]]; then
        # baseline >= quebrada: injeção simples (comportamento clássico)
        cp -f "$basepkg" "/var/cache/elite-local/${basepkg##*/}"
        say "  ELITE-INJECT ${basepkg##*/} (baseline >= quebrada: resolve no elite-local)"
        return 0
    fi
    # baseline mais VELHA: repack com o pkgrel MAJOR da quebrada + 1
    # ('1.1'→'2', '3.1'→'4', '1'→'2'). O original fazia '3.1→3.1.1' —
    # makepkg REJEITA pkgrel com 3 componentes ("pkgrel must be of the
    # form 'integer[.integer]', not 1.1.1" — build #49, libyuv 1.1→1.1.1)
    # e o fallback cp clássico NÃO satisfaz o resolve (versão mais velha
    # perde p/ a quebrada anunciada) → 6 rounds quebrados → abort sem
    # build. vercmp('2','1.1')>0: major+1 SEMPRE supera a quebrada (que
    # tem o mesmo major ou menor) e fica no formato válido.
    local bver brrel brmaj newrel parch d="/tmp/elite-bump/$nb_name"
    bver=$(printf '%s' "$bverrel" | rev | cut -d- -f2- | rev)
    brrel="${nb_verrel##*-}"                                       # rel da QUEBRADA
    brmaj="${brrel%%.*}"
    if [[ ! "$brmaj" =~ ^[0-9]+$ ]]; then
        # rel fora do formato pacote (epoch? sufixo?): honesto — cp clássico
        say "  ELITE-BUMP: rel quebrada '$brrel' fora do formato integer[.integer] — cp clássico"
        cp -f "$basepkg" "/var/cache/elite-local/${basepkg##*/}"
        return 0
    fi
    newrel=$(( brmaj + 1 ))
    parch=$(printf '%s' "${basepkg##*/}" | sed -nE 's/.*-(any|x86_64(_v3)?)\.pkg\.tar\.zst$/\1/p')
    [[ -n "$parch" ]] || parch=any
    rm -rf "$d" && mkdir -p "$d/payload"
    bsdtar -xf "$basepkg" -C "$d/payload" --exclude='.PKGINFO' --exclude='.MTREE' --exclude='.BUILDINFO'
    cat > "$d/PKGBUILD" <<EOP
pkgname=$nb_name
pkgver=$bver
pkgrel=$newrel
pkgdesc="ELITE baseline override (mirror CachyOS com skew travado — ver CHANGES v1.1)"
arch=($parch)
options=(!debug)
license=(unknown)
package() {
    cp -a "\$srcdir/../payload/." "\$pkgdir"/
}
EOP
    chown -R builder "$d"
    if runuser -l builder -c "cd $d && makepkg -f --noconfirm" \
       && cp "$d/"*.pkg.tar.zst /var/cache/elite-local/; then
        say "  ELITE-BUMP $nb_name $bverrel → $bver-$newrel (baseline repackeada: versão > quebrada, elite-local vence)"
        return 0
    fi
    say "  ELITE-BUMP falhou p/ $nb_name — caindo no comportamento clássico (cp do baseline)"
    cp -f "$basepkg" "/var/cache/elite-local/${basepkg##*/}"
    return 0
}

preflight() {
    local pc=/work/elite-build/profile/pacman.conf
    local plconf=/tmp/elite-preflight.conf
    # RAIZ DO RUN #18: o -Syw rodava no HOST, cujo local db (base-devel +
    # prep) já satisfaz dezenas de deps → elas ficavam FORA da closure e o
    # “cache completo” era mentira parcial (173.65 MiB de buraco — exato o
    # “Total Download Size” da transação do pacstrap, idêntico nos runs #17
    # e #18). O pacstrap resolve para um chroot de local db VAZIO → precisa
    # delas → cache miss → (no #17: download ao vivo + skew; no #18 selado:
    # file:// fatal no linux-api-headers-v3). Fix: resolver com --dbpath num
    # dir SÓ DE DBS — local db vazio = mesma visão do pacstrap. A closure do
    # preflight passa a ser EXATAMENTE a do pacstrap.
    local pfdb=/tmp/pf-db
    mkdir -p "$pfdb" "$pfdb/sync" # dbpath: sync dbs caem em $pfdb/sync/ (layout do pacman)
    cd /work/elite-build/profile

    # Evidência (pedido da revisão v1.6, R1): a mirrorlist do Arch é a única
    # superfície de curl que o selo não cobre (só o preflight a usa). Quais
    # mirrors estavam em jogo fica registrado no log para qualquer triagem.
    echo "    Mirrorlist Arch em uso (até 5):"
    grep -m5 '^Server' /etc/pacman.d/mirrorlist 2>/dev/null | sed 's/^/      /' || true

    # XferCommand PLANO (execv-safe: flags apenas). O logger de falhas
    # mora FORA do XferCommand (sonda pós-round), nunca dentro dele.
    sed -e 's@^XferCommand = .*@XferCommand = /usr/bin/curl -L -C - -f -o %o %u --retry 3 --retry-delay 3 --retry-all-errors@' \
        "$pc" > "$plconf"

    # conf Arch-only p/ os baselines: awk remove as SEÇÕES inteiras dos
    # repos Elite/Archcraft/CachyOS (grep -v deixaria SigLevel órfão)
    awk '/^\[/{keep = !($0 ~ /^\[(elite-local|archcraft|cachyos|cachyos-v3|cachyos-core-v3|cachyos-extra-v3)\]$/)} keep' \
        "$pc" > /tmp/elite-arch-only.conf

    # lista de alvos IDÊNTICA à do pacstrap: mkarchcraftiso passa
    # "grep -h '^[^#]'" verbatim (inclui qualificados "archcraft/grub")
    mapfile -t PL < <(grep -h '^[^#]' packages.x86_64)

    local round u u2 code fn base fu
    for round in 1 2 3; do
        say "Preflight round $round/3: -Syw de ${#PL[@]} alvos (só download; nada é instalado)"
        if pacman --config "$plconf" -b "$pfdb" -Syw --noconfirm "${PL[@]}" >/tmp/elite-pf.log 2>&1; then
            say "Preflight: cache completo — pacstrap offline dali em diante"
            return 0
        fi
        say "Preflight round $round: -Syw falhou — stderr do próprio -Syw (causa real; #19 escondeu isto aqui):"
        tail -25 /tmp/elite-pf.log || true
        say "Mapeando URLs quebradas (sonda HEAD paralela)"
        # --print-format '%l' (pacman 6+): URL p/ não-cacheado, file:// p/
        # cacheado — o grep deixa passar só as URLs (o conjunto quebrado).
        # stderr do -Sp vai p/ arquivo: se a lista vier vazia (flag inválida,
        # db sync, resolução), o ERRO REAL aparece no console — não só o
        # tail do -Syw (no run #16 "db sync quebrado?" era mentira: era
        # "unrecognized option '--print-uris'" do pacman 7, silenciado).
        mapfile -t URLS < <(pacman --config "$plconf" -b "$pfdb" -Sp --print-format '%l' --noconfirm "${PL[@]}" 2>/tmp/elite-sp.err \
            | grep -oE '^https?://[^ ]+\.pkg\.tar\.zst$' | sort -u || true)
        if (( ${#URLS[@]} == 0 )); then
            say "Preflight: -Sp não listou URLs — stderr do próprio -Sp (causa real):"
            head -5 /tmp/elite-sp.err || true
            say "tail do pacman -Syw do round:"
            tail -8 /tmp/elite-pf.log || true
            continue
        fi
        # sonda paralela: 16 HEADs simultâneos. -n1 = uma URL por invocação
        # (sem ele o xargs empilha todas num único sh: só a 1ª sairia).
        # SEM -I{}: trocaria também o "{}" interno de "%{http_code}".
        # A URL entra como $1 (append padrão do xargs); $0="sh".
        : > /tmp/elite-probe.txt
        printf '%s\n' "${URLS[@]}" | xargs -d '\n' -n1 -P 16 sh -c \
            'u=$1; c=$(curl -s -o /dev/null -w "%{http_code}" -m 25 --head "$u" 2>/dev/null) || c=000; echo "$c $u"' sh \
            >> /tmp/elite-probe.txt
        mapfile -t BAD < <(awk '$1 != "200" {print $2}' /tmp/elite-probe.txt | sort -u || true)
        if (( ${#BAD[@]} == 0 )); then
            say "Preflight: nenhuma URL quebrada (falha transiente de rede) — re-sincronizando"
            continue
        fi
        say "Preflight: ${#BAD[@]} URL(s) quebrada(s):"
        printf '  ELITE-FAIL %s\n' "${BAD[@]}"
        local injected=0
        for u in "${BAD[@]}"; do
            # gêmeo cdn77↔us: só é problema se faltar em AMBOS
            u2=$u
            [[ "$u" == *cdn77.cachyos.org* ]] && u2=${u/cdn77.cachyos.org/us.cachyos.org}
            # gêmeo REVERSO (#22: o skew ROTACIONA — libyuv/vid.stab estavam
            # no US, não no cdn77; sem esta regra o buraco do us só fecha via
            # baseline Arch, gastando rounds a mais)
            [[ "$u" == *us.cachyos.org* ]] && u2=${u/us.cachyos.org/cdn77.cachyos.org}
            code=$(curl -s -o /dev/null -w '%{http_code}' -m 25 --head "$u2" 2>/dev/null) || code=000
            if [[ "$code" == "200" ]]; then
                # SEMÂNTICA PACMAN (comprovada no #19): XferCommand NÃO tem
                # failover por servidor p/ PACOTES — servidor-1 falhar =
                # pacote falhar (o #17 "curou" só porque o skew durava ~30s
                # = o tempo da própria ladder; o do #19 dura HORAS). O us
                # tem o arquivo: baixa DIRETO p/ o cache — a verificação
                # sha256 do db na próxima rodada valida o conteúdo.
                if curl -fsSL -o "/var/cache/pacman/pkg/${u2##*/}" "$u2"; then
                    say "  baixado do mirror gêmeo (${u2#https://}) direto p/ o cache — ${u2##*/}"
                else
                    say "  gêmeo responde 200 no HEAD mas GET falhou — ${u2}"
                fi
                continue
            fi
            fn=${u##*/}
            base=$(printf '%s' "$fn" | sed -E 's/-(any|x86_64(_v3)?)\.pkg\.tar\.zst$//' | rev | cut -d- -f3- | rev)
            # fu = URL do PRÓPRIO pacote-alvo (NÃO da 1ª dependência!):
            # o -Sp com local db vazio resolve a transação inteira — tzdata,
            # glibc, gcc-libs… saem ANTES do alvo na lista; um head -1 cego
            # baixava a DEP como 'baseline' e o repack nascia com payload
            # alheio (build #50: libyuv-elite-2 com os arquivos da tzdata →
            # conflito 'exists in both tzdata and libyuv' no pacstrap).
            # awk -F/ com index($NF, "<base>-")==1: match por PREFIXO em
            # string FIXA (sem regex — nomes com ponto/plus como vid.stab).
            fu=$(pacman --config /tmp/elite-arch-only.conf -b "$pfdb" -Sp --print-format '%l' --noconfirm "$base" 2>/dev/null \
                 | grep -oE '^https?://[^ ]+\.pkg\.tar\.zst$' \
                 | awk -F/ -v pfx="$base-" 'index($NF, pfx) == 1' | head -1 || true)
            if [[ -n "$fu" ]]; then
                say "  $fn quebrado nos 2 mirrors → baseline Arch injetado no [elite-local]"
                # download com o NOME REAL do pacote: o elite_inject_bumped
                # deriva a versão da baseline de ${basepkg##*/} — um nome
                # genérico (/tmp/elite-baseline.pkg.tar.zst) entregaria
                # 'elite-2' de versão (build #50) e o resolve nunca fecharia.
                mkdir -p /tmp/elite-baseline
                if curl -fsSL -o "/tmp/elite-baseline/${fu##*/}" "$fu"; then
                    elite_inject_bumped "$fn" "/tmp/elite-baseline/${fu##*/}" && injected=1
                fi
            else
                say "  $fn quebrado e SEM baseline Arch — próximo round decide"
            fi
        done
        if (( injected )); then
            
# v2.1 — REORG: o bloco AUR duplicado que re-clonava e recompilava o
#  pwvucontrol aqui (~60 linhas copiadas do estágio principal, +4 min
#  quando disparava) foi REMOVIDO (E138: o estágio AUR inteiro morreu —
#  o mixer da casa é o pavucontrol do [cachyos-extra-v3], em repo).
#  Os pkg.tar.zst de brave-origin e wlrctl JÁ estão em
#  /var/cache/elite-local (estágio principal; persistidos entre runs pelo
#  cache do Actions) — o repo-add abaixo re-registra tudo junto com os
#  baselines injetados.
ls /var/cache/elite-local/brave-origin-*.pkg.tar.zst >/dev/null 2>&1 \
    || { echo "ELITE-FAIL: brave-origin ausente do [elite-local] (estágio principal)" >&2; exit 1; }
# v2.7.0 — o foco da dock: a fonte vendada do wlrctl tem que ter virado
# pacote no estágio principal (a build #110 morreu com 'target not found:
# wlrctl' — o pacote não existia em repo nenhum; agora nasce AQUI)
ls /var/cache/elite-local/wlrctl-*.pkg.tar.zst >/dev/null 2>&1 \
    || { echo "ELITE-FAIL: wlrctl ausente do [elite-local] (estágio principal — fonte vendada não compilou?)" >&2; exit 1; }

repo-add --quiet /var/cache/elite-local/elite-local.db.tar.gz /var/cache/elite-local/*.pkg.tar.zst
            cp /var/cache/elite-local/* /work/elite-build/profile/airootfs/var/cache/elite-local/
            say "  [elite-local] atualizado com baseline(s) — refazendo o round"
        fi
    done
    say "Preflight: 3 rounds sem fechar o cache — ABORTANDO com o diagnóstico acima (build com cache quebrado é tempo perdido)"
    return 1
}

# ── Selo pós-preflight: pacstrap OFFLINE, zero curl ──────────────────
#  O preflight VERIFICA (dbs ao vivo + cache completo). Sem o selo, o
#  pacstrap re-sincroniza dbs AO VIVO: dbs novos ≠ dbs verificados →
#  versões novas → cache miss → download ao vivo → skew de mirror →
#  curl 404 em escada. Foi exatamente assim que o run #17 emitiu ~118
#  curl-22 espalhados por 78 min MESMO com o preflight "perfeito": o sync
#  do pacstrap (02:56) pegou dbs diferentes dos do preflight (02:42).
#  E o run #18 revelou a SEGUNDA metade da verdade: o buraco de 173.65
#  MiB ("Total Download Size" idêntico nos 2 runs) vinha do -Syw rodando
#  no HOST — o local db do container (base-devel + prep) satisfez dezenas
#  de deps fora da closure. O preflight agora resolve com --dbpath num
#  dir só-de-dbs (local db vazio = visão do chroot) — closure idêntica.
#  O selo aponta TODOS os Server/Include https do conf de build para
#  file:///tmp/pf-db/sync — os MESMOS dbs que o preflight verificou. SigLevel
#  = Never nas seções Arch (core/extra/multilib) mata os probes .db.sig
#  (curl 37 no #18 — a única causa restante de ruído curl no pacstrap).
#  Idempotente via marcador '# elite-sealed'.
seal_build_conf() {
    local pc=/work/elite-build/profile/pacman.conf
    grep -q '^# elite-sealed' "$pc" && { say "Selo já aplicado (idempotente)"; return 0; }

    # Assert (da revisão v1.6, R2): todo .db que o pacstrap vai ler precisa
    # existir no pf-db ANTES do selo — sem isto, um db ausente viraria falha
    # file:// LOCAL no meio do pacstrap, com mensagem confusa.
    local missing=() s
    for s in $(awk '/^\[/{sec=$0; gsub(/[][]/,"",sec); if (sec!="options" && sec!="elite-local") print sec}' "$pc"); do
        [[ -s /tmp/pf-db/sync/$s.db ]] || missing+=("$s")
    done
    if ((${#missing[@]})); then
        say "SELO ABORTADO: db(s) ausente(s) em /tmp/pf-db: ${missing[*]} — preflight não fechou estes repos"
        return 1
    fi

    sed -i -E \
        -e 's@^Server = https?://.+@Server = file:///tmp/pf-db/sync@' \
        -e 's@^Include = /etc/pacman\.d/mirrorlist$@Server = file:///tmp/pf-db/sync@' \
        -e 's@^Include = /etc/pacman\.d/archcraft-mirrorlist$@Server = file:///tmp/pf-db/sync@' \
        -e '/^DownloadUser = /d' \
        -e 's@^\[core\]$@[core]\nSigLevel = Never@' \
        -e 's@^\[extra\]$@[extra]\nSigLevel = Never@' \
        -e 's@^\[multilib\]$@[multilib]\nSigLevel = Never@' \
        "$pc"
    sed -i '1i # elite-sealed (pacstrap offline; dbs = os que o preflight verificou em /tmp/pf-db)' "$pc"
    say "Conf de build lacrado: dbs file:///tmp/pf-db/sync (pacstrap offline, zero curl)"
    # Prova de evidência no log (R2): mapa seção → Server efetivo pós-selo
    awk '/^\[/{sec=$0} /^[[:space:]]*Server/{print "    " sec " " $0}' "$pc"
}

# E101 — SELO 2 · A RESOLUÇÃO LACRADA ENTREGA O PACOTE DE HOJE: o selo 1
#  olhou o db no ponto de criação; este olha o QUE O PACMAN RESOLVE com o
#  conf lacrado (dbs de /tmp/pf-db — os MESMOS que o pacstrap offline
#  consome). É a prova de ponta a ponta: db → resolver → a versão que
#  ENTRA na ISO. Se o fóssil voltar por qualquer caminho (repo-add,
#  sync, skew), o build morre aqui — no minuto 6, não no QEMU do minuto 40.
selo_elite_system_resolve() {
    local want got
    want="${ES_STAGED#elite-system-}"          # 1.0-44-x86_64.pkg.tar.zst
    want="${want%-x86_64.pkg.tar.zst}"         # 1.0-44
    got="$(pacman --config /work/elite-build/profile/pacman.conf -b /tmp/pf-db \
             -Sp --print-format '%n %v' --noconfirm elite-system 2>/dev/null \
             | awk '$1=="elite-system"{print $2; exit}')"
    if [ -z "$got" ]; then
        say "selo E101: o resolve lacrado não respondeu — stderr inteiro (honestidade do preflight):"
        pacman --config /work/elite-build/profile/pacman.conf -b /tmp/pf-db \
             -Sp --print-format '%n %v' --noconfirm elite-system || true
        echo "ELITE-FAIL: selo E101 — o resolve lacrado não achou elite-system" >&2
        return 1
    fi
    if [ "$got" != "$want" ]; then
        echo "ELITE-FAIL: selo E101 — o resolve lacrado entrega elite-system $got mas o build pariu $want (a ISO nasceria com pacote velho — classe da run #153)" >&2
        return 1
    fi
    say "E101 selo 2: o resolve lacrado entrega elite-system $want (o de hoje)"
}

say "Construindo ISO (mkarchcraftiso — fork oficial do Archcraft)"
mkdir -p /mnt/iso-work /work/out
cd elite-build/profile
for attempt in 1 2; do
    rm -rf /mnt/iso-work
    if preflight && seal_build_conf && selo_elite_system_resolve && ./mkarchcraftiso -v -w /mnt/iso-work -o /work/out . ; then
        break
    fi
    if [ "$attempt" = "2" ]; then
        echo "FALHOU nas 2 tentativas — causa acima nos logs (falha determinística não se cura com retry; não há 3ª)"
        exit 1
    fi
    say "Tentativa $attempt falhou — UMA retentativa, sem sleep (cache do preflight acelera a 2ª)"
done

say "Checksums + relatório de tamanho"
cd /work/out
sha256sum -- * > sha256sums.txt
cat sha256sums.txt
ls -lh --si

# fix #25: out/ é gravado pelo container (root); os steps do RUNNER (split
# do release, >2GiB) precisam escrever nele — sem isto o 'split' morre com
# 'Permission denied' em .part-00. chown p/ o uid/gid do runner.
if [[ -n "${HOST_UID:-}" ]]; then
    chown -R "${HOST_UID}:${HOST_GID:-$HOST_UID}" /work/out 2>/dev/null || true
    chown -R "${HOST_UID}:${HOST_GID:-$HOST_UID}" "$ELITE_CARGO_TARGET_DIR" 2>/dev/null || true
    say "out/ entregue ao uid do runner (${HOST_UID}) — steps de release podem escrever"
fi
