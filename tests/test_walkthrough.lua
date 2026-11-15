-- Full campaign played by a "bot" that really WALKS (arrow keys, wall
-- sliding, doors) from task to task: finds invisible walls, unreachable
-- stations and stuck spots that teleporting tests cannot see.
-- Run from the repository root:  lua tests/test_walkthrough.lua

package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq = T.test, T.eq
local Room = require("src.room_scene")
local Map = require("src.station_map")

local held = {}
local function isDown(k) return held[k] == true end
local DT = 1 / 60
local STEP = 12

-- grid search over free standing spots, from Vulcan to any spot where goal(x, y)
local function findPath(room, goal)
  local v = room.vulcan
  local x0, y0 = math.floor(v.x / STEP + 0.5), math.floor(v.y / STEP + 0.5)
  local function key(i, j) return i * 100000 + j end
  local prev, queue, head = { [key(x0, y0)] = false }, { { x0, y0 } }, 1
  while head <= #queue do
    local c = queue[head]; head = head + 1
    local cx, cy = c[1] * STEP, c[2] * STEP
    if goal(cx, cy) then
      local path, k = {}, key(c[1], c[2])
      local node = c
      while node do
        table.insert(path, 1, { node[1] * STEP, node[2] * STEP })
        node = prev[key(node[1], node[2])]
      end
      return path
    end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local i, j = c[1] + d[1], c[2] + d[2]
      local k = key(i, j)
      if prev[k] == nil and not room:_blocked(i * STEP, j * STEP) then
        prev[k] = c
        queue[#queue + 1] = { i, j }
      end
    end
  end
  return nil
end

local function release() held = {} end

-- drive the keys along the path; returns false + position when stuck
local function follow(room, path)
  local v = room.vulcan
  for _, p in ipairs(path) do
    local stuckFrames, last = 0, nil
    while true do
      local dx, dy = p[1] - v.x, p[2] - v.y
      if math.abs(dx) <= 3 and math.abs(dy) <= 3 then break end
      release()
      if dx > 1 then held.right = true elseif dx < -1 then held.left = true end
      if dy > 1 then held.down = true elseif dy < -1 then held.up = true end
      room:update(DT)
      local now = v.x * 10000 + v.y
      if last and math.abs(now - last) < 0.01 then stuckFrames = stuckFrames + 1 else stuckFrames = 0 end
      last = now
      if stuckFrames > 30 then release(); return false, string.format("stuck at %.3f,%.3f heading to %d,%d (over=%s asleep=%s critical=%s cause=%s)", v.x, v.y, p[1], p[2], tostring(room:isOver()), tostring(room.human.isSleeping), table.concat(room.ls:criticalSystems(), "+"), tostring(room.ls.failureCause)) end
    end
  end
  release()
  return true
end

local function walkTo(room, label, goal)
  local path = findPath(room, goal)
  if not path then error("no walking route to " .. label .. " from " .. math.floor(room.vulcan.x) .. "," .. math.floor(room.vulcan.y)) end
  local ok, why = follow(room, path)
  if not ok then error("walking to " .. label .. ": " .. why) end
end

-- a spot comfortably inside the click range (8 px margin for steering)
local function nearGoal(room, m)
  local reach = Room.INTERACT_RANGE + room.vulcan.radius - 8
  return function(x, y)
    local cx = math.max(m.x, math.min(x, m.x + m.w))
    local cy = math.max(m.y, math.min(y, m.y + m.h))
    return (x - cx) ^ 2 + (y - cy) ^ 2 <= reach * reach
  end
end

test("a walking bot finishes the whole campaign", function()
  release()
  local r = Room.new({ isDown = isDown, campaign = true, puzzles = true })
  local puzzles = 0
  local log = {}
  local guard = 0
  while not r.missionComplete do
    guard = guard + 1
    if guard > 2000 then error("too many steps; stuck on " .. tostring(r.mission:objective().id)) end
    assert(not r.ls.missionFailed, "mission failed: " .. tostring(r.ls.failureCause))
    local o = r.mission:objective()
    local station = r.guide.station or o.station
    if os.getenv("WALK_LOG") and r.mission.level >= 7 then print(string.format("  [t=%.0f] guide=%s (%s) O2=%.2f CO2=%.2f water=%.0f procW=%.1f batt=%.0f phase=%s crit=%s", r.ls.missionTime, tostring(r.guide.station), r.guide.text, r.air.oxygenPercent, r.air.carbonDioxidePercent, r.ls.potableWater, r.ls.processWater, r.ls.battery, r.ls.radiation.phase, table.concat(r.ls:criticalSystems(), "+"))) end
    if not station then
      -- nothing to do right now (waiting out the storm): let time pass
      for _ = 1, 10 do r:update(0.1) end
    elseif station == "outside" then
      walkTo(r, "outside", function(x, y) return Map.isOutside(x, y) and x < -120 end)
    elseif station == "entrance" then
      walkTo(r, "inner door", function(x, y) return x > Map.ENTRANCE_X + 40 and y > Map.ENTRANCE_Y1 and y < Map.ENTRANCE_Y2 end)
    else
      local m = r:machineById(station)
      assert(m, "unknown station " .. tostring(station))
      walkTo(r, station, nearGoal(r, m))
      if station == "solar" then while not r.ls:isSunUp() do r:update(0.5) end end
      r:clickStation(m)
      if r.puzzles:isOpen() then
        -- play the mini-game (solved through its own rules), then close it
        puzzles = puzzles + 1
        r.puzzles.active:update(0.05)
        r.puzzles.active:solve()
        local guardP = 0
        while r.puzzles:isOpen() and guardP < 200 do r:update(0.05); guardP = guardP + 1 end
        assert(not r.puzzles:isOpen(), "puzzle " .. m.puzzle .. " did not close")
      end
      if os.getenv("WALK_LOG") then print(string.format("L%d %-12s %s", r.mission.level, station, tostring(r.message))) end
      log[#log + 1] = string.format("L%d %-12s %s", r.mission.level, station, tostring(r.message))
      if r.ls.co2CleanerCooldown > 0 and station == "co2" then r:update(0.1) end
    end
  end
  eq(r.missionComplete, true)
  eq(r.ls.missionFailed, false)
  assert(puzzles >= 17, "every mini-game was played (" .. puzzles .. ")")
end)

test("every machine and the outer door can be reached on foot (sandbox)", function()
  release()
  local r = Room.new({ isDown = isDown })
  for _, m in ipairs(r.machines) do
    local start = { r.vulcan.x, r.vulcan.y }
    if not findPath(r, nearGoal(r, m)) then error("cannot walk to " .. m.id) end
    r.vulcan.x, r.vulcan.y = start[1], start[2]
  end
end)

T.finish()
