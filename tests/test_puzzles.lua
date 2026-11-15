-- Mini-game logic tests (plain Lua, no Love2D): every puzzle can be won
-- and lost, timers run out, sliders stay in bounds, hit boxes work, and
-- the PuzzleManager reports results.
-- Run from the repository root:  lua tests/test_puzzles.lua

package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq = T.test, T.eq
local Base = require("src.puzzles.base")
local PM = require("src.puzzles.manager")

math.randomseed(42)
local function new(id, opts) return Base.create(PM.REGISTRY[id], opts) end
local function run(p, seconds) for _ = 1, math.floor(seconds / 0.05 + 0.5) do p:update(0.05) end end

local ALL = { "sheep", "oven", "scrub", "brush", "hepa", "pipes", "valves", "seedtray", "spectrum",
  "compost", "salvage", "chemmix", "gasmix", "breaker", "oscillo", "excavate", "armor" }

test("all 17 mini-games are registered and can be solved", function()
  for _, id in ipairs(ALL) do
    assert(PM.REGISTRY[id], "missing puzzle " .. id)
    for seed = 1, 5 do
      math.randomseed(seed)
      local p = new(id)
      p:update(0.05)
      p:solve()
      if p.state ~= "won" then error(id .. " not solved (seed " .. seed .. "): " .. tostring(p.result)) end
    end
  end
end)

test("timed puzzles are lost when the timer runs out", function()
  for _, id in ipairs(ALL) do
    local p = new(id)
    if p.timeLimit and id ~= "valves" then
      run(p, p.timeLimit + 1)
      if p.state ~= "lost" then error(id .. " should time out, state " .. p.state) end
    end
  end
end)

test("sheep: counting at the fence works, mistimed clicks lose focus", function()
  local p = new("sheep")
  p.sheep = { { x = p.FENCE_X } }; eq(p:count(), true); eq(p.counted, 1)
  for _ = 1, p.MAX_MISSES do p:count() end
  eq(p.state, "lost")
end)

test("oven: too early is frozen, too late is burnt, green is perfect", function()
  local p = new("oven"); p.heat = 5; p:pull(); eq(p.state, "lost"); eq(p.pulled, "raw")
  p = new("oven"); local lo, hi = p:zone(); p.heat = hi + 1; p:pull(); eq(p.pulled, "burnt")
  p = new("oven"); run(p, 20); eq(p.state, "lost"); eq(p.pulled, "burnt")
  p = new("oven"); lo, hi = p:zone(); p.heat = (lo + hi) / 2; p:pull(); eq(p.state, "won")
end)

