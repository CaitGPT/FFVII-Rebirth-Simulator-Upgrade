# Lua state lost ("no instance inside lua_instances"), 2026-11-21

Status: root cause found in UE4SS 3.0.1's source and binary; fix written and tested offline (branch `ws/lua-state`);
❌ not yet seen in game. ✅ = seen in game, 🟡 = partly, ❌ = not yet.

## What happened

At 06:46:45, about 21 minutes into a session with many UI window opens and closes, UE4SS logged:

```
[LoopAsync] [process_lua_function] The lua state '0x16c218b5408' has no instance inside lua_instances unordered map
stack traceback:
	[C]: in function 'ExecuteInGameThread'
	...\Mods\SimulatorOverhaul\Scripts\ui_main.lua:187: in function <...\ui_main.lua:181>
```

The UI stopped until the game was restarted, and the parent reports that every part stopped. The full UE4SS.log of
that session was overwritten at the 07:08 launch. The backed-up part logs (`install-backups\20261121-070756`) record
only events, so they can't show whether the other parts' loops kept running between 06:46:45 and the 06:53:18
restart.

## Root cause (UE4SS 3.0.1, git c0a8d4c, the installed `UE4SS.dll` 3f5e8d93…)

1. **`lua_instances` is a global `std::unordered_map<lua_State*, std::shared_ptr<Lua>>` with no lock**
   (`deps/first/LuaMadeSimple/src/LuaMadeSimple.cpp`). Every UE4SS Lua function (`process_lua_function`) looks up its
   calling `lua_State` in it, on whatever thread calls it: each mod's async thread, the game thread, the key-bind
   thread. Lua's own lock (UE4SS's `luauser.c`: one critical section for every Lua state in the process) is released
   while a C function runs, so nothing serialises these lookups.
2. **Every `ExecuteInGameThread` inserts into it.** `ExecuteInGameThread` calls `make_hook_state` → `Lua::new_thread`
   → `lua_newthread` plus `lua_instances.emplace`, on the calling thread. The Lua thread is unreferenced after its
   action runs, but the map entry is never erased. The map grows whenever a new address comes up, and MSVC rehashes
   it each time it passes its bucket count (8 → 64 → 512 → 1024 → …).
3. **A rehash rebuilds the bucket array while other threads read it.** A lookup during that moment sees an empty
   bucket: `contains()` is false and UE4SS throws the error above. Or it follows a stale node pointer and crashes the
   game. Disassembly: `UE4SS+0xbf4630` is `process_lua_function` (it hashes the `lua_State*` with FNV-1a, MSVC's
   pointer hash), and **`UE4SS+0xbf476c` is `cmp rbx, [rax+0x10]`, the bucket walk of `lua_instances.contains()`**.
   That address is the faulting instruction of 8 crash folders (2026-08-25 to 2026-11-20, reading 0x10, -1 or garbage;
   FFVII-Modding `docs/crash-220-ue4ss.md`, "Not this signature"). Today's error and those crashes are the same race:
   one ends as a miss, the other as a bad read.
4. **The integrated mod was the heaviest writer.** Seven loops queued game work up to about 70 times a second (UI and
   Custom Training 20/s with the menu open, the equipment pad 20/s, the equipment watcher 10/s, the meters and the
   equipment tick 5/s, Stages 4/s, the machine 0.5/s). Each call is a new Lua thread and a new map insert. Other Lua
   mods (Biome Randomizer, Junon Colosseum, Battle Meters, No Popups, Training Dummy, the exporter) read and write the
   same map from their own threads.
5. **Why it never came back:** UE4SS's `LuaMod::process_delayed_actions` starts with `bool result = true` and removes
   a `LoopAsync` whose callback throws. The UI's one loop was gone for good.
6. **Lua's `pcall` cannot catch a UE4SS error.** UE4SS raises every error as a C++ exception (`throw_error` throws
   `std::runtime_error`; it never calls `lua_error`). Its Lua is compiled as C, using setjmp/longjmp (`UE4SS.dll`
   imports `__intrinsic_setjmp` and `longjmp`). The exception unwinds past every Lua `pcall` to the nearest C++ catch:
   `process_delayed_actions` for `LoopAsync`, `RC::TRY` in the game-thread action runner (it logs and carries on). On
   the way it skips Lua's own bookkeeping: the thread's call-info chain and C-call count stay as they were. That is
   the "C stack overflow after failed member lookups" in the exporter's history: each escape leaks one of the 200
   C calls. `game.safe(...)` and the parts' `pcall` wrappers catch Lua errors only.

