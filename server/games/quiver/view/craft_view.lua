-- ============================================================================
-- view/craft_view —— 制造/锻造场景(像素世界)：暮色林地 + 主角 chop 做工 + 工作台(制造)/铁砧(锻造) +
--   进度；下半屏维持设计空间(480x800)像素扁平皮：当前图谱产出/缺料 + tab + 已知图谱卡列表。
-- 提供 draw()、hit(x,y)->handled（点选下半屏图谱卡=切换并持续制造）、craft_known_list/craft_card_rect。
-- 依赖：base/screen + base/draw + view/sprites + core/state + fx + sys/inventory + sys/craft + view/items + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local sprites = require("view.sprites")
local state = require("core.state")
local fx = require("fx")
local inv = require("sys.inventory")
local craft = require("sys.craft")
local items = require("view.items")
local D = require("data")
local UI = D.UI
local BLUEPRINTS = D.BLUEPRINTS
local RAR = D.RAR
local SLOT_INFO = D.SLOT_INFO
local MAT_NAME = D.MAT_NAME
local DESIGN_H = D.DESIGN_H

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local setc = draw.setc
local panel, bar, mat_chip = draw.panel, draw.bar, draw.mat_chip
local rrect = draw.rrect
local inv_count, ammo_count = inv.inv_count, inv.ammo_count
local can_craft = craft.can_craft
local draw_item_icon = items.draw_item_icon

local craft_view = {}

-- 制造页分类 tab：制箭/材料 走 craft 职业；炼锭/造甲/造弓 走 forge 职业。
-- 选中的 tab 存 state.player.craft_tab(默认按当前活动给：forge 活动默认炼锭)。
local TABS = {
    { id="fletch", name="制箭", job=nil },
    { id="mat",    name="材料", job=nil },
    { id="ingot",  name="炼锭", job="forge" },
    { id="armor",  name="造甲", job="forge" },
    { id="bow",    name="造弓", job="forge" },
}

-- 图谱产物图标：箭矢按三轴派生，装备按目标槽 kind，其它按 id。
local function out_icon_item(o)
    if o.kind=="arrow" then return { kind="arrow", head=o.head, element=o.element, feather=o.feather } end
    if o.kind=="gear" then return { kind="mat", id="__gear__" } end   -- 占位(下方 gear 单独画)
    return { kind=o.kind, id=o.id }
end
-- 画图谱产物图标(gear 走 icon_kind 按槽类型)
local function draw_out_icon(o, cx, cy, s)
    if o.kind=="gear" then draw.icon_kind(SLOT_INFO[o.slot].kind, cx, cy, s, {0.7,0.72,0.78})
    else draw_item_icon(out_icon_item(o), cx, cy, s) end
end
-- 图谱展示色：箭矢三轴派生色，装备按其稀有度池里最高一档(展示用)，其它用 out.color。
local function bp_color(b)
    if b.out.kind=="arrow" then return D.arrow_color(b.out) end
    if b.out.kind=="gear" then
        local best, bt = "common", 0
        for rid in pairs(b.out.rarity_roll or {}) do if RAR[rid] and RAR[rid].tier>bt then bt=RAR[rid].tier; best=rid end end
        return RAR[best].color
    end
    return b.out.color or {0.6,0.7,0.85}
end

-- 制造图谱卡片几何（draw 与 hit 共用）：下半屏竖排，只列当前 tab 下已知图谱
-- 当前选中 tab（默认随活动：forge 活动给炼锭，否则制箭）
function craft_view.cur_tab()
    local t = state.player.craft_tab
    for _,tb in ipairs(TABS) do if tb.id==t then return t end end
    return (state.activity=="forge") and "ingot" or "fletch"
