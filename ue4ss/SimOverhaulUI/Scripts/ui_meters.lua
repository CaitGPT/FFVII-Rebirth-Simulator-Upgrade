-- The meters part (ws/meters), for the menu's Meter, Clear meter and Reset stagger rows. Its interface, from the
-- header of meters_api.lua: state() -> { meter = "damage" | "taken" | "heal", label, visible }; act(action) with
-- "meter=damage|taken|heal", "show", "hide", "clear", "stagger" (and next, prev, toggle).
-- Integrated: require("meters_api") in the same Lua state. Development: the meters' own files in its folder,
-- meters-state.txt (key=value lines) and meters-command.txt (one action a line).
local M = {}

function M.parse_state(text)
    if not text or text == "" then return nil end
    local s = {}
    for line in text:gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k then s[k] = v end
    end
    if not s.meter then return nil end
    return { meter = s.meter, label = s.label, visible = s.visible ~= "false" }
end

-- No meters part: the menu shows no meter rows.
function M.none()
    return { kind = "none", present = function() return false end, state = function() return nil end,
             act = function() return false end }
end

function M.direct(api)
    return {
        kind = "meters_api",
        present = function() return true end,
        state = function() return api.state() end,
        act = function(action) return api.act(action) end,
    }
end

-- io = { read(path), write(path, text), exists(path) }; dir: the meters' development folder, with the trailing slash.
function M.bridge(dir, io, log)
    local self = { kind = "bridge" }
    function self.present() return io.exists(dir .. "meters-state.txt") end
    function self.state() return M.parse_state(io.read(dir .. "meters-state.txt")) end
    function self.act(action)
        -- The meters read the whole file, one action a line, and remove it: add to what is still waiting.
        local path = dir .. "meters-command.txt"
        local waiting = io.read(path) or ""
        local ok = io.write(path, waiting .. action .. "\n")
        log("meters\tsent\t" .. action .. "\t" .. tostring(ok))
        return ok
    end
    return self
end

return M
