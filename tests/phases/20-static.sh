#!/usr/bin/env bash
# FASE 2 — A TAMPA DA CAIXA: qualidade estática (o desenho completo antes de abrir)
source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"
phase_start 2 "QUALIDADE ESTÁTICA — a tampa da caixa"

# v1.6.2 — lista GLOB-DRIVEN ANCORADA EM $REPO (idêntica ao job lint do
# build.yml): a enumeração manual estava DESATUALIZADA desde a v1.4
# (craft-connect, craft-fix-keys, craft-pin-pick — e o craft-idle novo —
# fora dela; o CI pega tudo pelo glob craft-*, a suíte local não via
# NADA disso: era a brecha por onde o SC1090 passou). Anchored-glob =
# mesma semântica do CI, imune ao cwd, nunca mais des sincroniza.
shopt -s nullglob
SHELLS=(
  "$REPO"/scripts/*.sh
  "$REPO"/.ci/*.sh
  "$REPO"/elite/fragments/*.sh
  "$REPO"/elite/airootfs/usr/local/bin/*
  "$REPO"/elite/airootfs/etc/skel/.config/labwc/autostart
  "$REPO"/tests/run-tests.sh
  "$REPO"/tests/lib/*.sh
  "$REPO"/tests/phases/*.sh
)
shopt -u nullglob

# peças: sintaxe — bash -n em tudo (a suíte testa a si mesma: peças 7-12)
# v2.0: scripts PYTHON (craft-dock-gui) entram por py_compile, não por bash -n
bashn=0; bashfail=0; pyn=0; pyfail=0
for s in "${SHELLS[@]}"; do
  if head -1 "$s" 2>/dev/null | grep -q 'python3'; then
    # ast.parse: valida sintaxe SEM gravar bytecode (o __pycache__ sujaria
    # os globs de binários da própria suíte — lição v2.0)
    if python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$s" 2>/dev/null; then pyn=$((pyn+1)); else pyfail=$((pyfail+1)); echo "    sintaxe py ruim: $s" >&2; fi
  elif bash -n "$s" 2>/dev/null; then bashn=$((bashn+1)); else bashfail=$((bashfail+1)); echo "    sintaxe ruim: $s" >&2; fi
done
assert_eq "$bashfail" "0" "bash -n: $bashn/${#SHELLS[@]} scripts parseiam (repo + a própria suíte)"
if (( pyn + pyfail > 0 )); then
  assert_eq "$pyfail" "0" "py_compile: $pyn script(s) Python da Elite parseiam (craft-dock-gui)"
fi

# peça: shellcheck — mesmo gate do CI (warning ou acima); local pode não ter
if command -v shellcheck >/dev/null 2>&1; then
  sc_log="$WORK/shellcheck.log"; : > "$sc_log"
  for s in "${SHELLS[@]}"; do
    # v2.0.1 — craft-dock-gui é PYTHON (#!/usr/bin/python3): shellcheck só
    # aceita sh/bash/dash/ksh (SC1071) — MESMA regra do gate de lint do
    # build.yml (run #88 em flagrante: lint morreu no GUI Python).
    head -n1 "$s" | grep -q '^#!.*python' && continue
    shellcheck -S warning -x "$s" >> "$sc_log" 2>&1 || true
  done
  # o lint cobre também os mocks/extract gerados (padrão de qualidade da suíte)
  # v0.11 imprime 4 linhas por aviso — na falha, o log INTEIRO vira detalhe
  # da peça (o CI mostra o diagnóstico, não só a contagem)
  sc_lines=$(wc -l < "$sc_log")
  if [[ "$sc_lines" == "0" ]]; then
    ok "shellcheck: 0 avisos em ${#SHELLS[@]} scripts (gate do CI — mesma lista do build.yml, glob-driven)"
  else
    fail "shellcheck: 0 avisos em ${#SHELLS[@]} scripts (gate do CI — mesma lista do build.yml, glob-driven)" "$(head -c 700 "$sc_log")"
  fi
else
  skip "shellcheck: gate do CI" "binário ausente neste ambiente — o job de lint no GitHub o executa"
fi

# peça v2.0.1: o gate de lint (build.yml) e esta suíte compartilham a regra
# python — craft-dock-gui é PyGObject e shellcheck só aceita shells (SC1071;
# run #88 do CI em flagrante: lint morto antes do build). E o gatilho push
# do build.yml é YAML VÁLIDO (o 'branches: ain]' corrompido da 93c582e morre
# — builds de branch disparavam por fallback sem filtro do GitHub).
assert_grep "$REPO/.github/workflows/build.yml" "grep -q '\^#!\.\*python'" "v2.0.1: lint do CI pula script Python (SC1071 — run #88)"
assert_grep "$REPO/tests/phases/20-static.sh" "grep -q '\^#!\.\*python'" "v2.0.1: a SUÍTE também pula Python no shellcheck (mesma regra do lint)"
assert_nogrep "$REPO/.github/workflows/build.yml" "^\s*branches: ain\]" "v2.0.1: gatilho 'branches: ain]' (YAML corrompido) EXTINTO (linha de config, não comentário)"
# v2.1 — REORG do gatilho: ISO é evento de RELEASE (tag v* ou dispatch);
# push de branch roda a suíte rápida (tests.yml), não uma ISO idêntica.
assert_grep "$REPO/.github/workflows/build.yml" "tags: \['v\*'\]" "v2.1: build da ISO disparada por TAG v* (evento de release — fim das ISOs idênticas por push de branch)"
assert_grep "$REPO/.github/workflows/tests.yml" "branches: \['\*\*'\]" "v2.1: suíte de contratos roda em TODA branch (push auditado em ~1.4 min, não em 40 min de ISO)"
# v2.3.1 — a lista de lint NÃO referencia binário extinto: o 'fg-booster'
# hardcoded no for do lint derrubou as builds #95 E #96 inteiras (o arquivo
# saiu na v2.2 e a lista continuou cobrando — lint vermelho ANTES do build).
assert_nogrep "$REPO/.github/workflows/build.yml" "^\s*elite/airootfs/usr/local/bin/fg-booster" "v2.3.1: lista de lint sem binário extinto (fg-booster derrubou #95/#96 — 'head: cannot open')"
# v2.3.1 — o gate da sessão cobre MENUS (fuzzel presente + INI parseável):
# os 5 dropdowns craft-* morriam calados e o gate nunca olhou pra eles.
assert_grep "$REPO/.github/workflows/build.yml" "FUZZEL_BIN" "v2.3.1: gate da sessão cobre fuzzel presente (menus da família craft-*)"
assert_grep "$REPO/.github/workflows/build.yml" "FUZZEL_INI" "v2.3.1: gate da sessão cobre fuzzel.ini parseável (config corrompida = todos os menus mortos)"

# peças: YAML válido (os 5 workflows — v1.5.2: diag-install renomeado p/
# verify-install [nomenclatura de debug não vive em pipeline de produção]
# e publish-artifact entrou na lista: é load-bearing no release manual)
for y in build.yml verify-install.yml agents.yml tests.yml publish-artifact.yml; do
  if [[ -f "$REPO/.github/workflows/$y" ]]; then
    python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$REPO/.github/workflows/$y" 2>/dev/null \
      && ok "yaml: $y parseia" \
      || fail "yaml: $y" "YAML inválido"
  else
    fail "yaml: $y" "workflow ausente"
  fi
done

# peças v1.5.2: workflows de DEBUG mortos removidos — diag-boot/2/3 eram
# remanescentes de sessões de forense (evidência preservada em docs/CHANGES.md
# e no git log); diag-install virou verify-install.yml. Sujeira zero na pipeline.
for gone in diag-boot.yml diag-boot2.yml diag-boot3.yml diag-install.yml; do
  assert_nofile "$REPO/.github/workflows/$gone" "v1.5.2: $gone removido (debug não vive na pipeline)"
done

# peças v1.5.2: o gate de forense de log — existe, executa e carrega a
# história do projeto como especificação (cada padrão FATAL foi bug REAL
# numa build verde; a v1.4 saiu sem keyring com 5 deles ESCRITOS no log)
LF="$REPO/scripts/log-forensics.sh"
assert_file "$LF" "v1.5.2: scripts/log-forensics.sh existe (gate de forense)"
[[ -x "$LF" ]] && ok "v1.5.2: log-forensics.sh executável" || fail "v1.5.2: log-forensics.sh executável" "bit de execução ausente"
for pat in 'target not found' 'could not determine root mount point' 'not enough free disk space' 'is unknown trust' 'signature from .* is invalid' 'No space left on device'; do
  assert_grep "$LF" "$pat" "v1.5.2: forense caça '$pat' (bug real da história)"
done
assert_grep "$LF" 'grub-editenv: error: failed to get canonical path' "v1.5.2: forense documenta o benigno grub-editenv (chroot sem /boot/grub)"
assert_grep "$LF" 'ELITE-BUMP\|baseline Arch injetado' "v1.5.2: forense reconhece recuperação de baseline (libyuv)"
assert_grep "$LF" 'exit 1' "v1.5.2: forense sai 1 em achado fatal"

# peça v1.5.2 → v2.2: o xdotool SAIU — era dep exclusiva do fg-booster,
# extinto na fusão dos boosters (o crash-loop v1.0→v1.5 segue contado
# como REGRA na suíte 30-unit; a presença do pacote é agora BANIDA).
assert_nogrep "$REPO/elite/packages.add" '^xdotool$' "v2.2: xdotool FORA da ISO (dep exclusiva do fg-booster extinto — fusão dos boosters)"

# peças: bits executáveis onde o runtime exige — INDEX-DRIVEN (v2.9.1:
# o [[ -x ]] olhava o FILESYSTEM e neste sandbox tudo nasce rwxrwxrwx —
# a peça passava local e o CI reprovou: o craft-menu-dismiss nasceu
# 100644 no INDEX e foi isso que o checkout do CI e o squashfs da ISO
# herdaram (0644 → 203/EXEC no live, classe provada com elite-tune).
# O que o CI e a ISO veem é o MODO DO INDEX — é ele que a peça audita;
# filesystem vira reserva só para caminho não-rastreado)
shopt -s nullglob
EXECBINS=(
  "$REPO"/elite/airootfs/usr/local/bin/*
  "$REPO"/elite/airootfs/etc/skel/.config/labwc/autostart
  "$REPO"/scripts/*.sh
)
shopt -u nullglob
for x in "${EXECBINS[@]}"; do
  rel="${x#"$REPO"/}"
  mode="$(git -C "$REPO" ls-files -s -- "$rel" 2>/dev/null | awk '{print $1; exit}')"
  if [[ -n "$mode" ]]; then
    [[ "$mode" == "100755" ]] && ok "exec: $rel" \
      || fail "exec: $rel" "modo do index é $mode — checkout do CI e squashfs herdam 0644 → 203/EXEC no live (curar com git update-index --chmod=+x)"
  else
    [[ -x "$x" ]] && ok "exec: $rel" || fail "exec: $rel" "sem bit de execução"
  fi
done

# peças: higiene — sem CRLF, shebang presente
crlf=0
for s in "${SHELLS[@]}" "$REPO"/.github/workflows/*.yml; do
  grep -qU $'\r' "$s" 2>/dev/null && crlf=$((crlf+1))
done
assert_eq "$crlf" "0" "higiene: 0 arquivos com CRLF"

# v1.6.2 — contagem DINÂMICA (era "14" hardcoded, já eram 17): o shebang
# é exigido em TODO binário que existir, não numa foto antiga do diretório
bins=( "$REPO"/elite/airootfs/usr/local/bin/* )
sheb=0
for x in "${bins[@]}"; do
  head -1 "$x" | grep -q '^#!' && sheb=$((sheb+1))
done
assert_eq "$sheb" "${#bins[@]}" "higiene: shebang em TODOS os ${#bins[@]} binários do airootfs (contagem dinâmica)"
head -1 "$REPO/elite/airootfs/etc/skel/.config/labwc/autostart" | grep -q '^#!/bin/sh' \
  && ok "higiene: autostart do labwc é POSIX sh com shebang" \
  || fail "autostart do labwc" "shebang #!/bin/sh ausente"

# (v1.6.2 — o gate de lint acima — loop sobre a SHELLS agora GLOB-driven —
#  É o mesmo conjunto do job lint do build.yml; o SC1090 do craft-idle
#  passava pela suíte porque a lista manual estava desatualizada)

# ── peças: units systemd embarcadas (parse INI de verdade — typo não passa) ──
U="$REPO/elite/airootfs/etc/systemd/system"
UU="$REPO/elite/airootfs/etc/skel/.config/systemd/user"
uout=$(python3 - "$U" "$UU" 2>&1 <<'PYEOF' || true
import configparser, os, sys
u, uu = sys.argv[1], sys.argv[2]
cases = {
  'elite-firstboot.service': {'Unit', 'Service', 'Install'},
  # v1.6.2 — user units do skel (poda do cliphist): service puxado pelo
  # timer NÃO tem (nem precisa de) [Install]; timer tem [Timer]+[Install]
  # v2.2 — scx-elite/fg-booster/fg-boost.slice EXTINTOS (fusão dos boosters)
  'cliphist-prune.service': {'Unit', 'Service'},
  'cliphist-prune.timer':   {'Unit', 'Timer', 'Install'},
}
# strict=False: systemd PERMITE chaves repetidas (ConditionPathExists=
# acumula condições) — o parse aqui checa sintaxe e seções, não política
# de duplicatas (que é legítima em units)
for f, want in cases.items():
    path = f'{u}/{f}' if os.path.exists(f'{u}/{f}') else f'{uu}/{f}'
    cp = configparser.ConfigParser(strict=False)
    try:
        cp.read(path, encoding='utf-8')
        got = set(cp.sections())
        missing = want - got
        if missing:
            raise AssertionError(f'{f}: sem seção(ões) {missing}')
    except Exception as e:
        print(f'FALHOU: {e}'); sys.exit(1)
print('OK 3')
PYEOF
)
assert_eq "$uout" "OK 3" "systemd: 3 units parseiam (1 de sistema + 2 user v1.6.2 — INI válido, seções completas; v2.2: as 3 units de booster EXTINTAS sairam da contagem)"

assert_grep "$U/elite-firstboot.service" '^ExecStart=/' "systemd: elite-firstboot.service ExecStart com caminho absoluto"

[[ -L "$U/multi-user.target.wants/elite-firstboot.service" ]] \
  && ok "systemd: symlink elite-firstboot.service (unit habilitada de fábrica)" \
  || fail "systemd: symlink multi-user.target.wants/elite-firstboot.service" "não é symlink"

# ── v2.2 — FUSÃO DOS BOOSTERS 4→1: nada do exército extinto sobra ─────
# (scx-elite/bpfland + fg-booster/xdotool + dmemcg: 3 camadas que
# brigavam com o BORE do kernel e com o ananicy-cpp — a 4ª, ananicy-cpp,
# é a única que fica, contratada abaixo)
for gone in "$U/scx-elite.service" "$U/fg-booster.service" "$U/fg-boost.slice" \
            "$REPO/elite/airootfs/usr/local/bin/fg-booster" \
            "$U/multi-user.target.wants/scx-elite.service" \
            "$U/multi-user.target.wants/dmemcg-booster-system.service" \
            "$U/graphical.target.wants/fg-booster.service"; do
  assert_nofile "$gone" "v2.2: fusão dos boosters — $(basename "$gone") EXTINTO do airootfs"
done
for p in '^scx-scheds$' '^scx-tools$' '^dmemcg-booster$' '^xdotool$'; do
  assert_nogrep "$REPO/elite/packages.add" "$p" "v2.2: fusão dos boosters — pacote ${p#^} banido do packages.add"
done
for keep in '^cachyos-settings$' '^cachyos-ananicy-rules$' '^ananicy-cpp$'; do
  assert_grep "$REPO/elite/packages.add" "$keep" "v2.2: booster único — $(echo "$keep" | tr -d '^$') permanece no packages.add"
done
# elite-tune: o histórico no header menciona os extintos (é história) — o
# contrato caça os usos OPERACIONAIS (comandos), que não podem mais existir:
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'enable --now scx-elite' "v2.2: elite-tune não habilita mais a scx-elite (scheduler = BORE do kernel)"
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'enable --now fg-boost|enable --now fg-booster' "v2.2: elite-tune não habilita mais o fg-booster/slice (extintos)"
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'enable --now dmemcg-booster' "v2.2: elite-tune não habilita mais o dmemcg (extinto)"
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'noconfirm xdotool|noconfirm cachyos-settings cachyos-ananicy-rules ananicy-cpp scx-scheds' "v2.2: elite-tune não instala mais xdotool/scx/dmemcg (fusão 4→1: só cachyos-settings + rules + ananicy-cpp)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'pacman -S --needed --noconfirm cachyos-settings cachyos-ananicy-rules ananicy-cpp$' "v2.2: elite-tune [1] instala exatamente o booster único (fim da linha em ananicy-cpp)"

# ── peças: preset mkinitcpio do BORE (o initramfs do live) ─────────────
PR="$REPO/elite/airootfs/etc/mkinitcpio.d/linux-cachyos-bore.preset"
assert_grep "$PR" "^ALL_kver='/boot/vmlinuz-linux-cachyos-bore'$" "preset: ALL_kver aponta o BORE"
assert_grep "$PR" '^archiso_image="/boot/initramfs-linux-cachyos-bore\.img"$' "preset: imagem archiso do BORE"

# ── peças: configs embarcadas (o tuning assado na ISO) ──────────────
SC="$REPO/elite/airootfs/etc/sysctl.d/99-elite.conf"
for k in 'vm\.swappiness' 'vm\.vfs_cache_pressure' 'vm\.max_map_count'; do
  assert_grep "$SC" "^${k} = " "sysctl: $k presente (gaming)"
done
UV="$REPO/elite/airootfs/etc/udev/rules.d/60-io-elite.rules"
assert_grep "$UV" 'ATTR\{queue/scheduler\}="none"' "udev: scheduler none p/ NVMe/SSD"
assert_grep "$UV" 'ATTR\{queue/scheduler\}="bfq"' "udev: bfq p/ HDD (rotacional)"
ZR="$REPO/elite/airootfs/etc/systemd/zram-generator.conf"
assert_grep "$ZR" '^\[zram0\]$' "zram: seção [zram0]"
assert_grep "$ZR" 'compression-algorithm = zstd' "zram: compressão zstd"

# ── peça: agents/*.ts transpilam (o agents.yml roda bun neles no CI) ──
if command -v bun >/dev/null 2>&1; then
  tsfail=""
  for f in "$REPO"/agents/*.ts; do
    bun build "$f" --target=bun --outfile="$WORK/ts-check.js" >/dev/null 2>&1 \
      || tsfail="$tsfail $(basename "$f")"
  done
  assert_eq "$tsfail" "" "agents: todo *.ts transpila (gate de sintaxe bun)"
else
  skip "agents: gate de sintaxe bun" "bun ausente — o workflow agents.yml o executa"
fi

# ── peças: contratos do tests.yml (a suíte protege o PRÓPRIO gate) ──
TY="$REPO/.github/workflows/tests.yml"
assert_grep "$TY" 'container: archlinux:base-devel' "contrato: tests.yml roda no container Arch"
assert_grep "$TY" 'bash tests/run-tests\.sh' "contrato: tests.yml executa a suíte inteira"
assert_grep "$TY" 'shellcheck' "contrato: tests.yml instala o shellcheck (o gate de lint)"
assert_grep "$TY" 'pull_request:' "contrato: tests.yml roda em PR (gate de merge)"

# ── peças: dock v2.0 — A DOCK NATIVA (fim da era waybar-dock) ─────────────
# A era waybar-dock acabou COM EVIDÊNCIA: waybar 0.15 crasha com 3+ módulos
# image (Waybar#5051 — pins de ícone real impossíveis), glifos Nerd Font
# entregaram "botões mal recortados… nada é o ícone real" (dono), e o
# nwg-dock log.Fatal sem sway IPC (morto no labwc). A v2.0 é uma dock
# GTK3 NATIVA (craft-dock-gui) no protocolo wlr-layer-shell: ícones REAIS
# do tema via Gio.DesktopAppInfo, e desde a v2.3.4 SEMPRE VISÍVEL (o
# autohide por hotspot morreu na prática — escondia e não voltava),
# pílula centrada que abraça o conteúdo.
GUI="$REPO/elite/airootfs/usr/local/bin/craft-dock-gui"
DKCSS="$REPO/elite/airootfs/etc/skel/.config/elite/dock.css"
PINSKEL="$REPO/elite/airootfs/etc/skel/.config/elite/dock-pins"
assert_nofile "$REPO/elite/airootfs/etc/skel/.config/waybar/config.dock" "v2.0: o config.dock do waybar saiu de cena (a dock não é mais waybar)"
assert_nofile "$REPO/elite/airootfs/etc/skel/.config/waybar/style.dock.css" "v2.0: o style.dock.css do waybar saiu de cena"
assert_file "$GUI" "v2.0: a dock nativa existe (craft-dock-gui)"
assert_grep "$GUI" 'GtkLayerShell' "v2.0: dock no protocolo wlr-layer-shell (labwc-compatible por construção)"
assert_grep "$GUI" 'Gio\.DesktopAppInfo' "v2.0: pins resolvidos por .desktop REAL — ícone/nome/exec do sistema (fim dos glifos)"
assert_grep "$GUI" 'set_pixel_size\(ICON_SIZE\)' "v2.0: escala FIXA 36px (spec M3.2 — ícone de tema, não glifo)"
assert_grep "$GUI" 'GtkLayerShell\.Layer\.BOTTOM' "v2.3.4: layer BOTTOM — tela cheia/gaveta cobrem a dock sozinhas (semântica do protocolo, zero polling)"
assert_grep "$GUI" 'auto_exclusive_zone_enable' "v2.3.4: zona exclusiva — maximizadas respeitam a faixa (o 'como as outras distros' do dono)"
assert_nogrep "$GUI" 'hotspot|HOTSPOT|teaser|SHOW_AT_START|_startup_hide|HIDE_DELAY|hide_now' "v2.3.4: ZERO resquício de autohide (escondeu e não voltou no rig do dono — extinto de verdade)"
assert_grep "$GUI" 'SIGUSR1' "v2.0: toggle via sinal (W-S-d → craft-dock) — esconder é ESCOLHA, nunca decisão da dock"
assert_grep "$GUI" 'SIGUSR2' "v2.0: reload de pins via sinal (craft-pin add/rm)"
assert_grep "$GUI" 'pgrep' "v2.0: indicador de aberto (classe .running — o ponto do macOS)"
# v2.1.1 (run #93): PyGObject lança TypeError ("constructor returned NULL")
# em construtor não-nullable — o guard `if info is None` sozinho NUNCA roda.
# read_pins tem que capturar TypeError: pin ruim é ignorado com log, a dock
# não morre (a #93 crash-loopou 15× sem isso).
assert_grep "$GUI" 'except TypeError' "v2.1.1: read_pins captura TypeError do PyGObject (pin inválido ignorado — a #93 crash-loopou 15× sem isso)"
assert_file "$DKCSS" "v2.0: dock.css no skel (GTK3 CSS da pílula)"
assert_grep "$DKCSS" 'min-height: 44px' "v2.0 M3.1: bounding box único nos botões (ícone CENTRADO no caixilho — a cura do desalinho)"
assert_nogrep "$DKCSS" 'font-size' "v2.0 M3.1: dock.css não escala glifo (não existe mais glifo — só ícone real)"
assert_file "$PINSKEL" "v2.0: dock-pins no skel (pins de fábrica)"
pin_lines=$(grep -cv '^#\|^$' "$PINSKEL" 2>/dev/null || echo 0)
assert_eq "$pin_lines" "3" "v2.0: fábrica = 3 pins de apps reais (foot/thunar/brave — SEM lançador e SEM ação na dock: M2.4/M3.4)"
assert_grep "$PINSKEL" 'foot\.desktop' "v2.0: pin Terminal (foot)"
assert_grep "$PINSKEL" 'thunar\.desktop' "v2.0: pin Arquivos (thunar)"
# v2.1.1 (run #93): o brave-origin instala 'brave-browser.desktop' (contrato
# do build.sh); o pin 'brave.desktop' não resolve → DesktopAppInfo.new NULL →
# PyGObject lança TypeError → dock crash-loopou 15× e derrubou o verify.
assert_grep "$PINSKEL" 'brave-browser\.desktop' "v2.1.1: pin Brave = ID REAL do pacote (brave-browser.desktop — 'brave.desktop' crash-loopou a dock na #93)"
assert_nogrep "$PINSKEL" 'brave\.desktop' "v2.1.1: ID inexistente banido do pins (o .desktop do Brave é brave-browser.desktop)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock" 'USR1' "v2.0: craft-dock toggle via SIGUSR1 (W-S-d)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock" 'USR2' "v2.0: craft-dock reload via SIGUSR2 (craft-pin)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bars" 'craft-dock-gui' "v2.0: craft-bars supervisiona a dock NATIVA (mesma garantia ≤5s da v1.6.3)"
assert_grep "$REPO/elite/packages.add" '^python$' "v2.0: runtime python na ISO (o GUI da dock)"
assert_grep "$REPO/elite/packages.add" '^python-gobject$' "v2.0: PyGObject na ISO (GTK3 do GUI)"
assert_grep "$REPO/elite/packages.add" '^gtk-layer-shell$' "v2.0: gtk-layer-shell na ISO (o protocolo da dock)"
# v2.2: o fixture menu-icons-papirus.txt foi EXTINTO junto com o tema —
# o contrato de menu agora é "texto puro" (bloco de menu na 40-int).
assert_nofile "$REPO/tests/fixtures/menu-icons-papirus.txt" "v2.2: fixture Papirus extinto (tema de ícones saiu da ISO — diretriz do dono)"
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/craft-pin" 'pkill -SIGUSR2' \
  "craft-pin: reload SEM SIGUSR2 (waybar 0.15: o sinal recarrega só CSS — config novo nunca entrava; v1.8.2 reinicia o waybar)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin" '\.bak\.' \
  "craft-pin: toda mutação grava backup restaurável (craft-pin restore)"
assert_grep "$REPO/scripts/apply-overlay.sh" 'craft-pin' \
  "apply-overlay: craft-pin registrado no file_permissions (senão 203/EXEC no live)"

# ── peças v1.8: CSS GTK3-STRICT — a classe "subiu só o wallpaper" NOMEADA ──
# O waybar 0.15 trata propriedade CSS inválida como FATAL (exit 1 no parse).
# TRÊS propriedades GTK4-only foram condenadas EM DOIS BOOTS de CI: o parser
# aborta no PRIMEIRO erro de cada arquivo — run #79 revelou 'icon-size'
# (style.top.css, v1.6) e 'max-width' (style.dock.css, dock v3); curadas as
# duas, a run #80 revelou 'width' na linha seguinte do mesmo bloco. Cada
# boot só mostra o próximo erro — por isso a suíte caça a CLASSE inteira
# (propriedades GTK4-only + width/height crus) e não os nomes avulsos.
# Flagrante #79: BARS_EXITS=32 (pgrep pegando as instâncias NO MEIO da
# espiral de morte ~1,5s/ciclo de 5s do craft-bars). #78 (main): 53.
# A intermitência entre boots do dono = builds de dias diferentes puxaram
# waybar 0.14 (erro=warning ignorável) vs 0.15 (erro=fatal) dos repos rolling.
TOPCSS="$REPO/elite/airootfs/etc/skel/.config/waybar/style.top.css"
assert_nogrep "$TOPCSS" '^[[:space:]]*icon-size:' "css top: sem propriedade GTK4 de tamanho de ícone (FATAL no waybar 0.15 — run #79)"
assert_nogrep "$TOPCSS" '^[[:space:]]*max-(width|height):' "css top: sem propriedades GTK4 de largura/altura máxima (a classe inteira)"
assert_nogrep "$DKCSS" '^[[:space:]]*max-(width|height):' "css dock: sem propriedades GTK4 de largura/altura máxima (FATAL no waybar 0.15 — run #79)"
assert_nogrep "$DKCSS" '^[[:space:]]*icon-size:' "css dock: sem propriedade GTK4 de tamanho de ícone (a classe inteira)"
assert_nogrep "$TOPCSS" '^[[:space:]]*(width|height):' "css top: sem largura/altura cruas (GTK4-only — condenadas na run #80)"
assert_nogrep "$DKCSS" '^[[:space:]]*(width|height):' "css dock: sem largura/altura cruas (FATAL no waybar 0.15 — run #80: width:120)"
assert_nogrep "$TOPCSS" '#tray' "v2.3.6: zero CSS órfão de tray (o módulo e o nm-applet morreram — o conector é texto no craft-connect)"
# (v2.0: os contratos do separador do waybar-dock saíram — o separador
# morreu junto com a dock waybar; o dock.css é GTK3 livre do modo estrito)

# ── peças: Calamares — o heredoc EOSB parseia como YAML (a lição da v1.1) ──
# A ISO v1.1 entregou "shellprocess@btrfs could not be loaded" no rig do
# dono: 4 printfs do heredoc tinham \n REAL partido em coluna 0 → o block
# scalar `>` do YAML terminava no meio do comando → parse error. O gate só
# grepaVA padrões — nunca parseou. Este contrato EXTRAI o heredoc EXATO do
# elite-customize.sh e o parseia com o PyYAML (presente no container CI).
ECF="$REPO/elite/fragments/elite-customize.sh"
if python3 -c 'import yaml' 2>/dev/null; then
  heredoc_yaml=$(python3 - "$ECF" <<'PYCHK' && echo OK || echo FAIL
import sys, re, yaml
src = open(sys.argv[1]).read()
m = re.search(r"<<'EOSB'\n(.*?)\nEOSB\n", src, re.S)
if not m: sys.exit(1)
try:
    data = yaml.safe_load(m.group(1))
    assert isinstance(data, dict) and 'script' in data and data['script']
    # cada command é string não-vazia e é SHELL válido (sh -n)
    import subprocess
    for e in data['script']:
        cmd = e['command'] if isinstance(e, dict) else e
        assert isinstance(cmd, str) and cmd.strip()
        t = cmd.replace('${ROOT}', '/mnt').replace('$ROOT', '/mnt') \
              .replace('${USER}', 'u').replace('${LANG}', 'C')
        r = subprocess.run(['sh', '-n', '-c', t], capture_output=True)
        assert r.returncode == 0, r.stderr.decode()[:120]
    sys.exit(0)
except Exception:
    sys.exit(1)
PYCHK
)
  assert_eq "$heredoc_yaml" "OK" "Calamares: heredoc EOSB = YAML válido + commands shell-ok (o gate cego da v1.1)"

  # o validador do gate [1b/8] (mesmo código no CI e aqui) precisa PROVAR
  # que pega o bug da v1.1: root sintético com o YAML quebrado → exit 1;
  # com o YAML são → exit 0. Sem isto o gate pode ser um no-op sorridente.
  VROOT="$WORK/cal-valid"
  mkdir -p "$VROOT/etc/calamares/modules"
  cat > "$VROOT/etc/calamares/settings.conf" <<'EOSET'
instances:
- id:       btrfs
  module:   shellprocess
  config:   shellprocess_btrfs.conf
sequence:
- exec:
  - shellprocess@btrfs
EOSET
  # YAML VÁLIDO (o fix v1.2: printf numa linha, \n literal)
  printf '%s\n' '---' 'script:' '    - command: >' '        printf '"'"'%%s\\n'"'"' x > /f' > \
    "$VROOT/etc/calamares/modules/shellprocess_btrfs.conf"
  if python3 "$REPO/.ci/validate-calamares.py" "$VROOT" >/dev/null 2>&1; then
    ok "gate [1b/8]: validador APPROVA YAML são (fix v1.2)"
  else
    fail "gate [1b/8]: validador APPROVA YAML são" "validador rejeitou um conf válido (falso positivo)"
  fi
  # YAML QUEBRADO (a corrupção da v1.1: continuação em coluna 0)
  printf '%s\n' '---' 'script:' '    - command: >' '        printf '"'"'%%s'"'"'' \
    "' '# ELITE" > "$VROOT/etc/calamares/modules/shellprocess_btrfs.conf"
  if python3 "$REPO/.ci/validate-calamares.py" "$VROOT" >/dev/null 2>&1; then
    fail "gate [1b/8]: validador PEGA o YAML quebrado da v1.1" "conf corrompido passou no gate (no-op sorridente!)"
  else
    ok "gate [1b/8]: validador PEGA o YAML quebrado da v1.1 (a corrupção da v1.1)"
  fi
else
  skip "gate [1b/8]: validador PEGA o YAML quebrado da v1.1" "sem PyYAML local — o container CI o instala e roda o contrato"
fi
assert_file "$REPO/.ci/validate-calamares.py" "gate [1b/8]: validador vive no repo (.ci/)"
assert_grep "$REPO/.github/workflows/verify-install.yml" 'validate-calamares.py' \
  "gate [1b/8]: workflow chama o validador do repo (um caminho só)"
# forma tripa-seca: nenhuma linha "printf '%s" solta (a assinatura da corrupção)
if grep -qE "printf '%s\$" "$ECF"; then
  fail "Calamares: sem printf partido em coluna 0" "linha printf %s sem fechamento mata o YAML (v1.1)"
else
  ok "Calamares: nenhum printf com string aberta em coluna 0 (a corrupção da v1.1)"
fi

# ── v1.8.1 — TERMINAL DO THUNAR (o bug do dono: "não encontrasse ou não
#    tivesse fallback"). Fonte primária exo 4.20 exo-execute.c:
#    find_fallback_application = (1) ~/.config/xfce4/helpers.rc →
#    g_find_program_in_path(valor) [binário!]; (2) xfce4-terminal.desktop
#    (debloatou); (3) "Could not find fallback TerminalEmulator
#    application". O arquivo é FLAT: o exo PREPENSA "[Default]\n" antes de
#    parsear (data = g_strconcat("[Default]\n", contents)) — um cabeçalho
#    no arquivo seria GRUPO DUPLICADO, e o valor tem de ser NOME DE
#    BINÁRIO no PATH (foot existe — é o terminal do rice, E12).
HELPERS="$REPO/elite/airootfs/etc/skel/.config/xfce4/helpers.rc"
assert_file "$HELPERS" "terminal: helpers.rc existe no skel (o elo que o exo consulta 1º)"
assert_grep "$HELPERS" '^TerminalEmulator=foot$' "terminal: TerminalEmulator=foot (binário resolvido via g_find_program_in_path)"
assert_nogrep "$HELPERS" '\[Default\]' "terminal: arquivo FLAT — cabeçalho de grupo NUNCA (o exo o prepensa; duplicado = parse errado)"
assert_nogrep "$HELPERS" 'kitty|alacritty|xfce4-terminal|urxvt|termite' "terminal: nenhum terminal debloatado referenciado (a classe do dono)"
assert_grep "$ECF" "TERMINAL=.*foot" "terminal: E12 /etc/environment coerente (TERMINAL=foot — a mesma verdade em 2 lugares)"
# o único valor que o exo resolve na ISO é um binário que o debloat deixou:
assert_grep "$REPO/elite/packages.remove" 'xfce4-terminal' \
  "terminal: debloat documentado — xfce4-terminal fora (o fallback morto que gerava o erro)"

# ── v1.8.1 — DEBLOAT SISTÊMICO (E15/E16 do fragmento) ────────────────
assert_grep "$ECF" '\[E15\]' "debloat sistêmico: E15 presente (locale/man/doc no chroot)"
assert_grep "$ECF" 'locale-gen' "debloat sistêmico: locale-gen regenera o archive com a lista podada"
assert_grep "$ECF" 'pt_BR\.UTF-8' "debloat sistêmico: pt_BR gerado (dono pt-BR; LANG segue o upstream — rice intacto)"
assert_grep "$ECF" 'ELITE-FAIL.*locale|locale.*ELITE-FAIL' "debloat sistêmico: locale falho = build falha (nunca boot)"
assert_grep "$ECF" 'en_US\.utf8' "debloat sistêmico: verificação pós-locale-gen (auto-cura antes do fail)"
assert_nogrep "$ECF" 'rm -rf /usr/share/licenses' "debloat sistêmico: licenças INTACTAS (compliance legal — a poda não encosta)"
assert_grep "$ECF" 'l10n' "debloat sistêmico: prune de locale preserva l10n/ e en*/pt* (flags de exceção no find)"
assert_grep "$ECF" '\[E16\]' "debloat sistêmico: E16 presente (v2.2 — guarda sem-tema-de-ícones)"
assert_nogrep "$ECF" 'papirus-icon-theme|Papirus-Dark|ELITE-FAIL: Papirus' "debloat sistêmico: NENHUM resquício de gate do Papirus no customize (tema saiu — diretriz do dono)"
MENUX="$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml"
assert_nogrep "$MENUX" '<item label=[^>]* icon=' "debloat sistêmico: menu.xml é TEXTO PURO (nenhum item com atributo de ícone — sem tema de ícones na ISO)"
assert_nogrep "$REPO/elite/airootfs/etc/skel/.config/fuzzel/fuzzel.ini" 'Papirus|icon-theme' "debloat sistêmico: fuzzel sem icon-theme (fallback base do GTK)"
assert_nogrep "$REPO/elite/airootfs/etc/skel/.config/gtk-3.0/settings.ini" 'Papirus|gtk-icon-theme-name' "debloat sistêmico: GTK3 sem referência a tema de ícones (fallback Adwaita, dep de gtk3)"
assert_nogrep "$REPO/elite/airootfs/etc/skel/.config/gtk-4.0/settings.ini" 'Papirus|gtk-icon-theme-name' "debloat sistêmico: GTK4 espelha a ausência"
# journald cap — o teto que protege RAM (live) e disco (instalado)
JCAP="$REPO/elite/airootfs/etc/systemd/journald.conf.d/99-elite-cap.conf"
assert_file "$JCAP" "journal: drop-in de teto existe (journald.conf.d vence qualquer journald.conf upstream)"
assert_grep "$JCAP" '^SystemMaxUse=100M$' "journal: SystemMaxUse=100M (instalado — disco sem crescimento sem fim)"
assert_grep "$JCAP" '^RuntimeMaxUse=64M$' "journal: RuntimeMaxUse=64M (live em RAM — memória protegida)"

# ── v1.8.1 — RELEASE com 2 gates de integridade (a classe v1.8.0
#    truncada: asset 1.55 GiB de 2.77 — PVD mentia contra o blob) ──────
BYML="$REPO/.github/workflows/build.yml"
assert_grep "$BYML" 'sha256sum -c sha256sums\.txt' "release: GATE 1 pré-upload (artifact vs sha256sums selado pelo build.sh)"
assert_grep "$BYML" 'gh release download' "release: GATE 2 pós-upload (re-download do blob do GitHub)"
assert_grep "$BYML" 'sha256sum -c \.\./sha256sums\.txt --ignore-missing' "release: GATE 2 verifica os bytes publicados (--ignore-missing: split)"
assert_grep "$BYML" 'body_path: out/body\.md' "release: tabela de integridade no CORPO da release (dono vê tamanhos antes de baixar)"
assert_grep "$BYML" 'GH_TOKEN: \$\{\{ github\.token \}\}' "release: GATE 2 autenticado (gh release download precisa do token do workflow)"

# ── v1.8.2 — A CLASSE DO TERMBIN iy38 + os flagrantes do áudio/fotos
#    do dono (24/out): install morto no copytoram, botão gigante GTK4,
#    pins invisíveis na dock, menus que não se fecham, TUI onde o dono
#    quer GUI, LACT pedindo Service Setup ──────────────────────────────

# C1 — fonte de kernel em CASCATA (bootmnt → /boot do live → backing do
#      loop): com copytoram=y (padrão da ISO) o bootmnt é DESMONTADO e a
#      v1.8.1 morria no job 36 ("nenhum vmlinuz em /run/archiso/bootmnt").
EIS="$REPO/elite/airootfs/usr/local/bin/elite-install-stage"
assert_grep "$EIS" 'for cand in /run/archiso/bootmnt/arch/boot/x86_64 /boot' \
  "install-stage: cascata A+B (bootmnt e o /boot do live) declarada"
assert_grep "$EIS" 'losetup -n -o BACK-FILE' \
  "install-stage: cascata C (backing do loop do airootfs — ISO/sfs do copytoram)"
assert_grep "$EIS" 'mount -o loop,ro "\$backfile"' \
  "install-stage: cascata C monta o backing read-only"
assert_nogrep "$EIS" 'ERRO — nenhum vmlinuz' \
  "install-stage: o hard-fail de copytoram da v1.8.1 NÃO é mais desfecho possível"
assert_grep "$EIS" 'vmlinuz são\(s\) do unpackfs — seguindo' \
  "install-stage: alvo com kernel são do unpackfs SEGUE com aviso (não morre)"
assert_grep "$EIS" '"MZ"' \
  "install-stage: sanidade do kernel do alvo = tamanho + assinatura bzImage"
assert_grep "$EIS" 'cmp -s "\$kv" "\$tmp"' \
  "install-stage: a PROVA da v1.8 (cmp byte-a-byte) fica intacta"

# H1 — GTK4: o círculo do Adwaita é o `> image` DENTRO do button (fonte:
#      libadwaita _header-bar.scss); pintar o button sem matar o image =
#      botão gigante (flagrante: LACT/Papers/pwvucontrol, 24/out).
G4="$REPO/elite/airootfs/etc/skel/.config/gtk-4.0/gtk.css"
assert_grep "$G4" 'windowcontrols > button > image' \
  "gtk4: o círculo interno do Adwaita é neutralizado no image do button"
assert_grep "$G4" 'windowcontrols > button:hover > image' \
  "gtk4: veneno do '> image' cobre HOVER (estado que o Adwaita pinta)"
assert_grep "$G4" 'windowcontrols > button\.close' \
  "gtk4: trio pintado com especificidade ≥ Adwaita (> button.close)"
assert_grep "$G4" 'background-image: none' \
  "gtk4: background-image morto (glyph SVG do Adwaita não vaza)"
# o css GTK4 inteiro tem que parsear limpo: classe de erro waybar (v1.7.2)
# e GTK compartilham a leitura — propriedade desconhecida aborta o arquivo
if [[ -f "$G4" ]]; then
  python3 - "$G4" <<'PYEOF' && ok "gtk4: css sem chaves desbalanceadas (estrutura íntegra)" || fail "gtk4: css sem chaves desbalanceadas" "recontar {} no arquivo"
import sys
s = open(sys.argv[1]).read()
assert s.count('{') == s.count('}'), f"{s.count('{')} abre vs {s.count('}')} fecha"
PYEOF
fi

# H2a — (v2.0) craft-pin-status saiu de cena: o GUI da dock resolve os pins
#      pelo .desktop (Gio) — não existe mais "pin invisível por permissão".
AO="$REPO/scripts/apply-overlay.sh"
assert_nofile "$REPO/elite/airootfs/usr/local/bin/craft-pin-status" "v2.0: craft-pin-status saiu de cena (a dock nativa não executa JSON por pin)"
assert_nogrep "$AO" 'craft-pin-status' "v2.0: craft-pin-status fora do file_permissions"

# H2b — reload do craft-pin v2: SIGUSR2 na dock NATIVA (o GUI re-lê o
#      arquivo de pins — a classe "fixou, mas a dock não atualizou" morre
#      com o waybar fora da dock).
CPIN="$REPO/elite/airootfs/usr/local/bin/craft-pin"
assert_grep "$CPIN" 'craft-dock reload' \
  "craft-pin v2: reload via craft-dock (SIGUSR2 — o GUI re-lê os pins)"

# H3 — cross-dismiss: abrir Sessão fecha Rede e vice-versa (nunca 2
#      dropdowns empilhados — áudio do dono, 24/out e 21/out)
CCON="$REPO/elite/airootfs/usr/local/bin/craft-connect"
CMEN="$REPO/elite/airootfs/usr/local/bin/craft-menu"
# H3 v2.6.0 — a lei dos menus VIROU DETERMINISMO (os prints do rig 26/out
# desmentiram a física: "clico de novo e não fecha, um não anula o outro").
# O craft-menu v4 grava o pid do fuzzel vivo; 2ª chamada do MESMO título
# mata e sai 2 (toggle); título diferente mata e abre (cross-dismiss).
assert_grep "$CMEN" 'elite-menus\.' \
  "v2.6.0: a lei dos menus é DETERMINÍSTICA (pid do fuzzel em \$XDG_RUNTIME_DIR — toggle e cross-dismiss por pid, não por física de foco que o rig desmentiu)"
assert_grep "$CMEN" 'exit 2' \
  "v2.6.0: TOGGLE = a 2ª chamada do mesmo título fecha (rc 2 — a gramática 0/1/2/143 intacta para os chamadores)"
assert_grep "$CMEN" '--hide-prompt' \
  "v2.6.0: menu = LISTA PURA (o dono: 'tirar esse risco | que fica na frente' + o nome 'Sessão:'/'Encerrar:' — a linha de digitação inteira some; digitar ainda filtra)"
assert_grep "$CMEN" '--anchor top-right' \
  "v2.6.0: o menu nasce SOB O BOTÃO (o dono: 'não seria melhor ficar onde ela for aberta?' — anchor top-right + x-margin calibrado por slot; a barra de 36px empurra pelo exclusive zone)"
assert_grep "$CMEN" 'fuzzel --help' \
  "v2.6.0: degradação graciosa (fuzzel velho demais para as curas? o menu clássico com prompt abre em vez de morrer)"
assert_nogrep "$CMEN" '\$UID' \
  "v2.6.0: id -u, NUNCA \$UID (dash não tem UID — sob set -u o script morria rc=2, que o chamador lê como toggle benigno: menu que nunca abre e morre sorrateiro; flagrado no smoke test)"
assert_nogrep "$CCON" "pkill -f 'fuzzel" \
  "craft-connect sem pkill de irmão (a lei mora no craft-menu — um lugar só)"

# H4 — conectividade v2.6.0 (o dono, prints do rig: "no menu de rede eu
#      não consigo desligar/ligar minhas conexões seja cabo, wi-fi e etc
#      nem me conectar a redes; isso é pra criação de rede manual"): o
#      menu volta a CONTROLAR o NetworkManager via nmcli (o cli do
#      próprio serviço — cada verbo é UM comando dele). O editor
#      (nm-connection-editor) segue, agora como UM item: a CRIAÇÃO
#      manual mora lá, como o dono mesmo definiu. O bug do picker v3
#      morreu de vez: linha→SSID/segredo via MAPA escrito pelo mesmo awk
#      que desenha a lista — o valor devolvido ao NM é o que o NM deu.
assert_grep "$REPO/elite/packages.add" '^network-manager-applet$' \
  "packages.add: network-manager-applet presente (o editor de conexões é dele — item do menu)"
assert_grep "$REPO/elite/packages.add" '^blueman$' \
  "packages.add: blueman presente (GUI de bluetooth)"
assert_grep "$CCON" 'nmcli radio wifi' \
  "craft-connect v5: Wi-Fi liga/desliga pelo rádio do NetworkManager (o dono: 'não consigo desligar/ligar... wi-fi')"
assert_grep "$CCON" 'nmcli device connect' \
  "craft-connect v5: cabo liga por dispositivo (nmcli device connect — 'desligar/ligar minhas conexões seja cabo')"
assert_grep "$CCON" 'nmcli device disconnect' \
  "craft-connect v5: cabo desliga por dispositivo"
assert_grep "$CCON" 'nmcli device wifi connect' \
  "craft-connect v5: CONECTAR em rede volta ao caminho (a reversão ASSUMIDA: o dono pediu conectar no menu — o bug do picker v3 era o parse; agora linha→SSID via MAPA do próprio awk)"
assert_grep "$CCON" 'nmcli connection up' \
  "craft-connect v5: conexões salvas religam pelo nome (senha do cofre do NM, sem prompt)"
assert_grep "$CCON" 'nmcli connection down' \
  "craft-connect v5: conexão ativa desliga (● = ativa na lista)"
assert_grep "$CCON" '--ask=' \
  "craft-connect v5: rede nova protegida pede a senha no menu (o prompt visível é a exceção honesta; rede salva nunca pergunta)"
assert_grep "$CCON" 'elite-net\.' \
  "craft-connect v5: o MAPA linha→valor (o que o NM entregou é o que volta ao NM — nunca parse de tela)"
assert_grep "$CCON" 'exec nm-connection-editor' \
  "craft-connect v5: o editor do SISTEMA segue (a criação manual mora lá — definição do próprio dono)"
assert_grep "$CCON" 'blueman-manager' \
  "craft-connect v5: o verbo Bluetooth que o dono APROVOU segue (GUI, TUI só fallback)"
assert_grep "$CCON" '--at=network' \
  "craft-connect v5: o menu nasce SOB O BOTÃO de rede (âncora do craft-menu v4)"
RCXML="$REPO/elite/airootfs/etc/skel/.config/labwc/rc.xml"
assert_grep "$RCXML" 'command="nm-connection-editor"' \
  "rc.xml: W-n abre o editor de conexões (função avançada fora do menu de 2 itens)"
assert_grep "$RCXML" 'command="blueman-manager"' \
  "rc.xml: W-S-b abre GUI de bluetooth (era bluetui TUI)"
AUTO="$REPO/elite/airootfs/etc/skel/.config/labwc/autostart"
assert_nogrep "$AUTO" 'nm-applet &' \
  "v2.3.6: nm-applet FORA do autostart — a história completa: v2.0 estética → v2.3.5 função (voltou) → v2.3.6 substituição → v2.3.7 o menu chama o gerenciador do sistema"
assert_nogrep "$AUTO" 'blueman-applet &' \
  "v2.0: blueman-applet FORA do autostart (mesma classe — o blueman-manager do craft-connect cobre)"
# v2.3.6 — a lei do fechamento: ESC (exit 1 com stderr vazio) é benigno em
# TODOS os 6 menus — fechar menu NUNCA é erro (o rig flagrou "erro 1" no
# fechamento normal da Rede; mesma classe do 143 da v2.3.5).
for m in craft-power craft-connect craft-bgapps craft-pin-pick craft-logout craft-idle; do
  assert_grep "$REPO/elite/airootfs/usr/local/bin/$m" 'fechado pelo usuário \(ESC\)' \
    "v2.3.6: $m — ESC é fechamento benigno (fim do falso 'erro 1')"
done
CTOP="$REPO/elite/airootfs/etc/skel/.config/waybar/config.top"
assert_nogrep "$CTOP" '"tray"' \
  "v2.3.6: módulo tray FORA da topbar (nada a exibir — udiskie roda --no-tray; o conector é texto no craft-connect)"

# H5 — LACT com daemon de fábrica (flagrante: "Service Status: inactive")
assert_grep "$ECF" '\[E17\]' \
  "customize: E17 presente (lactd habilitado no build)"
assert_grep "$ECF" 'ln -sf /usr/lib/systemd/system/lactd\.service' \
  "customize: E17 habilita o lactd via symlink direto (container sem PID 1 — systemctl não é confiável no build)"
assert_grep "$ECF" 'ELITE-FAIL: symlink do wants do lactd' \
  "customize: E17 com gate duro (wants ausente = build falha)"

# M3 — Brave com titlebar GTK (os botões mac do rice aplicam no Chromium;
#      flagrante: Brave com X padrão — áudio do dono, 24/out)
BLS="$REPO/elite/airootfs/etc/skel/.config/BraveSoftware/Brave-Browser/Local State"
assert_file "$BLS" "brave: Local State preseedado no skel"
python3 - "$BLS" <<'PYEOF' && ok "brave: Local State é JSON válido com custom_chrome_frame=false" || fail "brave: Local State" "JSON inválido ou pref ausente"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["browser"]["custom_chrome_frame"] is False
PYEOF


# ═══════════════════════════════════════════════════════════════════════════
# v1.9 — SPEC ESTRUTURAL DO DONO (out/2026): as 5 frentes, contrato a contrato
# ═══════════════════════════════════════════════════════════════════════════

# ── M1.1: fase final de boot — hash + regen + flush (o "premature end of
#    file /@/boot/vmlinuz-linux" do rig não passa mais: kernel selado por
#    sha256 fonte==alvo, mkinitcpio -P COMPLETO com gate duro, grub-mkconfig
#    no stage, sync de disco) ──
INST="$REPO/elite/airootfs/usr/local/bin/elite-install-stage"
assert_grep "$INST" 'sha256sum' "M1.1: verificação por HASH (sha256) do kernel no chroot final"
assert_grep "$INST" 'mkinitcpio -P' "M1.1: re-geração COMPLETA do mkinitcpio (todos os presets — não só o bore)"
assert_grep "$INST" 'grub-mkconfig' "M1.1: grub-mkconfig re-gerado no próprio stage (belt-and-suspenders do módulo bootloader)"
assert_grep "$INST" 'menuentry' "M1.1: grub.cfg validado (menuentry + vmlinuz presentes — sem menu vazio)"
assert_grep "$INST" 'sync -f' "M1.1: flush completo do disco (sync + sync -f no /boot do alvo)"
assert_nogrep "$INST" 'mkinitcpio -p linux-cachyos-bore' "M1.1: o regen NARROW do bore morreu (agora é mkinitcpio -P completo com gate duro — sem || true)"

# ── M1.10: a recorrência 25/out (IMG_20261025_004850 — GRUB 'premature
#    end of file /@/boot/vmlinuz-linux-cachyos-bore' após install feliz):
#    com copytoram a cascata A→B→C cai TODA e o alvo seguia com o vmlinuz
#    do UNPACKFS (a cópia que trunca em btrfs real — E10 v1.0.4). A fonte
#    D (kernel EM EXECUÇÃO do live) fecha o buraco; a auditoria deixa de
#    ser cega; o /boot nasce nodatacow; o menu só tem o kernel ÚNICO. ──
assert_grep "$INST" '/usr/lib/modules/\$\{live_kver\}/vmlinuz' \
  "M1.10: fonte D = o kernel EM EXECUÇÃO no live (à prova de copytoram — fecha a cascata A→B→C→D)"
assert_grep "$INST" 'cp -f --sparse=never' \
  "M1.10: escrita SEM sparse (a classe de truncamento em btrfs comprimido é escrita sparse)"
assert_grep "$INST" 'for attempt in 1 2' \
  "M1.10: retry antes de falhar alto (não morre na 1ª divergência de cópia)"
assert_grep "$INST" 'chattr \+C "\$\{ROOT\}/boot"' \
  "M1.10: /boot do alvo nodatacow — arquivos de boot nascem sem zstd/CoW (GRUB lê extents crus)"
assert_grep "$INST" "grep -Ev '\\^vmlinuz-linux-cachyos-bore\\\$'" \
  "M1.10: gate do menu — grub.cfg só pode referenciar o kernel ÚNICO (vmlinuz órfão reprova a instalação)"
assert_grep "$INST" 'initramfs-linux-cachyos-bore-fallback' \
  "M1.10: presença do fallback verificada (a principal + a reserva, nada além)"

# ── M1.2: Calamares transparente — log SILENCIOSO + persistente ──
# v2.9.2: o dono aposentou o terminal de log ao vivo ("Log calamaris não
# precisa mais abrir um terminal só pra aparecer logs") — um foot que se
# abre SOZINHO antes do instalador é sujeira visual. Log é ARQUIVO para
# auditoria (/var/log/calamares.log), não janela para interromper.
CALLOG="$REPO/elite/airootfs/usr/local/bin/calamares-elite-log"
CALD="$REPO/elite/airootfs/usr/local/share/applications/calamares.desktop"
assert_grep "$CALD" 'calamares-elite-log' "M1.2: calamares.desktop lança o wrapper de log (Exec=)"
assert_nogrep "$CALLOG" 'foot' "M1.2 v2.9.2: NENHUM terminal se abre sozinho (o log ao vivo morreu — nada aparece sem pedido)"
assert_nogrep "$CALLOG" 'tail' "M1.2 v2.9.2: wrapper não tails log em janela (auditoria é por arquivo)"
assert_grep "$CALLOG" '/var/log/calamares\.log' "M1.2: log completo persistido em /var/log/calamares.log"
assert_grep "$CALLOG" '/etc/calamares/launch.sh' "M1.2: launch.sh upstream curado segue intocado (E5a2)"

# ── M2: top bar — geometria (Y centrado, tray com respiro, linha morta) ──
TOPCSS="$REPO/elite/airootfs/etc/skel/.config/waybar/style.top.css"
assert_nogrep "$TOPCSS" 'border-bottom' "M2.3: a linha fantasma sob a barra está MORTA (border-bottom removido do window#waybar)"
assert_grep "$TOPCSS" 'padding-top: 2px' "M2.1: padding vertical SIMÉTRICO no painel (topo == base — ícone não encosta no teto)"
assert_grep "$TOPCSS" 'padding-bottom: 2px' "M2.1: padding-bottom presente (par do padding-top)"
assert_grep "$TOPCSS" 'padding: 0 12px' "M2.2→v2.3.9: UM padding para toda a barra (0 12px — o 14px exclusivo do power era a assimetria que o dono flagrou no hover: 'espaços, tamanho, consistência — tudo padronizado')"

# ── M3: dock — centralização, escala fixa, ícones reais, launcher único ──
# M3.1/M3.2/M3.3 (v2.0): o desalinho e os ícones quebrados tinham UMA causa
# estrutural — a dock waybar com glifos/imagens. A dock nativa mata a classe:
# v2.2: ícones vêm do PRÓPRIO app (hicolor) + fallback base Adwaita; caixa
# única 44px no dock.css (contratos no bloco da dock v2.0). Sem tema de
# ícones, o override do instalador aponta o ícone do PRÓPRIO pacote:
assert_grep "$REPO/elite/airootfs/usr/local/share/applications/calamares.desktop" 'Icon=calamares' "M3.3 v2.2: Instalador com o ícone do PRÓPRIO pacote (sem tema de ícones, ícone de tema não é garantia)"
assert_nofile "$REPO/elite/airootfs/usr/local/share/applications/lact.desktop" "M3.3 v2.0: override lact.desktop saiu (o .desktop upstream do app é a fonte)"
assert_nofile "$REPO/elite/airootfs/usr/local/share/applications/mpv.desktop" "M3.3 v2.0: override mpv.desktop saiu"
assert_nofile "$REPO/elite/airootfs/usr/share/pixmaps/elite/lact.png" "M3.3 v2.0: PNG desenhado à mão saiu do pacote (lact)"
assert_nofile "$REPO/elite/airootfs/usr/share/pixmaps/elite/mpv.png" "M3.3 v2.0: PNG desenhado à mão saiu do pacote (mpv)"

# ── M4: tecla Super = menu de aplicativos ──
RCX="$REPO/elite/airootfs/etc/skel/.config/labwc/rc.xml"
assert_grep "$RCX" 'key="Super_L"' "M4.1: tecla SUPER mapeada (só pressionada → Launchpad)"
assert_grep "$RCX" 'key="W-S-d"' "M3.5: W-S-d alterna a dock (mostrar/esconder — escolha do usuário; a dock é sempre visível)"

# ── M5: wallpaper vetorial flat (sem poeira) — arquivo selado no 40-int ──
assert_file "$REPO/elite/airootfs/etc/skel/.config/labwc/wallpaper.png" "M5.1: wallpaper.png (PNG lossless — o JPEG com ruído saiu de cena)"
assert_nogrep "$REPO/elite/airootfs/etc/skel/.config/labwc/autostart" 'wallpaper\.jpg.*first' "M5.1: autostart NÃO prefere mais o jpg (PNG primeiro)"

# ── file_permissions: TODO binário do overlay precisa de 0755 (203/EXEC) ──
# v2.0: dock · v2.3.4: craft-bgapps · v2.3.5: craft-dump
# v2.9.1: a lista manual tinha o MESMO buraco que a exec teve na v1.6.2 —
# o craft-menu-dismiss nasceu fora dela E fora do apply-overlay, e a ISO
# herdou 0644 (a suíte não viu porque a peça olhava o filesystem local).
# GLOB-DRIVEN: cada script do airootfs/usr/local/bin tem de estar
# registrado no apply-overlay — binário novo sem entrada reprova AQUI.
for nb in "$REPO"/elite/airootfs/usr/local/bin/*; do
  b="$(basename "$nb")"
  assert_grep "$REPO/scripts/apply-overlay.sh" "/usr/local/bin/$b" "apply-overlay: $b registrado no file_permissions (senão 203/EXEC no live)"
done

# ── pacman-init: retry honesto (v2.9.1) ──
# o oneshot do upstream morre SEM retry: na build v2.9.1 o pacman-key
# tropeçou 1× no live do CI (exit 1 · 30s CPU · 91s wall) com a sessão
# perfeita em volta e o gate v1.5.2 reprovou uma ISO boa — flake sob a
# carga do runner (verify + verify-install, 2× QEMU em paralelo). O
# drop-in dá 3 tentativas em 300s: flake se cura sozinho; keyring
# quebrado de verdade falha as 3 e o gate segue reprovando.
assert_file "$REPO/elite/airootfs/etc/systemd/system/pacman-init.service.d/10-elite-retry.conf" "pacman-init: drop-in de retry existe (oneshot upstream nasceu sem fôlego)"
assert_grep "$REPO/elite/airootfs/etc/systemd/system/pacman-init.service.d/10-elite-retry.conf" 'Restart=on-failure' "pacman-init: retry on-failure (falha real segue reprovando o gate v1.5.2)"
assert_grep "$REPO/elite/airootfs/etc/systemd/system/pacman-init.service.d/10-elite-retry.conf" 'StartLimitBurst=3' "pacman-init: 3 tentativas com limite (não é loop eterno)"


# ── v2.10.5 — A AUDITORIA DE SIMULAÇÕES: as leis que nasceram dela ─────
# (5 personas percorreram todo o código; cada cura que sobreviveu à
# perícia vira CONTRATO — a classe inteira morre, não só o sintoma)
SK="$REPO/elite/airootfs/etc/skel"
RCX="$SK/.config/labwc/rc.xml"

# A. o terminal fala a língua da distro: foot abre o ZSH (o .zshrc é o
#    dono do shell — '/bin/sh -l' escondia starship/aliases do usuário)
assert_nogrep "$SK/.config/foot/foot.ini" 'shell = /bin/sh' "v2.10.5: foot NUNCA mais abre POSIX sh (o .zshrc inteiro morria calado)"
assert_grep "$SK/.config/foot/foot.ini" 'shell = /usr/bin/zsh -l' "v2.10.5: foot abre o zsh de login (starship/autosuggestion/aliases vivos)"

# B. a fonte dos títulos é a REAL (mesma lei da waybar/fuzzel/foot):
assert_nogrep "$RCX" '<name>JetBrains Mono</name>' "v2.10.5: rc.xml não usa a família fantasma 'JetBrains Mono' (fontconfig caía no fallback genérico)"
assert_grep "$RCX" '<name>JetBrainsMono NF</name>' "v2.10.5: títulos do labwc na família REAL do archcraft-fonts 2.0"

# C. screenshot com keysym sem ambiguidade (README e rc.xml na mesma língua):
assert_grep "$RCX" 'key="W-p"' "v2.10.5: região em W-p (keysym minúsculo — o 'P' maiúsculo implícita Shift)"
assert_grep "$RCX" 'key="W-S-p"' "v2.10.5: tela inteira em W-S-p"
assert_nogrep "$RCX" '<keybind key="W-P"|<keybind key="W-S-P"' "v2.10.5: nenhum bind de screenshot com keysym maiúsculo (dois binds no mesmo combo)"

# D. o editor existe (mousepad saiu da ISO; o alias não aponta pro fantasma):
assert_nogrep "$SK/.zshrc" "mousepad ~" "v2.10.5: .zshrc não invoca pacote removido (mousepad saiu no debloat)"
assert_grep "$SK/.zshrc" "alias zshconfig='nano ~/.zshrc'" "v2.10.5: zshconfig aponta pro editor da distro (nano)"

# E. a flag é probada antes de usar (lei do craft-menu — classe 'flag nova que mata'):
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin-pick" "grep -q -- '--anchor'" "v2.10.5: pin-pick prova --anchor (fuzzel velho não mata o picker)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-rollback" "grep -q -- '--anchor'" "v2.10.5: rollback prova --anchor (mesma lei)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin-pick" 'Hidden=true' "v2.10.5: picker respeita Hidden (a lei XDG é dupla)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin-pick" 'pt_BR' "v2.10.5: picker fala o nome da gente (Name[pt_BR] antes do genérico)"

# F. bateria: /sys puro (upower saiu da equação — e a mensagem amigável é alcançável):
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/craft-bat" 'command -v upower' "v2.10.5: craft-bat sem upower (dep que não estava na ISO)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bat" '/sys/class/power_supply' "v2.10.5: craft-bat lê o kernel direto (o código concorda com o docs)"
assert_grep "$SK/.config/waybar/config.top" '"battery"' "v2.10.5: o notebook tem assento na barra (módulo battery — clique dá o resumo)"

# G. o conf do idle sobrevive ao menu (suspend opt-in não morre no rewrite):
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" 'SUSPEND_MIN=%s' "v2.10.5: idle.conf regravado COM o suspend do usuário (os dois caminhos)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" 'LOCK_MIN:-.*\*\[!0-9\]\*\) LOCK_MIN=10' "v2.10.5: valor lixo no conf não mata o daemon (sanidade antes do -eq)"

# H. a senha recusada é PERGUNTADA de novo (classe 'fora de alcance' mentirosa):
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-connect" 'connection delete' "v2.10.5: perfil com senha recusada morre e o fluxo PERGUNTA (léxico EN+pt do stderr)"

# I. supervisão: singleton + corrida do fork com veredito por prova:
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bars" 'flock -n 9' "v2.10.5: craft-bars é singleton (2 supervisores = barra duplicada no relogin)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bars" '2ª instância saiu 0' "v2.10.5: corrida fork/exec não é óbito (BARS_EXITS não mente no gate do QEMU)"
assert_grep "$SK/.config/labwc/autostart" 'command -v swaync' "v2.10.5: até a central de avisos nasce com guarda (fim do último spawn nu)"

# J. udev: a regra só cospe no disco inteiro:
assert_grep "$REPO/elite/airootfs/etc/udev/rules.d/60-io-elite.rules" 'TEST!="partition"' "v2.10.5: scheduler de NVMe não tenta escrever em partição (o '*' engolia o p1)"

# K. enum de verdade no swaync (número mágico 80 não é valor de image-visibility):
assert_nogrep "$SK/.config/swaync/config.json" '"image-visibility": 80' "v2.10.5: image-visibility não é número mágico (o schema é enum — chave ignorada era ruído)"
assert_grep "$SK/.config/swaync/config.json" "when-there's-a-tray-icon" "v2.10.5: image-visibility com valor de enum válido"

# L. pacotes: a dependência jurada existe de facto:
assert_grep "$REPO/elite/packages.add" '^libpulse$' "v2.10.5: libpulse explícito (pactl/volumes + módulo pulseaudio da waybar)"
assert_grep "$REPO/elite/packages.remove" '^networkmanager-sstp$' "v2.10.5: nome REAL do pacote sstp (o 'network-manager-sstp' era no-op silencioso)"
assert_nogrep "$REPO/elite/packages.remove" '^network-manager-sstp$' "v2.10.5: o nome errado saiu da lista"

# M. GPU: a limpeza reconcilia o initramfs (a contradição Optimus morre):
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'MODULES=\(nvidia' "v2.10.5: tune reconcilia MODULES do install-stage (híbrido não morre no próximo mkinitcpio)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-tune" "00-elite-nvidia.conf" "v2.10.5: options órfãs do nvidia saem junto"
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-tune" "raiz não é btrfs" "v2.10.5: ext4 não nasce com grub-btrfsd FAILED (snapshots são lei do btrfs)"

# N. CI: a suíte é GATE de release e o publish tem GATE de origem:
assert_grep "$REPO/.github/workflows/build.yml" 'needs: \[build, verify, verify-install, suite\]' "v2.10.5: release exige a suíte (push de tag nunca mais publica sem contratos)"
assert_grep "$REPO/.github/workflows/build.yml" 'gate de release' "v2.10.5: o job suite existe no build.yml"
assert_grep "$REPO/.github/workflows/tests.yml" "tags: \['v\*'\]" "v2.10.5: a suíte também audita tags (dupla prova da lei)"
assert_grep "$REPO/.github/workflows/publish-artifact.yml" 'PUBLICAÇÃO NEGADA' "v2.10.5: publish-artifact GATEia o run de origem (ISO de run vermelho não vira release)"
assert_grep "$REPO/.ci/build.sh" 'try\$\{try\}\.log' "v2.10.5: makepkg do AUR não mancha o log com ruído de tentativa curada ('target not found' da 1ª vaia é capturado)"

# O. veredito não celebra fase morta:
assert_grep "$REPO/tests/phases/60-verdict.sh" 'SEM LINHA no summary' "v2.10.5: fase que morre antes do phase_end é NO-GO (GO com 4/5 peças extinto)"

# P. can-suspend ANTES do lock (toast que ninguém via extinto):
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-power" 'loginctl can-suspend' "v2.10.5: hardware sem suspend é avisado NA SESSÃO (nada é travado)"

# Q. o selo do fix-keys só come com a cura feita:
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-fix-keys" 'keyring não atualizado' "v2.10.5: sem rede não escreve selo de 24h (o script não mente)"

phase_end
