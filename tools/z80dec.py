"""Декодер Z80 (без DD/FD — в игре нет IX/IY): decode(mem, a) -> Insn.
Insn.text — мнемоника в синтаксисе sjasmplus с числами 0x...; kind — тип перехода; tgt — адрес перехода/вызова."""
R = ['b', 'c', 'd', 'e', 'h', 'l', '(hl)', 'a']
RP = ['bc', 'de', 'hl', 'sp']
RP2 = ['bc', 'de', 'hl', 'af']
CC = ['nz', 'z', 'nc', 'c', 'po', 'pe', 'p', 'm']
ALU = ['add a,', 'adc a,', 'sub ', 'sbc a,', 'and ', 'xor ', 'or ', 'cp ']
ROT = ['rlc', 'rrc', 'rl', 'rr', 'sla', 'sra', 'sll', 'srl']
X0Z7 = ['rlca', 'rrca', 'rla', 'rra', 'daa', 'cpl', 'scf', 'ccf']


class Insn:
    __slots__ = ('a', 'n', 'mn', 'ops', 'kind', 'tgt', 'imm', 'immpos')

    def __init__(s, a, n, mn, ops=(), kind='seq', tgt=None, imm=None, immpos=None):
        s.a, s.n, s.mn, s.ops, s.kind, s.tgt, s.imm, s.immpos = a, n, mn, list(ops), kind, tgt, imm, immpos

    @property
    def text(s):
        return s.mn + (' ' + ','.join(s.ops) if s.ops else '')

    def __repr__(s):
        return f'{s.a:04X}: {s.text}'


def h16(v): return f'0x{v:04X}'
def h8(v): return f'0x{v:02X}'


