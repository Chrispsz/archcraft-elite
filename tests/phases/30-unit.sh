#!/usr/bin/env bash
# FASE 3 — PEÇAS AVULSAS SOB A LUZ: unidade (cada peça isolada, peça por peça)
source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"
phase_start 3 "UNIDADE — peças avulsas sob a luz"

FIX="$TESTS_DIR/fixtures/lspci"

# ── 3.A detecção de hardware (função REAL, mocks de lspci/nvidia-smi) ──
detect() { # <fixture> [nome-smi] -> "vendor gen"
  with_mocks env DETECT_ONLY=1 LSPCI_FIXTURE="$FIX/$1" NVIDIA_SMI="${2:-}" \
    bash "$WORK/extract.sh"
}
assert_eq "$(detect rtx-5060.txt)"                    "nvidia blackwell" "detect: RTX 5060 (Setup A) → nvidia/blackwell"
assert_eq "$(detect rtx-5060.txt 'NVIDIA GeForce RTX 5060')" "nvidia blackwell" "detect: RTX 5060 + nvidia-smi"
assert_eq "$(detect rx-7600.txt)"                     "amd unknown"      "detect: RX 7600 (Setup B) → amd"
assert_eq "$(detect intel-igpu.txt)"                  "intel unknown"    "detect: iGPU Intel → intel"
assert_eq "$(detect hybrid-optimus.txt)"              "intel unknown"    "detect: híbrido sem smi → intel (conservador: só a 1ª linha conta)"
assert_eq "$(detect nv-gp102-bare.txt)"               "nvidia pascal"    "detect: GP102 sem pciids → resgate pelo codinome (gp1)"
assert_eq "$(detect nv-device-bare.txt)"              "nvidia unknown"   "detect: 'Device 2684' sem pciids → nvidia (o 'ati' de Corpor|ati|on NÃO pode virar amd)"
assert_eq "$(detect matrox-unknown.txt)"              "unknown unknown"  "detect: Matrox (sem vendor conhecido) → unknown"
assert_eq "$(detect no-vga.txt)"                      "unknown unknown"  "detect: lspci sem VGA → unknown sem crash"

# ── 3.B gpu_cleanup_foreign (allowlist por nome — nunca -Qmq genérico) ──
CU() { with_mocks env CU_VENDOR="$1" bash "$WORK/extract.sh"; }
fresh_state() { : > "$STATE/installed.txt"; : > "$STATE/pacman.log"; rm -f "$STATE/refuse"; }
installed() { for p in "$@"; do echo "$p" >> "$STATE/installed.txt"; done; }

# Setup B (amd) herdando o stack NVIDIA inteiro da ISO:
fresh_state; installed nvidia-open nvidia-utils nvidia-settings lib32-nvidia-utils \
  vulkan-intel lib32-vulkan-intel mesa steam linux-cachyos-bore
out="$(CU amd)"
assert_match "$out" 'Auto-limpeza: GPU amd → removendo stack do outro vendor \(nvidia-open nvidia-utils nvidia-settings lib32-nvidia-utils vulkan-intel lib32-vulkan-intel\)' \
  "cleanup amd: anuncia os 6 pacotes do stack estranho"
assert_grep "$STATE/pacman.log" '^pacman -Rns --noconfirm nvidia-open nvidia-utils nvidia-settings lib32-nvidia-utils vulkan-intel lib32-vulkan-intel$' \
  "cleanup amd: remove EXATAMENTE os 6 da allowlist (ordem e conteúdo)"
grep -qxF nvidia-open "$STATE/installed.txt" \
  && fail "cleanup amd: pacotes saíram do estado" "nvidia-open ainda instalado" \
  || ok    "cleanup amd: stack NVIDIA saiu do estado (installed.txt)"
for kept in mesa steam linux-cachyos-bore; do
  grep -qxF "$kept" "$STATE/installed.txt" \
    && ok "cleanup amd: $kept intocado" \
    || fail "cleanup amd: $kept intocado" "foi removido — allowlist vazou!"
done

# Setup A (nvidia) herdando ICDs Vulkan alienígenas:
fresh_state; installed vulkan-radeon lib32-vulkan-radeon vulkan-intel lib32-vulkan-intel \
  mesa steam linux-cachyos-bore nvidia-open nvidia-utils
