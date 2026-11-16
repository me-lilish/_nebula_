--[[
  Languages: English (built in) and Arabic
  ========================================
  All game text is written in English. When Arabic is chosen, every string
  drawn with love.graphics.print / printf is:
    1. translated  - exact match in src/i18n_ar.lua, or a template with
                     numbers ("Loaded %d units ..." -> "{1} ...")
    2. shaped      - Arabic letters take their joined forms (initial,
                     medial, final, isolated; lam-alef ligatures), because
                     LOVE does not join Arabic letters by itself
    3. ordered     - right-to-left (numbers and Latin words keep their order)
    4. drawn with an Arabic font (DejaVu Sans, assets/fonts) and wrapped
       line by line in reading order.

  Pure Lua except I18n.install() (hooks love.graphics), so tests can check
  translations and shaping without Love2D.
]]
local I18n = {}

I18n.lang = "en"
I18n.LANGS = { "en", "ar" }
I18n.NAMES = { en = "English", ar = "العربية" }

------------------------------------------------------------------------------
-- UTF-8 helpers
------------------------------------------------------------------------------
local function decode(s)
  local cps, i, n = {}, 1, #s
  while i <= n do
    local c = s:byte(i)
    local cp, len
    if c < 0x80 then cp, len = c, 1
    elseif c < 0xE0 then cp, len = (c - 0xC0) * 64 + (s:byte(i + 1) - 0x80), 2
    elseif c < 0xF0 then cp, len = (c - 0xE0) * 4096 + (s:byte(i + 1) - 0x80) * 64 + (s:byte(i + 2) - 0x80), 3
    else cp, len = (c - 0xF0) * 262144 + (s:byte(i + 1) - 0x80) * 4096 + (s:byte(i + 2) - 0x80) * 64 + (s:byte(i + 3) - 0x80), 4 end
    cps[#cps + 1] = cp
    i = i + len
  end
  return cps
end

local function encode1(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
    0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

local function encode(cps)
  local t = {}
  for i, cp in ipairs(cps) do t[i] = encode1(cp) end
  return table.concat(t)
end
I18n.decode, I18n.encode = decode, encode

function I18n.hasArabic(s)
  -- Arabic letters start with the UTF-8 lead bytes 0xD8-0xDB (U+0600-U+06FF)
  -- or 0xEF 0xBA/0xBB (presentation forms)
  return s:find("[\216-\219]") ~= nil or s:find("\239[\186\187]") ~= nil
end

------------------------------------------------------------------------------
-- Arabic letter shaping
--   FORMS[cp] = { isolated, final, initial, medial }  (initial/medial nil for
--   letters that never join to the next letter)
------------------------------------------------------------------------------
local FORMS = {
  [0x0621] = { 0xFE80 },
  [0x0622] = { 0xFE81, 0xFE82 }, [0x0623] = { 0xFE83, 0xFE84 }, [0x0624] = { 0xFE85, 0xFE86 },
  [0x0625] = { 0xFE87, 0xFE88 }, [0x0626] = { 0xFE89, 0xFE8A, 0xFE8B, 0xFE8C },
  [0x0627] = { 0xFE8D, 0xFE8E }, [0x0628] = { 0xFE8F, 0xFE90, 0xFE91, 0xFE92 },
  [0x0629] = { 0xFE93, 0xFE94 }, [0x062A] = { 0xFE95, 0xFE96, 0xFE97, 0xFE98 },
  [0x062B] = { 0xFE99, 0xFE9A, 0xFE9B, 0xFE9C }, [0x062C] = { 0xFE9D, 0xFE9E, 0xFE9F, 0xFEA0 },
  [0x062D] = { 0xFEA1, 0xFEA2, 0xFEA3, 0xFEA4 }, [0x062E] = { 0xFEA5, 0xFEA6, 0xFEA7, 0xFEA8 },
  [0x062F] = { 0xFEA9, 0xFEAA }, [0x0630] = { 0xFEAB, 0xFEAC }, [0x0631] = { 0xFEAD, 0xFEAE },
  [0x0632] = { 0xFEAF, 0xFEB0 }, [0x0633] = { 0xFEB1, 0xFEB2, 0xFEB3, 0xFEB4 },
  [0x0634] = { 0xFEB5, 0xFEB6, 0xFEB7, 0xFEB8 }, [0x0635] = { 0xFEB9, 0xFEBA, 0xFEBB, 0xFEBC },
  [0x0636] = { 0xFEBD, 0xFEBE, 0xFEBF, 0xFEC0 }, [0x0637] = { 0xFEC1, 0xFEC2, 0xFEC3, 0xFEC4 },
  [0x0638] = { 0xFEC5, 0xFEC6, 0xFEC7, 0xFEC8 }, [0x0639] = { 0xFEC9, 0xFECA, 0xFECB, 0xFECC },
  [0x063A] = { 0xFECD, 0xFECE, 0xFECF, 0xFED0 }, [0x0641] = { 0xFED1, 0xFED2, 0xFED3, 0xFED4 },
  [0x0642] = { 0xFED5, 0xFED6, 0xFED7, 0xFED8 }, [0x0643] = { 0xFED9, 0xFEDA, 0xFEDB, 0xFEDC },
  [0x0644] = { 0xFEDD, 0xFEDE, 0xFEDF, 0xFEE0 }, [0x0645] = { 0xFEE1, 0xFEE2, 0xFEE3, 0xFEE4 },
  [0x0646] = { 0xFEE5, 0xFEE6, 0xFEE7, 0xFEE8 }, [0x0647] = { 0xFEE9, 0xFEEA, 0xFEEB, 0xFEEC },
  [0x0648] = { 0xFEED, 0xFEEE }, [0x0649] = { 0xFEEF, 0xFEF0 },
  [0x064A] = { 0xFEF1, 0xFEF2, 0xFEF3, 0xFEF4 },
}
local TATWEEL = 0x0640
local LAM_ALEF = { [0x0622] = { 0xFEF5, 0xFEF6 }, [0x0623] = { 0xFEF7, 0xFEF8 },
  [0x0625] = { 0xFEF9, 0xFEFA }, [0x0627] = { 0xFEFB, 0xFEFC } }

local function isMark(cp) return cp >= 0x064B and cp <= 0x0652 end
local function isLetter(cp) return FORMS[cp] ~= nil or cp == TATWEEL end
local function joinsNext(cp) return cp == TATWEEL or (FORMS[cp] and FORMS[cp][3] ~= nil) end
local function joinsPrev(cp) return cp == TATWEEL or (FORMS[cp] and cp ~= 0x0621) end

-- contextual forms, still in logical (reading) order
function I18n.shapeLogical(cps)
  local out = {}
  local n = #cps
  local function prevLetter(i)
    local j = i - 1
    while j >= 1 and isMark(cps[j]) do j = j - 1 end
    return j >= 1 and cps[j] or nil
  end
  local function nextLetter(i)
    local j = i + 1
    while j <= n and isMark(cps[j]) do j = j + 1 end
    return j <= n and cps[j] or nil, j
  end
  local i = 1
  while i <= n do
    local cp = cps[i]
    if isLetter(cp) and cp ~= TATWEEL then
      local p = prevLetter(i)
      local joinBefore = p ~= nil and isLetter(p) and joinsNext(p) and joinsPrev(cp)
      local nx, nxi = nextLetter(i)
      if cp == 0x0644 and nx and LAM_ALEF[nx] then
        out[#out + 1] = LAM_ALEF[nx][joinBefore and 2 or 1]
        i = nxi + 1
      else
        local joinAfter = nx ~= nil and isLetter(nx) and joinsNext(cp) and joinsPrev(nx)
        local f = FORMS[cp]
        local form
        if joinBefore and joinAfter then form = f[4]
        elseif joinBefore then form = f[2]
        elseif joinAfter then form = f[3]
        else form = cp end -- isolated: the plain letter (every Arabic font has it)
        out[#out + 1] = form or cp
        i = i + 1
      end
    else
      out[#out + 1] = cp
      i = i + 1
    end
  end
  return out
end

------------------------------------------------------------------------------
-- Right-to-left ordering (simplified bidi): Latin letters and numbers keep
-- their order inside a run; everything else is read right to left.
------------------------------------------------------------------------------
local MIRROR = { [40] = 41, [41] = 40, [91] = 93, [93] = 91, [60] = 62, [62] = 60, [123] = 125, [125] = 123 }

local function isLTR(cp)
  return (cp >= 48 and cp <= 57) or (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122) or cp == 0x2082
end
local function isLTRJoiner(cp) -- inside a Latin / number run: 21.5%  3/9  O2-B  12:30
  return cp == 46 or cp == 37 or cp == 47 or cp == 58 or cp == 45 or cp == 43 or cp == 95
end

function I18n.visual(cps)
  -- split into runs
  local runs, cur, curLTR = {}, {}, nil
  local i, n = 1, #cps
  while i <= n do
    local cp = cps[i]
    local ltr = isLTR(cp) or (curLTR == true and isLTRJoiner(cp) and i < n and (isLTR(cps[i + 1]) or cp == 37))
    ltr = ltr and true or false
    if i == 1 then curLTR = ltr end
    if ltr ~= curLTR then
      runs[#runs + 1] = { ltr = curLTR, cps = cur }
      cur, curLTR = {}, ltr
    end
    cur[#cur + 1] = cp
    i = i + 1
  end
  if #cur > 0 then runs[#runs + 1] = { ltr = curLTR, cps = cur } end
  -- a % sign belongs before the number when read right to left: 50% -> %50
  local out = {}
  for r = #runs, 1, -1 do
    local run = runs[r]
    if run.ltr then
      for _, cp in ipairs(run.cps) do out[#out + 1] = cp end
    else
      for k = #run.cps, 1, -1 do
        local cp = run.cps[k]
        out[#out + 1] = MIRROR[cp] or cp
      end
    end
  end
  return out
end

-- logical Arabic text -> string ready to draw left-to-right
function I18n.shape(s)
  if not I18n.hasArabic(s) then return s end
  return encode(I18n.visual(I18n.shapeLogical(decode(s))))
end

------------------------------------------------------------------------------
-- Translation
------------------------------------------------------------------------------
local TABLES = {}
local exact, templates = {}, {}

local function escapePattern(s) return (s:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")) end

-- "Loaded %d units (%s)" -> Lua pattern with captures
local function templateToPattern(fmt)
  local out, i, n, caps = {}, 1, #fmt, 0
  while i <= n do
    local c = fmt:sub(i, i)
    if c == "%" then
      local spec = fmt:match("^%%[%-%d%.]*[dsf%%]", i)
      if spec == "%%" then out[#out + 1] = "%%"; i = i + 2
      elseif spec then
        local kind = spec:sub(-1)
        caps = caps + 1
        if kind == "d" then out[#out + 1] = "(%-?%d+)"
        elseif kind == "f" then out[#out + 1] = "(%-?[%d%.]+)"
        else out[#out + 1] = "(.-)" end
        i = i + #spec
      else
        out[#out + 1] = "%%"; i = i + 1
      end
    else
      out[#out + 1] = escapePattern(c)
      i = i + 1
    end
  end
  return "^" .. table.concat(out) .. "$", caps
end

local function load(lang)
  if TABLES[lang] then return TABLES[lang] end
  local ok, tbl = pcall(require, "src.i18n_" .. lang)
  TABLES[lang] = ok and tbl or {}
  return TABLES[lang]
end

function I18n.setLanguage(lang)
  I18n.lang = lang
  exact, templates = {}, {}
  I18n._cache = {}
  if lang == "en" then return end
  for en, tr in pairs(load(lang)) do
    if en:find("%%[%-%d%.]*[dsf]") then
      local pat, caps = templateToPattern(en)
      templates[#templates + 1] = { pat = pat, tr = tr, caps = caps, len = #en }
    else
      exact[en] = tr
    end
  end
  -- most specific templates first
  table.sort(templates, function(a, b) return a.len > b.len end)
end

function I18n.isRTL() return I18n.lang == "ar" end

-- English text -> current language (unknown text stays English)
function I18n.t(s)
  if I18n.lang == "en" or type(s) ~= "string" or s == "" then return s end
  local cache = I18n._cache
  if cache[s] then return cache[s] end
  local tr = exact[s]
  if not tr then
    local trimmed = s:match("^%s*(.-)%s*$")
    tr = exact[trimmed]
    if not tr then
      for _, t in ipairs(templates) do
        local caps = { s:match(t.pat) }
        if #caps > 0 or s:match(t.pat) then
          tr = (t.tr:gsub("{(%d)}", function(k)
            local v = caps[tonumber(k)] or ""
            return I18n.t(v) -- words inside numbers' sentences translate too
          end))
          break
        end
      end
    end
  end
  tr = tr or s
  cache[s] = tr
  return tr
end
I18n._cache = {}

------------------------------------------------------------------------------
-- love.graphics hook
------------------------------------------------------------------------------
-- Splits logical text into lines that fit `limit` pixels (measured shaped)
function I18n.wrap(font, text, limit)
  local lines = {}
  for para in (text .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      local try = line == "" and word or (line .. " " .. word)
      if line ~= "" and font:getWidth(I18n.shape(try)) > limit then
        lines[#lines + 1] = line
        line = word
      else
        line = try
      end
    end
    lines[#lines + 1] = line
  end
  return lines
end

-- Picks the Arabic font for `text` drawn where English `english` would be:
-- same line height and baseline as the English font, shrunk (down to 72%)
-- when the Arabic would take more room than the English did.
local function fitFont(Theme, enFont, english, arabic, limit)
  local scale = 1
  local f = Theme.arabicFontFor(enFont, 1)
  if not f then return nil end
  if limit then
    local _, enLines = enFont:getWrap(english, limit)
    local want = math.max(1, #enLines)
    while scale > 0.72 and #I18n.wrap(f, arabic, limit) > want do
      scale = scale - 0.07
      f = Theme.arabicFontFor(enFont, scale)
    end
  else
    local room = enFont:getWidth(english) * 1.12 + 8
    while scale > 0.72 and f:getWidth(I18n.shape(arabic)) > room do
      scale = scale - 0.07
      f = Theme.arabicFontFor(enFont, scale)
    end
  end
  return f
end

function I18n.install()
  if I18n.installed then return end
  I18n.installed = true
  local lg = love.graphics
  local rawPrint, rawPrintf = lg.print, lg.printf
  local Theme = require("src.ui.theme")
  I18n.rawPrint, I18n.rawPrintf = rawPrint, rawPrintf

  -- draws with the fitted Arabic font, on the English baseline
  local function withArabicFont(english, arabic, limit, fn)
    local cur = lg.getFont()
    local f = fitFont(Theme, cur, english, arabic, limit)
    if not f then return fn(cur, 0) end
    -- sit on the same baseline as the English text would
    local dy = cur:getBaseline() - f:getBaseline()
    lg.setFont(f)
    fn(f, dy)
    lg.setFont(cur)
  end

  lg.print = function(text, x, y, ...)
    if type(text) ~= "string" or I18n.lang == "en" then return rawPrint(text, x, y, ...) end
    local tr = I18n.t(text)
    if not I18n.hasArabic(tr) then return rawPrint(tr, x, y, ...) end
    local args = { ... }
    withArabicFont(text, tr, nil, function(_, dy) rawPrint(I18n.shape(tr), x, y + dy, unpack(args)) end)
  end

  lg.printf = function(text, x, y, limit, align, ...)
    if type(text) ~= "string" or I18n.lang == "en" then return rawPrintf(text, x, y, limit, align, ...) end
    local tr = I18n.t(text)
    if not I18n.hasArabic(tr) then return rawPrintf(tr, x, y, limit, align, ...) end
    local args = { ... }
    local enFont = lg.getFont()
    local enLH = enFont:getHeight() * enFont:getLineHeight()
    withArabicFont(text, tr, limit, function(font, dy)
      -- same alignment and line spacing as the English text
      for i, line in ipairs(I18n.wrap(font, tr, limit)) do
        rawPrintf(I18n.shape(line), x, y + dy + (i - 1) * enLH, limit, align, unpack(args))
      end
    end)
  end
end

-- width of a string as it will be drawn (for panels that size to their text)
function I18n.width(font, s)
  local tr = I18n.t(s)
  if I18n.hasArabic(tr) then
    local Theme = require("src.ui.theme")
    local f = fitFont(Theme, font, s, tr, nil) or font
    return f:getWidth(I18n.shape(tr))
  end
  return font:getWidth(tr)
end

return I18n
