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
# ── v2.2 · LEVEZA RADICAL: ISO 64-bit PURO (lib32 vira on-demand do instalado)
# A cadeia de lib32 do firstboot/elite-tune (vendor do rig) continua contratada
# nos testes de unidade/cadeia — o que saiu é o EMPACOTAMENTO de fábrica.
for p in lib32-mesa lib32-vulkan-radeon lib32-vulkan-intel lib32-gamemode lib32-mangohud; do
  assert_nogrep "$PKG" "^${p}$" "v2.2: ${p} FORA da ISO (64-bit puro — firstboot/elite-tune recolocam o lib32 do vendor no instalado)"
done
assert_nogrep "$PKG" '^xdotool$' "v2.2: xdotool FORA do packages.x86_64 (dep exclusiva do fg-booster extinto — fusão dos boosters; o crash-loop v1.0→v1.5 não pode renascer; o upstream também o trazia — banido nos DOIS lados)"
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
# v1.8.2: blueman SAIU desta lista — VOLTOU (GUI de bluetooth que o dono
# pediu no áudio 24/out; a esquizofrenia add∩remove tem contrato na fase 2)
for gone in firefox thunar-volman thunar-archive-plugin vim pavucontrol; do
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
# ── v2.3 · AUDITORIA MINUCIOSA (o teto da limpeza — diretriz do dono) ──
# Grupos do upstream = a porta dos fundos: no CI a expansão [5.2] trazia
# os MEMBROS REAIS mesmo com a linha do grupo comentada (grep -qxF
# substring casava com o próprio comentário). O fix -qx fecha o buraco;
# estes 4 grupos eram 71 pacotes de tema (24 ícones INCLUSIVE outro
# Papirus + 30 temas GTK + 15 cursores + 2 wallpapers):
for gonegrp in archcraft-icons archcraft-cursors archcraft-themes archcraft-wallpapers xorg; do
  assert_grep "$PKG" "^#${gonegrp} # ELITE-REMOVED$" "v2.3: grupo ${gonegrp} COMENTADO (expansão [5.2] ancorada não traz mais os membros)"
done
# DDX mortos (Xwayland não usa DDX; greeter usa modesetting embutido)
for gone in xf86-video-amdgpu xf86-video-ati xf86-video-intel xf86-video-nouveau xf86-video-vesa xf86-video-fbdev xorg-xinput; do
  assert_grep "$PKG" "^#${gone} # ELITE-REMOVED$" "v2.3: ${gone} comentado (DDX/input X mortos numa sessão Wayland)"
done
# GStreamer inteiro fora (mpv/Brave/qt6-multimedia-ffmpeg não consomem)
for gone in gstreamer gst-libav gst-plugins-good gst-plugins-ugly gst-plugins-bad gst-plugin-pipewire; do
  assert_grep "$PKG" "^#${gone} # ELITE-REMOVED$" "v2.3: ${gone} comentado (stack GStreamer sem consumidor)"
done
# Rede sem duplicação (NM: DHCP interno + wpa_supplicant)
for gone in dhcpcd iwd; do
  assert_grep "$PKG" "^#${gone} # ELITE-REMOVED$" "v2.3: ${gone} comentado (duplicação de daemon de rede)"
done
# Resíduos/dualezas (memtest86+ com o + ESCAPADO — em ERE '+' é quantificador)
for gone in xdotool boost man-db man-pages apparmor linux-firmware-marvell rxvt-unicode-terminfo archcraft-openbox-themes; do
  assert_grep "$PKG" "^#${gone} # ELITE-REMOVED$" "v2.3: ${gone} comentado (auditoria: inútil/duplicado)"
done
assert_grep "$PKG" '^#memtest86\+ # ELITE-REMOVED$' "v2.3: memtest86+ comentado (auditoria: nicho de resgate)"
assert_grep "$PKG" '^#memtest86\+-efi # ELITE-REMOVED$' "v2.3: memtest86+-efi comentado idem"
# Reposições cirúrgicas do que os grupos entregavam de útil
assert_grep "$PKG" '^xorg-server$' "v2.3: xorg-server EXPLÍCITO (greeter SDDM em X11 — DisplayServer não é wayland no conf)"
assert_grep "$PKG" '^archcraft-cursor-qogirr$' "v2.3: cursor Qogirr explícito (CursorTheme do greeter — o grupo que o trazia saiu)"
assert_grep "$REPO/scripts/apply-overlay.sh" 'grep -qx "\$g"' "v2.3: expansão de grupos com match EXATO de linha (o -qxF substring lia a própria linha comentada — a porta dos fundos dos grupos)"
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
assert_nofile "$P/airootfs/etc/skel/.config/waybar/config.dock" "v2.0: waybar DOCK saiu de cena (a dock é a nativa craft-dock-gui)"
assert_file "$P/airootfs/usr/local/bin/craft-dock-gui" "v2.0: dock NATIVA no pacote (craft-dock-gui — GTK3 + layer-shell)"
assert_file "$P/airootfs/etc/skel/.config/elite/dock.css" "v2.0: dock.css no skel (a pílula no AMOLED rice)"
assert_file "$P/airootfs/etc/skel/.config/elite/dock-pins" "v2.0: dock-pins no skel (1 ID .desktop por linha — ícones REAIS do tema)"
assert_grep "$P/airootfs/usr/local/bin/craft-dock-gui" 'Gio\.DesktopAppInfo' "v2.0: dock resolve ícone/nome/exec pelo .desktop (fim dos glifos e dos PNGs custom)"
assert_nofile "$P/airootfs/usr/local/bin/craft-pin-status" "v2.0: craft-pin-status saiu (nada executa JSON por pin)"
assert_nofile "$P/airootfs/usr/local/bin/craft-dock-config" "v2.0: craft-dock-config saiu (o autohide foi EXTINTO na v2.3.4 — a dock é sempre visível)"
assert_nofile "$P/airootfs/usr/local/bin/craft-dock-autohide" "v2.0: craft-dock-autohide saiu (W-S-d → craft-dock toggle)"
assert_file "$P/airootfs/etc/skel/.config/waybar/style.top.css" "v1.0.4: waybar CSS menu bar no skel"
assert_nofile "$P/airootfs/etc/skel/.config/waybar/style.dock.css" "v2.0: waybar CSS dock saiu de cena"
assert_file "$P/airootfs/etc/skel/.config/elite/dock.css" "v2.0: dock.css da dock NATIVA no skel"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" '"mpris"' "v1.0.3: waybar módulo música (MPRIS — SUA mídia: YouTube/player)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" '"format-empty": ""' "v1.0.3: mpris auto-esconde com nada tocando (zero sample music)"
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/config.top" '"battery' "v1.0.3: waybar sem bateria (desktop — diretriz do dono)"
assert_grep "$PKG" '^playerctl$' "v1.0.3: playerctl no packages (keybinds mídia + CLI)"
assert_file "$P/airootfs/etc/skel/.config/swaync/config.json" "v1.0.3: swaync config no skel"
assert_file "$P/airootfs/etc/skel/.config/fuzzel/fuzzel.ini" "v1.0.3: fuzzel config no skel"

# ── v1.0.4 DESKTOP v2: macOS-style, mouse-first ─────────────────────────
# Dock (waybar 2ª instância): launchers fixos + janelas abertas com ícones
# (v2.0) taskbar/tray/glifos da dock waybar: TODOS morreram com a dock.
# O lançador de apps fica EXCLUSIVO na barra superior (M2.4/M3.4):
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" '"custom/drawer"' "v1.9 M2.4: barra superior com o ARCH lançador no canto esquerdo (exclusivo)"
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/config.top" '"wlr/taskbar"' "v2.0: a barra superior não vira dock (as janelas alternam por A-Tab e o wlr/window mostra o foco)"
# v2.1.1 (run #93): o ID do pin tem que ser o .desktop REAL do pacote
# (brave-origin instala brave-browser.desktop) — 'brave.desktop' não existe.
assert_grep "$P/airootfs/etc/skel/.config/elite/dock-pins" 'brave-browser\.desktop' "v2.1.1: Brave fixado com o ID REAL (brave-browser.desktop — 'brave.desktop' crash-loopou a dock na #93)"
assert_nogrep "$P/airootfs/etc/skel/.config/elite/dock-pins" 'brave\.desktop' "v2.1.1: NENHUM pin com ID que não resolve (banido após a #93)"
assert_grep "$P/airootfs/etc/skel/.config/elite/dock-pins" 'foot\.desktop' "v2.0: Terminal (foot) fixado de fábrica"
assert_grep "$P/airootfs/etc/skel/.config/elite/dock-pins" 'thunar\.desktop' "v2.0: Arquivos (Thunar) fixado de fábrica"
assert_nogrep "$P/airootfs/etc/skel/.config/elite/dock-pins" 'craft-drawer\|uf3' "v2.0 M3.4: NENHUM lançador/ação/glifo na dock (só apps de verdade)"
# v2.0: pins = arquivo dock-pins (1 ID .desktop por linha) + craft-pin v2
assert_file "$P/airootfs/etc/skel/.config/elite/dock-pins" "v2.0: arquivo de pins viaja na ISO (fixar apps do usuário)"
assert_grep "$P/airootfs/usr/local/bin/craft-pin" 'craft-dock reload' "v2.0: craft-pin embarcado v2 (add/rm no dock-pins + reload por sinal)"
# Menu bar: tudo clicável (mouse-first — diretriz do dono; v1.4: rede abre
# a CENTRAL craft-connect — cabo+Wi-Fi+Bluetooth num só ícone; volume abre
# pwvucontrol — zero applet/dialog GTK3 legado)
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" '"on-click": "craft-connect"' "v1.4: rede abre a central de conectividade no clique (craft-connect)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" 'swaync-client -t' "v1.0.4: relógio abre central de notificações no clique"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" 'pwvucontrol' "v1.1: volume abre pwvucontrol no clique-direito (GTK4/Rust)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" 'craft-power' "v1.0.4: botão power na barra do topo"
# Launchpad (nwg-drawer) + power gráfico (labnag) + SEM tema de ícones (v2.2)
assert_grep "$PKG" '^nwg-drawer$' "v1.0.4: nwg-drawer no packages (o Launchpad)"
assert_nogrep "$PKG" '^papirus-icon-theme$' "v2.2: papirus-icon-theme FORA da ISO (leveza radical — diretriz do dono: cada app usa o próprio ícone, fallback base = Adwaita, dep de gtk3/gtk4)"
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
assert_grep "$P/airootfs/usr/local/bin/craft-bars" 'craft-dock-gui' "v2.0: o supervisor sobe a dock NATIVA"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'wallpaper\.png' "v2.0 M5.1: autostart prefere o PNG lossless (o JPEG era a fonte da poeira)"
assert_file "$P/airootfs/etc/skel/.config/labwc/wallpaper.png" "v2.0 M5.1: wallpaper.png no skel (vetorial flat — o dono relatou ruído/granulação/dithering no JPEG)"

