# QUIVER 挂机扩展设计（合并稿）

> 来源：1 份现状地图 + 5 份子系统设计（技能/采集/制造/地区/集成）+ 1 份对抗评审。
> 评审挑出 **4 个 blocker** 与一份「集成必须统一的契约」，本稿已据此拍板，冲突处只留唯一方案。
> 硬约束：单文件 `main.lua`、零依赖、数据驱动、复用现有 `setc/rrect/panel/button/bar/ring/icon_*/draw_archer`、所有数值接现有锚点、不为单实现造扩展点。

---

## 0. 契约清单（任何子系统不得私改）

1. **`player.skill` 唯一形状** = `{ woodcut={lvl,xp}, mining={lvl,xp}, herb={lvl,xp} }`（仅三个采集职业，都带经验）。所有 `player.skill[id]` 读取一律改 `player.skill[id].lvl`。
2. **制造职业独立** = `player.craft={lvl=1,xp=0}`（不进 `player.skill`，因为靠做工攒经验而非金币）。`skill.fletch` 字段彻底删除。
3. **发射唯一入口** `do_shot(mult, opts)`：唯一「射出抛射物」的函数，`opts={dot=, no_ammo=}`。`archer_fire()` = `do_shot(1.0,{})` 普攻别名。`cast_skill()` 内 shot 类技能调 `do_shot(s.dmg_mult, {no_ammo=true, ...})`。**【决策】主动 shot 技能不扣箭（`no_ammo=true`）但仍读取当前最高箭档倍率/颜色（享用箭档加成，只是不消耗库存）；普通攻击照常吃箭。buff/heal 不发射不吃箭。** 这同时缓解 Blocker#2（技能不再额外叠加「消耗式箭档」，且 dmg_mult 已压低）。
4. **ATB 触发点（L442）**：`player.atb>=1` 分支由 `archer_fire()` 改 `cast_skill()`；`cast_skill` 过滤可用技能后**按 prio 降序确定性取第一个**，挑不到回退 `do_shot(1.0,{})`。enemy 分支不动。
5. **SKILLS schema** = `{ id, name, cd, prio, effect("shot"/"dot"/"heal"/"buff"), dmg_mult, multi?, color, learn={lvl=N} 或 {master=true,cost_g=,cost_mat={}} }`。
6. **技能态字段**：`player.skills={"shoot"}`（已学 id 数组）、`player.cd={}`（id→剩余冷却秒）、`player.buffs={}`（`{kind,amt,t}`）、`enemy.dots={}`（`{dmg,left,tick,acc,color}`）。`recalc` 末尾**只读** `player.buffs` 叠加 atk_speed/crit，**绝不改** max_hp/hp。
7. **panel_open 取值最终集合** = `nil|"activity"|"bag"|"equip"|"region"|"skills"`（技能面板用复数 `"skills"`，与 `player.skills` 一致，和采集职业 `player.skill` 区分）。修正 L126 注释笔误。
8. **`region.nodes` 唯一 schema** = `{ wood={kinds={...},lvloff=N}, ore={kinds={...},lvloff=N}, herb={kinds={...},lvloff=N} }`。`roll_node` 按当前 activity 映射到 mat（woodcut→wood / mining→ore / herb→herb），读 `region.nodes[mat]`，从 kinds 抽展示名，`node_lvl=clamp(random(lo,hi)+lvloff,1,99)`。**kinds 只做展示名+等级载体，产物仍归并到 wood/ore/herb 三种**（不炸开 MATERIALS）。
9. **REGIONS 项结构** = `{id,name,tier("low"/"mid"/"high"),lo,hi,ilo,ihi,rar={4},rar_elite={2},enemies={},nodes={...}}`。单值 `level/ilvl` 废弃。
10. **`make_enemy(arch_id, rank)`**：`next_enemy` 先掷 rank（先判 rare 后判 elite）再传入。`ENEMY_RANK` 是 elite/rare 系数唯一来源。**elite/rare 的 lvl 用 region 区间随机（不用 ceil(hi*1.2)），仅乘 hp/atk/armor 系数；atk 系数必须保守**。
11. **`MAT_NAME/MAT_COLOR` 覆盖所有可能进背包的 mat id**（含 ironbar/leather），否则取色/取名 nil 崩溃。新增 `POT_NAME/POT_COLOR`。MATERIALS 展示数组保持 wood/ore/herb 三种。
12. **列表面板 draw/press 共用几何函数**（对齐现有 `equip_cell_rect/bag_cell_rect`）：新增 `region_card_rect(i, scroll_y)`、`act_row_rect(group_i,row_i)`。20 区列表按 tier 三段单列可滚动。

