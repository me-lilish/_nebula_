-- Plain-Lua tests for the habitat room (no Love2D needed): layout, walking,
-- reachability, clicks, the airlock dust flow, messages and game over.
-- Run from the repository root:  lua tests/test_room.lua

package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq = T.test, T.eq
local LSC, AirC, DustC = T.C, T.AirC, T.DustC
local Room = require("src.room_scene")
local Map = require("src.station_map")

local held = {}
local function isDown(k) return held[k] == true end
local function newRoom() held = {}; return Room.new({ isDown = isDown }) end
local function newStillRoom()
  held = {}
  local cfg = T.stillConfigs()
  cfg.isDown = isDown
  return Room.new(cfg)
end

local function station(room, id) return room:machineById(id) end
local function centre(m) return m.x + m.w / 2, m.y + m.h / 2 end
local function click(room, m) return room:clickStation(m) end
local function goTo(room, m)
  local x, y = room:spotNear(m)
  assert(x, "no free spot next to " .. m.id)
  room.vulcan.x, room.vulcan.y = x, y
end
local function use(room, id) local m = station(room, id); goTo(room, m); click(room, m); return room.message end
local function walk(room, key, frames)
  held[key] = true
  for _ = 1, frames do room:update(0.02) end
  held[key] = false
end
-- Stand inside the airlock just before the habitat entrance and walk in / out.
local function walkIn(room)
  room.vulcan.x = Room.ENTRANCE_X - 60
  room.vulcan.y = 1100
  walk(room, "right", 30)
  assert(room.vulcan.x > Room.ENTRANCE_X, "did not cross the entrance")
end
local function walkOut(room)
  walk(room, "left", 30)
  assert(room.vulcan.x < Room.ENTRANCE_X, "did not go back into the airlock")
end

