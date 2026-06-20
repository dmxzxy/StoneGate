-- ============================================================================
-- view/system —— 系统菜单（齿轮）：继续 / 音量(音乐+音效滑条) / 重置存档 / 退回大厅。
-- 重置/退出由 core/state 标志位转交 main.lua 执行(避免循环 require)。音量存 player.settings，
-- 调节即写 love.audio.setVolume(若有)；目前游戏无音频，滑条先就位等以后接上。
-- 提供 draw() / hit(x,y)。命中坐标与 draw 共用 row 几何。
-- ============================================================================
local screen = require("base.screen")
local draw = require("base.draw")
local state = require("core.state")
local fx = require("fx")
local D = require("data")
local UI = D.UI

local function sx(v) return v*screen.sw end
local function sy(v) return v*screen.sh end
local function hit(x,y,rx,ry,rw,rh) return x>=rx and x<=rx+rw and y>=ry and y<=ry+rh end
local setc, panel, button = draw.setc, draw.panel, draw.button

local system_view = {}

-- 面板几何：居中卡
local function panel_rect()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    local pw,ph=sx(300),sy(360); return (w-pw)/2,(h-ph)/2,pw,ph
end
-- 两条音量滑条的轨道矩形
local function slider_rect(i, px,py,pw)
    return px+sx(80), py+sy(86)+(i-1)*sy(44), pw-sx(110), sy(10)
end
local BTNS = {  -- {label, col, id}
    { "继续",     {0.3,0.55,0.9},  "resume" },
    { "重置存档", {0.7,0.45,0.3},  "reset"  },
    { "退回大厅", {0.55,0.4,0.5},  "exit"   },
}
local function btn_rect(i, px,py,pw,ph)
    local bw=pw-sx(40); return px+sx(20), py+ph-sy(40)-(#BTNS-i)*sy(44), bw, sy(34)
end

function system_view.draw()
    local w,h=love.graphics.getWidth(),love.graphics.getHeight()
    love.graphics.setColor(0,0,0,0.72); love.graphics.rectangle("fill",0,0,w,h)
    local px,py,pw,ph = panel_rect()
    panel(px,py,pw,ph,{0.10,0.11,0.16,0.99},UI.line,0)
    love.graphics.setFont(draw.font_med); setc(UI.text); love.graphics.printf("系统",px,py+sy(10),pw,"center")
    draw.close_x(px,py,pw)
    -- 音量滑条
    local s = state.player.settings or { music=0.7, sfx=0.8 }
    love.graphics.setFont(draw.font_sm)
    local labels={ {"音乐","music"}, {"音效","sfx"} }
    for i,lb in ipairs(labels) do
        local tx,ty,tw,th = slider_rect(i,px,py,pw)
        setc(UI.dim); love.graphics.print(lb[1], px+sx(24), ty-sy(2))
        setc({0,0,0,0.4}); love.graphics.rectangle("fill",tx,ty,tw,th)              -- 轨道
        local v = s[lb[2]] or 0
        setc(UI.btn); love.graphics.rectangle("fill",tx,ty,tw*v,th)                 -- 已填
        setc(UI.text); love.graphics.rectangle("fill",tx+tw*v-sx(3),ty-sy(3),sx(6),th+sy(6)) -- 把手
        setc(UI.text); love.graphics.printf(math.floor(v*100).."%", tx, ty-sy(2), tw, "right")
    end
    -- 提示：当前无音频
    setc(UI.dim); love.graphics.setFont(draw.font_sm)
    love.graphics.printf("（音频后续加入，音量设置已保存）", px, py+sy(170), pw, "center")
    -- 按钮
    for i,b in ipairs(BTNS) do
        local bx,by,bw,bh = btn_rect(i,px,py,pw,ph)
        button(bx,by,bw,bh,b[1],b[2],true,draw.font)
    end
end

function system_view.hit(x,y)
    local px,py,pw,ph = panel_rect()
    if draw.hit_close_x(x,y,px,py,pw) then state.panel_open=nil; return true end
    -- 音量滑条拖/点
    local s = state.player.settings; local keys={"music","sfx"}
    for i,k in ipairs(keys) do
        local tx,ty,tw,th = slider_rect(i,px,py,pw)
        if hit(x,y,tx,ty-sy(6),tw,th+sy(12)) then
            local v=math.max(0,math.min(1,(x-tx)/tw)); s[k]=v
            if love.audio and love.audio.setVolume then pcall(love.audio.setVolume, (s.music+s.sfx)/2) end
            return true
        end
    end
    -- 按钮
    for i,b in ipairs(BTNS) do
        local bx,by,bw,bh = btn_rect(i,px,py,pw,ph)
        if hit(x,y,bx,by,bw,bh) then
            if b[3]=="resume" then state.panel_open=nil
            elseif b[3]=="reset" then
                if state.confirm_reset then state.req_reset=true; state.confirm_reset=nil; state.panel_open=nil
                else state.confirm_reset=true; fx.set_toast("再点一次「重置存档」确认", UI.bad) end
            elseif b[3]=="exit" then state.req_exit=true end
            return true
        end
    end
    return true
end

return system_view
