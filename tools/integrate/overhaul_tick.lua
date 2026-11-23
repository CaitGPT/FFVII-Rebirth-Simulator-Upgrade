-- Simulator Upgrade: one scheduler for every part's LoopAsync and ExecuteInGameThread (docs/workstreams/lua-state.md).
-- The integrated main.lua installs it before requiring the parts, so the parts stay unchanged.
--
-- Why. In UE4SS 3.0.1 each ExecuteInGameThread call makes a new Lua thread and adds it to `lua_instances`, a global
-- std::unordered_map that every Lua mod's threads read on every UE4SS function call, with no lock. When the map grows
-- past its bucket count it rehashes, and a thread reading it at that moment misses its own state ("The lua state ...
-- has no instance inside lua_instances unordered map", 2026-11-21 06:46) or reads a bad node and crashes the game
-- (UE4SS+bf476c, 8 crash folders). The error is a C++ exception: Lua's pcall can't catch it, and a LoopAsync whose
-- callback throws is dropped by UE4SS for good. Six parts with seven loops made up to ~70 new Lua threads a second.
--
-- What this does instead:
--   * One real LoopAsync (the master, every BASE_MS) runs every part's loop at its own interval, each in pcall, so a
--     Lua error in one part neither stops it nor the others. A second real loop (the watchdog) restarts the master
--     if UE4SS ever drops it.
--   * ExecuteInGameThread only queues the function (pure Lua: no new Lua thread, no UE4SS call). The queue is run on
--     the game thread by the native pump (SimulatorUpgradeNative calls SimOverhaulGameTick from its ProcessEvent
--     callback) when it is running, and otherwise by at most one real ExecuteInGameThread at a time.
-- With the pump: no new Lua threads at all, and the async thread makes no UE4SS calls of its own.

local M = {}

M.BASE_MS = 50              -- the master's period; every part's interval is a multiple of it (50 ms is the fastest)
M.WATCHDOG_MS = 1000
M.WATCHDOG_STALE = 3        -- watchdog runs with no master tick before the master is restarted
M.PUMP_FRESH_MS = 500       -- the pump counts as running if it drained within this many ms of master time
M.REAL_OVERDUE_MS = 5000    -- a real action that started and hasn't finished by then is taken as stopped by a UE4SS error
M.LOAD_GAP_MS = 1000        -- between real calls while the pump ran within LOAD_WINDOW_MS (a load: no pump frames)
M.LOAD_WINDOW_MS = 60000
M.DRAIN_STALE_S = 10        -- os.clock seconds after which a drain that never finished is taken as abandoned

local real = {}             -- UE4SS's own LoopAsync and ExecuteInGameThread
local loops = {}            -- {ms, fn, next_at, name, errors}
local queue = {}            -- functions waiting for the game thread, in order
local batch, batch_i = nil, 1
local log = function() end

M.ticks = 0                 -- master ticks; master time is ticks * BASE_MS
M.gen = 0                   -- the live master's generation; an older master stops itself
M.pump_tick = nil           -- master tick at the pump's last drain
M.real_pending_since = nil  -- master tick when the outstanding real ExecuteInGameThread was queued
M.real_done_tick = nil      -- master tick when the last real action finished draining
M.real_started_tick = nil   -- master tick when the outstanding real action started on the game thread
M.draining_since = nil      -- os.clock() at the start of the running drain
M.stats = {queued = 0, run = 0, errors = 0, real_calls = 0, pump_drains = 0, real_drains = 0, master_starts = 0,
           abandoned = 0, loop_errors = 0}

local function now_ms() return M.ticks * M.BASE_MS end

function M.pump_running()
    return M.pump_tick ~= nil and (M.ticks - M.pump_tick) * M.BASE_MS <= M.PUMP_FRESH_MS
end

-- The replacement ExecuteInGameThread: queue it. Same contract as UE4SS's: the function runs later on the game thread.
function M.execute_in_game_thread(fn)
    if type(fn) ~= "function" then
        error("ExecuteInGameThread(LuaFunction callback): callback is not a function", 2)
    end
    queue[#queue + 1] = fn
    M.stats.queued = M.stats.queued + 1
end

-- The replacement LoopAsync: run fn every ms (first after ms), until it returns true.
function M.loop_async(ms, fn)
    if type(ms) ~= "number" or type(fn) ~= "function" then
        error("LoopAsync(integer DelayInMilliseconds, LuaFunction Callback): bad arguments", 2)
    end
    local info = debug and debug.getinfo and debug.getinfo(2, "Sl")
    local name = info and ((info.short_src or "?") .. ":" .. tostring(info.currentline)) or "?"
    loops[#loops + 1] = {ms = ms, fn = fn, next_at = now_ms() + ms, name = name, errors = 0}
end

local function set_game_thread_flag(value)
    -- UE4SS keeps "IsInGameThread" in the registry for LoadAsset; set it as UE4SS does around its own actions.
    local ok, registry = pcall(function() return debug.getregistry() end)
    if ok and type(registry) == "table" then
        local before = registry.IsInGameThread
        registry.IsInGameThread = value
        return before
    end
end

-- Runs the queue. Game thread only (the pump, or a real ExecuteInGameThread). A UE4SS error inside a function is a C++
-- exception that skips every pcall and stops this drain where it is: the index has moved on already, so the next
-- drain carries on after the function that threw.
function M.drain(source)
    if M.draining_since then
        if os.clock() - M.draining_since < M.DRAIN_STALE_S then return 0 end   -- re-entered from inside a drain
        M.stats.abandoned = M.stats.abandoned + 1
        log("drain\tabandoned\ta UE4SS error stopped an earlier drain")
    end
    if source == "pump" then M.pump_tick = M.ticks end
    if not batch then
        if #queue == 0 then return 0 end
        batch, batch_i, queue = queue, 1, {}
    end
    M.draining_since = os.clock()
    local before = set_game_thread_flag(true)
    local count = 0
    while batch and batch_i <= #batch do
        local fn = batch[batch_i]
        batch_i = batch_i + 1
        count = count + 1
        local ok, err = pcall(fn)
        M.stats.run = M.stats.run + 1
        if not ok then
            M.stats.errors = M.stats.errors + 1
            log("game\terror\t" .. tostring(err))
        end
        if batch_i > #batch then batch = nil end
    end
    set_game_thread_flag(before)
    M.draining_since = nil
    if source == "pump" then M.stats.pump_drains = M.stats.pump_drains + 1
    else M.stats.real_drains = M.stats.real_drains + 1 end
    return count
end

-- Called by the native pump on the game thread (as SimOverhaulGameTick).
function M.game_tick()
    return M.drain("pump")
end

-- UE4SS's ExecuteInGameThread does luaL_ref twice on the calling (async) thread, and after running the action
-- luaL_unref on the game thread, outside any lock: each is several Lua API calls, so the two can take the same
-- registry slot and the next action's ref is "not function", which UE4SS throws outside its TRY and the game dies
-- (crash 2026-11-21 08:54, UE4SS+bf2ea2). So the next real call waits until the last action has finished and a
-- whole master tick has passed, by which time UE4SS has unref'd it.
-- One that is queued and hasn't started (the game paused or loading: no ProcessEvent) is never replaced: UE4SS keeps it
-- and runs it when frames come back, and each replacement would be one more Lua thread in lua_instances. Only one that
-- started and never finished (a UE4SS error escaped its drain) is replaced, after REAL_OVERDUE_MS.
local function queue_real_drain()
    if M.real_pending_since then return end
    if M.real_started_tick and (M.ticks - M.real_started_tick) * M.BASE_MS < M.REAL_OVERDUE_MS then return end
    if M.real_done_tick and M.ticks - M.real_done_tick < 2 then return end
    -- In a load the pump stops for 10-30 s while UE4SS keeps running its actions: one real call a second then, not
    -- one every other master tick (that was ~100 Lua threads per load, seen in the game 2026-11-21).
    if M.real_done_tick and M.pump_tick and (M.ticks - M.pump_tick) * M.BASE_MS < M.LOAD_WINDOW_MS
        and (M.ticks - M.real_done_tick) * M.BASE_MS < M.LOAD_GAP_MS then return end
    M.real_pending_since = M.ticks
    M.real_started_tick = nil
    M.stats.real_calls = M.stats.real_calls + 1
    local ok, err = pcall(real.ExecuteInGameThread, function()
        M.real_pending_since = nil
        M.real_started_tick = M.ticks
        M.drain("ue4ss")
        M.real_started_tick = nil
        M.real_done_tick = M.ticks
    end)
    if not ok then
        M.real_pending_since = nil
        log("real\terror\t" .. tostring(err))
    end
end

function M.master_tick()
    M.ticks = M.ticks + 1
    local now = now_ms()
    local i = 1
    while i <= #loops do
        local loop = loops[i]
        local remove = false
        if now >= loop.next_at then
            loop.next_at = now + loop.ms
            local ok, result = pcall(loop.fn)
            if not ok then
                loop.errors = loop.errors + 1
                M.stats.loop_errors = M.stats.loop_errors + 1
                if loop.errors == 1 or loop.errors % 100 == 0 then
                    log("loop\terror\t" .. loop.name .. "\t" .. loop.errors .. "\t" .. tostring(result))
                end
            elseif result == true then
                remove = true
            end
        end
        if remove then table.remove(loops, i) else i = i + 1 end
    end
    if (#queue > 0 or batch) and not M.pump_running() then queue_real_drain() end
end

local function start_master(reason)
    M.gen = M.gen + 1
    local gen = M.gen
    M.stats.master_starts = M.stats.master_starts + 1
    real.LoopAsync(M.BASE_MS, function()
        if gen ~= M.gen then return true end
        M.master_tick()
        return false
    end)
    if reason then log("master\tstarted\t" .. reason) end
end

local function start_watchdog()
    local seen, stale = -1, 0
    real.LoopAsync(M.WATCHDOG_MS, function()
        if M.ticks == seen then
            stale = stale + 1
            if stale >= M.WATCHDOG_STALE then
                stale = 0
                start_master("after " .. M.WATCHDOG_STALE .. " s without a master tick")
            end
        else
            seen, stale = M.ticks, 0
        end
        return false
    end)
end

function M.status()
    local s = M.stats
    return string.format("pump %s, loops %d, queued %d, run %d, errors %d, real %d, drains pump %d ue4ss %d, " ..
        "masters %d, abandoned %d", M.pump_running() and "on" or "off", #loops, s.queued, s.run, s.errors,
        s.real_calls, s.pump_drains, s.real_drains, s.master_starts, s.abandoned)
end

-- Status for the soak and for bug reports: every 30 s into <dir>overhaul-tick.txt on a development install (plain
-- Lua io on the async thread: no UE4SS call, nothing on the game thread), and into UE4SS.log after a minute and then
-- every 10 minutes. The native pump's own status is read on the game thread, by the queue.
M.REPORT_MS = 30000
function M.start_reports(dir, dev, printer)
    local n = 0
    M.loop_async(M.REPORT_MS, function()
        n = n + 1
        M.execute_in_game_thread(function()
            local status = rawget(_G, "SimOverhaulGamePumpStatus")
            if type(status) == "function" then
                local ok, text = pcall(status)
                M.pump_status = ok and tostring(text) or ("error: " .. tostring(text))
            end
        end)
        local line = M.status() .. "; native pump: " .. tostring(M.pump_status or "absent")
        if dev and dir then
            local f = io.open(dir .. "overhaul-tick.txt", "w")
            if f then
                f:write(os.date("!%Y-%m-%dT%H:%M:%SZ"), "\t", line, "\n")
                f:close()
            end
        end
        if printer and (n == 2 or n % 20 == 0) then printer("status\t" .. line) end
        return false
    end)
end

-- Replaces env's LoopAsync and ExecuteInGameThread and starts the master and watchdog. Call once, before the parts
-- load, after the real first ExecuteInGameThread (which registers UE4SS's game-thread callback while mods load).
function M.install(env, logger)
    if real.LoopAsync then return M end
    real.LoopAsync, real.ExecuteInGameThread = env.LoopAsync, env.ExecuteInGameThread
    if logger then log = logger end
    env.LoopAsync = M.loop_async
    env.ExecuteInGameThread = M.execute_in_game_thread
    env.SimOverhaulGameTick = M.game_tick
    start_master()
    start_watchdog()
    return M
end

-- For the tests only: forget everything.
function M._reset()
    real, loops, queue, batch, batch_i = {}, {}, {}, nil, 1
    log = function() end
    M.ticks, M.gen, M.pump_tick, M.real_pending_since, M.draining_since = 0, 0, nil, nil, nil
    M.real_done_tick, M.real_started_tick = nil, nil
    for k in pairs(M.stats) do M.stats[k] = 0 end
end

return M
