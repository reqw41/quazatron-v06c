#!/bin/sh
# Образ ОЗУ оригинала для сборки: лента ZX -> orig/zx/blocks/ -> orig/zx/quazatron_ram.bin (+ снимок quazatron.z80 для MAME).
#   tools/prepare_orig.sh [путь к quazatron.tzx]   — по умолчанию orig/zx/quazatron.tzx
# Лента в репозиторий не входит (Quazatron © 1986 Hewson Consultants); нужна та, с которой сделан порт (md5 ниже).
set -e
cd "$(dirname "$0")/.."
TZX=${1:-orig/zx/quazatron.tzx}
TZX_MD5=2153f5aeec7fb1439804114e59b0cdb3
RAM_MD5=81fc1c872e734f617bc99f9d911b44a9
md5f() { if command -v md5 >/dev/null; then md5 -q "$1"; else md5sum "$1" | cut -d' ' -f1; fi; }
[ -f "$TZX" ] || { echo "нет ленты $TZX"; exit 1; }
[ "$(md5f "$TZX")" = $TZX_MD5 ] || { echo "$TZX: не та лента (нужна md5 $TZX_MD5)"; exit 1; }
mkdir -p orig/zx
[ "$TZX" -ef orig/zx/quazatron.tzx ] || cp "$TZX" orig/zx/quazatron.tzx
python3 tools/tzx_blocks.py orig/zx/quazatron.tzx orig/zx/blocks
python3 tools/mk_zxram.py
[ "$(md5f orig/zx/quazatron_ram.bin)" = $RAM_MD5 ] || { echo "orig/zx/quazatron_ram.bin: md5 не сошёлся"; exit 1; }
echo "orig/zx/quazatron_ram.bin готов"
