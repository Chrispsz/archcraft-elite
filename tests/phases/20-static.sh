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

# peças: YAML válido (TODOS os workflows vivos — v1.5.2: diag-install
# renomeado p/ verify-install [nomenclatura de debug não vive em pipeline de
# produção]; publish-artifact é load-bearing no release manual;
# publish-packages é o canal diário — v2.11.3 fecha a lista)
for y in build.yml verify-install.yml tests.yml publish-artifact.yml publish-packages.yml; do
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

# v2.10.26/E39 — ASSERT DE MODO 100755 LENDO O INDEX (o item nº 2 do plano
# do ARQUITETURA.md): o [[ -x ]] lê o FILESYSTEM e neste sandbox tudo nasce
# rwxrwxrwx — o guard passa local de graça e é o checkout do CI + o squashfs
# da ISO que herdam o modo do index (a classe do E35.1, que curou o loop
# geral e deixou 4 guardas soltos). O que o CI e a ISO veem é o modo do
# index — é ele que se audita; o filesystem nunca mais decide aqui.
# $1 = caminho relativo ao repo · $2 = nome da peça · $3 = consequência
index_exec() {
  local mode
  mode="$(git -C "$REPO" ls-files -s -- "$1" 2>/dev/null | awk '{print $1; exit}')"
  if [[ "$mode" == "100755" ]]; then
    ok "$2"
  else
    fail "$2" "${3:-modo do index é ${mode:-AUSENTE} — checkout do CI e squashfs herdam 0644 → 203/EXEC no live (curar com git update-index --chmod=+x)}"
  fi
}

# peças v1.5.2: o gate de forense de log — existe, executa e carrega a
# história do projeto como especificação (cada padrão FATAL foi bug REAL
# numa build verde; a v1.4 saiu sem keyring com 5 deles ESCRITOS no log)
LF="$REPO/scripts/log-forensics.sh"
assert_file "$LF" "v1.5.2: scripts/log-forensics.sh existe (gate de forense)"
index_exec "scripts/log-forensics.sh" "v1.5.2: log-forensics.sh executável (modo 100755 do index — v2.10.26/E39)" "bit de execução ausente no index — o CI e a ISO herdam 0644"
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
  # v2.10.10 — E23: a cura do keyring como ROOT. O SERVICE não tem
  # [Install] (ativação EXCLUSIVA do timer — lição do ciclo a3dea28:
  # nenhum .wants de boot target); o TIMER tem [Timer]+[Install] e mora
  # em timers.target.wants (o caminho sem ciclo).
  'elite-keyring-fix.service': {'Unit', 'Service'},
  'elite-keyring-fix.timer':   {'Unit', 'Timer', 'Install'},
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
print('OK 5')
PYEOF
)
assert_eq "$uout" "OK 5" "systemd: 5 units parseiam (3 de sistema + 2 user v1.6.2 — INI válido, seções completas; v2.10.10: + elite-keyring-fix service/timer)"

assert_grep "$U/elite-firstboot.service" '^ExecStart=/' "systemd: elite-firstboot.service ExecStart com caminho absoluto"

# ── v2.10.9 — A LEI DA COERÊNCIA DE HABILITAÇÃO ────────────────────────
# O [Install] da unit diz WantedBy=graphical.target (cura v2.10.7), mas o
# airootfs ainda a pré-habilitava em multi-user.target.wants — o rig (dump
# d33o L403) provou o custo: systemd achou ordering cycle envolvendo
# firstboot+graphical+multi-user e QUEBROU o ciclo apagando o job do
# firstboot (journal -u elite-firstboot: 'No entries'; marker ausente;
# service inactive) — o firstboot NUNCA rodou na 10.7 instalada, a cura Z2
# do XKB nunca foi aplicada. O symlink multi-user era a única ponte
# firstboot↔multi-user sob controle do repo — extinta. Habilitação de
# fábrica agora = o [Install]: graphical.target.wants, e NUNCA mais em
# multi-user.
[[ -L "$U/graphical.target.wants/elite-firstboot.service" ]] \
  && ok "v2.10.9: symlink elite-firstboot em graphical.target.wants (habilitação == [Install])" \
  || fail "v2.10.9: symlink graphical.target.wants/elite-firstboot.service" "não é symlink — unit sem habilitação de fábrica"
[[ ! -e "$U/multi-user.target.wants/elite-firstboot.service" ]] \
  && ok "v2.10.9: elite-firstboot EXTINTA de multi-user.target.wants (a ponte do ciclo do rig d33o L403 morreu)" \
  || fail "v2.10.9: multi-user.target.wants/elite-firstboot.service" "ainda existe — a ponte do ciclo sobreviveu"

# ── v2.10.10 — E23: A CURA DO KEYRING COMO ROOT ────────────────────────
# O MESMO d33o pegou a 2ª doença do firstboot-morto: o craft-fix-keys de
# sessão chama 'sudo -n' sem terminal → "a password is required" (journal
# 23:00:46) → o keyring do pacman NUNCA curou no instalado ("o chaveiro
# não pode ser escrito" + chaves CachyOS desconhecidas = pacman -Syu
# morto = sistema que não atualiza, não permanece na melhor versão).
# A cura: elite-keyring-fix.service (root, oneshot — o script já é
# root-ready: id -u 0 roda direto) puxado EXCLUSIVAMENTE pelo
# elite-keyring-fix.timer em timers.target.wants — o caminho que não
# briga com a transação de boot (nenhum .wants de graphical/multi-user).
assert_grep "$U/elite-keyring-fix.service" '^ExecStart=/usr/local/bin/craft-fix-keys$' "v2.10.10: elite-keyring-fix.service ExecStart = craft-fix-keys (absoluto, root-ready)"
grep -q '^\[Install\]' "$U/elite-keyring-fix.service" \
  && fail "v2.10.10: elite-keyring-fix.service tem [Install]" "unit de timer não deve ter [Install] — ativação exclusiva pelo timer (lei da coerência)" \
  || ok "v2.10.10: elite-keyring-fix.service SEM [Install] (ativação exclusiva do timer)"
assert_grep "$U/elite-keyring-fix.service" '^After=network-online.target$' "v2.10.10: keyring-fix espera a rede (pacman -Sy precisa; sem rede = sem selo = re-tenta)"
[[ -L "$U/timers.target.wants/elite-keyring-fix.timer" ]] \
  && ok "v2.10.10: elite-keyring-fix.timer habilitado em timers.target.wants (o caminho sem ciclo)" \
  || fail "v2.10.10: timers.target.wants/elite-keyring-fix.timer" "ausente — a cura E23 nunca dispararia no instalado"
[[ ! -e "$U/graphical.target.wants/elite-keyring-fix.timer" && ! -e "$U/multi-user.target.wants/elite-keyring-fix.timer" ]] \
  && ok "v2.10.10: keyring-fix EXTINTA de graphical/multi-user .wants (a aresta do ciclo nunca renasce)" \
  || fail "v2.10.10: keyring-fix em .wants de boot target" "a lição do ciclo (d33o L403) proíbe .wants de boot target fora da lei da coerência"
assert_grep "$U/elite-keyring-fix.timer" '^WantedBy=timers.target$' "v2.10.10: [Install] do timer = timers.target (coerência com o symlink de fábrica)"
assert_grep "$U/elite-keyring-fix.timer" '^OnBootSec=120s$' "v2.10.10: timer dispara 2min pós-boot (a cura chega cedo, sem brigar com o boot)"
assert_grep "$U/elite-keyring-fix.timer" '^OnUnitActiveSec=6h$' "v2.10.10: timer re-tenta de 6h em 6h (o guard de 24h do script decide o custo real)"
# craft-dump v2.2: a etiqueta = conteúdo, e o keyring ganha as 3 provas
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'ELITE DUMP v2\.10' "E100→E105 (E30→E90→E98→): craft-dump etiqueta v2.10 (a lei: etiqueta = conteúdo — a v2.10 traz A FOTO DA MÍDIA E DO LOCK [seção 6]; a v2.9 trouxe A FOTO DA PELE [seção 12]; a v2.8 trouxe a dose no papel e a gaveta/lxqt no ps; âncora refrescada viva)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'pubring.gpg' "v2.10.10: dump prova o pubring (a doença do d33o no papel)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'list-keys cachyos' "v2.10.10: dump prova as chaves CachyOS populadas"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'pacman lê o banco: OK' "v2.10.10: dump prova funcional do pacman (o -Syu vivo ou morto nomeado)"

# ── v2.10.11 — E24: A CURA DO DESPERTAR IMEDIATO ────────────────────────
# Prova d33o (dump a4h8): suspend 16:54:49 → retorno 16:54:54 (5s) — o
# dono clicou Suspender e viu "nada aconteceu". /proc/acpi/wakeup com 6
# wake sources USB/PCIe armadas (GP12, GP13, XHC0, SWUS, SWDS, PTXH) e o
# resume errando no xHC do PTXH (USBSTS 0x401, Reinit). O mem_sleep [deep]
# prova S3 real — quem acorda é USB. Cura: regra udev desarma o wakeup de
# TODO controlador USB PCI (class 0x0c03) no add — o PC dorme de verdade
# e acorda pelo botão de power. Ferramenta manual + perícia + dump juiz.
WG="$REPO/elite/airootfs/etc/udev/rules.d/90-elite-wake-guard.rules"
[[ -f "$WG" ]] \
  && ok "v2.10.11: regra udev 90-elite-wake-guard.rules presente (a cura do despertar no add/coldplug)" \
  || fail "v2.10.11: 90-elite-wake-guard.rules" "ausente — o suspend volta a acordar sozinho (a doença do a4h8)"
assert_grep "$WG" 'ACTION=="add"' "v2.10.11: regra E24 atua no add (coldplug cobre o boot, hotplug cobre o encaixe a quente)"
assert_grep "$WG" 'SUBSYSTEM=="pci"' "v2.10.11: regra E24 mira dispositivos PCI"
assert_grep "$WG" 'ATTR\{class\}=="0x0c03\*"' "v2.10.11: regra E24 desarma controladores USB (class 0x0c03) — cirúrgico, sem shotgun"
assert_grep "$WG" 'ATTR\{power/wakeup\}="disabled"' "v2.10.11: regra E24 escreve wakeup=disabled (sem porta de volta do mouse/controlador)"
index_exec "elite/airootfs/usr/local/bin/craft-wake-guard" \
  "v2.10.11: craft-wake-guard presente e executável (status/off/on — o comando manual da cura; modo 100755 do index — v2.10.26/E39)" \
  "ausente ou sem +x no index — o dono fica sem perícia/ajuste manual"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-wake-guard" 'do_set disabled' "v2.10.11: craft-wake-guard off desarma USB (o mesmo gesto da regra udev)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-wake-guard" 'do_set enabled' "v2.10.11: craft-wake-guard on rearma USB (a porta de volta, assumindo o risco E24)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-wake-guard" 'cat /sys/power/mem_sleep' "v2.10.11: craft-wake-guard status mostra o modo real do hardware (deep vs s2idle)"
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/craft-wake-guard" '0x0c00–0x0c07 = USB' \
  "E106/E33: a mentira taxonômica extinta (0x0c00–0x0c07 é SERIAL BUS — FireWire/ACCESS/SSA/USB/Fibre/SMBus/InfiniBand/IPMI; USB é SÓ a 0x0c03 — o comentário volta a mentir, a porteira crava)"
SR="$REPO/elite/airootfs/usr/lib/systemd/system-sleep/elite-sleep-report"
index_exec "elite/airootfs/usr/lib/systemd/system-sleep/elite-sleep-report" \
  "v2.10.11: hook elite-sleep-report presente e executável (perícia do sono no journal; modo 100755 do index — v2.10.26/E39)" \
  "ausente ou sem +x no index — se o sono voltar curto, o dump não nomeia o suspeito restante"
assert_grep "$SR" 'pre)' "v2.10.11: hook elite-sleep-report registra wake sources armadas ANTES de dormir"
# E88 — O SELO ACPI (o papel virou ATO): o dump 20261107 provou o suspend de
# 7 segundos — GP12/GP13/SWUS/SWDS armados na camada ACPI que a regra udev
# da E24 não alcança. O selo desarma TODO *enabled na porta do sono.
assert_grep "$SR" 'E88' "E88: o elite-sleep-report virou ATO (o papel que só nomeava o suspeito agora DESARMA: o suspend de 7s do dump não volta — 'ele sequer suspendeu' curado)"
assert_grep "$SR" 'ELITE_WAKEUP_FILE' "E88: o selo tem seam de teste (a prova funcional do desarme roda sem /proc real — a mesma escola do ELITE_MEMINFO da E74)"
assert_grep "$SR" '\*enabled' "E88: o selo lê o ESTADO antes de desarmar (echo em /proc/acpi/wakeup é TOGGLE — desarmar cego re- armaria o que já estava morto)"

# ── E63 — A VOLTA DA IMAGEM (relato do dono: suspendeu, voltou SEM SINAL
# no monitor — luz vermelha; cliquei Power e o PC desligou). O SUSPEND
# acontece (E60/E61) e o RESUME é a doença: o output morre DESLIGADO no
# DRM com o sistema já de pé. Três caminhos de religar, idempotentes +
# a perícia que nomeia o réu (idle.log + kernel no papel).
RD="$REPO/elite/airootfs/usr/lib/systemd/system-sleep/elite-resume-display"
index_exec "elite/airootfs/usr/lib/systemd/system-sleep/elite-resume-display" \
  "E63: hook elite-resume-display presente e executável (a rede de SISTEMA do resume; modo 100755 do index — lição E54.1)" \
  "ausente ou sem +x no index — o resume sem vídeo fica sem rede de sistema (203/EXEC no live)"
assert_grep "$RD" 'post)' "E63/E88: o hook age no RETORNO do sono E no INSTANTE dele (o pre fotografa o DPMS — a flag dark que decide o ciclo do wake; cada hook um papel, sem briga)"
assert_grep "$RD" 'wlopm --on' "E63: o hook religa os outputs pós-sono (a mesma ferramenta dos braços do usuário — idempotente com eles)"
assert_nogrep "$RD" 'runuser -u' "E88: NENHUM runuser/PAM no hook (a perícia do dump 20261107: o runuser contra user.slice congelado prendia o systemd-suspend 90s até o TimeoutStartSec — Varlink CreateSession UnitAllocationFailed — e a sessão inteira acordava CONGELADA: o 'mouse morto' do dono)"
assert_grep "$RD" 'setpriv --reuid' "E88: o executor sem PAM é o setpriv (reuid/regid diretos — nenhuma sessão logind nasce, nenhum Varlink existe para falhar)"
assert_grep "$RD" 'timeout 3' "E88: TODA chamada de usuário vive dentro de timeout (o compositor que não responde em 3s não recebe a paciência do wake — o hook nunca mais prende o suspend)"
assert_grep "$RD" 'setsid "\$0" waiter' "E88: o waiter DESAPEGADO (o hook sai em <1s — o thaw acontece na hora; a imagem religa DEPOIS do thaw, esperado no cgroup.freeze — o mesmo gesto da sucessora E79)"
assert_grep "$RD" 'cgroup.freeze' "E88: o waiter ESPERA O THAW (falar com user.slice congelado era a doença — a espera é a cura estrutural, não mais a sorte)"
assert_grep "$RD" 'sleep-dark' "E88: a flag dark do pre decide o ciclo (sono ESCURO = off→on invisível E75; sono ACESO = --on direto — zero blink na cara do dono já de pé)"
assert_grep "$RD" 'udevadm trigger --subsystem-match=input' "E88: o lembrete ao seat (os uevents de input atrasados pelo congelamento são re-emitidos — o mouse que o kernel JÁ vê volta ao libinput)"
assert_grep "$RD" 'logger -t elite-resume-display' "E63: o hook é OBSERVÁVEL no journal (o silêncio no resume é o buraco que escondeu o 'sem sinal')"
assert_grep "$RD" 'wayland-\*' "E68: o hook tenta TODOS os sockets wayland-* que existem no runtime (o wayland-0 fixo era aposta — sessão respawnada em wayland-1 ficava FORA da rede)"
assert_nogrep "$RD" 'WAYLAND_DISPLAY="wayland-0"' "E68: o socket NÃO é mais chutado fixo (a fila vem dos sockets que EXISTEM em /run/user — o chute não volta por descuido)"

# ── E75 — O CICLO QUE O --ON SOZINHO NÃO FAZ (o relato recorrente:
#    'suspende, volta e o monitor fica SEM SINAL — PC e periféricos
#    vivos, obrigou a reinicialização forçada'): o wlopm --on em output
#    que o compositor JÁ crê aceso é NO-OP com rc=0 — e no wake esse é
#    o estado comum (o labwc re-habilita na atividade de input que volta
#    com o rebind do elite-resume-usb; o 'Suspender' do menu não apaga
#    antes de dormir). Quando a doença mora no DRM (driver não re-assentou
#    o link — a classe amdgpu/KMS do seção 10), o rc=0 do no-op convive
#    com o monitor morto PARA SEMPRE. A cura é a TROCA REAL DE ESTADO.
CR="$REPO/elite/airootfs/usr/local/bin/craft-rescue-screen"
assert_grep "$RD" 'wlopm --off' "E75: o hook de sistema usa o CICLO (off → 1s → on) — a troca real de estado que força o re-commit do output no DRM e o re-treino do link"
assert_grep "$RD" 'FALHA: wlopm AUSENTE' "E75: o wlopm ausente DEIXA RASTRO no journal (o exit calado escondia a rede inexistente de um rig sem o binário — até a decisão de NÃO agir deixa linha)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" 'ciclo off→on E75' "E75: o screenon do usuário usa o MESMO ciclo do hook de sistema (três caminhos de religar, uma só gramática de cura)"
index_exec "elite/airootfs/usr/local/bin/craft-rescue-screen" \
  "E75: craft-rescue-screen presente e executável (a escotilha SEM reboot — TTY → login → ciclo → volta; o lock do hyprlock sobrevive ao passeio)" \
  "ausente ou sem +x no index — o 'monitor sem sinal' volta a exigir reinicialização forçada (a classe que atravessou E63/E68)"
assert_grep "$CR" 'wlopm --off' "E75: a escotilha repete o MESMO ciclo do E75 (a cura na mão do dono, sem inventar segunda gramática)"
assert_grep "$CR" 'Ctrl\+Alt\+F3' "E75: a escotilha ensina o caminho no próprio corpo (no pânico do 'sem sinal' ninguém abre wiki — o passo-a-passo mora no comando)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'elite-resume-display' "E75: o veredito do hook entra NO PAPEL (o logger vai ao journal GERAL — o tail -u systemd-suspend era cego à rede de sistema; a perícia do 'sem sinal' sem a prova da própria cura)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'sys/class/drm/card' "E75: a tríade status/enabled/dpms dos conectores DRM entra SEMPRE no dump (antes só no fallback sem sessão — na doença 'PC vivo, monitor morto' a sessão ESTÁ de pé e a prova não entrava)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-post-transaction" 'REINICIE' "E75: o kernel novo AVISA na cara de quem rodou o pacman -Syu cru (a pedagogia do reboot deixa de ser exclusiva da porta do craft-update)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-post-transaction" 'kernel-seen' "E75: o carimbo do kernel dispara o aviso UMA vez por troca (a 1ª execução é linha de base — nunca falso REINICIE)"
assert_grep "$REPO/.ci/build.sh" 'elite-post-transaction.hook' "E75: o hook libalpm viaja NO PACOTE (dono ÚNICO — heredoc no build, install em /usr/share/libalpm/hooks; escola elite-adopt)"
assert_grep "$REPO/.ci/build.sh" 'When = PostTransaction' "E75: o hook é PostTransaction Target=\* (toda transação conta — a do próprio craft-update incluída; o bin é inofensivo: zero rede, zero lock)"
assert_grep "$REPO/.ci/build.sh" 'depends=\(bash python wayland wlopm\)' "E75: o wlopm é DEPENDÊNCIA do elite-system (a rede do resume sem o binário era rede imaginária nos rigs que não o tinham)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 25→26 NO MESMO COMMIT' "E75: pkgrel elite-system 25→26 NO MESMO COMMIT (lei E41 — craft-idle, craft-dump e elite-resume-display mudaram de conteúdo; 2 bins + o .hook libalpm são novos; âncora na HISTÓRIA, lição E58/E59)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 26→27 NO MESMO COMMIT' "E75.1: pkgrel elite-system 26→27 NO MESMO COMMIT (lei E41 — elite-ferramentas mudou de conteúdo: a linha morta ITEM='' saiu; o 1.0-26 nunca publicou — o container recusou o wlopm ausente, cura no preflight dos DOIS ramos)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 27→28 NO MESMO COMMIT' "E76: pkgrel elite-system 27→28 NO MESMO COMMIT (lei E41 — craft-pin e craft-pin-pick mudaram de conteúdo: o help não vaza código, o picker fala os três desfechos E36 de verdade e lista o XDG_DATA_HOME do usuário; âncora na HISTÓRIA, lição E58/E59)"

# ── E69 — O DESPERTAR DOS DISPOSITIVOS (relato REAL do dono no 1.0-18:
#    "o suspender volta sem despertar os dispositivos USB — não consigo
#    sequer desbloquear"): a classe 'xHC error in resume, Reinit' (prova
#    a4h8/E24) era latente e o sono diário a acordou. A cura: re-bind dos
#    controladores USB no pós-sono + re-aplicação da política E24.
#    RELATO DE TESTE > PAPEL — o contrato certifica a rede; o rig julga.
RU="$REPO/elite/airootfs/usr/lib/systemd/system-sleep/elite-resume-usb"
index_exec "elite/airootfs/usr/lib/systemd/system-sleep/elite-resume-usb" \
  "E69: hook elite-resume-usb presente e executável (a cura do RETORNO dos dispositivos — modo 100755 do index, lições E54.1/E60.1)" \
  "ausente ou sem +x no index — o resume com USB morto fica sem cura no live (203/EXEC)"
