# ARQUITETURA — o código-fonte interrogado: 10 palavras-chave × 10 questionamentos

Data: 2026-11-02 · E36 · origem: pedido do dono — *"peguei todo o nosso código fonte e transformei em
palavras-chave para fazer pesquisas aprofundadas sobre como melhorar cada coisa… faz 10 questionamentos
sobre cada palavra-chave e estruture o código da melhor forma possível"*.

## Método

O repo INTEIRO (`0cf16b1`: 32 bins em `elite/airootfs/usr/local/bin/`, ~6.300 linhas de scripts, 117
arquivos de overlay, suíte, workflows, docs) foi reduzido a **10 palavras-chave**. Seis auditores
independentes leram os arquivos em escopo NA ÍNTEGRA e responderam cada questionamento com evidência
`arquivo:linha`. Tudo que este documento afirma foi re-verificado pela manutenção antes de cravar —
incluindo **duas correções à própria auditoria** (seção "Correções"). As curas de baixo risco e alto
impacto saíram NA MESMA rodada (seção "Curas aplicadas"); o resto vive no plano ranqueado do fim.

## O mapa de palavras-chave

| # | Palavra-chave | Arquivos no escopo (linhas) |
|---|---------------|------------------------------|
| 1 | **dock** | `craft-dock-gui` (1049) · `craft-dock` · `craft-pin` · `craft-pin-pick` · `dock-pins` · `dock.css` · `vendor/craft-toplevel.c` (804) |
| 2 | **tune** | `elite-tune` (918) · `elite-firstboot.service` · `craft-hello` |
| 3 | **sessão** | labwc (rc/menu/autostart/environment) · waybar · fuzzel · swaync · nwg-drawer · foot · gtk · sddm · hyprlock · `craft-bars/menu/menu-dismiss/drawer/bgapps/idle/lock/logout/power/shot/bat/wake-guard` · `elite-session-probe` · cliphist · sleep/timeout units |
| 4 | **arquivos** | Thunar `uca.xml` · `craft-extract` · `mimeapps.list` · `xfce4/helpers.rc` · xarchiver/7zip/zenity no `packages.add` (o `craft-compress` morreu com honra na E72 — ordem do dono) |
| 5 | **áudio** | `craft-audio-route` (256) · pipewire/pwvucontrol no `packages.add` |
| 6 | **rede-kernel** | `craft-connect` (539) · sysctl 99-elite(-net) · BBR · zram · udev I/O · preset BORE |
| 7 | **saúde** | `craft-dump` (565) · `elite-sweep` · `craft-rollback` · `craft-fix-keys` · keyring-fix unit+timer · `craft-update` · `elite-status` · `craft-clean` · `craft-keyring-wait` · journald cap |
| 8 | **instalação** | `elite-install-stage` (394) · `calamares-elite-log` · `calamares.desktop` · `validate-calamares.py` · verify-install.yml |
| 9 | **build-pacotes** | `apply-overlay.sh` (514) · `.ci/build.sh` · `qemu-boot-test.sh` · fragments · `packages.add/remove` · pins (Brave/pywal/wlrctl) · vendor |
| 10 | **porteira-gestão** | `tests/**` (6 fases) · 5 workflows · `agents/*.ts` · `docs/**` · leis do PROTOCOL |

## Veredicto por palavra-chave

| Palavra | Veredito | O achado central |
|---------|----------|------------------|
| dock | ⚠️ madura com 2 feridas na borda | o casamento por TÍTULO serve o verbo DESTRUTIVO (meio-click fecha janela alheia); o CSS de fallback ainda desenha a barrinha que o dono rejeitou (espelho E33) |
| tune | ⚠️ maquinaria de campo, espelhos doentes | enxerto interativo em CPU pré-v3 AVISA e mesmo assim instala o kernel v3 (SIGILL no boot); espelhos firstboot↔interativo já morderam 1× (guard do snapper) |
| sessão | ⚠️ sistema de verdade com leis não cumpridas | o knob "Suspender" morre calado com Lock=Nunca; 4 mentiras E33 vivas; swaync/udiskie/polkit são órfãos sem supervisão; cursor muda de sotaque entre greeter/desktop/apps |
| arquivos | ✅ fluxo bom, provas incompletas | o verbo do E35 é o que o dono pediu; a lição 7z rc=1 não foi espelhada no tar; o rig do dono não recebe a cura (sem scripts/live/cura-e35); as provas funcionais juradas no commit não estão na suíte |
| áudio | ✅ maduro, 1 bug real de classe | BAD_RE pega o microfone pela MARCA (fifine), não pela classe — "USB Microphone" em EN escapa e pode virar default; o contrato jura cobertura pt+en que o código não tinha |
| rede-kernel | ✅ acima da média | espinha dorsal sênior; feridas de consistência (stderr capturado num verbo e não nos irmãos; linha de Bluetooth sem adaptador; senha Wi-Fi visível com README jurando "senha oculta") |
| saúde | ✅ fundação excelente | o núcleo (keyring, dump anti-mentira, sweep) é o mais maduro do repo; rollback/fix-keys ainda chutam a causa no toast (stderr destruído); `--upload` manda papel com SSIDs/IPs para paste público sem avisar |
| instalação | ⚠️ boa com 1 contradição lógica | o knob do os-prober (promessa D2) e o gate kernel-único BRIGAM no mesmo script: 2º Linux no disco = Installation Failed; porta de entrada do leigo em EN |
| build-pacotes | ✅ nível produção | preflight/preflight-offline/vendoring exemplares; a base upstream flutua sem pin; check-brave é guardião órfão; o overlay copiaria `__pycache__` para a ISO (o E35 curou o sintoma, não a fonte) |
| porteira-gestão | ✅ funciona, flanco cego: DOCOS | ~1,4 min, testa a si mesma nos 2 sentidos; README mente sobre o produto (timeshift/2 barras) e nada pega; SCRIPTS.md documentava ~1/3 dos scripts; o gate nem roda quando `docs/**` muda |

