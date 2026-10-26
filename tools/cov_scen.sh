#!/bin/sh
# Покрытие по сценарию: tools/cov_scen.sh <имя> <кадров>; сценарий — переменные QZ_DBG, QZ_MOVES (см. zx-stand/run.lua)
cd "$(dirname "$0")/.."
NAME=$1; END=${2:-3000}
mkdir -p build/cov
F=build/cov/fifo_$NAME; rm -f $F; mkfifo $F
python3 tools/cov_collect.py $F build/cov/cov_$NAME.txt &
P=$!
cd zx-stand && QZ_END=$END QZ_TRACE=1-$END QZ_TRACEFILE=../$F QZ_SHOT=${QZ_SHOT:-0} ./run.sh -seconds_to_run $((END / 50 + 30)) -snapshot_directory ../build/cov/snap_$NAME >/dev/null 2>&1
wait $P; rm -f ../$F
