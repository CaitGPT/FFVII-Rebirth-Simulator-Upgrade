// The game-thread pump's logic (native/overhaul/src/game_pump_core.hpp) with a fake Lua: when it ticks, what each
// kind of failure does, and that it moves to a spare Lua thread after a UE4SS error and stops when none are left.
//   tests/integrate/Build-GamePumpTest.ps1
#include "../../native/overhaul/src/game_pump_core.hpp"

#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <string>

namespace
{
    struct FakeLua
    {
        int stack{};
        int calls{};
        int get_stack_size() const { return stack; }
        void discard_value(int) { --stack; }
    };

    using State = SimOverhaulGamePump::BasicState<FakeLua>;
    using SimOverhaulGamePump::Failure;

    int failures = 0;
    void check(bool ok, const char* what)
    {
        if (!ok)
        {
            std::printf("FAILED: %s\n", what);
            ++failures;
        }
    }

    State* fresh(FakeLua (&luas)[SimOverhaulGamePump::SPARES])
    {
        auto* s = new State();
        s->quiet = true;
        for (size_t i = 0; i < SimOverhaulGamePump::SPARES; ++i) s->threads[i] = &luas[i];
        s->made = SimOverhaulGamePump::SPARES;
        s->game_thread = 7;
        return s;
    }
}

int main()
{
    using SimOverhaulGamePump::classify;
    check(classify("[Lua::prepare_function_call] lua_getglobal returned !LUA_TFUNCTION, type returned: nil") ==
              Failure::missing, "a missing tick function");
    check(classify("[Lua::call_function] lua_pcall returned LUA_ERRRUN => overhaul_tick.lua:90: boom") ==
              Failure::lua_error, "a Lua error");
    check(classify("[Lua::call_function] lua_pcall returned LUA_ERRRUN => C stack overflow") == Failure::ue4ss_error,
          "C stack overflow spends the thread");
    check(classify("[process_lua_function] The lua state '0x16c218b5408' has no instance inside lua_instances "
                   "unordered map") == Failure::ue4ss_error, "the lua_instances miss");
    check(classify("Tried calling a member function but the UObject instance is nullptr") == Failure::ue4ss_error,
          "any other UE4SS error");

    FakeLua luas[SimOverhaulGamePump::SPARES]{};
    State& s = *fresh(luas);

    // When it ticks.
    State unbound;
    check(!due(unbound, 7, 1000), "not before the game thread is bound");
    check(!due(s, 8, 1000), "not on another thread");
    check(due(s, 7, 1000), "on the game thread");
    run_tick(s, 1000, [](FakeLua& l) { ++l.calls; });
    check(s.ticks == 1 && luas[0].calls == 1, "a tick calls the Lua tick on the first thread");
    check(!due(s, 7, 1000 + SimOverhaulGamePump::INTERVAL_MS - 1), "not again within the interval");
    check(due(s, 7, 1000 + SimOverhaulGamePump::INTERVAL_MS), "again after it");
    bool reentered = true;
    run_tick(s, 2000, [&](FakeLua&) { reentered = due(s, 7, 5000); });
    check(!reentered, "not from inside a tick (a ProcessEvent the tick makes)");

    // The tick function is missing (the Lua mod failed or hasn't started): wait, same thread.
    run_tick(s, 3000, [](FakeLua&) { throw std::runtime_error("[Lua::prepare_function_call] lua_getglobal returned !LUA_TFUNCTION"); });
    check(s.missing == 1 && s.current == 0, "missing: counted, same thread");
    check(!due(s, 7, 3500) && due(s, 7, 3000 + SimOverhaulGamePump::RETRY_MS), "missing: retried after a second");

    // A Lua error in the tick itself: the message left on the stack is cleared, same thread.
    luas[0].stack = 2;
    run_tick(s, 5000, [](FakeLua&) { throw std::runtime_error("[Lua::call_function] lua_pcall returned LUA_ERRRUN => x"); });
    check(s.lua_errors == 1 && s.current == 0 && luas[0].stack == 0, "lua error: stack cleared, same thread");
    check(!due(s, 7, 5500), "lua error: waits a second");

    // UE4SS errors: each spends a thread; after the last, the pump stops for good.
    for (size_t i = 0; i < SimOverhaulGamePump::SPARES; ++i)
    {
        check(due(s, 7, 10000 + i * 100), "due before each UE4SS error");
        run_tick(s, 10000 + i * 100, [](FakeLua&) { throw std::runtime_error("[process_lua_function] no instance"); });
        check(s.escapes == i + 1, "ue4ss error counted");
        check(s.current == i + 1, "moved to the next spare thread");
    }
    check(s.stopped && !due(s, 7, 20000), "stopped with no spare left");
    check(s.last_error == "[process_lua_function] no instance", "the last error is kept");
    std::string status = status_text(s);
    const std::string n = std::to_string(SimOverhaulGamePump::SPARES);
    check(status.starts_with("stopped, thread " + n + " of " + n) && status.find("ue4ss errors " + n) != std::string::npos,
          "status line");

    // A thrown non-std exception is a UE4SS error too.
    FakeLua more[SimOverhaulGamePump::SPARES]{};
    State& t = *fresh(more);
    run_tick(t, 1000, [](FakeLua&) { throw 42; });
    check(t.escapes == 1 && t.current == 1, "any exception spends the thread");
    run_tick(t, 2000, [](FakeLua& l) { ++l.calls; });
    check(more[1].calls == 1 && t.ticks == 1, "and the next tick runs on the spare");

    std::printf(failures ? "%d failure(s)\n" : "game pump: all checks passed\n", failures);
    return failures ? 1 : 0;
}
