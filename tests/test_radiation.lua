-- Unit tests for the radiation subsystem (src/radiation_system.lua).
-- Run from the repository root:  lua tests/test_radiation.lua

package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq, near = T.test, T.eq, T.near
local RC = T.RadC
local RadiationSystem = require("src.radiation_system")

local function run(r, seconds)
  local events = {}
  for _ = 1, math.floor(seconds / 0.1 + 0.5) do
    for _, e in ipairs(r:update(0.1)) do events[#events + 1] = e end
  end
  return events
end
local function count(events, kind)
  local n = 0
  for _, e in ipairs(events) do if e.type == kind then n = n + 1 end end
  return n
end

test("nine sections and nine shield units", function()
  local r = RadiationSystem.new()
  eq(#r.order, 9); eq(RC.SHIELD_UNITS, 9); eq(r:unitsLeft(), 9); eq(r:deployedUnits(), 0)
  for _, id in ipairs({ "crew", "air", "water", "food", "power", "greenhouse", "waste", "entrance", "storage" }) do
    if not r.sections[id] then error("missing section " .. id) end
  end
end)
test("schedule: clear -> warning (2 min) -> storm -> clear", function()
  local r = RadiationSystem.new()
  local e = run(r, RC.FIRST_WARNING_AT_SEC - 0.1); eq(r.phase, "clear"); eq(#e, 0)
  e = run(r, 0.1); eq(r.phase, "warning"); eq(count(e, "warning"), 1)
  near(r:timeToStorm(), RC.WARNING_LEAD_SEC)
  run(r, RC.WARNING_LEAD_SEC - 0.1); eq(r.phase, "warning")
  e = run(r, 0.1); eq(r.phase, "storm"); eq(count(e, "storm"), 1)
  e = run(r, RC.STORM_DURATION_SEC); eq(r.phase, "clear"); eq(count(e, "clear"), 1)
  eq(r.stormsSurvived, 1)
  near(r:timeToStorm(), RC.STORM_INTERVAL_SEC + RC.WARNING_LEAD_SEC)
end)
test("loader adds 3 units per use up to 9; reasons when done", function()
  local r = RadiationSystem.new()
  eq(r:load(), 3); eq(r.loadedUnits, 3); eq(r:unitsLeft(), 6)
  r:load(); r:load(); eq(r.loadedUnits, 9)
  eq(select(2, r:canLoad()), "loader_full")
  r:deploy(); eq(select(2, r:canLoad()), "all_shielded")
end)
test("deploy places loaded units crew first, then in order", function()
  local r = RadiationSystem.new()
  eq(select(2, r:canDeploy()), "no_regolith")
  r:load(); eq(r:deploy(), 3)
  eq(r.sections.crew.shielded, true); eq(r.sections.air.shielded, true); eq(r.sections.water.shielded, true)
  eq(r.sections.food.shielded, false); eq(r.loadedUnits, 0)
end)
test("crew is exposed only during a storm without a crew shield", function()
  local r = RadiationSystem.new(); r:triggerWarning()
  eq(r:isCrewExposed(), false)
  run(r, RC.WARNING_LEAD_SEC); eq(r.phase, "storm"); eq(r:isCrewExposed(), true)
  r:load(); r:deploy(); eq(r:isCrewExposed(), false)
end)
test("unshielded sections lose integrity; damage event once at the line", function()
  local r = RadiationSystem.new(); r:triggerWarning(); r:load(); r:deploy()
  local e = run(r, RC.WARNING_LEAD_SEC + RC.STORM_DURATION_SEC)
  eq(count(e, "damage"), 6)
  eq(r.sections.crew.integrity, 100)
  near(r.sections.food.integrity, math.max(0, 100 - RC.SECTION_DAMAGE_PER_SEC * (RC.STORM_DURATION_SEC + 0.1)), 0.3)
  eq(r.sections.food.damaged, true)
end)
test("no damage outside storms", function()
  local r = RadiationSystem.new()
  run(r, RC.FIRST_WARNING_AT_SEC + RC.WARNING_LEAD_SEC - 1)
  for _, id in ipairs(r.order) do eq(r.sections[id].integrity, 100) end
end)
test("reset clears shields, schedule and damage", function()
  local r = RadiationSystem.new(); r:triggerWarning(); r:load(); r:deploy(); run(r, 200)
  r:reset()
  eq(r.phase, "clear"); eq(r:deployedUnits(), 0); eq(r.loadedUnits, 0); eq(r.sections.food.integrity, 100)
end)

T.finish()
