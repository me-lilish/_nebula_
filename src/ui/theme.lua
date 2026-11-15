--[[
  Visual theme - palette, fonts and drawing helpers
  =================================================
  Style taken from the team's main-menu art (JuniorAstronautMission):
  deep navy space, cream Moon with craters, bright blue/green Earth, glowing
  cyan sci-fi buttons with cut corners, thick dark outlines, flat cel shading.
]]

local Theme = {}

local function hex(h, a)
  h = h:gsub("#", "")
  return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, a or 1 }
end
Theme.hex = hex

Theme.C = {
  space = hex("#131030"), spaceDeep = hex("#0B0920"),
  ink = hex("#1B1830"), inkSoft = hex("#2D2950"),
  cream = hex("#F1E9C3"), crater = hex("#D9CFA2"), craterShade = hex("#C4B98A"),
  cyan = hex("#4DEBFF"), cyanDark = hex("#2F5468"), cyanMid = hex("#3E6375"), cyanLight = hex("#A8F6FF"),
  earthBlue = hex("#0A66FF"), earthGreen = hex("#6BE05A"),
  white = hex("#FFFFFF"), offWhite = hex("#F4F6FB"),
  hull = hex("#E3E8F2"), hullShade = hex("#B7C0D6"), hullDark = hex("#8E98B3"),
  floor = hex("#2C3254"), floorLine = hex("#252A48"), floorLight = hex("#363E66"),
  corridor = hex("#242946"), grate = hex("#1D2140"),
  wallFace = hex("#3F4776"), wallPanel = hex("#4B5589"), wallTrim = hex("#2A3058"),
  metal = hex("#C9D2E3"), metalShade = hex("#9AA6C0"), metalDark = hex("#5E6888"),
  screen = hex("#0E2A3A"), screenGlow = hex("#4DEBFF"),
  good = hex("#5BE37D"), caution = hex("#FFD84D"), danger = hex("#FF9A3C"), critical = hex("#FF4D5E"),
  water = hex("#3FA9FF"), urine = hex("#F5D547"), brine = hex("#D9DCE6"), oxygen = hex("#8FE4FF"),
  hydrogen = hex("#FF9EDB"), co2 = hex("#B0B6C8"), plant = hex("#5CCB5F"), soil = hex("#7A5A3A"),
  power = hex("#FFD23F"), food = hex("#FFB25C"), waste = hex("#B98CFF"), dust = hex("#C9B98A"),
}

-- Room accent colours (signs, light strips, minimap)
Theme.ROOM = {
  power = hex("#FFD23F"), batteries = hex("#FFB13F"), water = hex("#3FA9FF"), quarters = hex("#FF8FC7"),
  airlock = hex("#FF9A3C"), comms = hex("#4DEBFF"), food = hex("#7EE06A"), air = hex("#8FE4FF"),
  waste = hex("#B98CFF"),
}

Theme.STATUS = { good = Theme.C.good, clean = Theme.C.good, caution = Theme.C.caution,
  danger = Theme.C.danger, critical = Theme.C.critical }

------------------------------------------------------------------------------
-- Fonts: Bahnschrift (Windows) gives a clean sci-fi look; falls back to the
-- default font everywhere else.
------------------------------------------------------------------------------
local fontCache = {}
local fontData

local function loadFontData()
  if fontData ~= nil then return fontData end
  fontData = false
  for _, path in ipairs({ "C:/Windows/Fonts/bahnschrift.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" }) do
    local f = io.open(path, "rb")
    if f then
      local bytes = f:read("*a"); f:close()
      local ok, data = pcall(love.filesystem.newFileData, bytes, "ui.ttf")
      if ok then fontData = data; break end
    end
  end
  return fontData
end

local fontSize = setmetatable({}, { __mode = "k" }) -- font object -> size

function Theme.font(size)
  if fontCache[size] then return fontCache[size] end
  local data = loadFontData()
  local ok, f = false, nil
  if data then ok, f = pcall(love.graphics.newFont, data, size) end
  if not ok or not f then f = love.graphics.newFont(size) end
  fontCache[size] = f
  fontSize[f] = size
  return f
end

-- Arabic text uses DejaVu Sans (assets/fonts, free licence, has every
-- joined Arabic letter form), at the size of the English font it replaces.
local arabicCache, arabicData = {}, nil
local function loadArabicData()
  if arabicData ~= nil then return arabicData end
  arabicData = false
  local path = "assets/fonts/DejaVuSans-Bold.ttf"
  local ok, d = pcall(love.filesystem.newFileData, path)
  if ok and d then arabicData = d; return d end
  local f = io.open(path, "rb")
  if f then
    local bytes = f:read("*a"); f:close()
    local ok2, d2 = pcall(love.filesystem.newFileData, bytes, "arabic.ttf")
    if ok2 then arabicData = d2 end
  end
  return arabicData
end

function Theme.arabicFontFor(font)
  local size = (font and fontSize[font]) or 14
  if arabicCache[size] == nil then
    local data = loadArabicData()
    local ok, f = false, nil
    if data then ok, f = pcall(love.graphics.newFont, data, math.max(8, math.floor(size * 0.86 + 0.5))) end
    arabicCache[size] = (ok and f) or false
  end
  return arabicCache[size] or nil
end