local ROLE = {
  dustoff = "useSuitDustOff", water = "runWaterRecycler", toilet = "useToilet",
  oxygen = "runOxygenMaker", co2 = "runCO2Cleaner", recycler = "runCO2Recycler",
  trace = "serviceDustFilter", valves = "balanceWaterTanks", growlight = "tuneGrowLights", greenhouse = "harvestGreenhouse", foodstorage = "storeCrops",
  compost = "runCompost", foodstation = "eatMeal", solar = "aimSolar", battery = "togglePowerSaver",
  regolith = "loadRegolith", shield = "deployShields", sleep = "toggleSleep", recycle = "recycleParts",
}
local ACTIONS = {}
for _, fn in pairs(ROLE) do ACTIONS[fn] = true end
local function spy(room)
  local calls = {}
  for name in pairs(ACTIONS) do
    calls[name] = 0
    local original = room.ls[name]
    room.ls[name] = function(ls, ...) calls[name] = calls[name] + 1; return original(ls, ...) end
  end
  return calls
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------
test("all 19 player-facing stations have child names and technical names", function()
  local r = newRoom()
  local expect = {
    dustoff = "Brush Station", water = "Water Recycler", toilet = "Bathroom Pod",
    oxygen = "Oxygen Generator", co2 = "CO₂ Scrubber", recycler = "CO₂ Recycler", trace = "Dust Filter Unit",
    greenhouse = "Hydroponic Garden", foodstorage = "Food Cooler", compost = "Composter",
    foodstation = "Food Dispenser", solar = "Solar Array Control", battery = "Battery Bank",
    regolith = "Regolith Hopper", shield = "Shield Holo-Table", sleep = "Bunk Bed", recycle = "Machine Recycler",
    valves = "Tank Valves", growlight = "Grow-Light Timer",
  }
  eq(#r.machines, 19)
  for id, title in pairs(expect) do
    local m = station(r, id)
    if not m then error("missing station " .. id) end
    eq(m.title, title, id)
    if not m.tech or #m.tech == 0 then error("no technical label on " .. id) end
  end
  eq(station(r, "oxygen").tech, "Water electrolysis"); eq(station(r, "co2").tech, "Carbon Dioxide Removal")
  eq(station(r, "toilet").tech, "Waste Hygiene Unit"); eq(station(r, "recycler").tech, "Sabatier reactor")
end)
test("stations do not overlap and each sits inside its room", function()
  local r = newRoom()
  for i, a in ipairs(r.machines) do
    for j, b in ipairs(r.machines) do
      if i < j and a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then
        error(a.id .. " overlaps " .. b.id)
      end
    end
    local room = Map.roomById(a.room)
    if not room then error(a.id .. " has no room") end
    local cx, cy = a.x + a.w / 2, a.y + a.h - 4
    if Map.roomAt(cx, cy) ~= room then error(a.id .. " is outside its room " .. room.id) end
  end
end)
test("stations follow the team's station layout", function()
  local r = newRoom()
  -- the 8-system design brief: each system's machines live in its own room
  local expect = {
    sleep = "quarters", foodstation = "quarters", toilet = "quarters",          -- 1 human
    dustoff = "airlock", trace = "airlock",                                     -- 2 dust
    water = "water", valves = "water",                                          -- 3 water
    greenhouse = "food", foodstorage = "food", growlight = "food",              -- 4 food
    compost = "waste", recycle = "waste",                                       -- 5 waste
    oxygen = "air", co2 = "air", recycler = "air",                              -- 6 air
    solar = "power", battery = "batteries",                                     -- 7 power
    regolith = "comms", shield = "comms",                                       -- 8 radiation
  }
  for id, room in pairs(expect) do eq(station(r, id).room, room, id) end
  eq(station(r, "water").title, "Water Recycler")
end)
test("room back walls are solid, except doors where corridors enter", function()
  local power = Map.roomById("power")
  eq(Map.isWalkablePoint(power.x + 200, power.y + 20), false, "standing on the back wall")
  eq(Map.isWalkablePoint(power.x + 200, power.y + Map.WALL + 40), true, "room floor")
  for _, d in ipairs(Map.doors) do
    eq(Map.isWalkablePoint(d.x + d.w / 2, d.y + d.h / 2), true, "doorway")
  end
end)
test("all nine rooms from the layout exist and are joined by corridors", function()
  eq(#Map.rooms, 9)
  for _, id in ipairs({ "power", "water", "quarters", "airlock", "comms", "batteries", "food", "air", "waste" }) do
    if not Map.roomById(id) then error("missing room " .. id) end
  end
end)
test("every station can be reached on foot from the airlock", function()
  local r = newRoom()
  local step = 12
  local seen, queue = {}, { { Room.START_X, Room.START_Y } }
  local function key(x, y) return math.floor(x / step) .. ":" .. math.floor(y / step) end
  seen[key(Room.START_X, Room.START_Y)] = true
  local reachable = {}
  while #queue > 0 do
    local p = table.remove(queue)
    reachable[#reachable + 1] = p
    for _, d in ipairs({ { step, 0 }, { -step, 0 }, { 0, step }, { 0, -step } }) do
      local nx, ny = p[1] + d[1], p[2] + d[2]
      local k = key(nx, ny)
      if not seen[k] and not r:_blocked(nx, ny) then seen[k] = true; queue[#queue + 1] = { nx, ny } end
    end
  end
  for _, m in ipairs(r.machines) do
    local ok = false
    for _, p in ipairs(reachable) do
      r.vulcan.x, r.vulcan.y = p[1], p[2]
      if r:isNear(m) then ok = true; break end
    end
    if not ok then error(m.id .. " cannot be reached") end
  end
end)
test("every reason a station can report has a visible tag", function()
  for _, reason in ipairs({ "no_water", "no_power", "no_co2", "no_hydrogen", "storage_full", "wastewater_full",
      "tanks_full", "filter_full", "cooldown", "nothing_to_recycle", "no_co2_in_air", "already_clean",
      "urine_full", "waste_storage_full", "just_ate", "no_food", "emergency", "storm_alert", "growing",
      "no_light", "no_fertilizer", "crate_full", "no_crops", "no_scraps", "fertilizer_full", "night",
      "already_aimed", "all_shielded", "loader_full", "no_regolith" }) do
    if not Room.STATE_TAGS[reason] then error("no tag for " .. reason) end
  end
end)

------------------------------------------------------------------------------
-- Walking and clicking
------------------------------------------------------------------------------
test("Vulcan starts outside on the Moon, too far from every station", function()
  local r = newRoom()
  if not Map.inRect(r.vulcan.x, r.vulcan.y, Map.outside) then error("should start on the Moon outside") end
  eq(Map.roomAt(r.vulcan.x, r.vulcan.y), nil)
  for _, m in ipairs(r.machines) do eq(r:isNear(m), false, m.id) end
end)
test("walls block Vulcan: the Moon pad only opens into the airlock", function()
  local r = newRoom()
  walk(r, "up", 200)
  if r.vulcan.y < Map.outside.y then error("walked off the Moon pad") end
  local r2 = newRoom(); walk(r2, "right", 60)
  eq(Map.roomAt(r2.vulcan.x, r2.vulcan.y).id, "airlock")
end)
test("clicking from too far says 'Move Vulcan closer!' and does nothing", function()
  local r = newRoom(); local calls = spy(r)
  click(r, station(r, "oxygen"))
  eq(r.message, "Move Vulcan closer!"); eq(calls.runOxygenMaker, 0)
end)
test("walking with the movement keys reaches the Suit Dust-Off", function()
  local r = newRoom()
  walk(r, "right", 60); walk(r, "up", 20)
  eq(r:isNear(station(r, "dustoff")), true)
end)
test("Vulcan cannot walk through a station", function()
  local r = newRoom()
  local m = station(r, "dustoff"); goTo(r, m)
  assert(r.vulcan.y > m.y + m.h, "should stand below the Dust-Off")
  walk(r, "up", 60)
  if r.vulcan.y - r.vulcan.radius < m.y + m.h - 0.001 then error("Vulcan entered the station") end
end)
for id, fn in pairs(ROLE) do
  test("clicking " .. id .. " calls only " .. fn, function()
    local r = newStillRoom(); local calls = spy(r)
    use(r, id)
    for name in pairs(ACTIONS) do eq(calls[name], name == fn and 1 or 0, name) end
  end)
end
test("clicking empty floor or with the right button does nothing", function()
  local r = newRoom(); local calls = spy(r)
  eq(r:mousepressed(600, 700, 1), nil)
  local m = station(r, "oxygen"); goTo(r, m)
  local x, y = r:worldToScreen(centre(m)); r:mousepressed(x, y, 2)
  eq(calls.runOxygenMaker, 0); eq(r.message, nil)
end)

------------------------------------------------------------------------------
-- Child-friendly results
------------------------------------------------------------------------------
test("air and water messages", function()
  local r = newStillRoom()
  eq(use(r, "oxygen"), "Great! Fresh oxygen is flowing.")
  r.ls.processWater = 0
  eq(use(r, "oxygen"), "The Oxygen Generator needs clean water! Run the Water Recycler.")
  r.ls.processWater, r.ls.battery = 20, 0
  eq(use(r, "oxygen"), "The Oxygen Generator needs power!")
  r.ls.battery = 80
  eq(use(r, "recycler"), "The CO₂ Recycler needs CO₂! Use the CO₂ Scrubber first.")
  r.ls.wastewater = 0
  eq(use(r, "water"), "No used water yet.")
end)
test("toilet: use, then seal after three uses", function()
  local r = newStillRoom()
  for _ = 1, 3 do eq(use(r, "toilet"), "Ahh, better! Urine goes to the Water Recycler.") end
  eq(use(r, "toilet"), "Waste sealed safely. The Bathroom Pod is ready again!")
end)
test("food chain messages", function()
  local r = newStillRoom()
  eq(use(r, "greenhouse"), "The plants are still growing. Come back later!")
  r.ls.growth = 100
  eq(use(r, "greenhouse"), "Harvest time! Crops and plant scraps collected.")
  eq(use(r, "foodstorage"), "Crops packed into the Food Cooler.")
  eq(use(r, "compost"), "Plant scraps turned into fertilizer for the garden.")
  eq(use(r, "foodstation"), "Yum! Vulcan ate a warm meal.")
  eq(use(r, "foodstation"), "You just ate! Try again a bit later.")
end)
test("power and radiation messages", function()
  local r = newStillRoom()
  eq(use(r, "solar"), "The panels already point at the Sun.")
  eq(use(r, "battery"), "Power Saver ON: grow lamps off, lights dimmed.")
  eq(use(r, "battery"), "Power Saver OFF: everything at full power.")
  eq(use(r, "shield"), "Load regolith first at the Regolith Hopper!")
  eq(use(r, "regolith"), "Loaded 3 units of Moon soil (regolith).")
  eq(use(r, "shield"), "3 shield sections placed. The crew is safer!")
end)
test("Sleep Pod fast-forwards eight simulated hours", function()
  local r = newStillRoom()
  eq(use(r, "sleep"), "Eight hours passed safely. Vulcan feels rested!")
  eq(r.human.isSleeping, false)
  T.near(r.ls.missionTime, 48)
end)
test("radiation warning appears as news in the room", function()
  local r = newStillRoom()
  r.ls:triggerRadiationWarning(); r:update(0.1)
  assert(r.news and r.news:find("Radiation warning"), tostring(r.news))
end)

------------------------------------------------------------------------------
-- Airlock dust flow
------------------------------------------------------------------------------
test("clean entry: Suit Dust-Off, then walk in", function()
  local r = newStillRoom()
  eq(r.dust.suitDust, DustC.EVA_SUIT_DUST)
  eq(use(r, "dustoff"), "Suit clean! Safe to go in.")
  walkIn(r)
  eq(r.message, "Great job! You kept the cabin clean."); eq(r.dust.cabinDust, 0)
end)
test("dirty entry adds suit dust to the cabin once", function()
  local r = newStillRoom()
  walkIn(r)
  eq(r.message, "Oops! Dust entered the cabin."); eq(r.dust.cabinDust, 60)
  for _ = 1, 3 do walkOut(r); walk(r, "right", 30) end
  eq(r.dust.cabinDust, 60)
  eq(use(r, "trace"), "Fresh HEPA filter locked in - the cabin air is clean!"); eq(r.dust.dustCleanliness, 100)
end)
test("dust in the room never changes O2, CO2 or the air score", function()
  local r = newStillRoom()
  T.setAir(r.ls, 20.3, 0.62)
  local o2, co2, q = r.air.oxygenPercent, r.air.carbonDioxidePercent, r.air.airQuality
  walkIn(r); use(r, "trace"); use(r, "dustoff"); r:update(1)
  eq(r.air.oxygenPercent, o2); eq(r.air.carbonDioxidePercent, co2); eq(r.air.airQuality, q)
end)

------------------------------------------------------------------------------
-- Game over, reset, messages
------------------------------------------------------------------------------
test("game over: cause + lesson, stations refuse, Vulcan stops, R restarts", function()
  local r = newRoom(); local calls = spy(r)
  T.setAir(r.ls, 17, 0.04)
  for _ = 1, 310 do r:update(0.1) end
  eq(r:isOver(), true)
  eq(r.ls.failureCause, "The cabin ran out of safe oxygen.")
  assert(r.ls.failureLesson:find("clean water and power"))
  use(r, "oxygen"); eq(r.message, Room.TEXT.missionOver); eq(calls.runOxygenMaker, 0)
  local x = r.vulcan.x
  walk(r, "right", 20); eq(r.vulcan.x, x)
  r:keypressed("r")
  eq(r:isOver(), false); eq(r.air.oxygenPercent, AirC.START_O2_PERCENT)
  eq(r.dust.suitDust, DustC.EVA_SUIT_DUST); eq(r.vulcan.x, Room.START_X)
end)
test("Machine Recycler turns broken parts into spares", function()
  local r = newStillRoom()
  eq(use(r, "recycle"), "No broken parts to recycle right now.")
  r.ls.salvageParts = 3
  eq(use(r, "recycle"), "Recycled 3 broken parts into spares for repairs!")
  eq(r.ls.salvageParts, 0); eq(r.ls.spareParts, 3)
end)
test("walking out through the outer airlock door puts dust on the suit", function()
  local r = newStillRoom()
  use(r, "dustoff"); eq(r.dust.suitDust, 0)
  local d = Map.outerDoor
  r.vulcan.x, r.vulcan.y = d.x + d.w + 30, d.y + d.h / 2
  r:update(0.02); eq(r.outside, false)
  walk(r, "left", 60)
  eq(r.outside, true)
  assert(r.dust.suitDust > 0, "no dust collected outside")
  assert(r.vulcan.x < 0, "should walk out onto the open lunar field")
end)
test("messages disappear after a few seconds", function()
  local r = newRoom()
  click(r, station(r, "oxygen"))
  for _ = 1, 40 do r:update(0.1) end
  eq(r.message, nil)
end)

T.finish()
