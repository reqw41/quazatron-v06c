#!/usr/bin/env node
// Покомандная сверка перевода i8080 (tools/port8080.py) с образом Z80, из которого он сделан: оба процессора на плоской
// памяти 64К без железа Вектора (порты читаются как 0xFF, прерывание — каждые QZ_XC_IRQ команд Z80, если разрешено).
// Точки встречи — метки zXXXX (pcmap.txt): Z80 стоит на XXXX, i8080 — на её переводе. Сверяются A, BC, DE, HL, SP,
// флаги S/Z/C (QZ_XC_FLAGS=1) и записанная с прошлой встречи память (кроме кода, стека и ячеек port/i8080.asm).
// Участки Z80 без меток (blit_tile — свой код i8080) проходятся целиком, регистры после них берутся у Z80.
//   node tools/xcheck80.js [команд Z80, по умолчанию 5e6] [--ru]
"use strict";
const fs = require("fs"), vm = require("vm"), path = require("path");
const base = process.env.V06JS || path.join(require("os").homedir(), "projects/vector06js");
const ROOT = path.join(__dirname, "..");
const N = +process.argv[2] || 5e6, RU = process.argv.includes("--ru"), SUF = RU ? "_ru" : "";
const IRQ = +(process.env.QZ_XC_IRQ || 20000), FLAGS = !!process.env.QZ_XC_FLAGS;
const zimg = new Uint8Array(fs.readFileSync(`${ROOT}/build/port/quaz_z80${SUF}.r0m`));
const iimg = new Uint8Array(fs.readFileSync(`${ROOT}/build/port8080/quaz_8080${SUF}.r0m`));
const map = new Map(), rev = new Map();
for (const l of fs.readFileSync(`${ROOT}/build/port8080/pcmap${SUF}.txt`, "utf8").trim().split("\n")) {
  const [a, b] = l.split(" ").map(x => parseInt(x, 16)); map.set(a, b); if (!rev.has(b)) rev.set(b, a); }
const XR = fs.readFileSync(`${ROOT}/build/port8080/layout${SUF}.txt`, "utf8").trim().split(" ").map(x => parseInt(x, 16));   // пары начало конец добавок
const inX = a => { for (let k = 0; k < XR.length; k += 2) if (a >= XR[k] && a < XR[k + 1]) return true; return false; };
// не сверять: код обеих сборок (байты команд), стек, ячейки i8080
const nocmp = new Uint8Array(0x10000);
for (const l of fs.readFileSync(`${ROOT}/build/port8080/quaz_8080${SUF}.lst`, "latin1").split("\n")) {
  const m = l.match(/^\s*\d+\+?\s+([0-9A-F]{4})\s((?:[0-9A-F]{2} ?)+)\s*\t(.*)$/);
  if (m && !/^\s*(incbin|db|dw|ds)\b/i.test(m[3])) { const a = parseInt(m[1], 16); for (let k = 0; k < m[2].trim().split(" ").length; k++) nocmp[a + k] = 1; } }
for (const [a] of map) nocmp[a] = 1;                                   // начала команд Z80 (байты команд Z80 — ниже)
for (let a = 0; a < 0x10000; a++) if (inX(a)) nocmp[a] = 1;
const XC = Object.fromEntries(fs.readFileSync(`${ROOT}/build/port8080/xc${SUF}.txt`, "utf8").trim().split("\n").map(l => { const [k, ...v] = l.split(" "); return [k, v]; }));
for (const r of XC.code) { const [x, y] = r.split("-").map(v => parseInt(v, 16)); for (let a = x; a < y; a++) nocmp[a] = 1; }
for (const r of XC.nocmp || []) { const [x, y] = r.split("-").map(v => parseInt(v, 16)); for (let a = x; a < y; a++) nocmp[a] = 1; }
const REGDIFF = new Set(XC.regdiff.map(v => parseInt(v, 16)));
const RETPOP = new Set(XC.retpop.map(v => parseInt(v, 16)));
let relax = 0;
const SKIPRET = new Set((XC.skipret || []).map(v => parseInt(v, 16)));
const ADEAD = new Set((XC.adead || []).map(v => parseInt(v, 16)));   // A мёртв (перевод его не сохраняет) — берётся у Z80
const SKIP = new Map(XC.skip.map(v => v.split(":").map(x => parseInt(x, 16))));
for (let a = 0x6100; a < 0x61A9; a++) nocmp[a] = 1;
const syms = []; for (const l of fs.readFileSync(ROOT + "/docs/symbols.txt", "utf8").split("\n")) {
  const m = l.match(/^([0-9A-Fa-f]{4})\s+(\w+)/); if (m) syms.push([parseInt(m[1], 16), m[2]]); }
