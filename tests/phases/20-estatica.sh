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
menu_ok "menu.xml nasce SEM texto órfão fora de tag (E146 — a gramática da casa)" "$AIROOTFS/etc/skel/.config/labwc/menu.xml"
xml_ok "rc.xml nasce bem-formado" "$AIROOTFS/etc/skel/.config/labwc/rc.xml"
ini_ok "fuzzel.ini nasce com seção (a lição E137)" "$AIROOTFS/etc/skel/.config/fuzzel/fuzzel.ini"

# 1.0-108 — O SONO E O ENCERRAR PELAS PORTAS DA CASA (o systemctl nu e o
# labwc --exit nu saem das telas: o craft-suspend espera o lock MAPEAR
# antes do freeze, o craft-logout encerra a família em ORDEM)
file_has "menu: o Suspender é verbo de primeira classe (1.0-108: pela porta do craft-suspend)" "$AIROOTFS/etc/skel/.config/labwc/menu.xml" 'craft-suspend'
file_has "menu: o Encerrar sessão veste o encerrar ORDEIRO (craft-logout)" "$AIROOTFS/etc/skel/.config/labwc/menu.xml" 'craft-logout'
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
# 1.0-108 — O ARRANQUE LIMPO (a diretriz do dono palavra por palavra):
# o autostart é o berço do FRAME 0 — o AMBIENTE no D-Bus (labwc:wlroots),
# os ALICERCES que não dependem do supervisor (swaybg, agente polkit com
# guard pgrep, udiskie --automount --notify --no-tray, fix-keys,
# cliphist) e UM SÓ orquestrador (elite-daemon session no bloco
# BEGIN/END). O daemon doente de 1.0-107.3 levava o berço junto — agora
# o frame 0 nasce de pé por conta própria.
file_has "autostart: o AMBIENTE no D-Bus antes de tudo (labwc:wlroots da diretriz)" "$AIROOTFS/etc/skel/.config/labwc/autostart" 'XDG_CURRENT_DESKTOP=labwc:wlroots'
file_has "autostart: o swaybg é alicerce de frame 0 (não depende do motor)" "$AIROOTFS/etc/skel/.config/labwc/autostart" 'swaybg -m fill'
file_has "autostart: o agente polkit nasce com guard pgrep (UM só na sessão)" "$AIROOTFS/etc/skel/.config/labwc/autostart" 'pgrep -x lxqt-policykit-agent'
file_has "autostart: o automount é o udiskie da diretriz (--notify --no-tray)" "$AIROOTFS/etc/skel/.config/labwc/autostart" 'udiskie --automount --notify --no-tray'
file_has "autostart: o keyring de sempre (craft-fix-keys)" "$AIROOTFS/etc/skel/.config/labwc/autostart" 'craft-fix-keys'
file_has "autostart: o clipboard de sempre (cliphist)" "$AIROOTFS/etc/skel/.config/labwc/autostart" 'cliphist store'
file_has "autostart: o bloco gerenciado do orquestrador (E146)" "$AIROOTFS/etc/skel/.config/labwc/autostart" 'BEGIN ELITE-DAEMON-SESSION'
# PROIBIDO no autostart (linha VIVA): o swaync é do SUPERVISOR (a lei
# 1.0-107 — o elite-daemon session é o ÚNICO dono da central) e o
# resto é fóssil de era; o corpo congelado de dose antiga é fóssil que
# o elite-heal-sessao reconstrói do mestre
_nao_residente="$(grep -vE '^[[:space:]]*(#|$)' "$AIROOTFS/etc/skel/.config/labwc/autostart" 2>/dev/null \
    | grep -cE '(^|[[:space:]/])(swaync|swayosd-server|polkit-gnome|waybar|craft-bars|craft-toplevel|swayidle)([[:space:]]|&|$)' || true)"
if [ "${_nao_residente:-0}" -eq 0 ]; then
    t_ok "autostart: ZERO residente proibido em linha viva (o swaync é do supervisor — 1.0-108)"
else
    t_fail "autostart: ZERO residente proibido em linha viva" \
        "$_nao_residente spawn(s) fóssil(is) — o swaync/swayosd são do supervisor, os outros são de era morta"
fi
unset _nao_residente

# ══ O PACOTE (as ferramentas dedicadas da diretriz, o debloat) ══
# 2.0 Fase 2 — o swayidle APOSENTOU (a vigília é do elite-daemon nativo)
PKG="elite/packages.add"
for p in iwgtk blueman nm-connection-editor pwvucontrol coolercontrol nwg-drawer gnome-text-editor papers brave-origin cliphist swayosd lxqt-policykit; do
    file_line_exact "packages.add: a ferramenta dedicada $p" "$PKG" "$p"
done
# 1.0-108 — O ARRANQUE LIMPO NOS PACOTES (a reversão da E151 pela
# diretriz: o udiskie é o automounter do frame 0 de novo — o par udev
# oneshot de era aposentou; a LINHA INTEIRA é o contrato)
file_line_absent "packages.add: o waybar NÃO volta (a top bar é nativa)" "$PKG" 'waybar'
file_line_absent "packages.add: o xorg-server NÃO volta (o greeter é wayland nativo)" "$PKG" 'xorg-server'
file_line_exact "packages.add: o udiskie VOLTA (o automounter do arranque limpo)" "$PKG" 'udiskie'
file_line_exact "packages.add: o adwaita-icon-theme garante o cursor do greeter (CursorTheme=Adwaita)" "$PKG" 'adwaita-icon-theme'
file_line_absent "packages.add: o hyprpolkitagent NÃO volta (o polkit é ÚNICO)" "$PKG" 'hyprpolkitagent'
file_line_exact "packages.remove: o xorg-server aposentado (o greeter veste wayland — E151)" "elite/packages.remove" 'xorg-server'
file_line_absent "packages.remove: o udiskie NÃO sai mais (a reversão 1.0-108 — o arranque limpo é o dono do automount)" "elite/packages.remove" 'udiskie'
file_line_exact "packages.remove: o hyprpolkitagent aposentado (o lxqt-policykit é o ÚNICO)" "elite/packages.remove" 'hyprpolkitagent'
file_has "packages.remove: os legados i3-wm/feh/openbox/i3status vedados (a faxina E151)" "elite/packages.remove" 'feh'
file_line_exact "packages.remove: o swayidle aposentado (a vigília é do daemon)" "elite/packages.remove" 'swayidle'
file_line_exact "packages.remove: o craft-toplevel aposentado (o C de 3 gerações)" "elite/packages.remove" 'craft-toplevel'
file_has "packages.remove: o mousepad fica fora (gnome-text-editor é o editor)" "elite/packages.remove" 'mousepad'
file_line_exact "packages.remove: o kernel stock continua fora (BORE único)" "elite/packages.remove" 'linux'

# ══ 1.0-103 — A ERRADICAÇÃO DO PYTHON (a radiografia de linguagens) ══
BS=".ci/build.sh"
# o repo NÃO carrega mais NENHUM arquivo .py (o último foi o gate do
# Calamares — portado ao juiz de casa craft-audit). A lista é do INDEX do
# git (E35.1/E39: a árvore de trabalho pode carregar fósseis de fora —
# o repo é o que o git rastreia):
PY_FILES="$(git ls-files '*.py' 2>/dev/null || true)"
if [ -z "$PY_FILES" ]; then
    t_ok "repo: ZERO arquivo .py no index (o gate do Calamares agora é craft-audit calamares)"
else
    t_fail "repo: ZERO arquivo .py no index" "fósseis: $(printf '%s' "$PY_FILES" | head -3 | tr '\n' ' ')"
fi
# e nenhum CÓDIGO python embutido nos scripts da casa (os comentários que
# NARRAM a morte do python são legítimos; heredoc python = réu):
PY_HD="$(grep -rn "<<'PY" elite/airootfs tests .ci/build.sh scripts 2>/dev/null | grep -v 'PYE50\|PYE57' | head -3 || true)"
if [ -z "$PY_HD" ]; then
    t_ok "repo: ZERO heredoc python vivo (o juiz é o craft-audit de casa)"
else
    t_fail "repo: ZERO heredoc python vivo" "réus: $PY_HD"
fi
# o heredoc do molde PKGBUILD agora é COTADO com @marcas@ (o f-string morreu):
file_has "build.sh: o molde PKGBUILD é sh puro com marcas" "$BS" "<<'MOLDE_PKGBUILD'"
file_has "build.sh: a substituição do molde é expansão de parâmetro" "$BS" 'linha="${linha//@$marca@/$esc}"'
file_has "build.sh: o juiz craft-audit embarca com a família de bins" "$BS" 'craft-update craft-clean craft-help craft-pick craft-net craft-dump craft-audit; do'
# o juiz de casa existe e fala todos os verbos:
file_has "craft-audit: o núcleo do juiz vive no craft-tools" "crates/craft-tools/src/audit.rs" 'pub fn xml_bem_formado'
file_has "craft-audit: a gramática E146 do menu" "crates/craft-tools/src/audit.rs" 'pub fn menu_sem_orfao'
file_has "craft-audit: o gate do Calamares portado" "crates/craft-tools/src/audit.rs" 'pub fn calamares_confere'
file_has "craft-audit: o aperto de mão do bus.sock" "crates/craft-tools/src/audit.rs" 'pub fn hello_bus'
file_has "craft-audit: a resolução de Execute da fase 40" "crates/craft-tools/src/audit.rs" 'pub fn resolve_exec'
file_has "craft-audit: o bin da linha de comando" "crates/craft-tools/src/bin/craft-audit.rs" 'exec-resolve'

# ══ O MOLDE DO PACOTE (a ponte crates/ → elite-system) ══
BS=".ci/build.sh"
file_has "build.sh: o estágio Rust fala /work/crates" "$BS" 'tar -C /work/crates'
file_has "build.sh: elite-core entra na família" "$BS" 'RUST_CRATES="elite-core elite-daemon"'
file_has "build.sh: craft-dump-rs entra se presente" "$BS" 'craft-dump-rs'
file_has "build.sh: o MANIFEST nasce dos bins reais (2.0: os bins COMPILADOS pulam o overlay)" "$BS" 'craft-update|craft-clean|craft-help|craft-pick|craft-net|craft-dump|craft-audit|elite-daemon|craft-bar-rs|craft-dock-rs) continue'
file_has "build.sh: o CoolerControl viaja com o override --disable-gpu" "$BS" 'org.coolercontrol.CoolerControl.desktop'
file_has "guard-pkgrel: o Rust é conteúdo do elite-system (crates/** no delta — a lei E41 pega a fundação)" ".ci/guard-pkgrel.sh" "crates/**"

# ══ O LEGADO AUSENTE (a varredura nos caminhos ATIVOS) ══
scan_vivo() { # scan_vivo <regex> — só linhas de CÓDIGO (não comentário),
    # fora dos peritos/ceifadores nomeados (craft-dump noma fósseis;
    # elite-post-upgrade e os motores elite-dose/elite-clean os CEIFAM
    # — migração, não uso; os nomes mudaram na 2.0, a função continua.
    # 1.0-102 — o elite-heal-sessao entra na lista: o juízo do FÓSSIL DE
    # SPAWN NOMEA os fósseis para os CAÇAR no autostart doente — o
    # grep dele é a perícia, nunca o uso)
    grep -rnE "$1" "$AIROOTFS/usr/local/bin" 2>/dev/null \
        | awk -F: '$0 !~ /craft-dump|elite-session-probe|elite-post-upgrade|elite-dose|elite-clean|craft-bgapps|elite-heal-sessao/ {
            line=$3; gsub(/^[ \t]+/, "", line)
            if (line !~ /^#/) print $1":"$2
        }'
}
legacy_hits="$(scan_vivo 'craft-bars|craft-connect|craft-pin-pick|craft-dock-gui')"
[ -z "$legacy_hits" ] && t_ok "bins: ZERO chamada de código vivo aos fósseis (craft-bars/connect/pin-pick/dock-gui)" \
    || t_fail "bins: ZERO chamada de código vivo aos fósseis" "réus: $legacy_hits"
# 2.0 Fase 2 — os 12 chamadores do craft-menu APOSENTARAM (a diretriz:
# popovers nativos + ferramentas dedicadas; o picker é o craft-pick).
# 1.0-108 — o craft-logout SAIU da era do craft-menu: renasce como o
# ENCODER ORDEIRO da dose (contrato próprio, âncoras acima)
menu_hits="$(scan_vivo 'craft-menu |craft-menu$|craft-menu --|craft-player|craft-power|craft-drawer|craft-audio-route')"
[ -z "$menu_hits" ] && t_ok "bins: ZERO chamada viva ao craft-menu e sua era (player/power/drawer/audio-route)" \
    || t_fail "bins: ZERO chamada viva ao craft-menu e sua era" "réus: $menu_hits"
waybar_hits="$(scan_vivo 'pgrep -x waybar|exec waybar|(^|[ &])waybar(&|[ ])')"
[ -z "$waybar_hits" ] && t_ok "bins: ZERO spawn vivo de waybar (o perito e as ceifas de migração são legítimos)" \
    || t_fail "bins: ZERO spawn vivo de waybar" "réus: $waybar_hits"
file_absent "skel: a pasta waybar não volta" "$AIROOTFS/etc/skel/.config/waybar"

# ══ A QUALIDADE (o shellcheck da casa — 0 avisos warning+, a lei §3) ══
# O MESMO CONTRATO DA ERA ANTERIOR (2bbca8c, 20-static): -S warning (o
# SC2016 info é história da casa, não réu) + shebang python fora do escopo
# 1.0-107.3 — O GATE LOCAL VESTE A CASA INTEIRA (o MESMO recorte do gate
# do build.yml: a família elite-*, os hooks de system-sleep, o exo-open e
# o log do calamares entram — o gate que não vê o que o CI julga é
# contrato morto; a varredura local é o espelho fiel da esteira)
if command -v shellcheck >/dev/null 2>&1; then
    sh_ok=1
    sh_out="$(shellcheck -S warning -x scripts/*.sh .ci/*.sh \
        elite/airootfs/usr/local/bin/elite-* \
        elite/airootfs/usr/local/bin/craft-* \
        elite/airootfs/usr/local/bin/exo-open \
        elite/airootfs/usr/local/bin/calamares-elite-log \
        elite/airootfs/usr/lib/systemd/system-sleep/elite-* \
        elite/airootfs/etc/skel/.config/labwc/autostart 2>&1)" || sh_ok=0
    if [ "$sh_ok" = 1 ]; then
        t_ok "shellcheck (-S warning): 0 avisos na casa inteira (scripts/, .ci/, elite-*, craft-*, hooks, autostart)"
    else
        t_fail "shellcheck (-S warning): 0 avisos na casa inteira (scripts/, .ci/, elite-*, craft-*, hooks, autostart)" "$(printf '%s' "$sh_out" | head -4 | tr '\n' ' ')"
    fi
else
    t_skip "shellcheck" "toolchain ausente no ambiente (o CI instala)"
