# quiver 大改造方案（OVERHAUL_PLAN）

> 状态：可执行方案 v1。基于真实源码核验（main.lua 1782 行、src/game_loader.lua、src/FlexLove.lua、test_headless.lua 69 行）。
> 三大目标：**界面优化（信息高效呈现）**、**代码解耦（从底层往上分层）**、**存档系统**。
> 约束总闸：本环境无法实机 playtest，所有验证只能靠 `luac -p`（语法）+ 扩展后的 `test_headless.lua`（无头冒烟 + 断言）。

---

## 1. 总览 + 与 CLAUDE.md 的张力说明 + 总体取舍

### 现状（已核验）
- `main.lua` 单文件 1782 行，纯 immediate-mode 手画：`draw_combat/gather/fletch/rest/hud/bottom_btns/regions/activity/skills/equip/bag/tooltip` 十几个屏。
- 输入是**单点**：`love.touchpressed(id,x,y)→press(x,y)`、`touchmoved→drag_move(x,y)`、`touchreleased` 按 `region_drag`/`drag` 两个**互斥状态变量**分流——**`id` 被直接丢弃**（main.lua:1774-1776），与 `mousepressed` 完全同构。
- 缩放：`sw=屏宽/480, sh=屏高/800`，`sx(v)=v*sw / sy(v)=v*sh`，在 480×800 设计空间布局。
- **没有 `love.quit`**（grep 0 处）、**没有日志**、**没有存档**。
- 宿主 StoneGate 用 `love.filesystem.mount(.love, "", false)` 把游戏挂进自己进程跑；退出时 `pcall(love.quit)`（loader:266），并清掉本次 require 出的 `package.loaded`（loader:276-280）。

### 与根 CLAUDE.md 的张力（诚实说明）
用户想要"MVVM / 解耦 / 公共设计 / 从底层往上建模"，而根 CLAUDE.md 是 **IMPORTANT/OVERRIDE 级**硬约束："拒绝过度抽象、不要企业分层模板、命名说人话、少依赖、不为单实现造接口/工厂"。两者表面冲突，实质不冲突——**用户真正要的是三个收益（存档好做 / UI 好改 / 加内容好加），不是架构图好看。**

**总体取舍：做"弱 MVVM 的务实投影"，不做企业 MVVM。**
- Model = `sys/` 规则 + `core/state` 持有的游戏态；View = `view/` 的 immediate draw；ViewModel **退化为 view 函数里现读现算的几行**，不单独造类、不做 observable/数据绑定（immediate-mode 每帧重绘，绑定纯属负担）。
- 分层只为上述三个收益服务；任何一层若不能指向其中之一，就不建。
- **第一期明确砍掉 event 发布订阅总线**（见 §2）：当前 `drop_loot→gain_xp→check_skill_unlock` 是**同帧顺序调用**，不是跨系统异步通知，用 emit/on 解耦只会增加间接层、调试更难，违背反过度抽象红线。

---

## 2. 架构与文件树

> 统一为**一套**结构（两份研究给了 `core/+model/` 与 `base/+sys/` 两套，此处拍定后者，命名更贴游戏域）。`main.lua` 保持薄入口，**不挪到 `src/`**（loader 找 `main.lua` 或 `src/main.lua`，保持根 main.lua 少一层）。

