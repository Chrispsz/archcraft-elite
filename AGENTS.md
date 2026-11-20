# CONSTITUIÇÃO OPERACIONAL PERMANENTE — archcraft-elite

> **ESTE ARQUIVO É A LEI SUPREMA DO PROJETO.** Toda sessão futura — mesmo
> após reset de sandbox, clone novo ou máquina nova — DEVE ler este arquivo
> ANTES de qualquer operação e cumpri-lo automaticamente. Nenhum documento
> da casa (incluindo `docs/gestao/PROTOCOL.md`) revoga, rebaixa ou dispensa
> estas leis; em conflito percebido, **este arquivo prevalece** e a
> divergência deve ser registrada e harmonizada no mesmo commit.
>
> **Regra de segredos (válida para todas as seções abaixo):** NUNCA escrever
> o valor bruto de nenhum token/credencial dentro deste arquivo ou de
> QUALQUER arquivo rastreado pelo Git — o GitHub Secret Scanning revoga
> tokens expostos em commits e quebra a automação da casa. Os tokens vivem
> SOMENTE nos caminhos persistidos fora do Git, documentados aqui por
> caminho (§1).

---

## §1 · Bootstrap Limpo & Autenticação Persistente

### 1.1 Escada de token sem pedir ao usuário

Sempre buscar a credencial do GitHub nesta ordem ANTES de qualquer
operação remota (fetch, push, API, clone):

1. `/home/z/my-project/.elite-gh-token` — A FONTE PERSISTENTE (1ª via,
   ordem do dono 2026-11-21): o sandbox recicla `/home/z/` mas
   `/home/z/my-project/` sobrevive — este arquivo é a cópia que
   renasce. Se `~/.elite-gh-token` ou `~/.git-credentials` estiverem
   AUSENTES (reciclo detectado), o agente os (re)cria AQUI
   automaticamente antes de qualquer operação: `cp` para
   `~/.elite-gh-token` (`chmod 600`) e grava
   `https://USUARIO:TOKEN@github.com` em `~/.git-credentials`
   (`chmod 600`, com `git config --global credential.helper store`),
   sem nunca imprimir o valor;
2. `~/.elite-gh-token` (arquivo com `chmod 600` — cópia sobrevivente fora
   do repo);
3. `~/.git-credentials` (formato `https://USUARIO:TOKEN@github.com`,
   `chmod 600`, alimentado por `git config --global credential.helper
   store`);
4. Variáveis de ambiente (`GH_TOKEN` / `GITHUB_TOKEN`) ou `gh auth token`.

Se NENHUMA via funcionar: relatório honesto de bloqueio ao dono — nunca
inventar resultado, nunca pedir credencial em texto exposto (L6/L3 da casa
continuam valendo: toda chamada de API autenticada, honestidade absoluta).

### 1.2 Repositório íntegro

- **Corrupção de `.git`** (fetch morrendo em `Failed to checksum
  …/tmp_pack_*`, index-pack abortado) ou **`mv` cross-filesystem
  interrompido** (árvore parcial + `index.lock` órfão): remover o
  diretório quebrado e executar `git clone` LIMPO **diretamente no destino
  final** usando o token persistido — nunca `mv` de repo git entre
  filesystems em tarefa cron (lição provada em 2026-11-20: a árvore parcial
  diverge 138 arquivos do índice e o `reset --hard` cego a agrava).
- **Nunca rodar `git reset --hard` cego:** inspecionar `git status` e
  `git diff` ANTES. Herdeiro encontrado na árvore é julgado, provado e
  commitado (ou descartado com voz) — nunca apagado sem perícia
  (jurisprudência da auditoria 2026-11-20).
- Remote do repo permanece limpo (`https://github.com/Chrispsz/archcraft-elite.git`,
  sem token embutido na URL) — a credencial vem da escada 1.1.

---

## §2 · Execução Incremental Anti-Timeout (Zero Perda de Progresso)

- **Proibido acumular trabalho grande sem push:** o ambiente de execução
  tem limite de tempo e pode resetar em raciocínio silencioso longo ou com
  muitos arquivos acumulados. Trabalho sem push é trabalho que pode
  desaparecer.
- **Ciclo atômico obrigatório:** qualquer demanda com mais de 2
  blocos/arquivos é dividida em etapas pequenas e independentes. Ao
  concluir **cada etapa**:
  1. validação rápida da etapa (`bash -n` / `shellcheck` / `py_compile` /
     teste unitário da peça);
  2. `git add` → `git commit` → `git push origin main` imediatamente (a
     regra do dono 2026-11-21: commit + push ao final de CADA etapa —
     sempre com a suíte porteira GO quando a lei L2 da casa
     exigir);
  3. só então avançar para a etapa seguinte.
- **Validação prática em vez de especulação:** não gastar minutos em
  raciocínio abstrato tentando prever erros de sintaxe ou regex — escrever
  o código, executar os testes no terminal e corrigir pelo output REAL.
  Adivinhação não é prova; terminal é prova.