fi

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
# BLOCO 3 (1.0-98) — A PALETA OFICIAL DO GUIA 02 substitui os 4 hexes da
# era 1.0-93 (os antigos #13111c/#9d7cd8/#bb9af7/#e6e4f0 MORREM — os
# novos são os 7 tokens medidos WCAG da Diretriz Mestre; a substituição
# é 4 por 4 — o GO continua COM mais prova, não menos)
file_has "css: a base oficial #11111b (guia 02 — superfície elevada)" "crates/elite-core/assets/theme.css" '#11111b'
file_has "css: o acento primário #a855f7 (purple-500)" "crates/elite-core/assets/theme.css" '#a855f7'
file_has "css: o acento suave #cba6f7 (mauve)" "crates/elite-core/assets/theme.css" '#cba6f7'
file_has "css: o texto nítido #f8fafc (relógio/títulos)" "crates/elite-core/assets/theme.css" '#f8fafc'
file_has "bar: o CenterBox (o relógio exatamente no centro)" "crates/craft-bar-rs/src/ui.rs" 'CenterBox'
file_has "bar: o relógio LOCAL (o glib now_local — o UTC morre)" "crates/craft-bar-rs/src/ui.rs" 'now_local'
file_has "bar: o calendário GTK4 do hover" "crates/craft-bar-rs/src/ui.rs" 'gtk::Calendar'
# E147 — A RECONSTRUÇÃO DA UI: os contratos novos substituem os da era
# E149 — O MAPA DIRETO: o ESQUERDO abre a FERRAMENTA de verdade, o
# DIREITO é a AÇÃO RÁPIDA sem janela (a era popover customizado morre —
# os 3 contratos da central/painel/seletor de popover são SUBSTITUÍDOS)
file_has "bar: o mapa E149 do áudio — o ESQUERDO abre o pwvucontrol" "crates/craft-bar-rs/src/ui.rs" 'pwvucontrol'
file_has "bar: o mute RÁPIDO no direito (wpctl set-mute na hora, sem janela)" "crates/craft-bar-rs/src/ui.rs" 'set-mute'
file_has "bar: o mapa E149 do bluetooth — o ESQUERDO abre o blueman-manager" "crates/craft-bar-rs/src/ui.rs" 'blueman-manager'
# 1.0-105 — o esquerdo da rede é o FRONT-END GRÁFICO do NetworkManager
# (a distro é NetworkManager; o iwgtk cede o assento do clique)
file_has "bar: o mapa E149 da rede — o ESQUERDO abre o nm-connection-editor (1.0-105)" "crates/craft-bar-rs/src/ui.rs" 'nm-connection-editor'
file_has "bar: o direito da rede alterna o RÁDIO Wi-Fi na hora" "crates/craft-bar-rs/src/ui.rs" '["radio", "wifi"]'
file_has "bar: a sessão é O endereço único de Bloquear/Encerrar (o dedupe da diretriz)" "crates/craft-bar-rs/src/ui.rs" 'bar.logout'
file_has "bar: o ícone por NOME GTK (o glifo Nerd quebrado morre)" "crates/craft-bar-rs/src/ui.rs" 'audio-volume-high-symbolic'
file_has "bar: o juízo do ícone de volume pelo estado (o núcleo nomeia)" "crates/craft-bar-rs/src/state.rs" 'audio-volume-muted-symbolic'
file_hasnt "bar: o bgapps NÃO VOLTA (a ordem do dono: fora da interface e do código)" "crates/craft-bar-rs/src/ui.rs" 'craft-bgapps'
file_hasnt "bar: NENHUM glifo Nerd Font no label (a fonte GTK não os tem)" "crates/craft-bar-rs/src/ui.rs" '\\u{f027}'
file_hasnt "daemon: o ouvidor bus bgapps não volta (nenhum emissor do +9)" "crates/elite-daemon/src/main.rs" 'thread_bus_bgapps'
file_has "post-upgrade: o fóssil craft-bgapps morre com voz" "elite/airootfs/usr/local/bin/elite-post-upgrade" 'craft-bgapps'
file_has "post-upgrade: a sincronização de peles do skel" "elite/airootfs/usr/local/bin/elite-post-upgrade" 'sync_skel'
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
# E146 — A CURA DOS ARQUIVOS DE SESSÃO: a âncora antiga (migração por
# append) foi SUBSTITUÍDA — o heal detecta corrupção (nº de lançadores
# ≠ 1, XML órfão) e reconstrói do mestre com prova pós-escrita.
file_has "post-upgrade: a cura dos arquivos de sessão mora no heal" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'elite-heal-sessao'
file_has "heal: o bin da cura existe (E146)" "$AIROOTFS/usr/local/bin/elite-heal-sessao" 'BEGIN ELITE-DAEMON-SESSION'
file_has "heal: o julgamento estrito do menu (texto órfão é defeito)" "$AIROOTFS/usr/local/bin/elite-heal-sessao" 'menu_ok'
file_has "heal: a rotação dos backups (1 por base)" "$AIROOTFS/usr/local/bin/elite-heal-sessao" 'saneia_baks'
file_has "rice: o backup único (a rotação E146)" "$AIROOTFS/usr/local/bin/craft-rice" 'bak_unica'
file_has "rice: o xmllint é o juiz principal do XML" "$AIROOTFS/usr/local/bin/craft-rice" 'xmllint --noout'
file_has "dump: o modo --full (o consolidado limpo E146)" "crates/craft-dump-rs/src/main.rs" 'modo_full'
file_has "post-upgrade: o debloat waybar/gpsd com consulta de dependentes" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'Required By'
file_has "post-upgrade: mitigations=off no GRUB da dose" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'mitigations=off'
file_has "tune: o scx-lavd direto também no painel" "$AIROOTFS/usr/local/bin/elite-tune" 'scx-lavd.service'
file_has "probe: o lock privado também no probe da sessão" "$AIROOTFS/usr/local/bin/elite-session-probe" 'session.lock'

# ══ 1.0-94 (E145 — A DOSE DOS TESTES REAIS DA 1.0-93) ══
# a ARMADURA RT: o intervalo real-time INTEIRO handled no 1º instante
file_has "bar: a armadura RT (o 'real-time event N' não mata mais a barra)" "crates/craft-bar-rs/src/ui.rs" 'fn arma_rt'
file_has "dock: a armadura RT (a instabilidade visual morre na classe)" "crates/craft-dock-rs/src/ui.rs" 'fn arma_rt'
# o DONO ÚNICO do bus: o modo game vira CLIENTE publicante
file_has "daemon: a publicação é broadcast do dono do bus (o game-notify publica pelo fio)" "crates/elite-daemon/src/nucleo.rs" 'e.bus.broadcast(msg)' 
file_has "daemon: o CLI game-notify publica o QueryStatus REAL no bus (o pill acende no clique)" "crates/elite-daemon/src/main.rs" 'cli.publish(&elite_core::BusMsg::GameMode' 
file_has "bus: a publicação de cliente retransmitida (sem eco ao remetente)" "crates/elite-core/src/bus.rs" 'fn publish'
# o craft-clean sobe como raiz de verdade (o pkexec na frente)
file_has "tools: o pkexec na frente do elite-clean (a porta --as-root é de raiz)" "crates/craft-tools/src/lib.rs" '"pkexec".to_string()'
# o probe nunca mais CRIA o bars.lock do dono
# os menus abrem PAINÉIS, não CLIs mudos — E106/2: a execução é
# NATIVA (o craft-pick é a ÚNICA janela; o foot preto de era, com o
# aviso de portal e o hangup no fechar, morre da porta do dono)
file_has "menu: o Modo de jogo roda NATIVO (craft-game menu — sem foot)" "elite/airootfs/etc/skel/.config/labwc/menu.xml" "command=\"craft-game menu\""
file_has "menu: a Auto-suspensão roda NATIVA (craft-idle menu — sem foot)" "elite/airootfs/etc/skel/.config/labwc/menu.xml" "command=\"craft-idle menu\""
# 1.0-105 — a forma do foot (com espaço) é a bandeira do seletor: o -T
# com ESPAÇO no craft-pick e nos wrappers da casa (o --title= colado morre)
file_has "idle: o verbo menu existe (o painel do dono — forma do foot -T)" "$AIROOTFS/usr/local/bin/craft-idle" 'craft-pick -T "$1"'
# E149 — A FÁBRICA DA VAGA AUTOMÁTICA E DA TRAVA (a diretriz: o modo
# jogo volta a nascer ligado; o skel cobre a ISO nova, o post_upgrade
# cobre o rig que antecedeu a dose)
file_absent "jogo: o game.conf morreu com o modo automático (o manual é o único)" "elite/airootfs/etc/skel/.config/elite/game.conf"
file_has "trava: a fábrica do idle trava em 5 (LOCK_MIN da casa)" "elite/airootfs/etc/skel/.config/elite/idle.conf" 'LOCK_MIN=5'
# E150 — o gesto separado: a tela APAGA no tempo PRÓPRIO (fábrica 10)
file_has "trava: a fábrica do idle apaga em 10 (o gesto separado E150)" "elite/airootfs/etc/skel/.config/elite/idle.conf" 'OFF_MIN=10'
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

# ══ BLOCO 4 (1.0-98) — LOCK + GREETER NA PALETA OFICIAL (docs/skills/02) ══
# A LOCK SKIN v8: os tokens oficiais substituem a aproximação da era v5/v7
# (a paleta antiga do theme.conf do SDDM) — os rgba velhos MORREM do código:
file_has "lock v8: o foco/digitação veste o acento #a855f7" "$AIROOTFS/etc/skel/.config/hypr/hyprlock.conf" 'rgba(168, 85, 247'
file_has "lock v8: o erro veste o #f38ba8 (elite-danger)" "$AIROOTFS/etc/skel/.config/hypr/hyprlock.conf" 'rgba(243, 139, 168'
file_has "lock v8: o relógio veste o nítido #f8fafc" "$AIROOTFS/etc/skel/.config/hypr/hyprlock.conf" 'rgba(248, 250, 252'
file_has "lock v8: a borda inativa veste o grafite #262637" "$AIROOTFS/etc/skel/.config/hypr/hyprlock.conf" 'rgba(38, 38, 55'
file_has "lock v8: o campo veste a ilha #181825" "$AIROOTFS/etc/skel/.config/hypr/hyprlock.conf" 'rgba(24, 24, 37'
file_has "lock v8: o raio de canto é O RAIO DA DOCK (rounding = 20)" "$AIROOTFS/etc/skel/.config/hypr/hyprlock.conf" 'rounding = 20'
file_hasnt "lock v8: a paleta antiga do greeter MORRE do código (a era #D8D8D8 não volta)" "$AIROOTFS/etc/skel/.config/hypr/hyprlock.conf" 'rgba(216, 216, 216'
file_hasnt "lock v8: o azul de validação da era antiga não volta (#5294E2)" "$AIROOTFS/etc/skel/.config/hypr/hyprlock.conf" 'rgba(82, 148, 226'
# A PELE DO GREETER (theme.conf override do tema archcraft do SDDM — o
# stack NATIVO, zero daemon/dep nova):
file_has "greeter: a pele override veste a BORDA ROXA ATIVA em foco" "$AIROOTFS/usr/share/sddm/themes/archcraft/theme.conf" 'HighlightBorderColor="#a855f7"'
file_has "greeter: o relógio do login veste o nítido #f8fafc" "$AIROOTFS/usr/share/sddm/themes/archcraft/theme.conf" 'TimeTextColor="#f8fafc"'
file_has "greeter: a data veste o #cdd6f4" "$AIROOTFS/usr/share/sddm/themes/archcraft/theme.conf" 'DateTextColor="#cdd6f4"'
file_has "greeter: o erro do login veste o #f38ba8" "$AIROOTFS/usr/share/sddm/themes/archcraft/theme.conf" 'WarningColor="#f38ba8"'
file_has "greeter: os campos veste o raio da dock (RoundCorners 20)" "$AIROOTFS/usr/share/sddm/themes/archcraft/theme.conf" 'RoundCorners="20"'
file_has "greeter: o blur leve está ligado (FullBlur true, custo só do instante)" "$AIROOTFS/usr/share/sddm/themes/archcraft/theme.conf" 'FullBlur="true"'
file_has "greeter: ZERO saudação (HeaderText vazio — uma voz por tela)" "$AIROOTFS/usr/share/sddm/themes/archcraft/theme.conf" 'HeaderText=""'
file_has "greeter: o hover NUNCA inverte para claro (acento suave #cba6f7)" "$AIROOTFS/usr/share/sddm/themes/archcraft/theme.conf" 'HoverSessionButtonTextColor="#cba6f7"'
# A SESSÃO DE ENTRADA + O CHÃO TÉCNICO 1.0-108 (99-elite.conf — as três
# chaves da diretriz: InputMethod vazio, CursorTheme=Adwaita garantido
# no disco pelo adwaita-icon-theme, ReuseSession=false; um dono por
# chave — o elite.conf segue dono SÓ do Current):
file_has "greeter 99: o InputMethod vazio (o stub do teclado virtual de era morre)" "$AIROOTFS/etc/sddm.conf.d/99-elite.conf" 'InputMethod='
file_has "greeter 99: o cursor é Adwaita (o tema que a MÁQUINA garante — 'Could not setup default cursor' morre)" "$AIROOTFS/etc/sddm.conf.d/99-elite.conf" 'CursorTheme=Adwaita'
file_has "greeter 99: o ReuseSession=false (a sessão reciclada das dores de relogin morre)" "$AIROOTFS/etc/sddm.conf.d/99-elite.conf" 'ReuseSession=false'
file_has "greeter: o elite.conf segue dono SÓ do Current (um dono por chave)" "$AIROOTFS/etc/sddm.conf.d/elite.conf" 'Current=elite'
file_hasnt "greeter: o elite.conf NÃO veste mais o chão do 99 (dois donos pela mesma chave não)" "$AIROOTFS/etc/sddm.conf.d/elite.conf" 'InputMethod='
file_has "greeter: a sessão do autologin é labwc (sem ruído de seletor)" "$AIROOTFS/etc/sddm.conf.d/kde_settings.conf" 'Session=labwc'
file_has "build.sh: o mestre 99-elite.conf viaja no pacote" "$BS" '/usr/local/share/elite/sddm/99-elite.conf'
file_has "post-upgrade: o 99-elite.conf chega ao rig vivo na dose (escola E150)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" '/etc/sddm.conf.d/99-elite.conf'
file_line_absent "packages.add: o archcraft-cursor-qogirr não volta (pacote órfão aposentado)" "$PKG" 'archcraft-cursor-qogirr'
# A ENTREGA (uma fonte, dois veículos — ISO via overlay, rig via mestre):
file_has "build.sh: o mestre do greeter viaja no pacote (elite/sddm)" "$BS" '/usr/local/share/elite/sddm/theme.conf'
file_has "build.sh: o mestre do greeter nasce DA MESMA FONTE do overlay" "$BS" '/work/elite/airootfs/usr/share/sddm/themes/archcraft/theme.conf'
file_has "post-upgrade: a pele do greeter chega ao rig vivo na dose" "$AIROOTFS/usr/local/bin/elite-post-upgrade" '/usr/share/sddm/themes/archcraft/theme.conf'
file_has "rice: o fóssil da v7 na rede do lock (quem adotou a v7 renova à v8)" "$AIROOTFS/usr/local/bin/craft-rice" '6e4597244cb625dde1ed33f419afabb8bf9270230a4218311c9c4acf9919b0ea'
# O MOLDE veste o pkgrel 107.3 (lei E41 — o guard compara versão)
# (1.0-107.3 — a auditoria total dos pacotes: pkgrel com ponto, o 108
#  fica reservado ao ciclo pós-validação no hardware; a âncora viva
#  sobe junto NO MESMO COMMIT do conteúdo)
file_has "build.sh: o pkgrel da dose é 108 (elite-system 1.0-108 — a dose completa: motor/infra da Etapa 1 + camada visual da Etapa 2, lei E41 no MESMO commit)" "$BS" 'pkgrel=108'

# ══ 1.0-107.3 — A PERÍCIA DO CONJUNTO FINAL DA ISO (as 4 redundâncias
#    que a debloat de eras não via + o backend de portais que faltava) ══
file_has "packages.remove: o pavucontrol vedado (o mixer é o pwvucontrol GTK4 — DOIS mixers é duplicação)" "elite/packages.remove" 'pavucontrol'
file_has "packages.remove: o pulsemixer vedado (TUI sem chamador na casa zero-TUI)" "elite/packages.remove" 'pulsemixer'
file_has "packages.remove: o network-manager-applet vedado (a higiene o tira dos rigs — a ISO não nasce com ele)" "elite/packages.remove" 'network-manager-applet'
file_has "packages.remove: o xf86-input-libinput vedado (DDX de input do xorg-server que a E151 aposentou)" "elite/packages.remove" 'xf86-input-libinput'
file_line_absent "packages.add: o pavucontrol NÃO volta (o pwvucontrol é o único mixer da ISO)" "$PKG" 'pavucontrol'
file_line_absent "packages.add: o pulsemixer NÃO volta (zero TUI de fábrica)" "$PKG" 'pulsemixer'
file_line_absent "packages.add: o network-manager-applet NÃO volta (a rede é módulo nativo da barra)" "$PKG" 'network-manager-applet'
file_line_absent "packages.add: o xf86-input-libinput NÃO volta (Xwayland tem o próprio input)" "$PKG" 'xf86-input-libinput'
file_has "packages.add: o backend GTK dos portais (FileChooser para apps Flatpak — 1.0-107.3)" "$PKG" 'xdg-desktop-portal-gtk'

