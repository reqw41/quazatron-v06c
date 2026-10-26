#!/usr/bin/env node
// Проверка образа с заставкой (tools/mk_splash.py) в эмуляторе Вектора (vector06js): старт с 0, кадры заставки,
// клавиша (пробел) нажата и отпущена, распаковка; в момент второго входа в 0000 память 0000-7FFF и A000-FFFF — байт
// в байт образ игры. Снимки: заставка и игра через N кадров после старта (build/splash/check_*.png).
//   node tools/splash_check.js заставка.r0m игра.r0m
"use strict";
const fs = require("fs"), vm = require("vm"), path = require("path");
const base = process.env.V06JS || path.join(require("os").homedir(), "projects/vector06js");
const ROOT = path.join(__dirname, "..");
const [SPL, GAME] = process.argv.slice(2);
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
const spl = new Uint8Array(fs.readFileSync(SPL)), game = new Uint8Array(fs.readFileSync(GAME));
memory.init_from_array(spl, 0); memory.detach_boot && memory.detach_boot();
cpu.pc = 0; cpu.sp = 0; cpu.iff = false;
const rd = a => memory.bytes[memory.tobank(a)];
const shot = name => {   // плоскости + палитра (io) -> PNG через python
  const b = Buffer.alloc(16 + 0x8000); for (let i = 0; i < 16; i++) b[i] = io.Palette ? io.Palette[i] : 0;
  for (let a = 0; a < 0x8000; a++) b[16 + a] = rd(0x8000 + a);
  fs.writeFileSync(`${ROOT}/build/splash/${name}.bin`, b); };
const VFRAME = 59904; let vt = 0, frames = 0, zeroHits = 0, key = 0, done = false, keyFrame = 0;
let steps = 0;
while (frames < 2500 && !done) {
  if (cpu.pc === 0 && steps > 0) { zeroHits++;
    let bad = 0, first = -1; for (const [a0, a1] of [[0, 0x8000], [0xA000, 0x10000]]) for (let a = a0; a < a1; a++) if (rd(a) !== game[a]) { bad++; if (first < 0) first = a; }
    console.log(`вход в 0000 на кадре ${frames} (клавиша на кадре ${keyFrame}): отличий от игры ${bad}${bad ? ", первое " + first.toString(16) : ""}`);
    if (bad) process.exitCode = 1; done = true; break; }
  cpu.instruction(); steps++; const c = cpu.vcycles; if (cpu.last_opcode === 0xd3) io.commit && io.commit();
  vt += c; if (vt >= VFRAME) { vt -= VFRAME; frames++; v06c.irq = true; v06c.checkInterrupt();
    if (frames === 100) { keyboard.matrix[7] = 0x80; keyFrame = frames; }   // пробел
    if (frames === 105) keyboard.matrix[7] = 0; }
}
if (!done) { console.log(`за ${frames} кадров перехода в 0000 нет, pc ${cpu.pc.toString(16)}`); process.exitCode = 1; }
