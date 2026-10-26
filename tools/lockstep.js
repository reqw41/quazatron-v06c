#!/usr/bin/env node
// Покадровая сверка логики: ZX (оригинал) против порта Вектора (Z80), обе машины — ядро Z80_v06.js в одном процессе.
//   node tools/lockstep.js [проходов main_loop] [зерно]
// Одинаковы на обеих машинах: последовательность rnd (результат подменяется в B5B4; вызовы из isr — отдельный поток,
// число прерываний у машин разное), ввод — Kempston по номеру вызова input_read, до игры — меню «4», ENTER, огонь.
// QZ_BLIT=1 — при расхождении показать последние вызовы blit_tile (HL@проход).
// На каждом входе в main_loop сравниваются: t_objs, население, t_deckdroids, переменные AF00-B065, счёт, буфер поля
// (указатели в перенесённое окно сравниваются с поправкой −0x6000). Первое расхождение — с именами из docs/symbols.txt.
"use strict";
const fs = require("fs"), vm = require("vm"), path = require("path"), zipfile = require("zlib");
const base = process.env.V06JS || path.join(require("os").homedir(), "projects/vector06js");
const PASSES = +process.argv[2] || 1000, SEED = +process.argv[3] || 1;
const ROOT = path.join(__dirname, "..");
const syms = []; for (const l of fs.readFileSync(ROOT + "/docs/symbols.txt", "utf8").split("\n")) {
  const m = l.match(/^([0-9A-Fa-f]{4})\s+(\w+)/); if (m) syms.push([parseInt(m[1], 16), m[2]]); }
syms.sort((a, b) => a[0] - b[0]);
const symName = a => { let best = null; for (const [s, n] of syms) { if (s <= a) best = [s, n]; else break; }
  return best ? `${best[1]}+${(a - best[0]).toString(16)}` : a.toString(16); };

// ---------- случайность и ввод (общие) ----------
let rs = SEED * 2654435761 >>> 0;
const rnd32 = () => { rs ^= rs << 13; rs >>>= 0; rs ^= rs >>> 17; rs ^= rs << 5; rs >>>= 0; return rs; };
const RSEQ = Array.from({ length: 1 << 16 }, () => rnd32() & 255);
const ISEQ = Array.from({ length: 1 << 16 }, () => rnd32() & 255);
// Kempston по вызовам input_read (после первого прохода main_loop): направление на 10..60 проходов (или стоять), огонь с вероятностью 1/4
const KEMP = [];
function kempAt(n) {   // сценарий достраивается по требованию (опросов на экранах ожидания — миллионы)
  while (KEMP.length <= n) { const len = 10 + rnd32() % 50, d = rnd32() % 10;
    const dir = [0, 1, 2, 4, 8, 5, 6, 9, 10, 0][d]; for (let i = 0; i < len; i++) KEMP.push(dir | ((rnd32() & 3) === 0 ? 0x10 : 0)); }
  return KEMP[n]; }

function makeSide(name) { return { name, passes: 0, polls: 0, blits: [], rI: 0, iI: 0, inIsr: false, frames: 0, snaps: null }; }
function rndHook(side, getA, setA) {
  // в B5B4 (после xor (hl)) — подмена A
  const v = side.inIsr ? ISEQ[side.iI++ & 0xFFFF] : RSEQ[side.rI++ & 0xFFFF];
  setA(v);
}

// ---------- ZX ----------
const Z80 = require(base + "/Z80_v06.js");
const zmem = new Uint8Array(0x10000), zWrote = new Uint8Array(0x10000);
zmem.set(fs.readFileSync(ROOT + "/build/port/zxrom_0000.bin"), 0);
zmem.set(fs.readFileSync(ROOT + "/orig/zx/quazatron_ram.bin"), 0x4000);
// CIRCUIT (карточка части в пульте): порт берёт узор не из ПЗУ 0400–052B, а из неизменной графики палуб (9700–982B)
zmem.set(zmem.slice(0x9700, 0x982C), 0x0400);
const CIRC0 = Buffer.from(zmem.slice(0x9700, 0x982C));
process.on("exit", () => { if (Buffer.compare(CIRC0, Buffer.from(zmem.slice(0x9700, 0x982C)))) console.log("!! графика 9700–982B менялась"); });
const ZX = makeSide("ZX"); let zkeys = { F7: 0xFF, BF: 0xFF }, zkemp = 0;
const zcore = {
  mem_read: a => zmem[a & 0xFFFF], mem_write: (a, v) => { a &= 0xFFFF; if (a >= 0x4000) { zmem[a] = v & 255; zWrote[a] = 1; } },
  io_read: p => { const lo = p & 255, hi = p >> 8 & 255;
    if (lo === 0x1F) return zkemp;
    if (lo === 0xFE) { let r = 0xFF; if (!(hi & 0x08)) r &= zkeys.F7; if (!(hi & 0x40)) r &= zkeys.BF; return r; }
    return 0xFF; },
  io_write: () => {} };
const zcpu = new Z80(zcore);
{ const st = zcpu.getState(); st.pc = 0xDE70; st.sp = 0x61A5; st.iff1 = 0; st.iff2 = 0; zcpu.setState(st); }

// ---------- Вектор ----------
const g = {}; g.window = g; g.document = { createElement: () => fc(), getElementById: () => fc() };
function fcx() { return { createImageData: () => ({ data: new Uint8ClampedArray(4) }), putImageData() {}, getImageData: () => ({ data: new Uint8ClampedArray(4) }), fillRect() {}, drawImage() {} }; }
function fc() { return { width: 0, height: 0, style: {}, getContext: () => fcx() }; }
g.requestAnimationFrame = () => 0; g.setTimeout = () => 0; g.print = () => 0;
g.console = { log() {}, debug() {}, warn() {}, error() {}, info() {} };
const ctx = vm.createContext(g);
// QZ_CPU=8080 — сборка i8080 (tools/port8080.py): процессор Вектора i8080, адреса команд через pcmap.txt
const I80 = process.env.QZ_CPU === "8080", I80SUF = process.env.QZ_LS_RU ? "_ru" : "";
for (const f of ["i8080-js/i8080_trace.js", "i8080-js/i8080_disasm.js", "i8080-js/i8080.js", "Z80_v06.js", ...(I80 ? [] : ["z80_adapter.js"]),
  "src/fili.js", "src/ay.js", "src/fd1793.js", "src/fddimage.js", "src/i8253.js", "src/io.js", "src/keyboard.js", "src/memory.js",
  "src/sound.js", "src/tv.js"]) vm.runInContext(fs.readFileSync(base + "/" + f, "utf8"), ctx, { filename: f });
const memory = new ctx.Memory(), keyboard = new ctx.Keyboard(), timer = new ctx.I8253(), ay = new ctx.AY(),
  floppy = new (ctx.Floppy().FD1793)(), io = new ctx.IO(keyboard, timer, memory, ay, floppy);
