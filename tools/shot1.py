#!/usr/bin/env python3
"""Один сырой кадр lockstep (QZ_LS_SHOTDIR) -> PNG с увеличением: shot1.py кадр.bin выход.png [масштаб]"""
import sys
from PIL import Image
b = open(sys.argv[1], 'rb').read(); k = int(sys.argv[3]) if len(sys.argv) > 3 else 3
pal = [((c & 7) * 255 // 7, (c >> 3 & 7) * 255 // 7, (c >> 6) * 255 // 3) for c in b[:16]]
im = Image.new('RGB', (256, 256)); px = im.load()
for col in range(32):
    for r in range(256):
        v, q = b[16 + col * 256 + r], b[16 + 0x2000 + col * 256 + r]
        for bit in range(8): px[col * 8 + bit, 255 - r] = pal[((v >> (7 - bit)) & 1) << 3 | ((q >> (7 - bit)) & 1)]
im.crop((0, 32, 256, 224)).resize((256 * k, 192 * k), Image.NEAREST).save(sys.argv[2])
