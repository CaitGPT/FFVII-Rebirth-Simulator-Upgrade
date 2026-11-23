local Tracker = require("meters_tracker")

local function near(a, b) return math.abs(a - b) < 1e-6 end
local function member(id, hp, max, mp, names) return { id = id, hp = hp, max = max or 5000, mp = mp, names = names } end
local function enemy(key, name, hp, max) return { key = key, name = name, hp = hp, max = max or 100000 } end

-- Strict (hit events present), Passive: damage by who dealt it, the unexplained rest Unattributed.
local t = Tracker.new(5)
local cloud_names = { "Cloud", "PC0000_00" }
local zack_names = { "ZACK", "PC0009_00" }
local party = function(c, z) return { member("Cloud", c, 5000, 100, cloud_names), member("Zack", z, 6000, 100, zack_names) } end
t:tick({ now = 1, native = true, behaviour = "passive", party = party(5000, 6000), enemies = { enemy("a", "EN_A", 100000) } })
t:tick({ now = 2, native = true, behaviour = "passive", party = party(5000, 6000), enemies = { enemy("a", "EN_A", 99000) },
    hits = { { damage = 700, causer = "Cloud", target = "EN_A", heal = false }, { damage = 200, causer = "ZACK", target = "EN_A", heal = false } } })
local s = t:snapshot(2)
assert(s.strict and s.kinds.damage.total == 1000 and s.kinds.damage.attributed)
assert(s.kinds.damage.by_source.Cloud == 700 and s.kinds.damage.by_source.Zack == 200 and s.kinds.damage.by_source.Unattributed == 100)
assert(s.party[1] == "Cloud" and s.party[2] == "Zack")

-- Strict, Healing: Custom Training's drop to 1% and its refills aren't counted; a heal counts for who cast it, up to
-- the HP really gained.
t = Tracker.new(5)
t:tick({ now = 1, native = true, behaviour = "healing", party = party(5000, 6000), enemies = { enemy("a", "EN_A", 100000) } })
t:tick({ now = 2, native = true, behaviour = "healing", party = party(50, 60), enemies = { enemy("a", "EN_A", 100000) } })
s = t:snapshot(2)
assert(s.kinds.taken.total == 0, "the 1% hold is not damage taken")
t:tick({ now = 3, native = true, behaviour = "healing", party = party(50, 2060), enemies = { enemy("a", "EN_A", 100000) },
    hits = { { damage = 3000, causer = "Cloud", target = "ZACK", heal = true } } })
s = t:snapshot(3)
assert(s.kinds.heal.total == 2000, "capped at the HP gained")
assert(s.kinds.heal.by_source.Cloud == 2000 and s.kinds.heal.attributed)
t:tick({ now = 4.6, native = true, behaviour = "healing", party = party(50, 60), enemies = { enemy("a", "EN_A", 100000) } })
s = t:snapshot(4.6)
assert(s.kinds.taken.total == 0 and s.kinds.heal.total == 2000, "dropping back is nothing")

-- Strict, Aggressive: an enemy hit is damage taken by who took it; the refill to full isn't healing.
t = Tracker.new(5)
t:tick({ now = 1, native = true, behaviour = "aggressive", party = party(5000, 6000), enemies = { enemy("a", "EN_A", 100000) } })
t:tick({ now = 2, native = true, behaviour = "aggressive", party = party(2000, 6000), enemies = { enemy("a", "EN_A", 100000) },
    hits = { { damage = 3000, causer = "EN_A", target = "Cloud", heal = false } } })
t:tick({ now = 3, native = true, behaviour = "aggressive", party = party(5000, 6000), enemies = { enemy("a", "EN_A", 100000) } })
s = t:snapshot(3)
assert(s.kinds.taken.total == 3000 and s.kinds.taken.by_source.Cloud == 3000)
assert(s.kinds.heal.total == 0, "the refill is not healing")