```
quiver/
  conf.lua                 # 现有，不动（identity quiver_proto, 480x800）
  main.lua                 # 薄入口 ~60-90 行：love.load/update/draw/touch*/mouse*/wheel/resize/quit + require 装配 + 转调
  assets/                  # 现有字体等
  test_headless.lua        # 冒烟测试（第0阶段先扩展）

  base/                    # 底层工具：只依赖 love，禁止出现 player/enemy/SKILLS 等游戏名词
    screen.lua             # DESIGN_W/H, sw/sh, sx()/sy(), set_scale/resize
    draw.lua               # setc/rrect/panel/button/bar/ring/mat_chip + 全部 icon_*/draw_skill_icon + 字体句柄。无状态绘制函数库
    assets.lua             # 字体加载/缓存（搬 love.load 里 mkfont/CJK 回退）
    save.lua               # 序列化 + read/write + version/migrate（见 §4）。纯 IO，不 require sys
    log.lua                # love.filesystem.append 写 quiver/quiver.log（绝不碰 stonegate.log）
  fx.lua                   # floats/particles/shake/swing/t_accum + add_float/burst/set_toast/update_fx/draw_particles
                           #   被所有 sys 单向依赖，自己不依赖任何 sys —— 打断 set_toast/node_machine 前向声明
  data.lua                 # 【第一期单文件】全部静态表：RARITIES/SLOTS/ATTRS/AFFIXES/MATERIALS/BLUEPRINTS/ARROWS/
                           #   SKILLS/ACTIVITIES/REGIONS/ENEMY_*/NODE_*/UI + 数值锚点 GEAR_BUDGET/CRIT_MULT/...
  core/
    state.lua              # 集中运行态：player/enemy/region/stage/activity/panel_open/result_banner/drag/tooltip/scroll
                           #   提供 open_panel/close/current。存档只需序列化这一个根
    input.lua              # press/drag_move/drag_release/wheel 总分发：按 panel_open 路由到 view.*.hit
  sys/                     # 游戏规则，每文件一个游戏关注点
    progression.lua        # recalc/xp_need/gain_xp/check_skill_unlock/各职业经验曲线
    inventory.lua          # inv_*/ammo_*/max_stack/roll_gear/add_gear_stats/gear_score/gear_*/装备换装
    combat.lua             # make_enemy/next_enemy/do_shot/cast_skill/resolve_hit/enemy_attack/kill_enemy/drop_loot + 战斗 tick
                           #   技能轮转 learn_skill/技能大师第一期留这里（与 do_shot/projectiles 共生），数据在 data.lua
    gather.lua             # node_machine/make_node/finish_node + 采集遭遇状态机
    craft.lua              # can_craft/do_craft/unlock_blueprints + craft tick
    regions.lua            # 切区/筛选展示逻辑（数据在 data.lua）
  view/                    # immediate-mode 视图：每屏一文件，提供 draw() 和 hit(x,y)->handled
    hud.lua                # 顶部角色卡（头像+HP/弹药/经验）+ 底部活动胶囊 + 入口按钮（需求1主战场）
    combat_view.lua  gather_view.lua  craft_view.lua  rest_view.lua
    bag_view.lua  equip_view.lua  region_view.lua  activity_view.lua  skills_view.lua
    tooltip.lua            # tt_content/tt_geom/draw_tooltip/tooltip_press
  ui.lua                   # 自研轻量 immediate-mode UI 工具箱（见 §3），随 *.lua 打进 .love
```

### 依赖方向（只能向下，禁止成环）
```
main.lua → core + sys + view + base        (入口可见全部，做装配)
view/*   → base.draw + core.state + sys查询 + data + ui
sys/*    → base(save/log) + data + core.state + fx
core/*   → base ; core.input → view.*.hit  (框架调具体视图命中，单向)
fx       → base.draw（画）；被所有 sys 单向依赖，不 require 任何 sys
base/*   → 只依赖 love
```
**禁止**：base 反向 require core/sys/view；`draw.lua` 出现 player/enemy；sys 之间互相 require 成环。`node_machine` 进 `sys/gather`，只依赖 `fx+data+inventory+state`，**不被 craft require**（craft 自己的进度 tick 独立）；拆分时画依赖图确认无环，作为 PR checklist。