const vcpu = new ctx.I8080(memory, io), v06c = new ctx.Vector06c(vcpu, memory, io, ay, { advance() {}, sample: 0, reset() {} });
v06c.bmp = new Uint32Array(576 * 288); v06c.displayFrame = () => {}; v06c.check_breakpoint = () => false; v06c.dbg = null;
memory.init_from_array(new Uint8Array(fs.readFileSync(process.env.QZ_ROM || ROOT + (I80 ? `/build/port8080/quaz_8080${I80SUF}.r0m` : "/build/port/quaz_z80.r0m"))), 0);
if (I80) {   // getState/setState, как у Z80_v06 (только то, что нужно стенду)
  const R = ["b", "c", "d", "e", "h", "l", null, "a"];
  vcpu.getState = () => { const s = { pc: vcpu.pc, sp: vcpu.sp }; R.forEach((n, i) => { if (n) s[n] = vcpu.regs[i]; }); return s; };
  vcpu.setState = s => { R.forEach((n, i) => { if (n) vcpu.regs[i] = s[n] & 255; }); vcpu.pc = s.pc; vcpu.sp = s.sp; }; }
const PCMAP = new Map(), I80CODE = new Set();
let I80X = [], I80STRIP = -1;
const inX80 = a => { for (let k = 0; k < I80X.length; k += 2) if (a >= I80X[k] && a < I80X[k + 1]) return true; return false; };   // добавки i8080 (пары)
if (I80) { for (const l of fs.readFileSync(ROOT + `/build/port8080/pcmap${I80SUF}.txt`, "utf8").trim().split("\n")) { const [a, b] = l.split(" ").map(x => parseInt(x, 16)); PCMAP.set(a, b); }
  for (const l of fs.readFileSync(ROOT + `/build/port8080/quaz_8080${I80SUF}.lst`, "latin1").split("\n")) { const m = l.match(/^\s*\d+\+?\s+([0-9A-F]{4})\s([0-9A-F]{2})/); if (m && !/\b(incbin|db|dw|ds|include)\b/i.test(l.split("\t").slice(1).join(" "))) I80CODE.add(parseInt(m[1], 16)); }
  I80X = fs.readFileSync(ROOT + `/build/port8080/layout${I80SUF}.txt`, "utf8").trim().split(" ").map(x => parseInt(x, 16));
  I80STRIP = PCMAP.get(0xC1B7) + 1; }
memory.detach_boot && memory.detach_boot();
vcpu.pc = 0; vcpu.sp = 0x61A5; vcpu.iff = false;
// QZ_LS_PROF=файл — такты Вектора по PC после первого прохода main_loop; режим перед адресом: x — мини-игра, s — проход с прокруткой, p — без
const PROF = process.env.QZ_LS_PROF ? new Map() : null;
if (PROF) process.on("exit", () => fs.writeFileSync(process.env.QZ_LS_PROF, [...PROF].map(([q, n]) => q + " " + n).join("\n") + "\n"));
// QZ_RING=1 — модель поля-кольца (сборка i8080 без своего кольца): поле T_FIELD 2300-35FF (4864 байта) хранится со смещением
// RING.off — логический байт L по адресу 2300 + (L + off) mod 4864; сдвиги поля (ldir/lddr в scr_shift_* и scroll_step) не
// копируют, а меняют смещение. Все обращения Вектора к полю пересчитываются (стоимость пересчёта не учитывается — верхняя оценка)
const RING = process.env.QZ_RING ? { off: 0, n: 0 } : null;
// сборка i8080 с полем-кольцом (port/i8080_ring.asm): смещение — в её ячейке ring_off (логический вид поля для сверки)
const RINGA = (() => { if (!I80 || RING) return null; for (const l of fs.readFileSync(`${ROOT}/build/port8080/quaz_8080${I80SUF}.sld`, "latin1").split("\n")) {
  const p = l.split("|"); if (p.length >= 8 && p[6] === "L" && p[7].split(",")[1] === "ring_off") return +p[5]; } return null; })();
const ringOff = () => RING ? RING.off : memory.bytes[memory.tobank(RINGA)] | memory.bytes[memory.tobank(RINGA + 1)] << 8;
const ringPhys = a => (!RING && RINGA === null) || a < 0x2300 || a >= 0x3600 ? a : 0x2300 + (a - 0x2300 + ringOff()) % 4864;
const vrd = a => memory.bytes[memory.tobank(ringPhys(a & 0xFFFF))];
if (RING) { const orr = memory.read.bind(memory), oww = memory.write.bind(memory);
  memory.read = (a, st) => orr(ringPhys(a & 0xFFFF), st); memory.write = (a, v, st) => oww(ringPhys(a & 0xFFFF), v, st); }
if (process.env.QZ_LS_CHECKS) { const ow = memory.write.bind(memory); memory.write = (a, v, s) => { if (VEC.passes > 0) checkWrite(a & 0xFFFF, vcpu.pc); return ow(a, v, s); };
  const oo = io.output.bind(io); io.output = (port, v) => { if (port >= 8 && port <= 11) viOuts++; return oo(port, v); }; }
// QZ_LS_WATCHW="с-по" — какие команды Вектора пишут в диапазон (сводка в конце)
const WW = process.env.QZ_LS_WATCHW ? process.env.QZ_LS_WATCHW.split("-").map(x => parseInt(x, 16)) : null, wwMap = new Map();
const WR = process.env.QZ_LS_WATCHR ? process.env.QZ_LS_WATCHR.split("-").map(x => parseInt(x, 16)) : null, wrMap = new Map();
if (WR) { const orr = memory.read.bind(memory); memory.read = (a, s) => { if (a >= WR[0] && a <= WR[1]) wrMap.set(vcpu.pc, (wrMap.get(vcpu.pc) || 0) + 1); return orr(a, s); }; }
process.on("exit", () => WR && console.log("читали: " + [...wrMap].sort((a, b) => a[0] - b[0]).map(([p, n]) => p.toString(16) + "×" + n).join(" ")));
const WLOG = process.env.QZ_LS_WLOG ? process.env.QZ_LS_WLOG.split("-").map(x => parseInt(x, 16)) : null, wlog = [], WLOG0 = +(process.env.QZ_LS_WLOGPASS || 0);
if (WLOG !== null) { const ow = memory.write.bind(memory); memory.write = (a, v, s) => { if (a >= WLOG[0] && a <= WLOG[WLOG.length - 1] && VEC.passes >= WLOG0) wlog.push(`${a.toString(16)} ` + `${VEC.passes} ${vcpu.pc.toString(16)} ${v.toString(16)} f${VEC.frames}`); return ow(a, v, s); };
  process.on("exit", () => fs.writeFileSync(process.env.QZ_LS_WLOGF || "build/port/wlog.txt", wlog.join("\n") + "\n")); }
