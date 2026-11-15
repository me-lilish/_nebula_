-- Tests for the mission guide ("what should I do next?").
-- Run from the repository root:  lua tests/test_guide.lua

package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq = T.test, T.eq
local Guide = require("src.guide")
local Room = require("src.room_scene")

local function still() return T.still() end

test("first: clean the suit, then walk in", function()
  local ls = still(); ls.dust:addSuitDust(60)
  eq(Guide.next(ls).station, "dustoff")
  ls:useSuitDustOff()
  eq(Guide.next(ls).station, "entrance")
  ls:enterCabin()
  eq(Guide.next(ls).station, nil, "nothing to do in a healthy station")
end)
test("every station the guide can name exists in the room", function()
  local room = Room.new({ isDown = function() return false end })
  local names = { "dustoff", "oxygen", "co2", "recycler", "water", "toilet", "solar", "battery",
    "shield", "regolith", "foodstation", "sleep", "trace", "greenhouse", "foodstorage", "compost" }
  for _, id in ipairs(names) do
    if not room:machineById(id) then error("guide names a missing station: " .. id) end
  end
end)
test("critical problems beat tips", function()
  local ls = still(); ls.dust:enterCabin(); ls.growth = 100
  eq(Guide.next(ls).station, "greenhouse")
  T.setAir(ls, 17, 0.04)
  local g = Guide.next(ls)
  eq(g.station, "oxygen"); eq(g.level, "critical")
end)
test("high CO2 -> CO2 Cleaner, or the Recycler when storage is full", function()
  local ls = still(); ls.dust:enterCabin(); T.setAir(ls, 21, 0.9)
  eq(Guide.next(ls).station, "co2")
  ls.capturedCO2 = ls.config.CAPTURED_CO2_MAX
  eq(Guide.next(ls).station, "recycler")
end)
test("too much oxygen needs no machine", function()
  local ls = still(); ls.dust:enterCabin(); T.setAir(ls, 24, 0.04)
  eq(Guide.next(ls).station, nil)
end)
test("radiation warning: load regolith, then place shields", function()
  local ls = still(); ls.dust:enterCabin(); ls:triggerRadiationWarning()
  eq(Guide.next(ls).station, "regolith")
  ls:loadRegolith()
  eq(Guide.next(ls).station, "shield")
  ls:deployShields()
  local g = Guide.next(ls)
  if g.station == "shield" and g.level == "danger" then error("crew is shielded already") end
end)
test("low battery -> aim panels by day, Power Saver otherwise", function()
  local ls = still(); ls.dust:enterCabin(); ls.battery = 30; ls.solarAim = 60; ls:_afterAction()
  eq(Guide.next(ls).station, "solar")
  ls.solarAim = 100
  eq(Guide.next(ls).station, "battery")
end)
test("needs: hungry -> Food Station, bathroom -> Toilet, full toilet -> Toilet", function()
  local ls = still(); ls.dust:enterCabin()
  ls.human.timeSinceFood = 700
  eq(Guide.next(ls).station, "foodstation")
  ls.human.timeSinceFood = 0; ls.human.timeSinceToilet = 600
  eq(Guide.next(ls).station, "toilet")
end)
test("dust in the cabin -> Trace Air Cleaner", function()
  local ls = still(); ls.dust:enterCabin(); ls.dust:addCabinDust(60); ls:_afterAction()
  eq(Guide.next(ls).station, "trace")
end)
test("water low -> Water Recovery", function()
  local ls = still(); ls.dust:enterCabin(); ls.potableWater = 20; ls:_afterAction()
  eq(Guide.next(ls).station, "water")
end)

T.finish()
