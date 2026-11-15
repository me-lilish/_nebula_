--[[
  Tier 4 - FOOD SYSTEM mini-games
    seedtray : "Hydro-Tray Sorter"     (Hydroponic Garden) plant, water, harvest
    spectrum : "Photosynthesis Tuner"  (Grow-Light Timer)  match the light recipe
]]
local Base = require("src.puzzles.base")
local P = {}

------------------------------------------------------------------------------
-- Hydro-Tray Sorter: pick a tool, then click a tray slot.
--   seed pod -> empty slot, pipette -> planted slot, shears -> ripe crop
------------------------------------------------------------------------------
local Tray = Base.extend({
  system = "FOOD SYSTEM - HYDROPONICS", title = "Hydro-Tray Sorter",
  hint = "Pick a tool on the right, then click a tray slot: plant seeds, water them, snip ripe crops!",
  timeLimit = 55, SLOTS = 4, GROW_TIME = 1.6,
  TOOLS = {
    { id = "seed", sprite = "seed_pod", x = 1000, y = 230, w = 56 },
    { id = "water", sprite = "pipette", x = 1000, y = 350, w = 60 },
    { id = "shears", sprite = "shears", x = 1000, y = 470, w = 110 },
  },
  BASKET = { x = 150, y = 455, w = 180, h = 100 },
})
P.seedtray = Tray

function Tray:setup()
  self.slots = {}
  for i = 1, self.SLOTS do self.slots[i] = { x = 440 + (i - 1) * 135, y = 400, stage = "empty", grow = 0 } end
  self.tool = nil
  self.harvested = 0
  self.shake = {}
end
function Tray:progress()
  local score = 0
  local w = { empty = 0, seeded = 1, growing = 2, ripe = 3, done = 4 }
  for _, s in ipairs(self.slots) do score = score + w[s.stage] end
  return score / (4 * self.SLOTS)
end

function Tray:apply(i)
  local s = self.slots[i]
  local ok = (self.tool == "seed" and s.stage == "empty") or (self.tool == "water" and s.stage == "seeded")
    or (self.tool == "shears" and s.stage == "ripe")
  if not ok then self.shake[i] = 0.3; return false end
  if self.tool == "seed" then s.stage = "seeded"
  elseif self.tool == "water" then s.stage, s.grow = "growing", 0
  else
    s.stage = "done"
    self.harvested = self.harvested + 1
    if self.harvested >= self.SLOTS then self:win("Basket full of fresh crops - and the scraps go to compost!") end
  end
  return true
end

function Tray:update(dt)
  if not self:tick(dt) then return end
  for i, s in ipairs(self.slots) do
    if s.stage == "growing" then
      s.grow = s.grow + dt / self.GROW_TIME
      if s.grow >= 1 then s.grow, s.stage = 1, "ripe" end
    end
    if self.shake[i] then self.shake[i] = self.shake[i] - dt; if self.shake[i] <= 0 then self.shake[i] = nil end end
  end
end

function Tray:slotAt(x, y)
  for i, s in ipairs(self.slots) do
    if math.abs(x - s.x) < 60 and math.abs(y - s.y) < 110 then return i end
  end
end

function Tray:mousepressed(x, y)
  Base.mousepressed(self, x, y)
  for _, tool in ipairs(self.TOOLS) do
    if Base.dist(x, y, tool.x, tool.y) < 60 then self.tool = tool.id; self.dragFrom = { x, y }; return end
  end
  local i = self:slotAt(x, y)
  if i and self.tool then self:apply(i) end
end

function Tray:mousereleased(x, y)
  Base.mousereleased(self, x, y)
  local i = self:slotAt(x, y)
  -- dragging a tool onto a slot works too
  if i and self.tool and self.dragFrom and Base.dist(x, y, self.dragFrom[1], self.dragFrom[2]) > 40 then self:apply(i) end
  self.dragFrom = nil
end

function Tray:keypressed(k)
  if k == "1" then self.tool = "seed" elseif k == "2" then self.tool = "water" elseif k == "3" then self.tool = "shears" end
end

function Tray:solve()
  for _, tool in ipairs({ "seed", "water" }) do
    self.tool = tool
    for i = 1, self.SLOTS do self:apply(i) end
  end
  for _, s in ipairs(self.slots) do s.stage, s.grow = "ripe", 1 end
  self.tool = "shears"
  for i = 1, self.SLOTS do self:apply(i) end
end

