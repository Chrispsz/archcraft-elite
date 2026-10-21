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

# ── v1.1 · PURGA DO APP-LAYER LEGADO (MEGA PROMPT — stack moderna) ─────
for gone in firefox thunar thunar-volman tumbler vim blueman pavucontrol; do
  assert_grep "$PKG" "^#${gone} # ELITE-REMOVED$" "v1.1: ${gone} comentado (saiu da ISO)"
  assert_nogrep "$PKG" "^${gone}$" "v1.1: ${gone} ativo sumiu"
done
assert_nogrep "$PKG" '^(mousepad|zathura|zathura-pdf-poppler|file-roller|xgps|xgpsspeed)$' \
  "v1.1: mousepad/zathura/file-roller/xgps* não voltam por engano"
for modern in brave-bin papers pwvucontrol bluetui impala helix; do
  assert_grep "$PKG" "^${modern}\$" "v1.1: ${modern} no packages (app-stack moderna)"
done
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
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.dock" '"custom/web"' "v1.0.4: dock tem launcher do navegador"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.dock" '"icon-size": 40' "v1.0.4: ícones grandes no dock (estilo dock)"
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/config.dock" '"tray"' "v1.0.4: dock SEM tray (SNI watcher único — tray fica na barra do topo)"
# Menu bar: tudo clicável (mouse-first — diretriz do dono; v1.1: rede abre
# impala no foot, volume abre pwvucontrol — zero applet/dialog GTK3 legado)
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" 'foot -e impala' "v1.1: rede abre impala no foot no clique (TUI rust)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" 'swaync-client -t' "v1.0.4: relógio abre central de notificações no clique"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" 'pwvucontrol' "v1.1: volume abre pwvucontrol no clique-direito (GTK4/Rust)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config.top" 'craft-power' "v1.0.4: botão power na barra do topo"
# Launchpad (nwg-drawer) + power gráfico (labnag) + ícones Papirus
assert_grep "$PKG" '^nwg-drawer$' "v1.0.4: nwg-drawer no packages (o Launchpad)"
assert_grep "$PKG" '^papirus-icon-theme$' "v1.0.4: papirus-icon-theme no packages (ícones de apps)"
assert_file "$P/airootfs/etc/skel/.config/nwg-drawer/drawer.css" "v1.0.4: CSS do Launchpad (Catppuccin) no skel"
assert_file "$P/airootfs/usr/local/bin/craft-drawer" "v1.0.4: craft-drawer (Launchpad + barra de sessão)"
assert_grep "$P/airootfs/usr/local/bin/craft-drawer" 'pbexit' "v1.0.4: Launchpad com barra de sessão (power bar)"
assert_file "$P/airootfs/usr/local/bin/craft-power" "v1.0.4: craft-power (menu de sessão mouse-first)"
assert_grep "$P/airootfs/usr/local/bin/craft-power" 'labnag' "v1.0.4: power via labnag (nag bar nativo do labwc)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'craft-drawer' "v1.0.4: W-d abre o Launchpad"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'systemctl poweroff' "v1.0.4: menu raiz com Desligar"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'systemctl reboot' "v1.0.4: menu raiz com Reboot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'config.top' "v1.0.4: autostart sobe a menu bar"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'config.dock' "v1.0.4: autostart sobe o DOCK"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'wallpaper.jpg' "v1.0.4: wallpaper de imagem (não cor sólida)"
assert_file "$P/airootfs/etc/skel/.config/labwc/wallpaper.jpg" "v1.0.4: wallpaper.jpg no skel"
assert_file "$P/airootfs/etc/skel/.config/gtk-3.0/settings.ini" "v1.0.4: settings.ini GTK3 no skel"
assert_grep "$P/airootfs/etc/skel/.config/gtk-3.0/settings.ini" 'Papirus-Dark' "v1.0.4: GTK usa Papirus-Dark (ícones de apps)"
assert_grep "$P/airootfs/etc/skel/.config/gtk-4.0/settings.ini" 'Papirus-Dark' "v1.0.4: GTK4 espelha o Papirus-Dark"
assert_grep "$REPO/scripts/apply-overlay.sh" 'craft-drawer' "v1.0.4: craft-drawer no file_permissions (0755 no live)"