### 反过度抽象红线（对照 CLAUDE.md IMPORTANT）
- **命名**：禁止 `AbstractXxx/XxxFactory/XxxManager/IXxx/XxxService/doProcessXxxHandler`。用 `player/enemy/spawn/hp/atk/crit/loot/node/projectile/buff/tick/draw`。模块名说人话（`combat.lua` 不叫 `CombatSystemManager`）。
- **目录**：禁止 `controllers/services/models/utils/helpers/interfaces/`。`utils` 垃圾桶名禁用。
- **抽象**：单一实现不造接口/策略/抽象基类。activity 的 4 种 kind、enemy 的 arch、skill 的 effect 一律**数据表 + 字符串分发**，不升级成多态类继承树。
- **第一期不引 event 总线**；不引 json/serpent；不做 observable/数据绑定/ViewModel 类。

---

## 3. UI / helium 决策 + 主界面重设计 + 蓝量方案

### 3.1 决策：**不引 helium，不复用宿主 FlexLove，自研单文件 `ui.lua`**

**不引 helium 的理由（已删除不实论据，只留站得住的）：**
1. **范式错配**：helium 是 retained-mode + 每个元素 GPU canvas 原子缓存；本游戏 immediate-mode + 每帧动态数值（HP/经验/箭数/伤害跳字），缓存反成负担，且主战斗画面（火柴人/抛射物/粒子）无论如何要继续手画 → 必然出现两套渲染范式并存。
2. **handler 注入跨会话污染（最硬）**：helium `require` 时在 `core/input.lua` 顶层 monkeypatch `love.handlers`。而 StoneGate loader 退出时清 `package.loaded`（loader:276-280），**二次启动重新 require 会再次包裹 handler**，存在跨会话 handler 链污染。
3. **缩放无援**：helium 不认 480×800 / sw,sh，缩放要全程手动，抵消其本地坐标系优势。
4. **停更 legacy**：最后 release 2021-06。
5. **违反根 CLAUDE.md**：引入 ~1700 行带 canvas 图集的框架，背离"少依赖/单文件能跑"。

> **已删除的不实论据**：原研究称"触摸→鼠标模拟会丢多点/手势 id 损害手感"。**经核验不成立**——main.lua:1774-1776 的 `touchpressed/moved/released` 全部**丢弃 id**，游戏本就是单点输入，背包拖拽 vs 地区滚动靠 `drag`/`region_drag` 两个**互斥状态变量**区分，不靠触点 id。触摸→鼠标模拟对本游戏**零损害**。结论不变，但理由表只留真的。

**不复用宿主 FlexLove 的澄清（研究遗漏，此处补上）：**
StoneGate 宿主 shell 自身用 `src/FlexLove.lua`（69KB 响应式 UI 库）。但它是**宿主依赖，不随 quiver 的 .love 打包**（.love 是独立只读挂载包）。挂载运行下 loader 把宿主 require path 追加在后（loader:143-146），`require('FlexLove')` 理论上可能命中宿主路径；但 **standalone 跑 `quiver.love` 必然 require 不到**。为保证两种运行方式行为一致、且不把游戏耦合到宿主，**不复用 FlexLove**。自研 `ui.lua` 随 `*.lua` 打进 .love，两种模式零分支。

### 3.2 自研 `ui.lua` 最小 API（~200-300 行，零依赖，immediate-mode）
不是"框架"，是把现有手画工具收成一个带命中检测的小工具箱，复用 `setc/rrect/panel/button/bar/ring/icon_*`，原生支持 touch 与 sw/sh。

