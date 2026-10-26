#!/usr/bin/env python3
"""Вырезка поддерева отрисовки палубы (BE38 и вызываемые) из образа ZX и перевод Z80 -> i8080
ядром переводчика King's Valley (kv_z80_to_8080.translate).
Выход: build/demo/render_8080.asm (переведённый код) + build/demo/render_z80.asm (исходник среза).
B07D (вывод столбцов плитки) сюда НЕ входит — он написан вручную в demo/blit.asm."""
import os, re, subprocess, sys
KV = os.path.expanduser('~/projects/kvalley-v06c/tools')
sys.path.insert(0, KV)
import kv_z80_to_8080 as kv

# тела функций по Ghidra (build/ghidra_funcs.txt), включительно
BODIES = [(0xB4F1, 0xB5A2), (0xBE08, 0xC043),  # C044 (заливка полосы) — vecout.asm
          (0xC12B, 0xC1A4)]  # C1A5 (полоса -> буфер) заменён vecout.asm
LO, HI = 0xB000, 0xC2FF
os.makedirs('build/demo', exist_ok=True)
img = open('orig/zx/quazatron_ram.bin', 'rb').read()
open('build/demo/slice.bin', 'wb').write(img[LO - 0x4000:HI + 1 - 0x4000])
with open('build/demo/blocks.txt', 'w') as f:
    cur, i = LO, 0
    for a, b in BODIES:
        if a > cur: f.write(f'd{i}: start 0x{cur:04x} end 0x{a:04x} type bytedata\n'); i += 1
        f.write(f'c{i}: start 0x{a:04x} end 0x{b+1:04x} type code\n'); i += 1
        cur = b + 1
    f.write(f'd{i}: start 0x{cur:04x} end 0x{HI+1:04x} type bytedata\n')
subprocess.run(f'z80dasm -a -l -g 0x{LO:04x} -b build/demo/blocks.txt -o build/demo/slice.asm build/demo/slice.bin',
               shell=True, check=True, stderr=subprocess.DEVNULL)

# метки границ блоков (cN_start, dN_end, ...) -> sub_XXXXh по адресу
raw = open('build/demo/slice.asm').read()
bnd = {}
for nm, a, b in re.findall(r"; BLOCK '(\w+)' \(start 0x([0-9a-f]+) end 0x([0-9a-f]+)\)", raw):
    bnd[nm + '_start'] = int(a, 16); bnd[nm + '_end'] = int(b, 16)
raw = re.sub(r'\b([cd]\d+_(?:start|end))\b', lambda m: f'sub_{bnd[m[1]]:04x}h', raw)
open('build/demo/slice.asm', 'w').write(raw)
# оставить только строки кода внутри BODIES (адрес берём из комментария ;xxxx, которого без -a нет —
# поэтому идём по блокам: z80dasm пишет "; BLOCK 'cN'" перед каждым блоком)
out, keep = [], False
for line in open('build/demo/slice.asm'):
    m = re.match(r"; BLOCK '(\w+)'", line)
    if m: keep = m[1].startswith('c'); out.append(line.rstrip()); continue
    if not keep and re.match(r'^\w+:', line): continue
    if keep and not line.startswith(';') and line.strip() and not re.match(r'\s*org\b', line):
        out.append(line.rstrip())
# метки концов блоков (sub_XXXXh на адресе конца кода) — не наши, убрать; входы без ссылок — добавить
ends = {v for k, v in bnd.items() if k.endswith('_end')}
starts = {a for a, b in BODIES}
ENTRIES = [0xBE38]
res = []
for l in out:
    m = re.match(r'^sub_([0-9a-f]{4})h:$', l)
    if m and int(m[1], 16) in ends and int(m[1], 16) not in starts: continue
    m = re.search(r';([0-9a-f]{4})\b', l)
    if m and int(m[1], 16) in ENTRIES and f'sub_{m[1]}h:' not in res: res.append(f'sub_{m[1]}h:')
    res.append(re.sub(r'\t+;[0-9a-f]{4}\b.*$', '', l))
src = '\n'.join(res) + '\n'
open('build/demo/render_z80.asm', 'w').write(src)

# Ручные замены в исходнике Z80 до перевода (старое -> новое, ровно одно вхождение)
PATCHES = [
    # BE38: буфер-полоса — раскладкой Вектора на 4 страницах (demo: STRIP), а не 4 байта на строку в 0x8080
    ('\tld hl,08080h\n', '\tld hl,05800h\n'),
    # BEF1: адрес клетки карты 16x16 перестановкой бит через rl/rr e (в переводе — длинные цепочки).
    # Проверено перебором d,e = 0..63: индекс = (d & 0x3C) << 2 | e >> 2, старший байт 0.
    ('lbef1h:\n\trra\n\trra\n\trl e\n\trl e\n\trra\n\trr e\n\trra\n\trr e\n\trra\n\trr e\n\trra\n\trr e\n\tand 001h\n\tld d,a\n',
     'lbef1h:\n\tand 03ch\n\tadd a,a\n\tadd a,a\n\tld d,a\n\tld a,e\n\trrca\n\trrca\n\tand 00fh\n\tor d\n\tld e,a\n\tld d,000h\n'),
]
for old, new in PATCHES:
    n = src.count(old)
    if n != 1: sys.exit(f'замена не применилась ({n} вхождений): {old[:40]!r}')
    src = src.replace(old, new)
open('build/demo/render_z80.asm', 'w').write(src)

defined = set(re.findall(r'^(\w+):', src, re.M))
used = set(re.findall(r'\b((?:sub_|l)[0-9a-f]{4}h)\b', src))
ext = sorted(used - defined)
codezones = [(0x61A9, 0x6200), (0xB07D, 0xB1E5), (0xB1E6, 0xBDFC), (0xC05A, 0xC12A), (0xC20D, 0xE6FF)]
bad = []
eq = []
for name in ext:
    a = int(re.search(r'([0-9a-f]{4})h$', name)[1], 16)
    if name in ('sub_b07dh', 'sub_c1a5h', 'sub_c044h'): continue  # ручные: blit.asm, vecout.asm
    # переход/вызов в непереведённый код — ошибка
    if re.search(rf'\b(call|jp|jr|djnz)\b[^;\n]*\b{name}\b', src): bad.append(name)
    eq.append(f'{name}:\tequ 0x{a:04x}')
if bad: sys.exit('переходы в непереведённый код: ' + ', '.join(bad))
pre = kv._classify_exx(src)[0] if hasattr(kv, '_classify_exx') else src
tr = kv.translate(pre)
hdr = '; СГЕНЕРИРОВАНО demo/extract.py — не править руками\n'
open('build/demo/render_8080.asm', 'w').write(hdr + '\n'.join(eq) + '\n\n' + tr + '\n' + kv._LDIR_HELPERS)
print(f'срез: {len(src.splitlines())} строк Z80, внешних меток {len(eq)}')
