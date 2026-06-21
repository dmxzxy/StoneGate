-- ============================================================================
-- view/sprites —— 像素世界精灵库（在低分场景画布的像素坐标里画，整体由 screen 放大）。
-- 收纳：主角 draw_hero（骨骼火柴人，代码关节非PNG，chibi 大头，从 scene_hero_ref 移植）
--      + 怪物像素精灵 M{}/spr（从 monsters_ref 移植，全彩暮色调）
--      + 资源节点像素精灵（树/矿/草）+ 通用 draw_sprite / spr API。
-- 纯绘制，无状态：所有动画相位由调用方传入。坐标都是场景画布像素（240x400），不乘 screen.sw。
-- 依赖：love + data(D.PIX 调色)。
-- ============================================================================
local D = require("data")
local screen = require("base.screen")
local draw = require("base.draw")   -- 只取动画时钟 draw.t（萤火漂移相位）；draw 不 require sprites，无环。
local P = D.PIX

local sprites = {}

local function C(c,a) love.graphics.setColor(c[1],c[2],c[3],a or c[4] or 1) end
local function lerp(a,b,t) return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t} end

-- ── 暮色像素背景（场景画布像素坐标）：3 段天空 + 暖地平线 + 月 + 星 + 远山 + 地面 + 草丛 + 树。
-- 所有活动场景共用同一片"暮色林地"，只在前景叠各自的道具/角色。HOR=地平线（场景像素 y）。
-- opt.path=true 才画小径(战斗/采集那种"出门"场景)；休息/工作场景不画路，让前景道具坐实地面。
sprites.SCENE_W, sprites.SCENE_H = screen.SCENE_W, screen.SCENE_H
sprites.HOR = math.floor(screen.SCENE_H*0.56)
function sprites.draw_backdrop(opt)
    opt = opt or {}
    local SW, SH, HOR = sprites.SCENE_W, sprites.SCENE_H, sprites.HOR
    for yy=0,HOR-1 do local t=yy/HOR; local col
        if t<0.6 then col=lerp(P.sky_top,P.sky_mid,t/0.6) else col=lerp(P.sky_mid,P.sky_hor,(t-0.6)/0.4) end
        C(col); love.graphics.rectangle("fill",0,yy,SW,1) end
    C(P.warm,0.5); love.graphics.rectangle("fill",0,HOR-10,SW,10)
    -- 月 + 辉 + 弯月 + 星
    C(P.moon,0.10); love.graphics.circle("fill",SW-40,46,22)
    C(P.moon); love.graphics.circle("fill",SW-40,46,13); C(P.sky_mid); love.graphics.circle("fill",SW-46,42,12)
    C({1,1,1},0.8); for _,s in ipairs({{30,42},{63,27},{105,60},{SW-15,82},{45,105},{144,33},{90,132}}) do love.graphics.rectangle("fill",s[1],s[2],1,1) end
    -- 远山
    C(P.hill_far); love.graphics.ellipse("fill",54,HOR+24,108,46); love.graphics.ellipse("fill",SW-30,HOR+27,96,40)
    C(P.hill_mid); love.graphics.ellipse("fill",SW/2,HOR+36,144,36)
    -- 地面
    C(P.grass); love.graphics.rectangle("fill",0,HOR,SW,SH-HOR)
    C(P.grass_hi); love.graphics.rectangle("fill",0,HOR,SW,3)
    if opt.path then  -- 小径（向地平线收窄）
        C(P.dirt); love.graphics.polygon("fill", 90,HOR, 114,HOR, 144,SH, 60,SH)
        C(P.dirt_hi); love.graphics.polygon("fill", 96,HOR, 105,HOR, 111,SH, 87,SH)
    end
    -- 草丛 + 树（深度分层：远小冷 → 近大）
    for _,g in ipairs({{18,HOR+16},{45,HOR+46},{180,HOR+22},{SW-12,HOR+60},{150,HOR+76}}) do
        C(P.grass_dk); love.graphics.rectangle("fill",g[1],g[2],2,1); C(P.grass_hi); love.graphics.rectangle("fill",g[1],g[2]-1,1,1) end
    sprites.draw_tree(30,HOR+20,18); sprites.draw_tree(SW-22,HOR+28,22)
    sprites.draw_tree(18,HOR+110,38)
    sprites.draw_bush(78,HOR+86,6); sprites.draw_rock(150,HOR+150,7)
    -- 萤火：随时钟轻飘(整数像素，亮度脉动)。各点相位错开，避免齐步走。
    local tt = draw.t or 0
    local flies = {{108,HOR+60},{150,HOR+45},{78,HOR+92},{192,HOR+66},{126,HOR+78}}
    for i,p in ipairs(flies) do
        local ph = tt*1.4 + i*1.7
        local fxp = math.floor(p[1] + math.sin(ph)*3)
        local fyp = math.floor(p[2] + math.cos(ph*0.8)*2)
        C(P.fly, 0.55 + 0.4*math.abs(math.sin(ph*1.3)))
        love.graphics.rectangle("fill", fxp, fyp, 1, 1)
    end
