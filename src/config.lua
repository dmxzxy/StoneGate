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

    -- Theme colors (RGB, 0-1) — refined dark palette with depth
    colors = {
        bg            = { 0.06, 0.06, 0.10 },
        bg_surface    = { 0.09, 0.09, 0.14 },   -- slightly lighter surface
        card          = { 0.12, 0.13, 0.19 },
        card_hi       = { 0.16, 0.17, 0.24 },   -- card highlight line (top edge)
        card_border   = { 0.18, 0.20, 0.28 },
        shadow        = { 0.00, 0.00, 0.00 },    -- shadows use alpha separately
        accent        = { 0.35, 0.65, 1.00 },
        accent_dim    = { 0.20, 0.40, 0.75 },
        accent_glow   = { 0.40, 0.70, 1.00 },
        text          = { 0.95, 0.95, 1.00 },
        text_sub      = { 0.70, 0.72, 0.82 },
        text_dim      = { 0.42, 0.44, 0.54 },
        success       = { 0.22, 0.82, 0.52 },
        success_dim   = { 0.14, 0.28, 0.22 },
        warning       = { 1.00, 0.72, 0.22 },
        warning_dim   = { 0.30, 0.22, 0.10 },
        danger        = { 0.92, 0.32, 0.32 },
        danger_dim    = { 0.30, 0.12, 0.12 },
        placeholder   = { 0.08, 0.09, 0.14 },
        divider       = { 0.15, 0.16, 0.22 },
    },
}

return config
