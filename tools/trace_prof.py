#!/usr/bin/env python3
"""Профиль трассы MAME (строки "такты,PC: дизасм"): исключающие такты по процедурам.
Процедура = ближайшая снизу цель call (цели собираются из самой трассы).
  python3 tools/trace_prof.py zx-stand/prof.tr [топ=30]"""
import sys, re, bisect
from collections import Counter
fn = sys.argv[1]; top = int(sys.argv[2]) if len(sys.argv) > 2 else 30
rows = []
targets = set()
for line in open(fn, encoding='latin-1'):
    m = re.match(r'(\d+),([0-9A-F]{4}): (.*)', line)
    if not m: continue
    t, pc, ins = int(m[1]), int(m[2], 16), m[3]
    rows.append((t, pc))
    c = re.match(r'call\s+(?:\w+,)?\$([0-9A-F]{4})', ins)
    if c: targets.add(int(c[1], 16))
tg = sorted(targets)
cyc = Counter(); pcs = Counter()
for (t, pc), (t2, _) in zip(rows, rows[1:]):
    d = t2 - t
    if d > 200: continue                    # разрывы (прерывание вне трассы, конец кадра)
    i = bisect.bisect_right(tg, pc) - 1
    f = tg[i] if i >= 0 else 0
    cyc[f] += d; pcs[pc] += d
total = sum(cyc.values())
print(f'всего {total} тактов, {rows[-1][0]-rows[0][0]} по часам, {len(rows)} команд')
for f, c in cyc.most_common(top):
    print(f'{f:04X} {c:9d} {100*c/total:5.1f}%')
# горячие участки: подряд идущие PC (разрыв < 16 байт) одним блоком
print('--- участки')
blk = []
for pc in sorted(pcs):
    if blk and pc - blk[-1][1] < 16: blk[-1][1] = pc; blk[-1][2] += pcs[pc]
    else: blk.append([pc, pc, pcs[pc]])
for a, b, c in sorted(blk, key=lambda x: -x[2])[:top]:
    print(f'{a:04X}-{b:04X} {c:9d} {100*c/total:5.1f}%')
