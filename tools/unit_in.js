#!/usr/bin/env node
// Проверка перевода опроса клавиатуры (rst 10h — вместо in a,(c) ZX): сборка Z80 и i8080 на случайных матрицах Вектора
// (порты 2/3 и копия vec_kb), рядах B (в том числе 00 — все ряды) и портах C (FE — клавиатура, 1F — Kempston). Сверка A и флагов.
//   node tools/unit_in.js [проверок] [--ru]
"use strict";
const fs = require("fs"), vm = require("vm"), path = require("path");
const base = process.env.V06JS || path.join(require("os").homedir(), "projects/vector06js");
const ROOT = path.join(__dirname, "..");
const N = +process.argv[2] || 20000, SUF = process.argv.includes("--ru") ? "_ru" : "";
const L8 = {}; for (const l of fs.readFileSync(`${ROOT}/build/port8080/quaz_8080${SUF}.sld`, "latin1").split("\n")) { const p = l.split("|"); if (p.length >= 8 && p[6] === "L") { const n = p[7].split(",")[1]; if (n && !(n in L8)) L8[n] = +p[5]; } }
const zimg = new Uint8Array(fs.readFileSync(`${ROOT}/build/port/quaz_z80${SUF}.r0m`));
const iimg = new Uint8Array(fs.readFileSync(`${ROOT}/build/port8080/quaz_8080${SUF}.r0m`));
const VEC_KB = (() => { for (const l of fs.readFileSync(ROOT + "/build/port/glue.sld", "latin1").split("\n")) {
  const p = l.split("|"); if (p.length >= 8 && p[6] === "L" && p[7].split(",")[1] === "vec_kb") return +p[5]; } })();
const matrix = new Uint8Array(8);
const kbRead = pa => { let r = 0; const row = ~pa & 255; for (let i = 0; i < 8; i++) if (row >> i & 1) r |= matrix[i]; return ~r & 255; };
const mkIO = () => { let pa = 0xFF; return { read: p => (p & 255) === 2 ? kbRead(pa) : 0xFF, write: (p, v) => { if ((p & 255) === 3) pa = v; } }; };
const Z80 = require(base + "/Z80_v06.js");
const zm = new Uint8Array(zimg), zio = mkIO();
const zc = new Z80({ mem_read: a => zm[a & 0xFFFF], mem_write: (a, v) => { zm[a & 0xFFFF] = v & 255; }, io_read: p => zio.read(p), io_write: (p, v) => zio.write(p, v) });
const g = { alert: s => { throw new Error(s); } }; g.window = g; const ctx = vm.createContext(g);
vm.runInContext(fs.readFileSync(base + "/i8080-js/i8080.js", "utf8"), ctx);
const im = new Uint8Array(iimg), iio = mkIO();
const ic = new ctx.I8080({ read: a => im[a & 0xFFFF], write: (a, v) => { im[a & 0xFFFF] = v & 255; } }, { input: p => iio.read(p), output: (p, v) => iio.write(p, v), interrupt() {} });
let rs = 99; const rnd = () => { rs ^= rs << 13; rs >>>= 0; rs ^= rs >>> 17; rs ^= rs << 5; rs >>>= 0; return rs; };
const STOP = 0xFFF0, SP = 0x6100;
let bad = 0;
for (let n = 0; n < N; n++) {
  for (let i = 0; i < 8; i++) matrix[i] = (rnd() & 3) === 0 ? rnd() & 255 : 0;
  for (const m of [zm, im]) for (let i = 0; i < 8; i++) m[VEC_KB + i] = matrix[i];
  const B = [0x00, 0xFE, 0xFD, 0xFB, 0xF7, 0xEF, 0xDF, 0xBF, 0x7F, rnd() & 255][rnd() % 10], C = (rnd() & 7) === 0 ? 0x1F : 0xFE;
  const A0 = rnd() & 255, D = rnd() & 255, E = rnd() & 255, H = rnd() & 255, L = rnd() & 255;
  for (const m of [zm, im]) { m[SP - 2] = STOP & 255; m[SP - 1] = STOP >> 8; }
  const s = zc.getState(); Object.assign(s, { a: A0, b: B, c: C, d: D, e: E, h: H, l: L, sp: SP - 2, pc: 0x10, iff1: 0, iff2: 0 }); zc.setState(s);
  let k = 0; while (zc.getState().pc !== STOP) { zc.run_instruction(); if (++k > 100000) throw new Error("Z80 не вернулся"); }
  // i8080: ряды ZX считает прерывание (kbd_scan_80 -> kb_rebuild80) — пересчитать из записанной vec_kb
  ic.sp = SP - 2; ic.pc = L8.kb_rebuild80; ic.iff = false; k = 0; while (ic.pc !== STOP) { ic.instruction(); if (++k > 200000) throw new Error("kb_rebuild80 не вернулся"); }
  im[SP - 2] = STOP & 255; im[SP - 1] = STOP >> 8;
  ic.regs = [B, C, D, E, H, L, 0, A0]; ic.sp = SP - 2; ic.pc = 0x10; ic.iff = false;
  k = 0; while (ic.pc !== STOP) { ic.instruction(); if (++k > 200000) throw new Error("i8080 не вернулся"); }
  const z = zc.getState(), r = { a: ic.regs[7], b: ic.regs[0], c: ic.regs[1], d: ic.regs[2], e: ic.regs[3], h: ic.regs[4], l: ic.regs[5] };
  const diff = ["a", "b", "c", "d", "e", "h", "l"].filter(x => z[x] !== r[x]);
  if (z.sp !== ic.sp) diff.push("sp");
  if (diff.length && bad++ < 10) console.log(`B=${B.toString(16)} C=${C.toString(16)} матрица ${[...matrix].map(x => x.toString(16)).join(" ")}: ${diff.map(x => `${x} Z80 ${(z[x] ?? z.sp).toString(16)} i8080 ${(r[x] ?? ic.sp).toString(16)}`).join(", ")}`);
}
console.log(`проверок ${N}, расхождений ${bad}`);
