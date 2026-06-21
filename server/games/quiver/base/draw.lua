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

-- 像素扁平：硬直角矩形（忽略圆角参数 r —— 保住硬边像素观感）。签名保持不变，调用方无需改。
function draw.rrect(m,x,y,w,h,r) love.graphics.rectangle(m,x,y,w,h) end
local rrect = draw.rrect

-- 1px(随缩放最少 1px)硬描边的整数线宽
local function px(v) return math.max(1, math.floor(v*screen.sw+0.5)) end

-- 面板：实色填充 + 1px 硬描边 + 顶部一条简单高光带（无圆角/阴影/渐变）
function draw.panel(x,y,w,h,fill,border,r)
    setc(fill or UI.panel); love.graphics.rectangle("fill",x,y,w,h)
    love.graphics.setColor(1,1,1,0.05); love.graphics.rectangle("fill",x+px(1),y+px(1),w-px(2),px(2))  -- 顶高光条
    setc(border or UI.line); love.graphics.setLineWidth(px(1)); love.graphics.rectangle("line",x,y,w,h); love.graphics.setLineWidth(1)
end
local panel = draw.panel

-- 按钮：实色填充 + 顶高光条 + 底暗边 + 1px 硬描边
function draw.button(x,y,w,h,label,col,enabled,fnt)
    col=col or UI.btn; if enabled==false then col={col[1]*0.35,col[2]*0.35,col[3]*0.4} end
    setc(col); love.graphics.rectangle("fill",x,y,w,h)
    love.graphics.setColor(1,1,1,0.16); love.graphics.rectangle("fill",x+px(1),y+px(1),w-px(2),px(2))      -- 顶高光
    love.graphics.setColor(0,0,0,0.28); love.graphics.rectangle("fill",x+px(1),y+h-px(2),w-px(2),px(2))     -- 底暗边
    setc({col[1]*1.4,col[2]*1.4,col[3]*1.4}); love.graphics.setLineWidth(px(1)); love.graphics.rectangle("line",x,y,w,h); love.graphics.setLineWidth(1)
    fnt=fnt or draw.font; love.graphics.setFont(fnt); setc(enabled==false and UI.dim or UI.text); love.graphics.printf(label,x,y+(h-fnt:getHeight())/2,w,"center")
end

-- 进度条：黑槽 + 实色填充 + 顶高光条 + 1px 硬描边（无圆头/渐变）
function draw.bar(x,y,w,h,frac,col,label)
    frac=math.max(0,math.min(1,frac))
    love.graphics.setColor(0,0,0,0.6); love.graphics.rectangle("fill",x,y,w,h)
    if frac>0 then
        local fw=math.max(px(1),w*frac); setc(col); love.graphics.rectangle("fill",x,y,fw,h)
        love.graphics.setColor(1,1,1,0.22); love.graphics.rectangle("fill",x,y+px(1),fw,px(1))
    end
    setc(UI.line); love.graphics.setLineWidth(px(1)); love.graphics.rectangle("line",x,y,w,h); love.graphics.setLineWidth(1)
    if label then love.graphics.setFont(draw.font_sm); love.graphics.setColor(1,1,1,0.95); love.graphics.printf(label,x,y+(h-draw.font_sm:getHeight())/2,w,"center") end
end

function draw.mat_chip(m, x, y, s) setc(MAT_COLOR[m]); rrect("fill",x-s,y-s,s*2,s*2,s*0.4); love.graphics.setColor(0,0,0,0.3); rrect("line",x-s,y-s,s*2,s*2,s*0.4) end

