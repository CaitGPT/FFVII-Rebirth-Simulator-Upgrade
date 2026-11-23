# Workstream: Simulator Stages in the Overhaul

Simulator Overhaul includes Simulator Stages 1.3.0: a course's fight can be held on a stage from elsewhere in the
world. `components/stages/` keeps the released component as it was (its own tools, native helper source and tests);
`ue4ss/SimOverhaulStages/` is the part the Overhaul builds from.

Changes from the release (2026-11-21):

| Change | Why |
| --- | --- |
| Modules in `Scripts/stages/` (`rules`, `data`, `game`, `session`); `main.lua` requires `stages.*` | the integrated mod shares one Lua state and one `Scripts/` folder; `game` and `session` are too generic |
| `MOD_DIR = rawget(_G, "SIM_OVERHAUL_DIR") or ...` | the integrated mod's folder |
| Settings keys carry `stages_`; other parts' lines in the shared `settings.txt` are passed over quietly | one `settings.txt` for every part |
| `choices.txt` is `stages-choices.txt` | files carry the part's prefix |
| Stands down when the standalone `SimulatorStages` mod is installed and enabled | two pickers for one fight |

The level helper (`dlls/main.dll`, the released 1.3.0 build) is unchanged. It exchanges files in the folder it is
installed in (`stages-request.txt`, `stages-ack.txt`, `stages-helper.txt`), which in the integrated mod is
`SimulatorOverhaul/`, the same folder as the scripts' `MOD_DIR`.

Keys and buttons: F7 on the simulator's course list, only when `stages_picker = key` (default `select`: the picker
opens when a course is selected). The picker is one of the game's own message windows, so the pad works in it.

Tests: `python tests/stages/run_tests.py` (the component's tests, adapted, plus one for the shared settings file).

## In the game, integrated build (2026-11-21, 14:40–15:06 UTC, main e024519, slot 25 at Costa del Sol, parent)

Entered through Chadley's talk (the machine part is gone).
- ✅ All five parts started (UE4SS.log: `started: stages, ct, equipment, meters, ui`), the scheduler and native game pump on, with no `lua_instances` or C-stack lines.
- ✅ **Keyboard**: on the course list, Up then Enter on "Combat Training: Synergy" opened **Choose a stage**, with the simulator plus eight stages. Choosing Mythril Mine by keyboard (`choose_message_window`, device keyboard) gave the black screen, which lifted 11.7 s after arrival, and the fight on the stage.
- ✅ **Pad**: after a restart, D-pad and A on COL30_CORLA_05 opened the picker. Its first row was **Replay: Mythril Mine**: the choice is kept across a restart in `stages-choices.txt`. Edge of Creation was chosen by pad and the fight ran on it with a party of three. Giving up released and unloaded its 7 levels.
- Seen, not ours:
  - Battle Meters 1.1.0's own panel shows over the black screen in ordinary courses.
  - A GPU crash (UE4CC `CrashType GPUCrash`, game frames only) on a relaunch straight after a force close.
  - The harness's give-up fails while a course's tutorial prompt holds Esc ("Synergy Skills – Esc View"), and between rounds (Get Ready).

Still to see in the game: the stand-down with the standalone mod.