# ── v1.0.4 RICE PRÓPRIO: themerc-override (fim do tema fantasma) ────────
assert_file "$P/airootfs/etc/skel/.config/labwc/themerc-override" "v1.0.4: themerc-override no skel (rice próprio — zero dependência de tema OB)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" 'window.active.border.color: #cba6f7' "v1.0.4: borda de janela ativa MAUVE (assinatura do rice)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" '#a6e3a1' "v1.0.4: traffic lights — iconify green"
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" '#f9e2af' "v1.0.4: traffic lights — max yellow"
assert_grep "$P/airootfs/etc/skel/.config/labwc/themerc-override" '#f38ba8' "v1.0.4: traffic lights — close red"
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
# papers/pwvucontrol/bluetui/impala/helix/brave-bin/yazi (assertados acima)
assert_grep "$PKG" '^qalculate-gtk$' "curadoria: qalculate (galculator saiu)"
assert_nogrep "$PKG" '^galculator$' "curadoria: galculator saiu (qalculate entra)"
assert_grep "$PKG" '^nwg-look$' "curadoria: nwg-look (xfce4-settings saiu)"
assert_grep "$PKG" '^yazi$' "curadoria: yazi FM TUI rust (ranger saiu — e agora é O gerenciador)"
# Satélites do labwc (docs oficiais: idle/automount/gamma/clipboard)
assert_grep "$PKG" '^swayidle$' "curadoria: swayidle (idle→lock automático)"
assert_grep "$PKG" '^udiskie$' "curadoria: udiskie (automount USB + notificação)"
assert_grep "$PKG" '^wlsunset$' "curadoria: wlsunset (night light)"
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
assert_nogrep "$PKG" '^firefox$' "v1.1: firefox saiu (brave-bin entra — Wayland-native)"
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
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'swayidle' "curadoria: swayidle no autostart"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'wlsunset' "curadoria: wlsunset no autostart"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'cliphist store' "curadoria: watcher cliphist no autostart"
# W-v clipboard + menu com os apps novos
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'W-v' "curadoria: W-v = histórico de clipboard"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'cliphist decode' "curadoria: pipe cliphist→fuzzel→wl-copy"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'foot -e yazi' "v1.1: menu Arquivos = yazi no foot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'foot -e helix' "v1.1: menu Editor = helix no foot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'papers' "v1.1: menu Leitor de PDF = papers (GTK4)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'foot -e impala' "v1.1: menu Rede = impala no foot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'foot -e bluetui' "v1.1: menu Bluetooth = bluetui no foot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'pwvucontrol' "v1.1: menu Mixer = pwvucontrol"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'foot -e 7z' "v1.1: menu Arquivos compactados = 7z no foot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'for b in brave librewolf' "v1.1: navegador do menu = brave em 1º"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'thunar|mousepad|nmtui|pulsemixer|file-roller' "v1.1: menu sem vestígio do app-layer legado"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'qalculate-gtk' "curadoria: qalculate no menu"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'nwg-look' "curadoria: nwg-look no menu"

# ── v1.1 · APP-STACK MODERNA (MEGA PROMPT): skel novo por dentro ────────
SKCFG="$P/airootfs/etc/skel/.config"
# brave: flags Wayland + aceleração de GPU completa
assert_file "$SKCFG/brave-flags.conf" "v1.1: brave-flags.conf no skel (lido pelo launcher do brave-bin)"
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
# yazi: tema Catppuccin Mocha com accent mauve + openers modernos
assert_file "$SKCFG/yazi/yazi.toml" "v1.1: yazi.toml no skel"
assert_file "$SKCFG/yazi/theme.toml" "v1.1: theme.toml do yazi no skel"
assert_grep "$SKCFG/yazi/theme.toml" '#cba6f7' "v1.1: tema yazi accent mauve #cba6f7 (assinatura do rice)"
assert_grep "$SKCFG/yazi/yazi.toml" 'helix "\$@"' "v1.1: opener de texto do yazi = helix"
assert_grep "$SKCFG/yazi/yazi.toml" 'mpv "\$@"' "v1.1: opener de mídia do yazi = mpv"
assert_grep "$SKCFG/yazi/yazi.toml" 'xdg-open "\$@"' "v1.1: opener genérico do yazi = xdg-open"
# helix: tema catppuccin_mocha + editor relativo
assert_file "$SKCFG/helix/config.toml" "v1.1: config.toml do helix no skel"
assert_grep "$SKCFG/helix/config.toml" '^theme = "catppuccin_mocha"$' "v1.1: helix no tema catppuccin_mocha"
assert_grep "$SKCFG/helix/config.toml" 'line-number\s*=\s*"relative"' "v1.1: helix com line-number relativo (modal)"
# rc.xml: keybinds da stack nova
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'foot -e yazi' "v1.1: rc.xml W-f/W-e → yazi no foot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'foot -e impala' "v1.1: rc.xml W-n → impala no foot"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'foot -e bluetui' "v1.1: rc.xml W-S-b → bluetui no foot (o bind que o craft-bat citava)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'for b in brave librewolf' "v1.1: rc.xml navegador = brave em 1º (cadeia)"
assert_nogrep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'thunar|nmtui|mousepad' "v1.1: rc.xml sem app legado nos binds"
assert_grep "$P/airootfs/etc/skel/.config/labwc/rc.xml" 'identifier="com\.github\.dominiksalvet\.pwvucontrol"' \
  "v1.1: windowRule do mixer aponta pwvucontrol (identificador novo)"