```
-- 每帧
ui.begin(mx,my)                              -- 由 touch/mouse 回调喂入当前指针（屏幕坐标），清本帧命中区
ui.set_pointer_down(b) / ui.set_pointer_up()

-- 布局（轻，坐标在设计空间，内部统一过 sx/sy）
ui.col(x,y,w,gap):next(h) -> x,y,w,h         -- 游标，不做 flex/grid 仪式
ui.scroll(id,x,y,w,h, content_h, fn)         -- 滚动视口：内部 setScissor + 维护 ui.scrolls[id].off

-- 控件（返回是否本帧被点击/被选）
ui.panel(x,y,w,h,fill,border)
ui.button(id,x,y,w,h,label,col,enabled) -> clicked      -- release 帧返回 true
ui.bar(x,y,w,h,frac,col,label)                          -- HP/弹药/经验/ATB
ui.list(id,x,y,w,h,items,row_h,draw_row) -> clicked_index
ui.cell(id,x,y,s,item,draggable) -> {clicked,drag_started}
ui.avatar_card(x,y,w,h,player)                          -- 头像卡：圆头像+HP条+弹药条+经验条

-- 事件（贴合现有单 press 模型，不另起监听体系）
ui.drag_begin(id,item) / ui.dragging() / ui.drop_target(id) -> bool   -- 原样搬现有 drag 三段 + DRAG_THRESH
```
迁移是对现有 `draw_*/press` 的**薄封装**，可分阶段：阶段A 收口 `button/bar/panel`；阶段B 收口 `list/scroll`；阶段C 收口 `cell/drag`。

### 3.3 主 HUD 重设计（设计坐标 480×800）

```
=== 主 HUD（战斗中）===
┌────────────────────────────────────────────┐ y=0
│ ┌──────┐ 弓箭手            Lv 12   [🪙 1840]│  角色卡(8,8,200,62) + 右上资源(x=w-92)
│ │ /o\  │ HP ▓▓▓▓▓▓▓▓░░ 312/360            │  HP  (78,26,110,9) good 9px 最粗
│ │ /|\ 12│ 弹药▓▓▓▓▓▓░░░ iron 86           │  弹药(78,38,110,7) 档色 7px（见3.4）
│ └──────┘ XP ▓▓▓░░░░░░░                     │  XP  (78,49,110,6) xp蓝 6px 最细
│                              [➹ iron 86]   │  toast 在 y=74 之下淡出，不压资源区
│            (火柴弓手)        ●敌 Lv12 幽魂   │
│   你 hp▓▓▓▓▓▓░  atb▓▓░       ▓▓▓▓▓░ hp     │
│        [➹][⚡][⇶][✚]  技能栏(冷却环 ring)    │  ← ATB蓄势条留在战斗区原位，不上 HUD
│ ● 战斗 · 晨曦绿野            (活动胶囊)        │ y=h-78  group色点+活动名+关键即时数
│┌────┐┌────┐┌────┐┌────┐┌────┐               │ y=h-46  入口按钮(图标在上/文字在下)
││ ▴  ││ ➹  ││ 🎒 ││ 🛡 ││ ⚑  │               │  有红点提醒画右上角点
││活动││技能││背包││装备││地区│               │
│└────┘└────┘└────┘└────┘└────┘               │
└────────────────────────────────────────────┘ y=800
```
> **布局微调（采纳评审 minor）**：角色卡宽度从 170 放到 **200**（头像右侧可用宽 200-78=122px），HP bar label 用短格式（仅当前值或 `312/360`），资源区起点右移到 `x=w-92`。标注"需首轮 luac + 截图后微调"，不阻塞落地。
> **头像实操**：在 `setScissor(8,8,54,54)` 裁剪区内 `draw_archer`，脚落框外只露头+弓臂；左下角叠等级徽章圆。

### 3.4 蓝量 / 第二条资源条决策：**做"弹药条"，不做"蓄势条"，不做真法力**（采纳评审 major 修正）
- **真法力（否）**：要改 SKILLS 表 + cast_skill 轮转 + recalc + 平衡，本环境无法实机调平衡，风险最高。
- **蓄势条 = `player.atb`（否）**：`player.atb` 每帧 0→1→瞬清（main.lua:752-753），高攻速下 HUD 常驻位会变成**高频抖动的进度条**，视觉噪音大，反比纯展示更糟。
- **【推荐·采用】弹药条**：`frac = 当前箭档总数 / 该档容量上限`。**慢变量、不抖**，箭矢是真实的第二条战力腿（recalc 已有 `arrow_tier`/`ammo_cap`，main.lua:367-370）。颜色用 `arrow_tier.color`，标"弹药"。零数据表改动、零平衡风险、第一阶段就能上。ATB 蓄势可视化降级保留在**战斗区原有小条**（main.lua:1002 已有），不上 HUD。

