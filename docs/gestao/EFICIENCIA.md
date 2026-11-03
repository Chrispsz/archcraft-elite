# EFICIÊNCIA — a auditoria de recursos (E38, 2026-11-02)

> Pergunta do dono: **"hoje nosso sistema é o máximo eficiente possível em
> recursos? Tudo é pensado para consumir só quando necessário? As
> atualizações da UI/UX, todo o funcionamento?"**
>
> Resposta honesta ANTES desta rodada: **não** — a casa era boa (áudio,
> clipboard, idle e compositor já event-driven; zero daemon redundante),
> mas havia **três mecanismos de polling sobre a mesma verdade**, tuning de
> kernel pela metade e knobs de energia ausentes. Esta auditoria mediu,
> curou o de baixo risco e deixou o resto plano-contratado.

## Método
5 auditores paralelos leram o código NA ÍNTEGRA (dock+daemon, supervisores,
sistema/units/pacotes, waybar/forks/CI, UI/UX/qualidade), cada achado com
evidência `arquivo:linha` — e cada réu foi RE-VERIFICADO pela manutenção
antes de agir (lição E36). Bench do loop quente feito com o código verbatim
no sandbox. Curas de baixo risco saíram NA MESMA rodada, com contrato novo
para cada uma (a porteira aprova o estado, não a intenção).

## O mapa do custo contínuo da sessão (o que acordava o CPU)

| Mecanismo | Antes | Custo medido/estimado | Depois (E38) |
|---|---|---|---|
| Dock tick 1s (poll do socket + /proc scan) | `GLib.timeout_add(1000)` :377 | ~2 wakeups/s ≈ **172.800/dia** + 1.200–2.000 syscalls/s + varredura do índice 60×/min | **PUSH EVT** (evento) + tick 5s de segurança; memoização mata o loop quente |
| craft-bars loop 5s | 8× pgrep + wc + sleep | ~120 forks/min ≈ 172.800/dia | cap_log a cada 6 ciclos (−14.400 forks/dia); systemd --user no PLANO |
| craft-bgapps status (waybar) | interval 10s, `tr\|grep` por processo | ~8–11k forks/h ocioso; 30–45k/h com Brave | interval 30 (−67%); reescrita awk NO PLANO (proteção de shell exige rodada própria) |
| craft-menu abertura | 5 `grep -q` por abertura | 5 forks + latência por menu | **substring POSIX, zero fork** |
| craft-keyring-wait | 2 pgrep/5s em transação | até ~168 forks/boot | **1 pgrep ERE** |
| Áudio HDA / Wi-Fi Intel | NENHUM powersave | ~0,5–2W idle em notebook | **modprobe.d 99-elite-powersave.conf** |
| Watchdog/zswap no LIVE | só no INSTALADO (GRUB) | mW de IRQ + dupla compressão | **tokens nas 4 entradas do live** |
| zram | sem `page-cluster/watermark*` | swap-in de 8 páginas, stalls de reclaimer | **trio SteamOS/Fedora completo** (overlay + espelho elite-tune) |

## O que JÁ estava certo (verificado, não presumido)
- **Compositor**: labwc sem blur/anim por frame; sombras 60/40 mitiga­das
  (`dropShadowsOnTiled no`); CSS estático (transição só em hover).
  Hyprlock: blur é surto ÚNICO por lock (cacheia o framebuffer).
- **Daemons da sessão**: ~200–280 MB somados, TODOS event-driven ou
  justificados (pactl subscribe, udiskie/dbus, wl-paste --watch,
  swayidle/wlopm, cliphist com poda). Nenhum redundante — a RAM cortável
  sem perda de função é ~1-2 MB de subshells do supervisor.
- **mpris interval 1**: decisão registrada do dono (segundos ao vivo, zero
  fork — 20-static:1046 crava o `"interval": 1` de propósito). NÃO migrado.
- **craft-connect**: loops só vivem dentro do diálogo (0% da sessão fora dele).
- **CI**: cache pacman (`pacman -Sw` preflight) + [elite-local] já
  persistentes — "re-download em toda build" é falso. Buraco real: chave
  de cache MISTA invalida ~2 GB a qualquer edit no build.sh (PLANO).

