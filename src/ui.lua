-- ui.lua - StoneGate visual layer
-- Polished dark-theme UI with shadows, gradients, font hierarchy, and animations.

local ui = {}
local config = require("config")

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------
local CARD_H     = 100
local CARD_PAD   = 14
local CARD_R     = 12
local THUMB_SZ   = 68
local THUMB_PAD  = 10
local BTN_W      = 76
local BTN_H      = 34
local BTN_R      = 17          -- pill-shaped buttons
local DEL_SZ     = 28
local HEADER_H   = 64
local FOOTER_H   = 44
local SCROLLBAR_W = 3
local SCROLLBAR_R = 2

--------------------------------------------------------------------------------
-- Fonts (loaded once in ui.init)
--------------------------------------------------------------------------------
local fonts = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function color(c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function lerp_color(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    }
end

local function rounded_rect(mode, x, y, w, h, r)
    r = math.min(r, w / 2, h / 2)
    if love.graphics.roundedRectangle then
        love.graphics.roundedRectangle(mode, x, y, w, h, r)
    else
        love.graphics.rectangle(mode, x, y, w, h)
    end
end

--- Vertical gradient (top → bottom)
local function gradient_v(x, y, w, h, top_c, bot_c, alpha_top, alpha_bot)
    alpha_top = alpha_top or 1
    alpha_bot = alpha_bot or 1
    local step = math.max(1, math.floor(h / 40))
    for i = 0, h - 1, step do
        local t = i / math.max(1, h - 1)
        local c = lerp_color(top_c, bot_c, t)
        love.graphics.setColor(c[1], c[2], c[3], alpha_top + (alpha_bot - alpha_top) * t)
        love.graphics.rectangle("fill", x, y + i, w, math.min(step, h - i))
    end
end

--- Draw a soft shadow behind a rounded rect
local function draw_shadow(x, y, w, h, r, depth)
    depth = depth or 4
    for i = depth, 1, -1 do
        local a = 0.12 * (1 - i / (depth + 1))
        color(config.colors.shadow, a)
        rounded_rect("fill", x + i, y + i, w, h, r)
    end
end

--- Draw a pill-shaped button with optional gradient
local function draw_button(x, y, w, h, r, base_color, text_str, text_font)
    -- Shadow
    draw_shadow(x, y, w, h, r, 3)

    -- Button body
    color(base_color)
    rounded_rect("fill", x, y, w, h, r)

    -- Top highlight (lighter stripe on top half)
    local hi = lerp_color(base_color, { 1, 1, 1 }, 0.15)
    love.graphics.setScissor(x, y, w, h / 2)
    color(hi, 0.25)
    rounded_rect("fill", x, y, w, h / 2, r)
    love.graphics.setScissor()

    -- Text
    if text_str then
        love.graphics.setFont(text_font or fonts.btn)
        color(config.colors.text)
        love.graphics.printf(text_str, x, y + (h - (text_font or fonts.btn):getHeight()) / 2, w, "center")
    end
end

--------------------------------------------------------------------------------
-- Scroll state
--------------------------------------------------------------------------------
local scroll_y = 0
local max_scroll = 0
local touch_id = nil
local touch_start_y = 0
local touch_start_scroll = 0
local touch_start_time = 0

local function card_positions(n)
    local positions = {}
    local y = HEADER_H + CARD_PAD + scroll_y
    for i = 1, n do
        positions[i] = y
        y = y + CARD_H + CARD_PAD
    end
    local content_h = y - scroll_y
    local screen_h = love.graphics.getHeight()
    max_scroll = math.max(0, content_h - screen_h + FOOTER_H)
    return positions
end

--------------------------------------------------------------------------------
-- Button rects
--------------------------------------------------------------------------------
local function action_btn_rect(cx, cy, cw)
    return cx + cw - BTN_W - 12, cy + (CARD_H - BTN_H) / 2
end

local function delete_btn_rect(cx, cy, cw)
    local bx, by = action_btn_rect(cx, cy, cw)
    return bx - DEL_SZ - 6, by + (BTN_H - DEL_SZ) / 2
end

--------------------------------------------------------------------------------
-- Thumbnail
--------------------------------------------------------------------------------
local function draw_thumbnail(game_id, x, y, thumbs)
    local img = thumbs and thumbs[game_id]
    -- Background
    color(config.colors.placeholder)
    rounded_rect("fill", x, y, THUMB_SZ, THUMB_SZ, 8)

    if img then
        love.graphics.draw(img, x + 2, y + 2, 0,
            (THUMB_SZ - 4) / img:getWidth(),
            (THUMB_SZ - 4) / img:getHeight())
    else
        -- Placeholder: first letter with accent color
        local letter = (game_id or "?"):sub(1, 1):upper()
        love.graphics.setFont(fonts.thumb)
        color(config.colors.accent, 0.6)
        love.graphics.printf(letter, x, y + THUMB_SZ / 2 - fonts.thumb:getHeight() / 2, THUMB_SZ, "center")
    end
end

--------------------------------------------------------------------------------
-- Scrollbar
--------------------------------------------------------------------------------
local function draw_scrollbar(w, h)
    if max_scroll <= 0 then return end
    local track_h = h - HEADER_H - FOOTER_H
    local thumb_ratio = track_h / (track_h + max_scroll)
    local thumb_h = math.max(30, track_h * thumb_ratio)
    local thumb_y = HEADER_H + (-scroll_y / max_scroll) * (track_h - thumb_h)

    color(config.colors.text_dim, 0.15)
    love.graphics.rectangle("fill", w - SCROLLBAR_W - 4, thumb_y, SCROLLBAR_W, thumb_h, SCROLLBAR_R)
end

--------------------------------------------------------------------------------
-- Status dot + text
--------------------------------------------------------------------------------
local function draw_status(x, y, text, dot_color)
    -- Colored dot
    color(dot_color, 0.9)
    love.graphics.circle("fill", x + 4, y + 6, 3.5)
    -- Text
    color(config.colors.text_dim)
    love.graphics.setFont(fonts.sm)
    love.graphics.printf(text, x + 13, y, 300, "left")
end

--------------------------------------------------------------------------------
-- Init — call once from love.load
--------------------------------------------------------------------------------
function ui.init()
    fonts.lg   = love.graphics.newFont(24)
    fonts.md   = love.graphics.newFont(17)
    fonts.sm   = love.graphics.newFont(14)
    fonts.btn  = love.graphics.newFont(15)
    fonts.thumb = love.graphics.newFont(28)
    fonts.h1   = love.graphics.newFont(32)
end

--------------------------------------------------------------------------------
-- Screens
--------------------------------------------------------------------------------

function ui.draw_loading()
    local w, h = love.graphics.getDimensions()
    color(config.colors.bg)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local cx, cy = w / 2, h / 2 - 20
    local t = love.timer.getTime()

    -- Animated pulsing rings
    for i = 3, 1, -1 do
        local phase = (t * 1.5 + i * 0.4) % 1.8
        local scale = 0.3 + phase * 0.7
        local alpha = math.max(0, 0.35 - phase * 0.25)
        color(config.colors.accent, alpha)
        local r = 18 + 28 * scale
        love.graphics.setLineWidth(1.5)
        love.graphics.circle("line", cx, cy, r)
    end

    -- Center dot
    local pulse = 0.7 + math.sin(t * 4) * 0.3
    color(config.colors.accent, pulse)
    love.graphics.circle("fill", cx, cy, 6)

    -- App name
    love.graphics.setFont(fonts.lg)
    color(config.colors.text)
    love.graphics.printf(config.app_name, 0, cy + 50, w, "center")

    -- Subtitle
    love.graphics.setFont(fonts.sm)
    color(config.colors.text_dim)
    love.graphics.printf("Loading game list" .. string.rep(".", math.floor(t * 2) % 4), 0, cy + 80, w, "center")

    -- Server address
    love.graphics.setFont(fonts.sm)
    color(config.colors.text_dim, 0.4)
    love.graphics.printf(config.server_url, 0, cy + 100, w, "center")
end

function ui.draw_menu(games, installed, thumbnails)
    local w, h = love.graphics.getDimensions()
    local t = love.timer.getTime()

    -- Background
    color(config.colors.bg)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Header area with gradient
    gradient_v(0, 0, w, HEADER_H,
        config.colors.bg_surface, config.colors.bg, 1, 1)

    -- Brand text
    love.graphics.setFont(fonts.lg)
    color(config.colors.accent)
    love.graphics.printf(config.app_name, 0, 16, w, "center")

    -- Subtle accent line under header
    color(config.colors.accent, 0.15)
    love.graphics.rectangle("fill", w * 0.25, HEADER_H - 1, w * 0.5, 1)

    -- Cards (clipped)
    love.graphics.setScissor(0, HEADER_H, w, h - HEADER_H - FOOTER_H)

    local positions = card_positions(#games)
    local margin = CARD_PAD

    for i, game in ipairs(games) do
        local cy = positions[i]
        local cx = margin
        local cw = w - margin * 2

        -- Skip off-screen cards
        if cy + CARD_H >= HEADER_H and cy <= h - FOOTER_H then
            local is_installed  = installed[game.id] ~= nil
            local needs_update  = is_installed and (
                installed[game.id].version ~= game.version or
                (game.size and installed[game.id].size and installed[game.id].size ~= game.size)
            )

            -- Shadow
            draw_shadow(cx, cy, cw, CARD_H, CARD_R, 5)

            -- Card body
            color(config.colors.card)
            rounded_rect("fill", cx, cy, cw, CARD_H, CARD_R)

            -- Top highlight — subtle bright line
            love.graphics.setScissor(cx, cy, cw, 2)
            color(config.colors.card_hi, 0.5)
            love.graphics.rectangle("fill", cx + CARD_R, cy, cw - CARD_R * 2, 1)
            love.graphics.setScissor(0, HEADER_H, w, h - HEADER_H - FOOTER_H)

            -- Thumbnail
            local thumb_x = cx + THUMB_PAD
            local thumb_y = cy + (CARD_H - THUMB_SZ) / 2
            draw_thumbnail(game.id, thumb_x, thumb_y, thumbnails)

            -- Text area
            local text_x = thumb_x + THUMB_SZ + THUMB_PAD
            local text_w = cw - (text_x - cx) - BTN_W - DEL_SZ - 28

            -- Game name
            love.graphics.setFont(fonts.md)
            color(config.colors.text)
            love.graphics.printf(game.name or game.id, text_x, cy + 10, text_w, "left")

            -- Version + size
            love.graphics.setFont(fonts.sm)
            color(config.colors.text_sub)
            local info = "v" .. (game.version or "?")
            if game.size then info = info .. "  ·  " .. ui.format_size(game.size) end
            love.graphics.printf(info, text_x, cy + 32, text_w, "left")

            -- Status
            local status_text, dot_c
            if not is_installed then
                status_text, dot_c = "Not downloaded", config.colors.accent
            elseif needs_update then
                status_text, dot_c = "Update available", config.colors.warning
            else
                status_text, dot_c = "Installed", config.colors.success
            end
            draw_status(text_x, cy + 52, status_text, dot_c)

            -- Action button
            local btn_text, btn_c
            if not is_installed then
                btn_text, btn_c = "Get", config.colors.accent
            elseif needs_update then
                btn_text, btn_c = "Update", config.colors.warning
            else
                btn_text, btn_c = "Play", config.colors.success
            end

            local btn_x, btn_y = action_btn_rect(cx, cy, cw)
            draw_button(btn_x, btn_y, BTN_W, BTN_H, BTN_R, btn_c, btn_text, fonts.btn)

            -- Delete button (outline style, subtle)
            if is_installed then
                local dx, dy = delete_btn_rect(cx, cy, cw)
                color(config.colors.danger_dim, 0.6)
                rounded_rect("fill", dx, dy, DEL_SZ, DEL_SZ, DEL_SZ / 2)
                love.graphics.setFont(fonts.sm)
                color(config.colors.danger, 0.7)
                love.graphics.printf("×", dx, dy + (DEL_SZ - fonts.sm:getHeight()) / 2, DEL_SZ, "center")
            end
        end
    end

    love.graphics.setScissor()

    -- Scrollbar
    draw_scrollbar(w, h)

    -- Footer
    local footer_y = h - FOOTER_H
    gradient_v(0, footer_y, w, FOOTER_H,
        config.colors.bg, config.colors.bg_surface, 0.7, 1)

    -- Divider line
    color(config.colors.divider)
    love.graphics.rectangle("fill", 0, footer_y, w, 1)

    -- Refresh button
    local refresh_w = 76
    local refresh_h = 30
    local refresh_x = w - refresh_w - 14
    local refresh_y = footer_y + (FOOTER_H - refresh_h) / 2 + 1
    draw_button(refresh_x, refresh_y, refresh_w, refresh_h, refresh_h / 2,
        config.colors.accent_dim, "Refresh", fonts.btn)

    -- Game count
    love.graphics.setFont(fonts.sm)
    color(config.colors.text_dim)
    local count_text = #games .. " game" .. (#games ~= 1 and "s" or "")
    love.graphics.printf(count_text, 16, footer_y + 14, w - refresh_w - 30, "left")
end

function ui.draw_downloading(game, progress)
    local w, h = love.graphics.getDimensions()
    local t = love.timer.getTime()

    color(config.colors.bg)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local cx, cy = w / 2, h / 2

    -- Spinning arc
    love.graphics.setLineWidth(2)
    local angle = t * 3
    for i = 0, 11 do
        local a = angle + i * math.pi * 2 / 12
        local alpha = 0.1 + (i / 12) * 0.4
        color(config.colors.accent, alpha)
        local r = 30
        love.graphics.arc("line", "open", cx, cy - 40, r, a, a + 0.3)
    end

    -- Title
    love.graphics.setFont(fonts.lg)
    color(config.colors.text_sub)
    love.graphics.printf("Downloading", 0, cy + 10, w, "center")

    -- Game name
    love.graphics.setFont(fonts.md)
    color(config.colors.accent)
    love.graphics.printf(game.name or game.id, 0, cy + 40, w, "center")

    -- Progress bar
    local bar_w = w * 0.65
    local bar_h = 6
    local bar_x = (w - bar_w) / 2
    local bar_y = cy + 70

    -- Track
    color(config.colors.card)
    rounded_rect("fill", bar_x, bar_y, bar_w, bar_h, bar_h / 2)

    -- Animated indeterminate shimmer
    local shimmer_pos = ((t * 0.8) % 2.4) / 2.4
    local shimmer_w = bar_w * 0.3
    local shimmer_x = bar_x + shimmer_pos * (bar_w - shimmer_w)
    color(config.colors.accent, 0.6)
    rounded_rect("fill", shimmer_x, bar_y, shimmer_w, bar_h, bar_h / 2)

    -- Size counter
    love.graphics.setFont(fonts.sm)
    color(config.colors.text_dim)
    local progress_text = progress > 0 and ui.format_size(progress) or "Connecting..."
    love.graphics.printf(progress_text, 0, bar_y + 16, w, "center")
end

function ui.draw_error(msg, detail)
    local w, h = love.graphics.getDimensions()

    color(config.colors.bg)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local cx, cy = w / 2, h / 2

    -- Error icon — circle with ×
    color(config.colors.danger_dim, 0.25)
    love.graphics.circle("fill", cx, cy - 60, 28)
    color(config.colors.danger, 0.9)
    love.graphics.setLineWidth(2.5)
    love.graphics.circle("line", cx, cy - 60, 28)
    love.graphics.line(cx - 10, cy - 70, cx + 10, cy - 50)
    love.graphics.line(cx + 10, cy - 70, cx - 10, cy - 50)

    -- Title
    love.graphics.setFont(fonts.lg)
    color(config.colors.danger)
    love.graphics.printf("Something went wrong", 0, cy - 18, w, "center")

    -- Message
    love.graphics.setFont(fonts.md)
    color(config.colors.text)
    love.graphics.printf(msg or "Unknown error", w * 0.08, cy + 16, w * 0.84, "center")

    -- Detail
    if detail and detail ~= "" then
        love.graphics.setFont(fonts.sm)
        color(config.colors.text_dim)
        local d = detail
        if #d > 180 then d = d:sub(1, 180) .. "..." end
        love.graphics.printf(d, w * 0.08, cy + 46, w * 0.84, "center")
    end

    -- Retry hint
    love.graphics.setFont(fonts.sm)
    color(config.colors.text_dim, 0.5)
    love.graphics.printf("Tap anywhere to retry", 0, cy + 90, w, "center")
end

--------------------------------------------------------------------------------
-- Touch / mouse handling
--------------------------------------------------------------------------------

function ui.touch_pressed(id, x, y)
    touch_id = id
    touch_start_y = y
    touch_start_scroll = scroll_y
    touch_start_time = love.timer.getTime()
    return nil
end

function ui.touch_moved(id, x, y)
    if id ~= touch_id then return end
    local dy = y - touch_start_y
    scroll_y = touch_start_scroll + dy
    scroll_y = math.max(-max_scroll, math.min(0, scroll_y))
end

function ui.touch_released(id, x, y, games, installed)
    if id ~= touch_id then return nil end
    touch_id = nil

    if math.abs(y - touch_start_y) > 15 then return nil end

    local w = love.graphics.getWidth()
    local positions = card_positions(#games)
    local margin = CARD_PAD

    for i, game in ipairs(games) do
        local cy = positions[i]
        local cx = margin
        local cw = w - margin * 2

        local is_installed = installed[game.id] ~= nil

        -- Delete button
        if is_installed then
            local dx, dy2 = delete_btn_rect(cx, cy, cw)
            if x >= dx and x <= dx + DEL_SZ and y >= dy2 and y <= dy2 + DEL_SZ then
                return "remove", game.id
            end
        end

        -- Action button
        local bx, by = action_btn_rect(cx, cy, cw)
        if x >= bx and x <= bx + BTN_W and y >= by and y <= by + BTN_H then
            local needs_update = is_installed and (
                installed[game.id].version ~= game.version or
                (game.size and installed[game.id].size and installed[game.id].size ~= game.size)
            )
            if not is_installed then
                return "download", game.id
            elseif needs_update then
                return "update", game.id
            else
                return "play", game.id
            end
        end
    end

    return nil
end

function ui.wheel_moved(dx, dy)
    scroll_y = scroll_y + dy * 40
    scroll_y = math.max(-max_scroll, math.min(0, scroll_y))
end

function ui.hit_refresh(x, y)
    local w, h = love.graphics.getDimensions()
    local footer_y = h - FOOTER_H
    local refresh_w, refresh_h = 76, 30
    local refresh_x = w - refresh_w - 14
    local refresh_y = footer_y + (FOOTER_H - refresh_h) / 2 + 1
    return x >= refresh_x and x <= refresh_x + refresh_w
       and y >= refresh_y and y <= refresh_y + refresh_h
end

function ui.reset_scroll()
    scroll_y = 0
end

--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------

function ui.format_size(bytes)
    if not bytes or bytes <= 0 then return "?" end
    if bytes < 1024 then return bytes .. " B" end
    if bytes < 1024 * 1024 then return string.format("%.1f KB", bytes / 1024) end
    return string.format("%.1f MB", bytes / (1024 * 1024))
end

return ui
