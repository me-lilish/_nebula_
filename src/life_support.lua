--[[
  Mission / Life Support coordinator
  ==================================
  Pure Lua: no love.* calls, no input, no drawing.

  The ONE authoritative mission state. It owns:
    - the mission clock (fixed ticks: frame-rate independent)
    - the ONE shared battery (power) and solar arrays
    - water, waste, food, fertilizer, hydrogen, captured CO2, salvage
    - the ONE emergency timer and the game-over cause
    - every cross-system dependency
  Focused subsystems it drives (each owns only its own state):
    self.air       src/air_system.lua        cabin O2 / CO2 + air status
    self.dust      src/dust_system.lua       suit / cabin dust + Cleanliness
    self.human     src/human_system.lua      health, sleep, hunger, bathroom
    self.radiation src/radiation_system.lua  storms, sections, regolith
  Station actions live in src/stations_*.lua; they add methods to this
  coordinator and own no state of their own.

  Every station has:
    canX() -> ok, reason      (no changes; used to show machine state)
    X()    -> ok, reason, ... (does the work only when inputs allow)
]]

local AirSystem = require("src.air_system")
local DustSystem = require("src.dust_system")
local HumanSystem = require("src.human_system")
local RadiationSystem = require("src.radiation_system")
local defaultConfig = require("src.life_support_config")

local LifeSupport = {}
LifeSupport.__index = LifeSupport

local EPS = 1e-9
LifeSupport.EPS = EPS
LifeSupport.COLORS = AirSystem.COLORS

-- opts.config / airConfig / dustConfig / humanConfig / radiationConfig
function LifeSupport.new(opts)
  opts = opts or {}
  local self = setmetatable({ config = opts.config or defaultConfig }, LifeSupport)
  self.air = AirSystem.new(opts.airConfig)
  self.dust = DustSystem.new({ config = opts.dustConfig, power = self })
  self.human = HumanSystem.new(opts.humanConfig)
  self.radiation = RadiationSystem.new(opts.radiationConfig)
  self.radiationEnabled = opts.radiationEnabled ~= false
  self:reset()
  return self
end

function LifeSupport:enableRadiation()
  self.radiationEnabled = true
  self.radiation.timer = self.radiation.config.FIRST_WARNING_AT_SEC
end

function LifeSupport:reset()
  local c = self.config
  self.air:reset(); self.dust:reset(); self.human:reset(); self.radiation:reset()

  -- Clock
  self.missionTime = 0       -- real seconds since the mission started
  self._accUs = 0            -- leftover microseconds smaller than one tick

  -- Power
  self.battery = c.BATTERY_START
  self.solarAim = c.SOLAR_AIM_START
  self.powerSaver = false
  self.powerGenPerSec = 0    -- smoothed, for the Power Monitor
  self.powerUsePerSec = 0
  self._spentThisTick = 0

  -- Water (units: % of the 7.6 L starter tank)
  self.potableWater = c.START_POTABLE_WATER
  self.processWater = c.START_PROCESS_WATER
  self.urine = c.START_URINE
  self.wastewater = c.START_WASTEWATER
  self.brine = c.START_BRINE
  self.capturedCO2 = 0
  self.hydrogen = 0

  -- Waste
  self.toiletUses = 0
  self.toiletFullTime = 0
  self.sealedWaste = 0
  self.salvageParts = 0      -- broken machine parts (never food/water/fertilizer)
  self.spareParts = 0        -- parts the Machine Recycler saved for repairs

  -- Food
  self.food = c.FOOD_START
  self.crops = 0             -- harvested crops waiting for Food Storage
  self.plantScraps = 0
  self.fertilizer = c.FERTILIZER_START
  self.growth = 0
  self.greenhouseGrowing = false
  self.greenhouseMissing = nil -- first missing need, or nil

  -- What left the station (counters)
  self.wasteSolids = 0       -- dried brine solids
  self.methaneVented = 0
  self.hydrogenVented = 0

  self.co2CleanerCooldown = 0

  -- Emergency
  self.criticalTimer = 0
  self.missionFailed = false
  self.failureSystem = nil
  self.failureCause = nil
  self.failureLesson = nil
  self.failureMessage = nil

  self.events = {}           -- child-friendly news for the room to show
  self:_refreshStatuses()
  self:_updateGreenhouseNeeds()
  self.powerGenPerSec, self.powerUsePerSec = self:solarPerSec(), self:loadPerSec()
