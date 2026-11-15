--[[
  Tier 8 - RADIATION SYSTEM mini-games
    excavate : "Regolith Scoop & Chute"  (Regolith Hopper)   claw 9 units into the chute
    armor    : "Bulkhead Armor Lock"     (Shield Holo-Table) plate sections before strikes
]]
local Base = require("src.puzzles.base")
local P = {}

------------------------------------------------------------------------------
-- Regolith Scoop & Chute: move the claw with the mouse (or arrows), click to
-- drop it. Scoop from a mound, then drop the load over the chute funnel.
------------------------------------------------------------------------------
local Dig = Base.extend({
  system = "RADIATION SYSTEM - REGOLITH", title = "Regolith Scoop & Chute",
  hint = "Move the claw, click to scoop Moon soil from a mound, then click over the CHUTE to dump it. 9 loads!",
  timeLimit = 60, timeoutText = "The hopper jammed before 9 loads! Try again.",
  GOAL = 9, RAIL_Y = 180, GROUND_Y = 500, SPEED = 520, DROP_TIME = 0.55, CHUTE_X = 960,
})
P.excavate = Dig

function Dig:setup()
  self.clawX, self.targetX = 600, 600
  self.mounds = { { x = 300, units = 4 }, { x = 480, units = 4 }, { x = 660, units = 4 } }
  self.full, self.units = false, 0
  self.drop = nil -- 0..1 animation while the claw goes down and up
  self.spill = 0
end
function Dig:progress() return self.units / self.GOAL end

function Dig:moundAt(x)
  for _, m in ipairs(self.mounds) do
    if m.units > 0 and math.abs(x - m.x) < 70 then return m end
  end
end
function Dig:overChute(x) return math.abs(x - self.CHUTE_X) < 70 end

function Dig:act()
  if self.state ~= "play" or self.drop then return end
  self.drop = 0
  local x = self.clawX
  if not self.full then
    local m = self:moundAt(x)
    if m then m.units = m.units - 1; self.full = true end
  elseif self:overChute(x) then
    self.full = false
    self.units = self.units + 1
    if self.units >= self.GOAL then self:win("9 loads of regolith in the hopper - enough to shield the whole habitat!") end
  else
    self.full = false -- dumped on the ground: spilled
    self.spill = 0.6
    for _, m in ipairs(self.mounds) do if math.abs(x - m.x) < 120 then m.units = m.units + 1; break end end
  end
end

function Dig:update(dt)
  if not self:tick(dt) then return end
  if self.drop then
    self.drop = self.drop + dt / self.DROP_TIME
    if self.drop >= 1 then self.drop = nil end
  else
    local d = self.targetX - self.clawX
    local step = self.SPEED * dt
    self.clawX = self.clawX + Base.clamp(d, -step, step)
  end
  self.spill = math.max(0, self.spill - dt)
end
function Dig:mousemoved(x, y) Base.mousemoved(self, x, y); self.targetX = Base.clamp(x, 220, 1060) end
function Dig:mousepressed(x, y) Base.mousepressed(self, x, y); self:act() end
function Dig:keypressed(k)
  if k == "left" or k == "a" then self.targetX = Base.clamp(self.clawX - 90, 220, 1060)
  elseif k == "right" or k == "d" then self.targetX = Base.clamp(self.clawX + 90, 220, 1060)
  elseif k == "space" or k == "return" then self:act() end
end
function Dig:solve()
  while self.state == "play" do
    local m = self:moundAt(300) or self:moundAt(480) or self:moundAt(660)
    self.clawX = m.x; self.drop = nil; self:act()
    self.clawX = self.CHUTE_X; self.drop = nil; self:act()
  end
end

