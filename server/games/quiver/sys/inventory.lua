-- ============================================================================
-- sys/inventory —— 物品/背包/箭袋/装备：统一格子背包模型 + 弹药槽 + WoW 式装备。
--   item: {kind="mat"/"arrow"/"potion", id=, qty=}  或  {kind="gear", gear=<obj>, qty=1}
--   player.inv = 定长格子数组（nil 或 item）；player.ammo = 弹药槽数组。
-- 依赖：data（静态表）+ core/state（读写 player.inv/ammo/equip）。最底层 sys，不 require 其它 sys，
--   故 progression 可在 load 期顶层 require 本模块而不成环。装备换装/重算由 progression.recalc
--   负责，调用方（combat.drop_loot / tooltip 装备）显式调 recalc，本模块只动库存数据。
-- ============================================================================
local D = require("data")
local state = require("core.state")

local SLOT_INFO = D.SLOT_INFO
local RAR = D.RAR
local TIER_PREFIX = D.TIER_PREFIX
local ATTRS = D.ATTRS
local AFFIXES = D.AFFIXES
local ARROWS = D.ARROWS
local BAG_SLOTS = D.BAG_SLOTS
local GEAR_BUDGET = D.GEAR_BUDGET
local WEAPON_DPS_K = D.WEAPON_DPS_K
local WEAPON_SPEED_DEFAULT = D.WEAPON_SPEED_DEFAULT

local inv = {}

-- ---- 堆叠 / 背包格 ----
function inv.max_stack(kind) return (kind=="arrow") and 200 or 9999 end  -- 箭矢 200/堆
function inv.inv_count(kind,id)
    local n=0; for i=1,BAG_SLOTS do local it=state.player.inv[i]; if it and it.kind==kind and it.id==id then n=n+it.qty end end; return n
end
function inv.inv_add(kind,id,qty,gear)
    if kind=="gear" then
        for i=1,BAG_SLOTS do if not state.player.inv[i] then state.player.inv[i]={kind="gear",gear=gear,qty=1}; return true end end
        return false
    end
    local ms=inv.max_stack(kind)
    -- 先填已有未满的堆
    for i=1,BAG_SLOTS do local it=state.player.inv[i]; if it and it.kind==kind and it.id==id and it.qty<ms then
        local put=math.min(ms-it.qty,qty); it.qty=it.qty+put; qty=qty-put; if qty<=0 then return true end end end
    -- 再开新格（超过 200 自动分堆）
    for i=1,BAG_SLOTS do if not state.player.inv[i] then
        local put=math.min(ms,qty); state.player.inv[i]={kind=kind,id=id,qty=put}; qty=qty-put; if qty<=0 then return true end end end
    return qty<=0
end
function inv.inv_remove(kind,id,n)
    for i=1,BAG_SLOTS do local it=state.player.inv[i]; if it and it.kind==kind and it.id==id then
        local take=math.min(n,it.qty); it.qty=it.qty-take; n=n-take; if it.qty<=0 then state.player.inv[i]=nil end
        if n<=0 then break end end end
end
-- 交换/移动/堆叠两个格子（拖拽用），堆叠尊重上限
function inv.inv_swap(a,b)
    if a==b then return end
    local ia,ib = state.player.inv[a], state.player.inv[b]
    if ia and ib and ia.kind==ib.kind and ia.id==ib.id and ia.kind~="gear" then
        local ms=inv.max_stack(ia.kind); local mv=math.min(ms-ib.qty, ia.qty)
        if mv>0 then ib.qty=ib.qty+mv; ia.qty=ia.qty-mv; if ia.qty<=0 then state.player.inv[a]=nil end; return end
    end
    state.player.inv[a], state.player.inv[b] = ib, ia
end

-- ---- 箭袋弹药槽（箭矢只能放这里，不进主背包） ----
function inv.ammo_count(id)
    local n=0; for i=1,(state.player.ammo_cap or 0) do local it=state.player.ammo[i]; if it and it.id==id then n=n+it.qty end end; return n
end
function inv.ammo_add(id,qty)
    local cap=state.player.ammo_cap or 0; local ms=200
    for i=1,cap do local it=state.player.ammo[i]; if it and it.id==id and it.qty<ms then local put=math.min(ms-it.qty,qty); it.qty=it.qty+put; qty=qty-put; if qty<=0 then return true end end end
    for i=1,cap do if not state.player.ammo[i] then local put=math.min(ms,qty); state.player.ammo[i]={id=id,qty=put}; qty=qty-put; if qty<=0 then return true end end end
    return qty<=0   -- 装不下的部分丢弃（箭袋满）
end
function inv.ammo_remove(id,n)
    for i=1,(state.player.ammo_cap or 0) do local it=state.player.ammo[i]; if it and it.id==id then
        local take=math.min(n,it.qty); it.qty=it.qty-take; n=n-take; if it.qty<=0 then state.player.ammo[i]=nil end
        if n<=0 then break end end end
end
function inv.ammo_swap(a,b)
    if a==b then return end
    local ia,ib=state.player.ammo[a],state.player.ammo[b]
    if ia and ib and ia.id==ib.id then local mv=math.min(200-ib.qty,ia.qty); if mv>0 then ib.qty=ib.qty+mv; ia.qty=ia.qty-mv; if ia.qty<=0 then state.player.ammo[a]=nil end; return end end
    state.player.ammo[a],state.player.ammo[b]=ib,ia
end

-- ---- 装备掉落/属性聚合/评分 ----
function inv.roll_gear(slot, ilvl, rarity_id)
    local info = SLOT_INFO[slot]; local r = RAR[rarity_id]
    local budget = GEAR_BUDGET * ilvl * r.mult * info.w
    local g = { slot=slot, ilvl=ilvl, rarity=rarity_id, stats={}, affixes={} }
    if info.kind == "weapon" then
        -- 武器两条基础属性：攻击力区间 + 攻速。慢弓伤害高、快弓伤害低，wmid*wspeed 守恒到 budget*WEAPON_DPS_K
        local wspeed = 0.45 + math.random()*0.20          -- 0.45~0.65 次/秒
        local wmid   = budget * WEAPON_DPS_K / wspeed
        g.stats.wmin   = math.max(1, math.floor(wmid*0.85))
        g.stats.wmax   = math.max(g.stats.wmin+1, math.floor(wmid*1.15))
        g.stats.wspeed = wspeed
    elseif info.kind == "quiver" then
        g.stats.agi = math.max(1, math.floor(budget))
        g.ammo_slots = r.tier   -- 弹药槽数 = 稀有度层级（普通=2，越高越多）
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

function inv.add_gear_stats(g, acc)
    for k,v in pairs(g.stats) do acc[k]=(acc[k] or 0)+v end
    for _,af in ipairs(g.affixes) do
        if af.key=="crit" then acc.crit_pct=(acc.crit_pct or 0)+af.val
        else acc[af.key]=(acc[af.key] or 0)+af.val end
    end
end
function inv.gear_score(g)
    local a={}; inv.add_gear_stats(g,a)
    local wscore = a.wmin and ((a.wmin+a.wmax)/2*(a.wspeed or WEAPON_SPEED_DEFAULT)*3.6) or 0  -- 武器按 DPS 比较
    return wscore +(a.str or 0)+(a.agi or 0)+(a.sta or 0)*0.8+(a.armor or 0)*0.5+(a.crit_pct or 0)*4
end
function inv.gear_color(g) return RAR[g.rarity].color end
function inv.gear_full_name(g) return RAR[g.rarity].name.." "..g.name end

return inv