assert_grep "$RU" '\[ "\$1" = "post" \]' "E69/E88: o post é onde o hook cura (o pre DESTE hook fotografa o inventário — a foto precisa do mesmo olho que julga)"
assert_grep "$RU" 'pre)' "E88: o pre fotografa o inventário HID (a prova de morte do wake compara contra ESTA foto — o rebind cego da E69 não descia sem prova)"
assert_grep "$RU" 'unbind' "E69: o re-bind é a re-inicialização DETERMINÍSTICA do controlador (a classe Reinit do a4h8 não depende da boa vontade do driver — o custo em controlador sadio é ~1s de re-enumeracao)"
assert_grep "$RU" 'USB intacto' "E88: o caminho SADIO não paga o martelo (a foto e o presente BATEM = zero rebind — o mouse que morria no rebind de todo wake morre de causa)"
assert_grep "$RU" 'prova de morte' "E88: rebind SÓ COM PROVA (a graça de 3s da re-enumeração natural vem primeiro; o alvejado toca SÓ o controlador hospedeiro do morto — o teclado vivo do vizinho nunca é derrubado pela cura do mouse)"
assert_grep "$RU" 'RESERVA' "E88: o martelo completo da E69 é RESERVA (o alvejado não bastou = a cura antiga desce inteira — nada da cura de antes se perde, tudo passa a ter prova antes)"
assert_grep "$RU" 'disabled' "E69: a política E24 é RE-APLICADA depois do bind (o re-nascer 'enabled' reabriria o despertar sozinho — a doença de volta por efeito colateral do remédio)"
assert_nogrep "$RU" 'set -e' "E69: o hook NUNCA falha o ciclo de sono (set -e morreria no primeiro sysfs ausente — o resume não é lugar de abortar)"
assert_nogrep "$RU" 'runuser' "E88: zero PAM no hook (a casa do elite-resume-display vale aqui: só sysfs/procfs/journal — user.slice congelado não é interlocutor)"
assert_grep "$RU" 'logger -t elite-resume-usb' "E69: o hook é OBSERVÁVEL no journal (rebinds e guardados nomeados — o silêncio no resume é o buraco da lição E63)"
assert_grep "$REPO/.ci/build.sh" 'elite-resume-usb' "E69: o hook viaja NO PACOTE elite-system (a lei E57/E63 — fora dele o rig instalado NUNCA recebe pelo canal)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'xhci' "E69: o réu do USB morto entra NO PAPEL (journal xhci/usb + status do wake-guard — perícia antes de chute)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" "wlopm --on '\*' \|\| rc=\\\$\\?" "E63: o screenon sonda o rc do wlopm em CADA tentativa (o réu do resume fica nomeado no idle.log — o tiro único morreu)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" 're-armada no resume' "E63: o resume RE-ARMA a vigília (o vigia morre no próprio suspend e o braço idle só DEFERE com vigia no ar — o ciclo de sono reintroduzia o bug da E61)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-vigil" 'craft-idle screenon' "E63: o vigia SOBREVIVE ao próprio suspend e religa a tela no retorno (quem chamou o sono é o primeiro usuário de pé no wake)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-power" 'pgrep -x hyprlock >/dev/null 2>&1; do' "E63: o craft-power espera o lock NASCER (o 0.6s fixo era aposta contra o blur de segundos — E47)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-install-stage" 'nvidia-suspend\.service nvidia-resume\.service' "E63: a VRAM preservada (PreserveVideoMemoryAllocations) ganhou os SERVIÇOS que a salvam/restauram — sem eles o resume NVIDIA nasce preto"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'amdgpu\|drm\|fence\|nvrm' "E63: o papel julga o DRIVER no resume (o réu de kernel era invisível — a classe do 'sem sinal' fica nomeada)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'elite/idle\.log' "E63: o idle.log entra NO PAPEL (o rc do wlopm do resume e o rearmamento da vigília são a evidência central)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 17→18 NO MESMO COMMIT' "E68: pkgrel elite-system 17→18 NO MESMO COMMIT (lei E41 — o hook elite-resume-display mudou de conteúdo; âncora na HISTÓRIA, lição E58/E59: o número atual é lei do guard-pkgrel do CI)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 12→13 NO MESMO COMMIT' "E63: pkgrel elite-system 12→13 NO MESMO COMMIT (lei E41 — cinco bins + o hook novo mudaram de conteúdo; âncora na HISTÓRIA, lição E58/E59)"
assert_grep "$REPO/.ci/build.sh" 'files/usr/lib/systemd/system-sleep' "E63: o hook viaja NO PACOTE elite-system (fora dele o rig instalado NUNCA receberia pelo canal — system-sleep nunca foi veículo de adoção)"
assert_grep "$REPO/.ci/build.sh" 'sobreviveu à remoção E57/E92' "E92: a remoção E57 vira VARREDURA com guard de sobrevivente (a lista por nome enferrujou a 3ª vez — o pacote é o ÚNICO dono, o pacstrap recusa não-dono e quem sobreviver ABORTA o build)"

# ── E92 — A ADOÇÃO SEM RECUSA (relato do dono, 08/11): o rig flagrou
#    'elite-sleep-report existe no sistema de arquivos' e o pacman recusou
#    a transação INTEIRA — o --overwrite escopado da casa (E42) cobria só
#    /usr/local/bin + units, e a E90/E91 pôs TRÊS famílias novas no pacote
#    (system-sleep, share/elite, libalpm hooks). A cura estrutural: UMA
#    fonte das famílias (HOUSE_OVERWRITE) usada pelos 4 sites do pacman +
#    a remoção E57 vira varredura no profile. A ferida 'lista fixa
#    enferruja' (E46 bins → E90 hooks → E92 escopo) morre CONTRATADA: o
#    esquecimento seguinte morre aqui, não no rig do dono. ──
CU92="$REPO/elite/airootfs/usr/local/bin/craft-update"
assert_grep "$CU92" 'HOUSE_OVERWRITE=\(' "E92: as famílias da casa nascem de UMA fonte (a lista duplicada à mão em 4 sites era a doença — o escopo velho recusou a transação inteira no rig)"
assert_grep "$CU92" '/usr/lib/systemd/system-sleep/\*' "E92: a família system-sleep está na lista (o réu do relato: elite-sleep-report, unowned da era ISO vs. o sweep do pacote)"
assert_grep "$CU92" '/usr/local/share/elite/\*' "E92: a família share/elite está na lista (hyprlock/fastfetch/docs/src — o payload da E90/E91 que a lista velha nunca viu)"
assert_grep "$CU92" '/usr/share/libalpm/hooks/elite-\*' "E92: a família libalpm está na lista (o hook E75 — o próximo unowned não nasce recusa)"
assert_grep "$CU92" '/etc/systemd/system/elite-\*' "E92: a família das units preservada (o que a casa já cobria segue coberto pela fonte única)"
assert_grep "$CU92" '/usr/local/bin/\*' "E92: a família dos bins preservada (a adoção original da E42 segue de pé pela mesma fonte)"
n_over92="$(grep -c '"${HOUSE_OVERWRITE\[@\]}"' "$CU92" || true)"
assert_eq "$n_over92" "4" "E92: os 4 sites do pacman usam a MESMA lista (canal + semanal + manual com e sem alvo — nenhum escopo escrito à mão para enferrujar)"
assert_nogrep "$CU92" 'run_root pacman.*--overwrite' "E92: NENHUM site carrega escopo inline (a fonte única ou nada — o par à mão era a classe da recusa)"
assert_grep "$REPO/.ci/build.sh" 'airootfs/usr/local/share/elite/fastfetch' "E92: a família share/elite SAI do profile também (o airootfs entregava o config que o pacote agora reclama — um dono por caminho na ISO)"
assert_grep "$REPO/.ci/build.sh" 'remoção E57/E92' "E92: o guard de sobrevivente generalizado (quem sobreviver à varredura ABORTA antes do pacstrap — a lição E57.1 vale para hooks e configs, não só units)"
assert_grep "$REPO/.ci/build.sh" "--overwrite '/usr/lib/systemd/system-sleep/\*'" "E92: o 5º site — o hook elite-adopt (standalone no craft-toplevel velho) leva as famílias novas TAMBÉM (a adoção da ponte recusaria pelo mesmo conflito; a peça 30-unit prova o alcance real no pacman.log)"

# ── E64 — A ATUALIZAÇÃO FINA (os 5 curáveis do AUD-B da auditoria geral,
#    num degrau só): feridas de TEMPO e de REDE no sistema de atualização
#    que o dono aplaudiu — nenhuma estrutural. (1) dose ao ligar com teto
#    próprio + re-armamento; (2) prova de rede ANTES de qualquer
#    transação; (3) sentinela nas TRÊS portas; (4) a semanal pula o live;
#    (5) o keyring-fix tem minutos de parede.
B64="$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.service"
T64="$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.timer"
S64="$REPO/elite/airootfs/etc/systemd/system/elite-sysupdate.service"
K64="$REPO/elite/airootfs/etc/systemd/system/elite-keyring-fix.service"
CU64="$REPO/elite/airootfs/usr/local/bin/craft-update"
assert_grep "$B64" '^TimeoutStartSec=15min$' "E64/AUD-B1: a dose ao ligar tem TETO PRÓPRIO (herdava 90s do system.conf — download lento = dose morta por SIGTERM antes de nascer; o --sistema sempre teve 2h, a diária era a órfã)"
assert_grep "$T64" '^OnUnitInactiveSec=1h$' "E64/AUD-B1: a dose MORTA volta em 1h (OnUnitInactiveSec conta 'deactivated' de rodada viva OU morta — o dia sem cura por um boot apertado morre aqui)"
assert_grep "$S64" '^ConditionPathExists=!/run/archiso$' "E64/AUD-B4: a semanal TAMBÉM pula o live (a doença E59 curada no bootupdate e esquecida na irmã — live usado >1 semana levaria -Syu NA MÍDIA)"
assert_grep "$K64" '^TimeoutStartSec=15min$' "E64/AUD-B5: o keyring-fix tem MINUTOS DE PAREDE (pacman-key de minutos morto aos 90s = selo que nunca nasce, re-tenta eterna de 6h)"
assert_grep "$CU64" 'rede_viva' "E64/AUD-B2: prova de rede ANTES de qualquer transação (curl 8s no db da casa — falha de rede deixa de virar notify CRITICAL a cada boot)"
assert_grep "$CU64" 'releases/latest/download/elite-local\.db' "E64/AUD-B2: a prova bate no MESMO arquivo que o pacman baixa (o db da casa — overridável por ELITE_NET_URL, a escola do LCK/VMARK/ULOG)"
assert_grep "$CU64" 'sentinela_db auto canal' "E64/AUD-B3: a sentinela na porta do CANAL (a dose ao ligar esperava zero e morria calada na briga com o keyring aos 120s = dia inteiro sem dose)"
assert_grep "$CU64" 'sentinela_db auto sistema' "E64/AUD-B3: a sentinela na porta SEMANAL (a mesma briga — agora espera com teto e adia honesta)"
assert_grep "$CU64" 'já estava em dia' "E64: checagem não é notícia (o re-armamento horário multiplica a dose por 24 — sem novidade, ZERO pop-up; notify é a exceção por delta, escola E48)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 13→14 NO MESMO COMMIT' "E64: pkgrel elite-system 13→14 NO MESMO COMMIT (lei E41 — craft-update + 4 units mudaram de conteúdo; âncora na HISTÓRIA, lição E58/E59)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'ELITE DUMP v2\.10' "E100→E105 (E30→E90→E98→): craft-dump etiqueta v2.10 (etiqueta = conteúdo — a foto da mídia e do lock na seção 6; a foto da pele segue na 12; âncora refrescada viva)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'date \+%Y%m%d-%H%M%S' "v2.10.11: dump com segundos no STAMP (fim da colisão de dois runs no mesmo minuto — a doença do a4h8)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'if ! : > "\$OUT" 2>/dev/null; then' "v2.10.11: guard de escrita antes do papel (dump root-owned + rerun sem sudo = recusa clara)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" '90-elite-wake-guard.rules' "v2.10.11: dump prova a regra E24 no papel (seção 10)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'power/wakeup' "v2.10.11: dump prova o wakeup REAL dos controladores USB PCI (a cura julgada no próximo papel)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'elite-sleep-report' "v2.10.11: dump taila o relato do hook system-sleep (quem estava armado no momento de dormir)"

# ── v2.10.11 — E25: A CURA VIVA (o rig se cura SEM reinstalar) ─────────
# Prova: o a4h8 morreu na linha 341 ('CACHE: variável não associada',
# set -u) — as seções 13/14 NUNCA saíram no papel e a E23 segue sem
# veredito. O réu era o typo $CACHE (vs $UCACHE) no bloco dos logs — e a
# doença VIAJOU: estava viva TAMBÉM no v2.3 do repo (linha 381). E o rig
# 10.9 não tinha como renovar a perícia sem reinstalar a ISO. Cura: typo
# extinto do código + craft-dump --update (raw público da main, bash -n
# antes de instalar, .bak do velho, sha256 no terminal) + cura-viva.sh (o
# one-liner do campo: as 4 peças E24+dump na máquina viva, regra udev
# aplicada a quente, wake-guard off imediato, idle.conf do dono intocado).
DUMP="$REPO/elite/airootfs/usr/local/bin/craft-dump"
! grep -v '^[[:space:]]*#' "$DUMP" | grep -q '\$CACHE' \
  && ok "v2.10.11: a doença do a4h8 EXTINTA do código (\$CACHE era typo do \$UCACHE — só vive na história do cabeçalho)" \
  || fail "v2.10.11: \$CACHE vivo no código do craft-dump" "o papel voltaria a morrer no meio (seções 13/14 perdidas — a doença do a4h8)"
assert_grep "$DUMP" '"--update"' "v2.10.11: craft-dump tem o caminho --update (a perícia se renova sem reinstalar)"
assert_grep "$DUMP" 'raw.githubusercontent.com/Chrispsz/archcraft-elite/main' "v2.10.11: --update puxa da main via raw público (sem credencial na máquina do dono)"
assert_grep "$DUMP" 'bash -n "\$TMP"' "v2.10.11: --update valida o que chegou com bash -n ANTES de instalar (nada entra quebrado)"
assert_grep "$DUMP" '\.bak-\${STAMP}' "v2.10.11: --update guarda o velho como .bak-<stamp> (a volta é sempre possível)"
assert_grep "$DUMP" 'sha256sum "\$SELF"' "v2.10.11: --update imprime o sha256 do instalado (auditável no terminal)"
CV="$REPO/scripts/live/cura-viva.sh"
[[ -f "$CV" ]] \
  && ok "v2.10.11: cura-viva.sh presente (o one-liner do campo — rig 10.9/10.10 se cura sem reinstalar)" \
  || fail "v2.10.11: scripts/live/cura-viva.sh" "ausente — o dono ficaria refém de reinstalar a ISO para ter dump completo + E24"
# v2.10.26/E39 — a peça JURAVA o modo do git (a mensagem citava update-index
# e core.fileMode) mas o [[ -x ]] lia o filesystem — mentia igual aos outros
# 3: neste sandbox 777 passava de graça, e o réu real (modo do index) nunca
# era auditado. Agora lê o index como jura.
index_exec "scripts/live/cura-viva.sh" \
  "v2.10.11: cura-viva.sh executável (o modo executável via git update-index — a lição do E24-hotfix; modo 100755 do index — v2.10.26/E39)" \
  "index sem 100755 para o cura-viva (0644 no index OU git não operou no repo — cf. safe.directory) — a lição do E24-hotfix se repete"
assert_grep "$CV" 'raw.githubusercontent.com/Chrispsz/archcraft-elite/main' "v2.10.11: cura-viva baixa da main via raw público (sem credencial na máquina do dono)"
assert_grep "$CV" '90-elite-wake-guard.rules' "v2.10.11: cura-viva instala a regra E24 (a cura do despertar no rig velho)"
assert_grep "$CV" 'elite-sleep-report' "v2.10.11: cura-viva instala o hook system-sleep (a perícia do sono no rig velho)"
assert_grep "$CV" 'udevadm trigger' "v2.10.11: cura-viva aplica a regra a quente (a cura vale NA HORA, sem reboot)"
assert_grep "$CV" 'craft-wake-guard off' "v2.10.11: cura-viva desarma o USB no fim (o mesmo gesto que a regra fará em todo boot)"
assert_grep "$CV" 'idle.conf do dono (NÃO é tocado|não foi tocado)' "v2.10.11: cura-viva declara o limite (LOCK/OFF/SUSPEND_MIN do dono intocados — nada às escondidas)"
assert_grep "$CV" 'bash -n' "v2.10.11: cura-viva prova cada peça com bash -n antes de instalar"

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
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'pacman_s cachyos-settings cachyos-ananicy-rules ananicy-cpp' "v2.2: elite-tune [1] instala exatamente o booster único (fim da linha em ananicy-cpp) — E37: via pacman_s (rc real no epílogo)"

# ── peças: preset mkinitcpio do BORE (o initramfs do live) ─────────────
PR="$REPO/elite/airootfs/etc/mkinitcpio.d/linux-cachyos-bore.preset"
assert_grep "$PR" "^ALL_kver='/boot/vmlinuz-linux-cachyos-bore'$" "preset: ALL_kver aponta o BORE"
assert_grep "$PR" '^archiso_image="/boot/initramfs-linux-cachyos-bore\.img"$' "preset: imagem archiso do BORE"

# ── peças: configs embarcadas (o tuning assado na ISO) ──────────────
SC="$REPO/elite/airootfs/etc/sysctl.d/99-elite.conf"
for k in 'vm\.swappiness' 'vm\.vfs_cache_pressure' 'vm\.max_map_count' \
         'vm\.page-cluster' 'vm\.watermark_boost_factor' 'vm\.watermark_scale_factor'; do
  assert_grep "$SC" "^${k} = " "sysctl: $k presente (gaming)"
done
# ── v2.10.26/E38 — EFICIÊNCIA: o repositório SteamOS/Fedora COMPLETO ────
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'vm\.page-cluster = 0' "E38: o espelho write_elite_sysctl carrega o trio zram (overlay e elite-tune NÃO divergem — a doença do swappiness 150×180 nunca mais)"
PSV="$REPO/elite/airootfs/etc/modprobe.d/99-elite-powersave.conf"
assert_grep "$PSV" 'snd_hda_intel power_save=1' "E38: áudio HDA dorme entre os sons (power_save=1 — default Fedora/Ubuntu; ~0,5-1W em idle)"
assert_grep "$PSV" 'iwlwifi power_save=1' "E38: Wi-Fi Intel em powersave de firmware (audit E38: o knob NÃO existia em lugar nenhum)"
assert_nogrep "$REPO/elite/airootfs/etc/skel/.config/waybar/config.top" '"interval": 10,' "E38: o bgapps não acorda a cada 10s (interval 30 — o maior fork-poll da sessão cai 3×; a reescrita awk fica no plano do EFICIENCIA.md)"
UV="$REPO/elite/airootfs/etc/udev/rules.d/60-io-elite.rules"
assert_grep "$UV" 'ATTR\{queue/scheduler\}="none"' "udev: scheduler none p/ NVMe/SSD"
assert_grep "$UV" 'ATTR\{queue/scheduler\}="bfq"' "udev: bfq p/ HDD (rotacional)"
ZR="$REPO/elite/airootfs/etc/systemd/zram-generator.conf"
assert_grep "$ZR" '^\[zram0\]$' "zram: seção [zram0]"
assert_grep "$ZR" 'compression-algorithm = zstd' "zram: compressão zstd"

# ── peça v2.11.3: harness de agentes de IA fora do repo (infraestrutura
#    estranha ao produto — a revisão de código é a suíte de contratos) ──
assert_nofile "$REPO/.github/workflows/agents.yml" "v2.11.3: agents.yml removido (auditoria por IA fora do repositório)"
assert_nofile "$REPO/agents/run.ts" "v2.11.3: agents/ removido (nada de relay de IA no repo)"
assert_nofile "$REPO/docs/AGENTS.md" "v2.11.3: docs/AGENTS.md removido"
assert_nogrep "$REPO/README.md" 'Token Harbor' "v2.11.3: README sem menção a infra de IA externa"

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
# TODOS os menus (5 desde o nº 9/E65 — o craft-logout virou wrapper do
# craft-power e saiu da lista) — fechar menu NUNCA é erro (o rig flagrou
# "erro 1" no fechamento normal da Rede; mesma classe do 143 da v2.3.5).
for m in craft-power craft-connect craft-bgapps craft-pin-pick craft-idle; do
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

# ── v2.10.16 · E29 — a classe do pacman-init morre de vez ──
# run 41070218496 (verify da v2.10.15): o daemon-reload da transação do
# keyring (elite-keyring-fix, root, sem selo no live) REINICIOU o
# pacman-init no meio do lock do gnupg — 3 retries colidiram todas e o
# StartLimit estourou. Cura em 2 camadas + selo que mata a transação
# redundante no nascimento.
assert_file "$REPO/elite/airootfs/usr/local/bin/craft-keyring-wait" "pacman-init: guarda do lock existe (restart espera a transação em vez de colidir)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-keyring-wait" '#!/bin/sh' "craft-keyring-wait: POSIX sh (ExecStartPre chama direto)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-keyring-wait" 'pacman-key' "craft-keyring-wait: espera pacman-key em voo (a janela de colisão real)"
assert_grep "$REPO/elite/airootfs/etc/systemd/system/pacman-init.service.d/10-elite-retry.conf" 'ExecStartPre=/usr/local/bin/craft-keyring-wait' "pacman-init: ExecStartPre espera o lock (a cura da classe E29)"
assert_grep "$REPO/elite/airootfs/etc/systemd/system/pacman-init.service.d/10-elite-retry.conf" 'StartLimitIntervalSec=600' "pacman-init: janela de retry 600s (vidas sobrevivem a populate longo)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'keyring-refresh.stamp' "keyring: selo do root semeado no build (live não re-cura o que nasceu curado — run 41070218496)"
assert_grep "$REPO/scripts/apply-overlay.sh" '/usr/local/bin/craft-keyring-wait' "apply-overlay: craft-keyring-wait registrado no file_permissions (senão 203/EXEC no live)"

# ── v2.10.16.1 · E29.1 — as duas verdades que a 2ª verify vermelha expôs ──
# run 41078548156: o selo em /root NUNCA foi lido (o serviço systemd roda
# sem $HOME — o guard velho lia /.local/state) e a transação provou 4min46s
# de wall (o teto de 240s do guarda não podia vencer a corrida). Cura:
# caminho absoluto para root + selo no skel + teto 420s + guarda no timer.
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-fix-keys" 'STAMP="/root/.local/state/elite/keyring-refresh.stamp"' "craft-fix-keys: selo do root é caminho ABSOLUTO (serviço systemd roda sem \$HOME — run 41078548156)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" '/etc/skel/.local/state/elite' "keyring: selo também no skel (o home do liveuser nasce dele — camada de sessão também descansa no live)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-keyring-wait" '84' "craft-keyring-wait: teto 420s (> transação provada de 4min46s — o guard vence a corrida)"
assert_grep "$REPO/elite/airootfs/etc/systemd/system/elite-keyring-fix.service" 'ExecStartPre=/usr/local/bin/craft-keyring-wait' "elite-keyring-fix: timer espera transação de sessão em voo (duas curas não colidem)"


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
# E106 — a v4 corre no MOTOR craft-menu (a probe CAPS com cache selado mora
# LÁ — o picker cru que forkava 'fuzzel --help' POR CLIQUE morreu com o laço)
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin-pick" 'craft-menu --title' "v2.10.5→E106: o picker corre no motor com probe própria (a lei 'flag nova que mata' seguiu para o craft-menu — CAPS cacheadas por stat, zero fork de prova por clique)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-rollback" "grep -q -- '--anchor'" "v2.10.5: rollback prova --anchor (mesma lei)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin-pick" 'Hidden=true' "v2.10.5: picker respeita Hidden (a lei XDG é dupla)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin-pick" 'pt_BR' "v2.10.5: picker fala o nome da gente (Name[pt_BR] antes do genérico)"