### 3.5 各面板增量（几何沿用现有 `*_rect`，不动命中坐标）
- **通用**：标题栏加右上角 28×28 **X 关闭键**（press 对应分支加一次 hit）；选中态加左侧 3px 彩色竖条作分类语言。
- **背包**：顶部加"全部/材料/箭矢/装备/消耗"筛选 tab——**仅降非当前类透明度(0.4)，不重排**（零风险，不动拖拽坐标）。装备 tooltip 加"与当前装备对比 ↑绿/↓红 gear_score 差值"（已有 `gear_score`）。
- **装备**：底部属性卡把 **DPS 放大为主数字**（font_med + gold）。
- **活动**：每行加活动图标；加速按钮内嵌 `icon_coin`；进行中行用 `ring` 显示职业经验进度。
- **技能**：顶部加"已学技能轮转预览"小图标条（按 prio 顺序），解决"为什么放这个技能"的可见性。
- **地区**：卡片加推荐度（区间内绿勾 / 偏低红"偏难" / 远高灰"已轻松"）。
- **制造**（在 `draw_fletch` 内）：缺料把缺的材料 chip 标红描边。

---

## 4. 存档系统

### 4.1 存什么 / 不存什么（按 init() + recalc() 真实字段，已核验）
**必存（player 持久"账本"）**：
- `level, xp`（`xp_next` 可重算）
- `base_str, base_agi, base_sta`（升级累加的根；**绝不存** recalc 衍生的 str/agi/sta/atk_*/dps/max_hp）
- `gold`
- `hp`（当前血；`max_hp` 不存，recalc 重算）
- `equip`（slot→gear 整表，纯数据可直存）
- `inv[1..24]`、`ammo[]`（**稀疏存，见 4.2 坑**；`ammo_cap` 不存，recalc 由 quiver.ammo_slots 算）
- `skill = {woodcut={lvl,xp}, mining={...}, herb={...}}`（采集职业）
- `craft = {lvl, xp}`、`craft_bp`（字符串 id）、`craft_prog`（可选）
- `bp_known = {[id]=true}`、`skills = {"shoot",...}`（已学技能 id 数组）

**必存（模块级）**：`activity`（字符串）、`region.id`（**存 id，非整表**——它是 REGIONS 元素引用）、`stage`。

**明确不存**：所有 recalc 衍生（str/atk_*/dps/max_hp/ammo_cap/`arrow_tier`）；`craft_target`/`player.arrow_tier`（数据表引用）；`gather_node`/`cd`/`buffs`/`cast_flash`/`atb`/`enemy`（瞬时）；`floats/particles/projectiles/toast/result_banner/panel_open/drag/region_drag/region_scroll/swing/shake/t_accum`（init 默认重建）。
**口诀**：只存 `base_*` 与"账本"，推导态交给 `recalc()`，瞬时态交给 init/状态机重建。**凡指向数据表元素的引用一律只存 id，加载查回。**

### 4.2 序列化器（手写 table→Lua 字面量，不引 json）
数据全是纯 Lua 表，序列化成 `return {...}` 源码、`love.filesystem.load + pcall` 反序列化最地道。数字整数走 `%d`、小数走 `%.6g`（防 locale 逗号/超长尾巴）；字符串 `%q`。

**关键坑（采纳评审 major，固化为契约）**：定长数组中间有 nil（inv/ammo 格子可空）时 `ipairs` 截断会丢后续物品。**因此**：
- `save` 前：`inv`/`ammo` 各跑 `to_sparse()` → `{[i]=item}` 稀疏表。
- `load` 后：`rebuild_fixed(BAG_SLOTS)` 循环 `1..BAG_SLOTS` 补 nil。
- **test 必须覆盖"第2格空、第1/3格有物"的空洞 round-trip**，验证 c 不丢。

