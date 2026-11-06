# CAIXA DE FERRAMENTAS ESSENCIAIS — brainstorm v1 (E68)

> Pedido do dono (06/nov): brainstorm técnico e de UX sobre ferramentas, utilitários
> e lógicas que deveriam vir por padrão ou ser facilmente acessíveis — máxima
> praticidade, sem poluir a instalação (conceito limpo e minimalista).
>
> **PAPEL APENAS** — nada disto entra no pacote sem ordem do dono. Nenhuma peça
> deste documento mudou o elite-system (lei E41 não acionada aqui). O que já
> existe foi VERIFICADO no código de hoje (1.0-17); o que é proposta está marcado.

---

## 0. A regra do jogo (a lei de admissão da caixa)

"Limpo e minimalista" não é "vazio" — é **nada parado sem trabalho**. Toda peça
candidata passa por três portas antes de entrar:

1. **Custo medido** — quanto pesa na ISO e no boot (MB, daemon, dependência)?
2. **Detecção antes de instalação** — o sistema pergunta ao hardware ANTES de
   instalar painel específico (a regra do dono para GPU/fãs já é lei aqui).
3. **Zero daemon sem função** — se não roda em todo boot com trabalho real,
   é lazy (nasce no 1º uso) ou opt-in (um toggle no elite-tune).

E a porta de saída: o que é pesado, duplica o que a casa já tem, ou exige
daemon de vigilância permanente, **fica fora** (seção 4).

---

## 1. Gestão e facilidade na instalação de software (sem lojas pesadas)

### 1.1 AUR — `paru` ou `yay`?

| | paru | yay |
|---|---|---|
| Linguagem/deps | Rust | Go (estático) |
| Binário oficial pronto | Sim (pkg.tar.zst no GitHub Releases) | Sim (binário estático) |
| Revisão de PKGBUILD | Interativa, mostra diffs | Interativa |
| Peso instalado | ~4-6 MB | ~8-10 MB |

**Recomendação: `paru`, por binário oficial do GitHub com sha256 fixado no CI**
(o mesmo padrão de selo que a casa já aplica às próprias peças — a cadeia de
suprimento não vira mão negra: o hash entra no build.sh e a suíte cobra).

**Como entra (decisão de dono, duas portas legítimas):**
- **Porta A — pré-instalado**: paru no pacote de base; AUR disponível no 1º minuto.
- **Porta B — toggle no elite-tune** ("Habilitar AUR — paru"): baixa e instala na
  hora, com selo; a ISO nasce mais magra e quem não usa AUR nunca vê.

A regra de segurança é inegociável nos dois caminhos: **AUR helper nunca roda
como root** (paru/yay recusam por desenho) e a casa NÃO vira porteira — PKGBUILD
é revisado pelo usuário na tela do próprio paru. Risco honesto registrado: AUR é
comunidade; o selo do hash protege o TRANSPORTE, não o CONTEÚDO de terceiros.

### 1.2 AppImage — integração sem AppImageLauncher

AppImageLauncher FORA: é daemon + watcher de desktop que vigia o disco inteiro,
histórico de manutenção oscilante, e adiciona uma camada que a casa não controla.

**Proposta: `craft-appimage <arquivo.AppImage>` (~60 linhas, ZERO pacotes):**
1. Move para `~/Applications/` e dá +x;
2. Extrai o `.desktop` + ícones via `--appimage-extract` e instala em
   `~/.local/share/{applications,icons}` — **fuzzel, Thunar e a dock enxergam de
   graça** (todos leem .desktop; nenhum registro extra é necessário);
3. `--remove` desfaz; recusa = toast (lei v2.9.0 da casa);
4. Ação nova no `uca.xml` do Thunar: botão direito → "Integrar AppImage".

Custo: 1 script da família craft-* + 1 linha no uca.xml. Sem daemon, sem peso,
idioma da casa (toasts + logs). **A recomendação mais forte deste documento.**

### 1.3 Solução visual leve para pacotes

