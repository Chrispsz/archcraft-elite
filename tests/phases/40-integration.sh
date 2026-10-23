#!/usr/bin/env bash
# FASE 4 — A CADEIA: integração (peças encaixando: a saída de uma é a entrada da outra)
source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"
phase_start 4 "CADEIA — peças encaixando"

# ════════════════════════════════════════════════════════════════════
# 4.A o overlay inteiro contra o upstream-fixture (apply-overlay REAL,
# clone redirecionado por git insteadOf — zero rede, zero config global)
# ════════════════════════════════════════════════════════════════════
RE="$WORK/repo"; rm -rf "$RE" "$RE-out"
mkdir -p "$RE"
cp -a "$REPO/elite" "$REPO/scripts" "$RE/"

if out="$( cd "$RE" && HOME="$WORK/home" bash scripts/apply-overlay.sh 2>&1 )" ; then
  ok "overlay: roda limpo contra o fixture"
else
  fail "overlay: roda limpo contra o fixture" "${out:0:300}"
fi

# v1.1: pacotes do packages.remove que NÃO existem upstream (mousepad/
# zathura/file-roller vieram do add da v1.0.3; xgps/xgpsspeed nunca
# existiram) → o overlay AVISA e segue (contrato documentado, não erro)
assert_match "${out:-}" "aviso: 'xgps' não está na lista upstream — ignorado" \
  "cadeia A: xgps inexistente upstream → aviso (não erro — contrato do remove)"
assert_match "${out:-}" "aviso: 'mousepad' não está na lista upstream — ignorado" \
  "cadeia A: ex-Elite mousepad (saiu do add) → aviso tolerado"
assert_match "${out:-}" "aviso: 'gpsd' não está na lista upstream — ignorado" \
  "cadeia A: gpsd (dep transitiva) → aviso tolerado (a remoção REAL é o E13 no build)"

P="$RE/elite-build/archcraft"   # profile transformado
assert_file "$P/packages.x86_64" "cadeia A: elite-build/archcraft existe (profile detectado)"

# proveniência do clone (armadilha #6 da revisão deepseek): se o insteadOf
# falhar em silêncio, o overlay teria clonado o upstream REAL — verde por sorte.
# ls-remote --get-url aplica o insteadOf (remote get-url mostra a URL crua);
# precisa do HOME onde o insteadOf foi registrado
if [[ -d "$RE/elite-build/.git" ]]; then
  purl=$(HOME="$WORK/home" git -C "$RE/elite-build" ls-remote --get-url 2>/dev/null || echo FALHOU)
  [[ "$purl" == "$WORK/upstream-src" ]] \
    && ok "cadeia A: clone veio do FIXTURE (insteadOf ativo — hermético, sem rede)" \
    || fail "cadeia A: proveniência do clone" "resolver='$purl' ≠ fixture — risco de fixture-rot"
else
  fail "cadeia A: proveniência do clone" "elite-build/.git ausente"
fi

PKG="$P/packages.x86_64"
assert_grep "$PKG" '^#cups # ELITE-REMOVED$' "cadeia A: cups comentado com marcador ELITE-REMOVED"
assert_nogrep "$PKG" '^cups$' "cadeia A: cups ativo sumiu"
assert_grep "$PKG" '^#archcraft-sway-free # ELITE-REMOVED$' "cadeia A: archcraft-sway-free debloatado"
assert_grep "$PKG" '^#linux-firmware # ELITE-REMOVED' "cadeia A: meta linux-firmware comentado"
assert_grep "$PKG" '^linux-firmware-amd$' "cadeia A: subpacote firmware amd presente"
assert_eq "$(grep -cx 'vulkan-radeon' "$PKG")" "1" "cadeia A: vulkan-radeon 1× (dedupe — add não duplica)"
assert_eq "$(grep -cx 'vulkan-intel'  "$PKG")" "1" "cadeia A: vulkan-intel 1× (append do packages.add)"
assert_grep "$PKG" '^xdotool$' "cadeia v1.5.2: xdotool propaga do packages.add p/ packages.x86_64 (fg-booster exige — o debloat v4.2 o varreu e a unit crash-loopou em silêncio por 5 versões)"
dups=$(sort "$PKG" | uniq -d | wc -l)
assert_eq "$dups" "0" "cadeia A: packages.x86_64 sem nenhuma duplicata"

# ── v1.1 · KERNEL ÚNICO BORE: linux/linux-headers/nvidia-open/settings ───
assert_grep "$PKG" '^#linux # ELITE-REMOVED$' "v1.1: kernel stock linux comentado (kernel único BORE)"
assert_grep "$PKG" '^#linux-headers # ELITE-REMOVED$' "v1.1: linux-headers stock comentado"
assert_nogrep "$PKG" '^linux$' "v1.1: kernel stock ativo sumiu"
assert_grep "$PKG" '^#nvidia-open # ELITE-REMOVED$' "v1.1: nvidia-open (pré-compilado p/ stock) comentado"
assert_grep "$PKG" '^#nvidia-settings # ELITE-REMOVED$' "v1.1: nvidia-settings comentado (LACT cobre)"
assert_grep "$PKG" '^nvidia-utils$' "v1.1: nvidia-utils FICA no live (userspace do dkms — upstream L169)"
assert_grep "$PKG" '^nvidia-open-dkms$' "v1.1: nvidia-open-dkms entra (pré-compilado contra o BORE — E11)"
assert_grep "$PKG" '^linux-cachyos-bore-headers$' "v1.1: headers do BORE presentes (dkms reconstrói no alvo)"

# ── v1.1 · PRESETS ÓRFÃOS DO KERNEL STOCK (build #48 — overlay [6.3]) ────
#  linux.preset/linux-nvidia.preset são ARQUIVOS ESTÁTICOS do profile
#  upstream (não pacotes): com o kernel stock comentado, ninguém os
#  remove exceto o overlay. Sem o [6.3] o hook mkinitcpio do build morre
#  em 'vmlinuz-linux must be readable' (tolerado) e o órfão segue pro
#  squashfs → unpackfs → sistema instalado (o gate verify-install da
#  build #48 derrubou a release exatamente nisso).
assert_file "$P/airootfs/etc/mkinitcpio.d/linux-cachyos-bore.preset" \
  "v1.1: preset BORE (overlay) presente no profile final"
assert_nofile "$P/airootfs/etc/mkinitcpio.d/linux.preset" \
  "v1.1 build#48: preset stock DELETADO do profile (arquivo estático upstream — kernel único)"
assert_nofile "$P/airootfs/etc/mkinitcpio.d/linux-nvidia.preset" \
  "v1.1 build#48: preset nvidia-stock DELETADO do profile (órfão do kernel stock)"
assert_nofile "$P/airootfs/etc/mkinitcpio.conf.d/archiso-nvidia.conf" \
  "v1.1 build#48: archiso-nvidia.conf DELETADO (perdeu o único consumidor — o preset deletado)"
assert_file "$P/airootfs/etc/mkinitcpio.conf.d/archiso.conf" \
  "v1.1: archiso.conf FICA (1ª geração do initramfs live do BORE — E11 o recria e limpa)"

# ── v1.1 · PURGA DO APP-LAYER LEGADO + v1.5 · BLOATWARE DA SPEC ────────
for gone in firefox thunar-volman thunar-archive-plugin vim blueman pavucontrol; do
  assert_grep "$PKG" "^#${gone} # ELITE-REMOVED$" "v1.1: ${gone} comentado (saiu da ISO)"
  assert_nogrep "$PKG" "^${gone}$" "v1.1: ${gone} ativo sumiu"
done
# v1.5 (spec do dono): gufw/ufw são bloatware — firewall GUI não vem de
# fábrica (nem o serviço ufw no boot — ver apply-overlay [7] + E14)
for gone in gufw ufw; do
  assert_grep "$PKG" "^#${gone} # ELITE-REMOVED$" "v1.5: ${gone} comentado (bloatware fora — spec)"
  assert_nogrep "$PKG" "^${gone}$" "v1.5: ${gone} ativo sumiu"
done
# v1.2: o plugin era o elo que RESSUSCITAVA o thunar (e o xfce4-about no
# rastro) como dependência — evidência do pacman db da ISO v1.1 real
assert_nogrep "$PKG" '^thunar-archive-plugin$' \
  "v1.2: thunar-archive-plugin ativo sumiu (depend do thunar — ressuscitava o purgado)"
assert_nogrep "$PKG" '^(mousepad|zathura|zathura-pdf-poppler|file-roller|xgps|xgpsspeed)$' \
  "v1.1: mousepad/zathura/file-roller/xgps* não voltam por engano"
for modern in brave-origin papers pwvucontrol bluetui impala; do
  assert_grep "$PKG" "^${modern}\$" "v1.1/v1.4: ${modern} no packages (app-stack moderna)"
done
# v1.5 (spec): Thunar VOLTOU como FM padrão (GUI + xdg-mime inode/directory)
for back in thunar tumbler; do
  assert_grep "$PKG" "^${back}$" "v1.5: ${back} ATIVO no packages (Thunar = FM padrão da spec)"
  assert_nogrep "$PKG" "^#${back} # ELITE-REMOVED$" "v1.5: ${back} des-comentado (voltou da purga v1.1)"
done
# v1.5 (spec): bloatware fora — helix/yazi/nvtop/swaylock/wlsunset extintos
for extinct in helix yazi nvtop swaylock wlsunset; do
  assert_nogrep "$PKG" "^${extinct}$" "v1.5: ${extinct} ativo sumiu (bloatware da spec fora)"
done
# v1.5: o novo par idle/lock (hyprlock + wlopm — receita wiki labwc)
assert_grep "$PKG" '^hyprlock$' "v1.5: hyprlock no packages (ext-session-lock-v1 no labwc)"
assert_grep "$PKG" '^wlopm$' "v1.5: wlopm no packages (DPMS wlr-output-power-management)"
assert_nogrep "$PKG" '^brave-bin$' "v1.4: brave-bin saiu (Brave ORIGIN oficial entra — diretriz do dono)"
assert_grep "$PKG" '^qalculate-gtk$' "v1.1: qalculate-gtk fica (sobrevivente GTK3)"
assert_grep "$PKG" '^nwg-look$' "v1.1: nwg-look fica (theming GTK — sobrevivente)"

# ── v1.0.3: sessão única labwc — debloat com comentário inline ─────────
assert_grep "$PKG" '^#archcraft-openbox # ELITE-REMOVED$' "v1.0.3: archcraft-openbox debloatado (linha com comentário inline no .remove)"
assert_grep "$PKG" '^#archcraft-bspwm # ELITE-REMOVED$' "v1.0.3: archcraft-bspwm debloatado"
assert_grep "$PKG" '^#archcraft-installer # ELITE-REMOVED$' "v1.0.3: archcraft-installer debloatado (Calamares fica)"
assert_grep "$PKG" '^#polybar # ELITE-REMOVED$' "v1.0.3: polybar (barra X11) debloatado"
assert_grep "$PKG" '^#alacritty # ELITE-REMOVED$' "v1.0.3: alacritty debloatado (foot é O terminal)"
assert_grep "$PKG" '^#mpd # ELITE-REMOVED$' "v1.0.3: mpd (sample music) debloatado"
assert_nogrep "$PKG" '^archcraft-openbox$' "v1.0.3: archcraft-openbox ativo sumiu"
assert_nogrep "$PKG" '^alacritty$' "v1.0.3: alacritty ativo sumiu"
assert_grep "$PKG" '^labwc$' "v1.0.3: labwc no packages (a sessão)"
assert_grep "$PKG" '^waybar$' "v1.0.3: waybar no packages"
assert_grep "$PKG" '^foot$' "v1.0.3: foot no packages"
assert_grep "$PKG" '^swaync$' "v1.0.3: swaync no packages"
assert_grep "$PKG" '^fuzzel$' "v1.0.3: fuzzel no packages"
assert_grep "$PKG" '^fastfetch$' "v1.0.3: fastfetch no packages (craft-hello)"

# ── v1.0.3: skel labwc + sddm sessão labwc ─────────────────────────────
assert_file "$P/airootfs/etc/skel/.config/labwc/rc.xml" "v1.0.3: rc.xml do labwc no skel"
assert_file "$P/airootfs/etc/skel/.config/labwc/menu.xml" "v1.0.3: menu.xml no skel"
assert_file "$P/airootfs/etc/skel/.config/labwc/autostart" "v1.0.3: autostart no skel"
assert_file "$P/airootfs/etc/skel/.config/waybar/config.top" "v1.0.3+: waybar menu bar (config.top) no skel"
assert_file "$P/airootfs/etc/skel/.config/waybar/config.dock" "v1.0.4: waybar DOCK (config.dock) no skel"
assert_file "$P/airootfs/etc/skel/.config/waybar/style.top.css" "v1.0.4: waybar CSS menu bar no skel"
assert_file "$P/airootfs/etc/skel/.config/waybar/style.dock.css" "v1.0.4: waybar CSS dock no skel"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" '"mpris"' "v1.0.3: waybar módulo música (MPRIS — SUA mídia: YouTube/player)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" '"format-empty": ""' "v1.0.3: mpris auto-esconde com nada tocando (zero sample music)"
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/config.top" '"battery' "v1.0.3: waybar sem bateria (desktop — diretriz do dono)"
assert_grep "$PKG" '^playerctl$' "v1.0.3: playerctl no packages (keybinds mídia + CLI)"
assert_file "$P/airootfs/etc/skel/.config/swaync/config.json" "v1.0.3: swaync config no skel"
assert_file "$P/airootfs/etc/skel/.config/fuzzel/fuzzel.ini" "v1.0.3: fuzzel config no skel"

# ── v1.0.4 DESKTOP v2: macOS-style, mouse-first ─────────────────────────
# Dock (waybar 2ª instância): launchers fixos + janelas abertas com ícones
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.dock" '"wlr/taskbar"' "v1.0.4: dock tem taskbar (janelas abertas — wlr-foreign-toplevel nativo do labwc)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.dock" '"custom/drawer"' "v1.0.4: dock tem botão Launchpad"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.dock" '"custom/web"' "v1.0.4/v1.6: dock tem launcher do navegador (custom/web — Brave fixado no centro, fix waybar #5051)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.dock" '"icon-size": 40' "v1.0.4: ícones grandes no dock (estilo dock)"
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/config.dock" '"tray"' "v1.0.4: dock SEM tray (SNI watcher único — tray fica na barra do topo)"
# v1.1→v1.4: pins do usuário (craft-pin) — a seção PINS viaja na ISO
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.dock" '"exclusive": false' "v1.1: dock exclusive false (janelas usam a base — modelo macOS)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.dock" 'PINS \(craft-pin\)' "v1.1: seção PINS no config.dock da ISO (fixar apps do usuário)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/style.dock.css" 'Pins do usuário \(craft-pin\)' "v1.1: CSS com seção de pins (craft-pin add apoia os blocos aqui)"
assert_grep "$P/airootfs/usr/local/bin/craft-pin" '#!/usr/bin/env bash' "v1.1: craft-pin embarcado (fixar/desfixar apps da dock)"
# Menu bar: tudo clicável (mouse-first — diretriz do dono; v1.4: rede abre
# a CENTRAL craft-connect — cabo+Wi-Fi+Bluetooth num só ícone; volume abre
# pwvucontrol — zero applet/dialog GTK3 legado)
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" '"on-click": "craft-connect"' "v1.4: rede abre a central de conectividade no clique (craft-connect)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" 'swaync-client -t' "v1.0.4: relógio abre central de notificações no clique"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" 'pwvucontrol' "v1.1: volume abre pwvucontrol no clique-direito (GTK4/Rust)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" 'craft-power' "v1.0.4: botão power na barra do topo"
# Launchpad (nwg-drawer) + power gráfico (labnag) + ícones Papirus
assert_grep "$PKG" '^nwg-drawer$' "v1.0.4: nwg-drawer no packages (o Launchpad)"
assert_grep "$PKG" '^papirus-icon-theme$' "v1.0.4: papirus-icon-theme no packages (ícones de apps)"
assert_file "$P/airootfs/etc/skel/.config/nwg-drawer/drawer.css" "v1.0.4: CSS do Launchpad (Catppuccin) no skel"
assert_file "$P/airootfs/usr/local/bin/craft-drawer" "v1.0.4: craft-drawer (o Launchpad)"
# v1.4: barra de sessão do Launchpad EXTINTA (burn test: dono mandou tirar
# os botões travar/desligar/reiniciar da base — sessão mora SÓ na menu bar)
assert_nogrep "$P/airootfs/usr/local/bin/craft-drawer" 'pbexit' "v1.4: Launchpad SEM barra de sessão (power bar extinta)"
assert_file "$P/airootfs/usr/local/bin/craft-power" "v1.0.4: craft-power (menu de sessão mouse-first)"
assert_grep "$P/airootfs/usr/local/bin/craft-power" 'labnag' "v1.0.4: power via labnag (nag bar nativo do labwc)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'craft-drawer' "v1.0.4: W-d abre o Launchpad"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'systemctl poweroff' "v1.0.4: menu raiz com Desligar"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'systemctl reboot' "v1.0.4: menu raiz com Reboot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'config.top' "v1.0.4: autostart sobe a menu bar"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'config.dock' "v1.0.4: autostart sobe o DOCK"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'wallpaper\.png' "v1.0.4: wallpaper de imagem (não cor sólida)"
assert_file "$P/airootfs/etc/skel/.config/labwc/wallpaper.png" "v1.0.4: wallpaper.png no skel"

