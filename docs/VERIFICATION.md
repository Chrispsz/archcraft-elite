# VERIFICATION — o que cada gate PROVA (e o que não prova)

Princípio do projeto: **nenhum resultado é "verde" por cortesia**. Este
documento é o contrato de honestidade do pipeline — cada gate lista o que
prova, a evidência que deixa no log e os limites que NÃO cobre.

## lint (build.yml)

**Prova:** todos os scripts shell passam em `shellcheck -S warning`
(1.0-103 — sem pulo nenhum: a erradicação do python acabou com a era dos
shebangs de fora da casa; a cobertura é INTEIRA).

## Suíte de contratos (tests.yml)

**Prova:** ~1.900+ asserções em 6 fases (o placar exato é impresso a CADA run — número fixo envelhece; cresce a cada versão — cada cura do dono vira contrato que impede a regressão) — sintaxe, YAML, units, overlay REAL contra fixture hermética, ciclo split→hash→reassemble, determinismo bit-a-bit, contratos de UI (a barra/dock configurada é a que o dono aprovou).

**Não prova:** o boot real da ISO; hardware real.

## FASE 2 — Os três pilares novos da porteira (tests/phases/35/40/50)

**35-ajuda · Contrato do craft-help (o mapa é promessa):** extrai TODOS os comandos/atalhos de `craft_tools::mapa_comandos` (a fonte única, sem lista dupla) e cobra: (1) existência real no universo que a casa entrega (airootfs ∪ bins compilados do molde ∪ packages.add ∪ aliases de split package ∪ allowlist base); (2) modo 0755 no git index OU o enforcement `chmod 755` no empacotamento do build.sh (defesa em profundidade — o rig recebe o bit MESMO que um push externo derrube o modo); (3) `sh -n`/`bash -n` pelo shebang; (4) verbo seguro EXECUTIVO (`--help`/`-h`/`uso`/`status` sai 0 em HOME sandbox — o réu histórico era o elite-update que respondia um pkexec; curado com guard antes da escalada); os atalhos (W-d, W-a, W-S-b…) são cobrados contra os keybinds VIVOS do rc.xml. Os bins compilados são cobrados no fonte (arm de ajuda) e executivamente no smoke do Canal.

**40-compositor · Integridade do compositor:** XML estrito de menu.xml + rc.xml (parser real), menu SEM texto órfão fora de tag (E146), nenhum item com atributo de ícone (regra v2.2) e — o contrato executivo — TODO `<action name="Execute" command="X">` resolve o binário principal (wrappers `sh -c`, cadeias `for b in`, `foot -e`, `${TERMINAL:-foot}` entendidos) no mesmo universo da fase 35; fósseis de era (craft-drawer/craft-bars/craft-connect/craft-menu…) BANIDOS de Execute. O labwc nunca mais herda menu com fantasma (a era do menu de 3 itens morre por contrato, não por sorte).

**50-runtime-ipc · Saúde de runtime e IPC (estática):** sweep 0755 de 100% dos bins/scripts da casa (index OU enforcement); sintaxe de 100% dos bins shell; EXATAMENTE UM lançador `elite-daemon session` no autostart-template dentro do bloco marcado E146; bus.sock como fonte única (elite-core ∪ barra ∪ dock); instância única no fonte (flock + recusa com papel); ZERO glifo Nerd `\u{f0xx}` em código vivo; ciclo de vida dos popovers da dock fechado (popdown+unparent+queue_resize — o "still has children" e o bloco preto órfão nunca mais); craft-game/craft-idle respondem `status` (executivo, HOME sandbox).

## ci-runtime-smoke — a sessão booted sobre o PACOTE (Canal)

**Prova:** o pilare 3 executivo. `tests/ci-runtime-smoke.sh` roda NO container do Canal, APÓS o makepkg e ANTES do repo-add/upload: extrai o elite-system recém-parido, sobe um **labwc headless** (WLR_BACKENDS=headless, render pixman + GSK cairo — sem DRM/GPU) e cobra: bus.sock VIVO; 2ª instância sai 0 COM papel (flock E30); barra + dock de pé e continuando de pé; logs SEM `Gtk-WARNING`, SEM "still has children", SEM `\uXXXX` mojibake; craft-game/craft-idle `status` sai 0; `--help` dos 8 compilados (E90 executiva). Contrato quebrado = run vermelha = **nada sobe para o rig** (o db só recebe pacote que provou sessão).

**Honestidade:** compositor que não sobe NO CONTAINER = SKIP nomeado no log (juízo de ambiente; o juízo de compilação já foi pago pelo makepkg e o static continua valendo) — nunca um verde de cortesia.

**Não prova:** interação real de mouse; hardware do dono (o session_smoke no rig cobre).

## build (build.yml + .ci/build.sh + log-forensics)## build (build.yml + .ci/build.sh + log-forensics)

**Prova:** a ISO foi construída e o log foi varrido por padrões fatais
conhecidos (`log-forensics.sh` — erro silencioso = run vermelha). O
`sha256sums.txt` selado dentro do artifact é a identidade dos bits.

**Não prova:** que a ISO boota. (É o que os dois gates seguintes fazem.)

## verify — boot do LIVE (QEMU serial)