end
function craft_view.craft_known_list()
    local tab = craft_view.cur_tab()
    local list={}; for _,b in ipairs(BLUEPRINTS) do
        if state.player.bp_known[b.id] and (b.cat or "fletch")==tab then list[#list+1]=b end
    end
    return list
end
local craft_known_list = craft_view.craft_known_list

-- tab 行几何（下半屏标题之上一排）
function craft_view.tab_rect(i)
    local w=love.graphics.getWidth(); local n=#TABS; local gap=sx(4)
    local tw=(w-sx(40)-gap*(n-1))/n; local th=sy(22)
    local top=DESIGN_H*0.55*screen.sh - sy(40)
    return sx(20)+(i-1)*(tw+gap), top, tw, th
end

function craft_view.craft_card_rect(slot)
    local w=love.graphics.getWidth(); local ch,gap=sy(34),sy(6); local top=DESIGN_H*0.55*screen.sh
    return sx(20), top+(slot-1)*(ch+gap), w-sx(40), ch
end
local craft_card_rect = craft_view.craft_card_rect

-- 当前 tab 选中的图谱 id：forge 类 tab 用 forge_bp，否则 craft_bp。
local function sel_bp_id()
    local tab = craft_view.cur_tab()
    for _,tb in ipairs(TABS) do if tb.id==tab then
        return (tb.job=="forge") and state.player.forge_bp or state.player.craft_bp
    end end
    return state.player.craft_bp
end

function craft_view.draw()
    local sw, sh = screen.sw, screen.sh
    local cx = love.graphics.getWidth()/2
    local is_forge = (state.activity=="forge") or (craft_view.cur_tab()=="ingot" or craft_view.cur_tab()=="armor" or craft_view.cur_tab()=="bow")

    -- ── 像素世界：场景画布（上半屏暮色工坊）──
    screen.begin_scene()
    sprites.draw_backdrop({ path=false })
    local SW, SH, HOR = sprites.SCENE_W, sprites.SCENE_H, sprites.HOR
    local gy = HOR + math.floor((SH-HOR)*0.40)
    local hx = math.floor(SW*0.30)
    local sx0 = hx + 22                       -- 工作台/铁砧紧贴主角右侧
    if is_forge then sprites.draw_anvil(sx0, gy, fx.t_accum) else sprites.draw_bench(sx0, gy) end
    -- 主角挥锤/做工：锻造工具头偏红铁、制造偏木
    sprites.draw_hero(hx, gy, fx.swing*6, "chop", is_forge and {0.6,0.62,0.68} or {0.7,0.55,0.35})
    -- 做工火花（锻造时坯料处冒火星）
    if is_forge then
        love.graphics.setColor(1,0.7,0.3, 0.5+0.3*math.sin(fx.t_accum*9))
        for _,p in ipairs({{sx0-2,gy-16},{sx0+1,gy-18},{sx0-4,gy-15}}) do love.graphics.rectangle("fill",p[1],p[2],1,1) end
    end
    screen.end_scene()

    -- ── HUD（设计空间 480x800，像素扁平皮）：产物信息锚在上半屏(设计 y≈320)，避开下半屏 tab/卡片 ──
    local py = DESIGN_H*0.40*sh               -- 产物信息基准 y（与旧布局一致，清晰在 tab 之上）
    local bp = state.player.craft_target
    if bp and state.player.bp_known[bp.id] and can_craft(bp) then
        -- 正在制造：产出图标(产物色) + 库存 + 进度（gear 不显数量，显槽名）
        local o=bp.out
        draw_out_icon(o, cx-sx(40), py-sy(92), sx(16))
        if o.kind~="gear" then
            local have = (o.kind=="arrow") and ammo_count(o.head) or inv_count(o.kind,o.id)
            love.graphics.setFont(draw.font_big); setc(o.color or {0.8,0.8,0.85}); love.graphics.print(have, cx-sx(10), py-sy(106))
        end
        love.graphics.setFont(draw.font_sm); setc(UI.dim); love.graphics.printf("正在制造 "..bp.name, 0, py-sy(116), love.graphics.getWidth(), "center")
        bar(cx-sx(100), py-sy(70), sx(200), sy(12), state.player.craft_prog or 0, bp_color(bp))
    elseif bp then
        -- 缺料：灰产物 + 所需材料(够亮/缺红)
        draw_out_icon(bp.out, cx, py-sy(92), sx(16))
        love.graphics.setFont(draw.font_sm); setc(UI.bad); love.graphics.printf("材料不足："..bp.name, 0, py-sy(116), love.graphics.getWidth(), "center")
        local i=0; for m,n in pairs(bp.cost) do local mx=cx-sx(40)+i*sx(46); i=i+1
            local ok=inv_count("mat",m)>=n
            mat_chip(m, mx, py-sy(70), sx(7))
            if not ok then setc(UI.bad); love.graphics.setLineWidth(math.max(1,2*screen.sw)); rrect("line", mx-sx(8), py-sy(70)-sx(8), sx(16), sx(16), sx(3)); love.graphics.setLineWidth(1) end  -- 缺料红描边
            setc(ok and UI.text or UI.bad); love.graphics.setFont(draw.font_sm); love.graphics.print(inv_count("mat",m).."/"..n, mx-sx(6), py-sy(62))
        end
    end
    -- 分类 tab 行（制箭/材料/炼锭/造甲/造弓）
    local curtab = craft_view.cur_tab()
    for i,tb in ipairs(TABS) do
        local tx,ty,tw,th = craft_view.tab_rect(i); local on=(tb.id==curtab)
        panel(tx,ty,tw,th, on and {0.18,0.2,0.3,0.97} or {0.11,0.12,0.17,0.9}, on and UI.btn or UI.line, 5*sw)
        setc(on and UI.text or UI.dim); love.graphics.setFont(draw.font_sm); love.graphics.printf(tb.name, tx, ty+sy(3), tw, "center")
    end
    -- 下半屏：当前 tab 下已知图谱，点选即切换并持续制造（材料用尽自动停）
    love.graphics.setFont(draw.font_sm); setc(UI.dim); love.graphics.printf("图谱（点选制造）", sx(20), DESIGN_H*0.55*sh-sy(16), love.graphics.getWidth()-sx(40), "left")
    local selid = sel_bp_id()
    for slot,b in ipairs(craft_known_list()) do
        local x,y,cw,ch = craft_card_rect(slot); local sel=(selid==b.id); local oc=bp_color(b)
        panel(x,y,cw,ch, sel and {oc[1]*0.22,oc[2]*0.22,oc[3]*0.24,0.97} or {0.11,0.12,0.17,0.95}, sel and oc or UI.line, 6*sw)
        draw_out_icon(b.out, x+sx(18), y+ch/2, sx(11))
        setc(UI.text); love.graphics.setFont(draw.font_sm)
        local qlabel = (b.out.kind=="gear") and "" or ("  x"..b.out.qty)
        love.graphics.print(b.name..qlabel, x+sx(36), y+sy(4))
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

-- 无面板场景内交互：点 tab = 切分类；点下半屏图谱卡 = 选图谱、按其 job 切活动并持续制造
function craft_view.hit(x,y)
    for i,tb in ipairs(TABS) do
        local tx,ty,tw,th = craft_view.tab_rect(i)
        if hit(x,y,tx,ty,tw,th) then state.player.craft_tab=tb.id; return true end
    end
    for slot,b in ipairs(craft_known_list()) do
        local cxr,cyr,cwr,chr = craft_card_rect(slot)
        if hit(x,y,cxr,cyr,cwr,chr) then
            if b.job=="forge" then state.player.forge_bp=b.id; state.activity="forge"
            else state.player.craft_bp=b.id; state.activity="fletch" end
            state.player.craft_prog=0; state.player.craft_stopped=nil; return true
        end
    end
    return false
end

return craft_view