# ── v1.2 DESKTOP v2.1: burn test do dono (rig B) — a cura completa ──────
# Forense da v1.1: 7 de 8 botões da dock com "format": "" (glifos perdidos
# na escrita — dock INVISÍVEL), botão do Brave com o glifo FIREFOX (U+F0239),
# CSS pedindo família "JetBrainsMono Nerd Font" (não existe no archcraft-fonts
# 2.0 — real: "JetBrainsMono NF"), e 4 printfs do heredoc do Calamares com \n
# literal → YAML inválido → "shellprocess@btrfs could not be loaded" (o
# instalador TRAVOU no rig do dono). v2.1 = a resposta caso a caso.
CT="$P/airootfs/etc/skel/.config/waybar/config.top"
# Top bar (v1.5): relógio no CENTRO, canto esquerdo LIMPO (ARCH saiu — spec),
# áudio só ícone, power no canto direito
assert_grep "$CT" '"modules-center": \["clock"\]' "v2.1: relógio no CENTRO da barra (diretriz do dono)"
assert_grep "$CT" '"fixed-center": true' "v1.5: fixed-center (centro EXATO independente dos lados)"
assert_nogrep "$CT" '"custom/menu"' "v1.5: lançador ARCH FORA do canto esquerdo (spec do dono — o Launchpad vive na dock)"
assert_grep "$CT" '"modules-left": \["custom/drawer", "wlr/window"\]' "v2.0: convenção dos rices — ESQUERDA = lançador (ARCH) + app focado"
assert_grep "$CT" '"modules-right": \[' "v2.1: o STATUS vive à DIREITA (volume/rede/tray/sessão — declutter do dono)"
assert_nogrep "$CT" '"custom/shot"' "v2.1: botão screenshot SAIU da barra (declutter do dono — a função vive em W-P/W-S-P; AÇÃO sem assento fixo)"
assert_nogrep "$CT" '"idle_inhibitor"' "v2.0: o café SAIU da barra (módulo extinto — 'botão estranho', áudio do dono)"
assert_grep "$CT" '"format": "\{icon\}"' "v2.1: áudio em modo ícone"
assert_nogrep "$CT" '"format": "\{volume\}' "v2.1: SEM porcentagem numérica no áudio (o '40%')"
assert_grep "$CT" '"custom/power"' "v1.8: botão de sessão presente (agora no CLUSTER ESQUERDO — spec do dono)"
assert_grep "$CT" '"format": "\\uf011"' "v2.1: glifo do power presente (FA power-off — BMP)"
# v2.1: o shot SAIU da barra (declutter do dono) — o glifo U+F0C4 não
# pode mais aparecer no config.top; a dock segue sem nenhum glifo —
# só ícones reais de apps (.desktop)
assert_nogrep "$CT" '\\uf0c4' "v2.1: glifo do shot EXTINTO da barra superior (módulo removido — declutter)"
assert_nofile "$P/airootfs/etc/skel/.config/waybar/config.dock" "v2.0: a dock waybar não existe mais (o glifo na dock morreu com ela)"
assert_nogrep "$P/airootfs/etc/skel/.config/elite/dock.css" '\\u[0-9a-fA-F]{5,}' "v2.1: nenhum escape de 5+ hex no CSS da dock (SMP trap: parseia como 4-hex + dígito)"
assert_nogrep "$CT" '\\u[0-9a-fA-F]{5,}' "v2.1: idem no config.top"
# v2.0: os 3 pins de fábrica são .desktop REAIS no dock-pins (Gio resolve
# ícone do tema) — a classe "waybar #5051" (3+ image modules) deixa de
# existir porque a dock não é mais waybar; craft-pin-status saiu de cena:
assert_nogrep "$P/airootfs/usr/local/bin/craft-dock-gui" 'craft-pin-status' "v2.0: o GUI não depende do craft-pin-status (morto — a classe anti-leak vira in-process)"
assert_grep "$P/airootfs/usr/local/bin/craft-dock-gui" 'DesktopAppInfo\.new' "v2.0: resolução de pin = .desktop do sistema"
assert_nogrep "$P/airootfs/usr/local/bin/craft-dock-gui" '\\u[0-9a-f]{4}' "v2.0: ZERO glifo Nerd Font no GUI da dock (ícones do tema — o pedido literal do dono)"
# CSS v2.0: a pílula no dock.css (GTK3 livre) — bbox único, ícone real:
DCSS="$P/airootfs/etc/skel/.config/elite/dock.css"
assert_grep "$DCSS" '#dockbox button' "v2.0: dock.css estiliza os botões da pílula"
assert_grep "$DCSS" 'min-height: 44px' "v2.0 M3.1: bbox único centralizado (a cura do desalinho fotografado)"
assert_grep "$DCSS" 'box-shadow: inset 0 -3px 0' "v2.0: indicador .running por inset shadow (zero shift)"
# Dock: grupo ÚNICO central (fixados + abertos), sem lock/power
assert_file "$P/airootfs/etc/skel/.config/elite/dock-pins" "v2.1: a estrutura da dock agora é o GUI + arquivo de pins (sem grupo waybar)"
assert_nofile "$P/airootfs/etc/skel/.config/waybar/config.dock" "v2.1: o separador fixos│abertos morreu com a dock waybar (pins = apps de verdade)"
assert_nofile "$P/airootfs/etc/skel/.config/waybar/config.dock" "v2.1: dock waybar extinta (sem modules-left/right — a pílula é conteúdo do GUI)"
assert_grep "$P/airootfs/usr/local/bin/craft-dock-gui" 'Gtk\.Orientation\.HORIZONTAL' "v2.1: pílula horizontal única (centrada na base — o 'horizontalmente menor' do áudio)"
assert_nogrep "$P/airootfs/usr/local/bin/craft-dock-gui" '"custom/lock"' "v2.1: dock SEM lock (menu de sessão na barra superior — GUI da dock)"
assert_nogrep "$P/airootfs/usr/local/bin/craft-dock-gui" '"custom/power"' "v2.1: dock SEM power (menu de sessão na barra superior — GUI da dock)"
# Fontes: família REAL do archcraft-fonts 2.0
assert_grep "$P/airootfs/etc/skel/.config/waybar/style.top.css" 'JetBrainsMono NF' "v2.1: CSS top com a família REAL (JetBrainsMono NF)"
assert_grep "$P/airootfs/etc/skel/.config/elite/dock.css" 'alpha\(#050508' "v2.1: dock.css na escada AMOLED (mantle translúcido)"
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/style.top.css" 'font-family: "?JetBrainsMono Nerd Font' "v2.1: família inexistente fora do font-family do CSS top (comentários citam o nome antigo de propósito)"
assert_nogrep "$P/airootfs/etc/skel/.config/elite/dock.css" 'JetBrainsMono Nerd Font' "v2.1: família inexistente fora de lugar nenhum no dock.css"
assert_grep "$P/airootfs/etc/skel/.config/fuzzel/fuzzel.ini" 'font=JetBrainsMono NF' "v2.1: fuzzel com a família REAL"
assert_nogrep "$P/airootfs/etc/skel/.config/fuzzel/fuzzel.ini" 'font=JetBrainsMono Nerd Font' "v2.1: fuzzel sem a família inexistente na diretiva font="
assert_nogrep "$P/airootfs/etc/skel/.config/elite/dock.css" '#custom-sep' "v2.1: dock.css sem separador (a era dos glifos morreu)"
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
assert_grep "$APPS/calamares.desktop" 'Icon=calamares' "v2.2 M3.3: Instalador com o ícone do PRÓPRIO pacote (calamares embarca hicolor — sem tema de ícones na ISO)"
assert_grep "$APPS/calamares.desktop" '^TryExec=calamares$' "v1.2: override preserva o TryExec do instalador"
assert_file "$APPS/abif.desktop" "v1.2: override do instalador CLI"
assert_grep "$APPS/abif.desktop" 'NoDisplay=true' "v1.2: instalador CLI fora do menu (2º instalador = sujeira)"
assert_file "$APPS/foot.desktop" "v1.2: override do .desktop do foot"
assert_grep "$APPS/foot.desktop" 'Icon=foot' "v2.2: foot com o ícone do PRÓPRIO pacote (hicolor do foot — taskbar/Launchpad sem placeholder)"
assert_grep "$APPS/footclient.desktop" 'NoDisplay=true' "v1.2: foot-client fora do menu (triplicação Foot — nome REAL do arquivo: footclient.desktop)"
assert_grep "$APPS/foot-server.desktop" 'NoDisplay=true' "v1.2: foot-server fora do menu (triplicação Foot)"
assert_grep "$APPS/xgps.desktop" 'NoDisplay=true' "v1.2: xgps fora do menu (GPS num desktop gaming?)"
assert_grep "$APPS/xgpsspeed.desktop" 'NoDisplay=true' "v1.2: xgpsspeed fora do menu"
assert_grep "$REPO/elite/packages.remove" '^gpsd$' "v1.2: gpsd listado no debloat (depend DURA do waybar — NoDisplay é a cura real)"
assert_grep "$REPO/elite/packages.remove" '^thunar-archive-plugin$' "v1.2: thunar-archive-plugin removido (era o elo que RESSUSCITAVA o thunar como dep — evidência do pacman db da v1.1)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'pacman -Rns --noconfirm gpsd' "v1.2: E13 tenta remover gpsd em build (falha segura — depend do waybar)"
# craft-pin v2.1: pins no grupo central, antes do separador
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin" 'dock-pins' "v2.1: craft-pin insere no ARQUIVO de pins (1 linha = 1 app real)"
assert_file "$P/airootfs/etc/skel/.config/gtk-3.0/settings.ini" "v1.0.4: settings.ini GTK3 no skel"
assert_nogrep "$P/airootfs/etc/skel/.config/gtk-3.0/settings.ini" 'Papirus|gtk-icon-theme-name' "v2.2: GTK3 SEM tema de ícones (fallback base Adwaita — dep dura de gtk3/gtk4, <1 MB)"
assert_nogrep "$P/airootfs/etc/skel/.config/gtk-4.0/settings.ini" 'Papirus|gtk-icon-theme-name' "v2.2: GTK4 espelha a ausência de tema de ícones"
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
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" '<showIcons>no</showIcons>' "v2.2: menu raiz SEM coluna de ícones (showIcons no — texto puro, sem tema de ícones)"
for png in close-active iconify-active max-active close_hover-active iconify_hover-active max_hover-active close-inactive max_toggled-active; do
  assert_file "$TH/${png}.png" "v1.6: asset ${png}.png no tema (traffic lights mac)"