out="$(CU nvidia)"
assert_match "$out" 'Auto-limpeza: GPU nvidia → removendo stack do outro vendor \(vulkan-radeon lib32-vulkan-radeon vulkan-intel lib32-vulkan-intel\)' \
  "cleanup nvidia: anuncia os 4 ICDs estranhos"
grep -qxF vulkan-radeon "$STATE/installed.txt" \
  && fail "cleanup nvidia: ICDs saíram do estado" "vulkan-radeon ainda instalado" \
  || ok    "cleanup nvidia: ICDs AMD/Intel saíram, mesa/nvidia ficaram"

# rig já limpo → no-op barulhento
fresh_state; installed mesa linux-cachyos-bore
out="$(CU amd)"
assert_match "$out" 'nenhum pacote estranho ao hardware \(já limpo\)' "cleanup: rig limpo → no-op declarado"
grep -q -- '-Rns' "$STATE/pacman.log" \
  && fail "cleanup: no-op não chamou -Rns" "log trouxe remoção" \
  || ok    "cleanup: no-op não disparou remoção"

# pacman recusa (dependência) → warn + rc 0 (firstboot nunca morre por causa da limpeza)
fresh_state; installed nvidia-open nvidia-utils mesa linux-cachyos-bore; touch "$STATE/refuse"
out="$(CU amd)"; rc=$?
assert_eq "$rc" "0" "cleanup: recusa do pacman não derruba o script (rc 0)"
assert_match "$out" "restou 'nvidia-open'" "cleanup: recusa vira aviso manual (restou …)"

# vendor desconhecida → silêncio e rc 0 (nunca chuta)
fresh_state; installed nvidia-open mesa
out="$(CU unknown)"; rc=$?
assert_eq "$rc" "0" "cleanup: vendor unknown → rc 0"
assert_eq "$out" "" "cleanup: vendor unknown → zero ação (não chuta)"

# ── 3.C regressão #27: o glob do pywal (cd com 2 args) ───────────────
pyw="$WORK/pywal-case"; rm -rf "$pyw"; mkdir -p "$pyw/pywal-236aa48e741ff8d65c4c3826db2813bf2ee6f352"
touch "$pyw/pywal-master.tar.gz"
if ( cd "$pyw" && cd pywal-* ) 2>/dev/null; then
  fail "pywal #27: glob sem barra FALHA" "cd pywal-* tinha que recusar (2 entradas); aceitou"
else
  ok "pywal #27: glob sem barra recusa (cd: too many arguments — o bug do run #27)"
fi
landed="$( cd "$pyw" && cd pywal-*/ && pwd )"
assert_match "$landed" 'pywal-236aa48e' "pywal #27: com barra aterrissa no diretório do pin"
assert_grep "$REPO/.ci/build.sh" 'cd pywal-\*/' "pywal #27: o PKGBUILD do CI usa a forma com barra"

# ── 3.D contratos dos workflows (o texto do CI é promessa pública) ──
BY="$REPO/.github/workflows/build.yml"
assert_eq "$(grep -c 'runs-on: ubuntu-24.04' "$BY")" "2" "contrato: build.yml — os 2 jobs pinados em ubuntu-24.04"
assert_grep "$BY" 'split -b 1900M -d "\$ISO" "\$\{ISO\}\.part-"' "contrato: split com prefixo aspasado"
assert_grep "$BY" 'sha256sum -- "\$\{ISO\}\.part-"\* >> sha256sums\.txt' "contrato: hashes das PARTES ANEXADOS (>>)"
pat_q=$(printf '%s' "grep -E 'part|" "\${ISO}\$' sha256sums.txt")
if grep -qF -- "$pat_q" "$BY"; then
  ok "contrato: verificação do usuário com regex aspasada (string exata)"
else
  fail "contrato: verificação do usuário com regex aspasada" "ausente: $pat_q"
fi
assert_grep "$BY" 'cancel-in-progress: true' "contrato: build.yml — cancel-in-progress"
assert_grep "$BY" "tags: \['v\*'\]" "contrato: build.yml — tag v* dispara release"
assert_grep "$BY" 'paths-ignore:.*tests/\*\*' "contrato: build.yml — tests/** não recompila ISO"
AY="$REPO/.github/workflows/agents.yml"
assert_grep "$AY" 'deepseek' "contrato: agents.yml — deepseek presente"
assert_grep "$AY" 'mimo' "contrato: agents.yml — mimo presente"
assert_grep "$AY" 'actions: read' "contrato: agents.yml — permissão de ler runs"

