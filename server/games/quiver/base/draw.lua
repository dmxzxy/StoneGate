-- ============================================================================
-- base/draw —— 无状态绘制原语 + 图标库 + 字体句柄。
-- 依赖：love(画) + base/screen(sx/sy/sw/sh) + data(UI 颜色 / MAT_COLOR)。
-- 不依赖任何游戏态(player/enemy/SKILLS…)：技能/材料等数据由调用方作参数传入。
-- 字体句柄(font/font_sm/font_med/font_big)在这里持有，由 base/assets.load_fonts 写回。
-- ============================================================================
local screen = require("base.screen")
local D = require("data")
local UI = D.UI
local MAT_COLOR = D.MAT_COLOR

local draw = {}

-- 缩放助手（与 screen 共享同一份 sw/sh，现读现算）
local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end

-- 字体句柄：由 assets.load_fonts() 在 love.load 阶段写回；绘制时现取。
draw.font, draw.font_sm, draw.font_med, draw.font_big = nil, nil, nil, nil
function draw.set_fonts(f, fsm, fmed, fbig)
    draw.font, draw.font_sm, draw.font_med, draw.font_big = f, fsm, fmed, fbig
end

-- 动画时钟：纯展示用相位（不是游戏态），主循环每帧写 draw.t；draw_archer 待机呼吸用它。
draw.t = 0

-- ---- 基础原语 ----
function draw.setc(c,a) love.graphics.setColor(c[1],c[2],c[3],a or c[4] or 1) end
local setc = draw.setc

function draw.rrect(m,x,y,w,h,r) love.graphics.rectangle(m,x,y,w,h,r or 6*screen.sw,r or 6*screen.sw) end
local rrect = draw.rrect

function draw.panel(x,y,w,h,fill,border,r)
    setc(fill or UI.panel); rrect("fill",x,y,w,h,r or 8*screen.sw)
    love.graphics.setColor(1,1,1,0.04); rrect("fill",x,y,w,h*0.42,r or 8*screen.sw)
    if border then setc(border); love.graphics.setLineWidth(math.max(1,1.3*screen.sw)); rrect("line",x,y,w,h,r or 8*screen.sw); love.graphics.setLineWidth(1) end
end
local panel = draw.panel

function draw.button(x,y,w,h,label,col,enabled,fnt)
    col=col or UI.btn; if enabled==false then col={col[1]*0.35,col[2]*0.35,col[3]*0.4} end
    setc(col); rrect("fill",x,y,w,h,6*screen.sw); love.graphics.setColor(1,1,1,0.16); rrect("fill",x+6*screen.sw,y+1.5*screen.sh,w-12*screen.sw,h*0.34)
    love.graphics.setColor(0,0,0,0.22); rrect("fill",x,y+h-3*screen.sh,w,3*screen.sh,6*screen.sw)
    fnt=fnt or draw.font; love.graphics.setFont(fnt); setc(enabled==false and UI.dim or UI.text); love.graphics.printf(label,x,y+(h-fnt:getHeight())/2,w,"center")
end

function draw.bar(x,y,w,h,frac,col,label)
    frac=math.max(0,math.min(1,frac)); love.graphics.setColor(0,0,0,0.5); rrect("fill",x,y,w,h,h/2)
    if frac>0 then setc(col); rrect("fill",x,y,math.max(h,w*frac),h,h/2); love.graphics.setColor(1,1,1,0.2); rrect("fill",x+h/2,y+1.5*screen.sh,math.max(0,w*frac-h),h*0.3,h*0.2) end
    if label then love.graphics.setFont(draw.font_sm); love.graphics.setColor(1,1,1,0.95); love.graphics.printf(label,x,y+(h-draw.font_sm:getHeight())/2,w,"center") end
end

function draw.mat_chip(m, x, y, s) setc(MAT_COLOR[m]); rrect("fill",x-s,y-s,s*2,s*2,s*0.4); love.graphics.setColor(0,0,0,0.3); rrect("line",x-s,y-s,s*2,s*2,s*0.4) end

-- 面板标题栏右上角 X 关闭键（视觉）。命中矩形由调用方按同一坐标判定。
-- px,py,pw 为面板左上+宽；返回该键矩形 x,y,w,h 供命中复用。
function draw.close_x(px,py,pw)
    local s=28*screen.sw; local x=px+pw-s-10*screen.sw; local y=py+8*screen.sh
    setc({0.22,0.12,0.14,0.9}); rrect("fill",x,y,s,s,5*screen.sw)
    setc({0.55,0.25,0.28}); love.graphics.setLineWidth(math.max(1,1.2*screen.sw)); rrect("line",x,y,s,s,5*screen.sw)
    setc({0.9,0.6,0.6}); love.graphics.setLineWidth(math.max(2,2.2*screen.sw))
    local p=s*0.3
    love.graphics.line(x+p,y+p, x+s-p,y+s-p); love.graphics.line(x+s-p,y+p, x+p,y+s-p)
    love.graphics.setLineWidth(1)
    return x,y,s,s
