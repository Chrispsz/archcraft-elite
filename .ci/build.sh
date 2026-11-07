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
    pacman -Syu --noconfirm --needed git rsync curl base-devel sudo python \
        wayland wayland-protocols libxkbcommon wlopm
else
    pacman -Syu --noconfirm --needed \
        git rsync curl archiso xorriso mtools dosfstools \
        e2fsprogs squashfs-tools openssl arch-install-scripts \
        base-devel sudo \
        meson ninja wayland wayland-protocols libxkbcommon wlopm
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

# ── v2.10.1: CRAFT-TOPLEVEL (o alt-tab da dock) — FONTE NO PRÓPRIO REPO ──
#  O dono pediu a v2.10 com "a dock tendo essa funcionalidade de alt tab
#  perfeitamente pra navegar entre os programas abertos… ou até mesmo um
#  atalho pra isso clicável na dock". O wlrctl não lista janelas (limitação
#  honesta da v2.10.0) — a cura é o protocolo DIRETO: este daemon fala
#  zwlr_foreign_toplevel_management_v1 com o labwc e serve LIST/ACT/CLOSE/
#  CYCLE num socket UNIX da sessão. A fonte vem do REPO (vendor/), com o
#  sha256 PINADO como manda a casa — mudou 1 byte, o makepkg PARA.
#  Deps: só libwayland-client (os headers que o HOST usa para compilar o
#  wlrctl servem — a esteira é a mesma, 4º pacote da fila).
mkdir -p /tmp/elite-src/craft-toplevel
cp /work/vendor/craft-toplevel.c /tmp/elite-src/craft-toplevel/

# ═══ E50 — A PONTE PARA O PACOTE ÚNICO (a era dos dois veículos encerra) ═
# O dono: 'a atualização do sistema como um todo deveria ser em um só
# pacote — já atualizava todo o sistema com um só pacote'. O elite-system
# (pkgname único, replaces/conflicts do par legado) é essa era nova. Mas
# o rig que NUNCA teve pacote algum roda um craft-update sem alvos
# explícitos: o -Syu atualiza o INSTALADO e NADA instala o pacote novo
# sozinho. A ponte mora no ÚNICO pacote da casa que TODO rig tem (o
# craft-toplevel): hook PostTransaction + elite-adopt em /usr/share/elite
# puxam o elite-system — o pacman SUBSTITUI o par legado na MESMA
# transação (replaces) e o rig salta DIRETO para a era de um pacote só.
# Veículo único presente = calado para sempre; ausente = a adoção nasce
# DESPRENDIDA (pacman NÃO roda dentro do hook — o lock da transação-mãe
# ainda vive), espera o lock soltar e entrega a conclusão ao
# craft-update --adotar: sessão inteira com o código novo
# (dock/toplevel/áudio/idle) + cadência ligada, UMA rodada de update,
# sem relogin — a resposta final ao 'atualizei e ficou igual'.
cat > /tmp/elite-src/craft-toplevel/elite-adopt <<'EOADOPT'
#!/bin/sh
# elite-adopt — E50: A PONTE PARA O PACOTE ÚNICO (o salto de era).
# O rig que nunca teve pacote algum roda um craft-update sem alvos
# explícitos: o -Syu atualiza o INSTALADO e NADA instala o pacote novo
# sozinho. O gatilho mora no hook PostTransaction do craft-toplevel (o
# ÚNICO pacote da casa que TODO rig tem) e puxa o ELITE-SYSTEM — o
# SISTEMA INTEIRO em um pacote (diretriz do dono); o pacman substitui o
# par legado (elite-craft + craft-toplevel) na MESMA transação
# (replaces/conflicts). Regras:
#   · elite-system presente → calado para sempre (custo zero por
#     transação — a era da ponte acabou, o hook nunca mais acorda);
#   · elite-system ausente  → a adoção nasce DESPRENDIDA (pacman NÃO roda
#     dentro do hook — o lock da transação que o pariu ainda vive),
#     espera o lock soltar, puxa o pacote único e entrega a conclusão ao
#     craft-update --adotar (sessão viva: dock/toplevel/áudio/idle +
#     cadência — UMA rodada de update, sem relogin).
# Papel: /var/log/elite-update.log com o teto E36. Portas de prova (a
# mesma escola do VMARK/ELITE_UNIT_DIR do craft-update):
#   ELITE_ADOPT_SYNC=1    o corpo corre ACOPLADO (a suíte observa
#                         comportamento; o hook real nunca liga)
#   ELITE_UPDATE_LOG      a morada do papel
#   ELITE_CRAFT_UPDATE    o craft-update da conclusão (prova aponta o repo)
#   ELITE_ADOPT_SETTLE    a espera inicial do lock (default 3s)
#   ELITE_ADOPT_POLL      o passo da espera do lock (default 3s)
LOG="${ELITE_UPDATE_LOG:-/var/log/elite-update.log}"
CU="${ELITE_CRAFT_UPDATE:-/usr/local/bin/craft-update}"
SETTLE="${ELITE_ADOPT_SETTLE:-3}"
POLL="${ELITE_ADOPT_POLL:-3}"

