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
  -- stars, kept away from the title and the buttons
  local rng = love.math.newRandomGenerator(42)
  self.stars = {}
  local tries = 0
  while #self.stars < 70 and tries < 4000 do
    tries = tries + 1
    local x, y = rng:random(20, W - 20), rng:random(15, H - 15)
    local hitTitle = x > 290 and x < 990 and y > 20 and y < 290
    local hitButtons = x > 400 and x < 880 and y > 410 and y < 630
    if not hitTitle and not hitButtons then
      self.stars[#self.stars + 1] = { x = x, y = y, s = rng:random(10, 22), frame = rng:random(1, 7),
        timer = rng:random() * 0.5, speed = 0.08 + rng:random() * 0.12 }
    end
  end
  return self
end

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

function Menu:update(dt, mx, my)
  self.t = self.t + dt
  self.hover = (self.state == "menu") and self:hit(mx or -1, my or -1) or nil
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

function Menu:mousepressed(x, y, button)
  if button ~= 1 then return end
  if self.state == "briefing" then
    if self.onStart then self.onStart() end
    return
  end
  local id = self:hit(x, y)
  if id == "start" then self.state = "briefing"
  elseif id == "abort" and self.onQuit then self.onQuit() end
end

function Menu:keypressed(key)
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
      end
    end
    lg.setFont(Theme.font(14)); Theme.set(C.cyanLight, 0.6)
    lg.printf("NASA Space Apps Challenge 2026", 0, H - 30, W, "center")
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
  lg.printf("Welcome to the Moon base, Vulcan! You just came back from a moonwalk. "
    .. "Keep the habitat alive: every machine is connected, just like on a real space station.",
    x + 60, y + 78, w - 120, "center")
  local steps = {
    { "clean", C.cyanLight, "Clean your dusty suit at the Suit Dust-Off before you go inside." },
    { "air", C.oxygen, "Make oxygen and clean the CO2 so the crew can breathe." },
    { "water", C.water, "Recycle used water into clean drinking water." },
    { "power", C.power, "Aim the solar panels so the batteries stay charged." },
    { "food", C.food, "Grow, harvest and eat food. Sleep and use the toilet too!" },
    { "radiation", C.caution, "When a solar storm warning comes, pile Moon soil as shields." },
  }
  for i, s in ipairs(steps) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local bx, by = x + 50 + col * 410, y + 170 + row * 82
    Theme.panel(bx, by, 390, 70, { cut = 10, fill = C.spaceDeep, edge = C.cyanMid })
    Icons.draw(s[1], bx + 36, by + 35, 34, s[2])
    lg.setFont(Theme.font(15)); Theme.set(C.offWhite)
    lg.printf(s[3], bx + 66, by + 14, 310, "left")
  end
  lg.setFont(Theme.font(17)); Theme.set(C.cyanLight)
  lg.printf("Walk: arrow keys or WASD      Use a machine: walk close + click it      Follow the arrow!",
    x, y + 430, w, "center")
  Theme.panel(x + w / 2 - 190, y + 480, 380, 58, { cut = 14, fill = C.cyanMid, edge = C.cyan, lineWidth = 3 })
  Theme.outlinedText("CLICK TO BEGIN", x + w / 2 - 190, y + 494, 380, "center", C.cyan, C.ink,
    Theme.font(28))
end

return Menu
