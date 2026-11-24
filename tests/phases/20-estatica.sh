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
# 2.0 Fase 2 — o swayidle APOSENTOU (a vigília é do elite-daemon nativo)
PKG="elite/packages.add"
for p in iwgtk blueman nm-connection-editor pwvucontrol coolercontrol swaync nwg-drawer gnome-text-editor papers brave-origin udiskie cliphist swayosd xorg-server; do
    file_line_exact "packages.add: a ferramenta dedicada $p" "$PKG" "$p"
done
file_hasnt "packages.add: o waybar NÃO volta (a top bar é nativa)" "$PKG" '^waybar$'
file_line_exact "packages.remove: o swayidle aposentado (a vigília é do daemon)" "elite/packages.remove" 'swayidle'
file_line_exact "packages.remove: o craft-toplevel aposentado (o C de 3 gerações)" "elite/packages.remove" 'craft-toplevel'
file_has "packages.remove: o mousepad fica fora (gnome-text-editor é o editor)" "elite/packages.remove" 'mousepad'
file_line_exact "packages.remove: o kernel stock continua fora (BORE único)" "elite/packages.remove" 'linux'

# ══ O MOLDE DO PACOTE (a ponte crates/ → elite-system) ══
BS=".ci/build.sh"
file_has "build.sh: o estágio Rust fala /work/crates" "$BS" 'tar -C /work/crates'
file_has "build.sh: elite-core entra na família" "$BS" 'RUST_CRATES="elite-core elite-daemon"'
file_has "build.sh: craft-dump-rs entra se presente" "$BS" 'craft-dump-rs'
file_has "build.sh: o MANIFEST nasce dos bins reais (2.0: os bins COMPILADOS pulam o overlay)" "$BS" 'craft-update|craft-clean|craft-help|craft-pick|craft-dump|elite-daemon|craft-bar-rs|craft-dock-rs) continue'
file_has "build.sh: o CoolerControl viaja com o override --disable-gpu" "$BS" 'org.coolercontrol.CoolerControl.desktop'
file_has "guard-pkgrel: o Rust é conteúdo do elite-system (crates/** no delta — a lei E41 pega a fundação)" ".ci/guard-pkgrel.sh" "crates/**"

# ══ O LEGADO AUSENTE (a varredura nos caminhos ATIVOS) ══
scan_vivo() { # scan_vivo <regex> — só linhas de CÓDIGO (não comentário),
    # fora dos peritos/ceifadores nomeados (craft-dump noma fósseis;
    # elite-post-upgrade e os motores elite-dose/elite-clean os CEIFAM
    # — migração, não uso; os nomes mudaram na 2.0, a função continua)
    grep -rnE "$1" "$AIROOTFS/usr/local/bin" 2>/dev/null \
        | awk -F: '$0 !~ /craft-dump|elite-session-probe|elite-post-upgrade|elite-dose|elite-clean|craft-bgapps/ {
            line=$3; gsub(/^[ \t]+/, "", line)
            if (line !~ /^#/) print $1":"$2
        }'
}
legacy_hits="$(scan_vivo 'craft-bars|craft-connect|craft-pin-pick|craft-dock-gui')"
[ -z "$legacy_hits" ] && t_ok "bins: ZERO chamada de código vivo aos fósseis (craft-bars/connect/pin-pick/dock-gui)" \
    || t_fail "bins: ZERO chamada de código vivo aos fósseis" "réus: $legacy_hits"
# 2.0 Fase 2 — os 12 chamadores do craft-menu APOSENTARAM (a diretriz:
# popovers nativos + ferramentas dedicadas; o picker é o craft-pick)
menu_hits="$(scan_vivo 'craft-menu |craft-menu$|craft-menu --|craft-player|craft-power|craft-logout|craft-drawer|craft-audio-route')"
[ -z "$menu_hits" ] && t_ok "bins: ZERO chamada viva ao craft-menu e sua era (player/power/logout/drawer/audio-route)" \
    || t_fail "bins: ZERO chamada viva ao craft-menu e sua era" "réus: $menu_hits"
