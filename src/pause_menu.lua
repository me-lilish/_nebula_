--[[
  Pause menu (Esc or P in the game, or the round pause button)
    RESUME          | LANGUAGE
    RESTART LEVEL   | READ ALOUD
    START OVER      | SOUND
    MAIN MENU       |
  Two columns of big buttons so they are easy to hit with a thumb on a
  phone. The station is frozen while it is open. Mouse, touch and keyboard
  (Up / Down / Enter, Esc or P to resume) all work.
  START OVER wipes the saved level, so it asks for a second tap first.

  PauseMenu.new(actions) - actions[id]() is called when a button is used;
  actions.value(id) returns the text after "LANGUAGE:" etc.
]]
local PauseMenu = {}
PauseMenu.__index = PauseMenu

-- keyboard order = top to bottom, left column first
PauseMenu.ITEMS = {
  { id = "resume", label = "RESUME", col = 1, row = 1 },
  { id = "restart", label = "RESTART LEVEL", col = 1, row = 2 },
  { id = "startover", label = "START OVER", confirm = "TAP AGAIN TO START OVER", col = 1, row = 3 },
  { id = "menu", label = "MAIN MENU", col = 1, row = 4 },
  { id = "language", label = "LANGUAGE: %s", col = 2, row = 1 },
  { id = "tts", label = "READ ALOUD: %s", col = 2, row = 2 },
  { id = "sound", label = "SOUND: %s", col = 2, row = 3 },
}
-- 96 px tall buttons: about 43 points even on the smallest screen (iPhone SE
-- in Safari, 568 x 320 points, shows the game at 0.44); Apple asks for 44
PauseMenu.X, PauseMenu.W, PauseMenu.COLGAP = 218, 410, 24
PauseMenu.Y0, PauseMenu.H, PauseMenu.GAP = 150, 96, 12

function PauseMenu.new(actions)
  return setmetatable({ actions = actions or {}, selected = 1, hover = nil, confirming = nil }, PauseMenu)
end

function PauseMenu:rect(i)
  local item = PauseMenu.ITEMS[i]
  return PauseMenu.X + (item.col - 1) * (PauseMenu.W + PauseMenu.COLGAP),
    PauseMenu.Y0 + (item.row - 1) * (PauseMenu.H + PauseMenu.GAP), PauseMenu.W, PauseMenu.H
end

function PauseMenu:hit(x, y)
  for i = 1, #PauseMenu.ITEMS do
    local rx, ry, rw, rh = self:rect(i)
    if x >= rx and x <= rx + rw and y >= ry and y <= ry + rh then return i end
  end
  return nil
end

function PauseMenu:label(i)
  local item = PauseMenu.ITEMS[i]
  if item.confirm and self.confirming == item.id then return item.confirm end
  if item.label:find("%%s") then
    local v = self.actions.value and self.actions.value(item.id) or ""
    return string.format(item.label, v)
  end
  return item.label
end

function PauseMenu:isDisabled(i)
  local item = PauseMenu.ITEMS[i]
  return item and self.actions.disabled and self.actions.disabled(item.id) or false
end

function PauseMenu:activate(i)
  local item = PauseMenu.ITEMS[i]
  if not item or self:isDisabled(i) then return nil end
  -- a button that needs a second tap: the first one only asks
  if item.confirm and self.confirming ~= item.id then
    self.confirming = item.id
    return "confirm"
  end
  self.confirming = nil
  if self.actions[item.id] then self.actions[item.id]() end
  return item.id
end

function PauseMenu:mousemoved(x, y)
  self.hover = self:hit(x, y)
  if self.hover then self:_select(self.hover) end
end

function PauseMenu:_select(i)
  if i ~= self.selected then self.confirming = nil end
  self.selected = i
end

-- called when the menu opens
function PauseMenu:open()
  self.selected, self.hover, self.confirming = 1, nil, nil
end

function PauseMenu:mousepressed(x, y)
  local i = self:hit(x, y)
  if i then self:_select(i); return self:activate(i) end
  self.confirming = nil
  return nil
end

function PauseMenu:keypressed(key)
  local n, i = #PauseMenu.ITEMS, self.selected
  if key == "up" or key == "w" then
    repeat i = (i - 2) % n + 1 until not self:isDisabled(i)
    self:_select(i)
  elseif key == "down" or key == "s" then
    repeat i = i % n + 1 until not self:isDisabled(i)
    self:_select(i)
  elseif key == "return" or key == "space" then return self:activate(self.selected)
  elseif key == "escape" or key == "p" then return self:activate(1) end
  return nil
end

function PauseMenu:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  lg.setColor(0.02, 0.02, 0.08, 0.72); lg.rectangle("fill", 0, 0, 1280, 720)
  local px, py = PauseMenu.X - 40, PauseMenu.Y0 - 104
  local pw = 2 * PauseMenu.W + PauseMenu.COLGAP + 80
  local ph = 4 * PauseMenu.H + 3 * PauseMenu.GAP + 104 + 64
  T.panel(px, py, pw, ph, { cut = 22, fill = T.hex("#0F0D2A"), alpha = 0.97, edge = C.cyan, lineWidth = 3 })
  T.outlinedText("PAUSED", px, py + 22, pw, "center", C.white, C.ink, T.font(36))
  for i = 1, #PauseMenu.ITEMS do
    local x, y, w, h = self:rect(i)
    local off = self:isDisabled(i)
    local sel = i == self.selected and not off
    local warn = PauseMenu.ITEMS[i].confirm and self.confirming == PauseMenu.ITEMS[i].id
    local pts = T.cutPoints(x, y, w, h, 12)
    T.set(warn and C.critical or (sel and C.cyan or T.hex(off and "#191C30" or "#1E2A4F")), (sel or warn) and 1 or 0.95); lg.polygon("fill", pts)
    T.set((sel or warn) and C.white or (off and C.metalDark or C.cyanMid)); lg.setLineWidth(3); lg.polygon("line", pts); lg.setLineWidth(1)
    lg.setFont(T.font(warn and 18 or 22)); T.set(warn and C.white or (sel and C.ink or (off and C.metalShade or C.white)))
    lg.printf(self:label(i), x + 8, y + h / 2 - 13, w - 16, "center")
  end
  lg.setFont(T.font(14)); T.set(C.metalShade)
  lg.printf("Esc / P: resume", px, py + ph - 34, pw, "center")
end

return PauseMenu
