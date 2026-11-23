// The game-thread pump's logic without UE4SS (game_pump.hpp wires it in; tests/integrate/game_pump_test.cpp tests it
// with a fake Lua). LuaT needs get_stack_size() and discard_value(int).
#pragma once

#include <array>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <string>
#include <string_view>

namespace SimOverhaulGamePump
{
    constexpr unsigned long long INTERVAL_MS = 40;      // the parts' fastest loop is 50 ms
    constexpr unsigned long long RETRY_MS = 1000;       // after the tick function was missing or failed
    constexpr size_t SPARES = 32;  // each lua_instances miss caused by another mod spends one (one in ~8 min seen in the game)
    constexpr const char* TICK_FUNCTION = "SimOverhaulGameTick";

    enum class Failure { none, missing, lua_error, ue4ss_error };

    // What a failed call's message says happened. LuaMadeSimple throws "[Lua::prepare_function_call] ..." when the
    // global isn't a function (stack already cleaned) and "[Lua::call_function] ..." when lua_pcall reported an error;
    // anything else is a UE4SS error that escaped past lua_pcall. "C stack overflow" means the thread's C-call count
    // leaked from earlier escapes: that thread is spent too.
    inline Failure classify(std::string_view what)
    {
        if (what.starts_with("[Lua::prepare_function_call]")) return Failure::missing;
        if (what.starts_with("[Lua::call_function]") && what.find("C stack overflow") == std::string_view::npos)
            return Failure::lua_error;
        return Failure::ue4ss_error;
    }

    template <typename LuaT>
    struct BasicState
    {
        std::atomic<unsigned long> game_thread{0};
        bool busy{};
        bool stopped{};
        unsigned long long last{};
        unsigned long long retry_at{};
        std::array<LuaT*, SPARES> threads{};
        size_t current{};
        size_t made{};
        uint64_t ticks{}, missing{}, lua_errors{}, escapes{};
        std::string last_error;
        bool quiet{};   // tests: no printing

        void note_error(std::string_view what)
        {
            last_error.assign(what.substr(0, 300));
            if (!quiet) printf_s("[SimulatorUpgradeNative] game pump: %s\n", last_error.c_str());
        }
    };

    // Whether a ProcessEvent call on `thread` at `now` should run a tick.
    template <typename LuaT>
    bool due(const BasicState<LuaT>& s, unsigned long thread, unsigned long long now)
    {
        const unsigned long game_thread = s.game_thread.load(std::memory_order_relaxed);
        if (game_thread == 0 || thread != game_thread || s.busy || s.stopped) return false;
        return now - s.last >= INTERVAL_MS && now >= s.retry_at;
    }

    // One tick, on the game thread: call_tick(lua) calls the Lua tick function on the current spare thread.
    template <typename LuaT, typename CallTick>
    void run_tick(BasicState<LuaT>& s, unsigned long long now, CallTick&& call_tick)
    {
        s.last = now;
        LuaT* lua = s.current < s.made ? s.threads[s.current] : nullptr;
        if (!lua)
        {
            s.stopped = true;
            return;
        }
        s.busy = true;
        Failure failure = Failure::none;
        std::string what;
        try
        {
            call_tick(*lua);
            ++s.ticks;
        }
        catch (const std::exception& e)
        {
            what = e.what();
            failure = classify(what);
        }
        catch (...)
        {
            what = "unknown exception";
            failure = Failure::ue4ss_error;
        }
        s.busy = false;
        switch (failure)
        {
        case Failure::none:
            break;
        case Failure::missing:
            ++s.missing;
            s.retry_at = now + RETRY_MS;
            break;
        case Failure::lua_error:
            ++s.lua_errors;
            s.note_error(what);
            while (lua->get_stack_size() > 0) lua->discard_value(-1);
            s.retry_at = now + RETRY_MS;
            break;
        case Failure::ue4ss_error:
            ++s.escapes;
            s.note_error(what);
            ++s.current;
            if (s.current >= s.made)
            {
                s.stopped = true;
                if (!s.quiet) printf_s("[SimulatorUpgradeNative] game pump stopped: no spare Lua thread left\n");
            }
            break;
        }
    }

    template <typename LuaT>
    std::string status_text(const BasicState<LuaT>& s)
    {
        char line[512];
        snprintf(line, sizeof(line), "%s, thread %zu of %zu, ticks %llu, missing %llu, lua errors %llu, ue4ss errors %llu%s%s",
                 s.stopped ? "stopped" : (s.game_thread.load() ? "running" : "not bound"),
                 s.current < s.made ? s.current + 1 : s.made, s.made, static_cast<unsigned long long>(s.ticks),
                 static_cast<unsigned long long>(s.missing), static_cast<unsigned long long>(s.lua_errors),
                 static_cast<unsigned long long>(s.escapes), s.last_error.empty() ? "" : ", last: ",
                 s.last_error.c_str());
        return line;
    }
}