---

## 1. 活动优先级层级（idle > 战斗 > 副职业）

`ACTIVITIES` 每项加 `group("idle"/"combat"/"sub")` + `ord`，`rest` 改名「挂机」置顶；`ACT_ORDER` 重排为 idle→combat→sub；活动菜单按 `ACT_GROUPS` 分段画分组标题。底部入口标签前加分组色点，一眼看出当前处于哪一层。

```lua
local ACTIVITIES = {
  rest    = { name="挂机", kind="rest",   group="idle",   ord=1 },
  combat  = { name="战斗", kind="combat", group="combat", ord=1 },
  woodcut = { name="砍柴", kind="gather", group="sub", ord=1, mat="wood", skill="woodcut" },
  mining  = { name="采矿", kind="gather", group="sub", ord=2, mat="ore",  skill="mining"  },
  herb    = { name="采药", kind="gather", group="sub", ord=3, mat="herb", skill="herb"    },
  craft   = { name="制造", kind="craft",  group="sub", ord=4 },  -- 原 fletch，语义升级为通用制造
}
local ACT_ORDER  = { "rest","combat","woodcut","mining","herb","craft" }
local ACT_GROUPS = {
  { id="idle",   name="挂机",   col={0.5,0.7,0.95} },
  { id="combat", name="战斗",   col=UI.bad },
  { id="sub",    name="副职业", col={0.6,0.55,0.4} },
}
```

底部入口 4→5：`[活动][技能][背包][装备][地区]`，`bw=(w-sx(20)-gap*4)/5, gap=sx(6)`。**活动菜单的材料栏移除**（背包已有材料区），避免分组后面板溢出 `h-sy(112)`。

---

## 2. player 状态增改清单（init L449-462 / recalc L249-267）

```lua
-- 采集职业（带经验，替换原 skill={woodcut=1,...,fletch=1}）
skill = { woodcut={lvl=1,xp=0}, mining={lvl=1,xp=0}, herb={lvl=1,xp=0} },
-- 制造职业（独立，做工升级）
craft = { lvl=1, xp=0 },
craft_bp = "wood", craft_prog = 0, craft_target = nil,
bp_known = { wood=true },        -- learn=="start" 的图谱初始已知
-- 采集遭遇态
gather_node = nil,
-- 角色技能态
skills = { "shoot" }, cd = {}, buffs = {}, cast_flash = {},
-- 删除：player.acc（遭遇式不再线性累积）、player.fletch_*（改名 craft_*）
```

`recalc` 末尾追加（**只读 buffs，只动 atk_speed/crit**）：
```lua
for _,b in ipairs(player.buffs) do
  if b.kind=="haste" then player.atk_speed = player.atk_speed*(1+b.amt)
  elseif b.kind=="crit" then player.crit = math.min(0.6, player.crit+b.amt) end
end
```

---

## 3. 角色技能系统

### 3.1 数据表（ARROW/BLUEPRINTS 之后）
```lua
local SKILLS = {
  shoot  ={ id="shoot",  name="普通射击", cd=0,    prio=0, effect="shot", dmg_mult=1.0, multi=1, color={0.8,0.8,0.85}, learn={lvl=1} },
  power  ={ id="power",  name="强力射击", cd=3.0,  prio=5, effect="shot", dmg_mult=1.7, multi=1, color={1.0,0.7,0.2},  learn={lvl=3} },
  double ={ id="double", name="双重射击", cd=4.5,  prio=4, effect="shot", dmg_mult=0.75,multi=2, color={0.5,0.8,1.0},  learn={lvl=6} },
  aimed  ={ id="aimed",  name="瞄准射击", cd=6.0,  prio=6, effect="shot", dmg_mult=1.5, multi=1, color={0.55,0.9,0.75},learn={master=true,cost_g=120,cost_mat={ore=10}} },  -- 原"穿云箭"，去 pierce，纯高伤单发
  poison ={ id="poison", name="毒箭",     cd=7.0,  prio=7, effect="dot",  dmg_mult=0.5, dot_mult=0.3, dot_dur=4, dot_tick=1, color={0.5,0.85,0.45}, learn={master=true,cost_g=150,cost_mat={herb=12}} },
  rapid  ={ id="rapid",  name="疾风蓄势", cd=12.0, prio=8, effect="buff", buff="haste", buff_amt=0.4, buff_dur=5, color={0.5,0.9,0.9},  learn={lvl=10} },
  hawkeye={ id="hawkeye",name="鹰眼",     cd=16.0, prio=8, effect="buff", buff="crit",  buff_amt=0.25,buff_dur=6, color={1.0,0.55,0.2}, learn={master=true,cost_g=220,cost_mat={herb=8,ore=8}} },
  mend   ={ id="mend",   name="包扎",     cd=14.0, prio=9, effect="heal", heal_pct=0.30, color={0.5,0.85,0.5}, learn={master=true,cost_g=100,cost_mat={herb=10}} },
}
local SKILL_ORDER = { "shoot","power","double","aimed","poison","rapid","hawkeye","mend" }
```