if (WW) { const ow = memory.write.bind(memory); memory.write = (a, v, s) => { if (a >= WW[0] && a <= WW[1]) wwMap.set(vcpu.pc, (wwMap.get(vcpu.pc) || 0) + 1); return ow(a, v, s); }; }
const VEC = makeSide("Вектор"); const ATTRLOG = new Map();
// перенос блока в порте (build/port/reloc.txt: начало конец новое): адреса команд на стороне Вектора
const [RL0, RL1, RLN] = fs.readFileSync(ROOT + "/build/port/reloc.txt", "utf8").trim().split(/\s+/).map(x => parseInt(x, 16));
const vpcZ = a => (a >= RL0 && a < RL1) ? a - RL0 + RLN : a;
const vpc = a => { const z = vpcZ(a); if (!I80) return z; if (!PCMAP.has(z)) throw new Error(`нет в pcmap: ${a.toString(16)}`); return PCMAP.get(z); };
// адрес копии матрицы в склейке (vec_kb): склейка добавляет к Kempston стрелки и пробел из неё —
// в стенде пишем её сразу, иначе ввод отстаёт на кадр (копия обновляется в прерывании)
const VEC_KB = (() => { for (const l of fs.readFileSync(ROOT + "/build/port/glue.sld", "latin1").split("\n")) {
  const p = l.split("|"); if (p.length >= 8 && p[6] === "L" && p[7].split(",")[1] === "vec_kb") return +p[5]; } throw new Error("нет vec_kb в glue.sld"); })();
function vkemp(k) { // Kempston -> матрица Вектора (порт 0Eh стенда берёт стрелки и пробел)
  keyboard.matrix[0] = (keyboard.matrix[0] & 0x0F) | (k & 1 ? 0x40 : 0) | (k & 2 ? 0x10 : 0) | (k & 8 ? 0x20 : 0) | (k & 4 ? 0x80 : 0);
  keyboard.matrix[7] = (keyboard.matrix[7] & 0x7F) | (k & 0x10 ? 0x80 : 0);
  memory.write(VEC_KB, keyboard.matrix[0], false); memory.write(VEC_KB + 7, keyboard.matrix[7], false);
  if (KEMP80 >= 0) memory.write(KEMP80, k & 0x1F, false); }   // i8080: стрелки и пробел для Kempston считает прерывание — тоже сразу
// QZ_LS_CNT=адрес,адрес (адреса Вектора, hex) — счёт входов по месту вызова, итог в QZ_LS_CNTF; QZ_LS_CNTOFF — смещение адреса возврата
// в стеке после первой команды (она уже исполнена; push — 2)
const CNTOFF = +(process.env.QZ_LS_CNTOFF || 0), CNT = process.env.QZ_LS_CNT ? new Set(process.env.QZ_LS_CNT.split(",").map(x => parseInt(x, 16))) : null, CNTM = new Map();
if (CNT) process.on("exit", () => fs.writeFileSync(process.env.QZ_LS_CNTF || "build/port/cnt.txt", [...CNTM].sort((a, b) => b[1] - a[1]).map(([k, n]) => k + " " + n).join("\n") + "\n"));
const LDIR80 = ["z_ldir", "z_lddr"].map(n => { if (!I80) return -1; for (const l of fs.readFileSync(ROOT + `/build/port8080/quaz_8080${I80SUF}.sld`, "latin1").split("\n")) {
  const p = l.split("|"); if (p.length >= 8 && p[6] === "L" && p[7].split(",")[1] === n) return +p[5]; } return -1; });
// i8080: ячейка kemp_kb80 (port/i8080.asm)
const KEMP80 = (() => { if (!I80) return -1; for (const l of fs.readFileSync(ROOT + `/build/port8080/quaz_8080${I80SUF}.sld`, "latin1").split("\n")) {
  const p = l.split("|"); if (p.length >= 8 && p[6] === "L" && p[7].split(",")[1] === "kemp_kb80") return +p[5]; } return -1; })();
function vkey(row, mask, down) { if (down) keyboard.matrix[row] |= mask; else keyboard.matrix[row] &= ~mask; }

// ---------- проверки (QZ_LS_CHECKS=1): сторож, чужие записи, плоскость цвета ----------
const CHECKS = !!process.env.QZ_LS_CHECKS;
const GL = {}; for (const l of fs.readFileSync(ROOT + "/build/port/glue.sld", "latin1").split("\n")) {
  const p = l.split("|"); if (p.length >= 8 && p[6] === "L") { const n = p[7].split(",")[1]; if (n && !(n in GL)) GL[n] = +p[5]; } }
if (I80) for (const n in GL) if (PCMAP.has(GL[n])) GL[n] = PCMAP.get(GL[n]);   // метки кода склейки -> адреса i8080
const glueData = new Uint8Array(0x2000);   // байты склейки, которые разрешено писать (db/dw/ds, таблицы)
{ const L = fs.readFileSync(ROOT + "/build/port/glue.lst", "latin1").split("\n").map(l => l.match(/^\s*\d+\+?\s+([0-9A-F]{4})\s(.*)$/)).filter(Boolean);
  for (let i = 0; i < L.length; i++) { const a = parseInt(L[i][1], 16), src = L[i][2];
    if (/\b(db|dw|ds|defb|defw|defs)\b/i.test(src)) { let j = i + 1;
      while (j < L.length && (parseInt(L[j][1], 16) === a || /^[\s0-9A-F]*$/.test(L[j][2]))) j++;   // строки-продолжения db
      const b = j < L.length ? parseInt(L[j][1], 16) : a + 1; for (let x = a; x < Math.min(b, 0x2000); x++) glueData[x] = 1; } } }
for (let x = 0x1600; x < 0x1E00; x++) glueData[x] = 1;          // BAND
const GLUE_END = GL.glue_end;
const vWrote = new Map(), bad = [];
function vMapZX(a) {            // адрес Вектора -> адрес ZX (или null — своя область Вектора)
  if (a >= 0x2000 && a < 0x4000) return a + 0x6000;
  if (a >= RLN && a < RLN + RL1 - RL0) return a - RLN + RL0;
  if (a >= 0x61A9 && a < 0x8000) return a;
  if (a >= 0xA000 && a < RL0) return a;
  return null; }
