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

## fg-booster (v4.1.1) — `/usr/local/bin/fg-booster` (unit `fg-booster.service`)

**O quê:** a cada segundo, identifica a janela em foco (xdotool, EWMH — Openbox/BSPWM ok) e promove a árvore de processos dela para `fg-boost.slice` (CPUWeight/IOWeight 900, **sem teto de VRAM** — os tetos são do dmemcg-booster). Ao perder o foco, devolve cada processo ao **cgroup leaf de origem** (registrado no momento da promoção; escrita em leaf é sempre permitida pelo cgroup v2 — o bug da v4.0, que devolvia p/ um slice interno e era rejeitado, morreu). PIDs mortos são limpos do mapa a cada 30 polls. **v4.1.1 (v1.5.2):** guards de ambiente (xdotool/slice ausentes) saem **0** — no-op limpo — em vez de `exit 1`; a unit ganha `StartLimitIntervalSec=120`/`StartLimitBurst=3`. Forense: o debloat v4.2 varreu o xdotool do packages.add e o `exit 1` + `RestartSec=5` (que nunca atinge o start-limit default) crash-loopou o serviço em TODA boot v1.0→v1.5, no live E no instalado — 17 `Failed with result` no serial do gate verify da v1.5, invisível porque nenhum gate varria units falhadas (v1.5.2 fecha isso também).

**Como rodar:** já vem habilitado (`graphical.target.wants`). Manual: `sudo systemctl enable --now fg-booster`.

**Validar:** `systemd-cgls /fg-boost.slice` — o app focado aparece no slice e some ao perder o foco. `elite-tune --status` mostra quantos PIDs estão no slice.

**Reverter:** `sudo systemctl disable --now fg-booster`.

**Depende de:** xdotool (contrato de BUILD no CI — v1.5.2), cgroup v2, X11 com WM EWMH (não serve p/ Wayland).

---

## elite-status — `/usr/local/bin/elite-status`

**O quê:** alias de `elite-tune --status` (kernel, driver cpufreq, cmdline, zram, THP, repos, estado dos serviços Elite, GPU/BAR1, contador do fg-boost.slice).

**Como rodar:** `elite-status` (sem root).

---

## apply-overlay.sh — `scripts/apply-overlay.sh` (repo)

**O quê:** o "delta" inteiro. Clona o profile oficial do Archcraft, aplica o overlay `elite/airootfs`, mescla `packages.add`, comenta os de `packages.remove`, troca o firmware meta por subpacotes, insere os repos CachyOS (trio v3 + baseline) antes de `[core]`, reescreve o **menu de boot v1.1** (3 entradas: AMD default · NVIDIA dkms · nomodeset rescue — TODAS no BORE, copy-to-RAM no default e na NVIDIA; OpenSource e a antiga 05 Copy-to-RAM saem; guarda de sanidade contra referência a kernel stock), injeta `systemd.default_timeout_start_sec=90 systemd.default_timeout_stop_sec=90` no cmdline de TODAS as entradas dos 3 bootloaders ([6.2] — no live o PID-1 vindo do initramfs não reavalia drop-ins de `/etc` após o switch_root; o cmdline é a única precedência que sempre vence), remove wants de serviços debloatados, patcha o mkarchcraftiso p/ pacstrap não-interativo, anexa o fragmento E0–E12 ao customize_airootfs, expande grupos em pacotes explícitos (CI), cria o mirrorlist do archcraft p/ o ambiente de build (root/CI) e rebatiza a ISO p/ `archcraft-elite-<data>`.

**Como rodar:** `bash scripts/apply-overlay.sh` → saída em `elite-build/`.

**Reverter:** inexistente por design — cada execução começa de um clone fresco (`rm -rf elite-build` se quiser).

**Depende de:** git, rsync, curl.

---

## craft-pin (v1.1) — `/usr/local/bin/craft-pin`

