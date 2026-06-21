-- ============================================================================
-- view/hud_helium —— 用 helium 搭的新主 HUD（画在 HUD 层，盖在 immediate 场景之上）。
-- 两个 helium 元素（都进非缓存 scene → 每帧重画，自然读到最新 state，无 canvas 缓存停旧值）：
--   · topcard：左上角色头像卡(scissor 露头+弓臂+等级徽章) + HP/MP/经验三条 + 右上金币/箭档。
--     纯展示，不订阅任何输入 → 点击全部落到游戏 press（与背包/装备拖拽不打架）。
--   · bottombar：底部五入口(图标在上/文字在下) + 活动胶囊。只在无面板时 :draw()，开面板时 :undraw()。
--     仅在五个按钮矩形上订阅 'clicked'（命中即 setpanel + 捕获，helium 吞掉该点，游戏 press 不再触发）。
-- 内部全部复用 base/draw 原语（已带 sx/sy 缩放），坐标走 480×800 设计空间。
-- 依赖：helium(由 main 传入) + base/screen + base/draw + core/state + fx + sys/inventory + data。
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
local bar = draw.bar
local icon_coin, icon_arrow = draw.icon_coin, draw.icon_arrow
local ammo_count = inv.ammo_count

local hh = {}

local function group_color(gid) for _,g in ipairs(ACT_GROUPS) do if g.id==gid then return g.col end end return UI.dim end

-- 五入口按钮的设计空间几何（与 core/input 的命中保持同一套坐标，松手处仍可走游戏 press 兜底）
local function btn_rects()
    local w,h = love.graphics.getWidth(), love.graphics.getHeight()
    local by=h-sy(46); local n=5; local gap=sx(6); local bw=(w-sx(20)-gap*(n-1))/n
    local r={}
    for i=1,n do r[i]={ x=sx(10)+(i-1)*(bw+gap), y=by, w=bw, h=sy(36) } end
    return r
end

local BTN_IDS = { "activity", "skills", "bag", "equip", "region" }
-- {标签, 主色}；图标用画的小符号(在标签上方)
local BTN_LABELS = {
    { "活动", {0.5,0.4,0.65} }, { "技能", {0.7,0.4,0.4} }, { "背包", {0.55,0.45,0.3} },
    { "装备", UI.btn },          { "地区", {0.3,0.5,0.7} },
}

-- 小入口图标（像素剪影，置于按钮上半部）
local function btn_icon(id, cx, cy, s, col)
    draw.pixel_icon(id, cx, cy, s, col)
end

-- ----------------------------------------------------------------------------
-- topcard 渲染：只保留 角色头像 + 等级（去掉 HP/MP/经验三条与右上资源列；血条移到场景、金币移到背包按钮）。
-- ----------------------------------------------------------------------------
local function draw_topcard()
    local w = love.graphics.getWidth()
    local p = state.player
    -- 头像卡(8,6,62,54)：scissor 内露 chibi 弓手半身+弓臂，脚落框外
    local cx,cy,cw,ch = sx(8),sy(6),sx(56),sy(54)
    draw.panel(cx,cy,cw,ch, {0.1,0.11,0.16,0.95}, UI.line, sx(6))
    setc({0.14,0.13,0.22,0.95}); love.graphics.rectangle("fill",cx+sx(2),cy+sy(2),cw-sx(4),ch-sy(4))
    love.graphics.push("all"); love.graphics.setScissor(cx,cy,cw,ch)
    local ps = math.max(2, sx(1.7))
    draw.draw_hero_chibi(cx+cw*0.5, cy+ch+sy(20), ps, draw.t)
    love.graphics.pop()
    -- 等级徽章（左下角圆）
    setc(UI.gold); love.graphics.circle("fill", cx+sx(11), cy+ch-sy(11), sx(10))
    setc({0.1,0.09,0.05}); love.graphics.setFont(draw.font_sm)
    love.graphics.printf(p.level, cx+sx(11)-sx(10), cy+ch-sy(11)-draw.font_sm:getHeight()/2, sx(20), "center")
    -- 头像右侧：名字 + 一行小字资源(许可/钥匙)，简洁不堆条
    setc(UI.text); love.graphics.setFont(draw.font); love.graphics.print("弓手 Lv"..p.level, cx+cw+sx(10), sy(10))
    love.graphics.setFont(draw.font_sm); setc({0.6,0.82,1})
    draw.pixel_icon("license", cx+cw+sx(16), sy(36), sx(7), {0.55,0.78,0.95})
    love.graphics.print(math.floor(p.energy or 0).."/"..math.floor(p.energy_max or 0), cx+cw+sx(26), sy(31))
    local keys = (inv.inv_count("mat","iron_key") or 0)+(inv.inv_count("mat","ember_key") or 0)+(inv.inv_count("mat","void_key") or 0)
    draw.pixel_icon("key", cx+cw+sx(74), sy(36), sx(7), {0.9,0.78,0.4})
    setc({0.95,0.85,0.5}); love.graphics.print(keys, cx+cw+sx(84), sy(31))
    -- toast 在卡片之下淡出
    if fx.toast then love.graphics.setFont(draw.font_sm); setc(fx.toast.color, math.min(1,fx.toast.timer))
        love.graphics.printf(fx.toast.text, 0, sy(50), w-sx(10), "right") end
