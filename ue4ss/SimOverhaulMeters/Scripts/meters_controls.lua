-- The panel's settings and controls, without the game (tested offline): settings.txt (keys meters_), which meter is
-- shown, whether the panel is shown, and the actions a key, Custom Training's menu or a command asks for.
local M = {}
M.__index = M

-- The three meters, in cycling order. Kinds as in meters_core: damage dealt, damage taken, healing.
M.METERS = { "damage", "taken", "heal" }
M.LABELS = { damage = "Damage", taken = "Tanking", heal = "Healing" }
-- The meter a course opens on, by Custom Training's behaviour (owner, 2026-11-20 evening).
M.FOR_BEHAVIOUR = { passive = "damage", aggressive = "taken", healing = "heal" }

M.DEFAULTS = {
    x = 48, y = 48,                 -- 1920x1080 units from the top left
    visible = "on",                 -- the last show/hide choice, kept for the next course
    next_key = "F9", clear_key = "F5", stagger_key = "F6", toggle_key = "F8",
    window = 5,                     -- seconds for "Last 5 seconds"
    linger = 8,                     -- seconds the last numbers stay after the course ends
    json = "on",                    -- meters.json beside the mod
}
local NUMBERS = { x = { 0, 1800 }, y = { 0, 1000 }, window = { 1, 60 }, linger = { 0, 60 } }
local SWITCHES = { visible = true, json = true }
local KEYS = { next_key = true, clear_key = true, stagger_key = true, toggle_key = true }

function M.parse(text)
    local s = {}
    for k, v in pairs(M.DEFAULTS) do s[k] = v end
    for line in (text or ""):gmatch("[^\r\n]+") do
        local key, value = line:match("^%s*meters_([%w_]+)%s*=%s*(.-)%s*$")
        if key and NUMBERS[key] then
            local n = tonumber(value)
            if n and n >= NUMBERS[key][1] and n <= NUMBERS[key][2] then
                s[key] = n
                s.chosen = s.chosen or {}
                s.chosen[key] = true   -- set by the player: never moved for Battle Meters
            end
        elseif key and SWITCHES[key] and (value == "on" or value == "off") then
            s[key] = value
        elseif key and KEYS[key] and value:match("^[%w_]+$") then
            s[key] = value
        end
    end
    return s
end

