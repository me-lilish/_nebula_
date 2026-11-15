--[[
  Dust subsystem (Trace Contaminant Control - particulates)
  =========================================================
  Pure Lua: no love.* calls, no input, no drawing.

  Owns suit dust, cabin dust, Cabin Cleanliness and the Trace Air Cleaner's
  filter life. It does NOT own power or the emergency timer:
  src/life_support.lua passes its shared power (anything with
  trySpend(amount) -> boolean) and runs the one emergency timer.

    dust:addSuitDust(amount)     dust picked up outside (EVA)
    dust:addCabinDust(amount)    future dust events / debug & tests only
    dust:enterCabin()            first entry only: dirty suit -> cabin dust
    dust:cleanSuit()             Suit Dust-Off Station      -> ok, reason
    dust:runCabinDustFilter()    Trace Air Cleaner          -> ok, reason
    dust:getFeedback(timeLeft)

  Dust is completely separate from O2/CO2 and the air-quality score.
  Suit dust never lowers Cabin Cleanliness by itself.
]]

local defaultConfig = require("src.dust_config")

local DustSystem = {}
DustSystem.__index = DustSystem

DustSystem.STATUS = {
  CLEAN = "clean",
  CAUTION = "caution",
  DANGER = "danger",
  CRITICAL = "critical",
}
local S = DustSystem.STATUS
local SEVERITY = { clean = 1, caution = 2, danger = 3, critical = 4 }

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

------------------------------------------------------------------------------
-- Pure classification helpers
------------------------------------------------------------------------------

function DustSystem.classifySuit(suitDust, c)
  c = c or defaultConfig
  if suitDust >= c.SUIT_DANGER_MIN then return S.DANGER end
  if suitDust >= c.SUIT_CAUTION_MIN then return S.CAUTION end
  return S.CLEAN
end

function DustSystem.classifyCabin(cleanliness, c)
  c = c or defaultConfig
  if cleanliness <= c.CLEANLINESS_CRITICAL_AT then return S.CRITICAL end
  if cleanliness <= c.CLEANLINESS_DANGER_AT then return S.DANGER end
  if cleanliness <= c.CLEANLINESS_CLEAN_ABOVE then return S.CAUTION end
  return S.CLEAN
end

-- Overall status is the worse of suit and cabin.
function DustSystem.classify(suitDust, cabinDust, c)
  c = c or defaultConfig
  local a = DustSystem.classifySuit(suitDust, c)
  local b = DustSystem.classifyCabin(c.MAX - cabinDust, c)
  if SEVERITY[a] >= SEVERITY[b] then return a end
  return b
end

------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------

-- opts.config : optional config table (defaults to src/dust_config.lua)
-- opts.power  : optional shared power source with trySpend(amount)
function DustSystem.new(opts)
  opts = opts or {}
  local self = setmetatable({ config = opts.config or defaultConfig, power = opts.power }, DustSystem)
  self:reset()
  return self
end

-- Resets dust state only (shared power is not owned here).
function DustSystem:reset()
  local c = self.config
  self.suitDust = c.START_SUIT_DUST
  self.cabinDust = c.START_CABIN_DUST
  self.filterUses = c.FILTER_USES
  self.hasEnteredCabin = false
  self:_refresh()
end

function DustSystem:_refresh()
  local c = self.config
  self.suitDust = clamp(self.suitDust, c.MIN, c.MAX)
  self.cabinDust = clamp(self.cabinDust, c.MIN, c.MAX)
  self.dustCleanliness = c.MAX - self.cabinDust
  self.suitStatus = DustSystem.classifySuit(self.suitDust, c)
  self.cabinStatus = DustSystem.classifyCabin(self.dustCleanliness, c)
  self.dustStatus = DustSystem.classify(self.suitDust, self.cabinDust, c)
end

function DustSystem:isCritical()
  return self.cabinStatus == S.CRITICAL
end

------------------------------------------------------------------------------
-- Dust sources
------------------------------------------------------------------------------

-- Dust picked up outside. Only the suit gets dirtier.
function DustSystem:addSuitDust(amount)
  if amount <= 0 then return end
  self.suitDust = self.suitDust + amount
  self:_refresh()
end

-- Explicit cabin dust (future dust-event system, debug keys, tests).
-- Nothing calls this automatically over time.
function DustSystem:addCabinDust(amount)
  if amount <= 0 then return end
  self.cabinDust = self.cabinDust + amount
  self:_refresh()
end

-- Vulcan walks through the habitat entrance. Only the FIRST entry counts:
--   clean suit -> returns "clean", cabin unchanged
--   dirty suit -> adds exactly suitDust to cabinDust (once), returns "dirty"
-- Later entries (walking back and forth) return nil and change nothing.
-- The suit keeps its own dust; suit and cabin dust stay separate values.
function DustSystem:enterCabin()
  if self.hasEnteredCabin then return nil end
  self.hasEnteredCabin = true
  if self.suitDust <= 0 then return "clean" end
  self.cabinDust = self.cabinDust + self.suitDust -- clamped to 100 in _refresh
  self:_refresh()
  return "dirty"
end

-- Walking out through the outer airlock door: the next walk in counts again.
function DustSystem:goOutside()
  self.hasEnteredCabin = false
end

