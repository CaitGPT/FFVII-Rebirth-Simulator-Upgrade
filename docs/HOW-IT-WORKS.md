# How Simulator Upgrade works

Simulator Upgrade is one UE4SS Lua mod (`SimulatorUpgrade`) built from five parts, a native helper mod
(`SimulatorUpgradeNative`) and one pak. Each part has its own document, with what it does, how, what was seen in the
game and the dead ends.

| Part | Document | In short |
| --- | --- | --- |
| Stages | [workstreams/stages.md](workstreams/stages.md) | Simulator Stages 1.3.0, adapted to the shared folder and settings; its native helper loads a stage's levels beside the simulator |
| Custom Training | [workstreams/custom-training.md](workstreams/custom-training.md) | A course row in the simulator's tables, a native search for its enemy-wave slots, spawning and replacing opponents through the game's reinforcement waves, behaviours by status effects and HP holds, the difficulty override |
| Zack and Sephiroth | [workstreams/party.md](workstreams/party.md) | One value on the course row, `ExtendedSequenceBits = 6`, which adds both to the team screen |
| Equipment | [workstreams/equipment.md](workstreams/equipment.md) | Opens the game's own main menu from the simulator's screens on F3 or pad Start, and adds an entry to the simulator's key guide |
| Meters | [workstreams/meters.md](workstreams/meters.md) | Training Dummy's and Battle Meters' meters in one panel, fed by HP reads and, through the native helper, the game's hit events |
| Settings menu | [workstreams/ui.md](workstreams/ui.md) | Custom Training's settings in the game's own choice window, driven by its own cursor and confirm |

## One mod from five parts

`tools/integrate/build_mod.py` copies every part's scripts into `SimulatorUpgrade/Scripts/`, renames each part's
`main.lua` to `<part>_main.lua`, joins their settings into one `settings.txt`, and writes a `main.lua` that sets
`SIM_OVERHAUL_DIR` and starts each part in turn under `pcall`, so one failing part leaves the others running. The
rules the parts follow so this works without edits (folder, module and file names, settings prefixes, how parts find
each other, keys, start-up quiet time) are in [COORDINATION.md](COORDINATION.md), "The integrated mod".

The parts talk through small Lua modules rather than files: `ct_api` (Custom Training's state, lists and changes),
`meters_api` (the meters' commands) and `equipment/api`. In a development install, where each part is its own UE4SS
mod, the same calls go through files in the parts' folders.

## The pak

`SimulatorUpgrade_9200_P` replaces the simulator's `Colosseum`, `EnemyTerritory` and `ColosseumPositionData` tables
with the game's own plus Custom Training's course, its territory and its position. Being numbered 9200, it wins over
lower-numbered paks that replace the same tables, which hides their courses. For Junon Colosseum players,
`SimulatorUpgrade_JunonCompat_9200_P` is built on Junon Colosseum's own tables instead, so its courses stay.

## Native helpers

- `SimulatorUpgrade/dlls/main.dll`: Simulator Stages' level loader, unchanged from its 1.3.0 release.
- `SimulatorUpgradeNative/dlls/main.dll` (`native/overhaul/`): Custom Training's wave-slot search and difficulty
  override, and the meters' hit-event reader, in one DLL. Both register their functions for the Lua mod named
  `SimulatorUpgrade`.

Each checks the game code it relies on before use and switches itself off if it does not recognise it.
