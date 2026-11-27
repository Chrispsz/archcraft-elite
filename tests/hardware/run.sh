#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════
# Archcraft ELITE · tests/hardware/run.sh — O SIMULADOR DOS 6 PERFIS
# ═══════════════════════════════════════════════════════════════════════
# E106/5c — A MATRIZ DE HARDWARE COMO CONTRATO VIVO. A casa promete
# tuning CONDICIONADO ao hardware (o deep do S3 só quando o /sys/power/
# mem_sleep lista, o snapper só no btrfs, o sensor só quando o chip
# PROVA hwmon, o liquidctl fechado quando o pacote não existe) — a
# promessa agora é BYTE A BYTE: cada perfil real da matriz roda os
# scripts DA CASA (elite-post-upgrade, elite-acpi-wakeup, craft-display)
# num SANDBOX DE ROOT FALSO e os arquivos resultantes são comparados
# com os esperados POR PERFIL (heredocs com o conteúdo exato).
#
# O SANDBOX (unshare -rm + bind mounts — ZERO mudança de produção):
#   · /etc   ← cópia do /etc real + seeds do perfil (grub, sensors,
#              coolercontrol) — a dose escreve LÁ, o sistema fica;
#   · /sys   ← o /sys FALSO do perfil (mem_sleep, hwmon, module/);
#   · /home  ← vazio (nenhum usuário vivo — as asas de /home/* ficam);
#   · /run   ← o flock da dose e os stamps da tela;
#   · /var/log ← o papel da dose (elite-post-upgrade.log);
#   · PATH   ← stubs de findmnt/systemctl/pacman/modprobe/snapper/
#              grub-mkconfig/lspci/flatpak/loginctl/mkinitcpio — cada
#              stub registra a chamada (a prova dos enables) e simula
#              o hardware (modprobe que binda cria hwmon novo, quem
#              não tem o chip FALHA — o driver ocioso desce).
# O mold é o das seams da casa: ELITE_ACPI_WAKEUP (elite-acpi-wakeup) e
# ELITE_RANDR (craft-display) — nenhum caminho de produção mudou.
#
# PROTOCOLO DE SAÍDA (a fase 55 converte em t_ok/t_fail da porteira):
#   OK\t<descrição>            — a asserção provou
#   FAIL\t<descrição>\t<réu>   — a asserção caiu (réu nomeado)
#   INFO\t<texto>              — linha informativa (ecoada, não conta)
# exit 0 = sem falhas · 1 = com falhas · 3 = sandbox impossível (pulo)
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
REPO="$(pwd)"

HW="$(mktemp -d /tmp/elite-hw-XXXXXX)"
KEEP="${ELITE_TESTS_KEEP:-0}"
(( KEEP )) || trap 'rm -rf "$HW" 2>/dev/null || true' EXIT
mkdir -p "$HW"

OK=0; FAIL=0
emit_ok()  { OK=$((OK + 1)); printf 'OK\t%s\n' "$1"; }
emit_fail(){ FAIL=$((FAIL + 1)); printf 'FAIL\t%s\t%s\n' "$1" "${2:-?}"; }
emit_info(){ printf 'INFO\t%s\n' "$1"; }

# a comparação BYTE A BYTE (o arquivo do sandbox contra o heredoc esperado)
cmp_bytes() { # cmp_bytes <desc> <arquivo> <arquivo-esperado>
    if [ ! -f "$2" ]; then emit_fail "$1" "ausente: $2"; return; fi
    if cmp -s "$2" "$3"; then emit_ok "$1"; else
        emit_fail "$1" "$(diff "$3" "$2" 2>/dev/null | head -4 | tr '\n' ' ')"
    fi
}
# a contagem EXATA de ocorrências (enables idempotentes, 1× dos tokens)
count_is() { # count_is <desc> <arquivo> <agulha> <n>
    local n
    n="$(grep -cF -- "$3" "$2" 2>/dev/null || true)"
    [ "${n:-0}" = "$4" ] && emit_ok "$1" || emit_fail "$1" "esperado $4×, veio ${n:-0}× de '$3' em $2"
}

# ── o sandbox de root falso (unshare -rm: root DENTRO, nada fora) ────────
sandbox_possivel() {
    unshare -rm --propagation private true 2>/dev/null
}

# monta o /etc FALSO do perfil: cópia do real + os seeds do perfil
seed_etc() { # seed_etc <root> — cópia do /etc REAL + os seeds do perfil
    local r="$1"
    mkdir -p "$r/etc"
    # cp -r (NUNCA -a): a cópia nasce do DONO do sandbox — o -a
    # preservaria root:root e o root FALSO do userns não escreveria
    # (o arquivo apareceria nobody e a dose morreria em silêncio)
    cp -r /etc/. "$r/etc/" 2>/dev/null || true
}