done
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" 'window.button.width: 24' "v1.6: célula do botão 24px (círculo 12px mac)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" 'window.button.hover.bg.color: #00000000' "v1.6: overlay de hover OFF (o glifo mora no PNG)"
# Menu TEXTO PURO (v2.2 — o papirus-icon-theme saiu da ISO; o menu e o
# craft-power perderam os icon= — nenhum caminho de tema de ícones sobra)
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/menu.xml" '<item label=[^>]* icon=' "v2.2: menu.xml sem NENHUM atributo de ícone em item (texto puro — sem tema de ícones)"
assert_nogrep "$P/airootfs/usr/local/bin/craft-power" 'printf .%s.0icon' "v2.2: craft-power SEM protocolo de ícones do dmenu (NUL+icon+US extinto com o Papirus)"
assert_nogrep "$P/airootfs/usr/local/bin/craft-power" 'Papirus|\.svg' "v2.2: craft-power sem NENHUM path de ícone (entradas texto puro)"
# Keyring/polkit (a pergunta do dono — "o que é keyring que pede senha?")
assert_file "$P/airootfs/etc/polkit-1/rules.d/49-elite-desktop.rules" "v1.6: rule polkit Elite (UX desktop sem senha p/ ações comuns)"
assert_grep "$P/airootfs/etc/polkit-1/rules.d/49-elite-desktop.rules" 'org.freedesktop.login1.power-off' "v1.6: power-off sem senha p/ usuário ativo local"
assert_grep "$P/airootfs/etc/polkit-1/rules.d/49-elite-desktop.rules" 'modify.global-system' "v1.6: exceção deliberada — config global segue pedindo admin (sem wildcard)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'gnome-keyring-daemon --unlock' "v1.6: bootstrap do chaveiro vazio no live/autologin (fim dos prompts)"
# tray hardening (o bloco cinza do burn test)
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/style.top.css" '#tray' "v2.3.6: zero CSS de tray SNI (o módulo e o nm-applet morreram — o conector é texto no craft-connect)"
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
STG="$REPO/elite/airootfs/usr/local/bin/elite-install-stage"
assert_file "$STG" "v1.7: elite-install-stage existe (a lógica E10 saiu do YAML — classe 'Missing variables' morta)"
assert_grep "$STG" 'for kv in "\$KERNEL_SRC"/vmlinuz-\*' "v1.8.2: elite-install-stage copia da FONTE EM CASCATA (KERNEL_SRC — bootmnt é desmontado com copytoram=y)"
assert_grep "$STG" 'arch-chroot "[$]ROOT" mkinitcpio -P' "v1.9 M1.1: re-geração COMPLETA do initramfs no alvo (mkinitcpio -P — todos os presets, gate duro)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'kernel-copy-success' "v1.0.4: E10 preserva o marcador do upstream"
assert_grep "$P/airootfs/etc/sddm.conf.d/kde_settings.conf" '^Session=labwc$' "v1.0.3: SDDM autologin Session=labwc"
assert_grep "$P/airootfs/var/lib/sddm/state.conf" 'wayland-sessions/labwc\.desktop' "v1.0.3: greeter pré-seleciona labwc"
assert_nofile "$P/airootfs/etc/systemd/system/fg-booster.service" "v2.2: fg-booster.service EXTINTA do airootfs (fusão dos boosters — ananicy-cpp é o único daemon; ver contratos v2.2 na 20-static)"
# v2.3.6 — FIM DO nm-applet COM EVIDÊNCIA DUPLA: o rig v2.3.2 provou o
# custo da estética (sem conector) e o rig v2.3.5 provou o custo DO
# remédio — o ícone SNI de ethernet é bitmap de tema de ícones, fora da
# família de glifos da barra ("inconsistentes e espaçados" + "remove esse
# ícone feio de Pc"). O conector agora é TEXTO no craft-connect
# ('Wi-Fi: conectar à rede…' → picker fuzzel+nmcli, senha oculta).
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/autostart" '^[[:space:]]*nm-applet &' "v2.3.6: nm-applet FORA do autostart — o conector é o picker de texto do craft-connect (o feio PC da tray morreu)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/autostart" '^[[:space:]]*blueman-applet &' "v2.0: blueman-applet fora do autostart (o blueman-manager do craft-connect cobre — mesma decisão)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'craft-connect' "v2.0: o comentário do autostart documenta a direção v2.0 (um ponto só de conectividade)"

# ── v2.3.5 — AS CURAS DO RIG v2.3.2 (prints e relatos do dono) ──────────
assert_grep "$P/airootfs/usr/local/bin/craft-connect" 'Wi-Fi: conectar à rede' "v2.3.6: o conector é TEXTO no menu de rede (diretriz do dono: 'como texto escrito nela')"
assert_grep "$P/airootfs/usr/local/bin/craft-connect" 'nmcli device wifi connect' "v2.3.6: o picker conecta de verdade (nmcli — o fluxo do antigo applet, sem applet)"
assert_nogrep "$P/airootfs/usr/local/bin/craft-connect" 'nm-connection-editor' "v2.3.6: o EDITOR saiu do menu de rede (editar ≠ conectar; edição avançada no W-n)"
assert_grep "$P/airootfs/usr/local/share/applications/lstopo.desktop" 'NoDisplay=true' "v2.3.5: lstopo (hardware locality) fora do Launchpad — override NoDisplay, o padrão xgps"
assert_grep "$P/airootfs/usr/local/share/applications/lstopo-no-graphics.desktop" 'NoDisplay=true' "v2.3.5: lstopo-no-graphics também oculto (mesma classe — dep de terceiros não é app do dono)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/environment" 'XDG_DATA_DIRS=.*flatpak/exports/share' "v2.3.5: flatpak exports no XDG_DATA_DIRS da sessão (o Sober sem ícone é isso — literal, sem depender de expansão)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'Defaults !lecture' "v2.3.5: E20 mata a palestra do sudo (o print 'Presumimos que você recebeu…' é ruído, não segurança)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'visudo -cf' "v2.3.5: E20 valida o sudoers com visudo antes de aceitar (sudoers quebrado derruba TODA a elevação)"
assert_grep "$P/airootfs/etc/skel/.config/elite/idle.conf" 'SUSPEND_MIN=0' "v2.3.5: auto-suspend é OPT-IN no idle.conf (0 = off — a ISO não muda comportamento às escondidas)"
assert_grep "$P/airootfs/usr/local/bin/craft-idle" 'systemctl suspend' "v2.3.5: craft-idle suspende de verdade quando SUSPEND_MIN > 0 (o before-sleep trava antes — acorda no lock)"
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/config.top" '"tray"' "v2.3.6: módulo tray FORA da topbar (nada a exibir — udiskie roda --no-tray; o ícone SNI bitmap não pertence à família de glifos)"

# craft-dump — o 'btop completão' (pedido do dono: RAM, pacotes, CPU, uso,
# caches e os logs da Elite num arquivo único que ele pode me mandar)
DUMP="$P/airootfs/usr/local/bin/craft-dump"
assert_file "$DUMP" "v2.3.5: craft-dump existe (o diagnóstico completo do dono)"
assert_grep "$DUMP" '/dev/tcp/termbin\.com/9999' "v2.3.5: --upload via /dev/tcp (termbin sem nc — a ISO não o carrega)"
assert_grep "$DUMP" 'journalctl -b -u systemd-suspend' "v2.3.5: o dump caça o despertar (journal do suspend — o 'acordou sozinho' do dono)"
assert_grep "$DUMP" "tr -d '\\\\0'" "v2.3.6: NUL morre na fonte do dump (o rig flagrou 'byte nulo ignorado' no upload — journal cospem NUL)"

# ── v2.3.6 — O DUMP DO RIG (740 linhas): 4 curas de release + UX ─────────
TUN="$REPO/elite/airootfs/usr/local/bin/elite-tune"
assert_grep "$TUN" 'pacman-key --populate archlinux cachyos' "v2.3.6: firstboot popula as chaves ANTES do primeiro -Sy (db assinado por chave desconhecida falha INTEIRO — o rig flagrou: firstboot nunca completava)"
assert_grep "$TUN" 'timeout 90 pacman-key --recv-keys' "v2.3.6: recv-keys com timeout 90 (keyserver lento pendurou a unit 17min em 'activating' — o rig flagrou)"
assert_grep "$TUN" 'ensure_cachyos \|\| true' "v2.3.6: firstboot puxa o keyring FRESCO do mirror (o pacote datado 2024 é a raiz do 'chave desconhecida')"
assert_grep "$TUN" 'snapper --no-dbus -c root create-config' "v2.3.6: firstboot cria a config do snapper (grub-btrfsd nasce FAILED sem /.snapshots — o rig flagrou active=failed)"
assert_grep "$P/airootfs/etc/udev/rules.d/60-io-elite.rules" 'nvme\[0-9\]n\[0-9\]\*' "v2.3.6: regra NVMe casa só o bloco inteiro (partição sem queue/scheduler = ruído 'could not chase' — o rig flagrou)"
assert_grep "$P/airootfs/etc/skel/.config/fuzzel/fuzzel.ini" 'keyboard-focus=on-demand' "v2.3.6: fuzzel solta o grab (clique fora FECHA o menu — o rig flagrou menu preso na tela)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" 'pulseaudio#mic' "v2.3.6: microfone com assento na barra (paridade pedida pelo dono — clique muta o mic, direito gerencia)"
assert_grep "$P/airootfs/usr/local/bin/craft-power" 'Tempo de idle' "v2.3.6: controle do idle no menu Sessão (energia + idle na mesma porta — o dono perguntou 'tem como controlar facilmente?')"

