-- Plain-Lua tests for the cabin-air (O2/CO2) subsystem (no Love2D needed).
-- Machines, power and the emergency timer are tested in test_life_support.lua.
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
local function setAir(air, o2, co2)
  air.oxygenPercent, air.carbonDioxidePercent = o2, co2
  air:_refresh()
end

------------------------------------------------------------------------------
-- Thresholds (unchanged from the original air system)
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
  eq(AirSystem.computeQuality(21.0, 0.0), 100)
end)
test("status comes from thresholds, not the score", function()
  local air = AirSystem.new()
  setAir(air, 19.6, 0.04); eq(air.airStatus, "caution")
  setAir(air, 21.0, 1.05); eq(air.airStatus, "critical")
  if air.airQuality < 30 then error("score unexpectedly low for this check") end
end)

------------------------------------------------------------------------------
-- Breathing and gas changes
------------------------------------------------------------------------------
test("crew breathing lowers O2 and raises CO2 at the configured rates", function()
  local air = AirSystem.new()
  for _ = 1, 100 do air:update(0.1) end
  near(air.oxygenPercent, 21.0 - 10 * baseConfig.ASTRONAUT_O2_USE_PER_SEC)
  near(air.carbonDioxidePercent, 0.04 + 10 * baseConfig.ASTRONAUT_CO2_MAKE_PER_SEC)
end)
test("ignored breathing eventually makes the air critical", function()
  local air = AirSystem.new()
  for _ = 1, 2000 do air:update(0.1) end
  eq(air:isCritical(), true); eq(air:criticalCause(), "low_oxygen")
end)
test("addOxygen raises O2 and returns what was added (clamped)", function()
  local air = AirSystem.new()
  near(air:addOxygen(1.0), 1.0); near(air.oxygenPercent, 22.0)
  setAir(air, 29.5, 0.04)
  near(air:addOxygen(1.0), 0.5); eq(air.oxygenPercent, baseConfig.O2_MAX_PERCENT)
end)
test("removeCO2 lowers CO2 and never removes more than exists", function()
  local air = AirSystem.new()
  setAir(air, 21.0, 0.9)
  near(air:removeCO2(0.3), 0.3); near(air.carbonDioxidePercent, 0.6)
  setAir(air, 21.0, 0.1)
  near(air:removeCO2(0.3), 0.1); eq(air.carbonDioxidePercent, 0)
end)
test("gas changes never affect each other", function()
  local air = AirSystem.new()
  local co2 = air.carbonDioxidePercent
  air:addOxygen(1.0); eq(air.carbonDioxidePercent, co2)
  local o2 = air.oxygenPercent
  air:removeCO2(0.01); eq(air.oxygenPercent, o2)
end)
test("critical cause names the gas", function()
  local air = AirSystem.new()
  setAir(air, 17, 0.04); eq(air:criticalCause(), "low_oxygen")
  setAir(air, 21, 1.5); eq(air:criticalCause(), "high_co2")
  setAir(air, 17, 1.5); eq(air:criticalCause(), "both")
  setAir(air, 21, 0.04); eq(air:criticalCause(), nil); eq(air:isCritical(), false)
end)
test("air subsystem owns no power, tanks or timer", function()
  local air = AirSystem.new()
  eq(air.power, nil); eq(air.oxygenCanisters, nil); eq(air.criticalTimer, nil)
  eq(air.useOxygenGenerator, nil)
end)

------------------------------------------------------------------------------
-- Feedback
------------------------------------------------------------------------------
test("feedback colour and message per status", function()
  local air = AirSystem.new()
  eq(air:getFeedback().color, AirSystem.COLORS.good)
  setAir(air, 20.0, 0.04)
  local fb = air:getFeedback()
  eq(fb.color, AirSystem.COLORS.caution); eq(fb.message, "Check the air system.")
  setAir(air, 19.0, 0.04)
  fb = air:getFeedback()
  eq(fb.color, AirSystem.COLORS.danger); assert(fb.message:find("Oxygen Maker"), fb.message)
  setAir(air, 21.0, 0.9)
  assert(air:getFeedback().message:find("CO2 Cleaner"))
  setAir(air, 21.0, 1.2)
  fb = air:getFeedback(25)
  eq(fb.color, AirSystem.COLORS.critical); eq(fb.timeLeft, 25)
  assert(fb.message:find("EMERGENCY") and fb.message:find("25 seconds"), fb.message)
end)
test("danger from too much O2 says to stop adding oxygen", function()
  local air = AirSystem.new()
  setAir(air, 24.0, 0.04)
  assert(air:getFeedback().message:find("Stop adding oxygen"))
end)
test("failure messages are child-friendly and name the machine", function()
  assert(AirSystem.FAILURE_MESSAGES.low_oxygen:find("Oxygen Maker"))
  assert(AirSystem.FAILURE_MESSAGES.high_co2:find("CO2 Cleaner"))
  assert(AirSystem.FAILURE_MESSAGES.both:find("unsafe for too long"))
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
