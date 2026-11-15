--[[
  Exterior renderer - the open lunar surface
  ==========================================
  Shown only while Vulcan is outside. Stark black space with stars, Earth and
  the Sun; cream lunar ground with craters; the habitat seen from outside
  (closed roof modules); and the exterior artifacts each level unlocks.
  Locked artifacts are drawn grey with a padlock sign.
]]
local Theme = require("src.ui.theme")
local Map = require("src.station_map")
local Assets = require("src.assets")
local Props = require("src.render.props")
local C = Theme.C

local X = {}

-- deterministic star field (screen space with slow parallax)
local STARS
local function stars()
  if STARS then return STARS end
  STARS = {}
  local seed = 12345
  local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
  for i = 1, 260 do STARS[i] = { rnd() * 2600, rnd() * 900, 0.6 + rnd() * 1.8, rnd() * 6.28 } end
  return STARS
end

function X.drawSky(camX, camY, t, ls, W, H)
  local lg = love.graphics
  lg.setColor(0.01, 0.01, 0.04); lg.rectangle("fill", 0, 0, W, H)
  local px, py = camX * 0.15, camY * 0.1
  for _, s in ipairs(stars()) do
    local x = (s[1] - px) % 2600 - 200
    local y = (s[2] - py) % 900
    local tw = 0.55 + 0.45 * math.sin(t * 1.7 + s[4])
    lg.setColor(1, 1, 1, tw); lg.circle("fill", x, y, s[3])
  end
  -- Earth hanging in the black sky
  local earth = Assets.image("assets/menu/menu_earth.png")
  local hy = Map.HORIZON_Y - camY
  if earth then
    local s = 96 / earth:getWidth()
    lg.setColor(1, 1, 1)
    lg.draw(earth, 960 - camX * 0.05, hy - 110, t * 0.02, s, s, earth:getWidth() / 2, earth:getHeight() / 2)
  end
  -- the Sun (only in the lunar day)
  if ls:isSunUp() then
    local sx, sy = 300 - camX * 0.05, hy - 120
    lg.setBlendMode("add")
    for k = 4, 1, -1 do lg.setColor(1, 0.95, 0.7, 0.07 * k); lg.circle("fill", sx, sy, 30 + (4 - k) * 18) end
    lg.setBlendMode("alpha")
    lg.setColor(1, 1, 0.92); lg.circle("fill", sx, sy, 30)
  end
end

------------------------------------------------------------------------------
-- Ground (world space)
------------------------------------------------------------------------------
local CRATERS = {
  { -620, 1190, 70 }, { -290, 1300, 46 }, { -170, 1560, 60 }, { -760, 1560, 40 }, { -1250, 1290, 36 },
  { -150, 880, 28 }, { -900, 1850, 110 }, { -330, 1880, 80 }, { -1200, 1960, 70 }, { 300, 1470, 60 },
  { 700, 2100, 90 }, { 1600, 2080, 60 },
}

local function crater(lg, x, y, r)
  Theme.set(C.craterShade); lg.ellipse("fill", x, y, r, r * 0.55)
  Theme.set(Theme.hex("#BFB386")); lg.ellipse("fill", x + r * 0.08, y + r * 0.06, r * 0.82, r * 0.42)
  Theme.set(C.crater); lg.ellipse("fill", x + r * 0.16, y + r * 0.1, r * 0.66, r * 0.32)
  Theme.set(C.ink); lg.setLineWidth(3); lg.ellipse("line", x, y, r, r * 0.55); lg.setLineWidth(1)
end

