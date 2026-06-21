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
--   武器两条基础属性：攻击力区间 wmin~wmax + 攻速 wspeed(次/秒)。慢弓伤害高/快弓伤害低，武器 DPS 守恒。
--   1 STR=+1攻击(加到攻击区间) ; 1 AGI=+0.6%攻速(乘在武器攻速上)+0.04%暴击 ; 1 STA=+6生命
--   装备预算 budget = GEAR_BUDGET * ilvl * rarity.mult * slot.weight
--   武器 DPS 贡献 = budget * WEAPON_DPS_K（与速度无关）；单发伤害 = 攻击区间随机 × 箭档倍率 × 暴击 × (1-减伤)
--   角色每级 +2力 +2敏 +3耐（慢），经验需求 80*L^1.6
-- ============================================================================
--
-- 本文件已收薄成入口：装配各层(base/fx/state/sys/view/input) + love 回调转调。
-- 静态数据在 data.lua；底层绘制/缩放/字体在 base/；运行态在 core/state；规则在 sys/；
-- immediate-mode 视图在 view/（每屏 draw()+hit()）；指针分发在 core/input。
-- 仍留在主文件：存档(save 表，待后续阶段移 base/save) + init() + love 回调 + QUIVER_TEST 钩子。
-- ============================================================================
-- helium 在 require 期 monkeypatch love.handlers（mousepressed/moved/released/key*/textinput），
-- 包成"命中 HUD 元素则吞掉、否则下发原 handler"。StoneGate 退出会清 package.loaded，二次启动
-- 会再包一层 → 跨会话 handler 污染。缓解：require 前快照这 6 个原始 handler，love.quit 里先还原。
local _orig_handlers = {}
for _,n in ipairs({"mousepressed","mousemoved","mousereleased","keypressed","keyreleased","textinput"}) do
    _orig_handlers[n] = love.handlers and love.handlers[n]
end
local helium = require("helium")

local D = require("data")
local fx = require("fx")
local state = require("core.state")
local inv = require("sys.inventory")
local prog = require("sys.progression")
local combat = require("sys.combat")
local gather = require("sys.gather")
local craft = require("sys.craft")
local dungeon = require("sys.dungeon")
local input = require("core.input")
-- view 层：HUD + 各活动场景 + 各面板（draw/hit）
local hud_helium = require("view.hud_helium")  -- 新主 HUD（helium 元素，替代旧 view/hud 的顶/底栏）
local combat_view = require("view.combat_view")
local gather_view = require("view.gather_view")
local craft_view = require("view.craft_view")
local rest_view = require("view.rest_view")
local bag_view = require("view.bag_view")
local equip_view = require("view.equip_view")
local mastery_view = require("view.mastery_view")
local system_view = require("view.system_view")
local region_view = require("view.region_view")
local dungeon_view = require("view.dungeon_view")
local activity_view = require("view.activity_view")
local skills_view = require("view.skills_view")
local tooltip = require("view.tooltip")

-- 常用数据/规则别名（save/init 与主循环用到）
local BLUEPRINTS = D.BLUEPRINTS
local BP = D.BP
local SKILLS = D.SKILLS
local ACTIVITIES = D.ACTIVITIES
local REGIONS = D.REGIONS
local BAG_SLOTS = D.BAG_SLOTS
local MP_REGEN = D.MP_REGEN
local roll_gear = inv.roll_gear
local inv_add, ammo_add = inv.inv_add, inv.ammo_add
local recalc, xp_need = prog.recalc, prog.xp_need

-- 前向声明：update() 里(重置/退出)要用 save 与 init，但它们定义在下方 → 先声明 local，
-- 后面用 `function init()` / `save = {}`（不带 local）填充同一个 upvalue。
local init
local save

-- ============================================================================
-- 主循环：通用推进（特效/冷却/mp/活动 tick）串起战斗 tick。规则逻辑全在 sys/。
-- ============================================================================
-- 挂机活动 tick：一次只挂一种。gather→采集状态机；craft→图谱持续制造（都在 sys/）。
local function activity_tick(dt)
    local a = ACTIVITIES[state.activity]
    if a.kind == "gather" then gather.node_machine(dt)
    elseif a.kind == "craft" then craft.tick(dt) end
