--[[
  Main menu + mission briefing
  ============================
  Built from the team's JuniorAstronautMission main menu (art in
  assets/menu, copied from their project): navy space, twinkling hand-drawn
  stars, Earth in the corner, the SPACE MISSION title, a floating spinning
  astronaut and the Start / Abort Mission buttons.
  After "Start Mission" a briefing card explains the mission and controls.

  Menu.new(onStart, onQuit); menu:update(dt, mx, my); menu:draw();
  menu:mousepressed(x, y, b); menu:keypressed(key)
]]
local Theme = require("src.ui.theme")
local Icons = require("src.ui.icons")
local Assets = require("src.assets")
local C = Theme.C

local Menu = {}
Menu.__index = Menu

local W, H = 1280, 720

function Menu.new(onStart, onQuit)
  local self = setmetatable({ onStart = onStart, onQuit = onQuit, state = "menu", t = 0 }, Menu)
  local img = function(n) return Assets.image("assets/menu/" .. n .. ".png") end
  self.earth, self.title = img("menu_earth"), img("menu_title")
  self.startN, self.startH = img("start_normal"), img("start_hover")
  self.abortN, self.abortH = img("abort_normal"), img("abort_hover")
  self.starImgs = {}
  for i = 1, 7 do self.starImgs[i] = img("star" .. i) end
  self.astro = Assets.image("assets/vulcan_idle.png")
  self.astroState = { x = 900, y = 260, vx = 120, vy = 90, angle = 0 }
  -- buttons (centre x, centre y, width)
  self.buttons = {
    { id = "start", cx = W / 2, cy = 470, w = 420, n = self.startN, h = self.startH },
    { id = "abort", cx = W / 2, cy = 570, w = 420, n = self.abortN, h = self.abortH },
  }
  -- language + read-aloud toggles (main menu) and the briefing speaker button.
  -- main.lua sets onLanguage / onTTS / onSpeak and valueOf(id) -> text.
  self.toggles = {
    { id = "lang", label = "LANGUAGE: %s", x = 296, y = 640, w = 330, h = 44 },
    { id = "tts", label = "READ ALOUD: %s", x = 654, y = 640, w = 330, h = 44 },
  }
  self.speaker = { x = 1040, y = 120, r = 30 }
  self.stars = Menu.placeStars(42, 64)
  return self
end

------------------------------------------------------------------------------
-- Star placement (pure, testable): evenly spread twinkling stars that never
-- sit on text, buttons, the Earth or the Moon.
------------------------------------------------------------------------------
-- rectangles (x0, y0, x1, y1) and circles (cx, cy, r) kept free of stars
Menu.STAR_KEEP_OUT = {
  rects = {
    { 290, 30, 990, 312 },   -- SPACE MISSION title + subtitle
    { 400, 400, 880, 632 },  -- Start / Abort buttons
    { 270, 626, 1010, 720 }, -- language + read-aloud buttons and the footer
  },
  circles = {
    { -150, 420, 300 },      -- the Earth (left)
    { W + 60, H + 40, 350 }, -- the Moon (bottom right)
  },
}
Menu.STAR_SPACING = 64     -- no two stars closer than this
Menu.STAR_MARGIN = 26      -- keep away from the screen edges

function Menu.starAllowed(x, y, r)
  local k = Menu.STAR_KEEP_OUT
  if x < Menu.STAR_MARGIN or x > W - Menu.STAR_MARGIN or y < Menu.STAR_MARGIN or y > H - Menu.STAR_MARGIN then return false end
  for _, b in ipairs(k.rects) do
    if x + r > b[1] and x - r < b[3] and y + r > b[2] and y - r < b[4] then return false end
  end
  for _, c in ipairs(k.circles) do
    if (x - c[1]) ^ 2 + (y - c[2]) ^ 2 < (c[3] + r) ^ 2 then return false end
  end
  return true
end

