--[[
  Tier 7 - POWER SYSTEM mini-games
    breaker : "Grid Load Reroute"   (Battery Bank)        drag wires to matching sockets
    oscillo : "Wattage Stabilizer"  (Solar Array Control) match two sine waves
]]
local Base = require("src.puzzles.base")
local P = {}

local COLORS = {
  red = { 1, 0.3, 0.3, 1 }, blue = { 0.3, 0.55, 1, 1 }, yellow = { 1, 0.85, 0.25, 1 },
}
local NAMES = { "red", "blue", "yellow" }

------------------------------------------------------------------------------
-- Grid Load Reroute: drag from a cut cable to the socket of the same colour.
-- The wire follows your mouse - steer it around the sparking LIVE wires.
------------------------------------------------------------------------------
local Breaker = Base.extend({
  system = "POWER SYSTEM - BREAKER CABINET", title = "Grid Load Reroute",
  hint = "Drag each cut cable to the socket of the SAME colour. Steer around the sparking live wires!",
  timeLimit = 55, MAX_MISTAKES = 3, LEFT_X = 300, RIGHT_X = 980, ROWS = { 230, 350, 470 },
})
P.breaker = Breaker

local function shuffled(self, list)
  local t = { list[1], list[2], list[3] }
  for i = 3, 2, -1 do local j = self:rand(1, i); t[i], t[j] = t[j], t[i] end
  return t
end

function Breaker:setup()
  local l, r = shuffled(self, NAMES), shuffled(self, NAMES)
  self.cables, self.sockets = {}, {}
  for i = 1, 3 do
    self.cables[i] = { color = l[i], x = self.LEFT_X, y = self.ROWS[i], done = false }
    self.sockets[i] = { color = r[i], x = self.RIGHT_X, y = self.ROWS[i] }
  end
  -- live (sparking) wires hanging in the middle
  self.hazards = {}
  for i = 1, 2 do
    self.hazards[i] = { x = 520 + (i - 1) * 200, y = 190 + self:rand(0, 200), w = 40, h = 120 }
  end
  self.wires = {}
  self.drag = nil
  self.zap = 0
end
function Breaker:connected()
  local n = 0
  for _, c in ipairs(self.cables) do if c.done then n = n + 1 end end
  return n
end
function Breaker:progress() return self:connected() / 3 end

-- does the segment (x1,y1)-(x2,y2) touch rectangle r?
local function segHitsRect(x1, y1, x2, y2, r)
  local steps = math.max(1, math.floor(Base.dist(x1, y1, x2, y2) / 4))
  for s = 0, steps do
    local u = s / steps
    if Base.inside(x1 + (x2 - x1) * u, y1 + (y2 - y1) * u, r) then return true end
  end
  return false
end
Breaker.segHitsRect = segHitsRect

function Breaker:pathHitsHazard(path)
  for i = 2, #path do
    for _, h in ipairs(self.hazards) do
      if segHitsRect(path[i - 1][1], path[i - 1][2], path[i][1], path[i][2], h) then return true end
    end
  end
  return false
end

function Breaker:mistake(text)
  self.mistakes = self.mistakes + 1
  self.zap = 0.4
  self.lastProblem = text
  if self.mistakes >= self.MAX_MISTAKES then self:lose("ZAP! Too many shorts - the breaker tripped.") end
end