Why "every part" may have stopped: each part has its own loop, and one escape removes only the loop that threw. If the
other parts stopped too, either they each hit the same miss (a rehash that broke the map for longer), or the parent
saw the UI's front end go (it drives the Custom Training and meters windows). The overwritten log can't tell which.
The fix below covers both cases.

## The fix (branch `ws/lua-state`)

The parts are unchanged. The integrated build adds two pieces.

**`tools/integrate/overhaul_tick.lua`**, shipped as `Scripts/overhaul_tick.lua`. The generated `main.lua` installs
it before requiring the parts. It replaces the globals `LoopAsync` and `ExecuteInGameThread`:

- One real `LoopAsync` (the master, every 50 ms) runs every part's loop at its own interval, each in `pcall`. A Lua
  error in a part is logged (the first time, then every 100th) and that loop keeps running. A second real loop, the
  watchdog (1 s), starts a new master if UE4SS drops it (a UE4SS error inside it).
- `ExecuteInGameThread` only queues the function, in plain Lua: no Lua thread and no UE4SS call. The queue is run
  on the game thread:
  - by the native pump, when it is running;
  - otherwise by at most one real `ExecuteInGameThread` outstanding at a time. One that is queued and hasn't started
    (the game paused, or loading) is never replaced: each replacement would be one more Lua thread. Only one that
    started and never finished (a UE4SS error escaped its drain) is replaced, after 5 s. In a load (the pump ran within
    the last minute) the next one waits a second; otherwise the next one waits until the last has finished and a
    whole master tick has passed. UE4SS's `ExecuteInGameThread` does
    `luaL_ref` twice on the calling thread, and after the action `luaL_unref` on the game thread, with no lock around
    either: overlapping, they can hand one registry slot out twice, and the next action's ref is then not a function.
    UE4SS throws "Ref was not function" outside its `TRY` and the game dies (crash (a) below).
- A UE4SS error inside a queued function stops that drain where it is. The index has already moved on, so the next
  drain carries on after the function that threw. A drain left unfinished is noticed after 10 s of `os.clock` and
  taken as abandoned.
