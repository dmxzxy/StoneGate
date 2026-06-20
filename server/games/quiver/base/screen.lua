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

-- ── 低分场景画布（像素世界）──
-- 活动场景画进一块 240x400 的虚拟画布（与 480x800 设计同 0.6 比例），最近邻整数放大铺满。
-- 用法：begin_scene() → 在 240x400 像素坐标里画 → end_scene() 自动放大贴到屏幕。
-- canvas 懒建（headless mock 下 newCanvas 返回 fakeobj，照样不崩）。
screen.SCENE_W, screen.SCENE_H = 240, 400
local scene_canvas

local function ensure_canvas()
    if not scene_canvas then
        scene_canvas = love.graphics.newCanvas(screen.SCENE_W, screen.SCENE_H)
        if scene_canvas.setFilter then scene_canvas:setFilter("nearest","nearest") end
    end
    return scene_canvas
end

-- 开始画场景：切到低分画布并清空（caller 传背景色，默认透明）。
function screen.begin_scene(clear)
    local c = ensure_canvas()
    love.graphics.setCanvas(c)
    if clear ~= false then love.graphics.clear(0,0,0,0) end
    return screen.SCENE_W, screen.SCENE_H
end

-- 结束场景：切回屏幕，最近邻放大铺满窗口。
function screen.end_scene()
    love.graphics.setCanvas()
    love.graphics.setColor(1,1,1,1)
    local sx = love.graphics.getWidth()/screen.SCENE_W
    local sy = love.graphics.getHeight()/screen.SCENE_H
    if scene_canvas then love.graphics.draw(scene_canvas, 0,0, 0, sx, sy) end
end

-- 设计坐标(480x800) → 场景画布坐标(240x400)。给 HUD/逻辑算出的点定位场景元素用。
function screen.to_scene_x(dx) return dx * screen.SCENE_W / screen.DESIGN_W end
function screen.to_scene_y(dy) return dy * screen.SCENE_H / screen.DESIGN_H end

-- 按当前窗口尺寸重算缩放（love.load / resize 都走这里）
function screen.set_scale()
    screen.sw = love.graphics.getWidth()/screen.DESIGN_W
    screen.sh = love.graphics.getHeight()/screen.DESIGN_H
end
screen.resize = screen.set_scale

return screen