end

-- ── 怪物精灵：字符行 → 1px 方块（每精灵自带调色）。从 monsters_ref 原样移植。──
-- spr(rows,pal,ox,oy[,sc][,flip]): sc 整数放大；flip 水平翻转（敌人朝左面向主角）。
local function spr(rows, pal, ox, oy, sc, flip)
    sc = sc or 1
    local w = #rows[1]
    for r=1,#rows do local row=rows[r]
        for c=1,#row do local p=pal[row:sub(c,c)]
            if p then C(p)
                local cc = flip and (w-c) or (c-1)
                love.graphics.rectangle("fill", ox+cc*sc, oy+(r-1)*sc, sc, sc)
            end
        end
    end
end
sprites.spr = spr

-- 怪物精灵表（name -> {pal, rows}），从 _pixel_ref/monsters_ref.lua 移植。
local M = {}
M.slime={ pal={O={0.12,0.28,0.16},b={0.34,0.72,0.42},h={0.5,0.86,0.56},d={0.2,0.46,0.28},w={0.95,0.97,0.9},e={0.1,0.12,0.1}},
 rows={"....OOOOOO....","..OObbbbbbOO..",".ObbhhhhbbbbO.","ObbbbbbbbbbbbO","ObwwbbbbwwbbbO","ObweObbbbweObO","ObbbbbbbbbbbbO","ObbbbbbbbbbbbO","OdbbbbbbbbbbdO",".OdddddddddddO","..OOOOOOOOOO.."} }
M.bat={ pal={O={0.10,0.08,0.12},b={0.42,0.30,0.52},h={0.58,0.44,0.7},e={0.95,0.7,0.2},f={0.95,0.95,0.95}},
 rows={"O..........O","OO........OO","ObO.OOOO.ObO","ObbOObbOObbO","ObbbbbbbbbbO",".ObbeeeebO..",".ObbbbbbbO..","..ObffffbO..","...OffffO...","....OOOO...."} }
M.boar={ pal={O={0.16,0.10,0.08},b={0.45,0.30,0.22},h={0.6,0.42,0.3},d={0.30,0.20,0.14},e={0.9,0.5,0.2},t={0.92,0.92,0.85}},
 rows={".....OOOOO....","...OOhhhhhO...","..OdbbbbbbbO..",".ObbbbbbbbbbbO","ObhhbbbbbbbbbO","ObbbbbbbbbbebO","tObbbbbbbbbbbO",".ObbbbbbbbbbO.",".O.OO..OO.O..","..O.O..O.O..."} }
M.wolf={ pal={O={0.10,0.10,0.14},b={0.46,0.48,0.55},h={0.62,0.64,0.72},d={0.30,0.31,0.38},e={0.95,0.75,0.25}},
 rows={"O.O.........","OhO.OOOO....","OhhOhhhhO...","OdhhhhhhhO.OO",".OhhhhhhhhhhO",".OhhhhhhhhdO.","OebhhhhhhbO..",".OhhhhhhhhO..","..O.OO.OO.O..","..O.OO.OO...."} }
M.ghost={ pal={O={0.55,0.6,0.78},b={0.78,0.84,0.96},h={0.92,0.95,1.0},e={0.2,0.25,0.45}},
 rows={"...OOOOOO...","..ObbbbbbO..",".ObhhhhhbbO.","ObhhhhhhhhbO","ObheeheehhbO","ObhhhhhhhhbO","ObbbbbbbbbbO","ObbObbObbbbO",".O.O..O..O.."} }
