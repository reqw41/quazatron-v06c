#!/usr/bin/env python3
"""Разбор TZX: стандартные блоки (0x10) -> orig/zx/blocks/NN_<тип>.bin (без флага и контрольной суммы)."""
import sys, os
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
d = open(src, 'rb').read()
p, i = 10, 0
while p < len(d):
    t = d[p]
    if t == 0x10:
        n = d[p+3] | d[p+4] << 8; b = d[p+5:p+5+n]; p += 5 + n
        kind = 'hdr' if b[0] == 0 else 'data'
        body = b[1:-1]
        fn = f'{i:02d}_{kind}.bin'
        open(os.path.join(out, fn), 'wb').write(body)
        x = 0
        for c in b: x ^= c
        extra = ''
        if kind == 'hdr':
            extra = f"type={body[0]} name={body[1:11].decode('latin1')!r} len={body[11]|body[12]<<8} p1={body[13]|body[14]<<8} p2={body[15]|body[16]<<8}"
        print(f'{fn} flag={b[0]:02X} len={len(body)} xor_ok={x==0} {extra}')
        i += 1
    elif t == 0x30: p += 2 + d[p+1]
    elif t == 0x32: p += 3 + (d[p+1] | d[p+2] << 8)
    elif t == 0x20: p += 3
    else: sys.exit(f'неизвестный блок {t:#x} @ {p:#x}')
