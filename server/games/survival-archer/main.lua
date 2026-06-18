-- ============================================================================
-- Survival Archer — 挂机生存弓箭手（装备驱动重做版）
-- 纯 LÖVE2D 实现，无外部依赖，无图片资源，程序化合成音效
--
-- 设计核心：纯挂机零操作。弓箭手固定左侧自动射击，敌人从右推进。
-- 战力主要来自「会掉落的多槽位装备 + 稀有度 + 词缀」，配合掉落→分解→
-- 升级的资源闭环，以及连杀倍率/无限波次/离线收益的滚雪球。
-- ============================================================================

-- ============================================================================
-- SECTION 1: 基础常量
-- ============================================================================

local DESIGN_W, DESIGN_H = 480, 800
local GROUND_FRAC = 0.62       -- 地面线在屏幕高度的比例（战斗带居中偏下）
local ARCHER_X_FRAC = 0.15     -- 弓箭手 X 位置比例
local MAX_ARROWS = 120         -- 同屏箭矢上限（多重/穿透会增加用量）
local MAX_ENEMIES = 40
local BAG_LIMIT = 12           -- 背包格数，满了自动分解最弱件
local MILESTONE_WAVE = 30      -- 里程碑波次（不再是终点，只是成就提示）

-- 槽位顺序（也是 UI 显示顺序）
local SLOTS = { "bow", "quiver", "armor", "trinket" }
local SLOT_NAMES = {
    bow     = "Bow",
    quiver  = "Quiver",
    armor   = "Armor",
    trinket = "Trinket",
}

local MATERIALS = { "wood", "stone", "iron", "feather" }
local MAT_COLORS = {
    wood    = {0.6, 0.4, 0.2},
    stone   = {0.6, 0.6, 0.6},
    iron    = {0.72, 0.74, 0.8},
    feather = {0.9, 0.9, 0.85},
}
local MAT_LABELS = { wood = "Wd", stone = "St", iron = "Ir", feather = "Ft" }

local UI = {
    bg      = {0.07, 0.07, 0.11},
    panel   = {0.11, 0.11, 0.17, 0.95},
    btn     = {0.25, 0.55, 1.0},
    btn_dim = {0.18, 0.28, 0.5},
    text    = {0.93, 0.93, 0.97},
    dim     = {0.55, 0.56, 0.62},
    hp_good = {0.3, 0.78, 0.42},
    hp_bad  = {0.85, 0.25, 0.25},
    gold_c  = {1.0, 0.84, 0.2},
    exp_c   = {0.35, 0.62, 1.0},
}

-- ============================================================================
-- SECTION 2: 装备系统数据表
-- ============================================================================

-- 稀有度：mult 缩放 base 属性，affixes 决定附带词缀条数，weight 是掉落权重。
local RARITIES = {
    { id = "common",    name = "Common",    mult = 1.0,  affixes = 0, weight = 100, color = {0.75, 0.75, 0.78} },
    { id = "uncommon",  name = "Uncommon",  mult = 1.35, affixes = 1, weight = 55,  color = {0.4, 0.85, 0.4} },
    { id = "rare",      name = "Rare",      mult = 1.8,  affixes = 2, weight = 24,  color = {0.35, 0.6, 1.0} },
    { id = "epic",      name = "Epic",      mult = 2.5,  affixes = 3, weight = 8,   color = {0.75, 0.4, 1.0} },
    { id = "legendary", name = "Legendary", mult = 3.6,  affixes = 4, weight = 2,   color = {1.0, 0.62, 0.15} },
}
local RARITY_BY_ID = {}
for i, r in ipairs(RARITIES) do RARITY_BY_ID[r.id] = r; r.tier = i end

-- 弹道行为：让不同武器在「纯挂机」下也肉眼可辨。
--   single — 单发命中即消失
--   pierce — 穿透 N 个敌人
--   multi  — 一次射 N 发扇形
--   splash — 命中产生范围溅射
-- 这些是 base 的「自带行为」；词缀还能在此之上叠加 +穿透/+多重。

-- 每个 base 的属性键含义（缺省为 0）：
--   dmg          基础伤害加成
--   atk_spd      攻速（次/秒）基准，仅 bow 提供；其它槽位用 atk_spd_pct 百分比
--   max_hp       最大生命加成
--   crit         暴击率（0~1）
--   crit_mult    暴击倍率加成
--   multishot    额外箭矢数
--   pierce       穿透数
--   splash       溅射半径（设计单位）
--   gold_find    金币加成（百分比，0.2 = +20%）
--   exp_find     经验加成（百分比）
--   lifesteal    吸血（百分比，按伤害回血）
--   hp_regen     每秒回血
--   dr           减伤（0~0.8）
--   arrow_regen  每秒自动补箭数（仅 quiver）

local GEAR_BASES = {
    bow = {
        { id = "short_bow",    name = "Short Bow",    wave = 1,  behavior = "single", dmg = 6,  atk_spd = 1.4, color = {0.6, 0.42, 0.2} },
        { id = "recurve_bow",  name = "Recurve Bow",  wave = 3,  behavior = "single", dmg = 11, atk_spd = 1.5, crit = 0.05, color = {0.7, 0.5, 0.22} },
        { id = "long_bow",     name = "Long Bow",     wave = 6,  behavior = "pierce", dmg = 16, atk_spd = 1.1, pierce = 1, color = {0.55, 0.4, 0.7} },
        { id = "twin_bow",     name = "Twin Bow",     wave = 9,  behavior = "multi",  dmg = 13, atk_spd = 1.3, multishot = 1, color = {0.4, 0.7, 0.75} },
        { id = "siege_bow",    name = "Siege Bow",    wave = 13, behavior = "splash", dmg = 24, atk_spd = 0.95, splash = 32, color = {0.85, 0.45, 0.2} },
        { id = "storm_bow",    name = "Storm Bow",    wave = 18, behavior = "multi",  dmg = 22, atk_spd = 1.6, multishot = 2, crit = 0.08, color = {0.4, 0.8, 1.0} },
        { id = "dragon_bow",   name = "Dragon Bow",   wave = 24, behavior = "pierce", dmg = 40, atk_spd = 1.2, pierce = 3, crit = 0.1, color = {1.0, 0.4, 0.25} },
    },
    quiver = {
        { id = "leather_quiver",  name = "Leather Quiver",  wave = 1,  arrow_regen = 3,  color = {0.55, 0.4, 0.25} },
        { id = "swift_quiver",    name = "Swift Quiver",    wave = 4,  arrow_regen = 4,  atk_spd_pct = 0.1, color = {0.4, 0.7, 0.5} },
        { id = "barbed_quiver",   name = "Barbed Quiver",   wave = 8,  arrow_regen = 4,  pierce = 1, dmg = 5, color = {0.7, 0.5, 0.3} },
        { id = "split_quiver",    name = "Split Quiver",    wave = 12, arrow_regen = 5,  multishot = 1, color = {0.5, 0.6, 0.85} },
        { id = "hunter_quiver",   name = "Hunter Quiver",   wave = 17, arrow_regen = 6,  crit = 0.1, crit_mult = 0.5, color = {0.85, 0.7, 0.3} },
        { id = "infinity_quiver", name = "Infinity Quiver", wave = 23, arrow_regen = 9,  multishot = 1, pierce = 1, color = {0.7, 0.45, 1.0} },
    },
    armor = {
        { id = "cloth_armor",   name = "Cloth Armor",   wave = 1,  max_hp = 30,  color = {0.6, 0.55, 0.5} },
        { id = "leather_armor", name = "Leather Armor", wave = 4,  max_hp = 60,  dr = 0.05, color = {0.6, 0.42, 0.28} },
        { id = "chain_armor",   name = "Chain Armor",   wave = 9,  max_hp = 110, dr = 0.1,  color = {0.65, 0.66, 0.72} },
        { id = "plate_armor",   name = "Plate Armor",   wave = 14, max_hp = 180, dr = 0.16, hp_regen = 2, color = {0.75, 0.77, 0.82} },
        { id = "rune_armor",    name = "Rune Armor",    wave = 20, max_hp = 280, dr = 0.22, hp_regen = 5, color = {0.5, 0.7, 1.0} },
    },
    trinket = {
        { id = "copper_ring",  name = "Copper Ring",  wave = 2,  gold_find = 0.2, color = {0.8, 0.55, 0.3} },
        { id = "scholar_amulet", name = "Scholar Amulet", wave = 5, exp_find = 0.3, color = {0.5, 0.7, 0.9} },
        { id = "vampire_fang", name = "Vampire Fang", wave = 10, lifesteal = 0.06, dmg = 6, color = {0.8, 0.25, 0.3} },
        { id = "lucky_clover", name = "Lucky Clover", wave = 15, gold_find = 0.4, crit = 0.08, color = {0.4, 0.8, 0.4} },
        { id = "war_totem",    name = "War Totem",    wave = 21, dmg = 18, crit = 0.1, crit_mult = 0.6, color = {0.9, 0.4, 0.2} },
    },
}
-- 索引：base_id -> base（跨槽位查找，存档反序列化用）
local BASE_BY_ID = {}
for slot, list in pairs(GEAR_BASES) do
    for _, b in ipairs(list) do b.slot = slot; BASE_BY_ID[b.id] = b end
end

-- 词缀池：掉落时按稀有度滚 N 条。每条在 [min,max] 区间内随机。
-- kind = "pct" 的值是百分比小数；"flat" 是直接数值；"int" 取整。
local AFFIX_POOL = {
    { key = "dmg_pct",    name = "+%d%% DMG",      kind = "pct",  min = 0.08, max = 0.4 },
    { key = "crit",       name = "+%d%% Crit",     kind = "pct",  min = 0.03, max = 0.15 },
    { key = "crit_mult",  name = "+%d%% Crit Dmg", kind = "pct",  min = 0.15, max = 0.6 },
    { key = "atk_spd_pct",name = "+%d%% Atk Spd",  kind = "pct",  min = 0.05, max = 0.25 },
    { key = "max_hp",     name = "+%d HP",         kind = "int",  min = 20,   max = 120 },
    { key = "gold_find",  name = "+%d%% Gold",     kind = "pct",  min = 0.1,  max = 0.5 },
    { key = "exp_find",   name = "+%d%% EXP",      kind = "pct",  min = 0.1,  max = 0.5 },
    { key = "lifesteal",  name = "+%d%% Lifesteal",kind = "pct",  min = 0.02, max = 0.08 },
    { key = "multishot",  name = "+%d Multishot",  kind = "int",  min = 1,    max = 1 },
    { key = "pierce",     name = "+%d Pierce",     kind = "int",  min = 1,    max = 2 },
}
local AFFIX_BY_KEY = {}
for _, a in ipairs(AFFIX_POOL) do AFFIX_BY_KEY[a.key] = a end

