-- main.lua — StoneGate 游戏模板
--
-- 这个示例只做最小的事,重点是把「给 StoneGate 写游戏」的几条约定演示清楚:
--   1. 资源加载   —— 用包内相对路径加载 assets/ 里的图(外壳把 .love 挂到根,
--                     所以 "assets/icon.png" 这种 bare 路径能直接用)。
--   2. 退出回大厅 —— 两条路: ESC/物理返回键(外壳自动拦截), 以及屏幕上的
--                     「返回」按钮调 stonegate_exit()(手机没物理键时的主路径)。
--   3. 触摸输入   —— love.touchpressed 是手机上的主输入;鼠标点击作桌面兼容。
--
-- 复制本目录、改 conf.lua 的 identity/title 和 meta.json,就是一个新游戏的骨架。

local icon            -- 包内加载的图(可能为 nil,下面有兜底)
local ripples = {}    -- 点击生成的涟漪,做点即时反馈

-- 返回按钮的位置/大小(在 layout() 里按屏幕尺寸算)
local back_btn = { x = 0, y = 0, w = 0, h = 0 }

local function layout()
    local w = love.graphics.getWidth()
    local m = math.floor(w * 0.04)
    back_btn.w = math.floor(w * 0.28)
    back_btn.h = math.floor(back_btn.w * 0.34)
    back_btn.x = m
    back_btn.y = m
end

-- 是否点中了返回按钮
local function hit_back(px, py)
    return px >= back_btn.x and px <= back_btn.x + back_btn.w
       and py >= back_btn.y and py <= back_btn.y + back_btn.h
end

-- 退出回大厅。外壳启动游戏时注入了全局 stonegate_exit;
-- 桌面单独跑(没有外壳)时它是 nil,就退出整个程序。
local function go_back()
    if _G.stonegate_exit then
        stonegate_exit()
    else
        love.event.quit()
    end
end

function love.load()
    layout()
    -- 资源加载: pcall 包一层,图缺失也不至于让整个游戏崩在加载阶段。
    local ok, img = pcall(love.graphics.newImage, "assets/icon.png")
    if ok then icon = img end
end

function love.update(dt)
    -- 推进涟漪动画,淡出后移除
    for i = #ripples, 1, -1 do
        local rp = ripples[i]
        rp.r = rp.r + dt * 220
        rp.a = rp.a - dt * 1.6
        if rp.a <= 0 then table.remove(ripples, i) end
    end
end

function love.draw()
    local w, h = love.graphics.getDimensions()
    love.graphics.setBackgroundColor(0.08, 0.10, 0.15)

    -- 涟漪(点击反馈)
    for _, rp in ipairs(ripples) do
        love.graphics.setColor(0.35, 0.65, 1.0, rp.a)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", rp.x, rp.y, rp.r)
    end

    -- 包内资源: 居中画 icon;没有就画个占位方块,说明加载失败
    local cx, cy = w/2, h/2
    if icon then
        local s = (w * 0.25) / icon:getWidth()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(icon, cx, cy, 0, s, s, icon:getWidth()/2, icon:getHeight()/2)
    else
        love.graphics.setColor(0.3, 0.3, 0.4, 1)
        love.graphics.rectangle("fill", cx - 32, cy - 32, 64, 64)
    end

    -- 文案
    love.graphics.setColor(0.6, 0.62, 0.72)
    love.graphics.printf("StoneGate 游戏模板\n点击任意处看反馈", 0, cy + w*0.18, w, "center")

    -- 返回按钮(屏幕左上角) —— 手机无物理返回键时的退出路径
    love.graphics.setColor(0.16, 0.18, 0.26, 1)
    love.graphics.rectangle("fill", back_btn.x, back_btn.y, back_btn.w, back_btn.h, back_btn.h/2)
    love.graphics.setColor(0.9, 0.92, 1.0)
    love.graphics.printf("← 返回", back_btn.x, back_btn.y + back_btn.h*0.28, back_btn.w, "center")

    love.graphics.setColor(0.4, 0.42, 0.5)
    love.graphics.printf("或按 ESC", 0, h - w*0.12, w, "center")
end

-- 一次点击的处理: 命中返回按钮就退出,否则生成涟漪。
local function on_press(x, y)
    if hit_back(x, y) then
        go_back()
        return
    end
    ripples[#ripples + 1] = { x = x, y = y, r = 6, a = 0.9 }
end

-- 触摸是手机主输入
function love.touchpressed(id, x, y)
    on_press(x, y)
end

-- 鼠标作桌面兼容
function love.mousepressed(x, y, button)
    if button == 1 then on_press(x, y) end
end

-- 注: ESC / 物理返回键由外壳(game_loader)统一拦截并退出,
-- 游戏自己不用处理。这里就不写 love.keypressed 了。

function love.resize()
    layout()
end
