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
# runs-on mora no diag-install.yml reutilizado, também 24.04
assert_eq "$(grep -c 'runs-on: ubuntu-24.04' "$BY")" "4" "contrato: build.yml — 4 jobs pinados em ubuntu-24.04 (lint/build/release/verify)"
assert_grep "$BY" 'needs: \[build, verify, verify-install\]' "contrato: release SÓ depois do gate de boot E do gate de instalação (v1.0.5)"
assert_grep "$BY" 'verify-install:' "contrato: job verify-install presente (install-gate no pipeline)"
assert_grep "$BY" 'uses: \./\.github/workflows/diag-install\.yml' "contrato: install-gate reusa o diag-install.yml (workflow_call — zero duplicação)"
assert_grep "$BY" "code=203/EXEC" "contrato: gate verifica 203/EXEC (binários executáveis no live)"
assert_grep "$BY" 'gh workflow run agents\.yml' "contrato: relay dispara mimo/deepseek pós-build"
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
DI="$REPO/.github/workflows/diag-install.yml"
assert_grep "$DI" 'workflow_call:' "contrato: diag-install.yml é workflow reutilizável (chamável como gate)"
assert_grep "$DI" 'sudo unsquashfs' "contrato: unsquashfs com sudo (xattrs exigem root — run #1)"
assert_grep "$DI" '\(linux\|initrd\)\[\[:space:\]\]' "contrato: grep de entradas do grub.cfg casa TAB ([[:space:]])"
# v1.1: kernel único BORE — o pre-flight troca o check do linux.preset (E6b
# aposentado) pelo check do dkms nvidia (E11); o [6b/8] roda o MESMO detector
# de vendor do shellprocess_btrfs (unknown esperado no QEMU) e os 4 contratos
# per-rig são greps no YAML que o Calamares real executa
assert_grep "$DI" 'preset stock PRESENTE \(E6b foi aposentado' "contrato v1.1: diag-install rejeita o preset stock (E6b morto)"
assert_grep "$DI" 'updates/dkms/nvidia' "contrato v1.1: diag-install confere o dkms nvidia pré-compilado (E11)"
assert_grep "$DI" '0x10de\) ELITE_GPU=nvidia' "contrato v1.1: detector de vendor do E10 no gate (nvidia)"
assert_grep "$DI" 'pacman -Rdd --noconfirm nvidia-open-dkms' "contrato v1.1: limpeza AMD do E10 no gate"
assert_grep "$DI" 'gpu-detect\.txt' "contrato v1.1: artifact gpu-detect.txt (no lugar do mkinitcpio-stock.log)"
assert_nogrep "$DI" 'mkinitcpio-stock\.log' "contrato v1.1: artifact do kernel stock sumiu do gate"

# v1.1: estágio AUR do build — brave-bin/pwvucontrol nascem no [elite-local]
assert_grep "$REPO/.ci/build.sh" 'aur_build brave-bin' "contrato v1.1: build.sh compila brave-bin do AUR → elite-local"
assert_grep "$REPO/.ci/build.sh" 'aur_build pwvucontrol' "contrato v1.1: build.sh compila pwvucontrol do AUR → elite-local"
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

# ── 3.K craft-pin: fixar apps na dock (HOME falso, skel real) ──────────
#  O script edita ~/.config/waybar/{config.dock,style.dock.css} do usuário
#  — aqui o $HOME é um scratch com as cópias do skel. O juiz final é o
#  parse JSON (comentários de linha inteira removidos) + diff contra o
#  skel: add/rm em qualquer ordem volta BYTE A BYTE ao estado de fábrica.
PINHOME="$WORK/craft-pin-home"
DKT="$PINHOME/.config/waybar/config.dock"
CST="$PINHOME/.config/waybar/style.dock.css"
SKD="$REPO/elite/airootfs/etc/skel/.config/waybar/config.dock"
SKC="$REPO/elite/airootfs/etc/skel/.config/waybar/style.dock.css"
pin_reset() {
  rm -rf "$PINHOME"; mkdir -p "$PINHOME/.config/waybar"
  cp "$SKD" "$DKT"; cp "$SKC" "$CST"
}
CP() { env HOME="$PINHOME" bash "$REPO/elite/airootfs/usr/local/bin/craft-pin" "$@"; }
pinjson() { sed 's|^[[:space:]]*//.*||' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; }

pin_reset
assert_match "$(CP list)" 'nenhum app fixado' "craft-pin: list em fábrica → nenhum app"
CP add steam $'\uf1b6' Steam steam green >/dev/null
if pinjson "$DKT"; then ok "craft-pin: 1º pin → config.dock parseia como JSON (vírgulas certas)"; else fail "craft-pin: JSON" "config.dock quebrou após o 1º add"; fi
assert_grep "$DKT" '^    "custom/shot",$' "craft-pin: modules-left — shot ganha vírgula, pin entra depois"
assert_grep "$DKT" '^    "custom/pin-steam"$' "craft-pin: pin é o último elemento do array (sem vírgula)"
assert_grep "$DKT" '^  "custom/pin-steam": \{ "format": ' "craft-pin: linha do módulo na seção PINS"
assert_grep "$DKT" '^  \},$' "craft-pin: bloco power fecha com vírgula antes da seção PINS"
assert_grep "$CST" '^#custom-pin-steam \{$' "craft-pin: bloco CSS criado"
assert_grep "$CST" '^  color: @green;$' "craft-pin: cor escolhida aplicada no CSS"
assert_match "$(CP add discord $'\uf392' Discord discord mauve 2>&1)" 'discord.* fixado' \
  "craft-pin: 2º pin aceito"
