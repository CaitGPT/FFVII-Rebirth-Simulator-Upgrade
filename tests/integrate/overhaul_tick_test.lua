-- overhaul_tick.lua against a fake UE4SS: its async thread (LoopAsync, dropping a loop whose callback errors or
-- returns true, as UE4SS 3.0.1 does), its game-thread actions (one Lua thread each) and the native pump.
local M = require("overhaul_tick")

local function fake_ue4ss()
    local u = {t = 0, loops = {}, actions = {}, real_calls = 0, outstanding_max = 0}
    function u.LoopAsync(ms, fn)
        u.loops[#u.loops + 1] = {ms = ms, fn = fn, next_at = u.t + ms, alive = true}
    end
    function u.ExecuteInGameThread(fn)
        assert(type(fn) == "function")
        u.real_calls = u.real_calls + 1
        u.actions[#u.actions + 1] = fn
        if #u.actions > u.outstanding_max then u.outstanding_max = #u.actions end
    end
    -- The async thread, 5 ms at a time.
    function u.run_async(ms)
        local stop = u.t + ms
        while u.t < stop do
            u.t = u.t + 5
            for _, loop in ipairs(u.loops) do
                if loop.alive and u.t >= loop.next_at then
                    local ok, result = pcall(loop.fn)
                    if not ok or result == true then loop.alive = false end
                    loop.next_at = u.t + loop.ms
                end
            end
        end
    end
    -- One game frame: UE4SS runs every queued action.
    function u.frame()
        local actions = u.actions
        u.actions = {}
        for _, fn in ipairs(actions) do pcall(fn) end
    end
    -- A frame whose actions run without pcall, so a yield inside one (a UE4SS error) leaves the frame.
    function u.frame_raw()
        local actions = u.actions
        u.actions = {}
        for _, fn in ipairs(actions) do fn() end
    end
    function u.alive_loops()
        local n = 0
        for _, loop in ipairs(u.loops) do if loop.alive then n = n + 1 end end
        return n
    end
    return u
end

local function setup()
    M._reset()
    local u = fake_ue4ss()
    local env = {LoopAsync = u.LoopAsync, ExecuteInGameThread = u.ExecuteInGameThread}
    local logged = {}
    M.install(env, function(line) logged[#logged + 1] = line end)
    return u, env, logged
end

-- Plays `seconds` of the game: async time in 50 ms steps, a game frame after each (and the pump, if on).
local function play(u, env, seconds, pump)
    for _ = 1, math.floor(seconds * 20) do
        u.run_async(50)
        u.frame()
        if pump then env.SimOverhaulGameTick() end
    end
end

local tests = {}

function tests.parts_keep_their_globals_and_intervals()
    local u, env = setup()
    assert(env.LoopAsync ~= u.LoopAsync and env.ExecuteInGameThread ~= u.ExecuteInGameThread)
    assert(#u.loops == 2, "master and watchdog are the only real loops")
    local runs = {}
    for _, ms in ipairs({50, 100, 200, 250, 2000}) do
        runs[ms] = 0
        env.LoopAsync(ms, function() runs[ms] = runs[ms] + 1; return false end)
    end
    play(u, env, 10)
    assert(#u.loops == 2, "parts' loops never reach UE4SS")
    for ms, n in pairs(runs) do
        local expected = 10000 // ms
        assert(math.abs(n - expected) <= 1, ms .. " ms loop ran " .. n .. " times, expected about " .. expected)
    end
end

function tests.game_work_is_coalesced_without_the_pump()
    local u, env = setup()
    local ran, order = 0, {}
    -- Seven loops like the parts', each queuing game work every run (the worst case: a course with the menu open).
    for i, ms in ipairs({50, 50, 50, 100, 200, 250, 2000}) do
        env.LoopAsync(ms, function()
            env.ExecuteInGameThread(function() ran = ran + 1; order[#order + 1] = i end)
            return false
        end)
    end
    play(u, env, 10)
    local before = 3 * 200 + 100 + 50 + 40 + 5        -- what UE4SS made with one Lua thread per call: ~795 in 10 s
    assert(ran >= before - 10, "every queued function ran: " .. ran)
    assert(u.real_calls <= 200, "at most one real ExecuteInGameThread per master tick: " .. u.real_calls)
    assert(u.outstanding_max == 1, "never more than one real action outstanding")
    assert(M.stats.real_drains > 0 and M.stats.pump_drains == 0)
end

function tests.the_pump_takes_over_and_hands_back()
    local u, env = setup()
    local ran = 0
    env.LoopAsync(50, function() env.ExecuteInGameThread(function() ran = ran + 1 end); return false end)
    play(u, env, 2, true)
    local calls_with_pump_start = u.real_calls
    assert(M.pump_running())
    play(u, env, 10, true)
    assert(u.real_calls == calls_with_pump_start, "no real ExecuteInGameThread while the pump runs")
    assert(ran >= 230, "the pump ran the work: " .. ran)
    -- The pump stops (a load, or the native part failed): back to real actions within PUMP_FRESH_MS.
    local ran_before = ran
    play(u, env, 3, false)
    assert(not M.pump_running())
    assert(u.real_calls > calls_with_pump_start, "fell back to UE4SS's game-thread actions")
    assert(ran > ran_before + 40, "work kept running without the pump")
end

function tests.a_failing_loop_keeps_running_and_spares_the_others()
    local u, env, logged = setup()
    local bad, good = 0, 0
    env.LoopAsync(50, function() bad = bad + 1; error("part bug") end)
    env.LoopAsync(100, function() good = good + 1; return false end)
    play(u, env, 5)
    assert(bad >= 99, "UE4SS would have dropped it after one error; it ran " .. bad .. " times")
    assert(good >= 49)
    assert(u.alive_loops() == 2, "the master survives part errors")
    assert(#logged >= 1 and logged[1]:find("part bug", 1, true), "the first error is logged")
    assert(#logged < 5, "and not every one: " .. #logged)
end

function tests.returning_true_stops_only_that_loop()
    local u, env = setup()
    local a, b = 0, 0
    env.LoopAsync(50, function() a = a + 1; return a >= 3 end)
    env.LoopAsync(50, function() b = b + 1; return false end)
    play(u, env, 2)
    assert(a == 3, "stopped after returning true: " .. a)
    assert(b >= 39)
end

function tests.work_queued_during_a_drain_runs_in_the_next_one()
    local u, env = setup()
    local seen = {}
    env.ExecuteInGameThread(function()
        seen[#seen + 1] = "first"
        env.ExecuteInGameThread(function() seen[#seen + 1] = "nested" end)
        assert(env.SimOverhaulGameTick() == 0, "a drain inside a drain does nothing")
    end)
    env.ExecuteInGameThread(function() seen[#seen + 1] = "second" end)
    assert(env.SimOverhaulGameTick() == 2)
    assert(seen[1] == "first" and seen[2] == "second" and #seen == 2)
    assert(env.SimOverhaulGameTick() == 1 and seen[3] == "nested")
end

-- A UE4SS error is a C++ exception: it skips every pcall and stops the drain where it is. A coroutine that is
-- never resumed models that: nothing after the yield runs.
function tests.a_ue4ss_error_skips_only_the_function_that_threw()
    local u, env, logged = setup()
    local seen = {}
    env.ExecuteInGameThread(function() seen[#seen + 1] = 1 end)
    env.ExecuteInGameThread(function() coroutine.yield("ue4ss error") end)
    env.ExecuteInGameThread(function() seen[#seen + 1] = 3 end)
    local co = coroutine.create(function() return env.SimOverhaulGameTick() end)
    local ok, why = coroutine.resume(co)
    assert(ok and why == "ue4ss error" and #seen == 1)
    assert(env.SimOverhaulGameTick() == 0, "an unfinished drain looks like a running one at first")
    M.DRAIN_STALE_S = -1            -- os.clock moved on
    assert(env.SimOverhaulGameTick() == 1, "the next drain carries on after the function that threw")
    assert(seen[2] == 3 and #seen == 2, "and doesn't run it again")
    assert(M.stats.abandoned == 1)
    M.DRAIN_STALE_S = 10
    assert(logged[#logged]:find("abandoned", 1, true))
end

function tests.the_watchdog_restarts_a_dropped_master()
    local u, env, logged = setup()
    local runs = 0
    env.LoopAsync(50, function() runs = runs + 1; return false end)
    play(u, env, 1)
    u.loops[1].alive = false       -- UE4SS dropped the master (a UE4SS error in it)
    local before = runs
    play(u, env, 2)
    assert(runs == before, "nothing runs while the master is gone")
    play(u, env, 3)
    assert(runs > before + 20, "the watchdog started a new master: " .. runs - before)
    assert(M.stats.master_starts == 2)
    assert(logged[#logged]:find("master", 1, true))
    play(u, env, 5)
    assert(M.stats.master_starts == 2, "only once")
end

function tests.an_old_master_stops_itself()
    local u, env = setup()
    play(u, env, 1)
    -- A second master by mistake (the watchdog firing while the first is alive can't happen, but if it did):
    M.gen = M.gen + 1
    play(u, env, 1)
    assert(not u.loops[1].alive, "the first master returned true and is gone")
end

function tests.the_game_thread_flag_is_set_while_draining()
    local u, env = setup()
    local registry = debug.getregistry()
    registry.IsInGameThread = false
    local inside
    env.ExecuteInGameThread(function() inside = registry.IsInGameThread end)
    env.SimOverhaulGameTick()
    assert(inside == true and registry.IsInGameThread == false)
end

function tests.bad_arguments_fail_like_ue4ss()
    local u, env = setup()
    assert(not pcall(env.ExecuteInGameThread, 5))
    assert(not pcall(env.LoopAsync, "x", function() end))
end

function tests.no_real_call_until_ue4ss_has_unrefd_the_last_action()
    M._reset()
    local u = fake_ue4ss()
    local call_ticks, done_ticks = {}, {}
    local function real_execute(fn)
        call_ticks[#call_ticks + 1] = M.ticks
        u.ExecuteInGameThread(function() fn(); done_ticks[#done_ticks + 1] = M.ticks end)
    end
    local env2 = {LoopAsync = u.LoopAsync, ExecuteInGameThread = real_execute}
    M.install(env2, function() end)
    env2.LoopAsync(50, function() env2.ExecuteInGameThread(function() end); return false end)
    play(u, env2, 5)
    assert(#call_ticks > 10, "real actions still ran: " .. #call_ticks)
    for i = 2, #call_ticks do
        assert(call_ticks[i] - done_ticks[i - 1] >= 2,
            "real call " .. i .. " at tick " .. call_ticks[i] .. ", last action done at " .. done_ticks[i - 1])
    end
end

function tests.a_real_action_waiting_for_frames_is_not_replaced()
    local u, env = setup()
    env.LoopAsync(50, function() env.ExecuteInGameThread(function() end); return false end)
    u.run_async(30000)                 -- the game paused for 30 s: no frames, so the real action waits
    assert(u.real_calls == 1, "one real ExecuteInGameThread, not one per REAL_OVERDUE_MS: " .. u.real_calls)
    u.frame()
    u.run_async(200)
    assert(u.real_calls == 2, "the next one after it ran: " .. u.real_calls)
end

function tests.a_load_makes_one_real_call_a_second()
    local u, env = setup()
    local ran = 0
    env.LoopAsync(50, function() env.ExecuteInGameThread(function() ran = ran + 1 end); return false end)
    play(u, env, 3, true)                          -- the pump runs
    local before = u.real_calls
    play(u, env, 20, false)                        -- a 20 s load: frames for UE4SS's actions, none for the pump
    local made = u.real_calls - before
    assert(made <= 21, "about one real call a second in a load: " .. made)
    assert(ran >= 20 * 20 - 30, "the work still ran, batched: " .. ran)
end

function tests.a_real_action_stopped_by_a_ue4ss_error_is_replaced()
    local u, env = setup()
    env.LoopAsync(50, function() return false end)
    env.ExecuteInGameThread(function() coroutine.yield("ue4ss error") end)
    u.run_async(100)
    assert(u.real_calls == 1)
    local co = coroutine.create(function() u.frame_raw() end)
    assert(coroutine.resume(co))        -- the action starts and never finishes
    env.ExecuteInGameThread(function() end)
    u.run_async(1000)
    assert(u.real_calls == 1, "still within REAL_OVERDUE_MS")
    u.run_async(5000)
    assert(u.real_calls == 2, "replaced after REAL_OVERDUE_MS: " .. u.real_calls)
end

function tests.reports_read_the_pump_on_the_game_thread_and_log_rarely()
    local u, env, logged = setup()
    local status_calls = 0
    SimOverhaulGamePumpStatus = function() status_calls = status_calls + 1; return "running, thread 1 of 4" end
    local printed = {}
    M.start_reports(nil, false, function(line) printed[#printed + 1] = line end)
    play(u, env, 61, true)
    SimOverhaulGamePumpStatus = nil
    assert(status_calls == 2, "the pump's status was read on the game thread each 30 s: " .. status_calls)
    assert(#printed == 1, "logged once in the first minute: " .. #printed)
    assert(printed[1]:find("native pump: running", 1, true), printed[1])
    assert(printed[1]:find("real 0,", 1, true), "the pump ran from the first frame: no real ExecuteInGameThread")
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
    local ok, err = pcall(tests[name])
    if not ok then error(name .. ": " .. tostring(err), 0) end
end
print("overhaul_tick: " .. #names .. " tests passed")
