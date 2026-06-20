-- ============================================================================
-- view/rest_view —— 休息场景：篝火 + 弓手坐着 + Zzz。纯绘制，无命中。
-- 依赖：base/screen + base/draw + fx + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local fx = require("fx")
local D = require("data")
local UI = D.UI
local DESIGN_H = D.DESIGN_H

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local setc = draw.setc
local draw_archer = draw.draw_archer

local rest_view = {}

function rest_view.draw()
    local sw, sh = screen.sw, screen.sh
    local cx = love.graphics.getWidth()/2
    local px,py = cx, DESIGN_H*0.46*sh
    -- 篝火
    local f = math.sin(fx.swing*8)*0.2+0.8
    setc({0.3,0.2,0.12}); love.graphics.rectangle("fill",px-sx(18),py,sx(36),sy(7),2*sw)
    setc({1.0,0.5*f,0.15}); love.graphics.polygon("fill",px-sx(10),py,px,py-sy(28*f),px+sx(10),py)
    setc({1.0,0.8,0.3,0.85}); love.graphics.polygon("fill",px-sx(5),py,px,py-sy(14*f),px+sx(5),py)
    draw_archer(px-sx(56),py+sy(2))
    -- Zzz（图形，无说明文字）
    setc(UI.dim)
    for i=0,2 do local zx,zy=px-sx(64)+i*sx(11), py-sy(78)-i*sy(14)
        love.graphics.setFont(i==0 and draw.font_med or draw.font_sm); love.graphics.print("z", zx, zy) end
end

return rest_view
