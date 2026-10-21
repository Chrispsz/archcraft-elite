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
assert_file "$P/airootfs/etc/skel/.config/waybar/config" "v1.0.3: waybar config no skel"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config" '"mpris"' "v1.0.3: waybar módulo música (MPRIS — SUA mídia: YouTube/player)"
assert_grep "$P/airootfs/etc/skel/.config/waybar/config" '"format-empty": ""' "v1.0.3: mpris auto-esconde com nada tocando (zero sample music)"
assert_nogrep "$P/airootfs/etc/skel/.config/waybar/config" '"battery' "v1.0.3: waybar sem bateria (desktop — diretriz do dono)"
assert_grep "$PKG" '^playerctl$' "v1.0.3: playerctl no packages (keybinds mídia + CLI)"
assert_file "$P/airootfs/etc/skel/.config/swaync/config.json" "v1.0.3: swaync config no skel"
assert_file "$P/airootfs/etc/skel/.config/fuzzel/fuzzel.ini" "v1.0.3: fuzzel config no skel"
assert_grep "$P/airootfs/etc/sddm.conf.d/kde_settings.conf" '^Session=labwc$' "v1.0.3: SDDM autologin Session=labwc"
assert_grep "$P/airootfs/var/lib/sddm/state.conf" 'wayland-sessions/labwc\.desktop' "v1.0.3: greeter pré-seleciona labwc"
assert_grep "$P/airootfs/etc/systemd/system/fg-booster.service" '^Slice=fg-boost\.slice$' "v1.0.3: fg-booster com Slice= (fix restart-loop)"
assert_grep "$P/airootfs/etc/skel/.config/labwc/autostart" 'blueman-applet' "v1.0.3: autostart sobe blueman-applet (fix bluetooth)"

# ── v1.0.3 CURADORIA "brabos 2026": uso geral de fábrica ───────────────
# GUI best-in-class (substituições validadas na pesquisa Task 42-a)
assert_grep "$PKG" '^mousepad$' "curadoria: mousepad (editor GUI — geany saiu)"
assert_grep "$PKG" '^zathura$' "curadoria: zathura (PDF — atril saiu)"
assert_grep "$PKG" '^zathura-pdf-poppler$' "curadoria: backend poppler do zathura"
assert_grep "$PKG" '^qalculate-gtk$' "curadoria: qalculate (galculator saiu)"
assert_grep "$PKG" '^file-roller$' "curadoria: file-roller (xarchiver saiu)"
assert_grep "$PKG" '^nwg-look$' "curadoria: nwg-look (xfce4-settings saiu)"
assert_grep "$PKG" '^yazi$' "curadoria: yazi FM TUI rust (ranger saiu)"
assert_grep "$PKG" '^thunar$' "curadoria: thunar fica (O gerenciador de arquivos)"
assert_grep "$PKG" '^pavucontrol$' "curadoria: pavucontrol fica (mixer GUI)"
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
assert_grep "$PKG" '^firefox$' "curadoria: firefox fica (default em toda distro 2026)"
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
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'mousepad' "curadoria: mousepad no menu"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'qalculate-gtk' "curadoria: qalculate no menu"
assert_grep "$P/airootfs/etc/skel/.config/labwc/menu.xml" 'nwg-look' "curadoria: nwg-look no menu"

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

# ── v1.0.3: E5 (Calamares) e E9 (skel) EXECUTADOS de verdade ───────────
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

# E9: cria skel sujo (dirs órfãos), roda o bloco, confere a limpeza
for d in openbox bspwm polybar tint2 rofi dunst alacritty kitty; do
  mkdir -p "$P/airootfs/etc/skel/.config/$d"
done
sed -n '/^## \[E9\]/,$p' "$FRAG" \
  | sed "s|/etc/skel|$P/airootfs/etc/skel|g" > "$WORK/e9-block.sh"
if bash "$WORK/e9-block.sh" 2>"$WORK/e9.err"; then
  ok "E9: bloco de limpeza do skel executa limpo"
else
  fail "E9: bloco de limpeza do skel" "$(head -c 200 "$WORK/e9.err")"
fi
dead=0
for d in openbox bspwm polybar tint2 rofi dunst alacritty kitty; do
  [[ -d "$P/airootfs/etc/skel/.config/$d" ]] && dead=$((dead+1))
done
assert_eq "$dead" "0" "E9: skel sem diretórios órfãos de sessões removidas"
assert_file "$P/airootfs/etc/skel/.config/labwc/rc.xml" "E9: configs labwc sobrevivem à limpeza"

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

