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
pacman -Syu --noconfirm --needed \
    git rsync curl archiso xorriso mtools dosfstools \
    e2fsprogs squashfs-tools openssl arch-install-scripts \
    base-devel sudo \
    meson ninja wayland wayland-protocols libxkbcommon

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
# PIN de commit (R6 do auditor mimo): a URL branch-driven (refs/heads/master)
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

# makepkg se recusa a rodar como root — usuário builder descartável
useradd -m builder 2>/dev/null || true
chown -R builder /tmp/elite-src
for pkgdir in python-pywal qt5-virtualkeyboard wlrctl; do
    (cd "/tmp/elite-src/$pkgdir" && runuser -l builder -c "cd /tmp/elite-src/$pkgdir && makepkg -f --noconfirm") \
        || { echo "FALHA ao construir $pkgdir"; exit 1; }
    cp "/tmp/elite-src/$pkgdir/"*.pkg.tar.zst /var/cache/elite-local/
done
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


# ── v1.4: BRAVE ORIGIN (release oficial) → [elite-local] ─────────────
#  Diretriz do dono (burn test da v1.3 AO VIVO no rig dele, 2026-10-22):
#  o navegador padrão da Elite passa a ser o BRAVE ORIGIN — o build
#  oficial brave-origin-*.zip das releases da Brave (produto de primeira
#  classe: linux amd64/arm64 + darwin; o PROFILE do usuário segue o do
#  Brave de sempre: BraveSoftware/Brave-Browser — o preseed de
#  custom_chrome_frame mora lá; verificado no binário: app_id continua
#  "brave-browser"). Empacotado AQUI (mesmo padrão dos stubs acima) em
#  vez de clonar o AUR: versão PINADA em 1.98.60 (determinismo —
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
say "Estágio Brave ORIGIN 1.98.60 (release oficial) → /var/cache/elite-local/"
# v2.1 — cache do Actions persiste /var/cache/elite-local entre runs
#  (build.yml monta .ci-cache/elite-local no container): pkg.tar.zst
#  presente = bits cujos sources passaram no sha256 da run que o
#  construiu. Cache miss = download/rebuild (comportamento original).
if ls /var/cache/elite-local/brave-origin-*.pkg.tar.zst >/dev/null 2>&1; then
    say "  cache hit: $(ls /var/cache/elite-local/brave-origin-*.pkg.tar.zst | head -1 | xargs -n1 basename) — download/rebuild pulados"
    sha256sum /var/cache/elite-local/brave-origin-*.pkg.tar.zst
else
mkdir -p /tmp/elite-src/brave-origin
cat > /tmp/elite-src/brave-origin/PKGBUILD <<'EOPKGBUILD'
pkgname=brave-origin
pkgver=1.98.60
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
            '39a69cf12b5787f789d0a0b013f32253bddc9004d03e36c679a8daa61821b6e8')

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
    say "  ok: brave-origin 1.98.60 (Brave ORIGIN oficial, sha256 verificado)"
else
    echo "ELITE-FAIL: makepkg do brave-origin (fonte/CDN fora?) — sem retry: fonte é GitHub Releases da Brave" >&2
    exit 1
fi
fi  # v2.1 — fim do guard de cache do estágio brave-origin

# ── v1.1: estágio AUR → [elite-local] (pwvucontrol) ──────────────────
#  pwvucontrol não existe nos repos oficiais ( conferido via
#  archlinux.org/packages/search). O build clona o AUR, compila como
#  usuário descartável e o pacote entra no repo file:// — o pacstrap
#  selado o resolve OFFLINE como qualquer outro. Falha de CDN/AUR após
#  2 tentativas = abort com diagnóstico (mesma filosofia do preflight:
#  fail loud no build, nunca no boot).
#  v1.4: brave-bin SAIU daqui — o navegador agora é o brave-origin do
#  estágio anterior (release oficial pinado; o AUR nem é consultado).
say "Estágio AUR: pwvucontrol → /var/cache/elite-local/"
# v2.1 — evidência de proveniência do AUR (supply-chain): HEAD commit e
#  pkgver vão para o log de TODA run que consulta a fonte; cache hit
#  (pkg persistido pelo Actions) pula o rebuild por completo.
if ls /var/cache/elite-local/pwvucontrol-*.pkg.tar.zst >/dev/null 2>&1; then
    say "  cache hit: $(ls /var/cache/elite-local/pwvucontrol-*.pkg.tar.zst | head -1 | xargs -n1 basename) — rebuild pulado"
    sha256sum /var/cache/elite-local/pwvucontrol-*.pkg.tar.zst
