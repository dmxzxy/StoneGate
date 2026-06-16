-- updater.lua - Game list fetching, version tracking, download management

local updater = {}

local config  = require("config")
local json    = require("json")
local http    = require("http")

--------------------------------------------------------------------------------
-- Installed-games metadata (persisted to installed.json in save dir)
--------------------------------------------------------------------------------

--- Load the installed-games manifest from disk.
--- Returns a table: { [game_id] = { version = "1.0", file = "games/id.love" } }
local function load_manifest()
    local raw = love.filesystem.read(config.meta_file)
    if not raw then return {} end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == "table" then return data end
    return {}
end

--- Save the manifest to disk.
local function save_manifest(manifest)
    -- Minimal JSON encoder (just for our simple manifest format)
    local parts = { "{" }
    local first = true
    for id, info in pairs(manifest) do
        if not first then parts[#parts + 1] = "," end
        parts[#parts + 1] = string.format(
            '"%s":{"version":"%s","file":"%s"}',
            id, info.version, info.file
        )
        first = false
    end
    parts[#parts + 1] = "}"
    love.filesystem.write(config.meta_file, table.concat(parts))
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Fetch the game list from the server.
--- Returns: list of game entries, or nil + error
function updater.fetch_list()
    local url = config.server_url .. config.list_endpoint
    local body, err = http.get(url)
    if not body then
        -- Fallback: return demo games when server unreachable (for offline UI testing)
        return {
            { id = "plinko",       name = "Plinko",           version = "1.0", file = "/games/plinko.love",       size = 24942, thumbnail = nil },
            { id = "marble-duel", name = "Marble Duel",       version = "1.0", file = "/games/marble-duel.love",  size = 17564, thumbnail = nil },
            { id = "survival-archer", name = "Survival Archer", version = "1.0", file = "/games/survival-archer.love", size = 14102, thumbnail = nil },
            { id = "sample",      name = "Sample",            version = "1.0", file = "/games/sample.love",       size = 631,  thumbnail = nil },
            { id = "plinko2",     name = "Plinko 2",         version = "2.0", file = "/games/plinko2.love",     size = 30000, thumbnail = nil },
            { id = "marble3",     name = "Marble 3D",        version = "1.5", file = "/games/marble3.love",    size = 22000, thumbnail = nil },
            { id = "archer2",     name = "Archer Quest",      version = "1.2", file = "/games/archer2.love",    size = 18000, thumbnail = nil },
            { id = "breakout",    name = "Breakout",          version = "1.0", file = "/games/breakout.love",   size = 15000, thumbnail = nil },
            { id = "snake",       name = "Snake Classic",     version = "1.0", file = "/games/snake.love",      size = 8000,  thumbnail = nil },
            { id = "tetris",      name = "Tetris",            version = "1.1", file = "/games/tetris.love",     size = 12000, thumbnail = nil },
            { id = "pacman",      name = "Pac-Man",           version = "1.0", file = "/games/pacman.love",     size = 20000, thumbnail = nil },
            { id = "spaceinv",    name = "Space Invaders",    version = "1.0", file = "/games/spaceinv.love",   size = 16000, thumbnail = nil },
        }
    end

    local ok, data = pcall(json.decode, body)
    if not ok or type(data) ~= "table" or not data.games then
        return nil, "Invalid game list format"
    end

    return data.games
end

--- Scan the local save directory for already-downloaded .love files
--- and reconcile with the manifest. Returns the manifest table.
function updater.scan_installed()
    local manifest = load_manifest()

    -- Ensure the games directory exists
    love.filesystem.createDirectory(config.download_dir)

    -- List .love files
    local files = love.filesystem.getDirectoryItems(config.download_dir)
    for _, fname in ipairs(files) do
        if fname:match("%.love$") then
            local id = fname:match("(.+)%.love$")
            if id and not manifest[id] then
                -- Found a file but no manifest entry — record it with unknown version
                manifest[id] = {
                    version = "0.0",
                    file    = config.download_dir .. "/" .. fname,
                }
            end
        end
    end

    -- Remove manifest entries whose files no longer exist
    for id, info in pairs(manifest) do
        if not love.filesystem.getInfo(info.file) then
            manifest[id] = nil
        end
    end

    save_manifest(manifest)
    return manifest
end

--- Check if a specific game is installed with the given (or any) version.
--- If version is nil, just checks presence.
function updater.is_installed(manifest, game_id, version)
    local entry = manifest[game_id]
    if not entry then return false end
    if version and entry.version ~= version then return false end
    return true
end

--- Register a completed download in the manifest.
function updater.register_download(game, file_path)
    local manifest = load_manifest()
    local info = love.filesystem.getInfo(file_path)
    manifest[game.id] = {
        version = game.version,
        file    = file_path,
        size    = info and info.size or game.size,
    }
    save_manifest(manifest)
end

--- Download a game. Calls on_progress(downloaded, total) periodically.
--- Returns: true on success, false + error on failure.
--- On success, updates the manifest automatically.
--- NOTE: This is the synchronous version, kept as fallback.
function updater.download_game(game, on_progress)
    local url  = config.server_url .. game.file
    local dest = config.download_dir .. "/" .. game.id .. ".love"

    local ok, err = http.download(url, dest, on_progress)
    if not ok then return false, err end

    updater.register_download(game, dest)
    return true
end

--- Download a single thumbnail. Small file, synchronous is fine.
--- Returns true on success.
function updater.download_thumbnail(thumbnail_url, dest_path)
    local url = config.server_url .. thumbnail_url
    local ok, err = http.download(url, dest_path)
    return ok
end

--- Verify a downloaded file against the server-provided SHA256.
--- A corrupt or truncated .love (e.g. a download cut short) would otherwise be
--- registered as "installed" and crash on launch — this catches it first.
--- Returns true if it matches, OR if expected_sha is nil/empty (nothing to
--- check against, e.g. the offline fallback list carries no hashes).
function updater.verify_file(rel_path, expected_sha)
    if not expected_sha or expected_sha == "" then return true end
    local data = love.filesystem.read(rel_path)
    if not data then return false end
    local digest = love.data.encode("string", "hex", love.data.hash("sha256", data))
    return digest:lower() == expected_sha:lower()
end

--- Remove a downloaded game.
function updater.remove_game(game_id)
    local manifest = load_manifest()
    local entry = manifest[game_id]
    if entry then
        love.filesystem.remove(entry.file)
        manifest[game_id] = nil
        save_manifest(manifest)
    end
end

return updater