-- deterministic (same sky every time), no love.* needed
function Menu.placeStars(seed, count)
  local state = seed
  local function rnd() state = (state * 1103515245 + 12345) % 2147483648; return state / 2147483648 end
  local stars, tries = {}, 0
  while #stars < count and tries < 20000 do
    tries = tries + 1
    local size = 10 + math.floor(rnd() * 13)
    local x, y = 20 + rnd() * (W - 40), 15 + rnd() * (H - 30)
    if Menu.starAllowed(x, y, size / 2 + 4) then
      local ok = true
      for _, o in ipairs(stars) do
        if (o.x - x) ^ 2 + (o.y - y) ^ 2 < Menu.STAR_SPACING ^ 2 then ok = false; break end
      end
      if ok then
        stars[#stars + 1] = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), s = size,
          frame = 1 + math.floor(rnd() * 7), timer = rnd() * 0.5, speed = 0.08 + rnd() * 0.12 }
      end
    end
  end
  return stars
end

Menu.INTRO = "Welcome to the Moon base, Vulcan! Keep the habitat alive: every machine is connected, just like on a real space station."
Menu.STEPS = {
  { "health", { 1, 0.3, 0.37, 1 }, "Start in the Crew Quarters: eat, use the bathroom and sleep." },
  { "clean", { 0.66, 0.96, 1, 1 }, "Each level opens a new room and a new system to look after." },
  { "air", { 0.56, 0.89, 1, 1 }, "Every machine has a mini-game: win it to make the machine work." },
  { "water", { 0.25, 0.66, 1, 1 }, "Locked rooms are run by Mission Control until you reach them." },
  { "power", { 1, 0.82, 0.25, 1 }, "Watch air, water and battery at the top of the screen." },
  { "radiation", { 1, 0.85, 0.3, 1 }, "At Level 8 a solar storm comes: pile Moon soil as shields!" },
}

local function buttonRect(b)
  local img = b.n
  local h = img and (img:getHeight() * b.w / img:getWidth()) or 70
  return b.cx - b.w / 2, b.cy - h / 2, b.w, h
end

function Menu:hit(mx, my)
  for _, b in ipairs(self.buttons) do
    local x, y, w, h = buttonRect(b)
    -- the visible button sits in the middle 80% of the art
    if mx > x + w * 0.08 and mx < x + w * 0.92 and my > y + h * 0.1 and my < y + h * 0.9 then return b.id end
  end
  return nil
end

-- optional sound hook: menu.sound = function(name) ... end
function Menu:_sound(name) if self.sound then self.sound(name) end end

function Menu:update(dt, mx, my)
  self.t = self.t + dt
  local tg = self.state == "menu" and self:toggleAt(mx or -1, my or -1)
  self.hoverToggle = tg and tg.id or nil
  local hover = (self.state == "menu") and self:hit(mx or -1, my or -1) or nil
  if hover and hover ~= self.hover then self:_sound("sfx_hover") end
  self.hover = hover
  if self.quitTimer then
    self.quitTimer = self.quitTimer - dt
    if self.quitTimer <= 0 then self.quitTimer = nil; if self.onQuit then self.onQuit() end end
  end
  local a = self.astroState
  a.angle = a.angle + 1.2 * dt
  a.x, a.y = a.x + a.vx * dt, a.y + a.vy * dt
  if a.x < 60 or a.x > W - 60 then a.vx = -a.vx; a.x = math.max(60, math.min(W - 60, a.x)) end
  if a.y < 60 or a.y > H - 60 then a.vy = -a.vy; a.y = math.max(60, math.min(H - 60, a.y)) end
  for _, s in ipairs(self.stars) do
    s.timer = s.timer + dt
    if s.timer >= s.speed then s.timer = 0; s.frame = s.frame % 7 + 1 end
  end
end

function Menu:toggleAt(x, y)
  for _, b in ipairs(self.toggles or {}) do
    if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then return b end
  end
end

