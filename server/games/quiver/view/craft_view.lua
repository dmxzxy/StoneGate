-- ============================================================================
-- view/craft_view —— 制造场景(draw_fletch)：弓手做工 + 当前图谱产出/缺料 + 下半屏已知图谱列表。
-- 提供 draw()、hit(x,y)->handled（点选下半屏图谱卡=切换并持续制造，属无面板场景内交互）、
-- craft_known_list/craft_card_rect（几何，draw 与 hit 共用）。
-- 依赖：base/screen + base/draw + core/state + fx + sys/inventory + sys/craft + view/items + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local state = require("core.state")
local fx = require("fx")
local inv = require("sys.inventory")
local craft = require("sys.craft")
local items = require("view.items")
local D = require("data")
local UI = D.UI
local BLUEPRINTS = D.BLUEPRINTS
local MAT_NAME = D.MAT_NAME
local DESIGN_H = D.DESIGN_H

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local setc = draw.setc
local panel, bar, mat_chip = draw.panel, draw.bar, draw.mat_chip
local rrect = draw.rrect
local draw_archer = draw.draw_archer
local inv_count, ammo_count = inv.inv_count, inv.ammo_count
local can_craft = craft.can_craft
local draw_item_icon = items.draw_item_icon

local craft_view = {}

-- 图谱产物图标：箭矢按三轴(head/element/feather)派生，其它按 id。
local function out_icon_item(o)
    if o.kind=="arrow" then return { kind="arrow", head=o.head, element=o.element, feather=o.feather } end
    return { kind=o.kind, id=o.id }
end
-- 图谱展示色：箭矢用三轴派生色，其它用 out.color。
local function bp_color(b)
    if b.out.kind=="arrow" then return D.arrow_color(b.out) end
    return b.out.color or {0.6,0.7,0.85}
end

-- 制造图谱卡片几何（draw 与 hit 共用）：下半屏竖排，只列已知图谱
function craft_view.craft_known_list()
    local list={}; for _,b in ipairs(BLUEPRINTS) do if state.player.bp_known[b.id] then list[#list+1]=b end end; return list
end
local craft_known_list = craft_view.craft_known_list

function craft_view.craft_card_rect(slot)
    local w=love.graphics.getWidth(); local ch,gap=sy(34),sy(6); local top=DESIGN_H*0.55*screen.sh
    return sx(20), top+(slot-1)*(ch+gap), w-sx(40), ch
end
local craft_card_rect = craft_view.craft_card_rect

function craft_view.draw()
    local sw, sh = screen.sw, screen.sh
    local px,py = sx(80), DESIGN_H*0.40*sh
    draw_archer(px,py,"chop",fx.swing*6)
    setc({0.4,0.3,0.2}); love.graphics.rectangle("fill",px+sx(22),py-sy(2),sx(70),sy(10),3*sw)
    local bp = state.player.craft_target
    local cx = love.graphics.getWidth()/2
    if bp and state.player.bp_known[bp.id] and can_craft(bp) then
        -- 正在制造：产出图标(产物色) + 库存 + 进度
        local o=bp.out
        draw_item_icon(out_icon_item(o), cx-sx(40), py-sy(92), sx(16))
        local have = (o.kind=="arrow") and ammo_count(o.head) or inv_count(o.kind,o.id)
        love.graphics.setFont(draw.font_big); setc(o.color or {0.8,0.8,0.85}); love.graphics.print(have, cx-sx(10), py-sy(106))
        love.graphics.setFont(draw.font_sm); setc(UI.dim); love.graphics.printf("正在制造 "..bp.name, 0, py-sy(116), love.graphics.getWidth(), "center")
        bar(cx-sx(100), py-sy(70), sx(200), sy(12), state.player.craft_prog or 0, o.color or {0.6,0.7,0.85})
    elseif bp then
        -- 缺料：灰产物 + 所需材料(够亮/缺红)
        draw_item_icon(out_icon_item(bp.out), cx, py-sy(92), sx(16))
        love.graphics.setFont(draw.font_sm); setc(UI.bad); love.graphics.printf("材料不足："..bp.name, 0, py-sy(116), love.graphics.getWidth(), "center")
        local i=0; for m,n in pairs(bp.cost) do local mx=cx-sx(40)+i*sx(46); i=i+1
            local ok=inv_count("mat",m)>=n
            mat_chip(m, mx, py-sy(70), sx(7))
            if not ok then setc(UI.bad); love.graphics.setLineWidth(math.max(1,2*screen.sw)); rrect("line", mx-sx(8), py-sy(70)-sx(8), sx(16), sx(16), sx(3)); love.graphics.setLineWidth(1) end  -- 缺料红描边
            setc(ok and UI.text or UI.bad); love.graphics.setFont(draw.font_sm); love.graphics.print(inv_count("mat",m).."/"..n, mx-sx(6), py-sy(62))
        end
    end
    -- 下半屏：所有已知图谱，点选即切换并持续制造（材料用尽自动停）
    love.graphics.setFont(draw.font_sm); setc(UI.dim); love.graphics.printf("图谱（点选制造）", sx(20), DESIGN_H*0.55*sh-sy(18), love.graphics.getWidth()-sx(40), "left")
    for slot,b in ipairs(craft_known_list()) do
        local x,y,cw,ch = craft_card_rect(slot); local sel=(state.player.craft_bp==b.id); local oc=bp_color(b)
        panel(x,y,cw,ch, sel and {oc[1]*0.22,oc[2]*0.22,oc[3]*0.24,0.97} or {0.11,0.12,0.17,0.95}, sel and oc or UI.line, 6*sw)
        draw_item_icon(out_icon_item(b.out), x+sx(18), y+ch/2, sx(11))
        setc(UI.text); love.graphics.setFont(draw.font_sm); love.graphics.print(b.name.."  x"..b.out.qty, x+sx(36), y+sy(4))
        local cxx=x+sx(36); local can=true
        for m,n in pairs(b.cost) do
            local ok=inv_count("mat",m)>=n; if not ok then can=false end
            mat_chip(m, cxx+sx(5), y+ch-sy(10), sx(5))
            if not ok then setc(UI.bad); love.graphics.setLineWidth(math.max(1,sx(1.6))); rrect("line", cxx+sx(5)-sx(6), y+ch-sy(10)-sx(6), sx(12), sx(12), sx(2.5)); love.graphics.setLineWidth(1) end  -- 缺料红描边
            setc(ok and UI.dim or UI.bad); love.graphics.setFont(draw.font_sm); love.graphics.print(n, cxx+sx(12), y+ch-sy(17)); cxx=cxx+sx(30)
        end
        if not can then setc(UI.bad); love.graphics.setFont(draw.font_sm); love.graphics.printf("缺料", x, y+sy(5), cw-sx(8), "right") end
    end
end

local function hit(x,y,rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end

-- 无面板场景内交互：点下半屏图谱卡 = 选图谱并持续制造
function craft_view.hit(x,y)
    for slot,b in ipairs(craft_known_list()) do
        local cxr,cyr,cwr,chr = craft_card_rect(slot)
        if hit(x,y,cxr,cyr,cwr,chr) then state.player.craft_bp=b.id; state.player.craft_prog=0; state.player.craft_stopped=nil; return true end
    end
    return false
end

return craft_view
