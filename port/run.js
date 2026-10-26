#!/usr/bin/env node
// Стенд порта Z80 на vector06js в режиме Z80 (Z80_v06.js + z80_adapter.js); QZ_CPU=8080 — процессор i8080 (сборка tools/port8080.py).
//   node port/run.js build/port/quaz_z80.r0m <кадров> [out.png] [сценарий]
// Сценарий: "кадр:клавиша[:up],..." — клавиша держится до :up (или 6 кадров, если без :up и с '!': "900:4!").
// Клавиши: left right up down space enter 0-9 a-z (матрица Вектора). Джойстик «П» (порт 0Eh) — из стрелок и пробела.
// QZ_SHOTS="к1,к2" — снимки out_к.png; QZ_DUMP="к" — ОЗУ 64К в out_к.bin.
"use strict";
const fs = require("fs"), vm = require("vm"), zlib = require("zlib"), path = require("path");
const base = process.env.V06JS || path.join(require("os").homedir(), "projects/vector06js");
const [ROM, NS, OUT, SCEN] = process.argv.slice(2);
const N = +NS || 200, out = OUT || "build/port/shot.png";
const L = {};
const sld = "build/port/glue.sld";
if (fs.existsSync(sld)) for (const l of fs.readFileSync(sld, "latin1").split("\n")) {
  const p = l.split("|"); if (p.length >= 8 && p[6] === "L") { const n = p[7].split(",")[1]; if (n && !(n in L)) L[n] = +p[5]; }
}
const g = {}; g.window = g; g.document = { createElement: () => fc(), getElementById: () => fc() };
function fcx() { return { createImageData: () => ({ data: new Uint8ClampedArray(4) }), putImageData() {}, getImageData: () => ({ data: new Uint8ClampedArray(4) }), fillRect() {}, drawImage() {} }; }
function fc() { return { width: 0, height: 0, style: {}, getContext: () => fcx() }; }
g.requestAnimationFrame = () => 0; g.setTimeout = () => 0; g.print = () => 0;
g.console = { log() {}, debug() {}, warn() {}, error() {}, info() {} };
const ctx = vm.createContext(g);
for (const f of ["i8080-js/i8080_trace.js", "i8080-js/i8080_disasm.js", "i8080-js/i8080.js", "Z80_v06.js", ...(process.env.QZ_CPU === "8080" ? [] : ["z80_adapter.js"]),
  "src/fili.js", "src/ay.js", "src/fd1793.js", "src/fddimage.js", "src/i8253.js", "src/io.js", "src/keyboard.js", "src/memory.js",
  "src/sound.js", "src/tv.js"])
  vm.runInContext(fs.readFileSync(base + "/" + f, "utf8"), ctx, { filename: f });
const memory = new ctx.Memory(), keyboard = new ctx.Keyboard(), timer = new ctx.I8253(), ay = new ctx.AY(),
  floppy = new (ctx.Floppy().FD1793)(), io = new ctx.IO(keyboard, timer, memory, ay, floppy);
// QZ_WATCHW="с-по" — кто пишет в диапазон памяти (PC писавших команд)
if (process.env.QZ_WATCHW) { const [w0, w1] = process.env.QZ_WATCHW.split("-").map(x => parseInt(x, 16)); const ww = memory.write.bind(memory);
  global.qzWriters = new Map(); memory.write = (a, v, s) => { if (a >= w0 && a <= w1) qzWriters.set(cpuRef.pc, (qzWriters.get(cpuRef.pc) || 0) + 1); return ww(a, v, s); }; }
let cpuRef = null;
// QZ_WATCHR="с-по" — кто читает диапазон памяти
if (process.env.QZ_WATCHR) { const [r0, r1] = process.env.QZ_WATCHR.split("-").map(x => parseInt(x, 16)); const rr = memory.read.bind(memory);
  global.qzReaders = new Map(); memory.read = (a, s) => { if (a >= r0 && a <= r1 && cpuRef) qzReaders.set(cpuRef.pc, (qzReaders.get(cpuRef.pc) || 0) + 1); return rr(a, s); }; }
const cpu = new ctx.I8080(memory, io), tape = { advance: () => {}, sample: 0, reset: () => {} },
  v06c = new ctx.Vector06c(cpu, memory, io, ay, tape);
cpuRef = cpu; v06c.bmp = new Uint32Array(576 * 288); v06c.displayFrame = () => {}; v06c.check_breakpoint = () => false; v06c.dbg = null;
memory.init_from_array(new Uint8Array(fs.readFileSync(ROM)).subarray(0, 0x10000), 0); memory.detach_boot && memory.detach_boot();
cpu.pc = 0; cpu.sp = 0x61A5; cpu.iff = false;
const rd = a => memory.bytes[memory.tobank(a & 0xffff)];

