-- game_loader.lua - Dynamically mount, run, and unload .love games
--
-- Strategy:
--   1. Downloaded .love files live in the save directory (games/<id>.love)
--   2. love.filesystem.mount mounts to a unique mount point like "__game__<id>"
--      to avoid shadowing the shell's own files.
--   3. We set love.filesystem.setRequirePath so the game's require() works.
--   4. The game's main.lua sets global love callbacks — we capture those and
--      wrap them in pcall for crash recovery.
--   5. On crash, we capture the error, unmount, and return to shell.
--   6. On normal exit (back key), we unmount and restore the shell's callbacks.

local game_loader = {}

local config = require("config")

-- Saved shell callbacks (restored when game exits)
local shell = {}
-- Saved require path (restored when game exits)
local saved_require_path = nil
-- Snapshot of package.loaded keys taken at launch, so we can unload the game's
-- own required modules on exit. Lua caches loaded modules in package.loaded; if
-- we don't clear them, an UPDATED game's modules go stale across launches in the
-- same process (the new main.lua then reads the old module → nil-field crashes).
local saved_package_loaded = nil
-- Currently mounted game info
local mounted = nil
-- Callback invoked after exiting a game
local on_exit_fn = nil
-- Crash error message (set when a game callback throws)
local crash_err = nil

--------------------------------------------------------------------------------
-- Save / restore helpers
--------------------------------------------------------------------------------
local CALLBACK_NAMES = {
    "load", "update", "draw",
    "keypressed", "keyreleased",
    "touchpressed", "touchmoved", "touchreleased",
    "mousepressed", "mousereleased", "mousemoved",
    "gamepadpressed", "gamepadreleased",
    "textinput", "wheelmoved",
    "focus", "visible", "resize",
    "filedropped", "directorydropped",
    "lowmemory", "quit",
}

local function save_shell_callbacks()
    for _, name in ipairs(CALLBACK_NAMES) do
        shell[name] = love[name]
    end
end

local function restore_shell_callbacks()
    for _, name in ipairs(CALLBACK_NAMES) do
        love[name] = shell[name] or function() end
    end
end

local function clear_callbacks()
    for _, name in ipairs(CALLBACK_NAMES) do
        love[name] = function() end
    end
end

--------------------------------------------------------------------------------
-- Logging helper — writes to stonegate.log in save directory
--------------------------------------------------------------------------------
local function log(msg)
    local f = io.open(love.filesystem.getSaveDirectory() .. "/stonegate.log", "a")
    if f then f:write("[" .. os.date("%H:%M:%S") .. "] [loader] " .. msg .. "\n") f:close() end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Register a function to be called when a game exits (returns to shell).
function game_loader.set_on_exit(fn)
    on_exit_fn = fn
end

--- Get and clear the last crash error (nil if game exited normally).
function game_loader.get_crash_error()
    local err = crash_err
    crash_err = nil
    return err
end

