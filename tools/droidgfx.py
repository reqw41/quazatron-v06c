#!/usr/bin/env python3
"""Графика дроидов t_droidgfx (A403, 96 указателей) -> build/droidgfx.png и сводка.
Формат изображения (blit_tile B07D): [число столбцов], затем на столбец: [dx со знаком, точки] [dy со знаком]
[режим|высота: б7 — стирание (and not), б6 — запись, иначе or; б0-5 — высота] [высота байт]. Столбец — 8 точек шириной."""
import sys
from PIL import Image, ImageDraw
img = open('orig/zx/quazatron_ram.bin', 'rb').read()
b = lambda a: img[a - 0x4000]; w = lambda a: b(a) | b(a + 1) << 8
sg = lambda v: v - 256 if v > 127 else v
def parse(p):
    n, cols, a = b(p), [], p + 1
    for _ in range(n):
        dx, dy, f = sg(b(a)), sg(b(a + 1)), b(a + 2); h = f & 0x3F
        cols.append((dx, dy, f >> 6, [b(a + 3 + i) for i in range(h)])); a += 3 + h
    return cols, a
def table(base=0xA403, n=96, out='build/droidgfx.png', title='t_droidgfx'):
    S, CW, CH = 3, 48, 64
    im = Image.new('RGB', (12 * CW * S, ((n + 11) // 12) * CH * S), (30, 30, 70)); d = ImageDraw.Draw(im)
    rows = []
    for i in range(n):
        p = w(base + 2 * i); cx, cy = (i % 12) * CW * S, (i // 12) * CH * S
        d.text((cx + 3, cy + 2), str(i + 1), fill=(255, 255, 0))
        if p == 0: rows.append((i + 1, 0, 0, 0)); continue
        cols, end = parse(p)
        ox, oy = cx + 24 * S, cy + 44 * S          # точка привязки
        d.line([ox - 2, oy, ox + 2, oy], fill=(255, 80, 80)); d.line([ox, oy - 2, ox, oy + 2], fill=(255, 80, 80))
        for dx, dy, mode, data in cols:
            colr = {0: (255, 255, 255), 1: (120, 255, 120), 2: (90, 90, 140), 3: (255, 120, 255)}[mode]
            for r, v in enumerate(data):
                for k in range(8):
                    if v & (0x80 >> k):
                        x, y = ox + (dx + k) * S, oy + (dy + r) * S
                        d.rectangle([x, y, x + S - 1, y + S - 1], fill=colr)
        rows.append((i + 1, p, len(cols), end - p))
    im.save(out)
    return rows
if __name__ == '__main__':
    for r in table(): print('%2d %04X столбцов %d байт %d' % r)
