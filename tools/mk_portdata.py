#!/usr/bin/env python3
"""Данные разметки оригинала для сборки порта -> port/data/: blocks.txt (блоки кода и данных, tools/mk_disasm.py)
и relo_labelled.txt — адреса команд кода, у которых операнд в листинге build/quaz.asm записан меткой внутри
переносимого блока DE70-EE91 (tools/port_build.py сдвигает только их). Нужны build/blocks.txt и build/quaz.asm."""
import re, shutil
RELO_LO, RELO_HI = 0xDE70, 0xEE91
shutil.copy('build/blocks.txt', 'port/data/blocks.txt')
code = set()
for l in open('build/blocks.txt'):
    m = re.match(r'b\d+: start 0x(\w+) end 0x(\w+) type code', l)
    if m: code |= set(range(int(m[1], 16), int(m[2], 16)))
# только операнды, записанные в листинге меткой (имя или lXXXXh): числа вроде ld bc,0DFFEh (порт клавиатуры) — не адреса
symaddr = {}
for l in open('docs/symbols.txt', encoding='utf-8'):
    m = re.match(r'([0-9A-Fa-f]{4})\s+(\w+)', l)
    if m: symaddr[m[2]] = int(m[1], 16)
labelled = set()                                       # адреса команд, у которых операнд — метка в блоке
for l in open('build/quaz.asm', encoding='latin-1'):
    m = re.match(r'\t(\S+)\s+([^;]*?)\s*;([0-9a-f]{4})\s*$', l)
    if not m or int(m[3], 16) not in code: continue
    for tok in re.findall(r'[A-Za-z_]\w*', m[2]):
        v = symaddr.get(tok, int(tok[1:5], 16) if re.fullmatch(r'l[0-9a-f]{4}h', tok) else None)
        if v is not None and RELO_LO <= v < RELO_HI: labelled.add(int(m[3], 16))

open('port/data/relo_labelled.txt', 'w').write('\n'.join(f'{a:04X}' for a in sorted(labelled)) + '\n')
print(len(code), 'байт кода,', len(labelled), 'команд с меткой')
