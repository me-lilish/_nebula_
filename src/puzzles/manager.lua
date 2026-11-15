--[[
  PuzzleManager
  =============
  Opens one mini-game at a time over the station. While a puzzle is open the
  room pauses its life-support simulation; input is routed to the puzzle.
  When the puzzle ends (won / lost / left with Esc) the manager calls
  onDone(won, puzzle, cancelled) so the room can apply the system effect
  (the station's action) and progress the mission.

    pm = PuzzleManager.new()
    pm:start("pipes", { ls = ls }, function(won, p) ... end)
    pm:update(dt); pm:mousepressed(x, y); pm:draw(t)
]]
local Base = require("src.puzzles.base")

local PuzzleManager = {}
PuzzleManager.__index = PuzzleManager

PuzzleManager.RESULT_SECONDS = 1.8  -- the result card closes by itself after this

-- id -> puzzle class (each tier module returns { id = class, ... })
PuzzleManager.REGISTRY = {}
for _, mod in ipairs({ "tier1", "tier2", "tier3", "tier4", "tier5", "tier6", "tier7", "tier8" }) do
  for id, cls in pairs(require("src.puzzles." .. mod)) do
    if type(cls) == "table" and cls.title then -- skip helper functions
      cls.id = id
      PuzzleManager.REGISTRY[id] = cls
    end
  end
end

function PuzzleManager.new()
  return setmetatable({ active = nil }, PuzzleManager)
end

function PuzzleManager:isOpen() return self.active ~= nil end

function PuzzleManager:start(id, opts, onDone)
  local cls = PuzzleManager.REGISTRY[id]
  assert(cls, "unknown puzzle " .. tostring(id))
  self.active = Base.create(cls, opts)
  self.onDone = onDone
  return self.active
end

function PuzzleManager:_finish(cancelled)
  local p, done = self.active, self.onDone
  self.active, self.onDone = nil, nil
  if done then done(p.state == "won", p, cancelled) end
end

function PuzzleManager:update(dt)
  local p = self.active
  if not p then return end
  p:update(dt)
  if p.state ~= "play" and p.after >= PuzzleManager.RESULT_SECONDS then self:_finish(false) end
end

function PuzzleManager:mousepressed(x, y, button)
  local p = self.active
  if not p or button ~= 1 then return end
  if p.state ~= "play" then
    if p.after > 0.3 then self:_finish(false) end
    return
  end
  p:mousepressed(x, y)
end

function PuzzleManager:mousereleased(x, y, button)
  local p = self.active
  if p and button == 1 and p.state == "play" then p:mousereleased(x, y) end
end

function PuzzleManager:mousemoved(x, y)
  local p = self.active
  if p and p.state == "play" then p:mousemoved(x, y) end
end

function PuzzleManager:keypressed(key)
  local p = self.active
  if not p then return end
  if key == "escape" then
    if p.state == "play" then p:lose("You left the puzzle.") end
    self:_finish(true)
    return
  end
  if p.state ~= "play" then
    if (key == "return" or key == "space") and p.after > 0.3 then self:_finish(false) end
    return
  end
  p:keypressed(key)
end

function PuzzleManager:draw(t)
  local p = self.active
  if not p then return end
  love.graphics.push("all")
  Base.drawFrame(p, t)
  p:draw(t)
  Base.drawResult(p, t)
  love.graphics.pop()
end

return PuzzleManager
