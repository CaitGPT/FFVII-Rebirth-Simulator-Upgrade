# How we built it

Simulator Stages was built in two days, 16 and 17 November 2026, by Claude, an AI model from Anthropic, working in
Claude Code. The channel owner set the design, made the calls on what it should be, and played it. Claude researched
the game's files, wrote the code, and tested every change in the running game through a test harness that can read the
game's state, press buttons and take screenshots. This is the story, dead ends included.

## The idea

The request came from an issue on our modding repository: the Combat Simulator always looks the same, a grid of blue
blocks floating in a void. Could fights happen somewhere else? The owner's first idea was to use the arenas where each
region's boss is fought. Later the owner added the two stages of the final battle, and a list of story-boss arenas.

The design the owner settled on: you choose a stage after selecting a course, from the stages that course can use;
beating a boss unlocks its arena; and every stage can be chosen wherever you open the simulator.

## Reading the game first

The game was busy with another project on the first day, so the first day was spent reading files. That turned up the
key fact: the simulator is not a map of its own. Each continent has one streaming volume that places the simulator's
level far off the map, high in the air. The fight itself, with its cameras and the points enemies move between,
belongs to that level.

That left two ways to put a fight somewhere else. One was to move the simulator onto the arena by changing where that
volume places it. The other was to leave the simulator where it is and load the arena's own levels around it. Moving
needed no extra code but would only work on the arena's own continent. Loading worked anywhere, which is what the
owner wanted, but the scripting tool we use, UE4SS, cannot make the game's level-loading call from its Lua scripts on
this game. So we wrote a small native helper in C++ that makes the call, reusing the safety checks from the helper of
our Junon Colosseum mod.

## The first time in the game

When the game was free, the helper loaded levels at a chosen position without trouble, and the simulator was exactly
where the files said. The first stage we tried was the final battle's white space. It came up black.

The reason was a pattern we kept meeting: a stage's parts arrive switched off. The game's own boss-fight scripts
switch on the sun, the fog and sometimes the ground itself when the fight reaches that stage. Loaded on its own, a
stage is dark. The mod now switches those parts on itself. The rock platform in space was worse: every one of its 41
meshes arrived hidden.

Hiding the simulator's look had its own surprise. Hiding the blocks left a black skyline of blocks behind, because the
skyline is drawn by a separate terrain system. That needed hiding too.

## The picker

The owner wanted the choice made after selecting a course, so the picker lists only stages the course can use. We used
the game's own choice window rather than drawing our own. One snag: the menu does not hold a course's displayed title
but its text id, so the mod matches courses by that id, which also works in every language.

## What did not work: the boss arenas

The regional arenas loaded without errors, and distant mountains appeared, but there was no ground under the fight.
Their ground is the game's open-world terrain, which did not draw at the new place. Their skies were a second problem:
the Nibel sky has 192 local fog volumes, and with all of them on the scene went white, with all of them off it went
black. Moving the simulator to the arena instead was also ignored, at least once the simulator had already been used.
The arena stages are switched off until we solve this.

## Too low by a metre

The owner played the two working stages and reported two faults. On the rock, Cloud could only run on the spot inside
a small patch. In the white space, characters were silhouettes.

Both had one cause: the stages sat about a metre too low. The rock's walkable top is a little over a metre above its
own zero, so the party was standing inside the rock. The white space's floor is a metre up too, so the party was
standing under it, in the dark. We measured the ground by dropping the party's collision capsule onto a grid of points
and reading where it stopped, and set each stage's height from that.

## Fitting the rock

Next the owner noticed a big patch of invisible floor on the rock. The simulator's arena is a circle of about 24 m
radius; the rock is smaller and was off to one side, so a third of the arena had nothing under it.

Our first fix centred the rock using its collision, and moved it the wrong way: the rock's collision reaches much
further than anything you can see. So we read the rock's true outline from its mesh file, three hundred thousand
vertices, and worked out the smallest stretch that puts level rock under every metre of the arena. It is 1.08 one way
and 1.70 the other. Heights are left alone, so the bumps do not grow.

## The floating rocks and the names

The owner pointed out that the real stage has floating rocks around it. They come from a "far land" level that we had
not loaded and from four rock effects that arrive hidden. Both now load at their true size and place. The far-land
mesh contains a rough copy of the platform, which poked through the real one, so it sits a metre lower.

The owner named the stages: Edge of Creation, and Inside the Lifestream, since the white space is the Lifestream.

## The Lifestream's sky

The Lifestream still lacked the starry sky the owner remembered. We had guessed its sky. The game's cutscene table
names the right one, the Galaxy sky, for the scene tied to these levels. On its own the Galaxy sky was far too dark;
loaded on top of the white sky we had used before, it matched the owner's screenshot of the real fight. One more lesson
came from it: the Lifestream's far-land level is a sheet of water above the floor, and with it loaded the party waded.
A far-land level is not always scenery.

## The "Get Ready" screen

The owner noticed the simulator sometimes stayed on "Get Ready" forever. The mod's log showed that on those visits it
had hidden the simulator's lighting levels very early. It judged the simulator ready when the game's loader was idle,
and on a second visit the simulator is cached, so the loader is idle from the start. Telling those levels to hide while
the game was still bringing them in held up the start. The mod now waits until the game has shown all of them.

## The frozen frame

Then the owner noticed that for two or three seconds the simulator's own stage showed, frozen, before ours appeared.
We timed the mod's searches for objects in the game: each one takes about a fifth of a second, whatever it looks for,
and the mod made eight of them at the moment of the swap. Now every search happens behind the loading screen and the
swap only flips things already found. On a first visit, the first picture on screen already shows the new stage.

