#!/usr/bin/env bash
# FASE 5 — O PRODUTO NA MÃO: uso real + release pública (rede; degrada sem quebrar a cadeia)
# v1.8.1 — BIMODAL + CONTRATO PVD:
#   A v1.8.0 subiu TRUNCADA (asset 1.55 GiB; o PVD interno da ISO declarava
#   2.77 GiB — 56,2% do arquivo real) e a classe passou despercebida: split
#   <2GiB + zero verificação pós-upload. O PVD (Primary Volume Descriptor,
#   ISO9660, byte 0x8000) declara o tamanho da ISO que o xorriso BUILDOU —
#   se os bytes publicados ≠ tamanho declarado, o asset foi truncado (e o
#   Ventoy/GRUB recusa na hora). O contrato baixa 33 KiB (range-request),
#   parseia o PVD e compara com o tamanho do asset — matemática, não
#   confiança. Suporta os 2 modos de release: ISO ÚNICA (≤ 2 GiB) e SPLIT
#   (part-00/part-01, ISO > 2 GiB).
source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"
phase_start 5 "USO & RELEASE — o produto na mão"

API="https://api.github.com/repos/Chrispsz/archcraft-elite"
if ! curl -fsS --max-time 15 "$API/releases?per_page=5" -o "$WORK/releases.json" 2>/dev/null; then
  skip "release: sem rede (fase inteira)" "a cadeia segue de pé — o resto já provou o essencial"
  phase_end
  return 2>/dev/null || exit 0
fi

python3 - "$WORK/releases.json" <<'PYEOF' > "$WORK/rel.txt" 2>/dev/null || true
import json,sys
rels=json.load(open(sys.argv[1]))
r=next((x for x in rels if not x.get('draft')), None)
if not r: print("NO-RELEASE"); sys.exit(0)
print(r['tag_name'])
print(r['name'])
for a in r.get('assets',[]):
    print(f"{a['name']}\t{a['size']}")
PYEOF

TAG=$(sed -n 1p "$WORK/rel.txt")
if [[ "$TAG" == "NO-RELEASE" || -z "$TAG" ]]; then
  fail "release: existe uma release publicada" "nenhuma não-draft encontrada"
  phase_end
  return 2>/dev/null || exit 0
fi
ok "release: tag mais recente publicada — $TAG"

BASE="https://github.com/Chrispsz/archcraft-elite/releases/download/$TAG"

# ── detecção do modo ──────────────────────────────────────────────────
p00=$(awk -F'\t' '$1 ~ /\.part-00$/ {print $2}' "$WORK/rel.txt" | head -1)
p01=$(awk -F'\t' '$1 ~ /\.part-01$/ {print $2}' "$WORK/rel.txt" | head -1)
iso=$(awk -F'\t' '$1 ~ /^archcraft-elite-.*-x86_64\.iso$/ {print $2}' "$WORK/rel.txt" | head -1)

MODE="none"
if [[ -n "$p00" && -n "$p01" ]]; then
  MODE="split"
elif [[ -n "$iso" ]]; then
  MODE="single"
fi
ok "release: modo detectado = $MODE"

# ── PVD helper: baixa 33 KiB do asset, parseia o descriptor ──────────
# imprime o tamanho declarado (blocos × bytes/bloco); stdout limpo.
pvd_declared() { # $1 = nome do asset (com o PVD; na ISO inteira ou part-00)
  local f="$WORK/pvd.bin"
  if ! curl -fsSL --max-time 30 -r 0-33791 "$BASE/$1" -o "$f" 2>/dev/null; then
    echo "CURL-FAIL"; return 0
  fi
  python3 - "$f" <<'PYPVD'
import struct, sys
buf = open(sys.argv[1], 'rb').read()
pvd = buf[32768:32768+2048]
if pvd[1:6] != b'CD001':
    print("PVD-INVALID"); sys.exit(0)
vss = struct.unpack('<I', pvd[80:84])[0]
bs  = struct.unpack('<H', pvd[128:130])[0]
print(vss * bs)
PYPVD
}

