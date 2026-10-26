#!/usr/bin/env node
// Снимок i8080 (tools/lockstep.js QZ_LS_DUMPPOLL) — в полный эмулятор Вектора (vector06js): как есть (i8080) или переведённым
// в сборку Z80 (данные общие, стек и PC — через pcmap). Ввод — матрица из снимка, без изменений.
//   node tools/vsnap.js снимок.json 8080|z80 [кадров] [--ru]  -> опросов input_read, частые места
"use strict";
const fs = require("fs"), vm = require("vm"), path = require("path");
const base = process.env.V06JS || path.join(require("os").homedir(), "projects/vector06js");
const ROOT = path.join(__dirname, "..");
const [SNAP, CPU, NF] = [process.argv[2], process.argv[3], +process.argv[4] || 3000];
const SUF = process.argv.includes("--ru") ? "_ru" : "", Z = CPU === "z80";
const st = JSON.parse(fs.readFileSync(SNAP, "utf8")), d = Buffer.from(st.mem, "base64");
const map = new Map(), rev = new Map();
for (const l of fs.readFileSync(`${ROOT}/build/port8080/pcmap${SUF}.txt`, "utf8").trim().split("\n")) {
  const [a, b] = l.split(" ").map(x => parseInt(x, 16)); map.set(a, b); if (!rev.has(b)) rev.set(b, a); }
const XC = Object.fromEntries(fs.readFileSync(`${ROOT}/build/port8080/xc${SUF}.txt`, "utf8").trim().split("\n").map(l => { const [k, ...v] = l.split(" "); return [k, v]; }));
const XR = fs.readFileSync(`${ROOT}/build/port8080/layout${SUF}.txt`, "utf8").trim().split(" ").map(x => parseInt(x, 16));   // пары начало конец добавок
const inX = a => { for (let k = 0; k < XR.length; k += 2) if (a >= XR[k] && a < XR[k + 1]) return true; return false; };
const L8 = {}; for (const l of fs.readFileSync(`${ROOT}/build/port8080/quaz_8080${SUF}.sld`, "latin1").split("\n")) { const p = l.split("|"); if (p.length >= 8 && p[6] === "L") { const n = p[7].split(",")[1]; if (n && !(n in L8)) L8[n] = +p[5]; } }
const VEC_KB = (() => { for (const l of fs.readFileSync(ROOT + "/build/port/glue.sld", "latin1").split("\n")) {
  const p = l.split("|"); if (p.length >= 8 && p[6] === "L" && p[7].split(",")[1] === "vec_kb") return +p[5]; } })();

const g = {}; g.window = g; g.document = { createElement: () => fc(), getElementById: () => fc() };
function fcx() { return { createImageData: () => ({ data: new Uint8ClampedArray(4) }), putImageData() {}, getImageData: () => ({ data: new Uint8ClampedArray(4) }), fillRect() {}, drawImage() {} }; }
function fc() { return { width: 0, height: 0, style: {}, getContext: () => fcx() }; }
g.requestAnimationFrame = () => 0; g.setTimeout = () => 0; g.print = () => 0;
g.console = { log() {}, debug() {}, warn() {}, error() {}, info() {} };
const ctx = vm.createContext(g);
for (const f of ["i8080-js/i8080_trace.js", "i8080-js/i8080_disasm.js", "i8080-js/i8080.js", "Z80_v06.js", ...(Z ? ["z80_adapter.js"] : []),
  "src/fili.js", "src/ay.js", "src/fd1793.js", "src/fddimage.js", "src/i8253.js", "src/io.js", "src/keyboard.js", "src/memory.js",
  "src/sound.js", "src/tv.js"]) vm.runInContext(fs.readFileSync(base + "/" + f, "utf8"), ctx, { filename: f });
const memory = new ctx.Memory(), keyboard = new ctx.Keyboard(), timer = new ctx.I8253(), ay = new ctx.AY(),
  floppy = new (ctx.Floppy().FD1793)(), io = new ctx.IO(keyboard, timer, memory, ay, floppy);
