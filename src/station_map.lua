--[[
  Station map
  ===========
  Pure data + geometry (no love.* calls). World: 2400 x 2400 units.
  The room/corridor arrangement follows the team's layout idea; the
  architecture is a real station: rooms have hull walls, corridors meet them
  through DOORS (computed below), and the back wall of each room is solid.

  rooms     : named rooms. Floor = room minus a wall band on top (WALL) and
              a hull border (HULL_GAP) on the other sides.
  corridors : walkable corridor rectangles
  doors     : openings where a corridor meets a room (computed)
  outside   : Moon surface outside the airlock door (EVA start)
]]

local Map = {}

Map.WIDTH, Map.HEIGHT = 2400, 2400
Map.WALL = 90        -- back-wall band at the top of every room (solid)
Map.HULL_GAP = 20    -- hull thickness inside a room on its left/right/bottom
Map.DOOR_WIDTH = 116 -- door opening

Map.rooms = {
  { id = "power",     name = "POWER GRID ROOM",   x = 0,    y = 158,  w = 621, h = 357 },
  { id = "water",     name = "HYDRO-PLUMBING BAY",   x = 849,  y = 0,    w = 773, h = 673 },
  { id = "quarters",  name = "CREW QUARTERS",     x = 1881, y = 0,    w = 519, h = 674 },
  { id = "airlock",   name = "AIRLOCK & DECON BAY",     x = 345,  y = 734,  w = 314, h = 664,
    extra = { { x = 157, y = 914, w = 188, h = 267 } } },  -- outside-door wing
  { id = "comms",     name = "RADIATION COMMAND",    x = 1890, y = 782,  w = 510, h = 478 },
  { id = "batteries", name = "BATTERY BANK",      x = 0,    y = 1609, w = 604, h = 425 },
  { id = "food",      name = "PANTRY & HYDROPONICS", x = 1842, y = 1386, w = 558, h = 559 },
  { id = "air",       name = "ATMOSPHERE HUB",     x = 885,  y = 1614, w = 695, h = 351 },
  { id = "waste",     name = "RECYCLING WORKSHOP",      x = 919,  y = 2010, w = 791, h = 387 },
}

Map.corridors = {
  { x = 1622, y = 232,  w = 259, h = 151 },  -- water <-> quarters
  { x = 1660, y = 383,  w = 150, h = 563 },
  { x = 1315, y = 946,  w = 575, h = 150 },  -- to comms
  { x = 1165, y = 673,  w = 150, h = 936 },  -- water <-> air
  { x = 810,  y = 1079, w = 355, h = 150 },
  { x = 660,  y = 412,  w = 150, h = 1339 }, -- spine beside the airlock
  { x = 621,  y = 262,  w = 228, h = 150 },  -- power <-> water
  { x = 604,  y = 1751, w = 276, h = 150 },  -- batteries <-> air
  { x = 1580, y = 1751, w = 262, h = 150 },  -- air <-> food
  { x = 2140, y = 1260, w = 150, h = 126 },  -- comms <-> food
  { x = 2121, y = 674,  w = 150, h = 108 },  -- quarters <-> comms
  { x = 144,  y = 2034, w = 150, h = 316 },
  { x = 144,  y = 2199, w = 775, h = 151 },  -- batteries -> waste
  { x = 2092, y = 1945, w = 150, h = 416 },
  { x = 1710, y = 2211, w = 532, h = 150 },  -- food -> waste
}

-- Outside: the landing pad at the outer airlock door plus the open lunar
-- field west of the habitat (x < 0). Only the pad touches the hull.
Map.outside = { x = -40, y = 800, w = 197, h = 700 }
Map.field = { x = -1300, y = 800, w = 1260, h = 960 }
Map.outsideAreas = { Map.outside, Map.field }
Map.HORIZON_Y = 760                       -- beyond this line: black space
Map.EXTERIOR = { x = -1300, y = 360, w = 3700, h = 1560 } -- camera bounds outside

Map.START_X, Map.START_Y = 70, 1047       -- back from a moonwalk (sandbox)
Map.CREW_START_X, Map.CREW_START_Y = 2050, 520 -- waking up in the crew quarters (campaign)

-- Radiation shield sections -> rooms they protect (for drawing berms)
Map.SECTION_ROOMS = {
  crew = { "quarters" }, air = { "air" }, water = { "water" }, food = { "food" },
  power = { "power", "batteries" }, greenhouse = { "food" }, waste = { "waste" },
  entrance = { "airlock" }, storage = { "comms" },
}

------------------------------------------------------------------------------
-- Geometry helpers
------------------------------------------------------------------------------

local function inRect(px, py, r, pad)
  pad = pad or 0
  return px >= r.x - pad and px <= r.x + r.w + pad and py >= r.y - pad and py <= r.y + r.h + pad
end
Map.inRect = inRect

function Map.roomById(id)
  for _, r in ipairs(Map.rooms) do if r.id == id then return r end end
  return nil
end