adopt_body() {
    _ec="$1" _tl="$2"
    sleep "$SETTLE"
    # o lock da transação-mãe pode ainda viver — espera honesta com teto
    _n=0
    while [ "$_n" -lt 20 ]; do
        command -v fuser >/dev/null 2>&1 || break
        fuser /var/lib/pacman/db.lck >/dev/null 2>&1 || break
        sleep "$POLL"
        _n=$((_n + 1))
    done
    if [ -f "$LOG" ] && [ "$(wc -c <"$LOG" 2>/dev/null || echo 0)" -gt 262144 ]; then
        tail -c 131072 "$LOG" >"$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" || true
    fi
    printf '[%s] adotar: PACOTE ÚNICO elite-system ausente — a ponte puxa o sistema inteiro (hook do craft-toplevel, E50)\n' "$(date '+%F %T')" >>"$LOG" 2>/dev/null || true
    if ! pacman -Syu --needed --noconfirm --overwrite '/usr/local/bin/*' \
            --overwrite '/etc/systemd/system/elite-*' \
            elite-system >>"$LOG" 2>&1; then
        printf '[%s] adotar: pacman RECUSOU a adoção — a prova está acima no log (o próximo update tenta de novo)\n' "$(date '+%F %T')" >>"$LOG" 2>/dev/null || true
        return 1
    fi
    # o craft-update no disco AGORA é o novo (veio no pacote único) — a
    # sessão viva recebe a cura POR ELE (fonte única da lógica de refresh);
    # os 'antes' capturados NO HOOK narram a transição: o pacote único vai
    # VAZIO na frente (a ADOÇÃO já é a mudança), o par legado na sequência
    "$CU" --adotar "" "$_ec" "$_tl" >>"$LOG" 2>&1 || true
    printf '[%s] adotar: adoção concluída — o veículo vive e a sessão recebeu o código novo\n' "$(date '+%F %T')" >>"$LOG" 2>/dev/null || true
}

# a reentrada do corpo desprendido (o pai que forka passa --body)
if [ "${1:-}" = "--body" ]; then
    adopt_body "${2:-}" "${3:-}"
    exit 0
fi

[ "$(id -u)" = 0 ] || exit 0
command -v pacman >/dev/null 2>&1 || exit 0
_es="$(pacman -Q elite-system 2>/dev/null | awk '{print $2}')"
[ -n "$_es" ] && exit 0    # o PACOTE ÚNICO já vive — hook calado, custo zero
_ec="$(pacman -Q elite-craft 2>/dev/null | awk '{print $2}')"
_tl="$(pacman -Q craft-toplevel 2>/dev/null | awk '{print $2}')"

if [ "${ELITE_ADOPT_SYNC:-0}" = "1" ]; then
    adopt_body "$_ec" "$_tl"
    exit 0
fi
setsid "$0" --body "$_ec" "$_tl" >/dev/null 2>&1 </dev/null &
exit 0
EOADOPT
cat > /tmp/elite-src/craft-toplevel/elite-adopt.hook <<'EOHOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = craft-toplevel

[Action]
Description = Elite: a ponte puxa o PACOTE ÚNICO elite-system (o rig velho salta de era — E50)
When = PostTransaction
Exec = /usr/share/elite/elite-adopt
EOHOOK

