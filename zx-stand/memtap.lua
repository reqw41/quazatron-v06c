-- Обёртка run.lua: кто пишет/читает 0x5D00-0x61A8 (стек и t_detect_old 60EE-60F5), минимум SP. Запуск: QZ_SCRIPT=memtap.lua ./run.sh

local m = manager.machine
local cpu = m.devices[':maincpu']; local sp = cpu.spaces['program']
local minw, wr, rd, minsp = 0x10000, {}, {}, 0x10000
_G.qz_taps = {
 sp:install_write_tap(0x5D00, 0x61A8, 'lw', function(off, data, mask)
   if off < minw then minw = off end
   if off >= 0x60EE and off <= 0x60F5 then local pc = cpu.state['PC'].value; wr[pc] = (wr[pc] or 0) + 1 end
 end),
 sp:install_read_tap(0x60EE, 0x60F5, 'lr', function(off, data, mask)
   local k = string.format('%04X:%02X', cpu.state['PC'].value, data); rd[k] = (rd[k] or 0) + 1
 end)}
emu.register_frame_done(function()
  local s = cpu.state['SP'].value; if s < minsp then minsp = s end
end)
local function rep()
  print(string.format('min write addr %04X, min SP(frame) %04X', minw, minsp))
  for k, v in pairs(wr) do print(string.format('write 60EE.. PC=%04X x%d', k, v)) end
  for k, v in pairs(rd) do print('read', k, v) end
end
local fr=0
emu.register_frame_done(function() fr=fr+1; if fr%3000==0 then print('fr',fr); rep() end end)
dofile((os.getenv("QZ_STAND") or ".") .. "/run.lua")
