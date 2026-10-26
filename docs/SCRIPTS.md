# SCRIPTS — documentação por script

Formato: **o quê faz / como rodar / como reverter / dependências**.

---

## elite-tune (v4.6) — `/usr/local/bin/elite-tune`

**O quê:** detecção de hardware (ISA x86-64, GPU+geração, RAM/pentes/MHz, discos) e aplicação da camada Elite: repos CachyOS (chave F3B607488DB35A47 + keyring + mirrorlist via `pacman -U`, sem pacman fork), kernel BORE, daemons (ananicy, scx-elite, dmemcg, fg-booster, grub-btrfsd, lactd), boot params GRUB (quote-safe), driver NVIDIA por geração (Turing+ → `nvidia-open-dkms`; Maxwell/Pascal → orientação AUR `nvidia-580xx-dkms`), zram/sysctl/udev idempotentes, shader cache NVIDIA. **v4.5 — firstboot anti-brick:** a troca de driver NVIDIA é `-S` → `-R` (instala o dkms ANTES de remover o pré-compilado); sem rede no 1º boot o driver do live fica **preservado**, o marker `firstboot-done` **não** é escrito e a unit re-tenta no boot seguinte — o wall avisa "pendente" em vez de "REINICIE". **v4.6 — ISO v1.1:** detecta o dkms NVIDIA **pré-compilado** da ISO (módulos em `/usr/lib/modules/<kver>/updates/dkms` + nvidia-utils) → primeiro boot do rig NVIDIA instala NADA (offline total, marker na primeira passada; online vira fallback p/ sistema não-ISO); `gpu_cleanup_foreign` varre também nvidia-open-dkms e os .ko pré-compilados em rigs AMD/Intel; **guard BBR** — kernel sem bbr remove as linhas do `99-elite-net.conf` em vez de deixar sysctl morto reclamando; interativo instala só headers do BORE (kernel único).

**Modos:**
```bash
sudo elite-tune                 # interativo (dossiê + confirmação)
sudo elite-tune --dry-run      # simula (nada é escrito; pacotes não executam)
sudo elite-tune --yes          # sem confirmações
sudo elite-tune --firstboot    # não-interativo (usado pela unit elite-firstboot)
sudo elite-tune --apps         # menu de apps: Steam / Lutris+Wine / OBS / criação / escritório
elite-tune --status            # certificação (sem root) — alias: elite-status
```

**Reverter:** todo arquivo editado ganha `.bak.<timestamp>` junto ao original. Repos: remova as seções `[cachyos*]` do `/etc/pacman.conf`. Kernel: `pacman -R linux-cachyos-bore` (o `linux` do Arch nunca sai).

**Depende de:** pacman, lspci (pciutils), dmidecode, curl, GRUB (grub-mkconfig).

---

## log-forensics.sh (v1.5.2) — `scripts/log-forensics.sh` (repo, gate do CI)

**O quê:** forense determinística do log de build — a metade "máquina" da diretriz do dono ("os agentes devem analisar os logs minuciosamente; erros não podem passar como normal"; a metade semântica são deepseek/mimo do relay-agents). Varre o log inteiro atrás de padrões FATAIS que já passaram em silêncio na história do projeto (cada um é bug real: `target not found`, `could not determine root mount point`, `not enough free disk space`, `is unknown trust`, `signature from … is invalid`, `No space left on device`…) e dá run VERMELHA. Benignos são benignos POR ESCRITO (grub-editenv em chroot, journal-nocow, downloader com recuperação de baseline libyuv…); condicionais têm fronteira (downloader SEM recuperação = fatal; `command failed` fora de contexto grub = fatal).

**Como rodar:** o CI roda em toda build (`build.yml`: `tee build-output.log` + step de forense). Manual: `bash scripts/log-forensics.sh <log>`.

**Validação de campo:** log real da v1.5 (run 39864937531) → exit 0; log real da v1.4 (run 39804335535, build verde e releaseada) → exit 1 com 5 classes fatais — o gate teria barrado a ISO sem keyring ANTES do burn test.

**Reverter:** remover o step do build.yml (a suíte reprova — contrato v1.5.2).

**Depende de:** bash, grep, sed (nada além do POSIX-ish do runner).

---

## fg-booster — EXTINTO (v2.2)

