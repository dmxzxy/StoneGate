-- ============================================================================
-- view/rest_view —— 休息场景（像素世界）：暮色林地 + 篝火 + 主角坐着烤火(rest 姿势) + Zzz。
-- HUD/文字留设计空间叠上层。纯绘制，无命中。
-- 依赖：base/screen + base/draw + view/sprites + fx + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local sprites = require("view.sprites")
local fx = require("fx")
local D = require("data")
local UI = D.UI
local DESIGN_H = D.DESIGN_H

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local setc = draw.setc

local rest_view = {}

function rest_view.draw()
    -- ── 像素世界：场景画布 ──
    screen.begin_scene()
    sprites.draw_backdrop({ path=false })   -- 营地不画小径，篝火坐实地面
    local SW, SH, HOR = sprites.SCENE_W, sprites.SCENE_H, sprites.HOR
    local gy = HOR + math.floor((SH-HOR)*0.45)
    local fxp = math.floor(SW*0.56)         -- 篝火 x
    sprites.draw_fire(fxp, gy-4, fx.swing)
    sprites.draw_hero(math.floor(SW*0.40), gy, fx.t_accum, "rest")  -- 主角坐火堆左侧烤火
    screen.end_scene()

    -- ── HUD（设计空间）：Zzz 浮在主角头顶（图形，无说明文字）──
    local sw, sh = screen.sw, screen.sh
    local hero_dx = SW*0.40 / SW * D.DESIGN_W * sw
    local hero_dy = gy/SH * DESIGN_H * sh
    setc(UI.dim)
    for i=0,2 do local zx,zy=hero_dx-sx(8)+i*sx(11), hero_dy-sy(70)-i*sy(14)
        love.graphics.setFont(i==0 and draw.font_med or draw.font_sm); love.graphics.print("z", zx, zy) end
end

return rest_view
