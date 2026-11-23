-- ct_session against a fake game: a visit starts, the first opponent is replaced by the chosen one, the menu changes
-- the count, and the difficulty is put back at the end.
local session_module = require("ct_session")
local T = "terT"
local catalogue = { territory = T, base = { { id = "mobcolvr_A", level = 20 }, { id = "mobcolvr_C", level = 5 } },
  opponents = {
    { id = "mobcolvr_A", spec = "EN0001_00_Rat", label = "$en_Rat", category = 3, level = 20, slot = 0, home = {} },
    { id = "mobcolvr_B", spec = "EN0002_00_Orc", label = "$en_Orc", category = 3, level = 30, slot = 1,
      home = { { 0, "mobcolvr_Crown", 30 } } },
} }
local world = { enemies = {}, n = 0, paused = false, windows = {}, spawned = {}, removed = {} }
local function add(spec) world.n = world.n + 1; local a = { name = "E" .. world.n, spec = spec, hp = 100, max = 100 }; world.enemies[#world.enemies + 1] = a; return a end
local spec_of = { mobcolvr_A = "EN0001_00_Rat", mobcolvr_B = "EN0002_00_Orc", mobcolvr_C = "EN0003_00_Cat",
                  mobcolvr_Crown = "WE0000_Crown" }
local index_of, name_of_index = {}, {}
for i, n in ipairs({ "mobcolvr_A", "mobcolvr_B", "mobcolvr_C", "mobcolvr_Crown" }) do index_of[n] = i * 100; name_of_index[i * 100] = n end
world.slots = { [0] = "mobcolvr_A", [1] = "mobcolvr_C" }
local finds = 0
_G.CustomTrainingFindWaves = function(names, levels)
    finds = finds + 1
    if finds == 1 then return "searching" end
    assert(#names == 2 * 16 and #levels == 2 * 8, "hex lengths: " .. #names .. " " .. #levels) -- 2 base entries here
    return "found"
end
_G.CustomTrainingSetWave = function(slot, index, number, level) world.slots[slot] = name_of_index[index]; return true end
local game = {
    enemies = function() return world.enemies end,
    territory_of = function() return T end,
    name_of = function(a) return a.name end,
    spec = function(a) return a.spec end,
    hp = function(a) return a.hp, a.max end,
    refill = function(a) a.hp = a.max end,
    hold = function(a, passive) a.held = passive end,
    stash = function(a, spot) a.stashed = true; return spot or {} end,
    untarget = function(a) a.untargetable = true; return true end,
    in_battle = function() return #world.enemies > 0 end,
    spawn_wave = function(t, w) world.spawned[#world.spawned + 1] = w; add(spec_of[world.slots[w]]); return { "x" } end,
    remove = function(t, a)
        for i, e in ipairs(world.enemies) do if e == a then table.remove(world.enemies, i); world.removed[#world.removed + 1] = a.name; return true end end
        return false
    end,
    lookup = function(key) return key == "$en_Orc" and "Orc" or nil end,
    fname_index = function(name) return index_of[name] end,
    keys_down = function(names) return world.keys or {} end,
    party = function() return world.party or {} end,
    set_hp_percent = function(actor, percent) actor.hp = math.floor(actor.max * percent / 100) end,
    refill_mp = function(kind) world.mp_refilled = (world.mp_refilled or 0) + 1; return 5 end,
    show_panel = function(view) world.view = view; return true end,
    hide_panel = function() world.view = nil end,
    pause = function(on) world.paused = on end,
}
local saved_difficulty = { 0, 1 }
_G.CustomTrainingGetDifficulty = function() return saved_difficulty[1], saved_difficulty[1], saved_difficulty[2], 0 end
_G.CustomTrainingSetDifficulty = function(v, s) saved_difficulty = { v, s }; return true end
local clock = 0
local settings = { opponent = "mobcolvr_B", count = 2, behaviour = "passive", difficulty = "hard" }
local s = session_module.new({ game = game, catalogue = catalogue, settings = settings, save_settings = function() end,
    log = function() end, clock = function() return clock end })

assert(s:tick() == false, "nothing before the course")
add("EN0001_00_Rat")                       -- the course's opening enemy
assert(s:tick() == true, "visit begins")
assert(saved_difficulty[1] == 2, "difficulty set to hard")
assert(#world.spawned == 0, "nothing before the slots are found")
clock = clock + 1.1; s:tick()
assert(#world.spawned == 2 and world.spawned[1] == 1, "two Orcs asked for, from the Orc's slot")
assert(world.slots[0] == "mobcolvr_Crown", "the Orc's own add written into its wave")
clock = clock + 2; s:tick()
assert(#world.removed == 0 and world.enemies[1].stashed and world.enemies[1].held, "the opening Rat is the held anchor")
assert(world.enemies[1].untargetable and not world.enemies[2].untargetable, "the anchor alone is out of targeting")
assert(#world.enemies == 3 and world.enemies[2].held == true, "two held Orcs")
-- Passive (owner 2026-11-21: as before): damage is refilled
world.enemies[2].hp = 50; clock = clock + 0.2; s:tick()
assert(world.enemies[2].hp == 100, "Passive refills")
-- Aggressive (real conditions): no refill, a defeated Orc stays down while the other stands
settings.behaviour = "aggressive"
world.enemies[2].hp = 50; clock = clock + 0.2; s:tick()
assert(world.enemies[2].hp == 50, "Aggressive: no refill")
assert(s.wave == 1, "the first wave")
table.remove(world.enemies, 3); clock = clock + 0.2; s:tick()
assert(#world.enemies == 2, "one Orc down, not back")
-- the last one dead (HP 0, still there for its death motion): a clear; the round waits for Respawn (owner
-- 2026-11-21: no automatic respawn), then the whole set comes back as wave 2
world.enemies[2].hp = 0; clock = clock + 0.2; s:tick(); clock = clock + 0.2; s:tick()
assert(#world.enemies == 2 and s.wave == 1 and s.last_clear and s.last_clear > 0, "cleared, waiting: " .. #world.enemies)
assert(s:respawn(clock)); clock = clock + 0.2; s:tick()
assert(#world.enemies == 4 and s.wave == 2, "Respawn: a new wave of two: " .. #world.enemies)
table.remove(world.enemies, 2) -- the dead one's body goes
settings.behaviour = "passive"; clock = clock + 0.2; s:tick()
-- the panel: F7, down to Quantity, right (2 -> 3), Select
s:request_menu(); clock = clock + 0.2; s:tick()
assert(world.view and world.paused and world.view.sections[1].cells[2].text == "Orc", "panel open on the Orc, paused")
s:inject_key("down"); s:inject_key("down"); s:inject_key("down"); clock = clock + 0.05; s:tick()
assert(world.view.sections[4].focused, "quantity focused")
s:inject_key("right"); clock = clock + 0.05; s:tick()
assert(world.view.sections[4].cells[1].text == "3", "three in the draft")
assert(settings.count == 2, "nothing applied before Select")
s:inject_key("select"); clock = clock + 0.05; s:tick()
assert(settings.count == 3 and not world.paused and world.view == nil, "applied, closed, unpaused")
-- the shoulder chord opens it in a fight; Back closes without changes
world.keys = { Gamepad_LeftShoulder = true, Gamepad_RightShoulder = true }; clock = clock + 0.2; s:tick()
assert(s:panel_open(), "chord opens")
world.keys = {}; s:inject_key("down"); s:inject_key("right"); s:inject_key("back"); clock = clock + 0.05; s:tick()
assert(not s:panel_open() and settings.behaviour == "passive", "back closes without changes")
clock = clock + 0.2; s:tick()
assert(#world.enemies == 4, "third Orc")
-- aggressive releases the hold
settings.behaviour = "aggressive"; clock = clock + 0.2; s:tick()
assert(world.enemies[2].held == false and world.enemies[1].held == true, "aggressive; the anchor stays held")
-- the visit ends: difficulty put back
world.enemies = {}; clock = clock + 0.2; s:tick(); clock = clock + 5; s:tick()
assert(s.active == false, "visit over " .. tostring(s.active))
assert(world.slots[0] == "mobcolvr_A" and world.slots[1] == "mobcolvr_C", "base waves put back")
assert(saved_difficulty[1] == 0 and saved_difficulty[2] == 1, "difficulty restored " .. tostring(saved_difficulty[1]) .. "/" .. tostring(saved_difficulty[2]))


-- Healing: the party is held at 1%; any opponent as set, a capped one at its cap
world.enemies = {}; add("EN0001_00_Rat")
local cloud = { hp = 1000, max = 1000 }
world.party = { { id = "Cloud", actor = cloud, kind = 0, hp = 1000, max = 1000 } }
local s3 = session_module.new({ game = game, catalogue = catalogue, settings = { opponent = "mobcolvr_A", count = 3,
    behaviour = "healing", difficulty = "normal" }, save_settings = function() end, log = function() end,
    clock = function() return clock end })
clock = clock + 0.2; s3:tick()
assert(cloud.hp == 10 and (world.mp_refilled or 0) > 0, "patient at 1%, MP refilled")
catalogue.opponents[1].boss = true
assert(s3:count() == 3, "a former boss as set")
catalogue.opponents[1].boss, catalogue.opponents[1].cap = nil, 1
assert(s3:count() == 1, "a capped one at its cap")
catalogue.opponents[1].cap = nil

-- ct_api: what ui and meters use
local api = require("ct_api")
local events = {}
api.on_course(function(e) events[#events + 1] = e.what .. ":" .. tostring(e.behaviour) end)
world.enemies = {}; add("EN0001_00_Rat")
local s4 = session_module.new({ game = game, catalogue = catalogue, settings = { opponent = "mobcolvr_A", count = 2,
    behaviour = "passive", difficulty = "normal" }, save_settings = function() end, log = function() end,
    clock = function() return clock end, emit = api.emit })
api.bind(s4)
assert(not api.active(), "not active before the course")
clock = clock + 0.2; s4:tick()
assert(api.active() and events[#events] == "start:passive", "start event")
local l = api.lists()
assert(#l.opponents == 2 and #l.behaviours == 3 and l.behaviours[3].id == "healing" and l.max_count == 3, "lists")
local ok, why = api.apply({ behaviour = "flying" })
assert(not ok and why:find("behaviour", 1, true), "bad value refused")
assert(api.apply({ behaviour = "aggressive", count = 1 }), "apply")
assert(api.state().behaviour == "aggressive" and api.state().count == 1 and events[#events] == "change:aggressive", "change event")
assert(api.format(api.state()):find("behaviour=aggressive", 1, true), "status file text")
assert(api.state().boss == nil and api.state().max_count == 3 and api.lists().opponents[1].boss == nil
    and api.lists().opponents[1].max_count == 3, "no boss flag; max_count instead")
-- From a capped opponent (reported at its cap) to another without a count: the one shown stays, not the stored count
s4.settings.count = 2; catalogue.opponents[1].cap = 1
assert(api.state().count == 1 and api.state().max_count == 1, "a capped one reports one")
local okc, whyc = api.apply({ count = 2 })
assert(not okc and whyc:find("1 to 1", 1, true), "above the cap refused")
assert(api.apply({ opponent = "mobcolvr_B" }), "apply opponent only")
assert(s4.settings.count == 1 and api.state().count == 1, "count kept at the one shown: " .. tostring(s4.settings.count))
catalogue.opponents[1].cap = nil
assert(api.apply({ opponent = "mobcolvr_A", count = 3 }) and s4.settings.count == 3, "an explicit count still applies")
assert(api.apply({ opponent = "mobcolvr_B" }) and s4.settings.count == 3, "no cap: the count stays as it was")
world.enemies = {}; clock = clock + 0.2; s4:tick(); clock = clock + 5; s4:tick()
assert(not api.active() and events[#events] == "end:aggressive", "end event")

-- MP given back, for meters; the lists file for ui; the meters' panel sections; the panel blocked
world.enemies = {}; add("EN0001_00_Rat")
world.party = { { id = "Cloud", actor = { hp = 1000, max = 1000 }, kind = 0, hp = 1000, max = 1000 } }
local sent, blocked = {}, false
local meters = { state = function() return { meter = "taken", visible = true } end,
                 act = function(c) sent[#sent + 1] = c end }
local s5 = session_module.new({ game = game, catalogue = catalogue, settings = { opponent = "mobcolvr_A", count = 1,
    behaviour = "passive", difficulty = "normal" }, save_settings = function() end, log = function() end,
    clock = function() return clock end, emit = api.emit, meters = meters, panel_blocked = function() return blocked end })
api.bind(s5)
s5:request_menu()
assert(not s5.menu_requested, "F7 outside a course is ignored")
clock = clock + 0.2; s5:tick(); clock = clock + 0.2; s5:tick()
assert(api.mp_refilled().Cloud == 10, "MP given back counted: " .. tostring(api.mp_refilled().Cloud))
assert(api.mp_text() == "mp.Cloud=10\n", "mp file text")
api.apply({ count = 2 })
assert(api.mp_refilled().Cloud == nil, "a change starts the count again")
local text = api.lists_text()
assert(text:find("opponent\tmobcolvr_A\t3\tBeasts\t3\t", 1, true) and text:find("behaviour\thealing\tHealing", 1, true)
    and text:find("max_count\t3\n", 1, true), "lists file text")
blocked = true
s5:request_menu(); clock = clock + 0.2; s5:tick()
assert(not s5:panel_open(), "blocked panel stays shut")
blocked = false
s5:request_menu(); clock = clock + 0.2; s5:tick()
assert(s5:panel_open() and #world.view.sections == 6 and world.view.sections[5].cells[2].selected, "meters sections, on its meter")
s5:inject_key("up"); s5:inject_key("left"); s5:inject_key("select") -- the tools row (last), back to Reset stagger
clock = clock + 0.2; s5:tick()
assert(sent[1] == "stagger" and #sent == 1, "a tool sent: " .. table.concat(sent, ","))

-- A new opponent starts with a clean party: statuses off, HP and MP back (owner 2026-11-21)
world.enemies = {}; add("EN0001_00_Rat")
local poisoned = { hp = 400, max = 1000, statuses = { BSC_Poison = true } }
world.party = { { id = "Cloud", actor = poisoned, kind = 0, hp = 400, max = 1000 } }
local cleaned, mp_full = 0, 0
game.clear_bad_status = function(actor, ids)
    local out = {}
    if ids then -- only these (the lethal ones, checked twice a second)
        for _, id in ipairs(ids) do
            if actor.statuses and actor.statuses[id] then actor.statuses[id] = nil; out[#out + 1] = id end
        end
        return out
    end
    for k in pairs(actor.statuses or {}) do out[#out + 1] = k end
    actor.statuses = {}
    cleaned = cleaned + 1
    return out
end
game.LETHAL_STATUSES = { "BSC_DeathSentence", "BSC_Petrifaction" }
game.full_mp = function(kind) mp_full = mp_full + 1 end
local s6 = session_module.new({ game = game, catalogue = catalogue, settings = { opponent = "mobcolvr_A", count = 1,
    behaviour = "passive", difficulty = "normal" }, save_settings = function() end, log = function() end,
    clock = function() return clock end })
clock = clock + 0.2; s6:tick()
assert(cleaned == 1 and poisoned.hp == 1000 and mp_full == 1, "clean at the start (Passive): statuses off, HP and MP full")
poisoned.statuses = { BSC_Poison = true }; poisoned.hp = 300; world.party[1].hp = 300
s6:apply({ opponent = "mobcolvr_B" }, clock)
clock = clock + 0.2; s6:tick()
assert(cleaned == 2 and next(poisoned.statuses) == nil and poisoned.hp == 1000, "clean when the opponent changes (Passive)")
clock = clock + 2.5; s6:tick()
assert(cleaned == 3, "and once more 2 s later")
clock = clock + 5; s6:tick()
assert(cleaned == 3, "then not again")
-- Condemned comes off as it lands (it knocks out at any HP); poison stays until the next change
poisoned.statuses = { BSC_DeathSentence = true, BSC_Poison = true }
clock = clock + 0.6; s6:tick()
assert(not poisoned.statuses.BSC_DeathSentence and poisoned.statuses.BSC_Poison and cleaned == 3, "lethal status lifted, poison kept")
-- Auto-Life kept on: given when missing, not again while it is there
local given = 0
game.keep_reraise = function(actor) if actor.reraise then return false end; actor.reraise = true; given = given + 1; return true end
clock = clock + 0.6; s6:tick(); clock = clock + 0.6; s6:tick()
assert(poisoned.reraise and given == 1, "Auto-Life given once")
poisoned.reraise = nil -- used up by a knockout
clock = clock + 0.6; s6:tick()
assert(poisoned.reraise and given == 2, "and given again")
game.keep_reraise = nil
game.clear_bad_status, game.full_mp, game.LETHAL_STATUSES = nil, nil, nil

-- Aggressive (owner 2026-11-21: real conditions): the clean-up takes statuses off but gives back neither HP nor MP,
-- MP is not refilled as spent, nobody's HP is refilled; Auto-Life stays.
do
    local hurt = { hp = 300, max = 1000, statuses = { BSC_Poison = true } }
    world.party = { { id = "Cloud", actor = hurt, kind = 0, hp = 300, max = 1000 } }
    world.enemies = {}; add("EN0001_00_Rat")
    local cleans, fulls, refills = 0, 0, 0
    game.clear_bad_status = function(actor, ids) if not ids then cleans = cleans + 1; actor.statuses = {} end; return {} end
    game.full_mp = function() fulls = fulls + 1 end
    local old_refill_mp = game.refill_mp
    game.refill_mp = function() refills = refills + 1; return 5 end
    local s7 = session_module.new({ game = game, catalogue = catalogue, settings = { opponent = "mobcolvr_A", count = 1,
        behaviour = "aggressive", difficulty = "normal" }, save_settings = function() end, log = function() end,
        clock = function() return clock end })
    for _ = 1, 4 do clock = clock + 0.6; s7:tick() end
    assert(cleans >= 1 and next(hurt.statuses) == nil, "Aggressive: statuses off")
    assert(hurt.hp == 300 and fulls == 0 and refills == 0, "Aggressive: no HP or MP back")
    game.clear_bad_status, game.full_mp, game.refill_mp = nil, nil, old_refill_mp
end
