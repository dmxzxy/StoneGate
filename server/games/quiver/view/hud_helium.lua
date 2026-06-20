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

-- 小入口图标（简笔，置于按钮上半部）
local function btn_icon(id, cx, cy, s, col)
    setc(col); love.graphics.setLineWidth(math.max(1,sx(1.6)))
    if id=="activity" then       -- 上三角
        love.graphics.polygon("line", cx,cy-s, cx+s*0.9,cy+s*0.7, cx-s*0.9,cy+s*0.7)
    elseif id=="skills" then     -- 斜箭(技能)
        icon_arrow(cx, cy, s*0.95, col)
    elseif id=="bag" then        -- 背包袋
        love.graphics.polygon("line", cx-s*0.8,cy+s*0.8, cx-s*0.6,cy-s*0.4, cx+s*0.6,cy-s*0.4, cx+s*0.8,cy+s*0.8)
        love.graphics.arc("line","open", cx,cy-s*0.4, s*0.45, math.pi, math.pi*2)
    elseif id=="equip" then      -- 盾
        love.graphics.polygon("line", cx,cy-s, cx+s*0.85,cy-s*0.4, cx+s*0.55,cy+s, cx,cy+s*1.05, cx-s*0.55,cy+s, cx-s*0.85,cy-s*0.4)
    else                          -- region：旗
        love.graphics.line(cx-s*0.6,cy-s, cx-s*0.6,cy+s)
        love.graphics.polygon("line", cx-s*0.6,cy-s, cx+s*0.7,cy-s*0.55, cx-s*0.6,cy-s*0.1)
    end
    love.graphics.setLineWidth(1)
end

-- ----------------------------------------------------------------------------
-- topcard 渲染：角色卡 + 三条 + 右上资源。纯画，无输入订阅。
-- ----------------------------------------------------------------------------
local function draw_topcard()
    local w = love.graphics.getWidth()
    local p = state.player
    -- 顶栏底板（盖住设计区 0..62）
    love.graphics.setColor(0.05,0.06,0.1,0.95); love.graphics.rectangle("fill",0,0,w,sy(64))
    love.graphics.setColor(UI.btn[1],UI.btn[2],UI.btn[3],0.5); love.graphics.rectangle("fill",0,sy(64)-2*screen.sh,w,2*screen.sh)

    -- 头像卡(8,6,62,54)：scissor 内露头+弓臂，脚落框外
    local cx,cy,cw,ch = sx(8),sy(6),sx(56),sy(54)
    draw.panel(cx,cy,cw,ch, {0.1,0.11,0.16,0.95}, UI.line, sx(6))
    love.graphics.push("all")
    love.graphics.setScissor(cx,cy,cw,ch)
    -- 把火柴弓手放到框内，脚在框下沿外，只露上半身+弓臂
    draw.draw_archer(cx+cw*0.42, cy+ch+sy(18), "bow", draw.t)
    love.graphics.pop()
    -- 等级徽章（左下角圆）
    setc(UI.gold); love.graphics.circle("fill", cx+sx(11), cy+ch-sy(11), sx(10))
    setc({0.1,0.09,0.05}); love.graphics.setFont(draw.font_sm)
    love.graphics.printf(p.level, cx+sx(11)-sx(10), cy+ch-sy(11)-draw.font_sm:getHeight()/2, sx(20), "center")

    -- 三条：HP(最粗) / MP(中) / 经验(最细)，起点在头像右侧
    local bx = cx+cw+sx(10); local bw = w - bx - sx(96)
    bar(bx, sy(10), bw, sy(9),  p.hp/p.max_hp,        UI.good, math.floor(p.hp).."/"..math.floor(p.max_hp))
    bar(bx, sy(22), bw, sy(7),  (p.mp or 0)/(p.max_mp or 1), UI.btn, "MP "..math.floor(p.mp or 0))
    bar(bx, sy(33), bw, sy(5),  p.xp/p.xp_next,       UI.xp)

    -- 右上资源：金币 + 当前箭档数
    icon_coin(w-sx(86), sy(13), sx(8)); setc(UI.gold); love.graphics.setFont(draw.font_sm)
    love.graphics.print(p.gold, w-sx(74), sy(7))
    local acol = p.arrow_tier and p.arrow_tier.color or {0.5,0.3,0.3}
    local acnt = p.arrow_tier and ammo_count(p.arrow_tier.id) or 0
    icon_arrow(w-sx(82), sy(34), sx(10), acol); setc(acol); love.graphics.print(acnt, w-sx(70), sy(28))

    -- toast 在卡片之下淡出（不压资源区）
    if fx.toast then love.graphics.setFont(draw.font_sm); setc(fx.toast.color, math.min(1,fx.toast.timer))
        love.graphics.printf(fx.toast.text, 0, sy(48), w-sx(10), "right") end
end

-- ----------------------------------------------------------------------------
-- bottombar 渲染：活动胶囊 + 五入口（图标在上/文字在下，含红点位）。
-- ----------------------------------------------------------------------------
local function draw_bottombar()
    local w,h = love.graphics.getWidth(), love.graphics.getHeight()
    -- 活动胶囊：层级色点 + "当前：xxx"
    local a=ACTIVITIES[state.activity]; local gc=group_color(a.group)
    setc(gc); love.graphics.circle("fill", w/2-sx(40), h-sy(62), sx(4))
    love.graphics.setFont(draw.font_sm); setc(a.group=="idle" and UI.dim or UI.good)
    love.graphics.printf("当前："..a.name, sx(20), h-sy(68), w-sx(40), "center")
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
