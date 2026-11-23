> Kept for the record: the first live checks as planned on 16 November 2026. What happened is in
> [LIVE-RESULTS.md](../LIVE-RESULTS.md).

# First live checks

Nothing in this mod has run in the game. These checks go in order: each one decides whether the next is worth doing.
A pass is an observed result (a position read, a screenshot, a log line), not a call that returned.

## Set-up

- Dev install: copy `ue4ss/SimulatorStages` to the game's `ue4ss/Mods/`, add `SimulatorStages : 1` to `mods.txt`
  above `Keybinds : 1`, and put an empty `dev.txt` in the mod folder (it turns on `stages-log.txt`).
- A save beside Chadley in the Corel region with a simulator course available. Corel's arena is the flattest. Save in
  front of the test first, to the designated test slot.
- Checks 0 to 11 are for the move route: `settings.txt` gets `route = move`, `force_stage = corel`,
  `picker = off`, and `require_unlock = false` unless the save has finished
  Corel's classified intel. If it hasn't, expect the Tonberry King to be in the arena (check 6). The picker gets its
  own checks (12 to 14) once the stage itself works.

## Checks

| # | Question | `steps` | How | Pass |
| --- | --- | --- | --- | --- |
| 0 | Does the mod load and see a course confirmed? | (any) | Start a course | `loaded` and `confirm <course key> corel forced` in the log |
| 1 | Does the simulator appear at the arena? | `relocate` | Read the leader's position once the round starts | Within 2 m of (150858, 40601, 936): the arena centre plus the party's 5.9 m start offset |
| 2 | Is the region's terrain there and visible? | `relocate,unhide` | Screenshot at fade-in and 5 s later | Ground and surroundings drawn, no fall, no pop-in after fade-in |
| 3 | Is the simulator's look gone, and do feet meet the ground? | `relocate,unhide,dressing` | Screenshot; compare the leader's z with the ground | No floor prop, blocks, cubes or spotlights; feet within 10 cm of the ground. Otherwise set `lift_cm` |
| 4 | Is the sky the region's? | all four | Screenshot | Daytime Corel sky, not the simulator's |
| 5 | Does a fight work? | all four | Fight one round to the result screen, leave | Enemies spawn, approach and attack; result screen; back at Chadley; `restore … target restored` in the log |
| 6 | Does anything local join in? | all four | Watch the enemy list and the log during check 5 | Only the course's enemies; no wildlife, camp or boss |
| 7 | Does it work a second time, and does `enabled = false` give the normal simulator after? | all four | Two more courses | Second visit as good as the first; the vanilla course untouched |
| 8 | Arriving from far away | all four | Start the Corel stage from Gongaga or Nibelheim | Terrain loaded before fade-in |
| 9 | The hard cases | all four | A summon course (entrance cut), a Mu round, a multi-round course, a round with a flyer | Each plays as in the normal simulator |
| 10 | The other five arenas | all four | One round in each, east ones from the east | As checks 2 to 6. Quetzalcoatl's is the uneven one |
| 11 | Cost | all four | Frame times on arrival and in the fight | No stall over 50 ms from the mod's own work after the black screen |
| 12 | Is a course recognised by its title, in English and one other language? | (any) | Select several courses; switch the game's language and repeat | `select <course key> …` for each, none `unrecognised` |
| 13 | Does the picker open on a selected course and return the pick? | `picker = select` | Select a course, pick a stage, confirm | The game's choice window lists the right stages; `choice <key> <stage>` in the log; the game's own confirmation still works; controller and keyboard both |
| 14 | Is the pick remembered? | `picker = select` | Leave, come back, select the same course | The window starts on the remembered stage; confirming without picking uses it; `choices.txt` holds it |

## Streamed stages (the default route)

These need the helper built (`tools/Build-Native.ps1`, not while another session has the game) and installed as
`Mods/SimulatorStages/dlls/main.dll`. Start with the smallest stage.

| # | Question | How | Pass |
| --- | --- | --- | --- |
| S0 | Does the helper start and pass its checks on this game build? | Load a save; read `stages-helper.txt` | `ready 1`, `tick` moving; `level helper ready` in UE4SS.log; no `SS-BUILD` or `SS-LOADER` line |
| S1 | Does one level load at a position? | `force_stage = white_void`, any course | `stages-ack.txt` says `loaded` for each level; `stream ready` in the log; no crash on arrival or on leaving |
| S2 | Is the stage where the fight is, at the right height? | Screenshot; leader's feet against the floor | The white floor under the party; otherwise correct the stage's `anchor` z or `lift_cm` |
| S3 | Is the lighting and sky right? | Screenshot | The stage's own look, not the simulator's; record which sky level is the white one |
| S4 | Does it unload cleanly, and work again? | Leave; start another course on the simulator's stage, then the white void again | Normal simulator in between; second visit as good as the first; memory back down |
| S5 | A terrain stage: does `MassiveEnvironment` terrain follow the offset? | `force_stage = nibel` (133 MB) | The arena's ground and rocks drawn around the fight, lit; record load time |
| S6 | The uneven one | `force_stage = space_rock` | The rock under the party; note where feet and floor disagree |
| S7 | From the other continent | Corel's arena from the Grasslands | As good as from the west |
| S8 | Each other stage, smallest first | One round each | Scenery right; record load time and which levels can be dropped |
| S9 | Cost | Memory and frame times on the heavy stages (Junon, Temple) | No stall after the black screen; decide what to trim |

If S1 crashes or hangs on arrival, the request met the simulator's own load: have the helper wait for the simulator
to finish (serve only once the game is inside), or request at arrival instead of at confirmation. If S5 shows the
levels loaded but no terrain, the massive-environment system ignores the instance's offset: the fallback for
open-world stages is `route = move`, and for dungeon stages a different way of placing them has to be found.

## If a check fails

- **1 fails with the simulator at its usual place.** The game read `TargetLocation` before our write. Try, in order:
  write it when the mod loads; call `EnableStreamingVolume(false)` then `(true)` after writing; unload the stage
  level's stream so the next visit builds it again. If none works, the position is fixed in the level file and the
  route becomes an edited `WorldPlan` level in an archive (one position per continent per archive, or added volumes).
- **1 fails with the write refused** (`target not accepted`). Set `TargetLocation.X/.Y/.Z` one by one, or write the
  three floats through the native route.
- **2 fails (terrain hidden).** List the volume's `HideLevelsInstead` entries that are still hidden and show their
  streaming levels directly.
- **2 fails (terrain not loaded).** The world did not stream around the arena. Limit a stage to courses started in its
  own region, or warp the party near the arena first, as fast travel does.
- **3 fails (flat collision in the way on slopes).** Turn off the stage's three collision actors and let the party
  stand on the real ground; then recheck that enemies still path.
- **5 fails (enemies do not move).** The simulator's navigation is baked at its usual place. Check which navigation
  the arena offers in battle, and whether the stage's `EndNavModifierVolume`s matter.
- **6 fails.** Hide or switch off the local territory for the visit and restore it after.
- **12 fails.** Log the title the menu gives and what `GetString` returns for the course's text id; match on the
  tab and cell index instead if titles can't be trusted.
- **13 fails (the window clashes with the game's confirmation).** Use `picker = key` (F7 on the highlighted course),
  or show the stage on the course's info panel and cycle it there.

## Evidence to keep

`stages-log.txt`, a screenshot per check, the leader's position per round, and any crash report. Outside Git, under
`D:\FF7RebirthModding\Mods\SimulatorStages\`.
