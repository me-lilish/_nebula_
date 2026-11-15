-- Plain-Lua tests for the Habitat Air System (no Love2D needed).
-- Run from the repository root:  lua tests/test_air_system.lua

package.path = "./?.lua;" .. package.path
local AirSystem = require("src.air_system")
local baseConfig = require("src.air_config")

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. name .. "\n   " .. tostring(err)) end
end
local function eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end
local function near(actual, expected, msg)
  if math.abs(actual - expected) > 1e-6 then
    error((msg or "") .. " expected ~" .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

-- Config copy with overrides (e.g. no breathing, so we control gas levels).
local function cfg(overrides)
  local c = {}
  for k, v in pairs(baseConfig) do c[k] = v end
  for k, v in pairs(overrides or {}) do c[k] = v end
  return c
end
local still = { ASTRONAUT_O2_USE_PER_SEC = 0, ASTRONAUT_CO2_MAKE_PER_SEC = 0, POWER_RECHARGE_PER_SEC = 0 }

local function setAir(air, o2, co2)
  air.oxygenPercent, air.carbonDioxidePercent = o2, co2
  air:_refresh()
end

-- Step the simulation in small slices like a real frame loop.
local function run(air, seconds, step)
  step = step or 0.1
  local n = math.floor(seconds / step + 0.5)
  for _ = 1, n do air:update(step) end
end

------------------------------------------------------------------------------
-- Thresholds
------------------------------------------------------------------------------
local o2Cases = {
  { 25.0, "danger" }, { 23.6, "danger" }, { 23.5, "caution" }, { 21.6, "caution" },
  { 21.5, "good" }, { 21.0, "good" }, { 20.5, "good" }, { 20.45, "caution" },
  { 20.4, "caution" }, { 19.5, "caution" }, { 19.4, "danger" }, { 18.0, "danger" },
  { 17.99, "critical" }, { 10.0, "critical" },
}
for _, case in ipairs(o2Cases) do
  test("O2 " .. case[1] .. "% is " .. case[2], function()
    eq(AirSystem.classifyO2(case[1]), case[2])
  end)
end

local co2Cases = {
  { 0.04, "good" }, { 0.49, "good" }, { 0.5, "caution" }, { 0.7, "caution" },
  { 0.705, "danger" }, { 0.71, "danger" }, { 1.0, "danger" }, { 1.01, "critical" }, { 3.0, "critical" },
}
for _, case in ipairs(co2Cases) do
  test("CO2 " .. case[1] .. "% is " .. case[2], function()
    eq(AirSystem.classifyCO2(case[1]), case[2])
  end)
end

test("overall status is the worse gas", function()
  eq(AirSystem.classify(21.0, 0.6), "caution")
  eq(AirSystem.classify(19.0, 0.6), "danger")
  eq(AirSystem.classify(21.0, 1.2), "critical")
  eq(AirSystem.classify(17.0, 0.04), "critical")
end)

test("too much O2 is never critical", function()
  eq(AirSystem.classifyO2(30.0), "danger")
end)

------------------------------------------------------------------------------
-- Air-quality score
------------------------------------------------------------------------------
test("score starts at 100 with 21% O2 and 0.04% CO2", function()
  local air = AirSystem.new()
  near(air.airQuality, 100)
  eq(air.airStatus, "good")
end)
test("score drops with O2 distance from 21% in both directions", function()
  near(AirSystem.computeQuality(20.0, 0.04), 80)
  near(AirSystem.computeQuality(22.0, 0.04), 80)
end)
test("score drops with CO2", function()
  near(AirSystem.computeQuality(21.0, 0.54), 70)
end)
test("score is clamped to 0..100", function()
  eq(AirSystem.computeQuality(5.0, 4.0), 0)
  eq(AirSystem.computeQuality(21.0, 0.0), 100) -- CO2 below 0.04 doesn't exceed 100
end)
test("status comes from thresholds, not the score", function()
  -- 19.6% O2: score ~72 but status caution; 17.9%: score ~38 and critical.
  local air = AirSystem.new(cfg(still))
  setAir(air, 19.6, 0.04); eq(air.airStatus, "caution")
  setAir(air, 21.0, 1.05); eq(air.airStatus, "critical")
  if air.airQuality < 30 then error("score unexpectedly low for this check") end
end)

------------------------------------------------------------------------------
-- Critical timer and game over
------------------------------------------------------------------------------
test("critical timer counts up while critical", function()
  local air = AirSystem.new(cfg(still))
  setAir(air, 17.0, 0.04)
  run(air, 10)
  near(air.criticalTimer, 10, "timer")
  eq(air.missionFailed, false)
end)
test("timer resets to 0 as soon as air leaves critical (via update)", function()
  local air = AirSystem.new(cfg(still))
  setAir(air, 17.0, 0.04)
  run(air, 20)
  setAir(air, 18.5, 0.04) -- danger, not critical
  air:update(0.1)
  eq(air.criticalTimer, 0)
end)
test("timer resets immediately when an interaction fixes the air", function()
  local air = AirSystem.new(cfg(still))
  setAir(air, 17.5, 0.04)
  run(air, 15)
  assert(air:useOxygenGenerator())
  eq(air.airStatus, "danger")
  eq(air.criticalTimer, 0)
end)
test("timer does NOT reset if only one of two critical gases is fixed", function()
  local air = AirSystem.new(cfg(still))
  setAir(air, 17.5, 1.2)
  run(air, 10)
  assert(air:useOxygenGenerator())
  eq(air.airStatus, "critical")
  near(air.criticalTimer, 10)
end)
test("game over after exactly 30 continuous critical seconds", function()
  local air = AirSystem.new(cfg(still))
  setAir(air, 17.0, 0.04)
  run(air, 29.9)
  eq(air.missionFailed, false, "at 29.9s")
  run(air, 0.1)
  eq(air.missionFailed, true, "at 30s")
  eq(air.failureCause, "low_oxygen")
end)
test("leaving critical at 29s and returning restarts the full 30s", function()
  local air = AirSystem.new(cfg(still))
  setAir(air, 17.0, 0.04); run(air, 29)
  setAir(air, 19.0, 0.04); air:update(0.1)
  setAir(air, 17.0, 0.04); run(air, 29)
  eq(air.missionFailed, false)
end)
test("failure cause names CO2 or both", function()
  local a = AirSystem.new(cfg(still)); setAir(a, 21, 1.5); run(a, 30)
  eq(a.failureCause, "high_co2")
  local b = AirSystem.new(cfg(still)); setAir(b, 17, 1.5); run(b, 30)
  eq(b.failureCause, "both")
  local fb = b:getFeedback()
  eq(fb.failed, true)
  assert(fb.message:find("unsafe for too long"), fb.message)
end)
test("simulation freezes and interactions refuse after game over", function()
  local air = AirSystem.new(cfg(still))
  setAir(air, 17.0, 0.04); run(air, 30)
  local o2 = air.oxygenPercent
  air:update(5)
  eq(air.oxygenPercent, o2)
  local ok, reason = air:useOxygenGenerator()
  eq(ok, false); eq(reason, "mission_failed")
end)
test("ignored astronaut breathing eventually causes game over", function()
  local air = AirSystem.new()
  run(air, 200)
  eq(air.missionFailed, true)
end)

------------------------------------------------------------------------------
-- Equipment limits
------------------------------------------------------------------------------
test("oxygen generator raises O2 and uses a canister + power", function()
  local air = AirSystem.new(cfg(still))
  setAir(air, 19.0, 0.04)
  local ok = air:useOxygenGenerator()
  eq(ok, true)
  near(air.oxygenPercent, 20.0)
  eq(air.oxygenCanisters, baseConfig.O2_GEN_START_CANISTERS - 1)
  near(air.power, baseConfig.POWER_START - baseConfig.O2_GEN_POWER_COST)
end)
test("oxygen generator stops when canisters run out", function()
  local air = AirSystem.new(cfg(still))
  for _ = 1, baseConfig.O2_GEN_START_CANISTERS do assert(air:useOxygenGenerator()) end
  local ok, reason = air:useOxygenGenerator()
  eq(ok, false); eq(reason, "no_canisters")
end)
test("oxygen generator needs power", function()
  local air = AirSystem.new(cfg(still))
  air.power = baseConfig.O2_GEN_POWER_COST - 1
  local ok, reason = air:useOxygenGenerator()
  eq(ok, false); eq(reason, "no_power")
  eq(air.oxygenCanisters, baseConfig.O2_GEN_START_CANISTERS, "canister not wasted")
end)
test("scrubber lowers CO2, then is blocked by cooldown", function()
  local air = AirSystem.new(cfg(still))
  setAir(air, 21.0, 0.9)
  assert(air:useScrubber())
  near(air.carbonDioxidePercent, 0.6)
  local ok, reason = air:useScrubber()
  eq(ok, false); eq(reason, "cooldown")
  run(air, baseConfig.SCRUBBER_COOLDOWN_SEC)
  assert(air:useScrubber())
end)
test("scrubber CO2 never goes below 0", function()
  local air = AirSystem.new(cfg(still))
  assert(air:useScrubber())
  eq(air.carbonDioxidePercent, 0)
end)
test("scrubber filter capacity runs out", function()
  local air = AirSystem.new(cfg(still))
  air.power = 1000
  for _ = 1, baseConfig.SCRUBBER_FILTER_USES do
    assert(air:useScrubber()); run(air, baseConfig.SCRUBBER_COOLDOWN_SEC)
  end
  local ok, reason = air:useScrubber()
  eq(ok, false); eq(reason, "filter_full")
end)
test("scrubber needs power", function()
  local air = AirSystem.new(cfg(still))
  air.power = 0
  local ok, reason = air:useScrubber()
  eq(ok, false); eq(reason, "no_power")
  eq(air.scrubberFilterUses, baseConfig.SCRUBBER_FILTER_USES, "filter use not wasted")
end)
test("power never exceeds max", function()
  local air = AirSystem.new()
  run(air, 10)
  eq(air.power, baseConfig.POWER_MAX)
end)

------------------------------------------------------------------------------
-- Farm
------------------------------------------------------------------------------
local farmOnly = cfg(still)
test("farm needs water AND light AND power", function()
  local air = AirSystem.new(farmOnly)
  air:update(1); eq(air.farmActive, false, "nothing")
  air:setFarmWater(true); air:update(1); eq(air.farmActive, false, "water only")
  air:setFarmWater(false); air:setFarmLight(true); air:update(1); eq(air.farmActive, false, "light only")
  air:setFarmWater(true); air:update(1); eq(air.farmActive, true, "all three")
  air.power = 0; air:update(1); eq(air.farmActive, false, "no power")
end)
test("active farm makes O2, removes CO2 and uses power", function()
  local air = AirSystem.new(farmOnly)
  setAir(air, 20.0, 0.5)
  air:setFarmWater(true); air:setFarmLight(true)
  run(air, 10)
  near(air.oxygenPercent, 20.0 + 10 * baseConfig.FARM_O2_MAKE_PER_SEC)
  near(air.carbonDioxidePercent, 0.5 - 10 * baseConfig.FARM_CO2_REMOVE_PER_SEC)
  near(air.power, baseConfig.POWER_START - 10 * baseConfig.FARM_POWER_USE_PER_SEC)
end)
test("farm alone cannot keep up with the astronaut (not an emergency fix)", function()
  assert(baseConfig.FARM_O2_MAKE_PER_SEC < baseConfig.ASTRONAUT_O2_USE_PER_SEC)
  assert(baseConfig.FARM_CO2_REMOVE_PER_SEC < baseConfig.ASTRONAUT_CO2_MAKE_PER_SEC)
  local air = AirSystem.new()
  air:setFarmWater(true); air:setFarmLight(true)
  run(air, 300)
  eq(air.missionFailed, true)
end)

------------------------------------------------------------------------------
-- Feedback
------------------------------------------------------------------------------
test("feedback colour and message per status", function()
  local air = AirSystem.new(cfg(still))
  eq(air:getFeedback().color, AirSystem.COLORS.good)
  setAir(air, 20.0, 0.04)
  local fb = air:getFeedback()
  eq(fb.color, AirSystem.COLORS.caution); eq(fb.message, "Check the air system.")
  setAir(air, 19.0, 0.04)
  fb = air:getFeedback()
  eq(fb.color, AirSystem.COLORS.danger); assert(fb.message:find("Oxygen Generator"), fb.message)
  setAir(air, 21.0, 0.9)
  assert(air:getFeedback().message:find("CO2 Scrubber"))
  setAir(air, 21.0, 1.2); air:update(5)
  fb = air:getFeedback()
  eq(fb.color, AirSystem.COLORS.critical)
  near(fb.timeLeft, 25)
  assert(fb.message:find("EMERGENCY") and fb.message:find("25 seconds"), fb.message)
end)
test("danger from too much O2 says to stop adding oxygen", function()
  local air = AirSystem.new(cfg(still))
  setAir(air, 24.0, 0.04)
  assert(air:getFeedback().message:find("Stop adding oxygen"))
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
