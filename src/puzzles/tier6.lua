--[[
  Tier 6 - AIR SYSTEM mini-games
    chemmix : "Chemical Absorbent Mix"  (CO2 Scrubber)     load canisters in order
    gasmix  : "21% O2 Sweet Spot"       (Oxygen Generator) balance O2 and N2 valves
]]
local Base = require("src.puzzles.base")
local P = {}

local CANISTERS = {
  B = { label = "O2-B", color = { 0.25, 0.55, 1, 1 } },
  Y = { label = "CO2-A", color = { 1, 0.82, 0.25, 1 } },
  G = { label = "N2-C", color = { 0.35, 0.85, 0.4, 1 } },
}
local ORDER = { "B", "Y", "G" }

local function drawCanister(x, y, key, scale, alpha)
  local T = require("src.ui.theme")
  local lg = love.graphics
  local c = CANISTERS[key]
  local s = scale or 1
  lg.push(); lg.translate(x, y); lg.scale(s)
  T.set(T.C.ink, alpha); lg.rectangle("fill", -28, -54, 56, 108, 14, 14)
  T.set(T.C.metal, alpha); lg.rectangle("fill", -24, -50, 48, 100, 12, 12)
  lg.setColor(c.color[1], c.color[2], c.color[3], alpha or 1); lg.rectangle("fill", -18, -30, 36, 62, 6, 6)
  lg.setColor(1, 1, 1, 0.6 * (alpha or 1))
  for k = 0, 5 do lg.circle("fill", -8 + (k % 3) * 8, -18 + math.floor(k / 3) * 30, 4) end
  T.set(T.C.metalDark, alpha); lg.rectangle("fill", -14, -60, 28, 12, 4, 4)
  lg.pop()
  Base.text(c.label, x - 50, y + 58 * s, 100, 13, T.C.white)
end

------------------------------------------------------------------------------
-- Chemical Absorbent Mix
------------------------------------------------------------------------------
local Mix = Base.extend({
  system = "AIR SYSTEM - CO2 SCRUBBER", title = "Chemical Absorbent Mix",
  hint = "Load the canisters into the scrubber in the SAME order as the chart on the wall.",
  timeLimit = 45, LENGTH = 5, MAX_MISTAKES = 3,
})
P.chemmix = Mix
Mix.CANISTERS = CANISTERS

function Mix:setup()
  self.sequence = {}
  for i = 1, self.LENGTH do self.sequence[i] = ORDER[self:rand(1, 3)] end
  self.loaded = {}
  self.buttons = {}
  for i, k in ipairs(ORDER) do self.buttons[i] = { key = k, x = 420 + (i - 1) * 220, y = 470 } end
  self.flash = 0