### 3.2 机制（接 ATB / archer_fire / resolve_hit）
- **do_shot(mult, opts)**（由 archer_fire L387-399 原地拆出）：保留「取最高可用箭档→`ammo_remove(1)`→掷暴击→`raw=attack*箭档*mult*(crit?2:1)`→`dmg=max(1,raw*(1-mitigation))`」；新增 `opts.dot` 写进 projectile（命中挂毒）。`archer_fire()=do_shot(1.0,{})`。
- **cast_skill()**（archer_fire 之后新增）：遍历 `player.skills`，过滤「`cd` 就绪 且 情境有意义」（heal 仅 `hp<max*0.6`、buff 仅同 kind 不在场），**按 prio 降序确定性取第一个** s：
  - `shot`：循环 `s.multi` 次 `do_shot(s.dmg_mult, {})`，多发各加 ±0.12 ang 抖动。
  - `dot`：`do_shot(s.dmg_mult, {dot={mult=s.dot_mult,dur=s.dot_dur,tick=s.dot_tick,color=s.color}})`。
  - `heal`：`player.hp=min(max_hp, hp+max_hp*s.heal_pct)` + 绿飘字/绿粒子，不发射。
  - `buff`：同 kind 先移除再 push `{kind,amt,t=dur}`（**刷新不叠加**），飘技能名。
  - 挑不到 → `do_shot(1.0,{})`。命中后 `cd[s.id]=s.cd; cast_flash[s.id]=0.4`。
- **update 头部（L412-416）**：递减 `player.cd / buffs.t / cast_flash`（全局回充，切回战斗即就绪）。
- **DOT 结算（L441 之前，phase=="fight"）**：遍历 `enemy.dots`，`acc+=dt`，满 tick 扣血/飘小绿字/粒子；血<=0 走抽出的 `kill_enemy()`（把 resolve_hit 死亡段抽成函数复用）。
- **学习**：`check_skill_unlock()`（gain_xp 升级后 L281 调）扫 SKILLS，`learn.lvl<=player.level` 且未学则 push + toast。技能大师 `learn_skill(id)`：扣金币+材料后 push。

### 3.3 ⚠ Blocker#2 修正 — 技能伤害不膨胀
技能 dmg_mult 已压低（power 2.2→**1.7**、aimed 1.6→**1.5**、double 单发 0.8→**0.75**、buff 幅度下调）。**验收口径（落地后必须对照）**：长期 DPS 增益（含冷却覆盖率）≤ **+40~60%**，而非只看单发峰值。
- 强力 1.7×、cd3s、atk_speed≈0.57（≈1.75s/次）→ 约每 2 次行动放 1 次 → 峰值增益 ≈ (1.7-1)/2 ≈ **+35%**。
- 疾风 haste+40%/5s、cd12 → 覆盖率 5/12≈42% → 等效 **+17%** 长期攻速。
- 鹰眼 crit+25%/6s 仍受 `min(0.6)` 钳制，CRIT_MULT=2.0 不变。
- aimed 去掉 pierce 字段与 update 特判（**Blocker/Major：pierce 是为不存在的怪群预留的扩展点，第一期砍掉**），仅作高伤单发。

### 3.4 UI（看得见技能在放）
- **战斗技能栏**（draw_combat L628-629 之后）：玩家 hp/atb 条下方 `py+sy(56)` 横排 `player.skills`，每槽 `sx(34)` 方格、间距 `sx(6)`。`panel` 底（技能色淡底+描边）+ `draw_skill_icon(s)`；冷却中盖 `setColor(0,0,0,0.55)` 灰罩 + `ring(cx,cy,sx(13),1-cd/s.cd,色)` 回充环；`cast_flash>0` 时放大 1.15x+白闪。8 格在 480 宽放得下（34*8+6*7=314）。
- **技能大师面板** `draw_skills()`（仿 draw_activity）：列 SKILL_ORDER，每行 图标+名+一句效果（"伤害x1.7"/"中毒4秒"/"回血30%"/"攻速+40% 5秒"）+冷却；已学=绿"已学"，等级未到=灰"Lv N 解锁"，可学=`button("学习 120金+矿x10", enabled=金料够)`。底部返回。

