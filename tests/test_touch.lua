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

test("touch targets are thumb-sized on the smallest phone and never overlap", function()
  local HUD = require("src.ui.hud")
  local Room = require("src.room_scene")
  -- iPhone SE landscape in Safari: 568 x 320 points -> the game at 0.44
  local scale = math.min(568 / 1280, 320 / 720)
  local targets = {
    { "pause", HUD.PAUSE.x, HUD.PAUSE.y, HUD.PAUSE.hit },
    { "speaker", Room.SPEAKER.x, Room.SPEAKER.y, Room.SPEAKER.hit },
  }
  for _, b in ipairs(Touch.BUTTONS) do targets[#targets + 1] = { b.id, b.x, b.y, b.hit or b.r } end
  for _, t in ipairs(targets) do
    local pts = 2 * t[4] * scale
    -- the speaker sits in the top bar, so it gets a little less
    assert(pts >= (t[1] == "speaker" and 31 or 40), t[1] .. " is only " .. pts .. " points wide")
    -- at least the middle of the touch area is on screen (a bit past an edge is harmless)
    local h = t[4] / 2
    assert(t[2] - h >= 0 and t[3] - h >= 0 and t[2] + h <= 1280 and t[3] + h <= 720, t[1] .. " off screen")
  end
  for i = 1, #targets do
    for j = i + 1, #targets do
      local a, b = targets[i], targets[j]
      local d = math.sqrt((a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
      assert(d >= a[4] + b[4], a[1] .. " and " .. b[1] .. " touch areas overlap")
    end
  end
  -- the thumb-stick area (left half, lower part) stays clear of the buttons
  for _, b in ipairs(Touch.BUTTONS) do assert(b.x - (b.hit or b.r) > 560, b.id .. " reaches into the stick area") end
  -- the mini-game X is big enough too
  assert(2 * Touch.CLOSE.hit * scale >= 40, "X button")
  -- presses land on the touch area, not just the drawn circle
  local t = Touch.new()
  local tab = Touch.BUTTONS[3]
  eq(t:press(5, tab.x + tab.hit - 1, tab.y), "tab")
  eq(HUD.hitPause(HUD.PAUSE.x - HUD.PAUSE.hit + 1, HUD.PAUSE.y), true)
end)

T.finish()
