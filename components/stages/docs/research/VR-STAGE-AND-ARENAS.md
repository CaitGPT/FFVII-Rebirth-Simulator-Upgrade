# The simulator's stage and the six boss arenas (offline research, 2026-11-16)

No game, harness, install or save was touched. Sources: the installed game's containers (read-only, with the FF7R
retoc fork: `to-legacy --no-shaders -f <filter>` into a scratch folder), the table CSVs in
`D:\FF7RebirthModding\DataTableIndex\Input`, the layout index, the UE4SS header dump and FFVII-Modding's
`FF7R_Indexer/level_layout_points.py` as the level reader. No game files are reproduced here.

Tags: **[static]** read from game data · **[inferred]** reasoned from static data · **[guess]** untested.

## 1. The simulator's stage

### 1.1 What it is made of [static]

| Level | Holds |
| --- | --- |
| `0000-COMON/VR/0000-COMON_VR` | Two volumes (`VRContent`, `VRContentNIBLS`) that stream the terrain and light levels; level script naming the flags `stfCmn_IsInVR_EASTC` and `stfCmn_IsInVR_WESTC` |
| `…/Layout/0000-COMON_VR_Terrain_Strip` | The floor prop `BG0342_00_Floor_VR_C`; ten rotating blocks and pillars (`BG1127_*`, `BG1128_*`) 140 to 290 m out; three flat collision assets; volumes that stream the battle levels and the effect and sound levels |
| `…/0000-COMON_VR_Light` | 16 spotlights, a precomputed light environment |
| `…/0000-COMON_VR_Effect` | Three Niagara actors (`FX_0000-COMON_VR_Cube_01`) |
| `…/0000-COMON_VR_Sound` | One audio volume |
| `…/0000-COMON_Btl_Navigation_Mod` (+ `_ServerBuild`) | `VRBattle_TerritoryCmnActor` and three Gilgamesh-quest territories, 264 `EndTargetPoint`s, 26 AI recognition volumes, result and entry cameras |
| `0001-WORLD/Layout/Lighting/VR/0001-WORLD_VRSky` | One directional light, fog, post-process volume, reflection capture, sky texture `T_VrRoomSky` |

Positions inside the stage level: the centre point `oblPointCmn_VrBattle_Center` is the level's origin, floor at z = 0;
`oblPointCmn_VrBattle_Player01` at (590, 0, 2); `oblPointCmn_VrBattle_ENEMY01` at (−470, 0, 0); the territory actor at
(50, 50, 142).

The 264 points include ones enemy scripts name: `SephirothMagic*`, `SU2010_*` (Odin), `SU2030_*`, `SU2040_01_*`,
`EN2216_WarpTargetPoint_*` (Mindflayer), `EN2101_*`, `RudeSpecial_*`, `ElenaSpecial_*`, and the summon entrance points
`oblPointCmn_End2VrBattle_*` that `ColosseumSceneData` rows use.

### 1.2 How it is placed in the world [static]

Each world's plan level has an `AEndStreamingVolume` labelled `COMMON_VR`:

| World | Level | Actor | `TargetLocation` | `HideLevelsInstead` |
| --- | --- | --- | --- | --- |
| East continent | `1000-EASTC_WorldPlan` | `1000-StreamingVolume_VR_Battle` | (−200000, −100000, 60000) | 45 levels: sea, Midgar, far terrain of Grasslands and Junon |
| West continent | `2000-WESTC_WorldPlan_MiniGame` | `2000-StreamingVolume_VR_Battle` | (−200000, −100000, 10000) | 117 levels, including Corel's own terrain levels |
| Gilgamesh's island | `0110-GILGA_WorldPlan` | `0100-StreamingVolume_VR_Battle` | (350000, 120000, 30000) | none |
| Gold Saucer | `2350-GOLDS_WorldPlan` | `2350-StreamingVolume_VR_Battle` | not read | not read |

Each streams `0000-COMON_VR` and is `bForce`, `bDisabled` (something enables it when the simulator starts).

