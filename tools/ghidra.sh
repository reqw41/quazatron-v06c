#!/bin/sh
# Анализ образа ZX в консольной Ghidra (Z80): build/ghidra_{funcs,xrefs,code}.txt
cd "$(dirname "$0")/.."
G=${GHIDRA_HEADLESS:-/opt/homebrew/Cellar/ghidra/12.1.4/libexec/support/analyzeHeadless}
# засев: покрытие трассы + старт игры (DE70) + обработчик прерывания BD2D.
( cat build/cov_pcs.txt; printf "DE70\nBD2D\n" ) | sort -u > build/seeds.txt
# образ для анализа — как после старта: E6E6 = jp isr (DE70 пишет C3 2D BD до включения прерываний)
python3 - <<'P'
d = bytearray(open('orig/zx/quazatron_ram.bin', 'rb').read())
d[0xE6E6 - 0x4000:0xE6E9 - 0x4000] = bytes([0xC3, 0x2D, 0xBD])
open('build/quaz_ghidra.bin', 'wb').write(d)
P
rm -rf build/ghidra_proj && mkdir -p build/ghidra_proj
"$G" build/ghidra_proj quaz -import build/quaz_ghidra.bin -loader BinaryLoader -loader-baseAddr 0x4000 \
  -processor "z80:LE:16:default" -scriptPath tools/ghidra -postScript QuazExport.java \
  build/seeds.txt build/call_targets.txt build "$@" 2>&1 | grep -E "ERROR|Exception" || true
wc -l build/ghidra_funcs.txt build/ghidra_code.txt
