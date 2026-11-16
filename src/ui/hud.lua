--[[
  In-game HUD (screen space, 1280 x 720), styled after the team's menu:
  cut-corner navy panels with cyan edges, Bahnschrift text, drawn icons.
    clock card (top-left) | guide / emergency banner (top-centre)
    7 system cards (right) | minimap (bottom-left) | news ticker (bottom)
]]
local Theme = require("src.ui.theme")
local Icons = require("src.ui.icons")
local Map = require("src.station_map")
local C = Theme.C

local HUD = {}

HUD.PANEL_X, HUD.PANEL_W = 1030, 240
HUD.PAUSE = { x = 1236, y = 90, r = 30, hit = 48 } -- pause button (mouse + touch); hit = thumb-sized touch area
HUD.MINIMAP = { x = 14, y = 720 - 182, size = 168 }

local function f0(x) return math.floor(x + 0.5) end
local function statusColor(s) return Theme.STATUS[s] or C.cyan end

local function card(y, h, icon, iconColor, status, title, value, frac, msg, t)
  local lg = love.graphics
  local x, w = HUD.PANEL_X, HUD.PANEL_W
  local col = statusColor(status)
  local alarm = status == "critical" or status == "danger"
  Theme.panel(x, y, w, h, { cut = 10, edge = alarm and col or C.cyanMid, edgeAlpha = alarm and (0.6 + 0.4 * math.sin(t * 6)) or 0.9 })
  Theme.set(col); lg.rectangle("fill", x + 3, y + 12, 4, h - 24, 2, 2)
  -- icon bubble
  Theme.set(C.spaceDeep); lg.circle("fill", x + 32, y + 30, 21)
  Theme.set(col); lg.setLineWidth(2); lg.circle("line", x + 32, y + 30, 21); lg.setLineWidth(1)
  Icons.draw(icon, x + 32, y + 30, 26, iconColor)
  lg.setFont(Theme.font(13)); Theme.set(C.cyanLight)
  lg.print(title, x + 60, y + 8)
  lg.setFont(Theme.font(17)); Theme.set(C.white)
  lg.print(value, x + 60, y + 26)
  Theme.meter(x + 60, y + 50, w - 74, 7, frac, col)
  lg.setFont(Theme.font(11)); Theme.set(C.offWhite, 0.85)
  lg.printf(msg or "", x + 12, y + 61, w - 20, "left")
end

function HUD.drawCards(ls, t)
  local y, h, gap = 10, 82, 4
  local function row(i) return y + (i - 1) * (h + gap) end
  local a = ls:getAirFeedback()
  card(row(1), h, "air", C.oxygen, a.status, "AIR",
    string.format("O2 %.1f%%  CO2 %.2f%%", ls.air.oxygenPercent, ls.air.carbonDioxidePercent),
    ls.air.airQuality / 100, a.message, t)
  local w = ls:getWaterFeedback()
  card(row(2), h, "water", C.water, w.status, "WATER",
    string.format("Drink %d%%  O2 line %d", f0(ls.potableWater), f0(ls.processWater)),
    ls.potableWater / 100, w.message, t)
  local d = ls:getDustFeedback()
  card(row(3), h, "clean", C.cyanLight, d.cabinStatus, "CABIN CLEANLINESS",
    string.format("%d%%  (filter %d)", f0(d.cleanliness), ls.dust.filterUses),
    d.cleanliness / 100, d.cabinMessage, t)
  local p = ls:getPowerFeedback()
  card(row(4), h, "power", C.power, p.status, "POWER",
    string.format("Battery %d%%  %s", f0(ls.battery), ls.powerSaver and "SAVER" or ""),
    ls.battery / 100, string.format("Sun +%d/min  Use -%d/min", f0(p.genPerMin), f0(p.usePerMin)), t)
  local fd = ls:getFoodFeedback()
  card(row(5), h, "food", C.food, fd.status, "FOOD",
    string.format("%d%%  Plants %d%%", f0(ls.food), math.floor(ls.growth)),
    ls.food / 100, fd.greenhouse, t)
  local hm = ls:getHumanFeedback()
  card(row(6), h, "health", C.critical, hm.status, "VULCAN",
    string.format("Health %d", f0(ls.human.health)), ls.human.health / 100, hm.message, t)
  local r = ls:getRadiationFeedback()
  card(row(7), h, "radiation", C.caution, r.status, "RADIATION",
    string.format("%s  Shields %d/%d", r.phase:upper(), r.deployed, r.total), r.deployed / r.total, r.message, t)
  -- (values use a smaller font so every card fits)
