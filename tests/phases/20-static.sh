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

# ── peças: dock SEMPRE VISÍVEL (v1.4) + pins do usuário (contratos do rice) ─
DK="$REPO/elite/airootfs/etc/skel/.config/waybar/config.dock"
DKCSS="$REPO/elite/airootfs/etc/skel/.config/waybar/style.dock.css"
assert_grep "$DK" '"exclusive": false' "dock: exclusive false (janelas usam a base — modelo macOS)"
# v1.4 (burn test do dono: "a dock sumiu"): auto-hide MORTO — a pílula é
# SEMPRE visível, flutuando 8px (config) sem margem negativa no CSS
assert_grep "$DK" '"margin-bottom": 8' "dock: v1.4 flutua 8px SEMPRE (auto-hide extinto)"
assert_nogrep "$DKCSS" 'margin-bottom: -' "dock: v1.4 sem margem negativa no CSS (o talho de ícones cortados era isso)"
assert_grep "$DK" 'PINS \(craft-pin\)' "dock: seção PINS presente (craft-pin add/rm gerencia)"
assert_grep "$DKCSS" 'Pins do usuário \(craft-pin\)' "dock: CSS tem a seção de pins documentada"
pin_defs=$(grep -c '^  "custom/pin-' "$DK" || true)
assert_eq "$pin_defs" "0" "dock: skel sai de fábrica com ZERO pins (usuário fixa os seus)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin" 'pkill -SIGUSR2' \
  "craft-pin: reload via SIGUSR2 (man 5 waybar: recarrega config+estilo)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin" '\.bak\.' \
  "craft-pin: toda mutação grava backup restaurável (craft-pin restore)"
assert_grep "$REPO/scripts/apply-overlay.sh" 'craft-pin' \
  "apply-overlay: craft-pin registrado no file_permissions (senão 203/EXEC no live)"

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

phase_end