M.golem={ pal={O={0.14,0.14,0.16},b={0.45,0.46,0.52},h={0.6,0.62,0.68},d={0.30,0.31,0.36},e={0.5,0.85,0.95}},
 rows={"..OOOOOOOO..",".OhhhhhhhhO.","OhheehheehhO","OhhhhhhhhhhO","OdhhhhhhhhdO","OhhOhhhhOhhO","OhhhhhhhhhhO",".OdhhhhhhdO.",".O.OOOO.OO.",".OO....OO..."} }
M.ogre={ pal={O={0.12,0.16,0.10},b={0.40,0.58,0.32},h={0.52,0.72,0.42},d={0.26,0.40,0.22},e={0.95,0.85,0.3},t={0.92,0.9,0.8}},
 rows={"...OOOOOO...","..OhhhhhhO..",".OheeeehhO..",".OhhhhhhhhO.","tOhhhbbhhhOt","OhhhhhhhhhhO","OdhhhhhhhhdO",".OhhhhhhhhO.",".OhO..OhO...",".OO....OO..."} }
M.dragon={ pal={O={0.30,0.10,0.10},h={0.80,0.32,0.27},e={0.98,0.85,0.32},w={0.50,0.18,0.16}},
 rows={"...O....O...","..OhO..OhO..","..OhhOOhhO..",".OhhhhhhhhO.",".OheehheehO.",".OhhhhhhhhO.","OwhhhhhhhhwO","OwwOhhhhOwwO",".OOOhhhhOOO.","...OhhhhO...","...OO..OO..."} }
M.skeleton={ pal={O={0.2,0.2,0.18},b={0.86,0.86,0.8},h={0.96,0.96,0.92},e={0.9,0.3,0.2},d={0.6,0.6,0.55}},
 rows={"...OOOO...","..ObbbbO..",".ObheehbO.",".ObhhhhbO.","..ObbbbO..","...ObO.O..","O.ObbbbO.O","OObbbbbbOO",".O.ObbO.O.","...O..O...","..OO..OO.."} }
M.beetle={ pal={O={0.10,0.12,0.08},b={0.30,0.50,0.24},h={0.46,0.7,0.34},e={0.95,0.8,0.2},d={0.18,0.32,0.14}},
 rows={"..O.OO.O..",".ObOOOObO.","O.ObhhbO.O","OObhhhhbOO","ObhdhhdhbO","ObhhhhhhbO","ObheehbO..","OObhhhhbOO",".O.OOOO.O.","..O....O.."} }
-- ── P1 补全敌型（沿用 O=描边 + 暮色全彩 + 一条高光的同款风格）──
-- 强盗：兜帽人形，露出眼缝 + 短刀，暮色棕革。
M.bandit={ pal={O={0.10,0.08,0.10},b={0.46,0.34,0.22},h={0.6,0.46,0.30},k={0.55,0.4,0.5},e={0.95,0.8,0.3},s={0.78,0.8,0.85}},
 rows={"...OOOOO...","..OkkkkkO..",".OkkkkkkkO.",".OkbbbbbkO.",".ObeOObebO.",".ObhhhhhbO.","OsObbbbbObO","sOObbbbbbO.",".ObbObbbbO.",".OO.O.OOO..","..O...O...."} }
-- 石像鬼：构造翼魔，灰岩 + 角 + 展翅，冷青眼。
M.gargoyle={ pal={O={0.10,0.11,0.13},b={0.42,0.44,0.50},h={0.56,0.58,0.64},d={0.28,0.30,0.36},e={0.5,0.85,0.95},w={0.34,0.36,0.42}},
 rows={"wO...OOO...Ow","wwOOObbbOOOww","wbOOhhhhhOObw","wOhbeehheebOw","wObhhhhhhhbOw",".OObhhhhhbOO.",".OOdhhhhhdOO.",".OOhhOhhhOhO.",".OOdhhhhhdOO.","..OhO...OhO..","..OO.....OO.."} }
-- 冰狼：冷蓝犬，霜毛 + 寒气眼，与 wolf 同骨不同色。
M.icewolf={ pal={O={0.12,0.16,0.22},b={0.50,0.70,0.85},h={0.70,0.88,0.98},d={0.34,0.50,0.66},e={0.6,0.95,1.0},f={0.92,0.98,1.0}},
 rows={"O.O.........","OhO.OOOO....","OhhOffffO...","OdhhhhhhhO.OO",".OhhhhhhhhhhO",".OhhhffhhhdO.","OebhhhhhhbO..",".OffhhhhffO..","..O.OO.OO.O..","..O.OO.OO...."} }