**Estado:** o script, a unit e o xdotool saíram da ISO na v2.2 (fusão dos boosters no elite-tune; o Wayland não tem xdotool/EWMH — o fg-boost por janela focada era herança X11). A extinção é CONTRATO (assert_nofile do binário + da unit no CI). O boost real de first-party vive no elite-tune (dmemcg/fg slices sem depender de janela focada). Seção mantida aqui só para contar a história — quem procurar o fg-booster no instalado encontra a verdade, não um fantasma.

---

## elite-status — `/usr/local/bin/elite-status`

**O quê:** alias de `elite-tune --status` (kernel, driver cpufreq, cmdline, zram, THP, repos, estado dos serviços Elite, GPU/BAR1).

**Como rodar:** `elite-status` (sem root).

---

## apply-overlay.sh — `scripts/apply-overlay.sh` (repo)

**O quê:** o "delta" inteiro. Clona o profile oficial do Archcraft, aplica o overlay `elite/airootfs`, mescla `packages.add`, comenta os de `packages.remove`, troca o firmware meta por subpacotes, insere os repos CachyOS (trio v3 + baseline) antes de `[core]`, reescreve o **menu de boot v1.1** (3 entradas: AMD default · NVIDIA dkms · nomodeset rescue — TODAS no BORE, copy-to-RAM no default e na NVIDIA; OpenSource e a antiga 05 Copy-to-RAM saem; guarda de sanidade contra referência a kernel stock), injeta `systemd.default_timeout_start_sec=90 systemd.default_timeout_stop_sec=90` no cmdline de TODAS as entradas dos 3 bootloaders ([6.2] — no live o PID-1 vindo do initramfs não reavalia drop-ins de `/etc` após o switch_root; o cmdline é a única precedência que sempre vence), remove wants de serviços debloatados, patcha o mkarchcraftiso p/ pacstrap não-interativo, anexa o fragmento E0–E12 ao customize_airootfs, expande grupos em pacotes explícitos (CI), cria o mirrorlist do archcraft p/ o ambiente de build (root/CI) e rebatiza a ISO p/ `archcraft-elite-<data>`.

**Como rodar:** `bash scripts/apply-overlay.sh` → saída em `elite-build/`.

**Reverter:** inexistente por design — cada execução começa de um clone fresco (`rm -rf elite-build` se quiser).

**Depende de:** git, rsync, curl.

---

## craft-pin (v2.7) — `/usr/local/bin/craft-pin`

**O quê:** fixa (pin) apps na DOCK GTK (craft-dock-gui) — os launchers fixos de fábrica (Launchpad, terminal, arquivos, navegador, editor) nascem no `~/.config/elite/dock-pins` (um ID de .desktop por linha); os SEUS entram via este script. O craft-dock-gui lê o arquivo no boot e a cada reload (`craft-dock reload` = SIGUSR2 no daemon — o GUI re-lê os pins e reconstrói a pílula, SEM re-parsear o CSS). O indicador de "aberto" (pílula `running`) acompanha: 1 pgrep com alternância por tick de 3s (v2.5.0 — era 1 por pin). **v2.7.0:** a linha do dock-pins pode levar uma 2ª coluna — o **hint de app_id** que a dock usa para FOCAR a janela (ex.: `thunar.desktop org.xfce.Thunar` — apps GTK se apresentam com o id da GApplication, que nem o StartupWMClass nem o binário adivinham). O add/rm viraram CONSCIENTES da coluna (dedup e remoção por `$1`, nunca pela linha inteira — o hint não quebra nada).

```bash
craft-pin list                    # apps fixados
craft-pin add steam               # fixa pelo ID desktop (resolve pelo nome)
craft-pin rm steam                # desfixa
craft-pin reload                  # re-lê os pins (SIGUSR2 na dock)
craft-pin restore                 # desfaz a última alteração
```

**Como rodar:** `craft-pin <comando>` (sem root — edita `~/.config/elite/dock-pins`).

**Reverter:** `craft-pin rm <nome>`, `craft-pin restore`, ou restaure o `.bak.last`.

**Depende de:** sh, craft-dock-gui (a dock GTK — NÃO o waybar; a era config.dock/style.dock.css morreu com a waybar-dock v1.x e é proibida por contrato).

---

## elite-customize.sh (fragmento E0–E12) — anexado ao customize_airootfs do upstream