end

local function update(dt)
    -- 系统菜单请求(由 view/system 设标志，在此主文件执行，避免循环 require)
    if state.req_reset then
        state.req_reset=nil; pcall(love.filesystem.remove, save.FILE); init(); fx.set_toast("存档已重置", D.UI.good)
    end
    if state.req_exit then
        state.req_exit=nil; pcall(save.write)
        if type(_G.stonegate_exit)=="function" then _G.stonegate_exit()    -- StoneGate 大厅
        elseif love.event then love.event.quit() end                       -- standalone 退出
        return
    end
    fx.update_fx(dt)   -- 特效推进：粒子物理 / 跳字漂移 / toast 计时 / 震屏衰减 / 动画时钟（喂回 draw.t）
    -- 活动抽屉滑入/滑出动画（左侧 drawer）：开则 t→1，关则 t→0
    do
        local target = (state.panel_open=="activity") and 1 or 0
        local d = state.drawer_t or 0; local step = dt/0.18
        if d < target then d = math.min(target, d+step) elseif d > target then d = math.max(target, d-step) end
        state.drawer_t = d
    end
    -- 技能冷却 / 限时增益 / 释放闪光（全局回充，切回战斗即就绪）
    for id,v in pairs(state.player.cd) do local nv=v-dt; state.player.cd[id]=(nv>0) and nv or nil end
    for id,v in pairs(state.player.cast_flash) do local nv=v-dt; state.player.cast_flash[id]=(nv>0) and nv or nil end
    for i=#state.player.buffs,1,-1 do state.player.buffs[i].t=state.player.buffs[i].t-dt; if state.player.buffs[i].t<=0 then table.remove(state.player.buffs,i) end end
    -- 法力回复（战斗内外都回，封顶 max_mp）
    if state.player.mp and state.player.max_mp then state.player.mp=math.min(state.player.max_mp, state.player.mp + MP_REGEN*dt) end
    -- 探险许可恢复（随时间涨，离线也算；last_time 跟随）
    dungeon.update(dt)

    -- 副本进行中：独立推进(波次/boss/结算)，盖过普通挂机活动
    if state.dungeon_run then dungeon.tick(dt); return end
    -- 结算弹窗弹出时暂停推进(等玩家确认)
    if state.dungeon_result then return end

    -- 当前挂机活动（一次只挂一种）
    activity_tick(dt)
    recalc()  -- 箭档/增益显示随库存刷新

    if state.result_banner then return end
    -- 战斗只在「战斗挂机」时推进（ATB 对决 + 抛射物 + DOT + 自动药剂，全在 sys/combat）
    if state.activity ~= "combat" then return end
    combat.tick(dt)
end