-- Without hit events: the rules. Healing: the drop to 1% isn't damage taken; heals count by who received them.
t = Tracker.new(5)
t:tick({ now = 1, native = false, behaviour = "healing", party = party(5000, 6000), enemies = {} })
t:tick({ now = 2, native = false, behaviour = "healing", party = party(50, 60), enemies = {} })
t:tick({ now = 3, native = false, behaviour = "healing", party = party(1050, 60), enemies = {} })
s = t:snapshot(3)
assert(not s.strict and s.kinds.taken.total == 0 and s.kinds.heal.total == 1000 and s.kinds.heal.by_source.Cloud == 1000)
assert(not s.kinds.heal.attributed)
-- Passive: a rise to full from below half is Custom Training's refill; any other loss and gain count.
t = Tracker.new(5)
t:tick({ now = 1, native = false, behaviour = "passive", party = party(5000, 6000), enemies = {} })
t:tick({ now = 2, native = false, behaviour = "passive", party = party(2000, 5000), enemies = {} })
t:tick({ now = 3, native = false, behaviour = "passive", party = party(5000, 5500), enemies = {} })
s = t:snapshot(3)
assert(s.kinds.taken.total == 4000 and s.kinds.taken.by_source.Cloud == 3000 and s.kinds.taken.by_source.Zack == 1000)
assert(s.kinds.heal.total == 500 and s.kinds.heal.by_source.Zack == 500)
-- Aggressive: real conditions (owner, 2026-11-21), no refills, so the same rise to full is a heal (a Cure, Auto-Life).
t = Tracker.new(5)
t:tick({ now = 1, native = false, behaviour = "aggressive", party = party(5000, 6000), enemies = {} })
t:tick({ now = 2, native = false, behaviour = "aggressive", party = party(2000, 5000), enemies = {} })
t:tick({ now = 3, native = false, behaviour = "aggressive", party = party(5000, 5500), enemies = {} })
s = t:snapshot(3)
assert(s.kinds.taken.total == 4000 and s.kinds.heal.total == 3500 and s.kinds.heal.by_source.Cloud == 3000)
-- Custom Training's clean-up after a start or change (no hit events): a rise to full in the first 3 s isn't healing,
-- in any behaviour (Passive tops up then and 2 s later; leaving Healing sets held members back to full); later it is.
t = Tracker.new(5)
t:tick({ now = 1, native = false, behaviour = "aggressive", party = party(5000, 6000), enemies = {} })
t:tick({ now = 2, native = false, behaviour = "aggressive", party = party(50, 6000), enemies = {} })
t:reset(true)
t:tick({ now = 3, native = false, behaviour = "aggressive", party = party(50, 6000), enemies = {} })
t:tick({ now = 5.5, native = false, behaviour = "aggressive", party = party(5000, 6000), enemies = {} })
assert(t:snapshot(5.5).kinds.heal.total == 0, "the clean-up's top-up")
t:tick({ now = 7, native = false, behaviour = "aggressive", party = party(3000, 6000), enemies = {} })
t:tick({ now = 8, native = false, behaviour = "aggressive", party = party(5000, 6000), enemies = {} })
assert(t:snapshot(8).kinds.heal.total == 2000, "a heal to full after the window counts")
t:reset()   -- F5: no clean-up window
t:tick({ now = 9, native = false, behaviour = "aggressive", party = party(3000, 6000), enemies = {} })
t:tick({ now = 10, native = false, behaviour = "aggressive", party = party(5000, 6000), enemies = {} })
assert(t:snapshot(10).kinds.heal.total == 2000, "after F5 a heal to full counts")
-- Damage without hit events: a total, no split.
t:tick({ now = 4, native = false, party = party(5000, 5500), enemies = { enemy("a", "EN_A", 1000) } })
t:tick({ now = 5, native = false, party = party(5000, 5500), enemies = { enemy("a", "EN_A", 600) } })
s = t:snapshot(5)
assert(s.kinds.damage.total == 400 and not s.kinds.damage.attributed and next(s.kinds.damage.by_source) == nil)

-- An opponent that vanishes takes its last HP as the killing blow (not when the battle ends from above half).
t = Tracker.new(5)
t:tick({ now = 1, native = false, party = {}, enemies = { enemy("a", "EN_A", 300, 1000), enemy("b", "EN_B", 900, 1000) } })
t:tick({ now = 2, native = false, party = {}, enemies = { enemy("b", "EN_B", 900, 1000) } })
assert(t:snapshot(2).kinds.damage.total == 300)
t:tick({ now = 3, native = false, party = {}, enemies = {}, battle_over = true })
assert(t:snapshot(3).kinds.damage.total == 300, "the battle ended with B above half: not counted")

-- Opponents Custom Training removes (Apply with another opponent) leave with their HP: never damage (seen 2026-11-21,
-- a Titan removed on Apply counted 84,186). With hit events: the course change clears and marks them outgoing.
t = Tracker.new(5)
local cloud = { member("Cloud", 5000, 5000, 100, cloud_names) }
t:tick({ now = 1, native = true, party = cloud, enemies = { enemy("t", "EN_Titan", 90000, 100000) } })
t:tick({ now = 2, native = true, party = cloud, enemies = { enemy("t", "EN_Titan", 84186, 100000) },
    hits = { { damage = 5814, causer = "Cloud", target = "EN_Titan" } } })
