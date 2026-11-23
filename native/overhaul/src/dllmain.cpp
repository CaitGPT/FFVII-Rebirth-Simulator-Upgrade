// Simulator Upgrade Native: the release's one C++ mod (UE4SS 3.0.1), ModName SimulatorUpgradeNative. It holds every
// part's native helper, each compiled from its own unchanged source, and registers their Lua functions for the
// integrated Lua mod, SimulatorUpgrade:
//   native/custom-training  Custom Training's difficulty and wave helper (CustomTraining* functions)
//   native/meters           the meters' hit events, a copy of Battle Meters Native (SimOverhaulMeters* functions)
//   game_pump.hpp           the game-thread pump that runs every part's ExecuteInGameThread work without a new Lua
//                           thread each time (SimOverhaulGamePump* functions, docs/workstreams/lua-state.md)
//
// Each part's source is included whole, with SIM_OVERHAUL_COMBINED defined: each then registers its functions for
// SimulatorUpgrade only (not its development mod), and its own start_mod/uninstall_mod exports are renamed below, so
// the only real entry points are this file's. The wrapper owns one instance of each part's mod and forwards the two
// events they use, on_unreal_init and on_lua_start.
//
// Battle Meters' own BattleMetersNative can run beside this: each registers its own ProcessEvent callback and fills its
// own queue, read only by its own Lua mod, so nothing is counted twice.
//
// SIM_OVERHAUL_COMBINED_TEST (a development build only): the meters part also registers for its development mod,
// SimOverhaulMeters, and Custom Training's part registers nowhere, so the combined DLL can be tried in the game
// beside the parts' development mods without touching Custom Training's.
#define SIM_OVERHAUL_COMBINED 1

#define start_mod custom_training_start_mod
#define uninstall_mod custom_training_uninstall_mod
#include "custom-training/src/dllmain.cpp"
#undef start_mod
#undef uninstall_mod

#define start_mod meters_start_mod
#define uninstall_mod meters_uninstall_mod
#include "meters/src/dllmain.cpp"
#undef start_mod
#undef uninstall_mod

#include "callback_room.hpp"
#include "game_pump.hpp"

namespace SimulatorUpgradeNative
{
    class Mod : public RC::CppUserModBase
    {
        CustomTrainingNative::Mod m_custom_training;
        SimOverhaulMetersNative::Mod m_meters;
        SimOverhaulGamePump::Pump m_pump;

    public:
        Mod()
        {
            ModName = STR("SimulatorUpgradeNative");
            ModVersion = STR("0.1.0");
            ModAuthors = STR("CaitGPT");
            ModDescription = STR("Simulator Upgrade's native helpers: Custom Training's difficulty and waves, the meters' hit events, the game-thread pump");
            // Before any hook is installed: room in UE4SS's ProcessEvent callback lists (callback_room.hpp).
            printf_s("[SimulatorUpgradeNative] %s\n", SimulatorUpgradeCallbackRoom::make_room().c_str());
        }

        void on_unreal_init() override
        {
            m_custom_training.on_unreal_init();
            m_meters.on_unreal_init();
            m_pump.on_unreal_init();
        }

        void on_lua_start(StringViewType mod_name, RC::LuaMadeSimple::Lua& lua, RC::LuaMadeSimple::Lua& main_lua,
                          RC::LuaMadeSimple::Lua& async_lua, std::vector<RC::LuaMadeSimple::Lua*>& hook_luas) override
        {
#ifndef SIM_OVERHAUL_COMBINED_TEST
            m_custom_training.on_lua_start(mod_name, lua, main_lua, async_lua, hook_luas);
#endif
            m_meters.on_lua_start(mod_name, lua, main_lua, async_lua, hook_luas);
            m_pump.on_lua_start(mod_name, lua);
        }
    };
}

extern "C"
{
    __declspec(dllexport) RC::CppUserModBase* start_mod() { return new SimulatorUpgradeNative::Mod(); }
    __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
}