# E76 — ÁREA 3 DA ROTAÇÃO (GUIs fuzzel): o picker fala a verdade e enxerga
# o mesmo mundo que o irmão resolve.
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin-pick" '\|\| addrc=\$\?' \
  "E76: o add do picker usa a gramática '|| addrc=\$?' (a forma 'out=\$(…); addrc=\$?' morria no set -e com rc≠0 do craft-pin — o desfecho 'já estava na dock' do E36 era inalcançável; prova FUNCIONAL no 30-unit 3.O)"
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/craft-pin-pick" '\); addrc=\$\?' \
  "E76: a forma morta 'out=\$(…); addrc=\$?' saiu do picker (o ponto-e-vírgula era a assinatura da morte calada)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin-pick" 'local/share\}/applications' \
  "E76: o inventário do picker inclui o XDG_DATA_HOME do USUÁRIO PRIMEIRO (a MESMA precedência do resolve do craft-pin — .desktop do usuário, ex. AppImage do appimagelauncher, é fixável pelo mouse; o comentário 'overrides primeiro' vira verdade)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-pin" 'awk .NR==1\{next\}' \
  "E76: o help do craft-pin imprime ENQUANTO é comentário (o range mágico '2,22p' vazava PINS_DIR/DESKTOP_DIRS/ensure_file cru; prova FUNCIONAL no 30-unit 3.O)"

# F. bateria: /sys puro (upower saiu da equação — e a mensagem amigável é alcançável):
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/craft-bat" 'command -v upower' "v2.10.5: craft-bat sem upower (dep que não estava na ISO)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bat" '/sys/class/power_supply' "v2.10.5: craft-bat lê o kernel direto (o código concorda com o docs)"
assert_grep "$SK/.config/waybar/config.top" '"battery"' "v2.10.5: o notebook tem assento na barra (módulo battery — clique dá o resumo)"

# G. o conf do idle sobrevive ao menu (suspend opt-in não morre no rewrite):
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" 'SUSPEND_MIN=%s' "v2.10.5: idle.conf regravado COM o suspend do usuário (os dois caminhos)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" 'LOCK_MIN:-.*\*\[!0-9\]\*\) LOCK_MIN=5' "E43: valor lixo no conf não mata o daemon (sanidade antes do -eq; a fábrica do gesto único responde)"

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
assert_grep "$SK/.config/swaync/config.json" '"when-available"' "E43: image-visibility no enum REAL do swaync 0.12.x (man swaync.5.scd:151) — o v2.10.5 aqui certificava a sintaxe MORTA 'when-there...'; o warning de deserialização em TODO boot era o sintoma (dump tg0b1)"

# L. pacotes: a dependência jurada existe de facto:
assert_grep "$REPO/elite/packages.add" '^libpulse$' "v2.10.5: libpulse explícito (pactl/volumes + módulo pulseaudio da waybar)"
# v2.10.5 acreditava que 'networkmanager-sstp' era o nome REAL e baniu o
# 'network-manager-sstp' como 'no-op silencioso'. O DUMP nl3z FALSIFICOU:
# o rig INSTALADO carrega network-manager-sstp 1.3.2-7.1 (seção 13) — a
# v2.10.5 trocou a grafia certa pela errada e o plugin cruzou TODOS os
# builds desde então. v2.10.14: as DUAS grafias vedadas (a classe de
# nome errado = remoção silenciosa não renasce em nenhuma direção).
assert_grep "$REPO/elite/packages.remove" '^networkmanager-sstp$' "v2.10.14: a grafia v2.10.5 segue vedada (as duas formas do nome ficam na lista)"
assert_grep "$REPO/elite/packages.remove" '^network-manager-sstp$' "v2.10.14: a grafia que o rig PROVOU real entra no debloat (a v2.10.5 a chamava de 'no-op silencioso' e o plugin chegou ao rig instalado — falsificado pelo papel)"

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
# v2.10.8 — o gate em DUAS INSTÂNCIAS (o d33o arbitrou: kernel 'freeze mem
# disk' + mem_sleep [deep] com can-suspend ≠ yes — o logind calado não nega
# mais o que o kernel prova; nem logind nem kernel = recusa honesta mantida)
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-power" '/sys/power/state' "v2.10.8: a capacidade do KERNEL entra no gate (logind calado/negativo + mem presente = TENTA — o erro real vira toast, nunca silêncio)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-power" 'kernel-mem=' "v2.10.8: a divergência logind×kernel fica NO LOG (a prova da próxima perícia nasce no momento do clique)"

# Q. o selo do fix-keys só come com a cura feita:
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-fix-keys" 'keyring não atualizado' "v2.10.5: sem rede não escreve selo de 24h (o script não mente)"

# R. E26 (v2.10.12) — AS NOVE CURAS DO PAPEL COMPLETO (dump nl3z + log 84wl):
#    o primeiro papel COMPLETO da casa (v2.4, 1326 linhas, FIM presente)
#    nomeou o que nenhuma simulação viu — cada cura com o seu contrato.
# R1. O SUSPEND MORTO NO ESCURO (o réu da década): set -e + loginctl sem
#     o verbo can-suspend ('Unknown command verb' no rig, systemd novo) =
#     morte ANTES do lock/suspend/aviso — 'clico e nada acontece'.
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-power" 'can="\$\(loginctl can-suspend 2>/dev/null\)" || can=""' "v2.10.12: a atribuição sobrevive ao verbo ausente (set -eu matava o script no rig nl3z ANTES de qualquer ação — o || can='' torna o vazio caminho previsto)"
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/craft-power" 'can="\$\(loginctl can-suspend 2>/dev/null\)"$' "v2.10.12: a forma sem guarda EXTINTA (a linha nua sob set -e era a morte calada)"
# R2. O -i QUE PEDIRIA SENHA: suspend-ignore-inhibit não estava na regra
#     polkit (default upstream = auth_admin_keep) — a cura A reabriria a
#     porta pro prompt de senha a cada suspender.
assert_grep "$REPO/elite/airootfs/etc/polkit-1/rules.d/49-elite-desktop.rules" 'org.freedesktop.login1.suspend-ignore-inhibit' "v2.10.12: a variante ignore-inhibit é da família local+ativo=YES (o -i do craft-power não pode virar prompt de senha)"
# R3. O FANTASMA DO INSTALADOR: cleanup remove o .desktop mas o CACHE do
#     nwg-drawer desenha arquivo morto; abif.desktop era peso morto extra.
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'abif\.desktop' "v2.10.12: o cleanup arranca também o abif.desktop (peso morto do live que sobrevive ao unpackfs)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'cache\.db' "v2.10.12: o cache do nwg-drawer é purgado no cleanup (o 'instalador ficando nos aplicativos' era o drawer desenhando arquivo morto)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'FANTASMA: cache do drawer' "v2.10.12: o papel nomeia o fantasma (cache do drawer listando calamares) se ele voltar"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" "ls /usr/local/share/applications/" "v2.10.12: o papel lista os .desktop locais (o suspeito do menu do dono fica nomeado no papel)"
# R4. O NOME ERRADO DO FUZZEL (já coberto no 40 — aqui o eco da suíte estática):
assert_grep "$REPO/elite/airootfs/etc/skel/.config/fuzzel/fuzzel.ini" 'exit-on-keyboard-focus-loss=yes' "v2.10.12: a opção com o nome que o fuzzel conhece (o próprio comentário v2.4.0 citava o nome certo)"
# R5. A LÓGICA DO IDLE HONESTA: etiquetas nomeiam o que fazem + o knob do
#     suspender existe (o dono mudou 'tempo de tela' e a tela TRAVOU).
#     E46 — o menu de 13 itens virou DUAS PORTAS nomeadas ('organiza
#     melhor o de tempo de idle e etc', o dono): a porta diz o que
#     controla E mostra o valor ATUAL; o gesto único LOCK=OFF segue lei.
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" 'Tela: trava e apaga — \$lock_txt' "E46: a porta da TELA diz o que controla E mostra o valor atual (a parede de 13 itens morreu; o gesto único LOCK=OFF da E43 segue lei nos dois níveis)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" 'Suspender após o idle' "E46: a porta do SUSPENDER tem nome que se lê (v2.10.12: o knob era fixo e invisível; v2.10.12/E43: etiqueta honesta — agora em porta própria)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" "'Nunca'\) +SUSPEND_MIN=0" "E46: suspender 'Nunca' = 0 (o start v2.3.5 já suportava — agora é escolha do dono na porta própria; o espaçamento não é peça)"
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/craft-idle" 'OFF_MIN=\$\(\(mins \+ 5\)\)' "E46: o fallback de terminal aprendeu o gesto único (OFF=mins+5 era a janela 'travada e acesa' que a E43 matou no menu — sobrevivia no terminal; espelho E33 morto)"
# R6. O CHAVEIRO GNOME QUE O PAM JAMAIS DESBLOQUEIA: bootstrap com senha
#     vazia corria na frente no sistema COM senha (gkr-pam 'couldn't
#     unlock' em todo login — journal 22:31:35 do nl3z).
assert_grep "$REPO/elite/airootfs/etc/skel/.config/labwc/autostart" '/run/archiso.*login\.keyring|login\.keyring.*run/archiso|SÓ NO LIVE' "v2.10.12: o bootstrap do keyring vazio é do LIVE (no instalado o PAM cria com a senha do login)"
# R7. O RUÍDO DO SUDO DE SESSÃO (journal 22:31:36 'a password is
#     required'): a camada de sessão só age no live; no instalado quem
#     cura é o serviço root (E23).
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-fix-keys" '"\$\(id -u\)" -ne 0.*run/archiso' "v2.10.12: a sessão instalada não tenta sudo no escuro (o elite-keyring-fix root é o curandeiro; o journal do rig fica limpo)"
# R8. A CORRIDA DO /proc (bars.log ×4 'Processo inexistente'): redirect
#     falha no shell do pipeline ANTES do 2>/dev/null do tr alcançar.
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bgapps" '\( tr .*/proc/.pid/environ.*\) 2>/dev/null' "v2.10.12: a corrida do processo morrendo engolida no subshell (o erro era do SHELL do redirect, não do tr)"
# R9. A E23 GANHA CURANDEIRO VISÍVEL NO PAPEL (o nl3z não mostrou UM
#     elite-keyring — o veredito da cura precisa ver quem cura):
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'elite-keyring-fix\.timer' "v2.10.12: a seção 5 mostra o timer da E23 (a cura estava invisível no papel)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'ELITE DUMP v2\.10' "E100→E105 (E30→E90→E98→): o papel é v2.10 (etiqueta = conteúdo — a v2.9/E100: A FOTO DA PELE [home vs mestre: sha256 + 1ª linha + veredito na seção 12] segue viva — e a v2.10 soma A FOTO DA MÍDIA E DO LOCK na seção 6 (o barramento MPRIS nomeia o fantasma; o lock.log assina o nascimento) — o estado nunca mais anda às cegas; a v2.8/E98 trouxe a dose no papel e a gaveta/lxqt no ps; âncora refrescada viva)"

# ── v2.10.18 · E30 — o papel p6aw (1325 linhas) + as fotos do dono ─────────
# O rig real provou o que o QEMU não vê: bell misterioso (wall do firstboot
# às 16:14:45), som saindo pelo SINK FANTASMA do microfone USB (fifine),
# DOIS swayidle vivos, hyprlock 'got yeeten' vivo com a sessão destravada,
# 3 toasts 'Encerrado' (inclusive do próprio notify-send), wpctl cortado em
# head -30 (o réu quase escapou do papel), player sem descobribilidade.

# A. O BELL MISTERIOSO MORRE: nenhuma invocação de wall sobra no elite-tune
#    (o broadcast de root@archpc às 16:14:45 = o MESMO segundo do 'Finished
#    elite-firstboot' no journal do p6aw). NVIDIA segue com toast na sessão.
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'wall "' "E30: nenhum wall no elite-tune (o bell de terminal morre na origem — dump p6aw 16:14:45 = Finished elite-firstboot)"
assert_grep  "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'notify-send -a .Elite. -u critical' "E30: NVIDIA mantém o aviso REAL na sessão gráfica (toast crítico, não TTY)"

# B. ÁUDIO: o roteador existe, é event-driven e a classe proibida é dupla
#    (pt+en — o sink do rig era 'fifine Microphone', inglês)
assert_file  "$REPO/elite/airootfs/usr/local/bin/craft-audio-route" "E30: craft-audio-route existe (som saindo pelo microfone = sink fantasma provado no dump p6aw)"
assert_grep  "$REPO/elite/airootfs/usr/local/bin/craft-audio-route" '#!/usr/bin/env python3' "E30: roteador é python3 (JSON do pactl parseado de verdade)"
assert_grep  "$REPO/elite/airootfs/usr/local/bin/craft-audio-route" 'pactl., .subscribe.|"pactl", "subscribe"' "E30: roteador é EVENT-DRIVEN (pactl subscribe — zero polling)"
assert_grep  "$REPO/elite/airootfs/usr/local/bin/craft-audio-route" '-f., .json' "E30: roteador lê pactl -f json (parse estrutural, não regex frágil)"
assert_grep  "$REPO/elite/airootfs/usr/local/bin/craft-audio-route" 'microfone|microphone' "E30: classe proibida cobre pt+en (o réu p6aw era 'fifine Microphone')"
assert_grep  "$REPO/elite/airootfs/usr/local/bin/craft-audio-route" 'set-default-sink' "E30: BT/USB novo assume o som (o pedido do dono: conectou, trocou)"
assert_grep  "$REPO/elite/airootfs/usr/local/bin/craft-audio-route" 'set-sink-port' "E30: fone no MESMO sink muda a PORTA (jack com detecção)"
assert_grep  "$REPO/elite/airootfs/usr/local/bin/craft-bars" 'craft-audio-route' "E30: roteador sob a supervisão da família (morreu, volta em ≤5s)"
assert_nogrep "$REPO/elite/airootfs/etc/skel/.config/labwc/autostart" '^[[:space:]]*craft-audio-route[[:space:]]*&' "E30/v2.10.6: UM SÓ lançador (craft-bars) — a corrida fork/exec do idle não renasce"
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/craft-update" 'x craft-audio-route' \
  "E106/E48: o refresh de sessão NUNCA volta ao -x (o comm do daemon é 'python3' — shebang env — o -x JAMAIS casou e o roteador envelhecia no update; a forma é a -f do supervisor)"

# C. LOCK/IDLE: as corridas do dump morrem
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-lock" 'pkill -x hyprlock' "E30: instância única do locker (o 'got yeeten'/pid 3666 fantasma do bars.log)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" 'idle-start.lock' "E30: MUTEX do spawn do idle (DOIS swayidle vivos no p6aw: pid 937 + 21282)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" '/proc/\\?\\\$lpid/comm|/proc/\$lpid/comm' "E30: o mutex distingue spawn em voo de daemon vivo (restart legítimo prossegue)"

# D. NOTIFICAÇÕES: encerrar fica mudo; o encanamento sai da lista
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/craft-bgapps" "'Encerrado'" "E30: o toast 'Encerrado' morre (3 toasts na foto do dono — a janela sumindo É o feedback)"
assert_grep  "$REPO/elite/airootfs/usr/local/bin/craft-bgapps" 'notify-send\*' "E30: notify-send sai da lista do killer (avisou a morte do próprio aviso — pid 11463/11464)"
assert_grep  "$REPO/elite/airootfs/usr/local/bin/craft-bgapps" 'tumblerd\*' "E30: serviços dbus-ativados saem da lista (matar é inútil — renascem)"

# D2. A SPEC UNIFICADA DO DONO (06/nov) — as três curas do dia
#     (1) crashpad fora da lista de PROGRAMAS (o guard --type= não o via —
#         o crashpad_handler é binário PRÓPRIO sem a flag; órfão virava
#         "programa" fantasma cujo fecho não fecha navegador nenhum)
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bgapps" "grep -q -e . --type=. -e .crashpad." "06/nov/spec: o guard do Chromium cobra crashpad PELO NOME (a spec: 'detecta apenas os subprocessos do Chrome Crashpad' — o fantasma sai da lista)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bgapps" 'O CRASHPAD NÃO LEVA --type=' "06/nov/spec: a cura tem PONHEIRO no fonte (a lição E33 do craft-dump v2.6 — o comentário do guard antigo jurava crashpad excluído e o código não excluía)"
#     (2) a GRAÇA DO SNAPSHOT na dock (o 'pisca, some e reaparece'): 1 LIST
#         falho não derruba o último snapshot — derrubar fazia o marcador
#         apagar e reacender no tick seguinte
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-gui" '_tl_miss' "06/nov/spec: a dock conta as falhas seguidas do LIST (a graça do snapshot — o flap de um tick vira invisível)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-gui" 'snapshot anterior segurado \(graça\)' "06/nov/spec: a graça deixa RASTRO no log (recusa nunca é silêncio — mesmo a cortesia de 2 ticks)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-gui" 'self\._tl_miss = 0' "06/nov/spec: o sucesso ZERA o contador de falhas (a morte real continua assumida na mesma cadência — a graça não vira cegueira)"
#     (3) o rice entrega o SSD da família (a decoração ÚNICA — Brave/imv)
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-rice" '20-elite-ssd\.xml' "06/nov/spec: o rice entrega o fragmento SSD ao lado do dos jogos (a decoração é UMA em todo o desktop)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-rice" 'CHANGED' "06/nov/spec: o reconfigure dispara se QUALQUER fragmento foi escrito (idêntico e recusado não reconfiguram — o labwc relê só com entrega nova)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-rice" 'brave-browser\|chromium' "06/nov/spec: a regra do SSD mira a família do relato (o dono abriu o Brave e o imv nus — os dois entram)"

# E. PAPEL COMPLETO: wpctl sem o head que escondeu o réu
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'wpctl status \| head' "E30: o dump NUNCA mais corta o wpctl (o head -30 escondeu Sinks/Sources do p6aw)"

# F. PLAYER: descobribilidade + segundos em tempo real (custo = leitura
#    DBus interna, zero fork — a resposta honesta à pergunta do dono)
assert_grep "$REPO/elite/airootfs/etc/skel/.config/waybar/config.top" '"interval": 1' "E30: mpris com segundos em tempo real (interval 1 = 1 leitura DBus interna/s, zero fork)"
assert_grep "$REPO/elite/airootfs/etc/skel/.config/waybar/config.top" 'on-scroll-up' "E30: scroll troca faixa (passar/retroceder sem adivinhar botões)"
assert_grep "$REPO/elite/airootfs/etc/skel/.config/waybar/config.top" 'tooltip-format' "E30: a barra DIZ os controles (o dono descobriu meio/dir por sorte)"

# G. CAPTURA RÁPIDA no menu (pedido explícito do dono) — binário real na ISO
assert_grep "$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml" 'Captura de tela' "E30: captura rápida no menu do desktop (o dono pediu botão)"
assert_grep "$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml" 'command="craft-shot"' "E30: o item lança o craft-shot (contrato v1.6.3: binário real, modo região = default)"

# H. BRAVE com os botões da casa: o flag que forçava CSD morre (SSD do labwc)
assert_nogrep "$REPO/elite/airootfs/etc/skel/.config/brave-flags.conf" 'WaylandWindowDecorations' "E30: fim do CSD forçado (o labwc desenha SSD igual às outras janelas — os botões macOS do foot)"
assert_grep  "$REPO/elite/airootfs/etc/skel/.config/brave-flags.conf" 'UseOzonePlatform' "E30: Wayland nativo do Brave preservado (só a decoração muda)"

# I. O INSTALADOR MORRE ANTES DO LOGIN (o dono clicou no fantasma às 16:12:21;
#    o firstboot removeria às 16:14:4x — a janela de corrida vira impossível)
assert_file "$REPO/elite/airootfs/usr/local/bin/elite-sweep" "E30: elite-sweep existe (varredura pré-login dos atalhos de instalador)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-sweep" 'run/archiso' "E30: o sweep NUNCA toca no live (o instalador é legítimo lá)"
assert_grep "$REPO/elite/airootfs/etc/systemd/system/elite-sweep.service" 'Before=display-manager.service' "E30: o sweep corre ANTES do SDDM (nenhum menu enxerga o fantasma)"
assert_file "$REPO/elite/airootfs/etc/systemd/system/multi-user.target.wants/elite-sweep.service" "E30: sweep habilitado de fábrica (symlink = o que o systemctl enable faria)"

# J. A CURA-VIVA E30 (o rig v2.10.17 do dono se cura SEM reinstalar — escola E25/E26)
assert_grep "$REPO/scripts/live/cura-e30.sh" 'raw.githubusercontent.com/Chrispsz/archcraft-elite/main' "E30: cura baixa da main via raw público (sem credencial)"
assert_grep "$REPO/scripts/live/cura-e30.sh" 'py_compile' "E30: a peça python é provada com py_compile (bash -n não julga python)"
assert_grep "$REPO/scripts/live/cura-e30.sh" 'WaylandWindowDecorations' "E30: a cura remove o flag CSD do rig (o Brave ganha os botões da casa)"
assert_grep "$REPO/scripts/live/cura-e30.sh" 'pkill -x swayidle' "E30: a cura mata os DOIS swayidle (o mutex renasce um)"
assert_grep "$REPO/scripts/live/cura-e30.sh" 'run/user/' "E30: a cura resolve a sessão por /run/user (o sudo reseta HOME — lição E29.1)"
assert_grep "$REPO/scripts/live/cura-e30.sh" 'NÃO é morto aqui' "E30: a cura declara o limite (matar o locker com a tela travada destravaria a sessão)"

# R10. A CURA DE CAMPO DA E26 (a escola cura-viva: o rig velho se cura SEM reinstalar):
CV2="$REPO/scripts/live/cura-e26.sh"
[ -f "$CV2" ] || fail "v2.10.12: cura-e26.sh não existe" "o papel completo sem a cura de campo é metade da cura"
assert_grep "$CV2" 'raw.githubusercontent.com/Chrispsz/archcraft-elite/main' "v2.10.12: cura-e26 baixa da main via raw público (sem credencial)"
assert_grep "$CV2" 'bash -n' "v2.10.12: cura-e26 prova cada peça com bash -n antes de instalar"
assert_grep "$CV2" '\|\| can=""' "v2.10.12: cura-e26 instala o craft-power com a guarda do set -e (a cura do suspend no campo)"
assert_grep "$CV2" 'suspend-ignore-inhibit' "v2.10.12: cura-e26 instala a regra polkit da variante -i"
assert_grep "$CV2" 'cache\.db' "v2.10.12: cura-e26 purga o cache do nwg-drawer (o fantasma morre no campo)"
assert_grep "$CV2" 'keyrings.bak-e26' "v2.10.12: cura-e26 move o chaveiro vazio com .bak (o PAM recria com a senha do login)"
assert_grep "$CV2" 'idle.conf do dono NÃO foi tocado' "v2.10.12: cura-e26 declara o limite (escolhas de idle intocadas)"
assert_grep "$CV2" 'pkill -f .*craft-dock-gui\$' "v2.10.12: cura-e26 recicla a dock (o supervisor ressuscita com o código novo em ≤5s)"