else
    if git clone --depth=1 --quiet https://aur.archlinux.org/pwvucontrol.git /tmp/elite-src/aur/pwvucontrol-probe 2>/dev/null; then
        say "  AUR HEAD: $(git -C /tmp/elite-src/aur/pwvucontrol-probe rev-parse HEAD)"
        say "  AUR pkgver: $(grep -m1 '^pkgver=' /tmp/elite-src/aur/pwvucontrol-probe/PKGBUILD | cut -d= -f2)"
    else
        say "  (probe de evidência do AUR falhou — o aur_build abaixo registra a falha real, se houver)"
    fi
    mkdir -p /tmp/elite-src/aur
fi
# makepkg -s (syncdeps) instala deps de build via sudo — regra descartável
printf 'builder ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/builder
chmod 440 /etc/sudoers.d/builder
aur_build() { # $1 = nome do pacote AUR
    local pkg=$1 try
    for try in 1 2; do
        rm -rf "/tmp/elite-src/aur/$pkg"
        if git clone --depth=1 --quiet "https://aur.archlinux.org/${pkg}.git" "/tmp/elite-src/aur/$pkg"; then
            chown -R builder "/tmp/elite-src/aur/$pkg"
            # --skippgpcheck: PKGBUILDs de bin sem assinatura PGP própria;
            #  sha256 do source continua verificado pelo makepkg
            if runuser -l builder -c "cd /tmp/elite-src/aur/$pkg && makepkg -sf --noconfirm --skippgpcheck" \
               && cp /tmp/elite-src/aur/$pkg/*.pkg.tar.zst /var/cache/elite-local/; then
                say "  ok: $pkg (tentativa $try)"
                return 0
            fi
            say "  makepkg falhou p/ $pkg (tentativa $try) — últimos logs:"
            tail -15 "/tmp/elite-src/aur/$pkg"/*.log 2>/dev/null || true
        else
            say "  git clone do AUR falhou p/ $pkg (tentativa $try)"
        fi
    done
    echo "ELITE-FAIL: não foi possível construir '$pkg' (AUR/CDN fora?) — 2 tentativas" >&2
    return 1
}
if ! ls /var/cache/elite-local/pwvucontrol-*.pkg.tar.zst >/dev/null 2>&1; then
    aur_build pwvucontrol  || exit 1
fi
rm -f /etc/sudoers.d/builder

repo-add --quiet /var/cache/elite-local/elite-local.db.tar.gz /var/cache/elite-local/*.pkg.tar.zst
ls -la /var/cache/elite-local/

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

    # Evidência (pedido do auditor mimo, R1): a mirrorlist do Arch é a única
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
#  quando disparava) foi REMOVIDO. Os pkg.tar.zst de pwvucontrol e
#  brave-origin JÁ estão em /var/cache/elite-local (estágio principal;
#  persistidos entre runs pelo cache do Actions) — o repo-add abaixo
#  re-registra tudo junto com os baselines injetados.
ls /var/cache/elite-local/pwvucontrol-*.pkg.tar.zst >/dev/null 2>&1 \
    || { echo "ELITE-FAIL: pwvucontrol ausente do [elite-local] (estágio principal)" >&2; exit 1; }
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

    # Assert (auditor mimo, R2): todo .db que o pacstrap vai ler precisa
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

say "Construindo ISO (mkarchcraftiso — fork oficial do Archcraft)"
mkdir -p /mnt/iso-work /work/out
cd elite-build/profile
for attempt in 1 2; do
    rm -rf /mnt/iso-work
    if preflight && seal_build_conf && ./mkarchcraftiso -v -w /mnt/iso-work -o /work/out . ; then
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
    say "out/ entregue ao uid do runner (${HOST_UID}) — steps de release podem escrever"
fi
