#!/usr/bin/env python3
"""Итог tools/tempo.sh: темп по режимам (взвешенно по сценариям) и профиль тактов по участкам в каждом режиме.
  tools/tempo.py z80|80 [строк профиля]   (сборка i8080 — адреса через pcmap, добавки i8080.asm — по своим меткам)"""
import re, bisect, sys, glob, os
P = sys.argv[1]; TOP = int(sys.argv[2]) if len(sys.argv) > 2 else 12
RU = ''
acc = {}
for f in sorted(glob.glob(f'build/tempo/{P}_*.txt')):
    t = open(f, encoding='utf-8').read()
    for side in ('ZX', 'Вектор'):
        m = re.search(side + r': мини-игра ([\d.]+) кадра на ход \((\d+)\)', t)
        if m: a = acc.setdefault((side, 'мини-игра'), [0, 0]); a[0] += float(m[1]) * int(m[2]); a[1] += int(m[2])
        m = re.search(side + r': проход с прокруткой ([\d.]+) кадра \((\d+)\), без ([\d.]+) кадра \((\d+)\)', t)
        if m:
            for k, v, n in (('прокрутка', m[1], m[2]), ('ход', m[3], m[4])):
                a = acc.setdefault((side, k), [0, 0]); a[0] += float(v) * int(n); a[1] += int(n)
    for side in ('ZX', 'Вектор'):
        m = re.search(side + r': проход без прокрутки по числу объектов: (.*)', t)
        if m:
            for n, v, c in re.findall(r'(\d+): ([\d.]+) \((\d+)\)', m[1]):
                a = acc.setdefault((side, 'n' + n), [0, 0]); a[0] += float(v) * int(c); a[1] += int(c)
    if 'расхождений нет' not in t: print('!!', os.path.basename(f), 'с расхождением:', t.strip().split('\n')[-1][:200])
print(f'темп ({P}), кадров ТВ:      ZX     Вектор   ×')
for k in ('мини-игра', 'ход', 'прокрутка'):
    z, v = acc.get(('ZX', k), [0, 1]), acc.get(('Вектор', k), [0, 1])
    zz, vv = z[0] / max(z[1], 1), v[0] / max(v[1], 1)
    print(f'  {k:12s} (ходов/проходов {v[1]:5d}) {zz:6.2f} {vv:8.2f} {vv / zz if zz else 0:5.2f}')
for side in ('ZX', 'Вектор'):
    r = [f'{n}: {acc[(side, "n" + str(n))][0] / acc[(side, "n" + str(n))][1]:.3f} ({acc[(side, "n" + str(n))][1]})' for n in range(7) if (side, 'n' + str(n)) in acc]
    if r: print(f'  проход без прокрутки по числу объектов, {side}: ' + ', '.join(r))

s = {}
for l in open('docs/symbols.txt', encoding='utf-8'):
    m = re.match(r'([0-9A-Fa-f]{4})\s+(\w+)', l)
    if m: s[int(m[1], 16)] = m[2]
for l in open('build/port/glue.sld', encoding='latin-1'):
    p = l.split('|')
    if len(p) >= 8 and p[6] == 'L':
        n = p[7].split(',')[1]
        if n and '.' not in n and 0x100 <= int(p[5]) < 0x2000: s[int(p[5])] = 'glue:' + n
ks = sorted(s)
RL0, RL1, RLN = [int(x, 16) for x in open('build/port/reloc.txt').read().split()]
zxa = lambda a: a - RLN + RL0 if RLN <= a < RLN + RL1 - RL0 else a     # адрес образа -> адрес ZX (перенесённый блок)
name = lambda a: s[ks[bisect.bisect_right(ks, zxa(a)) - 1]]
if P == '80':
    pm = sorted((int(b, 16), int(a, 16)) for a, b in (l.split() for l in open('build/port8080/pcmap.txt')))
    pi = [x[0] for x in pm]
    XR = [int(x, 16) for x in open('build/port8080/layout.txt').read().split()]
    inX = lambda a: any(XR[k] <= a < XR[k + 1] for k in range(0, len(XR), 2))
    xl = {}
    for l in open('build/port8080/quaz_8080.sld', encoding='latin-1'):
        p = l.split('|')
        if len(p) >= 8 and p[6] == 'L':
            n = p[7].split(',')[1]; a = int(p[5])
            if n and '.' not in n and inX(a): xl[a] = 'x80:' + n
    xk = sorted(xl)
    vname = lambda a: xl[xk[bisect.bisect_right(xk, a) - 1]] if inX(a) else name(pm[bisect.bisect_right(pi, a) - 1][1])
else: vname = name
prof = {}
for f in glob.glob(f'build/tempo/{P}_*.prof'):
    for l in open(f):
        k, n = l.split()
        if k[0] == 'L': d = prof.setdefault('L' + k[1], {}); nm = vname(int(k[2:], 16) - 3); d[nm] = d.get(nm, 0) + int(n); continue
        m, a = k[0], int(k[1:], 16)
        d = prof.setdefault(m, {}); nm = vname(a); d[nm] = d.get(nm, 0) + int(n)
for m, title in (('x', 'мини-игра'), ('p', 'ход'), ('s', 'прокрутка')):
    d = prof.get(m, {}); tot = sum(d.values()) or 1
    print(f'профиль: {title}, всего {tot / 1e6:.0f} М тактов')
    for k, n in sorted(d.items(), key=lambda x: -x[1])[:TOP]: print(f'    {k:24s} {n / 1e6:8.1f} {100 * n / tot:5.1f}%')
    d = prof.get('L' + m)
    if d: print('    ldir/lddr, тыс. байт по месту вызова: ' + ', '.join(f'{k} {n / 1e3:.0f}' for k, n in sorted(d.items(), key=lambda x: -x[1])[:8]))