-- Settings back to text, keeping every line that isn't ours (other workstreams' keys, comments).
function M.render(s, previous)
    local lines, seen = {}, {}
    for line in (previous or ""):gmatch("[^\r\n]+") do
        local key = line:match("^%s*meters_([%w_]+)%s*=")
        if key and M.DEFAULTS[key] ~= nil then
            if not seen[key] then lines[#lines + 1] = "meters_" .. key .. " = " .. tostring(s[key]); seen[key] = true end
        else
            lines[#lines + 1] = line
        end
    end
    local keys = {}
    for k in pairs(M.DEFAULTS) do keys[#keys + 1] = k end
    table.sort(keys)
    -- The position is written only when the player set it: written as a default it would count as set next time
    -- and stop the panel being placed clear of Battle Meters (seen 2026-11-21).
    local chosen = s.chosen or {}
    for _, k in ipairs(keys) do
        if not seen[k] and (NUMBERS[k] == nil or (k ~= "x" and k ~= "y") or chosen[k]) then
            lines[#lines + 1] = "meters_" .. k .. " = " .. tostring(s[k])
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

-- Battle Meters, as its installed files say (read once at start-up, no game calls). Battle Meters 1.2.0 and later
-- stand aside while meters-active.txt exists; an older one draws its panel in our course too.
--   main: its Scripts/main.lua text (nil: not installed); config: its Scripts/config.lua text; enabled: whether
--   mods.txt or enabled.txt turns it on.
-- Returns { installed, enabled, stands_aside, x, y, width }.
M.BM_WIDTH = 300   -- Battle Meters' panel width (overlay.lua WIDTH)
function M.battle_meters(main, config, enabled)
    local bm = { installed = main ~= nil, enabled = enabled == true, x = 48, y = 240, width = M.BM_WIDTH }
    bm.stands_aside = main ~= nil and (main:find("meters-active.txt", 1, true) ~= nil
        or main:find('require("sim_overhaul")', 1, true) ~= nil)
    for key, field in pairs({ overlay_x = "x", overlay_y = "y" }) do
        local n = tonumber((config or ""):match(key .. "%s*=%s*(%-?%d+)"))
        if n then bm[field] = n end
    end
    return bm
end

-- Whether mods.txt turns a mod on ("Name : 1"), or its folder holds enabled.txt.
function M.mod_enabled(mods_txt, name, has_enabled_txt)
    if has_enabled_txt then return true end
    for line in (mods_txt or ""):gmatch("[^\r\n]+") do
        local n, v = line:match("^%s*([%w_]+)%s*:%s*(%d)")
        if n == name then return v == "1" end
    end
    return false
end

-- Where the panel goes: the top right beside an older, enabled Battle Meters, unless the player set our position.
-- Returns x, y and why.
-- Beside an older Battle Meters (its panel top left) ours goes top right: right beside Battle Meters' it sat near the
-- middle of the screen and covered opponents' nameplates (seen 2026-11-21).
M.PANEL_WIDTH, M.SCREEN_WIDTH, M.MARGIN = 404, 1920, 48
function M.place(settings, bm)
    local chosen = settings.chosen or {}
    if bm and bm.installed and bm.enabled and not bm.stands_aside and not (chosen.x or chosen.y) then
        return M.SCREEN_WIDTH - M.MARGIN - M.PANEL_WIDTH, settings.y,
            "top right, clear of Battle Meters (an older version that doesn't stand aside)"
    end
    return settings.x, settings.y, (chosen.x or chosen.y) and "as set" or "default"
end

function M.new(settings)
    return setmetatable({ settings = settings, meter = "damage", visible = settings.visible == "on" }, M)
end

local function index_of(meter)
    for i, m in ipairs(M.METERS) do if m == meter then return i end end
    return 1
end

-- A course started or its behaviour changed: the matching meter.
function M:follow(behaviour)
    local meter = M.FOR_BEHAVIOUR[behaviour]
    if meter then self.meter = meter end
end

-- One action: "next", "prev", "clear", "stagger", "toggle", "show", "hide", "meter=damage|taken|heal".
-- Returns what the caller must do in the game ("clear", "stagger", "save" when the shown/hidden choice changed), or
-- nil, and whether the action was understood.
function M:act(action)
    action = tostring(action or ""):match("^%s*(.-)%s*$")
    if action == "next" or action == "prev" then
        local step = action == "next" and 1 or -1
        self.meter = M.METERS[(index_of(self.meter) - 1 + step) % #M.METERS + 1]
        return nil, true
    end
    local meter = action:match("^meter%s*=%s*(%w+)$")
    if meter then
        if not M.LABELS[meter] then return nil, false end
        self.meter = meter
        return nil, true
    end
    if action == "clear" or action == "stagger" then return action, true end
    if action == "toggle" or action == "show" or action == "hide" then
        local visible = (action == "show") or (action == "toggle" and not self.visible)
        if visible == self.visible then return nil, true end
        self.visible = visible
        self.settings.visible = visible and "on" or "off"
        return "save", true
    end
    return nil, false
end

-- What Custom Training's menu shows for the meters (and meters-state.txt during development).
function M:state()
    return { meter = self.meter, label = M.LABELS[self.meter], visible = self.visible }
end

function M.format_state(state)
    return string.format("meter=%s\nlabel=%s\nvisible=%s\n", state.meter, state.label, tostring(state.visible))
end

-- The development command file: one action per line, blank lines and # comments ignored.
function M.commands(text)
    local list = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local action = line:match("^%s*(.-)%s*$")
        if action ~= "" and action:sub(1, 1) ~= "#" then list[#list + 1] = action end
    end
    return list
end

return M