const VK = { left: [0, 0x10], right: [0, 0x40], up: [0, 0x20], down: [0, 0x80], enter: [0, 0x04], space: [7, 0x80] };
for (let i = 0; i < 8; i++) VK[String(i)] = [2, 1 << i];
VK["8"] = [3, 0x01]; VK["9"] = [3, 0x02];
"@abcdefg".split("").forEach((c, i) => { if (c !== "@") VK[c] = [4, 1 << i]; });
"hijklmno".split("").forEach((c, i) => VK[c] = [5, 1 << i]);
"pqrstuvw".split("").forEach((c, i) => VK[c] = [6, 1 << i]);
"xyz".split("").forEach((c, i) => VK[c] = [7, 1 << i]);
const sched = [];
for (const s of (SCEN || "").split(",").filter(Boolean)) {
  const [f, k0, d] = s.split(":"); const tap = k0.endsWith("!"), k = k0.replace("!", "");
  if (!VK[k]) throw new Error("нет клавиши " + k);
  sched.push({ f: +f, k, down: d !== "up" });
  if (tap) sched.push({ f: +f + 6, k, down: false });
}
function key(k, down) { const [r, b] = VK[k]; if (down) keyboard.matrix[r] |= b; else keyboard.matrix[r] &= ~b; }
// QZ_POKE="адрес=знач@с-по,..." — запись в память на каждом кадре диапазона (адреса Вектора)
const POKES = (process.env.QZ_POKE || "").split(",").filter(Boolean).map(s => { const m = s.match(/(\w+)=(\w+)@(\d+)-(\d+)/); return [parseInt(m[1], 16), parseInt(m[2], 16), +m[3], +m[4]]; });
const shots = (process.env.QZ_SHOTS || "").split(",").filter(Boolean).map(Number);
const dumps = (process.env.QZ_DUMP || "").split(",").filter(Boolean).map(Number);

function png(file) {
  const pal = [];
  for (let i = 0; i < 16; i++) { const c = L.vec_pal !== undefined ? rd(L.vec_pal + i) : (i & 8 ? 0xFF : 0);
    pal.push([(c & 7) * 255 / 7 | 0, (c >> 3 & 7) * 255 / 7 | 0, (c >> 6) * 255 / 3 | 0]); }
  const S = 2, W = 256 * S, H = 256 * S, img = Buffer.alloc(W * H * 3);
  for (let sy = 0; sy < 256; sy++) { const mrow = 255 - sy;
    for (let col = 0; col < 32; col++) {
      const b = [rd(0x8000 + (col << 8) + mrow), rd(0xA000 + (col << 8) + mrow), rd(0xC000 + (col << 8) + mrow), rd(0xE000 + (col << 8) + mrow)];
      for (let bit = 7; bit >= 0; bit--) {
        const idx = ((b[0] >> bit & 1) << 3) | ((b[1] >> bit & 1) << 2) | ((b[2] >> bit & 1) << 1) | (b[3] >> bit & 1);
        const c = pal[idx], x = col * 8 + 7 - bit;
        for (let dy = 0; dy < S; dy++) for (let dx = 0; dx < S; dx++) { const o = ((sy * S + dy) * W + x * S + dx) * 3; img[o] = c[0]; img[o + 1] = c[1]; img[o + 2] = c[2]; }
      }
    }
  }
  const raw = Buffer.alloc(H * (W * 3 + 1));
  for (let y = 0; y < H; y++) { raw[y * (W * 3 + 1)] = 0; img.copy(raw, y * (W * 3 + 1) + 1, y * W * 3, (y + 1) * W * 3); }
  let T = null; const crc32 = buf => { if (!T) { T = new Int32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; T[n] = c; } }
    let c = 0xFFFFFFFF; for (const b of buf) c = T[(c ^ b) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; };
  const chunk = (t, d) => { const len = Buffer.alloc(4); len.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t, "latin1"), d]);
    const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td)); return Buffer.concat([len, td, c]); };
  const ih = Buffer.alloc(13); ih.writeUInt32BE(W, 0); ih.writeUInt32BE(H, 4); ih[8] = 8; ih[9] = 2;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ih), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}
function dump(file) { const b = Buffer.alloc(0x10000); for (let a = 0; a < 0x10000; a++) b[a] = rd(a); fs.writeFileSync(file, b); }