# ── 3.E listas de pacotes (sanidade das duas caixas) ─────────────────
PA="$REPO/elite/packages.add"; PR="$REPO/elite/packages.remove"
bad_a=$(grep -vE '^(#.*|[a-z0-9][a-z0-9@._+-]*)$' "$PA" | grep -vc '^$' || true)
assert_eq "$bad_a" "0" "packages.add: só nomes válidos ou comentários"
dup_a=$(grep -v '^#' "$PA" | sed 's/#.*//' | grep -v '^$' | tr -d ' ' | sort | uniq -d | wc -l)
assert_eq "$dup_a" "0" "packages.add: sem duplicatas"
dup_r=$(grep -v '^#' "$PR" | sed 's/#.*//' | grep -v '^$' | tr -d ' ' | sort | uniq -d | wc -l)
assert_eq "$dup_r" "0" "packages.remove: sem duplicatas"
both=$(comm -12 <(grep -v '^#' "$PA" | sed 's/#.*//' | tr -d ' ' | grep -v '^$' | sort) \
                 <(grep -v '^#' "$PR" | sed 's/#.*//' | tr -d ' ' | grep -v '^$' | sort))
assert_eq "$both" "" "packages.add ∩ packages.remove = ∅ (sem esquizofrenia)"

# ── 3.F o grep do usuário final (armadilhas A1/A2 do auditor mimo) ──
g="$WORK/grep-case"; mkdir -p "$g"
iso="archcraft-elite-2026.10.20-x86_64.iso"
printf '%s\n' \
  "1111111111111111111111111111111111111111111111111111111111111111  $iso" \
  "2222222222222222222222222222222222222222222222222222222222222222  $iso.part-00" \
  "3333333333333333333333333333333333333333333333333333333333333333  $iso.part-01" \
  "4444444444444444444  JUNTAR-ISO.md" > "$g/sha256sums.txt"
sel=$(cd "$g" && grep -E "part|$iso\$" sha256sums.txt | wc -l)
assert_eq "$sel" "3" "grep do usuário: seleciona ISO + 2 partes, exclui JUNTAR-ISO.md"
nosel=$(cd "$g" && grep -E "part|$iso\$" sha256sums.txt | grep -c JUNTAR || true)
assert_eq "$nosel" "0" "grep do usuário: pipeline-sem-aspas não vaza (A1 fechada)"

# ── 3.G contratos de build (lacunas apontadas na revisão deepseek run #11) ─
# #19: o stderr do -Syw tem de SER MOSTRADO na falha (não escondido)
assert_grep "$REPO/.ci/build.sh" 'stderr do próprio -Syw' "contrato #19: preflight revela o stderr do -Syw (não esconde)"
assert_grep "$REPO/.ci/build.sh" '-Syw .*>/tmp/elite-pf\.log' "contrato #19: stderr do -Syw vai p/ log que é dumpado (nunca /dev/null)"
# #25: out/ precisa mudar de dono (container root → uid do runner) antes do split
assert_grep "$REPO/.ci/build.sh" 'chown -R "\$\{HOST_UID\}' "contrato #25: build.sh entrega out/ ao uid do runner (chown)"
assert_grep "$REPO/.github/workflows/build.yml" '-e HOST_UID="\$\(id -u\)"' "contrato #25: workflow passa o uid do runner ao container"
# #20/#21: E3 garante Architecture + [options] no pacman.conf do SISTEMA (chroot)
assert_grep "$REPO/elite/fragments/elite-customize.sh" "grep -q '\^Architecture' /tmp/elite-pc-options" "contrato E3: fallback Architecture existe (#20)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" "Architecture = x86_64 x86_64_v3" "contrato E3:Architecture aceita v3 (#21)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'opt && /\^\\\[/\{' "contrato E3: awk captura [options] inteiro — sem ele o conf sai sem seção"

