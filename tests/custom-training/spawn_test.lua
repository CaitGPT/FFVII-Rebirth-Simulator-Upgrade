-- ct_session's spawning against a fake game whose summons take 10 s to appear, all at one spot (2026-11-21: three
-- Titans were given up at once after 8 s; three Alexanders stood 0.0 m apart).
local session_module = require("ct_session")
local T = "terS"
local catalogue = { territory = T, base = { { id = "mobcolvr_R", level = 20 } }, opponents = {
    { id = "mobcolvr_R", spec = "EN0001_00_Rat", label = "$en_Rat", category = 3, level = 20, slot = 0, home = {} },
    { id = "mobcolvr_SU", spec = "SU2000_00_Titan_Standard", label = "$en_Titan", category = 5, level = 70, slot = 0, home = {} },
} }
local world = { enemies = {}, n = 0, due = {}, moved = 0 }
local clock = 0
local slot0 = "mobcolvr_R"
local spec_of = { mobcolvr_R = "EN0001_00_Rat", mobcolvr_SU = "SU2000_00_Titan_Standard" }
local delay_of = { mobcolvr_R = 0, mobcolvr_SU = 10 }
local function add(spec)
    world.n = world.n + 1
    local a = { name = "E" .. world.n, spec = spec, hp = 100, max = 100, x = 1000, y = 2000, z = 0 }
    world.enemies[#world.enemies + 1] = a
    return a
end
_G.CustomTrainingFindWaves = function() return "found" end
_G.CustomTrainingSetWave = function(slot, index) slot0 = index == 2 and "mobcolvr_SU" or "mobcolvr_R"; return true end
_G.CustomTrainingGetDifficulty, _G.CustomTrainingSetDifficulty = nil, nil
local game = {
    enemies = function() return world.enemies end,
    territory_of = function() return T end,
    name_of = function(a) return a.name end,
    spec = function(a) return a.spec end,
    hp = function(a) return a.hp, a.max end,
    refill = function(a) a.hp = a.max end,
    hold = function() end,
    stash = function(a, spot) a.x = a.x + 6000; return spot or {} end,
    untarget = function() return true end,
    in_battle = function() return true end,
    spawn_wave = function(t, w)
        world.due[#world.due + 1] = { at = clock + delay_of[slot0], spec = spec_of[slot0] }
        return { "x" }
    end,
    remove = function(t, a)
        for i, e in ipairs(world.enemies) do if e == a then table.remove(world.enemies, i); return true end end
        return false
    end,
    lookup = function() return nil end,
    fname_index = function(name) return name == "mobcolvr_SU" and 2 or 1 end,
    keys_down = function() return {} end,
    party = function() return {} end,
    set_hp_percent = function() end,
    refill_mp = function() return 0 end,
    show_panel = function() return true end,
    hide_panel = function() end,
    pause = function() end,
    location = function(a) return { X = a.x, Y = a.y, Z = a.z } end,
    move_to = function(a, spot) a.x, a.y = spot.X, spot.Y; world.moved = world.moved + 1; return true end,
}
local function step(dt)
    clock = clock + dt
    local kept = {}
    for _, d in ipairs(world.due) do if clock >= d.at then add(d.spec) else kept[#kept + 1] = d end end
    world.due = kept
    return s_tick and s_tick()
end
local settings = { opponent = "mobcolvr_SU", count = 3, behaviour = "aggressive", difficulty = "normal" }
local s = session_module.new({ game = game, catalogue = catalogue, settings = settings, save_settings = function() end,
    log = function() end, clock = function() return clock end })
s_tick = function() return s:tick() end
add("EN0001_00_Rat") -- the opening enemy, the anchor
step(0)
for _ = 1, 60 do step(0.25) end -- 15 s
local titans = {}
for _, e in ipairs(world.enemies) do if e.spec == "SU2000_00_Titan_Standard" then titans[#titans + 1] = e end end
assert(settings.opponent == "mobcolvr_SU", "a summon that takes 10 s is not given up: " .. settings.opponent)
assert(#titans == 3, "three Titans, got " .. #titans)
local function apart(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
assert(apart(titans[1], titans[2]) >= 150 and apart(titans[1], titans[3]) >= 150 and apart(titans[2], titans[3]) >= 150,
    "the three moved apart")
assert(world.moved >= 2, "moved " .. world.moved)

-- One that never appears is still given up (after two expiries), and the one before it comes back.
delay_of.mobcolvr_SU = 1e9
world.enemies, world.due = { world.enemies[1] }, {}
local s2 = session_module.new({ game = game, catalogue = catalogue, settings = { opponent = "mobcolvr_R", count = 1,
    behaviour = "aggressive", difficulty = "normal" }, save_settings = function() end, log = function() end,
    clock = function() return clock end })
s_tick = function() return s2:tick() end
for _ = 1, 8 do step(0.25) end
s2:apply({ opponent = "mobcolvr_SU" }, clock)
for _ = 1, 200 do step(0.25) end -- 50 s: two 20 s waits
assert(s2.settings.opponent == "mobcolvr_R" and s2.unspawnable.mobcolvr_SU, "never appeared: given up")
s_tick = nil

-- The wave row not found (ui's run on Cave of the Gi, 2026-11-21: "not found: templates 1, levels 2"): searched again
-- 5 s apart, three times; meanwhile an opponent outside the built-in slots waits, and the log says so once; when the
-- search finds it after all, the opponent comes.
do
    local answers = { "not found: templates 1, levels 2", "not found: templates 1, levels 2", "found" }
    local asked = 0
    _G.CustomTrainingFindWaves = function()
        asked = asked + 1
        return answers[math.min(asked, #answers)]
    end
    local logs = {}
    world.enemies, world.due = {}, {}
    delay_of.mobcolvr_SU = 0
    add("EN0001_00_Rat")
    local s4 = session_module.new({ game = game, catalogue = catalogue, settings = { opponent = "mobcolvr_SU", count = 1,
        behaviour = "aggressive", difficulty = "normal" }, save_settings = function() end,
        log = function(l) logs[#logs + 1] = l end, clock = function() return clock end })
    s_tick = function() return s4:tick() end
    for _ = 1, 8 do step(0.25) end -- 2 s: not found, nothing spawned
    local said = 0
    for _, l in ipairs(logs) do if l:match("no slot for mobcolvr_SU") then said = said + 1 end end
    assert(said == 1, "said once: " .. said)
    for _ = 1, 50 do step(0.25) end -- 12.5 s: searched again twice, found on the second retry
    local titans = 0
    for _, e in ipairs(world.enemies) do if e.spec == "SU2000_00_Titan_Standard" then titans = titans + 1 end end
    assert(asked == 3 and titans == 1 and s4.settings.opponent == "mobcolvr_SU", "found on a retry, the Titan came: " .. asked .. " " .. titans)
    -- Never found: after three retries, an opponent outside the built-in slots is given up, and the course falls back.
    answers = { "not found: templates 1, levels 2" }
    asked = 0
    world.enemies, world.due = {}, {}
    add("EN0001_00_Rat")
    local s5 = session_module.new({ game = game, catalogue = catalogue, settings = { opponent = "mobcolvr_SU", count = 1,
        behaviour = "aggressive", difficulty = "normal" }, save_settings = function() end, log = function() end,
        clock = function() return clock end })
    s_tick = function() return s5:tick() end
    for _ = 1, 100 do step(0.25) end -- 25 s
    assert(asked == 4 and s5.settings.opponent == "mobcolvr_R" and s5.unspawnable.mobcolvr_SU, "given up after three retries: " .. asked .. " " .. s5.settings.opponent)
    _G.CustomTrainingFindWaves = function() return "found" end
    s_tick = nil
end
