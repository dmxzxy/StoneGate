-- http.lua - HTTP client using LuaSocket (ships with love-android)
-- Provides: GET for JSON, binary download with progress callback

local http = {}

--------------------------------------------------------------------------------
-- Try to load LuaSocket
--------------------------------------------------------------------------------
local socket_ok, socket_http = pcall(require, "socket.http")
local ltn12_ok, ltn12 = pcall(require, "ltn12")

if not socket_ok or not ltn12_ok then
    -- LuaSocket unavailable — provide stubs that fail clearly
    function http.get(url)
        return nil, "LuaSocket not available on this device"
    end
    function http.download(url, dest, cb)
        return false, "LuaSocket not available on this device"
    end
    return http
end

--------------------------------------------------------------------------------
-- Logging helper
--------------------------------------------------------------------------------
local function log(msg)
    local f = io.open(love.filesystem.getSaveDirectory() .. "/stonegate.log", "a")
    if f then f:write("[" .. os.date("%H:%M:%S") .. "] [http] " .. msg .. "\n") f:close() end
end

--------------------------------------------------------------------------------
-- Timeout for all requests (seconds)
--------------------------------------------------------------------------------
local TIMEOUT = 10

--------------------------------------------------------------------------------
-- GET request — returns body string or nil + error
--------------------------------------------------------------------------------
function http.get(url)
    socket_http.TIMEOUT = 5

    local response = {}
    local ok, one, two, three, four = pcall(function()
        return socket_http.request({
            url     = url,
            method  = "GET",
            sink    = ltn12.sink.table(response),
            headers = { ["Accept"] = "application/json" },
        })
    end)

    if not ok then
        log("GET " .. url .. " pcall FAILED: " .. tostring(one))
        return nil, "Network error: " .. tostring(one)
    end

    log("GET " .. url .. " => type(one)=" .. type(one) .. " code=" .. tostring(two))

    -- With sink + table form: one=1, two=200, three=headers, four=statusline
    if type(one) == "number" and one == 1 then
        if tostring(two):match("^200") then
            return table.concat(response)
        else
            return nil, "HTTP " .. tostring(two)
        end
    end

    -- Simple form (shouldn't happen with sink, but just in case)
    if type(one) == "string" then
        if tostring(two):match("^200") then
            return one
        else
            return nil, "HTTP " .. tostring(two)
        end
    end

    return nil, "Unexpected response"
end

--------------------------------------------------------------------------------
-- Binary download with progress — saves to love save directory
--   url       : full URL
--   dest_path : relative path inside save directory (e.g. "games/demo.love")
--   on_progress : optional callback(downloaded_bytes, total_bytes)
-- Returns: true on success, false + error on failure
--------------------------------------------------------------------------------
function http.download(url, dest_path, on_progress)
    log("DOWNLOAD " .. url .. " => " .. dest_path)

    -- Ensure parent directories exist
    local dir = dest_path:match("^(.+)/[^/]+$")
    if dir then love.filesystem.createDirectory(dir) end

    -- Resolve absolute path for io.open (LuaSocket needs real filesystem)
    local save_dir = love.filesystem.getSaveDirectory()
    local abs_path = save_dir .. "/" .. dest_path

    -- Download with progress tracking
    local file, err = io.open(abs_path, "wb")
    if not file then
        log("DOWNLOAD cannot write: " .. tostring(err))
        return false, "Cannot write: " .. (err or abs_path)
    end

    local downloaded = 0
    local total_size = 0
    local function sink(chunk)
        if chunk then
            file:write(chunk)
            downloaded = downloaded + #chunk
            if on_progress then
                pcall(on_progress, downloaded, total_size)
            end
        end
        return true
    end

    local ok, one, two, three, four = pcall(function()
        return socket_http.request({
            url    = url,
            method = "GET",
            sink   = sink,
        })
    end)

    file:close()

    if not ok then
        log("DOWNLOAD pcall FAILED: " .. tostring(one))
        return false, "Download error: " .. tostring(one)
    end

    log("DOWNLOAD response: type(one)=" .. type(one) .. " code=" .. tostring(two) .. " bytes=" .. downloaded)

    -- Table form: one=1, two=code
    if type(one) == "number" then
        if tostring(two):match("^200") then
            log("DOWNLOAD OK (" .. downloaded .. " bytes)")
            return true
        else
            return false, "HTTP " .. tostring(two)
        end
    end

    -- Simple form
    if type(one) == "string" then
        if tostring(two):match("^200") then
            return true
        else
            return false, "HTTP " .. tostring(two)
        end
    end

    return false, "Unexpected download response: " .. tostring(one)
end

return http
