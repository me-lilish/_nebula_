--[[
  Tier 1 - HUMAN SYSTEM mini-games
    sheep : "Count the Space Sheep"    (Bunk Bed)       rhythm / timing
    oven  : "Perfect Replicator Roast" (Food Dispenser) heat-gauge timing
    scrub : "Scrub & Rinse"            (Bathroom Pod)   wipe the fog away
]]
local Base = require("src.puzzles.base")
local P = {}

------------------------------------------------------------------------------
-- Count the Space Sheep: click (or Space) while a sheep is over the fence.
------------------------------------------------------------------------------
local Sheep = Base.extend({
  system = "HUMAN SYSTEM - SLEEP", title = "Count the Space Sheep",
  hint = "Click or press SPACE when a sheep jumps over the fence. 8 sheep = 8 hours of sleep!",
  FENCE_X = 640, GROUND_Y = 470, WINDOW = 72, SPEED = 250, GAP = 1.25, GOAL = 8, MAX_MISSES = 3,
})
P.sheep = Sheep

function Sheep:setup()
  self.sheep, self.counted, self.misses, self.spawn = {}, 0, 0, 0.3
  self.flash = 0
end
function Sheep:progress() return self.counted / self.GOAL end

function Sheep:update(dt)
  if not self:tick(dt) then return end
  self.flash = math.max(0, self.flash - dt)
  self.spawn = self.spawn - dt
  if self.spawn <= 0 then
    self.sheep[#self.sheep + 1] = { x = Base.AX + 10 }
    self.spawn = self.GAP + self:rand() * 0.5
  end
  for i = #self.sheep, 1, -1 do
    local s = self.sheep[i]
    s.x = s.x + self.SPEED * dt
    if not s.counted and not s.missed and s.x > self.FENCE_X + self.WINDOW then
      s.missed = true
      self:_miss()
    end
    if s.x > Base.AX + Base.AW + 60 then table.remove(self.sheep, i) end
  end
end

function Sheep:_miss()
  self.misses = self.misses + 1
  if self.misses >= self.MAX_MISSES then self:lose("Vulcan lost focus and woke up! Try again.") end
end

function Sheep:count()
  for _, s in ipairs(self.sheep) do
    if not s.counted and not s.missed and math.abs(s.x - self.FENCE_X) <= self.WINDOW then
      s.counted = true
      self.counted = self.counted + 1
      self.flash = 0.3
      if self.counted >= self.GOAL then self:win("8 sheep counted: 8 hours of deep sleep!") end
      return true
    end
  end
  self:_miss()
  return false
end

function Sheep:mousepressed(x, y) Base.mousepressed(self, x, y); self:count() end
function Sheep:keypressed(k) if k == "space" or k == "return" then self:count() end end
function Sheep:solve()
  for _ = self.counted + 1, self.GOAL do
    self.sheep[#self.sheep + 1] = { x = self.FENCE_X }
    self:count()
  end
end

function Sheep:jumpY(x)
  local u = (x - self.FENCE_X) / 170
  return -150 * math.max(0, 1 - u * u)
end

function Sheep:draw(t)
  local T = require("src.ui.theme")
  local lg = love.graphics
  local ax, ay, aw, ah = Base.AX, Base.AY, Base.AW, Base.AH
  lg.setColor(0.05, 0.06, 0.2); lg.rectangle("fill", ax, ay, aw, ah, 12, 12)
  for i = 1, 60 do
    lg.setColor(1, 1, 1, 0.4 + 0.4 * math.sin(t * 2 + i))
    lg.circle("fill", ax + (i * 157) % aw, ay + (i * 83) % (ah - 140), 1.5)
  end
  T.set(T.C.cream); lg.rectangle("fill", ax, self.GROUND_Y + 30, aw, ah - (self.GROUND_Y + 30 - ay), 0, 0, 12, 12)
  Base.sprite("crater_fence", self.FENCE_X, self.GROUND_Y + 10, 260)
  -- counting window
  T.set(self.flash > 0 and T.C.good or T.C.cyan, 0.18 + (self.flash > 0 and 0.3 or 0))
  lg.rectangle("fill", self.FENCE_X - self.WINDOW, ay + 20, self.WINDOW * 2, self.GROUND_Y - ay, 10, 10)
  for _, s in ipairs(self.sheep) do
    local y = self.GROUND_Y - 30 + self:jumpY(s.x) + math.abs(math.sin(s.x * 0.05)) * -6
    Base.sprite("space_sheep", s.x, y, 110, 0, s.missed and 0.45 or 1)
    if s.counted then Base.text("+1 hour", s.x - 60, y - 90, 120, 18, T.C.good) end
  end
  Base.sprite("zzz", ax + aw - 110, ay + 70 + math.sin(t * 2) * 8, 120)
  Base.text(string.format("HOURS SLEPT  %d / %d", self.counted, self.GOAL), ax + 20, ay + 16, 400, 22, T.C.white, "left")
  for i = 1, self.MAX_MISSES do
    T.circle(ax + 40 + (i - 1) * 34, ay + 66, 12, i <= self.MAX_MISSES - self.misses and T.C.caution or T.C.metalDark, 2)
  end
  Base.text("FOCUS", ax + 20, ay + 84, 120, 12, T.C.caution, "left")
end

------------------------------------------------------------------------------
-- Perfect Replicator Roast: pull the meal out while the heat is green.
------------------------------------------------------------------------------
local Oven = Base.extend({
  system = "HUMAN SYSTEM - FOOD PREP", title = "Perfect Replicator Roast",
  hint = "The heat rises... click PULL OUT (or SPACE) when the needle is in the GREEN zone!",
  ZONE = 14,
})
P.oven = Oven

function Oven:setup()
  self.heat, self.zoneLo, self.pulled = 0, 50 + self:rand() * 20, nil
  self.button = { x = 820, y = 500, w = 220, h = 60 }
end
function Oven:progress() return math.min(1, self.heat / 100) end
function Oven:zone() return self.zoneLo, self.zoneLo + self.ZONE end

function Oven:update(dt)
  if not self:tick(dt) then return end
  self.heat = self.heat + (22 + self.heat * 0.18) * dt
  if self.heat >= 100 then self.heat = 100; self.pulled = "burnt"; self:lose("Too late - the ration burnt to a crisp!") end
end

function Oven:pull()
  if self.state ~= "play" then return end
  local lo, hi = self:zone()
  if self.heat < lo then self.pulled = "raw"; self:lose("Too early - the ration is still frozen!")
  elseif self.heat > hi then self.pulled = "burnt"; self:lose("Too late - the ration is burnt!")
  else self.pulled = "cooked"; self:win("A perfect, golden meal. Yum!") end
end

function Oven:mousepressed(x, y) Base.mousepressed(self, x, y); self:pull() end
function Oven:keypressed(k) if k == "space" or k == "return" then self:pull() end end
function Oven:solve() local lo, hi = self:zone(); self.heat = (lo + hi) / 2; self:pull() end

function Oven:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  local lo, hi = self:zone()
  Base.sprite("oven", 480, 360, 560)
  -- glow inside the oven
  lg.setBlendMode("add"); T.set(C.danger, 0.1 + 0.4 * self.heat / 100); lg.rectangle("fill", 300, 290, 300, 110, 12, 12); lg.setBlendMode("alpha")
  local food = self.pulled or (self.heat < lo and "raw" or (self.heat <= hi and "cooked" or "burnt"))
  Base.sprite("ration_" .. food, 450, 350 - (self.pulled and 40 or 0), 220)
  -- heat gauge
  local gx, gy, gw, gh = 960, 180, 50, 330
  T.set(C.ink); lg.rectangle("fill", gx - 4, gy - 4, gw + 8, gh + 8, 10, 10)
  T.set(T.hex("#28305A")); lg.rectangle("fill", gx, gy, gw, gh, 8, 8)
  T.set(C.water, 0.7); lg.rectangle("fill", gx, gy + gh * (1 - lo / 100), gw, gh * lo / 100, 8, 8)
  T.set(C.good); lg.rectangle("fill", gx, gy + gh * (1 - hi / 100), gw, gh * (hi - lo) / 100)
  T.set(C.critical, 0.8); lg.rectangle("fill", gx, gy, gw, gh * (1 - hi / 100), 8, 8)
  local ny = gy + gh * (1 - self.heat / 100)
  T.set(C.white); lg.polygon("fill", gx - 18, ny - 10, gx - 2, ny, gx - 18, ny + 10)
  T.set(C.ink); lg.setLineWidth(3); lg.line(gx - 6, ny, gx + gw + 6, ny); lg.setLineWidth(1)
  Base.text("HEAT", gx - 20, gy - 28, gw + 40, 14, C.cyanLight)
  Base.text("FROZEN", gx + gw + 8, gy + gh - 30, 80, 12, C.water, "left")
  Base.text("PERFECT", gx + gw + 8, gy + gh * (1 - (lo + hi) / 200) - 8, 80, 12, C.good, "left")
  Base.text("BURNT", gx + gw + 8, gy + 10, 80, 12, C.critical, "left")
  local b = self.button
  Base.button("PULL OUT!", b.x, b.y, b.w, b.h, C.caution, Base.inside(self.mx, self.my, b))
end

------------------------------------------------------------------------------
-- Scrub & Rinse: wipe the fogged mirror clean before time runs out.
------------------------------------------------------------------------------
local Scrub = Base.extend({
  system = "HUMAN SYSTEM - HYGIENE", title = "Scrub & Rinse",
  hint = "Hold the mouse button and wipe the sponge over the foggy mirror!",
  timeLimit = 22, COLS = 16, ROWS = 9, RADIUS = 58, GOAL = 0.95,
  MIRROR = { x = 380, y = 200, w = 520, h = 300 },
})
P.scrub = Scrub

function Scrub:setup()
  self.grime = {}
  for i = 1, self.COLS * self.ROWS do self.grime[i] = 1 end
end

function Scrub:cell(i)
  local m = self.MIRROR
  local c, r = (i - 1) % self.COLS, math.floor((i - 1) / self.COLS)
  return m.x + (c + 0.5) * m.w / self.COLS, m.y + (r + 0.5) * m.h / self.ROWS
end

function Scrub:cleanliness()
  local sum = 0
  for _, g in ipairs(self.grime) do sum = sum + g end
  return 1 - sum / #self.grime
end
function Scrub:progress() return self:cleanliness() end

function Scrub:scrubAt(x, y, power)
  for i = 1, #self.grime do
    local cx, cy = self:cell(i)
    if Base.dist(x, y, cx, cy) < self.RADIUS then self.grime[i] = math.max(0, self.grime[i] - power) end
  end
  if self:cleanliness() >= self.GOAL then self:win("Sparkling clean! Germs don't stand a chance.") end
end

function Scrub:update(dt)
  if not self:tick(dt) then return end
  if self.down then self:scrubAt(self.mx, self.my, dt * 0.9) end
end

function Scrub:mousepressed(x, y) Base.mousepressed(self, x, y); self:scrubAt(x, y, 0.2) end
function Scrub:mousemoved(x, y)
  local d = Base.dist(x, y, self.mx, self.my)
  Base.mousemoved(self, x, y)
  if self.down then self:scrubAt(x, y, math.min(0.5, d * 0.012)) end
end
function Scrub:solve() for i = 1, #self.grime do self.grime[i] = 0 end; self:scrubAt(-999, -999, 0) end

function Scrub:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  local m = self.MIRROR
  local fw = m.w * 1.18
  -- clear reflection behind the fog
  T.set(T.hex("#BDEBFF")); lg.rectangle("fill", m.x, m.y, m.w, m.h)
  T.set(C.white, 0.5); lg.polygon("fill", m.x + 40, m.y, m.x + 120, m.y, m.x + 40, m.y + m.h, m.x - 40 + 0, m.y + m.h)
  local A = require("src.assets")
  local v = A.image("assets/vulcan_idle.png")
  if v then lg.setColor(1, 1, 1); local s = 230 / v:getHeight(); lg.draw(v, m.x + m.w / 2, m.y + m.h, 0, s, s, v:getWidth() / 2, v:getHeight()) end
  -- fog
  for i, g in ipairs(self.grime) do
    if g > 0.02 then
      local cx, cy = self:cell(i)
      lg.setColor(0.86, 0.88, 0.86, 0.55 * g); lg.circle("fill", cx, cy, 44)
      lg.setColor(0.9, 0.92, 0.9, 0.5 * g); lg.circle("fill", cx - 8, cy + 6, 30)
      lg.setColor(0.6, 0.55, 0.45, 0.25 * g); lg.circle("fill", cx + 10, cy - 6, 14)
    end
  end
  -- frame: the team's mirror art, glass cut out by drawing only its border
  lg.push("all")
  lg.stencil(function() lg.rectangle("fill", m.x, m.y, m.w, m.h) end, "replace", 1)
  lg.setStencilTest("equal", 0)
  Base.sprite("fogged_mirror", m.x + m.w / 2, m.y + m.h / 2, fw)
  lg.pop()
  Base.text(string.format("CLEAN  %d%%", math.floor(self:cleanliness() * 100)), m.x, m.y + m.h + 40, m.w, 20, C.good)
  Base.sprite("sponge", self.mx, self.my, 130, self.down and math.sin(t * 25) * 0.15 or 0)
  if self.down then
    for k = 0, 4 do lg.setColor(1, 1, 1, 0.8); lg.circle("line", self.mx + math.sin(t * 9 + k) * 40, self.my - 30 - k * 12, 5 + k) end
  end
end

return P
