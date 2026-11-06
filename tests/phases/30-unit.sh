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

# Setup B (amd) herdando o stack NVIDIA inteiro da ISO (v1.1: inclui o
# nvidia-open-dkms pré-compilado — quem não é NVIDIA não carrega driver alheio):
fresh_state; installed nvidia-open nvidia-open-dkms nvidia-utils nvidia-settings lib32-nvidia-utils \
  vulkan-intel lib32-vulkan-intel mesa steam linux-cachyos-bore
out="$(CU amd)"
assert_match "$out" 'Auto-limpeza: GPU amd → removendo stack do outro vendor \(nvidia-open nvidia-open-dkms nvidia-utils nvidia-settings lib32-nvidia-utils vulkan-intel lib32-vulkan-intel\)' \
  "cleanup amd: anuncia os 7 pacotes do stack estranho (v4.6: + nvidia-open-dkms)"
assert_grep "$STATE/pacman.log" '^pacman -Rns --noconfirm nvidia-open nvidia-open-dkms nvidia-utils nvidia-settings lib32-nvidia-utils vulkan-intel lib32-vulkan-intel$' \
  "cleanup amd: remove EXATAMENTE os 7 da allowlist (ordem e conteúdo)"
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

# v4.6: varredura dos .ko pré-compilados é CONTRATO de código (o dkms do
# build os compilou fora do controle de arquivos do pacman; guarda DRY)
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-tune" \
  'for m in /usr/lib/modules/\*/updates/dkms/nvidia\*\.ko\*; do' \
  "cleanup (contrato v4.6): varre /usr/lib/modules/*/updates/dkms/nvidia*.ko*"
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-tune" \
  '\(\( DRY \)\) \|\| rm -f "\$m"' \
  "cleanup (contrato v4.6): rm dos .ko respeita o DRY (dry é seco)"

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
# v1.0.3/v1.0.5: 4 jobs com runs-on próprio pinados em ubuntu-24.04 (lint,
# build, release, verify — runner image é superfície de risco p/ o build
# privilegiado, o release e o QEMU do gate); relay-agents (só dispatch da
# API) fica no ubuntu-latest; verify-install (v1.0.5) é workflow_call — o
# runs-on mora no verify-install.yml (ex-diag-install) reutilizado, também 24.04
# E31 (v2.10.19): o suite (v2.10.5) e o notify-failure (issue de diagnóstico
# de tag) entram na mesma disciplina de pino — 6 no total.
assert_eq "$(grep -c 'runs-on: ubuntu-24.04' "$BY")" "6" "contrato: build.yml — 6 jobs pinados em ubuntu-24.04 (lint/build/release/verify/suite + notify-failure da E31 — a disciplina do pino é para todo job que importa)"
assert_grep "$BY" 'needs: \[build, verify, verify-install, suite\]' "contrato: release SÓ depois do gate de boot E do gate de instalação E da suíte (v1.0.5 + v2.10.5)"
assert_grep "$BY" 'verify-install:' "contrato: job verify-install presente (install-gate no pipeline)"
assert_grep "$BY" 'uses: \./\.github/workflows/verify-install\.yml' "contrato: install-gate reusa o verify-install.yml (workflow_call — zero duplicação)"
assert_grep "$BY" "code=203/EXEC" "contrato: gate verifica 203/EXEC (binários executáveis no live)"
assert_nogrep "$BY" 'gh workflow run agents\.yml' "contrato v2.1: a build NÃO dispatcha agentes (auditoria sob demanda — agents.yml manual; cota free respeitada)"
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
# v1.1: copy-to-RAM no boot default exige RAM de sobra no QEMU dos gates
# (2.9GB de ISO + 5G de cow: -m 3072 morreria no boot; 7168 é o contrato)
assert_grep "$BY" '-m 7168' "contrato v1.1: build.yml — QEMU do verify com 7168 MB (copytoram=y no default)"
assert_grep "$REPO/scripts/qemu-boot-test.sh" '-m 7168' "contrato v1.1: qemu-boot-test.sh idem (7168 MB)"
AY="$REPO/.github/workflows/agents.yml"
assert_grep "$AY" 'deepseek' "contrato: agents.yml — deepseek presente"
assert_grep "$AY" 'mimo' "contrato: agents.yml — mimo presente"
assert_grep "$AY" 'actions: read' "contrato: agents.yml — permissão de ler runs"
# v1.0.5: o install-gate tem contrato próprio — o grep de entradas do
# grub.cfg casa TAB (o '(linux|initrd) ' com espaço da v1.0.4 devolvia vazio
# = falso negativo; a run #2 da branch diag-install morreu nisso sem o
# bug existir) e o unsquashfs roda com sudo (xattrs security.capability)
DI="$REPO/.github/workflows/verify-install.yml"
assert_grep "$DI" 'workflow_call:' "contrato: verify-install.yml (ex-diag-install) é workflow reutilizável (chamável como gate)"
assert_grep "$DI" 'sudo unsquashfs' "contrato: unsquashfs com sudo (xattrs exigem root — run #1)"
assert_grep "$DI" '\(linux\|initrd\)\[\[:space:\]\]' "contrato: grep de entradas do grub.cfg casa TAB ([[:space:]])"
# v1.1: kernel único BORE — o pre-flight troca o check do linux.preset (E6b
# aposentado) pelo check do dkms nvidia (E11); o [6b/8] roda o MESMO detector
# de vendor do shellprocess_btrfs (unknown esperado no QEMU) e os 4 contratos
# per-rig são greps no YAML que o Calamares real executa
assert_grep "$DI" 'preset stock PRESENTE \(E6b foi aposentado' "contrato v1.1: verify-install rejeita o preset stock (E6b morto)"
assert_grep "$DI" 'updates/dkms/nvidia' "contrato v1.1: verify-install confere o dkms nvidia pré-compilado (E11)"
assert_grep "$DI" '0x10de\) ELITE_GPU=nvidia' "contrato v1.1: detector de vendor do E10 no gate (nvidia)"
assert_grep "$DI" 'pacman -Rdd --noconfirm nvidia-open-dkms' "contrato v1.1: limpeza AMD do E10 no gate"
assert_grep "$DI" 'gpu-detect\.txt' "contrato v1.1: artifact gpu-detect.txt (no lugar do mkinitcpio-stock.log)"
assert_nogrep "$DI" 'mkinitcpio-stock\.log' "contrato v1.1: artifact do kernel stock sumiu do gate"
# FIX #52 (forense das builds #48–#52): o gate verify-install baixava a ISO
# da ÚLTIMA run bem-sucedida (v1.0.4, run #45) — o check antigo confiava em
# GITHUB_EVENT_NAME == workflow_call, que nunca é verdade como env padrão (o
# env reflete o evento da RUN: push/dispatch/tag; workflow_call seta o
# CONTEXTO github.event_name, não o env). 5 builds reprovadas pelo
# linux.preset legítimo da v1.0.4 (kernel duplo daquela era) — produto são,
# gate cego. A fonte da verdade agora é o INPUT explícito.
assert_grep "$BY" 'run_id: \$\{\{ github\.run_id \}\}' \
  "contrato fix #52: build.yml passa a run corrente ao install-gate (a ISO testada é a desta build)"
assert_grep "$DI" 'gh run download "\$RUN_ID"' \
  "contrato fix #52: verify-install baixa o artifact do run_id explícito (input = fonte da verdade)"
assert_nogrep "$DI" 'GITHUB_EVENT_NAME' \
  "contrato fix #52: o env GITHUB_EVENT_NAME não decide mais a fonte da ISO (nunca era workflow_call)"
# ordem de precedência documentada: tag (release manual) > run_id (gate) >
# fallback consciente — o elif do RUN_ID vem DEPOIS do TAG
TAGLINE=$(grep -n 'if \[ -n "\$TAG" \]' "$DI" | head -1 | cut -d: -f1)
RIDLINE=$(grep -n 'elif \[ -n "\$RUN_ID" \]' "$DI" | head -1 | cut -d: -f1)
if [[ -n "${TAGLINE:-}" && -n "${RIDLINE:-}" && "$RIDLINE" -gt "$TAGLINE" ]]; then
  ok "contrato fix #52: precedência tag > run_id > fallback (dispatch manual por último)"
else
  fail "contrato fix #52: precedência tag > run_id" "elif do RUN_ID não está depois do TAG (linha $RIDLINE vs $TAGLINE)"
fi
# workflow_call declara os inputs — sem declaração o input não chega ao
# workflow chamado (era o motivo do RUN_ID vazio nas builds #48–#52).
# Cuidado: o 'inputs:' do workflow_dispatch vem ANTES no arquivo — o que
# vale é o primeiro 'inputs:' DEPOIS da linha do workflow_call.
WCLINE=$(grep -n '^  workflow_call:' "$DI" | head -1 | cut -d: -f1)
WILINE=$(awk -v wc="${WCLINE:-0}" 'NR>wc && /^    inputs:/ {print NR; exit}' "$DI")
if [[ -n "${WCLINE:-}" && -n "${WILINE:-}" && "$WILINE" -gt "$WCLINE" ]]; then
  ok "contrato fix #52: workflow_call declara inputs (run_id chega ao workflow chamado)"
else
  fail "contrato fix #52: inputs do workflow_call" "bloco inputs não está depois de workflow_call (linha $WILINE vs $WCLINE)"
fi

# v1.1→v1.4: brave-origin (release oficial pinado) + pwvucontrol nascem no [elite-local]
assert_grep "$REPO/.ci/build.sh" 'pkgname=brave-origin' "contrato v1.4: build.sh empacota brave-origin (release oficial) → elite-local"
assert_grep "$REPO/.ci/build.sh" 'brave-origin-.*linux-amd64' "contrato v1.4: source do brave-origin = release oficial da Brave"
brsha="$(sed -n '/^pkgname=brave-origin$/,/^EOPKGBUILD$/p' "$REPO/.ci/build.sh" | grep -oE "'[0-9a-f]{64}'" | sed -n '3p' | tr -d "'")"
assert_match "$brsha" '^[0-9a-f]{64}$' "contrato v1.4: sha256 do zip do brave-origin PINADO (64 hex na 3ª posição do source — o bump troca o VALOR, nunca a FORMA; cravar bytes aqui quebraria a suíte a cada bump)"
assert_grep "$REPO/.ci/build.sh" 'aur_build pwvucontrol' "contrato v1.1: build.sh compila pwvucontrol do AUR → elite-local"
# v1.4 (lição da run #57: "install: cannot stat 'brave-origin.sh'"): os
# sources LOCAIS precisam estar no source=() do PKGBUILD E os sha256
# declarados têm que bater com os bytes REAIS dos heredocs — se alguém
# editar o launcher/desktop sem recalcular, o makepkg falha no CI. Este
# contrato quebra ANTES de gastar run.
assert_grep "$REPO/.ci/build.sh" 'source=\(brave-origin\.sh' "contrato v1.4: brave-origin.sh declarado no source=() (makepkg o copia ao srcdir)"
assert_grep "$REPO/.ci/build.sh" 'brave-browser\.desktop' "contrato v1.4: brave-browser.desktop declarado no source=()"
if command -v python3 >/dev/null 2>&1; then
  bo_hashes="$(python3 - "$REPO/.ci/build.sh" << 'PYEOF'
import hashlib, sys
raw = open(sys.argv[1], 'rb').read().decode('utf-8')
for marker in ('EOSH', 'EODESK'):
    key = f"<<'{marker}'\n"
    start = raw.find(key) + len(key)
    end = raw.find(f"\n{marker}\n", start)
    if end < 0:
        print(f"HEREDOC-AUSENTE-{marker}")
        continue
    print(hashlib.sha256(raw[start:end + 1].encode('utf-8')).hexdigest())
PYEOF
)"
  h_sh="$(printf '%s\n' "$bo_hashes" | sed -n '1p')"
  h_desk="$(printf '%s\n' "$bo_hashes" | sed -n '2p')"
  assert_grep "$REPO/.ci/build.sh" "$h_sh" "contrato v1.4: sha256 do brave-origin.sh confere com o heredoc (anti-drift)"
  assert_grep "$REPO/.ci/build.sh" "$h_desk" "contrato v1.4: sha256 do brave-browser.desktop confere com o heredoc (anti-drift)"
else
  skip "contrato v1.4: sha256 dos heredocs" "python3 indisponível"
fi
assert_grep "$REPO/.ci/build.sh" 'base-devel sudo' "contrato v1.1: container prep ganha base-devel+sudo (makepkg do AUR)"

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

# ── 3.K craft-pin v2: fixar apps na dock NATIVA (HOME falso, skel real) ─
#  O craft-pin v2 edita ~/.config/elite/dock-pins (1 ID de .desktop por
#  linha) — nada de JSON/waybar. O juiz: o arquivo resultante, o .bak
#  restaurável, o reload gracioso e o byte-a-byte vs skel.
PINHOME="$WORK/craft-pin-home"
PINSF="$PINHOME/.config/elite/dock-pins"
SKP="$REPO/elite/airootfs/etc/skel/.config/elite/dock-pins"
FIXAPPS="$WORK/fake-data/applications"
pin_reset() {
  rm -rf "$PINHOME" "$WORK/fake-data"; mkdir -p "$PINHOME/.config/elite" "$FIXAPPS"
  cp "$SKP" "$PINSF"
  # os fixtures .desktop vivem NO XDG_DATA_HOME do HOME falso (precedência
  # XDG: o resolve confere o usuário primeiro) — recriados a cada reset
  mkdesk steam.desktop 'Steam' 'steam' steam
  mkdesk discord.desktop 'Discord' 'discord' discord
  mkdesk obs.desktop 'OBS Studio' 'obs' com.obsproject.Studio
}
CP() { env HOME="$PINHOME" XDG_DATA_HOME="$WORK/fake-data" bash "$REPO/elite/airootfs/usr/local/bin/craft-pin" "$@"; }
# fixtures .desktop no XDG_DATA_HOME do usuário falso (precedência XDG: o
# resolve do craft-pin confere o diretório do usuário PRIMEIRO — o teste
# fica determinístico mesmo que o runner tenha desktops do sistema)
mkdesk() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nIcon=%s\n' "$2" "$3" "$4" > "$FIXAPPS/$1"; }

pin_reset
out="$(CP list 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "craft-pin v2: list em fábrica é gracioso (rc 0)" || fail "craft-pin v2: list" "rc $rc — $out"

out="$(CP add steam 2>&1)"
assert_match "$out" 'steam\.desktop fixado' "craft-pin v2: add resolve fuzzy pelo NOME do app (steam → steam.desktop)"
assert_grep "$PINSF" '^steam\.desktop$' "craft-pin v2: pin entra no arquivo (uma linha, um ID)"
assert_file "$(ls -1t "$PINSF".bak.* 2>/dev/null | head -1)" "craft-pin v2: toda mutação grava .bak restaurável (contrato v1.8 vivo)"

out="$(CP add discord 2>&1)"
assert_match "$out" 'discord\.desktop fixado' "craft-pin v2: 2º pin aceito"
out="$(CP add OBS 2>&1)"
assert_match "$out" 'obs\.desktop fixado' "craft-pin v2: add casa por Nome com espaço (OBS → obs.desktop)"
assert_grep "$PINSF" '^obs\.desktop$' "craft-pin v2: 3º pin no arquivo"

rc=0
out="$(CP add steam 2>&1)" || rc=$?
assert_match "$out" 'já está fixado' "craft-pin v2: duplicata rejeitada (rc ≠ 0)"
# E36 — o contrato antigo JURAVA 'rc ≠ 0' e só lia stdout (o código saía 0
# e a peça passava igual: a mentira era dupla). O rc agora é PROVADO —
# e o picker com rc≠0 + mensagem 'já está fixado' dá toast honesto.
assert_eq "$rc" "1" "E36: duplicata NÃO é sucesso (rc=1 PROVADO — o picker nunca mais notifica 'fixado' quando nada mudou)"
out="$(CP add aplicativo-que-nao-existe-xyz 2>&1)" || true
assert_match "$out" 'nenhum app casa' "craft-pin v2: nome desconhecido recusado com mensagem clara"

assert_match "$(CP list)" 'steam\.desktop' "craft-pin v2: list mostra os pins"
assert_match "$(CP list)" 'obs\.desktop' "craft-pin v2: list mostra o 3º"

CP rm discord >/dev/null
if grep -qxF 'discord.desktop' "$PINSF"; then
  fail "craft-pin v2: rm do meio" "discord ainda presente"
else
  ok "craft-pin v2: rm do meio remove SÓ a linha do app"
fi
CP rm steam >/dev/null; CP rm obs >/dev/null
if diff -q "$PINSF" "$SKP" >/dev/null; then ok "craft-pin v2: todos removidos → dock-pins == skel BYTE a BYTE"; else fail "craft-pin v2: pristino" "dock-pins divergiu do skel após add/rm de tudo"; fi

CP add steam >/dev/null
CP restore >/dev/null
if grep -qxF 'steam.desktop' "$PINSF"; then
  fail "craft-pin v2: restore" "steam ainda presente após restore"
else
  ok "craft-pin v2: restore devolve o estado anterior à última alteração"
fi
out="$(CP restore 2>&1)" || true
assert_match "$out" 'sem backup' "craft-pin v2: restore sem histórico recusa (rc 1)"

# harness: a função REAL do craft-pin extraída por profundidade de chaves
# (mesmo idioma do 3.L abaixo) — craft-dock AUSENTE no ambiente de teste é a
# classe 'reload sem dock': o || true interno tem que devolver rc 0 (a lição
# da v2.3.3: o heredoc antigo injetava $(declare -f) DENTRO de aspas simples
# — a função nunca entrava no shell interno e o ok decorativo não via nada)
RLBIN="$WORK/reload-run.sh"
{
  echo '#!/usr/bin/env bash'
  awk '/^reload_dock\(\)/{print; d=1; next}
       d{print; o=gsub(/{/,"{"); c=gsub(/}/,"}"); d+=o-c; if(d<=0) exit}' \
    "$REPO/elite/airootfs/usr/local/bin/craft-pin"
  printf 'PINS="%s"\nreload_dock\n' "$PINSF"
} > "$RLBIN"
out="$(env HOME="$PINHOME" bash "$RLBIN" 2>&1)"
rc=$?
assert_eq "$rc" "0" "craft-pin v2: reload sem dock é gracioso (rc 0 — função REAL extraída, craft-dock ausente)"

# ── 3.L elite_inject_bumped (ELITE-BUMP — build #49: pkgrel 3 componentes) ─
#  A função REAL do .ci/build.sh, extraída por fidelidade (como o extract.sh
#  faz com o elite-tune), rodando isolada do host: unshare -rm com tmpfs em
#  /var quando o kernel permite (dev machine), ou DIRETO quando já é root no
#  container efêmero do CI (mesma detecção do ns-body da fase 4 — o runner
#  GitHub bloqueia userns+mountns: 'unshare: Operation not permitted',
#  pego na Test Suite #26). vercmp/bsdtar/runuser/makepkg são mockados na
#  frente do PATH — o makepkg-mock valida o pkgrel com a MESMA regra do
#  real ('integer[.integer]'): foi exatamente "pkgrel must be of the form
#  'integer[.integer]', not 1.1.1" que derrubou a build #49 (o repack
#  falhava, caía no cp clássico que não satisfaz o resolve, 6 rounds
#  quebrados, abort sem ISO).
if unshare -rm true 2>/dev/null; then
  BUMP_ISOL=(unshare -rm); BUMP_MODE=ns   # dev machine: escritas evaporam com o ns
elif [[ $EUID -eq 0 ]]; then
  BUMP_ISOL=();          BUMP_MODE=root  # container do CI: root direto, /var do job
else
  BUMP_MODE=skip
fi
if [[ "$BUMP_MODE" != skip ]]; then
  # harness: função real + driver (tmpfs em /var como o ns-body faz).
  # extração por PROFUNDIDADE DE CHAVES (awk): o sed /^}$/ cortaria no '}'
  # do package() DENTRO do heredoc do PKGBUILD — função truncada = script
  # quebrado (here-document delimited by end-of-file).
  BUMPBIN="$WORK/bump-run.sh"
  {
    echo '#!/usr/bin/env bash'
    echo 'say() { printf "%s\n" "$*"; }'
    awk '/^elite_inject_bumped\(\)/{print; d=1; next}
         d{print; o=gsub(/{/,"{"); c=gsub(/}/,"}"); d+=o-c; if(d<=0) exit}' \
      "$REPO/.ci/build.sh"
    printf '%s\n' \
      'mount -t tmpfs tmpfs /var 2>/dev/null || true' \
      'rm -rf /tmp/elite-bump' \
      'mkdir -p /var/cache/elite-local' \
      'elite_inject_bumped "$1" "$2"' \
      'echo "RC=$?"' \
      'ls -1 /var/cache/elite-local/ 2>/dev/null | sed "s/^/CACHE /"' \
      'cat /tmp/elite-bump/*/PKGBUILD 2>/dev/null | sed "s/^/PKGBUILD /"' \
      'rm -rf /tmp/elite-bump' \
      'exit 0'
  } > "$BUMPBIN"
  chmod +x "$BUMPBIN"

  # mocks: vercmp (semântica ver-rel p/ os casos), bsdtar (no-op), runuser
  # (roda o -c payload) e makepkg (valida pkgrel como o real + "compila")
  MB="$WORK/mocks-bump"; mkdir -p "$MB"
  cat > "$MB/vercmp" <<'EOF'
