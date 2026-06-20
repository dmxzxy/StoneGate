-- ============================================================================
-- fx —— 纯表现层特效：跳字(floats)/粒子(particles)/震屏(shake)/采集挥动相位(swing)/
--        动画时钟(t_accum)/顶部提示(toast)。
-- 依赖：love(画) + base/screen(缩放) + base/draw(字体句柄)。
-- 被所有 sys 单向依赖（战斗/采集/制造往这里喂跳字、粒子、震屏、toast），
-- 自己绝不 require 任何 sys —— 这样打断了原来 set_toast/node_machine 的前向声明。
-- 状态字段直接挂在 fx 表上(fx.floats / fx.shake / fx.toast …)，所有写入方统一改写它们。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local D = require("data")
local UI = D.UI
local DESIGN_W, DESIGN_H = D.DESIGN_W, D.DESIGN_H

local fx = {}

-- 运行态（特效是瞬时的，init/reset 默认重建，不进存档）
fx.floats = {}       -- 伤害/收获跳字 {x,y,text,color,timer,scale,vy}
fx.particles = {}    -- 击破/采集碎屑 {x,y,vx,vy,life,max,size,color}
fx.shake = 0         -- 震屏强度（每帧衰减）
fx.swing = 0         -- 采集挥动动画相位（持续累加）
fx.t_accum = 0       -- 动画时钟（持续累加，敌人光环/篝火等用它做相位）
fx.toast = nil       -- 顶部短提示 {text,color,timer}

-- 瞬时态重建（init / 读档后调用）
function fx.reset()
    fx.floats = {}; fx.particles = {}; fx.shake = 0; fx.swing = 0; fx.toast = nil
    -- t_accum 是连续动画时钟，不重置（重置会让待机相位跳一下；与旧行为一致：init 不动 t_accum）
end

-- 缩放助手（与 screen 共享同一份 sw/sh，现读现算）
local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end

-- ---- 喂入接口（被 sys 调用） ----
function fx.add_float(x,y,txt,col,scale)
    fx.floats[#fx.floats+1] = { x=x, y=y, text=txt, color=col or UI.text, timer=1.0, scale=scale or 1, vy=-45 }
end
function fx.burst(x,y,c,n)
    for _=1,n do
        local a=math.random()*math.pi*2; local s=40+math.random()*150
        fx.particles[#fx.particles+1] = { x=x, y=y, vx=math.cos(a)*s, vy=math.sin(a)*s-40, life=0.4+math.random()*0.4, max=0.8, size=2+math.random()*4, color=c }
    end
end
function fx.set_toast(t,c) fx.toast = { text=t, color=c or UI.text, timer=2.5 } end

-- ---- 每帧推进（粒子物理 / 跳字漂移 / toast 计时 / 震屏与时钟） ----
function fx.update_fx(dt)
    fx.t_accum = fx.t_accum + dt
    fx.shake = math.max(0, fx.shake - dt*40)
    fx.swing = fx.swing + dt
    draw.t = fx.t_accum   -- 喂动画时钟给 base/draw（draw_archer 待机相位默认用它，等价旧 t_accum 默认）
    for i=#fx.particles,1,-1 do local p=fx.particles[i]; p.vy=p.vy+260*dt; p.x=p.x+p.vx*dt; p.y=p.y+p.vy*dt; p.life=p.life-dt; if p.life<=0 then table.remove(fx.particles,i) end end
    for i=#fx.floats,1,-1 do local f=fx.floats[i]; f.y=f.y+f.vy*dt; f.vy=f.vy+40*dt; f.timer=f.timer-dt; if f.timer<=0 then table.remove(fx.floats,i) end end
    if fx.toast then fx.toast.timer=fx.toast.timer-dt; if fx.toast.timer<=0 then fx.toast=nil end end
end

-- ---- 绘制（共享粒子 / 跳字；与旧 main 内联画法逐字等价） ----
function fx.draw_particles()
    for _,p in ipairs(fx.particles) do
        local al=math.max(0,p.life/p.max)
        love.graphics.setColor(p.color[1],p.color[2],p.color[3],al)
        love.graphics.rectangle("fill", p.x*screen.sw-p.size*screen.sw/2, p.y*screen.sh-p.size*screen.sh/2, p.size*screen.sw, p.size*screen.sh)
    end
end
function fx.draw_floats()
    for _,f in ipairs(fx.floats) do
        love.graphics.setFont(f.scale>1.2 and draw.font_med or draw.font_sm)
        love.graphics.setColor(f.color[1],f.color[2],f.color[3],math.min(1,f.timer*2))
        love.graphics.printf(f.text, f.x*screen.sw-sx(60), f.y*screen.sh, sx(120), "center")
    end
end

return fx