---

## 4. 采集类副职业（遭遇式）

把 woodcut/mining/herb 从「线性产材料」改造成与战斗同构的遭遇状态机，**三种采集共用一台机器**，只换 mat 与地区池。

### 4.1 数据（常量区 + 显示表）
```lua
local GATHER_SEARCH, GATHER_FOUND, GATHER_DONE = 0.7, 0.35, 0.3   -- 阶段时长（放 ENTER_TIME 旁）
local MAT_REQ_FAIL = { wood="树木等级不足", ore="矿石等级不足", herb="草药等级不足" }
-- NODE_NAME：kinds 展示名（橡木/铜矿/三叶草…），由地区 kinds 驱动；产物仍归 wood/ore/herb
local NODE_BASE = { wood={hp=1.0,yield=1.0}, ore={hp=1.4,yield=0.8}, herb={hp=0.8,yield=0.9} }
```

### 4.2 状态机 `node_machine(dt)`（替换 activity_tick 的 gather 分支 L318-328，写法刻意复刻战斗 update 尾部）
- **search（0.7s）**：无 node 或上一个 done → 进入；满 → `roll_node()`。
- **roll_node()**（仿 next_enemy）：mat=当前 activity 对应材料；读 `region.nodes[mat]`，从 kinds 抽展示名；`node_lvl=clamp(random(lo,hi)+lvloff,1,99)`；偶发富集 rich(5%) `node_lvl+=ceil(region.hi*0.2)`、产量翻倍。`make_node` 实例化 → found。
- **found（0.35s）**：节点 ease-out 滑入（复用 enemy enter）。到位判定 `player.skill[mat映射].lvl >= node.level`：
  - 够 → `phase="harvest"`，atb=0。
  - 不够 → `add_float(MAT_REQ_FAIL[mat]+"(需Lv"..node.level..")", UI.bad)` + 红描边闪 → node=nil → 回 search（**立刻找下一个**）。
- **harvest（像打怪）**：`node.atb += harvest_speed*dt`，满 1 触发 `chop()`（`dur-=1`、flash/hurt、碎屑粒子）；dur<=0 → `finish_node()`。
- **finish_node()**（仿 drop_loot）：`inv_add("mat",mat,node.yield)`、`gain_gather_xp(mat,node.xp)`、burst+飘"+N 木材" → done。
- **done（0.3s）** → 淡出 → 回 search。

### 4.3 数值（接锚点）
- `harvest_speed = 0.9*(1+(gather_lvl-1)*0.05)`；`max_dur = ceil(3*NODE_BASE.hp*(1+node_lvl*0.12))`。
- `yield = max(1, floor(NODE_BASE.yield*(1+node_lvl*0.18)*(1+(gather_lvl-1)*0.04)))`，rich×2。
- `node.xp = floor(node_lvl*5+6)`；`gather_need(lvl)=floor(50*lvl^1.55)`。
- **⚠ Blocker/Major（采集产率 vs 箭耗供需闭环）**：遭遇式起步产率（Lv1 树 ≈0.30/s）低于战斗箭耗（≈0.57/s）。落地后**必须验收一条完整循环**「挂采集 X 秒攒料 → 制造把料变箭 → 战斗能打多久」，证明箭不会饿死。修正手段（按需启用）：起步 yield 给 2~3、或缩短 search/done、或明确「采集本就慢于箭耗，逼三态轮换」并出三段产率对照表。

### 4.4 UI（draw_gather L633-655 按 phase 分支）
search 火柴人张望+头顶放大镜随 `sin` 摆 + `bar(phase_t/0.7,UI.dim)`；found 节点滑入+判定描边（绿勾/红闪）；harvest 复用 L639-648 三种节点画法 + flash/hurt + `bar(dur/max_dur, MAT_COLOR)` 耐久条 + 细 atb 条 + 头顶 `Lv` 标签（够=text/不够=bad）；done 淡出。顶部 `ring` 改显**采集职业 xp/等级环**，中心印 `Lv`。

---

## 5. 制造类副职业（图谱式）

把硬编码 ARROW_TIERS 升级为统一 `BLUEPRINTS`，制箭只是「造箭类图谱」，与中间材料/药剂共用同一套 `can_craft/do_craft`，**不并存两套**。

