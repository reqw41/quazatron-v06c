#!/usr/bin/env python3
"""Сырые кадры lockstep (QZ_LS_SHOTDIR) -> листы PNG. shots.py папка выход.png [фильтр: all|menu (in_game=0)] [в ряд] [масштаб]"""
import sys, os
from PIL import Image
d, out = sys.argv[1], sys.argv[2]
flt = sys.argv[3] if len(sys.argv) > 3 else 'all'
cols = int(sys.argv[4]) if len(sys.argv) > 4 else 4
fs = sorted(f for f in os.listdir(d) if f.endswith('.bin') and (flt == 'all' or f.endswith('_0.bin')))
def render(b):
    pal = [((c & 7) * 255 // 7, (c >> 3 & 7) * 255 // 7, (c >> 6) * 255 // 3) for c in b[:16]]
    im = Image.new('RGB', (256, 256)); px = im.load()
    for col in range(32):
        for r in range(256):
            v, k = b[16 + col * 256 + r], b[16 + 0x2000 + col * 256 + r]
            for bit in range(8):
                px[col * 8 + bit, 255 - r] = pal[((v >> (7 - bit)) & 1) << 3 | ((k >> (7 - bit)) & 1)]
    return im
ims, prev = [], None
for f in fs:
    b = open(os.path.join(d, f), 'rb').read()
    v = b[16:16 + 0x2000]
    if prev is not None and sum(1 for x, y in zip(v, prev) if x != y) < 300: continue
    prev = v; ims.append((f, render(b)))
rows = (len(ims) + cols - 1) // cols
sheet = Image.new('RGB', (cols * 260, rows * 270), (60, 60, 60))
from PIL import ImageDraw
dr = ImageDraw.Draw(sheet)
for i, (f, im) in enumerate(ims):
    x, y = (i % cols) * 260, (i // cols) * 270
    sheet.paste(im, (x + 2, y + 12)); dr.text((x + 2, y), f[:-4], fill=(255, 255, 0))
sheet.save(out); print(len(ims), 'кадров')
