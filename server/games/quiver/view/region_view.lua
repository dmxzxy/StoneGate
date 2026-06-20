-- ============================================================================
-- view/region_view —— 地区面板：三档分组 + 可滚动地区卡列表。
-- 提供 draw()、press(x,y)（返回键 / 开始滚动）、release(x,y)（未滚动则按落点选地区）、
-- clamp_scroll()、region_layout()/region_viewport()（几何，draw 与命中共用）。
-- 拖拽滚动状态在 state.region_drag / state.region_scroll，由 core/input 三段驱动；命中坐标完全不变。
-- 依赖：base/screen + base/draw + core/state + fx + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local state = require("core.state")
local fx = require("fx")
local D = require("data")
local UI = D.UI
local RAR = D.RAR
local TIER_BAND, TIER_ORDER, REGIONS = D.TIER_BAND, D.TIER_ORDER, D.REGIONS

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local function hit(x,y,rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end
local setc = draw.setc
local panel, button, rrect = draw.panel, draw.button, draw.rrect

local region_view = {}

-- 地区列表布局（draw 与命中共用）：三档分组标题 + 段内地区卡，y/h 为内容空间坐标(未减滚动)
function region_view.region_layout()
    local entries={}; local cy=0
    local hh, ch, gap = sy(22), sy(58), sy(6)
    for _,tid in ipairs(TIER_ORDER) do
        entries[#entries+1]={ kind="header", tier=tid, y=cy, h=hh }; cy=cy+hh+sy(4)
        for i,rg in ipairs(REGIONS) do if rg.tier==tid then
            entries[#entries+1]={ kind="card", ri=i, y=cy, h=ch }; cy=cy+ch+gap
        end end
    end
    return entries, cy
end
local region_layout = region_view.region_layout

-- 列表视口（标题下、返回按钮上）
function region_view.region_viewport()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112)
    return px,py,pw,ph, py+sy(40), py+ph-sy(48)
end
local region_viewport = region_view.region_viewport

function region_view.clamp_scroll()
    local _,total = region_layout()
    local _,_,_,_,y0,y1 = region_viewport()
    local maxs=math.max(0, total-(y1-y0))
    if state.region_scroll>maxs then state.region_scroll=maxs end
    if state.region_scroll<0 then state.region_scroll=0 end
end

function region_view.draw()
    local sw = screen.sw
    local w,h=love.graphics.getWidth(),love.graphics.getHeight(); love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,w,h)
    local px,py,pw,ph,y0,y1 = region_viewport(); panel(px,py,pw,ph,{0.09,0.1,0.15,0.98},UI.line,10*sw)
    love.graphics.setFont(draw.font_med); setc(UI.text); love.graphics.printf("地区",px,py+sy(8),pw,"center")
    draw.close_x(px,py,pw)
    -- 左上"副本"入口：开副本面板(复用地区页作 hub，避免底部第6入口拥挤)
    do
        local bx,by,bw,bh = px+sx(10), py+sy(9), sx(64), sy(26)
        button(bx,by,bw,bh,"副本",{0.6,0.4,0.65},true,draw.font_sm)
    end
    region_view.clamp_scroll()
    local entries = region_layout()
    love.graphics.setScissor(px, y0, pw, y1-y0)
    for _,e in ipairs(entries) do
        local yy = y0 + e.y - state.region_scroll
        if yy+e.h>=y0 and yy<=y1 then
            if e.kind=="header" then
                local tb=TIER_BAND[e.tier]
                setc(tb.color); rrect("fill", px+sx(14), yy+sy(5), sx(3), e.h-sy(8))
                love.graphics.setFont(draw.font_sm); setc(tb.color); love.graphics.print(tb.name.."  适合 Lv "..tb.pmin.."-"..tb.pmax, px+sx(22), yy+sy(3))
            else
                local rg=REGIONS[e.ri]; local cur=(rg.id==state.region.id); local tb=TIER_BAND[rg.tier]
                local lowlvl = state.player.level < rg.lo
                panel(px+sx(12), yy, pw-sx(24), e.h, cur and {0.15,0.2,0.3,0.97} or {0.11,0.12,0.17,0.95}, cur and UI.btn or UI.line, 8*sw)
                setc(tb.color); rrect("fill", px+sx(12), yy, sx(4), e.h, 2*sw)   -- 档位色条
                love.graphics.setFont(draw.font); setc(lowlvl and UI.dim or UI.text); love.graphics.print(rg.name, px+sx(24), yy+sy(7))
                love.graphics.setFont(draw.font_sm); setc(UI.dim); love.graphics.print("敌人 Lv "..rg.lo.."-"..rg.hi.."   装等 "..rg.ilo.."-"..rg.ihi, px+sx(24), yy+sy(28))
                local seen={}; local dx=px+sx(24)
                for _,rid in ipairs(rg.rar) do if not seen[rid] then seen[rid]=true; setc(RAR[rid].color); love.graphics.circle("fill",dx+sx(6),yy+sy(48),sx(5)); dx=dx+sx(16) end end
                -- 推荐度：区间内绿勾 / 偏低红"偏难" / 远高灰"已轻松"
                local rtxt, rcol
                if cur then rtxt, rcol = "当前", UI.good
                elseif state.player.level < rg.lo then rtxt, rcol = "偏难", UI.bad
                elseif state.player.level > rg.hi + 5 then rtxt, rcol = "已轻松", UI.dim
                else rtxt, rcol = "✓ 推荐", UI.good end
                setc(rcol); love.graphics.setFont(draw.font_sm); love.graphics.printf(rtxt, px+sx(12), yy+sy(7), pw-sx(40), "right")
            end
        end
    end
    love.graphics.setScissor()
    button(px+pw/2-sx(64),py+ph-sy(40),sx(128),sy(30),"返回",{0.4,0.4,0.5},true)
end

-- 按下：返回键关闭，否则在列表区开始滚动/点选（移动超阈值算滚动）
function region_view.press(x,y)
    local px,py,pw,ph,y0,y1 = region_viewport()
    if draw.hit_close_x(x,y,px,py,pw) then state.panel_open=nil; return true end
    -- "副本"入口：切到副本面板
    if hit(x,y, px+sx(10), py+sy(9), sx(64), sy(26)) then state.panel_open="dungeon"; return true end
    if hit(x,y,px+pw/2-sx(64),py+ph-sy(40),sx(128),sy(30)) then state.panel_open=nil; return true end
    if y>=y0 and y<=y1 then state.region_drag={ y0=y, s0=state.region_scroll, moved=false } end
    return true
end

-- 列表松手：未滚动则按落点选地区
function region_view.release(x,y)
    local rd=state.region_drag; state.region_drag=nil
    if rd.moved then return end
    local px,py,pw,ph,y0,y1 = region_viewport()
    if y<y0 or y>y1 then return end
    local entries = region_layout()
    for _,e in ipairs(entries) do
        if e.kind=="card" then
            local yy = y0 + e.y - state.region_scroll
            if hit(x,y, px+sx(12), yy, pw-sx(24), e.h) then
                local rg=REGIONS[e.ri]; state.region=rg; state.stage=0; state.enemy=nil; state.player.gather_node=nil
                fx.set_toast("狩猎地："..rg.name, UI.good); return
            end
        end
    end
end

return region_view
