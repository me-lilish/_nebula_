--[[
  Pause menu (Esc or P in the game, or the MENU touch button)
    RESUME | LANGUAGE | READ ALOUD | SOUND | RESTART MISSION | MAIN MENU
  The station is frozen while it is open. Mouse, touch and keyboard
  (Up / Down / Enter, Esc or P to resume) all work.

  PauseMenu.new(actions) - actions[id]() is called when a button is used;
  actions.value(id) returns the text after "LANGUAGE:" etc.
]]
local PauseMenu = {}
PauseMenu.__index = PauseMenu

PauseMenu.ITEMS = {
  { id = "resume", label = "RESUME" },
  { id = "language", label = "LANGUAGE: %s" },
  { id = "tts", label = "READ ALOUD: %s" },
  { id = "sound", label = "SOUND: %s" },
  { id = "restart", label = "RESTART MISSION" },
  { id = "menu", label = "MAIN MENU" },
}
PauseMenu.X, PauseMenu.W, PauseMenu.Y0, PauseMenu.H, PauseMenu.GAP = 430, 420, 196, 52, 12

function PauseMenu.new(actions)
  return setmetatable({ actions = actions or {}, selected = 1, hover = nil }, PauseMenu)
end

function PauseMenu:rect(i)
  return PauseMenu.X, PauseMenu.Y0 + (i - 1) * (PauseMenu.H + PauseMenu.GAP), PauseMenu.W, PauseMenu.H
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
  if self:isDisabled(i) then return nil end
  if item and self.actions[item.id] then self.actions[item.id]() end
  return item and item.id
end

function PauseMenu:mousemoved(x, y)
  self.hover = self:hit(x, y)
  if self.hover then self.selected = self.hover end
end

function PauseMenu:mousepressed(x, y)
  local i = self:hit(x, y)
  if i then self.selected = i; return self:activate(i) end
  return nil
end

function PauseMenu:keypressed(key)
  if key == "up" or key == "w" then
    repeat self.selected = (self.selected - 2) % #PauseMenu.ITEMS + 1 until not self:isDisabled(self.selected)
  elseif key == "down" or key == "s" then
    repeat self.selected = self.selected % #PauseMenu.ITEMS + 1 until not self:isDisabled(self.selected)
  elseif key == "return" or key == "space" then return self:activate(self.selected)
  elseif key == "escape" or key == "p" then return self:activate(1) end
  return nil
end

function PauseMenu:draw(t)
  local T = require("src.ui.theme")
  local C, lg = T.C, love.graphics
  lg.setColor(0.02, 0.02, 0.08, 0.72); lg.rectangle("fill", 0, 0, 1280, 720)
  local _, y0 = self:rect(1)
  local _, yl, _, hl = self:rect(#PauseMenu.ITEMS)
  T.panel(PauseMenu.X - 50, y0 - 110, PauseMenu.W + 100, yl + hl - y0 + 170,
    { cut = 22, fill = T.hex("#0F0D2A"), alpha = 0.97, edge = C.cyan, lineWidth = 3 })
  T.outlinedText("PAUSED", PauseMenu.X - 50, y0 - 90, PauseMenu.W + 100, "center", C.white, C.ink, T.font(36))
  for i = 1, #PauseMenu.ITEMS do
    local x, y, w, h = self:rect(i)
    local off = self:isDisabled(i)
    local sel = i == self.selected and not off
    local pts = T.cutPoints(x, y, w, h, 12)
    T.set(sel and C.cyan or T.hex(off and "#191C30" or "#1E2A4F"), sel and 1 or 0.95); lg.polygon("fill", pts)
    T.set(sel and C.white or (off and C.metalDark or C.cyanMid)); lg.setLineWidth(3); lg.polygon("line", pts); lg.setLineWidth(1)
    lg.setFont(T.font(20)); T.set(sel and C.ink or (off and C.metalShade or C.white))
    lg.printf(self:label(i), x, y + h / 2 - 12, w, "center")
  end
  lg.setFont(T.font(14)); T.set(C.metalShade)
  lg.printf("Esc / P: resume", PauseMenu.X - 50, yl + hl + 22, PauseMenu.W + 100, "center")
end

return PauseMenu
