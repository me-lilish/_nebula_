--[[
  Text-to-speech (always English)
  ===============================
  TTS.speak(text)  reads a sentence aloud now (the speaker button)
  TTS.auto(text)   reads it only when "Read aloud" is ON and it is new
  Backends:
    Windows : the built-in Windows voice (System.Speech) through one hidden
              PowerShell process that stays open (commands are streamed)
    Web     : the browser's speechSynthesis (the web page listens for lines
              printed with the "@@TTS@@" prefix, see tools/build_web.py)
    macOS   : say      Linux : espeak / spd-say (if installed)
  Text is cleaned (CO₂ -> C O 2) so the voice reads it nicely.
]]
local TTS = {}
TTS.enabled = false   -- automatic read-aloud
TTS.blocked = false   -- true while the game is in another language (voice is English only)
TTS.last = nil

-- what the voice should actually say
function TTS.clean(text)
  text = tostring(text or "")
  text = text:gsub("CO₂", "C O 2"):gsub("CO2", "C O 2"):gsub("O2", "O 2"):gsub("H2", "H 2")
  text = text:gsub("₂", "2"):gsub("[\r\n]+", " "):gsub("%s+", " ")
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local os_
local function osName()
  if not os_ then os_ = (love and love.system and love.system.getOS()) or "Unknown" end
  return os_
end

local pipe
local function windowsSpeak(text, queue)
  if pipe == nil then
    local ok, p = pcall(io.popen, 'powershell -NoProfile -NoLogo -WindowStyle Hidden -Command -', 'w')
    pipe = ok and p or false
    if pipe then
      pipe:write("Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Rate = 0\n")
    end
  end
  if not pipe then return false end
  local safe = text:gsub("'", "''")
  local ok = pcall(function()
    pipe:write((queue and "" or "$s.SpeakAsyncCancelAll(); ") .. "[void]$s.SpeakAsync('" .. safe .. "')\n")
    pipe:flush()
  end)
  if not ok then pipe = false end
  return ok
end

local function shellQuote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

-- Speak now (queue = true: after the current sentence instead of cutting
-- it off). Returns the backend used.
function TTS.speak(text, queue)
  if TTS.blocked then return nil end
  text = TTS.clean(text)
  if text == "" then return nil end
  TTS.lastSpoken = text
  local name = osName()
  if name == "Web" then
    print((queue and "@@TTSQ@@" or "@@TTS@@") .. text)
    return "web"
  elseif name == "Windows" then
    return windowsSpeak(text, queue) and "windows" or nil
  elseif name == "OS X" then
    os.execute("say " .. shellQuote(text) .. " &")
    return "mac"
  elseif name == "Linux" then
    os.execute("(espeak " .. shellQuote(text) .. " || spd-say " .. shellQuote(text) .. ") >/dev/null 2>&1 &")
    return "linux"
  end
  return nil
end

function TTS.auto(text, queue)
  if TTS.blocked or not TTS.enabled or not text or text == TTS.last then return end
  TTS.last = text
  TTS.speak(text, queue)
end

function TTS.setEnabled(on)
  TTS.enabled = on
  TTS.last = nil
end

function TTS.shutdown()
  if pipe then pcall(function() pipe:write("exit\n"); pipe:close() end) end
  pipe = nil
end

return TTS
