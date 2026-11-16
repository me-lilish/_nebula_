--[[
  Lunar Habitat - the playable station
  ====================================
  Logic: Vulcan walks the station (src/station_map.lua) and clicks stations;
  each station calls ONE coordinator action (src/life_support.lua).
  Layout (where every machine and piece of furniture stands): src/room_layout.lua
  Campaign: 8 levels (src/mission_state.lua) unlock the rooms one system at a
  time; locked systems are run by Mission Control (LifeSupport autopilot).
  Drawing: inside = src/render/station_render.lua (dark cut-away habitat),
  outside = src/render/exterior.lua (open lunar surface), machines =
  src/render/machines.lua, furniture = src/render/props.lua, HUD = src/ui/hud.lua.

  Controls: arrows / WASD walk, Shift sprint, left-click (or E) a station when close,
            Tab tablet, M mute sound, R restart, Esc back to the menu (main.lua).

  The logic part (movement, range, clicks, messages, camera, progression)
  needs no love.* calls, so tests can run it with plain Lua.
]]

local LifeSupport = require("src.life_support")
local Vulcan = require("src.vulcan")
local Map = require("src.station_map")
local Guide = require("src.guide")
local Mission = require("src.mission_state")
local PuzzleManager = require("src.puzzles.manager")
local TTS = require("src.tts")
local I18n = require("src.i18n")

local Room = {}
Room.__index = Room

Room.WIDTH, Room.HEIGHT = 1280, 720       -- virtual screen
Room.VIEW_W, Room.VIEW_H = 1280, 720      -- full-screen playfield; details live in the tablet
Room.START_X, Room.START_Y = Map.START_X, Map.START_Y
Room.ENTRANCE_X = Map.ENTRANCE_X
Room.INTERACT_RANGE = 60
Room.TIRED_SPEED = 0.6
Room.CORNER_SLIDE = 12                    -- px Vulcan may slip round a door corner                    -- exhaustion slows Vulcan down
Room.MESSAGE_SECONDS = 3.5
Room.SPEAKER = { x = 852, y = 33, r = 24, hit = 36 } -- read-aloud button beside the task banner (hit = touch area)
Room.NEWS_SECONDS = 7

Room.TEXT = {
  tooFar = "Move Vulcan closer!",
  missionOver = "Mission paused. Press R to try again.",
  cleanEntry = "Great job! You kept the cabin clean.",
  dirtyEntry = "Oops! Dust entered the cabin.",
}

-- Short tags shown on a station that can't run right now.
-- red = missing input / power / capacity; grey = idle or not needed.
Room.STATE_TAGS = {
  no_water = { "Needs water!", "red" },
  no_power = { "Needs power!", "red" },
  no_co2 = { "Needs CO2!", "red" },
  no_hydrogen = { "Needs hydrogen!", "red" },
  storage_full = { "Storage full!", "red" },
  wastewater_full = { "Water tank full!", "red" },
  tanks_full = { "Tanks full", "grey" },
  filter_full = { "Filter full!", "red" },
  cooldown = { "Resting...", "grey" },
  nothing_to_recycle = { "Nothing to recover", "grey" },
  no_co2_in_air = { "No CO2 to catch", "grey" },
  already_clean = { "All clean", "grey" },
  urine_full = { "Urine tank full!", "red" },
  waste_storage_full = { "Waste storage full!", "red" },
  just_ate = { "Just ate", "grey" },
  no_food = { "No food!", "red" },
  emergency = { "Emergency!", "red" },
  storm_alert = { "Storm alert!", "red" },
  growing = { "Growing...", "grey" },
  no_light = { "Needs light!", "red" },
  no_fertilizer = { "Needs fertilizer!", "red" },
  crate_full = { "Store crops first", "grey" },
  no_crops = { "No crops yet", "grey" },
  no_scraps = { "Needs plant scraps", "grey" },
  fertilizer_full = { "Fertilizer full", "grey" },
  night = { "Night - no Sun", "grey" },
  already_aimed = { "Aimed at Sun", "grey" },
  all_shielded = { "All shielded", "grey" },
  loader_full = { "Regolith loaded", "grey" },
  no_regolith = { "Load regolith first", "grey" },
  no_parts = { "No broken parts", "grey" },
  already_ripe = { "Ripe - harvest!", "grey" },
}
local RED = {}
for reason, tag in pairs(Room.STATE_TAGS) do if tag[2] == "red" then RED[reason] = true end end

local function f0(x) return math.floor(x + 0.5) end

------------------------------------------------------------------------------
-- Stations (world coordinates). fx = effect played when the action works.
------------------------------------------------------------------------------

local Layout = require("src.room_layout")

-- Copies a station's geometry (and sprite) from src/room_layout.lua
local function S(def)
  local g = Layout.MACHINES[def.id]
  def.x, def.y, def.w, def.h, def.sprite = g.x, g.y, g.w, g.h, g.sprite
  return def
end