-- 像素宝石/稀有度色块：硬边方块 + 左上 1px 高光 + 黑描边（替代抗锯齿圆点，保住像素观感）。
-- (cx,cy)=中心，s=半边长。col=稀有度色。整数对齐。
function draw.gem(cx, cy, s, col)
    local x=math.floor(cx-s+0.5); local y=math.floor(cy-s+0.5); local w=math.max(2,math.floor(s*2+0.5)); local d=px(1)
    setc(col); love.graphics.rectangle("fill",x,y,w,w)
    love.graphics.setColor(1,1,1,0.45); love.graphics.rectangle("fill",x+d,y+d,math.max(d,w*0.4),d)  -- 左上高光
    love.graphics.setColor(0,0,0,0.4); love.graphics.setLineWidth(d); love.graphics.rectangle("line",x,y,w,w); love.graphics.setLineWidth(1)
end

-- 像素物品槽：硬边方格 + 内陷斜面(左上暗/右下亮 1px) + 实色描边。
-- 空槽用深底+灰边；有物品时底色取 border 的极暗版、边用 border(稀有度色)。
-- pip>0 时在右上角画 pip 个 1px 稀有度方块(稀有度档位指示，史诗/传说一眼可辨)。
-- 整数对齐 + px(1) 描边，保住硬边像素观感。坐标/尺寸不变（命中沿用调用方矩形）。
function draw.slot(x,y,s,border,filled,pip)
    x=math.floor(x+0.5); y=math.floor(y+0.5); s=math.floor(s+0.5)
    local b = border or {0.24,0.25,0.32}
    local fill = filled and {b[1]*0.16,b[2]*0.16,b[3]*0.18,0.96} or {0.08,0.09,0.13,0.94}
    setc(fill); love.graphics.rectangle("fill",x,y,s,s)
    -- 内陷斜面：上/左 一道暗线，下/右 一道亮线 → 凹槽手感
    local d=px(1)
    love.graphics.setColor(0,0,0,0.34); love.graphics.rectangle("fill",x+d,y+d,s-2*d,d); love.graphics.rectangle("fill",x+d,y+d,d,s-2*d)
    love.graphics.setColor(1,1,1,filled and 0.12 or 0.05); love.graphics.rectangle("fill",x+d,y+s-2*d,s-2*d,d); love.graphics.rectangle("fill",x+s-2*d,y+d,d,s-2*d)
    -- 硬边描边
    setc(b); love.graphics.setLineWidth(d); love.graphics.rectangle("line",x,y,s,s); love.graphics.setLineWidth(1)
    -- 稀有度角标 pip（右上连排小方块）
    if pip and pip>0 then
        local ps=math.max(2,px(3)); setc(b)
        for i=1,pip do love.graphics.rectangle("fill", x+s-d-ps - (i-1)*(ps+px(1)), y+d, ps, ps) end
    end