if [[ "$MODE" == "split" ]]; then
  # peças: assets — 2 partes + docs, cada uma ≤ 2 GiB (contrato do GitHub)
  ok "release: 2 partes presentes (part-00 + part-01)"
  for pair in "part-00:$p00" "part-01:$p01"; do
    sz="${pair#*:}"; nm="${pair%%:*}"
    if [[ -n "$sz" ]] && (( sz > 0 )) && (( sz <= 2147483648 )); then
      ok "release: $nm tem $sz B (≤ 2 GiB — o contrato do split)"
    else
      fail "release: $nm dentro do limite" "size='$sz'"
    fi
  done
  if (( p00 >= p01 )); then
    ok "release: part-00 ≥ part-01 (semântica do split: última menor)"
  else
    fail "release: part-00 ≥ part-01" "p00='$p00' p01='$p01'"
  fi
  # ISO real reconstruída = soma das partes
  REAL=$(( p00 + p01 ))
  ok "release: ISO real (part-00 + part-01) = $REAL B"

  # peças: sha256sums.txt — 3 hashes (ISO inteira + 2 partes)
  if curl -fsSL --max-time 30 "$BASE/sha256sums.txt" -o "$WORK/rel-sums.txt" 2>/dev/null; then
    ok "release: sha256sums.txt baixável"
  else
    fail "release: sha256sums.txt baixável" "HTTP falhou"
  fi
  n=$(grep -cE '^[0-9a-f]{64}  .+$' "$WORK/rel-sums.txt" 2>/dev/null || echo 0)
  assert_eq "$n" "3" "release: sha256sums traz 3 hashes (ISO inteira + 2 partes)"
  ISOn=$(grep -oE '  \S+$' "$WORK/rel-sums.txt" | grep -E 'archcraft-elite-.*-x86_64\.iso$' | head -1 | sed 's/^  //')
  [[ -n "$ISOn" ]] \
    && ok "release: hash da ISO inteira presente ($ISOn)" \
    || fail "release: hash da ISO inteira presente" "linha .iso ausente"

  # peças: JUNTAR-ISO.md — as instruções casam com os assets reais
  if curl -fsSL --max-time 30 "$BASE/JUNTAR-ISO.md" -o "$WORK/rel-juntar.md" 2>/dev/null; then
    ok "release: JUNTAR-ISO.md baixável"
  else
    fail "release: JUNTAR-ISO.md baixável" "HTTP falhou"
  fi
  assert_grep "$WORK/rel-juntar.md" 'cat .*\.part-\* > ' "juntar: comando cat com glob das partes"
  assert_grep "$WORK/rel-juntar.md" "sha256sum -c <\(grep -E 'part\|" "juntar: verificação com grep aspasado (armadilha A1 fechada)"
  jiso=$(grep -oE 'cat \S+\.part-\*' "$WORK/rel-juntar.md" | head -1 | sed 's/^cat //; s/\.part-\*$//')
  [[ -n "$ISOn" && "$jiso" == "$ISOn" ]] \
    && ok "juntar: o nome da ISO no comando == nome hasheado (encaixe perfeito)" \
    || fail "juntar: nome da ISO bate" "cat diz '$jiso' · hash diz '$ISOn'"

  # peças: as partes respondem 206 (range) — estão MESMO baixáveis
  for pn in part-00 part-01; do
    url=$(curl -sSL --max-time 30 -r 0-1023 -o "$WORK/chunk-$pn" -w '%{http_code}' "$BASE/$ISOn.$pn")
    if [[ "$url" == "206" ]] && (( $(stat -c%s "$WORK/chunk-$pn" 2>/dev/null || echo 0) == 1024 )); then
      ok "release: $pn responde 206 com 1 KiB real (não é 404 de mentira)"
    else
      fail "release: $pn range-request" "http='$url'"
    fi
  done

  # CONTRATO PVD (o caçador da v1.8.0 truncada): a part-00 carrega o
  # descriptor da ISO INTEIRA — o tamanho declarado tem de ser EXATAMENTE
  # a soma das partes publicadas. 1 byte de diferença = truncamento.
  decl=$(pvd_declared "$ISOn.part-00")
  if [[ "$decl" == "CURL-FAIL" || "$decl" == "PVD-INVALID" ]]; then
    fail "release: PVD legível na part-00" "resposta='$decl'"
  elif [[ "$decl" == "$REAL" ]]; then
    ok "release: PVD declara $decl B == part-00+part-01 ($REAL B) — NENHUM truncamento"
  else
    fail "release: PVD == bytes publicados (o caçador da classe v1.8.0 truncada)" \
         "PVD declara $decl B · partes somam $REAL B ($(awk "BEGIN{printf \"%.1f\", 100.0*$REAL/$decl}")%)"
  fi

