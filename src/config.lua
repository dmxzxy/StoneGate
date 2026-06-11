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

    -- Theme colors (RGB, 0-1)
    colors = {
        bg          = { 0.08, 0.08, 0.12 },
        card        = { 0.15, 0.16, 0.22 },
        card_border = { 0.25, 0.27, 0.35 },
        accent      = { 0.25, 0.55, 1.00 },
        text        = { 0.92, 0.92, 0.96 },
        text_dim    = { 0.50, 0.52, 0.60 },
        success     = { 0.25, 0.75, 0.40 },
        warning     = { 0.95, 0.65, 0.15 },
        danger      = { 0.85, 0.25, 0.25 },
        placeholder = { 0.12, 0.13, 0.18 },
    },
}

return config
