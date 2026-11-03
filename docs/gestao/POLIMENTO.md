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
- CORREÇÃO (14:5x, mesma entrada do dia): as métricas acima foram medidas COM o __pycache__ que o py_compile de conferência derramou na pasta (o mesmo que a suíte flagrou como NO-GO) — o find contou o .pyc (1 arquivo, 215 "linhas" de bytecode). NÚMEROS REAIS: scripts: 31 · linhas: 6137 → 6142 (+5). O erro de medição é da mesma família do E33 (o resultado não é o que parece) — e a prova de que a porteira funciona é que ela flagrou o contaminante antes de qualquer push; a correção do NÚMERO fica escrita aqui porque registro falso, mesmo inocente, não fica.

## 2026-11-02 · polimento (2ª entrada — E37: o plano da auditoria arquitetural começou a ser executado)
- feito: o dono mandou 'vai ainda além no que faltou' — em vez de só caçar E33 na área 2, EXECUTOU o item nº 1 do plano de reestruturação do ARQUITETURA.md (fatoração dos espelhos do elite-tune) + o nº 16 (epílogo honesto), os dois que o próprio plano casa juntos. OS 4 PARES GÊMEOS firstboot↔interativo viraram FUNÇÃO ÚNICA chamada PELOS DOIS modos: apply_grub_tokens (tokens de kernel + grub-mkconfig — o plano do kernel nascia em dois lugares), write_elite_sysctl (a lei do sysctl — o firstboot tinha cópia com cabeçalho próprio 'restaurado pelo firstboot v2.10.14'), ensure_bbr (iso|graft — e a limpeza do sysctl no firstboot ganhou o guard de DRY: o sed/rm rodavam até seco, violando a doutrina 'dry é seco' v4.4) e ensure_btrfs_stack (findmnt + guard do snapper por SAÍDA + timer E32 — o 'MESMO GUARD' do comentário E33 deixou de ser promessa: é a MESMA FUNÇÃO; o fallback sem-snapper do firstboot passa a valer no interativo como rede de segurança do [6] offline). Nº 16 — o 'CONCLUÍDO' incondicional do modo interativo MORREU: as instalações decisivas ([1] kernel+booster, [4] AMD/NVIDIA, [5] zram-generator, [6] stack de jogo) passam por pacman_s com rc REAL alimentando FAILURES; falha vira 'PENDÊNCIA: …' anunciada NA HORA e o epílogo diz 'CONCLUÍDO COM N PENDÊNCIA(S)' com a lista e o caminho (rode de novo — seções idempotentes). Brinde de coerência: o pacman_s ganhou o eco do plano no modo REAL — o rc real não pode custar a linha '  $ pacman …' (contrato visual da casa).
- prova: espelho cravado como CONTAGEM na suíte (bloco E37 do 20-static): def 1× / chamada 2× para as 4 funções + zero cópia viva (nowatchdog, vm.swappiness e grub-mkconfig em 1 ocorrência — eram 2; quem divergir o espelho de novo, a porteira aponta). Cadeia D (interativo dry, BBR on/off) e cadeia F (firstboot real, bbr on/off) da 40-integration rodaram o refatorado inteiro. Suíte: 2073 peças · 0 falhas · 2 pulos · GO NA 1ª RODADA (15 contratos novos: 8 do loop de funções + 3 de cópia morta + 4 do epílogo honesto). bash -n OK. Métricas: scripts: 32 · linhas: 6489 → 6539 (+50 — a função única custa o cabeçalho, paga as cópias).
- próximo: o plano do ARQUITETURA.md segue vivo — nº 2 (guards da suíte index-driven via git ls-files -s: o fim do NO-GO local que o sandbox finge e o CI desmente) é o próximo da fila; nº 3 (contratos de docs: todo craft-* citado no README existe) e nº 9 (craft-logout wrapper do craft-power, −80 linhas de duplicação) em seguida.

