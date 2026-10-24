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
bashn=0; bashfail=0
for s in "${SHELLS[@]}"; do
  if bash -n "$s" 2>/dev/null; then bashn=$((bashn+1)); else bashfail=$((bashfail+1)); echo "    sintaxe ruim: $s" >&2; fi
done
assert_eq "$bashfail" "0" "bash -n: $bashn/${#SHELLS[@]} scripts parseiam (repo + a própria suíte)"

# peça: shellcheck — mesmo gate do CI (warning ou acima); local pode não ter
if command -v shellcheck >/dev/null 2>&1; then
  sc_log="$WORK/shellcheck.log"; : > "$sc_log"
  for s in "${SHELLS[@]}"; do
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

# peça v1.5.2: xdotool no packages.add — o debloat v4.2 o varreu e o
# fg-booster crash-loopou em TODA boot v1.0→v1.5 (17 'Failed with result'
# no serial da v1.5; causa-raiz: guard exit 1 + RestartSec=5 que nunca
# atinge o start-limit default). Presença do pacote = contrato de BUILD.
assert_grep "$REPO/elite/packages.add" '^xdotool$' "v1.5.2: xdotool em packages.add (fg-booster — debloat v4.2 o varreu)"

# peças: bits executáveis onde o runtime exige — GLOB-DRIVEN (v1.6.2:
# a lista manual tinha o mesmo buraco da SHELLS — craft-connect/fix-keys/
# pin-pick/idle fora dela; o craft-idle nasceu 100644 no git e ninguém viu)
shopt -s nullglob
EXECBINS=(
  "$REPO"/elite/airootfs/usr/local/bin/*
  "$REPO"/elite/airootfs/etc/skel/.config/labwc/autostart
  "$REPO"/scripts/*.sh
)
shopt -u nullglob
for x in "${EXECBINS[@]}"; do
  [[ -x "$x" ]] && ok "exec: ${x#"$REPO"/}" || fail "exec: ${x#"$REPO"/}" "sem bit de execução"
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
  'scx-elite.service':      {'Unit', 'Service', 'Install'},
  'fg-booster.service':     {'Unit', 'Service', 'Install'},
  'elite-firstboot.service': {'Unit', 'Service', 'Install'},
  'fg-boost.slice':         {'Unit', 'Slice', 'Install'},
  # v1.6.2 — user units do skel (poda do cliphist): service puxado pelo
  # timer NÃO tem (nem precisa de) [Install]; timer tem [Timer]+[Install]
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
print('OK 6')
PYEOF
)
assert_eq "$uout" "OK 6" "systemd: 6 units parseiam (4 de sistema + 2 user v1.6.2 — INI válido, seções completas)"

for f in scx-elite.service fg-booster.service elite-firstboot.service; do
  assert_grep "$U/$f" '^ExecStart=/' "systemd: $f ExecStart com caminho absoluto"
done

for l in multi-user.target.wants/elite-firstboot.service \
         multi-user.target.wants/scx-elite.service \
         multi-user.target.wants/dmemcg-booster-system.service \
         graphical.target.wants/fg-booster.service; do
  [[ -L "$U/$l" ]] \
    && ok "systemd: symlink $l (unit habilitada de fábrica)" \
    || fail "systemd: symlink $l" "não é symlink"
done

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

# ── peças: dock v1.9 — AUTOHIDE PADRÃO (M3.5) + pins do usuário ───────────
# v1.4 tinha a dock SEMPRE visível ("a dock sumiu" era bug de talho cortado).
# v1.9 — spec M3.5 do dono: autohide é PADRÃO DE FÁBRICA, implementado de
# verdade: modo "peek" (config gerado em tmpfs a partir do config ATUAL do
# usuário — margin-bottom -48 = tira de 6px; TODOS os on-click viram
# "craft-dock-autohide show" — clique na tira revela, sem abrir app por
# engano), W-S-d alterna, craft-bars religa no modo vigente em ≤5s.
DK="$REPO/elite/airootfs/etc/skel/.config/waybar/config.dock"
DKCSS="$REPO/elite/airootfs/etc/skel/.config/waybar/style.dock.css"
assert_grep "$DK" '"exclusive": false' "dock: exclusive false (janelas usam a base — modelo macOS)"
assert_grep "$DK" '"margin-bottom": 8' "dock: modo SHOWN flutua 8px (o modo PADRÃO peek é o config.dock.peek gerado em runtime)"
assert_nogrep "$DKCSS" 'margin-bottom: -' "dock: sem margem negativa no CSS (a margem negativa mora no config peek gerado — o talho v1.1 era outra classe)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-config" 'config\.dock\.peek' "autohide: craft-dock-config devolve o config peek (tmpfs, sempre sincronizado com os pins)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-config" '"margin-bottom": -48' "autohide: peek esconde 48px (54 da dock − tira de 6px)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-config" 'craft-dock-autohide show' "autohide: QUALQUER clique na tira REVELA (on-click sobreposto — sem misclick de app)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-autohide" 'toggle' "autohide: toggle existe (W-S-d)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-autohide" 'pkill -f .waybar -c' "autohide: reinício REAL da instância da dock na troca de modo (pkill da instância)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bars" 'craft-dock-config' "autohide: craft-bars sobe a dock no MODO vigente (supervisor integrado)"
assert_grep "$REPO/tests/fixtures/menu-icons-papirus.txt" '.' "fixture Papirus presente (contrato de ícones do menu — v1.6.3 segue)"
assert_grep "$DK" 'PINS \(craft-pin\)' "dock: seção PINS presente (craft-pin add/rm gerencia)"
assert_grep "$DKCSS" 'Pins do usuário \(craft-pin\)' "dock: CSS tem a seção de pins documentada"
pin_defs=$(grep -c '^  "custom/pin-' "$DK" || true)
assert_eq "$pin_defs" "0" "dock: skel sai de fábrica com ZERO pins (usuário fixa os seus)"
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
assert_grep "$TOPCSS" '\-gtk-icon-transform: scale' "css top: ícone do tray 18px via -gtk-icon-transform (GTK3-válido — PROVA positiva: topo 100% limpo na #80)"
assert_grep "$DKCSS" 'min-width: 1px' "css dock: separador │ pisa em 1px (min-width — parseou limpo na #80)"
assert_grep "$DKCSS" 'font-size: 1px' "css dock: glifo do separador encolhido (font-size:1px — o módulo é um espaço; com min-width dá o 1px exato)"

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
  ok "(skip local: sem PyYAML — o container CI o instala; contrato roda lá)"
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
assert_grep "$ECF" '\[E16\]' "debloat sistêmico: E16 presente (variantes Papirus mortas)"
assert_grep "$ECF" 'Papirus-Dark' "debloat sistêmico: E16 mantém Papirus-Dark (GTK/fuzzel do rice)"
assert_grep "$ECF" 'ELITE-FAIL: Papirus' "debloat sistêmico: gate duro do E16 — variantes vivas ausentes = build falha"
MENUX="$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml"
assert_grep "$MENUX" '/usr/share/icons/Papirus/' "debloat sistêmico: menu usa a variante Papirus viva (contrato do fixture)"
assert_nogrep "$MENUX" 'ePapirus|Papirus-Light' "debloat sistêmico: NENHUM config referencia variante podada (ePapirus/Papirus-Light)"
assert_nogrep "$REPO/elite/airootfs/etc/skel/.config/fuzzel/fuzzel.ini" 'ePapirus|Papirus-Light' \
  "debloat sistêmico: fuzzel na variante viva (Papirus-Dark)"
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
  "gtk4: veneno do `> image` cobre HOVER (estado que o Adwaita pinta)"
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

# H2a — craft-pin-status com bit de execução: sem 0755 o exec do waybar
#      morre em Permission denied e os 3 pins de fábrica NASCEM INVISÍVEIS
#      (dock com só 2 ícones — flagrante do dono, IMG_20261024_114720).
AO="$REPO/scripts/apply-overlay.sh"
assert_grep "$AO" '/usr/local/bin/craft-pin-status' \
  "apply-overlay: craft-pin-status na lista file_permissions (0755 — pins visíveis)"

# H2b — reload do craft-pin: SIGUSR2 no waybar 0.15 recarrega SÓ CSS
#      ("fixou, mas a dock não atualizou" — áudio do dono). Reload real =
#      reiniciar o waybar (craft-bars devolve em ≤5s lendo o config novo).
#      (o contrato nogrep 'pkill -SIGUSR2' já existe na peça da dock — 223)
CPIN="$REPO/elite/airootfs/usr/local/bin/craft-pin"
assert_grep "$CPIN" 'pkill -x waybar' \
  "craft-pin: reload reinicia o waybar (config novo entra; supervisor devolve)"

# H3 — cross-dismiss: abrir Sessão fecha Rede e vice-versa (nunca 2
#      dropdowns empilhados — áudio do dono, 24/out e 21/out)
CPOW="$REPO/elite/airootfs/usr/local/bin/craft-power"
CCON="$REPO/elite/airootfs/usr/local/bin/craft-connect"
assert_grep "$CPOW" "pkill -f 'fuzzel\.\*--prompt=Rede'" \
  "craft-power: cross-dismiss — abrir Sessão fecha o menu de Rede"
assert_grep "$CCON" "pkill -f 'fuzzel\.\*--prompt=Sess'" \
  "craft-connect: cross-dismiss — abrir Rede fecha o menu de Sessão"

# H4 — conectividade GUI (dono: "impala e bluetui eu não sei utilizar…
#      quero mais bonito e mais fácil"): nm-applet + blueman de volta,
#      craft-connect abre nm-connection-editor/blueman-manager, applets
#      na sessão, TUIs só como fallback
assert_grep "$REPO/elite/packages.add" '^network-manager-applet$' \
  "packages.add: network-manager-applet de volta (GUI de rede no dia a dia — nm-applet é o binário)"
assert_grep "$REPO/elite/packages.add" '^blueman$' \
  "packages.add: blueman de volta (GUI de bluetooth no dia a dia)"
assert_grep "$CCON" 'nm-connection-editor' \
  "craft-connect: menu abre GUI de rede (TUI impala só como fallback)"
assert_grep "$CCON" 'blueman-manager' \
  "craft-connect: menu abre GUI de bluetooth (TUI bluetui só como fallback)"
RCXML="$REPO/elite/airootfs/etc/skel/.config/labwc/rc.xml"
assert_grep "$RCXML" 'command="nm-connection-editor"' \
  "rc.xml: W-n abre GUI de rede (era impala TUI)"
assert_grep "$RCXML" 'command="blueman-manager"' \
  "rc.xml: W-S-b abre GUI de bluetooth (era bluetui TUI)"
AUTO="$REPO/elite/airootfs/etc/skel/.config/labwc/autostart"
assert_grep "$AUTO" 'nm-applet &' \
  "autostart: nm-applet na tray (ícone de rede sempre à mão)"
assert_grep "$AUTO" 'blueman-applet &' \
  "autostart: blueman-applet na tray (bluetooth à mão)"

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

phase_end


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

# ── M1.2: Calamares transparente — log ao vivo + persistente ──
CALLOG="$REPO/elite/airootfs/usr/local/bin/calamares-elite-log"
CALD="$REPO/elite/airootfs/usr/local/share/applications/calamares.desktop"
assert_grep "$CALD" 'calamares-elite-log' "M1.2: calamares.desktop lança o wrapper de log (Exec=)"
assert_grep "$CALLOG" 'tail -n 30 -F' "M1.2: terminal de logs EM TEMPO REAL (foot + tail -F do session.log)"
assert_grep "$CALLOG" '/var/log/calamares\.log' "M1.2: log completo persistido em /var/log/calamares.log"
assert_grep "$CALLOG" '/etc/calamares/launch.sh' "M1.2: launch.sh upstream curado segue intocado (E5a2)"

# ── M2: top bar — geometria (Y centrado, tray com respiro, linha morta) ──
TOPCSS="$REPO/elite/airootfs/etc/skel/.config/waybar/style.top.css"
assert_nogrep "$TOPCSS" 'border-bottom' "M2.3: a linha fantasma sob a barra está MORTA (border-bottom removido do window#waybar)"
assert_grep "$TOPCSS" 'padding-top: 2px' "M2.1: padding vertical SIMÉTRICO no painel (topo == base — ícone não encosta no teto)"
assert_grep "$TOPCSS" 'padding-bottom: 2px' "M2.1: padding-bottom presente (par do padding-top)"
assert_grep "$TOPCSS" 'padding: 0 14px 0 8px' "M2.2: tray com 14px de respiro à direita (entre os 12-16px do spec)"

# ── M3: dock — centralização, escala fixa, ícones reais, launcher único ──
assert_grep "$DKCSS" 'min-height: 48px' "M3.1: bounding box PADRONIZADO nos botões da taskbar (48px — ícone centralizado)"
assert_nogrep "$DKCSS" 'border-bottom: 3px' "M3.1: o indicador .active NÃO usa border-bottom (empurrava o ícone p/ cima — box-shadow inset, zero shift)"
assert_nogrep "$DKCSS" 'font-size 0\.18s' "M3.1: SEM zoom por font-size (a transição mudava a caixa e desalinhava o glifo no hover — escala fixa)"
assert_grep "$DKCSS" 'font-size: 30px' "M3.2: escala FIXA dos glifos (30px — sem exceção, sem estado de zoom)"
assert_grep "$REPO/elite/airootfs/usr/local/share/applications/lact.desktop" 'Icon=/usr/share/pixmaps/elite/lact\.png' "M3.3: LACT com Icon= absoluto (ícone real, não genérico)"
assert_grep "$REPO/elite/airootfs/usr/local/share/applications/btop.desktop" 'Icon=/usr/share/pixmaps/elite/btop\.png' "M3.3: btop com Icon= absoluto"
assert_grep "$REPO/elite/airootfs/usr/local/share/applications/mpv.desktop" 'Icon=/usr/share/pixmaps/elite/mpv\.png' "M3.3: mpv com Icon= absoluto"
assert_grep "$REPO/elite/airootfs/usr/local/share/applications/calamares.desktop" 'Icon=/usr/share/pixmaps/elite/elite-install\.png' "M3.3: Instalador Archcraft com Icon= absoluto"
for iconf in lact btop mpv elite-install; do
  assert_file "$REPO/elite/airootfs/usr/share/pixmaps/elite/$iconf.png" "M3.3: ativo de ícone real no pacote ($iconf.png — o Icon= resolve SEMPRE)"
done

# ── M4: tecla Super = menu de aplicativos ──
RCX="$REPO/elite/airootfs/etc/skel/.config/labwc/rc.xml"
assert_grep "$RCX" 'key="Super_L"' "M4.1: tecla SUPER mapeada (só pressionada → Launchpad)"
assert_grep "$RCX" 'key="W-S-d"' "M3.5: W-S-d alterna a dock (autohide toggle)"

# ── M5: wallpaper vetorial flat (sem poeira) — arquivo selado no 40-int ──
assert_file "$REPO/elite/airootfs/etc/skel/.config/labwc/wallpaper.png" "M5.1: wallpaper.png (PNG lossless — o JPEG com ruído saiu de cena)"
assert_nogrep "$REPO/elite/airootfs/etc/skel/.config/labwc/autostart" 'wallpaper\.jpg.*first' "M5.1: autostart NÃO prefere mais o jpg (PNG primeiro)"

# ── file_permissions: os 3 binários novos precisam de 0755 (203/EXEC) ──
for nb in craft-dock-config craft-dock-autohide calamares-elite-log; do
  assert_grep "$REPO/scripts/apply-overlay.sh" "/usr/local/bin/$nb" "apply-overlay: $nb registrado no file_permissions (senão 203/EXEC no live)"
done