# craft-rollback v2 — o rollback que de fato funciona (o rig provou que o
# timeshift NUNCA foi configurado; o par canônico do grub-btrfs é snapper)
CRB="$P/airootfs/usr/local/bin/craft-rollback"
assert_grep "$CRB" 'snapper --no-dbus -c root create --description' "v2.3.6: craft-rollback CRIA snapshot (a ação que o timeshift nunca teve wiring para fazer)"
assert_grep "$CRB" 'snapper --no-dbus -c root rollback' "v2.3.6: craft-rollback RESTAURA snapshot (rollback real — o reboot finaliza e o grub-btrfsd regenera o GRUB)"
assert_grep "$CRB" 'pkexec' "v2.3.6: elevação por ação via pkexec (GUI como root no Wayland morre com o env vazio — o menu roda como usuário)"
assert_grep "$CRB" 'fechado pelo usuário \(ESC\)' "v2.3.6: rollback segue a lei dos menus (ESC/143 benignos, stderr capturado)"
assert_grep "$DUMP" '/proc/acpi/wakeup' "v2.3.5: tabela ACPI wakeup no dump (quem acorda o rig: dispositivo vs BIOS)"
assert_grep "$DUMP" 'pacman -Qe' "v2.3.5: pacotes explícitos no dump (a coletânea audita o que existe de verdade)"
assert_grep "$DUMP" 'tail -n 150' "v2.3.5: logs tailados no dump (evidência recente — sem arquivo gigante)"
assert_grep "$REPO/scripts/apply-overlay.sh" '/usr/local/bin/craft-dump' "v2.3.5: craft-dump no file_permissions (senão 203/EXEC no live — a lição diag-boot2)"

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
# v2.3.6 — a evidência virou a decisão: timeshift JAMAIS foi configurado
# (sem config, sem snapshot — promessa pela metade) e o grub-btrfsd vigia
# /.snapshots, o diretório do SNAPPER (o par canônico do grub-btrfs).
assert_nogrep "$PKG" '^timeshift$' "v2.3.6: timeshift SAIU (nunca configurado — o rig provou; um rei só na estratégia de snapshot)"
assert_grep "$PKG" '^snapper$' "v2.3.6: snapper na ISO (o rig flagrou grub-btrfsd FAILED sem /.snapshots — o rollback precisava de quem cria o subvolume; a rota 'cockpit' da v1.0.4 nunca existiu de fato)"
assert_nogrep "$PKG" '^archcraft-omz$' "curadoria: oh-my-zsh saiu (plugins+starship)"
assert_nogrep "$PKG" '^archcraft-skeleton$' "curadoria: skel órfão do stock saiu (skel Elite é o dono)"
assert_nogrep "$PKG" '^archcraft-welcome$' "curadoria: welcome do stock saiu (craft-hello cobre)"
assert_nogrep "$PKG" '^archcraft-neofetch$' "curadoria: neofetch descontinuado saiu (fastfetch)"
assert_nogrep "$PKG" '^xfce4-settings$' "curadoria: xfce4-settings saiu (nwg-look entra)"
assert_nogrep "$PKG" '^xfce4-power-manager$' "curadoria: power manager saiu (swayidle entra)"
assert_nogrep "$PKG" '^gvfs-afc$' "curadoria: iPhone mount saiu (gvfs+mtp+smb ficam)"
assert_grep "$PKG" '^gvfs$' "curadoria: gvfs fica (trash/mtp/smb)"
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
# v1.6.2 — a classe clássica de leak/CPU-burn do waybar é script polling
# sem freio; as barras nasceram 100% módulos nativos (2 intervals: mpris
# 10s, clock 60s). v2.3.4 — UMA exceção CONTRACTUAL, barata e delimitada,
# para o botão de 2º plano do dono: o craft-bgapps é um ps do UID a cada
# 10s (3 processos curtos por tick — custo menor que o D-Bus do mpris).
# A não-regressão vira PRECISA: NENHUM outro exec além do bgapps (o
# custom/exec genérico da era do leak segue extinto).
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/config.top" '"custom/exec"' "v1.6.2: o módulo custom/exec genérico (a classe do leak) segue EXTINTO — a única exceção contratada é o bgapps"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" '"exec": "craft-bgapps status"' "v2.3.4: o ÚNICO exec da menu bar é o poller delimitado do craft-bgapps (ps do UID a cada 10s)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" '"return-type": "json"' "v2.3.4: o botão de 2º plano responde JSON (classe/texto — texto vazio = some da barra)"
# v2.0 — a classe de leak morre DE VEZ: a dock nativa não tem exec JSON
# por pin; o indicador é pgrep IN-PROCESS (timer GTK de 3s, um único
# processo). O config.top segue 100% módulos nativos (contrato acima).
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-gui" 'timeout_add\(3000, self\.poll_running\)' "v2.0: indicador in-process (timer GTK 3s — zero exec-json por pin)"
assert_nogrep "$P/airootfs/usr/local/bin/craft-dock-gui" '"exec"' "v2.0: o GUI não executa JSON de pin (a classe narrow v1.8 virou arquitetura)"
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
# v1.7 (dono: "deixa só os importantes", "sem muita complexidade"): as
# ferramentas de sistema saíram DO MENU — continuam INSTALADAS e vivem no
# Launchpad (nwg-drawer busca + categoriza); o dock é o comutador de
# janelas; Reconfigure/Encerrar eram ruído/perigo.
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'foot -e impala' "v1.7: impala saiu do menu (fica no craft-connect e no Launchpad)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'foot -e bluetui' "v1.7: bluetui saiu do menu (W-S-b e Launchpad)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'pwvucontrol' "v1.7: pwvucontrol saiu do menu (Launchpad)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'foot -e 7z' "v1.7: 7z saiu do menu (Launchpad)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'nwg-look' "v1.7: nwg-look saiu do menu (Launchpad)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'craft-hello|craft-rollback|foot -e btop' "v1.7: submenu Cockpit extinto do menu (ferramentas continuam no Launchpad)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'cockpit-menu|Janelas\.\.\.|Reconfigure|Encerrar labwc' "v1.7: Janelas/Reconfigure/Encerrar saíram (decisão do dono)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'Atualizar sistema' "v1.7: menu = Atualizar sistema (o 'importante' eleito pelo dono)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'command="foot -e craft-update"' "v1.7: Atualizar abre craft-update no foot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'Limpeza do sistema' "v1.7: menu = Limpeza do sistema (pacman cache + órfãos — o 'se for bom' é)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'command="foot -e craft-clean"' "v1.7: Limpeza abre craft-clean no foot"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'mousepad|nmtui|pulsemixer|file-roller|yazi|helix' "v1.1/v1.5: menu sem vestígio do app-layer legado/extinto"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'qalculate-gtk' "curadoria: qalculate no menu"

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
# v1.7: o avatar 'A' saiu do lock (a pergunta literal do dono no burn test) —
# e o PNG órfão saiu do overlay na v2.3.3 (hyprlock não o usa desde a v1.7)
assert_nogrep "$HLK" 'pixmaps/elite/avatar' "v1.7: lock SEM avatar (o 'A' do burn test saiu — decisão do dono)"
assert_nogrep "$HLK" 'rounding = -1' "v1.7: sem o círculo do avatar (só o campo tem rounding)"
assert_grep "$HLK" 'outer_color = rgba\(203, 166, 247' "v1.5→v1.7: borda MAUVE agora no CAMPO (a assinatura do rice)"
assert_grep "$HLK" 'placeholder_text = .*Digite a senha para desbloquear' "v1.5: placeholder da spec (campo sempre visível — fade_on_empty false)"
assert_grep "$HLK" 'fail_text = .*Senha Incorreta' "v1.5: feedback de FALHA em texto (spec)"
assert_grep "$HLK" 'check_text = .*Validando' "v1.5: feedback de VALIDAÇÃO em texto (spec)"
assert_grep "$HLK" 'fail_color = rgba\(243, 139, 168' "v1.5: falha em VERMELHO Catppuccin (spec)"
assert_grep "$HLK" 'dots_text_format = \*' "v1.5: asteriscos como feedback de digitação (spec)"
assert_grep "$HLK" 'fade_on_empty = false' "v1.5: campo de senha fixo (não some vazio — spec)"
assert_grep "$HLK" 'outline_thickness = 3' "v1.5: campo com borda estilizada (outline mauve)"
assert_grep "$HLK" 'outer_color = rgba\(203, 166, 247' "v1.5: borda do campo MAUVE"
assert_grep "$HLK" '\$font = JetBrainsMono NF' "v1.5: fonte do lock = a REAL do rice (definida em \$font)"
# v1.6: os PNGs de dock (terminal/files/web) saíram JUNTO com os módulos
# image# (fix waybar #5051) — glifos mandam; o avatar.png órfão saiu na v2.3.3
for gone in terminal files web avatar; do
  assert_nofile "$P/airootfs/usr/share/pixmaps/elite/${gone}.png" "v1.6→v2.3.3: pixmaps/elite/${gone}.png REMOVIDO (sem consumidor)"
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
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'nm-connection-editor' "v1.8.2: rc.xml W-n → nm-connection-editor (GUI — era impala TUI)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'blueman-manager' "v1.8.2: rc.xml W-S-b → blueman-manager (GUI — era bluetui TUI)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'for b in brave librewolf' "v1.1: rc.xml navegador = brave em 1º (cadeia)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'command="(foot -e )?(yazi|helix|nvtop|nmtui|mousepad)' "v1.5: rc.xml sem COMANDO de app extinto nos binds"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'identifier="com\.github\.dominiksalvet\.pwvucontrol"' \
  "v1.1: windowRule do mixer aponta pwvucontrol (identificador novo)"
# waybar dock: launchers convertidos (v1.5: ícones reais) — o ID REAL do
# brave já é contratado acima (v2.1.1, lição da #93)
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
for p in /usr/local/bin/elite-tune /usr/local/bin/elite-status \
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
# v1.7: a lógica E10 agora vive no elite-install-stage (arquivo real — o
# Calamares chama com ${ROOT}; variável de shell em YAML inline matava o
# instalador). O bloco de asserts abaixo aponta pro SCRIPT.
cp "$REPO/elite/airootfs/usr/local/bin/elite-install-stage" "$WORK/e10-block.txt"
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
assert_grep "$WORK/e10-block.txt" 'for kv in "\$KERNEL_SRC"/vmlinuz-\*' \
  "E10/v1.8.2: recopia da FONTE EM CASCATA (KERNEL_SRC — sobrevive ao copytoram)"
assert_grep "$WORK/e10-block.txt" 'arch-chroot "[$]ROOT" mkinitcpio -P' \
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
assert_match "$outA" '\$ systemctl enable --now ananicy-cpp\.service' "cadeia C (Setup A): serviço único ecoado, não executado (dry — v2.2: ananicy-cpp é o único daemon de boost)"
assert_match "$outA" 'FIRSTBOOT CONCLUÍDO' "cadeia C (Setup A): chegou ao fim sem abortar"
grep -q -- '-Rns' "$STATE/pacman.log" \
  && fail "cadeia C (Setup A): dry-run NÃO executa remoção" "log trouxe -Rns" \
  || ok "cadeia C (Setup A): dry-run não executou -Rns (só -Qq consultou)"
assert_nofile "/etc/modprobe.d/00-elite-nvidia.conf" "cadeia C (Setup A): nada escrito em /etc (dry é seco)"
assert_nofile "/etc/systemd/system/scx-elite.service" "cadeia C (Setup A): nenhuma unit de booster criada fora do dry (v2.2: scx-elite extinta — nada a criar)"
# regressão v4.4: dry não cria marker nem transmite wall (o aviso "REINICIE"
# numa SIMULAÇÃO seria mentira broadcastada para todos os ttys do usuário)
if [[ -s "$STATE/wall.log" ]]; then
  fail "cadeia C (Setup A): dry não transmite wall" "wall.log tem conteúdo"
else
  ok "cadeia C (Setup A): dry NÃO transmite wall (nenhum aviso falso)"
fi
fbm1=0; [[ -f /var/lib/elite/firstboot-done ]] && fbm1=1
assert_eq "$fbm1" "$fbm0" "cadeia C (Setup A): dry não cria/toca /var/lib/elite/firstboot-done"
assert_match "$outA" 'Instalador: calamares não está no disco' "cadeia C (Setup A): passo 2d no plano (mock sem calamares — o -Qq consultou e respeitou)"
assert_match "$outA" '\[dry\] remoção dos arquivos do instalador simulada' "cadeia C (Setup A): dry NÃO remove arquivo do instalador (só anuncia)"

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

# ── v2.3.4 — O INSTALADOR SAI DO SISTEMA INSTALADO (contratos de código) ──
# O unpackfs copia o root do LIVE inteiro: Calamares + atalho + wrappers
# chegavam ao disco e ficavam para sempre ("ficou o botão instalar
# archcraft ainda no menu de aplicativos", dono). O passo 2d do firstboot
# é EXCLUSIVO do instalado (o live precisa do Calamares).
assert_grep "$TUNE" 'pacman -Rns --noconfirm calamares' "v2.3.4: pacote do Calamares sai do instalado (mídia de instalação ≠ sistema)"
assert_grep "$TUNE" 'rm -f /usr/local/share/applications/calamares\.desktop' "v2.3.4: o atalho 'Instalar o Archcraft' sai do Launchpad do instalado (o sintoma que o dono vê)"
assert_grep "$TUNE" '/usr/local/bin/calamares-elite-log' "v2.3.4: wrapper de log do instalador sai do instalado (só vive no live)"
assert_grep "$TUNE" '/usr/local/bin/elite-install-stage' "v2.3.4: stage de instalação sai do instalado (não há 2ª instalação)"
assert_grep "$TUNE" 'rm -rf /etc/calamares' "v2.3.4: /etc/calamares sai do instalado (config de mídia, não de sistema)"
assert_grep "$P/airootfs/etc/systemd/system/elite-firstboot.service" 'ConditionPathExists=!/run/archiso' "v2.3.4: a remoção do instalador é exclusiva do INSTALADO (o live NUNCA roda o firstboot)"

