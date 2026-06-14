-- ui.lua - StoneGate visual layer (FlexLove edition)
-- Responsive card-grid UI that adapts to any screen size and orientation.

local ui = {}
local config = require("config")
local FlexLove = require("FlexLove")
local Color = FlexLove.Color

--------------------------------------------------------------------------------
-- Responsive sizing (computed at init from actual screen)
--------------------------------------------------------------------------------
local SW, SH = 480, 800       -- actual screen pixels
local S = 1                    -- master scale (relative to card)
local HEADER_H, FOOTER_H
local CARD_W, CARD_H, GRID_PAD, CARD_R
local BTN_W, BTN_H, BTN_R, DEL_SZ
local MIN_DIM = 0              -- screen shorter side (for responsive scaling)

local function compute_layout()
    local min_dim  = math.min(SW, SH)
    local max_dim  = math.max(SW, SH)
    local is_landscape = SW > SH
    MIN_DIM = min_dim

    -- Target cards per row by orientation. The value must leave headroom so
    -- that an extra card overflows and wraps; see content math below.
    local target_cards_per_row = is_landscape and 4 or 3

    -- Spacing constants derived from min_dim so they don't depend on CARD_W.
    local inter_card_gap = math.floor(min_dim * 0.04)   -- gap between cards
    local card_margin    = math.floor(min_dim * 0.02)   -- per-side card margin
    local grid_pad_ratio = 0.03                          -- padding as fraction of min_dim

    -- Content width inside scroll_area: SW minus padding on both sides.
    -- GRID_PAD is derived from min_dim (not CARD_W) to avoid a circular
    -- dependency during sizing.
    GRID_PAD = math.floor(min_dim * grid_pad_ratio)
    local content_w = SW - GRID_PAD * 2

    -- Solve for CARD_W so that `target_cards_per_row` cards occupy exactly
    -- 92% of content_w (footprint includes left+right margins). This leaves
    -- ~8% headroom, guaranteeing that a (target+1)th card overflows and the
    -- flex container wraps it onto the next row instead of squeezing it in.
    local target_fill_ratio = 0.92
    local total_footprint = math.floor(content_w * target_fill_ratio)
    local per_card_total = math.floor(total_footprint / target_cards_per_row)
    local raw_card_w = math.max(120, per_card_total - card_margin * 2)
    CARD_W = math.max(120, raw_card_w)
    CARD_H = math.floor(CARD_W * 1.35)
    CARD_R = math.floor(CARD_W * 0.08)

    HEADER_H = math.floor(min_dim * 0.065)
    FOOTER_H = math.floor(min_dim * 0.045)
    BTN_W    = math.floor(CARD_W * 0.55)
    BTN_H    = math.floor(CARD_W * 0.14)
    BTN_R    = math.floor(BTN_H / 2)
    DEL_SZ   = math.floor(CARD_W * 0.12)

    -- Master scale: 1.0 when card = 180px
    S = CARD_W / 180
end

-- Scaled font size for FlexLove text elements
local function ts(design_size)
    return math.max(8, math.floor(design_size * S))
end

--------------------------------------------------------------------------------
-- Color bridge
--------------------------------------------------------------------------------
local C = {}
local function to_color(rgb, a) return Color.new(rgb[1], rgb[2], rgb[3], a or 1) end
local function build_colors()
    for k, v in pairs(config.colors) do C[k] = to_color(v) end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local action_cb     = nil
local screens       = {}
local menu_refs     = {}
local current_state = "loading"
local fonts         = {}

-- Cached data for resize rebuild
local cached_games      = {}
local cached_installed  = {}
local cached_thumbnails = {}

--------------------------------------------------------------------------------
-- Drawing helpers
--------------------------------------------------------------------------------
local function lerp_color(a, b, t)
    return { a[1]+(b[1]-a[1])*t, a[2]+(b[2]-a[2])*t, a[3]+(b[3]-a[3])*t }
