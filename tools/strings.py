#!/usr/bin/env python3
"""Строки игры -> docs/STRINGS.md. Кодировка шрифта: 00-09 цифры, 0A-23 A-Z, 24 пробел?, 25 пробел; прочее — {xx}.
Списки: t_msgs (77C0, msg_find, индекс с 1) и t_strtab2 (69C5, str_find2, индекс & 0x7F с 1). Запись: [длина][коды], FF — перевод строки."""
d = open('orig/zx/quazatron_ram.bin', 'rb').read()
b = lambda a: d[a - 0x4000]
def ch(c):
    if c < 10: return chr(48 + c)
    if c < 0x24: return chr(55 + c)
    if c in (0x24, 0x25): return ' '
    if c == 0xFF: return '⏎'
    if c in (0x26, 0x28): return ''          # правая половина широких M (16+26) и W (20+28)
    return '{%02X}' % c
def lst(base, n):
    out, a = [], base
    for i in range(1, n + 1):
        L = b(a)
        out.append((i, a, ''.join(ch(b(a + 1 + k)) for k in range(L))))
        a += L + 1
    return out
md = ['# Строки игры\n', 'Сгенерировано `tools/strings.py`. Коды шрифта: 00-09 цифры, 0A-23 A-Z, 24/25 пробел, M и W — по два знака (16+26, 20+28), прочие — `{xx}`.\n']
for title, base, n in [('t_msgs (77C0) — msg_find, номер A с 1 (до E2)', 0x77C0, 0xE2), ('t_strtab2 (69C5) — str_find2, номер (A & 0x7F) с 1: псевдографика рамок и панели (до 21)', 0x69C5, 0x21)]:
    md.append(f'\n## {title}\n\n| № | адрес | текст |\n|---|---|---|')
    for i, a, t in lst(base, n):
        md.append(f'| {i:02X} | {a:04X} | `{t}` |')
open('docs/STRINGS.md', 'w', encoding='utf-8').write('\n'.join(md) + '\n')
