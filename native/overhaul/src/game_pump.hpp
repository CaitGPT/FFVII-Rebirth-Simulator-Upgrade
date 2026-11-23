// Simulator Upgrade's game-thread pump (docs/workstreams/lua-state.md). It runs the integrated Lua mod's game-thread
// queue (tools/integrate/overhaul_tick.lua) from a ProcessEvent callback, so the mod never calls ExecuteInGameThread
// during play.
//
// Why: in UE4SS 3.0.1 every ExecuteInGameThread makes a new Lua thread and inserts it into `lua_instances`, a global
// std::unordered_map that every UE4SS function call from every Lua mod reads, on any thread, without a lock. A rehash
// while another thread reads it makes that lookup miss ("The lua state ... has no instance inside lua_instances
// unordered map": the LoopAsync is then dropped for good) or read a bad node (the UE4SS+bf476c crashes). This pump
// uses Lua threads made once, at start-up, so it inserts nothing during play.
//
// How:
// - SimOverhaulGamePumpBind(), called by main.lua from its first ExecuteInGameThread (which UE4SS runs on the game
//   thread from its own ProcessEvent callback), records that thread. The pump runs on that thread only.
// - At most every INTERVAL_MS, from inside a ProcessEvent call on that thread, it calls the Lua global
//   SimOverhaulGameTick on its own Lua thread (made in on_lua_start, kept in the registry).
// - A UE4SS error inside the tick is a C++ exception that skips Lua's own error handling and leaves that Lua thread
//   mid-call. The pump then moves to the next of SPARES threads made at start-up (making one during play would be the
//   insert this avoids). With none left it stops, and the Lua side goes back to UE4SS's ExecuteInGameThread.
// - Re-entry (a ProcessEvent made by the tick itself) is skipped.
//
// SimOverhaulGamePumpStatus() returns a one-line summary for logs. The logic is in game_pump_core.hpp.
#pragma once

#include <Windows.h>
#include <Mod/CppUserModBase.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/UFunction.hpp>

#include <functional>

#include "game_pump_core.hpp"

namespace RC::Unreal::Hook
{
    // Exact declaration from the installed UEPseudo (as the meters part and the telemetry exporter use it).
    using ProcessEventCallback = std::function<void(UObject*, UFunction*, void*)>;
    RC_UE_API auto RegisterProcessEventPreCallback(ProcessEventCallback) -> void;
}

namespace SimOverhaulGamePump
{
    using State = BasicState<RC::LuaMadeSimple::Lua>;
    // Never freed: a ProcessEvent callback can still run while the game shuts down.
    inline State* g_state = new State();

    inline void on_process_event(RC::Unreal::UObject*, RC::Unreal::UFunction*, void*)
    {
        State& s = *g_state;
        if (s.game_thread.load(std::memory_order_relaxed) == 0) return;   // the common case before binding: one load
        const unsigned long long now = GetTickCount64();
        if (!due(s, GetCurrentThreadId(), now)) return;
        run_tick(s, now, [](RC::LuaMadeSimple::Lua& lua) { lua.call_function(TICK_FUNCTION, 0, 0); });
    }

    inline int lua_bind(const RC::LuaMadeSimple::Lua&)
    {
        g_state->game_thread.store(GetCurrentThreadId(), std::memory_order_relaxed);
        return 0;
    }

    inline int lua_status(const RC::LuaMadeSimple::Lua& lua)
    {
        lua.set_string(status_text(*g_state));
        return 1;
    }

    class Pump
    {
    public:
        // At load, as the other parts do: registering a ProcessEvent callback during play can crash.
        void on_unreal_init() { RC::Unreal::Hook::RegisterProcessEventPreCallback(on_process_event); }

        // Lua mods start after the C++ mods. Make the pump's Lua threads now, while the mod loads, and anchor each in
        // the registry (new_thread pushes it; make_ref pops it into a reference). A restarted Lua mod is a new Lua
        // state: start again, unbound until its main.lua binds the game thread.
        void on_lua_start(RC::StringViewType mod_name, RC::LuaMadeSimple::Lua& lua)
        {
            if (mod_name != STR("SimulatorUpgrade")) return;
            State& s = *g_state;
            s.game_thread.store(0);
            s.stopped = false;
            s.current = 0;
            for (size_t i = 0; i < SPARES; ++i)
            {
                s.threads[i] = &lua.new_thread();
                lua.registry().make_ref();
            }
            s.made = SPARES;
            lua.register_function("SimOverhaulGamePumpBind", lua_bind);
            lua.register_function("SimOverhaulGamePumpStatus", lua_status);
        }
    };
}
