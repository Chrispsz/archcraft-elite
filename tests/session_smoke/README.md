# tests/session_smoke — Nível 2 da suíte real (Fase 2 da reconstrução)

O contrato da SESSÃO VIVA: roda no rig do dono (ou numa sessão labwc de
testes) e julga o sistema ACORDADO, não mocks.

## O que contrata (o mapa do fumo)

1. **Zero legado:** nenhum processo `waybar`, `craft-audio`, `craft-bars`,
   `craft-connect`, `craft-pin-pick`, `craft-dock-gui` vivo (`/proc/*/comm`).
2. **Família nativa de pé e CONECTADA:** `elite-daemon` (session + game),
   `craft-bar-rs`, `craft-dock-rs` vivos; o `bus.sock`
   (`/run/user/$UID/elite/bus.sock`) existe e responde ao `Hello`
   (nível 2 exige o fio, não só o arquivo).
3. **Serviços críticos:** `NetworkManager`, `bluetooth`, `coolercontrold`,
   `scx_loader` — `systemctl is-active`.
4. **Áudio:** o sink padrão é a analógica (`Starship/Matisse` família) ou
   uma escolha EXPLÍCITA do dono; volume > 0 (o piso 40% do roteador).
5. **Boot:** `mitigations=off`, `nowatchdog`, `amdgpu.ppfeaturemask=0xffffffff`,
   `ntsync` no `/proc/cmdline`; swappiness VIVO = 180 (`/proc/sys/vm/swappiness`);
   `zram0` ativo.
6. **Pele única:** os providers CSS da barra e da dock aceitam a folha
   mestra (sem erro de parse no journal da sessão).

## Implementação (Fase 2)

O runner é o `craft-dump-rs` v2 (nível 3 da telemetria) + um script bash
fino que executa o binário e faz os asserts acima sobre o papel. A peça
entra quando a coleta v2 completa (bus.sock + journal
`PrepareForSleep`) estiver escrita — o esqueleto NUNCA finge GO.

## Uso planejado

```sh
bash tests/session_smoke/run.sh        # no rig do dono ou sessão de teste
```
