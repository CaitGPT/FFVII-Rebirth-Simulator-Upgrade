# Release check: Simulator Upgrade 1.0.0 candidate (2026-11-22, 04:33–05:00 UTC)

The build a player would get, installed and tried end to end in the game. Earlier, each part was proven in depth in its
own workstream (`docs/workstreams/`); this check covers the parts together, from the release build.

**Build:** main `57afd86`, `tools/integrate/build_mod.py --version 1.0.0` without `--dev` (no `dev.txt`). Native helper
`97D2510B…`: the DLL the gimmick-fight runs used, from the same native sources as main. Stage loader `4C0C179D…`
(Simulator Stages 1.3.0). Pak `SimulatorUpgrade_9200_P`: its inputs are unchanged since it was built. All 54 installed
files matched the build's manifest by SHA-256.

**Game:** Epic 1.005, save slot 25, harness on master `eadf5ba5`. Installed alongside: UE4SS 1.005 Fix 1.1.1, Battle
Meters 1.2.0, Training Dummy, Junon Colosseum, No Popups, Biome Randomizer.

| Check | Result |
| --- | --- |
| Start-up | ✅ "1.0.0 loaded … started: stages, ct, equipment, meters, ui"; every part `dev false`; Custom Training 206 opponents; Stages 17 stages, 79 courses (Custom Training included); meters "Battle Meters on, stands aside" |
| Entering the simulator | ✅ by Chadley's own Talk (no machine part) |
| Equipment, keyboard | ✅ F3 on the course list opened the game's main menu over the simulator; Esc back |
| Equipment, pad | ✅ Start opened it, with the pad's glyphs; B back to the course list |
| Stage picker for Custom Training | ✅ Enter on Custom Training opened **Choose a stage** with all eight stages |
| Custom Training on a stage | ✅ Midgar Outskirts, a Zu, Passive: the fight ran on the stage |
| Meters | ✅ our panel at the top left, Damage, a row per character; Battle Meters 1.2.0 stood aside (no second panel) |
| Settings menu, keyboard | ✅ F7 opened it: "Stage: Midgar Outskirts", rows Respawn, Mode, Opponent 1–3, Behaviour, Difficulty, Meter, Clear meter, Reset stagger, Apply, Cancel |
| Settings menu, pad | ✅ LB+RB; Respawn chosen with the pad brought the fight back and closed the menu |
| Respawn, keyboard | ✅ F4 brought the fight back |
| Leaving | ✅ give-up, the stage's 16 levels unloaded in the background |
| Save loads after it | ✅ 5 of 5, gameplay each time |
| Errors | ✅ no `lua_instances`, C-stack, failed-start or pump-stopped line; scheduler errors 0; native pump missing 0, errors 0; no crash report |

Not covered here (proven in the workstreams): Aggressive's rules and Auto-Life, waves and the clear notice, rounds and
mixed groups, the room marks on small stages, every opponent and the gimmick fights, the Junon compatibility pak.

One harness note: an Esc sent straight after F7 was refused by the harness ("another input action is executing"); the
menu's Esc and Backspace were proven with real presses in ui's runs.
