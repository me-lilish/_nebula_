-- Integration tests for the life-support flows of the mission coordinator:
-- every schematic arrow, machine inputs/outputs, missing-input and no-power
-- behaviour, one shared battery, air/dust independence.
-- (Time, food, waste, human needs, radiation and game over: test_mission.lua)
-- Run from the repository root:  lua tests/test_life_support.lua

package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq, near = T.test, T.eq, T.near
local C, AirC, DustC = T.C, T.AirC, T.DustC
local still, setAir, run = T.still, T.setAir, T.run
local LifeSupport = require("src.life_support")

local function totalWater(ls)
  return ls.potableWater + ls.processWater + ls.urine + ls.wastewater + ls.brine
end

------------------------------------------------------------------------------
-- 1-2. Crew consumes water and oxygen; produces urine, condensate, CO2
------------------------------------------------------------------------------
test("crew drinks potable water", function()
  local ls = LifeSupport.new()
  run(ls, 60)
  near(ls.potableWater, C.START_POTABLE_WATER - 60 * C.CREW_DRINK_PER_SEC - ls.config.GREENHOUSE_WATER_PER_SEC * 60, 1e-6)
end)
test("drinking makes bladder urine and humidity condensate", function()
  local ls = still({ CREW_DRINK_PER_SEC = 0.1 })
  run(ls, 10)
  near(ls.human.bladder, 1.0 * C.CREW_URINE_SHARE)
  near(ls.wastewater, 1.0 * C.CREW_HUMIDITY_SHARE)
  eq(ls.urine, 0, "urine reaches the tank only through the Toilet")
end)
test("one gallon a day: daily water use is about 50 u", function()
  -- drinking + about four meals + about three toilet uses
  local perDay = C.CREW_DRINK_PER_SEC * 24 * 60 + 4 * C.MEAL_WATER + 3 * C.TOILET_HYGIENE_WATER
  if perDay < 30 or perDay > 55 then error("daily water use " .. perDay) end
end)
test("crew breathing: O2 falls, CO2 rises", function()
  local ls = LifeSupport.new()
  run(ls, 10)
  near(ls.air.oxygenPercent, AirC.START_O2_PERCENT - 10 * AirC.ASTRONAUT_O2_USE_PER_SEC)
  near(ls.air.carbonDioxidePercent, AirC.START_CO2_PERCENT + 10 * AirC.ASTRONAUT_CO2_MAKE_PER_SEC)
end)
test("no potable water -> crew cannot drink", function()
  local ls = still({ CREW_DRINK_PER_SEC = 0.1 }); ls.potableWater = 0; ls:_afterAction()
  run(ls, 5)
  eq(ls.potableWater, 0); eq(ls.human.bladder, 0)
end)