**O quê:** fixa (pin) apps do usuário na DOCK — os launchers fixos do skel (Launchpad, terminal, arquivos, navegador, editor, screenshot) nascem na ISO; os SEUS ficam na seção `PINS` do `config.dock`, gerenciada por este script. Um pin = 1 linha JSONC no config + 1 entrada no `modules-left` + 1 bloco CSS autocontido no `style.dock.css` com o mesmo DNA visual dos fixos (glyph 30px → zoom 34px no hover, realce surface, cor Catppuccin à escolha). As vírgulas do JSON ficam SEMPRE corretas (juiz: parse JSON a cada mutação); skel antigo sem a seção PINS é auto-curado; toda alteração grava `.bak.<ts>` dos dois arquivos e recarrega as barras via `SIGUSR2` (man 5 waybar: "By default reloads (resets) the bar" — config + estilo, sem reiniciar a sessão). Limite honesto vs macOS: app fixado rodando aparece como ícone extra no CENTRO (wlr/taskbar) — o waybar não une pin+running.

```bash
craft-pin list                                  # apps fixados
craft-pin add steam   ''  Steam    steam     green
craft-pin add discord ''  Discord  discord   mauve
craft-pin add code    ''  VS Code  code      sky
craft-pin rm steam                               # desfixa
craft-pin reload                                 # recarrega as barras (SIGUSR2)
craft-pin restore                                # desfaz a última alteração
```

**Como rodar:** `craft-pin <comando>` (sem root — edita `~/.config/waybar/`). GLYPH é um glifo Nerd Font (nerdfonts.com/cheat-sheet); NOME só `[a-z0-9-]`; COR é um nome Catppuccin do `style.dock.css` (padrão `mauve`).

**Reverter:** `craft-pin rm <nome>` por pin, `craft-pin restore` para a última alteração, ou restaure os `.bak.<ts>` manualmente. Add/rm em qualquer ordem devolve os arquivos **byte a byte** ao estado de fábrica (garantido por teste).

**Depende de:** bash, awk, sed, grep, waybar (opcional — sem waybar rodando, só avisa).

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

## craft-power (v2.1 → motor v2.4.0) — `/usr/local/bin/craft-power`

**O quê:** menu de sessão do botão ⏻ da barra com toggle por pressão (2º ⏻ fecha — "esse tipo de erro não pode existir"). v2.3.8: passou ao craft-menu (o menu da casa — fim do dropdown ancorado próprio). v2.4.0: o motor do craft-menu é o fuzzel — a escolha nasce no motor com prova de vida no rig. Entradas: Travar tela · Sair da sessão · Suspender · Reiniciar · Desligar · Tempo de idle…. Fallback labnag preservado (e o labnag aberto também vira toggle). Toda abertura e toda falha deixam linha no `menus.log`.

**Como rodar:** botão ⏻ da barra (custom/power) ou menu raiz.

**Reverter:** n/a — o motor é o fuzzel do sistema; as entradas moram neste script.

**Depende de:** craft-menu (fuzzel), systemctl (ações via polkit — ver `49-elite-desktop.rules`).

---

## craft-menu (v3.0 — O MOTOR QUE JÁ ABRIA) — `/usr/local/bin/craft-menu`

**O quê:** o menu da distro — v3 = `fuzzel --dmenu` em POSIX sh puro. A era GTK (v2.3.8 nativa → v2.3.11 "gaiola") **nunca abriu no rig real**: duas reescritas, dois funerais — a v1 morria antes do 1º frame (corrida de foco no mapa) e a gaiola também não nasceu na máquina do dono. A v3 usa o ÚNICO motor com prova de vida no rig: o fuzzel — o launcher e o menu de Sessão sempre abriram, filtraram e fecharam nele (a cura v2.3.6 do clique-fora foi provada NA MÁQUINA). Zero GTK, zero layer-shell, zero corrida de foco para EXISTIR: a classe "morre antes do 1º frame" está extinta por construção — não existe mais toolkit para falhar. A lei dos menus virou FÍSICA: só existe um teclado — abrir outro menu rouba o foco e o anterior FECHA SOZINHO (`exit-on-focus-loss=yes`, contrato no fuzzel.ini); o 2º clique no botão fecha (burn test v1.4 do Sessão provou).