end
function Mix:progress() return #self.loaded / self.LENGTH end
function Mix:co2() return 1.2 - 0.85 * (#self.loaded / self.LENGTH) end

function Mix:load(key)
  if self.state ~= "play" then return end
  if self.sequence[#self.loaded + 1] == key then
    self.loaded[#self.loaded + 1] = key
    if #self.loaded == self.LENGTH then self:win("Scrubber packed! CO2 drops below 0.5% - easy breathing.") end
  else
    self.mistakes = self.mistakes + 1
    self.loaded = {}
    self.flash = 0.5
    if self.mistakes >= self.MAX_MISTAKES then self:lose("Wrong chemical mix - the scrubber clogged!") end
  end
end

function Mix:update(dt)
  if not self:tick(dt) then return end
  self.flash = math.max(0, self.flash - dt)
end
function Mix:mousepressed(x, y)
  Base.mousepressed(self, x, y)
  for _, b in ipairs(self.buttons) do
    if math.abs(x - b.x) < 50 and math.abs(y - b.y) < 70 then self:load(b.key) end
  end
end
function Mix:keypressed(k)
  if k == "1" then self:load("B") elseif k == "2" then self:load("Y") elseif k == "3" then self:load("G") end
end
function Mix:solve() for i = #self.loaded + 1, self.LENGTH do self:load(self.sequence[i]) end end

function Mix:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  -- wall chart with the recipe
  T.box(170, 160, 330, 120, T.hex("#0B1830"), 10, 3)
  Base.text("ATMOSPHERE CHART - LOAD ORDER", 170, 168, 330, 13, C.cyanLight)
  for i, k in ipairs(self.sequence) do
    local cx = 205 + (i - 1) * 62
    local done = i <= #self.loaded
    lg.setColor(CANISTERS[k].color); lg.circle("fill", cx, 230, 20)
    T.set(C.ink); lg.setLineWidth(3); lg.circle("line", cx, 230, 20); lg.setLineWidth(1)
    if done then T.set(C.white); lg.setLineWidth(4); lg.line(cx - 9, 230, cx - 2, 238, cx + 11, 220); lg.setLineWidth(1) end
    Base.text(tostring(i), cx - 20, 254, 40, 12, C.offWhite)
  end
  -- rotating scrubber chambers
  local cx, cy, r = 760, 250, 90
  T.set(C.ink); lg.circle("fill", cx, cy, r + 14)
  T.set(self.flash > 0 and C.critical or C.metalShade); lg.circle("fill", cx, cy, r + 8)
  T.set(T.hex("#1B2140")); lg.circle("fill", cx, cy, r)
  local spin = t * 0.6
  for i = 1, self.LENGTH do
    local a = spin + (i - 1) * 2 * math.pi / self.LENGTH
    local x, y = cx + math.cos(a) * 58, cy + math.sin(a) * 58
    T.set(C.ink); lg.circle("fill", x, y, 22)
    if self.loaded[i] then lg.setColor(CANISTERS[self.loaded[i]].color) else T.set(C.metalDark) end
    lg.circle("fill", x, y, 18)
  end
  -- CO2 readout
  local co2 = self:co2()
  Base.text("CABIN CO2", 920, 180, 180, 15, C.cyanLight)
  Base.text(string.format("%.2f%%", co2), 920, 202, 180, 34, co2 < 0.5 and C.good or C.critical)
  T.meter(940, 250, 140, 10, co2 / 1.2, co2 < 0.5 and C.good or C.critical)
  for _, b in ipairs(self.buttons) do
    local hot = math.abs(self.mx - b.x) < 50 and math.abs(self.my - b.y) < 70
    drawCanister(b.x, b.y - (hot and 6 or 0), b.key, 1)
  end
  for i = 1, self.MAX_MISTAKES do
    T.circle(Base.AX + 30 + i * 30, Base.AY + 410, 10, i <= self.MAX_MISTAKES - self.mistakes and C.caution or C.critical, 2)
  end
end

------------------------------------------------------------------------------
-- 21% O2 Sweet Spot: two valves; O2 share must sit at 21% AND the total
-- pressure must stay in the green, while the needles wobble.
------------------------------------------------------------------------------
local Gas = Base.extend({
  system = "AIR SYSTEM - GAS MIX", title = "21% O2 Sweet Spot",
  hint = "Drag the OXYGEN and NITROGEN valves: O2 must read 21% and the pressure must stay green. Hold it!",
  timeLimit = 40, HOLD = 2.0, O2_LO = 20.4, O2_HI = 21.6, P_LO = 0.85, P_HI = 1.15,
})
P.gasmix = Gas

function Gas:setup()
  self.o2 = Base.Slider.new(420, 210, 300, 0.7, true, { 0.55, 0.9, 1, 1 }, "OXYGEN")
  self.n2 = Base.Slider.new(560, 210, 300, 0.3, true, { 0.65, 0.7, 0.85, 1 }, "NITROGEN")
  self.hold = 0
end
function Gas:pressure() return self.o2.value + self.n2.value end
function Gas:o2Percent()
  local total = self:pressure()
  local wobble = 0.3 * math.sin(self.time * 2.3) + 0.15 * math.sin(self.time * 5.1)
  if total <= 0.001 then return 0 end
  return 100 * self.o2.value / total + wobble
end
function Gas:ok()
  local o, p = self:o2Percent(), self:pressure()
  return o >= self.O2_LO and o <= self.O2_HI and p >= self.P_LO and p <= self.P_HI
end
function Gas:progress()
  local e = math.abs(self:o2Percent() - 21) / 21
  return self.state == "won" and 1 or Base.clamp(1 - e * 3, 0, 1) * 0.7 + 0.3 * self.hold / self.HOLD
end

function Gas:update(dt)
  if not self:tick(dt) then return end
  if self:ok() then
    self.hold = self.hold + dt
    if self.hold >= self.HOLD then self:win("Locked at 21% oxygen - just like the air on Earth!") end
  else self.hold = 0 end
end
function Gas:mousepressed(x, y) Base.mousepressed(self, x, y); if not self.o2:press(x, y) then self.n2:press(x, y) end end
function Gas:mousemoved(x, y) Base.mousemoved(self, x, y); self.o2:move(x, y); self.n2:move(x, y) end
function Gas:mousereleased(x, y) Base.mousereleased(self, x, y); self.o2:release(); self.n2:release() end
function Gas:keypressed(k)
  local s = 0.01
  if k == "up" then self.o2.value = Base.clamp(self.o2.value + s, 0, 1)
  elseif k == "down" then self.o2.value = Base.clamp(self.o2.value - s, 0, 1)
  elseif k == "right" then self.n2.value = Base.clamp(self.n2.value + s, 0, 1)
  elseif k == "left" then self.n2.value = Base.clamp(self.n2.value - s, 0, 1) end
end
function Gas:solve()
  self.o2.value, self.n2.value = 0.21, 0.79
  self.time = 0 -- needles at rest
  for _ = 1, 30 do self:update(self.HOLD / 25) end
end

function Gas:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  Base.drawSlider(self.o2)
  Base.drawSlider(self.n2)
  -- digital O2 bar meter
  local o = self:o2Percent()
  local x, y, w, h = 720, 200, 360, 70
  T.box(x - 8, y - 8, w + 16, h + 16, C.metalDark, 10, 3)
  T.set(T.hex("#071222")); lg.rectangle("fill", x, y, w, h, 6, 6)
  local segs = 30
  for i = 0, segs - 1 do
    local v = (i + 0.5) / segs * 40 -- 0..40 %
    local lit = v <= o
    local col = (v >= self.O2_LO and v <= self.O2_HI) and C.good or (v < 19.5 and C.water or (v > 23.5 and C.critical or C.caution))
    if lit then T.set(col) else T.set(col, 0.15) end
    lg.rectangle("fill", x + 6 + i * (w - 12) / segs, y + 10, (w - 12) / segs - 3, h - 20, 2, 2)
  end
  local zx = x + 6 + (21 / 40) * (w - 12)
  T.set(C.white); lg.polygon("fill", zx - 8, y - 14, zx + 8, y - 14, zx, y - 2)
  Base.text(string.format("O2  %.1f%%", o), x, y + h + 12, w, 26, self:ok() and C.good or C.white)
  -- pressure needle gauge
  local gx, gy, gr = 900, 455, 72
  T.set(C.ink); lg.circle("fill", gx, gy, gr + 8)
  T.set(C.offWhite); lg.circle("fill", gx, gy, gr)
  local function ang(v) return math.pi * (0.75 + 1.5 * Base.clamp(v / 2, 0, 1)) end
  T.set(C.good); lg.setLineWidth(10); lg.arc("line", "open", gx, gy, gr - 12, ang(self.P_LO), ang(self.P_HI)); lg.setLineWidth(1)
  local a = ang(self:pressure() + 0.03 * math.sin(t * 6))
  T.set(C.critical); lg.setLineWidth(5); lg.line(gx, gy, gx + math.cos(a) * (gr - 10), gy + math.sin(a) * (gr - 10)); lg.setLineWidth(1)
  T.circle(gx, gy, 9, C.ink, 1)
  Base.text("PRESSURE", gx - 80, gy + gr + 12, 160, 14, C.cyanLight)
  T.meter(720, 330, 360, 10, self.hold / self.HOLD, C.good)
  Base.text("HOLD", 720, 344, 360, 13, C.good)
end

return P
