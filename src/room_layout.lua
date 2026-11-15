--[[
  Room layout (pure data, no love.* calls)
  ========================================
  Where every machine and piece of furniture stands, room by room, following
  the 8-system design brief. Art comes from assets/props (see
  tools/build_props.py); sizes come from src/prop_sizes.lua so the layout can
  be checked by plain-Lua tests.

  place(sprite, cx, bottom, width) -> rect { x, y, w, h } of a sprite drawn
  with its bottom-centre at (cx, bottom), scaled to `width`.

  Layout.MACHINES[id] = rect (+ sprite) for each clickable station.
  Layout.PROPS        = furniture: { sprite, room, x, y, w, h, solid, wall }
     solid : Vulcan cannot walk through its foot area
     wall  : mounted on the back wall (always drawn behind Vulcan)
]]
local Sizes = require("src.prop_sizes")

local Layout = {}

local function place(sprite, cx, bottom, width)
  local s = Sizes[sprite]
  local h = s and math.floor(width * s[2] / s[1] + 0.5) or width
  return { sprite = sprite, x = cx - width / 2, y = bottom - h, w = width, h = h }
end
Layout.place = place

------------------------------------------------------------------------------
-- Machines (clickable stations)
------------------------------------------------------------------------------
local M = {}
-- SYSTEM 1  Crew Quarters & Personal Maintenance Bay
M.sleep = place("bunk", 2012, 252, 210)              -- bunk bed against the top-left wall
M.foodstation = place("food_dispenser", 2330, 306, 96) -- food dispenser beside the dining table
M.toilet = place("restroom", 2318, 646, 120)          -- bathroom pod, bottom-right corner
-- SYSTEM 2  Airlock & Suit Decontamination Bay
M.dustoff = place("brush_station", 262, 988, 140)     -- brushes + static mat inside the outer door
M.trace = place("air_filter", 575, 1032, 118)         -- dust filtration unit above the inner door
-- SYSTEM 3  Hydro-Plumbing & Storage Bay
M.water = { sprite = "purifier", x = 1086, y = 108, w = 318, h = 124 } -- 3-stage purifier, back wall
M.valves = { sprite = "water_tank", x = 1396, y = 494, w = 202, h = 148 } -- main storage tanks + valves
-- SYSTEM 4  Pantry & Hydroponics Bay
M.greenhouse = place("hydroponics", 2005, 1640, 250)  -- tiered grow unit, upper half
M.foodstorage = place("freezer", 2318, 1762, 120)     -- insulated cooler, right wall
M.growlight = place("temp_panel", 2323, 1462, 86)      -- grow-light timer + thermometer, right of the door
-- SYSTEM 5  Recycling & Salvage Workshop
M.recycle = place("shredder", 1172, 2196, 150)        -- shredder + furnace, back wall
M.compost = place("composter", 1572, 2202, 180)       -- organic composter, right side
-- SYSTEM 6  Atmospheric Control & Vent Hub
M.co2 = place("co2_scrubber", 1400, 1792, 150)        -- CO2 scrubber, centre
M.oxygen = place("o2_generator", 1492, 1946, 112)     -- electrolyzer, right wall
M.recycler = place("reactor", 1100, 1946, 86)         -- CO2 recycler (Sabatier reactor)
-- SYSTEM 7  Reactor & Main Electrical Grid Room
M.solar = place("power_console", 320, 404, 160)       -- power management unit, centre
M.battery = { sprite = "battery_rack", x = 60, y = 1716, w = 340, h = 84 } -- 3 battery towers
-- SYSTEM 8  Radiation Shielding & Command Center
M.shield = place("holo_table", 2010, 1236, 172)       -- tactical holo-table
M.regolith = place("regolith_hopper", 1990, 986, 120) -- regolith hopper / collector
Layout.MACHINES = M

