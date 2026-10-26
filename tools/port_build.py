#!/usr/bin/env python3
"""Порт Quazatron на Вектор-06Ц с Z80 (этап 1, docs/PLAN.md): build/port/quaz_z80.r0m (64 КБ, старт с 0x0000).
Берёт образ ОЗУ ZX после загрузки (orig/zx/quazatron_ram.bin, 4000-FFFF), правит его побайтово со сверкой исходных байтов
и собирает с склейкой port/glue.asm (0000-1FFF, копия ПЗУ ZX с 0x1000).
  окно 8000-9FFF -> 2000-3FFF (−0x6000): 21 операнд в коде + указатели t_deckgfx;
  im 2 -> im 1 (на Векторе только кадровое RST 38h);
  rnd и пульт читают копию ПЗУ ZX с 0x1000;
  out (0FEh),a -> rst 08h; in a,(c) -> rst 10h (ввод-вывод ZX через склейку).
Опции: --detector — исправление ошибки оригинала (DETECTOR в лифте читает t_deckdroids)."""
import hashlib, os, subprocess, sys, zipfile
ZXROM_MD5 = "5ba5b72af463925b1cf3dd91c240192b"   # ПЗУ ZX 48K (Sinclair), 0000-052F
LO = 0x4000
img = bytearray(open('orig/zx/quazatron_ram.bin', 'rb').read())   # 4000-FFFF
OFF = 0x6000
mem = bytearray(0x10000)
mem[LO:] = img
log = []

def rb(a): return mem[a]
def rw(a): return mem[a] | mem[a + 1] << 8
def patch(a, old, new, why):
    old, new = bytes(old), bytes(new)
    if mem[a:a + len(old)] != old:
        sys.exit(f'{a:04X} {why}: ждали {old.hex()}, в образе {mem[a:a + len(old)].hex()}')
    mem[a:a + len(new)] = new
    log.append(f'{a:04X} {old.hex():>12} -> {new.hex():<12} {why}')

# --- окно 8000-9FFF -> 2000-3FFF ---
WIN = [0xBE38, 0xBE42, 0xC05A, 0xC07D, 0xC0A0, 0xC1B7, 0xC241, 0xD971, 0xDE83, 0xDE8B, 0xDEE1, 0xDF6C,
       0xE10E, 0xE111, 0xE11D, 0xE120, 0xE12C, 0xE12F, 0xE146, 0xE149, 0xE3DA]   # ld rr,nn (D407 — счётчик, не адрес)
for a in WIN:
    op, v = mem[a], rw(a + 1)
    if op not in (0x01, 0x11, 0x21) or not 0x8000 <= v < 0xA000:
        sys.exit(f'{a:04X}: не ld rr,nn в окно ({op:02X} {v:04X})')
    patch(a + 1, [v & 255, v >> 8], [(v - OFF) & 255, (v - OFF) >> 8], f'окно {v:04X}->{v - OFF:04X}')
# указатели t_deckgfx (9603): до начала графики
a, n = 0x9603, 0
first = min(rw(x) for x in range(0x9603, 0x9670, 2) if 0x9603 <= rw(x) < 0xA000)
while a + 2 <= first - 1:          # перед первой графикой — байт заголовка
    v = rw(a)
    if v:
        if not 0x9603 <= v < 0xA000: sys.exit(f'{a:04X}: указатель t_deckgfx вне окна {v:04X}')
        mem[a], mem[a + 1] = (v - OFF) & 255, (v - OFF) >> 8; n += 1
    a += 2
log.append(f'9603 t_deckgfx: {n} указателей −0x6000 (таблица до {first:04X})')
mem[0x8000 - OFF:0xA000 - OFF] = mem[0x8000:0xA000]
mem[0x8000:0xA000] = bytes(0x2000)                     # видимая плоскость

# --- прерывание ---
patch(0xDE81, [0xED, 0x5E], [0xED, 0x56], 'im 2 -> im 1')

patch(0xB6E9, [0xF3], [0x00], 'play_tune: di -> nop (клавиатура Вектора опрашивается в прерывании)')

