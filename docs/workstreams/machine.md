# Workstream: the machine next to Chadley

Owner's request (2026-11-20): enter the combat simulator by interacting with the little machine next to Chadley,
rather than talking to Chadley, at every Chadley location; and where both appear, swap the two so the machine is the
easier one to reach.

Development mod: `ue4ss/SimOverhaulMachine` (Lua only, no pak). Keys: none. Tables: none. Settings (`settings.txt`):
`machine_swap = off` keeps the game's positions, `machine_enabled = off` turns the part off. Binds no keys or buttons:
the game's own interact button presses Operate.

✅ seen in game · 🟡 partly · ❌ tried and failed

## How it works

1. Every 2 s in the field, a physics overlap (`KismetSystemLibrary.SphereOverlapActors`, 30 m around the player,
   filtered to the machine's class) looks for Chadley's machine, `FA0719_00_ChadleyVehicle_Standard_C`. About 1–8 ms. ✅
2. For a machine it hasn't seen, a second overlap (3 m, `Character`) looks for Chadley beside it: a class name
   starting `NP0067_` or `NP0147_01_KigurumiTonberry_Chadley` (his outfits in `ChadleySpec`), within 2 m. ✅
3. If he's there, the two swap places, each keeping its own height above the ground. ✅ (Costa del Sol)
4. On the machine it spawns the game's own vending-machine interaction, `SampleVendingMachine00_C` (an
   `EndFieldActionActorVendingMachine` with no mesh), with `ShopActionID = actCmn_ShowVRBattleMenu` and
   `MenuTextID = $level_action_operation`. The prompt reads **Operate**, and pressing it opens the simulator's course
   list. ✅
5. If the game puts the pair back (an area reload, a scene), they are swapped again; if the machine moves, the point
   is placed again; when the machine goes, the point goes. 🟡 (written, not yet seen happen)
6. Nothing happens until `stfComn_ChadleyVR_First` is set, which Chadley's first simulator visit sets. So the story's
   introduction to the simulator still goes through Chadley. 🟡 (the flag is set on slot 25; an earlier save not tried)

## What was seen (2026-11-20, Epic 1.005, slot 25 at Costa del Sol)

