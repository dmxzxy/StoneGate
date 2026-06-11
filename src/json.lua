-- json.lua - Minimal JSON decoder for StoneGate
-- Handles: strings, numbers, booleans, null, arrays, objects
-- No encoder needed (we only receive JSON from the server)

local json = {}

--------------------------------------------------------------------------------
-- Error helper
--------------------------------------------------------------------------------
local function decode_error(str, pos, msg)
    local line, col = 1, 1
    for i = 1, pos - 1 do
        if str:sub(i, i) == "\n" then line = line + 1; col = 1 else col = col + 1 end
    end
    error(string.format("JSON error at line %d col %d: %s", line, col, msg), 2)
end

--------------------------------------------------------------------------------
-- Whitespace
--------------------------------------------------------------------------------
local function skip_ws(str, pos)
    while pos <= #str do
        local c = str:byte(pos)
        if c == 32 or c == 9 or c == 10 or c == 13 then pos = pos + 1 else break end
    end
    return pos
end

--------------------------------------------------------------------------------
-- Forward declaration
--------------------------------------------------------------------------------
local decode_value

--------------------------------------------------------------------------------
-- String
--------------------------------------------------------------------------------
local function decode_string(str, pos)
    if str:sub(pos, pos) ~= '"' then decode_error(str, pos, "expected '\"'") end
    pos = pos + 1
    local chunks = {}
    while pos <= #str do
        local c = str:sub(pos, pos)
        if c == '"' then
            return table.concat(chunks), pos + 1
        elseif c == "\\" then
            pos = pos + 1
            if pos > #str then decode_error(str, pos, "unterminated escape") end
            local esc = str:sub(pos, pos)
            if    esc == '"'  then chunks[#chunks + 1] = '"'
            elseif esc == "\\" then chunks[#chunks + 1] = "\\"
            elseif esc == "/"  then chunks[#chunks + 1] = "/"
            elseif esc == "b"  then chunks[#chunks + 1] = "\b"
            elseif esc == "f"  then chunks[#chunks + 1] = "\f"
            elseif esc == "n"  then chunks[#chunks + 1] = "\n"
            elseif esc == "r"  then chunks[#chunks + 1] = "\r"
            elseif esc == "t"  then chunks[#chunks + 1] = "\t"
            elseif esc == "u" then
                if pos + 4 > #str then decode_error(str, pos, "invalid \\u escape") end
                local hex = str:sub(pos + 1, pos + 4)
                local code = tonumber(hex, 16)
                if not code then decode_error(str, pos, "bad hex: " .. hex) end
                -- UTF-8 encoding
                if code < 0x80 then
                    chunks[#chunks + 1] = string.char(code)
                elseif code < 0x800 then
                    chunks[#chunks + 1] = string.char(0xC0 + math.floor(code / 0x40))
                    chunks[#chunks + 1] = string.char(0x80 + code % 0x40)
                else
                    chunks[#chunks + 1] = string.char(0xE0 + math.floor(code / 0x1000))
                    chunks[#chunks + 1] = string.char(0x80 + math.floor(code / 0x40) % 0x40)
                    chunks[#chunks + 1] = string.char(0x80 + code % 0x40)
                end
                pos = pos + 4
            else
                decode_error(str, pos, "bad escape: \\" .. esc)
            end
        else
            chunks[#chunks + 1] = c
        end
        pos = pos + 1
    end
    decode_error(str, pos, "unterminated string")
end

--------------------------------------------------------------------------------
-- Number
--------------------------------------------------------------------------------
local function decode_number(str, pos)
    local start = pos
    if str:sub(pos, pos) == "-" then pos = pos + 1 end
    if str:sub(pos, pos) == "0" then
        pos = pos + 1
    else
        while pos <= #str and str:sub(pos, pos):match("%d") do pos = pos + 1 end
    end
    if str:sub(pos, pos) == "." then
        pos = pos + 1
        while pos <= #str and str:sub(pos, pos):match("%d") do pos = pos + 1 end
    end
    if str:sub(pos, pos):lower() == "e" then
        pos = pos + 1
        if str:sub(pos, pos) == "+" or str:sub(pos, pos) == "-" then pos = pos + 1 end
        while pos <= #str and str:sub(pos, pos):match("%d") do pos = pos + 1 end
    end
    local n = tonumber(str:sub(start, pos - 1))
    if not n then decode_error(str, start, "bad number") end
    return n, pos
end

--------------------------------------------------------------------------------
-- Literal (true / false / null)
--------------------------------------------------------------------------------
local function decode_literal(str, pos, word, value)
    if str:sub(pos, pos + #word - 1) == word then return value, pos + #word end
    decode_error(str, pos, "expected '" .. word .. "'")
end

--------------------------------------------------------------------------------
-- Array
--------------------------------------------------------------------------------
local function decode_array(str, pos)
    pos = pos + 1 -- skip '['
    local arr = {}
    pos = skip_ws(str, pos)
    if str:sub(pos, pos) == "]" then return arr, pos + 1 end
    while true do
        local v
        v, pos = decode_value(str, pos)
        arr[#arr + 1] = v
        pos = skip_ws(str, pos)
        local c = str:sub(pos, pos)
        if c == "]" then return arr, pos + 1 end
        if c ~= "," then decode_error(str, pos, "expected ',' or ']'") end
        pos = pos + 1
        pos = skip_ws(str, pos)
    end
end

--------------------------------------------------------------------------------
-- Object
--------------------------------------------------------------------------------
local function decode_object(str, pos)
    pos = pos + 1 -- skip '{'
    local obj = {}
    pos = skip_ws(str, pos)
    if str:sub(pos, pos) == "}" then return obj, pos + 1 end
    while true do
        pos = skip_ws(str, pos)
        local key
        key, pos = decode_string(str, pos)
        pos = skip_ws(str, pos)
        if str:sub(pos, pos) ~= ":" then decode_error(str, pos, "expected ':'") end
        pos = pos + 1
        local v
        v, pos = decode_value(str, pos)
        obj[key] = v
        pos = skip_ws(str, pos)
        local c = str:sub(pos, pos)
        if c == "}" then return obj, pos + 1 end
        if c ~= "," then decode_error(str, pos, "expected ',' or '}'") end
        pos = pos + 1
    end
end

--------------------------------------------------------------------------------
-- Value dispatcher
--------------------------------------------------------------------------------
decode_value = function(str, pos)
    pos = skip_ws(str, pos)
    if pos > #str then decode_error(str, pos, "unexpected end") end
    local c = str:sub(pos, pos)
    if    c == '"' then return decode_string(str, pos)
    elseif c == "{" then return decode_object(str, pos)
    elseif c == "[" then return decode_array(str, pos)
    elseif c == "t" then return decode_literal(str, pos, "true", true)
    elseif c == "f" then return decode_literal(str, pos, "false", false)
    elseif c == "n" then return decode_literal(str, pos, "null", nil)
    elseif c == "-" or (c >= "0" and c <= "9") then return decode_number(str, pos)
    else decode_error(str, pos, "unexpected '" .. c .. "'") end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
function json.decode(str)
    if type(str) ~= "string" then
        error("json.decode: expected string, got " .. type(str), 2)
    end
    local value = decode_value(str, 1)
    return value
end

return json