syms.sort((a, b) => a[0] - b[0]);
const RL = fs.readFileSync(ROOT + "/build/port/reloc.txt", "utf8").trim().split(/\s+/).map(x => parseInt(x, 16));
const zx = a => (a >= RL[2] && a < RL[2] + RL[1] - RL[0]) ? a - RL[2] + RL[0] : a;
const symName = a => { const z = zx(a); let best = null; for (const [s, n] of syms) { if (s <= z) best = [s, n]; else break; }
  return (best && z >= 0x2000 ? `${best[1]}+${(z - best[0]).toString(16)}` : "") + `(${a.toString(16)})`; };

// ---- клавиатура Вектора (ВВ55: порт 3 — ряды, порт 2 — столбцы); сценарий как у tools/lockstep.js: «4», ENTER, затем
// стрелки и пробел случайно (смена раз в 10..60 кадров); копию матрицы vec_kb склейки пишем на обеих сторонах сразу ----
const VEC_KB = (() => { for (const l of fs.readFileSync(ROOT + "/build/port/glue.sld", "latin1").split("\n")) {
  const p = l.split("|"); if (p.length >= 8 && p[6] === "L" && p[7].split(",")[1] === "vec_kb") return +p[5]; } })();
const matrix = new Uint8Array(8);
let rs = 12345 * 2654435761 >>> 0;
const rnd32 = () => { rs ^= rs << 13; rs >>>= 0; rs ^= rs >>> 17; rs ^= rs << 5; rs >>>= 0; return rs; };
const kbRead = pa => { let r = 0; const row = ~pa & 255; for (let i = 0; i < 8; i++) if (row >> i & 1) r |= matrix[i]; return ~r & 255; };
const mkIO = () => { let pa = 0xFF; return { read: p => (p & 255) === 2 ? kbRead(pa) : 0xFF, write: (p, v) => { if ((p & 255) === 3) pa = v; } }; };
const zio = mkIO(), iio = mkIO();
let kdir = 0, kleft = 0;
function frameInput(f) {
  matrix.fill(0);
  if (f >= 60 && f < 70) matrix[2] |= 0x10;
  if (f >= 120 && f < 130) matrix[0] |= 0x04;
  if (f > 200) { if (--kleft <= 0) { kleft = 10 + rnd32() % 50; kdir = [0, 1, 2, 4, 8, 5, 6, 9, 10, 0][rnd32() % 10]; }
    const k = kdir | ((rnd32() & 3) === 0 ? 0x10 : 0);
    matrix[0] |= (k & 1 ? 0x40 : 0) | (k & 2 ? 0x10 : 0) | (k & 8 ? 0x20 : 0) | (k & 4 ? 0x80 : 0);
    matrix[7] |= k & 0x10 ? 0x80 : 0; }
  for (const m of [zm, im]) { m[VEC_KB] = matrix[0]; m[VEC_KB + 7] = matrix[7]; } }

// ---- Z80 ----
const Z80 = require(base + "/Z80_v06.js");
const zm = new Uint8Array(zimg), zdirty = new Set();
const zc = new Z80({ mem_read: a => zm[a & 0xFFFF], mem_write: (a, v) => { a &= 0xFFFF; zm[a] = v & 255; zdirty.add(a); },
  io_read: p => zio.read(p), io_write: (p, v) => zio.write(p, v) });
{ const s = zc.getState(); s.pc = 0; s.sp = 0x61A5; s.iff1 = s.iff2 = 0; zc.setState(s); }
// Z80: байты команд — тоже не сверять
for (const [a] of map) { /* длины неизвестны здесь: берём по разнице меток не можем — помечаем по ходу исполнения */ }

// ---- i8080 ----
const g = { console, alert: s => { throw new Error(s); } }; g.window = g;
const ctx = vm.createContext(g);
vm.runInContext(fs.readFileSync(base + "/i8080-js/i8080.js", "utf8"), ctx, { filename: "i8080.js" });
const im = new Uint8Array(iimg), idirty = new Set();
const mem = { read: a => im[a & 0xFFFF], write: (a, v) => { a &= 0xFFFF; im[a] = v & 255; idirty.add(a); } };
const io = { input: p => iio.read(p), output: (p, v) => iio.write(p, v), interrupt: () => {} };
const ic = new ctx.I8080(mem, io);
ic.pc = 0; ic.sp = 0x61A5; ic.iff = false;

