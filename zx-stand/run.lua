-- Стенд Quazatron в MAME (запуск с -exp kempjoy -debug -debugger none, если нужна трасса).
-- Старт: меню «4» (Kempston), ENTER, огонь. Сценарий движения — QZ_MOVES="кадр:Right+Up,кадр:,..."
-- (пусто = отпустить; Fire — огонь, например 900:Fire или 900:Up+Fire). Переменные:
--   QZ_END     последний кадр (по умолчанию 1400)
--   QZ_SHOT    снимок каждые N кадров начиная с 900 (0 = только на последнем)
--   QZ_TRACE   "T0-T1": трасса с тактами в prof.tr
--   QZ_TAP     1: записи в экран 0x4000-0x5AFF — по кадрам в scrcount.txt, по PC в scrpcs.txt
--   QZ_DUMP    "кадр": ОЗУ 0x4000-0xFFFF в dump_<кадр>.bin
--   QZ_DBG     команды отладчика MAME через ';;' (на кадре 1), например точка останова с записью в память:
--              "bpset df76,1,{b@af0b=0;b@af20=18;b@af21=18;g}" (нужен -debug)
--   QZ_POKE    "адрес=значение@с-по,...": писать байт в память на каждом кадре в диапазоне (hex адрес и значение)
--   QZ_CTRL    клавиша выбора управления в меню (1 клавиатура, 2 курсор, 3 Sinclair, 4 Kempston — по умолчанию)
--   QZ_KEYS    "кадр:LINEn:Клавиша,..." — нажатия клавиш ZX (6 кадров), LINE0 CAPS..V, 1 A..G, 2 Q..T, 3 1..5, 4 0..6, 5 P..Y, 6 ENTER..H, 7 SPACE..B
--   QZ_RANDOM  зерно: случайная игра с кадра 800 — каждые 10..60 кадров новое направление (или стоять),
--              огонь с вероятностью 1/3; QZ_TRACEFILE — имя файла трассы (можно FIFO)
local m = manager.machine
local END = tonumber(os.getenv('QZ_END') or '1400')
local SHOT = tonumber(os.getenv('QZ_SHOT') or '0')
local T0, T1 = (os.getenv('QZ_TRACE') or ''):match('(%d+)-(%d+)')
T0, T1 = tonumber(T0), tonumber(T1)
local TAP = os.getenv('QZ_TAP') == '1'
local DUMP = {}
for d in (os.getenv('QZ_DUMP') or ''):gmatch('%d+') do DUMP[tonumber(d)] = true end
local RSEED = tonumber(os.getenv('QZ_RANDOM') or '')
local TRACEFILE = os.getenv('QZ_TRACEFILE') or 'prof.tr'
local POKES = {}
for a, v, f0, f1 in (os.getenv('QZ_POKE') or ''):gmatch('(%x+)=(%x+)@(%d+)%-(%d+)') do
  POKES[#POKES + 1] = { tonumber(a, 16), tonumber(v, 16), tonumber(f0), tonumber(f1) }
end
local MOVES = {}
for fr, dirs in (os.getenv('QZ_MOVES') or '900:Right'):gmatch('(%d+):([%a+]*)') do MOVES[tonumber(fr)] = dirs end

local function field(port, prefix)
  for name, f in pairs(m.ioport.ports[port].fields) do
    if name:sub(1, #prefix) == prefix then return f end
  end
end
local JOY = ':exp:kempjoy:JOY'
local DIRS = { 'Up', 'Down', 'Left', 'Right' }
local function set_dirs(s)
  for _, d in ipairs(DIRS) do
    local f = field(JOY, 'P1 ' .. d)
    if s:find(d) then f:set_value(1) else f:clear_value() end
  end
  local fb = field(JOY, 'P1 Button 1')
  if s:find('Fire') then fb:set_value(1) else fb:clear_value() end
end
local press = { {200, ':LINE3', os.getenv('QZ_CTRL') or '4'}, {300, ':LINE6', 'E'}, {700, JOY, 'P1 Button 1'} }
-- QZ_KEYS="кадр:LINEn:Клавиша,...": нажать клавишу ZX на 6 кадров (имя поля MAME начинается с Клавиша: буквы строчные, например LINE5:p, LINE6:ENTER)
for fr, ln, k in (os.getenv('QZ_KEYS') or ''):gmatch('(%d+):(LINE%d):([^,]+)') do press[#press + 1] = { tonumber(fr), ':' .. ln, k } end

local cpu, space, tap
local n, pcs = 0, {}
local cnt = TAP and io.open('scrcount.txt', 'w')
local f = 0
local rnext = -1
emu.register_frame_done(function()
  f = f + 1
  if f == 1 then
    cpu = m.devices[':maincpu']; space = cpu.spaces['program']
    local dbg = (os.getenv('QZ_DBG') or '') .. ';;'
    local p0 = 1
    while true do
      local i = dbg:find(';;', p0, true)
      if not i then break end
      local c = dbg:sub(p0, i - 1)
      if c:match('%S') then m.debugger:command(c) end
      p0 = i + 2
    end
    if TAP then
      tap = space:install_write_tap(0x4000, 0x5AFF, 'scr', function(off, data, mask)
        n = n + 1
        local pc = cpu.state['PC'].value
        pcs[pc] = (pcs[pc] or 0) + 1
      end)
    end
  end
  for _, p in ipairs(press) do
    local k = field(p[2], p[3])
    if f == p[1] then k:set_value(1) elseif f == p[1] + 5 then k:clear_value() end
  end
  if MOVES[f] then set_dirs(MOVES[f]) end
  for _, p in ipairs(POKES) do
    if f >= p[3] and f <= p[4] then space:write_u8(p[1], p[2]) end
  end
  if RSEED then
    if f == 800 then math.randomseed(RSEED); rnext = 800 end
    if f >= 800 and f == rnext then
      local opts = { '', 'Up', 'Down', 'Left', 'Right', 'Up+Left', 'Up+Right', 'Down+Left', 'Down+Right' }
      set_dirs(opts[math.random(#opts)])
      local fb = field(JOY, 'P1 Button 1')
      if math.random(3) == 1 then fb:set_value(1) else fb:clear_value() end
      rnext = f + math.random(10, 60)
    end
  end
  if T0 and f == T0 then m.debugger:command('trace ' .. TRACEFILE .. ',0,noloop,{tracelog "%d,", totalcycles}') end
  if T1 and f == T1 then m.debugger:command('trace off') end
  if cnt and f >= 700 then cnt:write(f, ' ', n, '\n') end
  n = 0
  if DUMP[f] then
    local fh = io.open('dump_' .. f .. '.bin', 'wb')
    for a = 0x4000, 0xFFFF do fh:write(string.char(space:read_u8(a))) end
    fh:close()
  end
  if (SHOT > 0 and f >= 900 and f % SHOT == 0) or f == END then m.video:snapshot() end
  if f == END then
    if cnt then
      cnt:close()
      local fh = io.open('scrpcs.txt', 'w')
      for pc, c in pairs(pcs) do fh:write(string.format('%04X %d\n', pc, c)) end
      fh:close()
    end
    m:exit()
  end
end)