# ══ 1.0-107.2 — O SUPERVISOR É EVENTO (a auditoria da filosofia: o
#    tick de 1s morre — o kernel toca a campainha) ══
file_has "daemon: o self-pipe dos eventos (SIGCHLD acorda o supervisor)" "crates/elite-daemon/src/main.rs" 'libc::signal(libc::SIGCHLD, ao_chld'
file_has "daemon: a espera do supervisor é poll(2) com teto (espera_evento)" "crates/elite-daemon/src/main.rs" 'pub(crate) fn espera_evento(teto_ms: i32)'
file_has "daemon: a vigia inotify do socket do compositor (o cão vira evento)" "crates/elite-daemon/src/main.rs" 'libc::inotify_add_watch(fd, c_dir.as_ptr(), libc::IN_DELETE)'
file_has "daemon: o STOP da thread acorda o que espera (fim_da_sessao toca o pipe)" "crates/elite-daemon/src/main.rs" 'A CAMPAINHA DIRETA (o STOP nasce de uma THREAD'
file_has "supervise: o loop dorme nos eventos com o teto do respawn" "crates/elite-daemon/src/supervise.rs" 'super::espera_evento(if teto < 0 { KEEPALIVE_MS } else { teto });'
file_has "supervise: o keepalive da adoção é honesto e nomeado (15s)" "crates/elite-daemon/src/supervise.rs" 'const KEEPALIVE_MS: i32 = 15_000;'
file_has "supervise: o teto do papel do bars.log (256 KiB, rabiço 128 KiB)" "crates/elite-daemon/src/supervise.rs" 'fn cap_log(log: &std::path::Path)'
file_hasnt "supervise: o tick de 1s de era não volta (a espera é evento)" "crates/elite-daemon/src/supervise.rs" 'std::thread::sleep(Duration::from_secs(1));'

# ══ 1.0-107.2 — O DIAGNÓSTICO EM 1 COMANDO (o craft-doctor: os
#    invariantes vitais da máquina real julgados em <50ms, zero bloat) ══
file_has "doctor: o módulo do diagnóstico mora no daemon (a corrida de 1 tiro)" "crates/elite-daemon/src/doctor.rs" 'pub fn run() -> i32'
file_has "doctor: o julgo da tabela wakeup é o MESMO do elite-acpi-wakeup (uma lei só)" "crates/elite-daemon/src/doctor.rs" 'pub fn julga_wakeup'
file_has "doctor: o relatório nomeia o réu com o código de saída honesto" "crates/elite-daemon/src/doctor.rs" 'pub fn relatorio(diags: &[Diag]) -> (String, i32)'
file_has "doctor: o handshake do bus.sock usa o teto da fundação (zero thread)" "crates/elite-daemon/src/doctor.rs" 'connect_bus'
file_has "doctor: o pactl SÓ nasce com o socket do PipeWire no chão (o stat antes do fork)" "crates/elite-daemon/src/doctor.rs" 'pipewire-0'
file_has "doctor: o agente polkit é lido em /proc comm (zero fork de pgrep)" "crates/elite-daemon/src/doctor.rs" 'lxqt-policykit-'
file_has "doctor: a porta doctor do elite-daemon" "crates/elite-daemon/src/main.rs" 'Some("doctor") => {'
file_has "doctor: o elo craft-doctor chega pelo argv0 (o symlink do pacote)" "crates/elite-daemon/src/main.rs" 'argv0 == Some("craft-doctor")'
# 1.0-107.2 — O GUARDA DO BUS (a corrida da 2ª instância: o bind de era
# matava o socket do dono PELO PATH — o craft-doctor nomeou o réu no Canal)
file_has "daemon: o guarda do bus julga o lock ANTES do liga_bus" "crates/elite-daemon/src/main.rs" 'if supervise::guarda_bus() {'
file_has "supervise: o guarda existe e escreve o papel da recusa" "crates/elite-daemon/src/supervise.rs" 'pub fn guarda_bus() -> bool'
# A CURA DO CANAL VERMELHO (#45632905510 — o E0599 pela 2ª era): o gdk4
# 0.11.5 NÃO gera monitor-added/removed/monitors-changed (deprecated desde
# o GTK 4.16, fora de DisplayExt) — a via viva é o items-changed do
# GListModel de monitors(); o comentário da era que dizia 'o 0.11 o
# entrega sem aviso' MENTIA (a classe E33 morre junto):
file_hasnt "monitor: o trio morto do gdk4 0.11 não volta (connect_monitor_added é E0599)" "crates/craft-bar-rs/src/ui.rs" 'connect_monitor_added'
file_hasnt "monitor: o trio morto do gdk4 0.11 não volta (dock idem)" "crates/craft-dock-rs/src/ui.rs" 'connect_monitor_added'
file_has "monitor: o ouvidor vivo é o items-changed do GListModel (barra)" "crates/craft-bar-rs/src/ui.rs" 'connect_items_changed'
file_has "monitor: o ouvidor vivo é o items-changed do GListModel (dock)" "crates/craft-dock-rs/src/ui.rs" 'connect_items_changed'

# ══ 1.0-106 — A CENTRAL DE NOTIFICAÇÕES MORREU, O CENSO MPRIS E O
#    BLUETOOTH INICIAL NO ARRANQUE ══
# o swaync MORREU por ordem do dono (o relógio é hora/calendário; a
# casa não carrega notificador NENHUM): AUSENTE da árvore, do pacote e
# do fluxo vivo do build:
file_exists "skel: o skel swaync VOLTOU com dono único (o style.css existente mata o COULD NOT FIND CSS FILE!)" "elite/airootfs/etc/skel/.config/swaync/style.css"
file_has "pkg: o molde swc_install volta ao PKGBUILD (os mestres da central com dono único)" "$BS" 'MOLDE[swc_install]' 
file_hasnt "daemon: o residente swaync NÃO volta à fila (RESIDENTES_DEFAULT limpa)" "crates/elite-daemon/src/supervise.rs" '("swaync",'
file_hasnt "heal: a cura do swaync NÃO volta (o morto não se cura)" "elite/airootfs/usr/local/bin/elite-heal-sessao" 'cura_swaync'
# o censo MPRIS no arranque: a thread NASCE com os nomes do bus
# (ListNames → GetNameOwner) e o estado inicial vestido (GetAll), com
# o título/autor lidos por CHAVE dentro do dict Metadata:
file_has "mpris: o censo de arranque varre os nomes do bus (ListNames)" "crates/elite-daemon/src/mpris.rs" 'ListNames'
file_has "mpris: a posse do nome é o GetNameOwner (o censo adota, não duplica)" "crates/elite-daemon/src/mpris.rs" 'GetNameOwner'
file_has "mpris: o estado inicial vem do GetAll (o contrato nasce vestido)" "crates/elite-daemon/src/mpris.rs" '"GetAll"'
file_has "mpris: o título/autor moram por chave no dict Metadata (xesam:title)" "crates/elite-daemon/src/mpris.rs" '"xesam:title"'
file_has "mpris: o artista veste a lista de era (xesam:artist — o brave manda array)" "crates/elite-daemon/src/mpris.rs" '"xesam:artist"'
# o bluetooth inicial consultado no arranque (o D-Bus nativo veste o
# Powered do adaptador — zero bluetoothctl de 10s no daemon):
file_exists "bluetooth: o estado inicial é módulo da casa (bluetooth.rs)" "crates/elite-daemon/src/bluetooth.rs"
file_has "bluetooth: o Powered do adaptador no D-Bus nativo (o ícone nasce certo)" "crates/elite-daemon/src/bluetooth.rs" '"Powered"'
# a barra da dose: o esquerdo da rede abre o SELETOR DE 1 CLIQUE (o
# craft-net de 1.0-109 — a evidência do dump: o esquerdo não executava
# ação NENHUMA), o direito veste a LEI DA CONEXÃO PRINCIPAL:
file_has "bar: o esquerdo da rede abre o CRAFT-NET (o seletor de 1 clique da diretriz)" "crates/craft-bar-rs/src/ui.rs" 'solta(&["craft-net"])'
# 1.0-108 — A LEI DA CONEXÃO PRINCIPAL (a evidência do rig 1.0-107.3: o
# direito de era derrubava o Networking INTEIRO — o enp7s0 "não
# disponível" sem volta; ethernet vence, quem cai é UMA conexão):
file_has "bar: o direito da rede veste a LEI DA CONEXÃO PRINCIPAL (alterna_conexao_principal)" "crates/craft-bar-rs/src/ui.rs" 'alterna_conexao_principal()'
# 1.0-109 — A LEI DA REDE NA FUNDAÇÃO (uma lei só, duas superfícies: o
# craft-net e o direito da top bar vestem o MESMO julgamento) e o
# SELETOR DE 1 CLIQUE da diretriz:
file_has "rede: a lei desceu para a fundação (elite-core::rede — a ethernet vence)" "crates/elite-core/src/rede.rs" 'pub fn conexao_principal'
file_has "rede: a queda é o nmcli device disconnect (NUNCA ip link set down)" "crates/elite-core/src/rede.rs" '["device", "disconnect"]'
file_has "rede: a lista das redes Wi-Fi com sinal e cadeado (o parser do seletor)" "crates/elite-core/src/rede.rs" 'pub fn redes_wifi'
file_has "rede: o last-net.state guarda o par (DEVICE, CONNECTION) da volta" "crates/elite-core/src/rede.rs" 'pub fn conteudo_last_net'
file_has "net: o seletor de 1 clique nasce na família (Ethernet + Wi-Fi + editor)" "crates/craft-tools/src/bin/craft-net.rs" 'Gerenciador de Rede'
file_has "net: as redes Wi-Fi próximas com o rescan auto da diretriz" "crates/craft-tools/src/bin/craft-net.rs" '"--rescan"'
file_has "net: a senha em diálogo LIMPO apenas para a protegida sem perfil salvo" "crates/craft-tools/src/bin/craft-net.rs" 'tem_perfil_salvo'
file_has "net: o toggle da Ethernet veste a LEI DA CONEXÃO PRINCIPAL da fundação" "crates/craft-tools/src/bin/craft-net.rs" 'alterna_conexao_principal'
file_has "net: a janela veste a MESMA camada do pick (Overlay · exclusiva · centralizada)" "crates/craft-tools/src/bin/craft-net.rs" 'janela_camada(app, "pickwin", "Rede", "craft-net")'
file_has "net: a entrada Gerenciador de Rede mora na grade (a paridade com o Bluetooth)" "$AIROOTFS/usr/local/share/applications/craft-net.desktop" 'Gerenciador de Rede'
file_has "net: a entrada da grade é VISÍVEL (NoDisplay=false — o editor de era nascia escondido)" "$AIROOTFS/usr/local/share/applications/craft-net.desktop" 'NoDisplay=false'
file_has "net: o craft-net embarca no pacote (o bin compilado da família)" "crates/craft-tools/Cargo.toml" 'name = "craft-net"'
file_has "bar: o estado da lei mora na FUNDAÇÃO (conexao_principal: ethernet vence — 1.0-109, uma lei só)" "crates/elite-core/src/rede.rs" 'pub fn conexao_principal'
file_has "bar: o par da volta mora no last-net.state (a ordem do dono, palavra por palavra)" "crates/craft-bar-rs/src/ui.rs" 'last-net.state'
file_has "bar: a queda é pelo nmcli device disconnect (NUNCA ip link set down)" "crates/craft-bar-rs/src/ui.rs" 'args(["device", "disconnect"])'
file_has "bar: a volta veste o link DE PÉ (ip link set up, best-effort)" "crates/craft-bar-rs/src/ui.rs" 'args(["link", "set", &dev, "up"])'
file_has "bar: a volta devolve o dev ao NetworkManager (managed yes)" "crates/craft-bar-rs/src/ui.rs" 'args(["device", "set", &dev, "managed", "yes"])'
file_has "bar: a volta sobe a conexão SALVA (nmcli connection up)" "crates/craft-bar-rs/src/ui.rs" 'args(["connection", "up"])'
file_has "bar: a queda honesta cai no device cru (nmcli device connect)" "crates/craft-bar-rs/src/ui.rs" 'args(["device", "connect"])'
file_has "bar: a detecção viva da religação mora na FUNDAÇÃO (dev_para_religar)" "crates/elite-core/src/rede.rs" 'pub fn dev_para_religar'
file_hasnt "bar: o nmcli networking INTEIRO não derruba mais a rede (o réu de era não volta)" "crates/craft-bar-rs/src/ui.rs" 'alterna_nmcli(&["networking"])'
# 1.0-108 — A PARIDADE COM O BLUETOOTH: o editor gráfico de rede VISÍVEL
# na grade do craft-apps (o .desktop upstream nasce NoDisplay=true — o
# applet de era era a porta dele e o applet NEM EXISTE na casa):
file_exists "rede: o override do nm-connection-editor mora na frente do XDG_DATA_DIRS" "elite/airootfs/usr/local/share/applications/nm-connection-editor.desktop"
file_has "rede: o override fala a cara pt_BR (Conexões de Rede na grade)" "elite/airootfs/usr/local/share/applications/nm-connection-editor.desktop" 'Name=Conexões de Rede'
file_hasnt "rede: o override SEM NoDisplay (a grade enxerga o editor)" "elite/airootfs/usr/local/share/applications/nm-connection-editor.desktop" 'NoDisplay'
file_hasnt "rede: o override SEM NotShowIn (nenhuma casa escondida)" "elite/airootfs/usr/local/share/applications/nm-connection-editor.desktop" 'NotShowIn'
file_has "bar: o meio da rede abre o editor completo (nm-connection-editor)" "crates/craft-bar-rs/src/ui.rs" 'solta(&["nm-connection-editor"])'
# 1.0-108 — A EVIDÊNCIA DO RIG 1.0-107.3: o botão Aplicativos abria o
# FUZZEL enquanto a tecla Windows abria a grade do craft-apps (a casa
# tem UMA gaveta), e o relógio abria o calendário ao PASSAR O MOUSE:
file_has "bar: o botão de aplicativos dispara o CRAFT-APPS (a MESMA porta da tecla Windows)" "crates/craft-bar-rs/src/ui.rs" 'solta(&["craft-apps"])'
file_hasnt "bar: o fuzzel NÃO mora mais no botão de apps (a gaveta é do craft-apps)" "crates/craft-bar-rs/src/ui.rs" 'solta(&["fuzzel"])'
file_has "bar: o relógio é HORA/CALENDÁRIO (o clique abre o popover da casa)" "crates/craft-bar-rs/src/ui.rs" 'abre_calendario'
file_hasnt "bar: o hover do relógio MORREU (nenhum enter/leave abre o calendário — só o clique)" "crates/craft-bar-rs/src/ui.rs" 'connect_enter'
# 1.0-108 — OS ATALHOS RÁPIDOS do menu da barra (a ordem do dono: Modo de
# jogo, Auto-suspensão, Monitores/120 Hz, Atualizar, Limpar, Snapshots):
file_has "bar: o menu da barra veste o MODO DE JOGO (craft-game menu)" "crates/craft-bar-rs/src/ui.rs" '("game", &["craft-game", "menu"][..])'
file_has "bar: o menu da barra veste a TRAVA AUTOMÁTICA (craft-idle menu)" "crates/craft-bar-rs/src/ui.rs" '("idle", &["craft-idle", "menu"][..])'
file_has "bar: o menu da barra veste os MONITORES/120Hz (wdisplays)" "crates/craft-bar-rs/src/ui.rs" '("displays", &["wdisplays"][..])'
file_has "bar: o menu da barra veste o ATUALIZAR sistema (craft-update)" "crates/craft-bar-rs/src/ui.rs" '("update", &["craft-update"][..])'
file_has "bar: o menu da barra veste o LIMPAR sistema (craft-clean)" "crates/craft-bar-rs/src/ui.rs" '("clean", &["craft-clean"][..])'
file_has "bar: o menu da barra veste os SNAPSHOTS (craft-rollback)" "crates/craft-bar-rs/src/ui.rs" '("rollback", &["craft-rollback"][..])'
file_hasnt "bar: o painel do notificador de era NÃO volta ao relógio" "crates/craft-bar-rs/src/ui.rs" 'swaync-client'
# o conflito do /etc/default/scx morre (o caminho é do scx-scheds oficial):
file_hasnt "pkg: o /etc/default/scx NÃO viaja no pacote (o caminho é do scx-scheds — zero conflito)" ".ci/build.sh" 'files/etc/default/scx'
file_absent "airootfs: o /etc/default/scx não existe mais (o dono é o scx-scheds)" "elite/airootfs/etc/default/scx"
file_has "tune: o scheduler via DROP-IN do scx.service (nunca o arquivo do alheio)" "elite/airootfs/usr/local/bin/elite-tune" 'scx.service.d/override.conf'
# o TOPLEVEL_COUNT lê o bus VIVO (o toplevel.sock de era morreu):
file_has "probe: o TOPLEVEL_COUNT drena o snapshot do bus (craft-audit windows)" "elite/airootfs/usr/local/bin/elite-session-probe" 'craft-audit windows'
file_has "audit: o juiz de casa conta as janelas do snapshot de boas-vindas" "crates/craft-tools/src/audit.rs" 'pub fn conta_janelas'
file_has "probe: o contador de era craft-toplevel NÃO volta (o fio vivo é o bus)" "elite/airootfs/usr/local/bin/elite-session-probe" 'tp_count=0'

