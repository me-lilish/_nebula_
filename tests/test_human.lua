-- Unit tests for the human-needs subsystem (src/human_system.lua).
-- Run from the repository root:  lua tests/test_human.lua

package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq, near = T.test, T.eq, T.near
local HC = T.HumanC
local HumanSystem = require("src.human_system")

local function run(h, seconds, loss)
  for _ = 1, math.floor(seconds / 0.1 + 0.5) do h:update(0.1, loss or 0) end
end

test("health starts at 100 and statuses follow thresholds", function()
  local h = HumanSystem.new()
  eq(h.health, 100); eq(h.healthStatus, "good")
  for _, case in ipairs({ { 70, "good" }, { 69.9, "caution" }, { 40, "caution" }, { 39.9, "danger" },
      { 0.1, "danger" }, { 0, "critical" } }) do
    h.health = case[1]; h:_refresh(); eq(h.healthStatus, case[2], "health " .. case[1])
  end
  h.health = 0; h:_refresh(); eq(h:isCritical(), true)
end)
test("hunger: ok -> warning at exactly 10 min -> danger at exactly 15 min", function()
  local h = HumanSystem.new()
  run(h, HC.HUNGER_WARNING_SEC - 0.1); eq(h:hungerStatus(), "ok")
  run(h, 0.1); eq(h:hungerStatus(), "warning")
  run(h, HC.HUNGER_DANGER_SEC - HC.HUNGER_WARNING_SEC - 0.1); eq(h:hungerStatus(), "warning")
  run(h, 0.1); eq(h:hungerStatus(), "danger")
  h:eat(); eq(h:hungerStatus(), "ok"); eq(h.timeSinceFood, 0)
end)
test("bathroom: need at 9 min, danger at 14 min, toilet resets", function()
  local h = HumanSystem.new()
  run(h, HC.BATHROOM_NEED_SEC - 0.1); eq(h:bathroomStatus(), "ok")
  run(h, 0.1); eq(h:bathroomStatus(), "need")
  run(h, HC.BATHROOM_DANGER_SEC - HC.BATHROOM_NEED_SEC); eq(h:bathroomStatus(), "danger")
  h:addToBladder(4)
  eq(h:useToilet(), 4); eq(h.bladder, 0); eq(h:bathroomStatus(), "ok")
end)
test("health loss is gradual, never instant", function()
  local h = HumanSystem.new(); h.timeSinceFood = HC.HUNGER_DANGER_SEC
  run(h, 1)
  near(h.health, 100 - HC.HUNGER_HEALTH_LOSS_PER_SEC, 1e-6)
  if h.health < 99 then error("too fast") end
end)
test("losses add up: hunger + bathroom + outside causes", function()
  local h = HumanSystem.new(); h.timeSinceFood = HC.HUNGER_DANGER_SEC; h.timeSinceToilet = HC.BATHROOM_DANGER_SEC
  run(h, 10, 0.1)
  near(h.health, 100 - 10 * (HC.HUNGER_HEALTH_LOSS_PER_SEC + HC.BATHROOM_HEALTH_LOSS_PER_SEC + 0.1))
end)
test("health recovers slowly when nothing is wrong, up to 100", function()
  local h = HumanSystem.new(); h.health = 50
  run(h, 10); near(h.health, 50 + 10 * HC.HEALTH_REGEN_PER_SEC)
  h.health = 99.99; run(h, 10); eq(h.health, 100)
end)
test("health never goes below 0", function()
  local h = HumanSystem.new(); h.health = 0.1
  run(h, 10, 5); eq(h.health, 0); eq(h.healthStatus, "critical")
end)
test("sleep counts only while sleeping", function()
  local h = HumanSystem.new()
  run(h, 10); eq(h:sleepInLastDay(), 0)
  h:startSleep(); run(h, 20); near(h:sleepInLastDay(), 20)
  h:wake(); run(h, 10); near(h:sleepInLastDay(), 20)
end)
test("no fatigue judgement during the first game day", function()
  local h = HumanSystem.new()
  run(h, HC.SLEEP_WINDOW_SEC - 1); eq(h:isFatigued(), false)
end)
test("less than 6 minutes of sleep in a game day -> fatigue + gradual loss", function()
  local h = HumanSystem.new(); local short = HC.SLEEP_MIN_SEC - 6
  h:startSleep(); run(h, short); h:wake()
  run(h, HC.SLEEP_WINDOW_SEC - short)
  eq(h:isFatigued(), true)
  local before = h.health
  h.timeSinceFood, h.timeSinceToilet = 0, 0
  run(h, 10)
  near(h.health, before - 10 * HC.FATIGUE_HEALTH_LOSS_PER_SEC, 1e-6)
end)
test("6+ minutes of sleep in the last game day -> not fatigued", function()
  local h = HumanSystem.new()
  run(h, 10); h:startSleep(); run(h, HC.SLEEP_MIN_SEC + 6); h:wake(); run(h, HC.SLEEP_WINDOW_SEC - 10 - HC.SLEEP_MIN_SEC - 6)
  eq(h:isFatigued(), false)
end)
test("sleep across midnight still counts as one night (rolling day)", function()
  local h = HumanSystem.new()
  run(h, 14 * 6)                               -- 06:00 -> 20:00
  h:startSleep(); run(h, 8 * 6); h:wake()      -- 20:00 -> 04:00 next day
  run(h, 2 * 6)
  eq(h:isFatigued(), false); near(h:sleepInLastDay(), 8 * 6, 0.2)
end)
test("old sleep drops out of the window after a day", function()
  local h = HumanSystem.new()
  h:startSleep(); run(h, 8 * 6); h:wake()
  run(h, HC.SLEEP_WINDOW_SEC + 6)
  near(h:sleepInLastDay(), 0, 0.2); eq(h:isFatigued(), true)
end)
test("reset restores every need", function()
  local h = HumanSystem.new(); h.health = 10; h:startSleep(); h:addToBladder(5); run(h, 100)
  h:reset()
  eq(h.health, 100); eq(h.isSleeping, false); eq(h.bladder, 0); eq(h.timeSinceFood, 0); eq(h:sleepInLastDay(), 0)
end)

T.finish()
