-- Загрузка с настоящей ленты (BASIC, LOAD ""): на старте игры (DE70) ОЗУ 4000-FFFF -> real_ram.bin, SP -> FF00.
-- mame spectrum -rompath zx-stand -cass orig/zx/quazatron.tzx -script zx-stand/tapeload.lua -debug -debugger none -nothrottle ...

local m = manager.machine
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f == 1 then
    m.debugger:command('bpset de70,1,{w@ff00=sp;save ' .. os.getenv('PWD') .. '/real_ram.bin,4000,c000;g}')
    for k, v in pairs(m.cassettes) do print('cass', k) end
  end
  if f == 150 then m.natkeyboard:post('j""\n') end
  if f == 250 then for k, c in pairs(m.cassettes) do c:play(); print('play', k, c.is_playing) end end
  if f % 2000 == 0 then
    local cpu = m.devices[':maincpu']
    print('frame', f, string.format('PC=%04X', cpu.state['PC'].value))
  end
end)
