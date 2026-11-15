--[[
  Mission / Life Support - configuration
  ======================================
  Numbers for the coordinator (src/life_support.lua and src/stations_*.lua):
  time, shared power, water, waste, food, the emergency timer and machines.
  Cabin gas thresholds: src/air_config.lua. Dust: src/dust_config.lua.
  Human needs: src/human_config.lua. Radiation: src/radiation_config.lua.

  Labels:
    [REAL-WORLD RELATIONSHIP]  How things really connect (inputs -> outputs).
    [GAME RULE]                A simplified number chosen for play. Not a NASA
                               medical, engineering or mission value.

  Units (one style everywhere):
    - Water-type resources (potable, process, urine, used water, brine) are
      "water units" (u): 1 u = 1% of the 7.6-litre (2-gallon) starter tank,
      so every water tank is shown as 0..100.
    - Stored gases (captured CO2, hydrogen) use abstract gas units (u).
    - Battery, food, fertilizer, sealed waste: 0..100 %.
    - Cabin gases: percent of cabin air (air_config.lua).
    - Time: real seconds. 1 real second = 10 in-game minutes.

  Flow (each arrow is a gameplay dependency, following NASA's simplified
  life-support schematic):
    Crew drinks potable water -> bladder (urine) + humidity condensate
    Toilet -> urine -> Urine Processor -> processed water + brine
    Brine -> Brine Processor -> recovered water (+ brine solids)
    condensate + processed + recovered + CO2-Recycler water -> Water Processor
    Water Processor -> potable water (Water Tank) + process water
    process water + power -> Oxygen Maker -> cabin O2 + hydrogen
    cabin CO2 -> CO2 Cleaner -> captured CO2 (purified air back to cabin)
    captured CO2 + hydrogen + power -> CO2 Recycler -> water + methane (vented)
    Sun -> Solar Arrays -> Battery -> every machine
    Greenhouse (power + water + light + fertilizer) -> crops + plant scraps
    crops -> Food Storage -> Food Station -> crew
    plant scraps -> Compost Processor -> fertilizer -> Greenhouse
    Toilet solid waste -> sealed waste storage (never fertilizer)
]]

local config = {}

------------------------------------------------------------------------------
-- Time
------------------------------------------------------------------------------
config.REAL_SECONDS_PER_GAME_HOUR = 6  -- [GAME RULE] 1 real second = 10 game minutes
config.GAME_HOURS_PER_DAY = 24         -- 144 real seconds = 1 game day
config.START_HOUR = 6                  -- [GAME RULE] mission starts at 06:00
-- Fixed simulation step. Every update is cut into exact steps of this size
-- (counted in whole microseconds), so one 60 s update gives exactly the same
-- result as sixty 1 s updates.
config.TICK_SECONDS = 0.1
config.SLEEP_FAST_FORWARD_HOURS = 8    -- [GAME RULE] eight simulated hours

------------------------------------------------------------------------------
-- Emergency timer (shared by every critical condition)
------------------------------------------------------------------------------
-- [GAME RULE] While ANY condition is critical, one timer counts. It resets to
-- 0 the moment nothing is critical. At the limit the mission fails.
config.CRITICAL_TIME_LIMIT = 30.0

------------------------------------------------------------------------------
-- Power: Sun -> solar arrays -> battery -> machines
------------------------------------------------------------------------------
-- [REAL-WORLD RELATIONSHIP] Solar arrays only make power in sunlight;
-- batteries store it for night; every machine draws from the battery.
-- [GAME RULE] A real lunar day lasts about two Earth weeks. Here the Sun is
-- up from 06:00 to 22:00 every 24-minute game day.
config.SUNRISE_HOUR = 6
config.SUNSET_HOUR  = 22
config.BATTERY_START = 90                 -- [GAME RULE] %
config.BATTERY_MAX   = 100
config.SOLAR_MAX_PER_SEC = 0.2            -- [GAME RULE] % battery per second at full aim
-- [GAME RULE] The Sun moves, so panels slowly point the wrong way. The Solar
-- Array Control re-aims them back to 100%.
config.SOLAR_AIM_START = 100
config.SOLAR_AIM_DECAY_PER_SEC = 0.15     -- 100% -> 30% in about 8 minutes
config.SOLAR_AIM_MIN = 30
config.SOLAR_AIM_POWER_COST = 0.5
config.BASE_LOAD_PER_SEC = 0.03           -- [GAME RULE] fans, pumps, lights
config.GREENHOUSE_PUMP_LOAD_PER_SEC = 0.01   -- while plants grow
config.GREENHOUSE_LAMP_LOAD_PER_SEC = 0.03   -- grow lamps (only without sunlight)
config.POWER_AVERAGE_SECONDS = 30         -- smoothing for the Power Monitor
-- Power Monitor status [GAME RULE]: 70-100 healthy, 50-69 caution,
-- 1-49 danger, 0 critical.
config.POWER_HEALTHY_MIN = 70
config.POWER_CAUTION_MIN = 50

