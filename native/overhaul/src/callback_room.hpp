#pragma once
// Room in UE4SS's ProcessEvent callback lists, made before anything registers (docs/workstreams/lua-state.md, "Callback
// lists"). UE4SS 3.0.1 keeps each hook's callbacks in a std::vector (Hook::StaticStorage), registers with an unlocked
// emplace_back and walks the vector with a range-for on the game thread. Our meters part and game pump both register a
// ProcessEvent pre-callback in on_unreal_init, after UE4SS has installed its hook: if the list is full then, it moves to
// a new buffer and frees the old one while the game thread may be walking it.
//
// SimulatorUpgradeNative's constructor runs in UE4SS's start_cpp_mods, before any hook is installed, so the lists are
// empty and nothing walks them: reserving room for 256 there means no later registration (ours, other C++ mods', Lua
// mods' first ExecuteInGameThread) ever moves them. UE4SS 1.005 Fix 1.1.1 does the same for all 27 lists; whichever runs
// first does the work and the other finds the room already there. A list that already holds callbacks is left alone.
//
// The vectors are UE4SS.dll exports, looked up by decorated name. Both modules use the shared CRT heap (/MD), so UE4SS
// frees our buffer correctly; every std::function is 64 bytes, so an empty list is reserved exactly as UE4SS's own type
// would be.
#include <Windows.h>

#include <functional>
#include <string>
#include <vector>

namespace SimulatorUpgradeCallbackRoom
{
    constexpr size_t ROOM = 256;

    inline const char* const LISTS[] = {
        "?ProcessEventPreCallbacks@StaticStorage@Hook@Unreal@RC@@2V?$vector@V?$function@$$A6AXPEAVUObject@Unreal@RC@@PEAVUFunction@23@PEAX@Z@std@@V?$allocator@V?$function@$$A6AXPEAVUObject@Unreal@RC@@PEAVUFunction@23@PEAX@Z@std@@@2@@std@@A",
        "?ProcessEventPostCallbacks@StaticStorage@Hook@Unreal@RC@@2V?$vector@V?$function@$$A6AXPEAVUObject@Unreal@RC@@PEAVUFunction@23@PEAX@Z@std@@V?$allocator@V?$function@$$A6AXPEAVUObject@Unreal@RC@@PEAVUFunction@23@PEAX@Z@std@@@2@@std@@A",
    };

    using AnyCallbacks = std::vector<std::function<void()>>;
    static_assert(sizeof(std::function<void()>) == 64);

    // Returns a short status line for the log.
    inline std::string make_room()
    {
        HMODULE ue4ss = GetModuleHandleW(L"UE4SS.dll");
        if (!ue4ss) return "callback room: UE4SS.dll not loaded";
        int reserved = 0, already = 0, busy = 0, missing = 0;
        for (const char* name : LISTS)
        {
            auto* v = reinterpret_cast<AnyCallbacks*>(GetProcAddress(ue4ss, name));
            if (!v) { ++missing; continue; }
            if (v->capacity() >= ROOM) { ++already; continue; }
            if (!v->empty()) { ++busy; continue; }
            v->reserve(ROOM);
            ++reserved;
        }
        return "callback room: " + std::to_string(reserved) + " reserved, " + std::to_string(already) + " already had room, " +
               std::to_string(busy) + " not empty, " + std::to_string(missing) + " not found";
    }
} // namespace SimulatorUpgradeCallbackRoom