The header dump gives `AEndStreamingVolume` these reflected members: `StreamingLevels`, `HideLevelsInstead`,
`TargetLocation` (FVector), `TargetRotationDegree`, `bDisabled`, `VolumeLabel`, and the functions
`EnableStreamingVolume(bool)`, `ShowHideStreamingLevels(bool, bool)`, `ShowHideInsteadLevels(bool, bool)`.

**The game already streams these stage levels at another offset.** The same plan levels hold volumes labelled
`EV_COMON_2010` and `SUB_EV_COMON_2010` that stream `0000-COMON_VR_Light` and `0000-COMON_VR_Terrain_Strip` at
(−80000, −80000, 50000) for a cutscene. Other small stages are placed the same way (the card game at
(20000, 20000, 50000), a Moogle cutscene set at two offsets).

### 1.3 A second look the game ships [static]

`0000-COMON_VR_Gilgamesh_Terrain_Strip`, `_Light`, `_Effect` and `_Sound`: 70 static meshes within 35 m of the same
origin, 62 point lights, a post-process volume, eight Niagara actors, its own collision in four grid levels listed by
`0000-COMON`. Its terrain level streams the same battle and navigation levels, and its territories are
`entr_0000COMON_GilQuest_010/020/030` in the shared battle level. [inferred] The Gilgamesh trial fights use it.

### 1.4 Courses [static]

`Colosseum.csv`: 75 of 125 courses have `IsVRMission 1`, `BattleWarpPoint Point_VRBattle`, an empty `UserLevelName`
and `TerritoryActorName VRBattle_TerritoryCmnActor`. The 33 Gold Saucer and 17 Corel Prison courses name their own
battle plan level, warp point and territory actor.

## 2. The six classified intel arenas

`WorldReport.csv` has one row of `ReportIconType 8` per region. Its `Hub` row names the control object, whose
`EnemyTerritory` row and `ObjectEnemy` row give the boss. The territory actors are in each region's
`<region>_World_Navigation_Mod` level, their spawn and summon points in `…_ServerBuild`.

| Region | World report | Finish flag | Territory | Boss template |
| --- | --- | --- | --- | --- |
| Grasslands | `WorldReport_GRASA_31` | `stfWorldReport_Finish_GRASA_031` | `Grassland_midgamob_15` (tables and level under `1100-MIDGA`) | `EN2207_00_Quetzalcoatl_StandardEnd2` |
| Junon | `WorldReport_JUNOA_26` | `…_JUNOA_026` | `JunonEastArea_mob_13` | `EN2216_00_Mindflayer_StandardEnd2` |
| Corel | `WorldReport_CORLA_31` | `…_CORLA_031` | `Corla_mob_07` | `EN2017_02_Tonberry_KingEnd2` |
| Gongaga | `WorldReport_GONGA_26` | `…_GONGA_026` | `Gongaga_west_mob_04` | `EN2016_01_Morbol_GreatEnd2` |
| Cosmo Canyon | `WorldReport_CSMOA_31` | `…_CSMOA_031` | `CsmoaSubjugation_mob_Ex` | `EN2243_00_Jabberwock_StandardEnd2` |
| Nibel | `WorldReport_NIBLA_25` | `…_NIBLA_025` | `NiblaEastArea_mob_Ex` | `EN2200_04_Zuu_KingEnd2` |

Geometry, in centimetres. Ground height is the actor's z plus the ServerBuild partner's centre ground summon point;
"spread" is the range of its four ground summon points 8 m from the centre.

| Region | Actor centre (x, y, z) | Ground z | Spread | Wall diameter | Actor yaw |
| --- | --- | --- | --- | --- | --- |
| Grasslands | (36535, −46540, 12570) | 11813 | 193 | 8000 | −52.9 |
| Junon | (32407, 165564, 429) | 131 | 74 | 3100 | −128.3 |
| Corel | (150268, 40601, 1804) | 934 | 12 | 2900 | 288 |
| Gongaga | (−19868, 308897, 2803) | 2593 | 14 | 4400 | 0 |
| Cosmo Canyon | (−209585, 121425, −26) | −89 | 26 | 3900 | 5 |
| Nibel | (−141341, −177374, 1544) | 550 | 20 | 4000 | 50 |

