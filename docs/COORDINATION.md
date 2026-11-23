# How the work is split

Simulator Overhaul is built by several Claude sessions at once, one per workstream, all testing in the owner's one
game. This page is the shared agreement. The parent session ("Simulator Overhaul", which made this repo) owns it,
merges the workstreams and builds the release. If something here blocks you, tell the parent; don't change the
rules on your own.

## Workstreams

| Workstream | Branch | Owns | Who |
| --- | --- | --- | --- |
| `machine` | `ws/machine` | interacting with the machine next to Chadley opens the simulator; Chadley and the machine swap places where both appear | parent |
| `stages` | `ws/stages` | Simulator Stages folded into the Overhaul | parent |
| `custom-training` | `ws/custom-training` | the Custom Training course: any opponent, 1 to 3 copies, Passive, Aggressive or Healing, difficulty switch, the settings logic; bosses; the opponent sweep | sub-session |
| `party` | `ws/party` | Zack and Sephiroth selectable for Custom Training | sub-session |
| `equipment` | `ws/equipment` | changing equipment and materia from the simulator's menus (course list and after choosing a course); not mid-fight | sub-session |
| `meters` | `ws/meters` | one meters panel in Custom Training combining Training Dummy's and Battle Meters' | sub-session |
| `ui` | `ws/ui` | Custom Training's settings in the game's own UI instead of the hand-built panel | sub-session |
| `equipment-midfight` | `ws/equipment-midfight` | offline research: changing equipment mid-fight without the T-pose (a later release) | sub-session |

`main` is the integrated mod. Only the parent merges into it.

### The owner's decisions (2026-11-20, evening)