### 5.1 数据（替换 ARROW_TIERS L80-85，保留 ARROW_BATCH=20）
```lua
local CRAFT_BASE = 0.20
local BLUEPRINTS = {
  { id="wood",   name="木箭",   req=1, time=4, learn="start",  out={kind="arrow",id="wood",  qty=ARROW_BATCH,mult=1.0, color={0.62,0.46,0.26}}, cost={wood=3} },
  { id="iron",   name="铁箭",   req=2, time=5, learn="level",  out={kind="arrow",id="iron",  qty=ARROW_BATCH,mult=1.35,color={0.72,0.74,0.8}},  cost={wood=2,ore=3} },
  { id="hunter", name="猎手箭", req=4, time=6, learn="level",  out={kind="arrow",id="hunter",qty=ARROW_BATCH,mult=1.75,color={0.5,0.85,0.55}}, cost={wood=2,ore=2,herb=3} },
  { id="rune",   name="符文箭", req=7, time=8, learn="master", out={kind="arrow",id="rune",  qty=ARROW_BATCH,mult=2.3, color={0.78,0.5,1.0}},  cost={wood=3,ore=4,herb=4} },
  { id="ironbar",name="精铁锭", req=3, time=6, learn="level",  out={kind="mat",  id="ironbar",qty=1, color={0.8,0.82,0.88}}, cost={ore=4} },
  { id="hppot",  name="疗伤药剂",req=2, time=5, learn="level",  out={kind="potion",id="hppot", qty=1, color={0.9,0.35,0.4}},  cost={herb=4} },
  { id="leather",name="鞣制皮革",req=5, time=7, learn="master", out={kind="mat",  id="leather",qty=2, color={0.7,0.5,0.32}}, cost={herb=3,ironbar=1} },
}
local BP = {}; for _,b in ipairs(BLUEPRINTS) do BP[b.id]=b end
-- MAT_NAME/MAT_COLOR 补 ironbar/leather；新增 POT_NAME/POT_COLOR={hppot=...}（药剂走 inv_*）
```

### 5.2 机制
- **activity_tick craft 分支重写（L329-344）**：`bp=BP[player.craft_bp]`；`bp and bp_known[bp.id] and can_craft(bp)` → `craft_prog += CRAFT_BASE*craft.lvl/bp.time*dt`，满 1 调 `do_craft(bp)`；否则 prog=0 并（首次缺料）`set_toast("材料不足，已停止制造",UI.bad)`。「直到材料用尽自动停」由 can_craft 失败自然实现。
- **can_craft(bp) / do_craft(bp)**（合并 L289-298）：遍历 `bp.cost`（ironbar/leather 也走 mat，天然支持材料链）；do_craft 扣料→按 `out.kind` 分发（arrow→ammo_add；mat/potion→inv_add）→`player.craft.xp += ceil(bp.time*2)`→`add_craft_xp()`→recalc。删 `craft()/best_affordable_tier()`。
- **职业等级**：`craft_need(lvl)=floor(40*lvl^1.4)`；速率 `CRAFT_BASE*craft.lvl/bp.time`（木箭 Lv1=20s/批≈1支/秒，Lv5=4s/批）。`add_craft_xp` 升级后调 `unlock_blueprints()`（level 类满 req 自动学，master 类第一期也按 req 自动解锁挂 TODO，技能大师入口与角色技能一起做）。
- **recalc 箭档读取**：数据源从 ARROW_TIERS 改遍历箭袋 id 查 `BP[id].out.mult/color` 取最高（逻辑等价）。
- **材料链**：解锁顺序 ironbar(req3) 先于 leather(req5)，成立。`MAT_NAME/MAT_COLOR` 必须覆盖 ironbar/leather（否则崩）。

### 5.3 UI
draw_fletch（→draw_craft）产出图标按 `out.kind` 分发（arrow→icon_arrow / mat→icon_mat / potion→新增极简 icon_potion）；**下半屏列已知图谱卡**（图标+产出x数+耗材色块串+可造亮/缺料红/未学灰锁，选中高亮）——这是「挂机页下方展示所有图谱」。活动菜单 craft 行只显 `制造 Lv X + 经验条`（去掉金币升级按钮）。

---

## 6. 地区系统（20 区 + 三档 + 精英/稀有）

