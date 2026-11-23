-- Placing spawned enemies (owner 2026-11-21): on the floor (they came out 2-3 m up, and Passive's hold kept them
-- there), flyers left at their height, and apart by their own size + 2 m (three Alexanders stood together).
local session_module = require("ct_session")
local T = "terP"
local catalogue = { territory = T, base = { { id = "mobcolvr_Rat", level = 20 } }, opponents = {
    { id = "mobcolvr_Rat", spec = "EN0001_00_Rat", label = "$en_Rat", category = 3, level = 20, slot = 0, home = {} },
    { id = "mobcolvr_Big", spec = "SU2030_01_Big", label = "$en_Big", category = 5, level = 70, slot = 0, home = {} },
    { id = "mobcolvr_Bat", spec = "EN2200_00_Bat", label = "$en_Bat", category = 3, level = 20, slot = 0, home = {}, air = true },
} }
local FLOOR = 10000
local size = { ["EN0001_00_Rat"] = { half = 60, radius = 40 }, ["SU2030_01_Big"] = { half = 500, radius = 400, extent = 450 },
               ["EN2200_00_Bat"] = { half = 80, radius = 80 } }
local world = { enemies = {}, n = 0, moves = 0 }
local slot0 = "mobcolvr_Rat"
local spec_of = { mobcolvr_Rat = "EN0001_00_Rat", mobcolvr_Big = "SU2030_01_Big", mobcolvr_Bat = "EN2200_00_Bat" }
local function add(spec, z)
    world.n = world.n + 1
    local a = { name = "E" .. world.n, spec = spec, hp = 100, max = 100, x = 0, y = 0, z = z or (FLOOR + 300) }
    world.enemies[#world.enemies + 1] = a
    return a
end
_G.CustomTrainingFindWaves = function() return "found" end
_G.CustomTrainingSetWave = function(slot, index) slot0 = ({ "mobcolvr_Rat", "mobcolvr_Big", "mobcolvr_Bat" })[index]; return true end
_G.CustomTrainingGetDifficulty, _G.CustomTrainingSetDifficulty = nil, nil
local game = {
    enemies = function() return world.enemies end,
    territory_of = function() return T end,
    name_of = function(a) return a.name end,
    spec = function(a) return a.spec end,
    hp = function(a) return a.hp, a.max end,
    refill = function(a) a.hp = a.max end,
    hold = function(a, passive)
        if passive and a.z > FLOOR + size[a.spec].half + 20 and not a.air_ok then world.held_in_air = true end
        a.held = passive
    end,
    stash = function(a, spot) a.x = 99999; return spot or {} end,
    untarget = function() return true end,
    in_battle = function() return true end,
    spawn_wave = function() add(spec_of[slot0]); return { "x" } end,
    remove = function(t, a)
        for i, e in ipairs(world.enemies) do if e == a then table.remove(world.enemies, i); return true end end
        return false
    end,
    lookup = function() return nil end,
    fname_index = function(name) return ({ mobcolvr_Rat = 1, mobcolvr_Big = 2, mobcolvr_Bat = 3 })[name] end,
    keys_down = function() return {} end,
    party = function() return {} end,
    set_hp_percent = function() end,
    refill_mp = function() return 0 end,
    show_panel = function() return true end,
    hide_panel = function() end,
    pause = function() end,
    location = function(a) return { X = a.x, Y = a.y, Z = a.z } end,
    move_to = function(a, spot) a.x, a.y, a.z = spot.X, spot.Y, spot.Z; world.moves = world.moves + 1; return true end,
    floor_z = function(context, spot) return FLOOR end,
    clear_way = function() return true end,
    size = function(a) return size[a.spec] end,
}
local clock = 0
local settings = { opponent = "mobcolvr_Big", count = 3, group = "", mode = "opponents", round = "", behaviour = "passive", difficulty = "normal" }
local s = session_module.new({ game = game, catalogue = catalogue, settings = settings, save_settings = function() end,
    log = function() end, clock = function() return clock end })
add("EN0001_00_Rat", FLOOR + 60) -- the anchor, on the floor
s:tick()
for _ = 1, 12 do clock = clock + 0.25; s:tick() end
local bigs = {}
for _, e in ipairs(world.enemies) do if e.spec == "SU2030_01_Big" then bigs[#bigs + 1] = e end end
assert(#bigs == 3, "three Bigs")
for _, e in ipairs(bigs) do assert(e.z == FLOOR + 500, "on the floor: " .. e.z) end
local function apart(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
-- size = the larger of capsule radius 400 and bounds 450: centre to centre at least 450 + 450 + 200
assert(apart(bigs[1], bigs[2]) >= 1100 and apart(bigs[1], bigs[3]) >= 1100 and apart(bigs[2], bigs[3]) >= 1100,
    "apart by size + 2 m: " .. apart(bigs[1], bigs[2]) .. " " .. apart(bigs[1], bigs[3]) .. " " .. apart(bigs[2], bigs[3]))
assert(not world.held_in_air and bigs[1].held, "held, and only on the floor")
-- A flyer keeps its height.
settings.group = ""
s:apply({ opponent = "mobcolvr_Bat", count = 1 }, clock)
for _ = 1, 12 do clock = clock + 0.25; s:tick() end
local bat
for _, e in ipairs(world.enemies) do if e.spec == "EN2200_00_Bat" then bat = e end end
assert(bat and bat.z == FLOOR + 300, "a flyer left at its height")

-- The party: an enemy put down on top of Cloud is moved off him (one pushed him through the floor, 2026-11-21), and a
-- member who fell through the floor is put back on it where the course opened.
local cloud = { name = "Cloud", spec = "PC0000", x = 0, y = 0, z = FLOOR + 88 }
size["PC0000"] = { half = 88, radius = 34 }
game.party = function() return { { id = "Cloud", actor = cloud, kind = 0, hp = 100, max = 100 } } end
world.enemies = {}
add("EN0001_00_Rat", FLOOR + 60) -- a new course: its opening enemy at 0,0 is the anchor and the arena's spot
local s2 = session_module.new({ game = game, catalogue = catalogue, settings = { opponent = "mobcolvr_Rat", count = 1, group = "",
    mode = "opponents", round = "", behaviour = "aggressive", difficulty = "normal" }, save_settings = function() end,
    log = function() end, clock = function() return clock end })
s2:tick()
for _ = 1, 12 do clock = clock + 0.25; s2:tick() end
local rat
for _, e in ipairs(world.enemies) do if e.spec == "EN0001_00_Rat" and e.name ~= s2.anchor_key then rat = e end end
assert(rat and math.sqrt(rat.x ^ 2 + rat.y ^ 2) >= 40 + 50 + 200, "the Rat moved off Cloud: " .. tostring(rat and math.sqrt(rat.x ^ 2 + rat.y ^ 2)))
cloud.x, cloud.y, cloud.z = 5000, 5000, FLOOR - 2000
clock = clock + 0.25; s2:tick()
assert(cloud.z == FLOOR + 88 + 5 and cloud.x == 0 and s2.party_caught == 1, "Cloud back on the floor: " .. cloud.z)
-- An add (not a member of the setup) is put on the floor but not moved apart.
local minion = add("EN0099_00_Minion", FLOOR + 400)
minion.x, minion.y = rat.x, rat.y
size["EN0099_00_Minion"] = { half = 50, radius = 30 }
for _ = 1, 8 do clock = clock + 0.25; s2:tick() end
assert(minion.z == FLOOR + 50 and minion.x == rat.x and minion.y == rat.y, "the add grounded where it came, not moved apart")
game.party = function() return {} end

-- A prop 8 m up at the spawn point (Inside the Lifestream, 2026-11-21): the trace there hits it, not the floor; the
-- party's floor is the reference, and the enemy goes on the real floor, apart from the others.
do
    local cloud2 = { name = "Cloud", spec = "PC0000", x = 3000, y = 0, z = FLOOR + 88 }
    game.party = function() return { { id = "Cloud", actor = cloud2, kind = 0, hp = 100, max = 100 } } end
    local real_floor = game.floor_z
    game.floor_z = function(context, spot)
        if math.abs(spot.X) < 100 and math.abs(spot.Y) < 100 and spot.Z > FLOOR + 800 then return FLOOR + 800 end
        return FLOOR
    end
    world.enemies = {}
    add("EN0001_00_Rat", FLOOR + 60)
    local s3 = session_module.new({ game = game, catalogue = catalogue, settings = { opponent = "mobcolvr_Big", count = 3,
        group = "", mode = "opponents", round = "", behaviour = "passive", difficulty = "normal" }, save_settings = function() end,
        log = function() end, clock = function() return clock end })
    -- spawns come out at 0,0 and 9 m up, above the prop
    local old_spawn = game.spawn_wave
    game.spawn_wave = function(t, w) local a = add(spec_of[slot0], FLOOR + 900); return { "x" } end
    s3:tick()
    for _ = 1, 12 do clock = clock + 0.25; s3:tick() end
    local bigs = {}
    for _, e in ipairs(world.enemies) do if e.spec == "SU2030_01_Big" then bigs[#bigs + 1] = e end end
    assert(#bigs == 3, "three Bigs: " .. #bigs)
    for _, e in ipairs(bigs) do assert(e.z == FLOOR + 500, "on the real floor, not the prop: " .. e.z) end
    assert(math.sqrt((bigs[1].x - bigs[2].x) ^ 2 + (bigs[1].y - bigs[2].y) ^ 2) >= 1100, "apart")
    game.spawn_wave, game.floor_z = old_spawn, real_floor
    game.party = function() return {} end
end

-- Far away at the arena's height (some fights' scripts put the party at the world's origin, 2026-11-22): caught too.
do
    local cloud3 = { name = "Cloud", spec = "PC0000", x = 0, y = 0, z = FLOOR + 88 }
    size["PC0000"] = { half = 88, radius = 34 }
    game.party = function() return { { id = "Cloud", actor = cloud3, kind = 0, hp = 100, max = 100 } } end
    world.enemies = {}
    add("EN0001_00_Rat", FLOOR + 60)
    local s6 = session_module.new({ game = game, catalogue = catalogue, settings = { opponent = "mobcolvr_Rat", count = 1,
        group = "", mode = "opponents", round = "", behaviour = "aggressive", difficulty = "normal" },
        save_settings = function() end, log = function() end, clock = function() return clock end })
    for _ = 1, 8 do clock = clock + 0.25; s6:tick() end
    cloud3.x, cloud3.y, cloud3.z = 200000, 100000, FLOOR + 10080
    clock = clock + 0.25; s6:tick()
    assert(cloud3.x == 0 and cloud3.z == FLOOR + 88 + 5 and s6.party_caught == 1, "caught from far away: " .. cloud3.x .. " " .. cloud3.z)
    game.party = function() return {} end
end
