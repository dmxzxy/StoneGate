-- ============================================================================
-- view/dungeon_view —— 副本面板：副本列表(分档/推荐等级/掉落/解锁/许可钥匙) → 开打。
--   战斗进行中：在该面板顶部显示波次进度 + 当前敌/boss(战斗场景仍由 combat_view 画)。
--   结算：dungeon_result 存在时画结算弹窗(经验/掉落/材料/钥匙 + 关闭)。
-- 提供 draw()、press(x,y)：列表点选开打 / 结算弹窗关闭 / 返回键。
-- 依赖：base/screen + base/draw + core/state + sys/dungeon + sys/inventory + fx + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local state = require("core.state")
local dungeon = require("sys.dungeon")
local inv = require("sys.inventory")
local fx = require("fx")
local D = require("data")
local UI = D.UI
local RAR = D.RAR
local TIER_BAND, TIER_ORDER = D.TIER_BAND, D.TIER_ORDER
local DUNGEONS = D.DUNGEONS
local MAT_NAME, MAT_COLOR = D.MAT_NAME, D.MAT_COLOR

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local function hit(x,y,rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end
local setc = draw.setc
local panel, button, rrect, bar = draw.panel, draw.button, draw.rrect, draw.bar

local dungeon_view = {}

-- 列表卡几何（按档分组）：返回 entries(header/card) + 总高
local function layout()
    local entries={}; local cy=0
    local hh, ch, gap = sy(22), sy(76), sy(6)
    for _,tid in ipairs(TIER_ORDER) do
        entries[#entries+1]={ kind="header", tier=tid, y=cy, h=hh }; cy=cy+hh+sy(4)
        for i,dg in ipairs(DUNGEONS) do if dg.tier==tid then
            entries[#entries+1]={ kind="card", di=i, y=cy, h=ch }; cy=cy+ch+gap
        end end
    end
    return entries, cy
end

local function viewport()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local px,py,pw,ph=sx(16),sy(56),w-sx(32),h-sy(112)
    return px,py,pw,ph, py+sy(40), py+ph-sy(48)
end

-- ---- 结算弹窗 ----
local function draw_result()
    local res = state.dungeon_result; if not res then return end
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    love.graphics.setColor(0,0,0,0.78); love.graphics.rectangle("fill",0,0,w,h)
    local pw,ph=sx(360),sy(420); local px,py=(w-pw)/2,(h-ph)/2
    panel(px,py,pw,ph,{0.1,0.11,0.16,0.99}, res.win and UI.gold or UI.bad, 12*screen.sw)
    love.graphics.setFont(draw.font_big); setc(res.win and UI.gold or UI.bad)
    love.graphics.printf(res.win and "通关！" or "副本失败", px, py+sy(14), pw, "center")
    love.graphics.setFont(draw.font); setc(UI.text); love.graphics.printf(res.dg.name, px, py+sy(48), pw, "center")
    local yy = py+sy(76)
    setc(UI.xp); love.graphics.setFont(draw.font); love.graphics.print("经验 +"..res.xp, px+sx(24), yy); yy=yy+sy(26)
    -- 装备掉落
    if #res.loot>0 then
        setc(UI.dim); love.graphics.setFont(draw.font_sm); love.graphics.print("装备", px+sx(24), yy); yy=yy+sy(16)
        for _,g in ipairs(res.loot) do
            setc(inv.gear_color(g)); love.graphics.setFont(draw.font_sm)
            love.graphics.print("· "..inv.gear_full_name(g), px+sx(30), yy); yy=yy+sy(16)
        end
    end
    -- 材料 / 钥匙
    local hasmat=false; for _ in pairs(res.mats) do hasmat=true end
    if hasmat or res.key then
        setc(UI.dim); love.graphics.setFont(draw.font_sm); love.graphics.print("材料", px+sx(24), yy); yy=yy+sy(16)
        local mx=px+sx(30)
        for id,q in pairs(res.mats) do
            draw.mat_chip(id, mx+sx(6), yy+sy(6), sx(6))
            setc(MAT_COLOR[id] or UI.text); love.graphics.setFont(draw.font_sm)
            love.graphics.print((MAT_NAME[id] or id).." x"..q, mx+sx(16), yy); yy=yy+sy(16)
        end
        if res.key then
            setc(MAT_COLOR[res.key] or UI.gold); love.graphics.setFont(draw.font_sm)
            love.graphics.print("◆ 获得 "..(MAT_NAME[res.key] or res.key).."！", px+sx(30), yy); yy=yy+sy(16)
        end
    end
    button(px+pw/2-sx(64), py+ph-sy(44), sx(128), sy(32), "确定", UI.btn, true)
end

-- ---- 战斗中：顶部进度条(波次/boss) ----
local function draw_run_progress()
    local run = state.dungeon_run; if not run then return end
    local w=love.graphics.getWidth()
    local px,py,pw = sx(16), sy(70), w-sx(32)
    panel(px,py,pw,sy(56),{0.1,0.11,0.16,0.98}, UI.line, 8*screen.sw)
    setc(UI.text); love.graphics.setFont(draw.font); love.graphics.print(run.dg.name, px+sx(12), py+sy(6))
    setc(UI.dim); love.graphics.setFont(draw.font_sm)
    local lbl = (run.phase=="boss") and "BOSS 战" or ("波次 "..run.wave.."/"..run.total)
    love.graphics.printf(lbl, px, py+sy(8), pw-sx(12), "right")
    -- 波次进度块
    local bx,by = px+sx(12), py+sy(34); local n=run.total; local bw=(pw-sx(24))/(n+1)
    for i=1,n do
        local on = (run.phase=="boss") or (i < run.wave) or (i==run.wave)
        local done = (run.phase=="boss") or (i < run.wave)
        setc(done and UI.good or (i==run.wave and UI.btn or UI.line))
        rrect("fill", bx+(i-1)*bw, by, bw-sx(4), sy(8), sx(3))
    end
    setc((run.phase=="boss") and UI.gold or UI.line)
    rrect("fill", bx+n*bw, by, bw-sx(4), sy(8), sx(3))
end

function dungeon_view.draw()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,w,h)
    -- 结算优先
    if state.dungeon_result then draw_result(); return end
    -- 战斗中：只显示进度条 + 返回(放弃)；战斗画面由底层 combat 场景画
    if state.dungeon_run then
        draw_run_progress()
        button(w/2-sx(64), h-sy(44), sx(128), sy(30), "放弃副本", UI.bad, true)
        return
    end
    -- 列表
    local px,py,pw,ph,y0,y1 = viewport()
    panel(px,py,pw,ph,{0.09,0.1,0.15,0.98},UI.line,10*screen.sw)
    love.graphics.setFont(draw.font_med); setc(UI.text); love.graphics.printf("副本", px, py+sy(8), pw, "center")
    draw.close_x(px,py,pw)
    -- 许可显示
    local p = state.player
    setc(UI.dim); love.graphics.setFont(draw.font_sm)
    love.graphics.printf("探险许可 "..math.floor(p.energy or 0).."/"..math.floor(p.energy_max or 0), px+sx(12), py+sy(12), pw-sx(28), "left")

    local entries = layout()
    love.graphics.setScissor(px, y0, pw, y1-y0)
    for _,e in ipairs(entries) do
        local yy = y0 + e.y
        if yy+e.h>=y0 and yy<=y1 then
            if e.kind=="header" then
                local tb=TIER_BAND[e.tier]
                setc(tb.color); rrect("fill", px+sx(14), yy+sy(5), sx(3), e.h-sy(8))
                love.graphics.setFont(draw.font_sm); setc(tb.color); love.graphics.print(tb.name.." 副本", px+sx(22), yy+sy(3))
            else
                local dg=DUNGEONS[e.di]
                local unlocked = dungeon.unlocked(dg)
                local can, why = dungeon.can_enter(dg)
                local tb=TIER_BAND[dg.tier]
                panel(px+sx(12), yy, pw-sx(24), e.h, can and {0.13,0.16,0.22,0.97} or {0.11,0.12,0.17,0.95}, can and UI.btn or UI.line, 8*screen.sw)
                setc(tb.color); rrect("fill", px+sx(12), yy, sx(4), e.h, 2*screen.sw)
                draw.pixel_icon("combat", px+sx(28), yy+sy(14), sx(8), unlocked and tb.color or UI.dim)
                love.graphics.setFont(draw.font); setc(unlocked and UI.text or UI.dim); love.graphics.print(dg.name, px+sx(42), yy+sy(6))
                love.graphics.setFont(draw.font_sm); setc(UI.dim)
                love.graphics.print("推荐 Lv"..dg.min_lvl.."   "..dg.waves.."波 + BOSS", px+sx(42), yy+sy(26))
                -- 成本：许可 + 钥匙
                local costtxt = "许可 "..dg.cost_energy
                if dg.key then costtxt = costtxt .. "  + "..(MAT_NAME[dg.key] or dg.key).."x1" end
                setc(can and UI.good or UI.bad); love.graphics.print(costtxt, px+sx(24), yy+sy(42))
                -- 掉落预览：保底稀有度色点 + unique 标
                local fl = dg.drops.rar_floor
                draw.gem(px+sx(30), yy+sy(64), sx(4), RAR[fl] and RAR[fl].color or UI.dim)
                setc(UI.dim); love.graphics.setFont(draw.font_sm)
                love.graphics.print("保底 "..(RAR[fl] and RAR[fl].name or fl).."+   唯一 "..math.floor((dg.drops.unique_chance or 0)*100).."%", px+sx(42), yy+sy(56))
                -- 右侧状态/开打
                if not unlocked then
                    setc(UI.bad); love.graphics.setFont(draw.font_sm); love.graphics.printf("未解锁", px+sx(12), yy+sy(8), pw-sx(40), "right")
                elseif can then
                    button(px+pw-sx(96), yy+e.h/2-sy(14), sx(72), sy(28), "开打", UI.btn, true, draw.font_sm)
                else
                    setc(UI.bad); love.graphics.setFont(draw.font_sm); love.graphics.printf(why or "不可进入", px+sx(12), yy+sy(8), pw-sx(40), "right")
                end
            end
        end
    end
    love.graphics.setScissor()
    button(px+pw/2-sx(64),py+ph-sy(40),sx(128),sy(30),"返回",{0.4,0.4,0.5},true)
end

function dungeon_view.press(x,y)
    -- 结算弹窗：点确定关闭
    if state.dungeon_result then
        local w,h=love.graphics.getWidth(),love.graphics.getHeight()
        local pw,ph=sx(360),sy(420); local px,py=(w-pw)/2,(h-ph)/2
        if hit(x,y, px+pw/2-sx(64), py+ph-sy(44), sx(128), sy(32)) then state.dungeon_result=nil end
        return true
    end
    -- 战斗中：放弃按钮
    if state.dungeon_run then
        local w,h=love.graphics.getWidth(),love.graphics.getHeight()
        if hit(x,y, w/2-sx(64), h-sy(44), sx(128), sy(30)) then dungeon.abandon() end
        return true
    end
    local px,py,pw,ph,y0,y1 = viewport()
    if draw.hit_close_x(x,y,px,py,pw) then state.panel_open=nil; return true end
    if hit(x,y,px+pw/2-sx(64),py+ph-sy(40),sx(128),sy(30)) then state.panel_open=nil; return true end
    if y>=y0 and y<=y1 then
        local entries = layout()
        for _,e in ipairs(entries) do
            if e.kind=="card" then
                local yy = y0 + e.y
                if hit(x,y, px+sx(12), yy, pw-sx(24), e.h) then
                    local dg=DUNGEONS[e.di]
                    if dungeon.can_enter(dg) then dungeon.enter(dg)
                    else local _,why=dungeon.can_enter(dg); fx.set_toast(why or "无法进入", UI.bad) end
                    return true
                end
            end
        end
    end
    return true
end

return dungeon_view