### 6.1 三档与结构
```lua
local TIER_BAND = {
  low ={ name="低级", pmin=1, pmax=15, color={0.5,0.8,0.55} },
  mid ={ name="中级", pmin=16,pmax=35, color={0.95,0.8,0.4} },
  high={ name="高级", pmin=36,pmax=60, color={0.9,0.45,0.5} },
}
local ENEMY_RANK = {   -- ⚠ Blocker#1 修正：atk 系数保守，lvl 用区间随机而非 ceil(hi*1.2)
  normal={ p=1.00, hp=1.0, atk=1.0,  armor=1.0, ilvl_bonus=0, rar_up=0.0, tag="" },
  elite ={ p=0.07, hp=1.6, atk=1.15, armor=1.2, ilvl_bonus=2, rar_up=0.5, tag="精英", color_mul=1.15 },
  rare  ={ p=0.02, hp=2.2, atk=1.3,  armor=1.3, ilvl_bonus=4, rar_up=1.0, tag="稀有", color_mul=1.3 },
}
-- 低档(tier=="low")禁用 rare：next_enemy 里 if region.tier=="low" then rare→normal。
```

### 6.2 20 个地区（低 6 / 中 6 / 高 8，区间连续微重叠）
```lua
local REGIONS = {
  -- 低级 1-15
  {id="meadow",  name="晨曦绿野", tier="low", lo=1, hi=4,  ilo=2, ihi=6,  rar={"poor","common","common","uncommon"}, rar_elite={"uncommon","rare"}, enemies={"boar","wolf"},          nodes={wood={kinds={"oak"},lvloff=0},        ore={kinds={"copper"},lvloff=-1},     herb={kinds={"clover"},lvloff=0}} },
  {id="brook",   name="低语溪谷", tier="low", lo=3, hi=6,  ilo=4, ihi=9,  rar={"poor","common","common","uncommon"}, rar_elite={"uncommon","rare"}, enemies={"boar","wolf","bandit"},  nodes={wood={kinds={"oak","birch"},lvloff=0},ore={kinds={"copper"},lvloff=0},      herb={kinds={"clover","mint"},lvloff=0}} },
  {id="downs",   name="风吹荒原", tier="low", lo=5, hi=8,  ilo=6, ihi=11, rar={"common","common","uncommon","uncommon"}, rar_elite={"uncommon","rare"}, enemies={"wolf","bandit"},     nodes={wood={kinds={"birch"},lvloff=-1},     ore={kinds={"copper","tin"},lvloff=1}, herb={kinds={"mint"},lvloff=0}} },
  {id="darkwood",name="幽暗森林", tier="low", lo=7, hi=10, ilo=8, ihi=14, rar={"common","uncommon","uncommon","rare"}, rar_elite={"rare","epic"}, enemies={"wolf","bandit","ogre"},   nodes={wood={kinds={"birch","ash"},lvloff=1},ore={kinds={"tin"},lvloff=0},          herb={kinds={"mint","sage"},lvloff=0}} },
  {id="quarry",  name="碎石矿场", tier="low", lo=9, hi=12, ilo=10,ihi=16, rar={"common","uncommon","uncommon","rare"}, rar_elite={"rare","epic"}, enemies={"bandit","ogre"},          nodes={wood={kinds={"ash"},lvloff=0},        ore={kinds={"tin","iron"},lvloff=2},  herb={kinds={"sage"},lvloff=-1}} },
  {id="fen",     name="腐沼湿地", tier="low", lo=11,hi=14, ilo=12,ihi=18, rar={"uncommon","uncommon","rare","rare"}, rar_elite={"rare","epic"}, enemies={"wolf","ogre","wraith"},     nodes={wood={kinds={"ash","yew"},lvloff=0},  ore={kinds={"iron"},lvloff=0},        herb={kinds={"sage","nightcap"},lvloff=1}} },
  -- 中级 16-35
  {id="ruins",   name="沉没遗迹", tier="mid", lo=15,hi=19, ilo=16,ihi=23, rar={"uncommon","rare","rare","epic"}, rar_elite={"epic","legendary"}, enemies={"bandit","ogre","wraith"}, nodes={wood={kinds={"yew"},lvloff=0},        ore={kinds={"iron","silver"},lvloff=1},herb={kinds={"nightcap"},lvloff=0}} },
  {id="canyon",  name="赤红峡谷", tier="mid", lo=18,hi=22, ilo=20,ihi=27, rar={"uncommon","rare","rare","epic"}, rar_elite={"epic","legendary"}, enemies={"ogre","wraith","golem"},  nodes={wood={kinds={"yew"},lvloff=-1},       ore={kinds={"silver"},lvloff=2},      herb={kinds={"nightcap","emberbloom"},lvloff=1}} },
  {id="hollow",  name="回响洞窟", tier="mid", lo=21,hi=25, ilo=23,ihi=31, rar={"rare","rare","epic","epic"}, rar_elite={"epic","legendary"}, enemies={"wraith","golem","ogre"},      nodes={wood={kinds={"yew","ironwood"},lvloff=0},ore={kinds={"silver","mithril"},lvloff=1},herb={kinds={"emberbloom"},lvloff=0}} },
  {id="peak",    name="霜寒峰",   tier="mid", lo=24,hi=28, ilo=26,ihi=34, rar={"rare","rare","epic","epic"}, rar_elite={"epic","legendary"}, enemies={"ogre","wraith","golem"},      nodes={wood={kinds={"ironwood"},lvloff=0},   ore={kinds={"mithril"},lvloff=1},     herb={kinds={"emberbloom","frostlily"},lvloff=1}} },
  {id="wastes",  name="灰烬废土", tier="mid", lo=27,hi=31, ilo=29,ihi=37, rar={"rare","epic","epic","legendary"}, rar_elite={"epic","legendary"}, enemies={"wraith","golem"},        nodes={wood={kinds={"ironwood"},lvloff=-1},  ore={kinds={"mithril"},lvloff=2},     herb={kinds={"frostlily"},lvloff=0}} },
  {id="catacomb",name="尘封地穴", tier="mid", lo=30,hi=34, ilo=32,ihi=40, rar={"rare","epic","epic","legendary"}, rar_elite={"epic","legendary"}, enemies={"wraith","golem","ogre"}, nodes={wood={kinds={"ironwood","darkoak"},lvloff=0},ore={kinds={"mithril","adamant"},lvloff=1},herb={kinds={"frostlily","mandrake"},lvloff=0}} },
  -- 高级 36-60
  {id="spire",   name="苍穹尖塔", tier="high",lo=35,hi=40, ilo=37,ihi=46, rar={"epic","epic","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"golem","wraith"},   nodes={wood={kinds={"darkoak"},lvloff=0},    ore={kinds={"adamant"},lvloff=1},     herb={kinds={"mandrake"},lvloff=0}} },
  {id="abyss",   name="深渊裂口", tier="high",lo=39,hi=44, ilo=41,ihi=50, rar={"epic","epic","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"wraith","golem"},   nodes={wood={kinds={"darkoak"},lvloff=-1},   ore={kinds={"adamant"},lvloff=2},     herb={kinds={"mandrake","voidbloom"},lvloff=1}} },
  {id="cinder",  name="炽炎熔狱", tier="high",lo=43,hi=48, ilo=45,ihi=54, rar={"epic","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"golem","ogre"}, nodes={wood={kinds={"darkoak","emberwood"},lvloff=0},ore={kinds={"adamant","starsteel"},lvloff=1},herb={kinds={"voidbloom"},lvloff=0}} },
  {id="glacier", name="永冻冰川", tier="high",lo=47,hi=52, ilo=49,ihi=58, rar={"epic","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"golem","wraith"}, nodes={wood={kinds={"emberwood"},lvloff=0},  ore={kinds={"starsteel"},lvloff=1},   herb={kinds={"voidbloom","frostlily"},lvloff=-1}} },
  {id="rift",    name="虚空断界", tier="high",lo=51,hi=56, ilo=53,ihi=62, rar={"legendary","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"wraith","golem"}, nodes={wood={kinds={"emberwood"},lvloff=-1},ore={kinds={"starsteel"},lvloff=2},   herb={kinds={"voidbloom"},lvloff=1}} },
  {id="throne",  name="陨灭王座", tier="high",lo=55,hi=60, ilo=57,ihi=66, rar={"legendary","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"golem","wraith","ogre"}, nodes={wood={kinds={"emberwood","worldroot"},lvloff=0},ore={kinds={"starsteel","voidiron"},lvloff=1},herb={kinds={"voidbloom","mandrake"},lvloff=0}} },
}
```
local ENEMY_ARCH = {  -- 现有 6 种保留，新增 4 种高级敌型（决策④：现在就补，供 36-60 高区用）
  -- boar/wolf/bandit/ogre/wraith/golem ... 不变
  frost   ={ name="霜魔",     hp=1.5, dmg=1.7, armor=0.5, spd=0.6,  color={0.6,0.8,0.95} },
  voidcat ={ name="虚空兽",   hp=1.4, dmg=2.0, armor=0.4, spd=0.78, color={0.45,0.3,0.6} },
  drake   ={ name="幼龙",     hp=2.2, dmg=1.8, armor=0.9, spd=0.5,  color={0.7,0.35,0.3} },
  revenant={ name="亡灵骑士", hp=1.9, dmg=1.6, armor=1.1, spd=0.55, color={0.5,0.55,0.6} },
}
-- 高区 enemies 池改用新敌型（spire 起逐步混入 frost/revenant/drake/voidcat）：
--   spire={golem,frost} canyon 不变 ... abyss={wraith,voidcat} cinder={drake,golem}
--   glacier={frost,golem} rift={voidcat,revenant} throne={drake,revenant,golem}


