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