**O quê:** roda DENTRO do airootfs no fim do build. E0: DNS do chroot. E1: chave CachyOS no keyring (vale p/ live e instalado — o gnupg é copiado pelo unpackfs). E2: keyring+mirrorlist v3 via `pacman -U` (fallback: mirrorlist escrito na mão). E3: pacman.conf do sistema reescrito limpo (archcraft → cachyos → core/extra/multilib). E4: `pacman -Sy` valida os 6 repos no chroot. E5: cirurgia no Calamares (unpackfs copia o vmlinuz BORE; instância `initcpio@elite`; packagechooser só labwc; btrfs default). E6/E6b: presets default/fallback do BORE **e** do kernel stock p/ o instalado. E7: tira cups/avahi da lista de serviços do post-install do Archcraft. E8: remove o repo de build `[elite-local]` da ISO. E9: limpa do skel configs de sessões extintas. **E10 (v1.0.4): recopia TODOS os vmlinuz-\*** do pendrive p/ `/boot` do alvo (o rsync→btrfs do unpackfs truncava arquivos grandes — causa-raiz do `premature end of file` no rig B) **e regenera o initramfs do BORE no alvo** com hooks de sistema.

**Como rodar:** automático (mkarchcraftiso chama o customize_airootfs.sh no build).

**Reverter:** n/a (build-time; o resultado vai pra ISO).

---

## elite-firstboot.service — unit (airootfs overlay)

**O quê:** no primeiro boot do sistema **instalado** (nunca no live: `ConditionPathExists=!/run/archiso`), roda `elite-tune --firstboot` (driver GPU + serviços + tokens GRUB), loga em `/var/log/elite-firstboot.log`, cria o marker `/var/lib/elite/firstboot-done`, se auto-desativa e avisa via `wall` p/ reiniciar.

**Como rodar:** automático. Manual: `sudo systemctl start elite-firstboot`.

**Reverter:** `sudo systemctl disable elite-firstboot` + remover o marker p/ reexecutar: `sudo rm /var/lib/elite/firstboot-done`.

---

## craft-power (v2.6.0) — `/usr/local/bin/craft-power`

**O quê:** menu de sessão do botão ⏻ da barra, MINIMALISTA como o dono pediu — entradas: Sair da sessão · Suspender · Reiniciar · Desligar · Tempo de idle… · Rollback do sistema…. **'Travar tela' saiu do menu** (o dono: "é necessária essa opção?" — não: o lock é PARTE do suspender e segue vivo no W-l). **O SUSPENDER DE VERDADE** (o dono: "tenta mas rapidamente liga e fica como se eu só tivesse clicado em travar tela"): trava PRIMEIRO (craft-lock — acorda no wallpaper borrado) e suspende com `systemctl suspend -i` — inibidores de sono de apps (navegador/players) IGNORADOS, que era a morte calada do suspend antigo. Fallback labnag preservado (e o labnag aberto também vira toggle). O menu nasce SOB O BOTÃO (--at=power). Toda abertura e toda falha deixam linha no `menus.log`.

**Como rodar:** clique ESQUERDO no botão ⏻ da barra (custom/power) — a lei dos dois botões v2.7.0: a barra é INTERFACE e clica com o ESQUERDO; o direito fica para o desktop (onde não há botão). O 2º clique no MESMO botão fecha (toggle por pid).

**Reverter:** n/a — o motor é o fuzzel do sistema; as entradas moram neste script.

**Depende de:** craft-menu (fuzzel), craft-lock, systemctl (ações via polkit — ver `49-elite-desktop.rules`).

---

## craft-menu (v4.1 — O MOTOR QUE ABRE, ANCORA, TOGGLA E ENGAIOLA) — `/usr/local/bin/craft-menu`

**O quê:** o menu da distro — `fuzzel --dmenu` em POSIX sh puro (a era GTK nunca abriu no rig: duas reescritas, dois funerais — história na v3). As TRÊS CURAS v2.6.0 (prints do rig 26/out, o dono: "solucione tudo de uma vez por todas"):