-- 敌人类型。spd 已是上一轮调过的「停留窗口友好」值。
local ENEMY_TYPES = {
    zombie      = { name = "Zombie",      hp = 15,  spd = 16, dmg = 8,  r = 15, color = {0.35, 0.55, 0.25}, exp = 5,  drop = 0.10 },
    skeleton    = { name = "Skeleton",    hp = 10,  spd = 26, dmg = 5,  r = 12, color = {0.85, 0.85, 0.75}, exp = 4,  drop = 0.10 },
    wolf        = { name = "Wolf",        hp = 20,  spd = 36, dmg = 12, r = 13, color = {0.45, 0.38, 0.32}, exp = 8,  drop = 0.12 },
    orc         = { name = "Orc",         hp = 40,  spd = 15, dmg = 18, r = 20, color = {0.4, 0.6, 0.22},   exp = 12, drop = 0.16 },
    dark_knight = { name = "Dark Knight", hp = 60,  spd = 22, dmg = 25, r = 18, color = {0.3, 0.2, 0.4},    exp = 20, drop = 0.2 },
    dragon      = { name = "Dragon",      hp = 120, spd = 14, dmg = 40, r = 28, color = {0.85, 0.25, 0.15}, exp = 50, drop = 1.0, boss = true },
}

-- ============================================================================
-- SECTION 3: 游戏状态
-- ============================================================================

local game_state = "title"   -- title | combat | gear | death
local panel_tab  = "equip"   -- equip | bag | upgrade（gear 界面内的子页）
local sw, sh = 1, 1
local font, font_sm, font_med, font_big
local shake = 0              -- 屏震强度（draw 时平移）
local time_accum = 0        -- 全局计时（动画用，避免 Date.now）

local player
local wave
local arrows, enemies, floats, particles, toasts
local shoot_timer
local combo, combo_timer    -- 连杀倍率
local total_kills, high_wave
local sfx                   -- 程序化音效表（可能为空）
local offline_report        -- 离线收益结算（非 nil 时盖在标题上显示）

local SAVE_FILE = "survival_save_v2.txt"

-- ============================================================================
-- SECTION 4: 缩放辅助
-- ============================================================================

local function sx(v) return v * sw end
local function sy(v) return v * sh end
local function ground_y() return DESIGN_H * GROUND_FRAC * sh end
local function archer_x() return DESIGN_W * ARCHER_X_FRAC * sw end

-- ============================================================================
-- SECTION 5: 随机/工具
-- ============================================================================

local function rand_range(a, b) return a + (b - a) * math.random() end

-- atan2 兼容垫片：LuaJIT(LÖVE) 有 math.atan2；标准 Lua 5.3+ 用双参 math.atan。
local atan2 = math.atan2 or math.atan

