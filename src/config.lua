-- config.lua - Central configuration for StoneGate
-- Change server_url to match your development machine's LAN IP
local config = {
    -- App
    app_name = "StoneGate",

    -- Server
    server_url = "http://192.168.50.123:8080",
    list_endpoint = "/games/list.json",

    -- Local storage
    download_dir = "games",
    thumbnail_dir = "thumbnails",
    meta_file = "installed.json",

    -- Keys that exit a running game back to the shell
    back_keys = { escape = true, back = true },

    -- Theme: "warm boutique" — espresso-dark page, cream paper cards, earthy
    -- accents. Two text scales: light (on the dark page) and ink (on cream).
    colors = {
        -- Page
        bg            = { 0.115, 0.098, 0.082 },  -- warm roasted-coffee dark
        bg_surface    = { 0.155, 0.132, 0.110 },  -- header/footer surface
        -- Cream paper card
        card          = { 0.937, 0.905, 0.842 },
        card_hi       = { 0.985, 0.965, 0.915 },  -- soft top highlight on the card
        card_sunken   = { 0.870, 0.828, 0.752 },  -- inset wells on the card (cover bg)
        shadow        = { 0.04, 0.025, 0.015 },   -- warm near-black; alpha applied at use
        -- Text on the dark page
        text          = { 0.945, 0.915, 0.855 },
        text_sub      = { 0.715, 0.655, 0.575 },
        text_dim      = { 0.500, 0.450, 0.385 },
        -- Text on cream cards (espresso ink)
        ink           = { 0.205, 0.165, 0.130 },
        ink_sub       = { 0.455, 0.395, 0.330 },
        -- Status / semantic (all muted earth tones, never neon)
        accent        = { 0.800, 0.450, 0.320 },  -- terracotta (default)
        accent_dim    = { 0.560, 0.310, 0.225 },
        success       = { 0.360, 0.480, 0.320 },  -- moss green (installed / play)
        success_dim   = { 0.220, 0.290, 0.195 },
        warning        = { 0.820, 0.600, 0.260 }, -- ochre (update available)
        warning_dim    = { 0.350, 0.260, 0.120 },
        danger        = { 0.760, 0.360, 0.300 },  -- burnt sienna (delete)
        danger_dim    = { 0.330, 0.190, 0.155 },
        placeholder   = { 0.870, 0.828, 0.752 },  -- = card_sunken
        divider       = { 0.235, 0.200, 0.168 },
    },

    -- Each game gets a stable earth-tone accent derived from a hash of its id,
    -- so empty thumbnails become a designed color identity instead of a grey
    -- block — no dependency on the game shipping artwork.
    accents = {
        { 0.800, 0.420, 0.300 },  -- terracotta
        { 0.500, 0.540, 0.340 },  -- olive
        { 0.820, 0.620, 0.300 },  -- ochre
        { 0.720, 0.460, 0.460 },  -- clay rose
        { 0.450, 0.520, 0.560 },  -- slate blue
        { 0.640, 0.480, 0.640 },  -- dusty plum
        { 0.780, 0.540, 0.350 },  -- caramel
        { 0.400, 0.560, 0.500 },  -- teal sage
    },

    -- Game-feel tuning (kept here so the whole launcher's feel is调一处). All
    -- values are deliberately restrained — subtle, not bouncy.
    fx = {
        press_scale  = 0.96,   -- how far a card/button shrinks while held
        hover_lift   = 3,      -- px a card rises on hover (scaled by S at use site)
        anim_speed   = 14,     -- exponential approach rate toward hover/press targets
        fade_time    = 0.16,   -- screen-transition fade-in duration (seconds)
    },
}

return config
