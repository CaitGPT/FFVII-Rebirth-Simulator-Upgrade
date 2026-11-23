-- ui_model with mixed groups (Opponent 1, 2, 3) and pre-built rounds (Mode, Round): what Custom Training's lists() and
-- state() carry from 2026-11-21 (group_max, conflicts, courses, mode, group, round). Also ui_ct's parsing of them.
for _, m in ipairs({ "ui_model", "ui_ct" }) do package.loaded[m] = nil end
local model = require("ui_model")
local ct = require("ui_ct")

-- Humans 3, Machines 3 (the third capped at one copy), Beasts 30, Anomalies 150.
local function lists()
    local opponents = {}
    local kinds = { { "Humans", 3 }, { "Machines", 3 }, { "Beasts", 30 }, { "Anomalies", 150 } }
    local n = 0
    for k, def in ipairs(kinds) do
        for i = 1, def[2] do
            n = n + 1
            local letter = string.char(string.byte("A") + math.floor((i - 1) * 26 / def[2]))
            opponents[#opponents + 1] = { id = "o" .. n, name = letter .. " " .. def[1] .. " " .. i, kind = k,
                                          kind_name = def[1], max_count = (k == 2 and i == 3) and 1 or 3 }
        end
    end
    -- As Custom Training sends them: sorted by tab (TabCategory, with tab_name), rounds named "Round N" with their
    -- enemies as text ("Name ×N, ..."; a piece without a count is one).
    local X = "\195\151"
    local courses = {
        { id = "c1", tab = 1, tab_name = "Summons", name = "Titan", rounds = { { id = "c1r1", number = 1, name = "Round 1", enemies = "Titan " .. X .. "1", size = 1 } } },
        { id = "c2", tab = 1, tab_name = "Summons", name = "Phoenix", rounds = { { id = "c2r1", number = 1, name = "Round 1", enemies = "Phoenix", size = 1 } } },
    }
    for c = 1, 14 do
        courses[#courses + 1] = { id = "g" .. c, tab = 3, tab_name = "Regions", name = "Region Course " .. string.format("%02d", c),
                                  rounds = { { id = "g" .. c .. "r1", number = 1, name = "Round 1", enemies = "Bandit " .. X .. "3", size = 3 } } }
    end
    local brutal = { id = "c3", tab = 5, tab_name = "Brutal", name = "Brutal Challenge: Ultimate Party Animal", rounds = {} }
    for r = 1, 15 do
        brutal.rounds[r] = { id = "c3r" .. r, number = r, name = "Round " .. r, enemies = "Cerulean Drake " .. X .. "2, Sandworm " .. X .. "1", size = 3 }
    end
    brutal.rounds[4].enemies = "Elite Grenadier (Junon Ver1 Another Voice) " .. X .. "2, Special Forces Operator " .. X .. "1, Sandworm"
    courses[#courses + 1] = brutal
    return {
        opponents = opponents,
        behaviours = { { id = "passive", name = "Passive" }, { id = "aggressive", name = "Aggressive" }, { id = "healing", name = "Healing" } },
        difficulties = { { id = "easy", name = "Easy" }, { id = "normal", name = "Normal" }, { id = "dynamic", name = "Dynamic" }, { id = "hard", name = "Hard" } },
        max_count = 3, group_max = 3,
        conflicts = { { "o4", "o8" } }, -- their own adds need the same wave slot
        courses = courses,
    }
end
local L = lists()
local function name(id) for _, o in ipairs(L.opponents) do if o.id == id then return o.name end end end

local state = { active = true, mode = "opponents", group = { "o2", "o2", "o7" }, opponent = "o2", count = 2,
                behaviour = "passive", difficulty = "normal" }
local meters = { meter = "damage", visible = true }
local m = model.new(lists(), state, meters)

-- Every window: at most 13 rows, the cursor on one of them, no row longer than a row holds (main rows aside: the game
-- squeezes an opponent's name there, as before).
local function check(w)
    assert(#w.options <= model.PAGE + 1, w.screen .. " has " .. #w.options .. " rows")
    assert(w.focus >= 1 and w.focus <= #w.options, w.screen .. " focus " .. tostring(w.focus))
    if w.screen ~= "main" and w.screen ~= "names" then
        for _, o in ipairs(w.options) do assert(#o <= model.ROW_CHARS, w.screen .. ": " .. o) end
    end
    return w
end

-- The main window: Mode, three opponent rows, Behaviour, Difficulty, the meter rows, Apply, Cancel; no Number.
local w = check(m:window())
assert(#w.options == 11, #w.options)
assert(w.options[1] == "Mode:   Opponents", w.options[1])
assert(w.options[2] == "Opponent 1:   " .. name("o2") and w.options[3] == "Opponent 2:   " .. name("o2")
       and w.options[4] == "Opponent 3:   " .. name("o7"), w.options[4])
assert(w.options[5] == "Behaviour:   Passive" and w.options[6] == "Difficulty:   Normal" and w.options[7] == "Meter:   Damage")
for _, o in ipairs(w.options) do assert(not o:find("Number", 1, true), o) end
assert(next(m:changes()) == nil, "nothing changed")

-- Opponent 2: the kinds, then None, then Back; the cursor on its opponent's kind and name.
m:choose(2)
w = check(m:window())
assert(w.screen == "sections" and w.options[#w.options - 1] == "None" and w.options[#w.options] == "Back")
assert(w.body:find("^Opponent 2: kind of enemy\nNow: ") and w.focus == 1, w.body .. " / " .. w.focus)
m:choose(1) -- Machines
w = check(m:window())
assert(w.screen == "names" and w.focus == 1, "not the kind of " .. name("o2") .. ": the first")
m:choose(0) -- o4
w = check(m:window())
assert(w.screen == "main" and w.focus == 3 and w.options[3] == "Opponent 2:   " .. name("o4"), w.options[3])
local c = m:changes()
assert(c.group and table.concat(c.group, ",") == "o2,o4,o7" and c.mode == nil and c.opponent == nil and c.count == nil)
m:choose(2)
assert(check(m:window()).focus == 2, "on Machines now")
m:choose(1)
assert(check(m:window()).focus == 1, "on " .. name("o4"))
m:choose(-1); m:choose(-1)

-- None in Opponent 2: the third moves up, the third is None.
m:choose(2); m:choose(#m.sections) -- None
w = check(m:window())
assert(w.options[3] == "Opponent 2:   " .. name("o7") and w.options[4] == "Opponent 3:   None", w.options[3] .. " / " .. w.options[4])
assert(table.concat(m:changes().group, ",") == "o2,o7")
-- Opponent 3 while it is None: its list starts where the row above is (Beasts, its range and name), and says Now: None.
m:choose(3)
w = check(m:window())
assert(w.body:find("Now: None", 1, true) and w.focus == 3, w.body)
m:choose(2) -- Beasts: its ranges, on the one holding o7
w = check(m:window())
assert(w.screen == "ranges" and w.focus == 1)
m:choose(0)
w = check(m:window())
assert(w.screen == "names" and w.options[w.focus] == name("o7"), "another copy is a confirm away")
m:choose(w.focus - 1)
w = check(m:window())
assert(w.options[4] == "Opponent 3:   " .. name("o7") and w.focus == 4)
assert(table.concat(m:changes().group, ",") == "o2,o7,o7")
-- Opponent 1 has no None.
m:choose(1)
assert(check(m:window()).options[#m.sections + 1] == "Back")
m:choose(-1)
assert(m.screen == "main" and m.row == 2, "Back on the kinds: the main window, on the row")

-- Opponent 3 with Opponent 2 None is picked as Opponent 2 (no gaps).
m:reset({ active = true, group = { "o1" }, behaviour = "passive", difficulty = "normal" })
assert(check(m:window()).options[3] == "Opponent 2:   None")
m:choose(3) -- Opponent 3
assert(m:window().body:find("^Opponent 2:"), "picked as the second")
m:choose(0); m:choose(2) -- Humans, o3
w = check(m:window())
assert(w.options[3] == "Opponent 2:   " .. name("o3") and w.options[4] == "Opponent 3:   None" and w.focus == 3)

-- An opponent capped at one copy: a second copy is refused, the names window says so, once.
m:reset({ active = true, group = { "o6" }, behaviour = "passive", difficulty = "normal" })
m:choose(2); m:choose(1); m:choose(2) -- Opponent 2, Machines, o6
w = check(m:window())
assert(w.screen == "names" and w.body:find("At most 1 " .. name("o6") .. " at a time", 1, true), w.body)
assert(not check(m:window()).body:find("At most", 1, true), "said once")
m:choose(0) -- o4 is fine
assert(m.screen == "main" and table.concat(m:changes().group, ",") == "o6,o4")
-- Two opponents Custom Training can't put in one group: the second is refused with both names.
m:reset({ active = true, group = { "o4" }, behaviour = "passive", difficulty = "normal" })
m:choose(2); m:choose(2); m:choose(0); m:choose(1) -- Opponent 2, Beasts, its first range, o8
w = check(m:window())
assert(w.screen == "names" and w.body:find(name("o8") .. " can't fight beside " .. name("o4"), 1, true), w.body)
m:choose(2) -- o9 is fine
assert(m.screen == "main" and table.concat(m:changes().group, ",") == "o4,o9")
-- Three copies of a three-copy opponent, but not four (there are three rows).
m:reset({ active = true, group = { "o1", "o1", "o1" }, behaviour = "passive", difficulty = "normal" })
assert(m:window().options[4] == "Opponent 3:   " .. name("o1"))
-- A state with opponent and count only (no group) reads as that many copies.
m:reset({ active = true, opponent = "o5", count = 2, behaviour = "passive", difficulty = "normal" })
w = m:window()
assert(w.options[2]:find(name("o5"), 1, true) and w.options[3]:find(name("o5"), 1, true) and w.options[4] == "Opponent 3:   None")
assert(next(m:changes()) == nil, "the same group: nothing to hand over")

-- Mode: Opponents / Round; Round mode has one Round row instead of the opponent rows.
m:reset(state)
m:choose(0)
w = check(m:window())
assert(w.screen == "values" and w.options[1] == "Opponents" and w.options[2] == "Round" and w.options[3] == "Back" and w.focus == 1)
m:choose(1)
w = check(m:window())
assert(#w.options == 9 and w.options[1] == "Mode:   Round" and w.options[2]:find("^Round:   Titan %- Round 1$"), w.options[2])
assert(w.options[3] == "Behaviour:   Passive" and w.focus == 1)
-- Round: the tabs with courses, in the simulator's order; the cursor on the tab of the round set.
m:choose(1)
w = check(m:window())
assert(w.screen == "tabs" and table.concat(w.options, ",") == "Summons,Regions,Brutal,Back" and w.focus == 1, table.concat(w.options, ","))
assert(w.body == "Round: simulator tab\nNow: Titan, round 1", w.body)
m:choose(2) -- Brutal: one course
w = check(m:window())
assert(w.screen == "courses" and w.options[1] == "Brutal Challenge: Ultimate Party Animal" and w.focus == 1)
m:choose(0) -- 15 rounds: two windows of rounds
w = check(m:window())
assert(w.screen == "round_ranges" and w.options[1] == "Rounds 1 - 8" and w.options[2] == "Rounds 9 - 15", w.options[1])
m:choose(0)
w = check(m:window())
assert(w.screen == "rounds" and #w.options == 8 + 1 and w.options[2] == "Round 2: 2 Cerulean Drake, Sandworm", w.options[2])
assert(#w.options[4] <= model.ROW_CHARS and w.options[4]:find("^Round 4: 2 "), w.options[4])
m:choose(1) -- Round 2
w = check(m:window())
assert(w.screen == "main" and w.focus == 2 and w.options[2] == "Round:   Brutal Challenge: Ultimate... - Round 2", w.options[2])
assert(#w.options[2] <= model.MAIN_CHARS)
c = m:changes()
assert(c.mode == "round" and c.round == "c3r2" and c.group == nil, "mode and round")
-- Opening the round list again: the cursor on Brutal, its course, its rounds window and the round.
m:choose(1)
assert(check(m:window()).focus == 3)
m:choose(2); m:choose(0)
assert(check(m:window()).focus == 1)
m:choose(0)
assert(check(m:window()).focus == 2)
m:choose(-1); m:choose(-1); m:choose(-1); m:choose(-1); m:choose(-1)
assert(m.screen == "main" and m.row == 2, "Back all the way: the main window, on Round")
-- Regions has 14 courses: two windows of them.
m:choose(1); m:choose(1)
w = check(m:window())
assert(w.screen == "course_ranges" and #w.options == 2 + 1 and w.options[1] == "Course 01  -  Course 07", w.options[1])
m:choose(1)
w = check(m:window())
assert(w.screen == "courses" and #w.options == 7 + 1 and w.options[1] == "Region Course 08")
m:choose(-1); assert(m.screen == "course_ranges")
m:choose(-1); assert(m.screen == "tabs")
m:choose(-1); assert(m.screen == "main")

-- A course in Round mode: the draft starts there; Opponents again hands the mode and the group over.
local rstate = { active = true, mode = "round", course = "c1", round = "c2r1", group = { "o1" }, behaviour = "healing", difficulty = "hard" }
m:reset(rstate)
w = check(m:window())
assert(w.options[1] == "Mode:   Round" and w.options[2] == "Round:   Phoenix - Round 1" and next(m:changes()) == nil, w.options[2])
m:choose(0); m:choose(0) -- Opponents
w = check(m:window())
assert(w.options[2] == "Opponent 1:   " .. name("o1") and w.focus == 1)
c = m:changes()
assert(c.mode == "opponents" and table.concat(c.group, ",") == "o1" and c.round == nil)

-- Without courses there is no Mode row; without group_max, Opponent and Number as before.
local plain = lists(); plain.courses = nil
local mp = model.new(plain, state)
assert(mp:window().options[1]:find("^Opponent 1:") and #mp:window().options == 7)
local old = lists(); old.courses = nil; old.group_max = nil
local mo = model.new(old, { active = true, opponent = "o2", count = 2, behaviour = "passive", difficulty = "normal" })
assert(mo:window().options[1]:find("^Opponent:") and mo:window().options[2] == "Number:   2")

-- set() (development screenshots).
m:reset(state)
m:set({ opponent2 = "none" })
assert(table.concat(m:changes().group, ",") == "o2,o7")
m:set({ opponent1 = "o5", opponent2 = "o6", opponent3 = "o150" })
assert(table.concat(m:changes().group, ",") == "o5,o6,o150")
m:set({ mode = "round", round = "c3r15" })
assert(m:window().options[2] == "Round:   Brutal Challenge: Ultimate... - Round 15", m:window().options[2])

-- Rounds' labels: the round's name and its enemies, count first (no "×" in the window); whole when they fit, cut to the
-- row otherwise.
assert(model.round_label({ number = 2, enemies = { { name = "Cerulean Drake", count = 2 }, { name = "Sandworm", count = 1 } } })
       == "Round 2: 2 Cerulean Drake, Sandworm")
assert(model.round_label({ number = 1, name = "Round 1", enemies = "Wererat \195\151" .. "2, Elphadunk \195\151" .. "2" })
       == "Round 1: 2 Wererat, 2 Elphadunk")
assert(model.round_label({ number = 3, name = "Round 3", enemies = "Gi Nattak, Bandit x3" }) == "Round 3: Gi Nattak, 3 Bandit")
assert(model.round_label({ number = 1, name = "Round 1",
                           enemies_list = { { name = "Sandworm", count = 1 } }, enemies = "ignored" }) == "Round 1: Sandworm")
for _, n in ipairs({ 1, 3, 6 }) do
    local enemies = {}
    for i = 1, n do enemies[i] = { name = string.rep("Longname", 3) .. i, count = 1 } end
    local label = model.round_label({ number = 12, enemies = enemies })
    assert(#label <= model.ROW_CHARS and label:find("^Round 12: "), label)
end

-- ui_ct: the development files' new lines.
local s = ct.parse_state("what=change\nactive=true\nmode=round\ngroup=o1,o1,o7\ncourse=c3\nround=c3r2\nbehaviour=passive\n")
assert(s.mode == "round" and #s.group == 3 and s.group[3] == "o7" and s.round == "c3r2")
assert(ct.parse_state("what=change\nactive=true\ngroup=o1\n").group[1] == "o1")
-- Custom Training's lines (agreed 2026-11-21): course id tab tab_name name; round course_id round_id number size name
-- enemies; conflict id id; group_max n.
local l = ct.parse_lists(table.concat({
    "opponent\to1\t1\tHumans\t3\tBandit", "opponent\to2\t3\tBeasts\t3\tWererat",
    "behaviour\tpassive\tPassive", "difficulty\tnormal\tNormal", "max_count\t3", "group_max\t3",
    "conflict\to1\to2",
    "course\tc1\t1\tSummons\tTitan", "course\tc3\t5\tBrutal\tBrutal Challenge",
    "round\tc1\tc1r1\t1\t1\tRound 1\tTitan \195\151" .. "1", "round\tc3\tc3r2\t2\t3\tRound 2\tCerulean Drake \195\151" .. "2, Sandworm \195\151" .. "1",
    "round\tc3\tc3r3\t3\t1\tRound 3\tSandworm", "" }, "\n"))
assert(l.group_max == 3 and #l.courses == 2 and #l.courses[2].rounds == 2 and l.courses[2].tab_name == "Brutal")
assert(l.courses[2].rounds[1].size == 3 and l.conflicts[1][2] == "o2")
local lm = model.new(l, { active = true, opponent = "o1", count = 1, behaviour = "passive", difficulty = "normal" })
assert(lm:window().options[1] == "Mode:   Opponents" and lm:window().options[2] == "Opponent 1:   Bandit")
assert(model.round_label(l.courses[2].rounds[1]) == "Round 2: 2 Cerulean Drake, Sandworm")
lm:choose(0); lm:choose(1); lm:choose(1)
assert(table.concat(lm:window().options, ",") == "Summons,Brutal,Back", "tabs by tab_name")
assert(ct.format_set({ group = { "o1", "o1", "o7" }, mode = "opponents" }) == "set group=o1,o1,o7 mode=opponents\n")

print("groups ok")