function checkWrite(a, pc) {
  if (I80 && inX80(a)) return;                             // port/i8080.asm: ячейки и самомодификация blit_tile
  if (I80 && (a === I80STRIP || a === I80STRIP + 1)) return;                   // операнд ld de,t_field в strip_put (склейка: BAND)
  if (a < 0x2000) { if (!glueData[a]) note(`запись в код склейки ${a.toString(16)} из ${pc.toString(16)}`); return; }
  if ((a >= 0x8000 && a < 0xA000) || a >= 0xE000) return;                     // плоскости
  if (a >= 0x5800 && a < 0x5B00) return;                                       // атрибуты
  if (a >= 0x5B00 && a < 0x61A9) return;                                       // стек
  if (a >= RLN + RL1 - RL0 && a < 0x5800 && !(a >= 0x5100 && a < 0x5400)) { note(`запись в бывший теневой экран ${a.toString(16)} из ${pc.toString(16)}`); return; }
  const z = vMapZX(a); if (z === null) return;
  const k = z; if (!vWrote.has(k)) vWrote.set(k, pc); }
const SKIPW = z => (z >= 0xB5B8 && z <= 0xB5BB)    // v_rnd_hl/ptr: rnd на Векторе подменяется только результатом
  || z === 0xC1B8 || z === 0xC1B9;                     // операнд strip_put: склейка направляет вывод в BAND (вертикальная прокрутка)
const notes = new Map(); function note(s) { notes.set(s, (notes.get(s) || 0) + 1); }
const PCH = [];
const TRP = +(process.env.QZ_LS_TRACEPOLL || 0), trp = [];   // трасса PC Вектора после опроса с этим номером
if (TRP) process.on("exit", () => fs.writeFileSync("build/port8080/trace_ls.txt", trp.join("\n")));
// QZ_LS_POLLCMP="с-по" — снимки состояния на опросах ввода с этими номерами; при выходе — первый опрос с отличием
const PL = process.env.QZ_LS_POLLCMP ? process.env.QZ_LS_POLLCMP.split("-").map(Number) : null, PLZ = new Map(), PLV = new Map();
if (PL) process.on("exit", () => { for (let n = PL[0]; n <= PL[1]; n++) { if (!PLZ.has(n) || !PLV.has(n)) continue; const d = compare(PLZ.get(n), PLV.get(n));
  if (d.length) { console.log(`опрос ${n}: ` + d.slice(0, 12).map(([a, z, v]) => `${a.toString(16)} ${symName(a)} ZX ${z.toString(16)} Век ${v.toString(16)}`).join("; ")); return; } }
  console.log(`опросы ${PL[0]}-${PL[1]}: отличий нет (ZX ${PLZ.size}, Вектор ${PLV.size})`); });
function watchPC(p) {
  if (I80) { PCH.push(p); if (PCH.length > 80) PCH.shift();
    if (!I80CODE.has(p) && !inX80(p)) { note(`исполнение вне кода: ${p.toString(16)}`);
      if (process.env.QZ_LS_STOPBAD) { console.log(`вне кода ${p.toString(16)} на проходе ${VEC.passes}, кадр ${VEC.frames}; до этого: ` + PCH.map(x => x.toString(16)).join(" ")); process.exit(2); } } }
  else if (!(p < GLUE_END || (p >= 0xB070 && p < RL0) || (p >= RLN && p < RLN + RL1 - RL0))) note(`исполнение вне кода: ${p.toString(16)}`);
  if (p === GL.boot && VEC.started) note("перезапуск (boot)");
  if (p === GL.boot) VEC.started = true; }
// цвет: ожидаемый класс клетки по SEL[атрибут] и точкам
// контур пола (склейка contour): окна в 2 знакоместа на границах пола по t_colattr, класс по точкам плоскости;
// снимается на входе в contour (после него t_colattr уже может описывать следующую полосу)
function contourMap() { const m = new Map(); if (vrd(0xB044) === vrd(0xB045)) return m;
  const win = (c, y0, dy) => { let k = 0xFF; for (let i = 0; i < 16; i++) { const y = y0 + dy * i; k &= vrd(0x8000 + (c << 8) + 223 - y); m.set(c * 256 + y, ~k & 255); } };
  for (let p = 0; p < 16; p++) { const f = vrd(0xB024 + 2 * p), s = vrd(0xB025 + 2 * p);
    if (f === 0xFF || s === 0) continue;
    if (f && s !== 0xFF && s - f < 2) continue;
    for (const c of [2 * p, 2 * p + 1]) { if (s !== 0xFF) win(c, s * 8 + 7, -1); if (f) win(c, (f - 1) * 8, 1); } }
  return m; }
function colourDiff() { let d = 0, first = null; const SELA = 0x5100;
  const inGame = vrd(GL.in_game), cm = inGame ? CM : new Map();
  for (let r = 0; r < 24; r++) for (let c = 0; c < 32; c++) { const at = vrd(0x5800 + r * 32 + c), code = (inGame && r * 32 + c >= 0x260) ? 0 : vrd(SELA + at);
    for (let i = 0; i < 8; i++) { const row = 223 - 8 * r - i, bm = vrd(0x8000 + (c << 8) + row), cl = vrd(0xE000 + (c << 8) + row);
      const exp = code === 0 ? 0 : code === 1 ? 0xFF : code === 2 ? (~bm & 255) : bm;
      if (cl !== exp && cl !== cm.get(c * 256 + 8 * r + i)) { d++; if (!first) first = `клетка ${r},${c} атрибут ${at.toString(16)} код ${code}: ${cl.toString(16)} вместо ${exp.toString(16)}`; } } }
  return [d, first]; }
// QZ_LS_SHOTDIR="папка" — каждые QZ_LS_SHOTEVERY кадров (100) сырой кадр Вектора: палитра 16 + плоскости 8000 и E000 (tools/shots.py)
const SHOTDIR = process.env.QZ_LS_SHOTDIR, SHOTEVERY = +(process.env.QZ_LS_SHOTEVERY || 100);
let lastShot = "";
function vShot() { const b = Buffer.alloc(16 + 0x4000); for (let i = 0; i < 16; i++) b[i] = vrd(GL.vec_pal + i);
  for (let a = 0; a < 0x2000; a++) { b[16 + a] = vrd(0x8000 + a); b[16 + 0x2000 + a] = vrd(0xE000 + a); }
  const h = require("crypto").createHash("md5").update(b).digest("hex"); if (h === lastShot) return; lastShot = h;
  fs.writeFileSync(`${SHOTDIR}/${String(VEC.frames).padStart(6, "0")}_${VEC.passes}_${vrd(GL.in_game)}.bin`, b); }