## Curas aplicadas nesta rodada (todas com contrato)
1. **PUSH EVT** (a cura-carro-chefe): daemon C aceita `EVT ON` (opt-in,
   clientes velhos intocados), empurra `EVT` por batch pós-dispatch
   (`evt_dirty` + `notify_evt`); dock abre 2ª conexão dedicada
   (`_tl_evt_open`/`_tl_evt`/`_tl_evt_close` + `io_add_watch`) e o tick
   1s→5s fica rede de segurança. Fallback lei v2.10.3 inteiro. sha256 do
   C re-pinado no PKGBUILD (contrato recalcula).
2. **Memoização** `_resolve_desktop` (positiva+nega­tiva, sentinel
   `_RCACHE_MISS`, invalidação quando o set de comms muda).
3. **Trio zram** em `99-elite.conf` + espelho `write_elite_sysctl`.
4. **Powersave** `snd_hda_intel power_save=1` + `iwlwifi power_save=1`.
5. **nowatchdog + zswap.enabled=0** nas entradas do live (AMD/NVIDIA,
   UEFI/syslinux/grub; rescue fica vanilla).
6. **craft-menu** sem fork na abertura (5 greps → `${CAPS#*X}`).
7. **keyring-wait** 1 pgrep ERE; **craft-bars** cap_log a cada 6 ciclos;
   **bgapps** interval 10→30.
8. **E33 ×3 + código morto ×2 + doc**: craft-bgapps ('física do compositor'
   mentia — a lei é pid), craft-logout ('por foco' mentia), fuzzel.ini
   (launcher ≠ menus), F_MINIMIZED e MENU órfãos removidos,
   SCRIPTS.md truthful (zero fork, tick 5s + push).

## O PLANO (o que NÃO foi feito de fábrica — e por quê)
| # | Item | Ganho | Por que não veio agora |
|---|---|---|---|
| 1 | craft-bars → systemd --user units (`Restart=always, RestartSec=5`) | −~150k forks/dia restantes, zero polling | toca a garantia ≤5s e ~15 contratos de supervisão — rodada própria com o gate do QEMU por perto |
| 2 | bgapps `status` → 1 awk sobre /proc | −95% dos forks restantes da barra | a casca de proteção de shells é bash `case` — reescrever sem poder testar em hardware real = risco de matar shell do dono |
| 3 | journald live volatile / SystemMaxUse↓ | até ~36-100 MB de teto em RAM | Storage=persistent serve o INSTALADO (mesmo arquivo herdado); exige solução por-ambiente |
| 4 | sshd fora do live | ~10-20 MB + fecha porta | toca "sshd sobrevivente" do verify-install — inverter contrato com teste |
| 5 | probe 60s → .timer | systemd-analyze honesto (−60s de target) | o gate do CI grepa o marcador — mudar o quando exige rodada de CI |
| 6 | systemd-resolved fora (NM dns interno) | ~5-15 MB + extingue a classe do freeze | validar em runtime antes (foi réu de freeze-loop) |
| 7 | entrada live SEM copytoram | ~1,5-2 GB de RAM em máquinas ≤8 GB | decisão de produto do dono (velocidade vs RAM) |
| 8 | ASPM/EPP por fonte | 1-3W em notebook | risco real em firmware ruim — só opt-in |
| 9 | CI: dividir chave de cache (pacman × build.sh) | fim do churn de ~2 GB | só workflow, sem urgência |
| 10 | espelhos restantes (GPU heredocs no elite-tune, gramática de saída em 6 menus, mlog×7, dock.css↔DEFAULT_CSS) | manutenibilidade | continuação do plano de 16 do ARQUITETURA.md (itens 4.1-4.3/4.8-4.9) |

## Veredicto
- **Por frame (GPU)**: a UI/UX já era estática barata — nada a curar.
- **Por segundo (CPU/wakeups)**: agora é event-driven de verdade — o
  'atualizar na hora' que o dono exige vem de EVENTO (latência ~0, melhor
  que o tick de 1s), e o que sobra de polling é rede de segurança declarada.
- **RAM**: sem daemon estofado; os cortes reais exigem decisão de produto
  (itens 3/4/7 do plano).
- **Consumir só quando necessário**: áudio, Wi-Fi, watchdog e zswap agora
  dormem/acordam por necessidade; a dock acorda por evento; o supervisor
  é o último poller de grande porte — e o plano o converte em SIGCHLD do
  systemd quando o dono autorizar a rodada.
