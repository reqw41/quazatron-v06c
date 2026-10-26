#!/usr/bin/env python3
"""Перевод порта на i8080 (этап 2, docs/PLAN.md). Источник — готовый образ Z80 (build/port/quaz_z80[_ru].r0m: все правки
порта, склейка и тексты уже внутри). Код (игра и склейка) декодируется трассировкой от входов (tools/z80dec.py),
переводится в подмножество i8080 и раскладывается по освободившимся местам; данные остаются на своих адресах.
Косвенных переходов нет — код переносится целиком; метка zXXXX — команда с адресом XXXX в образе Z80.
Ручные замены — port/i8080.asm (blit_tile, ldir, rld, ld a,r). Флаги: команды, которые на i8080 дают другие S/Z/C,
переводятся точно, если флаг дальше читается (анализ живости по всему коду), иначе — коротко.
  tools/port8080.py [--ru] [--exact] [--report]
  -> build/port8080/quaz_8080[_ru].r0m, pcmap.txt (адрес Z80 -> адрес i8080), quaz_8080.lst/.sld"""
import os, re, subprocess, sys
from collections import defaultdict
sys.path.insert(0, os.path.dirname(__file__))
from z80dec import decode

RU = '--ru' in sys.argv
EXACT = '--exact' in sys.argv
SRC = 'build/port/quaz_z80_ru.r0m' if RU else 'build/port/quaz_z80.r0m'
OUTD = 'build/port8080'
OUT = f'{OUTD}/quaz_8080{"_ru" if RU else ""}.r0m'
os.makedirs(OUTD, exist_ok=True)
mem = bytearray(open(SRC, 'rb').read())
RL0, RL1, RLN = [int(x, 16) for x in open('build/port/reloc.txt').read().split()]
img = lambda a: a - RL0 + RLN if RL0 <= a < RL1 else a          # адрес ZX -> адрес образа
ZXI = bytearray(0x4000) + open('orig/zx/quazatron_ram.bin', 'rb').read()
zxa = lambda a: a - RLN + RL0 if RLN <= a < RLN + RL1 - RL0 else a

def sld_labels(path):
    """имя (локальные — main.local) -> адрес"""
    L = {}
    for l in open(path, encoding='latin-1'):
        p = l.rstrip('\n').split('|')
        if len(p) >= 8 and p[6] == 'L':
            f = p[7].split(',')
            n = f[1] + ('.' + f[2] if len(f) > 2 and f[2] else '')
            if f[1] and n not in L: L[n] = int(p[5])
    return L
GZ = sld_labels('build/port/glue.sld')
# rnd: источник байтов — не копия ПЗУ ZX 1000-13FF, а неизменный код сборки C000-C3FF (and 0C3h; результат rnd стенды
# подменяют сами) — 1000-13FF свободны под код. CIRCUIT (D29B) читает графику палуб 3700 — копия ПЗУ 1400-152F тоже не нужна
assert mem[0xB5AB:0xB5AD] == bytes([0xE6, 0x13]) and mem[0xB5BB] == 0x10
mem[0xB5AC] = 0xC3; mem[0xB5BB] = 0xC0
mem[0x1000:0x1530] = bytes(0x530)

# ---- кандидаты кода: блоки code разметки игры + команды склейки (не db/dw/ds) ----
cand = bytearray(0x10000)
for l in open('port/data/blocks.txt'):
    m = re.match(r'b\d+: start 0x(\w+) end 0x(\w+) type code', l)
    if m:
        for a in range(int(m[1], 16), int(m[2], 16)): cand[img(a)] = 1
glue_data = bytearray(0x2000)
LST = [x for x in (re.match(r'^\s*\d+\+?\s+([0-9A-F]{4})\s((?:[0-9A-F]{2}\s?)*)\s*(.*)$', l)
                   for l in open('build/port/glue.lst', encoding='latin-1')) if x]
for k, x in enumerate(LST):
    a, bs, src = int(x[1], 16), x[2].split(), x[3]
    if a >= 0x1000: continue
    isdata = re.search(r'\b(db|dw|ds|defb|defw|defs)\b', src, re.I) or not re.search(r'[a-z]', src.split(';')[0], re.I)
    for i in range(len(bs)):
        if isdata: glue_data[a + i] = 1
        else: cand[a + i] = 1
for a in range(0x2000):
    if glue_data[a]: cand[a] = 0

EXTERNAL = {0xF70F}                                             # dbg_monitor: jp F70F (монитора авторов нет, не вызывается)
INLINE = {img(0xD3C2): 1, img(0xD402): 1}                       # rst 18h + байт значения (ld (hl),47h)
ROOTS = [0x0000, 0x0038]                                        # старт, кадровое прерывание (входы RST — через вызовы)

def name(t):
    if t in EXTERNAL: return f'0x{t:04X}'
    return f'z{t:04X}'

# ---- ручные замены (адрес образа -> строки i8080; term — дальше не идти) ----
REPL, REPL_TERM, REPL_TRACE = {}, set(), set()
def repl(a, lines, term=False, trace=()):
    REPL[a] = lines
    if term: REPL_TERM.add(a)
    REPL_TRACE.update(trace)
repl(img(0xB07D), ['jp blit_tile_80'], term=True)
ISR_ENTRY = decode(mem, 0x38).tgt                                # jp vec_isr
repl(0x38, ['jp isr80'], term=True, trace=[ISR_ENTRY])               # blit_tile целиком — port/i8080.asm
repl(img(0xDE70), ['ld hl,im2_dummy'])                          # start: jp isr в вектор IM 2 — в пустую ячейку
repl(img(0xB96F), ['push af', 'ld a,c', 'rst 0x18', 'pop af'])  # ld (hl),c через attr_hl (адрес возврата больше не признак)
repl(img(0xD3C2), ['push af', 'ld a,0x47', 'rst 0x18', 'pop af'])
repl(img(0xD402), ['push af', 'ld a,0x47', 'rst 0x18', 'pop af'])
AH = GZ['attr_hl'] + 8                                           # attr_hl: разбор адреса возврата — не нужен
assert decode(mem, AH).text == 'ld a,l', decode(mem, AH)
repl(AH, [f'jp {name(GZ["attr_hl.go"])}'], term=True, trace=[GZ['attr_hl.go']])
# xf_timer: sub 1 / daa (десятичное вычитание; daa i8080 — только после сложения). A <> 0 (ret z перед этим)
repl(img(0xCE7F), ['sub 0x01', 'ld (z_t),a', 'and 0x0F', 'cp 0x0F', 'ld a,(z_t)', 'jp nz,zq_bcd', 'sub 0x06',
                   'zq_bcd:', 'or a'])