# --- копия ПЗУ ZX с 0x1000 ---
patch(0xB5AB, [0xE6, 0x03], [0xE6, 0x13], 'rnd: and 03h -> and 13h')
patch(0xB5BA, [0x00, 0x00], [0x00, 0x10], 'v_rnd_ptr = 1000h')
# CIRCUIT (карточка части в пульте): узор из байтов ПЗУ 0400–052B -> из неизменной графики палуб (ZX 9700–982B, здесь 3700):
# копия ПЗУ 1400–152F больше не нужна (сборка i8080 отдаёт её под код); стенды кладут те же байты на место ПЗУ ZX
patch(0xD29B, [0x16, 0x04], [0x16, 0x37], 'CIRCUIT: ld d,04h -> ld d,37h (графика палуб)')

# --- DETECTOR (по желанию) ---
if '--detector' in sys.argv:
    patch(0xD498, [0x21, 0xEE, 0x60], [0x21, 0x78, 0x80 - 0x60], 'DETECTOR: t_deckdroids')

# --- blit_tile с HL = 0 (пустая ячейка графики) — не выводить (ошибка оригинала) ---
patch(0xB07D, [0x7E, 0x23], [0xE7, 0x00], 'blit_tile: rst 20h (HL = 0 — выход)')

# --- управление по умолчанию — «4» (Kempston: джойстик «П», стрелки и пробел), в меню достаточно ENTER ---
# меню управления: только клавиатура (режим 1 — таблица клавиш «курсора»: стрелки и пробел Вектора) и джойстик
# (режим 2 — путь Kempston: джойстик «П», стрелки, пробел); сверху логотип. По умолчанию — джойстик
patch(0xAFC4, [0x01], [0x02], 'v_ctrlmode = 2 (джойстик) по умолчанию')
patch(0xB9BD, [0xD5, 0xAF, 0xE5, 0xAF], [0xE5, 0xAF, 0xCF, 0xAF], 't_keytabs: режим 1 — таблица стрелок и пробела, 2 — маски Kempston')
patch(0xB628, [0xFE, 0x04], [0xFE, 0x02], 'input_read: Kempston — режим 2')
patch(0xB95D, [0x21, 0xA3, 0x58], [0x21, 0xE3, 0x58], 'menu_controls: подсветка — строки 7 и 9')
patch(0xB973, [0xFE, 0x05], [0xFE, 0x03], 'menu_controls: два пункта')
patch(0xB98D, [0x06, 0x04], [0x06, 0x02], 'menu_controls: клавиши 1 и 2')
patch(0xB94A, [0x01, 0x65, 0x40, 0x02, 0xA3, 0x40, 0x03, 0xE3, 0x40, 0x04, 0x23, 0x48, 0x05, 0x63, 0x48, 0x06, 0xA7, 0x48, 0xFF],
      [0xA0, 0x69, 0x40, 0xA1, 0x89, 0x40, 0x02, 0xE3, 0x40, 0x03, 0x23, 0x48, 0x06, 0x67, 0x48, 0xFF, 0xFF, 0xFF, 0xFF],
      'menu_controls: логотип (псевдографика A0/A1), пункты 1/2, подсказка')
if '--ru' not in sys.argv:          # русская — port/ru/text.py
    patch(0x77DF, [0x02, 0x24, 0x25, 0x0C, 0x1E, 0x1B, 0x1C, 0x18, 0x1B, 0x25, 0x14, 0x0E, 0x22, 0x1C, 0x25, 0x18, 0x1B, 0x25, 0x0A, 0x10, 0x0F],
          [0x02, 0x24, 0x25, 0x13, 0x18, 0x22, 0x1C, 0x1D, 0x12, 0x0C, 0x14] + [0x25] * 10, 'сообщение 3: 2. JOYSTICK')
    patch(0x782C, [0x1D, 0x18, 0x25, 0x04], [0x18, 0x1B, 0x25, 0x02], 'сообщение 6: SELECT 1 OR 2')

