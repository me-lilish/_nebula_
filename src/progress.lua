--[[
  Saved mission progress (kept between games, see src/store.lua)
  ==============================================================
    level : the level to continue from (a checkpoint: each new level that
            unlocks is saved straight away, so closing the game, a crash or a
            dead phone battery never loses more than the level being played)
    best  : best star rating on MISSION COMPLETE (1 - 3), 0 = not finished
    wins  : how many times the whole mission was completed

  Pure Lua (Store does the file / browser work).
]]
local Store = require("src.store")

local Progress = { NAME = "progress", MAX_LEVEL = 8 }
Progress.level, Progress.best, Progress.wins = 1, 0, 0

local function int(v, lo, hi, default)
  v = tonumber(v)
  if not v or v ~= v or v ~= math.floor(v) or v < lo or v > hi then return default end
  return v
end

-- text -> { level, best, wins }; anything broken or missing falls back to a new game
function Progress.parse(text)
  local p = { level = 1, best = 0, wins = 0 }
  for k, v in (text or ""):gmatch("(%w+)=([^\n]*)") do
    if k == "level" then p.level = int(v, 1, Progress.MAX_LEVEL, 1)
    elseif k == "best" then p.best = int(v, 0, 3, 0)
    elseif k == "wins" then p.wins = int(v, 0, 1e9, 0) end
  end
  return p
end

function Progress.serialize(p)
  return string.format("level=%d\nbest=%d\nwins=%d\n", p.level, p.best, p.wins)
end

function Progress.load()
  local p = Progress.parse(Store.read(Progress.NAME))
  Progress.level, Progress.best, Progress.wins = p.level, p.best, p.wins
  return Progress
end

function Progress.save()
  return Store.write(Progress.NAME, Progress.serialize(Progress))
end

-- a new level unlocked: continue from here next time
function Progress.reachLevel(level)
  level = int(level, 1, Progress.MAX_LEVEL, nil)
  if not level or level == Progress.level then return end
  Progress.level = level
  Progress.save()
end

-- the whole mission is done: keep the best stars, next game starts at Level 1
function Progress.finish(stars)
  Progress.best = math.max(Progress.best, int(stars, 1, 3, 1))
  Progress.wins = Progress.wins + 1
  Progress.level = 1
  Progress.save()
end

-- "Start over" in the pause menu (stars and wins are kept)
function Progress.startOver()
  Progress.level = 1
  Progress.save()
end

function Progress.hasSave() return Progress.level > 1 end

return Progress