# modo --status (uso diário): certifica sem alterar nada
outS="$(with_mocks env LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rtx-5060.txt" \
  NVIDIA_SMI='NVIDIA GeForce RTX 5060' \
  bash "$TUNE" --status 2>&1)"; rcS=$?
assert_eq "$rcS" "0" "cadeia C (uso): --status exit 0"
assert_match "$outS" 'ananicy-cpp' "cadeia C (uso): --status lista o booster único (v2.2 — scx/fg/dmemcg saíram da certificação)"

# ════════════════════════════════════════════════════════════════════
# 4.D MODO PADRÃO INTERATIVO (o enxerto em qualquer Arch) — dry de ponta
#     a ponta: dossiê, plano de cada seção [1]-[7] e o contrato "dry é
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
  assert_match "$outP" '\$ pacman -S --needed --noconfirm cachyos-settings cachyos-ananicy-rules ananicy-cpp' \
    "cadeia D: [1] stack CachyOS no plano (v2.2: booster único — sem scx/dmemcg)"
  if grep -q 'scx-scheds\|scx-tools\|dmemcg-booster' <<<"$outP"; then
    fail "cadeia D: [1] boosters extintos FORA do plano" "o plano ainda menciona scx-scheds/scx-tools/dmemcg-booster"
  else
    ok "cadeia D: [1] scx-scheds/scx-tools/dmemcg-booster fora do plano (fusão 4→1)"
  fi
  assert_match "$outP" '\$ grub-mkconfig -o /boot/grub/grub\.cfg' "cadeia D: [3] grub-mkconfig no plano"
  assert_match "$outP" 'NVIDIA blackwell → nvidia-open-dkms' "cadeia D: [4] driver certo p/ Blackwell"
  assert_match "$outP" '\[arquivo\] /etc/modprobe\.d/00-elite-nvidia\.conf' "cadeia D: [4] modprobe modeset/VRAM planejado"
  assert_match "$outP" 'Auto-limpeza: GPU nvidia' "cadeia D: [4] auto-limpeza de ICDs no plano"
  assert_match "$outP" '\[arquivo\] /etc/systemd/zram-generator\.conf' "cadeia D: [5] zram planejado"
  assert_match "$outP" '\[arquivo\] /etc/sysctl\.d/99-elite\.conf' "cadeia D: [5] sysctl de gaming planejado"
  assert_match "$outP" '\[arquivo\] /etc/udev/rules\.d/60-io-elite\.rules' "cadeia D: [5] udev I/O planejado"
  if grep -q 'fg-booster\|fg-boost' <<<"$outP"; then
    fail "cadeia D: [6] fg-booster EXTINTO ainda no plano" "a seção [6] antiga sobreviveu à fusão"
  else
    ok "cadeia D: [6] fg-booster/xdotool/slice fora do plano (v2.2: boost de jogo = gamemode)"
  fi
  assert_match "$outP" '\$ pacman -S --needed --noconfirm gamemode lib32-gamemode gamescope' \
    "cadeia D: [6] stack de jogo no plano"
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
  if grep -q 'ExecStart=/usr/bin/scx_bpfland' "$LA"; then
    fail "cadeia F (Setup A): unit scx-elite NÃO deve ser escrita" "o firstboot ainda cria a scx-elite (v2.2: EXTINTA)"
  else
    ok "cadeia F (Setup A): nenhuma unit scx escrita (scheduler = BORE do kernel — v2.2)"
  fi
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
WBT="$ST/waybar/style.top.css"; WBD="$ST/elite/dock.css"
DRW="$ST/nwg-drawer/drawer.css";  SWC="$ST/swaync/style.css"
FZL="$ST/fuzzel/fuzzel.ini";       FTC="$ST/foot/foot.ini"
THR="$ST/labwc/themerc-override";  AST="$ST/labwc/autostart"
WAL="$ST/labwc/wallpaper.png"

# ── Escada AMOLED idêntica nos 4 CSS (base do sistema = preto REAL) ────────
for f in "$WBT" "$WBD" "$SWC" "$DRW"; do
  fn=$(basename "$(dirname "$f")")/$(basename "$f")
  assert_nogrep "$f" '#1e1e2e' "v1.3: $fn anti-regressão (base Catppuccin 1e1e2e extinta)"
  assert_nogrep "$f" '#11111b' "v1.3: $fn anti-regressão (crust Catppuccin 11111b extinto)"
done
# v2.0: o dock.css é GTK3-literal (sem @define-color) — o preto REAL e a
# escada AMOLED vivem como literais rgba/alpha nos dois arquivos da dock:
assert_grep "$WBT" '^@define-color crust[[:space:]]*#000000' "v1.3: style.top.css crust = #000000 (preto REAL)"
assert_grep "$P/airootfs/etc/skel/.config/elite/dock.css" 'rgba..0, 0, 0.|alpha\(#050508' "v2.0: dock.css na escada AMOLED (mantle/preto literais — preto REAL)"

# ── Acentos Catppuccin INTACTOS (o colorido não escureceu) ─────────────────
assert_grep "$P/airootfs/etc/skel/.config/elite/dock.css" 'cdd6f4' "v2.3.6: indicador da dock NEUTRO (o dono: 'efeito roxo estranho' — destaque por luz; o mauve segue vivo na barra/fuzzel/foot/themerc)"
# (v2.0: o dock.css não carrega @define-color — cores literais GTK3; o peach é herança da waybar que saiu)

# ── Cores SEMÂNTICAS de marca na dock (v1.3: identidade do dono) ───────────
assert_nogrep "$WBD" '#custom-drawer' "v1.9 M3.4: CSS da dock SEM o drawer (Launchpad saiu — sem CSS órfão)"
# (v2.0: idem — a paleta waybar termina no style.top.css)

# ── Glifo ARCH no drawer (pair atualizado acima: uf00b → uf303) ────────────
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" '"format": "\\uf303"' "v1.9 M2.4: glifo ARCH U+F303 agora EXCLUSIVO da barra superior (o lançador)"
assert_nogrep "$P/airootfs/etc/skel/.config/elite/dock.css" '\\uf00b' "v1.3: glifo grid genérico extinto (CSS da dock)"

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

# ── v2.3.1 — FIM DO SILÊNCIO DOS MENUS (denúncia do rig: "os menus ────────
# morreram e não funcionam"): os 5 dropdowns da família craft-* vivem no
# fuzzel e falhavam com stderr no /dev/null — morte calada, zero rastro.
# Contrato: TODOS logam em ~/.cache/elite/menus.log (helper mlog) e o
# fuzzel call captura o stderr (crash vira linha de log + notify).
for menu in craft-power craft-connect craft-pin-pick craft-idle craft-logout craft-bgapps; do
  assert_grep "$P/airootfs/usr/local/bin/$menu" 'menus\.log' "v2.3.1: $menu loga falhas em menus.log (fim do silêncio — rig: 'os menus morreram')"
  # positivos (mais robustos que nogrep: o 2>/dev/null do pkill do toggle é legítimo)
  assert_grep "$P/airootfs/usr/local/bin/$menu" '2>"\$errf"' "v2.3.1: $menu captura o stderr do fuzzel (mktemp errf — crash deixa rastro)"
  assert_grep "$P/airootfs/usr/local/bin/$menu" 'FUZZEL FALHOU' "v2.3.1: $menu tem caminho de erro de fuzzel LOGADO (exit != 0 nunca é calado)"
  assert_grep "$P/airootfs/usr/local/bin/$menu" 'eq 143' "v2.3.5: $menu trata SIGTERM do toggle/cross-dismiss como fechamento benigno (o falso 'fuzzel exit=143' crítico do print do dono morreu)"
done
assert_grep "$P/airootfs/usr/local/bin/craft-pin-pick" 'command -v fuzzel >/dev/null 2>&1 \|\|' "v2.3.1: craft-pin-pick com guard de fuzzel (morria calado na linha 21)"

# ── v2.3.4 — DOCK SEMPRE VISÍVEL (o fim do autohide) ──────────────────────────
# O autohide morreu NA PRÁTICA: o dono instalou a v2.3.x e a dock escondeu
# no fim do teaser e o hotspot nunca mais a devolveu ("ela sumiu e não
# apareceu mais" / "tira esse auto hide da dock, funcionando como funciona
# as outras distros"). Cura = semântica do protocolo: layer BOTTOM (tela
# cheia e gaveta cobrem sozinhas) + zona exclusiva (maximizadas respeitam
# a faixa) — zero polling, zero heurística, zero estado para corromper.
assert_nogrep "$P/airootfs/usr/local/bin/craft-dock-gui" 'hotspot|HOTSPOT|teaser|SHOW_AT_START|_startup_hide|HIDE_DELAY|hide_now' "v2.3.4: nenhum resquício do autohide no GUI (hotspot/teaser/hide-on-leave extintos)"
assert_grep "$P/airootfs/usr/local/bin/craft-dock-gui" 'GtkLayerShell\.Layer\.BOTTOM' "v2.3.4: dock na layer BOTTOM — some SÓ sob tela cheia/gaveta (o 'sumiu e não apareceu mais' é estruturalmente impossível: não há estado de autohide)"
assert_grep "$P/airootfs/usr/local/bin/craft-dock-gui" 'auto_exclusive_zone_enable' "v2.3.4: zona exclusiva = comportamento das outras distros (maximizada/tileada respeita a faixa)"
assert_grep "$P/airootfs/usr/local/bin/craft-dock-gui" 'dock iniciada' "v2.3.4: arranque logado no dock.log (evidência de boot p/ forense do rig)"
assert_grep "$P/airootfs/etc/skel/.config/elite/dock.css" '#dockbox' "v2.3.4: dock.css segue estilizando a pílula (sem regra órfã do hotspot)"
assert_nogrep "$P/airootfs/etc/skel/.config/elite/dock.css" 'hotspot' "v2.3.4: dock.css sem o seletor #hotspot (morto junto com o autohide)"