local function makeStations()
  return {
    -- 1 HUMAN: Crew Quarters
    S {
      id = "sleep", puzzle = "sheep", room = "quarters", title = "Bunk Bed", tech = "Crew quarters rest cycle",
      subtitle = "Sleep 8 hours",
      run = function(ls) return ls:toggleSleep() end,
      check = function(ls) return ls:canToggleSleep() end,
      info = function(ls) return string.format("Slept %.1f / 8 h today", ls.human:sleepInLastDay() / 6) end,
      success = function() return "Eight hours passed safely. Vulcan feels rested!" end,
      problems = {
        emergency = "No sleeping during an emergency!",
        storm_alert = "Radiation alert! Place the shields before sleeping.",
      },
    },
    S {
      id = "foodstation", puzzle = "oven", room = "quarters", title = "Food Dispenser", tech = "Galley ration replicator",
      subtitle = "Eat a warm meal",
      run = function(ls) return ls:eatMeal() end,
      check = function(ls) return ls:canEatMeal() end,
      info = function(ls) return string.format("Stored food %d%%", f0(ls.food)) end,
      fx = { "steam", "Yum!" },
      success = "Yum! Vulcan ate a warm meal.",
      problems = {
        just_ate = "You just ate! Try again a bit later.",
        no_food = "No food left! Harvest and store crops.",
        no_water = "Cooking needs clean water!",
        no_power = "The Food Dispenser needs power!",
      },
    },
    S {
      id = "toilet", puzzle = "scrub", room = "quarters", title = "Bathroom Pod", tech = "Waste Hygiene Unit",
      subtitle = "Bathroom + sealing",
      run = function(ls) return ls:useToilet() end,
      check = function(ls) return ls:canUseToilet() end,
      info = function(ls)
        return string.format("Uses %d/%d  Sealed %d%%", ls.toiletUses, ls.config.TOILET_CAPACITY_USES, f0(ls.sealedWaste))
      end,
      fx = { "bubble", "Flush!" },
      success = function(mode)
        if mode == "sealed" then return "Waste sealed safely. The Bathroom Pod is ready again!" end
        return "Ahh, better! Urine goes to the Water Recycler."
      end,
      problems = {
        urine_full = "The urine tank is full! Run the Water Recycler.",
        waste_storage_full = "Sealed waste storage is full!",
        no_power = "The Bathroom Pod needs power to seal the waste!",
      },
    },
    -- 2 DUST: Airlock & Suit Decontamination Bay
    S {
      id = "dustoff", puzzle = "brush", room = "airlock", title = "Brush Station", tech = "Suit decontamination",
      subtitle = "Brush the dust off!",
      run = function(ls) return ls:useSuitDustOff() end,
      check = function(ls) return ls:canUseSuitDustOff() end,
      info = function(ls) return "Suit dust " .. f0(ls.dust.suitDust) .. "%" end,
      fx = { "dust", "Suit clean!" },
      success = "Suit clean! Safe to go in.",
      problems = { already_clean = "Your suit is already clean!", no_power = "The Brush Station needs power!" },
    },
    S {
      id = "trace", puzzle = "hepa", room = "airlock", title = "Dust Filter Unit", tech = "HEPA particulate filter",
      subtitle = "Catches lunar dust!",
      run = function(ls) return ls:serviceDustFilter() end,
      check = function(ls) return ls:canServiceDustFilter() end,
      info = function(ls) return "Filter life " .. ls.dust.filterUses end,
      fx = { "spark", "Clean air!" },
      success = "Fresh HEPA filter locked in - the cabin air is clean!",
      problems = {
        already_clean = "The cabin is already clean!",
        filter_full = "Dust filter full! It needs a new HEPA cartridge.",
        no_power = "The Dust Filter Unit needs power!",
      },
    },
    -- 3 WATER: Hydro-Plumbing & Storage Bay
    S {
      id = "water", puzzle = "pipes", room = "water", title = "Water Recycler", tech = "Water Recovery System",
      subtitle = "Used water into clean water",
      run = function(ls) return ls:runWaterRecycler() end,
      check = function(ls) return ls:canRunWaterRecycler() end,
      info = function(ls) return string.format("Clean %d%%  O2 water %d", f0(ls.potableWater), f0(ls.processWater)) end,
      fx = { "drop", "+clean water" }, success = "Three steps complete: clean water is ready!",
      problems = { nothing_to_recycle = "No used water yet.", tanks_full = "The clean-water tanks are full!", no_power = "The Water Recycler needs power!" },
    },
    S {
      id = "valves", puzzle = "valves", room = "water", title = "Tank Valves", tech = "Water storage pressure",
      subtitle = "Fill the O2-line tank",
      run = function(ls) return ls:balanceWaterTanks() end,
      check = function(ls) return ls:canBalanceWaterTanks() end,
      info = function(ls) return string.format("Clean %d%%  O2-line %d%%", f0(ls.potableWater), f0(ls.processWater)) end,
      fx = { "drop", "Balanced!" },
      success = function(n) return string.format("Tanks balanced: %d litres sent to the Oxygen Generator line.", n or 0) end,
      problems = {
        tanks_full = "The oxygen-line tank is already full!",
        no_water = "Not enough clean water to share. Run the Water Recycler.",
      },
    },
    -- 4 FOOD: Pantry & Hydroponics Bay
    S {
      id = "growlight", puzzle = "spectrum", room = "food", title = "Grow-Light Timer", tech = "LED light spectrum",
      subtitle = "Tune the plant lights",
      run = function(ls) return ls:tuneGrowLights() end,
      check = function(ls) return ls:canTuneGrowLights() end,
      info = function(ls) return string.format("Plant growth %d%%", math.floor(ls.growth)) end,
      fx = { "leaf", "Grow boost!" },
      success = "Perfect light recipe: the plants shot up!",
      problems = {
        already_ripe = "The plants are already ripe - harvest them!",
        no_power = "The grow lights need power!",
      },
    },
    S {
      id = "greenhouse", puzzle = "seedtray", room = "food", title = "Hydroponic Garden", tech = "Greenhouse growth unit",
      subtitle = "Grows food slowly",
      run = function(ls) return ls:harvestGreenhouse() end,
      check = function(ls) return ls:canHarvestGreenhouse() end,
      info = function(ls) return string.format("Growth %d%%  Fertilizer %d", math.floor(ls.growth), f0(ls.fertilizer)) end,
      fx = { "leaf", "+crops" },
      success = "Harvest time! Crops and plant scraps collected.",
      problems = {
        growing = "The plants are still growing. Come back later!",
        no_power = "The garden needs power!",
        no_light = "The plants need light! Turn off Power Saver at night.",
        no_water = "The garden needs water!",
        no_fertilizer = "The garden needs fertilizer! Use the Composter.",
        crate_full = "Store the last harvest in the Food Cooler first!",
      },
    },
    S {
      id = "foodstorage", room = "food", title = "Food Cooler", tech = "Insulated food storage",
      subtitle = "Packs crops as food",
      run = function(ls) return ls:storeCrops() end,
      check = function(ls) return ls:canStoreCrops() end,
      info = function(ls) return string.format("Food %d%%  Crops %d", f0(ls.food), f0(ls.crops)) end,
      fx = { "spark", "+food" },
      success = "Crops packed into the Food Cooler.",
      problems = {
        no_crops = "No crops to store. Harvest the garden first.",
        storage_full = "The Food Cooler is full!",
      },
    },
    -- 5 WASTE: Recycling & Salvage Workshop
    S {
      id = "compost", puzzle = "compost", room = "waste", title = "Composter", tech = "Organic waste recycler",
      subtitle = "Scraps to fertilizer",
      run = function(ls) return ls:runCompost() end,
      check = function(ls) return ls:canRunCompost() end,
      info = function(ls) return "Plant scraps " .. f0(ls.plantScraps) end,
      fx = { "leaf", "+fertilizer" },
      success = "Plant scraps turned into fertilizer for the garden.",
      problems = {
        no_scraps = "Not enough plant scraps yet. Harvest the garden.",
        fertilizer_full = "The fertilizer store is full!",
        no_power = "The Composter needs power!",
      },
    },
    S {
      id = "recycle", puzzle = "salvage", room = "waste", title = "Machine Recycler", tech = "Shredder + recycling furnace",
      subtitle = "Broken parts to spares",
      run = function(ls) return ls:recycleParts() end,
      check = function(ls) return ls:canRecycleParts() end,
      info = function(ls) return string.format("Broken %d  Spares %d", f0(ls.salvageParts), f0(ls.spareParts)) end,
      fx = { "spark", "+spare parts" },
      success = function(n) return string.format("Recycled %d broken parts into spares for repairs!", n or 0) end,
      problems = {
        no_parts = "No broken parts to recycle right now.",
        no_power = "The Machine Recycler needs power!",
      },
    },
    -- 6 AIR: Atmospheric Control & Vent Hub
    S {
      id = "oxygen", puzzle = "gasmix", room = "air", title = "Oxygen Generator", tech = "Water electrolysis",
      subtitle = "Water into oxygen!",
      run = function(ls) return ls:runOxygenMaker() end,
      check = function(ls) return ls:canRunOxygenMaker() end,
      info = function(ls) return "O2-line water " .. string.format("%.1f", ls.processWater) end,
      fx = { "bubble", "+O2" },
      success = "Great! Fresh oxygen is flowing.",
      problems = {
        no_water = "The Oxygen Generator needs clean water! Run the Water Recycler.",
        no_power = "The Oxygen Generator needs power!",
      },
    },
    S {
      id = "co2", puzzle = "chemmix", room = "air", title = "CO₂ Scrubber", tech = "Carbon Dioxide Removal",
      subtitle = "Catches used air!",
      run = function(ls) return ls:runCO2Cleaner() end,
      check = function(ls) return ls:canRunCO2Cleaner() end,
      info = function(ls)
        local s = string.format("Stored CO₂ %.1f", ls.capturedCO2)
        if ls.co2CleanerCooldown > 0 then s = s .. string.format(" (%ds)", math.ceil(ls.co2CleanerCooldown)) end
        return s
      end,
      fx = { "bubble", "-CO2" },
      success = "Nice! The CO₂ Scrubber caught used-up air.",
      problems = {
        no_power = "The CO₂ Scrubber needs power!",
        storage_full = "CO₂ storage is full! Use the CO₂ Recycler.",
        cooldown = "The CO₂ Scrubber is resting. Try again in %d seconds!",
        no_co2_in_air = "There is no CO₂ to catch right now.",
      },
    },
    S {
      id = "recycler", room = "air", title = "CO₂ Recycler", tech = "Sabatier reactor",
      subtitle = "CO₂ + hydrogen = water",
      run = function(ls) return ls:runCO2Recycler() end,
      check = function(ls) return ls:canRunCO2Recycler() end,
      info = function(ls) return string.format("CO₂ %.1f  H2 %.1f", ls.capturedCO2, ls.hydrogen) end,
      fx = { "steam", "+water" },
      success = "The CO₂ Recycler turned waste gas into water.",
      problems = {
        no_co2 = "The CO₂ Recycler needs CO₂! Use the CO₂ Scrubber first.",
        no_hydrogen = "The CO₂ Recycler needs hydrogen from the Oxygen Generator!",
        wastewater_full = "The used-water tank is full! Run the Water Recycler.",
        no_power = "The CO₂ Recycler needs power!",
      },
    },
    -- 7 POWER: Power Grid Room + Battery Bank
    S {
      id = "solar", puzzle = "oscillo", room = "power", title = "Solar Array Control", tech = "Power distribution unit",
      subtitle = "Aim the panels at the Sun",
      run = function(ls) return ls:aimSolar() end,
      check = function(ls) return ls:canAimSolar() end,
      info = function(ls) return string.format("Aim %d%%  %s", f0(ls.solarAim), ls:isSunUp() and "Sun up" or "Night") end,
      fx = { "spark", "+power" },
      success = "Panels now point at the Sun. More power!",
      problems = {
        night = "It's night! The Sun is down.",
        already_aimed = "The panels already point at the Sun.",
        no_power = "The panel motors need a little power!",
      },
    },
    S {
      id = "battery", puzzle = "breaker", room = "batteries", title = "Battery Bank", tech = "Power manager",
      subtitle = "Power Saver on / off",
      run = function(ls) return ls:togglePowerSaver() end,
      check = function(ls) return ls:canTogglePowerSaver() end,
      info = function(ls) return string.format("Battery %d%%  Saver %s", f0(ls.battery), ls.powerSaver and "ON" or "off") end,
      fx = { "spark", "Saver switched" },
      success = function(on)
        if on then return "Power Saver ON: grow lamps off, lights dimmed." end
        return "Power Saver OFF: everything at full power."
      end,
      problems = {},
    },
    -- 8 RADIATION: Radiation Shielding & Command Center
    S {
      id = "regolith", puzzle = "excavate", repeatRun = true, room = "comms", title = "Regolith Hopper", tech = "Lunar soil collector",
      subtitle = "Load Moon soil",
      run = function(ls) return ls:loadRegolith() end,
      check = function(ls) return ls:canLoadRegolith() end,
      info = function(ls) return string.format("Loaded %d  Left %d", ls.radiation.loadedUnits, ls.radiation:unitsLeft()) end,
      fx = { "dust", "+3 shield bags" },
      success = function(n) return string.format("Loaded %d units of Moon soil (regolith).", n or 0) end,
      problems = {
        all_shielded = "All 9 shield units are already placed!",
        loader_full = "All the regolith is loaded. Use the Shield Holo-Table!",
        no_power = "The Regolith Hopper needs power!",
      },
    },
    S {
      id = "shield", puzzle = "armor", room = "comms", title = "Shield Holo-Table", tech = "Sectional radiation shielding",
      subtitle = "Place regolith shields",
      run = function(ls) return ls:deployShields() end,
      check = function(ls) return ls:canDeployShields() end,
      info = function(ls) return string.format("Shields %d/%d placed", ls.radiation:deployedUnits(), ls.radiation.config.SHIELD_UNITS) end,
      fx = { "spark", "Shields up!" },
      success = function(n) return string.format("%d shield sections placed. The crew is safer!", n or 0) end,
      problems = {
        no_regolith = "Load regolith first at the Regolith Hopper!",
        all_shielded = "Every section is already shielded!",
        no_power = "The Shield Holo-Table needs power!",
      },
    },
  }
