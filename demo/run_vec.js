#!/usr/bin/env node
// Стенд демо на vector06js: прогон N кадров, нажатия клавиш, снимок экрана в PNG, замеры из ячеек qz_t_*.
//   node demo/run_vec.js build/demo/qzdemo.r0m <кадров> [out.png] [сценарий]
// Сценарий: "кадр:клавиша:down|up,..." — клавиши left/right/up/down (ряд 0 матрицы Вектора).
// QZ_SHOTS="к1,к2,..." — дополнительные снимки out_к.png на этих кадрах.
"use strict";
const fs = require("fs"), vm = require("vm"), zlib = require("zlib"), path = require("path");
const base = process.env.V06JS || path.join(require("os").homedir(), "projects/vector06js");
const [ROM, NS, OUT, SCEN] = process.argv.slice(2);
const N = +NS || 200;
const L = {};
const sld = ROM.replace(/\.r0m$/, ".sld");
if (fs.existsSync(sld)) for (const l of fs.readFileSync(sld, "latin1").split("\n")) {
  const p = l.split("|"); if (p.length >= 8 && p[6] === "L") { const n = p[7].split(",")[1]; if (n && !(n in L)) L[n] = +p[5]; }
}
const g = {}; g.window = g; g.document = { createElement: () => fc(), getElementById: () => fc() };
function fcx() { return { createImageData: () => ({ data: new Uint8ClampedArray(4) }), putImageData() {}, getImageData: () => ({ data: new Uint8ClampedArray(4) }), fillRect() {}, drawImage() {} }; }
function fc() { return { width: 0, height: 0, style: {}, getContext: () => fcx() }; }
g.requestAnimationFrame = () => 0; g.setTimeout = () => 0; g.print = () => 0;
g.console = { log() {}, debug() {}, warn() {}, error() {}, info() {} };
const ctx = vm.createContext(g);
for (const f of ["i8080-js/i8080_trace.js", "i8080-js/i8080_disasm.js", "i8080-js/i8080.js", "src/fili.js", "src/ay.js", "src/fd1793.js",
  "src/fddimage.js", "src/i8253.js", "src/io.js", "src/keyboard.js", "src/memory.js", "src/sound.js", "src/tv.js"])
  vm.runInContext(fs.readFileSync(base + "/" + f, "utf8"), ctx, { filename: f });
const memory = new ctx.Memory(), keyboard = new ctx.Keyboard(), timer = new ctx.I8253(), ay = new ctx.AY(),
  floppy = new (ctx.Floppy().FD1793)(), io = new ctx.IO(keyboard, timer, memory, ay, floppy);
const cpu = new ctx.I8080(memory, io), tape = { advance: () => {}, sample: 0, reset: () => {} },
  v06c = new ctx.Vector06c(cpu, memory, io, ay, tape);
v06c.bmp = new Uint32Array(576 * 288); v06c.displayFrame = () => {}; v06c.check_breakpoint = () => false; v06c.dbg = null;
memory.init_from_array(new Uint8Array(fs.readFileSync(ROM)).subarray(0, 0x10000), 0); memory.detach_boot && memory.detach_boot();
cpu.pc = 0; cpu.sp = 0xC000; cpu.iff = false;
const rd = a => memory.bytes[memory.tobank(a & 0xffff)];
const rdw = a => rd(a) | rd(a + 1) << 8;
const VKEYS = { left: [0, 0x10], right: [0, 0x40], up: [0, 0x20], down: [0, 0x80] };
const sched = (SCEN || "").split(",").filter(Boolean).map(s => { const [f, k, d] = s.split(":"); return { f: +f, k, down: d !== "up" }; });
const shots = (process.env.QZ_SHOTS || "").split(",").filter(Boolean).map(Number);
function key(k, down) { const [r, b] = VKEYS[k]; if (down) keyboard.matrix[r] |= b; else keyboard.matrix[r] &= ~b; }

