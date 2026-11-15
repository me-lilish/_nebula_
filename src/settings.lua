-- Player settings kept between games (language, read aloud, sound).
-- Saved as a tiny text file in the LOVE save folder; safe if missing.
local Settings = { lang = "en", tts = false, mute = false }
local FILE = "settings.txt"

function Settings.load()
  local ok, text = pcall(function() return love.filesystem.read(FILE) end)
  if not ok or not text then return Settings end
  for k, v in text:gmatch("(%w+)=(%w+)") do
    if k == "lang" and (v == "en" or v == "ar") then Settings.lang = v
    elseif k == "tts" then Settings.tts = v == "1"
    elseif k == "mute" then Settings.mute = v == "1" end
  end
  return Settings
end

function Settings.save()
  local text = string.format("lang=%s\ntts=%s\nmute=%s\n", Settings.lang, Settings.tts and "1" or "0", Settings.mute and "1" or "0")
  pcall(function() love.filesystem.write(FILE, text) end)
end

return Settings