const PCLOG = +(process.env.QZ_LS_PCLOG || 0), pclog = [];
// QZ_LS_HIT="адр,адр" (hex, адреса Вектора) — печать кадра, прохода и v_obj_p2 на каждом входе
const HITS = new Set((process.env.QZ_LS_HIT || "").split(",").filter(Boolean).map(x => parseInt(x, 16)));
if (PCLOG) process.on("exit", () => fs.writeFileSync(process.env.QZ_LS_PCLOGF, pclog.join("\n") + "\n"));
const MSGLOG = process.env.QZ_LS_MSGLOG ? new Map() : null;
let CM = new Map(), colBad = 0, colMax = 0, colFirst = null, viOuts = 0;
// ---------- снимок состояния ----------
const REG = [[0xA000, 0xA180, 0], [0xA1B0, 0xA2D1, 0], [0xAF00, 0xB066, 0], [0x8078, 0x8080, 0x6000], [0x8300, 0x9600, 0x6000]];
const PTRS = new Set([0xAF12, 0xAFC2, 0xB009, 0xB00B, 0xAF18, 0xAF01, 0xAFBE, 0xAFC0, 0xAF6F, 0xAF71, 0xB012, 0xB00E, 0xB010]);
const SKIP = new Set([0xB060, 0xB065,   // v_sfx_req, v_sfx_cur — звук ведёт isr (число прерываний у машин разное)
  0xAFC4, 0xAFCB, 0xAFCC,               // v_ctrlmode, v_keytab — у порта свои номера режимов меню (2 — джойстик = Kempston у ZX)
  0xAF04, 0xAF05, 0xAF1B]);             // v_blt_cols/skip/cx — внутренние blit_tile: при вертикальной прокрутке из BAND плитки не выводятся
// QZ_LS_RU=1 — русская сборка: переменные печати (позиция, указатели в строках) другие по построению
if (process.env.QZ_LS_RU) for (const a of [0xB00E, 0xB00F, 0xB010, 0xB011, 0xB04D, 0xB04E, 0xB04F]) SKIP.add(a);
function snap(rd, vec) { const out = []; for (const [a0, a1, off] of REG) for (let a = a0; a < a1; a++) out.push(rd(vec ? a - off : a)); return out; }
function compare(z, v) {
  const diffs = []; let i = 0;
  for (const [a0, a1] of REG) for (let a = a0; a < a1; a++, i++) {
    if (z[i] === v[i] || SKIP.has(a)) continue;
    // указатель в окно: слово (a, a+1) или (a-1, a)
    const w = (j, k) => [z[j] | z[j + 1] << 8, v[j] | v[j + 1] << 8];
    let ok = false;
    for (const [j, aa] of [[i, a], [i - 1, a - 1]]) if (j >= 0) { const [zw, vw] = w(j); if ((zw - vw === 0x6000 && zw >= 0x8000 && zw < 0xA000) || (zw >= RL0 && zw < RL1 && vw === zw - RL0 + RLN)) ok = true; }
    if (!ok) diffs.push([a, z[i], v[i]]);
  }
  return diffs;
}

// сценарные подстановки (одинаковы для обеих машин; адреса окна 8000-9FFF на Векторе −0x6000):
//   QZ_LS_AT="PC:адрес=знач;адрес=знач|PC2:..."  — перед исполнением команды PC
//   QZ_LS_PASS="проход:адрес=знач;...|..."        — на входе в main_loop с этим номером
const parseSets = s => s.split(";").filter(Boolean).map(x => { const [a, v] = x.split("="); return [parseInt(a, 16), parseInt(v, 16)]; });
const LS_AT = new Map((process.env.QZ_LS_AT || "").split("|").filter(Boolean).map(x => { const [pc, sets] = x.split(":"); return [parseInt(pc, 16), parseSets(sets)]; }));
const LS_PASS = new Map((process.env.QZ_LS_PASS || "").split("|").filter(Boolean).map(x => { const [n, sets] = x.split(":"); return [n === "*" ? "*" : +n, parseSets(sets)]; }));
const passSets = n => [...(LS_PASS.get(n) || []), ...(LS_PASS.get("*") || [])];
//   QZ_LS_KEMP="с-по:знач|..." — Kempston на диапазоне номеров опроса input_read вместо случайного сценария
const LS_KEMP = (process.env.QZ_LS_KEMP || "").split("|").filter(Boolean).map(x => { const [r, v] = x.split(":"); const [a, b] = r.split("-").map(Number); return [a, b, parseInt(v, 16)]; });
const kempFor = n => { for (const [a, b, v] of LS_KEMP) if (n >= a && n <= b) return v; return kempAt(n); };
const vaddr = a => (a >= 0x8000 && a < 0xA000) ? a - 0x6000 : a;
function zApply(sets) { for (const [a, v] of sets) zmem[a] = v; }
function vApply(sets) { for (const [a, v] of sets) memory.write(vaddr(a), v, false); }
// посещения (на ZX): что сверка прошла
const VISIT = new Map([[0xD356, "lift"], [0xCFB8, "console"], [0xC700, "xfer_game"], [0xBBAB, "scr_salvage"], [0xE4CB, "deck_change"],
  [0xE3EB, "plr_die"], [0xE513, "city_clear"], [0xE560, "game_over"], [0xE592, "hi_enter"], [0xE1D7, "scroll_start"]].map(([a, n]) => [a, { name: n, n: 0 }]));
// длительность прохода main_loop (в кадрах ТВ своей машины): с прокруткой (v_scr_steps > 0) и без
function passTime(side, steps, t) { if (side.lastT !== undefined) { const k = side.lastSteps ? "scroll" : "plain";
  side.pt = side.pt || { scroll: [0, 0], plain: [0, 0] }; side.pt[k][0] += t - side.lastT; side.pt[k][1]++;
    if (!side.lastSteps && side.lastN !== undefined) { side.pn = side.pn || {}; const q = side.pn[side.lastN] = side.pn[side.lastN] || [0, 0]; q[0] += t - side.lastT; q[1]++; } }
  side.lastT = t; side.lastSteps = steps; side.xfLast = undefined; side.inXf = false; }
// мини-игра захвата: длительность хода xf_play (CA19) в кадрах ТВ (подряд идущие ходы одного захвата)
function xfTime(side, t, F) { if (side.xfLast !== undefined && t - side.xfLast < 50 * F) { side.xt = side.xt || [0, 0]; side.xt[0] += t - side.xfLast; side.xt[1]++; }
  side.xfLast = t; side.inXf = true; }