------------------------------------------------------------------------------
-- Water tanks (units: % of the 7.6 L starter tank)
------------------------------------------------------------------------------
-- [REAL-WORLD RELATIONSHIP] One astronaut uses roughly one gallon (3.8 L) of
-- water a day for drinking, food preparation and hygiene before recycling.
-- That is 50 u per game day. The starter tank is a small emergency reserve.
config.TANK_MAX = 100
config.START_POTABLE_WATER = 100   -- [GAME RULE] full 2-gallon starter tank
config.START_PROCESS_WATER = 50    -- [GAME RULE]
config.START_URINE = 0
config.START_WASTEWATER = 0        -- water waiting for the Water Processor
config.START_BRINE = 0
config.CAPTURED_CO2_MAX = 30       -- [GAME RULE] CO2 storage size (gas units)
config.HYDROGEN_MAX = 30           -- [GAME RULE] extra hydrogen is vented

------------------------------------------------------------------------------
-- Crew water use (the rest of the 50 u/day is meals and toilet hygiene)
------------------------------------------------------------------------------
config.CREW_DRINK_PER_SEC = 25 / 1440 -- [GAME RULE] 25 u per 24-min day
-- [REAL-WORLD RELATIONSHIP] Water a person takes in leaves as urine and as
-- humidity (breath, sweat) that the cabin collects as condensate.
config.CREW_URINE_SHARE    = 0.5   -- [GAME RULE] into the bladder (Toilet)
config.CREW_HUMIDITY_SHARE = 0.45  -- [GAME RULE] condensate -> Water Processor
                                   -- (the other 5% is "used by the body")

------------------------------------------------------------------------------
-- Oxygen Maker (Oxygen Generator): process water + power -> O2 + hydrogen
------------------------------------------------------------------------------
-- [REAL-WORLD RELATIONSHIP] Electrolysis splits water into oxygen and
-- hydrogen. About 1 litre of water a day makes one person's oxygen.
config.OXYGEN_MAKER_WATER_USE  = 0.5  -- [GAME RULE] process water per use
config.OXYGEN_MAKER_O2_PERCENT = 1.0  -- [GAME RULE] cabin O2 added per use
config.OXYGEN_MAKER_H2_UNITS   = 1    -- [GAME RULE] hydrogen made per use
config.OXYGEN_MAKER_POWER_COST = 1    -- [GAME RULE] % battery

------------------------------------------------------------------------------
-- CO2 Cleaner (Carbon Dioxide Removal)
------------------------------------------------------------------------------
-- [REAL-WORLD RELATIONSHIP] Cabin air goes in, CO2 is captured and stored,
-- purified air returns. Captured CO2 never disappears: it waits for the
-- CO2 Recycler.
config.CO2_CLEANER_REMOVE_PERCENT = 0.3 -- [GAME RULE] cabin CO2 removed per use
config.CO2_UNITS_PER_PERCENT      = 5   -- [GAME RULE] 0.3% cabin CO2 = 1.5 u stored
config.CO2_CLEANER_POWER_COST     = 1   -- [GAME RULE]
config.CO2_CLEANER_COOLDOWN_SEC   = 5.0 -- [GAME RULE]

------------------------------------------------------------------------------
-- CO2 Recycler (Carbon Dioxide Reduction, methane path)
------------------------------------------------------------------------------
-- [REAL-WORLD RELATIONSHIP] CO2 + hydrogen -> water + methane. Water goes to
-- the Water Processor; methane is vented overboard.
config.CO2_RECYCLER_CO2_USE     = 1.5 -- [GAME RULE] one CO2 Cleaner use
config.CO2_RECYCLER_H2_USE      = 1   -- [GAME RULE] one Oxygen Maker use
config.CO2_RECYCLER_WATER_OUT   = 1   -- [GAME RULE]
config.CO2_RECYCLER_METHANE_OUT = 1   -- [GAME RULE]
config.CO2_RECYCLER_POWER_COST  = 1   -- [GAME RULE]

------------------------------------------------------------------------------
-- Water Recovery = Urine Processor -> Brine Processor -> Water Processor
-- (one shared "Run Water Recovery" click runs all three stages in order)
------------------------------------------------------------------------------
config.WATER_RECOVERY_POWER_COST = 3  -- [GAME RULE]
-- [REAL-WORLD RELATIONSHIP] Urine is distilled: most becomes water, the rest
-- is salty brine.
config.URINE_BATCH          = 20      -- [GAME RULE]
config.URINE_WATER_FRACTION = 0.85    -- [GAME RULE]
-- [REAL-WORLD RELATIONSHIP] Brine is dried for more water, leaving solids.
-- (NASA's schematic sends this water to the cabin as vapor, where it becomes
-- condensate; the game sends it straight to the Water Processor.)
config.BRINE_BATCH          = 5       -- [GAME RULE]
config.BRINE_WATER_FRACTION = 0.8     -- [GAME RULE]
-- [REAL-WORLD RELATIONSHIP] The Water Processor cleans all collected water
-- into potable water and process water for the Oxygen Maker.
config.WATER_PROCESSOR_BATCH = 20     -- [GAME RULE]
config.PROCESS_WATER_SHARE   = 0.3    -- [GAME RULE] (spills over if one tank is full)