| Candidato | Veredito | Por quê |
|---|---|---|
| **pacseek** (TUI, Go) | **ENTRA — padrão Elite** | ~3 MB, zero framework gráfico, busca repo+AUR (via paru), instala/remove, roda no foot. É a "loja" sem loja. |
| Octopi (Qt6) | opt-in documentado | Bom notifier + GUI, mas arrasta Qt6 (~50 MB instalado) para um desktop que não usa Qt. Só se o dono pedir. |
| Bauh | FORA | Python+Qt+deps = o peso de uma loja com o workflow de outra. |
| Pamac | FORA | libpamac é pesada e pouco mantida fora do Manjaro. |
| GNOME Software / Discover | FORA | Lojas de DE completas — o oposto do conceito. |

**A tríade "gerenciar sem loja": sinal na waybar (degrau B1 do UX-ROADMAP,
`pacman -Qu` zero-dependência) + `pacseek` para ver/pesquisar + `paru` para o
dia a dia no terminal.** O custo somado é menor que UM dos concorrentes GUI.

### 1.4 Flatpak/Flathub — suporte transparente, LAZY

O erro clássico é preinstalar flatpak + runtime + store no ISO (500 MB+ de
nada). O desenho Elite:

1. **O binário `flatpak` (~12 MB) é a única peça candidata a pré-instalação**;
   nada de runtime é baixado antes do 1º uso (runtime vem com o 1º app).
2. **`craft-flatpak` (wrapper da família)**: `search|install|remove|update|list`
   com toasts e logs da casa; o remoto Flathub é adicionado **na 1ª execução**
   (a ISO nunca toca a rede sozinha por isto);
3. Integração de menu é NATIVA do flatpak (instala .desktop em
   `~/.local/share/flatpak` — fuzzel/dock pegam sem config);
4. Update automático: timer systemd **opt-in** (mesmo padrão da cadência elite);
5. Flatseal (permissões): opt-in, não padrão.

---

## 2. Controle de hardware & telemetria inteligente

### 2.1 Detecção dinâmica — `craft-hardware` (NOVO, o pedido explícito do dono)

**Nada de pré-instalar `lact` "por precaução".** O script lê o hardware e SÓ
ENTÃO oferece o painel certo:

```
lspci -nn (vendor ID)                → o que o script oferece
  0x1002 AMD (GPU)                   → lact (binário oficial GitHub, sha256 fixado;
                                       fan/overclock/curvas — roda daemon próprio SOB DEMANDA)
  0x10de NVIDIA                      → JÁ COBERTO pela casa (elite-install-stage:
                                       modeset+fbdev+PreserveVideoMemoryAllocations
                                       + serviços nvidia-suspend/resume — E63;
                                       elite-tune L569 habilita em rig existente)
  0x8086 Intel (GPU)                 → intel-gpu-tools (opt-in, leve)
CPU/placas (hwmon + sensors)         → lm_sensors (pré — quase zero) + leitura
                                       de fãs no elite-status
```

O painel é **sugestão com instalação guiada** (menu dmenu/fuzzel com custo na
tela), nunca instalação silenciosa. Telemetria = leitura LOCAL para decisão —
**nada sai da máquina** (não existe telemetria remota na Elite e não vai existir).

### 2.2 Ventoinhas e energia

- **power-profiles-daemon** (repo oficial, leve, padrão de facto Wayland):
  perfis performance/balanced/powersave com `powerprofilesctl`; módulo na
  waybar (clique troca perfil — mesmo padrão dos módulos clicáveis que a casa
  já tem). É o "controle térmico" honesto para 90% dos rigs;
- **CoreCtrl**: opt-in via craft-hardware (pesa mais; para quem precisa de
  curva de fã por sensor, vale — mas é decisão por detecção, não padrão);
- **craft-bat** (existente) continua a porta do dono para bateria/alertas.

---

## 3. Utilitários essenciais de UI/UX (o "feijão com arroz" — estado REAL)