waybar_hits="$(scan_vivo 'pgrep -x waybar|exec waybar|(^|[ &])waybar(&|[ ])')"
[ -z "$waybar_hits" ] && t_ok "bins: ZERO spawn vivo de waybar (o perito e as ceifas de migração são legítimos)" \
    || t_fail "bins: ZERO spawn vivo de waybar" "réus: $waybar_hits"
file_absent "skel: a pasta waybar não volta" "$AIROOTFS/etc/skel/.config/waybar"

# ══ A QUALIDADE (o shellcheck da casa — 0 avisos warning+, a lei §3) ══
# O MESMO CONTRATO DA ERA ANTERIOR (2bbca8c, 20-static): -S warning (o
# SC2016 info é história da casa, não réu) + shebang python fora do escopo
if command -v shellcheck >/dev/null 2>&1; then
    sh_ok=1
    sh_out="$(shellcheck -S warning -x scripts/*.sh .ci/*.sh 2>&1)" || sh_ok=0
    if [ "$sh_ok" = 1 ]; then
        t_ok "shellcheck (-S warning): 0 avisos em scripts/ e .ci/"
    else
        t_fail "shellcheck (-S warning): 0 avisos em scripts/ e .ci/" "$(printf '%s' "$sh_out" | head -4 | tr '\n' ' ')"
    fi
else
    t_skip "shellcheck" "toolchain ausente no ambiente (o CI instala)"
fi

# ══ A CONSTITUIÇÃO (o §7 da filosofia 2.0 no papel) ══
file_has "AGENTS.md: a seção §7 (a filosofia 2.0 na constituição)" "AGENTS.md" '§7 · Filosofia 2.0'
file_has "AGENTS.md: reprojetar, nunca clonar" "AGENTS.md" 'Reprojetar, nunca clonar o legado'
file_has "AGENTS.md: o tuning sagrado preservado" "AGENTS.md" 'Tuning de baixo nível é SAGRADO'
file_has "AGENTS.md: a lei do commit puro (§6.1 — sem Co-Authored-By)" "AGENTS.md" 'Co-Authored-By'
file_has "PROTOCOL.md: a lei L2 (a porteira)" "docs/gestao/PROTOCOL.md" 'L2 · Suíte porteira'
file_has "PROTOCOL.md: a lei L4 (nunca tag de trabalho diário)" "docs/gestao/PROTOCOL.md" 'L4 · Trabalho diário NUNCA pusha tag'

# ══ 1.0-93 · A LEI DO COMMIT PURO EXECUTADA (§6.1: nenhum commit recente
#    carrega o TRAILER Co-Authored-By: — o grep é ÂNCORADO em início de
#    linha porque a MENÇÃO da lei no corpo de um commit de cura é texto
#    legítimo, não trailer; o push de commit contaminado morre NA
#    PORTEIRA, antes do Canal) ══
_coauth="$(git log -40 --pretty=%B 2>/dev/null | grep -c '^[[:space:]]*Co-Authored-By:' || true)"
if [ "${_coauth:-0}" -eq 0 ]; then
    t_ok "git: nenhum trailer Co-Authored-By nos últimos 40 commits (a lei §6.1)"
else
    t_fail "git: nenhum trailer Co-Authored-By nos últimos 40 commits (a lei §6.1)" "achado $_coauth trailer(s) — amend antes do push"
fi