repl(img(0xCE81), [])
# непосредственные операнды в код: не адреса (числа) и адреса внутри команды, переводимой без изменений
IMM_NUM = {img(0xB977), img(0xDE76)}
# процедуры, переписанные для i8080 целиком (port/i8080.asm): вход -> jp; tools/xcheck80.js сверяет после возврата
HAND = [(img(0xB07D), 'blit_tile_80'), (GZ['kbd_scan'], 'kbd_scan_80'), (GZ['zx_in_c'], 'zx_in_c_80'), (img(0xDD9E), 'font_copy_80'),
        (img(0xC20D), 'bg_restore_80'), (GZ['vec_spr_flush.row4'], 'spr_row4_80'), (img(0xB1FF), 'print_cont_80'),
        (img(0xCBEE), 'xf_rowaddr_80'), (GZ['cell_class'], 'cell_class_80'),
        (GZ['attr_de'], 'attr_de_80'), (GZ['reclass_all'], 'reclass_all_80'),
        (img(0xC1A5), 'strip_put_80'), (GZ['vec_scr_copy'], 'vec_scr_copy_80')]
for a, l in HAND[1:]: repl(a, [f'jp {l}'], term=True)
REPL_TRACE.update([GZ['vec_scr_copy_end']])                         # vec_scr_copy_80: атрибуты — scr_attr_80, затем классы
# поле-кольцо (port/i8080_ring.asm): сдвиги поля — смена смещения вместо ldir/lddr 4,8 КБ
for z, t, l in ((0xE135, 'ldir', 'ring_l80'), (0xE14F, 'lddr', 'ring_r80'), (0xE126, 'ldir', 'ring_u80'), (0xE117, 'lddr', 'ring_d80')):
    assert decode(mem, img(z)).text == t, (hex(z), decode(mem, img(z)).text); repl(img(z), [f'call {l}'])
# spr_pace: у ZX задержка (6 − объектов) × 32896 тактов — темп хода. Здесь вместо неё срок (pace80, port/i8080_fast2.asm):
# проход длится не меньше среднего прохода ZX при том же числе объектов (таблица pace_tab), опоздание до кадра — в зачёт
repl(img(0xDD80), ['call pace80', 'ld a,6'])
repl(img(0xDD8A), ['ld hl,0'])
for a in (0xDD8B, 0xDD8D, 0xDD8E, 0xDD90, 0xDD91): repl(img(a), [])
XSKIP = []                                                       # tools/xcheck80.js: несколько команд — одна замена
# ---- задержки по времени ZX: пустые циклы (dec l / jr nz / dec h / jr nz и циклы тонов, где бипер — уже ВИ53) переводятся
# в цикл i8080 той же длительности (такты ZX 3,5 МГц -> такты Вектора 3 МГц; итерация i8080 — 20 тактов, у ZX — 16..27)
def delay_nl(cyc, lo, hi, tag):                                  # цикл по паре hi:lo длиной cyc тактов Вектора, на выходе пара = 0
    best = None
    for H in range(1, 256):
        for L in range(1, 257):
            t = 12 + 20 * ((H - 1) * 256 + L) + 20 * H
            if best is None or abs(t - cyc) < abs(best[0] - cyc): best = (t, H, L & 255)
    t, H, L = best
    return [f'ld {hi},{H}', f'ld {lo},{L}', f'{tag}:', f'dec {lo}', f'jp nz,{tag}', f'dec {hi}', f'jp nz,{tag}']
def delay_repl(a0, a1, lines, regdiff=False):                    # команды a0..a1 (образ) -> lines; сверка — после a1
    a = a0; first = True
    while a < a1:
        repl(a, lines if first else []); first = False; a += decode(mem, a).n
    XSKIP.append((a0, a1))
    if regdiff: DREGDIFF.append(a1)
DREGDIFF = []
ZX2V = 3.0 / 3.5
# пауза (hl = 4000h), захват — выбор стороны (hl = 4800h), лифт (hl = 8000h): n итераций по 16 + 11 на шаг h
for z, n, h in ((0xB6D1, 0x4000, 0x40), (0xC9E1, 0x4800, 0x48), (0xD407, 0x8000, 0x80)):
    ln = n * 16 + h * 11
    delay_repl(img(z), img(z) + 9, delay_nl(ln * ZX2V, 'l', 'h', f'zq_d{z:04X}'))
# мелодия: нота — 5168 итераций по 88 тактов ZX (+ сдвиги голосов) при di; на Векторе идёт прерывание (~5% кадра)
delay_repl(img(0xB71F), img(0xB73C), delay_nl(455500 * ZX2V * 0.95, 'e', 'd', 'zq_tune'), regdiff=True)
# захват: тон выбора стороны (768 итераций по 27) и тон хода (513 по 27) — делитель уже в ВИ53, остаётся задержка
delay_repl(img(0xC9D3), img(0xC9E1), delay_nl((768 * 27 + 230) * ZX2V, 'l', 'h', 'zq_pick'), regdiff=True)
delay_repl(img(0xCA4D), img(0xCA5B), delay_nl((513 * 27 + 160) * ZX2V, 'l', 'h', 'zq_beep'), regdiff=True)
def find_seq(start, texts, limit=200):                            # первая пара команд подряд с данным текстом
    a = start
    for _ in range(limit):
        i = decode(mem, a); j = decode(mem, a + i.n)
        if i.text == texts[0] and j.text == texts[1]: return a, a + i.n
        a += i.n
    sys.exit(f'нет {texts} после {start:04X}')
CC = f'call 0x{GZ["cell_class"]:04X}'
for g in ('attr_de', 'attr_hl.go'):                             # ld (hl),a / call cell_class -> только если атрибут другой
    a1, a2 = find_seq(GZ[g], ('ld (hl),a', CC)); repl(a1, ['call attr_set80']); repl(a2, []); XSKIP.append((a1, a2 + 3))
_, a2 = find_seq(GZ['vec_glyph'], ('ld a,(hl)', CC)); repl(a2, ['call cell_class_px80'])   # знак: класс по точкам — только 2/3
a = GZ['vband_render']                                              # приёмник strip_put (BAND / поле) — в ячейку sp_dst
for _ in range(200):
    i = decode(mem, a)
    if i.text == 'ld (0xC1B8),hl': repl(a, ['ld (sp_dst),hl'])
    if i.text == 'jp 0x' + f'{GZ["G_CAM_ISO"]:04X}' or i.mn == 'ret': break
    a += i.n
