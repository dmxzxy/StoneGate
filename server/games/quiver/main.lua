-- ============================================================================
-- QUIVER — 挂机弓箭手（WoW 式装备栏 + 箭矢消耗经济 + 地区/升级）
-- 纯 LÖVE2D，无依赖，无资源。
--
-- 两条战力腿：
--   · 装备(永久)：WoW 式多格装备栏 → 主属性(力/敏/耐) → 攻击/攻速/HP/暴击
--   · 箭矢(流动)：用原材料制作分档箭，战斗消耗；高级箭打光自动降级 → 催你补料
-- 战斗是按攻速驱动的回合制对决(ATB)，一个个有分量的敌人，带入场/死亡过程。
--
-- ★ 数值锚点（一切由此推导，自洽不膨胀）：
--   1 STR=+1攻击 ; 1 AGI=+0.6%攻速+0.04%暴击 ; 1 STA=+6生命
--   装备预算 budget = GEAR_BUDGET * ilvl * rarity.mult * slot.weight
--   箭矢伤害 = 攻击 × 箭档倍率（打光降级，无箭则 0.5）
--   角色每级 +2力 +2敏 +3耐（慢），经验需求 80*L^1.6
--
-- 之后(roadmap)：挂机砍树/挖矿/制造 作为材料来源；副本掉紫橙。
-- ============================================================================

local DESIGN_W, DESIGN_H = 480, 800
local sw, sh = 1, 1
local font, font_sm, font_med, font_big
local t_accum, shake = 0, 0
local ENTER_TIME, DEATH_TIME = 0.6, 0.6
local ENEMY_HOME_X = DESIGN_W * 0.72
local GEAR_BUDGET = 4
local CRIT_MULT = 2.0
local ARMOR_K = 160

-- ============================================================================
-- 数据
-- ============================================================================
local RARITIES = {
    { id="uncommon",  name="优秀",  mult=1.0, affixes=1, color={0.4,0.85,0.4},  src="field"   },
    { id="rare",      name="精良",  mult=1.6, affixes=2, color={0.35,0.6,1.0},  src="field"   },
    { id="epic",      name="史诗",  mult=2.6, affixes=3, color={0.75,0.4,1.0},  src="dungeon" },
    { id="legendary", name="传说",  mult=4.0, affixes=4, color={1.0,0.62,0.15}, src="dungeon" },
}
local RAR = {}; for i,r in ipairs(RARITIES) do RAR[r.id]=r; r.tier=i end

-- WoW 式装备栏：左列防具，右列武器/首饰。kind 决定主属性，w 是该槽预算权重。
local SLOTS = { "head","shoulder","chest","hands","legs","feet","neck","ring","trinket","bow","quiver" }
local SLOT_INFO = {
    head     = { name="头部",   kind="armor",   w=0.9,  col="L" },
    shoulder = { name="肩部",   kind="armor",   w=0.75, col="L" },
    chest    = { name="胸甲",   kind="armor",   w=1.0,  col="L" },
    hands    = { name="护手",   kind="armor",   w=0.75, col="L" },
    legs     = { name="腿甲",   kind="armor",   w=1.0,  col="L" },
    feet     = { name="鞋子",   kind="armor",   w=0.75, col="L" },
    neck     = { name="项链",   kind="jewelry", w=0.56, col="R" },
    ring     = { name="戒指",   kind="jewelry", w=0.56, col="R" },
    trinket  = { name="饰品",   kind="jewelry", w=0.7,  col="R" },
    bow      = { name="弓",     kind="weapon",  w=2.0,  col="R" },
    quiver   = { name="箭袋",   kind="quiver",  w=0.7,  col="R" },
}
local SLOTS_L = { "head","shoulder","chest","hands","legs","feet" }
local SLOTS_R = { "neck","ring","trinket","bow","quiver" }
local TIER_PREFIX = { "破旧", "精铁", "精钢", "符文", "巨龙" }

local ATTRS = { "str","agi","sta" }
local ATTR_NAME = { str="力量", agi="敏捷", sta="耐力" }
local ATTR_COLOR = { str={0.9,0.4,0.35}, agi={0.5,0.85,0.55}, sta={0.6,0.7,0.95} }

local AFFIXES = {
    { key="str", name="+%d 力量" }, { key="agi", name="+%d 敏捷" },
    { key="sta", name="+%d 耐力" }, { key="crit", name="暴击 +%d%%", pct=true },
}

-- 原材料：每种由一类挂机产出
local MATERIALS = { "wood","ore","herb" }
local MAT_NAME = { wood="木材", ore="矿石", herb="草药" }
local MAT_COLOR = { wood={0.62,0.44,0.24}, ore={0.7,0.72,0.78}, herb={0.45,0.8,0.45} }

-- 箭矢分档（低→高）。mult 乘在攻击上；cost 是制作 BATCH 支的材料。
local ARROW_BATCH = 20
local ARROW_TIERS = {
    { id="wood",   name="木箭",   mult=1.0,  color={0.62,0.46,0.26}, cost={ wood=3 } },
    { id="iron",   name="铁箭",   mult=1.35, color={0.72,0.74,0.8},  cost={ wood=2, ore=3 } },
    { id="hunter", name="猎手箭", mult=1.75, color={0.5,0.85,0.55},  cost={ wood=2, ore=2, herb=3 } },
    { id="rune",   name="符文箭", mult=2.3,  color={0.78,0.5,1.0},   cost={ wood=3, ore=4, herb=4 } },
}

-- 挂机活动：一次只挂一种。gather 产材料，fletch 制箭，combat 打怪，rest 啥也不干。
local ACTIVITIES = {
    rest    = { name="休息",     kind="rest" },
    woodcut = { name="砍柴",     kind="gather", mat="wood", base=0.8 },
    mining  = { name="采矿",     kind="gather", mat="ore",  base=0.6 },
    herb    = { name="采药",     kind="gather", mat="herb", base=0.7 },
    fletch  = { name="制箭",     kind="craft" },
    combat  = { name="战斗",     kind="combat" },
}
local ACT_ORDER = { "rest", "woodcut", "mining", "herb", "fletch", "combat" }
local FLETCH_BASE = 0.25   -- 每秒每级的「制作进度」(满 1 出一批)

local REGIONS = {
    { id="meadow", name="绿野",     level=1,  ilvl=3,  rar={"uncommon","uncommon","rare"}, enemies={"boar","wolf"} },
    { id="forest", name="幽暗森林", level=6,  ilvl=10, rar={"uncommon","rare","rare"},     enemies={"wolf","bandit","ogre"} },
    { id="ruins",  name="沉没遗迹", level=14, ilvl=20, rar={"rare","rare","epic"},         enemies={"bandit","ogre","wraith"} },
    { id="peak",   name="霜寒峰",   level=24, ilvl=32, rar={"rare","epic","epic"},         enemies={"ogre","wraith","golem"} },
}
local ENEMY_ARCH = {
    boar  ={ name="野猪",   hp=1.0, dmg=1.0, armor=0.3, spd=0.55, color={0.6,0.45,0.35} },
    wolf  ={ name="野狼",   hp=0.8, dmg=1.2, armor=0.2, spd=0.85, color={0.5,0.5,0.55} },
    bandit={ name="强盗",   hp=1.1, dmg=1.1, armor=0.5, spd=0.6,  color={0.7,0.5,0.3} },
    ogre  ={ name="食人魔", hp=1.8, dmg=1.5, armor=0.6, spd=0.4,  color={0.45,0.6,0.3} },
    wraith={ name="幽魂",   hp=1.2, dmg=1.6, armor=0.3, spd=0.7,  color={0.55,0.45,0.75} },
    golem ={ name="石巨人", hp=2.6, dmg=1.4, armor=1.2, spd=0.35, color={0.6,0.62,0.68} },
}

local UI = {
    bg={0.07,0.08,0.12}, panel={0.12,0.13,0.19,0.97}, line={0.26,0.28,0.36},
    text={0.93,0.94,0.97}, dim={0.55,0.57,0.64}, good={0.4,0.85,0.5}, bad={0.88,0.3,0.3},
    gold={1.0,0.84,0.25}, xp={0.45,0.6,1.0}, btn={0.25,0.55,1.0},
}

-- ============================================================================
-- 状态
-- ============================================================================
local player, enemy, stage, region
local floats, particles, projectile
local activity = "rest"      -- 当前挂机活动：rest|woodcut|mining|herb|fletch|combat
local panel_open = nil       -- 覆盖菜单：nil|"activity"|"gear"|"region"
local result_banner, toast
local swing = 0              -- 采集挥动动画相位

-- atan2 兼容：LuaJIT(LÖVE) 有 math.atan2；标准 Lua 5.3+ 用双参 math.atan
local atan2 = math.atan2 or math.atan

local function sx(v) return v*sw end
local function sy(v) return v*sh end