function X.drawGround(t)
  local lg = love.graphics
  local E = Map.EXTERIOR
  local top = Map.HORIZON_Y
  -- distant mountains on the horizon
  Theme.set(Theme.hex("#8E8A9E"))
  local pts = { E.x - 200, top + 10 }
  for x = E.x - 200, E.x + E.w + 200, 120 do
    pts[#pts + 1] = x; pts[#pts + 1] = top - 30 - 40 * math.abs(math.sin(x * 0.0031)) - 22 * math.abs(math.sin(x * 0.011))
  end
  pts[#pts + 1] = E.x + E.w + 200; pts[#pts + 1] = top + 10
  lg.polygon("fill", pts)
  Theme.set(C.ink); lg.setLineWidth(3); lg.line(pts); lg.setLineWidth(1)
  -- ground
  Theme.set(C.cream); lg.rectangle("fill", E.x - 200, top, E.w + 400, E.y + E.h - top + 200)
  local tile = Assets.image("assets/moon_tile.png")
  if tile then
    tile:setWrap("repeat", "repeat")
    local quad = lg.newQuad(0, 0, E.w + 400, E.y + E.h - top + 200, tile:getWidth(), tile:getHeight())
    lg.setColor(1, 0.98, 0.9, 0.5)
    lg.draw(tile, quad, E.x - 200, top)
  end
  Theme.set(C.ink); lg.setLineWidth(4); lg.line(E.x - 200, top, E.x + E.w + 200, top); lg.setLineWidth(1)
  for _, c in ipairs(CRATERS) do crater(lg, c[1], c[2], c[3]) end
end

------------------------------------------------------------------------------
-- The habitat seen from outside (closed roof modules)
------------------------------------------------------------------------------
local function roof(lg, r, col, locked)
  local x, y, w, h = r.x - 16, r.y - 16, r.w + 32, r.h + 32
  Theme.set(C.ink, 0.35); lg.rectangle("fill", x + 12, y + 18, w, h, 16, 16)
  Theme.set(C.ink); lg.rectangle("fill", x - 4, y - 4, w + 8, h + 8, 18, 18)
  Theme.set(locked and Theme.hex("#7D8195") or C.hullShade); lg.rectangle("fill", x, y, w, h, 14, 14)
  Theme.set(locked and Theme.hex("#9A9EB0") or C.hull); lg.rectangle("fill", x + 10, y + 8, w - 20, h - 22, 10, 10)
  -- panel seams
  Theme.set(locked and Theme.hex("#868A9C") or C.hullShade)
  for px = x + 80, x + w - 40, 90 do lg.rectangle("fill", px, y + 10, 3, h - 26) end
  -- accent stripe
  Theme.set(locked and Theme.hex("#666A7C") or col); lg.rectangle("fill", x + 10, y + h - 26, w - 20, 8)
end

-- Modules beyond the horizon line are hidden (clipped at the horizon).
-- Shielded sections get regolith berm bags along their roof edges.
function X.drawHabitat(ls, t, isRoomLocked, camY)
  local lg = love.graphics
  lg.setScissor(0, math.max(0, Map.HORIZON_Y - (camY or 0)), 4000, 4000)
  local rad = ls.radiation
  local shielded = {}
  for _, id in ipairs(rad.order) do
    if rad.sections[id].shielded then
      for _, roomId in ipairs(Map.SECTION_ROOMS[id] or {}) do shielded[roomId] = true end
    end
  end
  -- corridors as tubes
  for _, c in ipairs(Map.corridors) do
    Theme.set(C.ink); lg.rectangle("fill", c.x - 4, c.y - 4, c.w + 8, c.h + 8, 12, 12)
    Theme.set(C.hullDark); lg.rectangle("fill", c.x, c.y, c.w, c.h, 10, 10)
    Theme.set(C.hullShade)
    if c.w >= c.h then for x = c.x + 20, c.x + c.w - 10, 40 do lg.rectangle("fill", x, c.y + 6, 6, c.h - 12) end
    else for y = c.y + 20, c.y + c.h - 10, 40 do lg.rectangle("fill", c.x + 6, y, c.w - 12, 6) end end
  end
  for _, r in ipairs(Map.rooms) do
    local locked = isRoomLocked and isRoomLocked(r.id)
    local col = Theme.ROOM[r.id] or C.cyan
    if r.extra then for _, e in ipairs(r.extra) do roof(lg, e, col, locked) end end
    roof(lg, r, col, locked)
    -- name stencil
    lg.setFont(Theme.font(22))
    Theme.set(C.ink, 0.55); lg.printf(r.name, r.x, r.y + r.h / 2 - 14, r.w, "center")
    -- blinking roof light
    Theme.circle(r.x + 26, r.y + 18, 6, (math.sin(t * 3 + r.x) > 0) and (locked and C.critical or C.good) or C.metalDark, 2)
    if shielded[r.id] then
      for x = r.x - 10, r.x + r.w + 10, 36 do
        for _, y in ipairs({ r.y - 22, r.y + r.h + 10 }) do
          Theme.set(C.ink); lg.ellipse("fill", x, y, 20, 12)
          Theme.set(Theme.hex("#CDBE8E")); lg.ellipse("fill", x, y - 2, 17, 9)
        end
      end
    end
  end
  lg.setScissor()
  -- the outer airlock door
  local d = Map.outerDoor
  if d then
    Theme.set(C.ink); lg.rectangle("fill", d.x - 10, d.y - 8, 34, d.h + 16, 6, 6)
    Theme.set(C.corridor); lg.rectangle("fill", d.x - 6, d.y - 4, 26, d.h + 8, 4, 4)
    for i = 0, 6 do
      Theme.set(i % 2 == 0 and C.caution or C.ink); lg.rectangle("fill", d.x - 6, d.y - 4 + i * (d.h + 8) / 7, 6, (d.h + 8) / 7)
    end
  end
end

------------------------------------------------------------------------------
-- Exterior artifacts (one per level; grey + padlock while locked)
------------------------------------------------------------------------------
local function tag(lg, text, x, y, locked, level)
  local f = Theme.font(13); lg.setFont(f)
  local s = locked and ("LEVEL " .. level .. " - LOCKED") or text
  local w = f:getWidth(s) + 20
  local pts = Theme.cutPoints(x - w / 2, y, w, 22, 6)
  Theme.set(C.space, 0.9); lg.polygon("fill", pts)
  Theme.set(locked and C.metalShade or C.cyan); lg.setLineWidth(2); lg.polygon("line", pts); lg.setLineWidth(1)
  lg.printf(s, x - w / 2, y + 4, w, "center")
end

local function panelArray(lg, ls, t)
  local aim = ls.solarAim / 100
  local sun = ls:isSunUp()
  for row = 0, 1 do
    for i = 0, 1 do
      local cx, cy = -1180 + i * 170, 900 + row * 160
      Theme.set(C.ink); lg.rectangle("fill", cx - 6, cy - 4, 12, 76)
      Theme.set(C.metalDark); lg.rectangle("fill", cx - 3, cy - 2, 6, 72)
      local tilt = (1 - aim) * 0.9
      local w, h = 140 * math.cos(tilt), 70
      local p = { cx - w / 2, cy - h / 2 + tilt * 20, cx + w / 2, cy - h / 2 - tilt * 20,
        cx + w / 2, cy + h / 2 - tilt * 20, cx - w / 2, cy + h / 2 + tilt * 20 }
      Theme.set(sun and Theme.hex("#2D5BD8") or Theme.hex("#1C2C66")); lg.polygon("fill", p)
      Theme.set(Theme.hex("#7FB0FF"), sun and 0.6 or 0.2)
      for k = 1, 3 do
        local f = k / 4
        lg.line(p[1] + (p[3] - p[1]) * f, p[2] + (p[4] - p[2]) * f, p[7] + (p[5] - p[7]) * f, p[8] + (p[6] - p[8]) * f)
      end
      if sun then
        Theme.set(C.white, 0.3 + 0.2 * math.sin(t * 2 + i))
        lg.polygon("fill", p[1], p[2], p[1] + (p[3] - p[1]) * 0.25, p[2] + (p[4] - p[2]) * 0.25,
          p[7] + (p[5] - p[7]) * 0.15, p[8] + (p[6] - p[8]) * 0.15, p[7], p[8])
      end
      Theme.set(C.ink); lg.setLineWidth(3); lg.polygon("line", p); lg.setLineWidth(1)
    end
  end
  -- power cable to the habitat
  local cable = { -940, 1100, -700, 1200, -60, 1200, -30, 1560 }
  Theme.set(C.ink); lg.setLineWidth(8); lg.line(cable)
  Theme.set(Theme.hex("#E0A030")); lg.setLineWidth(4); lg.line(cable); lg.setLineWidth(1)
end

local function condensers(lg, t)
  for i, p in ipairs({ { -830, 930 }, { -720, 955 } }) do
    local x, y = p[1], p[2]
    Theme.box(x - 22, y - 150, 44, 150, C.metal, 8)
    for k = 0, 4 do Theme.box(x - 38, y - 140 + k * 26, 76, 10, C.metalShade, 4, 2) end
    Theme.set(C.water, 0.5 + 0.3 * math.sin(t * 2 + i)); lg.circle("fill", x, y - 20, 8)
  end
end

local function dome(lg, t)
  local x, y, r = -900, 1400, 170
  Theme.set(C.ink, 0.3); lg.ellipse("fill", x + 12, y + 10, r + 10, 40)
  Theme.set(Theme.hex("#5A4A3A")); lg.ellipse("fill", x, y, r, 38)
  for i = 0, 6 do
    local px = x - r * 0.7 + i * r * 0.23
    Theme.set(C.plant); lg.circle("fill", px, y - 26 - (i % 2) * 14, 18)
  end
  Theme.set(C.cyanLight, 0.25); lg.arc("fill", x, y, r, math.pi, 2 * math.pi)
  Theme.set(C.ink); lg.setLineWidth(4); lg.arc("line", "open", x, y, r, math.pi, 2 * math.pi)
  lg.setLineWidth(2)
  for k = 1, 3 do lg.arc("line", "open", x, y, r * k / 4, math.pi, 2 * math.pi) end
  lg.line(x, y - r, x, y)
  lg.setLineWidth(4); lg.line(x - r, y, x + r, y); lg.setLineWidth(1)
end

local function intakeVents(lg, t)
  for i, p in ipairs({ { -470, 1380 }, { -360, 1420 }, { -560, 1440 } }) do
    local x, y = p[1], p[2]
    Theme.box(x - 26, y - 70, 52, 70, C.metal, 8)
    Theme.box(x - 34, y - 86, 68, 20, C.metalShade, 6)
    for k = 0, 3 do Theme.set(C.ink); lg.rectangle("fill", x - 18, y - 60 + k * 14, 36, 5) end
    Theme.set(C.oxygen, 0.4 + 0.3 * math.sin(t * 3 + i)); lg.circle("fill", x, y - 96 - (t * 30 + i * 9) % 30, 5)
  end
end

local function debris(lg, t)
  local x, y = -560, 1630
  for i, p in ipairs({ { 0, 0, 40 }, { 70, 30, 30 }, { -60, 40, 26 }, { 30, 70, 22 } }) do
    Theme.box(x + p[1] - p[3] / 2, y + p[2] - p[3] / 2, p[3], p[3] * 0.7, i % 2 == 0 and C.metalShade or C.metalDark, 4)
  end
  -- scrap drone
  local dx, dy = x + 40 + math.sin(t) * 60, y - 120 + math.sin(t * 2) * 10
  Theme.set(C.ink, 0.25); lg.ellipse("fill", dx, y + 60, 30, 8)
  Theme.box(dx - 26, dy - 12, 52, 24, C.metal, 10)
  Theme.set(C.cyan); lg.circle("fill", dx, dy, 6)
  Theme.set(C.ink); lg.setLineWidth(3); lg.line(dx - 40, dy - 16, dx + 40, dy - 16); lg.setLineWidth(1)
  for _, sx in ipairs({ -40, 40 }) do
    Theme.set(C.metalShade, 0.7); lg.ellipse("fill", dx + sx, dy - 16, 18 * math.abs(math.sin(t * 20)), 4)
  end
end

local function miningField(lg, t, ls)
  local x, y = -1050, 1640
  Theme.set(Theme.hex("#BFB386")); lg.ellipse("fill", x, y, 210, 90)
  Theme.set(C.ink); lg.setLineWidth(3); lg.ellipse("line", x, y, 210, 90); lg.setLineWidth(1)
  for i = 0, 7 do
    local a = i * math.pi / 4
    local px, py = x + math.cos(a) * 210, y + math.sin(a) * 90
    Theme.set(C.ink); lg.rectangle("fill", px - 4, py - 40, 8, 40)
    Theme.set(i % 2 == 0 and C.caution or C.critical); lg.rectangle("fill", px - 3, py - 39, 6, 14)
  end
  for i = 1, 5 do Theme.box(x - 120 + i * 40, y - 20 + (i % 2) * 18, 30, 20, Theme.hex("#CDBE8E"), 6, 2) end
  -- radiation map overlay ring
  local phase = ls.radiation.phase
  if phase ~= "clear" then
    Theme.set(phase == "storm" and C.critical or C.caution, 0.25 + 0.15 * math.sin(t * 5))
    lg.setLineWidth(6); lg.ellipse("line", x, y, 250 + 10 * math.sin(t * 3), 110); lg.setLineWidth(1)
  end
end

local function flag(lg, t)
  local x, y = -330, 940
  Theme.set(C.ink); lg.rectangle("fill", x - 3, y - 130, 6, 130)
  local wave = math.sin(t * 2) * 4
  local p = { x + 3, y - 128, x + 90, y - 120 + wave, x + 90, y - 72 + wave, x + 3, y - 80 }
  Theme.set(C.cyan); lg.polygon("fill", p)
  Theme.set(C.ink); lg.setLineWidth(3); lg.polygon("line", p); lg.setLineWidth(1)
  lg.setFont(Theme.font(12)); Theme.set(C.ink); lg.printf("JUNIOR\nASTRONAUT", x + 4, y - 118 + wave * 0.5, 86, "center")
  -- personal log beacon
  Theme.box(x + 30, y - 40, 40, 40, C.metal, 8)
  Theme.set(C.good, 0.5 + 0.5 * math.sin(t * 4)); lg.circle("fill", x + 50, y - 26, 6)
end

local function airlockPath(lg, t)
  local d = Map.outerDoor
  local y = d and (d.y + d.h / 2) or 1047
  for i = 0, 7 do
    local x = -60 - i * 90
    Theme.set(C.ink); lg.circle("fill", x, y - 70, 7); lg.circle("fill", x, y + 70, 7)
    local on = (math.floor(t * 4) % 8) == (7 - i)
    Theme.set(on and C.caution or Theme.hex("#B88A20")); lg.circle("fill", x, y - 70, 5); lg.circle("fill", x, y + 70, 5)
  end
end

X.ARTIFACTS = {
  { level = 1, name = "Crew Flag + Logs", x = -270, y = 946, draw = function(lg, t) flag(lg, t) end },
  { level = 2, name = "Airlock Path", x = -420, y = 1136, draw = function(lg, t) airlockPath(lg, t) end },
  { level = 3, name = "Water Condensers", x = -775, y = 972, draw = function(lg, t) condensers(lg, t) end },
  { level = 4, name = "Greenhouse Dome", x = -900, y = 1450, draw = function(lg, t) dome(lg, t) end },
  { level = 5, name = "Scrap Drones", x = -540, y = 1712, draw = function(lg, t) debris(lg, t) end },
  { level = 6, name = "Oxygen Intake Vents", x = -470, y = 1462, draw = function(lg, t) intakeVents(lg, t) end },
  { level = 7, name = "Solar Arrays", x = -1095, y = 1142, draw = function(lg, t, ls) panelArray(lg, ls, t) end },
  { level = 8, name = "Regolith Mining Field", x = -1050, y = 1738, draw = function(lg, t, ls) miningField(lg, t, ls) end },
}

-- isLevelOpen(level) -> bool
function X.drawArtifacts(ls, t, isLevelOpen)
  local lg = love.graphics
  for _, a in ipairs(X.ARTIFACTS) do
    local open = (not isLevelOpen) or isLevelOpen(a.level)
    lg.push("all")
    if not open then Props.gray(true) end
    a.draw(lg, open and t or 0, ls)
    lg.pop()
    tag(lg, a.name, a.x, a.y, not open, a.level)
  end
end

return X
