# Workstream `party`: Zack and Sephiroth in Custom Training

Marks: ✅ seen in game · 🟡 partly · ❌ tried and failed · 📄 read from the tables only

## What the owner will see

Choosing Custom Training opens the game's own team screen with **all nine characters**: the seven party members in
the party's order, then **Sephiroth** and **Zack**. Pick one to three, in any order; the first is the leader. Zack and
Sephiroth fight at Cloud's level (70 on the test save), with their own HP, MP and commands (Sephiroth's Aura Charge).
The battle HUD, character switching, Battle Meters and the result screen treat them like any party member. After the
course the normal party is unchanged. Other courses are unchanged.

## How it works ✅

**One value on Custom Training's course row: `ExtendedSequenceBits = 6`** (`data/party.json`, `courseRow.set`;
`custom-training`'s build folds it in). Nothing at runtime.

`ExtendedSequenceBits` is the game's own switch. On a course whose `EntryMember_Array` is empty, value 2 adds Sephiroth
and 4 adds Zack to the end of the team list, after everyone in the party. The four vanilla courses with Zack or
Sephiroth set it the same way (Zack 4, Sephiroth 2), alongside a fixed `EntryMember_Array`, which hides the effect there.
The name suggests it also loads their extra sequences; the battle intro, the clear and the result screen all played
normally with it set.

