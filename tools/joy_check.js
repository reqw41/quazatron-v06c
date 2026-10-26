#!/usr/bin/env node
// Джойстик «П» (ВВ55 №2, порт 6 за портом 5 = 9Fh): образ в эмуляторе Вектора, клавиатура не трогается.
// Меню: 2 (джойстик), ВК; старт игры — огонь джойстика; затем каждое направление по 100 кадров — игрок обязан сдвинуться
// (v_cam, v_plr_sx/sy). Порт 0Eh отдаёт «нажато всё» — его чтение сорвало бы проверку.
//   node tools/joy_check.js build/port8080/quaz_8080[_ru].r0m — только i8080 (эмулятор без Z80), без заставки; код 1 — провал
//   QZ_JOYDEAD=1 …                          — порт 6 молчит (негативный контроль: проверка обязана покраснеть)
"use strict";
const fs = require("fs"), vm = require("vm"), path = require("path");
const base = process.env.V06JS || path.join(require("os").homedir(), "projects/vector06js");
const ROOT = path.join(__dirname, "..");
const IMG = process.argv[2], DEAD = process.env.QZ_JOYDEAD === "1";
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
const JR = 1, JL = 2, JU = 4, JD = 8, JF = 0x40; let JOY = 0xFF;
const _in = io.input.bind(io);
io.input = p => { p &= 0xFF; if (p === 6) return DEAD ? 0xFF : JOY; if (p === 0x0E) return 0x00; return _in(p); };
const rd = a => memory.bytes[memory.tobank(a)];
const pmf = IMG.replace(/quaz_8080(_ru)?(_splash)?\.r0m$/, "pcmap$1.txt");    // i8080: адреса ZX -> адреса перевода
const pm = pmf.endsWith(".txt") ? new Map(fs.readFileSync(pmf, "utf8").trim().split("\n").map(l => l.split(" ").map(x => parseInt(x, 16)))) : null;
const RESET = pm ? pm.get(0xB87C) : 0xB87C;
const sig = () => [0xAF1C, 0xAF1D, 0xAF94, 0xAF95].map(rd).join(",");
const PLAN = [["вправо", JR], ["вниз", JD], ["влево", JL], ["вверх", JU]];
const VFRAME = 59904; let vt = 0, frames = 0, started = -1, prev = "", moved = {}, cur = null;
const T0 = 500;
while (frames < T0 + 60 + PLAN.length * 130) {
  if (cpu.pc === RESET && started < 0 && frames >= 395) started = frames;    // первый game_reset — на выходе из меню
  cpu.instruction(); if (cpu.last_opcode === 0xd3) io.commit && io.commit();
  vt += cpu.vcycles; if (vt >= VFRAME) { vt -= VFRAME; frames++; v06c.irq = true; v06c.checkInterrupt();
    if (frames === 60) keyboard.matrix[2] = 0x04; if (frames === 70) keyboard.matrix[2] = 0;    // меню: 2 (джойстик), ВК
    if (frames === 120) keyboard.matrix[0] = 0x04; if (frames === 130) keyboard.matrix[0] = 0;
    if (frames === 400) JOY = 0xFF & ~JF; if (frames === 410) JOY = 0xFF;                   // огонь — старт
    const t = frames - T0 - 60;
    if (t >= 0) { const i = Math.floor(t / 130), k = t % 130;
      if (i < PLAN.length) { cur = PLAN[i][0]; JOY = k < 100 ? 0xFF & ~PLAN[i][1] : 0xFF;
        const s = sig(); if (k > 0 && k < 100 && s !== prev) moved[cur] = (moved[cur] || 0) + 1; prev = s; } } } }
const ok = started >= 0 && PLAN.every(([n]) => moved[n] > 0);
console.log(`джойстик «П»${DEAD ? " (порт 6 молчит)" : ""}: старт огнём ${started >= 0 ? "на кадре " + started : "НЕТ"}; ` +
  PLAN.map(([n]) => `${n} ${moved[n] || 0}`).join(", ") + ` — ${ok ? "OK" : "FAIL"}`);
process.exit(ok ? 0 : 1);
