-- Mixed groups and pre-built rounds (owner 2026-11-21) against a fake game: each member from its own wave, adds in
-- their own waves, a member that falls comes back alone, a round's set comes back whole, and ct_api's fields.
local session_module = require("ct_session")
local api = require("ct_api")
local T = "terG"
local catalogue = { territory = T, base = { { id = "mobcolvr_Rat", level = 20 } }, opponents = {
    { id = "mobcolvr_Rat", spec = "EN0001_00_Rat", label = "$en_Rat", name = "Rat", category = 3, level = 20, slot = 0, home = {} },
    { id = "mobcolvr_Bomb", spec = "EN0002_00_Bomb", label = "$en_Bomb", name = "Bomb", category = 3, level = 25, slot = 0, home = {} },
    { id = "mobcolvr_King", spec = "EN0003_00_King", label = "$en_King", name = "King", category = 3, level = 50, slot = 4,
      home = { { 0, "mobcolvr_Crown", 50 }, { 1, "mobcolvr_Minion", 50 } } },
    { id = "mobcolvr_Hen", spec = "EN0004_00_Hen", label = "$en_Hen", name = "Hen", category = 3, level = 30, slot = 1,
      home = { { 0, "mobcolvr_Egg", 30 } } },
    { id = "mobcolvr_BanditA", spec = "EN0008_00_Bandit_A", label = "$en_Bandit", name = "Bandit", tag = "Axe", category = 1, level = 22, slot = 0, home = {} },
    { id = "mobcolvr_BanditB", spec = "EN0008_00_Bandit_B", label = "$en_Bandit", name = "Bandit", tag = "Bat", category = 1, level = 22, slot = 0, home = {} },
    { id = "mobcolvr_Solo", spec = "EN0009_00_Solo", label = "$en_Solo", name = "Solo", category = 3, level = 40, slot = 0, home = {}, cap = 1 },
    { id = "mobcolvr_Ghost", spec = "EN0010_00_Ghost", label = "$en_Ghost", name = "Ghost", category = 3, level = 40, slot = 0, home = {} },
}, courses = {
    { id = "COL_A", label = "$course_A", name = "Course A", tab = 2, rounds = {
        { id = "terA_010", number = 1, mobs = { { "mobcolvr_Rat_Ver1", 2, 19, "EN0001_00_Rat", "mobcolvr_Rat" },
                                                { "mobcolvr_Bomb", 1, 21, "EN0002_00_Bomb", "mobcolvr_Bomb" } },
          waves = { { 0, "mobcolvr_Spark", 21 } } },
        { id = "terA_020", number = 2, mobs = { { "mobcolvr_Ghost", 1, 30, "EN0010_00_Ghost", "mobcolvr_Ghost" } }, waves = {} },
    } },
} }
local spec_of = { mobcolvr_Rat = "EN0001_00_Rat", mobcolvr_Rat_Ver1 = "EN0001_00_Rat", mobcolvr_Bomb = "EN0002_00_Bomb",
    mobcolvr_King = "EN0003_00_King", mobcolvr_Hen = "EN0004_00_Hen", mobcolvr_BanditA = "EN0008_00_Bandit_A",
    mobcolvr_BanditB = "EN0008_00_Bandit_B", mobcolvr_Solo = "EN0009_00_Solo", mobcolvr_Crown = "WE0000_Crown",
    mobcolvr_Minion = "EN0003_01_Minion", mobcolvr_Egg = "EN0004_01_Egg", mobcolvr_Spark = "EN0002_01_Spark" }
