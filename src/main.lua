-- main.lua - StoneGate entry point and state machine

--------------------------------------------------------------------------------
-- Debug logging — writes to stonegate.log in save directory
--------------------------------------------------------------------------------
local function log(msg)
    local ts = os.date("%H:%M:%S")
    local line = string.format("[%s] %s\n", ts, tostring(msg))
    local save_dir = love.filesystem.getSaveDirectory()
    local f = io.open(save_dir .. "/stonegate.log", "a")
    if f then f:write(line) f:close() end
end

local config      = require("config")
local json        = require("json")
local http        = require("http")
local updater     = require("updater")
local game_loader = require("game_loader")
local ui          = require("ui")

log("=== StoneGate starting ===")

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local state    = "loading"   -- loading | menu | downloading | playing | error
local games    = {}          -- game list from server
local installed = {}         -- manifest: { [id] = {version, file} }
local err_msg  = ""
local err_detail = ""        -- detailed error for crash logs
local dl_game  = nil         -- game currently being downloaded
local dl_progress = 0

-- Thumbnail image cache: { [game_id] = Image }
local thumbnails = {}

--------------------------------------------------------------------------------
-- Download thread
--------------------------------------------------------------------------------
local download_thread = nil
local dl_cmd_channel
local dl_result_channel

local function init_download_thread()
    download_thread = love.thread.newThread("download_thread.lua")
    dl_cmd_channel    = love.thread.getChannel("sg_dl_cmd")
    dl_result_channel = love.thread.getChannel("sg_dl_result")
    download_thread:start()
    log("Download thread started")
end

local function stop_download_thread()
    if download_thread and download_thread:isRunning() then
        dl_cmd_channel:push({ action = "quit" })
        -- Give it a moment to exit
        local ok, err = pcall(function() download_thread:wait(2) end)
        if not ok then
            log("Download thread wait error: " .. tostring(err))
        end
    end
    download_thread = nil
end

--------------------------------------------------------------------------------
-- Thumbnail management
--------------------------------------------------------------------------------
local function release_thumbnails()
    for id, img in pairs(thumbnails) do
        if img then pcall(function() img:release() end) end
    end
    thumbnails = {}
end

local function load_thumbnails(game_list)
    release_thumbnails()
    love.filesystem.createDirectory(config.thumbnail_dir)

    for _, game in ipairs(game_list) do
        if game.thumbnail then
            local thumb_path = config.thumbnail_dir .. "/" .. game.id .. ".png"
            -- Download if not cached locally
            if not love.filesystem.getInfo(thumb_path) then
                updater.download_thumbnail(game.thumbnail, thumb_path)
            end
            -- Load as LÖVE image
            if love.filesystem.getInfo(thumb_path) then
                local ok, img = pcall(love.graphics.newImage, thumb_path)
                if ok and img then
                    thumbnails[game.id] = img
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Game loader callback — called when user exits a game back to the shell
--------------------------------------------------------------------------------
game_loader.set_on_exit(function()
    local crash = game_loader.get_crash_error()
    if crash then
        -- Game crashed — show error with details
        state = "error"
        err_msg = "Game crashed"
        err_detail = crash
        log("Game crashed: " .. crash)
    else
        -- Normal exit
        state = "menu"
        log("Returned to menu normally")
    end
    installed = updater.scan_installed()
    ui.reset_scroll()
end)

