/**
 * agents/run.ts — CLI dos agentes Elite (Token Harbor).
 *
 * Uso:
 *   bun agents/run.ts <deepseek|mimo> "<tarefa>" [--context <spec>] [--dry]
 *
 *   --context spec:
 *     ci           → log destilado do run MAIS RECENTE de build.yml
 *     ci:<run_id>  → idem, de um run específico
 *     links        → auditoria ao vivo de todas as URLs/repos do repo
 *     file:<path>  → anexa um arquivo (ou caminho relativo simples)
 *   --dry         → monta o contexto e sai (não chama a API; teste local)
 *
 * Saída: stdout com marcadores ===AGENT-REPORT-BEGIN/END=== + relatório
 * salvo em agents/out/<ts>-<agent>.md (e agents/out/report.md estável).
 */

import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { getAgent } from "./agents";
import { harborChat } from "./harbor";
import { buildCiContext } from "./context-ci";
import { buildLinksContext } from "./context-links";

const argv = process.argv.slice(2);
const agentId = argv[0];
const task = argv[1];
let contextSpec = "";
let dry = false;

for (let i = 2; i < argv.length; i++) {
  if (argv[i] === "--context") contextSpec = argv[++i] ?? "";
  else if (argv[i] === "--dry") dry = true;
  else {
    console.error(`argumento desconhecido: ${argv[i]}`);
    process.exit(2);
  }
}

if (!agentId || !task) {
  console.error(
    "uso: bun agents/run.ts <deepseek|mimo> \"<tarefa>\" [--context ci|ci:<id>|links|file:<path>] [--dry]",
  );
  process.exit(2);
}

const agent = getAgent(agentId); // erro claro se id inválido

// ── Contexto ────────────────────────────────────────────────────────
let contextMd = "";
let contextLabel = contextSpec || "nenhum";
if (contextSpec === "ci" || contextSpec.startsWith("ci:")) {
  const id = contextSpec === "ci" ? "latest" : Number(contextSpec.slice(3));
  const ctx = await buildCiContext(id);
  contextMd = ctx.markdown;
  contextLabel = `ci (run #${ctx.runNumber}, id ${ctx.runId}, ${ctx.status}/${ctx.conclusion ?? "rodando"}, ${(ctx.markdown.length / 1024).toFixed(1)} KB)`;
} else if (contextSpec === "links") {
  const repoDir = join(import.meta.dir, "..");
  contextMd = await buildLinksContext(repoDir);
  contextLabel = `links (${(contextMd.length / 1024).toFixed(1)} KB ao vivo)`;
} else if (contextSpec.startsWith("file:")) {
  contextMd = await import("node:fs").then((fs) =>
    fs.readFileSync(contextSpec.slice(5), "utf8"),
  );
  contextLabel = `file:${contextSpec.slice(5)}`;
} else if (contextSpec) {
  // caminho simples tratado como arquivo
  contextMd = await import("node:fs").then((fs) =>
    fs.readFileSync(contextSpec, "utf8"),
  );
  contextLabel = `file:${contextSpec}`;
}

if (dry) {
  console.log(`[elite-agents] DRY — contexto montado: ${contextLabel}`);
  console.log(contextMd.slice(0, 6000));
  mkdirSync(join(import.meta.dir, "out"), { recursive: true });
  writeFileSync(join(import.meta.dir, "out", "context-preview.md"), contextMd);
  console.log(
    `[elite-agents] contexto completo salvo em agents/out/context-preview.md`,
  );
  process.exit(0);
}

// ── Chamada ao modelo ───────────────────────────────────────────────
console.error(`[elite-agents] agente=${agent.id} modelo=${agent.model}`);
console.error(`[elite-agents] contexto: ${contextLabel}`);

const userContent = contextMd
  ? `${task}\n\n---\n# Contexto anexado\n${contextMd}`
  : task;

let reply: string;
try {
  reply = await harborChat({
    model: agent.model,
    messages: [
      { role: "system", content: agent.role },
      { role: "user", content: userContent },
    ],
    temperature: agent.temperature,
    maxTokens: agent.maxTokens,
  });
} catch (e) {
  const msg = e instanceof Error ? e.message : String(e);
  console.error(`[elite-agents] FALHA: ${msg}`);
  process.exit(1);
}

// ── Relatório ───────────────────────────────────────────────────────
const ts = new Date()
  .toISOString()
  .replace(/[-:]/g, "")
  .replace(/\..+/, "")
  .replace("T", "-");

const front = [
  "---",
  `agent: ${agent.id} (${agent.name})`,
  `model: ${agent.model}`,
  `task: ${task.replace(/\n/g, " ")}`,
  `context: ${contextLabel}`,
  `generated_at: ${new Date().toISOString()}`,
  "---",
  "",
].join("\n");

const report = `${front}${reply}\n`;

mkdirSync(join(import.meta.dir, "out"), { recursive: true });
const stampFile = join(import.meta.dir, "out", `${ts}-${agent.id}.md`);
writeFileSync(stampFile, report);
writeFileSync(join(import.meta.dir, "out", "report.md"), report);

console.log("===AGENT-REPORT-BEGIN===");
console.log(reply);
console.log("===AGENT-REPORT-END===");
console.error(`[elite-agents] relatório salvo: agents/out/${ts}-${agent.id}.md`);