// ---------- прогон ----------
const ZFRAME = 69888, VFRAME = 59904;
let zt = 0, vt = 0, vtacc = 0;
const zq = [], vq = [];        // снимки по проходам
let firstBad = null, compared = 0;
function zRun() {   // до следующего входа в main_loop
  const f0 = ZX.frames;
  for (;;) {
    const p = zcpu.pc;
    if (p === 0xBD2D) ZX.inIsr = true;
    if (p === 0xCA19) xfTime(ZX, ZX.frames * ZFRAME + zt, ZFRAME);
    if (p === 0xB5B4) { const s = zcpu.getState(); s.a = ZX.inIsr ? ISEQ[ZX.iI++ & 0xFFFF] : RSEQ[ZX.rI++ & 0xFFFF]; zcpu.setState(s); }
    if (VISIT.has(p)) VISIT.get(p).n++;
    if (LS_AT.has(p)) zApply(LS_AT.get(p));
    if (p === 0xB61F && ZX.passes > 0) { ZX.polls++; zkemp = kempFor(ZX.polls); if (PL && ZX.polls >= PL[0] && ZX.polls <= PL[1]) PLZ.set(ZX.polls, snap(a => zmem[a])); }
    if (p === 0xB07D && process.env.QZ_BLIT) { const s = zcpu.getState(); ZX.blits.push(((s.h << 8) | s.l).toString(16) + "@" + ZX.passes); if (ZX.blits.length > 8) ZX.blits.shift(); }
    if (p === 0xB07D) { const s = zcpu.getState(); if (s.h === 0 && s.l === 0) {   // как в порте: blit_tile(0) — выход
      s.pc = zmem[s.sp] | zmem[(s.sp + 1) & 0xFFFF] << 8; s.sp = (s.sp + 2) & 0xFFFF; zcpu.setState(s); continue; } }
    if (p === 0xDD79) ZX.lastN = Math.min(zmem[0xAF09], 6);
    if (p === 0xE0DC) { ZX.lastPassFrames = ZX.frames - f0; passTime(ZX, zmem[0xAF2C], ZX.frames * ZFRAME + zt); ZX.passes++; zApply(passSets(ZX.passes)); return snap(a => zmem[a]); }
    const c = zcpu.run_instruction(); zt += c;
    if (p === 0xBDFC) ZX.inIsr = false;     // ret обработчика (после ei)
    if (zt >= ZFRAME) { zt -= ZFRAME; ZX.frames++; zMenu(); if (zcpu.iff) zcpu.interrupt(false, 0xFF); }
    if (ZX.frames - f0 > 20000) throw new Error(`ZX: нет main_loop, PC ${zcpu.pc.toString(16)} (${symName(zcpu.pc)}), проход ${ZX.passes}, опросов ${ZX.polls}, kemp ${zkemp}`);
  }
}
const RINGSH = RING ? new Map([[0xE135, [0xE137, 2, 1]], [0xE14F, [0xE151, -2, -1]], [0xE126, [0xE128, 256, 1]], [0xE117, [0xE119, -256, -1]]]
  .map(([a, [nx, d, dir]]) => [vpc(a), { nx: vpc(nx), d, dir }])) : null;
function ringShift(p) {   // вместо call z_ldir/z_lddr сдвига поля: смещение кольца, регистры как после ldir/lddr
  const k = RINGSH.get(p), bc = vcpu.regs[0] << 8 | vcpu.regs[1], hl = vcpu.regs[4] << 8 | vcpu.regs[5], de = vcpu.regs[2] << 8 | vcpu.regs[3];
  const h2 = (hl + k.dir * bc) & 0xFFFF, d2 = (de + k.dir * bc) & 0xFFFF;
  vcpu.regs[4] = h2 >> 8; vcpu.regs[5] = h2 & 255; vcpu.regs[2] = d2 >> 8; vcpu.regs[3] = d2 & 255; vcpu.regs[0] = 0; vcpu.regs[1] = 0;
  RING.off = (RING.off + k.d + 4864) % 4864; RING.n++; vcpu.pc = k.nx; return 60; }
