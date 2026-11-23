# Workstream `meters`: one meters panel in Custom Training

Marks: ✅ seen in game · 🟡 partly · ❌ tried and failed · 📄 from code or docs only

Goal (owner, 2026-11-20 evening): inside Custom Training, one panel that does everything Training Dummy's and Battle
Meters' panels do, so neither mod is needed in the simulator. Damage, Tanking and Healing meters to cycle, a
per-character breakdown, reset stagger, clear, hide; the meter matching the course's behaviour opens first.

## Feature inventory 📄

Sources: Training Dummy 1.2.1 (`FFVII-Rebirth-Training-Dummy`, `ue4ss/TrainingDummy/Scripts`, `docs/GUIDE.md`) and
Battle Meters 1.1.0 (`FFVII-Rebirth-Battle-Meters`, `ue4ss/BattleMeters/Scripts`, `native/`, `docs/GUIDE.md`).
"TD" and "BM" below. The last column says where each one lands in the combined panel.

### Measuring

| Feature | TD | BM | Combined panel |
| --- | --- | --- | --- |
| Damage dealt per second (average since the first number) | ✓ (dummy only) | ✓ (every enemy) | Damage meter, every opponent except Custom Training's hidden anchor |
| Damage taken per second | ✓ (Tank) | ✓ | Tanking meter |
| Healing per second | ✓ (patients only) | ✓ | Healing meter |
| Last 5 seconds (rolling window, configurable) | ✓ | ✓ | ✓ every meter |
| Total | ✓ | ✓ | ✓ |
| Biggest hit / biggest hit taken / biggest heal | ✓ | ✓ | ✓ |
| MP spent, Healing per MP | ✓ (Healing) | ✓ (HPS) | ✓ Healing meter; MP from Custom Training's refill count (it refills MP as it's spent) |
| Time (game time, stops when paused) | ✓ (header) | ✓ (row) | ✓ header |
| Damage dealt shown on the Tank course too | ✓ (second block) | – | Tanking meter has a "Damage dealt per second" row |
| Damage dealt by character | – | ✓ (needs Battle Meters Native) | ✓ with the meters' own copy of the native helper |
| Healing by who did it | – (by who received) | ✓ (native); without it by who received | ✓ by who did it (native), else by who received |
| Damage taken by who took it | ✓ (rows with bars) | ✓ | ✓ |
| Unattributed share (poison, Regen, hits no event explained) | – | ✓ grey row and section | ✓ (damage dealt only; see the counting rules) |
| Overkill and overhealing not counted | ✓ (HP lost) | ✓ (credit capped at HP really changed) | ✓ |
| Killing blow of an enemy that vanishes between reads | – (dummy never dies) | ✓ (`killing_blow`) | ✓ as far as hit events explain it; never for opponents Custom Training removes (see Counting) |
| Its own HP writes not counted (refills, 1 HP holds) | ✓ (same mod) | – | ✓ party changes count only when a hit event explains them (with the native helper); rules without it |
| Every battle starts from zero; numbers survive cycling | ✓ | ✓ | ✓; also cleared at every Custom Training setup change |

### Showing

| Feature | TD | BM | Combined panel |
| --- | --- | --- | --- |
| Big number + stats rows, game HUD sprite panel, Roboto text | ✓ | ✓ | ✓ (same widgets, built at runtime) |
| Course title in the panel | ✓ | – | ✓ Custom Training's own words for the setup (`state().setup`: "Bomb ×3", "Tonberry King, Mindflayer, Bomb", "… · Round 1"), then the behaviour; in the game's language (UTF-8, cut by characters, a full-width one counting two; a round keeps its number). Not yet seen in the game: other languages and ×/· in the panel's font |
| Per-member rows | ✓ bar per member, biggest first | ✓ rows in party order | ✓ rows in party order with a share bar each, per second and total |
| Coloured share line, one colour per character (Zack cyan, Sephiroth purple...) | – | ✓ | ✓ same colours, used for the rows' bars too |
| Key hint line | ✓ | – | ✓ keyboard keys, and where the pad controls are |
| Hides while the game is paused | – | ✓ | ✓ |
| Last numbers linger after the battle | – (concealed) | ✓ 8 s | ✓ 8 s after the course ends |
| Shows briefly when switched outside a battle | – | ✓ | not needed: the panel exists only in a Custom Training course |
| `meters.json` for stream overlays and tests | ✓ | ✓ (with by_source) | ✓ (with by_source and the meter shown) |
| Position setting | ✓ 48,48 | ✓ 48,240 | ✓ setting, default 48,48 |
| Stands aside on Training Dummy's courses | – | ✓ | n/a; proposal for Battle Meters in the simulator below |