// QZ_WATCH="адрес|имя,..." — сообщать о проходе через адрес (имена склейки — из glue.sld)
const WATCH = new Map((process.env.QZ_WATCH || "").split(",").filter(Boolean).map(s => { const a = L[s] !== undefined ? L[s] : parseInt(s, 16); return [a, s]; }));
// QZ_SPANS="адрес_начала,адрес_конца" — такты между проходами (например, шаг прокрутки)
const SPANS = process.env.QZ_SPANS ? process.env.QZ_SPANS.split(",").map(s => L[s] !== undefined ? L[s] : parseInt(s, 16)) : null;
let spanT = null, spanTag = 0, totc = 0; const spanList = [];
const RING = process.env.QZ_RING, ring = new Array(256).fill(0); let ringI = 0;
// QZ_AT="PC:адрес=знач;...|..." — запись в память перед командой PC (адреса Вектора; PC блока DE70-EE90 пересчитывается)
const RLF = fs.existsSync("build/port/reloc.txt") ? fs.readFileSync("build/port/reloc.txt", "utf8").trim().split(/\s+/).map(x => parseInt(x, 16)) : [0, 0, 0];
const vpcR = a => (a >= RLF[0] && a < RLF[1]) ? a - RLF[0] + RLF[2] : a;
const AT = new Map((process.env.QZ_AT || "").split("|").filter(Boolean).map(x => { const [pc, sets] = x.split(":");
  return [vpcR(parseInt(pc, 16)), sets.split(";").filter(Boolean).map(s => s.split("=").map(v => parseInt(v, 16)))]; }));
let frames = 0, frc = 0, tacc = 0, steps = 0;
const pcs = new Map();   // QZ_PCSTAT=1 — счёт PC по страницам (поиск зависаний)
while (frames < N && steps < 2e9) {
  const c = (cpu.instruction(), cpu.vcycles); steps++; frc += c; tacc += c; totc += c;
  if (process.env.QZ_PCSTAT && (process.env.QZ_PCFROM ? frames >= +process.env.QZ_PCFROM && frames < +process.env.QZ_PCFROM + +process.env.QZ_PCSTAT : frames >= N - +process.env.QZ_PCSTAT)) { if (!process.env.QZ_PCSCROLL || (rd(0xAF2C) && (process.env.QZ_PCSCROLL === '1' || rd(0xAF2B) === parseInt(process.env.QZ_PCSCROLL, 16)))) pcs.set(cpu.pc, (pcs.get(cpu.pc) || 0) + c); }
  if (RING) { ring[ringI++ & 255] = cpu.pc; if ((cpu.pc === 0 || cpu.pc === L.boot) && frames > 5) { const r = []; for (let i = 0; i < 64; i++) r.push(ring[(ringI - 64 + i) & 255].toString(16)); console.log("переход на 0, кадр " + frames + ": " + r.join(" ")); process.exit(1); } }
  if (AT.has(cpu.pc)) for (const [a, v] of AT.get(cpu.pc)) memory.write(a, v, false);
  if (WATCH.has(cpu.pc)) console.log(`кадр ${frames}: ${WATCH.get(cpu.pc)}`);
  if (SPANS) { const p = cpu.pc;
    if (SPANS[0] === SPANS[1]) { if (p === SPANS[0]) { if (spanT !== null) spanList.push((totc - spanT) + (spanTag ? "*" : "")); spanT = totc; spanTag = rd(0xAF2C); } }
    else if (p === SPANS[0]) spanT = totc; else if (p === SPANS[1] && spanT !== null) { spanList.push(totc - spanT); spanT = null; } }
  if (cpu.last_opcode === 0xd3) io.commit();
  if (tacc > 1) { const tn = tacc >> 1; tacc -= tn * 2; timer.Count(tn); }
  if (frc >= 59904) {
    frc -= 59904; frames++;
    for (const s of sched) if (s.f === frames) key(s.k, s.down);
    for (const [a, v, f0, f1] of POKES) if (frames >= f0 && frames <= f1) memory.write(a, v, false);
    if (shots.includes(frames)) png(out.replace(/\.png$/, `_${frames}.png`));
    if (dumps.includes(frames)) dump(out.replace(/\.png$/, `_${frames}.bin`));
    v06c.irq = true; v06c.checkInterrupt();
  }
}
png(out);
if (SPANS) console.log(`отрезков ${spanList.length}: ` + spanList.map(x => (parseInt(x) / 59904).toFixed(2) + (String(x).endsWith("*") ? "*" : "")).join(" ") + " кадра");
if (process.env.QZ_WATCHR) console.log("читали " + process.env.QZ_WATCHR + ": " + [...qzReaders].slice(0, 30).map(([p, n]) => p.toString(16) + "×" + n).join(" "));
if (process.env.QZ_WATCHW) console.log("писали в " + process.env.QZ_WATCHW + ": " + [...qzWriters].map(([p, n]) => p.toString(16) + "×" + n).join(" "));
console.log(`кадров ${frames}, PC=${cpu.pc.toString(16)}, SP=${cpu.sp.toString(16)} -> ${out}`);
if (process.env.QZ_PCSTAT) fs.writeFileSync(out.replace(/\.png$/, ".pcstat"), [...pcs].map(([p, n]) => p.toString(16) + " " + n).join("\n"));