# ── OS STUBS (o hardware falso + o gravador de chamadas) ────────────────
mk_stubs() { # mk_stubs <root> <fstype> <hwmod_ok> <lspci>
    local r="$1" d="$1/stubs"
    mkdir -p "$d"
    printf '%s\n' "$2" > "$d/.fstype"
    printf '%s\n' "$3" > "$d/.hwmod_ok"
    printf '%s\n' "$4" > "$d/.lspci"

    cat > "$d/findmnt" <<'EOF'
#!/bin/sh
[ "$1" = "-n" ] && { cat "$(dirname "$0")/.fstype"; exit 0; }
exit 0
EOF
    # systemctl: registra TUDO; enable/disable/mask respondem 0 (o systemd
    # real é idempotente — o stub é o mesmo contrato)
    cat > "$d/systemctl" <<'EOF'
#!/bin/sh
printf '%s\n' "systemctl $*" >>"$(dirname "$0")/systemctl.log"
exit 0
EOF
    # pacman: -Q/-Qq/-Qi = NADA instalado (o liquidctl ausente fecha a
    # integração do CoolerControl; o -Qq do fã NoDisplay também pula)
    cat > "$d/pacman" <<'EOF'
#!/bin/sh
printf '%s\n' "pacman $*" >>"$(dirname "$0")/pacman.log"
case "$1" in -Q|-Qq|-Qi) exit 1 ;; esac
exit 0
EOF
    # modprobe: quem ESTÁ na lista do perfil BINDA (hwmon novo nasce no
    # /sys falso — a sonda da dose vê a mudança e mantém); quem não está
    # FALHA (o chip não é desta placa — o driver ocioso desce na hora)
    cat > "$d/modprobe" <<'EOF'
#!/bin/sh
D="$(dirname "$0")"; R="$ELITE_SYSROOT"
if [ "$1" = "-r" ]; then
    printf '%s\n' "modprobe -r $2" >>"$D/modprobe.log"
    rm -rf "$R/sys/module/$2" "$R/sys/class/hwmon/hwmon_$2" 2>/dev/null
    exit 0
fi
if grep -qw "$1" "$D/.hwmod_ok" 2>/dev/null; then
    mkdir -p "$R/sys/module/$1" "$R/sys/class/hwmon/hwmon_$1"
    printf '%s\n' "modprobe $1 ok (hwmon novo)" >>"$D/modprobe.log"
    exit 0
fi
printf '%s\n' "modprobe $1 fail (sem chip)" >>"$D/modprobe.log"
exit 1
EOF
    # snapper: list-configs vazio (o config do root nasce); create-config
    # CRIA o /etc/snapper/configs/root (o guard da 2ª corrida é REAL)
    cat > "$d/snapper" <<'EOF'
#!/bin/sh
D="$(dirname "$0")"
printf '%s\n' "snapper $*" >>"$D/snapper.log"
case "$*" in
    *create-config*)
        mkdir -p "$ELITE_SYSROOT/etc/snapper/configs"
        : >"$ELITE_SYSROOT/etc/snapper/configs/root"
        exit 0 ;;
esac
exit 0
EOF
    cat > "$d/grub-mkconfig" <<'EOF'
#!/bin/sh
printf '%s\n' "grub-mkconfig $*" >>"$(dirname "$0")/grub-mkconfig.log"
exit 0
EOF
    cat > "$d/lspci" <<'EOF'
#!/bin/sh
cat "$(dirname "$0")/.lspci"
exit 0
EOF
    cat > "$d/flatpak" <<'EOF'
#!/bin/sh
printf '%s\n' "flatpak $*" >>"$(dirname "$0")/flatpak.log"
case "$1" in info) exit 1 ;; esac
exit 0
EOF
    # loginctl: NENHUM usuário vivo no sandbox (as asas de sessão ficam)
    cat > "$d/loginctl" <<'EOF'
#!/bin/sh
printf '%s\n' "loginctl $*" >>"$(dirname "$0")/loginctl.log"
exit 0
EOF
    cat > "$d/mkinitcpio" <<'EOF'
#!/bin/sh
printf '%s\n' "mkinitcpio $*" >>"$(dirname "$0")/mkinitcpio.log"
exit 0
EOF
    chmod 755 "$d"/findmnt "$d"/systemctl "$d"/pacman "$d"/modprobe \
        "$d"/snapper "$d"/grub-mkconfig "$d"/lspci "$d"/flatpak \
        "$d"/loginctl "$d"/mkinitcpio
}

