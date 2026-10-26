# VERIFICATION — o que cada gate PROVA (e o que não prova)

Princípio do projeto: **nenhum resultado é "verde" por cortesia**. Este
documento é o contrato de honestidade do pipeline — cada gate lista o que
prova, a evidência que deixa no log e os limites que NÃO cobre.

## lint (build.yml)

**Prova:** todos os scripts shell passam em `shellcheck -S warning`. Scripts
Python (shebang python) são pulados explicitamente (v2.0.1 — o craft-dock-gui
é PyGObject).

**Não prova:** comportamento em runtime; scripts Python inteiros.

## Suíte de contratos (tests.yml)

**Prova:** ~1.497 asserções em 5 fases (o número cresce a cada versão —
cada cura do dono vira contrato que impede a regressão) — sintaxe, YAML,
units, overlay REAL
contra fixture hermética, ciclo split→hash→reassemble, determinismo
bit-a-bit, contratos de UI (a barra/dock configurada é a que o dono aprovou).

**Não prova:** o boot real da ISO; hardware real.

## build (build.yml + .ci/build.sh + log-forensics)

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
6. **Sessão gráfica viva**: o `elite-session-probe.service` imprime
   `WAYBAR_COUNT` e `BARS_EXITS` no serial — as 2 barras waybar têm que
   estar vivas e sem nenhuma morte. **v2.1: com KVM disponível no runner,
   o probe é OBRIGATÓRIO** — sem ele a run é vermelha (fim da classe
   "verde sem nunca ter visto a sessão gráfica").

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

## O que NINGUÉM deve fazer (contrato institucional)

- Não declarar correção "pronta" sem o gate correspondente fechado em verde.
- Não transformar checagem em informativo para ficar verde (a única exceção
  documentada é o probe sem KVM — e ela exige que o log declare a condição).
- Erro benigno é benigno **POR ESCRITO** (comentário no gate que o tolera),
  nunca por omissão.
- Changelog e CI verde não substituem o teste real: a ISO só "existe" quando
  verify + verify-install fecham verdes NA MESMA run que a produziu.
