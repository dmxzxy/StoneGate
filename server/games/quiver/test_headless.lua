-- Headless smoke test: mock the LÖVE API enough to load main.lua and run
-- init() + many update/draw frames across all activities. Catches nil-derefs
-- and logic errors that luac -p can't. Run: lua test_headless.lua
--
-- 运行约定：cd 到 quiver 目录后 `lua test_headless.lua`（cwd=quiver），故把
-- 设计空间子模块路径前置进 package.path，让重构后的 require("data") /
-- require("base.draw") / require("sys.combat") / require("helium") 等能解析。
package.path = "./?.lua;./?/init.lua;" .. package.path

local W,H = 480, 800
local function noop() end
-- 通用安全假对象：任何方法调用返回它自己 + 一对维度数字，足以让 helium 的
-- canvas/quad/image 链式调用与 :getDimensions() 不崩。
local fakeobj
fakeobj = setmetatable({}, { __index = function() return function() return fakeobj, W, H end end })
local fontobj = setmetatable({}, { __index=function() return function() return 12 end end })
local g = {}
local gfuncs = { "setColor","rectangle","circle","polygon","line","arc","print","printf",
  "push","pop","translate","setLineWidth","setLineStyle","setLineJoin","setFont",
  "setBackgroundColor","setScissor","ellipse","scale","origin","clear","present","points",
  -- helium require/draw 期会捕获/调用这些：保持 noop 或返回假对象
  "setCanvas","draw","setBlendMode","applyTransform","replaceTransform","intersectScissor",
  "rotate","shear","reset","setShader","stencil","setStencilTest","setColorMask" }
for _,n in ipairs(gfuncs) do g[n]=noop end
g.getWidth=function() return W end
g.getHeight=function() return H end
g.getDimensions=function() return W,H end
-- helium 非缓存元素渲染路径会调用 transformPoint 求屏幕坐标做 scissor（element.lua）
g.transformPoint=function(x,y) return x or 0, y or 0 end
g.inverseTransformPoint=function(x,y) return x or 0, y or 0 end
g.newFont=function() return fontobj end
g.getFont=function() return fontobj end
-- helium element.lua / atlas.lua 在 require 期把这些捕获进 local，必须是函数：
g.newCanvas=function() return fakeobj end
g.newImage=function() return fakeobj end
g.newQuad=function() return fakeobj end
g.getCanvas=function() return nil end
love = { graphics=g, timer={ getTime=function() return 0 end }, window={}, mouse={}, system={},
  -- helium core/input.lua 在 require 期读 love.handlers['mousepressed'] 等做 orig 快照，
  -- 然后写回包裹函数。给个空表即可让它塞；种入 noop 防被包裹函数调用 orig.X 时 nil 调用。
  handlers = setmetatable({}, { __index = function() return noop end }),
  -- helium 不用 math.newTransform，但 base/draw 等将来可能用；给最小桩。
  math = { newTransform = function() return fakeobj end, random = math.random,
           noise = function() return 0 end, colorFromBytes = function(...) return ... end },
  graphics_ok=true }

