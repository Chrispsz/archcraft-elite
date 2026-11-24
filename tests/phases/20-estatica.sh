#!/usr/bin/env bash
# tests/phases/20-estatica.sh — FASE 2: os contratos sobre os ARQUIVOS reais
# (tuning sagrado, configs, pacotes da diretriz, legado ausente, qualidade)
set -uo pipefail
source "$(dirname "$0")/../lib/core.sh"

echo "  ── FASE 2 · ESTÁTICA REAL — os contratos na árvore ──"

AIROOTFS="elite/airootfs"

# ══ O TUNING SAGRADO (§7: nada de template genérico; só se SOMA) ══
file_has "sysctl: swappiness 180 (a casa zram)" "$AIROOTFS/etc/sysctl.d/99-elite-performance.conf" 'vm.swappiness = 180'
file_has "sysctl: vfs_cache_pressure 50" "$AIROOTFS/etc/sysctl.d/99-elite-performance.conf" 'vm.vfs_cache_pressure = 50'
file_has "sysctl: max_map_count topo (jogos/proton)" "$AIROOTFS/etc/sysctl.d/99-elite-performance.conf" 'vm.max_map_count = 2147483642'
file_has "sysctl: BBR + fq (a rede da casa)" "$AIROOTFS/etc/sysctl.d/99-elite-performance.conf" 'net.ipv4.tcp_congestion_control = bbr'
file_has "sysctl: qdisc fq" "$AIROOTFS/etc/sysctl.d/99-elite-performance.conf" 'net.core.default_qdisc = fq'
file_has "udev: a regra zram da casa vence o vendor (SYSCTL 180)" "$AIROOTFS/etc/udev/rules.d/99-elite-zram.rules" 'SYSCTL{vm.swappiness}="180"'
file_has "udev: ntsync destravado (o proton da casa)" "$AIROOTFS/etc/udev/rules.d/60-ntsync.rules" 'ntsync'
file_has "modprobe: powersave de dispositivos (E38)" "$AIROOTFS/etc/modprobe.d/99-elite-powersave.conf" 'snd_hda_intel power_save=1'
file_has "modprobe: iwlwifi powersave" "$AIROOTFS/etc/modprobe.d/99-elite-powersave.conf" 'iwlwifi power_save=1'

# ── o par da diretriz 2.0 no boot (SOMA idempotente nos 2 ramos de GPU) ──
N_MIT="$(grep -c 'mitigations=off' "$AIROOTFS/usr/local/bin/elite-install-stage" 2>/dev/null || true)"
N_WDOG="$(grep -c 'nowatchdog' "$AIROOTFS/usr/local/bin/elite-install-stage" 2>/dev/null || true)"
N_PP="$(grep -c 'amdgpu.ppfeaturemask=0xffffffff' "$AIROOTFS/usr/local/bin/elite-install-stage" 2>/dev/null || true)"
if [ "$N_MIT" -ge 2 ]; then t_ok "grub: mitigations=off nos 2 ramos (AMD+NVIDIA, $N_MIT ocorrências)"
else t_fail "grub: mitigations=off nos 2 ramos" "achado $N_MIT (< 2)"; fi
if [ "$N_WDOG" -ge 2 ]; then t_ok "grub: nowatchdog nos 2 ramos ($N_WDOG)"
else t_fail "grub: nowatchdog nos 2 ramos" "achado $N_WDOG (< 2)"; fi
if [ "$N_PP" -ge 2 ]; then t_ok "grub: ppfeaturemask preservado nos 2 ramos ($N_PP)"
else t_fail "grub: ppfeaturemask preservado" "achado $N_PP (< 2)"; fi

# ══ OS CONFIGS DA SESSÃO (a interface nativa) ══
xml_ok "menu.xml nasce bem-formado" "$AIROOTFS/etc/skel/.config/labwc/menu.xml"
xml_ok "rc.xml nasce bem-formado" "$AIROOTFS/etc/skel/.config/labwc/rc.xml"
ini_ok "fuzzel.ini nasce com seção (a lição E137)" "$AIROOTFS/etc/skel/.config/fuzzel/fuzzel.ini"

file_has "menu: o Suspender é verbo de primeira classe" "$AIROOTFS/etc/skel/.config/labwc/menu.xml" 'systemctl suspend'
file_has "menu: o Desligar é direto" "$AIROOTFS/etc/skel/.config/labwc/menu.xml" 'systemctl poweroff'
file_has "menu: o Reiniciar é direto" "$AIROOTFS/etc/skel/.config/labwc/menu.xml" 'systemctl reboot'
file_hasnt "menu: o ITEM da gaveta fuzzel não volta (comentário de era é história)" "$AIROOTFS/etc/skel/.config/labwc/menu.xml" 'label="Apps da dock"'
file_has "rc.xml: W-n é o nm-connection-editor (a edição de verdade)" "$AIROOTFS/etc/skel/.config/labwc/rc.xml" 'nm-connection-editor'
file_has "rc.xml: W-S-b é o blueman-manager (a tela dedicada)" "$AIROOTFS/etc/skel/.config/labwc/rc.xml" 'blueman-manager'
file_has "rc.xml: o mixer é o pwvucontrol" "$AIROOTFS/etc/skel/.config/labwc/rc.xml" 'pwvucontrol'
file_has "rc.xml: o editor é o gnome-text-editor" "$AIROOTFS/etc/skel/.config/labwc/rc.xml" 'gnome-text-editor'
file_hasnt "rc.xml: o mousepad legado não volta" "$AIROOTFS/etc/skel/.config/labwc/rc.xml" 'mousepad'
file_has "autostart: o orquestrador ÚNICO é o elite-daemon session" "$AIROOTFS/etc/skel/.config/labwc/autostart" 'elite-daemon session'
file_hasnt "autostart: o craft-bars não volta (a cola sh morreu)" "$AIROOTFS/etc/skel/.config/labwc/autostart" 'craft-bars &'
file_hasnt "autostart: nenhuma spawn direta de waybar" "$AIROOTFS/etc/skel/.config/labwc/autostart" 'waybar &'

