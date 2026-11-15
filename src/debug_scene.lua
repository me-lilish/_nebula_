--[[
  Mission debug scene - plain text readout for testing the logic.
  Not final art or UI. Run with:  love . debug

  Station keys:
    G Oxygen Maker   S CO2 Cleaner   C CO2 Recycler   W Water Recovery
    T Trace Air Cleaner   D Suit Dust-Off   E Enter cabin   V Water Tank valve
    K Toilet   H Harvest greenhouse   F Food Storage   M Compost   N Eat
    A Aim solar   B Power Saver   L Load regolith   Z Deploy shields   Y Sleep
  Debug keys:
    1 -1% O2   2 +0.2% CO2   3 +20 cabin dust   4 radiation warning now
    5 skip 60 s   SPACE pause   R reset   Esc quit
]]

local LifeSupport = require("src.life_support")

local Scene = {}
Scene.__index = Scene

function Scene.new()
  local self = setmetatable({}, Scene)
  self.ls = LifeSupport.new()
  self.ls.dust:addSuitDust(self.ls.dust.config.EVA_SUIT_DUST)
  self.paused = false
  self.lastEvent = ""
  self.bigFont = love.graphics.newFont(18)
  self.font = love.graphics.newFont(12)
  return self
end

function Scene:update(dt)
  if not self.paused then self.ls:update(dt) end
  for _, e in ipairs(self.ls:popEvents()) do self.lastEvent = "NEWS: " .. e end
end

local ACTIONS = {
  g = { "Oxygen Maker", "runOxygenMaker" }, s = { "CO2 Cleaner", "runCO2Cleaner" },
  c = { "CO2 Recycler", "runCO2Recycler" }, w = { "Water Recovery", "runWaterRecycler" },
  t = { "Trace Air Cleaner", "runTraceAirCleaner" }, d = { "Suit Dust-Off", "useSuitDustOff" },
  v = { "Water Tank", "useWaterTank" }, k = { "Toilet", "useToilet" },
  h = { "Greenhouse", "harvestGreenhouse" }, f = { "Food Storage", "storeCrops" },
  m = { "Compost", "runCompost" }, n = { "Food Station", "eatMeal" },
  a = { "Solar Array", "aimSolar" }, b = { "Power Saver", "togglePowerSaver" },
  l = { "Regolith Loader", "loadRegolith" }, z = { "Shield Panel", "deployShields" },
  y = { "Sleep Pod", "toggleSleep" },
}

function Scene:keypressed(key)
  local ls = self.ls
  local a = ACTIONS[key]
  if a then
    local ok, reason, extra = ls[a[2]](ls)
    self.lastEvent = a[1] .. (ok and (": done " .. tostring(extra or "")) or (": " .. tostring(reason)))
  elseif key == "e" then
    self.lastEvent = "Enter cabin: " .. tostring(ls:enterCabin())
  elseif key == "1" then
    ls.air:addOxygen(-1); ls:_afterAction()
  elseif key == "2" then
    ls.air:removeCO2(-0.2); ls:_afterAction()
  elseif key == "3" then
    ls.dust:addCabinDust(20); ls:_afterAction()
  elseif key == "4" then
    ls:triggerRadiationWarning()
  elseif key == "5" then
    ls:update(60)
  elseif key == "space" then
    self.paused = not self.paused
  elseif key == "r" then
    ls:reset(); ls.dust:addSuitDust(ls.dust.config.EVA_SUIT_DUST); self.lastEvent = "Reset."
  elseif key == "escape" then
    love.event.quit()
  end
end

