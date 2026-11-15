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

local VW, VH = 1280, 720
local canvas
local scene, menu, room
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
  room = room or RoomScene.new({ campaign = true })
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
  love.window.setMode(VW, VH, { resizable = true, minwidth = 640, minheight = 360 })
  canvas = love.graphics.newCanvas(VW, VH)
  menu = Menu.new(startGame, function() love.event.quit() end)
end

function love.update(dt)
  dt = math.min(dt, 0.1) -- a dragged window must not skip seconds of simulation
  if mode == "debug" then scene:update(dt) return end
  if mode == "menu" then
    menu:update(dt, toVirtual(love.mouse.getPosition()))
  else
    room:update(dt)
  end
end

function love.draw()
  if mode == "debug" then scene:draw() return end
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 1)
  if mode == "menu" then menu:draw() else room:draw() end
  love.graphics.setCanvas()
  love.graphics.clear(0.03, 0.03, 0.08)
  local s, ox, oy = viewTransform()
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(canvas, ox, oy, 0, s, s)
end

function love.keypressed(key)
  if mode == "debug" then scene:keypressed(key) return end
  if mode == "menu" then
    menu:keypressed(key)
  elseif key == "escape" then
    menu.state = "menu"
    mode = "menu"
  else
    room:keypressed(key)
  end
end

function love.mousepressed(x, y, button)
  if mode == "debug" then return end
  local vx, vy = toVirtual(x, y)
  if mode == "menu" then menu:mousepressed(vx, vy, button) else room:mousepressed(vx, vy, button) end
end
