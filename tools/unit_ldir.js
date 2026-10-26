#!/usr/bin/env node
// Проверка z_ldir / z_lddr сборки i8080 (port/i8080.asm) на случайных копиях, в том числе перекрытых: память и регистры
// против побайтного ldir/lddr Z80.   node tools/unit_ldir.js [проверок]
"use strict";
const fs = require("fs"), vm = require("vm"), path = require("path");
const base = process.env.V06JS || path.join(require("os").homedir(), "projects/vector06js");
const ROOT = path.join(__dirname, "..");
const N = +process.argv[2] || 3000;
const img = new Uint8Array(fs.readFileSync(`${ROOT}/build/port8080/quaz_8080.r0m`));
const L8 = {}; for (const l of fs.readFileSync(`${ROOT}/build/port8080/quaz_8080.sld`, "latin1").split("\n")) { const p = l.split("|"); if (p.length >= 8 && p[6] === "L") { const n = p[7].split(",")[1]; if (n && !(n in L8)) L8[n] = +p[5]; } }
const g = { alert: s => { throw new Error(s); } }; g.window = g; const ctx = vm.createContext(g);
vm.runInContext(fs.readFileSync(base + "/i8080-js/i8080.js", "utf8"), ctx);
const m = new Uint8Array(65536);
const ic = new ctx.I8080({ read: a => m[a & 0xFFFF], write: (a, v) => { m[a & 0xFFFF] = v & 255; } }, { input: () => 0xFF, output() {}, interrupt() {} });
let rs = 7; const rnd = () => { rs ^= rs << 13; rs >>>= 0; rs ^= rs >>> 17; rs ^= rs << 5; rs >>>= 0; return rs; };
const STOP = 0xFFF0, SP = 0x6100, A0 = 0x7000;   // область копий 7000-7FFF (вне добавок и стека)
let bad = 0;
for (let n = 0; n < N; n++) {
  m.set(img);
  for (let a = A0; a < A0 + 0x1000; a++) m[a] = rnd() & 255;
  const back = rnd() & 1, len = [1, 2, 5, 6, 7, 63, 64, 65, 127, 128, 200, 1000][rnd() % 12] + (rnd() & 1);
  const near = rnd() % 4 === 0;
  let src = A0 + 0x400 + rnd() % 0x400, dst = near ? src + [1, -1, 2, -2, 31, -32][rnd() % 6] : A0 + 0x400 + rnd() % 0x400;
  if (back) { src += len; dst += len; }
  const ref = new Uint8Array(m); let s = src, d = dst;
  for (let k = 0; k < len; k++) { ref[d] = ref[s]; if (back) { s--; d--; } else { s++; d++; } }
  m[SP - 2] = STOP & 255; m[SP - 1] = STOP >> 8; ref[SP - 2] = m[SP - 2]; ref[SP - 1] = m[SP - 1];
  const A = rnd() & 255;
  ic.regs = [len >> 8, len & 255, dst >> 8, dst & 255, src >> 8, src & 255, 0, A]; ic.sp = SP - 2; ic.pc = back ? L8.z_lddr : L8.z_ldir; ic.iff = true;
  let k = 0; while (ic.pc !== STOP) { ic.instruction(); if (++k > 1e6) throw new Error(`не вернулся: ${back ? "lddr" : "ldir"} ${src.toString(16)}->${dst.toString(16)} ×${len}, pc ${ic.pc.toString(16)} sp ${ic.sp.toString(16)}`); }
  const r = ic.regs, why = [];
  if ((r[0] << 8 | r[1]) !== 0) why.push("BC");
  if ((r[2] << 8 | r[3]) !== (d & 0xFFFF)) why.push(`DE ${(r[2] << 8 | r[3]).toString(16)} ≠ ${d.toString(16)}`);
  if ((r[4] << 8 | r[5]) !== (s & 0xFFFF)) why.push(`HL ${(r[4] << 8 | r[5]).toString(16)} ≠ ${s.toString(16)}`);
  if (r[7] !== A) why.push("A"); if (ic.sp !== SP) why.push("SP"); if (!ic.iff) why.push("iff");
  for (let a = A0; a < A0 + 0x1000; a++) if (m[a] !== ref[a]) { why.push(`память ${a.toString(16)}`); break; }
  if (why.length && bad++ < 10) console.log(`${back ? "lddr" : "ldir"} ${src.toString(16)}->${dst.toString(16)} ×${len}: ${why.join(", ")}`);
}
console.log(`проверок ${N}, расхождений ${bad}`);
