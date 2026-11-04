# ESTRUTURA — o mapa do repositório (E52)

> O dono: "um repositório refeito pois esse tá muito bagunçado". O repo não
> estava bagunçado por falta de organização — estava bagunçado por FALTA DE
> MAPA. Este arquivo é o mapa. Nada aqui é decoração: cada diretório tem um
> dono, um papel e uma lei.

## A regra de ouro

**`elite/` é o sistema. Todo o resto existe para servir `elite/`.**

## O mapa

```
archcraft-elite/
├── elite/                      ← O SISTEMA (a única fonte da verdade)
│   ├── airootfs/                   o corpo: tudo que a ISO entrega e o
│   │   ├── usr/local/bin/            elite-system empacota (craft-*, elite-*)
│   │   ├── etc/systemd/system/       as units da casa (cadência E51)
│   │   └── etc/skel/                 o rice nasce aqui (configs de usuário)
│   ├── fragments/                  peças de config que o build compõe
│   ├── packages.add                o MANIFESTO da ISO (o que nasce instalado)
│   ├── packages.remove             o VETO (o que nunca mais volta)
│   └── pacman-repos.build.add      os repos do build
├── .ci/                        ← A ESTEIRA
│   ├── build.sh                    FONTE ÚNICA dos PKGBUILDs (elite-system
│   │                               nasce aqui; nada de template solto)
│   ├── guard-pkgrel.sh             a lei E41 executável (conteúdo mudou
│   │                               ⇒ pkgrel subiu, ou o push é vermelho)
│   └── validate-calamares.py       porteira do instalador
├── .github/workflows/          ← OS PORTÕES
│   ├── tests.yml                   a suíte (nada entra sem ela)
│   ├── build.yml                   a ISO mensal (a tag constrói)
│   ├── publish-packages.yml        O CANAL DIÁRIO (o commit de hoje chega
│   │                               ao rig hoje, sem ISO)
│   ├── verify-install.yml          a instalação provada
│   └── …                           agentes/artefatos
├── tests/                      ← A SUÍTE (a cadeia — 2298 peças)
│   ├── lib/                        o ambiente (mocks, extract.sh, core)
│   └── phases/20…50                estática → unidade → integração → release
├── vendor/                     ← FONTES VENDADAS (sha256 pinado; mudou 1
│   │                               byte, o makepkg PARA)
├── scripts/                    ← FERRAMENTAS DO MANTENEDOR
│   ├── apply-overlay.sh            a ponte repo → airootfs
│   ├── logs_dono/                  os dumps do rig do dono (provas)
│   └── …                           forense, qemu, brave
├── docs/                       ← O PAPEL
│   ├── ESTRUTURA.md                este mapa
│   ├── FUTURO.md                   o brainstorm da evolução (E53)
│   ├── SCRIPTS.md                  o índice dos bins (porteira E45/D2)
│   ├── BUILDING.md / VERIFICATION.md / CHANGES.md
│   └── gestao/                     a governança (PROTOCOL, POLIMENTO,
│                                   ARQUITETURA, ATUALIZACOES, AUDITORIA,
│                                   EFICIENCIA)
├── agents/                     ← o harness dos agentes de CI
└── README.md                   ← a porta de entrada (porteira E45/D1:
                                   todo craft-*/elite-* citado existe)
```

## As leis que mantêm o mapa limpo

1. **Fonte única**: um script de casa vive em `elite/airootfs/usr/local/bin/`
   e em lugar NENHUM mais. O PKGBUILD do `elite-system` nasce do
   `.ci/build.sh` (gerado) — não existe cópia para desincronizar.
2. **O pacote único (E50)**: TODO o código de casa viaja em UM pacote
   (`elite-system`) com UM número. Quem quiser saber "qual é a versão do
   sistema da Elite?" olha UM número: `pacman -Q elite-system`.
3. **Lei E41**: conteúdo de casa mudou ⇒ pkgrel sobe NO MESMO commit (o
   guard cobra; sem isso o `-Syu` pula a cura em silêncio).
4. **Lei da release única viva**: NENHUMA tag no dia a dia (a ISO é
   mensal); o canal diário publica pacotes, nunca toca a release.
5. **A suíte é a porteira**: 2298 peças em cadeia; fase morta = NO-GO; o
   CI nunca é o primeiro a ver uma classe de defeito (a lição E49.1).

## Como navegar (as perguntas mais comuns)

| Pergunta | Resposta |
|---|---|
| "Onde mexo num script de casa?" | `elite/airootfs/usr/local/bin/<script>` |
| "Onde está o PKGBUILD do elite-system?" | Dentro do `.ci/build.sh` (bloco PYE50 — gerado, fonte única) |
| "Onde habilito/desabilito algo da ISO?" | `elite/packages.add` / `elite/packages.remove` |
| "Onde a cadência atualiza?" | `elite/airootfs/etc/systemd/system/elite-bootupdate.timer` (ao LIGAR) + `elite-sysupdate.timer` (semanal) |
| "Por que meu push ficou vermelho?" | A suíte ou o guard E41 — a mensagem do assert nomeia o réu |
| "Qual a versão do sistema?" | `pacman -Q elite-system` (UM número para olhar) |
