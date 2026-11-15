--[[
  Radiation stations (added to the LifeSupport coordinator; no state of their own)
    Regolith Loader      : loads lunar soil into shield units
    Shield Control Panel : places loaded units on unshielded sections, crew first
]]

return function(LifeSupport)
  function LifeSupport:canLoadRegolith()
    if self.missionFailed then return false, "mission_failed" end
    local ok, reason = self.radiation:canLoad()
    if not ok then return false, reason end
    if not self:canSpend(self.radiation.config.LOADER_POWER_COST) then return false, "no_power" end
    return true
  end

  -- Returns ok, reason, unitsLoaded
  function LifeSupport:loadRegolith()
    local ok, reason = self:canLoadRegolith()
    if not ok then return false, reason end
    self:trySpend(self.radiation.config.LOADER_POWER_COST)
    local n = self.radiation:load()
    self:_afterAction()
    return true, nil, n
  end

  function LifeSupport:canDeployShields()
    if self.missionFailed then return false, "mission_failed" end
    local ok, reason = self.radiation:canDeploy()
    if not ok then return false, reason end
    if not self:canSpend(self.radiation.config.DEPLOY_POWER_COST) then return false, "no_power" end
    return true
  end

  -- Returns ok, reason, unitsPlaced
  function LifeSupport:deployShields()
    local ok, reason = self:canDeployShields()
    if not ok then return false, reason end
    self:trySpend(self.radiation.config.DEPLOY_POWER_COST)
    local n = self.radiation:deploy()
    self:_afterAction()   -- crew shielded mid-storm -> timer may reset now
    return true, nil, n
  end
end
