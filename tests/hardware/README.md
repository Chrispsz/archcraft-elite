# tests/hardware — o simulador dos 6 perfis de hardware (E106/5c)

A matriz de hardware da casa vira **contrato vivo**: cada perfil real
roda os scripts da casa (`elite-post-upgrade`, `elite-acpi-wakeup`,
`craft-display`) num **sandbox de root falso** e os arquivos resultantes
são comparados **byte a byte** contra o esperado do perfil.

```sh
bash tests/hardware/run.sh          # sai 0 = sem falhas · 1 = falhou · 3 = userns indisponível
```

## O sandbox (zero mudança de produção)

`unshare -rm` + bind mounts: `/etc` (cópia do real + seeds do perfil),
`/sys` (o hardware falso: `power/mem_sleep`, `class/hwmon`, `module/`),
`/home` vazio, `/run` e `/var/log` falsos — mais **stubs** de
`findmnt`/`systemctl`/`pacman`/`modprobe`/`snapper`/`grub-mkconfig`/
`lspci`/`flatpak`/`loginctl`/`mkinitcpio` no PATH (o `modprobe` que
"binda" cria hwmon novo; quem não tem o chip falha — o driver ocioso
desce). `elite-acpi-wakeup` e `craft-display` usam as **seams da casa**
(`ELITE_ACPI_WAKEUP`, `ELITE_RANDR`). O kernel do sandbox falso aplica o
toggle do `/proc/acpi/wakeup` (a escrita inverte o estado — a
idempotência da 2ª passada é provada byte a byte).

## A matriz (o mesmo conteúdo que `docs/ARCHITECTURE.md` documenta)

| # | Perfil | O que o sandbox prova |
|---|---|---|
| 1 | Entrada 1 · Intel iGPU + ext4 (s2idle) | GRUB **sem** `mem_sleep_default=deep` · snapper/grub-btrfsd **colhidos** · sensors.conf de fábrica intacto |
| 2 | Entrada 2 · AMD APU + btrfs | snapper-cleanup/grub-btrfsd **ligados** · `elite-sensors.conf` = `k10temp` |
| 3 | Intermediário 1 · **O RIG DO DONO** (Ryzen 5600 + ASUS nct6775 + RX 7600, btrfs, deep) | GRUB **com** deep (1×) · acpi-wakeup desarma os 6 gatilhos (idempotente) · sensors = `nct6775` · recover DP-1 `1920x1080@119.88` |
| 4 | Intermediário 2 · Intel + RTX + btrfs deep | deep no GRUB · snapper ligado · `config.toml` do dono ganha a chave DENTRO de `[settings]` |
| 5 | High-End 1 · Ryzen X3D + RX 7900 (btrfs, multi-monitor) | recover cobre DP-1 **e** HDMI-A-1 com seus modos persistidos · k10temp |
| 6 | High-End 2 · Intel + RTX 4080 (btrfs, multi-monitor) | recover cobre DP-1 **e** DP-2 · nct6775 |

Cada perfil roda a **dose 2×** (a idempotência é parte do contrato: a
2ª corrida é byte-idêntica e não reconstrói grub-mkconfig).

## A integração

`tests/phases/55-hardware.sh` converte o protocolo de saída (`OK\t` /
`FAIL\t`) em `t_ok`/`t_fail` da porteira (`tests/run-tests.sh` — entre a
fase 50-runtime-ipc e a 60-veredito). Sem `unshare` no ambiente: **pulo
honesto** (L6) — a matriz nunca mente GO sem provar.