### 6.3 机制
- **make_enemy(arch_id, rank)**：`lvl=random(region.lo,region.hi)`（rank≠normal 也用区间随机，不再 ceil(hi*1.2)）；`scale=1+(lvl-1)*0.22+(stage%5)*0.04` 不动；hp/attack/armor 各乘 `ENEMY_RANK[rank]` 系数；`enemy.rank=rank`，name 加 tag 前缀，color×color_mul。
- **next_enemy()**：先掷 rank（`r<0.02`→rare，再 `<0.09`→elite，否则 normal；低档 rare→normal）→抽敌型→make_enemy。
- **drop_loot()**：`drop_p = normal?0.3:1.0`；`ilvl = normal?random(ilo,ihi):(ihi+ilvl_bonus)`；池 `normal?region.rar:region.rar_elite`，按 `rar_up` 概率用 `RARITIES[min(#,RAR[rid].tier+1)].id` 升一档。经验/金币吃放大后的 enemy.level 自然变高，不特判。
- **draw_combat**：rank≠normal 时身体外画金(elite)/紫(rare)描边光环；击杀 burst 翻倍 + `add_float("精英击破!"/"稀有击破!")`。

### 6.4 地区菜单（draw_regions L741 + press L1098 共用 region_card_rect）
按 tier 三段分组标题 + 段内单列 + 整体 `scroll_y` 可滚动；每卡显 name + `Lv.lo-hi` + 稀有度色点 + TIER_BAND 色条；玩家 level<lo 时降饱和提示偏难（不硬锁，越级吃风险/收益）。