end

-- The always-visible HUD deliberately contains only the three survival
-- resources.  Everything else remains available behind the Mission Tablet.
-- autopilot[system] = true -> Mission Control still runs it (shown dimmed).
function HUD.drawVitals(ls, t, autopilot)
  local lg = love.graphics
  autopilot = autopilot or {}
  local items = {
    { "AIR", string.format("O2 %.1f  CO2 %.2f", ls.air.oxygenPercent, ls.air.carbonDioxidePercent), ls.air.airQuality / 100, ls:getAirFeedback().status, C.oxygen, autopilot.air },
    { "WATER", string.format("%d%%", f0(ls.potableWater)), ls.potableWater / 100, ls:getWaterFeedback().status, C.water, autopilot.water },
    { "BATTERY", string.format("%d%%", f0(ls.battery)), ls.battery / 100, ls:getPowerFeedback().status, C.power, autopilot.power },
  }
  local x = 878
  for i, item in ipairs(items) do
    local bx = x + (i - 1) * 128
    local auto = item[6]
    Theme.panel(bx, 10, 120, 46, { cut = 8, edge = auto and C.metalDark or statusColor(item[4]) })
    lg.setFont(Theme.font(11)); Theme.set(auto and C.metalShade or C.cyanLight); lg.printf(item[1], bx + 8, 15, 104, "center")
    if auto then
      lg.setFont(Theme.font(11)); Theme.set(C.metalShade); lg.printf("MISSION CONTROL", bx + 4, 30, 112, "center")
    else
      lg.setFont(Theme.font(13)); Theme.set(C.white); lg.printf(item[2], bx + 8, 27, 104, "center")
    end
    Theme.meter(bx + 10, 48, 100, 4, item[3], auto and C.metalShade or item[5])
  end
  Theme.panel(14, 654, 126, 42, { cut = 8, edge = statusColor(ls.human.healthStatus) })
  lg.setFont(Theme.font(12)); Theme.set(C.white); lg.printf(string.format("VULCAN  %d%%", f0(ls.human.health)), 20, 667, 114, "center")
  Theme.meter(24, 685, 104, 4, ls.human.health / 100, statusColor(ls.human.healthStatus))
  if HUD.touchMode then return end -- on phones the touch buttons take this corner
  Theme.panel(1130, 654, 136, 42, { cut = 8, edge = C.cyanMid })
  lg.setFont(Theme.font(12)); Theme.set(C.cyanLight); lg.printf("TAB tablet  M sound", 1134, 667, 128, "center")
end

function HUD.drawClock(ls, outside)
  local lg = love.graphics
  local day, hour, minute = ls:clock()
  Theme.panel(14, 10, 210, 46, { cut = 10 })
  local sun = ls:isSunUp()
  Icons.draw(sun and "sun" or "moon", 40, 33, 30, sun and C.power or C.cream)
  lg.setFont(Theme.font(22)); Theme.set(C.white)
  lg.print(string.format("DAY %d  %02d:%02d", day, hour, minute), 64, 19)
  if outside then
    Theme.panel(14, 112, 210, 30, { cut = 8, edge = C.caution })
    lg.setFont(Theme.font(14)); Theme.set(C.caution); lg.printf("ON THE MOON SURFACE", 14, 119, 210, "center")
  end
end