# ══ 1.0-105 — A FORMA DO FOOT (-T COM ESPAÇO), A DOCK SEM ANEL ROXO E O
#    FULLSCREEN DO COMPOSITOR EM PRIMEIRA CLASSE ══
# o seletor da casa fala a forma do foot (-T "título" COM ESPAÇO — o
# --title=VALOR colado morre nos wrappers da casa):
file_has "pick: o parser do seletor veste a forma do foot (-T título)" "crates/craft-tools/src/lib.rs" 'a == "-T"'
file_has "pick: o parser da forma longa de sempre segue viva (--title=)" "crates/craft-tools/src/lib.rs" 'strip_prefix("--title=")'
# E106/2 — o título do foot fica nas janelas de TERMINAL do menu (update/
# clean seguem no foot — os painéis nativos vestem o -T do craft-pick)
file_has "menu: as janelas de terminal do menu nascem com TÍTULO (foot -T)" "elite/airootfs/etc/skel/.config/labwc/menu.xml" "foot -T 'Atualizar o sistema' -e craft-update"
# a dock JAMAIS rouba o foco de teclado (o primeiro clique abre o app —
# não acorda a dock) e o anel roxo de foco morre no CSS:
file_has "dock: o teclado NUNCA é da dock (KeyboardMode::None — 1.0-105)" "crates/craft-dock-rs/src/ui.rs" 'KeyboardMode::None'
# 1.0-109 — A CONEXÃO PERSISTENTE ÚNICA (a evidência do dump 1.0-108:
# bus.cliente 3..7 — um ToplevelClient NOVO por clique, cada round-trip
# de até 1s BLOQUEANDO a main thread do GTK; a diretriz: uma única
# conexão persistente, zero IPC bloqueante no clique):
file_has "dock: o fio persistente nasce no bus (a thread de fundo entrega o Arc à UI)" "crates/craft-dock-rs/src/ui.rs" 'Bus(std::sync::Arc<elite_core::bus::BusClient>)'
file_has "dock: os VERBOS viajam pelo fio persistente (fire-and-forget — nunca round-trip)" "crates/craft-dock-rs/src/ui.rs" 'fn pede_verbo'
file_has "dock: o eco do verbo chega pelo MESMO fio (o Ack nomeado no papel)" "crates/craft-dock-rs/src/ui.rs" 'Ok(Msg::Ack { ok })'
file_has "dock: o snapshot do clique é o PUSH (o round-trip de LIST de era morre)" "crates/craft-dock-rs/src/ui.rs" 'A PROVA NO CLIQUE É O PUSH'
file_has "dock: o Estado guarda o fio único (bus: Option<Arc<BusClient>>)" "crates/craft-dock-rs/src/ui.rs" 'bus: Option<std::sync::Arc<elite_core::bus::BusClient>>'
file_hasnt "dock: o ToplevelClient por clique MORREU (o réu do bus.cliente 3..7)" "crates/craft-dock-rs/src/sock.rs" 'pub struct ToplevelClient'
file_hasnt "dock: NENHUM with_client abre fio no clique" "crates/craft-dock-rs/src/ui.rs" 'fn with_client'

file_has "css: o ANEL ROXO de foco da dock morre (outline/box-shadow none)" "crates/elite-core/assets/theme.css" '#dockbox button:focus-visible'
# o servidor/cliente do terminal nunca poluem os ícones abertos:
file_has "dock: o foot-server/footclient na DENYLIST (a ponte não é app)" "crates/craft-dock-rs/src/icons.rs" '"foot-server"'
# o fullscreen DO COMPOSITOR é de primeira classe (os jogos
# Proton/XWayland com ignoreConfigureRequest pedem o atalho real):
file_has "rc.xml: o W-f é o ToggleFullscreen DO COMPOSITOR (1.0-105)" "elite/airootfs/etc/skel/.config/labwc/rc.xml" '<keybind key="W-f">'
file_has "rc.xml: o A-Return idem (o clássico Alt+Enter dos jogos)" "elite/airootfs/etc/skel/.config/labwc/rc.xml" '<keybind key="A-Return">'
file_has "rc.xml: o Thunar segue vivo no C-A-f (um destino = um lugar)" "elite/airootfs/etc/skel/.config/labwc/rc.xml" '<keybind key="C-A-f">'
# o resolvedor de ícones vestem o Hydra de ~/.config/hydra e o cache
# unificado ~/.cache/elite/icons (a extração PE serve para sempre):
file_has "dock: o resolvedor busca os ícones no ~/.config/hydra do dono" "crates/craft-dock-rs/src/icons.rs" '".config/hydra"'
file_has "dock: o cache dos ícones de .exe veste o caminho da dose (~/.cache/elite/icons)" "crates/craft-dock-rs/src/main.rs" 'fn exeicon_cache_lookup'

# ══ E106/3 — O ÍNDICE NÃO ROUBA A IDENTIDADE DO DONO E O SEM-NOME FIXA ══
# o .desktop AUXILIAR (o bulk-rename que carrega o MESMO StartupWMClass,
# os *-settings, a família exo-*) nunca fica com a chave do app de
# verdade — thunar.desktop vence para WMClass Thunar:
file_has "dock: o índice ignora o .desktop AUXILIAR (o bulk-rename não rouba o WMClass)" "crates/craft-dock-rs/src/icons.rs" 'pub fn desktop_eh_auxiliar'
# o OCULTO (NoDisplay do foot-server da casa, que ordena ANTES no
# /usr/local) nunca rouba a chave do VISÍVEL (a chave "foot" é do
# foot.desktop do terminal — nunca do daemon):
file_has "dock: o OCULTO nunca rouba a chave do VISÍVEL (foot → foot.desktop)" "crates/craft-dock-rs/src/icons.rs" 'oculto(&entries[j]) && !oculto(e)'
# o SEM-NOME fixa gerando .desktop LOCAL no ~/.local do dono (Elite
# nunca escreve no sistema) e o desafixar apaga SÓ o que a casa gerou:
file_has "dock: o raw FIXA gerando .desktop local (elite-<chave>.desktop)" "crates/craft-dock-rs/src/ui.rs" 'fn fixa_raw'
file_has "dock: o corpo do .desktop do sem-nome é puro e testado (Name/Exec/WMClass)" "crates/craft-dock-rs/src/icons.rs" 'pub fn desktop_do_raw'
file_has "dock: o desafixar do raw apaga SÓ o .desktop gerado pela casa" "crates/craft-dock-rs/src/ui.rs" 'fn remove_desktop_gerado'
file_has "dock: a prova de origem do sem-nome é o mesmo Exec da fixação (argv0 → AppImage)" "crates/craft-dock-rs/src/procapp.rs" 'pub fn raw_exec_provavel'
file_has "dock: a re-indexação na hora (o pin do .desktop novo nasce resolve)" "crates/craft-dock-rs/src/ui.rs" 'fn reindexa_desktops'
# o log de arranque fala o fio REAL (bus.sock com BusClient persistente
# — o toplevel.sock de era é história narrada, nunca presente mentido):

# ══ E150 — A ONDA FINAL 1/2 (base 1.0-98): RELOGIN LIMPO, BOOT FRIO DOS
# HZ, SDDM/GRUB REAIS, DUMP SISTÊMICO, GAVETA E PALCO, PAUSAS E 126 ══
# O RELOGIN LIMPO (o SIGHUP da sessão velha + a colheita do órfão + a
# espera do compositor + a re-aplicação do monitor no boot frio):
file_has "relogin: o SIGHUP veste a saída limpa (o flock não fica retido)" "crates/elite-daemon/src/main.rs" 'libc::signal(libc::SIGHUP'
file_has "relogin: a colheita do irmão órfão (o lock traz o PID do dono)" "crates/elite-daemon/src/supervise.rs" 'pub fn colhe_relogin'
file_has "relogin: o pid da vaga gravado no lock (a identidade do dono)" "crates/elite-daemon/src/supervise.rs" 'std::process::id()'
file_has "relogin: a sessão espera o WAYLAND_DISPLAY registrar (teto 10s)" "crates/elite-daemon/src/main.rs" 'fn espera_wayland'
file_has "relogin: o fóssil de crash varrido antes do liga_bus" "crates/elite-daemon/src/supervise.rs" 'display-'
# o vídeo pós-suspensão e o idle que renasce no despertar:
file_has "resume: o wlopm --on religa as saídas no despertar" "crates/elite-daemon/src/main.rs" 'wlopm'
file_has "resume: o idle renasce no PrepareForSleep(false)/Unlock" "crates/elite-daemon/src/wayland.rs" 'pub fn reseta_idle'
# ══ E106/5a — O S3 DEEP, OS GATILHOS ESPÚRIOS E A RECUPERAÇÃO DE VÍDEO ══
# o deep hardware-aware nos TRÊS caminhos da casa (install-stage, tune e
# a dose do post-upgrade — o mesmo juízo: /sys/power/mem_sleep com deep):
file_has "grub: o S3 deep hardware-aware no install-stage (o único sono do rig sem LPS0)" "$AIROOTFS/usr/local/bin/elite-install-stage" 'mem_sleep_default=deep'
file_has "grub: o S3 deep hardware-aware no tune (deep no /sys/power/mem_sleep)" "$AIROOTFS/usr/local/bin/elite-tune" 'mem_sleep_default=deep'
file_has "grub: o S3 deep chega ao rig na dose (post-upgrade _ensure_token)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'mem_sleep_default=deep'
# a varredura dos gatilhos: A LEI PURA 1.0-108 (ler a tabela DIRETAMENTE
# e alternar TODO *enabled FORA da allowlist — GP12/GP13/SWUS/SWDS/XHC*/
# PTXH e qualquer nome novo; a lista FIXA de família de era morreu com
# os fora-da-lista acordados; o PS2K ausente do hardware é pulo, nunca
# erro — a MESMA allowlist universal do craft-wake-guard e do doctor):
file_has "acpi: a allowlist universal é a MÃO do dono (PWRB/SLPB/PBTN/PS2K/LID)" "$AIROOTFS/usr/local/bin/elite-acpi-wakeup" 'MANTEM="PWRB SLPB PBTN PS2K LID"'
file_hasnt "acpi: a fila FIXA de família de era não volta (a lei PURA cobre TODO nome novo)" "$AIROOTFS/usr/local/bin/elite-acpi-wakeup" 'GPP0 GPP8 XHC0 XHC1 XHCI PTXH'
file_has "acpi: o TOGGLE só escreve quem está fora da lei (idempotente por desenho)" "$AIROOTFS/usr/local/bin/elite-acpi-wakeup" 'printf '
file_has "wake-guard: a MESMA allowlist universal (uma lei só na casa)" "$AIROOTFS/usr/local/bin/craft-wake-guard" 'MANTEM_ALLOW="PWRB SLPB PBTN PS2K LID"'
file_has "wake-guard: a lei PURA na tabela (todo *enabled fora da allowlist dorme)" "$AIROOTFS/usr/local/bin/craft-wake-guard" 'fora da mão do dono'
file_has "acpi: a unit nasce DEPOIS do wake-guard (a política do teclado vence)" "$AIROOTFS/etc/systemd/system/elite-acpi-wakeup.service" 'After=elite-wake-guard.service'
file_exists "acpi: o wants do multi-user liga a varredura no primeiro boot" "$AIROOTFS/etc/systemd/system/multi-user.target.wants/elite-acpi-wakeup.service"
file_has "acpi: a varredura habilitada na dose (enable idempotente do post-upgrade)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'elite-acpi-wakeup.service'
# o sono NO TEMPO CONFIGURADO (o relógio rearma com o QUE FALTA):
file_has "idle: o relógio rearma com o QUE FALTA (o sono aos SUSPEND_MIN de ociosidade)" "crates/elite-daemon/src/idle.rs" 'pub fn faltam_ms'
file_has "idle: o tipo-2 (o sono) armado com o resto do relógio" "crates/elite-daemon/src/wayland.rs" 'faltam_ms(conf.suspend_min, conf.lock_min)'
file_has "idle: o tipo-1 (o apagar) armado com o resto do relógio" "crates/elite-daemon/src/wayland.rs" 'faltam_ms(conf.off_min, conf.lock_min)'
file_has "vigil: o olho do journal cobre o InhibitDelayMaxSec da casa (8 sondagens)" "$AIROOTFS/usr/local/bin/craft-vigil" '_esp" -le 8'
file_hasnt "vigil: o verbo MORTO craft-idle screenon não volta (caía no cycle dos presets)" "$AIROOTFS/usr/local/bin/craft-vigil" 'craft-idle screenon'
# a recuperação de vídeo DINÂMICA (o DP sem sinal do pós-resume/pós-unlock):
file_has "display: o recover é verbo da casa (a rede do DP sem sinal)" "$AIROOTFS/usr/local/bin/craft-display" '    recover) do_recover; exit 0 ;;'
file_has "display: a varredura DAS saídas é DINÂMICA (nada hardcoded — DP-*/HDMI-*/eDP-*)" "$AIROOTFS/usr/local/bin/craft-display" 'todas_saidas()'
file_has "display: o modo do recover vem do displays.conf persistido" "$AIROOTFS/usr/local/bin/craft-display" 'modo_do_conf()'
file_has "display: o guard de 10s do recover (um dono por veredito entre as redes)" "$AIROOTFS/usr/local/bin/craft-display" 'display-recover-guard'
file_has "display: a pausa de estabilização do ciclo (a constante da casa)" "$AIROOTFS/usr/local/bin/craft-display" 'off→1s→on --mode'
file_has "lock: o pós-unlock dispara o recover (a rede da imagem na porta da senha)" "$AIROOTFS/usr/local/bin/craft-lock" 'craft-display recover'
file_has "vigil: a volta do sono dispara o recover (a rede de imagem)" "$AIROOTFS/usr/local/bin/craft-vigil" 'craft-display recover'
file_has "hook: o resume-display dispara o recover por usuário (com o modo salvo)" "elite/airootfs/usr/lib/systemd/system-sleep/elite-resume-display" 'craft-display recover'
file_has "daemon: o despertar dispara o recover (PrepareForSleep(false)/Unlock)" "crates/elite-daemon/src/main.rs" '"recover"]'
# o áudio pós-resume sem o fone BT (o HDMI do monitor nunca fica mudo):
file_has "audio: o juízo do resume é PURO (o BT morto no sono não deixa o HDMI)" "crates/elite-daemon/src/audio.rs" 'pub fn julga_resume'
file_has "audio: o auto_null preso NÃO reafirma o HDMI do monitor (a lei E140)" "crates/elite-daemon/src/audio.rs" 'pub fn julga_autonull'
# a vigília armada DE VERDADE (o notifier atravessa o spawn):
file_has "idle: o notifier atravessa o spawn (a vigília nasce armada)" "crates/elite-daemon/src/wayland.rs" 'IDLE_CTL'
file_has "idle: o APAGAR é tempo próprio (a fábrica 5/10 no daemon)" "crates/elite-daemon/src/idle.rs" 'off_min'
# o wallpaper é vaga da sessão (UM lançador — a lei E137):
file_has "wallpaper: o swaybg é vaga supervisionada da sessão" "crates/elite-daemon/src/supervise.rs" 'swaybg -m fill'
file_hasnt "autostart: NENHUM spawn/comentário de era (o waybar morreu)" "elite/airootfs/etc/skel/.config/labwc/autostart" 'waybar'
file_hasnt "autostart: o craft-bars de era não volta nem em comentário" "elite/airootfs/etc/skel/.config/labwc/autostart" 'craft-bars'

