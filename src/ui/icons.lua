--[[
  Icons drawn in code (team style: flat shapes, thick ink outline).
  Icons.draw(name, cx, cy, size, color)  - size = icon height in pixels
]]
local Theme = require("src.ui.theme")
local C = Theme.C

local Icons = {}

local function ink(lw) Theme.set(C.ink); love.graphics.setLineWidth(lw or 2) end

local DRAW = {}

DRAW.air = function(x, y, s, col)
  local lg = love.graphics
  local r = s * 0.24
  for _, p in ipairs({ { -0.22, 0.08, 1 }, { 0.2, 0.12, 0.8 }, { 0.02, -0.22, 0.7 } }) do
    Theme.set(col); lg.circle("fill", x + p[1] * s, y + p[2] * s, r * p[3])
    ink(); lg.circle("line", x + p[1] * s, y + p[2] * s, r * p[3])
    Theme.set(C.white, 0.7); lg.circle("fill", x + p[1] * s - r * p[3] * 0.35, y + p[2] * s - r * p[3] * 0.35, r * p[3] * 0.25)
  end
end

DRAW.water = function(x, y, s, col)
  local lg = love.graphics
  local r = s * 0.3
  local pts = { x, y - s * 0.48, x + r * 0.95, y + s * 0.02, x - r * 0.95, y + s * 0.02 }
  Theme.set(col); lg.polygon("fill", pts); lg.circle("fill", x, y + s * 0.12, r)
  ink(); lg.arc("line", "open", x, y + s * 0.12, r, -0.35, math.pi + 0.35)
  lg.line(x - r * 0.95, y + s * 0.02, x, y - s * 0.48, x + r * 0.95, y + s * 0.02)
  Theme.set(C.white, 0.8); lg.circle("fill", x - r * 0.35, y + s * 0.08, r * 0.2)
end

DRAW.clean = function(x, y, s, col)
  local lg = love.graphics
  local function sparkle(cx, cy, r)
    local pts = { cx, cy - r, cx + r * 0.22, cy - r * 0.22, cx + r, cy, cx + r * 0.22, cy + r * 0.22,
      cx, cy + r, cx - r * 0.22, cy + r * 0.22, cx - r, cy, cx - r * 0.22, cy - r * 0.22 }
    Theme.set(col); lg.polygon("fill", pts); ink(); lg.polygon("line", pts)
  end
  sparkle(x - s * 0.08, y + s * 0.05, s * 0.42)
  sparkle(x + s * 0.3, y - s * 0.28, s * 0.18)
end

DRAW.power = function(x, y, s, col)
  local lg = love.graphics
  local pts = { x + s * 0.08, y - s * 0.5, x - s * 0.3, y + s * 0.06, x - s * 0.02, y + s * 0.06,
    x - s * 0.1, y + s * 0.5, x + s * 0.3, y - s * 0.08, x + s * 0.02, y - s * 0.08 }
  Theme.set(col); lg.polygon("fill", { pts[1], pts[2], pts[3], pts[4], pts[11], pts[12] })
  lg.polygon("fill", { pts[5], pts[6], pts[7], pts[8], pts[9], pts[10] })
  lg.polygon("fill", { pts[3], pts[4], pts[5], pts[6], pts[9], pts[10], pts[11], pts[12] })
  ink(); lg.polygon("line", pts)
end

DRAW.food = function(x, y, s, col)
  local lg = love.graphics
  Theme.set(col); lg.circle("fill", x - s * 0.13, y + s * 0.06, s * 0.3); lg.circle("fill", x + s * 0.13, y + s * 0.06, s * 0.3)
  ink(); lg.circle("line", x - s * 0.13, y + s * 0.06, s * 0.3); lg.circle("line", x + s * 0.13, y + s * 0.06, s * 0.3)
  Theme.set(col); lg.circle("fill", x, y + s * 0.08, s * 0.24)
  Theme.set(C.plant); lg.ellipse("fill", x + s * 0.12, y - s * 0.32, s * 0.16, s * 0.08)
  ink(); lg.ellipse("line", x + s * 0.12, y - s * 0.32, s * 0.16, s * 0.08); lg.line(x, y - s * 0.22, x + s * 0.02, y - s * 0.38)
