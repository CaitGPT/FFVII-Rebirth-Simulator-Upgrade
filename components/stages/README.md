# FFVII Rebirth Simulator Stages

A FINAL FANTASY VII REBIRTH PC mod that lets you fight Chadley's Combat Simulator courses on other stages. Pick a
course, choose a stage, and the fight takes place there instead of on the simulator's block arena. Eight stages are in
this version: **Edge of Creation** and **Inside the Lifestream** from the final battle, **Gilgamesh's Garden**,
**Midgar Outskirts** from the prologue, and four boss arenas from the story: **Mythril Mine**, **Cave of the Gi**,
**Shinra Manor** and the **Temple of the Ancients**.

**Spoiler note:** the stages, their names and the pictures of them come from the story, the final battle included.

An AI coding agent built this mod: Claude (Anthropic), in Claude Code, did the research, wrote the code and tested it
in the game through a test harness. The channel owner set the design and playtested it. [How we built it](docs/HOW-WE-BUILT-IT.md)
tells the story, dead ends included.

[Nexus Mods](https://www.nexusmods.com/finalfantasy7rebirth/mods/2529) ·
[Download from GitHub releases](https://github.com/CaitGPT/FFVII-Rebirth-Simulator-Stages/releases/latest)

## What it adds

- **A stage picker.** When you select a course, the game's own choice window asks you to choose a stage. The first
  option is the normal Combat Simulator. The mod remembers your choice for each course and marks it with `>` the next
  time.
- **Edge of Creation.** The rock platform, its floating rocks and the nebula sky from the final battle. The platform
  is stretched to cover the simulator's arena, a circle of about 24 m radius.
- **Inside the Lifestream.** The water floor and the starry sky from the final battle.
- **Gilgamesh's Garden.** The garden where Gilgamesh holds his legendary trials.
- **Mythril Mine.** The cavern where the Mythril Golem is fought.
- **Cave of the Gi.** The chamber where Gi Nattak is fought, lit as in that fight.
- **Shinra Manor.** The basement where the Galian Beast is fought, with its props and its floor door closed.
- **Midgar Outskirts.** The rocky ground outside Sector 5's wall where Zack fights Shinra's soldiers in the prologue,
  with its fires, fences, the plate overhead and the reactor. The downed helicopters from that fight are not included.
- **Temple of the Ancients.** The hall in the Temple's maze where the Red Dragon is fought, as in the fight's second
  phase, when gravity reverses: patterned walls on every side, the colonnade's windows and the diamond-panelled
  vault. The game stages that phase in an upside-down copy of the hall, which the stage loads, lit warmly by one of
  the hall's own lamps set inside the colonnade.
- **Which courses.** Every Combat Simulator course, including the summon courses, the Combat Training tutorials and
  the three courses our [Training Dummy](https://github.com/CaitGPT/FFVII-Rebirth-Training-Dummy) mod adds. The eight
  Shinra Manor courses are left as they are. A stage is only offered for courses whose enemies have room on it: the
  three story arenas are smaller than the simulator's arena, so the summon courses that need the most room (Phoenix,
  Alexander and Odin) offer only the larger stages (Midgar Outskirts fits Alexander and Odin, not Phoenix; the Temple
  of the Ancients fits Alexander, not Odin or Phoenix), and Shinra Manor fits only the smaller courses.
- **Unlocking.** Edge of Creation and Inside the Lifestream unlock when you have finished the game (once Chapter
  Select is open). Gilgamesh's Garden unlocks when Gilgamesh's quests are complete. Midgar Outskirts is offered from
  the start. Mythril Mine, Cave of the Gi, Shinra Manor and the Temple of the Ancients unlock as the story reaches
  them (from Chapters 4, 11, 12 and 13).
- **No invisible walls.** The simulator's own walls and pillars stop colliding on every stage, and on Midgar Outskirts and
  the four story arenas its floor goes too, so you stand on the arena's own floor and stop at its own walls.
- **No visible swap.** The stage loads behind a black screen, which lifts once it is in place. If the game starts the
  fight before then, the fight is held still until the screen lifts.
- **Replay.** The picker's first row is "Replay: <stage>", the last stage you picked, when the course can use it.

Nothing is written to your save. The mod changes no game files: it loads the stage's own levels beside the simulator
while you fight, and removes them when you leave.

## Requirements

- FINAL FANTASY VII REBIRTH for PC, game version **1.005**. We test on the Epic Games Store version. The Steam version
  needs the helper to search the game's code for what it uses; we test that search on the Epic copy.
- **Linux, Steam Deck and Steam Machine (Proton).** Version 1.2.0 crashed the game at start-up for a player on Proton.
  1.3.0 changes how the native helper starts (see the changelog). We cannot run Proton ourselves, so this is not yet
  confirmed. UE4SS itself needs the Steam launch option `WINEDLLOVERRIDES="dwmapi=n,b" %command%` there. If the game
  still crashes, please send us `SimulatorStages/stages-helper-trace.txt` with your UE4SS log.
- [RE-UE4SS FF7R](https://www.nexusmods.com/finalfantasy7rebirth/mods/267) (UE4SS 3.0.1) with a fix for game version
  1.005. We tested with our [UE4SS 1.005 Fix](https://www.nexusmods.com/finalfantasy7rebirth/mods/2521).
- The mod includes a small native helper (`dlls/main.dll`) built for that UE4SS. It loads the stage's levels, which
  UE4SS's Lua cannot do on this game. It checks the game code it relies on before acting and switches itself off if it
  does not recognise it: the game and the simulator run normally, but no picker appears.
- A save that has unlocked at least one stage (see Unlocking above).

## Install

1. Close the game.
2. Extract the release zip into the game folder, the one that holds `End`. It adds
   `End/Binaries/Win64/ue4ss/Mods/SimulatorStages/` (scripts, the native helper, `enabled.txt` and `settings.txt`)
   and a readme, licence and changelog beside `End`, which you can delete.
3. If `End/Binaries/Win64/ue4ss/Mods/mods.txt` lists `SimulatorStages : 0`, change it to `1`. Otherwise the included
   `enabled.txt` turns the mod on.

## Uninstall

Close the game and delete `End/Binaries/Win64/ue4ss/Mods/SimulatorStages`.

## How to use it

1. Talk to Chadley and open the Combat Simulator.
2. Select a course. The **Choose a stage** window opens.
3. Pick a stage, then choose your team and start as usual.

To change a course's stage later, select the course again. Choices are kept in `SimulatorStages/choices.txt`.

## Settings

`SimulatorStages/settings.txt` is read each time it is needed, so changes take effect without a restart.

| Setting | Values | What it does |
| --- | --- | --- |
| `enabled` | `true`, `false` | `false` leaves the simulator as the game ships it |
| `picker` | `select`, `key`, `off` | When to show the picker: when you select a course; only when you press F7 on a highlighted course; or never (courses use the stage last chosen for them) |
| `require_unlock` | `true`, `false` | `false` offers every stage whether or not you have finished the game |
| `experimental` | `false` | Leave off. `true` also offers the planned arena stages, which do not work yet |

The other settings in the file are for development.

## Known issues

<!-- Keep this list in step with the release notes; remove items as they are fixed. -->
- **Crashes inside UE4SS.** The game can crash with an access violation in `UE4SS.dll` (at `+0x6a8c4f`) when a Lua mod
  checks an object the game has already destroyed. We fixed every place this mod did that that we have found, and it
  also happened before this mod existed, with other mods installed. If it happens to you, tell us which mods you had.
- **Loading time.** A large stage takes a few seconds longer to load than the plain simulator, behind the black screen.
- **"Get Ready" screen that never ends.** We found and fixed one cause in the mod. The game can also stop on a black
  "Get Ready" or loading screen in its own simulator fights, without any mod. Restart the game.
- **The edge of Edge of Creation.** The platform is not round. It reaches 0.2 to 6 m past the simulator's invisible
  wall depending on direction, and along part of the south rim characters stand a little above the rock.
- **Game updates.** An update can change the code the native helper relies on. The helper then switches itself off
  and no stages are offered until we update the mod.
- Don't use UE4SS hot reload (Ctrl+R): it crashes this game.

## What is next

The design includes each region's boss arena, unlocked by beating that region's boss, and the arenas of open-world
bosses such as the Grasptropod, the Anuran Suppressor and Gilgamesh's island. They are in `data/stages.json` but do not
work yet: their ground is open-world terrain, which does not show when its level is loaded elsewhere. We also tried
the Temple of the Ancients' upper arenas (Reno and Rude, then Tseng and Elena) and left them out: parts of their floors
come from story events and did not come with them, and Reno and Rude's Lifestream sky did not either. The Red
Dragon's hall is in, as the fight's second phase: drawn as the first phase, its tall walls on two sides do not
appear. Drafts of the
Altar at the Forgotten Capital and a reactor arena were dropped as well. [How it works](docs/HOW-IT-WORKS.md) says what we tried.

## Build from source

This repository contains no game files.

- **Scripts.** The Lua mod is in `ue4ss/SimulatorStages/`. `data/stages.json`, `data/courses.json` and
  `data/mod_courses.json` describe the stages and the courses; `python tools/build_lua_data.py` turns them into
  `Scripts/stage_data.lua`. `tools/make_courses.py` rebuilds `data/courses.json` from your own export of the game's
  tables.
- **Native helper.** C++ in `native/`, built against the UE4SS 3.0.1 sources. See [native/README.md](native/README.md).
- **Release zip.** `python tools/make_release.py <version> --dll <built main.dll>`.
- **Tests** run offline: `python -m pip install lupa`, then `python tests/run_tests.py`.

## Documentation

- [How it works](docs/HOW-IT-WORKS.md): the stages, the picker, the native helper, timing, what was tested and the limits
- [How we built it](docs/HOW-WE-BUILT-IT.md): the whole story, dead ends included
- [Test log](docs/LIVE-RESULTS.md): every live session, with what was seen
- [Research](docs/research/VR-STAGE-AND-ARENAS.md): what the game's files show about the simulator and the arenas
- [Changelog](CHANGELOG.md)

## Credits

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) and the FF7 Rebirth build of it on Nexus Mods
- [retoc](https://github.com/trumank/retoc) by Truman Kilen and Archengius, and its FF7R patches, for reading the
  game's level files
- FModel and CUE4Parse, for reading the game's files
- The native helper reuses the game-thread, code-check and loader-idle parts of our
  [Junon Colosseum](https://github.com/CaitGPT/FFVII-Rebirth-Junon-Colosseum) helper
- The Rebirth modding community

## Requests

We take them. If there is a place in Rebirth you would like to fight simulator courses in (a region's boss arena, a
story boss's arena, or somewhere else entirely), say so and it goes on the list for the next stages. The same goes for
changes to this mod, or for a different mod entirely. Open an issue here, or post on the
[Nexus page](https://www.nexusmods.com/finalfantasy7rebirth/mods/2529?tab=posts). Not every place will work (the
open-world boss arenas don't yet), but we will look at each one.

## Licence

The source code is MIT licensed ([LICENSE](LICENSE)). The repository contains no game files; the mod loads the game's
own levels from your copy of the game.

FINAL FANTASY VII REBIRTH and its assets belong to Square Enix. This is an unofficial fan project, not affiliated with
or endorsed by Square Enix.
