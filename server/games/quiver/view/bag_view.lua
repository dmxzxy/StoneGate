-- ============================================================================
-- view/bag_view —— 背包面板：箭袋弹药行 + 6 列主背包格，可堆叠 + 图标，拖拽换位/点击看详情。
-- 提供 draw()、press(x,y)（tooltip 优先 / 返回键 / 拾起格子开始拖拽）、drag_release(x,y)（落点交换/堆叠或点击看详情）、
-- draw_drag()（拖拽中物品跟随指针）、bag_grid()/ammo_grid()/bag_cell_rect()（几何，共用）。
-- 拖拽位移判定(DRAG_THRESH)在 core/input.drag_move；这里命中坐标与原 main 完全一致。
-- 依赖：base/screen + base/draw + core/state + sys/inventory + view/items + view/tooltip + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local state = require("core.state")
local inv = require("sys.inventory")
local items = require("view.items")
local tooltip = require("view.tooltip")
local D = require("data")
local UI = D.UI
local ARROW = D.ARROW
local BAG_SLOTS = D.BAG_SLOTS

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local function hit(x,y,rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end
local setc = draw.setc
local panel, rrect = draw.panel, draw.rrect
local icon_arrow = draw.icon_arrow
local inv_swap, ammo_swap = inv.inv_swap, inv.ammo_swap
local item_color, draw_item_icon = items.item_color, items.draw_item_icon

local BAG_COLS = 6

local bag_view = {}

-- 筛选 tab（仅降非当前类透明度，不重排，零风险不动拖拽坐标）。
-- match(it) 判定某物品是否属于当前筛选；filter="all" 全亮。
local BAG_FILTERS = {
    { id="all",    name="全部" },
    { id="mat",    name="材料" },
    { id="arrow",  name="箭矢" },
    { id="gear",   name="装备" },
    { id="potion", name="消耗" },
}
-- 筛选 tab 几何（横排在标题下方、箭袋区上方的窄条）
function bag_view.filter_tab_rect(i)
    local w=love.graphics.getWidth()
    local px=sx(16); local pw=w-sx(32)
    local tw=sx(42); local gap=sx(4); local total=#BAG_FILTERS*tw+(#BAG_FILTERS-1)*gap
    local x0=px+(pw-total)/2; local y=sy(56)+sy(31)
    return x0+(i-1)*(tw+gap), y, tw, sy(17)
end
local filter_tab_rect = bag_view.filter_tab_rect

-- 物品(背包格/弹药格)是否被当前筛选点亮
local function item_dim(kind)
    local f = state.bag_filter or "all"
    if f=="all" then return false end
    return kind ~= f
end

-- 箭袋弹药格几何（一行，cap 个格）
function bag_view.ammo_grid()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112)
    local cell=sx(40); local gap=sx(6); local ax=px+sx(14); local ay=py+sy(56)
    return ax,ay,cell,gap
end
local ammo_grid = bag_view.ammo_grid

-- 背包网格几何（draw 与 press/drag 共用）
function bag_view.bag_grid()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112)
    local gap=sx(6)
    local rows=math.ceil(BAG_SLOTS/BAG_COLS)
    local gy0=py+sy(124)                      -- 标题 + 箭袋行 之下
    local bottom=py+ph-sy(48)                 -- 返回按钮上方留白
    local cw=(pw-sx(20)-gap*(BAG_COLS-1))/BAG_COLS
    local chh=(bottom-gy0-gap*(rows-1))/rows
    local cell=math.min(cw, chh)
    local gx=px+(pw-(cell*BAG_COLS+gap*(BAG_COLS-1)))/2   -- 水平居中
    return px,py,pw,ph,gx,gy0,cell,gap
end
local bag_grid = bag_view.bag_grid

-- 返回某格中心+矩形
function bag_view.bag_cell_rect(i, gx,gy,cell,gap)
    local c=(i-1)%BAG_COLS; local r=math.floor((i-1)/BAG_COLS)
    local x=gx+c*(cell+gap); local y=gy+r*(cell+gap)
    return x,y
end
local bag_cell_rect = bag_view.bag_cell_rect

