-- ============================================================================
-- base/screen —— 缩放与设计空间。只依赖 love + data。
-- 480×800 设计空间，sw/sh 是屏幕/设计的比例；sx(v)/sy(v) 把设计坐标映射到屏幕。
-- sw/sh 在这里持有并由 set_scale/resize 改写，sx/sy 现读现算，下游引用同一份比例。
-- ============================================================================
local D = require("data")

local screen = {}
screen.DESIGN_W, screen.DESIGN_H = D.DESIGN_W, D.DESIGN_H
screen.sw, screen.sh = 1, 1

function screen.sx(v) return v*screen.sw end
function screen.sy(v) return v*screen.sh end

-- 按当前窗口尺寸重算缩放（love.load / resize 都走这里）
function screen.set_scale()
    screen.sw = love.graphics.getWidth()/screen.DESIGN_W
    screen.sh = love.graphics.getHeight()/screen.DESIGN_H
end
screen.resize = screen.set_scale

return screen