---

## Os 100 questionamentos (condensados — veredito com a evidência no repo)

### 1. dock

1. **O casamento por título alimenta verbo destrutivo?** ❌ — `_windows_of` usa `(name and name in t)`
   como último recurso (craft-dock-gui:638-640) e o MEIO fecha TODOS os ids casados (:664-675): a aba
   "Arquivos do Windows" do Brave casava com o Thunar pt-BR e recebia WM_DELETE. Falso positivo em foco
   é chato; em fecho é perda de dados.
2. **O tick de 1s é de graça?** ⚠️ — /proc scan e LIST por socket persistente são bons; os comms sem
   .desktop varrem o índice inteiro por tick sem cache negativo (:464-466); `_dindex` nunca invalida.
3. **Os DOIS CSS (skel e fallback embutido) são espelho?** ❌ — o skel desenha a bolinha 6×3px v2.3.7
   (dock.css:45-57); o `DEFAULT_CSS` embutido ainda desenha `box-shadow: inset 0 -3px 0` (:1024) — A
   barrinha que o dono mandou matar — e não tem `:active` nem `transition`.
4. **`craft-pin add` duplicado: quem mente?** ⚠️ — código sai rc 0 (craft-pin:72-74); o contrato
   30-unit:365 jura "rc ≠ 0" e o picker notifica "'$choice' fixado" MESMO quando nada mudou.
5. **Picker e craft-pin enxergam o mesmo universo?** ⚠️ — o `resolve()` do craft-pin inclui
   `$XDG_DATA_HOME/applications` (craft-pin:20); o picker varre só os 2 dirs de sistema (craft-pin-pick:51).
6. **.desktop com `Terminal=true` no clique?** ❌ — nada acontece: `exec_of` só limpa `%field`, o campo
   Terminal tem ZERO ocorrências no GUI; o processo morre sem TTY e sem mensagem (o pior relato do leigo).
7. **O daemon C é robusto?** ✅ — flock antes do probe, O_NONBLOCK, teto MAX_WIN, sweep fora do callback,
   título sanitizado, supervisão por comm.
8. **A lei do fallback sobrevive à morte no meio do clique?** ✅ — degrada para `_fallback_focus` com o
   MESMO casamento; snapshot velho não lança duplicado; suíte trava a lei (40-int:2667-2674).
9. **O leigo descobre a gramática sozinho?** ✅ — tooltips ensinam os 3 verbos, direito fixa, menu do
   desktop fixa, crash notifica com ponteiro para o log; ressalva: o toggle W-S-d só o rc.xml ensina.
10. **Peças avulsas ou sistema?** ✅ — GUI→pin→reload→SIGUSR2 fechado; os 3 processos sob o MESMO
    supervisor com log único; dependências todas no `packages.add`.

### 2. tune

1. **Espelhos firstboot↔interativo sincronizados?** ❌ — tokens GRUB idênticos em 5 linhas
   (:715-719 ≡ :792-796), btrfs espelhado com o comentário confessando (:901-902), sysctl em TRÊS cópias,
   e o guard curado no firstboot foi RE-introduzido doente no interativo (E33 vivo, :892-898).
2. **CPU pré-v3 no enxerto: avisa e instala mesmo assim?** ❌ — `err` não sai (:86 é só echo), o
   `ensure_cachyos` escreve `Architecture = x86_64 x86_64_v3` sem olhar ISA e o `pacman -S
   linux-cachyos-bore` instala o pacote v3 → SIGILL no boot seguinte — viola a doutrina da própria casa
   ("nunca deixa o usuário num estado sem saída", :723-726).
