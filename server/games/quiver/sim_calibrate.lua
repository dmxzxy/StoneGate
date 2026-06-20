-- ============================================================================
-- sim_calibrate.lua —— C6 校准工具(临时)：无头估算 1→60 大致时长 + 三套范例 build 有效 DPS 差异。
-- 用 data.lua 的公式直接算(不跑战斗 tick，省时)，给出量级判断供调系数。
-- 运行：cd quiver 后 lua sim_calibrate.lua
-- ============================================================================
package.path = "./?.lua;./?/init.lua;" .. package.path
-- 复用 test_headless 的 mock love：直接 require 各 sys 跑真实战斗 tick 估 kill_t。
local W,H=480,800
local function noop() end
local fakeobj; fakeobj=setmetatable({},{__index=function() return function() return fakeobj,W,H end end})
local fontobj=setmetatable({},{__index=function() return function() return 12 end end})
local g={}; for _,n in ipairs({"setColor","rectangle","circle","polygon","line","arc","print","printf","push","pop","translate","setLineWidth","setLineStyle","setLineJoin","setFont","setBackgroundColor","setScissor","ellipse","scale","origin","clear","present","points","setCanvas","draw","setBlendMode","applyTransform","replaceTransform","intersectScissor","rotate","shear","reset","setShader","stencil","setStencilTest","setColorMask"}) do g[n]=noop end
g.getWidth=function() return W end; g.getHeight=function() return H end; g.getDimensions=function() return W,H end
g.transformPoint=function(x,y) return x or 0,y or 0 end; g.inverseTransformPoint=function(x,y) return x or 0,y or 0 end
g.newFont=function() return fontobj end; g.getFont=function() return fontobj end
g.newCanvas=function() return fakeobj end; g.newImage=function() return fakeobj end; g.newQuad=function() return fakeobj end; g.getCanvas=function() return nil end
love={ graphics=g, timer={getTime=function() return 0 end}, window={}, mouse={}, system={}, handlers=setmetatable({},{__index=function() return noop end}),
  math={ newTransform=function() return fakeobj end, random=math.random, noise=function() return 0 end, colorFromBytes=function(...) return ... end }, graphics_ok=true }
local FS={}; love.filesystem={ write=function(p,d) FS[p]=d; return true end, read=function(p) return FS[p],FS[p] and #FS[p] end, getInfo=function(p) return FS[p]~=nil and {type="file",size=#FS[p]} or nil end, load=function(p) return FS[p] and load(FS[p]) end, append=noop, createDirectory=function() return true end, getSaveDirectory=function() return "/m" end }
math.randomseed(777)

local D = require("data")
local state = require("core.state")
local inv = require("sys.inventory")
local prog = require("sys.progression")
local combat = require("sys.combat")

local CRIT_MULT = D.CRIT_MULT
local ARMOR_K = D.ARMOR_K
local GEAR_BUDGET = D.GEAR_BUDGET
local WEAPON_DPS_K = D.WEAPON_DPS_K

local function xp_need(L) return math.floor(55*(L^2.15)) end
local function mitigation(armor) return armor/(armor+ARMOR_K) end

-- 校准旋钮(可调):
local GEAR_LAG = 10         -- 装备/箭档普遍滞后当前等级约 10 ilvl(8 个箭手相关槽难同时补齐)
local COMBAT_XP_K = 4       -- 战斗 xp = floor(level*COMBAT_XP_K)(§0 设计值,精英×2/稀有×4)
-- "活跃战斗时间占比":挂机弓箭手把大量时间花在采集/制造/锻造(三态互喂,造箭尤其吃料)与离线,
-- 真实"练级墙钟时间"≈ 纯战斗时间 / COMBAT_TIME_SHARE。取 0.38(约 1/3 时间在战斗)。
local COMBAT_TIME_SHARE = 0.38

-- ----------------------------------------------------------------------------
-- 1) 实测 kill_t：真正跑 combat.tick 直到敌死，得到含 ATB/抛射/过场的真实击杀时间。
--    玩家按等级 L 装一套 ilvl≈L 的 uncommon 装(普攻流,无技能加速),箭档随等级。
-- ----------------------------------------------------------------------------
local function setup_player(L)
  -- 装备滞后:实战玩家装备 ilvl 普遍落后当前等级若干档(掉落随机、补不齐),按 L-GEAR_LAG 估。
  local gilvl = math.max(2, L-GEAR_LAG)
  state.player = { level=L, xp=0, xp_next=xp_need(L), base_str=5+(L-1)*2, base_agi=5+(L-1)*2, base_sta=5+(L-1)*3,
    gold=0, hp=nil, mp=nil, equip={}, inv={}, ammo={}, ammo_cap=6, atb=0,
    skill={}, craft={lvl=1,xp=0}, forge={lvl=1,xp=0}, bp_known={}, mastery={points=0},
    skills={"shoot"}, cd={}, buffs={}, cast_flash={} }
  -- 武器/箭袋:uncommon, ilvl 滞后
  state.player.equip.bow = inv.roll_gear("bow", gilvl, "uncommon")
  state.player.equip.quiver = inv.roll_gear("quiver", gilvl, "uncommon")
  for _,slot in ipairs({"head","chest","legs","hands","feet","shoulder","neck","ring","trinket"}) do
    state.player.equip[slot] = inv.roll_gear(slot, gilvl, "uncommon")
  end
  -- 箭档也滞后:用 (L-GEAR_LAG)/6 档(玩家常用比当前略低的箭)
  local htier = math.max(1, math.min(10, math.ceil(gilvl/6)))
  local head = D.ARROW_HEADS[htier].id
  inv.ammo_add_arrow(head, "phys", "plain", 9999)
  prog.recalc(); state.player.hp=state.player.max_hp; state.player.mp=state.player.max_mp
