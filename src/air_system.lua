--[[
  Cabin Air (O2 / CO2) subsystem
  ==============================
  Pure Lua: no love.* calls, no input, no drawing.

  Owns ONLY the cabin gases: oxygen %, carbon dioxide %, their status and the
  air-quality score. It does not own power, water, machines or the emergency
  timer - src/life_support.lua coordinates those and calls:
    air:update(dt)          crew breathing (O2 down, CO2 up)
    air:addOxygen(pct)      from the Oxygen Maker
    air:removeCO2(pct)      from the CO2 Cleaner (returns the amount removed)
    air:getFeedback(timeLeft)
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
AirSystem.SEVERITY = SEVERITY

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

------------------------------------------------------------------------------
-- Pure classification helpers
------------------------------------------------------------------------------

function AirSystem.classifyO2(o2, c)
  c = c or defaultConfig
  if o2 < c.O2_DANGER_LOW_MIN then return S.CRITICAL end
  if o2 < c.O2_CAUTION_LOW_MIN then return S.DANGER end
  if o2 < c.O2_GOOD_MIN then return S.CAUTION end
  if o2 <= c.O2_GOOD_MAX then return S.GOOD end
  if o2 <= c.O2_CAUTION_HIGH_MAX then return S.CAUTION end
  return S.DANGER -- too much oxygen (fire risk); never critical
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
-- State
------------------------------------------------------------------------------

function AirSystem.new(config)
  local self = setmetatable({ config = config or defaultConfig }, AirSystem)
  self:reset()
  return self
end

function AirSystem:reset()
  local c = self.config
  self.oxygenPercent = c.START_O2_PERCENT
  self.carbonDioxidePercent = c.START_CO2_PERCENT
  self:_refresh()
end

-- Clamp gases and recompute status and score.
function AirSystem:_refresh()
  local c = self.config
  self.oxygenPercent = clamp(self.oxygenPercent, c.O2_MIN_PERCENT, c.O2_MAX_PERCENT)
  self.carbonDioxidePercent = clamp(self.carbonDioxidePercent, c.CO2_MIN_PERCENT, c.CO2_MAX_PERCENT)
  self.o2Status = AirSystem.classifyO2(self.oxygenPercent, c)
  self.co2Status = AirSystem.classifyCO2(self.carbonDioxidePercent, c)
  self.airStatus = AirSystem.classify(self.oxygenPercent, self.carbonDioxidePercent, c)
  self.airQuality = AirSystem.computeQuality(self.oxygenPercent, self.carbonDioxidePercent, c)
end

-- Crew breathing.
function AirSystem:update(dt)
  if dt <= 0 then return end
  local c = self.config
  self.oxygenPercent = self.oxygenPercent - c.ASTRONAUT_O2_USE_PER_SEC * dt
  self.carbonDioxidePercent = self.carbonDioxidePercent + c.ASTRONAUT_CO2_MAKE_PER_SEC * dt
  self:_refresh()
end

-- Returns the oxygen actually added (after clamping).
function AirSystem:addOxygen(percent)
  local before = self.oxygenPercent
  self.oxygenPercent = self.oxygenPercent + percent
  self:_refresh()
  return self.oxygenPercent - before
end

-- Returns the CO2 actually removed (never more than is in the cabin).
function AirSystem:removeCO2(percent)
  local before = self.carbonDioxidePercent
  self.carbonDioxidePercent = self.carbonDioxidePercent - percent
  self:_refresh()
  return before - self.carbonDioxidePercent
end

function AirSystem:isCritical()
  return self.airStatus == S.CRITICAL
end

-- "low_oxygen" | "high_co2" | "both" | nil
function AirSystem:criticalCause()
  local lowO2 = self.o2Status == S.CRITICAL
  local highCO2 = self.co2Status == S.CRITICAL
  if lowO2 and highCO2 then return "both" end
  if lowO2 then return "low_oxygen" end
  if highCO2 then return "high_co2" end
  return nil
end

------------------------------------------------------------------------------
-- Player feedback (data only; a scene decides how to draw it)
------------------------------------------------------------------------------

AirSystem.COLORS = {
  good     = { 0.20, 0.80, 0.30 }, -- green
  caution  = { 0.95, 0.85, 0.20 }, -- yellow
  danger   = { 1.00, 0.55, 0.10 }, -- orange
  critical = { 0.90, 0.15, 0.15 }, -- red
}

AirSystem.FAILURE_MESSAGES = {
  low_oxygen = "The cabin air did not have enough oxygen for too long. "
    .. "Mission Control needs you to make oxygen with the Oxygen Maker.",
  high_co2 = "The cabin air had too much carbon dioxide for too long. "
    .. "Mission Control needs you to remove carbon dioxide with the CO2 Cleaner.",
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
  generator   = "Use the Oxygen Maker!",
  scrubber    = "Run the CO2 Cleaner!",
  both        = "Use the Oxygen Maker AND the CO2 Cleaner!",
  too_much_o2 = "Too much oxygen! Stop adding oxygen.",
}

-- timeLeft: seconds on the shared emergency timer (from the coordinator).
-- Returns { status, color, message, action, timeLeft }
function AirSystem:getFeedback(timeLeft)
  local status = self.airStatus
  local fb = {
    status = status,
    color = AirSystem.COLORS[status],
    action = self:_neededAction(),
  }
  if status == S.GOOD then
    fb.message = "The air is fresh and safe."
  elseif status == S.CAUTION then
    fb.message = "Check the air system."
  elseif status == S.DANGER then
    fb.message = "Warning! " .. ACTION_TEXT[fb.action]
  else
    fb.timeLeft = timeLeft
    if timeLeft then
      fb.message = string.format("EMERGENCY! %s %d seconds left!",
        ACTION_TEXT[fb.action], math.ceil(timeLeft))
    else
      fb.message = "EMERGENCY! " .. ACTION_TEXT[fb.action]
    end
  end
  return fb
end

return AirSystem
