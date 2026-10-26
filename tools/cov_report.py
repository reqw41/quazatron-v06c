#!/usr/bin/env python3
"""Покрытие по функциям: доля команд (по Ghidra), исполненных хоть раз во всех трассах.
Источники: build/ghidra_code.txt, build/ghidra_funcs.txt, build/cov_pcs.txt, build/cov/cov_*.txt, docs/symbols.txt."""
import glob, re, bisect
ins = [int(l.split()[0][4:], 16) for l in open('build/ghidra_code.txt')]
cov = set()
for f in ['build/cov_pcs.txt'] + glob.glob('build/cov/cov_*.txt'):
    cov |= {int(l, 16) for l in open(f) if re.fullmatch(r'[0-9A-F]{4}', l.strip())}
syms = {}
for l in open('docs/symbols.txt', encoding='utf-8'):
    m = re.match(r'([0-9A-Fa-f]{4})\s+(\w+)', l)
    if m: syms[int(m[1], 16)] = m[2]
funcs = sorted(int(l.split()[0][4:], 16) for l in open('build/ghidra_funcs.txt'))
st = {f: [0, 0] for f in funcs}
for a in ins:
    i = bisect.bisect_right(funcs, a) - 1
    if i < 0: continue
    st[funcs[i]][1] += 1
    if a in cov: st[funcs[i]][0] += 1
tot = sum(v[1] for v in st.values()); hit = sum(v[0] for v in st.values())
print(f'команд {tot}, исполнено {hit} ({100 * hit / tot:.0f}%); адресов в трассах {len(cov)}')
for f in funcs:
    h, n = st[f]
    if n and h < n:
        print(f'  {f:04X} {syms.get(f, ""):16s} {h:4d}/{n:<4d} {100 * h / n:4.0f}%')
