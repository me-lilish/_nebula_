-- Campaign play-through (plain Lua, no Love2D): the 8 levels unlock one
-- system at a time, locked rooms block Vulcan, Mission Control (autopilot)
-- keeps locked systems safe, and the whole mission can be finished.
-- Run from the repository root:  lua tests/test_progression.lua

package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq = T.test, T.eq
local Room = require("src.room_scene")
local Map = require("src.station_map")
local Layout = require("src.room_layout")
local Sizes = require("src.prop_sizes")

local held = {}
local function isDown(k) return held[k] == true end
local function newCampaign() held = {}; return Room.new({ isDown = isDown, campaign = true }) end
local function walk(room, key, frames)
  held[key] = true
  for _ = 1, frames do room:update(0.02) end
  held[key] = false
end
local function use(room, id)
  local m = room:machineById(id)
  local x, y = room:spotNear(m)
  assert(x, "no free spot next to " .. id)
  room.vulcan.x, room.vulcan.y = x, y
  room:clickStation(m)
  return room.message
end
local function objective(room) local o = room.mission:objective(); return o and o.id end

test("the campaign starts in the crew quarters with only level 1 open", function()
  local r = newCampaign()
  eq(Map.roomAt(r.vulcan.x, r.vulcan.y).id, "quarters")
  eq(r.outside, false); eq(r.dust.suitDust, 0)
  eq(objective(r), "foodstation")
  eq(r:isRoomLocked("quarters"), false)
  for _, id in ipairs({ "airlock", "water", "food", "waste", "air", "power", "batteries", "comms" }) do
    eq(r:isRoomLocked(id), true, id)
  end
  eq(r.guide.station, "foodstation")
end)

test("locked rooms: Vulcan cannot walk in and machines refuse", function()
  local r = newCampaign()
  local d
  for _, door in ipairs(Map.doors) do if door.room == "comms" and door.top then d = door end end
  -- stand in the quarters -> comms corridor and walk down into comms
  r.vulcan.x, r.vulcan.y = d.x + d.w / 2, d.y - 60
  walk(r, "down", 80)
  if Map.roomAt(r.vulcan.x, r.vulcan.y) and Map.roomAt(r.vulcan.x, r.vulcan.y).id == "comms" then
    error("walked into a locked room")
  end
  local m = r:machineById("oxygen")
  r.vulcan.x, r.vulcan.y = m.x + m.w / 2, m.y + m.h + 30
  r:clickStation(m)
  eq(r.message, "Locked! This opens at Level 6.")
end)

test("Mission Control keeps locked systems safe", function()
  local r = newCampaign()
  for _ = 1, 600 do r:update(0.1) end -- a whole minute (10 game hours)
  eq(r.ls:isAnyCritical(), false)
  T.near(r.air.oxygenPercent, T.AirC.START_O2_PERCENT)
  assert(r.ls.battery >= T.C.BATTERY_START - 1e-6, "battery held")
  eq(r.ls.radiation.phase, "clear")
end)

