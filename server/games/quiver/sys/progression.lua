-- ============================================================================
-- sys/progression —— 成长曲线与衍生属性：recalc（锚点换算，核心，被多处调用）+
--   角色经验/升级/技能解锁 + 采集职业经验 + 制造职业经验/图谱解锁 + 金币加速升级。
-- 依赖：data + core/state + fx + sys/inventory（recalc 读 add_gear_stats/ammo_count）。
--   inventory 在 load 期不读 progression（其 recalc 走惰性 require），故此处顶层 require
--   inventory 不成环。recalc 下沉至此，main 与各 sys 仍通过本表调得到。
-- ============================================================================
local D = require("data")
local state = require("core.state")
local fx = require("fx")
local inv = require("sys.inventory")

local SLOTS = D.SLOTS
local SKILLS, SKILL_ORDER = D.SKILLS, D.SKILL_ORDER
local ARROWS = D.ARROWS
local BLUEPRINTS = D.BLUEPRINTS
local ACTIVITIES = D.ACTIVITIES
local MAT_COLOR = D.MAT_COLOR
local CRIT_MULT = D.CRIT_MULT
local WEAPON_SPEED_DEFAULT = D.WEAPON_SPEED_DEFAULT
local DESIGN_W, DESIGN_H = D.DESIGN_W, D.DESIGN_H
local UI = D.UI

local prog = {}

-- ============================================================================
-- 角色属性聚合（锚点换算）—— 核心：装备/箭档/增益/法力/生命统一重算
-- ============================================================================
function prog.recalc()
    local a = { str=state.player.base_str, agi=state.player.base_agi, sta=state.player.base_sta }
    for _,slot in ipairs(SLOTS) do local g=state.player.equip[slot]; if g then inv.add_gear_stats(g,a) end end
    state.player.str=a.str; state.player.agi=a.agi; state.player.sta=a.sta; state.player.armor=a.armor or 0
    -- 攻击力区间 = 基础 + 武器区间 + 力量（力量等量加到上下限）
    local wmin = math.floor(a.wmin or 1); local wmax = math.floor(a.wmax or 2)
    state.player.wspeed  = a.wspeed or WEAPON_SPEED_DEFAULT     -- 武器基础攻速（展示用）
    state.player.atk_min = 5 + wmin + state.player.str
    state.player.atk_max = 5 + wmax + state.player.str
    state.player.atk_mid = (state.player.atk_min + state.player.atk_max)/2
    state.player.attack  = state.player.atk_mid                       -- 兼容旧引用/兜底
    state.player.atk_speed = state.player.wspeed * (1 + state.player.agi*0.006)   -- 武器攻速 × 敏捷加成
    -- 武器签名 haste：累加各装备 sig.haste(实践只武器有)，乘进攻速
    local sig_haste = 0
    for _,slot in ipairs(SLOTS) do local g=state.player.equip[slot]
        if g and g.sig and g.sig.haste then sig_haste = sig_haste + (type(g.sig.haste)=="number" and g.sig.haste or 0.08) end
    end
    if sig_haste>0 then state.player.atk_speed = state.player.atk_speed * (1 + sig_haste) end
    -- 暴击 = 基础 + 敏捷 + 词缀暴击 + 武器内置/签名暴击(crit_innate)
    state.player.crit      = math.min(0.6, 0.05 + state.player.agi*0.0004 + (a.crit_pct or 0)*0.01 + (a.crit_innate or 0))
    -- 战斗精通(满级软成长)：攻击/急速乘算、暴击加算、采集另在 gather 取。每级 +0.5%。
    local MP = D.MASTERY_PER_POINT
    local m = state.player.mastery
    if m then
        local a_lv, h_lv, c_lv = m.attack or 0, m.haste or 0, m.crit or 0
        if a_lv>0 then
            local mul = 1 + a_lv*MP
            state.player.atk_min = math.floor(state.player.atk_min*mul)
            state.player.atk_max = math.floor(state.player.atk_max*mul)
            state.player.atk_mid = (state.player.atk_min + state.player.atk_max)/2
            state.player.attack  = state.player.atk_mid
        end
        if h_lv>0 then state.player.atk_speed = state.player.atk_speed * (1 + h_lv*MP) end
        if c_lv>0 then state.player.crit = math.min(0.6, state.player.crit + c_lv*MP) end
    end
    state.player.max_hp    = 60 + state.player.sta*6
    if state.player.hp==nil or state.player.hp>state.player.max_hp then state.player.hp=state.player.max_hp end
    -- 法力：独立池，随等级长（不占用基础属性）
    state.player.max_mp = 30 + state.player.level*5
    if state.player.mp==nil or state.player.mp>state.player.max_mp then state.player.mp=state.player.max_mp end
    -- 箭袋弹药槽数（无箭袋则 0）
    state.player.ammo = state.player.ammo or {}
    state.player.ammo_cap = (state.player.equip.quiver and state.player.equip.quiver.ammo_slots) or 0
    -- 当前箭档倍率（从弹药槽里取最高档）
    state.player.arrow_mult, state.player.arrow_tier = 0.5, nil
    for i=#ARROWS,1,-1 do if inv.ammo_count(ARROWS[i].id)>0 then state.player.arrow_mult=ARROWS[i].mult; state.player.arrow_tier=ARROWS[i]; break end end
    local cf = 1 + state.player.crit*(CRIT_MULT-1)
    state.player.dps = state.player.attack * state.player.arrow_mult * cf * state.player.atk_speed
    -- 限时增益叠加（只读 buffs，只动攻速/暴击，绝不碰 max_hp/hp）
    for _,b in ipairs(state.player.buffs or {}) do
        if b.kind=="haste" then state.player.atk_speed = state.player.atk_speed*(1+b.amt)
        elseif b.kind=="crit" then state.player.crit = math.min(0.6, state.player.crit+b.amt) end
    end