CP add obs $'\uf03d' 'OBS Studio' obs red >/dev/null
if pinjson "$DKT"; then ok "craft-pin: 3 pins → JSON continua válido"; else fail "craft-pin: JSON 3 pins" "config.dock quebrou com 3 pins"; fi
assert_match "$(CP list)" 'steam' "craft-pin: list mostra steam"
assert_match "$(CP list)" 'OBS Studio' "craft-pin: list mostra tooltip com espaço"
out="$(CP add steam $'\uf1b6' Steam steam 2>&1)" || true
assert_match "$out" 'já está fixado' "craft-pin: duplicata rejeitada com instrução (rm primeiro)"
out="$(CP add teste $'\uf1b6' Teste teste neonpink 2>&1)" || true
assert_match "$out" 'cor .*não existe' "craft-pin: cor fora da paleta Catppuccin rejeitada"
out="$(CP add 'Nome Ruim' $'\uf1b6' Teste teste 2>&1)" || true
assert_match "$out" 'inválido' "craft-pin: nome com espaço/maiúscula rejeitado"

CP rm discord >/dev/null
if pinjson "$DKT"; then ok "craft-pin: rm do MEIO → JSON válido (vírgula migrou)"; else fail "craft-pin: rm meio" "config.dock quebrou no rm do meio"; fi
assert_grep "$DKT" '^  "custom/pin-steam": \{.*\},$' "craft-pin: rm do meio — steam vira o último do bloco (vírgula)"
assert_grep "$DKT" '^  "custom/pin-obs": \{.*\}$' "craft-pin: rm do meio — obs fica sem vírgula"
if grep -q 'pin: discord' "$CST"; then
  fail "craft-pin: bloco CSS removido" "CSS ainda tem o bloco do discord"
else
  ok "craft-pin: bloco CSS do pin removido (com a linha em branco)"
fi
CP rm steam >/dev/null; CP rm obs >/dev/null
if diff -q "$DKT" "$SKD" >/dev/null; then ok "craft-pin: todos removidos → config.dock == skel BYTE a BYTE"; else fail "craft-pin: pristino" "config.dock divergiu do skel após add/rm de tudo"; fi
if diff -q "$CST" "$SKC" >/dev/null; then ok "craft-pin: style.dock.css == skel BYTE a BYTE"; else fail "craft-pin: pristino CSS" "style.dock.css divergiu do skel"; fi

CP add obs $'\uf03d' 'OBS Studio' obs red >/dev/null
CP restore >/dev/null
if grep -q '"custom/pin-obs"' "$DKT"; then
  fail "craft-pin: restore" "obs ainda presente após restore"
else
  ok "craft-pin: restore devolve o estado anterior à última alteração"
fi
out="$(CP restore 2>&1)" || true
assert_match "$out" 'nada para restaurar' "craft-pin: restore sem histórico recusa (rc 1)"

pin_reset
sed -i '/PINS (craft-pin)/d' "$DKT"   # simula skel antigo SEM a seção
CP add code $'\ue70c' 'VS Code' code sky >/dev/null
if pinjson "$DKT"; then ok "craft-pin: skel antigo sem marcador → auto-cura + JSON válido"; else fail "craft-pin: auto-cura" "config.dock quebrou no skel sem marcador"; fi
assert_grep "$DKT" 'PINS \(craft-pin\)' "craft-pin: marcador recriado automaticamente"
assert_match "$(CP reload)" 'waybar não está rodando' "craft-pin: reload sem waybar é gracioso (rc 0)"

# ── 3.L elite_inject_bumped (ELITE-BUMP — build #49: pkgrel 3 componentes) ─
#  A função REAL do .ci/build.sh, extraída por fidelidade (como o extract.sh
#  faz com o elite-tune), em unshare -rm com tmpfs em /var: as escritas em
#  /var/cache/elite-local evaporam com o namespace. vercmp/bsdtar/runuser/
#  makepkg são mockados na frente do PATH — o makepkg-mock valida o pkgrel
#  com a MESMA regra do real ('integer[.integer]'): foi exatamente "pkgrel
#  must be of the form 'integer[.integer]', not 1.1.1" que derrubou a
#  build #49 (o repack falhava, caía no cp clássico que não satisfaz o
#  resolve, 6 rounds quebrados, abort sem ISO).
if [[ $EUID -eq 0 ]] || unshare -r true 2>/dev/null; then
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
  run_bump() { PATH="$MB:$PATH" unshare -rm bash "$BUMPBIN" "$1" "$2"; }

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
  skip "3.L elite_inject_bumped" "unshare -r indisponível (contratos estáticos abaixo valem)"
fi

# contratos estáticos (valem SEM unshare): major+1 no lugar do .1 de 3 componentes
assert_grep "$REPO/.ci/build.sh" 'newrel=\$\(\( brmaj \+ 1 \)\)' \
  "contrato bump: newrel = major da quebrada + 1 (build #49)"
assert_nogrep "$REPO/.ci/build.sh" 'newrel="\$\{nb_verrel##\*-\}\.1"' \
  "contrato bump: a forma '3.1→3.1.1' (pkgrel inválido, makepkg rejeita) não existe mais"

phase_end
