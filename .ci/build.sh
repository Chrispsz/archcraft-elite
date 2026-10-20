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
    e2fsprogs squashfs-tools openssl arch-install-scripts

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
rm -rf /tmp/elite-src && mkdir -p /tmp/elite-src/python-pywal /tmp/elite-src/qt5-virtualkeyboard

cd /tmp/elite-src/python-pywal
curl -fsSL -o pywal-master.tar.gz "https://codeload.github.com/dylanaraps/pywal/tar.gz/refs/heads/master"
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
    cd pywal-master
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

# makepkg se recusa a rodar como root — usuário builder descartável
useradd -m builder 2>/dev/null || true
chown -R builder /tmp/elite-src
for pkgdir in python-pywal qt5-virtualkeyboard; do
    (cd "/tmp/elite-src/$pkgdir" && runuser -l builder -c "cd /tmp/elite-src/$pkgdir && makepkg -f --noconfirm") \
        || { echo "FALHA ao construir $pkgdir"; exit 1; }
    cp "/tmp/elite-src/$pkgdir/"*.pkg.tar.zst /var/cache/elite-local/
done
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
# Preflight auto-curativo: os mirrors rolling do CachyOS vivem em janelas
# de dessincronização db↔arquivo (migração de toolchain: gcc/glibc/qt5/
# libyuv 404 por horas). Antes de CADA tentativa:
#   1. baixa TODOS os pacotes da transação p/ o cache (-Syw — mesma
#      resolução que o pacstrap usará; nada é instalado no host)
#   2. o XferCommand de preflight REGISTRA cada URL que falhar
#   3. arquivo 404 no cdn77 E no gêmeo us → injeta a versão BASELINE do
#      Arch no repo [elite-local] (primeiro repo do conf) e refaz o round
# Com o cache completo, o pacstrap do mkarchcraftiso não baixa nada.
# ─────────────────────────────────────────────────────────────────────
preflight() {
    local pc=/work/elite-build/profile/pacman.conf
    local plconf=/tmp/elite-preflight.conf
    cd /work/elite-build/profile

    # conf de preflight: profile + XferCommand que loga as falhas
    sed -e 's@^XferCommand = .*@XferCommand = /usr/bin/curl -L -C - -f -o %o %u --retry 2 --retry-delay 3 --retry-all-errors || echo "ELITE-FAIL %u" >> /tmp/elite-404s.txt@' \
        "$pc" > "$plconf"

    # conf Arch-only p/ resolver os fallbacks baseline
    grep -vE '^\[cachyos|\.cachyos\.org|^\[elite-local\]|file:///var/cache/elite-local' \
        "$pc" > /tmp/elite-arch-only.conf

    mapfile -t PL < <(grep -vE '^#|^ *$' packages.x86_64 | sed 's|^archcraft/||')
    say "Preflight: ${#PL[@]} alvos — baixando tudo p/ o cache (round 1)"

    local round u u2 c2 fn base fu
    for round in 1 2 3 4 5; do
        rm -f /tmp/elite-404s.txt
        if pacman --config "$plconf" -Syw --needed --noconfirm "${PL[@]}" >/tmp/elite-pf.log 2>&1; then
            say "Preflight round $round: cache completo — pacstrap não vai baixar pacote da rede"
            return 0
        fi
        say "Preflight round $round falhou — tail do pacman:"
        tail -5 /tmp/elite-pf.log || true
        mapfile -t BAD < <(grep '^ELITE-FAIL ' /tmp/elite-404s.txt 2>/dev/null | awk '{print $2}' | grep '\.pkg\.tar\.zst$' | sort -u || true)
        if (( ${#BAD[@]} == 0 )); then
            say "Preflight: falha sem 404 de pacote mapeado — re-sincronizando e repetindo"
            continue
        fi
        local injected=0
        for u in "${BAD[@]}"; do
            # gêmeo cdn77↔us: só é problema se faltar em AMBOS
            u2=$u
            [[ "$u" == *cdn77.cachyos.org* ]] && u2=${u/cdn77.cachyos.org/us.cachyos.org}
            c2=$(curl -s -o /dev/null -w '%{http_code}' -m 25 --head "$u2" 2>/dev/null) || c2=000
            [[ "$c2" == "200" ]] && continue
            fn=${u##*/}
            base=$(printf '%s' "$fn" | sed -E 's/-(any|x86_64(_v3)?)\.pkg\.tar\.zst$//' | rev | cut -d- -f3- | rev)
            fu=$(pacman --config /tmp/elite-arch-only.conf -Sp --print-uris --noconfirm "$base" 2>/dev/null \
                 | grep -oE 'https?://[^ ]+' | head -1 || true)
            if [[ -n "$fu" ]]; then
                say "Preflight: $fn quebrado nos 2 mirrors → baseline Arch injetado no [elite-local]"
                curl -fsSL -o "/var/cache/elite-local/${fu##*/}" "$fu" || true
                injected=1
            else
                say "Preflight: $fn quebrado e sem fallback Arch — próxima rodada decide"
            fi
        done
        if (( injected )); then
            repo-add --quiet /var/cache/elite-local/elite-local.db.tar.gz /var/cache/elite-local/*.pkg.tar.zst
            cp /var/cache/elite-local/* /work/elite-build/profile/airootfs/var/cache/elite-local/
            say "Preflight: repo [elite-local] atualizado com baseline(s)"
        fi
    done
    say "Preflight: 5 rodadas sem fechar o cache — seguindo (retry externo cobre)"
    return 0
}

say "Construindo ISO (mkarchcraftiso — fork oficial do Archcraft)"
mkdir -p /mnt/iso-work /work/out
cd elite-build/profile
for attempt in 1 2 3; do
    preflight
    rm -rf /mnt/iso-work
    if ./mkarchcraftiso -v -w /mnt/iso-work -o /work/out . ; then
        break
    fi
    if [ "$attempt" = "3" ]; then
        echo "FALHOU após 3 tentativas"
        exit 1
    fi
    say "Tentativa $attempt falhou — aguardando 90s (mirrors sincronizam) e repetindo"
    sleep 90
done

say "Checksums + relatório de tamanho"
cd /work/out
sha256sum -- * > sha256sums.txt
cat sha256sums.txt
ls -lh --si
