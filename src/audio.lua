--[[
  Audio manager
  =============
  Three channels, each with its own volume:
    music   : 3 looping layers that cross-fade with the mission state
                ambient  - normal operation
                tension  - power < 70 %, air quality < 50 %, waste >= 50 %,
                           or any system in danger
                crisis   - radiation warning / storm, or anything critical
    ambient : machine loops placed in the world (air, water, power, hopper,
              storm siren); louder near the machine, "broken" variants when
              that system is failing
    sfx     : footsteps (metal deck / rubber mats / lunar regolith) and UI
              blips (success, problem, level unlocked, airlock door)

  Sounds are loaded by NAME from assets/audio/<name>.ogg or .wav, so real or
  AI-generated recordings can replace the synthesised ones (tools/build_audio.py)
  without code changes.

  The decision functions (musicState, surfaceAt, emitters) are pure and are
  tested in plain Lua; playback is skipped when love.audio is missing.
]]
local Map = require("src.station_map")

local Audio = {}
Audio.__index = Audio

Audio.VOLUME = { music = 0.5, ambient = 0.55, sfx = 0.8 }
Audio.FADE_SECONDS = 0.6         -- music cross-fade time
Audio.STEP_DISTANCE = 48         -- world px walked per footstep
Audio.HEAR_RADIUS = 650          -- machines are silent beyond this distance
Audio.MUSIC = { ambient = "music_ambient", tension = "music_tension", crisis = "music_crisis" }

------------------------------------------------------------------------------
-- Pure decisions
------------------------------------------------------------------------------

local function isBad(status) return status == "danger" or status == "critical" end

-- "ambient" | "tension" | "crisis"
function Audio.musicState(ls)
  if ls.missionFailed then return "ambient" end
  if ls.radiation.phase ~= "clear" or ls:isAnyCritical() then return "crisis" end
  if ls.battery < 70 or ls.air.airQuality < 50 or ls.sealedWaste >= 50 or ls.urine >= 50
      or isBad(ls.air.airStatus) or isBad(ls.waterStatus) or isBad(ls.powerStatus)
      or isBad(ls.dust.cabinStatus) or isBad(ls.human.healthStatus) then
    return "tension"
  end
  return "ambient"
end

-- Floor under Vulcan: "regolith" outside, "rubber" in the power rooms, else "metal"
function Audio.surfaceAt(x, y)
  if Map.isOutside(x, y) then return "regolith" end
  local r = Map.roomAt(x, y)
  if r and (r.id == "power" or r.id == "batteries") then return "rubber" end
  return "metal"
end

local function centre(id)
  local r = Map.roomById(id)
  return r.x + r.w / 2, r.y + r.h / 2
end

-- World sound emitters. volume(ls, room) -> 0..1 base loudness; broken(ls)
-- -> true to play the failing variant.
Audio.EMITTERS = {
  { id = "air", room = "air", sound = "loop_air", brokenSound = "loop_air_broken",
    at = function() return centre("air") end,
    volume = function() return 0.8 end,
    broken = function(ls) return isBad(ls.air.airStatus) or ls.battery <= 0 end },
  { id = "water", room = "water", sound = "loop_water", brokenSound = "loop_water_broken",
    at = function() return centre("water") end,
    volume = function() return 0.7 end,
    broken = function(ls) return isBad(ls.waterStatus) or ls.battery <= 0 end },
  { id = "power", room = "power", sound = "loop_power",
    at = function() return centre("power") end,
    volume = function() return 0.8 end },
  { id = "batteries", room = "batteries", sound = "loop_power",
    at = function() return centre("batteries") end,
    volume = function(ls) return 0.4 + 0.5 * ls.battery / 100 end },
  { id = "hopper", room = "comms", sound = "loop_hopper",
    at = function() return centre("comms") end,
    volume = function(ls, room)
      local m = room and room:machineById("regolith")
      return m and math.min(1, m.act * 2) or 0
    end },
  { id = "siren", room = "comms", sound = "loop_siren", everywhere = 0.18,
    at = function() return centre("comms") end,
    volume = function(ls) return ls.radiation.phase ~= "clear" and 0.6 or 0 end },
}

-- Loudness of one emitter heard by Vulcan (0..1)
function Audio.emitterGain(e, ls, room)
  local base = e.volume(ls, room)
  if base <= 0 then return 0 end
  if room and room.isRoomLocked and room:isRoomLocked(e.room) then return 0 end
  local v = room and room.vulcan
  if not v then return base end
  if room.outside then return base * (e.everywhere or 0) * 0.6 end
  local x, y = e.at()
  local d = math.sqrt((v.x - x) ^ 2 + (v.y - y) ^ 2)
  local near = math.max(0, 1 - d / Audio.HEAR_RADIUS) ^ 1.6
  return base * math.max(near, e.everywhere or 0)
end

------------------------------------------------------------------------------
-- Playback (love.audio)
------------------------------------------------------------------------------