3. **Falha de pacman no interativo chega ao leigo como o quê?** ⚠️ — `run()` engole rc BY DESIGN
   (:110-111) e o epílogo diz "CONCLUÍDO" mesmo com lib32 recusado sem [multilib] (:883-884, :308, :917).
4. **O `--firstboot` cumpre "erro nunca calado"?** ✅ — pacman_s com rc real onde decide, RETRY_DRIVER,
   sysctl conferido no kernel com réu nomeado, Brave patch por rc 1/2/3, DRY seco de verdade.
5. **A unit firstboot pode virar refém do boot?** ✅ — ConditionPathExists dupla, After/WantedBy
   graphical.target (cura v2.10.7), TimeoutStartSec=1800, ExecStopPost registra TODOS os desfechos.
6. **Detecção de hardware cobre os edge-cases?** ⚠️ — ISA/Optimus/reconciliação MODULES bons; NVIDIA com
   GEN unknown cai no default que não existe para pré-Turing e escreve modprobe/serviços sem driver.
7. **`discover_latest` raspa HTML — robusto?** ⚠️ — sort -Vu + fallback pinado + pacman-key antes do -Sy
   são bons; o pacman -U falhado engolido segue inserindo repos que apontam para keyring velho.
8. **`craft-hello` é peça avulsa?** ✅ — 16 linhas, fallback com pipefail curado, keybind W-S-h, custo zero.
9. **O `--status` fala a língua do leigo?** ⚠️ — o único modo sem root, textos claros; mas "inactive" do
   firstboot auto-desativado lê como defeito e o `resultado:` registrado pela unit não é lido.
10. **O tuning (zram, swappiness 180, THP, max_map_count) é coerente?** ✅ — o par zram zstd+swappiness é
    doutrina CachyOS documentada no próprio conf; udev preserva HDD com bfq; THP always é escolha
    discutível MAS consciente e idempotente.

### 3. sessão

1. **Três lançadores = três peças avulsas?** ✅ — o fuzzel É o motor dos dois papéis (craft-menu é wrapper
   dmenu; cliphist reusa; nwg-drawer é a grade mouse-first); divisão documentada, não acidental; root-menu
   estático curado (só itens do dia-1).
2. **Supervisor shell artesanal + metade systemd — coerente?** ⚠️ — craft-bars com flock/restart≤5s/forense
   é bom, mas swaync, udiskie, polkit e o watcher do clipboard são ÓRFÃOS totais (morrem e ninguém relança
   nem loga).
3. **wake-guard/sleep coerentes?** ✅ — udev só nos controladores USB do réu a4h8, hibernação recusada COM
   argumento (zram sem partição persistente), hook que nomeia o próximo suspeito, CLI com root e aviso.
4. **Idle/lock/logout/power se respeitam?** ❌ — "Travar: Nunca + Suspender 20min" grava o conf, dá pkill
   e não sobe NADA (craft-idle:108-111 sai ANTES do ramo suspend; craft-bars:125-127 só olha LOCK_MIN) —
   o usuário PERDE um suspend que funcionava; o suspend do idle era `systemctl suspend` SECO (inibidor
   segura — a cura `-i` do craft-power:160 não foi espelhada); DOIS menus de sessão com conteúdos
   divergentes (craft-logout 3 itens sem Suspender vs craft-power 6 itens).
5. **Waybar + âncoras dos menus?** ⚠️ — a barra é o modelo da casa (módulos que somem quando vazios); mas
   as âncoras dos menus são offsets FIXOS contra uma barra DINÂMICA (bgapps vazio = menu de rede nasce
   35px longe do botão); o ensure() do waybar ainda usa pgrep -f sem âncora.
6. **Fronteira dock↔sessão?** ✅ — 3 fios auditáveis (sinais SIGUSR1/2 ancorados, 1 arquivo de pins, socket
   do toplevel com PING real no probe e no gate do CI).
7. **PT-BR e ponteiro?** ⚠️ — a língua de ponta a ponta; o CURSOR não: Bibata nos apps GTK, Qogirr no
   greeter, tema DEFAULT no compositor/foot (nenhum XCURSOR_THEME no environment).
8. **Quem avisa quando uma peça morre?** ⚠️ — a doutrina existe (logs com teto, toast que some, fechamento
   nunca é erro); mas o swaync — a superfície de TODOS os avisos — não tem supervisão nem log; craft-shot
   fala com o stderr que o labwc não redireciona.
9. **Custo permanente pensado?** ✅ — mpris 1 leitura interna/s, dock com socket persistente, áudio
   event-driven, swayidle por evento, o único polling é o bgapps 10s barato.