# ══ 1.0-102 — O CICLO DE VIDA DO RELOGIN (audit 102 + dump 094140) ══
# o Broken pipe do fio Wayland não pode mais deixar o dono vivo no lock:
file_has "daemon: o fim_da_sessao desce a casa no EPIPE/EOF do compositor" "crates/elite-daemon/src/main.rs" 'fn fim_da_sessao'
file_has "daemon: o fio Wayland chama o fim da sessão no erro do dispatch" "crates/elite-daemon/src/wayland.rs" 'fim_da_sessao'
# o julgamento do órfão pela IDENTIDADE da sessão (o wayland-0 de mesmo
# nome não mente mais):
file_has "daemon: o relogin julga o órfão pela identidade (XDG_SESSION_ID)" "crates/elite-daemon/src/supervise.rs" 'julga_orfao_relogin'
file_has "daemon: o lock do órfão teimoso é assumido na hora" "crates/elite-daemon/src/supervise.rs" 'ASSUME'
# 1.0-104 — O PROBE LÊ O LOCK VIVO (o SUPERVISOR_LOCK reflete o
# session.lock do elite-daemon — o bars.lock fóssil nunca mais mente):
file_has "probe: o SUPERVISOR_LOCK julga pelo session.lock do elite-daemon" "elite/airootfs/usr/local/bin/elite-session-probe" 'elite/session.lock'
# o heal ganha o juízo do FÓSSIL DE SPAWN (o corpo congelado de dose
# antiga com residente de era nascendo é reconstruído do mestre):
# a DOCK ATÔMICA (a duplicação transitória do pin morre no mesmo ciclo):
file_has "dock: a reconciliação do rebuild_pins (pin · dinâmico · indicador no MESMO ciclo)" "crates/craft-dock-rs/src/ui.rs" 'fn rebuild_pins'
file_has "dock: os dinâmicos resolvem pelos app_ids das JANELAS (a régua unificada)" "crates/craft-dock-rs/src/ui.rs" 'fn sync_dynamic'
# a gaveta desce com o palco (o overlay nunca fica por cima da casa):
file_has "gaveta: o daemon desce o nwg-drawer quando outra janela ganha foco" "crates/elite-daemon/src/wayland.rs" 'gaveta_desce'
file_has "gaveta: o sinal do daemon colhe o drawer do uid" "crates/elite-daemon/src/main.rs" 'pub(crate) fn gaveta_desce'
# o seletor nunca vira zumbi (~24 MB): perdeu o foco = exit imediato
file_has "pick: o notify::is-active desce o seletor quando o palco é de outro (1.0-107 — zero zumbi)" "crates/craft-tools/src/bin/craft-pick.rs" 'is-active'
file_has "pick: o NON_UNIQUE destrava o 2º menu (a instância única matava o pedido novo)" "crates/craft-tools/src/bin/craft-pick.rs" 'NON_UNIQUE'
# 1.0-108 — A EVIDÊNCIA DO RIG 1.0-107.3: `craft-pick -T "Teste"` morreu
# com "opção -T desconhecida" no binário de ERA e deixou 22 processos
# presos (~530 MB) — o parser agora aceita as QUATRO formas e a flag
# inválida é exit 2 ANTES do GTK (zero processo vivo), e o FALSE do
# primeiro frame do labwc (o GTK4 dispara is-active=false antes de
# ativar a janela) não mata mais o menu dos chamadores:
file_has "pick: as QUATRO formas do título (-T T · -TT · --title T · --title=T)" "crates/craft-tools/src/lib.rs" '-TTÍTULO'
file_has "pick: a flag inválida é ERRO NOMEADO (nunca item fantasma do zumbi)" "crates/craft-tools/src/lib.rs" 'opção desconhecida'
file_has "pick: o exit 2 fecha a porta ANTES de qualquer GTK (o juiz antes do init — a saída única colhe o pidfile)" "crates/craft-tools/src/bin/craft-pick.rs" 'sai(2)'
file_has "pick: a guarda de foco do labwc (ja_teve_foco — o primeiro frame é cortesia)" "crates/craft-tools/src/bin/craft-pick.rs" 'ja_teve_foco'
file_has "pick: a carência inicial de 300ms após o present() (o frame 0..1 do compositor)" "crates/craft-tools/src/bin/craft-pick.rs" 'from_millis(300)'
# 1.0-109 — A EVIDÊNCIA DO DUMP 1.0-108: 24 craft-pick presos em
# background e NENHUM menu na tela do labwc (o GtkApplicationWindow
# comum não recebe sobreposição nem foco) — o pick veste A CAMADA (a
# diretriz, palavra por palavra) e a instância única veste o toggle:
file_has "pick: a janela veste o gtk4-layer-shell (a cura dos 24 pick invisíveis)" "crates/craft-tools/src/lib.rs" 'init_layer_shell'
file_has "pick: a camada é a de SOBREPOSIÇÃO (acima de qualquer janela — a gramática do calendário)" "crates/craft-tools/src/lib.rs" 'Layer::Overlay'
file_has "pick: o teclado é EXCLUSIVO da superfície (Escape/setas/Enter direto)" "crates/craft-tools/src/lib.rs" 'KeyboardMode::Exclusive'
file_has "pick: o namespace da camada é o da casa" "crates/craft-tools/src/lib.rs" 'set_namespace(Some(namespace))'
file_has "pick: a janela-base pede a camada com o namespace próprio" "crates/craft-tools/src/bin/craft-pick.rs" 'janela_camada(app, "pickwin", titulo, "craft-pick")'
file_has "pick: o gtk4-layer-shell é dependência da gui (o par provado da bar/dock)" "crates/craft-tools/Cargo.toml" 'gtk4-layer-shell'
file_has "pick: o pidfile da instância única mora no XDG_RUNTIME_DIR/elite (a diretriz)" "crates/craft-tools/src/bin/craft-pick.rs" 'craft-pick.pid'
file_has "pick: o MESMO título vivo é toggle (fecha o velho e sai limpo)" "crates/craft-tools/src/lib.rs" 'InstanciaPick::Toggle'
file_has "pick: OUTRO menu vivo é substituição na hora" "crates/craft-tools/src/lib.rs" 'InstanciaPick::Substitui'
file_has "pick: a saída única colhe o pidfile do dono (nenhum invisível captura ponteiro)" "crates/craft-tools/src/bin/craft-pick.rs" 'fn sai(codigo: i32)'
# 1.0-109 — OS ARGUMENTOS SÃO DA CASA, NÃO DO GLIB (a descoberta da
# prova executiva local: o app.run() de era passava o argv inteiro ao
# g_application_run e o parser do GLib RECUSAVA o '-T' ("Unknown
# option -T" — o menu morria na porta do GTK); o parser da casa já
# consumiu tudo — ao GLib sobra SOMENTE a palavra do processo):
file_has "pick: o argv NUNCA vai ao parser do GLIB (o -T é da casa)" "crates/craft-tools/src/bin/craft-pick.rs" 'run_with_args::<&str>(&[])'
file_has "net: o argv NUNCA vai ao parser do GLIB (palavra torta não mata o seletor)" "crates/craft-tools/src/bin/craft-net.rs" 'run_with_args::<&str>(&[])'
# o ESC sai LIMPO (exit 0 — a diretriz da instância única): os
# chamadores julgam pelo CONTEÚDO (vazio = cancelado benigno)
file_has "rollback: a descrição vazia é cancelamento benigno (o juízo é o conteúdo)" "$AIROOTFS/usr/local/bin/craft-rollback" 'descrição vazia/cancelada'
file_has "game: a escolha vazia é o cancelamento benigno (nenhum despacho corre)" "$AIROOTFS/usr/local/bin/craft-game" 'fechado sem escolha'
# as flags reais do craft-pick --help (a cura do 'Opção --title=... desconhecida'
# — 1.0-105: a forma do foot -T com espaço é a bandeira da casa):
file_has "pick: o craft-idle sonda o --help antes do -T (a flag de era não mata o painel)" "$AIROOTFS/usr/local/bin/craft-idle" 'craft-pick --help'
file_has "pick: o craft-game sonda o --help antes do -T (idem)" "$AIROOTFS/usr/local/bin/craft-game" 'craft-pick --help'
# E106/2 — o pick calado no stderr (os avisos de portal do GTK não mancham
# a sessão nativa; o contrato 0/1 do exit code segue INTACTO — o juiz é
# o rc, nunca o eco)
file_has "game: o pick do jogo desce calado no stderr (contrato 0/1 intacto)" "$AIROOTFS/usr/local/bin/craft-game" 'craft-pick -T "$1" 2>/dev/null'
file_has "idle: o pick da trava desce calado no stderr (idem)" "$AIROOTFS/usr/local/bin/craft-idle" 'craft-pick -T "$1" 2>/dev/null'
# E106/2 — o DND morreu por ordem do dono: o corpo do jogo NÃO toca na
# central de notificações (o 'manual: ON/OFF' do papel vem ANTES do fio
# do pill roxo — o estado nunca fica devendo a porta estranha nenhuma)
file_hasnt "game: o swaync-client MORREU do corpo do jogo (o DND de era não volta)" "$AIROOTFS/usr/local/bin/craft-game" 'swaync-client'
file_hasnt "game: a lembrança do DND não volta nem em comentário" "$AIROOTFS/usr/local/bin/craft-game" 'game-dnd-antes'
file_has "game: o estado manual assinado ANTES do fio do pill (bus_notifica depois do glog)" "$AIROOTFS/usr/local/bin/craft-game" 'glog "manual: ON'
# E106/2 — a lista do seletor veste a pele escura de verdade: o botão do
# item ganha hover/ativo escuros e o nó REAL do GtkListBox veste as
# linhas (o listview de era casava com NADA — o fundo claro do tema
# externo era o réu da lista branca do rig)
file_has "css: o item do seletor veste o hover escuro (R3 no botão da lista)" "crates/elite-core/assets/theme.css" '#pickwin button:hover'
file_has "css: a lista do seletor veste o nó real do ListBox (o listview de era casava com nada)" "crates/elite-core/assets/theme.css" '#pickwin list row:hover'
# as pausas do foot -e (o terminal do menu não some com o veredito):
file_has "terminal: o craft-help pausa no Enter (o mapa não some)" "crates/craft-tools/src/bin/craft-help.rs" 'Pressione Enter para fechar'
file_has "terminal: o craft-update pausa no Enter (o veredito não some)" "crates/craft-tools/src/bin/craft-update.rs" 'Pressione Enter para fechar'
# o cancelamento do pkexec é silêncio (o 126 não é erro):
file_has "pkexec: o rc 126 (senha cancelada) sai calado (o toast de era morreu)" "$AIROOTFS/usr/local/bin/elite-gparted" 'ne 126'
# o greeter REAL no rig (cmp manda, sem trava de SHA único) + o cursor:
file_has "greeter: o juízo é POR CONTEÚDO (cmp — o SHA único morreu)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'cmp -s "$_GREET_SRC" "$_GREET_DST"'
file_has "greeter: o kde_settings.conf do Bibata viaja no pacote" "$BS" '/usr/local/share/elite/sddm/kde_settings.conf'
file_has "greeter: a dose entrega o cursor no /etc/sddm.conf.d (preservando o papel do dono)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" '/etc/sddm.conf.d/kde_settings.conf'
# O TEMA GRUB DA CASA (a pele roxa no boot — ISO, install e dose; o git
# TEXT-ONLY: o wallpaper bebe do skel e a barra viaja em base64):
file_exists "grub: o theme.txt da casa existe no overlay" "elite/airootfs/usr/share/grub/themes/archcraft/theme.txt"
file_exists "grub: a barra de seleção viaja em base64 (o git text-only)" "elite/airootfs/usr/share/grub/themes/archcraft/select_bar.png.b64"
file_has "grub: o tema veste o wallpaper da casa e a barra #a855f7" "elite/airootfs/usr/share/grub/themes/archcraft/theme.txt" 'selected_item_pixmap_style = "select_bar.png"'
file_has "grub: a ISO decodifica a barra e bebe o wallpaper do skel" "scripts/apply-overlay.sh" 'base64 -d'
file_has "grub: a ISO materializa o tema no rootfs do live (unpackfs carrega)" "scripts/apply-overlay.sh" '$PROFILE/airootfs/usr/share/grub/themes/archcraft'
file_has "grub: o GRUB_DISTRIBUTOR da casa (os títulos batizados)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'GRUB_DISTRIBUTOR="Archcraft ELITE"'
file_has "grub: o install-stage crava GRUB_THEME+DISTRIBUTOR no primeiro menu" "$AIROOTFS/usr/local/bin/elite-install-stage" 'GRUB_THEME='
file_has "grub: o mestre do tema viaja no pacote (elite/grub)" "$BS" '/usr/local/share/elite/grub/theme.txt'
file_has "grub: o pacote bebe o wallpaper do skel (UMA fonte binária)" "$BS" '/work/elite/airootfs/etc/skel/.config/labwc/wallpaper.png'
file_has "grub: a ISO injeta o tema no menu de boot (apply-overlay)" "scripts/apply-overlay.sh" 'themes/archcraft/theme.txt'
file_has "grub: a dose entrega em /usr/share E /boot/grub/themes" "$AIROOTFS/usr/local/bin/elite-post-upgrade" '/boot/grub/themes/archcraft'
# O DUMP SISTÊMICO (a ordem do dono: todos os subsistemas no papel curto):
file_has "dump: o consumo GLOBAL (free -m parseado nos 6 campos)" "crates/craft-dump-rs/src/lib.rs" 'pub fn parse_free_m'
file_has "dump: o zramctl vivo no papel" "crates/craft-dump-rs/src/main.rs" 'zramctl'
file_has "dump: o top RSS ranqueado (rank_rss puro)" "crates/craft-dump-rs/src/lib.rs" 'pub fn rank_rss'
file_has "dump: o top RSS do sistema E da interface no papel" "crates/craft-dump-rs/src/main.rs" 'top RSS'
file_has "dump: timers e unidades failed do systemd" "crates/craft-dump-rs/src/main.rs" 'list-timers'
file_has "dump: o total de pacotes (instalados/explícitos/locais)" "crates/craft-dump-rs/src/main.rs" 'pacotes:'
file_has "dump: o veredito da persistência do monitor (displays.conf × wlr-randr)" "crates/craft-dump-rs/src/lib.rs" 'pub fn veredito_display'
file_has "dump: os sockets do XDG_RUNTIME_DIR com o tipo" "crates/craft-dump-rs/src/lib.rs" 'pub fn linhas_runtime_dir'
file_has "dump: a ENTRADA de áudio (default source) no papel" "crates/craft-dump-rs/src/lib.rs" 'pub fn pactl_default_source'
file_has "dump: os três tempos da vigília no papel" "crates/craft-dump-rs/src/lib.rs" 'pub fn idle_conf_tres'
file_has "dump: o wake-guard audita a política de despertar" "crates/craft-dump-rs/src/main.rs" 'craft-wake-guard'
file_has "dump: o veredito de XML no papel CURTO (não só no --full)" "crates/craft-dump-rs/src/main.rs" 'XML da sessão'
# as últimas falhas do journal com as unidades failed nomeadas:
file_has "dump: as unidades failed nomeadas antes do journal" "crates/craft-dump-rs/src/main.rs" '--failed'