cat > /tmp/elite-src/craft-toplevel/PKGBUILD <<'EOPKGBUILD'
pkgname=craft-toplevel
pkgver=1.0
# v2.10.7 — O ACK HONESTO: o rig 1º-install da 10.6 flagrou ACT com ACK e
# sem foco na tela (dump 0qmq) — o daemon agora cobra a prova do compositor
# (state activated confirma; state alheio/timeout 2s denuncia) em toplevel.log
# E41 — O PKGREL QUE NÃO SUBIU (achado 2026-11-03, pergunta do dono sobre a
# marcação de programas abertos): a E38 trocou o C (PUSH EVT — o sha acima
# é o conteúdo novo) e deixou pkgrel=2 — o MESMO 1.0-2 que os rigs
# instalados já carregam (dump do dono 10-29: 'craft-toplevel 1.0-2').
# pacman compara VERSÃO, nunca bytes: o -Syu do craft-update via
# [elite-local] comparava 1.0-2 == 1.0-2 e PULAVA — o daemon do EVT nunca
# chegaria a máquina instalada NENHUMA por update (a ISO nova não padece:
# instalação fresca lê o repo ATUAL). A lei daqui em diante: conteúdo da
# casa muda → pkgrel sobe NO MESMO commit.
# E49 — o pacote carrega a ADOÇÃO DE UMA VIA (elite-adopt + hook): o rig
# da era pré-E46 roda um craft-update sem alvos explícitos e NUNCA adota
# o veículo por si — o gatilho viaja no ÚNICO pacote da casa que TODO rig
# tem; UMA rodada de update fecha tudo (veículo + sessão viva + cadência).
# E50 — A ÚLTIMA VERSÃO DO PAR: o pacote vira PONTE — o hook puxa o
# ELITE-SYSTEM (o sistema inteiro em um pacote, replaces/conflicts do par
# legado) e o rig salta de era na MESMA transação. O daemon continua
# aqui (o rig cuja ponte falha offline segue funcional até a próxima
# dose). Lei E41: pkgrel NO MESMO commit.
# E71 — O PARENT QUE MATAVA A CONEXÃO (dump e8xl do dono: 'a dock ainda é
#     bugada — o indicativo de aplicativos abertos somem do nada e as
#     ações se comportam como se o programa não estivesse aberto'; 449
#     mortes / 488 restarts em 1h36): o evento parent era declarado 'o'
#     SECO — o XML oficial é allow-null="true" (desde a v2) e o
#     labwc/wlroots manda parent(NULL) quando uma janela perde o pai. O
#     demarshal da libwayland rejeita NULL em não-nulável ("NULL object
#     received on non-nullable type, message parent(o)") e MATA a conexão
#     inteira: o renascido servia '0 janelas' com a sessão CHEIA, a dock
#     recebia LIST vazio VÁLIDO, apagava os indicadores e o clique
#     lançava DUPLICADO — em loop. A cura é 1 caractere ('?o' nulável)
#     + o evento nomeado no enum e ignorado de graça (a dock não o usa).
#     pkgrel 5→6 NO MESMO COMMIT (lei E41 — o C do daemon mudou).
pkgrel=6
pkgdesc='Daemon wlr-foreign-toplevel da Elite — janelas por id (LIST/ACT/CLOSE/CYCLE + anel MRU) para a dock comutar de verdade'
arch=(x86_64)
url=https://github.com/Chrispsz/archcraft-elite
license=(GPL3)
depends=(wayland)
# E43 — sem pacote -debug (gcc -s já entrega o binário limpo; o -debug
# era asset gorduroso no release — o dono perguntou 'porque está saindo
# tantos assets?')
options=(!debug)
source=("craft-toplevel.c")
# E71 — o sha do C com o parent NULÁVEL ('?o') + EVT_PARENT no dispatcher
sha256sums=('f719c2f0582f0787a26440ebc5566408d5889d8dc037e91505384efb9544f258')
build() {
    gcc -O2 -Wall -Wextra -s -o craft-toplevel craft-toplevel.c -lwayland-client
}
package() {
    install -Dm755 craft-toplevel "${pkgdir}/usr/local/bin/craft-toplevel"
    install -Dm644 craft-toplevel.c "${pkgdir}/usr/local/share/elite/src/craft-toplevel.c"
    # E49 — a adoção de UMA VIA: hook + gatilho (fora de /usr/local/bin —
    # o elite-craft reivindica os bins da casa; aqui não há briga de dono).
    # Os gêmeos moram no STARTDIR (nascem ao lado do PKGBUILD, payload
    # GERADO — não são source=() e não carregam sha256); o package() roda
    # no srcdir — o CI desmentiu a 1ª forma (run 41893237128: 'A failure
    # occurred in package()' — install sem caminho = arquivo não visto).
    install -Dm755 "${startdir}/elite-adopt" "${pkgdir}/usr/share/elite/elite-adopt"
    install -Dm644 "${startdir}/elite-adopt.hook" "${pkgdir}/usr/share/libalpm/hooks/elite-adopt.hook"
}
EOPKGBUILD

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
cp /work/vendor/craft-toplevel.c /tmp/elite-src/elite-system/
# caminho ABSOLUTO: aqui o CWD é /tmp/elite-src/<pkg> (o cd da seção pywal
# acima) — o relativo nasceria vazio (a lição vai no próprio comentário).
for f in /work/elite/airootfs/usr/local/bin/*; do
    b="${f##*/}"
    # o daemon NÃO vem do overlay — nasce do C compilado no build()
    # (fonte única vendada com sha256; o skip é cinto e suspensório)
    [ "$b" = "craft-toplevel" ] && continue
    printf '%s\n' "$b"
