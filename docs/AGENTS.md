# AGENTS — auditoria por IA e protocolo de consenso

O projeto mantém dois agentes de IA externos que auditam o trabalho — e uma
regra dura: **só entra no código o que os três modelos concordam**
(Z.ai/GLM, DeepSeek e MiMo). Este documento descreve a infraestrutura, a
cota e o protocolo.

## Infraestrutura (Token Harbor)

`agents.yml` executa `agents/run.ts` NO RUNNER do GitHub Actions (a API do
Token Harbor bloqueia algumas regiões; os runners dos EUA sempre passam).
Cada execução devolve o relatório em três lugares:

1. Log do job (marcadores `===AGENT-REPORT-BEGIN/END===`);
2. Artifact `agent-<id>-<run_number>`;
3. Commit na branch `agent-reports` (`reports/<ts>-<agent>.md`).

| Agente | Modelo (Token Harbor) | Papel |
|---|---|---|
| `deepseek` | `deepseek-v4.1-flash:free` | **Elite Builder** — engenheiro de build: causa-raiz de logs, patch mínimo, riscos |
| `mimo` | `mimo-v2.6-flash:free` | **Elite Auditor** — QA: saúde de URLs/repos, mirror skew, riscos ranqueados |

## Como disparar

Pela UI: *Actions → Agents → Run workflow* (escolha agente, tarefa e
contexto: `ci`, `ci:<run_id>`, `links` ou um caminho de arquivo).

Pela CLI:

```bash
gh workflow run agents.yml \
  -f agent=deepseek \
  -f task="Audite a run de build <N>: procure unidades em crash-loop, pacotes órfãos e regressões vs. build anterior. Cite linhas de log." \
  -f context=ci:<run_id>
```

Contexto `ci` anexa o log destilado da run (48+ KB) à tarefa — o agente
trabalha com evidência real, nunca com suposição.

## Cota e a lição v2.0.1 (fim dos artifacts 0 MB)

O tier free do Token Harbor tem allowance por período. Na v2.0.x o relay
disparava os dois agentes **em toda build** (inclusive runs canceladas),
queimou a cota e passou a devolver **HTTP 429** — e como o `report.md` só
nascia depois da resposta, os artifacts ficavam com ~0.5 KB (a UI mostra
"0 MB"): **a cara da auditoria fake**.

Correções v2.1:

- O relay automático foi **removido do `build.yml`** — auditoria é sob
  demanda (o canto manual acima).
- `run.ts` agora escreve **relatório de FALHA assinado** (`status: FALHA` +
  erro exato) ANTES do exit — ausência de auditoria nunca mais passa por
  auditoria silenciosa.
- Se o erro for 429, aguardar o reset do período e re-disparar. O reset da
  cota atual está anunciado na própria mensagem de erro do Token Harbor.

## Protocolo de consenso (3 IAs)

1. **Z.ai/GLM** (este projeto, agent principal) implementa e documenta a
   mudança, com o diff e a justificativa.
2. **DeepSeek** recebe a MESMA mudança via `agents.yml`
   (`agent=deepseek`) com a tarefa de revisão (patch > contorno; riscos
   explícitos) e responde com veredito `GO`/`NO-GO` + achados.
3. **MiMo** recebe a MESMA mudança (`agent=mimo`) com foco em QA
   (contratos, confiabilidade de teste, links/URLs) e responde
   `GO`/`NO-GO` + achados.
4. **Regra:** só passa o que os TRÊS marcam GO. `NO-GO` de qualquer um
   manda o item para o backlog com a objeção documentada — não para o
   commit. Achados convergentes de 2+ modelos viram prioridade alta.

### Tarefa de revisão pronta (copiar no campo `task`)

```text
Revise a mudança anexada (diff no contexto). Para cada item responda GO ou
NO-GO com evidência: (1) a correção é mínima e não contorno? (2) o que ela
pode quebrar? (3) os contratos/testes cobrem a mudança? (4) há risco de
segurança novo? Formato: TL;DR → tabela item/GO-NO-GO/evidência → riscos.
```

## Histórico

Os relatórios anteriores (v1.x, incl. a auditoria do DeepSeek que refutou a
tese do failover com as próprias linhas do log — relay #6) vivem na branch
[`agent-reports`](../../tree/agent-reports).
