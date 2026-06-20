-- ============================================================================
-- view/combat_view —— 战斗场景（像素世界）：暮色天空/地面/远景 + 主角骨骼火柴人
--   + 敌人像素精灵(入场/死亡过程) + 抛射物，全部画进低分场景画布(240x400)再最近邻放大。
-- HUD(玩家 HP/MP/ATB 三条 + 技能槽)留在设计空间(480x800)叠在上层，换像素皮(扁平+硬边)。
-- 纯绘制(immediate-mode)，无命中：战斗交互全自动，场景无可点元素。逻辑(ATB/技能/元素/抗性)不变。
-- 依赖：base/screen + base/draw + view/sprites + core/state + fx + sys/combat + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local sprites = require("view.sprites")
local state = require("core.state")
local fx = require("fx")
local combat = require("sys.combat")
local D = require("data")
local UI = D.UI
local P = D.PIX
local SKILLS = D.SKILLS
local DESIGN_W, DESIGN_H = D.DESIGN_W, D.DESIGN_H
local ENTER_TIME, DEATH_TIME = D.ENTER_TIME, D.DEATH_TIME

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local setc = draw.setc
local panel, bar, ring, rrect = draw.panel, draw.bar, draw.ring, draw.rrect
local draw_skill_icon = draw.draw_skill_icon
local buff_active = combat.buff_active
local to_sx, to_sy = screen.to_scene_x, screen.to_scene_y

local function C(c,a) love.graphics.setColor(c[1],c[2],c[3],a or 1) end
local function lerp(a,b,t) return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t} end

local combat_view = {}

-- 敌人 → 精灵名（按 arch_id 精确，退家族，再退 slime）。纯查表，不碰战斗逻辑。
local function enemy_sprite(e)
    return (e.arch_id and D.ENEMY_SPRITE[e.arch_id])
        or (e.family and D.ENEMY_SPRITE_FAMILY[e.family])
        or "slime"
end

-- ── 暮色像素背景：共用 sprites.draw_backdrop（战斗场景走"出门小径"版）。──
local SW, SH = screen.SCENE_W, screen.SCENE_H
local HOR = sprites.HOR
local function draw_backdrop()
    sprites.draw_backdrop({ path=true })
end