end

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
    -- m 可以是采集大类(wood/ore/herb)或具体材料 id(D.MAT[id])。
    -- 形状按大类(木=原木/矿=矿石/草=双叶)，颜色按材料色，再按"系"加小标记(箭簇尖角/兵刃刃纹/甲胄块面)。
    local def = D.MAT and D.MAT[m]
    local cat = def and def.cat or m
    local col = (D.MAT_COLOR and D.MAT_COLOR[m]) or nil
    if cat=="wood" then
        local c1 = col or {0.55,0.38,0.2}
        setc(c1); love.graphics.rectangle("fill",cx-s,cy-s*0.55,s*2,s*1.1,s*0.4)
        setc({math.min(1,c1[1]+0.17),math.min(1,c1[2]+0.14),math.min(1,c1[3]+0.1)}); love.graphics.circle("fill",cx+s*0.7,cy,s*0.42)
        setc({c1[1]*0.7,c1[2]*0.7,c1[3]*0.7}); love.graphics.circle("line",cx+s*0.7,cy,s*0.42)
    elseif cat=="ore" then
        local c1 = col or {0.5,0.52,0.58}
        setc(c1); love.graphics.polygon("fill",cx-s,cy+s*0.6,cx-s*0.4,cy-s,cx+s*0.6,cy-s*0.7,cx+s,cy+s*0.6)
        setc({math.min(1,c1[1]+0.25),math.min(1,c1[2]+0.25),math.min(1,c1[3]+0.25)}); love.graphics.circle("fill",cx-s*0.1,cy-s*0.05,s*0.22); love.graphics.circle("fill",cx+s*0.4,cy+s*0.2,s*0.14)
    else -- herb
        local c1 = col or {0.4,0.7,0.35}
        setc(c1); love.graphics.ellipse("fill",cx-s*0.45,cy-s*0.1,s*0.5,s*0.95); love.graphics.ellipse("fill",cx+s*0.45,cy-s*0.1,s*0.5,s*0.95)
        setc({c1[1]*0.7,c1[2]*0.7,c1[3]*0.6}); love.graphics.setLineWidth(math.max(1,1.4*screen.sw)); love.graphics.line(cx,cy-s,cx,cy+s); love.graphics.setLineWidth(1)
    end
    -- 系标记：仅具体材料显示，区分一个大类内的三系角色
    if def then
        local sys = def.system
        if sys=="head" then  -- 箭簇=右上尖角
            setc({0.95,0.95,1.0}); love.graphics.polygon("fill", cx+s*0.55,cy-s*0.85, cx+s*0.95,cy-s*0.55, cx+s*0.55,cy-s*0.45)
        elseif sys=="blade" then  -- 兵刃=斜刃纹
            setc({0.95,0.95,1.0}); love.graphics.setLineWidth(math.max(1,1.6*screen.sw)); love.graphics.line(cx-s*0.4,cy+s*0.5, cx+s*0.5,cy-s*0.5); love.graphics.setLineWidth(1)
        elseif sys=="plate" then  -- 甲胄=块面方框
            setc({0.9,0.92,1.0}); love.graphics.rectangle("line", cx-s*0.45,cy-s*0.35, s*0.9, s*0.7)
        elseif sys=="shaft" then  -- 箭杆=竖直细线
            setc({1,1,0.9}); love.graphics.setLineWidth(math.max(1,1.4*screen.sw)); love.graphics.line(cx,cy-s*0.7,cx,cy+s*0.7); love.graphics.setLineWidth(1)
        elseif sys=="bowarm" then  -- 弓臂=弧
            setc({1,1,0.9}); love.graphics.setLineWidth(math.max(1,1.4*screen.sw)); love.graphics.arc("line","open",cx,cy,s*0.7,-0.9,0.9); love.graphics.setLineWidth(1)
        elseif sys=="char" then  -- 薪炭=小火点
            setc({1,0.6,0.2}); love.graphics.circle("fill",cx,cy-s*0.5,s*0.18)
        elseif sys=="essence" then  -- 精萃=亮点
            setc({1,1,0.7}); love.graphics.circle("fill",cx,cy-s*0.45,s*0.16)
        elseif sys=="toxic" then  -- 毒性=三个小点
            setc({0.6,1,0.4}); love.graphics.circle("fill",cx-s*0.3,cy+s*0.3,s*0.1); love.graphics.circle("fill",cx+s*0.3,cy+s*0.3,s*0.1); love.graphics.circle("fill",cx,cy+s*0.45,s*0.1)
        end
        -- 档位角标：右下小点数（高档更亮）
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

function draw.icon_coin(cx,cy,r,tier)
    -- tier: "gold"(默认)/"silver"/"copper"，决定币色；底层金钱仍是总铜数，只显示分级
    local base,face = {0.78,0.58,0.12}, UI.gold
    if tier=="silver" then base,face = {0.55,0.58,0.62},{0.82,0.85,0.9}
    elseif tier=="copper" then base,face = {0.5,0.32,0.16},{0.82,0.52,0.30} end
    setc(base); love.graphics.circle("fill",cx,cy,r)
    setc(face); love.graphics.circle("fill",cx,cy,r*0.7)
    setc({1,1,1,0.5}); love.graphics.circle("fill",cx-r*0.25,cy-r*0.25,r*0.18)
end
-- 把总铜数拆成 金/银/铜（100 进位）。返回 {g=,s=,c=}
function draw.coin_parts(total)
    total = math.max(0, math.floor(total or 0))
    return { g=math.floor(total/10000), s=math.floor(total/100)%100, c=total%100 }
