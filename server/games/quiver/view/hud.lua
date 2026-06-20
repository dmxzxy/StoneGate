-- ============================================================================
-- view/hud —— 顶部资源条(等级/经验/金币/箭矢) + 底部活动标签 + 五入口按钮。
-- 依赖：base/screen(缩放) + base/draw(原语+字体) + core/state + sys/inventory(ammo_count) + data。
-- 提供 draw_hud()（顶栏，始终画）、bottom_btns()（底栏，无面板时画）、group_color(gid)。
-- 底部入口的命中在 core/input（无面板路由），这里只负责画。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local state = require("core.state")
local fx = require("fx")
local inv = require("sys.inventory")
local D = require("data")
local UI = D.UI
local ACT_GROUPS = D.ACT_GROUPS
local ACTIVITIES = D.ACTIVITIES

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local setc = draw.setc
local bar, button = draw.bar, draw.button
local icon_coin, icon_arrow = draw.icon_coin, draw.icon_arrow
local ammo_count = inv.ammo_count

local hud = {}

function hud.draw_hud()
    local w=love.graphics.getWidth()
    local bh=sy(46)
    love.graphics.setColor(0.05,0.06,0.1,0.94); love.graphics.rectangle("fill",0,0,w,bh)
    love.graphics.setColor(UI.btn[1],UI.btn[2],UI.btn[3],0.5); love.graphics.rectangle("fill",0,bh-2*screen.sh,w,2*screen.sh)
    -- 左：等级 + 经验条
    love.graphics.setFont(draw.font_med); setc(UI.text); love.graphics.print(state.player.level, sx(10), sy(5))
    bar(sx(34), sy(9), sx(130), sy(10), state.player.xp/state.player.xp_next, UI.xp)
    -- 右：金币图标+数、箭矢图标(档色)+数
    icon_coin(w-sx(120), sy(15), sx(8)); setc(UI.gold); love.graphics.setFont(draw.font_sm); love.graphics.print(state.player.gold, w-sx(108), sy(9))
    local acol = state.player.arrow_tier and state.player.arrow_tier.color or {0.5,0.3,0.3}
    local acnt = state.player.arrow_tier and ammo_count(state.player.arrow_tier.id) or 0
    icon_arrow(w-sx(56), sy(15), sx(11), acol); setc(acol); love.graphics.print(acnt, w-sx(38), sy(9))
    if fx.toast then love.graphics.setFont(draw.font_sm); setc(fx.toast.color,math.min(1,fx.toast.timer)); love.graphics.printf(fx.toast.text,0,sy(50),w-sx(10),"right") end
end

function hud.group_color(gid) for _,g in ipairs(ACT_GROUPS) do if g.id==gid then return g.col end end return UI.dim end

function hud.bottom_btns()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    -- 当前活动标签 + 所属优先级层级色点
    local a=ACTIVITIES[state.activity]; local gc=hud.group_color(a.group)
    setc(gc); love.graphics.circle("fill", w/2-sx(40), h-sy(62), sx(4))
    love.graphics.setFont(draw.font_sm); setc(a.group=="idle" and UI.dim or UI.good)
    love.graphics.printf("当前："..a.name, sx(20), h-sy(68), w-sx(40), "center")
    -- 五入口：活动 / 技能 / 背包 / 装备 / 地区
    local by=h-sy(46); local n=5; local gap=sx(6); local bw=(w-sx(20)-gap*(n-1))/n
    local labels={ {"活动",{0.5,0.4,0.65}}, {"技能",{0.7,0.4,0.4}}, {"背包",{0.55,0.45,0.3}}, {"装备",UI.btn}, {"地区",{0.3,0.5,0.7}} }
    for i,l in ipairs(labels) do
        button(sx(10)+(i-1)*(bw+gap), by, bw, sy(36), l[1], l[2], true, draw.font_sm)
    end
end

return hud