end

-- 命中 X 关闭键：与 close_x 同坐标。px,py,pw 同上，(mx,my) 为指针。
function draw.hit_close_x(mx,my,px,py,pw)
    local s=28*screen.sw; local x=px+pw-s-10*screen.sw; local y=py+8*screen.sh
    return mx>=x and mx<=x+s and my>=y and my<=y+s
end

-- 进度圆环（替代部分文字进度）
function draw.ring(cx,cy,r,frac,col)
    setc({1,1,1,0.1}); love.graphics.setLineWidth(sx(3)); love.graphics.circle("line",cx,cy,r)
    setc(col); love.graphics.arc("line","open",cx,cy,r,-math.pi/2,-math.pi/2+math.pi*2*math.max(0,math.min(1,frac))); love.graphics.setLineWidth(1)
end

-- ============================================================================
-- 图标（用图形代替文字）
-- ============================================================================
function draw.icon_mat(m, cx, cy, s)
    if m=="wood" then
        setc({0.55,0.38,0.2}); love.graphics.rectangle("fill",cx-s,cy-s*0.55,s*2,s*1.1,s*0.4)
        setc({0.72,0.52,0.3}); love.graphics.circle("fill",cx+s*0.7,cy,s*0.42); setc({0.45,0.3,0.16}); love.graphics.circle("line",cx+s*0.7,cy,s*0.42)
    elseif m=="ore" then
        setc({0.5,0.52,0.58}); love.graphics.polygon("fill",cx-s,cy+s*0.6,cx-s*0.4,cy-s,cx+s*0.6,cy-s*0.7,cx+s,cy+s*0.6)
        setc({0.85,0.87,0.95}); love.graphics.circle("fill",cx-s*0.1,cy-s*0.05,s*0.22); love.graphics.circle("fill",cx+s*0.4,cy+s*0.2,s*0.14)
    else -- herb
        setc({0.4,0.7,0.35}); love.graphics.ellipse("fill",cx-s*0.45,cy-s*0.1,s*0.5,s*0.95); love.graphics.ellipse("fill",cx+s*0.45,cy-s*0.1,s*0.5,s*0.95)
        setc({0.3,0.5,0.22}); love.graphics.setLineWidth(math.max(1,1.4*screen.sw)); love.graphics.line(cx,cy-s,cx,cy+s); love.graphics.setLineWidth(1)
    end
end
local icon_mat = draw.icon_mat

function draw.icon_arrow(cx, cy, s, col)
    -- 斜 45° 箭：细杆 + 三角箭头 + 尾羽，更像物品图标
    local c=col or {0.8,0.8,0.85}
    local d=0.7071  -- cos45
    local tx,ty = cx+s*d, cy-s*d        -- 箭尖(右上)
    local bx,by = cx-s*d, cy+s*d        -- 箭尾(左下)
    setc({0.55,0.4,0.25}); love.graphics.setLineWidth(math.max(1.5,s*0.22))  -- 木杆
    love.graphics.line(bx,by,tx-s*0.28*d,ty+s*0.28*d)
    -- 箭头(三角)
    setc(c)
    local hx,hy = tx,ty
    love.graphics.polygon("fill", hx,hy, hx-s*0.5*d+s*0.22*d, hy+s*0.5*d+s*0.22*d, hx-s*0.5*d-s*0.22*d, hy+s*0.5*d-s*0.22*d)
    -- 尾羽(两片)
    setc({0.85,0.85,0.9}); love.graphics.setLineWidth(math.max(1,s*0.16))
    love.graphics.line(bx,by, bx+s*0.34, by-s*0.04); love.graphics.line(bx,by, bx+s*0.04, by-s*0.34)
    love.graphics.setLineWidth(1)
end
local icon_arrow = draw.icon_arrow

function draw.icon_coin(cx,cy,r)
    setc({0.78,0.58,0.12}); love.graphics.circle("fill",cx,cy,r)
    setc(UI.gold); love.graphics.circle("fill",cx,cy,r*0.7)
    setc({1,1,1,0.5}); love.graphics.circle("fill",cx-r*0.25,cy-r*0.25,r*0.18)
end

