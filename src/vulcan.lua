--[[
  Vulcan - the player's astronaut
  ===============================
  Movement: arrow keys or WASD (unchanged).
  Art: the team's sprites (assets/vulcan_idle.png + 3 walk frames), built by
  tools/build_assets.py. The walk frames face left; they are mirrored when
  Vulcan walks right. If the images are missing, a simple drawn astronaut is
  used instead.

  The room uses: Vulcan.new(x, y), vulcan:update(dt, isDown, bounds),
  vulcan:draw(), vulcan.x / vulcan.y (feet-circle centre), vulcan.radius
]]

local Vulcan = {}
Vulcan.__index = Vulcan

Vulcan.SPEED = 220        -- world pixels per second
Vulcan.RADIUS = 22        -- collision circle around the feet
Vulcan.HEIGHT = 96        -- drawn sprite height
Vulcan.FRAME_TIME = 0.14  -- seconds per walk frame (at walking speed)
Vulcan.SPRINT = 1.7       -- Shift: sprint speed multiplier

function Vulcan.new(x, y)
  return setmetatable({ x = x, y = y, radius = Vulcan.RADIUS, facing = -1, moving = false, anim = 0 }, Vulcan)
end

-- isDown(key) -> boolean (love.keyboard.isDown in the game, a stub in tests)
-- speedMul (optional): < 1 when Vulcan is exhausted (no sprinting then).
-- The walk animation advances with the distance actually covered (see
-- Vulcan:stepAnimation), so legs never slide or "moonwalk" into walls.
function Vulcan:update(dt, isDown, bounds, speedMul)
  local dx, dy = 0, 0
  if isDown("left") or isDown("a") then dx = dx - 1 end
  if isDown("right") or isDown("d") then dx = dx + 1 end
  if isDown("up") or isDown("w") then dy = dy - 1 end
  if isDown("down") or isDown("s") then dy = dy + 1 end
  if dx ~= 0 and dy ~= 0 then dx, dy = dx * 0.7071, dy * 0.7071 end

  self.wantsToMove = dx ~= 0 or dy ~= 0
  if dx < 0 then self.facing = -1 elseif dx > 0 then self.facing = 1 end
  local tired = (speedMul or 1) < 1
  self.sprinting = self.wantsToMove and not tired and (isDown("lshift") or isDown("rshift"))
  self.prevX, self.prevY = self.x, self.y

  local speed = Vulcan.SPEED * (speedMul or 1) * (self.sprinting and Vulcan.SPRINT or 1)
  self.x = self.x + dx * speed * dt
  self.y = self.y + dy * speed * dt
  if bounds then
    local r = self.radius
    self.x = math.max(bounds.left + r, math.min(bounds.right - r, self.x))
    self.y = math.max(bounds.top + r, math.min(bounds.bottom - r, self.y))
  end
  self:stepAnimation()
end

-- Call again after the caller moved Vulcan back from a wall: the legs only
-- move as far as the body really travelled.
function Vulcan:stepAnimation()
  local d = math.sqrt((self.x - (self.prevX or self.x)) ^ 2 + (self.y - (self.prevY or self.y)) ^ 2)
  self.moving = d > 0.01
  if self.moving then
    self.anim = (self.baseAnim or self.anim) + d / Vulcan.SPEED
  else
    self.anim = 0
  end
  self.baseAnim = nil
end

------------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------------

local images -- loaded on first draw: { idle = Image, walk = { Image, Image, Image } } or false

local function loadImages()
  if images ~= nil then return images end
  local A = require("src.assets")
  local idle, w1, w2, w3 = A.image("assets/vulcan_idle.png"), A.image("assets/vulcan_walk1.png"),
    A.image("assets/vulcan_walk2.png"), A.image("assets/vulcan_walk3.png")
  images = (idle and w1 and w2 and w3) and { idle = idle, walk = { w1, w2, w3 } } or false
  return images
end

-- Walk cycle 1-2-3-2
local CYCLE = { 1, 2, 3, 2 }

function Vulcan:draw()
  local lg = love.graphics
  local imgs = loadImages()
  -- soft shadow on the floor
  lg.setColor(0, 0, 0, 0.25)
  lg.ellipse("fill", self.x, self.y + self.radius - 4, self.radius * 1.1, 7)
  if imgs then
    local img = imgs.idle
    if self.moving then
      img = imgs.walk[CYCLE[math.floor(self.anim / Vulcan.FRAME_TIME) % #CYCLE + 1]]
    end
    local s = Vulcan.HEIGHT / img:getHeight()
    local sx = (self.moving and self.facing > 0) and -s or s
    lg.setColor(1, 1, 1)
    -- feet at the bottom of the collision circle
    lg.draw(img, self.x, self.y + self.radius, 0, sx, s, img:getWidth() / 2, img:getHeight())
    return
  end
  -- Fallback: simple drawn astronaut
  local x, y, r = self.x, self.y, self.radius
  lg.setColor(0.95, 0.95, 1.0); lg.circle("fill", x, y, r)
  lg.setColor(0.35, 0.55, 0.85); lg.ellipse("fill", x, y - 4, r * 0.65, r * 0.45)
  lg.setColor(0.2, 0.2, 0.3); lg.circle("line", x, y, r)
end

return Vulcan
