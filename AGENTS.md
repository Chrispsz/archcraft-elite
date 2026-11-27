# CONSTITUIÇÃO OPERACIONAL PERMANENTE — archcraft-elite

> **ESTE ARQUIVO É A LEI SUPREMA DO PROJETO.** Toda sessão futura — mesmo
> após reset de sandbox, clone novo ou máquina nova — DEVE ler este arquivo
> ANTES de qualquer operação e cumpri-lo automaticamente. Nenhum documento
> da casa (incluindo `docs/gestao/PROTOCOL.md`) revoga, rebaixa ou dispensa
> estas leis; em conflito percebido, **este arquivo prevalece** e a
> divergência deve ser registrada e harmonizada no mesmo commit.
>
> **§0 · A LEITURA OBRIGATÓRIA DAS SKILLS (E151):** antes de editar
> QUALQUER código, skin, menu ou pacote deste repo, ler TODOS os arquivos
> `docs/skills/*.md` (a fundação visual e as skills permanentes —
> hierarquia, paleta, CSS GTK4, janelas Wayland, filosofia extrema,
> UI/UX GTK4+Wayland) e aplicar as regras inegociáveis que eles fixam:
> zero `--` dentro de comentário XML em `menu.xml`/`rc.xml`; itens do
> `menu.xml` em texto puro SEM atributo de ícone; botões de janela
> SEMPRE à direita (rc.xml + `gtk-decoration-layout`); zero
> `Co-Authored-By` em commit; zero tag de trabalho (L4). Em conflito
> entre guia e código, a folha mestra viva
> (`crates/elite-core/assets/theme.css`) é a fonte de verdade da pele;
> em conflito entre guia e constituição, a constituição vence.
>
> **Regra de segredos (válida para todas as seções abaixo):** NUNCA escrever
> o valor bruto de nenhum token/credencial dentro deste arquivo ou de
> QUALQUER arquivo rastreado pelo Git — o GitHub Secret Scanning revoga
> tokens expostos em commits e quebra a automação da casa. Os tokens vivem
> SOMENTE nos caminhos persistidos fora do Git, documentados aqui por
> caminho (§1).

---

## §1 · Bootstrap Limpo & Autenticação Persistente

### 1.1 Escada de token sem pedir ao usuário

Sempre buscar a credencial do GitHub nesta ordem ANTES de qualquer
operação remota (fetch, push, API, clone):

1. `/home/z/my-project/.elite-gh-token` — A FONTE PERSISTENTE (1ª via,
   ordem do dono 2026-11-21): o sandbox recicla `/home/z/` mas
   `/home/z/my-project/` sobrevive — este arquivo é a cópia que
   renasce. Se `~/.elite-gh-token` ou `~/.git-credentials` estiverem
   AUSENTES (reciclo detectado), o agente os (re)cria AQUI
   automaticamente antes de qualquer operação: `cp` para
   `~/.elite-gh-token` (`chmod 600`) e grava
   `https://USUARIO:TOKEN@github.com` em `~/.git-credentials`
   (`chmod 600`, com `git config --global credential.helper store`),
   sem nunca imprimir o valor;
2. `~/.elite-gh-token` (arquivo com `chmod 600` — cópia sobrevivente fora
   do repo);
3. `~/.git-credentials` (formato `https://USUARIO:TOKEN@github.com`,
   `chmod 600`, alimentado por `git config --global credential.helper
   store`);
4. Variáveis de ambiente (`GH_TOKEN` / `GITHUB_TOKEN`) ou `gh auth token`.

Se NENHUMA via funcionar: relatório honesto de bloqueio ao dono — nunca
inventar resultado, nunca pedir credencial em texto exposto (L6/L3 da casa
continuam valendo: toda chamada de API autenticada, honestidade absoluta).

### 1.2 Repositório íntegro

- **Corrupção de `.git`** (fetch morrendo em `Failed to checksum
  …/tmp_pack_*`, index-pack abortado) ou **`mv` cross-filesystem
  interrompido** (árvore parcial + `index.lock` órfão): remover o
  diretório quebrado e executar `git clone` LIMPO **diretamente no destino
  final** usando o token persistido — nunca `mv` de repo git entre
  filesystems em tarefa cron (lição provada em 2026-11-20: a árvore parcial
  diverge 138 arquivos do índice e o `reset --hard` cego a agrava).
- **Nunca rodar `git reset --hard` cego:** inspecionar `git status` e
  `git diff` ANTES. Herdeiro encontrado na árvore é julgado, provado e
  commitado (ou descartado com voz) — nunca apagado sem perícia
  (jurisprudência da auditoria 2026-11-20).