1. **LISTA PURA** — `--hide-prompt` mata a linha de digitação inteira: sem o nome ('Sessão:', 'Encerrar:'), sem o "risco |" que ficava na frente ("tirar esse risco"). Digitar ainda filtra, às escondidas; `--minimal-lines` encolhe a janela para o tamanho da lista.
2. **ANCORA NO BOTÃO** — `--anchor top-right` + `--x-margin` calibrado POR SLOT (`--at=power|bgapps|network|drawer`): o menu nasce SOB O BOTÃO que o chamou ("não seria melhor ficar onde ela for aberta?"), não no centro da tela. A barra de 36px empurra a layer pelo exclusive zone; submenus herdam o slot do pai.
3. **LEI DETERMINÍSTICA** — o toggle e o cross-dismiss deixaram de depender da física do foco (que o rig DESMENTIU: "clico de novo e não fecha, um não anula o outro"): o pid do fuzzel vivo fica em `$XDG_RUNTIME_DIR/elite-menus.<uid>`; 2ª chamada do MESMO título mata e sai 2 (toggle); título diferente mata e abre o novo (cross-dismiss). Probe `fuzzel --help` degrada graciosamente em fuzzel velho. E `id -u`, NUNCA a variável UID do bash (dash não a tem — sob `set -u` era morte rc=2 silenciosa que o chamador lia como toggle benigno; flagrado no smoke test).
4. **A GAIOLA (v4.1/v2.7.0)** — "quando eu quiser fechar um menu clicando fora não vai abrir o menu da home": o clique de fora não vaza MAIS. A dock (processo GTK quente desde o boot) é pedida por SIGRTMIN (pid em `elite-dock.<uid>`) e mapeia uma superfície INVISÍVEL que engole todo clique fora do menu aberto e da barra e mata o fuzzel pelo pid do state — o desktop NEM VÊ o clique. Handshake por arquivo (ack em `elite-cage.<uid>`, prazo 30×10ms = 300ms): sem ack o menu abre IGUAL (degradação graciosa — o ESC e o toggle por pid são universais). E o `trap EXIT` limpa o state do toggle e o ack em TODO fechamento (sem pid zombie, sem gaiola órfã).

```bash
craft-menu --title='Sessão' --at=power 'Sair da sessão' 'Suspender'   # argv
printf '%s\n' 'brave (pid 123)' | craft-menu --title='Encerrar' --at=bgapps   # stdin
craft-menu --title='Senha Wi-Fi' --at=network --ask='Senha' </dev/null   # modo entrada
```

**Gramática de saída (contrato com os 6 chamadores — intocada):** escolha no stdout · exit 0 · fechado sem escolha (ESC / clique fora) = **exit 1** (fechar NUNCA é falha) · **exit 2** = TOGGLE real (a 2ª chamada do mesmo título fechou) · **143** = morto por SIGTERM (cross-dismiss) · outros = falha REAL (stderr vivo para o chamador logar + avisar e SOME).

**Como rodar:** pelos módulos que abrem menu — Sessão (craft-power), Encerrar (craft-bgapps), idle (craft-idle), rollback (craft-rollback), sair (craft-logout), rede (craft-connect). TODOS por clique ESQUERDO (a lei dos dois botões v2.7.0: a barra é interface; o direito é do desktop).

**Depende de:** fuzzel ≥ 1.10 (anchor/hide-prompt — a ISO carrega o corrente), sh. O rice do menu morto (menu.css) foi aposentado.

---


## craft-bgapps (v4.0 — SÓ PROGRAMA DO DONO) — `/usr/local/bin/craft-bgapps`

**O quê:** o botão de apps em 2º plano da menu bar (módulo `custom/bgapps`) — só ocupa a barra QUANDO há programa do usuário fora da casca da sessão (texto vazio = some). A LEI v2.3.10 (fica): o que é da SESSÃO nunca aparece, e TODO programa de verdade aparece — varredura do `/proc`/ps REAL do UID, casamento POR PREFIXO (o ps corta o comm em 15 caracteres). A LEI v2.4.0: **UM PROCESSO POR PROGRAMA** — o PRINCIPAL de cada árvore; renderers do Chromium são a sombra, NUNCA entrada; tooltip = DESCRIÇÃO curta. A LEI v2.6.0 (o dono, foto do rig: "continua pegando serviços do sistema que inclusive não encerram — (sd-pam), dconf-service, gvfs-udisks2-vo, gvfs-mtp-volume"):