# ══ 1.0-93 · OS NOVOS CONTRATOS DO PACOTE (scx-lavd direto, sudoers limpo,
#    a paleta unificada na folha mestra) ══
file_has "unit: o scx-lavd.service DIRETO (ExecStart=/usr/bin/scx_lavd)" "$AIROOTFS/etc/systemd/system/scx-lavd.service" 'ExecStart=/usr/bin/scx_lavd'
file_has "unit: o scx-lavd só com sched_ext (PULADA, nunca FAILED)" "$AIROOTFS/etc/systemd/system/scx-lavd.service" 'ConditionPathExists=/sys/kernel/sched_ext'
file_has "sudoers: os insults do sudo saem da casa" "$AIROOTFS/etc/sudoers.d/99-elite-clean" 'Defaults !insults'
file_has "css: a paleta roxo/escuro ELITE (#13111c)" "crates/elite-core/assets/theme.css" '#13111c'
file_has "css: o acento roxo #9d7cd8" "crates/elite-core/assets/theme.css" '#9d7cd8'
file_has "css: o acento forte #bb9af7" "crates/elite-core/assets/theme.css" '#bb9af7'
file_has "css: o texto #e6e4f0" "crates/elite-core/assets/theme.css" '#e6e4f0'
file_has "bar: o CenterBox (o relógio exatamente no centro)" "crates/craft-bar-rs/src/ui.rs" 'CenterBox'
file_has "bar: o relógio LOCAL (o glib now_local — o UTC morre)" "crates/craft-bar-rs/src/ui.rs" 'now_local'
file_has "bar: o calendário GTK4 do hover" "crates/craft-bar-rs/src/ui.rs" 'gtk::Calendar'
file_has "bar: o ícone real do bgapps (o f085 quebrado sai)" "crates/craft-bar-rs/src/ui.rs" 'system-run-symbolic'
file_has "bar: o seletor rápido de rede (popover)" "crates/craft-bar-rs/src/ui.rs" 'popover_rede'
file_has "bar: o botão Aplicativos com ícone GTK" "crates/craft-bar-rs/src/ui.rs" 'view-app-grid-symbolic'
file_hasnt "bar: as pílulas da mesa não voltam (o scroll/atalho do labwc manda)" "crates/craft-bar-rs/src/ui.rs" 'wsbtn'
file_hasnt "bar: o título ativo não volta (a moldura da janela manda)" "crates/craft-bar-rs/src/ui.rs" 'titulolbl'
file_has "ipc: o lock da sessão no tmpfs do dono" "crates/elite-core/src/lib.rs" 'session_lock_path'
file_has "ipc: o teto de 500ms na conexão (a classe dos 49s morre)" "crates/elite-core/src/ipc.rs" 'IPC_CONNECT_TETO_MS'
file_has "daemon: o session usa o lock privado" "crates/elite-daemon/src/supervise.rs" 'session_lock_path'
file_has "dock: o queue_draw no evento do toplevel (o fantasma morre)" "crates/craft-dock-rs/src/ui.rs" 'queue_draw'
file_has "dump: o upload do termbin (o --upload)" "crates/craft-dump-rs/src/main.rs" 'termbin'
file_has "dump: o SUDO_UID resolvido (o dono, não o root)" "crates/craft-dump-rs/src/main.rs" 'SUDO_UID'
file_has "dump: o journal de erros do boot" "crates/craft-dump-rs/src/main.rs" 'journalctl'
file_has "display: o verbo icc (perfis registrados, fronteira nomeada)" "$AIROOTFS/usr/local/bin/craft-display" '    icc)'
file_has "post-upgrade: a migração do autostart dos homes vivos" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'elite-daemon session &'
file_has "post-upgrade: o debloat waybar/gpsd com consulta de dependentes" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'Required By'
file_has "post-upgrade: mitigations=off no GRUB da dose" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'mitigations=off'
file_has "tune: o scx-lavd direto também no painel" "$AIROOTFS/usr/local/bin/elite-tune" 'scx-lavd.service'
file_has "probe: o lock privado também no probe da sessão" "$AIROOTFS/usr/local/bin/elite-session-probe" 'session.lock'

