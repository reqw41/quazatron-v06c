#!/usr/bin/env python3
"""Таблицы с экранными адресами ZX: надписи (print_list B297) и прямоугольники атрибутов (attr_rects B5BC).
Ищет `ld hl,X` перед `call B297/B5BC` в коде (Ghidra), разбирает записи -> docs/TABLES.md."""
import re
code = []
for l in open('build/ghidra_code.txt'):
    a, n, t = l.rstrip().split(None, 2)
    code.append((int(a[4:], 16), t))
code.sort()
d = open('orig/zx/quazatron_ram.bin', 'rb').read()
b = lambda a: d[a - 0x4000]
def zx(a):
    if 0x5800 <= a < 0x5B00:
        o = a - 0x5800; return f'атр. ряд {o // 32} ст. {o % 32}'
    if 0x4000 <= a < 0x5800:
        o = a - 0x4000
        row = (o >> 11) * 8 + ((o >> 5) & 7); line = (o >> 8) & 7
        return f'ряд {row} ст. {o & 31}' + (f' стр. {line}' if line else '')
    return f'{a:04X}?'
tabs = {}
for i, (a, t) in enumerate(code):
    m = re.match(r'CALL 0x(b297|b5bc)$', t)
    if not m: continue
    for j in range(i - 1, max(i - 6, 0), -1):
        mm = re.match(r'LD HL,0x([0-9a-f]+)$', code[j][1])
        if mm: tabs.setdefault((int(mm[1], 16), m[1]), []).append(a); break
out = ['# Таблицы с экранными адресами ZX\n', 'Сгенерировано `tools/tables.py`. Адреса ZX переводятся в Вектор внутри '
       '`print_at`/`attr_rects`, таблицы не меняются.\n']
for (t, kind), sites in sorted(tabs.items()):
    out.append(f'\n## {t:04X} — {"надписи (print_list)" if kind == "b297" else "прямоугольники атрибутов (attr_rects)"}; '
               f'вызовы: {", ".join("%04X" % s for s in sites)}\n')
    a = t
    for _ in range(40):
        if b(a) == 0xFF: break
        if kind == 'b297':
            idx, ad, fl = b(a), b(a + 1) | (b(a + 2) & 0x7F) << 8, b(a + 2) & 0x80
            out.append(f'- строка {idx:02X}{" (составная)" if fl else ""} -> {ad:04X} ({zx(ad)})')
            a += 3
        else:
            w, h, ad, c = b(a), b(a + 1), b(a + 2) | b(a + 3) << 8, b(a + 4)
            out.append(f'- {w}x{h} -> {ad:04X} ({zx(ad)}), цвет {c:02X}')
            a += 5
open('docs/TABLES.md', 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print(len(tabs), 'таблиц')
