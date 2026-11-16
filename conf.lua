-- LOVE configuration (runs before the game starts).
function love.conf(t)
  t.identity = "junior_astronaut_mission"
  t.window.title = "Space Mission - Junior Astronaut Trainer"
  t.window.width, t.window.height = 1280, 720
  -- The game never uses gamepads. Browsers without the Gamepad API (many
  -- iPhone in-app browsers) would otherwise stop LOVE from starting at all.
  t.modules.joystick = false
  t.modules.physics = false
  t.modules.video = false
  -- The web page passes --noaudio when the browser cannot play sound, so the
  -- game starts silently instead of failing to open an audio device.
  for _, a in ipairs(arg or {}) do
    if a == "--noaudio" then t.modules.audio = false end
  end
end
