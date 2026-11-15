--[[
  Tier 5 - WASTE SYSTEM mini-games
    compost : "Leaves-to-Compost Toss"  (Composter)        sort leaves vs bolts
    salvage : "Machinery Disassembly"   (Machine Recycler) cut screws, pick parts
]]
local Base = require("src.puzzles.base")
local P = {}

local function drawLeaf(x, y, s, rot)
  local T = require("src.ui.theme")
  local lg = love.graphics
  lg.push(); lg.translate(x, y); lg.rotate(rot or 0)
  T.set(T.C.ink); lg.ellipse("fill", 0, 0, 30 * s + 4, 14 * s + 4)
  T.set(T.hex("#9C8B3C")); lg.ellipse("fill", 0, 0, 30 * s, 14 * s)
  T.set(T.hex("#6E7A2E")); lg.ellipse("fill", -6 * s, -2 * s, 18 * s, 7 * s)
  T.set(T.C.ink); lg.setLineWidth(3); lg.line(-30 * s, 0, 38 * s, 0); lg.setLineWidth(1)
  lg.pop()
end

local function drawBolt(x, y, s, rot)
  local T = require("src.ui.theme")
  local lg = love.graphics
  lg.push(); lg.translate(x, y); lg.rotate(rot or 0)
  T.set(T.C.ink); lg.rectangle("fill", -6 * s - 3, -34 * s, 12 * s + 6, 50 * s, 3, 3)
  T.set(T.C.metalShade); lg.rectangle("fill", -6 * s, -32 * s, 12 * s, 46 * s)
  T.set(T.C.metalDark); for k = 0, 4 do lg.rectangle("fill", -6 * s, -28 * s + k * 9 * s, 12 * s, 3 * s) end
  local hex = {}
  for k = 0, 5 do local a = k * math.pi / 3; hex[#hex + 1] = math.cos(a) * 20 * s; hex[#hex + 1] = 22 * s + math.sin(a) * 20 * s end
  T.set(T.C.ink); lg.setLineWidth(6); lg.polygon("line", hex); lg.setLineWidth(1)
  T.set(T.C.metal); lg.polygon("fill", hex)
  T.set(T.C.ink); lg.circle("fill", 0, 22 * s, 6 * s)
  lg.pop()
end
P.drawLeaf, P.drawBolt = drawLeaf, drawBolt

------------------------------------------------------------------------------
-- Leaves-to-Compost Toss
------------------------------------------------------------------------------
local Compost = Base.extend({
  system = "WASTE SYSTEM - COMPOST", title = "Leaves-to-Compost Toss",
  hint = "Drag dead LEAVES into the moving composter hatch. Drag BOLTS into the scrap bin - never into the composter!",
  timeLimit = 45, GOAL = 8, MAX_JAMS = 3, LIFE = 5, SPAWN = 0.9,
  SPOTS = { { 230, 330 }, { 330, 300 }, { 280, 410 }, { 380, 390 } },
  BIN = { x = 900, y = 470, w = 180, h = 110 },
})
P.compost = Compost

function Compost:setup()
  self.items, self.spawn, self.leaves, self.jams = {}, 0.2, 0, 0
  self.hatchX = 700
  self.held = nil
end
function Compost:progress() return self.leaves / self.GOAL end
function Compost:hatch() return { x = self.hatchX - 70, y = 230, w = 140, h = 110 } end

function Compost:update(dt)
  if not self:tick(dt) then return end
  self.hatchX = 720 + math.sin(self.time * 1.1) * 150
  self.spawn = self.spawn - dt
  if self.spawn <= 0 and #self.items < #self.SPOTS then
    local free
    for _, s in ipairs(self.SPOTS) do
      local used = false
      for _, it in ipairs(self.items) do if it.spot == s then used = true end end
      if not used then free = s; break end
    end
    if free then
      self.items[#self.items + 1] = { kind = self:rand() < 0.68 and "leaf" or "bolt", spot = free,
        x = free[1], y = free[2], age = 0, rot = self:rand() * 6 }
    end
    self.spawn = self.SPAWN
  end
  for i = #self.items, 1, -1 do
    local it = self.items[i]
    if it ~= self.held then
      it.age = it.age + dt
      if it.age > self.LIFE then table.remove(self.items, i) end
    end
  end
end

function Compost:mousepressed(x, y)
  Base.mousepressed(self, x, y)
  for _, it in ipairs(self.items) do
    if Base.dist(x, y, it.x, it.y) < 45 then self.held = it; return end
  end
end
function Compost:mousemoved(x, y)
  Base.mousemoved(self, x, y)
  if self.held then self.held.x, self.held.y = x, y end
end

function Compost:drop(it, x, y)
  local into = Base.inside(x, y, self:hatch())
  local bin = Base.inside(x, y, self.BIN)
  if into and it.kind == "leaf" then
    self.leaves = self.leaves + 1
  elseif into and it.kind == "bolt" then
    self.jams = self.jams + 1
    if self.jams >= self.MAX_JAMS then self:lose("Too many bolts - the composter jammed!") end
  elseif not (bin and it.kind == "bolt") then
    it.x, it.y = it.spot[1], it.spot[2] -- dropped elsewhere: back to the basket
    return
  end
  for i, o in ipairs(self.items) do if o == it then table.remove(self.items, i) break end end
  if self.leaves >= self.GOAL then self:win("Composter full! Those leaves will become fertilizer.") end
end

function Compost:mousereleased(x, y)
  Base.mousereleased(self, x, y)
  if self.held then local it = self.held; self.held = nil; self:drop(it, x, y) end
end

function Compost:solve()
  for _ = self.leaves + 1, self.GOAL do
    local it = { kind = "leaf", spot = self.SPOTS[1], x = 0, y = 0 }
    self.items[#self.items + 1] = it
    local h = self:hatch()
    self:drop(it, h.x + 10, h.y + 10)
  end
end

function Compost:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  Base.sprite("basket", 300, 400, 300)
  -- composter + hatch
  local h = self:hatch()
  Base.sprite("composter", self.hatchX, 330, 280)
  T.set(C.ink); lg.ellipse("fill", h.x + h.w / 2, h.y + 10, 66, 22)
  T.set(T.hex("#2B4A1E")); lg.ellipse("fill", h.x + h.w / 2, h.y + 10, 58, 16)
  Base.text("HATCH", h.x, h.y - 30, h.w, 14, C.good)
  -- scrap bin
  local b = self.BIN
  T.box(b.x, b.y, b.w, b.h, C.metalDark, 10, 3)
  Base.text("SCRAP BIN", b.x, b.y + 12, b.w, 15, C.caution)
  for _, it in ipairs(self.items) do
    local fade = it == self.held and 1 or math.max(0.3, 1 - math.max(0, it.age - self.LIFE + 1.5) / 1.5)
    lg.setColor(1, 1, 1, fade)
    if it.kind == "leaf" then drawLeaf(it.x, it.y, 1, it.rot) else drawBolt(it.x, it.y, 1, it.rot) end
  end
  Base.text(string.format("LEAVES  %d / %d", self.leaves, self.GOAL), 160, 520, 300, 18, C.good)
  for i = 1, self.MAX_JAMS do
    T.circle(560 + i * 32, 545, 11, i <= self.MAX_JAMS - self.jams and C.caution or C.critical, 2)
  end
  Base.text("JAM", 520, 538, 40, 13, C.caution, "left")
end

------------------------------------------------------------------------------
-- Machinery Disassembly: hold the plasma cutter on each screw, then pick
-- only the intact parts (gears + circuit boards). Burnt parts crumble.
------------------------------------------------------------------------------
local Salvage = Base.extend({
  system = "WASTE SYSTEM - SALVAGE", title = "Machinery Disassembly",
  hint = "HOLD the plasma cutter on each screw. Then click only the shiny, intact parts!",
  timeLimit = 50, CUT_TIME = 0.7, MAX_MISTAKES = 2,
  PANEL = { x = 360, y = 180, w = 500, h = 340 },
})
P.salvage = Salvage

function Salvage:setup()
  local p = self.PANEL
  self.screws = {
    { x = p.x + 30, y = p.y + 30 }, { x = p.x + p.w - 30, y = p.y + 30 },
    { x = p.x + 30, y = p.y + p.h - 30 }, { x = p.x + p.w - 30, y = p.y + p.h - 30 },
  }
  for _, s in ipairs(self.screws) do s.cut = 0 end
  local kinds = { "gear", "board", "gear", "burnt", "burnt" }
  for i = #kinds, 2, -1 do local j = self:rand(1, i); kinds[i], kinds[j] = kinds[j], kinds[i] end
  self.parts = {}
  for i, k in ipairs(kinds) do
    self.parts[i] = { kind = k, x = p.x + 80 + (i - 1) * 85, y = p.y + 140 + (i % 2) * 90, taken = false }
  end
  self.spares = 0
  self.open = 0
end
function Salvage:screwsLeft()
  local n = 0
  for _, s in ipairs(self.screws) do if s.cut < 1 then n = n + 1 end end
  return n
end
function Salvage:goodLeft()
  local n = 0
  for _, part in ipairs(self.parts) do if part.kind ~= "burnt" and not part.taken then n = n + 1 end end
  return n
end
function Salvage:progress() return (4 - self:screwsLeft()) / 8 + (3 - self:goodLeft()) / 6 end

function Salvage:update(dt)
  if not self:tick(dt) then return end
  if self.down and self:screwsLeft() > 0 then
    for _, s in ipairs(self.screws) do
      if s.cut < 1 and Base.dist(self.mx, self.my, s.x, s.y) < 30 then s.cut = math.min(1, s.cut + dt / self.CUT_TIME) end
    end
  end
  if self:screwsLeft() == 0 then self.open = math.min(1, self.open + dt * 2) end
end

function Salvage:mousepressed(x, y)
  Base.mousepressed(self, x, y)
  if self.open < 1 then return end
  for _, part in ipairs(self.parts) do
    if not part.taken and Base.dist(x, y, part.x, part.y) < 38 then
      part.taken = true
      if part.kind == "burnt" then
        self.mistakes = self.mistakes + 1
        if self.mistakes >= self.MAX_MISTAKES then self:lose("That part was burnt and crumbled. Try again!") end
      else
        self.spares = self.spares + 1
        if self:goodLeft() == 0 then self:win("All intact gears and boards saved as spare parts!") end
      end
      return
    end
  end
end

function Salvage:solve()
  for _, s in ipairs(self.screws) do s.cut = 1 end
  self.open = 1
  for _, part in ipairs(self.parts) do if part.kind ~= "burnt" then self:mousepressed(part.x, part.y) end end
end

local function drawGear(x, y, r, color)
  local T = require("src.ui.theme")
  local lg = love.graphics
  T.set(T.C.ink)
  for k = 0, 7 do
    local a = k * math.pi / 4
    lg.push(); lg.translate(x + math.cos(a) * r, y + math.sin(a) * r); lg.rotate(a)
    lg.rectangle("fill", -9, -9, 18, 18, 3, 3); lg.pop()
  end
  lg.circle("fill", x, y, r + 3)
  T.set(color)
  for k = 0, 7 do
    local a = k * math.pi / 4
    lg.push(); lg.translate(x + math.cos(a) * r, y + math.sin(a) * r); lg.rotate(a)
    lg.rectangle("fill", -6, -6, 12, 12, 2, 2); lg.pop()
  end
  lg.circle("fill", x, y, r)
  T.set(T.C.ink); lg.circle("fill", x, y, r * 0.35)
end

local function drawBoard(x, y, burnt)
  local T = require("src.ui.theme")
  local lg = love.graphics
  T.box(x - 34, y - 24, 68, 48, burnt and T.hex("#3A3028") or T.hex("#2E9E57"), 4, 3)
  T.set(burnt and T.hex("#1A1410") or T.hex("#F2C744"))
  for k = 0, 3 do lg.rectangle("fill", x - 26 + k * 15, y - 16, 4, 32) end
  T.set(T.C.ink); lg.rectangle("fill", x - 10, y - 8, 20, 16)
end

function Salvage:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  local p = self.PANEL
  -- machine insides
  T.box(p.x, p.y, p.w, p.h, T.hex("#2A2F4D"), 12, 3)
  for i, part in ipairs(self.parts) do
    if not part.taken then
      if part.kind == "gear" then drawGear(part.x, part.y, 26, C.metal)
      elseif part.kind == "board" then drawBoard(part.x, part.y, false)
      else
        if i % 2 == 0 then drawGear(part.x, part.y, 26, T.hex("#3A2E26")) else drawBoard(part.x, part.y, true) end
        lg.setColor(0.4, 0.4, 0.4, 0.6); lg.circle("fill", part.x + 10, part.y - 30 - (t * 20 % 20), 8)
      end
    end
  end
  -- damaged casing panel slides away when all screws are cut
  if self.open < 1 then
    local ox = self.open * 600
    T.box(p.x + ox, p.y, p.w, p.h, C.metalShade, 12, 4)
    T.set(C.metalDark); for k = 1, 4 do lg.line(p.x + ox + 60 + k * 80, p.y + 40, p.x + ox + 20 + k * 80, p.y + p.h - 40) end
    T.set(C.caution); lg.rectangle("fill", p.x + ox + 160, p.y + p.h / 2 - 20, 180, 40, 6, 6)
    Base.text("DAMAGED", p.x + ox + 160, p.y + p.h / 2 - 12, 180, 18, C.ink)
    for _, s in ipairs(self.screws) do
      if s.cut < 1 then
        T.circle(s.x + ox, s.y, 14, C.metal, 3)
        T.set(C.ink); lg.setLineWidth(3); lg.line(s.x + ox - 8, s.y, s.x + ox + 8, s.y); lg.setLineWidth(1)
        if s.cut > 0 then T.set(C.danger); lg.arc("line", "open", s.x + ox, s.y, 22, -math.pi / 2, -math.pi / 2 + s.cut * 2 * math.pi) end
      end
    end
  end
  -- spare-parts tray
  T.box(920, 200, 170, 300, T.hex("#1B2140"), 10, 3)
  Base.text("SPARE PARTS", 920, 210, 170, 15, C.good)
  for k = 1, self.spares do drawGear(1005, 230 + k * 70, 22, C.metal) end
  for i = 1, self.MAX_MISTAKES do
    T.circle(Base.AX + 30 + i * 30, Base.AY + 410, 10, i <= self.MAX_MISTAKES - self.mistakes and C.caution or C.critical, 2)
  end
  -- plasma cutter tool
  local cutting = self.down and self:screwsLeft() > 0
  lg.push(); lg.translate(self.mx, self.my); lg.rotate(-0.6)
  T.box(8, -12, 90, 24, C.metal, 8, 3)
  T.box(30, 10, 22, 40, C.metalDark, 6, 3)
  T.box(-10, -6, 22, 12, C.caution, 3, 2)
  lg.pop()
  if cutting then
    lg.setBlendMode("add")
    for k = 1, 6 do
      lg.setColor(1, 0.6 + 0.4 * math.random(), 0.2, 0.9)
      lg.line(self.mx, self.my, self.mx + (math.random() - 0.5) * 50, self.my + math.random() * 40)
    end
    lg.setColor(0.4, 0.9, 1, 0.8); lg.circle("fill", self.mx, self.my, 6 + math.sin(t * 40) * 2)
    lg.setBlendMode("alpha")
  end
end

return P
