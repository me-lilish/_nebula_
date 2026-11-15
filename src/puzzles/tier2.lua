--[[
  Tier 2 - DUST SYSTEM mini-games
    brush : "Static Brush-Off"          (Brush Station)    scrub the dust off the suit
    hepa  : "HEPA Cartridge Alignment"  (Dust Filter Unit) swap + lock a filter
]]
local Base = require("src.puzzles.base")
local P = {}

------------------------------------------------------------------------------
-- Static Brush-Off
------------------------------------------------------------------------------
local Brush = Base.extend({
  system = "DUST SYSTEM - SUIT", title = "Static Brush-Off",
  hint = "Hold the mouse button and sweep the magnetic brush over every dust clump!",
  timeLimit = 25, RADIUS = 52,
  SPOTS = { { 520, 250 }, { 600, 230 }, { 470, 330 }, { 650, 330 }, { 560, 380 }, { 500, 450 },
    { 620, 450 }, { 470, 530 }, { 640, 530 } },
})
P.brush = Brush

function Brush:setup()
  self.clumps = {}
  for i, s in ipairs(self.SPOTS) do self.clumps[i] = { x = s[1], y = s[2], hp = 1, size = 70 + (i % 3) * 14 } end
end
function Brush:left()
  local n = 0
  for _, c in ipairs(self.clumps) do if c.hp > 0 then n = n + 1 end end
  return n
end
function Brush:progress() return 1 - self:left() / #self.clumps end

function Brush:sweep(x, y, power)
  for _, c in ipairs(self.clumps) do
    if c.hp > 0 and Base.dist(x, y, c.x, c.y) < self.RADIUS then c.hp = math.max(0, c.hp - power) end
  end
  if self:left() == 0 then self:win("Suit dust 0%! The static brush pulled every grain off.") end
end

function Brush:update(dt)
  if not self:tick(dt) then return end
  if self.down then self:sweep(self.mx, self.my, dt * 1.4) end
end
function Brush:mousepressed(x, y) Base.mousepressed(self, x, y); self:sweep(x, y, 0.15) end
function Brush:mousemoved(x, y)
  local d = Base.dist(x, y, self.mx, self.my)
  Base.mousemoved(self, x, y)
  if self.down then self:sweep(x, y, math.min(0.4, d * 0.01)) end
end
function Brush:solve() for _, c in ipairs(self.clumps) do c.hp = 0 end; self:sweep(-999, -999, 0) end

function Brush:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  T.set(T.hex("#1B2040")); lg.rectangle("fill", Base.AX, Base.AY, Base.AW, Base.AH, 12, 12)
  local A = require("src.assets")
  local v = A.image("assets/vulcan_idle.png")
  if v then lg.setColor(1, 1, 1); local s = 420 / v:getHeight(); lg.draw(v, 560, 575, 0, s, s, v:getWidth() / 2, v:getHeight()) end
  for _, c in ipairs(self.clumps) do
    if c.hp > 0 then Base.sprite("dust_clump", c.x, c.y, c.size * (0.45 + 0.55 * c.hp), t * 0.2, 0.3 + 0.7 * c.hp) end
  end
  local dust = math.floor((1 - self:progress()) * 100 + 0.5)
  Base.text("SUIT DUST", 860, 230, 200, 18, C.cyanLight)
  Base.text(dust .. "%", 860, 255, 200, 54, dust > 0 and C.dust or C.good)
  T.meter(880, 330, 160, 12, dust / 100, dust > 0 and C.dust or C.good)
  Base.sprite("mag_brush", self.mx + 20, self.my + 40, 130, self.down and (-0.5 + math.sin(t * 20) * 0.2) or -0.5)
  if self.down then
    lg.setColor(0.3, 0.9, 1, 0.8)
    for k = 1, 5 do lg.line(self.mx, self.my, self.mx + math.sin(t * 30 + k) * 30, self.my + math.cos(t * 23 + k) * 30) end
  end
end

------------------------------------------------------------------------------
-- HEPA Cartridge Alignment
------------------------------------------------------------------------------
local Hepa = Base.extend({
  system = "DUST SYSTEM - AIR FILTER", title = "HEPA Cartridge Alignment",
  timeLimit = 45, MAX_MISTAKES = 3, TOLERANCE = 10,
  HOUSING = { x = 300, y = 200, w = 260, h = 330 },
  BIN = { x = 820, y = 420, w = 200, h = 140 },
  SHELF = { x = 820, y = 180, w = 200, h = 200 },
  ROT_LEFT = { x = 300, y = 545, w = 70, h = 44 }, ROT_RIGHT = { x = 490, y = 545, w = 70, h = 44 },
  LOCK = { x = 380, y = 545, w = 100, h = 44 },
})
P.hepa = Hepa

local HINTS = {
  pull = "1. Drag the clogged filter out of the housing into the bin.",
  clear = "2. Click the dust left in the intake to clear it.",
  insert = "3. Drag the fresh HEPA filter from the shelf into the housing.",
  align = "4. Rotate until the blue marks line up, then press LOCK.",
}

function Hepa:setup()
  self.step = "pull"
  self.hint = HINTS.pull
  self.held = nil
  self.dust = {}
  for i = 1, 4 do self.dust[i] = { x = 360 + (i % 2) * 120, y = 260 + i * 50, on = true } end
  self.angle = 60 + self:rand() * 240 -- degrees off the groove
end
function Hepa:_go(step) self.step = step; self.hint = HINTS[step] end
function Hepa:progress()
  local order = { pull = 0, clear = 0.25, insert = 0.5, align = 0.75 }
  return self.state == "won" and 1 or order[self.step]
