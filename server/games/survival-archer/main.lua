-- ============================================================================
-- Survival Archer — 挂机生存弓箭手
-- 纯 LÖVE2D 实现，无外部依赖，无图片资源
-- ============================================================================

-- ============================================================================
-- SECTION 1: 常量和数据表
-- ============================================================================

local DESIGN_W, DESIGN_H = 480, 800
local MAX_WAVES = 30
local GROUND_FRAC = 0.55       -- 地面线在屏幕高度的比例
local ARCHER_X_FRAC = 0.15    -- 弓箭手 X 位置比例
local MAX_ARROWS = 50
local MAX_ENEMIES = 30

local BOWS = {
    wooden_bow   = { name = "Wooden Bow",      dmg = 0,  spd_m = 1.0,  rng = 0,   color = {0.6, 0.4, 0.2} },
    short_bow    = { name = "Short Bow",      dmg = 2,  spd_m = 0.85, rng = 20,  color = {0.5, 0.35, 0.15} },
    long_bow     = { name = "Long Bow",      dmg = 4,  spd_m = 1.2,  rng = 80,  color = {0.7, 0.5, 0.2} },
    iron_bow     = { name = "Iron Bow",      dmg = 8,  spd_m = 1.0,  rng = 30,  color = {0.5, 0.5, 0.55} },
    steel_bow    = { name = "Steel Bow",      dmg = 14, spd_m = 0.9,  rng = 50,  color = {0.7, 0.7, 0.75} },
    compound_bow = { name = "Compound Bow",    dmg = 22, spd_m = 0.75, rng = 80,  color = {0.3, 0.3, 0.35} },
}

local BOW_RECIPES = {
    wooden_bow   = { cost = {},                                          wave = 1 },
    short_bow    = { cost = { wood = 10, stone = 5 },                   wave = 3 },
    long_bow     = { cost = { wood = 15, stone = 8 },                   wave = 5 },
    iron_bow     = { cost = { wood = 8, iron = 10, stone = 5 },         wave = 8 },
    steel_bow    = { cost = { iron = 15, stone = 10 },                   wave = 12 },
    compound_bow = { cost = { iron = 25, stone = 15, feather = 10 },    wave = 18 },
}

local ARROWS = {
    wooden_arrow = { name = "Wood Arrow",   dmg = 0,  spd = 300, color = {0.6, 0.4, 0.2}, cost = { wood = 2, feather = 1 },       amt = 5 },
    stone_arrow = { name = "Stone Arrow",    dmg = 3,  spd = 280, color = {0.6, 0.6, 0.6}, cost = { wood = 1, stone = 2, feather = 1 }, amt = 5 },
    iron_arrow  = { name = "Iron Arrow",    dmg = 7,  spd = 320, color = {0.7, 0.7, 0.75}, cost = { wood = 1, iron = 2, feather = 1 },  amt = 5 },
    steel_arrow = { name = "Steel Arrow",    dmg = 13, spd = 350, color = {0.85, 0.85, 0.9}, cost = { iron = 3, feather = 2 },        amt = 5 },
    fire_arrow  = { name = "Fire Arrow",    dmg = 18, spd = 300, color = {1.0, 0.4, 0.1}, cost = { iron = 2, feather = 1, stone = 1 }, amt = 3, splash = 30 },
}

local ENEMY_TYPES = {
    zombie      = { name = "Zombie",     hp = 15,  spd = 40,  dmg = 8,  r = 15, color = {0.3, 0.5, 0.2},    loot = { wood = 1, stone = 1 },           gold = {1, 3},  exp = 5 },
    skeleton    = { name = "Skeleton",     hp = 10,  spd = 65,  dmg = 5,  r = 12, color = {0.85, 0.85, 0.75}, loot = { stone = 1 },                     gold = {1, 2},  exp = 4 },
    wolf        = { name = "Wolf",       hp = 20,  spd = 90,  dmg = 12, r = 13, color = {0.4, 0.35, 0.3},  loot = { feather = 2 },                   gold = {2, 4},  exp = 8 },
    orc         = { name = "Orc",     hp = 40,  spd = 35,  dmg = 18, r = 20, color = {0.4, 0.6, 0.2},   loot = { iron = 1 },                      gold = {3, 6},  exp = 12 },
    dark_knight = { name = "Dark Knight",   hp = 60,  spd = 50,  dmg = 25, r = 18, color = {0.25, 0.15, 0.3}, loot = { iron = 2 },                      gold = {5, 10}, exp = 20 },
    dragon      = { name = "Dragon",     hp = 120, spd = 30,  dmg = 40, r = 28, color = {0.8, 0.2, 0.1},   loot = { iron = 3, feather = 3 },         gold = {10, 20}, exp = 50, boss = true },
}

local MAT_COLORS = {
    wood    = {0.6, 0.4, 0.2},
    stone   = {0.6, 0.6, 0.6},
    iron    = {0.7, 0.7, 0.75},
    feather = {0.9, 0.9, 0.85},
}

local UI_COLORS = {
    bg      = {0.08, 0.08, 0.12},
    panel   = {0.12, 0.12, 0.18, 0.9},
    btn     = {0.25, 0.55, 1.0},
    btn_dim = {0.18, 0.30, 0.55},
    text    = {0.92, 0.92, 0.96},
    dim     = {0.55, 0.55, 0.60},
    hp_good = {0.25, 0.75, 0.40},
    hp_bad  = {0.85, 0.25, 0.25},
    gold_c  = {1.0, 0.85, 0.2},
    exp_c   = {0.3, 0.6, 1.0},
}

-- ============================================================================
-- SECTION 2: 游戏状态
-- ============================================================================

local game_state = "title"   -- title | combat | crafting | death | victory
local sw, sh = 1, 1          -- 屏幕缩放
local font, font_sm

-- 玩家
local player
-- 波次
local wave
-- 实体列表
local arrows, enemies, loots, float_texts
-- 自动射击计时
local shoot_timer
-- 制作界面
local craft_tab = "bows"
-- 统计
local total_kills, high_wave
-- 存档
local SAVE_FILE = "survival_save.txt"