a1, a2 = find_seq(GZ['vec_cam_draw'], ('ld bc,0x0100', 'ldir')); repl(a2, ['call ring_band80'])   # 8 строк BAND -> поле
# pal_set: коды SEL не зависят от бита мигания — считать 0..7Fh и копировать; zxcol — по таблице (port/i8080_fast.asm)
ZXCOL = f'call 0x{GZ["zxcol"]:04X}'
a = GZ['pal_set']
for _ in range(400):
    i = decode(mem, a)
    if i.text == ZXCOL: repl(a, ['call zxcol_t80'])
    if i.text == 'inc l' and decode(mem, a + 1).text == f'jp nz,0x{GZ["pal_set.s"]:04X}':
        repl(a + 1, [f'jp p,z{GZ["pal_set.s"]:04X}', 'call pal_hi80']); break
    a += i.n
else: sys.exit('pal_set: нет конца цикла')
SKIPRET_X = [GZ['pal_set']]
assert decode(mem, img(0xCC73)).text == 'ld (0xCECA),de'           # xf_side_setup: новый первый ряд -> кэш xf_rowaddr_80 сбросить
repl(img(0xCC73), ['ex de,hl', 'ld (0xCECA),hl', 'ex de,hl', 'push af', 'xor a', 'ld (xr_rows),a', 'pop af'])
repl(GZ['vec_scr_copy_end.same'], ['jp fcls80'], term=True, trace=[GZ['contour'], GZ['fc_fix']]); SKIPRET_X.append(GZ['vec_scr_copy_end.same'])   # классы поля
# isr игры: exx / ex af,af' на входе и выходе — только чтобы не трогать основные регистры (isr не читает старые
# значения BC', DE', A', других пользователей запасных регистров в сборке i8080 нет); vec_isr сам сохраняет AF, BC, DE, HL.
# На i8080 — без обмена (push af / pop af остаются); сверка — после возврата из isr
# Из запасных читается только HL' (rnd в isr_noise сохраняет HL в v_rnd_hl) — он и переносится: z_hl2 <-> HL.
for z, t, l in ((0xBD2E, 'exx', ['ld hl,(z_hl2)']), (0xBD2F, "ex af,af'", []), (0xBDF9, "ex af,af'", []),
                (0xBDFA, 'exx', ['ld (z_hl2),hl'])):
    assert decode(mem, img(z)).text == t, (hex(z), decode(mem, img(z)).text); repl(img(z), l)
SKIPRET_X.append(img(0xBD2D))
# attr_promote: при pal_lock (игра, захват) — сразу выход, без сохранения всех регистров
AP = GZ['attr_promote']
assert decode(mem, AP).text == 'push af'
repl(AP, ['push af', f'ld a,(0x{GZ["pal_lock"]:04X})', 'and a', 'jp z,zq_ap', 'pop af', 'ret', 'zq_ap:', 'pop af', 'push af'])
SKIPRET_X.append(AP)                            # ld bc,0BFFEh — порт; ld de,isr — значение для вектора IM 2

# ---- трассировка ----
ins = {}
todo = list(ROOTS) + list(range(0x08, 0x38, 8)) + sorted(REPL_TRACE)
while todo:
    a = todo.pop()
    while a not in ins:
        if not cand[a]: sys.exit(f'{a:04X}: переход в не-код')
        i = decode(mem, a)
        if a in INLINE: i.n += INLINE[a]
        ins[a] = i
        if a in REPL_TERM: break
        t = i.tgt
        if t is not None and t not in EXTERNAL:
            if not cand[t]: sys.exit(f'{i}: цель {t:04X} вне кода')
            todo.append(t)
        if i.kind == 'jpind': sys.exit(f'{i}: косвенный переход')
        if i.kind in ('jp', 'ret', 'halt'): break
        a += i.n

reach = bytearray(0x10000)
for a, i in ins.items():
    for k in range(i.n): reach[a + k] = 1

def ranges(arr, lo=0, hi=0x10000):
    out, a = [], lo
    while a < hi:
        if arr[a]:
            b = a
            while b < hi and arr[b]: b += 1
            out.append((a, b)); a = b
        else: a += 1
    return out

# начало команды для адреса внутри неё
owner = {}
for a, i in ins.items():
    for k in range(i.n): owner[a + k] = a

GSRC = {int(x[1], 16): x[3].encode('latin-1').decode('utf-8', 'replace') for x in LST if x[2].strip()}       # адрес команды склейки -> исходник
def imm_sym(i):
    """операнд-адрес в код: символ или None (не адрес)"""
    v = i.imm
    if i.a in IMM_NUM: return None
    if i.a >= 0x2000 and v < 0x2000: return None                  # игра не берёт адресов кода склейки (кроме переходов)
    if i.a < 0x2000:                                              # склейка: адрес, только если операнд — метка кода
        src = GSRC.get(i.a, '').split(';')[0]
        idents = re.findall(r'[A-Za-z_.][\w.]*', src.split(None, 1)[1] if len(src.split(None, 1)) > 1 else '')
        if not any(n in GZ and cand[GZ[n]] for n in idents): return None
    if RLN <= v < RLN + RL1 - RL0:                                # 4000-5020: адрес экрана ZX или перенесённый указатель
        o = zxa(i.a) + i.immpos if i.a >= 0x2000 else None
        if o is not None and (ZXI[o] | ZXI[o + 1] << 8) == v: return None
    if v in ins: return name(v)
    if v in owner:
        o = owner[v]
        return f'{name(o)}+{v - o}'
    return 'BAD'

# ---- флаги: использование и определение (S, Z, C) ----
ALL = frozenset('SZCA')                                          # флаги S, Z, C и регистр A (живость для перевода)
CCF = {'nz': 'Z', 'z': 'Z', 'nc': 'C', 'c': 'C', 'p': 'S', 'm': 'S'}
ALU8 = {'add', 'adc', 'sub', 'sbc', 'and', 'or', 'xor', 'cp'}
SHIFTS = {'rlc', 'rrc', 'rl', 'rr', 'sla', 'sra', 'srl', 'sll'}

