#!/bin/sh
# Долгие и редкие сценарии сверки (с проверками): вспышки, несколько городов, длинные игры.
#   tools/lockstep_soak.sh [проходов длинных игр]   — итог в build/port/soak_<имя>.txt
#   I80=1 tools/lockstep_soak.sh                     — сборка i8080, итог soak80_<имя>.txt
cd "$(dirname "$0")/.."
N=${1:-40000}
CITY="D97B:8078=1;8079=0;807a=0;807b=0;807c=0;807d=0;807e=0;807f=0"
if [ -n "$I80" ]; then CPU="QZ_CPU=8080"; P=soak80_; else CPU=""; P=soak_; fi
run() { name=$1; n=$2; seed=$3; shift 3; env $CPU QZ_LS_SCREEN=1 QZ_LS_CHECKS=1 "$@" node tools/lockstep.js $n $seed > build/port/$P$name.txt 2>&1; }
run flash 8000 41 QZ_LS_PASS="*:af88=05" &
run enflash 8000 42 QZ_LS_AT="D6EF:af83=05" &
run cities 30000 43 QZ_LS_AT="$CITY" &
for s in 51 52 53 54 55 56; do run long$s $N $s & done
wait
bad=0
for f in $(ls build/port/$P*.txt | grep -v ${P}all); do
  n=$(basename $f .txt | sed "s/$P//")
  if grep -q "расхождений нет" $f && grep -q "картинка: проходов с отличиями 0 " $f && grep -q "цвет — проходов с отличиями 0;" $f \
     && grep -q "чужих записей 0;" $f && grep -q "замечаний 0" $f; then st=OK; else st=FAIL; bad=1; fi
  printf "%-8s %-4s %s | %s\n" $n $st "$(head -1 $f | cut -d';' -f1)" "$(grep посещения $f | cut -c20-)"
done
exit $bad
