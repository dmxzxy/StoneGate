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
local S = 1                    -- master scale (relative to a 480px-wide phone)
local HEADER_H, FOOTER_H
local CARD_W, CARD_H, GRID_PAD, CARD_R
local COVER_SZ                  -- square accent cover on the left of each row
local BTN_W, BTN_H, BTN_R, DEL_SZ
local MIN_DIM = 0              -- screen shorter side (for responsive scaling)

-- Pre-rendered backgrounds. The card body (shadow + rounded cream fill + top
-- highlight) and the header/footer surfaces are static for a given layout, so
-- we bake them into canvases once and blit instead of re-drawing dozens of
-- rects every frame. Rebuilt on resize; set USE_CACHE=false to fall back to
-- per-frame drawing if a device's GPU mishandles canvases.
local USE_CACHE = true
local SHADOW_PAD = 10          -- px of slack around the card canvas so the soft drop shadow isn't clipped
local card_canvas              -- baked card body (size = CARD_W+2*pad × CARD_H+2*pad)
local header_canvas, footer_canvas

local function compute_layout()
    local min_dim  = math.min(SW, SH)
    local is_landscape = SW > SH
    MIN_DIM = min_dim

    -- Column count by orientation: one wide row in portrait, two in landscape.
    local cols = is_landscape and 2 or 1

    -- Derive the master scale from the actual COLUMN width, not the raw screen
    -- edge. Type and card chrome must fit the card they live in; basing S on the
    -- short edge let a big desktop window (e.g. 1000×800) balloon the type while
    -- each two-up card stayed narrow, so the title overflowed and wrapped.
    -- A reference column of ~440px design-px maps to S=1.
    local raw_pad   = math.floor(SW * 0.038)
    local raw_gap   = math.floor(SW * 0.03)
    local raw_lane  = math.floor(SW * 0.016)
    local col_w     = (SW - raw_pad * 2 - raw_lane - raw_gap * (cols - 1)) / cols
    S = math.max(0.75, math.min(1.6, col_w / 440))

    GRID_PAD = math.floor(18 * S)
    local gap = math.floor(14 * S)            -- also each card's total horizontal margin
    local content_w = SW - GRID_PAD * 2
    local lane = math.floor(8 * S)
    CARD_W = math.floor((content_w - lane) / cols) - gap
    CARD_H = math.floor(92 * S)
    CARD_R = math.floor(18 * S)

    COVER_SZ = CARD_H - math.floor(22 * S)   -- inset square cover, vertically centered

    HEADER_H = math.floor(72 * S)
    FOOTER_H = math.floor(54 * S)
    BTN_H    = math.floor(36 * S)
    BTN_W    = math.floor(92 * S)
    BTN_R    = math.floor(BTN_H / 2)
    DEL_SZ   = math.floor(30 * S)
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

