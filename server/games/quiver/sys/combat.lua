-- ============================================================================
-- sys/combat —— 战斗：敌人生成/掉落、唯一发射入口 do_shot、技能轮转 cast_skill、
--   命中/敌人攻击结算、技能大师学习，外加战斗挂机 tick（ATB 对决 + 抛射物推进 + DOT + 自动药剂）。
-- 依赖：data + core/state + sys/inventory（装备/弹药）+ sys/progression（经验/recalc）+ fx。
--   顶层 require 无环（inventory/progression 在 load 期不读 combat）。
-- ============================================================================
local D = require("data")
local state = require("core.state")
local inv = require("sys.inventory")
local prog = require("sys.progression")
local fx = require("fx")

local SKILLS = D.SKILLS
local ARROWS = D.ARROWS
local RARITIES, RAR = D.RARITIES, D.RAR
local SLOTS = D.SLOTS
local ENEMY_ARCH, ENEMY_RANK = D.ENEMY_ARCH, D.ENEMY_RANK
local CRIT_MULT = D.CRIT_MULT
local ARMOR_K = D.ARMOR_K
local ENEMY_HOME_X = D.ENEMY_HOME_X
local ENTER_TIME, DEATH_TIME = D.ENTER_TIME, D.DEATH_TIME
local DESIGN_W, DESIGN_H = D.DESIGN_W, D.DESIGN_H
local POT_COLOR = D.POT_COLOR
local UI = D.UI

-- atan2 兼容：LuaJIT(LÖVE) 有 math.atan2；标准 Lua 5.3+ 用双参 math.atan
local atan2 = math.atan2 or math.atan
-- 战斗布景的设计坐标（与抛射物共用，保证箭从弓口射出；draw_combat 在 view 侧不依赖这些）
local CB_BOW_X, CB_BOW_Y = 90, DESIGN_H*0.42-46       -- 弓口位置
local CB_ENEMY_Y = DESIGN_H*0.42-12                   -- 敌人身体中心

local combat = {}

function combat.mitigation(armor) return armor/(armor+ARMOR_K) end

function combat.make_enemy(arch_id, rank)
    rank = rank or "normal"
    local arch=ENEMY_ARCH[arch_id]; local rk=ENEMY_RANK[rank]
    -- 等级在地区区间内随机；精英/稀有也用区间随机（仅靠系数变强，不另外拔高等级）
    local lvl = math.random(state.region.lo, state.region.hi)
    local scale = 1 + (lvl-1)*0.22 + (state.stage%5)*0.04
    local hp = math.floor(60*arch.hp*scale*rk.hp)
    -- 颜色按 rank 提亮，让精英/稀有一眼可辨
    local col = { math.min(1,arch.color[1]*rk.color_mul), math.min(1,arch.color[2]*rk.color_mul), math.min(1,arch.color[3]*rk.color_mul) }
    return { arch_id=arch_id, name=(rk.tag~="" and rk.tag.." " or "")..arch.name, color=col, level=lvl, rank=rank,
        max_hp=hp, hp=hp, attack=math.floor(8*arch.dmg*scale*rk.atk), armor=math.floor(20*arch.armor*scale*rk.armor),
        spd=arch.spd, atb=0, flash=0, hurt=0, phase="enter", phase_t=0, x=DESIGN_W+60, dots={} }
