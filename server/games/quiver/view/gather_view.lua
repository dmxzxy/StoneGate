-- ============================================================================
-- view/gather_view —— 采集场景（砍柴/采矿/采药）：像素世界(低分场景画布)画暮色林地 +
--   主角骨骼火柴人 chop 姿势 + 资源节点像素精灵(寻找/遇到/采集/完成 状态视觉)；
--   HUD(寻找文字/进度条/库存/职业经验环/节点等级)留设计空间(480x800)叠上层，像素扁平皮。
-- 纯绘制，无命中：采集全自动。逻辑(sys/gather 状态机)不变。
-- 依赖：base/screen + base/draw + view/sprites + core/state + fx + sys/inventory + sys/progression + data。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local sprites = require("view.sprites")
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
local gather_need = prog.gather_need
local to_sx = screen.to_scene_x

-- 采集工具头色：砍柴=斧绿、采矿=镐灰、采药=镰青（仅视觉区分挥动的工具）
local TOOL_COL = { wood={0.55,0.7,0.4}, ore={0.78,0.8,0.86}, herb={0.6,0.85,0.7} }

local gather_view = {}

function gather_view.draw()
    local a = ACTIVITIES[state.activity]; local key=state.activity
    local nd = state.player.gather_node
    local harvesting = nd and nd.phase=="harvest"

    -- ── 像素世界：场景画布 ──
    screen.begin_scene()
    sprites.draw_backdrop({ path=true })
    local SW, SH, HOR = sprites.SCENE_W, sprites.SCENE_H, sprites.HOR
    local gy = HOR + math.floor((SH-HOR)*0.42)          -- 地面基线（主角与节点同站此线）
    local hx = math.floor(SW*0.22)
    -- 主角挥工具：采集时挥得快，寻找时慢
    sprites.draw_hero(hx, gy, harvesting and fx.swing*7 or fx.swing*2, "chop", TOOL_COL[a.mat])
    -- 节点（found 阶段从右滑入，nd.x 是设计 x → 场景 x）
    if nd and (nd.phase=="found" or nd.phase=="harvest" or nd.phase=="done") then
        local nx = to_sx(nd.x or NODE_HOME_X)
        local alpha = (nd.phase=="done") and (1-math.min(1,nd.phase_t/GATHER_DONE)) or 1
        if nd.rich then  -- 富集节点：金色辉环
            setc(UI.gold, alpha*0.5+0.2*math.sin(fx.t_accum*5)); love.graphics.setLineWidth(1)
            love.graphics.circle("line", nx, gy-18, 22); love.graphics.setLineWidth(1)
        end
        sprites.draw_node(nd.mat, nx, gy, nd.flash, nd.hurt, alpha)
    end
    screen.end_scene()

    -- ── HUD（设计空间 480x800，像素扁平皮）──
    local cx = love.graphics.getWidth()/2
    -- 节点屏幕坐标(场景→屏幕，整数放大同 end_scene)：bar/等级用它对齐精灵，避免两套坐标错位
    local nx_node = to_sx(nd and (nd.x or NODE_HOME_X) or NODE_HOME_X)
    local fX = love.graphics.getWidth()/SW; local fY = love.graphics.getHeight()/SH
    local node_cx = nx_node*fX               -- 节点屏幕 x
    local node_feet = gy*fY                  -- 节点/主角脚下屏幕 y

    if (not nd) or nd.phase=="search" then
        -- 寻找：搜索文字 + 进度条（屏幕中部偏上）
        love.graphics.setFont(draw.font_med); setc(UI.dim)
        love.graphics.printf("寻找"..(MAT_NAME[a.mat] or "").."中…", 0, node_feet-sy(150), love.graphics.getWidth(), "center")
        bar(cx-sx(70), node_feet-sy(120), sx(140), sy(8), (nd and nd.phase_t or 0)/GATHER_SEARCH, UI.dim)
    elseif nd.phase~="done" then
        local okreq = state.player.skill[key].lvl >= nd.req
        -- 等级在节点头顶
        setc(okreq and UI.text or UI.bad); love.graphics.setFont(draw.font_sm)
        love.graphics.printf((nd.rich and "★" or "").."Lv"..nd.level, node_cx-sx(40), node_feet-sy(64), sx(80), "center")
        -- 采集进度(耐久)+ atb 在节点脚下
        if nd.phase=="harvest" then
            bar(node_cx-sx(46), node_feet+sy(4), sx(92), sy(8), nd.dur/nd.max_dur, MAT_COLOR[nd.mat])
            bar(node_cx-sx(46), node_feet+sy(14), sx(92), sy(4), nd.atb, {0.9,0.7,0.3})
        end
    end
    -- 当前采集大类持有数 + 职业等级/经验环：放在头像卡右侧"名字行下方"第二行(不压名字/许可钥匙)
    local hudx = sx(122); local hudy = sy(38)
    icon_mat(a.mat, hudx, hudy+sy(5), sx(8)); setc(MAT_COLOR[a.mat]); love.graphics.setFont(draw.font_sm)
    love.graphics.print(inv.cat_count(a.mat), hudx+sx(12), hudy)
    local s = state.player.skill[key]
    ring(hudx+sx(56), hudy+sy(5), sx(9), s.xp/gather_need(s.lvl), MAT_COLOR[a.mat])
    love.graphics.setFont(draw.font_sm); setc(UI.text); love.graphics.printf("Lv"..s.lvl, hudx+sx(56)-sx(14), hudy+sy(1), sx(28), "center")
end

return gather_view