E01="$P/efiboot/loader/entries/01-archiso-linux.conf"
E02="$P/efiboot/loader/entries/02-archiso-opensource.conf"
E03="$P/efiboot/loader/entries/03-archiso-nvidia.conf"
assert_grep "$E01" 'vmlinuz-linux-cachyos-bore' "cadeia A: entrada default (UEFI) → kernel BORE"
assert_grep "$E01" 'BORE kernel' "cadeia A: título default rebatizado Elite"
assert_nogrep "$E01" 'initramfs-linux\.img' "cadeia A: initramfs default trocado (sem vestígio stock)"
assert_grep "$E02" 'vmlinuz-linux-cachyos-bore' "cadeia A: entrada opensource (UEFI) → kernel BORE"
assert_grep "$E03" 'vmlinuz-linux$' "cadeia A (A COROA): entrada NVIDIA permanece no kernel STOCK"
assert_nogrep "$E03" 'cachyos-bore' "cadeia A: entrada NVIDIA intocada pelo BORE"

SL="$P/syslinux/archiso_sys-linux.cfg"
assert_eq "$(grep -c 'vmlinuz-linux-cachyos-bore' "$SL")" "1" "cadeia A: syslinux default → BORE (1×)"
assert_grep "$SL" 'LABEL archnonfree' "cadeia A: bloco archnonfree preservado"
grep -A3 '^LABEL archnonfree' "$SL" | grep -q 'vmlinuz-linux$' \
  && ok "cadeia A: archnonfree segue no kernel stock (BIOS)" \
  || fail "cadeia A: archnonfree segue no kernel stock (BIOS)" "bloco foi reescrito"

GR="$P/grub/grub.cfg"
assert_grep "$GR" "--id 'archcraftpn'" "cadeia A: menuentry NVIDIA (archcraftpn) preservado"
# o bloco do pn precisa continuar em vmlinuz-linux + initramfs-linux-nvidia.img (stock)
if grep -A4 -- "--id 'archcraftpn'" "$GR" | grep -q 'nvidia nvidia-drm.modeset=1'; then
  ok "cadeia A: bloco NVIDIA segue no kernel stock (BIOS/loopback)"
else
  fail "cadeia A: bloco NVIDIA segue no kernel stock (BIOS/loopback)" "params nvidia sumiram do bloco"
fi
if grep -A4 -- "--id 'archcraftpn'" "$GR" | grep -q 'initramfs-linux-nvidia\.img'; then
  ok "cadeia A: initramfs-nvidia.img exclusivo do stock preservado"
else
  fail "cadeia A: initramfs-nvidia.img preservado" "linha ausente no bloco pn"
fi
assert_eq "$(grep -c 'vmlinuz-linux-cachyos-bore' "$GR")" "3" \
  "cadeia A: default+opensource+nomodeset → BORE (3×, NVIDIA fora)"
assert_grep "$GR" "--id 'archcraftos'" "cadeia A: menuentry opensource presente"
assert_grep "$GR" "--id 'archcraftnm'" "cadeia A: menuentry nomodeset presente"

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

# Setup B (RX 7600) herdando o stack NVIDIA inteiro:
: > "$STATE/installed.txt"; : > "$STATE/pacman.log"
for p in nvidia-open nvidia-utils nvidia-settings lib32-nvidia-utils \
         mesa steam linux-cachyos-bore; do
  echo "$p" >> "$STATE/installed.txt"
done
if outB="$(firstboot LSPCI_FIXTURE="$TESTS_DIR/fixtures/lspci/rx-7600.txt" \
  bash "$TUNE" --firstboot --dry-run --yes 2>&1)"; then rcB=0; else rcB=$?; fi
assert_eq "$rcB" "0" "cadeia C (Setup B): firstboot dry-run exit 0"
assert_match "$outB" 'AMD → mesa/RADV' "cadeia C (Setup B): plano AMD certo (RADV assado = no-op)"
assert_match "$outB" 'Auto-limpeza: GPU amd → removendo stack do outro vendor \(nvidia-open' "cadeia C (Setup B): ~500MB de NVIDIA inertes anunciados p/ sair"
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
  assert_match "$outP" '\$ pacman -S --needed --noconfirm linux-cachyos-bore linux-cachyos-bore-headers linux-headers' \
    "cadeia D: [1] kernel BORE no plano"
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
    with_mocks "${ISOL[@]}" env NS_TMPFS="$NS_TMPFS" TUNE="$TUNE" \
      FB_LOG="$STATE/fb-real-$scen.log" \
      FB_FIXTURE="$fix" FB_SMI="$smi" FB_REFUSE="$refuse" FB_PKGS="$*" \
      MOCK_DIR="$STATE" bash "$TESTS_DIR/lib/ns-body.sh"
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
  assert_grep "$STATE/pacman.log" 'pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings lib32-nvidia-utils$' \
    "cadeia F (Setup A): stack dkms instalado (mock log exato)"
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
