--[[
  Human needs subsystem
  =====================
  Pure Lua: no love.* calls, no input, no drawing.

  Owns Vulcan's health, sleep, hunger, bathroom timers and bladder. It does
  not own food, water or the emergency timer: src/life_support.lua calls
    human:update(dt, externalLossPerSec)  -- dust/radiation/hygiene effects
    human:eat()  human:useToilet()  human:startSleep()  human:wake()
    human:addToBladder(u)
  Health only reaches 0 through gradual losses; it never drops instantly.
]]

local defaultConfig = require("src.human_config")

local HumanSystem = {}
HumanSystem.__index = HumanSystem

local EPS = 1e-9

function HumanSystem.new(config)
  local self = setmetatable({ config = config or defaultConfig }, HumanSystem)
  self:reset()
  return self
end

function HumanSystem:reset()
  local c = self.config
  self.health = c.HEALTH_START
  self.isSleeping = false
  self.timeSinceFood = 0
  self.timeSinceToilet = 0
  self.timeSinceMeal = math.huge -- for "you just ate"
  self.bladder = 0               -- urine waiting for the Toilet (water units)
  self.elapsed = 0
  -- Sleep over the last game day: one bucket per real minute.
  self.sleepBuckets = {}
  self.bucketCount = math.floor(c.SLEEP_WINDOW_SEC / c.SLEEP_BUCKET_SEC + 0.5)
  for i = 1, self.bucketCount do self.sleepBuckets[i] = 0 end
  self.bucketIndex = 1
  self.bucketTime = 0
  self:_refresh()
end

------------------------------------------------------------------------------
-- Needs
------------------------------------------------------------------------------

function HumanSystem:sleepInLastDay()
  local total = 0
  for i = 1, self.bucketCount do total = total + self.sleepBuckets[i] end
  return total
end

-- Fatigue is judged once a full game day has passed.
function HumanSystem:isFatigued()
  local c = self.config
  return self.elapsed >= c.SLEEP_WINDOW_SEC - EPS and self:sleepInLastDay() < c.SLEEP_MIN_SEC - EPS
end

-- "ok" | "warning" | "danger"
function HumanSystem:hungerStatus()
  local c = self.config
  if self.timeSinceFood >= c.HUNGER_DANGER_SEC - EPS then return "danger" end
  if self.timeSinceFood >= c.HUNGER_WARNING_SEC - EPS then return "warning" end
  return "ok"
end

-- "ok" | "need" | "danger"
function HumanSystem:bathroomStatus()
  local c = self.config
  if self.timeSinceToilet >= c.BATHROOM_DANGER_SEC - EPS then return "danger" end
  if self.timeSinceToilet >= c.BATHROOM_NEED_SEC - EPS then return "need" end
  return "ok"
end

-- Health lost per second from Vulcan's own unmet needs.
function HumanSystem:needLossPerSec()
  local c = self.config
  local loss = 0
  if self:isFatigued() then loss = loss + c.FATIGUE_HEALTH_LOSS_PER_SEC end
  if self:hungerStatus() == "danger" then loss = loss + c.HUNGER_HEALTH_LOSS_PER_SEC end
  if self:bathroomStatus() == "danger" then loss = loss + c.BATHROOM_HEALTH_LOSS_PER_SEC end
  return loss
end

function HumanSystem:_refresh()
  local c = self.config
  self.health = math.max(0, math.min(c.HEALTH_MAX, self.health))
  if self.health <= EPS then
    self.healthStatus = "critical"
  elseif self.health < c.HEALTH_DANGER_BELOW then
    self.healthStatus = "danger"
  elseif self.health < c.HEALTH_CAUTION_BELOW then
    self.healthStatus = "caution"
  else
    self.healthStatus = "good"
  end
end

function HumanSystem:isCritical()
  return self.health <= EPS
end

------------------------------------------------------------------------------
-- Time step
------------------------------------------------------------------------------

-- externalLossPerSec: health loss from outside causes (dust, radiation,
-- hygiene), computed by the coordinator.
function HumanSystem:update(dt, externalLossPerSec)
  if dt <= 0 then return end
  local c = self.config
  self.elapsed = self.elapsed + dt
  self.timeSinceFood = self.timeSinceFood + dt
  self.timeSinceToilet = self.timeSinceToilet + dt
  self.timeSinceMeal = self.timeSinceMeal + dt

  -- Sleep buckets (rolling game day)
  if self.isSleeping then
    self.sleepBuckets[self.bucketIndex] = self.sleepBuckets[self.bucketIndex] + dt
  end
  self.bucketTime = self.bucketTime + dt
  while self.bucketTime >= c.SLEEP_BUCKET_SEC - EPS do
    self.bucketTime = math.max(0, self.bucketTime - c.SLEEP_BUCKET_SEC)
    self.bucketIndex = self.bucketIndex % self.bucketCount + 1
    self.sleepBuckets[self.bucketIndex] = 0
  end

  -- Health: gradual loss, or slow recovery when nothing is wrong
  local loss = self:needLossPerSec() + (externalLossPerSec or 0)
  if loss > 0 then
    self.health = self.health - loss * dt
  else
    self.health = self.health + c.HEALTH_REGEN_PER_SEC * dt
  end
  self:_refresh()
end

------------------------------------------------------------------------------
-- Actions (called by coordinator stations)
------------------------------------------------------------------------------

function HumanSystem:eat()
  self.timeSinceFood = 0
  self.timeSinceMeal = 0
end

-- Empties the bladder; returns the urine (water units) for the Toilet.
function HumanSystem:useToilet()
  local urine = self.bladder
  self.bladder = 0
  self.timeSinceToilet = 0
  return urine
end

function HumanSystem:addToBladder(amount)
  if amount > 0 then self.bladder = self.bladder + amount end
end

function HumanSystem:startSleep() self.isSleeping = true end
function HumanSystem:wake() self.isSleeping = false end

return HumanSystem
