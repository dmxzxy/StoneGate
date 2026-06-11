-- conf.lua embedded
local x, y = 200, 300
local vx, vy = 180, 130
local r, g, b = 0.3, 0.6, 1.0

function love.load()
    love.window.setTitle("Sample Game")
end

function love.update(dt)
    local w, h = love.graphics.getDimensions()
    x = x + vx * dt
    y = y + vy * dt
    if x <= 30 or x >= w - 30 then
        vx = -vx
        r, g, b = math.random()*0.8+0.2, math.random()*0.8+0.2, math.random()*0.8+0.2
    end
    if y <= 30 or y >= h - 30 then
        vy = -vy
        r, g, b = math.random()*0.8+0.2, math.random()*0.8+0.2, math.random()*0.8+0.2
    end
    x = math.max(30, math.min(w - 30, x))
    y = math.max(30, math.min(h - 30, y))
end

function love.draw()
    love.graphics.setBackgroundColor(0.08, 0.10, 0.15)

    -- Trail effect
    love.graphics.setColor(0.15, 0.20, 0.30, 0.4)
    love.graphics.circle("fill", x - vx * 0.02, y - vy * 0.02, 28)

    -- Ball
    love.graphics.setColor(r, g, b)
    love.graphics.circle("fill", x, y, 30)

    -- Highlight
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.circle("fill", x - 8, y - 8, 10)

    -- Instructions
    love.graphics.setColor(0.6, 0.6, 0.7)
    love.graphics.printf("Sample Game - Bouncing Ball\nPress ESC to return to Boot Shell", 20, 20, love.graphics.getWidth() - 40)
end