#!/usr/bin/env bash
# mock vercmp — fiel p/ ver igual (decide no rel numérico) e ver diferente
av=${1%-*}; arel=${1##*-}; bv=${2%-*}; brel=${2##*-}
if [[ "$av" != "$bv" ]]; then [[ "$av" > "$bv" ]] && echo 1 || echo -1; exit 0; fi
x=(${arel//./ }); y=(${brel//./ }); i=0
while :; do
  xv=${x[i]:-0}; yv=${y[i]:-0}
  (( xv > yv )) && { echo 1; exit 0; }
  (( xv < yv )) && { echo -1; exit 0; }
  [[ -z ${x[i]:-} && -z ${y[i]:-} ]] && { echo 0; exit 0; }
  i=$((i+1))
done
EOF
  printf '#!/usr/bin/env bash\nexit 0\n' > "$MB/bsdtar"
  cat > "$MB/runuser" <<'EOF'
#!/usr/bin/env bash
cmd=""; prev=""
for a in "$@"; do [[ "$prev" == "-c" ]] && cmd="$a"; prev="$a"; done
exec bash -c "$cmd"
EOF
  cat > "$MB/makepkg" <<'EOF'
#!/usr/bin/env bash
# mock makepkg — valida o PKGBUILD como o real e "compila" o pacote
name=$(sed -n 's/^pkgname=//p' PKGBUILD)
ver=$(sed -n  's/^pkgver=//p'  PKGBUILD)
rel=$(sed -n  's/^pkgrel=//p'  PKGBUILD)
arch=$(sed -nE 's/^arch=\((.*)\)$/\1/p' PKGBUILD)
if [[ ! "$rel" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "==> ERROR: pkgrel must be of the form 'integer[.integer]', not $rel." >&2
  exit 1
fi
touch "$name-$ver-$rel-$arch.pkg.tar.zst"
EOF
  chmod +x "$MB"/*
  run_bump() {
    if (( ${#BUMP_ISOL[@]} )); then
      PATH="$MB:$PATH" "${BUMP_ISOL[@]}" bash "$BUMPBIN" "$1" "$2"
    else
      PATH="$MB:$PATH" bash "$BUMPBIN" "$1" "$2"
    fi
  }

  # baseline dummy (o bsdtar é mockado; o cp lê o arquivo real)
  BL="$WORK/bump-baseline"; mkdir -p "$BL"
  touch "$BL/libyuv-r2921+644251f25-1-x86_64.pkg.tar.zst" \
        "$BL/libcdio-paranoia-10.2+2.0.2-3-x86_64.pkg.tar.zst" \
        "$BL/demo-2.0-2-x86_64.pkg.tar.zst"

  # caso #49: libyuv 1.1 → bump DEVE gerar pkgrel 2 (não 1.1.1 — inválido)
  out="$(run_bump "libyuv-r2921+644251f25-1.1-x86_64_v3.pkg.tar.zst" "$BL/libyuv-r2921+644251f25-1-x86_64.pkg.tar.zst")"
  printf '%s\n' "$out" > "$WORK/bump49.out"
  assert_match "$out" 'ELITE-BUMP libyuv r2921\+644251f25-1 → r2921\+644251f25-2' \
    "bump #49: libyuv 1.1 → major+1 = 2 (makepkg-mock aceita; o 1.1.1 da build #49 morreria aqui)"
  assert_match "$out" 'CACHE libyuv-r2921\+644251f25-2-x86_64\.pkg\.tar\.zst' \
    "bump #49: pacote r2921+644251f25-2 no elite-local (vence o resolve contra 1.1)"
  assert_grep "$WORK/bump49.out" '^PKGBUILD pkgrel=2$' "bump #49: pkgrel=2 no PKGBUILD (integer — formato makepkg)"
  if grep -q 'not 1.1.1' <<<"$out"; then
    fail "bump #49: regressão" "makepkg-mock rejeitou o pkgrel (3 componentes voltaram?)"
  else
    ok "bump #49: makepkg-mock VALIDOU o pkgrel (sem 'not 1.1.1')"
  fi

  # caso #47: libcdio-paranoia 3.1 → bump major+1 = 4 (não 3.1.1)
  out="$(run_bump "libcdio-paranoia-10.2+2.0.2-3.1-x86_64_v3.pkg.tar.zst" "$BL/libcdio-paranoia-10.2+2.0.2-3-x86_64.pkg.tar.zst")"
  printf '%s\n' "$out" > "$WORK/bump47.out"
  assert_match "$out" 'CACHE libcdio-paranoia-10\.2\+2\.0\.2-4-x86_64\.pkg\.tar\.zst' \
    "bump #47: libcdio-paranoia 3.1 → 4 no elite-local"
  assert_grep "$WORK/bump47.out" '^PKGBUILD pkgrel=4$' "bump #47: pkgrel=4 (o 3.1.1 do design original era inválido)"

  # vercmp do mock: 2 > 1.1 e 4 > 3.1 (a matemática que faz o resolve vencer)
  v() { PATH="$MB:$PATH" vercmp "$1" "$2"; }
  assert_eq "$(v 'r2921+644251f25-2' 'r2921+644251f25-1.1')" "1" "bump: vercmp(2, 1.1) = 1 (elite-local vence o resolve)"
  assert_eq "$(v '10.2+2.0.2-4' '10.2+2.0.2-3.1')" "1" "bump: vercmp(4, 3.1) = 1"

  # caminho clássico: baseline >= quebrada → ELITE-INJECT com cp puro
  out="$(run_bump "demo-2.0-1.1-x86_64_v3.pkg.tar.zst" "$BL/demo-2.0-2-x86_64.pkg.tar.zst")"
  assert_match "$out" 'ELITE-INJECT demo-2\.0-2-x86_64\.pkg\.tar\.zst' \
    "bump clássico: baseline >= quebrada → injeção simples (cp)"
  assert_match "$out" 'CACHE demo-2\.0-2-x86_64\.pkg\.tar\.zst' \
    "bump clássico: arquivo do baseline intacto no elite-local"
  if grep -q 'PKGBUILD' <<<"$out"; then
    fail "bump clássico: sem repack" "PKGBUILD gerado no caminho clássico (não deveria)"
  else
    ok "bump clássico: nenhum PKGBUILD (repack só quando baseline é mais velha)"
  fi

  # rel fora do formato (defesa honesta) → cp clássico, sem crash
  out="$(run_bump "demo-2.0-3+x1-x86_64_v3.pkg.tar.zst" "$BL/demo-2.0-2-x86_64.pkg.tar.zst")"
  assert_match "$out" 'fora do formato' "bump: rel exótica → cp clássico honesto (sem aritmética cega)"
else
  skip "3.L elite_inject_bumped" "sem root nem unshare -rm (contratos estáticos abaixo valem)"
fi

# contratos estáticos (valem SEM unshare): major+1 no lugar do .1 de 3 componentes
assert_grep "$REPO/.ci/build.sh" 'newrel=\$\(\( brmaj \+ 1 \)\)' \
  "contrato bump: newrel = major da quebrada + 1 (build #49)"
assert_nogrep "$REPO/.ci/build.sh" 'newrel="\$\{nb_verrel##\*-\}\.1"' \
  "contrato bump: a forma '3.1→3.1.1' (pkgrel inválido, makepkg rejeita) não existe mais"
# contratos da forense #50: a baseline tem que SER o pacote-alvo, com nome real
assert_grep "$REPO/.ci/build.sh" "awk -F/ -v pfx=\"\\\$base-\" 'index\(\\\$NF, pfx\) == 1'" \
  "contrato bump: fu = URL do PRÓPRIO alvo (build #50: head -1 cego baixava a 1ª DEP — tzdata virou 'baseline' de libyuv)"
assert_grep "$REPO/.ci/build.sh" '/tmp/elite-baseline/\$\{fu##\*/\}' \
  "contrato bump: baseline baixada com o NOME REAL do pacote (versão preservada p/ o parse — 'elite-2' nunca mais)"
assert_grep "$REPO/.ci/build.sh" 'options=\(!debug\)' \
  "contrato bump: PKGBUILD do repack com options=(!debug) (sem -debug espúrio no elite-local)"

# ════════════════════════════════════════════════════════════════════
# v1.5.2 — LIMPEZA + RELAY DOS AGENTES + FORENSE DE LOG + UNITS FALHADAS
# Diretriz do dono pós-v1.5: "os agentes do repositório devem analisar
# justamente os logs minuciosamente; esses erros não podem passar ou ser
# tratados como algo normal". Três buracos sistêmicos fechados de uma vez:
#   (a) build VERDE com erro silencioso no log — a v1.4 saiu sem
#       cachyos-keyring com 5 classes fatais ESCRITAS no log;
#   (b) relay-agents engolia o dispatch quebrado — gh sem --repo caía em
#       "fatal: not a git repository" e o if/else abafava: ZERO auditorias
#       desde 20/out;
#   (c) units em crash-loop passavam pelo gate de boot — fg-booster
#       falhava 17× no serial da v1.5 (debloat v4.2 varreu o xdotool) e
#       'Startup finished' não enxerga units falhadas.
# ════════════════════════════════════════════════════════════════════

# (a) forense de log plugada na build: captura (tee) + gate
assert_grep "$BY" 'set -o pipefail' "contrato v1.5.2: build com pipefail (docker quebra a pipe, não o tee)"
assert_grep "$BY" 'bash \.ci/build\.sh 2>&1 \| tee build-output\.log' \
  "contrato v1.5.2: log da build capturado em build-output.log (evidência, não ruído)"
assert_grep "$BY" 'scripts/log-forensics\.sh build-output\.log' \
  "contrato v1.5.2: gate de forense roda no job de build (erro silencioso = run vermelha)"

# (b) v2.1 — auditoria por IA é SOB DEMANDA: o relay automático saiu do
# build (queimava a cota free do Token Harbor em toda build — inclusive
# cancelada — até o 429 em massa). A auditoria agora vive no agents.yml
# manual, com relatório de FALHA assinado (fim dos artifacts 0 MB).
assert_nogrep "$BY" 'relay-agents' \
  "contrato v2.1: NENHUM job de relay automático no build (cota do Token Harbor respeitada)"
assert_grep "$REPO/.github/workflows/agents.yml" 'workflow_dispatch' \
  "contrato v2.1: auditoria de IA sob demanda (agents.yml manual — deepseek/mimo com contexto ci:<run_id>)"
assert_grep "$REPO/agents/run.ts" 'RELATÓRIO DE FALHA' \
  "contrato v2.1: falha do agente gera relatório ASSINADO antes do exit (artifacts 0 MB extintos)"
assert_nogrep "$BY" 'não derruba a build' \
  "contrato v1.5.2: o abafador 'não derruba a build' não existe mais no build.yml"

# (c) gates de boot caçam units em failed (live E instalado)
assert_grep "$BY" "Failed with result" \
  "contrato v1.5.2: gate do live varre 'Failed with result' (crash-loop caçado)"
assert_grep "$DI" "Failed with result" \
  "contrato v1.5.2: gate do instalado varra 'Failed with result' idem"

# fg-booster — v2.2: EXTINTO na fusão dos boosters. A história v1.5.2
# (crash-loop 17× do xdotool varrido) virou REGRA PERMANENTE: nenhum
# unit/binário/pacote daquela cadeia pode voltar, e a cura da causa-raiz
# (units extintas + teto de restart onde ainda existe unit) segue.
FB="$REPO/elite/airootfs/usr/local/bin/fg-booster"
FBU="$REPO/elite/airootfs/etc/systemd/system/fg-booster.service"
assert_nofile "$FB" "contrato v2.2: binário fg-booster EXTINTO (fusão dos boosters — ananicy-cpp é o único daemon)"
assert_nofile "$FBU" "contrato v2.2: unit fg-booster.service EXTINTA idem"
assert_nofile "$REPO/elite/airootfs/etc/systemd/system/fg-boost.slice" "contrato v2.2: fg-boost.slice EXTINTO idem"
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'StartLimitIntervalSec=120.*fg|fg-booster.service$' \
  "contrato v2.2: elite-tune sem habilitação do fg-booster (o padrão anti-crash-loop segue nos contratos de gate)"

# ── 3.M forense de log — teste FUNCIONAL com fixtures (o gate é código,
# código se testa de verdade: benigno passa, fatal barra, condicional
# discrimina; a validação de campo foi contra os logs REAIS das runs
# 39864937531 [v1.5 → limpo] e 39804335535 [v1.4 → 5 fatais]) ─────────
LF="$REPO/scripts/log-forensics.sh"
FW="$WORK/forense"; rm -rf "$FW"; mkdir -p "$FW"

# fixture 1: benigno completo (a assinatura do log REAL da v1.5)
cat > "$FW/benign.log" <<'EOF'
==> Construindo repo local [elite-local]
Warning: Problem (retrying all errors). Retrying in 3 seconds.
curl: (22) The requested URL returned error: 404
error: failed to commit transaction (error invoking external downloader)
==>   libyuv quebrado nos 2 mirrors → baseline Arch injetado no [elite-local]
==>   ELITE-BUMP libyuv r2921+644251f25-1 → r2921+644251f25-2
/usr/bin/grub-editenv: error: failed to get canonical path of `//boot/grub'.
/usr/sbin/grub-mkconfig: line 271: /boot/grub/grub.cfg.new: No such file or directory
error: command failed to execute correctly
/usr/lib/tmpfiles.d/journal-nocow.conf:26: Failed to resolve specifier: uninitialized /etc/ detected, skipping.
gpg: Note: third-party key signatures using the SHA1 algorithm are rejected
Error while writing index for `/usr/bin/pwvucontrol': No debugging symbols
==> WARNING: Skipping verification of source file PGP signatures.
==> WARNING: Possibly missing firmware for module: 'ast'
==> WARNING: /mnt/iso-work/x86_64/airootfs is not a mountpoint. This may have undesirable side effects.
Cannot start unit with --now when systemd is not running, ignoring.
Wrap blueprint-compiler.wrap type git not found: blueprint-compiler
==> Done! customize_airootfs.sh run successfully.
EOF
if bash "$LF" "$FW/benign.log" >/dev/null 2>&1; then
  ok "forense funcional: log benigno (assinatura da v1.5 real) → exit 0"
else
  fail "forense funcional: log benigno" "scanner reprovou log limpo (falso positivo!)"
fi

# fixture 2: os 5 fatais REAIS da v1.4 (log da run 39804335535, build verde)
cat > "$FW/fatal-v14.log" <<'EOF'
==> E2: instalando keyring
error: target not found: cachyos-keyring
error: target not found: cachyos-v3-mirrorlist
error: could not determine root mount point /
error: not enough free disk space
error: failed to commit transaction (not enough free disk space)
error: cachyos-extra-v3: signature from "CachyOS <admin@cachyos.org>" is invalid
error: failed to synchronize all databases (unexpected error)
E11: módulos nvidia presentes — regenerando initramfs
EOF
if bash "$LF" "$FW/fatal-v14.log" >/dev/null 2>&1; then
  fail "forense funcional: log da v1.4 (5 fatais reais)" "scanner APROVOU o log que queimou o burn test (falso negativo!)"
else
  ok "forense funcional: log da v1.4 → exit 1 (os 5 fatais da história, barrados)"
fi

# fixture 3: downloader SEM recuperação (mirror quebrado sem baseline)
printf '%s\n' 'error: failed to commit transaction (error invoking external downloader)' > "$FW/dl-sem-cura.log"
if bash "$LF" "$FW/dl-sem-cura.log" >/dev/null 2>&1; then
  fail "forense funcional: downloader sem recuperação" "404 de mirror sem baseline passou (deveria ser fatal)"
else
  ok "forense funcional: downloader sem recuperação → exit 1 (fatal sem a cura no log)"
fi

# fixture 4: 'command failed' FORA de contexto grub (hook abortado real)
printf '%s\n' 'installing some-package...' 'error: command failed to execute correctly' > "$FW/hook-solto.log"
if bash "$LF" "$FW/hook-solto.log" >/dev/null 2>&1; then
  fail "forense funcional: hook fora de contexto grub" "hook abortado sem grub por perto passou (deveria ser fatal)"
else
  ok "forense funcional: hook fora de contexto grub → exit 1 (a whitelist tem fronteira)"
fi

# fixture 5: keyring silencioso (a assinatura da dor do dono)
printf '%s\n' 'error: cachyos-keyring: signature from "CachyOS" is unknown trust' > "$FW/keyring.log"
if bash "$LF" "$FW/keyring.log" >/dev/null 2>&1; then
  fail "forense funcional: unknown trust" "a assinatura do burn test do dono passou (deveria ser fatal)"
else
  ok "forense funcional: 'is unknown trust' → exit 1 (a dor do burn test, caçada)"
fi


# ── 3.N v2.10.5 — AUDITORIA DE SIMULAÇÕES: as curas da ilha, provadas ──

# forense fixture 6: 'failed to synchronize' CURADO pelo re-sync do
# preflight (a classe #116 inteira — round transiente → cache fechou)
cat > "$FW/sync-curado.log" <<'FIXLOG'
Preflight round 1/3: -Syw de 900 alvos (só download; nada é instalado)
error: failed to synchronize all databases (unexpected error)
Preflight round 1: -Syw falhou — stderr do próprio -Syw (causa real; #19 escondeu isto aqui):
Preflight: cache completo — pacstrap offline dali em diante
==> Done! customize_airootfs.sh run successfully.
FIXLOG
if bash "$LF" "$FW/sync-curado.log" >/dev/null 2>&1; then
  ok "forense funcional: synchronize curado pelo re-sync (janela #116) → exit 0"
else
  fail "forense funcional: synchronize curado" "build SÁDIO reprovado — o falso positivo da classe #116 continua vivo"
fi

# forense fixture 7: 'failed to synchronize' SEM cura → segue FATAL
printf '%s
' 'error: failed to synchronize all databases (unexpected error)' > "$FW/sync-morto.log"
if bash "$LF" "$FW/sync-morto.log" >/dev/null 2>&1; then
  fail "forense funcional: synchronize sem recuperação" "pacman -Sy morto sem 'cache completo' passou (deveria ser fatal)"
else
  ok "forense funcional: synchronize sem cura → exit 1 (a condicional não mascara doença)"
fi

# forense fixture 8: pacote corrompido no round 1 CURADO pelo re-download
# (a 2ª build v2.10.5 provou em campo: checksum ruim de mirror, round 2
# fechou o cache, ISO sã com sha256 — FATAL incondicional era falso positivo)
cat > "$FW/corr-curado.log" <<'FIXLOG'
==> Preflight round 1/3: -Syw de 235 alvos (só download; nada é instalado)
:: File /var/cache/pacman/pkg/wlrctl-0.2.2-1-x86_64.pkg.tar.zst is corrupted (invalid or corrupted package (checksum)).
error: failed to commit transaction (invalid or corrupted package)
==> Preflight round 2/3: -Syw de 235 alvos (só download; nada é instalado)
==> Preflight: cache completo — pacstrap offline dali em diante
==> Done! customize_airootfs.sh run successfully.
FIXLOG
if bash "$LF" "$FW/corr-curado.log" >/dev/null 2>&1; then
  ok "forense funcional: corrupção de download curada pelo re-download (cache completo) → exit 0"
else
  fail "forense funcional: corrupção curada" "build SÁDIO reprovado — a 2ª build v2.10.5 teria continuado reprovada"
fi

# forense fixture 9: corrupção SEM cura → segue FATAL (transação morta)
printf '%s
' 'error: failed to commit transaction (invalid or corrupted package)' > "$FW/corr-morto.log"
if bash "$LF" "$FW/corr-morto.log" >/dev/null 2>&1; then
  fail "forense funcional: corrupção sem recuperação" "transação abortada por corrupção sem cache fechado passou (deveria ser fatal)"
else
  ok "forense funcional: corrupção sem cura → exit 1 (a transação morta continua caçada)"
fi

# v2.10.6 — AS 4 REGRAS FATAIS INCONDICIONAIS GANHAM FIXTURE + o ramo
# downloader/'cache completo' exercitado (a Rodada 2 provou: 4 regras
# FATAIS com ZERO fixtures nos dois sentidos — qualquer regex falso-
# positivo novo derrubaria build sã sem a suíte perceber; a lição
# #116/#122 exige ciência nas DUAS direções):
# forense fixture 10: keyring marginal (FATAL incondicional — sem fixture até hoje)
printf '%s
' 'gpg: key CACHYOS: The key is marginally trusted' > "$FW/marginal.log"
if bash "$LF" "$FW/marginal.log" >/dev/null 2>&1; then
  fail "forense funcional: 'is marginally trusted'" "keyring marginal passou (deveria ser fatal — regra sem fixture era cega)"
else
  ok "forense funcional: 'is marginally trusted' → exit 1 (fatal incondicional agora com fixture)"
fi
# forense fixture 11: conflito de dependências (transação abortada)
printf '%s
' 'error: failed to prepare transaction (conflicting dependencies)' > "$FW/conflict.log"
if bash "$LF" "$FW/conflict.log" >/dev/null 2>&1; then
  fail "forense funcional: 'conflicting dependencies'" "conflito de dependências passou (deveria ser fatal — regra sem fixture era cega)"
else
  ok "forense funcional: 'conflicting dependencies' → exit 1 (fatal incondicional agora com fixture)"
fi
# forense fixture 12: pacstrap morto (a string literal do pacman no new root)
printf '%s
' 'error: failed to install packages to new root' > "$FW/pacstrap.log"
if bash "$LF" "$FW/pacstrap.log" >/dev/null 2>&1; then
  fail "forense funcional: 'failed to install packages'" "pacstrap morto passou (deveria ser fatal — a regra que caça o rootfs incompleto era cega)"
else
  ok "forense funcional: 'failed to install packages' → exit 1 (o rootfs incompleto fica caçado, agora com fixture)"
fi
# forense fixture 13: disco REAL cheio (distinto do falso do mtab)
printf '%s
' 'error: cannot write to /var/cache/pacman/pkg/x.pkg.tar.zst: No space left on device' > "$FW/diskfull.log"
if bash "$LF" "$FW/diskfull.log" >/dev/null 2>&1; then
  fail "forense funcional: 'No space left on device'" "disco real cheio passou (deveria ser fatal — regra sem fixture era cega)"
else
  ok "forense funcional: 'No space left on device' → exit 1 (o disco cheio REAL fica caçado, agora com fixture)"
fi
# forense fixture 14: downloader CURADO só pelo 'cache completo' (o ramo
# v2.11 do condicional nunca tinha sido exercitado — só o do ELITE-BUMP tinha)
cat > "$FW/dl-cache-curado.log" <<'FIXLOG'
==> Preflight round 1/3: -Syw de 900 alvos (só download; nada é instalado)
error: failed to commit transaction (error invoking external downloader)
==> Preflight round 2/3: -Syw de 900 alvos (só download; nada é instalado)
==> Preflight: cache completo — pacstrap offline dali em diante
==> Done! customize_airootfs.sh run successfully.
FIXLOG
if bash "$LF" "$FW/dl-cache-curado.log" >/dev/null 2>&1; then
  ok "forense funcional: downloader curado pelo re-sync (SEM baseline — o ramo 'cache completo' provado nos DOIS sentidos) → exit 0"
else
  fail "forense funcional: downloader curado por cache completo" "build SÁDIO reprovado — o ramo v2.11 do condicional continua sem ciência"
fi

# veredito: fase morta (linha ausente no summary) é NO-GO — o GO com
# 4/5 peças morreu (fase morta não escreve linha e o veredito celebrava)
VDW="$WORK/verdict-missing"; rm -rf "$VDW"; mkdir -p "$VDW"
printf '1\tA MESA\t26\t0\t0\n2\tESTATICA\t284\t0\t0\n3\tUNIDADE\t144\t0\t0\n4\tCADEIA\t1240\t0\t0\n' > "$VDW/summary.txt"
if ELITE_TESTS_WORK="$VDW" bash "$REPO/tests/phases/60-verdict.sh" >/dev/null 2>&1; then
  fail "verdict: fase ausente é NO-GO" "summary sem a fase 50-release recebeu GO — a imagem incompleta passou por completa"
else
  ok "verdict: summary sem a fase 50-release → NO-GO (fase morta não celebra)"
fi
VDW2="$WORK/verdict-full"; rm -rf "$VDW2"; mkdir -p "$VDW2"
for ph in 1 2 3 4 5; do
  printf '%s\tfase\t10\t0\t0\n' "$ph" >> "$VDW2/summary.txt"
done
if ELITE_TESTS_WORK="$VDW2" bash "$REPO/tests/phases/60-verdict.sh" >/dev/null 2>&1; then
  ok "verdict: 5 fases na mesa, zero falhas → GO (a lei não bloqueou o bom)"
else
  fail "verdict: 5 fases → GO" "veredito reprovou imagem completa — a lei apertou demais"
fi

# craft-bat: sem bateria = mensagem amigável ALCANÇÁVEL (o set -e+grep
# matava calado — o código morto da era upower). Em máquina COM bateria
# o teste cede (a prova pertence ao CI sem /sys/class/power_supply).
if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
  skip "craft-bat: mensagem amigável sem bateria" "este host TEM bateria — a prova roda no CI"
else
  out="$(bash "$REPO/elite/airootfs/usr/local/bin/craft-bat" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q 'nenhuma bateria encontrada' <<<"$out"; then
    ok "craft-bat: sem bateria → mensagem amigável + exit 1 (o código morto respondeu)"
  else
    fail "craft-bat: sem bateria" "esperado exit 1 + mensagem; obtido rc=$rc out='$out'"
  fi
fi

# ── v2.10.9 — O CONTRATO DO CICLO (systemd-analyze na suíte, para sempre) ──
# O rig (dump d33o L403) provou que um ordering cycle envolvendo
# firstboot+graphical+multi-user APAGA o job do firstboot no boot — e o
# systemd o apaga calado (INFO): journal vazio, marker ausente, doença
# silenciosa. O sandbox reproduziu o Wants= do symlink como INERTE para
# ordenação (a aresta exata do rig nunca foi nomeada — o dump não capturou
# drop-ins do rig), então a lei aqui é DUPLA: (1) a árvore shimada do repo
# (unit + symlink graphical) verifica SEM ciclo; (2) o próprio harness se
# prova com um controle positivo (a After=b + b After=a) — um
# systemd-analyze que não vê o ciclo do controle não pode absolver ninguém.
if ! command -v systemd-analyze >/dev/null 2>&1; then
  skip "contrato do ciclo: systemd-analyze ausente" "host sem systemd — o contrato roda no CI (ubuntu tem systemd 2xx)"
else
  CW="$WORK/cycle-contract"; rm -rf "$CW"; mkdir -p "$CW/etc/systemd/system/graphical.target.wants"
  cp "$REPO/elite/airootfs/etc/systemd/system/elite-firstboot.service" "$CW/etc/systemd/system/"
  chmod -x "$CW/etc/systemd/system/elite-firstboot.service"
  ln -s ../elite-firstboot.service "$CW/etc/systemd/system/graphical.target.wants/elite-firstboot.service"

  # controle positivo: o harness TEM que flagrar o ciclo canônico
  mkdir -p "$CW/ctrl"
  printf '[Unit]\nDescription=A\nAfter=b.service\n[Service]\nType=oneshot\nExecStart=/bin/true\n' > "$CW/ctrl/a.service"
  printf '[Unit]\nDescription=B\nAfter=a.service\n[Service]\nType=oneshot\nExecStart=/bin/true\n' > "$CW/ctrl/b.service"
  ctrlout="$(SYSTEMD_UNIT_PATH="$CW/ctrl:/usr/lib/systemd/system" systemd-analyze verify "$CW/ctrl/a.service" "$CW/ctrl/b.service" 2>&1 || true)"
  if grep -qiE 'ordering cycle|cyclic' <<<"$ctrlout"; then
    ok "contrato do ciclo: controle positivo DETETADO (o harness vê cycle canônico — pode julgar)"
  else
    skip "contrato do ciclo: controle positivo não flagrado" "systemd-analyze deste host não julga ordenação — absolver aqui seria fé"
  fi

  # a árvore da cura: transação de boot (multi-user + graphical) com o
  # firstboot habilitado SÓ no graphical — ciclo AQUI é doença eterna
  treeout="$(SYSTEMD_UNIT_PATH="$CW/etc/systemd/system:/usr/lib/systemd/system" systemd-analyze verify --recursive-errors=no multi-user.target graphical.target 2>&1 || true)"
  if grep -qiE 'ordering cycle|cyclic' <<<"$treeout"; then
    fail "contrato do ciclo: transação de boot SEM cycle" "ciclo detectado na árvore shimada: $(grep -iE 'ordering cycle|cyclic' <<<"$treeout" | head -2)"
  else
    ok "contrato do ciclo: multi-user+graphical+firstboot(graphical.wants) — zero cycle (a ponte do rig morreu pra sempre)"
  fi
fi

# ── 3.Z craft-update v2 (E32): reboot EXATO, ISO nova, offline-safe ─────
# Cenas com mocks CENÁRICOS próprios (dir à parte — o pacman compartilhado
# dos irmãos NÃO pode vazar para cá, nem o meu para eles):
CU_BIN="$REPO/elite/airootfs/usr/local/bin/craft-update"
mkdir -p "$WORK/mock-cu"
cat > "$WORK/mock-cu/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
cat > "$WORK/mock-cu/pacman" <<'EOF'
#!/usr/bin/env bash
# mock pacman do craft-update: -Q lê $MOCK_DIR/kv; -Syu grava $NEW_KV
ST="${MOCK_DIR:?}"; mkdir -p "$ST"; [ -f "$ST/kv" ] || printf '0.0.0-1\n' > "$ST/kv"
case "$1" in
  -Q)   printf 'linux-cachyos-bore %s\n' "$(cat "$ST/kv")" ;;
  -Syu) printf '%s\n' "${NEW_KV:-0.0.0-1}" > "$ST/kv" ;;
  *)    exit 0 ;;
esac
EOF
cat > "$WORK/mock-cu/curl" <<'EOF'
#!/usr/bin/env bash
[[ -n "${CURL_FAIL:-}" ]] && exit 1
printf '%s' "${CURL_JSON:-}"
EOF
chmod +x "$WORK/mock-cu/"*
cu_reset() {
    mkdir -p "$WORK/state-cu"
    printf '1.0.0-1\n'    > "$WORK/state-cu/kv"
    printf '%s\n' "${1:-v2.10.19}" > "$WORK/state-cu/vmark"
}
cu_run() { # envs como args; saída no stdout, rc no $?
    (
        export PATH="$WORK/mock-cu:$PATH"
        export MOCK_DIR="$WORK/state-cu"
        export ELITE_VERSION_MARKER="$WORK/state-cu/vmark"
        # SC2163: 'export "$@"' lê como exportar '@' — "${e?}" é a forma
        # documentada p/ export dinâmico (o ? garante não-vazio de quebra)
        local e
        for e in "$@"; do export "${e?}"; done
        bash "$CU_BIN"
    )
}
cu_reset
# o JSON do fixture é FIEL ao formato real da API: "tag_name" em linha
# própria e INDENTADA (o sed do craft-update casa ^ *\"tag_name\" — um
# JSON de uma linha com '{' na frente NUNCA casa, e não deveria)
outA="$(cu_run NEW_KV=2.0.0-1 CURL_JSON=$'{\n  "url": "https://api.github.com/x",\n  "tag_name": "v2.10.20"\n}\n' 2>&1)"; rcA=$?
assert_eq "$rcA" "0" "E32: craft-update termina 0 na cena kernel+ISO novas (avisos nunca viram erro)"
assert_match "$outA" 'REINICIE' "E32: kernel 1.0.0-1 → 2.0.0-1 na transação = aviso de reboot (kbefore≠kafter — exato por construção)"
assert_match "$outA" 'Elite v2\.10\.20 disponível' "E32: release viva ≠ marker = defasagem da casa DECLARADA (scripts/configs não são pacotes)"
cu_reset "v2.10.19"
outB="$(cu_run NEW_KV=1.0.0-1 CURL_JSON=$'{\n  "tag_name": "v2.10.19"\n}\n' 2>&1)"; rcB=$?
assert_eq "$rcB" "0" "E32: termina 0 na cena nada-a-fazer"
if grep -q 'REINICIE' <<<"$outB"; then
  fail "E32: sem kernel novo = sem aviso de reboot" "cena idêntica gritou REINICIE (falso positivo)"
else
  ok "E32: sem kernel novo = SEM aviso de reboot (o aviso não é piua ocioso)"
fi
if grep -q 'disponível' <<<"$outB"; then
  fail "E32: base em dia = sem aviso de ISO" "marker == release viva gritou 'disponível' (falso positivo)"
else
  ok "E32: base em dia = SEM aviso de ISO (silêncio é a voz de tudo certo)"
fi
cu_reset "v2.10.19"
outC="$(cu_run CURL_FAIL=1 NEW_KV=1.0.0-1 2>&1)"; rcC=$?
assert_eq "$rcC" "0" "E32: OFFLINE — curl morto NÃO derruba o craft-update (set -e sobrevive ao || true)"
if grep -q 'disponível' <<<"$outC"; then
  fail "E32: offline = zero aviso de versão" "curl morto e ainda assim avisou (nunca deveria)"
else
  ok "E32: offline = zero aviso de versão (falha de rede é silêncio, doutrina da casa)"

fi

# ── E36 — a classe proibida do áudio EXECUTA (o contrato antigo só grepava
# a PALAVRA — 'USB Microphone' em EN escapava do BAD_RE que só tinha
# 'microfone' pt + a marca do rig: a reincidência exata da doença p6aw por
# outro nome. Comportamento se prova EXECUTANDO o regex do arquivo real):
if command -v python3 >/dev/null 2>&1; then
  BAD_LINE="$(sed -n 's/^BAD_RE = //p' "$REPO/elite/airootfs/usr/local/bin/craft-audio-route")"
  if [ -n "$BAD_LINE" ] && python3 -c "
import re, sys
bad = eval(sys.argv[1])
caem = ['Fifine Microphone', 'USB Microphone', 'Microfone do painel', 'Monitor of Built-in Audio']
nao_cai = 'Saída Analógica'
sys.exit(0 if all(bad.search(p) for p in caem) and not bad.search(nao_cai) else 1)
" "$BAD_LINE" 2>/dev/null; then
    ok "E36: BAD_RE do áudio EXECUTA — microfone pt+EN e 'Monitor of' caem na classe proibida; saída analógica não"
  else
    fail "E36: BAD_RE do áudio executa" "o regex da classe proibida não pegou as provas (réu: 'USB Microphone' EN virava default)"
  fi
else
  skip "E36: BAD_RE do áudio executa" "python3 ausente no runner"
fi

# ── E46 — craft-update v4: as doses automatizadas SOB A LUZ (a ferida do
#    'erros persistem' provada no COMPORTAMENTO, não no texto — a lição
#    E35.1/E42: o sandbox mente quando o teste só lê). Mundo isolado com
#    mocks dedicados (id=root, pacman com estado, snapper, fuser, loginctl).
MOCKCU="$WORK/mocks-cupd"
mkdir -p "$MOCKCU"
cat > "$MOCKCU/id" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "-u" ] && echo 0
exit 0
EOF
cat > "$MOCKCU/pacman" <<'EOF'
#!/usr/bin/env bash
# pacman de prova: -Slq devolve o canal, -Q lê o flip do kernel, a transação
# cria o flip (o kernel muda de VERDADE entre o antes e o depois)
ST="${MOCK_DIR:?}"; mkdir -p "$ST"; touch "$ST/pacman.log"
printf 'pacman %s\n' "$*" >> "$ST/pacman.log"
if [[ -f "$ST/pacman-fail" && "$1" == "-Syu" ]]; then echo "erro simulado" >&2; exit 3; fi
case "$1" in
  -Q)   if [ "$2" = "elite-system" ]; then
            # E50: o PACOTE ÚNICO tem delta próprio (o antes/depois da era nova)
            if [ -f "$ST/es-ver" ]; then echo "elite-system $(cat "$ST/es-ver")"; exit 0; fi
            echo "erro: pacote 'elite-system' não encontrado" >&2; exit 1
        fi
        if [ "$2" = "elite-craft" ]; then
            # LEGADO: o fóssil da era dos dois veículos (a transição narra)
            if [ -f "$ST/ec-ver" ]; then echo "elite-craft $(cat "$ST/ec-ver")"; exit 0; fi
            echo "erro: pacote 'elite-craft' não encontrado" >&2; exit 1
        fi
        if [ "$2" = "craft-toplevel" ]; then
            # a PONTE (o hook do elite-adopt captura o 'antes' dele no hook)
            if [ -f "$ST/tl-ver" ]; then echo "craft-toplevel $(cat "$ST/tl-ver")"; exit 0; fi
            echo "erro: pacote 'craft-toplevel' não encontrado" >&2; exit 1
        fi
        v="6.12.4-2"; [ -f "$ST/kernel-flip" ] && v="6.12.5-1"
        echo "linux-cachyos-bore $v"; exit 0 ;;
  -Slq) [ -f "$ST/repo-fail" ] && exit 1
        # E50: o db da era nova — elite-system, a PONTE craft-toplevel, o
        # FÓSSIL elite-craft (o canal dele se livra) e os apps de terceiros
        printf '%s\n' elite-system craft-toplevel elite-craft brave-origin; exit 0 ;;
  -Syu) touch "$ST/kernel-flip"
        [ -f "$ST/es-upgrade" ] && printf '1.0-1\n' > "$ST/es-ver"
        [ -f "$ST/ec-upgrade" ] && printf '1.0-4\n' > "$ST/ec-ver"
        [ -f "$ST/tl-upgrade" ] && printf '1.0-4\n' > "$ST/tl-ver"
        exit 0 ;;
  -Sy)  [ -f "$ST/es-upgrade" ] && printf '1.0-1\n' > "$ST/es-ver"
        [ -f "$ST/ec-upgrade" ] && printf '1.0-4\n' > "$ST/ec-ver"
        [ -f "$ST/tl-upgrade" ] && printf '1.0-4\n' > "$ST/tl-ver"
        exit 0 ;;
  *)    exit 0 ;;
