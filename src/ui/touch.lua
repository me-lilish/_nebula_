--[[
  Touch controls (phones / tablets)
  =================================
  Appear the first time the screen is touched.
    left half  : floating thumb-stick (walk); push it all the way to run
    USE        : like E - use the nearest machine
    RUN        : hold to sprint (like Shift)
    TABLET     : the mission tablet (like Tab)
    (pause     : the round pause button at the top right, src/ui/hud.lua)
    X          : leave a mini-game (like Esc)
  Taps anywhere else work like mouse clicks (stations, puzzles, menus).

  Logic is pure (virtual 1280 x 720 coordinates) and tested in plain Lua.
]]
local Touch = {}
Touch.__index = Touch

Touch.STICK_RADIUS = 80
Touch.DEAD = 0.35            -- stick push needed before walking
Touch.RUN_PUSH = 0.97        -- pushed all the way = run
Touch.BUTTONS = {
  { id = "use", label = "USE", x = 1176, y = 586, r = 64 },
  { id = "run", label = "RUN", x = 1046, y = 640, r = 46 },
  { id = "tab", label = "TABLET", x = 1052, y = 520, r = 38 },
}
Touch.CLOSE = { x = 1138, y = 92, r = 34 } -- leave a mini-game

function Touch.new()
  return setmetatable({ enabled = false, stick = nil, held = {} }, Touch)
end

local function hit(b, x, y) return (x - b.x) ^ 2 + (y - b.y) ^ 2 <= b.r * b.r end
Touch.hit = hit

function Touch:buttonAt(x, y)
  for _, b in ipairs(Touch.BUTTONS) do if hit(b, x, y) then return b end end
  return nil
end

-- Returns "stick", a button id, or nil (= a normal tap / click)
function Touch:press(id, x, y)
  self.enabled = true
  local b = self:buttonAt(x, y)
  if b then
    self.held[id] = b.id
    return b.id
  end
  if x < 560 and y > 260 and not self.stick then
    self.stick = { id = id, ox = x, oy = y, dx = 0, dy = 0 }
    return "stick"
  end
  return nil
end

function Touch:move(id, x, y)
  local s = self.stick
  if s and s.id == id then
    local dx, dy = x - s.ox, y - s.oy
    local len = math.sqrt(dx * dx + dy * dy)
    local max = Touch.STICK_RADIUS
    if len > max then dx, dy = dx / len * max, dy / len * max end
    s.dx, s.dy = dx / max, dy / max
  end
end

function Touch:release(id)
  if self.stick and self.stick.id == id then self.stick = nil end
  self.held[id] = nil
end

function Touch:isHeld(buttonId)
  for _, b in pairs(self.held) do if b == buttonId then return true end end
  return false
end

-- Key-style input for the room (same names as the keyboard)
function Touch:isDown(key)
  local s = self.stick
  if key == "lshift" then
    if self:isHeld("run") then return true end
    return s ~= nil and math.sqrt(s.dx * s.dx + s.dy * s.dy) >= Touch.RUN_PUSH
  end
  if not s then return false end
  if key == "left" then return s.dx < -Touch.DEAD end
  if key == "right" then return s.dx > Touch.DEAD end
  if key == "up" then return s.dy < -Touch.DEAD end
  if key == "down" then return s.dy > Touch.DEAD end
  return false
end

------------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------------
function Touch:draw(puzzleOpen)
  if not self.enabled then return end
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  lg.push("all")
  if puzzleOpen then
    local c = Touch.CLOSE
    T.circle(c.x, c.y, c.r, C.critical, 3)
    lg.setFont(T.font(26)); T.set(C.white); lg.printf("X", c.x - c.r, c.y - 15, c.r * 2, "center")
    lg.pop()
    return
  end
  -- thumb-stick
  local s = self.stick
  local bx, by = s and s.ox or 150, s and s.oy or 560
  T.set(C.space, s and 0.45 or 0.25); lg.circle("fill", bx, by, Touch.STICK_RADIUS)
  T.set(C.cyan, s and 0.7 or 0.35); lg.setLineWidth(4); lg.circle("line", bx, by, Touch.STICK_RADIUS)
  local kx, ky = bx + (s and s.dx or 0) * Touch.STICK_RADIUS, by + (s and s.dy or 0) * Touch.STICK_RADIUS
  T.set(C.cyan, s and 0.85 or 0.4); lg.circle("fill", kx, ky, 34)
  if not s then
    lg.setFont(T.font(14)); T.set(C.cyanLight, 0.6); lg.printf("MOVE", bx - 60, by - 8, 120, "center")
  end
  for _, b in ipairs(Touch.BUTTONS) do
    local on = self:isHeld(b.id)
    T.set(on and C.cyan or C.space, on and 0.85 or 0.55); lg.circle("fill", b.x, b.y, b.r)
    T.set(b.id == "use" and C.caution or C.cyan, 0.9); lg.circle("line", b.x, b.y, b.r)
    lg.setFont(T.font(b.r > 50 and 22 or 14)); T.set(C.white, 0.95)
    lg.printf(b.label, b.x - b.r, b.y - (b.r > 50 and 13 or 8), b.r * 2, "center")
  end
  lg.setLineWidth(1)
  lg.pop()
end

return Touch