---

## 7. 实施顺序（每步可独立跑，因无法在此运行 LÖVE）

> 原则：先改**不破坏现有可玩性**的数据层，再逐子系统替换，每步替换后游戏应仍能启动并挂机。

1. **契约地基**（state 改形不改玩法）：改 `player.skill→{lvl,xp}`、加 `player.craft/skills/cd/buffs`、删 acc/fletch_*；把所有 `player.skill[id]` 读取改 `.lvl`；修 panel_open 注释。— 动 init/recalc/activity_tick/draw_activity/upgrade_skill 的读取点。**验收**：游戏照常启动、四活动照常挂机（采集暂时仍线性也行，先让它不崩）。
2. **地区数据层**：替换 REGIONS（20 区）+ TIER_BAND + ENEMY_RANK；改 make_enemy/next_enemy/drop_loot 读区间与 rank。**验收**：战斗能打、掉落正常、偶遇精英/稀有且打得过（盯 Blocker#1 的 TTK）。
3. **地区菜单可滚动**：region_card_rect + 三段分组 + 滚动。**验收**：20 区可选、切区生效。
4. **制造图谱化**：ARROW_TIERS→BLUEPRINTS、can_craft/do_craft、craft 等级、recalc 箭档改源、draw_craft 图谱列表。**验收**：选图谱持续造、缺料停、造箭仍喂战斗。
5. **遭遇式采集**：node_machine + make_node/roll_node + draw_gather 四状态 + 采集职业经验。**验收**：寻找→遇到→判定→采集闭环；等级不足跳过；**跑 §4.3 供需闭环验收**。
6. **技能系统**：do_shot 拆分、cast_skill、SKILLS、cd/buff/dot、kill_enemy、check_skill_unlock。**验收**：战斗看得见技能轮转+冷却环；DPS 增益对照 ≤+60%（Blocker#2）。
7. **技能大师面板 + 底部 5 入口 + 活动菜单分组**：draw_skills/skill_press、bottom_btns 5 入口、ACT_GROUPS 分段、act_row_rect。**验收**：动线全通，拖拽/tooltip 不破。

---

## 8. 已拍板决策

1. **主动 shot 技能不吃箭**（`no_ammo=true`），但仍享用当前箭档倍率；普通攻击照常吃箭。
2. **疗伤药剂**：战斗中 `HP < max*0.4` 时自动消耗一瓶回 `max*0.3`（`update` 战斗段检查，背包有 hppot 才触发）；不再做「阵亡免死」。
3. **采集产率**：先按 §4.3 数值落地，跑通「采集→制造→战斗」闭环后按实测调（起步可能调高 yield 或缩短 search）。
4. **高级敌型**：现在就补 4 种（霜魔/虚空兽/幼龙/亡灵骑士），高区 enemies 池混入，见 §6.2。
