-- ============================================================================
-- view/sprites —— 像素世界精灵库（在低分场景画布的像素坐标里画，整体由 screen 放大）。
-- 收纳：主角 draw_hero（骨骼火柴人，代码关节非PNG，chibi 大头，从 scene_hero_ref 移植）
--      + 怪物像素精灵 M{}/spr（从 monsters_ref 移植，全彩暮色调）
--      + 资源节点像素精灵（树/矿/草）+ 通用 draw_sprite / spr API。
-- 纯绘制，无状态：所有动画相位由调用方传入。坐标都是场景画布像素（240x400），不乘 screen.sw。
-- 依赖：love + data(D.PIX 调色)。
-- ============================================================================
local D = require("data")
local P = D.PIX

local sprites = {}

local function C(c,a) love.graphics.setColor(c[1],c[2],c[3],a or c[4] or 1) end
local function lerp(a,b,t) return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t} end

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

-- ── 主角：骨骼火柴人（代码关节驱动，大头 chibi，拉弓姿势 + 呼吸）。从 scene_hero_ref 移植。──
-- cx,gy 为场景像素坐标（gy=脚底地面线）。t=动画相位。pose: "bow"(拉弓) | "idle"。
local function bone(x1,y1,x2,y2,w,col)
    C(col); local d=math.sqrt((x2-x1)^2+(y2-y1)^2); local steps=math.max(2,math.ceil(d))
    for i=0,steps do local u=i/steps; love.graphics.circle("fill",x1+(x2-x1)*u,y1+(y2-y1)*u,w) end
end
function sprites.draw_hero(cx, gy, t, pose)
    pose = pose or "bow"
    t = t or 0
    local br=math.sin(t*2)*0.6
    local pelvis={cx,gy-12}; local chest={cx,gy-19-br}; local head={cx,gy-27-br}; local hr=6
    local sh={cx,gy-19-br}
    local fElb={cx+5,gy-19-br}; local fHand={cx+10,gy-22-br}
    local bElb={cx-4,gy-18-br}; local bHand={cx-2,gy-20-br}
    local kL={cx-3,gy-6}; local fL={cx-5,gy}; local kR={cx+3,gy-6}; local fR={cx+4,gy}
    bone(pelvis[1],pelvis[2],kL[1],kL[2],1.4,P.outl); bone(kL[1],kL[2],fL[1],fL[2],1.4,P.outl)
    bone(pelvis[1],pelvis[2],kR[1],kR[2],1.4,P.outl); bone(kR[1],kR[2],fR[1],fR[2],1.4,P.outl)
    bone(pelvis[1],pelvis[2],chest[1],chest[2],1.7,P.outl)
    bone(sh[1],sh[2],fElb[1],fElb[2],1.3,P.outl); bone(fElb[1],fElb[2],fHand[1],fHand[2],1.3,P.skin)
    bone(sh[1],sh[2],bElb[1],bElb[2],1.3,P.outl); bone(bElb[1],bElb[2],bHand[1],bHand[2],1.3,P.skin)
    C(P.outl); love.graphics.circle("fill",head[1],head[2],hr+0.6)
    C(P.skin); love.graphics.circle("fill",head[1],head[2],hr)
    C(P.hood); love.graphics.arc("fill","pie",head[1],head[2],hr+0.8,math.pi*1.05,math.pi*1.95)
    C(P.hood_hi); love.graphics.arc("fill","pie",head[1],head[2],hr-1,math.pi*1.15,math.pi*1.5)
    C(P.outl); love.graphics.rectangle("fill",head[1]+2,head[2]-1,1,1)
    -- 弓 + 弦 + 搭箭
    C({0.55,0.37,0.20}); love.graphics.setLineStyle("smooth"); love.graphics.setLineWidth(1.4)
    love.graphics.arc("line","open",fHand[1],fHand[2],6,-1.35,1.35)
    C({0.85,0.83,0.7}); love.graphics.setLineWidth(0.8)
    local t1x,t1y=fHand[1]+6*math.cos(-1.35),fHand[2]+6*math.sin(-1.35)
    local t2x,t2y=fHand[1]+6*math.cos(1.35), fHand[2]+6*math.sin(1.35)
    love.graphics.line(t1x,t1y, bHand[1],bHand[2], t2x,t2y)
    if pose=="bow" then
        C(P.acc); love.graphics.setLineWidth(1); love.graphics.line(bHand[1],bHand[2], fHand[1]+5,fHand[2])
        love.graphics.polygon("fill", fHand[1]+6,fHand[2], fHand[1]+3,fHand[2]-1.5, fHand[1]+3,fHand[2]+1.5)
    end
    love.graphics.setLineWidth(1)
end

return sprites