### 4.3 落点：挂载 vs standalone（零分支）
- 单一常量 `SAVE_FILE = "quiver/save.lua"`，全程 `love.filesystem.read/write`（**不用 io.open 拼绝对路径**——那是 loader 跨沙盒的特权写法）。
- 挂载下落在 StoneGate save dir 的 `quiver/` 子目录；standalone 下落在 `quiver_proto` save dir 的 `quiver/` 子目录——两种模式代码零分支，love.filesystem 自动用当前进程 save dir，命名空间隔离防与 `stonegate.log`/其它游戏冲突。
- 游戏内日志写 `quiver/quiver.log`，**绝不碰 `stonegate.log`**（loader 自己用裸 io.open 写它，loader:70）。

### 4.4 触发与加载（time 时序契约，采纳评审 blocker）
**保存触发**：脏标记 `save_dirty=true`（升级/掉落装备/切活动/切地区/学技能/学图谱/制造完成/采集完成）+ `update()` 内 **10~15s 节流** `do_save` + **`love.quit` 强存**。
> **`love.quit` 必须在 `main.lua` 顶层（chunk 执行期）定义**——loader 在 `pcall(chunk)` 之后才捕获回调快照（loader 捕获在 love.load 之前），延迟到 love.load 内异步赋值则不在快照里，退出存档静默丢失。`test_headless` 须断言：chunk 加载后 `type(love.quit)=='function'`。

**加载流程**（替换 love.load 末尾的无条件 `init()`）：
```
function love.load()
  ...建字体/算 sw,sh...
  if not load_game() then init() end   -- 有档加载，无档/坏档回退全新开局
end
```
`load_game()` 步骤（**全程 pcall**，任何失败 return false → init()，绝不让坏档崩启动）：
1. `getInfo(SAVE_FILE)` 无则 return false。
2. `love.filesystem.load(SAVE_FILE)` 失败 return false。
3. `pcall(chunk)`；非 table return false。
4. `migrate(data)`；失败 return false。
5. **先 `init()`** 铺完整默认结构（新增字段不为 nil 的兜底）→ 用 data 覆盖 player 持久字段、activity、stage、`region = REGIONS 按 id 查`（查不到回 REGIONS[1]）。
6. 重建 `inv/ammo` 定长补 nil；`craft_bp` 校验 BP[id] 否则回 "wood"；`bp_known/skills` 过滤掉当前表已不存在的 id（防删条目崩）。
7. 清瞬时态：`gather_node=nil; cd={}; buffs={}; cast_flash={}; atb=0; enemy=nil`。
8. **`hp` 必须在 `recalc()` 之前赋好**（recalc 有 `if hp==nil or hp>max_hp then hp=max_hp`，main.lua:364）→ 然后 `recalc()`。

### 4.5 版本迁移
存档带 `version` 字段。`migrate(data)`：缺失或 `> SAVE_VERSION` → 当不兼容 return nil → 回 init()；否则 `while v<SAVE_VERSION do upgraders[v](data); v=v+1 end`。两道防线胜过堆 migration：(1) "先 init 再覆盖"让加字段天然兼容；(2) 加载按现有表过滤校验 id 挡住"引用已删条目"。第一期只有 v1，upgraders 空，框架先就位。约定：每改 player 持久结构/数据表 id，`SAVE_VERSION+1` 并补一个 upgrader（哪怕为空）。

---

## 5. 分阶段实施路线

> 每阶段独立可跑、可回退；推进门槛 = `luac -p` 全过 + `test_headless.lua` 不崩 + 断言通过。**先做不破坏可玩性的地基。**