# ── a DOSE no sandbox: elite-post-upgrade com o /etc e o /sys do perfil ──
# (o bin da casa viaja CÓPIA dentro do sandbox — o bind do /home do rig
#  some do namespace; a cópia no /tmp do sandbox é o caminho vivo)
run_dose() { # run_dose <root>
    local r="$1"
    cp "$REPO/elite/airootfs/usr/local/bin/elite-post-upgrade" "$r/elite-post-upgrade"
    chmod 755 "$r/elite-post-upgrade"
    unshare -rm --propagation private env -i \
        PATH="$r/stubs:/usr/bin:/bin" \
        ELITE_SYSROOT="$r" \
        bash -c '
            r="$1"
            mount --bind "$r/etc"   /etc     2>/dev/null || true
            mount --bind "$r/sys"   /sys     2>/dev/null || true
            mount --bind "$r/home"  /home    2>/dev/null || true
            mount --bind "$r/run"   /run      2>/dev/null || true
            mount --bind "$r/varlog" /var/log 2>/dev/null || true
            sh "$r/elite-post-upgrade" >>"$r/dose.log" 2>&1
        ' _ "$r" 2>>"$r/ns.err"
}

# ── O SNAPSHOT das chaves (a 2ª corrida tem que ser byte-idêntica) ──────
chaves_sha() { # chaves_sha <root>
    local r="$1"
    sha256sum "$r/etc/default/grub" "$r/etc/modules-load.d/elite-sensors.conf" \
              "$r/etc/coolercontrol/config.toml" 2>/dev/null | awk '{print $1}' | sort
}

# ═════════════════════════════════════════════════════════════════════
# A MATRIZ — os 6 perfis reais (cada um sela o sandbox do seu hardware)
# ═════════════════════════════════════════════════════════════════════
# args: <nº> <nome> <fstype> <hwmod_ok> <lspci> <mem_sleep> <deep:0|1>
rodar_perfil() {
    local num="$1" nome="$2" fstype="$3" hwok="$4" lspci="$5" memsleep="$6" deep="$7"
    local r="$HW/perfil$num"
    emit_info "── perfil $num · $nome ──"

    # ── o mundo do perfil ──
    mkdir -p "$r"/sys/power "$r"/sys/class/hwmon "$r"/sys/module \
             "$r"/home "$r"/run "$r"/varlog
    seed_etc "$r"
    mk_stubs "$r" "$fstype" "$hwok" "$lspci"
    printf '%s\n' "$memsleep" > "$r/sys/power/mem_sleep"
    # o conf de FÁBRICA dos sensores (o molde da ISO — a dose sonda por cima)
    cp "$REPO/elite/airootfs/etc/modules-load.d/elite-sensors.conf" \
       "$r/etc/modules-load.d/elite-sensors.conf" 2>/dev/null || {
        mkdir -p "$r/etc/modules-load.d"
        cp "$REPO/elite/airootfs/etc/modules-load.d/elite-sensors.conf" \
           "$r/etc/modules-load.d/elite-sensors.conf"
    }
    # o GRUB do rig (sem os tokens da casa — a dose soma)
    cat > "$r/etc/default/grub" <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX="loglevel=3"
EOF
    # os quartos que TODO rig Arch tem (o sandbox da DEVEL pode não ter —
    # a dose conta com eles: modprobe.d, coolercontrol, snapper, sddm)
    mkdir -p "$r/etc/modprobe.d" "$r/etc/coolercontrol" "$r/etc/snapper" "$r/etc/sddm.conf.d"

    # ── os seeds ESPECIAIS por perfil ──
    case "$num" in
        4)  # o CoolerControl do dono já tem papel (a chave entra DENTRO
            # da seção [settings] — nunca duplica, nunca sobrescreve)
            mkdir -p "$r/etc/coolercontrol"
            cat > "$r/etc/coolercontrol/config.toml" <<'EOF'
# o papel do dono — o CoolerControl da casa
[settings]
frontend = "dark"
EOF
            ;;
    esac

    # ── a DOSE (2×: a idempotência é parte do contrato) ──
    run_dose "$r"
    local sha1_tudo gm1 mk1
    sha1_tudo="$(chaves_sha "$r")"
    # o retrato da 1ª corrida (a 2ª não pode somar NENHUMA reconstrução)
    gm1="$(grep -c . "$r/stubs/grub-mkconfig.log" 2>/dev/null || true)"
    mk1="$(grep -c . "$r/stubs/mkinitcpio.log" 2>/dev/null || true)"
    run_dose "$r"

    # ── AS PROVAS (byte a byte contra o esperado DO PERFIL) ──
    local esp="$HW/esp-$num"
    mkdir -p "$esp"

    # 1. o GRUB do perfil: os tokens da casa na ordem da dose (zswap,
    #    madvise, [deep do hardware], mitigations, nowatchdog)
    if [ "$deep" = 1 ]; then
        cat > "$esp/grub" <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash zswap.enabled=0 transparent_hugepage=madvise mem_sleep_default=deep mitigations=off nowatchdog"
