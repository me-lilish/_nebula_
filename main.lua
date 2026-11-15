-- Nebula: Junior Astronaut Mission Trainer - Love2D entry point.
-- Run from the repository root with:
--   love .          main menu -> briefing -> the Moon habitat
--   love . debug    the life-support debug readout
--
-- The game draws to a fixed 1280 x 720 virtual screen that is scaled to fit
-- any window size (the window is resizable).

local RoomScene = require("src.room_scene")
local DebugScene = require("src.debug_scene")
local Menu = require("src.menu_scene")
local Audio = require("src.audio")
local Touch = require("src.ui.touch")

local VW, VH = 1280, 720
local canvas
local scene, menu, room, audio
local touch = Touch.new()
local mode = "menu" -- "menu" | "game" | "debug"

local function viewTransform()
  local ww, wh = love.graphics.getDimensions()
  local s = math.min(ww / VW, wh / VH)
  return s, (ww - VW * s) / 2, (wh - VH * s) / 2
end

local function toVirtual(x, y)
  local s, ox, oy = viewTransform()
  return (x - ox) / s, (y - oy) / s
end

local function startGame()
  room = room or RoomScene.new({ campaign = true, puzzles = true,
    isDown = function(k) return love.keyboard.isDown(k) or touch:isDown(k) end })
  room:reset()
  mode = "game"
end

function love.load(args)
  love.graphics.setDefaultFilter("linear", "linear")
  local debug = false
  for _, a in ipairs(args or {}) do if a == "debug" then debug = true end end
  if debug then
    love.window.setTitle("Nebula - life support (debug)")
    love.window.setMode(1000, 640)
    scene = DebugScene.new()
    mode = "debug"
    return
  end
  love.window.setTitle("Space Mission - Junior Astronaut Trainer")
  if love.system.getOS() == "Web" then
    -- in a browser the page scales the 1280 x 720 canvas to fit the screen
    love.window.setMode(VW, VH, { resizable = false })
  else
    love.window.setMode(VW, VH, { resizable = true, minwidth = 640, minheight = 360 })
  end
  local ok, icon = pcall(love.image.newImageData, "assets/icon.png")
  if ok then love.window.setIcon(icon) end
  canvas = love.graphics.newCanvas(VW, VH)
  -- in a web browser there is nothing to quit to: Abort just stays on the menu
  local onWeb = love.system.getOS() == "Web"
  menu = Menu.new(startGame, function() if not onWeb then love.event.quit() end end)
  audio = Audio.new()
  menu.sound = function(name) audio:play(name) end
end

function love.update(dt)
  dt = math.min(dt, 0.1) -- a dragged window must not skip seconds of simulation
  if mode == "debug" then scene:update(dt) return end
  if mode == "menu" then
    menu:update(dt, toVirtual(love.mouse.getPosition()))
    audio:updateMusic(dt, "ambient")
    audio:silenceWorld(dt)
  else
    room:update(dt)
    audio:update(dt, room)
  end
end

function love.draw()
  if mode == "debug" then scene:draw() return end
  love.graphics.setCanvas({ canvas, stencil = true })
  love.graphics.clear(0, 0, 0, 1)
  if mode == "menu" then menu:draw() else room:draw(); touch:draw(room.puzzles:isOpen()) end
  love.graphics.setCanvas()
  love.graphics.clear(0.03, 0.03, 0.08)
  local s, ox, oy = viewTransform()
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(canvas, ox, oy, 0, s, s)
end

function love.keypressed(key)
  if mode == "debug" then scene:keypressed(key) return end
  if key == "m" then audio:toggleMute() return end
  if mode == "menu" then
    menu:keypressed(key)
  elseif key == "escape" and not room.puzzles:isOpen() then
    audio:play("sfx_click")
    menu.state = "menu"
    mode = "menu"
    touch.stick = nil
  else
    room:keypressed(key)
  end
end

-- Touches arrive as touch events; the copies the system also sends as mouse
-- events (istouch = true) are ignored so nothing happens twice.
function love.mousereleased(x, y, button, istouch)
  if mode ~= "game" or istouch then return end
  local vx, vy = toVirtual(x, y)
  room:mousereleased(vx, vy, button)
end

function love.mousemoved(x, y, dx, dy, istouch)
  if mode ~= "game" or istouch then return end
  local vx, vy = toVirtual(x, y)
  room:mousemoved(vx, vy)
end

function love.mousepressed(x, y, button, istouch)
  if mode == "debug" or istouch then return end
  local vx, vy = toVirtual(x, y)
  if mode == "menu" then menu:mousepressed(vx, vy, button) else room:mousepressed(vx, vy, button) end
end

------------------------------------------------------------------------------
-- Touch screens (phones / tablets, also in the browser build)
------------------------------------------------------------------------------
local puzzleTouch = nil -- the finger that is playing a mini-game

function love.touchpressed(id, x, y)
  if mode == "debug" then return end
  touch.enabled = true
  require("src.ui.hud").touchMode = true
  local vx, vy = toVirtual(x, y)
  if mode == "menu" then menu:mousepressed(vx, vy, 1) return end
  if room.puzzles:isOpen() then
    if Touch.hit(Touch.CLOSE, vx, vy) then room:keypressed("escape") return end
    puzzleTouch = id
    room:mousemoved(vx, vy)
    room:mousepressed(vx, vy, 1)
    return
  end
  local action = touch:press(id, vx, vy)
  if action == "use" then room:keypressed("e")
  elseif action == "tab" then room:keypressed("tab")
  elseif action == "menu" then love.keypressed("escape")
  elseif action == nil then room:mousepressed(vx, vy, 1) end
end

function love.touchmoved(id, x, y)
  if mode ~= "game" then return end
  local vx, vy = toVirtual(x, y)
  if puzzleTouch == id then room:mousemoved(vx, vy) else touch:move(id, vx, vy) end
end

function love.touchreleased(id, x, y)
  if mode ~= "game" then return end
  local vx, vy = toVirtual(x, y)
  if puzzleTouch == id then puzzleTouch = nil; room:mousereleased(vx, vy, 1) end
  touch:release(id)
end
