# DIÁRIO DE ATUALIZAÇÕES — o que o mundo soltou hoje

Tarefa 1 do protocolo (`PROTOCOL.md`). Roda diário 08:30 -03.

Escopo: pins de versão que o build sela em `.ci/build.sh` (brave-origin,
python-pywal, qt5-virtualkeyboard, libyuv, pwvucontrol, craft-toplevel) e
qualquer defasagem nova que a API dos upstreams mostrar. Regra L9: pin só
sobe com checksum publicado e verificado; sem checksum = não sobe, e o
diário explica o porquê.

Formato: ver `PROTOCOL.md` (feito/prova/próximo). Entrada por dia, mesmo
em dia sem nada ("nada a atualizar — provado contra as APIs X, Y, Z").

## ESTADO INICIAL (antes da 1ª entrada)
- próximo: brave (check-brave.sh) + python-pywal (PyPI, via API) + qt5-virtualkeyboard (tag do Qt no GitHub).
- Rotação sugerida dos demais: libyuv → pwvucontrol → craft-toplevel → cachyos-keyring → cachyos-v3-mirrorlist (os últimos 2 acompanham a data, não API de release — registrar o que provou).

## 2026-11-02 · atualizações
- feito: NADA a atualizar — dia de provas, todos os 3 pins do estado inicial conferidos contra os upstreams. IMPORTANTE: esta é a REPOSITÓRIA MANUAL da cron das 08:30 — o run disparou na hora (run_count=1, last_run 08:30 -03) mas FALHOU na plataforma antes do agente rodar ('model concurrency limit exceeded', limite de concorrência do provedor de modelo, não bug do protocolo); o dono perguntou 'E agora?' e a tarefa foi executada à mão ~09:15 -03, passo a passo do protocolo. Sem commit de código (nada subiu em lugar nenhum).
- prova: (1) check-brave.sh com GH_TOKEN: pin 1.98.63 = latest 1.98.63, '✔ pin em dia', exit 0. (2) pywal: dylanaraps/pywal master HEAD = 236aa48e741f == PYWAL_PIN (repo arquivado, último commit 2021-09-09 — zero movimento); PyPI 'pywal' latest = 3.8.15 MAS é o fork pywal16 (home_page: github.com/eylles/pywal16) publicado sob o nome original — NÃO adotado: trocar a fonte muda a provenance do pacote (decisão de dono/release, não de pin diário; L9 não se aplica porque não é sobe de versão, é troca de linhagem). (3) qt5-virtualkeyboard: tags v5.15.16/v5.15.17/v5.15.18 → HTTP 404 no repo do módulo E no qtbase — a série 5.15 não é tagada no GitHub público (pós-5.15.13 é release comercial, código fechado); não existe versão pública nova a acompanhar; o stub é placeholder de dependência (não compila nada do Qt), sem checksum a verificar. (4) CI main: último run 41338436229 (2aba0bb) = success; pushes docs-only (d6d258e, 2e35a7a) sem run por paths-filter do tests.yml — por desenho, não CI engolida. (5) Suíte local: 2016 peças · 0 falhas · 2 pulos · GO (porteira antes deste push).
- próximo: brave (check-brave.sh) + libyuv (API do repo) + pwvucontrol (API do repo) — primeiros 2 da rotação semente. FATO registrado para o dono: o nome 'pywal' no PyPI agora serve o fork pywal16 3.8.15; se um dia o pywal original faltar, a migração de linhagem (nova fonte + checksums + suíte) é caminho de release.

## 2026-11-03 · atualizações
- feito: PROVENIÊNCIA HONESTA: a irmã das 08:30 não escreveu hoje (o buraco que a auditoria da manhã registrou); esta entrada é a repositora MANUAL da noite (E40, sob demanda do dono) com o dia inteiro dentro. (1) CICLO DE RELEASE sob demanda: v2.10.26 → túmulo (a SEGUNDA porta — o build.yml herdava o git desconfiado do checkout@v5; cura f8d6f25) → v2.10.27 = release viva (run 41701203539 verde, 6 jobs, ~46min; GATE 2 independente: ISO reconstituída + sha256 c8c00a6bd3825510… OK, 19 assets; Lei aplicada pela CI — 1 viva, tags intactas). (2) PINS provados HOJE: brave 1.98.63 = latest (check-brave exit 0); pywal (repo arquivado, zero movimento) e qt5-virtualkeyboard (série 5.15 sem tag pública) sem novidade desde a prova de ontem — nada a atualizar. (3) AUDITORIA E40 sob demanda ('cadê o botão pra abrir o terminal?'): cura do verbo 'Abrir terminal aqui' no Thunar (uca.xml do skel + ponte exo-open em /usr/local/bin + handler x-scheme-handler/terminal=foot.desktop) — raiz dupla provada no FONTE OFICIAL do Thunar 4.20.10 (o uca de fábrica — única fonte do 'Open Terminal Here' — é sombreado pelo skel E35 SEM merge, e o comando de fábrica exo-open nem existe na ISO); porteira GO 2102·0·2 (a porteira pegou o mantenedor 1×: exo-open sem registro no file_permissions = 203/EXEC no live); gparted confirmado NÃO-ser-requisito (é a conversa PAM do pkexec — diagnóstico ec7e823, teste sudo -v do dono pendente).
- prova: check-brave.sh exit 0 (pin 1.98.63 = latest 1.98.63) · suíte local 2102 peças · 0 falhas · 2 pulos · GO · fontes do Thunar 4.20.10 (gitlab.xfce.org, tag thunar-4.20.10): plugins/thunar-uca/uca.xml.in (1 ação, exo-open), thunar-uca-model.c:278-285 (xfce_resource_lookup sem merge), thunar-file.c:1756 (exo-open interno) · foot.1.scd:99 (-D/--working-directory) · run v2.10.27 41701203539 success + GATE 2 sha256 OK (prova do ciclo, AUDITORIA de hoje) · XML do uca validado (minidom) · 100755 no índice (ls-files -s; E39).
- próximo: a 08:30 de amanhã vigiada (2º dia sem entrada = padrão confirmado, escala ao dono) · brave (check-brave.sh) + libyuv + pwvucontrol na rotação de amanhã · o E40 viaja na próxima ISO (ciclo sob demanda do dono) · a cura do gparted decide-se com o sudo -v do dono (não curar no chute).
