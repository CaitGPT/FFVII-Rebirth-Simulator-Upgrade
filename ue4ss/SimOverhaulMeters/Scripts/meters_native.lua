-- The game's hit events, from the meters' native helper (native/meters, a copy of Battle Meters Native that registers
-- SimOverhaulMetersHit and SimOverhaulMetersStatus into this mod). Battle Meters' native_hits.lua with those names.
-- Called on the game thread.
local M = {}

local MAX_PER_TICK = 512   -- the queue holds 2048; a tick sees a few dozen at most

local function present()
    return type(SimOverhaulMetersHit) == "function" and type(SimOverhaulMetersStatus) == "function"
end

-- "ok" once the helper is hooked, otherwise why not; plus hits it dropped since the last call and hits since load.
function M.status()
    if not present() then return "not installed", 0, 0 end
    local ok, text, dropped, total = pcall(SimOverhaulMetersStatus)
    if not ok then return "status failed: " .. tostring(text), 0, 0 end
    return tostring(text), tonumber(dropped) or 0, tonumber(total) or 0
end

function M.available()
    return present() and M.status() == "ok"
end

-- Hits since the last call, oldest first: {damage, causer, target, heal}.
function M.drain()
    local out = {}
    if not present() then return out end
    for _ = 1, MAX_PER_TICK do
        local ok, damage, causer, target, heal = pcall(SimOverhaulMetersHit)
        if not ok or damage == nil then break end
        out[#out + 1] = { damage = damage, causer = causer, target = target, heal = heal == true }
    end
    return out
end

-- Hits from before this course (the field, the last fight's tail) are thrown away.
function M.discard()
    for _ = 1, 8 do
        if #M.drain() < MAX_PER_TICK then break end
    end
    M.status()
end

return M
