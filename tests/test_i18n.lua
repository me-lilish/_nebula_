-- Languages, Arabic shaping, read-aloud and the pause menu (plain Lua).
-- Run from the repository root:  lua tests/test_i18n.lua
package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq = T.test, T.eq
local I18n = require("src.i18n")
local TTS = require("src.tts")
local PauseMenu = require("src.pause_menu")

local function cps(s) return I18n.decode(s) end

test("Arabic letters join: initial, medial, final and isolated forms", function()
  -- "بيت" (house): beh initial, yeh medial, teh final
  local shaped = I18n.shapeLogical(cps("بيت"))
  eq(shaped[1], 0xFE91); eq(shaped[2], 0xFEF4); eq(shaped[3], 0xFE96)
  -- "دار": dal never joins forward, alef after it stands alone
  shaped = I18n.shapeLogical(cps("دار"))
  -- (letters that stand alone use the plain letter, which fonts draw isolated)
  eq(shaped[1], 0x062F); eq(shaped[2], 0x0627); eq(shaped[3], 0x0631)
  -- lam + alef becomes one ligature
  shaped = I18n.shapeLogical(cps("لا"))
  eq(#shaped, 1); eq(shaped[1], 0xFEFB)
end)

test("right-to-left: Arabic reversed, numbers keep their order", function()
  local v = I18n.visual(cps("ab 12 ج"))
  -- logical: a b space 1 2 space jeem -> runs reversed; "12" stays "12"
  local s = I18n.encode(v)
  assert(s:find("12", 1, true), s)
  local first = I18n.decode(I18n.shape("المستوى 3"))
  eq(first[1], 51, "the number comes first (leftmost) when read right to left")
end)

test("English mode changes nothing", function()
  I18n.setLanguage("en")
  eq(I18n.t("Use the Bathroom Pod."), "Use the Bathroom Pod.")
end)

test("Arabic: exact phrases and sentences with numbers translate", function()
  I18n.setLanguage("ar")
  eq(I18n.t("Use the Bathroom Pod."), "استخدم الحمام.")
  local s = I18n.t("Loaded 9 units of Moon soil (regolith).")
  assert(s:find("9", 1, true) and I18n.hasArabic(s), s)
  -- words captured inside a sentence are translated too
  s = I18n.t("LEVEL 2 UNLOCKED: DUST SYSTEM - Airlock & Decon Bay")
  assert(s:find("نظام الغبار", 1, true) and s:find("غرفة الضغط", 1, true), s)
  eq(I18n.t("DAY 1  06:30"), "اليوم 1  06:30")
  eq(I18n.t("Something new that has no translation"), "Something new that has no translation")
  I18n.setLanguage("en")
end)

test("every level, station, tag and puzzle text has an Arabic translation", function()
  I18n.setLanguage("ar")
  local missing = {}
  local function check(s)
    if type(s) ~= "string" then return end
    s = s:gsub("%%d", "3") -- texts are shown with their numbers filled in
    if not I18n.hasArabic(I18n.t(s)) then missing[#missing + 1] = s end
  end
  local Mission = require("src.mission_state")
  for _, lv in ipairs(Mission.LEVELS) do
    check(lv.name); check(lv.room); check(lv.lesson)
    for _, task in ipairs(lv.tasks) do check(task.text) end
  end
  local Room = require("src.room_scene")
  for _, tag in pairs(Room.STATE_TAGS) do check(tag[1]) end
  local r = Room.new({ isDown = function() return false end })
  for _, m in ipairs(r.machines) do
    check(m.title); check(m.tech); check(m.subtitle); check(m.success)
    for _, p in pairs(m.problems) do check(p) end
  end
  for _, cls in pairs(require("src.puzzles.manager").REGISTRY) do check(cls.title); check(cls.hint); check(cls.system) end
  for _, item in ipairs(PauseMenu.ITEMS) do check(item.label) end
  local Map = require("src.station_map")
  for _, room in ipairs(Map.rooms) do check(room.name) end
  I18n.setLanguage("en")
  if #missing > 0 then error("missing Arabic: " .. table.concat(missing, " | ")) end
end)

test("read aloud: cleans text, only speaks automatically when switched on", function()
  eq(TTS.clean("Use the CO₂ Scrubber!\nNow"), "Use the C O 2 Scrubber! Now")
  TTS.setEnabled(false); TTS.lastSpoken = nil
  TTS.auto("Hello there"); eq(TTS.lastSpoken, nil)
  TTS.setEnabled(true)
  TTS.auto("Hello there"); eq(TTS.lastSpoken, "Hello there")
  TTS.lastSpoken = nil
  TTS.auto("Hello there"); eq(TTS.lastSpoken, nil, "the same sentence is not repeated")
  TTS.setEnabled(false)
end)

test("pause menu: keyboard, mouse and touch pick the right action", function()
  local used = {}
  local actions = { value = function(id) return id == "language" and "English" or "ON" end }
  for _, item in ipairs(PauseMenu.ITEMS) do actions[item.id] = function() used[#used + 1] = item.id end end
  local p = PauseMenu.new(actions)
  eq(p:keypressed("escape"), "resume")
  p:keypressed("down"); p:keypressed("down"); eq(p:keypressed("return"), "tts")
  p:keypressed("up"); p:keypressed("up"); p:keypressed("up"); eq(p.selected, #PauseMenu.ITEMS, "wraps around")
  local x, y, w, h = p:rect(6)
  eq(p:mousepressed(x + w / 2, y + h / 2), "menu")
  eq(p:mousepressed(5, 5), nil)
  eq(p:label(2), "LANGUAGE: English")
  eq(table.concat(used, ","), "resume,tts,menu")
end)

test("the speaker button in the room reads the task", function()
  local Room = require("src.room_scene")
  local r = Room.new({ isDown = function() return false end, campaign = true })
  local text = r:readAloudText()
  assert(text:find("Food Dispenser"), text)
  local sp = Room.SPEAKER
  eq(r:mousepressed(sp.x, sp.y, 1), nil)
  eq(TTS.lastSpoken, TTS.clean(text))
end)

T.finish()
