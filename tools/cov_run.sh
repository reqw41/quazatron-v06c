#!/bin/sh
# Покрытие: случайная игра в MAME, трасса через FIFO -> build/cov/cov_<зерно>.txt
#   tools/cov_run.sh <зерно> <кадров>
cd "$(dirname "$0")/.."
SEED=$1; END=${2:-20000}
mkdir -p build/cov
F=build/cov/fifo_$SEED; rm -f $F; mkfifo $F
python3 tools/cov_collect.py $F build/cov/cov_$SEED.txt &
P=$!
cd zx-stand && QZ_RANDOM=$SEED QZ_END=$END QZ_TRACE=1-$END QZ_TRACEFILE=../$F QZ_MOVES="" ./run.sh -seconds_to_run $((END / 50 + 30)) -snapshot_directory ../build/cov/snap_$SEED >/dev/null 2>&1
wait $P; rm -f ../$F
