#!/bin/sh
# Замер темпа по трём режимам: мини-игра захвата (кадров ТВ на ход xf_play), проход main_loop без прокрутки и с прокруткой.
# Сценарии — как в lockstep_all (случайные игры + захват), без проверок; профиль тактов по режимам — tools/tempo.py.
#   tools/tempo.sh [проходов]          — сборка Z80 (build/port), итог build/tempo/z80_*.txt
#   I80=1 tools/tempo.sh [проходов]    — сборка i8080 (build/port8080), итог build/tempo/80_*.txt
cd "$(dirname "$0")/.."
N=${1:-3000}; mkdir -p build/tempo
if [ -n "$I80" ]; then CPU="QZ_CPU=8080"; P=80; else CPU="QZ_LS_X=1"; P=z80; fi
run() { name=$1; seed=$2; shift 2; env $CPU QZ_LS_PN=1 QZ_LS_PROF=build/tempo/${P}_$name.prof "$@" node tools/lockstep.js $N $seed > build/tempo/${P}_$name.txt 2>&1; }
for s in 1 2 3 5 6; do run rnd$s $s & done
run salv 28 QZ_LS_AT="CB21:afad=8" QZ_LS_PASS="*:af68=1" &
wait
python3 tools/tempo.py $P
