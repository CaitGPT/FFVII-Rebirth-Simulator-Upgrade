# Stages after 1.1.0 (2026-11-19)

The owner asked for four more stages: the Tseng and Elena arena, the Altar at the Forgotten Capital, the large atrium
inside the Nibelheim reactor where the Diabolic Variant is fought, and Zack's prologue fight beside the downed
helicopters outside Midgar. Each was drafted offline from the game's files (the Steam build's containers, read with
retoc and FF7R_Indexer) while the game was in use, then tried in the game.

**Outcome (owner, 2026-11-19):** only Midgar Outskirts ships, in 1.2.0. The other drafts were removed from
`data/stages.json`; what we learned about them is below so the work is not repeated.

## How each was found

- **The arena's place:** the boss's row in the area's `EnemyTerritory` table, then its `EndFieldEnemyTerritoryActor`
  in the area's battle navigation level (centre, shape, wall).
- **The levels:** the streaming volume the game itself uses at that spot, read from the area's main level
  (`tools/dump_level.py`, then the nearest volumes and their level lists and switch sets).
- **The sky:** the area's cutscene table (`CutSceneList`, its `DebugSkySwitchLabel`) for the scenes at that place.
- **The collision:** `tools/select_collision.py` for the grid cells within 30 m of the centre.

## Midgar Outskirts (`midgar_outskirts`): ships in 1.2.0

- **Where:** `4000-MIDGR`, Zack's prologue fight against Shinra soldiers outside Sector 5's wall. Territories
  `4000MIDGR_mob_01` and `_02` share a centre at (-470, 68340, 60) with an escape wall 50 m across.
- **Levels:** the `020_5thOutWall` set that `EndStreamingVolume_5thOutWall` loads there (terrain, light, effects,
  glow, the gate, physics), `TimeSet_Day`, the outer wall's `Terrain_Grid` cells and `GridPhys` cells 1000002,
  1000003, 3001002 and 3001003.
- **Sky:** `ZaxSky_Day`, from the prologue scenes EV_MIDGR_0020 to 0030.
- **Live:** loads; the floor probe finds ground within ±60 cm across the centre once all four `GridPhys` cells are in.
  Four autopilot courses (Titan solo, Alexander with the party, two Grasslands courses), 90 s each: the stage was in
  3 to 7 s after arrival every time, and the game stayed up. One load in three after a harness restart froze the game
  for a minute and then ended it silently (no crash dump), two to four seconds into streaming; the same happened once
  on the Tseng and Elena draft. Not seen in seven loads before that restart, nor in the four courses above.
- **The downed helicopters:** the wreck is the prop model `VE0015_00_FallenHeli_Standard` (Blueprint
  `/Game/BluePrint/Character/Property/VE0015_00_FallenHeli_Standard`, a skeletal mesh with its own physics asset). The
  story script places three at markers in `4000-MIDGR_LevelPlan_Resident`: `obl4000_Position_helicopter_z1_0a` at
  (-27, 69941, 77), `_0b` at (-1730, 71459, 1524) and `_0c` at (-1608, 67484, 397), 14 to 16 m from the centre, with
  the fire effect point at (-7297, 60427, 645). The model is not in memory in the simulator, and UE4SS's `LoadAsset`
  returns an invalid object for it (live, 2026-11-19), so placing them needs a native "load asset" step in the helper,
  as Junon Colosseum's helper does with `LoadAsset_Blocking`.

## Cut drafts

- **Tseng and Elena** (`3110-TEMPL`, territory `Templ_Elena`, Life Room B on the second floor). The first load at the
  territory's height found ground only 6.6 to 7.5 m below; the room's own pieces sit at z -38,907 to -38,967. With the
  anchor lowered and Life Room B and B02's collision cells added, the probe found an octagonal courtyard about 35 m
  across, but the stage has the same invisible-floor problem as Reno and Rude's plaza next door, which was cut earlier
  because some of its floor sections are only added by a story event. One load in two also ended the game silently,
  two seconds into streaming its 32 levels, with no crash dump or Windows error; the next identical load was fine.
- **Forgotten Capital Altar** (`3120-CAPTL`, the Lifeclinger's phase-one set in `Layout/LastBattle/`, round the
  origin, sky `IslandSky_Jenova`). The `JenovaLife_1` set shows Jenova's tissue, not the reference's pale blue tiled
  floor in water. Untried candidates: the set's massive water terrain, or the Capital's own halls (Hall A, Hall B and
  Basement A, about (34700, -228000)).
- **Reactor atrium.** The owner meant the Nibelheim reactor where the Diabolic Variant is fought. In the tables we read,
  the Diabolic Variant (`EB2110_00_BiologicalBoss`) has a battle spec and territory only in `2420-GONGM` (Gongaga, at
  (134334, 334418, -4648)). The flashback Nibelheim reactor (`2660-NIBLM`, the `Before` levels) has no battle
  territory inside. The owner thought neither draft was the right place. Neither was tried in the game.

## Live test method

With `experimental = true` and `force_stage = <id>` in the installed `settings.txt`, on the Training Dummy DPS course:

1. Load it and read the mod's log: `stream ready`, any `refused` levels (a level missing from Epic 1.005), and
   `activate` counts.
2. Look: photo-mode pictures from the centre in four directions, against the reference shots.
3. Floor: drop the leader's capsule on a grid (`tools/live/probe_height_map.lua`) to set the anchor height and find
   holes; walk to each edge for the radius.
4. Light: compare with the reference.
5. Load, leave and reload, watching for the stale-object crash.