Tables changed by this workstream: none of its own (no pak in the release). Rows added: none. Keys bound: none. No
Lua. Development only: test pak `SimOverhaulPartyTest_9300_P` (`tools/party/Build-PartyTest.ps1`, Colosseum only, built
on Junon Colosseum's installed table so it hides no installed course), installed only while this workstream held the
game lock, removed afterwards.

## How the vanilla courses do it 📄 ✅

| Course | `EntryMember_Array` | `PartyMax` | `MemberSelectionTextID_Array` | `ExtendedSequenceBits` |
| --- | --- | --- | --- | --- |
| `COL30_EXTRA_15_Free_Col` (Legendary Bout, Cloud & Zack, 10 rounds) | `pt_Cloud`, `pt_Zack` | 2 | `$menu_Colosseum_CourseRule_CloudZack_Only` | 4 |
| `COL30_EXTRA_14_Free_Col` (Legendary Bout: To Be a Hero, Cloud & Sephiroth) | `pt_Cloud`, `pt_Sephiroth` | 2 | `$menu_Colosseum_CourseRule_CloudSephiroth_Only` | 2 |
| `COL1Z_TutorialBtl_01_Zack_Vr` (Combat Training: Zack, 2 rounds) | `pt_Zack` | 1 | `$menu_Colosseum_CourseRule_Zack_Only` | 4 |
| `COL1S_TutorialBtl_01_Sephiroth_Vr` (Combat Training: Sephiroth) | `pt_Sephiroth` | 1 | `$menu_Colosseum_CourseRule_Sephiroth_Only` | 2 |

- `EntryMember_Array`, when not empty, **is the team list** ✅: exactly those names, padded with empty rows to
  `PartyMax`; the player picks any of them in any order (Confirm Team is offered after the first pick). The vanilla
  courses list as many names as `PartyMax`, so their party is fixed.
- `EntryMemberFixedAbilityId_Array` and `ExtraRule_Array` are empty on all four. Other rows with `ExtendedSequenceBits`:
  the summon courses (1) and `COL30_GOLDA_21`, `COL11_UNDRS_00`, `COL30_NIBLS_04`/`08` (9); not tested.
- `PlayerTable`: `pt_Zack` (`PC0009_00_Zack_Standard`) and `pt_Sephiroth` (`PC0010_00_Sephiroth_Standard`) are full
  player rows with equipment release flags (`stfComn_Release_Equipment_Zack`, `..._WeaponChange_Zack`,
  `..._MateriaChange_Zack`, same for Sephiroth). `PlayerParameter` has their per-level stats.

## Results in game (2026-11-20, Epic 1.005, save slot 25 at Costa del Sol, nothing saved)

Test courses (`data/party/test-vanilla-copy.json`): rows cloned from `COL30_GRASA_01_Free_vr`, cut to its first round,
at the end of the Combat Training tab, no reward or clear flag. T1–T4 reuse vanilla title keys; T5 and T6 show their own
keys. Screenshots in `tests/party/evidence/`. Party read with `tools/party/party-probe.lua` (`EndPartyAPI`, through
Simulator Stages' eval console).

| Row | `EntryMember_Array` | `PartyMax` | Bits | Seen |
| --- | --- | --- | --- | --- |
| T1 | all nine | 3 | 6 | ❌ only the first three (Cloud, Barret, Tifa) offered (`04`) |
| T2 | `pt_Zack` | 3 | 4 | ❌ Zack and two empty rows; no normal party (`05`) |
| T3 | `pt_Cloud`, `pt_Zack`, `pt_Sephiroth` | 3 | 6 | ✅ those three, fought, cleared, result screen (`01`–`03`) |
| T4 | `pt_Zack`, `pt_Sephiroth` | 2 | 6 | not opened (T3 answers it) |
| **T5** | empty | 3 | **6** | ✅ **all nine, cleared with Zack + Sephiroth + Aerith and with Cloud + Barret + Tifa** (`11`–`13`) |
| T6 | empty | 3 | 0 | the normal seven (nine only with the reserve-status trick, below) (`10`) |

- ✅ **T5, the stand-in for Custom Training's row**, with Zack and Sephiroth at party status 0 (read back 0) and no
  Lua: team list Cloud, Aerith, Yuffie, Barret, Tifa, Red XIII, Cait Sith, **Sephiroth, Zack** (`11`). Picked Zack
  (leader), Sephiroth, Aerith (`12`); autopilot cleared it in 44.7 s; "Challenge Complete", time recorded, reward "---"
  (`13`). Production event `ac357ba2…` verified, interval certain. Then Cloud, Barret, Tifa cleared it in 27.7 s: the
  value changes nothing for a normal party.
- ✅ **T3**: Zack level 70 (HP 6922, MP 121, weapon level 0/0 SP), Sephiroth level 70 (HP 8000, MP 140). Battle slots:
  Cloud `PC0000_00`, Zack `PC0009_00`, Sephiroth `PC0010_00`; the other six at status 0 during the course. Won in
  83.5 s. Event `0c14e9f1…` verified.
- ✅ After every course, and on leaving the course list, the game restores its own party (normal battle members and
  reserve back; Zack and Sephiroth 0).

## For `custom-training`

- Apply `data/party.json` as it is (`courseRow.set.ExtendedSequenceBits = "6"`). Keep `EntryMember_Array` empty and
  `PartyMax 3`. Then open Custom Training and check the team list ends with Sephiroth and Zack.
- **Training Dummy's courses hang on "Get Ready" while your pak is installed** (seen with Training Dummy: DPS: no
  enemies ever appeared, give-up impossible, the game had to be closed). Likely: your pak's `EnemyTerritory` and
  `ColosseumPositionData` are built on the vanilla export, which drops Training Dummy's repurposed territory
  (`terVR_COL30_SUMMON_Gilgamesh_010_BtlTest_Hard`) and its added `POS_TD_TrainingDummy_010`. Junon Colosseum's
  courses read those tables too, and the owner has both mods installed.

## For `equipment`

- In a course Zack and Sephiroth are ordinary battle members (`EndPartyAPI:GetBattleMember*`, `EndBattleAPI:GetActorName`
  "ZACK"/"SEPHIROTH", `GetCharaID` `PC0009_00`/`PC0010_00`, player types 7 and 8). Outside a course their party status
  is 0 (NONE), so field menus built from the party will not list them.
- Their weapon, armour, accessory and materia are their own save data (weapon level 0/0 SP on this save); this
  workstream does not change them. To let the player change them inside Custom Training, the equipment screen has to
  take player types 7 and 8 while they are battle members. Not tested here.
- `PlayerTable` gates their menus with `stfComn_Release_Equipment_Zack` / `..._WeaponChange_Zack` /
  `..._MateriaChange_Zack` (same for Sephiroth): if the menu hides them, check those flags first.
- An `EndPartyAPI:GetEquipmentMenuMembers` read through the eval console came back empty for everyone, so it is no
  guide.

## Dead ends and detours

- ❌ More names than `PartyMax` in `EntryMember_Array` (T1): only the first `PartyMax` are offered.
- ❌ One fixed name with a bigger `PartyMax` (T2): the other rows are empty, not the normal party.
- 🟡 **Reserve status at runtime** (commit `6fca645`, removed after): `EndPartyAPI:SetPlayerStatus(7, 5)` and `(8, 5)`
  (RESERVE) while the course list was open made any course with an empty `EntryMember_Array` offer all nine: Training
  Dummy: DPS (`06`, `07`), vanilla Grasslands 1, where Sephiroth, Zack and Cloud won round 1 in 61 s (`08`, event
  `65ce5cbe…` verified), and T6 (`10`). A small Lua mod did it from the course-menu hooks. On T5 it listed Zack and
  Sephiroth twice (`09`), which is how the bits were found. Not needed for Custom Training. It would be the way to
  offer them in other courses, if the owner ever wants that. Lessons from it:
  - Lua hooks on `EndColosseumMenu:OnCourseMenuSelectedIndexChanged` fire before the menu updates its info window,
    so the title they read is the previous course's; reading again ~0.2 s later gets the right one.
  - `os.clock()` in UE4SS is process CPU time, not wall time: count loop ticks for delays.
  - The game restores the party when a course ends and when the course list closes, so a status set there never
    reaches the field.
- Training Dummy: DPS hung on "Get Ready" with Sephiroth, Zack and Tifa: the `custom-training` pak issue above, not
  the party (the same team fought in vanilla Grasslands 1 and T5).
- Harness notes: `start_and_load_save_slot_async` and `load_save_slot_async` only dry-run without `execute=true`. At
  Costa del Sol `use_field_action` refuses Operate while the planter's parkour prompt shows, so the simulator was
  entered through Chadley's Talk (a few `move_direction` steps from the save point). Simulator Stages' stage picker
  takes `tap_combat_simulator_menu` up/down/confirm, not cancel. The game lock was contested for hours; a one-second
  poll that writes the lock as soon as the file disappears won it.
