--[[
  Prop sprites (assets/props/*.png, built by tools/build_props.py)
  Props.draw(name, x, y, w, h, opts)   sprite stretched to the rect
     opts.shadow  (default true)  soft contact shadow under the base
     opts.alpha
  Props.gray(true/false)          locked look: desaturated + darker
]]
local Assets = require("src.assets")

local Props = {}

local grayShader
local function shader()
  if grayShader == nil then
    local ok, s = pcall(love.graphics.newShader, [[
      vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 p = Texel(tex, tc) * color;
        float g = dot(p.rgb, vec3(0.299, 0.587, 0.114));
        return vec4(vec3(0.22 + g * 0.42), p.a);
      }
    ]])
    grayShader = ok and s or false
  end
  return grayShader
end

function Props.gray(on)
  local s = shader()
  if not s then return end
  love.graphics.setShader(on and s or nil)
end

function Props.image(name)
  return Assets.image("assets/props/" .. name .. ".png")
end

function Props.shadow(x, y, w, h, alpha)
  local lg = love.graphics
  lg.setColor(0.02, 0.02, 0.08, alpha or 0.35)
  lg.ellipse("fill", x + w / 2, y + h - 3, w * 0.48, math.max(6, math.min(16, w * 0.09)))
end

function Props.draw(name, x, y, w, h, opts)
  opts = opts or {}
  local img = Props.image(name)
  if opts.shadow ~= false then Props.shadow(x, y, w, h) end
  if not img then
    love.graphics.setColor(0.8, 0.82, 0.9, opts.alpha or 1)
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)
    love.graphics.setColor(0.06, 0.06, 0.12, opts.alpha or 1)
    love.graphics.setLineWidth(3); love.graphics.rectangle("line", x, y, w, h, 8, 8); love.graphics.setLineWidth(1)
    return
  end
  love.graphics.setColor(1, 1, 1, opts.alpha or 1)
  love.graphics.draw(img, x, y, 0, w / img:getWidth(), h / img:getHeight())
end

return Props
