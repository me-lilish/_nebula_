--[[
  Machine art: every station is a cel-shaded prop sprite (assets/props) with
  live overlays drawn on top, so a child can SEE each machine's state:
  bubbling tubes, tank levels, glowing reactor, shield map, battery cells...
  `act` (0..1) is a glow that fades after the station is used.

  Machines.draw(m, ls, t, act)   m = station rect + id + sprite
  Overlay positions are fractions of the sprite rect (see rel()).
]]
local Theme = require("src.ui.theme")
local Props = require("src.render.props")
local C = Theme.C

local M = {}
local D = {}

local function rel(m, fx, fy, fw, fh)
  return m.x + m.w * fx, m.y + m.h * fy, m.w * (fw or 0), m.h * (fh or 0)
end

local function sprite(m, name)
  Props.draw(name or m.sprite, m.x, m.y, m.w, m.h)
end

local function bubbles(x, y, w, h, t, n, color, speed)
  local g = love.graphics
  for i = 1, n do
    local phase = (t * (speed or 0.6) + i * 0.37) % 1
    local bx = x + ((i * 37) % 100) / 100 * w
    local by = y + h - phase * h
    Theme.set(color or C.white, 0.9 * (1 - phase))
    g.circle("fill", bx + math.sin(t * 4 + i) * 2, by, 1.5 + (i % 3))
  end
end

local function glow(cx, cy, r, color, a)
  local g = love.graphics
  g.setBlendMode("add")
  for k = 3, 1, -1 do
    Theme.set(color, a * 0.22 * k); g.circle("fill", cx, cy, r * (1 + (3 - k) * 0.45))
  end
  g.setBlendMode("alpha")
end

