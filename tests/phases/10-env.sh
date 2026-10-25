#!/usr/bin/env bash
# FASE 1 — A MESA: ambiente e inventário (sem mesa não há quebra-cabeça)
source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"
phase_start 1 "A MESA — ambiente e inventário"

# peças: arquivos vivos do repo
for f in \
  elite/airootfs/usr/local/bin/elite-tune \
  elite/airootfs/usr/local/bin/elite-status \
  elite/airootfs/usr/local/bin/craft-fix-keys \
  elite/fragments/elite-customize.sh \
  elite/packages.add \
  elite/packages.remove \
  elite/pacman-repos.build.add \
  scripts/apply-overlay.sh \
  .ci/build.sh \
  .github/workflows/build.yml \
  .github/workflows/agents.yml \
  elite/airootfs/etc/skel/.config/brave-flags.conf \
  elite/airootfs/etc/skel/.config/hypr/hyprlock.conf \
  elite/airootfs/etc/skel/.face.icon \
  elite/airootfs/etc/skel/.config/mimeapps.list \
  elite/airootfs/etc/sysctl.d/99-elite-net.conf \
  elite/airootfs/etc/modules-load.d/elite-bbr.conf
do
  assert_file "$REPO/$f" "inventário: $f"
done

# peças: ferramentas que as fases seguintes precisam
for t in git rsync curl sha256sum split python3; do
  command -v "$t" >/dev/null 2>&1 \
    && ok "ferramenta: $t" \
    || fail "ferramenta: $t" "binário ausente no PATH"
done

python3 -c 'import yaml' 2>/dev/null \
  && ok "ferramenta: python3+pyyaml (validador de workflows)" \
  || fail "ferramenta: python3+pyyaml" " módulo yaml ausente (pip install pyyaml)"

# peças: fixtures íntegros (o quebra-cabeça confere a própria caixa)
FIX="$TESTS_DIR/fixtures/lspci"
n=0
for f in rtx-5060 rx-7600 intel-igpu hybrid-optimus nv-gp102-bare nv-device-bare matrox-unknown; do
  [[ -s "$FIX/$f.txt" ]] && n=$((n+1))
done
[[ -f "$FIX/no-vga.txt" ]] && n=$((n+1))
assert_eq "$n" "8" "fixtures: 8 cenários de lspci no lugar"

# peça: bash ≥ 5 (assoc arrays + <<= nos scripts do repo)
v="${BASH_VERSINFO[0]:-0}"
(( v >= 5 )) && ok "ferramenta: bash $v (≥5)" || fail "ferramenta: bash $v" "esperado ≥5"

phase_end