-- 熔岩兽：元素，黑岩躯壳 + 炽红裂缝 + 余烬。
M.lava={ pal={O={0.08,0.05,0.05},b={0.24,0.16,0.14},h={0.36,0.22,0.18},c={0.98,0.55,0.18},e={1.0,0.85,0.35},m={0.95,0.35,0.12}},
 rows={"...OOOOOO...","..ObbbcbbO..",".ObbcbbcbbO.","ObbbbccbbbbO","ObceObbObecO","ObbbccbcbbbO","ObmbbccbbmbO","ObbbcbbbcbbO","ObcbbbbbbcbO",".OmbbccbbmO.","..OcOOOOcO..","...O....O..."} }
-- 霜魔：元素精怪，冰晶体 + 冷白核 + 棱角。
M.frost={ pal={O={0.16,0.22,0.32},b={0.42,0.62,0.82},h={0.66,0.86,0.98},c={0.88,0.96,1.0},e={0.55,0.9,1.0}},
 rows={"....OO....",".O.OhhO.O.","OhOhcchOhO",".OhhcchhO.","OhhceechhO","OhhccccchO",".OhhcchhO.","OhO.Ohh.OO","..OhhhhO..",".O.O..O.O.","..O....O.."} }
-- 虚空兽：紫黑兽影，发光独眼 + 漂浮残体。
M.voidcat={ pal={O={0.06,0.04,0.10},b={0.30,0.18,0.42},h={0.46,0.30,0.60},e={0.75,0.5,1.0},v={0.55,0.35,0.85},s={0.85,0.65,1.0}},
 rows={"O.O......O.O",".OvO....OvO.","OhhO.OO.OhhO",".OhhObbOhhO.","OhhbbbbbbhhO","ObbbsssbbbbO","ObbsseeesbbO","ObbbsssbbbbO",".ObbbbbbbbO.","..O.OvvO.O..","...O.OO.O..."} }
-- 幼龙：chibi 小龙(沿用 dragon 那版配色，体型更小更圆)。
M.drake={ pal={O={0.28,0.10,0.10},h={0.82,0.36,0.30},e={0.98,0.85,0.32},w={0.52,0.20,0.18},b={0.95,0.6,0.3}},
 rows={"..O....O..",".OhO..OhO.",".OhhOOhhO.","OwhhhhhhwO","OheebbeehO","OwhhbbhhwO",".OhhhhhhO.","OwOhhhhOwO",".OOhhhhOO.","..OObbOO..","...O..O..."} }
sprites.M = M

-- 画一个怪物精灵，自动居中到 (cx,cy)（cx,cy 为场景像素坐标，sc 整数放大，flip 翻面）。
-- name 不在表里则退回 slime 占位（P1 补全）。返回实际用的 name。
function sprites.draw_monster(name, cx, cy, sc, flip)
    sc = sc or 4
    local m = M[name] or M.slime
    local w = #m.rows[1]*sc; local h = #m.rows*sc
    spr(m.rows, m.pal, math.floor(cx-w/2), math.floor(cy-h/2), sc, flip)
    return M[name] and name or "slime"
end

-- ── 资源节点像素精灵（树/矿/草）。画在场景像素坐标，by=地面基线。──
function sprites.draw_tree(cx, baseY, size)
    local tw=math.max(2,math.floor(size*0.16)); local th=math.floor(size*0.55)
    C(P.trunk_dk); love.graphics.rectangle("fill",cx-math.ceil(tw/2),baseY-th,tw+1,th)
    C(P.trunk);    love.graphics.rectangle("fill",cx-math.ceil(tw/2),baseY-th,tw,th)
    local r=size*0.55; local ccy=baseY-th-r*0.7
    C(P.fol_dk); love.graphics.circle("fill",cx,ccy+1,r+1)
    C(P.fol);    love.graphics.circle("fill",cx,ccy,r)
    C(P.fol_hi); love.graphics.circle("fill",cx-r*0.32,ccy-r*0.32,r*0.5)
end
function sprites.draw_bush(cx, by, s)
    C(P.fol_dk); love.graphics.circle("fill",cx,by,s+1)
    C(P.fol);    love.graphics.circle("fill",cx,by,s)
    C(P.fol_hi); love.graphics.circle("fill",cx-s*0.3,by-s*0.3,s*0.45)
