-- ============================================================================
-- sys/regions —— 切区：选定一个地区即重置关卡推进与战斗/采集瞬时态。
--   地区列表的布局/绘制/滚动是 view 关注点（仍在 main，待 view 阶段下沉），不在此处。
-- 依赖：core/state + fx。数据(REGIONS/分档)在 data.lua。
-- ============================================================================
local D = require("data")
local state = require("core.state")
local fx = require("fx")

local UI = D.UI

local regions = {}

-- 切到指定地区：清关卡计数 + 敌人 + 采集节点，提示一次（行为同旧 region_release 命中分支）
function regions.select(rg)
    state.region=rg; state.stage=0; state.enemy=nil; state.player.gather_node=nil
    fx.set_toast("狩猎地："..rg.name, UI.good)
end

return regions