end
local function sc(rgb, a) love.graphics.setColor(rgb[1], rgb[2], rgb[3], a or rgb[4] or 1) end
local function rrect(mode, x, y, w, h, r)
    r = math.min(r, w/2, h/2)
    if love.graphics.roundedRectangle then love.graphics.roundedRectangle(mode, x, y, w, h, r)
    else love.graphics.rectangle(mode, x, y, w, h) end
end
local function gradient_v(x, y, w, h, tc, bc, at, ab)
    at, ab = at or 1, ab or 1
    local step = math.max(1, math.floor(h/40))
    for i = 0, h-1, step do
        local t = i/math.max(1,h-1); local c = lerp_color(tc, bc, t)
        love.graphics.setColor(c[1], c[2], c[3], at+(ab-at)*t)
        love.graphics.rectangle("fill", x, y+i, w, math.min(step, h-i))
    end
end
local function shadow(x, y, w, h, r, d)
    d = d or 4
    for i = d, 1, -1 do
        sc(config.colors.shadow, 0.12*(1-i/(d+1)))
        rrect("fill", x+i, y+i, w, h, r)
    end
end

--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------
function ui.format_size(bytes)
    if not bytes or bytes <= 0 then return "?" end
    if bytes < 1024 then return bytes.." B" end
    if bytes < 1024*1024 then return string.format("%.1f KB", bytes/1024) end
    return string.format("%.1f MB", bytes/(1024*1024))
end

--------------------------------------------------------------------------------
-- Screen visibility
--------------------------------------------------------------------------------
function ui.set_state(name)
    current_state = name
    for _, sname in ipairs({"loading","menu","downloading","error"}) do
        local el = screens[sname]
        if el then
            if sname == name then el:show() else el:hide() end
        end
    end
end

--------------------------------------------------------------------------------
-- Loading screen
--------------------------------------------------------------------------------
local function create_loading_screen()
    local root = FlexLove.new({
        positioning = "absolute", x = 0, y = 0,
        width = SW, height = SH, backgroundColor = C.bg, opacity = 1,
    })
    FlexLove.new({
        parent = root, positioning = "absolute", x = 0, y = 0,
        width = SW, height = SH,
        customDraw = function(self)
            local cx, cy = SW/2, SH/2 - math.floor(30*S)
            local t = love.timer.getTime()
            local base = math.floor(22*S)
            for i = 3, 1, -1 do
                local phase = (t*1.5 + i*0.4) % 1.8
                local scale = 0.3 + phase*0.7
                local alpha = math.max(0, 0.35 - phase*0.25)
                sc(config.colors.accent, alpha)
                love.graphics.setLineWidth(math.max(1, 1.5*S))
                love.graphics.circle("line", cx, cy, base + math.floor(30*S)*scale)
            end
            local pulse = 0.7 + math.sin(t*4)*0.3
            sc(config.colors.accent, pulse)
            love.graphics.circle("fill", cx, cy, math.floor(7*S))

            love.graphics.setFont(fonts.lg); sc(config.colors.text, 1)
            love.graphics.printf(config.app_name, 0, cy+math.floor(55*S), SW, "center")
            love.graphics.setFont(fonts.sm); sc(config.colors.text_dim, 1)
            love.graphics.printf("Loading game list"..string.rep(".", math.floor(t*2)%4), 0, cy+math.floor(85*S), SW, "center")
            sc(config.colors.text_dim, 0.4)
            love.graphics.printf(config.server_url, 0, cy+math.floor(105*S), SW, "center")
        end,
    })
    return root
end

