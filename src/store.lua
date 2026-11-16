--[[
  Store: small text files that survive closing the game
  =====================================================
  Desktop / phone app : the LOVE save folder (love.filesystem).
  Web browser         : the same, AND a copy in the browser's localStorage.
    The game prints "@@SAVE@@name=<url-encoded text>"; the web page
    (tools/build_web.py) stores it as localStorage["nebula:name"]. When the
    page starts the game it passes every saved copy back as an argument
    "--store:name=<url-encoded text>", read by Store.init.
    localStorage is the reliable one on iPhones (the browser's IndexedDB
    copy of the save folder can be lost), so both are kept.

  Every write adds a "rev=N" line; on load the copy with the higher rev wins,
  so a newer browser copy is never replaced by an older file (or the other
  way round).

  Pure Lua apart from love.filesystem / love.system, which are optional:
  plain-Lua tests run with an in-memory stand-in (Store.backend).
]]
local Store = {}

Store.web = false
Store.mirror = {}  -- name -> text handed over by the web page
Store.revs = {}    -- name -> last rev read or written
Store.PREFIX = "@@SAVE@@"

-- percent-encoding: the text travels as one printable line
function Store.encode(s)
  return (s:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

function Store.decode(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function validName(name) return type(name) == "string" and name:match("^[%w_]+$") ~= nil end

-- file access (love.filesystem in the game, a table in tests)
local function loveBackend()
  local fs = love and love.filesystem
  if not fs then return nil end
  return {
    -- Check that the file exists first: raising (even caught) Lua errors
    -- crashes LOVE in Safari's WebAssembly engine, so avoid them.
    read = function(file)
      if not (fs.getInfo and fs.getInfo(file)) then return nil end
      local ok, text = pcall(fs.read, file)
      return ok and text or nil
    end,
    write = function(file, text) pcall(fs.write, file, text) end,
    remove = function(file) if fs.getInfo and fs.getInfo(file) then pcall(fs.remove, file) end end,
  }
end
Store.backend = nil -- tests set { read, write, remove }
local function backend() return Store.backend or loveBackend() end

-- Reads the web page's saved copies from the start-up arguments.
function Store.init(args)
  Store.web = (love and love.system and love.system.getOS and love.system.getOS() == "Web") or false
  Store.mirror = {}
  for _, a in ipairs(args or {}) do
    if type(a) == "string" then
      local name, data = a:match("^%-%-store:([%w_]+)=(.*)$")
      if name then Store.mirror[name] = Store.decode(data) end
    end
  end
end

function Store.revOf(text)
  return tonumber(text and text:match("^rev=(%d+)") or "") or 0
end

local function stripRev(text) return (text:gsub("^rev=%d+\n", "")) end

-- Text of the newest saved copy (without the rev line), or nil
function Store.read(name)
  if not validName(name) then return nil end
  local b = backend()
  local file = b and b.read(name .. ".txt")
  local web = Store.mirror[name]
  local best = file
  if web and (not file or Store.revOf(web) > Store.revOf(file)) then best = web end
  if not best then return nil end
  Store.revs[name] = math.max(Store.revOf(file), Store.revOf(web))
  return stripRev(best)
end

function Store.write(name, text)
  if not validName(name) then return false end
  local rev = (Store.revs[name] or 0) + 1
  Store.revs[name] = rev
  local full = "rev=" .. rev .. "\n" .. text
  local b = backend()
  if b then b.write(name .. ".txt", full) end
  Store.mirror[name] = full
  if Store.web then print(Store.PREFIX .. name .. "=" .. Store.encode(full)) end
  return true
end

return Store
