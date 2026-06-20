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
local CRAFT_BASE = D.CRAFT_BASE
local UI = D.UI

local craft = {}

function craft.can_craft(bp)
    for m,n in pairs(bp.cost) do if inv.inv_count("mat",m) < n then return false end end
    return true
end
function craft.do_craft(bp)
    if not craft.can_craft(bp) then return end
    for m,n in pairs(bp.cost) do inv.inv_remove("mat",m,n) end
    local o = bp.out
    if o.kind=="arrow" then inv.ammo_add(o.id, o.qty)
    else inv.inv_add(o.kind, o.id, o.qty) end   -- mat/potion 进背包
    prog.add_craft_xp(math.ceil(bp.time*2))
    prog.recalc()
end

-- craft 挂机 tick：按当前选中图谱持续制造，材料用尽自动停摆并提示一次
function craft.tick(dt)
    local bp = BP[state.player.craft_bp or "wood"]
    state.player.craft_target = bp
    if bp and state.player.bp_known[bp.id] and craft.can_craft(bp) then
        state.player.craft_prog = (state.player.craft_prog or 0) + CRAFT_BASE * state.player.craft.lvl / bp.time * dt
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
