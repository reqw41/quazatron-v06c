-- снимок экрана на кадре N (QZ_FRAME, по умолчанию 300), затем выход.
-- QZ_KEYS="кадр/поле/метка,..." — нажать клавишу на 5 кадров (поле MAME, напр. :LINE6, метка "ENTER")
local N = tonumber(os.getenv('QZ_FRAME') or '300')
local keys = {}
for fr, port, name in string.gmatch(os.getenv('QZ_KEYS') or '', '(%d+)/([^/,]+)/([^,]+)') do
  keys[#keys+1] = {tonumber(fr), port, name}
end
local function field(port, name)
  local p = manager.machine.ioport.ports[port]
  for fname, f in pairs(p.fields) do if fname:upper():find(name:upper(), 1, true) then return f end end
end
local f = 0
emu.register_frame_done(function()
  f = f + 1
  for _, k in ipairs(keys) do
    local fl = field(k[2], k[3])
    if fl then
      if f == k[1] then fl:set_value(1) elseif f == k[1] + 5 then fl:clear_value() end
    end
  end
  if f == N then manager.machine.video:snapshot(); manager.machine:exit() end
end)
