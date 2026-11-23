# How it works

Reference for modders: what the mod does at each step, what it relies on, what was tested and what is known not to
work. The story of how we got here is in [HOW-WE-BUILT-IT.md](HOW-WE-BUILT-IT.md); each live session is in
[LIVE-RESULTS.md](LIVE-RESULTS.md); what the game's files show is in [research/VR-STAGE-AND-ARENAS.md](research/VR-STAGE-AND-ARENAS.md).

## The simulator's stage

The Combat Simulator's arena is not a map of its own. Each continent's world holds one streaming volume labelled
`COMMON_VR`, which streams the level `0000-COMON_VR` into the open world at the volume's `TargetLocation`: far off the
map and high in the air (east continent (-200000, -100000, 60000), west (-200000, -100000, 10000)). The level's origin
is the centre of the arena and its floor is at z = 0. The fight itself (territory, cameras, navigation and 264 named
points that enemy scripts use) belongs to that level and its sub-levels, so it stays where it is whatever we show
around it. The playable area is a circle of 24.4 m radius (measured: the party's capsule stops there in every
direction).

What makes the simulator look like the simulator:

| Part | Where |
| --- | --- |
| Floor, pillars and walls | Five actor classes (`BG0342_00_Floor_VR_C`, `BG1127_0x_BlockPillar_Standard_C`, `BG1128_0x_BlockWall_Standard_C`) in `0000-COMON_VR_Terrain_Strip` |
| The block skyline | The terrain level's massive-environment component (hiding the actors does not hide it) |
| Low blocks round the rim | Collision only, through the terrain level's `Spl_CST` collision actor |
| Lights and effects | The streaming levels `0000-COMON_VR_Light` and `0000-COMON_VR_Effect` |
| Sky | `0001-WORLD_VRSky` (`0001-WORLD_VRSky_Low` on low settings) |

## A visit, step by step

1. **Course selected** (`EndColosseumMenu:OnCourseMenuPressedItem`). The mod reads the course's title from the menu,
   which holds the text id (`$menu_Colosseum_CourseTitle_...`), and finds the course in `stage_data.lua`. It lists
   the stages the course can use and opens the picker: the game's own choice window
   (`UEndMenuAPI.ShowMessageWindow`). With fewer than two options it shows nothing.
2. **Course confirmed** (`OnYesButtonPressed`). The mod writes one load request per level of the chosen stage for the
   native helper. Each level is loaded as a new instance named `SimStage_<stage>_<n>_<height>_<visit>`, placed so the
   stage's anchor lands on the simulator's centre.
3. **Loading screen.** The party "arrives" when the game's in-simulator flag turns on, 5 to 9 s after the confirm. The
   game ends its own loading screen once its own levels are in, whatever ours are doing, so on arrival the mod puts up
   a black screen of the game's own (`UEndMenuAPI.AddFadeFilter`, black and opaque) and fades it out over 0.5 s once
   the stage is in, set up and lit (1 to 9 s after arrival; lifted after 40 s whatever happens). While a stage loads
   or unloads, the engine's level-streaming budgets are raised (`s.UnregisterComponentsTimeLimit` and its kin, 20 ms
   and 100 components a step) and put back after. Behind the black screen, once the package loader has been idle for
   a second:
   - the stage is stretched if it has a `fit`, and its hidden meshes are shown;
   - the simulator's floor, blocks, skyline and rim collision are found and hidden as soon as its floor exists; its
     pillars and walls stop colliding (hidden, they would be invisible walls inside a larger stage), and on a stage
     with its own ground (`own_ground`) so does its flat floor;
   - the stage's lights wait until none of the simulator's lighting levels is showing (see Lighting below).
4. **The simulator's lighting.** Its lighting, effect and sky levels are told to hide on the first tick on which the
   game has loaded and shown all three. Telling one to hide while the game is still bringing it in can stop the start
   on the "Get Ready" screen.
