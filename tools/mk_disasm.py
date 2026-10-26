#!/usr/bin/env python3
"""Листинг оригинала ZX: build/quaz.asm (0x61A9-0xEE90), собирается обратно байт в байт.
Код — команды, найденные Ghidra (build/ghidra_code.txt, рекурсивный спуск), плюс покрытие трасс
(build/cov_pcs.txt, build/cov/cov_*.txt); остальное — данные. Имена и комментарии — docs/symbols.txt:
    ADDR  имя  [; комментарий]          (ADDR — 4 hex-цифры)
Строки с # — комментарии файла. Проверка: sjasmplus собирает build/quaz.asm, байты сравниваются с образом.
"""
import glob, os, re, subprocess, sys
LO, HI = 0x61A9, 0xEE90
img = open('orig/zx/quazatron_ram.bin', 'rb').read()
code = bytearray(0x10000)
if os.path.exists('build/ghidra_code.txt'):
    for l in open('build/ghidra_code.txt'):
        a, n, _ = l.split(None, 2)
        a = int(a[4:], 16)
        for i in range(int(n)): code[a + i] = 1
starts = set()
for f in ['build/cov_pcs.txt'] + glob.glob('build/cov/cov_*.txt'):
    for l in open(f):
        l = l.strip()
        if re.fullmatch(r'[0-9A-F]{4}', l): starts.add(int(l, 16))
for a in starts:                      # начало команды из трассы, которого нет у Ghidra — хотя бы 1 байт кода
    code[a] = 1
blocks, cur = [], LO
while cur <= HI:
    t = code[cur]
    e = cur
    while e + 1 <= HI and code[e + 1] == t: e += 1
    blocks.append((cur, e, 'code' if t else 'bytedata'))
    cur = e + 1
os.makedirs('build', exist_ok=True)
with open('build/blocks.txt', 'w') as f:
    for i, (a, b, t) in enumerate(blocks):
        f.write(f'b{i:04d}: start 0x{a:04x} end 0x{b + 1:04x} type {t}\n')
# символы
syms = {}
with open('build/syms_in.txt', 'w') as f:
    if os.path.exists('docs/symbols.txt'):
        for l in open('docs/symbols.txt', encoding='utf-8'):
            l = l.rstrip('\n')
            if not l.strip() or l.lstrip().startswith('#'): continue
            m = re.match(r'\s*([0-9A-Fa-f]{4})\s+([A-Za-z_][\w]*)\s*(?:;\s*(.*))?$', l)
            if not m: sys.exit(f'symbols.txt: не разобрал строку: {l}')
            a, name, com = int(m[1], 16), m[2], m[3]
            syms[name] = a
            f.write(f'{name}: equ 0x{a:04x}' + (f' ; {com}' if com else '') + '\n')
open('build/quaz_body.bin', 'wb').write(img[LO - 0x4000:HI + 1 - 0x4000])
subprocess.run(f'z80dasm -a -l -c -g 0x{LO:04x} -b build/blocks.txt -S build/syms_in.txt -s build/syms_out.txt '
               f'-o build/quaz.asm build/quaz_body.bin', shell=True, check=True, stderr=subprocess.DEVNULL)
# метки границ блоков z80dasm (bNNNN_start/_end) -> имя из symbols.txt по адресу или lXXXXh
bnd = {}
for i, (a, b, t) in enumerate(blocks):
    bnd[f'b{i:04d}_start'] = a; bnd[f'b{i:04d}_end'] = b + 1
byaddr = {v: k for k, v in syms.items()}
txt = open('build/quaz.asm', encoding='latin-1').read()
def ren(m):
    a = bnd[m[1]]
    return byaddr.get(a, f'l{a:04x}h')
txt = re.sub(r'\b(b\d{4}_(?:start|end))\b', ren, txt)
# одно имя могло стать двумя метками на одном адресе: убрать повторное определение
out, seen = [], set()
for line in txt.split('\n'):
    m = re.match(r'^(\w+):\s*$', line)
    if m:
        if m[1] in seen: continue
        seen.add(m[1])
    out.append(line)
open('build/quaz.asm', 'w', encoding='latin-1').write('\n'.join(out))
ncode = sum(b - a + 1 for a, b, t in blocks if t == 'code')
print(f'листинг build/quaz.asm: кода {ncode} байт, блоков {len(blocks)}, имён {len(syms)}')
# обратная сборка
SJ = os.environ.get('SJASMPLUS', os.path.abspath('tools/sjasmplus'))
src = open('build/quaz.asm', encoding='latin-1').read()
# имена вне образа (equ) z80dasm пишет в шапку; sjasmplus их понимает. Обёртка: вывод в файл.
open('build/quaz_rt.asm', 'w', encoding='latin-1').write(
    '\tDEVICE NOSLOT64K\n' + src + f'\n\tSAVEBIN "quaz_rt.bin",0x{LO:04x},{HI - LO + 1}\n')
r = subprocess.run([SJ, '--nologo', '--msg=err', 'quaz_rt.asm'], cwd='build', capture_output=True, text=True)
if r.returncode:
    sys.exit('sjasmplus: ' + (r.stdout + r.stderr)[-2000:])
rt = open('build/quaz_rt.bin', 'rb').read()
orig = img[LO - 0x4000:HI + 1 - 0x4000]
diff = [i for i in range(len(orig)) if rt[i] != orig[i]]
print('обратная сборка: ' + ('байт в байт' if not diff else f'{len(diff)} отличий, первое 0x{LO + diff[0]:04X}'))
sys.exit(1 if diff else 0)
