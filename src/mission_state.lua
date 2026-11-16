--[[
  Mission progression: 8 life-support systems, easiest to hardest
  ===============================================================
  Pure logic (no love.*). Each LEVEL unlocks one system's room(s); its tasks
  are done in order, one at a time, so a child always has exactly one clear
  objective. Finishing the last task of a level unlocks the next level.

  Systems the player has not unlocked yet are run by "Mission Control"
  (LifeSupport autopilot) so they stay safe until the child learns them.

    1 Human     Crew Quarters            eat, bathroom, sleep
    2 Dust      Airlock                  go outside, brush suit, walk in, new HEPA filter
    3 Water     Hydro-Plumbing Bay       reconnect pipes, balance tank valves
    4 Food      Pantry & Hydroponics     tune grow lights, harvest, store crops
    5 Waste     Recycling Workshop       compost, recycle broken parts
    6 Air       Atmosphere Hub           oxygen, CO2 cleaner, CO2 recycler
    7 Power     Power Grid + Battery     Power Saver, aim solar panels
    8 Radiation Radiation Command        regolith, shields, survive the storm
]]
local Mission = {}
Mission.__index = Mission

Mission.LEVELS = {
  { id = "human", name = "HUMAN SYSTEM", room = "Crew Quarters", rooms = { "quarters" },
    lesson = "Astronauts need food, the bathroom and sleep - just like on Earth!",
    tasks = {
      { id = "foodstation", station = "foodstation", text = "Eat breakfast at the Food Dispenser." },
      { id = "toilet", station = "toilet", text = "Use the Bathroom Pod." },
      { id = "sleep", station = "sleep", text = "Rest in your bunk bed." },
    } },
  { id = "dust", name = "DUST SYSTEM", room = "Airlock & Decon Bay", rooms = { "airlock" }, exterior = true,
    lesson = "Moon dust is sharp! Brush it off before it gets into the air.",
    tasks = {
      { id = "outside", station = "outside", text = "Go out through the airlock onto the Moon." },
      { id = "dustoff", station = "dustoff", text = "Come back and brush the dust off your suit." },
      { id = "entrance", station = "entrance", text = "Walk in through the inner airlock door." },
      { id = "trace", station = "trace", text = "Swap the clogged HEPA filter in the Dust Filter Unit." },
    } },
  { id = "water", name = "WATER SYSTEM", room = "Hydro-Plumbing Bay", rooms = { "water" },
    lesson = "On the Moon, used water is cleaned and used again and again.",
    tasks = {
      { id = "water", station = "water", text = "Reconnect the pipes at the Water Recycler." },
      { id = "valves", station = "valves", text = "Balance the Tank Valves." },
    } },
  { id = "food", name = "FOOD SYSTEM", room = "Pantry & Hydroponics", rooms = { "food" },
    lesson = "Plants grow without soil under special lights: hydroponics!",
    tasks = {
      { id = "growlight", station = "growlight", text = "Tune the Grow-Light Timer." },
      { id = "greenhouse", station = "greenhouse", text = "Plant and harvest at the Hydroponic Garden." },
      { id = "foodstorage", station = "foodstorage", text = "Put the crops in the Food Cooler." },
    } },
  { id = "waste", name = "WASTE SYSTEM", room = "Recycling Workshop", rooms = { "waste" },
    lesson = "Nothing is thrown away: scraps become fertilizer, broken parts become spares.",
    tasks = {
      { id = "compost", station = "compost", text = "Turn plant scraps into fertilizer." },
      { id = "recycle", station = "recycle", text = "Recycle the broken rover parts." },
    } },
  { id = "air", name = "AIR SYSTEM", room = "Atmosphere Hub", rooms = { "air" },
    lesson = "Oxygen comes from splitting water; CO2 is caught and recycled.",
    tasks = {
      { id = "oxygen", station = "oxygen", text = "Make oxygen from water." },
      { id = "co2", station = "co2", text = "Clean the CO2 out of the air." },
      { id = "recycler", station = "recycler", text = "Recycle the CO2 into water." },
    } },
  { id = "power", name = "POWER SYSTEM", room = "Power Grid & Battery Bank", rooms = { "power", "batteries" },
    lesson = "Solar panels make power by day; batteries keep the lights on at night.",
    tasks = {
      { id = "battery", station = "battery", text = "Switch Power Saver at the Battery Bank." },
      { id = "solar", station = "solar", text = "Aim the solar panels at the Sun." },
    } },
  { id = "radiation", name = "RADIATION SYSTEM", room = "Radiation Command", rooms = { "comms" },
    lesson = "Moon soil (regolith) piled on the habitat blocks solar storm radiation.",
    tasks = {
      { id = "regolith", station = "regolith", text = "A storm is coming! Load regolith." },
      { id = "shield", station = "shield", text = "Place all 9 shields at the holo-table." },
      { id = "survive", station = nil, text = "Stay safe until the solar storm is over." },
    } },
}