-- 药瓶图标（圆肚 + 细颈 + 瓶塞），col=药液色
function draw.icon_potion(cx,cy,s,col)
    col=col or {0.9,0.35,0.4}
    setc({0.5,0.36,0.22}); love.graphics.rectangle("fill",cx-s*0.22,cy-s*1.1,s*0.44,s*0.32,s*0.1)  -- 瓶塞
    setc({0.85,0.9,0.95,0.5}); love.graphics.rectangle("fill",cx-s*0.18,cy-s*0.8,s*0.36,s*0.45)      -- 瓶颈(玻璃)
    setc(col); love.graphics.circle("fill",cx,cy+s*0.15,s*0.62)                                       -- 圆肚药液
    setc({1,1,1,0.35}); love.graphics.circle("fill",cx-s*0.22,cy-s*0.05,s*0.16)                       -- 高光
end

-- 槽位类型图标（武器/箭袋/防具/首饰，4 种线描）
function draw.icon_kind(kind, cx, cy, s, col)
    setc(col); love.graphics.setLineWidth(math.max(1,1.6*screen.sw))
    if kind=="weapon" then
        love.graphics.arc("line","open",cx-s*0.2,cy,s,-1.0,1.0)
        love.graphics.line(cx-s*0.2+s*math.cos(-1.0),cy+s*math.sin(-1.0), cx-s*0.2+s*math.cos(1.0),cy+s*math.sin(1.0))
    elseif kind=="quiver" then
        love.graphics.polygon("line", cx-s*0.5,cy-s, cx+s*0.5,cy-s, cx+s*0.35,cy+s, cx-s*0.35,cy+s)
        love.graphics.line(cx-s*0.2,cy-s,cx-s*0.2,cy-s*1.4); love.graphics.line(cx+s*0.2,cy-s,cx+s*0.2,cy-s*1.4)
    elseif kind=="armor" then
        love.graphics.polygon("line", cx,cy-s, cx+s*0.9,cy-s*0.4, cx+s*0.6,cy+s, cx,cy+s*1.1, cx-s*0.6,cy+s, cx-s*0.9,cy-s*0.4)
    else
        love.graphics.polygon("line", cx,cy-s, cx+s*0.8,cy, cx,cy+s, cx-s*0.8,cy)
    end
    love.graphics.setLineWidth(1)
end

-- ============================================================================
-- 火柴人 / 技能图标 / 资源节点本体（无状态：所有动画相位由调用方传入）
-- ============================================================================
-- 经典细线火柴人：细线条 + 圆头 + 明确关节坐标。pose: idle | bow | chop。
-- phase 为动画相位（待机呼吸/挥砍）；调用方不传则用 draw.t（纯展示时钟，非游戏态）。
function draw.draw_archer(px, py, pose, phase)
    pose = pose or "idle"
    phase = phase or draw.t
    local breathe = math.sin(phase*2)*sy(1.2)
    py = py + breathe
    local R    = sx(7)            -- 头半径
    local LW   = math.max(2, sx(2))   -- 细线，约 2px
    local skin = {0.92,0.78,0.62}
    local ink  = {0.82,0.85,0.92}     -- 身体线条（浅色细线，灵动）

    -- 关节坐标
    local footL = { px-sx(8), py }
    local footR = { px+sx(8), py }
    local hip   = { px, py-sy(26) }
    local neck  = { px, py-sy(46) }
    local head  = { px, py-sy(54) }

    love.graphics.push("all")
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineWidth(LW)
    love.graphics.setLineJoin("bevel")
    setc(ink)

    -- 腿（带膝盖中继点，轻微弯曲）
    local kneeL={px-sx(5),py-sy(13)}; local kneeR={px+sx(5),py-sy(13)}
    love.graphics.line(hip[1],hip[2], kneeL[1],kneeL[2], footL[1],footL[2])
    love.graphics.line(hip[1],hip[2], kneeR[1],kneeR[2], footR[1],footR[2])
    -- 躯干
    love.graphics.line(hip[1],hip[2], neck[1],neck[2])

    -- 手臂
    if pose=="bow" then
        -- 前臂水平持弓，后臂拉弦到脸侧
        local fx,fy = px+sx(20), neck[2]+sy(1)
        local dx,dy = px-sx(2), neck[2]+sy(4)
        love.graphics.line(neck[1],neck[2], px+sx(11),neck[2]+sy(2), fx,fy)   -- 前臂(带肘)
        love.graphics.line(neck[1],neck[2], dx,dy)                            -- 后臂
        -- 弓
        setc({0.66,0.48,0.22}); love.graphics.setLineWidth(math.max(2,sx(2)))
        love.graphics.arc("line","open",fx,fy,sx(13),-1.3,1.3)
        setc({0.9,0.88,0.8}); love.graphics.setLineWidth(math.max(1,sx(1)))
        love.graphics.line(fx+sx(13)*math.cos(-1.3),fy+sx(13)*math.sin(-1.3), dx,dy, fx+sx(13)*math.cos(1.3),fy+sx(13)*math.sin(1.3))
    elseif pose=="chop" then
        -- 一臂随相位抡工具，一臂自然垂
        local amt=math.sin(phase)*0.5+0.5; local ang=-1.3+amt*1.2
        local ex,ey = px+sx(8), neck[2]+sy(6)                                  -- 肘
        local hx,hy = ex+math.cos(ang)*sx(16), ey+math.sin(ang)*sy(16)         -- 手
        love.graphics.line(neck[1],neck[2], ex,ey, hx,hy)
        love.graphics.line(neck[1],neck[2], px-sx(8),neck[2]+sy(14))
        -- 工具：柄 + 头
        local tx,ty = hx+math.cos(ang)*sx(14), hy+math.sin(ang)*sy(14)
        setc({0.5,0.36,0.22}); love.graphics.setLineWidth(math.max(2,sx(2.4))); love.graphics.line(hx,hy,tx,ty)
        setc({0.8,0.82,0.88}); love.graphics.circle("fill",tx,ty,sx(3.5))
    else
        -- 待机：双臂自然垂（带轻微肘弯）
        love.graphics.line(neck[1],neck[2], px-sx(9),neck[2]+sy(11), px-sx(7),neck[2]+sy(20))
        love.graphics.line(neck[1],neck[2], px+sx(9),neck[2]+sy(11), px+sx(7),neck[2]+sy(20))
    end

    -- 头（实心 + 细描边）
    setc(skin); love.graphics.circle("fill", head[1],head[2], R)
    setc(ink); love.graphics.setLineWidth(math.max(1,sx(1.2))); love.graphics.circle("line", head[1],head[2], R)

    love.graphics.pop()