# K. E31 — O PT-BR COMPLETO + O SUSPEND DESTRAVADO (o dono: "mistura de
#    inglês com ptbr… a data e o open terminal here" + "fica todo tempo
#    ligado nela… nunca entra em idle como o modo suspender faz")
assert_file "$REPO/elite/airootfs/etc/locale.conf" "E31: locale de FÁBRICA existe (a live nascia em locale C — 'Mon 31 Oct' no relógio e 'Open Terminal Here' no Thunar)"
assert_grep "$REPO/elite/airootfs/etc/locale.conf" 'LANG=pt_BR\.UTF-8' "E31: LANG=pt_BR.UTF-8 de fábrica (o E15 já gerava o locale — a sessão agora USA)"
assert_grep "$SK/.config/waybar/config.top" '"locale": "pt_BR\.UTF-8"' "E31: relógio com locale EXPLÍCITO (o strftime do waybar é do PROCESSO, não herda a sessão — 'seg 31 out' em toda superfície)"
assert_grep "$SK/.config/foot/foot.ini" 'urgent = no' "E31: bell sem urgência (a janela do terminal não é mais marcada)"
assert_grep "$SK/.config/foot/foot.ini" 'notify = no' "E31: bell sem toast (morto o wall E30, o que sobraria é BEL virando aviso — só o essencial)"
assert_grep "$SK/.config/foot/foot.ini" 'O BELL FICA MUDO' "E31: a cura do bell está documentada no próprio arquivo (a história não se perde)"
CE31="$REPO/scripts/live/cura-e31.sh"
assert_file "$CE31" "E31: cura de campo existe (o rig do dono destrava o suspend SEM reinstalar)"
assert_grep "$CE31" 'raw.githubusercontent.com/Chrispsz/archcraft-elite/main' "E31: cura baixa da main via raw público (sem credencial)"
assert_grep "$CE31" 'bash -n' "E31: a cura prova os SHELL com bash -n antes de instalar"
assert_grep "$CE31" 'prove_data' "E31: JSONC/INI são provados por MARCADOR (bash -n em config.top morreria na mão do dono — o '(' do comentário)"
assert_grep "$CE31" 'SUSPEND_MIN=20' "E31: o suspend-via-idle destratado (o 0 era SELO do menu antigo, não escolha do dono)"
assert_grep "$CE31" 'run/user/' "E31: cura resolve a sessão por /run/user (o sudo reseta HOME — lição E29.1)"
assert_grep "$CE31" 'NÃO PODE APAGAR ANTES DO LOCK' "E31: a ordem do fluxo é lei (OFF_MIN ≥ LOCK_MIN garantido pela cura)"
assert_grep "$CE31" 'limitação de hardware' "E31: a cura declara o limite (jack sem detecção é hardware)"
assert_grep "$REPO/scripts/live/cura-e30.sh" 'prove_data' "E31: cura-e30 CORRIGIDA — config.top/menu.xml não são shell (o prove_sh da v2.10.18 abortava no passo 2/5 na mão do dono)"

# L. E31 — CI COM DENTES (a build mensal automática: a lei e a falha nunca silenciosas)
assert_grep "$REPO/.github/workflows/build.yml" 'Lei da Release Única Viva' "E31: a lei da release única virou STEP da CI (publicou a nova, apaga as outras)"
assert_grep "$REPO/.github/workflows/build.yml" 'cleanup-tag=false' "E31: a lei apaga RELEASE, nunca TAG (--cleanup-tag=false)"
assert_grep "$REPO/.github/workflows/build.yml" 'notify-failure' "E31: falha de tag abre issue de diagnóstico (sinal durável para o dono e para o agente)"

# M. E32 — "DEIXE TUDO ATUALIZÁVEL" (o dono: "a distro não pode ficar velha
#    com o tempo, tudo deve funcionar e o código da nossa overlay deve ser
#    de qualidade total"). O audit da Task 8 provou: brave-origin era o
#    ÚNICO pacote congelado ([elite-local] só existia durante o build) e o
#    snapper-cleanup.timer nunca foi habilitado (NUMBER_LIMIT letra morta).
assert_grep "$REPO/elite/fragments/elite-customize.sh" '^\[elite-local\]' "E32: o pacman.conf do sistema entrega o repo da casa (o navegador saía congelado — o [elite-local] morria com o build)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'releases/latest/download' "E32: Server = release VIVA (a URL nunca apodrece — a lei garante que sempre há uma no ar)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'Server = file:///var/cache/elite-local' "E32: fallback file:// com o db de fábrica (o sync não fica vermelho sem rede)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'rm -f /var/cache/elite-local/\*\.pkg\.tar\.zst' "E32: o E8 preserva o DB (só os PKGs saem da ISO — o file:// continua resolvendo)"
assert_nogrep "$REPO/elite/fragments/elite-customize.sh" 'rm -rf /var/cache/elite-local' "E32: o rm -rf inteiro não existe mais (ele apagaria o db preservado)"
assert_grep "$REPO/.ci/build.sh" 'cp /var/cache/elite-local/elite-local.db.tar.gz /var/cache/elite-local/elite-local.db' "E32: o db nasce com o NOME que o pacman consulta (sem o cp, o file:// de nada serve)"
assert_grep "$REPO/.ci/build.sh" 'usr/local/share/elite/VERSION' "E32: marker da casa escrito no build (craft-update compara com a release viva)"
assert_grep "$REPO/.github/workflows/build.yml" 'ELITE_VERSION' "E32: a tag entra no build como marker (ref_type tag → ref_name; fallback git/dev)"
assert_grep "$REPO/.github/workflows/build.yml" "'\.ci/build\.sh'" "E32: build.sh na chave do cache (bump do Brave sem isto = cache-hit do pkg VELHO para sempre)"
assert_grep "$REPO/.github/workflows/build.yml" 'elite-local-pkgs' "E32: pkgs da casa viajam como artifact (build → release) com selo sha256"
assert_grep "$REPO/.github/workflows/build.yml" 'GATE R' "E32: o selo é re-verificado no release job ANTES de subir (artifact corrompido = run vermelha)"
assert_grep "$REPO/.github/workflows/build.yml" 'repo-add --quiet elite-local.db.tar.gz' "E32: db regenerado no release job (repo-add num container Arch efêmero — o ubuntu não tem repo-add)"
assert_grep "$REPO/.github/workflows/build.yml" 'gh release upload' "E32: o repo da casa é publicado como ASSET da release viva (é para cá que o [elite-local] aponta)"
assert_grep "$REPO/.github/workflows/build.yml" 'Atualização pelo terminal' "E32: o corpo da release DECLARA que tudo atualiza (transparência na página pública)"

CU="$REPO/elite/airootfs/usr/local/bin/craft-update"
assert_grep "$CU" 'sudo pacman -Syu' "E32: o coração segue sendo o -Syu (8 repos + [elite-local] numa transação só)"
assert_grep "$CU" 'kbefore' "E32: kernel capturado ANTES da transação"
assert_grep "$CU" 'kafter' "E32: kernel comparado DEPOIS (mudou = aviso de reboot EXATO — sem adivinhar formato de uname)"
assert_grep "$CU" 'ELITE_VERSION_MARKER' "E32: marker com path injetável (a prova nunca escreve em /usr — escola DETECT_ONLY)"
assert_grep "$CU" 'max-time 10' "E32: teto de tempo no curl (o aviso de defasagem nunca trava a atualização)"
assert_grep "$CU" '\|\| true' "E32: falha de rede no aviso é SILÊNCIO (offline-safe: nunca é erro de atualização)"
assert_grep "$CU" 'command -v paru' "E32: honestidade v2.10.5 mantida (paru só se existir — a promessa calada não voltou)"

assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'snapper-cleanup.timer' "E32: o NUMBER_LIMIT volta a valer (sem o timer, snapshot manual acumula CoW para sempre)"
NT2="$(grep -c 'systemctl enable --now snapper-cleanup.timer' "$REPO/elite/airootfs/usr/local/bin/elite-tune" || true)"
assert_eq "$NT2" "1" "E32+E37: o timer vive em ensure_btrfs_stack (a função ÚNICA — os 2 ramos agora compartilham a linha)"
NG="$(grep -c 'list-configs 2>/dev/null | grep -qw root' "$REPO/elite/airootfs/usr/local/bin/elite-tune" || true)"
assert_eq "$NG" "1" "E33+E37: o guard do snapper por SAÍDA vive em ensure_btrfs_stack (1 definição chamada PELOS DOIS modos — a doença do espelho morreu na estrutura)"

CB="$REPO/scripts/check-brave.sh"
assert_file "$CB" "E32: o guardião do pin existe (sem ele o rebuild mensal reusaria a MESMA versão do Brave via cache)"
assert_grep "$CB" 'pkgname=brave-origin' "E32: extração ESCOPADA na seção do Brave (o primeiro pkgver= do build.sh é do python-pywal — bug pego na prova real)"
assert_grep "$CB" 'Authorization: Bearer' "E32: API autenticada quando há token (o rate limit de IP não engole o guardião)"
assert_grep "$CB" 'nunca rebaixo' "E32: downgrade proibido (latest < pin = intocado)"
assert_grep "$CB" 'brave-origin \$\{cur\}' "E32: TODAS as strings de versão mudam junto (o say 'ok: brave-origin x' era o fóssil esquecido)"

CE32="$REPO/scripts/live/cura-e32.sh"
assert_file "$CE32" "E32: cura de campo existe (o rig do dono solta o Brave SEM reinstalar)"
assert_grep "$CE32" 'releases/latest/download' "E32: a cura anexa o [elite-local] ao pacman.conf do rig"
assert_grep "$CE32" 'bash -n' "E32: prove_sh antes de instalar (escola cura-viva)"
assert_grep "$CE32" 'prove_data' "E32: pacman.conf é DADO (marcador + não-vazio — não é shell)"
assert_grep "$CE32" 'v2\.10\.19\+cura-e32' "E32: o rig DECLARA sua base (o craft-update compara com a release viva)"
assert_grep "$CE32" 'snapper-cleanup.timer' "E32: a cura também fecha a lacuna do cleanup no rig"
assert_grep "$CE32" 'LIMITES' "E32: limites honestos declarados (rank do repo anexado, ritmo mensal do Brave)"

# N. E32.3 — O E4 SEM MUTAÇÃO (a run 41256005824: o -Sy vivo do E4 substituiu
#    dbs selados pelo pacstrap e a listagem do mkarchcraftiso leu 'signature
#    invalid' — FATAL da forense nascido no validate, não no pacstrap)
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'dbpath /tmp/elite-e4-db' "E32.3: o E4 valida em dbpath DESCARTÁVEL (escola preflight v2.7 — prova os repos, substitui NADA)"
assert_nogrep "$REPO/elite/fragments/elite-customize.sh" '^pacman -Sy --noconfirm \|\| true' "E32.3: o -Sy vivo descalço EXTINTO do customize (era o único passo que mutava os dbs do live depois do pacstrap)"
assert_grep "$REPO/elite/fragments/elite-customize.sh" 'mkdir -p /tmp/elite-e4-db' "E32.3: o dbpath de prova nasce antes do pacman (pacman não cria dir raiz de db)"

# O. E34 — GOVERNAÇÃO DIÁRIA (o dono: 'você trabalhando no repositório
#    diariamente… anti reset sandbox… devidamente commitado') — o sistema
#    de manutenção contínua (3 tarefas diárias + build mensal) vive NO REPO:
#    a memória que sobrevive ao reset do sandbox é a que está commitada.
for GF in PROTOCOL ATUALIZACOES POLIMENTO AUDITORIA; do
  assert_file "$REPO/docs/gestao/$GF.md" "E34: docs/gestao/$GF.md existe (a memória anti-reset é commitada — sandbox é descartável)"
done
assert_grep "$REPO/docs/gestao/PROTOCOL.md" 'reset --hard origin/main' "E34: bootstrap anti-reset cravado (clone local é CACHE — o GitHub manda)"
assert_grep "$REPO/docs/gestao/PROTOCOL.md" 'Suíte porteira' "E34: a lei do GO local antes de push está no protocolo (L2 — sem GO não sai commit)"
assert_grep "$REPO/docs/gestao/PROTOCOL.md" 'Release Única Viva' "E34: a lei das releases governa os agentes também (L5 — tag imutável, uma viva)"
assert_grep "$REPO/docs/gestao/PROTOCOL.md" 'NUNCA pusha tag' "E34: trabalho diário não pusha tag — a tag é exclusiva do ciclo mensal (L4)"
assert_grep "$REPO/docs/gestao/POLIMENTO.md" 'comentário que mente' "E34: a classe E33 é o foco declarado do polimento (par comentário ↔ código)"
assert_grep "$REPO/docs/gestao/AUDITORIA.md" 'releases/latest' "E34: a auditoria verifica a Lei na API autenticada (não na fé)"

# ── P. E36 — AUDITORIA ARQUITETURAL (o dono: 'pegue todo o código fonte,
#    transforme em palavras-chave, faça 10 questionamentos sobre cada uma').
#    100 questionamentos (docs/gestao/ARQUITETURA.md); as curas desta rodada
#    ganham contratos AQUI — a cura sem contrato é promessa, não entrega.
CIDLE="$REPO/elite/airootfs/usr/local/bin/craft-idle"
CBARS="$REPO/elite/airootfs/usr/local/bin/craft-bars"
CAUT="$REPO/elite/airootfs/etc/skel/.config/labwc/autostart"
CRXML="$REPO/elite/airootfs/etc/skel/.config/labwc/rc.xml"
CTOP2="$REPO/elite/airootfs/etc/skel/.config/waybar/config.top"
CENV="$REPO/elite/airootfs/etc/skel/.config/labwc/environment"
CTHEMER="$REPO/elite/airootfs/etc/skel/.config/labwc/themerc-override"
CPKG="$REPO/elite/packages.add"
CDGUI="$REPO/elite/airootfs/usr/local/bin/craft-dock-gui"
CCON2="$REPO/elite/airootfs/usr/local/bin/craft-connect"
CDUMP2="$REPO/elite/airootfs/usr/local/bin/craft-dump"
CSTAGE="$REPO/elite/airootfs/usr/local/bin/elite-install-stage"
CTUNE="$REPO/elite/airootfs/usr/local/bin/elite-tune"
CALD="$REPO/elite/airootfs/usr/local/share/applications/calamares.desktop"
assert_grep "$CIDLE" 'systemctl suspend -i' "E36: o suspend do IDLE ignora inibidores (a cura -i do craft-power chegou ao idle — navegador com vídeo não segura mais o sono)"
assert_grep "$CIDLE" 'LOCK_MIN:-0.*-eq 0.*\] && \[ "\${SUSPEND_MIN:-0}"' "E36: o exit calado exige os DOIS knobs em 0 — Lock=Nunca + Suspender=20min ENTREGA o suspend (antes: exit antes do ramo suspend = promessa do menu que o daemon matava)"
assert_grep "$CBARS" 'SUSPEND_MIN' "E36: o supervisor acorda o idle por LOCK OU SUSPEND (o gate só de LOCK nunca nascia a combinação Nunca+20min)"
assert_grep "$CBARS" 'pgrep -x swaync' "E36: o swaync — a superfície de TODOS os avisos de erro — tem REDE no supervisor (fim do órfão total)"
assert_grep "$CBARS" 'pgrep -x udiskie' "E36: o udiskie tem rede no supervisor (USB automount morto calado não existe mais)"
assert_grep "$CBARS" 'polkit-gnome-authentication-agent-1' "E36: o agente polkit tem rede no supervisor (pkexec sem agente = senha impossível)"
assert_grep "$CBARS" '\^waybar -c' "E36: o ensure da waybar usa âncora ^ (a lição v2.10.6 da dock/toplevel chegou ao ensure mais velho — editor com o config aberto não mascara mais)"
assert_grep "$CAUT" 'bars\.log.*2>&1 &|>>.*bars\.log.*2>&1 &' "E36: o spawn do swaync no autostart despeja o stderr no bars.log (o comentário que invocava 'a lei dos vizinhos' sobre um spawn nu era E33 — agora o código cumpre)"
assert_nogrep "$CRXML" 'ToggleShowDesktop → preservada' "E36: rc.xml não conta mais a história da v1.2 como presente (a nota 'W-d → fuzzel/ToggleShowDesktop' era E33 — o código real é craft-drawer/toggle da dock)"
assert_nogrep "$CTOP2" 'W-S-P' "E36: a barra fala a língua dos keysyms NOS COMENTÁRIOS também (o bug 'P maiúsculo implícita Shift' curado na v2.10.5 sobrevivia em 3 comentários — E33)"
assert_grep "$CTOP2" 'W-S-p' "E36: os comentários da barra citam os atalhos REAIS (W-p/W-S-p minúsculos)"
assert_grep "$CENV" 'XCURSOR_THEME=Bibata' "E36: fim dos TRÊS sotaques do ponteiro — a sessão herda o Bibata dos GTK (antes: Bibata nos apps, tema DEFAULT no compositor/foot)"
assert_grep "$CTHEMER" 'cursor\.theme: Bibata' "E36: o próprio compositor crava o cursor do rice (labwc-theme(5) cursor.theme — o XCURSOR_* sozinho não cobria o labwc)"
assert_grep "$CPKG" '^os-prober$' "E36: o knob D2 do install-stage deixou de ser código morto (os-prober ligado no GRUB mas AUSENTE da ISO = nem o Windows entraria)"
assert_grep "$CDGUI" 'strict=True' "E36: o FECHO do meio NUNCA casa por título (a cláusula 'name in title' era o caminho do WM_DELETE para janela alheia — falso positivo em fecho = perda de dados)"
assert_grep "$CDGUI" 'background-size: 6px 3px' "E36: o CSS de fallback ESPELHA o skel (a bolinha v2.3.7 no DEFAULT_CSS — a barrinha inset rejeitada morreu nos DOIS lugares)"
assert_nogrep "$CDGUI" 'box-shadow: inset 0 -3px 0' "E36: a barrinha que o dono rejeitou não existe em NENHUM dos dois CSS (o espelho E33 skel↔fallback acabou)"
assert_grep "$CCON2" 'zenity --password' "E36: a senha Wi-Fi é MASCARADA (o fuzzel mostrava tudo enquanto o README:70 jurava 'senha oculta' — zenity está na ISO desde o E35; fallback fuzzel preservado)"
assert_grep "$CCON2" '/sys/class/bluetooth' "E36: a linha de Bluetooth SÓ nasce com adaptador (a linha incondicional abria janela vazia em desktop sem BT — 'linha que diz o que não existe')"
assert_grep "$CDUMP2" 'PÚBLICO' "E36: o --upload avisa que o paste é PÚBLICO (SSIDs/IPs/MACs não podem expor a rede doméstica em silêncio)"
assert_grep "$CSTAGE" '30_os-prober' "E36: o gate kernel-único EXCLUI o bloco 30_os-prober (a promessa D2 do dual-boot e o gate param de brigar no mesmo script — 2º Linux ≠ Installation Failed)"
assert_grep "$CTUNE" 'PRV3=0' "E36: gate ISA no enxerto — CPU pré-v3 NÃO instala kernel/repos x86_64_v3 (o 'avisa e mesmo assim instala' gerava SIGILL no boot seguinte)"
assert_grep "$CTUNE" 'SEÇÃO \[1\] PULADA' "E36: o pulo da seção [1] é AVISADO com o motivo e o destino (o resto do tune segue — nunca deixa o usuário sem saída)"
assert_grep "$CALD" 'Name\[pt_BR\]=Instalar' "E36: a porta de entrada do instalador fala PT-BR (distro PT-BR não abre a ação mais crítica em EN)"
assert_grep "$REPO/.github/workflows/tests.yml" "docs/\*\*" "E36: a porteira RODA quando docs/** muda (o ponto cego da proteção sobre os arquivos que protege morre)"
assert_grep "$REPO/scripts/apply-overlay.sh" "exclude='__pycache__'" "E36: o rsync do [3] exclui __pycache__/*.pyc na FONTE (o E35 curou o sintoma no file_permissions — a ISO nunca mais vê entulho de runtime)"
assert_grep "$REPO/docs/gestao/ARQUITETURA.md" '100 questionamentos' "E36: o documento da auditoria arquitetural existe (10 palavras-chave × 10 questionamentos com evidência)"

# ── E37: FATORAÇÃO DOS ESPELHOS do elite-tune (plano ARQUITETURA nº1) ──
# A doença do E33 (o interativo carregava o guard do snapper morto no
# firstboot sob o comentário 'o MESMO GUARD') não pode renascer: função
# ÚNICA chamada PELOS DOIS modos — espelho cravado como contagem (def 1×,
# chamada 2×, zero cópia viva).
CTUNE="$REPO/elite/airootfs/usr/local/bin/elite-tune"
for fn in apply_grub_tokens write_elite_sysctl ensure_bbr ensure_btrfs_stack; do
  ND="$(grep -c "^${fn}() {" "$CTUNE" || true)"
  NC="$(grep -cE "^[[:space:]]*${fn}( |$)" "$CTUNE" || true)"
  assert_eq "$ND" "1" "E37: ${fn} definida UMA vez (a fonte única da verdade)"
  assert_eq "$NC" "2" "E37: ${fn} chamada PELOS DOIS modos (firstboot + interativo — o espelho é a chamada, não a cópia)"
done
assert_eq "$(grep -c 'ensure_cmdline_token /etc/default/grub nowatchdog' "$CTUNE" || true)" "1" \
  "E37: o token nowatchdog não tem mais cópia espelhada (era 2 — a doença do E33 morreu na estrutura)"
assert_eq "$(grep -c 'vm\.swappiness = 180' "$CTUNE" || true)" "1" \
  "E37: a lei do sysctl vive em write_elite_sysctl (era 2 cópias que podiam divergir)"
assert_eq "$(grep -c 'grub-mkconfig -o /boot/grub/grub\.cfg' "$CTUNE" || true)" "1" \
  "E37: o grub-mkconfig vive em apply_grub_tokens (era 2 — o plano do kernel nascia em dois lugares)"
# E37 + plano nº16: o epílogo do interativo conta a verdade
assert_grep "$CTUNE" 'FAILURES=\(\)' "E37/n16: o epílogo tem memória de falha (FAILURES — o 'CONCLUÍDO' incondicional não tem memória)"
assert_grep "$CTUNE" 'PENDÊNCIA: ' "E37/n16: cada falha de pacman_s é anunciada NA HORA (note_fail — a falha não espera o fim para existir)"
assert_grep "$CTUNE" 'CONCLUÍDO COM' "E37/n16: o epílogo diz 'CONCLUÍDO COM pendências' quando algo falhou (o sucesso é a exceção declarada, não o default)"
assert_grep "$CTUNE" 'echo -e .*N\} pacman -S --needed --noconfirm \$\*' \
  "E37/n16: o pacman_s mantém a linha do plano no modo REAL (o rc real não custa o contrato visual '  $ pacman …')"

# ── E45: CONTRATOS DE DOCS (plano ARQUITETURA nº3) ──────────────────────
# A auditoria provou (§10.3/§10.7): NENHUM contrato lia o README e ele
# APODRECEU — vendia o Timeshift que o packages.remove derruba. O papel da
# casa agora tem porteira própria: fantasma citado = push vermelho, índice
# desgarrado dos bins = idem, rollback vendido fora do rei = idem.
BINS="$REPO/elite/airootfs/usr/local/bin"
# D1. O README não cita fantasma: todo craft-*/elite-* citado existe na
#     árvore (bin, unit ou fragmento). Allowlist só com justificativa.
DOC_GHOSTS=""
for TOK in $(grep -oE '\b(craft|elite)-[a-z0-9.-]+' "$REPO/README.md" | sort -u); do
  case "$TOK" in
    elite-build) ;;              # diretório de SAÍDA do apply-overlay (não é programa)
    elite-local) ;;              # id do REPO da casa no pacman.conf (não é arquivo)
    elite-firstboot.service) ;;  # unit — resolvida pelo contrato abaixo
    elite-bootupdate.timer|elite-sysupdate.timer) ;;  # units da cadência E46/E51 — resolvidas pelos contratos V4
    elite-system) ;;             # o PACOTE ÚNICO (E50) — resolvido pelos contratos E50 do build/packages.add
    *) [ -f "$BINS/$TOK" ] || DOC_GHOSTS="$DOC_GHOSTS $TOK" ;;
  esac
