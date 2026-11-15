--[[
  Water stations (added to the LifeSupport coordinator; no state of their own)
    Water Recovery = Urine Processor -> Brine Processor -> Water Processor
      (one shared "Run Water Recovery" action runs all three stages)
    Water Tank     : valve that sends potable water to the process-water line
]]

return function(LifeSupport)
  local EPS = LifeSupport.EPS

  -- Urine -> processed water (to used water) + brine
  function LifeSupport:_urineStage()
    local c = self.config
    local f = c.URINE_WATER_FRACTION
    local amount = math.min(c.URINE_BATCH, self.urine)
    if f > 0 then amount = math.min(amount, self:_space("wastewater") / f) end
    if f < 1 then amount = math.min(amount, self:_space("brine") / (1 - f)) end
    if amount <= EPS then return 0, 0, 0 end
    local water, brine = amount * f, amount * (1 - f)
    self.urine = self.urine - amount
    self.wastewater = self.wastewater + water
    self.brine = self.brine + brine
    return amount, water, brine
  end

  -- Brine -> recovered water (to used water) + dried brine solids
  function LifeSupport:_brineStage()
    local c = self.config
    local f = c.BRINE_WATER_FRACTION
    local amount = math.min(c.BRINE_BATCH, self.brine)
    if f > 0 then amount = math.min(amount, self:_space("wastewater") / f) end
    if amount <= EPS then return 0, 0, 0 end
    local water, solids = amount * f, amount * (1 - f)
    self.brine = self.brine - amount
    self.wastewater = self.wastewater + water
    self.wasteSolids = self.wasteSolids + solids
    return amount, water, solids
  end

  -- Used water (condensate + urine water + brine water + CO2-Recycler water
  -- + hygiene water) -> potable water + process water
  function LifeSupport:_waterStage()
    local c = self.config
    local potableSpace, processSpace = self:_space("potableWater"), self:_space("processWater")
    local amount = math.min(c.WATER_PROCESSOR_BATCH, self.wastewater, potableSpace + processSpace)
    if amount <= EPS then return 0, 0, 0 end
    local toProcess = math.min(amount * c.PROCESS_WATER_SHARE, processSpace)
    local toPotable = math.min(amount - toProcess, potableSpace)
    toProcess = amount - toPotable -- spill into process water if potable is full
    self.wastewater = self.wastewater - amount
    self.potableWater = self.potableWater + toPotable
    self.processWater = self.processWater + toProcess
    return amount, toPotable, toProcess
  end

  function LifeSupport:canRunWaterRecycler()
    local c = self.config
    if self.missionFailed then return false, "mission_failed" end
    if self.urine <= EPS and self.brine <= EPS and self.wastewater <= EPS then
      return false, "nothing_to_recycle"
    end
    if self:_space("potableWater") <= EPS and self:_space("processWater") <= EPS then
      return false, "tanks_full"
    end
    if not self:canSpend(c.WATER_RECOVERY_POWER_COST) then return false, "no_power" end
    return true
  end

  -- Returns ok, reason, report { urine, urineWater, brineMade, brine,
  --   brineWater, solids, cleaned, toPotable, toProcess }
  function LifeSupport:runWaterRecycler()
    local ok, reason = self:canRunWaterRecycler()
    if not ok then return false, reason end
    self:trySpend(self.config.WATER_RECOVERY_POWER_COST)
    local r = {}
    r.urine, r.urineWater, r.brineMade = self:_urineStage()
    r.brine, r.brineWater, r.solids = self:_brineStage()
    r.cleaned, r.toPotable, r.toProcess = self:_waterStage()
    self:_afterAction()
    return true, nil, r
  end

  ----------------------------------------------------------------------------
  -- Water Tank valve: potable -> process water line
  ----------------------------------------------------------------------------
  function LifeSupport:canUseWaterTank()
    local c = self.config
    if self.missionFailed then return false, "mission_failed" end
    if self.potableWater < c.WATER_TANK_TRANSFER - EPS then return false, "no_water" end
    if self:_space("processWater") <= EPS then return false, "tanks_full" end
    if not self:canSpend(c.WATER_TANK_POWER_COST) then return false, "no_power" end
    return true
  end

  function LifeSupport:useWaterTank()
    local ok, reason = self:canUseWaterTank()
    if not ok then return false, reason end
    local c = self.config
    self:trySpend(c.WATER_TANK_POWER_COST)
    local moved = math.min(c.WATER_TANK_TRANSFER, self:_space("processWater"))
    self.potableWater = self.potableWater - moved
    self.processWater = self.processWater + moved
    self:_afterAction()
    return true, nil, moved
  end

  -- Tank Valves (Gallon Gauge Stabilizer mini-game): send clean water to the
  -- oxygen-line tank that feeds the Oxygen Generator.
  function LifeSupport:canBalanceWaterTanks()
    local c = self.config
    if self.missionFailed then return false, "mission_failed" end
    if self:_space("processWater") < 1 then return false, "tanks_full" end
    if self.potableWater < c.VALVE_TRANSFER + c.VALVE_KEEP_POTABLE then return false, "no_water" end
    return true
  end

  -- Returns ok, reason, litres moved
  function LifeSupport:balanceWaterTanks()
    local ok, reason = self:canBalanceWaterTanks()
    if not ok then return false, reason end
    local c = self.config
    local amount = math.min(c.VALVE_TRANSFER, self:_space("processWater"))
    self.potableWater = self.potableWater - amount
    self.processWater = self.processWater + amount
    self:_afterAction()
    return true, nil, amount
  end
end