const R8 = ["b", "c", "d", "e", "h", "l", null, "a"];
// QZ_XC_FROM=снимок i8080 (tools/lockstep.js QZ_LS_DUMPPOLL): обе стороны стартуют с него — данные общие, адреса возврата
// в стеке и PC переводятся обратно в адреса Z80, регистры Z80' и IX — из ячеек port/i8080.asm
if (process.env.QZ_XC_FROM) {
  const st = JSON.parse(fs.readFileSync(process.env.QZ_XC_FROM, "utf8")), d = Buffer.from(st.mem, "base64");
  const codeZ = new Uint8Array(0x10000);
  for (const r of XC.code) { const [x, y] = r.split("-").map(v => parseInt(v, 16)); for (let a = x; a < y; a++) codeZ[a] = 1; }
  for (let a = 0; a < 0x10000; a++) { im[a] = d[a]; if (!codeZ[a] && !inX(a)) zm[a] = d[a]; }
  const L8 = {}; for (const l of fs.readFileSync(`${ROOT}/build/port8080/quaz_8080${SUF}.sld`, "latin1").split("\n")) { const p = l.split("|"); if (p.length >= 8 && p[6] === "L") { const n = p[7].split(",")[1]; if (n && !(n in L8)) L8[n] = +p[5]; } }
  const w = a => d[a] | d[a + 1] << 8, remap = [];
  for (let a = st.sp; a < 0x61A5; a += 2) { const v = w(a); if (rev.has(v)) { const z = rev.get(v); zm[a] = z & 255; zm[a + 1] = z >> 8; remap.push(`${a.toString(16)}:${v.toString(16)}->${z.toString(16)}`); } }
  console.log("стек: " + remap.join(" "));
  for (let i = 0; i < 8; i++) matrix[i] = d[VEC_KB + i];                 // ввод на момент снимка
  R8.forEach((n, i) => { if (n) ic.regs[i] = st[n]; }); ic.retrieve_flags(st.f); ic.sp = st.sp; ic.pc = st.pc; ic.iff = st.iff;
  const zs = zc.getState(); R8.forEach(n => { if (n) zs[n] = st[n]; });
  zs.flags = { S: st.f >> 7 & 1, Z: st.f >> 6 & 1, Y: 0, H: 0, X: 0, P: 0, N: 0, C: st.f & 1 };
  const af2 = w(L8.z_af2), bc2 = w(L8.z_bc2), de2 = w(L8.z_de2), hl2 = w(L8.z_hl2);
  zs.a_prime = af2 >> 8; zs.flags_prime = { S: af2 >> 7 & 1, Z: af2 >> 6 & 1, Y: 0, H: 0, X: 0, P: 0, N: 0, C: af2 & 1 };
  zs.b_prime = bc2 >> 8; zs.c_prime = bc2 & 255; zs.d_prime = de2 >> 8; zs.e_prime = de2 & 255; zs.h_prime = hl2 >> 8; zs.l_prime = hl2 & 255;
  zs.ix = w(L8.z_ix); zs.sp = st.sp; zs.pc = rev.get(st.pc); zs.iff1 = zs.iff2 = st.iff ? 1 : 0; zs.imode = 1;
  if (zs.pc === undefined) throw new Error("PC снимка не на метке");
  zc.setState(zs); console.log(`старт со снимка: Z80 ${symName(zs.pc)}, i8080 ${st.pc.toString(16)}`);
}
const zst = () => { const s = zc.getState(); return { a: s.a, b: s.b, c: s.c, d: s.d, e: s.e, h: s.h, l: s.l, sp: s.sp,
  S: s.flags.S, Z: s.flags.Z, C: s.flags.C }; };
const ist = () => ({ a: ic.regs[7], b: ic.regs[0], c: ic.regs[1], d: ic.regs[2], e: ic.regs[3], h: ic.regs[4], l: ic.regs[5], sp: ic.sp,
  S: ic.sf, Z: ic.zf, C: ic.cf });
const fmt = s => `A${s.a.toString(16)} BC${(s.b << 8 | s.c).toString(16)} DE${(s.d << 8 | s.e).toString(16)} HL${(s.h << 8 | s.l).toString(16)} SP${s.sp.toString(16)} ${s.S ? "S" : "-"}${s.Z ? "Z" : "-"}${s.C ? "C" : "-"}`;
const hist = [], zhist = new Map(); let npolls = 0;
let steps = 0, zsince = 0, warned = new Set();
function zStep() { const p = zc.getState().pc;
  do { zc.run_instruction(); } while (zc.getState().pc === p && zm[p] === 0xED);     // ldir/lddr — до конца
  steps++; zsince++; if (p === 0xB61F) npolls++; if (steps % 97 === 0) zhist.set(p, (zhist.get(p) || 0) + 1);
  hist.push(p); if (hist.length > 30) hist.shift(); }
