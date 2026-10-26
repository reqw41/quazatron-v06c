#!/usr/bin/env python3
"""Непокрытые участки кода по функциям: tools/cov_holes.py [функция|адрес ...] (без аргументов — все функции < 100%)."""
import glob, re, sys, bisect
ins = [int(l.split()[0][4:], 16) for l in open('build/ghidra_code.txt')]
cov = set()
for f in ['build/cov_pcs.txt'] + glob.glob('build/cov/cov_*.txt'):
    cov |= {int(l, 16) for l in open(f) if re.fullmatch(r'[0-9A-F]{4}', l.strip())}
syms = {}
for l in open('docs/symbols.txt', encoding='utf-8'):
    m = re.match(r'([0-9A-Fa-f]{4})\s+(\w+)', l)
    if m: syms[int(m[1], 16)] = m[2]
funcs = sorted(int(l.split()[0][4:], 16) for l in open('build/ghidra_funcs.txt'))
want = set()
for a in sys.argv[1:]:
    want |= {k for k, v in syms.items() if v == a} or {int(a, 16)}
holes = {}
for a in ins:
    if a in cov: continue
    f = funcs[bisect.bisect_right(funcs, a) - 1]
    holes.setdefault(f, []).append(a)
for f, lst in sorted(holes.items()):
    if want and f not in want: continue
    rng, s, p = [], lst[0], lst[0]
    for a in lst[1:]:
        if a - p > 4: rng.append((s, p)); s = a
        p = a
    rng.append((s, p))
    print(f'{f:04X} {syms.get(f, ""):14s} ' + ' '.join(f'{a:04X}-{b:04X}' for a, b in rng))
