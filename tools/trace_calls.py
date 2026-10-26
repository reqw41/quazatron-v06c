#!/usr/bin/env python3
"""Дерево вызовов по трассе MAME: call/rst/ret, с включающими тактами.
  python3 tools/trace_calls.py prof.tr [макс.глубина=4] [мин.тактов=2000] [от_такта] [до_такта]"""
import sys, re
fn = sys.argv[1]; maxd = int(sys.argv[2]) if len(sys.argv) > 2 else 4
minc = int(sys.argv[3]) if len(sys.argv) > 3 else 2000
t_from = int(sys.argv[4]) if len(sys.argv) > 4 else 0
t_to = int(sys.argv[5]) if len(sys.argv) > 5 else 1 << 62
stack = []          # [цель, такт входа, sp-глубина, строки детей]
root = ['ROOT', None, []]
cur = root
out_nodes = []
prev = None
for line in open(fn, encoding='latin-1'):
    m = re.match(r'(\d+),([0-9A-F]{4}): (\S+)\s*(.*)', line)
    if not m: continue
    t, pc, op, arg = int(m[1]), int(m[2], 16), m[3], m[4]
    if t < t_from: continue
    if t > t_to: break
    if prev:
        pt, pop, parg, ppc = prev
        if pop == 'call' or pop == 'rst':
            # вход выполнен, если PC != следующей команде (условный call мог не сработать — грубо: PC далеко)
            node = [pc, pt, []]
            cur[2].append(node); stack.append(cur); cur = node
        elif pop.startswith('ret') or pop == 'reti':
            if stack and (pop in ('ret', 'reti') or abs(pc - ppc) > 3):
                cur.append(t); cur = stack.pop()
    prev = (t, op, arg, pc)
def show(n, d):
    for c in n[2]:
        dur = (c[3] if len(c) > 3 else t) - c[1]
        if dur >= minc:
            print('  ' * d + f'{c[0]:04X} {dur}')
            if d + 1 < maxd: show(c, d + 1)
show(root, 0)
