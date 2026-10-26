#!/bin/sh
# Сборка демо прокрутки: build/demo/qzdemo.r0m (64К с 0x0000) и qzdemo.rom (с 0x0100).
set -e
cd "$(dirname "$0")/.."
SJ=${SJASMPLUS:-$(pwd)/tools/sjasmplus}
mkdir -p build/demo
python3 demo/extract.py
python3 - <<'P'
# таблицы сдвигов: страница 2s — (b << (7-s)) >> 8, страница 2s+1 — младший байт; s = 0..6
t = bytearray()
for s in range(7):
    t += bytes(((b << (7 - s)) >> 8) & 255 for b in range(256))
    t += bytes((b << (7 - s)) & 255 for b in range(256))
open('build/demo/shift_tables.bin', 'wb').write(t)
# данные игры из снимка ОЗУ идущей игры (кадр 1100 стенда, палуба 1)
d = open('orig/zx/state_play1100.bin', 'rb').read()
open('build/demo/zxdata.bin', 'wb').write(d[0x61A9 - 0x4000:0xE000 - 0x4000])
P
cd demo && "$SJ" --nologo --msg=war --lst=../build/demo/qzdemo.lst --fullpath --sld=../build/demo/qzdemo.sld qzdemo.asm
cd .. && python3 tools/check_i8080.py build/demo/qzdemo.lst | tail -3
ls -la build/demo/qzdemo.r0m build/demo/qzdemo.rom
