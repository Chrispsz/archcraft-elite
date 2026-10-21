#!/usr/bin/env bash
# FASE 2 — A TAMPA DA CAIXA: qualidade estática (o desenho completo antes de abrir)
source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"
phase_start 2 "QUALIDADE ESTÁTICA — a tampa da caixa"

SHELLS=(
  scripts/apply-overlay.sh
  scripts/qemu-boot-test.sh
  .ci/build.sh
  elite/fragments/elite-customize.sh
  elite/airootfs/usr/local/bin/elite-tune
  elite/airootfs/usr/local/bin/fg-booster
  elite/airootfs/usr/local/bin/elite-status
  elite/airootfs/usr/local/bin/craft-hello
  elite/airootfs/usr/local/bin/craft-update
  elite/airootfs/usr/local/bin/craft-clean
  elite/airootfs/usr/local/bin/craft-rollback
  elite/airootfs/usr/local/bin/craft-lock
  elite/airootfs/usr/local/bin/craft-logout
  elite/airootfs/usr/local/bin/craft-shot
  elite/airootfs/usr/local/bin/craft-bat
  elite/airootfs/usr/local/bin/craft-drawer
  elite/airootfs/usr/local/bin/craft-power
  elite/airootfs/etc/skel/.config/labwc/autostart
  tests/run-tests.sh
  tests/lib/core.sh
  tests/lib/setup.sh
  tests/lib/ns-body.sh
  tests/phases/10-env.sh tests/phases/20-static.sh tests/phases/30-unit.sh
  tests/phases/40-integration.sh tests/phases/50-release.sh tests/phases/60-verdict.sh
)

# peças: sintaxe — bash -n em tudo (a suíte testa a si mesma: peças 7-12)
bashn=0; bashfail=0
for s in "${SHELLS[@]}"; do
  if bash -n "$REPO/$s" 2>/dev/null; then bashn=$((bashn+1)); else bashfail=$((bashfail+1)); echo "    sintaxe ruim: $s" >&2; fi
done
assert_eq "$bashfail" "0" "bash -n: $bashn/${#SHELLS[@]} scripts parseiam (repo + a própria suíte)"

# peça: shellcheck — mesmo gate do CI (warning ou acima); local pode não ter
if command -v shellcheck >/dev/null 2>&1; then
  sc_log="$WORK/shellcheck.log"; : > "$sc_log"
  for s in "${SHELLS[@]}"; do
    shellcheck -S warning -x "$REPO/$s" >> "$sc_log" 2>&1 || true
  done
  # o lint cobre também os mocks/extract gerados (padrão de qualidade da suíte)
  assert_eq "$(wc -l < "$sc_log")" "0" "shellcheck: 0 avisos em ${#SHELLS[@]} scripts (gate do CI)"
else
  skip "shellcheck: gate do CI" "binário ausente neste ambiente — o job de lint no GitHub o executa"
fi

# peças: YAML válido (os 4 workflows — diag-install entrou na lista v1.0.5:
# virou workflow_call load-bearing, gate obrigatório do release)
for y in build.yml diag-install.yml agents.yml tests.yml; do
  if [[ -f "$REPO/.github/workflows/$y" ]]; then
    python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$REPO/.github/workflows/$y" 2>/dev/null \
      && ok "yaml: $y parseia" \
      || fail "yaml: $y" "YAML inválido"
  else
    fail "yaml: $y" "workflow ausente"
  fi
done

# peças: bits executáveis onde o runtime exige
for x in \
  elite/airootfs/usr/local/bin/elite-tune \
  elite/airootfs/usr/local/bin/fg-booster \
  elite/airootfs/usr/local/bin/elite-status \
  elite/airootfs/usr/local/bin/craft-hello \
  elite/airootfs/usr/local/bin/craft-update \
  elite/airootfs/usr/local/bin/craft-clean \
  elite/airootfs/usr/local/bin/craft-rollback \
  elite/airootfs/usr/local/bin/craft-lock \
  elite/airootfs/usr/local/bin/craft-logout \
  elite/airootfs/usr/local/bin/craft-drawer \
  elite/airootfs/usr/local/bin/craft-power \
  elite/airootfs/usr/local/bin/craft-shot \
  elite/airootfs/usr/local/bin/craft-bat \
  elite/airootfs/etc/skel/.config/labwc/autostart \
  scripts/apply-overlay.sh \
  scripts/qemu-boot-test.sh
do
  [[ -x "$REPO/$x" ]] && ok "exec: $x" || fail "exec: $x" "sem bit de execução"
done

# peças: higiene — sem CRLF, shebang presente
crlf=0
for s in "${SHELLS[@]}" "$REPO"/.github/workflows/*.yml; do
  grep -qU $'\r' "$s" 2>/dev/null && crlf=$((crlf+1))
done
assert_eq "$crlf" "0" "higiene: 0 arquivos com CRLF"

sheb=0
for x in elite-tune fg-booster elite-status craft-hello craft-update craft-clean \
         craft-rollback craft-lock craft-logout craft-shot craft-bat \
         craft-drawer craft-power; do
  head -1 "$REPO/elite/airootfs/usr/local/bin/$x" | grep -q '^#!' && sheb=$((sheb+1))
done
assert_eq "$sheb" "13" "higiene: shebang nos 13 binários do airootfs"
head -1 "$REPO/elite/airootfs/etc/skel/.config/labwc/autostart" | grep -q '^#!/bin/sh' \
  && ok "higiene: autostart do labwc é POSIX sh com shebang" \
  || fail "autostart do labwc" "shebang #!/bin/sh ausente"

# ── peças: units systemd embarcadas (parse INI de verdade — typo não passa) ──
U="$REPO/elite/airootfs/etc/systemd/system"
uout=$(python3 - "$U" 2>&1 <<'PYEOF' || true
import configparser, sys
u = sys.argv[1]
cases = {
  'scx-elite.service':      {'Unit', 'Service', 'Install'},
  'fg-booster.service':     {'Unit', 'Service', 'Install'},
  'elite-firstboot.service': {'Unit', 'Service', 'Install'},
  'fg-boost.slice':         {'Unit', 'Slice', 'Install'},
}
# strict=False: systemd PERMITE chaves repetidas (ConditionPathExists=
# acumula condições) — o parse aqui checa sintaxe e seções, não política
# de duplicatas (que é legítima em units)
for f, want in cases.items():
    cp = configparser.ConfigParser(strict=False)
    try:
        cp.read(f'{u}/{f}')
        got = set(cp.sections())
        missing = want - got
        if missing:
            raise AssertionError(f'{f}: sem seção(ões) {missing}')
    except Exception as e:
        print(f'FALHOU: {e}'); sys.exit(1)
print('OK 4')
PYEOF
)
assert_eq "$uout" "OK 4" "systemd: 4 units parseiam (INI válido) com Unit+Service|Slice+Install"

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

phase_end
