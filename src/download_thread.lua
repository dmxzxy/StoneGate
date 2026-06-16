-- download_thread.lua - Background download thread for StoneGate
-- Runs in a separate LÖVE thread to avoid blocking the UI.
-- Communicates via named channels:
--   sg_dl_cmd    : main → thread (commands)
--   sg_dl_result : thread → main (progress + completion)

local cmd_channel    = love.thread.getChannel("sg_dl_cmd")
local result_channel = love.thread.getChannel("sg_dl_result")

--------------------------------------------------------------------------------
-- Load LuaSocket inside the thread
--------------------------------------------------------------------------------
local socket_ok, socket_http = pcall(require, "socket.http")
local ltn12_ok, ltn12 = pcall(require, "ltn12")

if not socket_ok or not ltn12_ok then
    result_channel:push({
        action = "fatal",
        err    = "LuaSocket not available in thread",
    })
    -- Thread stays alive but won't process downloads
end

--------------------------------------------------------------------------------
-- Main loop — wait for commands from the main thread
--------------------------------------------------------------------------------
while true do
    local cmd = cmd_channel:demand()  -- blocks until a command arrives

    if not cmd then break end
    if cmd.action == "quit" then break end

    if cmd.action == "download" and socket_ok then
        local url      = cmd.url
        local abs_path = cmd.abs_path
        local game_id  = cmd.game_id

        -- Ensure parent directory exists (io-based, works in thread)
        local dir = abs_path:match("^(.+)/[^/]+$")
        if dir then
            -- Use os.execute for mkdir (cross-platform enough for our use case)
            love.filesystem.createDirectory(cmd.rel_dir or "games")
        end

        local file, err = io.open(abs_path, "wb")
        if not file then
            result_channel:push({
                action  = "done",
                ok      = false,
                err     = "Cannot write: " .. (err or abs_path),
                game_id = game_id,
            })
        else
            local downloaded = 0
            local last_report = 0
            local total = 0   -- learned from Content-Length once headers arrive

            local function sink(chunk)
                if chunk then
                    file:write(chunk)
                    downloaded = downloaded + #chunk
                    -- Throttle progress reports to avoid flooding the channel
                    if downloaded - last_report > 32768 then
                        result_channel:push({
                            action     = "progress",
                            downloaded = downloaded,
                            total      = total,
                            game_id    = game_id,
                        })
                        last_report = downloaded
                    end
                end
                return true
            end

            local ok, one, two, headers = pcall(function()
                return socket_http.request({
                    url    = url,
                    method = "GET",
                    sink   = sink,
                })
            end)

            file:close()

            -- LuaSocket lowercases header keys; Content-Length lets the UI show
            -- a real percentage instead of an indeterminate spinner.
            if type(headers) == "table" and headers["content-length"] then
                total = tonumber(headers["content-length"]) or 0
            end

            if not ok then
                result_channel:push({
                    action  = "done",
                    ok      = false,
                    err     = "Download error: " .. tostring(one),
                    game_id = game_id,
                })
            elseif type(one) == "number" then
                if tostring(two):match("^200") then
                    result_channel:push({
                        action  = "done",
                        ok      = true,
                        size    = downloaded,
                        total   = total,
                        game_id = game_id,
                    })
                else
                    result_channel:push({
                        action  = "done",
                        ok      = false,
                        err     = "HTTP " .. tostring(two),
                        game_id = game_id,
                    })
                end
            else
                result_channel:push({
                    action  = "done",
                    ok      = false,
                    err     = "Unexpected response",
                    game_id = game_id,
                })
            end
        end
    end
end