**Prova, com a cmdline REAL da entrada default da ISO** (lição #43: o gate
não inventa cmdline):

1. `Startup finished` — systemd completou o boot.
2. Sem shell de emergência do initramfs.
3. Sem `code=203/EXEC` — binários executáveis no squashfs.
4. A cmdline real tem `systemd.default_timeout_start_sec=90` (regressão do
   fix [6.2] é reprovação automática).
5. **Zero unidades systemd em failed** (`Failed with result` — a classe do
   `fg-booster` crash-loopado em silêncio v1.0→v1.5).
6. **Sessão gráfica viva**: o `elite-session-probe.service` imprime no
   serial e o gate cobra TODOS os tokens (v2.10.5 — o doc dizia só
   WAYBAR_COUNT/BARS_EXITS e mentia por omissão):
   `WAYBAR_COUNT` (≥1) · `DOCK_COUNT` (≥1) · `TOPLEVEL_COUNT` (≥1, o
   daemon das janelas vivo) · `TOPLEVEL_SOCKET=OK` (PING real no socket)
   · `BARS_EXITS=0` (nenhuma morte) · fuzzel binário + INI parseável.
   **v2.1: com KVM disponível no runner, o probe é OBRIGATÓRIO** — sem
   ele a run é vermelha (fim da classe "verde sem nunca ter visto a
   sessão gráfica"). **v2.10.5: o QEMU do verify usa KVM quando o runner
   tem** — a cobrança e a máquina agora falam a mesma moeda.

**Não prova:** máquina física do usuário (GPU real, firmware, periféricos);
comportamento pós-kill do QEMU (janela de ~15 s pós-probe).

## verify-install — a instalação REAL (QEMU)

**Prova:** a cadeia Calamares é reproduzida de verdade contra um disco
(btrfs): unpackfs, hash do kernel copiado (comparação byte-a-byte),
mkinitcpio, grub-install — e **o disco instalado boota no QEMU** com
veredito de 5 classes. É o gate que caça o bug do rig B
(`premature end of file` no GRUB).

**v2.1:** a checagem `sha256sum -c` do artifact é GATE DURO (o `|| true`
antigo engolia ISO truncada — classe v1.8.0).

**Não prova:** todo modelo de GPU/disco; instalação em partição não-btrfs
(o default do instalador é btrfs).

## release — GATE 1 + GATE 2

**GATE 1 (pré-upload):** o artifact baixado do job build bate com o
`sha256sums.txt` selado dentro dele — corrupção de download = run vermelha
antes de publicar qualquer coisa.

**GATE 2 (pós-upload):** re-download dos assets JÁ PUBLICADOS e nova
conferência — o blob do GitHub é a única verdade. Divergiu = run vermelha
(e o release nasce verificado ou não nasce). **v2.1: o GATE 2 também existe
no caminho manual (`publish-artifact.yml`)** — a classe "release truncada"
está fechada nos dois caminhos.

**Não prova:** o pendrive do usuário; mas dá a prova matemática de que o
que está publicado é exatamente o que o build produziu.

## Os dois canais (Fase 2) — Teste/Beta vs. Estável/ISO

**Canal Teste/Beta — `publish-packages.yml` (Canal diário [elite-local]):** push no `main` (com conteúdo de casa) → guard E41 → **guarda do modo 0755** (o bit viaja no git; push externo que o derrube é recolocado e commitado de volta) → makepkg PACKAGES_ONLY → **smoke de runtime sobre o pacote** (o portão novo) → repo-add contra o db da release viva → upload. É o caminho RÁPIDO e FREQUENTE: o rig do dono recebe por `craft-update`/`pacman -Syu` minutos depois do push. Só entra no db o pacote que PROVOU sessão.

**Canal Estável/Produção → ISO — `build.yml` (tag v\*):** a ISO é o retrato promovido e NUNCA nasce de código não-auditado: `release` tem `needs: [build, verify, verify-install, suite]` — a MESMA suíte de contratos (que agora inclui os três pilares da Fase 2) é GATE da release, na MESMA commit da tag. O que o dono queima é o código que passou por: suíte verde + forense do log + boot do LIVE (QEMU) + instalação REAL (QEMU) + GATE 1/2 de sha256.

**Velocidade (o diagnóstico da Fase 2):** a suíte e o Canal carregavam DOIS caches de cargo gêmeos (`cargo-target-*` vs `canal-cargo-target-*`) que nunca se falavam — as deps pagavam compile DUAS vezes por push. Chave UNIFICADA agora (mesma `cargo-target-<hash do Cargo.lock>` + restore-key comum nas três esteiras: suíte, Canal e ISO — a ISO recompilava o workspace inteiro a cada tag). Os `.db` do pacman continuam NUNCA cacheados (mirror skew, lição #17).

## O que NINGUÉM deve fazer (contrato institucional)

- Não declarar correção "pronta" sem o gate correspondente fechado em verde.
- Não transformar checagem em informativo para ficar verde (a única exceção
  documentada é o probe sem KVM — e ela exige que o log declare a condição).
- Erro benigno é benigno **POR ESCRITO** (comentário no gate que o tolera),
  nunca por omissão.
- Changelog e CI verde não substituem o teste real: a ISO só "existe" quando
  verify + verify-install fecham verdes NA MESMA run que a produziu.
