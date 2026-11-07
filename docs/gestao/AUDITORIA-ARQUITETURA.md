# AUDITORIA ARQUITETURAL — ELEVAR 10% O QUE JÁ FUNCIONA

> Sob demanda do dono (07/nov): *"Desconsidere o que já está resolvido e
> funcionando perfeitamente… analise sob a ótica de como podemos refinar
> e tornar 10% mais rápido, leve e robusto."* Diretriz respeitada: NADA
> aqui reescreve o que funciona — cada eixo separa **o que JÁ é lei da
> casa (com prova)** do que é **gargalo real** e do que é **proposta**.

---

## 0 · O CHÃO REAL (perícia antes de plano — a lei E33 do documento)

Fatos provados na árvore de `07/nov` (main `6302c44` + E75):

| Eixo do pedido | O que JÁ existe (prova) |
|---|---|
| Kernel otimizado | **linux-cachyos-bore** é o kernel da ISO e do rig (preset `etc/mkinitcpio.d/linux-cachyos-bore.preset`; `KPKG` no craft-update) — o "kernel CachyOS" do contexto do dono é REAL, não aspiração |
| Base | Archcraft/Arch — o labwc + waybar + fuzzel + swaync é a identidade da casa (autostart v1.0.3+; openbox/bspwm removidos) |
| Sync de customizações | `craft-update v5.5`: repo `[elite-local]` servido da release viva (`releases/latest/download`), dose ao ligar (elite-bootupdate, 3 min) + semanal (ConditionPathExists=!/run/archiso), sentinela E54, alvo condicional E56, delta reinicia toplevel→dock sem relogin, kernel pedagogy na própria porta |
| Integridade do canal | o pacman **verifica cada pacote contra o db** (checksum gravado pelo `repo-add` no CI) e o CI re-baixa + `sha256sum -c` (GATE 2) — a integridade não depende de fé |
| Rollback | snapshot btrfs PRE-transação: a falha grave tem "rollback: snapshot #N no GRUB" (craft-update) + `craft-rollback` para o dia a dia |
| Provisionamento dinâmico | `elite-optimize` (matemática por MemTotal: ≤4 GB zram×2/swappiness 150 · 8 GB 60 · 16 GB+ 15 — E74), `elite-drivers` (perfis AMD/Intel/NVIDIA por lspci, purga auditável — E74), `elite-ferramentas` (paru/octopi/AppImageLauncher — E74), modprobe.d powersave (E38), udev wake-guard (E24), zram-generator + sysctl da casa |
| Painéis/OSD | menu bar waybar no topo + **dock própria em C** (craft-dock-gui + daemon craft-toplevel — o componente mais leve da casa), swaync, swayosd com fallbacks (E74), fuzzel |
| NVIDIA suspend | `elite-install-stage` já entrega `nvidia-suspend/resume/hibernate.services` + `NVreg_PreserveVideoMemoryAllocations=1` (E63, contrato 20-static:341) |

**Conclusão do chão:** os 4 eixos do pedido já têm base estrutural.
O trabalho de elevação é cirúrgico — os gaps abaixo são os ÚNICOS
gargalos provados; tudo mais seria achismo ou reescrita.

---

## 1 · EIXO A — PIPELINE DE ATUALIZAÇÃO (GitHub & custom layers)

### A1 [FEITO NO E75] Hook pós-transação — a casa acorda no `-Syu` cru
- **Gargalo provado:** a pedagogia de reboot do kernel só existia na
  porta do craft-update. Um `pacman -Syu` manual trocava o kernel em
  silêncio (o rolling da base não avisa nada) — o dono podia rodar
  semanas num kernel antigo sem saber.
- **Cura:** `elite-post-transaction.hook` (libalpm, PostTransaction,
  Target=\*) → `elite-post-transaction`: detecta troca do
  linux-cachyos-bore (carimbo `/var/lib/elite/kernel-seen` — 1ª execução
  é linha de base, nunca falso "REINICIE"), avisa na cara de quem rodou
  o pacman, loga e observa o wake-guard E24 no papel
  (`/var/log/elite-post-transaction.log`). Zero rede, zero lock —
  inofensivo na transação do próprio craft-update.

### A2 [PROPOSTO — próximo degrau] Health-probe pós-delta
- Após o restart toplevel→dock do delta, prober por ≤10 s se os processos
  estão vivos; se não, **toast honesto + linha no log** apontando o
  `craft-dump`. SEM auto-rollback de código: o rollback da casa é o
  snapshot do GRUB (A4) — auto-reverter pacotes por script é prometer o
  que não se pode provar (a mesma escola da E33).

### A3 [PROPOSTO — próximo degrau] Paridade do selo no `--canal`
- O db do `[elite-local]` já carrega checksums; a defesa extra seria o
  craft-update comparar o `sha256sums-pacotes.txt` da release contra o
  db recebido (detectaria upload parcial/CDB agressivo). Prioridade
  BAIXA: o GATE 2 do CI já re-baixa e confere a cada publicação.

### A4 [DECISÃO CONSCIENTE — manter] Rollback = snapshot GRUB
- O pacman é transacional (tudo-ou-nada POR pacote); a falha multi-pacote
  é re-executável; a falha GRAVA tem snapshot PRE + GRUB. Rollback
  automático dentro do craft-update adicionaria um segundo mecanismo de
  reversão — risco maior que o ganho.

---