def flags_ud(i):
    mn, ops = i.mn, i.ops
    if mn in ('jp', 'jr', 'call', 'ret') and ops and ops[0] in CCF and len(ops) == (1 if mn == 'ret' else 2):
        return {CCF[ops[0]]}, set()
    if mn in ('jp', 'call', 'ret') and ops and ops[0] in ('po', 'pe'): sys.exit(f'{i}: условие по P/V')
    if mn in ALU8 and not (ops[0] in ('hl', 'ix') and len(ops) == 2):
        return ({'C'} if mn in ('adc', 'sbc') else set()), set('SZC')
    if mn in ('inc', 'dec') and ops[0] not in ('bc', 'de', 'hl', 'sp', 'ix'): return set(), set('SZ')
    if mn == 'add' and ops[0] in ('hl', 'ix'): return set(), {'C'}
    if mn in ('adc', 'sbc'): return {'C'}, set('SZC')
    if mn in ('rlca', 'rrca'): return set(), {'C'}
    if mn in ('rla', 'rra'): return {'C'}, {'C'}
    if mn == 'daa': return {'C'}, set('SZC')
    if mn == 'scf': return set(), {'C'}
    if mn == 'ccf': return {'C'}, {'C'}
    if mn == 'neg': return set(), set('SZC')
    if mn in SHIFTS: return ({'C'} if mn in ('rl', 'rr') else set()), set('SZC')
    if mn == 'bit': return set(), set('SZ')
    if mn == 'push' and ops[0] == 'af': return set(ALL), set()
    if mn == 'pop' and ops[0] == 'af': return set(), set(ALL)
    if mn == 'ex' and ops[0] == 'af': return set(ALL), set(ALL)
    if mn == 'in' and ops[1] == '(c)': return set(), set('SZ')
    if i.text in ('ld a,r', 'ld a,i', 'rld', 'rrd'): return set(), set('SZ')
    return set(), set()

def nexts(i):
    """преемники внутри процедуры (без входа в вызов)"""
    out = []
    if i.a in REPL_TERM:
        return [t for t in REPL_TRACE if REPL[i.a] and REPL[i.a][-1].endswith(name(t))]
    if i.kind not in ('jp', 'ret', 'halt'):
        f = i.a + i.n
        if f in ins: out.append(f)
    if i.kind in ('jp', 'jpc') and i.tgt in ins: out.append(i.tgt)
    return out

callers = defaultdict(list)                                      # цель вызова -> адреса после вызовов
for a, i in ins.items():
    if i.kind in ('call', 'callc', 'rst') and i.tgt in ins and a not in REPL_TERM:
        if a + i.n in ins: callers[i.tgt].append(a + i.n)
for a, lines in REPL.items():                                     # rst 18h в заменах
    if any(l == 'rst 0x18' for l in lines) and a in ins:
        f = a + ins[a].n
        if f in ins: callers[0x18].append(f)
# какие ret достижимы из входа процедуры
rets_of = {}
def rets_from(t):
    if t in rets_of: return rets_of[t]
    seen, st, rs = set(), [t], set()
    while st:
        a = st.pop()
        if a in seen or a not in ins: continue
        seen.add(a)
        i = ins[a]
        if i.kind in ('ret', 'retc') and a not in REPL_TERM: rs.add(a)
        st.extend(nexts(i))
    rets_of[t] = rs
    return rs
ret_ctx = defaultdict(set)                                       # ret -> адреса возврата
for t, fs in callers.items():
    for r in rets_from(t): ret_ctx[r].update(fs)
root_rets = set()
for t in ROOTS: root_rets |= rets_from(t)

def a_ud(i):
    """(читает A, пишет A) у команды Z80 (вызовы и rst — через живость входа вызываемой)"""
    mn, ops, t = i.mn, i.ops, i.text
    if t in ('xor a', 'sub a'): return False, True
    if mn in ALU8 and not (ops[0] in ('hl', 'ix') and len(ops) == 2): return True, mn != 'cp'
    if mn in ('rlca', 'rrca', 'rla', 'rra', 'cpl', 'neg', 'daa', 'rld', 'rrd'): return True, True
    if mn in SHIFTS or mn in ('set', 'res'): return (True, True) if ops[-1] == 'a' else (False, False)
    if mn == 'bit': return ops[-1] == 'a', False
    if mn in ('inc', 'dec'): return (True, True) if ops[0] == 'a' else (False, False)
    if mn == 'ld' and len(ops) == 2: return ops[1] == 'a', ops[0] == 'a'
    if mn == 'out': return 'a' in ops, False
    if mn == 'in': return False, ops[0] == 'a'
    return False, False
def ud(a, i):
    u, d = flags_ud(i)
    ua, da = a_ud(i)
    u, d = set(u) | ({'A'} if ua else set()), set(d) | ({'A'} if da else set())
    if a in REPL_TERM: u |= {'A'}                                 # своя процедура i8080 — может читать A
    return u, d
UD = {a: ud(a, i) for a, i in ins.items()}
live_in = {a: set() for a in ins}
def live_out(a):
    i = ins[a]
    if EXACT: return set(ALL)
    s = set()
    if i.kind in ('ret', 'retc') and a not in REPL_TERM:
        if a < 0x2000 or a in root_rets or not ret_ctx.get(a): s |= ALL      # склейка (фокусы со стеком), корни
        for f in ret_ctx.get(a, ()): s |= live_in[f]
    if i.kind == 'jp' and i.tgt in EXTERNAL: s |= ALL
    for n in nexts(i): s |= live_in[n]
    return s
changed = True
while changed:
    changed = False
    for a in sorted(ins, reverse=True):
        i = ins[a]
        u, d = UD[a]
        lo = live_out(a)
        if i.text in ('and a', 'or a') and not lo & {'S', 'Z'}: u = set(u) - {'A'}   # только сброс C — A не читается
        li = set(u) | (lo - d)
        if i.kind in ('call', 'callc', 'rst') and i.tgt in live_in: li |= live_in[i.tgt]
        if li != live_in[a]: live_in[a] = li; changed = True

# своя процедура (HAND) — что живо после её вызова (флаги и A на выходе должны быть как у Z80 там, где живы)
def reaches(t):                                                  # входы своих процедур, куда приходит поток из t (без вызовов)
    seen, todo, out = set(), [t], set()
    while todo:
        a = todo.pop()
        if a in seen or a not in ins: continue
        seen.add(a)
        if a in HANDA: out.add(a); continue
        todo += nexts(ins[a])
    return out
HANDA = {a for a, _ in HAND}
HAND_LIVE = {l: set() for _, l in HAND}
for a, i in ins.items():
    if i.kind in ('call', 'callc', 'rst') and i.tgt is not None:
        for h in reaches(i.tgt): HAND_LIVE[dict(HAND)[h]] |= live_in.get(a + i.n, set())