-- ============================================================================
-- 初始化
-- ============================================================================
function init()
    state.player = { level=1, xp=0, xp_next=xp_need(1), base_str=5, base_agi=5, base_sta=5,
        gold=0, hp=nil, mp=nil, equip={}, inv={}, ammo={}, ammo_cap=0, atb=0,
        -- 探险许可(副本进入成本，随时间恢复；离线靠 last_time 折算)
        energy=D.ENERGY_MAX, energy_max=D.ENERGY_MAX, last_time=(love.timer and love.timer.getTime and love.timer.getTime()) or os.time(),
        -- 采集职业：独立等级 + 经验（靠采集攒经验升级，与角色等级分离）
        skill={ woodcut={lvl=1,xp=0}, mining={lvl=1,xp=0}, herb={lvl=1,xp=0} },
        -- 制造职业：独立，做工攒经验升级（不进 skill 表）
        craft={ lvl=1, xp=0 }, craft_bp="ar_flint", craft_prog=0, craft_target=nil, bp_known={},
        -- 锻造职业：独立子职业（炼锭/造装），做工攒经验解锁更高配方
        forge={ lvl=1, xp=0 }, forge_bp="fg_copper",
        gather_node=nil,             -- 遭遇式采集当前节点（含 phase）
        -- 战斗精通(满级软成长)：points=可分配点，<id>=各精通已投级数
        mastery={ points=0 },
        -- 系统设置（音量等；音频以后接上，先存好）
        settings={ music=0.7, sfx=0.8 },
        -- 角色技能态：已学技能 / 冷却 / 限时增益 / 释放闪光
        skills={ "shoot" }, cd={}, buffs={}, cast_flash={} }
    for _,b in ipairs(BLUEPRINTS) do if b.learn=="start" then state.player.bp_known[b.id]=true end end
    -- 初始装备：灰色弓 + 普通(白)箭袋（先装好箭袋，弹药槽才存在）
    state.player.equip.bow = roll_gear("bow", 1, "poor")
    state.player.equip.quiver = roll_gear("quiver", 1, "common")
    recalc()
    -- 初始物品：T1 系材料入背包(够接通制箭/造锭/药剂) + 羽毛，箭矢入箭袋
    inv_add("mat","w_shaft1",8); inv_add("mat","o_head1",4); inv_add("mat","h_heal1",2)
    inv_add("mat","feather",6); inv_add("mat","o_blade2",2)
    ammo_add("flint",30)   -- 燧石箭(纯物理)开局弹药
    state.player.hp=state.player.max_hp
    state.region=REGIONS[1]; state.stage=0; fx.floats={}; fx.particles={}; state.projectiles={}; state.result_banner=nil; fx.toast=nil
    state.activity="rest"; state.panel_open=nil; state.enemy=nil
    state.dungeon_run=nil; state.dungeon_result=nil
end

-- ============================================================================
-- 存档（零依赖：手写 table→Lua 源码 序列化；love.filesystem 读写；版本迁移）
-- 只存 base_* 与"账本"，衍生态交给 recalc()，瞬时态交给 init/状态机重建；引用只存 id。
-- ============================================================================
-- 收进单个 save 表（避免主 chunk 触及 Lua 200 局部变量上限；文件拆分后会移到 base/save.lua）
save = {}
save.FILE = "quiver/save.lua"
save.VERSION = 9
local save_timer = 0

