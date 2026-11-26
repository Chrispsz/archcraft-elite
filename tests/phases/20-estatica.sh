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
# 1.0-102 — O AUTOSTART MINIMALISTA (audit 102 §2): nenhum residente
# nasce no autostart (linha VIVA, fora de comentário) — quem lança é o
# elite-daemon session; o corpo congelado de dose antiga é fóssil que o
# elite-heal-sessao reconstrói do mestre
_nao_residente="$(grep -vE '^[[:space:]]*(#|$)' "$AIROOTFS/etc/skel/.config/labwc/autostart" 2>/dev/null \
    | grep -cE '(^|[[:space:]/])(swaync|swaybg|swayosd-server|lxqt-policykit-agent|polkit-gnome|udiskie)([[:space:]]|&|$)' || true)"
if [ "${_nao_residente:-0}" -eq 0 ]; then
    t_ok "autostart: ZERO residente nascendo fora do orquestrador (1.0-102 — o corpo é minimalista)"
else
    t_fail "autostart: ZERO residente nascendo fora do orquestrador" \
        "$_nao_residente spawn(s) fóssil(is) em linha viva — o lançador ÚNICO é o elite-daemon session"
fi
unset _nao_residente

# ══ O PACOTE (as ferramentas dedicadas da diretriz, o debloat) ══
# 2.0 Fase 2 — o swayidle APOSENTOU (a vigília é do elite-daemon nativo)
PKG="elite/packages.add"
for p in iwgtk blueman nm-connection-editor pwvucontrol coolercontrol swaync nwg-drawer gnome-text-editor papers brave-origin cliphist swayosd lxqt-policykit; do
    file_line_exact "packages.add: a ferramenta dedicada $p" "$PKG" "$p"