------------------------------------------------------------------------------
-- Water Tank valve: potable water -> process-water line
------------------------------------------------------------------------------
-- [REAL-WORLD RELATIONSHIP] Oxygen generators can draw from the station's
-- clean-water supply. [GAME RULE] One click moves 10 u.
config.WATER_TANK_TRANSFER   = 10
config.WATER_TANK_POWER_COST = 0.5

------------------------------------------------------------------------------
-- Toilet / Waste Hygiene Unit
------------------------------------------------------------------------------
-- [REAL-WORLD RELATIONSHIP] Space toilets send urine to water recovery and
-- seal solid waste in containers. Raw human waste is NOT plant fertilizer.
config.TOILET_CAPACITY_USES  = 3      -- [GAME RULE] uses before sealing
config.RECYCLE_POWER_COST    = 1      -- [GAME RULE] Machine Recycler (broken parts -> spares)
config.TOILET_HYGIENE_WATER  = 1      -- [GAME RULE] potable water per use -> used water
config.TOILET_SEAL_POWER_COST = 2     -- [GAME RULE]
config.SEALED_WASTE_PER_SEAL = 10     -- [GAME RULE] % of sealed-waste storage
config.HYGIENE_GRACE_SEC     = 120    -- [GAME RULE] full toilet left this long -> hygiene danger

------------------------------------------------------------------------------
-- Food
------------------------------------------------------------------------------
config.FOOD_START = 80               -- [GAME RULE] % (brief: 50-100)
config.FOOD_MAX = 100
config.FOOD_CAUTION_BELOW = 50       -- [GAME RULE]
config.FOOD_DANGER_BELOW = 20        -- [GAME RULE]
config.MEAL_FOOD = 8                 -- [GAME RULE] food used per meal
config.MEAL_WATER = 2                -- [GAME RULE] potable water for food prep
config.MEAL_POWER_COST = 0.5         -- [GAME RULE] warming the food
config.MEAL_MIN_GAP_SEC = 60         -- [GAME RULE] "You just ate!"

-- [REAL-WORLD RELATIONSHIP] Plants need light, water, nutrients and power for
-- pumps and lamps. They grow slowly.
config.GREENHOUSE_GROWTH_PER_SEC = 100 / 360  -- [GAME RULE] 6 real minutes to harvest
config.GREENHOUSE_WATER_PER_SEC  = 0.005      -- [GAME RULE] potable water
config.FERTILIZER_USE_PER_SEC    = 0.05       -- [GAME RULE]
config.FERTILIZER_START = 40                  -- [GAME RULE] %
config.FERTILIZER_MAX = 100
config.HARVEST_CROPS = 30            -- [GAME RULE] food % per harvest
config.HARVEST_PLANT_SCRAPS = 10     -- [GAME RULE] inedible leaves/stems
config.HARVEST_POWER_COST = 0.5

-- Compost Processor: plant scraps -> fertilizer (plant waste ONLY)
config.COMPOST_BATCH = 10            -- [GAME RULE] plant scraps per run
config.COMPOST_FERTILIZER_OUT = 8    -- [GAME RULE]
config.COMPOST_POWER_COST = 2        -- [GAME RULE]
config.GROWLIGHT_BOOST = 25          -- [GAME RULE] growth % from a tuned light recipe
config.GROWLIGHT_POWER_COST = 1      -- [GAME RULE]
config.VALVE_TRANSFER = 20           -- [GAME RULE] clean water -> oxygen-line tank per balance
config.VALVE_KEEP_POTABLE = 20       -- [GAME RULE] never drain the drinking water below this

------------------------------------------------------------------------------
-- Water / hygiene status (Water Monitor)  [GAME RULE]
--   critical : potable water is 0
--   danger   : potable < 15, or toilet left full too long
--   caution  : potable < 30 (warning begins below 30%), process < 15,
--              urine / used water at 80+, toilet full, sealed waste 80+
--   good     : otherwise
------------------------------------------------------------------------------
config.WATER_POTABLE_CAUTION_BELOW = 30
config.WATER_POTABLE_DANGER_BELOW  = 15
config.WATER_PROCESS_CAUTION_BELOW = 15
config.WATER_WASTE_CAUTION_AT      = 80
config.SEALED_WASTE_CAUTION_AT     = 80

return config