print('живо после своих процедур: ' + ', '.join(f'{k} {"".join(sorted(v)) or "-"}' for k, v in HAND_LIVE.items()))
# ---- перевод команды ----
PREV = {a + i.n: a for a, i in ins.items()}                      # предыдущая команда (по адресам)
KNOWN_BC = {img(0xD5EC): 12}                                     # objs_update: ld bc,0Ch в D5D6, путь — только jr nz в D5DA
def short_bc(a):                                                 # ld bc,N (N <= 16) раньше по прямому пути без записи в B/C
    if a in KNOWN_BC: return KNOWN_BC[a]
    for _ in range(4):
        if a in TARGETS: return None
        p = PREV.get(a)
        if p is None: return None
        t = ins[p].text
        m = re.fullmatch(r'ld bc,0x00([0-9A-F]{2})', t)
        if m: return int(m[1], 16) if 1 <= int(m[1], 16) <= 16 else None
        if ins[p].kind != 'seq' or re.search(r'\b(b|c|bc)\b', t.split(' ', 1)[-1].split(',')[0]) or t.startswith(('call', 'rst', 'ex', 'pop', 'exx')):
            return None
        a = p
    return None
TARGETS = {i.tgt for i in ins.values() if i.tgt is not None} | set(REPL_TRACE)
QN = [0]
def q():
    QN[0] += 1
    return f'zq{QN[0]}'
STAT = defaultdict(int)

def shift_seq(mn, r, need_zs, keep_a=True):
    body = {'sla': ['add a,a'], 'srl': ['or a', 'rra'], 'rl': ['rla'], 'rr': ['rra'], 'rlc': ['rlca'], 'rrc': ['rrca']}
    zs = ['inc a', 'dec a'] if need_zs else []
    sv, rs = (['ld (z_a),a'], ['ld a,(z_a)']) if keep_a else ([], [])
    if mn == 'sra':
        if r == 'a': return ['ld (z_t),a', 'rla', 'ld a,(z_t)', 'rra'] + zs
        return sv + [f'ld a,{r}', 'rla', f'ld a,{r}', 'rra', f'ld {r},a'] + zs + rs
    b = body[mn]
    if r == 'a': return b + zs
    return sv + [f'ld a,{r}'] + b + [f'ld {r},a'] + zs + rs

def ix_seq(i):
    mn, ops = i.mn, i.ops
    if mn == 'push': return ['push hl', 'ld hl,(z_ix)', 'ex (sp),hl']
    if mn == 'pop': return ['ex (sp),hl', 'ld (z_ix),hl', 'pop hl']
    if mn == 'ld' and ops[0] == 'ix': return ['push hl', f'ld hl,{ops[1]}', 'ld (z_ix),hl', 'pop hl']
    if mn in ('inc', 'dec') and ops[0] == 'ix': return ['push hl', 'ld hl,(z_ix)', f'{mn} hl', 'ld (z_ix),hl', 'pop hl']
    if mn == 'add' and ops[0] == 'ix':
        if ops[1] not in ('bc', 'de'): sys.exit(f'{i}: не поддержано')
        return ['push hl', 'ld hl,(z_ix)', f'add hl,{ops[1]}', 'ld (z_ix),hl', 'pop hl']
    # операнд (ix+d)
    k = next(n for n, o in enumerate(ops) if o.startswith('(ix'))
    d = int(ops[k][3:-1])
    adj = ['inc hl'] * d if d >= 0 else ['dec hl'] * -d
    o2 = list(ops); o2[k] = '(hl)'
    if mn == 'ld' and (('h' in ops or 'l' in ops) or not re.fullmatch(r'[abcde]|0x[0-9A-F]{2}', ops[1 - k])):
        sys.exit(f'{i}: не поддержано')
    return ['push hl', 'ld hl,(z_ix)'] + adj + [mn + ' ' + ','.join(o2), 'pop hl']

