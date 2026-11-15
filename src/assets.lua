-- Image loading that works both from the game folder (love.filesystem) and,
-- as a fallback, from the current working directory (used by smoke tests
-- that run the game code from another folder). Returns nil if not found.
local Assets = {}

local cache = {}

function Assets.image(path)
  if cache[path] ~= nil then return cache[path] or nil end
  local ok, img = pcall(love.graphics.newImage, path)
  if not ok then
    local f = io.open(path, "rb")
    if f then
      local bytes = f:read("*a")
      f:close()
      ok, img = pcall(function()
        return love.graphics.newImage(love.image.newImageData(love.filesystem.newFileData(bytes, path)))
      end)
    end
  end
  cache[path] = ok and img or false
  return ok and img or nil
end

return Assets