-- Stable per-game accent: hash the id into the earth-tone palette so every game
-- has a consistent color identity even with no thumbnail.
local function accent_for(id)
    local pal = config.accents
    local h = 0
    for i = 1, #(id or "?") do h = (h * 31 + id:byte(i)) % 4294967296 end
    return pal[(h % #pal) + 1]
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local action_cb     = nil
local screens       = {}
local menu_refs     = {}
local current_state = "loading"
local fonts         = {}
local screen_fade   = 1   -- 0 right after a state change, eased to 1 (full fade-in)

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
-- Soft, downward-biased drop shadow. Layers expanding rounded rects below the
-- element with falloff alpha — reads as ambient depth, not a hard diagonal.
local function shadow(x, y, w, h, r, spread, dy, strength)
    spread   = spread or 6
    dy       = dy or 3
    strength = strength or 0.10
    for i = spread, 1, -1 do
        local t = i / spread
        sc(config.colors.shadow, strength * (1 - t) * (1 - t))
        rrect("fill", x - i, y - i + dy, w + i*2, h + i*2, r + i)
    end
end

--------------------------------------------------------------------------------
-- Interaction feel: per-element hover/press state that eases toward a target.
-- Attach _fx to any FlexLove element, drive targets from its onEvent, and call
-- fx_step() each frame inside customDraw (it pulls dt from love.timer).
--------------------------------------------------------------------------------
local function fx_new()
    return { hover = 0, press = 0, hover_t = 0, press_t = 0 }
end
-- Update the fx struct toward its targets; returns hover, press in [0,1].
local function fx_step(fx)
    if not fx then return 0, 0 end
    local dt = love.timer.getDelta()
    local k = math.min(1, dt * config.fx.anim_speed)
    fx.hover = fx.hover + (fx.hover_t - fx.hover) * k
    fx.press = fx.press + (fx.press_t - fx.press) * k
    return fx.hover, fx.press
end
-- Wire hover/press target changes from an event into an fx struct.
local function fx_handle_event(fx, event)
    local t = event.type
    if t == "hover" then fx.hover_t = 1
    elseif t == "unhover" then fx.hover_t = 0; fx.press_t = 0
    elseif t == "press" or t == "touchpress" then fx.press_t = 1
    elseif t == "release" or t == "click" or t == "touchrelease" then fx.press_t = 0 end
end

--------------------------------------------------------------------------------
-- Pre-rendered backgrounds (built once per layout, blitted each frame)
--------------------------------------------------------------------------------
local function release_canvases()
    for _, c in ipairs({ card_canvas, header_canvas, footer_canvas }) do
        if c then pcall(function() c:release() end) end
    end
    card_canvas, header_canvas, footer_canvas = nil, nil, nil
end

-- Per-game cover art, generated procedurally: a rounded square with a diagonal
-- two-tone gradient derived from the game's accent, plus a faint geometric
-- motif. Keyed by game id, rebuilt on layout change. Baked to a canvas at
-- rebuild time (no scroll transform in effect), so the rounded mask can use a
-- stencil safely — a runtime scissor would be misplaced under scrolling.
local cover_cache = {}   -- [game_id] = Canvas
local function release_covers()
    for _, c in pairs(cover_cache) do
        if c then pcall(function() c:release() end) end
    end
    cover_cache = {}
end

local function build_cover(accent)
    local sz = COVER_SZ
    local r  = math.floor(sz * 0.26)
    local cv = love.graphics.newCanvas(sz, sz)
    -- stencil=true so we can mask the rounded corners while rendering to canvas.
    love.graphics.setCanvas({ cv, stencil = true })
    love.graphics.clear(0, 0, 0, 0)

    -- Two tones from the accent: lighter top-left → deeper bottom-right.
    local hi = lerp_color(accent, {1, 1, 1}, 0.22)
    local lo = lerp_color(accent, {0, 0, 0}, 0.26)
    local mid = lerp_color(hi, lo, 0.5)

    -- Round-rect mask via stencil, then fill with a 4-corner gradient mesh.
    love.graphics.stencil(function() rrect("fill", 0, 0, sz, sz, r) end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    local mesh = love.graphics.newMesh({
        { 0,  0,  0, 0, hi[1],  hi[2],  hi[3],  1 },
        { sz, 0,  1, 0, mid[1], mid[2], mid[3], 1 },
        { sz, sz, 1, 1, lo[1],  lo[2],  lo[3],  1 },
        { 0,  sz, 0, 1, mid[1], mid[2], mid[3], 1 },
    }, "fan", "static")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)

    -- Faint geometric motif: two thin diagonal bands for a designed texture.
    love.graphics.setColor(1, 1, 1, 0.07)
    love.graphics.setLineWidth(math.max(2, sz * 0.06))
    love.graphics.line(-sz*0.1, sz*0.55, sz*0.55, -sz*0.1)
    love.graphics.line(sz*0.45, sz*1.1, sz*1.1, sz*0.45)
    love.graphics.setStencilTest()

    love.graphics.setCanvas()
    pcall(function() mesh:release() end)
    return cv
end

local function build_canvases()
    release_canvases()
    if not USE_CACHE then return end

    -- Card body: soft warm shadow + cream rounded fill + subtle top highlight,
    -- offset by SHADOW_PAD so the shadow has room to bleed inside the canvas.
    local cw, ch = CARD_W + SHADOW_PAD * 2, CARD_H + SHADOW_PAD * 2
    card_canvas = love.graphics.newCanvas(cw, ch)
    love.graphics.setCanvas(card_canvas)
    love.graphics.clear(0, 0, 0, 0)
    do
        local ox, oy = SHADOW_PAD, SHADOW_PAD
        shadow(ox, oy, CARD_W, CARD_H, CARD_R, math.floor(7*S), math.floor(4*S), 0.16)
        -- Cream fill with a faint vertical sheen (lighter at top).
        gradient_v(ox, oy, CARD_W, CARD_H, config.colors.card_hi, config.colors.card, 1, 1)
        -- Re-cut the rounded silhouette over the rectangular gradient by drawing
        -- the rounded fill on top in the base cream; the gradient peeks at center.
        sc(config.colors.card, 1)
        rrect("fill", ox, oy, CARD_W, CARD_H, CARD_R)
        -- Crisp 1px top highlight along the rounded top edge.
        love.graphics.setScissor(ox, oy, CARD_W, math.max(1, math.floor(2*S)))
        sc(config.colors.card_hi, 0.9)
        rrect("fill", ox, oy, CARD_W, CARD_H, CARD_R)
        love.graphics.setScissor()
    end

    -- Header / footer surface strips (full screen width), warm gradient + hairline.
    header_canvas = love.graphics.newCanvas(SW, HEADER_H)
    love.graphics.setCanvas(header_canvas)
    love.graphics.clear(0, 0, 0, 0)
    gradient_v(0, 0, SW, HEADER_H, config.colors.bg_surface, config.colors.bg, 1, 1)
    sc(config.colors.divider, 1)
    love.graphics.rectangle("fill", 0, HEADER_H-1, SW, 1)

    footer_canvas = love.graphics.newCanvas(SW, FOOTER_H)
    love.graphics.setCanvas(footer_canvas)
    love.graphics.clear(0, 0, 0, 0)
    gradient_v(0, 0, SW, FOOTER_H, config.colors.bg, config.colors.bg_surface, 1, 1)
    sc(config.colors.divider, 1)
    love.graphics.rectangle("fill", 0, 0, SW, 1)

    love.graphics.setCanvas()
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
    if name ~= current_state then screen_fade = 0 end  -- retrigger fade-in
    current_state = name
    for _, sname in ipairs({"loading","menu","downloading","error"}) do
        local el = screens[sname]
        if el then
            if sname == name then el:show() else el:hide() end
        end
    end
end

-- Quick fade-in after each state change. Drawn by main.lua AFTER FlexLove so it
-- sits above everything; kept out of the FlexLove tree on purpose — a full-screen
-- element there would also block input to the cards beneath it.
function ui.draw_fade()
    screen_fade = math.min(1, screen_fade + love.timer.getDelta() / config.fx.fade_time)
    if screen_fade < 1 then
        sc(config.colors.bg, 1 - screen_fade)
        love.graphics.rectangle("fill", 0, 0, SW, SH)
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
local dl_game, dl_prog, dl_total = nil, 0, 0
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
            if dl_total > 0 then
                -- Real progress: fill proportional to bytes downloaded
                local frac = math.max(0, math.min(1, dl_prog/dl_total))
                sc(config.colors.accent, 1)
                rrect("fill", bx, by, math.max(bh, bw*frac), bh, bh/2)
            else
                -- Unknown total: keep the indeterminate sweeping bar
                local sp = ((t*0.8)%2.4)/2.4; local sw = bw*0.3
                sc(config.colors.accent, 0.6)
                rrect("fill", bx+sp*(bw-sw), by, sw, bh, bh/2)
            end

            love.graphics.setFont(fonts.sm); sc(config.colors.text_dim, 1)
            local label
            if dl_total > 0 then
                label = string.format("%s / %s (%d%%)", ui.format_size(dl_prog),
                    ui.format_size(dl_total), math.floor(dl_prog/dl_total*100))
            elseif dl_prog > 0 then
                label = ui.format_size(dl_prog)
            else
                label = "Connecting..."
            end
            love.graphics.printf(label, 0, by+math.floor(16*S), SW, "center")
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
            if header_canvas then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(header_canvas, 0, 0)
            else
                gradient_v(0, 0, SW, HEADER_H, config.colors.bg_surface, config.colors.bg, 1, 0.85)
                sc(config.colors.divider, 1)
                love.graphics.rectangle("fill", 0, HEADER_H-1, SW, 1)
            end
            love.graphics.setFont(fonts.lg)
            sc(config.colors.text, 1)
            love.graphics.print("StoneGate", GRID_PAD, math.floor(HEADER_H*0.24))
            -- terracotta dot after the wordmark — small brand mark
            local tw = fonts.lg:getWidth("StoneGate")
            sc(config.colors.accent, 1)
            love.graphics.circle("fill", GRID_PAD + tw + math.floor(8*S), math.floor(HEADER_H*0.24) + fonts.lg:getHeight()*0.5, math.floor(4*S))
            sc(config.colors.text_sub, 1)
            love.graphics.setFont(fonts.sm)
            love.graphics.print("游戏库", GRID_PAD, math.floor(HEADER_H*0.62))
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

    -- Footer: count label (left) + flat Refresh pill (right), both in Inter to
    -- match the cards. count text lives in an upvalue the bar draws each frame.
    local count_text = "0 games"
    local fp = math.floor(16 * S)
    local rfw, rfh = math.floor(92 * S), math.floor(34 * S)

    FlexLove.new({
        parent = root, positioning = "absolute",
        x = 0, y = SH - FOOTER_H,
        width = SW, height = FOOTER_H,
        customDraw = function(self)
            if footer_canvas then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(footer_canvas, 0, self.y)
            else
                gradient_v(0, self.y, SW, FOOTER_H, config.colors.bg, config.colors.bg_surface, 0.7, 1)
                sc(config.colors.divider, 1)
                love.graphics.rectangle("fill", 0, self.y, SW, 1)
            end
            -- Count label, vertically centered.
            love.graphics.setFont(fonts.sm); sc(config.colors.text_dim, 1)
            love.graphics.printf(count_text, fp, self.y + FOOTER_H/2 - fonts.sm:getHeight()/2, SW, "left")
        end,
    })

    local refresh_fx = fx_new()
    FlexLove.new({
        parent = root, positioning = "absolute",
        x = SW - rfw - fp, y = SH - FOOTER_H + math.floor((FOOTER_H - rfh)/2),
        width = rfw, height = rfh,
        onEvent = function(self, event)
            fx_handle_event(refresh_fx, event)
            if event.type == "click" and action_cb then action_cb("refresh") end
        end,
        customDraw = function(self)
            local hover, press = fx_step(refresh_fx)
            local s = 1 - press * (1 - config.fx.press_scale)
            love.graphics.push()
            local mx, my = self.x + self.width/2, self.y + self.height/2
            love.graphics.translate(mx, my); love.graphics.scale(s, s); love.graphics.translate(-mx, -my)
            -- Flat terracotta pill, brightening slightly on hover.
            local col = lerp_color(config.colors.accent, {1,1,1}, hover * 0.10)
            sc(col, 1)
            rrect("fill", self.x, self.y, self.width, self.height, self.height/2)
            love.graphics.setFont(fonts.btn); sc({1,1,1}, 0.97)
            love.graphics.printf("Refresh", self.x, my - fonts.btn:getHeight()/2, self.width, "center")
            love.graphics.pop()
        end,
    })

    menu_refs = {
        scroll_area = scroll_area, root = root,
        set_count = function(t) count_text = t end,
    }
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

    -- Regenerate procedural cover art for this game set (sizes depend on layout).
    release_covers()
    if USE_CACHE then
        for _, game in ipairs(games) do
            cover_cache[game.id] = build_cover(accent_for(game.id))
        end
    end

    -- Row-card geometry, in card-local coordinates. Constant per layout, reused
    -- for drawing and hit-testing. Layout: [cover] name/version … [× pill].
    -- The delete glyph sits to the LEFT of the pill, both vertically centered,
    -- so they never overlap (an earlier top-right delete clipped the pill).
    local inset    = math.floor((CARD_H - COVER_SZ) / 2)   -- cover inset = vertical centering
    local cover_x  = inset
    local cover_y  = inset
    local text_x   = cover_x + COVER_SZ + math.floor(16 * S)
    local pill_w   = BTN_W
    local pill_h   = BTN_H
    local pill_x   = CARD_W - pill_w - math.floor(16 * S)
    local pill_y   = math.floor((CARD_H - pill_h) / 2)
    local del_sz   = DEL_SZ
    local del_x    = pill_x - del_sz - math.floor(12 * S)
    local del_y    = math.floor((CARD_H - del_sz) / 2)
    local del_hit  = math.floor(del_sz * 0.5)
    local vgap     = math.floor(14 * S)

    for i, game in ipairs(games) do
        local is_installed  = installed[game.id] ~= nil
        local needs_update  = is_installed and (
            installed[game.id].version ~= game.version or
            (game.size and installed[game.id].size and installed[game.id].size ~= game.size))
        local game_id = game.id

        -- Pill + primary action depend on install state.
        local btn_text, btn_color
        if not is_installed then btn_text, btn_color = "Get", config.colors.accent
        elseif needs_update then btn_text, btn_color = "Update", config.colors.warning
        else btn_text, btn_color = "Play", config.colors.success end

        local action_type = not is_installed and "download" or (needs_update and "update" or "play")

        local info = "v" .. (game.version or "?")
        if game.size then info = info .. "   ·   " .. ui.format_size(game.size) end

        local name = game.name or game_id
        local cover = accent_for(game_id)          -- stable per-game earth tone
        -- Text runs up to the delete glyph (installed) or the pill (otherwise).
        local text_w = (is_installed and del_x or pill_x) - text_x - math.floor(10 * S)
        local fx = fx_new()
        -- Per-card gesture state for tap-vs-drag arbitration (see onEvent).
        -- `touch` latches once real touch events arrive so the emulated-mouse
        -- polling path is ignored for scrolling; `fired` dedupes the action when
        -- both paths synthesize a click for the same tap.
        local g = { down = false, touch = false, dragged = false, fired = false,
                    x0 = 0, y0 = 0, lasty = 0 }

        -- One element per card: it draws everything and resolves its own clicks.
        -- The whole row is the primary action (play / download / update); the
        -- delete glyph carves out an excluded hit region. Single draw call, and
        -- it sidesteps FlexLove's touch model where overlapping children fire.
        FlexLove.new({
            parent = scroll_area, positioning = "relative",
            width = CARD_W, height = CARD_H,
            flexShrink = 0,
            margin = math.floor(vgap / 2),
            onEvent = function(self, event)
                fx_handle_event(fx, event)
                local et = event.type

                -- Tap-vs-drag arbitration. The card owns the whole gesture (it has
                -- onEvent), so scroll_area never sees a finger that starts on a
                -- card. We track movement here: once it passes DRAG_SLOP it's a
                -- scroll — forward the delta to scroll_area and mark the gesture so
                -- the trailing click is suppressed (no accidental launch).
                -- Touch is authoritative; the emulated-mouse path only drives
                -- scrolling on real desktops (where no touch events ever arrive).
                local DRAG_SLOP = math.floor(8 * S)

                if et == "press" or et == "touchpress" then
                    g.down = true; g.dragged = false; g.fired = false
                    if et == "touchpress" then g.touch = true end
                    g.x0, g.y0, g.lasty = event.x, event.y, event.y
                    fx.press_t = 1
                elseif et == "drag" or et == "touchmove" then
                    if et == "touchmove" then g.touch = true end
                    if g.down then
                        if math.abs(event.x - g.x0) > DRAG_SLOP or math.abs(event.y - g.y0) > DRAG_SLOP then
                            g.dragged = true
                            fx.press_t = 0   -- drop the press visual once scrolling
                        end
                        local authoritative = (et == "touchmove") or (not g.touch)
                        if authoritative then
                            if g.dragged and menu_refs.scroll_area then
                                menu_refs.scroll_area:scrollBy(0, -(event.y - g.lasty))
                            end
                            g.lasty = event.y
                        end
                    end
                elseif et == "click" then
                    g.down = false
                    if g.dragged or g.fired then return end   -- was a scroll, or already handled
                    g.fired = true
                    if action_cb then
                        local lx, ly = event.x - self.x, event.y - self.y
                        if is_installed
                           and lx >= del_x - del_hit and lx <= del_x + del_sz + del_hit
                           and ly >= del_y - del_hit and ly <= del_y + del_sz + del_hit then
                            action_cb("remove", game_id)
                        else
                            action_cb(action_type, game_id)
                        end
                    end
                elseif et == "release" or et == "touchrelease" then
                    g.down = false
                end
            end,
            customDraw = function(self)
                local hover, press = fx_step(fx)
                local lift = hover * config.fx.hover_lift * S
                local s = 1 - press * (1 - config.fx.press_scale)

                love.graphics.push()
                local cx, cy = self.x + self.width/2, self.y + self.height/2
                love.graphics.translate(cx, cy - lift)
                love.graphics.scale(s, s)
                love.graphics.translate(-cx, -cy)

                local ox, oy = self.x, self.y

                -- Cream card body (baked) or per-frame fallback.
                if card_canvas then
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(card_canvas, ox - SHADOW_PAD, oy - SHADOW_PAD)
                else
                    shadow(ox, oy, CARD_W, CARD_H, CARD_R, math.floor(7*S), math.floor(4*S), 0.16)
                    sc(config.colors.card, 1)
                    rrect("fill", ox, oy, CARD_W, CARD_H, CARD_R)
                end
                -- Hover: warm the whole card a touch (focus cue).
                if hover > 0.01 then
                    sc(cover, hover * 0.06)
                    rrect("fill", ox, oy, CARD_W, CARD_H, CARD_R)
                end

                -- Cover: procedurally generated gradient art (cached per game) +
                -- big initial. Baked canvas, so just a shadow + blit here.
                local cvx, cvy = ox + cover_x, oy + cover_y
                local cover_r = math.floor(COVER_SZ * 0.26)
                shadow(cvx, cvy, COVER_SZ, COVER_SZ, cover_r, math.floor(4*S), math.floor(2*S), 0.10)
                local cc = cover_cache[game_id]
                if cc then
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(cc, cvx, cvy)
                else
                    sc(cover, 1)
                    rrect("fill", cvx, cvy, COVER_SZ, COVER_SZ, cover_r)
                end
                local img = thumbnails and thumbnails[game_id]
                if img then
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(img, cvx+2, cvy+2, 0, (COVER_SZ-4)/img:getWidth(), (COVER_SZ-4)/img:getHeight())
                else
                    local letter = (game_id or "?"):sub(1,1):upper()
                    love.graphics.setFont(fonts.cover); sc({1,1,1}, 0.95)
                    love.graphics.printf(letter, cvx, cvy + COVER_SZ/2 - fonts.cover:getHeight()/2, COVER_SZ, "center")
                end

                -- Name + version (ink on cream), vertically grouped near center.
                local name_y = oy + math.floor(CARD_H * 0.27)
                local info_y = oy + math.floor(CARD_H * 0.54)
                love.graphics.setFont(fonts.card_name); sc(config.colors.ink, 1)
                love.graphics.printf(name, text_x + ox, name_y, text_w, "left")
                love.graphics.setFont(fonts.card_info); sc(config.colors.ink_sub, 1)
                love.graphics.printf(info, text_x + ox, info_y, text_w, "left")

                -- Action pill (flat filled earth tone, white label).
                local bx, by = ox + pill_x, oy + pill_y
                shadow(bx, by, pill_w, pill_h, BTN_R, math.floor(4*S), math.floor(2*S), 0.14)
                sc(btn_color, 1); rrect("fill", bx, by, pill_w, pill_h, BTN_R)
                love.graphics.setFont(fonts.card_btn); sc({1,1,1}, 0.97)
                love.graphics.printf(btn_text, bx, by + pill_h/2 - fonts.card_btn:getHeight()/2, pill_w, "center")

                -- Delete glyph (installed only): a soft circular button, clearer on hover.
                if is_installed then
                    local dx, dy = ox + del_x, oy + del_y
                    sc(config.colors.danger, 0.18 + hover * 0.20)
                    rrect("fill", dx, dy, del_sz, del_sz, del_sz/2)
                    sc({1,1,1}, 0.80 + hover * 0.20)
                    love.graphics.setFont(fonts.card_info)
                    love.graphics.printf("×", dx, dy + del_sz/2 - fonts.card_info:getHeight()/2, del_sz, "center")
                end

                love.graphics.pop()
            end,
        })
    end

    if menu_refs.set_count then
        menu_refs.set_count(#games .. " game" .. (#games ~= 1 and "s" or ""))
    end
end

--------------------------------------------------------------------------------
-- Update / Error
--------------------------------------------------------------------------------
function ui.update_download(game, progress, total) dl_game = game; dl_prog = progress or 0; dl_total = total or 0 end
function ui.update_error(msg, detail) err_msg = msg or "Unknown error"; err_detail = detail or "" end

--------------------------------------------------------------------------------
-- Recreate fonts at current scale
--------------------------------------------------------------------------------
-- Typeface: Inter for Latin (weighted display), Noto Sans SC as a CJK fallback
-- so Chinese game names / labels render instead of tofu boxes. The 8MB CJK
-- file is loaded once as Data and reused across sizes. Falls back to LÖVE's
-- default font if the assets are missing.
local FONT_FILES = {
    regular  = "assets/fonts/Inter-Regular.ttf",
    medium   = "assets/fonts/Inter-Medium.ttf",
    semibold = "assets/fonts/Inter-SemiBold.ttf",
    bold     = "assets/fonts/Inter-Bold.ttf",
}
local CJK_FILE = "assets/fonts/NotoSansSC-Regular.otf"
local cjk_data                    -- reusable Data for the CJK fallback

local function mkfont(weight, size)
    size = math.max(1, math.floor(size))
    local path = FONT_FILES[weight] or FONT_FILES.regular
    local ok, f = pcall(love.graphics.newFont, path, size)
    if not ok then return love.graphics.newFont(size) end  -- assets stripped → default
    if cjk_data == nil then
        local got, data = pcall(love.filesystem.newFileData, CJK_FILE)
        cjk_data = got and data or false
    end
    if cjk_data then
        local cok, cjk = pcall(love.graphics.newFont, cjk_data, size)
        if cok then pcall(function() f:setFallbacks(cjk) end) end
    end
    f:setFilter("linear", "linear")   -- crisp downscaled glyphs
    return f
end

local function rebuild_fonts()
    fonts.lg    = mkfont("bold",     22 * S)   -- header wordmark
    fonts.md    = mkfont("regular",  17 * S)
    fonts.sm    = mkfont("medium",   13 * S)
    fonts.btn   = mkfont("semibold", 15 * S)
    fonts.thumb = mkfont("bold",     28 * S)
    -- Manually-drawn card content.
    fonts.card_name = mkfont("semibold", 18 * S)  -- game title (ink on cream)
    fonts.card_info = mkfont("regular",  12.5 * S) -- version · size
    fonts.card_btn  = mkfont("semibold", 14 * S)  -- pill label
    fonts.cover     = mkfont("bold", COVER_SZ * 0.46)  -- big initial on the cover
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
    build_canvases()


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
    build_canvases()

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