function bag_view.draw()
    local sw = screen.sw
    local w,h=love.graphics.getWidth(),love.graphics.getHeight(); love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,w,h)
    local px,py,pw,ph,gx,gy,cell,gap = bag_grid(); panel(px,py,pw,ph,{0.09,0.1,0.15,0.98},UI.line,10*sw)
    love.graphics.setFont(draw.font_med); setc(UI.text); love.graphics.printf("背包",px,py+sy(8),pw,"center")
    draw.close_x(px,py,pw)

    -- 筛选 tab（仅降非当前类透明度，不重排）
    local cur_f = state.bag_filter or "all"
    for i,f in ipairs(BAG_FILTERS) do
        local tx,ty,tw,th = filter_tab_rect(i); local on=(f.id==cur_f)
        setc(on and {0.22,0.26,0.36,0.95} or {0.12,0.13,0.18,0.85}); rrect("fill",tx,ty,tw,th,5*sw)
        if on then setc(UI.btn); love.graphics.setLineWidth(math.max(1,sw)); rrect("line",tx,ty,tw,th,5*sw); love.graphics.setLineWidth(1) end
        love.graphics.setFont(draw.font_sm); setc(on and UI.text or UI.dim); love.graphics.printf(f.name, tx, ty+(th-draw.font_sm:getHeight())/2, tw, "center")
    end

    -- 箭袋区（弹药格，仅箭矢）
    setc(UI.dim); love.graphics.setFont(draw.font_sm)
    love.graphics.printf("箭袋（仅箭矢）", px, py+sy(38), pw-sx(14), "right")
    local ax,ay,acell,agap = ammo_grid()
    local dim_ammo = item_dim("arrow")
    for i=1,(state.player.ammo_cap or 0) do
        local x=ax+(i-1)*(acell+agap)
        local it=state.player.ammo[i]
        local bc = it and item_color(it) or {0.3,0.31,0.4}
        if it then panel(x,ay,acell,acell,{bc[1]*0.16,bc[2]*0.16,bc[3]*0.18,0.95},bc,6*sw)
        else panel(x,ay,acell,acell,{0.1,0.11,0.15,0.9},{0.22,0.23,0.3},6*sw) end
        if it and not (state.drag and state.drag.moved and state.drag.from=="ammo" and state.drag.slot==i) then
            love.graphics.push("all"); if dim_ammo then love.graphics.setColor(1,1,1,0.4) end
            icon_arrow(x+acell/2, ay+acell/2-sy(2), acell*0.3, D.arrow_color(it))
            setc(UI.text, dim_ammo and 0.4 or 1); love.graphics.printf(it.qty, x, ay+acell-sy(14), acell-sx(2), "right")
            love.graphics.pop()
        end
    end

    -- 主背包格（材料/装备）
    local used=0; for i=1,BAG_SLOTS do if state.player.inv[i] then used=used+1 end end
    setc(UI.dim); love.graphics.setFont(draw.font_sm); love.graphics.printf("背包  "..used.."/"..BAG_SLOTS, px, py+sy(102), pw-sx(14), "right")
    for i=1,BAG_SLOTS do
        local x,y=bag_cell_rect(i,gx,gy,cell,gap)
        local it=state.player.inv[i]
        local border = it and item_color(it) or {0.22,0.23,0.3}
        if it then panel(x,y,cell,cell,{border[1]*0.16,border[2]*0.16,border[3]*0.18,0.95},border,6*sw)
        else panel(x,y,cell,cell,{0.1,0.11,0.15,0.9},{0.2,0.21,0.27},6*sw) end
        if it and not (state.drag and state.drag.moved and state.drag.from=="bag" and state.drag.slot==i) then
            local dim = item_dim(it.kind)
            love.graphics.push("all"); if dim then love.graphics.setColor(1,1,1,0.4) end
            draw_item_icon(it, x+cell/2, y+cell/2-sy(2), cell*0.32)
            if it.qty>1 then setc(UI.text, dim and 0.4 or 1); love.graphics.setFont(draw.font_sm); love.graphics.printf(it.qty, x, y+cell-sy(15), cell-sx(3), "right") end
            love.graphics.pop()
        end
    end
    draw.button(px+pw/2-sx(60),py+ph-sy(34),sx(120),sy(28),"返回",{0.4,0.4,0.5},true)
end