- Simulator Overhaul replaces Training Dummy: Custom Training must do everything Training Dummy's three courses do.
- Behaviour is **Passive** (enemies held; Training Dummy's DPS course), **Aggressive** (they fight; its Tanking course)
  or **Healing** (enemies held, every party member held at 1% HP; its Healing course).
- One meters panel in Custom Training combines Training Dummy's and Battle Meters': cycle Damage, Tanking and Healing
  meters, per-character breakdown, reset stagger, clear, hide, and whatever else either mod has that the other lacks.
- Equipment only from the simulator's menus. No equipment change mid-fight while it T-poses the fighters; that is
  researched offline for a later release.
- Custom Training's settings should live in the game's own UI, not the hand-built panel.
- Every menu, panel and key the mod adds works fully from both keyboard and gamepad: opening, moving, changing,
  confirming, closing. Nothing may need the other device. Test both in the game.
- The opponent sweep runs in **Aggressive**: each opponent must actually attack (damage or a guard seen), and anything
  odd is recorded and fixed or the opponent left out: stuck or idle, invisible, falling through the floor, wrong
  position, adds that don't come or don't go, the round ending, HUD or camera trouble, a crash or freeze.
- Everything the mod draws must look good in every state it can be in, judged from screenshots: longest and shortest
  names, every opponent kind, boss and non-boss, each behaviour and difficulty, every meter, empty and full values, in
  and out of a fight, at the owner's resolution. Nothing clipped, overlapping, unreadable or off-screen.
- Every opponent gets tested. Bosses: one copy only, and those that break without their own arena are fixed or left
  out after testing.

## Where to work

- Each workstream has its own git worktree of this repo:
  `<our mods folder>\FFVII-Rebirth-Simulator-Overhaul-wt\<workstream>`, on its branch. Commit there, often.
  Don't push; there is no remote yet.
- Touch only your own paths (below). If you need a change in another workstream's files, or in a shared file, ask the
  parent.
- Write what you learn in `docs/workstreams/<workstream>.md` as you go: findings, dead ends (they go into the
  how-we-built-it write-up and the video), what has been seen in the game and how. Mark each claim ✅ seen in game,
  🟡 partly, ❌ tried and failed.

## Paths

| Path | Owner |
| --- | --- |
| `ue4ss/SimOverhaul<Part>/` (e.g. `SimOverhaulCustomTraining`) | that workstream: its development UE4SS mod |
| `data/<workstream>.json`, `data/<workstream>/` | that workstream: its DataBuilder spec |
| `native/<workstream>/` | that workstream, if it needs a native helper |
| `tools/<workstream>/`, `tests/<workstream>/` | that workstream |
| `docs/workstreams/<workstream>.md` | that workstream |
| `README.md`, `docs/COORDINATION.md`, `tools/DataBuilder/`, `ue4ss/SimulatorOverhaul/`, release tooling | parent |

### Development installs, then one mod

While we build, each workstream installs **its own** UE4SS mod folder (`SimOverhaul<Part>`) and, if it changes tables,
**its own** pak (`SimOverhaul<Part>_<n>_P`, see the pak numbers below). That way installing your build never
overwrites another workstream's. At integration the parent folds the parts into one `SimulatorOverhaul` mod folder and
one pak.

To make that merge easy:

- Keep `main.lua` thin: start-up and the loop only. Put the logic in modules, and keep game-free logic in files that
  can be tested offline with `lupa` (see Training Dummy's `tests/run_tests.py`).
- Separate UE4SS mods have separate Lua states, so they can't call each other during development. When a part needs
  another part (Custom Training's settings menu offering "Equipment"), call it through `pcall(require, ...)` and do
  nothing if it's missing; the integrated mod will have both.
- Settings go in `settings.txt` beside the scripts (Battle Meters' pattern), with keys prefixed by your workstream.
- Say in your workstream doc which keys you bind, which tables you change and which rows you add.

### The integrated mod (from 2026-11-21)

`tools/integrate/build_mod.py` (parent) assembles the release from every part's development mod:

- **`SimulatorOverhaul/`**: one UE4SS mod. Every part's `Scripts/` is copied into its `Scripts/` (subfolders kept);
  each part's `main.lua` becomes `<part>_main.lua` and the generated `main.lua` requires them one by one, each in a
  `pcall`, so one part failing leaves the others running. Simulator Stages' level helper is its `dlls/main.dll`.
- **`SimulatorOverhaulNative/`**: Custom Training's native helper as its `dlls/main.dll` (it registers its functions
  for the Lua mod named `SimulatorOverhaul`).
- **One pak**, `SimulatorOverhaul_P`, built from all the parts' specs.

So that this works without edits at build time, every part follows these rules now:

1. **Folder:** `local MOD_DIR = rawget(_G, "SIM_OVERHAUL_DIR") or <your own detection>`. The generated `main.lua`
   sets `SIM_OVERHAUL_DIR` to the `SimulatorOverhaul` folder before requiring the parts.
2. **Module names** don't collide: prefix them (`ct_*`, `meters_*`, `ui_*`, `machine_*`) or use a subfolder
   (`equipment/`). Never a top-level `main`, `game`, `session`, `stages`, `settings`, `util` (Stages uses some).
3. **Settings:** one shared `settings.txt`. Read only keys with your prefix (`ct_`, `equipment_`, `meters_`, `ui_`,
   `machine_`, `stages_`) and ignore every other line. Ship your defaults as a section of your own `settings.txt`;
   the build joins the sections.
4. **Files** you write (logs, state, bridges) are named with your prefix, in `MOD_DIR`.
5. **Talking to another part:** `pcall(require, "<its module>")` first, the file bridge only when that fails.
6. **Keys and buttons:** list every binding in your doc's table. Two parts never bind the same key or button in the
   same place. Simulator Stages binds F7 on the course list when `stages_picker = key`.
7. **Start-up:** nothing that calls the game in the first seconds after mods load. Register `ExecuteInGameThread` once
   at load (see the machine part) and wait for a party pawn before the first game call.
8. **Loops (from 2026-11-21, `docs/workstreams/lua-state.md`):** in the integrated mod, `LoopAsync` and
   `ExecuteInGameThread` go through one scheduler (`tools/integrate/overhaul_tick.lua`) and the native game pump.
   Keep using them as before, but call no other UE4SS function from a `LoopAsync` callback; plain Lua and `io` are
   fine. Queue game work only when there is some. `pcall` doesn't catch UE4SS errors (they are C++ exceptions):
   avoid them instead.

### Tables

Paks replace whole tables, so two paks that change the same table conflict, and the later pak wins. Before adding a
table to your pak, check this list and tell the parent:

| Table | Changed by |
| --- | --- |
| `Colosseum`, `EnemyTerritory`, `EnemyTerritoryLevel`, `ColosseumPositionData`, `EnemyParameter` | `custom-training` (and `party` through it, see below). Training Dummy and Junon Colosseum, both installed in the owner's game, replace these too. |
| `Action`, `ActionGroup`, `ChadleySpec` (if needed) | `machine`. No Popups and Junon Colosseum replace `Action`. |

`party` and `custom-training` share the Custom Training course row. `custom-training` owns the row; `party` delivers
the fields it needs as `data/party.json` (a list of `set` values for the course row, plus any rows of its own), and
`custom-training`'s build applies it. Until the row exists, `party` can prove its approach on a copy of a vanilla
course in its own pak.

Build tables against the export that matches the game: the owner's game is the **Epic 1.005** build, so
`D:\FF7RebirthModding\GameExports\vanilla-epic-1.005-2026-11-13\Exports`. The shared DataBuilder is FFVII-Modding
`Tools/ff7r-databuilder`; the parent copies it into `tools/DataBuilder` for everyone.

### Numbers, so nothing collides

| What | `machine` | `custom-training` | `party` | `equipment` | `stages` | `meters` | `ui` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Row `UniqueIndex` | 1970698000–099 | 1970698100–499 | 1970698500–599 | 1970698600–699 | 1970698700–799 | 1970698800–899 | 1970698900–999 |
| StoryFlag `UniqueIndex` | 16400–16419 | 16420–16469 | 16470–16479 | 16480–16489 | 16490–16499 | ask the parent | ask the parent |
| Pak | `SimOverhaulMachine_9100_P` | `SimOverhaulCustomTraining_9200_P` | (through custom-training) | `SimOverhaulEquipment_9400_P` | `SimOverhaulStages_9500_P` | `SimOverhaulMeters_9600_P` | `SimOverhaulUI_9700_P` |
| New row names | `*Mod_SimOverhaul_Machine_*` | `*Mod_SimOverhaul_CT_*`, courses `COL99_SimOverhaul_CT_*` | `*Mod_SimOverhaul_Party_*` | `*Mod_SimOverhaul_Equip_*` | `*Mod_SimOverhaul_Stages_*` | `*Mod_SimOverhaul_Meters_*` | `*Mod_SimOverhaul_UI_*` |

Rows other mods already use (don't take these): Training Dummy's territory
`terVR_COL30_SUMMON_Gilgamesh_010_BtlTest_Hard`, `Enemy_99` and `COL99_TrainingDummy_*`; Junon Colosseum's list in the
mod skill's `references/cookbook.md` ("Rows and IDs our mods already use"). Check nothing references a row before you
repurpose it.

## The game

There is one game: the owner's **Epic** copy, `D:\Epic Games\FinalFantasyVIIRebirth`. UE4SS mods go in
`End\Binaries\Win64\ue4ss\Mods\`, paks in `End\Content\Paks\~mods\`. Other mods are installed there (Training Dummy,
Battle Meters, Junon Colosseum, No Popups, Simulator Stages' development build); leave them as they are unless the
parent agrees.

### Taking turns

Only one session uses the game at a time. The lock is the file
`D:\FF7RebirthModding\Mods\SimulatorOverhaul\GAME-LOCK.json`:

```json
{"holder": "custom-training", "since": "2026-11-20T15:30:00Z", "refreshed": "2026-11-20T15:41:00Z", "doing": "testing the opponent picker"}
```

- **Take it** only when the file doesn't exist, or its `refreshed` is more than 30 minutes old. Write it, then read
  it back to make sure it's yours.
- **The queue:** `GAME-NEXT.txt` beside the lock names the session that goes next (one workstream name per line, first
  line next). While it exists, take a free lock only if the first line is your name, and remove your line when you take
  it. To join the queue, add your name at the end. The parent may reorder it.
- **Refresh** `refreshed` at least every 10 minutes while you use the game.
- **Release it** (delete the file) as soon as your test is done. Don't hold the game while you write code: build
  first, then take the lock, install, restart, test, and release.
- Without the lock: no input, no installs into the game, no game restarts, and no Lua through the eval console
  (`stages-eval.lua`; two sessions writing it replace each other's code). Reading files is fine.
- When you take the lock, assume nothing about the game's state: check it.
- You may force-close and relaunch the game while you hold the lock (the owner allows force-closing).

### Driving it

- The harness (MCP server at `http://127.0.0.1:8765/mcp`) drives the game. If its tools aren't attached to your
  session, use the mod skill's `scripts/mcp.py`: `python mcp.py <tool> '<json>'`, or `mcp.op(name, **args)` for a
  harness operation. `FFVII-Modding/AGENTS.md` applies whenever you drive the game; use `-Mode Offline`, no
  narration.
- The control session is already open. Don't close it or call `stop_all_input` unless something is going wrong.
- **Save slot 25** is in front of Costa del Sol's Chadley: load it to test. Don't save into any slot without asking
  the parent: slots 10, 13, 14 and 17 belong to other work, and 14 is never saved to.
- Restart the game after every Lua change: UE4SS hot reload (Ctrl+R) crashes this game.
- Simulator Stages' development build has a live Lua console: write a Lua file to
  `ue4ss\Mods\SimulatorStages\stages-eval.lua`, and within a second it runs once on the game thread and its output
  (`out(...)`) lands in `stages-eval.out`. Write it atomically (write `stages-eval.tmp`, then rename it to
  `stages-eval.lua`): the hook polls for the file and can read it while it is still empty, which runs nothing and
  reports `ok nil`. Delete `stages-eval.out` first and wait for a new one. A UE4SS member error aborts the chunk with
  no output at all; trace to a file of your own to see how far it got. Never name a member an object lacks, even inside `pcall`, and never call a
  function an object doesn't have: both break the Lua state until a restart.
- No full test suites or drive scans while the game runs. Run targeted tests at Idle priority.
- Mark tested moments for the video with production test events (`register_production_test_context`,
  `begin_production_test`, `end_production_test`; mod skill `references/test-and-evidence.md`).

## Known so far

From the parent's research (2026-11-20), useful to more than one workstream:

- Chadley's menu is a "shop" action: `actCmn_ChadleyShop` (Type 43, ints `8, 1`). Its Combat Simulator entry runs
  the resident action group `acgCmn_ChadleyVR`: the first-visit and entry scenes (`EV_COMON_2110`/`2111`/`2112`), then
  `actCmn_ShowVRBattleMenu` (Type 43, ints `4, 1, 0, 1`), which opens the simulator's course menu.
  `acgCmn_ChadleyVR_PartyMember` is the variant for a leader other than Cloud.
- Type 43's first integer picks the screen: 0 main menu (`actCmn_ShowMainMenu`), 2 map, 4 colosseum or simulator
  course menu, 5 next-course menu (`actCmn_ShowColosseumNextMenu`), 8 Chadley's menu, 9 quest board, 11 chocobo
  customisation, 12 wardrobe.
- `Colosseum.ChadleyShop = 1` marks the 67 courses listed in Chadley's simulator. `BattleWarpPoint` is
  `Point_VRBattle` for them, `TerritoryActorName` `VRBattle_TerritoryCmnActor`.
- Chadley in the field is spawned natively at `AEndChadleyPoint` actors (`Parameters.bEnableDevice` adds the machine,
  `Parameters.Location`/`Rotation`). The machine is `FA0719_00_ChadleyVehicle_Standard`; `ChadleySpec` picks Chadley's
  outfit and the machine per point.

## The game baseline (from 2026-11-21, 02:00)

From the meters' game turn on, the game carries the **integrated build** (`tools/integrate/build_mod.py --dev`) and no
standalone SimOverhaul* parts or standalone pak. `D:\FF7RebirthModding\Mods\SimulatorOverhaul\INSTALLED.txt` says what
is installed and how to restore it. To try newer work, commit it on your branch, ask the parent to merge it into main
(or merge main into your branch and build from there), rebuild the integrated build, and install that, backing up
what you replace. Don't put a standalone part back beside the integrated one: both would run.


## The name: Simulator Upgrade (owner, 2026-11-21)

The mod is called **Simulator Upgrade**. Everything a player sees uses it: the mod folders `SimulatorUpgrade/` and
`SimulatorUpgradeNative/` (the native helpers register for the Lua mod named `SimulatorUpgrade`), the paks
`SimulatorUpgrade_9200_P` and `SimulatorUpgrade_JunonCompat_9200_P`, the release zip, the readme and the Nexus page.
Internal names keep "Overhaul" for now (`SIM_OVERHAUL_DIR`, the `SimOverhaul*` development folders, `native/overhaul`,
this repository's folder), so work in progress doesn't break; the public repository will be
`FFVII-Rebirth-Simulator-Upgrade`. A live script that looks for `Mods\SimulatorOverhaul` must look for
`Mods\SimulatorUpgrade` once the renamed build is installed.

## The machine leaves (owner, 2026-11-21)

Chadley's machine becomes the way into the owner's separate Relive Memories mod (story rematch,
`<our mods folder>\FFVII-Rebirth-Story-Rematch`), which takes the machine part's code. Simulator Upgrade no
longer ships the machine part: the simulator opens from Chadley's own talk again, and Chadley and the machine stay
where the game puts them. Equipment inside the simulator is what saves the trips to Chadley now. `ue4ss/SimOverhaulMachine`
stays in this repository's history only.
