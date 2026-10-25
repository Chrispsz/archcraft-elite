/**
 * agents/harbor.ts — Cliente Token Harbor (API compatível com OpenAI).
 *
 * Zero dependências: usa fetch global (Bun ou Node >= 18).
 * Endpoint: POST {TH_BASE}/chat/completions   [padrão: https://tokenharbor.ai/v1]
 * Auth: Bearer TH_TOKEN (env, ou agents/.env ao lado deste arquivo).
 *
 * Nota de geo: Token Harbor bloqueia HK/Macau/China continental. Se você
 * estiver numa região bloqueada, use o relay .github/workflows/agents.yml
 * (runner dos EUA) em vez de chamar direto.
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

export class HarborError extends Error {
  constructor(
    message: string,
    public readonly kind:
      | "REGION_BLOCKED"
      | "AUTH"
      | "HTTP"
      | "TIMEOUT"
      | "EMPTY",
    public readonly status?: number,
  ) {
    super(message);
    this.name = "HarborError";
  }
}

export function loadToken(): string {
  if (process.env.TH_TOKEN) return process.env.TH_TOKEN;
  const envPath = join(import.meta.dir, ".env");
  if (existsSync(envPath)) {
    for (const line of readFileSync(envPath, "utf8").split("\n")) {
      const m = line.match(/^\s*TH_TOKEN\s*=\s*(\S+)\s*$/);
      if (m) return m[1]!;
    }
  }
  throw new HarborError(
    "TH_TOKEN não definido (variável de ambiente ou agents/.env).",
    "AUTH",
  );
}

export function baseUrl(): string {
  return (process.env.TH_BASE ?? "https://tokenharbor.ai/v1").replace(/\/+$/, "");
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function harborChat(opts: {
  model: string;
  messages: ChatMessage[];
  temperature?: number;
  maxTokens?: number;
  timeoutMs?: number;
  /** Retry interno: se o raciocínio consumir o orçamento e o content vier
   *  vazio (modelos reasoning), dobra maxTokens e tenta UMA vez. */
  allowBudgetRetry?: boolean;
}): Promise<string> {
  const token = loadToken();
  const url = `${baseUrl()}/chat/completions`;
  const body = JSON.stringify({
    model: opts.model,
    messages: opts.messages,
    temperature: opts.temperature ?? 0.2,
    max_tokens: opts.maxTokens ?? 8192,
  });

  // 3 tentativas: 429/5xx fazem backoff (modelos :free têm rate limit apertado).
  for (let attempt = 1; attempt <= 3; attempt++) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), opts.timeoutMs ?? 300_000);
    let res: Response;
    try {
      res = await fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body,
        signal: ctl.signal,
      });
    } catch (e: unknown) {
      clearTimeout(timer);
      const msg = e instanceof Error ? e.message : String(e);
      // v1.8 — ERRO DE REDE TAMBÉM REPETE: o ECONNRESET matou o relay #41
      // (socket fechado pelo endpoint free aos 60s, depois do request vivo)
      // e o catch re-throwava sem nenhuma 2ª chance — só 429/5xx repetiam.
      // Mesma política do loop HTTP: backoff e tenta de novo até 3×.
      if (attempt < 3) {
        console.error(
          `[harbor] rede falhou (tentativa ${attempt}/3): ${msg} — repetindo com backoff`,
        );
        await sleep(attempt * 5000);
        continue;
      }
      throw new HarborError(
        `falha de rede ao contatar ${url}: ${msg}`,
        "TIMEOUT",
      );
    }
    clearTimeout(timer);

    const text = await res.text();

    if (res.ok) {
      let data: any;
      try {
        data = JSON.parse(text);
      } catch {
        throw new HarborError(
          `resposta não-JSON do Harbor: ${text.slice(0, 300)}`,
          "EMPTY",
        );
      }
      const msg: any = data?.choices?.[0]?.message;
      const content: string | undefined = msg?.content;
      if (!content) {
        // Modelos reasoning (deepseek/mimo flash): o raciocínio pode consumir
        // o orçamento inteiro e o content final vem vazio/truncado. Uma vez:
        // dobra o orçamento e repete a chamada (mesma conversa, sem re-montar).
        const reasoning: string | undefined = msg?.reasoning_content;
        if (reasoning && opts.allowBudgetRetry !== false) {
          // Modelos reasoning EXPANDEM o raciocínio para preencher o orçamento
          // (relay #5: 27.399 chars de raciocínio comeram 8192 E 16384). O
          // retry multiplica ×4 e injeta diretriz de concisão no final da
          // mensagem do usuário — ataca o problema dos dois lados.
          console.error(
            `[harbor] content vazio com raciocínio de ${reasoning.length} chars — reexecutando com 4x o orçamento + diretriz de concisão`,
          );
          const messages = opts.messages.map((m, i) =>
            i === opts.messages.length - 1 && m.role === "user"
              ? { ...m, content: m.content + "\n\n[diretiva: orçamento ampliado — raciocine o mínimo necessário e vá DIRETO à resposta estruturada pedida]" }
              : m,
          );
          return harborChat({
            ...opts,
            messages,
            maxTokens: (opts.maxTokens ?? 8192) * 4,
            allowBudgetRetry: false,
          });
        }
        if (reasoning && reasoning.length > 2000) {
          // Último recurso: o content nunca veio, mas o raciocínio traz a
          // análise (parcial). Entrega MARCADA — melhor que run falho.
          console.error(
            `[harbor] content vazio após retry; entregando o raciocínio (${reasoning.length} chars) como relatório marcado`,
          );
          return "> **[harbor]** content veio vazio mesmo após retry orçado —\n> relatório recuperado do canal de raciocínio (pode estar incompleto):\n\n" +
            reasoning.slice(-12000);
        }
        throw new HarborError(
          `completion vazia do Harbor: ${JSON.stringify(data).slice(0, 400)}`,
          "EMPTY",
        );
      }
      return content;
    }

    // Erros HTTP — classifica os casos acionáveis.
    if (res.status === 403 && text.includes("region_blocked")) {
      throw new HarborError(
        "Token Harbor bloqueou a região deste IP (HK/Macau/China/sancionadas). " +
          "Use o relay: workflow_dispatch em .github/workflows/agents.yml " +
          "(runner nos EUA) ou rode de uma região permitida.",
        "REGION_BLOCKED",
        res.status,
      );
    }
    if (res.status === 401 || res.status === 403) {
      throw new HarborError(
        `TH_TOKEN recusado (HTTP ${res.status}): ${text.slice(0, 200)}`,
        "AUTH",
        res.status,
      );
    }
    if (res.status === 429 && attempt < 3) {
      await sleep(attempt * 8000);
      continue;
    }
    if (res.status >= 500 && attempt < 3) {
      await sleep(attempt * 5000);
      continue;
    }
    throw new HarborError(
      `HTTP ${res.status} do Harbor: ${text.slice(0, 400)}`,
      "HTTP",
      res.status,
    );
  }
  throw new HarborError("esgotadas as tentativas contra o Harbor", "HTTP");
}
