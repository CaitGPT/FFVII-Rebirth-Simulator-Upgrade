-- Custom Training's course, as the meters see it, without the game (tested offline).
-- In the integrated mod Custom Training calls in through ct_api.on_course; during development it is a separate Lua
-- state and writes ct-course.txt (key=value lines, ct_api.format) on every start, end and change. Either way the
-- state goes through update(), which says what happened:
--   "start"  a course began (or began again)      -> clear the numbers, open the behaviour's meter
--   "change" its setup changed mid-course          -> clear the numbers; the meter follows a new behaviour
--   "end"    the course ended
--   "wave"   Custom Training respawned the chosen set (a key, its menu's Respawn row, or ct_auto_respawn): wave = N.
--            A wave ends when its last enemy dies (last_clear = seconds it took); a respawn mid-fight starts a new
--            wave with no clear time for the one cut short. The numbers keep running; the panel shows "Wave N" and
--            the last clear time
-- MP: in Passive and Healing Custom Training refills MP as it is spent, so it counts what it refills (mp.<Name>=<total>
-- lines, cumulative); mp_spent() turns those into amounts spent since the last call. Aggressive refills nothing.
local M = {}
M.__index = M

local SETUP = { "active", "behaviour", "opponent", "count", "difficulty", "anchor", "mode", "group", "round" }
-- The fields whose change means Custom Training replaces the opponents (everything but the behaviour: a behaviour
-- change leaves them in the fight, seen 2026-11-21, and their last blow must still count).
local OPPONENTS = { "active", "opponent", "count", "difficulty", "anchor", "mode", "group", "round" }

function M.parse(text)
    local t, mp = {}, {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_%.]+)%s*=%s*(.-)%s*$")
        if k then
            local who = k:match("^mp%.(.+)$")
            if who then
                mp[who] = tonumber(v)
            else
                if v == "true" then v = true elseif v == "false" then v = false elseif v == "nil" then v = nil end
                t[k] = v
            end
        end
    end
    t.mp = mp
    return t
end

function M.new()
    return setmetatable({ state = { active = false }, setup = nil, mp_seen = {} }, M)
end

-- A list (ct_api's group is a new table on every call) by its contents, anything else as text.
local function text_of(v)
    if type(v) ~= "table" then return tostring(v) end
    local items = {}
    for i, item in ipairs(v) do items[i] = tostring(item) end
    return "{" .. table.concat(items, ",") .. "}"
end

local function setup_of(state, keys)
    local parts = {}
    for _, k in ipairs(keys or SETUP) do parts[#parts + 1] = text_of(state[k]) end
    return table.concat(parts, "|")
end

-- state: a parsed ct-course.txt or an on_course event. Returns "start", "change", "end", "wave" or nil, and whether
-- the behaviour changed; self.replaced says whether a start or change replaces the opponents (not a behaviour change). The wave number and the last clear time are kept here (state.wave, state.last_clear on the
-- state kept), so they stay shown between Custom Training's events; a start or a change forgets them.
function M:update(state)
    state = state or { active = false }
    local was = self.state
    local setup = setup_of(state)
    local event = nil
    if state.active == true and was.active ~= true then
        event = "start"
    elseif state.active ~= true and was.active == true then
        event = "end"
    elseif state.active == true and (setup ~= self.setup or state.what == "start" and was.what ~= "start") then
        event = state.what == "start" and "start" or "change"
    end
    if event == "start" or event == "change" or state.active ~= true then self.wave, self.last_clear = nil, nil end
    local wave, clear = tonumber(state.wave), tonumber(state.last_clear)
    -- Wave 0 is Custom Training's moment between a start or change and its first spawn: 0 to 1 is not a respawn.
    if not event and wave and self.wave and self.wave >= 1 and wave > self.wave then event = "wave" end
    if wave then self.wave = wave end
    -- Custom Training's waves say the last clear time themselves (nil before one); only without a wave number is the
    -- one an event gave kept.
    if wave then self.last_clear = clear elseif clear then self.last_clear = clear end
    state.wave, state.last_clear = self.wave, self.last_clear
    local behaviour_changed = state.behaviour ~= was.behaviour
    local opponents = setup_of(state, OPPONENTS)
    self.replaced = event == "start" or (event == "change" and opponents ~= self.opponents)
    self.state, self.setup, self.opponents = state, setup, opponents
    -- Custom Training restarts its MP counts at every start and change.
    if event == "start" or event == "change" then self.mp_seen = {} end
    -- mp_counts: Custom Training gives counts (integrated, even before its first refill); otherwise any count seen.
    if state.mp_counts == true or (state.mp and next(state.mp)) then self.mp = state.mp or {} end
    return event, behaviour_changed
end

function M:active() return self.state.active == true end

-- MP spent per member since the last call, from Custom Training's cumulative refill counts. A count that went down
-- was restarted by Custom Training: its new value is all new.
function M:mp_spent()
    local out = {}
    for who, total in pairs(self.mp or {}) do
        local before = self.mp_seen[who] or 0
        local spent = total >= before and total - before or total
        if spent > 0 then out[who] = spent end
        self.mp_seen[who] = total
    end
    return out
end

-- Custom Training's MP counts are the MP spent (so MP isn't read from the party as well), except in Aggressive: real
-- conditions there (owner, 2026-11-21), no MP refill, so MP spent is the party's own MP drops.
function M:counts_mp() return self.mp ~= nil and self.state.behaviour ~= "aggressive" end

return M
