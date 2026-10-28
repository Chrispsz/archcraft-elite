#!/usr/bin/env bash
# =====================================================================
#  scripts/log-forensics.sh — GATE de forense do log de build (v1.5.2)
#
#  DIRETRIZ DO DONO (22/out/2026, pós-v1.5): "os agentes do repositório
#  devem analisar justamente os logs minuciosamente; esses erros não
#  podem passar ou serem tratados como algo normal". Este gate é a
#  metade DETERMINÍSTICA da diretriz (a metade semântica são os agentes
#  deepseek/mimo do agents.yml, sob demanda): varre o log inteiro da build e
#  transforma padrão de erro conhecido em run VERMELHA — ANTES do
#  release, não no burn test do dono.
#
#  PROVA DE CONCEITO (logs reais, forense da v1.5.2): o log da build
#  v1.4 (run 39804335535, VERDE e releaseada) contém 5 padrões fatais
#  literais — "target not found: cachyos-keyring", "could not determine
#  root mount point /", "not enough free disk space" — e a ISO saiu sem
#  o keyring populado (causa-raiz do "signature unknown trust" do burn
#  test). Este gate teria barrado aquela release. O log da v1.5
#  (run 39864937531) passa limpo: benignos auditados, zero fatais.
#
#  Cada padrão FATAL é um bug REAL deste projeto (a história é a
#  especificação — nada aqui é teoria):
#    · "target not found"               v1.4/v1.5.0: repo local invisível
#                                      no chroot (pacstrap -C não copia)
#    · "could not determine root mount
#      point" / "not enough free disk
#      space"                          v1.5.1: CheckSpace lê mtab sem "/"
#                                      (84G livres, erro falso)
#    · "is unknown trust" /
#      "signature is invalid"          v1.4: keyring ausente — E2/E3
#                                      falharam EM SILÊNCIO
#    · "invalid or corrupted package"  VEJO CONDICIONAL ABAIXO (v2.10.5:
#                                      o preflight re-baixa e o round
#                                      seguinte fecha o cache — a 2ª
#                                      build v2.10.5 provou: 3 pacotes
#                                      com checksum ruim no round 1,
#                                      cache completo no round 2, ISO
#                                      sã com sha256)
#    · "conflicting dependencies"      transação abortada por conflito
#    · "[Ff]ailed to install packages" pacstrap abortou (rootfs
#                                      incompleto = ISO inútil)
#    · "failed to synchronize"         VEJO CONDICIONAL ABAIXO (v2.10.5:
#                                      o re-sync do preflight imprime essa
#                                      string num build SADIO — mesma
#                                      janela do #116; FATAL incondicional
#                                      era falso positivo)
#    · "No space left on device"       disco REAL cheio (distinto do
#                                      falso do mtab)
#
#  CONDICIONAIS (fatal só sem a recuperação comprovada no mesmo log):
#    · "error invoking external downloader" → benigno SE o log prova a
#      recuperação (baseline Arch injetada / ELITE-BUMP — o caso libyuv
#      do CachyOS, mirrors quebrados, fallback documentado no build.sh)
#    · "command failed to execute correctly" → benigno SE toda ocorrência
#      estiver a ≤3 linhas de grub-editenv/grub-mkconfig (hook do grub no
#      chroot do airootfs: /boot/grub não existe no live — o grub do LIVE
#      é gerado pelo mkarchiso FORA do chroot e o do DISCO INSTALADO é
#      gerado pelo Calamares num /boot real; o gate verify-install boota
#      o disco e prova que não afeta produto)
#
#  BENIGNOS DOCUMENTADOS (auditados, nunca falham — se um deles aparecer
#  em contexto novo, o gate é revisitado EXPLICITAMENTE, nunca mudo
#  por conveniência):
#    · "Failed to resolve specifier: uninitialized /etc/" — tmpfiles do
#      journal-nocow em chroot (comportamento stock do archiso)
#    · "gpg: Note: third-party key signatures using the SHA1" — gnupg
#      moderno importando keyring antigo (nota informativa)
#    · "No debugging symbols" — strip do makepkg sem índice de debug
#    · "Skipping verification of source file PGP signatures" — fontes do
#      AUR pinadas por sha256 no PKGBUILD (upstream sem sigs)
#    · "Possibly missing firmware for module" — firmwares licenciados
#      fora do linux-firmware (mkinitcpio stock, toda ISO Arch)
#    · "is not a mountpoint. This may have undesirable side effects" —
#      mkarchcraftiso rodando em container docker (bind mount)
#    · "Cannot start unit with --now when systemd is not running" —
#      systemctl enable em chroot sem systemd vivo
#    · "Wrap blueprint-compiler.wrap type git not found" — meson usa o
#      fallback do wrap (comportamento normal no pwvucontrol)
#    · "grub-editenv: error: failed to get canonical path" — vide
#      condicional grub acima
#    · "grub.cfg.new: No such file or directory" — idem (a linha do
#      grub-mkconfig que segue o grub-editenv no chroot)
#
#  USO:  bash scripts/log-forensics.sh <arquivo-de-log>
#  EXIT: 0 = log aceito (benignos listados como auditoria)
#        1 = padrão FATAL reconhecido — a build NÃO pode seguir
#        2 = uso errado (log ausente — erro de chamada, não de build)
# =====================================================================
set -uo pipefail

