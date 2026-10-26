#!/usr/bin/env python3
"""Аудит кода оригинала для перевода Z80 -> i8080: docs/AUDIT.md.
Источник: build/ghidra_code.txt (адрес, длина, текст команды), build/ghidra_xrefs.txt, docs/symbols.txt.
Ищет: железо ZX (порты, экран, атрибуты), самомодификацию (запись в байты кода), ld a,r, IX/IY,
exx / ex af, флаги P/V (на i8080 — только чётность), daa после вычитания, ld sp, block-команды."""
import re, collections
code = []                              # (адрес, длина, текст)
for l in open('build/ghidra_code.txt'):
    a, n, t = l.rstrip('\n').split(None, 2)
    code.append((int(a[4:], 16), int(n), t.strip()))
code.sort()
isc = bytearray(0x10000)
for a, n, t in code:
    for i in range(n): isc[a + i] = 1
syms = {}
for l in open('docs/symbols.txt', encoding='utf-8'):
    m = re.match(r'([0-9A-Fa-f]{4})\s+(\w+)', l)
    if m: syms[int(m[1], 16)] = m[2]
funcs = sorted(int(l.split()[0][4:], 16) for l in open('build/ghidra_funcs.txt'))
import bisect
def owner(a):
    i = bisect.bisect_right(funcs, a) - 1
    f = funcs[i] if i >= 0 else None
    return f'{syms.get(f, "%04X" % f) if f is not None else "?"}'
def nm(a): return syms.get(a, f'{a:04X}')

sec = collections.OrderedDict((k, []) for k in [
    'Порты ввода-вывода', 'Экран ZX (0x4000-0x57FF)', 'Атрибуты ZX (0x5800-0x5AFF)', 'Прерывания и IM',
    'Самомодификация (запись в байты кода)', 'ld a,r / ld a,i (R нет на i8080)', 'IX / IY',
    'exx / ex af,af\'', 'Флаги P/V (на i8080 — только чётность)', 'daa', 'ld sp / ex (sp)', 'Block-команды (ldir и др.)',
    'Сдвиги и биты CB (на i8080 нет)'])
prev = None
for a, n, t in code:
    u = t.upper()
    loc = f'`{a:04X}` {owner(a)}: `{t}`'
    if re.match(r'(IN|OUT|INI|INIR|OUTI|OTIR|IND|OUTD)\b', u): sec['Порты ввода-вывода'].append(loc)
    if re.search(r'\b(DI|EI|IM|HALT|RETI|RETN)\b', u): sec['Прерывания и IM'].append(loc)
    if re.match(r'LD A,[RI]$', u): sec['ld a,r / ld a,i (R нет на i8080)'].append(loc)
    if re.search(r'\bI[XY]', u): sec['IX / IY'].append(loc)
    if re.match(r'(EXX|EX AF)', u): sec["exx / ex af,af'"].append(loc)
    if re.search(r'\b(JP|CALL|RET)\s+(PE|PO)\b', u) or re.match(r'(JP|CALL|RET) (PE|PO)', u):
        sec['Флаги P/V (на i8080 — только чётность)'].append(loc + (f' (после `{prev}`)' if prev else ''))
    if u.startswith('DAA'): sec['daa'].append(loc + (f' (после `{prev}`)' if prev else ''))
    if re.match(r'LD SP|EX \(SP\)', u): sec['ld sp / ex (sp)'].append(loc)
    if re.match(r'(LDIR|LDDR|LDI|LDD|CPIR|CPDR|CPI|CPD)\b', u): sec['Block-команды (ldir и др.)'].append(loc)
    if re.match(r'(RLC|RRC|RL|RR|SLA|SRA|SRL|SLL|BIT|SET|RES) ', u): sec['Сдвиги и биты CB (на i8080 нет)'].append(loc)
    prev = t
# обращения к памяти по Ghidra: экран, атрибуты, самомодификация
seen = set()
for l in open('build/ghidra_xrefs.txt'):
    p = l.split(None, 4)
    to, kind, fr = int(p[0][4:], 16), p[1], int(p[2][4:], 16)
    if 'CALL' in kind or 'JUMP' in kind or 'FLOW' in kind: continue
    loc = f'`{fr:04X}` {owner(fr)} -> `{to:04X}` ({kind}): `{p[4].strip()[1:-1] if len(p) > 4 else ""}`'
    if 0x4000 <= to < 0x5800: sec['Экран ZX (0x4000-0x57FF)'].append(loc)
    elif 0x5800 <= to < 0x5B00: sec['Атрибуты ZX (0x5800-0x5AFF)'].append(loc)
    elif 'WRITE' in kind and isc[to] and (fr, to) not in seen:
        seen.add((fr, to)); sec['Самомодификация (запись в байты кода)'].append(loc + f' — в коде {owner(to)}')
with open('docs/AUDIT.md', 'w', encoding='utf-8') as f:
    f.write('# Аудит кода оригинала для перевода на i8080\n\n'
            'Сгенерировано `tools/audit.py` из анализа Ghidra (`tools/ghidra.sh`) и `docs/symbols.txt`. '
            'Обращения к памяти — только явные (адрес в команде); косвенные через HL/DE здесь не видны.\n\n')
    f.write('| раздел | мест |\n|---|---|\n')
    for k, v in sec.items(): f.write(f'| {k} | {len(v)} |\n')
    for k, v in sec.items():
        f.write(f'\n## {k} ({len(v)})\n\n')
        for x in v: f.write(f'- {x}\n')
print('\n'.join(f'{k}: {len(v)}' for k, v in sec.items()))
