--[[
  Food stations (added to the LifeSupport coordinator; no state of their own)
    Greenhouse        : grows slowly with power + water + light + fertilizer;
                        harvest -> crops + plant scraps
    Food Storage      : stores harvested crops as food
    Compost Processor : plant scraps ONLY -> fertilizer for the Greenhouse
  Raw human waste never becomes fertilizer (it is sealed at the Toilet).
]]

return function(LifeSupport)
  local EPS = LifeSupport.EPS

  -- Decides whether plants can grow right now (and the first missing need).
  function LifeSupport:_updateGreenhouseNeeds()
    local missing = nil
    if self.growth >= 100 - EPS then
      missing = nil
    elseif self.battery <= EPS then
      missing = "no_power"
    elseif not self:isSunUp() and self.powerSaver then
      missing = "no_light"          -- Power Saver switches the grow lamps off
    elseif self.potableWater <= EPS then
      missing = "no_water"
    elseif self.fertilizer <= EPS then
      missing = "no_fertilizer"
    end
    self.greenhouseMissing = missing
    self.greenhouseGrowing = (missing == nil) and self.growth < 100 - EPS
  end

  function LifeSupport:_growGreenhouse(dt)
    if not self.greenhouseGrowing then return end
    local c = self.config
    self.growth = math.min(100, self.growth + c.GREENHOUSE_GROWTH_PER_SEC * dt)
    self.potableWater = math.max(0, self.potableWater - c.GREENHOUSE_WATER_PER_SEC * dt)
    self.fertilizer = math.max(0, self.fertilizer - c.FERTILIZER_USE_PER_SEC * dt)
  end

  ----------------------------------------------------------------------------
  -- Greenhouse: harvest
  ----------------------------------------------------------------------------
  function LifeSupport:canHarvestGreenhouse()
    local c = self.config
    if self.missionFailed then return false, "mission_failed" end
    if self.growth < 100 - EPS then
      return false, self.greenhouseMissing or "growing"
    end
    if self:_space("crops", c.FOOD_MAX) < c.HARVEST_CROPS - EPS then return false, "crate_full" end
    if not self:canSpend(c.HARVEST_POWER_COST) then return false, "no_power" end
    return true
  end

  function LifeSupport:harvestGreenhouse()
    local ok, reason = self:canHarvestGreenhouse()
    if not ok then return false, reason end
    local c = self.config
    self:trySpend(c.HARVEST_POWER_COST)
    self.crops = self.crops + c.HARVEST_CROPS
    self:_fill("plantScraps", c.HARVEST_PLANT_SCRAPS, 100)
    self.growth = 0
    self:_afterAction()
    return true
  end

  ----------------------------------------------------------------------------
  -- Food Storage: crops -> stored food
  ----------------------------------------------------------------------------
  function LifeSupport:canStoreCrops()
    local c = self.config
    if self.missionFailed then return false, "mission_failed" end
    if self.crops <= EPS then return false, "no_crops" end
    if self:_space("food", c.FOOD_MAX) <= EPS then return false, "storage_full" end
    return true
  end

  function LifeSupport:storeCrops()
    local ok, reason = self:canStoreCrops()
    if not ok then return false, reason end
    local moved = self:_fill("food", self.crops, self.config.FOOD_MAX)
    self.crops = self.crops - moved
    self:_afterAction()
    return true, nil, moved
  end

  ----------------------------------------------------------------------------
  -- Compost Processor: plant scraps -> fertilizer
  ----------------------------------------------------------------------------
  function LifeSupport:canRunCompost()
    local c = self.config
    if self.missionFailed then return false, "mission_failed" end
    if self.plantScraps < c.COMPOST_BATCH - EPS then return false, "no_scraps" end
    if self:_space("fertilizer", c.FERTILIZER_MAX) <= EPS then return false, "fertilizer_full" end
    if not self:canSpend(c.COMPOST_POWER_COST) then return false, "no_power" end
    return true
  end

  function LifeSupport:runCompost()
    local ok, reason = self:canRunCompost()
    if not ok then return false, reason end
    local c = self.config
    self:trySpend(c.COMPOST_POWER_COST)
    self.plantScraps = self.plantScraps - c.COMPOST_BATCH
    self:_fill("fertilizer", c.COMPOST_FERTILIZER_OUT, c.FERTILIZER_MAX)
    self:_afterAction()
    return true
  end
end