function combat_view.draw()
    -- ── 像素世界：场景画布 ──
    screen.begin_scene()
    draw_backdrop()
    -- 主角站在小径左侧、地面线上。弓随 ATB 张满；刚发射(箭在飞)→松弦放箭手感。
    local hx = math.floor(SW*0.24); local gy = HOR + math.floor((SH-HOR)*0.45)
    local draw_amt = math.min(1, (state.player.atb or 0))
    if #state.projectiles > 0 then draw_amt = 0 end   -- 放箭瞬间松弦
    sprites.draw_hero(hx, gy, draw.t, "bow", nil, draw_amt)
    -- 敌人像素精灵（design x → 场景 x；y 与主角同地面线）
    if state.enemy then
        local hurt = state.enemy.hurt or 0
        local ex = to_sx(state.enemy.x) + hurt*6   -- 受击向后(右)顿挫
        local ey = gy
        local alpha,scl = 1,1
        if state.enemy.phase=="dying" then local k=math.min(1,state.enemy.phase_t/DEATH_TIME); alpha=1-k; scl=1+k*0.4
        elseif state.enemy.phase=="enter" then alpha=math.min(1,state.enemy.phase_t/(ENTER_TIME*0.5)) end
        local pscale = math.max(2, math.floor(5*scl + hurt*1.5))
        love.graphics.setColor(1,1,1,alpha)
        if state.enemy.flash and state.enemy.flash>0 then
            -- 受击白闪：用白色覆盖整精灵（画一遍纯白方块近似）
            local nm = enemy_sprite(state.enemy); local m = sprites.M[nm] or sprites.M.slime
            local w=#m.rows[1]*pscale; local h=#m.rows*pscale
            love.graphics.setColor(1,1,1,alpha)
            love.graphics.rectangle("fill", math.floor(ex-w/2), math.floor(ey-h*0.85), w, h)
        else
            love.graphics.setColor(1,1,1,alpha)
            sprites.draw_monster(enemy_sprite(state.enemy), ex, ey-pscale*5, pscale, true)
        end
        -- 精英/稀有光环
        if state.enemy.rank=="elite" or state.enemy.rank=="rare" then
            local hc = (state.enemy.rank=="rare") and {0.78,0.5,1.0} or P.acc
            love.graphics.setColor(hc[1],hc[2],hc[3], alpha*(0.55+0.25*math.sin(fx.t_accum*5)))
            love.graphics.setLineWidth(1); love.graphics.circle("line",ex,ey-pscale*5,pscale*7)
        end
    end
    -- 抛射物（p.x/p.y 是设计坐标 480x800 → 场景坐标 240x400）
    for _,p in ipairs(state.projectiles) do
        C(p.crit and UI.gold or p.color); love.graphics.setLineWidth(2)
        local hx2,hy2 = to_sx(p.x), to_sy(p.y)
        local ca,sa = math.cos(p.ang or 0), math.sin(p.ang or 0)
        love.graphics.line(hx2-ca*7, hy2-sa*7, hx2, hy2)
        love.graphics.polygon("fill", hx2,hy2, hx2-ca*3-sa*1.5, hy2-sa*3+ca*1.5, hx2-ca*3+sa*1.5, hy2-sa*3-ca*1.5)
        love.graphics.setLineWidth(1)
    end
    screen.end_scene()

    -- ── HUD（设计空间 480x800，像素扁平皮）──
    -- 敌人血条/名字浮在敌人头顶（用屏幕坐标，对齐场景里的敌人）
    local px,py = sx(70), DESIGN_H*0.42*screen.sh
    if state.enemy and state.enemy.phase=="fight" then
        local ex = state.enemy.x*screen.sw; local ey = py
        bar(ex-sx(60),ey-sy(60),sx(120),sy(11),state.enemy.hp/state.enemy.max_hp,UI.bad,math.floor(state.enemy.hp))
        bar(ex-sx(60),ey-sy(47),sx(120),sy(5),state.enemy.atb,{0.9,0.7,0.3})
        setc(state.enemy.rank=="rare" and {0.78,0.5,1.0} or state.enemy.rank=="elite" and UI.gold or UI.text)
        love.graphics.setFont(draw.font_sm); love.graphics.printf(state.enemy.name.." Lv"..state.enemy.level, ex-sx(70), ey-sy(76), sx(140), "center")
    end
    -- 玩家三条（锚在主角脚下：场景里主角约 design x≈115 / y≈600）
    local atbcol = buff_active("haste") and {0.4,0.95,0.95} or {0.4,0.7,1.0}
    local bx = sx(60); local by = sy(640)
    bar(bx,by,sx(110),sy(12),state.player.hp/state.player.max_hp,UI.good,math.floor(state.player.hp).."/"..state.player.max_hp)
    bar(bx,by+sy(14),sx(110),sy(9),(state.player.mp or 0)/(state.player.max_mp or 1),{0.35,0.55,0.95},"MP "..math.floor(state.player.mp or 0))
    bar(bx,by+sy(25),sx(110),sy(5),state.player.atb,atbcol)
    -- 技能栏：横排已学技能 + 冷却环 + 释放白闪
    local n=#state.player.skills; local sz=sx(16); local gap=sx(10); local total=n*(sz*2)+(n-1)*gap
    local sx0=(love.graphics.getWidth()-total)/2; local sy0=sy(700)
    for i,id in ipairs(state.player.skills) do
        local s=SKILLS[id]; local cxc=sx0+(i-1)*(sz*2+gap)+sz; local cyc=sy0
        local flash=state.player.cast_flash[id] or 0; local fs=1+(flash>0 and 0.15 or 0)
        panel(cxc-sz, cyc-sz, sz*2, sz*2, {s.color[1]*0.16,s.color[2]*0.16,s.color[3]*0.18,0.95}, s.color)
        draw_skill_icon(s, cxc, cyc, sz*0.7*fs)
        local cd=state.player.cd[id]
        if cd and s.cd>0 then
            love.graphics.setColor(0,0,0,0.55); rrect("fill",cxc-sz,cyc-sz,sz*2,sz*2)
            ring(cxc, cyc, sz*0.8, 1-cd/s.cd, s.color)
        end
        if flash>0 then love.graphics.setColor(1,1,1,flash*1.6); rrect("line",cxc-sz,cyc-sz,sz*2,sz*2) end
    end
end

return combat_view