---

## §3 · Regra de Ouro de Entrega: Nenhuma Tarefa Termina Localmente

- **Commit local ≠ Entrega:** uma tarefa ou correção NUNCA é considerada
  concluída enquanto estiver apenas no workspace local. O produto da casa
  é o que o rig do dono recebe pelo canal.
- **Pipeline obrigatório de release** — sempre que houver alteração de
  código/configuração que afete o sistema instalado:
  1. incrementar o `pkgrel` do `elite-system` (lei E41: bump no MESMO
     commit do conteúdo, âncora viva refrescada);
  2. rodar o portão completo de qualidade: `shellcheck 0.11.0` com **0
     avisos** nos scripts da casa + validação de sintaxe (`bash -n`,
     parser do XML quando houver) + suíte completa de testes com **0
     falhas** (veredicto GO);
  3. `git push` para `main` (nunca tag — L4: tag é exclusiva do ciclo
     mensal);
  4. consultar a API do GitHub Actions ATÉ confirmar que os workflows de
     build/publicação concluíram com **`success`** (verdes) e que o novo
     `.pkg.tar.zst` está publicado no índice do repositório `elite-local`
     pronto para `sudo pacman -Syu`. CI vermelha = entrega inacabada: a
     cura é imediata (ou nomeada com run id para a irmã das 16:00 assumir
     — réu escondido é proibido).
- Mudança de papel/documentação (diários, constituições, comentários) não
  bumpa `pkgrel` — jurisprudência E114/E41: bump só com conteúdo de
  sistema mudando.

---

## §4 · Zero Comandos Manuais & Migração Autônoma (`post_upgrade`)

- **O usuário final nunca roda comandos manuais de pós-instalação:** toda
  correção em `/etc`, regras Polkit, systemd units (enable/start/wants),
  parâmetros de kernel/sysctl, remoção/adoção de Flatpaks ou sincronização
  de dotfiles (`~/.config` via `craft-rice` + `labwc --reconfigure`) DEVE
  ser executada automaticamente durante o `pacman -Syu`, através do
  `post_upgrade()` no `elite-system.install` / hooks de pós-transação —
  sem depender do `firstboot-done` (que só roda na instalação inicial). O
  rig já instalado tem de RECEBER a cura pela atualização, não consultá-la
  num manual.
- **Idempotência obrigatória:** toda rotina do `post_upgrade()` deve poder
  rodar MÚLTIPLAS vezes com segurança — sem duplicar linhas, sem quebrar
  configuração do usuário, sem reboot forçado desnecessário (avisar com
  voz clara APENAS quando kernel/drivers mudarem e o boot novo for
  preciso).
- A suíte contrata isso: peça nova de migração entra com teste de
  idempotência (rodar 2× = mesmo estado final).

---

## §5 · Princípios de Arquitetura do `archcraft-elite`

- **Boot instantâneo e zero auto-update no boot:** NUNCA habilitar
  `pacman -Sy`/`-Syu` automático no boot ou silencioso em background
  (gargalo de I/O, `db.lck` travado, partial upgrades, dessincronização de
  módulos do kernel). Atualização é 100% sob demanda via `elite-update` /
  `craft-update`, com o dono no comando.
- **Zero polling desnecessário:** preferir eventos, sockets, sinais
  (`SIGRTMIN+N`), `flock` de instância única e built-ins do shell em vez
  de loops com `pgrep`/`ps` a cada segundo; leitura direta de `/proc` e
  `/sys` quando o dado já mora lá. Idle CPU da sessão é dívida moral.
- **Higiene visual e de sistema:** ícones Papirus consistentes em GTK e Qt
  (`qt6ct`), menus sem nomes crus de interface de hardware (`enp7s0`/
  `wlan0` — rótulos humanos), ausência de apps redundantes e autorização
  Polkit limpa para o grupo `wheel` (pt-br em toda a face do produto, L10
  da casa).

---

## §6 · Formato do Relatório Final

Ao encerrar QUALQUER entrega, apresentar objetivamente:

1. **Hashes dos commits** enviados ao GitHub (`origin/main`);
2. **Versão/release publicada** (`pkgrel` — ou a justificativa E41 de não
   bump);
3. **Status confirmado dos workflows** do GitHub Actions (run id +
   conclusão);
4. **Checklist curto de validação prática** para o usuário confirmar após
   `sudo pacman -Syu` (o que ele deve VER/FAZER no rig — nunca passo
   manual de pós-instalação; o checklist confirma, não conserta).

---

*Casa archcraft-elite · Constituição ratificada pelo dono em 2026-11-20 ·
Fonte da verdade dos dados: `docs/gestao/PROTOCOL.md` (protocolo das 4
tarefas) · Memória que sobrevive ao reset: os diários de `docs/gestao/` ·
Supremacia: este arquivo.*