--------------------------------------------------------------------------------
-- Error screen
--------------------------------------------------------------------------------
local err_msg, err_detail = "", ""
local function create_error_screen()
    local root = FlexLove.new({
        positioning = "absolute", x = 0, y = 0,
        width = SW, height = SH, backgroundColor = C.bg, opacity = 1,
        onEvent = function(self, event)
            if event.type == "click" or event.type == "release" then
                if action_cb then action_cb("retry") end
            end
        end,
    })
    FlexLove.new({
        parent = root, positioning = "absolute", x = 0, y = 0,
        width = SW, height = SH,
        customDraw = function(self)
            local cx, cy = SW/2, SH/2
            local r = math.floor(28*S)
            sc(config.colors.danger_dim, 0.25)
            love.graphics.circle("fill", cx, cy-math.floor(60*S), r)
            sc(config.colors.danger, 0.9)
            love.graphics.setLineWidth(math.max(1, 2.5*S))
            love.graphics.circle("line", cx, cy-math.floor(60*S), r)
            local d = math.floor(10*S)
            love.graphics.line(cx-d, cy-math.floor(70*S), cx+d, cy-math.floor(50*S))
            love.graphics.line(cx+d, cy-math.floor(70*S), cx-d, cy-math.floor(50*S))

            love.graphics.setFont(fonts.lg); sc(config.colors.danger, 1)
            love.graphics.printf("Something went wrong", 0, cy-math.floor(18*S), SW, "center")
            love.graphics.setFont(fonts.md); sc(config.colors.text, 1)
            love.graphics.printf(err_msg or "Unknown error", SW*0.08, cy+math.floor(16*S), SW*0.84, "center")
            if err_detail and err_detail ~= "" then
                love.graphics.setFont(fonts.sm); sc(config.colors.text_dim, 1)
                local det = #err_detail > 180 and err_detail:sub(1,180).."..." or err_detail
                love.graphics.printf(det, SW*0.08, cy+math.floor(46*S), SW*0.84, "center")
            end
            love.graphics.setFont(fonts.sm); sc(config.colors.text_dim, 0.5)
            love.graphics.printf("Tap anywhere to retry", 0, cy+math.floor(90*S), SW, "center")
        end,
    })
    return root
end

--------------------------------------------------------------------------------
-- Downloading screen
--------------------------------------------------------------------------------
local dl_game, dl_prog = nil, 0
local function create_downloading_screen()
    local root = FlexLove.new({
        positioning = "absolute", x = 0, y = 0,
        width = SW, height = SH, backgroundColor = C.bg, opacity = 1,
    })
    FlexLove.new({
        parent = root, positioning = "absolute", x = 0, y = 0,
        width = SW, height = SH,
        customDraw = function(self)
            local cx, cy = SW/2, SH/2
            local t = love.timer.getTime()
            love.graphics.setLineWidth(math.max(1, 2*S))
            local arc_r = math.floor(30*S)
            local angle = t * 3
            for i = 0, 11 do
                local a = angle + i * math.pi * 2 / 12
                sc(config.colors.accent, 0.1 + (i/12)*0.4)
                love.graphics.arc("line", "open", cx, cy-math.floor(40*S), arc_r, a, a+0.3)
            end
            love.graphics.setFont(fonts.lg); sc(config.colors.text_sub, 1)
            love.graphics.printf("Downloading", 0, cy+math.floor(10*S), SW, "center")
            love.graphics.setFont(fonts.md); sc(config.colors.accent, 1)
            love.graphics.printf(dl_game and (dl_game.name or dl_game.id) or "", 0, cy+math.floor(40*S), SW, "center")

            local bw = SW*0.65; local bh = math.max(3, math.floor(6*S))
            local bx = (SW-bw)/2; local by = cy+math.floor(70*S)
            sc(config.colors.card, 1); rrect("fill", bx, by, bw, bh, bh/2)
            local sp = ((t*0.8)%2.4)/2.4; local sw = bw*0.3
            sc(config.colors.accent, 0.6)
            rrect("fill", bx+sp*(bw-sw), by, sw, bh, bh/2)

            love.graphics.setFont(fonts.sm); sc(config.colors.text_dim, 1)
            love.graphics.printf(dl_prog > 0 and ui.format_size(dl_prog) or "Connecting...", 0, by+math.floor(16*S), SW, "center")
        end,
    })
    return root
end

