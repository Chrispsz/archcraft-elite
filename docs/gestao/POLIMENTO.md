# DIÁRIO DE POLIMENTO — o código da casa, um degrau por dia

Tarefa 2 do protocolo (`PROTOCOL.md`). Roda diário 11:00 -03.

Escopo: qualidade do código da overlay (scripts craft-*/elite-*, configs
labwc/waybar/swaync/fuzzel, fragments, CI, suíte). Classe de bug em foco
(lição E33): **comentário que mente sobre o código** — revisar sempre o par
comentário↔comportamento. Também: duplicação, dead code, guards ausentes,
erros engolidos, PT-BR inconsistente no produto ao dono.

REGRAS: um degrau pequeno e provado por dia (polimento ≠ refatoração
gigante); suíte GO antes do push; dia sem melhoria honesta possível =
diário diz e explica por quê.

MÉTRICAS (o dono pediu quantidade de código): toda entrada carrega
`scripts: N · linhas: X → Y` (wc -l somado sobre usr/local/bin antes/depois).

## Rotação (a entrada `próximo` do diário diz onde parou)

| # | Área | Foco conhecido |
|---|------|----------------|
| 1 | craft-dock-gui (1044 l) | maior arquivo da casa; crash-guards (lição v2.1.1) |
| 2 | elite-tune (916 l) | espelhos firstboot↔interativo (E33); comentários mentirosos |
| 3 | craft-drawer / craft-pin / craft-pin-pick | GUIs fuzzel |
| 4 | craft-dump / craft-status | honestidade do diagnóstico |
| 5 | craft-audio-route / craft-wake-guard | PipeWire/WirePlumber |
| 6 | craft-idle / craft-lock | suspend-via-idle (E31) |
| 7 | craft-rollback / craft-sweep | snapper; lei do rollback explícito |
| 8 | craft-install-stage / elite-keyring* | instalação; selos de 24h (E29) |
| 9 | craft-menu / craft-bars / craft-dock / craft-bgapps | menu labwc e barras |
| 10 | craft-logout / craft-power / craft-update / craft-clean | sessão e sistema |
| 11 | labwc rc.xml / menu.xml / skel | i18n PT-BR; teclas |
| 12 | waybar / swaync / fuzzel configs | tema e coesão |
| 13 | fragments (elite-customize.sh) | o maior arquivo do build; heredocs |
| 14 | CI (.ci/build.sh + workflows) | gates; pins; jobs |
| 15 | suíte tests/ | contratos que certificam o sistema |

## ESTADO INICIAL (antes da 1ª entrada)
- próximo: área 1 da rotação (craft-dock-gui — o maior arquivo da casa, 1044 l).

## 2026-11-02 · polimento
- feito: EXECUÇÃO MANUAL a pedido do dono ('roda todos os três agora' ~09:50 -03 — a cron 11:00 segue agendada e pode rodar a área 2 no mesmo dia). Área 1 de 15 — craft-dock-gui (1044 l, o maior arquivo da casa), varredura INTEIRA, caça na ordem do protocolo. CURA E33 ×2 + 1 na suíte: (1) o fragmento '# v2.10.3 — o comutador tem ÍCONE FIXO (o veredito do dono: "o ícone fica' pendia TRUNCADO sobre o def log — descrevia o comutador que a v2.10.8 REMOVEU (resto de cirurgia mal fechada); saiu, e o log() ganhou docstring com a verdade (append-only, teto 1 MiB, OSError engolido de propósito). (2) o docstring do _sync_dynamic jurava 'zero flicker no tick de 3s' — o tick é 1s desde a v2.10.12 e o comentário ficou no passado; acordou. (3) a MENSAGEM do contrato do diff-guard (40-integration.sh) carregava o mesmo '3s' — corrigida junto: a casa inteira fala a verdade ou ninguém fala. Zero mudança de comportamento — só comentário agora verdadeiro.
- prova: py_compile parseia · suíte 2016 peças · 0 falhas · 2 pulos · GO. A 1ª rodada da suíte hoje deu NO-GO por causa do PRÓPRIO mantenedor: o py_compile de conferência nasceu com __pycache__ DENTRO da overlay e a peça 'apply-overlay: __pycache__ registrado no file_permissions (senão 203/EXEC no live)' cravou — a porteira pegou o mantenedor; árvore limpa, re-GO. Lição cravada: rodar python contra a árvore SEMPRE com PYTHONDONTWRITEBYTECODE=1. Métricas: scripts: 32 · linhas: 6352 → 6357 (+5 — a verdade que entra também ocupa linha).
- próximo: área 2 da rotação — elite-tune (916 l, os espelhos firstboot↔interativo: a classe E33 JÁ MOROU lá — guard por exit code do v2.10.24; ler os DOIS ramos lado a lado, caçar espelho dessincronizado e comentário que mente).