-- Level tracker: 8 systems from easiest to hardest
local SHORT = { "HUMAN", "DUST", "WATER", "FOOD", "WASTE", "AIR", "POWER", "RADIATION" }
function HUD.drawLevel(mission, t)
  local lg = love.graphics
  local x, y, w, h = 14, 62, 210, 46
  local lv = mission:currentLevel()
  Theme.panel(x, y, w, h, { cut = 10, edge = C.cyan })
  lg.setFont(Theme.font(13)); Theme.set(C.cyan)
  lg.print(mission:isComplete() and "ALL LEVELS DONE!" or string.format("LEVEL %d/8  %s", mission.level, lv.name), x + 12, y + 6)
  for i = 1, 8 do
    local px = x + 16 + (i - 1) * 24
    local done = i < mission.level or mission:isComplete()
    local cur = i == mission.level and not mission:isComplete()
    local col = done and C.good or (cur and C.cyan or C.metalDark)
    if cur then Theme.set(C.cyan, 0.3 + 0.2 * math.sin(t * 4)); lg.circle("fill", px + 6, y + 32, 11) end
    Theme.set(C.ink); lg.circle("fill", px + 6, y + 32, 8)
    Theme.set(col); lg.circle("fill", px + 6, y + 32, 6)
  end
end

-- Big "NEW AREA UNLOCKED" card
function HUD.drawUnlock(card, t)
  local lg = love.graphics
  local a = math.min(1, card.timer * 2, (6 - card.timer) * 4)
  local w, h = 560, 190
  local x, y = 640 - w / 2, 150 - (1 - a) * 30
  Theme.panel(x, y, w, h, { cut = 22, fill = C.space, alpha = 0.96 * a, edge = C.good, lineWidth = 3 })
  lg.setFont(Theme.font(16)); Theme.set(C.good, a)
  lg.printf(string.format("LEVEL %d UNLOCKED!", card.index), x, y + 16, w, "center")
  lg.setFont(Theme.font(30)); Theme.set(C.white, a)
  lg.printf(card.level.name, x, y + 40, w, "center")
  lg.setFont(Theme.font(18)); Theme.set(C.cyanLight, a)
  lg.printf("New area: " .. card.level.room, x, y + 82, w, "center")
  lg.setFont(Theme.font(15)); Theme.set(C.offWhite, a * 0.9)
  lg.printf(card.level.lesson, x + 30, y + 114, w - 60, "center")
  lg.setFont(Theme.font(12)); Theme.set(C.metalShade, a)
  lg.printf("click to continue", x, y + h - 24, w, "center")
end