-- little ink-outlined screen with text (live numbers on a machine)
local function screen(x, y, w, h, lines, color)
  local g = love.graphics
  Theme.set(C.ink); g.rectangle("fill", x - 2, y - 2, w + 4, h + 4, 5, 5)
  Theme.set(Theme.hex("#0B1830")); g.rectangle("fill", x, y, w, h, 4, 4)
  Theme.set(color or C.cyan)
  local f = Theme.font(math.max(9, math.min(14, math.floor(h / #lines) - 2)))
  g.setFont(f)
  local lh = h / #lines
  for i, s in ipairs(lines) do g.printf(s, x, y + (i - 1) * lh + (lh - f:getHeight()) / 2, w, "center") end
end

local function meter(x, y, w, frac, color)
  Theme.meter(x, y, w, 7, math.max(0, math.min(1, frac)), color)
end

local function puffs(x, y, t, a, color, n)
  local g = love.graphics
  for k = 0, (n or 3) - 1 do
    local p = (t * 0.8 + k / (n or 3)) % 1
    Theme.set(color or C.white, a * (1 - p))
    g.circle("fill", x + math.sin(t * 3 + k) * 6 + p * 10, y - p * 40, 5 + p * 8)
  end
end

------------------------------------------------------------------------------
-- 1 Crew quarters
------------------------------------------------------------------------------
D.sleep = function(m, ls, t, act)
  sprite(m)
  if act > 0 then
    local g = love.graphics
    g.setFont(Theme.font(22)); Theme.set(C.white, act)
    g.print("z", m.x + m.w * 0.7, m.y + 10 - (t * 12 % 14)); g.print("Z", m.x + m.w * 0.8, m.y - 8 - (t * 12 % 14))
  end
end

D.foodstation = function(m, ls, t, act)
  sprite(m)
  local x, y, w, h = rel(m, 0.27, 0.66, 0.46, 0.16)
  if act > 0 then
    Theme.set(Theme.hex("#FFB84D"), act); love.graphics.rectangle("fill", x + w * 0.2, y + h * 0.3, w * 0.6, h * 0.5, 4, 4)
    puffs(x + w / 2, y, t, 0.6 * act, C.white)
  end
end

D.toilet = function(m, ls, t, act)
  sprite(m)
  local cap = ls.config.TOILET_CAPACITY_USES
  local x, y = rel(m, 0.66, 0.9)
  for i = 1, cap do
    Theme.led(x + (i - 1) * 13, y, i <= ls.toiletUses, ls:toiletNeedsSealing() and C.critical or C.caution)
  end
  if act > 0 then bubbles(m.x + m.w * 0.3, m.y + m.h * 0.4, m.w * 0.2, m.h * 0.4, t, 6, C.water, 1.4) end
end

------------------------------------------------------------------------------
-- 2 Airlock
------------------------------------------------------------------------------
D.dustoff = function(m, ls, t, act)
  sprite(m)
  local g = love.graphics
  local suit = ls.dust.suitDust
  -- dust left on the static mat
  if suit > 0 then
    Theme.set(C.dust, 0.25 + 0.5 * suit / 100)
    for i = 1, math.floor(suit / 6) do
      g.circle("fill", m.x + m.w * (0.12 + (i * 0.137 % 0.76)), m.y + m.h * (0.7 + (i * 0.071 % 0.22)), 3 + i % 3)
    end
  end
  if act > 0 then
    local x = m.x + m.w * (0.3 + 0.2 * math.sin(t * 18))
    Theme.set(C.dust, act); for k = 0, 5 do g.circle("fill", x + k * 6, m.y + m.h * 0.55 - (t * 60 + k * 9) % 30, 2.5) end
  end
  meter(m.x + m.w * 0.15, m.y + m.h + 4, m.w * 0.7, suit / 100, suit > 0 and C.dust or C.good)
end

D.trace = function(m, ls, t, act)
  sprite(m)
  local x, y, w, h = rel(m, 0.2, 0.25, 0.5, 0.4)
  local dirt = ls.dust.cabinDust / 100
  if dirt > 0 then Theme.set(C.dust, 0.75 * dirt); love.graphics.rectangle("fill", x, y, w, h, 4, 4) end
  local uses, max = ls.dust.filterUses, ls.dust.config.FILTER_USES
  local lx, ly = rel(m, 0.74, 0.62)
  for i = 1, max do Theme.led(lx + (i - 1) * 9, ly, i <= uses, uses <= 1 and C.critical or C.good) end
  if act > 0 then glow(x + w / 2, y + h / 2, w * 0.4, C.cyanLight, act) end
end

------------------------------------------------------------------------------
-- 3 Water: three purifiers in a row = the 3 recovery steps
------------------------------------------------------------------------------
D.water = function(m, ls, t, act)
  local g = love.graphics
  local unitW = m.h / 1.354
  local gap = (m.w - unitW * 3) / 2
  local stages = {
    { ls.urine / 100, C.urine, "1 COLLECT" },
    { ls.brine / 100, C.brine, "2 SEPARATE" },
    { ls.potableWater / 100, C.water, "3 CLEAN" },
  }
  -- pipes between the units (flow dashes)
  local py = m.y + m.h * 0.78
  for i = 1, 2 do
    local x0 = m.x + i * unitW + (i - 1) * gap - 8
    local x1 = x0 + gap + 16
    Theme.set(C.ink); g.setLineWidth(10); g.line(x0, py, x1, py)
    Theme.set(C.metal); g.setLineWidth(6); g.line(x0, py, x1, py); g.setLineWidth(1)
    Theme.set(stages[i + 1][2])
    local off = (t * (20 + 60 * act)) % 12
    for x = x0 + off, x1 - 4, 12 do g.rectangle("fill", x, py - 2, 5, 4) end
  end
  for i, s in ipairs(stages) do
    local ux = m.x + (i - 1) * (unitW + gap)
    local u = { x = ux, y = m.y, w = unitW, h = m.h }
    Props.draw("purifier", u.x, u.y, u.w, u.h)
    -- tinted liquid level in the glass column
    local tx, ty, tw, th = rel(u, 0.11, 0.29, 0.1, 0.42)
    Theme.set(C.screen); g.rectangle("fill", tx, ty, tw, th, 3, 3)
    local lh = th * math.max(0, math.min(1, s[1]))
    Theme.set(s[2]); g.rectangle("fill", tx, ty + th - lh, tw, lh, 3, 3)
    if act > 0 or i == 3 then bubbles(tx, ty + th - lh, tw, lh, t, 3, C.white, 0.8 + act) end
    -- step tag
    local f = Theme.font(11); g.setFont(f)
    local lw = f:getWidth(s[3]) + 10
    local lx, ly = ux + unitW / 2 - lw / 2, m.y - 18
    Theme.set(C.ink); g.rectangle("fill", lx - 2, ly - 2, lw + 4, 18, 5, 5)
    Theme.set(s[2]); g.rectangle("fill", lx, ly, lw, 14, 4, 4)
    Theme.set(C.ink); g.printf(s[3], lx, ly + 1, lw, "center")
  end
end

------------------------------------------------------------------------------
-- 4 Food
------------------------------------------------------------------------------
D.greenhouse = function(m, ls, t, act)
  sprite(m)
  local g = love.graphics
  local grow = math.max(0, math.min(1, ls.growth / 100))
  -- unripe plants: rows look small / pale
  if grow < 1 then
    for _, r in ipairs({ 0.15, 0.4, 0.63 }) do
      local x, y, w, h = rel(m, 0.1, r, 0.55, 0.15 * (1 - grow))
      Theme.set(Theme.hex("#3B2A4A"), 0.8); g.rectangle("fill", x, y, w, h)
    end
  end
  -- grow lights
  local lit = not ls.greenhouseMissing and grow < 1
  if lit then
    g.setBlendMode("add"); Theme.set(Theme.hex("#FF5FD2"), 0.12 + 0.05 * math.sin(t * 2))
    g.rectangle("fill", rel(m, 0.08, 0.12, 0.6, 0.72)); g.setBlendMode("alpha")
  end
  if grow >= 1 then
    local x, y = rel(m, 0.38, -0.02)
    Theme.set(C.ink); g.rectangle("fill", x - 34, y - 14, 72, 24, 8, 8)
    Theme.set(C.good); g.rectangle("fill", x - 32, y - 12, 68, 20, 7, 7)
    g.setFont(Theme.font(13)); Theme.set(C.ink); g.printf("RIPE!", x - 32, y - 10, 68, "center")
  end
  meter(m.x + m.w * 0.1, m.y + m.h + 4, m.w * 0.55, grow, C.plant)
end

D.foodstorage = function(m, ls, t, act)
  sprite(m)
  local x, y, w, h = rel(m, 0.6, 0.15, 0.27, 0.17)
  screen(x, y, w, h, { string.format("%d%%", math.floor(ls.food + 0.5)) }, C.food)
  if ls.crops > 0 then
    Theme.box(m.x + m.w * 0.1, m.y - 14, 30, 20, C.plant, 5, 2)
  end
end

------------------------------------------------------------------------------
-- 5 Waste
------------------------------------------------------------------------------
D.compost = function(m, ls, t, act)
  sprite(m)
  local g = love.graphics
  local x, y, w, h = rel(m, 0.31, 0.35, 0.34, 0.26)
  local churn = t * (1 + 5 * act)
  Theme.set(Theme.hex("#2E5E1E"), 0.55)
  for k = 0, 2 do
    local a = churn + k * 2.1
    g.ellipse("fill", x + w / 2 + math.cos(a) * w * 0.3, y + h / 2 + math.sin(a) * h * 0.25, 7, 4)
  end
  meter(m.x + m.w * 0.15, m.y + m.h + 4, m.w * 0.7, ls.fertilizer / 100, Theme.hex("#B5824B"))
end

D.recycle = function(m, ls, t, act)
  sprite(m)
  local g = love.graphics
  local x, y, w, h = rel(m, 0.44, 0.63, 0.25, 0.16)
  g.setBlendMode("add")
  Theme.set(Theme.hex("#FF7A1A"), 0.25 + 0.15 * math.sin(t * 13) + 0.4 * act)
  g.rectangle("fill", x, y, w, h, 4, 4)
  g.setBlendMode("alpha")
  if act > 0 then puffs(m.x + m.w * 0.66, m.y + m.h * 0.22, t, 0.8 * act, C.metalShade, 4) end
  if (ls.salvageParts or 0) > 0 then
    local bx, by = m.x + m.w * 0.02, m.y + m.h - 22
    for i = 1, math.min(5, math.floor(ls.salvageParts)) do
      Theme.circle(bx + i * 13, by - (i % 2) * 6, 7, C.metalShade, 2)
      Theme.circle(bx + i * 13, by - (i % 2) * 6, 2.5, C.ink, 1)
    end
  end
end

------------------------------------------------------------------------------
-- 6 Air
------------------------------------------------------------------------------
D.oxygen = function(m, ls, t, act)
  sprite(m)
  local n, sp = act > 0 and 9 or 3, act > 0 and 1.8 or 0.5
  bubbles(m.x + m.w * 0.1, m.y + m.h * 0.22, m.w * 0.14, m.h * 0.5, t, n, C.white, sp)
  bubbles(m.x + m.w * 0.31, m.y + m.h * 0.22, m.w * 0.14, m.h * 0.5, t + 0.5, n, C.hydrogen, sp)
  local x, y, w, h = rel(m, 0.63, 0.27, 0.24, 0.2)
  screen(x, y, w, h, { "O2", string.format("%.1f%%", ls.air.oxygenPercent) }, C.oxygen)
end

D.co2 = function(m, ls, t, act)
  sprite(m)
  local g = love.graphics
  -- the bead canisters fill up with captured CO2
  local frac = ls.capturedCO2 / ls.config.CAPTURED_CO2_MAX
  for _, fx in ipairs({ 0.36, 0.56 }) do
    local x, y, w, h = rel(m, fx, 0.33, 0.16, 0.38)
    Theme.set(C.ink, 0.55); g.rectangle("fill", x, y, w, h * (1 - frac))
  end
  if ls.co2CleanerCooldown > 0 then
    local x, y = rel(m, 0.18, 0.08)
    g.setFont(Theme.font(12)); Theme.set(C.caution); g.print(string.format("%ds", math.ceil(ls.co2CleanerCooldown)), x, y)
  end
  if act > 0 then glow(m.x + m.w * 0.54, m.y + m.h * 0.5, m.w * 0.22, C.cyanLight, act) end
end

D.recycler = function(m, ls, t, act)
  sprite(m)
  local cx, cy = rel(m, 0.5, 0.53)
  local ready = ls.capturedCO2 > 0 and ls.hydrogen > 0
  glow(cx, cy, m.w * 0.16, C.caution, (ready and 0.35 or 0.12) + 0.6 * act + 0.08 * math.sin(t * 5))
  if act > 0 then puffs(m.x + m.w * 0.72, m.y + m.h * 0.05, t, 0.6 * act, C.white) end
  meter(m.x + 6, m.y + m.h + 4, m.w / 2 - 9, ls.capturedCO2 / ls.config.CAPTURED_CO2_MAX, C.co2)
  meter(m.x + m.w / 2 + 3, m.y + m.h + 4, m.w / 2 - 9, ls.hydrogen / ls.config.HYDROGEN_MAX, C.hydrogen)
end

------------------------------------------------------------------------------
-- 7 Power
------------------------------------------------------------------------------
D.solar = function(m, ls, t, act)
  sprite(m)
  local g = love.graphics
  local x, y, w, h = rel(m, 0.28, 0.11, 0.44, 0.26)
  Theme.set(Theme.hex("#0B1830")); g.rectangle("fill", x, y, w, h, 4, 4)
  local sun = ls:isSunUp()
  Theme.set(sun and C.power or C.metalDark); g.circle("fill", x + 14, y + h / 2, 8)
  local tilt = (1 - ls.solarAim / 100) * 0.9
  g.push(); g.translate(x + w * 0.5, y + h * 0.55); g.rotate(-tilt)
  Theme.set(Theme.hex("#2D5BD8")); g.rectangle("fill", -14, -3, 28, 6)
  g.pop()
  g.setFont(Theme.font(11)); Theme.set(C.cyan)
  g.printf(string.format("%d%%", math.floor(ls.solarAim + 0.5)), x + w * 0.6, y + h / 2 - 7, w * 0.4, "center")
end

D.battery = function(m, ls, t, act)
  local g = love.graphics
  local n = 3
  local uw = m.w / n
  local lit = math.floor(ls.battery / 100 * n * 6 + 0.5)
  local col = ls.battery < 50 and C.danger or (ls.battery < 70 and C.caution or C.good)
  for i = 0, n - 1 do
    local u = { x = m.x + i * uw + 2, y = m.y, w = uw - 4, h = m.h }
    Props.draw("battery_rack", u.x, u.y, u.w, u.h)
    for c = 0, 5 do
      local idx = i * 6 + c + 1
      local cx = u.x + u.w * (0.1 + (c % 3) * 0.235)
      local cy = u.y + u.h * (c < 3 and 0.36 or 0.76)
      Theme.set(C.ink); g.rectangle("fill", cx - 1, cy - 1, u.w * 0.16 + 2, 6)
      Theme.set(idx <= lit and col or C.metalDark); g.rectangle("fill", cx, cy, u.w * 0.16, 4)
    end
  end
  if ls.powerSaver then
    g.setFont(Theme.font(12)); Theme.set(C.ink); g.rectangle("fill", m.x + m.w / 2 - 42, m.y - 20, 84, 18, 6, 6)
    Theme.set(C.good); g.printf("SAVER ON", m.x + m.w / 2 - 42, m.y - 18, 84, "center")
  end
end

------------------------------------------------------------------------------
-- 8 Radiation
------------------------------------------------------------------------------
D.shield = function(m, ls, t, act)
  sprite(m)
  local g = love.graphics
  local r = ls.radiation
  local x, y, w, h = rel(m, 0.22, 0.1, 0.56, 0.36)
  local cw, ch = w / 3, h / 3
  for i, id in ipairs(r.order) do
    local s = r.sections[id]
    local col = s.shielded and C.good or ((r.phase == "storm") and C.critical or Theme.hex("#7FD6FF"))
    if r.phase == "warning" and not s.shielded and math.sin(t * 8) > 0 then col = C.caution end
    local bx = x + ((i - 1) % 3) * cw
    local by = y + math.floor((i - 1) / 3) * ch
    Theme.set(col, s.shielded and 0.85 or 0.45); g.rectangle("fill", bx + 2, by + 2, cw - 4, ch - 4, 3, 3)
  end
end

D.regolith = function(m, ls, t, act)
  sprite(m)
  local g = love.graphics
  local loaded = ls.radiation.loadedUnits
  for i = 1, math.min(loaded, 9) do
    local bx = m.x + m.w + 4 + ((i - 1) % 3) * 17
    local by = m.y + m.h - 14 - math.floor((i - 1) / 3) * 12
    Theme.box(bx, by, 16, 12, Theme.hex("#CDBE8E"), 4, 2)
  end
  if act > 0 then
    Theme.set(C.dust, act)
    for k = 0, 6 do g.circle("fill", m.x + m.w * (0.15 + k * 0.03), m.y + m.h * 0.1 + (t * 80 + k * 7) % 40, 3) end
  end
end

function M.draw(m, ls, t, act)
  local fn = D[m.id]
  love.graphics.push("all")
  if fn then fn(m, ls, t, act or 0) elseif m.sprite then sprite(m) end
  love.graphics.pop()
end

return M
