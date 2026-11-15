--[[
  Station renderer - INSIDE the habitat
  =====================================
  Inside, the habitat is shown as a cut-away: dark metal superstructure
  around the rooms (no Moon surface is visible from inside).
  Static layer (built once into a canvas): superstructure, hull walls,
  corridors, floors (rubber mats in the power rooms), back walls with signs,
  floor markings (hazard stripes, drain grates, moisture strips).
  Live layer (every frame): sliding doors (locked doors stay shut with a red
  light), wall screens, gas chart, sirens and alarms.
]]
local Theme = require("src.ui.theme")
local Map = require("src.station_map")
local Assets = require("src.assets")
local C = Theme.C

local R = {}
R.__index = R

local HULL = 16

function R.new()
  local self = setmetatable({}, R)
  self.doorOpen = {}
  for i = 1, #Map.doors do self.doorOpen[i] = 0 end
  return self
end

------------------------------------------------------------------------------
-- Static canvas
------------------------------------------------------------------------------

local function expand(r, p) return r.x - p, r.y - p, r.w + 2 * p, r.h + 2 * p end

local function allShells()
  local list = {}
  for _, r in ipairs(Map.rooms) do
    list[#list + 1] = r
    if r.extra then for _, e in ipairs(r.extra) do list[#list + 1] = e end end
  end
  for _, c in ipairs(Map.corridors) do list[#list + 1] = c end
  return list
end

-- Dark metal superstructure between the rooms (big riveted plates + conduits)
local function drawSuperstructure(lg)
  Theme.set(Theme.hex("#100E26")); lg.rectangle("fill", 0, 0, Map.WIDTH, Map.HEIGHT)
  local step = 160
  for x = 0, Map.WIDTH, step do
    for y = 0, Map.HEIGHT, step do
      local shade = ((x / step + y / step) % 2 == 0) and "#15132F" or "#131129"
      Theme.set(Theme.hex(shade)); lg.rectangle("fill", x + 3, y + 3, step - 6, step - 6, 6, 6)
      Theme.set(Theme.hex("#1D1A3C"))
      for _, p in ipairs({ { 12, 12 }, { step - 12, 12 }, { 12, step - 12 }, { step - 12, step - 12 } }) do
        lg.circle("fill", x + p[1], y + p[2], 3)
      end
    end
  end
  -- conduits (pipes and cable runs) behind the hull
  local runs = {
    { 0, 560, 2400, 560 }, { 0, 1540, 2400, 1540 }, { 760, 0, 760, 2400 }, { 1760, 0, 1760, 2400 },
    { 0, 2080, 900, 2080 }, { 1450, 700, 1450, 1600 },
  }
  for i, r in ipairs(runs) do
    Theme.set(Theme.hex("#0A0919")); lg.setLineWidth(18); lg.line(r)
    Theme.set(i % 2 == 0 and Theme.hex("#2B3157") or Theme.hex("#262046")); lg.setLineWidth(10); lg.line(r)
    Theme.set(Theme.hex("#3A4274"), 0.6); lg.setLineWidth(2)
    lg.line(r[1], r[2] - 3, r[3], r[4] - 3)
  end
  lg.setLineWidth(1)
end

local function drawHull(lg)
  local shells = allShells()
  Theme.set(C.ink, 0.5)
  for _, r in ipairs(shells) do local x, y, w, h = expand(r, HULL); lg.rectangle("fill", x + 8, y + 12, w, h, 10, 10) end
  Theme.set(C.ink)
  for _, r in ipairs(shells) do local x, y, w, h = expand(r, HULL + 4); lg.rectangle("fill", x, y, w, h, 12, 12) end
  Theme.set(C.hullDark)
  for _, r in ipairs(shells) do local x, y, w, h = expand(r, HULL); lg.rectangle("fill", x, y, w, h, 10, 10) end
  Theme.set(C.hullShade)
  for _, r in ipairs(shells) do local x, y, w, h = expand(r, HULL - 4); lg.rectangle("fill", x, y - 2, w, h - 4, 8, 8) end
end

local function grid(lg, f, step, color)
  Theme.set(color)
  for x = f.x + step, f.x + f.w - 1, step do lg.rectangle("fill", x, f.y, 2, f.h) end
  for y = f.y + step, f.y + f.h - 1, step do lg.rectangle("fill", f.x, y, f.w, 2) end
end

local function drawCorridors(lg)
  for _, c in ipairs(Map.corridors) do
    Theme.set(C.corridor); lg.rectangle("fill", c.x, c.y, c.w, c.h)
    Theme.set(C.grate)
    if c.w >= c.h then
      for x = c.x + 10, c.x + c.w - 4, 26 do lg.rectangle("fill", x, c.y + 26, 10, c.h - 52) end
    else
      for y = c.y + 10, c.y + c.h - 4, 26 do lg.rectangle("fill", c.x + 26, y, c.w - 52, 10) end
    end
  end
  Theme.set(C.cyan, 0.35)
  for _, c in ipairs(Map.corridors) do
    if c.w >= c.h then
      lg.rectangle("fill", c.x, c.y + 6, c.w, 4); lg.rectangle("fill", c.x, c.y + c.h - 10, c.w, 4)
    else
      lg.rectangle("fill", c.x + 6, c.y, 4, c.h); lg.rectangle("fill", c.x + c.w - 10, c.y, 4, c.h)
    end
  end
end

local function floorParts(r)
  local parts = { Map.roomFloor(r) }
  if r.extra then for _, e in ipairs(r.extra) do parts[#parts + 1] = Map.extraFloor(e) end end
  return parts
end

-- Interlocking black rubber safety mats (power rooms)
local function rubberMats(lg, p)
  local mat = Assets.image("assets/props/rubber_mat.png")
  Theme.set(Theme.hex("#1E1F2A")); lg.rectangle("fill", p.x, p.y, p.w, p.h)
  if not mat then return end
  lg.push("all")
  lg.setScissor(p.x, p.y, p.w, p.h)
  local w = 150
  local s = w / mat:getWidth()
  local h = mat:getHeight() * s * 0.82
  lg.setColor(1, 1, 1)
  for y = p.y - 10, p.y + p.h, h do
    for x = p.x - 10, p.x + p.w, w * 0.92 do lg.draw(mat, x, y, 0, s, s) end
  end
  lg.pop()
end

local FLOOR_TINT = {
  quarters = "#3A3358", airlock = "#33354F", water = "#29395A", food = "#2C3E46",
  waste = "#35304A", air = "#2B3A55", comms = "#28304F",
}

local function drawRoomFloor(lg, r)
  local accent = Theme.ROOM[r.id] or C.cyan
  for _, p in ipairs(floorParts(r)) do
    if r.id == "power" or r.id == "batteries" then
      rubberMats(lg, p)
    else
      Theme.set(Theme.hex(FLOOR_TINT[r.id] or "#2C3254")); lg.rectangle("fill", p.x, p.y, p.w, p.h)
      grid(lg, p, 64, Theme.darken(Theme.hex(FLOOR_TINT[r.id] or "#2C3254"), 0.25))
      Theme.set(C.white, 0.06)
      for x = p.x + 4, p.x + p.w - 4, 64 do for y = p.y + 4, p.y + p.h - 4, 64 do lg.rectangle("fill", x, y, 28, 2) end end
    end
    -- accent trim around the floor
    Theme.set(accent, 0.35); lg.setLineWidth(3); lg.rectangle("line", p.x + 4, p.y + 4, p.w - 8, p.h - 8, 6, 6); lg.setLineWidth(1)
  end
  local f = Map.roomFloor(r)
  Theme.set(C.ink, 0.45); lg.rectangle("fill", f.x, f.y, f.w, 16)
end

local function drawBackWall(lg, r)
  local accent = Theme.ROOM[r.id] or C.cyan
  local x, y, w = r.x + Map.HULL_GAP, r.y + 6, r.w - 2 * Map.HULL_GAP
  local h = Map.WALL - 6
  Theme.set(C.wallFace); lg.rectangle("fill", x, y, w, h)
  for px = x + 10, x + w - 60, 96 do
    Theme.set(C.wallPanel); lg.rectangle("fill", px, y + 10, 84, h - 30, 4, 4)
    Theme.set(C.wallTrim); lg.setLineWidth(2); lg.rectangle("line", px, y + 10, 84, h - 30, 4, 4); lg.setLineWidth(1)
  end
  Theme.set(C.wallTrim); lg.rectangle("fill", x, y + h - 12, w, 12)
  Theme.set(accent, 0.9); lg.rectangle("fill", x, y + h - 16, w, 4)
  Theme.set(accent, 0.25); lg.rectangle("fill", x, y + h - 22, w, 6)
  Theme.set(C.ink); lg.setLineWidth(3); lg.rectangle("line", x, y, w, h); lg.setLineWidth(1)
end

-- Room name signs, placed where no door or wall-mounted prop covers them
local SIGN_AT = {
  power = { 250, 172 }, water = { 1180, 14 }, quarters = { 2225, 14 }, airlock = { 360, 742 },
  comms = { 1958, 792, 14 }, batteries = { 120, 1622 }, food = { 1880, 1394 }, air = { 1300, 1630, 14 },
  waste = { 1150, 2020 },
}
local function drawSign(lg, r)
  local accent = Theme.ROOM[r.id] or C.cyan
  local p = SIGN_AT[r.id] or { r.x + 30, r.y + 12 }
  local font = Theme.font(p[3] or 16)
  lg.setFont(font)
  local tw = require("src.i18n").width(font, r.name) + 26
  local sx, sy = p[1], p[2]
  local pts = Theme.cutPoints(sx, sy, tw, 28, 9)
  Theme.set(C.space, 0.95); lg.polygon("fill", pts)
  Theme.set(accent); lg.setLineWidth(2); lg.polygon("line", pts); lg.setLineWidth(1)
  Theme.set(accent); lg.printf(r.name, sx, sy + 14 - font:getHeight() / 2, tw, "center")
end

local function hazardStripes(lg, x, y, w, h)
  lg.push("all")
  lg.setScissor(x, y, w, h)
  for i = -30, 60 do
    Theme.set((i % 2 == 0) and C.caution or C.ink, 0.9)
    lg.polygon("fill", x + i * 14, y, x + i * 14 + 14, y, x + i * 14 + 4 - h * 0.3, y + h, x + i * 14 - 10 - h * 0.3, y + h)
  end
  lg.pop()
  Theme.set(C.ink); lg.setLineWidth(2); lg.rectangle("line", x, y, w, h); lg.setLineWidth(1)
end

local function drawDoorFloors(lg)
  for _, d in ipairs(Map.doors) do
    Theme.set(C.corridor); lg.rectangle("fill", d.x, d.y, d.w, d.h)
    lg.push("all")
    lg.setScissor(d.x, d.y, d.w, d.h)
    for i = -10, 20 do
      Theme.set((i % 2 == 0) and C.caution or C.ink, 0.85)
      if d.vertical then
        lg.polygon("fill", d.x, d.y + i * 14, d.x + d.w, d.y + i * 14 - 10, d.x + d.w, d.y + i * 14 + 4, d.x, d.y + i * 14 + 14)
      else
        lg.polygon("fill", d.x + i * 14, d.y, d.x + i * 14 + 14, d.y, d.x + i * 14 + 4, d.y + d.h, d.x + i * 14 - 10, d.y + d.h)
      end
    end
    lg.pop()
    Theme.set(C.corridor)
    if d.vertical then lg.rectangle("fill", d.x + 8, d.y + 6, d.w - 16, d.h - 12)
    else lg.rectangle("fill", d.x + 6, d.y + 8, d.w - 12, d.h - 16) end
  end
end

-- Floor markings from the brief
local function drawFloorMarks(lg)
  -- airlock: caution stripes around both thresholds
  local od, ed = Map.outerDoor, Map.entranceDoor
  if od then hazardStripes(lg, od.x + od.w - 2, od.y - 16, 30, od.h + 32) end
  if ed then hazardStripes(lg, ed.x - 28, ed.y - 16, 30, ed.h + 32) end
  -- water: drain grates + moisture sensor strips near the tanks
  for _, g in ipairs({ { 1400, 470 }, { 1520, 470 }, { 1250, 600 } }) do
    Theme.set(C.ink); lg.rectangle("fill", g[1] - 2, g[2] - 2, 52, 26, 4, 4)
    Theme.set(Theme.hex("#4A5A80")); lg.rectangle("fill", g[1], g[2], 48, 22, 3, 3)
    Theme.set(C.ink); for k = 0, 4 do lg.rectangle("fill", g[1] + 5 + k * 9, g[2] + 4, 4, 14) end
  end
  Theme.set(C.water, 0.6); lg.rectangle("fill", 1380, 652 - 30, 220, 5)
  Theme.set(C.water, 0.35); lg.rectangle("fill", 1380, 652 - 22, 220, 3)
  -- waste: hazard border by the barrels
  hazardStripes(lg, 1016, 2366, 116, 8)
  -- radiation: trefoil on the floor
  local cx, cy = 2205, 1150
  Theme.set(C.caution, 0.18); lg.circle("fill", cx, cy, 44)
  Theme.set(C.ink, 0.35)
  for k = 0, 2 do
    local a = k * 2 * math.pi / 3 - math.pi / 2
    lg.arc("fill", cx, cy, 38, a - 0.5, a + 0.5)
  end
  Theme.set(C.caution, 0.18); lg.circle("fill", cx, cy, 12)
  -- water room: blue (clean) + grey (used water) pipes along the back wall
  for _, p in ipairs({ { 30, C.water }, { 46, C.metalShade } }) do
    Theme.set(C.ink); lg.rectangle("fill", 869, p[1] - 2, 470, 12, 5, 5)
    Theme.set(p[2]); lg.rectangle("fill", 869, p[1], 470, 8, 4, 4)
  end
end

function R:build()
  local lg = love.graphics
  local ok, canvas = pcall(lg.newCanvas, Map.WIDTH, Map.HEIGHT)
  if not ok then return end
  self.canvas = canvas
  lg.push("all")
  lg.setCanvas(canvas)
  lg.clear(0, 0, 0, 0)
  drawSuperstructure(lg)
  drawHull(lg)
  drawCorridors(lg)
  for _, r in ipairs(Map.rooms) do drawRoomFloor(lg, r) end
  drawDoorFloors(lg)
  for _, r in ipairs(Map.rooms) do drawBackWall(lg, r) end
  for _, d in ipairs(Map.doors) do
    if d.top then
      Theme.set(C.corridor); lg.rectangle("fill", d.x + 6, d.y, d.w - 12, d.h)
      Theme.set(C.caution, 0.8); lg.rectangle("fill", d.x + 6, d.y + d.h - 14, d.w - 12, 6)
    end
  end
  drawFloorMarks(lg)
  for _, r in ipairs(Map.rooms) do drawSign(lg, r) end
  lg.pop()
end

------------------------------------------------------------------------------
-- Live layer
------------------------------------------------------------------------------

-- locked(d) -> true when that door must stay shut
function R:update(dt, vulcan, locked)
  for i, d in ipairs(Map.doors) do
    local cx, cy = d.x + d.w / 2, d.y + d.h / 2
    local near = (vulcan.x - cx) ^ 2 + (vulcan.y - cy) ^ 2 < 150 * 150
    local target = (near and not (locked and locked(d))) and 1 or 0
    local o = self.doorOpen[i]
    self.doorOpen[i] = o + (target - o) * math.min(1, dt * 8)
  end
end

local function drawDoorPanels(lg, d, open, isLocked, t)
  local gap = (1 - open)
  local col = isLocked and Theme.hex("#8C93AC") or C.metal
  local light = isLocked and C.critical or C.good
  if d.vertical then
    local mx, half = d.x + d.w / 2, d.h / 2
    local len = half * gap
    Theme.box(mx - 7, d.y, 14, len, col, 3, 2)
    Theme.box(mx - 7, d.y + d.h - len, 14, len, col, 3, 2)
    Theme.box(mx - 11, d.y - 16, 22, 18, C.hullShade, 4, 2)
    Theme.box(mx - 11, d.y + d.h - 2, 22, 18, C.hullShade, 4, 2)
    Theme.circle(mx, d.y - 7, 4, light, 1)
  else
    local my, half = d.y + d.h / 2, d.w / 2
    local len = half * gap
    if d.top then my = d.y + d.h - 30 end
    Theme.box(d.x, my - 7, len, 14, col, 3, 2)
    Theme.box(d.x + d.w - len, my - 7, len, 14, col, 3, 2)
    Theme.box(d.x - 16, my - 11, 18, 22, C.hullShade, 4, 2)
    Theme.box(d.x + d.w - 2, my - 11, 18, 22, C.hullShade, 4, 2)
    Theme.circle(d.x - 7, my, 4, light, 1)
  end
  if isLocked and open < 0.05 then
    -- padlock on the closed door
    local cx, cy = d.x + d.w / 2, d.y + d.h / 2
    if d.top then cy = d.y + d.h - 30 end
    Theme.set(C.ink); lg.rectangle("fill", cx - 12, cy - 6, 24, 20, 4, 4)
    Theme.set(C.caution); lg.rectangle("fill", cx - 10, cy - 4, 20, 16, 3, 3)
    Theme.set(C.ink); lg.setLineWidth(4); lg.arc("line", "open", cx, cy - 6, 7, math.pi, 2 * math.pi); lg.setLineWidth(1)
    lg.circle("fill", cx, cy + 3, 3)
  end
end

-- Wall screens in the radiation command centre: Mission Control + storm radar
local function drawCommsScreens(lg, ls, t)
  local y, w, h = 800, 54, 50
  local x = 2262
  Theme.box(x - 4, y - 4, w + 8, h + 8, C.metalDark, 6)
  Theme.set(C.space); lg.rectangle("fill", x, y, w, h)
  local earth = Assets.image("assets/menu/menu_earth.png")
  if earth then
    lg.setColor(1, 1, 1)
    local s = 38 / earth:getWidth()
    lg.draw(earth, x + w / 2, y + h / 2, t * 0.05, s, s, earth:getWidth() / 2, earth:getHeight() / 2)
  end
  local phase = ls.radiation.phase
  local col = phase == "clear" and C.good or (phase == "warning" and C.caution or C.critical)
  x = 2324
  Theme.box(x - 4, y - 4, w + 8, h + 8, C.metalDark, 6)
  Theme.set(C.space); lg.rectangle("fill", x, y, w, h)
  local rx, ry = x + w / 2, y + h / 2
  Theme.set(col, 0.25); lg.circle("fill", rx, ry, 20)
  Theme.set(col); lg.circle("line", rx, ry, 20); lg.circle("line", rx, ry, 10)
  lg.setLineWidth(2); lg.line(rx, ry, rx + math.cos(t * 2) * 20, ry + math.sin(t * 2) * 20); lg.setLineWidth(1)
  lg.setFont(Theme.font(10)); Theme.set(col)
  lg.printf(phase == "clear" and "SPACE WEATHER: CALM" or (phase == "warning" and "STORM SOON!" or "SOLAR STORM!"), 2258, 856, 124, "center")
end

-- Atmospheric chart on the air room wall: live gas pie (N2 / O2 / CO2)
local function drawGasChart(lg, ls)
  local x, y, w, h = 1456, 1628, 100, 62
  Theme.box(x - 4, y - 4, w + 8, h + 8, C.metalDark, 6)
  Theme.set(Theme.hex("#0B1830")); lg.rectangle("fill", x, y, w, h)
  local cx, cy, r = x + 26, y + h / 2, 22
  local o2, co2 = ls.air.oxygenPercent / 100, ls.air.carbonDioxidePercent / 100
  local a0 = -math.pi / 2
  local function slice(frac, col)
    Theme.set(col); lg.arc("fill", cx, cy, r, a0, a0 + frac * 2 * math.pi); a0 = a0 + frac * 2 * math.pi
  end
  slice(1 - o2 - co2, Theme.hex("#7C86A8")); slice(o2, C.oxygen); slice(math.max(co2, 0.004), C.critical)
  Theme.set(C.ink); lg.circle("line", cx, cy, r)
  lg.setFont(Theme.font(10)); Theme.set(C.oxygen); lg.print(string.format("O2 %.1f", ls.air.oxygenPercent), x + 52, y + 9)
  Theme.set(C.critical); lg.print(string.format("CO2 %.2f", ls.air.carbonDioxidePercent), x + 52, y + 25)
  Theme.set(Theme.hex("#AEB6D2")); lg.print("N2 78", x + 52, y + 41)
end

-- Sealed waste storage gauge above the barrels
local function drawWasteGauge(lg, ls)
  local x, y = 1024, 2282
  Theme.set(C.ink); lg.rectangle("fill", x - 2, y - 2, 100, 20, 5, 5)
  Theme.set(C.screen); lg.rectangle("fill", x, y, 96, 16, 4, 4)
  local n = math.floor(ls.sealedWaste / 10 + 0.5)
  for i = 0, 9 do
    Theme.set(i < n and C.waste or C.metalDark); lg.rectangle("fill", x + 4 + i * 9, y + 4, 7, 8, 2, 2)
  end
end

-- Red alert sirens (radiation command centre corners) + emergency lights
local function drawSirens(lg, ls, t)
  local phase = ls.radiation.phase
  if phase == "clear" and not ls:isAnyCritical() then return end
  local col = phase == "warning" and C.caution or C.critical
  for _, p in ipairs({ { 1928, 820 }, { 2386, 820 } }) do
    local a = t * 5
    lg.setBlendMode("add")
    Theme.set(col, 0.35)
    lg.arc("fill", p[1], p[2], 130, a, a + 0.5); lg.arc("fill", p[1], p[2], 130, a + math.pi, a + math.pi + 0.5)
    lg.setBlendMode("alpha")
  end
end

local function drawAlarms(lg, t)
  for _, r in ipairs(Map.rooms) do
    for _, ax in ipairs({ r.x + 44, r.x + r.w - 44 }) do
      local ay = r.y + 30
      Theme.set(C.critical, 0.25 + 0.25 * math.abs(math.sin(t * 6))); lg.circle("fill", ax, ay, 26)
      Theme.circle(ax, ay, 9, C.critical, 2)
    end
  end
end

function R:drawStatic()
  if self.canvas then
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.canvas, 0, 0)
  end
end

-- isDoorLocked(d) -> bool (campaign progression)
function R:drawLive(ls, t, isDoorLocked)
  local lg = love.graphics
  drawCommsScreens(lg, ls, t)
  drawGasChart(lg, ls)
  drawWasteGauge(lg, ls)
  for i, d in ipairs(Map.doors) do drawDoorPanels(lg, d, self.doorOpen[i], isDoorLocked and isDoorLocked(d), t) end
  if ls:isAnyCritical() and not ls.missionFailed then drawAlarms(lg, t) end
end

function R:drawOverlays(ls, t)
  drawSirens(love.graphics, ls, t)
end

return R