end
-- 紧凑文字形式（只显示非零的高位两级，避免太长）。如 "1金23银"、"45银6铜"、"7铜"
function draw.coin_str(total)
    local p=draw.coin_parts(total)
    if p.g>0 then return p.g.."金"..(p.s>0 and (p.s.."银") or "")
    elseif p.s>0 then return p.s.."银"..(p.c>0 and (p.c.."铜") or "")
    else return p.c.."铜" end
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

-- ============================================================================
-- 像素件：chibi 骨骼弓手头像 + 网格剪影图标（复用 _pixel_ref/scene_hero_ref 的画法）。
-- 用于 HUD 头像卡与底部导航 / 活动抽屉的图标，保住硬边像素观感（整数像素、无抗锯齿弧）。
-- ============================================================================
-- chibi 骨骼弓手：代码关节(非PNG帧)、大头比例、拉弓姿势 + 呼吸。
-- 在一块本地像素网格里画(px≈1 像素格)，落点 (ox,oy) 为脚底；ps=像素格边长(屏幕像素)。
-- 调用方一般把它当头像半身：把脚放到框下沿外，scissor 只露上半身+弓臂。
-- phase 不传则用 draw.t（纯展示相位）。
function draw.draw_hero_chibi(ox, oy, ps, phase)
    ps = ps or math.max(2, sx(3)); phase = phase or draw.t
    local br = math.sin(phase*2)*ps*0.6          -- 呼吸：上半身轻微起伏
    -- 关节（单位=像素格，相对脚底 oy 往上）。比例照 ref（chibi 大头）。
    local function P(gx,gy) return ox+gx*ps, oy+gy*ps end
    local pelvis={P(0,-12)}; local chest={P(0,-19)}; local head={P(0,-27)}
    chest[2]=chest[2]-br; head[2]=head[2]-br
    local hr = ps*6
    local sh={chest[1],chest[2]}
    local fElb={P(5,-19)}; fElb[2]=fElb[2]-br; local fHand={P(10,-22)}; fHand[2]=fHand[2]-br
    local bElb={P(-4,-18)}; bElb[2]=bElb[2]-br; local bHand={P(-2,-20)}; bHand[2]=bHand[2]-br
    local kL={P(-3,-6)}; local fL={P(-5,0)}; local kR={P(3,-6)}; local fR={P(4,0)}
    -- 画一条"骨"：沿线撒像素圆点（粗细 w，像素格单位），保留 ref 的颗粒感
    local OUTL={0.11,0.09,0.12}; local SKIN={0.93,0.74,0.52}
    local TUNIC={0.30,0.42,0.55}; local TUNIC_HI={0.42,0.56,0.70}; local HAIR={0.34,0.24,0.16}; local ACC={0.96,0.75,0.34}
    local function bone(a,b,w,col)
        setc(col); local dx,dy=b[1]-a[1],b[2]-a[2]; local d=math.sqrt(dx*dx+dy*dy)
        local steps=math.max(2,math.ceil(d/ps)); for i=0,steps do local u=i/steps
            love.graphics.circle("fill", a[1]+dx*u, a[2]+dy*u, w*ps) end
    end
    -- 腿
    bone(pelvis,kL,1.4,OUTL); bone(kL,fL,1.4,OUTL)
    bone(pelvis,kR,1.4,OUTL); bone(kR,fR,1.4,OUTL)
    -- 躯干（上衣色一段，区别于细线版）
    bone(pelvis,chest,1.9,TUNIC); bone(pelvis,chest,1.2,TUNIC_HI)
    -- 手臂（肩→肘 上衣色，肘→手 肤色）
    bone(sh,fElb,1.3,TUNIC); bone(fElb,fHand,1.3,SKIN)
    bone(sh,bElb,1.3,TUNIC); bone(bElb,bHand,1.3,SKIN)
    -- 头（大头 chibi，无帽：描边 + 肤 + 头发弧 + 一个眼点）
    setc(OUTL); love.graphics.circle("fill",head[1],head[2],hr+ps*0.6)
    setc(SKIN); love.graphics.circle("fill",head[1],head[2],hr)
    setc(HAIR); love.graphics.arc("fill","pie",head[1],head[2],hr,math.pi*1.02,math.pi*1.98)   -- 头发(无帽不秃)
    setc(OUTL); love.graphics.rectangle("fill",head[1]+ps*2,head[2]-ps,ps,ps)   -- 眼
    -- 弓（前手处的弧 + 弦 + 箭）
    setc({0.55,0.37,0.20}); love.graphics.setLineWidth(math.max(1,ps*1.4))
    love.graphics.arc("line","open",fHand[1],fHand[2],ps*6,-1.35,1.35)
    setc({0.85,0.83,0.7}); love.graphics.setLineWidth(math.max(1,ps*0.8))
    local t1x,t1y=fHand[1]+ps*6*math.cos(-1.35),fHand[2]+ps*6*math.sin(-1.35)
    local t2x,t2y=fHand[1]+ps*6*math.cos(1.35), fHand[2]+ps*6*math.sin(1.35)
    love.graphics.line(t1x,t1y, bHand[1],bHand[2], t2x,t2y)
    setc(ACC); love.graphics.setLineWidth(math.max(1,ps)); love.graphics.line(bHand[1],bHand[2], fHand[1]+ps*5,fHand[2])
    love.graphics.polygon("fill", fHand[1]+ps*6,fHand[2], fHand[1]+ps*3,fHand[2]-ps*1.5, fHand[1]+ps*3,fHand[2]+ps*1.5)
    love.graphics.setLineWidth(1)