------------------------------------------------------------------------------
-- 3-6. Water Recovery
------------------------------------------------------------------------------
test("Toilet -> urine tank -> Urine Processor", function()
  local ls = still(); ls.human.bladder = 6
  local ok, _, mode = ls:useToilet()
  eq(ok, true); eq(mode, "used"); eq(ls.urine, 6); eq(ls.human.bladder, 0)
end)
test("Urine Processor -> processed water + brine", function()
  local ls = still(); ls.urine = 10
  local amt, water, brine = ls:_urineStage()
  eq(amt, 10); near(water, 10 * C.URINE_WATER_FRACTION); near(brine, 10 * (1 - C.URINE_WATER_FRACTION))
  near(ls.wastewater, water); near(ls.brine, brine)
end)
test("Brine Processor -> recovered water + brine solids", function()
  local ls = still(); ls.brine = 5
  local amt, water, solids = ls:_brineStage()
  eq(amt, 5); near(water, 5 * C.BRINE_WATER_FRACTION); near(ls.wasteSolids, solids)
  near(ls.wastewater, water)
end)
test("Water Processor -> potable + process water (configured share)", function()
  local ls = still(); ls.potableWater, ls.processWater, ls.wastewater = 10, 10, 20
  local amt, toPotable, toProcess = ls:_waterStage()
  eq(amt, 20); near(toProcess, 20 * C.PROCESS_WATER_SHARE); near(toPotable, 20 - toProcess)
end)
test("Water Processor spills into the other tank when one is full", function()
  local ls = still(); ls.potableWater, ls.processWater, ls.wastewater = 100, 50, 20
  local _, toPotable, toProcess = ls:_waterStage()
  eq(toPotable, 0); eq(toProcess, 20)
end)
test("one Water Recovery click runs urine -> brine -> water processor", function()
  local ls = still(); ls.urine = 10; ls.potableWater, ls.processWater = 0, 0
  local ok, _, r = ls:runWaterRecycler()
  eq(ok, true); eq(r.urine, 10)
  near(r.brine, 10 * (1 - C.URINE_WATER_FRACTION))
  near(r.cleaned, r.urineWater + r.brineWater)
  near(ls.potableWater + ls.processWater, r.cleaned)
end)
test("Water Recovery conserves water except brine solids", function()
  local ls = still(); ls.urine, ls.brine, ls.wastewater = 30, 4, 12
  local before = totalWater(ls)
  assert(ls:runWaterRecycler())
  near(totalWater(ls) + ls.wasteSolids, before)
end)
test("humidity condensate -> Water Processor -> potable water", function()
  local ls = still({ CREW_DRINK_PER_SEC = 0.2 }); ls.potableWater = 50
  run(ls, 50)                                   -- condensate builds up
  local condensate = ls.wastewater
  if condensate <= 0 then error("no condensate") end
  local potable = ls.potableWater
  assert(ls:runWaterRecycler())
  near(ls.potableWater - potable, condensate * (1 - C.PROCESS_WATER_SHARE))
end)
test("process water supplies the Oxygen Maker", function()
  local ls = still(); ls.processWater = 0; ls.wastewater = 20
  eq(select(2, ls:canRunOxygenMaker()), "no_water")
  assert(ls:runWaterRecycler())
  eq(ls:canRunOxygenMaker(), true)
end)
test("Water Recovery: nothing to recycle / tanks full / no power", function()
  local ls = still()
  eq(select(2, ls:runWaterRecycler()), "nothing_to_recycle")
  ls.potableWater, ls.processWater, ls.wastewater = 100, 100, 10
  eq(select(2, ls:runWaterRecycler()), "tanks_full")
  ls.processWater, ls.battery = 50, 1
  eq(select(2, ls:runWaterRecycler()), "no_power"); eq(ls.wastewater, 10)
end)
test("Water Tank valve: potable -> process water", function()
  local ls = still(); ls.processWater = 20
  local ok, _, moved = ls:useWaterTank()
  eq(ok, true); eq(moved, C.WATER_TANK_TRANSFER)
  eq(ls.potableWater, C.START_POTABLE_WATER - moved); eq(ls.processWater, 20 + moved)
  ls.potableWater = 5
  eq(select(2, ls:useWaterTank()), "no_water")
  ls.potableWater, ls.processWater = 50, 100
  eq(select(2, ls:useWaterTank()), "tanks_full")
end)

------------------------------------------------------------------------------
-- 7. Oxygen Maker: process water + power -> O2 + hydrogen
------------------------------------------------------------------------------
test("Oxygen Maker uses process water and battery, makes O2 and hydrogen", function()
  local ls = still()
  local o2, water, bat, potable = ls.air.oxygenPercent, ls.processWater, ls.battery, ls.potableWater
  assert(ls:runOxygenMaker())
  near(ls.air.oxygenPercent, o2 + C.OXYGEN_MAKER_O2_PERCENT)
  near(ls.processWater, water - C.OXYGEN_MAKER_WATER_USE)
  near(ls.battery, bat - C.OXYGEN_MAKER_POWER_COST)
  near(ls.hydrogen, C.OXYGEN_MAKER_H2_UNITS)
  eq(ls.potableWater, potable); eq(ls.oxygenCanisters, nil, "no oxygen canisters")
end)
test("Oxygen Maker without water or power does nothing", function()
  local ls = still(); ls.processWater = 0
  local o2 = ls.air.oxygenPercent
  eq(select(2, ls:runOxygenMaker()), "no_water"); eq(ls.air.oxygenPercent, o2)
  ls.processWater, ls.battery = 10, 0.5
  eq(select(2, ls:runOxygenMaker()), "no_power"); eq(ls.processWater, 10); eq(ls.hydrogen, 0)
end)
test("extra hydrogen beyond storage is vented overboard", function()
  local ls = still(); ls.hydrogen = C.HYDROGEN_MAX
  assert(ls:runOxygenMaker())
  eq(ls.hydrogen, C.HYDROGEN_MAX); near(ls.hydrogenVented, C.OXYGEN_MAKER_H2_UNITS)
end)