### Controls

| Feature | TD | BM | Combined panel |
| --- | --- | --- | --- |
| Cycle meters | – (fixed per course) | Ctrl+Shift+D: DPS → HPS → DTPS → off | F9 (keyboard); pad: Custom Training's menu (LB+RB), METERS section |
| Remember the chosen meter | – | ✓ `settings.txt` | the meter follows the behaviour at each start (owner); the hidden/shown choice is remembered |
| Clear stagger | F6 | – | F6; pad: Custom Training's menu |
| Reset meters | F7 | – | F5 (F7 is Custom Training's); pad: Custom Training's menu |
| Hide / show | F8 | "off" in the cycle | F8; pad: Custom Training's menu |

### Left to Custom Training (Training Dummy features that aren't meters)

The unbeatable dummy and its refill, the passive hold, Healing's 1% patients, Aggressive's refill below half and
unlimited MP are Custom Training's behaviours (`ws/custom-training`, `ct_party.lua`, `ct_game.lua`). Training
Dummy's course names in the simulator menu likewise.

### Left out

- Battle Meters outside the simulator (field fights, Combat Assignments): out of scope; Battle Meters stays the mod
  for that.
- Battle Meters' "panel shows for a few seconds after switching outside a battle": the combined panel only exists
  in a course.
- Training Dummy's `debug` setting: replaced by the development log (`meters-log.txt` with `dev.txt`).

## Design

Development mod `ue4ss/SimOverhaulMeters/` (with `dev.txt` it logs to `meters-log.txt` and takes development
commands), plus the native helper `native/meters` built into `dlls/main.dll` of the same folder.

| Module | What | Game calls |
| --- | --- | --- |
| `main.lua` | start-up, keys, the 200 ms loop (once a second outside a course) | – |
| `meters_core.lua` | per-second bookkeeping: average, last 5 s, total, biggest, by source (Battle Meters' `meters.lua`, unchanged) | none, tested |
| `meters_attribution.lua` | matching the game's hit events to HP changes (Battle Meters' `attribution.lua`, plus a credit callback) | none, tested |
| `meters_tracker.lua` | what one reading adds: opponents' HP lost, party HP, hits, MP; the counting rules below | none, tested |
| `meters_view.lua` | what the panel shows | none, tested |
| `meters_controls.lua` | settings (`meters_` keys in `settings.txt`), the meter shown, show/hide, actions | none, tested |
| `meters_course.lua` | Custom Training's course: start, change, end, MP counts | none, tested |
| `meters_api.lua` | the interface Custom Training's menu calls | none, tested through `main_sim_test` |
| `meters_game.lua` | readings, stagger reset, pause, time (Battle Meters' and Training Dummy's calls) | yes |
| `meters_overlay.lua` | the panel's widgets | yes |
| `meters_native.lua` | the native helper's hit queue | yes |
| `meters_samples.lua` | development only: made-up numbers for layout screenshots | none |

### Counting

- **Damage dealt**: every HP an opponent loses (Custom Training's hidden anchor left out by object name), split by who
  dealt it from the game's hit events; what no event explains is Unattributed (Battle Meters' rule). Only HP lost while
  an opponent is in the fight counts. Custom Training removes opponents itself (Apply with another opponent, a new
  attempt), and they leave with their HP: so a course change or start marks the opponents present, and those first
  seen in the next reading, as outgoing, and they count nothing when they leave. Any other opponent that vanishes
  between readings counts its last HP only as far as hit events on it explain it (a killing blow the readings missed),
  or without hit events only from half its HP or less (Battle Meters counts all of it: see the results). A clear keeps
  the opponents known, and a key that comes back with another name or max HP is a new opponent.
- **Custom Training's conditions** (owner, 2026-11-21): only **Aggressive** is real: no refills for the party (HP,
  MP) or the enemies, Auto-Life only. **Passive** keeps its refills (enemies held at 90%, party HP and MP), and
  **Healing** its 1% hold and MP refill.
