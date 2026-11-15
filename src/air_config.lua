--[[
  Habitat Air System - configuration
  ===================================
  Every number the air system uses lives in this one table so the game can be
  balanced later without touching the logic in air_system.lua.

  Labels used below:
    [REAL SCIENCE]  Based on real-world air-safety values. Keep these unless
                    the team decides otherwise after discussion.
    [GAME RULE]     Simplified or invented for fun and playability. Change
                    these freely while balancing.

  Units: gas levels are percent of cabin air (%). Time is in seconds of
  game time. "Power" is an abstract energy unit (0..POWER_MAX).
]]

local config = {}

------------------------------------------------------------------------------
-- Starting atmosphere
------------------------------------------------------------------------------
-- [REAL SCIENCE] Earth's air is about 21% oxygen and about 0.04% CO2.
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
-- [REAL SCIENCE] 19.5% is the common workplace "oxygen-deficient" limit and
-- 23.5% the "oxygen-enriched" (fire-risk) limit. 21% is normal air.
-- [REAL SCIENCE] Spacecraft keep CO2 far below 1%; around 0.5% astronauts can
-- get headaches, and higher levels become dangerous.
-- The exact cut-offs below are the project's agreed values.
--
-- Ranges are continuous so values like 20.45% are never "between" statuses:
--   O2  good     : 20.5 <= O2 <= 21.5
--   O2  caution  : 19.5 <= O2 < 20.5   or  21.5 < O2 <= 23.5
--   O2  danger   : 18.0 <= O2 < 19.5   or  O2 > 23.5 (see note)
--   O2  critical : O2 < 18.0
--   CO2 good     : CO2 < 0.5
--   CO2 caution  : 0.5 <= CO2 <= 0.7
--   CO2 danger   : 0.7 < CO2 <= 1.0
--   CO2 critical : CO2 > 1.0
-- NOTE: the brief does not say what happens above 23.5% O2. We treat it as
-- DANGER (fire risk) but never critical. Flagged for team discussion.
config.O2_GOOD_MIN        = 20.5
config.O2_GOOD_MAX        = 21.5
config.O2_CAUTION_LOW_MIN = 19.5
config.O2_CAUTION_HIGH_MAX = 23.5
config.O2_DANGER_LOW_MIN  = 18.0   -- below this is critical

config.CO2_CAUTION_MIN = 0.5
config.CO2_CAUTION_MAX = 0.7
config.CO2_DANGER_MAX  = 1.0       -- above this is critical

-- [GAME RULE] Seconds the air may stay critical before the mission fails.
config.CRITICAL_TIME_LIMIT = 30.0

------------------------------------------------------------------------------
-- Air-quality score (0..100). Display only; the thresholds above decide status.
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
-- Astronaut breathing
------------------------------------------------------------------------------
-- [GAME RULE] Real people would take hours to change a habitat's air this
-- much. These rates are sped up so a problem appears in about a minute.
config.ASTRONAUT_O2_USE_PER_SEC  = 0.05  -- 21% -> 18% in ~60 s if ignored
config.ASTRONAUT_CO2_MAKE_PER_SEC = 0.01 -- 0.04% -> 1.0% in ~96 s if ignored

------------------------------------------------------------------------------
-- Power
------------------------------------------------------------------------------
-- [GAME RULE]
config.POWER_START = 100
config.POWER_MAX   = 100
config.POWER_RECHARGE_PER_SEC = 1.0  -- e.g. solar panels

------------------------------------------------------------------------------
-- Oxygen generator / tank (one press = one boost)
------------------------------------------------------------------------------
-- [REAL SCIENCE idea] The ISS makes oxygen by splitting water with
-- electricity and also stores oxygen in tanks.
-- [GAME RULE] numbers:
config.O2_GEN_BOOST_PERCENT = 1.0  -- O2 added per use
config.O2_GEN_POWER_COST    = 10   -- power used per use
config.O2_GEN_START_CANISTERS = 6  -- limited resource; one used per press

------------------------------------------------------------------------------
-- CO2 scrubber (one press = one scrub)
------------------------------------------------------------------------------
-- [REAL SCIENCE idea] Spacecraft remove CO2 with filters/scrubbers that fill
-- up and need power.
-- [GAME RULE] numbers:
config.SCRUBBER_REDUCE_PERCENT = 0.3  -- CO2 removed per use
config.SCRUBBER_POWER_COST     = 8
config.SCRUBBER_COOLDOWN_SEC   = 5.0  -- wait between uses
config.SCRUBBER_FILTER_USES    = 8    -- filter capacity; 0 = filter full

------------------------------------------------------------------------------
-- Farm module (passive bonus)
------------------------------------------------------------------------------
-- [REAL SCIENCE idea] Plants take in CO2 and give off O2 when they have
-- light and water. NASA grows plants on the ISS (the Veggie experiment).
-- [GAME RULE] The bonus is deliberately SMALLER than what the astronaut
-- breathes, so the farm slows problems down but can never fix an emergency
-- on its own. Tests check this.
config.FARM_O2_MAKE_PER_SEC   = 0.01
config.FARM_CO2_REMOVE_PER_SEC = 0.003
config.FARM_POWER_USE_PER_SEC = 0.3   -- grow light needs power

return config