- **comm NORMALIZADO** — o sd-pam se apresenta como `(sd-pam)` (com parênteses!) e escapava do padrão `sd-pam*`; os parênteses saem antes do casamento. A casca ganhou `dconf*`, `gvfs*` (cobre gvfsd E os monitores gvfs-*), `Xwayland*`, `hyprlock/hypridle/hyprpaper`, `labnag*`;
- **CANDIDATO SEM DISPLAY NUNCA É PROGRAMA** — `/proc/PID/environ` sem `WAYLAND_DISPLAY=`/`DISPLAY=` é assinatura de serviço de fundo (o Brave e o Files conversam com o compositor; sd-pam/dconf/gvfs, nunca);
- **ENCERRAR DE VERDADE** — SIGTERM, 2s de paciência, SIGKILL em quem aguentou (o dono clica UMA vez);
- **ÃNCORA** — o menu nasce sob o PRÓPRIO botão (--at=bgapps) e abre no clique ESQUERDO (v2.7.0 — a lei dos dois botões; o 2º clique fecha).

```bash
craft-bgapps status   # JSON do módulo waybar (vazio = botão some)
craft-bgapps menu     # clique ESQUERDO: craft-menu com "nome (pid N)"
```

**Como rodar:** automático (o waybar executa `status` a cada 10s; clique ESQUERDO abre o `menu`).

**Depende de:** sh, ps, /proc; craft-menu para o menu.

---

## craft-connect (v6.0 — A CENTRAL RÁPIDA QUE CONTROLA O NetworkManager) — `/usr/local/bin/craft-connect`

**O quê:** o menu do ícone de rede da barra — e agora ele CONTROLA a rede, não só chama o gerenciador. O `nmcli` (o cli do PRÓPRIO NetworkManager) é a fonte única de verdade — cada verbo é UM comando do serviço. **v6 (v2.7.0) — RÁPIDO DE VERDADE + salvas que se gerem** (o dono: "o menu de redes não ficou tão responsivo e rápido apesar de finalmente funcionar… buscar redes por exemplo demora um pouco" + "no mínimo seria interessante conseguir excluir rede diretamente da tela de conexões salvas ou até mesmo editar a senha… deixar a parte de editor para editar as redes invés de criar um menu só pra isso"):
- **A LISTA ABRE DO CACHE** — `nmcli device wifi list --rescan no`: instantânea (a varredura bloqueante da era v5 travava a abertura por 2–8s). A varredura nova roda EM FUNDO (fogo-e-esquece na abertura da central e ao entrar em Redes Wi-Fi) — a próxima lista já nasce fresca;
- **Atualizar…** — a varredura EXPLÍCITA: pede o rescan e espera a PROVA da varredura nova pelo relógio do dispositivo (`nmcli -g LAST_SCAN device show <dev>` — comparar listas falha quando o fundo já varreu). Sem relógio, sem espera (honesto, nunca preso);
- **PARALELO** — status de dispositivos e rádio consultados ao MESMO tempo (wait) — a central responde na hora;
- **Cabo**: Ligar/Desligar por dispositivo (`nmcli device connect/disconnect` — estados ao vivo no menu);
- **Wi-Fi**: liga/desliga o rádio (`nmcli radio wifi`);
- **REDES WI-FI**: lista com sinal e 🔒 (● = conectada); rede salva sobe pelo nome (senha do cofre do NM, sem prompt); rede aberta conecta direta; rede nova protegida pede a senha no menu (`craft-menu --ask`);
- **CONEXÕES SALVAS que se GEREM** — o pick da conexão abre os VERBOS DELA, estado-aware: Conectar/Desconectar (`nmcli connection up/down`, ● = ativa) · **Alterar senha…** (Wi-Fi: `nmcli connection modify … 802-11-wireless-security.psk` + `up` para provar a senha nova AGORA) · **Esquecer…** (`nmcli connection delete` COM confirmação — apagar rede salva não pode ser acidente). SEM menu separado de gestão: a tela de salvas edita as redes no próprio lugar (o editor gráfico fica para a CRIAÇÃO manual, definição do próprio dono);
- **Bluetooth: dispositivos…** — o verbo que o dono APROVOU segue (blueman-manager, bluetui de fallback);
- **Editor de conexões…** — a CRIAÇÃO manual mora no nm-connection-editor.

O bug do picker v3 (conectou 3× com senha correta e falhou — menus.log 23:14) morreu de vez: o par linha→SSID/segredo vive num MAPA escrito pelo MESMO awk que desenha a lista (`$XDG_RUNTIME_DIR/elite-net.<uid>.map`) — o valor devolvido ao NM é o que o NM entregou, nunca parse de tela. Cada ação reabre o menu com o estado NOVO. O menu nasce SOB O BOTÃO de rede (--at=network) e abre no clique ESQUERDO (v2.7.0 — a lei dos dois botões; o 2º clique fecha).