def translate(a):
    i = ins[a]
    if a in REPL: STAT['замена'] += 1; return list(REPL[a])
    mn, ops = i.mn, list(i.ops)
    lo = live_out(a)
    # операнды-метки
    if i.tgt is not None and i.kind != 'rst':
        ops[-1] = name(i.tgt)
    elif i.imm is not None and cand[i.imm]:
        s = imm_sym(i)
        if s == 'BAD': sys.exit(f'{i}: операнд {i.imm:04X} — внутри кода, но не команда')
        if s is not None:
            if '+' in s and REPL.get(owner[i.imm]) is not None: sys.exit(f'{i}: операнд внутри заменённой команды')
            ops = [o.replace(f'0x{i.imm:04X}', s) for o in ops]
            STAT['операнд-метка'] += 1
    t = mn + (' ' + ','.join(ops) if ops else '')
    if any('ix' in o for o in ops): STAT['ix'] += 1; return ix_seq(i)
    if mn == 'jr': STAT['jr'] += 1; return ['jp ' + ','.join(ops)]
    if mn == 'djnz':
        if lo & {'S', 'Z'}:
            STAT['djnz точно'] += 1
            k = q()
            return ['push af', 'dec b', f'jp z,{k}', 'pop af', f'jp {ops[0]}', f'{k}:', 'pop af']
        STAT['djnz'] += 1
        return ['dec b', f'jp nz,{ops[0]}']
    if mn == 'neg':
        if 'C' in lo: STAT['neg точно'] += 1; return ['cpl', 'add a,0x01', 'ccf']
        STAT['neg'] += 1; return ['cpl', 'inc a']
    if mn in SHIFTS:
        if mn == 'sll': sys.exit(f'{i}: sll')
        need = bool(lo & {'S', 'Z'})
        STAT['сдвиг' + (' точно' if need else '')] += 1
        return shift_seq(mn, ops[0], need, 'A' in lo)
    if mn == 'bit':
        n, r = int(ops[0]), ops[1]
        ld = [] if r == 'a' else [f'ld a,{r}']
        ka = 'A' in lo or r == 'a'
        if 'C' in lo:                                            # and сбрасывает C — сохранить
            STAT['bit точно'] += 1
            return ['push af'] + ld + [f'and 0x{1 << n:02X}', 'ld (z_t),a', 'pop af'] + (['ld (z_a),a'] if ka else []) + \
                   ['ld a,(z_t)', 'inc a', 'dec a'] + (['ld a,(z_a)'] if ka else [])
        STAT['bit'] += 1
        return (['ld (z_a),a'] if ka else []) + ld + [f'and 0x{1 << n:02X}'] + (['ld a,(z_a)'] if ka else [])
    if mn in ('set', 'res'):
        n, r = int(ops[0]), ops[1]
        op = f'or 0x{1 << n:02X}' if mn == 'set' else f'and 0x{~(1 << n) & 255:02X}'
        STAT[mn] += 1
        if r == 'a':
            if not lo & {'S', 'Z', 'C'}: return [op]                 # флаги не нужны — прямо в A
            return ['push hl', 'push af', 'pop hl', 'ld a,h', op, 'ld h,a', 'push hl', 'pop af', 'pop hl']
        if not lo & set(ALL): return [f'ld a,{r}', op, f'ld {r},a']  # ни A, ни флаги не нужны
        return ['push af', f'ld a,{r}', op, f'ld {r},a', 'pop af']
    if mn in ('adc', 'sbc') and ops[0] == 'hl':
        rp = ops[1]
        if rp not in ('bc', 'de'): sys.exit(f'{i}: не поддержано')
        hi, lw = rp[0], rp[1]
        ka = 'A' in lo
        s = (['ld (z_a),a'] if ka else []) + ['ld a,l', f'{mn} a,{lw}', 'ld l,a', 'ld a,h', f'{mn} a,{hi}', 'ld h,a']
        if lo & {'S', 'Z'}:
            STAT[f'{mn} hl точно'] += 1
            d, c, cz = q(), q(), q()
            s += [f'jp nz,{d}', 'ld a,l', f'jp c,{c}', 'or a', f'jp z,{d}', 'ld a,0x01', 'or a', f'jp {d}',
                  f'{c}:', 'or a', f'jp z,{cz}', 'ld a,0x01', 'or a', f'{cz}:', 'scf', f'{d}:']
        else: STAT[f'{mn} hl'] += 1
        return s + (['ld a,(z_a)'] if ka else [])
    if mn == 'ex' and ops[0] == 'af':
        STAT["ex af,af'"] += 1
        return ['push hl', 'push af', 'ld hl,(z_af2)', 'ex (sp),hl', 'ld (z_af2),hl', 'pop af', 'pop hl']
    if mn == 'exx':
        STAT['exx'] += 1
        out = []
        for rp, cell in (('bc', 'z_bc2'), ('de', 'z_de2')):
            out += ['push hl', f'ld hl,({cell})', f'push {rp}', f'ld {rp[1]},l', f'ld {rp[0]},h', 'pop hl', f'ld ({cell}),hl', 'pop hl']
        return out + ['push hl', 'ld hl,(z_hl2)', 'ex (sp),hl', 'ld (z_hl2),hl', 'pop hl']
    if mn in ('ldir', 'lddr'):
        n = short_bc(a)                                          # BC = N (N <= 16) известно — развёрнутая копия
        if n:
            STAT[mn + ' короткий'] += 1
            return ['push af', f'call z_{mn}_{n}', 'pop af']
        STAT[mn] += 1; return [f'call z_{mn}']
    if mn in ('ldi', 'ldd', 'cpi', 'cpd', 'cpir', 'cpdr', 'ini', 'ind', 'inir', 'indr', 'outi', 'outd', 'otir', 'otdr', 'rrd'):
        sys.exit(f'{i}: {mn} не поддержан')
    if mn == 'rld': STAT['rld'] += 1; return ['call z_rld']
    if t == 'ld a,r':
        STAT['ld a,r'] += 1; return ['call z_ld_a_r']
    if t in ('ld i,a', 'ld r,a') or mn == 'im': STAT[t] += 1; return []
    if mn in ('reti', 'retn'): return ['ret']
    if mn in ('in', 'out') and '(c)' in ops: sys.exit(f'{i}: ввод-вывод через (c)')
    if mn == 'ld' and len(ops) == 2:
        d, s = ops
        if d in ('bc', 'de', 'sp') and s.startswith('('):
            STAT['ld rr,(nn)'] += 1
            if d == 'de': return ['ex de,hl', f'ld hl,{s}', 'ex de,hl']
            if d == 'bc': return ['push hl', f'ld hl,{s}', 'ld b,h', 'ld c,l', 'pop hl']
            STAT['ld sp,(nn)'] += 1
            return ['ld (z_hls),hl', f'ld hl,{s}', 'ld sp,hl', 'ld hl,(z_hls)']
        if s in ('bc', 'de', 'sp') and d.startswith('('):
            STAT['ld (nn),rr'] += 1
            if s == 'de': return ['ex de,hl', f'ld {d},hl', 'ex de,hl']
            if s == 'bc': return ['push hl', 'ld h,b', 'ld l,c', f'ld {d},hl', 'pop hl']
            STAT['ld (nn),sp'] += 1                               # без стека (SP может смотреть в данные); add hl,sp даёт C = 0
            c, e = q(), q()
            return ['ld (z_hls),hl', 'ld hl,0x0000', f'jp c,{c}', 'add hl,sp', f'jp {e}', f'{c}:', 'add hl,sp', 'scf', f'{e}:',
                    f'ld {d},hl', 'ld hl,(z_hls)']
    if mn == 'daa' and img(0xB790) != a: sys.exit(f'{i}: daa — проверить, что после сложения')
    return [t]

# ---- размер строки i8080 ----
R8 = {'a', 'b', 'c', 'd', 'e', 'h', 'l', '(hl)'}
def size(l):
    if l.endswith(':'): return 0
    mn, _, o = l.partition(' ')
    ops = o.split(',') if o else []
    if mn == 'db': return len(ops)
    if mn in ('nop', 'halt', 'di', 'ei', 'ret', 'rlca', 'rrca', 'rla', 'rra', 'daa', 'cpl', 'scf', 'ccf', 'push', 'pop', 'rst',
              'inc', 'dec'): return 1
    if mn == 'ex': return 1
    if mn in ('jp', 'call'): return 1 if ops == ['(hl)'] else 3
    if mn in ('in', 'out'): return 2
    if mn in ('add', 'adc', 'sub', 'sbc', 'and', 'or', 'xor', 'cp'):
        x = ops[-1]
        if mn == 'add' and ops[0] == 'hl': return 1
        return 1 if x in R8 else 2
    if mn == 'ld':
        d, s = ops
        if d == 'sp' and s == 'hl': return 1
        if d in R8 and s in R8: return 1
        if d in ('a',) and s in ('(bc)', '(de)'): return 1
        if s == 'a' and d in ('(bc)', '(de)'): return 1
        if d in R8 and not s.startswith('('): return 2
        if d in R8 and s.startswith('(') and d == 'a': return 3
        if d in ('bc', 'de', 'hl', 'sp'): return 3
        if d.startswith('(') and s in ('a', 'hl'): return 3
    raise ValueError(f'размер: {l}')