end

-- ----------------------------------------------------------------------------
-- bottombar 渲染：活动胶囊 + 五入口（图标在上/文字在下，含红点位）。
-- ----------------------------------------------------------------------------
local function draw_bottombar()
    local w,h = love.graphics.getWidth(), love.graphics.getHeight()
    -- 角色经验条（替代原"当前：xxx"状态行）：等级 + 经验进度，醒目可见
    local p = state.player
    bar(sx(40), h-sy(68), w-sx(80), sy(12), p.xp/p.xp_next, UI.xp, "Lv "..p.level.."   经验 "..math.floor(p.xp).."/"..p.xp_next)
    -- 五入口
    local rects = btn_rects()
    for i,r in ipairs(rects) do
        local lbl = BTN_LABELS[i]
        local col = lbl[2]
        setc(col); draw.rrect("fill", r.x, r.y, r.w, r.h, sx(6))
        love.graphics.setColor(1,1,1,0.14); draw.rrect("fill", r.x+sx(5), r.y+sy(1.5), r.w-sx(10), r.h*0.32, sx(6))
        love.graphics.setColor(0,0,0,0.22); draw.rrect("fill", r.x, r.y+r.h-sy(3), r.w, sy(3), sx(6))
        -- 图标在上
        btn_icon(BTN_IDS[i], r.x+r.w/2, r.y+sy(11), sy(8), {0.96,0.96,1})
        -- 文字在下
        love.graphics.setFont(draw.font_sm); setc(UI.text)
        love.graphics.printf(lbl[1], r.x, r.y+r.h-sy(15), r.w, "center")
        -- 背包按钮上方挂金币(铜银金分级)：钱包归在背包入口
        if BTN_IDS[i]=="bag" then
            local cp = draw.coin_parts(p.gold)
            local ctier = (cp.g>0 and "gold") or (cp.s>0 and "silver") or "copper"
            local cy = r.y - sy(13)
            draw.icon_coin(r.x+sx(7), cy+sy(4), sx(6), ctier)
            setc(ctier=="gold" and UI.gold or ctier=="silver" and {0.82,0.85,0.9} or {0.82,0.52,0.30})
            love.graphics.setFont(draw.font_sm); love.graphics.print(draw.coin_str(p.gold), r.x+sx(16), cy)
        end
        -- 红点位（暂无提醒来源，预留：state.badge[id] 为真时画）
        if state.badge and state.badge[BTN_IDS[i]] then
            setc(UI.bad); love.graphics.circle("fill", r.x+r.w-sx(6), r.y+sy(5), sx(4))
        end
    end
end

-- ----------------------------------------------------------------------------
-- 构建两个 helium 元素。main 在 love.load 里调一次，拿回 {top, bottom}。
-- helium element 工厂：传入的 func(params, view) 在 setup 期跑一次，返回每帧渲染闭包。
-- 输入订阅在 setup 期注册一次；'clicked' 命中即捕获 → 该点不会再下发到游戏 press。
-- ----------------------------------------------------------------------------
function hh.build(helium)
    local W,H = love.graphics.getWidth(), love.graphics.getHeight()

    local top = helium(function()
        return function() draw_topcard() end
    end)({}, W, H)

    local bottom = helium(function()
        local hinput = helium.input
        -- 五入口点击：命中即开面板并捕获（返回 true 由 helium 内部 mousepressed 判定）
        local rects = btn_rects()
        for i,r in ipairs(rects) do
            local id = BTN_IDS[i]
            hinput('clicked', function()
                if not state.panel_open then state.panel_open = id end
            end, true, r.x, r.y, r.w, r.h)
        end
        return function() draw_bottombar() end
    end)({}, W, H)

    return { top=top, bottom=bottom }
end

return hh
