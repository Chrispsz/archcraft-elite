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
#
# A evidência (FB_LOG) carrega: saída ANSI-stripada + RC + inventário de
# arquivos escritos + conteúdo dos arquivos-chave — TODAS as asserções rodam
# na fase (fora), lendo esse pacote: a lógica de teste mora com as peças.
set -u

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
} > "$FB_LOG"
exit 0