```bash
craft-menu --title='Sessão' 'Travar tela' 'Sair da sessão' 'Suspender'   # argv
printf '%s
' 'brave (pid 123)' | craft-menu --title='Encerrar'          # stdin (listas dinâmicas)
```

**Gramática de saída (contrato com os 7 chamadores — intocada):** escolha no stdout · exit 0 · fechado sem escolha (ESC / clique fora / foco perdido) = **exit 1 com stderr vazio** (fechar NUNCA é falha) · **143** = morto por SIGTERM (cross-dismiss) · outros = falha REAL (stderr vivo para o chamador logar + avisar e SOME). O título vive no prompt do fuzzel: contexto + filtro por digitação.

**Como rodar:** pelos módulos que abrem menu — Sessão (craft-power), Encerrar (craft-bgapps), idle (craft-idle), rollback (craft-rollback), sair (craft-logout), rede (craft-connect).

**Depende de:** fuzzel (dmenu), sh. O rice do menu morto (menu.css) foi aposentado.

---


## craft-bgapps (v3.0 — UM processo por PROGRAMA) — `/usr/local/bin/craft-bgapps`

**O quê:** o botão de apps em 2º plano da menu bar (módulo `custom/bgapps`) — só ocupa a barra QUANDO há programa do usuário fora da casca da sessão (texto vazio = some). A LEI v2.3.10 (fica): o que é da SESSÃO nunca aparece (compositor, barras, áudio, dbus, portals, keyring, idle, notificações, clipboard, automount, acessibilidade, systemd/sd e os craft-*/elite-*), e TODO programa de verdade aparece — nativo, flatpak (o processo real dentro do sandbox tem o próprio nome), AppImage, interpretado — varredura do `/proc`/ps REAL do UID, casamento POR PREFIXO (o ps corta o comm em 15 caracteres). A LEI v2.4.0 (o dono: "abri o Brave e abriu 11 serviços… só no processo principal"): **UM PROCESSO POR PROGRAMA** — entra no menu o PRINCIPAL de cada árvore (o candidato cujo PAI não é outro candidato); renderers/gpu/utility do Chromium e derivados, zygotes, crashpad e o app dentro do sandbox do flatpak são a sombra do programa, NUNCA entrada; cintura de segurança: cmdline com ` --type=` nunca é principal, nem órfã adotada pelo init. O tooltip é DESCRIÇÃO curta (a gramática dos outros módulos) — o preview da lista morreu ("não precisa de preview apenas uma descrição… ao clicar que abre o menu"). Status à prova de bala: qualquer falha interna ainda emite JSON válido (o botão só some sem programa de verdade).

```bash
craft-bgapps status   # JSON do módulo waybar (vazio = botão some)
craft-bgapps menu     # craft-menu com "nome (pid N)"; o escolhido recebe SIGTERM
```

**Como rodar:** automático (o waybar executa `status` a cada 10s; clique abre o `menu`). Encerramento = SIGTERM + notificação que SOME.

**Depende de:** sh, ps, /proc; craft-menu para o menu.

---


## craft-shot (v1.x) — `/usr/local/bin/craft-shot`

**O quê:** screenshots defensivos (grim + slurp + wl-copy). `area` = região selecionada com o mouse → clipboard + arquivo; `full` = tela cheia → arquivo. O arquivo nasce em `~/Pictures/shot-YYYYmmdd-HHMMSS.png`. Cancelar o slurp = silêncio (fechar a seleção não é erro — nenhum toast de falha).

```bash
craft-shot area   # região → clipboard + arquivo
craft-shot full   # tela inteira → arquivo
```

**Como rodar:** atalhos W-P (região) e W-Shift-P (tela inteira) do rc.xml. O botão de print da barra nasceu (v2.3.7) e morreu (v2.3.10, "melhor remover") — os verbos vivem no teclado, sem assento fixo na barra.

**Depende de:** grim, slurp (área), wl-clipboard, notify-send (opcional).
