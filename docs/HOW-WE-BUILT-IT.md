# How we built Simulator Upgrade

Simulator Upgrade was built by Claude, an AI model from Anthropic, working in Claude Code. The channel owner set the
design and changed it as the work showed what was possible. Every feature was tested in the running game through our
test harness, which presses keys and pad buttons, reads the game's state and takes screenshots. This is the story,
dead ends included.

## Why

The owner wanted Chadley's Combat Simulator to be a real practice room: change equipment without leaving it, fight any
opponent the way you want, see the numbers, and do it on the stages from our Simulator Stages mod. It started as one
small request, to open the simulator from the machine beside Chadley instead of talking to him. It grew from there.

## How the work was split

Several Claude sessions worked at once, one per part: equipment, Custom Training, the settings menu, the meters, and
the stages. A coordinating session merged their work, built the combined mod and kept the rules that let the parts
share one mod: one folder, one settings file with a prefix per part, no two parts on the same key, and no game calls in
the first seconds after the game starts.

There is only one game. The sessions took turns on it through a lock file and a queue: a session wrote its name and
what it was doing, refreshed the lock every ten minutes and handed the game on when it finished. Most of the waiting
was spent on work that needs no game: offline tests, reading the game's tables and planning the next run.

## Equipment inside the simulator

The simple version came first: a key that opens the game's own main menu over the simulator's screens, where Materia
and Equipment, Combat Settings and Party already live. F3 on the keyboard and Start on a pad open it on the course
list, the stage picker, the team screen and the "Begin challenge?" prompt. Once a course has started it does nothing.

Showing the key was harder than using it. A text built at runtime was added to the screen and reported a size, but
drew nothing. What worked was copying one of the game's own key-guide texts and adding the copy beside it. The copy
draws exactly like the game's entries and switches its button picture when the player picks up a pad.

Changing equipment in the middle of a fight was tried and dropped for this version: the game's menu opens, but the
fighters are left in a T-pose. That research continues for a later release.

## Custom Training

Custom Training is a course row added to the simulator's tables, cloned from the first Grasslands course. Its round
starts with one enemy and carries sixteen reinforcement waves. The trick is in those waves.

A small native helper finds the course's wave list in the game's memory, by the exact pattern of the sixteen waves we
put there. The Lua then writes the chosen opponent and its level into a free wave slot and starts that wave. Replacing
an opponent means spawning the new one first, then removing the old, so the round never runs out of enemies. A hidden
extra enemy, the anchor, keeps the round alive between fights.

What didn't work:

- One territory with a wave per opponent crashed the game: rounds above fifteen waves aren't safe.
- The first number in the call that starts a wave turned out to be the count, not the wave. The first test spawned
  seventy-six Zu.
- Moving the anchor the moment it appeared failed, because its own set-up put it back. From two seconds in, it stays.
- A textbook string search for the wave pattern took minutes in zero-filled memory. A scan for the first value, on
  aligned addresses, takes seconds.

Every opponent was tried. In the first pass, 240 of 245 candidates appeared. Later the list was cleaned up, to 207
opponents with the game's own names. In Aggressive, 206 of the 207 were seen attacking. The one that never did, a
standard Gi Specter, was dropped: no simulator course fights it, so there was nothing to compare with.

The rules changed as the owner tried them:

- Bosses were first limited to one copy. When story bosses were ruled out, the limit went. All 42 former bosses were
  tested with three copies, and none had to be limited.
