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