assert(t:snapshot(2).kinds.damage.total == 5814)
t:reset(true)
t:tick({ now = 3, native = true, party = cloud, enemies = { enemy("t", "EN_Titan", 84186, 100000) } })
t:tick({ now = 4, native = true, party = cloud, enemies = {} })
t:tick({ now = 5, native = true, party = cloud, enemies = { enemy("n", "EN_Bomb", 8000, 8000) } })
assert(t:snapshot(5).kinds.damage.total == 0, "the removed Titan counts nothing")
t:tick({ now = 6, native = true, party = cloud, enemies = { enemy("n", "EN_Bomb", 7000, 8000) },
    hits = { { damage = 1000, causer = "Cloud", target = "EN_Bomb" } } })
local d = t:snapshot(6).kinds.damage
assert(d.total == 1000 and d.by_source.Cloud == 1000, "the new opponent counts as usual")
-- Removed in the same reading as the course change (not seen again after the clear): outgoing too.
t = Tracker.new(5)
t:tick({ now = 1, native = true, party = cloud, enemies = { enemy("t", "EN_Titan", 84186, 100000) } })
t:reset(true)
t:reset()   -- the fight-started clear in the same tick doesn't undo it
t:tick({ now = 2, native = true, party = cloud, enemies = {} })
assert(t:snapshot(2).kinds.damage.total == 0)
-- Opponents first seen in the reading after a course change are on their way out as well.
t = Tracker.new(5)
t:reset(true)
t:tick({ now = 1, native = true, party = cloud, enemies = { enemy("t", "EN_Titan", 84186, 100000) } })
t:tick({ now = 2, native = true, party = cloud, enemies = { enemy("n", "EN_Bomb", 8000, 8000) } })
assert(t:snapshot(2).kinds.damage.total == 0)
-- Without a course change, with hit events: a vanishing opponent counts only what a hit on it explains.
t = Tracker.new(5)
t:tick({ now = 1, native = true, party = cloud, enemies = { enemy("a", "EN_A", 500, 1000), enemy("b", "EN_B", 900, 1000) } })
t:tick({ now = 2, native = true, party = cloud, enemies = {}, hits = { { damage = 9000, causer = "Cloud", target = "EN_A" } } })
d = t:snapshot(2).kinds.damage
assert(d.total == 500 and d.by_source.Cloud == 500, "the killing blow on A; B left unhit: nothing")
-- Without hit events: only from half its HP or less (Battle Meters' killing blow); more left is a removal.
t = Tracker.new(5)
t:tick({ now = 1, native = false, party = {}, enemies = { enemy("a", "EN_A", 300, 1000), enemy("b", "EN_B", 900, 1000) } })
t:tick({ now = 2, native = false, party = {}, enemies = {} })
assert(t:snapshot(2).kinds.damage.total == 300)
t = Tracker.new(5)
t:tick({ now = 1, native = false, party = {}, enemies = { enemy("a", "EN_A", 300, 1000) } })
t:reset(true)
t:tick({ now = 2, native = false, party = {}, enemies = {} })
assert(t:snapshot(2).kinds.damage.total == 0)
-- The same key back with another opponent (an address used again): a new opponent, no drop between the two.
t = Tracker.new(5)
t:tick({ now = 1, native = false, party = {}, enemies = { enemy("a", "EN_Titan", 84186, 100000) } })
t:tick({ now = 2, native = false, party = {}, enemies = { enemy("a", "EN_Bomb", 8000, 8000) } })
t:tick({ now = 3, native = false, party = {}, enemies = { enemy("a", "EN_Bomb", 7500, 8000) } })
assert(t:snapshot(3).kinds.damage.total == 500)
-- A clear mid-fight keeps the opponents known: what they lose after it counts, nothing before.
t = Tracker.new(5)
t:tick({ now = 1, native = false, party = {}, enemies = { enemy("a", "EN_A", 1000) } })
t:tick({ now = 2, native = false, party = {}, enemies = { enemy("a", "EN_A", 900) } })
t:reset()
t:tick({ now = 3, native = false, party = {}, enemies = { enemy("a", "EN_A", 700) } })
assert(t:snapshot(3).kinds.damage.total == 200)

-- Waves (owner, 2026-11-21): enemies don't refill; once the chosen set is killed it respawns. Damage stops at the HP
-- an enemy had (an overkill blow counts only that), and a new wave is neither damage nor healing, whether it comes as
-- new actors or as the same ones back at full. With and without hit events.
for _, native in ipairs({ true, false }) do
    t = Tracker.new(5)
    local function tick(now, enemies, hits, members)
        t:tick({ now = now, native = native, behaviour = "passive", party = members or party(5000, 6000), enemies = enemies,
            hits = native and hits or nil })
    end
    tick(1, { enemy("a", "EN_A", 3000, 3000), enemy("b", "EN_B", 3000, 3000) })
    tick(2, { enemy("a", "EN_A", 0, 3000), enemy("b", "EN_B", 1000, 3000) },
        { { damage = 9999, causer = "Cloud", target = "EN_A" }, { damage = 2000, causer = "ZACK", target = "EN_B" } })
    tick(3, { enemy("b", "EN_B", 0, 3000) }, { { damage = 5000, causer = "ZACK", target = "EN_B" } })
    tick(4, {})                                                               -- cleared: both gone
    tick(5, { enemy("c", "EN_A", 3000, 3000), enemy("d", "EN_B", 3000, 3000) })   -- wave 2: new actors
    s = t:snapshot(5)
    assert(s.kinds.damage.total == 6000, "only the HP they had: " .. s.kinds.damage.total)
    assert(s.kinds.heal.total == 0 and s.kinds.taken.total == 0, "a wave isn't healing or damage taken")
    if native then
        assert(s.kinds.damage.by_source.Cloud == 3000 and s.kinds.damage.by_source.Zack == 3000, "credit capped per kill: " .. tostring(s.kinds.damage.by_source.Cloud) .. " " .. tostring(s.kinds.damage.by_source.Zack))
    end
    -- Wave 3 as the same actors back at full (if Custom Training revives them instead).
    tick(6, { enemy("c", "EN_A", 0, 3000), enemy("d", "EN_B", 0, 3000) },
        { { damage = 3000, causer = "Cloud", target = "EN_A" }, { damage = 3000, causer = "Cloud", target = "EN_B" } })
    tick(7, { enemy("c", "EN_A", 3000, 3000), enemy("d", "EN_B", 3000, 3000) })
    tick(8, { enemy("c", "EN_A", 2500, 3000), enemy("d", "EN_B", 3000, 3000) }, { { damage = 500, causer = "Cloud", target = "EN_A" } })
    s = t:snapshot(8)
    assert(s.kinds.damage.total == 12500 and s.kinds.heal.total == 0, "revived at full isn't counted: " .. s.kinds.damage.total)
end

-- A respawn mid-fight: the living opponents Custom Training removes count nothing (outgoing), even at half HP or less
-- without hit events; the totals before it stay, and the new wave counts as usual.
for _, native in ipairs({ true, false }) do
    t = Tracker.new(5)
    t:tick({ now = 1, native = native, party = {}, enemies = { enemy("a", "EN_A", 10000, 10000) } })
    t:tick({ now = 2, native = native, party = {}, enemies = { enemy("a", "EN_A", 4000, 10000) },
        hits = native and { { damage = 6000, causer = "Cloud", target = "EN_A" } } or nil })
    t:outgoing()
    t:tick({ now = 3, native = native, party = {}, enemies = { enemy("b", "EN_A", 10000, 10000) } })
    t:tick({ now = 4, native = native, party = {}, enemies = { enemy("b", "EN_A", 9000, 10000) },
        hits = native and { { damage = 1000, causer = "Cloud", target = "EN_A" } } or nil })
    assert(t:snapshot(4).kinds.damage.total == 7000, "respawn mid-fight: " .. t:snapshot(4).kinds.damage.total)
end

-- MP: Custom Training's counts when given, else the party's own MP drops.
t = Tracker.new(5)
t:tick({ now = 1, native = false, party = party(5000, 6000), enemies = {}, mp_spent = { Cloud = 12 } })
t:tick({ now = 2, native = false, party = { member("Cloud", 5000, 5000, 20, cloud_names) }, enemies = {}, mp_spent = { Cloud = 8 } })
assert(t:snapshot(2).kinds.mp.total == 20)
t = Tracker.new(5)
t:tick({ now = 1, native = false, party = { member("Cloud", 5000, 5000, 100) }, enemies = {} })
t:tick({ now = 2, native = false, party = { member("Cloud", 5000, 5000, 70) }, enemies = {} })
t:tick({ now = 3, native = false, party = { member("Cloud", 5000, 5000, 100) }, enemies = {} })
assert(t:snapshot(3).kinds.mp.total == 30)

-- Reset starts again from nothing; the averages run from the first number.
t:reset()
assert(t:snapshot(3).kinds.mp.total == 0)
t:tick({ now = 10, native = false, party = {}, enemies = { enemy("a", "EN_A", 1000) } })
t:tick({ now = 12, native = false, party = {}, enemies = { enemy("a", "EN_A", 400) } })
local k = t:snapshot(14).kinds.damage
assert(k.total == 600 and near(k.average, 300), "averaged over the 2 s since the first number")