function Tray:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  -- grow lights + tray
  lg.setBlendMode("add"); T.set(T.hex("#FF5FD2"), 0.12); lg.rectangle("fill", 370, 160, 540, 330, 12, 12); lg.setBlendMode("alpha")
  T.box(380, 168, 520, 16, C.metalDark, 6, 3)
  T.box(370, 470, 540, 40, C.metal, 10, 3)
  T.set(C.water, 0.5); lg.rectangle("fill", 380, 478, 520, 10, 4, 4)
  for i, s in ipairs(self.slots) do
    local sx = s.x + (self.shake[i] and math.sin(t * 60) * 5 or 0)
    T.box(sx - 46, 440, 92, 40, T.hex("#3B4774"), 8, 3)
    if s.stage == "seeded" then Base.sprite("seed_pod", sx, 410, 40)
    elseif s.stage == "growing" or s.stage == "ripe" then
      local g = 0.35 + 0.65 * s.grow
      Base.sprite("crop_plant", sx, 460 - 90 * g, 140 * g)
      if s.stage == "ripe" then Base.text("RIPE!", sx - 40, 250, 80, 14, C.good) end
    elseif s.stage == "done" then Base.text("picked", sx - 40, 420, 80, 13, C.metalShade) end
  end
  -- basket fills up
  local b = self.BASKET
  for k = 1, self.harvested do Base.sprite("crop_plant", b.x + 40 + (k - 1) * 40, b.y + 20, 70) end
  Base.sprite("basket", b.x + b.w / 2, b.y + b.h / 2 + 20, b.w)
  Base.text(string.format("HARVEST %d / %d", self.harvested, self.SLOTS), b.x, b.y + b.h + 20, b.w, 15, C.good)
  -- toolbar
  for k, tool in ipairs(self.TOOLS) do
    local sel = self.tool == tool.id
    T.set(sel and C.cyan or C.metalDark, sel and 0.35 or 0.25); lg.circle("fill", tool.x, tool.y, 58)
    T.set(sel and C.cyan or C.metalShade); lg.setLineWidth(3); lg.circle("line", tool.x, tool.y, 58); lg.setLineWidth(1)
    if not sel then Base.sprite(tool.sprite, tool.x, tool.y, tool.w) end
    Base.text(k .. "  " .. ({ seed = "SEED", water = "WATER", shears = "SNIP" })[tool.id], tool.x - 60, tool.y + 52, 120, 12, C.cyanLight)
  end
  if self.tool then
    local tool
    for _, tl in ipairs(self.TOOLS) do if tl.id == self.tool then tool = tl end end
    Base.sprite(tool.sprite, self.mx + 10, self.my + 10, tool.w, self.tool == "shears" and math.sin(t * 8) * 0.1 or 0)
  end
end

------------------------------------------------------------------------------
-- Photosynthesis Tuner: slide red and blue light until the leaves glow green
-- and hold it there.
------------------------------------------------------------------------------
local Tuner = Base.extend({
  system = "FOOD SYSTEM - GROW LIGHTS", title = "Photosynthesis Tuner",
  hint = "Drag the RED and BLUE light sliders until the leaves glow bright green, then hold it!",
  timeLimit = 35, GOOD = 0.85, HOLD = 1.5,
})
P.spectrum = Tuner

function Tuner:setup()
  self.red = Base.Slider.new(380, 480, 420, 0.1, false, { 1, 0.3, 0.35, 1 }, "RED")
  self.blue = Base.Slider.new(380, 545, 420, 0.9, false, { 0.3, 0.55, 1, 1 }, "BLUE")
  self.target = { 0.25 + self:rand() * 0.55, 0.2 + self:rand() * 0.5 }
  self.hold = 0
end
function Tuner:match()
  local e = math.abs(self.red.value - self.target[1]) + math.abs(self.blue.value - self.target[2])
  return Base.clamp(1 - e * 2.2, 0, 1)
end
function Tuner:progress() return self.state == "won" and 1 or self:match() * 0.8 + 0.2 * self.hold / self.HOLD end

function Tuner:update(dt)
  if not self:tick(dt) then return end
  if self:match() >= self.GOOD then
    self.hold = self.hold + dt
    if self.hold >= self.HOLD then self:win("Perfect light recipe! The plants grow at top speed.") end
  else
    self.hold = 0
  end
end
function Tuner:mousepressed(x, y) Base.mousepressed(self, x, y); if not self.red:press(x, y) then self.blue:press(x, y) end end
function Tuner:mousemoved(x, y) Base.mousemoved(self, x, y); self.red:move(x, y); self.blue:move(x, y) end
function Tuner:mousereleased(x, y) Base.mousereleased(self, x, y); self.red:release(); self.blue:release() end
function Tuner:keypressed(k)
  local step = 0.02
  if k == "left" then self.red.value = Base.clamp(self.red.value - step, 0, 1)
  elseif k == "right" then self.red.value = Base.clamp(self.red.value + step, 0, 1)
  elseif k == "down" then self.blue.value = Base.clamp(self.blue.value - step, 0, 1)
  elseif k == "up" then self.blue.value = Base.clamp(self.blue.value + step, 0, 1) end
end
function Tuner:solve()
  self.red.value, self.blue.value = self.target[1], self.target[2]
  self:update(self.HOLD + 0.01)
end

function Tuner:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  local m = self:match()
  -- light from the lamp: the mix of the two sliders
  local r, b = self.red.value, self.blue.value
  lg.setBlendMode("add")
  lg.setColor(r * 0.9, 0.15, b * 0.9, 0.35); lg.polygon("fill", 520, 175, 760, 175, 860, 430, 420, 430)
  lg.setBlendMode("alpha")
  T.box(500, 160, 280, 24, C.metalDark, 8, 3)
  Base.sprite("crop_plant", 640, 330, 230)
  -- leaves glow green when the recipe matches
  lg.setBlendMode("add"); lg.setColor(0.3, 1, 0.3, 0.5 * m * m); lg.circle("fill", 640, 290, 120 + 6 * math.sin(t * 4)); lg.setBlendMode("alpha")
  Base.drawSlider(self.red)
  Base.drawSlider(self.blue)
  -- growth meter
  T.meter(900, 260, 180, 14, m, m >= self.GOOD and C.good or C.caution)
  Base.text("LEAF GLOW", 900, 230, 180, 15, C.cyanLight)
  Base.text(m >= self.GOOD and "HOLD IT!" or (m > 0.5 and "Almost..." or "Keep tuning"), 900, 286, 180, 18,
    m >= self.GOOD and C.good or C.offWhite)
  T.meter(900, 330, 180, 8, self.hold / self.HOLD, C.good)
end

return P
