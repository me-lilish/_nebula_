--[[
  Air System debug scene - placeholder rendering only, for testing the logic.
  Not final art or UI.

  Controls:
    G      Oxygen Generator (uses 1 canister + power)
    S      CO2 Scrubber     (uses power + 1 filter use, has cooldown)
    W      Farm water on/off
    L      Farm grow light on/off
    1 / 2  Debug: drop O2 by 1% / add 0.2% CO2 (to reach thresholds fast)
    P      Pause / resume
    R      Reset
    Esc    Quit
]]

local AirSystem = require("src.air_system")

local Scene = {}
Scene.__index = Scene

function Scene.new()
  local self = setmetatable({}, Scene)
  self.air = AirSystem.new()
  self.paused = false
  self.lastEvent = ""
  self.bigFont = love.graphics.newFont(22)
  self.font = love.graphics.newFont(14)
  return self
end

function Scene:update(dt)
  if not self.paused then self.air:update(dt) end
end

local REASON_TEXT = {
  no_canisters = "No oxygen canisters left!",
  no_power = "Not enough power!",
  cooldown = "Scrubber is cooling down.",
  filter_full = "Scrubber filter is full!",
  mission_failed = "Mission over - press R to restart.",
}

local function report(self, name, ok, reason)
  self.lastEvent = ok and (name .. " used.") or (name .. ": " .. (REASON_TEXT[reason] or reason))
end

function Scene:keypressed(key)
  local air = self.air
  if key == "g" then
    report(self, "Oxygen Generator", air:useOxygenGenerator())
  elseif key == "s" then
    report(self, "CO2 Scrubber", air:useScrubber())
  elseif key == "w" then
    air:setFarmWater(not air.farmHasWater)
  elseif key == "l" then
    air:setFarmLight(not air.farmLightOn)
  elseif key == "1" then
    air.oxygenPercent = air.oxygenPercent - 1; air:_refresh()
  elseif key == "2" then
    air.carbonDioxidePercent = air.carbonDioxidePercent + 0.2; air:_refresh()
  elseif key == "p" then
    self.paused = not self.paused
  elseif key == "r" then
    air:reset(); self.lastEvent = "Reset."
  elseif key == "escape" then
    love.event.quit()
  end
end

local function bar(x, y, w, h, frac, color)
  love.graphics.setColor(0.25, 0.25, 0.3)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(color)
  love.graphics.rectangle("fill", x, y, w * math.max(0, math.min(1, frac)), h)
end

function Scene:draw()
  local air, c = self.air, self.air.config
  local fb = air:getFeedback()
  local lg = love.graphics
  lg.clear(0.08, 0.08, 0.12)

  -- Status banner
  lg.setColor(fb.color)
  lg.rectangle("fill", 0, 0, lg.getWidth(), 70)
  lg.setColor(0, 0, 0)
  lg.setFont(self.bigFont)
  lg.printf(fb.failed and "MISSION FAILED" or ("AIR: " .. fb.status:upper()), 0, 8, lg.getWidth(), "center")
  lg.setFont(self.font)
  lg.printf(fb.message, 20, 40, lg.getWidth() - 40, "center")

  -- Critical countdown
  if fb.timeLeft then
    lg.setColor(AirSystem.COLORS.critical)
    lg.setFont(self.bigFont)
    lg.printf(string.format("Countdown: %.1f s", fb.timeLeft), 0, 80, lg.getWidth(), "center")
    lg.setFont(self.font)
  end

  -- Readouts
  local x, y = 30, 125
  lg.setColor(1, 1, 1)
  lg.print(string.format("Oxygen (O2): %.2f %%   [%s]", air.oxygenPercent, air.o2Status), x, y)
  bar(x, y + 20, 400, 12, air.oxygenPercent / 25, AirSystem.COLORS[air.o2Status])
  lg.setColor(1, 1, 1)
  lg.print(string.format("Carbon dioxide (CO2): %.3f %%   [%s]", air.carbonDioxidePercent, air.co2Status), x, y + 45)
  bar(x, y + 65, 400, 12, air.carbonDioxidePercent / 1.5, AirSystem.COLORS[air.co2Status])
  lg.setColor(1, 1, 1)
  lg.print(string.format("Air quality score: %.0f / 100", air.airQuality), x, y + 90)
  bar(x, y + 110, 400, 12, air.airQuality / 100, AirSystem.COLORS[air.airStatus])
  lg.setColor(1, 1, 1)
  lg.print(string.format("Critical timer: %.1f / %d s", air.criticalTimer, c.CRITICAL_TIME_LIMIT), x, y + 135)

  -- Equipment
  y = y + 170
  lg.print(string.format("Power: %.0f / %d", air.power, c.POWER_MAX), x, y)
  lg.print(string.format("[G] Oxygen Generator - canisters left: %d (cost %d power)",
    air.oxygenCanisters, c.O2_GEN_POWER_COST), x, y + 22)
  lg.print(string.format("[S] CO2 Scrubber - filter uses left: %d, cooldown: %.1f s (cost %d power)",
    air.scrubberFilterUses, air.scrubberCooldown, c.SCRUBBER_POWER_COST), x, y + 44)
  lg.print(string.format("Farm: water [W] %s, grow light [L] %s  ->  %s",
    air.farmHasWater and "ON" or "off", air.farmLightOn and "ON" or "off",
    air.farmActive and "GROWING (small bonus)" or "inactive"), x, y + 66)

  lg.setColor(0.7, 0.7, 0.8)
  lg.print("Debug: [1] -1% O2  [2] +0.2% CO2  [P] pause  [R] reset  [Esc] quit"
    .. (self.paused and "   (PAUSED)" or ""), x, y + 100)
  lg.print(self.lastEvent, x, y + 122)
end

return Scene
