-- ============================================================================
-- sys/gather —— 采集遭遇状态机：寻找→遇到→判定→采集，三种采集（砍柴/采矿/采药）共用。
--   gather_node.phase: "search" | "found" | "harvest" | "done"，与战斗同构。
-- 依赖：data + core/state + sys/inventory（产出入背包）+ sys/progression（采集经验）+ fx。
--   不被 craft require；顶层 require 无环。
-- ============================================================================
local D = require("data")
local state = require("core.state")
local inv = require("sys.inventory")
local prog = require("sys.progression")
local fx = require("fx")

local ACTIVITIES = D.ACTIVITIES
local NODE_BASE = D.NODE_BASE
local MAT_REQ_FAIL = D.MAT_REQ_FAIL
local MAT_NAME, MAT_COLOR = D.MAT_NAME, D.MAT_COLOR
local NODE_HOME_X = D.NODE_HOME_X
local GATHER_SEARCH, GATHER_FOUND, GATHER_DONE = D.GATHER_SEARCH, D.GATHER_FOUND, D.GATHER_DONE
local DESIGN_W, DESIGN_H = D.DESIGN_W, D.DESIGN_H
local UI = D.UI

local gather = {}

-- 实例化一个资源节点（类比 make_enemy）；返回 nil 表示该区无此类资源
function gather.make_node(mat)
    local nd = state.region.nodes and state.region.nodes[mat]
    if not nd or not nd.kinds or #nd.kinds==0 then return nil end
    local kind = nd.kinds[math.random(#nd.kinds)]
    local lvl = math.max(1, math.min(99, math.random(state.region.lo, state.region.hi) + (nd.lvloff or 0)))
    local rich = math.random() < 0.05
    if rich then lvl = lvl + math.ceil(state.region.hi*0.2) end   -- 富集节点：等级更高(约+20%)、产量翻倍
    return { phase="found", phase_t=0, mat=mat, kind=kind, name=MAT_NAME[kind] or kind, color=MAT_COLOR[kind] or MAT_COLOR[mat],
        level=lvl, req=lvl, rich=rich, max_dur=math.ceil(3*NODE_BASE[mat].hp*(1+lvl*0.12)), dur=math.ceil(3*NODE_BASE[mat].hp*(1+lvl*0.12)),
        atb=0, flash=0, hurt=0, x=DESIGN_W+60 }
end
function gather.finish_node(nd, key)
    local lvl = state.player.skill[key].lvl
    local y = math.max(1, math.floor(NODE_BASE[nd.mat].yield * (1+nd.level*0.18) * (1+(lvl-1)*0.04)))
    if nd.rich then y = y*2 end
    inv.inv_add("mat", nd.kind, y)   -- 产出具体材料(该档随机一系)，不再归并大类
    -- 砍柴小概率掉鸟巢羽毛(所有箭必需的低门槛二级材料)
    if nd.mat=="wood" and math.random() < 0.10 then inv.inv_add("mat", "feather", 1+math.random(2)) end
    -- 采矿副产利刃石/硫磺(元素箭附材)
    if nd.mat=="ore" and math.random() < 0.08 then
        inv.inv_add("mat", (math.random()<0.5) and "bladestone" or "sulfur", 1)
    end
    prog.gain_gather_xp(key, math.floor(nd.level*5+6))
    fx.burst(NODE_HOME_X, DESIGN_H*0.42, nd.color, 12)
    fx.add_float(NODE_HOME_X, DESIGN_H*0.20, "+"..y.." "..(MAT_NAME[nd.kind] or nd.kind), nd.color, 1.1)
    nd.phase="done"; nd.phase_t=0
end
function gather.node_machine(dt)
    local mat = ACTIVITIES[state.activity].mat
    local key = state.activity
    local nd = state.player.gather_node
    if not nd then state.player.gather_node = { phase="search", phase_t=0, mat=mat }; return end
    if nd.mat ~= mat then state.player.gather_node = nil; return end   -- 活动切换保护
    if nd.phase == "search" then
        nd.phase_t = nd.phase_t + dt
        if nd.phase_t >= GATHER_SEARCH then
            local n = gather.make_node(mat)
            if n then state.player.gather_node = n else nd.phase_t = 0 end   -- 该区无此资源则继续找
        end
    elseif nd.phase == "found" then
        nd.phase_t = nd.phase_t + dt
        local k = math.min(1, nd.phase_t/GATHER_FOUND); local e=1-(1-k)*(1-k)
        nd.x = DESIGN_W+60 + (NODE_HOME_X-(DESIGN_W+60))*e
        if nd.phase_t >= GATHER_FOUND then
            nd.x = NODE_HOME_X
            if state.player.skill[key].lvl >= nd.req then nd.phase="harvest"; nd.atb=0
            else
                fx.add_float(NODE_HOME_X, DESIGN_H*0.20, MAT_REQ_FAIL[mat].."(需Lv"..nd.req..")", UI.bad, 1.0)
                state.player.gather_node = nil   -- 等级不足：立刻继续寻找下一个
            end
        end
    elseif nd.phase == "harvest" then
        nd.flash=math.max(0,nd.flash-dt); nd.hurt=math.max(0,nd.hurt-dt)
        local hs = 0.9 * (1 + (state.player.skill[key].lvl-1)*0.05)   -- 职业越高采得越快
        nd.atb = nd.atb + hs*dt
        if nd.atb >= 1 then
            nd.atb = 0; nd.dur = nd.dur - 1; nd.flash=0.1; nd.hurt=0.2; fx.shake=math.min(8,fx.shake+1)
            for _=1,3 do local ang=math.random()*math.pi*2; local s=30+math.random()*80
                fx.particles[#fx.particles+1]={x=NODE_HOME_X,y=DESIGN_H*0.42,vx=math.cos(ang)*s,vy=math.sin(ang)*s-30,life=0.3+math.random()*0.3,max=0.6,size=2+math.random()*3,color=nd.color} end
            if nd.dur <= 0 then gather.finish_node(nd, key) end
        end
    elseif nd.phase == "done" then
        nd.phase_t = nd.phase_t + dt
        if nd.phase_t >= GATHER_DONE then state.player.gather_node = nil end
    end
end

return gather