# ── v2.3.4 — CRAFT-BGAPPS (o botão dos 2º planos, pedido do dono) ─────────
# "Um botão tray na topbar para encerrar programas que estão executando em
# segundo plano e seja do usuário caso queira" (easyeffects etc.).
# SEM LISTA INVENTADA: varredura /proc real do UID; a casca da sessão é a
# única coisa protegida. Mesma lei dos menus: toggle, cross-dismiss,
# stderr capturado, falha logada + notify.
BGA="$P/airootfs/usr/local/bin/craft-bgapps"
assert_file "$BGA" "v2.3.4: craft-bgapps existe (encerrar apps de 2º plano — escolha do usuário)"
assert_grep "$BGA" 'ps -u "\$\(id -u\)"' "v2.3.4: varredura /proc real do UID (sem premissa de app — nada de lista inventada)"
assert_grep "$BGA" 'is_protected' "v2.3.4: casca da sessão protegida (labwc/waybar/áudio/dbus/portais nunca aparecem no menu)"
assert_grep "$BGA" 'kill -TERM "\$pid"' "v2.3.4: término SIGTERM no escolhido (nunca KILL às cegas)"
assert_grep "$BGA" 'command -v notify-send' "v2.3.4: confirmação na tela (o dono vê o que foi encerrado)"
assert_grep "$BGA" 'FUZZEL FALHOU' "v2.3.4: menu de processos segue a lei dos menus (falha logada, nunca calada)"
assert_grep "$BGA" 'prompt=Encer' "v2.3.4: prompt único 'Encerrar' (toggle próprio + cross-dismiss sem colisão)"
assert_nogrep "$BGA" 'pacman' "v2.3.4: craft-bgapps NÃO toca no sistema de pacotes (encerrar processo ≠ desinstalar)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" '"custom/bgapps"' "v2.3.4: módulo custom/bgapps na top bar (o botão 'tray' pedido pelo dono)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" '"craft-bgapps menu"' "v2.3.4: clique no botão abre o menu de processos"
assert_grep "$P/airootfs/etc/skel/.config/waybar/style.top.css" '#custom-bgapps' "v2.3.4: CSS do botão no rice (pêssego quando há o que encerrar)"
assert_grep "$P/airootfs/usr/local/bin/craft-power" 'prompt=Encer' "v2.3.4: craft-power fecha o menu de processos (cross-dismiss na lei v1.8.2)"
assert_grep "$P/airootfs/usr/local/bin/craft-connect" 'prompt=\(Sess\|Encer\|Senha\)' "v2.3.6: craft-connect fecha Sessão/Encerrar/Senha (cross-dismiss na lei v1.8.2)"

# ── v2.3.1 — PROBE COBRE MENUS (o gate via enxergar o que o rig vê) ───────
assert_grep "$P/airootfs/usr/local/bin/elite-session-probe" 'FUZZEL_BIN=' "v2.3.1: probe colhe FUZZEL_BIN (binário dos 5 menus)"
assert_grep "$P/airootfs/usr/local/bin/elite-session-probe" 'FUZZEL_INI=' "v2.3.1: probe parseia o fuzzel.ini do usuário (config corrompida = menus mortos)"
assert_grep "$P/airootfs/usr/local/bin/elite-session-probe" 'MENUS\|' "v2.3.1: probe taila o menus.log no bloco do serial (falha de menu chega no gate)"
assert_grep "$P/airootfs/usr/local/bin/elite-session-probe" 'DOCK\|' "v2.3.1: probe taila o dock.log no bloco do serial (arranque da dock chega no gate)"

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

# ── Wallpaper: v2.0 — ARTE OFICIAL DA FAMÍLIA (a lição do áudio) ────────
# O dono: nada gerado por IA, nada desenhado à mão — "busque trazer
# coisas de outras distros, temas e etc". Cura v2.0: o wallpaper é o
# minimal-27.png DO PACOTE OFICIAL archcraft-backgrounds-minimal 1.0-6
# (GPL3, packages.archcraft.io — a mesma família de rice, arte
# profissional, coerência garantida). PNG LOSSLESS 4053×2280: fundo flat
# escuro (zero poeira por construção), tom violeta casando com o Mauve.
# sha256 anti-tamper + teto de tamanho (higiene de ISO).
assert_file "$WAL" "v2.0 M5.1: wallpaper.png existe (arte oficial archcraft-backgrounds-minimal, PNG lossless)"
walsha="$(sha256sum "$WAL" | cut -d' ' -f1)"
assert_eq "$walsha" "9e13031e0c0ca127cb5a2a6b0c5415eb4920c8df87c3315a318bc5ddbad10b8f" \
  "v2.0 M5.1: wallpaper.png é o minimal-27 do pacote oficial selado (sha256 anti-tamper — trocou = contrato quebra)"
walsize="$(stat -c%s "$WAL")"
sizeok=1; awk "BEGIN{exit !($walsize <= 2097152)}" || sizeok=0
assert_eq "$sizeok" "1" "v2.0 M5.1: wallpaper ≤2 MiB (higiene de ISO — tem $walsize B)"
waltype="$(file -b --mime-type "$WAL" 2>/dev/null)"
assert_eq "$waltype" "image/png" "v2.0 M5.1: wallpaper é PNG real (lossless — extensão honesta; tem '$waltype')"
if command -v python3 >/dev/null 2>&1; then
  if python3 -c 'from PIL import Image' 2>/dev/null; then
    walout="$(python3 - "$WAL" << 'PYEOF'