| 阶段 | 内容 | 验收点 |
|---|---|---|
| **0（硬前置）** | 扩展 `test_headless.lua`：①给 mock love 加 `filesystem.{write,read,getInfo,load,createDirectory,append}` 内存假实现；②设 `package.path` 让拆出的 `quiver/` 子模块 require 可解析；③加 save→重置 player→load→断言 `level/gold/inv计数/equip` 一致的用例（**含空洞 inv**）；④断言 chunk 加载后 `type(love.quit)=='function'`。 | 无重构，仅 harness 增强；现有冒烟仍 SMOKE OK。**没有这步，后续"可验证"是空话。** |
| **1** | 抽全部静态表到**单个** `data.lua`（不细拆五文件，避免 ARROWS←BLUEPRINTS、REGIONS←ENEMY_ARCH 的文件间 require 顺序坑）。零行为变化。 | luac 过 + 冒烟 SMOKE OK，行为零变化。 |
| **2** | 抽 `base/screen.lua` + `base/draw.lua`（渲染原语 + icon_* + 字体）+ `base/assets.lua`。draw 函数保持无状态。 | 冒烟 SMOKE OK，画面逻辑等价。 |
| **3** | `base/save.lua` + `base/log.lua` + 在 main.lua 顶层加 `love.quit` + load_game/触发点/migrate 框架。**独立新增，可早做。** | 阶段0 的 save round-trip 断言通过；空洞 inv 用例通过。 |
| **4** | 新增 `ui.lua` + 逐个析出 `view/*`（先 hud 落地需求1 主界面 + 弹药条；再 bag/equip/region/activity/skills/tooltip）。每析出一个面板单独验。 | 每面板析出后冒烟 SMOKE OK；press 路由等价。 |
| **5** | `fx.lua` + `core/state.lua` + `core/input.lua` + `sys/*` 下沉（progression/inventory/combat/gather/craft/regions）。打断前向声明。 | 全量冒烟 SMOKE OK；依赖图无环（PR checklist）。 |

每阶段 PR 独立合并；任一阶段失败可单独回退而不影响已落地的前序阶段。

---

## 6. 风险与回滚
1. **inv/ammo 空洞丢数据（最高）**：不处理会"装备/材料随机消失"。→ 强制 `to_sparse`/`rebuild_fixed` + 空洞 round-trip 测试。
2. **引用型字段误存**（region/craft_target/arrow_tier）→ 改数据表后脱钩崩。→ 规则：引用一律只存 id 查回。
3. **坏档崩启动**：→ `load_game` 全程 pcall，任何失败 return false → init()（总闸）。
4. **hp/recalc 顺序错**：→ hp 必在 recalc 之前赋。
5. **`love.quit` 延迟定义 → 退出存档静默丢失**：→ 顶层定义 + test 断言。
6. **挂载共享目录冲突**：→ `quiver/` 命名空间，不碰 stonegate.log。
7. **自动存节流抖动**：每帧存会卡（序列化全 inv+equip）→ 脏标记 + 10~15s 节流 + quit 强存。
8. **数字精度/locale**：→ 整数 `%d`、小数 `%.6g`。
9. **验证手段受限**：无法实机 → 阶段0 harness 是一切前提。

**回滚策略**：分阶段 = 分 PR，每阶段产物在 `luac + 冒烟` 绿之前不合并；新分层文件与旧 main.lua 在过渡期可并存，单阶段失败 `git revert` 该 PR 即可，已落地阶段不受影响。

---

## 7. 需要玩家拍板的关键决策（≤4，带推荐）

1. **第二条资源条（你要的"蓝量/MP"）做成什么？**
   **推荐：做"弹药条"**（当前箭档总数/容量上限，慢变量不抖、复用 arrow_tier/ammo_cap、零平衡风险），而非绑 `player.atb` 的"蓄势条"（高攻速下 HUD 抖动），更非真法力（动 SKILLS/平衡、无法实机调）。要"蓝条"的视觉位但填弹药。