-- in-memory mock filesystem (for save/load round-trip tests)
local FS = {}
love.filesystem = {
  write = function(path,data) FS[path]=data; return true end,
  read = function(path) if FS[path] then return FS[path], #FS[path] end; return nil,"nf" end,
  getInfo = function(path) if FS[path]~=nil then return {type="file", size=#FS[path]} end; return nil end,
  load = function(path) if not FS[path] then return nil,"nf" end; return load(FS[path]) end,
  append = function(path,data) FS[path]=(FS[path] or "")..data; return true end,
  createDirectory = function() return true end,
  getSaveDirectory = function() return "/mock/save" end,
}

-- enable the guarded test hook in main.lua
QUIVER_TEST = {}

-- deterministic-ish RNG seeded fixed
math.randomseed(12345)

-- load the game file
local chunk, err = loadfile("main.lua")
if not chunk then print("LOAD FAIL: "..tostring(err)); os.exit(1) end
local ok, e = pcall(chunk)
if not ok then print("CHUNK RUN FAIL: "..tostring(e)); os.exit(1) end

-- run callbacks
local function try(label, fn)
  local ok,e = pcall(fn)
  if not ok then print("FAIL ["..label.."]: "..tostring(e)); os.exit(1) end
end

try("love.load", function() love.load() end)

-- exercise every activity + panels by driving press() via love handlers,
-- and run many update/draw frames so all branches tick.
local function frames(n) for _=1,n do try("update", function() love.update(0.05) end); try("draw", function() love.draw() end) end end
local function tap(x,y) try("press@"..x..","..y, function() if love.mousepressed then love.mousepressed(x,y,1) end; if love.mousereleased then love.mousereleased(x,y,1) end end) end
-- activity is now a LEFT drawer (slides in from left); rows start at y=base(sy48)+layout.
-- centers under grouped layout (480x800): idle/combat/sub headers + rows. x=120 is inside drawer.
local ACT_OPEN = {55, 772}
local SKILLS_OPEN = {147, 772}
local ROW = { rest=98, combat=184, woodcut=270, mining=334, herb=398, fletch=462, forge=526 }
-- open the drawer, wait for slide-in (~0.18s), then tap a row, then let it settle
local function pick(act) tap(ACT_OPEN[1],ACT_OPEN[2]); frames(6); tap(120, ROW[act]); frames(4) end

frames(10)
-- accumulate materials via each gather, then craft (exercises do_craft / add_craft_xp / unlock_blueprints),
-- then fight (exercises make_enemy ranks / drop_loot / projectile).
pick("woodcut"); frames(800)
pick("mining");  frames(800)
pick("herb");    frames(800)
pick("fletch");  frames(2000)         -- craft until materials drain, then auto-stop
-- tap a blueprint card in the craft view (lower half) to switch blueprint
tap(W/2, 460); frames(200)
-- 锻造活动：开炼锭(挂机做工)，再切到造甲 tab(点 craft 页 tab 行)持续做装
pick("forge");   frames(1500)
-- 点制造页分类 tab 行(炼锭/造甲/造弓在下半屏标题之上一排)：x 约第3/4个 tab
tap(W*0.5, 380); frames(20); tap(W*0.7, 380); frames(20)
tap(W/2, 460);   frames(1200)         -- 切某图谱卡持续锻造
pick("combat");  frames(2500)
-- 技能面板：打开、点各行学习按钮(可能金/料不足)、关闭
tap(SKILLS_OPEN[1],SKILLS_OPEN[2]); frames(20)
for r=0,7 do tap(W-50, 130+r*60); frames(4) end
tap(W/2, H-70); frames(4)
-- open every panel + region scroll/select
for i=0,3 do tap(40+i*100, H-30); frames(40); tap(W/2, H-70); frames(4) end
tap(W-40, H-30); frames(4)
if love.wheelmoved then for _=1,40 do pcall(love.wheelmoved,0,-3) end end
frames(4); tap(W/2, 300); frames(20)          -- 选一个(可能更高级的)地区
pick("woodcut"); frames(600)                   -- 在高区采集：可能反复"等级不足"，验证跳过路径
pick("mining");  frames(400)
pick("rest"); frames(60)

-- ===== 存档系统 round-trip（含稀疏 inv 空洞）=====
local fails = 0
local function check(name, cond) if cond then print("PASS "..name) else print("FAIL "..name); fails=fails+1 end end
local S = QUIVER_TEST
check("love.quit 是函数(顶层定义)", type(love.quit)=="function")
check("test hook 暴露 save", type(S.save)=="table" and type(S.save.write)=="function")

local p = S.state().player
p.gold = 1234; p.level = 5; p.xp = 42
-- 造一个 inv 空洞：1/3 格有物、第2格空 —— 验证稀疏存不丢洞后物品
p.inv = {}; p.inv[1]={kind="mat",id="wood",qty=7}; p.inv[3]={kind="mat",id="ore",qty=3}
check("save.write 成功", S.save.write()==true)
local raw = FS["quiver/save.lua"]
check("存档文件已写入", type(raw)=="string" and #raw>0)
local data = assert(load(raw))()
check("序列化含 gold=1234", data.gold==1234)
check("inv 稀疏：洞(第2格)保留为空", data.inv[1]~=nil and data.inv[2]==nil and data.inv[3]~=nil)

-- 篡改内存后读档，应从磁盘完整复原
p.gold=0; p.level=1; p.inv={}
check("save.load 成功", S.save.load()==true)
local q = S.state().player
check("读档 gold 复原", q.gold==1234)
check("读档 level 复原", q.level==5)
check("读档 inv 洞后物品不丢", q.inv[1] and q.inv[1].qty==7 and q.inv[3] and q.inv[3].id=="ore" and q.inv[2]==nil)
check("读档后 max_mp 由 recalc 重算", q.max_mp==30+q.level*5 and q.mp~=nil)

-- 坏档不崩：写入垃圾，load 应 return false（调用方会 init 回退）
FS["quiver/save.lua"] = "this is not lua {{{"
check("坏档 save.load 返回 false 不崩", S.save.load()==false)

-- ===== C3 箭矢三轴 + 怪物家族抗性 白盒 =====
do
  local D = require("data")
  local inv = require("sys.inventory")
  local combat = require("sys.combat")
  local st = require("core.state")
  S.init()  -- 干净开局
  -- 派生：三轴成品箭 key/name/color/mult 不崩且自洽
  local a = { head="steel", element="bleed", feather="wind" }
  check("arrow_key 三轴拼接", D.arrow_key(a)=="steel|bleed|wind")
  check("arrow_mult 取箭头档", D.arrow_mult(a)==D.AHEAD.steel.phys_mult)
  check("arrow_name 含元素+箭头", type(D.arrow_name(a))=="string" and #D.arrow_name(a)>0)
  -- 缺轴/坏数据兜底(旧档安全)
  check("缺轴箭兜底不崩", D.arrow_mult({})==D.ARROW_HEADS[1].phys_mult)
  -- 弹药三轴存取：加两种不同元素箭，best 取最高物理档
  st.player.ammo_cap = 4; st.player.ammo = {}
  inv.ammo_add_arrow("flint","phys","plain",10)
  inv.ammo_add_arrow("steel","fire","wind",10)
  check("ammo_best 取最高物理档(steel)", inv.ammo_best() and inv.ammo_best().head=="steel")
  check("ammo_count 按箭头汇总", inv.ammo_count("flint")==10 and inv.ammo_count("steel")==10)
  check("ammo_key_count 按确切组合", inv.ammo_key_count({head="steel",element="fire",feather="wind"})==10)
  -- 家族抗性：不死怕火(系数>1)、构造抵毒(系数<1)
  check("undead 火抗>1(弱点)", D.ENEMY_FAMILY.undead.resist.fire>1)
  check("construct 高甲 armor_mul=1.3", D.ENEMY_FAMILY.construct.armor_mul==1.3)
  -- 各敌型都有 family，且 family 在 ENEMY_FAMILY 表里
  for id,arch in pairs(D.ENEMY_ARCH) do
    check("敌型 "..id.." 有合法 family", arch.family~=nil and D.ENEMY_FAMILY[arch.family]~=nil)
  end
  -- 命中元素：造一个不死敌人，火箭命中后挂 dot；构造敌护甲含 armor_mul
  st.region = D.REGIONS[1]; st.stage=0
  local en = combat.make_enemy("wraith","normal")  -- undead
  check("make_enemy 带 family/base_armor/debuffs", en.family=="undead" and en.base_armor~=nil and type(en.debuffs)=="table")
  st.enemy = en; en.phase="fight"
  st.projectiles = {}
  -- 装满火箭并发射，命中应挂火 dot
  st.player.ammo = {}; inv.ammo_add_arrow("steel","fire","wind",10); require("sys.progression").recalc()
  combat.do_shot(1.0, {})
  local p = st.projectiles[#st.projectiles]
  check("火箭抛射物带 dot(火元素)", p and p.dot~=nil and p.dot.eid=="fire")
  combat.resolve_hit(p)
  check("命中后敌身上有火 dot", #en.dots>0)
  -- 冰箭命中挂减速 debuff，敌 spd 降低
  local en2 = combat.make_enemy("boar","normal"); st.enemy=en2; en2.phase="fight"; st.projectiles={}
  local spd0 = en2.spd
  st.player.ammo={}; inv.ammo_add_arrow("iron","frost","plain",5); require("sys.progression").recalc()
  combat.do_shot(1.0,{})
  combat.resolve_hit(st.projectiles[#st.projectiles])
  check("冰箭命中后敌减速(spd 下降)", en2.spd < spd0)
end

-- ===== C4 锻造（炼锭 + 造甲造弓 + forge 子职业 + 存档）白盒 =====
do
  local D = require("data")
  local inv = require("sys.inventory")
  local craft = require("sys.craft")
  local prog = require("sys.progression")
  local st = require("core.state")
  S.init()
  -- 起始 forge 子职业存在、起始锻造图谱已学
  check("forge 子职业默认 lvl1", st.player.forge and st.player.forge.lvl==1 and st.player.forge.xp==0)
  check("forge 活动登记(kind=craft,job=forge)", D.ACTIVITIES.forge and D.ACTIVITIES.forge.kind=="craft" and D.ACTIVITIES.forge.job=="forge")
  check("起始锻造图谱 fg_copper 已学", st.player.bp_known.fg_copper==true)
  -- 锭材料登记
  check("锭材料 copper_ingot 有名/色", D.MAT_NAME.copper_ingot and D.MAT_COLOR.copper_ingot)
  check("锭材料 voidiron_ingot 登记", D.MAT_NAME.voidiron_ingot~=nil)
  -- 炼锭：备料后 do_craft 产出锭进背包 + 喂 forge 经验
  st.player.inv={}; inv.inv_add("mat","o_blade2",6); inv.inv_add("mat","w_char1",2)
  local fx0 = st.player.forge.xp
  craft.do_craft(D.BP.fg_copper)
  check("炼锭后背包有 copper_ingot", inv.inv_count("mat","copper_ingot")>=1)
  check("炼锭喂 forge 经验(forge.xp 增长，不喂 craft)", st.player.forge.xp>fx0)
  -- 造装：out.kind=gear → roll_gear 产出装备进背包(定向槽)
  st.player.inv={}; inv.inv_add("mat","copper_ingot",4); inv.inv_add("mat","leather",2)
  craft.do_craft(D.BP.fg_copper_chest)
  local got_gear=nil
  for i=1,D.BAG_SLOTS do local it=st.player.inv[i]; if it and it.kind=="gear" then got_gear=it.gear end end
  check("造甲产出 gear 进背包", got_gear~=nil)
  check("造甲定向到目标槽(chest)", got_gear and got_gear.slot=="chest")
  -- 造弓：out 带 wtype，产出武器 gear 含该 wtype + 守恒攻速
  st.player.inv={}; inv.inv_add("mat","copper_ingot",4); inv.inv_add("mat","w_bowarm1",3)
  craft.do_craft(D.BP.fg_copper_short)
  local got_bow=nil
  for i=1,D.BAG_SLOTS do local it=st.player.inv[i]; if it and it.kind=="gear" and it.gear.slot=="bow" then got_bow=it.gear end end
  check("造弓产出 weapon gear", got_bow~=nil and got_bow.stats.wmin~=nil)
  check("造弓含指定 wtype(shortbow)", got_bow and got_bow.wtype=="shortbow")
  -- forge 升级解锁更高配方：拉满 forge 等级后高档锭图谱解锁
  st.player.forge.lvl=20; prog.unlock_blueprints()
  check("forge 升级解锁高档锭图谱(fg_voidiron)", st.player.bp_known.fg_voidiron==true)
  -- forge 经验路由：add_craft_xp(n,"forge") 只动 forge，不动 craft
  local cx0, fx1 = st.player.craft.xp, st.player.forge.xp
  prog.add_craft_xp(5, "forge")
  check("add_craft_xp(_,forge) 只喂 forge", st.player.craft.xp==cx0 and st.player.forge.xp~=fx1 or st.player.forge.lvl>20)
  -- 存档持久化 forge 职业等级/经验 + forge_bp
  st.player.forge.lvl=7; st.player.forge.xp=33; st.player.forge_bp="fg_iron_chest"
  check("save.write(含 forge) 成功", S.save.write()==true)
  st.player.forge={lvl=1,xp=0}; st.player.forge_bp="fg_copper"
  check("save.load(含 forge) 成功", S.save.load()==true)
  local fp = S.state().player
  check("读档 forge.lvl 复原", fp.forge.lvl==7)
  check("读档 forge.xp 复原", fp.forge.xp==33)
  check("读档 forge_bp 复原", fp.forge_bp=="fg_iron_chest")
end

-- ===== C5 副本（许可恢复 + 进入/波次/boss/结算 + 存档）白盒 =====
do
  local D = require("data")
  local inv = require("sys.inventory")
  local prog = require("sys.progression")
  local combat = require("sys.combat")
  local dungeon = require("sys.dungeon")
  local st = require("core.state")
  S.init()
  -- 数据登记
  check("DUNGEONS 表非空", type(D.DUNGEONS)=="table" and #D.DUNGEONS>0)
  check("DUNGEON 索引可查", D.DUNGEON.darkwood_warren~=nil)
  check("BOSSES 登记(alpha_wolf)", D.BOSSES.alpha_wolf~=nil and D.BOSSES.alpha_wolf.family~=nil)
  check("钥匙材料 iron_key 有名/色", D.MAT_NAME.iron_key~=nil and D.MAT_COLOR.iron_key~=nil)
  -- 许可默认满 + 字段就位
  check("energy 默认满", st.player.energy==st.player.energy_max and st.player.energy_max==D.ENERGY_MAX)
  check("last_time 已铺", st.player.last_time~=nil)
  -- 许可时间恢复(在线 update)：先扣再 update 一段时间应回涨
  st.player.energy = 10
  dungeon.update(3600)  -- 模拟一小时(满恢复)
  check("许可随时间恢复(封顶)", st.player.energy>10 and st.player.energy<=st.player.energy_max)
  -- 离线折算：把 last_time 拨回过去 + 拉低许可，catch_up 应补足
  st.player.energy = 0
  local saved_getTime = love.timer.getTime
  local NOW = 100000
  love.timer.getTime = function() return NOW end
  st.player.last_time = NOW - 3600   -- 1 小时前
  dungeon.catch_up()
  check("离线时间折算恢复许可", st.player.energy>0)
  love.timer.getTime = saved_getTime
  -- make_boss：固定等级大倍率 + family/机制
  local boss = combat.make_boss("stone_lord", 20)
  check("make_boss 带 is_boss/family/big hp", boss.is_boss==true and boss.family=="construct" and boss.hp>200)
  -- make_enemy 接受 lvl_override(副本波次小怪)
  st.region = D.REGIONS[1]; st.stage=0
  local mob = combat.make_enemy("wolf","normal", 20)
  check("make_enemy lvl_override 生效", mob.level==20)
  -- 进入门槛：许可不足/缺钥匙拒绝
  local dg = D.DUNGEON.quarry_depths   -- 中级，需 iron_key
  st.player.level = 60                  -- 等级够(解锁)
  st.player.energy = 0
  st.player.inv = {}
  local can1 = dungeon.can_enter(dg)
  check("许可不足不可进入", can1==false)
  st.player.energy = st.player.energy_max
  local can2 = dungeon.can_enter(dg)
  check("缺钥匙不可进入(需 iron_key)", can2==false)
  inv.inv_add("mat","iron_key",1)
  local can3 = dungeon.can_enter(dg)
  check("许可+钥匙齐备可进入", can3==true)
  -- 进入：扣许可+钥匙、建运行态、切到波次1
  local e0 = st.player.energy
  check("dungeon.enter 成功", dungeon.enter(dg)==true)
  check("进入扣许可", st.player.energy == e0 - dg.cost_energy)
  check("进入扣钥匙", inv.inv_count("mat","iron_key")==0)
  check("运行态建立(波次1/有敌)", st.dungeon_run~=nil and st.dungeon_run.phase=="wave" and st.dungeon_run.wave==1 and st.enemy~=nil)
  -- 推进副本到通关：给玩家超强属性，跑足够帧逐波清完+boss
  st.player.base_str=99999; st.player.base_sta=99999; prog.recalc(); st.player.hp=st.player.max_hp
  st.player.ammo_cap=4; st.player.ammo={}; inv.ammo_add_arrow("void","pierce","eagle",9999); prog.recalc()
  local guard=0
  while st.dungeon_run and guard<4000 do dungeon.tick(0.05); guard=guard+1 end
  check("副本推进到结算(run 清空)", st.dungeon_run==nil)
  check("结算弹窗存在", st.dungeon_result~=nil)
  check("通关(win=true)", st.dungeon_result and st.dungeon_result.win==true)
  check("结算给经验大包", st.dungeon_result and st.dungeon_result.xp == dg.min_lvl*60)
  -- 失败安慰：阵亡走 consolation
  S.init(); st.player.level=60; st.player.energy=st.player.energy_max
  inv.inv_add("mat","iron_key",1)
  dungeon.enter(dg)
  st.player.base_str=1; st.player.base_sta=1; prog.recalc(); st.player.hp=1
  -- 玩家极弱：第一波就会被打死(标 failed)；多 tick 推进直到结算
  local g2=0
  while st.dungeon_run and g2<4000 do
    st.player.hp = math.min(st.player.hp, 1)   -- 持续压血，确保挨打即死
    dungeon.tick(0.05); g2=g2+1
  end
  check("阵亡后副本失败结算", st.dungeon_result~=nil and st.dungeon_result.win==false)
  -- 存档持久化 energy/last_time
  S.init()
  st.player.energy = 42; st.player.last_time = 555
  check("save.write(含 energy) 成功", S.save.write()==true)
  st.player.energy = 0; st.player.last_time = 0
  check("save.load(含 energy) 成功", S.save.load()==true)
  local ep = S.state().player
  check("读档 energy 复原(允许时间恢复后>=42)", ep.energy>=42)
  check("读档 last_time 刷新到当前", ep.last_time~=nil)
end

-- ===== helium require 烟测（验证 mock love 桩对未来 UI 阶段够用）=====
-- 后续阶段 main.lua 将 require("helium")。helium core/input.lua 在 require 期会
-- 读 love.handlers 做 orig 快照并写回包裹函数；atlas/element 捕获 love.graphics.*。
-- 这里在 harness 里先单独 require 一次，确保桩齐全、不崩。若 helium 目录尚不存在
-- 则跳过（标 PASS），不阻塞 harness。
if love.filesystem.getInfo and io.open then
  local f = io.open("helium/init.lua","r")
  if f then
    f:close()
    local hok, helium = pcall(require, "helium")
    check("require('helium') 在 mock love 下不崩", hok)
    if hok then
      check("helium 返回模块表(可调用)", type(helium)=="table" or type(helium)=="function")
      check("require helium 后 love.handlers.mousepressed 可调用",
            type(love.handlers.mousepressed)=="function")
    else
      print("  helium require 失败: "..tostring(helium))
    end
  else
    print("PASS helium 目录暂缺，跳过 require 烟测")
  end
end

if fails>0 then print("SAVE FAILURES: "..fails); os.exit(1) end
print("SMOKE OK")
