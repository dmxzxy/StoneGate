-- ============================================================================
-- view/items —— 物品图标/颜色分发（材料/箭矢/药剂/装备）。
-- 被 bag_view / craft_view / 拖拽渲染共用。依赖 base/draw 画图标 + data 颜色表 +
-- sys/inventory 的 gear_color（装备稀有度色由游戏逻辑给）。放在 view 层而非 base/draw，
-- 因为它要 require 游戏逻辑(gear_color)，而 base/draw 不许碰游戏态。
-- ============================================================================
local draw = require("base.draw")
local inv = require("sys.inventory")
local D = require("data")
local ARROW = D.ARROW
local POT_COLOR = D.POT_COLOR
local MAT_COLOR = D.MAT_COLOR
local SLOT_INFO = D.SLOT_INFO
local UI = D.UI
local icon_mat, icon_arrow, icon_potion, icon_kind = draw.icon_mat, draw.icon_arrow, draw.icon_potion, draw.icon_kind

local items = {}

function items.item_color(it)
    if it.kind=="gear" then return inv.gear_color(it.gear)
    elseif it.kind=="arrow" then return D.arrow_color(it)
    elseif it.kind=="potion" then return POT_COLOR[it.id] or UI.dim
    else return MAT_COLOR[it.id] or UI.dim end
end

function items.draw_item_icon(it, cx, cy, s)
    if it.kind=="mat" then icon_mat(it.id, cx, cy, s)
    elseif it.kind=="arrow" then icon_arrow(cx, cy, s, D.arrow_color(it))
    elseif it.kind=="potion" then icon_potion(cx, cy, s, POT_COLOR[it.id])
    else icon_kind(SLOT_INFO[it.gear.slot].kind, cx, cy, s, inv.gear_color(it.gear)) end
end

return items
