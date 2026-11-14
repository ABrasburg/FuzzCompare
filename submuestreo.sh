set -u

BASE=$HOME/fuzzing-lab
COV=$BASE/results/cobertura
CAMP=$BASE/results/campanas
REPLAY=$BASE/tools/replay
OUT=$COV/submuestreo
TMP=$OUT/tmp
REGEX='(fuzz/|replay_main|/usr/)'

mkdir -p "$OUT"
[ -x "$REPLAY" ] || { echo "FALTA $REPLAY (corré cobertura.sh primero)"; exit 1; }

medir_dir() {  # medir_dir <dir> -> imprime la línea TOTAL
  rm -f "$OUT/p.profraw" "$OUT/p.profdata"
  LLVM_PROFILE_FILE="$OUT/p.profraw" "$REPLAY" "$1" >/dev/null 2>&1
  [ -f "$OUT/p.profraw" ] || { echo "SIN_DATOS"; return; }
  llvm-profdata merge -sparse "$OUT/p.profraw" -o "$OUT/p.profdata" 2>/dev/null || { echo "MERGE_FALLO"; return; }
  llvm-cov report "$REPLAY" -instr-profile="$OUT/p.profdata" \
    --ignore-filename-regex="$REGEX" 2>/dev/null | awk '/^TOTAL/'
  rm -f "$OUT/p.profraw" "$OUT/p.profdata"
}

curva() {  # curva <etiqueta> <dir-corpus> <lista-de-tamanios>
  local tag=$1 src=$2 sizes=$3
  local tsv=$OUT/$tag.tsv
  : > "$tsv"

  local total
  total=$(ls "$src" | wc -l)

  for size in $sizes; do
    [ "$size" -le "$total" ] || continue
    for rep in 1 2 3; do
      rm -rf "$TMP"; mkdir -p "$TMP"
      ls "$src" | shuf -n "$size" | while read -r f; do
        cp "$src/$f" "$TMP/" 2>/dev/null
      done
      local n
      n=$(ls "$TMP" | wc -l)
      printf '%s\t%s\t%s\n' "$n" "$rep" "$(medir_dir "$TMP")" >> "$tsv"
      printf '  %s n=%s rep=%s\n' "$tag" "$n" "$rep"
    done
  done

  # referencia: corpus completo
  printf '%s\t%s\t%s\n' "$total" "0" "$(medir_dir "$src")" >> "$tsv"
  echo "  -> $tsv"
}

echo "== libFuzzer-01 =="
curva "lf-01" "$CAMP/libfuzzer-01/corpus" "50 100 200 400 800 1600 3200"

echo "== AFL++-01 =="
curva "afl-01" "$CAMP/afl-01/salida/default/queue" "50 100 200 400 700"

echo
echo "Listo. Pasá el contenido de:"
echo "  $OUT/lf-01.tsv"
echo "  $OUT/afl-01.tsv"

