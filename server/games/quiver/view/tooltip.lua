-- ============================================================================
-- view/tooltip —— 物品详情浮层：装备/材料/箭矢/药剂的标题/属性逐行/按钮。
-- 提供 draw_tooltip()、tt_content(tt)/tt_geom(tt)（几何，draw 与命中共用）、tooltip_press(x,y)。
-- 装备/卸下动作在 tooltip_press 内直接改 state.player.equip/inv 并 recalc（同帧顺序调用，不上事件）。
-- 依赖：base/screen + base/draw + core/state + sys/inventory + sys/progression(recalc) + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local state = require("core.state")
local inv = require("sys.inventory")
local prog = require("sys.progression")
local D = require("data")
local UI = D.UI
local RAR = D.RAR
local SLOT_INFO = D.SLOT_INFO
local ATTRS, ATTR_NAME, ATTR_COLOR = D.ATTRS, D.ATTR_NAME, D.ATTR_COLOR
local MAT_NAME, MAT_COLOR, MAT_DESC = D.MAT_NAME, D.MAT_COLOR, D.MAT_DESC
local POT_NAME, POT_COLOR, POT_DESC = D.POT_NAME, D.POT_COLOR, D.POT_DESC
local ARROW = D.ARROW
local BP = D.BP

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local setc = draw.setc
local panel, button = draw.panel, draw.button
local inv_count, ammo_count, inv_add = inv.inv_count, inv.ammo_count, inv.inv_add
local gear_color, gear_full_name = inv.gear_color, inv.gear_full_name
local recalc = prog.recalc

local tooltip = {}