const cpu = new ctx.I8080(memory, io), v06c = new ctx.Vector06c(cpu, memory, io, ay, { advance() {}, sample: 0, reset() {} });
v06c.bmp = new Uint32Array(576 * 288); v06c.displayFrame = () => {}; v06c.check_breakpoint = () => false; v06c.dbg = null;
const img = new Uint8Array(fs.readFileSync(Z ? `${ROOT}/build/port/quaz_z80${SUF}.r0m` : `${ROOT}/build/port8080/quaz_8080${SUF}.r0m`));
const codeZ = new Uint8Array(0x10000);
for (const r of XC.code) { const [x, y] = r.split("-").map(v => parseInt(v, 16)); for (let a = x; a < y; a++) codeZ[a] = 1; }
const m = new Uint8Array(img);
for (let a = 0; a < 0x10000; a++) if (!Z || (!codeZ[a] && !inX(a))) m[a] = d[a];
const w = a => d[a] | d[a + 1] << 8;
if (Z) for (let a = st.sp; a < 0x61A5; a += 2) { const v = w(a); if (rev.has(v)) { const z = rev.get(v); m[a] = z & 255; m[a + 1] = z >> 8; } }
memory.init_from_array(m, 0); memory.detach_boot && memory.detach_boot();
for (let i = 0; i < 8; i++) keyboard.matrix[i] = d[VEC_KB + i];
io.output(2, 0); io.commit && io.commit();
if (Z) { const s = cpu.getState(); for (const n of ["a", "b", "c", "d", "e", "h", "l"]) s[n] = st[n];
  s.flags = { S: st.f >> 7 & 1, Z: st.f >> 6 & 1, Y: 0, H: 0, X: 0, P: 0, N: 0, C: st.f & 1 };
  const af2 = w(L8.z_af2), bc2 = w(L8.z_bc2), de2 = w(L8.z_de2), hl2 = w(L8.z_hl2);
  s.a_prime = af2 >> 8; s.flags_prime = { S: af2 >> 7 & 1, Z: af2 >> 6 & 1, Y: 0, H: 0, X: 0, P: 0, N: 0, C: af2 & 1 };
  s.b_prime = bc2 >> 8; s.c_prime = bc2 & 255; s.d_prime = de2 >> 8; s.e_prime = de2 & 255; s.h_prime = hl2 >> 8; s.l_prime = hl2 & 255;
  s.ix = w(L8.z_ix); s.sp = st.sp; s.pc = rev.get(st.pc); s.iff1 = s.iff2 = st.iff ? 1 : 0; s.imode = 1; cpu.setState(s); }
else { [["b", 0], ["c", 1], ["d", 2], ["e", 3], ["h", 4], ["l", 5], ["a", 7]].forEach(([n, i]) => cpu.regs[i] = st[n]); cpu.retrieve_flags(st.f); cpu.sp = st.sp; cpu.pc = st.pc; cpu.iff = st.iff; }
const POLL = Z ? 0xB61F : map.get(0xB61F), MAIN = Z ? 0xE0DC : map.get(0xE0DC);
const TR = [];
const VFRAME = 59904; let vt = 0, vtacc = 0, frames = 0, polls = 0, mains = 0; const hist = new Map();
while (frames < NF) {
  const p = cpu.pc; if (p === POLL) polls++; if (p === MAIN) mains++;
  hist.set(p, (hist.get(p) || 0) + 1); if (TR.length < 3000000) TR.push(p.toString(16));
  cpu.instruction(); const c = cpu.vcycles; if (cpu.last_opcode === 0xd3) io.commit();
  vtacc += c; if (vtacc > 1) { const tn = vtacc >> 1; vtacc -= tn * 2; timer.Count(tn); }
  vt += c; if (vt >= VFRAME) { vt -= VFRAME; frames++; v06c.irq = true; v06c.checkInterrupt(); }
}
fs.writeFileSync(`build/port8080/trace_snap_${CPU}.txt`, TR.join("\n"));
// QZ_VS_RAW=файл — кадр в конце прогона: палитра 16 x ARGB (io.Palette) + плоскости 8000-FFFF (tools/vraw_png.py)
if (process.env.QZ_VS_RAW) { const b = Buffer.alloc(64 + 0x8000); for (let i = 0; i < 16; i++) b.writeUInt32LE(io.Palette[i] >>> 0, i * 4);
  for (let a = 0; a < 0x8000; a++) b[64 + a] = memory.bytes[memory.tobank(0x8000 + a)]; fs.writeFileSync(process.env.QZ_VS_RAW, b); }
const nm = q => (Z ? q : (rev.has(q) ? rev.get(q) : null));
console.log(`${CPU}: кадров ${frames}, опросов ${polls}, проходов main_loop ${mains}; частые: ` +
  [...hist].sort((a, b) => b[1] - a[1]).slice(0, 12).map(([q, n]) => `${q.toString(16)}${!Z && rev.has(q) ? "=" + rev.get(q).toString(16) : ""}×${n}`).join(" "));
