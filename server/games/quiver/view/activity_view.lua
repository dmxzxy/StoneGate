-- ============================================================================
-- view/activity_view —— 活动面板：按 ACT_GROUPS 分组(挂机>战斗>副职业)的活动选择列表。
-- 提供 draw()、hit(x,y)->handled（点抽屉外/X 收起 / 切活动）、act_layout()/act_base()（几何，共用）。
-- 依赖：base/screen + base/draw + core/state + sys/progression + sys/combat(next_enemy) + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local state = require("core.state")
local prog = require("sys.progression")
local combat = require("sys.combat")
local D = require("data")
local UI = D.UI
local ACTIVITIES, ACT_GROUPS = D.ACTIVITIES, D.ACT_GROUPS
local MAT_NAME, MAT_COLOR = D.MAT_NAME, D.MAT_COLOR

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local function hit(x,y,rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end
local setc = draw.setc
local panel, bar, rrect = draw.panel, draw.bar, draw.rrect
local gather_need, craft_need = prog.gather_need, prog.craft_need
local next_enemy = combat.next_enemy

local activity_view = {}

-- 活动菜单布局（draw 与 hit 共用）：按 ACT_GROUPS 分组(idle>战斗>副职业)，组标题 + 活动行
function activity_view.act_layout()
    local entries={}; local cy=0; local hh,rh,gap=sy(20),sy(56),sy(8)
    for _,g in ipairs(ACT_GROUPS) do
        entries[#entries+1]={ kind="header", g=g, y=cy, h=hh }; cy=cy+hh+sy(2)
        local rows={}; for id,a in pairs(ACTIVITIES) do if a.group==g.id then rows[#rows+1]=id end end
        table.sort(rows, function(p,q) return ACTIVITIES[p].ord < ACTIVITIES[q].ord end)
        for _,id in ipairs(rows) do entries[#entries+1]={ kind="act", id=id, y=cy, h=rh }; cy=cy+rh+gap end
    end
    return entries
end
local act_layout = activity_view.act_layout

-- 左侧抽屉几何（draw 与 hit 共用）：贴左边、约 2/3 宽、整高，按 state.drawer_t 从屏左滑入。
-- base = 活动行起点 y（标题/副标题之下）。
function activity_view.act_base()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local dw = sx(330)
    local t = state.drawer_t or 0
    local px = -dw*(1-t)            -- t=0 在屏外，t=1 紧贴左边
    return px, 0, dw, h, sy(48)
end
local act_base = activity_view.act_base

function activity_view.draw()
    local sw = screen.sw
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local px,py,pw,ph,base = act_base()
    local t = state.drawer_t or 1
    love.graphics.setColor(0,0,0,0.72*t); love.graphics.rectangle("fill",0,0,w,h)   -- scrim 随滑入淡入
    panel(px,py,pw,ph,{0.09,0.1,0.15,0.99},UI.line,0)   -- 左侧抽屉：贴边直角
    -- 右缘高光，强调"可向右点空白处收起"的抽屉边
    setc(UI.line); love.graphics.rectangle("fill", px+pw-sx(2), py, sx(2), ph)
    love.graphics.setFont(draw.font_med); setc(UI.text); love.graphics.printf("活动",px,py+sy(8),pw,"center")
    draw.close_x(px,py,pw)
    love.graphics.setFont(draw.font_sm); setc(UI.dim); love.graphics.printf("挂机优先 · 战斗其次 · 副职业再次",px,py+sy(30),pw,"center")
    for _,e in ipairs(act_layout()) do
        local yy=base+e.y
        if e.kind=="header" then
            setc(e.g.col); rrect("fill", px+sx(12), yy+sy(3), sx(3), e.h-sy(6))
            love.graphics.setFont(draw.font_sm); setc(e.g.col); love.graphics.print(e.g.name, px+sx(20), yy+sy(1))
        else
            local id=e.id; local a=ACTIVITIES[id]; local cur=(state.activity==id)
            panel(px+sx(10),yy,pw-sx(20),e.h, cur and {0.15,0.2,0.3,0.97} or {0.11,0.12,0.17,0.95}, cur and UI.btn or UI.line, 8*sw)
            -- 选中态左侧彩色竖条（分类语言）
            if cur then setc(UI.good); rrect("fill", px+sx(10), yy+sy(4), sx(3), e.h-sy(8), 2*sw) end
            -- 活动图标（按 kind 简笔，置于行左侧）
            local icx,icy = px+sx(28), yy+e.h/2
            if a.kind=="gather" then draw.icon_mat(a.mat, icx, icy, sy(9))
            elseif a.kind=="craft" then draw.icon_arrow(icx, icy, sy(10), a.job=="forge" and {0.8,0.55,0.4} or {0.7,0.6,0.4})
            elseif a.kind=="combat" then draw.icon_kind("weapon", icx, icy, sy(9), {0.9,0.55,0.5})
            else setc(UI.dim); love.graphics.circle("line", icx, icy, sy(8)); setc(UI.dim); love.graphics.circle("fill", icx, icy, sy(2)) end
            setc(UI.text); love.graphics.setFont(draw.font); love.graphics.print(a.name, px+sx(44), yy+sy(7))
            love.graphics.setFont(draw.font_sm); setc(UI.dim)
            if a.kind=="gather" then
                local s=state.player.skill[id]
                love.graphics.print(string.format("Lv %d   寻找采集 %s", s.lvl, MAT_NAME[a.mat]), px+sx(44), yy+sy(28))
                bar(px+sx(44), yy+sy(44), pw-sx(58), sy(6), s.xp/gather_need(s.lvl), MAT_COLOR[a.mat])
            elseif a.kind=="craft" then
                if a.job=="forge" then
                    local f=state.player.forge
                    love.graphics.print(string.format("Lv %d   炼锭/造装 解锁更高配方", f.lvl), px+sx(44), yy+sy(28))
                    bar(px+sx(44), yy+sy(44), pw-sx(58), sy(6), f.xp/craft_need(f.lvl), {0.8,0.55,0.4})
                else
                    love.graphics.print(string.format("Lv %d   做工攒经验解锁图谱", state.player.craft.lvl), px+sx(44), yy+sy(28))
                    bar(px+sx(44), yy+sy(44), pw-sx(58), sy(6), state.player.craft.xp/craft_need(state.player.craft.lvl), {0.7,0.6,0.4})
                end
            elseif a.kind=="combat" then
                love.graphics.print(state.region.name.."   技能轮转 · 消耗箭矢", px+sx(44), yy+sy(30))
            else
                love.graphics.print("原地休息，仅做被动结算", px+sx(44), yy+sy(30))
            end
            if cur then setc(UI.good); love.graphics.setFont(draw.font_sm); love.graphics.printf("进行中",px+sx(10),yy+sy(7),pw-sx(40),"right") end
        end
    end
end

function activity_view.hit(x,y)
    local px,py,pw,ph,base = act_base()
    if draw.hit_close_x(x,y,px,py,pw) then state.panel_open=nil; return true end
    if x > px+pw then state.panel_open=nil; return true end   -- 点抽屉外侧（scrim）= 收起
    for _,e in ipairs(act_layout()) do
        if e.kind=="act" then
            local id=e.id; local a=ACTIVITIES[id]; local yy=base+e.y
            if hit(x,y,px+sx(10),yy,pw-sx(20),e.h) then
                state.activity=id; state.player.craft_prog=0; state.player.gather_node=nil
                if id=="combat" and not state.enemy then next_enemy() end
                state.panel_open=nil; return true
            end
        end
    end
    return true
end

return activity_view
