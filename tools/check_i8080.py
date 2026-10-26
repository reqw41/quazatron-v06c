#!/usr/bin/env python3
"""Гейт i8080-чистоты по листингу sjasmplus (--lst). Падает, если инструкция эмитит Z80-only опкод."""
import re, sys
ILLEGAL = {0x08:"EX AF,AF'",0x10:"DJNZ",0x18:"JR",0x20:"JR NZ",0x28:"JR Z",0x30:"JR NC",0x38:"JR C",
           0xCB:"CB-prefix",0xD9:"EXX",0xDD:"DD-prefix(IX)",0xED:"ED-prefix",0xFD:"FD-prefix(IY)"}
DATA_RE = re.compile(r'^\s*(?:[A-Za-z_.@][\w.@]*:\s*)?(db|dw|ds|dc|dz|dm|defb|defw|defs|byte|word|block|incbin)\b', re.I)
hits = 0; insns = 0
for path in sys.argv[1:]:
    for raw in open(path, encoding='latin-1'):
        if '\t' not in raw: continue            # строка-продолжение данных (без исходника)
        left, src = raw.rstrip('\n').split('\t', 1)
        m = re.match(r'^\s*\d+[+]*\s+([0-9A-F]{4})\s+((?:[0-9A-F]{2}\s*)+)$', left)
        if not m: continue
        body = re.sub(r'^\s*[A-Za-z_.@][\w.@]*:\s*', '', src).strip()
        if not body or body.startswith(';') or DATA_RE.match(src): continue
        first = int(m.group(2).split()[0], 16)
        insns += 1
        if first in ILLEGAL:
            hits += 1
            if hits <= 40: print(f"  {m.group(1)}: {ILLEGAL[first]:18s} {src.strip()[:70]}")
print(f"check_i8080: инструкций {insns}, Z80-only {hits}")
sys.exit(1 if hits else 0)
