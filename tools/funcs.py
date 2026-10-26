#!/usr/bin/env python3
"""Оглавление кода -> docs/FUNCS.md: каждое имя кода из symbols.txt — участок до следующего имени кода,
размер, покрытие трассами, кто вызывает (call/jp/jr с других участков), что вызывает, комментарий."""
import glob, re
syms, com = {}, {}
for l in open('docs/symbols.txt', encoding='utf-8'):
    m = re.match(r'([0-9A-Fa-f]{4})\s+(\w+)\s*(?:;\s*(.*))?', l)
    if m: syms[int(m[1], 16)] = m[2]; com[int(m[1], 16)] = m[3] or ''
code = set()
for l in open('build/blocks.txt'):
    m = re.match(r'b\d+: start 0x(\w+) end 0x(\w+) type code', l)
    if m: code |= set(range(int(m[1], 16), int(m[2], 16)))
ins = sorted(int(l.split()[0][4:], 16) for l in open('build/ghidra_code.txt'))
cov = set()
for f in ['build/cov_pcs.txt'] + glob.glob('build/cov/cov_*.txt'):
    cov |= {int(l, 16) for l in open(f) if re.fullmatch(r'[0-9A-F]{4}', l.strip())}
heads = sorted(a for a in syms if a in code)
byname = {v: k for k, v in syms.items()}
def region(a):
    import bisect
    i = bisect.bisect_right(heads, a) - 1
    return heads[i] if i >= 0 else None
calls = {h: set() for h in heads}; callers = {h: set() for h in heads}
for l in open('build/quaz.asm', encoding='latin-1'):
    m = re.match(r'\s+(call|jp|jr|djnz)\s+(?:\w+,)?(\w+)\s*;([0-9a-f]{4})', l)
    if not m: continue
    tgt = byname.get(m[2])
    if tgt is None and re.fullmatch(r'l[0-9a-f]{4}h', m[2]): tgt = int(m[2][1:5], 16)
    if tgt is None: continue
    src = region(int(m[3], 16)); dst = region(tgt) if tgt in code else None
    if src is None or dst is None or src == dst: continue
    if m[1] == 'call' or tgt in heads:
        calls[src].add(dst); callers[dst].add(src)
out = ['# Оглавление кода (сгенерировано `tools/funcs.py`)\n',
       'Участок — от имени кода до следующего имени. Покрытие — доля команд (по Ghidra), исполненных в трассах MAME.\n',
       '| адрес | имя | байт | покрытие | вызывают | вызывает | описание |', '|---|---|---|---|---|---|---|']
tot = hit = 0
for i, h in enumerate(heads):
    e = heads[i + 1] if i + 1 < len(heads) else 0xEE91
    n = [a for a in ins if h <= a < e]; c = sum(a in cov for a in n); tot += len(n); hit += c
    pc = f'{100 * c // len(n)}%' if n else '—'
    nm = lambda s: ', '.join(sorted(syms[x] for x in s))
    out.append(f'| {h:04X} | `{syms[h]}` | {e - h} | {pc} | {nm(callers[h])} | {nm(calls[h])} | {com[h].replace("|", "/")} |')
out.insert(2, f'Всего участков {len(heads)}, команд {tot}, исполнено {hit} ({100 * hit / tot:.1f}%).\n')
open('docs/FUNCS.md', 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print(f'участков {len(heads)}, покрытие {100 * hit / tot:.1f}%')