end
function Hepa:misaligned() local a = self.angle % 360; return math.min(a, 360 - a) end

function Hepa:mousepressed(x, y)
  Base.mousepressed(self, x, y)
  if self.step == "pull" and Base.inside(x, y, self.HOUSING) then self.held = "dirty"
  elseif self.step == "clear" then
    for _, d in ipairs(self.dust) do
      if d.on and Base.dist(x, y, d.x, d.y) < 40 then d.on = false end
    end
    local left = 0
    for _, d in ipairs(self.dust) do if d.on then left = left + 1 end end
    if left == 0 then self:_go("insert") end
  elseif self.step == "insert" and Base.inside(x, y, self.SHELF) then self.held = "clean"
  elseif self.step == "align" then
    if Base.inside(x, y, self.ROT_LEFT) then self:rotate(-15)
    elseif Base.inside(x, y, self.ROT_RIGHT) then self:rotate(15)
    elseif Base.inside(x, y, self.LOCK) then self:lock() end
  end
end

function Hepa:mousereleased(x, y)
  Base.mousereleased(self, x, y)
  if self.held == "dirty" and Base.inside(x, y, self.BIN) then self:_go("clear")
  elseif self.held == "clean" and Base.inside(x, y, self.HOUSING) then self:_go("align") end
  self.held = nil
end

function Hepa:keypressed(k)
  if self.step ~= "align" then return end
  if k == "left" or k == "a" then self:rotate(-15)
  elseif k == "right" or k == "d" then self:rotate(15)
  elseif k == "space" or k == "return" then self:lock() end
end

function Hepa:rotate(deg) self.angle = (self.angle + deg) % 360 end

function Hepa:lock()
  if self:misaligned() <= self.TOLERANCE then
    self:win("Click! The new HEPA filter is locked in. Fresh, dust-free air!")
  else
    self.mistakes = self.mistakes + 1
    if self.mistakes >= self.MAX_MISTAKES then self:lose("The filter jammed in the grooves. Try again!") end
  end
end

function Hepa:solve()
  self:mousepressed(self.HOUSING.x + 50, self.HOUSING.y + 50); self:mousereleased(self.BIN.x + 50, self.BIN.y + 50)
  for _, d in ipairs(self.dust) do self:mousepressed(d.x, d.y) end
  self:mousepressed(self.SHELF.x + 50, self.SHELF.y + 50); self:mousereleased(self.HOUSING.x + 50, self.HOUSING.y + 50)
  self.angle = 0; self:lock()
end

function Hepa:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  local h = self.HOUSING
  Base.sprite("filter_housing", h.x + h.w / 2, h.y + h.h / 2, h.w + 40)
  -- what is inside the housing
  if self.step == "pull" and self.held ~= "dirty" then Base.sprite("hepa_dirty", h.x + h.w / 2 + 20, h.y + h.h / 2, 150) end
  if self.step == "clear" then
    for _, d in ipairs(self.dust) do if d.on then Base.sprite("dust_clump", d.x, d.y, 70, t) end end
  end
  if self.step == "align" or self.state == "won" then
    local a = math.rad(self.angle)
    local cx, cy = h.x + h.w / 2 + 20, h.y + h.h / 2
    Base.sprite("hepa_clean", cx, cy, 150)
    -- alignment marks: groove (fixed) and notch (rotates)
    lg.setLineWidth(6)
    T.set(C.ink); lg.circle("line", cx, cy - 150, 16)
    T.set(C.cyan); lg.line(cx, cy - 172, cx, cy - 128)
    local nx, ny = cx + math.sin(a) * 120, cy - math.cos(a) * 120
    T.set(self:misaligned() <= self.TOLERANCE and C.good or C.caution); lg.circle("fill", nx, ny, 12)
    lg.setLineWidth(1)
    Base.button("<", self.ROT_LEFT.x, self.ROT_LEFT.y, self.ROT_LEFT.w, self.ROT_LEFT.h, C.cyan)
    Base.button("LOCK", self.LOCK.x, self.LOCK.y, self.LOCK.w, self.LOCK.h, C.good)
    Base.button(">", self.ROT_RIGHT.x, self.ROT_RIGHT.y, self.ROT_RIGHT.w, self.ROT_RIGHT.h, C.cyan)
  end
  -- bin and shelf
  local b, s = self.BIN, self.SHELF
  T.box(b.x, b.y + 30, b.w, b.h - 30, C.metalDark, 10, 3)
  Base.text("USED FILTER BIN", b.x, b.y + b.h + 6, b.w, 13, C.metalShade)
  T.box(s.x, s.y + s.h - 20, s.w, 20, C.metal, 6, 3)
  Base.text("FRESH FILTER", s.x, s.y + s.h + 6, s.w, 13, C.cyanLight)
  if self.step == "pull" or self.step == "clear" or (self.step == "insert" and self.held ~= "clean") then
    Base.sprite("hepa_clean", s.x + s.w / 2, s.y + s.h / 2 - 10, 120)
  end
  if self.step ~= "pull" and self.step ~= "clear" then
    -- nothing on the shelf any more
  end
  if self.step ~= "pull" then Base.sprite("hepa_dirty", b.x + b.w / 2, b.y + 50, 90, 1.2) end
  if self.held then Base.sprite(self.held == "dirty" and "hepa_dirty" or "hepa_clean", self.mx, self.my, 140) end
  for i = 1, self.MAX_MISTAKES do
    T.circle(Base.AX + 620 + i * 30, Base.AY + 10, 10, i <= self.MAX_MISTAKES - self.mistakes and C.caution or C.metalDark, 2)
  end
end

return P