GRUB_CMDLINE_LINUX="loglevel=3"
EOF
    else
        cat > "$esp/grub" <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash zswap.enabled=0 transparent_hugepage=madvise mitigations=off nowatchdog"
GRUB_CMDLINE_LINUX="loglevel=3"
EOF
    fi
    cmp_bytes "P$num GRUB: o cmdline da casa é o esperado do perfil (byte a byte)" \
        "$r/etc/default/grub" "$esp/grub"
    count_is "P$num GRUB: mem_sleep_default=deep $([ "$deep" = 1 ] && echo 'ENTRA 1× (o hardware lista deep)' || echo 'NÃO entra (s2idle de série)')" \
        "$r/etc/default/grub" 'mem_sleep_default=deep' "$deep"

    # 2. a idempotência: a 2ª dose não mudou NENHUMA chave (byte-idêntica)
    if [ "$(chaves_sha "$r")" = "$sha1_tudo" ]; then
        emit_ok "P$num idempotência: a 2ª dose é byte-idêntica (grub+sensors+coolercontrol)"
    else
        emit_fail "P$num idempotência: a 2ª dose é byte-idêntica" "as chaves mudaram na 2ª corrida"
    fi
    # as DUAS seções que mudaram (tokens sysctl+madvise[+deep] e
    # mitigations/nowatchdog) reconstruíram UMA vez cada na 1ª dose
    if [ "${gm1:-0}" = 2 ]; then
        emit_ok "P$num GRUB: grub-mkconfig UMA vez por seção que mudou (2 seções = 2 na 1ª dose)"
    else
        emit_fail "P$num GRUB: grub-mkconfig UMA vez por seção que mudou" "veio ${gm1:-0}× na 1ª dose (esperado 2)"
    fi
    count_is "P$num GRUB: a 2ª dose NÃO reconstrói (o rebuild fantasma morre)" \
        "$r/stubs/grub-mkconfig.log" 'grub-mkconfig' "${gm1:-0}"

    # 3. os sensores do perfil (a sonda prova contra o hwmon FALSO)
    cat > "$esp/sensors" <<EOF
# ── ELITE (E106/5b): os chips que ESTA máquina provou no
# /sys/class/hwmon (a sonda da dose; os 4 candidatos da
# fábrica: nct6775/it87/k10temp/coretemp — quem sobe sem
# hwmon novo desce na hora).
${hwok:+$hwok}
EOF
    if [ -n "$hwok" ]; then
        cmp_bytes "P$num sensores: elite-sensors.conf = [$hwok] (o chip que a placa TEM)" \
            "$r/etc/modules-load.d/elite-sensors.conf" "$esp/sensors"
    else
        cmp_bytes "P$num sensores: elite-sensors.conf de FÁBRICA intacto (nenhum módulo provou)" \
            "$r/etc/modules-load.d/elite-sensors.conf" \
            "$REPO/elite/airootfs/etc/modules-load.d/elite-sensors.conf"
    fi

    # 4. o CoolerControl sem o líquido que não existe (liquidctl ausente)
    case "$num" in
        4) cat > "$esp/cc" <<'EOF'
# o papel do dono — o CoolerControl da casa
[settings]
liquidctl_integration = false
frontend = "dark"
EOF
           ;;
        *) cat > "$esp/cc" <<'EOF'