Cross-checks [static]: Corel's retry point `RetryPoint_Hub_C_7_1` is at z 933 and Nibel's `RetryPoint_Hub_F_Ex` at
z 525, both close to the ground heights above.

Every territory is `ExternalEnemies`, a cylinder, with `UseDisableEscapeInvisibleWall`. Their `EnemyTerritoryLevel`
rows have `UnableBattleEscape`, `ForceBattleInAllEnemies` and a hard-mode reward. Their object rows start in
`scg<region>_Hub_Ex_Territory_off`; [inferred] the boss is present only while its intel is open and unfinished.

Scenery [static]: each region's terrain, grass, trees, lights and effects are region-wide levels
(`<region>_Terrain_Strip`, `…_Light`, `…_TimeSet_Day`, FarLand levels and so on), not per-arena sets.

Skies [static, from Club Duel's research]: `Sky_Grass` (default `GrassSky_Day`), `Sky_Junon` (`JunonSky_Day`),
`Sky_SouthSea` for Costa del Sol, Corel and Gongaga (`SouthSeaSky_Day`), `Sky_Nibel` (`MountSky_Day`). Every one lists
a `VRSky` label. Cosmo Canyon's volume is not identified yet.

## 3. What other mods do

- **VR Lighting Change 1, 2, 3** (Eulymedon; Nexus 1173, 1204, 1584): recolours or relights the simulator. One look
  per installed file; the pages say it can't change per battle. Files not downloaded or inspected.
- **VR Simulator Overhaul** (NSK01; Nexus 1165): story bosses in the simulator through table edits. In the OpenFF7R
  Discord its author said the battle space could not be relocated (July 2025) and that imported bosses break without
  their home arena's points.
- **Scenery** (YIIS; named in the Discord): switches skies by region. Not found on Nexus.

## Reproducing

```
retoc to-legacy --no-shaders -f "0000-COMON/VR/" "<game>/End/Content/Paks" <out>
retoc to-legacy --no-shaders -f "Navigation_Mod" "<game>/End/Content/Paks" <out>
retoc to-legacy --no-shaders -f "1000-EASTC_WorldPlan.umap" "<game>/End/Content/Paks" <out>
retoc to-legacy --no-shaders -f "2000-WESTC_WorldPlan_MiniGame" "<game>/End/Content/Paks" <out>
```

Each takes 10 to 30 seconds. Read the results with `FF7R_Indexer/level_layout_points.py` (`LegacyPackage`,
`properties`), as Club Duel's `dump_level.py` does (`D:\FF7RebirthModding\Mods\ClubDuel\research\`).

## 4. The final battle stages, and which boss stages are their own sets (added 2026-11-16)

The owner asked about the two Sephiroth final-fight stages: the white void (with Aerith) and the rock in space (with
Zack).

### 4.1 The final battle [static]

The Forgotten Capital map `3120-CAPTL` holds one switch volume, `EndStreamingSwitchVolume_3120_Boss` (label
`3120_CAPTL_JenovaLife_1`), that swaps ten stage sets in at one place. Each set is five small levels under
`3120-CAPTL/Layout/LastBattle/` (`_Terrain_Strip`, `_Light`, `_Effect`, `_Gimmick`, `_Sound`, some with extra
`NatureMini`, `Interior` and `FarLand` levels):

| Switch label | Contents |
| --- | --- |
| `3120_CAPTL_JenovaLife_1`, `_2`, `_2B`, `_3` | Jenova Lifeclinger's phases |
| `3120_CAPTL_Sephiroth_1Cosmo` | 39 static meshes and one ground prop, about 36 m by 24 m around (−40, −9800); its own uneven terrain collision (5 assets); a post-process volume; 4 Niagara actors |
| `3120_CAPTL_Sephiroth_2CosmoDes` | The same place broken up: floating-island and ground props, 12 point and 4 spot lights, 31 Niagara actors, 12 `FeelerLaser01` gimmick actors |
| `3120_CAPTL_Sephiroth_3Jenova` | Collision, 14 point lights, 34 Niagara actors |
| `3120_CAPTL_Sephiroth_4Church` | 131 + 16 static meshes, a church floor and door prop, 20 collision assets |
| `3120_CAPTL_Sephiroth_5Jenova` | Collision, 2 spot lights, 15 Niagara actors |
| `3120_CAPTL_Sephiroth_6LastSpace` | 27 flat floor meshes covering about 448 m by 448 m at z 0 to 1 m; no lights, one post-process volume; 16 `BG1135_00_DummyWall` actors with AI recognition volumes in a ring 25 m in radius around (−10000, 0) |

The skies are separate levels switched by `3120-StreamingSwitchVolume_Sky` (label `3120-Sky`): among its labels are
`IslandSky_Space`, `IslandSky_Galaxy`, `IslandSky_Meteor`, `OtherSky_White`, `OtherSky_Sephiroth`,
`3120-CAPTL_EV8990_WhiteSky`, `LayerSky_Church_Day` and `IslandSky_Jenova`.

[inferred] `Sephiroth_1Cosmo` with `IslandSky_Space` or `IslandSky_Galaxy` is the rock in space (Cloud and Zack), and
`Sephiroth_6LastSpace` with a white sky is the white void (Cloud and Aerith). Which sky label goes with which set is
not read yet.

These sets are in a different map from the continents, so the simulator cannot be moved onto them. They would be
streamed to the simulator instead: load the set's levels at the simulator's position with an offset that puts the
set's fight centre on the simulator's centre, and load its sky level. Nothing loaded in the continent world names
these levels, so that needs a level-load call (`LevelStreamingDynamic.LoadLevelInstance`, which Junon Colosseum's
native helper already makes; a Lua call fails in UE4SS 3.0.1).

### 4.2 Boss stages that are their own level sets [static, from level names]

- The ten final battle sets above.
- `0000-COMON_VR_Gilgamesh_*` (already centred on the simulator).
- `1360-FERRY_BOSSBattle_*` (the ship's cargo hold fight).
- `2360-UNDRS_Dyne_*` and `2360-UNDRS_Battle_*` (Dyne; the Corel Prison colosseum).
- `2350-GOLDS_SQBattle_*` (the Battle Square) and `2355-LVLES_Arena_*` (the Loveless stage).

Every other boss room found so far is part of its dungeon's or town's general levels, not a set of its own.

## 5. How much space a course needs, and how stages are picked (added 2026-11-16)

### 5.1 Space [static]

Distance from the stage centre to the furthest of the simulator's scripted points, by the enemy that owns them
(`0000-COMON_Btl_Navigation_Mod`; names follow the enemy's code):

| Points | Enemy | Furthest |
| --- | --- | --- |
| `SU2040_*` | Phoenix | 28.3 m |
| `SephirothMagicLightning*`, `HLightningMagic*` | Sephiroth | 26.5 m, 26.0 m |
| `SU2010_*` | Odin | 24.9 m |
| `EN2216_WarpTargetPoint_*` | Mindflayer | 22.4 m |
| `SU2030_*`, `…Alexander_Appear` | Alexander | 22.0 m |
| `obl_VR_mu_*` | Mu, in rounds with `UsePopTargetPoint` | 18.0 m |
| `TargetPoint_VRBattle_8eye_*` | 8eye | 15.7 m |
| `…End2VrBattle_EnemyFar` | summon entrances | 13.7 m |

Ordinary spawns: the largest `PopOffset` in a simulator course's `ColosseumPositionData` row is 6.4 m from the enemy
point, which is 4.7 m from the centre; the party starts 5.9 m the other way. `tools/make_courses.py` turns this into
`needs_m` per course: 12 m for ordinary rounds, 14 m for a summon with no points of its own, otherwise the enemy's
furthest point. Of the 56 courses in scope, 39 need 12 m and 12 need 18 m or more.

[inferred] Two courses are marked 26.5 m only because an enemy template's name contains "Sephiroth"
(`EN3001_04_VagidPolice_SephirothEnd2`); whether that enemy uses Sephiroth's points is not known. `needs_m` says where
scripted points are, not how far a fight roams.

Stage sizes: a world stage's `radius_m` is half its boss territory's wall, an estimate of the clear ground.

### 5.2 The menu [static, header dump]

`UEndColosseumMenu` has the events `OnCourseMenuPressedItem(CellIndex)`, `OnCourseMenuSelectedIndexChanged(CellIndex)`,
`OnTagMenuSetupItem`, `OnCharaSelectMenu*`, `OnSummonLevelSelectMenu*`, `OnYesButtonPressed`, `OnNoButtonPressed`, and
the widgets `InfoWindow` (`Txt_CourseTitle`, `Txt_Info`), `ConfirmWindow` and `DifficultyWindow`. It has no property
naming the selected course. `UEndMenuAPI` has `GetString(TextId)`, `ShowMessageWindow`, `IsMessageWindowClosed`,
`GetMessageWindowSelectedIndex` and `HideMessageWindow`. `GetPartyLeader` is on `UEndBattleAPI`.

### 5.3 What unlocks a region's boss [static]

The classified intel opens when a hidden group of the region's Lifespring hubs (`HubGroup_Area_<n>_ExSubjugation`)
reaches its completion number: 4 of 6 in the Grasslands and Gongaga, 4 of 4 in Junon and Nibel, 6 of 6 in Corel and
Cosmo Canyon. The group's completion plays a Chadley call that sets `stfHubGroup_<region>_ExBattle_Open`. The mod's
unlock is the boss's defeat, `stfWorldReport_Finish_<region>_<n>`.

### 5.4 The Shinra Manor simulator [static]

`COL30_NIBLS_01` to `_08` ("Preliminary Trial: …" and "Evaluation: …"), one round each, three free party members,
using the content volume `VRContentNIBLS` and the flag `stfStory_NIBL_VR_on`. Excluded by the owner.

## 6. Streaming every stage, and the story-boss arenas (added 2026-11-16)

### 6.1 The story bosses the owner named [static]

From each location's `ObjectEnemy` and `EnemyTerritory` tables and its `Btl_Navigation_Mod` level:

| Boss | Template | Territory | Level | Centre (x, y, z) | Wall |
| --- | --- | --- | --- | --- | --- |
| Mythril Golem | `EB2030_00_MythrilGolem` | `MYTHM_MythrilGolem` | `1230-MYTHM_Btl_05_06_Navigation_Mod` | (8320, 114280, 2070) | none |
| Grasptropod | `EB2060_00_CatchMech` | `COSTT_CatchMech` | `2110-COSTT_Btl_Navigation_Mod` | (219740, -127985, 120) | cube, 73 m |
| Anuran Suppressor | `EB2100_*_PalmerMech` | `UNDRS_PalmerMech` | `2360-UNDRS_Btl_Navigation_Mod` | (3290, 37910, 3490) | 29 m |
| Gi Nattak | `EB2140_00_GiNattak` | `GIZOK_GiNattak` | `2550-GIZOK_Btl_Navigation_Mod` | (-157410, 52390, -47610) | none; spawns reach 20 m |
| Galian Beast (Vincent) | `EB2160_00_VincentValentine` | `NIBLS_VincentValentine` | `2650-NIBLS_Btl_Navigation_Mod` | (-28630, -231660, 2680) | 26 m |
| Reno and Rude | `EB0003_00_Reno`, `EB0005_05_Rude_Temple` | `Templ_Rude` | `3110-TEMPL_Btl_Navigation_Mod` | (-30420, -133620, -6870) | none |
| Gilgamesh | `SU2060_02_Gilgamesh_Boss` | `GILGA_Gilgamesh_Boss` | `0110-GILGA_Btl_Navigation_Mod` | (415437, 122683, 4220) | cube, 43.7 m |

None of these territories has a ServerBuild partner with ground summon points, so the ground height under them is
not known; the centre's z is the territory actor's own.

Other story bosses by location, for later: Midgardsormr (`1220-SWAMP`), Terror of the Deep (`1310-JNONV`), Jenova
Emergent (`1360-FERRY`), the Mt. Corel bosses (`2250-CORLM`), Rufus, Rude and others at the Gold Saucer
(`2350-GOLDS`), Dyne and Palmer (`2360-UNDRS`), the Gongaga reactor bosses (`2420-GONGM`), the Shinra Manor's Forgotten
Specimen (`2650-NIBLS`), Materia Guardian (`2660-NIBLM`), Red Dragon and Demon Gate (`3110-TEMPL`), Jenova Lifeclinger
and Sephiroth (`3120-CAPTL`).

### 6.2 What a stage has to load [static, heuristic]

`tools/select_levels.py` converts nothing itself: it reads a location's legacy-converted `Layout` folder and chooses
levels that place a mesh, light or effect within 120 m of the arena's centre, plus 'massive' terrain levels of the
same sub-area. Sizes are the level files themselves (meshes and textures are separate assets).

| Stage | Location's layout levels | Chosen | Level data |
| --- | --- | --- | --- |
| Nibel | 68, 1.0 GB | 6 | 133 MB |
| Anuran Suppressor | 56, 0.9 GB | 3 | 131 MB |
| Galian Beast | 25, 0.3 GB | 8 | 247 MB |
| Corel | 91, 2.4 GB | 6 | 255 MB |
| Gi Nattak | 50, 0.4 GB | 19 | 271 MB |
| Grasslands | 26, 0.6 GB | 5 | 421 MB |
| Gilgamesh | 21, 0.6 GB | 10 | 421 MB |
| Mythril Golem | 51, 0.8 GB | 21 | 431 MB |
| Cosmo Canyon | 137, 3.0 GB | 10 | 447 MB |
| Grasptropod | 51, 0.7 GB | 10 | 448 MB |
| Gongaga | 81 | 8 | 518 MB |
| Reno and Rude | 245, 2.0 GB | 56 | 1107 MB |
| Junon | 95, 2.4 GB | 17 | 1147 MB |

No boss room here is a level set of its own: each is inside its dungeon's or region's terrain level, so a stage
brings the surrounding area with it. Only the final battle's sets (section 4) and the game's own simulator stages are
small.

### 6.3 Why streaming at an offset should work [static]

- `AEndStreamingVolume` has `TargetLocation` and `TargetRotationDegree`, and the game uses them for the simulator
  itself, a simulator cutscene set, the card game and a Moogle cutscene set (section 1.2).
- `LevelStreamingDynamic.LoadLevelInstance` takes a location and rotation. Junon Colosseum's helper calls it in the
  game with both at zero; calling it with a position is untested.
- Terrain levels hold their meshes behind a `MassiveEnvironmentStreamingProxy`. The simulator's own Gilgamesh terrain
  level has one and is shown at the simulator's offset, so that system handles an offset in at least that case.
  [guess] Whether it does for a level instanced by `LoadLevelInstance` is the main thing the first streamed probe
  has to show.

### 6.4 Skies for the final battle [static]

The cutscene volume `EV_FOREE_8672_IslandSky_Space` streams `0001-WORLD_IslandSky_Space` together with
`Sephiroth_1Cosmo_Light` and the `2CosmoDes` levels, so that sky belongs to the rock in space. For the white void the
sky is a guess (`0001-WORLD_OtherSky_White`); the final battle's sky volume also lists `3120-CAPTL_EV8990_WhiteSky`.
The boss-stage switches are `Action` rows of type 241 (`act3120_SwitchVolume_Boss_To_<set>`); the sky switches for
those phases are not in the tables, so they are probably in cutscene clips.