--------------------------------------------------------------------------------
-- Fetch game list from server
--------------------------------------------------------------------------------
local function fetch_list()
    state = "loading"
    local ok, list_or_err = pcall(updater.fetch_list)
    if ok and list_or_err then
        games = list_or_err
        installed = updater.scan_installed()
        -- Download and load thumbnails (small files, synchronous is fine on LAN)
        load_thumbnails(games)
        state = "menu"
        ui.reset_scroll()
        log("Fetched " .. #games .. " games successfully")
    else
        err_msg = (not ok and tostring(list_or_err)) or list_or_err or "Unknown error"
        err_detail = ""
        state = "error"
        log("Fetch FAILED: " .. err_msg)
    end
end

--------------------------------------------------------------------------------
-- Start downloading a game (async via background thread)
--------------------------------------------------------------------------------
local function start_download(game_id)
    -- Find the game entry
    local game = nil
    for _, g in ipairs(games) do
        if g.id == game_id then game = g; break end
    end
    if not game then return end

    dl_game = game
    dl_progress = 0
    state = "downloading"

    -- Ensure games directory exists
    love.filesystem.createDirectory(config.download_dir)

    -- Resolve absolute path for the thread (LuaSocket needs real filesystem)
    local save_dir = love.filesystem.getSaveDirectory()
    local dest = config.download_dir .. "/" .. game.id .. ".love"
    local abs_path = save_dir .. "/" .. dest

    -- Send download command to background thread
    dl_cmd_channel:push({
        action   = "download",
        url      = config.server_url .. game.file,
        abs_path = abs_path,
        rel_dir  = config.download_dir,
        game_id  = game.id,
    })

    log("Started async download: " .. game.id)
end

--------------------------------------------------------------------------------
-- Process download thread results (called from love.update)
--------------------------------------------------------------------------------
local function process_download_results()
    if not dl_result_channel then return end

    while true do
        local msg = dl_result_channel:pop()
        if not msg then break end

        if msg.action == "progress" and state == "downloading" then
            -- Update progress — we may not know total size, so show bytes
            dl_progress = msg.downloaded
        elseif msg.action == "done" then
            if msg.ok then
                -- Download succeeded — register in manifest
                local dest = config.download_dir .. "/" .. msg.game_id .. ".love"
                updater.register_download(dl_game, dest)
                installed = updater.scan_installed()
                state = "menu"
                log("Download complete: " .. msg.game_id .. " (" .. msg.size .. " bytes)")
            else
                -- Download failed
                err_msg = "Download failed: " .. (msg.err or "unknown")
                err_detail = ""
                state = "error"
                log("Download FAILED: " .. err_msg)
            end
        elseif msg.action == "fatal" then
            log("Download thread fatal: " .. tostring(msg.err))
        end
    end
end

--------------------------------------------------------------------------------
-- Handle an action returned by the UI layer
--------------------------------------------------------------------------------
local function handle_action(action, game_id)
    if not action then return end
    log("Action: " .. action .. " game: " .. tostring(game_id))

    if action == "play" then
        state = "playing"
        log("Launching game: " .. game_id)
        local ok, err = pcall(game_loader.launch, game_id)
        if not ok then
            err_msg = "Launch pcall error: " .. tostring(err)
            err_detail = ""
            state = "error"
            log("PLAY PCALL ERROR: " .. tostring(err))
        elseif not err then
            -- launch returned nil (failure)
            err_msg = "Launch failed"
            err_detail = game_loader.get_crash_error() or ""
            state = "error"
            log("PLAY RETURNED NIL")
        else
            log("Game launched OK")
        end
    elseif action == "download" or action == "update" then
        start_download(game_id)
    elseif action == "remove" then
        log("Removing game: " .. game_id)
        updater.remove_game(game_id)
        installed = updater.scan_installed()
    end
end

--------------------------------------------------------------------------------
-- love callbacks
--------------------------------------------------------------------------------

function love.load()
    log("love.load() called")

    -- Create working directories
    love.filesystem.createDirectory(config.download_dir)
    love.filesystem.createDirectory(config.thumbnail_dir)

    -- Initialize UI (loads fonts, etc.)
    ui.init()
    love.graphics.setFont(love.graphics.newFont(17))

    -- Start download thread
    init_download_thread()

    -- Initial scan + fetch
    log("Scanning installed games...")
    installed = updater.scan_installed()
    log("Fetching game list from " .. config.server_url .. config.list_endpoint)
    fetch_list()
    log("State after fetch: " .. state .. " (games: " .. #games .. ")")
end

function love.draw()
    local ok, err = pcall(function()
        if state == "loading" then
            ui.draw_loading()
        elseif state == "menu" then
            ui.draw_menu(games, installed, thumbnails)
        elseif state == "downloading" then
            ui.draw_downloading(dl_game, dl_progress)
        elseif state == "playing" then
            -- The loaded game draws itself via its own love.draw
        elseif state == "error" then
            ui.draw_error(err_msg, err_detail)
        end
    end)
    if not ok then log("DRAW ERROR: " .. tostring(err)) end
end

function love.update(dt)
    -- Process download thread results
    if state == "downloading" then
        process_download_results()
    end
end

-- Touch events (primary input on mobile & desktop)
function love.touchpressed(id, x, y)
    if state == "menu" then
        -- Check refresh button first
        if ui.hit_refresh(x, y) then
            fetch_list()
            return
        end
        ui.touch_pressed(id, x, y)
    elseif state == "error" then
        fetch_list()
    end
end

function love.touchmoved(id, x, y)
    if state == "menu" then
        ui.touch_moved(id, x, y)
    end
end

function love.touchreleased(id, x, y)
    if state == "menu" then
        local action, game_id = ui.touch_released(id, x, y, games, installed)
        handle_action(action, game_id)
    end
end

-- Mouse events (for desktop testing, passthrough to touch)
function love.mousepressed(x, y, button)
    if button == 1 then
        love.touchpressed("mouse", x, y)
    end
end

function love.mousemoved(x, y)
    if love.mouse.isDown(1) and state == "menu" then
        ui.touch_moved("mouse", x, y)
    end
end

function love.mousereleased(x, y, button)
    if button == 1 then
        love.touchreleased("mouse", x, y)
    end
end

function love.wheelmoved(dx, dy)
    if state == "menu" then
        ui.wheel_moved(dx, dy)
    end
end

--------------------------------------------------------------------------------
-- Global error handler — LÖVE calls this on unhandled errors
--------------------------------------------------------------------------------
function love.errhand(msg)
    log("!!! FATAL ERROR: " .. tostring(msg))
    -- Also write to a separate crash log that's easy to find
    local f = io.open(love.filesystem.getSaveDirectory() .. "/crash.log", "w")
    if f then
        f:write("StoneGate crashed at " .. os.date() .. "\n")
        f:write("Error: " .. tostring(msg) .. "\n")
        f:close()
    end
end