- `IsInGameThread` (the registry flag UE4SS's `LoadAsset` checks) is set around each drain, as UE4SS does around its
  own actions.
- Status: `SIM_OVERHAUL_TICK.status()`; every 30 s into `overhaul-tick.txt` on a development install; into UE4SS.log
  after a minute and then every 10 minutes.

**`native/overhaul/src/game_pump.hpp`** (logic in `game_pump_core.hpp`), in `SimulatorUpgradeNative`:

- At load it registers a ProcessEvent pre-callback, as the meters part does.
- In `on_lua_start` it makes 32 Lua threads for the mod and anchors each in the registry. These are the only map
  inserts it ever makes.
- `main.lua`'s first `ExecuteInGameThread` calls `SimOverhaulGamePumpBind()`. That first call is UE4SS's own
  game-thread action, so the bind records the thread it runs on. The pump runs on that thread only.
- At most every 40 ms it calls `SimOverhaulGameTick()` on its current thread. It skips re-entry from inside its own
  tick.
- A UE4SS error that escapes the tick spends that Lua thread, so the pump moves to the next spare. With none left it
  stops, and the Lua side goes back to real `ExecuteInGameThread` within 0.5 s. A missing tick function or a Lua
  error waits a second and retries.

Result:

| | Lua threads and map inserts made by the integrated mod | UE4SS calls from its async thread |
| --- | --- | --- |
| Before | up to ~70 a second (one per queued call) | one per queued call |
| Scheduler without the pump | at most 20 a second, none when idle | at most 20 a second |
| Scheduler with the pump | none during play | none (only rare log lines) |

The worst case in the offline test: 795 queued calls in 10 s → 200 real calls without the pump, 1 with it.

What it doesn't fix: other mods still insert into `lua_instances` and can still rehash it while one of our threads
reads it. With the pump, our threads read it only on the game thread (the pump's own calls into UE4SS functions). A
fix for every mod at once is to pre-size the map in memory at start-up, before any Lua mod starts, so it never
rehashes. That belongs with the harness exporter's IsValid fix (FFVII-Modding issue #220, PR 789) and is not done
here.

## Tests (offline) ✅

- `python tests/integrate/run_tests.py`: 16 scheduler tests against a fake UE4SS. It drops a loop that throws or
  returns true, as UE4SS does, and runs one Lua thread per game-thread action. The tests cover:
  - intervals and first runs;
  - coalescing (≤ 1 real call outstanding);
  - the pump taking over and handing back;
  - a failing part loop that keeps running;
  - FIFO order and nested queuing;
  - a UE4SS error mid-drain (a coroutine that never resumes: nothing after it runs);
  - watchdog restart;
  - the game-thread flag;
  - argument errors;
  - a real action waiting for frames (game paused) is not replaced; one stopped by a UE4SS error is;
  - a 20 s load makes about one real call a second (195 without the cap);
  - no real call until UE4SS has unref'd the last action (fails without the wait);
  - reports.
- `tests/integrate/Build-GamePumpTest.ps1`: the native pump's logic with a fake Lua. It covers:
  - classification of each failure message;
  - when it is due;
  - the re-entry guard;
  - retry after a missing function or a Lua error (stack cleared);
  - moving to each spare after a UE4SS error, and stopping when none are left;
  - the status line.
- `python tools/integrate/smoke_test.py <build>`: every part starts, and every part's loop plus the report goes
  through the scheduler.
- The part suites pass unchanged.
- `tools/meters/Build-Overhaul-Native.ps1` builds `main.dll`. All 36 of its UE4SS imports, including `call_function`,
  `new_thread`, `make_ref`, `get_stack_size`, `discard_value`, `set_string` and `RegisterProcessEventPreCallback`, are
  exports of the installed `UE4SS.dll`.

## In-game check and soak (counted in events) ✅

2026-11-21, Epic 1.005, under the game lock, with the machine part still in the build (main 73adc07; main 6bb514e has
since removed it). Evidence: `D:\FF7RebirthModding\Mods\SimulatorOverhaul\lua-state-soak\`.

**Start-up**, after each of 5 launches: `[SimulatorUpgrade] … started` with every part, then `pump on … native pump:
running, thread 1 of N, ue4ss errors 0`.

**Exporter.** The telemetry exporter ran the FFVII-Modding PR 789 build (#220 IsValid fix, 4ef86fd9, main.dll SHA-256
4F6EC5F6…; PR 787's exporter Lua unchanged). Its health file read `"ue4ss_isvalid_hotfix":"applied"`. That is not
master's build: a runtime from FFVII-Modding master (904d8aef or later) still needs deploying under the lock. The
previous DLL (4427AB48…) is in `lua-state-soak\exporter-backup-before-789`.

| Run | Build | Events | Result |
| --- | --- | --- | --- |
| 1 | 51f273e, 4 spares, old exporter | 5 UI cycles | #220 crash at 11:39:31 from the exporter (`isvalid-uobject`, `FF7RTelemetryExporter+a663`), not ours. Just before it, one `no instance inside lua_instances` on the pump's own thread, on the game thread: another mod's insert, since ours made none. The pump moved to thread 2, as designed |
| 2 | same | 25 UI cycles | clean; stopped to install the 789 exporter and 32 spares |
| 3 | a93969a (32 spares) + 789 exporter | 285 UI opens, 284 closes (200 key, 60 pad chord, 25 dev command) | clean: 0 pump errors, 0 Lua errors, `masters 1` |
| 4 | 456390e + 789 exporter | 25 Custom Training spawns (Ceasar Subspecies first), 25 stage visits, 25 fast travels | clean: all 25 spawns appeared, all 25 visits reached their fight, all 25 travels arrived; 0 pump errors, pump on thread 1 of 32 throughout, `masters 1`, `abandoned 0` |

No `lua_instances`, `C stack overflow` or `game pump stopped` line in UE4SS.log in runs 2–4, and no crash folder after
11:39.

**Found and fixed during the soak** (both seen in `overhaul-tick.txt`, both offline-tested):

- `eedae4c`: while the menu paused the game, the fallback replaced its waiting real action every 5 s, one Lua thread
  each (real 13 → 40 over 50 UI cycles). Now a waiting action is never replaced.
- `456390e`: in a load the pump stops while UE4SS keeps running its actions, so the fallback made a real call every
  other tick, about 100 Lua threads per load. Now one a second in a load: real 115 → 5 for a launch and two loads.
  Over run 4's 75 loads, about 17 a load.
- `a93969a`: 32 spare pump threads instead of 4, since other mods' inserts can spend one.

**Driver issues, not the mod's:** the harness's give-up twice missed the simulator's pause, and the visit driver twice
left the team screen open. Both were handled by hand and are noted in `stage-visits.txt`.

**Still open:** the fallback runs at every load and every pause, and each real call is one map insert. Other mods'
inserts remain too. Both need the `lua_instances` map pre-sized at start-up, for every mod, with the exporter.

### Crashes from the custom-training sweep, 2026-11-21 (`custom-training-build\crashes-2026-11-21`)

- **(a) 08:54:39, 0xe06d7363, 4 s after a Custom Training spawn.** Not #220, not the map race itself: UE4SS's
  game-thread action runner (`+4bae35`) throws `[Lua::Registry::get_function_ref] Ref was not function`
  (`+bf2e20`), which it calls outside its `TRY`. The ref is spoiled by `ExecuteInGameThread`'s `luaL_ref` on an
  async thread racing the previous action's `luaL_unref` on the game thread, the same unlocked-from-two-threads root.
  The pump removes our mod's share (no `ExecuteInGameThread` during play), and the fallback now waits for the unref.
- **(b) 10:04:20, read of 0x10 during the slot 25 load.** The `lua_instances` race (`UE4SS+bf476c`): the reader was
  FF7RTelemetryExporter's game-thread Lua call (`main+a663` from a ProcessEvent callback). The inserting thread had
  finished by the dump (every LoopAsync thread was asleep), so its mod is unknown; our seven loops were the busiest
  inserter. The soak covers our share; other mods' inserts need the pre-sized map.

## Rules for every part (the integrated mod and the development mods)

- Don't call UE4SS functions from a `LoopAsync` callback other than `ExecuteInGameThread` (and in the integrated mod,
  that one is plain Lua now). File reads with Lua's own `io` are fine: they aren't UE4SS functions.
- `pcall` doesn't protect against UE4SS errors (a missing member, a bad argument, a freed object): they skip it. Avoid
  causing them, by checking classes and members first, rather than catching them.
- Queue game work only when there is some to do. The development mods still make one Lua thread per call.

## Callback lists (branch `ws/callback-lists`)

UE4SS 3.0.1 has a second race of the same kind as `lua_instances`. Each hook's callbacks live in a `std::vector`
(`Hook::StaticStorage`, UEPseudo `Hooks.cpp`). Registering one is an `emplace_back` with no lock, and `HookedProcessEvent`
walks the vector with a range-for on the game thread.

Our meters part and our game pump both register a ProcessEvent pre-callback in `on_unreal_init`. By then the hook is
installed, so if the list is full, it moves to a new buffer and frees the old one while the game thread may be walking
it. The same happens on every Lua mod's first `ExecuteInGameThread`. Simulator Stages traced its Proton start-up crash
to this.

The fix is `native/overhaul/src/callback_room.hpp`, called from `SimulatorUpgradeNative`'s constructor. That
constructor runs in UE4SS's `start_cpp_mods`, before any hook is installed, so the lists are empty there. It reserves
room for 256 in the ProcessEvent Pre and Post lists, which it looks up by their decorated export names, and leaves any
list that is not empty alone.

UE4SS 1.005 Fix 1.1.1 does the same for all 27 lists, and Simulator Stages does it for the two ProcessEvent lists.
Whichever runs first does the work; the others find the room already there. The Fix's offline test,
`native/tests/callbacks_test.cpp` in its repo, shows that with room, 201 registrations against about 7 million walks
never move the buffer. Without room, the same test crashes with `0xC0000409`.

Built: `main.dll` SHA-256 `9B4C997DD3E521B6E920C3EE6F7D62642BE805B55B77430E8691688462E44AFC`. It has not been run in the
game yet. Its start-up line is `[SimulatorUpgradeNative] callback room: ...`, printed to the console.