# ══ E151 — A ONDA FINAL 2/2: A IDENTIDADE OBSIDIANA DA UI ══
# UMA superfície escura entre barra e dock (a ordem do dono), a barra
# 28px, Áudio e Microfone separados, foco de tema morto e calendário
# legível:
file_has "css: a barra veste a obsidiana #0d0d12 (a ilha do dono)" "crates/elite-core/assets/theme.css" 'rgba(13, 13, 18'
file_has "css: a dock veste a MESMA obsidiana da barra (1.0-104 — os tokens alinhados)" "crates/elite-core/assets/theme.css" 'background: @elite-bg;'
file_has "css: a borda interna de luz da dock (1px rgba(255,255,255,0.12) — ícones escuros não somem)" "crates/elite-core/assets/theme.css" 'rgba(255, 255, 255, 0.12)'
file_has "css: a borda sutil mauve rgba(203, 166, 247, 0.16)" "crates/elite-core/assets/theme.css" 'rgba(203, 166, 247, 0.16)'
file_has "css: o MenuButton de energia fica SOLTO (background-image none no :checked)" "crates/elite-core/assets/theme.css" 'background-image: none'
file_has "css: o cabeçalho do calendário veste o #f8fafc (mês e ano legíveis)" "crates/elite-core/assets/theme.css" 'calendar > header'
file_has "css: o relógio veste tabular-nums (os dígitos não dançam)" "crates/elite-core/assets/theme.css" 'font-variant-numeric: tabular-nums'
# ══ 1.0-107.3 — A AUDITORIA DE CSS MORTO (seletor a seletor: a E149
#    enterrou os popovers customizados e a folha seguiu vestindo fantasmas) ══
file_hasnt "css: os rótulos de popover da E147 mortos não voltam (nenhum label.title na folha)" "crates/elite-core/assets/theme.css" 'popover > contents label.title'
file_hasnt "css: os switches de popover mortos não voltam (o customizado morreu com a E149)" "crates/elite-core/assets/theme.css" 'popover > contents switch'
file_hasnt "css: o scale de popover morto não volta (o slider era da central de áudio)" "crates/elite-core/assets/theme.css" 'popover > contents scale'
file_hasnt "css: o headerbar do pick morto não volta (a janela é ApplicationWindow nua)" "crates/elite-core/assets/theme.css" '#pickwin headerbar'
file_hasnt "css: o button.destructive de era não volta (sem consumidor na árvore)" "crates/elite-core/assets/theme.css" 'button.destructive'
file_hasnt "swaync: a grade de botões morta não volta (o config veste title/dnd/notifications)" "elite/airootfs/etc/skel/.config/swaync/style.css" '.widget-buttons-grid'
file_has "bar: a faixa é 28px (a proporção obsidiana do dono)" "crates/craft-bar-rs/src/ui.rs" 'const ALTURA: i32 = 28'
file_has "bar: o microfone é ASSENTO PRÓPRIO (o fim do clique do meio escondido)" "crates/craft-bar-rs/src/ui.rs" 'set_widget_name("micbtn")'
file_has "bar: o ícone do mudo do MIC é o próprio do microfone" "crates/craft-bar-rs/src/state.rs" 'microphone-sensitivity-muted-symbolic'
file_has "bar: o foco do tema morre nos botões (focus_on_click false)" "crates/craft-bar-rs/src/ui.rs" 'set_focus_on_click(false)'
file_has "bar: a pálida do foco corre na árvore pronta (apaga_foco_da_barra)" "crates/craft-bar-rs/src/ui.rs" 'apaga_foco_da_barra'
# o relógio de era do painel morreu com a central (1.0-106): o clique
# abre o CALENDÁRIO NATIVO (a âncora mora no bloco 1.0-106 acima)
file_has "skel: a pele da barra é a MESTRA NO BINÁRIO (o override SOMA — 1.0-104)" "elite/airootfs/etc/skel/.config/elite/bar.css" 'SOMA POR BAIXO do cascade'
file_has "skel: a pele da dock é a MESTRA NO BINÁRIO (o override SOMA — 1.0-104)" "elite/airootfs/etc/skel/.config/elite/dock.css" 'SOMA POR BAIXO do cascade'
file_has "post-upgrade: a pele de fábrica 1.0-98 sai do home (a E151 veste embaixo)" "elite/airootfs/usr/local/bin/elite-post-upgrade" 'elite/bar.css:rgba(17, 17, 27, 0.96'
file_has "dock: o flush ÚNICO da superfície (todo evento comita no frame)" "crates/craft-dock-rs/src/ui.rs" 'fn flush_superficie'
file_has "dock: o dreno comita o flush em TODA rodada (flags não esperam outra ação)" "crates/craft-dock-rs/src/ui.rs" 'recalcula_superficie(st);'
file_hasnt "dock: o clique do MEIO não encerra (o Fechar mora no menu completo)" "crates/craft-dock-rs/src/ui.rs" '2 => on_middle'

# ══ E151-c — O DEBLOAT EXTREMO NA ÁRVORE (o greeter wayland, o polkit
# ÚNICO, o automount sem daemon e o motor da dose ágil) ══
file_exists "sddm: o drop-in wayland da casa existe no overlay" "$AIROOTFS/etc/sddm.conf.d/elite_wayland.conf"
file_has "sddm: o DisplayServer é WAYLAND (o fim do Xorg ocioso)" "$AIROOTFS/etc/sddm.conf.d/elite_wayland.conf" 'DisplayServer=wayland'
file_has "sddm: o compositor do greeter é o LABWC (zero pacote novo)" "$AIROOTFS/etc/sddm.conf.d/elite_wayland.conf" 'CompositorCommand=labwc'
file_has "post-upgrade: o drop-in wayland só desce com o labwc no disco (a rede anti-tela-preta)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" '/usr/bin/labwc'
# 1.0-108 — O AUTOMOUNT VOLTOU AO ARRANQUE LIMPO (a reversão da E151 pela
# diretriz do dono: o udiskie --automount --notify --no-tray é alicoe de
# frame 0; o par udev oneshot de era APOSENTOU — um dono por domínio, a
# colheita dos fósseis na dose com voz)
file_absent "automount: a regra udev 91 de era APOSENTOU (o udiskie é o dono)" "$AIROOTFS/usr/lib/udev/rules.d/91-elite-automount.rules"
file_absent "automount: a unit oneshot de era APOSENTOU" "$AIROOTFS/etc/systemd/system/elite-automount@.service"
file_absent "automount: o helper elite-automount de era APOSENTOU (nada de fóssil na árvore)" "$AIROOTFS/usr/local/bin/elite-automount"
file_has "post-upgrade: os fósseis do par udev de era COLHIDOS na dose (com voz)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'fóssil de era $_fossil_automount'
file_has "post-upgrade: o udiskie FORA da lista de debloat (o automounter da casa)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'for _deb in waybar gpsd; do'
file_has "daemon: o udiskie segue FORA da fila do supervisor (o autostart é o dono)" "crates/elite-daemon/src/supervise.rs" 'RESIDENTES_DEFAULT'
file_hasnt "daemon: o residente udiskie não volta à fila (o arranque limpo é o dono)" "crates/elite-daemon/src/supervise.rs" '("udiskie",'
file_has "daemon: a mordaca do autostart duplicado do agente (Hidden=true por usuário)" "crates/elite-daemon/src/supervise.rs" 'entrega_mordaca_polkit'
file_has "skel: o supressor XDG do agente duplicado nasce na casa" "$AIROOTFS/etc/skel/.config/autostart/lxqt-policykit-agent.desktop" 'Hidden=true'
# 1.0-108 — O AGENTE POLKIT É DO ARRANQUE (a vaga do daemon morreu — o
# frame 0 não depende do motor; o daemon só entrega a mordaca)
file_hasnt "daemon: a VAGA policykit morreu (o agente é do autostart — o guard pgrep manda)" "crates/elite-daemon/src/supervise.rs" 'nome: "policykit".to_string()'
file_has "daemon: o swayosd veste o --style do $HOME (o COULD NOT FIND CSS FILE! morre)" "crates/elite-daemon/src/supervise.rs" 'swayosd-server --style'
file_has "daemon: o teto ignora a vaga ADOTADA (a cura do spin de 95,6% de CPU)" "crates/elite-daemon/src/supervise.rs" '|| v.adotada'
file_has "bus: o atendente lê por POLL, nunca timeout de leitura no meio do quadro" "crates/elite-core/src/bus.rs" 'poll(pfd.as_mut_ptr(), 1, 500)'
file_has "bus: o fio envenenado morre LIMPO (shutdown no erro de escrita)" "crates/elite-core/src/bus.rs" 'w.shutdown(std::net::Shutdown::Both)'
file_has "daemon: o fd morto sai do poll e do chão (POLLERR/POLLHUP/POLLNVAL)" "crates/elite-daemon/src/main.rs" 'POLLERR | libc::POLLHUP | libc::POLLNVAL'
# 1.0-109 — O DOCTOR HONESTO PARA O DESKTOP AM4 (a evidência do dump: o
# falso positivo em `wakeup` — o botão físico de ligar é ACPI Fixed
# Hardware e o /proc/acpi/wakeup fica SEM *enabled com os espúrios
# desligados) e o AMBIENTE pela canônica da diretriz (systemctl
# primeiro, propriedade D-Bus de queda):
file_has "doctor: o ambiente valida via systemctl --user show-environment (a canônica da diretriz)" "crates/elite-daemon/src/doctor.rs" '"--user", "show-environment"'
file_has "doctor: a PROPRIEDADE Environment do D-Bus é a QUEDA (não mais a frente)" "crates/elite-daemon/src/doctor.rs" 'or_else(|_| ambiente_do_dbus(c))'
file_has "doctor: a saúde do despertar aceita o botão do KERNEL (o ACPI Fixed Hardware do AM4)" "crates/elite-daemon/src/doctor.rs" 'pub fn wakeup_saudavel'
file_has "doctor: o driver do botão mora em /sys/bus/acpi/drivers/button (o caminho do kernel)" "crates/elite-daemon/src/doctor.rs" '"/sys/bus/acpi/drivers/button"'
file_has "doctor: o botão de hardware fixo também mora em /proc/acpi/button/power" "crates/elite-daemon/src/doctor.rs" '"/proc/acpi/button/power"'
file_has "polkit: a regra 49-elite.rules autoriza OS MOTORES da casa sem senha" "$AIROOTFS/etc/polkit-1/rules.d/49-elite.rules" 'elite-acpi-wakeup'
file_has "polkit: a regra casa pelo lookup EXATO do programa (sem wildcard)" "$AIROOTFS/etc/polkit-1/rules.d/49-elite.rules" 'action.lookup("program")'
file_has "polkit: o wheel ATIVO é o juiz" "$AIROOTFS/etc/polkit-1/rules.d/49-elite.rules" 'subject.isInGroup("wheel") && subject.active'
file_absent "polkit: a regra 50-elite-wheel de era saiu da árvore (um dono por regra)" "$AIROOTFS/etc/polkit-1/rules.d/50-elite-wheel.rules"
file_has "qt: o QT_QPA_PLATFORMTHEME veste o qt6ct (o Oxygen de fallback morre)" "$AIROOTFS/etc/skel/.config/labwc/environment" 'QT_QPA_PLATFORMTHEME=qt6ct'
file_has "qt: o esquema ESCURO da casa viaja no pacote (custom_palette + scheme)" "$AIROOTFS/usr/local/share/elite/qt6ct/qt6ct.conf" 'color_scheme_path=/usr/local/share/elite/qt6ct/elite-dark.conf'
file_exists "qt: o esquema elite-dark.conf existe (a paleta Catppuccin-Mocha do Qt)" "$AIROOTFS/usr/local/share/elite/qt6ct/elite-dark.conf"
file_has "update: a GUARDA do pkexec órfão veste o craft-update (HUP/INT/TERM)" "crates/craft-tools/src/lib.rs" 'pub fn corre_com_guarda'
file_has "heal: a linha 178 curada (_sb_vistas nasce vazio — set -u nunca aborta)" "$AIROOTFS/usr/local/bin/elite-heal-sessao" '_sb_vistas=""'
file_has "heal: o fóssil de spawn veste a lei 1.0-108 (swaybg/udiskie são alicerces; swaync NÃO)" "$AIROOTFS/usr/local/bin/elite-heal-sessao" 'swayosd|swaync|swaync-client'
file_has "post-upgrade: o _sh/_suid nascem na PORTA do loop (o aborto de era morre)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" '_sh="$_hdir"'
file_has "post-upgrade: o ZERO-TOUCH devolve o cache/config ao dono (chown -R uid:gid)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'chown -R "$_auid:$_agid"'
file_has "clean: o papel podado herda o dono do original (chown --reference)" "$AIROOTFS/usr/local/bin/elite-clean" 'herda_dono'
file_has "io: o escalonador do NVMe é none (a revisão de hardware E151)" "$AIROOTFS/etc/udev/rules.d/99-elite-io.rules" 'ATTR{queue/scheduler}="none"'
file_has "io: o SSD SATA veste mq-deadline (o HDD não é tocado)" "$AIROOTFS/etc/udev/rules.d/99-elite-io.rules" 'mq-deadline'
file_has "gtk: os botões de janela nascem À DIREITA (a lei da casa no GTK3)" "$AIROOTFS/etc/skel/.config/gtk-3.0/settings.ini" 'gtk-decoration-layout=:minimize,maximize,close'
file_has "gtk: os botões de janela nascem À DIREITA (idem GTK4)" "$AIROOTFS/etc/skel/.config/gtk-4.0/settings.ini" 'gtk-decoration-layout=:minimize,maximize,close'
file_has "dose: o pacman_agil sobe para 10 downloads paralelos (o -Syu ágil E151)" "$AIROOTFS/usr/local/bin/elite-dose" 'ParallelDownloads = 10'
file_has "dose: a limpeza do cache antigo após a dose (paccache -rk1)" "$AIROOTFS/usr/local/bin/elite-dose" 'cache_enxuga'
file_has "iso: o NoExtract poda doc/man/gtk-doc na ISO (o apply-overlay)" "scripts/apply-overlay.sh" 'usr/share/doc/*'
file_has "iso: a compressão da ISO é zstd alto (o profiledef)" "scripts/apply-overlay.sh" 'COMPRESSION="zstd"'
# ══ 1.0-107.2 — A AUDITORIA DA ESTEIRA (o canal testing × stable, o cache
#    máximo do cargo e a promessa E103.1 vestida de verdade) ══
file_has "iso: a compressão CALIBRADA -15 -T0 -b 512K (1.0-107.1 — o -19 pagava CPU máxima pelos últimos 2%)" "scripts/apply-overlay.sh" 'COMPRESSION_OPTIONS=(-15 -T0 -b 512K)'
file_has "canal: o gatilho do Canal veste o main DE VERDADE (a promessa E103.1 — o typo 'ain]' da E43 nunca casava nada e o GitHub ignorava o filtro inválido)" ".github/workflows/publish-packages.yml" 'branches: [main]'
file_has "canal: o cache MÁXIMO do cargo (target + registry/git juntos, chave por Cargo.lock)" ".github/workflows/publish-packages.yml" 'crates/.cargo-home'
file_has "suite: o cache máximo no host (o registry do runner entra no MESMO cache)" ".github/workflows/tests.yml" '~/.cargo/registry'
file_has "build.sh: o CARGO_HOME do container (o registry/git moram no repo montado — o download das crates paga 1x)" ".ci/build.sh" 'CARGO_HOME="/work/crates/.cargo-home"'
file_has "lock: o blur é CACHE por evento (wall-blur.png — zero blur por lock)" "$AIROOTFS/usr/local/bin/craft-lock" 'wall-blur.png'
# 1.0-108 — O MAPEAMENTO INSTANTÂNEO SEM PISCADA PRETA (a evidência do rig
# 1.0-107.3: o lock nascia com uma piscada preta — o fade-in de era cobria
# o primeiro frame antes do wallpaper):
# 1.0-109 — A AUDITORIA DAS FLAGS REAIS (a evidência do dump 1.0-108:
# o idle.log registrou 'lock não nasceu em 15s — réu: o lock não mapeou'
# porque o --immediate de 1.0-108 virou INTEIRO deprecated no hyprlock
# novo (sem valor o parser morre) e o no_fade_in SAIU das chaves válidas
# — o juiz agora é o --help do PRÓPRIO binário instalado):
file_has "lock: o juiz das flags é o --help do PRÓPRIO binário instalado" "$AIROOTFS/usr/local/bin/craft-lock" 'hyprlock_flags()'
file_has "lock: o --no-fade-in só nasce quando o binário o conhece" "$AIROOTFS/usr/local/bin/craft-lock" 'case "$_ajuda" in *--no-fade-in*) HYPRFLAGS+=(--no-fade-in) ;; esac'
file_has "lock: o --grace 0 das versões novas com a queda honesta para o --immediate bool de era" "$AIROOTFS/usr/local/bin/craft-lock" '*--grace*) HYPRFLAGS+=(--grace 0)'
file_has "lock: os DOIS caminhos vestem as flags auditadas" "$AIROOTFS/usr/local/bin/craft-lock" 'hyprlock "${HYPRFLAGS[@]}" -c "$conf" 9>&-'
file_hasnt "lock: NENHUMA flag de era hard-coded (o réu do 'não mapeou' morre)" "$AIROOTFS/usr/local/bin/craft-lock" 'hyprlock --immediate'
file_hasnt "lock: a chave no_fade_in SAIU do conf (inválida nas versões novas — o parser aborta)" "$AIROOTFS/etc/skel/.config/hypr/hyprlock.conf" 'no_fade_in ='
file_has "lock: o conf veste SÓ chaves válidas em toda a família (hide_cursor)" "$AIROOTFS/etc/skel/.config/hypr/hyprlock.conf" 'hide_cursor = true'
file_has "lock: o conf mestre veste fade_on_empty = false (o campo não pisca)" "$AIROOTFS/etc/skel/.config/hypr/hyprlock.conf" 'fade_on_empty = false'
# 1.0-109 — O CHÃO GARANTIDO: a regra polkit viaja COMO MESTRE no
# pacote e o cinto do elite-post-upgrade o entrega ao rig vivo (a
# evidência do dump: o 49-elite.rules AUSENTE no rig instalado) e o
# tema de ícones é o que a MÁQUINA garante (Adwaita — o Fallback Oxygen
# do lxqt-policykit-agent no dump morre):
file_has "build.sh: o mestre polkit viaja no pacote (o cinto do post-upgrade)" "$BS" '/usr/local/share/elite/polkit/49-elite.rules'
file_has "post-upgrade: o cinto entrega o 49-elite.rules (ausente nasce · divergente renova)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" '_PK49_SRC="/usr/local/share/elite/polkit/49-elite.rules"'
file_has "post-upgrade: o cinto entrega com mode 0644 (a gramática do polkit)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'install -m644 "$_PK49_SRC" "$_PK49_DST"'
file_has "gtk: o tema de ícones é o que a MÁQUINA garante (Adwaita no GTK3)" "$AIROOTFS/etc/skel/.config/gtk-3.0/settings.ini" 'gtk-icon-theme-name=Adwaita'
file_has "gtk: o tema de ícones é o que a MÁQUINA garante (Adwaita no GTK4)" "$AIROOTFS/etc/skel/.config/gtk-4.0/settings.ini" 'gtk-icon-theme-name=Adwaita'
file_has "heal: o ícone GARANTIDO veste a AUSÊNCIA no home (a escolha do dono vence)" "$AIROOTFS/usr/local/bin/elite-heal-sessao" 'cura_gtk'
file_has "heal: o guard do ícone só veste a linha AUSENTE (idempotente)" "$AIROOTFS/usr/local/bin/elite-heal-sessao" 'gtk-icon-theme-name='
# o craft-suspend espera o lock VIVO antes do freeze (a diretriz da dose):
file_has "suspend: o pgrep -x hyprlock confirma o lock ativo ANTES do systemctl suspend" "$AIROOTFS/usr/local/bin/craft-suspend" 'pgrep -x hyprlock'
file_has "lock: o cache STALE não segura o map (o ffmpeg renasce DESAPEGADO em setsid)" "$AIROOTFS/usr/local/bin/craft-lock" 'blur_fresco'
file_has "lock: o blur_passes=0 é LEI SEMPRE (nenhuma passada lenta antes do map)" "$AIROOTFS/usr/local/bin/craft-lock" 'blur_passes = 0|"'
file_has "bar: o Suspender do menu da barra veste o CRAFT-SUSPEND (lock mapeado antes do freeze)" "crates/craft-bar-rs/src/ui.rs" '("suspend", &["craft-suspend"][..])'
file_has "bar: o Encerrar do menu da barra veste o CRAFT-LOGOUT (a família cai em ordem)" "crates/craft-bar-rs/src/ui.rs" '("logout", &["craft-logout"][..])'
# 1.0-108 — O CRAFT-SUSPEND (a ordem do dono: a superfície do lock MAPEADA
# antes do systemctl suspend):
file_exists "suspend: o craft-suspend mora na casa" "$AIROOTFS/usr/local/bin/craft-suspend"
file_has "suspend: o ciclo espera o hyprlock VIVO (pgrep no /proc)" "$AIROOTFS/usr/local/bin/craft-suspend" 'pgrep -x hyprlock'
file_has "suspend: o assento de 400ms da superfície (a lei do lock_mapeado do daemon)" "$AIROOTFS/usr/local/bin/craft-suspend" 'sleep 0.4'
file_has "suspend: o teto honesto de 3s pela superfície" "$AIROOTFS/usr/local/bin/craft-suspend" 'lt 30'
file_has "suspend: o craft-idle veste o craft-suspend no Suspender agora" "$AIROOTFS/usr/local/bin/craft-idle" 'craft-suspend'
# 1.0-108 — O CRAFT-LOGOUT (o encerrar ORDEIRO: daemon → superfícies →
# agentes, o fóssil do chão varrido antes do labwc --exit):
file_exists "logout: o craft-logout mora na casa" "$AIROOTFS/usr/local/bin/craft-logout"
file_has "logout: o ORQUESTRADOR cai primeiro (quem respawnava a família)" "$AIROOTFS/usr/local/bin/craft-logout" 'encerra elite-daemon'
file_has "logout: as SUPERFÍCIES caem na ordem (barra e dock)" "$AIROOTFS/usr/local/bin/craft-logout" 'encerra craft-bar-rs craft-dock-rs'
file_has "logout: os AGENTES auxiliares caem no fim (central, OSD, polkit, automount, clipboard, wallpaper)" "$AIROOTFS/usr/local/bin/craft-logout" 'encerra swaync swayosd-server lxqt-policykit-agent udiskie cliphist wl-paste swaybg'
file_has "logout: o fóssil de /run é varrido ANTES do labwc --exit" "$AIROOTFS/usr/local/bin/craft-logout" 'exec labwc --exit'
file_hasnt "logout: o labwc --exit NU não volta ao menu da casa" "$AIROOTFS/etc/skel/.config/labwc/menu.xml" 'command="labwc --exit"'
# 1.0-108 — OS 120 Hz NO ARRANQUE (o craft-display apply NÃO-BLOQUEANTE na
# thread própria do arranque do elite-daemon session, sempre que houver
# perfil salvo — o do_apply reconcilia: sem conf = no-op silencioso):
file_has "display: o arranque do session re-aplica o perfil do monitor (a thread do boot frio)" "crates/elite-daemon/src/main.rs" 'fn thread_display_boot'
file_has "display: o apply da thread é o craft-display da casa (não-bloqueante na própria thread)" "crates/elite-daemon/src/main.rs" 'let ok = Command::new("/usr/local/bin/craft-display")'

