#!/bin/sh
# ./run.sh [доп. ключи MAME] — переменные QZ_* см. run.lua; QZ_SCRIPT — другой скрипт (memtap.lua)
cd "$(dirname "$0")" && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy exec mame spectrum -exp kempjoy -rompath . \
  -dump ../orig/zx/quazatron.z80 -video none -sound none -nothrottle -seconds_to_run 300 \
  -snapshot_directory snap -script ${QZ_SCRIPT:-run.lua} -skip_gameinfo -debug -debugger none "$@"