- Enemies first had their health refilled so a round could never end. The owner wanted to know whether a group can
  actually be beaten, so in Aggressive enemies now die and stay dead, and Respawn (F4, or the menu's first row) brings
  the same fight back.
- The party's refills went the same way. Aggressive is real conditions: no health or MP back, only Auto-Life, so a
  knockout doesn't end the practice. Passive keeps refilling everything, for trying things out.
- Mixed groups of up to three different opponents came next, then pre-built rounds from any simulator course: 227
  rounds from 63 courses.

The game's fights then taught us the rest:

- Enemies appeared a couple of metres in the air. Each spawned enemy is now placed on the floor, found by tracing down
  from the party's own floor height, and copies are spaced by their real size plus two metres.
- On a stage, the trace once hit a prop eight metres up and three Alexanders stood on it.
- A boss's one-hit attack could knock out a solo Cloud and end the round. That is why Auto-Life is kept on the party.
- Replaced enemies went on attacking for up to nine seconds while the game removed them. They are now frozen, made
  untargetable and moved out of the fight at once, and gone in under a second.
- One summon's fight script moved Cloud to the world's origin, two kilometres from the arena. The party is now put
  back if it ends up far away.
- Some opponents need more room than the smaller stages have. Instead of hiding stages, the menu marks opponents and
  rounds that need a larger stage.
- While we recorded the demo, one blow killed a Passive Zu faster than its refill, and the round stood empty, waiting
  for Respawn. In Passive and Healing a killed set now comes back by itself.

## The settings menu

The owner wanted the settings in the game's own interface. The menu is the game's own choice window, the one it uses
for its own questions, so it looks and behaves like part of the game. The game moves its cursor and confirms with
keyboard or pad, drawing the right button pictures. The mod only decides what each window shows and what a choice
does.

The window takes the input focus, so the mod can't read left and right while it is open. Every setting therefore
opens a short list of values. Long opponent lists are split by kind, then by ranges of names, so any opponent is at
most three windows away. Placing the window's cursor never worked, and a "More" page for long lists needed sixteen
pages for beasts, so both were dropped. Escape inside the window also reached the fight behind it and opened the
pause menu. The mod now closes that pause menu in the moment between two windows.

## The meters

The meters merge what our Training Dummy and Battle Meters mods each measured: damage, damage taken and healing per
second, with a row per character, the last five seconds, totals, biggest hits, and in Aggressive the wave number and
the last clear time. Who dealt each hit comes from the game's own hit events, through the same native helper.

The bugs worth telling:

- Removing an opponent counted its remaining health as damage dealt.
- A behaviour change lost the last blow of a kill.
- Comparing Custom Training's group, a fresh table each time, cleared the numbers every tick.

Each was found in the game and fixed. Battle Meters 1.2.0 now steps aside during Custom Training, so only one panel
shows.

## Zack and Sephiroth

Adding Zack and Sephiroth to the team screen took one value on the course row. The game's four courses that use them
already set it, beside a fixed team list that hides the effect. With an empty team list, the same value offers all
nine characters.

## Keeping it stable

About twenty minutes into one test, every part of the mod stopped at once. The cause was in UE4SS itself. It keeps one
shared table of every Lua thread, with no lock, and grows it in place while other threads read it. Each time a mod
hands work to the game thread, a row is added. The fix in the mod was to send all six parts' game-thread work through
one scheduler and a native pump, so the mod adds almost no rows. It passed a soak of 285 menu opens, 25 Custom
Training spawns, 25 stage visits and 25 fast travels.

Other mods still grow that table, so the proper fix went into UE4SS itself, through our UE4SS 1.005 Fix: version 1.1.0
gives the table room for the whole session at start-up. A related race in UE4SS's hook callback lists, which fits a
start-up crash reported on Proton, became version 1.1.1.

Just before release, three Steam players reported that the standalone Simulator Stages never loaded a stage. We
reproduced it on a Steam copy. The stage helper only acted during a Blueprint actor's per-frame event, and the
unmodified game has none. Our Epic test setup had one from a community mod loader we had installed in July, so every
one of our tests passed. The helper now also acts during the camera's per-frame update, and this mod shipped with the
fix (Simulator Stages 1.3.1). The lesson: test a release once on a setup with nothing else installed.

## What we changed our minds about

- The mod was called Simulator Overhaul until the owner renamed it Simulator Upgrade.
- The machine beside Chadley first opened the simulator, swapping places with Chadley so it was the nearer of the two.
  Once equipment could be changed inside the simulator, there was less reason to leave it. The owner moved the machine
  to a separate mod, Boss Rematch and Story Replay, where it opens a different menu.
- Story bosses were researched for Custom Training. Most need their own arena and fight script, so they were left out
  of this mod and became that separate mod's job.

## Tools

| Tool | What it did |
| --- | --- |
| UE4SS 3.0.1 | Runs the Lua parts and the native helpers |
| Our test harness | Drove the game: keys, pad buttons, menus, fights, screenshots, saves and loads |
| Our table builder | Added Custom Training's course row to the game's tables |
| FModel and CUE4Parse, retoc | Read the game's files |
| Lua tests with lupa | Ran each part's logic offline, against a stand-in game |

## Testing in numbers

- 206 opponents seen attacking in Aggressive, one at a time.
- 42 former bosses with three copies each.
- 27 bosses and summons watched through their phases and adds, with a mid-fight change after each.
- Mixed groups and rounds from several kinds of course.
- Every menu walked with the keyboard and with a pad.
- A final check of the release build, installed alongside our other mods.

## Known limits

- No equipment changes in the middle of a fight.
- Story bosses aren't in Custom Training.
- Other installed mods can still trigger the UE4SS races unless our UE4SS 1.005 Fix is installed.
- A game update can change the code the native helpers rely on. They then switch themselves off until we update the
  mod.

## Credits

- UE4SS and the FF7 Rebirth build of it.
- retoc and its FF7R patches, FModel and CUE4Parse, for reading the game's files.
- Our Training Dummy, Battle Meters, Simulator Stages and Junon Colosseum mods, whose code and findings this one
  builds on.
- The Rebirth modding community.
