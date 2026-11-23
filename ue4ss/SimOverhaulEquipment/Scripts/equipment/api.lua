-- The equipment workstream's interface: open the game's own main menu (Materia & Equipment, Combat Settings,
-- Upgrade Weapons, Party, ...) from Chadley's simulator menus.
--
--   local ok, equipment = pcall(require, "equipment.api")
--   if ok and equipment.available() then equipment.open() end      -- on the game thread
--   equipment.available()     false while a course runs (after "Begin challenge?" Yes, the fights, "Get Ready")
--   equipment.status()        "idle" | "open"
--   equipment.is_open()       true until the player has left the menu
--   equipment.on_close(fn)    fn(info) once, when the player has left it:
--                             info = { result = "closed" | "never_opened" | "failed", stats_changed = bool,
--                                      battle = false, needs_rebuild = false, seconds = n }
--
-- The owner's rule (2026-11-20): never inside a running course or fight. Opened there, the menu worked and changed
-- stats at once, but the fighters stood in a T-pose afterwards until the fight was given up and rechallenged
-- (docs/workstreams/equipment.md; researched further on ws/equipment-midfight). So open() refuses while a course
-- runs, and `battle` and `needs_rebuild` are always false (kept so callers written against them still work).
local game = require("equipment.game")
local session_module = require("equipment.session")

local M = {}

M.TICK_MS = 100

local state = {
    status = "idle",     -- idle | open
    session = nil,
    started = nil,
    before = nil,
    listeners = {},
    watching = false,
    log = nil,
    last = nil,          -- the last finished visit's info
    guard = nil,         -- fn() -> nil, or why opening isn't allowed now (main.lua: the course has started)
}

local clock = os.clock
function M.set_clock(fn) clock = fn end
function M.set_log(fn) state.log = fn end
local function log(message) if state.log then pcall(state.log, message) end end

-- main.lua tells the API when a course is running. Without it, only a fight blocks.
function M.set_guard(fn) state.guard = fn end

-- Why open() would refuse now, or nil. Game thread.
function M.blocked()
    if state.status ~= "idle" then return "already open" end
    if state.guard then
        local ok, why = pcall(state.guard)
        if ok and why then return why end
    end
    if game.in_battle() == true then return "in a fight" end
    return nil
end

function M.available() return M.blocked() == nil end
function M.status() return state.status end
function M.is_open() return state.status ~= "idle" end
function M.last() return state.last end

function M.on_close(fn)
    if type(fn) == "function" then state.listeners[#state.listeners + 1] = fn end
end

local function stats_differ(a, b)
    if not (a and b) then return false end
    for member, row in pairs(a) do
        local other = b[member]
        if other then
            for i, value in pairs(row) do
                if other[i] ~= nil and value ~= nil and other[i] ~= value then return true end
            end
        end
    end
    return false
end

local function finish(result)
    local info = {
        result = result,
        battle = false,
        needs_rebuild = false,
        seconds = state.started and (clock() - state.started) or 0,
        stats_changed = stats_differ(state.before, game.loadout_stats()),
    }
    -- A main menu that closed oddly has once left the world hidden (2026-11-20, in a fight).
    if game.hide_world() == true and game.pause_menu_closed() == true then
        game.set_hide_world(false)
        info.unhid_world = true
    end
    state.status, state.session, state.before = "idle", nil, nil
    state.last = info
    log(string.format("closed\t%s\tchanged=%s\t%.1fs", result, tostring(info.stats_changed), info.seconds))
    local listeners = state.listeners
    state.listeners = {}
    for _, fn in ipairs(listeners) do pcall(fn, info) end
end

-- One step of the watcher. Called on the game thread.
function M.tick()
    if state.status == "idle" then return false end
    local closed, bit = game.pause_menu_closed(), game.pause_bit()
    for _, action in ipairs(state.session:tick(clock(), closed, bit)) do
        if action == "set_bit" then
            game.set_pause_bit(true)
            log("pause bit set again")
        elseif action == "clear_bit" then
            game.set_pause_bit(false)
            log("pause bit cleared after close")
        elseif action == "finished" then
            finish(state.session.result)
            return false
        end
    end
    return true
end

local function ensure_watcher()
    if state.watching then return end
    state.watching = true
    LoopAsync(M.TICK_MS, function()
        if state.status == "idle" then
            state.watching = false
            return true
        end
        ExecuteInGameThread(function()
            local ok, problem = pcall(M.tick)
            if not ok then log("tick error\t" .. tostring(problem)) end
        end)
        return false
    end)
end

-- Opens the game's main menu. Call on the game thread. Returns true, or false and why not.
function M.open()
    local why = M.blocked()
    if why then
        log("open refused\t" .. why)
        return false, why
    end
    if game.pause_menu_closed() == false then return false, "another menu is open" end
    state.started = clock()
    state.before = game.loadout_stats()
    local ok, problem = game.open_main_menu()
    if not ok then
        log("open failed\t" .. tostring(problem))
        state.before = nil
        return false, problem
    end
    state.status = "open"
    state.session = session_module.new(clock())
    log("main menu requested")
    ensure_watcher()
    return true
end

return M
