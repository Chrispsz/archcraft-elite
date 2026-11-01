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
