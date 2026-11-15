--[[
  Tier 3 - WATER SYSTEM mini-games
    pipes  : "Hydro-Flow Reconnect"      (Water Recycler) rotate pipes to connect
    valves : "Gallon Gauge Stabilizer"   (Tank Valves)    fill both tanks to 100%
]]
local Base = require("src.puzzles.base")
local P = {}

------------------------------------------------------------------------------
-- Hydro-Flow Reconnect
--   directions 1 N, 2 E, 3 S, 4 W. A tile is { kind, rot } and opens the
--   directions of its base shape turned clockwise `rot` times.
------------------------------------------------------------------------------
local DX, DY = { 0, 1, 0, -1 }, { -1, 0, 1, 0 }
local function opposite(d) return (d + 1) % 4 + 1 end

local SHAPES = {
  straight = { false, true, false, true },  -- E W
  elbow = { true, true, false, false },     -- N E
  tee = { true, true, false, true },        -- N E W
}

local Pipes = Base.extend({
  system = "WATER SYSTEM - PLUMBING", title = "Hydro-Flow Reconnect",
  hint = "Click pipes to turn them. Connect the blue intake to the storage tank!",
  timeLimit = 60, COLS = 6, ROWS = 4, TILE = 92,
})
P.pipes = Pipes
Pipes.SHAPES = SHAPES

function Pipes.opens(tile, dir)
  local base = SHAPES[tile.kind]
  local i = ((dir - 1 - tile.rot) % 4) + 1
  return base[i]
end

