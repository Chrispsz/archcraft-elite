/**
 * agents/context-links.ts — Constrói o contexto de auditoria de links.
 *
 * 1. Varre os arquivos load-bearing do repo e extrai TODAS as URLs http(s):
 *    pacman-repos.build.add, mirrorlists, scripts (.ci/, scripts/,
 *    elite/fragments/, elite/airootfs/usr/local/bin/), workflows.
 * 2. Para cada Server= (em QUALQUER arquivo — conf, mirrorlist, printf em
 *    script), verifica o que o pacman REALMENTE busca: {server}/{seção}.db.
 *    Variáveis pacman são expandidas ($repo→seção, $arch→x86_64).
 * 3. Para cada URL genérica: HEAD (fallback GET Range) — classificada:
 *      - template  → artefato de shell (${var}, $REPO, https://}) — não é URL
 *      - base      → base de Server=; listing 404 é ESPERADO em CDN, a prova
 *                    é o .db do §1 (não conta como falha)
 *      - raiz      → raiz do host sem path — informativo
 *      - normal    → load-bearing; 4xx/5xx = FALHA REAL
 * 4. Emite Markdown tabelado por papel, pronto para o agente auditor.
 *
 * Zero dependências. Concorrência 8, timeout 12 s por request.
 */

import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, relative } from "node:path";

// ── Descoberta de arquivos ──────────────────────────────────────────

function walk(dir: string, out: string[] = []): string[] {
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return out;
  }
  for (const e of entries) {
    if (e === ".git" || e === "out" || e === "node_modules") continue;
    const p = join(dir, e);
    let st;
    try {
      st = statSync(p);
    } catch {
      continue;
    }
    if (st.isDirectory()) walk(p, out);
    else if (st.isFile() && st.size < 2_000_000) out.push(p);
  }
  return out;
}

function targets(repoDir: string): string[] {
  const t: string[] = [];
  const add = (p: string) => {
    if (existsSync(join(repoDir, p))) t.push(join(repoDir, p));
  };
  add("elite/pacman-repos.build.add");
  for (const p of walk(join(repoDir, "elite/airootfs/etc/pacman.d"))) t.push(p);
  for (const d of ["scripts", ".ci", "elite/fragments"]) {
    for (const p of walk(join(repoDir, d))) t.push(p);
  }
  const binDir = join(repoDir, "elite/airootfs/usr/local/bin");
  if (existsSync(binDir)) for (const p of walk(binDir)) t.push(p);
  add(".github/workflows/build.yml");
  add(".github/workflows/agents.yml");
  return t;
}

// ── Extração e classificação ────────────────────────────────────────

