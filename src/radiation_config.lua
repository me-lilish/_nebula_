--[[
  Radiation - configuration (src/radiation_system.lua)
  ====================================================
  [REAL-WORLD RELATIONSHIP] The Moon has no thick atmosphere or magnetic
  field, so solar storms reach the surface. Piling lunar soil (regolith)
  around a habitat blocks much of that radiation.
  [GAME RULE] The two-minute warning, storm length, nine shield units and
  nine sections are simplifications chosen for play.
]]

local config = {}

config.FIRST_WARNING_AT_SEC = 180   -- [GAME RULE] first warning 3 minutes in
config.WARNING_LEAD_SEC     = 120   -- [GAME RULE] two real minutes to prepare
config.STORM_DURATION_SEC   = 45    -- [GAME RULE]
config.STORM_INTERVAL_SEC   = 20 * 60 -- [GAME RULE] next warning after a storm ends

-- [GAME RULE] Regolith is represented by 9 shield units, one per section.
config.SHIELD_UNITS = 9
config.SECTIONS = {
  { id = "crew",       name = "Crew & sleep" },
  { id = "air",        name = "Air" },
  { id = "water",      name = "Water" },
  { id = "food",       name = "Food" },
  { id = "power",      name = "Power" },
  { id = "greenhouse", name = "Greenhouse" },
  { id = "waste",      name = "Waste" },
  { id = "entrance",   name = "Entrance" },
  { id = "storage",    name = "Storage" },
}

config.LOADER_UNITS_PER_USE = 3     -- [GAME RULE] regolith units loaded per click
config.LOADER_POWER_COST    = 2     -- [GAME RULE]
config.DEPLOY_POWER_COST    = 2     -- [GAME RULE] per Shield Control Panel click

-- [GAME RULE] Unshielded sections lose integrity during a storm. Crossing
-- the damage line breaks equipment there: salvage parts + a little dust.
config.SECTION_DAMAGE_PER_SEC = 2
config.SECTION_DAMAGE_LINE = 50
config.DAMAGE_SALVAGE_PARTS = 2
config.DAMAGE_CABIN_DUST = 5

return config
