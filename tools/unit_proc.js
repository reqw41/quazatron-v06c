#!/usr/bin/env node
// Сверка одной процедуры сборки i8080 (своей, port/i8080.asm) с Z80-образом на случайной памяти и переменных:
// регистры A, BC, DE, HL, SP и память данных (поле, полосы, плоскость, переменные AFxx) после возврата.   node tools/unit_proc.js bg_restore|spr_row4 [проверок]
"use strict";
const fs = require("fs"), vm = require("vm"), path = require("path");
const base = process.env.V06JS || path.join(require("os").homedir(), "projects/vector06js");
const ROOT = path.join(__dirname, "..");
const WHAT = process.argv[2], N = +process.argv[3] || 2000;
const zimg = new Uint8Array(fs.readFileSync(`${ROOT}/build/port/quaz_z80.r0m`));
const iimg = new Uint8Array(fs.readFileSync(`${ROOT}/build/port8080/quaz_8080.r0m`));
const sld = (f) => { const L = {}; for (const l of fs.readFileSync(f, "latin1").split("\n")) { const p = l.split("|"); if (p.length >= 8 && p[6] === "L") { const q = p[7].split(","); const n = q[1] + (q[2] ? "." + q[2] : ""); if (!(n in L)) L[n] = +p[5]; } } return L; };
const L8 = sld(`${ROOT}/build/port8080/quaz_8080.sld`), GZ = sld(`${ROOT}/build/port/glue.sld`);
const Z80 = require(base + "/Z80_v06.js");
const zm = new Uint8Array(65536), im = new Uint8Array(65536);
const zc = new Z80({ mem_read: a => zm[a & 0xFFFF], mem_write: (a, v) => { zm[a & 0xFFFF] = v & 255; }, io_read: () => 0xFF, io_write() {} });
const g = { alert: s => { throw new Error(s); } }; g.window = g; const ctx = vm.createContext(g);
vm.runInContext(fs.readFileSync(base + "/i8080-js/i8080.js", "utf8"), ctx);
const ic = new ctx.I8080({ read: a => im[a & 0xFFFF], write: (a, v) => { im[a & 0xFFFF] = v & 255; } }, { input: () => 0xFF, output() {}, interrupt() {} });
let rs = 99; const rnd = () => { rs ^= rs << 13; rs >>>= 0; rs ^= rs >>> 17; rs ^= rs << 5; rs >>>= 0; return rs; };
const STOP = 0xFFF0, SP = 0x6100;
const T = {
  bg_restore: { z: 0xC20D, i: L8.bg_restore_80, setup(m, r) {   // поле 2300 (32 × 152), полоса — 2080 или E700
      const buf = r.buf; m[0xAF12] = buf & 255; m[0xAF13] = buf >> 8;
      m[0xAF14] = r.col; m[0xAF15] = r.row; m[0xAF17] = r.h; }, gen() {
      const neg = rnd() % 3 === 0; return { buf: rnd() & 1 ? 0x2080 : 0xE700, col: [0, 5, 27, 28, 0xFD, 0xFF][rnd() % 6], row: neg ? 256 - 1 - rnd() % 40 : rnd() % 150, h: 1 + rnd() % 60, regs: {} }; } },
  xf_rowaddr: { z: 0xCBEE, i: L8.xf_rowaddr_80, adead: true, setup(m, r) {   // ряд/ячейка захвата: шаг ±1, первый ряд — любой адрес экрана; A после — мёртв
      const w = (a, v) => { m[a] = v & 255; m[a + 1] = v >> 8 & 255; };
      w(0xCEBC, r.dir); w(0xCECA, r.scr0); m[0xCEB9] = r.cells; m[0xCEB8] = r.rows; }, gen() {
      return { dir: rnd() & 1 ? 1 : 0xFFFF, scr0: 0x4000 + (rnd() & 0x17FF), cells: 1 + rnd() % 3, rows: rnd() % 4 ? 1 + rnd() % 12 : [0, 13, 14, 0xFF][rnd() % 4], regs: { h: rnd() & 255, l: rnd() & 255 } }; } },
  spr_row4: { z: GZ["vec_spr_flush.row4"], i: L8.spr_row4_80, setup() {}, gen() {
      const n = 1 + rnd() % 60; return { regs: { h: 0xE7, l: rnd() & 0x7F, d: 0x80 + rnd() % 28, e: 223 - rnd() % 100, b: n, c: 4 } }; } },
}[WHAT];
let bad = 0;
for (let n = 0; n < N; n++) {
  zm.set(zimg); im.set(iimg);   // данные (поле, полосы, плоскость) — случайные, код — свой у каждой сборки
  for (const [x, y] of [[0x2000, 0x4000], [0x8000, 0xA000], [0xE700, 0xE800]]) for (let a = x; a < y; a++) zm[a] = im[a] = rnd() & 255;
  const r = T.gen(); T.setup(zm, r); T.setup(im, r);
  for (const m of [zm, im]) { m[SP - 2] = STOP & 255; m[SP - 1] = STOP >> 8; }
  const R = { a: 0x11, b: 0x22, c: 0x33, d: 0x44, e: 0x55, h: 0x66, l: 0x77, ...r.regs };
  const s = zc.getState(); Object.assign(s, R, { sp: SP - 2, pc: T.z, iff1: 1, iff2: 1 }); zc.setState(s);
  let k = 0; while (zc.getState().pc !== STOP) { zc.run_instruction(); if (++k > 1e6) throw new Error("Z80 не вернулся"); }
  ic.regs = [R.b, R.c, R.d, R.e, R.h, R.l, 0, R.a]; ic.sp = SP - 2; ic.pc = T.i; ic.iff = true;
  k = 0; while (ic.pc !== STOP) { ic.instruction(); if (++k > 1e6) throw new Error("i8080 не вернулся"); }
  const z = zc.getState(), w = { a: ic.regs[7], b: ic.regs[0], c: ic.regs[1], d: ic.regs[2], e: ic.regs[3], h: ic.regs[4], l: ic.regs[5] };
  const why = ["a", "b", "c", "d", "e", "h", "l"].filter(x => !(T.adead && x === "a") && z[x] !== w[x]).map(x => `${x} ${z[x].toString(16)}/${w[x].toString(16)}`);
  if (z.sp !== ic.sp) why.push("sp"); if (!ic.iff) why.push("iff");
  let nd = 0, first = -1; for (const [x, y] of [[0x2000, 0x4000], [0x8000, 0xA000], [0xAF00, 0xB000], [0xCEB8, 0xCEE0], [0xE700, 0xE800]]) for (let a = x; a < y; a++) { if (zm[a] !== im[a]) { nd++; if (first < 0) first = a; } }
  if (nd) why.push(`память ${nd} байт с ${first.toString(16)}`);
  if (why.length && bad++ < 8) console.log(JSON.stringify(r), why.join(", "));
}
console.log(`${WHAT}: проверок ${N}, расхождений ${bad}`);
