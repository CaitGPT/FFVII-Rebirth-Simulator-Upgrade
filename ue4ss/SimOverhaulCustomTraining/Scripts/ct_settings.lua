-- Custom Training's settings: the last choices, kept in settings.txt beside the scripts (keys prefixed ct_, as
-- docs/COORDINATION.md asks), so the next visit starts where the last one ended. Game-free; tested offline.
local M = {}

M.DEFAULTS = {
    opponent = "", -- a template id; empty: the catalogue's default
    count = 1,
    group = "", -- 1 to 3 template ids, one per enemy ("a,b,b"); empty: the opponent, count times
    mode = "opponents", -- or "round": a pre-built round of a simulator course
    round = "", -- the round (territory id) for Round mode
    behaviour = "passive",
    difficulty = "normal",
    menu_key = "F7",
    respawn_key = "F4", -- brings back the last chosen set, in a running course (F3 equipment, F5/F6/F8/F9 meters, F7 menu)
    auto_respawn = "off", -- on: a cleared wave comes back by itself (endless dummies); off: it waits for Respawn
    unlimited_mp = "on", -- MP refilled as it is spent (Training Dummy's unlimited MP)
    auto = "on", -- off: testing only; the course holds and refills its enemies and never spawns or removes any
    panel = "on", -- off: the settings panel never opens (the ui part's menu takes F7 and LB+RB)
}

local VALID = {
    behaviour = { passive = true, aggressive = true, healing = true },
    unlimited_mp = { on = true, off = true },
    difficulty = { easy = true, normal = true, dynamic = true, hard = true },
    auto = { on = true, off = true },
    panel = { on = true, off = true },
    mode = { opponents = true, round = true },
    auto_respawn = { on = true, off = true },
}

local function clean(key, value)
    if key == "count" then
        local n = tonumber(value)
        if n and n >= 1 and n <= 3 and n == math.floor(n) then return n end
        return nil
    end
    if VALID[key] then return VALID[key][value] and value or nil end
    if key == "group" then
        return (type(value) == "string" and value:match("^[%w_,]*$")) and value or nil
    end
    if key == "opponent" or key == "menu_key" or key == "round" or key == "respawn_key" then
        return (type(value) == "string" and value:match("^[%w_]*$")) and value or nil
    end
    return nil
end

-- Text of settings.txt -> settings table (defaults for anything missing or wrong).
function M.parse(text)
    local s = {}
    for k, v in pairs(M.DEFAULTS) do s[k] = v end
    for line in (text or ""):gmatch("[^\r\n]+") do
        local key, value = line:match("^%s*ct_([%w_]+)%s*=%s*(.-)%s*$")
        if key and M.DEFAULTS[key] ~= nil then
            local v = clean(key, value)
            if v ~= nil then s[key] = v end
        end
    end
    return s
end

-- Development-only keys: read when present, never written into a player's file (ct_auto off: enemies held, nothing
-- spawned; ct_panel off: the built-in panel never opens, as when ui's menu is there).
M.DEVELOPMENT = { auto = true, panel = true }

-- Settings -> the text to write, keeping lines that are not ours (other workstreams' keys, comments).
function M.render(s, previous)
    local lines, seen = {}, {}
    for line in (previous or ""):gmatch("[^\r\n]+") do
        local key = line:match("^%s*ct_([%w_]+)%s*=")
        if key and M.DEFAULTS[key] ~= nil then
            if not seen[key] then lines[#lines + 1] = "ct_" .. key .. " = " .. tostring(s[key]); seen[key] = true end
        else
            lines[#lines + 1] = line
        end
    end
    local keys = {}
    for k in pairs(M.DEFAULTS) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        if not seen[k] and not M.DEVELOPMENT[k] then lines[#lines + 1] = "ct_" .. k .. " = " .. tostring(s[k]) end
    end
    return table.concat(lines, "\n") .. "\n"
end

return M