# ── v1.2 DESKTOP v2.1: burn test do dono (rig B) — a cura completa ──────
# Forense da v1.1: 7 de 8 botões da dock com "format": "" (glifos perdidos
# na escrita — dock INVISÍVEL), botão do Brave com o glifo FIREFOX (U+F0239),
# CSS pedindo família "JetBrainsMono Nerd Font" (não existe no archcraft-fonts
# 2.0 — real: "JetBrainsMono NF"), e 4 printfs do heredoc do Calamares com \n
# literal → YAML inválido → "shellprocess@btrfs could not be loaded" (o
# instalador TRAVOU no rig do dono). v2.1 = a resposta caso a caso.
CT="$P/airootfs/etc/skel/.config/waybar/config.top"
CD="$P/airootfs/etc/skel/.config/waybar/config.dock"
# Top bar (v1.5): relógio no CENTRO, canto esquerdo LIMPO (ARCH saiu — spec),
# áudio só ícone, power no canto direito
assert_grep "$CT" '"modules-center": \["clock"\]' "v2.1: relógio no CENTRO da barra (diretriz do dono)"
assert_grep "$CT" '"fixed-center": true' "v1.5: fixed-center (centro EXATO independente dos lados)"
assert_nogrep "$CT" '"custom/menu"' "v1.5: lançador ARCH FORA do canto esquerdo (spec do dono — o Launchpad vive na dock)"
assert_grep "$CT" '"modules-left": \["custom/drawer", "wlr/window"\]' "v1.6: ARCH à esquerda + nome do app focado (o pedido de volta do dono)"
assert_grep "$CT" '"format": "\{icon\}"' "v2.1: áudio em modo ícone"
assert_nogrep "$CT" '"format": "\{volume\}' "v2.1: SEM porcentagem numérica no áudio (o '40%')"
assert_grep "$CT" '"custom/power"' "v2.1: power visível no canto direito da barra"
assert_grep "$CT" '"format": "\\uf011"' "v2.1: glifo do power presente (FA power-off — BMP)"
# Glifos: os botões de GLIFO da dock (drawer/shot) com escape \uXXXX (a
# corrupção da v1.1 deixou 7 de 8 botões com format vazio — dock INVISÍVEL
# no rig do dono). v1.5: term/files/web viraram módulos image (ícone REAL)
for pair in 'drawer:\\uf303' 'shot:\\uf0c4'; do
  m=${pair%%:*}; g=${pair##*:}
  assert_grep "$CD" "\"format\": \"${g}\"," "v2.1/v1.5: dock custom/$m com glifo (v1.1: format vazio!)"
done
assert_nogrep "$CD" '\\u[0-9a-fA-F]{5,}' "v2.1: nenhum escape de 5+ hex (SMP trap: parseia como 4-hex + dígito)"
assert_nogrep "$CT" '\\u[0-9a-fA-F]{5,}' "v2.1: idem no config.top"
# v1.6: apps fixados por GLIFO Nerd Font (fix do burn test v1.5 — o waybar
# 0.15.0 crasha em silêncio com 3+ módulos image: issue upstream
# Alexays/Waybar#5051, race de realization; fix só no master). O modelo
# v1.4 (glifo) é o robusto — zero pixbuf, zero race.
for pinmod in 'term:\\uf489' 'files:\\uf07c' 'web:\\uf292'; do
  m=${pinmod%%:*}; g=${pinmod##*:}
  assert_grep "$CD" "\"custom/${m}\"" "v1.6: dock custom/${m} (pin por glifo — fix waybar #5051)"
  assert_grep "$CD" "\"format\": \"${g}\"" "v1.6: glifo do pin ${m} (escape \\uXXXX)"
done
assert_nogrep "$CD" '"image#' "v1.6: NENHUM módulo image na dock (3+ = crash silencioso — waybar #5051)"
assert_grep "$CD" '"on-click": "brave"' "v1.5/v1.6: Brave fixado no CENTRO da dock (custom/web → navegador padrão)"
assert_grep "$CD" '"on-click": "thunar"' "v1.5: Arquivos = Thunar (FM padrão da spec)"
assert_grep "$CD" '"on-click": "foot"' "v1.5: Terminal fixado (foot)"
assert_nogrep "$CD" 'pixmaps/elite' "v1.6: dock sem PNGs de pixmaps (glifos — os image# saíram junto)"
assert_nogrep "$CD" '"custom/editor"' "v1.5: botão editor (helix) saiu da dock junto com o pacote"
assert_nogrep "$CD" 'foot -e yazi|foot -e helix' "v1.5: nenhum launch de app extinto na dock"
# CSS v1.6: seletor #custom-<id> + zoom 30→36px no hover (a "magnificação")
assert_grep "$P/airootfs/etc/skel/.config/waybar/style.dock.css" '#custom-term' "v1.6: CSS #custom-term (glifo 30px)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/style.dock.css" '#custom-web:hover' "v1.6: hover do Brave = zoom 36px + pílula surface0"
assert_grep "$P/airootfs/etc/skel/.config/waybar/style.dock.css" 'font-size: 30px' "v1.6: pins a 30px de base (zoom p/ 36 no hover)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/style.dock.css" '#custom-web { color: @peach; }' "v1.6: Brave em PEACH (cor da marca) mesmo com glifo"
# Dock: grupo ÚNICO central (fixados + abertos), sem lock/power
assert_grep "$CD" '"modules-center": \[' "v2.1: dock tem grupo central"
assert_grep "$CD" '"custom/sep"' "v2.1: separador fixos│abertos no grupo central"
assert_grep "$CD" '"modules-left": \[\]' "v2.1: dock sem módulos à esquerda (bloco único central)"
assert_grep "$CD" '"modules-right": \[\]' "v2.1: dock sem módulos à direita (sessão mora no topo)"
assert_nogrep "$CD" '"custom/lock"' "v2.1: dock SEM lock (menu de sessão na barra superior)"
assert_nogrep "$CD" '"custom/power"' "v2.1: dock SEM power (menu de sessão na barra superior)"
# Fontes: família REAL do archcraft-fonts 2.0
assert_grep "$P/airootfs/etc/skel/.config/waybar/style.top.css" 'JetBrainsMono NF' "v2.1: CSS top com a família REAL (JetBrainsMono NF)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/style.dock.css" 'JetBrainsMono NF' "v2.1: CSS dock com a família REAL"
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/style.top.css" 'font-family: "?JetBrainsMono Nerd Font' "v2.1: família inexistente fora do font-family do CSS top (comentários citam o nome antigo de propósito)"
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/style.dock.css" 'font-family: "?JetBrainsMono Nerd Font' "v2.1: família inexistente fora do font-family do CSS dock"
assert_grep "$P/airootfs/etc/skel/.config/fuzzel/fuzzel.ini" 'font=JetBrainsMono NF' "v2.1: fuzzel com a família REAL"
assert_nogrep "$P/airootfs/etc/skel/.config/fuzzel/fuzzel.ini" 'font=JetBrainsMono Nerd Font' "v2.1: fuzzel sem a família inexistente na diretiva font="
assert_grep "$P/airootfs/etc/skel/.config/waybar/style.dock.css" '#custom-sep' "v2.1: CSS do separador (1px fixos│abertos)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/style.top.css" '#pulseaudio.muted' "v2.1: mudo = vermelho (áudio ícone precisa gritar estado)"
# craft-power v2: dropdown fuzzel ancorado no canto superior direito
assert_grep "$P/airootfs/usr/local/bin/craft-power" '--anchor=top-right' "v2.1: menu de sessão ancorado no canto direito (fuzzel)"
assert_grep "$P/airootfs/usr/local/bin/craft-power" 'fuzzel --dmenu' "v2.1: sessão via fuzzel dmenu (dropdown)"
assert_grep "$P/airootfs/usr/local/bin/craft-power" 'Travar tela' "v2.1: opção Travar no menu de sessão"
assert_grep "$P/airootfs/usr/local/bin/craft-power" 'Suspender' "v2.1: opção Suspender no menu de sessão"
assert_grep "$P/airootfs/usr/local/bin/craft-power" 'labnag' "v2.1: fallback labnag preservado (sem fuzzel)"
# Calamares: o YAML do shellprocess_btrfs TEM que parsear (o gate cego da v1.1)
assert_nogrep "$REPO/elite/fragments/elite-customize.sh" "printf '%s$" "v1.2: nenhum printf com \\n partido em coluna 0 (mata o YAML do Calamares)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" "printf '%s\\\\n'" "v1.2: printfs do heredoc com \\n literal (uma linha)"
# Overrides .desktop (menu limpo + ícone do instalador + foot dedupe)
APPS="$P/airootfs/usr/local/share/applications"
assert_file "$APPS/calamares.desktop" "v1.2: override do .desktop do instalador (XDG precedence)"
assert_grep "$APPS/calamares.desktop" 'Icon=system-software-install' "v1.2: ícone do instalador existente no Papirus (era archcraft-green → placeholder)"
assert_grep "$APPS/calamares.desktop" '^TryExec=calamares$' "v1.2: override preserva o TryExec do instalador"
assert_file "$APPS/abif.desktop" "v1.2: override do instalador CLI"
assert_grep "$APPS/abif.desktop" 'NoDisplay=true' "v1.2: instalador CLI fora do menu (2º instalador = sujeira)"
assert_file "$APPS/foot.desktop" "v1.2: override do .desktop do foot"
assert_grep "$APPS/foot.desktop" 'Icon=utilities-terminal' "v1.2: foot com ícone garantido no Papirus (taskbar sem placeholder)"
assert_grep "$APPS/footclient.desktop" 'NoDisplay=true' "v1.2: foot-client fora do menu (triplicação Foot — nome REAL do arquivo: footclient.desktop)"
assert_grep "$APPS/foot-server.desktop" 'NoDisplay=true' "v1.2: foot-server fora do menu (triplicação Foot)"
assert_grep "$APPS/xgps.desktop" 'NoDisplay=true' "v1.2: xgps fora do menu (GPS num desktop gaming?)"
assert_grep "$APPS/xgpsspeed.desktop" 'NoDisplay=true' "v1.2: xgpsspeed fora do menu"
assert_grep "$REPO/elite/packages.remove" '^gpsd$' "v1.2: gpsd listado no debloat (depend DURA do waybar — NoDisplay é a cura real)"
assert_grep "$REPO/elite/packages.remove" '^thunar-archive-plugin$' "v1.2: thunar-archive-plugin removido (era o elo que RESSUSCITAVA o thunar como dep — evidência do pacman db da v1.1)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'pacman -Rns --noconfirm gpsd' "v1.2: E13 tenta remover gpsd em build (falha segura — depend do waybar)"
# craft-pin v2.1: pins no grupo central, antes do separador
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin" 'modules-center' "v2.1: craft-pin insere no modules-center (junto aos fixos)"
assert_file "$P/airootfs/etc/skel/.config/gtk-3.0/settings.ini" "v1.0.4: settings.ini GTK3 no skel"
assert_grep "$P/airootfs/etc/skel/.config/gtk-3.0/settings.ini" 'Papirus-Dark' "v1.0.4: GTK usa Papirus-Dark (ícones de apps)"
assert_grep "$P/airootfs/etc/skel/.config/gtk-4.0/settings.ini" 'Papirus-Dark' "v1.0.4: GTK4 espelha o Papirus-Dark"
assert_grep "$REPO/scripts/apply-overlay.sh" 'craft-drawer' "v1.0.4: craft-drawer no file_permissions (0755 no live)"
assert_grep "$REPO/scripts/apply-overlay.sh" 'craft-connect' "v1.4: craft-connect no file_permissions (0755 no live — senão 203/EXEC)"
assert_grep "$REPO/scripts/apply-overlay.sh" 'craft-pin-pick' "v1.4: craft-pin-pick no file_permissions (0755 no live — senão 203/EXEC)"

# ── v1.0.4 RICE PRÓPRIO: themerc-override (fim do tema fantasma) ────────
assert_file "$P/airootfs/etc/skel/.config/labwc/themerc-override" "v1.0.4: themerc-override no skel (rice próprio — zero dependência de tema OB)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" 'window.active.border.color: #cba6f7' "v1.0.4: borda de janela ativa MAUVE (assinatura do rice)"
# v1.6: traffic lights com as cores REAIS do macOS (o mapeamento anterior
# tinha iconify=verde/max=amarelo — INVERTIDO vs macOS; o dono pediu "estilo
# macos": iconify=amarelo #febc2e, max=verde #28c840, close=vermelho #ff5f57).
# Os círculos agora são PNGs do tema Archcraft-Elite (fallback XBM segue).
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" '#febc2e' "v1.6: traffic light — iconify AMARELO (correção do macOS)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" '#28c840' "v1.6: traffic light — max VERDE (correção do macOS)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" '#ff5f57' "v1.6: traffic light — close VERMELHO (correção do macOS)"

# ════════════════════════════════════════════════════════════════════
# v1.6 — BURN TEST v1.5 DO DONO: instalador curado + botões mac + keyring
# Forense com fonte primária (log termbin do Calamares + ISO extraída +
# código upstream): o launch.sh do Archcraft reescreve o unpackfs.conf no
# copytoram com padrão que casa como PREFIXO do kernel BORE → source
# inexistente → "Configuração incorreta do unpackfs" no rig real.
# ════════════════════════════════════════════════════════════════════
ECF="$REPO/elite/fragments/elite-customize.sh"
VIY="$REPO/.github/workflows/verify-install.yml"
# E5a2: o patch do launch.sh (a cura do instalador)
assert_grep "$ECF" 'boot/x86_64/vmlinuz-linux-cachyos-bore' "v1.6: E5a2 alinha o padrão do launch.sh ao kernel BORE (fix do unpackfs)"
assert_grep "$ECF" 'x86_64/vmlinuz-linux-cachyos-bore\|/usr/lib/modules' "v1.6: E5a2 mira o replacement canônico (/usr/lib/modules/$KERNEL/vmlinuz)"
assert_grep "$ECF" 'E5a2: launch.sh' "v1.6: E5a2 loga a aplicação (auditável no log da build)"
# GATE copytoram no verify-install (o gate que faltava — a v1.5 passou nos
# gates e quebrou no rig: ninguém simulava o rewrite do launch.sh)
assert_grep "$VIY" 'launch-copytoram.sh' "v1.6: gate extrai o bloco copytoram do launch.sh real"
assert_grep "$VIY" 'fakebin/uname' "v1.6: gate com uname FALSO (kver da ISO, não o do runner)"
assert_grep "$VIY" 'regressão v1.5 morta' "v1.6: gate valida TODOS os sources do conf reescrito"
assert_grep "$VIY" 'vmlinuz-linux-cachyos-bore\|/usr/lib/modules' "v1.6: gate rejeita launch.sh sem o padrão BORE"
# Botões macOS: tema com PNGs + layout à direita (posição windows)
TH="$P/airootfs/usr/share/themes/Archcraft-Elite/labwc"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" '<name>Archcraft-Elite</name>' "v1.6: rc.xml aponta pro tema Elite (assets de botões)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" '<layout>icon:iconify,max,close</layout>' "v1.6: botões à DIREITA em ordem Windows (estilo mac, posição windows)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" '<showIcons>yes</showIcons>' "v1.6: menu raiz com ícones (labwc 0.8.3+)"
for png in close-active iconify-active max-active close_hover-active iconify_hover-active max_hover-active close-inactive max_toggled-active; do
  assert_file "$TH/${png}.png" "v1.6: asset ${png}.png no tema (traffic lights mac)"
done
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" 'window.button.width: 24' "v1.6: célula do botão 24px (círculo 12px mac)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" 'window.button.hover.bg.color: #00000000' "v1.6: overlay de hover OFF (o glifo mora no PNG)"
# Menu com ícones (Papirus verificado no squashfs da v1.5)
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'icon="/usr/share/icons/Papirus/48x48/apps/utilities-terminal.svg"' "v1.6: item Terminal com ícone Papirus"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'icon="/usr/share/icons/Papirus/24x24/actions/system-shutdown.svg"' "v1.6: itens de sessão com ícone (actions)"
# craft-power com ícones no dmenu (protocolo NUL+icon+US — pipe direto)
assert_grep "$P/airootfs/usr/local/bin/craft-power" 'printf .%s.0icon' "v1.6: craft-power com protocolo de ícones do dmenu (NUL+icon+US)"
assert_grep "$P/airootfs/usr/local/bin/craft-power" 'system-lock-screen.svg' "v1.6: ícone de travar no menu de sessão"
# Keyring/polkit (a pergunta do dono — "o que é keyring que pede senha?")
assert_file "$P/airootfs/etc/polkit-1/rules.d/49-elite-desktop.rules" "v1.6: rule polkit Elite (UX desktop sem senha p/ ações comuns)"
assert_grep "$P/airootfs/etc/polkit-1/rules.d/49-elite-desktop.rules" 'org.freedesktop.login1.power-off' "v1.6: power-off sem senha p/ usuário ativo local"
assert_grep "$P/airootfs/etc/polkit-1/rules.d/49-elite-desktop.rules" 'modify.global-system' "v1.6: exceção deliberada — config global segue pedindo admin (sem wildcard)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'gnome-keyring-daemon --unlock' "v1.6: bootstrap do chaveiro vazio no live/autologin (fim dos prompts)"
# tray hardening (o bloco cinza do burn test)
assert_grep "$P/airootfs/etc/skel/.config/waybar/style.top.css" '#tray > .tray > image' "v1.6: CSS de itens SNI da tray (cor + tamanho explícitos)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" 'window.active.shadow.size: 60' "v1.0.4: sombras grandes (receita hakuspace)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" 'osd.label.text.color: #cba6f7' "v1.0.4: OSD mauve (coerência com o acento)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'OB-Catppuccin-Mocha' "v1.0.4: tema FANTASMA OB-Catppuccin-Mocha removido do rc.xml (nunca existiu — causa do 'cru')"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" '<cornerRadius>12</cornerRadius>' "v1.0.4: cornerRadius 12 (ladder de raio do design system)"

# ── v1.0.4 RICE: tema GTK Catppuccin oficial + cursor Bibata ─────────────
assert_grep "$PKG" '^catppuccin-gtk-theme-mocha$' "v1.0.4: tema GTK Catppuccin Mocha oficial (repo [archcraft])"
assert_grep "$PKG" '^gtk-engine-murrine$' "v1.0.4: engine murrine (exigida pelo tema GTK)"
assert_grep "$PKG" '^archcraft-cursor-bibata$' "v1.0.4: cursor Bibata (o cursor dos melhores rices)"
assert_grep "$P/airootfs/etc/skel/.config/gtk-3.0/settings.ini" 'gtk-theme-name=Catppuccin-Mocha-Standard-Mauve-Dark' "v1.0.4: GTK3 usa Catppuccin-Mocha Mauve-Dark (= acento do rice)"
assert_grep "$P/airootfs/etc/skel/.config/gtk-3.0/settings.ini" 'gtk-cursor-theme-name=Bibata' "v1.0.4: cursor Bibata no GTK3"
assert_grep "$P/airootfs/etc/skel/.config/gtk-4.0/settings.ini" 'gtk-theme-name=Catppuccin-Mocha-Standard-Mauve-Dark' "v1.0.4: GTK4 espelha o tema Mauve-Dark"

# ── v1.0.4 FIX DO BOOT INSTALADO (shellprocess@btrfs × kernel BORE) ─────
# Bug reportado no rig B: GRUB "premature end of file vmlinuz-linux-cachyos-bore"
# pós-install em btrfs. O workaround upstream só recopia o kernel STOCK; o
# E10 estende pra TODOS os vmlinuz-* + regenera o initramfs do BORE no alvo.
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'shellprocess_btrfs.conf' "v1.0.4: E10 patcha o shellprocess_btrfs do Calamares"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'for kv in /run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-\*' "v1.0.4: E10 recopia TODOS os vmlinuz-* do pendrive (não só o stock)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'arch-chroot "\${ROOT}" mkinitcpio -p linux-cachyos-bore' "v1.0.4: E10 regenera initramfs do BORE no alvo (hooks de sistema, não do live)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'kernel-copy-success' "v1.0.4: E10 preserva o marcador do upstream"
assert_grep "$P/airootfs/etc/sddm.conf.d/kde_settings.conf" '^Session=labwc$' "v1.0.3: SDDM autologin Session=labwc"
assert_grep "$P/airootfs/var/lib/sddm/state.conf" 'wayland-sessions/labwc\.desktop' "v1.0.3: greeter pré-seleciona labwc"
assert_grep "$P/airootfs/etc/systemd/system/fg-booster.service" '^Slice=fg-boost\.slice$' "v1.0.3: fg-booster com Slice= (fix restart-loop)"
# v1.1: applets GTK3 do tray SAÍRAM (blueman/nm-applet) — bluetooth é bluetui
# (W-S-b), rede é impala (W-n); nenhum daemon GTK3 de graça na sessão
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/autostart" '^[^#]*blueman-applet' "v1.1: autostart SEM blueman-applet (bluetui cobre — fora de comentário)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/autostart" '^[^#]*nm-applet' "v1.1: autostart SEM nm-applet (impala cobre — fora de comentário)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'bluetui' "v1.1: comentário do autostart menciona bluetui (contrato)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'impala' "v1.1: comentário do autostart menciona impala (contrato)"

# ── v1.0.3 CURADORIA "brabos 2026": uso geral de fábrica ───────────
# v1.1 (MEGA PROMPT): a camada GUI legada/GTK3 foi purgada (mousepad,
# zathura, file-roller, pavucontrol, thunar, firefox → remove); entram
# papers/pwvucontrol/bluetui/impala/helix/brave-origin/yazi (assertados acima)
assert_grep "$PKG" '^qalculate-gtk$' "curadoria: qalculate (galculator saiu)"
assert_nogrep "$PKG" '^galculator$' "curadoria: galculator saiu (qalculate entra)"
assert_grep "$PKG" '^nwg-look$' "curadoria: nwg-look (xfce4-settings saiu)"
# Satélites do labwc (docs oficiais: idle/automount/clipboard)
assert_grep "$PKG" '^swayidle$' "curadoria: swayidle (idle→lock automático)"
assert_grep "$PKG" '^udiskie$' "curadoria: udiskie (automount USB + notificação)"
assert_nogrep "$PKG" '^wlsunset$' "v1.5: wlsunset SAIU dos satélites (night light não é imposição de fábrica)"
assert_grep "$PKG" '^cliphist$' "curadoria: cliphist (clipboard history — W-v)"
assert_grep "$PKG" '^libnotify$' "curadoria: libnotify (notify-send dos craft-*)"
# CLI brabos (rust — os essenciais do cockpit nascem na ISO)
for cli in ripgrep fd fzf eza bat zoxide dust procs sd starship tealdeer; do
  assert_grep "$PKG" "^$cli\$" "curadoria: CLI brabo $cli"
done
assert_grep "$PKG" '^zsh-autosuggestions$' "curadoria: plugin zsh autosuggestions"
assert_grep "$PKG" '^zsh-syntax-highlighting$' "curadoria: plugin zsh syntax-highlighting"
# Remoções-chave (cada uma com o substituto/razão)
assert_nogrep "$PKG" '^geany$' "curadoria: geany saiu (mousepad entra)"
assert_nogrep "$PKG" '^atril$' "curadoria: atril saiu (zathura entra)"
assert_nogrep "$PKG" '^galculator$' "curadoria: galculator saiu (qalculate entra)"
assert_nogrep "$PKG" '^xarchiver$' "curadoria: xarchiver saiu (file-roller entra)"
assert_nogrep "$PKG" '^ranger$' "curadoria: ranger saiu (yazi entra)"
assert_nogrep "$PKG" '^mc$' "curadoria: mc saiu (yazi fica)"
assert_nogrep "$PKG" '^htop$' "curadoria: htop saiu (btop fica)"
assert_nogrep "$PKG" '^ncdu$' "curadoria: ncdu saiu (dust entra)"
assert_nogrep "$PKG" '^simplescreenrecorder$' "curadoria: gravador X11 saiu (diretriz do dono)"
assert_nogrep "$PKG" '^btrfs-assistant$' "v1.0.4: btrfs-assistant saiu (GUI de snapper sem snapper = meia-ferramenta)"
assert_grep "$PKG" '^timeshift$' "v1.0.4: timeshift fica (ÚNICA estratégia de snapshot — craft-rollback/grub-btrfs)"
assert_nogrep "$PKG" '^snapper$' "v1.0.4: snapper fora da ISO (rota alternativa = cockpit dia-1)"
assert_nogrep "$PKG" '^archcraft-omz$' "curadoria: oh-my-zsh saiu (plugins+starship)"
assert_nogrep "$PKG" '^archcraft-skeleton$' "curadoria: skel órfão do stock saiu (skel Elite é o dono)"
assert_nogrep "$PKG" '^archcraft-welcome$' "curadoria: welcome do stock saiu (craft-hello cobre)"
assert_nogrep "$PKG" '^archcraft-neofetch$' "curadoria: neofetch descontinuado saiu (fastfetch)"
assert_nogrep "$PKG" '^xfce4-settings$' "curadoria: xfce4-settings saiu (nwg-look entra)"
assert_nogrep "$PKG" '^xfce4-power-manager$' "curadoria: power manager saiu (swayidle entra)"
assert_nogrep "$PKG" '^gvfs-afc$' "curadoria: iPhone mount saiu (gvfs+mtp+smb ficam)"
assert_grep "$PKG" '^gvfs$' "curadoria: gvfs fica (trash/mtp/smb)"
assert_grep "$PKG" '^xdotool$' "curadoria: xdotool FICA (dep dura do fg-booster)"
assert_grep "$PKG" '^qt6ct$' "curadoria: qt6ct fica (config de apps Qt futuros)"
assert_nogrep "$PKG" '^qt5ct$' "curadoria: qt5ct saiu (zero apps Qt5)"
assert_nogrep "$PKG" '^firefox$' "v1.1: firefox saiu (brave-origin entra — Wayland-native)"
# Skel próprio: .zshrc sem oh-my-zsh + .hushlogin (skeleton saiu)
assert_file "$P/airootfs/etc/skel/.zshrc" "curadoria: .zshrc próprio da Elite (omz saiu)"
assert_grep "$P/airootfs/etc/skel/.zshrc" 'starship init zsh' "curadoria: starship no prompt do .zshrc"
assert_grep "$P/airootfs/etc/skel/.zshrc" 'zsh-autosuggestions' "curadoria: autosuggestions no .zshrc"
assert_grep "$P/airootfs/etc/skel/.zshrc" 'zsh-syntax-highlighting' "curadoria: syntax-highlighting no .zshrc"
assert_grep "$P/airootfs/etc/skel/.zshrc" 'zoxide init zsh' "curadoria: zoxide no .zshrc"
assert_nogrep "$P/airootfs/etc/skel/.zshrc" 'oh-my-zsh|ZSH_THEME' "curadoria: .zshrc sem vestígio de omz"
assert_file "$P/airootfs/etc/skel/.hushlogin" "curadoria: .hushlogin (1º login limpo, skeleton saiu)"
# Autostart: os 4 satélites sobem sozinhos
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'udiskie' "curadoria: udiskie no autostart"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'craft-idle start' "curadoria: idle sobe no login (craft-idle → swayidle por baixo — v1.6.1)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/autostart" 'wlsunset' "v1.5: wlsunset FORA do autostart (causa-raiz do tom amarelado — spec)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'cliphist store' "curadoria: watcher cliphist no autostart"
# v1.6.2: cliphist PODADO — o DB cresceria SEM LIMITE (craft-shot area →
# wl-copy → PNG inteiro em base64 no histórico; meses = dezenas de MB).
# Cura = receita LITERAL do README upstream (sentriz/cliphist): "Run this
# from a timer to delete entries older than 30 days: cliphist wipe
# -older-than 720h". Duas camadas (o mesmo padrão das 4 camadas do keyring):
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'cliphist wipe -older-than 720h' "v1.6.2: camada 1 — poda no login (live/sessão sem user manager; antes do watcher, síncrona)"
assert_file "$P/airootfs/etc/skel/.config/systemd/user/cliphist-prune.service" "v1.6.2: serviço de poda existe (cliphist-prune.service)"
assert_grep "$P/airootfs/etc/skel/.config/systemd/user/cliphist-prune.service" 'ExecStart=/usr/bin/cliphist wipe -older-than 720h' "v1.6.2: ExecStart = comando literal do README (30 dias · wipe compacta o DB)"
assert_file "$P/airootfs/etc/skel/.config/systemd/user/cliphist-prune.timer" "v1.6.2: timer da poda existe (cliphist-prune.timer)"
assert_grep "$P/airootfs/etc/skel/.config/systemd/user/cliphist-prune.timer" 'OnCalendar=daily' "v1.6.2: camada 2 — poda diária (uptimes longos, semanas sem relogin)"
assert_grep "$P/airootfs/etc/skel/.config/systemd/user/cliphist-prune.timer" 'Persistent=true' "v1.6.2: Persistent — compensa os dias desligado (roda ao ligar)"
assert_file "$P/airootfs/etc/skel/.config/systemd/user/timers.target.wants/cliphist-prune.timer" "v1.6.2: timer HABILITADO no skel (symlink em timers.target.wants — useradd -m preserva)"
# v1.6.2: waybar SEM módulos exec — a classe clássica de leak/CPU-burn do
# waybar é script polling; as duas barras da Elite são 100% módulos nativos
# (apenas 2 intervals: mpris 10s, clock 60s). Contrato de não-regressão:
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/config.top" '"exec"' "v1.6.2: menu bar SEM módulo exec (zero script polling — classe de leak extinta por contrato)"
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/config.dock" '"exec"' "v1.6.2: dock SEM módulo exec (idem — os pins são format estático)"
# v1.5: keyring CachyOS em 4 camadas (spec: init → populate → refresh)
assert_grep "$P/airootfs/usr/local/bin/craft-fix-keys" 'pacman-key --populate archlinux cachyos' "v1.5: craft-fix-keys — comandos LITERAIS da spec (populate)"
assert_grep "$P/airootfs/usr/local/bin/craft-fix-keys" 'pacman -Sy --noconfirm archlinux-keyring cachyos-keyring' "v1.5: craft-fix-keys — refresh dos keyring packages (spec)"
assert_grep "$P/airootfs/usr/local/bin/craft-fix-keys" 'sudo -n' "v1.5: craft-fix-keys — sudo -n (nunca trava em background)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'craft-fix-keys' "v1.5: camada 4 no autostart (self-healing de sessão)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'E2b' "v1.5: camada 2 (E2b populate no build) presente"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'cachyos.gpg ausente' "v1.5: gate duro do keyring (fail no build, nunca no boot)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'populate archlinux cachyos' "v1.5: populate no build E2b E no chroot do alvo E10"
# v1.5.1: cura do run #40/#41 — E2 com conf efêmero (+elite-local offline, -CheckSpace)
# Causas provadas nos logs: (a) pacstrap -C NÃO copia o conf p/ o chroot (só -P)
# → /etc/pacman.conf do chroot = estoque do pacote pacman (CachyOS 7.1: CheckSpace
# ON) SEM [elite-local] → -S "target not found"; (b) CheckSpace lê o mtab do
# chroot (sem entrada "/") → "could not determine root mount point /" abortava
# QUALQUER install in-chroot com 84G livres (falha SILENCIOSA na v1.4 = ISO sem
# keyring = "unknown trust" do burn test; check_diskspace é gated pelo CheckSpace
# e SÓ existe no caminho de install — sync.c; -R/-Sy nunca passam por ele).
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'ELITE_PC_KR="\$\(mktemp\)"' "v1.5.1: E2 gera conf efêmero (mktemp — nunca vira arquivo da ISO)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'printf .\\n\[elite-local\]\\nSigLevel = Never\\nServer = file:///var/cache/elite-local' "v1.5.1: E2 conf efêmero declara [elite-local] file:// (repo DENTRO do chroot — offline-first REAL)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'CheckSpace\[\[:space:\]\]\*\$/d' "v1.5.1: E2 remove CheckSpace do conf efêmero (desliga a sonda de mtab que matava o commit)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'pacman --config "\$\{ELITE_PC_KR\}\.nc" -S --noconfirm cachyos-keyring' "v1.5.1: -S do E2 usa o conf sem CheckSpace (run #40/#41 nunca mais)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'pacman --config "\$\{ELITE_PC_KR\}\.nc" -U --noconfirm' "v1.5.1: fallback -U do E2 também sem CheckSpace (a escada inteira imune)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'rm -f "\$ELITE_PC_KR" "\$\{ELITE_PC_KR\}\.nc"' "v1.5.1: confs efêmeros removidos no fim do E2 (sem lixo no chroot)"
assert_nogrep "$REPO/elite/fragments/elite-customize.sh" '^pacman -S --noconfirm cachyos-keyring' "v1.5.1: NENHUM pacman in-chroot de install sem --config (o conf estoque tem CheckSpace)"
assert_grep "$REPO/scripts/apply-overlay.sh" 'craft-fix-keys' "v1.5: [9b] registra craft-fix-keys 0755 (203/EXEC nunca mais)"
# v1.6.1: idle/lock AJUSTÁVEL PELO USUÁRIO ("em quanto tempo o Pc entra
# em idle?" — dono): a receita swayidle INTEIRA (lock no timeout do conf
# + DPMS wlopm + resume + before-sleep) vive no craft-idle; o autostart
# só delega. Tempos no ~/.config/elite/idle.conf (defaults 10/15 — os da
# spec v1.5 viraram DEFAULT, não hardcode). Contratos completos adiante
# (bloco v1.6.1 · craft-idle).
assert_grep "$P/airootfs/usr/local/bin/craft-idle" "timeout [$]\(\(LOCK_MIN \* 60\)\) 'hyprlock'" "v1.6.1: lock no timeout do CONF (spec 10min vira default editável)"
assert_grep "$P/airootfs/usr/local/bin/craft-idle" "timeout [$]\(\(OFF_MIN \* 60\)\) 'wlopm --off" "v1.6.1: DPMS no timeout do CONF (tela APAGA — idle real, não tela fixa)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/autostart" 'swaylock -f|exec swaylock' "v1.5: invocação do swaylock EXTINTA do autostart (tela branca → hyprlock)"
# W-v clipboard + menu com os apps novos
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'W-v' "curadoria: W-v = histórico de clipboard"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'cliphist decode' "curadoria: pipe cliphist→fuzzel→wl-copy"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'Arquivos \(Thunar\)' "v1.5: menu Arquivos = Thunar (FM padrão da spec)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'command="thunar"' "v1.5: menu abre thunar direto (GUI)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'foot -e nano' "v1.5: menu Editor = nano no foot (helix saiu)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'papers' "v1.1: menu Leitor de PDF = papers (GTK4)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'foot -e impala' "v1.1: menu Rede = impala no foot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'foot -e bluetui' "v1.1: menu Bluetooth = bluetui no foot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'pwvucontrol' "v1.1: menu Mixer = pwvucontrol"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'foot -e 7z' "v1.1: menu Arquivos compactados = 7z no foot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'for b in brave librewolf' "v1.1: navegador do menu = brave em 1º"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'mousepad|nmtui|pulsemixer|file-roller|yazi|helix' "v1.1/v1.5: menu sem vestígio do app-layer legado/extinto"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'qalculate-gtk' "curadoria: qalculate no menu"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'nwg-look' "curadoria: nwg-look no menu"

# ── v1.1 · APP-STACK MODERNA (MEGA PROMPT): skel novo por dentro ────────
SKCFG="$P/airootfs/etc/skel/.config"
# brave: flags Wayland + aceleração de GPU completa
assert_file "$SKCFG/brave-flags.conf" "v1.1: brave-flags.conf no skel (lido pelo launcher do brave-origin — padrão chromium-flags)"
assert_grep "$SKCFG/brave-flags.conf" '^--ozone-platform=wayland$' "v1.1: brave — janelas nativas do compositor (Ozone)"
assert_grep "$SKCFG/brave-flags.conf" 'DefaultANGLEVulkan' "v1.1: brave — ANGLE sobre Vulkan"
assert_grep "$SKCFG/brave-flags.conf" 'WaylandWindowDecorations' "v1.1: brave — decorações Wayland"
assert_grep "$SKCFG/brave-flags.conf" '^--ignore-gpu-blocklist$' "v1.1: brave — sem blocklist de software rendering"
assert_grep "$SKCFG/brave-flags.conf" 'VaapiVideoDecodeLinuxGL' "v1.1: brave — VA-API documentado (comentado p/ rigs)"
# mimeapps: os apps padrão são os novos
assert_file "$SKCFG/mimeapps.list" "v1.1: mimeapps.list no skel"
assert_grep "$SKCFG/mimeapps.list" 'x-scheme-handler/https=brave-browser\.desktop' "v1.1: https abre brave"
assert_grep "$SKCFG/mimeapps.list" 'x-scheme-handler/http=brave-browser\.desktop' "v1.1: http abre brave"
assert_grep "$SKCFG/mimeapps.list" 'application/pdf=org\.gnome\.Papers\.desktop' "v1.1: PDF abre papers (GTK4)"
assert_grep "$SKCFG/mimeapps.list" 'image/png=imv\.desktop' "v1.1: imagens abrem imv (Wayland-nativo)"
assert_grep "$SKCFG/mimeapps.list" 'video/mp4=mpv\.desktop' "v1.1: vídeo abre mpv"
# v1.5: Thunar é o FM padrão (xdg-mime) — mimeapps declara o inode/directory
assert_grep "$SKCFG/mimeapps.list" '^inode/directory=thunar\.desktop$' "v1.5: pasta abre Thunar (xdg-mime default da spec)"
# v1.5: hyprlock — a tela de lock do rice (substitui o swaylock branco)
HLK="$SKCFG/hypr/hyprlock.conf"
assert_file "$HLK" "v1.5: hyprlock.conf no skel (lock estilizado)"
assert_grep "$HLK" 'path = screenshot' "v1.5: fundo = screenshot da tela (wlr-screencopy do labwc)"
assert_grep "$HLK" 'blur_passes = 3' "v1.5: blur alto no fundo"
assert_grep "$HLK" 'brightness = 0\.35' "v1.5: dim (brightness 0.35 — véu escuro)"
assert_grep "$HLK" 'text = \$TIME' "v1.5: relógio GRANDE (label \$TIME)"
assert_grep "$HLK" 'font_size = 96' "v1.5: relógio 96pt (topo/centro)"
assert_grep "$HLK" 'valign = top' "v1.5: relógio ancorado no TOPO (spec)"
assert_grep "$HLK" 'text = \$USER' "v1.5: nome do usuário acima do campo (spec)"
assert_grep "$HLK" 'pixmaps/elite/avatar\.png' "v1.5: avatar (image path absoluto determinístico)"
assert_grep "$HLK" 'rounding = -1' "v1.5: avatar circular (rounding -1)"
assert_grep "$HLK" 'border_color = rgba\(203, 166, 247' "v1.5: borda do avatar MAUVE (assinatura)"
assert_grep "$HLK" 'placeholder_text = .*Digite a senha para desbloquear' "v1.5: placeholder da spec (campo sempre visível — fade_on_empty false)"
assert_grep "$HLK" 'fail_text = .*Senha Incorreta' "v1.5: feedback de FALHA em texto (spec)"
assert_grep "$HLK" 'check_text = .*Validando' "v1.5: feedback de VALIDAÇÃO em texto (spec)"
assert_grep "$HLK" 'fail_color = rgba\(243, 139, 168' "v1.5: falha em VERMELHO Catppuccin (spec)"
assert_grep "$HLK" 'dots_text_format = \*' "v1.5: asteriscos como feedback de digitação (spec)"
assert_grep "$HLK" 'fade_on_empty = false' "v1.5: campo de senha fixo (não some vazio — spec)"
assert_grep "$HLK" 'outline_thickness = 3' "v1.5: campo com borda estilizada (outline mauve)"
assert_grep "$HLK" 'outer_color = rgba\(203, 166, 247' "v1.5: borda do campo MAUVE"
assert_grep "$HLK" '\$font = JetBrainsMono NF' "v1.5: fonte do lock = a REAL do rice (definida em \$font)"
# v1.6: avatar segue no overlay (hyprlock); os PNGs de dock (terminal/files/
# web) saíram JUNTO com os módulos image# (fix waybar #5051) — glifos mandam
assert_file "$P/airootfs/usr/share/pixmaps/elite/avatar.png" "v1.6: pixmaps/elite/avatar.png (hyprlock usa)"
for gone in terminal files web; do
  assert_nofile "$P/airootfs/usr/share/pixmaps/elite/${gone}.png" "v1.6: pixmaps/elite/${gone}.png REMOVIDO (image# extinto — limpeza)"
done
assert_file "$P/airootfs/etc/skel/.face.icon" "v1.5: ~/.face.icon no skel (avatar p/ login managers + personalização)"
# v1.5: craft-lock roteia pro hyprlock
assert_grep "$P/airootfs/usr/local/bin/craft-lock" 'exec hyprlock' "v1.5: craft-lock executa hyprlock (tela branca extinta)"
assert_nogrep "$P/airootfs/usr/local/bin/craft-lock" 'command -v swaylock|exec swaylock' "v1.5: craft-lock sem INVOCAÇÃO de swaylock (só a história no comentário)"
assert_nogrep "$P/airootfs/usr/local/bin/craft-logout" 'exec swaylock' "v1.5: craft-logout trava com hyprlock"
# rc.xml: keybinds da stack nova
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" '<keybind key="W-f">' "v1.5: W-f existe (FM)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'command="thunar"' "v1.5: rc.xml W-f → thunar (FM padrão GUI)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'foot -e nano' "v1.5: rc.xml W-e → nano no foot (editor)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'foot -e impala' "v1.1: rc.xml W-n → impala no foot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'foot -e bluetui' "v1.1: rc.xml W-S-b → bluetui no foot (o bind que o craft-bat citava)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'for b in brave librewolf' "v1.1: rc.xml navegador = brave em 1º (cadeia)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'command="(foot -e )?(yazi|helix|nvtop|nmtui|mousepad)' "v1.5: rc.xml sem COMANDO de app extinto nos binds"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'identifier="com\.github\.dominiksalvet\.pwvucontrol"' \
  "v1.1: windowRule do mixer aponta pwvucontrol (identificador novo)"
# waybar dock: launchers convertidos (v1.5: ícones reais)
assert_grep "$SKCFG/waybar/config.dock" '"on-click": "brave"' "v1.1: dock abre brave (era firefox)"
# overlay de REDE: sysctl BBR + módulo carregado antes do systemd-sysctl
assert_file "$P/airootfs/etc/sysctl.d/99-elite-net.conf" "v1.1: /etc/sysctl.d/99-elite-net.conf na ISO (BBR assado)"
assert_grep "$P/airootfs/etc/sysctl.d/99-elite-net.conf" '^net\.core\.default_qdisc = fq$' "v1.1: qdisc fq (BBR exige)"
assert_grep "$P/airootfs/etc/sysctl.d/99-elite-net.conf" '^net\.ipv4\.tcp_congestion_control = bbr$' "v1.1: congestion control bbr"
assert_file "$P/airootfs/etc/modules-load.d/elite-bbr.conf" "v1.1: modules-load.d/elite-bbr.conf na ISO"
assert_grep "$P/airootfs/etc/modules-load.d/elite-bbr.conf" '^tcp_bbr$' "v1.1: módulo tcp_bbr carrega antes do sysctl"
# craft-drawer: o Launchpad abre arquivos no Thunar (FM padrão v1.5)
assert_grep "$P/airootfs/usr/local/bin/craft-drawer" '-fm "thunar"' "v1.5: craft-drawer -fm thunar (era yazi no foot)"
# build/CI v1.1→v1.4: estágio brave-origin (oficial) e AUR pwvucontrol
assert_grep "$REPO/.ci/build.sh" 'pkgname=brave-origin' "v1.4: estágio brave-origin → /var/cache/elite-local (release oficial pinado)"
assert_grep "$REPO/.ci/build.sh" 'aur_build pwvucontrol' "v1.1: estágio AUR — pwvucontrol → /var/cache/elite-local"
assert_grep "$REPO/.ci/build.sh" 'sudoers\.d/builder' "v1.1: sudoers descartável do builder (makepkg -s)"
assert_grep "$REPO/.github/workflows/build.yml" '-m 7168' "v1.1: verify com QEMU de 7168 MB (copy-to-RAM)"
assert_grep "$REPO/scripts/qemu-boot-test.sh" '-m 7168' "v1.1: qemu-boot-test com 7168 MB (idem local)"

# ── v1.0.3: FIX do freeze em hardware real (diag-boot3 · Task 43) ─────
# O DefaultTimeoutStartSec=15s do cachyos-settings derruba serviços
# Type=notify em restart-loop eterno no boot a frio (resolved não fica
# pronto em 15s → splash congela — o sintoma do rig B). Drop-in /etc/*
# tem precedência sobre o /usr/lib/* do pacote.
assert_file "$P/airootfs/etc/systemd/system.conf.d/00-elite-timeout.conf" "fix freeze: drop-in de timeout no airootfs"
assert_grep "$P/airootfs/etc/systemd/system.conf.d/00-elite-timeout.conf" '^DefaultTimeoutStartSec=90s$' "fix freeze: start timeout 90s (vence o 15s do cachyos-settings)"
assert_grep "$P/airootfs/etc/systemd/system.conf.d/00-elite-timeout.conf" '^DefaultTimeoutStopSec=90s$' "fix freeze: stop timeout 90s (o 10s do cachyos era igualmente perigoso no shutdown)"

# ── v1.0.3→v1.1: [9b] file_permissions — 13 caminhos 0:0:755 no profiledef ─
PD="$P/profiledef.sh"
for p in /usr/local/bin/elite-tune /usr/local/bin/elite-status /usr/local/bin/fg-booster \
         /usr/local/bin/craft-hello /usr/local/bin/craft-update /usr/local/bin/craft-clean \
         /usr/local/bin/craft-rollback /usr/local/bin/craft-lock /usr/local/bin/craft-logout \
         /usr/local/bin/craft-shot /usr/local/bin/craft-bat /usr/local/bin/craft-pin \
         /etc/skel/.config/labwc/autostart; do
  assert_grep "$PD" "\\[\"$p\"\\]=\"0:0:755\"" "v1.0.3 [9b]: 0755 p/ $p"
done

# ── v1.0.3/v1.1: E5 (Calamares) e E9+E12 (skel/environment) EXECUTADOS ──
# extrai os blocos do fragmento, aponta os caminhos pro profile de teste
# e roda: a cirurgia labwc tem que produzir exatamente o esperado.
FRAG="$REPO/elite/fragments/elite-customize.sh"
CFX="$P/airootfs/etc/calamares"
sed -n '/^## \[E5\]/,/^## \[E6\]/p' "$FRAG" \
  | sed -e "s|^CC=\"/etc/calamares\"|CC=\"$CFX\"|" \
        -e "s|/usr/bin/chrooted_autologin\.sh|$P/airootfs/usr/bin/chrooted_autologin.sh|g" \
  > "$WORK/e5-block.sh"
if bash "$WORK/e5-block.sh" 2>"$WORK/e5.err"; then
  ok "E5: bloco Calamares executa limpo (CC → fixture)"
else
  fail "E5: bloco Calamares executa limpo" "$(head -c 200 "$WORK/e5.err")"
fi
# E5a (v1.1): a entrada vmlinuz-linux do unpackfs VIROU BORE no lugar (sed,
# não append — kernel único; fallback de append só sem a linha upstream)
UFS="$CFX/modules/unpackfs.conf"
assert_grep "$UFS" 'source: "/run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux-cachyos-bore"' \
  "E5a: source do unpackfs substituído no LUGAR (vmlinuz-linux → BORE)"
assert_grep "$UFS" 'destination: "/boot/vmlinuz-linux-cachyos-bore"' \
  "E5a: destination do unpackfs aponta o BORE"
assert_nogrep "$UFS" 'vmlinuz-linux"' "E5a: nenhum vmlinuz-linux stock com aspa final (substituição total)"
assert_grep "$UFS" 'destination: "/boot/initramfs-linux\.img"' "E5a: initramfs stock do upstream PRESERVADO (só o kernel é único)"
# E5b (v1.1): initcpio@elite entra na sequência exec e o módulo stock SAI
SET="$CFX/settings.conf"
assert_grep "$SET" 'config:   initcpio_elite\.conf' "E5b: módulo initcpio@elite (com config própria) inserido"
assert_grep "$SET" '^  - initcpio@elite$' "E5b: sequência exec ganha '  - initcpio@elite'"
assert_nogrep "$SET" '^  - initcpio$' "E5b: módulo stock '  - initcpio' REMOVIDO (kernel único BORE)"
assert_grep "$SET" 'config:   shellprocess_btrfs\.conf' "E5b: shellprocess_btrfs segue (E10 roda depois dele)"
assert_file "$CFX/modules/initcpio_elite.conf" "E5b: initcpio_elite.conf criado"
assert_grep "$CFX/modules/initcpio_elite.conf" '^kernel: linux-cachyos-bore$' "E5b: initcpio_elite aponta o kernel BORE"
PCC="$CFX/modules/packagechooser.conf"
assert_grep "$PCC" '^    - id: labwc$' "E5c: packagechooser tem o item labwc"
assert_nogrep "$PCC" '- id: (openbox|bspwm|sway|everything)$' "E5c: itens openbox/bspwm/sway/everything fora"
assert_grep "$PCC" '^default: labwc$' "E5c: default = labwc"
assert_grep "$PCC" 'name: "Archcraft Elite"' "E5c: nome do item = Archcraft Elite"
assert_grep "$CFX/modules/contextualprocess_autologin.conf" 'chrooted_autologin\.sh --labwc' "E5d: autologin contextual → --labwc"
assert_nogrep "$CFX/modules/contextualprocess_autologin.conf" '--(openbox|bspwm|sway|everything)$' "E5d: nenhum caminho de sessão antiga"
AI="$P/airootfs/usr/bin/chrooted_autologin.sh"
assert_grep "$AI" "'--labwc' \]\]; then" "E5e: chrooted_autologin aceita --labwc"
assert_grep "$AI" "enable_autologin 'labwc'" "E5e: sessão configurada = labwc"
assert_nogrep "$AI" "enable_autologin 'openbox'" "E5e: nenhum 'openbox' residual"
assert_grep "$CFX/modules/partition.conf" 'defaultFileSystemType:  "btrfs"' "E5f: btrfs default no installer"

# ── v1.1: E11 (dkms gate + regen do live) e E10 (per-rig) como contratos ──
#  E11 roda DENTRO do chroot do build (ls/mkinitcpio reais) — aqui o contrato
#  é o texto do fragmento, com o bloco isolado (o E10 também tem mkinitcpio)
sed -n '/^## \[E11\]/,/^## \[E5\]/p' "$FRAG" > "$WORK/e11-block.txt"
assert_grep "$WORK/e11-block.txt" 'updates/dkms/nvidia\.ko' \
  "E11: gate duro — exige nvidia.ko* em /usr/lib/modules/*cachyos-bore*/updates/dkms"
assert_grep "$WORK/e11-block.txt" 'ELITE-FAIL' "E11: falha do gate é ELITE-FAIL (build morre, não o boot)"
assert_grep "$WORK/e11-block.txt" 'mkinitcpio -p linux-cachyos-bore' \
  "E11: regenera o initramfs do live com o preset BORE (dentro do E11)"
assert_grep "$WORK/e11-block.txt" 'HOOKS=\(base udev microcode plymouth modconf kms' \
  "E11: conf.d/archiso.conf recriado com o hook kms (early-KMS nos 2 rigs)"
assert_grep "$WORK/e11-block.txt" 'COMPRESSION_OPTIONS=\(-9e\)' "E11: compressão xz -9e (verbatim do upstream)"
assert_grep "$WORK/e11-block.txt" 'rm -rf /etc/mkinitcpio\.conf\.d' \
  "E11: conf.d é REMOVIDO depois (não pode ir pro alvo — vence o initcpio@elite)"
sed -n '/^## \[E10\]/,$p' "$FRAG" > "$WORK/e10-block.txt"
assert_grep "$WORK/e10-block.txt" '0x10de\) ELITE_GPU=nvidia' "E10: detector de vendor (0x10de → nvidia)"
assert_grep "$WORK/e10-block.txt" '0x1002\) \[ "\$ELITE_GPU" != "nvidia" \] && ELITE_GPU=amd' \
  "E10: detector de vendor (0x1002 → amd, nvidia vence)"
assert_grep "$WORK/e10-block.txt" 'MODULES=\(amdgpu\)' "E10: rig AMD → MODULES=(amdgpu) no mkinitcpio do alvo"
assert_grep "$WORK/e10-block.txt" 'MODULES=\(nvidia nvidia_modeset nvidia_uvm nvidia_drm\)' \
  "E10: rig NVIDIA → MODULES=(nvidia …) no alvo"
assert_grep "$WORK/e10-block.txt" 'pacman -Rdd --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils' \
  "E10: rig AMD limpa o stack NVIDIA inteiro do alvo (dkms incluído)"
assert_grep "$WORK/e10-block.txt" 'nvidia_drm\.fbdev=1' "E10: GRUB do rig NVIDIA com modeset+fbdev"
assert_grep "$WORK/e10-block.txt" 'amdgpu\.ppfeaturemask=0xffffffff' "E10: GRUB do rig AMD com ppfeaturemask"
assert_grep "$WORK/e10-block.txt" 'NVreg_PreserveVideoMemoryAllocations=1' \
  "E10: modprobe.d NVIDIA preserva VRAM em suspend"
assert_grep "$WORK/e10-block.txt" 'rm -f "\$\{ROOT\}"/usr/lib/modules/\*/updates/dkms/nvidia\*\.ko\*' \
  "E10: rig AMD varre os .ko dkms do alvo (nada de driver alheio no disco)"
assert_grep "$WORK/e10-block.txt" 'for kv in /run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-\*' \
  "E10 (v1.0.4): recopia TODOS os vmlinuz-* do pendrive (fix btrfs truncado)"
assert_grep "$WORK/e10-block.txt" 'arch-chroot "\$\{ROOT\}" mkinitcpio -p linux-cachyos-bore' \
  "E10 (v1.0.4): regenera initramfs do BORE no alvo (DEPOIS do perfil de GPU)"

# E9+E12 (v1.1): skel sujo (dirs órfãos da purga GTK3 incluso) + environment
SKEL="$P/airootfs/etc/skel"
ENVF="$P/airootfs/etc/environment"
for d in openbox bspwm polybar tint2 rofi dunst alacritty kitty thunar zathura \
         mousepad file-roller blueman pavucontrol; do
  mkdir -p "$SKEL/.config/$d"
done
sed -n '/^## \[E9\]/,/^## \[E10\]/p' "$FRAG" \
  | sed -e "s|/etc/skel|$SKEL|g" -e "s|/etc/environment|$ENVF|g" > "$WORK/e912-block.sh"
if bash "$WORK/e912-block.sh" 2>"$WORK/e912.err"; then
  ok "E9+E12: bloco skel+environment executa limpo (redirecionado ao fixture)"
else
  fail "E9+E12: bloco skel+environment" "$(head -c 200 "$WORK/e912.err")"
fi
dead=0
for d in openbox bspwm polybar tint2 rofi dunst alacritty kitty zathura \
         mousepad file-roller blueman pavucontrol yazi helix; do
  [[ -d "$SKEL/.config/$d" ]] && dead=$((dead+1))
done
assert_eq "$dead" "0" "E9: skel sem diretórios órfãos (v1.1 purga GTK3 + v1.5 yazi/helix varridos)"
assert_file "$SKEL/.config/labwc/rc.xml" "E9: configs labwc sobrevivem à limpeza"
assert_file "$SKEL/.config/hypr/hyprlock.conf" "E9/v1.5: config do hyprlock sobrevive à limpeza"
assert_file "$SKEL/.config/foot/foot.ini" "E9: config do foot sobrevive à limpeza"
# E12: os 3 seds no /etc/environment (upstream nano/firefox/alacritty → v1.5)
assert_grep "$ENVF" '^EDITOR=nano$' "E12/v1.5: EDITOR=nano (helix saiu — editor do terminal)"
assert_grep "$ENVF" '^BROWSER=brave$' "E12: BROWSER=brave (firefox saiu)"
assert_grep "$ENVF" '^TERMINAL=foot$' "E12: TERMINAL=foot (alacritty saiu na v1.0.3)"
assert_grep "$ENVF" '^QT_QPA_PLATFORMTHEME=qt6ct$' "E12: o RESTO do environment upstream é preservado (sed no lugar)"
assert_nogrep "$ENVF" 'alacritty|firefox|helix' "E12/v1.5: nenhum valor legado/extinto sobrevive nas 3 chaves"

PC="$P/pacman.conf"
assert_grep "$PC" '^\[elite-local\]' "cadeia A: repo [elite-local] injetado"
el=$(grep -n '^\[elite-local\]' "$PC" | cut -d: -f1); ac=$(grep -n '^\[archcraft\]' "$PC" | head -1 | cut -d: -f1)
[[ -n "$el" && -n "$ac" && "$el" -lt "$ac" ]] \
  && ok "cadeia A: [elite-local] ANTES de [archcraft] (file:// resolve primeiro)" \
  || fail "cadeia A: [elite-local] ANTES de [archcraft]" "el=$el ac=$ac"
assert_grep "$PC" '^SigLevel = Never$' "cadeia A: [archcraft] SigLevel → Never (zero sondas .sig)"
cv=$(grep -n '^\[cachyos-v3\]' "$PC" | head -1 | cut -d: -f1); co=$(grep -n '^\[core\]' "$PC" | head -1 | cut -d: -f1)
[[ -n "$cv" && -n "$co" && "$cv" -lt "$co" ]] \
  && ok "cadeia A: trio cachyos-v3 ANTES de [core] (v3 ganha a resolução)" \
  || fail "cadeia A: trio antes de [core]" "cv=$cv co=$co"
assert_grep "$PC" '^Architecture = x86_64 x86_64_v3$' "cadeia A: Architecture aceita v3"
assert_grep "$PC" '^XferCommand = /usr/bin/curl' "cadeia A: XferCommand resiliente"
assert_grep "$PC" '^ParallelDownloads = 10$' "cadeia A: ParallelDownloads = 10"
assert_nogrep "$PC" '^DownloadUser' "cadeia A: DownloadUser removido (o container não deixa)"

# ── v1.1: MENU DE BOOT = 3 ENTRADAS, kernel BORE único, copy-to-RAM ────
#   01/default AMD · copytoram=y · amdgpu.ppfeaturemask
#   03/NVIDIA  · copytoram=y · nvidia_drm.modeset+fbdev (dkms pré-compilado)
#   04/rescue  · copytoram=n · nomodeset
# PENDÊNCIAS DE PRODUTO (bugs da cirurgia [6] v1.1, anotadas no worklog —
# os "pins" abaixo travam o estado ATUAL para que o fix venha acompanhado
# da atualização destas peças; NÃO são o contrato desejado do manifesto):
#   p1: syslinux — blocos arch/archnomodeset seguem em vmlinuz-linux (o awk
#       [6.1b] só reescreve LINUX/INITRD do archnonfree; o default BIOS boota
#       um kernel que não existe mais na ISO — a própria guarda de sanidade
#       do produto dispara o AVISO)
#   p2: grub — o menuentry OpenSource (archcraftos) NÃO é removido (a cadeia
#       de ifs do awk [6.1c] sobrescreve cur=del com cur=def via [^p])
#   p3: efiboot — a entrada 03 ganha sufixo DUPLICADO (cat> com BORE e o loop
#       converte de novo: vmlinuz-linux-cachyos-bore-cachyos-bore)

E01="$P/efiboot/loader/entries/01-archiso-linux.conf"
E02="$P/efiboot/loader/entries/02-archiso-linux-open-source.conf"
E03="$P/efiboot/loader/entries/03-archiso-linux-nvidia.conf"
E04="$P/efiboot/loader/entries/04-archiso-linux-nomodeset.conf"
E05="$P/efiboot/loader/entries/05-archiso-linux-ram.conf"

# 01 default: AMD · Copy to RAM (BORE + copytoram=y + ppfeaturemask)
assert_grep "$E01" 'vmlinuz-linux-cachyos-bore' "v1.1: entrada default (UEFI) → kernel BORE"
assert_grep "$E01" 'initramfs-linux-cachyos-bore\.img' "v1.1: initramfs default → BORE"
assert_nogrep "$E01" 'vmlinuz-linux([^-]|$)' "v1.1: default sem vestígio do kernel stock (mesmo guard do produto)"
assert_grep "$E01" 'copytoram=y' "v1.1: default com copytoram=y (o live inteiro na RAM)"
assert_grep "$E01" 'amdgpu\.ppfeaturemask=0xffffffff' "v1.1: default com ppfeaturemask AMD (undervolt/OC no LACT)"
assert_grep "$E01" 'UEFI, AMD · Copy to RAM' "v1.1: título default = AMD · Copy to RAM"
assert_grep "$E01" 'systemd\.default_timeout_start_sec=90' "v1.0.4: timeout 90s no cmdline do default"

# 02 OpenSource: REMOVIDA do menu (redundante — nouveau não existe no Blackwell)
assert_nofile "$E02" "v1.1: entrada OpenSource (UEFI) APAGADA — menu de 3"
# 05 Copy to RAM: APAGADA (o default AGORA copia p/ RAM)
assert_nofile "$E05" "v1.1: entrada 05 Copy to RAM (UEFI) apagada — default já é copy-to-RAM"

# 03 NVIDIA: reescrita íntegra — BORE + dkms + modeset/fbdev + copytoram=y
assert_grep "$E03" 'NVIDIA · Copy to RAM' "v1.1: título NVIDIA = · Copy to RAM"
assert_grep "$E03" 'copytoram=y' "v1.1: entrada NVIDIA com copytoram=y"
assert_grep "$E03" 'nvidia_drm\.modeset=1 nvidia_drm\.fbdev=1' "v1.1: NVIDIA com modeset+fbdev (Wayland)"
assert_grep "$E03" 'module_blacklist=nouveau' "v1.1: NVIDIA com nouveau no blacklist"
assert_grep "$E03" 'initramfs-linux-cachyos-bore\.img' "v1.1: initramfs NVIDIA = a MESMA do BORE (hook kms)"
assert_grep "$E03" 'vmlinuz-linux-cachyos-bore-cachyos-bore' \
  "PENDÊNCIA p3 (produto): 03 com sufixo DUPLICADO 'bore-cachyos-bore' (cat> + loop duplo) — fix deve deixar 1×"
assert_grep "$E03" '^sort-key 03$' "v1.1: sort-key 03 preservado (ordem do menu)"

# 04 rescue: nomodeset, copytoram=n (máquina com pouca RAM)
assert_grep "$E04" 'vmlinuz-linux-cachyos-bore' "v1.1: entrada rescue (UEFI) → kernel BORE"
assert_grep "$E04" 'initramfs-linux-cachyos-bore\.img' "v1.1: initramfs rescue → BORE"
assert_grep "$E04" 'copytoram=n' "v1.1: rescue mantém copytoram=n (pouca RAM)"
assert_grep "$E04" 'nomodeset' "v1.1: rescue com nomodeset"

# syslinux (BIOS): archfree FORA; archnonfree BORE+NVIDIA; default AMD
SL="$P/syslinux/archiso_sys-linux.cfg"
assert_nogrep "$SL" '^LABEL archfree' "v1.1: syslinux — bloco OpenSource (archfree) REMOVIDO"
assert_nogrep "$SL" '^LABEL archram' "v1.1: syslinux — LABEL archram (v1.0.4) não existe mais"
grep -A9 '^LABEL archnonfree' "$SL" | grep -q 'vmlinuz-linux-cachyos-bore' \
  && ok "v1.1: syslinux archnonfree → kernel BORE (dkms pré-compilado)" \
  || fail "v1.1: syslinux archnonfree → kernel BORE" "bloco não convertido"
grep -A9 '^LABEL archnonfree' "$SL" | grep -q 'initramfs-linux-cachyos-bore\.img' \
  && ok "v1.1: syslinux archnonfree → initramfs BORE" \
  || fail "v1.1: syslinux archnonfree → initramfs BORE" "initrd não convertido"
grep -A9 '^LABEL archnonfree' "$SL" | grep -q 'nvidia_drm\.modeset=1 nvidia_drm\.fbdev=1' \
  && ok "v1.1: syslinux archnonfree com modeset+fbdev" \
  || fail "v1.1: syslinux archnonfree com modeset+fbdev" "params nvidia ausentes"
grep -A9 '^LABEL archnonfree' "$SL" | grep -q 'copytoram=y' \
  && ok "v1.1: syslinux archnonfree com copytoram=y" \
  || fail "v1.1: syslinux archnonfree com copytoram=y" "copytoram=n sobrou"
assert_grep "$SL" 'MENU LABEL Boot Archcraft Elite \(%ARCH%, BIOS, NVIDIA · Copy to RAM\)' \
  "v1.1: syslinux título NVIDIA rebatizado"
grep -A9 '^LABEL arch$' "$SL" | grep -q 'copytoram=y' \
  && ok "v1.1: syslinux default (arch) com copytoram=y" \
  || fail "v1.1: syslinux default com copytoram=y" "APPEND não patchado"
grep -A9 '^LABEL arch$' "$SL" | grep -q 'amdgpu\.ppfeaturemask=0xffffffff' \
  && ok "v1.1: syslinux default com ppfeaturemask AMD" \
  || fail "v1.1: syslinux default com ppfeaturemask" "APPEND sem o param"
assert_grep "$SL" 'MENU LABEL Boot Archcraft Elite \(%ARCH%, BIOS, AMD · Copy to RAM\)' \
  "v1.1: syslinux título default = AMD · Copy to RAM"
grep -A9 '^LABEL archnomodeset' "$SL" | grep -q 'copytoram=n' \
  && ok "v1.1: syslinux rescue mantém copytoram=n" \
  || fail "v1.1: syslinux rescue copytoram=n" "rescue virou copy-to-RAM?"
# p1: blocos default/rescue AINDA no kernel stock (trava do estado atual —
# o manifesto diz "NENHUMA entrada com vmlinuz-linux puro"; o guard do
# próprio produto AVISA; fix do awk [6.1b] deve zerar esta contagem)
assert_eq "$(grep -cE 'vmlinuz-linux$' "$SL")" "2" \
  "PENDÊNCIA p1 (produto): 2 blocos syslinux (default+rescue) ainda em vmlinuz-linux — fix deve zerar"

# grub (BIOS/loopback): archcraftpn BORE+NVIDIA; default AMD; rescue BORE
GR="$P/grub/grub.cfg"
assert_grep "$GR" "--id 'archcraftpn'" "v1.1: menuentry NVIDIA (archcraftpn) presente"
if grep -A4 -- "--id 'archcraftpn'" "$GR" | grep -q 'nvidia_drm\.modeset=1 nvidia_drm\.fbdev=1'; then
  ok "v1.1: bloco NVIDIA com modeset+fbdev (kernel BORE + dkms)"
else
  fail "v1.1: bloco NVIDIA com modeset+fbdev" "params nvidia ausentes"
fi
if grep -A4 -- "--id 'archcraftpn'" "$GR" | grep -q 'vmlinuz-linux-cachyos-bore'; then
  ok "v1.1: bloco NVIDIA no kernel BORE (era stock até a v1.0.4)"
else
  fail "v1.1: bloco NVIDIA no kernel BORE" "não convertido"
fi
assert_nogrep "$GR" 'initramfs-linux-nvidia\.img' "v1.1: initramfs-nvidia.img exclusivo do stock sumiu"
if grep -A4 -- "--id 'archcraft'" "$GR" | grep -q 'copytoram=y'; then
  ok "v1.1: bloco default com copytoram=y"
else
  fail "v1.1: bloco default com copytoram=y" "cmdline sem copy-to-RAM"
fi
if grep -A4 -- "--id 'archcraft'" "$GR" | grep -q 'amdgpu\.ppfeaturemask=0xffffffff'; then
  ok "v1.1: bloco default com ppfeaturemask AMD"
else
  fail "v1.1: bloco default com ppfeaturemask" "param ausente"
fi
assert_grep "$GR" 'menuentry "Boot Archcraft Elite \(%ARCH%, \$\{archiso_platform\}, AMD · Copy to RAM\)"' \
  "v1.1: título default (grub) = AMD · Copy to RAM"
if grep -A4 -- "--id 'archcraftnm'" "$GR" | grep -q 'copytoram=n'; then
  ok "v1.1: rescue (archcraftnm) mantém copytoram=n"
else
  fail "v1.1: rescue copytoram=n" "rescue virou copy-to-RAM?"
fi
if grep -A4 -- "--id 'archcraftnm'" "$GR" | grep -q 'vmlinuz-linux-cachyos-bore'; then
  ok "v1.1: rescue no kernel BORE (conversão completa)"
else
  fail "v1.1: rescue no kernel BORE" "não convertido"
fi
assert_nogrep "$GR" "--id 'archcraftram'" "v1.1: menuentry RAM (v1.0.4) não existe mais"
# p2: o menuentry OpenSource devia SAIR (manifesto) — o awk não consegue (del
# sobrescrito por def); travado como estado atual: fix = peça vira nogrep
assert_grep "$GR" "--id 'archcraftos'" \
  "PENDÊNCIA p2 (produto): menuentry OpenSource AINDA presente (del→def no awk) — fix deve remover"
assert_eq "$(grep -c 'vmlinuz-linux-cachyos-bore' "$GR")" "4" \
  "v1.1: 4 blocos grub no BORE (def+os+nv+nm — p2 explica o 'os'; fix → 3)"
# extras upstream (memtest/shutdown) intocados pela conversão
if grep -A2 "class memtest" "$GR" | grep -q 'cachyos'; then
  fail "v1.1: memtest intocado pela conversão" "ganhou kernel BORE por engano"
else
  ok "v1.1: memtest/shutdown sobrevivem sem conversão (awk escopo certo)"
fi

# loopback.cfg (VENTOY): mesma cirurgia — 4 blocos, NVIDIA BORE+fbdev
LB="$P/grub/loopback.cfg"
if grep -A4 -- "--id 'archcraftpn'" "$LB" | grep -q 'nvidia_drm\.fbdev=1'; then
  ok "v1.1: loopback (Ventoy) NVIDIA com fbdev"
else
  fail "v1.1: loopback NVIDIA com fbdev" "params ausentes"
fi
if grep -A4 -- "--id 'archcraftpn'" "$LB" | grep -q 'vmlinuz-linux-cachyos-bore'; then
  ok "v1.1: loopback NVIDIA no kernel BORE"
else
  fail "v1.1: loopback NVIDIA no kernel BORE" "não convertido"
fi
if grep -A4 -- "--id 'archcraft'" "$LB" | grep -q 'amdgpu\.ppfeaturemask'; then
  ok "v1.1: loopback default com ppfeaturemask"
else
  fail "v1.1: loopback default com ppfeaturemask" "param ausente"
fi
assert_grep "$LB" "--id 'archcraftos'" \
  "PENDÊNCIA p2 (produto): loopback OpenSource AINDA presente (idem grub.cfg)"

W="$P/airootfs/etc/systemd/system/multi-user.target.wants"
[[ ! -L "$W/cups.service" && ! -L "$W/vmtoolsd.service" ]] \
  && ok "cadeia A: wants cups/vmtoolsd removidos (debloat de serviços)" \
  || fail "cadeia A: wants cups/vmtoolsd removidos" "sobrou link"
[[ -L "$W/sshd.service" ]] \
  && ok "cadeia A: sobrevivente sshd.service não foi punido por engano" \
  || fail "cadeia A: sobrevivente sshd.service" "link sumiu — padrão de delete largo demais"

CS="$P/airootfs/root/customize_airootfs.sh"
# v1.1 build #51: o customize upstream RESSUCITA o linux.preset (cat > no
# bloco "Fix Initrd Generation in Installed System") DEPOIS que o [6.3] do
# overlay apagou o arquivo estático do profile — o E6 do fragmento Elite
# (anexado AO FINAL do customize) precisa matá-lo de novo dentro do chroot.
assert_grep "$CS" 'cat > "/etc/mkinitcpio\.d/linux\.preset"' \
  "fixture #51: bloco de regeneração upstream presente (a armadilha reproduzida)"
assert_grep "$CS" '^rm -f /etc/mkinitcpio\.d/linux\.preset' \
  "E6: preset stock ressuscitado é removido de novo (kernel único BORE)"
CATLINE=$(grep -n 'cat > "/etc/mkinitcpio\.d/linux\.preset"' "$CS" | head -1 | cut -d: -f1)
RMLINE=$(grep -n '^rm -f /etc/mkinitcpio\.d/linux\.preset' "$CS" | head -1 | cut -d: -f1)
if [[ -n "${CATLINE:-}" && -n "${RMLINE:-}" && "$RMLINE" -gt "$CATLINE" ]]; then
  ok "E6: o rm roda DEPOIS do cat upstream (fragmento anexado ao final — ordem certa)"
else
  fail "E6: ordem cat→rm" "rm do E6 não está depois do cat upstream (linha $RMLINE vs $CATLINE)"
fi
assert_eq "$(grep -c '\[\[ -f /etc/skel/.config/sway/scripts/startup \]\]' "$CS")" "2" \
  "cadeia A: guarda sway ×2 (o fix do run #17 aplicado no customize)"
# [8.6] guards da curadoria v1.0.3: openbox/bspwm/scripts/screenlayout
# (o run da 2256d0a morreu no 'sed: can't read openbox/autostart' —
# set -e do customize upstream + sessões extintas)
assert_eq "$(grep -c '\[\[ -f /etc/skel/.config/openbox/autostart \]\]' "$CS")" "2" \
  "curadoria: guarda openbox ×2 no customize (fix do run 2256d0a)"
assert_eq "$(grep -c '\[\[ -f /etc/skel/.config/bspwm/bspwmrc \]\]' "$CS")" "2" \
  "curadoria: guarda bspwm ×2 no customize"
assert_grep "$CS" '\[\[ -d /usr/share/archcraft/scripts \]\]' \
  "curadoria: guarda ln-s archcraft-scripts (pacote removido)"
assert_grep "$CS" '\[\[ -f /etc/skel/\.screenlayout/my-layout\.sh \]\]' \
  "curadoria: guarda chmod screenlayout (skeleton removido)"
# customize resultante continua sintaticamente válido
assert_rc0 "curadoria: customize com guards é bash -n válido" bash -n "$CS"
assert_grep "$CS" 'ELITE_KEY=' "cadeia A: fragmento E0–E8 anexado ao customize"
cmp -s "$P/airootfs/usr/local/bin/elite-tune" "$REPO/elite/airootfs/usr/local/bin/elite-tune" \
  && ok "cadeia A: elite-tune idêntico ao overlay (rsync sem corrupção)" \
  || fail "cadeia A: elite-tune idêntico ao overlay" "diff no airootfs"
assert_file "$P/airootfs/usr/local/bin/hello-upstream" "cadeia A: arquivo upstream pré-existente não apagado"
assert_grep "$P/profiledef.sh" 'iso_name="archcraft-elite"' "cadeia A: ISO rebatizada archcraft-elite"
assert_nogrep "$P/mkarchcraftiso" 'pacstrap.* -i ' "cadeia A: pacstrap não-interativo (sem -i)"

# ════════════════════════════════════════════════════════════════════
# 4.B o ciclo split → hash → reassemble → conferir (o caminho da release,
# em miniatura: 5 MiB, mesmas regras do build.yml)
# ════════════════════════════════════════════════════════════════════
CH="$WORK/chain"; rm -rf "$CH"; mkdir -p "$CH"
head -c 5242880 /dev/urandom > "$CH/mini.bin"
ISO="mini.bin"
( cd "$CH" && sha256sum -- "$ISO" > sha256sums.txt )
( cd "$CH" && split -b 2097152 -d "$ISO" "${ISO}.part-" && rm -f "$ISO" )
( cd "$CH" && sha256sum -- "${ISO}.part-"* >> sha256sums.txt )
assert_file "$CH/mini.bin.part-00" "cadeia B: split produziu part-00"
parts=("$CH"/mini.bin.part-*)
assert_eq "${#parts[@]}" "3" "cadeia B: 3 partes (2 MiB + 2 MiB + 1 MiB)"
# o usuário final: junta e confere EXATAMENTE como o JUNTAR-ISO.md manda
( cd "$CH" && cat "${ISO}.part-"* > "$ISO" )
verif=$( cd "$CH" && sha256sum -c <(grep -E "part|$ISO\$" sha256sums.txt) 2>&1 )
assert_match "$verif" 'mini\.bin: OK' "cadeia B: sha256sum -c aprova (usuário confere antes de gravar)"
assert_match "$verif" 'part-00: OK' "cadeia B: partes conferem individualmente"
joined=$(sha256sum "$CH/mini.bin" | cut -d' ' -f1)
whole=$(grep ' mini.bin$' "$CH/sha256sums.txt" | cut -d' ' -f1)
assert_eq "$joined" "$whole" "cadeia B: ISO remontada é bit-a-bit a original"
# anti-tamper: 1 byte corrompido TEM que ser detectado
printf 'X' | dd of="$CH/mini.bin.part-01" bs=1 seek=100 conv=notrunc 2>/dev/null
if ( cd "$CH" && sha256sum -c <(grep -E 'part' sha256sums.txt) ) >/dev/null 2>&1; then
  fail "cadeia B: tamper detectado" "sha256sum -c passou com parte corrompida!"
else
  ok "cadeia B: 1 byte corrompido é rejeitado (a cadeia pega adulteração)"
fi

# ════════════════════════════════════════════════════════════════════
# 4.C elite-tune --firstboot --dry-run: os DOIS setups, ponta a ponta,
# sem tocar em nada (wfile/run são dry-guarded — a peça prova isso)
# ════════════════════════════════════════════════════════════════════
TUNE="$REPO/elite/airootfs/usr/local/bin/elite-tune"

# o elite-tune exige root (menos --status): local usa user-namespace (unshare -r),
# CI roda como root no container — se nenhum dos dois, pula sem quebrar a cadeia
if [[ $EUID -eq 0 ]]; then
  ROOTWRAP=()
elif unshare -r true 2>/dev/null; then
  ROOTWRAP=(unshare -r)
else
  ROOTWRAP=("SKIP")
fi
firstboot() { # encaminha p/ o wrapper de root escolhido; saída SEM códigos ANSI
  if [[ ${ROOTWRAP[0]} == SKIP ]]; then return 99; fi
  local out rc
  out=$(with_mocks "${ROOTWRAP[@]}" env "$@" 2>&1); rc=$?
  printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g'
  return $rc
}

# Setup A (RTX 5060) herdando ICDs Vulkan AMD/Intel da ISO:
# (guard deepseek #3: sem root E sem unshare → SKIP, nunca FAIL por ambiente)
if [[ ${ROOTWRAP[0]} == SKIP ]]; then
  skip "cadeia C (firstboot ×3): exige root (unshare indisponível)" "o job do CI roda como root no container Arch"
else
: > "$STATE/installed.txt"; : > "$STATE/pacman.log"; rm -f "$STATE/refuse"
for p in vulkan-radeon lib32-vulkan-radeon vulkan-intel lib32-vulkan-intel \
         mesa steam linux-cachyos-bore nvidia-open nvidia-utils; do
  echo "$p" >> "$STATE/installed.txt"
done
if outA="$(firstboot LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rtx-5060.txt" \
  NVIDIA_SMI='NVIDIA GeForce RTX 5060' \
  bash "$TUNE" --firstboot --dry-run --yes 2>&1)"; then rcA=0; else rcA=$?; fi
fbm0=0; [[ -f /var/lib/elite/firstboot-done ]] && fbm0=1
assert_eq "$rcA" "0" "cadeia C (Setup A): firstboot dry-run exit 0"
assert_match "$outA" 'NVIDIA blackwell → nvidia-open-dkms' "cadeia C (Setup A): plano do driver certo p/ Blackwell"
assert_match "$outA" 'Auto-limpeza: GPU nvidia → removendo stack do outro vendor' "cadeia C (Setup A): auto-limpeza anunciada"
assert_match "$outA" '\[arquivo\] /etc/modprobe\.d/00-elite-nvidia\.conf' "cadeia C (Setup A): modeset/VRAM planejados (wfile)"
assert_match "$outA" '\$ systemctl enable --now scx-elite\.service' "cadeia C (Setup A): serviços ecoados, não executados (dry)"
assert_match "$outA" 'FIRSTBOOT CONCLUÍDO' "cadeia C (Setup A): chegou ao fim sem abortar"
grep -q -- '-Rns' "$STATE/pacman.log" \
  && fail "cadeia C (Setup A): dry-run NÃO executa remoção" "log trouxe -Rns" \
  || ok "cadeia C (Setup A): dry-run não executou -Rns (só -Qq consultou)"
assert_nofile "/etc/modprobe.d/00-elite-nvidia.conf" "cadeia C (Setup A): nada escrito em /etc (dry é seco)"
assert_nofile "/etc/systemd/system/scx-elite.service" "cadeia C (Setup A): unit não criada fora do dry"
# regressão v4.4: dry não cria marker nem transmite wall (o aviso "REINICIE"
# numa SIMULAÇÃO seria mentira broadcastada para todos os ttys do usuário)
if [[ -s "$STATE/wall.log" ]]; then
  fail "cadeia C (Setup A): dry não transmite wall" "wall.log tem conteúdo"
else
  ok "cadeia C (Setup A): dry NÃO transmite wall (nenhum aviso falso)"
fi
fbm1=0; [[ -f /var/lib/elite/firstboot-done ]] && fbm1=1
assert_eq "$fbm1" "$fbm0" "cadeia C (Setup A): dry não cria/toca /var/lib/elite/firstboot-done"

# Setup B (RX 7600) herdando o stack NVIDIA inteiro (v1.1: com o dkms):
: > "$STATE/installed.txt"; : > "$STATE/pacman.log"
for p in nvidia-open nvidia-open-dkms nvidia-utils nvidia-settings lib32-nvidia-utils \
         mesa steam linux-cachyos-bore; do
  echo "$p" >> "$STATE/installed.txt"
done
if outB="$(firstboot LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rx-7600.txt" \
  bash "$TUNE" --firstboot --dry-run --yes 2>&1)"; then rcB=0; else rcB=$?; fi
