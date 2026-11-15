-- Shared helpers for the plain-Lua test files.
package.path = "./?.lua;" .. package.path
local LifeSupport = require("src.life_support")

local T = {}
T.C = require("src.life_support_config")
T.AirC = require("src.air_config")
T.DustC = require("src.dust_config")
T.HumanC = require("src.human_config")
T.RadC = require("src.radiation_config")

local passed, failed = 0, 0
function T.test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. name .. "\n   " .. tostring(err)) end
end
function T.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end
function T.near(actual, expected, tol, msg)
  if type(tol) == "string" then msg, tol = tol, nil end
  if math.abs(actual - expected) > (tol or 1e-6) then
    error((msg or "") .. " expected ~" .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end
function T.finish()
  print(string.format("\n%d passed, %d failed", passed, failed))
  os.exit(failed == 0 and 0 or 1)
end

function T.copy(t, over)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  for k, v in pairs(over or {}) do c[k] = v end
  return c
end

-- Radiation config with no storm during a test.
function T.noStorms(over)
  return T.copy(T.RadC, T.copy({ FIRST_WARNING_AT_SEC = 1e9 }, over))
end

-- A "still" station: no drinking, breathing, power loads, solar, plant
-- growth or storms, so a test sees only the arrow it checks.
function T.stillConfigs(over, airOver, humanOver, radOver)
  return {
    config = T.copy(T.C, T.copy({
      CREW_DRINK_PER_SEC = 0, BASE_LOAD_PER_SEC = 0, SOLAR_MAX_PER_SEC = 0, SOLAR_AIM_DECAY_PER_SEC = 0,
      GREENHOUSE_GROWTH_PER_SEC = 0, GREENHOUSE_WATER_PER_SEC = 0, FERTILIZER_USE_PER_SEC = 0,
      GREENHOUSE_PUMP_LOAD_PER_SEC = 0, GREENHOUSE_LAMP_LOAD_PER_SEC = 0,
    }, over)),
    airConfig = T.copy(T.AirC, T.copy({ ASTRONAUT_O2_USE_PER_SEC = 0, ASTRONAUT_CO2_MAKE_PER_SEC = 0 }, airOver)),
    humanConfig = T.copy(T.HumanC, humanOver),
    radiationConfig = T.noStorms(radOver),
  }
end
function T.still(over, airOver, humanOver, radOver)
  return LifeSupport.new(T.stillConfigs(over, airOver, humanOver, radOver))
end

function T.setAir(ls, o2, co2)
  ls.air.oxygenPercent, ls.air.carbonDioxidePercent = o2, co2
  ls.air:_refresh(); ls:_afterAction()
end

function T.run(ls, seconds, step)
  step = step or 0.1
  for _ = 1, math.floor(seconds / step + 0.5) do ls:update(step) end
end

return T
