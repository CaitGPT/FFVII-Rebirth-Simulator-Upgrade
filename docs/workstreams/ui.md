# Custom Training's settings in the game's own UI (workstream `ui`)

The owner wants Custom Training's settings (opponent, number, behaviour Passive/Aggressive/Healing, difficulty) housed in
the game's own UI, reusing its widgets and logic, so they look like part of the game, instead of the hand-built panel
(`ct_panel.lua`). Every menu the mod adds must work fully from keyboard and gamepad.

Marks: ✅ seen in game · 🟡 partly · ❌ tried and failed · 📖 read from the header dump, game data or code, not yet tried.

## What this workstream owns

| Kind | Name |
| --- | --- |
| UE4SS mod (development) | `ue4ss/SimOverhaulUI/` |
| Tests | `tests/ui/` (offline, `lupa`: `python tests/ui/run_tests.py`) |
| Pak | none needed (`SimOverhaulUI_9700_P` is reserved and unused) |
| Tables, rows | none |
| Keys | F7 (`ui_menu_key` in `settings.txt`) and, in a fight, LB+RB together: the keys Custom Training's panel used, which this menu takes over (Custom Training's `ct_panel = off`) |
| Settings | `settings.txt`: `ui_menu_key`, `ui_back_keys` (ESCAPE,BACKSPACE), `ui_pause` (on), `ui_chord` (on) |

## Keys and buttons

Everything below acts only while a Custom Training course is running (`ct_api.active()`); outside one the menu refuses
to open and nothing is pressed or drawn. Simulator Stages' F7 (course list, `stages_picker = key`) is a different place.

| Key or button | Where | Does | Read by |
| --- | --- | --- | --- |
| F7 (`ui_menu_key`) | in the course | opens the menu; closes it when open | `RegisterKeyBind` |
| LB + RB together (`ui_chord`) | in a fight in the course, menu closed, game not paused | opens the menu | `IsInputKeyDown`, every 100 ms |
| Up / Down (arrow keys, D-pad) | menu open | move the window's cursor (wraps from the top to Back) | the game's window |
| Confirm (Enter, A) | menu open | chooses the row | the game's window |
| Esc or Backspace (`ui_back_keys`) | menu open | back: Back on a list, Cancel on the main window, 0.25 s after the press | `RegisterKeyBind` (ignored while the menu is shut, so Esc still pauses the fight) |
| B (pad) | menu open | the same as Esc: once per press, not repeated while held, and not when already held as the menu opens | `UEndSystemAPI.IsInputKeyDown`, every 50 ms while a window is open |

Nothing else is bound. The window has the input focus, so the player controller's `IsInputKeyDown` sees no key while
it is open (seen in the game, below), and the game's window doesn't close on Esc, Backspace or B itself. So the mod
binds Esc and Backspace with `RegisterKeyBind`, and reads B through the game's own system input
(`UEndSystemAPI.IsInputKeyDown` on its default object, `Gamepad_FaceButton_Right`), which does see the pad while the
window is open. Every window keeps its Back or Cancel row as well. Esc pressed in the window still reaches the fight:
the game opens its Pause menu once the window has gone. So after a back key the mod hides its window, waits 0.5 s with
none of its own (where `UEndMenuAPI.IsPauseMenuClosed` can only mean the fight's Pause menu), closes that menu with
`HidePauseMenu` if it opened, then shows the next window and pauses again, or closes. B opens no Pause menu.

The meters bind their own keys, not this menu's: F9 next meter, F5 clear, F6 reset stagger, F8 show/hide, and no pad
button (the pad reaches them only through this menu's meter rows). Their panel hides while the game is paused, so it
is never over this window.

Custom Training's own panel used F7 and LB+RB in the course too; with this menu it is switched off (`ct_panel = off`,
asked of custom-training), so the two never take the same press.

## The design

The game's own choice window (`UEndMenuAPI.ShowMessageWindow`, widget `Com_Window_01_C`) is the menu. It is the window
the game uses for its own questions, it draws in the field and in battle, and the game itself moves its cursor and
confirms with the pad and the keyboard, drawing the device's own button icons (they change as soon as the other device
is used). The mod only chooses what each window shows and what a choice does.

```
Custom Training
(A) Change a setting, then Apply

  Opponent:   Deathclaw
  Number:   2
  Behaviour:   Passive
  Difficulty:   Normal
  Meter:   Damage           (these three rows only with the meters part)
  Clear meter
  Reset stagger
  Apply
  Cancel
```

- **Confirm on a setting** opens the list of its values (Number 1 to 3; Passive, Aggressive, Healing; Easy, Normal,
  Dynamic, Hard; Damage, Tanking, Healing, Hidden), then Back; the window's text says the current one ("Now:
  Aggressive"). A value chosen comes back to the main window. The game's window can't be told where to put its
  cursor (below), so every window opens on its first row.
