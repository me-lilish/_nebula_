--[[
  Dust / Trace Contaminant Control - configuration
  ================================================
  Numbers for src/dust_system.lua. In the life-support schematic, dust is the
  particulate part of "Trace Contaminant Control". The emergency timer lives
  in src/life_support_config.lua.

  Labels:
    [REAL-WORLD RELATIONSHIP]  How things really connect.
    [GAME RULE]                A simplified number chosen for play. Not a
                               medical or engineering limit.

  Real-world basis:
    - Moon and Mars dust is fine and sharp and clings to spacesuits
      (Apollo astronauts carried lots of it into the lunar module).
    - Suits should be cleaned before entering the cabin.
    - Dust inside a cabin can irritate eyes, nose and lungs and can clog or
      scratch equipment. Cabin air filters catch it.

  Units: dust is a made-up 0-100 scale. Cabin Cleanliness = 100 - cabinDust.
  Dust comes ONLY from a dirty airlock entry, explicit dust events or
  machinery damage (radiation). Ordinary crew life makes no lunar dust.
  Dust NEVER changes O2 or CO2 and never uses the O2/CO2 air-quality score.
]]

local config = {}

-- [GAME RULE] Scale and starting values (0..100 each)
config.MIN = 0
config.MAX = 100
config.START_SUIT_DUST  = 0
config.START_CABIN_DUST = 0

------------------------------------------------------------------------------
-- Status thresholds  [GAME RULE]
-- dustCleanliness = 100 - cabinDust
--   suit  clean   : suitDust < 30
--   suit  caution : 30 <= suitDust < 60
--   suit  danger  : suitDust >= 60          (suit dust is never critical)
--   cabin clean   : cleanliness > 70
--   cabin caution : 40 < cleanliness <= 70  (cabinDust 30 -> 70 = caution)
--   cabin danger  : 0 < cleanliness <= 40   (cabinDust 60 -> 40 = danger,
--                                            health/equipment warning)
--   cabin critical: cleanliness <= 0        (cabinDust reaches 100)
-- Overall dustStatus is the worse of suit and cabin.
------------------------------------------------------------------------------
config.SUIT_CAUTION_MIN = 30
config.SUIT_DANGER_MIN  = 60
config.CLEANLINESS_CLEAN_ABOVE  = 70  -- above this is clean
config.CLEANLINESS_DANGER_AT    = 40  -- at or below this is danger; 41..70 caution
config.CLEANLINESS_CRITICAL_AT  = 0   -- at or below this is critical

------------------------------------------------------------------------------
-- Airlock flow
-- [REAL-WORLD RELATIONSHIP] Dust on a suit gets carried inside if the suit is
-- not cleaned before entering.
-- [GAME RULE] Vulcan starts in the airlock after an EVA with this much suit
-- dust. Entering with a dirty suit adds the suit's whole dust amount to
-- cabinDust, once (see DustSystem:enterCabin).
------------------------------------------------------------------------------
config.EVA_SUIT_DUST = 60

------------------------------------------------------------------------------
-- Suit Dust-Off Station: cleanSuit()
-- [REAL-WORLD RELATIONSHIP] Brushing, vacuuming and electrostatic (static
-- electricity) dust removal are real suit-cleaning ideas.
------------------------------------------------------------------------------
config.SUIT_CLEAN_AMOUNT     = 100 -- [GAME RULE] one cycle = clean suit
config.SUIT_CLEAN_POWER_COST = 0   -- [GAME RULE] free (raise to make it use power)

------------------------------------------------------------------------------
-- Trace Air Cleaner (cabin particulate filter): runCabinDustFilter()
-- [REAL-WORLD RELATIONSHIP] Cabin air passes through fine particle filters
-- that catch dust; filters fill up and must be replaced.
------------------------------------------------------------------------------
config.FILTER_CLEAN_AMOUNT = 100 -- [GAME RULE] one cycle = clean cabin
config.FILTER_POWER_COST   = 3   -- [GAME RULE] % battery, from the shared battery
config.FILTER_USES         = 10  -- [GAME RULE] filter life; 0 = filter full

return config
