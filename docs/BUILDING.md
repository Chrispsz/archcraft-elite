# BUILDING — o pipeline de build em detalhe

Este documento explica como a ISO é construída, onde o tempo vai e como
diagnosticar uma run que quebrou. É o mapa operacional do
`.github/workflows/build.yml` + `.ci/build.sh`.

## Topologia (v2.1)

| Evento | O que roda | Duração típica |
|---|---|---|
| Push em qualquer branch / PR que toque código | `tests.yml` — suíte de contratos (5 fases; filtro de caminhos — push só de docs não roda CI) | ~1.4 min |
| Tag `v*` | `build.yml` completo: lint → build → verify → verify-install → **suite** → release (a suíte é GATE do release desde v2.10.5) | ~25-35 min (com cache quente) |
| `workflow_dispatch` no build.yml | Mesmo pipeline, sem release (a menos que a ref seja uma tag) | idem |

Regra: **ISO é evento de release**. Push de commit roda o que custa segundos,
não uma ISO de 40 minutos idêntica à anterior.

## Estágios do `.ci/build.sh`

Executados dentro de um container Arch Linux **privilegiado**
(`docker run --privileged` — o pacstrap monta `/proc` no chroot; o job
`container:` normal do Actions não tem permissão de mount).

| # | Estágio | O que faz |
|---|---|---|
| 1 | Preparo | `pacman -Syu` do container + archiso/mkarchcraftiso |
| 2 | Chave CachyOS | keyserver → fallback `curl \| pacman-key --add` (âncora de confiança) |
| 3 | `[elite-local]` | pywal (commit pinado), stub qt5, keyring/mirrorlist |
| 4 | Brave Origin | release oficial 1.98.60, **sha256 dos 3 sources fixados** no PKGBUILD |
| 5 | AUR | pwvucontrol (HEAD + pkgver registrados no log; rebuild pulado em cache hit) |
| 6 | Overlay | `scripts/apply-overlay.sh` sobre o clone fresco do upstream |
| 7 | Preflight | `pacman -Syw` de TODA a closure com `--dbpath` vazio (visão do chroot), 3 rounds, sonda HEAD paralela, gêmeo de mirror, baseline injection + ELITE-BUMP |
| 8 | Seal | repos `file://` + `SigLevel=Never` no pacstrap (mitigado: pacotes são hash-checados contra dbs sig-verificados no preflight) |
| 9 | mkarchcraftiso | squashfs + xorriso + `sha256sums.txt` selado |

## Cache (v2.1)

`actions/cache` persiste `.ci-cache/` entre runs:

- `.ci-cache/pacman` → montado em `/var/cache/pacman/pkg` — os ~2 GB de
  tarballs baixados uma vez, reusados enquanto a lista de pacotes não muda.
- `.ci-cache/elite-local` → montado em `/var/cache/elite-local` — os pacotes
  construídos no build (brave-origin, pwvucontrol) pula download/rebuild
  (−4 a −5 min) via *skip-if-present*.
- Chave: `elite-pkgs-v1-<hash de packages.add/remove/pacman-repos.build.add>`
  com `restore-keys` — mudou a lista, cache novo aproveitando o que serve.
- **Os `.db` NUNCA são cacheados** (lição forense dos runs #17-#19: db velho
  = mirror skew = 118 curl-22). O preflight re-sincroniza a cada run.

Ganho medido/esperado: **−6 a −12 min por build** (34-42 min → ~25-30 min
com cache quente). O `mksquashfs` (19,3 min em 4 vCPU) é o próximo gargalo —
só cai com runner maior (decisão de custo, não implementada).

## Diagnóstico de run quebrada

1. **lint** — shellcheck aponta arquivo e código `SC####`.
2. **build** — o passo *Forense do log* (`scripts/log-forensics.sh`) imprime
   a classe fatal (padrões conhecidos: keyring ausente, mirror skew,
   `contains the '$arch' variable`…). O `build-output.log` completo está no
   log do job.
3. **verify / verify-install** — o veredito imprime cada checagem com
   `✔/✖`; o serial completo vira artifact (`verify-boot-serial`,
   `verify-install-logs`).
4. **release** — GATE 1 (artifact vs. sha256sums) e GATE 2 (re-download dos
   assets) falham VERMELHO se qualquer byte divergir. Sem asset quebrado no
   ar.
5. Auditoria por IA opcional: `gh workflow run agents.yml -f agent=deepseek
   -f task="audite a run X" -f context=ci:<run_id>` (ver docs/AGENTS.md).

## Suíte de contratos (`tests.yml`)

5 fases em cadeia (fase que quebra bloqueia as seguintes):

1. **10-env** — ambiente do container.
2. **20-static** — `bash -n`, shellcheck, YAML dos workflows, units INI,
   presets, sysctl, contratos de texto.
3. **30-unit** — unit tests com mocks (lspci, vercmp, craft-pin, forense).
4. **40-integration** — apply-overlay REAL contra fixture hermética, ciclo
   split→hash→reassemble, firstboot não-dry sob namespace, determinismo
   bit-a-bit, contratos de UI (waybar/labwc/rc.xml).
5. **50-release** — PVD vs. bytes publicados, range requests (caça da
   v1.8.0 truncada; observação-only, precisa de rede).

Custo total no CI: **1.4 min**. Não é o gargalo — o gargalo era construir
ISO em todo push (corrigido na v2.1).
