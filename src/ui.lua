-- ui.lua - All UI rendering and touch/mouse input handling for StoneGate
-- Draws: loading spinner, game list with cards + thumbnails, download progress, error screen.
-- Touch: scroll, tap cards to download/play, delete installed games.

local ui = {}

local config = require("config")

--------------------------------------------------------------------------------
-- Layout constants
--------------------------------------------------------------------------------
local CARD_H     = 110
local CARD_PAD   = 16
local CARD_R     = 10          -- card corner radius
local THUMB_SIZE = 76          -- thumbnail width & height
local THUMB_PAD  = 12          -- padding around thumbnail
local BTN_W      = 80
local BTN_H      = 34
local BTN_R      = 8
local DEL_W      = 30          -- small delete button width
local DEL_H      = 30
local DEL_R      = 6
local HEADER_H   = 60
local FOOTER_H   = 40

--------------------------------------------------------------------------------
-- Color helper
--------------------------------------------------------------------------------
local function color(c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

--------------------------------------------------------------------------------
-- Rounded-rect helper (compat with LÖVE < 11.3)
--------------------------------------------------------------------------------
local function rounded_rect(mode, x, y, w, h, r)
    if love.graphics.roundedRectangle then
        love.graphics.roundedRectangle(mode, x, y, w, h, r)
    else
        love.graphics.rectangle(mode, x, y, w, h)
    end
end

--------------------------------------------------------------------------------
-- Scroll state (managed by ui)
--------------------------------------------------------------------------------
local scroll_y = 0
local max_scroll = 0
local touch_id = nil
local touch_start_y = 0
local touch_start_scroll = 0
local touch_start_time = 0

--------------------------------------------------------------------------------
-- Layout calculation — returns the y position of each card
--------------------------------------------------------------------------------
local function card_positions(n, w)
    local positions = {}
    local y = HEADER_H + CARD_PAD + scroll_y
    for i = 1, n do
        positions[i] = y
        y = y + CARD_H + CARD_PAD
    end
    -- Calculate max scroll (content height - visible area)
    local content_h = y - scroll_y
    local screen_h = love.graphics.getHeight()
    max_scroll = math.max(0, content_h - screen_h + FOOTER_H)
    return positions
end

--------------------------------------------------------------------------------
-- Button position helpers
--------------------------------------------------------------------------------
local function action_btn_rect(card_x, card_y, card_w)
    local btn_x = card_x + card_w - BTN_W - 12
    local btn_y = card_y + (CARD_H - BTN_H) / 2
    return btn_x, btn_y
end

local function delete_btn_rect(card_x, card_y, card_w)
    -- Small "×" button to the left of the action button
    local abx, aby = action_btn_rect(card_x, card_y, card_w)
    return abx - DEL_W - 6, aby + (BTN_H - DEL_H) / 2
end

--------------------------------------------------------------------------------
-- Thumbnail drawing
--------------------------------------------------------------------------------
local function draw_thumbnail(game_id, x, y, thumb_imgs)
    local img = thumb_imgs and thumb_imgs[game_id]
    if img then
        -- Draw actual thumbnail
        color(config.colors.card)
        rounded_rect("fill", x, y, THUMB_SIZE, THUMB_SIZE, 6)
        love.graphics.draw(img, x, y, 0, THUMB_SIZE / img:getWidth(), THUMB_SIZE / img:getHeight())
    else
        -- Placeholder: dark rounded rect with first letter
        color(config.colors.placeholder)
        rounded_rect("fill", x, y, THUMB_SIZE, THUMB_SIZE, 6)
        color(config.colors.card_border)
        rounded_rect("line", x, y, THUMB_SIZE, THUMB_SIZE, 6)
        -- First letter
        local letter = (game_id or "?"):sub(1, 1):upper()
        color(config.colors.text_dim)
        love.graphics.printf(letter, x, y + THUMB_SIZE / 2 - 14, THUMB_SIZE, "center")
    end
end

--------------------------------------------------------------------------------
-- Drawing functions
--------------------------------------------------------------------------------

function ui.draw_loading()
    local w, h = love.graphics.getDimensions()
    color(config.colors.bg)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Animated dots
    local t = love.timer.getTime()
    local dots = string.rep(".", math.floor(t * 2) % 4)

    color(config.colors.text)
    love.graphics.printf(config.app_name, 0, h / 2 - 40, w, "center")

    color(config.colors.text_dim)
    love.graphics.printf("Loading game list" .. dots, 0, h / 2 - 10, w, "center")
    love.graphics.printf(config.server_url, 0, h / 2 + 15, w, "center")
end

function ui.draw_menu(games, installed, thumbnails)
    local w, h = love.graphics.getDimensions()

    -- Background
    color(config.colors.bg)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Header
    color(config.colors.accent)
    love.graphics.printf(config.app_name, 0, 18, w, "center")

    -- Cards (clipped to scroll area)
    love.graphics.setScissor(0, HEADER_H, w, h - HEADER_H - FOOTER_H)

    local positions = card_positions(#games, w)
    local margin = CARD_PAD

    for i, game in ipairs(games) do
        local cy = positions[i]
        local cx = margin
        local cw = w - margin * 2

        -- Skip cards that are fully off-screen
        if cy + CARD_H < HEADER_H or cy > h - FOOTER_H then
            -- skip drawing but keep in positions
        else
            local is_installed = installed[game.id] ~= nil
            local needs_update = is_installed and (
                installed[game.id].version ~= game.version or
                (game.size and installed[game.id].size and installed[game.id].size ~= game.size)
            )

            -- Card background
            color(config.colors.card)
            rounded_rect("fill", cx, cy, cw, CARD_H, CARD_R)

            -- Card border (subtle)
            color(config.colors.card_border)
            rounded_rect("line", cx, cy, cw, CARD_H, CARD_R)

            -- Thumbnail
            local thumb_x = cx + THUMB_PAD
            local thumb_y = cy + (CARD_H - THUMB_SIZE) / 2
            draw_thumbnail(game.id, thumb_x, thumb_y, thumbnails)

            -- Text area starts after thumbnail
            local text_x = thumb_x + THUMB_SIZE + THUMB_PAD
            local text_w = cw - (text_x - cx) - BTN_W - DEL_W - 30

            -- Game name
            color(config.colors.text)
            love.graphics.printf(game.name or game.id, text_x, cy + 12, text_w, "left")

            -- Version + size
            color(config.colors.text_dim)
            local info_line = "v" .. (game.version or "?")
            if game.size then
                info_line = info_line .. "  •  " .. ui.format_size(game.size)
            end
            love.graphics.printf(info_line, text_x, cy + 38, text_w, "left")

            -- Status label
            local status_text = is_installed and (needs_update and "Update available" or "Installed") or "Not downloaded"
            love.graphics.printf(status_text, text_x, cy + 62, text_w, "left")

            -- Action button
            local btn_text, btn_color
            if not is_installed then
                btn_text  = "Download"
                btn_color = config.colors.accent
            elseif needs_update then
                btn_text  = "Update"
                btn_color = config.colors.warning
            else
                btn_text  = "Play"
                btn_color = config.colors.success
            end

            local btn_x, btn_y = action_btn_rect(cx, cy, cw)
            color(btn_color)
            rounded_rect("fill", btn_x, btn_y, BTN_W, BTN_H, BTN_R)
            color(config.colors.text)
            love.graphics.printf(btn_text, btn_x, btn_y + 8, BTN_W, "center")

            -- Delete button (only for installed games)
            if is_installed then
                local del_x, del_y = delete_btn_rect(cx, cy, cw)
                color(config.colors.danger)
                rounded_rect("fill", del_x, del_y, DEL_W, DEL_H, DEL_R)
                color(config.colors.text)
                love.graphics.printf("×", del_x, del_y + 5, DEL_W, "center")
            end
        end
    end

    love.graphics.setScissor()

    -- Footer with refresh button
    local footer_y = h - FOOTER_H
    color(config.colors.card)
    love.graphics.rectangle("fill", 0, footer_y, w, FOOTER_H)

    -- Refresh button (right side of footer)
    local refresh_w = 80
    local refresh_h = 30
    local refresh_x = w - refresh_w - 12
    local refresh_y = footer_y + (FOOTER_H - refresh_h) / 2
    color(config.colors.accent)
    rounded_rect("fill", refresh_x, refresh_y, refresh_w, refresh_h, BTN_R)
    color(config.colors.text)
    love.graphics.printf("Refresh", refresh_x, refresh_y + 7, refresh_w, "center")

    -- Server info (left side)
    color(config.colors.text_dim)
    love.graphics.printf(config.server_url, 12, footer_y + 12, w - refresh_w - 30, "left")
end

function ui.draw_downloading(game, progress)
    local w, h = love.graphics.getDimensions()

    color(config.colors.bg)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Game name
    color(config.colors.text)
    love.graphics.printf("Downloading", 0, h / 2 - 60, w, "center")

    color(config.colors.accent)
    love.graphics.printf(game.name or game.id, 0, h / 2 - 30, w, "center")

    -- Progress info
    local progress_text
    if progress > 0 then
        progress_text = ui.format_size(progress) .. " downloaded"
    else
        progress_text = "Connecting..."
    end
    color(config.colors.text_dim)
    love.graphics.printf(progress_text, 0, h / 2 + 30, w, "center")
end

function ui.draw_error(msg, detail)
    local w, h = love.graphics.getDimensions()

    color(config.colors.bg)
    love.graphics.rectangle("fill", 0, 0, w, h)

    color(config.colors.danger)
    love.graphics.printf("Error", 0, h / 2 - 70, w, "center")

    color(config.colors.text)
    love.graphics.printf(msg or "Unknown error", w * 0.08, h / 2 - 35, w * 0.84, "center")

    -- Show error detail (e.g. crash log) if available
    if detail and detail ~= "" then
        color(config.colors.text_dim)
        -- Truncate detail for display
        local display_detail = detail
        if #display_detail > 200 then
            display_detail = display_detail:sub(1, 200) .. "..."
        end
        love.graphics.printf(display_detail, w * 0.08, h / 2 + 5, w * 0.84, "center")
    end

    color(config.colors.text_dim)
    love.graphics.printf("Tap anywhere to retry", 0, h / 2 + 55, w, "center")
end

--------------------------------------------------------------------------------
-- Touch / mouse handling
--------------------------------------------------------------------------------

--- Call from love.touchpressed / love.mousepressed.
--- Returns: action ("download"|"play"|"update") + game_id, or nil
function ui.touch_pressed(id, x, y)
    touch_id = id
    touch_start_y = y
    touch_start_scroll = scroll_y
    touch_start_time = love.timer.getTime()
    return nil  -- action is determined on release
end

--- Call from love.touchmoved / love.mousemoved.
function ui.touch_moved(id, x, y)
    if id ~= touch_id then return end
    local dy = y - touch_start_y
    scroll_y = touch_start_scroll + dy
    -- Clamp
    scroll_y = math.max(-max_scroll, math.min(0, scroll_y))
end

--- Call from love.touchreleased / love.mousereleased.
--- Returns: action + game_id if a card button was tapped, or nil
function ui.touch_released(id, x, y, games, installed)
    if id ~= touch_id then return nil end
    touch_id = nil

    -- If the finger moved too far, it was a scroll — not a tap
    local dy = math.abs(y - touch_start_y)
    local dt = love.timer.getTime() - touch_start_time
    if dy > 15 then return nil end

    -- Check if the tap hit a button
    local w = love.graphics.getWidth()
    local positions = card_positions(#games, w)
    local margin = CARD_PAD

    for i, game in ipairs(games) do
        local cy = positions[i]
        local cx = margin
        local cw = w - margin * 2

        -- Check delete button first (only for installed games)
        local is_installed = installed[game.id] ~= nil
        if is_installed then
            local del_x, del_y = delete_btn_rect(cx, cy, cw)
            if x >= del_x and x <= del_x + DEL_W and y >= del_y and y <= del_y + DEL_H then
                return "remove", game.id
            end
        end

        -- Check action button
        local btn_x, btn_y = action_btn_rect(cx, cy, cw)
        if x >= btn_x and x <= btn_x + BTN_W and y >= btn_y and y <= btn_y + BTN_H then
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

--- Handle mouse wheel for desktop testing.
function ui.wheel_moved(dx, dy)
    scroll_y = scroll_y + dy * 40
    scroll_y = math.max(-max_scroll, math.min(0, scroll_y))
end

--- Check if a tap hit the refresh button in the footer. Returns true if hit.
function ui.hit_refresh(x, y)
    local w, h = love.graphics.getDimensions()
    local footer_y = h - FOOTER_H
    local refresh_w = 80
    local refresh_h = 30
    local refresh_x = w - refresh_w - 12
    local refresh_y = footer_y + (FOOTER_H - refresh_h) / 2
    return x >= refresh_x and x <= refresh_x + refresh_w
       and y >= refresh_y and y <= refresh_y + refresh_h
end

--- Reset scroll position (e.g. after returning from a game).
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
