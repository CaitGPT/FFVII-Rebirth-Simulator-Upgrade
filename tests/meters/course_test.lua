local Course = require("meters_course")

local function file(t)
    local lines = {}
    for _, k in ipairs({ "what", "active", "behaviour", "opponent", "name", "boss", "count", "difficulty", "anchor" }) do
        lines[#lines + 1] = k .. "=" .. tostring(t[k])
    end
    for who, n in pairs(t.mp or {}) do lines[#lines + 1] = "mp." .. who .. "=" .. n end
    return table.concat(lines, "\n") .. "\n"
end

local base = { what = "start", active = true, behaviour = "passive", opponent = "EN2001_00", name = "Bomb", boss = false,
    count = 1, difficulty = "normal", anchor = "EN9999_Anchor_C_123" }
local function with(changes)
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for k, v in pairs(changes or {}) do t[k] = v end
    return t
end

local p = Course.parse(file(base))
assert(p.active == true and p.behaviour == "passive" and p.count == "1" and p.boss == false and p.anchor == "EN9999_Anchor_C_123")
assert(next(p.mp) == nil)

local c = Course.new()
assert(not c:active())
local event, behaviour_changed = c:update(Course.parse(file(base)))
assert(event == "start" and behaviour_changed and c:active())
assert(c:update(Course.parse(file(base))) == nil, "the same file again is nothing")
event, behaviour_changed = c:update(Course.parse(file(with({ what = "change", count = 3 }))))
assert(event == "change" and not behaviour_changed)
event, behaviour_changed = c:update(Course.parse(file(with({ what = "change", count = 3, behaviour = "healing" }))))
assert(event == "change" and behaviour_changed)
event = c:update(Course.parse(file(with({ what = "end", active = false, count = 3, behaviour = "healing" }))))
assert(event == "end" and not c:active())
assert(c:update(Course.parse(file(with({ what = "end", active = false })))) == nil)
assert(c:update(nil) == nil)
assert(c:update(Course.parse(file(base))) == "start")

-- MP counts: amounts spent since the last call; a count that restarts is new.
c = Course.new()
assert(not c:counts_mp())
c:update(Course.parse(file(with({ mp = { Cloud = 10, Aerith = 0 } }))))
assert(c:counts_mp())
local spent = c:mp_spent()
assert(spent.Cloud == 10 and spent.Aerith == nil)
assert(next(c:mp_spent()) == nil)
assert(c:update(Course.parse(file(with({ mp = { Cloud = 25, Aerith = 8 } })))) == nil, "MP alone is not a change")
spent = c:mp_spent()
assert(spent.Cloud == 15 and spent.Aerith == 8)
c:update(Course.parse(file(with({ mp = { Cloud = 4, Aerith = 8 } }))))
spent = c:mp_spent()
assert(spent.Cloud == 4 and spent.Aerith == nil)
-- A new start begins the counts again.
c:update(Course.parse(file(with({ active = false, what = "end", mp = { Cloud = 4, Aerith = 8 } }))))
c:update(Course.parse(file(with({ mp = { Cloud = 4, Aerith = 8 } }))))
spent = c:mp_spent()
assert(spent.Cloud == 4 and spent.Aerith == 8)

-- Waves (owner, 2026-11-21): a "wave" event (or a higher wave number in the file) is a wave, not a change; the wave
-- number and the last clear time stay on the kept state between events; a start or a change forgets them; a wave
-- doesn't restart the MP counts.
c = Course.new()
assert(c:update(with({ wave = 1, wave_started = 0, mp = { Cloud = 5 } })) == "start")
assert(c.state.wave == 1 and c.state.last_clear == nil)
c:mp_spent()
assert(c:update(with({ what = "wave", wave = 2, wave_started = 83.4, last_clear = 83.4, mp = { Cloud = 9 } })) == "wave")
assert(c.state.wave == 2 and c.state.last_clear == 83.4)
assert(c:mp_spent().Cloud == 4, "MP counts run on across a wave")
assert(c:update(with({ what = "nil" })) == nil, "a state() without the fields: nothing")
assert(c.state.wave == 2 and c.state.last_clear == 83.4, "kept between events")
local text = "what=wave\nactive=true\nbehaviour=passive\nopponent=EN2001_00\nname=Bomb\ncount=1\ndifficulty=normal\n"
    .. "anchor=EN9999_Anchor_C_123\nwave=3\nwave_started=150.2\nlast_clear=66.8\n"
assert(c:update(Course.parse(text)) == "wave" and c.state.wave == 3 and c.state.last_clear == 66.8, "from the file")
assert(c:update(Course.parse(text)) == nil, "the same file again is nothing")
assert(c:update(with({ what = "change", count = 2, wave = 1 })) == "change")
assert(c.state.wave == 1 and c.state.last_clear == nil, "a change forgets the last clear")
c:update(with({ what = "end", active = false }))
assert(c.state.wave == nil)
-- Wave 0 (Custom Training's "starting") to 1 is the first spawn, not a respawn; a respawn mid-fight leaves no clear
-- time, as Custom Training's state says.
c = Course.new()
assert(c:update(with({ what = "change", wave = 0 })) == "start")
assert(c:update(with({ what = "state", wave = 1 })) == nil, "0 to 1 isn't a wave event")
assert(c:update(with({ what = "wave", wave = 2, last_clear = 40, clear_time = 40, cleared = 1 })) == "wave")
assert(c:update(with({ what = "wave", wave = 3 })) == "wave" and c.state.last_clear == nil, "cut short: no clear time")
-- MP in Aggressive: no refills (owner, 2026-11-21), so not Custom Training's counts but the party's own MP. Counts
-- given before any refill (integrated: mp_counts) are used from the start in Passive and Healing.
c = Course.new()
c:update(with({ behaviour = "passive", mp = {}, mp_counts = true }))
assert(c:counts_mp() and next(c:mp_spent()) == nil, "integrated, before the first refill")
c:update(with({ what = "change", behaviour = "aggressive", mp = {}, mp_counts = true }))
assert(not c:counts_mp(), "Aggressive: the party's own MP")
c:update(with({ what = "change", behaviour = "passive", mp = { Cloud = 6 }, mp_counts = true }))
assert(c:counts_mp() and c:mp_spent().Cloud == 6, "back in Passive: counts again, from the change")
-- Which changes replace the opponents (they then count nothing when they go): a start, an opponent, count,
-- difficulty or round change; not a behaviour change (seen 2026-11-21: a Zu's last blow lost after Passive to
-- Aggressive).
c = Course.new()
assert(c:update(with({})) == "start" and c.replaced)
assert(c:update(with({ what = "change", behaviour = "aggressive" })) == "change" and not c.replaced, "behaviour only")
assert(c:update(with({ what = "change", behaviour = "aggressive", count = 2 })) == "change" and c.replaced, "count")
assert(c:update(with({ what = "change", behaviour = "aggressive", count = 2, difficulty = "hard" })) == "change" and c.replaced)
assert(c:update(with({ what = "change", behaviour = "aggressive", count = 2, difficulty = "hard", mode = "round", round = "R1" })) == "change"
    and c.replaced, "a round")
-- ct_api's group is a list, a new table on every call (seen in the game 2026-11-21: the meters cleared every tick):
-- the same members are the same setup; other members are a change.
c = Course.new()
c:update(with({ mode = "opponents", group = { "EN_A" } }))
assert(c:update(with({ mode = "opponents", group = { "EN_A" } })) == nil, "same group, new table: nothing")
assert(c:update(with({ what = "change", mode = "opponents", group = { "EN_A", "EN_B" } })) == "change" and c.replaced)
