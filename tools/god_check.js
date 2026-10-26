#!/usr/bin/env node
// Режим бога (F1 + F3 на заставке игры): образ i8080 в эмуляторе Вектора, старт клавишами (F1+F3 или пробел), дальше
// случайные стрелки и огонь; итог — минимум энергии v_energy, входов в plr_die, флаг god.
//   node tools/god_check.js образ.r0m god|space [кадров]
"use strict";
const fs = require("fs"), vm = require("vm"), path = require("path");
const base = process.env.V06JS || path.join(require("os").homedir(), "projects/vector06js");
const ROOT = path.join(__dirname, "..");
const [IMG, MODE, NF] = [process.argv[2], process.argv[3], +process.argv[4] || 6000];
const g = {}; g.window = g; g.document = { createElement: () => fc(), getElementById: () => fc() };
function fcx() { return { createImageData: () => ({ data: new Uint8ClampedArray(4) }), putImageData() {}, getImageData: () => ({ data: new Uint8ClampedArray(4) }), fillRect() {}, drawImage() {} }; }
function fc() { return { width: 0, height: 0, style: {}, getContext: () => fcx() }; }
g.requestAnimationFrame = () => 0; g.setTimeout = () => 0; g.print = () => 0;
g.console = { log() {}, debug() {}, warn() {}, error() {}, info() {} };
const ctx = vm.createContext(g);
for (const f of ["i8080-js/i8080_trace.js", "i8080-js/i8080_disasm.js", "i8080-js/i8080.js",
  "src/fili.js", "src/ay.js", "src/fd1793.js", "src/fddimage.js", "src/i8253.js", "src/io.js", "src/keyboard.js", "src/memory.js",
  "src/sound.js", "src/tv.js"]) vm.runInContext(fs.readFileSync(base + "/" + f, "utf8"), ctx, { filename: f });
const memory = new ctx.Memory(), keyboard = new ctx.Keyboard(), timer = new ctx.I8253(), ay = new ctx.AY(),
  floppy = new (ctx.Floppy().FD1793)(), io = new ctx.IO(keyboard, timer, memory, ay, floppy);
const cpu = new ctx.I8080(memory, io), v06c = new ctx.Vector06c(cpu, memory, io, ay, { advance() {}, sample: 0, reset() {} });
memory.init_from_array(new Uint8Array(fs.readFileSync(IMG)), 0); memory.detach_boot && memory.detach_boot();
cpu.pc = 0; cpu.sp = 0; cpu.iff = false;
const rd = a => memory.bytes[memory.tobank(a)];
const pm = new Map(fs.readFileSync(IMG.replace(/\.r0m$/, "").replace(/quaz_8080(_ru)?$/, "pcmap$1") + ".txt", "utf8").trim().split("\n").map(l => l.split(" ").map(x => parseInt(x, 16))));
const PLR_DIE = pm.get(0xE3EB - 0xDE70 + 0x4000), TITLE = pm.get(0xDE94 - 0xDE70 + 0x4000), RESET = pm.get(0xB87C), POLL = pm.get(0xB61F);
const HIST = new Map();
const ev = []; let polls = 0;
const GODA = (() => { for (const l of fs.readFileSync(ROOT + "/build/port/glue.sld", "latin1").split("\n")) { const p = l.split("|"); if (p.length >= 8 && p[6] === "L" && p[7].split(",")[1] === "god") return +p[5]; } })();
let rs = 7; const rnd = () => { rs ^= rs << 13; rs >>>= 0; rs ^= rs >>> 17; rs ^= rs << 5; rs >>>= 0; return rs; };
const VFRAME = 59904; let vt = 0, frames = 0, dies = 0, emin = 255, started = false;
while (frames < NF) {
  HIST.set(cpu.pc, (HIST.get(cpu.pc) || 0) + 1);
  if (cpu.pc === PLR_DIE) dies++;
  if (cpu.pc === TITLE && ev.length < 6) ev.push('заставка@' + frames); if (cpu.pc === RESET && ev.length < 6) ev.push('game_reset@' + frames); if (cpu.pc === POLL) polls++;
  cpu.instruction(); if (cpu.last_opcode === 0xd3) io.commit && io.commit();
  vt += cpu.vcycles; if (vt >= VFRAME) { vt -= VFRAME; frames++; v06c.irq = true; v06c.checkInterrupt();
    if (frames === 60) keyboard.matrix[2] = 0x10; if (frames === 70) keyboard.matrix[2] = 0;    // меню: 4 (Kempston), ВК
    if (frames === 120) keyboard.matrix[0] = 0x04; if (frames === 130) keyboard.matrix[0] = 0;
    if (frames === 400) { if (MODE === "god") keyboard.matrix[1] = 0x28; else keyboard.matrix[7] = 0x80; }
    if (frames === 410) { keyboard.matrix[1] = 0; keyboard.matrix[7] = 0; started = true; }
    if (started && frames > 600 && frames % 25 === 0) { keyboard.matrix[0] = [0x10, 0x20, 0x40, 0x80, 0x30, 0x90][rnd() % 6]; keyboard.matrix[7] = rnd() & 1 ? 0x80 : 0; }
    if (started && frames > 600) emin = Math.min(emin, rd(0xAF93)); } }
console.log(ev.join(' '), 'опросов', polls, [...HIST].sort((a,b)=>b[1]-a[1]).slice(0,8).map(([k,n])=>k.toString(16)+'×'+n).join(' ')); console.log(`${MODE}: кадров ${frames}, god = ${rd(GODA)}, минимум энергии ${emin}, входов в plr_die ${dies}`);