function Dig:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  -- lunar dig site
  lg.setColor(0.01, 0.01, 0.05); lg.rectangle("fill", Base.AX, Base.AY, Base.AW, 140, 12, 12)
  T.set(C.cream); lg.rectangle("fill", Base.AX, Base.AY + 140, Base.AW, Base.AH - 140, 12, 12)
  for _, m in ipairs(self.mounds) do
    local s = 0.4 + 0.6 * m.units / 4
    T.set(C.ink); lg.ellipse("fill", m.x, self.GROUND_Y, 90 * s + 4, 50 * s + 4)
    T.set(T.hex("#BFB386")); lg.ellipse("fill", m.x, self.GROUND_Y, 90 * s, 50 * s)
    T.set(T.hex("#D9CFA2")); lg.ellipse("fill", m.x - 14 * s, self.GROUND_Y - 14 * s, 50 * s, 22 * s)
    Base.text(m.units .. "", m.x - 20, self.GROUND_Y + 50, 40, 14, C.ink)
  end
  Base.sprite("dust_processor", self.CHUTE_X, 420, 220)
  Base.text("CHUTE", self.CHUTE_X - 60, 540, 120, 14, C.ink)
  -- rail + claw
  T.set(C.ink); lg.rectangle("fill", 200, self.RAIL_Y - 10, 880, 20, 6, 6)
  T.set(C.metalShade); lg.rectangle("fill", 204, self.RAIL_Y - 6, 872, 12, 5, 5)
  local depth = 0
  if self.drop then depth = math.sin(self.drop * math.pi) * (self.GROUND_Y - self.RAIL_Y - 70) end
  local cx, cy = self.clawX, self.RAIL_Y + 40 + depth
  T.box(cx - 30, self.RAIL_Y - 18, 60, 30, C.caution, 6, 3)
  T.set(C.ink); lg.setLineWidth(6); lg.line(cx, self.RAIL_Y + 10, cx, cy); lg.setLineWidth(1)
  T.box(cx - 24, cy - 14, 48, 22, C.metal, 6, 3)
  local open = self.full and 0.15 or 0.5
  for _, side in ipairs({ -1, 1 }) do
    T.set(C.ink); lg.setLineWidth(9); lg.line(cx + side * 16, cy + 6, cx + side * (16 + 22 * open), cy + 46, cx + side * 6, cy + 60)
    T.set(C.metalShade); lg.setLineWidth(5); lg.line(cx + side * 16, cy + 6, cx + side * (16 + 22 * open), cy + 46, cx + side * 6, cy + 60)
  end
  lg.setLineWidth(1)
  if self.full then T.set(T.hex("#CDBE8E")); lg.ellipse("fill", cx, cy + 40, 18, 12) end
  if self.spill > 0 then Base.text("Spilled! Dump it over the CHUTE.", cx - 150, cy + 80, 300, 14, C.critical) end
  Base.text(string.format("HOPPER  %d / %d", self.units, self.GOAL), 820, 222, 260, 20, C.white)
  T.meter(840, 252, 220, 10, self.units / self.GOAL, C.good)
end

------------------------------------------------------------------------------
-- Bulkhead Armor Lock: drag armor plates from the tray onto the station
-- sections. Red reticles show where flares strike next - plate those first!
------------------------------------------------------------------------------
local Armor = Base.extend({
  system = "RADIATION SYSTEM - HULL SHIELDING", title = "Bulkhead Armor Lock",
  hint = "Drag regolith armor plates onto every section. Red reticles strike soon - cover those first!",
  MAX_HITS = 3, STRIKE_EVERY = 3.2, STRIKE_TIME = 5.5,
  NAMES = { "Crew", "Air", "Water", "Food", "Power", "Greenhouse", "Waste", "Entrance", "Storage" },
  MAP = { x = 330, y = 160, w = 480, h = 390 },
  TRAY = { x = 880, y = 170, w = 200, h = 380 },
})
P.armor = Armor

function Armor:setup()
  self.timeLimit = self.opts.timeLimit or 70
  local names = self.opts.sections or self.NAMES
  self.sections = {}
  local m = self.MAP
  local cw, ch = m.w / 3, m.h / 3
  for i = 1, 9 do
    local c, r = (i - 1) % 3, math.floor((i - 1) / 3)
    self.sections[i] = { name = names[i] or ("Section " .. i), x = m.x + c * cw + 8, y = m.y + r * ch + 8,
      w = cw - 16, h = ch - 16, plated = self.opts.alreadyShielded and self.opts.alreadyShielded[i] or false }
  end
  self.hits, self.strikes, self.next = 0, {}, 1.0
  self.held = false
end
function Armor:platedCount()
  local n = 0
  for _, s in ipairs(self.sections) do if s.plated then n = n + 1 end end
  return n
end
function Armor:progress() return self:platedCount() / 9 end

