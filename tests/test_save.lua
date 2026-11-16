-- Saving and loading (plain Lua): progress + settings survive closing the
-- game, in the save folder and in the browser's localStorage copy.
-- Run from the repository root:  lua tests/test_save.lua
package.path = "./?.lua;" .. package.path
local T = require("tests.helpers")
local test, eq = T.test, T.eq
local Store = require("src.store")
local Progress = require("src.progress")
local Settings = require("src.settings")

-- an in-memory save folder; `printed` collects what the web page would get
local files, printed = {}, {}
local function fresh(web, args)
  files = {}
  printed = {}
  Store.backend = {
    read = function(f) return files[f] end,
    write = function(f, text) files[f] = text end,
    remove = function(f) files[f] = nil end,
  }
  Store.revs = {}
  Store.init(args or {})
  Store.web = web or false
end
local realPrint = print
local function capture(fn)
  print = function(s) printed[#printed + 1] = s end
  local ok, err = pcall(fn)
  print = realPrint
  if not ok then error(err, 2) end
end

-- what the web page does with a printed "@@SAVE@@name=data" line
local function pageStores(line)
  local name, data = line:match("^@@SAVE@@([%w_]+)=(.*)$")
  assert(name, "not a save line: " .. tostring(line))
  return "--store:" .. name .. "=" .. data
end

test("text survives encoding for the browser (newlines, =, %, Arabic)", function()
  local s = "rev=3\nlang=ar\nx=50% & more\nمرحبا"
  eq(Store.decode(Store.encode(s)), s)
  assert(not Store.encode(s):find("[\n=%s]"), "one printable line")
end)

test("a new player starts at Level 1; broken saves are ignored", function()
  fresh()
  Progress.load()
  eq(Progress.level, 1); eq(Progress.hasSave(), false)
  for _, bad in ipairs({ "level=99", "level=-1", "level=2.5", "level=abc", "garbage", "" }) do
    local p = Progress.parse(bad)
    eq(p.level, 1, bad)
  end
  eq(Progress.parse("level=5\nbest=7\nwins=-2").best, 0, "stars 0-3 only")
end)

test("reaching a level saves it; loading continues from there", function()
  fresh()
  Progress.load()
  Progress.reachLevel(4)
  Progress.level = 1                 -- forget it in memory...
  Progress.load()                    -- ...and load it back from the file
  eq(Progress.level, 4)
  eq(Progress.hasSave(), true)
  Progress.startOver()
  Progress.load()
  eq(Progress.level, 1)
end)

test("finishing keeps the best stars and counts wins; next game is Level 1", function()
  fresh()
  Progress.load()
  Progress.reachLevel(8)
  Progress.finish(2)
  Progress.finish(3)
  Progress.finish(1)
  Progress.load()
  eq(Progress.level, 1); eq(Progress.best, 3); eq(Progress.wins, 3)
end)

test("in a browser every save is also sent to localStorage and read back", function()
  fresh(true)
  Progress.load()
  capture(function() Progress.reachLevel(6) end)
  eq(#printed, 1)
  local arg = pageStores(printed[1])
  -- the browser lost its save folder (IndexedDB) but kept localStorage
  fresh(true, { "./game.love", "--noaudio", arg })
  Progress.load()
  eq(Progress.level, 6)
end)

test("the newer copy wins (save folder vs browser copy)", function()
  -- browser copy is newer
  fresh(true)
  Progress.load()
  capture(function() Progress.reachLevel(2); Progress.reachLevel(3) end)
  local newer = pageStores(printed[2])
  files["progress.txt"] = "rev=1\nlevel=2\nbest=0\nwins=0\n"
  Store.revs = {}
  Store.init({ newer }); Progress.load()
  eq(Progress.level, 3, "browser copy (rev 2) beats the file (rev 1)")
  -- save folder is newer
  files["progress.txt"] = "rev=9\nlevel=7\nbest=0\nwins=0\n"
  Store.revs = {}
  Store.init({ newer }); Progress.load()
  eq(Progress.level, 7, "file (rev 9) beats the browser copy (rev 2)")
  -- the next save continues counting from the newest rev
  Progress.reachLevel(8)
  eq(Store.revOf(files["progress.txt"]), 10)
end)

test("settings use the same store (and old settings files still load)", function()
  fresh()
  files["settings.txt"] = "lang=ar\ntts=0\nmute=1\n" -- written by an older version
  Settings.lang, Settings.tts, Settings.mute = "en", false, false
  Settings.load()
  eq(Settings.lang, "ar"); eq(Settings.mute, true)
  Settings.lang = "en"; Settings.save()
  Settings.lang = "ar"; Settings.load()
  eq(Settings.lang, "en")
end)

test("bad names and odd arguments never break start-up", function()
  fresh()
  eq(Store.write("../evil", "x"), false)
  eq(Store.read("a b"), nil)
  Store.init({ "--store:=x", "--store:progress", 42, "--store:progress=%ZZ%" })
  Progress.load()
  eq(Progress.level, 1)
end)

test("the room continues a saved level and R retries it", function()
  local Room = require("src.room_scene")
  local r = Room.new({ isDown = function() return false end, campaign = true })
  r:reset(5)
  eq(r.mission.level, 5)
  eq(r.mission:objective().id, "compost")
  eq(r:isRoomLocked("waste"), false); eq(r:isRoomLocked("air"), true)
  eq(r.ls.autopilot.waste, nil); eq(r.ls.autopilot.air, true)
  assert(r.ls.plantScraps > 0, "the level's first job is ready")
  assert(r.news:find("Welcome back"), r.news)
  r:keypressed("r")
  eq(r.mission.level, 5, "R restarts the level, not the whole mission")
  r:reset(99); eq(r.mission.level, 8, "clamped")
  r:reset(); eq(r.mission.level, 1)
  r.missionComplete = true; eq(r:checkpoint(), 1, "after a win: a new mission")
end)

Store.backend = nil
T.finish()