local names, index_of = {}, {}
for n in pairs(spec_of) do names[#names + 1] = n end
names[#names + 1] = "mobcolvr_Ghost" -- never appears (spec_of has none)
table.sort(names)
for i, n in ipairs(names) do index_of[n] = i end
local world = { enemies = {}, n = 0, slots = {}, spawned = {}, removed = {} }
local function add(spec)
    world.n = world.n + 1
    local a = { name = "E" .. world.n, spec = spec, hp = 100, max = 100 }
    world.enemies[#world.enemies + 1] = a
    return a
end
local function count_of(spec)
    local n = 0
    for _, e in ipairs(world.enemies) do if e.spec == spec then n = n + 1 end end
    return n
end
local function kill(spec)
    for i, e in ipairs(world.enemies) do if e.spec == spec then table.remove(world.enemies, i); return end end
end
_G.CustomTrainingFindWaves = function() return "found" end
_G.CustomTrainingSetWave = function(slot, index, number, level) world.slots[slot] = names[index]; return true end
_G.CustomTrainingGetDifficulty, _G.CustomTrainingSetDifficulty = nil, nil
local game = {
    enemies = function() return world.enemies end,
    territory_of = function() return T end,
    name_of = function(a) return a.name end,
    spec = function(a) return a.spec end,
    hp = function(a) return a.hp, a.max end,
    refill = function(a) a.hp = a.max end,
    hold = function() end,
    stash = function(a, spot) return spot or {} end,
    untarget = function() return true end,
    in_battle = function() return true end,
    spawn_wave = function(t, w)
        world.spawned[#world.spawned + 1] = { wave = w, template = world.slots[w] }
        local spec = spec_of[world.slots[w]]
        if spec then add(spec) end
        return { "x" }
    end,
    remove = function(t, a)
        for i, e in ipairs(world.enemies) do
            if e == a then table.remove(world.enemies, i); world.removed[#world.removed + 1] = a.spec; return true end
        end
        return false
    end,
    lookup = function(key) return nil end,
    fname_index = function(name) return index_of[name] end,
    keys_down = function() return {} end,
    party = function() return {} end,
    set_hp_percent = function() end,
    refill_mp = function() return 0 end,
    show_panel = function() return true end,
    hide_panel = function() end,
    pause = function() end,
}
local clock = 0
local settings = { opponent = "mobcolvr_Rat", count = 1, group = "mobcolvr_Rat,mobcolvr_King,mobcolvr_King",
                   mode = "opponents", round = "", behaviour = "aggressive", difficulty = "normal" }
local s = session_module.new({ game = game, catalogue = catalogue, settings = settings, save_settings = function() end,
    log = function() end, clock = function() return clock end, emit = function(...) return api.emit(...) end })
api.bind(s)
local function tick(dt) clock = clock + (dt or 0.25); return s:tick() end

-- A Rat and two Kings: the King's adds (crown, minion) in their own waves 0 and 1, each member from a wave of its own.
add("EN0001_00_Rat") -- the course's opening enemy: the anchor
tick(0)
tick()
assert(count_of("EN0003_00_King") == 2 and count_of("EN0001_00_Rat") == 2, "two Kings and a Rat (and the anchor Rat)")
assert(world.slots[0] == "mobcolvr_Crown" and world.slots[1] == "mobcolvr_Minion", "the King's adds in waves 0 and 1")
local waves = {}
for _, sp in ipairs(world.spawned) do waves[sp.template] = sp.wave end
assert(waves.mobcolvr_Rat == 2 and waves.mobcolvr_King == 3, "Rat from wave 2, King from 3: " .. tostring(waves.mobcolvr_Rat) .. " " .. tostring(waves.mobcolvr_King))
assert(s:count() == 3, "count is the group's size")
local st = api.state()
assert(st.mode == "opponents" and #st.group == 3 and st.group[1] == "mobcolvr_Rat" and st.group[3] == "mobcolvr_King", "state().group")
assert(st.group_names[2] == "King" and st.opponent == "mobcolvr_Rat" and st.count == 3, "names and the old fields")
assert(st.setup == "Rat, King ×2", "setup words: " .. tostring(st.setup))

-- Waves: a King that falls stays down while the rest stand; an add lives on; once the last of the group falls, the
-- whole group comes back and the old wave's add goes.
tick() -- the wave seen (its spawn requests settled)
add("EN0003_01_Minion")
kill("EN0003_00_King"); tick()
assert(count_of("EN0003_00_King") == 1 and count_of("EN0003_01_Minion") == 1, "one King down, not back; the minion kept")
local events = {}
api.on_course(function(ev) if ev.what == "clear" or ev.what == "wave" then events[#events + 1] = ev end end)
local notices = {}
game.notice = function(text) notices[#notices + 1] = text; return true end
kill("EN0003_00_King")
for i, e in ipairs(world.enemies) do if e.spec == "EN0001_00_Rat" and e.name ~= s.anchor_key then table.remove(world.enemies, i); break end end
tick(); tick()
assert(count_of("EN0003_00_King") == 0 and #events == 1 and events[1].what == "clear" and events[1].cleared_wave == 1
    and events[1].clear_time > 0, "cleared: the round waits, a clear event")
assert(#notices == 1 and notices[1]:match("^Wave cleared in %d+:%d%d%. F4 or Respawn in the menu %(LB%+RB%) for the same fight%.$"), "notice: " .. tostring(notices[1]))
tick(); tick()
assert(count_of("EN0003_00_King") == 0 and #notices == 1, "still waiting, said once")
assert(api.respawn())
tick(); tick()
assert(count_of("EN0003_00_King") == 2 and count_of("EN0003_01_Minion") == 0 and api.state().wave == 2, "Respawn: two Kings, the old minion gone")
assert(#events == 2 and events[2].what == "wave", "a wave event for the new set")
-- Respawn mid-fight: a fresh set replaces what is there.
local before = {}
for _, e in ipairs(world.enemies) do if e.spec == "EN0003_00_King" then before[e.name] = true end end
assert(api.respawn()); tick(); tick()
local fresh = 0
for _, e in ipairs(world.enemies) do if e.spec == "EN0003_00_King" and not before[e.name] then fresh = fresh + 1 end end
assert(count_of("EN0003_00_King") == 2 and fresh == 2 and api.state().wave == 3, "mid-fight Respawn: two fresh Kings")
game.notice = nil

-- A capped opponent counts once; adds that need the same wave for different enemies don't mix; at most 3.
local ok, why = api.apply({ group = "mobcolvr_Solo,mobcolvr_Solo" })
assert(not ok and why:match("at most 1"), "a capped one counts once: " .. tostring(why))
ok, why = api.apply({ group = { "mobcolvr_King", "mobcolvr_Hen" } })
assert(not ok and why:match("wave 0"), "King and Hen both need wave 0: " .. tostring(why))
ok, why = api.apply({ group = "mobcolvr_Rat,mobcolvr_Rat,mobcolvr_Rat,mobcolvr_Rat" })
assert(not ok, "four is too many")
ok = api.apply({ group = "mobcolvr_Hen,mobcolvr_Bomb" })
assert(ok, "Hen and Bomb mix")

-- The change: the new ones come first, the old are removed (the anchor keeps the round); never empty.
tick()
assert(count_of("EN0004_00_Hen") == 1 and count_of("EN0002_00_Bomb") == 1, "Hen and Bomb came")
tick()
assert(count_of("EN0003_00_King") == 0, "the Kings went")
assert(settings.opponent == "mobcolvr_Hen" and settings.count == 2 and settings.mode == "opponents", "settings follow the group")

-- Two of one family told apart by their model: Bandit Axe and two Bandit Bats.
assert(api.apply({ group = "mobcolvr_BanditA,mobcolvr_BanditB,mobcolvr_BanditB" }))
tick(); tick()
assert(count_of("EN0008_00_Bandit_A") == 1 and count_of("EN0008_00_Bandit_B") == 2, "one Axe and two Bats")

-- The old way still works and ends the group.
assert(api.apply({ opponent = "mobcolvr_Bomb", count = 2 }))
tick(); tick()
assert(settings.group == "" and count_of("EN0002_00_Bomb") == 2 and count_of("EN0008_00_Bandit_A") == 0, "opponent and count: two Bombs")

-- Round mode: Course A round 1 = two Rats (its Ver1 template, at the round's level 19) and a Bomb, its spark wave 0.
local l = api.lists()
assert(l.group_max == 3 and #l.courses == 1 and l.courses[1].rounds[1].size == 3, "lists(): courses and rounds")
assert(l.courses[1].rounds[1].enemies == "Rat ×2, Bomb" and l.courses[1].name == "Course A", "round words: " .. l.courses[1].rounds[1].enemies)
assert(api.lists_text(l):match("\nround\tCOL_A\tterA_010\t1\t3\tRound 1\tRat ×2, Bomb\t\n"), "lists text round line")
assert(#l.conflicts == 1 and l.conflicts[1][1] == "mobcolvr_King" and l.conflicts[1][2] == "mobcolvr_Hen", "conflicts: King and Hen")
assert(api.lists_text(l):match("\nconflict\tmobcolvr_King\tmobcolvr_Hen\n"), "conflict line")
assert(l.courses[1].rounds[1].enemies_list[1].name == "Rat" and l.courses[1].rounds[1].enemies_list[1].count == 2, "enemies_list")
world.spawned = {}
assert(api.apply({ round = "terA_010" }))
assert(settings.mode == "round", "round sets the mode")
tick(); tick()
assert(count_of("EN0001_00_Rat") == 3 and count_of("EN0002_00_Bomb") == 1, "two Rats (and the anchor) and the round's Bomb")
assert(world.slots[0] == "mobcolvr_Spark", "the round's own wave 0")
local rat_template
for _, sp in ipairs(world.spawned) do if spec_of[sp.template] == "EN0001_00_Rat" then rat_template = sp.template end end
assert(rat_template == "mobcolvr_Rat_Ver1", "the round's own template")
st = api.state()
assert(st.mode == "round" and st.round == "terA_010" and st.round_name == "Course A · Round 1" and st.course == "COL_A", "state() round")
-- One falls: not back until the whole set has fallen; then all of it comes back.
local function fall(spec) -- one of the round's, not the anchor
    for i, e in ipairs(world.enemies) do
        if e.spec == spec and e.name ~= s.anchor_key then table.remove(world.enemies, i); return end
    end
end
fall("EN0002_00_Bomb"); tick()
assert(count_of("EN0002_00_Bomb") == 0, "a round's enemy stays down while the rest stand")
fall("EN0001_00_Rat"); tick()
assert(count_of("EN0001_00_Rat") == 2 and count_of("EN0002_00_Bomb") == 0, "still down: one Rat stands")
fall("EN0001_00_Rat"); tick(); tick()
assert(count_of("EN0001_00_Rat") == 1 and count_of("EN0002_00_Bomb") == 0, "cleared: only the anchor, waiting")
assert(api.respawn()); tick(); tick()
assert(count_of("EN0001_00_Rat") == 3 and count_of("EN0002_00_Bomb") == 1, "Respawn: the whole set back")
-- ct_auto_respawn = on: it comes back by itself.
settings.auto_respawn = "on"
fall("EN0002_00_Bomb"); fall("EN0001_00_Rat"); fall("EN0001_00_Rat"); tick(); tick()
assert(count_of("EN0001_00_Rat") == 3 and count_of("EN0002_00_Bomb") == 1, "auto respawn: the whole set back by itself")
settings.auto_respawn = "off"
assert(api.state().mode == "round", "still the round")
-- Passive and Healing: a set killed in one blow (before any refill) comes back by itself; Aggressive waits.
for _, b in ipairs({ "passive", "healing" }) do
    settings.behaviour = b
    fall("EN0002_00_Bomb"); fall("EN0001_00_Rat"); fall("EN0001_00_Rat"); tick(); tick()
    assert(count_of("EN0001_00_Rat") == 3 and count_of("EN0002_00_Bomb") == 1, b .. ": the whole set back by itself")
end
settings.behaviour = "aggressive"
fall("EN0002_00_Bomb"); fall("EN0001_00_Rat"); fall("EN0001_00_Rat"); tick(); tick()
assert(count_of("EN0001_00_Rat") == 1 and count_of("EN0002_00_Bomb") == 0, "aggressive: waits for Respawn")
assert(api.respawn()); tick(); tick()
assert(count_of("EN0001_00_Rat") == 3, "and Respawn brings it")

-- A round that never appears is given up, back to the opponents.
world.enemies = {}; add("EN0001_00_Rat")
local s2 = session_module.new({ game = game, catalogue = catalogue, settings = { opponent = "mobcolvr_Rat", count = 1, group = "",
    mode = "round", round = "terA_020", behaviour = "aggressive", difficulty = "normal" }, save_settings = function() end,
    log = function() end, clock = function() return clock end })
for _ = 1, 100 do clock = clock + 0.25; s2:tick() end -- 25 s: two 8 s waits
assert(s2.settings.mode == "opponents" and s2.unspawnable["round:terA_020"], "the Ghost's round given up")
api.bind(s)

-- Room (owner 2026-11-21: filter opponents by stage). The King needs 22 m, a round its course's 18; a stage of 15 m
-- refuses both with a reason, and a course started there with a stored setup that doesn't fit falls back.
for _, o in ipairs(catalogue.opponents) do o.needs = 12 end
catalogue.opponents[3].needs = 22
catalogue.courses[1].needs = 18
s.stage_override = { id = "small", name = "Small Room", radius_m = 15 }
local ok2, why2 = api.apply({ group = "mobcolvr_King" })
assert(not ok2 and why2:match("larger stage than Small Room"), "the King refused: " .. tostring(why2))
ok2, why2 = api.apply({ round = "terA_010" })
assert(not ok2 and why2:match("18 m"), "the round refused: " .. tostring(why2))
ok2, why2 = api.apply({ group = "mobcolvr_Rat,mobcolvr_Bomb" })
assert(ok2, "12 + 2 = 14 m fits 15: " .. tostring(why2))
ok2, why2 = api.apply({ group = "mobcolvr_Rat,mobcolvr_Rat,mobcolvr_Bomb" })
assert(not ok2, "12 + 2 + 2 = 16 m does not fit 15")
ok2, why2 = api.apply({ opponent = "mobcolvr_King", count = 1 })
assert(not ok2 and why2:match("22 m"), "an opponent and count are measured too (the game took Alexander on a 13 m stage): " .. tostring(why2))
ok2, why2 = api.apply({ opponent = "mobcolvr_Rat", count = 3 })
assert(not ok2, "three Rats: 16 m")
local l2 = api.lists()
assert(l2.room_m == 15 and l2.stage_name == "Small Room" and l2.courses[1].rounds[1].needs_m == 18, "lists(): room and needs")
assert(api.lists_text(l2):match("\topponent\t") == nil and api.state().room_m == 15, "state(): room")
-- A stored King on the small stage at the start of a course: falls back, and says so.
settings.mode, settings.group, settings.opponent, settings.count = "opponents", "", "mobcolvr_King", 1
s.last_good = "mobcolvr_Bomb"
s:fit_to_stage()
assert(settings.opponent == "mobcolvr_Bomb" and s.fallback:match("King") and s.fallback:match("Bomb instead"), "fallback: " .. tostring(s.fallback))
-- The plain arena: no limit.
s.stage_override = false
assert(api.apply({ group = "mobcolvr_King" }), "the plain arena takes the King")
s.stage_override = nil

-- A behaviour change restarts the wave's clock (meters' run: a clear 7 s after a change to Aggressive read 106 s).
world.enemies = {}
add("EN0001_00_Rat") -- a new course's opening enemy: the anchor
local bsettings = { opponent = "mobcolvr_Bomb", count = 1, group = "", mode = "opponents", round = "",
                    behaviour = "passive", difficulty = "normal", auto_respawn = "off" }
local sb = session_module.new({ game = game, catalogue = catalogue, settings = bsettings, save_settings = function() end,
    log = function() end, clock = function() return clock end })
sb.stage_override = false
local function tb(dt) clock = clock + (dt or 0.25); return sb:tick() end
tb(0); tb(); tb()
assert(count_of("EN0002_00_Bomb") == 1, "the Bomb")
clock = clock + 100; tb()
sb:apply({ behaviour = "aggressive" }, clock)
clock = clock + 7
for i, e in ipairs(world.enemies) do if e.spec == "EN0002_00_Bomb" then table.remove(world.enemies, i); break end end
tb(); tb()
assert(sb.clear_noted and math.abs(sb.last_clear - 7.5) < 1, "timed from the change: " .. tostring(sb.last_clear))

-- Replaced at once (owner 2026-11-21: Phoenix's and a Flan's moves came during Titan's fight): on a change the old ones
-- are held and out of targeting before they go, and an add of the old opponent that appears just after the change is
-- retired too; one of the new opponent's own adds is not.
do
    world.enemies = {}
    add("EN0001_00_Rat") -- the anchor
    local held = {}
    local old_hold, old_untarget = game.hold, game.untarget
    game.hold = function(a, passive) held[a.name] = passive end
    game.untarget = function(a) a.untargeted = true; return true end
    local rs = { opponent = "mobcolvr_King", count = 1, group = "", mode = "opponents", round = "", behaviour = "aggressive",
                 difficulty = "normal", auto_respawn = "off" }
    local sr = session_module.new({ game = game, catalogue = catalogue, settings = rs, save_settings = function() end,
        log = function() end, clock = function() return clock end })
    sr.stage_override = false
    local function tr() clock = clock + 0.25; return sr:tick() end
    tr(); tr(); tr()
    local king
    for _, e in ipairs(world.enemies) do if e.spec == "EN0003_00_King" then king = e end end
    assert(king, "the King")
    -- the King's spawn is delayed in the game; here the old one is held the moment the change is applied
    world.spawned = {}
    local real_spawn = game.spawn_wave
    game.spawn_wave = function(t, w) world.spawned[#world.spawned + 1] = { wave = w }; return { "x" } end -- the Bomb is late
    sr:apply({ opponent = "mobcolvr_Bomb", count = 1 }, clock)
    assert(held[king.name] == true and king.untargeted and sr.stale[king.name], "the King held and untargetable at once")
    local minion = add("EN0003_01_Minion") -- the King's script starts a minion during its removal
    tr()
    assert(held[minion.name] == true and count_of("EN0003_01_Minion") == 0, "the King's late minion retired: held and removed")
    game.spawn_wave = real_spawn
    for _ = 1, 40 do tr() end -- the held-back Bomb's request expires (8 s) and is asked again
    assert(count_of("EN0003_01_Minion") == 0 and count_of("EN0003_00_King") == 0 and count_of("EN0002_00_Bomb") == 1, "both gone, the Bomb there")
    -- the new opponent's own add (a Spark, its family in the Bomb's round waves? no: the Bomb has no adds here) is not
    -- touched outside the window
    clock = clock + 10
    local spark = add("EN0002_01_Spark")
    tr()
    assert(not sr.stale[spark.name], "after the window an add is left to the fight")
    game.hold, game.untarget = old_hold, old_untarget
end