done
assert_eq "$DOC_GHOSTS" "" "E45/D1: o README não cita craft-*/elite-* FANTASMA (toda citação existe em usr/local/bin; 'elite-build' é o diretório de saída do build e 'elite-firstboot.service' é a unit — allowlist com justificativa)"
assert_file "$REPO/elite/airootfs/etc/systemd/system/elite-firstboot.service" "E45/D1: a elite-firstboot.service citada pelo README existe como unit na árvore"
# D2. O índice do SCRIPTS.md cobre os bins VIVOS (a promessa E36 'todo
#     binário vivo tem linha aqui' — o exo-open E40 tinha nascido fora do
#     papel) e não documenta fantasma: todo craft-*/elite-* do índice existe.
DOC_MISSING=""
for BINPATH in "$BINS"/*; do
  N="$(basename "$BINPATH")"
  grep -q "\`$N\`" "$REPO/docs/SCRIPTS.md" || DOC_MISSING="$DOC_MISSING $N"
done
assert_eq "$DOC_MISSING" "" "E45/D2: o índice do SCRIPTS.md cobre TODOS os bins vivos (contagem — bin sem linha no papel = promessa E36 quebrada de novo)"
DOC_FANTASMA=""
for TOK in $(sed -n '/^## Índice completo/,/^\*\*Scripts de repo/p' "$REPO/docs/SCRIPTS.md" | grep -oE '\x60[a-z0-9._-]+\x60' | tr -d '\x60' | grep -E '^(craft|elite)-' | sort -u); do
  [ -f "$BINS/$TOK" ] || DOC_FANTASMA="$DOC_FANTASMA $TOK"
done
assert_eq "$DOC_FANTASMA" "" "E45/D2: o índice do SCRIPTS.md não documenta FANTASMA (todo craft-*/elite-* da tabela existe em usr/local/bin — doc de peça morta é peça morta no papel)"
# D3. O rollback citado bate com o packages.remove (a mentira flagrada na
#     auditoria: o README vendia o Timeshift enquanto a lista o derruba —
#     e o bloco v1.0.4 da lista jurava 'craft-rollback aponta pro
#     Timeshift' como presente, o craft-rollback v2 é SNAPPER desde a
#     v2.3.6, dump do rig).
assert_nogrep "$REPO/README.md" 'Rollback do sistema: Timeshift' "E45/D3: o README não vende mais o Timeshift como rollback (a frase da auditoria §10.3 está EXTINTA — a seção fala a mesma língua da tabela 'O que a ISO contém')"
assert_grep "$REPO/README.md" 'Rollback do sistema: snapshots \*\*snapper\*\*' "E45/D3: a seção de rollback do README cita o rei REAL (snapper + craft-rollback + grub-btrfs)"
assert_nogrep "$REPO/README.md" 'o timeshift saiu na v2.3.6' "E45/D3: a meia-verdade 'saiu na v2.3.6' EXTINTA (a v2.3.6 trocou a ESTRATÉGIA; o PACOTE só saiu na v2.10.14 — o README conta as duas datas certas)"
assert_grep "$REPO/elite/packages.remove" '^timeshift$' "E45/D3: o timeshift segue VEDADO no packages.remove (a promessa v2.3.6 executada na v2.10.14 não regride)"
assert_grep "$REPO/elite/packages.add" '^snapper$' "E45/D3: o rei REAL está na ISO (snapper — o craft-rollback v2 e o grub-btrfsd vigiam /.snapshots)"
assert_nogrep "$REPO/elite/packages.remove" 'craft-rollback aponta pro Timeshift' "E45/D3: o comentário E33 'craft-rollback aponta pro Timeshift' EXTINTO do packages.remove (verdade morta da v1.0.4 escrita como presente)"
assert_nogrep "$REPO/elite/packages.remove" 'o snapper NÃO vem na ISO' "E45/D3: a segunda mentira do bloco v1.0.4 EXTINTA (o snapper É da ISO desde a v2.3.6 — packages.add)"
assert_nogrep "$REPO/elite/packages.remove" 'README "Dia 1"' "E45/D3: o ponteiro morto 'README Dia 1' EXTINTO (seção que não existe em lugar nenhum do README)"

# ── E46: A ORDEM DO DONO (04/nov) — um verbo só, rollback fora do menu,
#    o canal que INSTALA e a cadência. O dono: "vejo os erros persistir
#    após atualizar… o sistema não deve quebrar ao atualizar mas sim
#    melhorar constantemente". A ferida cravada: o pacman só ATUALIZA o
#    que já está instalado — o veículo de todas as curas (elite-craft)
#    nunca tinha sido INSTALADO no rig da 28 (a ISO é anterior à E43) e
#    TODAS as curas do canal passaram por ele. Cada cura com contrato.
CU46="$REPO/elite/airootfs/usr/local/bin/craft-update"
CP46="$REPO/elite/airootfs/usr/local/bin/craft-power"
CXT="$REPO/elite/airootfs/usr/local/bin/craft-extract"
UCA="$REPO/elite/airootfs/etc/skel/.config/Thunar/uca.xml"
S46="$REPO/elite/airootfs/etc/systemd/system"
# V1. O CANAL QUE INSTALA (a cura da persistência):
assert_grep "$CU46" 'elite-craft craft-toplevel' "E46/V1: o -Syu leva os VEÍCULOS como alvos explícitos (quem não tem, INSTALA — o pacman só atualiza quem já tem era a ferida do 'erros persistem')"
assert_grep "$CU46" '--canal' "E46/V1: a dose DIÁRIA existe (--canal — só os pacotes [elite-local], --needed, offline-safe)"
assert_grep "$CU46" '--sistema' "E46/V1: a dose SEMANAL existe (--sistema — o -Syu completo com rede de segurança)"
assert_grep "$CU46" 'create -t pre' "E46/V1: a dose semanal arma o snapshot PRE do snapper ANTES da transação (quebrou? o GRUB liga o snapshot e o rollback é um reboot)"
assert_grep "$CU46" 'pre-number' "E46/V1: o POST casa com o PRE (--pre-number — o par fecha a história)"
assert_grep "$CU46" 'enable --now elite-bootupdate.timer elite-sysupdate.timer' "E51/V1: a porta manual ('Atualizar sistema') liga a cadência AO LIGAR na 1ª rodada (o automatismo nasce onde o dono já clica)"
assert_grep "$CU46" 'ELITE_UPDATE_LOG' "E46/V1: o log da automação é injetável (mesma escola do VMARK — a prova em sandbox não escreve em /var)"
assert_grep "$CU46" 'pacman -Slq elite-local' "E46/V1: a dose diária nasce da LISTA VIVA do repo (pacote novo da casa entra no canal por construção)"
# V2. UM VERBO POR FAMÍLIA (o 'Criar Arquivo…' que confundiu o dono morre):
assert_grep "$REPO/elite/packages.remove" '^thunar-archive-plugin$' "E46/V2: o plugin do duplo verbo VEDADO (o dono perguntou 'esse criar arquivo que é o botão novo?' — a faca de dois gumes da auditoria §4.6 virou corte)"
assert_nogrep "$REPO/elite/packages.add" '^thunar-archive-plugin$' "E46/V2: o plugin não volta ao packages.add (a mão no Thunar é dos verbos da casa)"
assert_grep "$REPO/elite/packages.add" '^xarchiver$' "E46/V2: o xarchiver FICA (abrir/gerenciar — só o plugin do duplo verbo morre)"
assert_file "$CXT" "E46/V2: o craft-extract existe (o 'Extrair aqui' herda a casa — a extração não morreu com o plugin)"
assert_grep "$CXT" 'command -v 7z || command -v 7zz' "E46/V2: o resolver 7z OU 7zz (E42 — a ISO nunca mais exige um binário que não tem; dono único desde a E72)"
assert_grep "$CXT" 'mktemp -d' "E46/V2: a extração em PALCO (o colide-contra-o-conteúdo-real — zero parse de listing; o que existe nunca é substituído sem pergunta)"
assert_grep "$UCA" 'craft-extract %F' "E46/V2: o 'Extrair aqui' tem assento no uca.xml (o skel nasce com os DOIS verbos da casa — terminal E40 + extrair E46; o Comprimir morreu na E72)"
assert_grep "$UCA" 'Extrair aqui' "E46/V2: o verbo em PT-BR no menu do dono (a lei L10)"
assert_nogrep "$UCA" 'segue no menu' "E46/V2: o cabeçalho do uca.xml não jura mais que o plugin 'segue no menu' (o plugin morreu — a mentira de comentário não renasce no próprio arquivo da cura)"
# V3. O ROLLBACK FORA DO MENU (ordem do dono):
assert_nogrep "$CP46" 'Rollback do sistema…' "E46/V3: o item 'Rollback do sistema…' fora do menu Sessão (a porta do rollback é a entrada de snapshot no GRUB — o menu fica com o que se usa toda semana)"
assert_nogrep "$CP46" 'exec craft-rollback' "E46/V3: o craft-power não executa mais o craft-rollback (o script segue no sistema — quem souber o caminho usa; o comentário que conta a história cita o nome, o EXEC é o que a peça proíbe)"
# V4. A CADÊNCIA (as units da casa):
for u46 in elite-bootupdate.service elite-bootupdate.timer elite-sysupdate.service elite-sysupdate.timer; do
  assert_file "$S46/$u46" "E51/V4: $u46 existe (a cadência tem corpo — ao LIGAR 3min pós-boot · semanal sáb 10:00±2h)"
done
assert_grep "$S46/elite-bootupdate.service" 'ConditionACPower=yes' "E51/V4: a dose da casa SÓ na tomada (battery nunca é o momento da transação)"
assert_grep "$S46/elite-bootupdate.timer" 'OnBootSec=3min' "E51/V4: a casa atualiza AO LIGAR (OnBootSec 3min — 'atualizar a cada vez que iniciar', o dono; o boot é o relógio que ele bate todos os dias)"
assert_grep "$S46/elite-sysupdate.timer" 'OnCalendar=Sat \*-\*-\* 10:00:00' "E46/V4: o sistema roda SEMANAL (sáb 10:00 ±2h — 'as partes do sistema semanalmente', o dono)"
assert_grep "$S46/elite-sysupdate.timer" 'Persistence=true' "E46/V4: o timer atrasado CUMPRE (máquina desligada no sábado = atualiza ao ligar, não pula a semana)"
assert_grep "$S46/elite-sysupdate.service" 'ConditionACPower=yes' "E46/V4: a dose semanal SÓ na tomada"
assert_file "$S46/timers.target.wants/elite-bootupdate.timer" "E51/V4: o timer ao LIGAR nasce HABILITADO (wants symlink da overlay — a casa-prova do keyring-fix)"
assert_file "$S46/timers.target.wants/elite-sysupdate.timer" "E46/V4: o timer do sistema nasce HABILITADO"
# V5. O VEÍCULO NASCE INSTALADO (futuras ISOs não repetem a ferida da 28):
# E50 — O PACOTE ÚNICO é a entrada viva (a era dos dois veículos encerrou):
assert_grep "$REPO/elite/packages.add" '^elite-system$' "E50: o elite-system no packages.add — a ISO nasce com O PACOTE ÚNICO INSTALADO (a diretriz do dono: um só pacote atualiza todo o sistema)"
assert_nogrep "$REPO/elite/packages.add" '^elite-craft$' "E50: o elite-craft SAIU do packages.add (a era dos dois veículos encerrou — a ISO não nasce com o fóssil)"
assert_grep "$REPO/.ci/build.sh" 'pkgname=elite-system' "E50: O PACOTE ÚNICO existe no build (elite-system — todo o código de casa em um pacote, diretriz do dono)"
assert_grep "$REPO/.ci/build.sh" "replaces=\('elite-craft' 'craft-toplevel'\)" "E50: o elite-system SUBSTITUI o par legado na transação (replaces — o rig antigo acorda com UM dono para /usr/local/bin)"
assert_grep "$REPO/.ci/build.sh" "conflicts=\('elite-craft' 'craft-toplevel'\)" "E50: o elite-system CONFLITA o par legado (a coexistência de eras é impossível — UM dono só)"
assert_grep "$REPO/.ci/build.sh" 'install -m755 craft-toplevel' "E50: o daemon de janelas viaja DENTRO do pacote único (compilado do C vendado — sem pacote irmão)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel=1' "E50: o elite-system nasce pkgrel=1 (a era nova começa honesta — lei E41 de agora em diante)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 5→6 NO MESMO COMMIT' "E71 (era E50, âncora refrescada): pkgrel craft-toplevel 5→6 NO MESMO COMMIT (lei E41 — o C do daemon mudou de conteúdo: o parent é nulável; âncora na HISTÓRIA, lição E58/E59: o número atual é lei do guard-pkgrel do CI)"
assert_grep "$REPO/.ci/build.sh" 'files/etc/systemd/system' "E50: o elite-system carrega as units no payload /etc (sem elas o rig instalado nunca recebe a cadência)"
assert_grep "$REPO/.ci/guard-pkgrel.sh" 'systemd/system/elite' "E46/V5: o guard-pkgrel cobra delta de UNIT também (unit mudada sem pkgrel = o -Syu pula a cadência em silêncio)"
assert_grep "$REPO/.ci/guard-pkgrel.sh" 'check elite-system' "E50: o guard cobra o PACOTE ÚNICO (bins + units + o C vendado — o mapa conteúdo→pacote segue a era nova)"
# ── E49: A CURA QUE SE ENTREGA SOZINHA — sessão inteira + adoção de uma
#    via. O dono: "eu atualizei mas o sistema está aparentemente igual…
#    a não ser que o pacote não instalou ou a lógica de atualizações não
#    funciona hoje". As provas dele (prints): rollback no menu, python3
#    na lista — o rig corria a era pré-E46/E48 INTEIRA. Duas raízes
#    mecânicas nomeáveis, dois contratos.
CU49="$REPO/elite/airootfs/usr/local/bin/craft-update"
# RAIZ 1 — o refresh da sessão era SÓ o swayidle: a dock (transição
# suave), o áudio e o daemon de janelas seguiam velhos até relogin.
assert_grep "$CU49" 'craft_tl_q' "E49: o SEGUNDO veículo tem delta próprio (craft-toplevel muda na transação → a sessão também recebe o daemon novo sem relogin)"
assert_grep "$CU49" 'refresh_session' "E49: o refresh da sessão é função própria (por delta e por pacote — o E48 cresceu sem virar espaguete)"
assert_grep "$CU49" 'craft-dock-gui\$' "E49: a DOCK entra no refresh (âncora do craft-bars — a transição suave v2.11 vale SEM relogin, o 'continua piscando' morre)"
assert_grep "$CU49" 'craft-audio-route' "E49: o roteador de áudio entra no refresh (nenhum daemon da casa envelhece dentro da sessão atualizada)"
assert_grep "$CU49" 'ELITE_TL_SETTLE' "E49: a espera do toplevel é porta de prova (a dock nova nasce sobre o toplevel de pé; a suíte não dorme à toa)"
assert_grep "$CU49" '--adotar' "E49: o verbo --adotar existe (a porta da conclusão da adoção — sessão + cadência numa rodada)"
# RAIZ 2 — o OVO-GALINHA: o rig pré-E46 roda craft-update sem alvos
# explícitos; o elite-craft nunca é adotado; o craft-update novo mora
# DENTRO do elite-craft. O gatilho viaja no craft-toplevel (o ÚNICO
# pacote que TODO rig da casa tem).
assert_grep "$REPO/.ci/build.sh" 'PACOTE ÚNICO elite-system ausente' "E50: a PONTE fala a língua da era nova (o elite-adopt puxa o elite-system — o rig que nunca teve pacote salta DIRETO para um pacote só)"
assert_grep "$REPO/.ci/build.sh" 'cat > /tmp/elite-src/craft-toplevel/elite-adopt' "E49: o elite-adopt nasce no build.sh (fonte única — a suíte o extrai e o executa: comportamento, não texto)"
assert_grep "$REPO/.ci/build.sh" 'When = PostTransaction' "E49: o hook é PostTransaction (dispara no fim da transação que o dono já rodou — nenhuma cerimônia nova)"
assert_grep "$REPO/.ci/build.sh" 'Target = craft-toplevel' "E49: o gatilho é o craft-toplevel (o ÚNICO pacote da casa que TODO rig tem — até o rig da 28 recebe)"
assert_grep "$REPO/.ci/build.sh" 'Exec = /usr/share/elite/elite-adopt' "E49: o Exec aponta para /usr/share/elite (FORA do domínio /usr/local/bin do elite-craft — zero briga de dono de arquivo)"
assert_grep "$REPO/.ci/build.sh" 'setsid' "E49: a adoção nasce DESPRENDIDA (pacman NÃO roda dentro do hook — o lock da transação-mãe ainda vive)"
assert_grep "$REPO/.ci/build.sh" 'db.lck' "E49: a espera do lock é honesta e com teto (a transação-mãe termina antes da adoção — sem corrida, sem loop eterno)"
assert_grep "$REPO/.ci/build.sh" '--adotar' "E49: a conclusão é do craft-update NOVO (fonte única da lógica de refresh — o elite-adopt só semeia)"
assert_grep "$REPO/.ci/build.sh" 'ELITE_ADOPT_SYNC' "E49: o corpo acoplado é porta de prova (a suíte observa o comportamento; o hook real nunca liga)"
# V6. O README conta a cadência (o papel acompanha o sistema):
assert_grep "$REPO/README.md" 'elite-bootupdate.timer' "E51/V6: o README documenta a cadência AO LIGAR (o boot é o relógio do dono — a casa atualiza a cada vez que iniciar)"
assert_nofile "$REPO/elite/airootfs/etc/systemd/system/elite-channel.timer" "E51: o timer de relógio APOSENTOU (a overlay não entrega mais o elite-channel — a era do 11:30 acabou)"
assert_nofile "$REPO/elite/airootfs/etc/systemd/system/elite-channel.service" "E51: o service do channel APOSENTOU junto (nenhum fantasma de cadência na overlay)"
assert_file "$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.service" "E51: a unit ao LIGAR nasce na overlay (a dose da casa tem casa)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-update" 'elite_cadencia' "E51: a cadência é UMA função nas duas portas (--adotar e manual — idempotente, sem duplicar)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-update" 'elite-channel.timer aposentado' "E51: a aposentadoria do relógio deixa réu no papel (o rig sabe POR QUE o canal de 11:30 sumiu)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 21→22 NO MESMO COMMIT' "E71 (era E54, âncora refrescada): pkgrel elite-system 21→22 NO MESMO COMMIT (lei E41 — o C do daemon e a dock mudaram de conteúdo; âncora na HISTÓRIA, o número atual é lei do guard-pkgrel do CI)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-update" 'dose AUTO-CURA a cadência' "E51.1: o canal SELF-HEAL a cadência (a dose v4.2 de hoje adota o rig e a PRÓPRIA dose troca o timer — nenhum rig fica com cadência fantasma)"
assert_grep "$REPO/.github/workflows/publish-packages.yml" 'craft-toplevel-\*\.pkg' "E51.1: o fluxo de publicação segue publicando a PONTE (a porta dos rigs v2 — o erro da aposentadoria confessado no build.sh)"
assert_grep "$REPO/README.md" 'elite-sysupdate.timer' "E46/V6: o README documenta a cadência SEMANAL com snapshot PRE/POST"
assert_nogrep "$REPO/README.md" 'restauração GUI no menu Sessão' "E46/V6: o README não vende mais a restauração GUI no menu Sessão (o rollback saiu do menu — o papel acompanha, E33 auto-patrulhado)"

# ── E53: A DOCK VÊ O SEM-NOME — o dono: "a dock não está mostrando todo
#    tipo de pacote — estou com um app image aberto e só consigo acessar
#    pelo alttab". A perícia: os dinâmicos nasciam SÓ do casamento
#    comm→.desktop — o _resolve_desktop devolvia None para o AppImage de
#    fábrica (sem .desktop NENHUM instalado) e o continue TRAGIA a janela
#    que o craft-toplevel já via de verdade: invisível na dock, só no
#    A-Tab. A cura (v2.10.9): a JANELA é a verdade — snapshot não coberto
#    por pin/dinâmico vira botão RAW com verbos reais por id.
CDGUI9="$REPO/elite/airootfs/usr/local/bin/craft-dock-gui"
assert_grep "$CDGUI9" 'self\.raw = \{\}' "E53: os sem-nome têm estado PRÓPRIO (diff separado dos dinâmicos — nada recria botão a cada tick)"
assert_grep "$CDGUI9" 'def _raw_key' "E53: a chave do sem-nome é o app_id/stem (a janela real entra na dock SEM depender de .desktop)"
assert_grep "$CDGUI9" 'set\(raw\) == set\(self\.raw\)' "E53: o diff dos raw é vigiado (nada entra nem sai sem mudança real — a lei v2.10.12 alcança o sem-nome)"
assert_grep "$CDGUI9" 'def _make_raw_button' "E53: o botão RAW existe (ícone do tema pelo stem; sem .desktop não há ícone real a prometer)"
assert_grep "$CDGUI9" 'theme\.has_icon' "E53: o tema de ícones é consultado pelo stem (AppImage que instala ícone o ganha; o resto, o glifo honesto)"
assert_grep "$CDGUI9" 'def _press_raw' "E53: o sem-nome tem verbos (esquerdo foca/cicla por id · meio encerra · direito nova sessão — gramática E54)"
assert_grep "$CDGUI9" 'def _raw_windows' "E53: as janelas do sem-nome são REAIS (snapshot do daemon; strict no fecho — a lei E36 não abre exceção)"
assert_grep "$CDGUI9" 'nova sessão sem prova de origem' "E53/E54: o direito no raw NUNCA adivinha (sem prova de origem o log ensina a saída — instale o .desktop e o app vira dinâmico completo)"
assert_grep "$CDGUI9" 'self\.dyn or self\.raw' "E53: o fio separador reconhece o lado dos raw (o sem-nome mora com os dinâmicos — nunca órfão no meio dos pins)"
assert_grep "$CDGUI9" 'raw ON' "E53: o boot da dock confessa os raw no bars.log (a cura é evidência, não promessa)"

