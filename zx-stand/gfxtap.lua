-- Обёртка run.lua: чтения таблицы t_droidgfx (A403..A4C2) -> пары (тип текущего объекта AF76, номер ячейки), в gfxuse.txt
local m = manager.machine
local cpu = m.devices[':maincpu']; local sp = cpu.spaces['program']
local use = {}
_G.qz_gfxtap = sp:install_read_tap(0xA403, 0xA4C2, 'gt', function(off, data, mask)
  if (off - 0xA403) % 2 == 0 then
    local k = string.format('%02X %d %04X', sp:read_u8(0xAF76), (off - 0xA403) // 2 + 1, cpu.state['PC'].value)
    use[k] = (use[k] or 0) + 1
  end
end)
local fr = 0
emu.register_frame_done(function()
  fr = fr + 1
  if fr % 2000 == 0 then
    local f = io.open('gfxuse.txt', 'w')
    for k, v in pairs(use) do f:write(k, ' ', v, '\n') end
    f:close()
  end
end)
dofile('run.lua')
