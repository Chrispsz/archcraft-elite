# CHANGES — Elite Edition vs. Archcraft upstream

Todo delta é aplicado pelo `scripts/apply-overlay.sh` em cima do clone fresco
do profile oficial. Nada é deletado do upstream — pacotes removidos são
**comentados** no `packages.x86_64`; arquivos Elite são sobrepostos.

## 🗺️ Visão por versão

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