def decode(m, a):
    """kind: seq, jp (безусловный), jpc (условный), call, callc, ret, retc, rst, jpind, halt"""
    op = m[a]
    b1 = m[(a + 1) & 0xFFFF]
    nn = m[(a + 1) & 0xFFFF] | m[(a + 2) & 0xFFFF] << 8
    rel = lambda: (a + 2 + (b1 - 256 if b1 > 127 else b1)) & 0xFFFF
    x, y, z, p, q = op >> 6, op >> 3 & 7, op & 7, op >> 4 & 3, op >> 3 & 1
    if op == 0xCB:
        o2 = b1
        x2, y2, z2 = o2 >> 6, o2 >> 3 & 7, o2 & 7
        if x2 == 0: return Insn(a, 2, ROT[y2], [R[z2]])
        return Insn(a, 2, ['', 'bit', 'res', 'set'][x2], [str(y2), R[z2]])
    if op == 0xED:
        o2 = b1
        x2, y2, z2, p2, q2 = o2 >> 6, o2 >> 3 & 7, o2 & 7, o2 >> 4 & 3, o2 >> 3 & 1
        nn2 = m[(a + 2) & 0xFFFF] | m[(a + 3) & 0xFFFF] << 8
        if x2 == 1:
            if z2 == 0: return Insn(a, 2, 'in', [R[y2] if y2 != 6 else 'f', '(c)'])
            if z2 == 1: return Insn(a, 2, 'out', ['(c)', R[y2] if y2 != 6 else '0'])
            if z2 == 2: return Insn(a, 2, 'adc' if q2 else 'sbc', ['hl', RP[p2]])
            if z2 == 3:
                if q2: return Insn(a, 4, 'ld', [RP[p2], f'({h16(nn2)})'], imm=nn2, immpos=2)
                return Insn(a, 4, 'ld', [f'({h16(nn2)})', RP[p2]], imm=nn2, immpos=2)
            if z2 == 4: return Insn(a, 2, 'neg')
            if z2 == 5: return Insn(a, 2, 'reti' if y2 == 1 else 'retn', kind='ret')
            if z2 == 6: return Insn(a, 2, 'im', [str([0, 0, 1, 2, 0, 0, 1, 2][y2])])
            return Insn(a, 2, ['ld i,a', 'ld r,a', 'ld a,i', 'ld a,r', 'rrd', 'rld', 'nop', 'nop'][y2])
        if x2 == 2 and y2 >= 4 and z2 <= 3:
            return Insn(a, 2, [['ldi', 'cpi', 'ini', 'outi'], ['ldd', 'cpd', 'ind', 'outd'],
                               ['ldir', 'cpir', 'inir', 'otir'], ['lddr', 'cpdr', 'indr', 'otdr']][y2 - 4][z2])
        raise ValueError(f'{a:04X}: ED {o2:02X}')
    if op == 0xDD:                       # IX — только в склейке (опрос клавиатуры): нужные формы
        o2 = b1
        d = m[(a + 2) & 0xFFFF]
        d = d - 256 if d > 127 else d
        ix = f'(ix{d:+d})'
        nn2 = m[(a + 2) & 0xFFFF] | m[(a + 3) & 0xFFFF] << 8
        if o2 == 0xE5: return Insn(a, 2, 'push', ['ix'])
        if o2 == 0xE1: return Insn(a, 2, 'pop', ['ix'])
        if o2 == 0x21: return Insn(a, 4, 'ld', ['ix', h16(nn2)], imm=nn2, immpos=2)
        if o2 == 0x23: return Insn(a, 2, 'inc', ['ix'])
        if o2 == 0x2B: return Insn(a, 2, 'dec', ['ix'])
        if o2 & 0xCF == 0x09: return Insn(a, 2, 'add', ['ix', ['bc', 'de', 'ix', 'sp'][o2 >> 4 & 3]])
        if o2 in (0x34, 0x35): return Insn(a, 3, 'inc' if o2 == 0x34 else 'dec', [ix])
        if o2 == 0x36: return Insn(a, 4, 'ld', [ix, h8(m[(a + 3) & 0xFFFF])])
        if o2 & 0xC7 == 0x46 and o2 != 0x76: return Insn(a, 3, 'ld', [R[o2 >> 3 & 7], ix])
        if o2 & 0xF8 == 0x70 and o2 != 0x76: return Insn(a, 3, 'ld', [ix, R[o2 & 7]])
        if o2 & 0xC7 == 0x86:
            mn, _, o = (ALU[o2 >> 3 & 7] + ix).partition(' ')
            return Insn(a, 3, mn, o.split(','))
        raise ValueError(f'{a:04X}: DD {o2:02X} — форма IX не поддержана')
    if op == 0xFD:
        raise ValueError(f'{a:04X}: префикс FD (IY)')
    if x == 0:
        if z == 0:
            if y == 0: return Insn(a, 1, 'nop')
            if y == 1: return Insn(a, 1, 'ex', ['af', "af'"])
            if y == 2: return Insn(a, 2, 'djnz', [h16(rel())], 'jpc', rel())
            if y == 3: return Insn(a, 2, 'jr', [h16(rel())], 'jp', rel())
            return Insn(a, 2, 'jr', [CC[y - 4], h16(rel())], 'jpc', rel())
        if z == 1:
            if q == 0: return Insn(a, 3, 'ld', [RP[p], h16(nn)], imm=nn, immpos=1)
            return Insn(a, 1, 'add', ['hl', RP[p]])
        if z == 2:
            if q == 0:
                if p == 0: return Insn(a, 1, 'ld', ['(bc)', 'a'])
                if p == 1: return Insn(a, 1, 'ld', ['(de)', 'a'])
                if p == 2: return Insn(a, 3, 'ld', [f'({h16(nn)})', 'hl'], imm=nn, immpos=1)
                return Insn(a, 3, 'ld', [f'({h16(nn)})', 'a'], imm=nn, immpos=1)
            if p == 0: return Insn(a, 1, 'ld', ['a', '(bc)'])
            if p == 1: return Insn(a, 1, 'ld', ['a', '(de)'])
            if p == 2: return Insn(a, 3, 'ld', ['hl', f'({h16(nn)})'], imm=nn, immpos=1)
            return Insn(a, 3, 'ld', ['a', f'({h16(nn)})'], imm=nn, immpos=1)
        if z == 3: return Insn(a, 1, 'dec' if q else 'inc', [RP[p]])
        if z == 4: return Insn(a, 1, 'inc', [R[y]])
        if z == 5: return Insn(a, 1, 'dec', [R[y]])
        if z == 6: return Insn(a, 2, 'ld', [R[y], h8(b1)])
        return Insn(a, 1, X0Z7[y])
    if x == 1:
        if op == 0x76: return Insn(a, 1, 'halt', kind='halt')
        return Insn(a, 1, 'ld', [R[y], R[z]])
    if x == 2:
        t = ALU[y] + R[z]
        mn, _, o = t.partition(' ')
        return Insn(a, 1, mn, o.split(','))
    if z == 0: return Insn(a, 1, 'ret', [CC[y]], 'retc')
    if z == 1:
        if q == 0: return Insn(a, 1, 'pop', [RP2[p]])
        return [Insn(a, 1, 'ret', kind='ret'), Insn(a, 1, 'exx'), Insn(a, 1, 'jp', ['(hl)'], 'jpind'),
                Insn(a, 1, 'ld', ['sp', 'hl'])][p]
    if z == 2: return Insn(a, 3, 'jp', [CC[y], h16(nn)], 'jpc', nn)
    if z == 3:
        if y == 0: return Insn(a, 3, 'jp', [h16(nn)], 'jp', nn)
        if y == 2: return Insn(a, 2, 'out', [f'({h8(b1)})', 'a'])
        if y == 3: return Insn(a, 2, 'in', ['a', f'({h8(b1)})'])
        return Insn(a, 1, ['', '', '', '', 'ex', 'ex', 'di', 'ei'][y],
                    [['(sp)', 'hl'], ['de', 'hl']][y - 4] if y in (4, 5) else [])
    if z == 4: return Insn(a, 3, 'call', [CC[y], h16(nn)], 'callc', nn)
    if z == 5:
        if q == 0: return Insn(a, 1, 'push', [RP2[p]])
        return Insn(a, 3, 'call', [h16(nn)], 'call', nn)
    if z == 6:
        t = ALU[y] + h8(b1)
        mn, _, o = t.partition(' ')
        return Insn(a, 2, mn, o.split(','))
    return Insn(a, 1, 'rst', [h8(y * 8)], 'rst', y * 8)