2. **接受"不引 helium、不复用宿主 FlexLove、自研 `ui.lua`"吗？**
   **推荐：接受**。helium 是停更 legacy（retained-mode + canvas 缓存 + require 时改 love.handlers），与本游戏 immediate-mode + loader 退出清 package.loaded 的契约冲突，且违背零依赖硬约束；FlexLove 是宿主依赖、standalone 跑不到。你的诉求（界面优化+信息高效+解耦）靠自研轻量 ui.lua + 三层拆分即可全部满足。

3. **认可第一期"弱 MVVM、不引 event 总线、data 先合并单文件"的尺度吗？**
   **推荐：认可**。data+sys=Model / view=immediate View / VM 退化为 view 内现读现算，不造接口/工厂/ViewModel 类；同帧顺序调用（drop_loot→gain_xp→check_skill_unlock）保持直接调用，不上发布订阅。既解耦又不过度仪式。

4. **存档自动保存策略：10~15s 节流 + 关键事件置脏 + love.quit 强存，可接受"最多丢十几秒"吗？**
   **推荐：接受**。挂机游戏掉最多 15s 进度换不卡顿是常规取舍。若要更激进的即时存，代价是序列化全 inv+equip 的偶发卡顿。

---

## 8. 玩家拍板结果 + 落地校正（v2）

**决策（用户已定）：**
1. 第二条资源条 = **真法力 / MP 系统**（覆盖原推荐的弹药条）。
2. UI = **采用 helium**（覆盖原推荐的自研 ui.lua）。
3. 架构 = 务实弱 MVVM（同推荐）。
4. 存档 = 节流自动存（同推荐）。

**helium 实机验证（本环境 lovec LÖVE 11.5，已跑）：**
- `require 'helium'` + `scene:draw/update` 跑 31 帧无报错、干净退出 → **helium 在本环境可用**。
- 但 `core/input.lua` 顶层**无防护**地 monkeypatch `love.handlers`（mousepressed/mousemoved/keys/textinput），每次 require 重新包裹 → StoneGate 退出清 `package.loaded` 后**二次启动会重复包裹**（跨会话 handler 污染）。
- helium 只挂 **mouse/键盘**，不挂 touch（移动端靠 LÖVE 的 touch→mouse 模拟，默认开）。
- **缓解（必做）**：游戏 `main.lua` 顶层 `love.quit` 里**恢复 `love.handlers` 原始函数**（require 前先快照）。loader 只恢复 `love.*` 回调、不管 `love.handlers`，所以游戏自己负责还原。`test_headless` 增断言：require helium 前后能拿到 handler 快照。
- **渲染范式**：helium retained-mode + 每元素 canvas 缓存；战斗场景(火柴人/抛射/粒子/跳字)继续 immediate-mode 画在 `love.draw`，helium 只画 **HUD/面板 chrome**（按钮/条/列表）。每帧变动的 HP/MP/经验数值元素需 `setCaching(false)` 或每帧喂 state 强制重绘，避免缓存停在旧值。

**MP / 法力系统设计（落地）：**
- 新增 `player.mp` / `player.max_mp`；`max_mp = 30 + level*5`（独立池，不占用力/敏/耐；不加第 4 基础属性）。
- `mp_regen = 6/秒`（战斗内外都回，update 头部 tick，封顶 max_mp）。
- `SKILLS` 每条加 `mp_cost`：普通射击=0；主动技按强度定（power 8 / double 10 / aimed 14 / poison 12 / rapid 18 / hawkeye 20 / mend 14）。
- `cast_skill`：候选技能须同时满足 **冷却就绪 且 mp≥mp_cost**；释放扣 mp。都不满足 → 普通射击(0 费)。这样 MP 是"主动技节奏"的第二资源，与冷却共同约束，不破坏现有平衡（普攻永远免费可用）。
- `recalc`：算 `max_mp`，`mp` 钳到 `[0,max_mp]`，初始/读档后补满。
- HUD 蓝条 = `mp/max_mp`。存档需持久化 `mp`（当前值）。