end

-- ============================================================================
-- 角色升级
-- ============================================================================
function prog.xp_need(lv) return math.floor(55*(lv^2.15)) end
-- 满级(60)后每多少 xp 转 1 精通点(= 满级单级 xp 需求)。
function prog.mastery_step() return prog.xp_need(D.LEVEL_CAP) end
-- 角色升到一定等级自动学会技能（learn.lvl 类）
function prog.check_skill_unlock()
    for _,id in ipairs(SKILL_ORDER) do local s=SKILLS[id]
        if s.learn and s.learn.lvl and state.player.level>=s.learn.lvl then
            local known=false; for _,k in ipairs(state.player.skills) do if k==id then known=true end end
            if not known then state.player.skills[#state.player.skills+1]=id; fx.set_toast("学会技能："..s.name, s.color) end
        end
    end
end
function prog.gain_xp(amount)
    state.player.xp = state.player.xp + amount
    -- 未满级：正常升级；满级(LEVEL_CAP)后 xp 不再升级，转「战斗精通」点(每 mastery_step 一点)。
    while state.player.level < D.LEVEL_CAP and state.player.xp >= state.player.xp_next do
        state.player.xp = state.player.xp - state.player.xp_next
        state.player.level = state.player.level + 1
        state.player.base_str = state.player.base_str + 2
        state.player.base_agi = state.player.base_agi + 2
        state.player.base_sta = state.player.base_sta + 3
        state.player.xp_next = prog.xp_need(state.player.level); prog.recalc(); state.player.hp = state.player.max_hp
        fx.floats[#fx.floats+1]={ x=DESIGN_W*0.18, y=DESIGN_H*0.14, text="LEVEL "..state.player.level, color=UI.xp, timer=1.4, scale=1.4, vy=-50 }
        prog.check_skill_unlock()
    end
    if state.player.level >= D.LEVEL_CAP then
        -- 满级：xp 池每攒满 mastery_step 转 1 精通点(温和无限成长)
        state.player.mastery = state.player.mastery or { points=0 }
        local step = prog.mastery_step()
        while state.player.xp >= step do
            state.player.xp = state.player.xp - step
            state.player.mastery.points = (state.player.mastery.points or 0) + 1
            fx.floats[#fx.floats+1]={ x=DESIGN_W*0.18, y=DESIGN_H*0.14, text="+1 精通", color=UI.gold, timer=1.4, scale=1.3, vy=-50 }
        end
        state.player.xp_next = step   -- 展示用：满级后进度条对齐到精通步长
    end
end

-- ============================================================================
-- 战斗精通(满级软成长)：投点 → 永久小幅加成。recalc 读 player.mastery 换算。
-- ============================================================================
-- 某精通已投级数
function prog.mastery_level(id) local m=state.player.mastery; return (m and m[id]) or 0 end
-- 精通乘子(1 + 级数×每点)：采集等"非 recalc 派生量"在各 sys 直接乘上。
function prog.mastery_mul(id) return 1 + prog.mastery_level(id)*D.MASTERY_PER_POINT end
-- 投一级精通(扣点，成本随已投级数递增)。点不够则不变。
function prog.spend_mastery(id)
    if not D.MASTERY[id] then return end
    state.player.mastery = state.player.mastery or { points=0 }
    local m = state.player.mastery
    local owned = m[id] or 0
    local cost = D.mastery_cost(owned)
    if (m.points or 0) < cost then return end
    m.points = m.points - cost
    m[id] = owned + 1
    prog.recalc()
end

-- ============================================================================
-- 采集职业经验
-- ============================================================================
function prog.gather_need(lvl) return math.floor(50*(lvl^1.55)) end
function prog.gain_gather_xp(key, n)
    local s = state.player.skill[key]; s.xp = s.xp + n
    while s.xp >= prog.gather_need(s.lvl) do
        s.xp = s.xp - prog.gather_need(s.lvl); s.lvl = s.lvl + 1
        fx.floats[#fx.floats+1]={ x=DESIGN_W*0.5, y=DESIGN_H*0.18, text=ACTIVITIES[key].name.." Lv "..s.lvl, color=MAT_COLOR[ACTIVITIES[key].mat], timer=1.3, scale=1.2, vy=-45 }
    end
end

-- ============================================================================
-- 三制造职业经验 / 图谱解锁（工程/锻造/制药共用一套，按 bp.job 路由）
-- ============================================================================
-- 子职业等级取数：按 job 取对应职业记录(engineer/forge/alchemy)，缺省回工程。
local function job_rec(job)
    return state.player[job or "engineer"] or state.player.engineer
end
local JOB_LABEL = { engineer="工程", forge="锻造", alchemy="制药" }
-- 制造职业升级曲线（比角色平缓：辅助线升得快些）；三职业共用
function prog.craft_need(lv) return math.floor(40*(lv^1.4)) end
prog.forge_need = prog.craft_need
function prog.unlock_blueprints()  -- 到达 req 等级自动解锁 level/master 类（master 第一期也按等级解锁，TODO：技能大师）
    for _,b in ipairs(BLUEPRINTS) do
        if not state.player.bp_known[b.id] and b.learn~="start" and job_rec(b.job).lvl >= b.req then
            local oc = (b.out.kind=="arrow") and D.arrow_color(b.out) or (b.out.color or {0.7,0.6,0.4})
            state.player.bp_known[b.id]=true; fx.set_toast("学会图谱："..b.name, oc)
        end
    end
end
function prog.add_craft_xp(n, job)
    local rec = job_rec(job)
    rec.xp = rec.xp + n
    while rec.xp >= prog.craft_need(rec.lvl) do
        rec.xp = rec.xp - prog.craft_need(rec.lvl)
        rec.lvl = rec.lvl + 1
        fx.floats[#fx.floats+1]={ x=DESIGN_W*0.5, y=DESIGN_H*0.2, text=(JOB_LABEL[job or "engineer"]).." Lv "..rec.lvl, color={0.7,0.6,0.4}, timer=1.3, scale=1.2, vy=-45 }
        prog.unlock_blueprints()
    end
end

-- ============================================================================
-- 金币加速：采集职业(skill[key].lvl) 与 制造类职业(engineer/forge/alchemy) 都能花钱直接升一级
-- ============================================================================
function prog.skill_cost(lvl) return math.floor(15 * (lvl ^ 1.7) + 10) end
function prog.upgrade_skill(key)
    local rec = (key=="engineer" or key=="forge" or key=="alchemy") and state.player[key] or state.player.skill[key]
    local c = prog.skill_cost(rec.lvl)
    if state.player.gold >= c then state.player.gold = state.player.gold - c; rec.lvl = rec.lvl + 1; prog.unlock_blueprints() end
end

return prog
