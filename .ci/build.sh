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
    for m in https://cdn77.cachyos.org/repo/x86_64/cachyos \
             https://us.cachyos.org/repo/x86_64/cachyos; do
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
        say "Preflight round $round: -Syw falhou — mapeando URLs quebradas (sonda HEAD paralela)"
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
            code=$(curl -s -o /dev/null -w '%{http_code}' -m 25 --head "$u2" 2>/dev/null) || code=000
            [[ "$code" == "200" ]] && { say "  ok no gêmeo us (cdn77 desinc só) — $u2"; continue; }
            fn=${u##*/}
            base=$(printf '%s' "$fn" | sed -E 's/-(any|x86_64(_v3)?)\.pkg\.tar\.zst$//' | rev | cut -d- -f3- | rev)
            fu=$(pacman --config /tmp/elite-arch-only.conf -b "$pfdb" -Sp --print-format '%l' --noconfirm "$base" 2>/dev/null \
                 | grep -oE '^https?://[^ ]+\.pkg\.tar\.zst$' | head -1 || true)
            if [[ -n "$fu" ]]; then
                say "  $fn quebrado nos 2 mirrors → baseline Arch injetado no [elite-local]"
                if curl -fsSL -o "/var/cache/elite-local/${fu##*/}" "$fu"; then injected=1; fi
            else
                say "  $fn quebrado e SEM baseline Arch — próximo round decide"
            fi
        done
        if (( injected )); then
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