LOG="${1:-}"
if [[ -z "$LOG" || ! -f "$LOG" ]]; then
  echo "✖ forense: log ausente ou inacessível: '${LOG}'"
  echo "  uso: bash scripts/log-forensics.sh <arquivo-de-log>"
  exit 2
fi

FATAL=0

count() { grep -cE -- "$1" "$LOG" 2>/dev/null || true; }
report_fatal() {   # $1: descrição  $2: ocorrências
  printf '  ✖ FATAL   %s — %sx\n' "$1" "$2"
  FATAL=1
}
report_benign() {  # $1: descrição  $2: ocorrências
  printf '  ✔ benigno %s — %sx\n' "$1" "$2"
}

echo "── Forense do log de build: $(basename "$LOG") ($(wc -l < "$LOG") linhas) ──"

# ── FATAIS incondicionais (a história como especificação) ────────────
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pat="${line%%|*}"
  desc="${line#*|}"
  n=$(count "$pat")
  (( n > 0 )) && report_fatal "$desc" "$n"
done <<'PATTERNS'
target not found|pacote não resolvível no chroot (v1.4/v1.5.0: repo local invisível — a ISO saía sem o keyring)
could not determine root mount point|CheckSpace sem / no mtab do chroot (v1.5.1)
not enough free disk space|disco cheio FALSO — mesma causa do mtab (v1.5.1; o REAL é 'No space left on device')
is unknown trust|assinatura sem confiança (a v1.4 saiu assim — burn test do dono pegou)
signature from .* is invalid|assinatura inválida (E3 -Sy falhava EM SILÊNCIO na v1.4 — achado forense v1.5.2)
is marginally trusted|assinatura marginalmente confiável (keyring incompleto)
conflicting dependencies|conflito de dependências → transação abortada
[Ff]ailed to install packages|pacstrap abortou — rootfs incompleto (ISO inútil)
No space left on device|disco REAL cheio (distinto do falso do mtab)
PATTERNS

# ── CONDICIONAL: downloader sem recuperação de baseline ──────────────
n=$(count 'error invoking external downloader')
if (( n > 0 )); then
  if grep -qE 'ELITE-BUMP|baseline Arch injetado' "$LOG"; then
    report_benign "downloader falhou E baseline injetada depois (libyuv — mirrors CachyOS quebrados, fallback do build.sh)" "$n"
  elif grep -q 'Preflight: cache completo' "$LOG"; then
    # v2.11 — run #116: janela de 404 transitória (propagação do mirror
    # archcraft). O preflight v3 tem DOIS caminhos de cura: baseline p/ URL
    # realmente quebrada e re-sync p/ transiente (a sonda HEAD não achou URL
    # quebrada → round seguinte fechou o cache). O gate só reconhecia o 1º —
    # falso positivo que reprovou uma ISO que se curou sozinha. Recuperação
    # honesta = o cache FECHOU (se o round 3 também tivesse falhado, o
    # build.sh aborta e NEM CHEGA ao forense — este ramo não mascara nada).
    report_benign "downloader falhou E o preflight re-sincronizou e fechou o cache depois (janela de 404 transitória — run #116)" "$n"
  else
    report_fatal "downloader falhou SEM recuperação (nem baseline nem cache fechado depois)" "$n"
  fi
fi

# ── CONDICIONAL: 'invalid or corrupted package' com cura do preflight ──
# v2.10.5 — A 2ª BUILD v2.10.5 PROVOU EM CAMPO: qt5-virtualkeyboard,
# wlrctl e craft-toplevel saíram com checksum ruim no round 1 (download
# parcial de mirror), o --noconfirm apagou e o round 2 fechou o cache —
# ISO gerada com sha256 e o forense a reprovou (falso positivo). A cura
# é a MESMA lei dos irmãos: recuperação honesta = o cache FECHOU depois.
# Se o cache nunca fechou, o build aborta antes do forense (rounds
# esgotados) — este ramo não mascara nada; e a transação do PACSTRAP
# morta por corrupção segue coberta: sem 'cache completo' no log é FATAL.
n=$(count 'invalid or corrupted package')
if (( n > 0 )); then
  if grep -q 'Preflight: cache completo' "$LOG"; then
    report_benign "pacote corrompido no download E o preflight re-baixou e fechou o cache depois (checksum transitório de mirror)" "$n"
  else
    report_fatal "pacote corrompido SEM recuperação (transação abortada — sem 'Preflight: cache completo' depois)" "$n"
  fi
