--[[
  Air stations (added to the LifeSupport coordinator; no state of their own)
    Oxygen Maker      : process water + power -> cabin O2 + hydrogen
    CO2 Cleaner       : cabin CO2 -> captured CO2 storage
    CO2 Recycler      : captured CO2 + hydrogen + power -> water + methane
    Trace Air Cleaner : removes cabin dust only (never O2/CO2)
    Suit Dust-Off     : cleans suit dust before entering
    enterCabin        : first airlock crossing (dirty suit -> cabin dust once)
]]

return function(LifeSupport)
  local EPS = LifeSupport.EPS

  ----------------------------------------------------------------------------
  -- Oxygen Maker
  ----------------------------------------------------------------------------
  function LifeSupport:canRunOxygenMaker()
    local c = self.config
    if self.missionFailed then return false, "mission_failed" end
    if self.processWater < c.OXYGEN_MAKER_WATER_USE - EPS then return false, "no_water" end
    if not self:canSpend(c.OXYGEN_MAKER_POWER_COST) then return false, "no_power" end
    return true
  end

  function LifeSupport:runOxygenMaker()
    local ok, reason = self:canRunOxygenMaker()
    if not ok then return false, reason end
    local c = self.config
    self:trySpend(c.OXYGEN_MAKER_POWER_COST)
    self.processWater = self.processWater - c.OXYGEN_MAKER_WATER_USE
    self.air:addOxygen(c.OXYGEN_MAKER_O2_PERCENT)
    local kept = self:_fill("hydrogen", c.OXYGEN_MAKER_H2_UNITS, c.HYDROGEN_MAX)
    self.hydrogenVented = self.hydrogenVented + (c.OXYGEN_MAKER_H2_UNITS - kept)
    self:_afterAction()
    return true
  end

  ----------------------------------------------------------------------------
  -- CO2 Cleaner
  ----------------------------------------------------------------------------
  function LifeSupport:canRunCO2Cleaner()
    local c = self.config
    if self.missionFailed then return false, "mission_failed" end
    if self.co2CleanerCooldown > 0 then return false, "cooldown" end
    if self:_space("capturedCO2", c.CAPTURED_CO2_MAX) <= EPS then return false, "storage_full" end
    if self.air.carbonDioxidePercent <= EPS then return false, "no_co2_in_air" end
    if not self:canSpend(c.CO2_CLEANER_POWER_COST) then return false, "no_power" end
    return true
  end

  function LifeSupport:runCO2Cleaner()
    local ok, reason = self:canRunCO2Cleaner()
    if not ok then return false, reason end
    local c = self.config
    self:trySpend(c.CO2_CLEANER_POWER_COST)
    local roomFor = self:_space("capturedCO2", c.CAPTURED_CO2_MAX) / c.CO2_UNITS_PER_PERCENT
    local removed = self.air:removeCO2(math.min(c.CO2_CLEANER_REMOVE_PERCENT, roomFor))
    self:_fill("capturedCO2", removed * c.CO2_UNITS_PER_PERCENT, c.CAPTURED_CO2_MAX)
    self.co2CleanerCooldown = c.CO2_CLEANER_COOLDOWN_SEC
    self:_afterAction()
    return true
  end

  ----------------------------------------------------------------------------
  -- CO2 Recycler (methane path)
  ----------------------------------------------------------------------------
  function LifeSupport:canRunCO2Recycler()
    local c = self.config
    if self.missionFailed then return false, "mission_failed" end
    if self.capturedCO2 < c.CO2_RECYCLER_CO2_USE - EPS then return false, "no_co2" end
    if self.hydrogen < c.CO2_RECYCLER_H2_USE - EPS then return false, "no_hydrogen" end
    if self:_space("wastewater") < c.CO2_RECYCLER_WATER_OUT - EPS then return false, "wastewater_full" end
    if not self:canSpend(c.CO2_RECYCLER_POWER_COST) then return false, "no_power" end
    return true
  end

  function LifeSupport:runCO2Recycler()
    local ok, reason = self:canRunCO2Recycler()
    if not ok then return false, reason end
    local c = self.config
    self:trySpend(c.CO2_RECYCLER_POWER_COST)
    self.capturedCO2 = self.capturedCO2 - c.CO2_RECYCLER_CO2_USE
    self.hydrogen = self.hydrogen - c.CO2_RECYCLER_H2_USE
    self:_fill("wastewater", c.CO2_RECYCLER_WATER_OUT)
    self.methaneVented = self.methaneVented + c.CO2_RECYCLER_METHANE_OUT
    self:_afterAction()
    return true
  end

  ----------------------------------------------------------------------------
  -- Trace Air Cleaner, Suit Dust-Off, airlock entry
  ----------------------------------------------------------------------------
  function LifeSupport:canRunTraceAirCleaner()
    if self.missionFailed then return false, "mission_failed" end
    return self.dust:canRunCabinDustFilter()
  end

  function LifeSupport:runTraceAirCleaner()
    if self.missionFailed then return false, "mission_failed" end
    local ok, reason = self.dust:runCabinDustFilter() -- spends shared battery
    if ok then self:_afterAction() end
    return ok, reason
  end

  function LifeSupport:canUseSuitDustOff()
    if self.missionFailed then return false, "mission_failed" end
    return self.dust:canCleanSuit()
  end

  function LifeSupport:useSuitDustOff()
    if self.missionFailed then return false, "mission_failed" end
    local ok, reason = self.dust:cleanSuit()
    if ok then self:_afterAction() end
    return ok, reason
  end

  -- First crossing into the habitat. Returns "clean", "dirty" or nil.
  function LifeSupport:enterCabin()
    if self.missionFailed then return nil end
    local result = self.dust:enterCabin()
    self:_afterAction()
    return result
  end

  -- Dust Filter Unit service (HEPA Cartridge Alignment mini-game):
  -- a fresh HEPA cartridge (full filter life) and a clean cabin.
  function LifeSupport:canServiceDustFilter()
    if self.missionFailed then return false, "mission_failed" end
    local d = self.dust
    if d.filterUses >= d.config.FILTER_USES and d.cabinDust <= EPS then return false, "already_clean" end
    if not self:canSpend(d.config.FILTER_POWER_COST or 1) then return false, "no_power" end
    return true
  end

  function LifeSupport:serviceDustFilter()
    local ok, reason = self:canServiceDustFilter()
    if not ok then return false, reason end
    local d = self.dust
    self:trySpend(d.config.FILTER_POWER_COST or 1)
    d.filterUses = d.config.FILTER_USES
    d.cabinDust = 0
    d:_refresh()
    self:_afterAction()
    return true
  end
end
