--[[
  Mini-game base class + shared drawing helpers
  =============================================
  Every mini-game is a small state machine:
     state = "play" -> "won" | "lost"
  It reads input in virtual-screen coordinates (1280 x 720) inside the
  puzzle panel, ticks its own timer and calls self:win(text) / self:lose(text).
  Game logic never calls love.*, so plain-Lua tests can play every puzzle;
  only the draw functions use love.graphics.

  Each puzzle also has :solve() - it puts the puzzle into its winning
  configuration through its own rules (used by tests and the walking bot).
]]
local Base = {}
Base.__index = Base

Base.PX, Base.PY, Base.PW, Base.PH = 120, 64, 1040, 592   -- panel
Base.AX, Base.AY, Base.AW, Base.AH = 150, 150, 980, 430   -- play area

function Base.extend(def)
  local cls = setmetatable(def, { __index = Base })
  cls.__index = cls
  return cls
end

function Base.create(cls, opts)
  local self = setmetatable({}, cls)
  self.opts = opts or {}
  self.rng = self.opts.rng or math.random
  self.time, self.state, self.after = 0, "play", 0
  self.mx, self.my, self.down = 0, 0, false
  self.mistakes = 0
  if self.setup then self:setup() end
  return self
end

function Base:rand(a, b)
  if a and b then return a + math.floor(self.rng() * (b - a + 1)) end
  return self.rng()
end

function Base:tick(dt)
  if self.state ~= "play" then self.after = self.after + dt; return false end
  self.time = self.time + dt
  if self.timeLimit and self.time >= self.timeLimit then
    self:lose(self.timeoutText or "Out of time! Try again.")
    return false
  end
  return true
end

function Base:timeLeft() return self.timeLimit and math.max(0, self.timeLimit - self.time) or nil end
function Base:win(text) if self.state == "play" then self.state, self.result, self.after = "won", text or "Great job!", 0 end end
function Base:lose(text) if self.state == "play" then self.state, self.result, self.after = "lost", text or "Try again!", 0 end end

-- progress 0..1 shown on the panel (override)
function Base:progress() return 0 end

-- input defaults (override what you need)
function Base:update(dt) self:tick(dt) end
function Base:mousepressed(x, y) self.down, self.mx, self.my = true, x, y end
function Base:mousereleased(x, y) self.down, self.mx, self.my = false, x, y end
function Base:mousemoved(x, y) self.mx, self.my = x, y end
function Base:keypressed(key) end