fi

# ── CONDICIONAL: 'failed to synchronize' com cura do preflight ─────────
# v2.10.5 — A MESMA LEI DO DOWNLOADER: o preflight v3 imprime o stderr do
# round que falhou ('-Syw falhou — stderr do próprio -Syw') e o round
# seguinte fecha o cache ('Preflight: cache completo'). Um 404 transiente
# de DB sync num build SADIO continha a string fatal — falso positivo da
# classe #116. A cura é honesta pelo mesmo argumento do downloader: se o
# cache NUNCA fechou, o build.sh aborta no round 3 e NEM CHEGA ao forense
# (e o pacstrap morto segue coberto por '[Ff]ailed to install packages').
n=$(count 'failed to synchronize')
if (( n > 0 )); then
  if grep -q 'Preflight: cache completo' "$LOG"; then
    report_benign "synchronize falhou E o preflight re-sincronizou e fechou o cache depois (transiente — janela do #116)" "$n"
  else
    report_fatal "pacman -Sy falhou SEM recuperação (rede/lock — sem 'Preflight: cache completo' depois)" "$n"
  fi
fi

# ── CONDICIONAL: 'command failed' fora de contexto grub ───────────────
# LIMITAÇÃO CONHECIDA (v2.10.5, auditoria): a janela de 3 linhas para trás
# pode 'abençoar' uma falha não-grub que por acaso desça perto de menção
# ao grub — falso negativo teórico. A janela NÃO foi apertada sem o log
# real do #116 em mãos (o gate é ciência: regra nova sem prova quebra a
# cura provada; as fixtures da suíte definem a verdade atual).
n_total=$(count 'command failed to execute correctly')
if (( n_total > 0 )); then
  n_grub=0
  while read -r ln; do
    start=$(( ln - 3 )); (( start < 1 )) && start=1
    if sed -n "${start},${ln}p" "$LOG" | grep -qE 'grub-editenv|grub-mkconfig'; then
      n_grub=$(( n_grub + 1 ))
    fi
  done < <(grep -nE 'command failed to execute correctly' "$LOG" | cut -d: -f1)
  if (( n_grub == n_total )); then
    report_benign "hook 'command failed' — TODOS em contexto grub no chroot (live usa grub do mkarchiso; disco gera o próprio no Calamares)" "$n_total"
  else
    report_fatal "hook 'command failed' FORA de contexto grub ($(( n_total - n_grub )) de $n_total)" "$n_total"
  fi
fi

# ── BENIGNOS documentados (auditoria, não falha) ──────────────────────
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pat="${line%%|*}"
  desc="${line#*|}"
  n=$(count "$pat")
  (( n > 0 )) && report_benign "$desc" "$n"
done <<'PATTERNS'
Failed to resolve specifier: uninitialized /etc/|tmpfiles journal-nocow em chroot (stock archiso)
third-party key signatures using the SHA1|nota do gnupg ao importar keyring antigo
No debugging symbols|strip do makepkg: índice de debug ausente (normal)
Skipping verification of source file PGP signatures|fontes pinadas por sha256 (upstream AUR sem sigs)
Possibly missing firmware for module|firmwares licenciados fora do linux-firmware (mkinitcpio stock)
is not a mountpoint. This may have undesirable side effects|mkarchcraftiso em container docker (bind)
Cannot start unit with --now when systemd is not running|systemctl enable em chroot sem systemd
Wrap blueprint-compiler.wrap type git not found|meson usa o fallback do wrap (pwvucontrol)
grub-editenv: error: failed to get canonical path|grub-editenv no chroot do live (grub.cfg.new não existe ali)
grub\.cfg\.new: No such file or directory|grub-mkconfig no chroot do live (sequência do grub-editenv acima)
PATTERNS

echo "──────────────────────────────────────────────────────────────────"
if (( FATAL )); then
  echo "Veredito: ✖ FATAL — padrão de erro reconhecido no log da build."
  echo "  'Build verde com erro silencioso' acabou: investigue ANTES do release"
  echo "  (a v1.4 saiu assim — sem cachyos-keyring — e queimou o burn test do dono)."
  exit 1
fi
echo "Veredito: ✔ log limpo — nenhum padrão fatal; benignos auditados acima."
exit 0
