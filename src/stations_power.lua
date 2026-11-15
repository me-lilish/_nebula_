--[[
  Power stations (added to the LifeSupport coordinator; no state of their own)
    Solar Array Control    : re-aim the panels at the Sun (aim back to 100%)
    Battery / Power Manager: Power Saver on/off (grow lamps off, dimmer lights)
]]

return function(LifeSupport)
  function LifeSupport:canAimSolar()
    local c = self.config
    if self.missionFailed then return false, "mission_failed" end
    if not self:isSunUp() then return false, "night" end
    if self.solarAim >= c.SOLAR_AIM_START - 1 then return false, "already_aimed" end
    if not self:canSpend(c.SOLAR_AIM_POWER_COST) then return false, "no_power" end
    return true
  end

  function LifeSupport:aimSolar()
    local ok, reason = self:canAimSolar()
    if not ok then return false, reason end
    self:trySpend(self.config.SOLAR_AIM_POWER_COST)
    self.solarAim = self.config.SOLAR_AIM_START
    self:_afterAction()
    return true
  end

  function LifeSupport:canTogglePowerSaver()
    if self.missionFailed then return false, "mission_failed" end
    return true
  end

  -- Returns ok, reason, newState (true = saver on)
  function LifeSupport:togglePowerSaver()
    local ok, reason = self:canTogglePowerSaver()
    if not ok then return false, reason end
    self.powerSaver = not self.powerSaver
    self:_updateGreenhouseNeeds()
    self:_afterAction()
    return true, nil, self.powerSaver
  end
end
