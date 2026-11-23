# FFVII Rebirth Simulator Upgrade

A FINAL FANTASY VII REBIRTH PC mod for Chadley's Combat Simulator. You can change equipment without leaving it, a
Custom Training course lets you fight any opponent the way you want, and the stages from our Simulator Stages mod are
included.

An AI coding agent built this mod: Claude (Anthropic), in Claude Code, did the research, wrote the code and tested it
in the game through a test harness. The channel owner set the design. [How it works](docs/HOW-IT-WORKS.md), [how we built it](docs/HOW-WE-BUILT-IT.md) (dead ends
included) and each part's notes in [docs/workstreams/](docs/workstreams/).

## What it adds

- **Equipment inside the simulator.** On the course list, the stage picker, the team screen and "Begin challenge?",
  **F3**, or **Start** on a pad, opens the game's own main menu: Materia & Equipment, Combat Settings, Party and the
  rest. Close it and the simulator is where you left it. An "Equipment" entry in the simulator's key guide shows the
  button. Once a course has started it does nothing: equipment changes mid-fight are not supported.
- **Custom Training**, a course on the Combat Training tab:
  - **Any opponent**: 206 of the game's enemies and bosses, grouped as the enemy book groups them (Humans, Machines,
    Beasts, Anomalies, Summons and others) and named in the game's language.
  - **One to three copies** of any opponent, or a **mixed group** of up to three different opponents.
  - **Or a pre-built round**: pick any course from the simulator's own tabs, then one of its rounds, and fight that
    round's enemies and reinforcement waves under the behaviour and difficulty you chose.
  - **Behaviour**:
    - **Passive**, for trying things out: enemies are held still, and everything refills, their HP and your HP and
      MP.
    - **Aggressive**, for real practice: enemies fight and nothing refills, on either side. You keep Auto-Life, so a
      knockout raises you and the fight goes on. Enemies stay dead: when they're all down, respawn the same fight
      (a key, or Respawn in the settings menu) or pick another.
    - **Healing**: enemies are held and your party is held at 1% HP, for healing practice.

    The course runs until you leave it.
  - **Difficulty**: Easy, Normal, Dynamic or Hard, whatever your game is set to.
  - **Change anything mid-course**: **F7**, or **LB + RB** together on a pad in a fight, pauses the game and opens a
    settings menu in the game's own choice window. Pick new opponents or a round, a behaviour or a difficulty and
    Apply: the old enemies leave at once and the new ones appear, standing on the floor and spaced apart. Ailments
    and debuffs come off the party. Respawn, the menu's first row (or **F4**), brings the same fight back, after a
    clear or to start it over.
  - **Any stage**: Custom Training can be fought on every Simulator Stages stage. On a smaller stage, opponents and
    rounds that need more room are marked "needs a larger stage" in the menu and can't be picked there.
  - **Zack and Sephiroth**: the team screen offers all nine characters, Zack and Sephiroth after the party.
- **Meters** in Custom Training: damage per second, damage taken per second and healing per second, with a row per
  character, the last five seconds, totals and the biggest hit, and in Aggressive the wave number and the last clear
  time. The behaviour picks the meter at the start; F9 cycles
  it, F5 clears it, F6 resets stagger and F8 shows or hides the panel. On a pad, the settings menu has Meter, Clear
  meter and Reset stagger rows.
