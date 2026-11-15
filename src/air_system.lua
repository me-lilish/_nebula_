--[[
  Habitat Air System - game logic
  ===============================
  Pure Lua: no love.* calls, no input, no drawing. This keeps it reusable in
  any scene and testable with plain `lua`.

  Usage:
    local AirSystem = require("src.air_system")
    local air = AirSystem.new()          -- or AirSystem.new(customConfig)
    air:update(dt)                       -- every frame
    air:useOxygenGenerator()             -- returns ok, reason
    air:useScrubber()                    -- returns ok, reason
    air:setFarmWater(true) / air:setFarmLight(true)
    air:getFeedback()                    -- colour + child-friendly message
]]

local defaultConfig = require("src.air_config")

local AirSystem = {}
AirSystem.__index = AirSystem

AirSystem.STATUS = {
  GOOD = "good",
  CAUTION = "caution",
  DANGER = "danger",
  CRITICAL = "critical",
}
local S = AirSystem.STATUS
local SEVERITY = { good = 1, caution = 2, danger = 3, critical = 4 }

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

------------------------------------------------------------------------------
-- Pure classification helpers (exposed for tests and other systems)
------------------------------------------------------------------------------

function AirSystem.classifyO2(o2, c)
  c = c or defaultConfig
  if o2 < c.O2_DANGER_LOW_MIN then return S.CRITICAL end
  if o2 < c.O2_CAUTION_LOW_MIN then return S.DANGER end
  if o2 < c.O2_GOOD_MIN then return S.CAUTION end
  if o2 <= c.O2_GOOD_MAX then return S.GOOD end
  if o2 <= c.O2_CAUTION_HIGH_MAX then return S.CAUTION end
  return S.DANGER -- too much oxygen (fire risk); never critical. See config.
end

function AirSystem.classifyCO2(co2, c)
  c = c or defaultConfig
  if co2 > c.CO2_DANGER_MAX then return S.CRITICAL end
  if co2 > c.CO2_CAUTION_MAX then return S.DANGER end
  if co2 >= c.CO2_CAUTION_MIN then return S.CAUTION end
  return S.GOOD
end

-- Overall status is the worse of the two gases.
function AirSystem.classify(o2, co2, c)
  local a, b = AirSystem.classifyO2(o2, c), AirSystem.classifyCO2(co2, c)
  if SEVERITY[a] >= SEVERITY[b] then return a end
  return b
end

function AirSystem.computeQuality(o2, co2, c)
  c = c or defaultConfig
  local score = 100
    - c.O2_SCORE_WEIGHT * math.abs(o2 - c.SCORE_IDEAL_O2)
    - c.CO2_SCORE_WEIGHT * math.max(0, co2 - c.SCORE_BASE_CO2)
  return clamp(score, 0, 100)
end

------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------

function AirSystem.new(config)
  local c = config or defaultConfig
  local self = setmetatable({ config = c }, AirSystem)
  self:reset()
  return self
end

function AirSystem:reset()
  local c = self.config
  self.oxygenPercent = c.START_O2_PERCENT
  self.carbonDioxidePercent = c.START_CO2_PERCENT
  self.power = c.POWER_START

  self.oxygenCanisters = c.O2_GEN_START_CANISTERS
  self.scrubberFilterUses = c.SCRUBBER_FILTER_USES
  self.scrubberCooldown = 0

  self.farmHasWater = false
  self.farmLightOn = false
  self.farmActive = false

  self.criticalTimer = 0
  self.missionFailed = false
  self.failureCause = nil -- "low_oxygen" | "high_co2" | "both"

  self:_refresh()
end

-- Recompute derived values (status, quality) from the gas levels.
function AirSystem:_refresh()
  local c = self.config
  self.oxygenPercent = clamp(self.oxygenPercent, c.O2_MIN_PERCENT, c.O2_MAX_PERCENT)
  self.carbonDioxidePercent = clamp(self.carbonDioxidePercent, c.CO2_MIN_PERCENT, c.CO2_MAX_PERCENT)
  self.o2Status = AirSystem.classifyO2(self.oxygenPercent, c)
  self.co2Status = AirSystem.classifyCO2(self.carbonDioxidePercent, c)
  self.airStatus = AirSystem.classify(self.oxygenPercent, self.carbonDioxidePercent, c)
  self.airQuality = AirSystem.computeQuality(self.oxygenPercent, self.carbonDioxidePercent, c)
end

------------------------------------------------------------------------------
-- Simulation step
------------------------------------------------------------------------------

function AirSystem:update(dt)
  if self.missionFailed or dt <= 0 then return end
  local c = self.config

  -- Astronaut breathing
  self.oxygenPercent = self.oxygenPercent - c.ASTRONAUT_O2_USE_PER_SEC * dt
  self.carbonDioxidePercent = self.carbonDioxidePercent + c.ASTRONAUT_CO2_MAKE_PER_SEC * dt

  -- Power recharge
  self.power = math.min(c.POWER_MAX, self.power + c.POWER_RECHARGE_PER_SEC * dt)

  -- Farm: works only with power, water AND grow light
  local farmPowerNeeded = c.FARM_POWER_USE_PER_SEC * dt
  self.farmActive = self.farmHasWater and self.farmLightOn and self.power >= farmPowerNeeded
  if self.farmActive then
    self.power = self.power - farmPowerNeeded
    self.oxygenPercent = self.oxygenPercent + c.FARM_O2_MAKE_PER_SEC * dt
    self.carbonDioxidePercent = self.carbonDioxidePercent - c.FARM_CO2_REMOVE_PER_SEC * dt
  end

  -- Scrubber cooldown
  -- (tiny epsilon: summing many frame dt values leaves float dust like 1e-15)
  self.scrubberCooldown = self.scrubberCooldown - dt
  if self.scrubberCooldown < 1e-9 then self.scrubberCooldown = 0 end

  self:_refresh()

  -- Critical timer: counts while critical, resets to 0 the moment it is not.
  if self.airStatus == S.CRITICAL then
    self.criticalTimer = self.criticalTimer + dt
    if self.criticalTimer >= c.CRITICAL_TIME_LIMIT - 1e-9 then -- float-dust tolerance
      self.criticalTimer = c.CRITICAL_TIME_LIMIT
      self:_fail()
    end
  else
    self.criticalTimer = 0
  end