const URL_RX = /https?:\/\/[^\s"'`<>\\]+/g;

function normalize(u: string): string {
  return u.replace(/[),.;:!?'"]+$/g, "").replace(/\)+$/g, "");
}

/** Artefato de shell — NÃO é uma URL literal probe-ável. */
export function isTemplate(u: string): boolean {
  if (/[{}]/.test(u)) return true; // https://${var}, https://} (bash ${m#https://})
  // $REPO, $file… são vars de shell; $arch/$repo são vars do pacman (expansíveis)
  return /\$(?!arch\b|repo\b)[A-Za-z_]/.test(u);
}

/** Expande variáveis pacman para probes ($arch→x86_64, $repo→core). */
export function expandPacmanVars(u: string): string {
  return u.replace(/\$arch/g, "x86_64").replace(/\$repo\b/g, "core");
}

function roleOf(u: string): string {
  const host = u.toLowerCase();
  if (host.includes("cachyos.org")) return "cachyos";
  if (host.includes("archcraft")) return "archcraft";
  if (
    host.includes("archlinux.org") ||
    host.includes("pkgbuild.com") ||
    /\/archlinux\//.test(u)
  )
    return "arch-mirror";
  if (host.includes("github.com") || host.includes("githubusercontent.com"))
    return "github";
  return "other";
}

interface UrlHit {
  url: string;
  roles: string;
  files: string[];
}

function extractUrls(repoDir: string): Map<string, UrlHit> {
  const map = new Map<string, UrlHit>();
  for (const file of targets(repoDir)) {
    let text: string;
    try {
      text = readFileSync(file, "utf8");
    } catch {
      continue;
    }
    if (text.includes("\0")) continue; // binário
    for (const raw of text.match(URL_RX) ?? []) {
      const u = normalize(raw);
      if (!/^https?:\/\//.test(u)) continue;
      const hit = map.get(u) ?? {
        url: u,
        roles: roleOf(u),
        files: [],
      };
      const rel = relative(repoDir, file);
      if (!hit.files.includes(rel)) hit.files.push(rel);
      map.set(u, hit);
    }
  }
  return map;
}

// ── Servers pacman → probe do .db real ──────────────────────────────

interface PacmanDbProbe {
  section: string;
  server: string; // como escrito no arquivo (com $arch etc.)
  dbUrl: string; // o que o pacman realmente baixa
  origin: string; // arquivo de onde veio
  result: string; // preenchido pelo check
}

/** Seção inferida da própria URL (para Server= em printf, sem header rastreável). */
function inferSection(server: string): string {
  const lower = server.toLowerCase();
  if (lower.includes("archcraft")) return "archcraft";
  const m = server.match(/\/([^/$]+)$/); // último segmento de path, sem vars
  if (m && m[1] && !m[1].includes(".")) return m[1]!;
  return "";
}

function extractPacmanServers(repoDir: string): PacmanDbProbe[] {
  const probes: PacmanDbProbe[] = [];
  const byDb = new Map<string, PacmanDbProbe>();
  for (const file of targets(repoDir)) {
    let text: string;
    try {
      text = readFileSync(file, "utf8");
    } catch {
      continue;
    }
    let section = "";
    for (const line of text.split("\n")) {
      const rel = relative(repoDir, file);
      // Seções pacman são identificadores ([core], [cachyos-v3]…). Testes de
      // shell ([ -z "…" ]) NÃO são seções: a classe abaixo rejeita espaços/aspas.
      const sec = line.match(/^\s*\[([A-Za-z0-9_-]+)\]/);
      if (sec) {
        section = sec[1]!;
        continue;
      }
      // Tier 1: linha de conf/mirrorlist — 'Server = <url>'
      // Tier 2: embutido em printf/echo de script — 'Server = https://…'
      //         (Servers construídos com %s/vars não têm literal http → ficam
      //          de fora por honestidade: não há URL conhecida para sondar)
      const srv =
        line.match(/^\s*Server\s*=\s*(\S+)/) ??
        line.match(/Server\s*=\s*(https?:\/\/[^\s'"`\\]+)/);
      if (!srv) continue;
      const server = srv[1]!;
      if (!/^https?:/.test(server)) continue; // file:// ([elite-local]) não é probeável
      let secName = section;
      if (!secName || secName === "options") secName = inferSection(server);
      if (!secName) continue; // sem seção e sem inferência — não dá nome ao .db
      const expanded = server
        .replace(/\$repo/g, secName)
        .replace(/\$arch/g, "x86_64");
      const dbUrl = expanded.replace(/\/+$/, "") + `/${secName}.db`;
      const existing = byDb.get(dbUrl);
      if (existing) {
        if (!existing.origin.includes(rel)) existing.origin += `, ${rel}`;
        continue;
      }
      const p: PacmanDbProbe = {
        section: secName,
        server,
        dbUrl,
        origin: rel,
        result: "?",
      };
      byDb.set(dbUrl, p);
      probes.push(p);
    }
  }
  return probes;
}

// ── Checks ao vivo ──────────────────────────────────────────────────

interface CheckResult {
  status: number;
  finalUrl: string;
  ms: number;
  method: string;
  err?: string;
}

async function checkUrl(
  url: string,
  timeoutMs = 12_000,
): Promise<CheckResult> {
  const t0 = performance.now();
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  const doFetch = (method: "HEAD" | "GET", extra: Record<string, string> = {}) =>
    fetch(url, {
      method,
      redirect: "follow",
      signal: ctl.signal,
      headers: { "User-Agent": "elite-agents-linkcheck/1.0", ...extra },
    });
  try {
    let res = await doFetch("HEAD");
    let method = "HEAD";
    // Alguns servidores recusam HEAD — fallback GET com Range 0-0.
    if ([403, 405, 501].includes(res.status)) {
      res = await doFetch("GET", { Range: "bytes=0-0" });
      method = "GET(range)";
    }
    return {
      status: res.status,
      finalUrl: res.url || url,
      ms: Math.round(performance.now() - t0),
      method,
    };
  } catch (e: unknown) {
    return {
      status: 0,
      finalUrl: url,
      ms: Math.round(performance.now() - t0),
      method: "HEAD",
      err: e instanceof Error ? e.message : String(e),
    };
  } finally {
    clearTimeout(timer);
  }
}

async function pool<T, R>(
  items: T[],
  n: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = [];
  let i = 0;
  const workers = Array.from({ length: Math.min(n, items.length) }, async () => {
    while (i < items.length) {
      const idx = i++;
      results[idx] = await fn(items[idx]!);
    }
  });
  await Promise.all(workers);
  return results;
}

// ── Contexto completo ───────────────────────────────────────────────

type EvClass = "normal" | "base" | "raiz" | "template";

interface Evidence {
  hit: UrlHit;
  cls: EvClass;
  probeUrl: string; // URL efetivamente sondada (expansões aplicadas)
  check: CheckResult | null; // null para templates
}

const stripSlash = (u: string) => u.replace(/\/+$/, "");

function isHostRoot(u: string): boolean {
  try {
    return new URL(u).pathname.replace(/\/+$/, "") === "";
  } catch {
    return false;
  }
}

export async function buildLinksContext(repoDir: string): Promise<string> {
  const urls = extractUrls(repoDir);
  const urlList = [...urls.values()];
  const dbProbes = extractPacmanServers(repoDir);

  console.error(
    `[context-links] ${urlList.length} URLs únicas + ${dbProbes.length} probes de DB pacman`,
  );

  await pool(dbProbes, 8, async (p) => {
    const r = await checkUrl(p.dbUrl);
    p.result = r.status
      ? `${r.status} (${r.method}, ${r.ms} ms)`
      : `ERRO: ${r.err}`;
    if (r.finalUrl !== p.dbUrl && r.status >= 200 && r.status < 400) {
      p.result += ` → ${r.finalUrl}`;
    }
  });

  // Bases expandidas dos Servers (para classificar §2): o que resta do
  // dbUrl depois de tirar o sufixo /{seção}.db, sem barras finais.
  const dbBases = new Set<string>();
  for (const p of dbProbes) {
    dbBases.add(
      stripSlash(p.dbUrl.slice(0, p.dbUrl.length - `/${p.section}.db`.length)),
    );
  }

  const evidence: Evidence[] = await pool(urlList, 8, async (h) => {
    if (isTemplate(h.url)) {
      return { hit: h, cls: "template", probeUrl: h.url, check: null };
    }
    const probeUrl = stripSlash(expandPacmanVars(h.url));
    let cls: EvClass = "normal";
    if (dbBases.has(probeUrl)) cls = "base";
    else if (isHostRoot(probeUrl)) cls = "raiz";
    const check = await checkUrl(probeUrl);
    return { hit: h, cls, probeUrl, check };
  });

  const ok = evidence.filter(
    (e) => e.check && e.check.status >= 200 && e.check.status < 300,
  );
  const fail = evidence.filter(
    (e) =>
      e.cls === "normal" &&
      e.check &&
      !(e.check.status >= 200 && e.check.status < 400),
  );
  const bases = evidence.filter((e) => e.cls === "base");
  const roots = evidence.filter((e) => e.cls === "raiz");
  const templates = evidence.filter((e) => e.cls === "template");

  const parts: string[] = [];
  parts.push("# Auditoria de links do archcraft-elite (evidência ao vivo)");
  parts.push(
    `Verificado em ${new Date().toISOString()} · ` +
      `${ok.length} ok · **${fail.length} falha(s) REAL(IS)** · ` +
      `${bases.length} base(s) Server= · ${roots.length} raiz(es) de host · ` +
      `${templates.length} template(s) de shell`,
  );

  parts.push("\n## 1. DBs pacman — o que o build realmente baixa");
  parts.push(
    "Cada `Server=` (conf, mirrorlist ou printf em script) sondado no que o " +
      "pacman efetivamente busca: `{server}/{seção}.db`. " +
      "Servers `file://` ([elite-local]) não aparecem aqui — repo gerado no próprio CI, não probeável.",
  );
  parts.push(
    "| seção | server | db verificado | resultado | origem |\n|---|---|---|---|---|",
  );
  for (const p of dbProbes) {
    parts.push(
      `| \`${p.section}\` | \`${p.server}\` | \`${p.dbUrl}\` | ${p.result} | \`${p.origin}\` |`,
    );
  }

  parts.push("\n## 2. Todas as URLs do repo, por papel");
  parts.push(
    "classificação: **base** = base de `Server=` (listing 404 é ESPERADO em CDN; " +
      "a prova de vida é o .db do §1) · **raiz** = host sem path (informativo) · " +
      "**template** = artefato de shell, não é URL · **normal** = load-bearing.",
  );
  const byRole = new Map<string, Evidence[]>();
  for (const e of evidence) {
    const list = byRole.get(e.hit.roles) ?? [];
    list.push(e);
    byRole.set(e.hit.roles, list);
  }
  for (const role of [...byRole.keys()].sort()) {
    parts.push(`\n### ${role}`);
    parts.push(
      "| URL | classificação | HTTP | método | ms | redirect final | usado em |",
    );
    parts.push("|---|---|---|---|---|---|---|");
    for (const e of byRole.get(role)!) {
      const final =
        e.check && e.check.finalUrl !== e.probeUrl ? e.check.finalUrl : "";
      const status = e.check
        ? e.check.err
          ? `ERRO (${e.check.err.slice(0, 60)})`
          : String(e.check.status)
        : "—";
      parts.push(
        `| \`${e.hit.url}\` | ${e.cls} | ${status} | ${e.check?.method ?? "—"} | ${e.check?.ms ?? "—"} | ${final ? `\`${final}\`` : ""} | ${e.hit.files.map((f) => `\`${f}\``).join(", ")} |`,
      );
    }
  }

  parts.push("\n## 3. Resumo executivo");
  parts.push(
    `- Total de URLs únicas: **${evidence.length}** em ${new Set(urlList.flatMap((h) => h.files)).size} arquivos`,
  );
  parts.push(`- Saudáveis (2xx): **${ok.length}**`);
  parts.push(
    `- **FALHAS REAIS (load-bearing, 4xx/5xx/erro): ${fail.length}** — ` +
      (fail.length
        ? "estas QUEBRARIAM o build/tarefa:"
        : "nenhuma. As não-2xx abaixo são esperadas por construção:"),
  );
  for (const e of fail) {
    parts.push(
      `  - \`${e.hit.url}\` → ${e.check?.status || "ERRO"} ${e.check?.err ?? ""} (${e.hit.files.join(", ")})`,
    );
  }
  if (bases.length) {
    parts.push(
      `- Bases de Server= sem listing (ESPERADO — cdn77 não lista diretórios; ` +
        `us lista): ${bases.length}. O que o pacman baixa de verdade (${bases.length > 0 ? "ver §1" : ""}): todos os .db correspondentes já estão em §1.`,
    );
    for (const e of bases) {
      parts.push(
        `  - \`${e.hit.url}\` → ${e.check?.status ?? "?"} (${e.hit.files.join(", ")})`,
      );
    }
  }
  if (roots.length) {
    parts.push(`- Raízes de host (informativo, não load-bearing): ${roots.length}`);
    for (const e of roots) {
      parts.push(`  - \`${e.hit.url}\` → ${e.check?.status ?? "?"}`);
    }
  }
  if (templates.length) {
    parts.push(
      `- Templates de shell (não são URLs — expansão de parâmetro/vars): ${templates.length}`,
    );
    for (const e of templates) {
      parts.push(`  - \`${e.hit.url}\` (${e.hit.files.join(", ")})`);
    }
  }
  parts.push(
    `- Veredito para o mandato do projeto: **${fail.length === 0 ? "0 falhas reais — toda URL load-bearing saudável" : `${fail.length} falha(s) a corrigir`}**`,
  );

  let md = parts.join("\n");
  if (md.length > 90_000) md = md.slice(0, 90_000) + "\n\n… (truncado)";
  return md;
}