That change brought one regression: on some later visits the Lifestream looked dull. The order mattered. If the
stage's lights came on while the simulator's lighting was still showing, the scene stayed dull after the simulator's
lighting went. The stage's lights now wait for it.

## Version 1.1.0: four more stages

The owner asked for more stages in order of how easy they would be. Gilgamesh's Garden came first and was nearly free:
the game ships it as a second look for the simulator's own level, centred in the same place.

The story arenas were harder, because an interior is more than its terrain. Each needed its props and doors (the
`Gimmick` and `Physics` levels), its floor and wall collision (grid levels picked by cell), and the right light. The
first Shinra Manor had a square pit in the middle that the boss fight does not have: a floor door that the fight
shows, which arrives hidden. Mythril Mine, Cave of the Gi and the Temple of the Ancients followed.

Then the owner played them and sent a list. The sides of the manor and the cave were dark; there were invisible walls
inside the arenas; loading was slow; the Temple's Lifestream ribbons were missing and its floor ran on past two edges;
and on arrival the screen flickered from the simulator to the stage.

- **Dark sides.** An indoor room in this game is still lit by its region's sky: its sun, fog and reflection capture.
  Loading Nibelheim's night sky with the manor and the mountain cave sky with the cave lit their walls as in the boss
  fights. Later the owner sent a screenshot of the Mythril Golem fight in which the party is lit, where ours were
  almost silhouettes. The mine was the one interior loaded without its area's main light level; reading the area's
  streaming volumes from the game's files showed which light and time-set levels the game loads there.
- **Invisible walls.** Hiding the simulator's pillars and walls left their collision. They now stop colliding, and on
  the interiors so does the simulator's flat floor, so the party stands on the room's own floor.
- **Slow loading.** The engine adds and removes a level's parts a few at a time each frame. The mod raises those limits
  while a stage loads and unloads, and unloads in the background once the player is back at the course list.
- **Flicker.** The game ends its own loading screen when its own levels are in, whatever ours are doing. Holding the
  loading screen blocked one of the manor's levels from loading; a camera fade and slowing the clock did nothing. The
  game's own menu fade, put up black on arrival and lifted when the stage is set up, works.
- **A queue limit.** The helper holds 64 unanswered requests. The Temple had 67 levels; its last three, the sky among
  them, were refused, and the sky stayed loaded after the visit, turning every later stage white. Requests now go 48
  at a time.
- **The Temple.** Its missing floor pieces are skeletal meshes that the cutscene before the fight moves into place, and
  its Lifestream ribbons are effects the story spawns. Neither is placed in a level, and loading them would need assets
  from disk that UE4SS's Lua cannot load on this game. The owner cut the stage.

## Version 1.2.0: Midgar Outskirts, and four drafts that did not make it

The owner asked for four more places, with reference screenshots: Tseng and Elena's arena in the Temple, the Altar at
the Forgotten Capital, a reactor atrium, and the spot outside Midgar where Zack fights beside the downed helicopters.
Another session had the game, so each was drafted from the game's files first: the boss's territory in its area's
battle tables, the streaming volume the game uses there, the sky its cutscenes name, and the collision cells nearby.

In the game, only Midgar Outskirts held up. Its first load had ground on one side only; the outer wall's other three
collision cells fixed that, and a probe that drops the leader on a grid found the ground level across the arena. The
helicopters are prop models that the story script places; their model is not in memory in the simulator, so they would
need the helper to load it from disk. The owner was happy without them.

The others were cut. Tseng and Elena's courtyard loaded several metres above its floor at first; lowered, it had the
same invisible-floor trouble as Reno and Rude's plaza. The Altar's level set turned out to be Jenova's tissue, not the
tiled floor of the fight. Neither reactor draft was the room the owner meant. A detour back to Reno and Rude's plaza,
which had already been cut, cost a test session; the owner caught it.

## The crashes

The game crashed every hour or two with the same fault inside UE4SS. Disassembled, the faulting code reads an object's
index: UE4SS's check of whether an object is still valid. A Lua mod kept an object, the game destroyed it and freed its
memory, and the mod asked whether it was still valid. This mod kept the simulator's levels from one visit to the next;
that was fixed first. One more crash came a second into an arrival: within a visit, the mod kept the simulator's level
streams while the game was still loading and could replace them. They are now found again by path each time.

Finding an object again by path turned out to work only for level streams; actors, widgets and volumes are not found
that way in this game. Before release the stages ran back to back on summon and regional courses: 43 stage loads
with no crash during a visit. Earlier that day the game had crashed about 9 times over 64 stage loads, not all
of them during a visit. The same kind of fault also
happens with no stage loaded, so other mods that keep objects across frames can cause it too.

The test runs had their own problems, which the owner spotted: the game froze for half a second every three seconds
during fights. That was our test driver asking the harness which simulator screen was showing; with no menu open, that
question searches every widget in the game. The driver now asks only while a menu is open.

## Tools

| Tool | Used for |
| --- | --- |
| UE4SS 3.0.1 (FF7 Rebirth build) | Lua scripts in the game, and the native helper |
| A test harness | Driving the game: menus, fights, positions, screenshots |
| retoc | Reading the game's level and mesh files |
| Python | Reading meshes, fitting the rock, building the data, tests |
| Lua tests with a stand-in for the game | Checking the mod's decisions offline |

## What we know does not work yet

- The regional and open-world boss arenas: their ground does not draw when loaded elsewhere.
- The Temple of the Ancients: its floor pieces and sky effects are placed by the story, not by its levels.
- The rock reaches past the arena's wall by up to 6 m in places and sits slightly low along part of one edge.
- The Mythril Mine is still a little darker than the boss fight.
- Tested on the Epic Games Store version only.

## Credits

UE4SS and its FF7 Rebirth build, retoc and its FF7R patches, FModel and CUE4Parse, and the Rebirth modding community.