function Audio.new()
  local self = setmetatable({}, Audio)
  self.enabled = love ~= nil and love.audio ~= nil
  self.muted = false
  self.state = "ambient"
  self.music, self.loops, self.sfx = {}, {}, {}
  self.musicGain = { ambient = 0, tension = 0, crisis = 0 }
  self.loopGain = {}
  self.walked = 0
  self.lastX, self.lastY = nil, nil
  if self.enabled then self:_load() end
  return self
end

-- Loads assets/audio/<name>.ogg|.wav from the game folder, or straight from
-- disk when the game runs from somewhere else (like src/assets.lua does).
local function source(name, kind)
  for _, ext in ipairs({ ".ogg", ".wav" }) do
    local path = "assets/audio/" .. name .. ext
    if love.filesystem.getInfo(path) then
      local ok, s = pcall(love.audio.newSource, path, kind)
      if ok then return s end
    end
    local f = io.open(path, "rb")
    if f then
      local bytes = f:read("*a"); f:close()
      local ok, s = pcall(function()
        local data = love.filesystem.newFileData(bytes, name .. ext)
        if kind == "stream" then return love.audio.newSource(love.sound.newDecoder(data), "stream") end
        return love.audio.newSource(love.sound.newSoundData(data), "static")
      end)
      if ok then return s end
    end
  end
  return nil
end

function Audio:_load()
  for state, name in pairs(Audio.MUSIC) do
    local s = source(name, "stream")
    if s then s:setLooping(true); s:setVolume(0); s:play(); self.music[state] = s end
  end
  for _, e in ipairs(Audio.EMITTERS) do
    for _, name in ipairs({ e.sound, e.brokenSound }) do
      if name and not self.loops[e.id .. name] then
        local s = source(name, "static")
        if s then s:setLooping(true); s:setVolume(0); s:play(); self.loops[e.id .. name] = s end
      end
    end
  end
  local names = { "sfx_ok", "sfx_error", "sfx_unlock", "sfx_door" }
  for _, surface in ipairs({ "metal", "rubber", "regolith" }) do
    for i = 1, 3 do names[#names + 1] = "step_" .. surface .. i end
  end
  for _, name in ipairs(names) do self.sfx[name] = source(name, "static") end
end

function Audio:toggleMute()
  self.muted = not self.muted
  return self.muted
end

function Audio:play(name, volume, pitch)
  if not self.enabled or self.muted then return end
  local s = self.sfx[name]
  if not s then return end
  local c = s:clone()
  c:setVolume((volume or 1) * Audio.VOLUME.sfx)
  c:setPitch(pitch or 1)
  c:play()
end

local function approach(current, target, rate)
  if current < target then return math.min(target, current + rate) end
  return math.max(target, current - rate)
end

-- Music only (menu)
function Audio:updateMusic(dt, state)
  self.state = state
  local rate = dt / Audio.FADE_SECONDS
  for st, s in pairs(self.music) do
    self.musicGain[st] = approach(self.musicGain[st], st == state and 1 or 0, rate)
    s:setVolume(self.muted and 0 or self.musicGain[st] * Audio.VOLUME.music)
  end
end

function Audio:silenceWorld(dt)
  for key, s in pairs(self.loops) do
    self.loopGain[key] = approach(self.loopGain[key] or 0, 0, dt * 2)
    s:setVolume(self.loopGain[key] * Audio.VOLUME.ambient)
  end
end

-- In game: music state, machine loops, footsteps, queued UI sounds
function Audio:update(dt, room)
  if not self.enabled then
    if room then room.sounds = {} end
    return
  end
  local ls = room.ls
  self:updateMusic(dt, Audio.musicState(ls))
  -- machine loops
  for _, e in ipairs(Audio.EMITTERS) do
    local gain = Audio.emitterGain(e, ls, room)
    local broken = e.brokenSound and e.broken and e.broken(ls)
    for _, name in ipairs({ e.sound, e.brokenSound }) do
      if name then
        local key = e.id .. name
        local s = self.loops[key]
        if s then
          local want = ((name == e.brokenSound) == (broken and true or false)) and gain or 0
          self.loopGain[key] = approach(self.loopGain[key] or 0, want, dt * 2)
          s:setVolume(self.muted and 0 or self.loopGain[key] * Audio.VOLUME.ambient)
        end
      end
    end
  end
  -- footsteps
  local v = room.vulcan
  if self.lastX and v.moving then
    self.walked = self.walked + math.sqrt((v.x - self.lastX) ^ 2 + (v.y - self.lastY) ^ 2)
    if self.walked >= Audio.STEP_DISTANCE then
      self.walked = 0
      local surface = Audio.surfaceAt(v.x, v.y)
      local vol = surface == "rubber" and 0.75 or (surface == "regolith" and 0.8 or 0.55)
      self:play("step_" .. surface .. love.math.random(1, 3), vol, 0.92 + love.math.random() * 0.16)
    end
  elseif not v.moving then
    self.walked = Audio.STEP_DISTANCE * 0.6 -- first step comes quickly
  end
  self.lastX, self.lastY = v.x, v.y
  -- UI / event sounds queued by the room
  for _, name in ipairs(room.sounds or {}) do self:play(name) end
  room.sounds = {}
end

return Audio
