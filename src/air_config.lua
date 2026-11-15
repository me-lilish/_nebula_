--[[
  Cabin Air (O2 / CO2) - configuration
  ====================================
  Numbers for the cabin-atmosphere subsystem (src/air_system.lua).
  Machines, power and the emergency timer live in src/life_support_config.lua.

  Labels:
    [REAL-WORLD RELATIONSHIP]  How things really connect (what goes up or down).
    [GAME RULE]                A simplified number chosen for play. These are NOT
                               NASA medical or engineering limits.

  Units: gas levels are percent of cabin air (%). Time is game seconds.
]]

local config = {}

------------------------------------------------------------------------------
-- Starting atmosphere
------------------------------------------------------------------------------
-- [REAL-WORLD RELATIONSHIP] Earth-like cabin air is about 21% oxygen and
-- about 0.04% CO2, so the cabin starts there.
config.START_O2_PERCENT  = 21.0
config.START_CO2_PERCENT = 0.04

-- [GAME RULE] Hard limits so numbers never run away (not a safety rule).
config.O2_MIN_PERCENT  = 0.0
config.O2_MAX_PERCENT  = 30.0
config.CO2_MIN_PERCENT = 0.0
config.CO2_MAX_PERCENT = 5.0

------------------------------------------------------------------------------
-- Status thresholds (authoritative - these decide good/caution/danger/critical)
------------------------------------------------------------------------------
-- [GAME RULE] The project's agreed cut-offs. 19.5% / 23.5% O2 echo common
-- workplace air-safety guidance and low CO2 echoes spacecraft practice, but
-- these are simplified game values, not NASA medical limits.
--
-- Ranges are continuous so values like 20.45% are never "between" statuses:
--   O2  good     : 20.5 <= O2 <= 21.5
--   O2  caution  : 19.5 <= O2 < 20.5   or  21.5 < O2 <= 23.5
--   O2  danger   : 18.0 <= O2 < 19.5   or  O2 > 23.5 (too much O2 = fire risk)
--   O2  critical : O2 < 18.0
--   CO2 good     : CO2 < 0.5
--   CO2 caution  : 0.5 <= CO2 <= 0.7
--   CO2 danger   : 0.7 < CO2 <= 1.0
--   CO2 critical : CO2 > 1.0
config.O2_GOOD_MIN         = 20.5
config.O2_GOOD_MAX         = 21.5
config.O2_CAUTION_LOW_MIN  = 19.5
config.O2_CAUTION_HIGH_MAX = 23.5
config.O2_DANGER_LOW_MIN   = 18.0   -- below this is critical

config.CO2_CAUTION_MIN = 0.5
config.CO2_CAUTION_MAX = 0.7
config.CO2_DANGER_MAX  = 1.0        -- above this is critical

------------------------------------------------------------------------------
-- Air-quality score (0..100). Display only; the thresholds above decide status.
-- Used ONLY for O2/CO2 - dust has its own Cabin Cleanliness value.
------------------------------------------------------------------------------
-- [GAME RULE] score = 100
--              - O2_SCORE_WEIGHT  * |O2 - 21|
--              - CO2_SCORE_WEIGHT * max(0, CO2 - 0.04)
--            then clamped to 0..100.
config.SCORE_IDEAL_O2   = 21.0
config.SCORE_BASE_CO2   = 0.04
config.O2_SCORE_WEIGHT  = 20.0  -- points lost per 1% away from 21% O2
config.CO2_SCORE_WEIGHT = 60.0  -- points lost per 1% CO2 above 0.04%

------------------------------------------------------------------------------
-- Crew breathing
------------------------------------------------------------------------------
-- [REAL-WORLD RELATIONSHIP] Breathing uses oxygen and adds carbon dioxide.
-- [GAME RULE] Sped up so the player must act every minute or so
-- (1 real minute = 1 game hour).
config.ASTRONAUT_O2_USE_PER_SEC   = 0.02  -- 21% -> 18% in 150 s if ignored
config.ASTRONAUT_CO2_MAKE_PER_SEC = 0.004 -- 0.04% -> 1.0% in 240 s if ignored

return config