## 2 · EIXO B — REPOS HÍBRIDOS (Arch + CachyOS + Archcraft)

### B1 [FEITO/EM VIGOR] Ordem e escopo de prioridade
- A ISO herda o pacman.conf do archiso (core/extra/multilib do Arch +
  repositório cachyos via keyring/mirrorlist da casa) e o `[elite-local]`
  entra como canal próprio. A regra que previne guerra de repos:
  **o `[elite-local]` só navega código da casa** (craft-*/elite-*, a ponte
  craft-toplevel e os pins de vendor como brave-origin) — ele NUNCA
  sobrescreve base. O `/etc` da Elite vence `/usr/lib` de qualquer vendor
  (sysctl 99-elite, zram-generator.conf, 00-elite-timeout — todos
  documentados na própria árvore).
- Os pacotes otimizados do CachyOS que a casa consome conscientemente:
  `linux-cachyos-bore`, `cachyos-settings` (base de sysctl/zram que o
  /etc da casa vence), `cachyos-keyring`, `cachyos-v3-mirrorlist`.

### B2 [PROPOSTO — guarda de futuro] Observabilidade do conflito
- Risco real documentado: repos atualizando em tempos diferentes podem
  entregar dependência de Wayland/labwc em versões desencontradas. A
  rede de segurança JÁ é a suíte + o gate de release; o degrau proposto
  é barato: no `craft-dump`, listar as versões de labwc/wlroots/foot/
  waybar/hyprlock lado a lado (hoje só aparecem se um erro as nomeia) —
  o dump passa a nomear o par suspeito ANTES do dono colher sintoma.

---

## 3 · EIXO C — EXPERIÊNCIA VISUAL & PAINEL (limite da arquitetura)

### C1 [EM VIGOR] A arquitetura de superfície
- waybar (menu bar) + craft-dock-gui (C nativo, memória na casa dos MB)
  + swaync + swayosd (E74) + fuzzel. O OSD responde ao knob e às teclas
  multimídia com fallback pactl/brightnessctl — a barra some, a função
  nunca (lei E74).

### C2 [PROPOSTO — degrau de polimento] Dieta do waybar
- O maior consumidor visual em memória é o waybar (dezenas de MB — a
  dock C é ~10×). O ganho honesto não é trocar de barra (identidade da
  casa), é **auditar os módulos ativos** no `config.top` e desligar o
  que o dono não usa (cada módulo é poll + render). Degrau de POLIMENTO
  com medição antes/depois (`ps -o rss=`), nunca a olho.

---

## 4 · EIXO D — DETECÇÃO DINÂMICA NO BOOT/INSTALAÇÃO

### D1 [EM VIGOR] O que já decide por hardware
- RAM → zram/swappiness (`elite-optimize`, E74); GPU → perfil de drivers
  (`elite-drivers`, E74); despertar USB → desarmado por classe
  (udev E24); powersave de áudio/Wi-Fi por módulo (modprobe.d E38).

### D2 [PROPOSTO — metade da F5 da spec do dono ainda de pé]
- **Storage:** `elite-optimize` cresce a perna de deteção de armazenamento —
  rotacional (`/sys/block/*/queue/rotational`) → bfq; NVMe/SSD →
  mq-deadline/none; montagem da casa com `noatime` e, em SSD, o
  `discard=async` via regra udev (nunca editando fstab alheio — a lei do
  domínio). Está no papel como PRÓXIMO degrau, não no E75: o E75 é a
  cura do relato de campo, e misturar cura com feature atrasa o rig.

### D3 [NÃO-FAZER — anti-achismo]
- **Nenhum parâmetro de kernel de GPU (amdgpu/i915) sem dump que nomeie o
  driver.** O prompt do dono lista `amdgpu.dc=1`/`i915.enable_psr=0` como
  *possibilidades por classe* — a casa só aplica quando o craft-dump
  (seção 10, agora com a tríade status/enabled/dpms dos conectores e o
  journal do hook de resume) apontar o réu. Prescrever remédio de ficha
  é a classe de bug E33 que a casa existe para matar.
- **Nenhuma migração de compositor/barra/locker.** labwc + waybar +
  craft-dock + hyprlock é a identidade da casa e o banco de provas de
  75 versões.

---

## 5 · O RESUMO EXECUTIVO (a resposta curta do dono)

| Item | Eixo | Status |
|---|---|---|
| Hook pacman pós-transação (kernel novo avisado em QUALQUER -Syu) | A | **FEITO (E75)** |
| Ciclo off→on da imagem no resume (o relato de campo) | — | **FEITO (E75)** |
| Escotilha `craft-rescue-screen` sem reboot | — | **FEITO (E75)** |
| Diário do hook + tríade DRM dos conectores no craft-dump | — | **FEITO (E75)** |
| Health-probe pós-delta do craft-update | A | Proposto |
| Paridade do selo no --canal | A | Proposto (baixa prioridade — GATE 2 cobre) |
| Versões de Wayland/labwc lado a lado no craft-dump | B | Proposto (barato) |
| Dieta dos módulos do waybar (medição antes/depois) | C | Proposto (polimento) |
| Storage dinâmico (bfq/mq-deadline, noatime, discard=async) | D | Proposto (F5 remanescente) |
| Params de GPU sem dump nomeando o réu | D | **NÃO-FAZER** (E33) |
| Troca de compositor/barra/locker | — | **NÃO-FAZER** (identidade + banco de provas) |
