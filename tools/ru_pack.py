"""Русская версия текстов (port/ru/text.py, port/ru/font.txt) в образ порта: вызывается из tools/port_build.py --ru.
Шрифт: новые буквы — коды B8.. (print_cont даёт адрес p_font + код*8 >= 73B9, склейка vec_glyph переводит его в ru_font).
Сообщения (t_msgs, список с префиксом длины, msg_find B1ED) и составные строки (p_strcomp 61BE) собираются заново:
номера сообщений 01-48 и C9-E2 сохраняются (код зовёт их прямо), слова составных строк раскладываются по 49-C8 и E3-FE;
слова, которые всегда стоят рядом, сливаются в одно сообщение. Место: составные — 73B9-772B (p_strcomp не меняется),
сообщения — 77C0-7FFF и вторая часть (msg_find -> vec_msg_find) вместе с буквами — в 5B00-60FF."""
import os, runpy

ROOT = os.path.join(os.path.dirname(__file__), '..')
FONT, MSGS, COMPS, P_COMP = 0x6DF9, 0x77C0, 0x73B9, 0x61BE
NL = 0x45                                   # сообщение «перевод строки» в составных (без пробела после)
AREAS = [(0x73B9, 0x772C), (0x77C0, 0x8000), (0x5B00, 0x6100)]
LAT = {c: 0x0A + i for i, c in enumerate('ABCDEFGHIJKLMNOPQRSTUVWXYZ')}
LAT.update({str(i): i for i in range(10)})
WIDE = {'M': [0x16, 0x26], 'W': [0x20, 0x28]}
CYR_AS = {'А': 'A', 'В': 'B', 'Е': 'E', 'Ё': 'E', 'К': 'K', 'О': 'O', 'Р': 'P', 'С': 'C', 'Т': 'T', 'Х': 'X', 'М': 'M', 'З': '3'}


def load_font():
    glyphs, cur = {}, None
    for l in open(os.path.join(ROOT, 'port/ru/font.txt'), encoding='utf-8'):
        l = l.rstrip('\n')
        if not l or l.startswith('# '): continue
        if len(l) == 1: cur = l; glyphs[cur] = []; continue
        assert len(l) == 8 and set(l) <= {'.', '#'}, l
        glyphs[cur].append(int(l.replace('.', '0').replace('#', '1'), 2))
    for k, v in glyphs.items(): assert len(v) == 8, k
    return glyphs


