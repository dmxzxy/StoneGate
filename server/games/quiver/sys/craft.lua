-- ============================================================================
-- sys/craft —— 图谱制造：箭/中间材料/药剂共用 can_craft/do_craft，外加 craft 挂机 tick。
-- 依赖：data + core/state + sys/inventory（增删物品/弹药）+ sys/progression（recalc/制造经验）+ fx。
--   不被 gather/combat require；自身的制造进度 tick 独立。顶层 require 无环（progression/inventory
--   在 load 期不读 craft）。
-- ============================================================================
local D = require("data")
local state = require("core.state")
local inv = require("sys.inventory")
local prog = require("sys.progression")
local fx = require("fx")

local BP = D.BP
local ACTIVITIES = D.ACTIVITIES
local CRAFT_BASE = D.CRAFT_BASE
local UI = D.UI

local craft = {}

function craft.can_craft(bp)
    for m,n in pairs(bp.cost) do if inv.inv_count("mat",m) < n then return false end end
    return true
end
-- 按 rarity_roll 权重表抽一个稀有度 id（造装用）；空表兜底 common。
local function pick_rarity(roll)
    if not roll then return "common" end
    local total=0; for _,w in pairs(roll) do total=total+w end
    if total<=0 then return "common" end
    local r=math.random()*total
    for id,w in pairs(roll) do r=r-w; if r<=0 then return id end end
    return "common"
end
function craft.do_craft(bp)
    if not craft.can_craft(bp) then return end
    for m,n in pairs(bp.cost) do inv.inv_remove("mat",m,n) end
    local o = bp.out
    if o.kind=="arrow" then inv.ammo_add_arrow(o.head, o.element, o.feather, o.qty)
    elseif o.kind=="gear" then
        -- 造装：roll 稀有度 → roll_gear(定向槽/弓类型/材料档) → 进背包
        local rid = pick_rarity(o.rarity_roll)
        local g = inv.roll_gear(o.slot, o.ilvl_base or 1, rid, { wtype=o.wtype })
        if inv.inv_add("gear", nil, 1, g) then
            fx.set_toast("锻造出 "..inv.gear_full_name(g), inv.gear_color(g))
        else fx.set_toast("背包已满，锻造失败", UI.bad) end
    else inv.inv_add(o.kind, o.id, o.qty) end   -- mat/potion 进背包
    prog.add_craft_xp(math.ceil(bp.time*2), bp.job)
    prog.recalc()
end

-- 当前活动选中的图谱 id：forge 活动用 forge_bp，否则 craft_bp。
function craft.cur_bp_id()
    return (state.activity=="forge") and (state.player.forge_bp or "fg_copper")
        or (state.player.craft_bp or "ar_flint")
end

-- craft 挂机 tick：按当前活动选中图谱持续制造（制造/锻造共用），材料用尽自动停摆并提示一次
function craft.tick(dt)
    local job = ACTIVITIES[state.activity].job   -- forge 活动带 job="forge"，制造为 nil
    local bp = BP[craft.cur_bp_id()]
    state.player.craft_target = bp
    if bp and state.player.bp_known[bp.id] and craft.can_craft(bp) then
        local lvl = (job=="forge") and state.player.forge.lvl or state.player.craft.lvl
        state.player.craft_prog = (state.player.craft_prog or 0) + CRAFT_BASE * lvl / bp.time * dt
        if state.player.craft_prog >= 1 then
            state.player.craft_prog = state.player.craft_prog - 1
            craft.do_craft(bp)
        end
        state.player.craft_stopped = nil
    else
        state.player.craft_prog = 0
        -- 缺料/未学：首次进入停摆时提示一次（持续制造直到材料用尽自然落到这里）
        if bp and state.player.bp_known[bp.id] and not state.player.craft_stopped then
            state.player.craft_stopped=true; fx.set_toast("材料不足，已停止制造", UI.bad)
        end
    end
end

return craft