# ---- перевод всего ----
code = {}
for a in sorted(ins):
    code[a] = [f'z{a:04X}:'] + translate(a)
# участки, где SP смотрит в данные (склейка: ld sp,(…)/ld sp,hl … ld sp,(сохранённый)): добавочные push/pop/call нельзя
saved = {i.imm for i in ins.values() if i.text.startswith('ld (') and i.text.endswith('),sp')}
hij, bad = None, []
for a in sorted(ins):
    i = ins[a]
    if i.mn == 'ld' and i.ops[0] == 'sp':
        if i.imm in saved: hij = None
        elif i.imm != 0x61A5: hij = a
        continue
    if hij is not None:
        orig = {i.text} if i.mn in ('push', 'pop') else set()
        extra = [l for l in code[a][1:] if l.split(' ')[0] in ('push', 'pop', 'call', 'rst') and l not in orig]
        if extra: bad.append(f'{i} (SP на данных с {hij:04X}): {extra}')
if bad: sys.exit('перевод со стеком там, где SP на данных:\n  ' + '\n  '.join(bad))

def falls(a):
    i = ins[a]
    if a in REPL_TERM: return False
    return i.kind not in ('jp', 'ret', 'halt')

if '--report' in sys.argv:
    print(f'команд {len(ins)} ({sum(i.n for i in ins.values())} байт Z80), i8080 {sum(size(l) for c in code.values() for l in c)} байт')
    for k, v in sorted(STAT.items()): print(f'  {k}: {v}')
    for a in sorted(ins):
        i = ins[a]
        if i.imm is not None and cand[i.imm] and a not in REPL and imm_sym(i): print(f'  операнд-метка {i} -> {imm_sym(i)}')
    sys.exit(0)

# ---- свободные места ----
free = bytearray(0x10000)
for a in range(0x100, 0x10000):
    if cand[a]: free[a] = 1
# 5088, 50E8: xf_fire при v_xf_row = FFh читает t_xf_wires(2) + 7F8h (за перенесённым блоком) — там должен остаться 0, как у Z80
XF_FF = [img(0xE700) + 0x7F8, img(0xE760) + 0x7F8]
assert XF_FF == [0x5088, 0x50E8]
EXTRA = [(GZ['glue_end'], 0x1600), (0x1E00, 0x2000), (0x5021, 0x5088), (0x5089, 0x50E8), (0x50E9, 0x5100),
         (0x5B00, 0x6100), (0xDE70, 0xE000)]
used = []
if RU:
    for l in open('build/port/ru_layout.txt'):
        x, y, _ = l.split(); used.append((int(x, 16), int(y, 16)))
for x, y in EXTRA:
    for a in range(x, y):
        if any(u0 <= a < u1 for u0, u1 in used): continue
        if mem[a]: sys.exit(f'свободное место {x:04X}-{y:04X}: в образе {a:04X} = {mem[a]:02X}')
        free[a] = 1
pinned = sorted(a for a in ins if a < 0x100)
base = bytearray(mem)
for a in range(0x10000):
    if free[a]: base[a] = 0
for a in pinned:
    for k in range(ins[a].n): base[a + k] = 0
open(f'{OUTD}/base.bin', 'wb').write(base)

# ---- метки склейки (данные) для port/i8080.asm ----
codestarts = set(ins)
equ, seen = [], set()
for n, v in sorted(GZ.items(), key=lambda x: x[1]):
    g = 'g_' + n.replace('.', '_')
    if g in seen or v in codestarts or not 0 <= v < 0x10000 or not re.fullmatch(r'g_[A-Za-z_]\w*', g): continue
    seen.add(g); equ.append(f'{g}\tequ\t0x{v:04X}')
open(f'{OUTD}/gequ.asm', 'w').write('\n'.join(equ) + '\n')
# метки кода склейки (входы процедур) для port/i8080.asm: c_<имя> -> метка перевода z<адрес>; в xsize.asm — 0
GC = sorted((n, v) for n, v in GZ.items() if v in codestarts and re.fullmatch(r'[A-Za-z_]\w*', n))
open(f'{OUTD}/gcode.asm', 'w').write(''.join(f'c_{n}\tequ\tz{v:04X}\n' for n, v in GC))
open(f'{OUTD}/gcode0.asm', 'w').write(''.join(f'c_{n}\tequ\t0\n' for n, v in GC))

SJ = os.environ.get('SJASMPLUS', os.path.abspath('tools/sjasmplus'))
def sj(src, *extra):
    r = subprocess.run([SJ, '--nologo', '--msg=war', '--fullpath', *extra, src], cwd=OUTD, capture_output=True, text=True)
    if r.returncode: sys.exit('sjasmplus: ' + r.stdout + r.stderr)
    return r
# размер port/i8080.asm
XFILES = ['port/i8080.asm', 'port/i8080_fast.asm', 'port/i8080_fast2.asm', 'port/i8080_ring.asm', 'port/i8080_ring2.asm']                # добавки: каждая часть — в свою дыру
ZREF = sorted({m for x in XFILES for m in re.findall(r'\bz[0-9A-F]{4}\b', open(x, encoding='utf-8').read())})   # метки перевода в добавках
open(f'{OUTD}/xsize.asm', 'w').write('\tDEVICE NOSLOT64K\n\tinclude "gequ.asm"\n\tinclude "gcode0.asm"\ng_isr_entry\tequ\t0\n'
                                      + ''.join(f'{z}\tequ\t0\n' for z in ZREF) + '\torg 0x8000\n'
                                      + ''.join(f'\tinclude "../../{x}"\nx_end{k}:\n' for k, x in enumerate(XFILES)))
sj('xsize.asm', '--sld=xsize.sld')
_xl = sld_labels(f'{OUTD}/xsize.sld')
XSIZES = [_xl[f'x_end{k}'] - (_xl[f'x_end{k - 1}'] if k else 0x8000) for k in range(len(XFILES))]

holes = [(x, y) for x, y in ranges(free) if y - x >= 4]
if os.environ.get("QZ_HOLES"): print("дыры:", " ".join(f"{x:04X}+{y - x}" for x, y in sorted(holes, key=lambda h: h[0] - h[1])[:8]))
# добавки — каждая часть в начало самой большой из оставшихся дыр
XPOS = []
for xf, xs in zip(XFILES, XSIZES):
    hx = max(range(len(holes)), key=lambda k: holes[k][1] - holes[k][0])
    if holes[hx][1] - holes[hx][0] < xs: sys.exit(f'нет места под {xf} ({xs} байт)')
    XPOS.append(holes[hx][0]); holes[hx] = (holes[hx][0] + xs, holes[hx][1])