5. **Leaving.** When the in-simulator flag has been off for 3 s, the mod drops everything it kept for the visit. Once
   the package loader has been idle for 4 s it asks the helper to unload every instance, 48 at a time, at the game's
   own streaming budgets, with the engine's purge of the unloaded levels spread over the next 70 s
   (`s.ContinuouslyIncrementalGCWhileLevelsPendingPurge`). The simulator's own levels are made anew on every visit.

Every `FindAllOf` costs about 0.2 s on this game, whatever the class, because it walks the whole object table, and a
`StaticFindObject` by path about 25 ms. The mod makes all of its searches behind the black screen; from the swap on it
only flips objects it found.

**Kept objects and crashes.** Asking UE4SS whether a kept object is still valid reads the object's memory; if the game
has already destroyed and freed it, the game crashes inside UE4SS (`UE4SS.dll+0x6a8c4f`). So nothing found on one visit
is used on the next, and the simulator's level streams, which the game can replace while it loads, are kept as their
path and address and found again by path each time (`ref` and `fresh` in `game.lua`). Only level streams can be found
by path in this game: an actor in a level, the level itself, a widget or a world-plan volume cannot. Actors are
therefore found once the loader is idle and used only within that visit.

## Lighting

A streamed stage arrives with parts switched off, because the game's own scripts switch them on during the boss fight:

| Arrives hidden | Shown by the mod |
| --- | --- |
| The sky level's sun and fog | `DirectionalLight`, `ExponentialHeightFog` |
| The light level's ambient light, reflection capture and fog volume | `PrecomputedLightEnvironmentActor`, `SphereReflectionCapture`, `VolumetricFogInjectionVolumeActor` |
| Some stages' meshes | the classes in the stage's `show_classes` |

Never shown: collision-only meshes (`CL_...`) and anything in the stage's `keep_hidden`.

The order matters. If the stage's lights come on while the simulator's own lighting levels are still showing, the
scene stays dull after those are hidden (seen on Inside the Lifestream). The mod switches the stage's lights on only
while none of the simulator's lighting levels is visible, or after 12 s regardless.

Characters are lit by more than the lamps. They take their ambient light and exposure from a light environment
(`PrecomputedLightEnvironmentComponent`), and the exposure also from brightness probes
(`PrecomputedBrightnessEnvironmentComponent`). Two things go wrong when a stage is streamed:

- The simulator's own light environment (in `0000-COMON_VR_Light`) stays on under the stage, and a stage's light levels
  can bring several of their own. A stage that names `light_environment` keeps only that one on and switches the
  simulator's off for the visit (it is put back with the rest of the simulator's look).
- The brightness probes keep their places in the map's own coordinates, which do not move with the level. A stage with
  `move_brightness_probes` has them moved by its levels' offset.

Without both, the party on the Temple of the Ancients stage was near-black.

A stage can also set its own look for the visit. The Temple's second-phase hall is the first-phase hall built upside
down: its colonnade is at the top, so the game's sun lights only the upper walls, and a streamed copy has no baked
light to fill the rest. `lamp` moves one of the stage's own spotlights (by name) to a place relative to the arena's
centre and aims and sets it: the Temple's is one of its light level's unused lamps, put inside the colonnade on the
side the sun comes from and aimed down into the hall, with a cool tint so the warm stone does not turn orange.
`render_settings` sets console variables for the visit and puts back the game's values afterwards (the Temple switches
off the massive-environment shadow culling, which made the sunlit patches jump as the camera moved).

## The fight's start

The game starts the fight on its own schedule once the simulator is loaded, which on a fast machine is before the mod
has finished setting up a stage (2.4 s after arrival on ours, with the stage ready at about 6 s). If the fight begins
behind the black screen, the mod holds the world's clock still (`SetGlobalTimeDilation` at the engine's minimum) and
lets it go as the screen lifts.

## The picker's Replay row

The remembered choices (`choices.txt`, one `course key = stage id` per line) also keep the last stage picked on any
course, as `last = <stage id>`. When the selected course can use that stage, the picker's first row is
"Replay: <stage name>", so the last stage is one press away; the stage keeps its own row further down too.