import sys
from PIL import Image
rgb = Image.open(sys.argv[1]).convert('RGB')
total = rgb.size[0] * rgb.size[1]
# sem numpy: histograma de L dá média/p1 (cumulativa); preto puro = contagem
# conjunta pixel a pixel (a lição v1.3 do artefato JPEG vale pra sempre)
black = 100.0 * sum(1 for p in rgb.getdata() if p == (0, 0, 0)) / total
h = rgb.convert('L').histogram()
n = sum(h)
mean = sum(i * c for i, c in enumerate(h)) / n
# v1.9: paleta distinta (anti-poeira) + flatness do céu (patches 64x64 no
# terço superior com passo 4 — arte flat tem 1 cor por patch; ruído tem N)
import random
rnd = random.Random(99)
worst = 0
px = rgb.load()
W, H = rgb.size
# patches no FUNDO aberto do minimal-27 (cristas ficam no terço inferior;
# a ilustração central ocupa o miolo) — os 4 quadrantes das bordas
regions = [(0, 0), (W - 64, 0), (0, 300), (W - 64, 300),
           (0, H // 2), (W - 64, H // 2)]
for bx, by in regions:
    worst = max(worst, len({px[bx + i, by + j]
                            for i in range(0, 64, 4)
                            for j in range(0, 64, 4)}))
print(rgb.size[0], round(black, 2), round(mean, 1), worst)
PYEOF
)"
    read -r walres _ walmean walsky <<<"$walout"
    if [[ "$walout" =~ ^[0-9]+[[:space:]][0-9.]+[[:space:]][0-9.]+[[:space:]][0-9.]+$ ]]; then
      widthok=1; awk "BEGIN{exit !($walres >= 2560)}" || widthok=0
      assert_eq "$widthok" "1" "v2.0 M5.1: wallpaper de alta definição (≥2560px de largura — o minimal-27 nativo tem 4053px; tem $walres)"
      meanok=1; awk "BEGIN{exit !($walmean <= 60.0)}" || meanok=0
      assert_eq "$meanok" "1" "v2.0 M5.1: luma média ≤60 (dark que não cega — o minimal-27 tem ~35; tem $walmean)"
      skyok=1; awk "BEGIN{exit !($walsky == 1)}" || skyok=0
      assert_eq "$skyok" "1" "v2.0 M5.1: FUNDO FLAT medido (patches no campo aberto com 1 única cor — PNG lossless não tem poeira; tem $walsky cor)"
    else
      fail "v2.0 M5.1: métricas do wallpaper" "saída do python3/PIL inesperada: '${walout:0:80}' (lição da run #34: nunca mais falha silenciosa com 'tem %')"
    fi
  else
    fail "v2.0 M5.1: métricas do wallpaper" "python3 presente sem PIL — instale python-pillow (o CI já traz)"
  fi
else
  skip "v2.0 M5.1: métricas do wallpaper" "python3 indisponível"
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
CPT="$ST/waybar/config.top"
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
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-gui" 'PILL_FLOAT = 6' "v2.3.4: pílula flutuando 6px acima da base (gap DENTRO da superfície — a zona exclusiva cobre o conjunto)"
assert_nogrep "$WBD" 'margin-bottom: -' "v1.4: auto-hide (margem negativa) EXTINTO do CSS — o talho de ícones cortados na base era isso"
assert_nogrep "$WBD" 'font-size: 32px' "v1.9 M3.1: SEM estado de zoom no hover (font-size constante — a caixa não muda de tamanho)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-gui" 'get_display_name' "v2.0: tooltip honesto = o NOME do .desktop (Brave Origin — do próprio sistema)"

# v1.5 (spec do dono): lançador ARCH EXTINTO da menu bar — canto esquerdo
# limpo (só o nome do app focado); o Launchpad vive na TOP BAR (v1.9 M3.4)
assert_nogrep "$CPT" '"custom/menu"' "v1.5: módulo custom/menu EXTINTO do config.top (spec)"
assert_grep "$CPT" '"modules-left": \["custom/drawer", "wlr/window"\]' "v2.0: cluster esquerdo = ARCH + app focado (convenção dos rices)"
assert_grep "$CPT" '"fixed-center": true' "v1.5: clock no centro EXATO (fixed-center)"
assert_nogrep "$P/airootfs/etc/skel/.config/elite/dock.css" '\\uf303' "v1.9 M3.4: ARCH U+F303 NÃO vive na dock (exclusivo da top bar — CSS da dock)"
assert_nogrep "$P/airootfs/usr/local/bin/craft-dock-gui" '"on-click": "craft-drawer"' "v1.9 M3.4: nenhum on-click de Launchpad na dock (GUI — sem duplicidade de lançador)"
assert_nogrep "$WBT" '#custom-menu' "v1.5: CSS sem regra órfã do custom-menu"
assert_grep "$P/airootfs/etc/skel/.config/waybar/style.top.css" '#custom-drawer \{' "v1.9 M2.4: identidade mauve do ARCH viva na BARRA SUPERIOR (lançador exclusivo)"

# ── Conectividade: UM ícone p/ cabo + Wi-Fi + Bluetooth ──────────────────
assert_grep "$CPT" '"on-click": "craft-connect"' "v1.4: rede → central de conectividade (um só ícone — diretrize do dono)"
assert_file "$CCT" "v1.4: craft-connect existe"
assert_grep "$CCT" 'foot -e impala' "v1.4: central abre impala (Wi-Fi/Ethernet)"
assert_grep "$CCT" 'foot -e bluetui' "v1.4: central abre bluetui (Bluetooth)"
assert_grep "$CCT" "--prompt='Rede" "v1.4: prompt 'Rede' (nunca colide com o toggle do 'Sessão')"
assert_grep "$CCT" "pgrep -f 'fuzzel.*--prompt=\(Rede\|Wi-Fi\)'" "v2.3.6: toggle detecta a central OU o picker aberto (2ª chamada fecha — mesma cura do 'Sessão')"
assert_grep "$CCT" "pkill -f 'fuzzel.*--prompt=\(Rede\|Wi-Fi\)'" "v1.6.1: toggle da central de rede MATA a instância (regressão do 'menu empilhava' morta por contrato)"
assert_nogrep "$WBT" 'idle-inhibitor' "v2.0: o café saiu da barra E do CSS (botão estranho — áudio do dono)"

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
assert_grep "$G4" 'windowcontrols > button\.close[[:space:]]*\{[[:space:]]*background-color: #ff5f57' "v1.8.2: GTK4 close = #ff5f57 no par que o Adwaita usa (> button.close)"
assert_grep "$G4" 'windowcontrols > button\.minimize[[:space:]]*\{[[:space:]]*background-color: #febc2e' "v1.8.2: GTK4 minimize = #febc2e (> button.minimize)"
assert_grep "$G4" 'windowcontrols > button\.maximize[[:space:]]*\{[[:space:]]*background-color: #28c840' "v1.8.2: GTK4 maximize = #28c840 (> button.maximize)"
assert_grep "$G4" 'windowcontrols > button > image' "v1.8.2: o círculo INTERNO do Adwaita é neutralizado (a cura do botão gigante)"
assert_grep "$G4" ':backdrop' "v1.6.1: GTK4 inativo = cinza (backdrop)"
assert_grep "$G4" 'windowcontrols > separator' "v1.6.1: GTK4 separador dos controles oculto (trio colado — mac)"


# ── Sessão com TOGGLE (bug do burn test: menu empilhava, não fechava) ────
assert_grep "$CPW" "fuzzel.*--prompt=Sess" "v1.4: craft-power detecta o menu aberto (toggle)"
assert_grep "$CPW" 'pkill -x labnag' "v1.4: fallback labnag também vira toggle"

# ── Fixar na dock: mouse-first, descobrível ──────────────────────────────
assert_file "$CPP" "v1.4: craft-pin-pick existe (fixar sem CLI — burn test: 'tentei fixar e não consigo')"
assert_grep "$MXML" 'craft-pin-pick' "v1.4: root menu do desktop expõe 'Fixar app na dock…'"
assert_grep "$CPP" 'craft-pin add' "v1.4: picker delega no craft-pin (mesma maquinaria validada)"
# v2.0.1: o picker acordou para a dock NATIVA — o config.dock (extinto na
# v2.0) era pré-requisito e matava o picker ("✖ config.dock não
# encontrado"); glifo Nerd Font morreu com a dock waybar; o ID entregue
# ao craft-pin é o .desktop REAL (Gio.DesktopAppInfo é case-sensitive).
assert_nogrep "$CPP" 'config\.dock' "v2.0.1: picker NÃO exige o config.dock extinto (dock = craft-dock-gui)"
assert_nogrep "$CPP" 'glyph' "v2.0.1: mapa de glifo/cor extinto do picker (ícone real via tema/Gio)"
assert_grep "$CPP" 'craft-pin add "\$base"' "v2.0.1: picker fixa o ID .desktop REAL (case-sensitive — sem slug)"
assert_nogrep "$CPP" "SC2034|glyph=''" "v2.0.1: zero variável morta no picker (shellcheck warning é gate)"

# ── Barras SUPERVISIONADAS (v1.6.3): burn test da v1.6.2 subiu SÓ com ────
#    wallpaper — waybar morreu calado, sem stderr, e o gate do CI (serial)
#    para no login: nunca vê a sessão gráfica. Cura: craft-bars vigia as
#    duas instâncias (respawn ≤5s) + stderr em ~/.cache/elite/bars.log
#    (teto 1 MiB — diretriz v1.6.2 de crescimento limitado).
CBR="$P/airootfs/usr/local/bin/craft-bars"
assert_file "$CBR" "v1.6.3: craft-bars existe (supervisor das duas barras)"
assert_grep "$AUTX" 'craft-bars &' "v1.6.3: autostart delega as barras ao craft-bars"
assert_nogrep "$AUTX" 'waybar -c' "v1.6.3: autostart NÃO sobe waybar direto (supervisão única — respawn garantido)"
assert_grep "$CBR" 'config\.top' "v1.6.3: supervisor vigia a barra de cima"
assert_grep "$CBR" 'craft-dock-gui' "v2.0: supervisor vigia a dock NATIVA (≤5s, mesma garantia da v1.6.3)"
assert_grep "$CBR" '1048576' "v1.6.3: bars.log com teto 1 MiB (sem crescimento ilimitado)"
assert_grep "$CBR" 'waybar -c [$]2' "v1.6.3: stderr do waybar capturado no log (forense do próximo incidente)"
assert_grep "$CBR" 'pgrep -f' "v1.6.3: respawn por pgrep (não empilha instância)"
assert_grep "$REPO/scripts/apply-overlay.sh" 'craft-bars' "v1.6.3: craft-bars no file_permissions (0755 no live — senão 203/EXEC)"

# ── SESSÃO OBSERVÁVEL (v1.7.1): a classe "subiu só o wallpaper" ──────────
#    atravessou v1.6.2→v1.7.0 porque o gate do CI parava no LOGIN e o
#    guard do autostart falhava calado. Cura em 4 camadas, TODAS
#    contratadas: (1) guard do autostart loga no bars.log; (2) craft-bars
#    registra exit code de cada morte; (3) elite-session-probe colhe o
#    estado real da sessão 60s pós-graphical.target e imprime no console;
#    (4) o gate do CI (build.yml + qemu-boot-test.sh) grepa o bloco e
#    cobra WAYBAR_COUNT≥1 + DOCK_COUNT≥1 e BARS_EXITS=0 (v2.1.1 — a sessão
#    v2.0 é 1 waybar + dock GTK; o "-ge 2" da era waybar-dock era defasado e
#    a #93 flagrou: 1/2 com a dock crash-loopando por pin inexistente).
AUTX2="$P/airootfs/etc/skel/.config/labwc/autostart"
PROBE="$P/airootfs/usr/local/bin/elite-session-probe"
PSVC="$P/airootfs/etc/systemd/system/elite-session-probe.service"
assert_file "$PROBE" "v1.7.1: elite-session-probe existe (evidência da sessão gráfica)"
assert_grep "$PROBE" 'ELITE_PROBE_BEGIN' "v1.7.1: probe abre bloco marcado (gate grepa o serial)"
assert_grep "$PROBE" 'ELITE_PROBE_END' "v1.7.1: probe fecha bloco marcado (fim determinístico)"
assert_grep "$PROBE" 'WAYBAR_COUNT=' "v1.7.1: probe reporta WAYBAR_COUNT (waybar top vivo)"
assert_grep "$PROBE" 'DOCK_COUNT=' "v2.1.1: probe reporta DOCK_COUNT (dock GTK faz parte da sessão — a #93 provou: dock morta = sessão incompleta)"
assert_grep "$PROBE" 'BARS_EXITS=' "v1.7.1: probe reporta BARS_EXITS (mortes de barra — waybar/dock)"
assert_grep "$PROBE" '/dev/console' "v1.7.1: probe escreve no console (serial no QEMU)"
assert_file "$PSVC" "v1.7.1: elite-session-probe.service existe"
assert_grep "$PSVC" 'ExecStart=/usr/local/bin/elite-session-probe' "v1.7.1: service aponta o probe real"
assert_grep "$PSVC" 'WantedBy=graphical.target' "v1.7.1: service ligado ao graphical.target"
assert_grep "$PSVC" 'After=graphical.target' "v1.7.1: service roda DEPOIS do target (não briga com o boot)"
if [ -L "$P/airootfs/etc/systemd/system/graphical.target.wants/elite-session-probe.service" ]; then
  ok "v1.7.1: probe habilitado no graphical.target.wants (symlink)"
else
  fail "v1.7.1: probe habilitado no graphical.target.wants (symlink)" "unidade existe mas NÃO está habilitada — o probe nunca rodaria"
fi
assert_grep "$AUTX2" 'binário waybar AUSENTE' "v1.7.1: guard loga waybar ausente no bars.log (fim do silêncio)"
assert_grep "$AUTX2" 'craft-bars ausente/sem bit de execução' "v1.7.1: guard loga craft-bars quebrado no bars.log"
assert_grep "$CBR" 'SAIU exit=' "v1.7.1: craft-bars registra exit code de cada morte do waybar"
assert_grep "$REPO/scripts/apply-overlay.sh" 'elite-session-probe' "v1.7.1: probe no file_permissions (0755 — sem isso o service morre 203/EXEC)"
assert_grep "$REPO/scripts/qemu-boot-test.sh" 'ELITE_PROBE_END' "v1.7.1: gate local espera o bloco do probe"
assert_grep "$REPO/scripts/qemu-boot-test.sh" 'WAYBAR_COUNT' "v1.7.1: gate local cobra o waybar vivo"
assert_grep "$REPO/scripts/qemu-boot-test.sh" 'DOCK_COUNT' "v2.1.1: gate local cobra a dock viva (sessão v2.0 = waybar + dock GTK)"
assert_grep "$REPO/.github/workflows/build.yml" 'ELITE_PROBE_END' "v1.7.1: gate do CI espera o bloco do probe"
assert_grep "$REPO/.github/workflows/build.yml" 'WAYBAR_COUNT' "v1.7.1: gate do CI cobra o waybar vivo"
assert_grep "$REPO/.github/workflows/build.yml" 'DOCK_COUNT' "v2.1.1: gate do CI cobra a dock viva (sessão v2.0 = waybar + dock GTK)"

# ── DESKTOP v3 (v1.8 — branch v2, a SPEC DO DONO no burn test da v1.7.0): ─
#    "canto superior esquerdo o ícone do archlinux... relógio centralizado,
#    no superior esquerdo botões úteis como print, wi-fi/redes/conectividade
#    (engloba bluetooth), botão liga/desliga/reset... dock estilo macOS/
#    cosmic centralizada com os principais programas fixados, fixar/
#    desfixar, animação no hover e indicador de programa fixado que está
#    aberto; programa aberto mesmo não fixado vai pra lá em uso".
CTP8="$P/airootfs/etc/skel/.config/waybar/config.top"
CPS="$P/airootfs/usr/local/bin/craft-pin-status"
# v2.1 (declutter do dono: “tá um pouco cheio”): o print SAIU da barra —
# a spec v1.8 pedia “botões úteis como print”, mas a diretriz nova vence:
# a função segue em W-P/W-S-P e a barra fica no essencial.
assert_nogrep "$CTP8" '"custom/shot"' "v2.1: print SAIU da barra (spec v1.8 evoluída — declutter do dono; W-P/W-S-P cobrem)"
assert_nogrep "$CTP8" '"on-click": "craft-shot"' "v2.1: nenhum on-click de shot no topo (o craft-shot segue no rc.xml)"
assert_nogrep "$CTP8" '"format": "\\uf0c4"' "v2.1: glifo do print extinto do topo"
assert_grep "$CTP8" '"on-click": "craft-connect"' "v1.8: wi-fi/redes/bt = 1 botão → central (spec: 'conectividade num geral')"
assert_grep "$CTP8" '"on-click": "craft-power"' "v1.8: liga/desliga/reset = botão de sessão no cluster esquerdo"
# v2.0: pins = IDs .desktop no dock-pins; indicador = pgrep in-process;
# craft-pin-status está EXTINTO (o GUI é o único consumidor de estado):
assert_nofile "$CPS" "v2.0: craft-pin-status EXTINTO (o indicador mora no GUI)"
assert_grep "$P/airootfs/usr/local/bin/craft-dock-gui" 'pgrep' "v2.0: detecção de aberto = pgrep (sem rede, sem jq — mesma dieta)"
# v2.1 — REGRESSÃO DA RUN #92: GLib.get_user_home_dir() NÃO EXISTE em
# PyGObject (AttributeError → dock crash-loopava 20× no boot; o gate da
# sessão pegou). A API para o .cache é get_user_cache_dir() (XDG).
assert_nogrep "$P/airootfs/usr/local/bin/craft-dock-gui" 'get_user_home_dir' "v2.1: API inexistente GLib.get_user_home_dir BANIDA do dock (run #92: AttributeError → crash-loop 20×)"
assert_grep "$P/airootfs/usr/local/bin/craft-dock-gui" 'get_user_cache_dir' "v2.1: log da dock via GLib.get_user_cache_dir (XDG_CACHE_HOME correto)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-gui" 'add_class..running' "v2.0: o ponto acende via classe .running no GUI"
assert_grep "$P/airootfs/usr/local/bin/craft-pin" 'craft-dock reload' \
  "v2.0: craft-pin recarrega a dock por sinal (fim da era waybar)"
assert_grep "$P/airootfs/etc/skel/.config/elite/dock.css" '\.running' \
  "v2.0: dock.css tem o seletor .running (o ponto do pin)"
assert_grep "$P/airootfs/etc/skel/.config/elite/dock.css" 'inset 0 -3px' \
  "v2.0: indicador = barra 3px na base (sem shift de layout)"

# ── BOOT COM PROVA (v1.8 — a RECORRÊNCIA do 'premature end of file'): ────
#    a v1.7.0 recopiava o kernel com `cp -f ... &&` (exit IGNORADO): falha
#    de cópia no rig = kernel truncado + instalação "feliz" + GRUB morto
#    (foto IMG_20261023_180301). O gate do CI rodava cp PRÓPRIO — divergência
#    gate⇄rig. Cura: script auto-verificante + gate executa o SCRIPT REAL.
STG="$REPO/elite/airootfs/usr/local/bin/elite-install-stage"
assert_grep "$STG" 'cmp -s "\$kv" "\$tmp"' "v1.8: cópia do kernel verificada byte-a-byte ANTES da promoção"
assert_grep "$STG" 'cmp -s "\$kv" "\${ROOT}/boot/\${kbase}"' "v1.8: re-verificação APÓS a promoção (prova final no alvo)"
assert_grep "$STG" '"\$dst_size" = "\$src_size"' "v1.10: tamanho conferido fonte⇄destino — só promove com IGUALDADE provada (v1.10: retry ×2 antes de falhar alto)"
assert_grep "$STG" 'rm -f "\$tmp"' "v1.8: tmp removido nos caminhos de erro (nada de lixo em /boot)"
assert_nogrep "$STG" 'cp -f "\$kv" "\${ROOT}/boot/\${kbase}" &&' \
  "v1.8: o cp cego antigo (exit ignorado) EXTINTO do stage"
VI8="$REPO/.github/workflows/verify-install.yml"
assert_grep "$VI8" 'rootfs/usr/local/bin/elite-install-stage /mnt/elite' \
  "v1.8: gate de install EXECUTA o script real (fim da divergência gate⇄rig)"
assert_grep "$VI8" 'mount --bind' "v1.8: gate bind-monta o pendrive no caminho exato do live"
assert_grep "$VI8" 'PIPESTATUS' "v1.8: rc REAL do stage checado (tee não mascara falha)"
assert_grep "$VI8" 'BORE truncado no alvo' "v1.8: BORE truncado no alvo = gate VERMELHO (não só informativo)"

# ── Menu raiz SEM fantasmas (v1.6.3): burn test do dono — 'os programas ──
#    que deveriam abrir não abrem'. Regra com contrato: todo Execute
#    command=X tem binário REAL na ISO — packages.add ∪ /usr/local/bin ∪
#    allowlist base (sh: runner dos compostos; systemctl: systemd; xdg-open:
#    xdg-utils — os três vêm do base/pacstrap, fora do packages.add).
MADD="$REPO/elite/packages.add"
menu_allow=" sh systemctl xdg-open "
while IFS= read -r mcmd; do
  [ -z "$mcmd" ] && continue
  mbin=${mcmd%% *}
  case "$menu_allow" in *" $mbin "*) continue ;; esac
  if grep -qx "$mbin" "$MADD" 2>/dev/null || [ -x "$P/airootfs/usr/local/bin/$mbin" ]; then
    ok "v1.6.3: item de menu '$mbin' existe na ISO (packages.add ∪ usr/local/bin)"
  else
    fail "v1.6.3: item de menu '$mbin' existe na ISO (packages.add ∪ usr/local/bin)" "comando órfão no menu.xml: $mcmd"
  fi