- Remote do repo permanece limpo (`https://github.com/Chrispsz/archcraft-elite.git`,
  sem token embutido na URL) — a credencial vem da escada 1.1.

---

## §2 · Execução Incremental Anti-Timeout (Zero Perda de Progresso)

- **Proibido acumular trabalho grande sem push:** o ambiente de execução
  tem limite de tempo e pode resetar em raciocínio silencioso longo ou com
  muitos arquivos acumulados. Trabalho sem push é trabalho que pode
  desaparecer.
- **Ciclo atômico obrigatório:** qualquer demanda com mais de 2
  blocos/arquivos é dividida em etapas pequenas e independentes. Ao
  concluir **cada etapa**:
  1. validação rápida da etapa (`bash -n` / `shellcheck` / `py_compile` /
     teste unitário da peça);
  2. `git add` → `git commit` → `git push origin main` imediatamente (a
     regra do dono 2026-11-21: commit + push ao final de CADA etapa —
     sempre com a suíte porteira GO quando a lei L2 da casa
     exigir);
  3. só então avançar para a etapa seguinte.
- **Validação prática em vez de especulação:** não gastar minutos em
  raciocínio abstrato tentando prever erros de sintaxe ou regex — escrever
  o código, executar os testes no terminal e corrigir pelo output REAL.
  Adivinhação não é prova; terminal é prova.

---

## §3 · Regra de Ouro de Entrega: Nenhuma Tarefa Termina Localmente

- **Commit local ≠ Entrega:** uma tarefa ou correção NUNCA é considerada
  concluída enquanto estiver apenas no workspace local. O produto da casa
  é o que o rig do dono recebe pelo canal.
- **Pipeline obrigatório de release** — sempre que houver alteração de
  código/configuração que afete o sistema instalado:
  1. incrementar o `pkgrel` do `elite-system` (lei E41: bump no MESMO
     commit do conteúdo, âncora viva refrescada);
  2. rodar o portão completo de qualidade: `shellcheck 0.11.0` com **0
     avisos** nos scripts da casa + validação de sintaxe (`bash -n`,
     parser do XML quando houver) + suíte completa de testes com **0
     falhas** (veredicto GO);
  3. `git push` para `main` (nunca tag — L4: tag é exclusiva do ciclo
     mensal);
  4. consultar a API do GitHub Actions ATÉ confirmar que os workflows de
     build/publicação concluíram com **`success`** (verdes) e que o novo
     `.pkg.tar.zst` está publicado no índice do repositório `elite-local`
     pronto para `sudo pacman -Syu`. CI vermelha = entrega inacabada: a
     cura é imediata (ou nomeada com run id para a irmã das 16:00 assumir
     — réu escondido é proibido).
- Mudança de papel/documentação (diários, constituições, comentários) não
  bumpa `pkgrel` — jurisprudência E114/E41: bump só com conteúdo de
  sistema mudando.

---

## §4 · Zero Comandos Manuais & Migração Autônoma (`post_upgrade`)

- **O usuário final nunca roda comandos manuais de pós-instalação:** toda
  correção em `/etc`, regras Polkit, systemd units (enable/start/wants),
  parâmetros de kernel/sysctl, remoção/adoção de Flatpaks ou sincronização
  de dotfiles (`~/.config` via `craft-rice` + `labwc --reconfigure`) DEVE
  ser executada automaticamente durante o `pacman -Syu`, através do
  `post_upgrade()` no `elite-system.install` / hooks de pós-transação —
  sem depender do `firstboot-done` (que só roda na instalação inicial). O
  rig já instalado tem de RECEBER a cura pela atualização, não consultá-la
  num manual.
- **Idempotência obrigatória:** toda rotina do `post_upgrade()` deve poder
  rodar MÚLTIPLAS vezes com segurança — sem duplicar linhas, sem quebrar
  configuração do usuário, sem reboot forçado desnecessário (avisar com
  voz clara APENAS quando kernel/drivers mudarem e o boot novo for
  preciso).
- A suíte contrata isso: peça nova de migração entra com teste de
  idempotência (rodar 2× = mesmo estado final).

---

## §5 · Princípios de Arquitetura do `archcraft-elite`

- **Boot instantâneo e zero auto-update no boot:** NUNCA habilitar
  `pacman -Sy`/`-Syu` automático no boot ou silencioso em background
  (gargalo de I/O, `db.lck` travado, partial upgrades, dessincronização de
  módulos do kernel). Atualização é 100% sob demanda via `elite-update` /
  `craft-update`, com o dono no comando.
