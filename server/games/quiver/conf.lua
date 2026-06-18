function love.conf(t)
    t.identity = "quiver_proto"
    t.version = "11.5"
    t.console = false
    t.window.title = "Quiver"
    t.window.width = 480
    t.window.height = 800
    t.window.resizable = true
    t.window.minwidth = 320
    t.window.minheight = 480
    t.modules.physics = false
    t.modules.video = false
    t.modules.thread = false
end