| Ferramenta | Estado verificado (1.0-17) | Ação |
|---|---|---|
| Clipboard (cliphist) | **JÁ EXISTE** — W-v abre histórico no fuzzel (rc.xml L250) | Nada a fazer ✔ |
| Captura (grim+slurp) | **JÁ EXISTE** — craft-shot (região/tela + wl-copy) | Nada a fazer ✔ |
| **Gravação de tela** | **NÃO EXISTE** | **`craft-record` NOVO: wf-recorder (~200 KB, Wayland nativo) + slurp de região, salva em ~/Vídeos, toast; áudio opcional via pw-record** |
| Rede | **JÁ EXISTE** — craft-connect v6 (central do NetworkManager) | Nada a fazer ✔ |
| Áudio na barra | **JÁ EXISTE** — módulo pulseaudio clicável + craft-audio-route | Manter ✔ |
| Bateria | **JÁ EXISTE** — módulo battery + craft-bat | Manter ✔ |
| **Bluetooth na barra** | **NÃO EXISTE módulo** (a base tem bluez; a waybar não tem o módulo) | **Módulo bluetooth na waybar + pareamento via bluetoothctl no menu (sem blueman/GTK pesado); a verificar na bancada o que a base já traz** |
| **Montagem de discos/pendrives** | Thunar monta ao abrir; **sem automount de sessão** | **udisks2 + udiskie (Python leve, notifica e monta ao conectar, ícone na bandeja; autostart com guard — mesmo padrão da casa)** |

---

## 4. O que NÃO entra (e o porquê — a lista é parte do brainstorm)

| Peça | Por quê fica fora |
|---|---|
| GNOME Software / Discover | Loja de DE: centenas de MB + plugins + backend; o conceito oposto |
| Bauh / Pamac | Peso de loja com GUI de loja; pacseek + paru cobrem por 10% do custo |
| AppImageLauncher | Daemon que vigia o disco inteiro; craft-appimage resolve com 60 linhas |
| Flatseal por padrão | Ferramenta de auditoria fina — opt-in para quem mexe em permissões |
| GPaste / coprar | cliphist já cobre (verificado) |
| Qualquer telemetria remota | Não existe e não vai existir — leitura local só |
| Deamons de monitoramento permanentes (lact daemon auto-start, corectrl no boot) | Painéis sob demanda; daemon sobe só quando o dono abre o painel |

---

## 5. Ordem de ataque proposta (amarrada ao UX-ROADMAP — 1 degrau/dia, suíte GO antes)

| # | Degrau | Tipo | Custo ISO | Impacto no dono |
|---|---|---|---|---|
| E1 | craft-appimage + uca.xml | 0 pacote | ~0 MB | Alto — AppImage deixa de ser "arquivo solto" |
| E2 | craft-hardware (detecção + lact/guiada) | 0 pré-instalação | ~0 MB (baixa na hora) | Alto — GPU certa sem chute |
| E3 | paru (porta A ou B) + pacseek | 1 binário + 1 TUI | ~8 MB | Alto — instalar qualquer coisa fica fácil |
| E4 | craft-record (wf-recorder) | 1 pacote | ~0,2 MB | Médio — gravação nativa Wayland |
| E5 | udiskie automount | 1 pacote | ~1 MB | Médio — pendrive que "só funciona" |
| E6 | flatpak lazy + craft-flatpak | opt-in | ~12 MB | Médio — universo de apps sem loja |
| E7 | módulo bluetooth na waybar | 0 pacote novo (a confirmar) | ~0 MB | Médio — fone que conecta da barra |

**Custo total do caminho completo: ~21 MB na ISO (e ~8 MB deles só se o dono
escolher a porta A do paru).** Cada degrau: contrato na suíte, E41 quando
elite-system mudar, diário no POLIMENTO. A fila do UX-ROADMAP (A1 craft-help
na frente) continua a menos que o dono reordene — este documento é a fila
"ESSENCIAIS", pronta para ser intercalada.

---

## 6. Métrica de sucesso (como o dono julga)

- Pendrive conectado aparece montado com notificação (E5);
- AppImage baixado aparece no fuzzel em < 30s sem terminal (E1);
- `craft-hardware` num rig AMD oferece lact; num Intel oferece intel-gpu-tools;
  num NVIDIA, aponta a cura que JÁ está aplicada (E2);
- Gravar 30s de tela com 2 cliques (E4);
- Instalar um pacote AUR sem abrir wiki (E3);
- A ISO continua no mesmo tamanho ± o custo declarado acima (a balança do CI
  é a prova — o build já imprime o tamanho dos artefatos).