test("scrub + brush: wiping where the mouse is cleans only there", function()
  local p = new("scrub")
  p:mousepressed(p.MIRROR.x + 10, p.MIRROR.y + 10)
  for k = 1, 30 do p:mousemoved(p.MIRROR.x + 10 + k, p.MIRROR.y + 10) end
  assert(p:cleanliness() > 0 and p:cleanliness() < 0.5)
  local b = new("brush")
  b:mousepressed(-500, -500); run(b, 2); eq(b:left(), #b.clumps, "brushing thin air does nothing")
end)

test("hepa: the steps must happen in order and a misaligned lock is a mistake", function()
  local p = new("hepa")
  p:mousepressed(p.SHELF.x + 20, p.SHELF.y + 20); p:mousereleased(p.HOUSING.x + 20, p.HOUSING.y + 20)
  eq(p.step, "pull", "cannot insert before pulling the old filter")
  p:mousepressed(p.HOUSING.x + 20, p.HOUSING.y + 20); p:mousereleased(p.BIN.x + 20, p.BIN.y + 20)
  eq(p.step, "clear")
  for _, d in ipairs(p.dust) do p:mousepressed(d.x, d.y) end
  eq(p.step, "insert")
  p:mousepressed(p.SHELF.x + 20, p.SHELF.y + 20); p:mousereleased(p.HOUSING.x + 20, p.HOUSING.y + 20)
  eq(p.step, "align")
  p.angle = 90; p:lock(); eq(p.mistakes, 1)
  p.angle = 5; p:lock(); eq(p.state, "won", "5 degrees off is close enough")
end)

test("pipes: every generated level is solvable and turning a tile rotates it", function()
  for seed = 1, 30 do
    math.randomseed(seed)
    local p = new("pipes")
    p:solve(); eq(p.state, "won")
  end
  local p = new("pipes")
  local rot = p.grid[1][1].rot
  p:mousepressed(p.ox + 5, p.oy + 5); eq(p.grid[1][1].rot, (rot + 1) % 4)
end)

test("valves: overflow loses, both tanks at 100 with wheels closed wins", function()
  local p = new("valves")
  p:toggle(1); run(p, 10); eq(p.state, "lost")
  p = new("valves"); p.level = { 99, 101 }; p:check(); eq(p.state, "won")
end)

test("sliders stay between 0 and 1 and only grab near the track", function()
  local s = Base.Slider.new(100, 200, 300, 0.5, false)
  eq(s:press(100, 400), false)
  eq(s:press(250, 200), true); s:move(-1000, 200); eq(s.value, 0); s:move(5000, 200); eq(s.value, 1)
  local v = Base.Slider.new(100, 100, 200, 0.5, true)
  eq(v:press(100, 150), true); v:move(100, -900); eq(v.value, 1); v:move(100, 900); eq(v.value, 0)
end)

test("spectrum + gasmix + oscillo: matching must be held, not just touched", function()
  local p = new("spectrum"); p.red.value, p.blue.value = p.target[1], p.target[2]
  p:update(0.5); eq(p.state, "play"); run(p, 1.2); eq(p.state, "won")
  local g = new("gasmix"); g.o2.value, g.n2.value = 0.5, 0.5; run(g, 3); eq(g.state, "play")
  local o = new("oscillo"); o.amp.value, o.freq.value = o.target[1], o.target[2]; run(o, 2); eq(o.state, "won")
end)

test("seed tray: tools only work on the right stage", function()
  local p = new("seedtray")
  p.tool = "shears"; eq(p:apply(1), false)
  p.tool = "seed"; eq(p:apply(1), true); eq(p.slots[1].stage, "seeded")
  p.tool = "water"; eq(p:apply(1), true); run(p, 2); eq(p.slots[1].stage, "ripe")
  p.tool = "shears"; eq(p:apply(1), true); eq(p.harvested, 1)
end)

test("compost: bolts in the hatch jam it, bolts in the bin are fine", function()
  local p = new("compost")
  local h = p:hatch()
  for _ = 1, 3 do
    local it = { kind = "bolt", spot = p.SPOTS[1], x = 0, y = 0 }; p.items[#p.items + 1] = it
    p:drop(it, h.x + 5, h.y + 5)
  end
  eq(p.state, "lost")
  p = new("compost")
  local it = { kind = "bolt", spot = p.SPOTS[1], x = 0, y = 0 }; p.items[#p.items + 1] = it
  p:drop(it, p.BIN.x + 5, p.BIN.y + 5); eq(p.jams, 0); eq(#p.items, 0)
end)

test("salvage, chemmix, breaker: mistakes count up to a loss", function()
  local s = new("salvage")
  for _, sc in ipairs(s.screws) do sc.cut = 1 end; s.open = 1
  for _, part in ipairs(s.parts) do if part.kind == "burnt" then s:mousepressed(part.x, part.y) end end
  eq(s.state, "lost")
  local c = new("chemmix")
  local wrong = c.sequence[1] == "B" and "Y" or "B"
  for _ = 1, 3 do c:load(wrong) end
  eq(c.state, "lost")
  local b = new("breaker")
  local h = b.hazards[1]
  eq(b:pathHitsHazard({ { h.x - 10, h.y + 10 }, { h.x + h.w + 10, h.y + 10 } }), true)
  eq(b:pathHitsHazard({ { h.x - 10, h.y - 30 }, { h.x + h.w + 10, h.y - 30 } }), false)
end)

test("excavate: dumping off the chute spills; armor strikes cost hull", function()
  local d = new("excavate")
  d.clawX = 300; d:act(); eq(d.full, true); d.drop = nil
  d.clawX = 800; d:act(); eq(d.full, false); eq(d.units, 0)
  local a = new("armor", { timeLimit = 200 })
  run(a, 60)
  eq(a.state, "lost")
end)

test("PuzzleManager pauses on a puzzle and reports the result", function()
  local pm = PM.new()
  local result
  pm:start("oven", {}, function(won) result = won end)
  eq(pm:isOpen(), true)
  pm.active:solve()
  pm:update(PM.RESULT_SECONDS + 0.1)
  eq(pm:isOpen(), false); eq(result, true)
  pm:start("sheep", {}, function(won, p, cancelled) result = { won, cancelled } end)
  pm:keypressed("escape")
  eq(result[1], false); eq(result[2], true)
end)

test("in the room: a station opens its mini-game, the station is paused, winning runs it", function()
  local Room = require("src.room_scene")
  local r = Room.new({ isDown = function() return false end, puzzles = true })
  local m = r:machineById("oxygen")
  r.vulcan.x, r.vulcan.y = r:spotNear(m)
  local o2 = r.air.oxygenPercent
  r:clickStation(m)
  eq(r.puzzles:isOpen(), true); eq(r.puzzles.active.id, "gasmix")
  local clock = r.ls.missionTime
  r:update(1); eq(r.ls.missionTime, clock, "life support paused during the puzzle")
  r.puzzles.active:solve()
  r:update(PM.RESULT_SECONDS + 0.1)
  eq(r.puzzles:isOpen(), false)
  assert(r.air.oxygenPercent > o2, "winning ran the Oxygen Generator")
  eq(r.message, "Great! Fresh oxygen is flowing.")
  -- losing (or leaving) does nothing to the station
  r:clickStation(m)
  r.puzzles.active:lose("x"); r:update(PM.RESULT_SECONDS + 0.1)
  assert(r.message:find("Not quite"), r.message)
  r:clickStation(m); r:keypressed("escape")
  eq(r.puzzles:isOpen(), false)
end)

test("a station that cannot run explains why instead of opening a puzzle", function()
  local Room = require("src.room_scene")
  local r = Room.new({ isDown = function() return false end, puzzles = true })
  local m = r:machineById("greenhouse")
  r.vulcan.x, r.vulcan.y = r:spotNear(m)
  r:clickStation(m)
  eq(r.puzzles:isOpen(), false)
  eq(r.message, "The plants are still growing. Come back later!")
end)

test("every puzzle station in the room uses a registered mini-game", function()
  local Room = require("src.room_scene")
  local r = Room.new({ isDown = function() return false end })
  local n = 0
  for _, m in ipairs(r.machines) do
    if m.puzzle then n = n + 1; assert(PM.REGISTRY[m.puzzle], m.id .. " -> " .. m.puzzle) end
  end
  eq(n, 17)
end)

T.finish()