esac
EOF
cat > "$MOCKCU/snapper" <<'EOF'
#!/usr/bin/env bash
ST="${MOCK_DIR:?}"; mkdir -p "$ST"
printf 'snapper %s\n' "$*" >> "$ST/snapper.log"
if [ "$3" = "list-configs" ]; then [ -f "$ST/no-snapper" ] && exit 1; exit 0; fi
if [ "$3" = "create" ] && [ "$5" = "pre" ]; then echo 41; exit 0; fi
exit 0
EOF
cat > "$MOCKCU/fuser" <<'EOF'
#!/usr/bin/env bash
[ -f "${MOCK_DIR:?}/pacman-lock" ] && exit 0
exit 1
EOF
cat > "$MOCKCU/loginctl" <<'EOF'
#!/usr/bin/env bash
# sem cenário de sessão: silêncio (as cenas antigas não têm usuário);
# com user-flip: UM usuário logado (uid 1000) — a cena E48 da sessão viva
ST="${MOCK_DIR:?}"
[ -f "$ST/user-flip" ] && printf '%s\n' "1000 chris"
exit 0
EOF
cat > "$MOCKCU/runuser" <<'EOF'
#!/usr/bin/env bash
printf 'runuser %s\n' "$*" >> "${MOCK_DIR:?}/runuser.log"
exit 0
EOF
cat > "$MOCKCU/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify-send %s\n' "$*" >> "${MOCK_DIR:?}/notify.log"
exit 0
EOF
cat > "$MOCKCU/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "${MOCK_DIR:?}/systemctl.log"
exit 0
EOF
cat > "$MOCKCU/pgrep" <<'EOF'
#!/usr/bin/env bash
# E48: o pgrep da sessão — craft-bars vivo SÓ com bars-alive (cena decide);
# swayidle está vivo (a sessão roda). Toda chamada deixa linha no papel.
ST="${MOCK_DIR:?}"; touch "$ST/pgrep.log"
printf 'pgrep %s\n' "$*" >> "$ST/pgrep.log"
case "$*" in
  *craft-bars*) [ -f "$ST/bars-alive" ] && exit 0; exit 1 ;;
  *)            exit 0 ;;