-- ============================================================================
-- 装备
-- ============================================================================
local function roll_gear(slot, ilvl, rarity_id)
    local info = SLOT_INFO[slot]; local r = RAR[rarity_id]
    local budget = GEAR_BUDGET * ilvl * r.mult * info.w
    local g = { slot=slot, ilvl=ilvl, rarity=rarity_id, stats={}, affixes={} }
    if info.kind == "weapon" then
        g.stats.weapon_attack = math.max(1, math.floor(budget))
    elseif info.kind == "quiver" then
        g.stats.agi = math.max(1, math.floor(budget))
    elseif info.kind == "armor" then
        g.stats.sta = math.max(1, math.floor(budget*0.7))
        g.stats.armor = math.max(1, math.floor(budget*0.6))
    else -- jewelry：随机一条主属性
        local a = ATTRS[math.random(#ATTRS)]
        g.stats[a] = math.max(1, math.floor(budget))
    end
    g.name = TIER_PREFIX[math.min(#TIER_PREFIX, 1+math.floor(ilvl/8))] .. info.name
    local pool = {}; for _,a in ipairs(AFFIXES) do pool[#pool+1]=a end
    for _=1, r.affixes do
        if #pool==0 then break end
        local a = table.remove(pool, math.random(#pool))
        local val = a.pct and math.max(1,math.floor(budget*0.012)) or math.max(1,math.floor(budget*0.3))
        g.affixes[#g.affixes+1] = { key=a.key, val=val, pct=a.pct }
    end
    return g
end

local function add_gear_stats(g, acc)
    for k,v in pairs(g.stats) do acc[k]=(acc[k] or 0)+v end
    for _,af in ipairs(g.affixes) do
        if af.key=="crit" then acc.crit_pct=(acc.crit_pct or 0)+af.val
        else acc[af.key]=(acc[af.key] or 0)+af.val end
    end
end
local function gear_score(g)
    local a={}; add_gear_stats(g,a)
    return (a.weapon_attack or 0)*2 +(a.str or 0)+(a.agi or 0)+(a.sta or 0)*0.8+(a.armor or 0)*0.5+(a.crit_pct or 0)*4
end
local function gear_color(g) return RAR[g.rarity].color end
local function gear_full_name(g) return RAR[g.rarity].name.." "..g.name end

-- ============================================================================
-- 角色属性聚合（锚点换算）
-- ============================================================================
local function recalc()
    local a = { str=player.base_str, agi=player.base_agi, sta=player.base_sta }
    for _,slot in ipairs(SLOTS) do local g=player.equip[slot]; if g then add_gear_stats(g,a) end end
    local wa = a.weapon_attack or 0
    player.str=a.str; player.agi=a.agi; player.sta=a.sta; player.armor=a.armor or 0
    player.attack    = 5 + wa + player.str
    player.atk_speed = 0.55 * (1 + player.agi*0.006)
    player.crit      = math.min(0.6, 0.05 + player.agi*0.0004 + (a.crit_pct or 0)*0.01)
    player.max_hp    = 60 + player.sta*6
    if player.hp==nil or player.hp>player.max_hp then player.hp=player.max_hp end
    -- 当前箭档倍率（用于 DPS 估算与显示）
    player.arrow_mult, player.arrow_tier = 0.5, nil
    for i=#ARROW_TIERS,1,-1 do if (player.arrows[ARROW_TIERS[i].id] or 0)>0 then player.arrow_mult=ARROW_TIERS[i].mult; player.arrow_tier=ARROW_TIERS[i]; break end end
    local cf = 1 + player.crit*(CRIT_MULT-1)
    player.dps = player.attack * player.arrow_mult * cf * player.atk_speed
end

-- ============================================================================
-- 升级
-- ============================================================================
local function xp_need(lv) return math.floor(80*(lv^1.6)) end
local function gain_xp(amount)
    player.xp = player.xp + amount
    while player.xp >= player.xp_next do
        player.xp = player.xp - player.xp_next
        player.level = player.level + 1
        player.base_str = player.base_str + 2
        player.base_agi = player.base_agi + 2
        player.base_sta = player.base_sta + 3
        player.xp_next = xp_need(player.level); recalc(); player.hp = player.max_hp
        floats[#floats+1]={ x=DESIGN_W*0.18, y=DESIGN_H*0.14, text="LEVEL "..player.level, color=UI.xp, timer=1.4, scale=1.4, vy=-50 }
    end
end

-- ============================================================================
-- 箭矢制作
-- ============================================================================
local function can_craft(tier)
    for m,n in pairs(tier.cost) do if (player.mats[m] or 0) < n then return false end end
    return true
end
local function craft(tier)
    if not can_craft(tier) then return end
    for m,n in pairs(tier.cost) do player.mats[m] = player.mats[m] - n end
    player.arrows[tier.id] = (player.arrows[tier.id] or 0) + ARROW_BATCH
    recalc()
end

-- ============================================================================
-- 挂机活动：一次只挂一种。gather 产对应材料；fletch 一组组制箭；combat 在下面。
-- 技能等级越高，对应活动越快；升级在活动菜单里花金币。
-- ============================================================================
local function skill_cost(lvl) return math.floor(15 * (lvl ^ 1.7) + 10) end
local function upgrade_skill(key)
    local c = skill_cost(player.skill[key] or 1)
    if player.gold >= c then player.gold = player.gold - c; player.skill[key] = (player.skill[key] or 1) + 1 end
end

-- 当前 fletch 目标：能负担的最高档（返回 tier 或 nil）
local function best_affordable_tier()
    for i = #ARROW_TIERS, 1, -1 do if can_craft(ARROW_TIERS[i]) then return ARROW_TIERS[i] end end
    return nil
end

local function activity_tick(dt)
    local a = ACTIVITIES[activity]
    if a.kind == "gather" then
        local lvl = player.skill[activity] or 1
        player.acc = (player.acc or 0) + a.base * lvl * dt
        while player.acc >= 1 do
            player.mats[a.mat] = (player.mats[a.mat] or 0) + 1
            player.acc = player.acc - 1
            -- 采集碎屑（juice）
            local nx,ny = DESIGN_W*0.68, DESIGN_H*0.42
            for _=1,3 do local ang=math.random()*math.pi*2; local s=30+math.random()*80
                particles[#particles+1]={x=nx,y=ny,vx=math.cos(ang)*s,vy=math.sin(ang)*s-30,life=0.3+math.random()*0.3,max=0.6,size=2+math.random()*3,color=MAT_COLOR[a.mat]} end
        end
    elseif a.kind == "craft" then
        local lvl = player.skill.fletch or 1
        -- 按选定的图纸制造（材料够才生产）
        local bp = player.fletch_blueprint or "wood"
        local tier; for _,t in ipairs(ARROW_TIERS) do if t.id==bp then tier=t end end
        player.fletch_target = tier
        if tier and can_craft(tier) then
            player.fletch_prog = (player.fletch_prog or 0) + FLETCH_BASE * lvl * dt
            if player.fletch_prog >= 1 then
                player.fletch_prog = player.fletch_prog - 1
                craft(tier)
            end
        else
            player.fletch_prog = 0
        end
    end
end

-- ============================================================================
-- 战斗
-- ============================================================================
local function mitigation(armor) return armor/(armor+ARMOR_K) end

local function make_enemy(arch_id)
    local arch=ENEMY_ARCH[arch_id]; local lvl=region.level
    local scale = 1 + (lvl-1)*0.22 + (stage%5)*0.04
    local hp = math.floor(60*arch.hp*scale)
    return { arch_id=arch_id, name=arch.name, color=arch.color, level=lvl,
        max_hp=hp, hp=hp, attack=math.floor(8*arch.dmg*scale), armor=math.floor(20*arch.armor*scale),
        spd=arch.spd, atb=0, flash=0, hurt=0, phase="enter", phase_t=0, x=DESIGN_W+60 }
end
local function next_enemy() stage=stage+1; local p=region.enemies; enemy=make_enemy(p[math.random(#p)]) end
local function add_float(x,y,txt,col,scale) floats[#floats+1]={x=x,y=y,text=txt,color=col or UI.text,timer=1.0,scale=scale or 1,vy=-45} end
local function burst(x,y,c,n) for _=1,n do local a=math.random()*math.pi*2; local s=40+math.random()*150; particles[#particles+1]={x=x,y=y,vx=math.cos(a)*s,vy=math.sin(a)*s-40,life=0.4+math.random()*0.4,max=0.8,size=2+math.random()*4,color=c} end end
local function set_toast(t,c) toast={text=t,color=c or UI.text,timer=2.5} end

local function drop_loot()
    gain_xp(math.floor(enemy.level*6+10))
    player.gold = player.gold + math.floor(enemy.level*2+math.random(1,4))
    -- 战斗给经验/金币/装备；材料靠各类挂机采集（砍柴/采矿/采药）
    if math.random() < 0.3 then
        local rid = region.rar[math.random(#region.rar)]
        local g = roll_gear(SLOTS[math.random(#SLOTS)], region.ilvl, rid)
        local cur = player.equip[g.slot]
        if not cur or gear_score(g) > gear_score(cur) then
            if cur then player.bag[#player.bag+1]=cur end
            player.equip[g.slot]=g; recalc(); set_toast("已装备 "..gear_full_name(g), gear_color(g))
        elseif #player.bag<24 then player.bag[#player.bag+1]=g end
    end
end

-- 战斗布景的设计坐标（draw_combat 与抛射物共用，保证箭从弓口射出）
local CB_ARCHER_X, CB_ARCHER_Y = 70, DESIGN_H*0.42   -- 弓箭手脚底
local CB_BOW_X, CB_BOW_Y = 90, DESIGN_H*0.42-46       -- 弓口位置
local CB_ENEMY_Y = DESIGN_H*0.42-12                   -- 敌人身体中心

local function archer_fire()
    -- 取最高可用箭档，消耗 1 支；无箭则简易箭(0.5x)
    local mult, tier = 0.5, nil
    for i=#ARROW_TIERS,1,-1 do local id=ARROW_TIERS[i].id; if (player.arrows[id] or 0)>0 then mult=ARROW_TIERS[i].mult; tier=ARROW_TIERS[i]; player.arrows[id]=player.arrows[id]-1; break end end
    if tier==nil then recalc() end
    local crit = math.random()<player.crit
    local raw = player.attack*mult*(crit and CRIT_MULT or 1)
    local dmg = math.max(1, raw*(1-mitigation(enemy.armor)))
    -- 「普通攻击」：从弓口射出的抛射物，飞向敌人身体中心
    local tx, ty = (enemy and enemy.x or ENEMY_HOME_X), CB_ENEMY_Y
    local ang = atan2(ty-CB_BOW_Y, tx-CB_BOW_X)
    projectile = { x=CB_BOW_X, y=CB_BOW_Y, tx=tx, ty=ty, ang=ang, dmg=dmg, crit=crit, color=tier and tier.color or {0.7,0.7,0.7}, t=0 }
end
local function resolve_hit(p)
    enemy.hp=enemy.hp-p.dmg; enemy.flash=0.1; enemy.hurt=0.2
    add_float(enemy.x, DESIGN_H*0.13, math.floor(p.dmg)..(p.crit and "!" or ""), p.crit and UI.gold or {1,1,1}, p.crit and 1.4 or 1)
    shake=math.min(12,shake+(p.crit and 5 or 2))
    if enemy.hp<=0 then enemy.hp=0; enemy.phase="dying"; enemy.phase_t=0; burst(enemy.x,DESIGN_H*0.2,enemy.color,16); add_float(enemy.x,DESIGN_H*0.12,"DEFEATED",UI.gold,1.2); shake=math.min(14,shake+6); drop_loot() end
end
local function enemy_attack()
    local dmg=math.max(1, enemy.attack*(1-mitigation(player.armor)))
    player.hp=player.hp-dmg; add_float(DESIGN_W*0.18,DESIGN_H*0.16,"-"..math.floor(dmg),UI.bad); shake=math.min(14,shake+5)
    if player.hp<=0 then player.hp=0; result_banner="defeat" end
end

local function update(dt)
    t_accum=t_accum+dt; shake=math.max(0,shake-dt*40); swing=swing+dt
    for i=#particles,1,-1 do local p=particles[i]; p.vy=p.vy+260*dt; p.x=p.x+p.vx*dt; p.y=p.y+p.vy*dt; p.life=p.life-dt; if p.life<=0 then table.remove(particles,i) end end
    for i=#floats,1,-1 do local f=floats[i]; f.y=f.y+f.vy*dt; f.vy=f.vy+40*dt; f.timer=f.timer-dt; if f.timer<=0 then table.remove(floats,i) end end
    if toast then toast.timer=toast.timer-dt; if toast.timer<=0 then toast=nil end end

    -- 当前挂机活动（一次只挂一种）
    activity_tick(dt)
    recalc()  -- 箭档显示随库存刷新

    if result_banner then return end
    -- 战斗只在「战斗挂机」时推进
    if activity ~= "combat" then return end
    if not enemy then next_enemy() end
    if projectile then
        local k=math.min(1,dt*18)
        projectile.x=projectile.x+(projectile.tx-projectile.x)*k
        projectile.y=projectile.y+(projectile.ty-projectile.y)*k
        projectile.t=projectile.t+dt*6
        if projectile.t>=1 or math.abs(projectile.x-projectile.tx)<8 then resolve_hit(projectile); projectile=nil end
        return
    end
    enemy.flash=math.max(0,enemy.flash-dt); enemy.hurt=math.max(0,enemy.hurt-dt)
    if enemy.phase=="enter" then
        enemy.phase_t=enemy.phase_t+dt; local k=math.min(1,enemy.phase_t/ENTER_TIME); local e=1-(1-k)*(1-k)
        enemy.x=DESIGN_W+60+(ENEMY_HOME_X-(DESIGN_W+60))*e; if k>=1 then enemy.phase="fight"; enemy.x=ENEMY_HOME_X end
        return
    end
    if enemy.phase=="dying" then enemy.phase_t=enemy.phase_t+dt; if enemy.phase_t>=DEATH_TIME then next_enemy() end; return end
    player.atb=player.atb+player.atk_speed*dt; enemy.atb=enemy.atb+enemy.spd*dt
    if player.atb>=1 then player.atb=0; archer_fire() elseif enemy.atb>=1 then enemy.atb=0; enemy_attack() end
end

-- ============================================================================
-- 初始化
-- ============================================================================
local function init()
    player = { level=1, xp=0, xp_next=xp_need(1), base_str=5, base_agi=5, base_sta=5,
        gold=0, hp=nil, equip={}, bag={}, atb=0,
        mats={ wood=8, ore=4, herb=2 }, arrows={ wood=30 },
        skill={ woodcut=1, mining=1, herb=1, fletch=1 },
        acc=0, fletch_prog=0, fletch_target=nil, fletch_blueprint="wood" }
    player.equip.bow = roll_gear("bow", 1, "uncommon")
    recalc(); player.hp=player.max_hp
    region=REGIONS[1]; stage=0; floats={}; particles={}; projectile=nil; result_banner=nil; toast=nil
    activity="rest"; panel_open=nil; enemy=nil
end

-- ============================================================================
-- 绘制工具
-- ============================================================================
local function setc(c,a) love.graphics.setColor(c[1],c[2],c[3],a or c[4] or 1) end
local function rrect(m,x,y,w,h,r) love.graphics.rectangle(m,x,y,w,h,r or 6*sw,r or 6*sw) end
local function panel(x,y,w,h,fill,border,r)
    setc(fill or UI.panel); rrect("fill",x,y,w,h,r or 8*sw)
    love.graphics.setColor(1,1,1,0.04); rrect("fill",x,y,w,h*0.42,r or 8*sw)
    if border then setc(border); love.graphics.setLineWidth(math.max(1,1.3*sw)); rrect("line",x,y,w,h,r or 8*sw); love.graphics.setLineWidth(1) end
end
local function button(x,y,w,h,label,col,enabled,fnt)
    col=col or UI.btn; if enabled==false then col={col[1]*0.35,col[2]*0.35,col[3]*0.4} end
    setc(col); rrect("fill",x,y,w,h,6*sw); love.graphics.setColor(1,1,1,0.16); rrect("fill",x+6*sw,y+1.5*sh,w-12*sw,h*0.34)
    love.graphics.setColor(0,0,0,0.22); rrect("fill",x,y+h-3*sh,w,3*sh,6*sw)
    fnt=fnt or font; love.graphics.setFont(fnt); setc(enabled==false and UI.dim or UI.text); love.graphics.printf(label,x,y+(h-fnt:getHeight())/2,w,"center")
end
local function bar(x,y,w,h,frac,col,label)
    frac=math.max(0,math.min(1,frac)); love.graphics.setColor(0,0,0,0.5); rrect("fill",x,y,w,h,h/2)
    if frac>0 then setc(col); rrect("fill",x,y,math.max(h,w*frac),h,h/2); love.graphics.setColor(1,1,1,0.2); rrect("fill",x+h/2,y+1.5*sh,math.max(0,w*frac-h),h*0.3,h*0.2) end
    if label then love.graphics.setFont(font_sm); love.graphics.setColor(1,1,1,0.95); love.graphics.printf(label,x,y+(h-font_sm:getHeight())/2,w,"center") end
end
local function mat_chip(m, x, y, s) setc(MAT_COLOR[m]); rrect("fill",x-s,y-s,s*2,s*2,s*0.4); love.graphics.setColor(0,0,0,0.3); rrect("line",x-s,y-s,s*2,s*2,s*0.4) end

-- ============================================================================
-- 图标（用图形代替文字）
-- ============================================================================
local function icon_mat(m, cx, cy, s)
    if m=="wood" then
        setc({0.55,0.38,0.2}); love.graphics.rectangle("fill",cx-s,cy-s*0.55,s*2,s*1.1,s*0.4)
        setc({0.72,0.52,0.3}); love.graphics.circle("fill",cx+s*0.7,cy,s*0.42); setc({0.45,0.3,0.16}); love.graphics.circle("line",cx+s*0.7,cy,s*0.42)
    elseif m=="ore" then
        setc({0.5,0.52,0.58}); love.graphics.polygon("fill",cx-s,cy+s*0.6,cx-s*0.4,cy-s,cx+s*0.6,cy-s*0.7,cx+s,cy+s*0.6)
        setc({0.85,0.87,0.95}); love.graphics.circle("fill",cx-s*0.1,cy-s*0.05,s*0.22); love.graphics.circle("fill",cx+s*0.4,cy+s*0.2,s*0.14)
    else -- herb
        setc({0.4,0.7,0.35}); love.graphics.ellipse("fill",cx-s*0.45,cy-s*0.1,s*0.5,s*0.95); love.graphics.ellipse("fill",cx+s*0.45,cy-s*0.1,s*0.5,s*0.95)
        setc({0.3,0.5,0.22}); love.graphics.setLineWidth(math.max(1,1.4*sw)); love.graphics.line(cx,cy-s,cx,cy+s); love.graphics.setLineWidth(1)
    end
end
local function icon_arrow(cx, cy, s, col)
    -- 斜 45° 箭：细杆 + 三角箭头 + 尾羽，更像物品图标
    local c=col or {0.8,0.8,0.85}
    local d=0.7071  -- cos45
    local tx,ty = cx+s*d, cy-s*d        -- 箭尖(右上)
    local bx,by = cx-s*d, cy+s*d        -- 箭尾(左下)
    setc({0.55,0.4,0.25}); love.graphics.setLineWidth(math.max(1.5,s*0.22))  -- 木杆
    love.graphics.line(bx,by,tx-s*0.28*d,ty+s*0.28*d)
    -- 箭头(三角)
    setc(c)
    local hx,hy = tx,ty
    love.graphics.polygon("fill", hx,hy, hx-s*0.5*d+s*0.22*d, hy+s*0.5*d+s*0.22*d, hx-s*0.5*d-s*0.22*d, hy+s*0.5*d-s*0.22*d)
    -- 尾羽(两片)
    setc({0.85,0.85,0.9}); love.graphics.setLineWidth(math.max(1,s*0.16))
    love.graphics.line(bx,by, bx+s*0.34, by-s*0.04); love.graphics.line(bx,by, bx+s*0.04, by-s*0.34)
    love.graphics.setLineWidth(1)
end
local function icon_coin(cx,cy,r)
    setc({0.78,0.58,0.12}); love.graphics.circle("fill",cx,cy,r)
    setc(UI.gold); love.graphics.circle("fill",cx,cy,r*0.7)
    setc({1,1,1,0.5}); love.graphics.circle("fill",cx-r*0.25,cy-r*0.25,r*0.18)
end

-- ============================================================================
-- 挂机活动场景（一次只画当前活动）
-- ============================================================================
-- 经典细线火柴人：细线条 + 圆头 + 明确的关节坐标（不用余弦定理，避免扭曲）
-- 比例：头半径 R；脖、躯干、四肢都用直接坐标摆出，关节弯曲清楚可控。
-- pose: idle | bow | chop
local function draw_archer(px, py, pose, phase)
    pose = pose or "idle"
    phase = phase or t_accum
    local breathe = math.sin(phase*2)*sy(1.2)
    py = py + breathe
    local R    = sx(7)            -- 头半径
    local LW   = math.max(2, sx(2))   -- 细线，约 2px
    local skin = {0.92,0.78,0.62}
    local ink  = {0.82,0.85,0.92}     -- 身体线条（浅色细线，灵动）

    -- 关节坐标
    local footL = { px-sx(8), py }
    local footR = { px+sx(8), py }
    local hip   = { px, py-sy(26) }
    local neck  = { px, py-sy(46) }
    local head  = { px, py-sy(54) }

    love.graphics.push("all")
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineWidth(LW)
    love.graphics.setLineJoin("bevel")
    setc(ink)

    -- 腿（带膝盖中继点，轻微弯曲）
    local kneeL={px-sx(5),py-sy(13)}; local kneeR={px+sx(5),py-sy(13)}
    love.graphics.line(hip[1],hip[2], kneeL[1],kneeL[2], footL[1],footL[2])
    love.graphics.line(hip[1],hip[2], kneeR[1],kneeR[2], footR[1],footR[2])
    -- 躯干
    love.graphics.line(hip[1],hip[2], neck[1],neck[2])

    -- 手臂
    if pose=="bow" then
        -- 前臂水平持弓，后臂拉弦到脸侧
        local fx,fy = px+sx(20), neck[2]+sy(1)
        local dx,dy = px-sx(2), neck[2]+sy(4)
        love.graphics.line(neck[1],neck[2], px+sx(11),neck[2]+sy(2), fx,fy)   -- 前臂(带肘)
        love.graphics.line(neck[1],neck[2], dx,dy)                            -- 后臂
        -- 弓
        setc({0.66,0.48,0.22}); love.graphics.setLineWidth(math.max(2,sx(2)))
        love.graphics.arc("line","open",fx,fy,sx(13),-1.3,1.3)
        setc({0.9,0.88,0.8}); love.graphics.setLineWidth(math.max(1,sx(1)))
        love.graphics.line(fx+sx(13)*math.cos(-1.3),fy+sx(13)*math.sin(-1.3), dx,dy, fx+sx(13)*math.cos(1.3),fy+sx(13)*math.sin(1.3))
    elseif pose=="chop" then
        -- 一臂随相位抡工具，一臂自然垂
        local amt=math.sin(phase)*0.5+0.5; local ang=-1.3+amt*1.2
        local ex,ey = px+sx(8), neck[2]+sy(6)                                  -- 肘
        local hx,hy = ex+math.cos(ang)*sx(16), ey+math.sin(ang)*sy(16)         -- 手
        love.graphics.line(neck[1],neck[2], ex,ey, hx,hy)
        love.graphics.line(neck[1],neck[2], px-sx(8),neck[2]+sy(14))
        -- 工具：柄 + 头
        local tx,ty = hx+math.cos(ang)*sx(14), hy+math.sin(ang)*sy(14)
        setc({0.5,0.36,0.22}); love.graphics.setLineWidth(math.max(2,sx(2.4))); love.graphics.line(hx,hy,tx,ty)
        setc({0.8,0.82,0.88}); love.graphics.circle("fill",tx,ty,sx(3.5))
    else
        -- 待机：双臂自然垂（带轻微肘弯）
        love.graphics.line(neck[1],neck[2], px-sx(9),neck[2]+sy(11), px-sx(7),neck[2]+sy(20))
        love.graphics.line(neck[1],neck[2], px+sx(9),neck[2]+sy(11), px+sx(7),neck[2]+sy(20))
    end

    -- 头（实心 + 细描边）
    setc(skin); love.graphics.circle("fill", head[1],head[2], R)
    setc(ink); love.graphics.setLineWidth(math.max(1,sx(1.2))); love.graphics.circle("line", head[1],head[2], R)

    love.graphics.pop()
end

-- 进度圆环（替代部分文字进度）
local function ring(cx,cy,r,frac,col)
    setc({1,1,1,0.1}); love.graphics.setLineWidth(sx(3)); love.graphics.circle("line",cx,cy,r)
    setc(col); love.graphics.arc("line","open",cx,cy,r,-math.pi/2,-math.pi/2+math.pi*2*math.max(0,math.min(1,frac))); love.graphics.setLineWidth(1)
end

local function draw_combat()
    local px,py = sx(70), DESIGN_H*0.42*sh
    draw_archer(px,py,"bow")
    if enemy then
        local ex,ey = enemy.x*sw, py; local alpha,scl=1,1
        if enemy.phase=="dying" then local k=math.min(1,enemy.phase_t/DEATH_TIME); alpha=1-k; scl=1+k*0.4
        elseif enemy.phase=="enter" then alpha=math.min(1,enemy.phase_t/(ENTER_TIME*0.5)) end
        local r=sx(30)*(1+enemy.hurt*0.3)*scl
        if enemy.flash>0 then love.graphics.setColor(1,1,1,alpha) else setc(enemy.color,alpha) end
        love.graphics.circle("fill",ex,ey-r*0.4,r); love.graphics.setColor(0.1,0.1,0.12,alpha)
        love.graphics.circle("fill",ex-r*0.32,ey-r*0.5,r*0.13); love.graphics.circle("fill",ex+r*0.32,ey-r*0.5,r*0.13)
        if enemy.phase=="fight" then
            bar(ex-sx(60),ey+sy(18),sx(120),sy(11),enemy.hp/enemy.max_hp,UI.bad,math.floor(enemy.hp))
            bar(ex-sx(60),ey+sy(32),sx(120),sy(5),enemy.atb,{0.9,0.7,0.3})
        end
    end
    if projectile then
        setc(projectile.crit and UI.gold or projectile.color); love.graphics.setLineWidth(math.max(2,sx(2.5)))
        local hx,hy = projectile.x*sw, projectile.y*sh
        local ca,sa = math.cos(projectile.ang or 0), math.sin(projectile.ang or 0)
        love.graphics.line(hx-ca*sx(14), hy-sa*sx(14), hx, hy)
        -- 箭头
        love.graphics.polygon("fill", hx,hy, hx-ca*sx(6)-sa*sx(3), hy-sa*sx(6)+ca*sx(3), hx-ca*sx(6)+sa*sx(3), hy-sa*sx(6)-ca*sx(3))
        love.graphics.setLineWidth(1)
    end
    bar(px-sx(38),py+sy(30),sx(100),sy(11),player.hp/player.max_hp,UI.good,math.floor(player.hp).."/"..player.max_hp)
    bar(px-sx(38),py+sy(44),sx(100),sy(5),player.atb,{0.4,0.7,1.0})
end

-- 采集场景（砍柴/采矿/采药）
local function draw_gather()
    local a = ACTIVITIES[activity]
    local px,py = sx(80), DESIGN_H*0.46*sh
    draw_archer(px,py,"chop",swing*5)
    -- 资源节点
    local nx,ny = DESIGN_W*0.66*sw, py
    if activity=="woodcut" then
        setc({0.35,0.25,0.15}); love.graphics.rectangle("fill",nx-sx(6),ny-sy(46),sx(12),sy(46))
        setc({0.2,0.5,0.25}); love.graphics.circle("fill",nx,ny-sy(56),sx(30)); setc({0.16,0.42,0.2}); love.graphics.circle("fill",nx-sx(12),ny-sy(48),sx(16))
    elseif activity=="mining" then
        setc({0.42,0.44,0.5}); love.graphics.polygon("fill",nx-sx(30),ny,nx-sx(16),ny-sy(38),nx+sx(12),ny-sy(32),nx+sx(30),ny)
        setc({0.7,0.72,0.78}); love.graphics.circle("fill",nx-sx(4),ny-sy(16),sx(5)); love.graphics.circle("fill",nx+sx(10),ny-sy(22),sx(4))
    else
        setc({0.2,0.45,0.2}); love.graphics.circle("fill",nx,ny-sy(12),sx(22))
        setc({0.9,0.6,0.8}); love.graphics.circle("fill",nx-sx(9),ny-sy(16),sx(5)); love.graphics.circle("fill",nx+sx(8),ny-sy(9),sx(5))
    end
    -- 顶部：材料图标 + 数量（无文字标签）
    local cx = love.graphics.getWidth()/2
    icon_mat(a.mat, cx-sx(40), py-sy(120), sx(13))
    love.graphics.setFont(font_big); setc(MAT_COLOR[a.mat]); love.graphics.print(player.mats[a.mat] or 0, cx-sx(18), py-sy(134))
    -- 等级 pips + 每单位进度环
    ring(cx, py-sy(86), sx(10), player.acc or 0, MAT_COLOR[a.mat])
end

-- 制造场景
local function draw_fletch()
    local px,py = sx(80), DESIGN_H*0.46*sh
    draw_archer(px,py,"chop",swing*6)
    setc({0.4,0.3,0.2}); love.graphics.rectangle("fill",px+sx(22),py-sy(2),sx(70),sy(10),3*sw)
    local tier = player.fletch_target
    local cx = love.graphics.getWidth()/2
    if tier and can_craft(tier) then
        -- 正在制造：大箭图标(档色) + 库存 + 进度
        icon_arrow(cx-sx(34), py-sy(116), sx(20), tier.color)
        love.graphics.setFont(font_big); setc(tier.color); love.graphics.print(player.arrows[tier.id] or 0, cx+sx(2), py-sy(130))
        love.graphics.setFont(font_sm); setc(UI.dim); love.graphics.printf("正在制造 "..tier.name, 0, py-sy(140), love.graphics.getWidth(), "center")
        bar(cx-sx(100), py-sy(84), sx(200), sy(14), player.fletch_prog or 0, tier.color)
    else
        -- 缺料：灰箭 + 该图纸所需材料(够的亮/缺的暗叉)
        icon_arrow(cx, py-sy(112), sx(20), {0.4,0.4,0.45})
        love.graphics.setFont(font_sm); setc(UI.bad); love.graphics.printf("材料不足", 0, py-sy(140), love.graphics.getWidth(), "center")
        local need = tier and tier.cost or {}
        local i=0; for m,n in pairs(need) do local mx=cx-sx(36)+i*sx(40); i=i+1
            local ok=(player.mats[m] or 0)>=n
            if not ok then love.graphics.setColor(1,1,1,0.2) end
            icon_mat(m, mx, py-sy(82), sx(11))
            setc(ok and UI.text or UI.bad); love.graphics.setFont(font_sm); love.graphics.print((player.mats[m] or 0).."/"..n, mx-sx(8), py-sy(66))
        end
    end
end

-- 休息场景
local function draw_rest()
    local cx = love.graphics.getWidth()/2
    local px,py = cx, DESIGN_H*0.46*sh
    -- 篝火
    local f = math.sin(swing*8)*0.2+0.8
    setc({0.3,0.2,0.12}); love.graphics.rectangle("fill",px-sx(18),py,sx(36),sy(7),2*sw)
    setc({1.0,0.5*f,0.15}); love.graphics.polygon("fill",px-sx(10),py,px,py-sy(28*f),px+sx(10),py)
    setc({1.0,0.8,0.3,0.85}); love.graphics.polygon("fill",px-sx(5),py,px,py-sy(14*f),px+sx(5),py)
    draw_archer(px-sx(56),py+sy(2))
    -- Zzz（图形，无说明文字）
    setc(UI.dim)
    for i=0,2 do local zs=sx(7-i*1.5); local zx,zy=px-sx(64)+i*sx(11), py-sy(78)-i*sy(14)
        love.graphics.setFont(i==0 and font_med or font_sm); love.graphics.print("z", zx, zy) end
end

-- 主视图：按当前活动渲染 + 共享粒子
local function draw_main()
    local a = ACTIVITIES[activity]
    if a.kind=="combat" then draw_combat()
    elseif a.kind=="gather" then draw_gather()
    elseif a.kind=="craft" then draw_fletch()
    else draw_rest() end
    for _,p in ipairs(particles) do local al=math.max(0,p.life/p.max); love.graphics.setColor(p.color[1],p.color[2],p.color[3],al); love.graphics.rectangle("fill",p.x*sw-p.size*sw/2,p.y*sh-p.size*sh/2,p.size*sw,p.size*sh) end
end

local function draw_hud()
    local w=love.graphics.getWidth()
    local bh=sy(46)
    love.graphics.setColor(0.05,0.06,0.1,0.94); love.graphics.rectangle("fill",0,0,w,bh)
    love.graphics.setColor(UI.btn[1],UI.btn[2],UI.btn[3],0.5); love.graphics.rectangle("fill",0,bh-2*sh,w,2*sh)
    -- 左：等级 + 经验条
    love.graphics.setFont(font_med); setc(UI.text); love.graphics.print(player.level, sx(10), sy(5))
    bar(sx(34), sy(9), sx(130), sy(10), player.xp/player.xp_next, UI.xp)
    -- 右：金币图标+数、箭矢图标(档色)+数
    icon_coin(w-sx(120), sy(15), sx(8)); setc(UI.gold); love.graphics.setFont(font_sm); love.graphics.print(player.gold, w-sx(108), sy(9))
    local acol = player.arrow_tier and player.arrow_tier.color or {0.5,0.3,0.3}
    local acnt = player.arrow_tier and (player.arrows[player.arrow_tier.id] or 0) or 0
    icon_arrow(w-sx(56), sy(15), sx(11), acol); setc(acol); love.graphics.print(acnt, w-sx(38), sy(9))
    if toast then love.graphics.setFont(font_sm); setc(toast.color,math.min(1,toast.timer)); love.graphics.printf(toast.text,0,sy(50),w-sx(10),"right") end
end

local function bottom_btns()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    love.graphics.setFont(font_sm); setc(ACTIVITIES[activity].name=="休息" and UI.dim or UI.good)
    love.graphics.printf("当前："..ACTIVITIES[activity].name, 0, h-sy(68), w, "center")
    -- 四入口：活动 / 背包 / 装备 / 地区
    local by=h-sy(46); local n=4; local gap=sx(8); local bw=(w-sx(20)-gap*(n-1))/n
    local labels={ {"活动",{0.5,0.4,0.65}}, {"背包",{0.55,0.45,0.3}}, {"装备",UI.btn}, {"地区",{0.3,0.5,0.7}} }
    for i,l in ipairs(labels) do
        button(sx(10)+(i-1)*(bw+gap), by, bw, sy(36), l[1], l[2], true, font_sm)
    end
end

-- ============================================================================
-- 地区
-- ============================================================================
local function draw_regions()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight(); love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,w,h)
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112); panel(px,py,pw,ph,{0.09,0.1,0.15,0.98},UI.line,10*sw)
    love.graphics.setFont(font_med); setc(UI.text); love.graphics.printf("地区",px,py+sy(8),pw,"center")
    love.graphics.setFont(font_sm); setc(UI.dim); love.graphics.printf("higher = better loot & materials, tougher foes",px,py+sy(30),pw,"center")
    local ry=py+sy(52); local rh=sy(72)
    for i,rg in ipairs(REGIONS) do
        local y=ry+(i-1)*(rh+sy(8)); local cur=(rg.id==region.id)
        panel(px+sx(10),y,pw-sx(20),rh,cur and {0.15,0.2,0.3,0.97} or {0.11,0.12,0.17,0.95},cur and UI.btn or UI.line,8*sw)
        love.graphics.setFont(font); setc(UI.text); love.graphics.print(rg.name,px+sx(22),y+sy(8))
        love.graphics.setFont(font_sm); setc(UI.dim); love.graphics.print("敌人 Lv "..rg.level.."   掉落装等 "..rg.ilvl,px+sx(22),y+sy(28))
        local seen={}; local dx=px+sx(22)
        for _,rid in ipairs(rg.rar) do if not seen[rid] then seen[rid]=true; setc(RAR[rid].color); love.graphics.circle("fill",dx+sx(6),y+sy(52),sx(5)); dx=dx+sx(18) end end
        if cur then setc(UI.good); love.graphics.setFont(font_sm); love.graphics.printf("当前",px+sx(10),y+sy(8),pw-sx(40),"right") end
    end
    button(px+pw/2-sx(64),py+ph-sy(40),sx(128),sy(30),"返回",{0.4,0.4,0.5},true)
end

-- ============================================================================
-- 活动选择（挂机一次只挂一种）
-- ============================================================================
local function draw_activity()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight(); love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,w,h)
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112); panel(px,py,pw,ph,{0.09,0.1,0.15,0.98},UI.line,10*sw)
    love.graphics.setFont(font_med); setc(UI.text); love.graphics.printf("活动",px,py+sy(8),pw,"center")
    love.graphics.setFont(font_sm); setc(UI.dim); love.graphics.printf("选择一项挂机任务，持续进行直到切换",px,py+sy(30),pw,"center")

    local ry=py+sy(54); local rh=sy(56)
    for i,id in ipairs(ACT_ORDER) do
        local a=ACTIVITIES[id]; local y=ry+(i-1)*(rh+sy(6)); local cur=(activity==id)
        panel(px+sx(10),y,pw-sx(20),rh, cur and {0.15,0.2,0.3,0.97} or {0.11,0.12,0.17,0.95}, cur and UI.btn or UI.line, 8*sw)
        setc(UI.text); love.graphics.setFont(font); love.graphics.print(a.name, px+sx(22), y+sy(7))
        love.graphics.setFont(font_sm); setc(UI.dim)
        if a.kind=="gather" then
            love.graphics.print(string.format("Lv %d   产出 %s  +%.1f/秒", player.skill[id] or 1, MAT_NAME[a.mat], a.base*(player.skill[id] or 1)), px+sx(22), y+sy(30))
            local c=skill_cost(player.skill[id] or 1); local ok=player.gold>=c
            button(px+pw-sx(96), y+sy(13), sx(86), sy(30), "升级 "..c, ok and {0.3,0.6,0.5} or UI.btn, ok, font_sm)
        elseif a.kind=="craft" then
            love.graphics.print("图纸：", px+sx(22), y+sy(30))
            -- 4 个箭矢图纸，可点选；当前选中高亮
            for j,t in ipairs(ARROW_TIERS) do
                local ix=px+sx(64)+(j-1)*sx(40); local iy=y+sy(37)
                if player.fletch_blueprint==t.id then setc(t.color,0.25); rrect("fill",ix-sx(14),iy-sy(13),sx(28),sy(26),5*sw); setc(t.color); love.graphics.setLineWidth(math.max(1,sx(1.4))); rrect("line",ix-sx(14),iy-sy(13),sx(28),sy(26),5*sw); love.graphics.setLineWidth(1) end
                icon_arrow(ix, iy, sx(9), t.color)
            end
            local c=skill_cost(player.skill.fletch or 1); local ok=player.gold>=c
            button(px+pw-sx(96), y+sy(13), sx(86), sy(30), "升级 "..c, ok and {0.3,0.6,0.5} or UI.btn, ok, font_sm)
        elseif a.kind=="combat" then
            love.graphics.print(region.name.."   消耗箭矢", px+sx(22), y+sy(30))
        else
            love.graphics.print("什么也不做", px+sx(22), y+sy(30))
        end
        if cur then setc(UI.good); love.graphics.setFont(font_sm); love.graphics.printf("进行中",px+sx(10),y+sy(7),pw-sx(40),"right") end
    end

    -- 材料栏
    local my=py+ph-sy(56); love.graphics.setColor(0.06,0.07,0.11,0.9); rrect("fill",px+sx(6),my-sy(4),pw-sx(12),sy(24),5*sw)
    local mw=(pw-sx(12))/#MATERIALS
    for i,m in ipairs(MATERIALS) do local mx=px+sx(6)+(i-1)*mw; mat_chip(m,mx+sx(16),my+sy(8),sx(6)); setc(UI.text); love.graphics.setFont(font_sm); love.graphics.print(MAT_NAME[m]..": "..(player.mats[m] or 0), mx+sx(26),my+sy(2)) end
    button(px+pw/2-sx(60),py+ph-sy(32),sx(120),sy(26),"返回",{0.4,0.4,0.5},true)
end

-- ============================================================================
-- 装备栏（WoW 式 paperdoll + Bag）
-- ============================================================================
local gear_tab = "doll"
local tooltip = nil   -- { g=gear, src="equip"|"bag", idx=bagindex }
-- 槽位类型图标（4 种，复用）
local function icon_kind(kind, cx, cy, s, col)
    setc(col); love.graphics.setLineWidth(math.max(1,1.6*sw))
    if kind=="weapon" then
        love.graphics.arc("line","open",cx-s*0.2,cy,s,-1.0,1.0)
        love.graphics.line(cx-s*0.2+s*math.cos(-1.0),cy+s*math.sin(-1.0), cx-s*0.2+s*math.cos(1.0),cy+s*math.sin(1.0))
    elseif kind=="quiver" then
        love.graphics.polygon("line", cx-s*0.5,cy-s, cx+s*0.5,cy-s, cx+s*0.35,cy+s, cx-s*0.35,cy+s)
        love.graphics.line(cx-s*0.2,cy-s,cx-s*0.2,cy-s*1.4); love.graphics.line(cx+s*0.2,cy-s,cx+s*0.2,cy-s*1.4)
    elseif kind=="armor" then
        love.graphics.polygon("line", cx,cy-s, cx+s*0.9,cy-s*0.4, cx+s*0.6,cy+s, cx,cy+s*1.1, cx-s*0.6,cy+s, cx-s*0.9,cy-s*0.4)
    else
        love.graphics.polygon("line", cx,cy-s, cx+s*0.8,cy, cx,cy+s, cx-s*0.8,cy)
    end
    love.graphics.setLineWidth(1)
end
local function gear_summary(g)
    local a={}; add_gear_stats(g,a); local parts={}
    if a.weapon_attack then parts[#parts+1]="攻击 "..a.weapon_attack end
    for _,k in ipairs(ATTRS) do if a[k] then parts[#parts+1]="+"..a[k].." "..ATTR_NAME[k] end end
    if a.armor then parts[#parts+1]="护甲 "..a.armor end
    if a.crit_pct then parts[#parts+1]="暴击 +"..a.crit_pct.."%" end
    return table.concat(parts, "   ")
end

-- 物品详情的逐行内容（基础属性白/属性彩、词缀绿）
local function gear_detail_lines(g)
    local lines = {}
    local s = g.stats
    if s.weapon_attack then lines[#lines+1] = { "武器攻击  +"..s.weapon_attack, UI.text } end
    for _,k in ipairs(ATTRS) do if s[k] then lines[#lines+1] = { "+"..s[k].."  "..ATTR_NAME[k], ATTR_COLOR[k] } end end
    if s.armor then lines[#lines+1] = { "护甲  +"..s.armor, UI.text } end
    for _,af in ipairs(g.affixes) do
        local txt = af.pct and ((af.key=="crit" and "暴击" or ATTR_NAME[af.key] or af.key).."  +"..af.val.."%")
                            or ("+"..af.val.."  "..(ATTR_NAME[af.key] or af.key))
        lines[#lines+1] = { txt, {0.45,0.85,0.55} }
    end
    return lines
end

-- 物品说明文案
local MAT_DESC = { wood="砍柴所得。制作各种箭矢的基础材料。", ore="采矿所得。用于铁箭及以上。", herb="采药所得。用于猎手箭、符文箭。" }
local function arrow_desc(t) return "战斗消耗的弹药。伤害倍率 x"..t.mult.."。" end

-- 构建 tooltip 内容：标题/标题色/副标题/逐行/底部按钮文案
local function tt_content(tt)
    if tt.kind=="gear" then
        local g=tt.g
        return gear_full_name(g), gear_color(g),
            RAR[g.rarity].name.."  ·  "..SLOT_INFO[g.slot].name.."  ·  装等 "..g.ilvl,
            gear_detail_lines(g), (tt.src=="bag") and "装备" or nil
    elseif tt.kind=="mat" then
        local lines={ {"持有："..(player.mats[tt.id] or 0), UI.text}, {MAT_DESC[tt.id] or "", UI.dim} }
        return MAT_NAME[tt.id], MAT_COLOR[tt.id], "材料 · 可堆叠", lines, nil
    else -- arrow
        local t; for _,a in ipairs(ARROW_TIERS) do if a.id==tt.id then t=a end end
        local lines={ {"持有："..(player.arrows[tt.id] or 0).." 支", UI.text}, {arrow_desc(t), UI.dim} }
        -- 配方
        local parts={}; for m,n in pairs(t.cost) do parts[#parts+1]=MAT_NAME[m].."x"..n end
        lines[#lines+1]={ "配方："..table.concat(parts,"  "), {0.6,0.7,0.85} }
        return t.name, t.color, "箭矢 · 可堆叠", lines, nil
    end
end

local function tt_geom(tt)
    local W,H = love.graphics.getWidth(), love.graphics.getHeight()
    local _,_,_,lines = tt_content(tt)
    local tw = sx(290)
    local th = sy(66) + #lines*sy(20) + sy(50)
    return (W-tw)/2, (H-th)/2, tw, th, lines
end

local function draw_tooltip()
    if not tooltip then return end
    local W,H = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0,0,0,0.55); love.graphics.rectangle("fill",0,0,W,H)
    local title, tcol, sub, lines, equip = tt_content(tooltip)
    local tx,ty,tw,th = tt_geom(tooltip)
    panel(tx,ty,tw,th,{0.1,0.11,0.16,0.99},tcol,10*sw)
    setc(tcol); love.graphics.setFont(font_med); love.graphics.printf(title, tx+sx(14), ty+sy(10), tw-sx(28), "left")
    setc(UI.dim); love.graphics.setFont(font_sm); love.graphics.printf(sub, tx+sx(14), ty+sy(36), tw-sx(28), "left")
    setc(UI.line); love.graphics.rectangle("fill", tx+sx(14), ty+sy(56), tw-sx(28), 1*sh)
    local yy = ty+sy(64)
    for _,ln in ipairs(lines) do setc(ln[2]); love.graphics.print(ln[1], tx+sx(18), yy); yy = yy + sy(20) end
    local fy = ty+th-sy(40)
    if equip then
        local bw=(tw-sx(40))/2
        button(tx+sx(14), fy, bw, sy(30), "装备", {0.3,0.6,0.4}, true, font_sm)
        button(tx+sx(26)+bw, fy, bw, sy(30), "关闭", {0.4,0.4,0.5}, true, font_sm)
    else
        button(tx+tw/2-sx(60), fy, sx(120), sy(30), "关闭", {0.4,0.4,0.5}, true, font_sm)
    end
end

local function tooltip_press(x,y)
    local tx,ty,tw,th = tt_geom(tooltip)
    local fy = ty+th-sy(40)
    if tooltip.kind=="gear" and tooltip.src=="bag" then
        local bw=(tw-sx(40))/2
        if x>=tx+sx(14) and x<=tx+sx(14)+bw and y>=fy and y<=fy+sy(30) then
            local i=tooltip.idx; local g=tooltip.g
            if player.bag[i]==g then table.remove(player.bag,i) end
            local old=player.equip[g.slot]; player.equip[g.slot]=g; if old then player.bag[#player.bag+1]=old end
            recalc(); tooltip=nil; return
        end
    end
    tooltip=nil
end


-- 装备面板：角色总览卡 + 11 槽位列表（点击看详情）
local function draw_equip()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight(); love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,w,h)
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112); panel(px,py,pw,ph,{0.09,0.1,0.15,0.98},UI.line,10*sw)
    love.graphics.setFont(font_med); setc(UI.text); love.graphics.printf("装备",px,py+sy(8),pw,"center")
    -- 总览卡
    local cy=py+sy(40)
    panel(px+sx(10),cy,pw-sx(20),sy(46),{0.13,0.15,0.22,0.97},UI.line,7*sw)
    love.graphics.setFont(font_sm)
    for j,k in ipairs(ATTRS) do setc(ATTR_COLOR[k]); love.graphics.print(ATTR_NAME[k].." "..player[k], px+sx(20)+(j-1)*sx(74), cy+sy(6)) end
    setc(UI.text); love.graphics.print(string.format("攻击 %d   攻速 %.2f   暴击 %d%%", math.floor(player.attack), player.atk_speed, math.floor(player.crit*100)), px+sx(20), cy+sy(26))
    setc(UI.dim); love.graphics.printf(string.format("生命 %d  护甲 %d  DPS %d", player.max_hp, player.armor, math.floor(player.dps)), px+sx(20), cy+sy(26), pw-sx(30), "right")
    -- 槽位列表
    local ly=cy+sy(54); local rh=sy(38)
    for i,slot in ipairs(SLOTS) do
        local y=ly+(i-1)*(rh+sy(3)); local g=player.equip[slot]; local info=SLOT_INFO[slot]
        local rc = g and gear_color(g) or {0.32,0.33,0.4}
        panel(px+sx(10),y,pw-sx(20),rh,{0.11,0.12,0.17,0.95},rc,6*sw)
        setc(rc); love.graphics.rectangle("fill",px+sx(10),y,3*sw,rh,1.5*sw,1.5*sw)
        icon_kind(info.kind, px+sx(28), y+rh/2, sx(8), rc)
        setc(UI.dim); love.graphics.setFont(font_sm); love.graphics.print(info.name, px+sx(46), y+sy(3))
        if g then
            setc(rc); love.graphics.print(gear_full_name(g), px+sx(46), y+sy(19))
            setc(UI.dim); love.graphics.printf("›", px+sx(46), y+sy(11), pw-sx(40), "right")
        else
            setc({0.42,0.42,0.48}); love.graphics.print("空", px+sx(46), y+sy(19))
        end
    end
    button(px+pw/2-sx(60),py+ph-sy(34),sx(120),sy(28),"返回",{0.4,0.4,0.5},true)
end

-- 背包面板：材料 / 箭矢 / 装备 三区，可堆叠 + 图标，点击看说明
-- 返回各可点项的矩形，供 press 复用
local function bag_layout()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112)
    return px,py,pw,ph
end
local function draw_bag()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight(); love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,w,h)
    local px,py,pw,ph=bag_layout(); panel(px,py,pw,ph,{0.09,0.1,0.15,0.98},UI.line,10*sw)
    love.graphics.setFont(font_med); setc(UI.text); love.graphics.printf("背包",px,py+sy(8),pw,"center")
    local function header(t,y) setc(UI.dim); love.graphics.setFont(font_sm); love.graphics.print(t, px+sx(14), y) end
    -- 材料区
    header("材料", py+sy(40))
    local mcw=(pw-sx(20))/3
    for i,m in ipairs(MATERIALS) do
        local cx=px+sx(10)+(i-1)*mcw; local cyy=py+sy(58)
        panel(cx,cyy,mcw-sx(6),sy(40),{0.11,0.12,0.17,0.95},UI.line,6*sw)
        icon_mat(m, cx+sx(18), cyy+sy(20), sx(11))
        setc(UI.text); love.graphics.setFont(font_sm); love.graphics.print(player.mats[m] or 0, cx+sx(34), cyy+sy(13))
    end
    -- 箭矢区
    header("箭矢", py+sy(108))
    local acw=(pw-sx(20))/4
    for i,t in ipairs(ARROW_TIERS) do
        local cx=px+sx(10)+(i-1)*acw; local cyy=py+sy(126)
        panel(cx,cyy,acw-sx(6),sy(40),{t.color[1]*0.15,t.color[2]*0.15,t.color[3]*0.18,0.95},{t.color[1]*0.6,t.color[2]*0.6,t.color[3]*0.6},6*sw)
        icon_arrow(cx+sx(16), cyy+sy(20), sx(10), t.color)
        setc(t.color); love.graphics.setFont(font_sm); love.graphics.print(player.arrows[t.id] or 0, cx+sx(30), cyy+sy(13))
    end
    -- 装备区
    header("装备 ("..#player.bag..")", py+sy(176))
    local ly=py+sy(194); local rh=sy(38)
    if #player.bag==0 then setc({0.42,0.42,0.48}); love.graphics.setFont(font_sm); love.graphics.print("（暂无，战斗掉落）", px+sx(14), ly) end
    for i,g in ipairs(player.bag) do
        local y=ly+(i-1)*(rh+sy(4)); if y+rh>py+ph-sy(46) then break end
        local rc=gear_color(g); panel(px+sx(10),y,pw-sx(20),rh,{rc[1]*0.16,rc[2]*0.16,rc[3]*0.18,0.95},{rc[1]*0.7,rc[2]*0.7,rc[3]*0.7},6*sw)
        setc(rc); love.graphics.rectangle("fill",px+sx(10),y,3*sw,rh,1.5*sw,1.5*sw)
        icon_kind(SLOT_INFO[g.slot].kind, px+sx(28), y+rh/2, sx(8), rc)
        setc(rc); love.graphics.setFont(font_sm); love.graphics.print(gear_full_name(g), px+sx(46), y+sy(4))
        setc(UI.dim); love.graphics.print(SLOT_INFO[g.slot].name.." · 装等"..g.ilvl, px+sx(46), y+sy(21))
    end
    button(px+pw/2-sx(60),py+ph-sy(34),sx(120),sy(28),"返回",{0.4,0.4,0.5},true)
end

-- ============================================================================
-- love 回调
-- ============================================================================
function love.load()
    -- 中文字体（思源黑体）；缺失则退回默认字体（中文会显示为方块）
    local CJK = "assets/fonts/NotoSansSC-Regular.otf"
    local function mkfont(sz) local ok,f = pcall(love.graphics.newFont, CJK, sz); if ok then f:setFilter("linear","linear"); return f else return love.graphics.newFont(sz) end end
    font=mkfont(15); font_sm=mkfont(12); font_med=mkfont(19); font_big=mkfont(30)
    sw=love.graphics.getWidth()/DESIGN_W; sh=love.graphics.getHeight()/DESIGN_H; init()
end
function love.update(dt) if dt>0.05 then dt=0.05 end update(dt) end
function love.draw()
    love.graphics.setBackgroundColor(UI.bg)
    local ox,oy=0,0; if shake>0 then ox=(math.random()*2-1)*shake; oy=(math.random()*2-1)*shake end
    love.graphics.push(); love.graphics.translate(ox,oy)
    draw_main(); draw_hud(); if not panel_open then bottom_btns() end
    for _,f in ipairs(floats) do love.graphics.setFont(f.scale>1.2 and font_med or font_sm); love.graphics.setColor(f.color[1],f.color[2],f.color[3],math.min(1,f.timer*2)); love.graphics.printf(f.text,f.x*sw-sx(60),f.y*sh,sx(120),"center") end
    if panel_open=="region" then draw_regions() elseif panel_open=="activity" then draw_activity() elseif panel_open=="bag" then draw_bag(); draw_tooltip() elseif panel_open=="equip" then draw_equip(); draw_tooltip() end
    if result_banner=="defeat" then
        love.graphics.setColor(0,0,0,0.7); love.graphics.rectangle("fill",0,0,love.graphics.getWidth(),love.graphics.getHeight())
        love.graphics.setFont(font_big); setc(UI.bad); love.graphics.printf("已阵亡",0,love.graphics.getHeight()*0.4,love.graphics.getWidth(),"center")
        love.graphics.setFont(font_sm); setc(UI.dim); love.graphics.printf("Lv "..player.level.." · 点击复活",0,love.graphics.getHeight()*0.5,love.graphics.getWidth(),"center")
    end
    love.graphics.pop()
end

local function hit(x,y,rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end
local function press(x,y)
    if result_banner=="defeat" then player.hp=player.max_hp; result_banner=nil; activity="rest"; enemy=nil; return end
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    if not panel_open then
        -- 底部四入口：活动 / 背包 / 装备 / 地区
        local by=h-sy(46); local n=4; local gap=sx(8); local bw=(w-sx(20)-gap*(n-1))/n
        local ids={"activity","bag","equip","region"}
        for i,id in ipairs(ids) do if hit(x,y, sx(10)+(i-1)*(bw+gap), by, bw, sy(36)) then panel_open=id; return end end
    elseif panel_open=="region" then
        local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112); local ry=py+sy(52); local rh=sy(72)
        for i,rg in ipairs(REGIONS) do local yy=ry+(i-1)*(rh+sy(8)); if hit(x,y,px+sx(10),yy,pw-sx(20),rh) then region=rg; stage=0; enemy=nil; set_toast("狩猎地："..rg.name,UI.good); return end end
        if hit(x,y,px+pw/2-sx(64),py+ph-sy(40),sx(128),sy(30)) then panel_open=nil; return end
    elseif panel_open=="activity" then
        local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112); local ry=py+sy(54); local rh=sy(56)
        for i,id in ipairs(ACT_ORDER) do
            local a=ACTIVITIES[id]; local yy=ry+(i-1)*(rh+sy(6))
            if (a.kind=="gather" or a.kind=="craft") and hit(x,y,px+pw-sx(96),yy+sy(13),sx(86),sy(30)) then
                upgrade_skill(a.kind=="craft" and "fletch" or id); return
            end
            -- 制箭：点图纸 = 选图纸并开始制造
            if a.kind=="craft" then
                for j,t in ipairs(ARROW_TIERS) do
                    local ix=px+sx(64)+(j-1)*sx(40); local iy=yy+sy(37)
                    if hit(x,y,ix-sx(14),iy-sy(13),sx(28),sy(26)) then
                        player.fletch_blueprint=t.id; activity="fletch"; player.fletch_prog=0; panel_open=nil; return
                    end
                end
            end
            if hit(x,y,px+sx(10),yy,pw-sx(20),rh) then
                activity=id; player.acc=0; player.fletch_prog=0
                if id=="combat" and not enemy then next_enemy() end
                panel_open=nil; return
            end
        end
        if hit(x,y,px+pw/2-sx(60),py+ph-sy(32),sx(120),sy(26)) then panel_open=nil; return end
    elseif panel_open=="equip" then
        if tooltip then tooltip_press(x,y); return end
        local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112)
        if hit(x,y,px+pw/2-sx(60),py+ph-sy(34),sx(120),sy(28)) then panel_open=nil; return end
        local cy=py+sy(40); local ly=cy+sy(54); local rh=sy(38)
        for i,slot in ipairs(SLOTS) do
            local yy=ly+(i-1)*(rh+sy(3)); local g=player.equip[slot]
            if g and hit(x,y,px+sx(10),yy,pw-sx(20),rh) then tooltip={ kind="gear", g=g, src="equip" }; return end
        end
    elseif panel_open=="bag" then
        if tooltip then tooltip_press(x,y); return end
        local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112)
        if hit(x,y,px+pw/2-sx(60),py+ph-sy(34),sx(120),sy(28)) then panel_open=nil; return end
        -- 材料格
        local mcw=(pw-sx(20))/3
        for i,m in ipairs(MATERIALS) do local cx=px+sx(10)+(i-1)*mcw; if hit(x,y,cx,py+sy(58),mcw-sx(6),sy(40)) then tooltip={kind="mat",id=m}; return end end
        -- 箭矢格
        local acw=(pw-sx(20))/4
        for i,t in ipairs(ARROW_TIERS) do local cx=px+sx(10)+(i-1)*acw; if hit(x,y,cx,py+sy(126),acw-sx(6),sy(40)) then tooltip={kind="arrow",id=t.id}; return end end
        -- 装备行
        local ly=py+sy(194); local rh=sy(38)
        for i,g in ipairs(player.bag) do local yy=ly+(i-1)*(rh+sy(4)); if yy+rh>py+ph-sy(46) then break end
            if hit(x,y,px+sx(10),yy,pw-sx(20),rh) then tooltip={kind="gear",g=g,src="bag",idx=i}; return end end
    end
end
function love.touchpressed(id,x,y) press(x,y) end
function love.mousepressed(x,y,b) if b==1 then press(x,y) end end
function love.resize() sw=love.graphics.getWidth()/DESIGN_W; sh=love.graphics.getHeight()/DESIGN_H end