function Menu:onSpeaker(x, y)
  local sp = self.speaker
  return (x - sp.x) ^ 2 + (y - sp.y) ^ 2 <= sp.r * sp.r
end

-- English text of the briefing (read aloud by the speaker button)
function Menu:briefingText()
  local parts = { Menu.INTRO }
  for _, st in ipairs(Menu.STEPS) do parts[#parts + 1] = st[3] end
  return table.concat(parts, " ")
end

function Menu:mousepressed(x, y, button)
  if button ~= 1 then return end
  if self.state == "briefing" and self:onSpeaker(x, y) then
    self:_sound("sfx_click")
    if self.onSpeak then self.onSpeak(self:briefingText()) end
    return
  end
  if self.state == "menu" then
    local tg = self:toggleAt(x, y)
    if tg then
      self:_sound("sfx_click")
      if tg.id == "lang" and self.onLanguage then self.onLanguage() end
      if tg.id == "tts" and self.onTTS then self.onTTS() end
      return
    end
  end
  if self.state == "briefing" then
    self:_sound("sfx_click")
    if self.onStart then self.onStart() end
    return
  end
  local id = self:hit(x, y)
  if id then self:_sound("sfx_click") end
  if id == "start" then self.state = "briefing"
  elseif id == "abort" then self.quitTimer = 0.2 end -- let the click be heard
end

function Menu:keypressed(key)
  if key == "return" or key == "space" or key == "escape" then self:_sound("sfx_click") end
  if self.state == "briefing" then
    if key == "escape" then self.state = "menu"
    elseif self.onStart then self.onStart() end
  elseif key == "return" or key == "space" then
    self.state = "briefing"
  elseif key == "escape" and self.onQuit then
    self.onQuit()
  end
end

function Menu:_drawBackground()
  local lg = love.graphics
  Theme.set(C.space); lg.rectangle("fill", 0, 0, W, H)
  for _, s in ipairs(self.stars) do
    local img = self.starImgs[s.frame]
    if img then
      lg.setColor(1, 1, 1, 0.9)
      lg.draw(img, s.x, s.y, 0, s.s / img:getWidth(), s.s / img:getWidth(), img:getWidth() / 2, img:getHeight() / 2)
    end
  end
  if self.earth then
    lg.setColor(1, 1, 1)
    local s = 560 / self.earth:getWidth()
    lg.draw(self.earth, -150, H - 300, self.t * 0.02, s, s, self.earth:getWidth() / 2, self.earth:getHeight() / 2)
  end
  -- the Moon (the mission's destination) on the right
  Theme.set(C.cream); lg.circle("fill", W + 60, H + 40, 330)
  Theme.set(C.crater)
  for _, c in ipairs({ { W - 120, H - 170, 34 }, { W - 40, H - 250, 22 }, { W - 210, H - 60, 26 }, { W - 60, H - 90, 40 } }) do
    lg.circle("fill", c[1], c[2], c[3])
  end
end

function Menu:_drawAstronaut()
  local a, img = self.astroState, self.astro
  if not img then return end
  local lg = love.graphics
  lg.setColor(1, 1, 1)
  local s = 110 / img:getHeight()
  lg.draw(img, a.x, a.y, a.angle, s, s, img:getWidth() / 2, img:getHeight() / 2)
end

function Menu:draw()
  local lg = love.graphics
  self:_drawBackground()
  self:_drawAstronaut()
  if self.state == "menu" then
    if self.title then
      lg.setColor(1, 1, 1)
      local s = 640 / self.title:getWidth()
      lg.draw(self.title, W / 2 - 320, 50, 0, s, s)
    end
    Theme.outlinedText("JUNIOR ASTRONAUT TRAINER", 0, 268, W, "center", C.cyan, C.ink, Theme.font(24))
    for _, b in ipairs(self.buttons) do
      local img = (self.hover == b.id) and b.h or b.n
      if img then
        local x, y, w, h = buttonRect(b)
        local bob = (self.hover == b.id) and -3 or 0
        lg.setColor(1, 1, 1)
        lg.draw(img, x, y + bob, 0, w / img:getWidth(), w / img:getWidth())
        -- other languages: cover the English painted on the button art and
        -- write the translated label in the same cyan, outlined style
        local I18n = require("src.i18n")
        if I18n.lang ~= "en" then
          local label = b.id == "start" and "START MISSION" or "ABORT MISSION"
          Theme.set(Theme.hex(self.hover == b.id and "#263C5A" or "#2F526E")); lg.rectangle("fill", x + w * 0.085, y + bob + h * 0.18, w * 0.83, h * 0.64, 8, 8)
          Theme.outlinedText(label, x, y + bob + h * 0.5 - 20, w, "center", C.cyan, C.ink, Theme.font(34))
        end
      end
    end
    for _, b in ipairs(self.toggles or {}) do
      local off = self.isDisabled and self.isDisabled(b.id)
      local hot = self.hoverToggle == b.id and not off
      local pts = Theme.cutPoints(b.x, b.y, b.w, b.h, 10)
      Theme.set(hot and C.cyanMid or C.space, off and 0.6 or 0.92); lg.polygon("fill", pts)
      Theme.set(off and C.metalDark or C.cyan); lg.setLineWidth(2); lg.polygon("line", pts); lg.setLineWidth(1)
      local v = self.valueOf and self.valueOf(b.id) or ""
      lg.setFont(Theme.font(17)); Theme.set(off and C.metalShade or C.white)
      lg.printf(string.format(b.label, v), b.x, b.y + 11, b.w, "center")
    end
    lg.setFont(Theme.font(13)); Theme.set(C.cyanLight, 0.6)
    lg.printf("NASA Space Apps Challenge 2026", 0, H - 22, W, "center")
  else
    self:_drawBriefing()
  end
end

function Menu:_drawBriefing()
  local lg = love.graphics
  Theme.set(C.spaceDeep, 0.55); lg.rectangle("fill", 0, 0, W, H)
  local x, y, w, h = 190, 70, 900, 580
  Theme.panel(x, y, w, h, { cut = 24, fill = C.space, alpha = 0.96, lineWidth = 3 })
  Theme.outlinedText("MISSION BRIEFING", x, y + 22, w, "center", C.cyan, C.ink, Theme.font(34))
  lg.setFont(Theme.font(18)); Theme.set(C.white)
  lg.printf(Menu.INTRO, x + 60, y + 78, w - 120, "center")
  -- speaker: read the briefing aloud (English)
  local sp = self.speaker
  local mute = self.isDisabled and self.isDisabled("tts")
  Theme.circle(sp.x, sp.y, sp.r, mute and C.metalDark or C.cyanMid, 3)
  Icons.draw("speaker", sp.x, sp.y, 32, mute and C.metalShade or C.white)
  for i, s in ipairs(Menu.STEPS) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local bx, by = x + 50 + col * 410, y + 170 + row * 82
    Theme.panel(bx, by, 390, 70, { cut = 10, fill = C.spaceDeep, edge = C.cyanMid })
    Icons.draw(s[1], bx + 36, by + 35, 34, s[2])
    lg.setFont(Theme.font(15)); Theme.set(C.offWhite)
    lg.printf(s[3], bx + 66, by + 14, 310, "left")
  end
  lg.setFont(Theme.font(17)); Theme.set(C.cyanLight)
  lg.printf("Walk: arrows or WASD   Sprint: hold Shift   Use a machine: walk close + click (or E)   Follow the arrow!",
    x, y + 430, w, "center")
  Theme.panel(x + w / 2 - 190, y + 480, 380, 58, { cut = 14, fill = C.cyanMid, edge = C.cyan, lineWidth = 3 })
  Theme.outlinedText("CLICK TO BEGIN", x + w / 2 - 190, y + 494, 380, "center", C.cyan, C.ink,
    Theme.font(28))
end

return Menu