end
function sprites.draw_rock(cx, by, s)
    C({0.30,0.31,0.36}); love.graphics.polygon("fill",cx-s,by, cx-s*0.4,by-s, cx+s*0.5,by-s*0.8, cx+s,by)
    C({0.42,0.43,0.48}); love.graphics.polygon("fill",cx-s*0.4,by-s, cx+s*0.1,by-s*0.5, cx-s*0.2,by-s*0.4)
end
-- 矿脉节点（暮色岩 + 矿点）
function sprites.draw_ore(cx, by, s)
    C({0.30,0.31,0.36}); love.graphics.polygon("fill",cx-s,by, cx-s*0.6,by-s, cx+s*0.4,by-s*0.85, cx+s,by)
    C({0.42,0.43,0.48}); love.graphics.polygon("fill",cx-s*0.5,by-s*0.5, cx,by-s*0.4, cx-s*0.2,by-s*0.2)
    C(P.acc); love.graphics.rectangle("fill",cx-s*0.3,by-s*0.5,2,2); love.graphics.rectangle("fill",cx+s*0.3,by-s*0.3,2,2)
end

-- ── 篝火（glow halo + logs + flame）。t 用于火苗摆动相位。──
function sprites.draw_fire(fx, fy, t)
    local f = math.sin((t or 0)*6)*1
    C(P.fire2,0.10); love.graphics.circle("fill",fx,fy,26)
    C(P.fire1,0.10); love.graphics.circle("fill",fx,fy,16)
    C(P.trunk_dk); love.graphics.rectangle("fill",fx-7,fy+3,14,3)
    C(P.fire2); love.graphics.polygon("fill",fx-4,fy+3, fx,fy-9-f, fx+4,fy+3)
    C(P.fire1); love.graphics.polygon("fill",fx-2,fy+3, fx,fy-4-f, fx+2,fy+3)
end

-- ── 主角：骨骼火柴人（代码关节驱动，大头 chibi）。从 scene_hero_ref 移植，关节角度切姿势。──
-- cx,gy 为场景像素坐标（gy=脚底地面线）。t=动画相位。
-- pose: "bow"(拉弓·战斗) | "chop"(挥工具·采集/制造/锻造，挥动相位用 t) | "rest"(坐着·休息) | "idle"。
-- chop 的工具头颜色可传 tool（不传=灰斧头），让砍柴/采矿/制造视觉略有别。
-- draw_amt(0..1): bow 姿势的拉弦量——0=松弦, 1=满拉。战斗里喂 player.atb 让弓随 ATB 张满, 发射归零=放箭手感。
local function bone(x1,y1,x2,y2,w,col)
    C(col); local d=math.sqrt((x2-x1)^2+(y2-y1)^2); local steps=math.max(2,math.ceil(d))
    for i=0,steps do local u=i/steps; love.graphics.circle("fill",x1+(x2-x1)*u,y1+(y2-y1)*u,w) end
end
-- 头（大头 chibi，无帽：肤色头 + 一撮头发 + 眼点）。所有姿势共用，hx/hy 头心。
local function draw_head(hx, hy)
    local hr=6
    C(P.outl); love.graphics.circle("fill",hx,hy,hr+0.6)
    C(P.skin); love.graphics.circle("fill",hx,hy,hr)
    -- 头发：盖住上半弧(无帽,但不秃)
    C({0.34,0.24,0.16}); love.graphics.arc("fill","pie",hx,hy,hr,math.pi*1.02,math.pi*1.98)
    C(P.outl); love.graphics.rectangle("fill",hx+2,hy-1,1,1)
