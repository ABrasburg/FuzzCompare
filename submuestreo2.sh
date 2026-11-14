cd ~/fuzzing-lab
R=tools/replay; RX='(fuzz/|replay_main|/usr/)'
OUT=results/cobertura/submuestreo2; TMP=$OUT/tmp; mkdir -p $OUT
TSV=$OUT/sub.tsv; : > $TSV
for i in 01 02 03 04 05; do for m in libfuzzer afl; do
  if [ $m = libfuzzer ]; then src=results/campanas/libfuzzer-$i/corpus; else src=results/campanas/afl-$i/salida/default/queue; fi
  for n in 50 100 200 400 800; do for rep in 1 2 3; do
    rm -rf $TMP; mkdir -p $TMP
    ls $src | shuf -n $n --random-source=<(yes "$i$n$rep") | while read -r f; do cp "$src/$f" $TMP/; done
    rm -f $OUT/p.prof*
    LLVM_PROFILE_FILE=$OUT/p.profraw $R $TMP >/dev/null 2>&1
    llvm-profdata merge -sparse $OUT/p.profraw -o $OUT/p.profdata
    pct=$(llvm-cov report $R -instr-profile=$OUT/p.profdata --ignore-filename-regex="$RX" | awk '/^TOTAL/{print $4}')
    printf '%s\t%s\t%s\t%s\t%s\n' $m $i $n $rep $pct >> $TSV
  done; done
  echo "$m-$i listo"
done; done
echo FIN
