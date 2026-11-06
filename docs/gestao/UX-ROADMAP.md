# UX & PRODUTIVIDADE — o mapa da casa (E66)

Fonte: ordem do dono (06/nov) — "pensa como melhorar toda a UX e produtividade
do sistema" — e a pergunta pendente que a originou: "tudo perfeito? nosso
código é cirúrgico? os craft-* funcionam e têm utilidade real?".

Método: auditoria da superfície com prova (lei E33) antes de qualquer plano —
grep de consumidores de cada comando em configs live (rc.xml, menu.xml,
waybar, Thunar), units systemd, cadeia interna entre scripts e docs.

---

## 1 · O que a auditoria PROVOU (o balanço honesto)

### Forte (a manter — é o diferencial da casa)

1. **Zero comando morto.** Os 29 `craft-*` + `elite-tune` + `elite-status`
   têm cadeia viva de invocação: keybinding/menu/waybar/Thunar, unit
   systemd, ou chamada por outro script (ex.: `craft-audio-route` nasce no
   `craft-bars`; `craft-vigil` é armado pelo `craft-lock`; `craft-rice`
   desperta com a sessão). A pergunta "todos têm utilidade?" = SIM,
   verificada um a um por grep — nada para podar hoje.
2. **Superfície de acesso densa e coesa (Desktop v2):** 31 atalhos de
   teclado (22 W/C-A + 9 XF86 de mídia/brilho) · menu de desktop com 13
   itens · menu bar waybar com ações reais em cada módulo (drawer, bgapps,
   bateria, rede, áudio, mic) · dock nativa com toggle/reload · Launchpad ·
   Thunar com comprimir/extrair · W-v clipboard histórico · swaync central
   no relógio.
3. **UX de erro cuidada:** a cinta v2.9.0 (recusa NUNCA é silêncio: log +
   toast), guards no autostart, supervisor `craft-bars` que relança em ≤5s
   com stderr no `bars.log`, gramática de saída 0/1/143.
4. **Produtividade silenciosa de qualidade:** roteamento de áudio automático
   (E30), lock/DPMS/suspend ajustáveis sem relogin (craft-idle), automount
   com notificação, self-healing de keyring, doses de update com prova de
   rede e adiamento honesto (E64).

### As 3 lacunas (a prova da cura)

1. **DESCOBERTA (a maior).** O dono não tem como descobrir os comandos
   DENTRO do sistema:
   - 20 de 31 comandos sem `--help`/`uso:` (audio-route, bars, bat, clean,
     connect, dock-gui, drawer, dump, fix-keys, hello, idle, keyring-wait,
     lock, logout, menu-dismiss, power, rice, update, vigil, elite-status);
   - o `menu.xml` tem **0** itens de ajuda (grep "ajuda|help" = 0);
   - o `docs/SCRIPTS.md` **não viaja** no pacote nem na ISO (nada no
     `.ci/build.sh` nem no airootfs o inclui) — o mapa dos comandos só
     existe no repositório;
   - nenhum `craft-help` ou centro de ajuda existe.
   O código é cirúrgico, mas a cirurgia é invisível de dentro do sistema.
2. **RITMO DE UPDATE INVISÍVEL.** A dose ao ligar roda (timer 3min + re-arma
   1h, E64), mas quando a rede falha o dia fica sem cura em silêncio honesto
   — e não existe sinal visual de "tem atualização pendente" nem porta
   barata de checagem (`craft-update --check` não existe; o script é de
   linha reta).
3. **ONBOARDING RASO.** O `craft-hello` (binding dedicado no rc.xml) é um
   fastfetch — mostra kernel/CPU/pkgs e não apresenta o sistema: nem
   atalhos, nem comandos, nem estado Elite (última dose, vigil, snapshots).

---

## 2 · O plano (fases em degraus pequenos — um por dia, provado pela suíte)

### FASE A — DESCOBERTA (maior ROI, menor risco)