end

-- 实测某等级"该区敌人混合"的平均 kill_t(含 ogre/golem 等肉怪 + 精英概率)。
local SIM_ROSTER = {"wolf","bandit","ogre","golem","wraith"}   -- 混合:含高 hp 肉/构造
local function measure_kill_t(L, samples)
  setup_player(L)
  state.region = { id="sim", tier="mid", lo=L, hi=L, ilo=L, ihi=L, rar={"common"}, rar_elite={"rare"}, enemies=SIM_ROSTER }
  state.stage = 0
  local total_t, total_kills = 0, 0
  for s=1,samples do
    -- 轮换敌型 + 偶发精英(8%)/稀有(2%),贴近真实混合
    local arch = SIM_ROSTER[((s-1)%#SIM_ROSTER)+1]
    local rr=math.random(); local rank = (rr<0.02 and "rare") or (rr<0.10 and "elite") or "normal"
    state.enemy = combat.make_enemy(arch, rank, L)
    state.projectiles = {}
    local t=0
    while state.enemy and state.enemy.hp>0 and t<120 do
      combat.tick(0.05); t=t+0.05
      if state.enemy and state.enemy.phase=="dying" then break end
    end
    total_t = total_t + t + 0.6
    total_kills = total_kills + 1
    state.player.hp = state.player.max_hp
  end
  return total_t/total_kills
end

print("=== 1) 1→60 时长估算(真实 combat.tick 测 kill_t) ===")
-- 在采样等级测 kill_t,其余线性插值(逐级跑太慢)
local sample_L = {1,5,10,15,20,25,30,35,40,45,50,55,59}
local kt = {}
for _,L in ipairs(sample_L) do kt[L] = measure_kill_t(L, 6) end
local function kill_t_at(L)
  -- 最近邻插值
  local lo,hi=1,59
  for i=1,#sample_L-1 do if L>=sample_L[i] and L<=sample_L[i+1] then lo=sample_L[i]; hi=sample_L[i+1]; break end end
  if L<=sample_L[1] then return kt[sample_L[1]] end
  if L>=sample_L[#sample_L] then return kt[sample_L[#sample_L]] end
  local f=(L-lo)/math.max(1,hi-lo); return kt[lo]+(kt[hi]-kt[lo])*f
end

local total_h, seg = 0, {}
for L=1,59 do
  local need = xp_need(L)
  local kill_t = kill_t_at(L)
  local avg_mul = 0.9*1 + 0.08*2 + 0.02*4    -- 精英/稀有混合
  local xp_per = L*COMBAT_XP_K*avg_mul
  local dungeon_share = (L>=36) and 0.30 or 0.0
  local kills_c = need*(1-dungeon_share)/xp_per
  local t_combat = kills_c*kill_t
  local t_dungeon = (need*dungeon_share/xp_per)*kill_t*0.5
  local pure_combat_s = t_combat+t_dungeon
  -- 真实墙钟 = 纯战斗时间 / 战斗时间占比(其余在采集/制造/锻造/离线)
  total_h = total_h + (pure_combat_s/COMBAT_TIME_SHARE)/3600
  if L%10==0 or L==59 then seg[#seg+1]=string.format("到 Lv%d 累计 ≈ %.1f h (kill_t≈%.1fs)", L+1, total_h, kill_t) end
end
for _,s in ipairs(seg) do print("  "..s) end
print(string.format("  *** 总计 1→60 ≈ %.0f h (纯战斗墙钟,含采集/制造时间折算 share=%.2f) ***", total_h, COMBAT_TIME_SHARE))

-- ----------------------------------------------------------------------------
-- 2) 三套范例 build(§7) 有效 DPS 差异，目标 ±20~30%、无唯一最优。
--   场景差异：对"肉怪/boss"(高 hp)、"高甲 construct"、"不死"三类敌各算一遍。
--   流血风暴(短弓+流血)、破甲重弩(弩+穿甲)、灼焰长弓(长弓+火)。
-- ----------------------------------------------------------------------------
print("\n=== 2) 三套 build 有效 DPS(同等级 50、同 ilvl) ===")

local L = 50
local agi = 5 + (L-1)*2
local str = 5 + (L-1)*2
local ilvl = L
local wbudget = GEAR_BUDGET*ilvl*1.6*2.0   -- rare 武器(蓝)
local wdps = wbudget*WEAPON_DPS_K

-- 每类武器:攻速带取中值,内置暴击;箭三轴效果用乘算封顶 1.30
local builds = {
  { name="流血风暴(短弓+流血+风羽)", wspd=(0.72+0.92)/2, crit_in=-0.02, dot="bleed",
    note="高频叠流血(无视护甲)" },
  { name="破甲重弩(弩+穿甲+鹰羽)",   wspd=(0.34+0.46)/2, crit_in=0.06,  pierce=0.30,
    note="单发大+破甲高暴" },
  { name="灼焰长弓(长弓+火+普通羽)", wspd=(0.50+0.64)/2, crit_in=0.0,  ele="fire",
    note="火 DOT 稳覆盖" },
}

-- 三类目标敌人(等级 50)
local targets = {
  { name="肉怪/boss(高hp 中甲)", hp=60*8*(1+(L-1)*0.22), armor=20*0.6*(1+(L-1)*0.22), family="beast" },
  { name="高甲 construct",        hp=60*2.6*(1+(L-1)*0.22), armor=20*1.2*(1+(L-1)*0.22)*1.3, family="construct" },
  { name="不死 undead",           hp=60*1.4*(1+(L-1)*0.22), armor=20*0.4*(1+(L-1)*0.22), family="undead" },
}

local function build_dps(b, tgt)
  local wspeed = b.wspd*(1+agi*0.006)
  local crit = math.min(0.6, 0.05 + agi*0.0004 + (b.crit_in or 0))
  local feat_crit = (b.crit_in and b.crit_in>0) and 0.05 or 0   -- 鹰羽配弩
  local feat_haste = (b.dot=="bleed") and 0.06 or 0             -- 风羽配短弓
  crit = math.min(0.6, crit + feat_crit)
  wspeed = wspeed*(1+feat_haste)
  local wmid = wdps/b.wspd                                       -- 守恒:wmid=budget*K/wspeed(用带中值)
  local arrow_mult = 3.0   -- L50 高档箭
  local atk_mid = 5 + wmid + str
  local cf = 1 + crit*(CRIT_MULT-1)
  -- 穿甲:减敌护甲;火:对不死 ×1.2(封顶);流血:无视护甲的 DOT 额外约 +25% 对高 hp
  local pierce = b.pierce or 0
  local eff_armor = tgt.armor*(1-pierce)
  local base_dps = atk_mid*arrow_mult*cf*wspeed*(1-mitigation(eff_armor))
  -- 元素/特效 build 杠杆(乘算,封顶 +30%)
  local lever = 1.0
  if b.dot=="bleed" then
    -- 流血:无视护甲叠层,对高 hp 收益最大;按目标 hp 给 +0~25%
    lever = lever * (1 + math.min(0.25, tgt.hp/3000))
  end
  if b.ele=="fire" and tgt.family=="undead" then lever = lever*1.20 end
  if b.ele=="fire" and tgt.family=="construct" then lever = lever*0.9 end   -- 构造抗火
  if b.pierce and tgt.family=="construct" then lever = lever*1.15 end       -- 破甲克高甲
  lever = math.min(1.30, lever)
  return base_dps*lever
end

for _,tgt in ipairs(targets) do
  print("  -- 对 "..tgt.name.." --")
  local vals = {}
  for _,b in ipairs(builds) do
    local d = build_dps(b, tgt)
    vals[#vals+1] = d
    print(string.format("    %-26s DPS=%.0f", b.name, d))
  end
  local mn,mx = math.huge,-math.huge
  for _,v in ipairs(vals) do mn=math.min(mn,v); mx=math.max(mx,v) end
  print(string.format("    场景内极差 = %.0f%% (max/min-1)", (mx/mn-1)*100))
end

-- 跨场景:每套 build 在其最佳场景 vs 最差场景的相对优势
print("\n  -- 每套 build 的场景敏感性(最强/最弱场景) --")
for _,b in ipairs(builds) do
  local mn,mx=math.huge,-math.huge
  for _,tgt in ipairs(targets) do local d=build_dps(b,tgt); mn=math.min(mn,d); mx=math.max(mx,d) end
  print(string.format("    %-26s 场景波动 = %.0f%%", b.name, (mx/mn-1)*100))
end