# ── E57 — O PACOTE É O ÚNICO DONO NA ISO (build de ISO 05/nov 03:17:
#    'existe no sistema de arquivos' em 44 caminhos — a doença E56 no
#    lado da esteira). O overlay entregava bins/units NO DISCO e o
#    pacstrap instalava o elite-system por cima; o pacstrap não aceita
#    --overwrite (só pacotes atravessam), então a cura é na origem: o
#    par overlay↔pacote vira PACOTE SOZINHO, modos nativos do git index.
BSH57="$REPO/.ci/build.sh"
assert_grep "$BSH57" 'O PACOTE É O ÚNICO DONO NA ISO' "E57: a cura existe no build.sh (a ISO morria na mesma doença que derrubou a adoção do rig — 44 'existe no sistema de arquivos')"
assert_grep "$BSH57" "MF_E57=/tmp/elite-src/elite-system/files/MANIFEST" "E57: a lista de remoção nasce do MANIFEST do pacote único (fonte única — a remoção nunca é inventada à mão)"
assert_grep "$BSH57" 'MANIFEST do elite-system ausente — a remoção E57 é cega sem ele' "E57: sem MANIFEST o build ABORTA (remover sem prova de conteúdo = a doença com outra roupa)"
assert_grep "$BSH57" "grep -qxF 'elite-system'" "E57: a remoção só existe quando o elite-system é alvo do pacstrap (overlay fica se o pacote não instala — no-op honesto)"
assert_grep "$BSH57" 'file_permissions virou responsabilidade do elite-system' "E57: as entradas file_permissions dos bins empacotados saem do profiledef (os modos 100755/100644 viajam no pacote — o E54.1 garante)"
assert_grep "$BSH57" 'sobreviveram à remoção E57' "E57.1: quem sobreviver à remoção ABORTA ANTES do pacstrap (o build 2 provou o custo do silêncio: o glob com ponto literal removeu ZERO units e a ISO morreu 10 min depois — réus 44→9)"
assert_grep "$BSH57" 'elite-\*\.service' "E57.1: o glob das units é GLOB de verdade (o 'elite-'.*.service nascia exigindo um PONTO depois de elite- — glob não é regex)"

# ── E58 — O ROLLING TROCA O JOGO EMBAIXO (verify da ISO 05/nov: BARS_EXITS=17
#    com 'invalid version for global zwlr_layer_shell_v1 — expected at most 4,
#    got 5' + 'pacman-init.service: Failed with result'). Duas classes: o
#    hyprpolkitagent 0.2.0 reescrito em hyprtoolkit (v5) contra o labwc v4, e
#    o primeiro confronto sessão (craft-fix-keys ~40s) × pacman-init.
CBARS58="$REPO/elite/airootfs/usr/local/bin/craft-bars"
CFK58="$REPO/elite/airootfs/usr/local/bin/craft-fix-keys"
assert_grep "$CBARS58" '/usr/bin/lxqt-policykit-agent' "E58: o agente que roda HOJE assume a fila (hyprpolkitagent 0.2.0 = hyprtoolkit = layer-shell v5 vs o v4 do labwc — 17 mortes provadas no verify)"
assert_grep "$CBARS58" 'PROBE POR CONTEÚDO' "E58: o seletor decide por CONTEÚDO (binário com hyprtoolkit dentro sai da fila — a era Qt dos rigs segue válida de fallback)"
assert_grep "$REPO/elite/packages.add" '^lxqt-policykit' "E58: o agente WM-agnóstico é DEPENDÊNCIA DECLARADA (lxqt-policykit 2.4, no extra desde abr/26; hyprpolkitagent segue de fallback)"
assert_grep "$CFK58" 'craft-keyring-wait' "E58: a cura da sessão ESPERA antes de tocar no chaveiro (o primeiro confronto sessão×pacman-init não existe mais — quem chega segundo, espera; o E38/E29 só cobria o restart)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 7→8 NO MESMO' "E58: pkgrel elite-system 7→8 NO MESMO COMMIT (lei E41 — craft-bars e craft-fix-keys mudaram de conteúdo; a âncora é a HISTÓRIA no comentário — o número atual pertence ao guard-pkgrel do CI, não ao contrato estático: ele anda a cada E-passo)"

# ── E59 — A DOSE É DO SISTEMA INSTALADO (verify da ISO #4: elite-bootupdate
#    'Failed with result exit-code' aos 3min do LIVE — copy-to-RAM não
#    persiste nada, TCG lento; a causa exata do exit 1 é inobservável por
#    desenho: o stderr morre no update.log do live). Cura na unit: o live
#    PULA honestamente (condition failed = skipped — sem 'Failed with
#    result' para o gate v1.5.2 reprovar); o rig instalado segue E51.
assert_grep "$REPO/elite/airootfs/etc/systemd/system/elite-bootupdate.service" 'ConditionPathExists=!/run/archiso' "E59: o live PULA a dose (skipped honesto — a cadência E51 é do rig instalado; mídia descartável não se auto-atualiza)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 8→9 NO MESMO COMMIT' "E59: pkgrel elite-system 8→9 NO MESMO COMMIT (lei E41 — a unit do pacote único mudou de conteúdo; âncora na HISTÓRIA, lição do E58: número atual anda, a lei que o cobra é o guard do CI)"

# ── E62 — O PAPEL É DO DONO TAMBÉM (a foto do rig, 05/nov:
#    '/usr/local/bin/craft-update: linha 154: /var/log/elite-update.log:
#    Permissão negada'). O log nasce root:root 644 (a dose ao ligar é a
#    primeira a escrever) e a porta MANUAL do dono escrevia contra a
#    parede — o bash grita o erro de REDIRECIONAMENTO (o '|| true' não o
#    alcança: o diagnóstico é do próprio shell) e as linhas do manual se
#    perdiam inteiras. Cura de duas mãos no ulog.
CU62="$REPO/elite/airootfs/usr/local/bin/craft-update"
assert_grep "$CU62" 'sudo -n true' "E62: o heal do papel NUNCA pede prompt (sudo -n — frio = silêncio honesto, os timers escrevem como root de qualquer jeito)"
assert_grep "$CU62" 'chmod 666 "\$ULOG"' "E62: o papel é aberto para o dono (666 — a casa é de um dono; root mantém, o manual cura pelo sudo que a porta já autorizou)"
assert_grep "$CU62" '\( printf .* >>"\$ULOG" \) 2>/dev/null' "E62: o append viaja em subshell CALADO (mesmo um imprevisto de modo não grita mais — a linha 154 da foto morre por desenho)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 11→12 NO MESMO COMMIT' "E62: pkgrel elite-system 11→12 NO MESMO COMMIT (lei E41 — craft-update mudou de conteúdo; âncora na HISTÓRIA, lição E58/E59: o número atual é lei do guard-pkgrel do CI)"

# ── E70 — A MOLDURA ÚNICA + A ÁREA QUE SE ORGANIZA (o print do dono,
#    shot-20261106-204606: LACT/libadwaita CLARO com headerbar própria;
#    VS Code/Electron em XWayland com titlebar própria — dois sistemas de
#    moldura num só desktop). O xdg-decoration é NEGOCIADO (app que pede
#    CSD vence o <decoration>server do rc.xml) e a libadwaita NÃO lê o
#    settings.ini (lê o color-scheme do dconf). Cura arquitetural na
#    doutrina E54: a moldura vira propriedade do COMPOSITOR.
SK70="$REPO/elite/airootfs/etc/skel"
assert_file "$SK70/.config/code-flags.conf" "E70: code-flags.conf existe no skel (o launcher do code da Arch lê — VS Code nasce Wayland nativo e recebe a moldura do compositor)"
assert_grep "$SK70/.config/code-flags.conf" 'ozone-platform=wayland' "E70: VS Code Wayland nativo (XWayland desenha titlebar própria — a racha do print)"
assert_grep "$SK70/.config/labwc/environment" '^ELECTRON_OZONE_PLATFORM_HINT=auto' "E70: todo Electron ≥28 (AppImage incluído) nasce Wayland nativo pelo hint OFICIAL (a moldura do compositor alcança os AppImages sem flag nenhuma)"
assert_grep "$SK70/.config/labwc/autostart" "color-scheme 'prefer-dark'" "E70: o color-scheme prefer-dark cravado na sessão (a libadwaita NÃO lê settings.ini — o LACT claro do print morre aqui)"
assert_grep "$SK70/.config/labwc/autostart" "gtk-theme 'Catppuccin-Mocha-Standard-Mauve-Dark'" "E70: o gtk-theme do dconf é o MESMO Catppuccin do settings.ini (GTK3-dconf na mesma família do rice — zero sotaque)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-rice" '30-elite-organize.xml' "E70: o craft-rice entrega o fragmento de organização ao lado dos outros (a cura viaja NO PACOTE — a mesma escola E54 que alcança o rig vivo)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-rice" 'identifier=\\".*\\" serverDecoration' "E70: a regra UNIVERSAL está no código do rice (a moldura do compositor para toda janela que negocia — o fim da negociação perdida)"
CTUNE70="$REPO/elite/airootfs/usr/local/bin/elite-tune"
assert_grep "$CTUNE70" '\[8\] SESSÃO: A MOLDURA ÚNICA' "E70: a seção [8] existe no elite-tune (o rig vivo RECEBE a cura — o pacote nunca toca config de usuário, a lei do domínio)"
assert_grep "$CTUNE70" 'code-flags.conf entregue' "E70/[8]: a entrega do code-flags.conf deixa LINHA (tudo que decide deixa rastro — lei E63)"
assert_grep "$CTUNE70" 'ozone-platform=wayland' "E70/[8]: o CONTEÚDO do code-flags.conf viaja NO BIN (padrão craft-rice — o elite-system não carrega skel e o /etc/skel do rig é da época da instalação: copiar do skel era a cura que não alcança o rig antigo, a perícia por download do 1.0-20 flagrou)"
assert_grep "$CTUNE70" "grep -q '\\^ELECTRON_OZONE_PLATFORM_HINT='" "E70/[8]: o append do environment é IDEMPOTENTE (a chave presente nunca é reescrita — a 2ª rodada do tune é silêncio)"
assert_grep "$CTUNE70" "grep -q 'Tema escuro UNIVERSAL \\(E70'" "E70/[8]: o append do autostart tem MARCADOR (o bloco da casa se reconhece — a 2ª rodada não duplica)"
assert_grep "$CTUNE70" 'WAYLAND_DISPLAY="\$WSOCK"' "E70/[8]: o reconfigure vivo usa o SOCKET REAL da fila (wayland-* — a lição E68: SEM chute wayland-0)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 19→20 NO MESMO COMMIT' "E70: pkgrel elite-system 19→20 NO MESMO COMMIT (lei E41 — craft-rice e o skel da sessão mudaram o pacote; âncora na HISTÓRIA, o número atual é lei do guard-pkgrel do CI)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 20→21 NO MESMO COMMIT' "E70.1: pkgrel elite-system 20→21 NO MESMO COMMIT (lei E41 — elite-tune mudou de conteúdo: o code-flags.conf viaja no bin após a perícia por download flagrar o skel vazio no pacote)"

# ── E71 — A DOCK QUE NÃO MENTE VAZIA (relato do dono no dump e8xl) ──────
#    'a dock ainda é bugada — o indicativo de aplicativos abertos somem do
#    nada e as ações se comportam como se o programa não estivesse aberto'.
#    A perícia: o craft-toplevel morria em LOOP (449 mortes / 488 restarts
#    em 1h36) porque o evento parent era declarado não-nulável no C — o
#    parent(NULL) legal do XML oficial matava a conexão Wayland e o
#    renascido servia LIST vazio VÁLIDO com a sessão cheia; a graça da
#    E70 só cobria LIST FALHO. Cura em DUAS pontas: o '?o' no daemon e as
#    três redes na dock (prova no lançamento, dedup em voo, graça do
#    vazio).
assert_grep "$REPO/.ci/build.sh" '1a6aeea295db062e38e53b50bb525c6098eb4b436b4b2d8dfd8e84a174aedb11' "E71 (era f719c2f0, refrescada E95→E97.1): o sha256 NÃO é mais o do C com parent seco (a fonte mudou e os pins acompanharam — o makepkg para se algo destoar)"
assert_nogrep "$REPO/.ci/build.sh" '24d537866c1bc81881dc5f6e69a64b10447ae2de6270f18a6c8d0cf54f81b7be' "E71: o sha256 do C VELHO (parent 'o' seco) está EXTINTO do build (nenhum pin aponta para a fonte doente)"

# ── E89 — A TELA QUE LEMBRA + A DOCK QUE OBEDECE AO CLIQUE + O WAKE QUE
#    PROVA INPUT (dump elite-dump-20261107-190719 do rig 1.0-31 + a lista
#    de UX do dono). CINCO réus, cinco curas com contrato:
#    (1) os 200 Hz que somem no reboot → craft-display (apply/watch/menu);
#    (2) o SIGSEGV do daemon (4× exit=139) → blindagem no C + verbo MIN;
#    (3) o clique na dock que 'nada acontece' → toggle-minimize + dismiss
#        da gaveta;
#    (4) o mouse que ENUMERA e não mexe (usbhid 3-4:1.4) → foto de inputs
#        no hook;
#    (5) o PC que dormia DESBLOQUEADO e ACESO (SUSPEND 5min < LOCK 30min)
#        → a ordem é lei no craft-idle.
CDISP="$REPO/elite/airootfs/usr/local/bin/craft-display"
assert_file "$CDISP" "E89: craft-display EXISTE (a persistência de modo/Hz que o sistema nunca teve — o réu dos 200 Hz que somem)"
assert_grep "$CDISP" 'displays\.conf' "E89: o conf do arranjo é ~/.config/elite/displays.conf (o domínio da casa — mesma pasta do idle.conf)"
assert_grep "$CDISP" 'apply)' "E89: o braço APPLY existe (o arranjo salvo nasce aplicado no autostart — o 200 Hz sem clique nenhum)"
assert_grep "$CDISP" 'watch)' "E89: o braço WATCH existe (a mudança estável do dono grava sozinha — persistência que não depende de lembrar de salvar)"
assert_grep "$CDISP" 'save)' "E89: o braço SAVE existe (a fotografia do AGORA para o conf)"
assert_grep "$CDISP" 'ELITE_RANDR' "E89: craft-display tem seam de teste (ELITE_RANDR — a prova funcional roda sem sessão real, a escola da casa)"
assert_grep "$CDISP" 'wdisplays' "E89: a porta gráfica avançada (wdisplays) mora DENTRO do menu do craft-display (um lugar, uma porta por nível)"
CAUTOSTART="$REPO/elite/airootfs/etc/skel/.config/labwc/autostart"
assert_grep "$CAUTOSTART" 'craft-display apply' "E89: o autostart chama o apply (a tela LEMBRA no boot — o arranjo salvo é a primeira coisa de pé)"
assert_grep "$CAUTOSTART" 'craft-display watch' "E89: o autostart sobe o watch (a escolha do dono grava sozinha pelo resto da sessão)"
CMENUX="$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml"
assert_grep "$CMENUX" 'command="craft-display"' "E89: o menu do desktop tem o item Displays… (a porta 'bem pensada' que o dono pediu — todos os modos do EDID no fuzzel)"
assert_grep "$REPO/elite/packages.add" '^wdisplays$' "E89: o wdisplays EXPLÍCITO na ISO (a porta gráfica não depende de herança silenciosa do upstream — o contrato do menu cobra binário real)"
CTL="$REPO/vendor/craft-toplevel.c"
assert_grep "$CTL" '"MIN "' "E89: o daemon fala o verbo MIN (set_minimized — o TOGGLE da dock, a gramática de toda dock do mundo)"
assert_grep "$CTL" 'TL_SET_MINIMIZED' "E89: o MIN usa o opcode REAL do protocolo (set_minimized=2 — o mesmo zip de leis do ACT com unset_minimized=3/activate=4)"
assert_grep "$CTL" 'POLLHUP' "E89: a blindagem do SIGSEGV mora no loop (POLLHUP/POLLERR sem POLLIN = conexão perdida, NUNCA dispatch sobre fio morto — os 4× exit=139 do dump não têm mais porta)"
assert_grep "$CTL" 'wl_display_get_error' "E89: cada conversa termina com o veredito do fio (get_error após dispatch/roundtrip — erro = saída limpa, o supervisor renasce)"
assert_grep "$REPO/.ci/build.sh" '1a6aeea295db062e38e53b50bb525c6098eb4b436b4b2d8dfd8e84a174aedb11' "E95 (era E89, refrescada E97.1): o sha256 do C acompanhou a fonte (MIN + blindagem + ACOLCHOADO + o reply() do EAGAIN com prazo — o makepkg para se algo destoar, a mesma lei E71)"
assert_nogrep "$REPO/.ci/build.sh" 'ae1fbf22e3fc0e11aa9c3bf62710ff36cfe025274e075906fd78ad1e185270c5' "E97.1: o sha da era E95 está EXTINTO dos DOIS pins (o canal recusou a fonte com ele vivo no template — o ponto cego que a peça dos dois pins mata)"
assert_nogrep "$REPO/.ci/build.sh" '361f6c4fc3065a8d65516cfd673a5ba110aa8005d25a5b8be86bdaf3015761a5' "E95: o sha256 do C VELHO (sem acolchoado — a fonte onde os 9 exit=139 moravam) está EXTINTO do build (nenhum pin aponta para a fonte doente)"
assert_nogrep "$REPO/.ci/build.sh" 'f719c2f0582f0787a26440ebc5566408d5889d8dc037e91505384efb9544f258' "E89: o sha256 do C PRIMITIVO (sem MIN, sem blindagem) está EXTINTO do build (nenhum pin aponta para a fonte doente)"
CDOCK="$REPO/elite/airootfs/usr/local/bin/craft-dock-gui"
assert_grep "$CDOCK" '_tl_min' "E89: a dock fala MIN por id (o clique no app focado MINIMIZA — 'clico novamente no mesmo programa, ele não minimiza… nada acontece' curado)"
assert_grep "$CDOCK" '_dismiss_overlays' "E89: a dock encerra a gaveta aberta ao acordar/lançar (a janela nasce atrás do nwg-drawer — o dono tinha que fechar o menu à mão)"
CIDLE="$REPO/elite/airootfs/usr/local/bin/craft-idle"
assert_grep "$CIDLE" 'E89: ordem do ciclo restaurada' "E89: a ORDEM é lei no start (SUSPEND ≤ LOCK vira LOCK+5 — o PC que dormia DESBLOQUEADO e ACESO aos 5min morre com prova no papel)"
assert_grep "$CIDLE" 'E89: escolha do menu normalizada' "E89: a ordem é lei TAMBÉM no menu (a escolha ilegal não chega a nascer no conf)"
CRUSB="$REPO/elite/airootfs/usr/lib/systemd/system-sleep/elite-resume-usb"
assert_grep "$CRUSB" 'SNAP_IN' "E89: a foto do pre ganha a terceira dimensão (inputs contados por HID — o mouse que ENUMERA e não mexe é visto, o caso usbhid 3-4:1.4)"
assert_grep "$CRUSB" 'btusb' "E89: o BLUETOOTH re-assenta no wake (hci0 reset failed -19 do dump — o rádio que não voltava até o reboot)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 32→33 NO MESMO COMMIT' "E89: pkgrel elite-system 32→33 NO MESMO COMMIT (lei E41 — o C recompila com MIN+blindagem, craft-dock-gui/craft-idle mudaram, craft-display é bin novo, hook/autostart/menu/packages mudaram; âncora na HISTÓRIA, lição E58/E59)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 43→44 NO MESMO COMMIT' "E100: pkgrel elite-system 43→44 NO MESMO COMMIT (lei E41 — a pele v5 do lock no skel + craft-rice/craft-lock/craft-dump mudaram de conteúdo; âncora na HISTÓRIA, lição E58/E59)"

# ═══════════════════════════════════════════════════════════════════════
# E90/E91 — A ÁREA 4 DA ROTAÇÃO + AS 3 LACUNAS DO UX-ROADMAP + AS CURAS
# DAS REGRESSÕES DO 1.0-33 (dump 231955: a dock sumiu, o sono de 7s
# voltou, o lock não mudou — cada réu nomeado com prova)
# ═══════════════════════════════════════════════════════════════════════
# ── R1: o typo que matou a dock (a E89 escreveu "__main_" — main() nunca
# rodava, exit=0 em loop de 5s, DOCK_COUNT=0 no dump 231955) ──
CDOCK2="$REPO/elite/airootfs/usr/local/bin/craft-dock-gui"
assert_grep "$CDOCK2" 'if __name__ == "__main__":' "E91: o typo '__main_' está MORTO (a dock volta a nascer — o crash-loop exit=0 do dump 231955, DOCK_COUNT=0)"
assert_nogrep "$CDOCK2" '^if __name__ == "__main_":' "E91: nenhuma linha com o typo de um underscore sobrevive (a lição: ast.parse NÃO pega typo de string — o contrato pega)"

# ── R2: o selo ACPI fora do veículo (o build copiava 2 hooks POR NOME e
# o elite-sleep-report nunca viajou — o rig 1.0-33 seguiu com o hook
# velho, sono de 7s/9s no journal do dump 231955) ──
assert_grep "$REPO/.ci/build.sh" 'for h in /work/elite/airootfs/usr/lib/systemd/system-sleep/elite-\*' "E91: a cópia de hooks é VARREDURA do diretório (lista fixa enferruja — a mesma lição da ferida dos bins E46; o selo E88 chega ao rig pelo canal)"
assert_grep "$REPO/.ci/build.sh" 'elite-sleep-report' "E91: o elite-sleep-report VIAJA no pacote (o selo ACPI da E88 — a cura do 'suspendeu e voltou em 7s' que nunca chegou ao 1.0-33)"