done > /tmp/elite-src/elite-system/files/MANIFEST
while read -r f; do
    cp -p "/work/elite/airootfs/usr/local/bin/$f" /tmp/elite-src/elite-system/files/usr/local/bin/
done < /tmp/elite-src/elite-system/files/MANIFEST
# as units de SISTEMA da casa entram no pacote: sem elas, o rig instalado
# nunca recebe a cadência — a mesma classe da ferida dos bins. Só as
# units de topo da casa (elite-*); wants symlinks e drop-ins de terceiros
# seguem de overlay.
shopt -s nullglob
for u in /work/elite/airootfs/etc/systemd/system/elite-*.service \
         /work/elite/airootfs/etc/systemd/system/elite-*.timer; do
    cp -p "$u" /tmp/elite-src/elite-system/files/etc/systemd/system/
done
shopt -u nullglob
# E63 — A VOLTA DA IMAGEM viaja NO PACOTE: o hook de resume é a rede de
# sistema que religa o display no wake (o monitor 'sem sinal, luz
# vermelha' do dono) — fora do pacote ele NUNCA chegaria ao rig pelo
# canal (system-sleep nunca foi veículo de adoção; este hook NASCE
# empacotado, a lei de um dono por caminho).
mkdir -p /tmp/elite-src/elite-system/files/usr/lib/systemd/system-sleep
cp -p /work/elite/airootfs/usr/lib/systemd/system-sleep/elite-resume-display \
      /tmp/elite-src/elite-system/files/usr/lib/systemd/system-sleep/
cp -p /work/elite/airootfs/usr/lib/systemd/system-sleep/elite-resume-usb \
      /tmp/elite-src/elite-system/files/usr/lib/systemd/system-sleep/
