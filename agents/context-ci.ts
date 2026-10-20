/**
 * agents/context-ci.ts — Constrói o contexto de triagem de CI.
 *
 * Busca via GitHub REST API (sem dependências):
 *   1. Run mais recente do workflow build.yml (ignora runs de agents.yml)
 *      — ou um run específico por id.
 *   2. Jobs + steps (com conclusões) do run.
 *   3. Log de CADA job em texto puro (endpoint /actions/jobs/{id}/logs).
 *   4. "Destila" cada log: linhas de erro/warning/curl + cabeçalho + cauda,
 *      com orçamento de bytes — o agente recebe o essencial, não 50 MB.
 *
 * Token: GH_TOKEN | GITHUB_TOKEN | extraído do remote git (origin).
 * Repo:  GH_REPO | extraído do remote git (origin).
 */

import { execSync } from "node:child_process";

export interface CiContext {
  markdown: string;
  runId: number;
  runNumber: number;
  status: string;
  conclusion: string | null;
}

// ── API helpers ─────────────────────────────────────────────────────

export function ghToken(): string {
  if (process.env.GH_TOKEN) return process.env.GH_TOKEN;
  if (process.env.GITHUB_TOKEN) return process.env.GITHUB_TOKEN;
  try {
    const url = execSync("git remote get-url origin", {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    const m = url.match(/x-access-token:([^@]+)@/);
    if (m) return m[1]!;
  } catch {
    /* sem remote — cai no erro abaixo */
  }
  throw new Error(
    "GH_TOKEN/GITHUB_TOKEN não definidos nem extraível do remote git.",
  );
}

export function ghRepo(): string {
  if (process.env.GH_REPO) return process.env.GH_REPO;
  try {
    const url = execSync("git remote get-url origin", {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    const m = url.match(/github\.com[/:]([^/]+\/[^/.]+)(?:\.git)?$/);
    if (m) return m[1]!;
  } catch {
    /* ignore */
  }
  throw new Error("GH_REPO não definido nem extraível do remote git.");
}

async function api(path: string): Promise<any> {
  const res = await fetch(`https://api.github.com${path}`, {
    headers: {
      Authorization: `Bearer ${ghToken()}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });
  if (!res.ok) {
    throw new Error(
      `GitHub API ${res.status} em ${path}: ${(await res.text()).slice(0, 200)}`,
    );
  }
  return res.json();
}

async function fetchJobLog(jobId: number): Promise<string | null> {
  const res = await fetch(
    `https://api.github.com/repos/${ghRepo()}/actions/jobs/${jobId}/logs`,
    {
      headers: { Authorization: `Bearer ${ghToken()}` },
      redirect: "follow",
    },
  );
  if (!res.ok) return null;
  return res.text();
}

// ── Destilação de log ───────────────────────────────────────────────

const RX_INTEREST = new RegExp(
  [
    "error",
    "failed",
    "failure",
    "fatal",
    "warn",
    "curl",
    "\\b40[345]\\b",
    "\\b42?9\\b",
    "timed?[- ]?out",
    "invalid",
    "unable",
    "cannot",
    "not found",
    "denied",
    "refused",
    "abort",
    "exception",
    "traceback",
    "skew",
    "mismatch",
    "missing",
    "conflict",
    "corrupt",
    "warning:",
  ].join("|"),
  "i",
);

export function distillLog(text: string, budgetBytes: number): string {
  // Guarda de memória: logs gigantes ficam com head 2 MB + tail 4 MB.
  if (text.length > 8_000_000) {
    text = text.slice(0, 2_000_000) + "\n… (meio do log cortado) …\n" + text.slice(-4_000_000);
  }
  const lines = text.split("\n");
  const total = lines.length;

  const keep = new Set<number>();
  for (let i = 0; i < total; i++) {
    if (RX_INTEREST.test(lines[i]!)) {
      keep.add(i);
      keep.add(i + 1); // 1 linha de contexto após
    }
  }
  for (let i = 0; i < Math.min(12, total); i++) keep.add(i); // setup do job
  for (let i = Math.max(0, total - 100); i < total; i++) keep.add(i); // cauda

  const out: string[] = [];
  let prev = -2;
  let bytes = 0;
  const sorted = [...keep].filter((i) => i < total).sort((a, b) => a - b);
  for (const i of sorted) {
    if (i !== prev + 1) out.push(`  … (${i - prev - 1} linhas omitidas)`);
    const line = lines[i]!;
    out.push(line);
    bytes += line.length + 2;
    prev = i;
    if (bytes > budgetBytes) {
      out.push("  … (orçamento de contexto atingido — log truncado)");
      break;
    }
  }
  return out.join("\n");
}

// ── Contexto completo ───────────────────────────────────────────────

const fmt = (s?: string | null) =>
  s ? s.replace("T", " ").replace("Z", " UTC") : "—";

export async function buildCiContext(
  runIdOrLatest: number | "latest" = "latest",
): Promise<CiContext> {
  const repo = ghRepo();

  let run: any;
  if (runIdOrLatest === "latest") {
    const data = await api(
      `/repos/${repo}/actions/workflows/build.yml/runs?per_page=1`,
    );
    run = data?.workflow_runs?.[0];
    if (!run) throw new Error("nenhum run encontrado para build.yml");
  } else {
    run = await api(`/repos/${repo}/actions/runs/${runIdOrLatest}`);
  }

  const jobsData = await api(
    `/repos/${repo}/actions/runs/${run.id}/jobs?per_page=100`,
  );
  const jobs: any[] = jobsData?.jobs ?? [];

  const parts: string[] = [];
  parts.push(`# Run do CI: #${run.run_number} (id ${run.id})`);
  parts.push(
    [
      `- workflow: ${run.name} (${run.path})`,
      `- status: **${run.status}** · conclusion: **${run.conclusion ?? "ainda rodando"}**`,
      `- commit: \`${String(run.head_sha).slice(0, 7)}\` — ${run.head_commit?.message?.split("\n")[0] ?? ""}`,
      `- evento: ${run.event} · branch: ${run.head_branch}`,
      `- criado: ${fmt(run.created_at)} · atualizado: ${fmt(run.updated_at)}`,
      `- URL: ${run.html_url}`,
    ].join("\n"),
  );

  for (const job of jobs) {
    parts.push(`\n---\n## Job: ${job.name} — ${job.conclusion ?? job.status}\n`);
    const steps = (job.steps ?? [])
      .map(
        (s: any) =>
          `  - ${s.conclusion ?? s.status}: ${s.name} (${fmt(s.started_at)} → ${fmt(s.completed_at)})`,
      )
      .join("\n");
    parts.push(`### Steps\n${steps || "  (sem steps registrados)"}`);

    const raw = await fetchJobLog(job.id);
    if (raw == null) {
      parts.push("### Log\n(não disponível — o job ainda pode estar rodando)");
      continue;
    }
    const distilled = distillLog(raw, 48_000);
    parts.push(
      `### Log destilado (linhas de erro/warning + cabeçalho + cauda)\n` +
        "```\n" +
        distilled +
        "\n```",
    );
  }

  return {
    markdown: parts.join("\n"),
    runId: run.id,
    runNumber: run.run_number,
    status: run.status,
    conclusion: run.conclusion,
  };
}
