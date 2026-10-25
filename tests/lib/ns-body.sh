#!/usr/bin/env bash
# tests/lib/ns-body.sh — o corpo do firstboot REAL (não-dry), isolado do host.
#
# Executado pela fase 4 em um de dois modos:
#   · unshare -rm  → dev machine: tmpfs em /etc e /var — escritas reais que
#                    evaporam com o namespace (o host fica INTOCADO, e a fase
#                    prova isso fora do ns)
#   · root direto  → container efêmero do CI (archlinux:base-devel): escrever
#                    no /etc do container é seguro, ele morre com o job
#
# Recebe por env (herdado de with_mocks + fases):
#   TUNE        caminho do elite-tune sob teste
#   FB_FIXTURE  fixture lspci (obrigatório)
#   FB_SMI      nome que o mock do nvidia-smi reporta (opcional)
#   FB_REFUSE   1 → mock pacman recusa -S/-R (caminho pascal sem nvidia-dkms)
#   FB_PKGS     lista de pacotes "instalados" (1 por linha, opcional)
#   FB_LOG      arquivo de evidências a produzir (obrigatório)
#   NS_TMPFS    1 → montar tmpfs em /etc e /var (default; 0 no modo container)
#   MOCK_DIR    estado dos mocks (instalado/log/recusa)
#   MOCK_EXTRA  dir de mocks de cenário ($WORK/mocks-scoped) — vira frente
#               do PATH: ls/grep transparentes p/ os guards NV_PREBUILT/BBR
#               do v4.6, ligados por ELITE_SCOPED_NVLS / ELITE_SCOPED_BBR
#   FB_BBR      1 → pré-assa /etc/sysctl.d/99-elite-net.conf + modules-load.d/
#               elite-bbr.conf (como a ISO v1.1 entrega) p/ provar o guard BBR
#
# A evidência (FB_LOG) carrega: saída ANSI-stripada + RC + inventário de
# arquivos escritos + conteúdo dos arquivos-chave — TODAS as asserções rodam
# na fase (fora), lendo esse pacote: a lógica de teste mora com as peças.
set -u

# mocks de cenário na frente do PATH (ls/grep do v4.6 — transparentes sem toggle)
if [[ -n "${MOCK_EXTRA:-}" ]]; then
  export PATH="$MOCK_EXTRA:$PATH"
fi

if [[ "${NS_TMPFS:-1}" == 1 ]]; then
  mount -t tmpfs tmpfs /etc 2>/dev/null || true
  mount -t tmpfs tmpfs /var 2>/dev/null || true
fi

# O alvo do elite-tune é um sistema COM grub instalado: /etc/default/grub
# preexiste (o pacote grub o cria). No tmpfs ele não existe — sem isso o
# '>>' do token falharia em silêncio e o fixture mentiria sobre o produto.
if [[ ! -f /etc/default/grub ]]; then
  mkdir -p /etc/default
  printf 'GRUB_TIMEOUT=5\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' > /etc/default/grub
fi

# cenário BBR (v1.1): a ISO assa os DOIS arquivos de rede — o firstboot
# v4.6 confirma o bbr do kernel ou LIMPA (kernel sem bbr ≠ sysctl morto)
if [[ "${FB_BBR:-0}" == 1 ]]; then
  mkdir -p /etc/sysctl.d /etc/modules-load.d
  printf '# ── ELITE: rede — BBR + fq\nnet.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' \
    > /etc/sysctl.d/99-elite-net.conf
  printf '# ── ELITE: módulo BBR antes do systemd-sysctl\ntcp_bbr\n' \
    > /etc/modules-load.d/elite-bbr.conf
fi

# estado limpo por cenário (o container do CI compartilha /etc entre eles)
: > "$MOCK_DIR/installed.txt"
: > "$MOCK_DIR/pacman.log"
: > "$MOCK_DIR/systemctl.log"
: > "$MOCK_DIR/wall.log"
rm -f "$MOCK_DIR/refuse"
[[ "${FB_REFUSE:-}" == 1 ]] && touch "$MOCK_DIR/refuse"
read -ra _pkgs <<< "${FB_PKGS:-}"
for p in "${_pkgs[@]}"; do
  printf '%s\n' "$p" >> "$MOCK_DIR/installed.txt"
done

smi_env=()
if [[ -n "${FB_SMI:-}" ]]; then smi_env=("NVIDIA_SMI=$FB_SMI"); fi
out=$(env LSPCI_FIXTURE="$FB_FIXTURE" ${smi_env[@]+"${smi_env[@]}"} \
      bash "$TUNE" --firstboot --yes 2>&1); rc=$?

{
  printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g'
  echo "RC=$rc"
  echo "=== FILES ==="
  find /etc/modprobe.d /etc/systemd/system /etc/default /var/lib/elite \
       -type f 2>/dev/null | LC_ALL=C sort
  echo "=== MODPROBE-NV ===";  cat /etc/modprobe.d/00-elite-nvidia.conf 2>/dev/null || true
  echo "=== MODPROBE-AMD ==="; cat /etc/modprobe.d/00-elite-amdgpu.conf 2>/dev/null || true
  echo "=== GRUB ===";         cat /etc/default/grub 2>/dev/null || true
  echo "=== SCX-UNIT ===";     cat /etc/systemd/system/scx-elite.service 2>/dev/null || true
  echo "=== MARKER ==="; [[ -f /var/lib/elite/firstboot-done ]] && echo yes || echo no
  echo "=== ISAMD ===";  grep -q AuthenticAMD /proc/cpuinfo && echo yes || echo no
  echo "=== BBRCFG ==="; cat /etc/sysctl.d/99-elite-net.conf 2>/dev/null || echo MISSING
  echo "=== BBRMOD ==="; [[ -f /etc/modules-load.d/elite-bbr.conf ]] && echo yes || echo no
} > "$FB_LOG"
exit 0