end
function combat.next_enemy()
    state.stage=state.stage+1
    -- 先判稀有(更稀有)再判精英；低档地区禁用稀有，避免劝退
    local r=math.random(); local rank="normal"
    if r < ENEMY_RANK.rare.p and state.region.tier~="low" then rank="rare"
    elseif r < ENEMY_RANK.rare.p + ENEMY_RANK.elite.p then rank="elite" end
    local p=state.region.enemies; state.enemy=combat.make_enemy(p[math.random(#p)], rank)
end

function combat.drop_loot()
    prog.gain_xp(math.floor(state.enemy.level*6+10))
    state.player.gold = state.player.gold + math.floor(state.enemy.level*2+math.random(1,4))
    -- 战斗给经验/金币/装备；材料靠各类挂机采集（砍柴/采矿/采药）
    local rk = ENEMY_RANK[state.enemy.rank or "normal"]
    local drop_p = (state.enemy.rank=="normal") and 0.3 or 1.0   -- 精英/稀有保底出装
    if math.random() < drop_p then
        local ilvl = (state.enemy.rank=="normal") and math.random(state.region.ilo, state.region.ihi) or (state.region.ihi + rk.ilvl_bonus)
        local pool = (state.enemy.rank=="normal") and state.region.rar or state.region.rar_elite
        local rid  = pool[math.random(#pool)]
        if rk.rar_up>0 and math.random()<rk.rar_up then rid = RARITIES[math.min(#RARITIES, RAR[rid].tier+1)].id end
        local g = inv.roll_gear(SLOTS[math.random(#SLOTS)], ilvl, rid)
        local cur = state.player.equip[g.slot]
        if not cur or inv.gear_score(g) > inv.gear_score(cur) then
            state.player.equip[g.slot]=g; prog.recalc(); fx.set_toast("已装备 "..inv.gear_full_name(g), inv.gear_color(g))
            if cur then inv.inv_add("gear",nil,1,cur) end
        else
            inv.inv_add("gear",nil,1,g)
        end
    end
end

-- 唯一发射入口：射出一支抛射物。opts.no_ammo=主动技能不扣箭(仍享当前箭档倍率)；
-- opts.dot=命中挂持续伤害；opts.color/opts.spread 控制外观与散射角。
function combat.do_shot(mult, opts)
    opts = opts or {}
    local m, col = 0.5, {0.7,0.7,0.7}
    for i=#ARROWS,1,-1 do local id=ARROWS[i].id; if inv.ammo_count(id)>0 then
        m=ARROWS[i].mult; col=ARROWS[i].color
        if not opts.no_ammo then inv.ammo_remove(id,1) end
        break
    end end
    if not opts.no_ammo then prog.recalc() end   -- 普攻吃箭后箭档可能降级，刷新展示
    local crit = math.random()<state.player.crit
    local base = state.player.atk_min + math.random()*(state.player.atk_max-state.player.atk_min)   -- 攻击力区间内随机
    local raw = base*m*mult*(crit and CRIT_MULT or 1)
    local dmg = math.max(1, raw*(1-combat.mitigation(state.enemy.armor)))
    local tx, ty = (state.enemy and state.enemy.x or ENEMY_HOME_X), CB_ENEMY_Y
    local ang = atan2(ty-CB_BOW_Y, tx-CB_BOW_X) + (opts.spread or 0)
    state.projectiles[#state.projectiles+1] = { x=CB_BOW_X, y=CB_BOW_Y, tx=tx, ty=ty, ang=ang, dmg=dmg, crit=crit, color=opts.color or col, t=0, dot=opts.dot }
end
function combat.archer_fire() combat.do_shot(1.0, {}) end

function combat.buff_active(kind) for _,b in ipairs(state.player.buffs) do if b.kind==kind then return true end end return false end
-- 技能轮转：在可用(冷却好+情境有意义)技能里按 prio 取最高，挑不到回退普攻。
function combat.cast_skill()
    local best=nil
    for _,id in ipairs(state.player.skills) do
        local s=SKILLS[id]
        if s and (not state.player.cd[id] or state.player.cd[id]<=0) and (state.player.mp or 0) >= (s.mp_cost or 0) then
            local ok=true
            if s.effect=="heal" then ok = state.player.hp < state.player.max_hp*0.6
            elseif s.effect=="buff" then ok = not combat.buff_active(s.buff) end
            if ok and (not best or s.prio>best.prio) then best=s end
        end
    end
    if (not best) or best.id=="shoot" then combat.do_shot(1.0,{}); return end
    local s=best
    if s.effect=="shot" then
        local n=s.multi or 1
        for i=1,n do local spread=(n>1) and ((i-1)-(n-1)/2)*0.12 or 0
            combat.do_shot(s.dmg_mult, {no_ammo=true, color=s.color, spread=spread}) end
    elseif s.effect=="dot" then
        combat.do_shot(s.dmg_mult, {no_ammo=true, color=s.color, dot={mult=s.dot_mult, dur=s.dot_dur, tick=s.dot_tick, color=s.color}})
    elseif s.effect=="heal" then
        local h=math.floor(state.player.max_hp*s.heal_pct); state.player.hp=math.min(state.player.max_hp, state.player.hp+h)
        fx.add_float(DESIGN_W*0.18, DESIGN_H*0.16, "+"..h, UI.good, 1.1); fx.burst(DESIGN_W*0.18, DESIGN_H*0.42, UI.good, 8)
    elseif s.effect=="buff" then
        for i=#state.player.buffs,1,-1 do if state.player.buffs[i].kind==s.buff then table.remove(state.player.buffs,i) end end  -- 同类只刷新不叠加
        state.player.buffs[#state.player.buffs+1]={ kind=s.buff, amt=s.buff_amt, t=s.buff_dur }
        fx.add_float(DESIGN_W*0.18, DESIGN_H*0.16, s.name, s.color, 1.1)
    end
    state.player.cd[s.id]=s.cd; state.player.cast_flash[s.id]=0.4
    state.player.mp = math.max(0, (state.player.mp or 0) - (s.mp_cost or 0))   -- 释放扣法力
end

function combat.kill_enemy()
    state.enemy.hp=0; state.enemy.phase="dying"; state.enemy.phase_t=0
    local rank=state.enemy.rank or "normal"
    local n = (rank=="normal") and 16 or 32   -- 精英/稀有击破粒子翻倍
    fx.burst(state.enemy.x,DESIGN_H*0.2,state.enemy.color,n)
    if rank=="elite" then fx.add_float(state.enemy.x,DESIGN_H*0.12,"精英击破!",UI.gold,1.4)
    elseif rank=="rare" then fx.add_float(state.enemy.x,DESIGN_H*0.12,"稀有击破!",{0.78,0.5,1.0},1.4)
    else fx.add_float(state.enemy.x,DESIGN_H*0.12,"DEFEATED",UI.gold,1.2) end
    fx.shake=math.min(14,fx.shake+(rank=="normal" and 6 or 10)); combat.drop_loot()
end

-- 技能大师：学习 master 类技能（扣金币+材料）
function combat.skill_learnable(s)
    if not (s.learn and s.learn.master) then return false end
    for _,k in ipairs(state.player.skills) do if k==s.id then return false end end
    return true
end
function combat.skill_cost_ok(s)
    if state.player.gold < (s.learn.cost_g or 0) then return false end
    for m,n in pairs(s.learn.cost_mat or {}) do if inv.inv_count("mat",m)<n then return false end end
    return true
end
function combat.learn_skill(id)
    local s=SKILLS[id]; if not (combat.skill_learnable(s) and combat.skill_cost_ok(s)) then return end
    state.player.gold = state.player.gold - (s.learn.cost_g or 0)
    for m,n in pairs(s.learn.cost_mat or {}) do inv.inv_remove("mat",m,n) end
    state.player.skills[#state.player.skills+1]=id; fx.set_toast("学会技能："..s.name, s.color)
    fx.floats[#fx.floats+1]={ x=DESIGN_W*0.5, y=DESIGN_H*0.3, text=s.name, color=s.color, timer=1.4, scale=1.3, vy=-45 }
end

function combat.resolve_hit(p)
    if (not state.enemy) or state.enemy.phase~="fight" then return end   -- 敌人已死/未就绪：多重箭的后续命中作废
    state.enemy.hp=state.enemy.hp-p.dmg; state.enemy.flash=0.1; state.enemy.hurt=0.2
    fx.add_float(state.enemy.x, DESIGN_H*0.13, math.floor(p.dmg)..(p.crit and "!" or ""), p.crit and UI.gold or {1,1,1}, p.crit and 1.4 or 1)
    fx.shake=math.min(12,fx.shake+(p.crit and 5 or 2))
    if p.dot then state.enemy.dots[#state.enemy.dots+1]={ dmg=math.max(1,p.dmg*p.dot.mult), left=p.dot.dur, tick=p.dot.tick, acc=0, color=p.dot.color } end
    if state.enemy.hp<=0 then combat.kill_enemy() end
end
function combat.enemy_attack()
    local dmg=math.max(1, state.enemy.attack*(1-combat.mitigation(state.player.armor)))
    state.player.hp=state.player.hp-dmg; fx.add_float(DESIGN_W*0.18,DESIGN_H*0.16,"-"..math.floor(dmg),UI.bad); fx.shake=math.min(14,fx.shake+5)
    if state.player.hp<=0 then state.player.hp=0; state.result_banner="defeat" end
end

-- 战斗挂机 tick：抛射物推进 / 敌人入场死亡相位 / DOT / 自动药剂 / ATB 对决。
-- 仅在 activity=="combat" 时由主循环调用；非战斗推进的通用部分（冷却/mp/活动 tick）留在主循环。
function combat.tick(dt)
    if not state.enemy then combat.next_enemy() end
    if #state.projectiles>0 then
        local k=math.min(1,dt*18)
        for i=#state.projectiles,1,-1 do local p=state.projectiles[i]
            p.x=p.x+(p.tx-p.x)*k; p.y=p.y+(p.ty-p.y)*k; p.t=p.t+dt*6
            if p.t>=1 or math.abs(p.x-p.tx)<8 then combat.resolve_hit(p); table.remove(state.projectiles,i) end
        end
        return
    end
    state.enemy.flash=math.max(0,state.enemy.flash-dt); state.enemy.hurt=math.max(0,state.enemy.hurt-dt)
    if state.enemy.phase=="enter" then
        state.enemy.phase_t=state.enemy.phase_t+dt; local k=math.min(1,state.enemy.phase_t/ENTER_TIME); local e=1-(1-k)*(1-k)
        state.enemy.x=DESIGN_W+60+(ENEMY_HOME_X-(DESIGN_W+60))*e; if k>=1 then state.enemy.phase="fight"; state.enemy.x=ENEMY_HOME_X end
        return
    end
    if state.enemy.phase=="dying" then state.enemy.phase_t=state.enemy.phase_t+dt; if state.enemy.phase_t>=DEATH_TIME then combat.next_enemy() end; return end
    -- 持续伤害(DOT)结算
    for i=#state.enemy.dots,1,-1 do local d=state.enemy.dots[i]
        d.acc=d.acc+dt
        while d.acc>=d.tick and d.left>0 do
            d.acc=d.acc-d.tick; d.left=d.left-d.tick; state.enemy.hp=state.enemy.hp-d.dmg
            fx.add_float(state.enemy.x, DESIGN_H*0.15, "-"..math.floor(d.dmg), d.color, 0.9)
            if state.enemy.hp<=0 then break end
        end
        if d.left<=0 then table.remove(state.enemy.dots,i) end
    end
    if state.enemy.hp<=0 then combat.kill_enemy(); return end
    -- 药剂自动续航：HP 过低且背包有疗伤药剂则自动饮用
    if state.player.hp < state.player.max_hp*0.4 and inv.inv_count("potion","hppot")>0 then
        inv.inv_remove("potion","hppot",1); local h=math.floor(state.player.max_hp*0.3); state.player.hp=math.min(state.player.max_hp, state.player.hp+h)
        fx.add_float(DESIGN_W*0.18, DESIGN_H*0.16, "+"..h, UI.good, 1.1); fx.set_toast("自动饮用 疗伤药剂", POT_COLOR.hppot)
    end
    state.player.atb=state.player.atb+state.player.atk_speed*dt; state.enemy.atb=state.enemy.atb+state.enemy.spd*dt
    if state.player.atb>=1 then state.player.atb=0; combat.cast_skill() elseif state.enemy.atb>=1 then state.enemy.atb=0; combat.enemy_attack() end
end

return combat
