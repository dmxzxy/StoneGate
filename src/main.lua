-- main.lua - StoneGate entry point and state machine (FlexLove edition)

--------------------------------------------------------------------------------
-- Debug logging 闂?writes to stonegate.log in save directory
--------------------------------------------------------------------------------
local function log(msg)
    local ts = os.date("%H:%M:%S")
    local line = string.format("[%s] %s\n", ts, tostring(msg))
    local save_dir = love.filesystem.getSaveDirectory()
    local f = io.open(save_dir .. "/stonegate.log", "a")
    if f then f:write(line) f:close() end
end

--------------------------------------------------------------------------------
-- Global error handler — defined EARLY (before any require) so that a crash
-- during module loading (e.g. a syntax error in a required file) is also
-- captured with a full traceback in crash.log. Without this, a startup-time
-- crash falls back to LÖVE's default handler and stonegate.log is never
-- written, making diagnosis very hard.
--------------------------------------------------------------------------------
function love.errhand(msg)
    local tb = debug.traceback(tostring(msg), 2)
    pcall(log, "!!! FATAL ERROR: " .. tb)
    local ok, f = pcall(io.open, love.filesystem.getSaveDirectory() .. "/crash.log", "w")
    if ok and f then
        f:write("StoneGate crashed at " .. os.date() .. "\n")
        f:write(tb .. "\n")
        f:close()
    end
end

local config      = require("config")
local json        = require("json")
local http        = require("http")
local updater     = require("updater")
local game_loader = require("game_loader")
local ui          = require("ui")
local FlexLove    = require("FlexLove")

log("=== StoneGate starting ===")

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local state    = "loading"   -- loading | menu | downloading | playing | error
local last_dim_w, last_dim_h = 0, 0  -- track screen size changes
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
            -- Load as L闂備胶鍘ч顓炩枍婵?image
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
-- State transition helper
--------------------------------------------------------------------------------
local function set_state(new_state)
    state = new_state
    ui.set_state(new_state)
end

--------------------------------------------------------------------------------
-- Game loader callback 闂?called when user exits a game back to the shell
--------------------------------------------------------------------------------
game_loader.set_on_exit(function()
    local crash = game_loader.get_crash_error()
    if crash then
        -- Game crashed 闂?show error with details
        err_msg = "Game crashed"
        err_detail = crash
        ui.update_error(err_msg, err_detail)
        set_state("error")
        log("Game crashed: " .. crash)
    else
        -- Normal exit
        set_state("menu")
        log("Returned to menu normally")
    end
    installed = updater.scan_installed()
    -- Rebuild UI with current dimensions after game exit
    local w, h = love.graphics.getDimensions()
    ui.resize(w, h)
    FlexLove.resize()
    if not crash then
        ui.rebuild_cards(games, installed, thumbnails)
    end
end)

--------------------------------------------------------------------------------
-- Fetch game list from server
--------------------------------------------------------------------------------
local function fetch_list()
    set_state("loading")
    local ok, list_or_err = pcall(updater.fetch_list)
    if ok and list_or_err then
        games = list_or_err
        installed = updater.scan_installed()
        -- Download and load thumbnails (small files, synchronous is fine on LAN)
        load_thumbnails(games)
        set_state("menu")
        ui.rebuild_cards(games, installed, thumbnails)
        log("Fetched " .. #games .. " games successfully")
    else
        err_msg = (not ok and tostring(list_or_err)) or list_or_err or "Unknown error"
        err_detail = ""
        ui.update_error(err_msg, err_detail)
        set_state("error")
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
    ui.update_download(dl_game, dl_progress)
    set_state("downloading")

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
            -- Update progress 闂?we may not know total size, so show bytes
            dl_progress = msg.downloaded
            ui.update_download(dl_game, dl_progress)
        elseif msg.action == "done" then
            if msg.ok then
                -- Download succeeded 闂?register in manifest
                local dest = config.download_dir .. "/" .. msg.game_id .. ".love"
                updater.register_download(dl_game, dest)
                installed = updater.scan_installed()
                set_state("menu")
                ui.rebuild_cards(games, installed, thumbnails)
                log("Download complete: " .. msg.game_id .. " (" .. msg.size .. " bytes)")
            else
                -- Download failed
                err_msg = "Download failed: " .. (msg.err or "unknown")
                err_detail = ""
                ui.update_error(err_msg, err_detail)
                set_state("error")
                log("Download FAILED: " .. err_msg)
            end
        elseif msg.action == "fatal" then
            log("Download thread fatal: " .. tostring(msg.err))
        end
    end
end

--------------------------------------------------------------------------------
-- Handle an action from the UI layer
--------------------------------------------------------------------------------
local function handle_action(action, game_id)
    if not action then return end
    log("Action: " .. action .. " game: " .. tostring(game_id))

    if action == "refresh" or action == "retry" then
        fetch_list()
    elseif action == "play" then
        set_state("playing")
        log("Launching game: " .. game_id)
        local ok, err = pcall(game_loader.launch, game_id)
        if not ok then
            err_msg = "Launch pcall error: " .. tostring(err)
            err_detail = ""
            ui.update_error(err_msg, err_detail)
            set_state("error")
            log("PLAY PCALL ERROR: " .. tostring(err))
        elseif not err then
            -- launch returned nil (failure)
            err_msg = "Launch failed"
            err_detail = game_loader.get_crash_error() or ""
            ui.update_error(err_msg, err_detail)
            set_state("error")
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
        ui.rebuild_cards(games, installed, thumbnails)
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

    -- Initialize FlexLove
    FlexLove.init()

    -- Initialize UI
    log("FlexLove.initialized = " .. tostring(FlexLove.initialized) .. " initState=" .. tostring(FlexLove._initState))
    ui.init(function(action, game_id)
        handle_action(action, game_id)
    end)

    -- Set default font
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

function love.update(dt)
    -- Drive FlexLove so mouse/touch polling, hover, and click synthesis run each frame.
    -- Without this, processMouseEvents is never called and no button responds.
    local ok, err = pcall(FlexLove.update, dt)
    if not ok then log("UPDATE ERROR: " .. tostring(err)) end

    -- Pump download thread results (progress / completion / failure).
    if state ~= "playing" then
        process_download_results()
    end
end

function love.draw()
    if state ~= "playing" then
        local ok, err = pcall(function()
            FlexLove.draw()
            FlexLove.executeDeferredCallbacks()
        end)
        if not ok then log("DRAW ERROR: " .. tostring(err)) end
    end
end

function love.resize(w, h)
    ui.resize(w, h)
    FlexLove.resize()
end

-- Touch events (primary input on mobile)
function love.touchpressed(id, x, y)
    FlexLove.touchpressed(id, x, y)
end

function love.touchmoved(id, x, y)
    FlexLove.touchmoved(id, x, y)
end

function love.touchreleased(id, x, y)
    FlexLove.touchreleased(id, x, y)
end


function love.wheelmoved(dx, dy)
    FlexLove.wheelmoved(dx, dy)
end

function love.keypressed(key, scancode, isrepeat)
    FlexLove.keypressed(key, scancode, isrepeat)
end