## 2026-11-03 · polimento
- feito: área declarada pelo 'próximo' da véspera — o item nº 2 do plano do ARQUITETURA.md (guards da suíte INDEX-DRIVEN). Contexto do dia, cravado porque é fato de concorrência: ANTES deste degrau, a rodada E38 (auditoria de eficiência, a pergunta do dono) entrou em main pelo agente irmão (221e759) — este agente detectou a árvore sendo escrita em paralelo (mtimes 13:03, 5→20 arquivos) e NÃO TOCOU NELA até o push: corrida zero, nenhum byte pisado, o polimento de hoje nasceu POR CIMA do E38. Cura E39: o helper index_exec (modo 100755 lido do `git ls-files -s`, consequência e receita de cura na mensagem de falha) e os 4 guardas que AINDA liam o FILESYSTEM convertidos — log-forensics.sh (v1.5.2), craft-wake-guard, elite-sleep-report e cura-viva.sh (todos v2.10.11). A da cura-viva era a mais doente: a peça JURAVA o modo do git (a mensagem citava update-index e core.fileMode) e o código lia o fs — E33 de guarda, não de comentário. Neste sandbox tudo nasce rwxrwxrwx: os 4 passavam local de graça e o réu real (o modo que o checkout do CI e o squashfs herdam) nunca era auditado — o 'NO-GO local que o sandbox finge e o CI desmente' da classe E35.1 fica extinto por construção. O fallback fs do loop geral fica SÓ para caminho não-rastreado, como o comentário do bloco já declarava.
- prova: bash -n OK · suíte 2109 peças · 0 falhas · 1 pulo · GO (fase 5 COM rede hoje: 17 peças de release no lugar do pulo — 2092+17 = 2109, contagem consistente, a cura não alterou o número de peças). Os 4 réus conferidos no index ANTES da cura: todos 100755 — a porta fica trancada sem prender falso réu. Métricas: scripts: 32 · linhas: 6656 → 6656 (±0 — o degrau mora na suíte, os bins não mudaram).
- próximo: o plano do ARQUITETURA.md segue — nº 3 (contratos de docs: todo craft-*/elite-* citado no README/SCRIPTS.md existe em usr/local/bin; rollback citado bate com packages.remove; contrato de contagem) é o próximo da fila; a fila do EFICIENCIA.md (systemd --user units, awk do bgapps, journald live, sshd, probe timer, resolved, copytoram, ASPM) herda os próximos polimentos de eficiência.
- ADENDO (mesma entrada, ~10:50 -03): o CI DESMENTIU o degrau — run 41643776977 (6653565) vermelho, e a forense descobriu que a ficção ia MAIS FUNDO que o plano admitia. Razão cravada no log (linhas 451-463): o `actions/checkout@v5` adiciona o workspace ao safe.directory numa config global TEMPORÁRIA (GIT_CONFIG_GLOBAL do passo dele — morre com o passo). No passo seguinte, o git do container archlinux RECUSA o repo (dubious ownership) e `git ls-files -s` sai VAZIO (2>/dev/null engolia o 'fatal') — ou seja, o guard 'index-driven' do E35.1 NUNCA leu o index no CI: caía SEMPRE no fallback do filesystem (a prova retroativa: a peça do incidente 716ee1e reclamou 'sem bit de execução' — frase do ramo FALLBACK; se o index tivesse sido lido, a reclamação seria 'modo do index é 100644'). Os 4 conversos E39, SEM fallback, tombaram com mode vazio — e a mensagem customizada da cura-viva ('core.fileMode=false…') mascarou o diagnóstico: causa errada escrita por mim, corrigida no mesmo dia. CURAS: (1) tests.yml ganha o passo 'git confia no workspace' (safe.directory PERMANENTE no container — o passo da suíte lê o index de verdade; o comentário do passo carrega a forense inteira); (2) a mensagem da cura-viva deixa de nomear causa errada ('0644 no index OU git não operou no repo'). Com isso o item nº 2 do plano fica VERDADEIRO nos dois mundos: local (fs mente, index manda) e CI (git vivo, index lido — o fallback do fs deixa de ser a rota de fato). Suíte local: 2109 · 0 · 1 · GO (YAML validado com yaml.safe_load). CI: re-run no push do adendo.
