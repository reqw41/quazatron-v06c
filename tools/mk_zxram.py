#!/usr/bin/env python3
"""Образ ОЗУ ZX 48K (0x4000-0xFFFF) после загрузчика Quazatron без эмуляции ленты.
Загрузчик (0x850A, вызов USR EXP 10.4355 = 0x8500): блок q -> 25001, затем LD-BYTES
по 0x9603 (8192), 0xB603 (8192), 0xD603 (6397 = 0x18FD), старт = (0x8506) = 0xDE70.
Выход: orig/zx/quazatron_ram.bin (48 КБ с 0x4000), orig/zx/quazatron.z80 (снимок v1, PC=старт)."""
import os, struct
B = 'orig/zx/blocks/'
ram = bytearray(0xC000)
def put(addr, data): ram[addr-0x4000:addr-0x4000+len(data)] = data
put(25001, open(B+'03_data.bin', 'rb').read())
entry = ram[0x8506-0x4000] | ram[0x8507-0x4000] << 8
put(0x9603, open(B+'04_data.bin', 'rb').read())
put(0xB603, open(B+'05_data.bin', 'rb').read())
put(0xD603, open(B+'06_data.bin', 'rb').read())
# загрузчик затирает себя (0x850A..0x8538) на RST 38h после первого блока — повторим
for a in range(0x850A, 0x850A+0x2F): ram[a-0x4000] = 0xC7
open('orig/zx/quazatron_ram.bin', 'wb').write(ram)
sp = 0x61A0
# .z80 v1: A F BC HL PC SP I R flags DE BC' DE' HL' A' F' IY IX IFF1 IFF2 IM
hdr = struct.pack('<BBHHHHBBBHHHHBBHHBBB', 0, 0, 0, 0, entry, sp, 0x3F, 0, 0x00, 0, 0, 0, 0, 0, 0, 0x5C3A, 0, 0, 0, 1)
open('orig/zx/quazatron.z80', 'wb').write(hdr + ram)
print(f'entry={entry:#06x} sp={sp:#06x}')