-- 序列化一个纯数据值（数字/字符串/布尔/表）到 out 数组
function save.ser(v, out)
    local t = type(v)
    if t=="number" then
        if v==math.floor(v) and v~=math.huge and v~=-math.huge then out[#out+1]=string.format("%d", v)
        else out[#out+1]=string.format("%.6g", v) end
    elseif t=="string" then out[#out+1]=string.format("%q", v)
    elseif t=="boolean" then out[#out+1]= v and "true" or "false"
    elseif t=="table" then
        out[#out+1]="{"
        local n=#v; local contiguous=true; local cnt=0
        for k in pairs(v) do cnt=cnt+1; if type(k)~="number" then contiguous=false end end
        if contiguous and cnt==n then           -- 纯连续数组
            for i=1,n do save.ser(v[i],out); out[#out+1]="," end
        else                                     -- 含字符串/稀疏键
            for k,val in pairs(v) do
                if type(k)=="string" then out[#out+1]="["..string.format("%q",k).."]="
                else out[#out+1]="["..tostring(k).."]=" end
                save.ser(val,out); out[#out+1]=","
            end
        end
        out[#out+1]="}"
    else out[#out+1]="nil" end
end
function save.serialize(tbl) local out={"return "}; save.ser(tbl,out); return table.concat(out) end

-- 快照：稀疏存 inv/ammo（定长数组中间有 nil，连续序列化会截断）
function save.snapshot()
    local inv={}; for i=1,BAG_SLOTS do if state.player.inv[i] then inv[i]=state.player.inv[i] end end
    local ammo={}; for i=1,(state.player.ammo_cap or 0) do if state.player.ammo[i] then ammo[i]=state.player.ammo[i] end end
    return {
        version=save.VERSION,
        level=state.player.level, xp=state.player.xp,
        base_str=state.player.base_str, base_agi=state.player.base_agi, base_sta=state.player.base_sta,
        gold=state.player.gold, hp=state.player.hp, mp=state.player.mp,
        equip=state.player.equip, inv=inv, ammo=ammo,
        skill=state.player.skill, craft=state.player.craft, craft_bp=state.player.craft_bp,
        forge=state.player.forge, forge_bp=state.player.forge_bp,
        energy=state.player.energy, energy_max=state.player.energy_max, last_time=state.player.last_time,
        mastery=state.player.mastery,
        settings=state.player.settings,
        bag_slots=state.player.bag_slots,
        bp_known=state.player.bp_known, skills=state.player.skills,
        activity=state.activity, region_id=state.region.id, stage=state.stage,
    }
end

function save.write()
    local ok, s = pcall(save.serialize, save.snapshot())
    if not ok then return false end
    pcall(love.filesystem.createDirectory, "quiver")
    return (pcall(love.filesystem.write, save.FILE, s))
end

function save.migrate(data)
    if type(data)~="table" then return nil end
    local v = data.version or 1
    if v > save.VERSION then return nil end     -- 来自更新版本：不兼容，回退新开局
    -- v1→v2：材料细化(C1)。旧通用材料 wood/ore/herb 迁移为对应 T1 系主材；
    --   inv 里的 mat 物品改 id；技能/图谱配方的 cost 走当前 data 表(不存档)，无需迁移。
    --   未知/已删除材料 id 在 load 期由 D.MAT/SECONDARY/旧中间材料过滤(见下)，安全丢弃不崩。
    if v < 2 then
        local map = { wood="w_shaft1", ore="o_head1", herb="h_heal1" }
        if type(data.inv)=="table" then
            for _,it in pairs(data.inv) do
                if type(it)=="table" and it.kind=="mat" and map[it.id] then it.id = map[it.id] end
            end
        end
        data.version = 2
    end
    -- v2→v3：武器类型(C2)。旧武器 gear 无 wtype/crit_innate → 补 longbow/0(均衡型，不破坏数值)。
    --   遍历 equip(取 weapon 类槽) 与 inv(kind=="gear")，给缺字段的武器补默认；命名/签名旧档没有，留空即可。
    if v < 3 then
        local function backfill_weapon(g)
            if type(g)~="table" or not g.stats then return end
            if g.stats.wmin then   -- 有攻击区间 = 武器
                if not g.wtype then g.wtype = "longbow" end
                if g.stats.crit_innate==nil then g.stats.crit_innate = 0 end
            end
        end
        if type(data.equip)=="table" then for _,g in pairs(data.equip) do backfill_weapon(g) end end
        if type(data.inv)=="table" then for _,it in pairs(data.inv) do
            if type(it)=="table" and it.kind=="gear" then backfill_weapon(it.gear) end
        end end
        data.version = 3
    end
    -- v3→v4：箭矢三轴(C3)。旧弹药是单档箭 {id="wood"/"iron"/"hunter"/"rune", qty}，
    --   迁移为成品箭三轴 {head,element,feather=phys/plain}；未知箭 id 丢弃(留空格)不崩。
    --   旧 craft_bp(wood/iron/hunter/rune) / bp_known 旧箭图谱 id 在 load 期由 BP 过滤掉，安全。
    if v < 4 then
        local headmap = { wood="flint", iron="bronze", hunter="steel", rune="mithril" }
        if type(data.ammo)=="table" then
            for i,it in pairs(data.ammo) do
                if type(it)=="table" then
                    if it.head==nil then
                        local h = headmap[it.id]
                        if h then data.ammo[i] = { kind="arrow", head=h, element="phys", feather="plain", qty=it.qty or 0 }
                        else data.ammo[i] = nil end   -- 未知旧箭：丢弃
                    elseif it.kind==nil then it.kind="arrow" end
                end
            end
        end
        data.version = 4
    end
    -- v4→v5：锻造(C4)。旧档无 forge 子职业/forge_bp/锭材料 → load 期由 init() 默认补全
    --   (forge={lvl=1,xp=0}/forge_bp="fg_copper")，无需改 data；锻造图谱按 bp_known 过滤旧 id 安全。
    if v < 5 then
        data.version = 5
    end
    -- v5→v6：副本(C5)。旧档无 energy/last_time/钥匙 → load 期由 init() 默认补全
    --   (energy 满许可 / last_time=当前)，钥匙是普通背包材料按 D.MAT_NAME 校验保留。无需改 data。
    if v < 6 then
        data.version = 6
    end
    -- v6→v7：经验曲线收口 + 满级精通(C6)。旧档无 mastery → load 期由 init() 默认补全
    --   ({points=0})；xp 曲线变陡(xp_need)，xp_next 在 load 期按新公式重算，旧 xp 值原样保留(只是更慢)。
    if v < 7 then
        data.version = 7
    end
    return data
end

-- 读档：全程 pcall，任何失败 return false → 调用方 init() 全新开局，绝不让坏档崩启动
function save.load()
    local ok = pcall(function()
        if not love.filesystem.getInfo(save.FILE) then error("nofile") end
        local chunk = assert(love.filesystem.load(save.FILE))
        local data = save.migrate(chunk())
        assert(type(data)=="table", "baddata")
        init()                                   -- 先铺完整默认结构（新增字段兜底）
        state.player.level = data.level or 1
        state.player.xp = data.xp or 0
        state.player.xp_next = xp_need(state.player.level)
        state.player.base_str = data.base_str or state.player.base_str
        state.player.base_agi = data.base_agi or state.player.base_agi
        state.player.base_sta = data.base_sta or state.player.base_sta
        state.player.gold = data.gold or 0
        state.player.bag_slots = (type(data.bag_slots)=="number" and data.bag_slots>=24) and math.floor(data.bag_slots) or nil  -- 旧档无→nil→默认24
        if type(data.settings)=="table" then
            state.player.settings.music = tonumber(data.settings.music) or state.player.settings.music
            state.player.settings.sfx   = tonumber(data.settings.sfx)   or state.player.settings.sfx
        end
        state.player.equip = data.equip or {}
        state.player.skill = data.skill or state.player.skill
        state.player.craft = data.craft or state.player.craft
        state.player.craft_bp = (data.craft_bp and BP[data.craft_bp]) and data.craft_bp or "ar_flint"
        -- 锻造职业：旧档无 forge → 用 init() 默认；forge_bp 校验存在性
        state.player.forge = data.forge or state.player.forge
        state.player.forge_bp = (data.forge_bp and BP[data.forge_bp]) and data.forge_bp or "fg_copper"
        -- 探险许可：复原账本，再按 last_time 折算离线恢复(catch_up 在 recalc 后调)
        state.player.energy_max = data.energy_max or D.ENERGY_MAX
        state.player.energy = data.energy or state.player.energy_max
        state.player.last_time = data.last_time or ((love.timer and love.timer.getTime and love.timer.getTime()) or os.time())
        -- 战斗精通：复原 points + 各精通级数(按 D.MASTERY 校验 id，未知键丢弃；非数值兜底 0)
        state.player.mastery = { points=0 }
        if type(data.mastery)=="table" then
            local pts = tonumber(data.mastery.points) or 0
            state.player.mastery.points = math.max(0, math.floor(pts))
            for id in pairs(D.MASTERY) do
                local lv = tonumber(data.mastery[id])
                if lv and lv>0 then state.player.mastery[id] = math.floor(lv) end
            end
        end
        -- 已知图谱/已学技能：按当前表过滤掉已删除的 id（防改表后崩）
        state.player.bp_known = {}; for id in pairs(data.bp_known or {}) do if BP[id] then state.player.bp_known[id]=true end end
        -- start 类图谱(燧石箭/铜锭/铜甲/铜短弓...)始终保底已知(旧档无锻造起始配方也补上)
        for _,b in ipairs(BLUEPRINTS) do if b.learn=="start" then state.player.bp_known[b.id]=true end end
        state.player.skills = {}; for _,id in ipairs(data.skills or {}) do if SKILLS[id] then state.player.skills[#state.player.skills+1]=id end end
        if #state.player.skills==0 then state.player.skills={"shoot"} end
        -- inv/ammo：定长补 nil（稀疏表回填，绝不丢洞后物品）。
        -- 材料物品按当前 data 表校验 id：未知/已删除材料安全丢弃(留空格)，防 tooltip/图标查 nil 崩。
        state.player.inv = {}
        if data.inv then for i=1,BAG_SLOTS do
            local it = data.inv[i]
            if it and it.kind=="mat" and not (D.MAT_NAME[it.id]) then it=nil end
            state.player.inv[i]=it
        end end
        state.player.ammo = {}; if data.ammo then for i,it in pairs(data.ammo) do state.player.ammo[i]=it end end
        -- 引用按 id 查回
        local rg; for _,r in ipairs(REGIONS) do if r.id==data.region_id then rg=r end end
        state.region = rg or REGIONS[1]
        state.activity = (ACTIVITIES[data.activity] and data.activity) or "rest"
        state.stage = data.stage or 0
        -- 瞬时态清空
        state.player.gather_node=nil; state.player.cd={}; state.player.buffs={}; state.player.cast_flash={}; state.player.atb=0; state.enemy=nil
        state.dungeon_run=nil; state.dungeon_result=nil
        -- hp/mp 必须在 recalc 之前赋（recalc 有 nil/超上限钳制）
        state.player.hp = data.hp; state.player.mp = data.mp
        recalc()
        dungeon.catch_up()   -- 折算离线时间恢复探险许可
    end)
    return ok
end

-- ============================================================================
-- 绘制：按当前活动 kind 画场景 + HUD，再按 panel_open 叠面板/tooltip/拖拽/死亡幕。
-- ============================================================================
local function draw_main()
    -- 副本进行中：复用战斗场景画弓手/敌/boss/抛射物(波次进度由 dungeon_view 叠在上层)
    if state.dungeon_run then combat_view.draw(); fx.draw_particles(); return end
    local a = ACTIVITIES[state.activity]
    if a.kind=="combat" then combat_view.draw()
    elseif a.kind=="gather" then gather_view.draw()
    elseif a.kind=="craft" then craft_view.draw()
    else rest_view.draw() end
    fx.draw_particles()   -- 共享粒子（活动场景之上）
end

-- ============================================================================
-- love 回调（薄入口：装配 + 转调）
-- ============================================================================
-- ============================================================================
-- helium HUD：非缓存 scene（cached=false → 元素每帧重画、不进 canvas 缓存，自然读最新
-- HP/MP/经验/金币，避免缓存停旧值）。HUD 元素由 view/hud_helium 搭，每次 set_scale 后重建
-- (元素的输入订阅矩形在 setup 期按屏幕尺寸固化，resize 后须重建才对得上)。
-- ============================================================================
local hud_scene
local hud_el         -- {top=, bottom=}
local function build_hud()
    hud_scene = helium.scene.new(false)
    hud_el = hud_helium.build(helium)
end

function love.load()
    -- 中文字体（思源黑体）；缺失则退回默认字体（中文会显示为方块）。base/assets 负责加载并写回 base/draw。
    require("base.assets").load_fonts()
    local screen = require("base.screen")
    screen.set_scale()
    if not save.load() then init() end   -- 有档则读，无档/坏档全新开局
    build_hud()
end
function love.update(dt)
    if dt>0.05 then dt=0.05 end
    update(dt)
    if hud_scene then hud_scene:update() end   -- helium HUD 元素推进（非缓存：每帧重画）
    -- 自动存档：节流写盘（小表，开销可忽略）
    save_timer = save_timer + dt
    if save_timer >= 12 then save_timer = 0; pcall(save.write) end
end
function love.draw()
    love.graphics.setBackgroundColor(D.UI.bg)
    local ox,oy=0,0; if fx.shake>0 then ox=(math.random()*2-1)*fx.shake; oy=(math.random()*2-1)*fx.shake end
    love.graphics.push(); love.graphics.translate(ox,oy)
    draw_main()
    fx.draw_floats()   -- 跳字（在 HUD/面板覆盖之下，与旧行为同序）
    -- helium HUD：顶部角色卡始终画；底部入口栏仅无面板且无副本流程时激活
    hud_el.top:draw(0,0)
    local in_dungeon = state.dungeon_run or state.dungeon_result
    if state.panel_open or in_dungeon then hud_el.bottom:undraw() else hud_el.bottom:draw(0,0) end
    if hud_scene then hud_scene:draw() end
    if state.panel_open=="region" then region_view.draw()
    elseif state.panel_open=="dungeon" or in_dungeon then dungeon_view.draw()
    elseif state.panel_open=="activity" then activity_view.draw()
    elseif state.panel_open=="skills" then skills_view.draw()
    elseif state.panel_open=="bag" then bag_view.draw(); tooltip.draw_tooltip()
    elseif state.panel_open=="equip" then equip_view.draw(); tooltip.draw_tooltip()
    elseif state.panel_open=="mastery" then mastery_view.draw() end
    -- 齿轮按钮(顶栏右上角，常驻可点) + 系统菜单
    do
        local screen_ = require("base.screen"); local dr = require("base.draw"); local sw = screen_.sw
        local gx = love.graphics.getWidth()-34*sw; local gy=8*sw
        love.graphics.setColor(0.10,0.11,0.16,0.85); love.graphics.rectangle("fill",gx,gy,22*sw,22*sw)
        dr.pixel_icon("gear", gx+11*sw, gy+11*sw, 9*sw, {0.8,0.82,0.88})
    end
    if state.panel_open=="system" then system_view.draw() end
    -- 拖拽中的物品跟随指针（超过阈值才显示）
    bag_view.draw_drag()
    if state.result_banner=="defeat" then
        local dr = require("base.draw")
        love.graphics.setColor(0,0,0,0.7); love.graphics.rectangle("fill",0,0,love.graphics.getWidth(),love.graphics.getHeight())
        love.graphics.setFont(dr.font_big); dr.setc(D.UI.bad); love.graphics.printf("已阵亡",0,love.graphics.getHeight()*0.4,love.graphics.getWidth(),"center")
        love.graphics.setFont(dr.font_sm); dr.setc(D.UI.dim); love.graphics.printf("Lv "..state.player.level.." · 点击复活",0,love.graphics.getHeight()*0.5,love.graphics.getWidth(),"center")
    end
    love.graphics.pop()
end

function love.touchpressed(id,x,y) input.press(x,y) end
function love.touchmoved(id,x,y) input.drag_move(x,y) end
function love.touchreleased(id,x,y) input.release(x,y) end
function love.mousepressed(x,y,b) if b==1 then input.press(x,y) end end
function love.mousemoved(x,y) input.drag_move(x,y) end
function love.mousereleased(x,y,b) if b==1 then input.release(x,y) end end
function love.wheelmoved(dx,dy) input.wheel(dx,dy) end
function love.resize() local screen=require("base.screen"); screen.set_scale(); build_hud() end
-- 退出强存：必须在 chunk 顶层定义，loader 才能在回调快照里捕获到（否则退出存档静默丢失）。
-- 先还原 require helium 前快照的原始 handler，再写盘：缓解 StoneGate 清 package.loaded 后
-- 二次启动 helium 重新包裹 love.handlers 造成的跨会话链污染。
function love.quit()
    if love.handlers then
        for n,fn in pairs(_orig_handlers) do if fn then love.handlers[n]=fn end end
    end
    pcall(save.write)
end


-- [TEST] 仅当全局 QUIVER_TEST 被设置时暴露存档/状态供白盒回归测试；正常游戏 rawget 为 nil，零开销。
if rawget(_G,"QUIVER_TEST") then
    QUIVER_TEST.save  = save
    QUIVER_TEST.init  = init
    QUIVER_TEST.state = function() return { player=state.player, activity=state.activity, region=state.region, stage=state.stage } end
end