# waybar dock: launchers convertidos
assert_grep "$SKCFG/waybar/config.dock" '"on-click": "foot -e yazi"' "v1.1: dock abre yazi no foot (era thunar)"
assert_grep "$SKCFG/waybar/config.dock" '"on-click": "brave"' "v1.1: dock abre brave (era firefox)"
assert_grep "$SKCFG/waybar/config.dock" '"on-click": "foot -e helix"' "v1.1: dock abre helix no foot (era mousepad)"
# overlay de REDE: sysctl BBR + módulo carregado antes do systemd-sysctl
assert_file "$P/airootfs/etc/sysctl.d/99-elite-net.conf" "v1.1: /etc/sysctl.d/99-elite-net.conf na ISO (BBR assado)"
assert_grep "$P/airootfs/etc/sysctl.d/99-elite-net.conf" '^net\.core\.default_qdisc = fq$' "v1.1: qdisc fq (BBR exige)"
assert_grep "$P/airootfs/etc/sysctl.d/99-elite-net.conf" '^net\.ipv4\.tcp_congestion_control = bbr$' "v1.1: congestion control bbr"
assert_file "$P/airootfs/etc/modules-load.d/elite-bbr.conf" "v1.1: modules-load.d/elite-bbr.conf na ISO"
assert_grep "$P/airootfs/etc/modules-load.d/elite-bbr.conf" '^tcp_bbr$' "v1.1: módulo tcp_bbr carrega antes do sysctl"
# craft-drawer: o Launchpad abre arquivos no yazi
assert_grep "$P/airootfs/usr/local/bin/craft-drawer" '-fm "foot -e yazi"' "v1.1: craft-drawer -fm yazi no foot (era thunar)"
# build/CI v1.1: estágio AUR e RAM do QEMU (contratos de código)
assert_grep "$REPO/.ci/build.sh" 'aur_build brave-bin' "v1.1: estágio AUR — brave-bin → /var/cache/elite-local"
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

# ── v1.0.3: [9b] file_permissions — 12 caminhos 0:0:755 no profiledef ──
PD="$P/profiledef.sh"
for p in /usr/local/bin/elite-tune /usr/local/bin/elite-status /usr/local/bin/fg-booster \
         /usr/local/bin/craft-hello /usr/local/bin/craft-update /usr/local/bin/craft-clean \
         /usr/local/bin/craft-rollback /usr/local/bin/craft-lock /usr/local/bin/craft-logout \
         /usr/local/bin/craft-shot /usr/local/bin/craft-bat \
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
for d in openbox bspwm polybar tint2 rofi dunst alacritty kitty thunar zathura \
         mousepad file-roller blueman pavucontrol; do
  [[ -d "$SKEL/.config/$d" ]] && dead=$((dead+1))
done
assert_eq "$dead" "0" "E9: skel sem diretórios órfãos (v1.1: purga GTK3 varrida junto)"
assert_file "$SKEL/.config/labwc/rc.xml" "E9: configs labwc sobrevivem à limpeza"
assert_file "$SKEL/.config/yazi/yazi.toml" "E9: configs yazi (Elite) sobrevivem à limpeza"
# E12: os 3 seds no /etc/environment (upstream nano/firefox/alacritty → v1.1)
assert_grep "$ENVF" '^EDITOR=helix$' "E12: EDITOR=helix (vim/mousepad saem — editor modal)"
assert_grep "$ENVF" '^BROWSER=brave$' "E12: BROWSER=brave (firefox saiu)"
assert_grep "$ENVF" '^TERMINAL=foot$' "E12: TERMINAL=foot (alacritty saiu na v1.0.3)"
assert_grep "$ENVF" '^QT_QPA_PLATFORMTHEME=qt6ct$' "E12: o RESTO do environment upstream é preservado (sed no lugar)"
assert_nogrep "$ENVF" 'nano|alacritty|firefox' "E12: nenhum valor legado sobrevive nas 3 chaves"

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

phase_end
