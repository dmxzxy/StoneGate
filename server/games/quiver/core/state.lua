-- ============================================================================
-- core/state —— 集中持有运行态（一局游戏的当前快照）。
-- 这里的字段就是存档读写(save.snapshot/save.load)的目标根：持久账本 player + 模块级
-- activity/region/stage，加上瞬时的 enemy/projectiles 与各类 UI 覆盖态(panel_open/drag/tooltip…)。
-- 只持有数据 + 极薄访问器(open/close panel)；规则逻辑在 sys/，绘制在 view/，都来读写这里。
-- 依赖：无（只持有运行态字段 + 极薄访问器；规则在 sys/，绘制在 view/，都来读写这里）。
-- 保持在最底层、被上层引用，不 require sys/view，也不需要 data（初值都是字面量）。
-- ============================================================================

local state = {}

-- 玩家持久账本 + 衍生态（recalc 写）。init() 会整体重建为新表。
state.player = nil
-- 战斗瞬时
state.enemy = nil
state.projectiles = {}
-- 模块级进度
state.region = nil           -- 当前地区（REGIONS 元素引用；存档只存 id 查回）
state.stage = 0              -- 当前关卡推进计数
state.activity = "rest"      -- 当前挂机活动：rest|woodcut|mining|herb|fletch|combat
-- UI 覆盖态
state.panel_open = nil       -- 覆盖菜单：nil|"activity"|"bag"|"equip"|"region"|"skills"
state.result_banner = nil    -- nil|"defeat"
state.tooltip = nil          -- 物品详情：{kind=, ...}
state.drag = nil             -- 拖拽中：{from="bag"/"equip"/"ammo", slot=, item=, x=, y=, moved=}
state.region_drag = nil      -- 地区列表拖拽滚动/点选：{y0=, s0=, moved=}
state.region_scroll = 0      -- 地区列表滚动偏移
state.drawer_t = 0           -- 活动抽屉滑入进度 0..1（左侧 drawer 动画）

-- 极薄访问器（覆盖菜单开关；不做事件，只是命名清晰的赋值）
function state.open_panel(id) state.panel_open = id end
function state.close_panel() state.panel_open = nil end

return state
