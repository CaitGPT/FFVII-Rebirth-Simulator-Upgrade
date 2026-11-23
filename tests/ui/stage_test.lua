-- ui_model on a stage (owner 2026-11-21: every stage is offered; what needs more room than the stage loaded can't be
-- chosen): the stage in the main window's text, entries that need more room marked, refused when confirmed with the
-- stage named; on the plain arena nothing marked. Also ui_ct's needs_m fields.
for _, m in ipairs({ "ui_model", "ui_ct" }) do package.loaded[m] = nil end
local model = require("ui_model")
local ct = require("ui_ct")

local function lists()
    return {
        opponents = {
            { id = "bandit", name = "Bandit", kind = 1, kind_name = "Humans", needs_m = 12 },
            { id = "ogre", name = "Ogre", kind = 3, kind_name = "Beasts", needs_m = 24 },
            { id = "alex", name = "Alexander", kind = 5, kind_name = "Summons and others", needs_m = 40 },
            { id = "long", name = "Elite Grenadier (Junon Ver1 Another Voice) Long", kind = 1, kind_name = "Humans", needs_m = 30 },
            { id = "wolf", name = "Wolf", kind = 3, kind_name = "Beasts", needs_m = 20 },
        },
        behaviours = { { id = "passive", name = "Passive" } },
        difficulties = { { id = "normal", name = "Normal" } },
        max_count = 3, group_max = 3,
        courses = {
            { id = "c1", tab = 1, tab_name = "Summons", name = "Alexander", rounds = {
                { id = "c1r1", number = 1, name = "Round 1", enemies = "Alexander", needs_m = 40 },
                { id = "c1r2", number = 2, name = "Round 2", needs_m = 12, enemies = "Bandit \195\151" .. "2, Elite Grenadier (Junon Ver1 Another Voice)" },
            } },
        },
    }
end
local stage = { active = true, group = { "bandit" }, behaviour = "passive", difficulty = "normal",
                stage_name = "Cave of the Gi", room_m = 25, needs_m = 12 }
local m = model.new(lists(), stage)

-- The main window says the stage.
local w = m:window()
assert(w.body == "Custom Training\nStage: Cave of the Gi\n<button=decide> Change a setting, then Apply", w.body)
-- Humans' names: the Grenadier needs 30 m on a 25 m stage, marked and cut to fit; Bandit isn't.
m:choose(m:index("opponent2") - 1); m:choose(0)
w = m:window()
assert(w.options[1] == "Bandit", w.options[1])
assert(w.options[2]:find(" %(larger stage%)$") and #w.options[2] <= model.ROW_CHARS, w.options[2])
-- Confirming it: refused, the window stays and says why, once.
m:choose(1)
w = m:window()
assert(m.screen == "names" and w.body:find("Needs a larger stage than Cave of the Gi", 1, true), w.body)
assert(not m:window().body:find("Needs", 1, true), "said once")
-- Beasts (the kinds: Humans, Beasts, Summons). A group needs the most any member needs plus 2 m for each enemy beyond
-- the first: beside the Bandit, the Ogre (24 m) needs 26 m, marked; the Wolf (20 m) needs 22, fine.
m:choose(-1); m:choose(1)
w = m:window()
assert(w.options[1] == "Ogre (larger stage)" and w.options[2] == "Wolf", w.options[1] .. " / " .. w.options[2])
m:choose(1)
assert(m.screen == "main" and table.concat(m:changes().group, ",") == "bandit,wolf")
-- The third row: a second Wolf needs 24 m (fits); the Ogre 28.
m:choose(m:index("opponent3") - 1); m:choose(1)
w = m:window()
assert(w.options[1] == "Ogre (larger stage)" and w.options[2] == "Wolf")
m:choose(1)
assert(table.concat(m:changes().group, ",") == "bandit,wolf,wolf")
-- Alone, the Ogre fits (24 m on 25): Opponent 1 with the other rows None.
m:set({ opponent2 = "none", opponent3 = "none" })
m:choose(m:index("opponent1") - 1); m:choose(1)
assert(m:window().options[1] == "Ogre", m:window().options[1])
m:choose(0)
assert(table.concat(m:changes().group, ",") == "ogre")
-- A round that needs more room: marked and refused; one that fits is picked.
m:set({ mode = "round" })
m:choose(m:index("round") - 1); m:choose(0); m:choose(0)
w = m:window()
assert(w.options[1] == "Round 1: Alexander (larger stage)" and not w.options[2]:find("larger", 1, true), w.options[1])
assert(#w.options[2] <= model.ROW_CHARS, w.options[2])
m:choose(0)
assert(m.screen == "rounds" and m:window().body:find("Needs a larger stage than Cave of the Gi", 1, true))
m:choose(1)
assert(m.screen == "main" and m:changes().round == "c1r2")
-- A pick made before the stage changed: its main-window row is marked too.
m:reset({ active = true, group = { "alex" }, behaviour = "passive", difficulty = "normal", stage_name = "Cave of the Gi", room_m = 25, needs_m = 12 })
assert(m:window().options[m:index("opponent1")] == "Opponent 1:   Alexander (larger stage)", m:window().options[2])
m:reset({ active = true, mode = "round", round = "c1r1", behaviour = "passive", difficulty = "normal", stage_name = "Cave of the Gi", room_m = 25, needs_m = 12 })
assert(m:window().options[m:index("round")]:find("Round 1 %(larger stage%)$"), m:window().options[2])
assert(#m:window().options[m:index("round")] <= model.ROW_CHARS + 2) -- "Round:   " + 35

-- The plain arena: nothing marked, no stage line, nothing refused.
local plain = model.new(lists(), { active = true, group = { "bandit" }, behaviour = "passive", difficulty = "normal" })
assert(not plain:window().body:find("Stage", 1, true))
plain:choose(plain:index("opponent1") - 1); plain:choose(0)
for _, o in ipairs(plain:window().options) do assert(not o:find("larger", 1, true), o) end
plain:choose(1)
assert(plain.screen == "main", "picked")
-- A stage with no room given: nothing marked either.
local unknown = model.new(lists(), { active = true, group = { "alex" }, behaviour = "passive", difficulty = "normal", stage_name = "Somewhere", needs_m = 40 })
assert(unknown:window().options[2] == "Opponent 1:   Alexander" and unknown:window().body:find("Stage: Somewhere", 1, true))

-- ui_ct: needs_m in the opponent (field 7) and round (field 8) lines; stage_name and room_m in the course file.
local l = ct.parse_lists(table.concat({
    "opponent\tbandit\t1\tHumans\t3\tBandit\t", "opponent\talex\t5\tSummons\t1\tAlexander\t40",
    "behaviour\tpassive\tPassive", "group_max\t3",
    "course\tc1\t1\tSummons\tAlexander", "round\tc1\tc1r1\t1\t1\tRound 1\tAlexander\t40", "round\tc1\tc1r2\t2\t2\tRound 2\tBandit \195\151" .. "2", "" }, "\n"))
assert(l.opponents[1].needs_m == nil and l.opponents[2].needs_m == 40)
assert(l.courses[1].rounds[1].needs_m == 40 and l.courses[1].rounds[2].needs_m == nil)
local s = ct.parse_state("what=change\nactive=true\nstage_name=Cave of the Gi\nroom_m=25\n")
assert(s.stage_name == "Cave of the Gi" and s.room_m == 25)

print("stage ok")