------------------------------------------------------------------------------
-- Colour helpers
------------------------------------------------------------------------------
function Theme.set(c, a)
  love.graphics.setColor(c[1], c[2], c[3], (a or 1) * (c[4] or 1))
end

function Theme.mix(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, 1 }
end

function Theme.lighten(c, t) return Theme.mix(c, { 1, 1, 1 }, t) end
function Theme.darken(c, t) return Theme.mix(c, { 0, 0, 0 }, t) end

------------------------------------------------------------------------------
-- Shape helpers
------------------------------------------------------------------------------
local lg = love and love.graphics

-- Angular sci-fi panel (cut corners), like the team's Start Mission button.
function Theme.cutPoints(x, y, w, h, cut)
  cut = cut or 12
  return { x + cut, y, x + w - cut, y, x + w, y + cut, x + w, y + h - cut, x + w - cut, y + h,
    x + cut, y + h, x, y + h - cut, x, y + cut }
end

function Theme.panel(x, y, w, h, opts)
  opts = opts or {}
  local lg = love.graphics
  local cut = opts.cut or 12
  local pts = Theme.cutPoints(x, y, w, h, cut)
  Theme.set(opts.fill or Theme.C.space, opts.alpha or 0.88)
  lg.polygon("fill", pts)
  Theme.set(opts.edge or Theme.C.cyan, opts.edgeAlpha or 0.9)
  lg.setLineWidth(opts.lineWidth or 2)
  lg.polygon("line", pts)
  lg.setLineWidth(1)
  if opts.accent then
    Theme.set(opts.accent)
    lg.rectangle("fill", x + cut, y + 2, math.min(60, w - 2 * cut), 4)
  end
end

-- Box with a thick ink outline (the team's flat cartoon style)
function Theme.box(x, y, w, h, fill, r, lw)
  local lg = love.graphics
  Theme.set(fill)
  lg.rectangle("fill", x, y, w, h, r or 0, r or 0)
  Theme.set(Theme.C.ink)
  lg.setLineWidth(lw or 3)
  lg.rectangle("line", x, y, w, h, r or 0, r or 0)
  lg.setLineWidth(1)
end

function Theme.circle(x, y, r, fill, lw)
  local lg = love.graphics
  Theme.set(fill); lg.circle("fill", x, y, r)
  Theme.set(Theme.C.ink); lg.setLineWidth(lw or 3); lg.circle("line", x, y, r); lg.setLineWidth(1)
end

-- 3/4-view machine body: lighter top face + front face + ink outline + shadow
function Theme.machineBody(x, y, w, h, color, topH)
  local lg = love.graphics
  topH = topH or math.min(22, h * 0.25)
  Theme.set(Theme.C.ink, 0.28)
  lg.rectangle("fill", x + 6, y + h - 4, w, 12, 6, 6)
  Theme.set(Theme.darken(color, 0.12))
  lg.rectangle("fill", x, y + topH, w, h - topH, 6, 6)
  Theme.set(Theme.lighten(color, 0.25))
  lg.rectangle("fill", x, y, w, topH + 6, 6, 6)
  Theme.set(Theme.lighten(color, 0.55), 0.6)
  lg.rectangle("fill", x + 6, y + 4, w - 12, 3, 2, 2)
  Theme.set(Theme.C.ink)
  lg.setLineWidth(3)
  lg.rectangle("line", x, y, w, h, 6, 6)
  lg.line(x, y + topH, x + w, y + topH)
  lg.setLineWidth(1)
end

-- Little screen with glow; content drawn by callback in screen coordinates
function Theme.screen(x, y, w, h, glow, fn)
  local lg = love.graphics
  Theme.set(Theme.C.screen); lg.rectangle("fill", x, y, w, h, 3, 3)
  if fn then
    lg.push("all")
    fn(x, y, w, h)
    lg.pop()
  end
  Theme.set(glow or Theme.C.screenGlow, 0.25); lg.rectangle("fill", x, y, w, h * 0.35, 3, 3)
  Theme.set(Theme.C.ink); lg.setLineWidth(2); lg.rectangle("line", x, y, w, h, 3, 3); lg.setLineWidth(1)
end

function Theme.led(x, y, on, color)
  local lg = love.graphics
  if on then
    Theme.set(color or Theme.C.good, 0.35); lg.circle("fill", x, y, 6)
    Theme.set(color or Theme.C.good); lg.circle("fill", x, y, 3)
  else
    Theme.set(Theme.C.metalDark); lg.circle("fill", x, y, 3)
  end
end

-- Horizontal meter with rounded ends
function Theme.meter(x, y, w, h, frac, color, back)
  local lg = love.graphics
  frac = math.max(0, math.min(1, frac))
  Theme.set(back or Theme.C.inkSoft); lg.rectangle("fill", x, y, w, h, h / 2, h / 2)
  if frac * w >= h then Theme.set(color); lg.rectangle("fill", x, y, frac * w, h, h / 2, h / 2) end
end

-- Text with a dark outline so it reads on any background
function Theme.outlinedText(text, x, y, w, align, color, outline, font)
  local lg = love.graphics
  if font then lg.setFont(font) end
  Theme.set(outline or Theme.C.ink)
  for _, o in ipairs({ { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 }, { -1, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 } }) do
    lg.printf(text, x + o[1], y + o[2], w, align)
  end
  Theme.set(color or Theme.C.white)
  lg.printf(text, x, y, w, align)
end

return Theme