done
file_hasnt "packages.add: o waybar NÃO volta (a top bar é nativa)" "$PKG" '^waybar$'
# E151 — O DEBLOAT EXTREMO: o Xorg ocioso e o udiskie Python saem da ISO
file_hasnt "packages.add: o xorg-server NÃO volta (o greeter é wayland nativo)" "$PKG" '^xorg-server$'
file_hasnt "packages.add: o udiskie NÃO volta (o automount é regra udev)" "$PKG" '^udiskie$'
file_hasnt "packages.add: o hyprpolkitagent NÃO volta (o polkit é ÚNICO)" "$PKG" '^hyprpolkitagent$'
file_line_exact "packages.remove: o xorg-server aposentado (o greeter veste wayland — E151)" "elite/packages.remove" 'xorg-server'
file_line_exact "packages.remove: o udiskie aposentado (o Python residente morre — E151)" "elite/packages.remove" 'udiskie'
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
file_has "build.sh: o juiz craft-audit embarca com a família de bins" "$BS" 'craft-update craft-clean craft-help craft-pick craft-dump craft-audit; do'
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
file_has "build.sh: o MANIFEST nasce dos bins reais (2.0: os bins COMPILADOS pulam o overlay)" "$BS" 'craft-update|craft-clean|craft-help|craft-pick|craft-dump|craft-audit|elite-daemon|craft-bar-rs|craft-dock-rs) continue'
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
file_has "bar: o mapa E149 da rede — o ESQUERDO abre o iwgtk (o editor técnico é a queda honesta)" "crates/craft-bar-rs/src/ui.rs" 'iwgtk'
file_has "bar: o direito da rede alterna o RÁDIO Wi-Fi na hora" "crates/craft-bar-rs/src/ui.rs" '["radio", "wifi"]'
file_has "bar: a sessão é O endereço único de Bloquear/Encerrar (o dedupe da diretriz)" "crates/craft-bar-rs/src/ui.rs" 'bar.logout'
file_has "bar: o ícone por NOME GTK (o glifo Nerd quebrado morre)" "crates/craft-bar-rs/src/ui.rs" 'audio-volume-high-symbolic'
file_has "bar: o juízo do ícone de volume pelo estado (o núcleo nomeia)" "crates/craft-bar-rs/src/state.rs" 'audio-volume-muted-symbolic'
file_hasnt "bar: o bgapps NÃO VOLTA (a ordem do dono: fora da interface e do código)" "crates/craft-bar-rs/src/ui.rs" 'craft-bgapps'
file_hasnt "bar: NENHUM glifo Nerd Font no label (a fonte GTK não os tem)" "crates/craft-bar-rs/src/ui.rs" '\\u{f027}'
file_hasnt "daemon: o ouvidor bus bgapps não volta (nenhum emissor do +9)" "crates/elite-daemon/src/main.rs" 'thread_bus_bgapps'
file_has "post-upgrade: o fóssil craft-bgapps morre com voz" "elite/airootfs/usr/local/bin/elite-post-upgrade" 'craft-bgapps'
file_has "elite-clean: o blueman NÃO é mais removido (o gerenciador da interface fica)" "elite/airootfs/usr/local/bin/elite-clean" 'blueman: DEVOLVIDO ao sistema'
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
file_has "bar: a coveira dos filhos (o <defunct> morre colhido)" "crates/craft-bar-rs/src/ui.rs" 'solta-coveira'
file_has "dock: a coveira do dismiss (o pkill não vira zumbi)" "crates/craft-dock-rs/src/ui.rs" 'dismiss_overlays'
file_has "dump: o modo --full (o consolidado limpo E146)" "crates/craft-dump-rs/src/main.rs" 'modo_full'
file_has "daemon: a 2ª instância sai 0 COM VOZ (a recusa deixa papel)" "crates/elite-daemon/src/supervise.rs" 'a 2ª instância sai 0'
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
file_has "menu: o Modo de jogo abre o painel (craft-game menu)" "elite/airootfs/etc/skel/.config/labwc/menu.xml" 'command="foot -e craft-game menu"'
file_has "menu: a Trava automática abre o painel (craft-idle menu)" "elite/airootfs/etc/skel/.config/labwc/menu.xml" 'command="foot -e craft-idle menu"'
file_has "idle: o verbo menu existe (o painel do dono)" "$AIROOTFS/usr/local/bin/craft-idle" 'craft-pick --title'
# E149 — A FÁBRICA DA VAGA AUTOMÁTICA E DA TRAVA (a diretriz: o modo
# jogo volta a nascer ligado; o skel cobre a ISO nova, o post_upgrade
# cobre o rig que antecedeu a dose)
file_has "jogo: o AUTO=1 nasce na casa (a vaga automática do skel)" "elite/airootfs/etc/skel/.config/elite/game.conf" 'AUTO=1'
file_has "trava: a fábrica do idle trava em 5 (LOCK_MIN da casa)" "elite/airootfs/etc/skel/.config/elite/idle.conf" 'LOCK_MIN=5'
# E150 — o gesto separado: a tela APAGA no tempo PRÓPRIO (fábrica 10)
file_has "trava: a fábrica do idle apaga em 10 (o gesto separado E150)" "elite/airootfs/etc/skel/.config/elite/idle.conf" 'OFF_MIN=10'
file_has "daemon: a pele do swaync chega do skel ANTES do fork (o Config not found! morre)" "crates/elite-daemon/src/supervise.rs" 'fn entrega_pele_swaync'
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
# A SESSÃO DE ENTRADA: cursor único, sessão labwc direta:
file_has "greeter: o cursor do login é Bibata (o último sotaque do ponteiro morre)" "$AIROOTFS/etc/sddm.conf.d/kde_settings.conf" 'CursorTheme=Bibata'
file_has "greeter: a sessão do autologin é labwc (sem ruído de seletor)" "$AIROOTFS/etc/sddm.conf.d/kde_settings.conf" 'Session=labwc'
file_hasnt "packages.add: o archcraft-cursor-qogirr não volta (pacote órfão aposentado)" "$PKG" '^archcraft-cursor-qogirr$'
# A ENTREGA (uma fonte, dois veículos — ISO via overlay, rig via mestre):
file_has "build.sh: o mestre do greeter viaja no pacote (elite/sddm)" "$BS" '/usr/local/share/elite/sddm/theme.conf'
file_has "build.sh: o mestre do greeter nasce DA MESMA FONTE do overlay" "$BS" '/work/elite/airootfs/usr/share/sddm/themes/archcraft/theme.conf'
file_has "post-upgrade: a pele do greeter chega ao rig vivo na dose" "$AIROOTFS/usr/local/bin/elite-post-upgrade" '/usr/share/sddm/themes/archcraft/theme.conf'
file_has "rice: o fóssil da v7 na rede do lock (quem adotou a v7 renova à v8)" "$AIROOTFS/usr/local/bin/craft-rice" '6e4597244cb625dde1ed33f419afabb8bf9270230a4218311c9c4acf9919b0ea'
# O MOLDE veste o pkgrel 103 (lei E41 — o guard cobra)
# (1.0-103 — a âncora viva da era: cada dose sobe o número NO MESMO commit)
file_has "build.sh: o pkgrel da era é 103 (elite-system 1.0-103)" "$BS" 'pkgrel=103'
# A CURA DO CANAL VERMELHO (#45632905510 — o E0599 pela 2ª era): o gdk4
# 0.11.5 NÃO gera monitor-added/removed/monitors-changed (deprecated desde
# o GTK 4.16, fora de DisplayExt) — a via viva é o items-changed do
# GListModel de monitors(); o comentário da era que dizia 'o 0.11 o
# entrega sem aviso' MENTIA (a classe E33 morre junto):
file_hasnt "monitor: o trio morto do gdk4 0.11 não volta (connect_monitor_added é E0599)" "crates/craft-bar-rs/src/ui.rs" 'connect_monitor_added'
file_hasnt "monitor: o trio morto do gdk4 0.11 não volta (dock idem)" "crates/craft-dock-rs/src/ui.rs" 'connect_monitor_added'
file_has "monitor: o ouvidor vivo é o items-changed do GListModel (barra)" "crates/craft-bar-rs/src/ui.rs" 'connect_items_changed'
file_has "monitor: o ouvidor vivo é o items-changed do GListModel (dock)" "crates/craft-dock-rs/src/ui.rs" 'connect_items_changed'

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
file_has "daemon: a porta session sai com o lock FORA do chão (saída limpa)" "crates/elite-daemon/src/supervise.rs" 'session.lock fora do chão'
file_has "daemon: o cão de guarda do socket no supervisa (a 2ª via do fim)" "crates/elite-daemon/src/supervise.rs" 'SUMIU do chão'
# o julgamento do órfão pela IDENTIDADE da sessão (o wayland-0 de mesmo
# nome não mente mais):
file_has "daemon: o relogin julga o órfão pela identidade (XDG_SESSION_ID)" "crates/elite-daemon/src/supervise.rs" 'julga_orfao_relogin'
file_has "daemon: o lock do órfão teimoso é assumido na hora" "crates/elite-daemon/src/supervise.rs" 'ASSUME'
# a config padrão do swaync viaja na DOSE (o "Config not found!" do
# audit 102 morre; 1.0-104 — o CONFLITO do /etc/xdg morre junto: o
# caminho é do swaync upstream, dois pacotes no mesmo arquivo é
# --overwrite em TODA dose — o mestre da casa + o skel do rig bastam):
file_has "pkg: o mestre do swaync viaja no pacote (a cadeia do daemon lê 1º)" ".ci/build.sh" 'files/usr/local/share/elite/swaync/config.json'
file_has "pkg: o SKEL do swaync viaja no pacote (o rig recém-nascido já veste)" ".ci/build.sh" 'files/etc/skel/.config/swaync/config.json'
file_hasnt "pkg: o /etc/xdg/swaync NÃO viaja no pacote (o caminho é do swaync upstream — zero conflito de arquivo)" ".ci/build.sh" 'files/etc/xdg/swaync'
file_hasnt "skel-etc: o gêmeo /etc/xdg/swaync do airootfs NÃO existe mais (1.0-104)" "elite/airootfs/etc/xdg/swaync/config.json" 'positionX'
file_has "daemon: a cadeia de mestres do entrega_pele_swaync (pacote 1º, skel 2º)" "crates/elite-daemon/src/supervise.rs" 'usr/local/share/elite/swaync'
file_has "update: a pele do swaync (config E estilo) veste o $HOME ANTES da dose" "elite/airootfs/usr/local/bin/elite-update" 'config.json style.css'
# 1.0-104 — O PROBE LÊ O LOCK VIVO (o SUPERVISOR_LOCK reflete o
# session.lock do elite-daemon — o bars.lock fóssil nunca mais mente):
file_has "probe: o SUPERVISOR_LOCK julga pelo session.lock do elite-daemon" "elite/airootfs/usr/local/bin/elite-session-probe" 'elite/session.lock'
# o heal ganha o juízo do FÓSSIL DE SPAWN (o corpo congelado de dose
# antiga com residente de era nascendo é reconstruído do mestre):
file_has "heal: o juízo do FÓSSIL DE SPAWN (audit 102 §2)" "elite/airootfs/usr/local/bin/elite-heal-sessao" 'FÓSSIL DE SPAWN'
# a DOCK ATÔMICA (a duplicação transitória do pin morre no mesmo ciclo):
file_has "dock: a reconciliação ATÔMICA do rebuild_pins (pin · dinâmico · indicador no MESMO ciclo)" "crates/craft-dock-rs/src/ui.rs" 'A RECONCILIAÇÃO ATÔMICA'
file_has "dock: os dinâmicos resolvem pelos app_ids das JANELAS (a régua unificada)" "crates/craft-dock-rs/src/ui.rs" 'A FONTE UNIFICADA'
# a gaveta desce com o palco (o overlay nunca fica por cima da casa):
file_has "gaveta: o daemon desce o nwg-drawer quando outra janela ganha foco" "crates/elite-daemon/src/wayland.rs" 'gaveta_desce'
file_has "gaveta: o sinal do daemon colhe o drawer do uid" "crates/elite-daemon/src/main.rs" 'pub(crate) fn gaveta_desce'
# o seletor nunca vira zumbi (~24 MB): perdeu o foco = exit imediato
file_has "pick: o EventControllerFocus desce o seletor no leave (zero zumbi)" "crates/craft-tools/src/bin/craft-pick.rs" 'connect_leave'
# as flags reais do craft-pick --help (a cura do 'Opção --title=... desconhecida'):
file_has "pick: o craft-idle sonda o --help antes do --title (a flag de era não mata o painel)" "$AIROOTFS/usr/local/bin/craft-idle" 'craft-pick --help'
file_has "pick: o craft-game sonda o --help antes do --title (idem)" "$AIROOTFS/usr/local/bin/craft-game" 'craft-pick --help'
# as pausas do foot -e (o terminal do menu não some com o veredito):
file_has "terminal: o craft-help pausa no Enter (o mapa não some)" "crates/craft-tools/src/bin/craft-help.rs" 'Pressione Enter para fechar'
file_has "terminal: o craft-update pausa no Enter (o veredito não some)" "crates/craft-tools/src/bin/craft-update.rs" 'Pressione Enter para fechar'
# o cancelamento do pkexec é silêncio (o 126 não é erro):
file_has "pkexec: o rc 126 (senha cancelada) sai calado — sem toast no swaync" "$AIROOTFS/usr/local/bin/elite-gparted" 'ne 126'
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
file_has "bar: a faixa é 28px (a proporção obsidiana do dono)" "crates/craft-bar-rs/src/ui.rs" 'const ALTURA: i32 = 28'
file_has "bar: o microfone é ASSENTO PRÓPRIO (o fim do clique do meio escondido)" "crates/craft-bar-rs/src/ui.rs" 'set_widget_name("micbtn")'
file_has "bar: o ícone do mudo do MIC é o próprio do microfone" "crates/craft-bar-rs/src/state.rs" 'microphone-sensitivity-muted-symbolic'
file_has "bar: o foco do tema morre nos botões (focus_on_click false)" "crates/craft-bar-rs/src/ui.rs" 'set_focus_on_click(false)'
file_has "bar: a pálida do foco corre na árvore pronta (apaga_foco_da_barra)" "crates/craft-bar-rs/src/ui.rs" 'apaga_foco_da_barra'
file_has "bar: o relógio esquerdo alterna o painel swaync (a ordem do dono)" "crates/craft-bar-rs/src/ui.rs" '"swaync-client", "-t", "-sw"'
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
file_has "automount: a regra udev 91 existe (o udiskie morreu com substituto)" "$AIROOTFS/usr/lib/udev/rules.d/91-elite-automount.rules" 'elite-automount@'
file_exists "automount: a unit oneshot por evento existe" "$AIROOTFS/etc/systemd/system/elite-automount@.service"
file_line_exact "automount: o helper é bin da casa (0755, E90)" "$AIROOTFS/usr/local/bin/elite-automount" '#!/bin/sh'
file_has "automount: o mount é do USUÁRIO ATIVO (nunca um mount de root)" "$AIROOTFS/usr/local/bin/elite-automount" 'runuser -u'
file_has "daemon: o udiskie SAIU da fila de residentes (o Python não nasce)" "crates/elite-daemon/src/supervise.rs" 'RESIDENTES_DEFAULT'
file_hasnt "daemon: o residente udiskie não volta (a diretriz E151)" "crates/elite-daemon/src/supervise.rs" '("udiskie",'
file_has "daemon: a mordaca do autostart duplicado do agente (Hidden=true por usuário)" "crates/elite-daemon/src/supervise.rs" 'entrega_mordaca_polkit'
file_has "skel: o supressor XDG do agente duplicado nasce na casa" "$AIROOTFS/etc/skel/.config/autostart/lxqt-policykit-agent.desktop" 'Hidden=true'
file_has "post-upgrade: o udiskie sai dos rigs vivos na dose (a higiene com dependentes)" "$AIROOTFS/usr/local/bin/elite-post-upgrade" 'for _deb in waybar gpsd udiskie'
file_has "io: o escalonador do NVMe é none (a revisão de hardware E151)" "$AIROOTFS/etc/udev/rules.d/99-elite-io.rules" 'ATTR{queue/scheduler}="none"'
file_has "io: o SSD SATA veste mq-deadline (o HDD não é tocado)" "$AIROOTFS/etc/udev/rules.d/99-elite-io.rules" 'mq-deadline'
file_has "gtk: os botões de janela nascem À DIREITA (a lei da casa no GTK3)" "$AIROOTFS/etc/skel/.config/gtk-3.0/settings.ini" 'gtk-decoration-layout=:minimize,maximize,close'
file_has "gtk: os botões de janela nascem À DIREITA (idem GTK4)" "$AIROOTFS/etc/skel/.config/gtk-4.0/settings.ini" 'gtk-decoration-layout=:minimize,maximize,close'
file_has "dose: o pacman_agil sobe para 10 downloads paralelos (o -Syu ágil E151)" "$AIROOTFS/usr/local/bin/elite-dose" 'ParallelDownloads = 10'
file_has "dose: a limpeza do cache antigo após a dose (paccache -rk1)" "$AIROOTFS/usr/local/bin/elite-dose" 'cache_enxuga'
file_has "iso: o NoExtract poda doc/man/gtk-doc na ISO (o apply-overlay)" "scripts/apply-overlay.sh" 'usr/share/doc/*'
file_has "iso: a compressão da ISO é zstd alto (o profiledef)" "scripts/apply-overlay.sh" 'COMPRESSION="zstd"'
file_has "lock: o blur é CACHE por evento (wall-blur.png — zero blur por lock)" "$AIROOTFS/usr/local/bin/craft-lock" 'wall-blur.png'