end
function sprites.draw_hero(cx, gy, t, pose, tool, draw_amt)
    pose = pose or "bow"
    t = t or 0
    if pose=="rest" then
        -- 坐姿：盘腿低坐，双臂垂膝，头顶轻微呼吸。脚底地面线 gy 即臀部高度附近。
        local br=math.sin(t*1.6)*0.5
        local pelvis={cx,gy-3}; local chest={cx,gy-9-br}; local head={cx,gy-16-br}
        -- 盘起的腿（两条短折线贴地）
        bone(pelvis[1],pelvis[2],cx-6,gy-1,1.5,P.outl); bone(cx-6,gy-1,cx-9,gy,1.5,P.outl)
        bone(pelvis[1],pelvis[2],cx+6,gy-1,1.5,P.outl); bone(cx+6,gy-1,cx+9,gy,1.5,P.outl)
        bone(pelvis[1],pelvis[2],chest[1],chest[2],1.7,P.outl)
        -- 双臂松垂搭在膝上
        bone(chest[1],chest[2],cx-5,gy-7,1.3,P.outl); bone(cx-5,gy-7,cx-7,gy-3,1.3,P.skin)
        bone(chest[1],chest[2],cx+5,gy-7,1.3,P.outl); bone(cx+5,gy-7,cx+7,gy-3,1.3,P.skin)
        draw_head(head[1],head[2])
        love.graphics.setLineWidth(1)
        return
    end
    local br=math.sin(t*2)*0.6
    local pelvis={cx,gy-12}; local chest={cx,gy-19-br}; local head={cx,gy-27-br}
    local sh={cx,gy-19-br}
    local kL={cx-3,gy-6}; local fL={cx-5,gy}; local kR={cx+3,gy-6}; local fR={cx+4,gy}
    bone(pelvis[1],pelvis[2],kL[1],kL[2],1.4,P.outl); bone(kL[1],kL[2],fL[1],fL[2],1.4,P.outl)
    bone(pelvis[1],pelvis[2],kR[1],kR[2],1.4,P.outl); bone(kR[1],kR[2],fR[1],fR[2],1.4,P.outl)
    bone(pelvis[1],pelvis[2],chest[1],chest[2],1.7,P.outl)
    if pose=="chop" then
        -- 挥工具：后臂稳扶身前，前臂随相位上下抡（高举→下劈），手里握长柄工具。
        local amt=math.sin(t)*0.5+0.5            -- 0=高举 1=下劈
        local ang=-2.1+amt*1.6                   -- 抡动角度（从斜上举到斜下劈）
        local elb={cx+4,gy-18-br}
        local hand={elb[1]+math.cos(ang)*6, elb[2]+math.sin(ang)*6}
        bone(sh[1],sh[2],cx-3,gy-16-br,1.3,P.outl); bone(cx-3,gy-16-br,cx-4,gy-11,1.3,P.skin)  -- 后臂垂扶
        bone(sh[1],sh[2],elb[1],elb[2],1.3,P.outl); bone(elb[1],elb[2],hand[1],hand[2],1.3,P.skin)  -- 前臂抡
        draw_head(head[1],head[2])
        -- 工具：木柄 + 头（tool 给头色，默认钢灰）
        local tx,ty=hand[1]+math.cos(ang)*9, hand[2]+math.sin(ang)*9
        bone(hand[1],hand[2],tx,ty,1.3,{0.5,0.36,0.22})
        C(tool or {0.78,0.8,0.86}); love.graphics.circle("fill",tx,ty,2.2)
        C(P.outl); love.graphics.circle("line",tx,ty,2.2)
        love.graphics.setLineWidth(1)
        return
    end
    -- 默认/idle/bow：拉弓持弓。draw_amt 控拉弦量：满拉时后手(扣弦手)往后拉、上半身微沉。
    local da = math.max(0, math.min(1, draw_amt or (pose=="bow" and 0.5 or 0)))
    local fElb={cx+5,gy-19-br}; local fHand={cx+10,gy-22-br}
    local bElb={cx-4-da*2,gy-18-br}; local bHand={cx-2-da*4,gy-20-br}   -- 后手随拉弦后移
    bone(sh[1],sh[2],fElb[1],fElb[2],1.3,P.outl); bone(fElb[1],fElb[2],fHand[1],fHand[2],1.3,P.skin)
    bone(sh[1],sh[2],bElb[1],bElb[2],1.3,P.outl); bone(bElb[1],bElb[2],bHand[1],bHand[2],1.3,P.skin)
    draw_head(head[1],head[2])
    -- 弓 + 弦 + 搭箭（弦被后手拉成尖角，张力越大尖角越深）
    C({0.55,0.37,0.20}); love.graphics.setLineStyle("smooth"); love.graphics.setLineWidth(1.4)
    love.graphics.arc("line","open",fHand[1],fHand[2],6,-1.35,1.35)
    C({0.85,0.83,0.7}); love.graphics.setLineWidth(0.8)
    local t1x,t1y=fHand[1]+6*math.cos(-1.35),fHand[2]+6*math.sin(-1.35)
    local t2x,t2y=fHand[1]+6*math.cos(1.35), fHand[2]+6*math.sin(1.35)
    love.graphics.line(t1x,t1y, bHand[1],bHand[2], t2x,t2y)
    if pose=="bow" then
        -- 搭在弦上的箭：箭尾跟后手, 满拉时箭簇仍贴弓口(蓄势待发)
        C(P.acc); love.graphics.setLineWidth(1); love.graphics.line(bHand[1],bHand[2], fHand[1]+5,fHand[2])
        love.graphics.polygon("fill", fHand[1]+6,fHand[2], fHand[1]+3,fHand[2]-1.5, fHand[1]+3,fHand[2]+1.5)
    end
    love.graphics.setLineWidth(1)