elif [[ "$MODE" == "single" ]]; then
  # modo ISO única (≤ 2 GiB): asset único direto no Ventoy/Rufus
  if (( iso > 0 && iso <= 2147483648 )); then
    ok "release: ISO única com $iso B (≤ 2 GiB — contrato do GitHub)"
  else
    fail "release: ISO única dentro do limite" "size='$iso'"
  fi
  # peças: sha256sums.txt — ≥ 1 hash, com a ISO
  if curl -fsSL --max-time 30 "$BASE/sha256sums.txt" -o "$WORK/rel-sums.txt" 2>/dev/null; then
    ok "release: sha256sums.txt baixável"
  else
    fail "release: sha256sums.txt baixável" "HTTP falhou"
  fi
  n=$(grep -cE '^[0-9a-f]{64}  .+$' "$WORK/rel-sums.txt" 2>/dev/null || echo 0)
  (( n >= 1 )) \
    && ok "release: sha256sums traz $n hash(es)" \
    || fail "release: sha256sums com hashes" "n='$n'"
  ISOn=$(grep -oE '  \S+$' "$WORK/rel-sums.txt" | grep -E 'archcraft-elite-.*-x86_64\.iso$' | head -1 | sed 's/^  //')
  [[ -n "$ISOn" ]] \
    && ok "release: hash da ISO presente ($ISOn)" \
    || fail "release: hash da ISO presente" "linha .iso ausente"
  # peças: a ISO responde 206 (range) — baixável de verdade
  url=$(curl -sSL --max-time 30 -r 0-1023 -o "$WORK/chunk-iso" -w '%{http_code}' "$BASE/$ISOn")
  if [[ "$url" == "206" ]] && (( $(stat -c%s "$WORK/chunk-iso" 2>/dev/null || echo 0) == 1024 )); then
    ok "release: ISO responde 206 com 1 KiB real"
  else
    fail "release: ISO range-request" "http='$url'"
  fi
  # CONTRATO PVD — o mesmo caçador, no modo single
  decl=$(pvd_declared "$ISOn")
  if [[ "$decl" == "CURL-FAIL" || "$decl" == "PVD-INVALID" ]]; then
    fail "release: PVD legível na ISO" "resposta='$decl'"
  elif [[ "$decl" == "$iso" ]]; then
    ok "release: PVD declara $decl B == asset publicado ($iso B) — NENHUM truncamento"
  else
    fail "release: PVD == bytes publicados (o caçador da classe v1.8.0 truncada)" \
         "PVD declara $decl B · asset tem $iso B ($(awk "BEGIN{printf \"%.1f\", 100.0*$iso/$decl}")%)"
  fi

else
  fail "release: modo detectável (single OU split)" "nenhum *.iso nem *.part-* nos assets da release $TAG"
fi

phase_end