assert_eq "$rcB" "0" "cadeia C (Setup B): firstboot dry-run exit 0"
assert_match "$outB" 'AMD → mesa/RADV' "cadeia C (Setup B): plano AMD certo (RADV assado = no-op)"
assert_match "$outB" 'Auto-limpeza: GPU amd → removendo stack do outro vendor \(nvidia-open nvidia-open-dkms' "cadeia C (Setup B): stack NVIDIA inteiro (dkms incluso) anunciado p/ sair"
assert_match "$outB" '\[arquivo\] /etc/modprobe\.d/00-elite-amdgpu\.conf' "cadeia C (Setup B): ppfeaturemask planejado (undervolt/OC)"

# GPU desconhecida: firstboot não morre, só avisa
: > "$STATE/installed.txt"; : > "$STATE/pacman.log"
if outU="$(firstboot LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/matrox-unknown.txt" \
  bash "$TUNE" --firstboot --dry-run --yes 2>&1)"; then rcU=0; else rcU=$?; fi
assert_eq "$rcU" "0" "cadeia C (exótica): Matrox → exit 0 (nunca trava o firstboot)"
assert_match "$outU" 'GPU não identificada' "cadeia C (exótica): aviso explícito de GPU desconhecida"
fi

# modo --status (uso diário): certifica sem alterar nada
outS="$(with_mocks env LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rtx-5060.txt" \
  NVIDIA_SMI='NVIDIA GeForce RTX 5060' \
  bash "$TUNE" --status 2>&1)"; rcS=$?