-- Systems each level hands over from Mission Control to the player
Mission.SYSTEMS = {
  human = { "human" }, dust = { "dust" }, water = { "water" }, food = { "food" },
  waste = { "waste" }, air = { "air" }, power = { "power" }, radiation = { "radiation" },
}

function Mission.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Mission)
  self.level = 1        -- highest unlocked level
  self.task = 1         -- task index inside that level
  self.completed = {}
  self.done = false
  if opts.unlockAll then self.level, self.task, self.done = #Mission.LEVELS, 1, true end
  return self
end

-- Continue a saved game: jump to the start of `level` with every earlier
-- level finished (out-of-range values are clamped).
function Mission:startAt(level)
  level = math.max(1, math.min(#Mission.LEVELS, math.floor(tonumber(level) or 1)))
  self.level, self.task, self.done, self.early = level, 1, false, {}
  self.completed = {}
  for i = 1, level - 1 do
    for _, t in ipairs(Mission.LEVELS[i].tasks) do self.completed[t.id] = true end
  end
  return self
end

function Mission:currentLevel() return Mission.LEVELS[self.level] end

-- Current objective { id, station, text, level } or nil when everything is done
function Mission:objective()
  if self.done then return nil end
  local lv = self:currentLevel()
  local t = lv.tasks[self.task]
  return t and { id = t.id, station = t.station, text = t.text, level = self.level }
end

-- Tasks that only count at their turn (places to walk to, the storm). Machine
-- tasks done EARLY - before the mission asks for them - still count: without
-- this a quick player who, say, swapped the HEPA filter before walking in got
-- "already clean" later and was stuck on that step forever.
local IN_ORDER_ONLY = { outside = true, entrance = true, shield = true, survive = true }

function Mission:_laterTaskInLevel(id)
  local lv = self:currentLevel()
  for i = self.task + 1, #lv.tasks do
    if lv.tasks[i].id == id then return true end
  end
  return false
end

-- Moves to the next task; returns unlockedLevel, finishedGame
function Mission:_advance()
  local lv = self:currentLevel()
  if self.task < #lv.tasks then
    self.task = self.task + 1
    return nil, false
  end
  if self.level < #Mission.LEVELS then
    self.level, self.task = self.level + 1, 1
    self.early = {}
    return Mission.LEVELS[self.level], false
  end
  self.done = true
  return nil, true
end

-- Completes the current task if `id` matches (and any tasks right after it
-- that were already done early).
-- Returns completed (bool), unlockedLevel (table or nil), finishedGame (bool)
function Mission:complete(id)
  local o = self:objective()
  if not o then return false end
  self.early = self.early or {}
  if o.id ~= id then
    if not IN_ORDER_ONLY[id] and self:_laterTaskInLevel(id) then self.early[id] = true end
    return false
  end
  self.completed[id] = true
  local unlocked, finished = self:_advance()
  -- skip the following tasks of this level that were already done early
  while not unlocked and not finished do
    local nxt = self:objective()
    if not (nxt and self.early[nxt.id]) then break end
    self.completed[nxt.id] = true
    unlocked, finished = self:_advance()
  end
  return true, unlocked, finished
end

function Mission:isComplete() return self.done end

function Mission:levelOf(roomId)
  for i, lv in ipairs(Mission.LEVELS) do
    for _, r in ipairs(lv.rooms) do if r == roomId then return i, lv end end
  end
  return nil
end

function Mission:isRoomUnlocked(roomId)
  local i = self:levelOf(roomId)
  return i == nil or i <= self.level
end

function Mission:isLevelUnlocked(id)
  for i, lv in ipairs(Mission.LEVELS) do if lv.id == id then return i <= self.level end end
  return false
end

function Mission:exteriorUnlocked() return self:isLevelUnlocked("dust") end

-- Systems still run by Mission Control: { air = true, ... }
function Mission:autopilot()
  local a = {}
  for i, lv in ipairs(Mission.LEVELS) do
    if i > self.level then for _, s in ipairs(Mission.SYSTEMS[lv.id]) do a[s] = true end end
  end
  return a
end

return Mission
