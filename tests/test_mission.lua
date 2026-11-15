-- Mission-level tests: time model + frame-rate independence, power, food,
-- waste, human needs, radiation, the shared emergency timer, game over and
-- reset - all through the one coordinator.
-- Run from the repository root:  lua tests/test_mission.lua

package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq, near = T.test, T.eq, T.near
local C, HC, RC = T.C, T.HumanC, T.RadC
local still, setAir, run, copy = T.still, T.setAir, T.run, T.copy
local LifeSupport = require("src.life_support")
local HOUR = C.REAL_SECONDS_PER_GAME_HOUR -- real seconds per game hour
-- Needs keep ticking during long tests; these switch off their health loss
-- so a test sees only the effect it checks.
local CALM = { HUNGER_HEALTH_LOSS_PER_SEC = 0, BATHROOM_HEALTH_LOSS_PER_SEC = 0, FATIGUE_HEALTH_LOSS_PER_SEC = 0 }

-- Every number that describes the mission state.
local function snapshot(ls)
  local h, r = ls.human, ls.radiation
  local s = {
    ls.missionTime, ls.battery, ls.solarAim, ls.powerGenPerSec, ls.powerUsePerSec,
    ls.potableWater, ls.processWater, ls.urine, ls.wastewater, ls.brine, ls.capturedCO2, ls.hydrogen,
    ls.food, ls.crops, ls.plantScraps, ls.fertilizer, ls.growth, ls.toiletUses, ls.sealedWaste,
    ls.salvageParts, ls.criticalTimer, ls.co2CleanerCooldown, ls.air.oxygenPercent,
    ls.air.carbonDioxidePercent, ls.dust.cabinDust, h.health, h.timeSinceFood, h.timeSinceToilet,
    h.bladder, h:sleepInLastDay(), r.timer, r:deployedUnits(), ls.missionFailed and 1 or 0,
  }
  for _, id in ipairs(r.order) do s[#s + 1] = r.sections[id].integrity end
  return s
end
local function sameState(a, b, label)
  local sa, sb = snapshot(a), snapshot(b)
  for i = 1, #sa do
    if math.abs(sa[i] - sb[i]) > 1e-9 then
      error((label or "") .. " field " .. i .. " differs: " .. sa[i] .. " vs " .. sb[i], 2)
    end
  end
end

------------------------------------------------------------------------------
-- Time model
------------------------------------------------------------------------------
test("6 real seconds = 1 game hour; 24 game hours = 1 day", function()
  local ls = LifeSupport.new()
  local d, h, m = ls:clock(); eq(d, 1); eq(h, C.START_HOUR); eq(m, 0)
  run(ls, HOUR, 1); d, h, m = ls:clock(); eq(d, 1); eq(h, 7); eq(m, 0)
  run(ls, HOUR / 2, 1); d, h, m = ls:clock(); eq(h, 7); eq(m, 30)
  local ls2 = still()
  ls2:update(18 * HOUR); d, h = ls2:clock(); eq(d, 2); eq(h, 0)
  ls2:update(6 * HOUR); d, h = ls2:clock(); eq(d, 2); eq(h, C.START_HOUR)
end)
test("the Sun is up 06:00-22:00 only", function()
  local ls = still()
  eq(ls:isSunUp(), true)
  ls:update(16 * HOUR - 0.1); eq(ls:isSunUp(), true, "21:59")
  ls:update(0.1); eq(ls:isSunUp(), false, "22:00")
  ls:update(8 * HOUR); eq(ls:isSunUp(), true, "06:00 next day")
end)
test("a 60 s update equals sixty 1 s updates (and 1/60 s frames)", function()
  local a, b, c, d = LifeSupport.new(), LifeSupport.new(), LifeSupport.new(), LifeSupport.new()
  a:update(60)
  for _ = 1, 60 do b:update(1) end
  for _ = 1, 3600 do c:update(1 / 60) end
  for _ = 1, 600 do d:update(0.1) end
  sameState(a, b, "60 vs 60x1"); sameState(a, c, "60 vs 3600 frames"); sameState(a, d, "60 vs 600x0.1")
end)
test("frame-chunk invariance across a day, a storm and an emergency", function()
  local function play(chunk)
    local ls = LifeSupport.new()
    local t = 0
    while t < 30 * 60 - 1e-9 do ls:update(chunk); t = t + chunk end
    return ls
  end
  local a, b = play(60), play(0.5)
  sameState(a, b, "30 min")
  eq(a.missionFailed, true, "an ignored station fails")
  eq(a.failureSystem, b.failureSystem)
end)
test("time smaller than one tick is kept, not lost", function()
  local ls = still()
  ls:update(0.05); eq(ls.missionTime, 0)
  ls:update(0.05); near(ls.missionTime, 0.1)
end)
test("cooldowns finish exactly - no float leftovers", function()
  local ls = still(); setAir(ls, 21, 0.9)
  assert(ls:runCO2Cleaner())
  for _ = 1, 50 do ls:update(0.1) end
  eq(ls.co2CleanerCooldown, 0); eq(ls:canRunCO2Cleaner(), true)
  assert(ls:runCO2Cleaner()); ls:update(C.CO2_CLEANER_COOLDOWN_SEC)
  eq(ls.co2CleanerCooldown, 0)
end)
test("the emergency timer completes exactly at 30 s however time is chopped", function()
  for _, chunk in ipairs({ 30, 1, 0.1, 1 / 60 }) do
    local ls = still(); setAir(ls, 17, 0.04)
    local n = math.floor(29.9 / chunk + 1e-6)
    for _ = 1, n do ls:update(chunk) end
    ls:update(29.9 - n * chunk)
    eq(ls.missionFailed, false, "29.9 s chunk " .. chunk)
    ls:update(0.1)
    eq(ls.missionFailed, true, "30 s chunk " .. chunk)
  end
end)

------------------------------------------------------------------------------
-- Power: solar arrays -> battery -> machines
------------------------------------------------------------------------------
test("solar arrays charge the battery in sunlight", function()
  local ls = still({ SOLAR_MAX_PER_SEC = 0.2 }); ls.battery = 50
  run(ls, 10)
  near(ls.battery, 52, 1e-6)
end)
test("no solar power at night", function()
  local ls = still({ SOLAR_MAX_PER_SEC = 0.2 }); ls:update(16 * HOUR); ls.battery = 50
  run(ls, 10)
  eq(ls.battery, 50)
end)
test("panels drift off the Sun; Solar Array Control re-aims them", function()
  local ls = still({ SOLAR_AIM_DECAY_PER_SEC = 0.15, SOLAR_MAX_PER_SEC = 0.2 })
  eq(select(2, ls:canAimSolar()), "already_aimed")
  run(ls, 60)
  near(ls.solarAim, 91); near(ls:solarPerSec(), 0.2 * 0.91)
  assert(ls:aimSolar()); eq(ls.solarAim, 100)
  ls:update(6 * HOUR) -- 16:00 + 6 h = 22:00, sunset
  eq(select(2, ls:canAimSolar()), "night")
end)
test("base load drains the battery; battery stays within 0-100", function()
  local ls = still({ BASE_LOAD_PER_SEC = 0.5 }); ls.battery = 3
  run(ls, 10)
  eq(ls.battery, 0)
  local ls2 = still({ SOLAR_MAX_PER_SEC = 5 }); ls2.battery = 99
  run(ls2, 5); eq(ls2.battery, 100)
end)
test("power status thresholds", function()
  local ls = still()
  for _, case in ipairs({ { 100, "good" }, { 70, "good" }, { 69.9, "caution" }, { 50, "caution" },
      { 49.9, "danger" }, { 1, "danger" }, { 0, "critical" } }) do
    ls.battery = case[1]; ls:_afterAction()
    eq(ls.powerStatus, case[2], "battery " .. case[1])
  end
end)
test("machines fail honestly without power", function()
  local ls = still(); ls.battery = 0; setAir(ls, 19, 0.9)
  eq(select(2, ls:runOxygenMaker()), "no_power")
  eq(select(2, ls:runCO2Cleaner()), "no_power")
  ls.urine = 10
  eq(select(2, ls:runWaterRecycler()), "no_power")
end)
test("Power Saver lowers the load and switches grow lamps off at night", function()
  local ls = still()
  ls:update(16 * 60)
  ls.config.BASE_LOAD_PER_SEC, ls.config.GREENHOUSE_LAMP_LOAD_PER_SEC = 0.1, 0.05
  ls:_updateGreenhouseNeeds()
  local full = ls:loadPerSec()
  local ok, _, on = ls:togglePowerSaver()
  eq(ok, true); eq(on, true)
  if ls:loadPerSec() >= full then error("saver did not lower the load") end
  eq(ls.greenhouseMissing, "no_light")
end)
test("Power Monitor shows generation and consumption per minute", function()
  local ls = LifeSupport.new()
  local fb = ls:getPowerFeedback()
  near(fb.genPerMin, ls:solarPerSec() * 60); near(fb.usePerMin, ls:loadPerSec() * 60)
end)
test("empty battery starts the shared emergency and can fail the mission", function()
  local ls = still(); ls.battery = 0; ls:_afterAction()
  eq(ls:criticalSystems()[1], "power")
  run(ls, C.CRITICAL_TIME_LIMIT)
  eq(ls.failureSystem, "power"); eq(ls.failureCause, "The batteries ran out.")
  assert(ls.failureLesson:find("Solar power"))
end)

------------------------------------------------------------------------------
-- Food
------------------------------------------------------------------------------
test("food storage starts between 50 and 100%; caution below 50", function()
  local ls = still()
  assert(ls.food >= 50 and ls.food <= 100)
  ls.food = 49; ls:_afterAction(); eq(ls.foodStatus, "caution")
  ls.food = 19; ls:_afterAction(); eq(ls.foodStatus, "danger")
end)
test("Food Station: stored food + water -> meal, hunger resets", function()
  local ls = still(); ls.human.timeSinceFood = 700
  local food, water = ls.food, ls.potableWater
  assert(ls:eatMeal())
  eq(ls.food, food - C.MEAL_FOOD); eq(ls.potableWater, water - C.MEAL_WATER)
  eq(ls.human.timeSinceFood, 0)
  eq(select(2, ls:eatMeal()), "just_ate")
  run(ls, C.MEAL_MIN_GAP_SEC); ls.food = 2
  eq(select(2, ls:eatMeal()), "no_food")
  ls.food, ls.potableWater = 50, 1
  eq(select(2, ls:eatMeal()), "no_water")
end)
test("greenhouse grows gradually with power, light, water and fertilizer", function()
  local ls = still({ GREENHOUSE_GROWTH_PER_SEC = 1, GREENHOUSE_WATER_PER_SEC = 0.01, FERTILIZER_USE_PER_SEC = 0.1 })
  local water, fert = ls.potableWater, ls.fertilizer
  run(ls, 10)
  near(ls.growth, 10); near(ls.potableWater, water - 0.1); near(ls.fertilizer, fert - 1)
  eq(select(2, ls:harvestGreenhouse()), "growing")
end)
test("greenhouse stops without each input", function()
  local function check(setup, reason)
    local ls = still({ GREENHOUSE_GROWTH_PER_SEC = 1 })
    setup(ls); ls.growth = 0; ls:update(0.1); local g = ls.growth
    run(ls, 5)
    eq(ls.growth, g, reason); eq(ls.greenhouseMissing, reason)
  end
  check(function(ls) ls.battery = 0 end, "no_power")
  check(function(ls) ls:update(16 * 60); ls.powerSaver = true end, "no_light")
  check(function(ls) ls.potableWater = 0 end, "no_water")
  check(function(ls) ls.fertilizer = 0 end, "no_fertilizer")
end)
test("grow lamps give light at night when Power Saver is off", function()
  local ls = still({ GREENHOUSE_GROWTH_PER_SEC = 1 }); ls:update(16 * 60); ls.growth = 0
  local g = ls.growth; run(ls, 5)
  near(ls.growth, g + 5)
end)
test("harvest -> crops + plant scraps; Food Storage stores crops", function()
  local ls = still(); ls.growth = 100; ls.food = 40
  assert(ls:harvestGreenhouse())
  eq(ls.crops, C.HARVEST_CROPS); eq(ls.plantScraps, C.HARVEST_PLANT_SCRAPS); eq(ls.growth, 0)
  local ok, _, moved = ls:storeCrops()
  eq(ok, true); eq(moved, C.HARVEST_CROPS); eq(ls.food, 40 + C.HARVEST_CROPS); eq(ls.crops, 0)
  eq(select(2, ls:storeCrops()), "no_crops")
end)
test("Compost: plant scraps -> fertilizer (plant waste only)", function()
  local ls = still(); ls.plantScraps = C.COMPOST_BATCH; ls.fertilizer = 10
  ls.sealedWaste, ls.urine = 30, 20
  assert(ls:runCompost())
  eq(ls.plantScraps, 0); eq(ls.fertilizer, 10 + C.COMPOST_FERTILIZER_OUT)
  eq(ls.sealedWaste, 30, "human waste is never compost"); eq(ls.urine, 20)
  eq(select(2, ls:runCompost()), "no_scraps")
end)
test("fertilizer only helps the greenhouse", function()
  local ls = still(); ls.plantScraps = 10
  local food, water = ls.food, ls.potableWater
  assert(ls:runCompost())
  eq(ls.food, food); eq(ls.potableWater, water)
end)
test("full food loop: grow -> harvest -> store -> eat; scraps -> compost -> grow", function()
  local ls = still({ GREENHOUSE_GROWTH_PER_SEC = 10, FERTILIZER_USE_PER_SEC = 1 })
  ls.fertilizer = 5
  run(ls, 10)                                   -- fertilizer runs out mid-growth
  eq(ls.greenhouseMissing, "no_fertilizer")
  ls.plantScraps = 10; assert(ls:runCompost())  -- scraps -> fertilizer
  run(ls, 10); eq(ls.growth, 100)
  assert(ls:harvestGreenhouse()); assert(ls:storeCrops())
  ls.human.timeSinceMeal = 999; assert(ls:eatMeal())
end)

------------------------------------------------------------------------------
-- Waste
------------------------------------------------------------------------------
test("toilet holds 3 uses, then must seal the waste", function()
  local ls = still()
  for _ = 1, C.TOILET_CAPACITY_USES do
    local ok, _, mode = ls:useToilet(); eq(ok, true); eq(mode, "used")
  end
  eq(ls:toiletNeedsSealing(), true); eq(ls.waterStatus, "caution")
  local ok, _, mode = ls:useToilet()
  eq(ok, true); eq(mode, "sealed"); eq(ls.toiletUses, 0); eq(ls.sealedWaste, C.SEALED_WASTE_PER_SEAL)
end)
test("toilet use sends urine to Water Recovery and hygiene water to used water", function()
  local ls = still(); ls.human.bladder = 5
  local potable = ls.potableWater
  assert(ls:useToilet())
  eq(ls.urine, 5); eq(ls.potableWater, potable - C.TOILET_HYGIENE_WATER)
  eq(ls.wastewater, C.TOILET_HYGIENE_WATER)
  eq(ls.human.timeSinceToilet, 0)
end)
test("sealing needs power and storage space", function()
  local ls = still(); ls.toiletUses = C.TOILET_CAPACITY_USES; ls.battery = 0
  eq(select(2, ls:useToilet()), "no_power")
  ls.battery, ls.sealedWaste = 50, 100
  eq(select(2, ls:useToilet()), "waste_storage_full")
end)
test("a toilet left full too long hurts hygiene and health", function()
  local ls = still(nil, nil, CALM); ls.toiletUses = C.TOILET_CAPACITY_USES; ls:_afterAction()
  run(ls, C.HYGIENE_GRACE_SEC - 1); eq(ls.hygieneDanger, false)
  run(ls, 1); eq(ls.hygieneDanger, true); eq(ls.waterStatus, "danger")
  local hp = ls.human.health
  run(ls, 10); near(ls.human.health, hp - 10 * HC.HYGIENE_HEALTH_LOSS_PER_SEC)
end)
test("salvage parts are tracked apart from biological waste", function()
  local ls = still(); ls:triggerRadiationWarning()
  run(ls, RC.WARNING_LEAD_SEC + 30)
  if ls.salvageParts <= 0 then error("no salvage from damage") end
  eq(ls.fertilizer, C.FERTILIZER_START); eq(ls.sealedWaste, 0); eq(ls.food, C.FOOD_START)
end)

------------------------------------------------------------------------------
-- Human needs through the coordinator
------------------------------------------------------------------------------
test("hunger: warning at 10 min, danger at 15 min, then gradual health loss", function()
  local ls = still()
  run(ls, HC.HUNGER_WARNING_SEC - 0.1); eq(ls.human:hungerStatus(), "ok")
  run(ls, 0.1); eq(ls.human:hungerStatus(), "warning")
  ls.human.health = 80
  ls.human.timeSinceFood = HC.HUNGER_DANGER_SEC; ls.human.timeSinceToilet = 0
  run(ls, 10)
  near(ls.human.health, 80 - 10 * HC.HUNGER_HEALTH_LOSS_PER_SEC)
  ls.human.timeSinceMeal = 999; assert(ls:eatMeal())
  eq(ls.human:hungerStatus(), "ok")
end)
test("health 0 starts the shared emergency; game over only after the timer", function()
  local rec = still(); rec.human.health = 0; rec.human:_refresh(); rec:_afterAction()
  run(rec, 1); eq(rec.missionFailed, false); eq(rec.criticalTimer, 0, "recovers when needs are met")
  local ls = still(); ls.human.health = 0; ls.human.timeSinceFood = 2000 -- still starving
  ls.human:_refresh(); ls:_afterAction()
  eq(ls:isAnyCritical(), true); eq(ls.missionFailed, false)
  run(ls, C.CRITICAL_TIME_LIMIT)
  eq(ls.failureSystem, "health"); assert(ls.failureLesson:find("food, sleep"))
end)
test("the bunk fast-forwards a full night's sleep; no sleeping in an emergency", function()
  local ls = still()
  local ok, _, state = ls:toggleSleep(); eq(ok, true); eq(state, "slept")
  near(ls.human:sleepInLastDay(), 8 * HOUR); eq(ls.human.isSleeping, false)
  setAir(ls, 17, 0.04); ls:update(0.1)
  eq(select(2, ls:toggleSleep()), "emergency")
end)

------------------------------------------------------------------------------
-- Radiation through the coordinator
------------------------------------------------------------------------------
test("first warning comes on schedule with two minutes to prepare", function()
  local ls = still(nil, nil, nil, { FIRST_WARNING_AT_SEC = 180 })
  run(ls, 179.9); eq(ls.radiation.phase, "clear")
  run(ls, 0.1); eq(ls.radiation.phase, "warning")
  local news = ls:popEvents(); assert(news[#news]:find("Radiation warning"))
  near(ls.radiation:timeToStorm(), 120)
  run(ls, 120); eq(ls.radiation.phase, "storm")
end)
test("load + deploy regolith shields before the storm: crew stays safe", function()
  local ls = still(nil, nil, CALM); ls:triggerRadiationWarning()
  for _ = 1, 3 do assert(ls:loadRegolith()); assert(ls:deployShields()) end
  eq(ls.radiation:deployedUnits(), 9)
  eq(select(2, ls:loadRegolith()), "all_shielded")
  run(ls, RC.WARNING_LEAD_SEC + 10)
  eq(ls.radiation.phase, "storm"); eq(ls:isAnyCritical(), false); eq(ls.human.health, 100)
  eq(ls.salvageParts, 0, "shielded sections are not damaged")
end)
test("unshielded crew: health loss + shared emergency; shields mid-storm recover", function()
  local ls = still(nil, nil, CALM); ls:triggerRadiationWarning()
  run(ls, RC.WARNING_LEAD_SEC + 10)
  eq(ls:criticalSystems()[1], "radiation")
  near(ls.human.health, 100 - 10 * HC.RADIATION_HEALTH_LOSS_PER_SEC, 0.06) -- storm tick counts too
  assert(ls:loadRegolith()); assert(ls:deployShields())
  eq(ls.radiation.sections.crew.shielded, true)
  eq(ls.criticalTimer, 0, "timer resets the moment the crew is shielded")
end)
test("unshielded sections are damaged -> salvage parts and a little dust", function()
  local ls = still(); ls:triggerRadiationWarning()
  assert(ls:loadRegolith()); assert(ls:deployShields())       -- 3 of 9 shielded
  run(ls, RC.WARNING_LEAD_SEC + RC.STORM_DURATION_SEC)
  eq(ls.salvageParts, 6 * RC.DAMAGE_SALVAGE_PARTS)
  eq(ls.dust.cabinDust, 6 * RC.DAMAGE_CABIN_DUST)
end)
test("storm ends -> clear again, emergency over, health recovers", function()
  local ls = still(nil, nil, CALM); ls:triggerRadiationWarning()
  run(ls, RC.WARNING_LEAD_SEC + 5)
  assert(ls:loadRegolith()); assert(ls:deployShields())
  run(ls, RC.STORM_DURATION_SEC)
  eq(ls.radiation.phase, "clear"); eq(ls.criticalTimer, 0)
  -- a meal, the bathroom and a night's sleep: no need is unmet any more
  ls.human.timeSinceMeal = 999; assert(ls:eatMeal()); assert(ls:useToilet()); assert(ls:toggleSleep())
  local hp = ls.human.health
  run(ls, 10); near(ls.human.health, hp + 10 * HC.HEALTH_REGEN_PER_SEC)
end)
test("unshielded storm long enough fails the mission with a radiation lesson", function()
  local ls = still(); ls:triggerRadiationWarning()
  run(ls, RC.WARNING_LEAD_SEC + C.CRITICAL_TIME_LIMIT)
  eq(ls.missionFailed, true); eq(ls.failureSystem, "radiation")
  assert(ls.failureLesson:find("regolith"))
end)

------------------------------------------------------------------------------
-- Shared emergency timer, game over, reset
------------------------------------------------------------------------------
test("one timer for many critical conditions; priority picks the cause", function()
  local ls = still(); setAir(ls, 17, 1.5); ls.potableWater = 0; ls.battery = 0
  ls.dust:addCabinDust(100); ls:_afterAction()
  eq(#ls:criticalSystems(), 4)
  run(ls, C.CRITICAL_TIME_LIMIT)
  eq(ls.failureSystem, "air"); eq(ls.failureCause, "The cabin air became unsafe to breathe.")
end)
test("timer keeps counting while any condition is critical, resets when none", function()
  local ls = still(); setAir(ls, 17.5, 0.04); ls.potableWater = 0; ls:_afterAction()
  run(ls, 10)
  assert(ls:runOxygenMaker()); near(ls.criticalTimer, 10, "water still critical")
  ls.wastewater = 20; assert(ls:runWaterRecycler())
  eq(ls.criticalTimer, 0)
end)
test("every failure cause has a child-friendly cause and a science lesson", function()
  local cases = {
    { function(ls) setAir(ls, 17, 0.04) end, "air", "The cabin ran out of safe oxygen." },
    { function(ls) setAir(ls, 21, 1.5) end, "air", "Too much carbon dioxide built up in the cabin." },
    { function(ls) ls.potableWater = 0 end, "water", "The crew ran out of clean drinking water." },
    { function(ls) ls.battery = 0 end, "power", "The batteries ran out." },
    { function(ls) ls.dust:addCabinDust(100) end, "dust", "Too much dust entered the cabin." },
    { function(ls) ls.human.health = 0; ls.human.timeSinceFood = 2000; ls.human:_refresh() end, "health",
      "Vulcan's health ran out." },
  }
  for _, case in ipairs(cases) do
    local ls = still(); case[1](ls); ls:_afterAction()
    run(ls, C.CRITICAL_TIME_LIMIT)
    eq(ls.failureSystem, case[2]); eq(ls.failureCause, case[3])
    if not ls.failureLesson or #ls.failureLesson < 10 then error("missing lesson for " .. case[2]) end
  end
end)
test("after game over everything freezes and stations refuse", function()
  local ls = still(); setAir(ls, 17, 0.04); run(ls, 30)
  local t = ls.missionTime
  ls:update(10); eq(ls.missionTime, t)
  for _, fn in ipairs({ "runOxygenMaker", "runCO2Cleaner", "runWaterRecycler", "useToilet", "eatMeal",
      "harvestGreenhouse", "runCompost", "aimSolar", "loadRegolith", "deployShields", "toggleSleep" }) do
    eq(select(2, ls[fn](ls)), "mission_failed", fn)
  end
end)
test("reset restores the whole mission", function()
  local ls = LifeSupport.new(); ls:update(25 * 60)
  ls:reset()
  eq(ls.missionFailed, false); eq(ls.missionTime, 0); eq(ls.criticalTimer, 0)
  eq(ls.battery, C.BATTERY_START); eq(ls.potableWater, C.START_POTABLE_WATER)
  eq(ls.food, C.FOOD_START); eq(ls.growth, 0); eq(ls.toiletUses, 0); eq(ls.salvageParts, 0)
  eq(ls.human.health, HC.HEALTH_START); eq(ls.radiation.phase, "clear"); eq(ls.radiation:deployedUnits(), 0)
  eq(ls.air.oxygenPercent, T.AirC.START_O2_PERCENT); eq(ls.dust.cabinDust, 0)
  local d, h = ls:clock(); eq(d, 1); eq(h, C.START_HOUR)
end)

T.finish()
