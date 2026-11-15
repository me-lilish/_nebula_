--[[
  Human needs - configuration (src/human_system.lua)
  ==================================================
  [REAL-WORLD RELATIONSHIP] Astronauts need sleep, food and bathroom breaks;
  missing them makes people tired, weak and unwell.
  [GAME RULE] Every number below is a simplified game value, not medical
  advice. Times are REAL seconds; 1 real second = 10 game minutes.
]]

local config = {}

config.HEALTH_START = 100
config.HEALTH_MAX = 100
-- Health status: good >= 70, caution >= 40, danger > 0, critical at 0
config.HEALTH_CAUTION_BELOW = 70
config.HEALTH_DANGER_BELOW = 40

-- Sleep. [GAME RULE] Sleep is counted over the last 24 real minutes (one
-- game day) as 24 one-minute buckets, so a night that crosses midnight
-- still counts as one night.
config.SLEEP_TARGET_SEC = 8 * 6          -- 8 simulated hours
config.SLEEP_MIN_SEC = 6 * 6             -- below this -> fatigue
config.SLEEP_WINDOW_SEC = 24 * 6         -- rolling simulated day
config.SLEEP_BUCKET_SEC = 6
config.FATIGUE_HEALTH_LOSS_PER_SEC = 0.02

-- Hunger
config.HUNGER_WARNING_SEC = 10 * 6
config.HUNGER_DANGER_SEC = 15 * 6
config.HUNGER_HEALTH_LOSS_PER_SEC = 0.05

-- Bathroom
config.BATHROOM_NEED_SEC = 9 * 6
config.BATHROOM_DANGER_SEC = 14 * 6
config.BATHROOM_HEALTH_LOSS_PER_SEC = 0.03

-- Other health effects passed in by the coordinator
config.DUST_HEALTH_LOSS_PER_SEC = 0.01      -- Cabin Cleanliness at danger
config.HYGIENE_HEALTH_LOSS_PER_SEC = 0.01   -- toilet left full too long
config.RADIATION_HEALTH_LOSS_PER_SEC = 0.5  -- crew unshielded in a storm

-- Slow recovery when no need is unmet and nothing is hurting the crew
config.HEALTH_REGEN_PER_SEC = 0.02

return config