# ELITE (E106/5b): sem liquidctl no sistema — a integração fecha
[settings]
liquidctl_integration = false
EOF
           ;;
    esac
    cmp_bytes "P$num coolercontrol: config.toml com liquidctl_integration = false (liquidctl ausente)" \
        "$r/etc/coolercontrol/config.toml" "$esp/cc"

    # 5. o snapshot: btrfs HABILITA, ext4 COLHE (o findmnt do stub decide)
    local slog="$r/stubs/systemctl.log"
    if [ "$fstype" = btrfs ]; then
        count_is "P$num snapshot: grub-btrfsd enable idempotente (2 doses = 2 enables, sem erro)" \
            "$slog" 'enable --now grub-btrfsd.service' 2
        count_is "P$num snapshot: snapper-cleanup.timer enable idempotente" \
            "$slog" 'enable --now snapper-cleanup.timer' 2
        count_is "P$num snapshot: o config do root nasce UMA vez (o guard do arquivo)" \
            "$r/stubs/snapper.log" 'create-config' 1
    else
        count_is "P$num snapshot: ext4 COLHE os daemons de btrfs (grub-btrfsd desce)" \
            "$slog" 'disable --now grub-btrfsd.service' 2
        count_is "P$num snapshot: NENHUM enable de snapshot no filesystem errado" \
            "$slog" 'enable --now grub-btrfsd.service' 0
    fi

    # 6. a GPU: o conf amdgpu é da família AMD (o lspci do stub decide)
    case "$lspci" in
        *AMD*|*ATI*)
            cat > "$esp/amdgpu" <<'EOF'
# ELITE: AMD - destrava undervolt/OC p/ LACT
options amdgpu ppfeaturemask=0xffffffff
EOF
            cmp_bytes "P$num AMD: 00-elite-amdgpu.conf (ppfeaturemask — o LACT destravado)" \
                "$r/etc/modprobe.d/00-elite-amdgpu.conf" "$esp/amdgpu"
            if [ "${mk1:-0}" = 1 ] && [ "$(grep -c . "$r/stubs/mkinitcpio.log" 2>/dev/null || true)" = 1 ]; then
                emit_ok "P$num AMD: o initramfs reconstruído UMA vez (nasceu o conf; a 2ª dose não re-tenta)"
            else
                emit_fail "P$num AMD: o initramfs reconstruído UMA vez" "1ª dose=${mk1:-0}× total=$(grep -c . "$r/stubs/mkinitcpio.log" 2>/dev/null || echo 0)×"
            fi
            ;;
        *)
            [ ! -e "$r/etc/modprobe.d/00-elite-amdgpu.conf" ] \
                && emit_ok "P$num não-AMD: o conf amdgpu NÃO nasce (o rig não é da família)" \
                || emit_fail "P$num não-AMD: o conf amdgpu NÃO nasce" "00-elite-amdgpu.conf presente sem GPU AMD"
            count_is "P$num não-AMD: initramfs NÃO reconstruído (nada nasceu)" \
                "$r/stubs/mkinitcpio.log" 'mkinitcpio' 0
            ;;
    esac
}

# ═════════════════════════════════════════════════════════════════════
# A TELA QUE VOLTA — craft-display recover com o stub do wlr-randr
# (a seam ELITE_RANDR da casa; o modo vem do displays.conf DO PERFIL)
# ═════════════════════════════════════════════════════════════════════
run_display() { # run_display <num> <nome> <displays.conf> <estado wlr-randr> <log esperado>
    local num="$1" nome="$2" conf="$3" estado="$4" esperado="$5"
    local r="$HW/perfil$num"
    emit_info "── perfil $num · $nome — a tela que volta ──"
    local h="$r/home/dono"
    mkdir -p "$h/.config/elite" "$r/run/user/1000" "$r/stubs"

    printf '%s\n' "$conf" > "$h/.config/elite/displays.conf"
    printf '%s\n' "$estado" > "$r/stubs/randr-estado"
    : > "$r/stubs/randr.log"

    # o stub wlr-randr: sem args = o estado vivo do perfil; --help fala
    # a bandeira da casa; com --output REGISTRA a chamada (a prova)
    cat > "$r/stubs/wlr-randr" <<'EOF'
#!/bin/sh
D="$(dirname "$0")"
case "$*" in
    "") cat "$D/randr-estado"; exit 0 ;;
    --help) printf '%s\n' "usage: wlr-randr [--output X --mode WxH@R --scale-exact S ...]"; exit 0 ;;
    *)  printf '%s\n' "$*" >>"$D/randr.log"; exit 0 ;;
esac
EOF
    chmod 755 "$r/stubs/wlr-randr"

    HOME="$h" XDG_RUNTIME_DIR="$r/run/user/1000" \
        ELITE_RANDR="$r/stubs/wlr-randr" \
        PATH="$r/stubs:/usr/bin:/bin" \
        sh "$REPO/elite/airootfs/usr/local/bin/craft-display" recover \
        >"$r/display.out" 2>&1

    local esp="$HW/esp-$num"
    printf '%s\n' "$esperado" > "$esp/randr"
    cmp_bytes "P$num tela: o recover cicla off→on COM o modo persistido POR saída (byte a byte)" \
        "$r/stubs/randr.log" "$esp/randr"
    cmp_bytes "P$num tela: o displays.conf do dono é INTOCADO (o recover só LÊ)" \
        "$h/.config/elite/displays.conf" <(printf '%s\n' "$conf")
}

