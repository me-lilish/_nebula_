--[[
  Mission guide - "what should I do next?"
  ========================================
  Pure logic (no love.*). Looks at the mission state and returns the most
  urgent task as { station = id or "entrance", text = "...", level = ... }
  level: "critical" | "danger" | "caution" | "tip"
  The HUD shows the text and an arrow pointing at the station.
]]
local Guide = {}

local ORDER = { critical = 1, danger = 2, caution = 3, tip = 4 }

function Guide.next(ls)
  local tasks = {}
  local function add(level, station, text)
    tasks[#tasks + 1] = { level = level, station = station, text = text, n = #tasks + 1 }
  end
  local c = ls.config
  local air, dust, h, rad = ls.air, ls.dust, ls.human, ls.radiation

  -- Getting inside first
  if not dust.hasEnteredCabin then
    if dust.suitDust > 0 then
      add("tip", "dustoff", "Clean your dusty suit at the Suit Dust-Off")
    else
      add("tip", "entrance", "Walk through the door into the habitat")
    end
  end

  -- Air
  if air.o2Status == "critical" or air.o2Status == "danger" then
    if air.oxygenPercent < 21 then -- (too MUCH oxygen needs no machine: it falls by itself)
      add(air.o2Status == "critical" and "critical" or "danger", "oxygen", "Make oxygen at the Oxygen Maker!")
    end
  elseif air.o2Status == "caution" and air.oxygenPercent < 21 then
    add("caution", "oxygen", "Oxygen is dropping: use the Oxygen Maker")
  end
  if air.co2Status == "critical" or air.co2Status == "danger" then
    local level = air.co2Status
    if ls.capturedCO2 >= c.CAPTURED_CO2_MAX - 0.01 then
      add(level, "recycler", "CO2 storage is full: run the CO2 Recycler!")
    else
      add(level, "co2", "Too much CO2: run the CO2 Scrubber!")
    end
  elseif air.co2Status == "caution" then
    add("caution", "co2", "CO2 is rising: run the CO2 Scrubber")
  end

  -- Water
  if ls.waterStatus == "critical" then add("critical", "water", "No drinking water: run the Water Recycler!") end
  if ls.potableWater < c.WATER_POTABLE_CAUTION_BELOW then
    add(ls.potableWater < c.WATER_POTABLE_DANGER_BELOW and "danger" or "caution", "water", "Drinking water is low: run the Water Recycler")
  end
  if ls.processWater < c.OXYGEN_MAKER_WATER_USE then
    add("danger", "water", "The Oxygen Generator needs water: run the Water Recycler")
  end
  if ls:toiletNeedsSealing() then add(ls.hygieneDanger and "danger" or "caution", "toilet", "The Bathroom Pod is full: seal the waste") end
  if ls.urine >= c.WATER_WASTE_CAUTION_AT or ls.wastewater >= c.WATER_WASTE_CAUTION_AT then
    add("caution", "water", "Used water is piling up: run the Water Recycler")
  end

  -- Power
  if ls.powerStatus == "critical" or ls.powerStatus == "danger" then
    if ls:isSunUp() and ls.solarAim < 95 then
      add(ls.powerStatus, "solar", "Battery low: aim the solar panels at the Sun!")
    elseif not ls.powerSaver then
      add(ls.powerStatus, "battery", "Battery low: switch on Power Saver!")
    end
  elseif ls:isSunUp() and ls.solarAim < 60 then
    add("caution", "solar", "Re-aim the solar panels for more power")
  end

  -- Radiation
  if rad.phase ~= "clear" and rad.sections.crew and not rad.sections.crew.shielded then
    local level = rad.phase == "storm" and "critical" or "danger"
    if rad.loadedUnits > 0 then
      add(level, "shield", "Storm coming: place the shields at the Shield Holo-Table!")
    else
      add(level, "regolith", "Storm coming: load Moon soil at the Regolith Hopper!")
    end
  elseif rad.phase == "warning" and rad:deployedUnits() < #rad.order and rad:unitsLeft() + rad.loadedUnits > 0 then
    add("caution", rad.loadedUnits > 0 and "shield" or "regolith", "Shield the rest of the habitat before the storm")
  end

  -- Human needs
  if h:isCritical() then add("critical", "foodstation", "Vulcan is very weak: eat and rest!") end
  local hunger, bath = h:hungerStatus(), h:bathroomStatus()
  if hunger ~= "ok" then add(hunger == "danger" and "danger" or "caution", "foodstation", "Vulcan is hungry: eat at the Food Dispenser") end
  if bath ~= "ok" then add(bath == "danger" and "danger" or "caution", "toilet", "Vulcan needs the Bathroom Pod") end
  if h:isFatigued() or (not ls:isSunUp() and h:sleepInLastDay() < h.config.SLEEP_TARGET_SEC) then
    add(h:isFatigued() and "caution" or "tip", "sleep", "Time to sleep in the bunk bed")
  end

  -- Dust
  if dust.cabinStatus == "critical" then add("critical", "trace", "The cabin is full of dust: use the Dust Filter Unit!")
  elseif dust.cabinStatus == "danger" then add("danger", "trace", "Dust warning: use the Dust Filter Unit")
  elseif dust.cabinStatus == "caution" then add("caution", "trace", "Clean the cabin dust with the Dust Filter Unit") end

  -- Food production
  if ls.growth >= 99.999 then add("tip", "greenhouse", "Crops are ready: harvest the Hydroponic Garden") end
  if ls.crops > 0 then add("tip", "foodstorage", "Pack the harvest into the Food Cooler") end
  if ls.plantScraps >= c.COMPOST_BATCH and ls.fertilizer < 80 then add("tip", "compost", "Turn plant scraps into fertilizer") end
  if ls.greenhouseMissing == "no_fertilizer" then add("caution", "compost", "The garden needs fertilizer: use the Composter") end
  if ls.foodStatus ~= "good" then add("caution", "greenhouse", "Food is getting low: grow and harvest crops") end

  -- CO2 storage getting full: recycle it into water
  if ls.capturedCO2 >= c.CO2_RECYCLER_CO2_USE and ls.hydrogen >= c.CO2_RECYCLER_H2_USE
      and ls.capturedCO2 >= c.CAPTURED_CO2_MAX * 0.5 then
    add("tip", "recycler", "Turn stored CO2 into water with the CO2 Recycler")
  end

  if #tasks == 0 then
    return { level = "tip", station = nil, text = "All systems OK! Keep an eye on the monitors." }
  end
  table.sort(tasks, function(a, b)
    if ORDER[a.level] ~= ORDER[b.level] then return ORDER[a.level] < ORDER[b.level] end
    return a.n < b.n -- same urgency: keep the listed order
  end)
  return tasks[1]
end

return Guide
