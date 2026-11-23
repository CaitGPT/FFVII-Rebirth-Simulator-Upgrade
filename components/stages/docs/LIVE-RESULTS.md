# What has been seen in the game

Newest first. Each line is something observed, with where the evidence is. Screenshots and logs are outside Git, in
`D:\FF7RebirthModding\Mods\SimulatorStages\evidence\`.

## 2026-11-19/20: the helper for Proton, and the Red Dragon's hall (1.3.0)

- **The Proton crash (player report, Steam 1.005 on CachyOS with Proton, UE4SS c0a8d4c + our 1.005 fix, no other
  mods).** Three logs: each stops 1 to 87 ms after the helper's `level helper ready`, before any of the mod's Lua runs,
  with no crash dump. The player's console settings were already off; the built-in UE4SS mods were not the cause
  (the crash came with them disabled too). Under Proton the image loads at 0x140000000 and UE4SS is ready 3.5 s after
  launch (about 18 s on Windows). Not reproduced on Windows: the player's exact setup on the Epic copy (community
  `mods.txt`, our fix, 1.2.0) and a helper forced onto the Steam copy's search path both started normally.
- **What changed in the helper (1.3.0):** the code checks and the Steam search run once in `on_unreal_init`, on UE4SS's
  thread, under `__try`; the game-thread callback does nothing until 10 s after that; log lines from the game thread are
  queued and written from `on_update`; `QwordsEqual` reads only committed, readable pages of readable sections, under
  `__try`; every start-up step goes to `stages-helper-trace.txt`. Live on the Epic copy: the search build
  (`BA45CB69...`) found both by pattern in 250 ms on UE4SS's thread, armed 10 s later, and streamed Midgar Outskirts
  (16 levels, in 5.2 s, 40 s of combat); the release build (`BA1AF389...`) recognised `epic-1.005` from its table and
  armed 10 s later. Proton itself is untested.
- **Temple of the Ancients, the Red Dragon's hall (issue 3).** Territory `TEMPL_RedDragon` at (-33380, -72720, -7290).
  The game's own volume for the fight, `3110-StreamingVolume_Env_MazeRoomA_Boss`, 4 m away, loads the eight
  `025_RedRoomA` levels, and its physics volume adds `RedRoomA_Physics` and `RedRoomB_Physics`. The fight's scenes
  (EV_FOREE_8020, 8090: "VS Red Dragon") use the `TimeSet_Maze` switch; the maze's scenes use `IslandSky_DayMaze`.
  - First load at the territory's height: the view went white. The party had fallen 46 m (the simulator's floor is off
    on a stage with its own ground) and the room's meshes were 50 m above it. With the maze's height fogs hidden it was
    black: nothing around. The room's floor is at -2320 (its gimmick pieces sit at -2318), not at the marker.
  - At -2320: the paved hall, the colonnade, walls and the sun's shafts through the columns (`rd-4.png`). The capsule
    probe found floor within 15 cm of the simulator's height over about 40 m by 45 m; walls at 19 m (north) to 33 m.
    Centred 0.8 m east and 4.5 m south of the marker, the nearest wall is 22.3 m away in 24 directions: radius 22 m.
  - A strip of flat blue shows past one corner at some camera angles. Not removed by the island day sky (no sun shafts:
    darker), the first-floor maze sky (`DayMaze1st`, looks the same as `DayMaze`), the next room (`RedRoomB`) or the
    maze rooms the fight's scenes also stream (`MazeRoomA`, `MazeRoomB`); hiding the simulator's sky and its terrain
    backdrop did not either.
  - **Owner (photo mode, with screenshots of the real fight): the blue is missing wall.** The real hall is closed in by
    tall patterned walls. In photo mode two sides of ours were a low parapet with open blue above (`rdwall-sheet`).
    Not fixed by: every Temple and forest terrain level loaded beside it (76), the maze shell (`020_1th_MazeRoom_Terrain`),
    the temple exterior, the world sky level, forcing the terrain's streaming proxies to full detail, or the renderer's
    console variables (`r.MassiveEnvironment.*` HZB culling off, screen-size thresholds 0, LOD scales 16, simple
    instancing off; `r.Streaming.MassiveEnvironmentFullyLoad 1` with a 3000 MB pool, set before the load). The same
    walls were missing from 21 m off-centre. Turned 180 degrees, the hall's massive-environment terrain did not draw
    at all (its other actors and collision did turn): that renderer follows a move, not a turn. The terrain has no
    materials (468 texture imports) and its bulk data streams fine elsewhere (Midgar's is 73 MB).
  - **The second phase is a second hall.** `RedRoomB`'s pieces are at the same x and y as `RedRoomA`'s, 97 m lower,
    rolled 180 degrees: the game stages the gravity-reversed phase in an upside-down copy, which the fight's physics
    volume loads with the first. Its walking surface (the copy's vault) is flat at -15479 over 48 m by 48 m with a
    1.6 m ledge round it; the walls are 24.2 to 24.7 m from the centre (31 m into the corners), symmetric. It draws in
    full (`rd-roomb-photomode.png`). The stage now uses it (owner's request: the second phase's arena).
  - **Lighting (owner: the characters were too dark).** No lamps near the second hall (all of `RedRoomA_Light`'s 60
    light components are 130-140 m above its floor); the level BuiltData are empty. Characters take ambient light and
    exposure from PrecomputedLightEnvironment components. The simulator's own (`0000-COMON_VR_Light`) stayed on under
    the stage: characters near-black. `TimeSet_Maze`'s `DoorA_1` alone lit and shaded them; `DoorA_2` alone was darker;
    `PLEA_MazeRoomA` (`TimeSet_MazeRoomA`) or `TimeSet_Maze_2th`'s alone washed the picture out (`rd-light-environments.png`).
    The brightness probes (`PrecomputedBrightnessEnvironmentComponent.ExposureDataArray[].Position`) keep the map's
    coordinates, so they are moved by the level's offset. New stage fields: `light_environment`,
    `move_brightness_probes` (`rd-roomb-lit.png`).
  - **Lighting, second round (owner: uneven and unnatural, walls glaring over a dark floor; the light jumped across
    the walls when moving; reference shots of the real fight with sun stripes on a pale floor).** The reference shots
    are the first-phase hall: its flagstone floor is this hall's ceiling, and this hall's colonnade is at the top.
    With the stage sun's shadows off the floor lit pale, so it takes the sun; with them on no angle reached it:
    pitch 28 to 70 degrees from all four sides, and the sun turned to shine upwards. Not the cause: the simulator's
    massive terrain (moved 200 m down, no change). A spotlight inside the colonnade flooded the floor evenly; 80 m out
    the colonnade's depth blocked it, as it blocks the sun. Two looks shown to the owner: the sun at 1500 with one of
    the light level's unused spotlights as a shadowless fill from above (`exp-modlook`), and that spotlight inside the
    colonnade at full strength (`exp-orange`). The owner preferred the warm one, a little less orange. The lamp is
    white with colour temperature off: the orange is the strong light on the warm stone, so lowering its strength
    only darkened it and stayed red; a cool tint (0.62, 0.8, 1.0) at full strength turned it golden (`exp-tint1` to
    `exp-tint4`). Released: that lamp, the game's sun as it is, and the massive-environment shadow culling off for
    the visit.
  - **Fights starting behind the black screen (player reports).** Live with the new code: the game began the fight
    2.4 s after arrival, before the stage was set up; the mod held the world's clock (global time dilation 0.0001)
    for 3 s and let it go as the screen lifted.
  - **Turned start (owner: face the solid wall rather than the colonnade), dropped.** The simulator starts the party
    8 m out on +X facing -X, a colonnade. Turning the party, the enemies and the camera round the centre held for
    about a second, then the game put everyone back at the fight's real start; turning the simulator volume's target
    (`TargetRotationDegree`) did not move the start at all. The owner dropped it.
  - **Replay row.** "Replay: Temple of the Ancients" was the picker's first row after a Temple visit, and choosing it
    loaded the Temple.
  - **Release soak (the 1.3.0 zip's scripts and helper, 14:26 to 14:48): 8 visits, no crash.** The Temple from a
    Grasslands course (through Replay), Titan's and Alexander's summon courses and a Corel course; Midgar Outskirts
    twice (once through Replay); Cave of the Gi twice (once through Replay), each fought by the autopilot. Every visit
    the game began the fight before the stage was set up; the mod held it and let it go as the screen lifted (black
    screen off 3.0 to 6.6 s after arrival). The Temple's lamp and render settings were applied on each Temple visit,
    and the render settings were back to the game's values afterwards (`soak-130.txt`).
  - Crashes during this work: two `UE4SS.dll+0x6a8c4f` (after stage visits, on the plain simulator), one
    `VCRUNTIME140.dll` memcpy 5 s after a stage unloaded with `r.Streaming.MassiveEnvironmentFullyLoad 1` set by hand.

## 2026-11-19: Midgar Outskirts, and four drafts cut (1.2.0)

- **Midgar Outskirts loads and looks right.** Photo-mode views from the centre show the Sector 5 wall, the plate
  overhead, the reactor, fences and fires in daylight (`outskirts-views-20261119.jpg`). With one collision cell the
  ground ended about 6 m east of the centre; with the outer wall's four cells and their physics cells, the capsule probe
  found ground within 60 cm of the centre's height across the arena. The downed helicopters are not there: the story
  places them (`VE0015_00_FallenHeli_Standard`), and `LoadAsset` returns an invalid object for their model.
- **Courses:** Titan solo, Alexander with the party and two Grasslands courses, 90 s of combat autopilot each. The
  stage was in 3 to 7 s after arrival each time; the game stayed up.
- **Soak before release: 8 visits, no crash** (13:44 to 14:05, one game process since 13:14). Grasslands and Corel
  courses, Titan, Phoenix and Bahamut Arisen, solo and with the party, about 45 s of combat autopilot each, the stage
  forced. Each Midgar visit was in place 4 s after arrival. The Phoenix course ran on the plain simulator: it needs
  28.3 m of room and the stage has 25 m, so the mod left it out, as designed (`soak-midgar.log`).
- **Two silent exits while streaming.** Twice the game froze two to four seconds into streaming a stage (once Midgar
  Outskirts, once the Tseng and Elena draft), stayed frozen for about a minute and closed, with no crash dump, Windows
  error or UE4SS log line. Both came after a harness server restart that day; seven loads before it and the loads since
  were fine. The cause is not known.
- **Cut:** Tseng and Elena (invisible-floor problem, as Reno and Rude's plaza), the Altar (wrong level set), both
  reactor drafts (not the room meant). See `docs/research/NEXT-STAGES.md`.

## 2026-11-18, night: soak before release

**43 stage loads and 41 exits after the 17:31 fix, no crash during a visit** (17:45 to 21:38, all six stages: Inside
the Lifestream 9, Cave of the Gi 8, Shinra Manor 8, Gilgamesh's Garden 7, Mythril Mine 6, Edge of Creation 5; all six
summon courses and Grasslands, Corel and Gongaga battle courses, with the combat autopilot). The last run was 20
successful visits in a row (`evidence/soak-log.txt`, per-visit driver logs in `evidence/soak-visits/`). Earlier the
same day, before the fix: about 9 crash reports over 64 stage loads, not all of them during a visit. The owner chose a visit count over a fixed time
(crashes come on entering and leaving stages).

**One crash, not in a visit:** 20:10:06, `UE4SS.dll+0xbf476c` (a null read inside UE4SS's Lua interpreter), a minute
after a save load while the harness walked to Chadley; no stage had been loaded in that game, and this mod was only
reading its helper's file. The same signature appeared once earlier in the day. Not attributed.

**Frame freezes in fights (owner: "like clockwork, about every 4 seconds").** In the recording, clusters of 0.2 to 1 s
freezes every ~3.2 s (`freezedetect` on the OBS file) while a course sat between rounds with no autopilot. The only
activity was the test driver reading `read_combat_simulator_menu` every ~2 s: with no menu open, the harness's reader
searches every widget (a `read_message_window` in a fight took 1.4 s). The driver now reads the menu only while one is
open or, out of a fight, every third pass; the next fight's recording had no such rhythm. Earlier severe hitching
(18:01 to 18:46) was video encoding running beside the game. Also: `pkill` does not exist in this shell, so earlier
"stopped" drivers kept running and held the harness's input lock; the harness server was restarted at 20:07.

## 2026-11-18, evening: summon courses with the combat autopilot; one more crash and its fix

**Summon courses on the stages, fought by the harness's combat autopilot** (the owner asked for summon courses and the
autopilot). Each run: course, picker, the weakest power level, a three-member party, about 100 s of autopilot:
- Odin on Inside the Lifestream (solo Cloud: lost after 70 s; black screen off 5.6 s after arrival);
- Phoenix on Edge of Creation (`upd-04.png`: floating rocks, nebula, party fighting; 3.6 s);
- Bahamut Arisen on the Mythril Mine (`upd-05.png`; 6.4 s);
- Titan on the Cave of the Gi (`upd-06.png`: lit on every side; 6.6 s);
- Kujata on Gilgamesh's Garden (`upd-07.png`; 8.5 s).
Phoenix, Alexander and Odin need 22 to 28 m, so they offer Inside the Lifestream, Edge of Creation and Gilgamesh's
Garden; Titan, Kujata and Bahamut Arisen (14 m) also offer the Mythril Mine and the Cave of the Gi. Summon courses ask
for a power level after the picker. The harness reads only the picker's first two rows, so the driver counts rows.

**Mythril Mine lit (owner, with a screenshot of the fight: "the subjects are lit whereas in our mod they're almost
silhouette").** The mine was the one interior loaded without its area's light level or a sky. Its streaming volumes
(`1230-MYTHM.umap`, read from the Steam copy) load `1230-MYTHM_Light` with every part's `_Light` and `_TimeSet_Day`
level; adding it, `04Mine_TimeSet_Day`, `09JUNOACave_TimeSet_Day` and the mountain cave sky (`MountSky_Cave`, as for
the Cave of the Gi) lit the cave blue-green on every side, the crystals glowing and the party lit (`upd-09.png`,
Titan's course; 45 lights shown against 17 before, none of the 29 levels refused). Still a little darker than the
owner's screenshot. The owner had thought of cutting the stage, then kept it (2026-11-18).

**A crash a second into an arrival (17:31:13).** Shinra Manor on a Grasslands course: `black screen on` at 17:31:12,
then the same `UE4SS.dll+0x6a8c4f` fault, its stack a Lua `pcall` round `IsValid`, the shape of this mod's `valid()`.
Objects were no longer kept from one visit to the next, but within a visit the mod still kept the simulator's level
streams from the moment it found them and asked each tick whether they were valid, while the game was still loading
and can replace them. Fixed: those streams are kept as references and found again by path on every use.

**Finding an object again by its path only works for level streams** (tried in the game). StaticFindObject finds
`/Game/Level/Game/EndGame.EndGame:LevelStreamingDynamic_1`, but not an actor in a level, the level itself
(`...:PersistentLevel`), a world-plan volume or a widget, in any spelling tried (as GetFullName gives it, all dots,
KismetSystemLibrary's path name). So the earlier fix's look-up of kept actors after a visit never found them: putting
the simulator's look back after a visit has done nothing since then, which is harmless because the game builds the
simulator's levels anew on every visit. Turning the picker window and the simulator volume into references broke the
picker and the volume read (`picker closed without a choice`, `simulator volume unreadable`), so those, and the
actors, are kept as objects again, found only once the loader is idle and used only within the visit.
- UE4SS's `FindObject` with a nil outer raises "No overload found" past `pcall` and stops the chunk; so did
  `TArray:ForEach` meeting a null actor slot. Avoid both in probes.

## 2026-11-17: work towards 1.1.0 (more stages; Epic 1.005, slot 25)

**Gilgamesh's Garden works.** The game ships a second look for the simulator's own level,
`0000-COMON_VR_Gilgamesh_Terrain_Strip`, `_Light` and `_Effect`, used by Gilgamesh's legendary-summon trials. It is
centred on the simulator's own origin, so it needs no offset, height or fit. Loaded and set up by hand, then through
the mod's picker (`stream gilgamesh_garden 3 levels`, `activate 141`): the raked-sand garden with stepping stones,
lanterns and cliffs, lit, the party on the sand (`131-gil-shown.png`, `136-gil-through-mod.png`).
- Its 69 visible meshes, 62 point lights, 8 effects and its massive-environment backdrop arrive hidden.
- It needs the simulator's own sky: with the sky hidden the scene is black. The trials appear to use it too.
- Its own floor collision is in separate `AutoGenCollision` grid levels, not loaded; the simulator's flat floor is at
  the same height. Beyond about 25 m a raised border sits 50 cm up. The playable radius stays 24.4 m.
- Unlock: `stfArea0001_Gilga_StoryHub_Clear` (Gilgamesh's quests complete). Only checked on a finished save, where it
  and every other Gilgamesh flag read true.

**Interiors load and light, but do not fit the simulator.** The Galian Beast's arena (Shinra Manor basement, 8
levels) streamed at its territory's centre: 1,923 meshes, 37 point lights and 69 spot lights shown, a lit stone floor
at about the party's feet (`134-galian.png`). But the room is not a flat 24 m circle: walls stand inside it (a rim view
is all wall) and sunken pits lie within it, over which the party walks in mid-air on the simulator's invisible floor
(`135-galian-rim-*.png`). Its own collision is not loaded. An interior needs a chosen centre where the space is open
and flat, and possibly its own wall collision; each is a design job.

**What comes with an interior (owner, 2026-11-17: "figure out what else is supposed to come along with the level").**
Like the Lifestream's sky and the Edge of Creation's rocks, each interior has parts beyond its terrain:
- its `Gimmick` and `Physics` levels (props, doors, breakable boxes);
- its floor and wall collision, in `AutoGenCollision/*_Terrain_Grid_<cell>` and `GridPhys_<cell>` levels, chosen by
  cell with `tools/select_collision.py` (the Shinra Manor basement: 7 + 4);
- and no sky: an indoor stage marks `indoors`, so the simulator's sky goes with its look. With the simulator's sky
  and light still showing, the Mythril Mine is washed out pale cyan and its rock looks like ice (`147-mythril.png`);
  with them hidden it is dark rock, timber and lanterns, as in the story fight (`150-mythril-novr.png`).

**The Shinra Manor basement works** (23 levels, ready 4 s after arrival): the stone floor with its sunken channel and
grate, lanterns and floodlit platform, the party standing on its own collision (`157`/`158-galian-*.png`). The room's
breakable Shinra boxes are there. The owner saw a big square pit in the middle that the boss fight does not have: it
is closed by a floor door, `BG0307_00_FloorDoor_Standard` in the Gimmick level, which arrives hidden. Shown, it fills
the pit flush, with the square outline seen in the fight (`179`/`180-galian-door-*.png`, through the mod `181`).

**The Mythril Mine works** (25 levels, ready 4 s after arrival): matches the owner's screenshot of the Mythril Golem
fight (`151-mythril-mod.png`, `154-state.png`). Its collision grid levels and its Water level are not in the Epic 1.005
build (the helper's load is refused at every path), but its terrain collides on its own: a flat floor about 30 m
across, walled in. Cloud ranged about 30 m around it during a fight, on the ground throughout.

**Gi Nattak's cave works** (56 levels, ready 7 s after arrival): the orange-lit rubble floor, paving and dark walls,
as in the owner's two screenshots of the fight (`166`/`167-ginattak-mod.png`). Without its collision grid levels it
has no ground of its own (`f11` read nothing within 5 m), so all 28 of its `AutoGenCollision` cells are loaded (the
SeaArea's two left out). The level reader handles the Steam-era grid extractions but not these Epic 1.005 ones
(`list index out of range` on every export), so cells cannot be picked one by one yet. With them it is a bowl, flat to
within about 0.4 m for 18 m from the centre and about 15 cm below the simulator's floor (the anchor is lowered to
match), rising about 1 m beyond. The red glow at the far edge in the owner's screenshots is not seen here; it may be
the boss's own effect.

**Names (owner, 2026-11-17): the location only.** "Shinra Manor", "Mythril Mine", "Cave of the Gi", "Temple of the
Ancients" and so on, without the boss's arena.

**Reno and Rude's arena works** (67 levels, ready 12 s after arrival): the plaza on the temple's second floor, dark
stone paving round a recessed square, pillars, under a teal storm sky, as in the owner's two screenshots of the fight
(`175-renorude-mod.png`). What it took:
- The right rooms. Its old list loaded rooms from every floor (56 levels, 1.1 GB) and drew nothing near the arena.
  Counting each loaded level's actors near the centre placed the arena in the second floor's LifeRoom A and B
  (`030`-`032`); the first-floor maze, rest, doll, painting and black rooms were dropped.
- Its floor. The second floor's `030_2th_LifeRoom_Terrain` level and its Gimmick, Physics and collision cells. The
  plaza is 4.31 m below the territory marker, so the anchor is lowered by that much. It is flat at the simulator's
  height for about 40 m and drops away about 20 m to the south, so the radius is 18 m.
- Its light. The temple has no lights of its own: its sun and fog come from a world sky. With none it is black
  (`168-renorude.png`); the Island "DayMaze" sky lit it as a sunny day (`170`); the owner's screenshots show the fight
  under the "DayStorm" sky with the temple's `TimeSet_Storm` (`174`, `175`).
- More levels than the helper queues. The helper holds at most 64 unanswered requests and refuses the rest
  (`queue_full`); the first full try lost its last three levels, the sky among them. The mod now asks for 48 at a
  time and tops up as the helper answers.

The longer load shows: the simulator's own look stays for the 12 s it takes, as designed (it is hidden only once the
stage is in).

**Temple of the Ancients cut from 1.1.0 (owner, 2026-11-18): "more trouble than it's worth".** The floor's collision ran
2-3 m past the paving at the edges to Cloud's front (west) and left (south). The fight's extension floors sit there
(`BG3021_00_RenoFloor`, `BG3022_00_RenoFloorB`, LifeRoomA Gimmick), but they are skeletal meshes that the cutscene
before the fight (`EV_FOREE_2480`, its `BG3021_00` motions) moves into place; shown, they stay in their starting pose
and the owner still saw no floor. The sky's Lifestream ribbons are `FX_3110-TEMPL_2nd_LifeStreamStorm_01/02`, spawned
by state changes (`scg3110_2ndCloud2_VFX_Tornado_On` and others, from the PlannerLevelSet data), not placed in any
level. Both need assets loaded from disk; UE4SS's `LoadAsset` only finds what is already loaded in Epic 1.005, and
`LoadAsset_Blocking` cannot be called from Lua (its soft-object parameter is unsupported). A native "load asset" in the
helper would open both. Removed from the stage data (owner, 2026-11-18).

**Crashes: a kept object checked after the game destroyed it (2026-11-18).** Twelve crash reports since 2026-11-14,
ten inside UE4SS. Nine of those at `UE4SS.dll+0x6a8c4f`: disassembled, a function that reads a UObject's
InternalIndex (UE4SS's validity check), crashing on memory the game had freed. A Lua mod kept an object, the game
destroyed it, and the mod asked whether it was still valid. This mod did that: it kept the simulator's own levels
(`simulator_levels`) from one visit to the next and checked them again, and put the simulator's hidden parts back from
kept pointers after leaving. Two of today's crashes came exactly at that check (just after `scenery`). Fixed: kept
objects are stored as path and address and found again with StaticFindObject (`fresh`), and `forget_visit` drops
everything kept for a visit when a course is confirmed and when the visit ends. The same crash on 2026-11-14,
before this mod existed, means other mods do it too: the harness's telemetry exporter, Junon Colosseum, the Queen's
Blood probe, No Popups, Training Dummy, Battle Meters and the Biome Randomizer all keep objects across frames.

**Menu lag.** With a stage just left, the Biome Randomizer's step logged game-thread stalls of 1.0 to 1.8 s (once
3 s) several times a minute in the simulator menu. Unloading after a visit now runs at the game's own budgets with
the engine's purge spread out (`background unload on/off`). Timed through the harness, a menu press moved the
highlight in 0.83 s median with the Biome Randomizer and 0.71 s without: within the harness's own reading time, so
not conclusive. The owner's report decides.

**Arrival without the flicker (2026-11-18).** Recorded once a second from confirming the course, the Temple showed
the simulator at 14 s, a darkened simulator while its look went, then the Temple at about 27 s (`280-entry-sheet.png`).
The game ends its loading screen once its own levels are in, whatever ours are doing.
- Holding the loading screen by keeping one of the simulator's levels hidden (the old "Get Ready hang", on purpose)
  kept it up, but the game showed its round banner and the simulator anyway, and with it held one of the Shinra
  Manor's levels did not load until it was let go, 41 s in. Dropped.
- A camera fade and slowing the world's clock did nothing (the game drives both).
- What works: the game's own fade overlay, `UEndMenuAPI.AddFadeFilter`, black and opaque, put up on arrival and faded
  out over 0.5 s once the stage is in, set up and lit (`black screen on/off` in the log; lifted after 41 s whatever
  happens). Temple: black until 17 s, then the finished stage (`293-entry-sheet.png`); Lifestream: black, then the
  stage at about 12 s, as before (`288-entry-sheet.png`). Other mods' overlays drawn on top of everything, such as
  Training Dummy's panel, still show over the black. On the largest stages the fight's first seconds run under it.

**Skies light the interiors.** An indoor room is still lit by its region's sky (its sun, fog and reflection capture):
- Shinra Manor: with Nibelheim's night sky (`MountSky_Night`) its rock walls, graffiti, cage bars and the floodlit door
  show as in the owner's screenshot (`290-manor-night-*.png`, through the mod `292-manor-*.png`).
- Cave of the Gi: with the mountain cave sky (`MountSky_Cave`) every side is lit, arches and braziers in a warm haze
  (`294-cave-*.png`); Cosmo Canyon's sunset sky blew it out white.
- Temple: the Lifestream effects are in its levels; the game switches the far ones off by distance (on by hand, they go
  straight back off), so the broad ribbons of the boss fight are still missing. `start_effects` was removed.
- The game crashed four more times today with UE4SS faults (`UE4SS.dll+0x6a8c4f`, once `+0xbf476c`). The same crash
  happened six times on 2026-11-14, before this mod existed; two of today's came at the moment the mod hides the
  simulator's look on a large stage, so the mod's heavy moments may make it likelier.

**Owner's second round (2026-11-18): dark sides, invisible walls, load times, the Temple's sky.**
- **Invisible walls and floor.** Hiding the simulator's look left its collision: its pillars and walls about 24 m out
  were invisible walls inside the bigger stages, and its flat floor ran on past the Temple's edges. `drop_simulator_collision`
  turns the pillars and walls off on every streamed stage and, with `own_ground`, the floor too (the four interiors).
  The game keeps fighters inside the battle area itself: Cloud put 21 m out past the Temple's west edge was back on the
  plaza within 1.5 s. Mapped with the floor off, the Temple's plaza ends at its own edges (`f11`).
- **Which levels belong to an arena.** Each location's main level (`2550-GIZOK.umap`, `2650-NIBLS.umap`,
  `3110-TEMPL.umap`) holds streaming volumes listing what the game loads where; read from the Steam copy's paks (the Epic
  ones do not parse with our reader) with `volumes.py`. That added the Cave's SeaArea set and `SetArea_TimeSet_Day`,
  the Manor's `LostN_Emissive` and `Entrance_Terrain`, and the Temple's rooms' grass, tree and interior levels (the far
  ruins and towers). Eleven Cave levels that hold nothing in Epic 1.005 were dropped.
- **Cave of the Gi**: three sides now lit as in the owner's screenshot (`270-cave-*.png`); one side is still black.
- **Temple**: the Lifestream effects in its levels are mostly started by the story as the party walks in, so the
  stage starts them (`start_effects`); a faint green ribbon now shows in the sky (`276-temple-3.png`), not the broad
  ribbons of the owner's screenshot. Other skies tried (DayStormAerith1st, DayMaze, the Cetra time set) did not add them.
- **Shinra Manor's sides are still too dark**: the lamps glow but light little round them. Not the missing levels
  (all its light levels load), not its `Timeset_None`, and not the `Before_*` set (that is the flashback manor's). A
  guess: its walls' baked lighting does not come through when the levels are loaded away from their own place.
- **Load times.** The engine's level-streaming budgets (`s.UnregisterComponentsTimeLimit` 1 ms, 5 components a step;
  adding 5 ms, 10 a step) made leaving the Cave of the Gi take 79 s back to the course list, against 43 s from the
  plain simulator. The mod now raises them to 20 ms and 100 while a stage loads or unloads and puts the game's values
  back after (`fast streaming on/off` in the log; checked back at 1.0 after a visit). Sending the unloads only once the
  game's own loader has been idle 4 s after a visit, rather than as its trip back starts, took the Temple from 59 s to
  48 s; the garden takes 45 s. Arriving: the Cave's levels are in 8 s after arrival instead of 11. The helper's answer
  file is now read once a fifth of a second instead of once per level.
- The game crashed twice more today with the same UE4SS fault (`UE4SS.dll+0x6a8c4f`), once in a plain-simulator fight
  with no stage loaded: it is not this mod's loading.

**Checked with the game's photo mode (2026-11-18).** The owner asked for photo-mode pictures of every stage instead of
screenshots taken by moving the party (the earlier captures teleported Cloud, which the owner saw as him snapping
around). The harness now has `photo_mode_photos`; the `230-<stage>-<n>.png` series is four views per stage with the
party hidden.
- **Unloads hit the helper's 64-request queue too.** Leaving the Temple released its 67 levels at once; the last three,
  its sky among them, were refused and stayed loaded. The sky's fog, sun and unbound post-process then applied to the
  whole world: Edge of Creation and the Mythril Mine came out white, the Lifestream and the garden tinted. Releases are
  now queued and sent 48 at a time, after the visit too; checked in the game: all 67 unloaded (the 67th after 12.6 s)
  and the next stage was right.
- **Two game crashes**, at 00:16 and 01:00, both an access violation at `UE4SS.dll+0x6a8c4f` with the game's own C++
  exception on the stack: the same signature as the UE4SS crash in FFVII-Modding issue #220. Both came while a large
  stage (the Temple, then the Cave) was loading. Not caused by this mod's code as far as the dumps show, but large
  stages seem to make it likelier.
- Still to look at: the Shinra Manor is darker than the owner's screenshot of the fight; Gilgamesh's Garden shows the
  simulator's hexagon sky (kept on purpose: without it the garden is black).

**The stage's lights now always wait for the simulator's look to be hidden.** On a later visit a cached stage was
ready "0 s after arrival", before the game had shown the simulator's lighting, so the mod saw none and switched the
stage's lights on at once; the simulator's lighting could then arrive over them (the dull Lifestream the owner saw
once). Both a first and a cached second Lifestream visit now log `lights wait` then `lights` after the dressing, and
look the same (`160`/`161-lifestream-*.png`).

**Fixed before release:** a path "normalisation" in the working copy had doubled `/Game/Level/Game/` in every level
path. The installed 1.0.0 paths were right; the working copy was corrected before anything shipped.

**Feasibility, as it stands:**

| Stage | State |
| --- | --- |
| Gilgamesh's Garden | Works |
| Other final-battle sets (church, broken rock, Jenova phases) | Not tried; built like the two that work, expected easy. Not on the owner's list |
| Shinra Manor basement (Galian Beast), Mythril Mine (Mythril Golem) | Work |
| Cave of the Gi (Gi Nattak) | Works |
| Temple of the Ancients (Reno and Rude) | Loaded, but cut in 1.1.0 (floor collision and Lifestream sky missing; see 2026-11-18) |
| Open world: the six regional arenas, Grasptropod, Anuran Suppressor, Gilgamesh's island arena | Blocked: their ground is massive-environment terrain, which does not draw when loaded elsewhere |

## 2026-11-17: seventh live session (which courses; the swap at the start of a fight; Epic 1.005, slot 25)

The owner: the tutorial and Training Dummy courses should have the stages too (the Shinra Manor courses stay left
out); and "there's 2 or 3 seconds where the original stage shows, kind of frozen, then our stage loads in".

**Courses**

- The eleven tutorial courses are in scope. Not run in the game yet.
- The three courses the Training Dummy mod adds are recognised (`data/mod_courses.json`): the mod reads the title that
  mod puts on screen ("Training Dummy: DPS"). Seen: the picker opens for it and both stages load
  (`100-dummy-on-edge.png`).
- The eight Shinra Manor courses stay left out. They use the same simulator level through another content volume
  (`VRContentNIBLS`) and another flag, and have not been tried.

**The swap**

- **Every object search costs about 0.2 s** (`FindAllOf` walks the whole object table: 160 to 210 ms for each of 13
  classes tried, whatever the class). The mod made eight at the moment it hid the simulator's look, which froze the
  screen on the simulator's stage for about two seconds, and eight more for the repeat "show" five seconds into the
  fight.
- **What the game does on the way in**, from the mod's log and one screen frame a second: the party "arrives" (the
  flag flips) about 5 to 9 s after the course is confirmed; the screen is black until about 4 s after that (17 s after
  the confirm on a first visit, 13 s on a later one); the simulator's lighting, effect and sky levels only exist 3 to
  7 s after arrival.
- **Now:** the stage's own parts are stretched and shown as soon as its levels are in and the loader is idle; the
  simulator's scenery (floor, pillars, walls, skyline, rim collision) is found and hidden as soon as its floor exists
  (one cheap search a second asks); its lighting, effect and sky levels are told to hide on the first tick the game
  has all three showing, from kept references; the repeat show re-shows kept actors. No search happens after the
  loading screen.
- **Seen on a first visit** (`103-entry-*.png`): black through second 16, and the first frame with a picture already
  shows the Edge of Creation with its rocks. The mod had finished 13 s after the confirm. The simulator's stage never
  appears.
- **Not seen on a later visit.** By the log the mod finishes about 5 s after arrival there and the plain simulator's
  first picture comes about 4 s after arrival, so up to a second of the simulator's look may still show. The harness
  refused taps on and off for the rest of the session (its telemetry samples were just over its 2 s age limit; a
  video encode was running), so no clean capture was made.
- **If more is wanted:** the remaining cost is the eleven or so searches for the stage's own actors. Their names are
  fixed by the level files, so the mod could look each one up by its full name (a hash lookup, no walk) from lists
  made offline. Not built.
- The "Get Ready" protection is unchanged in substance: nothing tells one of the simulator's levels to hide before
  the game has shown it. Hiding its actors early changes no level's state.

### Added the same evening: "the Lifestream stage seemed a bit dull again" (owner)

- The visit the owner found dull (19:12) loaded everything: four levels, 31 hidden parts shown. What differed is
  order. Its log has the stage's lights switched on at 19:12:34 with the simulator's own lighting levels already
  showing, and those hidden at 19:12:36. On the visits that looked right the stage's lights came on before the
  simulator's lighting levels existed (18:47, 19:36: 7 to 9 s before) or after they had been hidden (every visit
  before the swap was reordered, including the one the owner called a perfect match at 18:13).
- So since the reorder the look depended on timing: a visit where the simulator's lighting is already up when the
  stage's lights go on (typical of a later visit in one game session) comes out dull.
- **Change, tried in the game the same evening:** the stage's meshes are still shown as early as possible, but its lights
  (sun, fog, ambient light, reflection capture, fog volume) are switched on only while none of the simulator's
  lighting levels is visible: at once if none is, otherwise the moment they have been hidden; after 12 s they go on
  regardless. This rests on three visits with a known look, one of them dull.
- **Tried (19:50 and 19:53, through the picker, Grasslands course):** a first visit after a restart (the stage's
  lights came on at once: the simulator's lighting was not showing yet) and a later visit in the same session (log:
  `activate 25  lights wait: 6`, then `lights 6` the same second the simulator's levels were hidden). Both looked like
  the owner's reference: pale silver water, stars (`117-ls-fix-first.png`, `119-ls-fix-later.png`).
- No setting was involved. `force_stage` and `picker`, which I change for scripted runs and put back, only decide
  which stage is used and whether the picker opens.

## 2026-11-17: sixth live session (the Lifestream's sky; Epic 1.005, slot 25)

The owner: the sky of Inside the Lifestream is not right, the real one has sparkles; later, with a reference
screenshot of the real battle (pale silver water, stars and a galaxy cloud overhead), "the floor got raised, we're
wading in it".

- **The battle's sky is the Galaxy sky.** The game's cutscene table (`CutSceneList`, 8800-FOREE) names
  `0001-WORLD_IslandSky_Galaxy` as the sky of `EV_FOREE_8790`, the scene tied to this battle's levels.
  `OtherSky_White` was my guess; it has no stars.
- **The Galaxy sky alone is too dark.** Loaded as the stage's only sky it gives a dim green-grey scene with stars.
  The look of the reference came only with the white sky level loaded first (its own sun and fog kept hidden) and the
  Galaxy sky after it: silver-grey water with reflections and stars overhead (`97-lifestream-two-skies.png`).
  Which of the white level's parts does this was not isolated; the load order is what the stage now fixes.
- **The Galaxy sky has ten fog variants** (centre, "olg", eight "side"); only the centre one is shown. The others were
  not tried.
- **The Lifestream's FarLand level must not be loaded.** It is a flat water plane (35 vertices, 560 m across) lying up
  to 40 cm above the floor. With it the floor turns flat green and the party wades (owner; `90-...png`). I had added
  it by analogy with the Edge of Creation without checking where its surface lies inside the arena, only where its
  vertices are.
- Its Effect level is empty. Its Sound level (not loaded) probably holds the battle's ambience.
- Scripting note: Git Bash rewrites an argument that starts with `/Game/` into a Windows path; set
  `MSYS_NO_PATHCONV=1` when passing package paths on the command line.

## 2026-11-17: fifth live session (the "Get Ready" hang; Epic 1.005, slot 25)

The owner: "sometimes it lingers forever on the Get Ready screen".

- **What the log shows.** Two visits ended with the game being closed and no fight (15:47 and 16:42). Both were a
  later visit in one game session, both read `settled 1 s` or `2 s after arrival` and `dressing 20` where every visit
  that worked reads 4 to 9 s and `dressing 21`. The mod had acted before the simulator had finished coming in.
- **Why it acted early.** "Settled" meant "the package loader has been idle for 2 s". On a later visit the
  simulator's levels are cached, the loader never gets busy, and that is true from the first second.
- **What the game does on the way in** (measured with `tools/live/probe_sim_levels.lua` and the arming probes): the
  in-simulator flag flips before any of the simulator's own levels exist; its lighting and sky levels appear about a
  second later, not yet loaded; its effect level comes last; it destroys and recreates them on every visit.
- **Telling a level not to be visible before the game has shown it holds up the start.** Done to the lighting and sky
  levels at first sight, the fight took 15 s to start where it takes 8, and the game had re-shown them by then.
  A permanent hang was not reproduced on demand in six tries (the timing window is short and varies).
- **Fix.** The mod touches nothing of the simulator's until the game has loaded and shown all three of those levels
  and that has held for two seconds (`game.simulator_shown`, `SHOWN_FOR`), and it never tells a level that is not
  visible to hide. If they have not all shown 20 s after arrival the log says `waiting` and how many exist.
- **After the fix:** six visits in one game session through the picker, alternating Edge of Creation and Inside the
  Lifestream, all reached their fights; each reads `settled N s after arrival, shown for 2 s`, `dressing 21`.
- Also learnt: searching for objects every 100 ms during the load slowed it badly (a fight took 34 s to start).
  The mod's own check runs once a second and only with the loader idle.
- Not proven: that this was the only cause. If it happens again, the last lines of `stages-log.txt` now say what the
  mod was waiting for.

## 2026-11-17: fourth live session (names, a closer fit, the floating rocks; Epic 1.005, slot 25)

The owner: fit the rock to the arena exactly if possible; add the real floating rocks in their right places; name the
stages "Inside the Lifestream" and "Edge of Creation".

- **Names.** `lifestream` is "Inside the Lifestream", `space_rock` is "Edge of Creation", and "Arena" is capitalised in
  the others.
- **The rock's true shape comes from its mesh file.** `tools/rock_outline.py` reads the vertices of the cooked
  skeletal mesh `BG2130_00` (312,548 of them; its extents match the bounds read in the game). The platform is an
  irregular oval of about 52 m by 35 m with cracks between its five fragments and a sloping rim.
- **It cannot match a circle exactly, but it can be close.** `tools/rock_fit.py` finds the centre and the stretch
  along X and along Y for which every metre of the arena's 24.75 m circle has level rock under it, with the least
  rock left over: centre (0, -75) in the mesh's coordinates, 1.08 by 1.70. Level rock then reaches 0.2 to 6 m past
  the wall depending on the direction (one stretch for both directions would need 1.70 and leave up to 22 m).
  Through the mod: `fit 47`; rock under all four rim points (`75-final-*.png`).
- **The floating rocks are two things**, both now loaded at their true size and place:
  the `FarLand` level (one low-detail mesh, 9,622 vertices, 520 m by 440 m, of the whole island and the rocks about
  it), which the stage never loaded, and four hidden rock effects in the Effect level, now shown.
- **The far-land mesh includes a copy of the platform** that reaches 46 cm above the floor inside the arena. It is
  lowered a metre (`fit.keep`), which puts it under the real platform; beyond the platform it stands in for the
  island's northern terrain, which is massive-environment terrain and does not show when streamed.
- **A summon works on a streamed stage**: Odin was called during the fight on the Edge of Creation
  (`72-far-lowered-135.png`).
- Dead ends: the ground piece has only 14 bones (five fragments), so bones do not trace its shape; the visible meshes
  have no collision, so nothing dropped or swept can find their edge.
- **My mistakes this session.** (1) A probe called `SetCollisionProfileName` with one argument where it takes two;
  UE4SS raised an error mid-probe, after the probe had switched collision off, and the game had to be restarted.
  Probes that change state now restore it inside `pcall`. (2) I ran probes that move the leader without checking the
  fight had started; they ran in the open world and left Cloud hanging over the sea. Check `in_battle` and the
  leader's position first. (3) The owner had restarted the game and was playing while I changed its settings file.
- Left: at the south rim the rock's collision is 30 to 50 cm below the floor for the last few metres, so characters
  stand on the simulator's floor just above the rock there.

## 2026-11-17: third live session (the rock's invisible floor; Epic 1.005, slot 25)

The owner: "the rock stage has quite a big chunk of invisible floor".

- **The arena is a circle of 24.4 m radius.** The leader's capsule swept outwards from the centre stops at 2440 cm in
  all 24 directions tried.
- **The rock's visible slab is about 51 m by 33 m and sat 7.5 m south of the arena's centre**, so the northern third
  of the arena had no rock under it. Read from the bounding boxes of its 39 visible meshes and its skeletal ground
  piece (`tools/live/probe_footprint.lua`); confirmed by standing Cloud at rim points, where he hung in space beside
  the rock (`64-rim-000.png`, `64-rim-270.png`).
- **Its collision is not its outline.** The rock's terrain collision reaches well north of anything visible, so the
  height map (a capsule dropped on a grid) showed ground where there was nothing to see. My first fix, centring on
  the collision, moved the rock the wrong way. Measure the visible meshes for coverage and the collision for footing.
- **Fix: centre on the visible slab and stretch it 1.8 times sideways** (`fit` in `data/stages.json`,
  `game.fit_stage`). Each mesh and collision actor moves to centre + 1.8 x its offset and its X and Y scale are
  multiplied; heights are left alone, so bumps do not grow. Static actors are made movable first, or the engine
  refuses to move them. All 50 actors moved.
- **Through the mod** (`fit 50`, `activate 44`): ground within about 24 cm of the simulator floor across the whole
  arena, visible rock under all four rim points and from every side looked at (`66-mod-fit-*.png`,
  `67-rock-through-mod.png`). The stretched texture still reads as rock.
- **Each visit now loads its own copy** (the visit's number ends the instance name), so a stretched copy is never
  found and stretched again. Seen on the way: actors of a copy that was unloaded but not yet collected are still
  found by a search.
- The rock's two massive-environment actors are left where they are. Hiding them made no visible difference.
- Not done: the rock's collision south edge sits a little inside the arena's rim on one side (20 to 80 cm low in the
  last 3 m), where characters stand on the simulator's floor just above the rock.

## 2026-11-17: second live session (owner's play, then probes and a retest; Epic 1.005, slot 25)

The owner played both stages and reported two faults. Both came from one mistake: the stages were anchored about a
metre too low.

| Fault (owner) | Cause, as measured | Fix | Retest through the mod |
| --- | --- | --- | --- |
| On the rock, Cloud is locked to a tiny patch | The rock's ground is 98 to 134 cm above its own z 0, so the party stood inside its collision. Measured by dropping the leader's capsule on a 3 m grid. Placed on the surface he moved freely | Anchor z 110 | Ground 0 to 24 cm above the simulator floor across the arena; Cloud covered 5 m in 6 s; enemies on the rock (`52-rock-fixed.png`) |
| In the "void", characters are silhouettes | Its collision floor is flat at z 100, so the party stood under the floor; and its ambient light, reflection capture, fog volume and 25 floor meshes arrive hidden | Anchor z 100; those classes are shown on arrival | Grey water floor with reflections and lit characters, party of three; Cloud covered 8 m in 3 s (`54-lifestream-fixed.png`) |

- The "white void" is the Lifestream (owner). The stage is now `lifestream`, "Final battle: the Lifestream". The
  owner confirmed the grey water look (`38-void-z100-floor.png`).
- **The simulator's rim clutter keeps its collision when hidden**: low blocks of 30 to 50 cm round the edge, through
  the terrain level's `Spl_CST` collision actor. Its collision now goes off with the look and back on when leaving.
  With it off the floor is flat out to the pillars at about 24 m.
- **A level that was unloaded but not yet collected is reused at its old position.** Reloading the rock 105 cm lower
  under the same instance name left it where it was. The instance name now carries the height.
- **Collision-only meshes (`CL_...`) and cutscene props (`Quest_...`) must stay hidden** when a stage's meshes are shown.
- Left as it is: the rock is about 36 m across and the simulator floor about 48 m, so near the rim characters stand on
  the simulator's invisible floor past the rock's edge.
- Not possible with the harness: walking the leader during a fight (it refuses movement while a target is present).
  Movement was read from the leader's position while the game's Classic mode moved him.

## 2026-11-17: first live session (Epic 1.005, UE4SS 3.0.1, slot 23, Costa del Sol and Bill's Ranch Chadleys)

Driven by the harness in an offline session. The game was restarted five times to load script and helper changes.

### Works

| What | How it was seen |
| --- | --- |
| The helper starts and passes its checks on this build | `stages-helper.txt`: `ready 1`, tick moving; events log: `game_thread_guard_ready epic-1.005`, `loader_check_ready` |
| The simulator stands where the level files say | Leader at (−200151, −99858, 60090) in the east and (−199291, −100522, 10090) in the west: the `COMMON_VR` volumes' `TargetLocation`, feet on z 60000 and 10000 |
| `LoadLevelInstance` with a position | `stages-ack.txt`: every requested level `loaded`; the levels' actors are at their own coordinates plus the offset (the white sky's light at (−190325, −99538, 20037)) |
| Unloading | `unloaded` for each instance; the stage gone from view; the next stage loads after it |
| **The white void, end to end** | `24-white-void-by-itself.png`: picked in the picker, streamed, the simulator's look hidden, sun and fog shown, a normal course fought on it. Log: `stream white_void 3 levels`, `dressing 20`, `activate 2` |
| **The rock in space, end to end** | `25-rock-by-itself.png`: rock underfoot, nebula sky, shadows. Log: `stream space_rock 6 levels`, `activate 43` (sun, fog and its 41 meshes) |
| The picker | `21-picker.png`: the game's choice window, "Choose a stage", over the team screen right after a course is selected; D-pad and confirm work; the choice is saved to `choices.txt` and reused |
| Courses are recognised in any language | The menu's title field holds the text id (`$menu_Colosseum_CourseTitle_COL30_GRASA_01`), not the displayed title |
| Leaving puts everything back | Log: `restore left the simulator released 6 levels`; the next course on the simulator's own stage looks normal |
| No crash | Six simulator courses, about twenty level loads and unloads, three stage swaps inside one fight |

### Found and fixed on the way

- **A stage's sky arrives switched off.** A sky level's sun and fog are hidden until the game's sky system selects that
  sky; streamed on its own it gave a black scene. The mod shows them (`game.activate_stage`).
- **The rock in space's meshes arrive hidden** (all 41): the boss fight shows them. The stage lists them in
  `show_classes`.
- **The simulator's block skyline is not its block actors.** Hiding those left a black skyline; it is drawn by the
  terrain level's massive-environment component. Hiding that component clears it.
- **The white void's light level cuts exposure by 6 stops.** Right with its own bright sky, black without it.
- **The white void's floor is one-sided.** Loaded 60 cm above the party it was invisible and squeezed the camera.
- **This machine uses the low-spec sky** (`0001-WORLD_VRSky_Low`); the hide matches both.
- **A weak pointer made in the helper never resolved**, so the first unloads were refused. The helper keeps the
  stream's address and confirms it is still a live object before using it.
- **An object search at arrival was the same pattern that crashed Junon Colosseum.** The scripts now wait for the
  helper's "loader idle" before searching.
- **My own mistakes:** a clean-up cut four functions off `game.lua` (a test now checks every `game.` call is
  defined); a dev snippet called `ShouldBeVisible`, which is not a function of that object (the Lua state survived).

### Does not work yet

| What | What happened |
| --- | --- |
| Arena stages, streamed (tried: Nibel) | Five of six levels loaded and unloaded cleanly, and distant mountains showed, but no ground appeared under the fight: the arena's ground is massive-environment terrain, which did not show at the offset. Its sky level has 192 local fog volumes; all on whites the scene out, all off leaves it black. The thirteen arena stages are marked `experimental` and are not offered |
| Moving the simulator (`route = move`, tried: Corel) | The write to `TargetLocation` was accepted and read back, but the party arrived at the simulator's usual place. The simulator had already been visited in that session; a first visit after launch is untested |
| The harness reading the picker | The running harness build read only the picker's first two buttons, and `choose_message_window` refuses outside a fight. Menu taps work |
| One Nibel level | `2600-NIBLA_Water_Terrain_Strip`: `load_refused` |

### Not looked at yet

- A summon course, a multi-round course and a party of three on a streamed stage.
- The picker's cursor starts on the first option, not the remembered one (the remembered one carries a `>` mark).
- Lighting on characters in the white void: silhouetted from some angles.
- Memory and load time. The two final battle stages were ready within 2 s of arrival.
- The unlock rules with a real save state (`require_unlock = false` was used throughout).
- Steam, and any game version other than Epic 1.005.
