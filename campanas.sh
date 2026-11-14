#!/usr/bin/env bash
# Campañas intercaladas: 5 repeticiones por motor, 300 s cada una.
# Uso: bash campanas.sh
# Variables: DUR (segundos), SNAP (intervalo de instantáneas), CORE (núcleo), RES (directorio de resultados)

set -u

BASE=$HOME/fuzzing-lab
JSONC=$BASE/src/json-c
DICT=$JSONC/fuzz/tokener_parse_ex_fuzzer.dict
SEEDS=$BASE/seeds/json

DUR=${DUR:-300}
SNAP=${SNAP:-60}
CORE=${CORE:-0}
RES=${RES:-$BASE/results/campanas-equivalentes-$(date +%Y%m%d-%H%M%S)}

# Mismas opciones para ambos motores.
export ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0
export UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1

# ---------- preflight ----------
for f in "$JSONC/build-libfuzzer/json_fuzzer" \
         "$JSONC/build-afl/json_afl" \
         "$DICT"; do
  [ -e "$f" ] || { echo "FALTA: $f"; exit 1; }
done

if [ "$(cat /proc/sys/kernel/core_pattern)" != "core" ]; then
  echo "ADVERTENCIA: core_pattern no es 'core' -> $(cat /proc/sys/kernel/core_pattern)"
fi

load=$(awk '{print $1}' /proc/loadavg)
awk -v l="$load" 'BEGIN{ if (l > 1.5) exit 1 }' || \
  echo "ADVERTENCIA: load average $load (¿queda algo abierto?)"

mkdir -p "$RES"

echo "Resultados: $RES"
echo "ASAN_OPTIONS=$ASAN_OPTIONS"
echo "UBSAN_OPTIONS=$UBSAN_OPTIONS"

# ---------- utilidades ----------
rss_mon() {
  local log=$1
  while :; do
    printf '%s ' "$(date +%H:%M:%S)" >> "$log"
    ps -Ao rss=,comm= \
      | awk '/json_fuzzer|json_afl/ {printf "%d ", $1/1024}' >> "$log"
    echo >> "$log"
    sleep 10
  done
}

snap() {   # snap <dir-origen> <dir-destino>
  local src=$1 dst=$2 t=0
  while [ "$t" -le "$DUR" ]; do
    if [ -d "$src" ]; then
      mkdir -p "$dst/t$(printf '%03d' "$t")"
      cp -a "$src"/. "$dst/t$(printf '%03d' "$t")/" 2>/dev/null
    fi
    sleep "$SNAP"
    t=$((t + SNAP))
  done
}

# ---------- campañas ----------
run_lf() {
  local rep=$1
  local out=$RES/libfuzzer-$(printf '%02d' "$rep")
  rm -rf "$out"
  mkdir -p "$out/corpus"
  cp "$SEEDS"/*.json "$out/corpus/"

  echo "=== libFuzzer rep $rep — $(date -Is) — load $(cut -d' ' -f1 /proc/loadavg) ==="

  rss_mon "$out/memoria.log" & local m=$!
  snap "$out/corpus" "$out/snapshots" & local s=$!

  taskset -c "$CORE" "$JSONC/build-libfuzzer/json_fuzzer" "$out/corpus" \
    -dict="$DICT" \
    -max_len=4096 \
    -timeout=10 \
    -rss_limit_mb=0 \
    -ignore_crashes=1 -ignore_timeouts=1 \
    -max_total_time="$DUR" \
    -seed=$((1000 + rep)) \
    -print_final_stats=1 \
    -artifact_prefix="$out/" \
    2>&1 | tee "$out/salida.log"

  kill "$m" "$s" 2>/dev/null
  wait "$m" "$s" 2>/dev/null
  cp "$out/memoria.log" "$out/memoria.txt" 2>/dev/null
}

run_afl() {
  local rep=$1
  local out=$RES/afl-$(printf '%02d' "$rep")
  rm -rf "$out"
  mkdir -p "$out/semillas"
  cp "$SEEDS"/*.json "$out/semillas/"

  echo "=== AFL++ rep $rep — $(date -Is) — load $(cut -d' ' -f1 /proc/loadavg) ==="

  rss_mon "$out/memoria.log" & local m=$!
  snap "$out/salida/default/queue" "$out/snapshots" & local s=$!

  AFL_NO_AFFINITY=1 \
  taskset -c "$CORE" afl-fuzz \
    -i "$out/semillas" \
    -o "$out/salida" \
    -x "$DICT" \
    -m none \
    -t 10000 \
    -G 4096 \
    -V "$DUR" \
    -- "$JSONC/build-afl/json_afl" \
    2>&1 | tee "$out/salida.log"

  kill "$m" "$s" 2>/dev/null
  wait "$m" "$s" 2>/dev/null
  cp "$out/memoria.log" "$out/memoria.txt" 2>/dev/null
}

# ---------- ejecución intercalada ----------
for rep in 1 2 3 4 5; do
  run_lf "$rep"
  run_afl "$rep"
done

echo "=== fin — $(date -Is) ==="
echo "Corpus finales:"
echo "  libFuzzer: $RES/libfuzzer-*/corpus"
echo "  AFL++:     $RES/afl-*/salida/default/queue"