done < <(sed -n 's/.*action name="Execute" command="\([^"]*\)".*/\1/p' "$MXML")
# v1.7: craft-hello saiu DO MENU (o Launchpad cobre o overview) — o binário
# segue instalado para CLI; o contrato do foot -e craft-hello (v1.6.3) deu
# lugar ao nogrep da curadoria acima.
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'for b in brave librewolf' "v1.1: navegador do menu = brave em 1º"

# ── v2.2 — MENU TEXTO PURO (o fixture menu-icons-papirus.txt foi EXTINTO):
#    nenhum item carrega icon= e o tema não existe mais na ISO. A regra 1
#    do header do menu.xml (binário REAL em command=X) segue valendo; a
#    regra 2 virou "zero ícones de tema" (diretriz do dono, leveza radical).
root_no_icon=$(sed -n '/id="root-menu"/,$p' "$MXML" | grep '<item label=' | grep -c 'icon=' || true)
assert_eq "$root_no_icon" "0" "v2.2: zero itens com icon= no root-menu (texto puro — sem tema de ícones)"

# ── MENU VISÍVEL (v1.7 → v2.2): a fonte do MenuItem manda na altura dos
#    itens (src/theme.c: menu_item_height = font_height + 2*padding_y — o
#    padding cancela). v2.2: sem coluna de ícones, a altura do item É o
#    texto — a mesma regra tipográfica segue valendo sozinha.
RCX="$P/airootfs/etc/skel/.config/labwc/rc.xml"
assert_grep "$RCX" 'place="MenuItem"' "v1.7: fonte do MenuItem definida no rc.xml (o dial da altura dos itens)"
assert_grep "$RCX" '<size>12</size>' "v1.7: fonte do menu 12px → itens ~27px (v2.2: texto puro, sem coluna de ícones)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" 'menu.items.padding.x: 8' "v1.7: padding.x do menu 8px (respiro do texto — themerc-override)"

# ── BOTÃO DIREITO (v1.7 — "tira essa mudança de ambiente… eu acho feio"): ─
#    direita = menu raiz curado; a lista de janelas morreu (dock comuta);
#    clique esquerdo no desktop ficou limpo; scroll segue trocando área.
assert_nogrep "$RCX" 'client-list-combined-menu' "v1.7: a lista de janelas do botão direito EXTINTA (dock é o comutador)"
assert_nogrep "$RCX" 'button="Left" action="Press"' "v1.7: clique esquerdo no desktop sem menu (zero menu acidental)"
assert_grep "$RCX" 'ShowMenu" menu="root-menu' "v1.7: botão direito abre o menu raiz (padrão universal)"
assert_grep "$RCX" 'GoToDesktop' "v1.7: scroll no desktop segue trocando de workspace (o gesto que o dono prefere)"

# ── LOCK SCREEN SÃO (v1.7 — as 3 fotos do burn test): markup cru fora, ───
#    avatar 'A' fora, relógio fora da borda (light bar).
HYP="$P/airootfs/etc/skel/.config/hypr/hyprlock.conf"
assert_nogrep "$HYP" '<span' "v1.7: hyprlock SEM markup cru (placeholder não parseia Pango — cor é propriedade)"
assert_nogrep "$HYP" 'avatar\.png' "v1.7: hyprlock SEM o avatar 'A' (decisão do dono)"
assert_grep "$HYP" 'Digite a senha para desbloquear' "v1.7: placeholder em texto plano (o literal do dono)"
assert_grep "$HYP" 'position = 0, 300' "v1.7: relógio a 300px do topo (terço superior, longe da light bar)"

# ── INSTALADOR À PROVA DE $ (v1.7 — a classe do "Installation Failed — ───
#    Missing variables are: kv,kbase,…"): o Calamares expande TODO $ de
#    command: inline contra ROOT/USER/LANG + global storage ANTES do shell
#    (doc no header do shellprocess_kms.conf); variável de shell em YAML =
#    morte na máquina real, invisível pro gate manual do CI. Contrato: nos
#    heredocs de .conf do Calamares do elite-customize, só a allowlist do
#    Calamares (ROOT/USER/LANG = shellprocess; LOCALE = packages.conf;
#    SERIAL/RANDOM/PHRASE = bootloader.conf) pode aparecer.
ECF="$REPO/elite/fragments/elite-customize.sh"
assert_grep "$ECF" 'command: "/usr/local/bin/elite-install-stage [$][{]ROOT[}]"' "v1.7: shellprocess@btrfs = 1 comando só (elite-install-stage \${ROOT})"
assert_grep "$REPO/scripts/apply-overlay.sh" 'elite-install-stage' "v1.7: elite-install-stage no file_permissions (0755 no live — senão 203/EXEC)"
CALAW=" ROOT USER LANG LOCALE SERIAL RANDOM PHRASE "
cal_bad=""
while IFS= read -r calvar; do
  case "$CALAW" in *" $calvar "*) continue ;; esac
  cal_bad="$cal_bad $calvar"
done < <(awk "/cat > \\/etc\\/calamares.*<<'EOSB'/{f=1;next} /^EOSB$/{f=0} f && /^[[:space:]]*#/{next} f" "$ECF" \
         | grep -oE '\$\{?[A-Za-z_]+\}?' | tr -d '${}' | sort -u)
assert_eq "$cal_bad" "" "v1.7: heredocs do Calamares sem \$ de shell (allowlist-only — a classe 'Missing variables' morta por contrato)"

# ── v2.3.2 — E18/E19: log do Calamares 25/out (rig do dono) ──
#   a) ufw.service habilitado pelo post_install upstream com o pacote JÁ
#      fora da ISO (E14) → "Unit ufw.service does not exist" em toda
#      instalação; b) pacman -Rns nvidia-open (nome que não existe — o
#      real é nvidia-open-dkms) → transação inteira morre; c) `which`
#      ausente da ISO → "command not found" no post_install e no grubcfg;
#   d) slideshow default girando "Next slide" a cada 5s (banner debloat).
assert_grep "$ECF" "s/'ufw\.service'//g" \
  "E18a: ufw.service sai da lista de units do post_install (pacote saiu no E14 — unit não existe mais)"
assert_grep "$ECF" 'nvidia-open-dkms\\1/g' \
  "E18b: nvidia-open → nvidia-open-dkms no post_install (nome real — a transação -Rns volta a funcionar)"
assert_grep "$REPO/elite/packages.add" '^which$' \
  "E18c: `which` na ISO (post_install:315 e grubcfg chamam which — 'command not found' em toda instalação)"
assert_grep "$ECF" 'defaultPartitionTableType: \[ "gpt", "msdos" \]' \
  "E19a: defaultPartitionTableType explícito — reproduz o automático (GPT/UEFI, msdos/BIOS) e mata o warning"
assert_grep "$ECF" 's/nonempty: true/minLength: 1/' \
  "E19b: users.conf nonempty → minLength: 1 (a 3.4 ignora nonempty — warning morto)"
assert_grep "$ECF" "slideshow: \"show.qml\"" \
  "E19c: branding aponta pro banner único estático (fim do loop 'Next slide' a cada 5s)"
assert_grep "$ECF" 'show.qml' \
  "E19c: show.qml mínimo existe no customize (slide estático, sem dependência de calamares.slideshow)"

phase_end