- **Zero polling desnecessário:** preferir eventos, sockets, sinais
  (`SIGRTMIN+N`), `flock` de instância única e built-ins do shell em vez
  de loops com `pgrep`/`ps` a cada segundo; leitura direta de `/proc` e
  `/sys` quando o dado já mora lá. Idle CPU da sessão é dívida moral.
- **Higiene visual e de sistema:** ícones Papirus consistentes em GTK e Qt
  (`qt6ct`), menus sem nomes crus de interface de hardware (`enp7s0`/
  `wlan0` — rótulos humanos), ausência de apps redundantes e autorização
  Polkit limpa para o grupo `wheel` (pt-br em toda a face do produto, L10
  da casa).

---

## §6 · Formato do Relatório Final

Ao encerrar QUALQUER entrega, apresentar objetivamente:

1. **Hashes dos commits** enviados ao GitHub (`origin/main`);
2. **Versão/release publicada** (`pkgrel` — ou a justificativa E41 de não
   bump);
3. **Status confirmado dos workflows** do GitHub Actions (run id +
   conclusão);
4. **Checklist curto de validação prática** para o usuário confirmar após
   `sudo pacman -Syu` (o que ele deve VER/FAZER no rig — nunca passo
   manual de pós-instalação; o checklist confirma, não conserta).

### §6.1 · A LEI DO COMMIT PURO (1.0-93 — proibição absoluta)

**NENHUM commit do repo carrega linha `Co-Authored-By:`** — o autor do
commit é o mantenedor da casa, ponto final: trailer de co-autoria
enterrado em mensagem de commit é ruído de ferramenta que NÃO faz parte
da autoria real e polui o `git log` que a auditoria E33 lê (a
comparação mensagem×diff fica mais difícil com metadados de agente no
meio). A suíte porteira CONTRATA esta lei (`tests/phases/20-estatica.sh`:
o grep nos N commits recentes; commit com o trailer = porteira VERMELHA
antes do push). A cura de um commit contaminado: `git commit --amend`
retirando a linha (antes do push; depois disso, o commit fica — nunca
force push, a lei L4).

---

---

## §7 · Filosofia 2.0 — A Reconstrução Nativa (diretriz do dono)

A fase 2.0 do projeto é uma RECONSTRUÇÃO, não uma tradução. As leis
desta seção operam dentro de §1–§6; em conflito, a harmonização é
registrada no mesmo commit.

- **Reprojetar, nunca clonar o legado:** o código antigo é estudado para
  compreender o domínio (kernel, sysctl, udev, GPU sysfs, wake-guard) e
  NUNCA portado linha a linha. A camada de interface, IPC e orquestração
  é reescrita do zero em Rust.
- **Sem fallback para o passado:** `waybar`, scripts Python de UI
  (`craft-audio`, `craft-bars`), wrappers de `fuzzel` fingindo ser painel
  de controle e `pkill` de sincronização morrem da árvore, do `PKGBUILD`
  e da suíte quando os módulos nativos assumem. O enterro tem SUBSTITUTO
  vivo antes da pá — nada é apagado sem destino (a faxina é segura ou
  não sai).
- **100% Rust na camada própria:** os binários da casa compilam com
  `LTO=fat + strip + opt-level=3`, orientados a eventos reais (epoll,
  procfs, sysfs, D-Bus `zbus`, protocolos Wayland nativos) — zero polling
  pesado, zero colcha de retalhos.
- **Workspace unificado (`crates/`):** `elite-core` é a fundação — os
  contratos tipados do estado, o protocolo do bus.sock
  (`/run/user/$UID/elite/bus.sock`) e a persistência atômica
  (`~/.config/elite/`); `elite-daemon` é o orquestrador único da sessão;
  `craft-bar-rs` e `craft-dock-rs` são as superfícies GTK4+
  layer-shell; `craft-dump-rs` é a telemetria v2.
- **Design System ELITE:** UMA folha mestra (`crates/elite-core/assets/
  theme.css`) define a identidade (paleta, raios, estados, tipografia) e
  viaja EMBUTIDA nos binários; `swaync` e `nwg-drawer` recebem a mesma
  paleta pelos skins do pacote. Nenhum componente pode parecer um bloco
  desconexo.