- **Confirm on Opponent** opens the kinds of enemy (Humans, Machines, Beasts, Anomalies, Summons and others), then for a
  kind with more than 12 names the ranges of names ("Citripine Schoolmaster  -  Death Claw"; both names whole when
  they fit the row's 44 characters, else the longer one is cut at a word), then the names. A kind with
  more than 144 names is cut in two by first letter ("Beasts (A-H)"), so a name is never more than three windows away.
  Each of these windows says the current opponent ("Now: Titan Boss").
  Every window has at most 12 choices and Back: the window grows with its rows instead of scrolling, and 13 rows fit.
- **Apply** hands every change to Custom Training at once; **Cancel** closes without changing anything.
- The game is paused while it is open (`GameplayStatics.SetGamePaused`, as Junon Colosseum's boon window does).
- Any opponent comes in one to three copies, with no "(boss)" tag anywhere (owner, 2026-11-21). An opponent Custom
  Training still caps at one copy carries `max_count = 1` in `lists()`; its Number row reads "1" and opens no list, and
  a larger number chosen before is handed over as 1. Without its own `max_count` an opponent gets the list's
  (`lists().max_count`, 3). A `boss` field is ignored.
- **The meters** (ws/meters), when installed, add the rows Custom Training's panel had: **Meter** is chosen from its list
  and applied with the rest; **Clear meter** and **Reset stagger** act as soon as they are confirmed, and the window
  comes back on the same row with the draft kept.

#### Mixed groups and pre-built rounds (1.0; offline 2026-11-21, in the game once Custom Training's side lands)

The main window follows what Custom Training's `lists()` offers; without the new fields it is exactly as above.

```
Custom Training
(A) Change a setting, then Apply

  Mode:   Opponents         (with courses: Opponents / Round)
  Opponent 1:   Deathclaw   (with group_max: three rows, no Number)
  Opponent 2:   Deathclaw
  Opponent 3:   None
  Behaviour:   Passive
  ...
```

- **Opponent 1, 2, 3** each open the kinds → ranges → names lists; Opponent 2 and 3 also have **None** (the row before
  Back). The same opponent in several rows gives copies, so the Number row goes. A new row's list opens where the row above
  is (its kind, range and name), so another copy is a few confirms away. A group has no gaps: None in Opponent 2 moves
  Opponent 3 up, and confirming Opponent 3 while Opponent 2 is None picks Opponent 2. A copy beyond an opponent's
  `max_count` is refused on the names window ("At most 1 Alexander at a time"), and the window stays.
- **Mode: Round** replaces the opponent rows with one **Round** row ("Round:   Titan - Round 1"). It opens the
  simulator's tabs that have courses, in the simulator's order. Next come the tab's courses (in windows of ranges
  past 12), then the course's rounds (past 12, "Rounds 1 - 8" windows first). A round reads "Round 2: 2 Cerulean
  Drake, 1 Sandworm": the round's name, then its enemies with the count first. The longest enemy name gives
  way first when it doesn't fit 44 characters. Every window says "Now: <course>, round N".
- Behaviour, Difficulty, the meter rows, Apply and Cancel stay. The most rows any window has is 11 (Mode, three
  opponents, Behaviour, Difficulty, three meter rows, Apply, Cancel).
- Apply hands over `group = { id, id, id }` in Opponents mode, `round = id` in Round mode, and `mode` when it changed.

#### Stages (owner 2026-11-21: filter opponents by stage, don't limit stages)

Every stage is offered for Custom Training; what needs more room than the loaded stage has can't be chosen there.
- With a stage loaded, the main window's text has a line "Stage: Cave of the Gi".
- An opponent or round that needs more room is marked " (larger stage)" in the names and rounds lists. The name or
  round text is cut first, so the row still fits 44 characters.
- An opponent is judged with the rows already filled, by Custom Training's rule: a group needs the most any member
  needs, plus 2 m for each enemy beyond the first. Beside a Bandit, a 24 m opponent needs 26 m.
- Confirming one keeps the window and says "Needs a larger stage than Cave of the Gi" (once).
- A pick made before the stage changed shows the same mark on its main-window row; Custom Training's apply is the
  backstop.
- On the plain arena nothing is marked.

The fields are custom-training's (ws/custom-training 78d80c9, 2026-11-21), with the names ui proposed:
- `needs_m` is always set on each opponent and round, in metres. Every opponent needs at least 12; Phoenix needs
  the most, at 28.3. A round needs its course's.
- In the development file `needs_m` is field 7 of an opponent line and field 8 of a round line.
- `state()` has `stage_name`, `room_m` (both unset on the plain arena), `needs_m` (the current setup's) and
  `fallback`. The ui reads the stage from `state()`, and from `lists()` only with a Custom Training that has no rooms.
- The `fallback` line is not shown: the main window's rows already show what the course fell back to.

Checked with `tests/ui/with_ct.py` against 78d80c9 on four stage sizes: Shinra Manor 13 m, Cave of the Gi 18,
Gongaga 22 and Midgar Outskirts 25.
- The menu's refusals match `ct_api.apply` for 22,149 groups and all 227 rounds on each: 0 disagreements.
- On Shinra Manor (13 m) only single 12 m opponents fit: every group of two or more needs at least 14 m, so 21,960
  groups and 62 rounds are refused there.

`matrix.py --only stage` shoots the stage line, a marked names window and its refusal, and a marked rounds window and
its refusal.

#### Respawn (owner 2026-11-21: enemies don't refill; the player brings the fight back)

- With a Custom Training that respawns, **Respawn** is the main window's first row. That means `ct_api.respawn()`
  exists and `state()` counts waves (`wave`).
- The menu opens with the cursor on Respawn, so on the pad LB+RB then A brings the fight back. On the keyboard it's
  F7 then Enter.
- It acts at once: the menu closes, the game resumes, and `ct_api.respawn()` is called. Changes not yet applied are
  dropped; Apply is still the way to change the setup.
- While the round waits after a clear, the window's text says "Wave cleared in 1:23" (from `state().cleared` and
  `cleared_in_s`). With a Custom Training that doesn't send `cleared`, it says "Last wave cleared in 1:23" from
  `last_clear`.
- Rows: Respawn, Mode, three opponents, Behaviour, Difficulty, three meter rows, Apply and Cancel is 12, within 13.
- Custom Training's fields (ws/custom-training a9d8c39, 2026-11-21):
  - `respawn()` returns true, or false and why.
  - `state().wave`, `cleared` (true only while the round waits), `cleared_in_s` (set while it waits) and
    `last_clear`.
  - Dev files: a `respawn` line in `ct-command.txt`, and `cleared=` and `cleared_in_s=` in `ct-course.txt`.
- Clears and Respawn only matter much under Aggressive (owner): there enemies die and a cleared wave waits. Under
  Passive and Healing enemies are held and refilled as before, and Respawn still works.
- `with_ct.py` against 7111339 checks that Respawn comes first. Seen in the game in the fifth run, by keyboard and pad.

Code: `ui_menu.lua` runs it, `ui_model.lua` decides what each window shows and what a choice does (offline-tested),
`ui_window.lua` makes the game calls, `ui_keys.lua` reads the opening chord, `ui_ct.lua` talks to Custom Training.

### The interface with Custom Training

`ui` calls Custom Training's `ct_api` (on `ws/custom-training`): `state()`, `lists()` and `apply(changes)`. In the
integrated mod that is `require("ct_api")` in the same Lua state. During development the two are separate Lua states,
so `ui_ct.lua` is a file bridge to Custom Training's development files (its `dev.txt`):

| File (in `SimOverhaulCustomTraining\`) | Written by | Used for |
| --- | --- | --- |
| `ct-course.txt` | custom-training, on every start, end and change | `state()`, and whether a course is running |
| `ct-lists.txt` | custom-training, at each start and on the `lists` command (asked for) | `lists()`; until it exists, the bridge reads `ct_catalogue.lua` and names opponents with the game's text |
| `ct-command.txt` | ui | `set opponent=… count=… behaviour=… difficulty=…` (with groups and rounds also `group=ID,ID,ID`, `mode=opponents\|round`, `round=ID`), which Custom Training passes to `ct_api.apply` |

The fields for groups and rounds follow custom-training's proposal of 2026-11-21, which ui accepted. Custom Training
builds them after its current game run.
- `lists()`:
  - `group_max = 3`.
  - `conflicts = { { id, id } }`: pairs whose own adds need the same wave slot. This is ui's addition and is not yet
    confirmed.
  - `courses = { { id, name, tab, tab_name, rounds = { { id, number, name = "Round 1", enemies = "Wererat ×2,
    Elphadunk ×2", size } } } }`, sorted by tab, then in the game's order.
  - The ui shows a round as "Round 1: 2 Wererat, 2 Elphadunk". It takes `enemies_list = { { name, count } }`
    first if Custom Training adds it.
- `ct-lists.txt` lines:
  - `group_max n`
  - `conflict id id`
  - `course id tab tab_name name`
  - `round course_id round_id number size name enemies`
- `state()` / `ct-course.txt`: `mode`, `group` (one id per enemy, `ID,ID,ID` in the file), `group_names`, `course`,
  `round` and `round_name`. `opponent` (= group[1]) and `count` (= #group) stay.
- `apply`: `group` (1 to 3 ids), `round` (which also sets the mode), `mode`. A cap counts across the group.

Checked offline against custom-training's own `ct_api` and its whole catalogue (ws/custom-training f448cfd,
2026-11-21), with `python tests/ui/with_ct.py <its Scripts folder>`:
- Every window the menu can show for the real lists has at most 13 rows, and no list row is longer than 44
  characters: 348 windows over 207 opponents and 63 courses.
- Every one of the 227 rounds can be chosen, and ct_api takes it.
- The menu refuses exactly the groups `ct_api.apply` refuses, over 21,942 groups (every pair and 414 triples): 52
  refused by both, 0 disagreements.
- Course names fall back to row ids offline, so they are checked in the game.

Custom Training's own panel stays shut when its `settings.txt` says `ct_panel = off`, and in the integrated mod
whenever `pcall(require, "ui_menu")` succeeds (agreed with custom-training, 2026-11-21).

The meters (`ui_meters.lua`) are reached the same way: `require("meters_api")` integrated (`state()` and `act(action)`,
from the header of the meters' `meters_api.lua`), and during development the meters' own files in
`SimOverhaulMeters\`:

| File (in `SimOverhaulMeters\`) | Written by | Used for |
| --- | --- | --- |
| `meters-state.txt` | meters, after every change | whether the meters are there, and the meter shown (`meter`, `label`, `visible`) |
| `meters-command.txt` | ui | one action a line: `meter=damage\|taken\|heal`, `show`, `hide`, `clear`, `stagger` |

## The candidates

| Candidate | Looks | Keyboard and pad | Mid-fight, paused | Game-thread cost | Verdict |
| --- | --- | --- | --- | --- | --- |
| **The game's choice window** (`ShowMessageWindow`, `Com_Window_01_C`) | the game's own window, cursor, sounds; text rows only | ✅ the game handles up/down/confirm on both, with each device's icons; no cancel of its own; the mod can't read keys while it is open | ✅ opens mid-fight and works under `SetGamePaused` (seen 2026-11-21) | nothing per frame: the mod reads no keys while it is open, only whether it has closed | **chosen** |
| The simulator's own course menu (`VR_Top_C`, `UEndColosseumMenu`: course list, info window, `DifficultyWindow`, summon level select, character select) | the simulator's own look | the game's | ❌ only before a course starts: it is the menu that starts a course, not one that opens inside it | – | not for in-course changes; a later idea for the course row's own details |
| The pause menu (`Pause_00_C`, `UEndPauseMenu.OptionScrollBox`, mode `Colosseum`) | the most natural home: Start/Esc, then "Custom Training" | the game's | the game pauses | none | 📖 adding a row means `SetItemCount` plus setting up our row's text; pressing it runs the game's `OnListMenuPressedItem` with an index past its own list, which a Lua hook can't stop (UE4SS hooks can't skip the native call). Needs a native detour; not now |
| An options list (Settings, Combat Settings: `UEndMainOptionsMenu`, rows `MainMenu_Options_Btn2_C` with title, value and left/right arrows) | closest to the owner's mock-up: a title and a value with arrows per row | the game's, inside its own menu | it is a main-menu screen | – | ❌ for its own list: `_OptionItems` is a `TMap` UE4SS can't read (Battle Meters). 📖 Its row widgets could be spawned and filled by the mod, but then the mod draws and drives them itself (what the hand-built panel already does) |
| Spawning the game's widget classes and filling them | the game's art | the mod's own input handling | yes | widget updates by the mod | 📖 creating `EndTextBlock`/`EndImage` at runtime draws nothing (Training Dummy); whole widget blueprints (`Com_Window_01_C` is one) are created by the game's own calls. Kept as the next step if the window is not enough |
| `UEndMenuAPI.ShowDebugListBox` | a debug list | – | – | – | 📖 a developer tool (latent, string list); not for players |

## In the game

### First run (2026-11-21, 01:48–02:02 UTC, slot 25, Cloud solo against a Shirdal)

The first design (left and right changing a setting in place, LB/RB jumping by kind), with separate development
installs: ui, and Custom Training's older installed build (no `ct_panel`, no `ct-lists.txt`; the lists came from its
catalogue through the bridge). Keyboard presses came from the harness's `battle_menu_tap` (Up and Down are the arrow
keys, Confirm Enter, Cancel Esc, its left and right are Q and E), pad presses from `battle_pad_chord` holding one
button (`switch_next` is D-pad Down, `cross` is A, `shortcut` is LB). Anything else is marked as a development command.
Screenshots: [run1/](ui/run1/).

| | What | How driven | Seen |
| --- | --- | --- | --- |
| ✅ | The window opens mid-fight and pauses the game; the main window looks like the game's own | dev `menu` | [old-main-keyboard](ui/run1/old-main-keyboard.jpg) |
| ✅ | The game draws button macros as icons, in the text and in rows, for the device in use: arrows, Z, X, the mouse on the keyboard; the D-pad, LB, RB, A on the pad, switching as soon as the pad is used | dev `probe 9`; pad D-pad Down | [keyboard](ui/run1/window-9-rows-keyboard-icons.jpg), [pad](ui/run1/pad-down-moves-cursor-pad-icons.jpg) |
| ✅ | The window grows with its rows instead of scrolling: 13 rows fit, 30 run off the top and bottom | dev `probe 13`, `probe 30` | [13](ui/run1/window-13-rows-fits.jpg), [30](ui/run1/window-30-rows-overflows.jpg) |
| ✅ | Rows and the text can be rewritten in the open window (no reopening) | dev `key right`, `key next_kind` | [after](ui/run1/old-main-after-right-and-next-kind.jpg) |
| ✅ | The focused row can be read (`IsHovered` on the row's button) | log | – |
| ✅ | Up and Down move the window's cursor, from the keyboard and the pad; Up on the first row wraps to the last | `battle_menu_tap` up/down; pad D-pad Down | [keyboard](ui/run1/keyboard-down-moves-cursor.jpg), [pad](ui/run1/pad-down-moves-cursor-pad-icons.jpg) |
| ✅ | Confirm closes the window with the row's index, from the keyboard (Enter) and the pad (A); the mod follows it: Opponent opened the kinds, Beasts its names, Back went back, A on Number applied | `battle_menu_tap` confirm; pad A | [kinds](ui/run1/kinds-after-enter.jpg) |
| ❌ | Held keys while the window is open: neither Q/E (keyboard) nor LB (pad) reached the mod, paused or not. The window has the input focus, so `IsInputKeyDown` reads nothing | `battle_menu_tap` left/right; pad LB | log: no key lines |
| ❌ | Back (Esc) on the window: paused, nothing happens; unpaused, Esc opens the battle's Pause menu over the window | `battle_menu_tap` cancel | [paused](ui/run1/esc-paused-does-nothing.jpg), [unpaused](ui/run1/esc-unpaused-opens-pause-menu.jpg) |
| ❌ | Putting the cursor on the current name when the list opens (`SetKeyboardFocus` right after the window was built): the cursor stayed on the first row | – | [names](ui/run1/old-names-16-pages.jpg) |
| ❌ | The pad chord opening the menu: RB held, LB pressed (120 ms and 600 ms together), game unpaused, after the window had been opened and closed several times: neither this menu nor Custom Training's panel opened (Custom Training saw its chord work on 2026-11-20, before any choice window) | `battle_pad_chord` guard + shortcut | – |
| 🟡 | Beasts had 16 pages of 10 names | – | [names](ui/run1/old-names-16-pages.jpg) |

What changed from it: everything inside the window is now done with the cursor and confirm (the value lists), Back
and Cancel are rows, the opponent list is kinds, ranges and names of at most 12 (no "More" pages), and the cursor is
put on the current value with retries after the window has settled, by three ways in turn (`SetKeyboardFocus`,
`SetUserFocus`, `SetFocus`), logging whether it took. To check next: the chord before any window has opened and after
one has closed, and whether giving the input back to the game (dev `inputmode`, `SetInputMode_GameOnly`) brings it
back; then the full screenshot matrix (`tools/ui/live/matrix.py`).

### Second run (2026-11-21, 05:27–07:05 UTC, slot 25, Cloud solo; integrated build)

The integrated build Custom Training installed at 03:37 (main 654fc3b: every part, Custom Training's panel shut by
`ui_menu`), with only ui's scripts swapped in as they changed (`INSTALLED.txt` lists each swap and its hashes; the
build's own files are in `ui-swap-2026-11-21\`). Every press is a real one through the harness's `press_key` /
`press_pad` (runtime with PR 787); no development command was used except the matrix's. Screenshots:
[run2/](ui/run2/), [walk-keyboard/](ui/walk-keyboard/), [walk-pad/](ui/walk-pad/), [matrix/](ui/matrix/).

| | What | How driven | Seen |
| --- | --- | --- | --- |
| ✅ | F7 on the simulator's course list opens Simulator Stages' picker and nothing else: this menu refuses (no course running), Custom Training's panel stays shut | `press_key F7` on the list | [picker](ui/run2/01-course-list-after-f7.jpg) |
| ✅ | The pad chord (RB held, LB pressed) opens the menu in a fight, before any window had been open; the game pauses, the pad's icons show | `press_pad lb hold=rb` | [main](ui/run2/03-chord-opens-main-pad.jpg) |
| ✅ | The chord again after windows had been opened and closed (run 1's ❌ was the chord pressed while a window was still open) | `press_pad lb hold=rb` | log |
| ✅ | F7 in a fight opens exactly one window (this menu; no Custom Training panel); F7 again closes it, the fight resumes | `press_key F7 field=true` | [main](ui/walk-keyboard/01-main.jpg), [closed](ui/run2/10-after-f7-close.jpg) |
| ✅ | Backspace: Back on a list, Cancel on the main window, the fight resumes | `press_key BackSpace` | [list → main](ui/run2/09-after-backspace-on-values.jpg), [closed](ui/run2/32-after-backspace-on-main.jpg) |
| ✅ | Esc: Back on a list (main window, cursor shown, fight paused), Cancel on the main window (fight resumes); the Pause menu Esc opens is closed in the gap, both times (log `pause menu closed after the back key`) | `press_key Escape` | [list → main](ui/run2/30-after-esc-on-values.jpg), [closed](ui/run2/31-after-esc-on-main.jpg) |
| ✅ | Value lists and opponent lists say the current value | keyboard | [values](ui/run2/15-values-now-keyboard.jpg), [ranges](ui/run2/17-ranges-keyboard.jpg), [names](ui/run2/18-names-keyboard.jpg) |
| ✅ | Keyboard walk: every row, every setting changed (opponent, number, behaviour, difficulty, meter), Apply; Custom Training swapped the opponent and the meters changed meter; reopened, Cancel | `walk.py keyboard` | [walk-keyboard/](ui/walk-keyboard/) |
| ✅ | Pad walk: the same with the D-pad and A, opened with the chord | `walk.py pad` | [walk-pad/](ui/walk-pad/) |
| ✅ | Apply changes the fight at once: Titan Boss → Black Bat, passive | keyboard | [before](ui/run2/20-cursor-on-apply-keyboard.jpg), [after](ui/run2/21-after-apply.jpg) |
| ✅ | 13 rows with a two-line text fit the screen (a full names page and Back) | – | [12 rows](ui/run2/18-names-keyboard.jpg), [13 (run 1)](ui/run1/window-13-rows-fits.jpg) |
| ❌ | Esc closing the window at once: the game then opened its Pause menu over the fight; closing it later (0.4 s, after the key's release) didn't help either | `press_key Escape` | [pause](ui/run2/05-after-esc-on-main.jpg) |
| ❌ | Esc on a list with the mod reading `IsPauseMenuClosed` while its own window was up: it counted the mod's window (it carries the `PauseMenu` flag), so the mod closed and reshowed it every tick, and `HidePauseMenu` let the fight run behind the menu | `press_key Escape` | [fight running](ui/run2/28-after-esc-on-values.jpg) |
| ❌ | Putting the cursor on a row (`SetKeyboardFocus`, `SetUserFocus`, `SetFocus`): the visible cursor never moved, and moving the keyboard focus off the window let Esc through to the Pause menu | – | [no cursor](ui/run2/26-after-esc-on-values.jpg) |
| ✅ | Esc with the menu shut still opens the fight's Pause menu (the mod's Esc does nothing then) | `press_key Escape field=true` | [pause](ui/run2/33-esc-with-menu-shut-pauses.jpg) |
| ✅ | Screenshot matrix, main window: the shortest and longest name of every kind, a boss of each kind that has one, every behaviour, difficulty, number and meter; every value list; the kinds and the first ranges window | dev `draft`, `pick` (`matrix.py`) | [matrix/](ui/matrix/) |
| 🟡 | The longest names on the main window's Opponent row: the game squeezes the row's text to fit, readable but narrow. They are Custom Training's labels with the game's internal variant tags ("Citripine Schoolmaster (Tropical Rare End2_G2)", "Junon Elite Security Officer (Senior Junon Ver1)", "Test 0 (Test Zero Another Voice)") | `matrix.py` | [k3 longest](ui/matrix/main-k3-longest.jpg), [k1 longest](ui/matrix/main-k1-longest.jpg) |
| ❌ | The whole SimulatorOverhaul Lua state was lost at 06:46:45, 2 s after the matrix's last window: UE4SS logged `The lua state ... has no instance inside lua_instances` from ui's `LoopAsync` → `ExecuteInGameThread`, and every part (meters, Custom Training) stopped until the game was restarted. Once in this run; the matrix's remaining list shots were dropped | `matrix.py` | `ui-lua-state-lost-2026-11-21.log` in the shared notes folder |
| 🟡 | B on the pad didn't close the window here (120 ms and 300 ms, game paused by the mod); Custom Training saw it close and unpause once. The pad's way back is the Back and Cancel rows | `press_pad b` | [still open](ui/run2/04-after-b.jpg) |

### Third run (2026-11-21, 10:54–11:30 UTC, slot 25, Cloud solo; integrated build)

Custom Training's integrated install (ws/custom-training 5f23191, with its cleaned opponent labels) with ui's seven
scripts swapped in from ws/ui fa5518b, then `ui_model.lua` again for the range labels (`INSTALLED.txt` has the hashes;
backups in `custom-training-build\ui-swap-20261121T1055Z`). Presses through the harness's `press_key` / `press_pad`.
Screenshots: [b-test/](ui/b-test/), [matrix/](ui/matrix/) (`list-*`).

| | What | How driven | Seen |
| --- | --- | --- | --- |
| ✅ | B on a value list (Behaviour): back on the main window, the fight still paused (log `pad back B true`, `back key`) | `press_key F7`, `press_pad b` | [before](ui/b-test/01-values-before-b.jpg), [after](ui/b-test/02-after-b-on-values.jpg) |
| ✅ | B on the main window: the menu closes, the fight resumes (harness `paused: false`), no Pause menu | `press_pad b` | [before](ui/b-test/03-main-before-b.jpg), [after](ui/b-test/04-after-b-on-main.jpg) |
| ✅ | Pad only (opened with the chord): B on the kinds → main; B on a ranges window → kinds | `press_pad lb hold=rb`, `a`, `dpad_down`, `b` | [kinds](ui/b-test/05-kinds-before-b.jpg), [→ main](ui/b-test/06-after-b-on-kinds.jpg), [ranges](ui/b-test/07-ranges-before-b.jpg), [→ kinds](ui/b-test/08-after-b-on-ranges.jpg) |
| ✅ | B four times from a names window: names → ranges → kinds → main → closed, the fight resumed | `press_pad b` | [names](ui/b-test/09-names-before-b.jpg), [ranges](ui/b-test/11-after-b-on-ranges.jpg), [closed](ui/b-test/13-after-b-on-main-closed.jpg) |
| ✅ | Screenshot matrix, list windows: the kinds, every kind's ranges and the names window holding its longest name, with Custom Training's cleaned labels; nothing clipped or squeezed | dev `draft`, `pick` (`matrix.py --only lists`) | [Humans ranges](ui/matrix/list-s1-ranges.jpg), [Beasts ranges](ui/matrix/list-s3-ranges.jpg), [Humans names](ui/matrix/list-s1-names.jpg), [Summons names](ui/matrix/list-s5-names.jpg) |
| ✅ | Range labels whole ("Citripine Schoolmaster  -  Death Claw", "2-C SOLDIER Operator  -  Flametrooper"); before the change they were cut at 20 characters a side ("Citripine Schoolmas...") with room to spare | `press_pad` | [cut](ui/b-test/07-ranges-before-b.jpg), [whole](ui/matrix/list-s3-ranges.jpg) |
| ✅ | No repeat of the lost Lua state (no `lua_instances` line in UE4SS.log) through the B test and the list matrix | – | UE4SS.log |
| 🟡 | The game quit on its own about two minutes after the first load (10:58), before any input of this run: no crash dump, no Application error event, UE4SS.log ends normally (Biome Randomizer's last lines). Not seen again | – | – |

### Fourth run (2026-11-21, 18:14–18:56 UTC, slot 25, Cloud solo; integrated build)

**Install.** The integrated install had Custom Training at ws/custom-training 7f7e111, with mixed groups, Round mode
and the room filter. Into it went ui's `ui_model.lua`, `ui_ct.lua` and `ui_main.lua` from ws/ui a0f37dd. After the
label fix, `ui_model.lua`, `ui_ct.lua` and `ui_menu.lua` went in again from 1190fa5. `INSTALLED.txt` has the hashes;
the backups are in `custom-training-build\ui-swap-20261121T1814Z`.

**Entry.** The course was entered by Chadley's talk (the machine is out of the mod). Custom Training's `to_course.py`
stopped at the team screen: the leader row's label key isn't reported until the list has settled. Cloud was then
picked by hand through the harness.

**Stages.** The stage was Edge of Creation (30 m) for the first matrix and Midgar Outskirts (25 m) after the restart.

Screenshots: [matrix/](ui/matrix/), [walk-keyboard/](ui/walk-keyboard/), [walk-pad/](ui/walk-pad/).

| | What | How driven | Seen |
| --- | --- | --- | --- |
| ✅ | Former bosses' main window: no "(boss)" anywhere; Opponent 1 holds the longest name of each kind, Opponent 2 and 3 None | dev `draft` (`matrix.py`) | [Summons](ui/matrix/main-k5-boss-longest.jpg), [Anomalies](ui/matrix/main-k4-boss-longest.jpg), [Beasts](ui/matrix/main-k3-boss-longest.jpg) |
| ✅ | Mixed group with three long names of different kinds, copies, two rows: 11 rows, the "Stage: Edge of Creation" line, nothing clipped | dev `draft` | [three](ui/matrix/main-group-longest-three.jpg), [copies](ui/matrix/main-group-copies.jpg), [two](ui/matrix/main-group-two.jpg) |
| ✅ | Mode's values, and Round mode's main window | dev `pick` | [Mode](ui/matrix/values-mode.jpg), [Round row](ui/matrix/main-round-longest.jpg) |
| ✅ | The round list: the simulator's own tab names (Summon Entities ... Shinra Manor: Evaluations, 8 tabs), every tab's courses, Battle Intel's 16 courses in two ranges, a round window for every tab | dev `pick` (`matrix.py --only rounds`) | [tabs](ui/matrix/rounds-tabs.jpg), [ranges](ui/matrix/rounds-t2-ranges.jpg), [Brutal rounds](ui/matrix/rounds-t5-c1-rounds.jpg) |
| ❌→✅ | Brutal Challenges' rounds (five or six kinds of enemy) were unreadable, every name cut to five letters ("Round 1: 1 Thund..., 1 Frigh..., 1..."). Fixed in 1190fa5 and reshot: whole names and "+N" ("Round 1: Kyuvildun, Carnifex +4"), counts only above one, course ranges and the Round row without the words a tab's courses share ("Grasslands Horror on the Range") | dev `pick` | [Brutal rounds](ui/matrix/rounds-t5-c1-rounds.jpg) |
| ✅ | Stage marks: on Midgar Outskirts (25 m) Experimental Varghidpolis (26.5 m) reads "(larger stage)" in Anomalies' names; confirming it keeps the window with "Needs a larger stage than Midgar Outskirts"; a round of Phoenix likewise | dev `draft`, `pick` (`matrix.py --only stage`) | [names marked](ui/matrix/stage-names-marked.jpg), [refused](ui/matrix/stage-names-refused.jpg), [round marked](ui/matrix/stage-rounds-marked.jpg), [refused](ui/matrix/stage-rounds-refused.jpg) |
| ✅ | Keyboard walk: F7, every value list, Opponent 1 through kinds → ranges → names, Opponent 2's kinds with None, None, a name for Opponent 2, Mode → Round, Round → tab → course → round, Apply (mode=round, Titan's round 1, applied `true`), reopened and Cancel | `press_key` (F7, Up/Down, Enter) (`walk.py keyboard`) | [Opponent 2 kinds](ui/walk-keyboard/12-kinds-opponent2.jpg), [round mode](ui/walk-keyboard/16-main-round-mode.jpg), [after round](ui/walk-keyboard/20-main-after-round.jpg) |
| ✅ | Pad walk: the same, opened with LB+RB, the D-pad and A, with the pad's icons; Titan's round came in (`SU2000_01` on the field) | `press_pad` (`walk.py pad`) | [Opponent 2 kinds](ui/walk-pad/12-kinds-opponent2.jpg), [rounds](ui/walk-pad/19-round-rounds.jpg), [Titan](ui/turn4/05-titan-round.jpg) |
| 📖 | Respawn row: not in this install (Custom Training 7f7e111 has no `respawn()`), so the menu showed none, as intended; offline tests and `with_ct.py` against 2bc9e17 | – | – |

### Fifth run (2026-11-21, 23:30–23:40 UTC, slot 25, Cloud solo, Cave of the Gi; integrated build)

**Install.** Custom Training's install of ws/custom-training 830503f (main c909240 with its fixes), which already
held ui's latest scripts (main has a274ea1). Nothing was swapped.

**Entry.** By Chadley's talk, with `to_course.py launch`. Cloud was picked alone by hand: the team screen's leader row
isn't reported until the list has settled.

**Driving.** One Bandit (Scimitar), Aggressive. Wave 1 was brought to 1% with Custom Training's dev `hp 1` and
finished by the harness's autopilot. Script: `respawn_live.py` (scratch), on custom-training's `wave_check.py`
helpers. Screenshots: [turn5/](ui/turn5/).

| | What | How driven | Seen |
| --- | --- | --- | --- |
| ✅ | After a clear, the menu opened by F7 shows "Wave cleared in 0:05" and the stage, with **Respawn** first and the cursor on it (12 rows) | `press_key F7` | [menu](ui/turn5/1-keyboard-cleared-menu.jpg) |
| ✅ | Enter on Respawn: the menu closes (`close respawn`, `respawn true`) and wave 2 comes | `press_key Enter` | [after](ui/turn5/1-keyboard-after-respawn.jpg) |
| ✅ | The same by pad: LB+RB opens it on Respawn with the pad's icons, A brings wave 3 | `press_pad lb+rb`, `a` | [menu](ui/turn5/2-pad-cleared-menu.jpg), [after](ui/turn5/2-pad-after-respawn.jpg) |
| ✅ | The respawned Bandit was dead 4.7 s and 2.3 s after each Respawn with no input (ct-log `wave 2 cleared in 4.7 s`, `wave 3 cleared in 2.3 s`). custom-training's reading: Cloud (level 70, Punisher Mode) counters a level-22 Bandit's swing at once; each respawn brought a fresh one. Not a fault. The run did catch one in Custom Training (a stale wave-row search, fixed on ws/custom-training 868928f): the Bandit was its built-in fallback | – | [dead Bandit](ui/turn5/2-pad-after-respawn.jpg) |

## Dead ends

| Tried | Result |
| --- | --- |
| Left and right (and LB/RB) read by the mod while the choice window is open | The window has the input focus: `IsInputKeyDown` sees no key from either device (2026-11-21). Replaced by value lists |
| A "More" page for long kinds | Beasts needed 16 pages; replaced by ranges of names |
| Placing the window's cursor (three focus ways, with retries) | Never moved the visible cursor; it took the focus off the window, letting Esc reach the Pause menu. Off (`place_cursor`); the lists say their current value instead |
| Keeping the game paused until Esc is up | The Pause menu opens anyway once the window has gone; replaced by closing it in the gap after a back key |

## Open

- The lost Lua state (second run): once, after about 20 minutes of the menu's 50 ms loop and the matrix's rapid
  windows; not seen in the third run. Handed to crash-220 to root-cause in UE4SS's source; the game-thread pattern
  (`LoopAsync` with `ExecuteInGameThread`) stays as it is until that reports.
