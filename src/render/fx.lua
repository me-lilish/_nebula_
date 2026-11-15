--[[
  Effects: particles, floating "+O2"-style labels and footprints.
  Pure data updates; drawing uses love.graphics (world coordinates).
]]
local Theme = require("src.ui.theme")
local C = Theme.C

local FX = {}
FX.__index = FX

function FX.new()
  return setmetatable({ parts = {}, labels = {}, prints = {} }, FX)
end

local function rnd(a, b) return a + math.random() * (b - a) end

-- kind: "bubble" | "dust" | "spark" | "steam" | "leaf" | "drop"
function FX:burst(kind, x, y, n, color)
  for _ = 1, n or 12 do
    local p = { kind = kind, x = x + rnd(-14, 14), y = y + rnd(-8, 8), t = 0, color = color }
    if kind == "bubble" then
      p.vx, p.vy, p.life, p.r = rnd(-12, 12), rnd(-70, -35), rnd(0.8, 1.5), rnd(3, 7)
    elseif kind == "dust" then
      p.vx, p.vy, p.life, p.r = rnd(-90, 90), rnd(-60, 30), rnd(0.6, 1.2), rnd(4, 10)
    elseif kind == "spark" then
      p.vx, p.vy, p.life, p.r = rnd(-140, 140), rnd(-140, 40), rnd(0.3, 0.7), rnd(2, 3)
    elseif kind == "steam" then
      p.vx, p.vy, p.life, p.r = rnd(-10, 10), rnd(-50, -25), rnd(1, 1.8), rnd(6, 11)
    elseif kind == "leaf" then
      p.vx, p.vy, p.life, p.r = rnd(-60, 60), rnd(-80, -20), rnd(0.8, 1.4), rnd(3, 5)
    else -- drop
      p.vx, p.vy, p.life, p.r = rnd(-50, 50), rnd(-90, -30), rnd(0.6, 1.1), rnd(3, 5)
    end
    self.parts[#self.parts + 1] = p
  end
end

function FX:label(text, x, y, color)
  self.labels[#self.labels + 1] = { text = text, x = x, y = y, t = 0, life = 1.6, color = color or C.cyan }
end

function FX:footprint(x, y, facing)
  local n = #self.prints
  local last = self.prints[n]
  if last and (last.x - x) ^ 2 + (last.y - y) ^ 2 < 22 * 22 then return end
  self.prints[n + 1] = { x = x + ((n % 2 == 0) and -6 or 6), y = y, t = 0, life = 6 }
  if #self.prints > 60 then table.remove(self.prints, 1) end
end

local function step(list, dt, gravity)
  local keep = {}
  for _, p in ipairs(list) do
    p.t = p.t + dt
    if p.t < p.life then
      if p.vx then
        p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
        if gravity then p.vy = p.vy + gravity * dt end
      end
      keep[#keep + 1] = p
    end
  end
  return keep
end

function FX:update(dt)
  self.parts = step(self.parts, dt, 60)
  self.labels = step(self.labels, dt)
  self.prints = step(self.prints, dt)
end

function FX:drawGround()
  local lg = love.graphics
  for _, p in ipairs(self.prints) do
    Theme.set(C.craterShade, 0.7 * (1 - p.t / p.life))
    lg.ellipse("fill", p.x, p.y, 5, 3)
  end
end

function FX:draw()
  local lg = love.graphics
  for _, p in ipairs(self.parts) do
    local a = 1 - p.t / p.life
    if p.kind == "bubble" then
      Theme.set(p.color or C.oxygen, 0.5 * a); lg.circle("fill", p.x, p.y, p.r)
      Theme.set(C.white, 0.9 * a); lg.circle("line", p.x, p.y, p.r)
    elseif p.kind == "dust" then
      Theme.set(p.color or C.dust, 0.6 * a); lg.circle("fill", p.x, p.y, p.r * (1 + p.t))
    elseif p.kind == "spark" then
      Theme.set(p.color or C.caution, a); lg.circle("fill", p.x, p.y, p.r)
    elseif p.kind == "steam" then
      Theme.set(C.white, 0.35 * a); lg.circle("fill", p.x, p.y, p.r * (1 + p.t * 0.8))
    elseif p.kind == "leaf" then
      Theme.set(p.color or C.plant, a); lg.ellipse("fill", p.x, p.y, p.r * 1.6, p.r * 0.8)
    else
      Theme.set(p.color or C.water, a); lg.circle("fill", p.x, p.y, p.r)
    end
  end
  local font = Theme.font(20)
  for _, l in ipairs(self.labels) do
    local a = 1 - l.t / l.life
    local y = l.y - l.t * 40
    lg.setFont(font)
    Theme.set(C.ink, a)
    for _, o in ipairs({ { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 } }) do lg.printf(l.text, l.x - 100 + o[1], y + o[2], 200, "center") end
    Theme.set(l.color, a)
    lg.printf(l.text, l.x - 100, y, 200, "center")
  end
end

return FX