-- 物品详情的逐行内容（基础属性白/属性彩、词缀绿）
local function gear_detail_lines(g)
    local lines = {}
    local s = g.stats
    if s.wmin then lines[#lines+1] = { "攻击力  "..s.wmin.."~"..s.wmax, UI.text } end
    if s.wspeed then lines[#lines+1] = { string.format("攻速  %.2f 秒/次", 1/s.wspeed), UI.text } end
    for _,k in ipairs(ATTRS) do if s[k] then lines[#lines+1] = { "+"..s[k].."  "..ATTR_NAME[k], ATTR_COLOR[k] } end end
    if s.armor then lines[#lines+1] = { "护甲  +"..s.armor, UI.text } end
    for _,af in ipairs(g.affixes) do
        local txt = af.pct and ((af.key=="crit" and "暴击" or ATTR_NAME[af.key] or af.key).."  +"..af.val.."%")
                            or ("+"..af.val.."  "..(ATTR_NAME[af.key] or af.key))
        lines[#lines+1] = { txt, {0.45,0.85,0.55} }
    end
    -- 武器：攻速基础来自武器，敏捷再按 % 加成
    if SLOT_INFO[g.slot].kind=="weapon" then lines[#lines+1] = { "敏捷再提升攻速、力量提升攻击", UI.dim } end
    return lines
end

local function arrow_desc(t) return "战斗消耗的弹药。伤害倍率 x"..t.mult.."。" end

-- 构建 tooltip 内容：标题/标题色/副标题/逐行/底部按钮文案
function tooltip.tt_content(tt)
    if tt.kind=="gear" then
        local g=tt.g
        local lines = gear_detail_lines(g)
        -- 与当前装备对比：背包里看装备时，对比同槽已装备的 gear_score 差值（↑绿/↓红）
        if tt.src=="bag" then
            local cur = state.player.equip[g.slot]
            if cur then
                local diff = math.floor(inv.gear_score(g) - inv.gear_score(cur))
                if diff>0 then lines[#lines+1] = { "装备评分 ↑ +"..diff.." 比当前", {0.45,0.85,0.55} }
                elseif diff<0 then lines[#lines+1] = { "装备评分 ↓ "..diff.." 比当前", UI.bad }
                else lines[#lines+1] = { "装备评分 与当前持平", UI.dim } end
            else
                lines[#lines+1] = { "该槽位当前为空", UI.dim }
            end
        end
        return gear_full_name(g), gear_color(g),
            RAR[g.rarity].name.."  ·  "..SLOT_INFO[g.slot].name.."  ·  装等 "..g.ilvl,
            lines, (tt.src=="bag") and "装备" or (tt.src=="equip") and "卸下" or nil
    elseif tt.kind=="mat" then
        local lines={ {"持有："..inv_count("mat",tt.id), UI.text}, {MAT_DESC[tt.id] or "", UI.dim} }
        return MAT_NAME[tt.id], MAT_COLOR[tt.id], "材料 · 可堆叠", lines, nil
    elseif tt.kind=="potion" then
        local lines={ {"持有："..inv_count("potion",tt.id), UI.text}, {POT_DESC[tt.id] or "", UI.dim} }
        return POT_NAME[tt.id], POT_COLOR[tt.id], "消耗品 · 可堆叠", lines, nil
    else -- arrow
        local t = ARROW[tt.id]; local bp = BP[tt.id]
        local lines={ {"持有："..ammo_count(tt.id).." 支", UI.text}, {arrow_desc(t), UI.dim} }
        if bp then local parts={}; for m,n in pairs(bp.cost) do parts[#parts+1]=(MAT_NAME[m] or m).."x"..n end
            lines[#lines+1]={ "配方："..table.concat(parts,"  "), {0.6,0.7,0.85} } end
        return t.name, t.color, "箭矢 · 可堆叠", lines, nil
    end
end

function tooltip.tt_geom(tt)
    local W,H = love.graphics.getWidth(), love.graphics.getHeight()
    local _,_,_,lines = tooltip.tt_content(tt)
    local tw = sx(290)
    local th = sy(66) + #lines*sy(20) + sy(50)
    return (W-tw)/2, (H-th)/2, tw, th, lines
end

function tooltip.draw_tooltip()
    if not state.tooltip then return end
    local sw = screen.sw
    local W,H = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0,0,0,0.55); love.graphics.rectangle("fill",0,0,W,H)
    local title, tcol, sub, lines, equip = tooltip.tt_content(state.tooltip)
    local tx,ty,tw,th = tooltip.tt_geom(state.tooltip)
    panel(tx,ty,tw,th,{0.1,0.11,0.16,0.99},tcol,10*sw)
    setc(tcol); love.graphics.setFont(draw.font_med); love.graphics.printf(title, tx+sx(14), ty+sy(10), tw-sx(28), "left")
    setc(UI.dim); love.graphics.setFont(draw.font_sm); love.graphics.printf(sub, tx+sx(14), ty+sy(36), tw-sx(28), "left")
    setc(UI.line); love.graphics.rectangle("fill", tx+sx(14), ty+sy(56), tw-sx(28), 1*screen.sh)
    local yy = ty+sy(64)
    for _,ln in ipairs(lines) do setc(ln[2]); love.graphics.print(ln[1], tx+sx(18), yy); yy = yy + sy(20) end
    local fy = ty+th-sy(40)
    if equip then
        local bw=(tw-sx(40))/2
        button(tx+sx(14), fy, bw, sy(30), equip, {0.3,0.6,0.4}, true, draw.font_sm)
        button(tx+sx(26)+bw, fy, bw, sy(30), "关闭", {0.4,0.4,0.5}, true, draw.font_sm)
    else
        button(tx+tw/2-sx(60), fy, sx(120), sy(30), "关闭", {0.4,0.4,0.5}, true, draw.font_sm)
    end
end

function tooltip.tooltip_press(x,y)
    local tx,ty,tw,th = tooltip.tt_geom(state.tooltip)
    local fy = ty+th-sy(40)
    if state.tooltip.kind=="gear" then
        local bw=(tw-sx(40))/2
        local on_action = x>=tx+sx(14) and x<=tx+sx(14)+bw and y>=fy and y<=fy+sy(30)
        if on_action and state.tooltip.src=="bag" then
            local i=state.tooltip.slot; local g=state.tooltip.g
            if i and state.player.inv[i] and state.player.inv[i].gear==g then state.player.inv[i]=nil end
            local old=state.player.equip[g.slot]; state.player.equip[g.slot]=g; if old then inv_add("gear",nil,1,old) end
            recalc(); state.tooltip=nil; return
        elseif on_action and state.tooltip.src=="equip" then
            -- 卸下：装备回背包
            local g=state.tooltip.g
            if inv_add("gear",nil,1,g) then state.player.equip[g.slot]=nil; recalc() end
            state.tooltip=nil; return
        end
    end
    state.tooltip=nil
end

return tooltip