assert_eq "$rcS" "0" "cadeia C (uso): --status exit 0"
assert_match "$outS" 'scx-elite' "cadeia C (uso): --status lista os serviços elite"

# ════════════════════════════════════════════════════════════════════
# 4.D MODO PADRÃO INTERATIVO (o enxerto em qualquer Arch) — dry de ponta
#     a ponta: dossiê, plano de cada seção [1]-[8] e o contrato "dry é
#     seco" auditado em /etc (nenhum .bak, nenhum arquivo novo)
# ════════════════════════════════════════════════════════════════════
dryrun() { # env… → elite-tune --dry-run --yes, ANSI-stripado, rc preservado
  local out rc
  out=$(with_mocks "${ROOTWRAP[@]}" env "$@" bash "$TUNE" --dry-run --yes 2>&1); rc=$?
  printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g'
  return $rc
}
if [[ ${ROOTWRAP[0]} == SKIP ]]; then
  skip "cadeia D (modo padrão dry): exige root (unshare indisponível)" "o job do CI roda como root"
else
  touch "$STATE/ran-D"   # prova p/ a peça anti-skip (abaixo): o bloco ENTROU
  baks0=$(ls /etc/*.bak.* 2>/dev/null | wc -l)
  # estado: Setup A herdando os ICDs Vulkan AMD/Intel da ISO (a auto-limpeza
  # do modo padrão tem o que anunciar no plano)
  : > "$STATE/installed.txt"; : > "$STATE/pacman.log"
  for p in vulkan-radeon lib32-vulkan-radeon vulkan-intel lib32-vulkan-intel \
           mesa steam linux-cachyos-bore nvidia-open nvidia-utils; do
    echo "$p" >> "$STATE/installed.txt"
  done
  if outP="$(dryrun LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rtx-5060.txt" \
              NVIDIA_SMI='NVIDIA GeForce RTX 5060')"; then rcP=0; else rcP=$?; fi
  assert_eq "$rcP" "0" "cadeia D (Setup A): modo padrão dry exit 0"
  assert_match "$outP" 'DOSSIÊ DETECTADO' "cadeia D: dossiê abre a sessão"
  assert_match "$outP" 'gen=blackwell vendor=nvidia' "cadeia D: dossiê mostra o hardware certo"
  assert_match "$outP" '\$ pacman -S --needed --noconfirm linux-cachyos-bore linux-cachyos-bore-headers' \
    "cadeia D: [1] kernel BORE no plano (kernel único)"
  if grep -q ' linux-headers' <<<"$outP"; then
    fail "cadeia D: [1] headers do kernel stock FORA do plano" "plano ainda instala linux-headers"
  else
    ok "cadeia D: [1] linux-headers stock fora do plano (v1.1: kernel único BORE)"
  fi
  assert_match "$outP" '\$ pacman -S --needed --noconfirm cachyos-settings cachyos-ananicy-rules ananicy-cpp scx-scheds scx-tools dmemcg-booster' \
    "cadeia D: [1] stack CachyOS completo no plano"
  assert_match "$outP" '\[arquivo\] /etc/systemd/system/scx-elite\.service' "cadeia D: [2] unit scx planejada"
  assert_match "$outP" '\$ grub-mkconfig -o /boot/grub/grub\.cfg' "cadeia D: [3] grub-mkconfig no plano"
  assert_match "$outP" 'NVIDIA blackwell → nvidia-open-dkms' "cadeia D: [4] driver certo p/ Blackwell"
  assert_match "$outP" '\[arquivo\] /etc/modprobe\.d/00-elite-nvidia\.conf' "cadeia D: [4] modprobe modeset/VRAM planejado"
  assert_match "$outP" 'Auto-limpeza: GPU nvidia' "cadeia D: [4] auto-limpeza de ICDs no plano"
  assert_match "$outP" '\[arquivo\] /etc/systemd/zram-generator\.conf' "cadeia D: [5] zram planejado"
  assert_match "$outP" '\[arquivo\] /etc/sysctl\.d/99-elite\.conf' "cadeia D: [5] sysctl de gaming planejado"
  assert_match "$outP" '\[arquivo\] /etc/udev/rules\.d/60-io-elite\.rules' "cadeia D: [5] udev I/O planejado"
  assert_match "$outP" 'fg-booster: binário não encontrado' "cadeia D: [6] graft fora da ISO avisa (fg-booster)"
  assert_match "$outP" '\[arquivo\] /etc/systemd/system/fg-boost\.slice' "cadeia D: [6] slice turbinado planejado"
  assert_match "$outP" '\$ pacman -S --needed --noconfirm gamemode lib32-gamemode gamescope' \
    "cadeia D: [7] stack de jogo no plano"
  assert_match "$outP" 'CONCLUÍDO. Reboot' "cadeia D: chegou ao fim"
  baks1=$(ls /etc/*.bak.* 2>/dev/null | wc -l)
  assert_eq "$baks1" "$baks0" "cadeia D: dry NÃO cria .bak em /etc (backup guardado — v4.4)"

  if outP2="$(dryrun LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rx-7600.txt")"; then rcP2=0; else rcP2=$?; fi
  assert_eq "$rcP2" "0" "cadeia D (Setup B): modo padrão dry exit 0"
  assert_match "$outP2" 'radeontop' "cadeia D (Setup B): plano AMD inclui radeontop"
  assert_match "$outP2" '\[arquivo\] /etc/modprobe\.d/00-elite-amdgpu\.conf' "cadeia D (Setup B): ppfeaturemask planejado"

  # aconselhamento de hardware (qualidade de USO, não só de código):
  outP3="$(with_mocks "${ROOTWRAP[@]}" env DMIDECODE_MODE=single \
    LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rtx-5060.txt" \
    NVIDIA_SMI='NVIDIA GeForce RTX 5060' \
    bash "$TUNE" --dry-run --yes 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
  assert_match "$outP3" 'SINGLE-CHANNEL' "cadeia D (conselho): 1 pente de RAM → alerta de upgrade"
  assert_match "$outP3" 'DOCP/XMP' "cadeia D (conselho): RAM @ 2666MHz → aviso de BIOS"

  # v4.6 — BBR determinístico: o mesmo guard do firstboot decide entre
  # wfile 99-elite-net.conf+elite-bbr.conf (kernel com bbr) e warn (sem).
  # O grep de /proc é mockado (mocks-scoped) — sem depender do kernel do host
  if outBBRp="$(PATH="$WORK/mocks-scoped:$PATH" dryrun ELITE_SCOPED_BBR=present \
      LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rtx-5060.txt" \
      NVIDIA_SMI='NVIDIA GeForce RTX 5060')"; then rcBBRp=0; else rcBBRp=$?; fi
  assert_eq "$rcBBRp" "0" "cadeia D (BBR on): dry exit 0 com kernel-bbr simulado"
  assert_match "$outBBRp" '\[arquivo\] /etc/sysctl\.d/99-elite-net\.conf' "cadeia D (BBR on): [5] sysctl BBR+fq planejado (wfile)"
  assert_match "$outBBRp" '\[arquivo\] /etc/modules-load\.d/elite-bbr\.conf' "cadeia D (BBR on): [5] modules-load tcp_bbr planejado (wfile)"
  if outBBRa="$(PATH="$WORK/mocks-scoped:$PATH" dryrun ELITE_SCOPED_BBR=absent \
      LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rtx-5060.txt" \
      NVIDIA_SMI='NVIDIA GeForce RTX 5060')"; then rcBBRa=0; else rcBBRa=$?; fi
  assert_eq "$rcBBRa" "0" "cadeia D (BBR off): dry exit 0 com kernel SEM bbr simulado"
  assert_match "$outBBRa" 'kernel sem bbr — mantendo cubic' "cadeia D (BBR off): aviso em vez de sysctl morto"
  if grep -q '99-elite-net' <<<"$outBBRa"; then
    fail "cadeia D (BBR off): sysctl BBR NÃO é escrito" "plano trouxe 99-elite-net.conf"
  else
    ok "cadeia D (BBR off): nenhum 99-elite-net.conf no plano (guard fecha a porta)"
  fi
fi

# ════════════════════════════════════════════════════════════════════
# 4.E MODO --apps (menu do usuário — "baixo só o que vou usar"), NÃO-dry:
#     o pacman mockado registra exatamente o que cada opção instala
# ════════════════════════════════════════════════════════════════════
if [[ ${ROOTWRAP[0]} == SKIP ]]; then
  skip "cadeia E (--apps): exige root (unshare indisponível)" "o job do CI roda como root"
else
  touch "$STATE/ran-E"   # prova p/ a peça anti-skip: o bloco ENTROU
  apps() { # opção do menu via stdin → saída ANSI-stripada, rc preservado
    local out rc
    out=$(with_mocks "${ROOTWRAP[@]}" env LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rtx-5060.txt" \
      bash "$TUNE" --apps <<< "$1" 2>&1); rc=$?
    printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g'
    return $rc
  }
  : > "$STATE/pacman.log"
  if out1="$(apps 1)"; then rc1=0; else rc1=$?; fi
  assert_eq "$rc1" "0" "cadeia E: opção 1 (Steam) exit 0"
  assert_grep "$STATE/pacman.log" 'pacman -S --needed --noconfirm steam protontricks$' \
    "cadeia E: Steam+protontricks EXATOS no log do pacman"
  assert_match "$out1" 'Concluído. Steam' "cadeia E: dica de Shader Pre-Caching"
  : > "$STATE/pacman.log"
  apps 4 >/dev/null
  assert_grep "$STATE/pacman.log" 'pacman -S --needed --noconfirm gimp inkscape kdenlive$' \
    "cadeia E: opção 4 instala a suíte de criação"
  : > "$STATE/pacman.log"
  if out0="$(apps 9)"; then rc0=0; else rc0=$?; fi
  assert_eq "$rc0" "0" "cadeia E: opção inválida exit 0 (não trava)"
  assert_match "$out0" 'Nada instalado' "cadeia E: opção inválida → recusa educada"
  nS=$(grep -c -- '-S --needed' "$STATE/pacman.log" 2>/dev/null || true)
  assert_eq "$nS" "0" "cadeia E: opção inválida não instala NADA"
fi

# ════════════════════════════════════════════════════════════════════
# 4.F FIRSTBOOT DE VERDADE (NÃO-dry) — as escritas REAIS, isoladas:
#     unshare -rm + tmpfs em /etc e /var (dev machine; host intocado) ou
#     root direto no container efêmero do CI. O dry-run prova o PLANO;
#     aqui prova-se a EXECUÇÃO: modprobe.d, tokens GRUB, unit scx, marker,
#     wall transmitido — e o caminho pascal-sem-nvidia-dkms (pacman recusa)
# ════════════════════════════════════════════════════════════════════
if unshare -rm true 2>/dev/null; then
  ISOL=(unshare -rm); NS_TMPFS=1
elif [[ $EUID -eq 0 ]]; then
  ISOL=(); NS_TMPFS=0
else
  ISOL=("SKIP")
fi
if [[ ${ISOL[0]} == SKIP ]]; then
  skip "cadeia F (firstboot real ×3): exige root/ns (unshare indisponível)" "o job do CI roda como root"
else
  fbreal() { # <cenario> <fixture> <smi> <refuse> [pkgs…] → evidência em $STATE/fb-real-<cenario>.log
    local scen=$1 fix=$2 smi=$3 refuse=$4
    shift 4
    # cenários v4.6: mocks de cenário (ls NV_PREBUILT / grep BBR) por nome
    local extra=()
    case "$scen" in
      nvpre)    extra=(MOCK_EXTRA="$WORK/mocks-scoped" ELITE_SCOPED_NVLS=1) ;;
      bbrabs)   extra=(MOCK_EXTRA="$WORK/mocks-scoped" FB_BBR=1 ELITE_SCOPED_BBR=absent) ;;
      bbrpres)  extra=(MOCK_EXTRA="$WORK/mocks-scoped" FB_BBR=1 ELITE_SCOPED_BBR=present) ;;
    esac
    with_mocks "${ISOL[@]}" env NS_TMPFS="$NS_TMPFS" TUNE="$TUNE" \
      FB_LOG="$STATE/fb-real-$scen.log" \
      FB_FIXTURE="$fix" FB_SMI="$smi" FB_REFUSE="$refuse" FB_PKGS="$*" \
      MOCK_DIR="$STATE" ${extra[@]+"${extra[@]}"} bash "$TESTS_DIR/lib/ns-body.sh"
  }
  hostmod0=0; [[ -f /etc/modprobe.d/00-elite-nvidia.conf ]] && hostmod0=1

  # cenário INTEL primeiro (no modo container o /etc é compartilhado entre
  # cenários; intel não cria modprobe — a ordem mantém as asserções válidas)
  fbreal intel "$TESTS_DIR/fixtures/lspci/intel-igpu.txt" "" 0 mesa steam
  LI="$STATE/fb-real-intel.log"
  assert_match "$(sed -n '/^RC=/p' "$LI")" '^RC=0$' "cadeia F (intel): firstboot REAL exit 0"
  assert_grep "$LI" 'Intel → mesa/ANV' "cadeia F (intel): plano mesa/ANV executado"
  if grep -q '00-elite-nvidia\|00-elite-amdgpu' "$LI"; then
    fail "cadeia F (intel): nenhum modprobe elite" "apareceu modprobe de outro vendor"
  else
    ok "cadeia F (intel): nenhum modprobe elite (intel não precisa)"
  fi
  assert_grep "$STATE/pacman.log" 'pacman -S --needed --noconfirm mesa lib32-mesa vulkan-intel$' \
    "cadeia F (intel): stack mesa/ANV no pacman real"
  assert_match "$(sed -n '/^=== MARKER/,+1p' "$LI" | tail -1)" '^yes$' \
    "cadeia F (intel): marker firstboot-done CRIADO (execução real)"

  # cenário NVIDIA BLACKWELL (Setup A) — o caminho completo
  fbreal nvbw "$TESTS_DIR/fixtures/lspci/rtx-5060.txt" 'NVIDIA GeForce RTX 5060' 0 \
    vulkan-radeon lib32-vulkan-radeon vulkan-intel lib32-vulkan-intel \
    mesa steam linux-cachyos-bore nvidia-open nvidia-utils
  LA="$STATE/fb-real-nvbw.log"
  assert_match "$(sed -n '/^RC=/p' "$LA")" '^RC=0$' "cadeia F (Setup A): firstboot REAL exit 0"
  assert_grep "$LA" '^/etc/modprobe\.d/00-elite-nvidia\.conf$' "cadeia F (Setup A): /etc/modprobe.d/00-elite-nvidia.conf escrito"
  assert_grep "$LA" 'options nvidia-drm modeset=1 fbdev=1' "cadeia F (Setup A): modeset+fbdev (Wayland)"
  assert_grep "$LA" 'NVreg_PreserveVideoMemoryAllocations=1' "cadeia F (Setup A): VRAM preservada em suspend"
  assert_grep "$LA" 'GRUB_CMDLINE_LINUX_DEFAULT=.*nowatchdog' "cadeia F (Setup A): token nowatchdog no GRUB real"
  assert_grep "$LA" 'GRUB_CMDLINE_LINUX_DEFAULT=.*zswap\.enabled=0' "cadeia F (Setup A): zswap desligado no cmdline"
  assert_grep "$LA" 'GRUB_CMDLINE_LINUX_DEFAULT=.*transparent_hugepage=always' "cadeia F (Setup A): THP always no cmdline"
  if grep -A1 '^=== ISAMD' "$LA" | grep -q '^yes$'; then
    assert_grep "$LA" 'GRUB_CMDLINE_LINUX_DEFAULT=.*amd_pstate=active' \
      "cadeia F (Setup A): CPU AMD → amd_pstate=active no cmdline"
  else
    ok "cadeia F (Setup A): CPU não-AMD → sem amd_pstate (decisão certa)"
  fi
  assert_grep "$LA" 'ExecStart=/usr/bin/scx_bpfland' "cadeia F (Setup A): unit scx-elite escrita (bpfland)"
  assert_match "$(sed -n '/^=== MARKER/,+1p' "$LA" | tail -1)" '^yes$' \
    "cadeia F (Setup A): marker firstboot-done criado"
  assert_grep "$STATE/pacman.log" 'pacman -R --noconfirm nvidia-open$' \
    "cadeia F (Setup A): nvidia-open pré-compilado removido (vai entrar o dkms)"
  assert_grep "$STATE/pacman.log" 'pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils$' \
    "cadeia F (Setup A): stack dkms instalado SEM nvidia-settings (v4.6 — LACT cobre)"
  assert_grep "$STATE/pacman.log" 'pacman -Rns --noconfirm vulkan-radeon' \
    "cadeia F (Setup A): ICDs alienígenas removidos na execução real"
  assert_grep "$STATE/systemctl.log" 'disable elite-firstboot' \
    "cadeia F (Setup A): unit firstboot auto-desativada"
  assert_grep "$STATE/wall.log" 'wall ELITE:' "cadeia F (Setup A): wall transmitido (aviso real de reboot)"

  # cenário PASCAL (rig veterano) COM pacman recusando nvidia-dkms:
  # o firstboot não pode morrer — o fallback AUR tem que aparecer
  fbreal pascal "$TESTS_DIR/fixtures/lspci/nv-gp102-bare.txt" 'NVIDIA GeForce GTX 1080' 1 mesa
  LP="$STATE/fb-real-pascal.log"
  assert_match "$(sed -n '/^RC=/p' "$LP")" '^RC=0$' "cadeia F (pascal): pacman recusa → firstboot AINDA exit 0"
  assert_grep "$LP" 'tentando nvidia-dkms' "cadeia F (pascal): plano branch 580 anunciado"
  assert_grep "$LP" 'nvidia-dkms indisponível' "cadeia F (pascal): falha assumida (sem crash)"
  assert_grep "$LP" 'paru -S nvidia-580xx-dkms' "cadeia F (pascal): instrução AUR de resgate"

  # cenário NVIDIA BLACKWELL SEM REDE (v4.5 — anti-brick do 1º boot offline):
  # o -S do dkms falha → nvidia-open PRESERVADO (nunca removido antes do
  # sucesso), marker NÃO escrito (a unit re-tenta no próximo boot) e sem
  # self-disable. Era o risco real do Elite A: live OK, install OK, reboot
  # sem cabo de rede → sem driver NENHUM e sem retry. Agora é contrato.
  # (ns-body reseta pacman/systemctl/wall por cenário; o marker precisa de
  #  limpeza manual só no modo container, que compartilha o /var real)
  [[ $NS_TMPFS == 0 ]] && rm -f /var/lib/elite/firstboot-done
  fbreal nvbw-net0 "$TESTS_DIR/fixtures/lspci/rtx-5060.txt" 'NVIDIA GeForce RTX 5060' 1 \
    nvidia-open nvidia-utils mesa
  LN="$STATE/fb-real-nvbw-net0.log"
  assert_match "$(sed -n '/^RC=/p' "$LN")" '^RC=0$' "cadeia F (A sem rede): firstboot AINDA exit 0 (nunca trava)"
  assert_grep "$LN" 'nvidia-open-dkms não instalou' "cadeia F (A sem rede): falha assumida com aviso"
  assert_grep "$LN" 'driver atual PRESERVADO' "cadeia F (A sem rede): driver do live PRESERVADO (anti-brick)"
  assert_grep "$STATE/pacman.log" 'pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils$' \
    "cadeia F (A sem rede): tentativa de dkms registrada (ordem -S→-R, sem nvidia-settings)"
  assert_nogrep "$STATE/pacman.log" 'pacman -R --noconfirm nvidia-open$' \
    "cadeia F (A sem rede): NUNCA removeu o nvidia-open (o -R só existe após -S vencer)"
  assert_match "$(sed -n '/^=== MARKER/,+1p' "$LN" | tail -1)" '^no$' \
    "cadeia F (A sem rede): marker NÃO escrito → re-tenta no próximo boot"
  assert_nogrep "$STATE/systemctl.log" 'disable elite-firstboot' \
    "cadeia F (A sem rede): unit NÃO auto-desativada (retry vivo)"
  assert_grep "$STATE/wall.log" 'pendente' "cadeia F (A sem rede): wall honesto ('pendente', não 'REINICIE')"

  # cenário v4.6 — NVIDIA com dkms PRÉ-COMPILADO da ISO (o coração da v1.1):
  # o ls de /usr/lib/modules/$(uname -r)/updates/dkms/nvidia.ko* responde (mock
  # de cenário) → firstboot NÃO instala NADA, marker na 1ª passada — 1º boot
  # do rig A 100% offline (a razão de ser do E11)
  [[ $NS_TMPFS == 0 ]] && rm -f /var/lib/elite/firstboot-done
  fbreal nvpre "$TESTS_DIR/fixtures/lspci/rtx-5060.txt" 'NVIDIA GeForce RTX 5060' 0 \
    nvidia-open-dkms nvidia-utils mesa steam
  LPB="$STATE/fb-real-nvpre.log"
  assert_match "$(sed -n '/^RC=/p' "$LPB")" '^RC=0$' "cadeia F (dkms pré-compilado): firstboot exit 0"
  assert_grep "$LPB" 'driver dkms PRÉ-COMPILADO da ISO já presente' \
    "cadeia F (dkms pré-compilado): caminho offline anunciado (nada a instalar)"
  assert_grep "$LPB" 'nada a instalar \(offline OK\)' "cadeia F (dkms pré-compilado): offline OK explícito"
  assert_nogrep "$STATE/pacman.log" 'pacman -S --needed --noconfirm nvidia-open-dkms' \
    "cadeia F (dkms pré-compilado): NENHUMA instalação de driver (mock log limpo)"
  assert_match "$(sed -n '/^=== MARKER/,+1p' "$LPB" | tail -1)" '^yes$' \
    "cadeia F (dkms pré-compilado): marker escrito na 1ª passada (sem retry)"
  assert_nogrep "$STATE/wall.log" 'pendente' "cadeia F (dkms pré-compilado): wall sem 'pendente' (nada ficou devendo)"

  # cenário v4.6 — BBR guard: kernel SEM bbr → o sysctl.d da ISO é LIMPO (as
  # linhas net.* somem e o modules-load morre) em vez de sysctl morto
  fbreal bbrabs "$TESTS_DIR/fixtures/lspci/intel-igpu.txt" "" 0 mesa steam
  LBBA="$STATE/fb-real-bbrabs.log"
  assert_match "$(sed -n '/^RC=/p' "$LBBA")" '^RC=0$' "cadeia F (bbr off): firstboot exit 0"
  assert_grep "$LBBA" 'bbr indisponível neste kernel' "cadeia F (bbr off): aviso de limpeza anunciado"
  bbrnet=$(sed -n '/^=== BBRCFG/,/^=== BBRMOD/p' "$LBBA" | grep -c '^net\.')
  assert_eq "$bbrnet" "0" "cadeia F (bbr off): linhas net.* REMOVIDAS do 99-elite-net.conf"
  bbrmod=$(awk '/^=== BBRMOD/{getline; print; exit}' "$LBBA")
  assert_eq "$bbrmod" "no" "cadeia F (bbr off): modules-load.d/elite-bbr.conf APAGADO"

  # cenário v4.6 — BBR presente: a ISO entrega bbr+fq e o firstboot SÓ confirma
  fbreal bbrpres "$TESTS_DIR/fixtures/lspci/intel-igpu.txt" "" 0 mesa steam
  LBBP="$STATE/fb-real-bbrpres.log"
  assert_match "$(sed -n '/^RC=/p' "$LBBP")" '^RC=0$' "cadeia F (bbr on): firstboot exit 0"
  assert_grep "$LBBP" 'TCP: bbr \+ fq ativos' "cadeia F (bbr on): confirmação bbr+fq (sysctl.d da ISO vale)"
  bbrnet2=$(sed -n '/^=== BBRCFG/,/^=== BBRMOD/p' "$LBBP" | grep -c '^net\.')
  assert_eq "$bbrnet2" "2" "cadeia F (bbr on): fq + bbr INTACTOS no sysctl.d (nada limpo)"
  bbrmod2=$(awk '/^=== BBRMOD/{getline; print; exit}' "$LBBP")
  assert_eq "$bbrmod2" "yes" "cadeia F (bbr on): modules-load elite-bbr.conf preservado"

  # prova de isolamento (modo ns): o HOST não ganhou nenhum arquivo elite
  if [[ $NS_TMPFS == 1 ]]; then
    hostmod1=0; [[ -f /etc/modprobe.d/00-elite-nvidia.conf ]] && hostmod1=1
    assert_eq "$hostmod1" "$hostmod0" \
      "cadeia F: host INTOCADO (escritas viveram no tmpfs do namespace)"
  else
    skip "cadeia F: host intocado (modo container)" "CI escreve no /etc do container efêmero — por design"
  fi
fi

# ── peças ANTI-SKIP: as cadeias novas são CONTRATO — pulo silencioso = NO-GO.
#    (Bug real que motivou isto: ${arr[0]:-SKIP} colapsa array vazia em SKIP
#    e fez o CI pular D/E/F num veredito verde — falsa segurança.)
can_root=0; { [[ $EUID -eq 0 ]] || unshare -r true 2>/dev/null; } && can_root=1
can_ns=0;   { [[ $EUID -eq 0 ]] || unshare -rm true 2>/dev/null; } && can_ns=1
if (( can_root )); then
  for p in D E; do
    [[ -f "$STATE/ran-$p" ]] \
      && ok "anti-skip: cadeia $p executou (guard não comeu o bloco)" \
      || fail "anti-skip: cadeia $p executou" "bloco pulado com root/unshare disponível — bug de guard"
  done
fi
if (( can_ns )); then
  [[ -f "$STATE/fb-real-nvbw.log" ]] \
    && ok "anti-skip: cadeia F executou (firstboot real com evidência)" \
    || fail "anti-skip: cadeia F executou" "evidência ausente com root/ns disponível"
  for ev in fb-real-nvpre.log fb-real-bbrabs.log fb-real-bbrpres.log; do
    [[ -f "$STATE/$ev" ]] \
      && ok "anti-skip: cenário v4.6 $ev rodou (evidência no estado)" \
      || fail "anti-skip: cenário v4.6 $ev" "evidência ausente com root/ns disponível"
  done
fi

# 4.G (determinismo): a segunda montagem do overlay é bit-a-bit igual à
# primeira (nenhum sed/awk acumulando edição em cima de edição)
DET="$WORK/det1"; mkdir -p "$DET"
cp "$P/packages.x86_64" "$DET/packages.x86_64"
cp "$P/pacman.conf"     "$DET/pacman.conf"
cp "$P/grub/grub.cfg"   "$DET/grub.cfg"
cp "$P/efiboot/loader/entries/01-archiso-linux.conf" "$DET/01-archiso-linux.conf"
if out="$( cd "$RE" && HOME="$WORK/home" bash scripts/apply-overlay.sh 2>&1 )"; then
  detsame=1; detbad=""
  cmp -s "$DET/packages.x86_64" "$P/packages.x86_64" || { detsame=0; detbad="packages.x86_64"; }
  cmp -s "$DET/pacman.conf"     "$P/pacman.conf"     || { detsame=0; detbad="pacman.conf"; }
  cmp -s "$DET/grub.cfg"        "$P/grub/grub.cfg"   || { detsame=0; detbad="grub.cfg"; }
  cmp -s "$DET/01-archiso-linux.conf" "$P/efiboot/loader/entries/01-archiso-linux.conf" \
    || { detsame=0; detbad="01-archiso-linux.conf"; }
  (( detsame )) \
    && ok "cadeia G: 2ª montagem do overlay → bit-a-bit idêntica (determinismo)" \
    || fail "cadeia G: determinismo do overlay" "divergiu: $detbad"
else
  fail "cadeia G: 2ª montagem do overlay" "${out:0:200}"
fi

# ═══════════════════════════════════════════════════════════════════════════
# v1.3 · AMOLED RICE — preto REAL em toda superfície + rodapé morto + foot
# ═══════════════════════════════════════════════════════════════════════════
ST="$P/airootfs/etc/skel/.config"
WBT="$ST/waybar/style.top.css"; WBD="$ST/waybar/style.dock.css"
DRW="$ST/nwg-drawer/drawer.css";  SWC="$ST/swaync/style.css"
FZL="$ST/fuzzel/fuzzel.ini";       FTC="$ST/foot/foot.ini"
THR="$ST/labwc/themerc-override";  AST="$ST/labwc/autostart"
WAL="$ST/labwc/wallpaper.png"

# ── Escada AMOLED idêntica nos 4 CSS (base do sistema = preto REAL) ────────
for f in "$WBT" "$WBD" "$SWC" "$DRW"; do
  fn=$(basename "$(dirname "$f")")/$(basename "$f")
  assert_grep "$f" '^@define-color crust[[:space:]]*#000000' "v1.3: $fn crust = #000000 (preto REAL)"
  assert_grep "$f" '^@define-color base[[:space:]]*#0a0a12' "v1.3: $fn base = #0a0a12"
  assert_nogrep "$f" '#1e1e2e' "v1.3: $fn anti-regressão (base Catppuccin 1e1e2e extinta)"
  assert_nogrep "$f" '#11111b' "v1.3: $fn anti-regressão (crust Catppuccin 11111b extinto)"
done

# ── Acentos Catppuccin INTACTOS (o colorido não escureceu) ─────────────────
assert_grep "$WBD" '^@define-color mauve[[:space:]]*#cba6f7' "v1.3: mauve 3cba6f7 intacto (assinatura)"
assert_grep "$WBD" '^@define-color peach[[:space:]]*#fab387' "v1.3: peach fab387 intacto (Brave)"

# ── Cores SEMÂNTICAS de marca na dock (v1.3: identidade do dono) ───────────
assert_grep "$WBD" '#custom-drawer[[:space:]]+\{ color: @mauve;' "v1.3: drawer (ARCH) em MAUVE — identidade"
assert_grep "$WBD" '@define-color peach[[:space:]]*#fab387' "v1.3/v1.5: peach fab387 intacto (paleta preservada — pin do Brave agora é ícone REAL)"

# ── Glifo ARCH no drawer (pair atualizado acima: uf00b → uf303) ────────────
assert_grep "$CD" '"format": "\\uf303"' "v1.3: dock custom/drawer com glifo ARCH U+F303"
assert_nogrep "$CD" '\\uf00b' "v1.3: glifo grid genérico extinto do drawer"

# ── Rodapé do nwg-drawer MORTO por CSS (sem fork do upstream) ──────────────
assert_grep "$DRW" '#status-label' "v1.3: drawer.css mata #status-label (rodapé 'N entries')"
assert_grep "$DRW" '#status-line-wrapper' "v1.3: drawer.css mata #status-line-wrapper"
assert_grep "$DRW" '#status-label \{[[:space:]]*$' "v1.3: bloco #status-label declarado"
if grep -A2 '#status-label {' "$DRW" | grep -q 'opacity: 0'; then
  ok "v1.3: #status-label com opacity 0 (morto, reversível — sem fork)"
else
  fail "v1.3: #status-label opacity 0" "seletor sem morte efetiva"
fi

# ── fuzzel.ini: INI VÁLIDO + AMOLED (cabeçalho é contrato) ────────────────
assert_grep "$FZL" '^\[main\]$' "v1.3: fuzzel.ini com seção [main] (cabeçalho presente)"
assert_nogrep "$FZL" '^ain\]$' "v1.3: anti-regressão: cabeçalho de seção nunca 'ain]'"
assert_grep "$FZL" '^background=000000f2$' "v1.3: fuzzel bg preto (véu f2)"
assert_grep "$FZL" '^prompt=cba6f7ff$' "v1.3: fuzzel prompt MAUVE (era blue)"
assert_grep "$FZL" '^border=cba6f7ff$' "v1.3: fuzzel borda MAUVE (era blue)"
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "
import configparser, sys
cp = configparser.ConfigParser(strict=True)
try:
    cp.read('$FZL')
    sys.exit(0 if 'main' in cp and 'colors' in cp else 1)
except Exception:
    sys.exit(2)
" 2>/dev/null; then
    ok "v1.3: fuzzel.ini parseia como INI válido (main + colors)"
  else
    fail "v1.3: fuzzel.ini parseia como INI válido" "configparser recusou o arquivo"
  fi
else
  skip "v1.3: fuzzel.ini parse INI" "python3 indisponível"
fi

# ── foot.ini: o terminal virou superfície do rice ──────────────────────────
assert_file "$FTC" "v1.3: foot.ini existe (terminal riceado — foot nunca teve config na ISO)"
assert_grep "$FTC" '^background = 000000$' "v1.3: foot bg preto AMOLED"
assert_grep "$FTC" '^selection-background = cba6f7$' "v1.3: foot seleção MAUVE"
assert_grep "$FTC" 'font = JetBrainsMono NF:size=10.5' "v1.5: foot fonte REAL no [main] (formato fontconfig family:size)"
assert_grep "$FTC" '^regular5   = f5c2e7$' "v1.3: foot tabela Mocha regular5 pink"
# v1.5 (spec do dono - foot 1.28 do Arch): secoes invalidas EXTINTAS.
# A v1.3 perdeu shell/font/colors/dim/bright-bold - o foot logava 'invalid
# section' e IGNORAVA: a fonte Nerd, o shell de login e as 16 cores nunca
# valeram. Schema real (codeberg.org/dnkl/foot - doc/foot.ini.5.scd):
for badsec in '\[shell\]' '\[font\]' '\[colors\]' '\[dim\]' '\[bright-bold\]'; do
  assert_nogrep "$FTC" "^${badsec}$" "v1.5: seção inválida ${badsec} extinta (foot 1.28 removeu [colors])"
done
assert_grep "$FTC" '^\[main\]$' "v1.5: [main] presente (shell/font vivem aqui)"
assert_grep "$FTC" '^shell = /bin/sh -l$' "v1.5: shell de login no [main] (v1.3: preso na seção inválida)"
assert_grep "$FTC" '^\[colors-dark\]$' "v1.5: [colors-dark] (a [colors] saiu no foot 1.28)"
assert_grep "$FTC" '^cursor = 000000 cba6f7$' "v1.5: cursor mauve na seção certa (1.26 removeu cursor.color)"
assert_grep "$FTC" '^dim0 = a6adc8$' "v1.5: dim0-7 DENTRO da colors-dark (a [dim] separada era inválida)"
assert_nogrep "$FTC" '^0 = f5e0dc$' "v1.5: bloco bare 0-15 extinto (sobrescrevia a paleta com valores errados)"
assert_nogrep "$FTC" 'max-shader-prompt' "v1.5: tweak.max-shader-prompt extinto (nunca existiu no foot)"
assert_nogrep "$FTC" '^clipboard-(paste|copy) =' "v1.5: atalhos duplicados dos defaults removidos (Ctrl+Shift+v/c já são defaults)"
assert_grep "$FTC" '^scrollback-up-page = Page_Up$' "v1.5: scroll Page_Up mantido (NÃO é default — override deliberado)"
# parse REAL: python configparser aceita o arquivo inteiro
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "
import configparser, sys
cp = configparser.ConfigParser(strict=True)
try:
    cp.read('$FTC')
    sys.exit(0 if {'main','colors-dark','cursor','mouse','scrollback','bell','key-bindings'} <= set(cp.sections()) else 1)
except Exception:
    sys.exit(2)
" 2>/dev/null; then
    ok "v1.5: foot.ini parseia como INI válido (7 seções do schema real)"
  else
    fail "v1.5: foot.ini parseia como INI válido" "configparser recusou o arquivo"
  fi
else
  skip "v1.5: foot.ini parse INI" "python3 indisponível"
fi

# ── themerc: titlebar ATIVA preta + assinatura mauve preservada ────────────
assert_grep "$THR" 'window.active.title.bg.color: #000000' "v1.3: titlebar ativa PRETA (era 1e1e2e)"
assert_grep "$THR" 'window.active.border.color: #cba6f7' "v1.3: borda ativa MAUVE intacta (assinatura)"
assert_grep "$THR" 'menu.items.bg.color: #050508' "v1.3: menu em mantle AMOLED"
assert_grep "$THR" 'osd.bg.color: #000000' "v1.3: OSD preto"
assert_grep "$THR" 'window.active.button.iconify.pressed.image.color: #22222e' "v1.3: pressed na escada v1.3"
assert_nogrep "$THR" ': #1e1e2e' "v1.3: themerc anti-regressão (nenhuma superfície 1e1e2e)"

# ── autostart: fallback do swaybg desce ao preto ──────────────────────────
assert_grep "$AST" "swaybg -m fill -c '#000000'" "v1.3: fallback swaybg preto AMOLED (era 1e1e2e)"

# ── Wallpaper: PNG lossless e AMOLED DE VERDADE (bytes, não promessa) ────
# JPEG não preserva preto exato (re-quantiza cada bloco 8x8: 0 px em 8,3M
# no arquivo original). PNG + black-point: 62% dos pixels são (0,0,0) puros.
assert_file "$WAL" "v1.3: wallpaper.png existe (4K real da internet, PNG lossless)"
if command -v python3 >/dev/null 2>&1; then
  if python3 -c 'from PIL import Image' 2>/dev/null; then
    walout="$(python3 - "$WAL" << 'PYEOF'
import sys
from PIL import Image
rgb = Image.open(sys.argv[1]).convert('RGB')
total = rgb.size[0] * rgb.size[1]
# Preto PURO = pixel (0,0,0) EXATO — contagem CONJUNTA, pixel a pixel.
# histogram() por canal NÃO serve: no JPEG original o canal G marcava
# 33.1% em zero sem NENHUM pixel preto (artefato de quantização JPEG) —
# superestima. A contagem conjunta confere com numpy (62.22% neste arquivo).
black = 100.0 * sum(1 for p in rgb.getdata() if p == (0, 0, 0)) / total
hist = rgb.convert('L').histogram()
mean = sum(i * c for i, c in enumerate(hist)) / sum(hist)
print(rgb.size[0], round(black, 1), round(mean, 1))
PYEOF
)"
    if [[ "$walout" =~ ^[0-9]+[[:space:]][0-9.]+[[:space:]][0-9.]+$ ]]; then
      read -r walres walblack walmean <<<"$walout"
      assert_eq "$walres" "3840" "v1.3: wallpaper 4K (3840px de largura — tem $walres)"
      blackok=1; awk "BEGIN{exit !($walblack >= 40.0)}" || blackok=0
      assert_eq "$blackok" "1" "v1.3: wallpaper ≥40% de preto PURO (0,0,0) — AMOLED real (tem $walblack%)"
      meanok=1; awk "BEGIN{exit !($walmean <= 30.0)}" || meanok=0
      assert_eq "$meanok" "1" "v1.3: luma média ≤30 (não cega de noite — tem $walmean)"
    else
      fail "v1.3: métricas do wallpaper" "saída do python3/PIL inesperada: '${walout:0:80}' (lição da run #34: nunca mais falha silenciosa com 'tem %')"
    fi
  else
    fail "v1.3: métricas do wallpaper" "python3 presente sem PIL — instale python-pillow (o CI já traz)"
  fi
else
  skip "v1.3: métricas do wallpaper" "python3 indisponível"
fi

# ── A corrosão NÃO alcançou os acentos globais (top bar) ───────────────────
assert_grep "$WBT" '^@define-color red[[:space:]]*#f38ba8' "v1.3: red f38ba8 intacto (mudo/disconnected)"
assert_grep "$WBT" '^@define-color green[[:space:]]*#a6e3a1' "v1.3: green a6e3a1 intacto"

# ═══════════════════════════════════════════════════════════════════════════
# v1.4 · BRAVE ORIGIN + ORGANIZAÇÃO DO RICE (burn test da v1.3 AO VIVO)
# Evidência: fotos do rig do dono (desktop/launcher/menu de sessão) +
# mensagem de voz 2026-10-22. Cada peça abaixo = uma diretrize dele.
# ═══════════════════════════════════════════════════════════════════════════
CDR="$P/airootfs/usr/local/bin/craft-drawer"
CPW="$P/airootfs/usr/local/bin/craft-power"
CCT="$P/airootfs/usr/local/bin/craft-connect"
CPP="$P/airootfs/usr/local/bin/craft-pin-pick"
CPT="$ST/waybar/config.top"; CKB="$ST/waybar/config.dock"
MXML="$ST/labwc/menu.xml"

# ── Brave ORIGIN: o PRODUTO troca, o contrato do rice intacto ────────────
assert_grep "$REPO/.ci/build.sh" 'pkgname=brave-origin' "v1.4: build empacota brave-origin (release oficial da Brave)"
assert_grep "$REPO/.ci/build.sh" 'brave-origin\.sh .\$pkgdir/usr/bin/brave' "v1.4: launcher /usr/bin/brave (comando não muda — zero regressão)"
assert_grep "$REPO/.ci/build.sh" 'applications/brave-browser\.desktop' "v1.4: desktop 'brave-browser.desktop' (contrato do mimeapps/taskbar)"
assert_grep "$REPO/.ci/build.sh" 'chrome-sandbox' "v1.4: sandbox suid 4755 (padrão upstream)"
assert_grep "$REPO/.ci/build.sh" '39a69cf12b5787f789d0a0b013f32253bddc9004d03e36c679a8daa61821b6e8' "v1.4: sha256 do brave-origin PINADO (determinismo)"
assert_nogrep "$REPO/.ci/build.sh" 'aur_build brave-bin' "v1.4: AUR brave-bin extinto (fonte = GitHub Releases, nem toca o AUR)"
assert_grep "$REPO/.ci/build.sh" 'Name=Brave Origin' "v1.4: desktop exibe o produto certo (Brave Origin)"
assert_grep "$REPO/.ci/build.sh" 'StartupWMClass=brave-browser' "v1.4: app_id casado com o taskbar (verificado no binário)"

# ── Drawer LIMPO: sem categorias, sem barra de sessão ────────────────────
assert_grep "$CDR" '-nocats' "v1.4: craft-drawer com -nocats (categorias nem nascem — flag oficial do upstream)"
assert_nogrep "$CDR" '-pb(lock|exit|reboot|poweroff|sleep)' "v1.4: flags -pb* extintas (sessão mora SÓ na menu bar — diretriz do burn test)"

# ── Dock SEMPRE VISÍVEL (a 'dock sumiu' do burn test) ────────────────────
assert_grep "$CKB" '"margin-bottom": 8' "v1.4: dock flutua 8px SEMPRE (config — iOS/macOS)"
assert_nogrep "$WBD" 'margin-bottom: -' "v1.4: auto-hide (margem negativa) EXTINTO do CSS — o talho de ícones cortados na base era isso"
assert_grep "$WBD" 'font-size: 36px' "v1.4: zoom hover 36px (magnificação iOS perceptível)"
assert_grep "$CKB" 'Brave Origin \(navegador padrão\)' "v1.4: tooltip da dock honesto com o produto (Brave Origin)"

# v1.5 (spec do dono): lançador ARCH EXTINTO da menu bar — canto esquerdo
# limpo (só o nome do app focado); o Launchpad vive na DOCK (custom/drawer)
assert_nogrep "$CPT" '"custom/menu"' "v1.5: módulo custom/menu EXTINTO do config.top (spec)"
assert_grep "$CPT" '"modules-left": \["custom/drawer", "wlr/window"\]' "v1.6: ARCH à esquerda + janela focada (pedido de volta do dono)"
assert_grep "$CPT" '"fixed-center": true' "v1.5: clock no centro EXATO (fixed-center)"
assert_grep "$CD" '\\uf303' "v1.5: ARCH U+F303 vive AGORA na dock (custom/drawer — Launchpad)"
assert_grep "$CD" '"on-click": "craft-drawer"' "v1.5: clique no ARCH da dock abre o Launchpad"
assert_nogrep "$WBT" '#custom-menu' "v1.5: CSS sem regra órfã do custom-menu"
assert_grep "$WBD" '#custom-drawer \{ color: @mauve;' "v1.3/v1.5: drawer (ARCH) em MAUVE — identidade viva na dock"

# ── Conectividade: UM ícone p/ cabo + Wi-Fi + Bluetooth ──────────────────
assert_grep "$CPT" '"on-click": "craft-connect"' "v1.4: rede → central de conectividade (um só ícone — diretrize do dono)"
assert_file "$CCT" "v1.4: craft-connect existe"
assert_grep "$CCT" 'foot -e impala' "v1.4: central abre impala (Wi-Fi/Ethernet)"
assert_grep "$CCT" 'foot -e bluetui' "v1.4: central abre bluetui (Bluetooth)"
assert_grep "$CCT" '--prompt=Rede' "v1.4: prompt 'Rede' (nunca colide com o toggle do 'Sessão')"
assert_grep "$CCT" "pgrep -f 'fuzzel.*--prompt=Rede'" "v1.6.1: craft-connect detecta o menu aberto (toggle — 2ª chamada fecha, mesma cura do 'Sessão')"
assert_grep "$CCT" "pkill -f 'fuzzel.*--prompt=Rede'" "v1.6.1: toggle da central de rede MATA a instância (regressão do 'menu empilhava' morta por contrato)"
assert_grep "$WBT" '#idle-inhibitor\.deactivated' "v1.4: café colapsa quando desativado (fim dos 'dois ícones de rede')"

# ── Gaveta com TOGGLE (v1.6.1): "abrir E fechar" (pedido do dono) ────────
assert_grep "$CDR" 'pgrep -x nwg-drawer' "v1.6.1: craft-drawer detecta a gaveta aberta (2º clique no ARCH fecha)"
assert_grep "$CDR" 'pkill -x nwg-drawer' "v1.6.1: toggle da gaveta MATA a instância (modelo craft-power/craft-connect — nunca empilha)"

# ── Idle AJUSTÁVEL (v1.6.1): "em quanto tempo o Pc entra em idle?" ───────
CID="$P/airootfs/usr/local/bin/craft-idle"
IDLECONF="$ST/elite/idle.conf"
AUTX="$ST/labwc/autostart"
assert_file "$CID" "v1.6.1: craft-idle existe (central de idle do dono)"
assert_file "$IDLECONF" "v1.6.1: idle.conf no skel (defaults documentados no arquivo)"
assert_grep "$IDLECONF" '^LOCK_MIN=10' "v1.6.1: default = trava aos 10min"
assert_grep "$IDLECONF" '^OFF_MIN=15' "v1.6.1: default = tela APAGA aos 15min (idle real, não tela fixa)"
assert_grep "$CID" "before-sleep 'hyprlock'" "v1.6.1: lock antes do suspend PRESERVADO no craft-idle"
assert_grep "$CID" 'resume .wlopm --on' "v1.6.1: resume → DPMS on (tela acorda JÁ no lock)"
assert_grep "$CID" 'Nunca' "v1.6.1: preset 'Nunca' (LOCK_MIN=0 → sem daemon, W-l manual)"
assert_grep "$CID" 'setsid craft-idle start' "v1.6.1: trocar o tempo reinicia o daemon NA HORA (sem relogin)"
assert_nogrep "$AUTX" 'timeout 600' "v1.6.1: hardcode 600s MORTO no autostart (o conf manda)"
assert_grep "$MXML" 'Tempo para travar a tela' "v1.6.1: menu do desktop expõe o ajuste de idle (mouse-first)"
assert_grep "$MXML" 'craft-idle' "v1.6.1: item do menu chama o craft-idle"
assert_grep "$REPO/scripts/apply-overlay.sh" 'craft-idle' "v1.6.1: craft-idle no file_permissions (0755 no live — senão 203/EXEC)"

# ── CSD coeso (v1.6.1): traffic lights TAMBÉM nos apps que desenham a ────
#    própria barra (GTK3 headerbar / GTK4 — pesquisa de fonte primária:
#    GTK3 pede CLIENT p/ headerbar; GTK4 não implementa protocolo de
#    decoração → CSD sempre; labwc-config(5): CSD nem sempre desligável).
#    O trio segue os PNGs do tema labwc: círculo colorido, glifo no hover,
#    cinza #5b5b60 inativo. Vale p/ QUALQUER app GTK que o usuário instalar.
G3="$ST/gtk-3.0/gtk.css"; G4="$ST/gtk-4.0/gtk.css"
assert_file "$G3" "v1.6.1: gtk.css GTK3 no skel (CSD traffic lights)"
assert_file "$G4" "v1.6.1: gtk.css GTK4 no skel (CSD traffic lights)"
assert_grep "$G3" '\.titlebutton\.close[[:space:]]*\{[[:space:]]*background-color: #ff5f57' "v1.6.1: GTK3 CSD close = círculo #ff5f57 (idem PNG labwc)"
assert_grep "$G3" '\.titlebutton\.minimize[[:space:]]*\{[[:space:]]*background-color: #febc2e' "v1.6.1: GTK3 CSD minimize = #febc2e"
assert_grep "$G3" '\.titlebutton\.maximize[[:space:]]*\{[[:space:]]*background-color: #28c840' "v1.6.1: GTK3 CSD maximize = #28c840"
assert_grep "$G3" ':backdrop' "v1.6.1: GTK3 CSD inativo = cinza (backdrop)"
assert_grep "$G4" 'windowcontrols button\.close[[:space:]]*\{[[:space:]]*background-color: #ff5f57' "v1.6.1: GTK4 windowcontrols close = #ff5f57"
assert_grep "$G4" 'windowcontrols button\.minimize[[:space:]]*\{[[:space:]]*background-color: #febc2e' "v1.6.1: GTK4 minimize = #febc2e"
assert_grep "$G4" 'windowcontrols button\.maximize[[:space:]]*\{[[:space:]]*background-color: #28c840' "v1.6.1: GTK4 maximize = #28c840"
assert_grep "$G4" ':backdrop' "v1.6.1: GTK4 inativo = cinza (backdrop)"
assert_grep "$G4" 'windowcontrols > separator' "v1.6.1: GTK4 separador dos controles oculto (trio colado — mac)"


# ── Sessão com TOGGLE (bug do burn test: menu empilhava, não fechava) ────
assert_grep "$CPW" "fuzzel.*--prompt=Sess" "v1.4: craft-power detecta o menu aberto (toggle)"
assert_grep "$CPW" 'pkill -x labnag' "v1.4: fallback labnag também vira toggle"

# ── Fixar na dock: mouse-first, descobrível ──────────────────────────────
assert_file "$CPP" "v1.4: craft-pin-pick existe (fixar sem CLI — burn test: 'tentei fixar e não consigo')"
assert_grep "$MXML" 'craft-pin-pick' "v1.4: root menu do desktop expõe 'Fixar app na dock…'"
assert_grep "$CPP" 'craft-pin add' "v1.4: picker delega no craft-pin (mesma maquinaria validada)"

phase_end