# ═════════════════════════════════════════════════════════════════════
# O SONO QUE ACORDA — elite-acpi-wakeup na tabela FALSA (seam da casa)
# ═════════════════════════════════════════════════════════════════════
run_wakeup() { # run_wakeup <num>
    local num="$1"
    local r="$HW/perfil$num"
    emit_info "── perfil $num · o rig do dono — o sono que não acorda sozinho ──"
    local h="$r/home/dono"
    mkdir -p "$h/.cache/elite"

    # a tabela ACPI do rig (1.0-107: a família INTEIRA por padrão — 9
    # gatilhos *enabled, incluindo os padrões de era GP30/X161/X1_1 que a
    # fila FIXA de 6 nomes da 1.0-106 nunca via + a mão do dono + o botão)
    # 1.0-107.2 — a prova do CINTO UNIVERSAL: SLPB e PBTN chegam
    # *disabled de fábrica (o firmware dormindo o botão de sleep e a
    # grafia alternativa do power — a mesa da diretriz do hardware
    # moderno) e LID *enabled (a tampa do notebook já armada)
    cat > "$r/wakeup" <<'EOF'
Device  S-state   Status          Sysfs node
GPP0      S4      *enabled  pci:0000:00:01.1
GPP8      S4      *enabled  pci:0000:00:01.2
GP30      S4      *enabled  pci:0000:00:01.3
XHC0      S4      *enabled  pci:0000:00:12.0
XHC1      S4      *enabled  pci:0000:00:12.1
XHCI      S4      *enabled  pci:0000:00:12.2
PTXH      S4      *enabled  pci:0000:00:12.3
X161      S4      *enabled  pci:0000:00:13.1
X1_1      S4      *enabled  pci:0000:00:13.2
PS2K      S3      *enabled  pnp:00:04
PWRB      S4      *enabled  button
SLPB      S4      *disabled  button
PBTN      S4      *disabled  button
LID       S3      *enabled  button
EOF
    XDG_CACHE_HOME="$h/.cache" ELITE_ACPI_WAKEUP="$r/wakeup" \
        sh "$REPO/elite/airootfs/usr/local/bin/elite-acpi-wakeup"

    # a 1ª passada: os nomes no papel da tabela (o toggle do kernel — a
    # tabela nova tem 16 linhas, o apêndice do script mora do 16 em diante)
    local n
    n="$(tail -n +16 "$r/wakeup" | grep -cE '^(GPP0|GPP8|GP30|XHC0|XHC1|XHCI|PTXH|X161|X1_1|SLPB|PBTN)$' || true)"
    [ "$n" = 11 ] \
        && emit_ok "P$num wakeup: a 1ª passada escreve os 11 toggles (9 da família espúria + o cinto armando SLPB/PBTN)" \
        || emit_fail "P$num wakeup: a 1ª passada escreve os 11 toggles" "foram $n/11 escritas na tabela"

    # o kernel da casa falsa aplica o toggle (a escrita INVERTE o estado —
    # os 9 espúrios *enabled→*disabled; o cinto universal *disabled→*enabled)
    local d
    for d in GPP0 GPP8 GP30 XHC0 XHC1 XHCI PTXH X161 X1_1; do
        sed -i "/^$d / s/\*enabled/*disabled/" "$r/wakeup"
    done
    for d in SLPB PBTN; do
        sed -i "/^$d / s/\*disabled/*enabled/" "$r/wakeup"
    done
    sed -i '/^\(GPP0\|GPP8\|GP30\|XHC0\|XHC1\|XHCI\|PTXH\|X161\|X1_1\|SLPB\|PBTN\)$/d' "$r/wakeup"

    cat > "$HW/esp-$num/wakeup" <<'EOF'
Device  S-state   Status          Sysfs node
GPP0      S4      *disabled  pci:0000:00:01.1
GPP8      S4      *disabled  pci:0000:00:01.2
GP30      S4      *disabled  pci:0000:00:01.3
XHC0      S4      *disabled  pci:0000:00:12.0
XHC1      S4      *disabled  pci:0000:00:12.1
XHCI      S4      *disabled  pci:0000:00:12.2
PTXH      S4      *disabled  pci:0000:00:12.3
X161      S4      *disabled  pci:0000:00:13.1
X1_1      S4      *disabled  pci:0000:00:13.2
PS2K      S3      *enabled  pnp:00:04
PWRB      S4      *enabled  button
SLPB      S4      *enabled  button
PBTN      S4      *enabled  button
LID       S3      *enabled  button
EOF
    cmp_bytes "P$num wakeup: os 9 espúrios da família *disabled na tabela (desarmados no boot)" \
        "$r/wakeup" "$HW/esp-$num/wakeup"
    grep -Eq '^PS2K +S3 +\*enabled' "$r/wakeup" \
        && emit_ok "P$num wakeup: a mão do dono PS2K segue *enabled (o allowlist da 1.0-107)" \
        || emit_fail "P$num wakeup: a mão do dono PS2K segue *enabled" "a linha PS2K mudou na tabela"
    # 1.0-107.2 — o CINTO UNIVERSAL: SLPB e PBTN dormindo de fábrica são
    # REARMADOS pela 1ª passada (o botão físico acorda em QUALQUER placa)
    grep -Eq '^SLPB +S4 +\*enabled' "$r/wakeup" \
        && emit_ok "P$num wakeup: o cinto universal arma o SLPB (o botão de sleep dormindo de fábrica)" \
        || emit_fail "P$num wakeup: o cinto arma o SLPB" "a linha SLPB não está *enabled"
    grep -Eq '^PBTN +S4 +\*enabled' "$r/wakeup" \
        && emit_ok "P$num wakeup: o cinto universal arma o PBTN (a grafia alternativa do power)" \
        || emit_fail "P$num wakeup: o cinto arma o PBTN" "a linha PBTN não está *enabled"
    grep -Eq '^LID +S3 +\*enabled' "$r/wakeup" \
        && emit_ok "P$num wakeup: a tampa LID segue *enabled (o allowlist não toca o que já está armado)" \
        || emit_fail "P$num wakeup: a tampa LID segue *enabled" "a linha LID mudou na tabela"

    # a 2ª passada: NADA no papel (idempotente — o grep antes de escrever)
    local sha_antes sha_depois
    sha_antes="$(sha256sum "$r/wakeup" | awk '{print $1}')"
    XDG_CACHE_HOME="$h/.cache" ELITE_ACPI_WAKEUP="$r/wakeup" \
        sh "$REPO/elite/airootfs/usr/local/bin/elite-acpi-wakeup"
    sha_depois="$(sha256sum "$r/wakeup" | awk '{print $1}')"
    [ "$sha_antes" = "$sha_depois" ] \
        && emit_ok "P$num wakeup: a 2ª passada é silêncio (byte-idêntica — rearmar o dormendo morre)" \
        || emit_fail "P$num wakeup: a 2ª passada é silêncio" "a tabela mudou na 2ª corrida"
    count_is "P$num wakeup: o papel da casa conta os 9 desarmados" \
        "$h/.cache/elite/acpi-wakeup.log" 'desarmado (gatilho espúrio' 9
    count_is "P$num wakeup: o papel conta os 2 do cinto universal rearmados (SLPB/PBTN)" \
        "$h/.cache/elite/acpi-wakeup.log" '→ rearmado (o allowlist' 2
}

