#!/usr/bin/env python3
"""Превью русских текстов по готовому образу (build/port/quaz_z80_ru.r0m): карточки частей пульта (cs_circuit:
имя 4067, строки 40A2/40E2, заметки 4882) и строки дроидов. ru_preview.py выход.png [части через запятую, по умолчанию все]"""
import sys
from PIL import Image, ImageDraw

m = open('build/port/quaz_z80_ru.r0m', 'rb').read()
L = {}
for l in open('build/port/glue.sld', encoding='latin-1'):
    p = l.split('|')
    if len(p) >= 8 and p[6] == 'L' and p[7].split(',')[1]: L.setdefault(p[7].split(',')[1], int(p[5]))
w = lambda a: m[a] | m[a + 1] << 8
FONT, OFF, SPLIT, TAB2 = 0x6DF9, w(L['ru_font_off']), m[L['msg_split']], w(L['msg_tab2'])

def nth(base, n):
    a = base
    for _ in range(n - 1): a += m[a] + 1
    return list(m[a + 1:a + 1 + m[a]])
msg = lambda n: nth(0x77C0, n) if n < SPLIT else nth(TAB2, n - SPLIT + 1)
comp = lambda n: nth(0x73B9, n)

class Scr:
    def __init__(s): s.im = Image.new('1', (256, 192)); s.px = s.im.load()
    def glyph(s, row, col, c):
        a = (FONT + c * 8 + (OFF if c >= 0xB8 else 0)) & 0xFFFF
        for r in range(8):
            for b in range(8):
                if 0 <= col < 32 and row < 24 and m[a + r] >> (7 - b) & 1: s.px[col * 8 + b, row * 8 + r] = 1
    def text(s, row, col, codes):
        c0 = col
        for c in codes:
            if c == 0xFF: row += 2; col = c0; continue
            s.glyph(row, col, c); col += 1
        return row, col
    def comp(s, row, col, n):
        c0 = col
        for it in comp(n):
            if it == 0x45: row += 2; col = c0; continue
            row, col = s.text(row, col, msg(it)); col += 1
            c0 = c0 if True else col
    def box(s):
        d = ImageDraw.Draw(s.im); d.rectangle((8 + 3, 8 + 3, 31 * 8 - 4, 18 * 8 - 4), outline=1)

parts = [int(x) for x in sys.argv[2].split(',')] if len(sys.argv) > 2 else [p for p in range(37) if p not in (24, 30)]
ims = []
for p in parts:
    s = Scr(); s.box(); b = 5 + 4 * p
    s.text(3, 2, msg(0x2A)); s.comp(3, 7, b); s.comp(5, 2, b + 1); s.text(5, 21, msg(0x2D)); s.comp(7, 2, b + 2)
    s.text(10, 2, msg(0x2C)); s.comp(12, 2, b + 3)
    ims.append(s.im.convert('RGB'))
cols = 3
sheet = Image.new('RGB', (cols * 264, ((len(ims) + cols - 1) // cols) * 200), (90, 90, 90))
for i, im in enumerate(ims): sheet.paste(im, ((i % cols) * 264 + 4, (i // cols) * 200 + 4))
sheet.save(sys.argv[1])