-- 缩放辅助
local function sx(v) return v * sw end
local function sy(v) return v * sh end
local function ground_y() return DESIGN_H * GROUND_FRAC * sh end
local function archer_x() return DESIGN_W * ARCHER_X_FRAC * sw end

-- ============================================================================
-- SECTION 3: 存档
-- ============================================================================

local function save_game()
    if not player then return end
    local function ser_tab(t)
        local parts = {}
        for k, v in pairs(t) do
            parts[#parts + 1] = string.format("%s=%d", k, v)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    local data = string.format(
        "%d|%d|%s|%s|%s|%s|%d|%d|%d|%d|%d|%d|%d",
        player.level, player.gold,
        player.bow_id, player.arrow_id,
        ser_tab(player.unlocked_bows),
        ser_tab(player.materials),
        player.stat_vit, player.stat_pow, player.stat_spd,
        player.stat_points, high_wave, total_kills,
        player.arrow_count
    )
    love.filesystem.write(SAVE_FILE, data)
end

local function load_game()
    if not love.filesystem.getInfo(SAVE_FILE) then return nil end
    local raw = love.filesystem.read(SAVE_FILE)
    if not raw then return nil end
    local parts = {}
    for p in raw:gmatch("[^|]+") do parts[#parts + 1] = p end
    if #parts < 13 then return nil end

    local function parse_tab(s)
        local t = {}
        for kv in s:gmatch("[^{},]+") do
            local k, v = kv:match("(%w+)=(%d+)")
            if k and v then t[k] = tonumber(v) end
        end
        return t
    end

    return {
        level = tonumber(parts[1]) or 1,
        gold = tonumber(parts[2]) or 0,
        bow_id = parts[3],
        arrow_id = parts[4],
        unlocked_bows = parse_tab(parts[5]),
        materials = parse_tab(parts[6]),
        stat_vit = tonumber(parts[7]) or 0,
        stat_pow = tonumber(parts[8]) or 0,
        stat_spd = tonumber(parts[9]) or 0,
        stat_points = tonumber(parts[10]) or 0,
        high_wave = tonumber(parts[11]) or 0,
        total_kills = tonumber(parts[12]) or 0,
        arrow_count = tonumber(parts[13]) or 20,
    }
end

-- ============================================================================
-- SECTION 4: 初始化 / 重置
-- ============================================================================

local function recalc_stats()
    local bow = BOWS[player.bow_id]
    local arr = ARROWS[player.arrow_id]
    player.max_hp = 100 + player.stat_vit * 10
    player.hp = math.min(player.hp, player.max_hp)
    player.damage = 3 + player.stat_pow + bow.dmg + arr.dmg
    player.attack_speed = math.max(0.3, 1.5 * bow.spd_m - player.stat_spd * 0.05)
    player.range = (200 + bow.rng) * sw
end

local function init_player(saved)
    player = {
        x = 0, y = 0,
        hp = 100, max_hp = 100,
        level = 1, exp = 0, exp_next = 100,
        gold = 0,
        bow_id = "wooden_bow", arrow_id = "wooden_arrow",
        arrow_count = 20,
        materials = { wood = 10, stone = 5, iron = 0, feather = 3 },
        unlocked_bows = { wooden_bow = 1 },
        stat_vit = 0, stat_pow = 0, stat_spd = 0,
        stat_points = 0,
        damage = 3, attack_speed = 1.5, range = 200,
        shoot_anim = 0,
    }
    if saved then
        for k, v in pairs(saved) do player[k] = v end
    end
    player.hp = player.max_hp
    recalc_stats()
end

local function init_wave(num)
    wave = {
        number = num or 1,
        spawned = 0,
        total = 3 + (num or 1) * 2,
        timer = 0,
        interval = math.max(0.3, 2.0 - (num or 1) * 0.05),
        boss_spawned = false,
    }
end

local function init_game(saved)
    init_player(saved)
    arrows = {}
    enemies = {}
    loots = {}
    float_texts = {}
    shoot_timer = 0
    total_kills = (saved and saved.total_kills) or 0
    high_wave = (saved and saved.high_wave) or 0
    init_wave(1)
    game_state = "combat"
end

-- ============================================================================
-- SECTION 5: 波次管理
-- ============================================================================

local function pick_enemy_type(wn)
    local pool = { "zombie", "skeleton" }
    if wn >= 6 then pool[#pool + 1] = "wolf" end
    if wn >= 11 then pool[#pool + 1] = "orc"; pool[#pool + 1] = "orc" end
    if wn >= 16 then
        pool[#pool + 1] = "dark_knight"
        pool[#pool + 1] = "dark_knight"
    end
    return pool[math.random(#pool)]
end

local function spawn_enemy(type_id, hp_mult)
    local et = ENEMY_TYPES[type_id]
    local w = love.graphics.getWidth()
    local hp = et.hp * hp_mult
    enemies[#enemies + 1] = {
        type_id = type_id,
        x = w + et.r * sw + math.random(0, 60),
        y = ground_y(),
        hp = hp, max_hp = hp,
        spd = et.spd * sw,
        dmg = et.dmg,
        r = et.r,
        color = et.color,
        flash = 0,
        walk_phase = math.random(),
    }
end

local function update_waves(dt)
    -- Boss spawn (every 5 waves, first enemy)
    if wave.number % 5 == 0 and not wave.boss_spawned then
        local mult = 1 + (wave.number - 1) * 0.15
        spawn_enemy("dragon", mult * 3)
        wave.boss_spawned = true
    end

    if wave.spawned < wave.total then
        wave.timer = wave.timer - dt
        if wave.timer <= 0 then
            local mult = 1 + (wave.number - 1) * 0.15
            spawn_enemy(pick_enemy_type(wave.number), mult)
            wave.spawned = wave.spawned + 1
            wave.timer = wave.interval
        end
    end

    -- 波次完成
    if wave.spawned >= wave.total and #enemies == 0 then
        if wave.number >= MAX_WAVES then
            game_state = "victory"
            save_game()
            return
        end
        -- 奖励
        player.gold = player.gold + wave.number * 2
        player.hp = math.min(player.max_hp, player.hp + math.floor(player.max_hp * 0.1))
        float_texts[#float_texts + 1] = {
            x = love.graphics.getWidth() / 2, y = ground_y() - 60,
            text = "Wave " .. wave.number .. " Clear! +" .. (wave.number * 2) .. "g",
            color = UI_COLORS.gold_c, timer = 2.0,
        }
        high_wave = math.max(high_wave, wave.number)
        init_wave(wave.number + 1)
        save_game()
    end
end

-- ============================================================================
-- SECTION 6: 战斗
-- ============================================================================

local function find_target()
    local best, best_x = nil, math.huge
    for _, e in ipairs(enemies) do
        if e.x < best_x then best_x = e.x; best = e end
    end
    if best and (best.x - archer_x()) <= player.range then return best end
    return nil
end

local function fire_arrow()
    if player.arrow_count <= 0 or #arrows >= MAX_ARROWS then return end
    local target = find_target()
    if not target then return end
    player.arrow_count = player.arrow_count - 1
    player.shoot_anim = 1.0
    local ad = ARROWS[player.arrow_id]
    arrows[#arrows + 1] = {
        x = archer_x() + sx(20), y = ground_y() - sy(18),
        vx = ad.spd * sw,
        dmg = player.damage,
        splash = ad.splash,
        color = ad.color,
    }
end

local function spawn_loot(enemy)
    local et = ENEMY_TYPES[enemy.type_id]
    local gold_amt = math.random(et.gold[1], et.gold[2])
    local mats = {}
    for mat, amt in pairs(et.loot) do
        if math.random() < 0.7 then
            mats[mat] = (mats[mat] or 0) + amt
        end
    end
    loots[#loots + 1] = {
        x = enemy.x, y = enemy.y,
        materials = mats, gold = gold_amt,
        timer = 0.8, vy = -40 * sh,
    }
end

local function add_float(x, y, text, color)
    float_texts[#float_texts + 1] = { x = x, y = y, text = text, color = color, timer = 1.0 }
end

local function check_level_up()
    local lvl_table = player.level
    player.exp_next = 50 + lvl_table * 50
    while player.exp >= player.exp_next do
        player.exp = player.exp - player.exp_next
        player.level = player.level + 1
        player.stat_points = player.stat_points + 2
        player.exp_next = 50 + player.level * 50
        player.hp = math.min(player.max_hp, player.hp + math.floor(player.max_hp * 0.2))
        add_float(player.x, player.y - sy(60), "LVL UP! Lv" .. player.level, UI_COLORS.exp_c)
        recalc_stats()
    end
end

local function update_combat(dt)
    -- 自动射击
    shoot_timer = shoot_timer - dt
    if shoot_timer <= 0 then
        fire_arrow()
        shoot_timer = player.attack_speed
    end
    player.shoot_anim = math.max(0, player.shoot_anim - dt * 5)

    -- 移动箭矢
    for i = #arrows, 1, -1 do
        local a = arrows[i]
        a.x = a.x + a.vx * dt
        if a.x > love.graphics.getWidth() + 20 then
            table.remove(arrows, i)
        end
    end

    -- 移动敌人
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        e.x = e.x - e.spd * dt
        e.flash = math.max(0, e.flash - dt)
        e.walk_phase = e.walk_phase + dt * 3

        if e.x - e.r * sw <= archer_x() + sx(10) then
            -- 攻击玩家
            player.hp = player.hp - e.dmg
            add_float(archer_x(), ground_y() - sy(50), "-" .. e.dmg, UI_COLORS.hp_bad)
            spawn_loot(e)
            table.remove(enemies, i)
            if player.hp <= 0 then
                player.hp = 0
                game_state = "death"
                -- 保留一半材料
                for mat, amt in pairs(player.materials) do
                    player.materials[mat] = math.floor(amt * 0.5)
                end
                high_wave = math.max(high_wave, wave.number)
                save_game()
                return
            end
        end
    end

    -- 碰撞：箭矢 vs 敌人
    for i = #arrows, 1, -1 do
        local a = arrows[i]
        local hit = false
        for j = #enemies, 1, -1 do
            local e = enemies[j]
            local dx, dy = a.x - e.x, a.y - e.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < e.r * sw + 4 then
                e.hp = e.hp - a.dmg
                e.flash = 0.1
                add_float(e.x, e.y - e.r * sh - sy(10), tostring(math.floor(a.dmg)), {1, 1, 1})

                -- 溅射
                if a.splash then
                    for k = #enemies, 1, -1 do
                        if k ~= j then
                            local e2 = enemies[k]
                            local d2 = math.sqrt((a.x - e2.x) ^ 2 + (a.y - e2.y) ^ 2)
                            if d2 < a.splash * sw then
                                local sd = math.floor(a.dmg * 0.5)
                                e2.hp = e2.hp - sd
                                e2.flash = 0.1
                            end
                        end
                    end
                end
                hit = true
                break
            end
        end
        if hit then table.remove(arrows, i) end
    end

    -- 移除死亡敌人
    for i = #enemies, 1, -1 do
        if enemies[i].hp <= 0 then
            local e = enemies[i]
            spawn_loot(e)
            local et = ENEMY_TYPES[e.type_id]
            player.exp = player.exp + et.exp
            total_kills = total_kills + 1
            check_level_up()
            table.remove(enemies, i)
        end
    end

    -- 掉落物
    for i = #loots, 1, -1 do
        local l = loots[i]
        l.vy = l.vy + 100 * sh * dt
        l.y = l.y + l.vy * dt
        l.timer = l.timer - dt
        if l.timer <= 0 then
            for mat, amt in pairs(l.materials) do
                player.materials[mat] = (player.materials[mat] or 0) + amt
            end
            player.gold = player.gold + l.gold
            table.remove(loots, i)
        end
    end

    -- 浮动文字
    for i = #float_texts, 1, -1 do
        local ft = float_texts[i]
        ft.y = ft.y - 30 * dt
        ft.timer = ft.timer - dt
        if ft.timer <= 0 then table.remove(float_texts, i) end
    end

    update_waves(dt)
end

-- ============================================================================
-- SECTION 7: 制作逻辑
-- ============================================================================

local function can_craft_bow(id)
    local r = BOW_RECIPES[id]
    if not r then return false end
    if wave.number < r.wave then return false end
    if player.unlocked_bows[id] then return false end
    for mat, amt in pairs(r.cost) do
        if (player.materials[mat] or 0) < amt then return false end
    end
    return true
end

local function craft_bow(id)
    if not can_craft_bow(id) then return false end
    local r = BOW_RECIPES[id]
    for mat, amt in pairs(r.cost) do
        player.materials[mat] = player.materials[mat] - amt
    end
    player.unlocked_bows[id] = 1
    player.bow_id = id
    recalc_stats()
    save_game()
    return true
end

local function can_craft_arrow(id)
    local a = ARROWS[id]
    if not a then return false end
    for mat, amt in pairs(a.cost) do
        if (player.materials[mat] or 0) < amt then return false end
    end
    return true
end

local function craft_arrow(id)
    if not can_craft_arrow(id) then return false end
    local a = ARROWS[id]
    for mat, amt in pairs(a.cost) do
        player.materials[mat] = player.materials[mat] - amt
    end
    player.arrow_count = player.arrow_count + a.amt
    player.arrow_id = id
    recalc_stats()
    save_game()
    return true
end

-- ============================================================================
-- SECTION 8: 绘制函数
-- ============================================================================

local function draw_background()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local gy = ground_y()

    -- 天空渐变
    for i = 0, 10 do
        local t = i / 10
        love.graphics.setColor(0.05 + t * 0.03, 0.05 + t * 0.05, 0.12 + t * 0.02)
        love.graphics.rectangle("fill", 0, t * gy, w, gy / 10 + 1)
    end

    -- 地面
    love.graphics.setColor(0.15, 0.1, 0.06)
    love.graphics.rectangle("fill", 0, gy, w, h - gy)
    love.graphics.setColor(0.2, 0.14, 0.08)
    love.graphics.rectangle("fill", 0, gy, w, 2)

    -- 背景树
    local trees = { 0.3, 0.5, 0.7, 0.85 }
    for _, tx in ipairs(trees) do
        local bx, by = tx * w, gy
        love.graphics.setColor(0.18, 0.12, 0.06)
        love.graphics.rectangle("fill", bx - 3, by - 50 * sh, 6, 50 * sh)
        love.graphics.setColor(0.1, 0.22, 0.08, 0.5)
        love.graphics.circle("fill", bx, by - 55 * sh, 18 * sw)
    end
end

local function draw_archer()
    local x, y = archer_x(), ground_y()
    local s = sw

    -- 腿
    love.graphics.setColor(0.3, 0.3, 0.4)
    love.graphics.line(x, y - 8 * sh, x - 5 * s, y)
    love.graphics.line(x, y - 8 * sh, x + 5 * s, y)

    -- 身体
    love.graphics.setColor(0.4, 0.35, 0.3)
    love.graphics.line(x, y - 24 * sh, x, y - 8 * sh)

    -- 头
    love.graphics.setColor(0.85, 0.7, 0.55)
    love.graphics.circle("fill", x, y - 30 * sh, 6 * s)

    -- 弓臂 (右手方向)
    local bow_x = x + 12 * s
    local bow_y = y - 20 * sh
    local bow_r = 10 * s
    local bow_c = BOWS[player.bow_id].color
    love.graphics.setColor(bow_c)
    love.graphics.arc("line", "open", bow_x, bow_y, bow_r, -1.2, 1.2)

    -- 弦
    local pull = player.shoot_anim * 6 * s
    love.graphics.setColor(0.8, 0.8, 0.7)
    love.graphics.line(bow_x + bow_r * math.cos(-1.2), bow_y + bow_r * math.sin(-1.2),
                       bow_x - pull, bow_y,
                       bow_x + bow_r * math.cos(1.2), bow_y + bow_r * math.sin(1.2))

    -- 手臂
    love.graphics.setColor(0.85, 0.7, 0.55)
    love.graphics.line(x, y - 20 * sh, bow_x - pull, bow_y)
end

local function draw_enemy(e)
    local x, y = e.x, e.y
    local r = e.r * sw
    local bob = math.sin(e.walk_phase) * 2 * sh

    -- 闪白
    if e.flash > 0 then
        love.graphics.setColor(1, 1, 1)
    else
        love.graphics.setColor(e.color)
    end

    local et = ENEMY_TYPES[e.type_id]
    if et.boss then
        -- 龙: 大圆 + 三角翅膀 + 尾巴
        love.graphics.circle("fill", x, y - r + bob, r)
        love.graphics.polygon("fill", x - r * 0.5, y - r * 1.8 + bob, x, y - r + bob, x + r * 0.5, y - r * 1.8 + bob)
        love.graphics.polygon("fill", x + r * 0.8, y - r * 0.5 + bob, x + r * 1.3, y - r + bob, x + r * 0.8, y + r * 0.2 + bob)
        love.graphics.polygon("fill", x - r * 0.8, y - r * 0.5 + bob, x - r * 1.3, y - r * 0.2 + bob, x - r * 0.8, y + r * 0.2 + bob)
        -- 眼睛
        love.graphics.setColor(1, 0.8, 0)
        love.graphics.circle("fill", x - r * 0.25, y - r + bob, r * 0.12)
        love.graphics.circle("fill", x + r * 0.25, y - r + bob, r * 0.12)
    elseif e.type_id == "skeleton" then
        -- 骷髅: 线条
        love.graphics.circle("line", x, y - r + bob, r * 0.7)
        love.graphics.line(x, y - r * 0.3 + bob, x, y + r * 0.4 + bob)
        love.graphics.line(x - r * 0.5, y + bob, x + r * 0.5, y + bob)
        love.graphics.line(x, y - r * 0.1 + bob, x - r * 0.4, y + r * 0.2 + bob)
        love.graphics.line(x, y - r * 0.1 + bob, x + r * 0.4, y + r * 0.2 + bob)
    elseif e.type_id == "wolf" then
        -- 狼: 横向椭圆
        love.graphics.ellipse("fill", x, y - r * 0.5 + bob, r * 1.2, r * 0.7)
        -- 耳朵
        love.graphics.polygon("fill", x - r * 0.5, y - r + bob, x - r * 0.3, y - r * 1.5 + bob, x - r * 0.1, y - r + bob)
        love.graphics.polygon("fill", x + r * 0.1, y - r + bob, x + r * 0.3, y - r * 1.5 + bob, x + r * 0.5, y - r + bob)
    else
        -- 通用: 矩形身体 + 圆头
        love.graphics.rectangle("fill", x - r * 0.5, y - r * 1.5 + bob, r, r * 1.5)
        love.graphics.circle("fill", x, y - r * 1.5 + bob, r * 0.5)
        if e.type_id == "orc" then
            -- 獠牙
            love.graphics.setColor(0.9, 0.9, 0.7)
            love.graphics.polygon("fill", x - r * 0.2, y - r * 1.2 + bob, x - r * 0.1, y - r * 0.9 + bob, x, y - r * 1.2 + bob)
            love.graphics.polygon("fill", x, y - r * 1.2 + bob, x + r * 0.1, y - r * 0.9 + bob, x + r * 0.2, y - r * 1.2 + bob)
        elseif e.type_id == "dark_knight" then
            -- 盾牌
            love.graphics.setColor(0.15, 0.15, 0.2)
            love.graphics.rectangle("fill", x - r * 0.8, y - r * 1.2 + bob, r * 0.3, r)
        end
    end

    -- HP 条
    local bar_w = r * 2
    local bar_h = 3 * sh
    local bar_x = x - bar_w / 2
    local bar_y = y - r * 2 - 4 * sh + bob
    love.graphics.setColor(0.3, 0.1, 0.1)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h)
    local hp_frac = math.max(0, e.hp / e.max_hp)
    love.graphics.setColor(0.2 + 0.6 * (1 - hp_frac), 0.6 * hp_frac, 0.1)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w * hp_frac, bar_h)
end

local function draw_arrow_proj(a)
    love.graphics.setColor(a.color)
    love.graphics.setLineWidth(2)
    love.graphics.line(a.x, a.y, a.x - 10 * sw, a.y)
    if ARROWS[player.arrow_id].splash then
        love.graphics.setColor(1, 0.6, 0.1)
        love.graphics.circle("fill", a.x, a.y, 3 * sw)
    end
    love.graphics.setLineWidth(1)
end

local function draw_loot(l)
    for mat, amt in pairs(l.materials) do
        love.graphics.setColor(MAT_COLORS[mat] or {1, 1, 1})
        love.graphics.rectangle("fill", l.x - 3, l.y - 3, 6, 6)
    end
end

local function draw_ui()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local gy = ground_y()

    -- 顶部栏
    love.graphics.setColor(0.08, 0.08, 0.12, 0.85)
    love.graphics.rectangle("fill", 0, 0, w, 50 * sh)

    love.graphics.setFont(font)
    love.graphics.setColor(UI_COLORS.text)

    -- 波次
    love.graphics.print("Wave " .. wave.number .. "/" .. MAX_WAVES, 8 * sw, 5 * sh)

    -- HP 条
    local hp_w = 120 * sw
    local hp_x = 8 * sw
    local hp_y = 26 * sh
    love.graphics.setColor(0.3, 0.1, 0.1)
    love.graphics.rectangle("fill", hp_x, hp_y, hp_w, 12 * sh)
    local hp_f = math.max(0, player.hp / player.max_hp)
    love.graphics.setColor(UI_COLORS.hp_good[1] * hp_f + UI_COLORS.hp_bad[1] * (1 - hp_f),
                           UI_COLORS.hp_good[2] * hp_f + UI_COLORS.hp_bad[2] * (1 - hp_f),
                           UI_COLORS.hp_good[3] * hp_f + UI_COLORS.hp_bad[3] * (1 - hp_f))
    love.graphics.rectangle("fill", hp_x, hp_y, hp_w * hp_f, 12 * sh)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(font_sm)
    love.graphics.print(math.floor(player.hp) .. "/" .. player.max_hp, hp_x + 4 * sw, hp_y + 1)

    -- 金币 & 等级
    love.graphics.setFont(font)
    love.graphics.setColor(UI_COLORS.gold_c)
    love.graphics.print("Gold:" .. player.gold, 145 * sw, 5 * sh)
    love.graphics.setColor(UI_COLORS.exp_c)
    love.graphics.print("Lv" .. player.level, w - 60 * sw, 5 * sh)

    -- EXP 条
    local exp_w = w - 145 * sw - 55 * sw
    local exp_x = 145 * sw
    local exp_y = 26 * sh
    love.graphics.setColor(0.1, 0.1, 0.2)
    love.graphics.rectangle("fill", exp_x, exp_y, exp_w, 12 * sh)
    love.graphics.setColor(UI_COLORS.exp_c)
    love.graphics.rectangle("fill", exp_x, exp_y, exp_w * (player.exp / player.exp_next), 12 * sh)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(font_sm)
    love.graphics.print(player.exp .. "/" .. player.exp_next, exp_x + 4 * sw, exp_y + 1)

    -- 底部面板
    local panel_y = gy + 10 * sh
    love.graphics.setColor(0.08, 0.08, 0.12, 0.9)
    love.graphics.rectangle("fill", 0, panel_y, w, h - panel_y)

    -- 材料栏
    love.graphics.setFont(font_sm)
    love.graphics.setColor(UI_COLORS.dim)
    local mat_y = panel_y + 8 * sh
    local mat_names = { "wood", "stone", "iron", "feather" }
    local mat_labels = { "Wd", "St", "Ir", "Ft" }
    for i, mat in ipairs(mat_names) do
        local mx = (i - 1) * w / 4 + 8 * sw
        love.graphics.setColor(MAT_COLORS[mat])
        love.graphics.print(mat_labels[i] .. ":" .. (player.materials[mat] or 0), mx, mat_y)
    end

    -- 按钮区
    local btn_y = mat_y + 22 * sh
    local btn_h = 40 * sh
    local btn_w = (w - 30 * sw) / 2

    -- [制作弓]
    love.graphics.setColor(UI_COLORS.btn)
    love.graphics.rectangle("fill", 8 * sw, btn_y, btn_w, btn_h, 4)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(font)
    love.graphics.printf("Craft Bow", 8 * sw, btn_y + 10 * sh, btn_w, "center")

    -- [制作箭]
    love.graphics.setColor(UI_COLORS.btn)
    love.graphics.rectangle("fill", 16 * sw + btn_w, btn_y, btn_w, btn_h, 4)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Craft Arrow", 16 * sw + btn_w, btn_y + 10 * sh, btn_w, "center")

    -- 属性区
    local stat_y = btn_y + btn_h + 10 * sh
    love.graphics.setFont(font_sm)
    love.graphics.setColor(UI_COLORS.dim)
    love.graphics.print("DMG:" .. player.damage .. "  SPD:" .. string.format("%.1f", player.attack_speed) .. "/s  RNG:" .. math.floor(player.range / sw), 8 * sw, stat_y)
    love.graphics.print("Bow:" .. BOWS[player.bow_id].name .. "  Arrow:" .. ARROWS[player.arrow_id].name .. "(" .. player.arrow_count .. ")", 8 * sw, stat_y + 16 * sh)

    -- 属性点
    if player.stat_points > 0 then
        local sp_y = stat_y + 34 * sh
        love.graphics.setColor(UI_COLORS.gold_c)
        love.graphics.print("Stats:" .. player.stat_points, 8 * sw, sp_y)
        local labels = { "VIT+", "POW+", "SPD+" }
        local stat_keys = { "stat_vit", "stat_pow", "stat_spd" }
        for i = 1, 3 do
            local bx = 120 * sw + (i - 1) * 70 * sw
            love.graphics.setColor(UI_COLORS.btn_dim)
            love.graphics.rectangle("fill", bx, sp_y - 2, 60 * sw, 20 * sh, 3)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(labels[i], bx + 5 * sw, sp_y)
        end
    end
end

local function draw_crafting()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    -- 遮罩
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- 面板
    local pw, ph = w - 40 * sw, h - 100 * sh
    local px, py = 20 * sw, 50 * sh
    love.graphics.setColor(0.1, 0.1, 0.16, 0.95)
    love.graphics.rectangle("fill", px, py, pw, ph, 6)
    love.graphics.setColor(0.25, 0.27, 0.35)
    love.graphics.rectangle("line", px, py, pw, ph, 6)

    -- 标题
    love.graphics.setFont(font)
    love.graphics.setColor(UI_COLORS.text)
    love.graphics.printf("Workshop", px, py + 10 * sh, pw, "center")

    -- Tab 按钮
    local tab_y = py + 40 * sh
    local tab_w = pw / 2 - 10 * sw
    love.graphics.setColor(craft_tab == "bows" and UI_COLORS.btn or UI_COLORS.btn_dim)
    love.graphics.rectangle("fill", px + 5 * sw, tab_y, tab_w, 30 * sh, 4)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Bows", px + 5 * sw, tab_y + 6 * sh, tab_w, "center")

    love.graphics.setColor(craft_tab == "arrows" and UI_COLORS.btn or UI_COLORS.btn_dim)
    love.graphics.rectangle("fill", px + tab_w + 15 * sw, tab_y, tab_w, 30 * sh, 4)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Arrows", px + tab_w + 15 * sw, tab_y + 6 * sh, tab_w, "center")

    -- 列表
    love.graphics.setFont(font_sm)
    local list_y = tab_y + 45 * sh
    local row_h = 70 * sh

    if craft_tab == "bows" then
        local bow_order = { "wooden_bow", "short_bow", "long_bow", "iron_bow", "steel_bow", "compound_bow" }
        for idx, id in ipairs(bow_order) do
            local b = BOWS[id]
            local r = BOW_RECIPES[id]
            local ry = list_y + (idx - 1) * row_h
            if ry + row_h > py + ph then break end

            -- 名称 & 属性
            love.graphics.setColor(b.color)
            love.graphics.print(b.name, px + 10 * sw, ry)
            love.graphics.setColor(UI_COLORS.dim)
            love.graphics.print("DMG+" .. b.dmg .. " SPD×" .. b.spd_m, px + 10 * sw, ry + 16 * sh)

            -- 状态按钮
            local btn_x = px + pw - 80 * sw
            local btn_w2 = 70 * sw
            if player.unlocked_bows[id] then
                if player.bow_id == id then
                    love.graphics.setColor(0.2, 0.5, 0.2)
                    love.graphics.rectangle("fill", btn_x, ry, btn_w2, 28 * sh, 4)
                    love.graphics.setColor(1, 1, 1)
                    love.graphics.printf("Equipped", btn_x, ry + 5 * sh, btn_w2, "center")
                else
                    love.graphics.setColor(0.3, 0.3, 0.4)
                    love.graphics.rectangle("fill", btn_x, ry, btn_w2, 28 * sh, 4)
                    love.graphics.setColor(1, 1, 1)
                    love.graphics.printf("Equip", btn_x, ry + 5 * sh, btn_w2, "center")
                end
            elseif wave.number < r.wave then
                love.graphics.setColor(0.2, 0.2, 0.25)
                love.graphics.rectangle("fill", btn_x, ry, btn_w2, 28 * sh, 4)
                love.graphics.setColor(UI_COLORS.dim)
                love.graphics.printf("Wave" .. r.wave, btn_x, ry + 5 * sh, btn_w2, "center")
            elseif can_craft_bow(id) then
                love.graphics.setColor(UI_COLORS.btn)
                love.graphics.rectangle("fill", btn_x, ry, btn_w2, 28 * sh, 4)
                love.graphics.setColor(1, 1, 1)
                love.graphics.printf("Craft", btn_x, ry + 5 * sh, btn_w2, "center")
                -- 显示费用
                local cost_parts = {}
                for mat, amt in pairs(r.cost) do
                    local labels = { wood = "Wd", stone = "St", iron = "Ir", feather = "Ft" }
                    cost_parts[#cost_parts + 1] = (labels[mat] or mat) .. amt
                end
                love.graphics.setColor(UI_COLORS.dim)
                love.graphics.print(table.concat(cost_parts, " "), px + 10 * sw, ry + 34 * sh)
            else
                love.graphics.setColor(0.25, 0.15, 0.15)
                love.graphics.rectangle("fill", btn_x, ry, btn_w2, 28 * sh, 4)
                love.graphics.setColor(UI_COLORS.dim)
                love.graphics.printf("No Mats", btn_x, ry + 5 * sh, btn_w2, "center")
            end
        end
    else
        -- 箭矢列表
        local arr_order = { "wooden_arrow", "stone_arrow", "iron_arrow", "steel_arrow", "fire_arrow" }
        for idx, id in ipairs(arr_order) do
            local a = ARROWS[id]
            local ry = list_y + (idx - 1) * row_h
            if ry + row_h > py + ph then break end

            love.graphics.setColor(a.color)
            love.graphics.print(a.name .. " (DMG+" .. a.dmg .. ")", px + 10 * sw, ry)

            local btn_x = px + pw - 80 * sw
            local btn_w2 = 70 * sw
            if can_craft_arrow(id) then
                love.graphics.setColor(UI_COLORS.btn)
                love.graphics.rectangle("fill", btn_x, ry, btn_w2, 28 * sh, 4)
                love.graphics.setColor(1, 1, 1)
                love.graphics.printf("x" .. a.amt, btn_x, ry + 5 * sh, btn_w2, "center")
            else
                love.graphics.setColor(0.25, 0.15, 0.15)
                love.graphics.rectangle("fill", btn_x, ry, btn_w2, 28 * sh, 4)
                love.graphics.setColor(UI_COLORS.dim)
                love.graphics.printf("No Mats", btn_x, ry + 5 * sh, btn_w2, "center")
            end
            -- 费用
            local cost_parts = {}
            for mat, amt in pairs(a.cost) do
                local labels = { wood = "Wd", stone = "St", iron = "Ir", feather = "Ft" }
                cost_parts[#cost_parts + 1] = (labels[mat] or mat) .. amt
            end
            love.graphics.setColor(UI_COLORS.dim)
            love.graphics.print(table.concat(cost_parts, " "), px + 10 * sw, ry + 16 * sh)
        end
    end

    -- 返回按钮
    local back_y = py + ph - 45 * sh
    love.graphics.setColor(0.4, 0.2, 0.2)
    love.graphics.rectangle("fill", px + pw / 2 - 60 * sw, back_y, 120 * sw, 35 * sh, 4)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(font)
    love.graphics.printf("Back", px + pw / 2 - 60 * sw, back_y + 8 * sh, 120 * sw, "center")
end

local function draw_title()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0.05, 0.05, 0.1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- 装饰弓
    love.graphics.setColor(0.5, 0.35, 0.15)
    love.graphics.arc("line", "open", w / 2, h * 0.35, 60 * sw, -1.2, 1.2)
    love.graphics.setColor(0.8, 0.8, 0.7)
    love.graphics.line(w / 2 + 60 * sw * math.cos(-1.2), h * 0.35 + 60 * sh * math.sin(-1.2),
                       w / 2 - 20 * sw, h * 0.35,
                       w / 2 + 60 * sw * math.cos(1.2), h * 0.35 + 60 * sh * math.sin(1.2))
    -- 箭
    love.graphics.setColor(0.6, 0.4, 0.2)
    love.graphics.line(w / 2 - 20 * sw, h * 0.35, w / 2 - 80 * sw, h * 0.35)

    love.graphics.setFont(font)
    love.graphics.setColor(UI_COLORS.text)
    love.graphics.printf("Survival Archer", 0, h * 0.5, w, "center")
    love.graphics.printf("Survival Archer", 0, h * 0.55, w, "center")

    love.graphics.setFont(font_sm)
    love.graphics.setColor(UI_COLORS.dim)
    love.graphics.printf("Tap to Start", 0, h * 0.68, w, "center")

    if high_wave and high_wave > 0 then
        love.graphics.setColor(UI_COLORS.gold_c)
        love.graphics.printf("Best Wave: " .. high_wave .. "  Kills: " .. (total_kills or 0), 0, h * 0.75, w, "center")
    end
end

local function draw_death()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0.1, 0.02, 0.02, 0.85)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(font)
    love.graphics.setColor(UI_COLORS.hp_bad)
    love.graphics.printf("You Died...", 0, h * 0.3, w, "center")

    love.graphics.setColor(UI_COLORS.text)
    love.graphics.printf("到达 Wave " .. wave.number, 0, h * 0.42, w, "center")
    love.graphics.printf("Kills: " .. total_kills .. "  Gold: " .. player.gold, 0, h * 0.48, w, "center")
    love.graphics.setColor(UI_COLORS.dim)
    love.graphics.printf("Gear kept, 50% materials saved", 0, h * 0.55, w, "center")

    love.graphics.setFont(font_sm)
    love.graphics.setColor(UI_COLORS.text)
    love.graphics.printf("Tap to Retry", 0, h * 0.68, w, "center")
end

local function draw_victory()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0.02, 0.08, 0.02, 0.85)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(font)
    love.graphics.setColor(UI_COLORS.hp_good)
    love.graphics.printf("Victory!", 0, h * 0.3, w, "center")

    love.graphics.setColor(UI_COLORS.text)
    love.graphics.printf("Survived " .. MAX_WAVES .. " Waves!", 0, h * 0.42, w, "center")
    love.graphics.printf("Total Kills: " .. total_kills, 0, h * 0.48, w, "center")

    love.graphics.setFont(font_sm)
    love.graphics.printf("Tap to Restart", 0, h * 0.68, w, "center")
end

-- ============================================================================
-- SECTION 9: 输入处理
-- ============================================================================

local function hit(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function handle_combat_touch(tx, ty)
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local gy = ground_y()
    local panel_y = gy + 10 * sh
    local mat_y = panel_y + 8 * sh
    local btn_y = mat_y + 22 * sh
    local btn_h = 40 * sh
    local btn_w2 = (w - 30 * sw) / 2

    -- [制作弓]
    if hit(tx, ty, 8 * sw, btn_y, btn_w2, btn_h) then
        craft_tab = "bows"
        game_state = "crafting"
        return
    end
    -- [制作箭]
    if hit(tx, ty, 16 * sw + btn_w2, btn_y, btn_w2, btn_h) then
        craft_tab = "arrows"
        game_state = "crafting"
        return
    end

    -- 属性点
    if player.stat_points > 0 then
        local stat_y = btn_y + btn_h + 44 * sh
        local stat_keys = { "stat_vit", "stat_pow", "stat_spd" }
        for i = 1, 3 do
            local bx = 120 * sw + (i - 1) * 70 * sw
            if hit(tx, ty, bx, stat_y - 2, 60 * sw, 20 * sh) then
                if player.stat_points > 0 then
                    player[stat_keys[i]] = player[stat_keys[i]] + 1
                    player.stat_points = player.stat_points - 1
                    recalc_stats()
                    save_game()
                end
                return
            end
        end
    end
end

local function handle_crafting_touch(tx, ty)
    local w = love.graphics.getWidth()
    local pw = w - 40 * sw
    local ph = love.graphics.getHeight() - 100 * sh
    local px, py = 20 * sw, 50 * sh
    local tab_y = py + 40 * sh
    local tab_w = pw / 2 - 10 * sw
    local list_y = tab_y + 45 * sh
    local row_h = 70 * sh

    -- Tab 切换
    if hit(tx, ty, px + 5 * sw, tab_y, tab_w, 30 * sh) then craft_tab = "bows"; return end
    if hit(tx, ty, px + tab_w + 15 * sw, tab_y, tab_w, 30 * sh) then craft_tab = "arrows"; return end

    -- 返回
    local back_y = py + ph - 45 * sh
    if hit(tx, ty, px + pw / 2 - 60 * sw, back_y, 120 * sw, 35 * sh) then
        game_state = "combat"
        return
    end

    -- 列表点击
    local btn_x = px + pw - 80 * sw
    local btn_w2 = 70 * sw

    if craft_tab == "bows" then
        local bow_order = { "wooden_bow", "short_bow", "long_bow", "iron_bow", "steel_bow", "compound_bow" }
        for idx, id in ipairs(bow_order) do
            local ry = list_y + (idx - 1) * row_h
            if ry + row_h > py + ph then break end
            if hit(tx, ty, btn_x, ry, btn_w2, 28 * sh) then
                if player.unlocked_bows[id] then
                    player.bow_id = id
                    recalc_stats()
                    save_game()
                elseif can_craft_bow(id) then
                    craft_bow(id)
                end
                return
            end
        end
    else
        local arr_order = { "wooden_arrow", "stone_arrow", "iron_arrow", "steel_arrow", "fire_arrow" }
        for idx, id in ipairs(arr_order) do
            local ry = list_y + (idx - 1) * row_h
            if ry + row_h > py + ph then break end
            if hit(tx, ty, btn_x, ry, btn_w2, 28 * sh) then
                if can_craft_arrow(id) then
                    craft_arrow(id)
                end
                return
            end
        end
    end
end

-- ============================================================================
-- SECTION 10: love 入口
-- ============================================================================

function love.load()
    font = love.graphics.newFont(16)
    font_sm = love.graphics.newFont(13)
    love.graphics.setFont(font)

    sw = love.graphics.getWidth() / DESIGN_W
    sh = love.graphics.getHeight() / DESIGN_H

    local saved = load_game()
    if saved then
        high_wave = saved.high_wave or 0
        total_kills = saved.total_kills or 0
    end

    game_state = "title"
end

function love.update(dt)
    if game_state == "combat" then
        -- 更新缩放（处理旋转/缩放）
        sw = love.graphics.getWidth() / DESIGN_W
        sh = love.graphics.getHeight() / DESIGN_H
        player.x = archer_x()
        player.y = ground_y()
        update_combat(dt)
    end
end

function love.draw()
    love.graphics.setBackgroundColor(0.05, 0.05, 0.1)

    if game_state == "title" then
        draw_title()
    elseif game_state == "combat" then
        draw_background()
        for _, l in ipairs(loots) do draw_loot(l) end
        for _, a in ipairs(arrows) do draw_arrow_proj(a) end
        for _, e in ipairs(enemies) do draw_enemy(e) end
        draw_archer()
        -- 浮动文字
        love.graphics.setFont(font_sm)
        for _, ft in ipairs(float_texts) do
            love.graphics.setColor(ft.color[1], ft.color[2], ft.color[3], math.min(1, ft.timer * 2))
            love.graphics.printf(ft.text, ft.x - 40 * sw, ft.y, 80 * sw, "center")
        end
        draw_ui()
    elseif game_state == "crafting" then
        draw_background()
        for _, e in ipairs(enemies) do draw_enemy(e) end
        draw_archer()
        draw_ui()
        draw_crafting()
    elseif game_state == "death" then
        draw_death()
    elseif game_state == "victory" then
        draw_victory()
    end
end

function love.touchpressed(id, x, y)
    if game_state == "title" then
        local saved = load_game()
        init_game(saved)
        return
    end
    if game_state == "death" or game_state == "victory" then
        local saved = load_game()
        init_game(saved)
        return
    end
    if game_state == "combat" then
        handle_combat_touch(x, y)
    elseif game_state == "crafting" then
        handle_crafting_touch(x, y)
    end
end

function love.mousepressed(x, y, button)
    if button == 1 then love.touchpressed("mouse", x, y) end
end

function love.quit()
    save_game()
end