- **A1 · `craft-help` — o mapa vivo da casa.** Menu fuzzel com todos os
  comandos, uma linha PT-BR cada + onde alcançar (tecla/menu/barra/dock);
  Enter descreve; comandos seguros executam. Item "Ajuda…" no menu do
  desktop (primeiro do bloco de sistema). Novo bin no pacote → MANIFEST
  dinâmico + pkgrel bump (lei E41) + contratos na suíte.
- **A2 · `--help` universal.** Os 20 sem ajuda ganham `uso:` honesto —
  DEGRAU POR DIA na rotação (áreas 1–15), começando pelos mais tocados:
  power, lock, idle, update, clean, connect, bat.
- **A3 · Cheat sheet de teclas dentro do craft-help** (seção "Teclas": os
  31 atalhos PT-BR — W-x, W-l, W-d, W-S-d, W-v, W-n, C-A-t…). Fim do
  "como eu faço pra…" respondido de memória.

### FASE B — FLUXO DIÁRIO

- **B1 · Sinal de update na barra.** Módulo waybar `custom/updates` com
  `pacman -Qu | wc -l` (zero dependência nova — pacman-contrib NÃO está no
  sistema, provado por grep): ícone discreto quando >0, clique →
  `foot -e craft-update`. Interval 3600s (custo zero em CPU).
- **B2 · Cura do labnag seco** (achado E65 sem cura): o fallback de diálogo
  chama `systemctl suspend` SEM o gate logind/kernel, SEM o lock antes, SEM
  `-i` — porta morta na prática. Cura alinhada ao padrão v2.6.0 do
  craft-power (mesma receita do irmão: gate + lock primeiro + `-i`).
- **B3 · `craft-hello` enriquecido.** 3 linhas de estado Elite abaixo do
  fastfetch: última dose do canal (data/versão), estado do vigil/idle,
  snapshots snapper. O "como está meu sistema?" em 1 tecla.

### FASE C — RITMO (só depois da A assentada)

- **C1 · `craft-update --check`** (rc 0 = em dia, rc 2 = pendente,
  silencioso, sem transação) — a porta barata que o B1 e scripts consomem.
- **C2 · Ação rápida no aviso.** O aviso de dose nova no swaync ganha botão
  "atualizar agora" (a central já é a superfície dos avisos — v2.10.5).

### FASE D — POLIMENTO VISUAL (fila baixa)

- **D1 · Coesão de ícones.** A v2.2 tirou o tema de ícones (leveza radical)
  — lookups caem no fallback GTK. Avaliar tema mínimo OU nomear a escolha
  como decisão consciente no SCRIPTS.md (E33: o que é deliberado não parece
  defeito).
- **D2 · Toasts padronizados.** A cinta v2.9.0 como padrão nos cantos que
  ainda aceitam ação silenciosa.

---

## 3 · Regras do plano (a lei da casa inteira)

- Cada degrau = 1 dia de polimento, suíte GO antes do push, pkgrel bump no
  MESMO commit quando o conteúdo do elite-system muda (lei E41), perícia
  por download no addendum (a etiqueta é conteúdo).
- A fase A É polimento: `--help` universal (A2) e craft-help (A1) passam
  pelas áreas da rotação — a máquina de estados não para, ganhou destino.
- Diretriz do dono toma a frente da fila; o nº 7 do ARQUITETURA
  (deduplicar elite_latest/elite_fetch) volta na sequência.

## 4 · Métricas de sucesso

1. "Descobrir um comando sem sair do sistema" — craft-help no menu (A1/A3).
2. "Tempo entre o aviso de update e a dose" — ≤ 2 cliques (B1/C2).
3. "0 comandos sem `uso:`" (A2) — contável pela suíte (assert por script).
4. Linhas: o mapa é degrau de CURA, não de peso — cada fase carrega
   `scripts: N · linhas: X → Y` no diário, como sempre.