# --- ввод-вывод ZX ---
# бипер в циклах тона и шума — сразу в порт Вектора: out (00h),a (бит-сет порта C ВВ55, бит 0 — динамик),
# переключение бита 0 вместо бита 4 ZX (те же размеры команд, тот же темп цикла)
# звук целиком на ВИ53: шум (isr_noise, bonus_count) — вызов склейки вместо and/or/out; тоны мини-игры — делитель
# в начале цикла (вместо ld hl,nn), сам цикл остаётся задержкой без вывода; адреса склейки — после её сборки (HOOKS2)
for a, old, new, why in [
        (0xBD8E, [0x3E, 0x12], [0x3E, 0x00], 'isr_tone: начальное A (цикл заменён vec_tone)'),
        (0xC9D6, [0xD3, 0xFE], [0x00, 0x00], 'xf_pick_loop: бипер молчит (тон — ВИ53)'),
        (0xCA4E, [0xD3, 0xFE], [0x00, 0x00], 'xf_beep: бипер молчит (тон — ВИ53)')]:
    patch(a, old, new, why)
HOOKS2 = [(0xBD71, [0xE6, 0x10, 0xF6, 0x02, 0xD3, 0xFE], 'vi_noise0', 'isr_noise: шум -> ВИ53 счётчик 0'),
          (0xB83A, [0xE6, 0x10, 0xF6, 0x02, 0xD3, 0xFE], 'vi_noise1', 'bonus_count: шум -> ВИ53 счётчик 1'),
          (0xC9CD, [0x21, 0x00, 0x03], 'vi_pick', 'xf_pick_loop: тон -> ВИ53 счётчик 2 (+ ld hl,0300h)'),
          (0xCA48, [0x21, 0x01, 0x03], 'vi_beep', 'xf_beep: тон -> ВИ53 счётчик 2 (+ ld hl,0301h)')]
patch(0xB732, [0xD3, 0xFE], [0x00, 0x00], 'play_tune: бипер молчит (мелодия — ВИ53)')
for a in [0xB87E, 0xB92C]:      # бордюр
    patch(a, [0xD3, 0xFE], [0xCF, 0x00], 'out (0FEh),a -> rst 08h')
patch(0xB73E, [0xFB], [0xF7], 'play_tune: ei -> rst 30h (мелодия замолкает)')
for a in [0xB2FD, 0xB35E, 0xB366, 0xB630, 0xB648, 0xB6B4, 0xB97A, 0xB985, 0xE220]:
    patch(a, [0xED, 0x78], [0xD7, 0x00], 'in a,(c) -> rst 10h')

# --- вывод по месту: входы spr_flush, scr_copy, cls_bitmap -> склейка (адреса из glue.sld после сборки) ---
HOOKS = [(0xB424, [0x3A, 0x17, 0xAF], 'vec_spr_flush'), (0xC05A, [0x11, 0x00, 0x83], 'vec_scr_copy'),
         (0xB2C9, [0x21, 0x00, 0x40], 'vec_cls')]

# --- склейка ---
os.makedirs('build/port', exist_ok=True)
# ПЗУ ZX 48K (нужны 0000-052F): файл из ZXROM, иначе набор MAME zx-stand/spectrum.zip
rom = open(os.environ['ZXROM'], 'rb').read() if os.environ.get('ZXROM') else zipfile.ZipFile('zx-stand/spectrum.zip').read('spectrum.rom')
if hashlib.md5(rom[:0x530]).hexdigest() != ZXROM_MD5: sys.exit('ПЗУ ZX: не та прошивка (нужна 48K, 0000-052F с md5 ' + ZXROM_MD5 + ')')
open('build/port/zxrom_0000.bin', 'wb').write(rom[:0x530])
SJ = os.environ.get('SJASMPLUS', os.path.abspath('tools/sjasmplus'))
r = subprocess.run([SJ, '--nologo', '--msg=war', '--fullpath', '--lst=../build/port/glue.lst', '--sld=../build/port/glue.sld',
                    'glue.asm'], cwd='port', capture_output=True, text=True)
