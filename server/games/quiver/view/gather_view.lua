-- ============================================================================
-- view/gather_view —— 采集场景（砍柴/采矿/采药）：弓手挥工具 + 资源节点(寻找/采集/完成) + 顶部库存/职业经验环。
-- 纯绘制，无命中：采集全自动。
-- 依赖：base/screen + base/draw + core/state + fx + sys/inventory(inv_count) + sys/progression(gather_need) + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local state = require("core.state")
local fx = require("fx")
local inv = require("sys.inventory")
local prog = require("sys.progression")
local D = require("data")
local UI = D.UI
local ACTIVITIES = D.ACTIVITIES
local MAT_NAME, MAT_COLOR = D.MAT_NAME, D.MAT_COLOR
local DESIGN_H = D.DESIGN_H
local GATHER_SEARCH, GATHER_DONE = D.GATHER_SEARCH, D.GATHER_DONE
local NODE_HOME_X = D.NODE_HOME_X

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local setc = draw.setc
local bar, ring = draw.bar, draw.ring
local icon_mat = draw.icon_mat
local draw_archer, draw_node_body = draw.draw_archer, draw.draw_node_body
local inv_count = inv.inv_count
local gather_need = prog.gather_need

local gather_view = {}

function gather_view.draw()
    local sw, sh = screen.sw, screen.sh
    local a = ACTIVITIES[state.activity]; local key=state.activity
    local nd = state.player.gather_node
    local px,py = sx(80), DESIGN_H*0.46*sh
    local harvesting = nd and nd.phase=="harvest"
    draw_archer(px,py,"chop", harvesting and fx.swing*7 or fx.swing*2)   -- 采集时挥得快，寻找时慢
    local cx = love.graphics.getWidth()/2
    if (not nd) or nd.phase=="search" then
        -- 寻找：头顶放大镜左右轻摆 + 搜索进度条
        local sxo = math.sin(fx.t_accum*4)*sx(6)
        setc(UI.dim); love.graphics.setLineWidth(math.max(1,sx(2)))
        love.graphics.circle("line", px+sxo, py-sy(70), sx(7)); love.graphics.line(px+sxo+sx(5),py-sy(65), px+sxo+sx(11),py-sy(59)); love.graphics.setLineWidth(1)
        love.graphics.setFont(draw.font_sm); setc(UI.dim); love.graphics.printf("寻找"..(MAT_NAME[a.mat] or "").."中…", 0, py-sy(108), love.graphics.getWidth(), "center")
        bar(cx-sx(60), py-sy(86), sx(120), sy(6), (nd and nd.phase_t or 0)/GATHER_SEARCH, UI.dim)
    else
        local nx = (nd.x or NODE_HOME_X)*sw; local ny = py
        local alpha = (nd.phase=="done") and (1-math.min(1,nd.phase_t/GATHER_DONE)) or 1
        draw_node_body(nd.mat, nx, ny, nd.flash, nd.hurt, alpha)
        if nd.rich then setc(UI.gold, alpha*0.8); love.graphics.setLineWidth(math.max(2,sx(2))); love.graphics.circle("line", nx, ny-sy(30), sx(34)); love.graphics.setLineWidth(1) end
        local okreq = state.player.skill[key].lvl >= nd.req
        setc(okreq and UI.text or UI.bad); love.graphics.setFont(draw.font_sm)
        love.graphics.printf((nd.rich and "★" or "").."Lv"..nd.level, nx-sx(40), ny-sy(78), sx(80), "center")
        if nd.phase=="harvest" then
            bar(nx-sx(48), ny+sy(14), sx(96), sy(9), nd.dur/nd.max_dur, MAT_COLOR[nd.mat])
            bar(nx-sx(48), ny+sy(26), sx(96), sy(4), nd.atb, {0.9,0.7,0.3})
        end
    end
    -- 顶部：材料图标 + 持有数 + 采集职业等级/经验环
    icon_mat(a.mat, cx-sx(40), py-sy(120), sx(13))
    love.graphics.setFont(draw.font_big); setc(MAT_COLOR[a.mat]); love.graphics.print(inv_count("mat",a.mat), cx-sx(18), py-sy(134))
    local s = state.player.skill[key]
    ring(cx+sx(40), py-sy(116), sx(11), s.xp/gather_need(s.lvl), MAT_COLOR[a.mat])
    love.graphics.setFont(draw.font_sm); setc(UI.text); love.graphics.printf("Lv"..s.lvl, cx+sx(40)-sx(16), py-sy(120), sx(32), "center")
end

return gather_view