const V_C700 = vpc(0xC700), V_CA19 = vpc(0xCA19), V_B61F = vpc(0xB61F), V_B07D = vpc(0xB07D), V_E0DC = vpc(0xE0DC), V_BD2D = vpc(0xBD2D), V_B5B4 = vpc(0xB5B4), V_BDFC = vpc(0xBDFC), V_DD79 = vpc(0xDD79);
const VLS_AT = new Map([...LS_AT].map(([a, s]) => [vpc(a), s]));
function vRun() {
  const f0 = VEC.frames;
  for (;;) {
    const p = vcpu.pc;
    if (HITS.has(p)) console.log(`hit ${p.toString(16)} кадр ${VEC.frames} проход ${VEC.passes} ret ${(vrd(vcpu.sp) | vrd(vcpu.sp + 1) << 8).toString(16)} p2 ${vrd(0xAF84).toString(16)} lock ${GL.pal_lock !== undefined ? vrd(GL.pal_lock) : "?"}`);
    if (CHECKS) watchPC(p);
    if (p === V_DD79) VEC.lastN = Math.min(vrd(0xAF09), 6);
    if (p === V_CA19) xfTime(VEC, VEC.frames * VFRAME + vt, VFRAME);
    if (p === V_C700) VEC.inXf = true;
    if (process.env.QZ_LS_WATCHDK && VEC.polls >= TRP) { VEC.wdk = (VEC.wdk || 0) + 1; if (VEC.wdk % 20000 === 0 && VEC.wdk < 4000000) { const rv = VEC.rv || (VEC.rv = new Map([...PCMAP].map(([a, b]) => [b, a])));
      let q = p; while (!rv.has(q) && q > 0) q--; const z = rv.get(q);
      fs.appendFileSync("build/port8080/watchdk.txt", `${VEC.wdk} f${VEC.frames} pc ${symName(z >= RLN && z < RLN + RL1 - RL0 ? z - RLN + RL0 : z)} d0 ${vrd(0xAF6B).toString(16)} e0 ${vrd(0xAF6A).toString(16)} d ${vrd(0xAF6D).toString(16)} e ${vrd(0xAF6C).toString(16)} hp ${vrd(0xAFAF).toString(16)} col ${vrd(0xAF14).toString(16)} y ${(vrd(0xAF29) | vrd(0xAF2A) << 8).toString(16)}\n`); } }
    if (TRP && VEC.polls >= TRP && trp.length < 3000000) { trp.push(p.toString(16)); if (trp.length === 3000000) fs.writeFileSync("build/port8080/trace_ls.txt", trp.join("\n")); }
    if (p === V_BD2D) VEC.inIsr = true;
    if (p === V_B5B4) { const s = vcpu.getState(); s.a = VEC.inIsr ? ISEQ[VEC.iI++ & 0xFFFF] : RSEQ[VEC.rI++ & 0xFFFF]; vcpu.setState(s); }
    if (VLS_AT.has(p)) vApply(VLS_AT.get(p));
    if (PCLOG && VEC.passes === PCLOG) { const st = vcpu.getState(); pclog.push(`${p.toString(16)} a${st.a.toString(16)} hl${(st.h << 8 | st.l).toString(16)} de${(st.d << 8 | st.e).toString(16)} bc${(st.b << 8 | st.c).toString(16)}`); }
    if (MSGLOG && (p === 0xB1ED || p === 0xB1E6)) { const st = vcpu.getState(); const ret = vrd(st.sp) | vrd(st.sp + 1) << 8; const k = `${p === 0xB1ED ? "msg" : "str2"} ${st.a.toString(16)} ${ret.toString(16)}`; MSGLOG.set(k, (MSGLOG.get(k) || 0) + 1); }
    if (CHECKS && p === GL.contour) { CM = contourMap(); if (process.env.QZ_CMDUMP && !VEC.cmd && [...Array(16)].some((_, i) => { const f = vrd(0xB024 + 2 * i); return f > 2 && f < 19; })) VEC.cmd = 1; if (process.env.QZ_CMDBG) console.log("contour", VEC.passes, [...Array(32)].map((_, i) => vrd(0xB024 + i).toString(16)).join(" ")); }
    if (process.env.QZ_LS_ATTRLOG && (p === 0x18 || p === 0x28)) { const s = vcpu.getState(); const ret = vrd(s.sp) | vrd(s.sp + 1) << 8;
      const tgt = p === 0x18 ? (s.h << 8 | s.l) : (s.d << 8 | s.e); const val = p === 0x18 ? s.a : s.a;
      const k = `${(ret - 1).toString(16)}: ${val.toString(16)}`; ATTRLOG.set(k, (ATTRLOG.get(k) || 0) + 1); }
    if (p === V_B61F && process.env.QZ_LS_DEBUG && VEC.passes === 4 && VEC.polls < 360) { const sp = vcpu.sp; if ((vrd(sp) | vrd(sp + 1) << 8) === 0xB6A1 && !VEC.dumped) { VEC.dumped = 1; const st = []; for (let i = 0; i < 12; i += 2) st.push((vrd(sp + i) | vrd(sp + i + 1) << 8).toString(16)); console.log("стек при первом вызове:", st.join(" "), "vec_kb:", [0,1,2,3,4,5,6,7].map(i => vrd(VEC_KB + i).toString(16)).join(" ")); } VEC.callers = VEC.callers || new Map(); const r = vrd(sp) | vrd(sp + 1) << 8; VEC.callers.set(r, (VEC.callers.get(r) || 0) + 1); }
    if (p === V_B61F && VEC.passes > 0) { VEC.polls++; VEC.lastPollFrame = VEC.frames; vkemp(kempFor(VEC.polls)); if (PL && VEC.polls >= PL[0] && VEC.polls <= PL[1]) PLV.set(VEC.polls, snap(vrd, true));
      if (+process.env.QZ_LS_DUMPPOLL === VEC.polls) {   // полное состояние i8080 (tools/xcheck80.js QZ_XC_FROM)
        const st = vcpu.getState(); st.f = vcpu.store_flags ? vcpu.store_flags() : 0; st.iff = vcpu.iff;
        st.mem = Buffer.from([...Array(65536)].map((_, a) => vrd(a))).toString("base64");
        fs.writeFileSync(process.env.QZ_LS_DUMPF || "build/port8080/state.json", JSON.stringify(st)); console.log("снимок на опросе " + VEC.polls); process.exit(0); } }
    if (p === V_B07D && process.env.QZ_BLIT) { const s = vcpu.getState(); VEC.blits.push(((s.h << 8) | s.l).toString(16) + "@" + VEC.passes); if (VEC.blits.length > 8) VEC.blits.shift(); }
    if (p === V_E0DC) { passTime(VEC, vrd(0xAF2C), VEC.frames * VFRAME + vt); VEC.passes++; vApply(passSets(VEC.passes)); return snap(vrd, true); }
    const c = RING && RINGSH.has(p) ? ringShift(p) : (vcpu.instruction(), vcpu.vcycles);
    if (CNT && CNT.has(p)) { const r = vrd(vcpu.sp + CNTOFF) | vrd(vcpu.sp + CNTOFF + 1) << 8, k = (VEC.inXf ? "x" : VEC.lastSteps ? "s" : "p") + p.toString(16) + "<" + r.toString(16); CNTM.set(k, (CNTM.get(k) || 0) + 1); }
    if (PROF && VEC.passes > 0 && (p === LDIR80[0] || p === LDIR80[1])) { const r = vrd(vcpu.sp + 2) | vrd(vcpu.sp + 3) << 8, k = "L" + (VEC.inXf ? "x" : VEC.lastSteps ? "s" : "p") + r.toString(16);
      PROF.set(k, (PROF.get(k) || 0) + (vcpu.regs[0] << 8 | vcpu.regs[1])); }   // ldir/lddr i8080 (после push af входа): байт по месту вызова
    if (PROF && VEC.passes > 0) { const k = (VEC.inXf ? "x" : VEC.lastSteps ? "s" : "p") + p.toString(16); PROF.set(k, (PROF.get(k) || 0) + c); }
    if (p === V_BDFC) VEC.inIsr = false;
    if (vcpu.last_opcode === 0xd3) io.commit();
    vtacc += c; if (vtacc > 1) { const tn = vtacc >> 1; vtacc -= tn * 2; timer.Count(tn); }
    vt += c; if (vt >= VFRAME) { vt -= VFRAME; VEC.frames++; if (SHOTDIR && VEC.frames % SHOTEVERY === 0) vShot(); vMenu(); v06c.irq = true; v06c.checkInterrupt(); }
    if (VEC.frames - Math.max(f0, VEC.lastPollFrame || 0) > 20000) {   // ни прохода, ни опроса ввода 20000 кадров const h = new Map(); const rv = new Map([...PCMAP].map(([a, b]) => [b, a]));
      for (let k = 0; k < 300000; k++) { const q = vcpu.pc; h.set(q, (h.get(q) || 0) + 1); vcpu.instruction(); vt += vcpu.vcycles; if (vt >= VFRAME) { vt -= VFRAME; v06c.irq = true; v06c.checkInterrupt(); } }
      const nm = q => { const r = rv.get(q); return r === undefined ? q.toString(16) : symName(r >= RLN && r < RLN + RL1 - RL0 ? r - RLN + RL0 : r); };
      const stk = []; for (let i = 0; i < 24; i += 2) { const w = vrd(vcpu.sp + i) | vrd(vcpu.sp + i + 1) << 8; stk.push(rv.has(w - 3) ? "→" + nm(w - 3) : w.toString(16)); }
      console.log("стек: " + stk.join(" ") + "; переменные AF00-AF40: " + [...Array(64)].map((_, i) => vrd(0xAF00 + i).toString(16)).join(" "));
      console.log("зависание, частые PC: " + [...h].sort((a, b) => b[1] - a[1]).slice(0, 25).map(([q, n]) => `${q.toString(16)}${rv.has(q) ? "=" + symName(rv.get(q) >= RLN && rv.get(q) < RLN + RL1 - RL0 ? rv.get(q) - RLN + RL0 : rv.get(q)) : ""}×${n}`).join(" "));
      throw new Error(`Вектор: нет main_loop, PC ${vcpu.pc.toString(16)} (${symName(vcpu.pc)}), проход ${VEC.passes}, опросов ${VEC.polls}`); }
  }
}
// меню до игры: «4» (Kempston), ENTER, затем огонь каждые 50 кадров до первого прохода main_loop
function zMenu() { const f = ZX.frames;
  zkeys.F7 = (f >= 60 && f < 70) ? 0xF7 : 0xFF; zkeys.BF = (f >= 120 && f < 130) ? 0xFE : 0xFF;
  if (ZX.passes === 0) zkemp = (f > 200 && f % 50 < 8) ? 0x10 : 0; }