if r.returncode: sys.exit('sjasmplus: ' + r.stdout + r.stderr)
glue = open('build/port/glue.bin', 'rb').read()
mem[0:0x2000] = glue
L = {}
RELO_LO, RELO_HI, RELO_NEW = 0xDE70, 0xEE91, 0x4000   # блок start..EE90 -> 4000 (плоскость E000-FFFF свободна под цвет)
for l in open('build/port/glue.sld', encoding='latin-1'):
    p = l.split('|')
    if len(p) >= 8 and p[6] == 'L':
        n = p[7].split(',')[1]
        if n and n not in L: L[n] = int(p[5])
patch(0xB22B, [0xED, 0x5B, 0x0E, 0xB0], [0xCD, L['vec_glyph'] & 255, L['vec_glyph'] >> 8, 0x00], 'call vec_glyph (знак сразу в плоскость)')
patch(0xBD8A, [0x3A, 0xFD, 0xBD], [0xC3, L['vec_tone'] & 255, L['vec_tone'] >> 8], 'isr_tone -> jp vec_tone (ВИ53)')
patch(0xB71C, [0x11, 0x30, 0x15], [0xCD, L['vec_note'] & 255, L['vec_note'] >> 8], 'play_tune: call vec_note (ВИ53)')
patch(0xE1A9, [0xCD, 0x38, 0xBE], [0xCD, L['vec_cam_draw'] & 255, L['vec_cam_draw'] >> 8], 'cam_step: call vec_cam_draw (вертикальная прокрутка из полосы)')
patch(0xDEB8, [0xCD, 0x7C, 0xB8], [0xCD, L['god_start'] & 255, L['god_start'] >> 8], 'title_loop: call god_start (F1 + F3 — режим бога)')
patch(0xE3AB, [0x3A, 0x93, 0xAF], [0xCD, L['god_chk'] & 255, L['god_chk'] >> 8], 'energy_check: call god_chk (режим бога)')
patch(0xDD7C, [0x3A, 0x09, 0xAF], [0xCD, L['vec_pace_n'] & 255, L['vec_pace_n'] >> 8], 'spr_pace: без задержки при прокрутке')
# цвет: записи атрибутов ZX — через склейку (класс клетки во второй плоскости, палитра)
for a in [0xB96F]:
    patch(a, [0x71], [0xDF], 'ld (hl),c -> rst 18h (атрибут + класс)')
for a in [0xCE22, 0xCE24, 0xD073, 0xD075, 0xD3FC, 0xD4D7, 0xDE55, 0xDE6A, 0xE304]:
    patch(a, [0x77], [0xDF], 'ld (hl),a -> rst 18h (атрибут + класс)')
for a in [0xD3C2, 0xD402]:
    patch(a, [0x36, 0x47], [0xDF, 0x47], 'ld (hl),47h -> rst 18h + байт (атрибут + класс)')
for a in [0xC8B0, 0xCBBA, 0xCBCD, 0xCCE1, 0xCCF5, 0xCD9A, 0xD4AE]:
    patch(a, [0x12], [0xEF], 'ld (de),a -> rst 28h (атрибут + класс)')
patch(0xC721, [0xCD, 0xBC, 0xB5], [0xCD, L['vec_xf_attr'] & 255, L['vec_xf_attr'] >> 8], 'xf_restart: call vec_xf_attr (цвета захвата)')
patch(0xB2E7, [0x21, 0x00, 0x58], [0xC3, L['vec_cls_attr'] & 255, L['vec_cls_attr'] >> 8], 'cls_attr -> jp vec_cls_attr (палитра)')
patch(0xB5BC, [0x7E, 0xFE, 0xFF], [0xC3, L['vec_attr_rects'] & 255, L['vec_attr_rects'] >> 8], 'attr_rects -> jp vec_attr_rects (классы)')
for a, old, name, why in HOOKS2:
    patch(a, old, [0xCD, L[name] & 255, L[name] >> 8] + [0x00] * (len(old) - 3), why)
for a, old, name in HOOKS:
    old = list(old)
    if a == 0xC05A: old = [0x11, 0x00, 0x23]          # операнд уже перенесён (8300 -> 2300)
    patch(a, old, [0xC3, L[name] & 255, L[name] >> 8], f'jp {name}')