# ── R3: o lock que não chegava (hyprlock.conf v3 só no skel — home vivo
# nunca o recebe, lei do domínio v3; o dono: "não mudou nada") ──
CRICE="$REPO/elite/airootfs/usr/local/bin/craft-rice"
assert_grep "$CRICE" 'LOCK_FOSSILS' "E91: a lock skin conhece os FÓSSEIS (a versão velha da casa = ninguém personalizou = renova com segurança)"
assert_grep "$CRICE" 'lock-adopt' "E91: a porta EXPLÍCITA --lock-adopt (backup .bak-<stamp> + entrega — a lei do domínio v3 intocada, a novidade a um comando)"
assert_grep "$CRICE" 'ELITE_LOCK_SRC' "E91: o seam de prova (a escola ELITE_* da casa — o teste nunca escreve em /usr)"
assert_grep "$REPO/elite/airootfs/etc/skel/.config/hypr/hyprlock.conf" 'entregue por craft-rice' "E91: o skel da v3 carrega o MARCADOR do rice (o conf da casa se renova em homes vivos nas próximas peles)"

# ── E94: a dock veste o terminal no TUI + a adoção de âncoras no rig ──
CDOCK94="$REPO/elite/airootfs/usr/local/bin/craft-dock-gui"
assert_grep "$CDOCK94" 'info\.get_boolean\("Terminal"\)' "E94: o exec_of consulta o Terminal=true do .desktop (o TUI sem tty nasce e morre — 'btop não abre pela dock', relato do dono 08-11)"
assert_grep "$CDOCK94" 'foot --app-id=' "E94: o foot da casa leva app-id DETERMINÍSTICO (o casamento de janelas fala o nome do app, não o do terminal — a mesma lição E89 das case-variants)"
assert_grep "$CDOCK94" 'def raw_of' "E94: a origem do app vive SEM o casaco (raw_of/binary_of — o comm do /proc e o app_id falam o APP)"
CUPD94="$REPO/elite/airootfs/usr/local/bin/craft-update"
assert_grep "$CUPD94" 'ADOCAO=\(lxqt-policykit pacman-contrib octopi yay flatpak swayosd\)' "E94+E97→E103: a ADOÇÃO DE ÂNCORAS tem FONTE ÚNICA no craft-update (packages.add só nutre a ISO — o rig nunca recebeu a cabeça da fila E58; a E97 soma a tríade da loja de fábrica E o pacman-contrib que o E96 pôs na ISO esquecendo o canal; a E103 soma o swayosd — o OSD do rig do dono nasceu antes da E74 e a barra nunca apareceu)"
assert_grep "$REPO/elite/packages.add" 'lxqt-policykit' "E94: a âncora do rig é a MESMA definição da ISO (sync contratado — a disciplina do pin aplicada à adoção)"
n_sites="$(grep -cE '^[[:space:]]*adota_ancoras$' "$CUPD94" || true)"
assert_eq "$n_sites" "3" "E94: a adoção corre nas TRÊS portas (canal, semanal, manual — uma função, nenhum escopo à mão)"
assert_grep "$REPO/.ci/build.sh" 'usr/local/share/elite/hyprlock/hyprlock.conf' "E91: a pele-mestra viaja NO PACOTE (a mesma escola do fastfetch E73 — fora do pacote nunca chega ao canal)"

# ── E90: craft-dump v2.7 — as provas que o papel deixava cair ──
CDUMP="$REPO/elite/airootfs/usr/local/bin/craft-dump"
assert_grep "$CDUMP" 'wayland-0 wayland-1 wayland-2.*140' "E90: o randr INTEIRO no papel (o teto 30 cortava o 200 Hz do dump 190719 — a lista começava em 1024x768, exatamente onde os modos grandes moravam)"
assert_grep "$CDUMP" 'displays\.conf' "E90: a E89 no papel (o conf em disco + craft-display status — o julgamento da tela que lembra ganha prova DIRETA)"
assert_grep "$CDUMP" 'Wake-on-LAN' "E90: o WOL na caça ao despertar (o r8169 é o réu clássico do 'voltou em 7s' — o papel nunca o fotografou)"
assert_grep "$CDUMP" 'Supports Wake' "E90: o ethtool entrega o Wake-on quando existe (entrou na ISO; sysfs é a prova sempre)"
assert_grep "$CDUMP" 'PME' "E90: a PME no grep do despertar (a outra face do réu PCIe)"
assert_grep "$CDUMP" "dumped core" "E90: os coredumps do toplevel no papel (o réu dos delays da dock — contagem + últimas mortes: zero linhas = cura E89 provada)"
assert_grep "$CDUMP" 'elite-resume-usb' "E90: o relato do rebind no papel (a foto dos inputs, o alvo, o martelo de reserva — a cura do mouse morto com prova DIRETA)"

# ── E90: a descoberta — craft-help + --help na família + a doc no pacote ──
CHELP="$REPO/elite/airootfs/usr/local/bin/craft-help"
assert_file "$CHELP" "E90: craft-help EXISTE (a lacuna nº 1 do UX-ROADMAP: a cirurgia deixa de ser invisível)"
assert_grep "$CHELP" 'O MAPA DOS COMANDOS' "E90: o craft-help se apresenta"
assert_grep "$CHELP" 'craft-help <termo>' "E90: o filtro por termo documentado no próprio mapa"
assert_grep "$CHELP" 'W-S-h repete|A-Tab / W-Tab' "E90: os atalhos REAIS no mapa (a verdade do rc.xml — nada de atalho fantasma)"
assert_grep "$REPO/scripts/apply-overlay.sh" 'craft-help' "E90: o craft-help registrado no file_permissions (o gate 203/EXEC — lição diag-boot2)"
assert_grep "$REPO/.ci/build.sh" 'usr/local/share/elite/docs/SCRIPTS.md' "E90: o SCRIPTS.md viaja NO PACOTE (a doc completa dentro do sistema — a fonte única continua o repo)"
assert_grep "$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml" 'foot -e craft-help' "E90: o menu do desktop abre o mapa (a porta de mouse-first da descoberta)"
# ── E106 — O ENXUGAMENTO DO MENU (a ordem do dono: "muita coisa aqui pode
#    simplesmente ser inútil e pode ser removida") ──
assert_nogrep "$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml" 'craft-update --check' "E106: 'Verificar atualizações' MORREU no menu (o dono: 'os dois é a mesma coisa. No caso o atualizar sistema ele já verifica e já atualiza, se necessário' — provado: o --check é read-only sobre a base LOCAL, o -Syu sincroniza E atualiza; o verbo --check segue vivo no CLI)"
assert_nogrep "$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml" 'label="Leitor de PDF"' "E106: 'Leitor de PDF' MORREU no menu (volume morto — o Aplicativos cobre; o dono mandou enxugar, NADA novo)"
assert_nogrep "$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml" 'label="Editor"' "E106: 'Editor' MORREU no menu (Terminal + nano cobre — volume morto do enxugamento)"
assert_grep "$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml" 'Apps da dock…' "E106: a GAVETA UNIFICADA (o desenho do dono, palavra por palavra: 'um menu unificado… com o marcador se tá ativado… ele só fecharia quando você tirasse o mouse de cima da função ou clicasse fora da tela' — ✓/· que alterna e reabre, ESC/clique-fora fecham)"
assert_grep "$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml" 'Sair da sessão' "E106: o SAIR DIRETO no menu (o dono: reboot e desligar já estão ali — o que faltava era o sair; o menu gráfico segue no ⏻ da topbar)"
assert_grep "$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml" 'Telas — resolução' "E106: o rótulo que DIZ o que faz (o dono: 'esse display, eu não sei nem para que é isso' — o nome era a doença)"
assert_nogrep "$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml" 'label="Calculadora"' "E106→E107: o item Calculadora SAIU do menu (curadoria do dono: 'para abrir programas já tem a parte de aplicativos' — programas vivem no Aplicativos; o padrão do aviso honesto do ramo vazio mora no commit E106, a máquina continua)"

# ── E90: a família inteira com --help (a auditoria E66: 20 de 31 nus) ──
# o contrato casa o VOCÁBULO --help no dispatch (a casa tem 3 gramáticas:
# case "-h|--help|uso)" do sh, "== \"--help\"" do bash e a tupla python
# "-h", "--help" — o que importa é a PORTA existir em cada bin)
E90_BINS="craft-audio-route craft-bars craft-bat craft-clean craft-connect craft-dock-gui craft-drawer craft-dump craft-fix-keys craft-hello craft-idle craft-keyring-wait craft-lock craft-logout craft-menu-dismiss craft-power craft-rice craft-update craft-vigil elite-status"
for b in $E90_BINS; do
    f="$REPO/elite/airootfs/usr/local/bin/$b"
    if grep -q -- '--help' "$f" 2>/dev/null && grep -q -- 'uso: ' "$f" 2>/dev/null; then
        ok "E90/--help: $b responde -h/--help (a descoberta de dentro do sistema)"
    else
        fail "E90/--help: $b NÃO responde -h/--help" "a auditoria E66 nomeou 20 nus; o contrato cobra a família inteira (--help no dispatch + 'uso: ' na saída)"
    fi
done

# ── E90: o veredito sem tocar nada (--check) + o onboarding (hello v2) ──
CUPD="$REPO/elite/airootfs/usr/local/bin/craft-update"
assert_grep "$CUPD" '== "--check"' "E90: craft-update --check existe (a pergunta barata de 'tem atualização?')"
assert_grep "$CUPD" 'zero -Sy, zero root, zero transação' "E90: o --check é READ-ONLY por contrato (o veredito nunca sincroniza a base)"
assert_grep "$CUPD" 'base sincronizada' "E90: a IDADE da base local no veredito (base velha = julgamento honesto do que o pacman JÁ viu)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-hello" 'elite_pointer' "E90: o onboarding depois do retrato (a versão + a última dose + o craft-help — a lacuna nº 3)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-tune" 'última dose' "E90/área 4: o estado do canal na certificação (elite-system/dose/pendências com a idade da base)"
assert_grep "$REPO/elite/packages.add" '^ethtool$' "E90: ethtool na ISO (a prova do WOL na caça ao despertar)"

# ── E90: a vigília fecha a porta (argumento inesperado = 2ª vigília —
# a lei E30 manda UMA por ciclo; o typo humano morre na entrada) ──
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-vigil" 'argumento inesperado' "E90: craft-vigil recusa argumentos com recusa clara (rc 2 — a 2ª vigília acidental nunca nasce)"

# ═══════════════════════════════════════════════════════════════════════
# E95 — O DEMARSHAL BLINDADO + O GPARTED QUE VESTE A SESSÃO + UM TRONO
# POLKIT + O CHAVEIRO QUE O PAM NÃO ABRIU (perícia dos dumps 165011 e
# 225119: 9 exit=139 com offsets idênticos; o gparted morrendo COM A
# SENHA VIVA; o gcr-prompter pedindo em cima do gkr-pam falho)
# ═══════════════════════════════════════════════════════════════════════
CTL95="$REPO/vendor/craft-toplevel.c"
assert_grep "$CTL95" '\{ "elite-pad", "", NULL \}' "E95: o ACOLCHOADO existe (a libwayland lê events[opcode] sem conferir event_count — opcode além da mesa era wl_message de lixo e o parser SEGVa nos 9 exit=139; o pad com assinatura VAZIA faz o opcode selvagem virar closure sã que o dispatcher ignora)"
n_pads="$(grep -c '"elite-pad"' "$CTL95" || true)"
assert_eq "$n_pads" "14" "E95: as DUAS mesas acolchoadas (8 pads no handle + 6 no manager — opcode 8..15 do handle e 2..7 do manager caem em memória NOSSA)"
assert_grep "$CTL95" '16, tl_events' "E95: a mesa do handle declara 16 lugares (8 reais do protocolo + 8 de fôlego)"
assert_grep "$CTL95" '8, mgr_events' "E95: a mesa do manager declara 8 lugares (2 reais + 6 de fôlego)"
assert_grep "$CTL95" 'version < 2 \? version : 2' "E95: o manager nasce em v2 (o evento parent — o da churn dos diálogos transitórios, o perfil dos 9 crashes — some do fio; a dock nunca o usou e o '?o' da E71 segue de cinto)"
assert_grep "$CTL95" 'clients\[i\]\.evt = 0' "E95: o slot reciclado não herda a inscrição de eventos do dono anterior (a conexão de PEDIDOS nunca recebe linha não pedida)"
assert_grep "$CTL95" 'ACOLCHOADO DO DEMARSHAL' "E95: a perícia dos 9 exit=139 mora na fonte (offsets idênticos libwayland-client+0x9ae3, um na rodada do STARTUP — quem ler a mesa sabe por quê)"

EGP="$REPO/elite/airootfs/usr/local/bin/elite-gparted"
assert_file "$EGP" "E95: o bin elite-gparted existe (o motor do gparted que veste o root)"
assert_grep "$EGP" 'ELITE_PKEXEC_BIN' "E95: o seam de prova do pkexec (o teste julga o VESTIMENTA sem polkit — a escola ELITE_*)"
assert_grep "$EGP" 'ELITE_GPARTED_BIN' "E95: o seam de prova do alvo (hermético: nem gparted instalado o teste precisa)"
assert_grep "$EGP" 'exec "\$PKEXEC_BIN" env' "E95: a vestimenta é 'pkexec env' (o pkexec despe o ambiente por LEI — WAYLAND_DISPLAY/XDG_RUNTIME_DIR nomeados EXPLICITAMENTE é a cura da GDK root morta)"
assert_grep "$EGP" 'WAYLAND_DISPLAY="\$\{WAYLAND_DISPLAY:-\}"' "E95: o fio do compositor atravessa com o ${VAR:-} de cinto (sessão sem X11 não explode; Wayland puro é o terreno)"
assert_grep "$EGP" '\-h\|--help\|uso\)' "E95 (lei E66): o bin tem --help (nenhum bin da casa é mudo)"
GPD="$REPO/elite/airootfs/usr/local/share/applications/gparted.desktop"
assert_file "$GPD" "E95: o override gparted.desktop existe na FRENTE do XDG_DATA_DIRS (o environment da sessão põe /usr/local/share primeiro — dock, gaveta e fuzzel resolvem para AQUI)"
assert_grep "$GPD" 'Exec=/usr/local/bin/elite-gparted %f' "E95: o Exec aponta o motor da casa (o upstream em /usr/share fica intocado — a fronteira é só nossa)"
assert_grep "$GPD" 'StartupWMClass=gparted' "E95: a janela casa de volta no botão da dock (o indicador/foco fala o APP — a mesma gramática E94 do raw_of)"
CBARS95="$REPO/elite/airootfs/usr/local/bin/craft-bars"
assert_grep "$CBARS95" 'polkit perdedor aposentado' "E95: UM TRONO POLKIT (o autostart dos homes vivos sobe o polkit-gnome às cegas e a âncora lxqt da E94 criaria DOIS agentes — o diálogo da senha nascendo 2×; o supervisor aposenta o perdedor, canal que alcança rigs vivos)"
assert_grep "$CBARS95" 'keyrings/login\.keyring' "E95: o chaveiro que o PAM não abriu recebe o unlock best-effort NO CHAVEIRO EXISTENTE (o guard é o cinto da v2.10.12: sem chaveiro, quem cria com a senha CERTA continua sendo o PAM)"
assert_grep "$CBARS95" 'gnome-keyring-daemon --unlock' "E95: a porta do unlock é a MESMA do live ('gkr-pam: couldn't unlock' em todo login + o gcr-prompter 2× no dump — o canal craft-bars alcança o home que update nenhum toca)"
CDMP95="$REPO/elite/airootfs/usr/local/bin/craft-dump"
assert_grep "$CDMP95" 'coredumpctl info --no-pager craft-toplevel' "E95: o dump v2.7.1 fotografa o 'SIGSEGV, address' do coredumpctl (NULO ≠ SELVAGEM — a peça que faltava se um 139 resistir ao acolchoado)"
assert_grep "$CDMP95" 'v2.7.1' "E95: a versão do dump no papel (o --update do rig compara versões — a perícia nunca envelhece)"
assert_grep "$REPO/.ci/build.sh" 'usr/local/share/applications/\*\.desktop' "E95→E98: o override VIAJA no pacote pela VARREDURA do dir (a lição E63 fica: fora do pacote nunca chega ao rig pelo canal)"
assert_grep "$REPO/.ci/build.sh" 'gp_install' "E95: o PKGBUILD gera as linhas de instalação da família nova (a mesma dança do fastfetch/lock/docs)"
assert_grep "$REPO/.ci/build.sh" "overwrite '/usr/local/share/applications/\*'" "E95 (E92, o 5º site): o elite-adopt da PONTE leva a família nova (senão a adoção recusa pelo MESMO conflito órfão que o rig flagrou)"
CUPD95="$REPO/elite/airootfs/usr/local/bin/craft-update"
assert_grep "$CUPD95" "'--overwrite' '/usr/local/share/applications/\\*'" "E95: o HOUSE_OVERWRITE do craft-update cobre a família nova (a lista↔payload é a porteira da 40-integration)"

# ── E98: os overrides NoDisplay da loja/theming — a gramática da desktop-entry ──
# (o gparted E95 NÃO entra na fila do NoDisplay: o override dele é FUNCIONAL —
# troca o Exec para o elite-gparted — e a entrada TEM que continuar visível)
for _ov in gparted octopi-notifier octopi-repoeditor qt6ct nwg-look; do
    _ovf="$REPO/elite/airootfs/usr/local/share/applications/$_ov.desktop"
    assert_grep "$_ovf" '^\[Desktop Entry\]$' "E98/gramática: $_ov.desktop abre com [Desktop Entry] (a mesa da spec — meio .desktop quebrado é entrada morta)"
    assert_grep "$_ovf" '^Type=Application' "E98/gramática: $_ov.desktop declara Type=Application (sem Type o launcher engole a entrada em silêncio)"
done
for _ov in octopi-notifier octopi-repoeditor qt6ct nwg-look; do
    _ovf="$REPO/elite/airootfs/usr/local/share/applications/$_ov.desktop"
    assert_grep "$_ovf" '^NoDisplay=true' "E98/gramática: $_ov.desktop carrega o NoDisplay=true (a MESMA desktop-id na frente do XDG_DATA_DIRS — o trilho xgps da v1.2)"
done
ON98="$REPO/elite/airootfs/usr/local/share/applications/octopi-notifier.desktop"
assert_grep "$ON98" '^Name=Octopi Notifier$' "E98/loja: fiel ao upstream aarnt/octopi (notifier/octopi-notifier.desktop — procedência lida no clone do upstream, não no palpite)"
assert_grep "$ON98" '^Exec=/usr/bin/octopi-notifier$' "E98/loja: o Exec do Notifier é o upstream de verdade (oculto NÃO é mutilado — roda na mão se um dia pedir)"
assert_grep "$REPO/elite/airootfs/usr/local/share/applications/octopi-repoeditor.desktop" '^Exec=/usr/bin/octopi-repoeditor$' "E98/loja: o Exec do RepoEditor idem (fiel; a decisão de OCULTAR é curadoria, a entrada não morre)"
assert_grep "$REPO/elite/airootfs/usr/local/share/applications/qt6ct.desktop" '^Exec=qt6ct$' "E98/theming: o Exec do Qt6 Settings pelo nome (o pacote FICA — 'qt6ct fica', a nota do packages.remove; só a UI sai do menu)"
assert_grep "$REPO/elite/airootfs/usr/local/share/applications/nwg-look.desktop" '^Exec=nwg-look$' "E98/theming: o Exec do GTK Settings pelo nome (nwg-look fica instalado — um dia de cursor novo roda na mão)"

phase_end

# ═══ E. E101 — O FÓSSIL DO CACHE NUNCA VENCE A VERSÃO DE HOJE ═══════════
#    A run #153 (tag v2.11.0) nasceu com o PASSADO dentro: o .ci-cache
#    restaurado trouxe o elite-system-1.0-7 de 5 dias atrás, o repo-add
#    RECUSOU o 1.0-44 recém-nascido ("A newer version for 'elite-system'
#    is already present in database") e o pacstrap instalou o fóssil na
#    ISO — o elite-bootupdate sem o skip do live rodou (unit failed), o
#    craft-bars sem a fila E58 elegeu o hyprpolkitagent (crash-loop 21×):
#    as DUAS falhas do verify, UM réu. O mesmo cache derrotou o pin do
#    Brave (1.98.63 aceito com o pin em 1.99.55). Os contratos abaixo
#    cravam as 4 curas no papel — o fóssil não volta nem de cache velho.
BS101="$REPO/.ci/build.sh"

# (1) a purga: pacote da casa recém-construído = fóssil do cache morto
assert_grep "$BS101" 'rm -f /var/cache/elite-local/"\$pkgdir"-\*\.pkg\.tar\.zst' "E101/purga: o fóssil do cache morre ANTES do pacote novo chegar ao repo (dois elite-system no dir = o velho pode vencer o repo-add — a #153 provou)"

# (2) o db nasce de novo: entradas de eras mortas não sobrevivem
assert_grep "$BS101" 'rm -f /var/cache/elite-local/elite-local\.db \\' "E101/db: o db é DESTRUÍDO antes do repo-add (o db restaurado do cache e o gosto do repo-add por versões velhas apontavam o repo pro passado)"
assert_grep "$BS101" 'elite-local\.db\.tar\.gz\.old' "E101/db: nem o .old do cache sobrevive (o fóssil de 5 dias viajou NELE na #153)"

# (3) selo 1: o db referencia o pacote de HOJE
assert_grep "$BS101" 'SELO 1' "E101/selo1: o db do [elite-local] tem que apontar pro pacote que o makepkg acabou de parir (divergência = ELITE-FAIL no minuto 6, não no QEMU do minuto 40)"

# (4) selo 2: a resolução lacrada entrega o pacote de HOJE
assert_grep "$BS101" 'selo_elite_system_resolve' "E101/selo2: a prova de ponta a ponta — o pacman resolve o elite-system de HOJE com o conf lacrado (os mesmos dbs que o pacstrap consome)"
assert_grep "$BS101" 'seal_build_conf && selo_elite_system_resolve && ./mkarchcraftiso' "E101/selo2: o selo está NA CADEIA do build (preflight → selo → ISO; fóssil no resolve = build morto antes de gastar 30 min)"

# (5) o pin do Brave é EXATO — fóssil de outra era não serve de cache hit
assert_grep "$BS101" '^BRAVE_PIN=' "E101/brave: o pin vive NUMA variável (o guard antigo aceitava QUALQUER brave-origin-* — o 1.98.63 do cache derrotava o pin 1.99.55 sem nem tentar)"
assert_grep "$BS101" 'if \[ -f "/var/cache/elite-local/\$BRAVE_PKG" \]' "E101/brave: o cache hit exige o ARQUIVO do pin exato (nome-versão-arquitetura — nada mais serve)"
assert_grep "$BS101" 'find /var/cache/elite-local -maxdepth 1 .*brave-origin-\*.*-delete' "E101/brave: nem no cache hit o fóssil sobrevive (o repo-add adiante processa o dir inteiro — dois brave-origin = o velho pode vencer)"