- The machine stands 0.6 m beside Chadley: machine (223023, -96631, 849), Chadley (222972, -96602, 952; his location
  is his capsule's centre). After the swap the machine is in front and Chadley behind it, and he stayed there.
- Operate opens the course list (`Combat Simulator 3.3.3G`). A course chosen from it started and played (Simulator
  Stages' picker came up too), giving up returned to the course list, and leaving the list returned to the field
  beside the machine.
- Chadley's Talk still shows at his new place.
- The installed mod did all of this by itself 20 s after the save loaded.

## Tour of the Chadley locations (2026-11-20, slot 25, late game, harness fast travel and navmesh walk)

The game's data names a Chadley point in each region (`ResidentObjectActor`, `obl####_*Chadley*`): Kalm, Bill's Ranch
(and its tower), Junon (Gabe's Ranch, Junon, Under Junon), Costa del Sol, North Corel, Gold Saucer (Under Saucer),
Gongaga, Cosmo Canyon (Kamaria's Ranch and the town), Nibel (the Chocobo Sage's Manor, Nibelheim) and Gilgamesh
Island. On this save he stands at the ones below; the town points belong to other chapters.

| Place | Result |
| --- | --- |
| Costa del Sol | ✅ swapped, Operate opens the course list, a course played, Talk still works |
| Bill's Ranch | ✅ swapped, Operate opens the course list, back to the field with Operate still there |
| Kamaria's Ranch | ✅ swapped, Operate opens the course list |
| Gabe's Ranch (Junon) | ✅ swapped and point placed (log; not pressed) |
| Gongaga (village) | ✅ swapped and point placed (log, screenshot; not pressed) |
| Chocobo Sage's Manor | ✅ swapped and point placed (log, screenshot; not pressed) |
| North Corel | ✅ swapped and point placed (log, screenshot; not pressed) |
| Cosmo Canyon, Under Junon, Nibelheim (gate) | no Chadley or machine within 400 m on this save |
| Gold Saucer | no Chadley near the arrival point; the game crashed 4 s after arriving (below) |
| Kalm | not reached (the harness's map query timed out) |
| Gilgamesh Island | not reached: the harness has no fast-travel region for its port |
| Torgan's Farm | not a Chadley location (my mistake in the first tour) |

**Talk can win over Operate.** The game shows one prompt for the press button. Standing so that Chadley is straight
behind the machine (Bill's Ranch, coming from the north), Talk showed even with the machine 0.75 m away and Chadley
1.2 m. From the machine's front (its yaw is Chadley's), Operate showed. The swap doesn't change this: the two keep the
same line between them, so the same approach lined them up before. Pressing Operate puts Cloud at the machine's front,
0.8 m out along that yaw. If players find Talk getting in the way, push Chadley a little further back after the swap.

**A crash on fast travel to the Gold Saucer** (22:18 UTC): `EXCEPTION_ACCESS_VIOLATION` in UE4SS.dll, stack
`+6a8c4f ← +45a60f ← +bedfd4 ← +bf487a` under a Lua call. That is issue #220's signature, seen in October before this
mod existed, and once more today at 19:51 during the equipment session's turn. Not shown to be this mod; ten other
fast travels with it installed today were clean. Worth a soak with and without the mod before release.

## Dead ends and lessons

- ❌ The first loop re-found actors by their path with `StaticFindObject`, which returns a dead object for actors
  here. Every tick then thought the machine had gone, adopted it again and swapped the pair back (and left ~190
  points behind). Now nothing is held between ticks: the machine and Chadley are found by overlap each tick, each
  point is attached to its machine and read back with `GetAttachedActors`, and tags stop a second swap. Our points
  don't show up in an overlap (their press box ignores queries), and `FindObject(class, name)` costs 40 ms.

- **The machine has no interaction of its own.** Its components are a skeletal mesh and a body collision primitive.
  Chadley has none either: his Talk comes from the game's object system.
- **Data tables don't show where vending machines' interactions come from**: `act1230_CallShop_010` is referenced
  only by its own row. They are level-placed `EndFieldActionActorVendingMachine` actors whose `ShopActionID` names
  the Action row. That made a runtime actor the way in.
- ❌ The native class `EndFieldActionActorVendingMachine` refuses to spawn (`SpawnActor` and
  `BeginDeferredActorSpawnFromClass` both return nothing; probably abstract). The Blueprint
  `/Game/BluePrint/FieldAction/Experiment/SampleVendingMachine00` spawns, and has no mesh.
- ❌ Moving a spawned point doesn't move its prompt. The game registers the field action where the actor starts.
  Spawn a new one instead.
- `MenuTextID` is read live: changing it changed the prompt at once.
- ❌ An object search for the machine (`FindAllOf`, `FindFirstOf`) costs 100–220 ms on the game thread here, far too
  much to poll. The class-filtered sphere overlap costs about a millisecond.
- The mod's folder: `debug.getinfo(...).source` doesn't give it under UE4SS; match `package.path` as No Popups does.
- A first launch with the mod crashed the game 0.1 s after mods started (C++ exception `0xe06d7363`, no Lua error
  logged). The next launch, with the mod waiting 20 s and for a party pawn (Battle Meters' lookup) before any game
  call, was clean. Not proven to be the mod; watch for it.
- `actCmn_ShowVRBattleMenu` alone skips Chadley's entry scenes (`EV_COMON_2111`/`2112`) and courses still start.
- The harness's `use_field_action` refuses while the planter's parkour prompt shows beside Operate (different
  buttons); worth a harness change.

## Still to do

- Gilgamesh Island's hologram Chadley, Kalm, and the town Chadleys in the chapters where they appear.
- A crash soak on fast travel with and without the mod (issue #220's signature).
- A save before the simulator's first visit (nothing should happen).
- A leader other than Cloud.