10. **Mensagens que mentem?** ❌ ×4 — rc.xml:29 vende "W-d → fuzzel (ToggleShowDesktop preservada em
    W-S-d)" e o código diz W-d → craft-drawer; autostart:76-79 invoca "a lei dos vizinhos" sobre um
    `swaync &` NU; config.top:56/66/94 ainda diz "W-P/W-S-P" maiúsculo (o bug de keysym que a v2.10.5
    curou); packages.add:223-227 anuncia nm-applet/blueman como "ícone na tray" quando a tray saiu na v2.3.6.

### 4. arquivos

1. **"Comprimir…" funciona para multi-seleção real?** ✅ no código — `%F` + `<patterns>*</patterns>` +
   `<directories/>` cobrem seleção mista; ⚠️ a prova: os "6 testes funcionais" jurados no commit E35 não
   estão na suíte (só 11 greps estáticos).
2. **O fluxo do leigo está completo?** ✅ — UM diálogo nome+formato, colisão que PERGUNTA, progresso com
   cancelamento que mata o motor e apaga o parcial, erro com a cauda do log, vitória com tamanho real.
3. **Espaços, acentos, barra?** ⚠️ — `%F`+`"$@"`+`--` no 7z + sanitização de `/` e `|` no nome estão
   certos; o TAR não tem `--` (arquivo começando com `-` é engolido como opção).
