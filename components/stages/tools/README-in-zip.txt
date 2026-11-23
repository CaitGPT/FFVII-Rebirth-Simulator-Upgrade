Simulator Stages for FINAL FANTASY VII REBIRTH - v{version}
==========================================================

Fight Chadley's Combat Simulator courses on other stages. Select a course and the
game's own choice window asks you to choose a stage:
  Edge of Creation       - the rock platform among floating rocks in space
  Inside the Lifestream  - the silver water under a starry sky
  Gilgamesh's Garden     - the garden of Gilgamesh's legendary trials
  Mythril Mine           - where the Mythril Golem is fought
  Cave of the Gi         - where Gi Nattak is fought
  Shinra Manor           - the basement where the Galian Beast is fought
  Midgar Outskirts       - outside Sector 5's wall, where Zack fights in the prologue
  Temple of the Ancients - the Red Dragon's hall, as in that fight's second phase
The first two are from the final battle and unlock once you have finished the
game; Gilgamesh's Garden once his quests are complete; Midgar Outskirts from the
start; the other four as the story reaches them. (Spoiler note: the stages come from the story.)
A stage is offered only for courses whose enemies have room on it.
The choice is remembered for each course, and the first row, "Replay: <stage>",
brings back the last stage you picked.

TO UPDATE from an earlier version, extract over the old folder.

REQUIRES: game version 1.005 (tested on the Epic Games Store version) and
RE-UE4SS FF7R (UE4SS 3.0.1) with a fix for 1.005, such as our UE4SS 1.005 Fix:
  https://www.nexusmods.com/finalfantasy7rebirth/mods/2521

LINUX / STEAM DECK / STEAM MACHINE (Proton): 1.3.0 changes how the mod's native
helper starts, after a crash at start-up on Proton with 1.2.0. We cannot test
Proton ourselves yet. UE4SS needs the Steam launch option
  WINEDLLOVERRIDES="dwmapi=n,b" %command%
If the game still crashes, please send us SimulatorStages/stages-helper-trace.txt
and your UE4SS log.

INSTALL
1. Close the game.
2. Extract this zip into your game folder (the one that contains "End").
   This places End/Binaries/Win64/ue4ss/Mods/SimulatorStages/
3. If End/Binaries/Win64/ue4ss/Mods/mods.txt lists "SimulatorStages : 0",
   change it to 1. Otherwise the included enabled.txt turns the mod on.

SETTINGS: SimulatorStages/settings.txt (picker on select or F7, unlocks, on/off).
UNINSTALL: delete the SimulatorStages folder. Nothing is written to your save.

Built and tested by an AI (Claude, in Claude Code); the channel owner set the
design and playtested it.

Nexus page (requests welcome in the Posts tab):
  https://www.nexusmods.com/finalfantasy7rebirth/mods/2529
Full guide, known issues, how it was built, and source code:
  https://github.com/CaitGPT/FFVII-Rebirth-Simulator-Stages
YouTube channel:
  https://www.youtube.com/@Cait-GPT
