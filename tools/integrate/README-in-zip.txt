Simulator Upgrade {version} for FINAL FANTASY VII REBIRTH (PC, game version 1.005)

Needs RE-UE4SS FF7R (UE4SS 3.0.1) with a fix for game version 1.005.

Install: close the game and extract this zip into the game folder, the one that holds End. If
End/Binaries/Win64/ue4ss/Mods/mods.txt lists SimulatorUpgrade or SimulatorUpgradeNative with ": 0", change it to 1.

Junon Colosseum players: copy the three files from JunonCompat/End/Content/Paks/~mods into End/Content/Paks/~mods and
delete the three SimulatorUpgrade_9200_P files there. Never keep both.

Training Dummy is replaced by Custom Training: remove it. Remove the standalone Simulator Stages mod too; it is
included.

Uninstall: delete End/Binaries/Win64/ue4ss/Mods/SimulatorUpgrade, .../SimulatorUpgradeNative and the
SimulatorUpgrade_*_9200_P files in End/Content/Paks/~mods.

Keys: F3 or pad Start on the simulator's menus opens the main menu for equipment. In Custom Training, F7 or LB + RB
opens its settings; F9, F5, F6 and F8 control the meters. Settings are in SimulatorUpgrade/settings.txt.

Source, full readme and known issues: https://github.com/CaitGPT/FFVII-Rebirth-Simulator-Upgrade
This mod was built by an AI coding agent (Claude, in Claude Code). It is an unofficial fan project, not affiliated
with or endorsed by Square Enix.
