#!/usr/bin/env python3
"""Кусок листинга build/quaz.asm по адресам: tools/lst.py A000 A100 (компактно, команда | команда)."""
import re, sys
a0, a1 = int(sys.argv[1], 16), int(sys.argv[2], 16)
out, lab = [], None
for l in open('build/quaz.asm', encoding='latin-1'):
    m = re.search(r';([0-9a-f]{4})\s*$', l)
    if re.match(r'^\w+:', l): lab = l.split(':')[0]; continue
    if not m: continue
    a = int(m[1], 16)
    if a0 <= a <= a1:
        if lab: out.append(lab + ':'); lab = None
        out.append(l.split(';')[0].strip())
    else: lab = None
print(' | '.join(out))