# ══ 1.0-94 (E145 — A DOSE DOS TESTES REAIS DA 1.0-93) ══
# a ARMADURA RT: o intervalo real-time INTEIRO handled no 1º instante
file_has "bar: a armadura RT (o 'real-time event N' não mata mais a barra)" "crates/craft-bar-rs/src/ui.rs" 'fn arma_rt'
file_has "dock: a armadura RT (a instabilidade visual morre na classe)" "crates/craft-dock-rs/src/ui.rs" 'fn arma_rt'
# o DONO ÚNICO do bus: o modo game vira CLIENTE publicante
file_has "daemon: o modo game sem posse vira CLIENTE do bus" "crates/elite-daemon/src/nucleo.rs" 'fn liga_cliente'
file_has "daemon: o daemon_loop decide a posse ANTES do bind" "crates/elite-daemon/src/main.rs" 'nucleo::liga_cliente()'
file_has "bus: a publicação de cliente retransmitida (sem eco ao remetente)" "crates/elite-core/src/bus.rs" 'fn publish'
file_has "bus: a retransmissão exclui o remetente (o loop infinito morre)" "crates/elite-core/src/bus.rs" 'remetente não bebe o próprio eco'
# o craft-clean sobe como raiz de verdade (o pkexec na frente)
file_has "tools: o pkexec na frente do elite-clean (a porta --as-root é de raiz)" "crates/craft-tools/src/lib.rs" '"pkexec".to_string()'
# o probe nunca mais CRIA o bars.lock do dono
file_has "probe: o bars.lock só é conferido se EXISTE (o root:root morre)" "$AIROOTFS/usr/local/bin/elite-session-probe" '[ -e "$_bars_lock" ]'
# os menus abrem PAINÉIS, não CLIs mudos
file_has "menu: o Modo de jogo abre o painel (craft-game menu)" "elite/airootfs/etc/skel/.config/labwc/menu.xml" 'command="craft-game menu"'
file_has "menu: a Trava automática abre o painel (craft-idle menu)" "elite/airootfs/etc/skel/.config/labwc/menu.xml" 'command="craft-idle menu"'
file_has "idle: o verbo menu existe (o painel do dono)" "$AIROOTFS/usr/local/bin/craft-idle" 'craft-pick --title'
# a gaveta com memória
file_line_exact "apps: o craft-apps é bin da casa (a gaveta com toggle)" "$AIROOTFS/usr/local/bin/craft-apps" '#!/bin/sh'
file_has "apps: o toggle mata a gaveta DO DONO pelo comm" "$AIROOTFS/usr/local/bin/craft-apps" 'nwg-drawer'
file_has "rc: o W-d vira o craft-apps (o toggle de primeira classe)" "elite/airootfs/etc/skel/.config/labwc/rc.xml" 'command="craft-apps"'
# o dump v2.1: os 3 estados do bus + a perícia dos benignos + as caudas
file_has "dump: o bus de 3 estados (MORTO ≠ CALADO — dois réus distintos)" "crates/craft-dump-rs/src/lib.rs" 'pub enum ColheitaBus'
file_has "dump: a perícia dos erros conhecidos do boot" "crates/craft-dump-rs/src/lib.rs" 'pub fn anota_conhecido'
file_has "dump: as caudas da sessão no papel" "crates/craft-dump-rs/src/main.rs" 'as caudas da sessão'
file_has "dump: o pactl veste o runtime do dono (o pkexec vê o PipeWire)" "crates/craft-dump-rs/src/main.rs" 'fn colhe_com_runtime'
# o respawn visual nas trocas de monitor
file_has "daemon: o DRM uevent re-sinaliza a dock/barra (o refresh de pele)" "crates/elite-daemon/src/main.rs" 'craft-dock-rs'
# as permissões dos dirs casam com o distro (o aviso do pacman cala)
file_has "build.sh: o sudoers.d veste 750 (o aviso de permissão cala)" "$BS" 'install -dm750 "${pkgdir}/etc/sudoers.d"'
file_has "build.sh: o polkit rules.d veste 750 (idem)" "$BS" 'install -dm750 "${pkgdir}/etc/polkit-1/rules.d"'

printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase20.txt"
exit 0