esac
EOF
cat > "$MOCKCU/pkill" <<'EOF'
#!/usr/bin/env bash
# E48: o pkill cirúrgico do refresh deixa réu nominal no papel
ST="${MOCK_DIR:?}"; touch "$ST/pkill.log"
printf 'pkill %s\n' "$*" >> "$ST/pkill.log"
exit 0
EOF
chmod +x "$MOCKCU"/*
CU="$REPO/elite/airootfs/usr/local/bin/craft-update"
run_cu() { # run_cu <args…> — mundo root isolado, log injetável (o ESTADO do
  # cenário o teste prepara antes — o run não apaga nada por trás)
  local st="$STCU"
  ( export PATH="${CU_EXTRA_PATH:+$CU_EXTRA_PATH:}$MOCKCU:$PATH" MOCK_DIR="$st" ELITE_UPDATE_LOG="${ELITE_UPDATE_LOG:-$st/update.log}" ELITE_VERSION_MARKER="/nada" ELITE_UNIT_DIR="$st/units" ELITE_TL_SETTLE=0
    # E54 — a morada do lock INJETÁVEL (mesma escola do VMARK/ULOG: o teste
    # nunca escreve em /var) e o teto de espera por cenário (a cena decide)
    export ELITE_PACMAN_LCK="$st/db.lck" ELITE_LOCK_WAIT="${ELITE_LOCK_WAIT:-120}"
    bash "$CU" "$@" 2>&1 )
}
STCU="$STATE/cupd"

# dose DIÁRIA: a lista VIVA do canal vai inteira para o pacman — E50: sem
# o par legado (o fóssil elite-craft e a ponte craft-toplevel ficam FORA —
# briga de dono pelo binário do daemon recusaria a dose inteira)
rm -rf "$STCU"; mkdir -p "$STCU"; printf '1.0-1\n' > "$STCU/es-ver"
run_cu --canal >/dev/null
assert_grep "$STCU/pacman.log" '\-Sy --needed --noconfirm --overwrite /usr/local/bin/\* --overwrite /etc/systemd/system/elite-\* elite-system brave-origin' \
  "E50→E56/canal: a dose diária leva a lista viva SEM o par legado e com os DOIS globs escopados (--needed — quem está em dia não reinstala; a era única não convive com o fóssil; as units órfãs não derrubam a dose)"
assert_nogrep "$STCU/pacman.log" '\-Sy .* (elite-craft|craft-toplevel)' "E50/canal: o fóssil e a ponte NÃO entram na dose (puxá-los numa era única seria briga de dono pelo daemon)"
assert_grep "$STCU/update.log" 'era do pacote único' "E50/canal: a era nova deixa linha no papel (quem lê o log entende POR QUE o par legado sumiu da dose)"
assert_grep "$STCU/update.log" 'canal: OK' "E46/canal: dose concluída com linha no papel (o timer deixa réu nomeado)"

# dose DIÁRIA de ADOÇÃO (E56 — a prova crua do rig): o rig da era v2
# (craft-toplevel vivo, elite-system ausente) recebe A ADOÇÃO na própria
# dose — o par legado sai pelo REPLACES, nunca como alvo (o conflito
# alvo-contra-alvo 'elite-system-1.0-6 e craft-toplevel-1.0-5 estão em
# conflito' morreu aqui)
rm -rf "$STCU"; mkdir -p "$STCU"
run_cu --canal >/dev/null
assert_grep "$STCU/pacman.log" '\-Sy --needed --noconfirm --overwrite /usr/local/bin/\* --overwrite /etc/systemd/system/elite-\* elite-system brave-origin' \
  "E56/canal: a dose de adoção leva o pacote único SEM o par legado na lista (o replaces faz a troca de era — o rig provou que NOMEAR os dois é transação morta)"
assert_nogrep "$STCU/pacman.log" '\-Sy .* (elite-craft|craft-toplevel)' "E56/canal: o par legado não vira alvo NEM adotando (o replaces o remove — brigando com ele a dose inteira recusava)"
assert_grep "$STCU/update.log" 'ADOÇÃO nesta dose' "E56/canal: a adoção deixa linha no papel (quem lê o log entende que ESTA dose trocou a era)"

# dose DIÁRIA offline: o repo não respondeu = silêncio rc 0 (o timer volta amanhã)
touch "$STCU/repo-fail"
out="$(run_cu --canal)" ; rc=$?
assert_eq "$rc" "0" "E46/canal: offline é silêncio rc 0 (falha de rede JAMAIS é erro de atualização — a lei v2)"
assert_grep "$STCU/update.log" 'não respondeu' "E46/canal: o offline fica no papel (a prova existe, o usuário não é assombrado)"

# ── E62 — O PAPEL É DO DONO TAMBÉM (a foto do rig, 05/nov): o log nasce
#    root:root 644 e a porta MANUAL do dono escrevia contra a parede — o
#    bash gritava 'linha 154: /var/log/elite-update.log: Permissão negada'
#    e as linhas do manual se perdiam inteiras. As cenas rodam o DONO
#    (mock id → 1000, via CU_EXTRA_PATH — o mesmo desenho do /var/log:
#    nem o papel nem a gaveta são dele).
# (a) sudo VIVO (a porta manual ACABOU de autorizar a transação): o papel
#     é aberto (chmod 666) e a linha ATERRISSA — a prova que a sentinela
#     aponta nunca mais fica sem a história do próprio dono
rm -rf "$STCU"; mkdir -p "$STCU/bin" "$STCU/ro"; touch "$STCU/repo-fail"
cat > "$STCU/bin/id" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "-u" ] && echo 1000
exit 0
EOF
cat > "$STCU/bin/sudo" <<'EOF'
#!/usr/bin/env bash
# sudo de prova (NOPASSWD/timestamp vivo): -n true → 0; os comandos do
# heal (touch/chmod) executados DE VERDADE no arquivo de teste — o
# mesmo caminho do rig, simulação honesta do poder concedido
[ "${1:-}" = "-n" ] && exit 0
exec "$@"
EOF
chmod +x "$STCU/bin/id" "$STCU/bin/sudo"
printf '' > "$STCU/ro/update.log"; chmod 444 "$STCU/ro/update.log"; chmod 555 "$STCU/ro"
CU_EXTRA_PATH="$STCU/bin"; export ELITE_UPDATE_LOG="$STCU/ro/update.log"
out="$(run_cu --canal)" ; rc=$?
assert_eq "$rc" "0" "E62/dono+sudo vivo: a dose offline segue rc 0 (a cura do papel nunca vira erro de atualização)"
assert_nogrep "$out" 'Permissão negada' "E62/dono+sudo vivo: NENHUM grito do bash na cara do dono (a foto, linha 154, morre aqui)"
assert_grep "$STCU/ro/update.log" 'canal: iniciando' "E62/dono+sudo vivo: a linha do dono ATERRISSA no papel curado (a porta manual volta a ter história)"
assert_eq "$(stat -c '%a' "$STCU/ro/update.log")" "666" "E62/dono+sudo vivo: o papel foi ABERTO (666 — a casa é de um dono; root segue escrevendo nele)"
# (b) sudo FRIO (senha exigida, nenhum timestamp — a cena que NUNCA pode
#     virar prompt): a linha morre em SILÊNCIO honesto e o bash não grita
chmod -R u+w "$STCU" 2>/dev/null || true
rm -rf "$STCU"; mkdir -p "$STCU/bin-frio" "$STCU/ro-frio"; touch "$STCU/repo-fail"
cat > "$STCU/bin-frio/id" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "-u" ] && echo 1000
exit 0
EOF
cat > "$STCU/bin-frio/sudo" <<'EOF'
#!/usr/bin/env bash
# sudo FRIO de prova: a senha é exigida e não há timestamp — falha
# calada (o sudo -n de verdade devolve o mesmo 1, nunca um prompt)
exit 1
EOF
chmod +x "$STCU/bin-frio/id" "$STCU/bin-frio/sudo"
printf '' > "$STCU/ro-frio/update.log"; chmod 444 "$STCU/ro-frio/update.log"; chmod 555 "$STCU/ro-frio"
CU_EXTRA_PATH="$STCU/bin-frio"; export ELITE_UPDATE_LOG="$STCU/ro-frio/update.log"
out="$(run_cu --canal)" ; rc=$?
assert_eq "$rc" "0" "E62/dono+sudo frio: silêncio rc 0 (a linha perdida nunca é erro de atualização)"
assert_nogrep "$out" 'Permissão negada' "E62/dono+sudo frio: o bash NÃO grita (erro de redirecionamento é do shell — calado por desenho)"
assert_nogrep "$STCU/ro-frio/update.log" 'canal' "E62/dono+sudo frio: a linha morre honesta (sem poder de escrita e sem sudo, nada é fingido — os timers escrevem como root)"
# (c) ROOT mantém o papel aberto: a dose ao ligar (mock id → 0) escreve no
#     log que encontrar fechado e o deixa 666 — o próximo manual do dono
#     já nasce com a porta aberta, sem esperar o primeiro sudo
chmod -R u+w "$STCU" 2>/dev/null || true
rm -rf "$STCU"; mkdir -p "$STCU"; touch "$STCU/repo-fail"
printf '' > "$STCU/update.log"; chmod 600 "$STCU/update.log"
CU_EXTRA_PATH=""; export ELITE_UPDATE_LOG=""
out="$(run_cu --canal)" ; rc=$?
assert_eq "$rc" "0" "E62/root: a dose ao ligar segue rc 0 (o chmod do papel nunca é erro)"
assert_eq "$(stat -c '%a' "$STCU/update.log")" "666" "E62/root: o root MANTÉM o papel aberto (600 → 666 — o manual do dono escreve sem pedir nada a ninguém)"
assert_grep "$STCU/update.log" 'não respondeu' "E62/root: a dose do root aterrissa no papel como sempre (E46 intacto)"
CU_EXTRA_PATH=""; unset ELITE_UPDATE_LOG

# dose SEMANAL: PRE antes, transação, POST casado, kernel novo = REINICIE
rm -rf "$STCU"; mkdir -p "$STCU"
run_cu --sistema >/dev/null
assert_grep "$STCU/snapper.log" 'create -t pre -p -d elite-sysupdate' "E46/sistema: o snapshot PRE é criado ANTES da transação (a rede de segurança arma antes do risco)"
assert_grep "$STCU/snapper.log" 'create -t post --pre-number 41' "E46/sistema: o POST casa com o PRE (#41 — o par fecha a história)"
assert_grep "$STCU/pacman.log" '\-Syu --needed --noconfirm --overwrite /usr/local/bin/\*' "E46/sistema: o -Syu completo leva o --overwrite escopado (a adoção da casa segue lei)"
assert_grep "$STCU/pacman.log" '\-Syu --needed --noconfirm --overwrite /usr/local/bin/\* --overwrite /etc/systemd/system/elite-\*' "E56/sistema: a dose semanal leva os DOIS globs escopados (as units órfãs do /etc não derrubam mais a transação — a prova crua do rig, 'arquivos conflitantes' 05/nov)"
assert_grep "$STCU/update.log" 'kernel 6.12.4-2 → 6.12.5-1 — REBOOT' "E46/sistema: kernel novo na transação = aviso de reboot no papel (a comparação -Q antes/depois, exata por construção)"
assert_grep "$STCU/update.log" 'REBOOT aplica' "E46/sistema: o kernel novo fica no papel (o aviso na sessão é guardado pelo bus do usuário — sandbox honesto não tem bus; o papel é o registro)"

# dose SEMANAL com pacman ocupado: silêncio, ZERO transação
rm -rf "$STCU"; mkdir -p "$STCU"; touch "$STCU/pacman-lock"
run_cu --sistema >/dev/null
assert_nogrep "$STCU/pacman.log" '\-Syu' "E46/sistema: pacman ocupado = NENHUMA transação (o lock é respeitado — a semana volta)"
assert_grep "$STCU/update.log" 'ocupado' "E46/sistema: a recusa fica no papel (nunca silêncio absoluto)"

# dose SEMANAL com pacman recusando: rc 1 + o PRE nomeado como rollback
rm -rf "$STCU"; mkdir -p "$STCU"; touch "$STCU/pacman-fail"
run_cu --sistema >/dev/null; rc=$?
assert_eq "$rc" "1" "E46/sistema: transação recusada = rc 1 (o timer falha visível — nunca vermelho calado)"
assert_grep "$STCU/update.log" 'FALHOU \(rc=3\)' "E46/sistema: o rc REAL no papel (capturado FORA da negação — dentro do if ! o status é o invertido; os parênteses são literais no ERE)"
assert_grep "$STCU/update.log" 'snapshot PRE #41 guarda o estado anterior' "E46/sistema: a falha aponta ONDE está o rollback, no papel (o snapshot #41 é a porta do GRUB)"

# dose SEMANAL sem snapper: segue SEM rede de segurança, com a verdade no papel
rm -rf "$STCU"; mkdir -p "$STCU"; touch "$STCU/no-snapper"
run_cu --sistema >/dev/null
assert_grep "$STCU/update.log" 'snapper indisponível' "E46/sistema: sem snapper a dose diz que segue SEM rede (nunca finge que o snapshot existe)"
assert_grep "$STCU/pacman.log" '\-Syu' "E46/sistema: a dose semanal NÃO morre por falta de snapper (a atualização é a missão; o snapshot é a rede — a ausência fica no papel)"

# a porta MANUAL: instala o veículo e liga a cadência (o fim do 'erros persistem')
rm -rf "$STCU"; mkdir -p "$STCU/units"
cp "$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.timer" "$REPO/elite/airootfs/etc/systemd/system/elite-sysupdate.timer" "$STCU/units/"
run_cu >/dev/null
assert_grep "$STCU/pacman.log" '\-Syu --needed --overwrite /usr/local/bin/\* --overwrite /etc/systemd/system/elite-\* elite-system' \
  "E50→E56/manual: sem a ponte viva, o alvo EXPLÍCITO instala o único com os DOIS globs (estado sem o par não briga; com craft-toplevel vivo o replaces adota — cena E56 abaixo)"
assert_nogrep "$STCU/pacman.log" '\-Syu --needed --overwrite /usr/local/bin/\* .* elite-craft' "E50/manual: o alvo é UM só (a era dos dois veículos não volta nem como alvo)"
assert_grep "$STCU/systemctl.log" 'enable --now elite-bootupdate.timer elite-sysupdate.timer' "E46/manual: a cadência liga na 1ª 'Atualizar sistema' (o automatismo nasce onde o dono já clica)"

# E56 — O ALVO CONDICIONAL (a prova crua do rig): craft-toplevel vivo +
# elite-system ausente = SEM alvo explícito — o replaces adota; nomear era
# conflito não solucionável ('elite-system-1.0-6 e craft-toplevel-1.0-5
# estão em conflito' — o pacman não substitui o que a MESMA transação
# atualiza)
rm -rf "$STCU"; mkdir -p "$STCU/units"
cp "$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.timer" "$REPO/elite/airootfs/etc/systemd/system/elite-sysupdate.timer" "$STCU/units/"
printf '1.0-4\n' > "$STCU/tl-ver"
run_cu >/dev/null
assert_grep "$STCU/pacman.log" 'pacman -Syu --needed --overwrite /usr/local/bin/\* --overwrite /etc/systemd/system/elite-\*$' \
  "E56/manual: com a ponte viva o -Syu vai SEM alvo explícito e com os DOIS globs (o replaces do elite-system adota na mesma transação)"
assert_nogrep "$STCU/pacman.log" 'pacman -Syu .* elite-system$' "E56/manual: o alvo explícito NÃO entra quando a ponte pode brigar (o rig provou: transação morta por conflito alvo-contra-alvo)"
assert_grep "$STCU/update.log" 'o REPLACES puxa o elite-system' "E56/manual: a decisão deixa linha no papel (quem lê o log entende POR QUE o alvo sumiu)"

# ── E54 — A SENTINELA DA BASE (o erro cru do dono morre): a base é de UM
#    dono por vez — a porta manual ESPERA, o órfão é limpo, a recusa é
#    honesta. O lock mora no cenário (ELITE_PACMAN_LCK) e o fuser mock lê
#    o pacman-lock do cenário (a mesma mecânica da cena --sistema E46).
# (a) manual com a base ocupada que LIBERA: espera com mensagem e segue
rm -rf "$STCU"; mkdir -p "$STCU/units"
cp "$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.timer" "$REPO/elite/airootfs/etc/systemd/system/elite-sysupdate.timer" "$STCU/units/"
touch "$STCU/pacman-lock" "$STCU/db.lck"
( sleep 1; rm -f "$STCU/pacman-lock" ) &
ELITE_LOCK_WAIT=20 run_cu >/dev/null
assert_grep "$STCU/pacman.log" '\-Syu --needed --overwrite /usr/local/bin/\* --overwrite /etc/systemd/system/elite-\* elite-system' "E54/sentinela: base ocupada que LIBERA = a porta manual espera e segue (a briga boot×mão não perde dose — o erro cru nunca mais é a saída)"
assert_grep "$STCU/update.log" 'manual: base ocupada por [0-9]+s' "E54/sentinela: a espera fica no papel COM O TEMPO (quem lê o log entende o porquê e o quanto)"
# (b) manual com a base ocupada ALÉM DO TETO: recusa honesta, NADA tocado
rm -rf "$STCU"; mkdir -p "$STCU/units"
cp "$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.timer" "$REPO/elite/airootfs/etc/systemd/system/elite-sysupdate.timer" "$STCU/units/"
touch "$STCU/pacman-lock"
ELITE_LOCK_WAIT=2; out="$(run_cu)"; rc=$?; unset ELITE_LOCK_WAIT
printf '%s\n' "$out" > "$STCU/saida.txt"
assert_eq "$rc" "1" "E54/sentinela: base ocupada além do teto = rc 1 honesto (a transação não começou — força é dano, a espera é cortesia com limite)"
assert_nogrep "$STCU/pacman.log" '\-Syu' "E54/sentinela: recusada pelo teto = ZERO transação (a base não é tocada à força — nem um byte)"
assert_grep "$STCU/saida.txt" 'segue ocupada' "E54/sentinela: a recusa fala com o dono (o erro cru do pacman nunca mais é a saída da porta do dono)"
# (c) manual com lock ÓRFÃO (db.lck sem transação viva): limpo e a dose segue
rm -rf "$STCU"; mkdir -p "$STCU/units"
cp "$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.timer" "$REPO/elite/airootfs/etc/systemd/system/elite-sysupdate.timer" "$STCU/units/"
touch "$STCU/db.lck"
run_cu >/dev/null
assert_grep "$STCU/pacman.log" '\-Syu --needed --overwrite /usr/local/bin/\* --overwrite /etc/systemd/system/elite-\* elite-system' "E54/sentinela: lock ÓRFÃO = limpo e a dose segue (o desligamento no meio da transação prende a base para sempre — o lixo sai com a prova no papel; a prova do rig 05/nov CONFIRMOU o órfão como o bloqueio recorrente)"
assert_grep "$STCU/update.log" 'lock órfão de .*db\.lck removido' "E54/sentinela: a limpeza do órfão fica no papel (a remoção tem réu e motivo — nunca silêncio)"
ORPH=$( [ -e "$STCU/db.lck" ] && echo ficou || echo saiu )
assert_eq "$ORPH" "saiu" "E54/sentinela: o db.lck órfão SAIU da base (o pacman respeita o arquivo para sempre — quem o remove é a casa, com nenhuma transação viva)"
# (d) canal com a base ocupada: silêncio rc 0, ZERO transação (a lei --sistema)
rm -rf "$STCU"; mkdir -p "$STCU"
touch "$STCU/pacman-lock" "$STCU/db.lck"
run_cu --canal >/dev/null; rc=$?
assert_eq "$rc" "0" "E54/canal: pacman ocupado = rc 0 (o timer falhar visível seria ruído — a dose volta no próximo boot)"
assert_nogrep "$STCU/pacman.log" '\-Sy' "E54/canal: ocupado = NENHUMA transação (a mesma definição das três portas — revisar uma é revisar todas)"
assert_grep "$STCU/update.log" 'canal: pacman ocupado' "E54/canal: a recusa fica no papel (silêncio para o usuário, réu no log)"
# (e) manual com o pacman recusando a transação: o rc REAL + mensagem honesta
rm -rf "$STCU"; mkdir -p "$STCU/units"
cp "$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.timer" "$REPO/elite/airootfs/etc/systemd/system/elite-sysupdate.timer" "$STCU/units/"
touch "$STCU/pacman-fail"
out="$(run_cu)"; rc=$?
printf '%s\n' "$out" > "$STCU/saida.txt"
assert_eq "$rc" "3" "E54/manual: o rc REAL do pacman chega ao script (capturado FORA da negação — a lição E46 agora também na porta manual)"
assert_grep "$STCU/saida.txt" 'recusou a transação' "E54/manual: a recusa fala com o dono (NADA da casa mudou — e a saída nunca mais é o erro cru calado)"

# ── E48 — A CURA NA SESSÃO VIVA (o 'atualizei e persistiu' morre): o
#    dump nl3z provou o rig correndo a receita velha DEPOIS do update
#    (timeout 1200 systemctl suspend cru, conf 2/7) — o update entregava
#    ARQUIVOS e a sessão seguia com o daemon VELHO até relogin.
# canal com DELTA: a dose diária ADOTOU o pacote único (ausente → 1.0-1)
rm -rf "$STCU"; mkdir -p "$STCU"
touch "$STCU/user-flip" "$STCU/bars-alive" "$STCU/es-upgrade"
run_cu --canal >/dev/null
assert_grep "$STCU/update.log" 'elite-system ausente → 1.0-1' "E50/canal: o delta do PACOTE ÚNICO fica no papel (a comparação -Q antes/depois, exata por construção — a adoção é delta)"
assert_grep "$STCU/pkill.log" 'pkill -u 1000 -x swayidle' "E48/canal: o swayidle da SESSÃO é reiniciado (o supervisor craft-bars ressuscita com a receita nova — idle/suspensão valem SEM relogin)"
assert_grep "$STCU/update.log" 'swayidle \(uid 1000\) reiniciado' "E48/canal: o refresh deixa linha no papel do log (o aviso na TELA segue o bus do usuário — sandbox honesto não tem bus; o papel é o registro, a lição E46)"
# canal SEM delta: a transação não tocou a casa = NENHUM pkill (churn de daemon de graça não existe)
rm -rf "$STCU"; mkdir -p "$STCU"
touch "$STCU/user-flip" "$STCU/bars-alive"
run_cu --canal >/dev/null
assert_nogrep "$STCU/pkill.log" 'swayidle' "E48/canal: sem delta NÃO há pkill (o daemon vivo só é reiniciado quando a casa mudou)"
# sistema com supervisor AUSENTE: o pkill NÃO sai (matar sem quem ressuscita = dano)
rm -rf "$STCU"; mkdir -p "$STCU"
touch "$STCU/user-flip" "$STCU/es-upgrade"
run_cu --sistema >/dev/null
assert_nogrep "$STCU/pkill.log" 'swayidle' "E48/sistema: SEM supervisor o pkill NÃO sai (matar o idle sem volta é dano, não cura — o relogin é a porta honesta)"
assert_grep "$STCU/update.log" 'supervisor craft-bars AUSENTE' "E48/sistema: a verdade no papel (o rig sem craft-bars sabe que a sessão segue com a receita antiga)"
# manual com ADOÇÃO: o rig SEM elite-system instala (ausente → 1.0-1) = delta
rm -rf "$STCU"; mkdir -p "$STCU/units"
cp "$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.timer" "$REPO/elite/airootfs/etc/systemd/system/elite-sysupdate.timer" "$STCU/units/"
touch "$STCU/user-flip" "$STCU/bars-alive" "$STCU/es-upgrade"
run_cu >/dev/null
assert_grep "$STCU/pkill.log" 'pkill -u 1000 -x swayidle' "E48/manual: a ADOÇÃO do pacote único também reinicia a sessão (ausente → 1.0-1 é delta — a ferida da 28 cura NA SESSÃO, não só nos arquivos)"

# ── E49 — A CURA NA SESSÃO INTEIRA + A ADOÇÃO DE UMA VIA: o v4.1 deixou
#    duas feridas abertas. (1) o refresh reiniciava SÓ o swayidle — a dock
#    (transição suave), o áudio e o daemon de janelas seguiam VELHOS na
#    sessão até relogin: o dono veria 'a dock continua piscando' após
#    atualizar. (2) o OVO-GALINHA: o rig da era pré-E46 roda um craft-
#    update SEM alvos explícitos — o elite-craft nunca é adotado e o
#    craft-update novo mora DENTRO dele. A quebra viaja no craft-toplevel
#    (o ÚNICO pacote que TODO rig tem): elite-adopt + hook PostTransaction.
#    O corpo do elite-adopt nasce do build.sh (fonte única) — o teste o
#    extrai DE LÁ e o executa: comportamento, não texto (lição E35.1/E42).
ADOPT_SRC="$WORK/elite-adopt-under-test"
sed -n "/^cat > \/tmp\/elite-src\/craft-toplevel\/elite-adopt <<'EOADOPT'$/,/^EOADOPT$/p" "$REPO/.ci/build.sh" | sed '1d;$d' > "$ADOPT_SRC"
chmod +x "$ADOPT_SRC"
run_adopt() { # run_adopt — o hook no mundo root dos mocks, corpo ACOPLADO
  local st="$STCU"
  ( export PATH="$MOCKCU:$PATH" MOCK_DIR="$st" ELITE_UPDATE_LOG="$st/update.log" ELITE_VERSION_MARKER="/nada" ELITE_UNIT_DIR="$st/units" ELITE_TL_SETTLE=0
    export ELITE_ADOPT_SYNC=1 ELITE_ADOPT_SETTLE=0 ELITE_ADOPT_POLL=0
    export ELITE_CRAFT_UPDATE="$REPO/elite/airootfs/usr/local/bin/craft-update"
    bash "$ADOPT_SRC" 2>&1 )
}

# (1) veículo PRESENTE: hook calado — custo zero, nenhuma adoção, nenhum papel
rm -rf "$STCU"; mkdir -p "$STCU"; touch "$STCU/update.log" "$STCU/pkill.log"
printf '1.0-1\n' > "$STCU/es-ver"
out="$(run_adopt)"; rc=$?
assert_eq "$rc" "0" "E50/adopt: PACOTE ÚNICO presente = exit 0 (o hook vive calado para sempre — a era da ponte acabou, custo zero por transação)"
assert_nogrep "$STCU/pacman.log" '\-Sy --needed' "E49/adopt: veículo presente = NENHUMA transação extra (a adoção é UMA via, não um imposto eterno)"
assert_nogrep "$STCU/update.log" 'adotar:' "E49/adopt: veículo presente = ZERO linhas no papel (silêncio honesto, não fingimento)"

# (2) veículo AUSENTE + supervisor vivo: a PONTE fecha TUDO — transação do
#     pacote único, sessão inteira (toplevel primeiro), cadência ligada
rm -rf "$STCU"; mkdir -p "$STCU/units"; touch "$STCU/update.log" "$STCU/pkill.log"
cp "$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.timer" "$REPO/elite/airootfs/etc/systemd/system/elite-sysupdate.timer" "$STCU/units/"
touch "$STCU/user-flip" "$STCU/bars-alive" "$STCU/es-upgrade" "$STCU/tl-upgrade"
printf '1.0-3\n' > "$STCU/tl-ver"
out="$(run_adopt)"; rc=$?
assert_eq "$rc" "0" "E50/adopt: pacote único ausente = a ponte conclui (rc 0 — a via única não tropeça)"
assert_grep "$STCU/pacman.log" '\-Syu --needed --noconfirm --overwrite /usr/local/bin/\* --overwrite /etc/systemd/system/elite-\* elite-system' \
  "E50→E56/adopt: a ponte puxa O PACOTE ÚNICO com os DOIS globs escopados (o pacman substitui o par legado na MESMA transação — replaces; as units órfãs não derrubam a adoção)"
assert_grep "$STCU/update.log" 'PACOTE ÚNICO elite-system ausente' "E50/adopt: a ponte deixa réu nominal no papel (o dono sabe QUEM agiu e quando)"
assert_grep "$STCU/update.log" 'adoção concluída' "E49/adopt: a conclusão fica no papel (o ciclo inteiro é auditável)"
assert_grep "$STCU/update.log" 'elite-system ausente → 1.0-1' "E50/adotar: o pacote único não tinha 'antes' — a ADOÇÃO já é a mudança (nada de refresh às cegas)"
assert_grep "$STCU/update.log" 'craft-toplevel 1.0-3 → 1.0-4' "E50/adotar: o 'antes' LEGADO capturado NO HOOK narra a substituição (a história completa no papel)"
assert_grep "$STCU/pkill.log" 'pkill -u 1000 -x craft-toplevel' "E49/adotar: o daemon de janelas MORRE PRIMEIRO (a dock nova nasce sobre o toplevel já de pé)"
assert_grep "$STCU/pkill.log" 'pkill -u 1000 -f \^/usr/bin/python3 /usr/local/bin/craft-dock-gui\$' \
  "E49/adotar: a DOCK da sessão é reiniciada (a transição suave v2.11 vale SEM relogin — o 'continua piscando' não renasce)"
assert_grep "$STCU/pkill.log" 'pkill -u 1000 -x craft-audio-route' "E49/adotar: o roteador de áudio segue o mesmo porta (nenhum daemon da casa envelhece no update)"
assert_grep "$STCU/pkill.log" 'pkill -u 1000 -x swayidle' "E49/adotar: o idle fecha o quarteto (a cura E48 continua valendo dentro da cura maior)"
assert_grep "$STCU/systemctl.log" 'enable --now elite-bootupdate.timer elite-sysupdate.timer' "E49/adotar: a cadência nasce ligada na MESMA rodada (o automatismo não espera a 2ª atualização)"
assert_nogrep "$STCU/update.log" 'AUSENTE' "E49/adotar: com supervisor vivo NADA de lamento no papel (o AUSENTE é a cena do mundo sem craft-bars)"

# (3) veículo ausente + supervisor AUSENTE: a adoção acontece (pacotes),
#     mas NENHUM pkill sai — matar daemon sem quem ressuscita é dano
rm -rf "$STCU"; mkdir -p "$STCU/units"; touch "$STCU/update.log" "$STCU/pkill.log"
cp "$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.timer" "$REPO/elite/airootfs/etc/systemd/system/elite-sysupdate.timer" "$STCU/units/"
touch "$STCU/user-flip" "$STCU/es-upgrade" "$STCU/tl-upgrade"
run_adopt >/dev/null
assert_nogrep "$STCU/pkill.log" 'pkill' "E49/adopt: SEM supervisor NENHUM daemon é morto (a lição E48 vale para os QUATRO — pkill sem volta é dano, não cura)"
assert_grep "$STCU/update.log" 'supervisor craft-bars AUSENTE' "E49/adopt: a verdade no papel (o rig sabe que a sessão segue antiga até o relogin)"
assert_grep "$STCU/update.log" 'adoção concluída' "E49/adopt: os PACOTES chegam mesmo sem supervisor (a cura em arquivo é real, a de sessão é honesta)"

# (4) o refresh POR DELTA e POR PACOTE: só o craft-toplevel mudou → só o
#     toplevel morre — a dock/áudio/idle NEM ACORDAM (churn de graça não existe)
rm -rf "$STCU"; mkdir -p "$STCU"
touch "$STCU/user-flip" "$STCU/bars-alive" "$STCU/tl-upgrade"
printf '1.0-3\n' > "$STCU/ec-ver"; printf '1.0-3\n' > "$STCU/tl-ver"
run_cu --canal >/dev/null
assert_grep "$STCU/pkill.log" 'pkill -u 1000 -x craft-toplevel' "E49/canal: delta SÓ do toplevel = SÓ o toplevel reinicia (a cirurgia é por pacote, não por família)"
assert_nogrep "$STCU/pkill.log" 'craft-dock-gui|craft-audio-route|swayidle' "E49/canal: quem NÃO mudou NEM acorda (a dock viva não pisca por causa de update alheio)"

# (5) --adotar com delta VAZIO: nenhuma morte, a cadência segue ligada
#     (era única: o 'antes' do pacote único é passado pelo chamador)
rm -rf "$STCU"; mkdir -p "$STCU/units"; touch "$STCU/update.log" "$STCU/pkill.log"
cp "$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.timer" "$REPO/elite/airootfs/etc/systemd/system/elite-sysupdate.timer" "$STCU/units/"
touch "$STCU/user-flip" "$STCU/bars-alive"
printf '1.0-1\n' > "$STCU/es-ver"; printf '1.0-4\n' > "$STCU/ec-ver"; printf '1.0-4\n' > "$STCU/tl-ver"
run_cu --adotar 1.0-1 1.0-4 1.0-4 >/dev/null
assert_nogrep "$STCU/pkill.log" 'pkill' "E49/adotar: antes == depois = NENHUM pkill (o refresh às cegas mataria daemon vivo por rotina)"
assert_grep "$STCU/systemctl.log" 'enable --now elite-bootupdate.timer elite-sysupdate.timer' "E49/adotar: a cadência idempotente (chamou de novo, liga de novo — sem dano)"

# (6) o PKGBUILD do craft-toplevel SOB A LUZ: no makepkg o package() roda
#     no srcdir (só recebe o source=()) e os gêmeos E49 moram no STARTDIR
#     (payload gerado, sem sha256) — o CI desmentiu a 1ª forma (run
#     41893237128, 'A failure occurred in package()': install sem caminho
#     não vê arquivo nenhum). A prova agora nasce AQUI, antes do CI: o
#     package() EXTRAÍDO executa com os caminhos do makepkg e o install
#     de prova registra ONDE cada arquivo foi buscado.
PGB="$WORK/craft-toplevel-PKGBUILD"
sed -n "/^cat > \/tmp\/elite-src\/craft-toplevel\/PKGBUILD <<'EOPKGBUILD'$/,/^EOPKGBUILD$/p" "$REPO/.ci/build.sh" | sed '1d;$d' > "$PGB"
bash -n "$PGB"
STPK="$WORK/state-pkgbuild"; rm -rf "$STPK"; mkdir -p "$STPK/startdir" "$STPK/srcdir" "$STPK/pkg"
cp "$PGB" "$STPK/startdir/PKGBUILD"
sed -n "/^cat > \/tmp\/elite-src\/craft-toplevel\/elite-adopt <<'EOADOPT'$/,/^EOADOPT$/p" "$REPO/.ci/build.sh" | sed '1d;$d' > "$STPK/startdir/elite-adopt"
sed -n "/^cat > \/tmp\/elite-src\/craft-toplevel\/elite-adopt.hook <<'EOHOOK'$/,/^EOHOOK$/p" "$REPO/.ci/build.sh" | sed '1d;$d' > "$STPK/startdir/elite-adopt.hook"
printf 'int main(void){return 0;}\n' > "$STPK/startdir/craft-toplevel.c"
cp "$STPK/startdir/craft-toplevel.c" "$STPK/srcdir/"
MOCKPK="$WORK/mocks-pkgbuild"; mkdir -p "$MOCKPK"
cat > "$MOCKPK/install" <<'EOF'
#!/usr/bin/env bash
printf 'install %s\n' "$*" >> "${MOCK_DIR:?}/install.log"
exit 0
EOF
chmod +x "$MOCKPK/install"
( cd "$STPK/srcdir" \
  && export PATH="$MOCKPK:$PATH" MOCK_DIR="$STPK" \
  && export startdir="$STPK/startdir" srcdir="$STPK/srcdir" pkgdir="$STPK/pkg" \
  && bash -c 'source "$startdir/PKGBUILD" ; package' )
assert_grep "$STPK/install.log" "install -Dm755 $STPK/startdir/elite-adopt $STPK/pkg/usr/share/elite/elite-adopt" \
  "E49/pkgbuild: o elite-adopt é resolvido NO STARTDIR (o package() roda no srcdir — o caminho explícito é a cura do 'failure in package()' que o CI pegou)"
assert_grep "$STPK/install.log" "install -Dm644 $STPK/startdir/elite-adopt.hook $STPK/pkg/usr/share/libalpm/hooks/elite-adopt.hook" \
  "E49/pkgbuild: o hook PostTransaction entra no payload com o modo 644 (o pacman o lê, não o executa)"

# ── E47 — craft-lock --if-needed: O LOCK QUE JÁ VIVE NÃO MORRE NO ESCURO
#    (a denúncia recorrente do dono: 'só entra em suspensão quando coloco
#    a senha na tela de bloqueio'. O before-sleep REINICIAVA o hyprlock —
#    pkill + espera + exec + init com blur — dentro da janela de 5s do
#    InhibitDelayMaxSec; o congelamento podia pegar a init no meio e o
#    acordar ficava sem lock. Prova no COMPORTAMENTO: hyprlock FAKE vivo
#    (cópia do sleep — o comm é 'hyprlock' de verdade) + hyprlock de PATH
#    que deixa linha no papel).
MOCKCL="$WORK/mocks-clock"
mkdir -p "$MOCKCL"
cat > "$MOCKCL/hyprlock" <<'EOF'
#!/usr/bin/env bash
ST="${MOCK_DIR:?}"; mkdir -p "$ST"
printf 'hyprlock %s\n' "$*" >> "$ST/hyprlock.log"
EOF
chmod +x "$MOCKCL/hyprlock"
CL="$REPO/elite/airootfs/usr/local/bin/craft-lock"
STCL="$WORK/state-clock"

# (1) lock VIVO + --if-needed: exit 0, o processo SOBREVIVE, ninguém recria
rm -rf "$STCL"; mkdir -p "$STCL"
FK="$WORK/fake-lock"; mkdir -p "$FK"; cp /bin/sleep "$FK/hyprlock"
"$FK/hyprlock" 60 & fkpid=$!
sleep 0.1   # o fake precisa existir no procfs antes da checagem
PATH="$MOCKCL:$PATH" MOCK_DIR="$STCL" bash "$CL" --if-needed >/dev/null 2>&1; rc=$?
assert_eq "$rc" "0" "E47/lock: --if-needed com lock vivo = exit 0 (o no-op é a cura: o hook do sono não briga com o lock que já está na tela)"
if kill -0 "$fkpid" 2>/dev/null; then
  ok "E47/lock: o hyprlock VIVO SOBREVIVE ao --if-needed (zero pkill na hora do sono — o acordar encontra o lock que ficou)"
else
  fail "E47/lock: o hyprlock VIVO SOBREVIVE ao --if-needed" "o processo fake morreu — a corrida do PrepareForSleep renasceria"
fi
assert_nogrep "$STCL/hyprlock.log" '.' "E47/lock: nenhum hyprlock NOVO nasceu no caminho --if-needed com lock vivo (recriar o vivo é a init que congelava no meio)"
kill "$fkpid" 2>/dev/null || true

# (2) lock MORTO + --if-needed: segue o fluxo COMPLETO (a promessa se auto-cura)
rm -rf "$STCL"; mkdir -p "$STCL"
PATH="$MOCKCL:$PATH" MOCK_DIR="$STCL" bash "$CL" --if-needed >/dev/null 2>&1; rc=$?
assert_eq "$rc" "0" "E47/lock: --if-needed com lock MORTO conclui com lock novo (o --if-needed NUNCA é pulo do lock: só poupando o vivo)"
assert_grep "$STCL/hyprlock.log" 'hyprlock' "E47/lock: o lock morto foi RECRIADO (o acordar nunca fica sem lock — nem no caso do hyprlock que morreu sozinho)"

# (3) caminho MANUAL sem flag: o reinício da E30 segue INTACTO (pkill no vivo)
rm -rf "$STCL"; mkdir -p "$STCL"
FK2="$WORK/fake-lock2"; mkdir -p "$FK2"; cp /bin/sleep "$FK2/hyprlock"
"$FK2/hyprlock" 60 & fk2pid=$!
sleep 0.1
PATH="$MOCKCL:$PATH" MOCK_DIR="$STCL" bash "$CL" >/dev/null 2>&1; rc=$?
assert_eq "$rc" "0" "E47/lock: o caminho manual conclui (W-l nunca vira no-op silencioso)"
if kill -0 "$fk2pid" 2>/dev/null; then
  fail "E47/lock: o caminho MANUAL reinicia o locker vivo (E30 intacta)" "o fake sobreviveu ao pkill — a instância única quebraria"
else
  ok "E47/lock: o caminho MANUAL reinicia o locker vivo (E30 intacta — o pkill é o fecho da corrida onde ela nasceu)"
fi
assert_grep "$STCL/hyprlock.log" 'hyprlock' "E47/lock: o manual nasceu lock NOVO (quem aperta W-l quer o lock na hora, não um fantasma)"
kill "$fk2pid" 2>/dev/null || true

# ── E48 — craft-bgapps v4.2 NO COMPORTAMENTO (a lição E35.1/E42: texto
#    não prova): processos REAIS com WAYLAND_DISPLAY no environ — o comm
#    de python3 invocado DIRETO é 'python3' (o interpretador; provado no
#    sandbox), o ps é FILTRADO para a cena e o /proc é o de verdade.
#    A cena replica o rig (dump nl3z + relato do dono): o daemon de
#    áudio python (comm python3) com o filho pactl, a dock python com o
#    filho brave (lançado pela dock — a sombra que ENGOLIA o Brave), um
#    app python de terceiros (blueman-applet) e um helper sombreado.
MOCKBG="$WORK/mocks-bgapps"
SCENE="$WORK/bgapps-scene"
mkdir -p "$MOCKBG" "$SCENE"
# os fakes binários (comm = basename garantido em qualquer kernel)
cp /bin/sleep "$SCENE/pactl"
cp /bin/sleep "$SCENE/brave"
cp /bin/sleep "$SCENE/bghelper"
# o daemon de áudio da casa (python3 DIRETO → comm 'python3') + filho pactl
cat > "$SCENE/craft-audio-route" <<EOF
#!/usr/bin/env python3
import os, subprocess, sys, time
env = dict(os.environ)
env["WAYLAND_DISPLAY"] = "wl-0"
p = subprocess.Popen(["$SCENE/pactl", "120"], env=env)
open("$SCENE/pid-pactl", "w").write(str(p.pid))
while True:
    time.sleep(120)
EOF
# a dock da casa (python3 DIRETO) que lança o Brave (a cadeia real do rig)
cat > "$SCENE/craft-dock-gui" <<EOF
#!/usr/bin/env python3
import os, subprocess, time
env = dict(os.environ)
env["WAYLAND_DISPLAY"] = "wl-0"
p = subprocess.Popen(["$SCENE/brave", "120"], env=env)
open("$SCENE/pid-brave", "w").write(str(p.pid))
while True:
    time.sleep(120)
EOF
# o app de terceiros (python3 DIRETO, nome honesto) + o helper sombreado
cat > "$SCENE/blueman-applet" <<EOF
#!/usr/bin/env python3
import os, subprocess, time
env = dict(os.environ)
env["WAYLAND_DISPLAY"] = "wl-0"
p = subprocess.Popen(["$SCENE/bghelper", "120"], env=env)
open("$SCENE/pid-helper", "w").write(str(p.pid))
while True:
    time.sleep(120)
EOF
chmod +x "$SCENE/craft-audio-route" "$SCENE/craft-dock-gui" "$SCENE/blueman-applet"
WAYLAND_DISPLAY=wl-0 python3 "$SCENE/craft-audio-route" & bg_aro=$!
WAYLAND_DISPLAY=wl-0 python3 "$SCENE/craft-dock-gui"   & bg_dock=$!
WAYLAND_DISPLAY=wl-0 python3 "$SCENE/blueman-applet"    & bg_blu=$!
sleep 0.6   # os filhos (pactl/brave/helper) precisam existir no procfs
bg_pactl="$(cat "$SCENE/pid-pactl" 2>/dev/null || true)"
bg_brave="$(cat "$SCENE/pid-brave" 2>/dev/null || true)"
bg_helper="$(cat "$SCENE/pid-helper" 2>/dev/null || true)"
# o ps FILTRADO para a cena: só os nossos pids (o resto do sandbox é ruído)
bg_ppid() { awk '{print $4}' "/proc/$1/stat" 2>/dev/null || echo 1; }
{
  printf '%s %s python3\n'      "$bg_aro" "$(bg_ppid "$bg_aro")"
  printf '%s %s python3\n'      "$bg_dock" "$(bg_ppid "$bg_dock")"
  printf '%s %s python3\n'      "$bg_blu" "$(bg_ppid "$bg_blu")"
  [ -n "$bg_pactl" ]  && printf '%s %s pactl\n'     "$bg_pactl"  "$(bg_ppid "$bg_pactl")"
  [ -n "$bg_brave" ]  && printf '%s %s brave\n'     "$bg_brave"  "$(bg_ppid "$bg_brave")"
  [ -n "$bg_helper" ] && printf '%s %s bghelper\n'  "$bg_helper" "$(bg_ppid "$bg_helper")"
} > "$SCENE/ps-lines"
cat > "$MOCKBG/ps" <<'EOF'
#!/usr/bin/env bash
# ps da cena: as linhas preparadas (pid ppid comm reais dos processos vivos)
ST="${MOCK_DIR:?}"
cat "$ST/ps-lines"
EOF
chmod +x "$MOCKBG/ps"
BGA="$REPO/elite/airootfs/usr/local/bin/craft-bgapps"
STBG="$WORK/state-bgapps"
bg_list() {
  ( export PATH="$MOCKBG:$PATH" MOCK_DIR="$SCENE" XDG_CACHE_HOME="$STBG/cache"
    BGAPPS_TRACE=1 bash "$BGA" list 2>/dev/null )
}
rm -rf "$STBG"; mkdir -p "$STBG"
bg_out="$(bg_list)"; rc=$?
assert_eq "$rc" "0" "E48/bgapps: o verbo list termina 0 (a lista bruta é a porta da forense)"
# (1) a cena montada de verdade (o teste não mente sobre o que construiu):
#     os 6 processos vivos com os comms esperados no papel da cena
assert_grep "$SCENE/ps-lines" '^[0-9]+ [0-9]+ brave$' "E48/bgapps: a cena tem o Brave vivo com ppid real (o teste prova o cenário antes de julgar a cura)"
assert_grep "$SCENE/ps-lines" '^[0-9]+ [0-9]+ pactl$' "E48/bgapps: a cena tem o pactl vivo (o filho do daemon de áudio do rig)"
if printf '%s' "$bg_out" | grep -q 'python3'; then
  fail "E48/bgapps: NENHUMA entrada 'python3' na lista" "python3 entrou — o interpretador não se apresentou pelo script"
else
  ok "E48/bgapps: NENHUMA entrada 'python3' na lista (o comm do interpretador nunca mais é 'programa')"
fi
if printf '%s' "$bg_out" | grep -q 'pactl'; then
  fail "E48/bgapps: NENHUMA entrada 'pactl' na lista" "pactl entrou — o encanamento de áudio voltou a aparecer (matar = matar o roteamento)"
else
  ok "E48/bgapps: NENHUMA entrada 'pactl' na lista (o encanamento de áudio/mídia está na casca)"
fi
if printf '%s' "$bg_out" | grep -qE 'craft-audio-route|craft-dock-gui'; then
  fail "E48/bgapps: os daemons da casa NÃO aparecem (casca craft-*)" "um daemon craft-* entrou na lista — a casca não alcançou o nome resolvido"
else
  ok "E48/bgapps: os daemons da casa NÃO aparecem (o nome resolvido cai na casca craft-* — matar o 'python 3' do menu nunca mais mata o áudio)"
fi
# (2) a denúncia B: o Brave lançado pela dock ENTRA (o pai resolvido é
#     protegido — não é mais candidato que o sombreie)
if printf '%s' "$bg_out" | grep -q '^brave (pid '; then
  ok "E48/bgapps: o Brave ENTRA na lista (lançado pela dock — o pai protegido não o sombreia mais; o dono fecha o Brave de lá)"
else
  fail "E48/bgapps: o Brave ENTRA na lista" "o pai python3 resolvido ainda sombreia — a lista segue cega para o app que o dono quer fechar"
fi
# (3) o app de terceiros com o nome HONESTO (não 'python3')
if printf '%s' "$bg_out" | grep -q '^blueman-applet (pid '; then
  ok "E48/bgapps: o app python de terceiros aparece com o SEU nome (a lista fala a língua do programa)"
else
  fail "E48/bgapps: o app python de terceiros aparece com o SEU nome" "a resolução do cmdline falhou para script relativo/absoluto"
fi
# (4) a sombra com RÉU NOMEADO: o helper é filho do blueman (candidato
#     vivo, comm diferente) — cortado COM a linha no papel
assert_grep "$STBG/cache/elite/menus.log" 'sombra: bghelper \(pid .*\) — filho de blueman-applet' \
  "E48/bgapps: a sombra cortada deixa réu nomeado (QUEM sombreou fica no papel — 'não sei se detecta tudo' tem resposta)"
# (5) o status de 30s NUNCA escreve no papel (a lei do teto E36)
rm -rf "$STBG"; mkdir -p "$STBG"
( export PATH="$MOCKBG:$PATH" MOCK_DIR="$SCENE" XDG_CACHE_HOME="$STBG/cache"
  bash "$BGA" status >/dev/null 2>&1 )
assert_nofile "$STBG/cache/elite/menus.log" "E48/bgapps: o status (30s em loop) NUNCA escreve no menus.log (o trace só nos verbos menu/list — o teto E36 não sangra)"
# ceifa da cena (nada órfão para o próximo teste)
kill "$bg_aro" "$bg_dock" "$bg_blu" 2>/dev/null || true
[ -n "$bg_pactl" ]  && kill "$bg_pactl"  2>/dev/null || true
[ -n "$bg_brave" ]  && kill "$bg_brave"  2>/dev/null || true
[ -n "$bg_helper" ] && kill "$bg_helper" 2>/dev/null || true

phase_end