```bash
craft-connect   # clique ESQUERDO no ícone de rede: cabo on/off, Wi-Fi on/off, conectar redes, gerenciar salvas
```

**Como rodar:** clique ESQUERDO no módulo `network` da barra. Teclado segue: W-n (editor), W-S-b (bluetui).

**Depende de:** nmcli (NetworkManager), craft-menu; nm-connection-editor (editor), blueman-manager/bluetui (Bluetooth), foot+impala como fallback TUI.

---

## craft-dock-gui (v2.7 — DOIS VERBOS NO CLIQUE + A GAIOLA) — `/usr/local/bin/craft-dock-gui`

**O quê:** a dock GTK nativa (layer BOTTOM, sempre visível, zona exclusiva, pílula de ícones reais via Gio.DesktopAppInfo — história v2.0/v2.3.4 no cabeçalho do script). **v2.7.0 (o dono: "clicar num programa já aberto ele deve ir para a tarefa aberta invés de abrir outra pois vi que isso acontece com alguns programas, se o usuário quiser abrir outra rapidamente ele pode fazer clicando no ícone com o botão direito")**:
- **ESQUERDO num pin** — se o programa ESTÁ rodando (pílula), FOCAR a janela dele (`wlrctl window focus app_id:…` — wlr-foreign-toplevel, que o labwc fala); se NÃO está, abrir. Não rodando = abrir DIRETO (zero subprocesso no caminho comum — instantâneo). A adivinhação do app_id segue ordem: hint explícito (2ª coluna do dock-pins) → StartupWMClass → binário → stem do desktop-id; TODOS falharam → abre (nunca pior que antes);
- **DIREITO num pin** — abrir OUTRA instância, sempre (o verbo rápido para "quero outro agora");
- **A GAIOLA** — o craft-menu pede por SIGRTMIN (pid da dock em `$XDG_RUNTIME_DIR/elite-dock.<uid>`) e a dock mapeia uma superfície INVISÍVEL (layer TOP, tela inteira, teclado NONE, transparente) cuja região de ENTRADA é a tela MENOS a faixa da barra: todo clique fora do menu aberto mata o fuzzel pelo pid do state e some — o desktop NEM VÊ o clique ("fechar um menu clicando fora" nunca mais abre o menu-raiz). Ela se desarma sozinha vigiando o state (some com o menu) e nasce PREGUIÇOSA (não existe até o 1º menu);
- **Tooltip honesto** — com wlrctl: "esquerdo: focar/abrir · direito: nova janela"; sem: "clique: abrir".

```bash
craft-dock toggle   # W-S-d: esconder/mostrar (SIGUSR1)
craft-dock reload   # craft-pin: re-lê os pins (SIGUSR2)
```

**Depende de:** python3 + PyGObject (Gtk 3, GtkLayerShell), wlrctl (foco — compilado no build a partir da FONTE VENDADA em `vendor/wlrctl-0.2.2.tar.gz`, sha256 pinado; sem ele o esquerdo só abre), pgrep.

---

## craft-shot (v1.x) — `/usr/local/bin/craft-shot`

**O quê:** screenshots defensivos (grim + slurp + wl-copy). `area` = região selecionada com o mouse → clipboard + arquivo; `full` = tela cheia → arquivo. O arquivo nasce em `~/Pictures/shot-YYYYmmdd-HHMMSS.png`. Cancelar o slurp = silêncio (fechar a seleção não é erro — nenhum toast de falha).

```bash
craft-shot area   # região → clipboard + arquivo
craft-shot full   # tela inteira → arquivo
```

**Como rodar:** atalhos W-P (região) e W-Shift-P (tela inteira) do rc.xml. O botão de print da barra nasceu (v2.3.7) e morreu (v2.3.10, "melhor remover") — os verbos vivem no teclado, sem assento fixo na barra.

**Depende de:** grim, slurp (área), wl-clipboard, notify-send (opcional).

---

## craft-bat — `/usr/local/bin/craft-bat`

**O quê:** relatório de bateria no terminal (nível, estado, saúde, tempo estimado) — a CLI de bolso para o dono checar a bateria sem abrir nada. Sem launcher/keybind por design: é ferramenta de terminal (o dono perguntou o comando, ganhou o script).

```bash
craft-bat
```

**Depende de:** sh, /sys/class/power_supply.
