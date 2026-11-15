-- Audio decisions (plain Lua): music state, floor surfaces, machine emitters
-- and the sound events the room queues. Playback itself needs Love2D.
-- Run from the repository root:  lua tests/test_audio.lua

package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq = T.test, T.eq
local Audio = require("src.audio")
local Room = require("src.room_scene")
local Map = require("src.station_map")

local function emitter(id) for _, e in ipairs(Audio.EMITTERS) do if e.id == id then return e end end end

test("music: ambient when healthy, tension on warnings, crisis on storms and criticals", function()
  local ls = T.still(); ls.dust:enterCabin(); ls:_afterAction()
  eq(Audio.musicState(ls), "ambient")
  ls.battery = 65; ls:_afterAction(); eq(Audio.musicState(ls), "tension", "power < 70%")
  ls.battery = 90; T.setAir(ls, 19.0, 0.04)
  assert(ls.air.airQuality < 50 or ls.air.airStatus ~= "good")
  eq(Audio.musicState(ls), "tension", "air quality")
  T.setAir(ls, 21, 0.04); ls.sealedWaste = 50; eq(Audio.musicState(ls), "tension", "waste 50%")
  ls.sealedWaste = 0; ls:triggerRadiationWarning(); eq(Audio.musicState(ls), "crisis", "storm countdown")
  local ls2 = T.still(); ls2.dust:enterCabin(); T.setAir(ls2, 17, 0.04)
  eq(Audio.musicState(ls2), "crisis", "O2 critical")
end)

test("footstep surfaces: metal deck, rubber mats, lunar regolith", function()
  eq(Audio.surfaceAt(Map.START_X, Map.START_Y), "regolith")
  eq(Audio.surfaceAt(-600, 1200), "regolith")
  eq(Audio.surfaceAt(300, 400), "rubber")     -- power room
  eq(Audio.surfaceAt(300, 1850), "rubber")    -- battery bank
  eq(Audio.surfaceAt(1240, 400), "metal")     -- water bay
  eq(Audio.surfaceAt(735, 900), "metal")      -- corridor
end)

test("machine loops: louder close by, silent outside / locked / far away", function()
  local r = Room.new({ isDown = function() return false end })
  local air = emitter("air")
  local x, y = air.at()
  r.vulcan.x, r.vulcan.y, r.outside = x, y, false
  local close = Audio.emitterGain(air, r.ls, r)
  r.vulcan.x, r.vulcan.y = x + 400, y
  local mid = Audio.emitterGain(air, r.ls, r)
  r.vulcan.x, r.vulcan.y = x + 2000, y
  eq(Audio.emitterGain(air, r.ls, r), 0)
  assert(close > mid and mid > 0, "volume should fall with distance")
  r.outside = true; eq(Audio.emitterGain(air, r.ls, r), 0)
  local c = Room.new({ isDown = function() return false end, campaign = true })
  c.vulcan.x, c.vulcan.y = x, y
  eq(Audio.emitterGain(air, c.ls, c), 0, "locked room is quiet")
end)

test("broken variants and the storm siren follow the systems", function()
  local ls = T.still(); ls.dust:enterCabin(); ls:_afterAction()
  eq(emitter("air").broken(ls), false)
  T.setAir(ls, 17, 0.04); eq(emitter("air").broken(ls), true)
  eq(emitter("siren").volume(ls), 0)
  ls:triggerRadiationWarning(); assert(emitter("siren").volume(ls) > 0)
end)

test("the room queues UI sounds; audio without Love2D is a safe no-op", function()
  local r = Room.new({ isDown = function() return false end })
  local m = r:machineById("oxygen")
  r.vulcan.x, r.vulcan.y = r:spotNear(m); r:clickStation(m)
  eq(r.sounds[#r.sounds], "sfx_ok")
  r.vulcan.x, r.vulcan.y = Map.START_X, Map.START_Y; r:clickStation(m)
  eq(r.sounds[#r.sounds], "sfx_error")
  local a = Audio.new()
  eq(a.enabled, false)
  a:update(0.1, r); eq(#r.sounds, 0)
end)

T.finish()