function Armor:update(dt)
  if not self:tick(dt) then return end
  self.next = self.next - dt
  if self.next <= 0 then
    self.next = self.STRIKE_EVERY
    local open = {}
    for i, s in ipairs(self.sections) do
      if not s.plated and not self.strikes[i] then open[#open + 1] = i end
    end
    if #open > 0 then self.strikes[open[self:rand(1, #open)]] = self.STRIKE_TIME end
  end
  for i, left in pairs(self.strikes) do
    left = left - dt
    if self.sections[i].plated then self.strikes[i] = nil
    elseif left <= 0 then
      self.strikes[i] = nil
      self.hits = self.hits + 1
      self.flash = 0.5
      if self.hits >= self.MAX_HITS then self:lose("A solar flare hit an unshielded section! Try again.") end
    else self.strikes[i] = left end
  end
  if self.flash then self.flash = self.flash - dt; if self.flash <= 0 then self.flash = nil end end
end

function Armor:place(i)
  local s = self.sections[i]
  if not s or s.plated then return false end
  s.plated = true
  self.strikes[i] = nil
  if self:platedCount() == 9 then self:win("Every bulkhead is armored. The crew is safe from the storm!") end
  return true
end

function Armor:sectionAt(x, y)
  for i, s in ipairs(self.sections) do if Base.inside(x, y, s) then return i end end
end
function Armor:mousepressed(x, y)
  Base.mousepressed(self, x, y)
  if Base.inside(x, y, self.TRAY) then self.held = true return end
  -- click-click works as well as drag
  local i = self:sectionAt(x, y)
  if i and self.held then self:place(i); self.held = false end
end
function Armor:mousereleased(x, y)
  Base.mousereleased(self, x, y)
  local i = self:sectionAt(x, y)
  if i and self.held then self:place(i); self.held = false end
end
function Armor:solve() for i = 1, 9 do self:place(i) end end

local function plate(x, y, w, h, alpha)
  local T = require("src.ui.theme")
  local lg = love.graphics
  T.set(T.C.ink, alpha); lg.rectangle("fill", x - 3, y - 3, w + 6, h + 6, 8, 8)
  T.set(T.hex("#CDBE8E"), alpha); lg.rectangle("fill", x, y, w, h, 6, 6)
  T.set(T.hex("#A99A6C"), alpha)
  for k = 1, 3 do lg.rectangle("fill", x + 6, y + k * h / 4 - 3, w - 12, 5, 2, 2) end
  T.set(T.C.metalDark, alpha)
  for _, p in ipairs({ { 8, 8 }, { w - 8, 8 }, { 8, h - 8 }, { w - 8, h - 8 } }) do lg.circle("fill", x + p[1], y + p[2], 4) end
end

function Armor:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  Base.sprite("holo_table", 570, 470, 620, 0, 0.35)
  local m = self.MAP
  lg.setBlendMode("add"); T.set(C.cyan, 0.12); lg.rectangle("fill", m.x, m.y, m.w, m.h, 12, 12); lg.setBlendMode("alpha")
  for i, s in ipairs(self.sections) do
    T.set(C.cyan, 0.7); lg.setLineWidth(2); lg.rectangle("line", s.x, s.y, s.w, s.h, 8, 8); lg.setLineWidth(1)
    if s.plated then plate(s.x + 4, s.y + 4, s.w - 8, s.h - 8, 1) end
    Base.text(s.name, s.x, s.y + s.h / 2 - 9, s.w, 15, s.plated and C.ink or C.cyanLight)
    local left = self.strikes[i]
    if left then
      local cx, cy = s.x + s.w / 2, s.y + s.h / 2
      local r = 20 + 30 * (left / self.STRIKE_TIME)
      T.set(C.critical, 0.4 + 0.4 * math.abs(math.sin(t * 8)))
      lg.setLineWidth(4); lg.circle("line", cx, cy, r)
      lg.line(cx - r - 10, cy, cx - r + 10, cy); lg.line(cx + r - 10, cy, cx + r + 10, cy)
      lg.line(cx, cy - r - 10, cx, cy - r + 10); lg.line(cx, cy + r - 10, cx, cy + r + 10)
      lg.setLineWidth(1)
      Base.text(string.format("%.0f", math.ceil(left)), cx - 30, cy + r + 4, 60, 14, C.critical)
    end
  end
  -- tray of plates
  local tr = self.TRAY
  T.box(tr.x, tr.y, tr.w, tr.h, T.hex("#1B2140"), 12, 3)
  Base.text("ARMOR PLATES", tr.x, tr.y + 10, tr.w, 15, C.caution)
  for k = 0, math.min(5, 9 - self:platedCount()) - 1 do plate(tr.x + 30, tr.y + 50 + k * 54, tr.w - 60, 40, 1) end
  Base.text(string.format("%d left", 9 - self:platedCount()), tr.x, tr.y + tr.h - 30, tr.w, 15, C.offWhite)
  if self.held then plate(self.mx - 60, self.my - 25, 120, 50, 0.85) end
  for i = 1, self.MAX_HITS do
    T.circle(Base.AX + 30 + i * 30, Base.AY + 410, 10, i <= self.MAX_HITS - self.hits and C.caution or C.critical, 2)
  end
  Base.text("HULL", Base.AX + 40, Base.AY + 384, 100, 12, C.caution, "left")
  if self.flash then lg.setColor(1, 0.3, 0.2, self.flash * 0.5); lg.rectangle("fill", Base.AX, Base.AY, Base.AW, Base.AH) end
end

return P
