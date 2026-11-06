# FUTURO — o brainstorm da evolução (E53)

> O dono pediu: "um brainstorm de ideias de como as distros funcionam, como
> a gente pode se diferenciar e como tudo pode ser simples para uma evolução
> de outro nível, de forma que muita coisa seja automatizada ou praticamente
> tudo — e minha manutenção manual já não seja mais necessária".
> Este documento é o brainstorm. Nada aqui está implementado por decreto:
> cada ideia diz o que JÁ EXISTE, o que FALTA e o custo honesto.

## 1. Como as distros funcionam hoje — o mapa honesto

| Escola | Mecanismo | Força | Ferida |
|---|---|---|---|
| **Arch rolling** (nossa base) | pacman + repos; o usuário monta | frescor total, controle | o "sistema do usuário" é uma SOMA de decisões manuais — reinstalar = refazer tudo |
| **NixOS** | sistema declarativo + gerações | rollback de TUDO, reprodutibilidade | linguagem própria, curva íngreme, o desktop "de fábrica" não existe |
| **Fedora Silverblue / openSUSE MicroOS** | root IMUTÁVEL + atualização por imagem A/B | o update é atômico e o rollback é um reboot | apps fora do flatpak sofrem; personalizar o root é luta contra o desenho |
| **VanillaOS / blendOS** | A/B + containers | isolamento | complexidade escondida que vaza |
| **CachyOS** (a Elite herda o kernel/tuning) | performance + BORE | velocidade real | distro "helpers" — a manutenção segue manual |

**A leitura da casa**: nenhuma escola entrega as CINCO coisas juntas que o
dono exige — *atualização que chega sozinha e não quebra*, *rollback real*,
*config de usuário intocável*, *sessão que fica viva após o update*,
*um só número para olhar*. A Elite já tem as cinco (E43→E51.1). O
diferencial não é inventar uma escola nova — é **fechar o circuito que as
outras deixam aberto**.

## 2. O que a Elite JÁ é (o presente que o dono pode cobrar)

1. **O pacote único** (`elite-system`, E50): o sistema da casa é UM
   quebra-cabeça atômico — uma transação troca TUDO, com replaces de era
   (duas trocas de era já provadas sem formatar: E43 e E50).
2. **A cadência que se alimenta sozinha** (E51): casa ao LIGAR (boot é o
   relógio do dono), sistema completo semanal com snapshot PRE/POST do
   snapper, ISO mensal, porta manual sempre.
3. **A cura chega VIVA** (E48/E49): update sem relogin — dock, áudio, idle
   e daemon de janelas renascem na sessão com o código novo.
4. **A rede de segurança** (E46): snapshot antes/depois; quebrou? o GRUB
   liga o snapshot e o rollback é um reboot.
5. **A porteira total** (E45→): 2436 peças em cadeia + guard E41 + canal
   diário — o CI nunca é o primeiro a ver um defeito.

## 3. O roadmap do "quase tudo automatizado" (o próximo nível)

### 3.1 `elite-doctor` — o sistema que examina a si mesmo *(custo: baixo)*
Um verbo novo no elite-system, rodando no boot (após a dose): saúde da
cadência (os timers vivos?), espaço em disco, contagem de snapshots, logs
de erro da última semana, delta entre `pacman -Q elite-system` e a release
viva. Sai um relatório honesto na sessão: **"o sistema está são"** ou
**"estes 2 pontos pedem atenção"**. O dono para de caçar sintomas — o
sistema se denuncia.

### 3.2 Auto-cura pós-update *(custo: médio)*
Hoje a dose semanal tem snapshot PRE/POST (rede de segurança manual — o
dono escolhe no GRUB). O próximo degrau: no boot seguinte à dose, um
checklist mínimo (sessão sobe? áudio, rede, dock vivos?) — falhou? o
sistema APITA com a evidência e oferece o rollback automático (um
`craft-rollback` com o número do snapshot, sem terminal). "Quebrou e
voltei" vira "quebrou e o sistema se curou".

### 3.3 Manifesto do quebra-cabeça *(custo: médio)*
O `packages.add/remove` JÁ é o manifesto da ISO — falta a ponte para o rig
INSTALADO: um arquivo `~/.config/elite/manifest.conf` (o que o dono
ADICIONOU da curadoria) + um verbo `elite-manifest aplicar` que reconstrói
a seleção numa máquina nova. **Reinstalar/formatar morre de vez**: a
máquina nova = ISO + `elite-manifest aplicar` + `elite-system` do dia =
o rig idêntico, sem backup manual de nada.

### 3.4 O rice como fragmento de fábrica *(custo: baixo)*
O dono já mantém o tema "do sistema em si" (catppuccin + acento). Formalizar:
os fragments ganham nomes (`fragment/acento-mauve`, `fragment/dock-mac`),
o skel os compõe, e o `elite-tune` sabe regenerar qualquer um sem tocar no
que o dono personalizou. O quebra-cabeça vira peças com nome.

### 3.5 Telemetria local honesta *(custo: baixo, opt-in)*
O `craft-dump`/`elite-status` já existem para perícia sob demanda. Virar
rotina: no doctor, um resumo (versão, uptime, erros) — nada sai da máquina
sem o dono pedir. O papel do log substitui a memória do dono.

### 3.6 A ISO que nasce perfeita *(custo: zero — já é assim)*
A ISO mensal nasce do MESMO tree que o canal entrega: a ISO do dia 1º é o
estado provado do dia 30. Nada de "ISO nova com bugs que o canal já curou"
— o que a ISO entrega, o canal já provou por 30 dias.

## 4. A promessa definitiva (o contrato com o dono)

> **A partir da era E50, a Elite só avança.** O dono não reinstala, não
> formata, não caça bug com terminal: liga o PC (a casa atualiza), usa,
> e o sistema se examina e se cura. O que o dono mantém na mão é o que ele
> QUER manter (o rice, a curadoria) — o resto é papel da casa e da esteira.

## 5. O que NÃO fazer (as armadilhas das outras escolas)

- **Imutabilidade radical**: a Elite é o quebra-cabeça personalizável —
  congelar o root é lutar contra a identidade da casa.
- **Linguagem própria** (estilo Nix): o valor da Elite é ser Arch por
  baixo — bash, pacman, systemd. Zero linguagem nova para manter.
- **Declaratividade total cedo demais**: o manifesto (3.3) cobre 80% do
  valor com 5% do custo. O resto é YAML de governança disfarçado.
- **Automatizar o que não dói**: cada automatismo novo entra COM a sua
  suíte e o seu papel — automatismo sem porteira é ferida futura (a lição
  E41: a lei não escrita é a lei quebrada).