- **Party healing and damage taken**: Custom Training writes party HP itself in Passive and Healing (Healing drops
  patients to 1% after each heal). So with the native helper these count only as far as a hit event explains the HP
  change: a heal event for a gain (credited to who cast it), a damage event for a loss (credited to who took it), each
  capped at the HP that really changed. Without the helper: every change counts except a drop to 2% of max or less in
  Healing, a rise to full from below half in Passive (Custom Training sets a living member under 50% to 100% in one
  jump), and any rise to full in the first 3 s after a start or change (its clean-up: Passive's top-up then and 2 s
  later, Healing's held members set back to full); healing is then shown by who received it. In Aggressive every
  change counts (only Auto-Life raises a member, HP from 0 up, which is healing).
- **MP spent**: in Passive and Healing Custom Training refills MP as it's spent, so the drop may never be seen from
  another mod. There it counts what it refills (`mp.<Name>` lines in `ct-mp.txt`, `ct_api.mp_refilled()`
  integrated, used from the course start even before the first refill). In Aggressive nothing is refilled, so MP
  spent is the party's own MP drops, read by the meters.
- **Waves** (owner, 2026-11-21): enemies die. The player respawns the same set (F4, the menu's Respawn row) or
  `ct_auto_respawn = on` brings it back once cleared. A wave starts at each respawn and is cleared when its last enemy
  dies; a respawn mid-fight starts a new wave with no clear time. Damage stops at the HP an enemy really had (HP
  readings never go below 0, and hit events are capped at the HP lost), and a new wave is neither damage nor healing:
  an opponent's HP gain never counts, whether the wave comes as new actors or as the same ones back at full. Killed
  opponents leave with 0 HP, so they count nothing more; on a respawn the opponents still in the fight are marked
  outgoing (as on Apply), so living ones removed with it count nothing. The totals keep running across waves. The
  panel's wave line ("Wave N   Last clear m:ss") shows in Aggressive, and elsewhere only once a wave was cleared.
- The numbers clear at every course start, every fight start inside it (a Rechallenge), every setup change in
  Custom Training's menu, and on Clear. A new wave doesn't clear them.

### Keys and buttons (every binding)

| Binding | Where it acts | Action | Bound by |
| --- | --- | --- | --- |
| F9 | anywhere (does something only in a Custom Training course) | next meter: Damage → Tanking → Healing | meters (`meters_next_key`) |
| F5 | same | clear the meters | meters (`meters_clear_key`) |
| F6 | same | reset stagger: every staggered opponent (not Custom Training's anchor) | meters (`meters_stagger_key`) |
| F8 | same | show / hide the panel (remembered) | meters (`meters_toggle_key`) |
| Pad (and keyboard): LB+RB or F7, then Meter, Clear meter, Reset stagger | the integrated settings menu (`ui`) in a Custom Training fight | Meter: Damage / Tanking / Healing / Hidden (then Apply); Clear meter and Reset stagger act at once | `ui` (its chord and menu, through `meters_api`; the meters bind no pad button). Seen in game 2026-11-21 on the integrated build |
| `meters-command.txt` (development) | – | `next`, `prev`, `meter=damage\|taken\|heal`, `clear`, `stagger`, `toggle`, `show`, `hide`, `sample <name>` | – |

Checked against everything else that binds keys in the owner's game (2026-11-21): Custom Training F7 (and LB+RB),
Equipment F3 (and Start in the simulator), Simulator Stages F7 (course list), Training Dummy F6/F7/F8 (act only on its
own courses; Simulator Overhaul replaces it), Battle Meters Ctrl+Shift+D, the harness's keyboard profile (F2, F3 and
letters, no F5/F6/F8/F9). The only other F5/F6 binding is `BenchInteractionLogger`, which is switched off. A pad chord of
our own was ruled out: in a fight every shoulder, D-pad and face button already does something, and the harness can't
press the stick buttons, so it couldn't be tested.

### Interface with Custom Training

- Course state: `ct_api.on_course` integrated; `ue4ss/Mods/SimOverhaulCustomTraining/ct-course.txt` during
  development (`what`, `active`, `behaviour`, `opponent`, `name`, `count`, `difficulty`, `anchor`). Start → the meter
  for the behaviour (Passive → Damage, Aggressive → Tanking, Healing → Healing); a behaviour change → that meter.
- Its menu reaches the meters through `meters_api.act(action)` and `meters_api.state()` integrated; during
  development by writing `meters-command.txt` in this mod's folder and reading `meters-state.txt`.
- Custom Training's menu (agreed 2026-11-21): a METER row (Damage / Tanking / Healing / Hidden, opening on
  `meters-state.txt`; Apply sends `meter=damage|taken|heal` then `show`, or `hide`) and a METER TOOLS row (Clear meter,
  Reset stagger: `clear`, `stagger`). It shows the section only when `meters_api` loads or `meters-state.txt` exists.
  The `ui` workstream, which replaces that panel, gets the same contract.
- MP spent (Passive and Healing): `ct_api.mp_refilled()` integrated (reset at every start and change); during development
  `SimOverhaulCustomTraining/ct-mp.txt` with `mp.<Name>=<total>` lines (a separate file, so a refill never looks like
  a change). Without them the meters read MP themselves.
- Waves (agreed with Custom Training 2026-11-21, `ws/custom-training` 80fecc9 and a510d09): `ct_api.state()` has
  `wave` (1 from the first wave; 0 between a start or change and its first spawn, shown as nothing), `wave_started`
  and `wave_time` (session clock), and `last_clear` (seconds the last cleared wave took, set when its last enemy
  dies; nil until one is cleared and after a start or change). `on_course` fires `what = "clear"` when a wave's last
  enemy falls (`clear_time`, `cleared`; `wave` stays at the cleared number while the round waits) and `what = "wave"`
  when a new set comes (a Respawn, or the automatic one, which also carries `clear_time` and `cleared`; a Respawn
  mid-fight carries none). The setup fields stay the same, so neither is a change. `ct-course.txt` has the same keys.
  A wave doesn't touch the party or reset `mp_refilled()`, and the anchor keeps the fight in battle across it (to be
  seen in the game). The meters take `last_clear` as the state says and mark the opponents outgoing on "wave".