# ══ E151-d — AS SKILLS PERMANENTES E A LEI DE ENTRADA ══
file_exists "skills: a filosofia extrema é guia permanente (05)" "docs/skills/05-filosofia-extrema.md"
file_exists "skills: a UI/UX obsidiana é guia permanente (06)" "docs/skills/06-ui-ux-gtk4-wayland.md"
file_has "skills: a LEI DE ENTRADA (ler docs/skills antes de editar)" "docs/skills/README.md" 'A LEI DE ENTRADA'
file_has "constituição: o §0 manda ler as skills antes de qualquer código" "AGENTS.md" '§0 · A LEITURA OBRIGATÓRIA DAS SKILLS'
file_has "skills 06: a superfície obsidiana ÚNICA documentada" "docs/skills/06-ui-ux-gtk4-wayland.md" 'rgba(13, 13, 18, 0.96)'
file_has "skills 05: o udiskie morto com substituto nomeado" "docs/skills/05-filosofia-extrema.md" 'elite-automount'
file_exists "ci: o workflow de manutenção mensal existe" ".github/workflows/maintenance.yml"
file_has "ci: o cron mensal é o dia 1 (a vigilância sem dedo do dono)" ".github/workflows/maintenance.yml" '0 7 1 *'
file_has "ci: o check das features completas contra o Arch do dia (a quebra upstream nomeada 1 mês antes)" ".github/workflows/maintenance.yml" 'cargo check --workspace --all-features --locked'

printf '%s\n' "$OK_COUNT $FAIL_COUNT $SKIP_COUNT" > "$WORK/fase20.txt"
exit 0
