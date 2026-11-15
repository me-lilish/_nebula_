-- Regression tests for the First Safe Day rebuild: game pacing and the
-- mission-state layer stay independent of Love2D rendering.
package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq, near = T.test, T.eq, T.near
local LifeSupport = require("src.life_support")
local Mission = require("src.mission_state")

test("new clock advances ten simulated minutes per real second", function()
  local ls = T.still()
  ls:update(6)
  local _, hour = ls:clock()
  eq(hour, T.C.START_HOUR + 1)
end)

test("sleep pod fast-forward simulates eight game hours and wakes Vulcan", function()
  local ls = T.still()
  local ok = ls:fastForwardSleep()
  eq(ok, true)
  near(ls.missionTime, 48)
  eq(ls.human.isSleeping, false)
  near(ls.human:sleepInLastDay(), 48)
end)

test("the mission is 8 levels, easiest to hardest, one task at a time", function()
  local ids = {}
  for i, lv in ipairs(Mission.LEVELS) do ids[i] = lv.id end
  eq(table.concat(ids, ","), "human,dust,water,food,waste,air,power,radiation")
  local m = Mission.new()
  eq(m:objective().station, "foodstation")
  eq(m:complete("toilet"), false, "only the current task counts")
  m:complete("foodstation"); eq(m:objective().station, "toilet")
  m:complete("toilet"); eq(m:objective().station, "sleep")
  local ok, unlocked = m:complete("sleep")
  eq(ok, true); eq(unlocked.id, "dust"); eq(m:objective().station, "outside")
end)

test("locked levels stay with Mission Control until they open", function()
  local m = Mission.new()
  eq(m:isRoomUnlocked("quarters"), true); eq(m:isRoomUnlocked("airlock"), false)
  eq(m:exteriorUnlocked(), false)
  local a = m:autopilot()
  eq(a.human, nil); eq(a.air, true); eq(a.radiation, true)
  for _, id in ipairs({ "foodstation", "toilet", "sleep" }) do m:complete(id) end
  eq(m:isRoomUnlocked("airlock"), true); eq(m:exteriorUnlocked(), true); eq(m:autopilot().dust, nil)
  eq(Mission.new({ unlockAll = true }):objective(), nil)
end)

T.finish()