- `meters-active.txt` exists in this mod's folder while a course runs, for Battle Meters to stand aside.

### Battle Meters alongside (parent's decision, 2026-11-21)

- **Battle Meters 1.2.0** stands aside while a Custom Training course runs, as on Training Dummy's courses. Branch
  `stand-aside-simulator-overhaul` in the Battle Meters repo (commits `10dbed6`, `bb42fe2` and `5ebf051`, not pushed,
  no release): a new `sim_overhaul.lua` checks for `meters-active.txt` in `SimulatorUpgrade/` (the mod's name since
  2026-11-21), `SimulatorOverhaul/` (a build from before the rename) or `SimOverhaulMeters/` at each battle start and
  then once a second while the battle runs, since Custom Training's start can come seconds later (a file check, no
  game calls); tests in `tests/sim_overhaul_test.lua` and `tests/main_sim_test.lua`; changelog, guide, how-it-works
  and README say so. Seen standing aside in the game (third run). Releasing it is the owner's call.
- **An older Battle Meters** doesn't know the marker. At start-up the meters read Battle Meters' installed
  `Scripts/main.lua` once (file reads only: it knows the marker if it mentions `meters-active.txt` or requires
  `sim_overhaul`), its `config.lua` for where its panel sits, and `mods.txt`/`enabled.txt` for whether it's on. Older
  and on: our panel moves to the top right (1468,48), unless the player set `meters_x`/`meters_y`. Right beside
  Battle Meters' panel (372,48) it covered nameplates mid-screen. The owner's game has Battle Meters 1.1.0 on.
- The marker is written either way, while a Custom Training fight is on, and removed at start-up in case the game
  closed mid-course.

