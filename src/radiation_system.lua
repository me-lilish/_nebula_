--[[
  Radiation subsystem (lunar solar storms + regolith shielding)
  =============================================================
  Pure Lua: no love.* calls, no input, no drawing.

  Owns the storm schedule (clear -> warning -> storm -> clear), the nine
  habitat sections and the regolith shield units. It does not own power,
  health, dust or salvage: src/life_support.lua turns the events returned by
  update() into those effects.
]]

local defaultConfig = require("src.radiation_config")

local RadiationSystem = {}
RadiationSystem.__index = RadiationSystem

local EPS = 1e-9

function RadiationSystem.new(config)
  local self = setmetatable({ config = config or defaultConfig }, RadiationSystem)
  self:reset()
  return self
end

function RadiationSystem:reset()
  local c = self.config
  self.phase = "clear"                 -- "clear" | "warning" | "storm"
  self.timer = c.FIRST_WARNING_AT_SEC  -- seconds until the next phase change
  self.loadedUnits = 0                 -- regolith loaded, not yet placed
  self.stormsSurvived = 0
  self.sections = {}
  self.order = {}
  for i, s in ipairs(c.SECTIONS) do
    self.sections[s.id] = { id = s.id, name = s.name, shielded = false, integrity = 100, damaged = false }
    self.order[i] = s.id
  end
end

------------------------------------------------------------------------------
-- Counts
------------------------------------------------------------------------------

function RadiationSystem:deployedUnits()
  local n = 0
  for _, id in ipairs(self.order) do
    if self.sections[id].shielded then n = n + 1 end
  end
  return n
end

-- Regolith units still in the ground (not loaded, not placed).
function RadiationSystem:unitsLeft()
  return self.config.SHIELD_UNITS - self.loadedUnits - self:deployedUnits()
end

function RadiationSystem:isCrewExposed()
  return self.phase == "storm" and not self.sections.crew.shielded
end

-- Seconds until the storm starts (nil during a storm).
function RadiationSystem:timeToStorm()
  if self.phase == "warning" then return self.timer end
  if self.phase == "clear" then return self.timer + self.config.WARNING_LEAD_SEC end
  return nil
end

------------------------------------------------------------------------------
-- Time step. Returns a list of events:
--   { type = "warning" } | { type = "storm" } | { type = "clear" }
--   { type = "damage", section = id }
------------------------------------------------------------------------------

function RadiationSystem:update(dt)
  local c = self.config
  local events = {}
  if dt <= 0 then return events end

  if self.phase == "storm" then
    for _, id in ipairs(self.order) do
      local s = self.sections[id]
      if not s.shielded then
        s.integrity = math.max(0, s.integrity - c.SECTION_DAMAGE_PER_SEC * dt)
        if not s.damaged and s.integrity <= c.SECTION_DAMAGE_LINE + EPS then
          s.damaged = true
          events[#events + 1] = { type = "damage", section = id }
        end
      end
    end
  end

  self.timer = self.timer - dt
  if self.timer <= EPS then
    if self.phase == "clear" then
      self.phase, self.timer = "warning", c.WARNING_LEAD_SEC
      events[#events + 1] = { type = "warning" }
    elseif self.phase == "warning" then
      self.phase, self.timer = "storm", c.STORM_DURATION_SEC
      events[#events + 1] = { type = "storm" }
    else
      self.phase, self.timer = "clear", c.STORM_INTERVAL_SEC
      self.stormsSurvived = self.stormsSurvived + 1
      events[#events + 1] = { type = "clear" }
    end
  end
  return events
end

-- Debug / test helper: start the two-minute warning now.
function RadiationSystem:triggerWarning()
  self.phase, self.timer = "warning", self.config.WARNING_LEAD_SEC
end

------------------------------------------------------------------------------
-- Regolith Loader and Shield Control Panel (power is checked by the caller)
------------------------------------------------------------------------------

function RadiationSystem:canLoad()
  if self:unitsLeft() <= 0 then
    if self.loadedUnits > 0 then return false, "loader_full" end
    return false, "all_shielded"
  end
  return true
end

-- Returns the number of units loaded.
function RadiationSystem:load()
  local n = math.min(self.config.LOADER_UNITS_PER_USE, self:unitsLeft())
  self.loadedUnits = self.loadedUnits + n
  return n
end

function RadiationSystem:canDeploy()
  if self:deployedUnits() >= #self.order then return false, "all_shielded" end
  if self.loadedUnits <= 0 then return false, "no_regolith" end
  return true
end

-- Places loaded units on unshielded sections, crew first. Returns count.
function RadiationSystem:deploy()
  local placed = 0
  for _, id in ipairs(self.order) do
    if self.loadedUnits <= 0 then break end
    local s = self.sections[id]
    if not s.shielded then
      s.shielded = true
      self.loadedUnits = self.loadedUnits - 1
      placed = placed + 1
    end
  end
  return placed
end

return RadiationSystem