end

-- 网格剪影图标：在 5×5 像素网格里点亮格子画硬边剪影。(cx,cy)=图标中心，s=半径(图标≈2s)。
-- name: activity/skills/bag/equip/region/coin/key/license/forge/gather/rest/combat。
-- 用 1 像素格 = s/2.5，整数对齐，无抗锯齿 → 干净像素剪影。col 为主色。
local PIX_ICON = {
    activity = {"..#..","..#..",".###.","#####",".###."},          -- 上箭头/帐篷
    skills   = {"....#","...#.","..#..",".#.#.","#...#"},          -- 飞箭
    bag      = {".###.","#...#","#####","#####","#####"},          -- 背包袋
    equip    = {"#####",".###.",".###.","..#..","..#.."},          -- 盾
    region   = {"#....","####.","#..#.","####.","#...."},          -- 旗
    combat   = {"#...#",".#.#.","..#..",".#.#.","#...#"},          -- 交叉(战斗)
    gather   = {"..#..","..#..","#####","..#..","..#.."},          -- 镐/采集
    craft    = {".###.","#...#","#.#.#","#...#",".###."},          -- 工件
    forge    = {"#...#","#...#",".###.","..#..","..#.."},          -- 砧/漏斗
    rest     = {".....","#####",".....","#####","....."},          -- 休息/床
    key      = {".##..","#..#.",".##..","..#..","..##."},          -- 钥匙
    license  = {"#####","#...#","#.#.#","#...#","#####"},          -- 许可文牒
    gear     = {".#.#.","#####",".#.#.","#####",".#.#."},          -- 齿轮
}
function draw.pixel_icon(name, cx, cy, s, col)
    local g = PIX_ICON[name]; if not g then return end
    local cell = math.max(1, math.floor(s/2.5 + 0.5))    -- 像素格边长(整数)
    local n = 5
    local x0 = math.floor(cx - n*cell/2 + 0.5)
    local y0 = math.floor(cy - n*cell/2 + 0.5)
    setc(col or {0.96,0.96,1})
    for row=1,n do local line=g[row]
        for cidx=1,n do
            if line:sub(cidx,cidx)=="#" then
                love.graphics.rectangle("fill", x0+(cidx-1)*cell, y0+(row-1)*cell, cell, cell)
            end
        end
    end
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
