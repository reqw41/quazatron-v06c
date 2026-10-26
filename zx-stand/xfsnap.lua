-- Обёртка run.lua: на каждом входе в xf_pickside (C9D8, провода построены) — снимок экрана и ОЗУ (xf_<n>.png/.bin в QZ_OUT)
local m = manager.machine
local OUT = os.getenv('QZ_OUT') or '.'
local fr, n, armed = 0, 0, false
emu.register_frame_done(function()
  fr = fr + 1
  local sp = m.devices[':maincpu'].spaces['program']
  if fr == 2 then m.debugger:command('bpset c9d8,1,{b@ff10=1;g}') end
  if sp:read_u8(0xFF10) == 1 then
    sp:write_u8(0xFF10, 0); armed = 3
  end
  if armed and armed > 0 then
    armed = armed - 1
    if armed == 0 and n < 6 then
      n = n + 1
      m.video:snapshot()
      local f = io.open(string.format('%s/xf_%d.bin', OUT, n), 'wb')
      for a = 0x4000, 0xFFFF do f:write(string.char(sp:read_u8(a))) end
      f:close()
      armed = false
    end
  end
end)
dofile('run.lua')
