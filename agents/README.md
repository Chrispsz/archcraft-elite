# agents/ — Equipe de IA do archcraft-elite

Dois agentes alimentados pelos modelos **free do Token Harbor**, especializados
neste projeto:

| id | modelo | papel |
|---|---|---|
| `deepseek` | `deepseek-v4.1-flash:free` | **Elite Builder** — engenheiro sênior de build: triagem de logs de CI com causa-raiz, patches cirúrgicos |
| `mimo` | `mimo-v2.6-flash:free` | **Elite Auditor** — auditor de QA: saúde de URLs/repos, mirror skew, riscos de curl error |

## Uso local (região permitida — ex.: Brasil)

```bash
# Token em agents/.env (gitignored) ou na env TH_TOKEN
echo 'TH_TOKEN=thk_live_...' > agents/.env

bun agents/run.ts deepseek "Por que o run #16 falhou?" --context ci:39358110229
bun agents/run.ts mimo     "Audite os repos do build" --context links
```

`--context` aceita:
- `ci` → log destilado do run **mais recente** de `build.yml` (erro/warning/curl + steps + cauda)
- `ci:<run_id>` → idem, de um run específico
- `links` → auditoria ao vivo: todas as URLs do repo + DBs pacman que o build realmente baixa (`{server}/{seção}.db`), com HEAD/GET-range real
- `file:<caminho>` → anexa um arquivo qualquer

Saída: stdout com marcadores `===AGENT-REPORT-BEGIN/END===` + relatório em
`agents/out/<ts>-<agente>.md` (não versionado).

`--dry` monta o contexto e sai sem chamar a API (teste local).

## Relay via GitHub Actions (para regiões bloqueadas)

O Token Harbor bloqueia HK/Macau/China e regiões sancionadas. Se a chamada
direta cair em `REGION_BLOCKED`, use o relay — o runner do GitHub (EUA) executa
o mesmo `agents/run.ts` com o secret `TH_TOKEN` do repo:

```bash
gh workflow run agents.yml -f agent=deepseek -f task="..." -f context=ci
# ou pela UI: Actions → Agents → Run workflow
```

O relatório volta como **artifact** (`agent-<id>-<n>`), no **log do job**
(marcadores BEGIN/END) e commitado na branch **`agent-reports`**
(`reports/<ts>-<agente>.md`).

## Arquivos

| arquivo | função |
|---|---|
| `agents.ts` | perfis + system prompts dos dois agentes |
| `harbor.ts` | cliente Token Harbor (OpenAI-compatible, retry 429/5xx, zero deps) |
| `context-ci.ts` | busca runs/jobs/logs no GitHub API e destila o log |
| `context-links.ts` | varre o repo, extrai URLs, verifica ao vivo (inclui `.db` reais) |
| `run.ts` | CLI que junta tudo |

## Segurança

- `TH_TOKEN` **nunca** é commitado: local fica em `agents/.env` (gitignored),
  no CI fica nos **secrets do repo**.
- O relay não imprime o token; em caso de falha de auth a mensagem não vaza valor.