holes = [h for h in holes if h[1] - h[0] >= 4]

# ---- раскладка: команды по порядку адресов, дыры по порядку; при смене дыры — jp на продолжение ----
out = ['\tDEVICE NOSLOT64K', '\torg 0', '\tincbin "base.bin"', '\tinclude "gequ.asm"', '\tinclude "gcode.asm"', f'g_isr_entry\tequ\tz{ISR_ENTRY:04X}']
for a in pinned:
    out.append(f'\torg 0x{a:04X}')
    out += [l if l.endswith(':') else '\t' + l for l in code[a]]
out.append(f'\tASSERT $ <= 0x0100')
for xf, xs, x0 in zip(XFILES, XSIZES, XPOS): out += [f'\torg 0x{x0:04X}', f'\tinclude "../../{xf}"', f'\tASSERT $ == 0x{x0 + xs:04X}']
order = [a for a in sorted(ins) if a >= 0x100]
hi = 0
hs, he = holes[0]
pos = hs
out.append(f'\torg 0x{hs:04X}')
prev_falls, njp = False, 0
for a in order:
    lines = code[a]
    s = sum(size(l) for l in lines)
    need = s + (3 if falls(a) else 0)
    while pos + need > he:
        if prev_falls:
            out.append(f'\tjp z{a:04X}'); pos += 3; njp += 1
        out.append(f'\tASSERT $ <= 0x{he:04X}')
        hi += 1
        if hi >= len(holes): sys.exit(f'не хватило места: остались команды с {a:04X}, ещё {sum(sum(size(l) for l in code[b]) for b in order[order.index(a):])} байт')
        hs, he = holes[hi]; pos = hs
        out.append(f'\torg 0x{hs:04X}')
        prev_falls = False
    out += [l if l.endswith(':') else '\t' + l for l in lines]
    pos += s
    prev_falls = falls(a)
out.append(f'\tASSERT $ <= 0x{he:04X}')
left = (he - pos) + sum(y - x for x, y in holes[hi + 1:])
out.append(f'\tSAVEBIN "{os.path.basename(OUT)}",0,0x10000')
SUF = '_ru' if RU else ''
open(f'{OUTD}/quaz_8080{SUF}.asm', 'w').write('\n'.join(out) + '\n')
sj(f'quaz_8080{SUF}.asm', f'--lst=quaz_8080{SUF}.lst', f'--sld=quaz_8080{SUF}.sld')
r = subprocess.run([sys.executable, 'tools/check_i8080.py', f'{OUTD}/quaz_8080{SUF}.lst'], capture_output=True, text=True)
print(r.stdout.strip().splitlines()[-1])
if r.returncode: print(r.stdout); sys.exit(1)
L8 = sld_labels(f'{OUTD}/quaz_8080{SUF}.sld')
with open(f'{OUTD}/pcmap{"_ru" if RU else ""}.txt', 'w') as f:
    for a in sorted(ins): f.write(f'{a:04X} {L8[f"z{a:04X}"]:04X}\n')
with open(f'{OUTD}/layout{"_ru" if RU else ""}.txt', 'w') as f:      # стенд: добавки (свои данные и самомодификация)
    f.write(' '.join(f'{x0:04X} {x0 + xs:04X}' for xs, x0 in zip(XSIZES, XPOS)) + '\n')   # пары начало конец
# tools/xcheck80.js: области кода (не сверять память) и команды после замен с другими регистрами
# isr: ex af,af' даёт A' — у Z80 там остаток от blit_tile (счётчик), у i8080 — своё; isr его сразу перезаписывает
REGDIFF = [img(0xDE70), img(0xBD2F)] + [a for a in ins if ins[a].text == 'ld a,r'] + [PREV[a] for a in DREGDIFF]
RETPOP = [a for a in ins if a < 0x2000 and (ins[a].mn == 'pop' and 'адрес возврата' in GSRC.get(a, '')
                                            or ins[a].text == f'ld hl,(0x{GZ["ah_ret"]:04X})')]
with open(f'{OUTD}/xc{"_ru" if RU else ""}.txt', 'w') as f:
    f.write('code ' + ' '.join(f'{x:04X}-{y:04X}' for x, y in ranges(bytearray(c or fr for c, fr in zip(cand, free)))) + '\n')
    f.write('regdiff ' + ' '.join(f'{a + ins[a].n:04X}' for a in REGDIFF) + f' {img(0xB5B4):04X}\n')   # rnd: другой источник байтов
    f.write('retpop ' + ' '.join(f'{a + ins[a].n:04X}' for a in RETPOP) + '\n')
    f.write('nocmp 2300-3600 B5BA-B5BC ' + ' '.join(f'{GZ[n]:04X}-{GZ[n] + 2:04X}' for n in ('ah_ret',)) + ' ' + f'{GZ["im2_vec"] if "im2_vec" in GZ else 0:04X}-0000' + '\n')
    f.write('adead ' + ' '.join(f'{a:04X}' for a in sorted(ins) if 'A' not in live_in[a]) + '\n')   # A мёртв на входе команды
    f.write('skipret ' + ' '.join(f'{a:04X}' for a, _ in HAND) + ''.join(f' {a:04X}' for a in SKIPRET_X) + '\n')   # свои процедуры — сверка после возврата
    # замены с вызовом внутри: сверка — сразу после команды
    sk = [(a, a + ins[a].n) for a, l in REPL.items() if a in ins and a not in REPL_TERM and any(x.startswith(('rst', 'call')) for x in l)]
    sk.append((img(0xCE7F), img(0xCE82)))                       # sub 1 / daa — одна замена на две команды
    sk.append((img(0xDD8A), img(0xDD93)))                       # spr_pace: задержка своей длины
    sk += XSKIP
    sk.append((img(0xB5A6), img(0xB5B4)))                       # rnd: указатель и байт из своей области (C000-C3FF)
    f.write('skip ' + ' '.join(f'{a:04X}:{b:04X}' for a, b in sk) + '\n')
print(f'{OUT}: команд {len(ins)}, i8080 {sum(size(l) for c in code.values() for l in c)} байт + добавки ' + ' + '.join(f'{xs} @ {x0:04X}' for xs, x0 in zip(XSIZES, XPOS)) + ', '
      f'переходов между дырами {njp}, свободно {left} байт')