--- Launch a game by its id (corresponds to games/<id>.love in save dir).
--- Returns true on success, nil + error message on failure.
function game_loader.launch(game_id)
    -- Safety: unmount any previous game first
    if mounted then game_loader.exit() end

    log("Launching: " .. game_id)

    local love_path = config.download_dir .. "/" .. game_id .. ".love"

    -- Verify the file exists
    local info = love.filesystem.getInfo(love_path)
    if not info then
        log("File not found: " .. love_path)
        return nil, "Game file not found: " .. love_path
    end
    log("File found: " .. love_path .. " (" .. info.size .. " bytes)")

    -- Save the shell's callbacks so we can restore them later
    save_shell_callbacks()
    log("Shell callbacks saved")

    -- Mount to root (empty mount_point) so the game's bare paths like
    -- 'assets/font.ttf' resolve against the mounted .love contents.
    -- Previous '__game_<id>__' mount point broke games that use bare asset paths
    -- (they only work for require() because we also patch setRequirePath).
    local mount_point = ""

    local ok, mount_err = love.filesystem.mount(love_path, mount_point, false)
    if not ok then
        log("Mount FAILED: " .. tostring(mount_err))
        restore_shell_callbacks()
        return nil, "Mount failed: " .. tostring(mount_err)
    end
    log("Mounted OK at root (mount_point='')")

    -- Save and modify require path so the game's require() finds its modules
    saved_require_path = love.filesystem.getRequirePath()
    -- mount_point is now "" so the require path entries become bare '/?.lua'
    -- which resolves against the mounted .love root.
    love.filesystem.setRequirePath(
        "?.lua;"
        .. "?/init.lua;"
        .. saved_require_path
    )
    log("Require path set to bare (mounted at root)")

    mounted = {
        id          = game_id,
        path        = love_path,
        mount_point = mount_point,
    }

    -- Snapshot which modules are already loaded so we can drop the game's own
    -- modules on exit (prevents stale-module crashes after a game update).
    saved_package_loaded = {}
    for k in pairs(package.loaded) do saved_package_loaded[k] = true end

    -- Clear all callbacks so the game starts from a clean slate
    clear_callbacks()

    -- Locate the game's main.lua inside the mount point
    local main_path = "main.lua"
    if not love.filesystem.getInfo(main_path) then
        main_path = "src/main.lua"
    end

    log("Loading: " .. main_path)

    local chunk, load_err = love.filesystem.load(main_path)
    if not chunk then
        log("Load FAILED: " .. tostring(load_err))
        game_loader.exit()
        return nil, "Load main.lua failed: " .. tostring(load_err)
    end
    log("Chunk loaded OK")

    -- Expose a global exit hook so games can return to the shell via an
    -- on-screen button (useful on devices with no physical back key).
    -- Games call:  stonegate_exit()  or  love.exit_to_shell()
    _G.stonegate_exit = function() game_loader.exit() end
    love.exit_to_shell = _G.stonegate_exit

    local ok2, run_err = pcall(chunk)
    if not ok2 then
        log("Run FAILED: " .. tostring(run_err))
        crash_err = "Game initialization error: " .. tostring(run_err)
        game_loader.exit()
        return nil, crash_err
    end
    log("Game code executed OK")

    -- Capture the game's callbacks
    local game = {}
    for _, name in ipairs(CALLBACK_NAMES) do
        game[name] = love[name]
    end

    -- Wrap ALL game callbacks in pcall for crash recovery
    -- If any callback throws, we capture the error and return to shell
    local function safe_callback(name, original_fn)
        if not original_fn then return function() end end
        return function(...)
            local ok, err = pcall(original_fn, ...)
            if not ok then
                log("CRASH in " .. name .. ": " .. tostring(err))
                crash_err = name .. ": " .. tostring(err)
                -- Use pcall for exit itself in case unmount fails
                pcall(game_loader.exit)
            end
        end
    end

    -- Special wrapper for keypressed — intercept back/escape key
    local original_keypressed = game.keypressed
    love.keypressed = function(key, scancode, isrepeat)
        if config.back_keys[key] then
            game_loader.exit()
            return
        end
        if original_keypressed then
            local ok, err = pcall(original_keypressed, key, scancode, isrepeat)
            if not ok then
                log("CRASH in keypressed: " .. tostring(err))
                crash_err = "keypressed: " .. tostring(err)
                pcall(game_loader.exit)
            end
        end
    end

    -- Wrap all other callbacks with crash recovery
    for _, name in ipairs(CALLBACK_NAMES) do
        if name ~= "keypressed" then
            love[name] = safe_callback(name, game[name])
        end
    end

    -- Fire the game's love.load
    if love.load then
        local ok, err = pcall(love.load, love.arg.parseGameArguments(arg), arg)
        if not ok then
            log("CRASH in love.load: " .. tostring(err))
            crash_err = "love.load: " .. tostring(err)
            pcall(game_loader.exit)
            return nil, crash_err
        end
    end

    log("Game launched successfully!")
    return true
end

--- Exit the current game and return to the shell.
function game_loader.exit()
    if not mounted then return end

    log("Exiting game: " .. mounted.id)

    -- Remove the exit hook we exposed to the game
    _G.stonegate_exit = nil
    love.exit_to_shell = nil

    -- Try to fire the game's quit handler
    if love.quit then pcall(love.quit) end

    -- Restore require path
    if saved_require_path then
        love.filesystem.setRequirePath(saved_require_path)
        saved_require_path = nil
    end

    -- Unload the game's required modules so an updated game gets fresh code on
    -- its next launch (Lua otherwise caches them in package.loaded).
    if saved_package_loaded then
        for k in pairs(package.loaded) do
            if not saved_package_loaded[k] then package.loaded[k] = nil end
        end
        saved_package_loaded = nil
    end

    -- Unmount the .love file
    love.filesystem.unmount(mounted.path)
    mounted = nil

    -- Restore shell callbacks
    restore_shell_callbacks()

    -- Notify the shell
    if on_exit_fn then on_exit_fn() end
end

--- Is a game currently running?
function game_loader.is_playing()
    return mounted ~= nil
end

--- Get info about the currently running game (or nil).
function game_loader.current()
    return mounted
end

return game_loader
