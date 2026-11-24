# tests/iso-qemu — Nível 3 da suíte real (Fase 2 da reconstrução)

A ISO booted no QEMU: o produto final validado como o dono o recebe.

## O que contrata

1. **Boot limpo até a sessão gráfica** `labwc` (QEMU/KVM + VirtIO GPU,
   sem display interativo — a sessão sobe no console gráfico virtual).
2. **A família nativa sobe pela primeira vez:** `elite-daemon session`
   ergue `craft-bar-rs` + `craft-dock-rs` no frame 0 (sem craft-bars,
   sem waybar — o autostart 2.0 é a porta).
3. **Extração automática:** o `craft-dump` v2 (e o `journalctl` do boot)
   saem da VM por `qemu-guest-agent`/ssh para a auditoria pós-build —
   o papel de dentro da VM é a prova.

## Implementação (Fase 2)

Script `tests/iso-qemu/run.sh` que: (1) localiza a ISO mais recente do
artefato do build mensal; (2) boota com `-nographic` + expect do login
autológico; (3) roda o `craft-dump` v2 dentro da VM; (4) compara o papel
contra os contratos do nível 2 (session_smoke). A peça entra COM a Fase 2
da reconstrução — o esqueleto não finge GO de ISO que não bootou.
