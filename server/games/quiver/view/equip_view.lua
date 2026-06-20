-- ============================================================================
-- view/equip_view —— 装备面板：中央火柴人 + 左右两列槽位格 + 底部属性卡(基础/衍生)。
-- 提供 draw()、hit(x,y)（tooltip 优先 / 返回键 / 点槽位看详情）、equip_cell_rect(slot)（几何，共用）。
-- 依赖：base/screen + base/draw + core/state + sys/inventory(gear_color) + view/tooltip + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local state = require("core.state")
local inv = require("sys.inventory")
local tooltip = require("view.tooltip")
local D = require("data")
local UI = D.UI
local SLOTS, SLOT_INFO = D.SLOTS, D.SLOT_INFO
local EQUIP_POS = D.EQUIP_POS
local ATTRS, ATTR_NAME, ATTR_COLOR = D.ATTRS, D.ATTR_NAME, D.ATTR_COLOR

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local function hit(x,y,rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end
local setc = draw.setc
local panel, button = draw.panel, draw.button
local icon_kind, draw_archer = draw.icon_kind, draw.draw_archer
local gear_color = inv.gear_color

local equip_view = {}

-- 装备格几何（draw 与 hit 共用）
function equip_view.equip_cell_rect(slot)
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112)
    local cell=sx(52); local gap=sy(10); local startY=py+sy(48)
    local p=EQUIP_POS[slot]
    local x = (p.col=="L") and (px+sx(20)) or (px+pw-sx(20)-cell)
    local y = startY + (p.idx-1)*(cell+gap)
    return x,y,cell
end
local equip_cell_rect = equip_view.equip_cell_rect

function equip_view.draw()
    local sw = screen.sw
    local w,h=love.graphics.getWidth(),love.graphics.getHeight(); love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,w,h)
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112); panel(px,py,pw,ph,{0.09,0.1,0.15,0.98},UI.line,10*sw)
    love.graphics.setFont(draw.font_med); setc(UI.text); love.graphics.printf("装备",px,py+sy(8),pw,"center")
    draw.close_x(px,py,pw)

    -- 中间角色火柴人
    local _,fy0,cell = equip_cell_rect("feet")  -- 用左列最后一格的 y 作为脚部参考
    draw_archer(px+pw/2, fy0+cell, "bow")

    -- 槽位格子（左列防具 / 右列武器首饰）
    for _,slot in ipairs(SLOTS) do
        local x,y,c = equip_cell_rect(slot); local g=state.player.equip[slot]; local info=SLOT_INFO[slot]
        local rc = g and gear_color(g) or {0.3,0.31,0.38}
        if g then panel(x,y,c,c,{rc[1]*0.16,rc[2]*0.16,rc[3]*0.18,0.95},rc,6*sw)
        else panel(x,y,c,c,{0.1,0.11,0.15,0.92},{0.22,0.23,0.3},6*sw) end
        if g then
            icon_kind(info.kind, x+c/2, y+c/2-sy(2), c*0.32, rc)
        else
            icon_kind(info.kind, x+c/2, y+c/2-sy(4), c*0.3, {0.38,0.39,0.46})
            setc({0.5,0.51,0.58}); love.graphics.setFont(draw.font_sm); love.graphics.printf(info.name, x, y+c-sy(15), c, "center")
        end
    end

    -- 底部属性卡：基础属性(力/敏/耐) 与 衍生属性(由基础+装备换算) 分区，标注单位
    local cardh=sy(138); local cardy=py+ph-sy(40)-cardh
    panel(px+sx(10),cardy,pw-sx(20),cardh,{0.13,0.15,0.22,0.97},UI.line,7*sw)
    local lx=px+sx(22); local rx=px+pw/2+sx(10); local innerw=pw-sx(44)
    local function kv(x,y,label,val,vcol)
        setc(UI.dim); love.graphics.setFont(draw.font_sm); love.graphics.print(label, x, y)
        setc(vcol or UI.text); love.graphics.print(tostring(val), x+sx(58), y)
    end
    local yy=cardy+sy(9)
    -- 基础属性（升级与装备提供）
    setc(UI.dim); love.graphics.setFont(draw.font_sm); love.graphics.print("基础属性", lx, yy); yy=yy+sy(19)
    local bw=innerw/3
    for j,k in ipairs(ATTRS) do
        setc(ATTR_COLOR[k]); love.graphics.setFont(draw.font); love.graphics.print(ATTR_NAME[k], lx+(j-1)*bw, yy)
        setc(UI.text); love.graphics.print(state.player[k], lx+(j-1)*bw+sx(40), yy)
    end
    yy=yy+sy(26)
    setc(UI.line); love.graphics.rectangle("fill", lx, yy, innerw, math.max(1,1*screen.sh)); yy=yy+sy(7)
    -- 衍生属性（由基础属性 + 装备换算而来）
    setc(UI.dim); love.graphics.setFont(draw.font_sm); love.graphics.print("衍生属性（基础属性 + 装备换算）", lx, yy); yy=yy+sy(19)
    kv(lx, yy, "攻击力", math.floor(state.player.atk_min).."~"..math.floor(state.player.atk_max))
    kv(rx, yy, "攻速", string.format("%.2f 秒/次", 1/math.max(0.01,state.player.atk_speed))); yy=yy+sy(20)
    kv(lx, yy, "暴击率", math.floor(state.player.crit*100).."%")
    kv(rx, yy, "生命", state.player.max_hp); yy=yy+sy(20)
    kv(lx, yy, "护甲", state.player.armor)
    -- 每秒伤害：放大为主数字（font_med + 金色），右侧醒目
    setc(UI.dim); love.graphics.setFont(draw.font_sm); love.graphics.print("每秒伤害", rx, yy)
    setc(UI.gold); love.graphics.setFont(draw.font_med); love.graphics.print(math.floor(state.player.dps), rx+sx(58), yy-sy(4))

    button(px+pw/2-sx(60),py+ph-sy(32),sx(120),sy(26),"返回",{0.4,0.4,0.5},true)
end

function equip_view.hit(x,y)
    if state.tooltip then tooltip.tooltip_press(x,y); return true end
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112)
    if draw.hit_close_x(x,y,px,py,pw) then state.panel_open=nil; return true end
    if hit(x,y,px+pw/2-sx(60),py+ph-sy(34),sx(120),sy(28)) then state.panel_open=nil; return true end
    for _,slot in ipairs(SLOTS) do
        local ex,ey,ec = equip_cell_rect(slot); local g=state.player.equip[slot]
        if g and hit(x,y,ex,ey,ec,ec) then state.tooltip={ kind="gear", g=g, src="equip", slot=slot }; return true end
    end
    return true
end

return equip_view