# anti-drift: BRAVE_PIN == pkgver do heredoc (o check-brave sobe os dois)
BP101="$(sed -n 's/^BRAVE_PIN="\([0-9.]*\)"$/\1/p' "$BS101" | head -1)"
BPV101="$(sed -n '/^pkgname=brave-origin$/,/^EOPKGBUILD$/p' "$BS101" | sed -n 's/^pkgver=\([0-9.]*\)$/\1/p' | head -1)"
assert_eq "$BP101" "$BPV101" "E101/brave: BRAVE_PIN (${BP101:-?}) == pkgver do heredoc (${BPV101:-?}) — as duas fontes do pin nunca divergem (drift = guard caçando versão morta)"

# o guardião sobe o BRAVE_PIN no mesmo bump
assert_grep "$REPO/scripts/check-brave.sh" 'BRAVE_PIN=' "E101/brave: o check-brave.sh atualiza o BRAVE_PIN no bump (single source: sem isto o guard procuraria o pin velho para sempre)"

# (6) a loja sem pilha: o canal não deixa 44 versões do mesmo pacote no ar
assert_grep "$REPO/.github/workflows/publish-packages.yml" 'delete-asset' "E101/loja: publicada a versão de hoje, a OUTRA versão do mesmo pacote sai do ar (o --clobber só cobre nome IGUAL — pkgrel novo é nome novo; a pilha de 4,9 GB nunca mais se forma)"
assert_grep "$REPO/.github/workflows/publish-packages.yml" 'A LOJA SEM PILHA' "E101/loja: a regra tem nome no papel (o dono: 'cheio de assets sujos' — a limpeza é lei, não acaso de uma run)"

phase_end

# ═══ E101.1 — O VENENO SILENCIOSO DAS ASPAS ═══════════════════════════
#    O script do canal vive DENTRO de bash -euc "..." — uma aspa simples
#    no corpo TERMINA a string: o resto do script morre como argumento
#    solto e o step fica VERDE (a run #63 provou na carne: o upload
#    rodou às 20:44:05, a dieta da loja virou poeira, o container saiu
#    0 dois segundos depois com a loja INTACTA). O corpo é LIVRE de
#    aspas simples por lei — o veneno silencioso vira contrato.
CANAL101="$REPO/.github/workflows/publish-packages.yml"
BODY101="$(sed -n "/bash -euc '/,/^            '/p" "$CANAL101" | sed '1d;$d')"
SQ101="$(printf '%s\n' "$BODY101" | grep -c "'" || true)"
assert_eq "$SQ101" "0" "E101.1/canal: ZERO aspas simples no corpo do bash -euc (a aspa termina a string e o step morre VERDE com metade do script executado — a lição da run #63)"

#    E103.1 — A PORTEIRA HONESTA: o filtro do push nasceu podre (a E43
#    escreveu 'branches: ain' sem o colchete de abertura) e o schema
#    leniente do Actions IGNORA filtro inválido — o canal disparava em
#    QUALQUER branch com os paths da casa (funcional por acidente, podre
#    por dentro — a cura viajou VIA API, E103.1). O filtro DIZ o que faz:
#    push no main dispara o canal; a suíte cobra a linha.
assert_grep "$CANAL101" "branches: \[main\]" "E103.1/canal: o filtro do push DIZ o que faz — o main dispara o canal (o filtro inválido que o Actions calava desde a E43 nunca mais volta; a porta escreve a verdade)"

# E101.1 — PARTIAL UPGRADE É FRANKENSTEIN: nenhum prep de container Arch
# usa -Sy sem -u (o rsync 3.5.2-3 da #266/#267 nasceu linkando a
# libcrypto.so.4 nova sobre a imagem com a lib velha — 'error while
# loading shared libraries' e 900 peças em cascata; o container se
# atualiza INTEIRO ou não se atualiza)
PART101="$(grep -rn "pacman -Sy " "$REPO/.github/workflows"/*.yml 2>/dev/null | wc -l)"
assert_eq "$PART101" "0" "E101.1/CI: NENHUM -Sy sem -u nos preps (Arch rolling é inteiro — a libcrypto do rsync da #267 ensinou)"

phase_end

# ═══ E101.2 — A FAMÍLIA .desktop NA LEI E57 ═══════════════════════════
#    A build #154 (v2.11.1) morreu no pacstrap: 14 overrides de menu da
#    E98 entraram NO PACOTE (a varredura gp_install) e a remoção E57
#    nunca ganhou a família — o overlay entregava os MESMOS caminhos e
#    o pacman recusava não-dono em todos ('exists in filesystem' ×14 ×2
#    tentativas). A lei de um dono por caminho agora cobre a família —
#    e quem sobreviver à remoção ABORTA o build antes do pacstrap.
E57SEC="$(sed -n '/E57 — O PACOTE É O ÚNICO DONO/,/^PYE57$/p' "$REPO/.ci/build.sh")"
assert_match "$E57SEC" 'usr/local/share/applications/\*\.desktop' "E101.2/E57: a remoção E57 cobre a família .desktop da E98 (um dono por caminho — o pacote entrega, o overlay cala; a #154 morreu no buraco)"
assert_match "$E57SEC" '\.desktop sobreviveram à remoção' "E101.2/E57: sobrevivente da família .desktop ABORTA o build antes do pacstrap (a regra E92 estendida — nunca seguir sabendo)"

# E101.2 — A LEI GERAL (o buraco era estrutural): toda família de caminho
# que o template instala NO PACOTE e que EXISTE no overlay tem que ter a
# sua remoção no bloco E57. As famílias de hoje: fastfetch (overlay tem,
# E92 remove), applications (overlay tem, E101.2 remove) — as demais
# (hyprlock/docs/src/hooks/libalpm) moram em caminhos que o overlay não
# carrega. O contrato cobre AS DUAS presentes:
for fam in 'usr/local/share/elite/fastfetch' 'usr/local/share/applications'; do
    assert_match "$E57SEC" "${fam}" "E101.2/E57: a família '$fam' (presente no overlay) tem remoção no bloco E57 — família nova no pacote ⇒ família nova na remoção (a lição da #154 em lei)"
done


# ── E105 — O DUMP 195332 PERICIADO (o polkit em loop, o avatar que era o
#    wallpaper, o 60 Hz que o stamp escondia, o fantasma da top bar) ────
assert_grep "$REPO/vendor/elite-polkit-listener.c" 'polkit_unix_session_new' \
    "E105/polkit: o subject nasce EXPLÍCITO (o polkit do rolling cobra o subject — a forma simples morria na asserção POLKIT_IS_SUBJECT, dump 195332)"
assert_grep "$REPO/vendor/elite-polkit-listener.c" '/proc/self/sessionid' \
    "E105/polkit: a 1ª fila do subject é a sessão logind do kernel (XDG_SESSION_ID é o fallback)"
assert_grep "$REPO/vendor/elite-polkit-listener.c" 'sem subject honesto' \
    "E105/polkit: sem subject = exit 1 com mensagem clara (nunca loop cego — a fila assume o trono)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bars" 'polkit DEMOÇÃO' \
    "E105/polkit: 3 arranques mortos (≤5s) = o fallback da fila assume o trono (o loop cego virou rede)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bars" 'polkit-fails' \
    "E105/polkit: o tempo de vida de cada saída vai para o papel (XDG_RUNTIME_DIR; sucesso zera)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-lock" '/\^background \{/,/\^}/ s\|' \
    "E105/lock: o sedito do wallpaper fica PRESO ao bloco background (o avatar E103 deixa de virar wallpaper)"
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/craft-lock" 'sed "s\|' \
    "E105/lock: o sedito GLOBAL (sed com s| na abertura) não existe mais"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-lock" 'lock-spawn.lock' \
    "E105/lock: a porteira flock única (a corrida idle×sleep-hook não gera spawn paralelo; a porta fecha com o hyprlock vivo)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-lock" 'spawn argv' \
    "E105/lock: a foto do nascimento no lock.log (argv + ppid = a porta e QUEM chamou)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-display" 'display-diverge' \
    "E105/display: a divergência conta em papel (6 ticks ≈ 30s — a escolha do dono em curso termina dentro)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-display" 'REAPLICANDO o arranjo do dono' \
    "E105/display: o stamp não é fé — conf ≠ realidade estável = o arranjo salvo volta (o 60 Hz escondido morre)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-display" 'fail:N|RE-TENTANDO|stamp honesto' \
    "E106/display: o stamp é HONESTO (escrito DEPOIS do feito, ok/fail:N com retry de 6 — a v2.6 escrevia 'sucesso antecipado' antes do apply e o fail era TERMINAL: um boot de link frio muteava a sessão inteira até o reboot, o réu dos 200 Hz do dump 20261112)"
assert_grep "$REPO/elite/airootfs/etc/skel/.config/waybar/config.top" '"format-stopped": ""' \
    "E105/topbar: o stopped não prende mais o módulo (o fantasma da aba fechada sai — a promessa do comentário vira fato)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'playerctl -l' \
    "E105/dump v2.10: a foto da MÍDIA (quem está no barramento — o próximo fantasma nasce com nome)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'lock\.log' \
    "E105/dump v2.10: a foto do LOCK (nascimentos + lock vivo + journal — a próxima denúncia de dupla senha nasce assinada)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 49→50 NO MESMO COMMIT' \
    "E106/E41 (âncora histórica, refrescada na E107): a colheita do dump 161718 no heredoc do PKGBUILD (âncora do game watch, polkit com subject, a dupla senha do lock, o stamp honesto do display, o menu enxugado 21→17, o contador honesto, o fantasma morto em três mãos)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bars" '\^bash /usr/local/bin/craft-game watch\$\|\^/usr/bin/env bash /usr/local/bin/craft-game watch' \
    "E106/bars: a âncora do game watch casa o CMDLINE REAL (o shebang env-bash apresenta 'bash …' — o padrão '^/usr/local/bin/…' JAMAIS viu o processo vivo: 1540 restarts, 12 pares vivos no ps do dump, o log em loop de 5s desde o boot — E48 a 3ª vez na casa)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bars" 'pkill -f .\^/usr/bin/lxqt-policykit-agent' \
    "E106/bars: a aposentadoria do lxqt por CMDLINE (o -x casa COMM e o comm é cortado em 15: 'lxqt-policykit-' — o residente nunca saía da sala e o listener não registrava; a fila E105 girava em falso)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bars" 'XDG_SESSION_ID="\$_pk_sid"' \
    "E106/bars: o lançador injeta o SUBJECT (o agente morria em TODO arranque com assertion POLKIT_IS_SUBJECT — XDG_SESSION_ID ausente na sessão SDDM+labwc; sem agente, TODO pedido de privilégio do menu morria calado)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bars" 'pgrep -x labwc' \
    "E99/bars: o GATE DO COMPOSITOR — supervisor DORME sem labwc (a janela morta do logout respawnava waybar/dock/toplevel/OSD/display-watch a cada 5s; cada um nascia sem display e morria em coredump — o réu 181504 da fila E99)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bars" 'supervisor DORME' \
    "E99/bars: a transição do gate loga UMA vez no bars.log (o gap de logout não vira spam — o papel conta o que o supervisor decidiu, não 20 linhas iguais)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bars" 'lm=5' \
    "E99/E33/bars: o clamp do LOCK_MIN espelha o craft-idle DE VERDADE (o comentário jurava espelho e o número era 10 — fábrica é 5 no idle.conf e no clamp do irmão; o gate é '-gt 0', zero mudança de comportamento, o papel que acordou)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" 'unlock_fresco 15' \
    "E106/idle: o termômetro do DESTRAVO guarda o sleep-hook E o suspend (o suspend em voo recriava o lock 1s após o destravo — a dupla senha do dump; o guard antigo só via o lock, nunca as mãos)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-vigil" 'suspend ABORTADO na última olhada' \
    "E106/vigil: a última olhada antes do sono (pgrep FRESCO imediatamente antes do systemctl — o tick de 30s é amostra, o sono é flagrante; sono sobre destravo nunca mais)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-idle" 'wake-cycle' \
    "E106/idle: o ciclo de wake é UM SÓ (mutex de 3s — três braços corriam o off→on em paralelo e a intercalação off(A) on(B) off(C) deixava a tela ESCURA com todos logando sucesso: o 'perde a imagem ao despertar')"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-bgapps" 'swayosd\*\|lxqt-policykit\*' \
    "E106/bgapps: os daemons saem da lista de programas (o SwayOSD era o 'programa em primeiro plano que não sei para quê' — ressuscitado ≤5s pelo supervisor; o lxqt-policykit- com o comm cortado JAMAIS casava o prefixo polkit\* e o dono matava o agente pelo menu)"
assert_grep "$REPO/elite/airootfs/etc/skel/.config/waybar/config.top" '"interval": 5' \
    "E106/topbar: o contador atualiza a cada 5s (a pílula de 30s mentia por até meio ciclo — 'acusa um programa, você clica e não tem nada'; o custo é o mesmo fork de ps do módulo pulseaudio que já roda a cada segundo)"
assert_grep "$REPO/elite/airootfs/usr/lib/systemd/system-sleep/elite-resume-display" 'display-resume' \
    "E106/resume: o marco do resume (a fronteira ESCOLHA × REVERSÃO — o watch NÃO grava a reversão do driver: a escolha de 200 Hz do dono saía do disco PARA SEMPRE em ~8s, antes do reconcile acordar)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/elite-post-transaction" 'calamares.desktop' \
    "E106/post-transaction: o fantasma não renasce (a dose REINSTALAVA o calamares.desktop em todo rig — o elite-sweep o removia 1× e a próxima dose o ressuscitava; o 'Starchcraft' que o dono viu nascer do nada)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-lock" 'exec hyprlock -c "\$conf" 9>&-' \
    "E106/lock: a porteira solta o exec (o fd 9 acompanhava o hyprlock VIVO — todo --if-needed paralelo esperava 2s e decidia com pgrep de até 2s atrás; a janela exata da dupla senha)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-menu" 'limpa_state' \
    "E106/menu: o state é removido SÓ se ainda é MEU (o rm incondicional apagava o state do menu NOVO no cross-dismiss: toggle cego, dismiss mudo, menus vazando — o dump fotografou 2× 'Encerrar' vivos)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-game" 'GAME_PATS=' \
    "E106/game: a família é ERE sobre o comm cortado (o pgrep -x wine64-preloader JAMAIS viu o Wine 64-bit — comm 'wine64-preload' em 15 chars; o modo automático nasceu cego para a família mais comum do dono)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-game" 'NOTE_URGEN=normal' \
    "E106/game: o feedback que o dono não via (a política low→muted do swaync engolia TUDO — on/off/Automático/Status falavam para o stdout do labwc; agora sobem normal e somem em 8s)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-help" 'pausa_final' \
    "E106/help: a pausa do E96 que o irmão nunca recebeu (a janela 'abre e fecha' do dono — o mapa imprimia e o foot fechava junto)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-gui" 'RAW_DENY_STEMS' \
    "E106/dock: a denylist do raw (o gcr-prompter 'raw entrou/saiu' no dock.log — diálogo de daemon não é aplicativo; o polkit-gnome já tinha entrado 2×)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dock-gui" 'timeout_add\(600, self\._dock_menu' \
    "E106/dock: o menu fica de pé (Fixar/Remover REABREM o menu com o verbo alternado — 'o menu fecha e depois faz a ação… toda vez abrir o menu novamente')"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'idle-write-fail' \
    "E106/dump: o buraco preto do papel entra no retrato (o boot inteiro SEM UMA linha no idle.log — braços rodaram e a escrita falhava calada; owner+mode dos logs e o fallback de escrita no papel)"

# ── E107 — A BOMBA DO MENU + AS TRÊS CARGAS DOS 200 Hz + AS PORTAS ──────
# (o dump 20261112-200537 periciado: o menu 'de 21 para 3', o displays.conf
#  com um TRAÇO no lugar do 200 Hz e o eco duplo de 5s no display.log —
#  o retry que anunciava e recusava, o save que gravava transição)
C107M="$REPO/elite/airootfs/etc/skel/.config/labwc/menu.xml"
if python3 -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' "$C107M" >/dev/null 2>&1; then
    ok "E107/menu: o menu.xml PARSEIA como XML de verdade (o libxml2 do labwc aceita — a v2.11.4 morreu 'not well-formed line 74': um verbo de CLI citado com dois hífens dentro de comentário, o arquivo INTEIRO rejeitado e todo rig da dose 1.0-50 caiu no menu de fábrica de 3 itens — 'de 21 para 3')"
else
    fail "E107/menu: o menu.xml NÃO PARSEIA" "o labwc rejeita o arquivo inteiro e o rig cai no menu de fábrica (Terminal/Reconfigure/Exit) — o botão direito morre de novo"
fi
assert_grep "$C107M" 'A LEI DO COMENTÁRIO' "E107/menu: a lei escrita na própria pele (dois hífens seguidos dentro de comentário são proibidos pela espec XML — a bomba da v2.11.4 documentada no arquivo que ela quase comeu)"
assert_grep "$C107M" 'AppImages…' "E107/menu: a porta do AppImage no botão direito (o registrador da E97 era CLI invisível — 'adiciono o AppImage e ele já nasce com ícone e atalho como programa nativo')"
assert_grep "$C107M" 'command="craft-appimage menu"' "E107/menu: o item chama o BRAÇO menu do craft-appimage (registrar/remover/ver com desfecho na tela)"
assert_grep "$C107M" 'Flatpaks…' "E107/menu: a porta do Flatpak no botão direito ('simplifies installing, uninstalling, and cleaning up leftover Flatpak data' — a gestão sem terminal)"
assert_grep "$C107M" 'command="craft-flatpak"' "E107/menu: o item lança o craft-flatpak (o bin NOVO da E107)"
assert_grep "$C107M" 'label="Terminal"' "E107/menu: o Terminal fica (o dono, palavra por palavra: 'pode ter o terminal, que é um negócio mais universal do sistema')"
assert_nogrep "$C107M" 'label="Navegador"' "E107/menu: o Navegador SAI (programa vive no Aplicativos — a curadoria do dono)"
assert_nogrep "$C107M" 'label="Arquivos"' "E107/menu: o Arquivos SAI (o menu é de AÇÕES DE SISTEMA — o mesmo desenho)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-rice" 'xml_ok' \
    "E107/rice: o gate de XML na porta do rig (pele doente NÃO viaja ao home — a pele viva segue no lugar: menu velho funcionando vence menu de fábrica de 3 itens)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-rice" 'renovação RECUSADA' \
    "E107/rice: a recusa é LOUD (a suíte E107 é o juiz principal; esta porta segura o rig se uma pele doente passar)"
assert_nogrep "$REPO/elite/airootfs/usr/local/bin/craft-display" 'nada a fazer \(o menu aplica à mão\)' \
    "E107/display: A MENTIRA MORRE (a v2.11.4 anunciava 'RE-TENTANDO' na fora e recusava DENTRO — o eco duplo de 5s no display.log do dump, o contador congelado em 1/6 para sempre)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-display" 'APLICADOR PURO' \
    "E107/display: a aplicadora não lê stamp nenhum (a máquina de estados mora SÓ no do_apply — as duas gramáticas de stamp da v2.11.4 brigavam no mesmo corpo e o retry era teatro)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-display" 'modo_em_curso' \
    "E107/display: a transição não é escolha (o save e o watch consultam a marca de modo atual — nada de 'mode:-' no conf)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-display" 'save: RECUSADO' \
    "E107/display: o save RECUSA lixo com a prova no papel (o displays.conf do rig amanheceu com um TRAÇO no lugar do 200 Hz, 19:57:08 — o 'tá salvando lixo' na letra do dono)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-display" 'NÃO grava \(o conf salvo é a fonte da verdade' \
    "E107/display: o watch SÓ grava com o apply da sessão assentado (o default do boot gravado como escolha era o envenenamento — o conf era sobrescrito 1 minuto após o boot)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-display" 'n_fail=\$\(\(n_fail \+ 1\)\)' \
    "E107/display: o contador ANDA de verdade (fail:1, fail:2… teto 6 — a v2.11.4 relia um stamp vazio e eternizava fail:1)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'labwc menu.xml' \
    "E107/dump: A FOTO DO MENU no papel (parse com veredito + a pele vs a mestre com sha256 — o ponto cego que escondeu o réu do 'de 21 para 3' morre)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-dump" 'HOME=.UHOME XDG_CONFIG_HOME=.UHOME/.config craft-display status' \
    "E107/dump: a injeção do env do dono expande NO PAI (a E106 escapava URUNTIME/UHOME com contra-barra — o filho expandia VAZIO e o status saía cego 'HOME=<não setado>')"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-clean" 'octopi' \
    "E107/clean: o cache do octopi no 'bem completinho' (nomeado pelo dono: 'limpa cache do octopi')"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-clean" 'thumbnails' \
    "E107/clean: miniaturas órfãs no relatório (medidas ANTES — o número é prova, não impressão)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-clean" 'yay' \
    "E107/clean: o cache de build do yay (a loja de fábrica E97 deixa palco atrás)"
assert_file "$REPO/elite/airootfs/usr/local/bin/craft-flatpak" "E107/flatpak: o bin existe (a gestão de Flatpaks SEM TERMINAL — o item 'Flatpaks…' do botão direito)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-flatpak" 'delete-data' \
    "E107/flatpak: os DADOS órfãos têm limpeza própria (o 'leftover Flatpak data' que o dono nomeou — uninstall --unused com --delete-data)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-flatpak" 'instalar\|remover\|limpar\|atualizar' \
    "E107/flatpak: os verbos têm porta CLI (o menu é a frente; o terminal é opção, não prisão)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-appimage" '= "menu"' \
    "E107/appimage: o braço menu existe (a porta do botão direito — registrar/remover/ver)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-appimage" 'die_menu' \
    "E107/appimage: o erro SOBE NA TELA no menu do desktop (o stdout do labwc morre no ar — morte calada nunca mais)"
assert_grep "$REPO/scripts/apply-overlay.sh" 'craft-flatpak' \
    "E107/overlay: o bin novo no file_permissions (a ferida E89: sem o 755 no live é 203/EXEC — o gate flagrou)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 51→52 NO MESMO COMMIT' \
    "E99/E41 (era 'pkgrel=51', âncora REFRESCADA — a lição E58/E59: o número atual é lei do guard-pkgrel do CI, o contrato estático ama a HISTÓRIA; o bump de hoje paga o craft-bars do gate do compositor E99 + o espelho do clamp E33)"
assert_grep "$REPO/.ci/build.sh" 'pkgrel 50→51 NO MESMO COMMIT' \
    "E107/E41: a razão do bump no heredoc (a história viaja no papel)"
assert_grep "$REPO/elite/airootfs/usr/local/bin/craft-help" 'craft-flatpak' \
    "E107/help: o mapa conhece a porta nova (a descoberta não depende de sorte)"
assert_grep "$REPO/docs/SCRIPTS.md" 'craft-flatpak' \
    "E107/doc: a doc que viaja no pacote conhece o bin novo"

phase_end
