#!/usr/bin/env python3
"""Образ с 16-цветной заставкой: игра (.r0m) + картинка -> .r0m, где на время заставки игра сжата.

    python3 tools/mk_splash.py игра.r0m выход.r0m [картинка.png]   (картинка по умолчанию — src/splash/title_c2.png)

Картинка 256 x 256 (весь экран) или 256 x 192 (по центру), не больше 16 цветов, среди них чёрный (индекс 0 — бордюр
и строки вне картинки). Каждый цвет приводится к сетке Вектора (R, G — 8 уровней, B — 4). Плоскости: точка (x, y) —
байт база + (x >> 3) * 256 + Y0 − y (Y0 = 255 или 223),
бит 7 − (x & 7); индекс палитры = p0 << 3 | p1 << 2 | p2 << 1 | p3 (p0 — плоскость 8000).
Игра: 8000-9FFF и E000-FFFF в образе — нули (проверяется); поток U — A000-DFFF, поток L — 0000-7FFF (zx0 -c, classic);
L лежит так, что кончается на delta байт за 8000; там точки картинки — эти байты хранит ступень 2 и кладёт на место
перед распаковкой L.
Распаковка проверяется моделью по адресам: запись не попадает в непрочитанный байт потока, итог 0000-7FFF и
A000-DFFF — байт в байт игра, E000-FFFF — нули. Код заставки — port/splash.asm."""
import hashlib, os, re, subprocess, sys
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
GAME, OUT = sys.argv[1], sys.argv[2]
PIC = sys.argv[3] if len(sys.argv) > 3 else os.path.join(ROOT, 'src', 'splash', 'title_c2_256.png')
BLD = os.path.join(ROOT, 'build', 'splash'); os.makedirs(BLD, exist_ok=True)
ZX0 = os.path.join(ROOT, 'build', 'zx0')
SJ = os.environ.get('SJASMPLUS', os.path.abspath('tools/sjasmplus'))
S2 = 0x9F00                                                    # ступень 2 (плоскость 0, её чистит загрузчик игры)

if not os.path.exists(ZX0):
    src = [os.path.join(ROOT, 'tools', 'zx0', f) for f in ('zx0.c', 'compress.c', 'optimize.c', 'memory.c')]
    subprocess.run(['cc', '-O2', '-o', ZX0] + src, check=True)

def zx0(data, tag):
    h = hashlib.md5(data).hexdigest(); cz = os.path.join(BLD, h + '.zx0'); cd = cz + '.delta'
    if not os.path.exists(cd):
        src = os.path.join(BLD, h + '.bin'); open(src, 'wb').write(data)
        r = subprocess.run([ZX0, '-f', '-c', src, cz], capture_output=True, text=True)
        m = re.search(r'delta (\d+)', r.stdout)
        if r.returncode or not m: sys.exit(f'zx0 ({tag}): {r.stdout}{r.stderr}')
        open(cd, 'w').write(m.group(1)); os.remove(src)
    return open(cz, 'rb').read(), int(open(cd).read())

def dzx0_model(comp, src_at, dst_at, mem):
    """распаковка classic по адресам в mem (порядок чтений — как у dzx0 Городецкого); -> (длина, нарушений)"""
    ip = [0]; viol = [0]; n = [0]
    def rd():
        b = mem[src_at + ip[0]]; ip[0] += 1; return b
    st = {'mask': 0, 'bt': False, 'val': 0, 'last': 0}
    def bit():
        if st['bt']: st['bt'] = False; return st['last'] & 1
        st['mask'] >>= 1
        if st['mask'] == 0: st['mask'] = 128; st['val'] = rd()
        return 1 if st['val'] & st['mask'] else 0
    def gamma():
        v = 1
        while not bit(): v = (v << 1) | bit()
        return v
    def put(v):
        a = dst_at + n[0]
        if src_at + ip[0] <= a < src_at + len(comp): viol[0] += 1
        mem[a] = v; n[0] += 1
    last, state = 1, 'lit'
    while True:
        if state == 'lit':
            for _ in range(gamma()): put(rd())
            state = 'new' if bit() else 'rep'
        elif state == 'rep':
            for _ in range(gamma()): put(mem[dst_at + n[0] - last])
            state = 'lit' if not bit() else 'new'
        else:
            msb = gamma()
            if msb == 256: break
            b = rd(); last = msb * 128 - (b >> 1); st['bt'], st['last'] = True, b
            for _ in range(gamma() + 1): put(mem[dst_at + n[0] - last])
            state = 'new' if bit() else 'lit'
    assert ip[0] == len(comp), 'поток прочитан не целиком'
    return n[0], viol[0]

game = open(GAME, 'rb').read(); assert len(game) == 0x10000
assert not any(game[0x8000:0xA000]) and not any(game[0xE000:]), 'в образе игры плоскости 8000/E000 не нулевые'

