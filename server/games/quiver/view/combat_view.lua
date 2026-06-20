-- ============================================================================
-- view/combat_view —— 战斗场景：弓手 + 敌人(入场/死亡过程) + 抛射物 + 玩家三条(HP/MP/ATB) + 技能栏。
-- 纯绘制(immediate-mode)，无命中：战斗交互全自动，场景无可点元素。
-- 依赖：base/screen + base/draw + core/state + fx + sys/combat(buff_active) + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local state = require("core.state")
local fx = require("fx")
local combat = require("sys.combat")
local D = require("data")
local UI = D.UI
local SKILLS = D.SKILLS
local DESIGN_H = D.DESIGN_H
local ENTER_TIME, DEATH_TIME = D.ENTER_TIME, D.DEATH_TIME

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local setc = draw.setc
local panel, bar, ring, rrect = draw.panel, draw.bar, draw.ring, draw.rrect
local draw_archer, draw_skill_icon = draw.draw_archer, draw.draw_skill_icon
local buff_active = combat.buff_active

local combat_view = {}

function combat_view.draw()
    local sw, sh = screen.sw, screen.sh
    local px,py = sx(70), DESIGN_H*0.42*sh
    draw_archer(px,py,"bow")
    if state.enemy then
        local ex,ey = state.enemy.x*sw, py; local alpha,scl=1,1
        if state.enemy.phase=="dying" then local k=math.min(1,state.enemy.phase_t/DEATH_TIME); alpha=1-k; scl=1+k*0.4
        elseif state.enemy.phase=="enter" then alpha=math.min(1,state.enemy.phase_t/(ENTER_TIME*0.5)) end
        local r=sx(30)*(1+state.enemy.hurt*0.3)*scl
        if state.enemy.flash>0 then love.graphics.setColor(1,1,1,alpha) else setc(state.enemy.color,alpha) end
        love.graphics.circle("fill",ex,ey-r*0.4,r); love.graphics.setColor(0.1,0.1,0.12,alpha)
        love.graphics.circle("fill",ex-r*0.32,ey-r*0.5,r*0.13); love.graphics.circle("fill",ex+r*0.32,ey-r*0.5,r*0.13)
        -- 精英/稀有光环：金/紫描边，一眼看出是硬货
        if state.enemy.rank=="elite" or state.enemy.rank=="rare" then
            local hc = (state.enemy.rank=="rare") and {0.78,0.5,1.0} or UI.gold
            love.graphics.setColor(hc[1],hc[2],hc[3], alpha*(0.55+0.25*math.sin(fx.t_accum*5)))
            love.graphics.setLineWidth(math.max(2,sx(2.5))); love.graphics.circle("line",ex,ey-r*0.4,r+sx(5)); love.graphics.setLineWidth(1)
        end
        if state.enemy.phase=="fight" then
            bar(ex-sx(60),ey+sy(18),sx(120),sy(11),state.enemy.hp/state.enemy.max_hp,UI.bad,math.floor(state.enemy.hp))
            bar(ex-sx(60),ey+sy(32),sx(120),sy(5),state.enemy.atb,{0.9,0.7,0.3})
            -- 敌人名+等级（精英/稀有名字已带前缀）
            setc(state.enemy.rank=="rare" and {0.78,0.5,1.0} or state.enemy.rank=="elite" and UI.gold or UI.dim)
            love.graphics.setFont(draw.font_sm); love.graphics.printf(state.enemy.name.." Lv"..state.enemy.level, ex-sx(60), ey-r-sy(18), sx(120), "center")
        end
    end
    for _,p in ipairs(state.projectiles) do
        setc(p.crit and UI.gold or p.color); love.graphics.setLineWidth(math.max(2,sx(2.5)))
        local hx,hy = p.x*sw, p.y*sh
        local ca,sa = math.cos(p.ang or 0), math.sin(p.ang or 0)
        love.graphics.line(hx-ca*sx(14), hy-sa*sx(14), hx, hy)
        love.graphics.polygon("fill", hx,hy, hx-ca*sx(6)-sa*sx(3), hy-sa*sx(6)+ca*sx(3), hx-ca*sx(6)+sa*sx(3), hy-sa*sx(6)-ca*sx(3))
        love.graphics.setLineWidth(1)
    end
    -- 玩家：增益生效时 atb 条染色提示
    local atbcol = buff_active("haste") and {0.4,0.95,0.95} or {0.4,0.7,1.0}
    bar(px-sx(38),py+sy(30),sx(100),sy(11),state.player.hp/state.player.max_hp,UI.good,math.floor(state.player.hp).."/"..state.player.max_hp)
    bar(px-sx(38),py+sy(43),sx(100),sy(8),(state.player.mp or 0)/(state.player.max_mp or 1),{0.35,0.55,0.95},"MP "..math.floor(state.player.mp or 0))
    bar(px-sx(38),py+sy(54),sx(100),sy(4),state.player.atb,atbcol)
    -- 技能栏：横排已学技能 + 冷却回充环 + 释放白闪（看得见技能在放）
    local n=#state.player.skills; local sz=sx(16); local gap=sx(10); local total=n*(sz*2)+(n-1)*gap
    local sx0=(love.graphics.getWidth()-total)/2; local sy0=py+sy(72)
    for i,id in ipairs(state.player.skills) do
        local s=SKILLS[id]; local cxc=sx0+(i-1)*(sz*2+gap)+sz; local cyc=sy0
        local flash=state.player.cast_flash[id] or 0; local fs=1+(flash>0 and 0.15 or 0)
        panel(cxc-sz, cyc-sz, sz*2, sz*2, {s.color[1]*0.16,s.color[2]*0.16,s.color[3]*0.18,0.95}, s.color, 6*sw)
        draw_skill_icon(s, cxc, cyc, sz*0.7*fs)
        local cd=state.player.cd[id]
        if cd and s.cd>0 then
            love.graphics.setColor(0,0,0,0.55); rrect("fill",cxc-sz,cyc-sz,sz*2,sz*2,6*sw)
            ring(cxc, cyc, sz*0.8, 1-cd/s.cd, s.color)
        end
        if flash>0 then love.graphics.setColor(1,1,1,flash*1.6); rrect("line",cxc-sz,cyc-sz,sz*2,sz*2,6*sw) end
    end
end

return combat_view