# ═════════════════════════════════════════════════════════════════════
# A CAMINHADA — os 6 perfis da matriz real
# ═════════════════════════════════════════════════════════════════════
main() {
    if ! sandbox_possivel; then
        printf 'SKIP\tmatriz dos 6 perfis (sandbox --root)\tunshare/mount indisponível no ambiente (userns bloqueado — pulo honesto L6)\n'
        exit 3
    fi

    # ── PERFIL 1 · ENTRADA 1 — Intel iGPU, ext4, s2idle de série:
    #    sem deep no mem_sleep, sem snapshot no filesystem errado,
    #    nenhum chip Super I/O provado
    rodar_perfil 1 "Entrada 1 · Intel iGPU + ext4 (s2idle)" ext4 "" \
        '00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 630 (rev 03)' \
        '[s2idle]' 0

    # ── PERFIL 2 · ENTRADA 2 — AMD APU (k10temp), btrfs: snapper ligado,
    #    o termômetro da CPU provado
    rodar_perfil 2 "Entrada 2 · AMD APU k10temp + btrfs" btrfs k10temp \
        '00:08.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Raphael (rev c8)' \
        '[s2idle]' 0

    # ── PERFIL 3 · INTERMEDIÁRIO 1 — O RIG DO DONO: Ryzen 5600 + ASUS
    #    (nct6775), RX 7600 (amdgpu), DP-1 1920x1080@119.88, btrfs, deep
    rodar_perfil 3 "Intermediário 1 · O RIG DO DONO (nct6775 + RX 7600 + DP-1, btrfs deep)" btrfs nct6775 \
        '00:08.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 32 [Radeon RX 7600]' \
        's2idle [deep]' 1

    # ── PERFIL 4 · INTERMEDIÁRIO 2 — Intel + RTX, btrfs, deep (o papel
    #    do CoolerControl JÁ EXISTIA — a chave entra na seção do dono)
    rodar_perfil 4 "Intermediário 2 · Intel + RTX + btrfs deep (coolercontrol do dono)" btrfs "" \
        '01:00.0 VGA compatible controller: NVIDIA Corporation AD103 [GeForce RTX 4080]' \
        's2idle [deep]' 1

    # ── PERFIL 5 · HIGH-END 1 — Ryzen X3D (k10temp) + RX 7900, btrfs,
    #    deep, MULTI-MONITOR (DP-1 + HDMI-A-1)
    rodar_perfil 5 "High-End 1 · Ryzen X3D + RX 7900 (k10temp, btrfs deep)" btrfs k10temp \
        '00:08.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 31 [Radeon RX 7900 XT]' \
        's2idle [deep]' 1

    # ── PERFIL 6 · HIGH-END 2 — Intel + RTX 4080, btrfs, deep,
    #    multi-monitor (DP-1 + DP-2)
    rodar_perfil 6 "High-End 2 · Intel + RTX 4080 (btrfs deep, DP-1+DP-2)" btrfs nct6775 \
        '01:00.0 VGA compatible controller: NVIDIA Corporation AD103 [GeForce RTX 4080]' \
        's2idle [deep]' 1

    # ── A TELA QUE VOLTA (perfis com display na matriz) ──
    run_display 3 "o rig do dono" \
        'DP-1|mode:1920x1080@119.88|pos:0,0|scale:1.000000|transform:normal|adaptive:enabled' \
        'DP-1 "RX 7600 [DP-1]"
  Enabled: yes
  Position: 0,0
  Transform: normal
  Scale: 1.000000
  Adaptive Sync: enabled
  Modes:
    1920x1080 px, 60.00 Hz
    1920x1080 px, 119.88 Hz (current)' \
        '--output DP-1 --off
--output DP-1 --on --mode 1920x1080@119.88'

    run_display 5 "high-end AMD multi-monitor" \
        'DP-1|mode:2560x1440@143.98|pos:0,0|scale:1.000000|transform:normal|adaptive:enabled
HDMI-A-1|mode:1920x1080@59.94|pos:2560,0|scale:1.000000|transform:normal|adaptive:disabled' \
        'DP-1 "RX 7900 XT [DP-1]"
  Enabled: yes
  Position: 0,0
  Transform: normal
  Scale: 1.000000
  Adaptive Sync: enabled
  Modes:
    2560x1440 px, 143.98 Hz (current)
    2560x1440 px, 59.95 Hz
HDMI-A-1 "RX 7900 XT [HDMI-A-1]"
  Enabled: yes
  Position: 2560,0
  Transform: normal
  Scale: 1.000000
  Adaptive Sync: disabled
  Modes:
    1920x1080 px, 59.94 Hz (current)' \
        '--output DP-1 --off
--output DP-1 --on --mode 2560x1440@143.98
--output HDMI-A-1 --off
--output HDMI-A-1 --on --mode 1920x1080@59.94'

    run_display 6 "high-end NVIDIA multi-monitor" \
        'DP-1|mode:3840x2160@143.99|pos:0,0|scale:1.000000|transform:normal|adaptive:disabled
DP-2|mode:1920x1080@119.88|pos:3840,0|scale:1.000000|transform:normal|adaptive:disabled' \
        'DP-1 "RTX 4080 [DP-1]"
  Enabled: yes
  Position: 0,0
  Transform: normal
  Scale: 1.000000
  Adaptive Sync: disabled
  Modes:
    3840x2160 px, 143.99 Hz (current)
    3840x2160 px, 59.97 Hz
DP-2 "RTX 4080 [DP-2]"
  Enabled: yes
  Position: 3840,0
  Transform: normal
  Scale: 1.000000
  Adaptive Sync: disabled
  Modes:
    1920x1080 px, 119.88 Hz (current)' \
        '--output DP-1 --off
--output DP-1 --on --mode 3840x2160@143.99
--output DP-2 --off
--output DP-2 --on --mode 1920x1080@119.88'

    # ── O SONO QUE ACORDA (o rig do dono) ──
    run_wakeup 3

    printf 'SUMMARY\t%s\t%s\n' "$OK" "$FAIL"
    [ "$FAIL" -eq 0 ] || exit 1
    exit 0
}

main "$@"