function Base.inside(x, y, r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end
function Base.dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
function Base.clamp(v, a, b) return math.max(a, math.min(b, v)) end

------------------------------------------------------------------------------
-- Slider (logic + drawing): value 0..1, drag the knob along a track
------------------------------------------------------------------------------
local Slider = {}
Slider.__index = Slider
Base.Slider = Slider

function Slider.new(x, y, len, value, vertical, color, label)
  return setmetatable({ x = x, y = y, len = len, value = value or 0.5, vertical = vertical,
    color = color, label = label, dragging = false }, Slider)
end
function Slider:knob()
  if self.vertical then return self.x, self.y + self.len * (1 - self.value) end
  return self.x + self.len * self.value, self.y
end
function Slider:setFrom(x, y)
  if self.vertical then self.value = Base.clamp(1 - (y - self.y) / self.len, 0, 1)
  else self.value = Base.clamp((x - self.x) / self.len, 0, 1) end
end
function Slider:press(x, y)
  local kx, ky = self:knob()
  local onTrack
  if self.vertical then onTrack = math.abs(x - self.x) < 26 and y > self.y - 20 and y < self.y + self.len + 20
  else onTrack = math.abs(y - self.y) < 26 and x > self.x - 20 and x < self.x + self.len + 20 end
  if Base.dist(x, y, kx, ky) < 30 or onTrack then self.dragging = true; self:setFrom(x, y); return true end
  return false
end
function Slider:move(x, y) if self.dragging then self:setFrom(x, y) end end
function Slider:release() self.dragging = false end

------------------------------------------------------------------------------
-- Drawing helpers (love only)
------------------------------------------------------------------------------
local Theme, Assets
local function deps()
  Theme = Theme or require("src.ui.theme")
  Assets = Assets or require("src.assets")
  return Theme, Assets
end

function Base.img(name)
  local _, A = deps()
  return A.image("assets/minigames/" .. name .. ".png") or A.image("assets/props/" .. name .. ".png")
end

-- sprite centred at (cx, cy), scaled to width w (keeps aspect); rot, alpha optional
function Base.sprite(name, cx, cy, w, rot, alpha, flip)
  local img = Base.img(name)
  local lg = love.graphics
  if not img then
    lg.setColor(0.8, 0.8, 0.9, alpha or 1); lg.circle("fill", cx, cy, w / 3); return
  end
  local s = w / img:getWidth()
  lg.setColor(1, 1, 1, alpha or 1)
  lg.draw(img, cx, cy, rot or 0, flip and -s or s, s, img:getWidth() / 2, img:getHeight() / 2)
end

function Base.spriteHeight(name, w)
  local img = Base.img(name)
  return img and w * img:getHeight() / img:getWidth() or w
end

function Base.text(str, x, y, w, size, color, align)
  local T = deps()
  love.graphics.setFont(T.font(size or 16))
  T.set(color or T.C.white)
  love.graphics.printf(str, x, y, w, align or "center")
end

function Base.drawSlider(s)
  local T = deps()
  local C, lg = T.C, love.graphics
  local x2, y2 = s.x, s.y
  if s.vertical then y2 = s.y + s.len else x2 = s.x + s.len end
  T.set(C.ink); lg.setLineWidth(14); lg.line(s.x, s.y, x2, y2)
  T.set(C.metalDark); lg.setLineWidth(8); lg.line(s.x, s.y, x2, y2)
  local kx, ky = s:knob()
  T.set(s.color or C.cyan); lg.setLineWidth(8)
  if s.vertical then lg.line(s.x, y2, kx, ky) else lg.line(s.x, s.y, kx, ky) end
  lg.setLineWidth(1)
  T.circle(kx, ky, 16, C.metal, 3)
  T.circle(kx, ky, 7, s.color or C.cyan, 2)
  if s.label then
    if s.vertical then Base.text(s.label, s.x - 60, y2 + 18, 120, 14, s.color or C.cyan)
    else Base.text(s.label, s.x - 120, s.y - 10, 100, 14, s.color or C.cyan, "right") end
  end
end

-- big rounded button; returns rect
function Base.button(label, x, y, w, h, color, hot)
  local T = deps()
  local C, lg = T.C, love.graphics
  T.set(C.ink); lg.rectangle("fill", x - 3, y - 3, w + 6, h + 6, 12, 12)
  T.set(hot and T.lighten(color or C.cyan, 0.25) or (color or C.cyan)); lg.rectangle("fill", x, y, w, h, 10, 10)
  T.set(C.white, 0.35); lg.rectangle("fill", x + 6, y + 4, w - 12, 6, 3, 3)
  Base.text(label, x, y + h / 2 - 11, w, 18, C.ink)
  return { x = x, y = y, w = w, h = h }
end

-- Shared frame: dim backdrop, panel, title, hint, timer and progress
function Base.drawFrame(p, t)
  local T = deps()
  local C, lg = T.C, love.graphics
  lg.setColor(0.02, 0.02, 0.08, 0.78); lg.rectangle("fill", 0, 0, 1280, 720)
  T.panel(Base.PX, Base.PY, Base.PW, Base.PH, { cut = 22, fill = T.hex("#0F0D2A"), alpha = 0.98, edge = C.cyan, lineWidth = 3 })
  lg.setFont(T.font(13)); T.set(C.cyan)
  lg.printf(p.system or "", Base.PX + 30, Base.PY + 14, 400, "left")
  T.outlinedText(p.title, Base.PX, Base.PY + 26, Base.PW, "center", C.white, C.ink, T.font(28))
  Base.text(p.hint or "", Base.PX + 40, Base.PY + Base.PH - 44, Base.PW - 80, 16, C.cyanLight)
  -- timer
  local left = p:timeLeft()
  if left then
    local frac = left / p.timeLimit
    local col = frac > 0.5 and C.good or (frac > 0.25 and C.caution or C.critical)
    T.meter(Base.PX + Base.PW - 250, Base.PY + 22, 200, 10, frac, col)
    Base.text(string.format("%d s", math.ceil(left)), Base.PX + Base.PW - 250, Base.PY + 36, 200, 14, col)
  end
  local pr = p:progress()
  T.meter(Base.PX + 30, Base.PY + 40, 200, 10, pr, C.good)
  Base.text(string.format("%d%%", math.floor(pr * 100 + 0.5)), Base.PX + 30, Base.PY + 54, 200, 13, C.good, "left")
  Base.text("Esc: leave", Base.PX + Base.PW - 160, Base.PY + Base.PH - 24, 140, 12, C.metalShade, "right")
end

function Base.drawResult(p, t)
  if p.state == "play" then return end
  local T = deps()
  local C, lg = T.C, love.graphics
  local won = p.state == "won"
  local a = math.min(1, p.after * 4)
  lg.setColor(0.02, 0.02, 0.08, 0.55 * a); lg.rectangle("fill", Base.PX, Base.PY, Base.PW, Base.PH)
  local w, h = 520, 160
  local x, y = 640 - w / 2, 360 - h / 2
  T.panel(x, y, w, h, { cut = 18, fill = C.space, alpha = 0.97 * a, edge = won and C.good or C.critical, lineWidth = 3 })
  T.outlinedText(won and "SUCCESS!" or "NOT QUITE!", x, y + 22, w, "center", won and C.good or C.critical, C.ink, T.font(32))
  Base.text(p.result or "", x + 20, y + 74, w - 40, 18, C.white)
  Base.text("click to continue", x, y + h - 28, w, 13, C.metalShade)
end

return Base
