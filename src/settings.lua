-- Player settings kept between games (language, read aloud, sound).
-- Saved with src/store.lua (save folder + the browser's localStorage);
-- anything missing or broken falls back to the defaults.
local Store = require("src.store")
local Settings = { lang = "en", tts = false, mute = false }
local NAME = "settings"

function Settings.load()
  local text = Store.read(NAME)
  if not text then return Settings end
  for k, v in text:gmatch("(%w+)=(%w+)") do
    if k == "lang" and (v == "en" or v == "ar") then Settings.lang = v
    elseif k == "tts" then Settings.tts = v == "1"
    elseif k == "mute" then Settings.mute = v == "1" end
  end
  return Settings
end

function Settings.save()
  Store.write(NAME, string.format("lang=%s\ntts=%s\nmute=%s\n", Settings.lang, Settings.tts and "1" or "0", Settings.mute and "1" or "0"))
end

return Settings
