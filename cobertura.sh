set -u

BASE=$HOME/fuzzing-lab
JSONC=$BASE/src/json-c
RES=$BASE/results/campanas
OUT=$BASE/results/cobertura
TOOLS=$BASE/tools

mkdir -p "$OUT" "$TOOLS"
: > "$OUT/total.txt"
: > "$OUT/curvas.txt"

[ -f "$TOOLS/replay_main.c" ] || { echo "FALTA $TOOLS/replay_main.c"; exit 1; }

# ---------- 1. build de cobertura (sin sanitizers) ----------
if [ ! -f "$JSONC/build-cov/libjson-c.a" ]; then
  echo "== compilando build-cov =="
  cmake -S "$JSONC" -B "$JSONC/build-cov" \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_C_FLAGS="-g -O1 -fprofile-instr-generate -fcoverage-mapping" \
    -DCMAKE_CXX_FLAGS="-g -O1 -fprofile-instr-generate -fcoverage-mapping" || exit 1
  cmake --build "$JSONC/build-cov" -j2 || exit 1
fi

clang -g -O1 -fprofile-instr-generate -fcoverage-mapping \
  -c "$TOOLS/replay_main.c" -o "$TOOLS/replay_main.o" || exit 1

clang++ -g -O1 -fprofile-instr-generate -fcoverage-mapping \
  -I "$JSONC" -I "$JSONC/build-cov" \
  "$JSONC/fuzz/tokener_parse_ex_fuzzer.cc" \
  "$TOOLS/replay_main.o" \
  "$JSONC/build-cov/libjson-c.a" \
  -o "$TOOLS/replay" || exit 1

# ---------- 2. medición ----------
medir() {   # medir <etiqueta> <directorio> <archivo-salida>
  local tag=$1 dir=$2 dest=$3
  [ -d "$dir" ] || { echo "$tag,FALTA_DIR"; return; }
  local p="$OUT/$tag"
  rm -f "$p.profraw" "$p.profdata"

  LLVM_PROFILE_FILE="$p.profraw" "$TOOLS/replay" "$dir" >/dev/null 2>&1
  [ -f "$p.profraw" ] || { echo "$tag,SIN_DATOS"; return; }

  llvm-profdata merge -sparse "$p.profraw" -o "$p.profdata" 2>/dev/null || {
    echo "$tag,MERGE_FALLO"; return; }

  llvm-cov report "$TOOLS/replay" -instr-profile="$p.profdata" \
      --ignore-filename-regex='(fuzz/|replay_main|/usr/)' 2>/dev/null \
    | awk -v t="$tag" '/^TOTAL/ {print t"\t"$0}' >> "$dest"
}

echo "== corpus finales =="
for rep in 01 02 03 04 05; do
  medir "lf-$rep"  "$RES/libfuzzer-$rep/corpus"              "$OUT/total.txt"
  medir "afl-$rep" "$RES/afl-$rep/salida/default/queue"      "$OUT/total.txt"
done

echo "== instantáneas (curvas de cobertura) =="
for d in "$RES"/libfuzzer-*/snapshots/t*; do
  [ -d "$d" ] || continue
  camp=$(basename "$(dirname "$(dirname "$d")")")
  t=$(basename "$d")
  medir "$camp-$t" "$d" "$OUT/curvas.txt"
done
for d in "$RES"/afl-*/snapshots/t*; do
  [ -d "$d" ] || continue
  camp=$(basename "$(dirname "$(dirname "$d")")")
  t=$(basename "$d")
  medir "$camp-$t" "$d" "$OUT/curvas.txt"
done

echo
echo "Listo. Pasame el contenido de:"
echo "  $OUT/total.txt"
echo "  $OUT/curvas.txt"

