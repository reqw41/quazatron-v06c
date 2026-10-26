#!/usr/bin/env python3
"""Кадр Вектора из tools/vsnap.js (QZ_VS_RAW): палитра io.Palette + 4 плоскости -> PNG. vraw_png.py кадр.raw выход.png [масштаб]"""
import sys, struct
from PIL import Image
b = open(sys.argv[1], 'rb').read(); k = int(sys.argv[3]) if len(sys.argv) > 3 else 2
pal = []
for i in range(16):
    v = struct.unpack_from('<I', b, i * 4)[0]
    pal.append((v & 0xFF, v >> 8 & 0xFF, v >> 16 & 0xFF))
im = Image.new('RGB', (256, 256)); px = im.load()
for col in range(32):
    for r in range(256):
        p = [b[64 + pl * 0x2000 + col * 256 + r] for pl in range(4)]
        for bit in range(8):
            m = 7 - bit
            idx = (p[0] >> m & 1) << 3 | (p[1] >> m & 1) << 2 | (p[2] >> m & 1) << 1 | (p[3] >> m & 1)
            px[col * 8 + bit, 255 - r] = pal[idx]
im.resize((256 * k, 256 * k), Image.NEAREST).save(sys.argv[2])
