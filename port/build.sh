#!/bin/sh
# Порт на Вектор с Z80 (этап 1): build/port/quaz_z80.r0m (образ 64К с 0x0000; на MiSTer — .c00, ядро в режиме Z80).
#   port/build.sh [--detector]   — сборка (tools/port_build.py)
#   port/build.sh --ru           — русская версия build/port/quaz_z80_ru.r0m (тексты port/ru/, tools/ru_pack.py)
#   port/build.sh run [кадров]   — сборка и прогон стенда port/run.js со снимком build/port/shot.png
#   port/build.sh --i8080 [--ru] — сборка i8080 (этап 2): образ Z80, затем tools/port8080.py -> build/port8080/quaz_8080[_ru].r0m
#   port/build.sh --i8080 [--ru] --splash — то же и образ с 16-цветной заставкой quaz_8080[_ru]_splash.r0m (tools/mk_splash.py)
set -e
cd "$(dirname "$0")/.."
if [ "$1" = "run" ]; then
  python3 tools/port_build.py
  node port/run.js build/port/quaz_z80.r0m "${2:-1600}" build/port/shot.png "200:4!,300:enter!,700:space,800:space:up,1200:right,1400:right:up"
elif [ "$1" = "--i8080" ]; then
  shift
  SPLASH=; RU=; ARGS=
  for a in "$@"; do case "$a" in --splash) SPLASH=1;; --ru) RU=_ru; ARGS="$ARGS $a";; *) ARGS="$ARGS $a";; esac; done
  python3 tools/port_build.py $ARGS
  python3 tools/port8080.py $ARGS
  [ -n "$SPLASH" ] && python3 tools/mk_splash.py build/port8080/quaz_8080$RU.r0m build/port8080/quaz_8080${RU}_splash.r0m
  true
else
  python3 tools/port_build.py "$@"
fi