end

-- Debug / test helper: start the radiation warning now (with its news).
function LifeSupport:triggerRadiationWarning()
  self.radiation:triggerWarning()
  self:_onRadiationEvent({ type = "warning" })
end

function LifeSupport:_event(text)
  self.events[#self.events + 1] = text
end

-- Returns and clears the queued news messages.
function LifeSupport:popEvents()
  local e = self.events
  self.events = {}
  return e
end

------------------------------------------------------------------------------
-- Clock
------------------------------------------------------------------------------

-- Game time in hours since midnight of day 1.
function LifeSupport:gameHours()
  local c = self.config
  return c.START_HOUR + self.missionTime / c.REAL_SECONDS_PER_GAME_HOUR
end

-- day (1, 2, ...), hour (0-23), minute (0-59)
function LifeSupport:clock()
  local h = self:gameHours() + EPS
  local day = math.floor(h / self.config.GAME_HOURS_PER_DAY) + 1
  local hourOfDay = h % self.config.GAME_HOURS_PER_DAY
  return day, math.floor(hourOfDay), math.floor((hourOfDay % 1) * 60)
end

function LifeSupport:isSunUp()
  local _, hour = self:clock()
  return hour >= self.config.SUNRISE_HOUR and hour < self.config.SUNSET_HOUR
end

-- Runs the same fixed-tick simulation used during normal play, but advances
-- eight simulated hours at once.  Rendering can animate this in under two
-- seconds; logic never skips resource use, cooldowns, or emergencies.
function LifeSupport:fastForwardSleep()
  if self.missionFailed or self:isAnyCritical() or self.radiation.phase ~= "clear" then return false end
  local seconds = self.config.SLEEP_FAST_FORWARD_HOURS * self.config.REAL_SECONDS_PER_GAME_HOUR
  self.human:startSleep()
  self:update(seconds)
  self.human:wake()
  return not self.missionFailed
end

------------------------------------------------------------------------------
-- Shared power (battery). The dust subsystem spends through these too.
------------------------------------------------------------------------------

function LifeSupport:canSpend(amount)
  return self.battery >= amount - EPS
end

function LifeSupport:trySpend(amount)
  if amount <= 0 then return true end
  if not self:canSpend(amount) then return false end
  self.battery = math.max(0, self.battery - amount)
  self._spentThisTick = self._spentThisTick + amount
  return true
end

-- Continuous loads right now (% battery per second).
function LifeSupport:loadPerSec()
  local c = self.config
  local load = c.BASE_LOAD_PER_SEC * (self.powerSaver and 0.7 or 1)
  if self.greenhouseGrowing then
    load = load + c.GREENHOUSE_PUMP_LOAD_PER_SEC
    if not self:isSunUp() and not self.powerSaver then
      load = load + c.GREENHOUSE_LAMP_LOAD_PER_SEC
    end
  end
  return load
end

function LifeSupport:solarPerSec()
  if not self:isSunUp() then return 0 end
  return self.config.SOLAR_MAX_PER_SEC * self.solarAim / 100
end

------------------------------------------------------------------------------
-- Tank helpers
------------------------------------------------------------------------------

function LifeSupport:_space(field, max)
  return math.max(0, (max or self.config.TANK_MAX) - self[field])
end

-- Adds up to `amount`, returns what actually fit.
function LifeSupport:_fill(field, amount, max)
  local added = math.min(amount, self:_space(field, max))
  if added < 0 then added = 0 end
  self[field] = self[field] + added
  return added
end

------------------------------------------------------------------------------
-- Statuses
------------------------------------------------------------------------------

function LifeSupport:_refreshStatuses()
  local c = self.config
  -- Power
  if self.battery <= EPS then self.powerStatus = "critical"
  elseif self.battery < c.POWER_CAUTION_MIN then self.powerStatus = "danger"
  elseif self.battery < c.POWER_HEALTHY_MIN then self.powerStatus = "caution"
  else self.powerStatus = "good" end
  -- Water + hygiene
  local hygieneDanger = self.toiletUses >= c.TOILET_CAPACITY_USES
    and self.toiletFullTime >= c.HYGIENE_GRACE_SEC - EPS
  if self.potableWater <= EPS then
    self.waterStatus = "critical"
  elseif self.potableWater < c.WATER_POTABLE_DANGER_BELOW or hygieneDanger then
    self.waterStatus = "danger"
  elseif self.potableWater < c.WATER_POTABLE_CAUTION_BELOW
      or self.processWater < c.WATER_PROCESS_CAUTION_BELOW
      or self.urine >= c.WATER_WASTE_CAUTION_AT
      or self.wastewater >= c.WATER_WASTE_CAUTION_AT
      or self.toiletUses >= c.TOILET_CAPACITY_USES
      or self.sealedWaste >= c.SEALED_WASTE_CAUTION_AT then
    self.waterStatus = "caution"
  else
    self.waterStatus = "good"
  end
  self.hygieneDanger = hygieneDanger
  -- Food
  if self.food < c.FOOD_DANGER_BELOW then self.foodStatus = "danger"
  elseif self.food < c.FOOD_CAUTION_BELOW then self.foodStatus = "caution"
  else self.foodStatus = "good" end
end

------------------------------------------------------------------------------
-- Emergency timer (one for everything)
------------------------------------------------------------------------------

-- Priority order decides the reported cause when several are critical.
function LifeSupport:criticalSystems()
  local list = {}
  if self.air:isCritical() then list[#list + 1] = "air" end
  if self.waterStatus == "critical" then list[#list + 1] = "water" end
  if self.powerStatus == "critical" then list[#list + 1] = "power" end
  if self.radiation:isCrewExposed() then list[#list + 1] = "radiation" end
  if self.human:isCritical() then list[#list + 1] = "health" end
  if self.dust:isCritical() then list[#list + 1] = "dust" end
  return list
end

function LifeSupport:isAnyCritical()
  return #self:criticalSystems() > 0
end

function LifeSupport:getCriticalTimeLeft()
  return math.max(0, self.config.CRITICAL_TIME_LIMIT - self.criticalTimer)
end

function LifeSupport:_timeLeftIfCounting()
  if self:isAnyCritical() then return self:getCriticalTimeLeft() end
  return nil
end

-- Game-over text: direct cause + one short science lesson.
LifeSupport.FAILURES = {
  low_oxygen = { "The cabin ran out of safe oxygen.",
    "Oxygen Makers use clean water and power to make oxygen." },
  high_co2 = { "Too much carbon dioxide built up in the cabin.",
    "The CO2 Cleaner catches the gas we breathe out, and the CO2 Recycler turns it into water." },
  both_air = { "The cabin air became unsafe to breathe.",
    "Astronauts need oxygen added and carbon dioxide removed all the time." },
  water = { "The crew ran out of clean drinking water.",
    "Water Recovery turns urine and cabin moisture back into clean water." },
  power = { "The batteries ran out.",
    "Solar power keeps life-support machines running. Aim the panels at the Sun!" },
  radiation = { "The crew was caught outside the shields during a radiation storm.",
    "Moon soil (regolith) piled around a habitat blocks space radiation." },
  health = { "Vulcan's health ran out.",
    "Astronauts need food, sleep and bathroom breaks to stay healthy." },
  dust = { "Too much dust entered the cabin.",
    "Clean suits before entering the airlock, and filter dust from the air." },
}

function LifeSupport:_fail()
  self.missionFailed = true
  self.failureSystem = self:criticalSystems()[1]
  local key = self.failureSystem
  if key == "air" then
    local cause = self.air:criticalCause()
    key = (cause == "both") and "both_air" or cause
  end
  local f = LifeSupport.FAILURES[key]
  self.failureCause, self.failureLesson = f[1], f[2]
  self.failureMessage = f[1] .. " " .. f[2]
  if self.human.isSleeping then self.human:wake() end
end

-- After any player action: if nothing is critical any more, the timer
-- resets immediately (not on the next tick).
function LifeSupport:_afterAction()
  self:_refreshStatuses()
  if not self:isAnyCritical() then self.criticalTimer = 0 end
end

------------------------------------------------------------------------------
-- Time: fixed ticks counted in whole microseconds, so the result never
-- depends on how the time was chopped into frames.
------------------------------------------------------------------------------

function LifeSupport:update(dt)
  if dt <= 0 then return end
  local c = self.config
  local tickUs = math.floor(c.TICK_SECONDS * 1e6 + 0.5)
  self._accUs = self._accUs + math.floor(dt * 1e6 + 0.5)
  while self._accUs >= tickUs do
    self._accUs = self._accUs - tickUs
    if self.missionFailed then
      self._accUs = 0
      break
    end
    self:_tick(c.TICK_SECONDS)
  end
end

function LifeSupport:_tick(dt)
  local c = self.config
  local dayBefore = self:clock()
  local sunBefore = self:isSunUp()
  self.missionTime = self.missionTime + dt
  local day = self:clock()
  if day ~= dayBefore then self:_event(string.format("Day %d begins!", day)) end
  local sun = self:isSunUp()
  if sun ~= sunBefore then
    self:_event(sun and "Sunrise! The solar panels are making power again."
      or "Sunset. The habitat now runs on its batteries.")
  end

  -- Greenhouse needs are checked first: they decide its power load.
  self:_updateGreenhouseNeeds()

  -- Power: solar in, loads out
  self.solarAim = math.max(c.SOLAR_AIM_MIN, self.solarAim - c.SOLAR_AIM_DECAY_PER_SEC * dt)
  local gen, load = self:solarPerSec(), self:loadPerSec()
  self.battery = math.max(0, math.min(c.BATTERY_MAX, self.battery + (gen - load) * dt))
  local k = math.min(1, dt / c.POWER_AVERAGE_SECONDS)
  self.powerGenPerSec = self.powerGenPerSec + (gen - self.powerGenPerSec) * k
  local used = load + self._spentThisTick / dt
  self.powerUsePerSec = self.powerUsePerSec + (used - self.powerUsePerSec) * k
  self._spentThisTick = 0

  -- Crew drinks potable water -> bladder (urine) + humidity condensate
  local drink = math.min(self.potableWater, c.CREW_DRINK_PER_SEC * dt)
  self.potableWater = self.potableWater - drink
  self.human:addToBladder(drink * c.CREW_URINE_SHARE)
  self:_fill("wastewater", drink * c.CREW_HUMIDITY_SHARE)

  -- Crew breathes (O2 down, CO2 up). Dust never changes with time.
  self.air:update(dt)

  -- Greenhouse growth (uses potable water + fertilizer)
  self:_growGreenhouse(dt)

  -- Radiation storms
  if self.radiationEnabled then
    for _, e in ipairs(self.radiation:update(dt)) do self:_onRadiationEvent(e) end
  end

  -- Toilet left full too long hurts hygiene
  if self.toiletUses >= c.TOILET_CAPACITY_USES then
    self.toiletFullTime = self.toiletFullTime + dt
  else
    self.toiletFullTime = 0
  end

  -- Human needs (+ outside effects on health)
  self:_refreshStatuses()
  local hc = self.human.config
  local extra = 0
  if self.radiation:isCrewExposed() then extra = extra + hc.RADIATION_HEALTH_LOSS_PER_SEC end
  if self.dust.cabinStatus == "danger" or self.dust.cabinStatus == "critical" then
    extra = extra + hc.DUST_HEALTH_LOSS_PER_SEC
  end
  if self.hygieneDanger then extra = extra + hc.HYGIENE_HEALTH_LOSS_PER_SEC end
  self.human:update(dt, extra)

  -- Systems the player has not unlocked yet are held safe by Mission Control
  self:_autopilotTick()

  -- Machine cooldowns (snap float dust to 0)
  self.co2CleanerCooldown = self.co2CleanerCooldown - dt
  if self.co2CleanerCooldown < EPS then self.co2CleanerCooldown = 0 end

  self:_refreshStatuses()

  -- One emergency timer for every critical condition
  if self:isAnyCritical() then
    if self.human.isSleeping then
      self.human:wake()
      self:_event("Alarm! Vulcan woke up because of an emergency.")
    end
    self.criticalTimer = self.criticalTimer + dt
    if self.criticalTimer >= c.CRITICAL_TIME_LIMIT - EPS then
      self.criticalTimer = c.CRITICAL_TIME_LIMIT
      self:_fail()
    end
  else
    self.criticalTimer = 0
  end
end

-- Mission Control autopilot. `self.autopilot` is a set of system names
-- ({ air = true, ... }) chosen by the mission progression; nil = off.
-- Each locked system is simply held at its safe starting values.
function LifeSupport:_autopilotTick()
  local a = self.autopilot
  if not a then return end
  local c = self.config
  if a.air then
    local ac = self.air.config
    self.air.oxygenPercent, self.air.carbonDioxidePercent = ac.START_O2_PERCENT, ac.START_CO2_PERCENT
    self.air:_refresh()
  end
  if a.dust then self.dust.cabinDust = 0; self.dust:_refresh() end
  if a.water then
    self.potableWater = math.max(self.potableWater, c.START_POTABLE_WATER * 0.9)
    self.processWater = math.max(self.processWater, c.START_PROCESS_WATER)
    self.urine = math.min(self.urine, 40)
    self.wastewater = math.min(self.wastewater, 40)
    self.brine = math.min(self.brine, 40)
  end
  if a.food then self.food = math.max(self.food, c.FOOD_START) end
  if a.waste and self.toiletUses >= c.TOILET_CAPACITY_USES then
    self.toiletUses, self.toiletFullTime = 0, 0
  end
  if a.power then
    self.battery = math.max(self.battery, c.BATTERY_START)
    self.solarAim = math.max(self.solarAim, 95)
  end
end

function LifeSupport:_onRadiationEvent(e)
  local rc = self.radiation.config
  if e.type == "warning" then
    self:_event("Radiation warning! A solar storm arrives in 2 minutes. Load regolith and deploy shields!")
    if self.human.isSleeping then
      self.human:wake()
      self:_event("Vulcan woke up for the radiation warning.")
    end
  elseif e.type == "storm" then
    self:_event("The solar storm has started! Stay behind the regolith shields.")
  elseif e.type == "clear" then
    self:_event("The storm is over. Great job, the habitat is safe again!")
  elseif e.type == "damage" then
    -- Machinery damage: salvage parts (kept apart from biological waste)
    -- and a little dust from broken equipment.
    self.salvageParts = self.salvageParts + rc.DAMAGE_SALVAGE_PARTS
    self.dust:addCabinDust(rc.DAMAGE_CABIN_DUST)
    self:_event("Radiation damaged the " .. self.radiation.sections[e.section].name
      .. " section. Broken parts were saved for repairs.")
  end
end

------------------------------------------------------------------------------
-- Monitors (read-only feedback). Each returns { status, color, message, ... }
------------------------------------------------------------------------------

local function color(status)
  return AirSystem.COLORS[status] or AirSystem.COLORS.good
end

local function withCountdown(msg, timeLeft)
  if timeLeft then return msg .. string.format(" %d seconds left!", math.ceil(timeLeft)) end
  return msg
end

function LifeSupport:getAirFeedback()
  return self.air:getFeedback(self:_timeLeftIfCounting())
end

function LifeSupport:getDustFeedback()
  return self.dust:getFeedback(self:_timeLeftIfCounting())
end

function LifeSupport:getWaterFeedback()
  local c = self.config
  local s = self.waterStatus
  local fb = { status = s, color = color(s) }
  if s == "good" then
    fb.message = "Clean water is ready."
  elseif s == "caution" then
    if self.potableWater < c.WATER_POTABLE_CAUTION_BELOW then
      fb.message = "Drinking water is below 30%. Run Water Recovery."
    elseif self.toiletUses >= c.TOILET_CAPACITY_USES then
      fb.message = "The toilet is full. Seal the waste at the Toilet."
    elseif self.urine >= c.WATER_WASTE_CAUTION_AT or self.wastewater >= c.WATER_WASTE_CAUTION_AT then
      fb.message = "Used water is piling up. Run Water Recovery."
    elseif self.sealedWaste >= c.SEALED_WASTE_CAUTION_AT then
      fb.message = "Sealed waste storage is almost full."
    else
      fb.message = "The Oxygen Maker is low on water. Run Water Recovery."
    end
  elseif s == "danger" then
    if self.hygieneDanger then
      fb.message = "Yuck! The toilet has been full too long. Seal the waste!"
    else
      fb.message = "Warning! Drinking water is very low! Run Water Recovery!"
    end
  else
    fb.timeLeft = self:_timeLeftIfCounting()
    fb.message = withCountdown("EMERGENCY! No drinking water! Run Water Recovery!", fb.timeLeft)
  end
  return fb
end

function LifeSupport:getPowerFeedback()
  local s = self.powerStatus
  local fb = { status = s, color = color(s),
    genPerMin = self.powerGenPerSec * 60, usePerMin = self.powerUsePerSec * 60 }
  if s == "good" then
    fb.message = self:isSunUp() and "Batteries are healthy." or "Night: running on batteries."
  elseif s == "caution" then
    fb.message = "Battery is getting low. Aim the solar panels!"
  elseif s == "danger" then
    fb.message = "Warning! Battery low! Aim the panels or turn on Power Saver."
  else
    fb.timeLeft = self:_timeLeftIfCounting()
    fb.message = withCountdown("EMERGENCY! The batteries are empty!", fb.timeLeft)
  end
  return fb
end

function LifeSupport:getFoodFeedback()
  local s = self.foodStatus
  local fb = { status = s, color = color(s) }
  if self.greenhouseMissing then
    local need = { no_power = "power", no_light = "light", no_water = "water",
      no_fertilizer = "fertilizer" }
    fb.greenhouse = "Greenhouse needs " .. need[self.greenhouseMissing] .. "!"
  elseif self.growth >= 100 - EPS then
    fb.greenhouse = "Crops are ready to harvest!"
  else
    fb.greenhouse = string.format("Plants growing: %d%%", math.floor(self.growth))
  end
  if s == "good" then
    fb.message = fb.greenhouse
  elseif s == "caution" then
    fb.message = "Food is below half. Harvest and store crops!"
  else
    fb.message = "Food is very low! Harvest the greenhouse!"
  end
  return fb
end

function LifeSupport:getHumanFeedback()
  local h = self.human
  local s = h.healthStatus
  local fb = { status = s, color = color(s), hunger = h:hungerStatus(),
    bathroom = h:bathroomStatus(), fatigued = h:isFatigued(),
    sleepMin = h:sleepInLastDay() / 60 }
  if s == "critical" then
    fb.timeLeft = self:_timeLeftIfCounting()
    fb.message = withCountdown("EMERGENCY! Vulcan's health is at 0! Eat, sleep and rest!", fb.timeLeft)
  elseif h.isSleeping then
    fb.message = "Zzz... Vulcan is sleeping."
  elseif fb.hunger == "danger" then
    fb.message = "Vulcan is very hungry and getting weak! Visit the Food Station."
  elseif fb.bathroom == "danger" then
    fb.message = "Vulcan really needs the toilet!"
  elseif fb.fatigued then
    fb.message = "Vulcan is tired. Sleep in the Sleep Pod tonight."
  elseif fb.hunger == "warning" then
    fb.message = "Vulcan is getting hungry."
  elseif fb.bathroom == "need" then
    fb.message = "Vulcan needs the toilet soon."
  elseif self.dust.cabinStatus == "danger" then
    fb.message = "The dust is making Vulcan cough."
  else
    fb.message = "Vulcan feels good!"
  end
  return fb
end

function LifeSupport:getRadiationFeedback()
  local r = self.radiation
  local fb = { phase = r.phase, deployed = r:deployedUnits(), loaded = r.loadedUnits,
    total = r.config.SHIELD_UNITS }
  if r.phase == "clear" then
    fb.status = "good"
    fb.message = "Space weather is calm."
  elseif r.phase == "warning" then
    fb.status = "caution"
    fb.timeToStorm = r:timeToStorm()
    fb.message = string.format("Storm in %d s! Load regolith and deploy shields!",
      math.ceil(fb.timeToStorm))
  elseif r:isCrewExposed() then
    fb.status = "critical"
    fb.timeLeft = self:_timeLeftIfCounting()
    fb.message = withCountdown("EMERGENCY! The crew is unshielded! Deploy shields!", fb.timeLeft)
  else
    fb.status = "danger"
    fb.message = "Storm! The shields are protecting the crew."
  end
  fb.color = color(fb.status)
  return fb
end

-- Station actions (each file adds methods; none owns state)
require("src.stations_air")(LifeSupport)
require("src.stations_water")(LifeSupport)
require("src.stations_food")(LifeSupport)
require("src.stations_crew")(LifeSupport)
require("src.stations_power")(LifeSupport)
require("src.stations_radiation")(LifeSupport)

return LifeSupport