function png(out) {
  // палитра из ячеек qz_pal (16 байт %BBGGGRRR)
  const pal = [];
  for (let i = 0; i < 16; i++) { const c = L.qz_pal !== undefined ? rd(L.qz_pal + i) : (i & 1 ? 0xFF : 0);
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
  fs.writeFileSync(out, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ih), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}

let frames = 0, frc = 0, tacc = 0, steps = 0, totc = 0, goc = 0;   // totc — такты с начала (замер не зависит от потерянных прерываний)
// QZ_VERIFY=1: после каждой прокрутки (qz_nscroll вырос, программа в qz_main) запомнить поле,
// выполнить qz_redraw (полная отрисовка при той же камере) и сравнить поле байт в байт
const vstat = { n: 0, bad: 0, first: null }; let lastN = 0, logN = 0;
function field() { const f = []; for (let c = 0; c < 32; c++) for (let r = 0; r < 152; r++) f.push(rd(0xE000 + (c << 8) + 0xE7 - r)); return f; }
function verify() {
  const before = field(), savedPC = cpu.pc;
  cpu.pc = L.qz_redraw; let guard = 0;
  while (cpu.pc !== L.qz_redraw_done && guard++ < 5e7) { cpu.instruction(); if (cpu.last_opcode === 0xd3) io.commit(); }
  const after = field(); let d = 0, first = null;
  for (let i = 0; i < after.length; i++) if (after[i] !== before[i]) { d++; if (!first) first = `столбец ${i / 152 | 0} строка ${i % 152}`; }
  vstat.n++; if (d) { vstat.bad++; if (!vstat.first) vstat.first = `прокрутка ${vstat.n} (${rd(0xaf2b).toString(16)}): ${d} байт, первое ${first}`; }
  cpu.pc = savedPC;
}
// QZ_PROF="кадр_от-кадр_до": такты по меткам (ближайшая метка снизу из .sld)
const PROF = (process.env.QZ_PROF || "").split("-").map(Number);
const labs = Object.entries(L).filter(([n, a]) => a < 0x4000 && !/^\.|^il_|_lp$/.test(n)).sort((a, b) => a[1] - b[1]);
const owner = new Array(0x4000).fill("?");
for (let i = 0; i < labs.length; i++) for (let a = labs[i][1]; a < (i + 1 < labs.length ? labs[i + 1][1] : 0x4000); a++) owner[a] = labs[i][0];
const prof = {}, pcp = {};
// QZ_COUNT="метка,метка": сколько раз выполнялась команда по адресу метки (в окне QZ_PROF)
const CNT = {}; for (const n of (process.env.QZ_COUNT || "").split(",").filter(Boolean)) CNT[L[n]] = { n, c: 0 };
const out = OUT || "build/demo/shot.png";
while (frames < N && steps < 5e8) {
  const pc0 = cpu.pc;
  if (pc0 === L.qz_go) goc = totc;
  const c = (cpu.instruction(), cpu.vcycles); steps++; frc += c; tacc += c; totc += c;
  if (PROF.length === 2 && frames >= PROF[0] && frames < PROF[1] && CNT[pc0]) CNT[pc0].c++;
  if (PROF.length === 2 && frames >= PROF[0] && frames < PROF[1]) { const o = pc0 < 0x4000 ? owner[pc0] : "data"; prof[o] = (prof[o] || 0) + c; pcp[pc0] = (pcp[pc0] || 0) + c; }
  if (cpu.last_opcode === 0xd3) io.commit();   // запись в порт vector06js откладывает до commit
  if (tacc > 1) { const tn = tacc >> 1; tacc -= tn * 2; timer.Count(tn); }
  if (L.qz_nscroll !== undefined && rdw(L.qz_nscroll) !== logN) { logN = rdw(L.qz_nscroll);
    if (process.env.QZ_LOG) console.log(`  прокрутка ${logN}: напр. ${rd(0xaf2b).toString(16)}, ${((totc - goc) / 59904).toFixed(1)} кадра по тактам, камера ${rd(0xaf1c)},${rd(0xaf1d)}`); }
  if (process.env.QZ_VERIFY && L.qz_nscroll !== undefined && rdw(L.qz_nscroll) !== lastN && cpu.pc === L.qz_main) { lastN = rdw(L.qz_nscroll); verify(); }
  if (frc >= 59904) {
    frc -= 59904; frames++;
    for (const s of sched) if (s.f === frames) key(s.k, s.down);
    if (shots.includes(frames)) png(out.replace(/\.png$/, `_${frames}.png`));
    v06c.irq = true; v06c.checkInterrupt();
  }
}
// QZ_BAND="напр,высота,AF2E,AF31,AF32,AF33": после прогона вызвать BE38 с таким блоком и сосчитать такты
if (process.env.QZ_BAND) {
  const [dir, h, e, r0, o2, o3] = process.env.QZ_BAND.split(",").map(x => parseInt(x));
  const blk = [0, 0x20, e, h, 0, r0, o2 & 255, o3 & 255, 0, 0];
  blk.forEach((v, i) => memory.write(0xaf2c + i, v, false)); memory.write(0xaf2b, dir, false);
  cpu.sp -= 2; memory.write(cpu.sp, L.qz_redraw_done & 255, false); memory.write(cpu.sp + 1, L.qz_redraw_done >> 8, false);
  cpu.pc = L.sub_be38h; let cyc = 0;
  while (cpu.pc !== L.qz_redraw_done) { cpu.instruction(); cyc += cpu.vcycles; if (cpu.last_opcode === 0xd3) io.commit(); }
  console.log(`полоса ${process.env.QZ_BAND}: ${cyc} тактов = ${(cyc / 59904).toFixed(1)} кадра`);
}
png(out);
if (process.env.QZ_VERIFY) console.log(`проверка прокруток: ${vstat.n} прокруток, с отличиями ${vstat.bad}${vstat.first ? " — " + vstat.first : ""}`);
if (PROF.length === 2) { const tot = Object.values(prof).reduce((a, b) => a + b, 0);
  console.log(`профиль кадров ${PROF[0]}-${PROF[1]}: ${tot} тактов`);
  if (process.env.QZ_PROFPC) { console.log("  по адресам (метка+смещение):");
    for (const [a, v] of Object.entries(pcp).sort((x, y) => y[1] - x[1]).slice(0, +process.env.QZ_PROFPC)) { const o = owner[a]; console.log(`    ${(+a).toString(16)} ${o}+${+a - L[o]} ${v}`); } }
  for (const v of Object.values(CNT)) console.log(`  счёт ${v.n}: ${v.c}`);
  for (const [k, v] of Object.entries(prof).sort((a, b) => b[1] - a[1]).slice(0, +(process.env.QZ_TOP || 25))) console.log(`  ${k.padEnd(14)} ${String(v).padStart(9)} ${(100 * v / tot).toFixed(1)}%`); }
const m = n => L[n] !== undefined ? rdw(L[n]) : "?";
console.log(`кадров ${frames}, PC=${cpu.pc.toString(16)}, полная отрисовка ${m("qz_t_full")} кадр., последняя прокрутка ${m("qz_t_scroll")} кадр., прокруток ${m("qz_nscroll")} -> ${out}`);
// QZ_CMP=файл_снимка_ZX: сравнить поле 32x152 с буфером 0x8300 снимка ОЗУ ZX (с 0x4000)
if (process.env.QZ_CMP) {
  const z = fs.readFileSync(process.env.QZ_CMP); let diff = 0, first = null;
  const TOP = 0xFF - 24;
  for (let r = 0; r < 152; r++) for (let c = 0; c < 32; c++) {
    const a = z[0x8300 - 0x4000 + r * 32 + c], b = rd(0xE000 + (c << 8) + TOP - r);
    if (a !== b) { diff++; if (!first) first = `строка ${r} столбец ${c}: ZX ${a.toString(16)} Вектор ${b.toString(16)}`; }
  }
  console.log(`сравнение с ${process.env.QZ_CMP}: отличий ${diff} из ${32 * 152}${first ? ", первое — " + first : ""}`);
}