-- Walkable floor of a room (inside its hull, below its back wall)
function Map.roomFloor(r)
  local g = Map.HULL_GAP
  return { x = r.x + g, y = r.y + Map.WALL, w = r.w - 2 * g, h = r.h - Map.WALL - g }
end

-- Floor of an extra wing: open towards the main room (on its right)
local function extraFloor(e)
  local g = Map.HULL_GAP
  return { x = e.x + g, y = e.y + g, w = e.w, h = e.h - 2 * g }
end

------------------------------------------------------------------------------
-- Doors: wherever a corridor (or the Moon pad) touches a room edge, one
-- door-sized opening is cut through the hull, centred on the shared span.
------------------------------------------------------------------------------
local function buildDoors()
  local doors = {}
  local half = Map.DOOR_WIDTH / 2
  local TOUCH = 8
  local function add(d) doors[#doors + 1] = d end

  local function connect(c, r, partFloor, part)
    -- c touches part's left / right / top / bottom edge?
    local f = partFloor
    if math.abs(c.x + c.w - part.x) <= TOUCH or math.abs(c.x - (part.x + part.w)) <= TOUCH then
      local y0, y1 = math.max(c.y, f.y), math.min(c.y + c.h, f.y + f.h)
      if y1 - y0 < Map.DOOR_WIDTH then return end
      local cy = (y0 + y1) / 2
      local left = math.abs(c.x + c.w - part.x) <= TOUCH
      local x0 = left and (c.x + c.w - 8) or (f.x + f.w - 8)
      local x1 = left and (f.x + 8) or (c.x + 8)
      add({ x = x0, y = cy - half, w = x1 - x0, h = 2 * half, vertical = true, room = r.id })
    elseif math.abs(c.y + c.h - part.y) <= TOUCH or math.abs(c.y - (part.y + part.h)) <= TOUCH then
      local x0, x1 = math.max(c.x, f.x), math.min(c.x + c.w, f.x + f.w)
      if x1 - x0 < Map.DOOR_WIDTH then return end
      local cx = (x0 + x1) / 2
      local above = math.abs(c.y + c.h - part.y) <= TOUCH
      local y0 = above and (c.y + c.h - 8) or (f.y + f.h - 8)
      local y1 = above and (f.y + 8) or (c.y + 8)
      add({ x = cx - half, y = y0, w = 2 * half, h = y1 - y0, vertical = false, room = r.id, top = above })
    end
  end

  for _, c in ipairs(Map.corridors) do
    for _, r in ipairs(Map.rooms) do connect(c, r, Map.roomFloor(r), r) end
  end
  -- The airlock's outside door (Moon pad -> airlock wing)
  local airlock = Map.roomById("airlock")
  local wing = airlock.extra[1]
  connect(Map.outside, airlock, extraFloor(wing), wing)
  return doors
end

Map.doors = buildDoors()

-- The outer airlock door (Moon pad -> airlock wing)
for _, d in ipairs(Map.doors) do
  if d.room == "airlock" and d.vertical and d.x < 200 then Map.outerDoor = d end
end

-- The habitat entrance: the door from the airlock into the spine corridor
Map.ENTRANCE_X = 660
for _, d in ipairs(Map.doors) do
  if d.room == "airlock" and d.vertical and d.x + d.w > 640 then
    Map.ENTRANCE_Y1, Map.ENTRANCE_Y2 = d.y, d.y + d.h
    Map.entranceDoor = d
  end
end

------------------------------------------------------------------------------
-- Walkability
------------------------------------------------------------------------------

function Map.isOutside(px, py)
  for _, a in ipairs(Map.outsideAreas) do if inRect(px, py, a) then return true end end
  return false
end

function Map.isWalkablePoint(px, py)
  if Map.isOutside(px, py) then return true end
  if px < 0 or py < 0 or px > Map.WIDTH or py > Map.HEIGHT then return false end
  for _, d in ipairs(Map.doors) do if inRect(px, py, d) then return true end end
  for _, r in ipairs(Map.rooms) do
    if inRect(px, py, Map.roomFloor(r)) then return true end
    if r.extra then
      for _, e in ipairs(r.extra) do if inRect(px, py, extraFloor(e)) then return true end end
    end
  end
  for _, c in ipairs(Map.corridors) do if inRect(px, py, c) then return true end end
  return false
end

-- Can a circle of radius r stand here? (centre + 8 points on its edge)
function Map.isWalkable(x, y, r)
  if not Map.isWalkablePoint(x, y) then return false end
  for i = 0, 7 do
    local a = i * math.pi / 4
    if not Map.isWalkablePoint(x + math.cos(a) * r, y + math.sin(a) * r) then return false end
  end
  return true
end

function Map.roomAt(px, py)
  for _, r in ipairs(Map.rooms) do
    if inRect(px, py, r) then return r end
    if r.extra then
      for _, e in ipairs(r.extra) do if inRect(px, py, e) then return r end end
    end
  end
  return nil
end

Map.extraFloor = extraFloor

return Map