local function weighted_rarity(boss_bonus)
    -- boss_bonus 把权重往高稀有度倾斜（Boss 掉落更好）
    local pool = {}
    local total = 0
    for _, r in ipairs(RARITIES) do
        local w = r.weight
        if boss_bonus then w = w * (1 + r.tier * boss_bonus) end
        total = total + w
        pool[#pool + 1] = { r = r, acc = total }
    end
    local roll = math.random() * total
    for _, e in ipairs(pool) do
        if roll <= e.acc then return e.r end
    end
    return RARITIES[1]
end

local function copy_color(c, a)
    return { c[1], c[2], c[3], a or 1 }
end

-- ============================================================================
-- SECTION 6: 装备实例：生成 / 评分 / 描述
-- ============================================================================

-- 从某槽位、当前波次可用的 base 中随机生成一件装备实例。
local function roll_gear(slot, max_wave, boss)
    local candidates = {}
    for _, b in ipairs(GEAR_BASES[slot]) do
        if b.wave <= max_wave then candidates[#candidates + 1] = b end
    end
    if #candidates == 0 then candidates = { GEAR_BASES[slot][1] } end
    local base = candidates[math.random(#candidates)]
    local rarity = weighted_rarity(boss and 0.6 or nil)

    -- 滚词缀：从池里不重复抽 rarity.affixes 条
    local affixes = {}
    local pool = {}
    for _, a in ipairs(AFFIX_POOL) do pool[#pool + 1] = a end
    for _ = 1, rarity.affixes do
        if #pool == 0 then break end
        local idx = math.random(#pool)
        local a = table.remove(pool, idx)
        local val
        if a.kind == "int" then
            val = math.random(a.min, a.max)
        else
            val = rand_range(a.min, a.max)
        end
        affixes[#affixes + 1] = { key = a.key, val = val }
    end

    return {
        slot = slot,
        base_id = base.id,
        rarity = rarity.id,
        affixes = affixes,
        level = 0,            -- 升级等级，每级 +10% base
    }
end

-- 把一件装备实例「展开」成属性贡献表（含 base×稀有度×升级 + 词缀）。
local function gear_stats(g)
    local base = BASE_BY_ID[g.base_id]
    local rarity = RARITY_BY_ID[g.rarity] or RARITIES[1]
    local lvl_mult = 1 + g.level * 0.1
    local s = {}

    -- base 数值属性 × 稀有度 mult × 升级 mult
    local SCALABLE = { "dmg", "max_hp", "splash", "arrow_regen", "hp_regen" }
    for _, k in ipairs(SCALABLE) do
        if base[k] then s[k] = (s[k] or 0) + base[k] * rarity.mult * lvl_mult end
    end
    -- base 的非缩放/特殊属性
    if base.atk_spd then s.atk_spd = base.atk_spd end          -- 武器基准攻速
    if base.atk_spd_pct then s.atk_spd_pct = (s.atk_spd_pct or 0) + base.atk_spd_pct end
    if base.crit then s.crit = (s.crit or 0) + base.crit end
    if base.crit_mult then s.crit_mult = (s.crit_mult or 0) + base.crit_mult end
    if base.multishot then s.multishot = (s.multishot or 0) + base.multishot end
    if base.pierce then s.pierce = (s.pierce or 0) + base.pierce end
    if base.dr then s.dr = (s.dr or 0) + base.dr end
    if base.gold_find then s.gold_find = (s.gold_find or 0) + base.gold_find end
    if base.exp_find then s.exp_find = (s.exp_find or 0) + base.exp_find end
    if base.lifesteal then s.lifesteal = (s.lifesteal or 0) + base.lifesteal end

    -- 词缀
    for _, af in ipairs(g.affixes) do
        s[af.key] = (s[af.key] or 0) + af.val
    end
    return s
end

-- 战力评分：用于「拾取后是否自动换装」和「背包满分解谁」。
local function gear_score(g)
    local s = gear_stats(g)
    local score = 0
    score = score + (s.dmg or 0) * 2
    score = score + (s.dmg_pct or 0) * 60
    score = score + (s.max_hp or 0) * 0.4
    score = score + (s.crit or 0) * 120
    score = score + (s.crit_mult or 0) * 30
    score = score + (s.atk_spd or 0) * 25
    score = score + (s.atk_spd_pct or 0) * 80
    score = score + (s.multishot or 0) * 50
    score = score + (s.pierce or 0) * 30
    score = score + (s.splash or 0) * 1.2
    score = score + (s.gold_find or 0) * 20
    score = score + (s.exp_find or 0) * 20
    score = score + (s.lifesteal or 0) * 200
    score = score + (s.dr or 0) * 150
    score = score + (s.hp_regen or 0) * 8
    score = score + (s.arrow_regen or 0) * 6
    return score
end

-- 人类可读的词缀行（UI 用）
local function affix_text(af)
    local a = AFFIX_BY_KEY[af.key]
    if not a then return "?" end
    if a.kind == "pct" then
        return string.format(a.name, math.floor(af.val * 100 + 0.5))
    else
        return string.format(a.name, math.floor(af.val + 0.5))
    end
end

local function gear_name(g)
    local base = BASE_BY_ID[g.base_id]
    local nm = base and base.name or g.base_id
    if g.level > 0 then nm = nm .. " +" .. g.level end
    return nm
end

local function gear_color(g)
    local r = RARITY_BY_ID[g.rarity] or RARITIES[1]
    return r.color
end

-- 升级一件装备的成本（随等级递增）。返回 {gold=, 主材料=amt}
local function upgrade_cost(g)
    local lvl = g.level
    local gold = 20 + lvl * lvl * 12 + lvl * 30
    -- 不同槽位吃不同主材料，制造材料需求多样性
    local mat = ({ bow = "wood", quiver = "feather", armor = "iron", trinket = "stone" })[g.slot]
    local amt = 3 + lvl * 2
    return gold, mat, amt
end

-- ============================================================================
-- SECTION 7: 玩家属性聚合（战力主来源 = 已装备的 4 件装备）
-- ============================================================================

local function recalc_stats()
    -- 极低的裸身基础：没有任何装备也能勉强戳死僵尸，但全靠装备成长。
    local agg = {
        dmg = 2, dmg_pct = 0, atk_spd = 1.0, atk_spd_pct = 0,
        max_hp = 60, crit = 0.02, crit_mult = 1.5,
        multishot = 0, pierce = 0, splash = 0,
        gold_find = 0, exp_find = 0, lifesteal = 0,
        hp_regen = 0, dr = 0, arrow_regen = 1,
    }

    local best_atk_spd = nil  -- 武器决定攻速基准；取已装备 bow 的 atk_spd
    for _, slot in ipairs(SLOTS) do
        local g = player.equip[slot]
        if g then
            local s = gear_stats(g)
            if s.atk_spd then best_atk_spd = s.atk_spd end
            for k, v in pairs(s) do
                if k ~= "atk_spd" then
                    agg[k] = (agg[k] or 0) + v
                end
            end
        end
    end
    if best_atk_spd then agg.atk_spd = best_atk_spd end

    -- 等级给一点裸 HP，让升级也有点意义但不喧宾夺主
    agg.max_hp = agg.max_hp + player.level * 8

    -- 最终派生
    player.damage = (agg.dmg) * (1 + agg.dmg_pct)
    player.attack_speed = math.max(0.18, 1 / (agg.atk_spd * (1 + agg.atk_spd_pct)))
    player.max_hp = math.floor(agg.max_hp)
    player.crit = math.min(0.9, agg.crit)
    player.crit_mult = agg.crit_mult
    player.multishot = math.floor(agg.multishot)
    player.pierce = math.floor(agg.pierce)
    player.splash = agg.splash
    player.gold_find = agg.gold_find
    player.exp_find = agg.exp_find
    player.lifesteal = agg.lifesteal
    player.hp_regen = agg.hp_regen
    player.dr = math.min(0.8, agg.dr)
    player.arrow_regen = agg.arrow_regen
    player.range = 600 * sw   -- 全屏射程；射程不再是差异点，弹道行为才是

    if player.hp then player.hp = math.min(player.hp, player.max_hp) end
    -- DPS 估算（离线收益 + UI 显示用）：含暴击期望与多重
    local hits = 1 + player.multishot
    local crit_factor = 1 + player.crit * (player.crit_mult - 1)
    player.dps = player.damage * hits * crit_factor / player.attack_speed
end

-- ============================================================================
-- SECTION 8: 存档（含装备实例序列化 + 离线时间戳）
-- ============================================================================
-- 格式：行式 key=value，装备用紧凑串。简单、健壮、缺字段可降级。

local function ser_gear(g)
    -- slot:base_id:rarity:level:key,val|key,val
    local af = {}
    for _, a in ipairs(g.affixes) do
        af[#af + 1] = a.key .. "," .. string.format("%.4f", a.val)
    end
    return table.concat({ g.slot, g.base_id, g.rarity, g.level, table.concat(af, "|") }, ":")
end

local function deser_gear(str)
    local slot, base_id, rarity, level, afstr = str:match("([^:]*):([^:]*):([^:]*):([^:]*):(.*)")
    if not base_id or not BASE_BY_ID[base_id] then return nil end
    local g = {
        slot = slot, base_id = base_id,
        rarity = RARITY_BY_ID[rarity] and rarity or "common",
        level = tonumber(level) or 0,
        affixes = {},
    }
    if afstr and afstr ~= "" then
        for pair in afstr:gmatch("[^|]+") do
            local k, v = pair:match("([^,]+),([^,]+)")
            if k and v and AFFIX_BY_KEY[k] then
                g.affixes[#g.affixes + 1] = { key = k, val = tonumber(v) or 0 }
            end
        end
    end
    return g
end

local function save_game()
    if not player then return end
    local lines = {}
    lines[#lines + 1] = "v=2"
    lines[#lines + 1] = "level=" .. player.level
    lines[#lines + 1] = "exp=" .. math.floor(player.exp)
    lines[#lines + 1] = "gold=" .. math.floor(player.gold)
    lines[#lines + 1] = "high_wave=" .. high_wave
    lines[#lines + 1] = "total_kills=" .. total_kills
    lines[#lines + 1] = "arrows=" .. math.floor(player.arrow_count)
    lines[#lines + 1] = "dps=" .. math.floor(player.dps or 0)
    lines[#lines + 1] = "time=" .. os.time()
    -- 材料
    local mats = {}
    for _, m in ipairs(MATERIALS) do mats[#mats + 1] = m .. "," .. (player.materials[m] or 0) end
    lines[#lines + 1] = "mats=" .. table.concat(mats, "|")
    -- 已装备
    for _, slot in ipairs(SLOTS) do
        if player.equip[slot] then
            lines[#lines + 1] = "eq_" .. slot .. "=" .. ser_gear(player.equip[slot])
        end
    end
    -- 背包
    for i, g in ipairs(player.bag) do
        lines[#lines + 1] = "bag=" .. ser_gear(g)
    end
    love.filesystem.write(SAVE_FILE, table.concat(lines, "\n"))
end

local function load_game()
    if not love.filesystem.getInfo(SAVE_FILE) then return nil end
    local raw = love.filesystem.read(SAVE_FILE)
    if not raw then return nil end
    local d = { equip = {}, bag = {}, materials = {} }
    for line in raw:gmatch("[^\n]+") do
        local k, v = line:match("([^=]+)=(.*)")
        if k then
            if k == "mats" then
                for pair in v:gmatch("[^|]+") do
                    local m, n = pair:match("([^,]+),([^,]+)")
                    if m then d.materials[m] = tonumber(n) or 0 end
                end
            elseif k == "bag" then
                local g = deser_gear(v)
                if g then d.bag[#d.bag + 1] = g end
            elseif k:match("^eq_") then
                local slot = k:sub(4)
                local g = deser_gear(v)
                if g then d.equip[slot] = g end
            else
                d[k] = v
            end
        end
    end
    return d
end

-- ============================================================================
-- SECTION 9: 初始化 / 重置
-- ============================================================================

local function init_player(saved)
    player = {
        x = 0, y = 0,
        hp = 60, max_hp = 60,
        level = 1, exp = 0, exp_next = 100,
        gold = 0,
        arrow_count = 40,
        materials = { wood = 8, stone = 5, iron = 0, feather = 4 },
        equip = {},     -- slot -> gear instance
        bag = {},       -- 未装备的装备实例
        shoot_anim = 0,
    }

    if saved then
        player.level = tonumber(saved.level) or 1
        player.exp = tonumber(saved.exp) or 0
        player.gold = tonumber(saved.gold) or 0
        player.arrow_count = tonumber(saved.arrows) or 40
        for _, m in ipairs(MATERIALS) do
            player.materials[m] = saved.materials[m] or player.materials[m] or 0
        end
        player.equip = saved.equip or {}
        player.bag = saved.bag or {}
    end

    -- 保底起始装备：没有 bow 就给一把短弓，保证能开打
    if not player.equip.bow then
        player.equip.bow = { slot = "bow", base_id = "short_bow", rarity = "common", level = 0, affixes = {} }
    end

    recalc_stats()
    player.hp = player.max_hp
    player.exp_next = 50 + player.level * 50
end

local function init_wave(num)
    num = num or 1
    wave = {
        number = num,
        spawned = 0,
        total = 8 + num * 3,                          -- 更多怪，战场更热闹
        timer = 0.3,
        interval = math.max(0.16, 0.65 - num * 0.025), -- 刷得更快，同屏密度更高
        boss_spawned = false,
    }
end

local function init_runtime()
    arrows, enemies = {}, {}
    floats, particles, toasts = {}, {}, {}
    shoot_timer = 0
    combo, combo_timer = 0, 0
    shake = 0
end

local function start_game(saved)
    init_player(saved)
    init_runtime()
    total_kills = tonumber(saved and saved.total_kills) or total_kills or 0
    high_wave = tonumber(saved and saved.high_wave) or high_wave or 0
    init_wave(1)
    game_state = "combat"
end

-- ============================================================================
-- SECTION 10: 程序化音效（零资源文件；合成失败则静默）
-- ============================================================================
-- 用 SoundData 现场合成短音。全程 pcall，任何失败都退化为「没有声音」，
-- 绝不影响游戏逻辑——符合框架「零依赖、零资源」约束。

local function synth(freq, dur, kind, vol)
    local rate = 22050
    local n = math.floor(rate * dur)
    local sd = love.sound.newSoundData(n, rate, 16, 1)
    for i = 0, n - 1 do
        local t = i / rate
        local env = 1 - (i / n)            -- 线性衰减包络
        local s
        if kind == "noise" then
            s = (math.random() * 2 - 1)
        elseif kind == "square" then
            s = (math.sin(2 * math.pi * freq * t) > 0) and 1 or -1
        else
            s = math.sin(2 * math.pi * freq * t)
        end
        sd:setSample(i, s * env * env * (vol or 0.5))
    end
    return love.audio.newSource(sd, "static")
end

local function build_sfx()
    sfx = {}
    local defs = {
        shoot  = { 440, 0.06, "square", 0.18 },
        hit    = { 220, 0.05, "sine",   0.25 },
        crit   = { 880, 0.12, "square", 0.3 },
        kill   = { 160, 0.12, "noise",  0.22 },
        gold   = { 1200, 0.08, "sine",  0.25 },
        upgrade= { 660, 0.18, "square", 0.3 },
        drop   = { 990, 0.1,  "sine",   0.28 },
        hurt   = { 110, 0.15, "noise",  0.3 },
    }
    for name, d in pairs(defs) do
        local ok, src = pcall(synth, d[1], d[2], d[3], d[4])
        if ok then sfx[name] = src end
    end
end

local function play(name)
    if sfx and sfx[name] then
        local s = sfx[name]
        pcall(function() s:stop(); s:play() end)
    end
end

-- ============================================================================
-- SECTION 11: 反馈系统（飘字 / 粒子 / 屏震 / toast）
-- ============================================================================

local function add_shake(amt)
    shake = math.min(24, shake + amt)
end

local function add_float(x, y, text, color, scale)
    floats[#floats + 1] = {
        x = x, y = y, text = text, color = color or UI.text,
        timer = 0.9, scale = scale or 1, vy = -40,
    }
end

local function burst_particles(x, y, color, count, power)
    for _ = 1, count do
        local ang = math.random() * math.pi * 2
        local spd = rand_range(40, 160) * power
        particles[#particles + 1] = {
            x = x, y = y,
            vx = math.cos(ang) * spd * sw,
            vy = math.sin(ang) * spd * sh - 40 * sh,
            life = rand_range(0.3, 0.7),
            max_life = 0.7,
            size = rand_range(2, 5) * sw,
            color = color,
        }
    end
end

local function add_toast(text, color)
    toasts[#toasts + 1] = { text = text, color = color or UI.text, timer = 2.6 }
end

-- ============================================================================
-- SECTION 12: 掉落 / 背包 / 自动装备 / 分解 / 升级
-- ============================================================================

-- 把一件装备分解成材料（按稀有度 + 升级返还）。
local function salvage(g)
    local rarity = RARITY_BY_ID[g.rarity] or RARITIES[1]
    local base_amt = rarity.tier + g.level
    local mat = ({ bow = "wood", quiver = "feather", armor = "iron", trinket = "stone" })[g.slot]
    player.materials[mat] = (player.materials[mat] or 0) + base_amt
    -- 附带一点通用材料
    player.materials.stone = (player.materials.stone or 0) + 1
    return mat, base_amt
end

-- 背包加一件；满了就把背包里评分最低的（含新件）分解掉。
local function bag_add(g)
    player.bag[#player.bag + 1] = g
    if #player.bag > BAG_LIMIT then
        local worst_i, worst_s = 1, math.huge
        for i, b in ipairs(player.bag) do
            local s = gear_score(b)
            if s < worst_s then worst_s = s; worst_i = i end
        end
        local removed = table.remove(player.bag, worst_i)
        local mat, amt = salvage(removed)
        add_toast("Bag full: salvaged " .. gear_name(removed) .. " (+" .. amt .. " " .. MAT_LABELS[mat] .. ")", UI.dim)
    end
end

-- 装备一件（来自背包），把原装备退回背包。
local function equip_from_bag(bag_index)
    local g = player.bag[bag_index]
    if not g then return end
    table.remove(player.bag, bag_index)
    local old = player.equip[g.slot]
    player.equip[g.slot] = g
    if old then player.bag[#player.bag + 1] = old end
    recalc_stats()
    play("upgrade")
    save_game()
end

-- 处理一件掉落：若比当前同槽位强则自动装备，否则进背包。
local function acquire_gear(g)
    local cur = player.equip[g.slot]
    local rarity = RARITY_BY_ID[g.rarity]
    if not cur or gear_score(g) > gear_score(cur) * 1.05 then
        -- 自动换装（高 5% 才换，避免反复横跳）
        if cur then bag_add(cur) end
        player.equip[g.slot] = g
        recalc_stats()
        add_toast("New " .. rarity.name .. " " .. SLOT_NAMES[g.slot] .. "!", rarity.color)
        play("drop")
    else
        bag_add(g)
    end
end

-- 升级已装备的某槽位装备。
local function upgrade_equipped(slot)
    local g = player.equip[slot]
    if not g then return false end
    local gold, mat, amt = upgrade_cost(g)
    if player.gold < gold or (player.materials[mat] or 0) < amt then return false end
    player.gold = player.gold - gold
    player.materials[mat] = player.materials[mat] - amt
    g.level = g.level + 1
    recalc_stats()
    play("upgrade")
    save_game()
    return true
end

-- ============================================================================
-- SECTION 13: 波次（无限 + 指数缩放）
-- ============================================================================

-- 波次缩放：前期线性，30 波后转指数，制造「越挂越肉、逼升级」的滚雪球压力。
local function wave_mult(n)
    if n <= MILESTONE_WAVE then
        return 1 + (n - 1) * 0.15
    else
        return (1 + (MILESTONE_WAVE - 1) * 0.15) * (1.08 ^ (n - MILESTONE_WAVE))
    end
end

local function pick_enemy_type(wn)
    local pool = { "zombie", "skeleton" }
    if wn >= 5 then pool[#pool + 1] = "wolf" end
    if wn >= 9 then pool[#pool + 1] = "orc"; pool[#pool + 1] = "orc" end
    if wn >= 14 then pool[#pool + 1] = "dark_knight"; pool[#pool + 1] = "dark_knight" end
    return pool[math.random(#pool)]
end

local function spawn_enemy(type_id, mult)
    if #enemies >= MAX_ENEMIES then return end
    local et = ENEMY_TYPES[type_id]
    local w = love.graphics.getWidth()
    local hp = et.hp * mult
    -- 垂直 lane：敌人在地面线上方的一条地带里错开推进，填满竖直空间，
    -- 也让多重箭的扇形能命中不同高度的目标（boss 走地面线、显得更重）。
    local lane = et.boss and 0 or rand_range(-200, 10) * sh
    enemies[#enemies + 1] = {
        type_id = type_id,
        x = w + et.r * sw + math.random(0, 220) * sw,
        y = ground_y() + lane,
        hp = hp, max_hp = hp,
        spd = et.spd * sw,
        dmg = et.dmg * (0.6 + mult * 0.4),  -- 伤害也随波缩放但更温和
        r = et.r,
        color = et.color,
        flash = 0, knock = 0,
        walk_phase = math.random() * math.pi * 2,
        spawn_anim = et.boss and 1.0 or 0,
    }
    if et.boss then add_shake(8); play("hurt") end
end

local function update_waves(dt)
    local mult = wave_mult(wave.number)

    -- Boss：每 5 波，波首一条龙
    if wave.number % 5 == 0 and not wave.boss_spawned then
        spawn_enemy("dragon", mult * 2.5)
        wave.boss_spawned = true
        add_toast("! Boss Wave " .. wave.number, UI.hp_bad)
    end

    if wave.spawned < wave.total then
        wave.timer = wave.timer - dt
        if wave.timer <= 0 then
            spawn_enemy(pick_enemy_type(wave.number), mult)
            wave.spawned = wave.spawned + 1
            wave.timer = wave.interval
        end
    end

    -- 清波
    if wave.spawned >= wave.total and #enemies == 0 then
        local reward = math.floor(wave.number * 3 * (1 + player.gold_find))
        player.gold = player.gold + reward
        player.hp = math.min(player.max_hp, player.hp + math.floor(player.max_hp * 0.12))
        add_float(love.graphics.getWidth() / 2, ground_y() - sy(80),
                  "Wave " .. wave.number .. " Clear  +" .. reward .. "g", UI.gold_c, 1.2)
        high_wave = math.max(high_wave, wave.number)
        if wave.number == MILESTONE_WAVE then
            add_toast("Milestone: " .. MILESTONE_WAVE .. " waves! Endless mode continues...", UI.gold_c)
        end
        init_wave(wave.number + 1)
        save_game()
    end
end

-- ============================================================================
-- SECTION 14: 战斗
-- ============================================================================

local function find_target()
    local best, best_x = nil, math.huge
    for _, e in ipairs(enemies) do
        if e.x < best_x then best_x = e.x; best = e end
    end
    return best
end

local ARROW_SPD = 620

-- 朝一个基准角度发射；angle_off 在基准上叠加扇形偏移。
local function spawn_arrow(base_ang, angle_off)
    local ang = base_ang + angle_off
    arrows[#arrows + 1] = {
        x = archer_x() + sx(20),
        y = ground_y() - sy(20),
        vx = math.cos(ang) * ARROW_SPD * sw,
        vy = math.sin(ang) * ARROW_SPD * sw,
        dmg = player.damage,
        pierce_left = player.pierce,
        splash = player.splash,
        hit_set = {},          -- 穿透时记录已命中敌人，避免重复
        color = gear_color(player.equip.bow),
        crit = math.random() < player.crit,
    }
end

local function fire()
    if player.arrow_count <= 0 then return end
    if #arrows >= MAX_ARROWS then return end
    local target = find_target()
    if not target then return end

    player.arrow_count = player.arrow_count - 1
    player.shoot_anim = 1.0

    -- 瞄准目标身体中心：弓箭手朝目标的实际方向射，箭迹肉眼对准敌人。
    local sx0 = archer_x() + sx(20)
    local sy0 = ground_y() - sy(20)
    local tx = target.x
    local ty = target.y - target.r * sh
    local base_ang = atan2(ty - sy0, tx - sx0)

    -- 多重：在瞄准方向上扇形展开
    local shots = 1 + player.multishot
    if shots == 1 then
        spawn_arrow(base_ang, 0)
    else
        local spread = 0.28
        for i = 1, shots do
            local t = (i - 1) / (shots - 1) - 0.5   -- -0.5 .. 0.5
            spawn_arrow(base_ang, t * spread)
        end
    end
    play("shoot")
end

local function bump_combo()
    combo = combo + 1
    combo_timer = 2.2
end

local function combo_mult()
    -- 每 5 连杀 +0.5 倍，封顶 x6
    return math.min(6, 1 + math.floor(combo / 5) * 0.5)
end

local function on_enemy_death(e)
    local et = ENEMY_TYPES[e.type_id]
    bump_combo()
    local cm = combo_mult()

    -- 经验 & 金币（含装备加成 + 连杀倍率）
    local exp_gain = math.floor(et.exp * (1 + player.exp_find) * cm)
    player.exp = player.exp + exp_gain

    -- 击杀爆裂
    burst_particles(e.x, e.y - e.r * sh, e.color, et.boss and 28 or 12, et.boss and 2 or 1)
    add_shake(et.boss and 12 or 3)
    play(et.boss and "crit" or "kill")

    total_kills = total_kills + 1

    -- 掉落判定
    if math.random() < et.drop then
        local g = roll_gear(SLOTS[math.random(#SLOTS)], wave.number, et.boss)
        acquire_gear(g)
    end
    -- Boss 必额外掉一件好的
    if et.boss then
        acquire_gear(roll_gear(SLOTS[math.random(#SLOTS)], wave.number, true))
    end

    -- 升级检查
    while player.exp >= player.exp_next do
        player.exp = player.exp - player.exp_next
        player.level = player.level + 1
        player.exp_next = 50 + player.level * 50
        recalc_stats()
        player.hp = player.max_hp
        add_float(archer_x(), ground_y() - sy(70), "LEVEL UP  Lv" .. player.level, UI.exp_c, 1.3)
        add_shake(4)
        play("upgrade")
    end
end

local function damage_enemy(e, dmg, is_crit, at_x, at_y)
    e.hp = e.hp - dmg
    e.flash = 0.12
    e.knock = math.min(14, (e.knock or 0) + (is_crit and 10 or 5))
    -- 吸血
    if player.lifesteal > 0 then
        player.hp = math.min(player.max_hp, player.hp + dmg * player.lifesteal)
    end
    local col = is_crit and UI.gold_c or {1, 1, 1}
    add_float(at_x, at_y, (is_crit and "" or "") .. math.floor(dmg) .. (is_crit and "!" or ""),
              col, is_crit and 1.5 or 1)
    if is_crit then add_shake(4); play("crit") else play("hit") end
end

local function update_combat(dt)
    sw = love.graphics.getWidth() / DESIGN_W
    sh = love.graphics.getHeight() / DESIGN_H
    player.x = archer_x()
    player.y = ground_y()

    -- 连杀倍率衰减
    if combo > 0 then
        combo_timer = combo_timer - dt
        if combo_timer <= 0 then combo = 0 end
    end

    -- 自动补箭 + 自动射击
    player.arrow_count = math.min(999, player.arrow_count + player.arrow_regen * dt)
    shoot_timer = shoot_timer - dt
    if shoot_timer <= 0 then
        fire()
        shoot_timer = player.attack_speed
    end
    player.shoot_anim = math.max(0, player.shoot_anim - dt * 5)

    -- 回血
    if player.hp_regen > 0 and player.hp < player.max_hp then
        player.hp = math.min(player.max_hp, player.hp + player.hp_regen * dt)
    end

    -- 箭矢移动
    for i = #arrows, 1, -1 do
        local a = arrows[i]
        a.x = a.x + a.vx * dt
        a.y = a.y + a.vy * dt
        if a.x > love.graphics.getWidth() + 30 or a.y > love.graphics.getHeight() + 30 then
            table.remove(arrows, i)
        end
    end

    -- 敌人移动 + 撞到弓箭手
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        e.spawn_anim = math.max(0, (e.spawn_anim or 0) - dt)
        e.flash = math.max(0, e.flash - dt)
        e.knock = math.max(0, (e.knock or 0) - dt * 40)
        e.walk_phase = e.walk_phase + dt * 3
        e.x = e.x - e.spd * dt + (e.knock or 0) * sw * dt

        if e.x - e.r * sw <= archer_x() + sx(10) then
            local dmg = math.max(1, e.dmg * (1 - player.dr))
            player.hp = player.hp - dmg
            add_float(archer_x(), ground_y() - sy(55), "-" .. math.floor(dmg), UI.hp_bad)
            add_shake(6)
            play("hurt")
            combo = 0
            burst_particles(archer_x(), ground_y() - sy(20), {1, 0.3, 0.3}, 8, 1)
            table.remove(enemies, i)
            if player.hp <= 0 then
                player.hp = 0
                game_state = "death"
                high_wave = math.max(high_wave, wave.number)
                save_game()
                return
            end
        end
    end

    -- 箭 vs 敌人（含穿透 / 溅射 / 暴击）
    for i = #arrows, 1, -1 do
        local a = arrows[i]
        local consumed = false
        for j = #enemies, 1, -1 do
            local e = enemies[j]
            if not a.hit_set[e] then
                local dx, dy = a.x - e.x, a.y - (e.y - e.r * sh)
                if dx * dx + dy * dy < (e.r * sw + 5) ^ 2 then
                    local dmg = a.dmg * (a.crit and player.crit_mult or 1)
                    damage_enemy(e, dmg, a.crit, e.x, e.y - e.r * sh - sy(12))
                    a.hit_set[e] = true

                    -- 溅射
                    if a.splash and a.splash > 0 then
                        for k = #enemies, 1, -1 do
                            local e2 = enemies[k]
                            if e2 ~= e then
                                local d2 = (a.x - e2.x) ^ 2 + (a.y - (e2.y - e2.r * sh)) ^ 2
                                if d2 < (a.splash * sw) ^ 2 then
                                    damage_enemy(e2, dmg * 0.5, false, e2.x, e2.y - e2.r * sh)
                                end
                            end
                        end
                        burst_particles(a.x, a.y, {1, 0.6, 0.15}, 8, 1)
                    end

                    if a.pierce_left > 0 then
                        a.pierce_left = a.pierce_left - 1
                    else
                        consumed = true
                    end
                    break
                end
            end
        end
        if consumed then table.remove(arrows, i) end
    end

    -- 清死亡敌人
    for i = #enemies, 1, -1 do
        if enemies[i].hp <= 0 then
            on_enemy_death(enemies[i])
            table.remove(enemies, i)
        end
    end

    -- 粒子
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.vy = p.vy + 280 * sh * dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.life = p.life - dt
        if p.life <= 0 then table.remove(particles, i) end
    end

    -- 飘字
    for i = #floats, 1, -1 do
        local f = floats[i]
        f.y = f.y + f.vy * dt
        f.vy = f.vy + 30 * dt
        f.timer = f.timer - dt
        if f.timer <= 0 then table.remove(floats, i) end
    end

    -- toast
    for i = #toasts, 1, -1 do
        toasts[i].timer = toasts[i].timer - dt
        if toasts[i].timer <= 0 then table.remove(toasts, i) end
    end

    -- 屏震衰减
    shake = math.max(0, shake - dt * 60)

    update_waves(dt)
end

-- ============================================================================
-- SECTION 15: 绘制
-- ============================================================================

local back_btn = { x = 0, y = 0, w = 0, h = 0 }

local function layout_back()
    local w = love.graphics.getWidth()
    back_btn.w = math.floor(w * 0.16)
    back_btn.h = math.floor(back_btn.w * 0.42)
    back_btn.x = w - back_btn.w - math.floor(w * 0.02)
    back_btn.y = math.floor(w * 0.02)
end

local function draw_back_btn()
    love.graphics.setColor(0.16, 0.18, 0.26, 0.9)
    love.graphics.rectangle("fill", back_btn.x, back_btn.y, back_btn.w, back_btn.h, back_btn.h / 2)
    love.graphics.setColor(0.9, 0.92, 1.0)
    love.graphics.setFont(font_sm)
    love.graphics.printf("< Exit", back_btn.x, back_btn.y + back_btn.h * 0.28, back_btn.w, "center")
end

-- ============================================================================
-- SECTION 15b: UI 原子组件（圆角面板 / 按钮 / 进度条 / 图标 / 装备卡）
-- 所有界面共用这几块，保证视觉统一、有层次（高光+阴影），而非纯平方块。
-- ============================================================================

local function set_col(c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

-- 圆角面板：底色 + 顶部高光带 + 可选细描边
local function ui_panel(x, y, w, h, fill, border, r)
    r = r or 8 * sw
    set_col(fill or {0.12, 0.13, 0.19, 0.97})
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setColor(1, 1, 1, 0.045)
    love.graphics.rectangle("fill", x, y, w, h * 0.42, r, r)
    if border then
        set_col(border)
        love.graphics.setLineWidth(math.max(1, 1.4 * sw))
        love.graphics.rectangle("line", x, y, w, h, r, r)
        love.graphics.setLineWidth(1)
    end
end

-- 按钮：实心圆角 + 顶部亮边 + 底部暗边（伪 3D）；enabled=false 变暗
local function ui_button(x, y, w, h, label, col, enabled, fnt)
    col = col or UI.btn
    local r = 6 * sw
    if enabled == false then col = { col[1]*0.35, col[2]*0.35, col[3]*0.4 } end
    set_col(col)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setColor(1, 1, 1, 0.18)
    love.graphics.rectangle("fill", x + r, y + 1.5 * sh, w - 2 * r, h * 0.34)
    love.graphics.setColor(0, 0, 0, 0.22)
    love.graphics.rectangle("fill", x, y + h - 3 * sh, w, 3 * sh, r, r)
    fnt = fnt or font
    love.graphics.setFont(fnt)
    love.graphics.setColor(enabled == false and 0.6 or 1, enabled == false and 0.6 or 1, enabled == false and 0.65 or 1)
    love.graphics.printf(label, x, y + (h - fnt:getHeight()) / 2, w, "center")
end

-- 进度条：圆角槽 + 圆角填充 + 高光 + 可选居中文字
local function ui_bar(x, y, w, h, frac, col, label)
    frac = math.max(0, math.min(1, frac))
    local r = h / 2
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    if frac > 0 then
        set_col(col)
        local fw = math.max(h, w * frac)
        love.graphics.rectangle("fill", x, y, fw, h, r, r)
        love.graphics.setColor(1, 1, 1, 0.22)
        love.graphics.rectangle("fill", x + r, y + 1.5 * sh, math.max(0, fw - 2 * r), h * 0.32)
    end
    if label then
        love.graphics.setFont(font_sm)
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.printf(label, x, y + (h - font_sm:getHeight()) / 2 - 0.5 * sh, w, "center")
    end
end

-- 金币图标
local function icon_coin(cx, cy, s)
    love.graphics.setColor(0.75, 0.55, 0.08); love.graphics.circle("fill", cx, cy, s)
    love.graphics.setColor(1, 0.85, 0.25); love.graphics.circle("fill", cx, cy, s * 0.72)
end

-- 心形（HP）
local function icon_heart(cx, cy, s, col)
    set_col(col or UI.hp_bad)
    love.graphics.circle("fill", cx - s*0.45, cy - s*0.2, s*0.55)
    love.graphics.circle("fill", cx + s*0.45, cy - s*0.2, s*0.55)
    love.graphics.polygon("fill", cx - s*0.95, cy, cx + s*0.95, cy, cx, cy + s*1.05)
end

-- 箭图标
local function icon_arrow(cx, cy, s)
    love.graphics.setColor(0.8, 0.8, 0.85)
    love.graphics.setLineWidth(math.max(1, 1.6 * sw))
    love.graphics.line(cx - s, cy, cx + s, cy)
    love.graphics.polygon("fill", cx + s, cy - s*0.5, cx + s + s*0.6, cy, cx + s, cy + s*0.5)
    love.graphics.setLineWidth(1)
end

-- 闪电（DPS）
local function icon_bolt(cx, cy, s)
    love.graphics.setColor(1, 0.85, 0.3)
    love.graphics.polygon("fill", cx + s*0.3, cy - s, cx - s*0.5, cy + s*0.1, cx, cy + s*0.1,
                                   cx - s*0.3, cy + s, cx + s*0.5, cy - s*0.1, cx, cy - s*0.1)
end

-- 槽位图标（每种装备一个可辨识的小符号）
local function icon_slot(slot, cx, cy, s, col)
    set_col(col or UI.dim)
    love.graphics.setLineWidth(math.max(1, 1.6 * sw))
    if slot == "bow" then
        love.graphics.arc("line", "open", cx - s*0.3, cy, s, -1.1, 1.1)
        love.graphics.line(cx - s*0.3 + s*math.cos(-1.1), cy + s*math.sin(-1.1),
                           cx - s*0.3 + s*math.cos(1.1), cy + s*math.sin(1.1))
    elseif slot == "quiver" then
        love.graphics.polygon("line", cx - s*0.5, cy - s, cx + s*0.5, cy - s, cx + s*0.35, cy + s, cx - s*0.35, cy + s)
        love.graphics.line(cx - s*0.2, cy - s, cx - s*0.2, cy - s*1.4)
        love.graphics.line(cx + s*0.2, cy - s, cx + s*0.2, cy - s*1.4)
    elseif slot == "armor" then
        love.graphics.polygon("line", cx, cy - s, cx + s*0.9, cy - s*0.5, cx + s*0.7, cy + s,
                                       cx, cy + s*1.1, cx - s*0.7, cy + s, cx - s*0.9, cy - s*0.5)
    else -- trinket: 菱形
        love.graphics.polygon("line", cx, cy - s, cx + s*0.8, cy, cx, cy + s, cx - s*0.8, cy)
    end
    love.graphics.setLineWidth(1)
end

-- 材料图标：稀有色圆角小方块 + 暗边
local function icon_mat(mat, cx, cy, s)
    set_col(MAT_COLORS[mat])
    love.graphics.rectangle("fill", cx - s, cy - s, s*2, s*2, s*0.4, s*0.4)
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle("line", cx - s, cy - s, s*2, s*2, s*0.4, s*0.4)
end


local function draw_background()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local gy = ground_y()

    -- 天空渐变
    for i = 0, 12 do
        local t = i / 12
        love.graphics.setColor(0.04 + t * 0.04, 0.05 + t * 0.06, 0.13 + t * 0.03)
        love.graphics.rectangle("fill", 0, t * gy, w, gy / 12 + 1)
    end

    -- 远景山（视差层 1）
    love.graphics.setColor(0.1, 0.1, 0.16)
    for k = 0, 4 do
        local mx = (k / 4) * w + math.sin(time_accum * 0.05 + k) * 4 * sw
        love.graphics.polygon("fill", mx - 70 * sw, gy, mx, gy - 90 * sh, mx + 70 * sw, gy)
    end

    -- 中景树（视差层 2）
    for _, tx in ipairs({ 0.28, 0.48, 0.68, 0.86 }) do
        local bx = tx * w
        love.graphics.setColor(0.14, 0.1, 0.06)
        love.graphics.rectangle("fill", bx - 3 * sw, gy - 52 * sh, 6 * sw, 52 * sh)
        love.graphics.setColor(0.1, 0.2, 0.08, 0.7)
        love.graphics.circle("fill", bx, gy - 58 * sh, 20 * sw)
    end

    -- 地面
    love.graphics.setColor(0.13, 0.09, 0.05)
    love.graphics.rectangle("fill", 0, gy, w, h - gy)
    love.graphics.setColor(0.2, 0.15, 0.08)
    love.graphics.rectangle("fill", 0, gy, w, 2 * sh)
end

local function draw_archer()
    local x, y = archer_x(), ground_y()
    local s = sw
    love.graphics.setColor(0.3, 0.3, 0.4)
    love.graphics.line(x, y - 8 * sh, x - 5 * s, y)
    love.graphics.line(x, y - 8 * sh, x + 5 * s, y)
    love.graphics.setColor(0.4, 0.35, 0.3)
    love.graphics.line(x, y - 24 * sh, x, y - 8 * sh)
    love.graphics.setColor(0.85, 0.7, 0.55)
    love.graphics.circle("fill", x, y - 30 * sh, 6 * s)

    local bow_x = x + 12 * s
    local bow_y = y - 20 * sh
    local bow_r = 11 * s
    love.graphics.setColor(gear_color(player.equip.bow))
    love.graphics.setLineWidth(2)
    love.graphics.arc("line", "open", bow_x, bow_y, bow_r, -1.2, 1.2)
    local pull = player.shoot_anim * 7 * s
    love.graphics.setColor(0.8, 0.8, 0.7)
    love.graphics.line(bow_x + bow_r * math.cos(-1.2), bow_y + bow_r * math.sin(-1.2),
                       bow_x - pull, bow_y,
                       bow_x + bow_r * math.cos(1.2), bow_y + bow_r * math.sin(1.2))
    love.graphics.setColor(0.85, 0.7, 0.55)
    love.graphics.line(x, y - 20 * sh, bow_x - pull, bow_y)
    love.graphics.setLineWidth(1)
end

local function draw_enemy(e)
    local x = e.x
    local y = e.y
    local r = e.r * sw
    local bob = math.sin(e.walk_phase) * 2 * sh
    local et = ENEMY_TYPES[e.type_id]

    -- 入场淡入缩放
    local sa = e.spawn_anim or 0
    if sa > 0 then r = r * (1.4 - sa * 0.4) end

    if e.flash > 0 then love.graphics.setColor(1, 1, 1) else love.graphics.setColor(e.color) end

    if et.boss then
        love.graphics.circle("fill", x, y - r + bob, r)
        love.graphics.polygon("fill", x - r*0.5, y - r*1.8 + bob, x, y - r + bob, x + r*0.5, y - r*1.8 + bob)
        love.graphics.polygon("fill", x + r*0.8, y - r*0.5 + bob, x + r*1.3, y - r + bob, x + r*0.8, y + r*0.2 + bob)
        love.graphics.polygon("fill", x - r*0.8, y - r*0.5 + bob, x - r*1.3, y - r*0.2 + bob, x - r*0.8, y + r*0.2 + bob)
        love.graphics.setColor(1, 0.8, 0)
        love.graphics.circle("fill", x - r*0.25, y - r + bob, r*0.12)
        love.graphics.circle("fill", x + r*0.25, y - r + bob, r*0.12)
    elseif e.type_id == "skeleton" then
        love.graphics.circle("line", x, y - r + bob, r*0.7)
        love.graphics.line(x, y - r*0.3 + bob, x, y + r*0.4 + bob)
        love.graphics.line(x - r*0.5, y + bob, x + r*0.5, y + bob)
    elseif e.type_id == "wolf" then
        love.graphics.ellipse("fill", x, y - r*0.5 + bob, r*1.2, r*0.7)
        love.graphics.polygon("fill", x - r*0.5, y - r + bob, x - r*0.3, y - r*1.5 + bob, x - r*0.1, y - r + bob)
        love.graphics.polygon("fill", x + r*0.1, y - r + bob, x + r*0.3, y - r*1.5 + bob, x + r*0.5, y - r + bob)
    else
        love.graphics.rectangle("fill", x - r*0.5, y - r*1.5 + bob, r, r*1.5)
        love.graphics.circle("fill", x, y - r*1.5 + bob, r*0.5)
        if e.type_id == "orc" then
            love.graphics.setColor(0.9, 0.9, 0.7)
            love.graphics.polygon("fill", x - r*0.2, y - r*1.2 + bob, x - r*0.1, y - r*0.9 + bob, x, y - r*1.2 + bob)
        elseif e.type_id == "dark_knight" then
            love.graphics.setColor(0.15, 0.15, 0.2)
            love.graphics.rectangle("fill", x - r*0.8, y - r*1.2 + bob, r*0.3, r)
        end
    end

    -- HP 条
    local bar_w = r * 2
    local bar_y = y - r * 2 - 4 * sh + bob
    love.graphics.setColor(0.3, 0.1, 0.1)
    love.graphics.rectangle("fill", x - bar_w/2, bar_y, bar_w, 3 * sh)
    local f = math.max(0, e.hp / e.max_hp)
    love.graphics.setColor(0.2 + 0.6*(1-f), 0.6*f, 0.1)
    love.graphics.rectangle("fill", x - bar_w/2, bar_y, bar_w * f, 3 * sh)
end

local function draw_arrow_proj(a)
    love.graphics.setColor(a.crit and {1, 0.85, 0.2} or a.color)
    love.graphics.setLineWidth(a.crit and 3 or 2)
    local len = 12 * sw
    local nx = a.vx
    local ny = a.vy
    local mag = math.sqrt(nx*nx + ny*ny)
    if mag > 0 then nx, ny = nx/mag, ny/mag end
    love.graphics.line(a.x, a.y, a.x - nx*len, a.y - ny*len)
    if a.splash and a.splash > 0 then
        love.graphics.setColor(1, 0.6, 0.1)
        love.graphics.circle("fill", a.x, a.y, 3 * sw)
    end
    love.graphics.setLineWidth(1)
end

local function draw_particles()
    for _, p in ipairs(particles) do
        local a = math.max(0, p.life / p.max_life)
        love.graphics.setColor(p.color[1], p.color[2], p.color[3], a)
        love.graphics.rectangle("fill", p.x - p.size/2, p.y - p.size/2, p.size, p.size)
    end
end

local function draw_floats()
    for _, f in ipairs(floats) do
        local a = math.min(1, f.timer * 2)
        love.graphics.setFont(f.scale > 1.2 and font or font_sm)
        love.graphics.setColor(f.color[1], f.color[2], f.color[3], a)
        love.graphics.printf(f.text, f.x - 50 * sw, f.y, 100 * sw, "center")
    end
end

local function draw_low_hp_vignette()
    local f = player.hp / player.max_hp
    if f < 0.35 then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        local pulse = 0.25 + 0.15 * math.sin(time_accum * 6)
        local a = (0.35 - f) / 0.35 * pulse
        love.graphics.setColor(0.7, 0.05, 0.05, a)
        local b = 40 * sw
        love.graphics.rectangle("fill", 0, 0, w, b)
        love.graphics.rectangle("fill", 0, h - b, w, b)
        love.graphics.rectangle("fill", 0, 0, b, h)
        love.graphics.rectangle("fill", w - b, 0, b, h)
    end
end

-- ============================================================================
-- SECTION 16: HUD（顶部状态 + 底部装备速览）
-- ============================================================================

-- 底部按钮区的布局（战斗界面点开 gear 面板）
local function gear_btn_rect()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local bw = w * 0.4
    return w/2 - bw/2, h - 44 * sh, bw, 34 * sh
end

local function draw_hud()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    -- 顶部信息条（圆角下沿 + 高光）
    local bar_h = 60 * sh
    love.graphics.setColor(0.05, 0.06, 0.1, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, bar_h, 0, 0)
    love.graphics.setColor(1, 1, 1, 0.05)
    love.graphics.rectangle("fill", 0, 0, w, bar_h * 0.4)
    love.graphics.setColor(UI.btn[1], UI.btn[2], UI.btn[3], 0.5)
    love.graphics.rectangle("fill", 0, bar_h - 2 * sh, w, 2 * sh)

    -- 左：心 + HP 条
    icon_heart(16 * sw, 16 * sh, 7 * sw)
    local hf = math.max(0, player.hp / player.max_hp)
    local hcol = { UI.hp_good[1]*hf + UI.hp_bad[1]*(1-hf), UI.hp_good[2]*hf + UI.hp_bad[2]*(1-hf), UI.hp_good[3]*hf + UI.hp_bad[3]*(1-hf) }
    ui_bar(28 * sw, 9 * sh, 132 * sw, 15 * sh, hf, hcol, math.floor(player.hp) .. " / " .. player.max_hp)

    -- 左下：Lv + EXP 条
    love.graphics.setFont(font_sm)
    love.graphics.setColor(UI.exp_c)
    love.graphics.print("Lv " .. player.level, 4 * sw, 30 * sh)
    ui_bar(40 * sw, 32 * sh, 120 * sw, 11 * sh, player.exp / player.exp_next, UI.exp_c)

    -- 右上：Wave 标题
    love.graphics.setFont(font_med)
    love.graphics.setColor(UI.text)
    local wave_txt = "WAVE " .. wave.number .. (wave.number > MILESTONE_WAVE and "  ENDLESS" or "")
    love.graphics.printf(wave_txt, 0, 6 * sh, w - 10 * sw, "right")

    -- 右下：金币 / 箭 / DPS 三个 chip（带图标，右对齐排列）
    local function chip(rx, icon_fn, txt, tcol)
        local cw = 64 * sw
        local x0 = rx - cw
        icon_fn(x0 + 8 * sw, 39 * sh, 6 * sw)
        love.graphics.setFont(font_sm)
        love.graphics.setColor(tcol or UI.text)
        love.graphics.print(txt, x0 + 18 * sw, 33 * sh)
        return x0 - 4 * sw
    end
    local rx = w - 10 * sw
    rx = chip(rx, icon_bolt, math.floor(player.dps or 0), UI.text)
    rx = chip(rx, icon_arrow, math.floor(player.arrow_count), UI.dim)
    rx = chip(rx, icon_coin, math.floor(player.gold), UI.gold_c)

    -- 连杀倍率（大字，越热越红）
    if combo >= 5 then
        local cm = combo_mult()
        local heat = math.min(1, combo / 30)
        love.graphics.setFont(font_big)
        love.graphics.setColor(1, 0.9 - heat * 0.5, 0.2, 0.55 + 0.45 * (combo_timer / 2.2))
        love.graphics.printf(string.format("x%.1f", cm), 0, 66 * sh, w - 12 * sw, "right")
        love.graphics.setFont(font_sm)
        love.graphics.printf(combo .. " kills", 0, 94 * sh, w - 12 * sw, "right")
    end

    -- toast（右上堆叠，带稀有色圆点）
    love.graphics.setFont(font_sm)
    for i, t in ipairs(toasts) do
        local a = math.min(1, t.timer)
        local ty = (110 + (i-1) * 18) * sh
        local tw = font_sm:getWidth(t.text)
        love.graphics.setColor(t.color[1], t.color[2], t.color[3], a)
        love.graphics.circle("fill", w - tw - 18 * sw, ty + 6 * sh, 3 * sw)
        love.graphics.printf(t.text, 0, ty, w - 12 * sw, "right")
    end

    -- 底部：装备速览 4 槽（每槽一个圆角格 + 槽位图标 + 稀有色边框）
    local slot_top = h - 96 * sh
    love.graphics.setColor(0.06, 0.07, 0.11, 0.95)
    love.graphics.rectangle("fill", 0, slot_top - 2 * sh, w, h - slot_top + 2 * sh)
    local gap = 6 * sw
    local cellw = (w - gap * 5) / 4
    for i, slot in ipairs(SLOTS) do
        local cx = gap + (i - 1) * (cellw + gap)
        local cy = slot_top + 4 * sh
        local ch = 40 * sh
        local g = player.equip[slot]
        local border = g and gear_color(g) or { 0.25, 0.26, 0.32 }
        ui_panel(cx, cy, cellw, ch, { 0.1, 0.11, 0.16, 0.95 }, border, 5 * sw)
        icon_slot(slot, cx + 12 * sw, cy + ch/2, 8 * sw, g and gear_color(g) or UI.dim)
        love.graphics.setFont(font_sm)
        if g then
            set_col(gear_color(g))
            love.graphics.printf(BASE_BY_ID[g.base_id].name, cx + 22 * sw, cy + 5 * sh, cellw - 24 * sw, "left")
            love.graphics.setColor(UI.dim)
            love.graphics.printf(g.level > 0 and ("+" .. g.level) or "", cx + 22 * sw, cy + 21 * sh, cellw - 26 * sw, "left")
        else
            love.graphics.setColor(0.4, 0.4, 0.45)
            love.graphics.printf("empty", cx + 22 * sw, cy + 13 * sh, cellw - 24 * sw, "left")
        end
    end

    -- 打开装备面板按钮
    local bx, by, bw, bh = gear_btn_rect()
    ui_button(bx, by, bw, bh, "Gear & Upgrade", UI.btn, true, font)
end

-- ============================================================================
-- SECTION 17: 装备面板（equip / bag / upgrade 三页）
-- ============================================================================

-- 返回这些可点区域给输入处理复用
local function panel_geom()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local px, py = 16 * sw, 56 * sh
    local pw, ph = w - 32 * sw, h - 112 * sh
    return px, py, pw, ph
end

-- 一张装备卡：稀有色描边 + 稀有色淡染背景 + 左侧色条 + 槽位图标 +
-- 名称（稀有色）+ 主属性摘要 + 词缀（绿）。右侧 action_w 宽度留给操作按钮。
local function draw_gear_card(g, x, y, w, hgt, action_w)
    local rc = gear_color(g)
    -- 背景：极淡的稀有色调
    ui_panel(x, y, w, hgt, { rc[1]*0.16, rc[2]*0.16, rc[3]*0.18, 0.95 }, { rc[1]*0.7, rc[2]*0.7, rc[3]*0.7, 0.9 }, 6 * sw)
    -- 左侧稀有色条
    set_col(rc)
    love.graphics.rectangle("fill", x, y, 4 * sw, hgt, 2 * sw, 2 * sw)
    -- 槽位图标
    icon_slot(g.slot, x + 18 * sw, y + 18 * sh, 9 * sw, rc)

    local tx = x + 34 * sw
    local content_w = w - 34 * sw - (action_w or 0)
    -- 名称
    set_col(rc)
    love.graphics.setFont(font)
    love.graphics.printf(gear_name(g), tx, y + 5 * sh, content_w, "left")
    -- 主属性摘要
    local s = gear_stats(g)
    local parts = {}
    if s.dmg then parts[#parts+1] = "DMG " .. math.floor(s.dmg) end
    if s.atk_spd then parts[#parts+1] = string.format("AS %.2f", s.atk_spd) end
    if s.max_hp then parts[#parts+1] = "HP " .. math.floor(s.max_hp) end
    if s.arrow_regen then parts[#parts+1] = string.format("Regen %.0f/s", s.arrow_regen) end
    if s.dr then parts[#parts+1] = "DR " .. math.floor(s.dr*100) .. "%" end
    love.graphics.setFont(font_sm)
    love.graphics.setColor(UI.dim)
    love.graphics.printf(table.concat(parts, "   "), tx, y + 24 * sh, content_w, "left")
    -- 词缀（绿，小圆点）
    local ay = y + 40 * sh
    for _, af in ipairs(g.affixes) do
        love.graphics.setColor(0.45, 0.85, 0.55)
        love.graphics.circle("fill", tx + 3 * sw, ay + 6 * sh, 2.5 * sw)
        love.graphics.print(affix_text(af), tx + 10 * sw, ay)
        ay = ay + 15 * sh
    end
end

local function draw_gear_panel()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local px, py, pw, ph = panel_geom()
    ui_panel(px, py, pw, ph, { 0.09, 0.1, 0.15, 0.98 }, { 0.28, 0.3, 0.4 }, 10 * sw)

    -- 标题
    love.graphics.setFont(font_med)
    love.graphics.setColor(UI.text)
    love.graphics.printf("EQUIPMENT", px, py + 8 * sh, pw, "center")

    -- Tab 段控件（活动页高亮 + 底部下划线）
    local tabs = { { "equip", "Equipped" }, { "bag", "Bag " .. #player.bag }, { "upgrade", "Upgrade" } }
    local tw = (pw - 20 * sw) / 3
    local tab_y = py + 36 * sh
    for i, t in ipairs(tabs) do
        local tx = px + 10 * sw + (i-1) * tw
        local active = panel_tab == t[1]
        love.graphics.setColor(active and UI.btn[1] or 0.16, active and UI.btn[2] or 0.17, active and UI.btn[3] or 0.24, active and 0.9 or 0.7)
        love.graphics.rectangle("fill", tx + 2 * sw, tab_y, tw - 4 * sw, 28 * sh, 5 * sw)
        love.graphics.setColor(active and 1 or 0.6, active and 1 or 0.6, active and 1 or 0.65)
        love.graphics.setFont(font_sm)
        love.graphics.printf(t[2], tx, tab_y + 7 * sh, tw, "center")
    end

    local list_y = py + 74 * sh
    local card_x = px + 10 * sw
    local card_w = pw - 20 * sw
    local CARD_H = 84 * sh      -- equip/upgrade 卡高
    local CARD_STEP = 92 * sh   -- equip/upgrade 行距
    local BAG_H = 64 * sh        -- bag 卡高
    local BAG_STEP = 70 * sh     -- bag 行距

    if panel_tab == "equip" then
        for i, slot in ipairs(SLOTS) do
            local ry = list_y + (i-1) * CARD_STEP
            local g = player.equip[slot]
            if g then
                draw_gear_card(g, card_x, ry, card_w, CARD_H, 0)
            else
                ui_panel(card_x, ry, card_w, CARD_H, { 0.1, 0.1, 0.14, 0.9 }, { 0.22, 0.23, 0.28 }, 6 * sw)
                icon_slot(slot, card_x + 18 * sw, ry + CARD_H/2, 9 * sw, { 0.35, 0.35, 0.4 })
                love.graphics.setFont(font_sm)
                love.graphics.setColor(0.4, 0.4, 0.45)
                love.graphics.printf(SLOT_NAMES[slot] .. " — empty", card_x + 34 * sw, ry + CARD_H/2 - 7 * sh, card_w - 40 * sw, "left")
            end
        end
    elseif panel_tab == "bag" then
        if #player.bag == 0 then
            love.graphics.setFont(font_sm)
            love.graphics.setColor(UI.dim)
            love.graphics.printf("Bag is empty.\nKill enemies to find gear.", px, py + ph/2 - 20 * sh, pw, "center")
        end
        local aw = 72 * sw
        for i, g in ipairs(player.bag) do
            local ry = list_y + (i-1) * BAG_STEP
            if ry + BAG_H > py + ph - 64 * sh then break end
            draw_gear_card(g, card_x, ry, card_w, BAG_H, aw + 8 * sw)
            ui_button(card_x + card_w - aw, ry + BAG_H/2 - 13 * sh, aw, 26 * sh, "Equip", UI.btn, true, font_sm)
        end
    else -- upgrade
        local aw = 92 * sw
        for i, slot in ipairs(SLOTS) do
            local ry = list_y + (i-1) * CARD_STEP
            local g = player.equip[slot]
            if g then
                draw_gear_card(g, card_x, ry, card_w, CARD_H, aw + 8 * sw)
                local gold, mat, amt = upgrade_cost(g)
                local can = player.gold >= gold and (player.materials[mat] or 0) >= amt
                ui_button(card_x + card_w - aw, ry + 8 * sh, aw, 32 * sh, "Upgrade", can and { 0.3, 0.7, 0.4 } or UI.btn, can, font_sm)
                love.graphics.setFont(font_sm)
                love.graphics.setColor(can and UI.gold_c or UI.dim)
                love.graphics.printf(gold .. "g  " .. amt .. " " .. MAT_LABELS[mat], card_x + card_w - aw, ry + 46 * sh, aw, "center")
            end
        end
    end

    -- 底部材料栏（图标 + 数量）
    local mat_y = py + ph - 60 * sh
    love.graphics.setColor(0.06, 0.07, 0.11, 0.9)
    love.graphics.rectangle("fill", px + 6 * sw, mat_y - 4 * sh, pw - 12 * sw, 24 * sh, 5 * sw)
    love.graphics.setFont(font_sm)
    local mcw = (pw - 12 * sw) / 4
    for i, m in ipairs(MATERIALS) do
        local mx = px + 6 * sw + (i-1) * mcw
        icon_mat(m, mx + 16 * sw, mat_y + 8 * sh, 6 * sw)
        love.graphics.setColor(UI.text)
        love.graphics.print(player.materials[m] or 0, mx + 26 * sw, mat_y + 2 * sh)
    end

    -- 返回
    ui_button(px + pw/2 - 64 * sw, py + ph - 36 * sh, 128 * sw, 30 * sh, "Back", { 0.45, 0.28, 0.3 }, true, font)
end

-- ============================================================================
-- SECTION 18: 标题 / 死亡 / 离线结算
-- ============================================================================

local function draw_title()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    -- 垂直渐变背景
    for i = 0, 16 do
        local t = i / 16
        love.graphics.setColor(0.04 + t*0.03, 0.05 + t*0.04, 0.1 + t*0.06)
        love.graphics.rectangle("fill", 0, t*h, w, h/16 + 1)
    end

    -- 装饰弓箭（带轻微脉动）
    local cx, cy = w/2, h*0.28
    local pulse = 1 + 0.03 * math.sin(time_accum * 2)
    love.graphics.setColor(0.55, 0.4, 0.18)
    love.graphics.setLineWidth(4 * sw)
    love.graphics.arc("line", "open", cx + 30*sw, cy, 70 * sw * pulse, -1.1, 1.1)
    love.graphics.setColor(0.75, 0.75, 0.65)
    love.graphics.setLineWidth(1.5 * sw)
    love.graphics.line(cx + 30*sw + 70*sw*math.cos(-1.1), cy + 70*sh*math.sin(-1.1),
                       cx - 15*sw, cy, cx + 30*sw + 70*sw*math.cos(1.1), cy + 70*sh*math.sin(1.1))
    love.graphics.setColor(0.85, 0.6, 0.3)
    love.graphics.setLineWidth(2.5 * sw)
    love.graphics.line(cx - 15*sw, cy, cx - 95*sw, cy)
    love.graphics.polygon("fill", cx - 95*sw, cy - 5*sh, cx - 108*sw, cy, cx - 95*sw, cy + 5*sh)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(font_big)
    love.graphics.setColor(UI.text)
    love.graphics.printf("SURVIVAL ARCHER", 0, h*0.46, w, "center")
    love.graphics.setFont(font_sm)
    love.graphics.setColor(UI.gold_c)
    love.graphics.printf("IDLE  -  LOOT  -  GROW", 0, h*0.54, w, "center")

    -- Tap to Start（呼吸闪烁）
    love.graphics.setFont(font_med)
    local blink = 0.5 + 0.5 * math.sin(time_accum * 3)
    love.graphics.setColor(UI.text[1], UI.text[2], UI.text[3], 0.4 + 0.6 * blink)
    love.graphics.printf("Tap to Start", 0, h*0.64, w, "center")

    if high_wave and high_wave > 0 then
        love.graphics.setFont(font_sm)
        love.graphics.setColor(UI.dim)
        love.graphics.printf("Best Wave " .. high_wave .. "      Kills " .. (total_kills or 0), 0, h*0.72, w, "center")
    end

    -- 离线收益结算卡
    if offline_report then
        local bw, bh = w * 0.84, h * 0.16
        local bx, by = w*0.08, h*0.79
        ui_panel(bx, by, bw, bh, { 0.1, 0.12, 0.18, 0.97 }, UI.gold_c, 10 * sw)
        icon_coin(bx + 24 * sw, by + bh/2, 11 * sw)
        love.graphics.setFont(font_med)
        love.graphics.setColor(UI.text)
        love.graphics.printf("Welcome back!", bx + 30 * sw, by + 14 * sh, bw - 40 * sw, "center")
        love.graphics.setFont(font_sm)
        love.graphics.setColor(UI.gold_c)
        love.graphics.printf(offline_report, bx + 30 * sw, by + 44 * sh, bw - 40 * sw, "center")
    end
end

local function draw_death()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0.1, 0.02, 0.02, 0.88)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(font_big)
    love.graphics.setColor(UI.hp_bad)
    love.graphics.printf("YOU DIED", 0, h*0.3, w, "center")

    -- 结算卡
    local bw, bh = w * 0.7, h * 0.16
    local bx, by = w*0.15, h*0.42
    ui_panel(bx, by, bw, bh, { 0.13, 0.08, 0.09, 0.97 }, { 0.5, 0.25, 0.27 }, 10 * sw)
    love.graphics.setFont(font)
    love.graphics.setColor(UI.text)
    love.graphics.printf("Reached Wave " .. wave.number, bx, by + 14 * sh, bw, "center")
    love.graphics.setFont(font_sm)
    love.graphics.setColor(UI.dim)
    love.graphics.printf("Kills " .. total_kills .. "      Gold " .. math.floor(player.gold), bx, by + 40 * sh, bw, "center")
    love.graphics.setColor(0.5, 0.7, 0.5)
    love.graphics.printf("Gear & gold kept", bx, by + 58 * sh, bw, "center")

    love.graphics.setFont(font_med)
    local blink = 0.5 + 0.5 * math.sin(time_accum * 3)
    love.graphics.setColor(UI.gold_c[1], UI.gold_c[2], UI.gold_c[3], 0.4 + 0.6 * blink)
    love.graphics.printf("Tap to Retry", 0, h*0.66, w, "center")
end

-- ============================================================================
-- SECTION 19: 输入
-- ============================================================================

local function hit(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function handle_combat_touch(tx, ty)
    if hit(tx, ty, back_btn.x, back_btn.y, back_btn.w, back_btn.h) then
        if _G.stonegate_exit then stonegate_exit() else love.event.quit() end
        return
    end
    local bx, by, bw, bh = gear_btn_rect()
    if hit(tx, ty, bx, by, bw, bh) then
        game_state = "gear"
        panel_tab = "equip"
        return
    end
end

local function handle_gear_touch(tx, ty)
    local px, py, pw, ph = panel_geom()
    -- Tab（与 draw_gear_panel 的几何保持一致）
    local tw = (pw - 20 * sw) / 3
    local tab_y = py + 36 * sh
    local tabs = { "equip", "bag", "upgrade" }
    for i, t in ipairs(tabs) do
        if hit(tx, ty, px + 10 * sw + (i-1)*tw, tab_y, tw, 28 * sh) then panel_tab = t; return end
    end
    -- Back
    if hit(tx, ty, px + pw/2 - 64 * sw, py + ph - 36 * sh, 128 * sw, 30 * sh) then
        game_state = "combat"
        save_game()
        return
    end

    local list_y = py + 74 * sh
    local card_x = px + 10 * sw
    local card_w = pw - 20 * sw

    if panel_tab == "bag" then
        local aw = 72 * sw
        local BAG_H, BAG_STEP = 64 * sh, 70 * sh
        for i, g in ipairs(player.bag) do
            local ry = list_y + (i-1) * BAG_STEP
            if ry + BAG_H > py + ph - 64 * sh then break end
            if hit(tx, ty, card_x + card_w - aw, ry + BAG_H/2 - 13 * sh, aw, 26 * sh) then
                equip_from_bag(i)
                return
            end
        end
    elseif panel_tab == "upgrade" then
        local aw = 92 * sw
        local CARD_STEP = 92 * sh
        for i, slot in ipairs(SLOTS) do
            local ry = list_y + (i-1) * CARD_STEP
            if player.equip[slot] and hit(tx, ty, card_x + card_w - aw, ry + 8 * sh, aw, 32 * sh) then
                upgrade_equipped(slot)
                return
            end
        end
    end
end

-- ============================================================================
-- SECTION 20: 离线收益
-- ============================================================================

local function grant_offline(saved)
    if not saved or not saved.time then return end
    local prev = tonumber(saved.time)
    if not prev then return end
    local elapsed = os.time() - prev
    if elapsed < 60 then return end                 -- 不足 1 分钟不结算
    elapsed = math.min(elapsed, 8 * 3600)           -- 封顶 8 小时
    local dps = tonumber(saved.dps) or 0
    -- 用 DPS 折算「期间击杀价值」：金币 + 少量材料
    local gold = math.floor(dps * elapsed * 0.05)
    local mat_amt = math.floor(elapsed / 120)       -- 每 2 分钟 1 材料
    player.gold = player.gold + gold
    player.materials.wood = (player.materials.wood or 0) + mat_amt
    player.materials.stone = (player.materials.stone or 0) + mat_amt
    local mins = math.floor(elapsed / 60)
    offline_report = string.format("Away %dm  ->  +%d gold, +%d wood/stone", mins, gold, mat_amt)
end

-- ============================================================================
-- SECTION 21: love 入口
-- ============================================================================

function love.load()
    font = love.graphics.newFont(15)
    font_sm = love.graphics.newFont(12)
    font_med = love.graphics.newFont(19)
    font_big = love.graphics.newFont(28)
    love.graphics.setFont(font)

    sw = love.graphics.getWidth() / DESIGN_W
    sh = love.graphics.getHeight() / DESIGN_H

    layout_back()
    pcall(build_sfx)   -- 音效合成失败也不影响游戏

    local saved = load_game()
    if saved then
        high_wave = tonumber(saved.high_wave) or 0
        total_kills = tonumber(saved.total_kills) or 0
        -- 预建 player 以便离线收益能写入材料/金币
        init_player(saved)
        grant_offline(saved)
        save_game()
    end
    game_state = "title"
end

function love.update(dt)
    time_accum = time_accum + dt
    if game_state == "combat" then
        update_combat(dt)
    end
end

function love.draw()
    love.graphics.setBackgroundColor(0.05, 0.05, 0.1)

    -- 屏震：随机平移
    local ox, oy = 0, 0
    if shake > 0 then
        ox = (math.random() * 2 - 1) * shake
        oy = (math.random() * 2 - 1) * shake
    end
    love.graphics.push()
    love.graphics.translate(ox, oy)

    if game_state == "title" then
        draw_title()
    elseif game_state == "combat" or game_state == "gear" then
        draw_background()
        for _, a in ipairs(arrows) do draw_arrow_proj(a) end
        for _, e in ipairs(enemies) do draw_enemy(e) end
        draw_archer()
        draw_particles()
        draw_floats()
        draw_low_hp_vignette()
        draw_hud()
        draw_back_btn()
        if game_state == "gear" then draw_gear_panel() end
    elseif game_state == "death" then
        draw_background()
        draw_archer()
        draw_death()
    end

    love.graphics.pop()
end

function love.touchpressed(id, x, y)
    if game_state == "title" then
        offline_report = nil
        local saved = load_game()
        start_game(saved)
        return
    elseif game_state == "death" then
        local saved = load_game()
        start_game(saved)
        return
    elseif game_state == "combat" then
        handle_combat_touch(x, y)
    elseif game_state == "gear" then
        handle_gear_touch(x, y)
    end
end

function love.mousepressed(x, y, button)
    if button == 1 then love.touchpressed("mouse", x, y) end
end

function love.resize()
    sw = love.graphics.getWidth() / DESIGN_W
    sh = love.graphics.getHeight() / DESIGN_H
    layout_back()
    if player then recalc_stats() end
end

function love.quit()
    save_game()
end
