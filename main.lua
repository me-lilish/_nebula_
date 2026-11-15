-- Nebula: Junior Astronaut Mission Trainer - Love2D entry point.
-- Run from the repository root with:  love .
-- For now this only loads the Habitat Air System debug scene.

local DebugScene = require("src.debug_scene")
local scene

function love.load()
  love.window.setTitle("Nebula - Habitat Air System (debug)")
  love.window.setMode(800, 520)
  scene = DebugScene.new()
end

function love.update(dt)
  -- Cap dt so a window drag/pause doesn't skip seconds of simulation at once.
  scene:update(math.min(dt, 0.1))
end

function love.draw()
  scene:draw()
end

function love.keypressed(key)
  scene:keypressed(key)
end
