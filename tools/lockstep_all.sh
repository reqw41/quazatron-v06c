#!/bin/sh
# Гейт этапа 1: покадровая сверка порта Z80 с ZX (логика + картинка) на наборе сценариев, параллельно, с проверками:
# сторож исполнения, чужие записи, плоскость цвета (QZ_LS_CHECKS). SEEDS="1 2 ..." — зёрна случайных игр.
#   tools/lockstep_all.sh [проходов]   — итог в build/port/lock_<имя>.txt, код возврата 1 при расхождении
#   RU=1 tools/lockstep_all.sh          — русская сборка (quaz_z80_ru.r0m): без сверки картинки, итог lock_ru_<имя>.txt
#   I80=1 tools/lockstep_all.sh         — сборка i8080 (tools/port8080.py, build/port8080/): итог lock80_[ru_]<имя>.txt
cd "$(dirname "$0")/.."
N=${1:-4000}
LIFT="DF76:af0b=0;af20=18;af21=18;af1e=a;af1f=e2"
CONS="DF76:af0b=0;af20=a8;af21=58;af1e=2e;af1f=f2"
CITY="D97B:8078=1;8079=0;807a=0;807b=0;807c=0;807d=0;807e=0;807f=0"
if [ -n "$I80" ]; then CPU="QZ_CPU=8080"; D=build/port8080; P0=lock80_; else CPU=""; D=build/port; P0=lock_; fi
if [ -n "$RU" ]; then MODE="$CPU QZ_LS_RU=1 QZ_ROM=$D/quaz_$([ -n "$I80" ] && echo 8080 || echo z80)_ru.r0m"; P=${P0}ru_; else MODE="$CPU QZ_LS_SCREEN=1"; P=$P0; fi
run() { name=$1; seed=$2; shift 2; env $MODE QZ_LS_CHECKS=1 "$@" node tools/lockstep.js $N $seed > build/port/$P$name.txt 2>&1; }
SEEDS=${SEEDS:-1 2 3 4 5 6}
for s in $SEEDS; do run rnd$s $s & done
run cons 26 QZ_LS_AT="$CONS" QZ_LS_KEMP="1-40:10|41-45:0|46-60:8|61-66:0|67-80:10|200-260:4|300-320:10" &
run lift 27 QZ_LS_AT="$LIFT" QZ_LS_KEMP="1-40:10|41-45:0|46-80:8|81-85:0|86-120:4|121-130:0|131-150:10" &
run lift_det 27 QZ_LS_AT="$LIFT;af8a=81" QZ_LS_KEMP="1-40:10|41-45:0|46-80:8|81-85:0|86-120:4|121-130:0|131-150:10" &
run city 23 QZ_LS_AT="$CITY" &
run hi 24 QZ_LS_PASS="50:b05a=88;b05b=13" &
run salv 28 QZ_LS_AT="CB21:afad=8" QZ_LS_PASS="*:af68=1" &
wait
bad=0
for f in build/port/$P*.txt; do
  n=$(basename $f .txt | sed "s/$P//")
  case $n in ru_*) continue;; esac
  if grep -q "расхождений нет" $f && { [ -n "$RU" ] || grep -q "картинка: проходов с отличиями 0 " $f; } && grep -q "цвет — проходов с отличиями 0;" $f \
     && grep -q "чужих записей 0;" $f && grep -q "замечаний 0" $f; then st=OK; else st=FAIL; bad=1; fi
  printf "%-10s %-4s %s | %s\n" $n $st "$(head -1 $f | cut -d';' -f1)" "$(grep посещения $f | cut -c20-)"
done
exit $bad