end

function AirSystem:_fail()
  self.missionFailed = true
  local lowO2 = self.o2Status == S.CRITICAL
  local highCO2 = self.co2Status == S.CRITICAL
  if lowO2 and highCO2 then
    self.failureCause = "both"
  elseif lowO2 then
    self.failureCause = "low_oxygen"
  else
    self.failureCause = "high_co2"
  end
end

-- Seconds left before game over (only meaningful while critical).
function AirSystem:getCriticalTimeLeft()
  return math.max(0, self.config.CRITICAL_TIME_LIMIT - self.criticalTimer)
end

------------------------------------------------------------------------------
-- Player interactions. Each returns ok (boolean), reason (string or nil).
------------------------------------------------------------------------------

function AirSystem:useOxygenGenerator()
  local c = self.config
  if self.missionFailed then return false, "mission_failed" end
  if self.oxygenCanisters <= 0 then return false, "no_canisters" end
  if self.power < c.O2_GEN_POWER_COST then return false, "no_power" end
  self.oxygenCanisters = self.oxygenCanisters - 1
  self.power = self.power - c.O2_GEN_POWER_COST
  self.oxygenPercent = self.oxygenPercent + c.O2_GEN_BOOST_PERCENT
  self:_refresh()
  self:_clearTimerIfSafe()
  return true
end

function AirSystem:useScrubber()
  local c = self.config
  if self.missionFailed then return false, "mission_failed" end
  if self.scrubberFilterUses <= 0 then return false, "filter_full" end
  if self.scrubberCooldown > 0 then return false, "cooldown" end
  if self.power < c.SCRUBBER_POWER_COST then return false, "no_power" end
  self.scrubberFilterUses = self.scrubberFilterUses - 1
  self.power = self.power - c.SCRUBBER_POWER_COST
  self.scrubberCooldown = c.SCRUBBER_COOLDOWN_SEC
  self.carbonDioxidePercent = self.carbonDioxidePercent - c.SCRUBBER_REDUCE_PERCENT
  self:_refresh()
  self:_clearTimerIfSafe()
  return true
end

-- An interaction that fixes the air resets the timer immediately,
-- without waiting for the next update.
function AirSystem:_clearTimerIfSafe()
  if self.airStatus ~= S.CRITICAL then self.criticalTimer = 0 end
end

function AirSystem:setFarmWater(on) self.farmHasWater = on and true or false end
function AirSystem:setFarmLight(on) self.farmLightOn = on and true or false end

------------------------------------------------------------------------------
-- Player feedback (data only; the scene decides how to draw it)
------------------------------------------------------------------------------

AirSystem.COLORS = {
  good     = { 0.20, 0.80, 0.30 }, -- green
  caution  = { 0.95, 0.85, 0.20 }, -- yellow
  danger   = { 1.00, 0.55, 0.10 }, -- orange
  critical = { 0.90, 0.15, 0.15 }, -- red
}

local FAILURE_MESSAGES = {
  low_oxygen = "The cabin air did not have enough oxygen for too long. "
    .. "Mission Control needs you to restore oxygen with the Oxygen Generator.",
  high_co2 = "The cabin air had too much carbon dioxide for too long. "
    .. "Mission Control needs you to remove carbon dioxide with the CO2 Scrubber.",
  both = "The cabin air was unsafe for too long. "
    .. "Mission Control needs you to restore oxygen or remove carbon dioxide.",
}

-- Which machine fixes the current problem? (the worse gas wins)
function AirSystem:_neededAction()
  local o2Sev, co2Sev = SEVERITY[self.o2Status], SEVERITY[self.co2Status]
  if co2Sev > o2Sev then return "scrubber" end
  if o2Sev > co2Sev then
    if self.oxygenPercent > self.config.O2_GOOD_MAX then return "too_much_o2" end
    return "generator"
  end
  if o2Sev == 1 then return nil end
  if self.oxygenPercent > self.config.O2_GOOD_MAX then return "scrubber" end
  return "both"
end

local ACTION_TEXT = {
  generator   = "Use the Oxygen Generator!",
  scrubber    = "Run the CO2 Scrubber!",
  both        = "Use the Oxygen Generator AND the CO2 Scrubber!",
  too_much_o2 = "Too much oxygen! Stop adding oxygen.",
}

-- Returns { status, color, message, action, timeLeft, failed }
function AirSystem:getFeedback()
  local status = self.airStatus
  local fb = {
    status = status,
    color = AirSystem.COLORS[status],
    action = self:_neededAction(),
    failed = self.missionFailed,
  }
  if self.missionFailed then
    fb.color = AirSystem.COLORS.critical
    fb.message = FAILURE_MESSAGES[self.failureCause]
  elseif status == S.GOOD then
    fb.message = "The air is fresh and safe."
  elseif status == S.CAUTION then
    fb.message = "Check the air system."
  elseif status == S.DANGER then
    fb.message = "Warning! " .. ACTION_TEXT[fb.action]
  else
    fb.timeLeft = self:getCriticalTimeLeft()
    fb.message = string.format("EMERGENCY! %s %d seconds left!",
      ACTION_TEXT[fb.action], math.ceil(fb.timeLeft))
  end
  return fb
end

return AirSystem