------------------------------------------------------------------------------
-- 8. CO2 Cleaner: cabin CO2 -> captured CO2 (never disappears)
------------------------------------------------------------------------------
test("CO2 Cleaner moves cabin CO2 into storage", function()
  local ls = still(); setAir(ls, 21.0, 0.9)
  local bat = ls.battery
  assert(ls:runCO2Cleaner())
  near(ls.air.carbonDioxidePercent, 0.9 - C.CO2_CLEANER_REMOVE_PERCENT)
  near(ls.capturedCO2, C.CO2_CLEANER_REMOVE_PERCENT * C.CO2_UNITS_PER_PERCENT)
  near(ls.battery, bat - C.CO2_CLEANER_POWER_COST)
  eq(ls.air.oxygenPercent, 21.0)
end)
test("captured CO2 is conserved (cabin + storage)", function()
  local ls = still(); setAir(ls, 21.0, 0.8)
  local total = ls.air.carbonDioxidePercent * C.CO2_UNITS_PER_PERCENT + ls.capturedCO2
  assert(ls:runCO2Cleaner())
  near(ls.air.carbonDioxidePercent * C.CO2_UNITS_PER_PERCENT + ls.capturedCO2, total)
end)
test("CO2 Cleaner: cooldown, storage full, no power", function()
  local ls = still(); setAir(ls, 21.0, 0.9)
  assert(ls:runCO2Cleaner())
  eq(select(2, ls:runCO2Cleaner()), "cooldown")
  run(ls, C.CO2_CLEANER_COOLDOWN_SEC)
  ls.capturedCO2 = C.CAPTURED_CO2_MAX
  eq(select(2, ls:runCO2Cleaner()), "storage_full")
  ls.capturedCO2, ls.battery = 0, 0
  eq(select(2, ls:runCO2Cleaner()), "no_power")
end)

------------------------------------------------------------------------------
-- 9-10. CO2 Recycler: CO2 + hydrogen + power -> water + methane (vented)
------------------------------------------------------------------------------
test("CO2 Recycler makes water for the Water Processor and vents methane", function()
  local ls = still(); ls.capturedCO2, ls.hydrogen = 5, 5
  local bat = ls.battery
  assert(ls:runCO2Recycler())
  near(ls.capturedCO2, 5 - C.CO2_RECYCLER_CO2_USE); near(ls.hydrogen, 5 - C.CO2_RECYCLER_H2_USE)
  near(ls.wastewater, C.CO2_RECYCLER_WATER_OUT); near(ls.methaneVented, C.CO2_RECYCLER_METHANE_OUT)
  near(ls.battery, bat - C.CO2_RECYCLER_POWER_COST)
end)
test("CO2 Recycler water reaches the clean tanks through the Water Processor", function()
  local ls = still(); ls.capturedCO2, ls.hydrogen, ls.potableWater, ls.processWater = 5, 5, 0, 0
  assert(ls:runCO2Recycler()); assert(ls:runWaterRecycler())
  near(ls.potableWater + ls.processWater, C.CO2_RECYCLER_WATER_OUT)
end)
test("CO2 Recycler needs CO2, hydrogen, room and power", function()
  local ls = still(); ls.hydrogen = 5
  eq(select(2, ls:runCO2Recycler()), "no_co2")
  ls.capturedCO2, ls.hydrogen = 5, 0
  eq(select(2, ls:runCO2Recycler()), "no_hydrogen")
  ls.hydrogen, ls.wastewater = 5, C.TANK_MAX
  eq(select(2, ls:runCO2Recycler()), "wastewater_full")
  ls.wastewater, ls.battery = 0, 0
  eq(select(2, ls:runCO2Recycler()), "no_power"); eq(ls.methaneVented, 0)
end)
test("full air loop from the very first uses", function()
  local ls = still(); setAir(ls, 19.0, 0.9)
  assert(ls:runOxygenMaker())        -- water -> O2 + hydrogen
  assert(ls:runCO2Cleaner())         -- one use captures enough CO2
  assert(ls:runCO2Recycler())        -- CO2 + H2 -> water
  near(ls.wastewater, C.CO2_RECYCLER_WATER_OUT)
end)