function fail(msg) {
  console.log(`РАСХОЖДЕНИЕ после ${steps} команд Z80: ${msg}`);
  console.log("последние команды Z80: " + hist.map(symName).join(" "));
  if (process.env.QZ_XC_FULLDIFF) { const d = []; for (let a = 0; a < 65536; a++) if (!nocmp[a] && zm[a] !== im[a]) d.push(a);   // все отличия данных
    console.log(`отличий данных ${d.length}: ` + d.slice(0, 40).map(a => `${a.toString(16)} ${zm[a].toString(16)}/${im[a].toString(16)}`).join(", ")); }
  process.exit(1); }
const t0 = Date.now();
let zpc = 0, irqs = 0;
while (steps < N) {
  // Z80 до следующей метки
  let excursion = false;
  const skipTo = SKIP.get(zpc);
  if (SKIPRET.has(zpc)) { const sp0 = zc.getState().sp; do zStep(); while (zc.getState().sp !== ((sp0 + 2) & 0xFFFF) || !map.has(zc.getState().pc)); zpc = zc.getState().pc; excursion = true; }
  else if (skipTo !== undefined) { do zStep(); while (zc.getState().pc !== skipTo); zpc = skipTo; }
  else do { zStep(); zpc = zc.getState().pc; if (!map.has(zpc)) excursion = true; } while (!map.has(zpc) && steps < N);
  const target = map.get(zpc);
  // i8080 до её перевода
  let k = 0;
  while (ic.pc !== target) { ic.instruction(); if (++k > 2000000) fail(`i8080 не дошёл до ${symName(zpc)} (pc ${ic.pc.toString(16)})`); }
  // регистры
  if (ADEAD.has(zpc)) ic.regs[7] = zc.getState().a;
  const zs = zst(), is = ist();
  const bad = ["a", "b", "c", "d", "e", "h", "l", "sp", ...(FLAGS ? ["S", "Z", "C"] : [])].filter(r => (zs[r] ? zs[r] : 0) !== (is[r] ? is[r] : 0));
  if (RETPOP.has(zpc)) relax = 3000;           // в регистре — адрес возврата (у сторон разный): сверка регистров — когда сойдутся
  const badF = ["S", "Z", "C"].filter(r => (zs[r] ? 1 : 0) !== (is[r] ? 1 : 0));
  if (relax) { if (!bad.length && !badF.length) relax = 0; else if (--relax === 0) fail(`регистры не сошлись после адреса возврата (${symName(zpc)}): ${bad.join(",")}`); }
  else if (bad.length) {
    if (excursion || REGDIFF.has(zpc)) { const key = hist[hist.length - 2]; if (!warned.has(key)) { warned.add(key); console.log(`после участка без меток (${symName(zpc)}): регистры ${bad.join(",")} другие — берутся у Z80`); }
      R8.forEach((n, i) => { if (n) ic.regs[i] = zs[n]; }); ic.sp = zs.sp; ic.sf = zs.S ? 1 : 0; ic.zf = zs.Z ? 1 : 0; ic.cf = zs.C ? 1 : 0; }
    else fail(`на ${symName(zpc)}: ${bad.join(",")}\n  Z80  ${fmt(zs)}\n  i8080 ${fmt(is)}`);
  }
  // память
  for (const a of new Set([...zdirty, ...idirty])) {
    if (nocmp[a]) continue;
    if (zm[a] !== im[a]) fail(`память ${symName(a)}: Z80 ${zm[a].toString(16)} i8080 ${im[a].toString(16)} (на ${symName(zpc)})`); }
  zdirty.clear(); idirty.clear();
  // прерывание (одинаково на обеих сторонах, в точке встречи)
  if (zsince >= IRQ && !relax && zc.getState().iff1 && ic.iff) {
    zsince = 0; irqs++; if (!process.env.QZ_XC_FROM) frameInput(irqs);
    zc.interrupt(false, 0xFF);
    // i8080 — сразу в обработчик склейки (обёртка isr80 нужна только для прерывания посреди переведённой команды,
    // а здесь оно приходит между командами; её проверяет tools/lockstep.js)
    ic.iff = false; ic.sp = (ic.sp - 2) & 0xFFFF; mem.write(ic.sp, ic.pc & 255); mem.write(ic.sp + 1, ic.pc >> 8);
    ic.pc = map.get(zimg[0x39] | zimg[0x3A] << 8);
    idirty.clear(); zdirty.clear();
  }
}
console.log(`опросов input_read: ${npolls}; частые места Z80: ` + [...zhist].sort((a, b) => b[1] - a[1]).slice(0, 8).map(([a, n]) => `${symName(a)}×${n}`).join(" "));
console.log(`сверено ${steps} команд Z80, прерываний ${irqs}, ${((Date.now() - t0) / 1000).toFixed(1)} с — расхождений нет`);