# ══ O PACOTE (as ferramentas dedicadas da diretriz, o debloat) ══
PKG="elite/packages.add"
for p in iwgtk blueman nm-connection-editor pwvucontrol coolercontrol swaync nwg-drawer gnome-text-editor papers brave-origin swayidle udiskie cliphist swayosd xorg-server; do
    file_line_exact "packages.add: a ferramenta dedicada $p" "$PKG" "$p"
done
file_hasnt "packages.add: o waybar NÃO volta (a top bar é nativa)" "$PKG" '^waybar$'
file_has "packages.remove: o mousepad fica fora (gnome-text-editor é o editor)" "elite/packages.remove" 'mousepad'
file_line_exact "packages.remove: o kernel stock continua fora (BORE único)" "elite/packages.remove" 'linux'

# ══ O MOLDE DO PACOTE (a ponte crates/ → elite-system) ══
BS=".ci/build.sh"
file_has "build.sh: o estágio Rust fala /work/crates" "$BS" 'tar -C /work/crates'
file_has "build.sh: elite-core entra na família" "$BS" 'RUST_CRATES="elite-core elite-daemon"'
file_has "build.sh: craft-dump-rs entra se presente" "$BS" 'craft-dump-rs'
file_has "build.sh: o MANIFEST nasce dos bins reais (skip do craft-toplevel C)" "$BS" '[ "$b" = "craft-toplevel" ] && continue'
file_has "build.sh: o CoolerControl viaja com o override --disable-gpu" "$BS" 'org.coolercontrol.CoolerControl.desktop'
file_has "guard-pkgrel: o exclude acompanhou crates/" ".ci/guard-pkgrel.sh" 'crates/**'

# ══ O LEGADO AUSENTE (a varredura nos caminhos ATIVOS) ══
scan_vivo() { # scan_vivo <regex> — só linhas de CÓDIGO (não comentário),
    # fora dos peritos/ceifadores nomeados (craft-dump noma fósseis;
    # elite-post-upgrade e craft-update os CEIFAM — migração, não uso)
    grep -rnE "$1" "$AIROOTFS/usr/local/bin" 2>/dev/null \
        | awk -F: '$0 !~ /craft-dump|elite-session-probe|elite-post-upgrade|craft-update|craft-bgapps/ {
            line=$3; gsub(/^[ \t]+/, "", line)
            if (line !~ /^#/) print $1":"$2
        }'
}
legacy_hits="$(scan_vivo 'craft-bars|craft-connect|craft-pin-pick|craft-dock-gui')"
[ -z "$legacy_hits" ] && t_ok "bins: ZERO chamada de código vivo aos fósseis (craft-bars/connect/pin-pick/dock-gui)" \
    || t_fail "bins: ZERO chamada de código vivo aos fósseis" "réus: $legacy_hits"
waybar_hits="$(scan_vivo 'pgrep -x waybar|exec waybar|(^|[ &])waybar(&|[ ])')"
[ -z "$waybar_hits" ] && t_ok "bins: ZERO spawn vivo de waybar (o perito e as ceifas de migração são legítimos)" \
    || t_fail "bins: ZERO spawn vivo de waybar" "réus: $waybar_hits"
file_absent "skel: a pasta waybar não volta" "$AIROOTFS/etc/skel/.config/waybar"

# ══ A QUALIDADE (o shellcheck da casa — 0 avisos, a lei §3) ══
if command -v shellcheck >/dev/null 2>&1; then
    sh_ok=1
    sh_out="$(shellcheck -x scripts/*.sh .ci/*.sh 2>&1)" || sh_ok=0
    if [ "$sh_ok" = 1 ]; then
        t_ok "shellcheck: 0 avisos em scripts/ e .ci/"
    else
        t_fail "shellcheck: 0 avisos em scripts/ e .ci/" "$(printf '%s' "$sh_out" | head -4 | tr '\n' ' ')"
    fi
else
    t_skip "shellcheck" "toolchain ausente no ambiente (o CI instala)"
fi

# ══ A CONSTITUIÇÃO (o §7 da filosofia 2.0 no papel) ══
file_has "AGENTS.md: a seção §7 (a filosofia 2.0 na constituição)" "AGENTS.md" '§7 · Filosofia 2.0'
file_has "AGENTS.md: reprojetar, nunca clonar" "AGENTS.md" 'Reprojetar, nunca clonar o legado'
file_has "AGENTS.md: o tuning sagrado preservado" "AGENTS.md" 'Tuning de baixo nível é SAGRADO'
file_has "PROTOCOL.md: a lei L2 (a porteira)" "docs/gestao/PROTOCOL.md" 'L2 · Suíte porteira'
file_has "PROTOCOL.md: a lei L4 (nunca tag de trabalho diário)" "docs/gestao/PROTOCOL.md" 'L4 · Trabalho diário NUNCA pusha tag'

printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase20.txt"
exit 0
