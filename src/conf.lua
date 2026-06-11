-- conf.lua - StoneGate configuration
function love.conf(t)
    t.identity = "stonegate"
    t.version = "11.5"
    t.console = true

    t.window.title = "StoneGate"
    t.window.width = 480
    t.window.height = 800
    t.window.resizable = true
    t.window.minwidth = 320
    t.window.minheight = 480

    -- Disable unused modules for smaller footprint on Android
    t.modules.physics = false
end