--------------------------------------------------------------------------------
-- Menu screen (card grid)
--------------------------------------------------------------------------------
local function create_menu_screen()
    local root = FlexLove.new({
        positioning = "absolute", x = 0, y = 0,
        width = SW, height = SH, backgroundColor = C.bg, opacity = 1,
    })

    -- Header
    FlexLove.new({
        parent = root, positioning = "absolute", x = 0, y = 0,
        width = SW, height = HEADER_H,
        customDraw = function(self)
            gradient_v(0, 0, SW, HEADER_H, config.colors.bg_surface, config.colors.bg, 1, 0.85)
            love.graphics.setFont(fonts.lg)
            sc(config.colors.accent, 1)
            love.graphics.print("StoneGate", GRID_PAD*2, math.floor(HEADER_H*0.28))
            sc(config.colors.text_sub, 0.7)
            love.graphics.setFont(fonts.sm)
            love.graphics.print("Game Launcher", GRID_PAD*2, math.floor(HEADER_H*0.62))
            sc(config.colors.divider, 1)
            love.graphics.rectangle("fill", 0, HEADER_H-1, SW, 1)
        end,
    })

    -- Scrollable grid area
    local scroll_area = FlexLove.new({
        parent = root, positioning = "absolute",
        x = 0, y = HEADER_H,
        width = SW, height = SH - HEADER_H - FOOTER_H,
        flexDirection = "horizontal",
        flexWrap = "wrap",
        justifyContent = "flex-start",  -- left-align cards in each row for clean grid
        alignContent = "flex-start",
        overflowY = "auto",
        overflowX = "hidden",
        scrollbarWidth = math.max(2, math.floor(3*S)),
        scrollbarColor = Color.new(config.colors.text_dim[1], config.colors.text_dim[2], config.colors.text_dim[3], 0.15),
        padding = GRID_PAD,
    })

    -- FlexLove only honors flexDirection/flexWrap/etc when an element's
    -- positioning is "flex". scroll_area must be "absolute" to sit under the
    -- header, so mirror the requested flex props onto its layout engine.
    -- Without this, cards never wrap and overflow off-screen.
    do
        local le = scroll_area._layoutEngine
        if le then
            le.flexDirection  = "horizontal"
            le.flexWrap       = "wrap"
            le.justifyContent = "flex-start"
            le.alignContent   = "flex-start"
        end
    end

    -- Footer
    FlexLove.new({
        parent = root, positioning = "absolute",
        x = 0, y = SH - FOOTER_H,
        width = SW, height = FOOTER_H,
        customDraw = function(self)
            gradient_v(0, self.y, SW, FOOTER_H, config.colors.bg, config.colors.bg_surface, 0.7, 1)
            sc(config.colors.divider, 1)
            love.graphics.rectangle("fill", 0, self.y, SW, 1)
        end,
    })

    -- Footer row
    local fp = math.floor(14*S)
    local footer_row = FlexLove.new({
        parent = root, positioning = "absolute",
        x = fp, y = SH - FOOTER_H,
        width = SW - fp*2, height = FOOTER_H,
        flexDirection = "horizontal", alignItems = "center",
        justifyContent = "space-between",
    })
    local count_el = FlexLove.new({
        parent = footer_row, text = "0 games",
        autoScaleText = false, textSize = ts(14), textColor = C.text_dim,
    })
    local rfw, rfh = math.floor(76*S), math.floor(30*S)
    FlexLove.new({
        parent = footer_row,
        width = rfw, height = rfh,
        cornerRadius = rfh/2,
        backgroundColor = C.accent_dim,
        text = "Refresh", autoScaleText = false, textSize = ts(14), textAlign = "center", textColor = C.text,
        onEvent = function(self, event)
            if event.type == "click" and action_cb then action_cb("refresh") end
        end,
        customDraw = function(self)
            shadow(self.x, self.y, self.width, self.height, self.height/2, 3)
            local hi = lerp_color(config.colors.accent_dim, {1,1,1}, 0.15)
            love.graphics.setScissor(self.x, self.y, self.width, self.height/2)
            sc(hi, 0.25); rrect("fill", self.x, self.y, self.width, self.height/2, self.height/2)
            love.graphics.setScissor()
        end,
    })

    menu_refs = { scroll_area = scroll_area, count_el = count_el, root = root }
    return root
end

--------------------------------------------------------------------------------
-- Rebuild menu cards (grid)
--------------------------------------------------------------------------------

