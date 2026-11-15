--[[
  Crew stations (added to the LifeSupport coordinator; no state of their own)
    Toilet / Waste Hygiene Unit : use it (urine -> Urine Processor, hygiene
                                  water -> used water); after 3 uses it must
                                  seal the solid waste into sealed storage
    Food Station                : stored food + potable water -> meal
    Sleep Pod                   : safely fast-forward one eight-hour sleep
]]

return function(LifeSupport)
  local EPS = LifeSupport.EPS

  ----------------------------------------------------------------------------
  -- Toilet / Waste Hygiene Unit
  ----------------------------------------------------------------------------
  function LifeSupport:toiletNeedsSealing()
    return self.toiletUses >= self.config.TOILET_CAPACITY_USES
  end

  function LifeSupport:canUseToilet()
    local c = self.config
    if self.missionFailed then return false, "mission_failed" end
    if self:toiletNeedsSealing() then
      if self:_space("sealedWaste", 100) < c.SEALED_WASTE_PER_SEAL - EPS then return false, "waste_storage_full" end
      if not self:canSpend(c.TOILET_SEAL_POWER_COST) then return false, "no_power" end
      return true
    end
    if self:_space("urine") < self.human.bladder - EPS then return false, "urine_full" end
    return true
  end

  -- Returns ok, reason, mode ("used" | "sealed")
  function LifeSupport:useToilet()
    local ok, reason = self:canUseToilet()
    if not ok then return false, reason end
    local c = self.config
    if self:toiletNeedsSealing() then
      self:trySpend(c.TOILET_SEAL_POWER_COST)
      self.toiletUses = 0
      self.toiletFullTime = 0
      self.sealedWaste = self.sealedWaste + c.SEALED_WASTE_PER_SEAL
      self:_afterAction()
      return true, nil, "sealed"
    end
    self:_fill("urine", self.human:useToilet())
    -- Hand washing / hygiene water ends up as used water for recovery
    local wash = math.min(c.TOILET_HYGIENE_WATER, self.potableWater)
    self.potableWater = self.potableWater - wash
    self:_fill("wastewater", wash)
    self.toiletUses = self.toiletUses + 1
    self:_afterAction()
    return true, nil, "used"
  end

  ----------------------------------------------------------------------------
  -- Food Station
  ----------------------------------------------------------------------------
  function LifeSupport:canEatMeal()
    local c = self.config
    if self.missionFailed then return false, "mission_failed" end
    if self.human.timeSinceMeal < c.MEAL_MIN_GAP_SEC - EPS then return false, "just_ate" end
    if self.food < c.MEAL_FOOD - EPS then return false, "no_food" end
    if self.potableWater < c.MEAL_WATER - EPS then return false, "no_water" end
    if not self:canSpend(c.MEAL_POWER_COST) then return false, "no_power" end
    return true
  end

  function LifeSupport:eatMeal()
    local ok, reason = self:canEatMeal()
    if not ok then return false, reason end
    local c = self.config
    self:trySpend(c.MEAL_POWER_COST)
    self.food = self.food - c.MEAL_FOOD
    self.potableWater = self.potableWater - c.MEAL_WATER
    -- Water in the meal leaves the body like drinking water does
    self.human:addToBladder(c.MEAL_WATER * c.CREW_URINE_SHARE)
    self:_fill("wastewater", c.MEAL_WATER * c.CREW_HUMIDITY_SHARE)
    self.human:eat()
    self:_afterAction()
    return true
  end

  ----------------------------------------------------------------------------
  -- Sleep Pod
  ----------------------------------------------------------------------------
  function LifeSupport:canToggleSleep()
    if self.missionFailed then return false, "mission_failed" end
    if not self.human.isSleeping and self:isAnyCritical() then return false, "emergency" end
    if not self.human.isSleeping and self.radiation.phase ~= "clear" then return false, "storm_alert" end
    return true
  end

  -- Returns ok, reason, state ("slept").
  function LifeSupport:toggleSleep()
    local ok, reason = self:canToggleSleep()
    if not ok then return false, reason end
    if self:fastForwardSleep() then return true, nil, "slept" end
    return false, "emergency"
  end

  ----------------------------------------------------------------------------
  -- Machine Recycler (shredder + furnace): broken parts -> spare parts
  ----------------------------------------------------------------------------
  function LifeSupport:canRecycleParts()
    if self.missionFailed then return false, "mission_failed" end
    if self.salvageParts < 1 - EPS then return false, "no_parts" end
    if not self:canSpend(self.config.RECYCLE_POWER_COST or 1) then return false, "no_power" end
    return true
  end

  -- Returns ok, reason, spare parts made
  function LifeSupport:recycleParts()
    local ok, reason = self:canRecycleParts()
    if not ok then return false, reason end
    local n = math.floor(self.salvageParts + EPS)
    self:trySpend(self.config.RECYCLE_POWER_COST or 1)
    self.salvageParts = self.salvageParts - n
    self.spareParts = self.spareParts + n
    self:_afterAction()
    return true, nil, n
  end
end
