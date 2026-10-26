#!/usr/bin/env python3
"""Профиль стенда порта: tools/port_prof.py build/port/X.pcstat — такты по участкам (имена игры и склейки)."""
import re, bisect, sys
s = {}
for l in open('docs/symbols.txt', encoding='utf-8'):
    m = re.match(r'([0-9A-Fa-f]{4})\s+(\w+)', l)
    if m: s[int(m[1], 16)] = m[2]
for l in open('build/port/glue.sld', encoding='latin-1'):
    p = l.split('|')
    if len(p) >= 8 and p[6] == 'L':
        n = p[7].split(',')[1]
        if n and '.' not in n: s[int(p[5])] = 'glue:' + n
ks = sorted(s); agg = {}; tot = 0
for l in open(sys.argv[1]):
    a, n = l.split(); a = int(a, 16); n = int(n); tot += n
    k = ks[bisect.bisect_right(ks, a) - 1]; agg[s[k]] = agg.get(s[k], 0) + n
for k, v in sorted(agg.items(), key=lambda x: -x[1])[:int(sys.argv[2]) if len(sys.argv) > 2 else 20]:
    print(f'{k:20s} {v:10d} {100 * v / tot:5.1f}%')
print('всего', tot)