------------------------------------------------------------------------------
-- Furniture and props
------------------------------------------------------------------------------
local P = {}
local function prop(room, sprite, cx, bottom, width, flags)
  local r = place(sprite, cx, bottom, width)
  r.room = room
  flags = flags or {}
  r.solid, r.wall, r.label = flags.solid, flags.wall, flags.label
  P[#P + 1] = r
  return r
end

-- Quarters
prop("quarters", "lockers", 2168, 214, 82, { solid = true })          -- bedside locker
prop("quarters", "sink", 2236, 170, 54, { wall = true })              -- mirror + sink vanity
prop("quarters", "fold_table", 2200, 432, 170, { solid = true })      -- dining table + stools
prop("quarters", "vitals_monitor", 2072, 646, 74, { solid = true })   -- vital signs monitor
prop("quarters", "first_aid", 1996, 640, 58, { solid = true })        -- first-aid cabinet
prop("quarters", "clipboard", 1950, 84, 38, { wall = true })          -- personal log
-- Airlock
prop("airlock", "lockers", 422, 1300, 104, { solid = true })          -- EVA suit lockers, left wall
prop("airlock", "gear_hooks", 420, 812, 92, { wall = true })          -- suit hooks
prop("airlock", "bench", 520, 1236, 130, { solid = true })            -- boot bench
prop("airlock", "filter_crate", 590, 1374, 84, { solid = true })      -- spare HEPA cartridges
prop("airlock", "filter_crate", 500, 1376, 74, { solid = true })
prop("airlock", "pressure_panel", 560, 864, 150, { solid = true })    -- gauge panel, control wall
-- Water
prop("water", "jug_rack", 960, 192, 150, { solid = true })            -- water jug shelving
prop("water", "plumbing_bench", 960, 562, 150, { solid = true })      -- pipe wrenches + seals
prop("water", "pipes", 1496, 82, 140, { wall = true })                -- blue + grey wall pipes
prop("water", "workstation", 1500, 232, 128, { solid = true })        -- diagnostic terminal
prop("water", "clipboard", 1582, 176, 40, { wall = true })            -- water quality log
-- Food
prop("food", "food_lockers", 2318, 1560, 112, { wall = true })        -- pantry cabinets, upper right
prop("food", "prep_counter", 1995, 1762, 150, { solid = true })       -- steel prep counter
prop("food", "ration_crates", 1962, 1920, 110, { solid = true })      -- rations + seed packets
prop("food", "workstation", 2318, 1920, 120, { solid = true })        -- botanical log station
-- Waste
prop("waste", "biohazard", 1072, 2376, 92, { solid = true })          -- bio-hazard barrels
prop("waste", "salvage_bench", 1372, 2236, 150, { solid = true })     -- scrap sorting table
prop("waste", "vent_hood", 1572, 2072, 150, { wall = true })          -- hood over the composter
prop("waste", "plumbing_bench", 1012, 2190, 120, { solid = true })    -- spare-parts rack
prop("waste", "gear_hooks", 1010, 2088, 70, { wall = true })          -- apron hooks
-- Air
prop("air", "gas_rack", 978, 1738, 106, { solid = true })             -- O2 / N2 cylinders
prop("air", "ladder", 1080, 1722, 40, { wall = true })                -- duct ladder
prop("air", "o2_masks", 1146, 1692, 48, { wall = true })              -- mask locker by the exit
prop("air", "o2_masks", 1538, 1764, 40, { wall = true })            -- mask locker by the right exit
prop("air", "amber_beacon", 952, 1652, 68, { wall = true })           -- strobe lights
prop("air", "amber_beacon", 1146, 1644, 56, { wall = true })
-- Power
prop("power", "breaker", 78, 262, 92, { solid = true })               -- breaker cabinets
prop("power", "breaker", 178, 262, 92, { solid = true })
prop("power", "breaker", 520, 262, 92, { solid = true })
prop("power", "eng_desk", 92, 494, 132, { solid = true })             -- engineer's desk
prop("power", "battery_rack", 530, 494, 110, { solid = true })        -- backup battery tower
prop("power", "hv_sign", 410, 236, 40, { wall = true })               -- HIGH VOLTAGE
-- Batteries
prop("batteries", "breaker", 500, 1772, 80, { solid = true })
prop("batteries", "battery_rack", 470, 2012, 100, { solid = true })
prop("batteries", "battery_rack", 360, 2012, 100, { solid = true })
prop("batteries", "hv_sign", 440, 1690, 40, { wall = true })
-- Radiation / command centre
prop("comms", "chute", 2088, 980, 70, { solid = true })               -- regolith transfer chute
prop("comms", "workstation", 2334, 1064, 92, { solid = true })        -- command console
prop("comms", "vault_door", 2336, 1236, 74, { solid = true })         -- shielded bulkhead door
prop("comms", "geiger", 2340, 984, 44, { wall = true })               -- Geiger counter
prop("comms", "siren", 1928, 836, 40, { wall = true })                -- red alert beacons
Layout.PROPS = P

-- Floor area a solid prop blocks (its front part, so Vulcan can pass "behind"
-- the top of tall furniture without walking through it).
function Layout.footprint(p, depth)
  local d = math.min(p.h, depth or 46)
  return { x = p.x + 6, y = p.y + p.h - d, w = p.w - 12, h = d }
end

return Layout