def build(mem, log, L):
    glyphs = load_font()
    code = {ch: 0xB8 + i for i, ch in enumerate(glyphs)}
    font = bytearray(b for g in glyphs.values() for b in g)

    def enc(s):
        out = []
        for ch in s:
            ch = CYR_AS.get(ch, ch)
            if ch in WIDE: out += WIDE[ch]
            elif ch in LAT: out.append(LAT[ch])
            elif ch in code: out.append(code[ch])
            elif ch == ' ': out.append(0x25)
            elif ch == '.': out.append(0x24)
            elif ch == '-': out.append(0x67)
            elif ch == '\n': out.append(0xFF)
            else: raise SystemExit(f'ru: нет знака {ch!r} в «{s}»')
        return out

    def lst(base, n):
        out, a = [], base
        for _ in range(n):
            L = mem[a]; out.append(list(mem[a + 1:a + 1 + L])); a += L + 1
        return out
    en_msg = dict(enumerate(lst(MSGS, 0xE2), 1))
    en_comp = dict(enumerate(lst(COMPS, 0x9F), 1))
    T = runpy.run_path(os.path.join(ROOT, 'port/ru/text.py'))
    MSG, COMP = T['MSG'], T['COMP']

    kept = [n for n in en_comp if n not in COMP]
    reserved = (set(range(1, 0x49)) | set(range(0xC9, 0xE3)) | {m for n in kept for m in en_comp[n]}) - set(T.get('POOL_EXTRA', []))
    msg = {}
    for n in sorted(reserved):
        if n in MSG: msg[n] = enc(MSG[n])
        else:
            msg[n] = en_msg.get(n, [])
            if any(0x0A <= c <= 0x23 for c in msg[n]): log.append(f'ru: сообщение {n:02X} не переведено')
    for n in MSG:
        if n not in reserved: raise SystemExit(f'ru: сообщение {n:02X} вне сохраняемых номеров')

    # составные: строки -> слова (пробелы подряд — к слову), затем слияние слов, всегда стоящих рядом
    def words(line):
        out = []
        for i, w in enumerate(line.split(' ')):
            if w == '' and out: out[-1] += ' '
            else: out.append(w)
        return out
    seqs = {}
    for n, t in COMP.items():
        s = []
        for i, line in enumerate(t.split('\n')):
            if i: s.append('\n')
            s += words(line) if line else []
        seqs[n] = s
    while True:
        nxt, prv, pairs = {}, {}, {}
        for s in seqs.values():
            for a, b in zip(s, s[1:]):
                nxt.setdefault(a, set()).add(b); prv.setdefault(b, set()).add(a); pairs[(a, b)] = 1
        cnt = {}
        for s in seqs.values():
            for w in s: cnt[w] = cnt.get(w, 0) + 1
        # a всегда перед b, b всегда после a; a и b — не перевод строки; a не последнее в своих строках
        best = next(((a, b) for (a, b) in pairs if '\n' not in (a, b) and nxt.get(a) == {b} and prv.get(b) == {a}
                     and sum(1 for s in seqs.values() for i in range(len(s) - 1) if s[i] == a and s[i + 1] == b) == cnt[a] == cnt[b]), None)
        if not best: break
        a, b = best
        for n, s in seqs.items():
            r, i = [], 0
            while i < len(s):
                if i + 1 < len(s) and s[i] == a and s[i + 1] == b: r.append(a + ' ' + b); i += 2
                else: r.append(s[i]); i += 1
            seqs[n] = r
    by_text = {}
    for n in sorted(reserved):
        by_text.setdefault(bytes(msg[n]), n)
    pool = [n for n in T.get('POOL_EXTRA', []) + list(range(0x49, 0xC9)) + list(range(0xE3, 0xFF)) if n not in reserved]
    for a, t in T.get('LABELS', {}).items():          # надписи print_list со своим текстом: номер < 80 (с 80 — str_find2)
        k = next(n for n in pool if n < 0x80); pool.remove(k); msg[k] = enc(t); mem[a] = k
    comp = {}
    for n in sorted(seqs):
        items = []
        for w in seqs[n]:
            if w == '\n': items.append(NL); continue
            e = bytes(enc(w))
            if e not in by_text:
                if not pool: pool.append(0x100 + len(msg)); log.append('ru: НЕ ХВАТИЛО номера')
                k = pool.pop(0); msg[k] = list(e); by_text[e] = k
            items.append(by_text[e])
        comp[n] = items
    for n in kept: comp[n] = en_comp[n]

    # ширина (знаков): строки составных и сообщения против оригинала
    def comp_lines(items, m):
        lines, cur = [], []
        for k, it in enumerate(items):
            if it == NL: lines.append(cur); cur = []; continue
            if cur: cur.append(0x25)
            for c in m[it]:
                if c == 0xFF: lines.append(cur); cur = []
                else: cur.append(c)
        lines.append(cur)
        return [len(l) for l in lines]
    LIM = T.get('LIMITS', {})
    warn = []
    for n in sorted(COMP):
        w, e = max(comp_lines(comp[n], msg)), max(comp_lines(en_comp[n], en_msg))
        lim = LIM.get(('c', n), 27 if n >= 5 and (n - 5) % 4 == 3 else max(e, 19 if n >= 5 and (n - 5) % 4 == 0 else e))
        if w > lim: warn.append(f'составная {n:02X}: {w} > {lim} (англ. {e})')
    for n in sorted(MSG):
        w = max(len(x) for x in bytes(msg[n]).split(b'\xff'))
        e = max(len(x) for x in bytes(en_msg[n]).split(b'\xff'))
        lim = LIM.get(('m', n), e)
        if w > lim: warn.append(f'сообщение {n:02X} «{MSG[n]}»: {w} > {lim}')

    # раскладка: шрифт, составные, сообщения
    top = max(msg)
    def mtab(lo, hi):
        b = bytearray()
        for n in range(lo, hi):
            m = msg.get(n, []); b += bytes([len(m)]) + bytes(m)
        return b
    cblob = bytearray()
    for n in range(1, 0xA0):
        cblob += bytes([len(comp[n])]) + bytes(comp[n])
    # составные — строго с 73B9: p_strcomp (61BE) не трогаем, его старший байт читается как клетка карты палубы 0
    # (v_cellptr − 16 у края, C597); буквы и вторая часть сообщений — в 5B00-60FF
    if len(cblob) > 0x772C - COMPS: raise SystemExit(f'ru: составные ({len(cblob)} байт) не помещаются в 73B9-772B')
    for a, b in AREAS: mem[a:b] = bytes(b - a)       # старые тексты — нулями
    mem[COMPS:COMPS + len(cblob)] = cblob
    split = top + 1
    while len(mtab(1, split)) > 0x8000 - 0x77C0: split -= 1
    m1, m2 = mtab(1, split), mtab(split, top + 1)
    rest = [(COMPS + len(cblob), 0x772C), (0x5B00, 0x6100)]
    place = {'составные': COMPS}
    for name, blob in (('сообщения 2', m2), ('буквы', font)):
        for i, (a, b) in enumerate(rest):
            if b - a >= len(blob): place[name] = a; rest[i] = (a + len(blob), b); break
        else: raise SystemExit(f'ru: {name} ({len(blob)} байт) не помещаются')
        mem[place[name]:place[name] + len(blob)] = blob
    mem[0x77C0:0x77C0 + len(m1)] = m1
    mem[0xB1ED:0xB1F0] = bytes([0xC3, L['vec_msg_find'] & 255, L['vec_msg_find'] >> 8])     # msg_find -> jp vec_msg_find
    a = place['сообщения 2']; mem[L['msg_tab2']], mem[L['msg_tab2'] + 1] = a & 255, a >> 8
    mem[L['msg_split']] = split if split <= 0xFF else 0xFF
    a = (place['буквы'] - 0x73B9) & 0xFFFF; mem[L['ru_font_off']], mem[L['ru_font_off'] + 1] = a & 255, a >> 8
    place['сообщения'] = 0x77C0
    with open('build/port/ru_layout.txt', 'w') as f:                # занятые области (tools/port8080.py: свободное место)
        for n, a, ln in (('составные', COMPS, len(cblob)), ('сообщения', 0x77C0, len(m1)), ('сообщения2', place['сообщения 2'], len(m2)),
                         ('буквы', place['буквы'], len(font))):
            f.write(f'{a:04X} {a + ln:04X} {n}\n')
    mblob = m1 + m2
    log.append(f'ru: букв {len(glyphs)} (B8-{0xB7 + len(glyphs):02X} @ {place["буквы"]:04X}), сообщений {top} ({len(m1)} байт @ 77C0, с {split:02X} — {len(m2)} @ {place["сообщения 2"]:04X}), '
               f'составных 9F ({len(cblob)} байт @ 73B9), свободных номеров {len(pool)}')
    return warn