# ── 3.H ensure_cmdline_token (a inserção GRUB "à prova de aspas") ────
#  A função mais delicada do produto: sed in-place numa linha aspasada do
#  GRUB. O dry-run NUNCA a exercita (guard EUID/DRY) — aqui ela roda de
#  verdade, peça por peça, num arquivo do $WORK (nunca no /etc do host).
if [[ $EUID -eq 0 ]] || unshare -r true 2>/dev/null; then
  ECTROOT=(); [[ $EUID -ne 0 ]] && ECTROOT=(unshare -r)
  ect() { # <arquivo> <token> [ECT_DRY=1] → executa a função REAL do produto
    local f=$1 t=$2; shift 2
    with_mocks "${ECTROOT[@]}" env ECT_FILE="$f" ECT_TOKEN="$t" "$@" bash "$WORK/extract.sh"
  }
  D="$WORK/ect"; rm -rf "$D"; mkdir -p "$D"

  printf 'GRUB_TIMEOUT=5\n' > "$D/g1"
  ect "$D/g1" amd_pstate=active
  assert_grep "$D/g1" '^GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_pstate=active"$' \
    "GRUB: arquivo SEM a linha → cria com o token"

  printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' > "$D/g2"
  ect "$D/g2" nowatchdog
  assert_grep "$D/g2" 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nowatchdog"' \
    "GRUB: token entra DENTRO das aspas existentes"

  printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet nowatchdog"\n' > "$D/g3"
  cp "$D/g3" "$D/g3.orig"
  ect "$D/g3" nowatchdog
  cmp -s "$D/g3" "$D/g3.orig" \
    && ok "GRUB: token repetido → arquivo intocado (idempotente)" \
    || fail "GRUB: token repetido → idempotente" "arquivo mudou"

  printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' > "$D/g4"
  ect "$D/g4" zswap.enabled=0
  ect "$D/g4" transparent_hugepage=always
  assert_grep "$D/g4" 'quiet splash zswap\.enabled=0 transparent_hugepage=always' \
    "GRUB: múltiplos tokens encadeiam sem perder os anteriores"

  printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' > "$D/g5"
  ect "$D/g5" nowatchdog ECT_DRY=1
  assert_grep "$D/g5" '^GRUB_CMDLINE_LINUX_DEFAULT="quiet"$' \
    "GRUB: --dry-run não toca no arquivo (guard EUID/DRY)"
  if ls "$D"/g5.bak.* >/dev/null 2>&1; then
    fail "GRUB: dry não cria backup" "apareceu .bak em simulação"
  else
    ok "GRUB: dry não cria .bak (v4.4)"
  fi

  printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' > "$D/g6"
  ect "$D/g6" nowatchdog
  if ls "$D"/g6.bak.* >/dev/null 2>&1; then
    ok "GRUB: modo REAL preserva o histórico (.bak criado)"
  else
    fail "GRUB: modo real cria .bak" "backup ausente na edição real"
  fi
else
  skip "3.H GRUB (6 peças): exige root" "unshare indisponível — o job do CI roda como root"
fi

# ── 3.I mirror CachyOS fora do ar → PINNED salvam o dia (resiliência) ─
#  O curl mockado SEMPRE falha: discover_latest tem que voltar vazio e o
#  produto tem que cair nos nomes PINNED (contrato de rede instável).
dl() { with_mocks env DL_PROBE="$1" bash "$WORK/extract.sh"; }
assert_eq "$(dl cachyos-keyring)"       "[]" "resiliência: mirror fora → discover_latest(keyring) vazio"
assert_eq "$(dl cachyos-v3-mirrorlist)" "[]" "resiliência: mirror fora → discover_latest(mirrorlist v3) vazio"
TUNE_BIN="$REPO/elite/airootfs/usr/local/bin/elite-tune"
assert_grep "$TUNE_BIN" '\|\| kr="\$PINNED_KEYRING"' "resiliência: fallback kr=PINNED_KEYRING no produto"
assert_grep "$TUNE_BIN" '\|\| ml="\$PINNED_V3ML"'    "resiliência: fallback ml=PINNED_V3ML no produto"

# ── 3.J híbrido Optimus COM nvidia-smi: a dGPU dedicada vence ─────────
assert_eq "$(detect hybrid-optimus.txt 'NVIDIA GeForce RTX 4060')" "nvidia ada" \
  "detect: híbrido + smi → dGPU vence (rtx 40 → ada, driver certo)"

phase_end