function ui.rebuild_cards(games, installed, thumbnails)
    -- Cache for resize rebuild
    cached_games      = games or {}
    cached_installed  = installed or {}
    cached_thumbnails = thumbnails or {}

    local scroll_area = menu_refs and menu_refs.scroll_area
    if not scroll_area then return end
    scroll_area:clearChildren()

    local pad   = math.floor(CARD_W * 0.06)
    local thumb = math.floor(CARD_W * 0.5)

    for i, game in ipairs(games) do
        local is_installed  = installed[game.id] ~= nil
        local needs_update  = is_installed and (
            installed[game.id].version ~= game.version or
            (game.size and installed[game.id].size and installed[game.id].size ~= game.size))
        local game_id = game.id

        local status_text, dot_color
        if not is_installed then status_text, dot_color = "Not downloaded", config.colors.accent
        elseif needs_update then status_text, dot_color = "Update available", config.colors.warning
        else status_text, dot_color = "Installed", config.colors.success end

        -- Button color based on state
        local btn_text, btn_color
        if not is_installed then btn_text, btn_color = "Get", config.colors.accent
        elseif needs_update then btn_text, btn_color = "Update", config.colors.warning
        else btn_text, btn_color = "Play", config.colors.success end

        local action_type = not is_installed and "download" or (needs_update and "update" or "play")

        -- Card: vertical block
        local card = FlexLove.new({
            parent = scroll_area, positioning = "relative",
            width = CARD_W, height = CARD_H,
            flexShrink = 0,
            margin = math.floor(MIN_DIM * 0.02),  -- consistent with inter_card_gap
            customDraw = function(self)
                shadow(self.x, self.y, self.width, self.height, CARD_R, 4)
                sc(config.colors.card, 1)
                rrect("fill", self.x, self.y, self.width, self.height, CARD_R)
                -- top highlight
                love.graphics.setScissor(self.x, self.y, self.width, 2)
                sc(config.colors.card_hi, 0.5)
                love.graphics.rectangle("fill", self.x + CARD_R, self.y, self.width - CARD_R*2, 1)
                love.graphics.setScissor()
            end,
        })

        -- Thumbnail (centered)
        local thumb_x = (CARD_W - thumb) / 2
        local thumb_y = pad + math.floor(CARD_W * 0.02)
        FlexLove.new({
            parent = card, positioning = "absolute",
            x = thumb_x, y = thumb_y, width = thumb, height = thumb,
            customDraw = function(self)
                local x, y = self.x, self.y
                local img = thumbnails and thumbnails[game_id]
                sc(config.colors.placeholder, 1)
                rrect("fill", x, y, thumb, thumb, math.floor(8*S))
                if img then
                    love.graphics.draw(img, x+2, y+2, 0, (thumb-4)/img:getWidth(), (thumb-4)/img:getHeight())
                else
                    local letter = (game_id or "?"):sub(1,1):upper()
                    love.graphics.setFont(fonts.thumb); sc(config.colors.accent, 0.6)
                    love.graphics.printf(letter, x, y + thumb/2 - fonts.thumb:getHeight()/2, thumb, "center")
                end
            end,
        })

        -- Game name
        local text_top = thumb_y + thumb + math.floor(CARD_W * 0.04)
        FlexLove.new({
            parent = card, positioning = "absolute",
            x = pad, y = text_top,
            width = CARD_W - pad*2, height = math.floor(CARD_W * 0.1),
            text = game.name or game.id,
            autoScaleText = false, textSize = ts(13), textAlign = "center", textColor = C.text,
        })

        -- Version + size
        local info = "v" .. (game.version or "?")
        if game.size then info = info .. "  · " .. ui.format_size(game.size) end
        FlexLove.new({
            parent = card, positioning = "absolute",
            x = pad, y = text_top + math.floor(CARD_W * 0.11),
            width = CARD_W - pad*2, height = math.floor(CARD_W * 0.08),
            text = info, autoScaleText = false, textSize = ts(10), textAlign = "center", textColor = C.text_sub,
        })

        -- Action button (centered near bottom)
        FlexLove.new({
            parent = card, positioning = "absolute",
            x = (CARD_W - BTN_W)/2,
            y = CARD_H - BTN_H - math.floor(CARD_W * 0.05),
            width = BTN_W, height = BTN_H,
            cornerRadius = BTN_R,
            backgroundColor = to_color(btn_color),
            text = btn_text, autoScaleText = false, textSize = ts(12), textAlign = "center", textColor = C.text,
            userdata = { game_id = game_id, action = action_type },
            onEvent = function(self, event)
                if event.type == "click" and action_cb then
                    action_cb(self.userdata.action, self.userdata.game_id)
                end
            end,
            customDraw = function(self)
                shadow(self.x, self.y, self.width, self.height, BTN_R, 3)
                local hi = lerp_color(btn_color, {1,1,1}, 0.15)
                love.graphics.setScissor(self.x, self.y, self.width, self.height/2)
                sc(hi, 0.25); rrect("fill", self.x, self.y, self.width, self.height/2, BTN_R)
                love.graphics.setScissor()
            end,
        })

        -- Delete (top-right, only if installed)
        if is_installed then
            FlexLove.new({
                parent = card, positioning = "absolute",
                x = CARD_W - DEL_SZ - math.floor(4*S), y = math.floor(4*S),
                width = DEL_SZ, height = DEL_SZ,
                cornerRadius = DEL_SZ/2,
                backgroundColor = Color.new(config.colors.danger_dim[1], config.colors.danger_dim[2], config.colors.danger_dim[3], 0.6),
                text = "×", autoScaleText = false, textSize = ts(10), textAlign = "center",
                textColor = Color.new(config.colors.danger[1], config.colors.danger[2], config.colors.danger[3], 0.7),
                onEvent = function(self, event)
                    if event.type == "click" and action_cb then action_cb("remove", game_id) end
                end,
            })
        end
    end

    if menu_refs.count_el then
        menu_refs.count_el:setText(#games .. " game" .. (#games ~= 1 and "s" or ""))
    end
end

--------------------------------------------------------------------------------
-- Update / Error
--------------------------------------------------------------------------------
function ui.update_download(game, progress) dl_game = game; dl_prog = progress or 0 end
function ui.update_error(msg, detail) err_msg = msg or "Unknown error"; err_detail = detail or "" end

--------------------------------------------------------------------------------
-- Recreate fonts at current scale
--------------------------------------------------------------------------------
local function rebuild_fonts()
    fonts.lg    = love.graphics.newFont(math.max(10, math.min(28, math.floor(math.min(SW,SH) * 0.016))))
    fonts.md    = love.graphics.newFont(ts(17))
    fonts.sm    = love.graphics.newFont(ts(14))
    fonts.btn   = love.graphics.newFont(ts(15))
    fonts.thumb = love.graphics.newFont(ts(28))
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------
function ui.init(on_action)
    action_cb = on_action
    SW, SH = love.graphics.getDimensions()
    compute_layout()
    build_colors()
    rebuild_fonts()


    screens.loading     = create_loading_screen()
    screens.error       = create_error_screen()
    screens.downloading = create_downloading_screen()
    screens.menu        = create_menu_screen()
    ui.set_state("loading")
end

--------------------------------------------------------------------------------
-- Resize 闁?called on orientation change to rebuild all screens
--------------------------------------------------------------------------------
function ui.resize(w, h)
    -- Use params from love.resize (more reliable than getDimensions inside callback)
    w = w or love.graphics.getWidth()
    h = h or love.graphics.getHeight()

    -- No-op if dimensions unchanged
    if w == SW and h == SH then return end

    SW, SH = w, h
    compute_layout()
    build_colors()
    rebuild_fonts()

    -- Destroy old screens
    for _, screen in pairs(screens) do
        if screen and screen.destroy then screen:destroy() end
    end
    screens = {}

    -- Recreate all screens with new dimensions
    screens.loading     = create_loading_screen()
    screens.error       = create_error_screen()
    screens.downloading = create_downloading_screen()
    screens.menu        = create_menu_screen()

    -- Restore current state
    ui.set_state(current_state)

    -- Rebuild cards if in menu state
    if current_state == "menu" then
        ui.rebuild_cards(cached_games, cached_installed, cached_thumbnails)
    end
end

return ui