-- Moon dust sticks to the suit while walking outside (up to an EVA's worth).
function DustSystem:collectSuitDust(amount)
  local cap = self.config.EVA_SUIT_DUST
  if self.suitDust >= cap then return end
  self.suitDust = math.min(cap, self.suitDust + amount)
  self:_refresh()
end

------------------------------------------------------------------------------
-- Cleaning actions. Each returns ok (boolean), reason (string or nil).
-- canX() checks without changing anything (used to show machine state).
------------------------------------------------------------------------------

function DustSystem:_hasPower(cost)
  if cost <= 0 or not self.power or not self.power.canSpend then return true end
  return self.power:canSpend(cost)
end

function DustSystem:_spendPower(cost)
  if cost <= 0 or not self.power then return true end
  return self.power:trySpend(cost) and true or false
end

function DustSystem:canCleanSuit()
  if self.suitDust <= 0 then return false, "already_clean" end
  if not self:_hasPower(self.config.SUIT_CLEAN_POWER_COST) then return false, "no_power" end
  return true
end

-- Suit Dust-Off Station (vacuum/brush + electrostatic dust removal).
-- Cleans the suit only, never the cabin.
function DustSystem:cleanSuit()
  local ok, reason = self:canCleanSuit()
  if not ok then return false, reason end
  if not self:_spendPower(self.config.SUIT_CLEAN_POWER_COST) then return false, "no_power" end
  self.suitDust = self.suitDust - self.config.SUIT_CLEAN_AMOUNT
  self:_refresh()
  return true
end

function DustSystem:canRunCabinDustFilter()
  if self.filterUses <= 0 then return false, "filter_full" end
  if self.cabinDust <= 0 then return false, "already_clean" end
  if not self:_hasPower(self.config.FILTER_POWER_COST) then return false, "no_power" end
  return true
end

-- Trace Air Cleaner (cabin particulate filter). Cleans cabin dust only;
-- never touches the suit, O2 or CO2.
function DustSystem:runCabinDustFilter()
  local ok, reason = self:canRunCabinDustFilter()
  if not ok then return false, reason end
  if not self:_spendPower(self.config.FILTER_POWER_COST) then return false, "no_power" end
  self.filterUses = self.filterUses - 1
  self.cabinDust = self.cabinDust - self.config.FILTER_CLEAN_AMOUNT
  self:_refresh()
  return true
end

------------------------------------------------------------------------------
-- Player feedback (data only; a scene decides how to draw it)
-- Wording rule: say "dust" or "Cabin Cleanliness", never "air quality", so
-- children don't mix dust up with O2 and CO2.
------------------------------------------------------------------------------

DustSystem.COLORS = {
  clean    = { 0.20, 0.80, 0.30 }, -- green
  caution  = { 0.95, 0.85, 0.20 }, -- yellow
  danger   = { 1.00, 0.55, 0.10 }, -- orange
  critical = { 0.90, 0.15, 0.15 }, -- red
}

DustSystem.FAILURE_MESSAGE = "The cabin was too dusty for too long. Dust can make astronauts "
  .. "cough and can break machines. Mission Control needs you to clean your suit "
  .. "before coming inside and use the Trace Air Cleaner."

local CABIN_TEXT = {
  clean = "The cabin is clean.",
  caution = "Cabin Cleanliness is dropping. Check for dust.",
  danger = "Dust warning! Dust can make astronauts cough and clog machines. "
    .. "Use the Trace Air Cleaner!",
}

local SUIT_TEXT = {
  clean = "Your suit is clean.",
  caution = "Your suit is a little dusty. Use the Suit Dust-Off!",
  danger = "Your suit is very dusty! Use the Suit Dust-Off before going inside!",
}

-- timeLeft: seconds on the shared emergency timer (from the coordinator).
-- Returns {
--   status, color, message, action, timeLeft           -- overall (worse of the two)
--   cabinStatus, cabinColor, cabinMessage, cleanliness  -- Cabin Cleanliness Monitor
--   suitStatus, suitMessage                             -- airlock
-- }
function DustSystem:getFeedback(timeLeft)
  local fb = {
    status = self.dustStatus,
    color = DustSystem.COLORS[self.dustStatus],
    cleanliness = self.dustCleanliness,
    cabinStatus = self.cabinStatus,
    cabinColor = DustSystem.COLORS[self.cabinStatus],
    suitStatus = self.suitStatus,
    suitMessage = SUIT_TEXT[self.suitStatus],
  }
  if self.cabinStatus == S.CRITICAL then
    fb.timeLeft = timeLeft
    fb.cabinMessage = "EMERGENCY! Too much dust in the cabin! Use the Trace Air Cleaner!"
    if timeLeft then
      fb.cabinMessage = fb.cabinMessage .. string.format(" %d seconds left!", math.ceil(timeLeft))
    end
  else
    fb.cabinMessage = CABIN_TEXT[self.cabinStatus]
  end

  -- Overall: the worse of cabin and suit (cabin wins a tie).
  if SEVERITY[self.cabinStatus] >= SEVERITY[self.suitStatus] then
    fb.message = fb.cabinMessage
    fb.action = self.cabinStatus ~= S.CLEAN and "filter" or nil
  else
    fb.message = fb.suitMessage
    fb.action = "clean_suit"
  end
  return fb
end

return DustSystem
