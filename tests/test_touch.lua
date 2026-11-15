-- Touch controls (plain Lua): thumb-stick directions, run, buttons, taps.
-- Run from the repository root:  lua tests/test_touch.lua
package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq = T.test, T.eq
local Touch = require("src.ui.touch")

test("the thumb-stick walks in 8 directions and runs when pushed all the way", function()
  local t = Touch.new()
  eq(t:press(1, 150, 560), "stick")
  t:move(1, 150 + 40, 560); eq(t:isDown("right"), true); eq(t:isDown("left"), false); eq(t:isDown("lshift"), false)
  t:move(1, 150 - 60, 560 - 60); eq(t:isDown("left"), true); eq(t:isDown("up"), true)
  t:move(1, 150, 560 + 500); eq(t:isDown("down"), true); eq(t:isDown("lshift"), true, "full push = run")
  t:move(1, 155, 562); eq(t:isDown("right"), false, "small wiggles do nothing")
  t:release(1); eq(t:isDown("down"), false)
end)

test("buttons: USE, RUN (held), TABLET, MENU; taps elsewhere are clicks", function()
  local t = Touch.new()
  for _, b in ipairs(Touch.BUTTONS) do eq(t:press(10, b.x, b.y), b.id); t:release(10) end
  eq(t:press(2, 1046, 640), "run"); eq(t:isDown("lshift"), true); t:release(2); eq(t:isDown("lshift"), false)
  eq(t:press(3, 900, 200), nil, "a tap on the station is a click")
  eq(t.enabled, true)
end)

test("two fingers: walk with one, press RUN with the other", function()
  local t = Touch.new()
  t:press(1, 150, 560); t:move(1, 250, 560)
  t:press(2, 1046, 640)
  eq(t:isDown("right"), true); eq(t:isDown("lshift"), true)
  eq(t:press(3, 200, 500), nil, "only one stick at a time")
end)

T.finish()
