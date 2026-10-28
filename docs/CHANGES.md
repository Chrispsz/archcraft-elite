# CHANGES — Elite Edition vs. Archcraft upstream

Todo delta é aplicado pelo `scripts/apply-overlay.sh` em cima do clone fresco
do profile oficial. Nada é deletado do upstream — pacotes removidos são
**comentados** no `packages.x86_64`; arquivos Elite são sobrepostos.

## 🗺️ Visão por versão

- **v2.10.7 — O 1º RIG-INSTALL FALOU (dump 0qmq) — as curas de campo**: a
  10.6 foi instalada no rig do dono e o craft-dump v2.0 voltou falando
  (o método v2.0.6 funcionou). Os achados com prova no papel e as curas:
  - **O BOOT DE 30 MINUTOS (o achado pesado)**: o `elite-firstboot` rodava
    `WantedBy=multi-user.target` e segurou o `graphical.target` por
    **30min 9s** — pacman da stack lib32 lento (mirror cdn77 com 404 +
    wifi Intel 7260 empane no meio) até o `TimeoutStartSec=1800` matar o
    serviço. Agora o firstboot corre `After=WantedBy=graphical.target` —
    o desktop sobe primeiro, o tuning termina em background (o mesmo
    trabalho, sem refém).
  - **O GUARD DO SNAPPER MENTIA**: `snapper --no-dbus list-configs` sem
    nenhuma config sai **0 e silencioso** — o `|| create-config` nunca
    armava (rig: snapper 0.13.2 instalado, ZERO configs, `/.snapshots`
    nunca nasceu, `grub-btrfsd` FAILED — o rollback D1 ainda morto por
    lógica, não por gate). A verdade é a SAÍDA: `list-configs | grep -qw
    root` decide.
  - **O Z2 PULAVA O US-INTERNACIONAL**: o guard `KBL != "us"` tratava
    layout `us` como "default, nada a fazer" — mas a VARIANTE `intl` É o
    que precisa viajar (dead keys). Rig: localectl `us + intl` e
    `/etc/environment` SEM XKB — a sessão nasceu us() seca. Escreve se o
    layout ≠ us **OU** a variante existe.
  - **O ACK HONESTO DO DAEMON (craft-toplevel 1.0-2)**: o rig clicou o
    comutador 13× ("menu das janelas aberto"), mandou foco 3× ("foco por
    id"), recebeu ACK de tudo — e NADA na tela. O `OK` do daemon só prova
    que o request saiu (opcodes ✓ contra o XML oficial do wlroots, marshal
    ✓, flush ✓ no loop, labwc ✓ `desktop_focus_view(raise=true)` — o elo
    sem prova é a obediência do compositor). O daemon agora COBRA recibo:
    o `state(activated)` do alvo confirma; state de outra janela ou
    timeout de 2s denuncia — veredito em `toplevel.log` (viaja no dump).
  - **O DUMP v2.0.1 GANHOU AS PROVAS QUE FALTARAM**: `/sys/power/state` +
    `mem_sleep` + `loginctl can-suspend` (o veredito do suspend com prova
    do kernel — o menu disse "não" e o papel não tinha o que julgar),
    journal das units Elite falhadas (`-u elite-firstboot -u grub-btrfsd`
    — o `-p err` afogou o erro do grub-btrfsd), `bluetoothctl show` +
    `lsusb` (lista vazia de BT precisa de réu), fuzzel.ini no papel (a
    linha :35 `ain].exit-on-focus-loss` gritou em TODO menu), toplevel.log
    e host via `uname -n` (o `hostname` não existe em toda ISO — o rig
    estampou "host: ?"). O NUL do termbin morreu no capture (`tr -d
    '\0\n'` — a linha 292 do rig gritou de novo).
  - **O EPÍLOGO É LEI**: `ExecStopPost` na unit registra o
    `SERVICE_RESULT` em sucesso, falha OU timeout-kill (no rig o serviço
    morreu aos 1800s e o log terminou no meio do systemctl, sem história).
    O marker v4.5 (retry por rede/driver) fica de pé.
  - Suíte: 12 contratos novos na fase 4 provando cada cura.

- **v2.10.6 — A RODADA 2: O DONO PEDIU "COM TODO O NOSSO CÓDIGO"** (a
  validação por simulação que nasceu na v2.10.5 virou MÉTODO: 4 domínios
  percorreram os ~12.700 linhas — sessão/dock, energia/manutenção,
  instalação, CI/forense/suíte — 80 cenários, prova file:line para cada
  veredito; as curas que sobreviveram à perícia):
  - **O ANTI-TAMPER QUE REPROVAVA REPO SÃO (o bug funcional provado)**:
    o tamper da cadeia B escrevia 'X' fixo sobre 1 byte aleatório — se o
    byte JÁ fosse 'X' (0x58, ~1/256; flagrado 3/512 na própria auditoria),
    o sha256 passava, a peça falhava e a suíte INTEIRA ia NO-GO. Agora o
    tamper escreve o COMPLEMENTO do byte lido (mudança matemática
    garantida).
  - **O GATE DO BTRFS QUE NUNCA RODAVA**: 'mount | grep -q " on / btrfs"'
    NUNCA casava (o util-linux imprime 'on / type btrfs') — snapper,
    /.snapshots e grub-btrfsd não nasciam em NENHUMA instalação, btrfs
    inclusive: o rollback morria em silêncio. findmnt decide (o mesmo
    idioma do install-stage), nos DOIS caminhos (firstboot E interativo).
  - **O OS-PROBER QUE NINGUÉM LIGAVA**: o GRUB 2.12+ desliga por default
    ('#GRUB_DISABLE_OS_PROBER=false' comentado) e nada descomentava — o
    Windows/2º SO nunca entrava no menu do disco instalado. O stage M1.1
    liga o knob (valor persiste no alvo).
  - **O HÍBRIDO QUE PERDIA A dGPU**: iGPU intel desenhava e o
    gpu_cleanup_foreign REMOVIA o driver nvidia inteiro — a RTX/GTX do
    Optimus ficava inútil. HYBRID=1 preserva o stack (offload/PRIME) e
    reconcilia só o que é estranho de verdade; nvidia-utils garantido.
  - **A MORTE NO MEIO DO CLIQUE**: ACT falhou + conexão morta = o clique
    na janela VIVA lançava DUPLICADO (snapshot velho). Degrada ao fallback
    (wlrctl tenta focar; só abre se TODAS as formas falharem) —
    _fallback_focus é o lugar único da lei v2.10.
  - **A FRONTEIRA DA CONTENÇÃO**: 'foot' ⊂ 'footclient' casava e o MEIO
    no pin do foot encerrava janelas do footclient (o fallback wlrctl,
    exato, mudava de mão e abria outro). _near_match: fronteira = o char
    colado não é letra/número — brave⊂brave-browser segue, footclient
    segue foot. A MESMA lei chega ao índice de .desktops: o botão dinâmico
    do Brave (comm 'brave' ≠ chave 'brave-browser') nasce.
  - **AS ÂNCORAS DA SUPERVISÃO**: 'pgrep -f craft-toplevel' somava o
    EDITOR com o fonte aberto — supervisão cega e USR1 de toggle no vim.
    toplevel/swayidle por comm (-x), dock por cmdline ANCORADA (bars,
    probe e craft-dock).
  - **O IDLE ENTRA NA SUPERVISÃO**: swayidle lançado UMA vez no autostart
    morria calado e lock/DPMS/suspend ficavam fora para sempre. craft-bars
    vigia (≤5s, ausência intencional silenciosa quando "Nunca"); o spawn
    do autostart saiu (um só lançador — a corrida fork/exec que se
    pkillava deixaria 'SAIU exit=143' no gate).
  - **AUTORIZAÇÃO ≠ SENHA ERRADA**: 'Not authorized to control networking'
    (polkit) casava '*auth*' e o perfil BOM era apagado. Ramo próprio SEM
    delete + aviso honesto.
  - **O 2 DO MENU É TOGGLE**: o rollback era o último irmão que tratava
    ec=2 como falha (toast falso). E o craft-clean morria calado com EOF
    no prompt (read || ans='').
  - **O AUTOLOGIN DO LIVE NÃO ENTRA NO INSTALADO**: o drop-in com
    User=liveuser sobrevivia ao unpackfs — o firstboot remove o bloco
    [Autologin]. E o TECLADO DO CALAMARES chega à sessão: XKB_DEFAULT_
    LAYOUT no /etc/environment (ABNT2 no desktop inteiro, não só no
    greeter).
  - **O POLKIT COMPLETO**: a variante suspend-multiple-sessions faltava
    (as demais tinham) — suspend com 2ª sessão pedia senha.
  - **O ALVO REAL DO LOG DO CALAMARES**: o mountPoint é um mkdtemp
    'calamares-root-*' — /mnt era código morto; o glob entra e o doc diz
    por que a promessa v2.0 se cumpre (preservefiles upstream).
  - **W-Tab EXPLÍCITO**: o <default/> do labwc podia trazer de volta a
    lista de janelas aposentada pela porta dos fundos — bind declarado
    (None) e a lista mora só na dock.
  - **O RUÍDO DO AUR**: o tail da tentativa 1 falhada não mancha mais o
    log que a tentativa 2 cura (só a falha FINAL imprime).
  - **A FORENSE COM CIÊNCIA COMPLETA**: 4 regras FATAIS incondicionais
    ('is marginally trusted', 'conflicting dependencies', 'failed to
    install packages', 'No space left on device') ganharam fixture —
    até a Rodada 2 eram cegas nos dois sentidos — e o ramo downloader/
    'cache completo' (SEM baseline) foi exercitado pela 1ª vez. qemu-boot-
    test alinha o gate local ao CI (sleep 15 + FUZZEL_BIN/INI).
  - **O TOKEN QUE DORMIA NO CONTAINER**: checkout com
    persist-credentials: false (o .git entrava num container
    --privileged) e tests.yml com permissions: contents: read.
  - Suíte: contratos das curas + fixtures novas (o placar exato na run).
  - **O DUMP v2.0 — O RIG FALA COMPLETO**: o craft-dump ("btop completão")
    ABRE com o VEREDITO RÁPIDO (probe da sessão + units falhados + disco
    raiz) e ganhou a tabela REAL de janelas do daemon toplevel (o socket
    que a dock fala: app_id/flags/rank MRU/título — o teste do btop chega
    com prova), pins vs dinâmicos, driver EM USO da GPU (lspci -k — a cura
    D5 com evidência), findmnt / (lição D1), história de boots,
    temperaturas sem lm_sensors, layout real de monitores (wlr-randr entra
    na ISO), rede (nmcli — a cura B2 com evidência), áudio (wpctl),
    idle.conf (a escolha do dono viaja) e XKB (o ABNT2 com prova). O
    --upload ganhou timeout (rede morta devolve o terminal em 15s) e a
    contagem da dock no dump usa a âncora da Rodada 2 (o comm é python3).
- **v2.10.5 — A AUDITORIA QUE CRUZOU A ILHA** (o dono pediu: "faz várias
  simulações de uso e olha como o código reage — quero validação real que
  a distro é bem pensada e estável, tudo da melhor forma"). 5 personas
  percorreram os ~7.000 linhas de código (sessão, teclado, energia,
  manutenção, instalação, CI); 40+ achados períciados um a um; as curas
  que sobreviveram à prova:
  - **O TERMINAL FALAVA OUTRA LÍNGUA**: foot.ini `shell = /bin/sh -l`
    abria bash-POSIX SEM o .zshrc — starship, autosuggestion, aliases:
    tudo morto, silenciosamente, no terminal principal da distro. O
    shell é o zsh (`/usr/bin/zsh -l`).
  - **A CONTRADIÇÃO OPTIMUS**: install-stage decide GPU por
    /sys/class/drm (vê o dGPU → MODULES=(nvidia …)) e o tune decide pela
    1ª linha lspci (híbrido → intel → REMOVE o nvidia) — o MODULES
    órfão matava o PRÓXIMO `mkinitcpio -P` ("module not found") e o
    boot ia pro emergency shell. gpu_cleanup_foreign agora RECONCILIA
    o initramfs + apaga modprobe.d/00-elite-nvidia.conf órfão.
  - **A BATERIA QUE RESPONDE**: craft-bat morria CALADO em máquina sem
    bateria (set -e + grep rc=1 — a mensagem amigável era código morto,
    provado em sandbox); upower nem estava na ISO. Reescrito em
    /sys/class/power_supply puro + módulo battery na waybar (clique =
    resumo) — o notebook entrou na interface.
  - **A SUÍTE NUNCA VIA UMA TAG**: push de v* não disparava a suíte e o
    publish-artifact publicava a ISO de QUALQUER run (verify vermelho?
    tanto faz). Agora: job `suite` é GATE `needs` do release, tests.yml
    ouve tags, e o publish GATEia a conclusão do run de origem.
  - **O FORENSE APRENDEU A CURA DO #116 INTEIRA**: "failed to
    synchronize" de round transiente (que o preflight cura com
    "cache completo") era FATAL incondicional — falso positivo da
    mesma janela do #116. Condicional com a mesma prova do downloader;
    sem cura segue FATAL. E o makepkg do AUR não mais mancha o log com
    o ruído da tentativa 1 ("target not found" curado na 2).
  - **O MENU QUE PRECISA DE SENHA**: rede salva com senha trocada
    mascarava "rede fora de alcance" e a senha NUNCA era pedida de
    novo — o stderr do nmcli agora é diagnóstico: credencial recusada
    apaga o perfil e PERGUNTA (léxico EN+pt).
  - **O SUSPEND OPT-IN QUE MORRIA NO MENU**: trocar o tempo de lock
    pelo menu regravava idle.conf SEM SUSPEND_MIN — suspendia nunca
    mais, silenciosamente. Viaja no reescrito (2 caminhos) + valores
    lixo no conf não matam o daemon + falha de menu ganha notify.
  - **O SUPERVISOR SEM IDENTIDADE**: craft-bars sem flock = 2
    supervisores após relogin apertado (barra duplicada); a corrida
    fork/exec do toplevel logava "SAIU exit=0" e o BARS_EXITS derrubava
    o gate do QEMU numa sessão SAUDÁVEL. flock + veredito por prova.
  - **AS VERDADES PEQUENAS**: veredito sem as 5 fases na mesa = NO-GO
    (fase morta não deixa linha); swaync com guarda (o aviso universal
    era o único daemon sem supervisionar/protect); udev nvme parava de
    escovar partições (TEST!=partition); Keysym do screenshot em
    minúscula (W-p/W-S-p, fim da ambiguidade região×tela do keysym 'P');
    fonte dos títulos é a REAL (JetBrainsMono NF — "JetBrains Mono"
    com espaço caía no fallback); foot/waybar/rc.xml falam a mesma
    família; --anchor probado no pin-pick/rollback (a lei "flag nova
    que mata"); Hidden e Name[pt_BR] entram no picker; can-suspend
    ANTES do lock (toast que ninguém via); selo do fix-keys só com
    cura feita; raiz ext4 não mais nasce com grub-btrfsd FAILED;
    libpulse explícito; image-visibility com valor de enum; nome do
    pacote sstp correto; zshconfig aponta pro editor que existe;
    KVM real no verify; journald/README/VERIFICATION/BUILDING/
    SCRIPTS concordam com o código.
- **v2.10.3 — O MENU DAS JANELAS** (o veredito do dono sobre a comutadora
  da v2.10.1/2, ponto a ponto):
  - **"eu esperava algo como o menu do alt+tab… não consigo escolher para
    qual programa quero voltar ou encerrar"** — o ciclo cego morreu: o
    comutador agora ABRE O MENU das janelas. Cada janela é uma linha
    (ícone do app + título, na ordem MRU do daemon — a semântica do
    alt-tab), o clique na linha foca/restaura a ESCOLHIDA e o ✕ da linha
    encerra AQUELA janela. Escolher é sair do menu. SEM preview, SEM
    miniatura — a linha é o OSD do alt-tab, agora clicável. O menu mora
    NA MESMA superfície da pílula (zero superfície nova, zero input
    fantasma), nasce invisível, cresce para cima e some na escolha.
  - **"o ícone fica mudando para o ícone dos programas, achei isso muito
    ruim"** — o botão não é mais ninguém: ícone FIXO
    (`preferences-system-windows`); quem carrega ícone de app é a LINHA,
    dentro do menu.
  - **"fecho um programa da dock e aquele marcador de aberto está
    continuando"** — a doença real: todo app lançado pela dock é filho
    DELA; saído sem colheita virava ZUMBI com `/proc/<pid>/comm` vivo e
    o scan lia o morto. Cura dupla: ceifa por `waitpid` não-bloqueante a
    cada tick (`_reap_children`) + o critério do "aberto" virou a
    JANELA REAL do daemon (processo em 2º plano sem janela não acende
    indicador, não segura botão dinâmico e não vira "focar" — é abrir).
  - **"a parte de programas em segundo plano não funciona, clico na
    tarefa e ela não encerra"** — craft-bgapps v4.1: a escolha era
    `Nome (pid N)` e o corte `${choice##*pid }` deixava o `)` no fim — o
    guard `*[!0-9]*` rejeitava TODA escolha ("escolha sem pid válido" no
    menus.log) e o kill NUNCA partia. O pid agora é só dígito
    (`tr -cd '0-9'`), com prova funcional na suíte. E a dock empatou o
    verbo: o MEIO no botão do app ENCERRA O PROGRAMA (todas as janelas
    recebem o WM_DELETE gracioso).
  - **MATCHING que faltava** — app_id composto casa por STEM
    (`org.xfce.Thunar` → `thunar`) e por contenção (≥4 chars, dois
    sentidos): janelas que o casamento antigo não via deixavam o fecho e
    o intercâmbio cegos.
  - **Leis intactas**: fallback v2.10 (daemon morto = /proc + wlrctl),
    A-Tab/A-S-Tab do compositor, a escada de raio 20–12px da lei v2.3.9,
    `font-size` banido do dock.css. O daemon `craft-toplevel` NÃO mudou
    (sha256 do PKGBUILD intacto — o CYCLE segue na API do socket; a dock
    é que não o usa mais: escolher venceu adivinhar).
  - Suíte: **1690 peças · 0 falhas · GO** (baseline 1673 — +17 líquidos:
    o contrato do CYCLE reescrito, 16 novos)

- **v2.10.2 — A CURA DA #117** (a v2.10.1 NUNCA publicou: o gate do verify
  pegou o daemon morrendo em loop no live e travou o release — o sistema
  funcionando como projetado):
  - **O QUE O GATE VIU**: TOPLEVEL_COUNT=0 · TOPLEVEL_SOCKET=DEAD ·
    BARS_EXITS=25 — o craft-toplevel nascia e morria a cada ciclo do
    supervisor (5s), com o stderr honesto no bars.log:
    `message too short, object (2), message global(usu)`.
  - **CAUSA-RAIZ**: o marshal MANUAL do `get_registry` usava o opcode 0 do
    wl_display — que é o **SYNC** (get_registry é o 1). O compositor criou
    um callback no id 2; meu cliente o tratava como registry; o
    `done(serial)` de 4 bytes chegava "too short" para o `global(usu)`.
    Nenhum global foi anunciado → sem manager → saída honesta exit 1.
  - **CURA**: `wl_display_get_registry()` da PRÓPRIA biblioteca (a função
    real existe desde sempre) + 2 contratos que proíbem marshal manual de
    request no display. O stderr honesto + supervisor + gate fizeram o
    trabalho de perícia sem uma linha extra de código de depuração.
  - Suíte: **1673 peças · 0 falhas · GO** (+2 contratos da lição)

- **v2.10.1 — A DOCK COMUTADORA** (o dono, ao pedir a v2.10 com navegação
  entre janelas: "a dock tendo meio que essa funcionalidade de alt tab
  perfeitamente pra navegar entre os programas abertos e etc ou até mesmo
  um atalho pra isso clicável na dock, pensa na melhor forma de fazer isso
  para que o dock não precise de preview dos aplicativos… o nosso é mais
  minimalista, produtivo, e com ui/UX extremamente bem pensada"):
  - **O PROTOCOLO DIRETO** — a limitação honesta da v2.10.0 ("por janela
    exige falar o protocolo direto") MORREU: o **craft-toplevel**, pacote
    novo compilado da fonte vendada do próprio repo (`vendor/craft-
    toplevel.c`, ~700 linhas de C, sha256 pinado, revisão independente
    3-a com 1 CRÍTICO corrigido — a compactação de janelas mortas movia
    structs apontadas pelo dispatcher; agora vive no heap, ponteiro
    estável), fala `zwlr_foreign_toplevel_management_v1` DIRETO com o
    labwc e serve a sessão num socket UNIX (`XDG_RUNTIME_DIR/elite/
    toplevel.sock`): LIST (janelas com flags, rank MRU, app_id, título),
    ACT (unset_minimized + activate **por id** — a restauração de
    minimizada é COMANDO DO PROTOCOLO, a "hipótese forte" da v2.10 virou
    lei), CLOSE e CYCLE (a próxima do **anel MRU** — o alt-tab de
    verdade). Dependência ÚNICA: libwayland-client (já ia na ISO).
  - **CLIQUE ESQUERDO = JANELA EXATA** — 1 janela: foca/restaura; N
    janelas: cicla ENTRE ELAS (a memória é de quem clicou); 0: abre.
    Fim da adivinhação de capitalização: o app_id do snapshot casa os
    candidatos case-insensitive (e o título como último recurso).
  - **O COMUTADOR CLICÁVEL (o atalho pedido)** — botão no FIM da pílula,
    existe SÓ com ≥2 janelas, **SEM preview e SEM miniatura** (minimalista
    como o dono manda): o ícone dele é o ÍCONE DO APP de destino — o
    clique anuncia onde vai cair — e o verbo é CYCLE; cliques seguidos
    caminham pelo anel inteiro. Some sozinho quando resta 1 janela.
  - **MEIO fecha por ID** (a janela focada do app; wlrctl no fallback).
  - **A LEI DO FALLBACK** — daemon ausente/morto = snapshot vazio e TODO
    verbo cai no caminho v2.10 (wlrtl case-variants / launch): a dock
    NUNCA fica pior por causa da cura. Conexão PERSISTENTE (zero fork por
    tick — o /proc scan dos indicadores segue à parte). O daemon é
    SUPERVISIONADO pelo craft-bars (restart ≤5s + stderr no bars.log;
    2ª instância é no-op: probe de socket vivo + flock de arranque) e
    nasce no autostart antes do supervisor.
  - **TECLADO × MOUSE, cada um no que é melhor** (a resposta à pergunta):
    A-Tab/A-S-Tab do compositor CONTINUAM (ciclo com OSD); a dock comuta
    por clique com o destino ANUNCIADO pelo ícone. Sem preview não é
    limitação — é o design (o preview está onde o mouse já está: no
    ícone do app).
  - **PROVA NO LIVE (gates novos)** — o probe da sessão agora reporta
    TOPLEVEL_COUNT e TOPLEVEL_SOCKET (PING real no socket), e o gate do
    verify cobra: daemon ≥1 E socket falando (processo sozinho não
    basta). 31 contratos novos trancam o protocolo (opcodes do XML
    oficial, dispatcher_data, new_id via .o, flock, heap), a esteira
    (PKGBUILD + sha256 pinado + packages.add), a dock (fallback lei,
    comutador, ciclo) e a sessão.
  - **O FORENSE APRENDEU O 2º CAMINHO DE CURA** (run #116: janela de 404
    transitória do mirror; o preflight re-sincronizou e fechou o cache, o
    forense não reconhecia a cura e matou uma ISO boa): "downloader
    falhou E o preflight fechou o cache depois" = benigno. O gate continua
    FATAL para downloader sem cura nenhuma (a lição v1.4 de pé).
  - Suíte: **1671 peças · 0 falhas · GO** (baseline 1640 — +31 líquidos)

- **v2.10.0 — A DOCK AUTO-ADAPTÁVEL** (rig do dono: "quando clico com o
  botão esquerdo no Brave ele abre como se fosse uma nova sessão… se eu
  minimizo programas não consigo voltar onde estava… quando abro um programa
  que não está fixado ele não vai pra dock… a dock deve ser auto adaptável e
  funcionar como funciona uma dock em qualquer sistema"):
  - **O FOCO QUE VIRAVA "NOVA SESSÃO" MORRE** — perícia: o matching do
    wlrctl é EXATO e case-sensitive; o bridge X11 do wlroots expõe a
    WM_CLASS com a capitalização do app ("Brave-browser") e os candidatos
    nasciam minúsculos → NENHUM casava → o fallback abria outra instância
    (o foot funcionava por ser minúsculo idêntico ao binário — o dono:
    "o foot funciona mas não é consistente"). CURA: TODO candidato
    (hint → StartupWMClass → binário → stem) vai em 3 formas canônicas
    (original/minúscula/Título) e o último recurso é por TÍTULO com o nome
    do app — para TODOS os apps. O "está rodando?" do clique também virou
    case-insensitive (o comm do /proc pode ter capitalização própria).
  - **APPS ABERTOS SEM PIN ENTRAM NA DOCK** (a parte que faltava para ser
    uma dock de verdade): app rodando sem pin e COM .desktop ganha botão
    dinâmico (ícone/nome resolvidos pelo sistema) após um FIO vertical;
    ao fechar, os dinâmicos somem sozinhos até restar só o fixado. NADA se
    fixa sozinho; o DIREITO num dinâmico FIXA (craft-pin add — .bak e
    reload SIGUSR2 de sempre). NoDisplay/Hidden NUNCA viram botão (a lei
    E21 da gaveta vale na dock). Dedup por desktop-id: fixado nunca
    duplica. Diff a cada tick: nada toca no GTK se nada mudou (zero
    flicker).
  - **O MEIO FECHA** (convencional das docks): wlrctl window close —
    WM_DELETE gracioso, o app confirma se tiver o que salvar.
  - **O POLL SIMPLIFICOU E CRESCOU**: a varredura direta de /proc (uid do
    usuário + comm) substitui o fork do pgrep a cada tick — N leituras sem
    NENHUM fork, sem ERE para escapar (a classe do audit 24-b é impossível
    por construção) e o MESMO scan alimenta pins e dinâmicos.
  - **Limitação HONESTA**: o matching é POR APP (comm/.desktop), não por
    janela — o wlr-foreign-toplevel não tem listagem via CLI (o wlrctl só
    casar). Duas janelas do mesmo app = um botão; se o rig reportar a
    necessidade de ciclo por janela, a v2.11 fala o protocolo direto.
    E a restauração de MINIMIZADA pelo activate é hipótese forte (a spec
    recomenda; o labwc decide) — validar no rig.
  - Página local do projeto APOSENTADA a pedido do dono ("pode apagar nossa
    página local aqui para não tomar tempo editando") — a prova real mora
    no CI e nos releases; o tempo vai para a distro, não para o espelho.
  - Suíte: **1640 peças · 0 falhas · GO** (baseline v2.9.2: 1627 — +13
    líquidos: 11 contratos da dock auto-adaptável + realinhamento do
    pgrep→/proc [o v2.5.0 vira proibição] + o scan por uid).

- **v2.9.2 — A LEI DO LOG SILENCIOSO (e a auditoria da sujeira inteira)**
  (dono: "Log calamaris não precisa mais abrir um terminal só pra aparecer
  logs… o que mais de sujo como isso ficou no sistema?"):
  - **O TERMINAL DE LOG DO CALAMARES MORREU** — a v1.9 cumpria o spec M1.2
    original abrindo um foot anexado (`tail -F`) ao session.log ANTES do
    instalador subir; um terminal que se abre SOZINHO é sujeira visual da
    mesma família do debloat: nada aparece sem pedido. O `calamares-elite-log`
    v2.0 mantém as duas frentes que valiam: o log completo persiste em
    **/var/log/calamares.log** do instalador E é copiado para o **/var/log do
    sistema instalado** (auditoria pós-boot) — log é ARQUIVO para auditoria,
    não janela para interromper. O launch.sh upstream segue intocado (E5a2).
  - **AUDITORIA DA SUJEIRA (a resposta ao "o que mais?")** — varredura de
    TODA a ISO atrás da mesma família (janela/terminal/processo visível que
    o sistema inicia sem pedido): (1) spawns de terminal — o do Calamares
    era o ÚNICO iniciado pelo sistema; todos os outros (W-Return/C-A-t foot,
    btop, pulsemixer, nano, TUIs de fallback do craft-connect) são resposta
    a pedido do usuário; (2) autostart do skel — só daemons headless
    (swaybg, craft-bars, swaync, polkit-gnome, udiskie --no-tray, craft-idle,
    craft-fix-keys, gnome-keyring, cliphist) — nada abre janela; (3) units
    de boot — elite-firstboot e elite-session-probe escrevem em
    /var/log e journal, zero aparição; (4) /etc/xdg/autostart — o upstream
    não entrega nada e nenhum pacote do rice spawna janela no boot;
    (5) Calamares NÃO auto-abre no live (o dono chama quando quer);
    (6) notificações existentes são FEEDBACK de ação (lei v2.3.10 "avisa e
    some") — nenhuma é iniciativa espontânea sem valor. Contratos novos
    provam a AUSÊNCIA (nogrep de foot/tail no wrapper) e a permanência da
    persistência.
  - Suíte: **1627 peças · 0 falhas · GO** (baseline v2.9.1: 1626 — +1
    líquido: o contrato que MANDAVA o terminal virou 2 proibições — foot e
    tail — na conta do bloco M1.2).

- **v2.9.0 — A GAIOLA MORREU (com prova), O ENCERRAR ENCERRA, A GAVETA FICA
  LIMPA** (rig v2.8.0, o dono: "matou o uso do mouse no sistema… eu não tô
  conseguindo sequer instalar o sistema pois o click do mouse não está
  funcionando direito, tá basicamente funcionando só na topbar e dock fora
  isso nada funciona click" · "a dock continua com o problema que falei de
  fazer tipo um refrash quando mexo nos menus" · "porque o meu click no menu
  de encerrar não está encerrando as tarefas?" · "oculta esses programas
  como xarchiver, gtk settings e etc que não precisa ficar na gaveta de
  aplicativos… ou são extensões, tipo o programa de documentos abrir pelo
  explorador de arquivos"):
  - **A GAIOLA MORREU — E A CLASSE DE BUG DELA É IMPOSSÍVEL POR CONSTRUÇÃO**
    — a perícia do código provou o crime: o campo da gaiola era setado
    DEPOIS da chamada que aplicava a região de entrada (a chamada lia o
    campo ainda vazio e RETORNAVA sem aplicar nada) → a gaiola nascia com
    a região de entrada DEFAULT (TODA a superfície) e o desarmar
    re-aplicava por UNIÃO (a rede só crescia) → UMA superfície invisível
    full-screen no layer TOP engolindo o clique de TODA janela — Calamares
    incluso (por isso nem instalar dava). CURA ESTRUTURAL: a dock volta a
    ser SÓ a pílula dela (layer BOTTOM) — zero superfícies auxiliares,
    zero regiões de entrada, zero telefone de menus. O clique fora de menu
    virou LEI DO COMPOSITOR: o rc.xml §Root executa `craft-menu-dismiss`
    (novo, ~40 linhas) no esquerdo (FECHA e não abre nada — sem menu é
    no-op de ~1ms: o esquerdo segue MUDO na prática) e no direito (FECHA e
    abre o menu-raiz NO LUGAR — nunca dois menus empilhados). O craft-menu
    perdeu o handshake (SIGRTMIN/ack/espera de 300ms): o menu nasce no
    frame em que é chamado. O "refresh" da dock ao abrir menu era a mesma
    família (superfície extra + troca de região + reinício do supervisor) —
    também morre aqui. Contratos de AUSÊNCIA provam: nenhum método, nenhum
    constante, nenhum layer TOP na dock.
  - **O ENCERRAR ENCERRA (e se o sistema recusar, o erro NUNCA é silêncio)**
    — o silêncio da v2.8 era a gaiola engolindo o clique (até o diálogo do
    polkit ficava intocável). Com o clique curado, a cinta que fica: se o
    `systemctl reboot`/`poweroff` RECUSAR por qualquer motivo (polkit,
    inibidor, logind), o craft-power loga e levanta toast normal na tela
    com o porquê (lei v2.3.10 mantida: toast que AVISA e SOME — nada de
    critical eterno). As regras polkit locais (`49-elite-desktop.rules`)
    já autorizavam power-off/reboot/suspend para o usuário local ativo.
  - **A GAVETA FICA LIMPA (E21)** — helpers/extensões/demos saem da grade
    de aplicativos SEM morrer: `NoDisplay=true` inserido pelo build (o
    customize do chroot) DENTRO do grupo `[Desktop Entry]` (appending cego
    no fim cairia num grupo de action e seria ignorado) — Exec/Icon/
    MimeType intactos. Fora da gaveta: **xarchiver** (o 7zip vive nos
    verbos do Thunar — "Criar pacote…"/"Extrair aqui"), **thunar-bulk-
    rename** (F2 do Thunar), **papers** (documentos abrem pelo explorador
    de arquivos), **nm-connection-editor** (o W-n e o menu Rede são a
    porta), **gtk3-demo / gtk3-widget-factory / gtk3-icon-browser** (demos
    de desenvolvedor do GTK). Idempotente por contrato.
  - Suíte: **1601 peças · 0 falhas · GO** (baseline v2.8: 1588 — +13
    líquidos: parse do Root prova o VERBO de cada botão, ausências da
    gaiola, o dismiss, o E21 e os caminhos de falha do sessão).
- **v2.9.1 — O CI DESMENTIU A SUÍTE LOCAL (e a suíte aprendeu a não
  mentir mais)** (Test Suite do main @ 4bddb1b: NO-GO — "peça defeituosa:
  exec: elite/airootfs/usr/local/bin/craft-menu-dismiss"):
  - **O CRIME**: o `craft-menu-dismiss` nasceu **100644 no INDEX do git**.
    O disco deste sandbox entrega `rwxrwxrwx` para todo arquivo — a peça
    `exec:` olhava o FILESYSTEM (`[[ -x ]]`) e era **viciada aqui**: passava
    local e reprovava no CI. O que o checkout do CI e o squashfs da ISO
    herdam é o MODO DO INDEX = 0644 → no live o script do dismiss nasceria
    não-executável (**203/EXEC** — a classe já provada com o elite-tune no
    diag-boot2) e a lei do compositor do rc.xml chamaria um binário morto.
    A cadeia da suíte parou na 1ª falha — a auditoria completa do index
    provou que era o ÚNICO binário quebrado (o mesmo buraco do craft-idle
    na v1.6.2, repetido).
  - **A CURA EM TRÊS CAMADAS**: (1) `git update-index --chmod=+x` — o modo
    real; (2) `craft-menu-dismiss` registrado no **file_permissions** do
    apply-overlay (a cinta antifalha projetada contra 203/EXEC — o diff
    bin×lista tinha exatamente 1 buraco, agora zero); (3) os DOIS gates
    viram à prova de lista manual: a peça `exec:` audita o **MODO DO
    INDEX** (o que CI e ISO veem de verdade; filesystem vira reserva só
    para caminho não-rastreado) e o loop do file_permissions virou
    **GLOB-DRIVEN** sobre `airootfs/usr/local/bin/*` — binário novo sem
    entrada reprova na suíte, não na mão do dono.
  - Suíte: **1623 peças · 0 falhas · GO** (baseline v2.9: 1601 — +22
    líquidos: o glob do file_permissions audita os 27 binários, não 5).
- **v2.8.0 — A FOTO DO DONO FEZ LEI** (fotos do rig 27/out + diretrizes:
  "com o click esquerdo do mouse esse menu está abrindo" · "esse menu de
  senha está meio ruim, muito longo pra colocar a senha dava pra ser bem
  menor" · "o sistema e explorador de arquivos tem 7zip implementado pra
  conseguir descompactar e compactar tudo" · "esse wallpaper dá pra arrumar
  melhor na internet… mais vivo em IPS, minimalista, sem destrair ou
  machucar a visão" · "quando abro o menu da topbar a dock meio que some e
  aparece como se estivesse atualizado"):
  - **O ESQUERDO DO DESKTOP É MUDO DE VERDADE** — o default do labwc
    (docs/rc.xml.all §Root) traz Left E Middle → ShowMenu root-menu e o
    `<default/>` importa tudo; definir só o Right NÃO remove o herdado
    (o labwc soma binds e substitui apenas o MESMO par button+event).
    A cura é a documentada em labwc-actions(5): `<action name="None" />`
    como única ação de um bind limpa o bind anterior. Agora o rc.xml
    declara os TRÊS botões do Root: esquerdo e médio = None, direito =
    menu-raiz. Contrato COMPORTAMENTAL novo: a suíte PARSEIA o XML e
    prova o verbo de cada botão.
  - **A JANELA DE SENHA ENCOLHEU** — o modo `--ask` do craft-menu herda o
    `lines=10` do launcher (a foto: caixa alta com 90% de espaço morto)
    e recebia UMA LINHA VAZIA como entrada (o `printf '%s\n' ""` imprime
    uma linha — a entrada fantasma selecionada da foto). Cura: `--minimal-lines
    --lines 1` no modo ask (com probe de suporte e degradação graciosa) e
    stdin VAZIO de verdade (`</dev/null`) quando a lista é vazia.
  - **A GAIOLA FICOU PERSISTENTE — o pisca-pisca da dock morreu** — a
    v2.7 mapeava e desmapeava uma superfície full-screen (layer TOP) a
    CADA menu: cada map/unmap re-arranja as layers no compositor e a dock
    (BOTTOM) levava configure/redesenho no caminho. A v2.8 ergue a gaiola
    UMA vez no boot (transparente e inerte — input region VAZIA, o clique
    atravessa) e armar/desarmar troca APENAS a input region (um commit de
    wl_surface — zero geometria de layer muda, a dock não é tocada).
    Contrato: NENHUM `cage.hide()` no código.
  - **7ZIP CHEGOU AO EXPLORADOR** — o CLI já estava na ISO; a mão no
    Thunar entra agora: `thunar-archive-plugin` (verbos "Criar
    pacote…"/"Extrair aqui" no menu de contexto) + `xarchiver` (a GUI
    GTK3 mais leve da categoria, 1,9 MB — o file-roller da purga v1.1
    não volta). Integração provada na API do Arch (xarchiver.tap +
    thunarx-3/*.so). `packages.remove` e os contratos v1.1/v1.2 que
    proibiam o par foram realinhados (eram artefatos da era pré-v1.5,
    quando nem o Thunar existia na ISO). mimeapps.list: 7z/zip/tar/gz/
    xz/zst/bz2/rar abrem no xarchiver.
  - **WALLPAPER NOVO, CURADO NA INTERNET** — ondas de seda roxo/violeta
    da Unsplash (licença livre; a MESMA fonte/estética da v1.7.1 que o
    dono escolheu), triada por VLM entre 3 candidatas (suavidade 10/10,
    topo uniformemente escuro p/ barra branca, harmonia Catppuccin
    Mocha). PNG lossless 2812×1582 (16:9 nativo, sem upscale), blur 0.4px
    no fonte mata o ringing do JPEG — a poeira da era v1.7.1 não volta.
    Medido: luma 30.1, 0.00% preto puro (não esmaga o IPS), delta mediano
    de gradiente 0.70 (contratos novos: suavidade mediana ≤4, pior patch
    ≤12, sha256 anti-tamper atualizado).
- **v2.7.0 — A LEI DOS DOIS BOTÕES: esquerdo na barra, direito no desktop,
  clique fora que só fecha, dock que foca em vez de duplicar — e a rede
  instantânea que se edita no próprio lugar** (o dono, rig: "o menu de
  redes não ficou tão responsivo e rápido apesar de finalmente funcionar…
  é melhor realmente deixar a parte de editor para editar as redes invés
  de criar um menu só pra isso, mas no mínimo seria interessante conseguir
  excluir rede diretamente da tela de conexões salvas ou até mesmo editar
  a senha… quando Clico com o botão direito ou esquerdo na tela abre o
  menu da distro ok, mas isso só deveria acontecer ao clicar com o botão
  direito, e o que você fez foi isso mesmo só que na topbar as a topbar
  era pra funcionar com click esquerdo e não direito e na home ao
  contrário… quando eu quiser fechar um menu clicando fora não vai abrir
  o menu da home sabe… já aproveita para trabalhar na eficiência máxima
  de todos esses botões menus para responderem instantâneos pois e de
  buscar redes por exemplo demora um pouco… já na dock quando Clico em um
  programa já aberto ele deve ir para a tarefa aberta invés de abrir outra
  pois vi que isso acontece com alguns programas, se o usuário quiser
  abrir outra rapidamente ele pode fazer clicando no ícone com o botão
  direito"):
  - **A LEI DOS DOIS BOTÕES** — a divisão é geográfica: TOPBAR (interface)
    clica com o ESQUERDO — Rede, Encerrar e Sessão abrem no clique
    esquerdo, o 2º clique no MESMO botão fecha (toggle por pid) e o
    direito é mudo; DESKTOP clica com o DIREITO — o menu-raiz é do clique
    direito e o esquerdo é MUDO por lei (rc.xml). Tooltips ensinam o novo
    verbo ("— clique: …").
  - **A GAIOLA (craft-dock-gui v2.7 + craft-menu v4.1)** — "fechar um menu
    clicando fora" nunca mais abre o menu da home: o craft-menu pede a
    gaiola à DOCK por SIGRTMIN (pid em `elite-dock.<uid>`; ack em ≤300ms)
    e a dock mapeia uma superfície INVISÍVEL (layer TOP, teclado NONE,
    transparente) cuja região de entrada é a tela MENOS a faixa da barra —
    todo clique fora do menu mata o fuzzel pelo pid do state e o desktop
    NEM VÊ o clique. Sem dock/sem ack: menu abre igual (degradação
    graciosa). `trap EXIT` limpa state + ack em TODO fechamento.
  - **A DOCK COM DOIS VERBOS** — ESQUERDO num pin: programa rodando →
    FOCAR a janela (`wlrctl window focus app_id:…` — wlr-foreign-toplevel);
    não rodando → abrir DIRETO (zero subprocesso no caminho comum). DIREITO:
    abrir OUTRA instância, sempre. A adivinhação do app_id: hint explícito
    (2ª coluna do dock-pins) → StartupWMClass → binário → stem; o pin de
    fábrica do Thunar nasce com o hint `org.xfce.Thunar` (app_id de app GTK
    não se adivinha do binário); o craft-pin add/rm viraram conscientes da
    coluna. **O WLRCTL é FONTE VENDADA**: a build #110 morreu com 'target
    not found: wlrctl' — o pacote NUNCA esteve em repo oficial nenhum (a
    suposição errada foi pega pelo gate, como manda a casa) e o upstream
    (sourcehut) estava em 502 no dia da cura — a fonte inteira vive agora
    em `vendor/wlrctl-0.2.2.tar.gz` (snapshot do mirror público @ 5872fa6a,
    código revisado: foco = alias de activate, app_id EXATO por strcmp,
    exit 1 sem match) com sha256 pinado no PKGBUILD do build — zero rede,
    zero fé, o gate do verify-install cobra o pacote.
  - **CRAFT-CONNECT v6 — INSTANTÂNEA E QUE SE EDITA**: a lista de redes
    abre do CACHE do NM (`--rescan no` — a varredura bloqueante da era v5
    travava 2–8s; era a lentidão flagrada); varredura nova roda EM FUNDO
    (fogo-e-esquece) e o "Atualizar…" explícito espera a PROVA da varredura
    nova pelo relógio do dispositivo (`LAST_SCAN` — comparar listas falha
    quando o fundo já varreu); status e rádio consultados em PARALELO.
    CONEXÕES SALVAS se gerem no próprio lugar, SEM menu separado de
    gestão: o pick abre os verbos da conexão — Conectar/Desconectar ·
    **Alterar senha…** (`nmcli connection modify … psk` + up para provar
    a senha nova AGORA) · **Esquecer…** (delete COM confirmação). O editor
    gráfico fica para a CRIAÇÃO manual (definição do próprio dono).
  - Suíte: contratos v2.6 quebrados atualizados + ~35 contratos NOVOS
    v2.7.0 (lei dos dois botões, gaiola, dois verbos da dock, hint de
    app_id, cache/paralelo/LAST_SCAN, verbos de senha/esquecer, fonte
    vendada do wlrctl com sha pinado) — 1.586 peças · 0 falhas · GO.
    Smoke funcional ponta-a-ponta com nmcli/craft- menu stubs: 16 ok ·
    0 falhas (cache, senha, esquecer+confirmação, espera pelo relógio,
    handshake sem dock, trap do state). E a cicatriz honesta: a build
    #110 FALHOU no gate ('target not found: wlrctl') e a cura foi a
    fonte vendada — o gate fazendo o trabalho dele.

- **v2.6.0 — A LEI DOS MENUS DA BARRA: clique direito, menu sob o botão,
  lista pura, toggle de verdade — e a rede que CONECTA** (o dono, prints
  do rig 26/out: "no menu de rede eu não consigo desligar/ligar minhas
  conexões seja cabo, wi-fi e etc nem me conectar a redes… esses menus
  centralizados não seria melhor ficar onde ela for aberta? tirar esse
  risco | que fica na frente… com o botão esquerdo do mouse remove o menu
  que aparece com o click e deixa só no click direito mesmo… clico nos
  botões da topbar novamente eles não fecham ou um não anula o outro…
  o encerrar continua pegando serviços do sistema que inclusive não
  encerram… no suspender meu pc até tenta mas rapidamente liga e fica
  como se eu só tivesse clicado em travar tela… solucione tudo de uma
  vez por todas"):
  - **CRAFT-MENU v4 — O MOTOR ANCORA E TOGGLA**: `--hide-prompt` mata a
    linha de digitação inteira (sem 'Sessão:', 'Encerrar:', sem o "|") e
    `--minimal-lines` encolhe a janela ao tamanho da lista — menu = LISTA
    PURA; `--anchor top-right` + `--x-margin` POR SLOT (`--at=power/
    bgapps/network/drawer`) faz o menu nascer SOB O BOTÃO (a barra de
    36px empurra pelo exclusive zone; submenus herdam o lugar do pai); e
    o toggle/cross-dismiss virou DETERMINISMO — pid do fuzzel gravado em
    `$XDG_RUNTIME_DIR/elite-menus.<uid>`: 2ª chamada do MESMO título
    fecha (exit 2), título diferente anula e abre (143) — a física de
    foco que o rig DESMENTIU saiu do caminho. Degradão gracioso via
    probe `fuzzel --help`; e `id -u` no lugar de `$UID` (dash não tem
    UID — morria rc=2 que o chamador lia como "toggle benigno": menu que
    nunca abre e morre sorrateiro; flagrado no smoke test).
  - **SÓ CLIQUE DIREITO** — network, custom/bgapps e custom/power ficam
    MUDOS no clique esquerdo ("remove o menu que aparece com o click e
    deixa só no click direito mesmo"); o ARCH do lançador segue no
    esquerdo (modelo macOS); tooltips ensinam o direito.
  - **CRAFT-CONNECT v5 — O MENU QUE CONTROLA A REDE**: ligar/desligar
    CABO por dispositivo, ligar/desligar WI-FI, CONECTAR em redes (lista
    ao vivo com sinal e 🔒; salva sobe pelo nome com a senha do cofre do
    NM; aberta conecta direta; nova protegida pede a senha no menu),
    reconectar/desligar CONEXÕES SALVAS, o Bluetooth que o dono aprovou
    e o editor para a criação manual — tudo `nmcli`, o cli do próprio
    NetworkManager (o bug do picker v3 morreu de vez: linha→SSID via
    MAPA escrito pelo mesmo awk que desenha a lista). Cada ação reabre o
    menu com o estado novo.
  - **CRAFT-BGAPPS v4 — SÓ PROGRAMA DO DONO**: o comm é normalizado
    antes da casca (o sd-pam se apresenta como "(sd-pam)" — com
    parênteses — e o padrão `sd-pam*` deixava o serviço vazar; foto do
    rig), a casca ganhou `dconf*`/`gvfs*`/`Xwayland*`, e CANDIDATO SEM
    DISPLAY NUNCA É PROGRAMA (assinatura de serviço no
    `/proc/PID/environ`). Encerrar DE VERDADE: SIGTERM, 2s, SIGKILL em
    quem aguentou.
  - **SESSÃO MINIMALISTA + SUSPENDER DE VERDADE**: 'Travar tela' saiu do
    menu (o dono: "é necessária essa opção?" — o lock é PARTE do
    suspender e segue no W-l); o Suspender trava PRIMEIRO (acorda no
    wallpaper borrado) e suspende com `systemctl suspend -i` — os
    inibidores de sono de apps (navegador/players) eram a morte calada
    do "tenta e volta".
- **v2.5.0 — A AUDITORIA TRIPLA: lock só com wallpaper + o fim da dock
  surda** (o dono: "só o wallpaper com Blur e não mostrar as janelas… faz
  3 auditorias e onde ficar confuso refaz… até ter certeza que está
  limpo, otimizado, eficiente e principalmente funcional e sem leak"):
  - **O LOCK NÃO REVELA MAIS O QUE ESTAVA ABERTO** — o fundo do hyprlock
    era `path = screenshot` (foto da TELA, janelas incluídas, borrada).
    Agora: O WALLPAPER do desktop com blur (png→jpg, a MESMA cadeia do
    swaybg; sem nenhum: preto AMOLED) — o craft-lock resolve o arquivo
    num conf efêmero de nome fixo (zero acumulação), e o idle/logout
    passam a travar POR ELE (o hyprlock direto ignorava a cadeia). Dim
    recalibrado 0.35→0.70 (o wallpaper dark premium em .35 era sopa
    preta). 3 cenários provados em teste + HOME hostil (com `&|`) provado.
  - **O ACHADO ALTO: A DOCK FICAVA SURDA** — os handlers SIGUSR1/SIGUSR2
    do craft-dock-gui retornavam `False` = G_SOURCE_REMOVE: a source do
    sinal morria na 1ª dispatch e `craft-pin add/rm` (reload) + o W-S-d
    ficavam MORTOS pelo resto da sessão — silencioso, porque a dock
    seguia viva e o supervisor nunca reiniciava. Cura: `SOURCE_CONTINUE`.
    `read_pins` também só capturava FileNotFoundError (mesma morte via
    caminho de erro) — agora `OSError, UnicodeDecodeError`.
  - **LEAKS/RECURSOS curados** (3 agentes forenses varreram o repo
    inteiro; 12 achados + 4 resíduos da re-auditoria, todos curados):
    bars.log sem teto DURANTE o loop (crash-loop ≈1,7MB/h — cap agora por
    ciclo); 1 pgrep POR PIN a cada 3s na dock (N→1 com alternância +
    re.escape); `pacman -Sy` completo a TODO login no craft-fix-keys
    (guard 24h com stamp clampado contra RTC morto); errf órfão nos exec
    do craft-logout (o trap EXIT não roda através de exec); sed do lock
    à prova de HOME com `&|`; marca "← atual" do idle que NUNCA casava
    (código morto desde sempre); mv condicional do craft-pin que pulava
    a remoção do último pin.
  - **SUJEIRA curada** — SCRIPTS.md ensinava o craft-pin da era morta
    (config.dock/modules-left) e documentava o fg-booster EXTINTO como
    instalado (agora: história documentada, não fantasma); craft-bat
    ganhou seção (era invisível); o symlink firstboot.wants agora é
    relativo (dangling no repo); comentário do build.sh sobre o profile
    do Brave corrigido; **craft-rollback ganhou porta de entrada** (menu
    completo de snapshots sem NENHUM chamador — órfão de UX: entrou no
    menu Sessão).
  - **O RITUAL PROVOU 2 VEZES**: o teste dos 3 cenários do lock flagrou o
    sed `^path` cego à indentação (no-op silencioso) ANTES do commit; a
    re-auditoria (rodada 3) confirmou as 10 correções e achou 4 resíduos
    (todos curados na hora). Suíte: 1492·0·GO.

- **v2.4.0 — O MOTOR QUE JÁ ABRIA + UM PROCESSO POR PROGRAMA** (o rig
  falou de novo: "quando clico nos botões nem abre menu nenhum… aquele
  de segundo plano abre um preview e não o menu… abri o Brave e abriu 11
  serviços… as vezes some também… se não conseguir compactar, pode
  remover o menu… estuda as extensões do gnome"):
  - **A HONESTIDADE QUE FALTAVA: o motor GTK do menu NUNCA abriu no rig**
    — a nativa (v2.3.8) e a gaiola (v2.3.11) morreram da mesma classe de
    falha na MÁQUINA REAL: duas reescritas, dois funerais. A v3 troca o
    MOTOR pelo único com prova de vida no rig: o FUZZEL — o launcher e o
    menu de Sessão sempre abriram, filtraram e fecharam nele (a cura
    v2.3.6 do clique-fora foi provada NA MÁQUINA do dono). craft-menu v3
    = POSIX sh puro, zero GTK, zero layer-shell, zero corrida de foco:
    a classe "morre antes do 1º frame" está EXTINTA por construção — não
    existe mais toolkit para falhar.
  - **A LEI DOS MENUS VIROU FÍSICA** — só existe um teclado: abrir outro
    menu rouba o foco e o anterior FECHA SOZINHO (exit-on-focus-loss=yes,
    agora CONTRATO escrito no fuzzel.ini); o 2º clique no botão fecha —
    o que o burn test v1.4 do Sessão já tinha provado. Gramática de
    saída 0/1/143 intocada: os 7 chamadores não mudaram uma linha. O
    título vive no prompt (contexto + filtro por digitação).
  - **BGAPPS v3: UM PROCESSO POR PROGRAMA** — "abri o Brave e abriu 11
    serviços" morre: entra no menu o PRINCIPAL de cada árvore (o
    candidato cujo PAI não é outro candidato) — renderers/gpu/utility do
    Chromium e derivados, zygotes, crashpad e o app dentro do sandbox do
    flatpak são a sombra do programa, NUNCA entrada. Cintura de
    segurança: cmdline com " --type=" nunca é principal — nem órfã
    adotada pelo init. Prova local: 5 processos numa árvore fake
    (app + 2 renderers + 1 filho limpo + 1 órfão) → 1 entrada.
  - **O PREVIEW MORREU** — o tooltip vira DESCRIÇÃO curta, a gramática
    dos outros módulos ("não precisa de preview apenas uma descrição
    assim como outro e ao clicar que abre o menu"): "N programa(s) em 2º
    plano — clique: escolher o que encerrar".
  - **O BOTÃO QUE SOME À TOA** — status à prova de bala: QUALQUER falha
    interna ainda emite JSON válido (o módulo só some quando NÃO há
    programa de verdade — que é a regra, não o bug).
  - menu.css aposentado junto (o rice do menu que nunca abriu).

- **v2.3.12 — a auditoria de garantia: o manual conta a história inteira e
  o mpris deixa de fingir** (auditoria topbar + manual + UI/UX, out/2026):
  - **O MANUAL ESTAVA 5 VERSÕES ATRASADO** — este CHANGES parava na
    v2.3.6: a v2.3.7 (os 6 crimes do live), a v2.3.8 (a era do menu
    nativo), a v2.3.9 (a Lei da Pílula), a v2.3.10 (notificações +
    bgapps + print fora + power mauve) e a v2.3.11 (a Gaiola) não
    existiam para quem lê os docs — as 5 entradas abaixo entraram agora,
    escritas dos commits. O VERIFICATION citava ~1.235 asserções (a
    suíte real passou de 1.477) e o SCRIPTS não documentava craft-menu,
    craft-bgapps nem craft-shot — exatamente os 3 scripts que mais
    mudaram nas últimas 3 versões.
  - **O MPRIS FINGIA** — o comentário do config prometia "Clique: esq =
    play/pause, meio = próxima, dir = anterior" e NENHUM on-click
    existia: clicar na música não fazia NADA (a v2.3.9 até excluiu o
    módulo do hover por ele não ser clicável — a pílula era honesta, o
    comentário não). Agora os cliques são reais (playerctl — já era dep
    dos keybinds de mídia do rc.xml) e o hover voltou por merecimento: a
    lei pinta quem de fato clica.
  - **BRANCO, como o dono pediu** — "o resto pode ser branco mesmo": o
    mpris era MAUVE no lado direito; a assinatura roxa fica com o ARCH
    (esquerda) e o power (direita) — o resto é texto.

- **v2.3.11 — craft-menu v2.0 A GAIOLA — o menu modal à prova de foco**
  (o rig: "os menus sequer abriam — reescreve do zero de forma
  completamente mais inteligente"):
  - ADMISSÃO: a v1 morria ANTES do 1º frame na máquina real — janela
    solta + teclado ON_DEMAND + focus-out→quit = corrida de foco no
    mapa (o labwc entrega e revoga o foco na mesma carrada) — o dono
    clicava e nada aparecia (as fotos da v2.3.10 eram o TOOLTIP, não o
    menu aberto).
  - REESCRITA DO ZERO com a fórmula dos overlays que funcionam em
    produção (wlogout, gtklock, o próprio fuzzel): a GAIOLA — a
    superfície é a TELA INTEIRA (4 âncoras, layer OVERLAY, véu 35%), a
    pílula do menu morta no centro dos 2 eixos, teclado EXCLUSIVE
    (ESC/↑/↓/Enter garantidos) e 5 caminhos de fechamento SEM depender
    de foco: clique fora por GEOMETRIA (alocação da pílula), ESC,
    escolha, toggle (2ª chamada do mesmo título) e cross-dismiss (abrir
    outro menu). ZERO focus-out-event: a classe do "menu que morre ao
    mapear" está extinta POR CONSTRUÇÃO — não existe código para
    falhar.
  - Interface argv/stdin intocada (a era dmenu continua); +7 contratos.
    A tag v2.3.10 foi movida para este commit e a build re-disparada
    (a ISO que nascia carregava o menu quebrado — cancelada antes de
    publicar).

- **v2.3.10 — fim das notificações eternas + bgapps só com PROGRAMA**
  (2 fotos do live 25/10: "essas notificações não somem… essa função dos
  processos é ruim… não gostei do botão de print melhor remover… o botão
  de desligar deixar roxo como o ícone do arch… o resto pode ser branco
  mesmo"):
  - **NOTIFICAÇÕES QUE NUNCA SUMIAM** — exit 1 COM stderr virava
    "FALHOU" nos 7 chamadores de menu; o GTK cospe Gtk-CRITICAL benigno
    no destroy (main_quit duplo: ESC → focus-out → 2º quit) e o toast
    nascia CRÍTICO — e o timeout-critical do swaync era 0 = ETERNO.
    Cura tripla: craft-menu com guard quit_once (stderr nasce limpo);
    os 7 chamadores tratam exit 1 SEM stderr como fechado pelo usuário
    (benigno SEMPRE — fechar NUNCA é falha; crash real com stderr
    continua gritando); swaync com timeouts 8/4/12s (nada é eterno).
  - **PROCESSOS SÓ DE VERDADE** — a lista exata da casca deixava vazar
    os comm truncados a 15 chars (at-spi2-registr, xdg-document-po,
    gvfsd-metadata) e o próprio craft-bgapps (7× na foto do dono).
    Cura: casca POR PREFIXO (at-spi*, xdg-*, gvfsd*, bwrap*, swaync/
    swayidle/udiskie/cliphist/wl-*, craft-*/elite-*, shells) + varredura
    do /proc REAL do UID: TODO programa de verdade aparece — nativo,
    flatpak, AppImage, interpretado — e o encanamento da sessão nunca.
  - **PRINT FORA DA BARRA** (3ª e definitiva) — o craft-shot segue vivo
    nos atalhos W-P (região) e W-S-P (tela inteira), que cobrem os dois
    verbos sem assento fixo na barra.
  - **POWER MAUVE, DIREITA BRANCA** — o ARCH à esquerda e o power à
    direita fecham a barra com a MESMA assinatura roxa; o pêssego do
    bgapps morreu (grito decorativo — a presença do botão já é o
    sinal) e o resto do lado direito é texto.

- **v2.3.9 — A LEI DA PÍLULA — hover centralizado e padronizado na
  distro inteira** (o dono: "quando coloca sobre alguns ícones… não
  parecem bem centralizados naquele contraste que o mouse cria… fique
  atento aos espaços, desenhos, tamanho e à consistência visual como um
  todo pra ficar tudo padronizado, bem desenhado e alinhado"):
  - A LEI: o hover é a MESMA pílula em toda a distro — o mesmo respiro
    nos 4 lados do alvo; alvo 44px = raio 12px (dock e menus GTK);
    hover SÓ onde clica (affordance honesta); transition na regra BASE
    (ida E volta animam); hover = surface0, pressed = surface2 (os
    degraus certos da escada Mocha).
  - 6 defeitos curados com evidência: dock 52×44 (o glifo nascia fora
    do centro da própria pílula), drawer assimétrico (0 12px 0 14px),
    shot sem regra base, 3 paddings misturados na barra (10/12/14),
    hover em módulo que não clica, título do craft-menu colado à
    esquerda (justify não centra linha única — halign CENTER sim), e o
    hover do menu labwc no degrau errado + swaync com raio 10px órfão.

- **v2.3.8 — A ERA DO MENU NATIVO — nasce o craft-menu** (o dono
  corrigiu a leitura: "o que eu queria centralizar é o nome do menu e
  remover a barra que fica, tipo Rede |"):
  - O menu deixa de ser texto no fuzzel e vira janela GTK própria:
    título centrado, itens com pílula, e é NELE que passa a morar a LEI
    do toggle (2ª chamada fecha) e do cross-dismiss (abrir outro fecha
    o primeiro).
  - Interface dmenu POR STDIN: listas DINÂMICAS passam por pipe
    (processos vivos, snapshots) — sem eval, sem word-splitting, à
    prova de injeção: linha = um item. Chamadores migrados: bgapps,
    idle, rollback-Restaurar.
  - Bit de execução gravado no índice git (o CI flagrou: o filesystem
    local mascara 777) e CPOW órfão removido da suíte (o gate cobre os
    próprios tests).

- **v2.3.7 — o live do dono falou em 3 áudios, 3 logs e 4 fotos — e o
  princípio é UM: "é tudo o que o usuário não espera"**:
  - OS 6 CRIMES curados: falso alarme crítico no ESC (fuzzel.ini com
    comentários ';' — o parser só honra '#'); botão de 2º plano morto
    em silêncio (newline cru no JSON do tooltip — o waybar recusava o
    módulo inteiro); alvos de morte que não são apps (at-spi/bwrap na
    lista de SIGTERM); picker de Wi-Fi morto (o verbo agora abre o
    gerenciador do SISTEMA — nm-connection-editor/nmtui; picker,
    prompt e parse próprios extintos); mutar o som mutava o mic junto
    (:not(.mic) isola o grito); WiFi/BT/power escondidos num
    buttons-grid dentro do painel de notificações (painel =
    notificações; rede no módulo de rede, energia no Sessão).
  - MEMÓRIA PARA O DUMP ("craft-dump --upload quero puxar só com esse"):
    journal PERSISTENTE (Storage=persistent — a história sobrevive ao
    reboot) e o dump varre TODOS os boots (o "acordou sozinho" de dias
    atrás agora aparece).
  - O botão de print VOLTOU à barra a pedido do dono (depois sai de vez
    na v2.3.10 — a história é essa).

- **v2.3.6 — o rig falou de novo: o conector é TEXTO, os menus não mentem
  mais (nem no ESC), e o roxo saiu da dock** (prints/relatos instalando a
  v2.3.5, out/2026):
  - **FIM DO FALSO "ERRO 1" NOS MENUS** — ESC no fuzzel devolve exit 1 com
    stderr vazio e o script gritava "Menu falhou" crítico em fechamento
    NORMAL (relato do dono no menu de Rede). Os 6 menus tratam
    1-sem-stderr como fechado pelo usuário (benigno, log sem alarme);
    crash real (stderr com texto) segue gritando. Bônus: o `rm -f` do
    tmpfile nos caminhos benignos do pin-pick/logout.
  - **O CONECTOR WI-FI É TEXTO — FIM DO "ÍCONE FEIO DE PC"** — nm-applet e
    tray morreram: o ícone SNI de ethernet é bitmap de tema de ícones,
    fora da família Nerd Font da barra ("ícones inconsistentes e
    espaçados"). 'Wi-Fi: conectar à rede…' no craft-connect lista as redes
    do entorno (nmcli, mais forte primeiro), pede senha em campo oculto
    (`fuzzel --password`) e conecta — o fluxo do applet, sem applet, zero
    pacote novo. O EDITOR saiu do menu (edição avançada segue no W-n); o
    prompt 'Senha' entrou na lei do cross-dismiss.
  - **INDICADOR DA DOCK NEUTRO** — o underline lavanda do Mocha leu como
    "efeito roxo estranho" no rig: destaque por luz (o text da barra), não
    por cor (dock.css + fallback embutido do craft-dock-gui).
  - **Comentário do rc.xml honestificado** — ainda descrevia o
    hotspot/tira de 4px mortos na v2.3.4; agora documenta o W-S-d que
    funciona até em tela cheia.
  - **O DUMP DO RIG (740 linhas) flagrou 4 bugs reais de release — curados:**
    - **FIRSTBOOT NUNCA COMPLETAVA** — `sudo: a password is required` para
      `pacman-key` no INSTALADO (design herdado do live, onde sudo é
      NOPASSWD) + `-Sy` ANTES das chaves (db assinado por chave
      desconhecida falha inteiro) + `--recv-keys` sem timeout (unit
      'activating' por 17min). Agora: `pacman-key --init/populate` → chave
      CachyOS (recv com timeout 90) → `-Sy` → `ensure_cachyos` (keyring
      FRESCO direto do mirror — o pacote datado 2024 morre).
    - **ROLLBACK QUEBRADO** — `grub-btrfsd: failed`, "No directory found
      at /.snapshots": o timeshift JAMAIS foi configurado (sem config, sem
      snapshot — a promessa era pela metade) e ninguém criava o subvolume
      que a unidade vigia. Um rei só: **timeshift sai**, `snapper` entra
      (o par canônico do grub-btrfs) — o firstboot cria config+subvolume
      e o **craft-rollback v2** agora CRIA e RESTAURA snapshots de
      verdade (menu fuzzel, `snapper rollback`, pkexec por ação, reboot
      finaliza).
    - **RUÍDO DO UDEV** — a regra NVMe casava PARTIÇÃO (`nvme0n1p1` sem
      queue/scheduler): 'Could not chase sysfs attribute' ×4 a cada boot.
      O `n` obrigatório (nvme[0-9]n[0-9]*) casa só o dispositivo de bloco.
    - **NUL NO UPLOAD DO DUMP** — "byte nulo ignorado" na linha 144
      (journal cospem NUL): `tr -d '\0'` na fonte — o dump nasce limpo.
  - **MENUS FECHAM AO CLICAR FORA** — fuzzel `keyboard-focus=on-demand`: o
    grab exclusive engolia o clique fora e o menu ficava preso; agora o
    clique fora devolve o foco e o menu fecha (exit-on-focus-loss, default
    do próprio fuzzel). Vale para TODOS os 6 menus + o picker.
  - **MIC COM ASSENTO NA BARRA** — paridade pedida ("o de Mic é tão
    importante quanto o de áudio"): `pulseaudio#mic` nativo do waybar —
    clique muta o microfone (`pactl set-source-mute`), direito abre o
    pwvucontrol igual ao do som, muto = vermelho. Tooltip do som agora
    ENSINA o clique-direito (gerenciar era descoberta escondida).
  - **IDLE NO MENU SESSÃO** — "tem como controlar o tempo de idle
    facilmente?": o craft-idle JÁ fazia, mas morava só no menu do desktop;
    'Tempo de idle…' agora carrega no Sessão (energia + idle na mesma
    porta).

- **v2.3.5 — o rig falou: curas cirúrgicas dos usos básicos + o dump do
  dono** (prints/relatos instalando a v2.3.2, out/2026):
  - **FALSA FALHA DOS MENUS MORRE** — o cross-dismiss/toggle mata o fuzzel
    com SIGTERM (exit 143) e o script original gritava "Menu de Sessão
    falhou" em notificação crítica EM TODO fechamento por fora (o print do
    dono: "fuzzel exit=143"). Os 6 menus agora tratam 143 como fechamento
    benigno (log sem alarme) — crash real segue gritando com stderr+log.
  - **FIM DA PALESTRA DO SUDO (E20)** — "Presumimos que você recebeu as
    instruções de sempre…" saiu da sessão (`Defaults !lecture` no
    sudoers.d, validado com `visudo -cf` — sudoers ruim nunca entra).
  - **lstopo/"Hardware locality" FORA do Launchpad** — é a GUI do hwloc
    (dependência de terceiros), não app do dono: override NoDisplay,
    o padrão xgps.
  - **FLATPAK COM ÍCONE** — o XDG_DATA_DIRS da sessão (labwc environment,
    valor literal sem expansão) ganha as exportações de flatpak de sistema
    — o Sober sem ícone era isso. Vale no próximo login.
  - **O CONECTOR WI-FI DE VOLTA** — nm-applet no autostart: função vence
    estética (o nm-connection-editor EDITA, não CONECTA — "como conector
    numa rede wi-fi assim?"). craft-connect com rótulo honesto ("editar
    conexões"); os toggles WiFi/BT do painel de notificações já eram reais
    (nmcli/bluetoothctl) — agora contratados.
  - **AUTO-SUSPEND OPT-IN** — SUSPEND_MIN no idle.conf (0 = off de
    fábrica: a ISO não muda comportamento às escondidas); o craft-idle
    suspende de verdade quando ligado, com lock ANTES de dormir. O
    despertar imediato do rig é caçado pelo craft-dump (journal do
    suspend + /proc/acpi/wakeup — dispositivo vs BIOS).
  - **CRAFT-DUMP (o "btop completão")** — hardware, kernel/tuning,
    serviços Elite, caça ao despertar, journal de erros do boot, sessão
    (processos/barras/dock), os 3 logs da Elite + firstboot + Calamares,
    pacotes (explícitos/órfãos/foreign/flatpak/repos) e caches — num
    único arquivo, com `--upload` que devolve URL curta (termbin via
    /dev/tcp do bash, sem nc).

- **v2.3.4 — a dock que não some + o fim do instalador no instalado + o
  botão dos 2º planos** (relato do dono instalando a v2.3.3, out/2026):
  - **DOCK SEMPRE VISÍVEL** — o autohide por hotspot morreu NA PRÁTICA:
    "a dock ficou bem legal, mas ela sumiu e não apareceu mais". A cura é
    a semântica do protocolo, sem polling nem heurística: layer BOTTOM
    (tela cheia e a gaveta cobrem a dock sozinhas — e ela volta quando
    acabam) + zona exclusiva automática (maximizadas/tileadas respeitam a
    faixa — o comportamento dash-to-dock/plank/painel do KDE). Hotspot,
    teaser de 4s e hide-on-leave EXTINTOS do GUI e do CSS; a superfície
    agora TEM o tamanho da pílula (ancorada só na base — nada de faixa
    full-width comendo clique) e o float de 6px mora dentro dela (a zona
    exclusiva cobre o conjunto). W-S-d continua: esconder é ESCOLHA do
    usuário, nunca decisão automática.
  - **INSTALADOR SAI DO SISTEMA INSTALADO** — o unpackfs copia o root do
    live inteiro: o Calamares, o atalho "Instalar o Archcraft" do
    Launchpad e os scripts de instalação chegavam ao disco e ficavam para
    sempre ("O sistema instalou mas ficou o botão instalar archcraft
    ainda no menu de aplicativos, remova completamente"). Passo 2d do
    elite-firstboot (exclusivo do INSTALADO — ConditionPathExists
    !/run/archiso, o live não é tocado): `pacman -Rns calamares` (guard
    -Qq, best-effort) + remoção do calamares.desktop, calamares-elite-log,
    elite-install-stage e /etc/calamares. Idempotente e seco no --dry-run.
  - **CRAFT-BGAPPS (o botão dos 2º planos)** — "um botão tray na topbar
    para encerrar programas que estão executando em segundo plano e seja
    do usuário caso queira, tipo para interromper o easyeffects, algum
    launcher ou algo assim": módulo `custom/bgapps` na waybar que SÓ
    aparece quando há processo do usuário fora da casca da sessão; clique
    abre fuzzel dmenu com "nome (pid)"; escolha = SIGTERM + notificação.
    Varredura /proc real do UID (ps -u) — sem lista inventada de apps; a
    casca (compositor, barras, dock, wallpaper, áudio, dbus, systemd,
    portals, polkit, keyring, foot-server) é protegida de listagem/morte.
    Toggle na 2ª chamada, cross-dismiss com Sessão/Rede (mesma lei v1.4/
    v1.8.2 dos menus), stderr capturado + menus.log + notify (lei v2.3.1).

- **v2.0 — "a dock de verdade + a barra na convenção dos rices"**
  (áudios do dono, out/2026 — fim das gambiarras, com evidência):
  - **(A) DOCK NATIVA (craft-dock-gui)** — a era waybar-dock acabou com
    EVIDÊNCIA: waybar 0.15 crasha com 3+ módulos image (Waybar#5051 —
    pins de ícone real impossíveis), os glifos Nerd Font entregaram
    "botões mal recortados… nada é o ícone real", e o nwg-dock morre no
    labwc (log.Fatal sem sway IPC — lido no fonte). A dock agora é um
    programa GTK3 PRÓPRIO no protocolo wlr-layer-shell (o mesmo
    mecanismo do nwg-dock, SEM a dependência do sway IPC):
    **ícones REAIS do tema** via Gio.DesktopAppInfo (Papirus-Dark),
    **autohide POR HOTSPOT** nativo (tira de 4px que revela ao passar o
    mouse — a cura definitiva do "auto-ocultar"), pílula CENTRADA que
    abraça o conteúdo (o "horizontalmente menor" do áudio — não a altura),
    indicador de aberto in-process (pgrep por binário, 3s), SIGUSR1
    toggle (W-S-d) e SIGUSR2 reload. Runtime: python + python-gobject +
    gtk-layer-shell. Supervisão craft-bars ≤5s mantida.
  - **(B) PINS = .desktop REAL** — dock-pins (1 ID por linha;
    fábrica: foot/thunar/brave). craft-pin v2: resolve fuzzy por
    nome/id/exec (precedência XDG), .bak.last de um nível com restore
    que consome, reload por sinal. **craft-pin-status EXTINTO** (nada
    executa JSON por pin — a classe narrow v1.8 virou arquitetura).
  - **(C) BARRA SUPERIOR NA CONVENÇÃO DOS RICES** (áudio: "repara como
    que são feitos os rices"): ESQUERDA = ARCH (lançador) + app focado;
    CENTRO = relógio; DIREITA = shot, volume, rede, tray, sessão — o
    cluster esquerdo que misturava status com lançador está desfeito;
    o café (idle_inhibitor) saiu ("botão estranho"); nm-applet/
    blueman-applet saíram do autostart (ícones SNI antigos/quebrados —
    um ponto só de conectividade: craft-connect/W-n/W-S-b).
  - **(D) ÍCONES: SISTEMA NATURAL** — os overrides Icon= custom e os
    PNGs desenhados à mão saíram ("deixe o ícone ser tratado como o
    sistema já é"); Papirus-Dark permanece como tema (completo/moderno).
  - **(E) WALLPAPER = ARTE OFICIAL DA FAMÍLIA** — o minimal-27.png do
    pacote archcraft-backgrounds-minimal 1.0-6 (GPL3): PNG lossless
    4053×2280, fundo flat escuro (zero poeira por construção), violeta
    casando com o Mauve. Nada de IA, nada desenhado — "trazer de outras
    distros/temas", na letra.
  - **(F) CALAMARES LOGS EM TEMPO REAL NA CI** — o verify-install
    transmite os logs do processo de instalação ao vivo (a meta-instrução
    do áudio: "pra VOCÊ pegar nos testes logs do Calamares em tempo
    real"); o M1.2 (v1.9) cobre o rig do dono (tail -F ao vivo +
    /var/log/calamares.log no instalador e no alvo).

- **v1.9 — "a spec estrutural: boot selado por hash + geometria da UI +
  autohide de fábrica + Super + wallpaper sem poeira"** (spec v1.9 do
  dono, 5 módulos obrigatórios, out/2026):
  - **(M1.1) BOOT SELADO — o "premature end of file /@/boot/vmlinuz-linux"
    morre por CASTELO**: além da recópia byte-a-byte v1.8.2, a fase final
    do `elite-install-stage` agora faz (a) **flush total** (`sync` +
    `sync -f /boot`) antes e depois de tudo; (b) **verificação por
    sha256 fonte==alvo** de CADA vmlinuz no chroot final (re-checagem
    tardia — pega corrupção que só aparece depois da cópia; hash
    registrado no log como trilha de auditoria); (c) **mkinitcpio -P**
    (TODOS os presets, não só o bore) com GATE DURO — saída ≠0 ou
    initramfs <1 MiB reprova a instalação (o `|| true` que engolia
    initramfs quebrado está morto); (d) **grub-mkconfig re-gerado no
    próprio stage** e validado (menuentry + vmlinuz presentes).
  - **(M1.2) CALAMARES TRANSPARENTE**: o `.desktop` da Elite lança o
    `calamares-elite-log` — um **foot com `tail -F` do session.log abre
    ANTES do instalador** (log ao vivo, fim do botão de debug escondido)
    e no fim o log completo vai para **/var/log/calamares.log** do
    instalador E é copiado para o **/var/log do sistema instalado**
    (auditoria pós-boot). O launch.sh upstream segue intocado.
  - **(M2) TOP BAR**: **linha fantasma morta** — a "linha horizontal solta"
    sob a barra ERA o `border-bottom: 1px` (removido); **padding vertical
    simétrico** (2px/2px + altura 34→36) centraliza os ícones no eixo Y
    (nada esmagado contra o teto); **tray com 14px de respiro** à direita
    (estava colado na borda); **ARCH permanece lançador EXCLUSIVO** do
    canto superior esquerdo.
  - **(M3) DOCK**: **(3.1) hover CENTRALIZADO** — o desalinho tinha 2
    causas, ambas mortas: o zoom por `font-size` (mudava a caixa no hover)
    e o `border-bottom: 3px` do indicador `.active` (empurrava o ícone p/
    cima). Agora: bounding box único (`min-height/min-width 48px`),
    padding simétrico, `box-shadow inset` no indicador (zero shift);
    **(3.2) escala FIXA 36px** (taskbar) e glifos 30px fixos, sem estado
    de zoom; **(3.3) ícones reais** p/ Instalador/LACT/btop/mpv: PNGs flat
    em `/usr/share/pixmaps/elite/` + overrides `.desktop` com `Icon=`
    ABSOLUTO (resolução à prova de tema incompleto) + `StartupWMClass`
    (btop ganhou `--app-id=btop` p/ casar no taskbar); **(3.4) Launchpad
    saiu da dock** — botão Arch EXCLUSIVO da barra superior; **(3.5)
    AUTOHIDE PADRÃO de fábrica**: modo *peek* com tira de 6px na base
    (config gerado em tmpfs a partir do config ATUAL do usuário — pins do
    craft-pin inclusive — com TODOS os on-click virando "show": clique na
    tira revela, sem abrir app por engano), **W-S-d alterna**, craft-bars
    religa no modo vigente em ≤5s, notify-send confirma o estado.
  - **(M4) TECLA SUPER**: Super sozinha abre o Launchpad (o mesmo menu de
    apps do botão Arch — convenção GNOME/Windows).
  - **(M5) WALLPAPER SEM POEIRA**: o JPEG da v1.7.1 tinha ruído/granulação
    de compressão ("impressão de poeira"). Novo padrão: arte **vetorial
    flat** (fundo preto AMOLED, cristas low-poly na escada de superfícies
    do rice, lua com aro mauve) em **PNG lossless 4K** — zero artefato de
    compressão POSSÍVEL. Contratos novos: **paleta ≤16 cores** (a métrica
    anti-poeira — foto/compressão tem milhares), **céu 100% flat** (1 cor
    por patch amostrado), preto ≥40%, sha256 anti-tamper.

- **v1.8.2 — "o install que não morre no copytoram + os flagrantes do
  áudio/fotos do dono"** (burn test v1.8.1: 2 tentativas de instalação
  mortas no job 36 — termbin `iy38` — e 6 áudios + 12 fotos registrando
  o uso real):
  - **(A) INSTALL QUE MORRIA COM copytoram=y (o padrão da ISO)** — o
    `elite-install-stage` da v1.8 mantinha a fonte do kernel presa ao
    `/run/archiso/bootmnt`, mas com copytoram o archiso **desmonta o
    bootmnt** depois de copiar o conteúdo para a RAM: TODA instalação
    real (Ventoy ou USB normal) caía no `exit 1` "nenhum vmlinuz em
    /run/archiso/bootmnt (copytoram?)" — exatamente o "Installation
    Failed / External command finished with errors" sem explicação que o
    dono fotografou. **CURA — fonte em CASCATA**: (A) bootmnt (boot
    copytoram=n/rescue) → (B) `/boot` do PRÓPRIO live (o squashfs
    airootfs carrega `/boot/vmlinuz-*` e é o root em uso — sobrevive ao
    copytoram por definição) → (C) backing do loop do airootfs via
    `losetup -o BACK-FILE` + `mount -o loop,ro` (cobre ISO inteira e sfs
    solto). A PROVA byte-a-byte da v1.8 fica intacta; a falha alta agora
    é só quando é REAL (sem fonte E sem kernel são no `/boot` do alvo —
    e o log diz o motivo). Alvo com kernel são do unpackfs segue com
    aviso em vez de morrer.
  - **(B) BOTÃO GIGANTE GTK4 (LACT/Papers/pwvucontrol com um círculo
    vermelho enorme)** — fonte primária libadwaita: o círculo é o
    `> image` DENTRO do button; o css da v1.6.1 pintava o button e
    perdia na especificidade do tamanho. CURA: neutraliza o `> image`
    (bg/padding/glyph em todos os estados) e pinta o trio no
    `windowcontrols > button.*` com especificidade igual à do tema
    (user css carrega depois — empate é do usuário).
  - **(C) DOCK COM OS 3 PINS INVISÍVEIS** — `craft-pin-status` não estava
    na lista `file_permissions` do apply-overlay: subia 0644, o exec do
    waybar morria em Permission denied e a dock nascia com só 2 ícones
    (flagrante IMG_20261024_114720). Entrou na lista (0755). E o reload
    do `craft-pin` trocou SIGUSR2 (que no waybar 0.15 recarrega SÓ o
    CSS — "fixou, mas a dock não atualizou") pelo reinício real do
    waybar: o craft-bars devolve as duas barras em ≤5s já lendo o config
    novo. Dock menor (62→54px, glifos 30→27, zoom 36→32, ícones do
    taskbar 40→34) — o "menor e mais perto do meio" do áudio.
  - **(D) CONECTIVIDADE GUI (áudio: "impala e bluetui… eu não sei
    utilizar esses programas que são terminal… quero mais bonito e mais
    fácil")** — `nm-applet` + `blueman` voltam (tray + GUIs completas);
    `craft-connect` abre `nm-connection-editor`/`blueman-manager` (os
    TUIs Rust ficam como fallback power-user); W-n/W-S-b apontam para as
    GUIs. **Menus cross-dismiss**: abrir Sessão fecha Rede e vice-versa
    (nunca dois dropdowns empilhados — áudio 21 e 24/out).
  - **(E) LACT com daemon de fábrica (E17)** — "Service Status: inactive"
    virou história: `systemctl enable lactd.service` no build nasce no
    /etc do airootfs e LIVE + INSTALADO herdam; gate duro se o unit
    sumir. **BRAVE com titlebar GTK**: `Local State` preseedado
    (`custom_chrome_frame: false`) — os botões mac do rice aplicam ao
    Chromium também.

- **v1.8.1 — "a ISO que o Ventoy aceita + o terminal que abre + o debloat
  sistêmico"** (burn test v1.8.0 do dono: Ventoy recusou a ISO — foto
  IMG_20261023_234603 — e o "Abrir terminal aqui" do Thunar morreu):
  - **(A) A v1.8.0 ERA TRUNCADA — a "compressão zstd nova" era um buraco**:
    matemática sobre a foto do dono (2 números = PVD × asset): o PVD
    interno da ISO declarava **2.969.681.920 B (2,77 GiB)** e o asset
    publicado tinha **1.669.742.510 B (56,2%)**. O release job da #82
    baixou o artifact truncado (a MESMA run cujo verify flagrou blob
    flaky), fez upload sem verificar, e o split <2 GiB celebrou o
    truncamento como leveza. O Ventoy recusou na hora — corretamente.
    **CURA EM 3 CAMADAS**: GATE 1 pré-upload (`sha256sum -c` do artifact
    vs o sha256sums.txt que o build.sh sela DENTRO dele); GATE 2
    pós-upload (re-download do asset publicado + `sha256sum -c
    --ignore-missing` — o blob do GitHub tem de ser a ISO selada);
    **contrato PVD na suíte** (range-request de 33 KiB → parse do
    descriptor ISO9660 → tamanho declarado == bytes publicados — matemática,
    não confiança; pega até truncamento que passe nos hashes). O corpo da
    release agora traz a tabela de integridade.
  - **(B) TERMINAL DO THUNAR — a cura no elo certo**: a mensagem do dono é
    o string do fonte (`exo-execute.c`: "Could not find fallback
    TerminalEmulator application"). Fonte primária exo 4.20 lida: a cadeia
    é (1) `xfce4-mime-helper` (não existe na ISO), (2)
    **`~/.config/xfce4/helpers.rc`** → `g_find_program_in_path(valor)`,
    (3) `xfce4-terminal.desktop` — **deletado pelo debloat** → erro. CURA:
    `elite/airootfs/etc/skel/.config/xfce4/helpers.rc` com
    `TerminalEmulator=foot` — arquivo FLAT (o exo PREPENSA o cabeçalho
    `[Default]` antes de parsear — duplicado quebraria) e valor = NOME DE
    BINÁRIO. `g_spawn_async(working_directory)` → o foot abre NA PASTA.
  - **(C) DEBLOAT SISTÊMICO (pedido: "pra ir além, não só em pacotes")** —
    só o provadamente inerte, com gate duro (falha no build, nunca no
    boot): **E15** pod `/usr/share/locale` fora de pt*/en* (locale.alias e
    l10n/ ficam), `locale.gen` → exatamente `en_US.UTF-8` + `pt_BR.UTF-8`
    com re-gen do archive (dono pt-BR ganha a locale de fábrica; LANG não
    muda — rice intacto; auto-cura se locale-gen falhar), e
    man/info/doc/gtk-doc fora (**licenças ficam** — compliance; páginas
    voltam reinstalando o pacote). **E16**: papirus-icon-theme embarca 6
    variantes (~100-160 MB cada); o rice usa **Papirus** (menu labwc) e
    **Papirus-Dark** (GTK/fuzzel) — as outras 4 (Papirus-Light, ePapirus×3)
    saem, com gate duro das 2 vivas. **journald com teto** (drop-in:
    SystemMaxUse=100M / RuntimeMaxUse=64M — disco do instalado e RAM do
    live protegidos, rotação só). O que NÃO foi tocado de propósito:
    kernel/firmware (hardware), toolchain+headers (dkms do NVIDIA no
    update do kernel), hicolor (fallback de ícones), toolchain de build.
  - **(D) SWEEP anti-debloat**: grep de todos os binários removidos no
    skel + usr/local/bin — a ferida do terminal era a ÚNICA viva (só um
    comentário histórico no rc.xml:14). +25 contratos novos na suíte.
- **v1.8 (branch v2 — "refaz o quebrado, mantém o que funciona"): o BOOT
  com PROVA + o desktop da SPEC do dono** (burn test v1.7.0, fotos
  23/out — GRUB "premature end of file" no sistema instalado):
  - **(A) A RECORRÊNCIA DO BOOT, CAUSA-RAIZ REAL**: o elite-install-stage
    recopiava os kernels com `cp -f … &&` — **exit code ignorado**. Qualquer
    falha de cópia no rig (disco cheio, OOM killer durante o install, erro
    btrfs) deixava o **kernel truncado do rsync no lugar**, a instalação
    "terminava feliz" e o GRUB morria — exatamente a foto
    IMG_20261023_180301. E o gate do CI nunca viu porque **rodava cp
    PRÓPRIO** no passo [6/8] em vez do script real — divergência gate⇄rig
    (gate verde ⇄ rig morto). **CURA 1**: o stage agora é AUTO-VERIFICANTE —
    cópia em arquivo temporário → conferência de tamanho → `cmp`
    byte-a-byte → promoção atômica (mv) → sync → **re-`cmp` no arquivo
    promovido** → marcador; QUALQUER desvio = `exit 1` = o Calamares mostra
    "Installation Failed" COM o motivo (df no log). **CURA 2**: o gate [6/8]
    EXECUTA o `elite-install-stage` REAL do rootfs da ISO contra o alvo
    btrfs, com o "pendrive" bind-montado no caminho exato do live
    (`/run/archiso/bootmnt`), rc checado via PIPESTATUS + prova
    independente de integridade (BORE truncado = CI vermelho).
  - **(B) DESKTOP v3 — a SPEC DO DONO, letra por letra**: canto superior
    esquerdo = **ARCH → menu de aplicativos** (como o Archcraft tem) +
    **botões úteis na sequência**: print (craft-shot região), **wi-fi/
    redes/conectividade num geral** (cabo+Wi-Fi+Bluetooth → craft-connect)
    e **liga/desliga/reset** (craft-power); **relógio no CENTRO EXATO**;
    direita só o status que sobra (música quando tocando, café invisível
    desligado, volume, tray). O que já funcionava NÃO foi mexido: glifos
    JSON-escape (v1.1), um-só-ícone-de-rede (v1.4), mpris auto-hide (v1.0.3),
    tray íntegro (v1.6), clock craft→swaync (v1.0.4).
  - **(C) DOCK v3 — macOS/COSMIC de verdade**: pins de fábrica (Launchpad,
    Terminal, Arquivos, Navegador, Screenshot) agora têm **INDICADOR DE
    PROGRAMA ABERTO** — o "pontinho" do macOS: cada pin é módulo custom
    `return-type: json` alimentado pelo **craft-pin-status** (1 `pgrep -x`
    por pin a cada 3s — SEM rede/jq; o contrato anti-exec da v1.6.2 virou
    NARROW: único exec permitido na dock = craft-pin-status, qualquer outro
    = CI vermelho). `class="running"` acende a barra 3px na base do ícone
    (CSS inset shadow — zero shift de layout); `craft-pin add/rm` gera pins
    com indicador automaticamente (e valida apóstrofo no tooltip). Janelas
    abertas (fixadas ou não) seguem no taskbar à direita do separador —
    clique foca, meio fecha, dir minimiza. Limite honesto documentado: o
    waybar 0.15 não expõe ativação externa de toplevel (e não há wlrctl no
    Arch), então o clique no pin abre nova instância — o FOCO das janelas
    é pelo taskbar. Zoom de hover macOS mantido (30→36px, .18s bezier).
  - **(D) WALLPAPER**: mantido o da curadoria internet da v1.7.1 (Unsplash,
    ondas de seda roxo/preto, 4K JPEG 0,43 MB — IPS-friendly, sha256
    contratado). O dono rejeitou gerados por IA — política permanente agora.
  - **(E) Branch e limpeza**: branch **v2** criada a partir do main
    (levando TUDO que funciona: instalador v1.7, lock v1.7, menu v1.7,
    probe v1.7.1, wallpaper internet). Limpeza de artifacts/releases
    ANTIGOS no GitHub exige PAT (reenviar) — comandos prontos no relatório;
    nada do que funciona é apagado até a v2 passar no burn test.
  - **(F) Suíte**: contratos novos para o cluster esquerdo, pins-json,
    craft-pin-status, CSS .running, PINLINE do craft-pin, verificação do
    kernel no stage (cmp/re-cmp/tmp + nogrep do cp cego) e gate executando
    o script real. Executada localmente: GO.
  - **(G) A CLASSE "SUBIU SÓ O WALLPAPER" NOMEADA E MORTA (runs #79 e #80
    do CI, flagrante pelo probe da v1.7.1)**: o waybar 0.15 trata
    propriedade CSS inválida como **FATAL** (exit 1 no parse) e o rice
    carregava TRÊS propriedades GTK4-only: `icon-size` (style.top.css
    §tray, v1.6), `max-width` (style.dock.css §separador, dock v3) e
    `width` (mesma regra, linha seguinte). As 2 barras morriam em LOOP
    ETERNO no boot — EXATAMENTE o que o dono via no rig desde a v1.6.x.
    A "intermitência" era o repo rolling: builds de dias diferentes
    puxaram waybar 0.14 (erro = warning ignorável) vs 0.15 (fatal).
    **A CAÇADA EM 2 BOOTS**: o parser do GTK aborta no PRIMEIRO erro de
    cada arquivo — a run #79 (BARS_EXITS=32) revelou os 2 primeiros;
    curados, a #80 (BARS_EXITS=18) revelou o `width` — e PROVOU a cura
    do topo: a barra superior inteira passou o boot com ZERO mortes
    (`-gtk-icon-transform: scale(0.75)` é válido, intenção da v1.6
    mantida; `min-width` parseou limpo antes do erro da linha seguinte).
    **CURA DEFINITIVA**: `font-size: 1px` + `min-width: 1px` no
    separador (o módulo é um espaço " " — glifo encolhido + piso = 1px
    exato). **CONTRATOS (9)**: os 2 CSS não podem ter NENHUMA
    propriedade GTK4-only (`icon-size`, `max-width`, `max-height`,
    `width`, `height` crus) — a suíte caça a classe, não os nomes — +
    os equivalentes válidos contratados com a prova de cada um. A main
    caiu com a MESMA assinatura dupla (#78, BARS_EXITS=53) — a v1.7.2
    leva os mesmos 9 contratos (1138→1141 peças · GO).

- **v1.7.1 (local, ainda sem release) — "a sessão que o CI nunca viu" +
  wallpaper da internet (burn test da v1.7.0, fotos do dono 23/out)**:
  o dono bootou a v1.7.0 e o desktop subiu DE NOVO só com o wallpaper
  (sem menu bar, sem dock) — a MESMA classe da v1.6.2. As 5 fotos de
  hoje provaram o resto: o instalador da v1.7 FUNCIONA (8%, "Filling
  up filesystems" — a classe do `${kv}` morreu de verdade) e o lock
  está são; o que morre é a SESSÃO. Curas, com contrato:
  - **(A) O GATE DO CI ENTRA NA SESSÃO GRÁFICA**: o verify boota a ISO
    e parava no LOGIN — a classe "barras mortas" era invisível por
    construção. Agora o **`elite-session-probe.service`** (system,
    WantedBy=graphical.target, ExecStartPre sleep 60) roda
    **`elite-session-probe`** 60s após o target: colhe
    WAYBAR_COUNT/SWAYNC_COUNT/BARS_EXITS/BARS_RESTARTS, os processos
    waybar vivos, o tail do bars.log de todos os usuários, memória e
    versões — e imprime um bloco MARCADO (ELITE_PROBE_BEGIN/END) no
    console (= serial no QEMU) e no journal. O **build.yml (verify)**
    e o **qemu-boot-test.sh** esperam o bloco e COBRAM:
    `WAYBAR_COUNT ≥ 2` e `BARS_EXITS = 0` — sessão de pé sem as duas
    barras = CI VERMELHO ANTES da ISO. Probe ausente (QEMU headless
    sem sessão) = informativo honesto, sem falso vermelho. Inofensivo
    no rig real: one-shot, sem escrita, exit 0 sempre (nunca vira
    unidade failed — o gate "nenhuma unidade em failed" não mente).
  - **(B) FIM DO SILÊNCIO DO GUARD**: o guard do autostart
    (`command -v waybar && [ -x craft-bars ]`) falhava SEM NENHUM
    rastro — waybar ausente no squashfs ou craft-bars 0644 = zero
    barras e zero evidência. Agora cada ramo do guard escreve no
    MESMO `~/.cache/elite/bars.log` do supervisor (com hora), e o
    **craft-bars registra o EXIT CODE de cada morte** (`waybar %s
    SAIU exit=%d` — 0 = morte limpa, ≠0 = crash, 137 = OOM killer):
    a "morte calada" deixou de existir como categoria.
  - **(C) WALLPAPER: volta a curadoria da INTERNET** (dono: "eu queria
    um wallpaper da internet mesmo, esses gerados são muito ruim"). O
    fractal IA da v1.7 saiu; entra abstrato 3D REAL da internet
    (Unsplash, licença de uso livre): ondas de seda roxo/preto,
    3000×1688 nativo → 3840×2160 (Lanczos + UnsharpMask), **JPEG q93 =
    0.43 MB** (o PNG 10.7 MB custava +19 MB de ISO — higiene volta com
    contrato de teto 2 MiB). Métricas medidas: 0.24% de (0,0,0) (o
    cuidado IPS da v1.7 sobrevive), luma média 32.6, topo luma 5.7 <<
    média (menu bar assenta em zona escura). Contratos: sha256
    anti-tamper do arquivo + mime real + largura 4K + faixas de luma.
    Fallback em cadeia: wallpaper.jpg → wallpaper.png (custom do
    usuário) → preto. Curadoria alternativa (3 candidatos avaliados e
    rejeitados/backup) guardada fora da ISO.
  - **(D) Suíte**: contratos novos para TODAS as camadas acima (probe
    + service + symlink do wants + guard logging + exit code +
    apply-overlay 0755 + gates greppando o bloco) e wallpaper
    re-ancorado. Executada localmente: GO.

- **v1.7 (main) — "não aceito nada além da perfeição": o pacote completo
  do burn test da v1.6.2 + os pedidos de UX do dono** (fotos e relato,
  out/2026). v1.6.3 nunca foi releaseada — todo o seu conteúdo entra
  aqui, junto com as curas novas:
  - **(A) O INSTALADOR (a cura mais importante — "o instalador está
    quebrado")**: a máquina real falhava com **"Could not run command.
    The commands use variables that are not defined. Missing variables
    are: kv,kbase,kv,kbase,v,v."** — CAUSA-RAIZ PROVADA com o doc do
    PRÓPRIO Calamares (header do shellprocess_kms.conf, embarcado):
    *"It is not possible to get an un-escaped $ in the shell command
    (either the command will fail because of undefined variables…)"* —
    o Calamares expande TODO `$var`/`${var}` de um `command:` inline
    contra ROOT/USER/LANG + global storage ANTES de rodar o shell. O
    `shellprocess_btrfs.conf` da Elite (v1.1) usava variáveis DE SHELL
    (`${kv}`, `${kbase}`, `$v`, `$ELITE_GPU`) dentro do YAML → morte na
    primeira instalação real. O bug dormiu 6 versões: o v1.5 morria
    antes (unpackfs) e o gate do CI **reproduz a cadeia FORA do
    Calamares** (define as variáveis à mão) — às cegas para a classe.
    **CURA**: a lógica inteira (recópia btrfs dos vmlinuz +
    especialização por GPU AMD/NVIDIA + initramfs do BORE + keyring do
    alvo) agora vive no **`elite-install-stage`** — um script real
    (semântica de shell de verdade, shellcheck+bash -n na suíte) que o
    Calamares chama com `/usr/local/bin/elite-install-stage ${ROOT}`.
    **CONTRATO NOVO**: scanner varre os heredocs de .conf do Calamares
    e só aceita a allowlist do Calamares (ROOT/USER/LANG = shellprocess;
    LOCALE = packages; SERIAL/RANDOM/PHRASE = bootloader) — qualquer `$`
    de shell no YAML = CI vermelho. A classe está extinta.
  - **(B) Barras SUPERVISIONADAS — craft-bars (novo)**: a sessão subiu só
    com wallpaper — as duas instâncias do waybar morreram caladas SEM
    deixar stderr (o labwc não redireciona o autostart) e o gate de boot
    do CI é serial e para no LOGIN — nunca vê a sessão gráfica (por isso
    passou verde). Cura em 2 frentes: (1) **supervisão** — o craft-bars
    vigia as duas barras por pgrep e reinicia em ≤5s (loop com sleep,
    ~0% CPU, ~1 MB: barra que morrer VOLTA — a classe "boot mudo" está
    morta por construção); (2) **forense** — o stderr do waybar agora vai
    para `~/.cache/elite/bars.log` com teto de 1 MiB (diretriz v1.6.2:
    nada cresce sem limite) — se voltar a acontecer, o log traz a
    mensagem EXATA (`cat ~/.cache/elite/bars.log`). O autostart não sobe
    waybar direto (contrato: delega ao craft-bars).
  - **(C) Menu raiz curado — "deixa só os importantes", "sem muita
    complexidade"**: 15 itens, todos com ícone provado. **Saíram** (por
    decisão do dono): as ferramentas do antigo submenu Cockpit (todas
    CONTINUAM instaladas — vivem no Launchpad, que busca e categoriza:
    a resposta honesta para "pastas de programas"), a lista de janelas
    que o botão direito abria, o item de reconfiguração do compositor
    (ferramenta de dev) e o de encerrar a sessão do compositor (mis-click
    perigoso). **Ficaram**: apps do dia-1 (Navegador, Arquivos, Terminal,
    Editor, PDF, Calculadora — todos PROVADOS no rootfs embarcado:
    nano vem do base linha 76; brave-origin, papers, qalculate, thunar
    instalados) + Atualizar/Limpeza (os eleitos) + Launchpad/Fixar +
    Lock/Tempo/Sessão + Reboot/Desligar. **Contratos**: todo Execute =
    binário real na ISO; fixture bidirecional de ícones; zero item sem
    icon=.
  - **(D) Ícones VISÍVEIS ("coloca ícone nas coisas e principalmente
    visíveis")**: no labwc o tamanho do ícone de menu É a altura da fonte
    do item — fonte do MenuItem era 10 (ícones ~14px, a foto do dono);
    agora **12** (itens ~27px, ícones ~17px) + padding.x 8. Fonte
    primária: src/menu/menu.c `ICON_SIZE = menu_item_height -
    2*padding_y` e src/theme.c `menu_item_height = font_height +
    2*padding_y` — o padding cancela; a fonte manda.
  - **(E) Botão direito decidido ("decide pra mim")**: **direita = menu
    raiz curado** (padrão universal); a lista de janelas do botão
    direito EXTINTA (o dock é o comutador de janelas); clique esquerdo
    no desktop ficou limpo (zero menu acidental); **scroll segue
    trocando de workspace** (o gesto que o dono prefere). Contratos nos
    4 comportamentos.
  - **(F) Tela de lock (as 3 fotos do burn test)**: (1) a marcação Pango
    aparecia LITERAL no placeholder — o hyprlock NÃO parseia markup no
    placeholder (o example.conf oficial usa texto plano) →
    placeholder/fail/check agora em TEXTO PLANO (as cores já são
    propriedade própria: check_color/fail_color/font_color); (2) o
    avatar "A" (logo do Archcraft) saiu — lock minimalista: fundo
    desfocado + relógio + data + usuário + campo; (3) relógio saiu da
    borda (colidia com a light bar do monitor) → 300px do topo, data a
    440 — terço superior com respiro em qualquer resolução.
  - **(G) Wallpaper novo — "qualidade máxima e melhor em monitores IPS"**:
    conceito trocado. O v1.3 era AMOLED (62% de preto puro — no IPS preto
    puro vira cinza morto). O novo é **fractal luminoso GERADO por IA
    para o projeto** (zero licença de terceiros): flor de fractal em
    fitas violeta/mauve sobre plum profundo, 3840×2160 (upscale Lanczos
    de 2048×1152 nativo) + UnsharpMask leve + grão fino determinístico
    (±2 níveis) contra banding. **Métricas com contrato**: 0.00% de
    pixels (0,0,0) (≤5%), luma média 36.7 (15-60 — dark premium), floor
    p1=13 (≥8 — sem crush), strip do topo 22.5 ≤ média (a menu bar
    assenta).
  - **(H) Correção honesta de registro (v1.6.2)**: o relatório anterior
    citava o EasyEffects como maior consumidor de RAM em standby —
    **ele NÃO está na ISO** (prova: pacman db do rootfs embarcado; saíra
    na curadoria; o bloco do autostart é guardado por `command -v` e
    nunca executa — zero RAM, vivo se o usuário instalar:
    `pacman -S easyeffects` e o autostart sobe o serviço sozinho). O
    campeão de standby residente é o trio waybar×2 + swaync (~60-90 MB
    somados) — todos com por quê.

- **v1.6.2 — A AUDITORIA DE "PERFEITO, OTIMIZADO, LIMPO E SEM
  MEMORY LEAK?"** (questionamento do dono antes da build final): auditoria
  item a item em código + fonte primária; **um buraco real encontrado e
  curado com a receita do próprio upstream**:
  - **(A) O ÚNICO crescimento sem limite do sistema: o histórico do
    clipboard**. O `craft-shot area` faz `wl-copy` do PNG → o watcher
    `wl-paste --watch cliphist store` grava o screenshot INTEIRO em
    base64 no DB (`~/.cache/cliphist/history`) — sem poda, meses de uso
    = dezenas de MB e o menu W-v arrastando. **Cura = a receita LITERAL
    do README do cliphist** (sentriz/cliphist, verificado no clone da
    fonte 0.7.0): "Run this from a timer to delete entries older than
    30 days: cliphist wipe -older-than 720h" — e o `wipe` já COMPACTA o
    DB (changelog 0.7.0: "compact db after wiping"). Duas camadas (o
    padrão das 4 camadas do keyring): camada 1 — poda síncrona no login
    (autostart, antes do watcher, cobre live/sessão sem user manager);
    camada 2 — `cliphist-prune.timer` do user manager (diário,
    `Persistent=true`, habilitado no skel via `timers.target.wants` —
    cobre uptimes de semanas sem relogin).
  - **(B) MEMÓRIA/ESTABILIDADE — o que a auditoria PROVOU que já estava
    são**: waybar com **zero módulos `exec`** (as duas barras são 100%
    módulos nativos; apenas 2 intervals: mpris 10s, clock 60s — a classe
    clássica de leak/CPU-burn do waybar é script polling, que aqui não
    existe; agora é contrato de não-regressão); o crash da dock
    (waybar#5051, módulos `image`) extinto desde v1.6 por construção
    (glyphs); **nenhum processo residente criado pelos botões** — o
    modelo toggle da família craft-* (power/connect/drawer/idle) é
    sempre one-shot ou kill-before-start: `craft-idle start` faz
    `pkill -x swayidle` ANTES do `exec` (daemon único, sem empilhar);
    nwg-drawer/fuzzel/impala/bluetui morrem no fechar; hyprlock só
    existe durante o lock; swayidle ~2MB; o cardápio de daemons
    permanentes da sessão é enxuto e cada um tem por quê (NM, wpa_supp,
    bluez, swaync, udiskie, swaybg, 2×waybar, swayidle, cliphist watcher,
    polkit, keyring).
  - **(C) REDE — a prova anti-travamento**: applets GTK (nm-applet/
    blueman) fora desde v1.1 (zero daemon GTK de graça); **ModemManager
    REMOVIDO da ISO** (pacote + wants — o daemon de polling serial que
    faz CPU-twitch); VPN plugins fora; cloud-init/vbox/vmware/hyperv/
    cups/pcscd/ufw: wants removidos no build ([7] do apply-overlay) —
    10+ serviços que nada fazem num PC físico não sobem; `iwd`/
    `dhcpcd` instalam da base mas **ficam inertes** (serviços não
    habilitados — zero RAM, o NM+wpa_supplicant é o stack ativo);
    BBR+fq ativo com auto-cura (firstboot confirma e degrada para cubic
    se o kernel não oferecer); toggle na central de rede contratado
    (2ª chamada fecha — menu nunca empilha). Bônus achado na auditoria:
    o SwayNC (clique no relógio) já tem **toggle de rádio Wi-Fi/BT**
    (`nmcli radio` / `bluetoothctl power`) — o "liga/desliga" existe
    fora do impala também.
  - Suíte: 1035 → **1044 contratos** · 0 falhas · GO.

- **v1.6.1 (main) — AS 3 FRENTES DO QUESTIONAMENTO DO DONO** ("o botão
  do arch abre e fecha a gaveta? os botões mac valem para TODOS os
  programas, inclusive os que eu instalar? consigo controlar o tempo
  de idle?") — tudo verificado em código + pesquisa de fonte primária,
  e os 3 buracos fechados com contrato:
  - **(A) GAVETA COM TOGGLE**: o ARCH no canto esquerdo ABRIA o
    Launchpad, mas o 2º clique não FECHAVA (craft-drawer sem toggle —
    o modelo craft-power/craft-connect não tinha chegado nele). Cura:
    `pgrep/pkill -x nwg-drawer` — 2ª chamada fecha. Contratado.
  - **(B) BOTÕES mac EM TODO O SISTEMA — a cobertura provada por
    fonte primária**: labwc-config(5) oficial (fetch do master):
    `<decoration>server` (já setado no rc.xml) vale para janelas
    xdg-shell; Chromium/Brave IMPLEMENTA xdg-decoration
    (`ui/ozone/…/xdg_toplevel.cc`: `zxdg_decoration_manager_v1` +
    `MODE_SERVER_SIDE` — o Brave recebe a titlebar SSD do labwc);
    GTK3 pede modo SERVER para janelas normais (gdkwindow-wayland.c,
    protocolo kwin server-decoration que o wlroots atende); XWayland
    é decorado pelo WM. **O buraco restante**: apps CSD — GTK3 com
    headerbar pede CLIENT, e o GTK4 NÃO implementa protocolo de
    decoração NENHUM (gdksurface-wayland.c: zero binds — CSD sempre;
    o próprio labwc-config(5) avisa: "not always possible to turn off
    client side decorations"). É exatamente onde nascia o "todo o
    sistema tinha botões menos X". **Cura**: `gtk.css` do usuário
    (GTK3 `.titlebutton` + GTK4 `windowcontrols`) pinta o MESMO trio
    traffic-light dos PNGs do labwc (círculo colorido sempre visível,
    glifo escuro no hover, cinza `#5b5b60` no backdrop) — vale para
    QUALQUER app GTK que o usuário instalar depois. Limite honesto
    documentado: app que desenha botões fora do toolkit GTK (não-GTK,
    CSD caseiro) está fora do alcance de qualquer compositor.
  - **(C) IDLE AJUSTÁVEL — "em quanto tempo o Pc entra em idle?"**:
    tempos saem do hardcode (600/900s) e vão para
    `~/.config/elite/idle.conf`; novo `craft-idle` (menu de presets no
    fuzzel — 2/5/10/15/30/60min ou "Nunca"; mostra o valor atual no
    prompt; fallback de terminal sem fuzzel) escreve o conf e
    REINICIA o daemon NA HORA (sem relogin); item "Tempo para travar
    a tela…" no menu raiz (mouse-first). A receita swayidle INTEIRA
    (lock + DPMS wlopm + resume + before-sleep) vive num lugar só
    (craft-idle start — o autostart só delega). Fluxo preservado e
    explicado no conf: X min → hyprlock; X+5 → tela APAGA (DPMS
    real); input → acorda JÁ no lock; suspend → lock antes.
  - Suíte: 1010 → 1035 contratos · 0 falhas · GO.

- **v1.6 (main) — A ISO INSTALÁVEL: o burn test v1.5 virado do avesso**
  (forense com fonte primária: log Calamares do dono via termbin [9z69],
  foto do rig analisada por VLM em 3 níveis de zoom, ISO v1.5 baixada do
  release [sha256 conferido — a ISO estava ÍNTEGRA], squashfs extraído e
  inspecionado, código-fonte do Archcraft upstream e do Calamares 3.4.2).
  - **(A) INSTALADOR — CAUSA-RAIZ PROVADA E CURADA (o bug que impedia a
    instalação no rig do dono)**: com Copy to RAM (default da Elite em
    TODAS as entradas de boot), o `launch.sh` do Archcraft REESCREVE o
    `unpackfs.conf` com `sed "s|…/x86_64/vmlinuz-linux|/usr/lib/modules/
    $KERNEL/vmlinuz|g"`. O padrão `vmlinuz-linux` casa como PREFIXO do
    nosso kernel renomeado (`vmlinuz-linux-cachyos-bore`) e deixa o
    sufixo órfão → source `/usr/lib/modules/7.3.0-2-cachyos-bore/
    vmlinuz-cachyos-bore` — arquivo INEXISTENTE (o real é `vmlinuz`,
    sem sufixo — verificado no squashfs) → Calamares aborta em
    "Configuração incorreta do unpackfs". O conf dentro da ISO estava
    CORRETO; o gate `verify-install` nunca pegou porque reproduz o
    Calamares manualmente — não roda o `launch.sh`. **Cura [E5a2]**:
    o customize alinha o padrão do sed do launch.sh ao kernel BORE
    (`boot/x86_64/vmlinuz-linux-cachyos-bore`); **Gate novo [1c/8]** no
    verify-install: extrai o bloco copytoram do launch.sh REAL da ISO,
    roda com `uname` FALSO (kver da ISO), e valida TODOS os sources do
    conf reescrito — a regressão v1.5 está morta por contrato.
  - **(B) DOCK — o bug upstream do waybar #5051, provado por eliminação**:
    a dock v1.5 usava 3 módulos `image#` (ícones PNG) como pins; o waybar
    0.15.0 crasha EM SILÊNCIO no startup com 3+ instâncias do módulo
    image (race: update antes da realization do widget → pixbuf com
    janela nula → abort; fix existe SÓ no master — issue
    Alexays/Waybar#5051, commit 0729823). A barra superior (sem image)
    subia; a dock NUNCA subiu no rig — e os pins do craft-pin "sumiam"
    (iam pra uma dock morta; o dono só via os apps na grade do
    Launchpad). **Cura**: pins voltam a módulos `custom/` com glifo Nerd
    Font (o modelo v1.4, que o dono viu funcionar AO VIVO) — zero
    pixbuf, zero race; zoom 30→36px + pílula no hover; Brave central em
    peach. PNGs órfãos de pixmaps removidos (avatar fica — hyprlock).
  - **(C) ARCH de volta ao canto esquerdo** (burn test: o dono reportou
    "o ícone do Arch no canto superior esquerdo não foi carregado" —
    ausência vista como FALTA; a spec v1.5 que o removeu é revertida
    pela evidência). `custom/drawer` + `wlr/window` no modules-left — o
    modelo menu-bar macOS: marca à esquerda abre o Launchpad.
  - **(D) BOTÕES DE JANELA macOS TRAFFIC-LIGHT à direita** ("estilo
    macos, posicionamento windows padrão" — o pedido do dono): tema
    `Archcraft-Elite` com 14 PNGs gerados por supersampling (círculos
    12px em célula 24px): close `#ff5f57`, iconify `#febc2e`, max
    `#28c840` — cores REAIS do macOS (o mapeamento anterior tinha
    iconify=verde/max=amarelo, invertido vs macOS); hover com glifo
    (×/−/⤢) no próprio PNG; inativo cinza `#5b5b60`; `max_toggled` com
    símbolo de restaurar. Layout `icon:iconify,max,close` = ícone à
    esquerda + botões à DIREITA em ordem Windows. Overlay de hover do
    labwc desligado (alpha 00) — o glifo mora no PNG.
  - **(E) KEYRING/POLKIT — a pergunta do dono respondida com código**:
    "o que é isso de keyring que alguns programas pedem a senha?" —
    duas metades: (1) **polkit** (ações de sistema): rule nova
    `49-elite-desktop.rules` no padrão Ubuntu/Fedora — power/reboot/
    suspend (incl. multiple-sessions), timedated e NetworkManager sem
    senha para o usuário local ATIVO, com exceção explícita para
    `modify.global-system` (nada de wildcard — as rules upstream de
    udisks/NM continuam valendo); (2) **gnome-keyring** (o "chaveiro"):
    no login com senha o PAM do sddm já desbloqueia (upstream); no
    live/autologin, bootstrap no autostart cria o chaveiro com senha
    VAZIA (`gnome-keyring-daemon --unlock` lê do stdin; sem chaveiro,
    CRIA) — Brave/Wi-Fi param de pedir "desbloquear chaveiro".
  - **(F) RICE "outro nível" (o "tá muito seco")**: menu raiz com
    ÍCONES (`<showIcons>` + 15 itens com paths absolutos Papirus —
    verificados no squashfs da v1.5); menu de sessão do craft-power com
    ícones (protocolo dmenu NUL+icon+US, printf direto no pipe —
    variável shell descarta bytes NUL); tray da menu bar endurecida
    (itens SNI com cor/tamanho explícitos — o bloco cinza do burn
    test). Sombras 60/40, cornerRadius 12, Alt-Tab com miniaturas e
    snapping overlay mauve já estavam (v1.0.4) — agora com botões mac.
  - **Fixes de hygiene**: `actions/checkout@v5` no verify-install (o
    rename da v1.5.2 carregou um v4 — achado do agente deepseek na 1ª
    auditoria REAL da história, run #63); agentes deepseek+mimo
    auditaram a build de validação da v1.5.2 e publicaram 2 relatórios
    na branch agent-reports (primeiros desde 20/out).
  - **Suíte**: 1010 peças, 0 falhas (+29 contratos v1.6: E5a2, gate
    copytoram com uname falso, tema com 9+ assets, layout de botões,
    showIcons, ícones do menu/craft-power, rule polkit, bootstrap do
    chaveiro, glifos da dock, ARCH de volta, PNGs removidos).

- **v1.5.2 (main, pós-v1.5) — LIMPEZA PROFUNDA + OS TRÊS BURACOS SISTÊMICOS
  FECHADOS** (diretriz do dono: "os agentes do repositório devem analisar
  justamente os logs minuciosamente; esses erros não podem passar ou ser
  tratados como algo normal"). Forense feita com FONTES PRIMÁRIAS: logs
  completos (zip de jobs + artifacts de serial) das runs v1.5
  (39864937531) e v1.4 (39804335535), API do GitHub e arqueologia git.
  - **(a) Build verde com erro silencioso — GATE DE FORENSE DE LOG**
    (`scripts/log-forensics.sh`, novo): o log da v1.4 (VERDE, releaseada)
    contém **5 classes fatais literais** — `target not found:
    cachyos-keyring` ×2, `could not determine root mount point /`,
    `not enough free disk space` ×2, `signature from "CachyOS" is
    invalid` ×2, `failed to synchronize all databases` — e a ISO saiu sem
    o keyring (causa-raiz do burn test). O gate roda em TODA build
    (`build.yml`: `tee build-output.log` + step de forense) e transforma
    padrão fatal em run vermelha ANTES do release. Validado contra a
    história real: log v1.5 → exit 0 (12 benignos auditados); log v1.4 →
    exit 1 (5 fatais). Whitelist de benignos DOCUMENTADA (grub-editenv em
    chroot, mtab journal-nocow, downloader com recuperação de baseline
    libyuv/ELITE-BUMP…), condicionais com fronteira (downloader sem
    recuperação = fatal; `command failed` fora de contexto grub = fatal).
  - **(b) Relay dos agentes MORTO desde a v1.1 — CAUSA-RAIZ ACHADA NO
    LOG**: o job `relay-agents` nunca despachou nada — `gh workflow run`
    sem `--repo` num job SEM checkout caía em `fatal: not a git
    repository` e o `if/else` abafava ("não derruba a build"). Zero runs
    de `agents.yml` na história; os 8 relatórios da branch
    `agent-reports` eram todos de execuções locais de 20/out. Cura:
    `--repo "$GITHUB_REPOSITORY"` explícito; dispatch falhou = job
    VERMELHO (`set -euo pipefail`); `needs: [build, verify,
    verify-install]` + `if: always()` — os agentes agora auditam o log
    COMPLETO e auditam TAMBÉM runs que falharam (é quando auditoria mais
    vale). O TASK deles ganhou o item "varra 'Failed with result' e
    'restart counter'".
  - **(c) fg-booster crash-loopando em TODA boot v1.0→v1.5** (17
    `Failed with result` no serial COMPLETO do gate verify da v1.5 —
    invisível porque o gate só olhava `Startup finished`): arqueologia
    git: v4.1 (69dfda1) criou o booster com `xdotool` no packages.add;
    o debloat da v4.2 (9410a32) VARREU o xdotool; o guard `command -v
    xdotool || exit 1` + `Restart=on-failure` + `RestartSec=5`
    (espaçamento que NUNCA atinge o start-limit default de 5-em-10s) =
    loop infinito silencioso no live E no instalado. Cura em 3 camadas:
    (1) **xdotool VOLTA ao packages.add** (presença = contrato de BUILD
    no CI); (2) guards de runtime saem **0** — no-op limpo (ambiente ≠
    defeito); (3) unit ganha `StartLimitIntervalSec=120` +
    `StartLimitBurst=3` (exit≠0 nunca mais vira loop infinito).
  - **Gates de boot endurecidos (live E instalado)**: `Failed with
    result` no serial = gate VERMELHO. Exceção benigna só POR ESCRITO
    com prova — a mesma regra da forense de log (benigno é benigno
    documentado, nunca silêncio).
  - **Limpeza do GitHub (ordem do dono: "as builds anteriores não
    importam pois não funcionam bem")**: releases v1.0.4/v1.1/v1.2/v1.3/
    v1.4 DELETADAS (≈15 GB de assets quebrados — a v1.4 sem keyring à
    venda como "estável"), tags v1.0.4–v1.4 deletadas (remoto e local),
    branches `feat/v1.5-iso-spec`/`feat/v1.5-spec-fixes` (merged/stale)
    deletadas. Ficam: release **v1.5** (a boa), tag v1.5, branches
    `main` + `agent-reports` (saída dos agentes).
  - **Limpeza estrutural**: workflows de debug mortos `diag-boot.yml`/
    `diag-boot2.yml`/`diag-boot3.yml` REMOVIDOS (evidência histórica
    preservada aqui e no git log); `diag-install.yml` renomeado p/
    **`verify-install.yml`** (nomenclatura de debug não vive em pipeline
    de produção — mesmo conteúdo, novo nome, artifact renomeado idem);
    `publish-artifact.yml` entrou no contrato de YAML-válido (era o 5º
    workflow sem contrato); `build-output.log` no .gitignore.
  - **Contratos novos na suíte** (~35 peças): forense estática (padrões
    fatais + whitelist documentada) e FUNCIONAL (5 fixtures: benigno
    v1.5-real → 0; fatais v1.4-real → 1; downloader sem cura → 1; hook
    fora de grub → 1; unknown trust → 1); relay (--repo, always,
    set -euo, abafador extinto); gates de units; fg-booster 3 camadas;
    xdotool (packages.add + propagação na cadeia); workflows mortos
    ausentes; 5 YAMLs válidos.

- **v1.5 (branch feat/v1.5-spec-fixes)** — **A ESPECIFICAÇÃO TÉCNICA DO
  DONO, ITEM A ITEM** (spec v1.5: 9 frentes de falhas reportadas no burn
  test da v1.4 — keyring CachyOS, foot.ini inválido, yazi quebrado,
  Calamares, bloatware, top bar, dock com pins, tela de lock, tom
  amarelado). Pesquisa de fontes primárias antes de cada decisão (diretriz
  permanente do dono: "evitar erros interpretativos, trabalhar com
  pesquisas e dados").
  - **Keyrings CachyOS ("signature unknown trust") — CAUSA-RAIZ ACHADA**:
    o live se auto-cura (o `pacman-init.service` do archiso/archcraft roda
    `pacman-key --populate` SEM argumentos sobre tmpfs — popula TODOS os
    keyrings instalados; o E2 instala o `cachyos-keyring`), mas o SISTEMA
    INSTALADO copia via unpackfs o gnupg DO SQUASHFS — que só tinha a
    chave MESTRA lsign'da pelo E1, não os PACKAGER keys. Cura: **[E2b]**
    `pacman-key --populate archlinux cachyos` no chroot do build (vai pro
    squashfs → vai pro disco) + GATE DURO (cachyos.gpg ausente = fail no
    build, nunca no boot) + belt-and-suspenders no **[E10]** (populate no
    arch-chroot do alvo na instalação) + **camada 4**: 
    no autostart (comandos LITERAIS da spec, idempotentes, sudo -n,
    background — self-healing de sessão p/ skew futuro).
  - **foot.ini — O TERMINAL PERDIA O RICE INTEIRO**: as seções
    `[shell]/[font]/[colors]/[dim]/[bright-bold]` NÃO EXISTEM no foot — o
    terminal logava "invalid section" e IGNORAVA tudo dentro: a fonte
    Nerd, o shell de login e as 16 cores Catppuccin **nunca valeram**.
    Pior: o bloco bare `0=..15=` sobrescrevia a paleta com valores de
    OUTRA tabela (0=f5e0dc: o "preto" renderizava rosado!). Reescrito no
    schema REAL do foot 1.28 (codeberg.org/dnkl/foot · doc/foot.ini.5.scd):
    `shell=`/`font=` em `[main]` (formato fontconfig), cores em
    `[colors-dark]` (a `[colors]` foi REMOVIDA no foot 1.28), `dim0-7`
    dentro da colors, `cursor =` na seção de cores (1.26 removeu
    `cursor.color`), atalhos duplicados dos defaults removidos. Parse
    validado por configparser no CI.
  - **yazi.toml quebrado → yazi REMOVIDO** (spec item bloatware): o parse
    error reportado deixa de existir junto com o pacote e o config.
  - **Calamares**: `shellprocess@btrfs` MANTIDO — a spec manda remover "SE
    não houver .conf em modules"; o `.conf` EXISTE ([E10] o reescreve com
    o fix de boot btrfs v1.0.4 + GPU profile — é o cure do GRUB truncado).
    `Icon=system-software-install` já era o nosso override
    (`/usr/local/share/applications/calamares.desktop`, precedência XDG) —
    contrado congelado.
  - **Bloatware FORA**: `helix` (editor → nano: upstream base, W-e, EDITOR),
    `yazi`, `nvtop` (btop cobre), `gufw`+`ufw` (pesquisa: o upstream
    archcraft lista ambos E habilita `ufw.service` no boot — apply-overlay
    [7] derruba o symlink do wants + E14 remove no chroot). **Thunar é O
    FM padrão** (spec): volta do purge v1.1 + `tumbler` (thumbnails);
    `inode/directory=thunar.desktop` no mimeapps, W-f, dock e craft-drawer
    apontam pra ele. **gpsd/xgps/xgpsspeed: IMPOSSÍVEL remover** — o waybar
    0.15.0-3 do [extra] tem dependência DURA de gpsd (archlinux.org/packages/
    extra/x86_64/waybar: módulo GPS compilado desde 0.13.0, meson 'gps'
    auto). Remover = dock/menu bar mortas. Continua oculto (NoDisplay) com
    auto-remove futuro (E13). Documentado com fonte — decisão de dados,
    não de gosto.
  - **Top bar (spec)**: lançador ARCH do canto esquerdo REMOVIDO (ordem
    direta da spec v1.5; o Launchpad segue na dock, 1º botão do grupo
    central — o ARCH U+F303 vive lá). Esquerda = só o nome do app focado;
    clock no centro exato (`fixed-center`); áudio/rede só ícone (sem %,
    já era contrato v2.1 — agora congelado).
  - **Dock com PINS de ÍCONE REAL (spec: "ícones visíveis no centro mesmo
    com app fechado; Brave fixado no centro")**: os launchers term/files/web
    viraram módulos `image` do waybar 0.15 (pesquisa: o custom module só
    ganha `image-path`/`image-name` no master pós-0.15 — PR #5069). PNGs
    96px do overlay em `/usr/share/pixmaps/elite/`: Papirus rasterizado
    (terminal/files) + **logo OFICIAL do Brave Origin** (product_logo do
    zip). Tooltip = 2ª linha do exec (man waybar-image). Hover = pílula
    surface0 (pixbuf não escala por CSS — documentado). Botão editor saiu
    junto com o helix.
  - **Lock screen — A ESTRELA DA v1.5**: swaylock (tela BRANCA estática)
    → **hyprlock** (pesquisa: roda no labwc via ext-session-lock-v1 —
    labwc.github.io/integration + hyprlock #607/#211 + labwc #3672; cobre
    11/11 itens da spec nativamente vs ~5/11 do swaylock-effects mortie,
    abandonado desde 2023). `~/.config/hypr/hyprlock.conf`: fundo =
    SCREENSHOT + blur 3 passes + dim (brightness .35) + noise; relógio 96pt
    topo-centro + data; **avatar circular com borda mauve** (PNG próprio em
    pixmaps/elite/ + `~/.face.icon` p/ login managers) + nome do usuário;
    campo de senha SEMPRE visível com borda mauve, placeholder "Digite a
    senha para desbloquear" em itálico mauve, **asteriscos** ao digitar,
    "Validando…" âmbar (check), "Senha Incorreta" vermelho (fail). Idle:
    swayidle 10min → hyprlock · 15min → **DPMS wlopm** (receita canônica da
    wiki labwc; wlr-randr --off re-arranja views) · before-sleep → lock.
    craft-lock/craft-logout roteiam pro hyprlock.
  - **Tom amarelado — CAUSA-RAIZ CONFIRMADA EM CÓDIGO**: `wlsunset -t 4000
    -T 6500` no autostart (filtro noturno SEM coordenadas → horário fixo
    default → 4000K forte). wlsunset REMOVIDO do autostart E do packages
    (a paleta Mocha já é fria/neutra; night light = escolha pós-install).
  - Suíte: 863 → **927 peças GO** (64 contratos v1.5: hyprlock item a
    item, foot.ini schema, pins image, Thunar FM, gufw/ufw fora, keyring
    E2b, ARCH extinto da menu bar, wlsunset extinto).

- **v1.4 (branch feat/v1.4-origin-polish)** — **BRAVE ORIGIN + ORGANIZAÇÃO
  DO RICE** (burn test da v1.3 AO VIVO no rig do dono — 3 fotos + mensagem
  de voz, 2026-10-22: *"invés do Brave ser o Brave Origin"*, *"a dock
  sumiu"*, *"ícones sobrepostos, ui/UX não responsiva"*, *"remover as
  categorias e os botões debaixo"*, *"um só ícone de conectividade"*,
  *"esse tipo de erro não pode existir"*). Cada item abaixo responde a uma
  diretrize literal do dono.
  - **Navegador = BRAVE ORIGIN (pacote, não tema)**: o produto oficial
    `brave-origin-*.zip` das releases da Brave (1ª classe: linux amd64/
    arm64 + darwin; profile próprio `BraveSoftware/Brave-Origin`) substitui
    o `brave-bin` do AUR. Empacotado no build com versão **PINADA 1.98.60**
    + sha256 verificado (determinismo — o AUR nem é mais consultado p/
    navegador). **Zero regressão**: launcher `/usr/bin/brave` lendo
    `brave-flags.conf` (padrão chromium-flags), desktop
    `brave-browser.desktop` (contrato do mimeapps.list do skel e do app_id
    do taskbar — `StartupWMClass=brave-browser` confirmado NO BINÁRIO),
    sandbox suid, ícones hicolor do `product_logo`. `Name=Brave Origin`.
  - **Dock SEMPRE VISÍVEL** (a "dock sumiu" do burn test): o auto-hide
    v1.1 (`margin-bottom: -52px` — sobrava um talho de 10px com metade dos
    ícones CORTADOS na base: os "ícones sobrepostos") é EXTINTO. A pílula
    flutua 8px acima da base, sempre (iOS/macOS); zoom hover 30→36px
    (magnificação perceptível — "estilo iOS, aumentam quando passa").
  - **Drawer LIMPO**: `-nocats` (flag oficial do upstream — a barra de
    categorias nem nasce; "deixa o usuário criar o próprio sistema") e
    flags `-pb*` extintas (a barra de sessão da base — travar/desligar/
    reiniciar — não existe mais: sessão mora SÓ na menu bar).
  - **ARCH no canto esquerdo da menu bar** (`custom/menu`, U+F303 em
    MAUVE, clique = Launchpad): a instrução que os resets de sandbox tinham
    apagado — a "maçã" do macOS da Elite.
  - **Conectividade = UM ícone**: o módulo network abre o **craft-connect**
    (novo): dropdown Redes→impala · Bluetooth→bluetui — cabo, Wi-Fi e
    Bluetooth num só lugar. O café (idle inhibitor) fica INVISÍVEL quando
    desativado (CSS v1.4) — fim dos "dois ícones de rede" do burn test.
  - **Sessão com TOGGLE** (o bug do burn test: apertar ⏻ de novo empilhava
    outro fuzzel na frente do desktop e nada fechava): `craft-power`
    detecta o menu aberto (`--prompt=Sessão`) e a 2ª pressão FECHA.
    Fallback labnag idem.
  - **Fixar apps na dock, mouse-first** ("tentei fixar e não consigo"):
    novo **craft-pin-pick** — clique-direito no desktop → "Fixar app na
    dock…" → lista os .desktop instalados → pinta o botão no DNA visual da
    dock (glyph+cor mapeados por app, `printf '\uXXXX'` à prova de
    corrupção). O clique-direito do drawer segue pinando no PRÓPRIO drawer
    (comportamento upstream), agora sem ambiguidade.
  - **Suíte**: 857 peças GO (19 novos contratos v1.4; contratos v1.1/v2.1
    superseded reescritos — auto-hide, power bar, impala-direto, logo
    esquerdo — com a razão da troca documentada em cada).

- **v1.3 (branch feat/v1.3-amoled-rice)** — **AMOLED RICE: preto REAL em
  toda superfície + rodapé do Launchpad extinto + logo do Arch na dock**
  (2ª rodada de diretrizes do dono: "rodapé do launcher", "preto puro
  AMOLED", "logo do Arch no drawer"). O conceito: *"Mocha com o backlight
  desligado"* — a escada de superfícies desce ao preto REAL `#000000`
  (pixels desligados no painel OLED), acentos e textos Catppuccin intactos:
  só o CHROME escurece, o colorido continua doce. GTK apps permanecem
  Catppuccin Mocha por trás do chrome preto — *"macOS style"*: a janela
  entrega a cor, o desktop entrega o preto.
  - **Escada AMOLED** (nos 4 CSS + themerc + fuzzel + foot): `base`
    `#000000` · `crust #050508` · `mantle #0a0a12` · `surface0 #16161f` ·
    `surface1 #22222e` · `surface2 #2e2e3d` — anti-regressão por contrato
    (qualquer `1e1e2e`/`11111b` de volta = falha).
  - **Rodapé do nwg-drawer MORTO**: o upstream gera o "N entries (+M
    hidden)" na base (`#status-label`/`#status-line-wrapper` — confirmado
    no binário 0.7.5 do [extra]). Sem fork: o par é morto por CSS
    (`opacity: 0` + `font-size: 1px` + colapso de margens) — reversível.
  - **Logo do ARCH no drawer da dock**: glifo U+F303
    (`nf-linux-archlinux`, presente no cmap do JetBrainsMono NF do
    archcraft-fonts 2.0) em **MAUVE** — a identidade do rice. Brave segue
    com o escudo U+F132 em **PEACH** — cor de marca. Cores SEMÂNTICAS por
    contrato, não acidente.
  - **Terminal riceado (NOVO `foot.ini`)**: o foot nunca teve config na ISO
    (defaults embutidos) — agora é superfície do rice: bg `#000000`, 16
    tons Mocha, cursor e seleção MAUVE, `pad 10x10`, JBM NF 10.5.
  - **Wallpaper AMOLED de verdade (4K, PNG lossless)**: wallpaper REAL da
    internet (fractal de luz mauve/rosa — 3840×2160) pós-processado para
    o conceito: black-point por luminância com ombro (K=10/S=64, croma
    preservado — o glow L≥64 fica byte-idêntico) e **PNG lossless**, pois
    JPEG re-quantiza cada bloco 8×8 e não entrega preto exato (0 px em
    8,3M no arquivo original). Resultado: **62% dos pixels são `(0,0,0)`
    EXATOS** — fisicamente desligados no painel (conferido por 2 métodos
    independentes: numpy e contagem PIL, 62.22% ambos) — e a dock flutua
    sobre preto de verdade. Contratos medem os BYTES: largura 3840,
    **≥40% de preto PURO contado pixel a pixel** (histogram por canal
    superestima — 33,1% de G==0 sem um único preto no arquivo original),
    luma média ≤30. Fallback do swaybg desce a `#000000`.
  - **Contrato de INI válido no fuzzel**: o arquivo é PARSEADO de
    verdade (configparser, seções `main`+`colors`) e o cabeçalho de
    seção nunca pode regredir — um fuzzel que não parseia cai no visual
    default e o rice morre no launcher.
  - **+64 contratos** na suíte (774 → **838 peças**, GO local com fase 5
    completa): escada idêntica
    nos 4 CSS, acentos intactos, cores semânticas de marca, glifo Arch,
    rodapé morto, foot.ini, wallpaper medido em BYTES (resolução, % preto
    puro, luma), INI do fuzzel parseado, anti-regressões em toda linha.

- **v1.2 (branch feat/desktop-v2.1)** — **BURN TEST DO DONO (rig B):
  forense completa da ISO v1.1 e a cura caso a caso**. O dono bootou a
  v1.1 no Elite B (5600+RX 7600) e reportou 4 screenshots + áudio. Cada
  sintoma virou causa-raiz, fix e contrato:
  - **Calamares TRAVOU no rig** ("The following modules could not be
    loaded: shellprocess@btrfs"): o heredoc EOSB do elite-customize
    reescreve o `shellprocess_btrfs.conf` — e 4 `printf` tinham o `\n`
    partido em quebra de linha REAL (a continuação caía na **coluna 0**,
    terminando o block scalar `>` do YAML no meio do comando → parse
    error → módulo recusado). O CI nunca viu: o gate verify-install
    **simula** os passos do Calamares com rsync/cp/mkinitcpio e só
    **grepa** padrões no .conf — nunca o parseia. Fix: printfs em linha
    única com `\n` literal (heredoc citado preserva o backslash). Gates
    novos: suíte extrai o heredoc EXATO e o parseia com PyYAML (+sh -n em
    cada command); o verify-install ganhou a etapa [1b/8] que parseia
    TODOS os /etc/calamares/*.conf como YAML e resolve instâncias da
    sequência. Bug introduzido no commit do MEGA PROMPT (v1.0.4 limpa).
  - **Dock INVISÍVEL**: 7 de 8 botões com `"format": ""` VAZIO (glifos
    perdidos na escrita dos configs) — o dono viu "uma pílula com um
    ícone só". E esse ícone era o **glifo do FIREFOX (U+F0239) no botão
    do BRAVE** ("achei ruim, o ícone do Firefox sendo que o navegador é
    Brave"). Fix radical: TODOS os glifos como **escapes JSON `\uXXXX`**
    (ASCII puro, à prova de corrupção de encoding) — todos verificados no
    cmap do Symbols Nerd Font / JetBrainsMono NF (archcraft-fonts 2.0).
    Brave agora com o **escudo U+F132** (a marca do Brave). Sem escapes
    de 5+ hex (SMP trap: `\uf0200` parseia como U+F020+dígito).
  - **CSS pedindo família inexistente**: "JetBrainsMono Nerd Font" não
    existe no archcraft-fonts 2.0 (a real: **"JetBrainsMono NF"**) —
    glifos só renderizavam por fallback do fontconfig. Corrigido nos 2
    CSS do waybar + fuzzel.ini (que também pedia weight=medium — só há
    Regular/Bold/Italic).
  - **Desktop v2.1 (as diretrizes do dono, uma a uma)**: relógio no
    CENTRO; logo do canto esquerdo REMOVIDO (launcher = botão grade da
    dock); áudio SÓ ÍCONE (o "40%" ia embora — mudo fica vermelho via
    CSS .muted); **lock/power saem da dock** → botão ⏻ no canto direito
    da barra abre o **craft-power v2: dropdown fuzzel --dmenu ancorado
    top-right** (Travar/Sair/Suspender/Reiniciar/Desligar; fallback
    labnag preservado); dock = **um grupo central único** (Launchpad +
    fixados + separador 1px + janelas abertas — modelo macOS), sem nada
    nas laterais; craft-pin insere os pins do usuário **antes do
    separador** (junto aos fixos).
  - **Menu de apps limpo**: overrides .desktop em
    `/usr/local/share/applications` (precedência XDG, sobrevive a
    updates): `foot-client`/`foot-server` NoDisplay (fim da triplicação
    Foot), `foot` com Icon=utilities-terminal (fim do placeholder roxo
    na taskbar — Papirus pode não ter foot.svg), `xgps`/`xgpsspeed`
    NoDisplay (GPS num desktop gaming?), `abif` (instalador CLI)
    NoDisplay, e **`calamares` com Icon=system-software-install** — o
    "Install Archcraft" tinha Icon=archcraft-green (quebrado → o
    placeholder que o dono viu na dock).
  - **gpsd/xgps/xgpsspeed**: evidência do pacman db da ISO v1.1 (squashfs
    extraído e conferido, hash bit-a-bit): **gpsd é dependência DURA do
    waybar 0.15** (módulo gps compilado — remover à força mataria a libgps
    e a barra não abriria). Cura: overrides NoDisplay de xgps/xgpsspeed
    (o pacote fica p/ satisfazer o waybar, as entradas somem do menu);
    E13 tenta `pacman -Rns` em build — falha segura hoje, cobre o dia em
    que o waybar largar a dep; packages.remove lista gpsd (defensivo).
  - **Thunar TINHA voltado**: o thunar-archive-plugin ficou ATIVO na
    lista upstream e RESSUSCITOU o thunar como dependência (o dono viu
    "Thunar File Manager" no menu — junto vieram libxfce4ui e
    xfce4-about "About Xfce"!). Fix: thunar-archive-plugin entra no
    packages.remove — thunar, libxfce4ui e xfce4-about saem inteiros.
  - **footclient.desktop**: o arquivo real chama `footclient` (sem
    hífen) — override renomeado (o dobro do menu: Foot/Foot Client/
    Foot Server viram UM).
  - **Fonte da forense**: a própria ISO v1.1 do release (2.9GB baixada,
    sha256 confere: f6c8aba9…) — airootfs.sfs extraído com pycdlib +
    unsquashfs 4.6.1 (deb extraído sem root); pacman db lido
    (1091 pacotes, reverse-deps cruzados); pacotes do repo Archcraft
    abertos (archcraft-fonts 2.0 — cmaps inspecionados com fontTools;
    calamares 3.4.2 — sem schema p/ shellprocess, o parse YAML é o
    gate; calamares-config 5.0 — settings.conf/instances íntegros: o
    bug era NOSSO heredoc); + screenshots do dono analisados por VLM e
    mockup HTML 1:1 (fontes reais, paleta exata, wallpaper da ISO)
    iterado até aprovação visual. O YAML quebrado foi confirmado
    VERBATIM no shellprocess_btrfs.conf da ISO real.

- **v1.1 (branch feat/v1.1-modern-stack)** — **MEGA PROMPT: modernização,
  purificação e dual-rig de verdade**:
  - **App-stack 100% moderna e Wayland-native** (diretriz do dono):
    firefox→`brave-bin` (flags Wayland/Vulkan/zero-copy no skel
    `.config/brave-flags.conf`), thunar+file-roller→`yazi`+`7zip`,
    mousepad+vim→`helix` (`catppuccin_mocha`), zathura→`papers`,
    pavucontrol→`pwvucontrol`, blueman→`bluetui` (novo bind W-S-b),
    nm-applet→`impala` (W-n). `brave-bin`/`pwvucontrol` via **estágio AUR
    do build** (aur_build → [elite-local], 2 tentativas, fail-loud).
    xgps/xgpsspeed registrados no remove (contrato; não existiam).
  - **KERNEL ÚNICO**: `linux`/`linux-headers` saem da ISO. A entrada
    NVIDIA do live usava o kernel stock (nvidia-open pré-compilado só
    existia p/ ele) — substituída pelo **nvidia-open-dkms PRÉ-COMPILADO
    contra o BORE**: o pacstrap instala, o hook do dkms compila, o **E11**
    regenera o initramfs do live com hook kms (o hook 90-mkinitcpio-install
    roda ANTES do hook dkms — ordem alfabética — a 1ª geração sairia sem
    nvidia). Resultado: UMA initramfs dá early-KMS nos DOIS rigs (o módulo
    do vendor ausente apenas não binda). O unpackfs leva módulo+fonte+
    toolchain p/ o alvo: **kernel update no sistema instalado reconstrói
    o driver sozinho, offline**. E5b remove o módulo initcpio stock da
    sequência (kernel ausente = abort de instalação); E5a substitui a
    entrada vmlinuz-linux do unpackfs pela do BORE; E6b aposentado.
  - **Menu de boot limpo**: 3 entradas (AMD default · NVIDIA · nomodeset
    rescue), TODAS no BORE, **copy-to-RAM no default e na NVIDIA** (o live
    inteiro na RAM — leitura sequencial, USB lento voa; exige ≥8GB, rescue
    fica copytoram=n p/ máquina pequena). Saem: OpenSource (02), a 05 Copy
    to RAM (default agora É), e qualquer referência ao kernel stock
    (guarda de sanidade no apply-overlay). QEMU dos gates: -m 7168.
  - **Especialização por GPU NA INSTALAÇÃO** (E10 v1.1): detector de
    vendor via /sys/class/drm (0x10de/0x1002) no shellprocess_btrfs —
    AMD: remove nvidia-open-dkms+nvidia-utils+ módulos do ALVO +
    MODULES=(amdgpu) + ppfeaturemask no GRUB; NVIDIA: MODULES=(nvidia*)
    + modeset/fbdev no GRUB + modprobe.d. Cada rig nasce com o driver do
    SEU hardware — zero contaminação cruzada.
  - **elite-tune v4.6**: firstboot detecta o dkms pré-compilado
    (NV_PREBUILT) → rig NVIDIA da ISO instala NADA no 1º boot (offline
    total, marker de primeira passada); online vira fallback p/ sistema
    não-ISO. gpu_cleanup_foreign varre também nvidia-open-dkms + .ko.
    **BBR+fq** ("internet rápida"): sysctl.d 99-elite-net +
    modules-load tcp_bbr, com guard no firstboot (kernel sem bbr →
    remove as linhas em vez de reclamar no boot p/ sempre).
  - **E12**: /etc/environment EDITOR=helix BROWSER=brave TERMINAL=foot
    (o TERMINAL=alacritty era stale desde a v1.0.3).
  - **diag-install (gate de install) v1.1**: pré-flight exige os .ko do
    dkms (E11) e o preset stock AUSENTE; [6b/8] roda o detector de vendor
    (QEMU: unknown = não-op seguro) + 4 contratos do per-rig; [7/8] só o
    initcpio do BORE; artifact gpu-detect.txt.
  - **FIX build #48 — presets órfãos do kernel stock** (forense: a ISO
    construiu, bootou no QEMU live, mas o gate `verify-install` derrubou
    a release no pré-flight com `✖ preset stock PRESENTE`): o upstream
    entrega `/etc/mkinitcpio.d/{linux,linux-nvidia}.preset` como
    **arquivos estáticos do profile** (não vêm de pacote — o
    mkarchcraftiso copia o airootfs ANTES do pacstrap e o hook
    90-mkinitcpio-install itera TODOS os presets no fim da transação).
    Com o kernel stock comentado, os arquivos viraram órfãos com efeito
    duplo: no build o hook morre em `Invalid option -k -- '/boot/
    vmlinuz-linux' must be readable` (erro tolerado — ruído no log) e o
    órfão segue pro squashfs → unpackfs → **sistema instalado**. Novo
    **[6.3] do apply-overlay** deleta `linux.preset`, `linux-nvidia
    .preset` e `archiso-nvidia.conf` (perdeu o único consumidor) do
    profile; `archiso.conf` fica (1ª geração do initramfs live do BORE;
    o E11 o recria e apaga o conf.d inteiro no final). Gate ganhou os
    contratos espelhados: nvidia-preset ausente + conf.d sem drops do
    live (o drop-in archiso venceria o ALL_config do initcpio@elite no
    alvo). Fixture do upstream sintético agora reproduz os 4 arquivos
    VERBATIM — a suíte rodaria verde sem ver o bug (o fixture antigo não
    os tinha).
  - **FIX build #49 — ELITE-BUMP gerava pkgrel inválido** (forense: a ISO
    nem chegou a ser construída; preflight abortou por design após 6
    rounds com `libyuv`/`vid.stab` 404 nos 2 mirrors CachyOS — skew
    ROTACIONA, não é o mesmo pacote da #47): o repack da baseline fazia
    `newrel="${rel_quebrada}.1"` → pkgrel `1.1.1`/`3.1.1` com 3
    componentes — **makepkg rejeita** (`pkgrel must be of the form
    'integer[.integer]', not 1.1.1`, visto no log da #49) → caía no cp
    clássico de baseline MAIS VELHA, que não satisfaz o resolve (pacman
    prefere a versão quebrada anunciada) → rounds eternos → abort. O
    ELITE-BUMP nunca tinha rodado de verdade (na #48 o mirror já estava
    sadio — o caminho nem executou). Fix: `newrel = major da quebrada + 1`
    (`1.1`→`2`, `3.1`→`4` — `vercmp('2','1.1')>0`, formato sempre
    válido); guard p/ rel exótica (cp clássico honesto, sem aritmética
    cega); log do gêmeo não mente mais o mirror ("us" fixo → host real).
    Suíte: seção 3.L — a função REAL extraída por profundidade de chaves
    (awk; o sed `^}$` cortava no `}` do package() do heredoc), roda em
    `unshare -rm` + tmpfs em /var com mocks de vercmp/bsdtar/runuser e
    um makepkg-mock que valida pkgrel com a MESMA regra do real — 14
    peças cobrindo #47, #49, caminho clássico e rel exótica.
  - **FIX build #50 — a "baseline" era o pacote errado** (forense: o
    ELITE-BUMP rodou de verdade pela 1ª vez e expôs 2 bugs latentes do
    preflight): ① `pacman -Sp | head -1` pegava a URL da PRIMEIRA
    DEPENDÊNCIA da transação (o local db vazio resolve tudo: tzdata,
    glibc…) — a "baseline" de libyuv baixada era o pacote **tzdata
    inteiro**; ② o download ia p/ `/tmp/elite-baseline.pkg.tar.zst`
    (nome genérico) — o parse de versão da função lê `${basepkg##*/}`,
    então o repack nascia `libyuv-elite-2` com **payload de tzdata** →
    preflight "fechava" resolvendo p/ o elite-local furado → pacstrap
    offline instalava → `exists in both 'tzdata' and 'libyuv'` →
    abort nas 2 tentativas. Fixes: fu filtrado por PREFIXO do nome do
    alvo (`awk -F/ index($NF, "<base>-")==1` — string fixa, nomes com
    ponto/plus como vid.stab); download p/
    `/tmp/elite-baseline/<nome-real>.pkg.tar.zst` (versão preservada
    pro parse); `options=(!debug)` no PKGBUILD do repack (o makepkg do
    container gerava um `-debug` espúrio no elite-local). +3 contratos
    estáticos na suíte.
  - **FIX build #51 — o preset órfão RESSUCITA no build** (forense: a ISO
    construiu E o boot live passou no QEMU, mas o verify-install viu o
    `linux.preset` de novo no squashfs): o `customize_airootfs.sh`
    upstream tem um bloco "Fix Initrd Generation in Installed System"
    que faz `cat > /etc/mkinitcpio.d/linux.preset`
    **incondicionalmente dentro do chroot** — o [6.3] do overlay apaga
    o arquivo ESTÁTICO do profile, mas este `cat` o recria na hora do
    build (no upstream faz sentido: lá o kernel stock existe; aqui é
    órfão). Como o fragmento Elite é ANEXADO ao final do customize, o
    **E6 agora o remove de novo** (`rm -f /etc/mkinitcpio.d/linux
    .preset`) — kernel único de verdade, nas DUAS camadas. Fixture
    reproduz o bloco de regeneração VERBATIM + contratos de presença e
    ORDEM (rm depois do cat). Suíte: 705 peças, 0 falhas, GO.
  - **FIX build #52 — o GATE testava a ISO ERRADA (v1.0.4)** (forense
    completa; a ISO v1.1 construiu, bootou no QEMU live [verify ✓] e o
    E6 matou o preset — mas o verify-install reprovou DE NOVO): o log do
    gate entregou a linha fatal — `→ run_id não informado; usando a mais
    recente bem-sucedida: 39612464434` = **Build #45, a ISO v1.0.4**
    (branch v1.0.4, sha 870eff0). O passo de download do diag-install
    confiava em `GITHUB_EVENT_NAME == workflow_call`, que **nunca era
    verdade**: a variável de ambiente padrão reflete o evento da RUN
    (push/dispatch/tag), não o tipo de chamada do workflow —
    `workflow_call` seta o CONTEXTO `github.event_name`, não o env. Com
    o branch morto e o `workflow_call:` sem inputs declarados, o gate
    caía no fallback "última bem-sucedida" desde a #48 — **5 builds
    reprovadas por um gate que nunca viu a ISO v1.1**: o `linux.preset`
    da v1.0.4 é legítimo (kernel duplo daquela era), então o contrato
    kernel-único falhava eternamente num produto são. As forenses #48
    ([6.3] presets estáticos) e #51 (E6 rm do ressuscitado) eram higiene
    REAL do kernel-único — necessárias, mas o bloqueio era o gate cego.
    Fix: `build.yml` passa `run_id: ${{ github.run_id }}` ao
    `verify-install`; `workflow_call:` declara os inputs; o download vira
    **tag > run_id > fallback consciente** (input explícito = fonte da
    verdade, zero dependência de env de evento). +5 contratos na suíte
    (run corrente passada, download pelo input, env de evento ausente do
    diag-install, precedência tag>run_id, inputs declarados).
  - **Rice: dock AUTO-OCULTANTE + craft-pin (fixar apps)**: a dock pílula
    agora estilo COSMIC — `exclusive: false` (janelas usam a base da tela)
    + CSS `margin-bottom: -52px` com reveal no hover (cubic-bezier 0.38s,
    zoom de glyphs). **`craft-pin`**: fixar apps do usuário na dock sem
    editar JSON à mão — `craft-pin add steam '' Steam steam green` insere
    1 linha JSONC na seção `PINS` do config.dock + entrada no
    `modules-left` + bloco CSS autocontido (mesmo DNA visual dos fixos);
    vírgulas sempre corretas (parse JSON como juiz), backup `.bak.<ts>` +
    `restore`, reload via SIGUSR2 (man 5 waybar), auto-cura de skel antigo
    sem a seção. Skel sai de fábrica com ZERO pins (launchers fixos do
    skel continuam nascendo na ISO). Limite documentado: wlr/taskbar não
    une pin+running (app fixado rodando = ícone extra no centro).
  - **Suíte**: 460 → **705 peças, 0 falhas, GO** (contratos v1.1: pacotes,
    menu de boot, E5a/E5b/E10/E11/E12, firstboot NV_PREBUILT/BBR on/off,
    brave-flags, mimeapps, yazi/helix, autostart sem applets GTK3,
    craft-pin, presets órfãos do kernel stock — fixture upstream agora
    reproduz os arquivos estáticos do mkinitcpio.d/conf.d VERBATIM — e
    ELITE-BUMP funcional com makepkg-mock validando pkgrel).

- **v1.0.5 (branch fix/estabilidade-gates)** — **GATES DE VERDADE + FIRSTBOOT
  ANTI-BRICK** (auditoria completa das runs de Actions + logs de falha):
  - **`diag-install` virou gate obrigatório de release** (`workflow_call` —
    job `verify-install` no build.yml; release agora exige `needs:
    [build, verify, verify-install]`). O teste de instalação existia mas era
    manual: o bug do rig B teria sido pego ANTES da v1.0.x sair se já
    estivesse na cadeia.
  - **fix do falso negativo do gate de install**: o grep das entradas do
    grub.cfg usava espaço literal (`'(linux|initrd) '`) — grub.cfg usa TAB;
    devolvia vazio e a run morria com o passo verde de verdade (prova:
    artifacts da run #2 da branch diag-install — `grub-mkconfig.log` com
    "Found linux image", `grub-entries.txt` vazio). Agora `[[:space:]]`.
  - **fix do gate de verify calado**: `set -e` + grep solto abortava o
    script ANTES do `chk` imprimir o diagnóstico — as builds #42/#43
    falharam sem uma linha de explicação. Agora `set +e` + `exit $FAIL`.
  - **fix unsquashfs sem sudo** (merge da branch diag-install — xattrs
    `security.capability` exigem root, exit 2 na run #1).
  - **elite-tune v4.5 — firstboot NVIDIA anti-brick**: a ordem antiga era
    `-R nvidia-open` → `-S nvidia-open-dkms`; sem rede no 1º boot o rig
    ficava **sem driver NENHUM** e o marker `firstboot-done` (escrito
    incondicionalmente) sepultava o retry. Agora: `-S` primeiro (`pacman_s`,
    dry-aware), `-R` só após sucesso; sem rede → driver preservado, marker
    não escrito, unit re-tenta no próximo boot, wall honesto ("pendente").
    Novo cenário na suíte: Blackwell + pacman recusando tudo.
  - **docs sincronizadas**: README (zram = min(RAM, 8GB), E0–E10, cadeia de
    gates), SCRIPTS.md (v4.5, E8–E10), craft-bat (bind fantasma W-S-b).
  - **scripts/qemu-boot-test.sh**: loop local rápido — boota a ISO com a
    cmdline REAL extraída dela (KVM se disponível; ~1 min vs ~55 min de
    TCG no CI) p/ iterar sem esperar runner.

- **v1.0.4 (main)** — **FIX DO BOOT DO SISTEMA INSTALADO** (bug real do
  rig B: GRUB `premature end of file /boot/vmlinuz-linux-cachyos-bore` →
  `you need to load the kernel first`): o install do Archcraft é
  **unpackfs** (cópia do live pro alvo) e em btrfs arquivos grandes chegam
  truncados — o upstream já tem workaround (`shellprocess@btrfs`) que
  **recopia só o vmlinuz-linux STOCK**; como a Elite boota o BORE por
  default, o kernel do BORE ficava truncado. Pior: o initramfs do BORE
  copiado era o do LIVE (hooks archiso). **[E10]** estende o workaround
  para **TODOS os vmlinuz-\*** do pendrive + **regenera o initramfs do
  BORE no alvo** (`arch-chroot mkinitcpio -p linux-cachyos-bore`, hooks
  de sistema). **DESKTOP v2 · macOS-style, mouse-first** (diretriz do
  dono pós-teste no hardware: "labwc tá muito ruim/seco, quero interface
  com barra tipo macOS e mais utilizável — não sou muito de atalho").
  **RICE PRÓPRIO** (fim do visual "cru": o `OB-Catppuccin-Mocha` citado
  desde o cockpit **NUNCA EXISTIU** — tema fantasma; labwc caía no tema
  default cinza): **themerc-override** próprio (labwc-theme(5)) com
  traffic-lights Mocha, **borda de janela ativa mauve**, titlebar
  centralizada, **sombras grandes 60/40** (receita hakuspace), menu/OSD
  coerentes — receita sintetizada dos melhores rices labwc públicos
  (hakuspace 272★, Speyll, modern-labwc 143★, dux-shell 8.4k★, themercs
  Catppuccin reais); **tema GTK Catppuccin Mocha OFICIAL**
  (`catppuccin-gtk-theme-mocha`, repo [archcraft], variante
  Standard-**Mauve**-Dark = acento do rice) + **cursor Bibata**
  (`archcraft-cursor-bibata`) + JetBrainsMono Nerd Font (já vinha do
  archcraft-fonts); **wallpaper REAL da internet** (dark-waves, coleção
  walls-catppuccin-mocha 2.9k★ — dominante #1d1f2d ≈ base Mocha; o
  AI-generated foi DESCARTADO a pedido do dono):
  **menu bar** no topo (waybar `config.top`: logo→Launchpad, nome da janela
  focada, música/MPRIS, rede→`nm-connection-editor`, volume→`pavucontrol`,
  tray, relógio→SwayNC, power) + **DOCK** flutuante na base (waybar
  `config.dock`: Launchpad, launchers fixos — terminal/arquivos/navegador/
  editor/screenshot — e **janelas abertas com ícones reais** via
  `wlr/taskbar`/foreign-toplevel, lock e power); **Launchpad** =
  `nwg-drawer` (`craft-drawer`: grade full-screen com busca, categorias e
  barra de sessão); **power mouse-first** = `craft-power` (labnag, o nag
  bar nativo do labwc — zero dependências novas); **ícones Papirus-Dark**
  no GTK3/4 (dock/Launchpad/apps); menu raiz ganha Aplicativos/Reboot/
  Desligar. Polish ui-ux-pro-max: matriz de estados completa (hover+
  `:active`+transition em tudo), alpha do dock 0.85 (contraste composto
  sobre wallpaper), drawer.css com tokens `@define-color`, categoria
  ativa com fundo (estado ≠ só cor). A rota wlogout foi descartada (**saiu
  dos repos oficiais**); nwg-dock também (task buttons exigem IPC do sway
  — inexistente no labwc; o waybar-dock cobre via protocolo). Coerência de
  snapshots: `btrfs-assistant` (stock) sai — é GUI do **snapper**, que não
  vem na ISO (meia-ferramenta) e duplicaria a estratégia do **Timeshift**
  (`craft-rollback` + `grub-btrfs`). Rota snapper = opcional, documentada
  no cockpit dia-1. Acompanha o **cockpit v1.4.0**: dia-1 alinhado à ISO
  (só o stack especializado — launchers, produção de conteúdo, dev,
  ventoinha, Android; mangohud/gamemode/gamescope/pavucontrol/
  polkit-gnome/file-roller/gparted/gcc já vêm de fábrica).
  **Entrada de boot "Copy to RAM"** nos 3 bootloaders (sdboot/syslinux/grub
  + loopback do Ventoy): `copytoram=y` — em pendrive lento (USB 2.0/Ventoy)
  o live padrão lê tudo do USB e serviços Type=notify escalam os timeouts;
  com a entrada RAM o airootfs é copiado no início (leitura sequencial,
  rápida) e o live voa. Requer ~8GB de RAM.
  **FIX DEFINITIVO DO FREEZE DO LIVE [6.2]**: `systemd.default_timeout_
  start_sec=90 systemd.default_timeout_stop_sec=90` no cmdline de **TODAS**
  as entradas dos 3 bootloaders. Fechamento do ciclo diag-boot3: o drop-in
  `/etc/systemd/system.conf.d/00-elite-timeout.conf` (90s, v1.0.3) cobre o
  sistema **instalado**, mas no **live** o PID-1 nasce no initramfs e, após
  o `switch_root`, **não reavalia drop-ins de `/etc`** — os jobs seguem com
  o `DefaultTimeoutStartSec=15s` que o `cachyos-settings` põe em
  `/usr/lib/systemd/system.conf.d/00-timeout.conf` (comprovado no serial:
  `Resource Manager (4s / 15s)` nas builds v1.0.3 **e** v1.0.4). Prova A/B
  local (QEMU TCG idêntico ao gate, ISO da run #42): SEM o param =
  `systemd-nsresourced` em restart-loop eterno (169 falhas/55min, 19s CPU
  por tentativa) + `systemd-tmpfiles-setup` travado 28min + boot nunca
  completa → gate #42 vermelho; COM o param = **0** falhas de nsresourced,
  tmpfiles completa, boot chega à fase final (~5min) → gate verde. A linha
  de comando do kernel é a única precedência que o PID-1 do live respeita
  sempre. Kernel-agnóstico (vale p/ BORE, stock e nvidia).
  **FIX DO GATE `verify` (build #43 vermelha)**: o gate boota com
  `-kernel/-append` direto e o `-append` era **hardcoded, sem o fix [6.2]**
  — a #43 testou uma cmdline que nenhum usuário boota (timeouts 15s de
  volta → nsresourced em loop, 153 falhas, SDDM só aos 56min, gate morto).
  O gate agora extrai o cmdline **REAL** da entrada default do syslinux da
  própria ISO (só observabilidade muda: sem quiet/splash, loglevel=7,
  console=ttyS0) e ganhou **check de regressão**: entrada sem
  `systemd.default_timeout_start_sec=90` = gate vermelho na hora.
- **v1.0.3** — sessão **ÚNICA labwc (Wayland)** com o rice Catppuccin Mocha
  (Waybar/SwayNC/Fuzzel/foot + helpers `craft-*` + fastfetch);
  **Openbox/BSPWM + satélites X11 removidos** (zero duplicação: um WM, um
  terminal, uma barra, um launcher — música de exemplo fora, a barra toca a
  SUA música via MPRIS); fix 203/EXEC dos binários no live (0755 no
  `file_permissions`); `Slice=` no fg-booster; Calamares apontado p/ labwc;
  documentado o requisito **x86-64-v3** (ISO inteira, não só o kernel);
  **curadoria "brabos 2026"**: ~30 best-in-class de uso geral entram
  (zathura/qalculate/file-roller/mousepad/nwg-look/yazi + CLI rust +
  satélites labwc: swayidle/udiskie/wlsunset/cliphist), ~60 saem
  (email-like/gravador/geany/ranger/oh-my-zsh/legado) — skel `.zshrc`
  próprio (plugins standalone + starship).
- **v1.0.2** — primeira pública (kernel BORE v3 + engine CachyOS + Vulkan + debloat).

## ➕ Adicionados (`elite/packages.add`)

| Pacote | Por quê |
|---|---|
| `linux-cachyos-bore` + `-headers` | Kernel BORE build x86-64-v3 (patchset CachyOS: latência + throughput). `linux`/`linux-headers` do Arch ficam como fallback e alvo do dkms |
| `cachyos-settings` | sysctl/udev/modprobe/limits de fábrica (70-cachyos-settings.conf; sem pacman fork, sem zram — o nosso `/etc` vence) |
| `cachyos-ananicy-rules` + `ananicy-cpp` | Regras de prioridade dinâmica para jogos/DE |
| `scx-scheds` | **Os binários** sched-ext (`scx_bpfland`, `scx_lavd`, …) — pacote do Arch `extra`; o CachyOS não empacota mais os schedulers |
| `scx-tools` | `scxctl`/`scxtui`/`scx_loader` (troca de scheduler em runtime) |
| `dmemcg-booster` | Tetos de VRAM p/ apps em background (unit `dmemcg-booster-system.service`) |
| `gamemode` + `lib32-gamemode` | Governor/prioridade ao rodar jogos |
| `gamescope` | Compositor micro do Valve (subnativo NIS/FSR p/ VRAM apertada) |
| `mangohud` + `lib32-mangohud` | Overlay de fps/frametime/VRAM (config no skel com VRAM à mostra) |
| `vulkan-radeon` / `vulkan-intel` (+ lib32) | **Vulkan de série** — o upstream só traz mesa; sem isto RADV/ANV não existem |
| `lib32-mesa` | 32-bit GL p/ jogos Proton antigos |
| `nvtop`, `btop` | Monitor de GPU / TUI de sistema |
| `lact` | Controle de GPU (undervolt/OC; ppfeaturemask já desbloqueado no tune AMD) |
| `grub-btrfs`, `timeshift` | Rollback real (btrfs default no installer + grub-btrfsd) |
| `pciutils` | `lspci` para a detecção de hardware do `elite-tune` |
| **v1.0.3** `labwc` | **A sessão default** (Wayland, clone do Openbox em gramática `rc.xml`) — o live autologa e o sistema instalado inicia nela |
| **v1.0.3** `waybar` `swaync` `fuzzel` `foot` | Barra floating pill + central de notificações + launcher + terminal (rice Catppuccin Mocha no skel) |
| **v1.0.3** `swaybg` `swaylock` `wl-clipboard` `grim` `slurp` | Wallpaper (cor sólida Base), bloqueio de tela (W-l/`craft-lock`), clipboard Wayland e screenshots (W-P/`craft-shot`) |
| **v1.0.3** `playerctl` `brightnessctl` `pulsemixer` | Teclas de mídia/brilho e o mixer W-a do `rc.xml` |
| **v1.0.3** `polkit-gnome` | Agente de senha da sessão labwc (o do Archcraft só sobe no Openbox) |
| **v1.0.3** `mpv` `imv` `fastfetch` | Vídeo/imagem minimalistas Wayland + system info (o `craft-hello` usa) |
| **v1.0.4** `nwg-drawer` | O **Launchpad**: grade de apps full-screen com busca, categorias, pin e barra de sessão (`craft-drawer`) — mouse-first (diretriz do dono) |
| **v1.0.4** `papirus-icon-theme` | Ícones de apps em toda parte: dock (waybar `wlr/taskbar`), Launchpad e GTK (skel aponta `Papirus-Dark`) |
| **v1.0.4** `catppuccin-gtk-theme-mocha` | Tema GTK **oficial Catppuccin** (repo [archcraft], 42 variantes) — o skel usa `Catppuccin-Mocha-Standard-Mauve-Dark` (= o acento do rice). Apps GTK nascem Mocha, não Adwaita |
| **v1.0.4** `gtk-engine-murrine` | Engine exigida pelo tema GTK Catppuccin |
| **v1.0.4** `archcraft-cursor-bibata` | Cursor **Bibata** — o cursor dos melhores rices labwc (hakuspace/modern-labwc) |
| **v1.0.3** `mousepad` `zathura`+`-pdf-poppler` `qalculate-gtk` `file-roller` `nwg-look` | **Curadoria brabos 2026** (uso geral de fábrica, GTK3 temável): editor de texto simples (geany→IDE-lite saiu), PDF keyboard-driven (atril saiu), a calculadora "de outro nível" 5.13 (galculator saiu), archives GUI integrado ao Thunar (xarchiver→bug DnD Wayland saiu), aparência GTK no labwc (xfce4-settings saiu) |
| **v1.0.3** `yazi` | FM TUI em rust com previews nativos — substitui ranger+ueberzug+highlight+mc |
| **v1.0.3** `ripgrep` `fd` `fzf` `eza` `bat` `zoxide` `dust` `procs` `sd` `starship` `tealdeer` | CLI modernos (rust) — os "essenciais" do cockpit agora nascem na ISO; o W-f do `rc.xml` já usava eza |
| **v1.0.3** `swayidle` `udiskie` `wlsunset` `cliphist` `libnotify` | Satélites oficiais do labwc: idle→lock automático (10 min), automount USB com notificação, night light e histórico de clipboard (W-v no fuzzel — receita oficial labwc) |
| **v1.0.3** `zsh-autosuggestions` `zsh-syntax-highlighting` | Plugins standalone que substituem o oh-my-zsh inteiro (skel `.zshrc` próprio + starship) |
| **v1.0.3** `xdg-desktop-portal-wlr` | Screenshare/gravação no Wayland (sem isto OBS vê tela preta no labwc) |

## ➖ Removidos (`elite/packages.remove`) — restore: `sudo pacman -S <pkg>`

| Grupo | Pacotes | Por quê sai | Risco |
|---|---|---|---|
| WM Wayland | `archcraft-sway-free` | A edição Sway do Archcraft é OUTRA stack (sway+wlroots próprios); a sessão Wayland da Elite é o **labwc** com configs próprias | quem quiser Sway: `pacman -S archcraft-sway-free` |
| **v1.0.3** Sessões X11 | `archcraft-openbox` `archcraft-bspwm` | **Diretriz do dono: labwc é A sessão** (Wayland, leve, moderna). Temas OB ficam (`archcraft-openbox-themes`) — o labwc lê os mesmos temas | `pacman -S archcraft-openbox` (ou `archcraft-bspwm`) |
| **v1.0.3** Instalador TUI | `archcraft-installer` | Calamares é o instalador da Elite; o TUI tem dep dura de `alacritty` (removido) | `pacman -S archcraft-installer` |
| **v1.0.3** Satélites X11 | `polybar` `tint2` `rofi` `picom` `obmenu-generator` `lead-git` `skippy-xd-git` `plank` `ksuperkey` `wmname` `wmctrl` `nitrogen` `hsetroot` `maim` `slop` `xclip` `betterlockscreen` `i3lock-color` `dunst` `obconf-qt` `light` `archcraft-arandr` `archcraft-randr` `archcraft-dunst-icons` `networkmanager-dmenu-git` | Cada um tem par Wayland na sessão labwc: waybar (barra), fuzzel (launcher), swaybg (wallpaper), grim/slurp (screenshots), wl-clipboard, swaylock, swaync (notificações), brightnessctl (brilho), wdisplays (monitores), blueman/nm-applet (trays) | `pacman -S <pkg>` — o X11 continua utilizável via XWayland |
| **v1.0.3** Terminais | `alacritty` `kitty` `kitty-terminfo` `xfce4-terminal` | **Dedupe de duplicação** (diretriz do áudio): 4 terminais viram 1 — o `foot` dos keybinds do `rc.xml` | `pacman -S alacritty` (ou kitty/xfce4-terminal) |
| **v1.0.3** Música exemplo/console | `archcraft-music` `archcraft-config-music` `mpd` `ncmpcpp` `mpc` `mplayer` | **Diretriz do áudio**: nada de sample music no sistema; a barra/notificações tocam a SUA música (playerctl/MPRIS — YouTube/Spotify/mpv). `mpv` fica p/ arquivos locais | `pacman -S mpd ncmpcpp` (stack console) |
| **v1.0.3** X11 dev/test | `xorg-server-devel` `-src` `-xephyr` `-xnest` `-xvfb` `xorg-docs` `xorg-util-macros` `xorg-bdftopcf` `xorg-fonts-100dpi` `xorg-fonts-75dpi` `xorg-fonts-alias` `xorg-x11perf` | Vieram da expansão do grupo `xorg` no pacstrap CI; dev/test/bitmap-fonts não pertencem a um live de desktop. O `xorg-server` FICA (greeter SDDM x11 + fallback nomodeset) + `xorg-xwayland` | `pacman -S <pkg>` |
| Impressão | `cups` `cups-pdf` `cups-filters` `ghostscript` `gsfonts` `foomatic-db-engine` `foomatic-db` `gutenprint` | ~400 MB instalados com deps | impressora: `pacman -S cups cups-filters gutenprint foomatic-db` + `systemctl enable --now cups` |
| Cloud/VM | `cloud-init` `hyperv` `open-vm-tools` `virtualbox-guest-utils` `qemu-guest-agent` `xf86-input-vmmouse` | daemons de graça em bare-metal; cloud-init ainda atrasava o boot | VM: `pacman -S <guest-tools-do-hypervisor>` |
| Modem/VPN legacy | `modemmanager` `ppp` `pptpclient` `xl2tpd` `wvdial` `linux-atm` `open-iscsi` `openconnect` `vpnc` `networkmanager-{openconnect,pptp,vpnc,sstp,strongswan}` `b43-fwcutter` `broadcom-wl` | PPPoE/dial-up/iSCSI/VPN enterprise; **openvpn fica** | VPN corporativa: `pacman -S networkmanager-<flavor>`; Broadcom WiFi antigo: `pacman -S broadcom-wl` |
| Resgate pesado | `clonezilla` `partclone` `partimage` `fsarchiver` `gpart` `ddrescue` | ~150 MB; testdisk/photorec e gparted ficam | pendrive de resgate dedicado |
| Rede/servidor | `bind` `dnsmasq` `nbd` `nfs-utils` `mkinitcpio-nfs-utils` `darkhttpd` `lftp` `lynx` `irssi` `nmap` `ldns` `sequoia-sq` `openpgp-card-tools` `pcsclite` | servidor DNS/DHCP/PXE/IRC/smartcard num desktop gamer | `pacman -S <pkg>` |
| FS exóticos | `bcachefs-tools` `jfsutils` `nilfs-utils` `udftools` `refind` | JFS/NilFS/UDF/CoW experimental/second bootloader | `pacman -S <pkg>` |
| Fontes | `noto-fonts-cjk` | ~90 MB de CJK | leitura/jogos CJK: `pacman -S noto-fonts-cjk` |
| Initramfs | `mkinitcpio-firmware` | duplicava firmware dentro de cada initramfs (×2 kernels no ISO) | nenhum — hook `kms` já embute o necessário |
| Console/access. | `brltty` `gpm` | braille/mouse de console | `pacman -S <pkg>` |
| Instalador TUI | `archinstall` | redundante com Calamares + ABIF | `pacman -S archinstall` |
| Pywal | `python-pywal` | **saiu dos repos oficiais** (quebrava o resolve do pacstrap); só as cores dinâmicas do rice perdem o helper | `yay -S python-pywal` |
| p7zip | `p7zip` → `7zip` | `p7zip` virou pacote **virtual** de `7zip` (2 providers em repos distintos = prompt interativo no build) | já substituído |
| **v1.0.3** Apps "simples demais" | `simplescreenrecorder` `geany` `geany-plugins` `meld` `catfish` `viewnior` `atril` `galculator` `xarchiver` `yad` `pastel` `xcolor` `xmlstarlet` `trash-cli` | **Diretriz do dono**: email, gravador de tela e afins = específico → cockpit pós-install. Cada um tem substituto brabo entrando: mousepad, zathura, qalculate-gtk, file-roller; viewnior duplicava o `imv` (Wayland-nativo); catfish perde p/ fd/fzf/yazi; trash-cli p/ `gio trash` | `pacman -S <pkg>` |
| **v1.0.3** CLI duplicados/legados | `htop` `nethogs` `ncdu` `powertop` `screen` `unarchiver` `lrzip` `lzop` `mc` `ranger` `ueberzug` `highlight` `archcraft-ranger` `archcraft-vim` | Dedupe com os brabos: `btop` fica, `dust` entra (ncdu sai), `tmux` fica, `yazi` (rust) substitui ranger+ueberzug+highlight+mc, unrar/zip/unzip ficam | `pacman -S <pkg>` |
| **v1.0.3** Shell | `archcraft-omz` | oh-my-zsh = 7.3 MB de framework carregado a cada prompt; substituído por zsh puro + `zsh-autosuggestions` + `zsh-syntax-highlighting` + `starship` (skel `.zshrc` próprio da Elite, técnica de rehash on-demand do criador preservada) | `pacman -S archcraft-omz` |
| **v1.0.3** Skel órfão | `archcraft-skeleton` | 6.4 MB de configs de sessões extintas (openbox/polybar/rofi) no `$HOME` de todo usuário novo — "sistema limpo desse lixo" (diretriz do dono). O skel Elite (labwc/waybar/swaync/fuzzel/`.zshrc`/`.hushlogin`) é o único dono do `/etc/skel` | `pacman -S archcraft-skeleton` |
| **v1.0.3** Fluff do stock | `archcraft-welcome` `archcraft-about` `archcraft-artworks` `archcraft-funscripts` `archcraft-help` `archcraft-neofetch` `archcraft-scripts` | Welcome/about/artworks/funscripts/help = fluff de desktop; neofetch descontinuado (fastfetch já na ISO); "arcs" do criador cobertos pelos `craft-*` da Elite | `pacman -S <pkg>` |
| **v1.0.3** Sessão Xfce/X11 | `xfce4-settings` `xsettingsd` `xfce4-power-manager` `xfce-polkit` `gtk-nocsd-git` `perl-linux-desktopfiles` `thunar-shares-plugin` `thunar-media-tags-plugin` | Theming X11 → `nwg-look`; power manager inútil em desktop sem bateria → `swayidle`; polkit duplicado do `polkit-gnome`; deps órfãs de ferramentas já removidas; plugins Thunar de nicho (samba/ID3) | `pacman -S <pkg>` |
| **v1.0.3** Sistema legado/nicho | `bolt` `dmraid` `mmc-utils` `ndisc6` `usb_modeswitch` `usbmuxd` `gvfs-afc` `gvfs-gphoto2` `sdparm` `sg3_utils` `lsscsi` `inetutils` `wireless_tools` `libusb-compat` `qt5ct` `kvantum` `kvantum-qt5` `archcraft-config-qt` | Thunderbolt/RAID legado/eMMC/modem 3G/daemon iPhone/SCSI admin/telnet-ftp/tools WiFi legados — nada disso existe no desktop alvo (Ryzen+RX 7600). `gvfs`+`gvfs-mtp`+`gvfs-smb` FICAM; `qt6ct` fica p/ apps Qt futuros; zero apps Qt5 restantes | `pacman -S <pkg>` |

## 🧩 Firmware cirúrgico (apply-overlay)

O meta `linux-firmware` é trocado pelos subpacotes que cobrem **hardware
consumidor**: `amd amdgpu atheros broadcom cirrus intel mediatek radeon
realtek ti whence` (+ `linux-firmware-marvell` que já vinha no upstream).

Saem (~700 MB–1 GB brutos):

| Subpacote | Conteúdo | Por quê sai |
|---|---|---|
| `linux-firmware-nvidia` | GSP/nouveau p/ NVIDIA | só serve ao **nouveau**; o driver proprietário (nvidia-open) embute o firmware dele |
| `linux-firmware-other` | SoCs ARM, NICs antigas, DSPs… | desktop x86 não usa |
| `linux-firmware-mellanox` / `-nfp` / `-qlogic` / `-liquidio` / `-qcom` | NICs enterprise / smartNIC / ARM | fora do alvo |

Restore total: `sudo pacman -S linux-firmware`.

## ⚙️ Modificações de comportamento

| O quê | Antes (upstream) | Depois (Elite) |
|---|---|---|
| Entradas de boot default/opensource/nomodeset | kernel `linux` | kernel `linux-cachyos-bore` (a entrada **Nvidia** fica no kernel stock — módulo pré-compilado) |
| Filesystem default do Calamares | ext4 | **btrfs** (rollback: timeshift + grub-btrfsd) |
| unpackfs do Calamares | copia só `vmlinuz-linux` p/ o alvo | copia também `vmlinuz-linux-cachyos-bore` |
| initcpio do Calamares | gera initramfs só do `linux` | instância extra `initcpio@elite` gera também do BORE |
| packagechooser | Openbox/Bspwm/Sway/Everything | Openbox/Bspwm/Everything (Sway fora da ISO) |
| Serviços no post-install | `cups`/`avahi-daemon` na lista | removidos da lista (pacotes fora) |
| pacman.conf do sistema | [archcraft]+[core]+[extra] duplicados no fim | reescrito limpo: archcraft → cachyos(v2+v3 trio) → core/extra/multilib |
| mkinitcpio preset BORE | — | nasce archiso (live) e vira default/fallback no instalado (mesmo padrão do upstream p/ o linux.preset) |
| systemd wants | cloud-init/vbox/vmware/hv/ModemManager/cups/pcscd | symlinks removidos |
| **v1.0.3** Sessão do live (autologin SDDM) | `openbox` | **`labwc`** (Wayland, única sessão) — `state.conf` pré-seleciona labwc no greeter do instalado também |
| **v1.0.3** packagechooser do Calamares | openbox/bspwm/sway/everything | **item único `labwc`** (página Desktop apenas confirma) + `chrooted_autologin.sh --labwc` |
| ISO | `archcraft-<data>-x86_64.iso` | `archcraft-elite-<data>-x86_64.iso` |
| Unit scx | — | `scx-elite.service` (bpfland; `systemctl edit` troca o scheduler) |
| Unit dmemcg | — | `dmemcg-booster-system.service` habilitada via wants |
| **v1.0.3** fg-booster.service | — | `Slice=fg-boost.slice` (realiza o slice; sem isto o script saía na guarda e reiniciava em loop) |

## 🆕 Arquivos novos no airootfs

- `/etc/sysctl.d/99-elite.conf` — swappiness 180, vfs_cache_pressure 50, max_map_count Steam, page_lock_unfairness
- `/etc/systemd/zram-generator.conf` — zram0 zstd, ½ RAM (teto 8 GB)
- `/etc/udev/rules.d/60-io-elite.rules` — NVMe/SSD `none`, HDD `bfq`
- `/etc/systemd/system/{elite-firstboot,fg-booster,scx-elite}.service`, `fg-boost.slice` (+ wants)
- `/etc/mkinitcpio.d/linux-cachyos-bore.preset` — preset archiso p/ o live
- `/etc/skel/.config/MangoHud/MangoHud.conf` — overlay com VRAM
- `/usr/local/bin/{elite-tune,elite-status,fg-booster}`
- **v1.0.3** `/etc/skel/.config/labwc/{rc.xml,menu.xml,autostart}` — a sessão inteira no skel (o mkarchcraftiso copia o skel p/ o home do liveuser preservando modos; novos usuários do instalado herdam pelo `useradd -m`)
- **v1.0.3** `/etc/skel/.config/{waybar,swaync,fuzzel}/` — rice Catppuccin Mocha da barra/notificações/launcher
- **v1.0.3** `/usr/local/bin/craft-{hello,update,clean,rollback,lock,logout,shot,bat}` — helpers dos keybinds do `rc.xml` (mesmos comandos do zip Cockpit; `craft-rollback` aponta p/ Timeshift na ISO)
- **v1.0.3** `/etc/sddm.conf.d/kde_settings.conf` (overlay) — autologin `Session=labwc`
- **v1.0.3** `/var/lib/sddm/state.conf` — greeter do sistema instalado pré-seleciona labwc

## 🐛 Causa raiz do freeze em hardware real (diag-boot3 — fix v1.0.3)

O sintoma do rig B ("a splash/progresso finaliza e congela", **ambas** as entradas
de boot, via Ventoy) foi **reproduzido e explicado** no QEMU round 3 (teste E =
caminho real do systemd-boot, `archisosearchuuid`):

- O `cachyos-settings` instala `/usr/lib/systemd/system.conf.d/00-timeout.conf`
  com **`DefaultTimeoutStartSec=15s`** (valor agressivo, pensado p/ sistema
  instalado em SSD quente);
- Em boot a frio via USB/Ventoy (IO lento), serviços **Type=notify** com
  `Restart=` (ex.: `systemd-resolved`, `systemd-oomd`) não ficam prontos em
  15s → `start operation timed out` → restart → timeout → **restart-loop
  eterno** (contador 75+ no serial) → `multi-user`/`graphical` nunca
  completam → `plymouth-quit` nunca roda → **splash congelada para sempre**;
- Evidência A/B: com o mesmo airootfs, o round 2 (dispositivo direto, timing
  mais folgado) mostrou `Started Network Name Resolution` e boot completo em
  3min54s; o round 3 (caminho real, timing apertado) mostrou o resolved cair
  no timeout-loop e o boot nunca terminar — a diferença entre "boota" e
  "congela" é uma corrida de milissegundos contra o timeout de 15s.

**Fix**: `elite/airootfs/etc/systemd/system.conf.d/00-elite-timeout.conf`
(start/stop = **90s**, padrão vanilla do systemd). Drop-ins em `/etc` têm
precedência sobre `/usr/lib` — o 15s do CachyOS fica neutralizado no
**sistema instalado** (no live o drop-in nunca valeu — ver [6.2] acima,
foi exatamente o que a #42/#43 expôs). Quem quiser o 15s de volta:
`sudo rm` o arquivo. (Correção histórica: quando isto foi escrito, o gate
`verify` do CI boota com `-append` próprio hardcoded — ele NÃO validava o
caminho real; a partir da v1.0.4 o gate extrai o cmdline da entrada default
da ISO e caça regressão do [6.2] em toda build.)

## ⚠️ Requisito de CPU (v1.0.3 — documentado)

**A ISO inteira exige x86-64-v3 (AVX2/FMA/BMI2)** — não é só o kernel BORE:
792 dos 1203 pacotes da v1.0.2 são rebuilds v3 do CachyOS (glibc, sddm,
xorg-server, qt6, mesa…). Zen 3 (Ryzen 5000) e superior rodam com folga.
Verificação em qualquer máquina:

```bash
/lib64/ld-linux-x86-64.so.2 --help | grep supported
# x86_64 (baseline), x86-64-v2, x86-64-v3  ← precisa listar o v3
```

CPU sem AVX2 (ex.: Celeron Gemini Lake) → usar o zip irmão
`archcraft-labwc-lite` (repos oficiais da distro, zero CachyOS).

## v4.4 — zero-curl ×2 + preflight execv-safe (runs #14/#15)

- **Causa raiz dos runs #14–#15 (prova binária)**: `libalpm.so` importa
  `execv`+`fork`, não `system()` — o pacman executa o XferCommand via
  fork/execv, SEM shell. O `|| echo "ELITE-FAIL %u" >> …` do preflight
  virava argumento literal do curl → "failed to synchronize all
  databases" em TODA transferência → 4-5 rounds inúteis.
- **Preflight v3**: XferCommand plano (flags apenas); mapeamento de
  falhas por SONDA pós-round (`pacman -Sp --print-uris` → HEAD paralelo
  16× via xargs -n1); 3 rounds (não 5); ABORTA com diagnóstico em vez
  de "seguir mesmo assim"; mkarchcraftiso 2 tentativas sem sleeps de
  90s; -Syw SEM --needed (cache = transação inteira do chroot).
- **E6b**: linux.preset reescrito para default/fallback no customize —
  no alvo, o chrooted_post_install_nvidia.sh do Archcraft DELETA
  /etc/mkinitcpio.conf.d/ antes do initcpio do Calamares; o preset
  'archiso' apontava para o conf deletado → `mkinitcpio -p linux`
  morreria em "must be readable" (check_path r, fonte 42.2) e o kernel
  stock (entrada NVIDIA: nvidia-open pré-compilado) ficaria sem
  initramfs no sistema instalado.
- **BORE não shipa preset** (MTREE verificado: 0 arquivos etc/) — sem
  conflito com o overlay; o hook 90-mkinitcpio-install gera os 3
  initramfs do live num `mkinitcpio -P` único. O `linux` do Arch idem
  (7752 arquivos, 0 mkinitcpio).
- ParallelDownloads 10 no conf de build; -n1 no xargs (sem ele, só a
  1ª URL era sondada); Never nos repos unsigned (archcraft/elite-local).

## v4.5 — triagem do feedback externo (só o real) + E2 offline-first

Triagem de uma análise externa do repo — 3 alegações, 2 procedentes
(1 parcialmente), 1 falsa/perigosa:

- **REAL — checkout@v4 em Node 20**: warning de deprecação confirmado
  nos logs de TODO run (`##[warning]Node.js 20 is deprecated … forced to
  run on Node.js 24: actions/checkout@v4`). Bump para `actions/checkout@v5`
  (Node 24 nativo) nos 2 jobs. `upload-artifact@v4` não gera warning
  (4.x atual já é Node 24).
- **PARCIAL — XferCommand com mais retries**: o conf de build sobe para
  `--retry 5 --retry-delay 5 --retry-connrefused --retry-all-errors
  --retry-max-time 120 --speed-time 60 --speed-limit 1024`.
  O que foi REJEITADO da sugestão (10×10s/300s): janelas reais de skew
  duram MINUTOS (run #13: 216×404) — esperar 300s às cegas não cura nada,
  só queima tempo; e no preflight a espera cegaria a sonda HEAD que
  injeta o baseline Arch em segundos (determinístico). Preflight continua
  fail-fast 3×3 (saída já vai p/ /tmp/elite-pf.log, console limpo).
  Acréscimos próprios: `--retry-connrefused` (edge CDN recusando é
  retriable) e `--speed-time/-limit` (transferência PARADA vira erro
  retriable — sem isso o curl não tem timeout e travaria até o limite
  do job).
- **FALSA — .sig dummy no [elite-local]**: o curl (37) do `elite-local.db.sig`
  era real no run #13 (12×), mas já foi eliminado NA RAIZ pelo
  `SigLevel = Never` (v4.4, runs #14/#15 com 0 curl errors na fase que
  rodou): Never = pacman não sonda .sig NENHUM. O fix sugerido seria
  nocivo: `.sig` presente + `Optional` = assinatura inválida = erro FATAL
  do pacman ("invalid or corrupted database"); sob Never o arquivo nem
  é lido. Nada aplicado — problema não existe mais.
- **E2 offline-first (além do feedback, mata a última rede do customize)**:
  `.ci/build.sh` baixa `cachyos-keyring` + `cachyos-v3-mirrorlist`
  (listing do us → pin; download cdn77 → us → pin) p/ o `[elite-local]`
  ANTES do repo-add; o E2 vira `pacman -S` file:// (primeiro repo do
  conf de build) — o chroot não toca a rede no customize. Escada de
  fallback: `[elite-local]` → `pacman -U` mirror → mirrorlist manual
  (chave via E1 keyserver). Validado ao vivo: escada executada de
  verdade (cdn77 primeiro, 200/200), pacotes abertos e conferidos
  (`usr/share/pacman/keyrings/cachyos.gpg`; `etc/pacman.d/cachyos-v3-mirrorlist`).

## v4.6 — run #16: causa raiz do preflight surdo (prova binária)

- **Run #16**: execv-safe funcionou (dbs sincronizaram; round 1 baixou
  440 pacotes em 239s), mas **2 pacotes 404aram em TODOS os 6 rounds**
  e o preflight nunca injetou baseline: `pacman -Sp --print-uris`
  morreu em TUDO com saída vazia ("db sync quebrado?" — diagnóstico
  errado).
- **Prova binária**: `--print-uris` foi REMOVIDO no pacman 6.0 (2021) —
  `strings` no binário real do core (pacman 7.1.0): 0 ocorrências de
  `print-uris`, `--print-format <string>` presente. getopt mata o
  comando com "unrecognized option" (stderr silenciado pelo 2>/dev/null)
  → zero URLs → sonda cega → injeção nunca dispara → abort.
- **Fix (2 call sites)**: `-Sp --print-uris` → `-Sp --print-format '%l'`.
  Semântica do substituto (lida no fonte 6.0.2, `pkg_get_location`):
  URL p/ pacote fora do cache, `file://<caminho>` p/ cacheado — o grep
  `^https?` filtra os locais e a sonda recebe EXATAMENTE o conjunto
  não-cacheado (o que interessa). Fonte: sync.c + util.c do pacman.
- **Diagnóstico honesto**: stderr do -Sp agora vai p/ arquivo e, se a
  lista vier vazia, o ERRO REAL do -Sp aparece no console (antes só o
  tail do -Syw — que apontava p/ lugar errado).
- **Sweep dos repos (agora)**: CachyOS 4 dbs × listing do us = 0 faltando;
  archcraft 190/190 HEADs = 200. Os 2× 404 do #16 eram janela transitória
  de propagação (02:19–02:28 UTC), já curada — a sonda+baseline é o
  remédio permanente p/ quando a janela reabrir.

## 🔬 Anomalia aberta (v1.5.2): o trigger `on.push` nunca disparou

Investigação empírica durante a validação da v1.5.2: **zero runs de evento
`push` em toda a história do repositório** (20 runs = 4 `pull_request` + 16
`workflow_dispatch`) — nem as 3 merges anteriores (que usavam `[skip ci]`,
o que criaria runs "skipped" visíveis), nem pushes diretos. Teste empírico
real (commit f7f8331, push direto em main, arquivo NÃO-ignorado
`scripts/log-forensics.sh`, sem `[skip ci]`): **nenhuma run criada**, zero
check-runs no commit, após 2+ minutos. Verificado: bloco `on:` byte-a-byte
válido (`od -c`), workflows `active` na API, Actions `enabled` com
`allowed_actions: all`, repo público (minutos infinitos), não-fork, branch
`main` sem proteção. O evento `pull_request` funciona normalmente (é ele
que roda a suíte nos PRs) e `workflow_dispatch` idem.

**Impacto operacional: nenhum** — o fluxo do projeto sempre foi dispatch
consciente pós-merge (as 16 builds da história), e permanece assim.
**Pendência:** testar trigger com outro ator/token, ou um workflow canário
minimal, se a automação de push passar a valer a pena. Nada de silêncio:
documentado aqui com o teste que o comprova.