------------------------------------------------------------------------------
-- 11. Trace Air Cleaner / dust independence
------------------------------------------------------------------------------
test("Trace Air Cleaner removes cabin dust using the shared battery", function()
  local ls = still(); ls.dust:addCabinDust(60)
  local bat = ls.battery
  assert(ls:runTraceAirCleaner())
  eq(ls.dust.cabinDust, 0); near(ls.battery, bat - DustC.FILTER_POWER_COST)
  ls.dust:addCabinDust(60); ls.battery = 1
  eq(select(2, ls:canRunTraceAirCleaner()), "no_power")
  eq(select(2, ls:runTraceAirCleaner()), "no_power"); eq(ls.dust.cabinDust, 60)
end)
test("dust actions never change O2, CO2 or the air score", function()
  local ls = still(); setAir(ls, 20.3, 0.62); ls.dust:addSuitDust(60)
  local o2, co2, q = ls.air.oxygenPercent, ls.air.carbonDioxidePercent, ls.air.airQuality
  ls:enterCabin(); ls:runTraceAirCleaner(); ls:useSuitDustOff(); ls.dust:addCabinDust(30)
  run(ls, 3)
  eq(ls.air.oxygenPercent, o2); eq(ls.air.carbonDioxidePercent, co2); eq(ls.air.airQuality, q)
end)
test("air machines never change dust; dust never feeds air status", function()
  local ls = still(); setAir(ls, 19.0, 0.9); ls.dust:addCabinDust(40)
  ls:runOxygenMaker(); ls:runCO2Cleaner(); ls:runCO2Recycler()
  eq(ls.dust.cabinDust, 40)
  ls.dust:addCabinDust(60); setAir(ls, 21, 0.04)
  eq(ls.air.airStatus, "good"); eq(ls.dust:isCritical(), true)
end)
test("cabin dust never rises with time on its own", function()
  local ls = LifeSupport.new({ radiationConfig = T.noStorms() })
  run(ls, 300)
  eq(ls.dust.cabinDust, 0)
end)
test("dirty airlock entry contaminates once; Dust-Off prevents it", function()
  local ls = still(); ls.dust:addSuitDust(60)
  eq(ls:enterCabin(), "dirty"); eq(ls.dust.cabinDust, 60); eq(ls:enterCabin(), nil); eq(ls.dust.cabinDust, 60)
  local ls2 = still(); ls2.dust:addSuitDust(60)
  assert(ls2:useSuitDustOff()); eq(ls2:enterCabin(), "clean"); eq(ls2.dust.cabinDust, 0)
end)

------------------------------------------------------------------------------
-- One battery; checks never change anything
------------------------------------------------------------------------------
test("there is exactly one power pool", function()
  local ls = LifeSupport.new()
  eq(ls.air.power, nil); eq(ls.power, nil)
  eq(ls.dust.power, ls, "dust spends through the coordinator")
end)
test("canX checks never change state", function()
  local ls = still(); setAir(ls, 19.0, 0.9); ls.urine = 10; ls.capturedCO2, ls.hydrogen = 5, 5
  local snap = { ls.battery, ls.processWater, ls.urine, ls.capturedCO2, ls.hydrogen, ls.air.oxygenPercent, ls.food }
  for _, fn in ipairs({ "canRunOxygenMaker", "canRunCO2Cleaner", "canRunCO2Recycler", "canRunWaterRecycler",
      "canRunTraceAirCleaner", "canUseSuitDustOff", "canUseWaterTank", "canUseToilet", "canEatMeal",
      "canHarvestGreenhouse", "canStoreCrops", "canRunCompost", "canAimSolar", "canLoadRegolith",
      "canDeployShields", "canToggleSleep", "canTogglePowerSaver" }) do
    ls[fn](ls)
  end
  local now = { ls.battery, ls.processWater, ls.urine, ls.capturedCO2, ls.hydrogen, ls.air.oxygenPercent, ls.food }
  for i = 1, #snap do eq(now[i], snap[i]) end
end)

T.finish()