end

-- ── 草药节点（双叶丛 + 花）。by=地面基线，s=大小。──
function sprites.draw_herb(cx, by, s)
    C(P.fol_dk); love.graphics.ellipse("fill",cx-s*0.5,by-s*0.3,s*0.55,s)
    C(P.fol);    love.graphics.ellipse("fill",cx+s*0.5,by-s*0.3,s*0.55,s)
    C(P.fol_hi); love.graphics.ellipse("fill",cx-s*0.4,by-s*0.6,s*0.3,s*0.5)
    C({0.92,0.6,0.78}); love.graphics.circle("fill",cx-s*0.5,by-s*1.0,1.4); love.graphics.circle("fill",cx+s*0.5,by-s*0.9,1.4)
end

-- ── 采集节点本体（按大类 wood/ore/herb 选树/矿/草），带受击白闪/砍击放大/淡出。──
-- nx 节点中心 x，by=地面基线 y（场景像素坐标）。flash>0 时整体覆白；hurt 放大；alpha 淡出。
function sprites.draw_node(mat, nx, by, flash, hurt, alpha)
    alpha = alpha or 1
    local sc = 1 + (hurt or 0)*0.4
    if (flash or 0) > 0 then
        -- 受击白闪：用一块覆盖矩形近似（与 combat 敌人白闪同套路）
        love.graphics.setColor(1,1,1,alpha)
        local w = (mat=="ore") and 30 or 26; local h=(mat=="wood") and 44 or 24
        love.graphics.rectangle("fill", nx-w/2, by-h, w, h)
        return
    end
    love.graphics.setColor(1,1,1,alpha)
    if mat=="wood" then sprites.draw_tree(nx, by, 36*sc)
    elseif mat=="ore" then sprites.draw_ore(nx, by, 14*sc)
    else sprites.draw_herb(nx, by, 9*sc) end
    love.graphics.setColor(1,1,1,1)
end

-- ── 工作台（制造）：木台面 + 台腿 + 台上工具(锤/料)。bx 台中心 x，by 地面基线。──
function sprites.draw_bench(bx, by)
    C(P.trunk_dk); love.graphics.rectangle("fill",bx-13,by-6,4,6); love.graphics.rectangle("fill",bx+9,by-6,4,6)  -- 腿
    C(P.trunk);    love.graphics.rectangle("fill",bx-15,by-11,30,5)                                                -- 台面
    C(P.dirt_hi);  love.graphics.rectangle("fill",bx-15,by-11,30,1)                                                -- 台面高光
    C({0.78,0.8,0.86}); love.graphics.rectangle("fill",bx+2,by-15,2,4)                                            -- 立着的料/锤柄
    C({0.5,0.36,0.22}); love.graphics.rectangle("fill",bx-9,by-13,7,2)                                            -- 横放木料
end

-- ── 铁砧（锻造）：铁砧轮廓 + 砧上炽红坯料。ax 砧中心 x，by 地面基线。t=辉光相位。──
function sprites.draw_anvil(ax, by, t)
    local g = math.sin((t or 0)*6)*0.15+0.85
    C({0.10,0.10,0.13}); love.graphics.rectangle("fill",ax-5,by-8,10,8)        -- 砧座
    C({0.24,0.25,0.30}); love.graphics.rectangle("fill",ax-9,by-13,18,5)        -- 砧台
    C({0.34,0.35,0.40}); love.graphics.rectangle("fill",ax-9,by-13,18,1)        -- 砧台高光
    C({0.24,0.25,0.30}); love.graphics.polygon("fill",ax+9,by-13, ax+14,by-11, ax+9,by-9)  -- 砧角
    C(P.fire2,0.25*g); love.graphics.circle("fill",ax-2,by-15,6)                -- 坯料辉光
    C({1.0,0.55*g,0.2}); love.graphics.rectangle("fill",ax-4,by-15,5,2)         -- 炽红坯料
end

return sprites