-- 拖拽中的物品跟随指针（超过阈值才显示）
function bag_view.draw_drag()
    if not (state.drag and state.drag.moved and state.drag.item) then return end
    local sw = screen.sw
    local _,_,_,_,_,_,cell = bag_grid()
    local it=state.drag.item
    local norm = it
    local c=item_color(norm)
    setc(c,0.85); rrect("fill", state.drag.x-cell/2, state.drag.y-cell/2, cell, cell, 6*sw)
    draw_item_icon(norm, state.drag.x, state.drag.y-sy(2), cell*0.3)
    if it.qty>1 then setc(UI.text); love.graphics.setFont(draw.font_sm); love.graphics.printf(it.qty, state.drag.x-cell/2, state.drag.y+cell/2-sy(16), cell-sx(4), "right") end
end

-- 按下：tooltip 优先 / 返回键关闭 / 拾起箭袋或背包格开始拖拽
function bag_view.press(x,y)
    if state.tooltip then tooltip.tooltip_press(x,y); return true end
    local px,py,pw,ph,gx,gy,cell,gap = bag_grid()
    if draw.hit_close_x(x,y,px,py,pw) then state.panel_open=nil; return true end
    if hit(x,y,px+pw/2-sx(60),py+ph-sy(34),sx(120),sy(28)) then state.panel_open=nil; return true end
    -- 筛选 tab 点击（仅切视觉过滤，不动物品）
    for i,f in ipairs(BAG_FILTERS) do
        local tx,ty,tw,th = filter_tab_rect(i)
        if hit(x,y,tx,ty,tw,th) then state.bag_filter=f.id; return true end
    end
    -- 箭袋弹药格 → 拾起
    local ax,ay,acell,agap = ammo_grid()
    for i=1,(state.player.ammo_cap or 0) do
        local cx=ax+(i-1)*(acell+agap)
        if hit(x,y,cx,ay,acell,acell) and state.player.ammo[i] then
            state.drag={ from="ammo", slot=i, item=state.player.ammo[i], x=x, y=y, sx0=x, sy0=y, moved=false }; return true
        end
    end
    -- 主背包格 → 拾起
    for i=1,BAG_SLOTS do
        local cx,cyy=bag_cell_rect(i,gx,gy,cell,gap)
        if hit(x,y,cx,cyy,cell,cell) and state.player.inv[i] then
            state.drag={ from="bag", slot=i, item=state.player.inv[i], x=x, y=y, sx0=x, sy0=y, moved=false }; return true
        end
    end
    return true
end

-- 拖拽放下：bag↔bag、ammo↔ammo 内部交换/堆叠；跨类拒绝；未移动=点击看详情
function bag_view.drag_release(x,y)
    if not state.drag then return end
    local d=state.drag; state.drag=nil
    local px,py,pw,ph,gx,gy,cell,gap = bag_grid()
    local ax,ay,acell,agap = ammo_grid()
    -- 找落点（先箭袋后主背包）
    local tgrid,tslot=nil,nil
    for i=1,(state.player.ammo_cap or 0) do local cx=ax+(i-1)*(acell+agap); if hit(x,y,cx,ay,acell,acell) then tgrid="ammo"; tslot=i; break end end
    if not tgrid then for i=1,BAG_SLOTS do local cx,cyy=bag_cell_rect(i,gx,gy,cell,gap); if hit(x,y,cx,cyy,cell,cell) then tgrid="bag"; tslot=i; break end end end
    -- 未移动且落回原格 → 点击看详情
    if not d.moved and tgrid==d.from and tslot==d.slot then
        if d.from=="ammo" then local it=state.player.ammo[d.slot]; if it then state.tooltip={kind="arrow", head=it.head, element=it.element, feather=it.feather} end
        else local it=state.player.inv[d.slot]; if it then
            if it.kind=="gear" then state.tooltip={ kind="gear", g=it.gear, src="bag", slot=d.slot } else state.tooltip={ kind=it.kind, id=it.id } end end
        end
        return
    end
    -- 同类网格内移动/交换；跨网格(箭矢↔背包)拒绝
    if tgrid and tgrid==d.from then
        if d.from=="ammo" then ammo_swap(d.slot,tslot) else inv_swap(d.slot,tslot) end
    end
end

return bag_view