function Breaker:connect(cable, socket, path)
  if self:pathHitsHazard(path) then self:mistake("You touched a live wire!"); return false end
  if socket.color ~= cable.color then self:mistake("Wrong colour - sparks!"); return false end
  cable.done = true
  self.wires[#self.wires + 1] = { color = cable.color, path = path }
  if self:connected() == 3 then self:win("All cables rerouted. The grid load is balanced!") end
  return true
end

function Breaker:update(dt)
  if not self:tick(dt) then return end
  self.zap = math.max(0, self.zap - dt)
end

function Breaker:mousepressed(x, y)
  Base.mousepressed(self, x, y)
  for _, c in ipairs(self.cables) do
    if not c.done and Base.dist(x, y, c.x, c.y) < 36 then self.drag = { cable = c, path = { { c.x, c.y } } } return end
  end
end
function Breaker:mousemoved(x, y)
  Base.mousemoved(self, x, y)
  local d = self.drag
  if d then
    local last = d.path[#d.path]
    if Base.dist(x, y, last[1], last[2]) > 8 then d.path[#d.path + 1] = { x, y } end
    if self:pathHitsHazard({ last, { x, y } }) then self.drag = nil; self:mistake("You touched a live wire!") end
  end
end
function Breaker:mousereleased(x, y)
  Base.mousereleased(self, x, y)
  local d = self.drag
  self.drag = nil
  if not d then return end
  for _, s in ipairs(self.sockets) do
    if Base.dist(x, y, s.x, s.y) < 40 then
      d.path[#d.path + 1] = { s.x, s.y }
      self:connect(d.cable, s, d.path)
      return
    end
  end
end

function Breaker:solve()
  for _, c in ipairs(self.cables) do
    for _, s in ipairs(self.sockets) do
      if s.color == c.color and not c.done then
        -- route above every hazard
        local path = { { c.x, c.y }, { c.x + 80, 160 }, { s.x - 80, 160 }, { s.x, s.y } }
        self:connect(c, s, path)
      end
    end
  end
end

function Breaker:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  -- open breaker cabinet
  T.box(200, 150, 880, 400, T.hex("#2A2F4D"), 14, 4)
  T.set(C.caution); for k = 0, 9 do lg.polygon("fill", 200 + k * 88, 150, 236 + k * 88, 150, 220 + k * 88, 166, 184 + k * 88, 166) end
  -- live hazard wires
  for _, h in ipairs(self.hazards) do
    T.set(C.ink); lg.rectangle("fill", h.x + h.w / 2 - 7, h.y - 40, 14, h.h + 40)
    T.set(T.hex("#C0392B")); lg.rectangle("fill", h.x + h.w / 2 - 4, h.y - 40, 8, h.h + 40)
    lg.setBlendMode("add")
    for k = 1, 4 do
      lg.setColor(0.4, 0.9, 1, 0.8)
      local sy = h.y + h.h
      lg.line(h.x + h.w / 2, sy, h.x + h.w / 2 + math.sin(t * 30 + k) * 26, sy + math.cos(t * 23 + k) * 20)
    end
    lg.setBlendMode("alpha")
    T.set(C.critical, 0.15); lg.rectangle("fill", h.x, h.y, h.w, h.h, 8, 8)
    Base.text("LIVE", h.x - 20, h.y + h.h + 20, h.w + 40, 12, C.critical)
  end
  -- finished wires
  for _, w in ipairs(self.wires) do
    local pts = {}
    for _, p in ipairs(w.path) do pts[#pts + 1] = p[1]; pts[#pts + 1] = p[2] end
    T.set(C.ink); lg.setLineWidth(12); lg.line(pts)
    lg.setColor(COLORS[w.color]); lg.setLineWidth(7); lg.line(pts)
  end
  -- wire being dragged
  if self.drag and #self.drag.path >= 1 then
    local pts = {}
    for _, p in ipairs(self.drag.path) do pts[#pts + 1] = p[1]; pts[#pts + 1] = p[2] end
    pts[#pts + 1] = self.mx; pts[#pts + 1] = self.my
    if #pts >= 4 then
      T.set(C.ink); lg.setLineWidth(12); lg.line(pts)
      lg.setColor(COLORS[self.drag.cable.color]); lg.setLineWidth(7); lg.line(pts)
    end
  end
  lg.setLineWidth(1)
  for _, c in ipairs(self.cables) do
    T.set(C.ink); lg.rectangle("fill", c.x - 110, c.y - 11, 100, 22, 6, 6)
    lg.setColor(COLORS[c.color]); lg.rectangle("fill", c.x - 106, c.y - 7, 94, 14, 5, 5)
    -- frayed copper end
    T.set(T.hex("#E09A3C"))
    for k = -1, 1 do lg.line(c.x - 12, c.y, c.x + 4, c.y + k * 8) end
    T.circle(c.x, c.y, 10, c.done and C.good or COLORS[c.color], 3)
  end
  for _, s in ipairs(self.sockets) do
    T.box(s.x - 26, s.y - 26, 70, 52, C.metal, 8, 3)
    lg.setColor(COLORS[s.color]); lg.circle("fill", s.x, s.y, 16)
    T.set(C.ink); lg.circle("fill", s.x - 5, s.y, 3); lg.circle("fill", s.x + 5, s.y, 3)
    Base.sprite("hv_sign", s.x + 30, s.y - 30, 26)
  end
  if self.zap > 0 then
    lg.setColor(0.6, 0.9, 1, self.zap); lg.rectangle("fill", Base.AX, Base.AY, Base.AW, Base.AH)
    Base.text(self.lastProblem or "ZAP!", 440, 520, 400, 20, C.critical)
  end
  for i = 1, self.MAX_MISTAKES do
    T.circle(Base.AX + 30 + i * 30, Base.AY + 410, 10, i <= self.MAX_MISTAKES - self.mistakes and C.caution or C.critical, 2)
  end
end

------------------------------------------------------------------------------
-- Wattage Stabilizer: turn the AMPLITUDE and FREQUENCY dials until your wave
-- sits on top of the target wave; keep the wattage above 70%.
------------------------------------------------------------------------------
local Osc = Base.extend({
  system = "POWER SYSTEM - DISTRIBUTION UNIT", title = "Wattage Stabilizer",
  hint = "Drag the AMPLITUDE and FREQUENCY sliders until the two waves match. Keep wattage above 70%!",
  timeLimit = 40, GOOD = 70, HOLD = 1.5,
  SCREEN = { x = 300, y = 170, w = 680, h = 230 },
})
P.oscillo = Osc

function Osc:setup()
  self.amp = Base.Slider.new(420, 470, 360, 0.15, false, { 0.36, 0.9, 0.5, 1 }, "AMPLITUDE")
  self.freq = Base.Slider.new(420, 540, 360, 0.9, false, { 1, 0.85, 0.3, 1 }, "FREQUENCY")
  self.target = { 0.3 + self:rand() * 0.55, 0.2 + self:rand() * 0.6 }
  self.hold = 0
end
function Osc:wattage()
  local e = math.abs(self.amp.value - self.target[1]) + math.abs(self.freq.value - self.target[2])
  return Base.clamp(100 * (1 - e * 3), 0, 100)
end
function Osc:progress() return self.state == "won" and 1 or self:wattage() / 100 end

function Osc:update(dt)
  if not self:tick(dt) then return end
  if self:wattage() >= self.GOOD then
    self.hold = self.hold + dt
    if self.hold >= self.HOLD then self:win(string.format("Waves locked! Wattage steady at %d%%.", math.floor(self:wattage()))) end
  else self.hold = 0 end
end
function Osc:mousepressed(x, y) Base.mousepressed(self, x, y); if not self.amp:press(x, y) then self.freq:press(x, y) end end
function Osc:mousemoved(x, y) Base.mousemoved(self, x, y); self.amp:move(x, y); self.freq:move(x, y) end
function Osc:mousereleased(x, y) Base.mousereleased(self, x, y); self.amp:release(); self.freq:release() end
function Osc:keypressed(k)
  local s = 0.02
  if k == "up" then self.amp.value = Base.clamp(self.amp.value + s, 0, 1)
  elseif k == "down" then self.amp.value = Base.clamp(self.amp.value - s, 0, 1)
  elseif k == "right" then self.freq.value = Base.clamp(self.freq.value + s, 0, 1)
  elseif k == "left" then self.freq.value = Base.clamp(self.freq.value - s, 0, 1) end
end
function Osc:solve()
  self.amp.value, self.freq.value = self.target[1], self.target[2]
  self:update(self.HOLD + 0.01)
end

local function wave(sc, amp, freq, t)
  local pts = {}
  local a = 10 + amp * (sc.h / 2 - 16)
  local cycles = 1 + freq * 4
  for i = 0, 120 do
    local u = i / 120
    pts[#pts + 1] = sc.x + u * sc.w
    pts[#pts + 1] = sc.y + sc.h / 2 - math.sin((u * cycles + t * 0.5) * 2 * math.pi) * a
  end
  return pts
end

function Osc:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  local sc = self.SCREEN
  -- retro oscilloscope frame
  T.box(sc.x - 26, sc.y - 26, sc.w + 52, sc.h + 52, C.metal, 20, 4)
  T.set(T.hex("#062016")); lg.rectangle("fill", sc.x, sc.y, sc.w, sc.h, 10, 10)
  T.set(C.good, 0.15)
  for gx = sc.x, sc.x + sc.w, sc.w / 10 do lg.line(gx, sc.y, gx, sc.y + sc.h) end
  for gy = sc.y, sc.y + sc.h, sc.h / 6 do lg.line(sc.x, gy, sc.x + sc.w, gy) end
  lg.setLineWidth(4)
  T.set(C.caution, 0.8); lg.line(wave(sc, self.target[1], self.target[2], t))
  T.set(C.good); lg.line(wave(sc, self.amp.value, self.freq.value, t))
  lg.setLineWidth(1)
  Base.text("TARGET", sc.x + 10, sc.y + 8, 120, 13, C.caution, "left")
  Base.text("YOUR WAVE", sc.x + 10, sc.y + 26, 120, 13, C.good, "left")
  Base.drawSlider(self.amp)
  Base.drawSlider(self.freq)
  local w = self:wattage()
  Base.text("WATTAGE", 880, 450, 200, 15, C.cyanLight)
  Base.text(string.format("%d%%", math.floor(w)), 880, 470, 200, 40, w >= self.GOOD and C.good or C.critical)
  T.meter(900, 520, 160, 10, w / 100, w >= self.GOOD and C.good or C.critical)
  T.meter(900, 540, 160, 6, self.hold / self.HOLD, C.good)
end

return P
