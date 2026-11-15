-- Runs every test file. From the repository root:  lua tests/run_all.lua
local files = {
  "tests/test_air_system.lua",
  "tests/test_dust_system.lua",
  "tests/test_human.lua",
  "tests/test_radiation.lua",
  "tests/test_life_support.lua",
  "tests/test_mission.lua",
  "tests/test_rebuild.lua",
  "tests/test_room.lua",
  "tests/test_guide.lua",
  "tests/test_progression.lua",
  "tests/test_walkthrough.lua",
}
-- Use the same Lua that is running this script.
local i, lua = 0, nil
while arg[i] do lua = arg[i]; i = i - 1 end
local allOk = true
for _, f in ipairs(files) do
  print("== " .. f)
  io.stdout:flush()
  local ok = os.execute('"' .. lua .. '" ' .. f)
  if ok ~= 0 and ok ~= true then allOk = false end
end
print(allOk and "\nALL TEST FILES PASSED" or "\nSOME TESTS FAILED")
os.exit(allOk and 0 or 1)
