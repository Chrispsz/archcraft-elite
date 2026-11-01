# PROTOCOLO DE MANUTENÇÃO CONTÍNUA — Archcraft Elite

Sistema pedido pelo dono ("você trabalhando no repositório diariamente para
melhoria geral do código e atualização… até completar 30 dias e roda build
mensal automática com todos os commits do mês… anti reset sandbox").

FONTE DA VERDADE: **o GitHub** (`origin/main`). O sandbox é DESCARTÁVEL —
pode ser apagado entre uma tarefa e outra. Tudo que importa está commitado
aqui. Se um agente acordar sem repo local, ele re-clona e segue do ponto
onde o diário diz (os diários desta pasta são a memória que sobrevive).

## As 4 tarefas (horários America/Sao_Paulo)

| # | Tarefa | Quando | Diário |
|---|--------|--------|--------|
| 1 | ATUALIZAÇÕES | diário 08:30 | `ATUALIZACOES.md` |
| 2 | POLIMENTO | diário 11:00 | `POLIMENTO.md` |
| 3 | AUDITORIA | diário 16:00 | `AUDITORIA.md` |
| 4 | BUILD MENSAL | 1º do mês 10:00 | worklog + release (CI) |

No dia 1º: as tarefas 1–3 rodam normalmente (commits vão para a build do
mês SEGUINTE; a tag do dia já fechou) e a auditoria verifica também o
resultado da build mensal do dia.

## Leis inegociáveis (valem para TODAS as tarefas)

- **L1 · Bootstrap anti-reset**: repo local em
  `/home/z/my-project/upload/archcraft-elite-v22`. Se existir:
  `git fetch origin && git reset --hard origin/main && git clean -fd`
  (o clone local é CACHE — o GitHub manda). Se NÃO existir: re-clonar com
  o token do agendador (`git clone https://x-access-token:TOKEN@github.com/Chrispsz/archcraft-elite.git`).
  Se nem o clone funcionar: relatório honesto de bloqueio — nunca inventar.
- **L2 · Suíte porteira**: `bash tests/run-tests.sh` com GO local (0
  falhas) antes de QUALQUER push. Sem GO não sai commit.
- **L3 · GitHub API sempre autenticada** (`-H "Authorization: Bearer $TOKEN"`).
  O anônimo engole em IP compartilhado.
- **L4 · Trabalho diário NUNCA pusha tag** — build só no ciclo mensal
  (push em main dispara apenas a Suíte, que é o gate; a tag é exclusiva
  da tarefa 4).
- **L5 · Lei da Release Única Viva + tag imutável**: uma release viva por
  vez (a CI aplica no job release); tag-túmulo fica; nunca deletar tag;
  nunca force push.
- **L6 · Honestidade absoluta**: só afirmar o que provou (run id, exit
  code, hash). Dia sem trabalho = diário diz "nada a fazer" — dia vazio
  honesto vale mais que commit decorativo. NUNCA commit vazio "para constar".
- **L7 · Sincronia**: `git pull --rebase origin main` antes de cada push;
  commits pequenos, mensagem longa e honesta (escola das eras E*).
- **L8 · Diário primeiro**: toda tarefa APPENDA sua entrada no diário da
  pasta (formato fixo abaixo) e commita — é o registro anti-reset. Entrada
  sem prova (run/exit/diff) não vale.
- **L9 · Pin só sobe com checksum publicado e verificado** (escola
  check-brave.sh: baixa, confere contra o .sha256 do upstream, atualiza
  pin+sha juntos). Upstream sem checksum publicado = NÃO sobe; registra
  honestamente no diário o motivo. Pin errado = build vermelha (o makepkg
  da CI re-verifica — a porteira paga).
- **L10 · O produto ao dono é PT-BR** (i18n da overlay) e a suíte contratá
  isso — polimento que quebra PT-BR quebra a suíte.

## Formato do diário (todas as tarefas)

```
## AAAA-MM-DD · <tarefa>
- feito: <o que realmente aconteceu>
- prova: <run id / exit code / diff curto / sha>
- próximo: <o ponto exato onde parou — a próxima entrada continua daqui>
```

A linha `próximo` é a MÁQUINA DE ESTADOS anti-reset: o agente de amanhã
começa lendo a entrada de hoje.

## Risco conhecido e aceito

Diário/pin mexidos por 3 agentes distintos no mesmo dia → colisão de push
é possível. Cura é L7 (pull --rebase; em conflito, rebase preserva AMBAS as
entradas do diário — arquivos são append-only). Ninguém força push jamais.