# ---- картинка -> плоскости и палитра ----
LV = [round(i * 255 / 7) for i in range(8)]; LB = [0, 85, 170, 255]
snap = lambda c: (min(LV, key=lambda v: abs(v - c[0])), min(LV, key=lambda v: abs(v - c[1])), min(LB, key=lambda v: abs(v - c[2])))
im = Image.open(PIC).convert('RGB'); assert im.size in ((256, 192), (256, 256)), im.size
PH = im.size[1]; Y0 = 255 if PH == 256 else 223
px = [[snap(im.getpixel((x, y))) for x in range(256)] for y in range(PH)]
cols = sorted({c for row in px for c in row}, key=lambda c: (c != (0, 0, 0), c))
assert cols[0] == (0, 0, 0), 'в картинке нет чёрного'; assert len(cols) <= 16, f'цветов {len(cols)}'
idx = {c: i for i, c in enumerate(cols)}
pal = bytes(LB.index(c[2]) << 6 | LV.index(c[1]) << 3 | LV.index(c[0]) for c in cols) + bytes(16 - len(cols))
planes = bytearray(0x8000)
for y in range(PH):
    for x in range(256):
        i = idx[px[y][x]]
        for p in range(4):
            if i >> (3 - p) & 1: planes[p * 0x2000 + (x >> 3) * 256 + Y0 - y] |= 0x80 >> (x & 7)

# ---- потоки игры ----
U, _ = zx0(game[0xA000:0xE000], 'U')
L, dL = zx0(game[0:0x8000], 'L')
assert 0 < dL <= 64, f'delta {dL}'
L_AT = 0x8000 + dL - len(L)
CODE_MAX = 0x0400                                              # код заставки и стек — до 0400
U_AT = L_AT - len(U)
assert U_AT >= CODE_MAX, f'не влезает: U с {U_AT:04X}'
print(f'{os.path.basename(GAME)}: U {len(U)} Б с {U_AT:04X}, L {len(L)} Б с {L_AT:04X} (delta {dL}), свободно {U_AT - CODE_MAX} Б, цветов {len(cols)}')

# ---- сборка кода заставки ----
open(os.path.join(BLD, 'pal.bin'), 'wb').write(pal); open(os.path.join(BLD, 'u.bin'), 'wb').write(U)
open(os.path.join(BLD, 'l.bin'), 'wb').write(L[:len(L) - dL]); open(os.path.join(BLD, 'tail.bin'), 'wb').write(L[len(L) - dL:] + b'\0')
asm = open(os.path.join(ROOT, 'port', 'splash.asm'), encoding='utf-8').read()
for k, v in (('"SPL_PAL"', '"pal.bin"'), ('"SPL_UBIN"', '"u.bin"'), ('"SPL_LBIN"', '"l.bin"'), ('"SPL_OUT"', '"lower.bin"'), ('"SPL_TAIL"', '"tail.bin"')):
    asm = asm.replace(k, v)
asm = f'SPL_S2\tequ\t0x{S2:04X}\nSPL_U\tequ\t0x{U_AT:04X}\nSPL_L\tequ\t0x{L_AT:04X}\nSPL_DELTA\tequ\t{dL}\n' + asm
open(os.path.join(BLD, 'splash.asm'), 'w', encoding='utf-8').write(asm)
r = subprocess.run([SJ, '--nologo', '--msg=war', '--sld=splash.sld', 'splash.asm'], cwd=BLD, capture_output=True, text=True)
if r.returncode: sys.exit('sjasmplus: ' + r.stdout + r.stderr)
lower = open(os.path.join(BLD, 'lower.bin'), 'rb').read()
code_end = [int(l.split('|')[5]) for l in open(os.path.join(BLD, 'splash.sld'), encoding='latin-1')
            if l.split('|')[6:7] == ['L'] and ',spl_code_end,' in l][0]
assert code_end <= CODE_MAX, f'код заставки до {code_end:04X}'

assert len(lower) == 0x8000, len(lower)
out = bytearray(0x10000); out[0x8000:] = planes; out[:0x8000] = lower

# ---- проверка распаковки моделью ----
m = bytearray(out)
n, v = dzx0_model(U, U_AT, 0xA000, m); assert n == 0x4000 and v == 0
m[0xE000:] = bytes(0x2000)
m[0x8000:0x8000 + dL] = L[len(L) - dL:]                      # хвост потока L — ступень 2 кладёт его на место
n, v = dzx0_model(L, L_AT, 0, m); assert n == 0x8000, n
assert v == 0, f'распаковка L на месте: {v} записей в непрочитанный поток'
assert m[0:0x8000] == game[0:0x8000] and m[0xA000:] == game[0xA000:], 'итог распаковки не равен игре'
open(OUT, 'wb').write(out)
pv = Image.new('RGB', (256, PH)); pp = pv.load()
for y in range(PH):
    for x in range(256):
        i = 0
        for p in range(4): i = i << 1 | (planes[p * 0x2000 + (x >> 3) * 256 + Y0 - y] >> (7 - (x & 7)) & 1)
        c = pal[i]; pp[x, y] = (LV[c & 7], LV[c >> 3 & 7], LB[c >> 6])
pv.resize((512, PH * 2), Image.NEAREST).save(os.path.join(BLD, 'preview.png'))
print(f'{OUT}: модель распаковки — совпадает с игрой; превью build/splash/preview.png')