### The integrated mod

The rules in `docs/COORDINATION.md` ("The integrated mod"): `MOD_DIR` is `SIM_OVERHAUL_DIR` when set; every module is
`meters_*`; `settings.txt` ships our section and only `meters_` keys are read; every file written is `meters-*`;
Custom Training through `pcall(require, "ct_api")` first, its file only as a fallback; no game call in the first 20 s
after load, and none before a party pawn has been seen. `tools/integrate/build_mod.py --parts meters,machine` (the machine was a part then) and its
smoke test: every part starts (2026-11-21).

### Native: one DLL for the release

`native/overhaul/src/dllmain.cpp` is the release's one C++ mod, `SimulatorUpgradeNative` (`SimulatorOverhaulNative`
before the rename, 2026-11-21): it includes Custom
Training's `native/custom-training/src/dllmain.cpp` and the meters' `native/meters/src/dllmain.cpp` whole (their own
`start_mod` exports renamed by macro), owns one instance of each part's mod and forwards `on_unreal_init` and
`on_lua_start`. With `SIM_OVERHAUL_COMBINED` defined each part registers its Lua functions for `SimulatorUpgrade`
only. Built with `tools/meters/Build-Overhaul-Native.ps1` (`-CustomTrainingNative` points at a newer Custom Training
source; `-Test` builds the development variant, where the meters part also registers for `SimOverhaulMeters` and
Custom Training's registers nowhere, to try it beside the development mods). Exports checked with dumpbin: one
`start_mod`/`uninstall_mod`, the parts' renamed. Custom Training's dev-name guard is in its commit `743093b`; merged here from main (`3509700`); built from this repo's own sources 2026-11-21 (release `F7B185BF…`, test `35644DE4…`).

Beside Battle Meters' own `BattleMetersNative`: two ProcessEvent pre-callbacks, each filling its own queue for its
own Lua mod, so nothing is counted twice (to check in the game).

## Settings (`settings.txt`, keys `meters_`)

`x`, `y` (48, 48; unset, the panel is placed for you), `visible` (on), `next_key` (F9), `clear_key` (F5), `stagger_key` (F6), `toggle_key` (F8),
`window` (5 s), `linger` (8 s), `json` (on).

## Tests

`python tests/meters/run_tests.py`: Battle Meters' own tests for the two copied modules, plus controls, course,
tracker (strict and fallback counting on made-up fights), view (including every sample against the panel's widths),
and `main_sim_test` (the real `main.lua` against a fake game through a Passive course, a change to Healing, keys,
the command and state files, the anchor, stagger, pause, hide, Apply with another opponent mid-fight, and the end).
`tracker_test` has the opponent-removal cases: removed after a course change (seen again or not), first seen after
it, a killing blow explained by a hit, one without hit events, a key used again, a clear mid-fight.

## Results in game

2026-11-21, Epic 1.005, save slot 25 at Costa del Sol, 1920x1080, nothing saved. Custom Training's installed
development build (from 01:23, before its METERS rows and `ct-mp.txt`), Battle Meters 1.1.0 with its own
BattleMetersNative on, Training Dummy and Junon Colosseum installed. Party with Zack and Sephiroth: they were set to
reserve (the party workstream's finding) because Custom Training's installed build predates `data/party.json`.
Production test events are listed with each result.

| What | Result | Seen |
| --- | --- | --- |
| Panel in a Passive course: Damage first, opponent and behaviour, zeros | ✅ | [01](meters/01-passive-damage-start.jpg) |
| Damage counted and split by who dealt it; matches Battle Meters' own panel | ✅ 10,205 vs Battle Meters' 10,157 read a moment earlier | [02](meters/02-passive-damage-fighting.jpg) |
| **F9** next meter: Damage → Tanking → Healing → Damage, pressed for real through the harness (`press_key`) | ✅ | [03](meters/03-key-f9-tanking.jpg), [04](meters/04-key-f9-healing.jpg), [05](meters/05-key-f9-damage.jpg) (cropped at the old position) |
| **F5** clear | ✅ numbers back to 0 | [06](meters/06-key-f5-cleared.jpg) |
| **F8** hide, **F8** show (remembered in `settings.txt`) | ✅ | [07](meters/07-key-f8-hidden.jpg), [08](meters/08-key-f8-shown.jpg) |
| Keys event | ✅ `4b531af0…` verified | |
| Switch to **Aggressive** mid-course: the panel goes to Tanking by itself; damage taken counted from hit events, Cloud's row, "Damage dealt per second" row | ✅ 1,993 taken | [09](meters/09-aggressive-tanking.jpg), event `7a4315ce…` |
| Switch to **Healing**: the panel goes to Healing by itself; Custom Training's 1% hold counted as nothing (taken 0) | ✅ | [10](meters/10-healing.jpg), event `85a0e0e2…` verified |
| Healing with **Aerith, Zack, Sephiroth**: heals counted for who cast them (Aerith 22,565, Sephiroth 10,440), rows in each colour, MP spent, healing per MP | ✅ | [11](meters/11-healing-party.jpg), event `38ebffc8…` verified |
| Damage with three fighters and **Unattributed** (four rows) | ✅ | [12](meters/12-damage-party-rows.jpg), [13](meters/13-after-stagger-reset.jpg) |
| **F6** reset stagger on a real stagger (after about two minutes of attacks) | ✅ "stagger cleared on 1" | event `11e673ca…` verified |
| Panel at 372,48 (right of Battle Meters 1.1.0's) | ❌ covered the Shirdal's nameplate mid-screen ([13](meters/13-after-stagger-reset.jpg)); moved |
| Panel top right (1468,48) beside Battle Meters 1.1.0 | ✅ clear of Battle Meters, nameplates and the party HUD | [14](meters/14-top-right-beside-old-battle-meters.jpg) |
| **Combined SimulatorOverhaulNative** (test build) beside Battle Meters' own BattleMetersNative | ✅ no crash; both count the same fight once: 5,314 damage, Sephiroth 5,173 / Zack 141 in both | event `b21d5c89…` verified |
| Paused: the panel hides | ✅ | [15](meters/15-paused-panel-hidden.jpg), [16](meters/16-unpaused-panel-back.jpg) |
| After the course (Give Up): last numbers stay on the result screen, then go | ❌ first gone at once ([17](meters/17-after-course-0.jpg)); ✅ after the fix | [18](meters/18-after-course-linger-0.jpg) then [gone](meters/18-after-course-linger-4.jpg) |
| Fight start when Custom Training writes its start after the fight begins | ❌ first: no hit events, totals only ([18](meters/18-after-course-linger-0.jpg) shows the note); ✅ after the fix | [19](meters/19-fight-start-fixed.jpg), event `dd5266f4…` |
| Layout with made-up numbers (development `sample` command): very large values (1:02:05, 9,999,999, 100,000), four rows with the longest names, small, empty, solo, no native, in each meter | ✅ nothing clipped or overlapping | [20](meters/20-sample-large-damage.jpg) [21](meters/21-sample-large-taken.jpg) [22](meters/22-sample-large-heal.jpg) [23](meters/23-sample-rows-damage.jpg) [24](meters/24-sample-rows-taken.jpg) [25](meters/25-sample-rows-heal.jpg) [26](meters/26-sample-small-damage.jpg) [27](meters/27-sample-small-heal.jpg) [28](meters/28-sample-empty-damage.jpg) [29](meters/29-sample-solo-damage.jpg) [30](meters/30-sample-solo-heal.jpg) [31](meters/31-sample-nonative-damage.jpg) [32](meters/32-sample-nonative-heal.jpg) |

Sample shots 20–32 were taken at the old 372,48 position, before the move to the top right; the panel's own layout
is the same in both places.

### Second run: the integrated build (2026-11-21, 07:15–07:35)

The game's new baseline, installed on this turn with `tools/meters/Install-Integrated.ps1` (backups in
`D:\FF7RebirthModding\Mods\SimulatorOverhaul\install-backups\20261121-070756` and `…-071434`): the integrated build
from main e3617ab plus the opponent-removal fix (9a63734), with the release combined SimulatorOverhaulNative
(`F7B185BF…`). No standalone SimOverhaul* parts (custom-training had set them aside, Simulator Stages' standalone mod
too: it was enabled). `mods.txt` now lists SimulatorOverhaulNative and SimulatorOverhaul (they also have `enabled.txt`;
UE4SS's log shows each started once). Battle Meters 1.1.0 with BattleMetersNative, Training Dummy, Junon Colosseum as
before. Party Cloud, Zack, Sephiroth (offered by Custom Training's team list now). The presses are real
(`press_pad` / `press_key`), driven by `tools/meters/pad_route.py` and `apply_opponent.py`.

| What | Result | Seen |
| --- | --- | --- |
| Release combined DLL in the integrated mod | ✅ "the meters' native helper is hooked"; rows by character | [03](meters/40-pad-03-tanking-after.jpg) |
| Placement beside Battle Meters 1.1.0 found at start-up | ✅ "Battle Meters on, older (doesn't stand aside)", panel top right, clear of it | [03](meters/40-pad-03-tanking-after.jpg) |
| **Pad route**: LB+RB opens the settings menu; Meter → Tanking, Apply | ✅ panel on Tanking | [menu](meters/40-pad-01-tanking-menu.jpg), [values](meters/40-pad-02-tanking-values.jpg), [after](meters/40-pad-03-tanking-after.jpg) |
| Meter → Healing, Apply | ✅ | [06](meters/40-pad-06-healing-after.jpg) |
| Meter → Hidden, Apply | ✅ panel hidden | [09](meters/40-pad-09-hidden-after.jpg) |
| Meter → Damage, Apply (from Hidden) | ✅ shown again on Damage ("meter=damage", "show") | [12](meters/40-pad-12-damage-after.jpg) |
| Clear meter | ✅ "meters cleared (asked)" | [14](meters/40-pad-14-clear-after.jpg) |
| Reset stagger | ✅ sent ("stagger cleared on 0": nothing was staggered) | [16](meters/40-pad-16-stagger-after.jpg) |
| Pad route event | ✅ `625b9daf…` | |
| **F7** opens the same menu (keyboard) | ✅ | [01](meters/40-keyboard-01-cancel-menu.jpg) |
| **Apply another opponent mid-fight**: Zuu → Titan (standard) | ✅ cleared on the Apply ("change passive"), then only the Titan's damage | [Titan fight](meters/41-apply-titan-fight.jpg) |
| Titan → Test 0 with the Titan at 78,853 / 84,357 HP (the case ui saw) | ✅ ours restarted at 0 and rose only with hits on Test 0, split by who dealt them; Battle Meters 1.1.0 jumped by exactly 78,853 (Unattributed 5,594 → 84,447, "Biggest hit 78,853") | [names](meters/42-remove-titan-03-names.jpg), [after](meters/42-remove-titan-05-after.jpg), event `c5f9ed2b…` |

Battle Meters 1.1.0 beside the integrated build: no crash in 20 minutes, both panels drawn; it counts what Custom
Training removes (the Zuu on the first Apply, 5,594 Unattributed, and the Titan), which 1.2.0's standing aside makes
moot in Custom Training.

### Third run: waves, MP and Battle Meters 1.2.0 (2026-11-21, 19:36–20:20)

A test build: ws/meters (as each fix landed, last a0b2eee) with ws/custom-training 7111339 (its waves, F4 Respawn),
merged in a scratch checkout; Battle Meters 1.2.0's two changed files in place of 1.1.0's; the combined native from
main. Zu (5,740 HP), with Cloud and Aerith, then Aerith alone. Afterwards custom-training's 15:07 install
(`install-backups\20261121-193614`) and Battle Meters 1.1.0 were put back.

| Check | Result | Evidence |
| --- | --- | --- |
| Battle Meters 1.2.0 found at start-up | ✅ "Battle Meters on, stands aside"; our panel at the top left (48,48) | meters log |
| Battle Meters 1.2.0 stands aside | ✅ in the first course (its battle start and our marker in the same instant): "leaving the panel to that mod", only our panel | [51](meters/51-bm120-stands-aside.jpg), event `db82482c…` |
| … when our marker comes seconds after its battle start | ❌ then ✅: in the second course Custom Training said its start 4 s after the battle began, Battle Meters had looked once and drew its panel under ours. Fixed on its branch (5ebf051: it looks again once a second); seen: battle start 20:16:15.35, stood aside 20:16:20.10, only our panel | [54](meters/54-cleared-waiting.jpg) (both panels), [57](meters/57-behaviour-change-kill.jpg) (ours only) |
| MP spent from Custom Training's refill counts (Healing) | ✅ ct_api.mp_refilled() Cloud 12, the panel's MP spent 12, healing per MP 1,861 | [52](meters/52-healing-mp.jpg) |
| A wave cleared in Aggressive: wave line | ✅ "Wave 1   Last clear 1:36", then "Wave 2   Last clear 1:58"; the clear time is Custom Training's (it counts from the course start, not from a behaviour change: reported to it) | [54](meters/54-cleared-waiting.jpg), [55](meters/55-wave2-cleared.jpg) |
| The panel while the round waits for Respawn | ❌ then ✅: it went away (only the anchor left to draw with); fixed (9844dd3), seen staying | [53](meters/53-aggressive-wave1.jpg) (gone), [54](meters/54-cleared-waiting.jpg) |
| F4 Respawn after a clear: totals run on, nothing for the new wave | ✅ damage 3,301 → 9,041 at wave 2's clear: exactly the new Zu's 5,740 | [55](meters/55-wave2-cleared.jpg), event `16b86d8b…` |
| F4 mid-fight (wave 3's Zu alive at 2,794 / 5,740) | ✅ ours 11,987 → 12,058 (only wave 4's own 71); "Wave 4   Last clear 1:58" kept; Battle Meters 1.2.0's own panel (not standing aside then) jumped by 2,794 Unattributed | [56](meters/56-midfight-respawn.jpg) |
| Passive → Aggressive, then the kill | ❌ then ✅: the first time the Zu's last blow was lost (3,301 counted of at least 5,166: the change marked it outgoing). Fixed (d44c85e); seen: HP 5,189 at the change, damage 5,189 at its death | [57](meters/57-behaviour-change-kill.jpg), event `f0cd5b9b…` |
| One clear per change | ❌ then ✅: with the group field compared, the meters cleared every tick (ct_api's group is a new table each call); fixed (a0b2eee), seen: one clear | UE4SS log |

### Found and fixed in the game

- The marker for Battle Meters was written at a course "start" read from Custom Training's file, which still said
  `active=true` after a game had closed mid-course: Battle Meters would then have hidden in field fights. Now the
  marker exists only while a Custom Training fight is on.
- The first fight's hit events were never switched on when Custom Training wrote its start a moment after the fight
  began. Now the fight start is "course active and in a fight", in either order; the offline test runs that order.
- Saving the show/hide choice also wrote the default position, which then counted as set by the player and stopped
  the panel being placed clear of Battle Meters. Now the position is written only when the player set it.
- On the result screen there is no pawn, so the linger hid the panel at once. It now leaves the last frame up until
  the linger ends.
- Next to an older Battle Meters, the panel right of Battle Meters' sat mid-screen and covered nameplates: moved to
  the top right.
- Waves (third run): the panel went away while a cleared round waited (only the anchor was left to draw with); a
  behaviour change marked the opponents outgoing, so a kill's last blow between two readings was lost; comparing
  Custom Training's `group` (a new table each call) cleared the numbers every tick. All three fixed and seen fixed.
- Battle Meters 1.2.0 looked for our marker only at its battle's start, which can come seconds before Custom
  Training's start: it now looks once a second (its branch, 5ebf051), seen standing aside 5 s in.
- Removing an opponent on Apply counted its remaining HP as damage (found on ui's turn: a Titan, 84,186
  Unattributed). The clear on Custom Training's change forgot the opponents, the next reading took the Titan as new,
  and its removal then counted as Battle Meters' killing blow. Fixed (see Counting) and seen fixed in the second run.

### Not yet seen in the game

- MP spent in Aggressive (the party's own MP, no refills): the third run's Aggressive fights cast nothing.
- The no-hit-events rules (Passive's refill, the 3 s clean-up window): every run had the native helper.
