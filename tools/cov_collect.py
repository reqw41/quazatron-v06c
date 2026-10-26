#!/usr/bin/env python3
"""Сборщик покрытия из трассы MAME (файл или FIFO): уникальные PC -> файл (дописывает к существующему)."""
import sys
src, out = sys.argv[1], sys.argv[2]
seen = set()
try:
    seen = set(l.strip() for l in open(out) if l.strip())
except FileNotFoundError:
    pass
n0 = len(seen)
with open(src, 'rb') as f:
    for line in f:
        i = line.find(b',')
        pc = line[i+1:i+5]
        if len(pc) == 4 and pc not in seen:
            seen.add(pc)
seen = {s if isinstance(s, str) else s.decode() for s in seen}
seen = {s for s in seen if len(s) == 4 and all(c in '0123456789ABCDEF' for c in s)}
open(out, 'w').write('\n'.join(sorted(seen)) + '\n')
print(f'{src}: было {n0}, стало {len(seen)}')