- **Simulator Stages.** Fight a course on a stage from elsewhere in the world: the final battle, Gilgamesh's Garden,
  the prologue's Midgar Outskirts and four story boss arenas, each unlocked as the story reaches it. See
  [Simulator Stages](https://github.com/CaitGPT/FFVII-Rebirth-Simulator-Stages) for the stages and their limits.
  **Spoiler note:** the stage names come from the story, the final battle included.

Nothing is written to your save.

## Keys and buttons

| Where | Keyboard | Pad | Does |
| --- | --- | --- | --- |
| Course list, stage picker, team screen, "Begin challenge?" | F3 | Start | the game's main menu, for equipment |
| Course list | F7 (only with `stages_picker = key`) | – | the stage picker for the highlighted course |
| Custom Training, in a fight | F7 | LB + RB together | the settings menu (F7 again closes it) |
| Settings menu | arrow keys, Enter, Esc or Backspace | D-pad, A, B | move, choose, back |
| Custom Training | F4 | Respawn in the settings menu | the same fight again |
| Custom Training | F9, F5, F6, F8 | through the settings menu | next meter, clear, reset stagger, show or hide |

**Download:** [Nexus Mods](https://www.nexusmods.com/finalfantasy7rebirth/mods/2548) or [GitHub releases](https://github.com/CaitGPT/FFVII-Rebirth-Simulator-Upgrade/releases).

## Requirements

- FINAL FANTASY VII REBIRTH for PC, game version **1.005**. We test on the Epic Games Store version; the release build was also checked on Steam.
- [RE-UE4SS FF7R](https://www.nexusmods.com/finalfantasy7rebirth/mods/267) (UE4SS 3.0.1) with a fix for game version
  1.005. We tested with our [UE4SS 1.005 Fix](https://www.nexusmods.com/finalfantasy7rebirth/mods/2521).
- The mod includes two small native helpers built for that UE4SS: the stage loader from Simulator Stages, and one for
  Custom Training and the meters (it finds the course's enemy slots, sets the difficulty and tells who dealt each
  hit). Each checks the game code it relies on and switches itself off if it does not recognise it. Without them,
  stages are not offered, Custom Training offers 16 opponents at the course's own difficulty, and the meters count
  hits without saying who dealt them.

## Install

1. Close the game.
2. Extract the release zip into the game folder, the one that holds `End`. It adds:
   - `End/Binaries/Win64/ue4ss/Mods/SimulatorUpgrade/` (the scripts, the stage loader, `settings.txt`);
   - `End/Binaries/Win64/ue4ss/Mods/SimulatorUpgradeNative/` (the other native helper);
   - `End/Content/Paks/~mods/SimulatorUpgrade_9200_P.pak`, `.ucas` and `.utoc` (the Custom Training course).
3. If `End/Binaries/Win64/ue4ss/Mods/mods.txt` lists either mod with `: 0`, change it to `1`. Otherwise the included
   `enabled.txt` files turn them on.
4. **Junon Colosseum players**: use the three `SimulatorUpgrade_JunonCompat_9200_P` files from the zip's `JunonCompat`
   folder instead of `SimulatorUpgrade_9200_P`, never both. They keep Junon Colosseum's courses. Junon Colosseum's
   tables also carry Training Dummy's three courses, so those show, as they already do with Junon Colosseum.

### Other mods

- **Simulator Stages**: included. If the standalone mod is still installed and enabled, it handles the stages and this
  mod's copy stays off. Removing the standalone mod is cleaner.
- **Training Dummy**: replaced by Custom Training's Passive, Aggressive and Healing. Remove it. Left installed, nothing
  breaks, but its courses are hidden.
- **Battle Meters**: keep it for fights outside the simulator. Version 1.2.0 steps aside during Custom Training, so only
  one panel shows. Beside an older version, this mod's panel moves to the top right to stay clear of it.
- Other mods that replace the simulator's `Colosseum`, `EnemyTerritory` or `ColosseumPositionData` tables: the
  highest-numbered pak wins, so either their courses or ours are hidden.

## Uninstall

Close the game and delete the two mod folders and the three `SimulatorUpgrade_9200_P` files (or the JunonCompat ones).

## Settings

`SimulatorUpgrade/settings.txt` holds every part's settings, each with a note. The ones players change most:

| Setting | Default | What it does |
| --- | --- | --- |
| `stages_picker` | `select` | `key`: the stage picker opens only on F7; `off`: never |
| `ct_respawn_key` | `F4` | the key that brings the same fight back |
| `ct_auto_respawn` | `off` | `on`: in Aggressive, a cleared fight comes back by itself |
| `equipment_key`, `equipment_pad_button` | `F3`, `Gamepad_Special_Right` (Start) | the equipment keys; `off` for none |
| `equipment_course_flow` | `course_list` | `after_course`: only once a course is chosen; `off`: never |
| `ui_menu_key`, `ui_chord` | `F7`, `on` | the settings menu's key, and LB + RB on a pad |
| `meters_next_key`, `meters_clear_key`, `meters_stagger_key`, `meters_toggle_key` | `F9`, `F5`, `F6`, `F8` | the meters' keys |
| `meters_x`, `meters_y` | placed for you | where the meters panel sits, on a 1920x1080 screen |

Restart the game after editing.

## Known issues

<!-- Keep this list in step with the release notes; remove items as they are fixed. -->
- **Crashes inside UE4SS.** UE4SS 3.0.1 keeps its Lua states in a table that isn't safe to grow while another thread
  reads it. When several Lua mods send work to the game thread, a load or fast travel can occasionally crash the game
  or stop a Lua mod. This mod sends its game-thread work through one scheduler, so it rarely touches that table, but
  other installed mods still can. Our UE4SS 1.005 Fix, version 1.1.0 or later, fixes it in UE4SS for every mod. If
  the game still crashes, tell us which mods you had installed.
- **No equipment changes mid-fight.** Changing gear in a fight leaves the fighters in a T-pose, so the mod offers
  equipment only before a course starts. We are looking into it for a later version.
- **Game updates.** An update can change the code the native helpers rely on. They then switch themselves off until we
  update the mod.
- Don't use UE4SS hot reload (Ctrl+R): it crashes this game.

## Build from source

This repository contains no game files.

- **Parts.** Each part is a UE4SS mod under `ue4ss/` (`SimOverhaulStages`,
  `SimOverhaulCustomTraining`, `SimOverhaulEquipment`, `SimOverhaulMeters`, `SimOverhaulUI`), with its doc in
  `docs/workstreams/`. [docs/COORDINATION.md](docs/COORDINATION.md) gives the rules they follow to share one mod.
- **The mod.** `python tools/integrate/build_mod.py --stages-dll <stage loader main.dll> --native-dll <overhaul
  main.dll> --pak-dir <pak folder>` assembles it under `build/integrated`; `python tools/integrate/smoke_test.py`
  loads it offline and checks every part starts.
- **Native helpers.** C++ against the UE4SS 3.0.1 sources: `native/overhaul/`, and Simulator Stages' `native/` in
  `components/stages/`.
- **The course's pak.** `tools/custom-training/Build-CustomTraining.ps1`.
- **Tests** run offline with `lupa`: `python tests/<part>/run_tests.py`.

## Credits

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) and the FF7 Rebirth build of it on Nexus Mods
- [retoc](https://github.com/trumank/retoc), FModel and CUE4Parse, for reading the game's files
- Our [Training Dummy](https://github.com/CaitGPT/FFVII-Rebirth-Training-Dummy),
  [Battle Meters](https://github.com/CaitGPT/FFVII-Rebirth-Battle-Meters),
  [Simulator Stages](https://github.com/CaitGPT/FFVII-Rebirth-Simulator-Stages) and
  [Junon Colosseum](https://github.com/CaitGPT/FFVII-Rebirth-Junon-Colosseum), whose code and findings this mod builds
  on
- The Rebirth modding community

## Licence

The source code is MIT licensed ([LICENSE](LICENSE)). The repository contains no game files.

FINAL FANTASY VII REBIRTH and its assets belong to Square Enix. This is an unofficial fan project, not affiliated with
or endorsed by Square Enix.
