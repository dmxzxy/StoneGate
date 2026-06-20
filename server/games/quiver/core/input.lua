-- ============================================================================
-- core/input —— 指针输入总分发：press/drag_move/drag_release/region_release/wheel。
-- 按 state.panel_open 路由到各 view 的 hit/press；无面板时处理战斗复活、制造场景内点选、底部五入口。
-- 拖拽三段(DRAG_THRESH)与命中几何与原 main 完全一致(命中坐标不变)；触摸/鼠标同构(丢弃 id)。
-- 依赖：core/state + base/screen(缩放) + fx + sys/combat(next_enemy 间接经 view) + view/*。
-- ============================================================================
local state = require("core.state")
local screen = require("base.screen")
local D = require("data")
local ACTIVITIES = D.ACTIVITIES

local activity_view = require("view.activity_view")
local skills_view = require("view.skills_view")
local bag_view = require("view.bag_view")
local equip_view = require("view.equip_view")
local mastery_view = require("view.mastery_view")
local system_view = require("view.system_view")
local region_view = require("view.region_view")
local craft_view = require("view.craft_view")
local dungeon_view = require("view.dungeon_view")

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local function hit(x,y,rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end

-- 拖拽位移阈值：超过才算"拖动"，否则松手算"点击"
local DRAG_THRESH = 10

local input = {}

function input.press(x,y)
    if state.result_banner=="defeat" then state.player.hp=state.player.max_hp; state.result_banner=nil; state.activity="rest"; state.enemy=nil; return end
    -- 副本流程(战斗中/结算)：无论是否开了面板，点击都先交给副本视图(放弃/确定/列表)
    if state.dungeon_run or state.dungeon_result then dungeon_view.press(x,y); return end
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    -- 齿轮按钮(右上角常驻)：开/关系统菜单。优先于其它(但副本流程已先拦)
    do
        local gw=22*screen.sw; local gx=w-34*screen.sw; local gy=8*screen.sw
        if hit(x,y,gx,gy,gw,gw) then state.panel_open=(state.panel_open=="system") and nil or "system"; return end
    end
    if state.panel_open=="system" then system_view.hit(x,y); return end
    if not state.panel_open then
        -- 制造挂机中：点下半屏图谱卡 = 选图谱并持续制造
        if ACTIVITIES[state.activity].kind=="craft" then
            if craft_view.hit(x,y) then return end
        end
        -- 底部五入口：活动 / 技能 / 背包 / 装备 / 地区
        local by=h-sy(46); local n=5; local gap=sx(6); local bw=(w-sx(20)-gap*(n-1))/n
        local ids={"activity","skills","bag","equip","region"}
        for i,id in ipairs(ids) do if hit(x,y, sx(10)+(i-1)*(bw+gap), by, bw, sy(36)) then state.panel_open=id; return end end
    elseif state.panel_open=="region" then
        region_view.press(x,y)
    elseif state.panel_open=="dungeon" then
        dungeon_view.press(x,y)
    elseif state.panel_open=="activity" then
        activity_view.hit(x,y)
    elseif state.panel_open=="skills" then
        skills_view.hit(x,y)
    elseif state.panel_open=="equip" then
        equip_view.hit(x,y)
    elseif state.panel_open=="mastery" then
        mastery_view.hit(x,y)
    elseif state.panel_open=="bag" then
        bag_view.press(x,y)
    end
end

function input.drag_move(x,y)
    -- 地区列表滚动（拖动超阈值算滚动）
    if state.region_drag then
        local dy = y-state.region_drag.y0
        state.region_scroll = state.region_drag.s0 - dy
        region_view.clamp_scroll()
        if math.abs(dy) > DRAG_THRESH*screen.sw then state.region_drag.moved=true end
        return
    end
    if not state.drag then return end
    state.drag.x=x; state.drag.y=y
    if not state.drag.moved then
        local dx,dy = x-state.drag.sx0, y-state.drag.sy0
        if dx*dx+dy*dy > (DRAG_THRESH*screen.sw)^2 then state.drag.moved=true end
    end
end

function input.drag_release(x,y) bag_view.drag_release(x,y) end
function input.region_release(x,y) region_view.release(x,y) end

-- 松手总分发：region_drag 优先（地区滚动/点选），否则背包拖拽
function input.release(x,y)
    if state.region_drag then region_view.release(x,y)
    elseif state.drag then bag_view.drag_release(x,y) end
end

function input.wheel(dx,dy)
    if state.panel_open=="region" then state.region_scroll=state.region_scroll-dy*sy(40); region_view.clamp_scroll() end
end

return input