-- Guide banner, or the red emergency countdown
function HUD.drawBanner(ls, guide, t)
  local lg = love.graphics
  local x, w = 240, 584
  if ls:isAnyCritical() and not ls.missionFailed then
    local names = { air = "AIR", water = "WATER", power = "POWER", radiation = "RADIATION", health = "HEALTH", dust = "DUST" }
    local parts = {}
    for _, s in ipairs(ls:criticalSystems()) do parts[#parts + 1] = names[s] end
    local pulse = 0.75 + 0.25 * math.sin(t * 8)
    Theme.panel(x, 10, w, 52, { cut = 14, fill = Theme.darken(C.critical, 0.45), edge = C.critical, alpha = 0.95, lineWidth = 3 })
    Icons.draw("alert", x + 34, 36, 32, C.critical)
    lg.setFont(Theme.font(24)); Theme.set(C.white, pulse)
    lg.printf(string.format("EMERGENCY: %s  -  %d s", table.concat(parts, " + "), math.ceil(ls:getCriticalTimeLeft())),
      x + 60, 16, w - 80, "left")
    if guide then
      lg.setFont(Theme.font(13)); Theme.set(C.offWhite)
      lg.printf(guide.text, x + 60, 43, w - 80, "left")
    end
    return
  end
  if not guide then return end
  local col = statusColor(guide.level == "tip" and "good" or guide.level)
  if guide.level == "tip" then col = C.cyan end
  Theme.panel(x, 10, w, 46, { cut = 12, edge = col })
  Icons.draw("arrow", x + 32, 33, 30, col)
  lg.setFont(Theme.font(13)); Theme.set(col)
  lg.print(guide.level == "tip" and "NEXT TASK" or "NEEDS YOU", x + 60, 14)
  local size = 19
  local I18n = require("src.i18n")
  while size > 12 and I18n.width(Theme.font(size), guide.text) > w - 76 do size = size - 1 end
  lg.setFont(Theme.font(size)); Theme.set(C.white)
  lg.print(guide.text, x + 60, 29 + (19 - size) * 0.5)
end

function HUD.hitPause(x, y)
  local b = HUD.PAUSE
  return (x - b.x) ^ 2 + (y - b.y) ^ 2 <= b.hit ^ 2
end

function HUD.drawPauseButton(hot)
  local lg = love.graphics
  local b = HUD.PAUSE
  Theme.set(C.ink); lg.circle("fill", b.x, b.y, b.r + 3)
  Theme.set(hot and C.cyanMid or C.space); lg.circle("fill", b.x, b.y, b.r)
  Theme.set(C.cyan); lg.setLineWidth(3); lg.circle("line", b.x, b.y, b.r); lg.setLineWidth(1)
  Theme.set(C.white)
  lg.rectangle("fill", b.x - 10, b.y - 11, 7, 22, 2, 2)
  lg.rectangle("fill", b.x + 3, b.y - 11, 7, 22, 2, 2)
end

-- read-aloud button (English text-to-speech)
function HUD.drawSpeaker(b, autoOn, t, disabled)
  local lg = love.graphics
  Theme.set(C.ink); lg.circle("fill", b.x, b.y, b.r + 3)
  Theme.set(autoOn and not disabled and C.cyan or C.space, disabled and 0.6 or 1); lg.circle("fill", b.x, b.y, b.r)
  Theme.set(disabled and C.metalDark or C.cyan); lg.setLineWidth(2); lg.circle("line", b.x, b.y, b.r); lg.setLineWidth(1)
  Icons.draw("speaker", b.x, b.y, b.r * 1.3, disabled and C.metalShade or (autoOn and C.ink or C.white))
end

function HUD.drawMinimap(machines, vulcan, cam, view, ls, guide, t)
  local lg = love.graphics
  local mm = HUD.MINIMAP
  local s = mm.size / Map.WIDTH
  local x0, y0 = mm.x, mm.y
  Theme.panel(x0 - 6, y0 - 6, mm.size + 12, mm.size + 12, { cut = 10 })
  Theme.set(C.cream, 0.25); lg.rectangle("fill", x0, y0, mm.size, mm.size)
  Theme.set(C.metalDark)
  for _, c in ipairs(Map.corridors) do lg.rectangle("fill", x0 + c.x * s, y0 + c.y * s, c.w * s, c.h * s) end
  local needs = {}
  for _, m in ipairs(machines) do
    local ok, reason = m.check(ls)
    if not ok and m.redReasons and m.redReasons[reason] then needs[m.room] = true end
  end
  local pulse = 0.5 + 0.5 * math.sin(t * 6)
  for _, r in ipairs(Map.rooms) do
    local col = Theme.ROOM[r.id] or C.cyan
    if needs[r.id] then Theme.set(C.critical, 0.6 + 0.4 * pulse) else Theme.set(col, 0.85) end
    lg.rectangle("fill", x0 + r.x * s, y0 + r.y * s, r.w * s, r.h * s, 2, 2)
    if r.extra then for _, e in ipairs(r.extra) do lg.rectangle("fill", x0 + e.x * s, y0 + e.y * s, e.w * s, e.h * s) end end
  end
  -- guide target
  if guide and guide.target then
    Theme.set(C.white, pulse); lg.circle("line", x0 + guide.target.x * s, y0 + guide.target.y * s, 5 + 3 * pulse)
  end
  Theme.set(C.white, 0.7); lg.rectangle("line", x0 + cam.x * s, y0 + cam.y * s, view.w * s, view.h * s)
  Theme.circle(x0 + vulcan.x * s, y0 + vulcan.y * s, 4, C.caution, 1)
end

function HUD.drawNews(text)
  if not text then return end
  local lg = love.graphics
  local x, w = 200, 816
  Theme.panel(x, 720 - 50, w, 40, { cut = 10, edge = C.cyanMid })
  lg.setFont(Theme.font(15)); Theme.set(C.white)
  lg.printf(text, x + 16, 720 - 40, w - 32, "center")
end

return HUD