4. **Disco cheio: zero entulho?** ⚠️ — falha apaga parcial e mostra a prova; MAS tar rc=1 ("file changed
   as we read it" — arquivo BOM criado) era tratado como FALHA e apagava o arquivo: a lição do 7z rc=1
   (E35) não foi espelhada no tar.
5. **mime defaults + xarchiver sem unzip?** ✅ — defaults cobrem zip/7z/tar.gz/xz/zstd/bz2/rar; verificado
   no fonte do xarchiver 0.5.4.27: sem unzip ele cai para `7z -tzip` (7zip está na ISO desde a v1.1);
   ⚠️ faltam os single-file `.xz`/`.zst`/`.bz2` no mimeapps.
6. **Dois verbos no menu confundem?** ⚠️ — o "Criar Arquivo…" do thunar-archive-plugin continua ao lado
   (decisão documentada no uca.xml:12-14 — tradeoff consciente, faca de dois gumes para O dono).
7. **"Extrair aqui" com que backend?** ✅ — o plugin resolve pelo mime defaults do GIO → xarchiver.tap do
   pacote; o ramo do diálogo "Select an archive manager" não dispara.
8. **O rig do dono (que reclamou) recebe a cura?** ❌ — tudo do E35 nasce via skel/ISO; NÃO existe
   `scripts/live/cura-e35.sh` (padrão E26/E30/E32 quebrado — a cura do próprio relato não chega à máquina).
9. **Higiene da casa?** ⚠️ — exec bit 100755 no INDEX (E35.1 contratado), die() nunca calado; MAS o
   compress.log é append-only SEM teto (a lei do teto vale para toda a família menos a peça nova).
10. **Bordas?** ⚠️ — seleção vazia/pasta read-only/colisão cancelada tratadas; falta uma borda de produto:
    o verbo aparece também sobre .zip/.7z (compactar zip dentro de zip sem entender).

### 5. áudio

1. **Roteamento automático é o que o usuário espera?** ✅ — é o pedido literal do dono no cabeçalho;
   event-driven (pactl subscribe, zero polling), troca manual entre sinks válidos respeitada.
2. **Nada conectado / dois sinks?** ⚠️ — sem sinks retorna cedo; ranking determinístico target>ok>hdmi;
   desempate entre MESMA classe é `sorted()` estável (indeterminado, benigno).
3. **A classe proibida pega TODOS os microfones-fantasma?** ❌ — BAD_RE tinha `microfone` pt + `fifine`
   (a MARCA do rig) mas NÃO `microphone` EN: um "USB Microphone" genérico classificava `ok` e podia virar
   default — a reincidência exata da doença p6aw por outro nome; e o contrato 20-static:1025 jurava
   "cobre pt+en" (grep de palavra ≠ comportamento).
4. **Persistência da escolha?** ⚠️ — o daemon não tem memória de intenção; desplugou → rank cego, não a
   última escolha manual (fronteira confessada no cabeçalho — honesta, mas o leigo lê como bug).
5. **Fone no jack do mesmo sink?** ✅ — manage_ports só age em portas com availability yes; unplug devolve
   a porta NÃO-fone; jack sem detecção confesso como limite de hardware.
6. **Quem lança/supervisiona?** ⚠️ — o craft-bars relança (lei da família) MAS sem backoff (morte
   permanente = respawn a cada 5s eternamente) e o `wait_audio` espera a pilha SEM teto e SEM log.
7. **Parse do pactl correto?** ✅ — verificado contra o fonte do pactl upstream: `-f json list sinks`
   emite array puro; o `json.loads` + isinstance está certo.
8. **UX do leigo?** ✅ — toast em cada troca, ícone da barra segue o default, pwvucontrol GTK4 na ISO com
   windowRule; ressalva: W-a abre pulsemixer TUI (o dono rejeita TUI no dia-a-dia).
9. **Briga com o usuário?** ✅ — só na classe proibida (curada à força MESMO se escolhida — coerente com o
   trauma fifine, confessado).
10. **Evidência e contratos?** ⚠️ — log com teto 256 KiB + TROCA/PORTA/FALHA logados com motivo; MAS
    nenhum contrato EXECUTAVA a classificação (o bug do Q3 passava limpo).

### 6. rede-kernel

1. **BBR+fq hardcode para TODO hardware?** ✅ — decisão da stack TCP, ordem de boot correta e documentada,
   guard que limpa o sysctl quando o kernel não tem bbr.
2. **sysctl de gaming no live sem zram garantido?** ⚠️ — o par swappiness/zram é sadio; o elo implícito é
   o binário zram-generator chegar como dependência do cachyos-settings (ninguém valida o zram ativo).
3. **A central é clara para o leigo?** ⚠️ — Wi-Fi/cabo/BT/salvas sim; HOTSPOT não existe (só no
   nm-connection-editor); a senha Wi-Fi aparecia enquanto se digitava (o README:70 jurava "senha oculta").
4. **Estados de erro honestos?** ⚠️ — o wifi_connect v2.10.5 captura e classifica stderr; known_manage e
   known_password ainda chutam a causa ("cabo fora? Wi-Fi desligado?") com stderr destruído.
5. **Retry honesto?** ✅ — cache-first com varredura de fundo, "Atualizar…" prova por LAST_SCAN (relógio do
   dispositivo), senha recusada apaga perfil e re-prompta UMA vez.
6. **Fallback de emergência fala com o serviço?** ⚠️ — `impala` é TUI de iwd; o NM que governa a distro
   não é o que ela controla (porta de emergência cenográfica; nmtui seria honesto).
7. **Regras udev de I/O?** ✅ — dois falsos-positivos mortos documentados, TEST!=partition, NVMe none,
   SSD none (tradeoff mq-deadline defensável), HDD bfq.
8. **zram min(ram,8192)+zstd?** ✅ — sóbrio e pareado com o swappiness; sem swap.priority explícita (fino).
9. **Preset BORE: dois mundos?** ✅ — uma estratégia com duas formas (live archiso → instalado
   default/fallback), kernel único = menos superfície.
10. **"Bluetooth: dispositivos…" sem adaptador mente?** ⚠️ — a linha é adicionada INCONDICIONALMENTE
    (craft-connect:137-138); desktop sem BT abre janela vazia — incoerente com o próprio padrão da casa
    ("adaptador ausente ≠ serviço morto").

### 7. saúde

1. **sweep/clean/rollback se sobrepõem?** ✅ — funções distintas com guardas; sobreposição real é outra:
   5 camadas de keyring intencionais que exigem sincronia.
2. **craft-update vs pacman -Syu — visível para o leigo?** ✅/⚠️ — a porta de entrada EXISTE desde a v1.7
   (menu.xml:78-79 "Atualizar sistema" → foot -e craft-update, contrato 40-int:881); a diferença real
   (aviso de kernel + drift) é magra mas há; o hook paru é decoração confessada.
3. **keyring-fix timer ainda necessário?** ✅ — é o único curandeiro no instalado (sessão sai de propósito
   fora do live); guard de 24h que só escreve o selo com a cura FEITA; ressalva: é um `-Sy` diário
   automatizado (convite teórico a partial upgrade).
4. **craft-dump é legível pelo dono?** ⚠️ — por desenho o dono é o CARTEIRO da perícia (565 linhas de
   mantenedor) e nenhuma linha diz "você não precisa ler isto, só enviar".
5. **Mensagens que mentem?** ⚠️ ×3 — rollback :108/:155 destrói o stderr do pkexec/snapper e adivinha
   ("senha ou snapper sem config"); fix-keys :81 idem ("sem rede?") — um keyring doente demais para
   VERIFICAR também falha; craft-dump --upload manda o papel inteiro para o termbin PÚBLICO sem uma
   palavra de aviso.
6. **craft-clean seguro?** ✅ — default seguro N, lista antes, EOF tratado, vacuum coerente com o teto.
7. **teto 420s do keyring-wait?** ✅ — número corrigido por evidência (84×5s > transação provada de 4min46s),
   sempre exit 0, o guard nunca mascara falha.
8. **elite-status duplicação?** ✅ — alias puro de 3 linhas (`exec elite-tune --status`); lógica num lugar só.
9. **craft-hello serviço real?** ✅ — ornamento honesto e barato; welcome removido sem resíduo.
10. **journald 100M aguenta "dias ligado"?** ✅ — decisão raciocinada no próprio arquivo (persistent +
    RuntimeMaxUse), dump taila o essencial.

### 8. instalação

1. **install-stage duplica config?** ⚠️ — divisão por fase limpa; mas GPU vive em dois atores com dois
   detectores (stage: drm card vendor; tune: lspci) — interplay CONTRATADO por escrito (:222-228).
2. **Config do Calamares validado em CI?** ✅ — sobre o rootfs REAL extraído do squashfs, parseia todos os
   .conf como YAML e resolve instâncias @id; ⚠️ não é schema do Calamares nem execução do binário.
3. **O leigo entende o pós-clicar-Instalar?** ⚠️ — wrapper sem terminal + slideshow PT; MAS o .desktop e
   o job de progresso em EN/jargão ("BORE initramfs") numa distro PT-BR.
4. **shellprocess é 1 comando?** ✅ — `elite-install-stage ${ROOT}` + gates triplos (grep no conf real,
   allowlist de variáveis, file_permissions).
5. **Cascata de kernel copytoram?** ✅ — 4 candidatos, prova byte-a-byte, retry ×2, falha alta SÓ quando o
   alvo não tem kernel são (a lição do termbin iy38).
6. **os-prober × kernel único?** ❌ — o knob D2 descomenta os-prober e ~15 linhas depois o gate reprova
   QUALQUER vmlinuz não-BORE no grub.cfg (incluindo os do 30_os-prober): 2º Linux no disco = Installation
   Failed exatamente no público que o D2 queria servir; e o pacote os-prober NÃO estava na ISO.
7. **O instalador some da gaveta?** ✅ — 3 camadas com a corrida real documentada (E30: dono clicou 9s após
   o login; janela ~2min30s) — sweep pré-display-manager + tune remove o pacote + registro com timestamp.
8. **Log do instalador sobrevive?** ✅ — 3 destinos; a v2.10.6 confessou o código morto /mnt/elite em
   comentário (modelo de honestidade).
9. **Gate cobre o fluxo COMPLETO?** ⚠️ — sem fstab/users/locale por escolha documentada; os módulos onde
   um leigo quebra nunca são exercidos no CI.
10. **Idempotente e à prova de drift?** ⚠️ — seds com guard grep; mas vmlinuz-linux-cachyos-bore hardcoded
    em ≥4 arquivos sem constante compartilhada.

### 9. build-pacotes

1. **apply-overlay idempotente/estruturado?** ⚠️ — idempotência estrutural (rm+clone, seds com guard);
   numeração envelhecida ([6.3] antes do [6.2], DOIS [9]) — monolito de 514 linhas legível com esforço.
2. **Pacote morto?** ✅ — cadeia viva quase total (wlrctl fallback real, gamemode re-afirmado…); único
   candidato: tealdeer (sem integração nenhuma).
3. **Pins no lugar?** ⚠️ — Brave com guardião próprio e cache-key; craft-toplevel com sha CALCULADO pela
   suíte; MAS o check-brave.sh não é chamado por NENHUMA automação (guardião órfão).
4. **Build reprodutível?** ⚠️ — cache bem desenhado (dbs nunca cacheados, ELITE_VERSION tag→describe→dev);
   MAS a BASE upstream é `git clone --depth=1` flutuante sem pin de commit.
5. **vendor/wlrctl por quê?** ✅ — dependência órfã de upstream morto, snapshot vendado com sha = pin =
   assert da suíte (verificado byte a byte).
6. **Contrato duplo fragments↔overlay?** ⚠️ — três pares de verdade paralela (pacman.conf ×2 com políticas
   diferentes; elite_latest ×2; qemu-boot-test duplica o gate inline do build.yml — e já divergiu 1×).
7. **Preflight é engenharia?** ✅ — closure idêntica ao pacstrap (--dbpath vazio), sondas paralelas, gêmeo
   bidirecional, repack pkgrel com vercmp, selo offline com assert de db ausente. O trecho mais sênior.
8. **qemu-boot-test cobre o mínimo?** ⚠️ — cmdline EXTRAÍDA da ISO, probe da sessão viva; MAS nenhum gate
   boota UEFI (OVMF) — as entradas efiboot sed-eias nunca são testadas.
9. **Falhas de fonte externa honestas?** ✅ — 2 tentativas com log integral SÓ na falha final, fallback com
   aviso, makepkg do Brave falha alto, "falha determinística não se cura com retry".
10. **Higiene do build?** ⚠️ — o rsync do [3] copiaria `__pycache__` para a ISO (o E35 curou o SINTOMA no
    file_permissions, não a FONTE); resto consciente (E8/E11/E32.3).

### 10. porteira-gestão

1. **A suíte é rápida o suficiente?** ✅ — medição do auditor: 18,3s nas 543 peças das fases 1-2; o repo
   declara ~1,4 min completo — a L2 é cumprível de verdade.
2. **Contratos duplicados entre fases?** ⚠️ — duplicatas puras (needs ×2, pkgname brave ×4, craft-pin ×3,
   dump ×3 na MESMA fase) sem marcação do que é defesa fonte→transporte por desenho.
3. **A suíte testa os docs?** ❌ — NENHUM contrato lê o README; o README JÁ apodreceu (vendia timeshift
   que o packages.remove derruba e "as 2 barras" que morreram na v2.0); e o tests.yml nem roda quando
   `docs/**` muda — a proteção tem ponto cego sobre os arquivos que protege.
4. **Workflows com drift?** ⚠️ — lint assimétrico (a peça jura "mesma lista do build.yml" e já não é);
   publish-artifact.yml NÃO tem a Lei da Release Única Viva; blocos gêmeos copiados ("Mesma lógica do
   build.yml" com data marcada).
5. **agents.ts coerente com docs/AGENTS.md?** ⚠️ — modelos e relay batem; MAS as 4 crons vivem SÓ na
   plataforma (sem versionamento, sem gate) e o dia 1 provou o custo (2/2 falhas de plataforma sem rastro).
6. **Diários têm máquina de estados?** ✅ — a lei do `próximo` está escrita; riscos de append-only já
   visíveis (adendo sem próximo; sem ponteiro "estado atual" no topo).
7. **SCRIPTS.md sincronizado?** ❌ — contados: ~15 seções para 41 scripts vivos (~30%); o README promete
   "cada script" e a promessa era falsa.
8. **Leis escritas com dentes?** ✅ — L1/L2/L4/L5/L9/L10 em PROTOCOL.md com a CI aplicando a L5 no release
   job e a suíte cobrando o próprio PROTOCOL por grep.
9. **Contratos que testam o testador?** ✅ — veredito testado como código (summary falso = NO-GO), validador
   de Calamares provado nos DOIS lados, suíte roda shellcheck sobre si mesma, harness extrai função REAL.
10. **PT-BR consistente?** ✅ — 100% com política explícita; typos de uniforme ("contratá" no PROTOCOL).

---

## Curas aplicadas nesta rodada (E36)

Critério: impacto alto × esforço baixo × risco baixo, tudo provado pela porteira antes do push.

1. **sessão/energia**: craft-idle entrega o SUSPEND com Lock=Nunca (o knob que o menu vende e o daemon
   matava); `systemctl suspend -i` no idle (a cura do craft-power chega ao idle); craft-bars acorda o idle
   por LOCK **ou** SUSPEND; `status` diz a verdade.
2. **sessão/órfãos**: swaync (a superfície de TODOS os avisos), udiskie e o agente polkit entram no
   craft-bars com ensure() idempotente + stderr no bars.log; comentário E33 do autostart corrigido;
   spawn do swaync agora despeja stderr no log.
3. **sessão/E33**: rc.xml:29, config.top W-P×3, packages.add nm-applet/blueman — as 4 mentiras morrem.
4. **sessão/cursor**: `XCURSOR_THEME=Bibata` + `XCURSOR_SIZE=24` no labwc environment + `cursor.theme/size`
   no themerc-override — o ponteiro para de mudar de sotaque (Bibata já é o tema dos GTK e da ISO).
5. **arquivos**: tar com `--` + rc_ok=1 (a lição 7z rc=1 espelhada — tar rc=1 warning NÃO apaga mais
   arquivo bom); teto de 256 KiB no compress.log (a lei da família chega à peça nova).
6. **áudio**: `microphone` (EN) entra no BAD_RE + contrato que EXECUTA a classificação sobre provas
   ("Fifine Microphone", "USB Microphone", "Monitor of", saída analógica que NÃO deve casar).
7. **dock**: `_windows_of` ganha `strict` — o FECHO (meio-click) NUNCA mais casa por título; DEFAULT_CSS
   sincronizado com o skel (a bolinha do dono no fallback; a barrinha rejeitada morta nos DOIS lugares);
   craft-pin duplicado sai rc 1 + picker com toast honesto ("já estava na dock") + contrato 30-unit passa
   a PROVAR o rc.
8. **tune**: gate ISA no enxerto — CPU pré-v3 NÃO instala kernel/repos v3 (o resto do tune segue); o
   "avisa e mesmo assim instala" que gerava SIGILL morre.
9. **instalação**: o gate kernel-único EXCLUI o bloco 30_os-prober do grub.cfg (a promessa D2 e o gate
   param de brigar) + `os-prober` entra no packages.add (o knob deixa de ser código morto) +
   calamares.desktop com `[pt_BR]`.
10. **saúde**: craft-dump --upload AVISA que o paste é público (SSIDs/IPs/MACs) + linha "você não precisa
    ler isto — só enviar" no veredito.
11. **rede**: senha Wi-Fi via `zenity --password` (mascarada — o README:70 volta a ser verdade; fallback
    fuzzel preservado) + linha de Bluetooth condicionada à existência de adaptador.
12. **build**: rsync do [3] exclui `__pycache__`/`*.pyc` (a fonte, não o sintoma) + tests.yml passa a
    rodar quando `docs/**` muda (fim do ponto cego da porteira).
13. **gestão**: README deixa de vender timeshift e "2 barras"; SCRIPTS.md ganha índice COMPLETO dos
    32 bins + scripts de repo (a promessa "cada script" vira verdade); typo da lei L10 corrigido.
14. **este documento** (`ARQUITETURA.md`) + entrada no diário AUDITORIA.md.

## Correções à própria auditoria (a auditoria também passa pela porteira)

1. **"craft-update sem porta de entrada" (saúde Q2) — FALSO.** O menu raiz tem "Atualizar sistema" →
   `craft-update` desde a v1.7 (menu.xml:78-79, contrato 40-int:881-882). O auditor varreu os bins e
   não varreu o menu.xml. Corrigido aqui para a história não gravar o erro.
2. **"ISA v1/v2" (tune) — o valor v2 não existe**: a detecção produz v1/v3/v4 (ld-linux --help); o gate
   correto é v1. Documentado para o polimento futuro não caçar um fantasma.

## Plano de reestruturação (o que fica — ranqueado)

1. ✅ **FEITO — E37**: os 4 pares gêmeos são hoje FUNÇÃO ÚNICA chamada pelos dois modos
   (`apply_grub_tokens`, `write_elite_sysctl`, `ensure_bbr` iso|graft, `ensure_btrfs_stack`); o espelho
   é cravado na suíte como contagem (def 1× / chamada 2× / zero cópia viva) e o epílogo do interativo
   ficou honesto (nº 16 no mesmo commit).
2. **Guards da suíte index-driven**: shebang e file_permissions lendo `git ls-files -s` (o guard de exec
   já faz) — fim do NO-GO local que o sandbox finge e o CI desmente.
3. **Contratos de docs**: todo `craft-*/elite-*` citado no README existe em `usr/local/bin`; rollback
   citado bate com packages.remove; SCRIPTS.md cobre os bins vivos (contrato de contagem).
4. **Curas de campo**: a `cura-e35.sh` prometida aqui NUNCA chegou a existir (E42 — o papel dizia
   'o rig do dono recebe o craft-compress' e o rig ficou sem cura; descoberta no mesmo dia em que o
   dono provou o verbo morto). As curas vivas seguem o padrão `cura-viva.sh` (E25); a cura E42 viaja
   na próxima ISO e o rig já instalado tem o alívio imediato do link `7z → 7zz` na resposta ao dono.
5. **Pino da base upstream**: `elite/upstream-pin` com o HEAD do archcraft-os consumido pelo clone —
   a ISO da tag vira função do repo (reprodutibilidade real).
6. **check-brave com gatilho**: workflow `schedule:` mensal (ou passo do agente) rodando o guardião.
7. **Deduplicar as verdades paralelas**: `elite_latest`/`elite_fetch` num `scripts/lib/` sourced pelos
   dois lados; publish-artifact herdando a Lei da Release Única Viva (composite action).
8. **Boot UEFI no gate**: `--uefi` (OVMF) no qemu-boot-test — o único caminho que nenhum teste vê.
9. **Reunificar os menus de sessão**: craft-logout vira wrapper do craft-power (Suspender para quem usa
   teclado; −80 linhas de duplicação).
10. **Áudio com memória de intenção** (fallback ao último default escolhido manualmente) + backoff no
    respawn do craft-bars + teto/aviso no wait_audio.
11. **W-a → pwvucontrol** (o TUI pulsemixer sai do dia-a-dia; o dono já rejeitou TUI).
12. **Hotspot no craft-connect** (`nmcli device wifi hotspot`) — o único verbo de conectividade comum só
    no caminho power-user.
13. **Terminal=true honrado na dock** (`foot -e` quando o .desktop pede) + cache negativo de comms +
    invalidar `_dindex` no SIGUSR2.
14. **Constante única do kernel** (`elite/KERNEL`) consumida por stage/overlay/fragmento — fim dos 4
    hardcodes coordenados à mão.
15. **Versionar as crons** (docs/gestao/CRONS.md + contrato E34) — a metade executante da gestão deixa
    de ser invisível ao repo.
16. ✅ **FEITO — E37**: pacman_s com rc real alimenta FAILURES; falha vira 'PENDÊNCIA: …' na hora e
    'CONCLUÍDO COM N PENDÊNCIA(S)' no epílogo — o 'CONCLUÍDO' incondicional morreu.