# --- перенос блока start..EE90 (DE70-EE90) в 4000: операнды команд кода, указывающие в блок, + сдвиг ---
import re
# разметка оригинала (tools/mk_portdata.py из build/blocks.txt и build/quaz.asm): блоки кода и адреса команд,
# у которых операнд в листинге — метка в переносимом блоке (числа вроде ld bc,0DFFEh — порт клавиатуры — не адреса)
code = set()
for l in open('port/data/blocks.txt'):
    m = re.match(r'b\d+: start 0x(\w+) end 0x(\w+) type code', l)
    if m: code |= set(range(int(m[1], 16), int(m[2], 16)))
labelled = {int(x, 16) for x in open('port/data/relo_labelled.txt').read().split()}
OP1 = {0x01, 0x11, 0x21, 0x31, 0x22, 0x2A, 0x32, 0x3A, 0xC2, 0xC3, 0xC4, 0xCA, 0xCC, 0xCD, 0xD2, 0xD4, 0xDA, 0xDC,
       0xE2, 0xE4, 0xEA, 0xEC, 0xF2, 0xF4, 0xFA, 0xFC}
OPED = {0x43, 0x4B, 0x53, 0x5B, 0x63, 0x6B, 0x73, 0x7B}
DELTA = RELO_NEW - RELO_LO
nfix = 0
for a in sorted(labelled):
    op = mem[a]
    if op in OP1: o = a + 1
    elif op == 0xED and mem[a + 1] in OPED: o = a + 2
    elif op in (0x10, 0x18, 0x20, 0x28, 0x30, 0x38): continue      # jr/djnz — относительные, двигаются вместе
    else: sys.exit(f'{a:04X}: операнд-метка в блоке, но команда не распознана ({op:02X})')
    v = mem[o] | mem[o + 1] << 8
    if not RELO_LO <= v < RELO_HI: sys.exit(f'{a:04X}: операнд {v:04X} не в блоке (правка склейки?)')
    v = (v + DELTA) & 0xFFFF; mem[o], mem[o + 1] = v & 255, v >> 8; nfix += 1
patch(0xB74E, [0x00, 0xEC], [(0xEC00 + DELTA) & 255, (0xEC00 + DELTA) >> 8], 't_tunes: мелодия заставки (перенос блока)')
mem[RELO_NEW:RELO_NEW + RELO_HI - RELO_LO] = mem[RELO_LO:RELO_HI]
mem[0xDE70:0x10000] = bytes(0x10000 - 0xDE70)          # E000-FFFF — плоскость цвета
log.append(f'перенос DE70-EE90 -> {RELO_NEW:04X}: операндов {nfix}')
open('build/port/reloc.txt', 'w').write(f'{RELO_LO:04X} {RELO_HI:04X} {RELO_NEW:04X}\n')
# таблицы звука ВИ53 (склейка читает по адресам 5400, 5600)
for n in range(256):
    h = n or 256
    d = min(65535, int(1497600 * 2 * (27 * h + 29) / 3500000 + 0.5))       # тон эффекта: полупериод 27h + 29 тактов ZX
    mem[0x5400 + 2 * n], mem[0x5401 + 2 * n] = d & 255, d >> 8
    d = min(65535, int(1497600 * 2 * 88 * h / 3500000 + 0.5))               # нота: период 2n итераций по 88 тактов
    mem[0x5600 + 2 * n], mem[0x5601 + 2 * n] = d & 255, d >> 8
OUT = 'build/port/quaz_z80.r0m'
if '--ru' in sys.argv:                                 # русские тексты и буквы (tools/ru_pack.py, port/ru/)
    sys.path.insert(0, os.path.dirname(__file__))
    import ru_pack
    for w in ru_pack.build(mem, log, L): print('ширина:', w)
    OUT = 'build/port/quaz_z80_ru.r0m'
open(OUT, 'wb').write(mem)
open(OUT.replace('.r0m', '_patches.txt') if '--ru' in sys.argv else 'build/port/patches.txt', 'w').write('\n'.join(log) + '\n')
print(f'{OUT}: правок {len(log)}, склейка {len(glue)} байт')