function Pipes:setup()
  self.ox = 640 - self.COLS * self.TILE / 2
  self.oy = 170
  self.inRow = self:rand(1, self.ROWS)
  -- random path from the left edge to the right edge (no revisits)
  local path, seen = {}, {}
  local c, r = 1, self.inRow
  local cameFrom = 4 -- entered from the west
  while true do
    seen[c .. "," .. r] = true
    local options = {}
    if c == self.COLS then options = { 2 }
    else
      options[#options + 1] = 2
      if r > 1 and not seen[c .. "," .. (r - 1)] and cameFrom ~= 1 then options[#options + 1] = 1 end
      if r < self.ROWS and not seen[c .. "," .. (r + 1)] and cameFrom ~= 3 then options[#options + 1] = 3 end
    end
    local out = options[self:rand(1, #options)]
    path[#path + 1] = { c = c, r = r, a = cameFrom, b = out }
    if c == self.COLS and out == 2 then break end
    c, r = c + DX[out], r + DY[out]
    cameFrom = opposite(out)
  end
  self.outRow = path[#path].r
  self.path = path
  self.grid = {}
  local kinds = { "straight", "elbow", "tee" }
  for y = 1, self.ROWS do
    self.grid[y] = {}
    for x = 1, self.COLS do self.grid[y][x] = { kind = kinds[self:rand(1, 3)], rot = self:rand(0, 3) } end
  end
  for _, s in ipairs(path) do
    local straight = (s.a == opposite(s.b))
    local tile = { kind = straight and "straight" or "elbow" }
    -- find the rotation that opens a and b
    for rot = 0, 3 do
      tile.rot = rot
      if Pipes.opens(tile, s.a) and Pipes.opens(tile, s.b) then s.solution = rot; break end
    end
    tile.rot = (s.solution + self:rand(1, 3)) % 4 -- scrambled
    self.grid[s.r][s.c] = tile
  end
  self:flow()
end

-- Water flood-fill from the intake; marks wet tiles, returns connected?
function Pipes:flow()
  self.wet = {}
  local start = self.grid[self.inRow][1]
  if not Pipes.opens(start, 4) then self.connected = false; return false end
  local queue, head = { { 1, self.inRow } }, 1
  self.wet[1 .. "," .. self.inRow] = true
  local reached = false
  while head <= #queue do
    local x, y = queue[head][1], queue[head][2]; head = head + 1
    local t = self.grid[y][x]
    if x == self.COLS and y == self.outRow and Pipes.opens(t, 2) then reached = true end
    for d = 1, 4 do
      if Pipes.opens(t, d) then
        local nx, ny = x + DX[d], y + DY[d]
        local n = self.grid[ny] and self.grid[ny][nx]
        if n and Pipes.opens(n, opposite(d)) and not self.wet[nx .. "," .. ny] then
          self.wet[nx .. "," .. ny] = true
          queue[#queue + 1] = { nx, ny }
        end
      end
    end
  end
  self.connected = reached
  if reached then self:win("Water flows from the intake to the storage tank - no leaks!") end
  return reached
end

function Pipes:progress()
  local n = 0
  for _ in pairs(self.wet or {}) do n = n + 1 end
  return self.connected and 1 or math.min(0.95, n / #self.path)
end

function Pipes:tileAt(x, y)
  local c = math.floor((x - self.ox) / self.TILE) + 1
  local r = math.floor((y - self.oy) / self.TILE) + 1
  if c >= 1 and c <= self.COLS and r >= 1 and r <= self.ROWS then return c, r end
end

function Pipes:mousepressed(x, y)
  Base.mousepressed(self, x, y)
  local c, r = self:tileAt(x, y)
  if c then
    local t = self.grid[r][c]
    t.rot = (t.rot + 1) % 4
    t.spin = 1
    self:flow()
  end
end

function Pipes:update(dt)
  if not self:tick(dt) then return end
  for y = 1, self.ROWS do for x = 1, self.COLS do
    local t = self.grid[y][x]
    if t.spin then t.spin = t.spin - dt * 6; if t.spin <= 0 then t.spin = nil end end
  end end
end

function Pipes:solve()
  for _, s in ipairs(self.path) do self.grid[s.r][s.c].rot = s.solution end
  self:flow()
end

local function drawElbow(cx, cy, size, rot, wet)
  local T = require("src.ui.theme")
  local lg = love.graphics
  lg.push(); lg.translate(cx, cy); lg.rotate(rot * math.pi / 2)
  local h = size / 2
  -- arc from the north edge to the east edge (centre at the NE corner)
  for _, layer in ipairs({ { 34, T.C.ink }, { 26, T.C.offWhite }, { 7, wet and T.C.water or T.hex("#2F7BE0") } }) do
    T.set(layer[2]); lg.setLineWidth(layer[1])
    lg.arc("line", "open", h, -h, h, math.pi / 2, math.pi, 16)
  end
  lg.setLineWidth(1)
  for _, p in ipairs({ { 0, -h + 6, 34, 10 }, { h - 6, 0, 10, 34 } }) do
    T.set(T.C.ink); lg.rectangle("fill", p[1] - p[3] / 2 - 3, p[2] - p[4] / 2 - 3, p[3] + 6, p[4] + 6, 4, 4)
    T.set(T.C.metal); lg.rectangle("fill", p[1] - p[3] / 2, p[2] - p[4] / 2, p[3], p[4], 3, 3)
  end
  lg.pop()
end

function Pipes:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  local S = self.TILE
  T.set(T.hex("#1A2142")); lg.rectangle("fill", self.ox - 10, self.oy - 10, self.COLS * S + 20, self.ROWS * S + 20, 12, 12)
  for y = 1, self.ROWS do
    for x = 1, self.COLS do
      local tile = self.grid[y][x]
      local cx, cy = self.ox + (x - 0.5) * S, self.oy + (y - 0.5) * S
      local wet = self.wet[x .. "," .. y]
      T.set(wet and T.hex("#1F4D8C") or T.hex("#262D55")); lg.rectangle("fill", cx - S / 2 + 3, cy - S / 2 + 3, S - 6, S - 6, 8, 8)
      local rot = tile.rot - (tile.spin or 0)
      if tile.kind == "straight" then
        Base.sprite("pipe_straight", cx, cy, S, rot * math.pi / 2)
      elseif tile.kind == "tee" then
        -- the art opens W, E and N... its stem points up
        Base.sprite("pipe_tee", cx, cy, S * 0.98, rot * math.pi / 2)
      else
        drawElbow(cx, cy, S, rot, wet)
      end
      if wet then
        lg.setBlendMode("add"); T.set(C.water, 0.25); lg.rectangle("fill", cx - S / 2 + 3, cy - S / 2 + 3, S - 6, S - 6, 8, 8); lg.setBlendMode("alpha")
      end
    end
  end
  -- intake (left) and storage tank (right)
  local iy = self.oy + (self.inRow - 0.5) * S
  T.box(self.ox - 120, iy - 40, 90, 80, C.water, 12, 3)
  Base.text("INTAKE", self.ox - 120, iy - 8, 90, 15, C.ink)
  local ty = self.oy + (self.outRow - 0.5) * S
  Base.sprite("water_tank", self.ox + self.COLS * S + 70, ty, 100)
  Base.text(self.connected and "FULL!" or "TANK", self.ox + self.COLS * S + 20, ty + 72, 100, 15, self.connected and C.good or C.cyanLight)
  if not self.connected then
    for k = 0, 2 do
      T.set(C.water, 0.8); lg.circle("fill", self.ox - 30, iy + 30 + ((t * 60 + k * 20) % 50), 4)
    end
  end
end

------------------------------------------------------------------------------
-- Gallon Gauge Stabilizer: open and close the wheels so both tanks stop at
-- 100% (green band) without overflowing into the red.
------------------------------------------------------------------------------
local Valves = Base.extend({
  system = "WATER SYSTEM - TANKS", title = "Gallon Gauge Stabilizer",
  hint = "Click a wheel to open / close it. Fill BOTH tanks into the green band, then close all wheels!",
  timeLimit = 45, LO = 95, HI = 105, OVERFLOW = 112,
  -- litres per second each open wheel adds to tank A / tank B
  FLOW = { { 14, 0 }, { 0, 14 }, { 5, 5 } },
  WHEELS = { { x = 440, y = 500 }, { x = 640, y = 500 }, { x = 840, y = 500 } },
})
P.valves = Valves

function Valves:setup()
  self.level = { 30 + self:rand() * 25, 30 + self:rand() * 25 }
  self.open = { false, false, false }
  self.spin = { 0, 0, 0 }
end
function Valves:progress()
  local a = math.min(1, self.level[1] / 100)
  local b = math.min(1, self.level[2] / 100)
  return (a + b) / 2
end
function Valves:inBand(i) return self.level[i] >= self.LO and self.level[i] <= self.HI end
function Valves:allClosed() return not (self.open[1] or self.open[2] or self.open[3]) end

function Valves:check()
  for i = 1, 2 do
    if self.level[i] > self.OVERFLOW then self:lose("Overflow! Water spilled past the red line."); return end
  end
  if self:allClosed() and self:inBand(1) and self:inBand(2) then
    self:win("Both tanks are full and steady. Perfect pressure!")
  end
end

function Valves:update(dt)
  if not self:tick(dt) then return end
  for w = 1, 3 do
    if self.open[w] then
      self.level[1] = self.level[1] + self.FLOW[w][1] * dt
      self.level[2] = self.level[2] + self.FLOW[w][2] * dt
      self.spin[w] = self.spin[w] + dt * 6
    end
  end
  self:check()
end

function Valves:toggle(w)
  self.open[w] = not self.open[w]
  self:check()
end

function Valves:mousepressed(x, y)
  Base.mousepressed(self, x, y)
  for w, p in ipairs(self.WHEELS) do
    if Base.dist(x, y, p.x, p.y) < 70 then self:toggle(w) end
  end
end
function Valves:keypressed(k)
  if k == "1" or k == "2" or k == "3" then self:toggle(tonumber(k)) end
end
function Valves:solve()
  self.open = { true, false, false }; self.level = { 100, 100 }; self:toggle(1)
end

local function drawTank(x, y, w, h, level, lo, hi, label, t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  T.set(C.ink); lg.rectangle("fill", x - 5, y - 5, w + 10, h + 10, 18, 18)
  T.set(T.hex("#1C2A4A")); lg.rectangle("fill", x, y, w, h, 14, 14)
  local scale = h / 120
  local lh = math.min(h, level * scale)
  T.set(level > hi and C.critical or C.water); lg.rectangle("fill", x, y + h - lh, w, lh, 14, 14)
  T.set(C.white, 0.35); lg.rectangle("fill", x + 2, y + h - lh, w - 4, 5 + math.sin(t * 4) * 2)
  T.set(C.good, 0.35); lg.rectangle("fill", x, y + h - hi * scale, w, (hi - lo) * scale)
  T.set(C.critical, 0.25); lg.rectangle("fill", x, y, w, h - 112 * scale, 14, 14)
  T.set(C.white, 0.3); lg.rectangle("fill", x + 10, y + 10, 8, h - 20, 4, 4)
  Base.text(label, x, y - 30, w, 16, C.cyanLight)
  Base.text(string.format("%d%%", math.floor(level + 0.5)), x, y + h / 2 - 14, w, 26, C.white)
end

function Valves:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  drawTank(300, 175, 130, 225, self.level[1], self.LO, self.HI, "TANK A", t)
  drawTank(850, 175, 130, 225, self.level[2], self.LO, self.HI, "TANK B", t)
  Base.sprite("pressure_gauge", 640, 250, 150)
  local open = (self.open[1] and 1 or 0) + (self.open[2] and 1 or 0) + (self.open[3] and 1 or 0)
  Base.text("FLOW: " .. ({ "CLOSED", "LOW", "MEDIUM", "HIGH" })[open + 1], 540, 340, 200, 16, open == 0 and C.good or C.caution)
  -- pipes from wheels to tanks
  T.set(C.ink); lg.setLineWidth(12)
  lg.line(440, 450, 440, 420, 365, 420, 365, 400); lg.line(640, 450, 640, 430, 915, 430, 915, 400)
  lg.line(840, 450, 840, 440, 380, 440); lg.line(840, 440, 900, 440)
  T.set(C.metal); lg.setLineWidth(6)
  lg.line(440, 450, 440, 420, 365, 420, 365, 400); lg.line(640, 450, 640, 430, 915, 430, 915, 400)
  lg.line(840, 450, 840, 440, 380, 440); lg.line(840, 440, 900, 440)
  lg.setLineWidth(1)
  for w, p in ipairs(self.WHEELS) do
    Base.sprite("valve_wheel", p.x, p.y, 110, self.spin[w])
    Base.text(self.open[w] and "OPEN" or "closed", p.x - 60, p.y + 60, 120, 15, self.open[w] and C.caution or C.metalShade)
    Base.text(({ "A", "B", "A + B" })[w], p.x - 60, p.y - 80, 120, 14, C.cyanLight)
  end
end

return P
