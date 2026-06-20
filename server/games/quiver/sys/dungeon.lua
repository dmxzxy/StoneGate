-- ============================================================================
-- sys/dungeon —— 副本(§6)：探险许可恢复(离线也算) + 进入(扣许可/钥匙) + 波次小怪/boss
--   逐波战斗(复用 combat tick) + 结算(经验大包 + 肥掉落 / 失败安慰产出)。
-- 依赖：data + core/state + sys/inventory(掉落/钥匙) + sys/progression(经验/recalc) + sys/combat(波次战斗) + fx。
--   顶层 require combat 不成环：combat 在 load 期不读 dungeon(只在 tick 期读 state.dungeon_run 标志)。
-- ============================================================================
local D = require("data")
local state = require("core.state")
local inv = require("sys.inventory")
local prog = require("sys.progression")
local combat = require("sys.combat")
local fx = require("fx")

local DUNGEON = D.DUNGEON
local RARITIES, RAR = D.RARITIES, D.RAR
local SLOTS = D.SLOTS
local UI = D.UI
local ENERGY_MAX, ENERGY_REGEN = D.ENERGY_MAX, D.ENERGY_REGEN

local dungeon = {}

-- ---- 探险许可恢复：基于 last_time 时间戳，离线时间一并补足(典型挂机留存设计) ----
-- player.energy/energy_max/last_time 由 init/load 铺；这里只推进。
function dungeon.now() return (love.timer and love.timer.getTime and love.timer.getTime()) or os.time() end
-- 读档/启动时调一次：把离线流逝的时间折算成许可(封顶)。
function dungeon.catch_up()
    local p = state.player
    p.energy_max = p.energy_max or ENERGY_MAX
    if p.energy == nil then p.energy = p.energy_max end
    local t = dungeon.now()
    local last = p.last_time or t
    local dtoff = math.max(0, t - last)
    p.energy = math.min(p.energy_max, p.energy + dtoff*ENERGY_REGEN)
    p.last_time = t
end
-- 每帧推进(在线恢复)；last_time 跟着走，保证退出/再进的离线折算正确。
function dungeon.update(dt)
    local p = state.player
    if not p then return end
    p.energy_max = p.energy_max or ENERGY_MAX
    if p.energy == nil then p.energy = p.energy_max end
    p.energy = math.min(p.energy_max, p.energy + ENERGY_REGEN*dt)
    p.last_time = dungeon.now()
end

-- ---- 解锁 / 进入门槛 ----
-- 副本解锁：到达过(或达等级足够进入)其解锁地区即视为可见。这里用"等级 >= min_lvl*0.6"作粗解锁，
--   再叠地区曾否可达(玩家等级够进解锁区)。简单稳健：min_lvl 之上的副本默认可尝试。
function dungeon.unlocked(dg)
    -- 解锁区存在且玩家等级达到其下限即解锁(对应"地区进度解锁"，不另存解锁表，避免膨胀)
    local rg; for _,r in ipairs(D.REGIONS) do if r.id==dg.unlock then rg=r end end
    if not rg then return state.player.level >= dg.min_lvl end
    return state.player.level >= rg.lo
end
function dungeon.have_key(dg)
    if not dg.key then return true end
    return inv.inv_count("mat", dg.key) > 0
end
function dungeon.can_enter(dg)
    if not dungeon.unlocked(dg) then return false, "未解锁" end
    if (state.player.energy or 0) < dg.cost_energy then return false, "许可不足" end
    if not dungeon.have_key(dg) then return false, "缺钥匙" end
    return true
end

-- ---- 进入：扣许可/钥匙 → 建立运行态 → 切到战斗推进(activity 暂存) ----
function dungeon.enter(dg)
    local ok = dungeon.can_enter(dg)
    if not ok then return false end
    state.player.energy = state.player.energy - dg.cost_energy
    if dg.key then inv.inv_remove("mat", dg.key, 1) end
    state.dungeon_result = nil
    state.dungeon_run = {
        dg = dg, lvl = dg.min_lvl, total = dg.waves, wave = 1, phase = "wave",
        prev_activity = state.activity, prev_enemy = nil, failed = false,
    }
    state.panel_open = nil
    state.projectiles = {}
    state.player.hp = state.player.max_hp   -- 进副本满血开打(挂机友好)
    state.enemy = nil
    dungeon.spawn_wave_mob()
    return true
end