test("full play-through: every level unlocks and the mission is completed", function()
  local r = newCampaign()
  -- 1 HUMAN
  eq(use(r, "foodstation"), "Yum! Vulcan ate a warm meal.")
  use(r, "toilet"); use(r, "sleep")
  eq(r.mission.level, 2); eq(r:isRoomLocked("airlock"), false)
  assert(r.unlockCard and r.unlockCard.level.id == "dust", "unlock card shown")
  eq(objective(r), "outside")
  -- 2 DUST: walk out through the outer door, come back, brush, walk in
  local d = Map.outerDoor
  r.vulcan.x, r.vulcan.y = d.x + d.w + 30, d.y + d.h / 2
  walk(r, "left", 60)
  eq(r.outside, true); eq(objective(r), "dustoff")
  assert(r.dust.suitDust > 0, "dusty suit")
  walk(r, "right", 60)
  eq(r.outside, false)
  use(r, "dustoff"); eq(r.dust.suitDust, 0)
  r.vulcan.x, r.vulcan.y = Room.ENTRANCE_X - 60, (Map.ENTRANCE_Y1 + Map.ENTRANCE_Y2) / 2
  walk(r, "right", 30)
  eq(r.dust.cabinDust, 0); eq(objective(r), "trace")
  eq(use(r, "trace"), "Fresh HEPA filter locked in - the cabin air is clean!")
  eq(r.mission.level, 3)
  -- 3 WATER
  eq(use(r, "water"), "Three steps complete: clean water is ready!")
  eq(use(r, "valves"), "Tanks balanced: 20 litres sent to the Oxygen Generator line.")
  eq(r.mission.level, 4)
  -- 4 FOOD: tune the lights, then the first crops are ripe
  eq(use(r, "growlight"), "Perfect light recipe: the plants shot up!")
  eq(use(r, "greenhouse"), "Harvest time! Crops and plant scraps collected.")
  eq(use(r, "foodstorage"), "Crops packed into the Food Cooler.")
  eq(r.mission.level, 5)
  -- 5 WASTE
  eq(use(r, "compost"), "Plant scraps turned into fertilizer for the garden.")
  eq(use(r, "recycle"), "Recycled 3 broken parts into spares for repairs!")
  eq(r.mission.level, 6)
  -- 6 AIR
  eq(use(r, "oxygen"), "Great! Fresh oxygen is flowing.")
  eq(use(r, "co2"), "Nice! The CO₂ Scrubber caught used-up air.")
  eq(use(r, "recycler"), "The CO₂ Recycler turned waste gas into water.")
  eq(r.mission.level, 7)
  -- 7 POWER (aim the panels by day)
  use(r, "battery")
  while not r.ls:isSunUp() do r:update(0.5) end
  eq(use(r, "solar"), "Panels now point at the Sun. More power!")
  eq(r.mission.level, 8)
  -- 8 RADIATION: a storm warning starts right away
  eq(r.ls.radiation.phase, "warning")
  for _ = 1, 3 do use(r, "regolith"); use(r, "shield") end
  eq(r.ls.radiation:deployedUnits(), 9)
  r:update(0.1)
  eq(objective(r), "survive")
  local guard = 0
  while not r.missionComplete and guard < 6000 do r:update(0.1); guard = guard + 1 end
  eq(r.missionComplete, true)
  eq(r.ls.missionFailed, false)
end)

test("layout: furniture stays inside its room and off the doorways", function()
  for _, p in ipairs(Layout.PROPS) do
    if not Sizes[p.sprite] then error("missing sprite size " .. p.sprite) end
    local room = Map.roomById(p.room)
    local cx, cy = p.x + p.w / 2, p.y + p.h - 4
    if Map.roomAt(cx, cy) ~= room then error(p.sprite .. " is outside " .. p.room) end
    if p.solid then
      local f = Layout.footprint(p)
      for _, d in ipairs(Map.doors) do
        if f.x < d.x + d.w + 24 and d.x - 24 < f.x + f.w and f.y < d.y + d.h + 24 and d.y - 24 < f.y + f.h then
          error(p.sprite .. " in " .. p.room .. " blocks a doorway")
        end
      end
    end
  end
end)

test("exhaustion slows Vulcan down", function()
  local r = newCampaign()
  local x0 = r.vulcan.x; walk(r, "left", 10); local normal = x0 - r.vulcan.x
  r.human.isFatigued = function() return true end
  x0 = r.vulcan.x; walk(r, "left", 10); local tired = x0 - r.vulcan.x
  T.near(tired, normal * Room.TIRED_SPEED, 1e-6)
end)

test("Shift sprints; legs only move when Vulcan really moves", function()
  local r = newCampaign()
  local Vulcan = require("src.vulcan")
  local x0 = r.vulcan.x; walk(r, "left", 10); local walked = x0 - r.vulcan.x
  held.lshift = true
  x0 = r.vulcan.x; walk(r, "left", 10); local sprinted = x0 - r.vulcan.x
  held.lshift = false
  T.near(sprinted, walked * Vulcan.SPRINT, 1e-6)
  -- push into the quarters' left wall: no walking animation, no "moving"
  walk(r, "left", 120)
  eq(r.vulcan.moving, false); eq(r.vulcan.anim, 0)
  -- tired astronauts cannot sprint
  r.human.isFatigued = function() return true end
  r.vulcan.x = 2100
  held.lshift = true; x0 = r.vulcan.x; walk(r, "left", 10); held.lshift = false
  T.near(x0 - r.vulcan.x, walked * Room.TIRED_SPEED, 1e-6)
end)

test("sandbox mode still opens everything", function()
  local r = Room.new({ isDown = isDown })
  eq(r:isRoomLocked("comms"), false); eq(r.mission:objective(), nil); eq(r.ls.autopilot, nil)
end)

T.finish()