# ══ E151-d — AS SKILLS PERMANENTES E A LEI DE ENTRADA ══
file_exists "skills: a filosofia extrema é guia permanente (05)" "docs/skills/05-filosofia-extrema.md"
file_exists "skills: a UI/UX obsidiana é guia permanente (06)" "docs/skills/06-ui-ux-gtk4-wayland.md"
file_has "skills: a LEI DE ENTRADA (ler docs/skills antes de editar)" "docs/skills/README.md" 'A LEI DE ENTRADA'
file_has "constituição: o §0 manda ler as skills antes de qualquer código" "AGENTS.md" '§0 · A LEITURA OBRIGATÓRIA DAS SKILLS'
file_has "skills 06: a superfície obsidiana ÚNICA documentada" "docs/skills/06-ui-ux-gtk4-wayland.md" 'rgba(13, 13, 18, 0.96)'
file_has "skills 05: o automount do arranque limpo nomeado na filosofia (1.0-108)" "docs/skills/05-filosofia-extrema.md" 'arranque limpo'
file_exists "ci: o workflow de manutenção mensal existe" ".github/workflows/maintenance.yml"
file_has "ci: o cron mensal é o dia 1 (a vigilância sem dedo do dono)" ".github/workflows/maintenance.yml" '0 7 1 *'
file_has "ci: o check das features completas contra o Arch do dia (a quebra upstream nomeada 1 mês antes)" ".github/workflows/maintenance.yml" 'cargo check --workspace --all-features --locked'

# ══ E106/5b — A CURA DO BOOT + O GREETER pt_BR DA CASA (o journal do rig:
#      coolercontrold/liqctld, o portal sem RealtimeKit, o sddm em inglês
#      sem cursor; snapper/grub-btrfsd só no btrfs; sensores da diretriz) ══
file_has "greeter elite: a ficha do tema nomeia o Theme-Id" "$AIROOTFS/usr/share/sddm/themes/elite/metadata.desktop" 'Theme-Id=elite'
file_has "greeter elite: o Main.qml é pt_BR (Bem-vindo!)" "$AIROOTFS/usr/share/sddm/themes/elite/Main.qml" 'text: "Bem-vindo!"'
file_has "greeter elite: o rótulo do usuário é pt_BR" "$AIROOTFS/usr/share/sddm/themes/elite/Main.qml" 'text: "Usuário"'
file_has "greeter elite: o rótulo da senha é pt_BR" "$AIROOTFS/usr/share/sddm/themes/elite/Main.qml" 'text: "Senha"'
file_has "greeter elite: o botão de entrada é Entrar" "$AIROOTFS/usr/share/sddm/themes/elite/Main.qml" 'text: "Entrar"'
file_has "greeter elite: o suspender é pt_BR" "$AIROOTFS/usr/share/sddm/themes/elite/Main.qml" 'text: "Suspender"'
file_has "greeter elite: a data do topo usa o locale pt_BR nativo" "$AIROOTFS/usr/share/sddm/themes/elite/Main.qml" 'Qt.locale("pt_BR")'
file_has "greeter elite: o login fala com o sddm (sessão incluída)" "$AIROOTFS/usr/share/sddm/themes/elite/Main.qml" 'sddm.login('
file_has "greeter elite: o desligar fala com o sddm" "$AIROOTFS/usr/share/sddm/themes/elite/Main.qml" 'sddm.powerOff()'
file_has "greeter elite: o conf da casa veste o tema" "$AIROOTFS/etc/sddm.conf.d/elite.conf" 'Current=elite'
file_has "greeter elite: o cursor é o Adwaita GARANTIDO da casa (o 'Could not setup default cursor' morto — 1.0-108)" "$AIROOTFS/etc/sddm.conf.d/99-elite.conf" 'CursorTheme=Adwaita'
file_hasnt "greeter elite: UM dono por chave (kde_settings sem a chave de tema)" "$AIROOTFS/etc/sddm.conf.d/kde_settings.conf" 'Current='
file_hasnt "greeter elite: UM dono por chave (kde_settings sem a chave de cursor)" "$AIROOTFS/etc/sddm.conf.d/kde_settings.conf" 'CursorTheme='
file_has "greeter elite: o Main.qml viaja no pacote (mestre sddm/elite)" "$BS" '/usr/local/share/elite/sddm/elite/Main.qml'
file_has "greeter elite: o drop-in elite.conf viaja no pacote" "$BS" '/usr/local/share/elite/sddm/elite.conf'
file_has "post-upgrade: o tema elite chega ao rig vivo (cmp manda)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" '/usr/share/sddm/themes/elite'
file_has "post-upgrade: as chaves antigas saem do kde_settings vivo (UM dono)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" '/^CursorTheme=/d'
file_has "coolercontrol: o liquidctl fecha quando o pacote não existe" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'liquidctl_integration = false'
file_has "coolercontrol: a cura SÓ desce sem o pacote liquidctl (o AIO do dono é respeitado)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'pacman -Qq liquidctl'
file_has "coolercontrol: a transação segue a mesma mão única (guard do pacman)" "$AIROOTFS/usr/local/bin/elite-post-transaction" 'pacman -Qq liquidctl'
file_has "rtkit: o daemon do RealtimeKit habilitado na dose (o portal sem choro)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'rtkit-daemon.service'
file_line_exact "packages.add: rtkit no boot (a prioridade realtime do áudio)" "$PKG" 'rtkit'
file_line_exact "packages.add: goverlay (a GUI do MangoHud da diretriz)" "$PKG" 'goverlay'
file_line_exact "sensores: o candidato Nuvoton no rol da fábrica" "$AIROOTFS/etc/modules-load.d/elite-sensors.conf" 'nct6775'
file_line_exact "sensores: o candidato ITE no rol da fábrica" "$AIROOTFS/etc/modules-load.d/elite-sensors.conf" 'it87'
file_line_exact "sensores: o termômetro AMD no rol da fábrica" "$AIROOTFS/etc/modules-load.d/elite-sensors.conf" 'k10temp'
file_line_exact "sensores: o termômetro Intel no rol da fábrica" "$AIROOTFS/etc/modules-load.d/elite-sensors.conf" 'coretemp'
file_has "sensores: a sonda da dose prova contra o hwmon vivo" "$AIROOTFS/usr/local/bin/elite-post-upgrade" '/sys/class/hwmon'
file_has "snapshot: o findmnt na raiz decide (a lei do btrfs)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'findmnt -n -o FSTYPE /'
file_has "snapshot: o config do root nasce guardado (idempotente)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" '/etc/snapper/configs/root'
file_has "snapshot: grub-btrfsd ligado SÓ no btrfs" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'grub-btrfsd.service'
file_has "snapshot: snapper-cleanup.timer vigiado no btrfs" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'snapper-cleanup.timer'