-- 波次小怪：从副本 mobs(无则解锁区 enemies)随机一只，等级用副本档。
function dungeon.spawn_wave_mob()
    local run = state.dungeon_run; local dg = run.dg
    local pool = dg.mobs
    if not pool or #pool==0 then
        local rg; for _,r in ipairs(D.REGIONS) do if r.id==dg.unlock then rg=r end end
        pool = (rg and rg.enemies) or {"wolf"}
    end
    -- 临时把区域 lo/hi 锚到副本等级，让 make_enemy 的随机等级落在副本档(战斗后还原)
    local arch = pool[math.random(#pool)]
    local en = combat.make_enemy(arch, "normal", run.lvl)
    state.enemy = en
end

function dungeon.spawn_boss()
    local run = state.dungeon_run
    state.enemy = combat.make_boss(run.dg.boss, run.lvl)
    fx.set_toast("BOSS：".. (state.enemy.name or "") .. (state.enemy.tip and ("  ("..state.enemy.tip..")") or ""), UI.gold)
end

-- ---- 结算掉落(肥包)：保底 rar_floor 起一件、unique 命名武器、特殊材料、钥匙 ----
local function rar_at_least(floor_id)
    local floor = RAR[floor_id] and RAR[floor_id].tier or 1
    -- 在 [floor, legendary] 间偏低随机(多数保底档，少数升档)
    local roll = math.random()
    local up = (roll<0.55) and 0 or (roll<0.85 and 1 or 2)
    local tier = math.min(#RARITIES, floor + up)
    return RARITIES[tier].id
end
function dungeon.roll_rewards(dg, lvl)
    local res = { dg=dg, win=true, loot={}, mats={}, key=nil, xp=0 }
    res.xp = lvl*60
    -- 装备：保底一件 rar_floor 起；有概率出命名武器(unique)
    local ilvl = lvl + 4
    local n_gear = 1 + math.random(2)   -- 1~3 件
    for i=1,n_gear do
        local rid = rar_at_least(dg.drops.rar_floor)
        local slot = SLOTS[math.random(#SLOTS)]
        if i==1 and dg.drops.unique_chance and math.random() < dg.drops.unique_chance then
            slot = "bow"   -- unique 武器：弓槽 + 蓝+稀有度 → roll_gear 命中 NAMED_WEAPONS 唯一名池
            if RAR[rid].tier < RAR.rare.tier then rid = "rare" end
        end
        local g = inv.roll_gear(slot, ilvl, rid)
        res.loot[#res.loot+1] = g
    end
    -- 特殊材料(保底量 + 少量浮动)
    for id,base in pairs(dg.drops.mats or {}) do
        res.mats[id] = (res.mats[id] or 0) + base + math.random(0, math.ceil(base*0.5))
    end
    -- boss 钥匙掉落
    if dg.drops.key_chance and dg.drops.key_id and math.random() < dg.drops.key_chance then
        res.key = dg.drops.key_id
    end
    return res
end

-- 失败安慰产出：少量经验 + 一点点材料(减少损失，不空手)
function dungeon.roll_consolation(dg, lvl)
    local res = { dg=dg, win=false, loot={}, mats={}, key=nil, xp=math.floor(lvl*60*0.2) }
    for id,base in pairs(dg.drops.mats or {}) do
        local q = math.max(1, math.floor(base*0.3))
        res.mats[id] = q
    end
    return res
end

-- 把结算结果实际发放到背包/经验(装备进背包、材料/钥匙进背包、经验给角色)
function dungeon.grant(res)
    if res.xp>0 then prog.gain_xp(res.xp) end
    for _,g in ipairs(res.loot) do inv.inv_add("gear", nil, 1, g) end
    for id,q in pairs(res.mats) do inv.inv_add("mat", id, q) end
    if res.key then inv.inv_add("mat", res.key, 1) end
    prog.recalc()
end

-- 结束副本：发结算弹窗 + 还原活动态(回到进副本前的活动)
local function finish(res)
    local run = state.dungeon_run
    dungeon.grant(res)
    state.dungeon_result = res
    state.dungeon_run = nil
    state.enemy = nil
    state.projectiles = {}
    state.activity = (run and run.prev_activity) or "rest"
    fx.set_toast(res.win and ("通关 "..res.dg.name.."！") or ("副本失败："..res.dg.name), res.win and UI.gold or UI.bad)
end

-- ---- 副本推进 tick：由主循环在 dungeon_run 存在时调用，先推 combat，再判波次/boss/结算 ----
function dungeon.tick(dt)
    local run = state.dungeon_run
    if not run then return end
    -- 阵亡(combat.enemy_attack 标 failed)：结算安慰产出
    if run.failed or (state.player.hp and state.player.hp<=0) then
        finish(dungeon.roll_consolation(run.dg, run.lvl)); return
    end
    -- 没敌人了 = 当前波/boss 被清，推进
    if not state.enemy then
        if run.phase=="wave" then
            if run.wave < run.total then
                run.wave = run.wave + 1; dungeon.spawn_wave_mob()
            else
                run.phase = "boss"; dungeon.spawn_boss()
            end
        elseif run.phase=="boss" then
            finish(dungeon.roll_rewards(run.dg, run.lvl)); return
        end
        return
    end
    -- 有敌人：复用战斗 tick(dungeon_run 标志会让 combat 不自动刷怪/不掉区域 loot)
    combat.tick(dt)
end

-- 放弃副本(UI 关闭/退出)：不结算、还原活动
function dungeon.abandon()
    local run = state.dungeon_run; state.dungeon_run=nil; state.enemy=nil; state.projectiles={}
    if run then state.activity = run.prev_activity or "rest" end
end

return dungeon
