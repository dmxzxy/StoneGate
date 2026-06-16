-- conf.lua — StoneGate 游戏模板配置
-- 这是给 StoneGate 写游戏的起点。复制整个 sample/ 目录，改名即可开新游戏。
function love.conf(t)
    t.identity = "sample"          -- 存档目录名,各游戏唯一
    t.version  = "11.5"            -- 目标 LÖVE 版本(不是游戏版本,游戏版本在 meta.json)
    t.console  = false

    -- 竖屏手机比例,和外壳一致;外壳会按真机尺寸调用 love.resize
    t.window.title     = "Sample"
    t.window.width     = 480
    t.window.height    = 800
    t.window.resizable = true
    t.window.minwidth  = 320
    t.window.minheight = 480

    -- 关掉用不到的模块,减小体积/内存。需要谁就打开谁。
    t.modules.physics = false
    t.modules.video   = false
    t.modules.joystick = false
end