function Scene:draw()
  local ls, lg = self.ls, love.graphics
  local air, dust, h, r = ls.air, ls.dust, ls.human, ls.radiation
  lg.clear(0.08, 0.08, 0.12)
  lg.setFont(self.bigFont)
  if ls.missionFailed then
    lg.setColor(0.9, 0.2, 0.2)
    lg.printf("MISSION FAILED (" .. ls.failureSystem .. "): " .. ls.failureMessage, 20, 10, lg.getWidth() - 40)
  elseif ls:isAnyCritical() then
    lg.setColor(0.9, 0.2, 0.2)
    lg.printf(string.format("EMERGENCY %s - %.1f s left", table.concat(ls:criticalSystems(), "+"),
      ls:getCriticalTimeLeft()), 0, 10, lg.getWidth(), "center")
  else
    lg.setColor(0.4, 0.9, 0.5)
    lg.printf("All systems OK", 0, 10, lg.getWidth(), "center")
  end

  local day, hour, minute = ls:clock()
  lg.setFont(self.font)
  lg.setColor(1, 1, 1)
  local lines = {
    string.format("TIME  Day %d %02d:%02d  mission %.1f s  sun %s", day, hour, minute, ls.missionTime, tostring(ls:isSunUp())),
    string.format("AIR   O2 %.2f%%  CO2 %.3f%%  %s  quality %.0f", air.oxygenPercent, air.carbonDioxidePercent, air.airStatus, air.airQuality),
    string.format("WATER potable %.1f  process %.1f  urine %.1f  used %.1f  brine %.1f  status %s",
      ls.potableWater, ls.processWater, ls.urine, ls.wastewater, ls.brine, ls.waterStatus),
    string.format("GAS   captured CO2 %.1f  hydrogen %.1f  | OUT methane %.1f  H2 vented %.1f  brine solids %.2f",
      ls.capturedCO2, ls.hydrogen, ls.methaneVented, ls.hydrogenVented, ls.wasteSolids),
    string.format("WASTE toilet %d/%d  full for %.0f s  sealed %.0f%%  salvage parts %d",
      ls.toiletUses, ls.config.TOILET_CAPACITY_USES, ls.toiletFullTime, ls.sealedWaste, ls.salvageParts),
    string.format("POWER battery %.1f%%  %s  aim %.0f%%  saver %s  gen %.2f/s  use %.2f/s",
      ls.battery, ls.powerStatus, ls.solarAim, tostring(ls.powerSaver), ls.powerGenPerSec, ls.powerUsePerSec),
    string.format("FOOD  stored %.1f  crops %.0f  scraps %.0f  fertilizer %.1f  growth %.1f%%  missing %s",
      ls.food, ls.crops, ls.plantScraps, ls.fertilizer, ls.growth, tostring(ls.greenhouseMissing)),
    string.format("HUMAN health %.1f  %s  sleeping %s  slept %.1f min/day  fatigued %s  food %.0fs  toilet %.0fs  bladder %.1f",
      h.health, h.healthStatus, tostring(h.isSleeping), h:sleepInLastDay() / 60, tostring(h:isFatigued()),
      h.timeSinceFood, h.timeSinceToilet, h.bladder),
    string.format("DUST  suit %.1f  cabin %.1f  Cleanliness %.1f  filter %d  entered %s",
      dust.suitDust, dust.cabinDust, dust.dustCleanliness, dust.filterUses, tostring(dust.hasEnteredCabin)),
    string.format("RAD   %s  timer %.1f  loaded %d  placed %d/9  crew exposed %s",
      r.phase, r.timer, r.loadedUnits, r:deployedUnits(), tostring(r:isCrewExposed())),
    string.format("EMERGENCY timer %.1f s", ls.criticalTimer),
    "",
    "G O2 Maker  S CO2 Cleaner  C CO2 Recycler  W Water Recovery  T Trace  D Dust-Off  E Enter  V Water Tank",
    "K Toilet  H Harvest  F Food Storage  M Compost  N Eat  A Aim solar  B Saver  L Regolith  Z Shields  Y Sleep",
    "1 -O2  2 +CO2  3 +dust  4 radiation warning  5 skip 60 s  SPACE pause  R reset  Esc quit"
      .. (self.paused and "   (PAUSED)" or ""),
    "",
    self.lastEvent,
  }
  for i, line in ipairs(lines) do lg.print(line, 20, 70 + (i - 1) * 22) end
end

return Scene