- **Não reinventar o que o mundo já fez bem:** Rede = `iwgtk` +
  `nm-connection-editor`; Bluetooth = `blueman`; Áudio (mixer) =
  `pwvucontrol`; Notificações = `swaync`; Lojas/Flatpaks = `Bazaar` +
  `Warehouse` + `Gear Lever`; Ventoinhas = `coolercontrol`. Nossa UI dá o
  estado em tempo real, a ação de 1 clique e a porta para a tela certa.
- **Enraizamento no compositor e no kernel:** `wlr-layer-shell`,
  `zwlr-foreign-toplevel-management-v1`, D-Bus (`logind`, NetworkManager,
  BlueZ, PipeWire, MPRIS) e `sysfs`/`procfs` — sem intermediários frágeis.
- **Tuning de baixo nível é SAGRADO e PRESERVADO:** `/etc/default/grub`,
  `sysctl.d`, `modprobe.d`, `udev/rules.d` e GPU `sysfs` da casa não são
  substituídos por templates genéricos — só se SOMA (`mitigations=off`,
  `nowatchdog`) quando a diretriz pede, sempre idempotente e com voz no
  papel.
- **Suíte real em 3 níveis:** (1) `cargo test --workspace` — os contratos
  reais do núcleo (IPC, persistência, parsers); (2) `tests/session_smoke`
  — a sessão viva (zero legado, família nativa conectada, serviços
  críticos, sink analógico, boot params); (3) `iso/test-iso-qemu` — a ISO
  bootada no QEMU com extração do dump. A suíte antiga de mocks morre
  quando os níveis reais cobrem os contratos essenciais — o gate (L2)
  NUNCA fica sem porteira.

---

## §8 · Dose 1.0-106 — o registro vivo (a matriz de hardware e o sono)

- **A matriz de hardware é contrato vivo:** `tests/hardware/run.sh` +
  a fase 55 da porteira (`tests/phases/55-hardware.sh`) simulam os 6
  perfis reais (2 de entrada, 2 intermediários, 2 high-end — um deles é
  o rig do dono) num sandbox de root falso (`unshare -rm` + bind mounts
  + stubs no PATH; seams da casa `ELITE_ACPI_WAKEUP`/`ELITE_RANDR`) e
  validam BYTE A BYTE, dose 2× idempotente, o que cada hardware recebe:
  `mem_sleep_default=deep` só quando o `/sys/power/mem_sleep` lista,
  snapper/grub-btrfsd só no btrfs (ext4 colhe), `elite-sensors.conf`
  só com o chip que PROVOU hwmon, `coolercontrol` com
  `liquidctl_integration = false` sem o pacote, e o recover de displays
  por saída com o modo persistido. O mapa canônico:
  `docs/ARCHITECTURE.md`.
- **O sono S3:** `mem_sleep_default=deep` (hardware-aware, 1×) +
  `elite-acpi-wakeup` (desarma os gatilhos espúrios
  GPP0/GPP8/XHC0/XHC1/XHCI/PTXH em `/proc/acpi/wakeup` — idempotente;
  a mão do dono é a política do `craft-wake-guard`) + `craft-display
  recover` em 4 gatilhos (daemon, `craft-lock`, hook de sistema,
  `craft-vigil`) com guard de 10s = um dono por veredito.
- **O `swaync` morreu por ordem do dono** (dispensou central de
  notificações e DND): fora do `packages.add`, fora do skel, fora do
  build — o relógio é hora/calendário. **NUNCA volta à árvore**
  (âncoras de ausência na porteira guardam o túmulo).
- **O seletor de rede e o `craft-pick`:** o esquerdo do módulo de rede
  abre o seletor nativo GTK4 (toggles Wi-Fi/Ethernet + redes ao alcance
  + conexão em 1 clique pelo `nmcli`), o meio abre o
  `nm-connection-editor`, o direito liga/desliga a conexão ativa; menus
  de escolha da casa são `craft-pick` (a gramática dmenu em GTK4 na
  folha mestra).
- **O tema SDDM `elite` é 100% pt_BR** (`/usr/share/sddm/themes/elite`,
  QML puro, zero binário no repo), fixado por
  `/etc/sddm.conf.d/elite.conf` (`Current=elite` +
  `CursorTheme=Bibata`).

*Casa archcraft-elite · Constituição ratificada pelo dono em 2026-11-20 ·
Fonte da verdade dos dados: `docs/gestao/PROTOCOL.md` (protocolo das 4
tarefas) · Memória que sobrevive ao reset: os diários de `docs/gestao/` ·
Supremacia: este arquivo.*
