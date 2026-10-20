#!/usr/bin/env bash
# FASE 5 — O PRODUTO NA MÃO: uso real + release pública (rede; degrada sem quebrar a cadeia)
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

# peças: assets — 2 partes + docs, cada uma ≤ 2 GiB (contrato do GitHub)
p00=$(awk -F'\t' '$1 ~ /\.part-00$/ {print $2}' "$WORK/rel.txt" | head -1)
p01=$(awk -F'\t' '$1 ~ /\.part-01$/ {print $2}' "$WORK/rel.txt" | head -1)
[[ -n "$p00" && -n "$p01" ]] \
  && ok "release: 2 partes presentes (part-00 + part-01)" \
  || fail "release: 2 partes presentes" "p00='$p00' p01='$p01'"
for pair in "part-00:$p00" "part-01:$p01"; do
  sz="${pair#*:}"; nm="${pair%%:*}"
  if [[ -n "$sz" ]] && (( sz > 0 )) && (( sz <= 2147483648 )); then
    ok "release: $nm tem $sz B (≤ 2 GiB — o contrato do split)"
  else
    fail "release: $nm dentro do limite" "size='$sz'"
  fi
done
if [[ -n "$p00" && -n "$p01" ]] && (( p00 >= p01 )); then
  ok "release: part-00 ≥ part-01 (semântica do split: última menor)"
else
  fail "release: part-00 ≥ part-01" "p00='$p00' p01='$p01'"
fi

# peças: sha256sums.txt da release — 3 hashes (ISO + partes)
BASE="https://github.com/Chrispsz/archcraft-elite/releases/download/$TAG"
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
names=$(grep -oE '  \S+$' "$WORK/rel-sums.txt" | sed 's/^  //' | sort -u | wc -l)
assert_eq "$names" "3" "release: 3 arquivos distintos nos hashes"

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
i=0
for pn in part-00 part-01; do
  url=$(curl -sSL --max-time 30 -r 0-1023 -o "$WORK/chunk-$pn" -w '%{http_code}' "$BASE/$ISOn.$pn")
  if [[ "$url" == "206" ]] && (( $(stat -c%s "$WORK/chunk-$pn" 2>/dev/null || echo 0) == 1024 )); then
    ok "release: $pn responde 206 com 1 KiB real (não é 404 de mentira)"
  else
    fail "release: $pn range-request" "http='$url'"
  fi
  i=$((i+1))
done

phase_end