## The stages

`data/stages.json` describes each stage; `tools/build_lua_data.py` writes it into `Scripts/stage_data.lua`.

| Field | Meaning |
| --- | --- |
| `levels` | Level packages to load, in order. They are asked for 48 at a time, more as the helper answers: the helper holds at most 64 unanswered requests |
| `sky_level` | Loaded last; when a stage brings a sky, the simulator's sky is hidden. An indoor room is still lit by its region's sky (its sun, fog and reflection capture), so the story arenas load the sky their boss fight uses |
| `indoors` | The simulator's sky (its light and post-process) is hidden even without a `sky_level`; otherwise it washes an interior out |
| `own_ground` | The stage has its own floor and walls: the simulator's flat floor stops colliding too |
| `anchor` | The point in the stage's own coordinates that lands on the simulator's centre: the arena's centre at the height of its ground |
| `radius_m` | Clear radius the stage offers; a course is offered the stage if its enemies need no more |
| `show_classes`, `keep_hidden` | See Lighting |
| `light_environment`, `move_brightness_probes` | Character lighting: see Lighting |
| `lamp`, `render_settings` | The stage's own look for the visit: see Lighting |
| `fit` | Stretch along X and Y about the arena's centre, and which actors to stretch, move or leave alone |
| `unlock` | A story flag, a chapter progress, or the game finished |
| `experimental` | Not offered unless the `experimental` setting is on |

### Edge of Creation (`space_rock`)

Levels: `3120-CAPTL_Sephiroth_1Cosmo_Terrain_Strip`, `_Light`, `_Gimmick`, `_Effect`,
`3120-CAPTL_34Sephiroth1CosmoNatureMini_Terrain_Strip` and the far-land level
`LastBattle/FarLand/3120-CAPTL_Sephiroth_1Cosmo_Terrain_FarLand`. Sky: `0001-WORLD_IslandSky_Space`.

- The platform is the skeletal ground piece `BG2130_00` plus 39 ground meshes in the Gimmick level, all arriving
  hidden. Its walkable top is 98 to 134 cm above the level's z = 0, so the anchor height is 110.
- Its level top, read from the mesh file (`tools/rock_outline.py`), is an irregular oval of about 52 m by 35 m.
  `tools/rock_fit.py` finds the smallest stretch that puts level rock under every metre of the arena: 1.08 along X and
  1.70 along Y about the top's centre. Heights are left alone.
- The floating rocks are the far-land mesh (the whole island and the rocks round it, low detail) and four rock
  effects. They keep their true size and place. The far-land mesh carries a low-detail copy of the platform that would
  poke through the real one, so it is lowered by a metre.
- Cutscene props (`Quest_...`) stay hidden.

### Inside the Lifestream (`lifestream`)

Levels: `3120-CAPTL_Sephiroth_6LastSpace_Terrain_Strip`, `_Light`, then the sky level `0001-WORLD_OtherSky_White`, and
the sky `0001-WORLD_IslandSky_Galaxy`.

- The floor is 25 water meshes that arrive hidden, flat at z = 100 (the anchor height).
- The battle's sky is the Galaxy sky (the game's cutscene table names it for the scene tied to these levels). On its
  own it is too dark; loading the white sky level first, with its own sun and fog kept hidden, gives the look of the
  real fight. Of the Galaxy sky's ten fog variants only the centre one is shown.
- Its far-land level is not loaded: it is a flat water plane up to 40 cm above the floor.

### Gilgamesh's Garden (`gilgamesh_garden`)

The game ships a second look for the simulator's own level, used by Gilgamesh's legendary trials:
`0000-COMON_VR_Gilgamesh_Terrain_Strip`, `_Light` and `_Effect`, centred on the simulator's own origin, so it needs no
offset or fit. Its meshes, lights, effects and backdrop arrive hidden. It keeps the simulator's sky: without it the
scene is black. Unlock: `stfArea0001_Gilga_StoryHub_Clear`.

