# DIÁRIO DE AUDITORIA — o cão de guarda do próprio sistema

Tarefa 3 do protocolo (`PROTOCOL.md`). Roda diário 16:00 -03 (depois das
outras duas — audita o que elas fizeram).

Escopo diário:
1. `git log --since="24 hours ago"` em origin/main — cada commit do dia:
   mensagem condiz com o diff? (a classe E33 aplicada aos commits)
2. Suíte GO no estado atual de main (rodar de novo é barato — é a porteira).
3. CI da Suíte em main verde (API autenticada); se vermelha: forense e cura
   (a auditoria é também curandeira — commit "E-auditoria: cura …").
4. Lei da Release Única Viva: `releases/latest` == última tag verde; tags
   inesperadas = ALERTA (trabalho diário não pusha tag — L4).
5. Buracos do próprio sistema: ATUALIZACOES.md e POLIMENTO.md têm entrada
   de HOJE? Cron silenciosa que não rodou é registrada AQUI com hora da
   última entrada — o buraco é fato, e fato se escreve.
6. Dia 1º do mês: auditoria EXTRA do ciclo mensal (tag nova, CI verde,
   release única com assets do [elite-local], brave-origin no pin do dia).

Formato: ver `PROTOCOL.md` (feito/prova/próximo).

## ESTADO INICIAL (antes da 1ª entrada)
- próximo: primeira auditoria pode rodar ANTES das irmãs terem entrado do dia — registre o estado real (diários vazios = crons recém-nascidas), nunca trate nascimento como buraco.
