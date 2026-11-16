-- Main menu sky (plain Lua): stars never sit on text, buttons or planets.
-- Run from the repository root:  lua tests/test_menu.lua
package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq = T.test, T.eq
local Menu = require("src.menu_scene")

test("stars stay clear of the title, buttons, footer, Earth and Moon", function()
  local stars = Menu.placeStars(42, 64)
  for _, s in ipairs(stars) do
    if not Menu.starAllowed(s.x, s.y, s.s / 2 + 4) then
      error(string.format("star at %d,%d (size %d) overlaps the menu", s.x, s.y, s.s))
    end
  end
end)

test("stars are evenly spread (none bunched together) and fill the sky", function()
  local stars = Menu.placeStars(42, 64)
  assert(#stars >= 40, "too few stars: " .. #stars)
  for i = 1, #stars do
    for j = i + 1, #stars do
      local d = math.sqrt((stars[i].x - stars[j].x) ^ 2 + (stars[i].y - stars[j].y) ^ 2)
      if d < Menu.STAR_SPACING then error(string.format("stars %d and %d only %.0f px apart", i, j, d)) end
    end
  end
end)

test("the sky is the same every time the menu opens", function()
  local a, b = Menu.placeStars(42, 64), Menu.placeStars(42, 64)
  eq(#a, #b)
  for i = 1, #a do eq(a[i].x, b[i].x); eq(a[i].y, b[i].y) end
end)

test("the keep-out zones cover every menu control", function()
  local m = setmetatable({ toggles = {
    { x = 296, y = 640, w = 330, h = 44 }, { x = 654, y = 640, w = 330, h = 44 } } }, Menu)
  for _, b in ipairs(m.toggles) do
    for _, p in ipairs({ { b.x, b.y }, { b.x + b.w, b.y + b.h }, { b.x + b.w / 2, b.y + b.h / 2 } }) do
      eq(Menu.starAllowed(p[1], p[2], 0), false, "toggle corner must be star-free")
    end
  end
  eq(Menu.starAllowed(640, 470, 0), false, "Start button")
  eq(Menu.starAllowed(640, 280, 0), false, "subtitle")
  eq(Menu.starAllowed(30, 420, 0), false, "Earth")
  eq(Menu.starAllowed(1200, 640, 0), false, "Moon")
  eq(Menu.starAllowed(150, 120, 0), true, "open sky")
end)

T.finish()