### The story arenas: Mythril Mine, Cave of the Gi, Shinra Manor

Each loads the rooms round its boss's territory, centred on the territory and lowered to its floor:

- its terrain, light and time-set levels, as the area's own streaming volumes list them (read from the area's main
  level, such as `1230-MYTHM.umap`, with `tools/dump_level.py`);
- its `Gimmick` and `Physics` levels (props, doors, breakable boxes; Shinra Manor's floor door is shown, closed as in
  the fight);
- its floor and wall collision in the `AutoGenCollision` grid levels where the terrain does not collide by itself
  (the Cave of the Gi loads all 28 cells; the mine's terrain collides on its own);
- a region sky: Nibelheim's night for the manor, the mountain cave for the cave and the mine. Without one, the sides
  of the room were dark and, in the mine, the party was almost a silhouette.

Clear radius: the mine 15 m, the cave 18 m, the manor 13 m, so the largest summon courses do not offer them. Unlock
by chapter progress (Chapters 4, 11 and 12), an approximation of when the story reaches each.

### Midgar Outskirts (`midgar_outskirts`)

Zack's prologue fight outside Sector 5's wall. Its two battle territories (`4000MIDGR_mob_01` and `_02`) share a
centre at (-470, 68340, 60) with an escape wall 50 m across. It loads the `020_5thOutWall` set that the area's
`EndStreamingVolume_5thOutWall` loads there (terrain, light, effects, glow, the gate, physics), the day time set, and the
outer wall's four `Terrain_Grid` collision cells with their `GridPhys` cells. With one cell, the ground ended about 6 m
east of the centre; with all four, the capsule probe found ground within 60 cm of the centre's height across the arena.
Its sky is `ZaxSky_Day`, which the prologue cutscenes name. The simulator's floor goes (`own_ground`). Clear radius 25 m,
so every summon course but Phoenix's (28.3 m) offers it. Offered from the start.

The three downed helicopters are not included. The story script places them (prop model
`VE0015_00_FallenHeli_Standard`, at markers in `4000-MIDGR_LevelPlan_Resident`), and the model is not in memory in the
simulator; placing them would need the native helper to load it from disk.

### Temple of the Ancients (`red_dragon`)

The Red Dragon's hall in the Temple's maze, as in the fight's second phase. Territory `TEMPL_RedDragon`; the game's own
volume for the fight (`3110-StreamingVolume_Env_MazeRoomA_Boss`) loads the `025_RedRoomA` levels, and its physics volume
adds `RedRoomA_Physics` and `RedRoomB_Physics`. `RedRoomB` is the second phase: the same hall built upside down, 97 m
below the first, so that the party can fight "on the ceiling" without the game turning gravity. The stage loads
`RedRoomB`'s levels, `RedRoomA`'s light level (it holds the lights for both), the maze's time set and its sky
(`IslandSky_DayMaze`). Floor at -15479, flat over 48 m by 48 m; walls 24.2 to 24.7 m from the centre, so radius 24 m:
every summon course but Odin's (24.9 m) and Phoenix's offers it. Character light: `DoorA_1` from the maze's time set.

The first phase (`RedRoomA`) was tried first and dropped: its massive-environment terrain drew the floor, the
colonnade and the vault but not the tall walls on two sides, whatever else was loaded and whatever the renderer's
settings; the same terrain turned 180 degrees drew nothing. The second hall draws in full.

### Planned stages that do not work yet

The six regional boss arenas and the open-world boss arenas (Grasptropod, Anuran Suppressor, Gilgamesh's island) are
in `data/stages.json` with `experimental: true`. Streamed to the simulator, their ground does not appear: it is the
game's open-world (massive-environment) terrain, which did not draw at the new place when we tried Nibel. Moving the
simulator to the arena instead (`route = move`, writing the arena's position into `TargetLocation`) was ignored once
the simulator had been visited; a first visit after starting the game is untested.

The Temple of the Ancients arena (Reno and Rude) was built and then removed: parts of its floor are skeletal meshes
that the cutscene before the fight moves into place, and its Lifestream ribbons are effects the story spawns, not
placed in any level. Both would need assets loaded from disk, which UE4SS's Lua cannot do on this game.

For 1.2.0 we drafted four more stages and kept only Midgar Outskirts. Tseng and Elena's courtyard on the Temple's
second floor had the same invisible-floor problem as Reno and Rude's plaza. The Altar at the Forgotten Capital's set
showed Jenova's tissue rather than the fight's tiled floor. Neither reactor draft was the room the owner meant.
[Next stages research](research/NEXT-STAGES.md) keeps the details.

## The native helper

UE4SS 3.0.1's Lua cannot call `LevelStreamingDynamic.LoadLevelInstance` on this game (its `bool` out-parameter breaks
the argument stack), so a small C++ UE4SS mod does the loading. Lua and the helper talk through files in the mod's
folder:

| File | Written by | Holds |
| --- | --- | --- |
| `stages-helper.txt` | helper, twice a second | its tick, whether its checks passed, whether the package loader is busy |
| `stages-request.txt` | Lua | `load`, name, package, x, y, z, yaw; or `unload`, name |
| `stages-ack.txt` | helper | name, `loaded`, `unloaded` or `refused`, and a reason |

The helper serves one request per frame from a game-thread safe point, loads only while the package loader is idle
(or after 8 s), and unloads with `SetIsRequestingUnloadAndRemoval`. Its game-thread check, code-byte checks and
loader-idle check are copied from our Junon Colosseum helper by `tools/make_helper_source.py`; they know two game
builds (the January 2025 Steam build and 1.005 on the Epic Games Store) and switch the helper off on any other.

## Courses

`data/courses.json` (from the game's tables, by `tools/make_courses.py`) gives each of the 75 simulator courses its
title id, English title and the radius its enemies need: 12 m for ordinary rounds, up to 28.3 m for Phoenix. Courses
other mods add are in `data/mod_courses.json` (Training Dummy's three). The eight Shinra Manor courses (`_NIBLS_`) are
left out; they use the same simulator level through another content volume.

## Files the mod writes

In `ue4ss/Mods/SimulatorStages/`: `choices.txt` (the stage chosen for each course), `stages-log.txt` (what it did on
each visit, with times), and the three helper files above. Nothing goes into the save.

## What was tested

On FINAL FANTASY VII REBIRTH 1.005 (Epic Games Store), UE4SS 3.0.1 with our 1.005 fix, a save that has finished the
game. Fights were driven by a test harness with the game's Classic mode or the harness's combat autopilot, and by the
owner by hand.

1.1.0:

- Every stage on at least two different courses: all six summon courses, Grasslands and Corel battle courses, and the
  Training Dummy DPS course; a three-round course kept its stage for every round.
- Visits back to back across all six stages after the fix for objects kept within a visit: 43 stage loads and 41
  exits on 2026-11-18 with no crash during a visit (one crash that evening came a minute after a save load, with no
  stage loaded; see LIVE-RESULTS). Before the fix the game crashed about 9 times that day, over 64 stage loads (not all of those crashes during a visit).
- The swap behind the black screen: one frame a second from the confirm.

1.0.0:

- Both stages through the picker, many times, on Grasslands courses and the Training Dummy DPS course, solo and with a
  party of three, with a summon (Odin) called on Edge of Creation; levels released on leaving every time.
- Movement on both stages; ground heights measured by dropping the party's capsule on a grid.
- The swap: one screen frame a second from the confirm on a first visit.
- Six visits in a row in one session after the "Get Ready" fix.
- Inside the Lifestream's lighting on a first and a later visit after the lighting-order fix.

Not tested: the Steam version, other UE4SS builds or settings, a save that has not finished the game, the tutorial
courses, controller input in the picker, and playing the game's own Chapter 14 fights with the mod installed (the mod
acts only on Combat Simulator visits and only on its own copies of the levels).
