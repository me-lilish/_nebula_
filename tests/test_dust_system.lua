-- Plain-Lua tests for the Dust System (no Love2D needed).
-- Run from the repository root:  lua tests/test_dust_system.lua

package.path = "./?.lua;" .. package.path
local DustSystem = require("src.dust_system")
local AirSystem = require("src.air_system")
local C = require("src.dust_config")

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. name .. "\n   " .. tostring(err)) end
end
local function eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end
local function near(actual, expected, msg)
  if math.abs(actual - expected) > 1e-6 then
    error((msg or "") .. " expected ~" .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end
local function set(d, suit, cabin)
  d.suitDust, d.cabinDust = suit, cabin
  d:_refresh()
end
-- Simple stand-in for a shared power source.
local function fakePower(amount)
  return { left = amount, trySpend = function(self, n)
    if self.left < n then return false end
    self.left = self.left - n
    return true
  end }
end

------------------------------------------------------------------------------
-- Start, clamping, cleanliness
------------------------------------------------------------------------------
test("starts clean at 0 / 0 with cleanliness 100", function()
  local d = DustSystem.new()
  eq(d.suitDust, 0); eq(d.cabinDust, 0); eq(d.dustCleanliness, 100); eq(d.dustStatus, "clean")
end)
test("values clamp to 0..100", function()
  local d = DustSystem.new()
  set(d, 150, 250); eq(d.suitDust, 100); eq(d.cabinDust, 100)
  set(d, -20, -5); eq(d.suitDust, 0); eq(d.cabinDust, 0)
  d:addSuitDust(500); eq(d.suitDust, 100)
end)
test("cleanliness is always 100 - cabinDust", function()
  local d = DustSystem.new()
  for _, cab in ipairs({ 0, 12.5, 30, 61, 99, 100 }) do
    set(d, 40, cab); eq(d.dustCleanliness, 100 - cab)
  end
end)
test("suit dust never lowers cabin cleanliness by itself", function()
  local d = DustSystem.new()
  d:addSuitDust(90)
  eq(d.cabinDust, 0); eq(d.dustCleanliness, 100); eq(d.suitDust, 90)
end)
test("addCabinDust raises cabin dust only (explicit dust event / debug action)", function()
  local d = DustSystem.new()
  d:addCabinDust(12)
  eq(d.cabinDust, 12); eq(d.suitDust, 0); eq(d.dustCleanliness, 88)
  d:addCabinDust(500); eq(d.cabinDust, 100); eq(d:isCritical(), true)
end)

------------------------------------------------------------------------------
-- Status thresholds
------------------------------------------------------------------------------
local suitCases = { { 0, "clean" }, { 29.9, "clean" }, { 30, "caution" }, { 59, "caution" },
  { 59.9, "caution" }, { 60, "danger" }, { 100, "danger" } }
for _, cs in ipairs(suitCases) do
  test("suitDust " .. cs[1] .. " is " .. cs[2], function()
    eq(DustSystem.classifySuit(cs[1]), cs[2])
  end)
end
local cabinCases = { { 100, "clean" }, { 70.1, "clean" }, { 70, "caution" }, { 41, "caution" },
  { 40.1, "caution" }, { 40, "danger" }, { 39, "danger" }, { 1, "danger" }, { 0.5, "danger" },
  { 0, "critical" } }
for _, cs in ipairs(cabinCases) do
  test("cleanliness " .. cs[1] .. " is " .. cs[2], function()
    eq(DustSystem.classifyCabin(cs[1]), cs[2])
  end)
end
test("overall status is the worse of suit and cabin", function()
  eq(DustSystem.classify(0, 0), "clean")
  eq(DustSystem.classify(29, 29), "clean")       -- cleanliness 71
  eq(DustSystem.classify(30, 0), "caution")
  eq(DustSystem.classify(0, 30), "caution")      -- cleanliness 70
  eq(DustSystem.classify(60, 30), "danger")
  eq(DustSystem.classify(10, 60), "danger")      -- cleanliness 40
  eq(DustSystem.classify(80, 100), "critical")
end)
test("suit dust alone is never critical", function()
  local d = DustSystem.new(); d:addSuitDust(100)
  eq(d.dustStatus, "danger")
end)

------------------------------------------------------------------------------
-- Entering the cabin (one-time)
------------------------------------------------------------------------------
test("MVP values: EVA suit dust 60, one clean/filter cycle empties", function()
  eq(C.EVA_SUIT_DUST, 60)
  if C.SUIT_CLEAN_AMOUNT < C.MAX then error("one suit clean must empty the suit") end
  if C.FILTER_CLEAN_AMOUNT < C.MAX then error("one filter cycle must empty the cabin") end
end)
test("clean entry leaves the cabin clean", function()
  local d = DustSystem.new()
  eq(d:enterCabin(), "clean"); eq(d.cabinDust, 0); eq(d.hasEnteredCabin, true)
end)
test("dirty entry adds exactly suitDust to the cabin, suit keeps its dust", function()
  local d = DustSystem.new(); d:addSuitDust(60)
  eq(d:enterCabin(), "dirty")
  eq(d.cabinDust, 60); eq(d.dustCleanliness, 40); eq(d.suitDust, 60)
end)
test("only the first entry counts", function()
  local d = DustSystem.new(); d:addSuitDust(60)
  d:enterCabin()
  for _ = 1, 5 do eq(d:enterCabin(), nil) end
  eq(d.cabinDust, 60)
end)
test("a clean first entry stays clean even if the suit gets dusty later", function()
  local d = DustSystem.new()
  d:enterCabin(); d:addSuitDust(80)
  eq(d:enterCabin(), nil); eq(d.cabinDust, 0)
end)
test("dirty entry clamps the cabin at 100", function()
  local d = DustSystem.new(); set(d, 70, 50)
  d:enterCabin()
  eq(d.cabinDust, 100); eq(d.dustStatus, "critical")
end)
test("cabin 30 -> cleanliness 70 caution; 60 -> 40 danger warning", function()
  local d = DustSystem.new()
  set(d, 0, 30)
  local fb = d:getFeedback()
  eq(fb.cleanliness, 70); eq(fb.cabinStatus, "caution")
  assert(fb.cabinMessage:find("Cabin Cleanliness"), fb.cabinMessage)
  set(d, 0, 60)
  fb = d:getFeedback()
  eq(fb.cleanliness, 40); eq(fb.cabinStatus, "danger")
  assert(fb.cabinMessage:find("cough") and fb.cabinMessage:find("machines"), fb.cabinMessage)
end)

------------------------------------------------------------------------------
-- cleanSuit (Dust-Off Station)
------------------------------------------------------------------------------
test("one cleanSuit cycle takes suit dust to 0 and leaves the cabin alone", function()
  local d = DustSystem.new(); set(d, 60, 35)
  local ok = d:cleanSuit()
  eq(ok, true)
  eq(d.suitDust, 0); eq(d.cabinDust, 35, "cabin untouched")
end)
test("cleanSuit clamps at 0 and refuses when already clean", function()
  local d = DustSystem.new(); set(d, 10, 0)
  assert(d:cleanSuit()); eq(d.suitDust, 0)
  local ok, reason = d:cleanSuit()
  eq(ok, false); eq(reason, "already_clean")
end)
test("cleanSuit lowers status from danger to clean", function()
  local d = DustSystem.new(); set(d, 60, 0)
  eq(d.dustStatus, "danger")
  d:cleanSuit()
  eq(d.dustStatus, "clean")
end)

------------------------------------------------------------------------------
-- runCabinDustFilter
------------------------------------------------------------------------------
test("one filter cycle takes cabin dust to 0, suit untouched", function()
  local d = DustSystem.new(); set(d, 50, 60)
  assert(d:runCabinDustFilter())
  eq(d.cabinDust, 0); eq(d.dustCleanliness, 100); eq(d.suitDust, 50, "suit untouched")
  eq(d.filterUses, C.FILTER_USES - 1)
  eq(d:getFeedback().cabinMessage, "The cabin is clean.")
end)
test("filter clamps at 0 and refuses when already clean", function()
  local d = DustSystem.new(); set(d, 0, 5)
  assert(d:runCabinDustFilter()); eq(d.cabinDust, 0)
  local ok, reason = d:runCabinDustFilter()
  eq(ok, false); eq(reason, "already_clean")
end)
test("filter capacity runs out", function()
  local d = DustSystem.new()
  for _ = 1, C.FILTER_USES do set(d, 0, 100); assert(d:runCabinDustFilter()) end
  local ok, reason = d:runCabinDustFilter()
  eq(ok, false); eq(reason, "filter_full")
end)
test("filter spends power through the shared power source", function()
  local p = fakePower(100)
  local d = DustSystem.new({ power = p }); set(d, 0, 50)
  assert(d:runCabinDustFilter())
  eq(p.left, 100 - C.FILTER_POWER_COST)
end)
test("filter without enough power does nothing and keeps its filter use", function()
  local p = fakePower(C.FILTER_POWER_COST - 1)
  local d = DustSystem.new({ power = p }); set(d, 0, 50)
  local ok, reason = d:runCabinDustFilter()
  eq(ok, false); eq(reason, "no_power")
  eq(d.cabinDust, 50); eq(d.filterUses, C.FILTER_USES); eq(p.left, C.FILTER_POWER_COST - 1)
end)
test("cleanSuit power cost is configurable", function()
  local cfg = {}; for k, v in pairs(C) do cfg[k] = v end
  cfg.SUIT_CLEAN_POWER_COST = 5
  local p = fakePower(4)
  local d = DustSystem.new({ config = cfg, power = p }); d:addSuitDust(50)
  local ok, reason = d:cleanSuit()
  eq(ok, false); eq(reason, "no_power"); eq(d.suitDust, 50)
end)

------------------------------------------------------------------------------
-- No O2/CO2 changes (sharing the air system's power)
------------------------------------------------------------------------------
test("dust actions never change O2 or CO2", function()
  local air = AirSystem.new()
  air.oxygenPercent, air.carbonDioxidePercent = 20.2, 0.6
  air:_refresh()
  local p = fakePower(100)
  local d = DustSystem.new({ power = p })
  d:addSuitDust(90); d:enterCabin(); d:cleanSuit(); d:runCabinDustFilter(); d:addCabinDust(5)
  eq(air.oxygenPercent, 20.2); eq(air.carbonDioxidePercent, 0.6)
  eq(air.airStatus, "caution")
end)

------------------------------------------------------------------------------
-- Critical state (the timer itself lives in the life-support coordinator)
------------------------------------------------------------------------------
test("only a cabin at 100 dust is critical", function()
  local d = DustSystem.new()
  set(d, 100, 99); eq(d:isCritical(), false)
  set(d, 0, 100); eq(d:isCritical(), true)
  assert(d:runCabinDustFilter()); eq(d:isCritical(), false)
end)
test("dust subsystem owns no timer", function()
  local d = DustSystem.new()
  eq(d.criticalTimer, nil); eq(d.missionFailed, nil); eq(d.update, nil)
end)
test("failure message is child-friendly and dust-specific", function()
  assert(DustSystem.FAILURE_MESSAGE:find("too dusty for too long"))
  assert(not DustSystem.FAILURE_MESSAGE:lower():find("air quality"))
end)

------------------------------------------------------------------------------
-- canX checks (used to show machine state) change nothing
------------------------------------------------------------------------------
test("canCleanSuit / canRunCabinDustFilter report reasons without changing state", function()
  local d = DustSystem.new()
  eq(select(2, d:canCleanSuit()), "already_clean")
  eq(select(2, d:canRunCabinDustFilter()), "already_clean")
  set(d, 40, 40)
  eq(d:canCleanSuit(), true); eq(d:canRunCabinDustFilter(), true)
  eq(d.suitDust, 40); eq(d.cabinDust, 40); eq(d.filterUses, C.FILTER_USES)
  d.filterUses = 0
  eq(select(2, d:canRunCabinDustFilter()), "filter_full")
end)
test("canRunCabinDustFilter sees missing power when the source can tell", function()
  local p = { left = 2, canSpend = function(self, n) return self.left >= n end,
    trySpend = function(self, n) if self.left < n then return false end self.left = self.left - n return true end }
  local d = DustSystem.new({ power = p }); set(d, 0, 50)
  local ok, reason = d:canRunCabinDustFilter()
  eq(ok, false); eq(reason, "no_power")
end)

------------------------------------------------------------------------------
-- Reset
------------------------------------------------------------------------------
test("reset restores dust, filter and entry state but not shared power", function()
  local p = fakePower(100)
  local d = DustSystem.new({ power = p }); set(d, 70, 100)
  d:runCabinDustFilter(); d:enterCabin(); set(d, 70, 100)
  d:reset()
  eq(d.suitDust, 0); eq(d.cabinDust, 0); eq(d.dustCleanliness, 100)
  eq(d.dustStatus, "clean"); eq(d.filterUses, C.FILTER_USES)
  eq(d.hasEnteredCabin, false, "entry can count again after reset")
  eq(p.left, 100 - C.FILTER_POWER_COST, "shared power is not reset by dust")
end)

------------------------------------------------------------------------------
-- Feedback
------------------------------------------------------------------------------
test("feedback per status uses Dust / Cabin Cleanliness wording", function()
  local d = DustSystem.new()
  eq(d:getFeedback().color, DustSystem.COLORS.clean)
  set(d, 35, 0)
  local fb = d:getFeedback()
  eq(fb.status, "caution"); eq(fb.action, "clean_suit")
  assert(fb.message:find("Suit Dust%-Off"), fb.message)
  set(d, 65, 0)
  fb = d:getFeedback()
  eq(fb.color, DustSystem.COLORS.danger); eq(fb.action, "clean_suit")
  set(d, 0, 60)
  fb = d:getFeedback()
  eq(fb.action, "filter"); assert(fb.message:find("Trace Air Cleaner"), fb.message)
  set(d, 0, 100)
  fb = d:getFeedback(26)
  eq(fb.color, DustSystem.COLORS.critical); near(fb.timeLeft, 26)
  assert(fb.cabinMessage:find("26 seconds"), fb.cabinMessage)
  for _, cab in ipairs({ 0, 30, 60, 100 }) do
    for _, suit in ipairs({ 0, 35, 60 }) do
      set(d, suit, cab)
      local f2 = d:getFeedback(10)
      for _, m in ipairs({ f2.message, f2.cabinMessage, f2.suitMessage }) do
        if m:lower():find("air quality") then error("mentions air quality: " .. m) end
      end
    end
  end
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