function vMenu() { const f = VEC.frames;
  vkey(2, 0x10, f >= 60 && f < 70); vkey(0, 0x04, f >= 120 && f < 130);
  if (VEC.passes === 0) vkemp((f > 200 && f % 50 < 8) ? 0x10 : 0); }

// QZ_LS_SCREEN=1 — сверять и картинку: битмап экрана ZX 4000-57FF против плоскости Вектора (строка y -> 223 − y)
let scrBad = 0, scrFirst = null, scrMax = 0;
function screenDiff() { let d = 0, first = null;
  for (let y = 0; y < 192; y++) { const za = 0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2);
    for (let c = 0; c < 32; c++) { const z = zmem[za + c], v = vrd(0x8000 + (c << 8) + 223 - y);
      if (z !== v) { d++; if (!first) first = `y ${y} столбец ${c}: ZX ${z.toString(16)} Вектор ${v.toString(16)}`; } } }
  return [d, first]; }
const t0 = Date.now();
for (let n = 0; n < PASSES; n++) {
  const z = zRun(); const v = vRun();
  compared++;
  if (process.env.QZ_LS_DEBUG && VEC.callers) console.log("вызовы input_read с:", [...VEC.callers].map(([a, n]) => a.toString(16) + "×" + n).join(" "));
  if (process.env.QZ_LS_DEBUG) console.log(`проход ${n + 1}: опросов ZX ${ZX.polls} Вектор ${VEC.polls}, rnd ${ZX.rI}/${VEC.rI}`);
  if (process.env.QZ_LS_SCREEN) { const [sd, sf] = screenDiff(); if (sd) { scrBad++; if (sd > scrMax) { scrMax = sd; scrFirst = `проход ${n + 1}: ${sd} байт, ${sf}`; } } }
  if (process.env.QZ_LS_DUMPAT && n + 1 === +process.env.QZ_LS_DUMPAT) fs.writeFileSync(process.env.QZ_LS_DUMPF, Buffer.from([...Array(65536)].map((_, a) => vrd(a))));
  if (VEC.cmd === 1) { VEC.cmd = 2; fs.writeFileSync(process.env.QZ_CMDUMP, Buffer.from([...Array(65536)].map((_, a) => vrd(a)))); }
  if (CHECKS) { const [cd, cf] = colourDiff(); if (cd) { colBad++; if (cd > colMax) { colMax = cd; colFirst = `проход ${n + 1}: ${cd} байт, ${cf}`; } } }
  const d = compare(z, v);
  if (d.length) { firstBad = { n: n + 1, d }; break; }
  // шаг с входа в main_loop, чтобы следующий zRun/vRun не вернулся сразу
  zt += zcpu.run_instruction();
  { const c = (vcpu.instruction(), vcpu.vcycles); vt += c; }
}
if (RING || RINGA !== null) console.log(`кольцо поля: смещение ${ringOff()}${RING ? `, сдвигов ${RING.n}` : ''}`);
const sec = ((Date.now() - t0) / 1000).toFixed(1);
console.log(`проходов сверено ${compared}; кадров ТВ: ZX ${ZX.frames}, Вектор ${VEC.frames}; rnd: ${ZX.rI}/${VEC.rI}, в isr ${ZX.iI}/${VEC.iI}; ${sec} с`);
if (process.env.QZ_LS_SCREEN) console.log(`картинка: проходов с отличиями ${scrBad} из ${compared}${scrFirst ? ", худший — " + scrFirst : ""}`);
for (const [s, F] of [[ZX, ZFRAME], [VEC, VFRAME]]) { if (s.xt) console.log(`${s.name}: мини-игра ${(s.xt[0] / s.xt[1] / F).toFixed(2)} кадра на ход (${s.xt[1]})`);
  if (s.pn && process.env.QZ_LS_PN) console.log(`${s.name}: проход без прокрутки по числу объектов: ` + Object.entries(s.pn).map(([n, q]) => `${n}: ${(q[0] / q[1] / F).toFixed(3)} (${q[1]})`).join(", "));
  if (s.pt) console.log(`${s.name}: проход с прокруткой ${(s.pt.scroll[0] / s.pt.scroll[1] / F).toFixed(2)} кадра (${s.pt.scroll[1]}), без ${(s.pt.plain[0] / s.pt.plain[1] / F).toFixed(2)} кадра (${s.pt.plain[1]})`); }
if (WW) { const rev = a => (a >= RLN && a < RLN + RL1 - RL0) ? a - RLN + RL0 : a;
  console.log("писали: " + [...wwMap].sort((a, b) => a[0] - b[0]).map(([p, n]) => `${rev(p).toString(16)}(${symName(rev(p))})×${n}`).join(" ")); }
if (CHECKS) {
  const foreign = [...vWrote].filter(([z]) => !zWrote[z] && !SKIPW(z));
  console.log(`проверки: цвет — проходов с отличиями ${colBad}${colFirst ? ", худший " + colFirst : ""}; ВИ53 — записей в порты ${viOuts}; ` +
    `чужих записей ${foreign.length}${foreign.length ? ": " + foreign.slice(0, 8).map(([z, pc]) => `${z.toString(16)}(${symName(z)}) из ${pc.toString(16)}`).join(", ") : ""}; ` +
    `замечаний ${notes.size}${notes.size ? ": " + [...notes].slice(0, 8).map(([s, n]) => `${s} ×${n}`).join("; ") : ""}`); }
if (process.env.QZ_LS_ATTRLOG) console.log("одиночные записи атрибутов (место: значение ×n): " + [...ATTRLOG].sort().map(([k, n]) => `${k}×${n}`).join(", "));
console.log("посещения: " + [...VISIT.values()].map(v => `${v.name} ${v.n}`).join(", "));
if (firstBad) {
  console.log(`РАСХОЖДЕНИЕ на проходе ${firstBad.n}: ${firstBad.d.length} байт`);
  if (process.env.QZ_BLIT) console.log("  blit_tile ZX:", ZX.blits.join(" "), "\n  blit_tile Вектор:", VEC.blits.join(" "));
  for (const [a, z, v] of firstBad.d.slice(0, 20)) console.log(`  ${a.toString(16)} ${symName(a).padEnd(22)} ZX ${z.toString(16).padStart(2, "0")}  Вектор ${v.toString(16).padStart(2, "0")}`);
  process.exit(1);
} else console.log("расхождений нет");

if (MSGLOG) fs.writeFileSync(process.env.QZ_LS_MSGLOG, [...MSGLOG].map(([k, n]) => k + " " + n).join("\n") + "\n");