# ══ 1.0-107 — CONSOLIDAÇÃO, ESTABILIDADE E POLIMENTO (a dose nova) ══
# §2 — O BOOT DA SESSÃO: o ambiente Wayland no dbus/userd ANTES de tudo
file_has "boot: o dbus-update-activation-environment nasce ANTES da casa (o cold boot vazio morre)" "$AIROOTFS/etc/skel/.config/labwc/autostart" 'dbus-update-activation-environment --systemd'
file_has "boot: o XDG_CURRENT_DESKTOP=labwc:wlroots no ambiente exportado (a grafia da diretriz 1.0-108)" "$AIROOTFS/etc/skel/.config/labwc/autostart" 'XDG_CURRENT_DESKTOP=labwc:wlroots'
# §2 — O AGENTE POLKIT DA MÁQUINA (o lxqt primeiro, o polkit-gnome de queda)
file_has "polkit: a vaga sabe a máquina (o lxqt-policykit-agent é o agente da casa)" "crates/elite-daemon/src/supervise.rs" '/usr/bin/lxqt-policykit-agent'
file_has "polkit: o polkit-gnome clássico é a queda honesta" "crates/elite-daemon/src/supervise.rs" '/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1'
# §2 — O DONO ÚNICO DO SWAYNC (a volta da central sem o crash-loop)
file_has "swaync: a vaga supervisionada sobe com -c E -s (o CSS EXISTENTE)" "crates/elite-daemon/src/supervise.rs" 'swaync -c {conf} -s {css}'
file_has "swaync: o gate é o nome org.freedesktop.Notifications no bus (a casa não soma centros)" "crates/elite-daemon/src/supervise.rs" 'org.freedesktop.Notifications'
file_has "swaync: o unit do systemd --user MASCARADO na dose (o start-limit-hit morre)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'systemctl --global mask swaync.service'
file_exists "swaync: a mask /etc/systemd/user/swaync.service → /dev/null na árvore (o pacote carrega)" "$AIROOTFS/etc/systemd/user/swaync.service"
file_has "swaync: o craft-rice entrega a pele na AUSÊNCIA (o presente é do dono)" "$AIROOTFS/usr/local/bin/craft-rice" 'swaync_skin'
file_has "swaync: o sync_skel entrega a central ao rig vivo" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'gtk-3.0 gtk-4.0 fuzzel nwg-drawer swayosd swaync'
file_line_exact "packages.add: swaync volta com dono único (a central da casa)" "$PKG" 'swaync'
# §3 — SDDM: estabilidade técnica (o visual nativo segue)
file_has "sddm: InputMethod vazio (o stub qtvirtualkeyboard morre — o dono é o 99-elite.conf)" "$AIROOTFS/etc/sddm.conf.d/99-elite.conf" 'InputMethod='
file_has "sddm: ReuseSession=false (o logout/login nasce sessão limpa)" "$AIROOTFS/etc/sddm.conf.d/elite.conf" 'ReuseSession=false'
# §4 — O SELETOR NÃO-BLOQUEANTE
file_has "pick: o NON_UNIQUE destrava o 2º menu (a instância única matava o pedido novo)" "crates/craft-tools/src/bin/craft-pick.rs" 'NON_UNIQUE'
file_has "pick: o notify::is-active desce o seletor quando o palco é de outro (1.0-107 — zero zumbi)" "crates/craft-tools/src/bin/craft-pick.rs" 'is-active'
# §5 — OS WAKEUPS ESPÚRIOS POR PADRÃO (a família inteira, a mão do dono no allowlist)
file_hasnt "acpi: a família FIXA de era não volta (a LEI PURA 1.0-108: TODO *enabled fora da allowlist dorme)" "$AIROOTFS/usr/local/bin/elite-acpi-wakeup" 'XHC*|PTXH|GPP*|GP[0-9]*|X1[0-9]*|X1_[0-9]*'
file_hasnt "wake: o gate do teclado de era MORREU (o dongle fingidor o vencia)" "$AIROOTFS/usr/local/bin/craft-wake-guard" 'ctrl_tem_teclado'
file_hasnt "wake: a exceção de teclado USB morre com o fingidor (todo USB dorme)" "$AIROOTFS/usr/local/bin/craft-wake-guard" 'HID 01 na própria árvore'
file_has "wake: TODO o USB dorme na política nova (o despertar é da mão do dono universal — a lei PURA 1.0-108)" "$AIROOTFS/usr/local/bin/craft-wake-guard" 'despertar = power/sleep/PS2K/LID (a lei PURA 1.0-108'
# 1.0-107.2 — O ALLOWLIST UNIVERSAL (desktop E notebook em qualquer AMD/Intel)
file_has "acpi: o allowlist universal da mão do dono (PWRB/SLPB/PBTN/PS2K/LID)" "$AIROOTFS/usr/local/bin/elite-acpi-wakeup" 'MANTEM="PWRB SLPB PBTN PS2K LID"'
file_has "acpi: o cinto ARMA o allowlist dormindo de fábrica (a outra face da lei)" "$AIROOTFS/usr/local/bin/elite-acpi-wakeup" 'O CINTO DO DESPERTAR'
file_has "wake: a allowlist universal veste as DUAS grafias do power e o sleep físico" "$AIROOTFS/usr/local/bin/craft-wake-guard" 'MANTEM_ALLOW="PWRB SLPB PBTN PS2K LID"'
# §5 — A SEQUÊNCIA SEGURA DO SONO (hyprlock mapeado ANTES do wlopm --off)
file_has "sono: a espera da superfície do lock ANTES do apagar (a ordem da diretriz)" "crates/elite-daemon/src/idle.rs" 'fn lock_mapeado'
file_has "sono: o backoff do link DP/HDMI entre o wlopm --on e o recover (o amdgpu assenta)" "crates/elite-daemon/src/main.rs" 'from_millis(800)'
file_has "sono: o hyprlock renasce se morreu no sono (a tela nunca acorda nua)" "crates/elite-daemon/src/main.rs" 'não sobreviveu ao sono'
# §6 — O MODO DE JOGO MANUAL (o automático morreu inteiro)
file_hasnt "game: o watch morreu com o automático (a varredura contínua é dívida)" "$AIROOTFS/usr/local/bin/craft-game" 'gm_watch'
file_hasnt "game: o AUTO=1 morreu (o conf de era não é lido)" "$AIROOTFS/usr/local/bin/craft-game" 'AUTO='
file_hasnt "game: o filtro WINE_HELPER_PATS morreu (a heurística de /proc é de era)" "$AIROOTFS/usr/local/bin/craft-game" 'WINE_HELPER_PATS'
file_hasnt "game: o gm_whois morreu (a perícia de /proc do hook de era)" "$AIROOTFS/usr/local/bin/craft-game" 'gm_whois'
file_has "game: o inibidor prende idle:sleep (bloqueio E suspensão na jogatina)" "$AIROOTFS/usr/local/bin/craft-game" '--what=idle:sleep'
file_has "game: o item do menu diz o estado (Ativar/Desativar conforme o momento)" "$AIROOTFS/usr/local/bin/craft-game" 'Desativar modo de jogo'
file_hasnt "daemon: a varredura round() de /proc morreu (o scan é só o cliente GameMode)" "crates/elite-daemon/src/scan.rs" 'pub fn round'
file_hasnt "game.ini: o hook start de era não aponta mais pro craft-game" "$AIROOTFS/etc/gamemode.ini" 'craft-game hook'
# §7 — A VIGÍLIA COORDENADA (o idle.conf unificado)
file_has "idle: o Desativado zera OS DOIS (o preset escreve 0 — o sistema nunca dorme sozinho)" "$AIROOTFS/usr/local/bin/craft-idle" 'escreve 0'
file_has "idle: o preset veste o sono associado (o dono VÊ o que escolheu)" "$AIROOTFS/usr/local/bin/craft-idle" 'dorme aos 20 min'
file_has "idle: o Suspender agora nasce no menu (o gesto imediato)" "$AIROOTFS/usr/local/bin/craft-idle" 'Suspender agora'
file_has "idle: o título veste o estado (trava E sono na mesma frase)" "$AIROOTFS/usr/local/bin/craft-idle" 'rotulo_estado'
file_has "daemon: a vigília honra o what COMPOSTO idle:sleep (split nos lados)" "crates/elite-daemon/src/idle.rs" "what.split(':')"
# §8 — O FEEDBACK HONESTO (cancelamento é silêncio, resumo é real)
file_has "tools: o cancelamento da senha é silêncio (rc 126/127 sem alarme falso)" "crates/craft-tools/src/bin/craft-update.rs" 'rc == 126 || rc == 127'
file_has "tools: o cancelamento da limpeza é silêncio idem" "crates/craft-tools/src/bin/craft-clean.rs" 'rc == 126 || rc == 127'
file_has "dose: o censo checkupdates veste o resumo REAL (N pacotes)" "$AIROOTFS/usr/local/bin/elite-dose" 'checkupdates'
file_has "dose: a conclusão notifica com o N e o conselho de reboot SÓ no kernel novo" "$AIROOTFS/usr/local/bin/elite-dose" 'Elite: atualização concluída'
file_has "clean: o resumo real notificado à sessão (o total liberado em MiB/GB)" "$AIROOTFS/usr/local/bin/elite-clean" 'Total liberado'
# §9 — O RELÓGIO SEM TOOLTIP (o calendário é do clique)
file_has "bar: o tooltip do relógio morre (o calendário é EXCLUSIVO do clique)" "crates/craft-bar-rs/src/ui.rs" 'set_has_tooltip(false)'
# §9 — a rede reavaliada no retorno do sono (sem travar o módulo)
file_has "rede: o connectivity check no retorno do sono (fork pontual por evento)" "crates/elite-daemon/src/main.rs" '"networking", "connectivity", "check"'
# ── 1.0-109 Etapa 2 — O TERMINAL INTELIGENTE (a diretriz §2.4: o card
#    fastfetch enxuto na abertura + os verbos rápidos em português)
# o fastfetch é DEPENDÊNCIA DURA do pacote (a instalação da dose é o depends)
file_has "pkg: o fastfetch viaja no depends do elite-system (o card do terminal é garantido pela transação)" ".ci/build.sh" 'depends=(bash wayland wlopm xorg-xhost xorg-xauth blueman fastfetch)'
# o card enxuto: os módulos de era (host/packages/shell/colors) saem
file_has "fetch: o card da casa veste o módulo de disco na RAIZ (o juízo da diretriz §2.4)" "$AIROOTFS/usr/local/share/elite/fastfetch/config.jsonc" '"type": "disk"'
file_hasnt "fetch: o card de 17 módulos morre (o packages/shell de era saem — o card é enxuto)" "$AIROOTFS/usr/local/share/elite/fastfetch/config.jsonc" '"packages"'
file_hasnt "fetch: o bloco de cores de era sai (o retrato é minimalista)" "$AIROOTFS/usr/local/share/elite/fastfetch/config.jsonc" '"colors"'
# o preset no skel + a entrega ao rig vivo (a dose veste quem já nasceu)
file_exists "fetch: o preset do card no skel (as instalações novas nascem com ele)" "$AIROOTFS/etc/skel/.config/fastfetch/config.jsonc"
file_has "heal: o cura_fetch entrega o MESTRE do pacote ao home AUSENTE (o skel do rig é da época da instalação)" "$AIROOTFS/usr/local/bin/elite-heal-sessao" 'cura_fetch'
file_has "heal: o card entregue é o mestre do pacote (sempre corrente na dose)" "$AIROOTFS/usr/local/bin/elite-heal-sessao" '/usr/local/share/elite/fastfetch/config.jsonc'
file_has "post: o sync_skel veste o fastfetch (a mesma escola das outras peles)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'gtk-3.0 gtk-4.0 fuzzel nwg-drawer swayosd swaync fastfetch'
# o GUARDA TRIPLO (a diretriz: scripts, pipes, subshells e testes nunca recebem saída extra)
file_has "zsh: o guarda julga o shell INTERATIVO (o $- da diretriz — o pipe nunca vira card)" "$AIROOTFS/etc/skel/.zshrc" '[[ $- == *i* ]] && [ -t 1 ]'
file_has "zsh: a fuga honesta ELITE_NO_FETCH nasce (a diretriz da Etapa 2)" "$AIROOTFS/etc/skel/.zshrc" 'ELITE_NO_FETCH'
file_has "tune: a injeção da saudação veste o guarda novo nas homes vivas" "$AIROOTFS/usr/local/bin/elite-tune" 'elite-verbos-2'
# os verbos rápidos em português (ninguém memoriza craft-*)
file_has "zsh: o verbo ajuda abre o mapa da casa" "$AIROOTFS/etc/skel/.zshrc" "alias ajuda='craft-help'"
file_has "zsh: o verbo saude abre o doutor da casa" "$AIROOTFS/etc/skel/.zshrc" "alias saude='craft-doctor'"
file_has "zsh: o verbo atualizar abre a dose" "$AIROOTFS/etc/skel/.zshrc" "alias atualizar='craft-update'"
file_has "zsh: o verbo limpar abre a limpeza" "$AIROOTFS/etc/skel/.zshrc" "alias limpar='craft-clean'"
file_has "zsh: o verbo rede abre o seletor de 1 clique" "$AIROOTFS/etc/skel/.zshrc" "alias rede='craft-net'"
file_has "zsh: o verbo jogo abre o painel do modo de jogo" "$AIROOTFS/etc/skel/.zshrc" "alias jogo='craft-game'"
file_has "zsh: o verbo monitores abre o wdisplays" "$AIROOTFS/etc/skel/.zshrc" "alias monitores='wdisplays'"
# a linha única sutil abaixo do retrato
file_has "hello: a LINHA ÚNICA dos verbos rápidos abaixo do retrato (a diretriz: uma linha sutil)" "$AIROOTFS/usr/local/bin/craft-hello" 'Comandos rápidos: ajuda · saude · atualizar · limpar · rede · jogo'
file_hasnt "hello: o pointer de 3 linhas de era morre (a versão/dose não é notícia do card)" "$AIROOTFS/usr/local/bin/craft-hello" 'última dose'
# ── 1.0-109 Etapa 2 — O RÓTULO CURTO, OS GRUPOS DA FAIXA E O TEXTO HONESTO
#    (a diretriz §2.3: Auto-suspensão de 14 caracteres SEM truncar; a
#    direita em BLOCOS Mídia · Hardware · Sessão; o atualizador com o
#    resumo REAL dos pacotes antes de aplicar)
file_has "menu: o rótulo Auto-suspensão (14 caracteres — SEM truncar com '...')" "$AIROOTFS/etc/skel/.config/labwc/menu.xml" '<item label="Auto-suspensão">'
file_hasnt "menu: o rótulo longo Trava automática de era morre (16 caracteres truncavam na largura monoespaçada)" "$AIROOTFS/etc/skel/.config/labwc/menu.xml" '<item label="Trava automática">'
file_has "bar: o menu da barra veste o rótulo CURTO Auto-suspensão" "crates/craft-bar-rs/src/ui.rs" 'Some("Auto-suspensão"), Some("bar.idle")'
file_hasnt "bar: o rótulo longo Trava automática morre no menu da barra" "crates/craft-bar-rs/src/ui.rs" '"Trava automática"'
file_has "css: o divisor sutil dos grupos da faixa na folha mestra (Mídia · Hardware · Sessão)" "crates/elite-core/assets/theme.css" '#barbox separator'
file_has "bar: o divisor ENTRE mídia e hardware (a direita em BLOCOS)" "crates/craft-bar-rs/src/ui.rs" 'dir.append(&separa_grupo())'
file_has "tools: o texto honesto do atualizador (sincronizando e verificando — a senha NUNCA foi daqui)" "crates/craft-tools/src/bin/craft-update.rs" 'sincronizando repositórios e verificando pacotes'
file_hasnt "tools: o texto mentiroso de era morre (a senha é do diálogo do polkit)" "crates/craft-tools/src/bin/craft-update.rs" 'digite sua senha para continuar'
file_has "tools: o resumo dos pacotes ANTES de aplicar (pacman -Qu sem elevação)" "crates/craft-tools/src/bin/craft-update.rs" '"-Qu"'
# ── 1.0-109 Etapa 2 — O PLAYER DE MÍDIA MINIMALISTA E REATIVO (a
#    diretriz §2.2: o pill único 100% interativo, o ciclo de vida pelo
#    NameOwnerChanged < 200ms, o ícone de AÇÃO e o filtro anti-ruído)
file_hasnt "bar: o botão avulso ⏭ de era MORREU (o pill único reina — zero botões extras)" "crates/craft-bar-rs/src/ui.rs" 'btn_next'
file_hasnt "css: a pele do assento avulso de era sai da folha mestra" "crates/elite-core/assets/theme.css" '#nextbtn {'
file_has "bar: o scroll do pill com o DEBOUNCE de 250ms (a diretriz: sem salto duplo)" "crates/craft-bar-rs/src/ui.rs" 'from_millis(250)'
file_has "bar: o nome AMIGÁVEL do app (org.mpris...brave.instance15578 → 'Brave')" "crates/craft-bar-rs/src/state.rs" 'fn nome_amigavel'
file_has "bar: o tooltip com a LEGENDA DOS GESTOS (a diretriz §2.2.5)" "crates/craft-bar-rs/src/state.rs" 'Clique: Play/Pause · Scroll: Faixa · Dir.: Abrir janela'
file_hasnt "bar: o tooltip NUNCA fala o nome técnico do bus (o org.mpris morre)" "crates/craft-bar-rs/src/state.rs" 'org.mpris.MediaPlayer2.brave.instance15578 (pausado)'
file_has "daemon: o MERGE com o cache da faixa (a cura do ícone travado — o sinal parcial)" "crates/elite-daemon/src/mpris.rs" 'fn funde_track'
file_has "daemon: o FILTRO dos títulos genéricos da diretriz (WhatsApp/Audio/Voice message)" "crates/elite-daemon/src/mpris.rs" '"mensagem de voz"'
file_has "daemon: o TETO do áudio curto em µs (60s — o mpris:length da ficha)" "crates/elite-daemon/src/mpris.rs" 'TETO_CURTO_US: i64 = 60_000_000'
file_has "daemon: a ficha da faixa lida (mpris:length + CanGoNext/CanGoPrevious)" "crates/elite-daemon/src/mpris.rs" '"CanGoNext"'
file_has "daemon: a faixa do nome MORTO morre JUNTO (NameOwnerChanged limpa o cache)" "crates/elite-daemon/src/mpris.rs" 'A FAIXA DO NOME MORTO MORRE JUNTO'
file_has "daemon: a preferência do TOCANDO (o pausado não rouba o assento de quem toca)" "crates/elite-daemon/src/mpris.rs" 'NÃO ROUBA O ASSENTO DE QUEM TOCA'

printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase20.txt"
exit 0