end

------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------

-- opts.isDown   : key-check function (tests pass a stub)
-- opts.campaign : true = the 8-level mission (start in the crew quarters,
--                 rooms unlock level by level). false (default) = sandbox
--                 with everything open, starting outside after a moonwalk.
-- opts.config / airConfig / dustConfig / humanConfig / radiationConfig
function Room.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Room)
  self.isDown = opts.isDown or function(k) return love.keyboard.isDown(k) end
  self.campaign = opts.campaign == true
  self.ls = LifeSupport.new({
    config = opts.config, airConfig = opts.airConfig, dustConfig = opts.dustConfig,
    humanConfig = opts.humanConfig, radiationConfig = opts.radiationConfig, radiationEnabled = false,
  })
  self.air, self.dust, self.human = self.ls.air, self.ls.dust, self.ls.human
  self.machines = makeStations()
  for _, m in ipairs(self.machines) do m.act = 0; m.redReasons = RED end
  self.props = Layout.PROPS
  self.solids = {}
  for _, p in ipairs(self.props) do if p.solid then self.solids[#self.solids + 1] = Layout.footprint(p) end end
  -- machines block only their base (where they stand on the floor), like
  -- furniture, so there are no invisible walls around the top of the art
  for _, m in ipairs(self.machines) do self.solids[#self.solids + 1] = Layout.footprint(m, 52) end
  local E = Map.EXTERIOR
  -- walking limits: the whole station plus the lunar field (walls do the rest)
  self.bounds = { left = E.x, top = 0, right = Map.WIDTH, bottom = Map.HEIGHT }
  self.camX, self.camY = 0, 0
  self.time = 0
  self.showTablet = false
  self.missionComplete = false
  -- mini-games: on in the real game (main.lua), off by default so logic
  -- tests can click stations directly
  self.usePuzzles = opts.puzzles == true
  self.puzzles = PuzzleManager.new()
  self:reset()
  return self
end

-- startLevel (campaign only): continue a saved game from the start of that
-- level (1 or nil = a brand-new mission).
function Room:reset(startLevel)
  self.ls:reset()
  -- A small used-water batch so the Water Recycler has something to clean.
  self.ls.wastewater = 20
  self.mission = Mission.new({ unlockAll = not self.campaign })
  if self.campaign then
    local level = math.max(1, math.min(#Mission.LEVELS, math.floor(tonumber(startLevel) or 1)))
    self.mission:startAt(level)
    self.ls.autopilot = self.mission:autopilot()
    self.dust:enterCabin() -- clean suit, already inside
    self.vulcan = Vulcan.new(Map.CREW_START_X, Map.CREW_START_Y)
    if level == 1 then
      self.news = "Good morning, Junior Astronaut! LEVEL 1: look after yourself in the Crew Quarters."
    else
      self:_setupLevel(Mission.LEVELS[level])
      self.news = string.format("Welcome back! LEVEL %d: %s", level, Mission.LEVELS[level].name)
    end
  else
    self.ls.autopilot = nil
    self.dust:addSuitDust(self.dust.config.EVA_SUIT_DUST) -- back from an EVA
    self.vulcan = Vulcan.new(Room.START_X, Room.START_Y)
    self.news = "Welcome back from your moonwalk! Go into the airlock and clean your suit."
  end
  self.newsTimer = Room.NEWS_SECONDS
  self.outside = Map.isOutside(self.vulcan.x, self.vulcan.y)
  self.fade = 0
  self.unlockCard = nil
  self.showTablet, self.missionComplete = false, false
  self.message, self.messageTimer = nil, 0
  self.sounds = {}       -- sound names for src/audio.lua to play this frame
  if self.puzzles then self.puzzles.active = nil end
  for _, m in ipairs(self.machines) do m.act = 0 end
  if self.fx then self.fx = require("src.render.fx").new() end -- clear old effects
  self:_refreshGuide()
  self:_updateCamera()
end

------------------------------------------------------------------------------
-- Progression (campaign)
------------------------------------------------------------------------------

function Room:isRoomLocked(roomId)
  return self.campaign and not self.mission:isRoomUnlocked(roomId)
end

function Room:isDoorLocked(d)
  return self:isRoomLocked(d.room)
end

function Room:_completeTask(id)
  if not self.campaign then return end
  local ok, unlocked, finished = self.mission:complete(id)
  if not ok then return end
  if unlocked then self:_onUnlock(unlocked) end
  if finished then
    self.missionComplete = true
    if self.onProgress then self.onProgress("complete", self:starRating()) end
  end
end

-- 1 - 3 stars on MISSION COMPLETE (how much battery is left)
function Room:starRating()
  local b = self.ls.battery
  return (b >= 70 and 3) or (b >= 40 and 2) or 1
end

-- The level to restart from: the one being played (Level 1 after a win)
function Room:checkpoint()
  if not self.campaign or self.missionComplete then return 1 end
  return self.mission.level
end

-- A new level opens: hand the system over from Mission Control and set up
-- a small, safe first job for the child.
function Room:_onUnlock(level)
  self:_setupLevel(level)
  self.unlockCard = { level = level, index = self.mission.level, timer = 6 }
  TTS.auto(string.format("Level %d unlocked: %s. %s", self.mission.level, level.name, level.lesson), true)
  self:_sound("sfx_unlock")
  self.news, self.newsTimer = string.format("LEVEL %d UNLOCKED: %s - %s", self.mission.level, level.name, level.room), Room.NEWS_SECONDS
  -- auto-save: next time the game continues from this level
  if self.onProgress then self.onProgress("level", self.mission.level) end
end

-- The level's machines get their first job (also when a saved game continues)
function Room:_setupLevel(level)
  local ls = self.ls
  ls.autopilot = self.mission:autopilot()
  local id = level.id
  if id == "dust" then
    ls.dust.filterUses = 1 -- the HEPA filter is clogged: time for a new one
    ls.dust:_refresh()
  elseif id == "water" then
    ls.wastewater = math.max(ls.wastewater, 20)
  elseif id == "food" then
    ls.growth = 75 -- the grow-light tune brings the first crop to ripe
    ls.food = math.min(ls.food, 60)
  elseif id == "waste" then
    ls.salvageParts = ls.salvageParts + 3
    ls.plantScraps = math.max(ls.plantScraps, ls.config.COMPOST_BATCH)
  elseif id == "air" then
    ls.air.oxygenPercent, ls.air.carbonDioxidePercent = 20.3, 0.45
    ls.air:_refresh()
  elseif id == "power" then
    ls.solarAim = math.min(ls.solarAim, 55)
  elseif id == "radiation" then
    ls:enableRadiation()
    ls:triggerRadiationWarning()
  end
  ls:_afterAction()
end

-- level tasks that finish by themselves (all shields placed, storm over)
function Room:_checkAutoTasks()
  local o = self.mission:objective()
  if o and o.id == "shield" and self.ls.radiation:deployedUnits() >= self.ls.radiation.config.SHIELD_UNITS then
    self:_completeTask("shield")
  end
  o = self.mission:objective()
  if o and o.id == "survive" and self.ls.radiation.stormsSurvived > 0 then self:_completeTask("survive") end
end

function Room:_nearestMachine()
  local best, bestDist
  for _, m in ipairs(self.machines) do
    if not self:isRoomLocked(m.room) then
      local cx = math.max(m.x, math.min(self.vulcan.x, m.x + m.w))
      local cy = math.max(m.y, math.min(self.vulcan.y, m.y + m.h))
      local d = math.sqrt((self.vulcan.x - cx) ^ 2 + (self.vulcan.y - cy) ^ 2)
      if d <= Room.INTERACT_RANGE + self.vulcan.radius and (not bestDist or d < bestDist) then best, bestDist = m, d end
    end
  end
  return best
end

function Room:isOver()
  return self.ls.missionFailed
end

------------------------------------------------------------------------------
-- Geometry and camera
------------------------------------------------------------------------------

local function pointInRect(px, py, m)
  return px >= m.x and px <= m.x + m.w and py >= m.y and py <= m.y + m.h
end

local function distanceToRect(px, py, m)
  local cx = math.max(m.x, math.min(px, m.x + m.w))
  local cy = math.max(m.y, math.min(py, m.y + m.h))
  return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

function Room:isNear(machine)
  local v = self.vulcan
  return distanceToRect(v.x, v.y, machine) - v.radius <= Room.INTERACT_RANGE
end

function Room:machineAt(wx, wy)
  for _, m in ipairs(self.machines) do
    if pointInRect(wx, wy, m) then return m end
  end
  return nil
end

function Room:machineById(id)
  for _, m in ipairs(self.machines) do
    if m.id == id then return m end
  end
  return nil
end

-- Can Vulcan stand at (x, y)? Walls (map), locked rooms, stations and
-- solid furniture block.
function Room:_blocked(x, y)
  local r = self.vulcan.radius
  if not Map.isWalkable(x, y, r) then return true end
  if self.campaign then
    for _, room in ipairs(Map.rooms) do
      if self:isRoomLocked(room.id) then
        if distanceToRect(x, y, room) < r then return true end
        if room.extra then for _, e in ipairs(room.extra) do if distanceToRect(x, y, e) < r then return true end end end
      end
    end
    if not self.mission:exteriorUnlocked() and Map.isOutside(x, y) then return true end
  end
  for _, f in ipairs(self.solids) do
    if distanceToRect(x, y, f) < r then return true end
  end
  return false
end

-- A free standing spot next to a station (used by tests and the smoke run).
function Room:spotNear(m)
  local r = self.vulcan.radius + 8
  local cx, cy = m.x + m.w / 2, m.y + m.h / 2
  for _, p in ipairs({ { cx, m.y + m.h + r }, { m.x + m.w + r, cy }, { m.x - r, cy }, { cx, m.y - r },
    { m.x + m.w + r, m.y + m.h + r }, { m.x - r, m.y + m.h + r } }) do
    if not self:_blocked(p[1], p[2]) then return p[1], p[2] end
  end
  return nil
end

function Room:_updateCamera()
  local v = self.vulcan
  -- inside: a margin past the map edge so the HUD never hides a room sign;
  -- outside: Vulcan sits low on the screen so the black sky shows above.
  local b = self.outside and Map.EXTERIOR or { x = -60, y = -96, w = Map.WIDTH + 120, h = Map.HEIGHT + 170 }
  local yBias = self.outside and Room.VIEW_H * 0.64 or (40 + Room.VIEW_H / 2)
  self.camX = math.max(b.x, math.min(b.x + b.w - Room.VIEW_W, v.x - Room.VIEW_W / 2))
  self.camY = math.max(b.y, math.min(b.y + b.h - Room.VIEW_H, v.y - yBias))
end

function Room:screenToWorld(sx, sy) return sx + self.camX, sy + self.camY end
function Room:worldToScreen(wx, wy) return wx - self.camX, wy - self.camY end

------------------------------------------------------------------------------
-- Update / input
------------------------------------------------------------------------------

-- Queue a one-shot sound (played by src/audio.lua; ignored in tests)
function Room:_sound(name)
  if #self.sounds < 8 then self.sounds[#self.sounds + 1] = name end
end

-- What the speaker button reads: the current task, then the last message
function Room:readAloudText()
  local parts = {}
  if self.guide and self.guide.text then parts[#parts + 1] = self.guide.text end
  if self.message then parts[#parts + 1] = self.message end
  return table.concat(parts, ". ")
end

function Room:say(text)
  TTS.auto(text)
  self.message, self.messageTimer = text, Room.MESSAGE_SECONDS
end

-- Effects (only when drawing is available)
function Room:_effect(kind, x, y, n, color)
  if self.fx then self.fx:burst(kind, x, y, n, color) end
end
function Room:_label(text, x, y, color)
  if self.fx then self.fx:label(text, x, y, color) end
end

-- What should the child do next? Emergencies first, then the level task.
function Room:_refreshGuide()
  local ls = self.ls
  self.guide = Guide.next(ls)
  if self.guide.station and self:isRoomLocked((self:machineById(self.guide.station) or {}).room or "") then
    self.guide = { level = "tip", text = "Mission Control is running the locked systems for you." }
  end
  -- the level task is shown unless something needs help urgently
  local urgent = self.guide.level == "danger" or self.guide.level == "critical"
  local o = self.mission:objective()
  if o and not self:isOver() and not urgent then
    local station, text = o.station, o.text
    local deployed = ls.radiation:deployedUnits()
    if o.id == "shield" and ls.radiation.loadedUnits == 0 and deployed < 9 then
      station, text = "regolith", string.format("Load more regolith (%d/9 shields placed).", deployed)
    end
    self.guide = { level = "tip", station = station, text = text, levelIndex = o.level }
  end
  -- read a new task aloud once it appears (after the current sentence)
  if self.guide.text ~= self.lastGuideText then
    self.lastGuideText = self.guide.text
    if self.guide.station or self.guide.level ~= "tip" then TTS.auto(self.guide.text, true) end
  end
  local g = self.guide
  if g.station == "entrance" then
    local d = Map.entranceDoor
    g.target = d and { x = d.x + d.w / 2, y = d.y + d.h / 2 }
  elseif g.station == "outside" then
    local d = Map.outerDoor
    g.target = d and { x = d.x - 140, y = d.y + d.h / 2 }
  elseif g.station then
    local m = self:machineById(g.station)
    g.target = m and { x = m.x + m.w / 2, y = m.y + m.h / 2 }
  end
end

function Room:update(dt)
  self.time = self.time + dt
  if self.puzzles:isOpen() then
    -- the station is paused while Vulcan works on a mini-game
    self.vulcan.moving = false
    self.puzzles:update(dt)
    if self.fx then self.fx:update(dt) end
    return
  end
  local v = self.vulcan
  if not self:isOver() and not self.human.isSleeping then
    local oldX, oldY = v.x, v.y
    local animBefore = v.anim
    v:update(dt, self.isDown, self.bounds, self.human:isFatigued() and Room.TIRED_SPEED or 1)
    -- Slide along walls: try the full move, then each axis on its own.
    local nx, ny = v.x, v.y
    if self:_blocked(nx, ny) then
      if not self:_blocked(nx, oldY) and nx ~= oldX then v.x, v.y = nx, oldY
      elseif not self:_blocked(oldX, ny) and ny ~= oldY then v.x, v.y = oldX, ny
      else
        v.x, v.y = oldX, oldY
        -- corner help: caught on the edge of a doorway? slip sideways a little
        local mx, my = nx - oldX, ny - oldY
        for off = 2, Room.CORNER_SLIDE, 2 do
          local done = false
          for _, sgn in ipairs({ 1, -1 }) do
            local tx, ty = oldX + mx, oldY + my
            if mx == 0 then tx = oldX + sgn * off elseif my == 0 then ty = oldY + sgn * off end
            if (mx == 0 or my == 0) and not self:_blocked(tx, ty) then
              -- move only a small step sideways this frame
              local step = math.min(off, math.abs(mx + my))
              if mx == 0 then v.x = oldX + sgn * step else v.y = oldY + sgn * step end
              if self:_blocked(v.x, v.y) then v.x, v.y = oldX, oldY else done = true end
              break
            end
          end
          if done then break end
        end
      end
    end
    v.prevX, v.prevY, v.baseAnim = oldX, oldY, animBefore
    v:stepAnimation()
    -- tell the child why running is slow when Vulcan is tired
    if v.sprinting and self.human:isFatigued() and (self.tiredHintAt or -99) < self.time - 8 then
      self.tiredHintAt = self.time
      self:say("Vulcan is tired and can't run fast. Sleep in your bunk bed!")
    end
    -- Inside <-> outside through the outer airlock door
    local nowOut = Map.isOutside(v.x, v.y)
    if nowOut ~= self.outside then
      self.outside, self.fade = nowOut, 1
      self:_sound("sfx_door")
      if nowOut then
        self.dust:goOutside()
        self.dust:collectSuitDust(20)
        self:say("You're on the Moon! Moon dust sticks to your suit.")
        self:_completeTask("outside")
      else
        self:say("Back in the airlock. Brush off the Moon dust!")
      end
    end
    if nowOut and v.moving then
      self.dust:collectSuitDust(dt * 10)
      if self.fx then self.fx:footprint(v.x, v.y + v.radius - 4) end
    end

    -- Leaving the airlock into the corridor: only the first crossing counts.
    if oldX < Map.ENTRANCE_X and v.x >= Map.ENTRANCE_X
        and v.y >= Map.ENTRANCE_Y1 and v.y <= Map.ENTRANCE_Y2 then
      local result = self.ls:enterCabin()
      if result == "clean" then
        self:say(Room.TEXT.cleanEntry)
        self:_label("Clean entry!", v.x, v.y - 100, { 0.36, 0.89, 0.49, 1 })
      elseif result == "dirty" then
        self:say(Room.TEXT.dirtyEntry)
        self:_effect("dust", v.x + 30, v.y, 30)
      end
      self:_completeTask("entrance")
    end
  else
    v.moving = false
  end
  self.fade = math.max(0, self.fade - dt * 2.5)
  self:_updateCamera()

  self.ls:update(dt)
  for _, text in ipairs(self.ls:popEvents()) do
    self.news, self.newsTimer = text, Room.NEWS_SECONDS
  end
  for _, m in ipairs(self.machines) do m.act = math.max(0, m.act - dt / 2.5) end
  if self.messageTimer > 0 then
    self.messageTimer = self.messageTimer - dt
    if self.messageTimer <= 0 then self.message = nil end
  end
  if self.newsTimer > 0 then
    self.newsTimer = self.newsTimer - dt
    if self.newsTimer <= 0 then self.news = nil end
  end
  if self.unlockCard then
    self.unlockCard.timer = self.unlockCard.timer - dt
    if self.unlockCard.timer <= 0 then self.unlockCard = nil end
  end
  self:_checkAutoTasks()
  self:_refreshGuide()
  if self.fx then self.fx:update(dt) end
  if self.renderer then self.renderer:update(dt, v, function(d) return self:isDoorLocked(d) end) end
end

-- (sx, sy) are SCREEN coordinates. Returns the station clicked (or nil).
-- Runs a station's action (after its mini-game was won, or directly when
-- mini-games are off): messages, effects, sounds and mission progress.
function Room:_runStation(m, fromPuzzle)
  local ok, reason, extra = m.run(self.ls)
  if ok and m.repeatRun and fromPuzzle then
    -- e.g. one excavation fills the whole regolith hopper
    for _ = 1, 8 do
      local again, _, more = m.run(self.ls)
      if not again then break end
      extra = (extra or 0) + (more or 0)
    end
  end
  if ok then
    self:say(type(m.success) == "function" and m.success(extra) or m.success)
    self:_sound("sfx_ok")
    m.act = 1
    if m.fx then
      self:_effect(m.fx[1], m.x + m.w / 2, m.y + m.h / 3, 16)
      self:_label(m.fx[2], m.x + m.w / 2, m.y - 10)
    end
    -- the shield task only counts once every section is covered
    if m.id ~= "shield" then self:_completeTask(m.id) end
  else
    self:_problem(m, reason)
  end
  self:_checkAutoTasks()
  self:_refreshGuide()
  return ok
end

function Room:_problem(m, reason)
  local text = m.problems[reason] or "That station can't help right now."
  if reason == "cooldown" then text = string.format(text, math.ceil(self.ls.co2CleanerCooldown)) end
  self:say(text)
  self:_sound("sfx_error")
end

-- Options a station's mini-game needs from the live mission
function Room:_puzzleOptions(m)
  local opts = {}
  if m.puzzle == "armor" then
    local rad = self.ls.radiation
    opts.sections, opts.alreadyShielded = {}, {}
    for i, id in ipairs(rad.order) do
      local sec = rad.sections[id]
      opts.sections[i] = sec.name
      opts.alreadyShielded[i] = sec.shielded
    end
    local left = rad.phase == "warning" and rad:timeToStorm() or nil
    opts.timeLimit = math.max(30, math.min(75, left or 75))
  end
  return opts
end

-- Opens the station's mini-game; winning it runs the station
function Room:_startPuzzle(m)
  self:_sound("sfx_click")
  local cls = PuzzleManager.REGISTRY[m.puzzle]
  if cls then TTS.auto(cls.title .. ". " .. (cls.hint or "")) end
  self.puzzles:start(m.puzzle, self:_puzzleOptions(m), function(won, p, cancelled)
    if won then
      self:_runStation(m, true)
    elseif not cancelled then
      self:say("Not quite! Try the " .. self:_t(m.title) .. " again.")
      self:_sound("sfx_error")
    end
  end)
end

-- (sx, sy) are SCREEN coordinates. Returns the station clicked (or nil).
function Room:mousepressed(sx, sy, button)
  if self.puzzles:isOpen() then
    local before = self.puzzles.active
    self.puzzles:mousepressed(sx, sy, button)
    if self.puzzles.active == before and before and before.state == "play" then self:_sound("sfx_hover") end
    return nil
  end
  if button ~= 1 then return nil end
  local sp = Room.SPEAKER
  if (sx - sp.x) ^ 2 + (sy - sp.y) ^ 2 <= sp.hit * sp.hit then
    self:_sound("sfx_click")
    TTS.speak(self:readAloudText())
    return nil
  end
  if self.unlockCard and self.unlockCard.timer < 5.2 then self.unlockCard = nil; self:_sound("sfx_click") end
  self:_updateCamera()
  local m = self:machineAt(self:screenToWorld(sx, sy))
  if not m then return nil end
  if self:isOver() then
    self:say(Room.TEXT.missionOver)
    self:_sound("sfx_error")
  elseif self:isRoomLocked(m.room) then
    self:_sound("sfx_error")
    local n = self.mission:levelOf(m.room)
    self:say(string.format("Locked! This opens at Level %d.", n or 0))
  elseif not self:isNear(m) then
    self:say(Room.TEXT.tooFar)
    self:_sound("sfx_error")
  elseif self.usePuzzles and m.puzzle then
    local ok, reason = m.check(self.ls)
    if ok then self:_startPuzzle(m) else self:_problem(m, reason) end
  else
    self:_runStation(m)
    return m
  end
  self:_checkAutoTasks()
  self:_refreshGuide()
  return m
end

function Room:mousereleased(sx, sy, button)
  if self.puzzles:isOpen() then self.puzzles:mousereleased(sx, sy, button) end
end

function Room:mousemoved(sx, sy)
  if self.puzzles:isOpen() then self.puzzles:mousemoved(sx, sy) end
end

-- Clicks the centre of a station (world) through the screen, as a player would.
function Room:clickStation(m)
  self:_updateCamera()
  local sx, sy = self:worldToScreen(m.x + m.w / 2, m.y + m.h / 2)
  return self:mousepressed(sx, sy, 1)
end

function Room:keypressed(key)
  if self.puzzles:isOpen() then
    if key == "escape" then self:_sound("sfx_click") end
    self.puzzles:keypressed(key)
    return
  end
  -- R: try the level again (after a win: a new mission from Level 1)
  if key == "r" then self:reset(self:checkpoint()); self:_sound("sfx_click") end
  if key == "tab" then self.showTablet = not self.showTablet; self:_sound("sfx_click") end
  if key == "e" and not self:isOver() then
    local m = self:_nearestMachine()
    if m then self:clickStation(m) else self:say("Move closer to a machine.") end
  end
end

------------------------------------------------------------------------------
-- Drawing (love only)
------------------------------------------------------------------------------

function Room:_initDrawing()
  if self.renderer then return end
  local StationRender = require("src.render.station_render")
  self.Theme = require("src.ui.theme")
  self.Machines = require("src.render.machines")
  self.Props = require("src.render.props")
  self.Exterior = require("src.render.exterior")
  self.HUD = require("src.ui.hud")
  self.Icons = require("src.ui.icons")
  self.fx = require("src.render.fx").new()
  self.renderer = StationRender.new()
  self.renderer:build()
end

function Room:_t(s) return (s:gsub("₂", "2")) end

-- Name plate under each station + highlight when close / when it needs help
function Room:_drawPlate(m)
  local lg = love.graphics
  local T, C = self.Theme, self.Theme.C
  local ok, reason = m.check(self.ls)
  local tag = (not ok) and Room.STATE_TAGS[reason] or nil
  local missing = tag and tag[2] == "red"
  local near = self:isNear(m) and not self:isOver()
  local pulse = 0.55 + 0.45 * math.sin(self.time * 6)
  if near or missing then
    if missing then T.set(C.critical, near and 1 or pulse) else T.set(C.cyan) end
    lg.setLineWidth(4); lg.rectangle("line", m.x - 6, m.y - 6, m.w + 12, m.h + 12, 10, 10); lg.setLineWidth(1)
  end
  local title = self:_t(m.title)
  local line, lineColor = m.subtitle, C.cyanLight
  if tag then line, lineColor = tag[1], missing and C.critical or C.metalShade
  elseif near then line = "Click or press E!" ; lineColor = C.caution end
  local f1, f2 = T.font(15), T.font(12)
  local info = near and self:_t(m.info(self.ls)) or nil
  local pw = math.max(140, I18n.width(f1, title) + 26, info and (I18n.width(f2, info) + 26) or 0)
  local ph = near and 56 or 40
  local px, py = m.x + m.w / 2 - pw / 2, m.y + m.h + 12
  local v = self.vulcan
  local fade = (v.x + 30 > px and v.x - 30 < px + pw and v.y + v.radius > py and v.y + v.radius - 96 < py + ph) and 0.35 or 1
  local pts = T.cutPoints(px, py, pw, ph, 8)
  T.set(C.space, 0.9 * fade); lg.polygon("fill", pts)
  T.set(missing and C.critical or C.cyanMid, fade); lg.setLineWidth(2); lg.polygon("line", pts); lg.setLineWidth(1)
  lg.setFont(f1); T.set(C.white, fade); lg.printf(title, px, py + 4, pw, "center")
  lg.setFont(f2); T.set(lineColor, fade); lg.printf(self:_t(line), px, py + 22, pw, "center")
  if info then T.set(C.offWhite, 0.8 * fade); lg.printf(info, px, py + 38, pw, "center") end
end

-- Speech bubble above Vulcan with the last action's message
function Room:_drawBubble()
  if not self.message then return end
  local lg = love.graphics
  local T, C = self.Theme, self.Theme.C
  local v = self.vulcan
  local f = T.font(15)
  local text = self:_t(self.message)
  local w = math.min(340, I18n.width(f, text) + 28)
  local lines
  if I18n.lang ~= "en" then
    local af = self.Theme.arabicFontFor(f) or f
    lines = I18n.wrap(af, I18n.t(text), w - 24)
  else
    lines = select(2, f:getWrap(text, w - 24))
  end
  local h = #lines * f:getHeight() + 18
  local x, y = v.x - w / 2, v.y - 96 - h - 14
  local a = math.min(1, self.messageTimer * 3)
  T.set(C.ink, a); lg.rectangle("fill", x - 3, y - 3, w + 6, h + 6, 14, 14)
  T.set(C.offWhite, a); lg.rectangle("fill", x, y, w, h, 12, 12)
  lg.polygon("fill", v.x - 10, y + h - 1, v.x + 10, y + h - 1, v.x, y + h + 14)
  T.set(C.ink, a); lg.setFont(f); lg.printf(text, x + 12, y + 9, w - 24, "center")
end

-- Arrow from Vulcan towards the guide's target station
function Room:_drawGuideArrow()
  local g = self.guide
  if not g or not g.target or self:isOver() then return end
  local lg = love.graphics
  local T, C = self.Theme, self.Theme.C
  local v = self.vulcan
  local dx, dy = g.target.x - v.x, g.target.y - v.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local col = g.level == "tip" and C.cyan or (T.STATUS[g.level] or C.cyan)
  local bob = math.sin(self.time * 5) * 6
  local tx, ty = g.target.x, g.target.y
  local m = g.station and self:machineById(g.station)
  if m then ty = m.y + 60 end
  T.set(col); lg.polygon("fill", tx - 16, ty - 86 + bob, tx + 16, ty - 86 + bob, tx, ty - 62 + bob)
  T.set(C.ink); lg.setLineWidth(3)
  lg.polygon("line", tx - 16, ty - 86 + bob, tx + 16, ty - 86 + bob, tx, ty - 62 + bob)
  lg.setLineWidth(1)
  if dist < 160 then return end
  local a = math.atan2(dy, dx)
  local r = 66
  lg.push()
  lg.translate(v.x + math.cos(a) * r, v.y - 30 + math.sin(a) * r)
  lg.rotate(a)
  self.Icons.draw("arrow", 0, 0, 34 + bob * 0.5, col)
  lg.pop()
end

local function overlaps(x, y, w, h, cx, cy, cw, ch)
  return x < cx + cw and x + w > cx and y < cy + ch and y + h > cy
end

function Room:_onScreen(r, pad)
  pad = pad or 80
  return overlaps(r.x - pad, r.y - pad, r.w + 2 * pad, r.h + 2 * pad, self.camX, self.camY, Room.VIEW_W, Room.VIEW_H)
end

-- Grey "LOCKED" look over a room the child has not reached yet
function Room:_drawLockedRoom(r, t)
  local lg = love.graphics
  local T, C = self.Theme, self.Theme.C
  local parts = { r }
  if r.extra then for _, e in ipairs(r.extra) do parts[#parts + 1] = e end end
  for _, p in ipairs(parts) do
    T.set(C.spaceDeep, 0.5); lg.rectangle("fill", p.x + 4, p.y + 4, p.w - 8, p.h - 8, 8, 8)
    lg.push("all")
    lg.setScissor(p.x - self.camX + 4, p.y - self.camY + 4, p.w - 8, p.h - 8)
    T.set(C.white, 0.04)
    for k = -p.h, p.w, 46 do lg.polygon("fill", p.x + k, p.y, p.x + k + 18, p.y, p.x + k + 18 + p.h, p.y + p.h, p.x + k + p.h, p.y + p.h) end
    lg.pop()
  end
  local n, lv = self.mission:levelOf(r.id)
  local cx, cy = r.x + r.w / 2, r.y + r.h / 2
  local w, h = 300, 112
  T.panel(cx - w / 2, cy - h / 2, w, h, { cut = 14, fill = C.space, alpha = 0.92, edge = C.metalShade, lineWidth = 3 })
  -- padlock
  local lx, ly = cx - w / 2 + 48, cy + 4
  T.set(C.ink); lg.setLineWidth(9); lg.arc("line", "open", lx, ly - 12, 15, math.pi, 2 * math.pi)
  T.set(C.metalShade); lg.setLineWidth(5); lg.arc("line", "open", lx, ly - 12, 15, math.pi, 2 * math.pi); lg.setLineWidth(1)
  T.box(lx - 24, ly - 12, 48, 38, C.caution, 6, 3)
  T.set(C.ink); lg.circle("fill", lx, ly + 4, 5); lg.rectangle("fill", lx - 2, ly + 4, 4, 12)
  lg.setFont(T.font(22)); T.set(C.white); lg.print("LOCKED", cx - w / 2 + 90, cy - 44)
  lg.setFont(T.font(15)); T.set(C.cyanLight)
  lg.print(string.format("LEVEL %d: %s", n or 0, lv and lv.name or ""), cx - w / 2 + 90, cy - 14)
  lg.setFont(T.font(13)); T.set(C.offWhite, 0.8)
  lg.printf(string.format("Finish Level %d to open", (n or 1) - 1), cx - w / 2 + 90, cy + 10, w - 100, "left")
end

function Room:_drawInside(ls, t)
  local lg = love.graphics
  local T, C = self.Theme, self.Theme.C
  local Props = self.Props
  T.set(T.hex("#100E26")); lg.rectangle("fill", 0, 0, Room.WIDTH, Room.HEIGHT)
  lg.push()
  lg.translate(-math.floor(self.camX), -math.floor(self.camY))
  self.renderer:drawStatic()
  self.fx:drawGround()
  self.renderer:drawLive(ls, t, function(d) return self:isDoorLocked(d) end)
  -- wall-mounted props behind everything
  for _, p in ipairs(self.props) do
    if p.wall and self:_onScreen(p) then
      local locked = self:isRoomLocked(p.room)
      if locked then Props.gray(true) end
      Props.draw(p.sprite, p.x, p.y, p.w, p.h, { shadow = false })
      if locked then Props.gray(false) end
    end
  end
  -- machines, furniture and Vulcan sorted by depth (feet line)
  local items = {}
  for _, m in ipairs(self.machines) do
    if self:_onScreen(m) then items[#items + 1] = { y = m.y + m.h, m = m } end
  end
  for _, p in ipairs(self.props) do
    if not p.wall and self:_onScreen(p) then items[#items + 1] = { y = p.y + p.h, p = p } end
  end
  items[#items + 1] = { y = self.vulcan.y + self.vulcan.radius, vulcan = true }
  table.sort(items, function(a, b) return a.y < b.y end)
  for _, it in ipairs(items) do
    if it.vulcan then
      self.vulcan:draw()
    else
      local room = it.m and it.m.room or it.p.room
      local locked = self:isRoomLocked(room)
      if locked then Props.gray(true) end
      if it.m then self.Machines.draw(it.m, ls, t, it.m.act)
      else Props.draw(it.p.sprite, it.p.x, it.p.y, it.p.w, it.p.h) end
      if locked then Props.gray(false) end
    end
  end
  self.renderer:drawOverlays(ls, t)
  for _, r in ipairs(Map.rooms) do
    if self:isRoomLocked(r.id) and self:_onScreen(r, 0) then self:_drawLockedRoom(r, t) end
  end
  for _, m in ipairs(self.machines) do
    if not self:isRoomLocked(m.room) and self:_onScreen(m) then self:_drawPlate(m) end
  end
  self.fx:draw()
  self:_drawGuideArrow()
  self:_drawBubble()
  lg.pop()
end

function Room:_drawOutside(ls, t)
  local lg = love.graphics
  local X = self.Exterior
  X.drawSky(self.camX, self.camY, t, ls, Room.WIDTH, Room.HEIGHT)
  lg.push()
  lg.translate(-math.floor(self.camX), -math.floor(self.camY))
  X.drawGround(t)
  self.fx:drawGround()
  X.drawHabitat(ls, t, function(id) return self:isRoomLocked(id) end, math.floor(self.camY))
  X.drawArtifacts(ls, t, function(level) return (not self.campaign) or level <= self.mission.level end)
  self.vulcan:draw()
  self.fx:draw()
  self:_drawGuideArrow()
  self:_drawBubble()
  lg.pop()
end

function Room:draw()
  self:_initDrawing()
  local lg = love.graphics
  local T, C = self.Theme, self.Theme.C
  local ls, t = self.ls, self.time
  if self.outside then self:_drawOutside(ls, t) else self:_drawInside(ls, t) end

  -- Night, storm and emergency tints over the playfield
  if not ls:isSunUp() then T.set({ 0.03, 0.04, 0.2 }, 0.3); lg.rectangle("fill", 0, 0, Room.WIDTH, Room.HEIGHT) end
  if ls.radiation.phase == "storm" then
    T.set(C.critical, 0.08 + 0.05 * math.sin(t * 4)); lg.rectangle("fill", 0, 0, Room.WIDTH, Room.HEIGHT)
  end
  if ls:isAnyCritical() and not self:isOver() then
    T.set(C.critical, 0.35 + 0.25 * math.sin(t * 6)); lg.setLineWidth(10)
    lg.rectangle("line", 5, 5, Room.WIDTH - 10, Room.HEIGHT - 10, 14, 14); lg.setLineWidth(1)
  end
  if self.fade > 0 then lg.setColor(0, 0, 0, self.fade); lg.rectangle("fill", 0, 0, Room.WIDTH, Room.HEIGHT) end

  -- HUD
  self.HUD.drawVitals(ls, t, ls.autopilot)
  self.HUD.drawClock(ls, self.outside)
  if self.campaign then self.HUD.drawLevel(self.mission, t) end
  self.HUD.drawBanner(ls, self.guide, t)
  self.HUD.drawSpeaker(Room.SPEAKER, TTS.enabled, t, TTS.blocked)
  if self.showTablet then self.HUD.drawCards(ls, t) end
  self.HUD.drawNews(self.news and self:_t(self.news))
  if self.unlockCard then self.HUD.drawUnlock(self.unlockCard, t) end

  if self:isOver() then self:_drawGameOver() elseif self.missionComplete then self:_drawMissionComplete() end
  self.puzzles:draw(t)
end

function Room:_drawMissionComplete()
  local lg, T, C = love.graphics, self.Theme, self.Theme.C
  T.set(C.spaceDeep, 0.72); lg.rectangle("fill", 0, 0, Room.WIDTH, Room.HEIGHT)
  T.panel(300, 175, 680, 350, { cut = 26, fill = C.space, alpha = 0.97, edge = C.good, lineWidth = 3 })
  T.outlinedText("MISSION COMPLETE!", 300, 220, 680, "center", C.good, C.ink, T.font(38))
  lg.setFont(T.font(22)); T.set(C.white); lg.printf("You mastered all 8 life-support systems!", 340, 285, 600, "center")
  lg.setFont(T.font(18)); T.set(C.cyanLight); lg.printf("Science tip: water, air, food, power and shielding all work together.", 350, 330, 580, "center")
  local stars = self:starRating()
  lg.setFont(T.font(36)); T.set(C.caution); lg.printf(string.rep("★ ", stars), 300, 385, 680, "center")
  lg.setFont(T.font(19)); T.set(C.cyanLight); lg.printf("Press R to play again", 300, 470, 680, "center")
end

function Room:_drawGameOver()
  local lg = love.graphics
  local T, C = self.Theme, self.Theme.C
  T.set(C.spaceDeep, 0.75); lg.rectangle("fill", 0, 0, Room.WIDTH, Room.HEIGHT)
  local bx, by, bw, bh = 290, 170, 700, 380
  T.panel(bx, by, bw, bh, { cut = 26, fill = C.space, alpha = 0.97, edge = C.critical, lineWidth = 3 })
  self.Icons.draw("alert", bx + bw / 2, by + 52, 52, C.critical)
  T.outlinedText("MISSION NEEDS YOUR HELP!", bx, by + 88, bw, "center", C.white, C.ink, T.font(34))
  lg.setFont(T.font(24)); T.set(C.caution)
  lg.printf(self:_t(self.ls.failureCause or ""), bx + 40, by + 146, bw - 80, "center")
  T.panel(bx + 50, by + 222, bw - 100, 86, { cut = 12, fill = C.cyanDark, alpha = 0.6, edge = C.cyan })
  lg.setFont(T.font(14)); T.set(C.cyan); lg.printf("SCIENCE LESSON", bx + 50, by + 232, bw - 100, "center")
  lg.setFont(T.font(18)); T.set(C.white)
  lg.printf(self:_t(self.ls.failureLesson or ""), bx + 70, by + 254, bw - 140, "center")
  lg.setFont(T.font(20)); T.set(C.cyanLight, 0.7 + 0.3 * math.sin(self.time * 4))
  lg.printf("Press R to try again   -   Esc for the menu", bx, by + bh - 48, bw, "center")
end

return Room