# E73 — o retrato do terminal viaja NO PACOTE (lição E63: fora do pacote
# nunca chega ao rig pelo canal). O craft-hello aponta pra cá; o usuário
# que quiser a própria cara cria ~/.config/fastfetch/config.jsonc e o
# dele VENCE (config de usuário intocado — lei do domínio v3).
mkdir -p /tmp/elite-src/elite-system/files/usr/local/share/elite/fastfetch
cp -p /work/elite/airootfs/usr/local/share/elite/fastfetch/config.jsonc \
      /tmp/elite-src/elite-system/files/usr/local/share/elite/fastfetch/config.jsonc
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
python3 - /tmp/elite-src/elite-system <<'PYE50'
import sys, pathlib
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
# E75 — o hook libalpm da casa (dono ÚNICO no pacote; pacman remove sozinho
# na desinstalação — arquivo pertence ao pacote, sem dança de adoção)
pt_install = '    install -Dm644 "${startdir}/elite-post-transaction.hook" "${pkgdir}/usr/share/libalpm/hooks/elite-post-transaction.hook"\n'
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
#     (1) vendor/craft-toplevel.c: o parent vira '?o' (nulável — 1
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
pkgrel=29
pkgdesc='O sistema da Elite em um pacote só — craft-*, elite-*, exo-open, daemon de janelas e units da cadência; substitui elite-craft/craft-toplevel'
arch=(x86_64)
url=https://github.com/Chrispsz/archcraft-elite
license=(GPL3)
depends=(bash python wayland wlopm)
# E50 — A SUBSTITUIÇÃO DE ERA: conflita e substitui os DOIS veículos
# legados — o -Syu do craft-update (alvo elite-system) remove o par e
# instala o único na MESMA transação; configs de usuário (~) NUNCA são
# tocados (o domínio da casa continua sendo /usr/local/bin + /etc/systemd).
replaces=('elite-craft' 'craft-toplevel')
conflicts=('elite-craft' 'craft-toplevel')
# sem -debug (shell/python + binário já compilado com -s; nada a tirar
# símbolo)
options=(!debug !strip)
source=("craft-toplevel.c")
sha256sums=('f719c2f0582f0787a26440ebc5566408d5889d8dc037e91505384efb9544f258')
build() {{
    gcc -O2 -Wall -Wextra -s -o craft-toplevel craft-toplevel.c -lwayland-client
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
{unit_loop}{hook_rm}{ff_rm}    return 0
}}
package() {{
    install -d "${{pkgdir}}/usr/local/bin"
    cp -a "${{startdir}}/files/usr/local/bin/." "${{pkgdir}}/usr/local/bin/"
    install -m755 craft-toplevel "${{pkgdir}}/usr/local/bin/craft-toplevel"
    # a fonte do daemon viaja no pacote (transparência — o mesmo papel que
    # ela tinha no craft-toplevel legado)
    install -Dm644 craft-toplevel.c "${{pkgdir}}/usr/local/share/elite/src/craft-toplevel.c"
{unit_install}{hook_install}{ff_install}{pt_install}}}
"""
(d / 'PKGBUILD').write_text(pkg)
PYE50

# makepkg se recusa a rodar como root — usuário builder descartável
useradd -m builder 2>/dev/null || true
chown -R builder /tmp/elite-src
# E43 — PACKAGES_ONLY=1 (canal diário, publish-packages.yml): só os
# pacotes de CÓDIGO DE CASA — pywal/qt5vk/wlrctl não mudam no dia a dia
# (o repo completo do release vivo entra no job por download+repo-add).
PKG_LIST=(python-pywal qt5-virtualkeyboard wlrctl craft-toplevel elite-system)
if [[ "${PACKAGES_ONLY:-0}" == "1" ]]; then
    PKG_LIST=(craft-toplevel elite-system)
fi
for pkgdir in "${PKG_LIST[@]}"; do
    (cd "/tmp/elite-src/$pkgdir" && runuser -l builder -c "cd /tmp/elite-src/$pkgdir && makepkg -f --noconfirm") \
        || { echo "FALHA ao construir $pkgdir"; exit 1; }
    cp "/tmp/elite-src/$pkgdir/"*.pkg.tar.zst /var/cache/elite-local/
done
if [[ "${PACKAGES_ONLY:-0}" == "1" ]]; then
    say "PACKAGES_ONLY=1 — pacotes da casa prontos (canal diário E43); ISO não construída"
    mkdir -p /work/out/pacotes
    cp /tmp/elite-src/*/*.pkg.tar.zst /work/out/pacotes/
    ( cd /work/out/pacotes && sha256sum *.pkg.tar.zst > sha256sums-pacotes.txt )
    ls -la /work/out/pacotes/
    chown -R "${HOST_UID:-1000}:${HOST_GID:-1000}" /work/out 2>/dev/null || true
    exit 0
fi
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
say "Estágio Brave ORIGIN 1.98.63 (release oficial) → /var/cache/elite-local/"
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
pkgver=1.98.63
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
            '7714b3c2bb3e92c14f8f8ab373e2d298ff941abe1d81589c21c5f9227ac07c0b')

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
    say "  ok: brave-origin 1.98.63 (Brave ORIGIN oficial, sha256 verificado)"
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
    local pkg=$1 try logf
    for try in 1 2; do
        rm -rf "/tmp/elite-src/aur/$pkg"
        logf="/tmp/elite-src/${pkg}-try${try}.log"
        if git clone --depth=1 --quiet "https://aur.archlinux.org/${pkg}.git" "/tmp/elite-src/aur/$pkg"; then
            chown -R builder "/tmp/elite-src/aur/$pkg"
            # --skippgpcheck: PKGBUILDs de bin sem assinatura PGP própria;
            #  sha256 do source continua verificado pelo makepkg
            # v2.10.5 — A SAÍDA DA TENTATIVA VAI PRO ARQUIVO, NÃO PRO LOG
            # PRINCIPAL: o 'target not found' da tentativa 1 manchava o log
            # de um build que a tentativa 2 CURAVA — e o forense (que é
            # CIÊNCIA desde a v1.4, onde 'target not found' foi o crime
            # real) reprovava a ISO sã. A prova da cura é o makepkg ok +
            # repo-add; na FALHA FINAL o log integral vai pro console
            # (evidência completa) e o build morre honesto.
            if runuser -l builder -c "cd /tmp/elite-src/aur/$pkg && makepkg -sf --noconfirm --skippgpcheck" >"$logf" 2>&1 \
               && cp /tmp/elite-src/aur/$pkg/*.pkg.tar.zst /var/cache/elite-local/; then
                say "  ok: $pkg (tentativa $try)"
                return 0
            fi
            say "  makepkg falhou p/ $pkg (tentativa $try) — log integral em $logf"
            # v2.10.6 — o tail da TENTATIVA 1 não vai mais pro log principal:
            # o stderr do makepkg morto (ex. 'target not found' de CDN)
            # manchava o log de um build que a tentativa 2 CURAVA e o
            # forense (ciência desde a v1.4) reprovaria a ISO sã. O tail
            # só sai na FALHA FINAL (tentativa 2), junto com o ELITE-FAIL.
            if [ "$try" -eq 2 ]; then
                tail -15 "$logf" 2>/dev/null || true
            fi
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
# E32 — pacman consulta <repo>.db SEM sufixo: o repo-add JÁ cria um SYMLINK
# elite-local.db → elite-local.db.tar.gz (a run 41254942475 flagrou: cp
# contra o próprio symlink = 'are the same file', exit 1 no set -e). O
# rm -f antes do cp garante ARQUIVO REAL (o symlink não viaja bem no
# artifact; o E8 preserva estes 2 arquivos na ISO p/ o file:// do conf)
rm -f /var/cache/elite-local/elite-local.db && cp /var/cache/elite-local/elite-local.db.tar.gz /var/cache/elite-local/elite-local.db
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
    # E63 — o hook de resume agora é DO PACOTE (a rede de sistema que o
    # rig recebe pelo canal): sai do airootfs antes do pacstrap (a MESMA
    # lei E57 de um dono por caminho — o pacstrap recusa não-dono).
    # E69 — a cura do RETORNO dos dispositivos USB viaja NO PACOTE
    # (o mesmo veículo de adoção: o rig instalado só a recebe por ele).
    rm -f "${PD_E57%profiledef.sh}airootfs/usr/lib/systemd/system-sleep/elite-resume-display"
    rm -f "${PD_E57%profiledef.sh}airootfs/usr/lib/systemd/system-sleep/elite-resume-usb"
    [[ ! -e "${PD_E57%profiledef.sh}airootfs/usr/lib/systemd/system-sleep/elite-resume-display" ]] || { echo "ELITE-FAIL: hook de resume sobreviveu à remoção E57/E63 — o pacote é o ÚNICO dono (nunca dois)" >&2; exit 1; }
    [[ ! -e "${PD_E57%profiledef.sh}airootfs/usr/lib/systemd/system-sleep/elite-resume-usb" ]] || { echo "ELITE-FAIL: hook de USB sobreviveu à remoção E57/E69 — o pacote é o ÚNICO dono (nunca dois)" >&2; exit 1; }
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
