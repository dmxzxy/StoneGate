-- ============================================================================
-- view/mastery_view —— 战斗精通面板(满级软成长)：显示可分配精通点 + 各精通行(投点按钮)。
-- 满级(60)后 xp 转精通点(progression.gain_xp)，这里把点投入各路线(每级 +0.5%，成本递增)。
-- 提供 draw()、hit(x,y)（返回键 / 投点按钮）、row_rect(i)（几何，共用）。
-- 依赖：base/screen + base/draw + core/state + sys/progression(spend_mastery/mastery_level) + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local state = require("core.state")
local prog = require("sys.progression")
local D = require("data")
local UI = D.UI
local MASTERIES = D.MASTERIES
local MP = D.MASTERY_PER_POINT

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local function hit(x,y,rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end
local setc = draw.setc
local panel, button = draw.panel, draw.button
local rrect = draw.rrect

local mastery_view = {}

function mastery_view.row_rect(i)
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112)
    local rh,gap=sy(58),sy(8); local base=py+sy(64)
    return px+sx(10), base+(i-1)*(rh+gap), pw-sx(20), rh
end
local row_rect = mastery_view.row_rect

function mastery_view.draw()
    local sw = screen.sw
    local w,h=love.graphics.getWidth(),love.graphics.getHeight(); love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,w,h)
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112); panel(px,py,pw,ph,{0.09,0.1,0.15,0.98},UI.line,10*sw)
    love.graphics.setFont(draw.font_med); setc(UI.text); love.graphics.printf("战斗精通",px,py+sy(8),pw,"center")
    draw.close_x(px,py,pw)
    local m = state.player.mastery or { points=0 }
    local pts = m.points or 0
    -- 可分配点 + 说明
    setc(UI.gold); love.graphics.setFont(draw.font); love.graphics.printf("可分配精通点："..pts, px, py+sy(34), pw, "center")
    setc(UI.dim); love.graphics.setFont(draw.font_sm)
    local hint = (state.player.level>=D.LEVEL_CAP) and "满级后经验转精通点 · 每级 +0.5% · 越投越贵(软上限)"
                 or ("到 Lv"..D.LEVEL_CAP.." 满级后经验转精通点 · 每级 +0.5%")
    love.graphics.printf(hint, px, py+sy(48), pw, "center")

    for i,mm in ipairs(MASTERIES) do
        local x,y,rw,rh = row_rect(i)
        local lv = prog.mastery_level(mm.id)
        local cost = D.mastery_cost(lv)
        local can = pts >= cost
        panel(x,y,rw,rh, {mm.color[1]*0.16,mm.color[2]*0.16,mm.color[3]*0.18,0.95}, mm.color, 8*sw)
        setc(mm.color); rrect("fill", x, y+sy(4), sx(3), rh-sy(8), 2*sw)
        setc(UI.text); love.graphics.setFont(draw.font); love.graphics.print(mm.name, x+sx(14), y+sy(7))
        setc(UI.dim); love.graphics.setFont(draw.font_sm); love.graphics.print(mm.desc, x+sx(14), y+sy(29))
        -- 当前级数/加成
        setc(mm.color); love.graphics.setFont(draw.font_sm)
        love.graphics.print("Lv "..lv.."  (+"..string.format("%.1f", lv*MP*100).."%)", x+sx(14), y+sy(43))
        -- 投点按钮(显示花费)
        button(x+rw-sx(96), y+sy(13), sx(86), sy(32), "投入 "..cost.."点", can and {0.4,0.5,0.7} or UI.btn, can, draw.font_sm)
    end
    button(px+pw/2-sx(60),py+ph-sy(36),sx(120),sy(28),"返回",{0.4,0.4,0.5},true)
end

function mastery_view.hit(x,y)
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112)
    if draw.hit_close_x(x,y,px,py,pw) then state.panel_open="equip"; return true end
    if hit(x,y,px+pw/2-sx(60),py+ph-sy(36),sx(120),sy(28)) then state.panel_open="equip"; return true end
    for i,mm in ipairs(MASTERIES) do
        local x0,y0,rw,rh = row_rect(i)
        if hit(x,y, x0+rw-sx(96), y0+sy(13), sx(86), sy(32)) then prog.spend_mastery(mm.id); return true end
    end
    return true
end

return mastery_view