end

-- 技能图标（按 effect 画简单符号），用于战斗技能栏与技能大师。s 为技能数据(含 color/effect)。
function draw.draw_skill_icon(s, cx, cy, sz)
    local c = s.color
    if s.effect=="shot" then icon_arrow(cx, cy, sz, c)
    elseif s.effect=="dot" then icon_arrow(cx, cy, sz, c); setc({0.5,0.9,0.4}); love.graphics.circle("fill", cx+sz*0.5, cy-sz*0.5, sz*0.28)
    elseif s.effect=="heal" then setc(c); love.graphics.rectangle("fill",cx-sz*0.18,cy-sz*0.7,sz*0.36,sz*1.4,sz*0.1); love.graphics.rectangle("fill",cx-sz*0.7,cy-sz*0.18,sz*1.4,sz*0.36,sz*0.1)
    else setc(c); love.graphics.circle("line",cx,cy,sz*0.7); love.graphics.setLineWidth(math.max(1,sx(1.5))); love.graphics.line(cx,cy-sz*0.7,cx,cy+sz*0.7); love.graphics.line(cx-sz*0.7,cy,cx+sz*0.7,cy); love.graphics.setLineWidth(1) end
end

-- 画资源节点本体（按 mat 选树/矿/草），带受击白闪/放大/淡出
function draw.draw_node_body(mat, nx, ny, flash, hurt, alpha)
    alpha = alpha or 1; local sc = 1 + (hurt or 0)*0.3; local white = (flash or 0) > 0
    if mat=="wood" then
        if white then love.graphics.setColor(1,1,1,alpha) else setc({0.35,0.25,0.15},alpha) end
        love.graphics.rectangle("fill",nx-sx(6)*sc,ny-sy(46)*sc,sx(12)*sc,sy(46)*sc)
        if white then love.graphics.setColor(1,1,1,alpha) else setc({0.2,0.5,0.25},alpha) end
        love.graphics.circle("fill",nx,ny-sy(56)*sc,sx(30)*sc)
        if not white then setc({0.16,0.42,0.2},alpha); love.graphics.circle("fill",nx-sx(12)*sc,ny-sy(48)*sc,sx(16)*sc) end
    elseif mat=="ore" then
        if white then love.graphics.setColor(1,1,1,alpha) else setc({0.42,0.44,0.5},alpha) end
        love.graphics.polygon("fill",nx-sx(30)*sc,ny,nx-sx(16)*sc,ny-sy(38)*sc,nx+sx(12)*sc,ny-sy(32)*sc,nx+sx(30)*sc,ny)
        if not white then setc({0.7,0.72,0.78},alpha); love.graphics.circle("fill",nx-sx(4),ny-sy(16),sx(5)); love.graphics.circle("fill",nx+sx(10),ny-sy(22),sx(4)) end
    else
        if white then love.graphics.setColor(1,1,1,alpha) else setc({0.2,0.45,0.2},alpha) end
        love.graphics.circle("fill",nx,ny-sy(12)*sc,sx(22)*sc)
        if not white then setc({0.9,0.6,0.8},alpha); love.graphics.circle("fill",nx-sx(9),ny-sy(16),sx(5)); love.graphics.circle("fill",nx+sx(8),ny-sy(9),sx(5)) end
    end
end

return draw
