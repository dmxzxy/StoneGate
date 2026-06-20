-- ============================================================================
-- view/skills_view —— 技能面板：已学技能 + 技能大师处学新技能。
-- 提供 draw()、hit(x,y)（返回键 / 学习按钮）、skill_row_rect(i)（几何，共用）。
-- 依赖：base/screen + base/draw + core/state + sys/inventory(inv_count) + sys/combat(learn_skill/skill_cost_ok) + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local state = require("core.state")
local inv = require("sys.inventory")
local combat = require("sys.combat")
local D = require("data")
local UI = D.UI
local SKILLS, SKILL_ORDER = D.SKILLS, D.SKILL_ORDER

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local function hit(x,y,rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end
local setc = draw.setc
local panel, button, mat_chip = draw.panel, draw.button, draw.mat_chip
local rrect = draw.rrect
local icon_coin, draw_skill_icon = draw.icon_coin, draw.draw_skill_icon
local inv_count = inv.inv_count
local learn_skill, skill_cost_ok = combat.learn_skill, combat.skill_cost_ok

local skills_view = {}

local function is_known_skill(id) for _,k in ipairs(state.player.skills) do if k==id then return true end end return false end

local function skill_desc(s)
    local t
    if s.effect=="shot" then t="伤害 x"..s.dmg_mult..((s.multi and s.multi>1) and ("  ×"..s.multi.."连发") or "")
    elseif s.effect=="dot" then t="毒伤 "..s.dot_dur.."秒"
    elseif s.effect=="heal" then t="回复生命 "..math.floor(s.heal_pct*100).."%"
    else t=(s.buff=="haste" and "攻速" or "暴击").." +"..math.floor(s.buff_amt*100).."%  持续 "..s.buff_dur.."秒" end
    if s.cd and s.cd>0 then t=t.."   CD "..s.cd.."s" end
    return t
end

function skills_view.skill_row_rect(i)
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112)
    local rh,gap=sy(54),sy(6); local base=py+sy(46)
    return px+sx(10), base+(i-1)*(rh+gap), pw-sx(20), rh
end
local skill_row_rect = skills_view.skill_row_rect

function skills_view.draw()
    local sw = screen.sw
    local w,h=love.graphics.getWidth(),love.graphics.getHeight(); love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,w,h)
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112); panel(px,py,pw,ph,{0.09,0.1,0.15,0.98},UI.line,10*sw)
    love.graphics.setFont(draw.font_med); setc(UI.text); love.graphics.printf("技能",px,py+sy(8),pw,"center")
    draw.close_x(px,py,pw)
    love.graphics.setFont(draw.font_sm); setc(UI.dim); love.graphics.printf("已学技能自动用于战斗轮转 · 技能大师处学新技能",px,py+sy(30),pw,"center")
    -- 已学技能轮转预览：按 prio 降序排（战斗里的实际抢占顺序），小图标条置于标题栏左侧
    local rot={}; for _,id in ipairs(SKILL_ORDER) do if is_known_skill(id) then rot[#rot+1]=id end end
    table.sort(rot, function(p,q) return (SKILLS[p].prio or 0) > (SKILLS[q].prio or 0) end)
    if #rot>0 then
        local iw=sx(20); local rx=px+sx(14); local ry=py+sy(20)
        for k,id in ipairs(rot) do
            local s=SKILLS[id]; local cx=rx+(k-1)*iw
            -- 像素小槽底(技能色暗版硬边方块)
            local sb=sy(9)
            setc({s.color[1]*0.3,s.color[2]*0.3,s.color[3]*0.32,0.95}); rrect("fill", cx+iw/2-sb, ry-sb, sb*2, sb*2)
            setc(s.color); love.graphics.setLineWidth(math.max(1,sx(1))); rrect("line", cx+iw/2-sb, ry-sb, sb*2, sb*2); love.graphics.setLineWidth(1)
            draw_skill_icon(s, cx+iw/2, ry, sy(7))
            if k<#rot then setc(UI.dim); love.graphics.print("›", cx+iw-sx(4), ry-sy(7)) end
        end
    end
    for i,id in ipairs(SKILL_ORDER) do
        local s=SKILLS[id]; local x,y,rw,rh=skill_row_rect(i); local known=is_known_skill(id)
        panel(x,y,rw,rh, known and {s.color[1]*0.16,s.color[2]*0.16,s.color[3]*0.18,0.95} or {0.11,0.12,0.17,0.95}, known and s.color or UI.line, 8*sw)
        if known then setc(s.color); rrect("fill", x, y+sy(4), sx(3), rh-sy(8), 2*sw) end   -- 已学：左侧彩色竖条
        -- 技能像素图标槽(硬边方格 + 技能色边)
        local isz=sx(16); draw.slot(x+sx(14)-isz, y+rh/2-isz, isz*2, known and s.color or UI.line, known)
        draw_skill_icon(s, x+sx(14), y+rh/2, sx(11))
        setc(UI.text); love.graphics.setFont(draw.font); love.graphics.print(s.name, x+sx(44), y+sy(6))
        setc(UI.dim); love.graphics.setFont(draw.font_sm); love.graphics.print(skill_desc(s), x+sx(44), y+sy(28))
        if known then
            setc(UI.good); love.graphics.setFont(draw.font_sm); love.graphics.printf("已学", x, y+sy(8), rw-sx(14), "right")
        elseif s.learn.lvl then
            setc(UI.dim); love.graphics.setFont(draw.font_sm); love.graphics.printf("Lv"..s.learn.lvl.." 解锁", x, y+sy(8), rw-sx(14), "right")
        elseif s.learn.master then
            local ok=skill_cost_ok(s)
            -- 花费：金币 + 材料
            local cxx=x+rw-sx(170); love.graphics.setFont(draw.font_sm)
            icon_coin(cxx, y+rh/2, sx(6)); setc(UI.gold); love.graphics.print(s.learn.cost_g or 0, cxx+sx(10), y+rh/2-sy(7)); cxx=cxx+sx(44)
            for m,nn in pairs(s.learn.cost_mat or {}) do mat_chip(m, cxx, y+rh/2, sx(5)); setc(inv_count("mat",m)>=nn and UI.dim or UI.bad); love.graphics.print(nn, cxx+sx(8), y+rh/2-sy(7)); cxx=cxx+sx(34) end
            button(x+rw-sx(74), y+sy(12), sx(64), sy(30), "学习", ok and {0.4,0.5,0.7} or UI.btn, ok, draw.font_sm)
        end
    end
    button(px+pw/2-sx(60),py+ph-sy(36),sx(120),sy(28),"返回",{0.4,0.4,0.5},true)
end

function skills_view.hit(x,y)
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112)
    if draw.hit_close_x(x,y,px,py,pw) then state.panel_open=nil; return true end
    if hit(x,y,px+pw/2-sx(60),py+ph-sy(36),sx(120),sy(28)) then state.panel_open=nil; return true end
    for i,id in ipairs(SKILL_ORDER) do local s=SKILLS[id]
        if s.learn and s.learn.master and not is_known_skill(id) then
            local x0,y0,rw,rh=skill_row_rect(i)
            if hit(x,y, x0+rw-sx(74), y0+sy(12), sx(64), sy(30)) then learn_skill(id); return true end
        end
    end
    return true
end

return skills_view