end

DRAW.health = function(x, y, s, col)
  local lg = love.graphics
  local r = s * 0.24
  Theme.set(col)
  lg.circle("fill", x - r * 0.95, y - s * 0.08, r); lg.circle("fill", x + r * 0.95, y - s * 0.08, r)
  lg.polygon("fill", x - r * 1.9, y, x + r * 1.9, y, x, y + s * 0.46)
  ink(); lg.arc("line", "open", x - r * 0.95, y - s * 0.08, r, math.pi * 0.75, math.pi * 2)
  lg.arc("line", "open", x + r * 0.95, y - s * 0.08, r, math.pi, math.pi * 2.25)
  lg.line(x - r * 1.85, y + r * 0.1, x, y + s * 0.46, x + r * 1.85, y + r * 0.1)
  Theme.set(C.white, 0.75); lg.circle("fill", x - r * 1.1, y - s * 0.14, r * 0.3)
end

DRAW.radiation = function(x, y, s, col)
  local lg = love.graphics
  local pts = { x - s * 0.36, y - s * 0.4, x + s * 0.36, y - s * 0.4, x + s * 0.36, y + s * 0.02, x, y + s * 0.48, x - s * 0.36, y + s * 0.02 }
  Theme.set(col); lg.polygon("fill", pts); ink(); lg.polygon("line", pts)
  Theme.set(C.ink)
  for i = 0, 2 do
    local a = -math.pi / 2 + i * 2 * math.pi / 3
    lg.arc("fill", x, y - s * 0.02, s * 0.24, a - 0.45, a + 0.45)
  end
  Theme.set(col); lg.circle("fill", x, y - s * 0.02, s * 0.08); Theme.set(C.ink); lg.circle("fill", x, y - s * 0.02, s * 0.045)
end

DRAW.sun = function(x, y, s, col)
  local lg = love.graphics
  Theme.set(col)
  for i = 0, 7 do
    local a = i * math.pi / 4
    lg.setLineWidth(s * 0.09)
    lg.line(x + math.cos(a) * s * 0.3, y + math.sin(a) * s * 0.3, x + math.cos(a) * s * 0.47, y + math.sin(a) * s * 0.47)
  end
  lg.setLineWidth(1)
  Theme.circle(x, y, s * 0.24, col, 2)
end

DRAW.moon = function(x, y, s, col)
  local lg = love.graphics
  Theme.circle(x, y, s * 0.38, col, 2)
  Theme.set(C.craterShade); lg.circle("fill", x - s * 0.1, y - s * 0.08, s * 0.08); lg.circle("fill", x + s * 0.13, y + s * 0.12, s * 0.06)
end

DRAW.arrow = function(x, y, s, col)
  local lg = love.graphics
  local pts = { x + s * 0.5, y, x - s * 0.1, y - s * 0.42, x - s * 0.1, y - s * 0.16, x - s * 0.5, y - s * 0.16,
    x - s * 0.5, y + s * 0.16, x - s * 0.1, y + s * 0.16, x - s * 0.1, y + s * 0.42 }
  Theme.set(col)
  lg.polygon("fill", { pts[1], pts[2], pts[3], pts[4], pts[13], pts[14] })
  lg.rectangle("fill", x - s * 0.5, y - s * 0.16, s * 0.42, s * 0.32)
  ink(3); lg.polygon("line", pts)
end

DRAW.alert = function(x, y, s, col)
  local lg = love.graphics
  local pts = { x, y - s * 0.46, x + s * 0.48, y + s * 0.4, x - s * 0.48, y + s * 0.4 }
  Theme.set(col); lg.polygon("fill", pts); ink(); lg.polygon("line", pts)
  Theme.set(C.ink); lg.rectangle("fill", x - s * 0.05, y - s * 0.18, s * 0.1, s * 0.3); lg.circle("fill", x, y + s * 0.25, s * 0.06)
end

function Icons.draw(name, x, y, size, color)
  local fn = DRAW[name]
  if not fn then return end
  love.graphics.push("all")
  fn(x, y, size, color or C.cyan)
  love.graphics.pop()
end

return Icons
