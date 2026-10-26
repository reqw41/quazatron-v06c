#!/usr/bin/env python3
"""Оригинал и перевод рядом -> docs/TRANSLATION.md: сообщения t_msgs и составные строки p_strcomp образа ZX
против port/ru/text.py (MSG, COMP с частями).   python3 tools/translation_table.py"""
import importlib.util
d = open('orig/zx/quazatron_ram.bin', 'rb').read(); b = lambda a: d[a - 0x4000]; w = lambda a: b(a) | b(a + 1) << 8
def ch(c):
    if c < 10: return chr(48 + c)
    if c < 0x24: return chr(55 + c)
    if c in (0x24, 0x25): return ' '
    if c == 0xFF: return ' / '
    if c in (0x26, 0x28): return ''
    return '{%02X}' % c
def lst(base, n):
    out, a = [], base
    for i in range(n):
        L = b(a); out.append(''.join(ch(b(a + 1 + k)) for k in range(L))); a += L + 1
    return out
msgs = lst(0x77C0, 0xE2)
comps, a = [], w(0x61BE)
for i in range(0x9F):
    n = b(a); ids = [b(a + 1 + k) for k in range(n)]; a += n + 1
    comps.append(' '.join(msgs[m - 1].strip() if m != 0x45 else '/' for m in ids).replace(' / ', ' / '))
spec = importlib.util.spec_from_file_location('t', 'port/ru/text.py'); T = importlib.util.module_from_spec(spec); spec.loader.exec_module(T)
md = ['# Перевод: оригинал и русский\n', 'Собрано `tools/translation_table.py` из образа ZX (t_msgs, p_strcomp) и `port/ru/text.py`.\n',
      '| что | английский | русский |', '|---|---|---|']
for k in sorted(T.MSG): md.append('| сообщение %02X | `%s` | `%s` |' % (k, msgs[k - 1].strip(), T.MSG[k].replace('\n', ' / ')))
for k in sorted(T.COMP): md.append('| составная %02X | `%s` | `%s` |' % (k, comps[k - 1], T.COMP[k].replace('\n', ' / ')))
open('docs/TRANSLATION.md', 'w', encoding='utf-8').write('\n'.join(md) + '\n')
print(len(md) - 4, 'строк')
