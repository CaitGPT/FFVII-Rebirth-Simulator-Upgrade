-- ui_model: the main window, the value lists, the opponent list (kinds, ranges, names), what is handed over.
package.loaded["ui_model"] = nil
local model = require("ui_model")

-- Humans 3, Machines 3 (the third capped at one copy), Beasts 30, Anomalies 150 (more than PAGE x PAGE).
local function lists()
    local opponents = {}
    local kinds = { { "Humans", 3 }, { "Machines", 3 }, { "Beasts", 30 }, { "Anomalies", 150 } }
    local n = 0
    for k, def in ipairs(kinds) do
        for i = 1, def[2] do
            n = n + 1
            local letter = string.char(string.byte("A") + math.floor((i - 1) * 26 / def[2]))
            opponents[#opponents + 1] = { id = "o" .. n, name = letter .. " " .. def[1] .. " " .. i, kind = k,
                                          kind_name = def[1], max_count = (k == 2 and i == 3) and 1 or nil,
                                          boss = (k == 2 and i == 2) } -- boss: what Custom Training used to send
        end
    end
    return {
        opponents = opponents,
        behaviours = { { id = "passive", name = "Passive" }, { id = "aggressive", name = "Aggressive" }, { id = "healing", name = "Healing" } },
        difficulties = { { id = "easy", name = "Easy" }, { id = "normal", name = "Normal" }, { id = "dynamic", name = "Dynamic" }, { id = "hard", name = "Hard" } },
        max_count = 3,
    }
end

local state = { active = true, opponent = "o2", count = 2, behaviour = "passive", difficulty = "normal" }
local m = model.new(lists(), state)

-- No window has more than 13 rows.
local function check(w)
    assert(#w.options <= model.PAGE + 1, w.screen .. " has " .. #w.options .. " rows")
    assert(w.focus >= 1 and w.focus <= #w.options, w.screen .. " focus " .. tostring(w.focus))
    return w
end

-- The main window shows the current settings.
local w = check(m:window())
assert(w.screen == "main" and #w.options == 6)
assert(w.options[1]:match("^Opponent:   %u Humans 2$"), w.options[1])
assert(w.options[2] == "Number:   2" and w.options[3] == "Behaviour:   Passive" and w.options[4] == "Difficulty:   Normal")
assert(w.options[5] == "Apply" and w.options[6] == "Cancel")
assert(w.body:find("<button=decide>", 1, true), "the game draws the confirm button's icon")

-- Nothing changed: Apply hands nothing over.
local r = m:choose(4)
assert(r.kind == "apply" and next(r.changes) == nil and #r.meters == 0)

-- A value list: Behaviour, with the cursor on the current value; choosing one comes back to the same row.
m:reset(state)
assert(m:choose(2).kind == "show" and m.screen == "values")
w = check(m:window())
assert(w.body:find("^Behaviour\nNow: ") and w.options[1] == "Passive" and w.options[4] == "Back" and w.focus == 1)
m:choose(2) -- Healing
w = check(m:window())
assert(w.screen == "main" and w.focus == 3 and w.options[3] == "Behaviour:   Healing", w.options[3])
-- Back changes nothing.
m:choose(1); m:choose(3)
assert(m:window().options[2] == "Number:   2", "Back keeps the value")
m:choose(1); m:choose(2) -- Number 3
m:choose(3); m:choose(3) -- Difficulty Hard
r = m:choose(4)
assert(r.kind == "apply" and r.changes.count == 3 and r.changes.behaviour == "healing" and r.changes.difficulty == "hard"
    and r.changes.opponent == nil)
-- Cancel and a cancelled window close.
m:reset(state)
assert(m:choose(5).kind == "close" and m:choose(-1).kind == "close" and m:choose(nil).kind == "close")

-- The opponent list: the kinds, the large one in two parts by letter.
m:reset(state)
assert(m:choose(0).kind == "show" and m.screen == "sections")
w = check(m:window())
assert(w.options[1] == "Humans" and w.options[3] == "Beasts", w.options[3])
assert(w.options[4]:match("^Anomalies %(A%-%a%)$") and w.options[5]:match("^Anomalies %(%a%-Z%)$"), w.options[4] .. " / " .. w.options[5])
assert(w.options[6] == "Back" and w.focus == 1, "focus on the current kind")
-- A small kind goes straight to its names.
m:choose(0)
w = check(m:window())
assert(w.screen == "names" and #w.options == 4 and w.focus == 2 and w.options[4] == "Back")
m:choose(3) -- Back
assert(m.screen == "sections")
-- Beasts (30): ranges of at most 12, then names.
m:choose(2)
w = check(m:window())
assert(w.screen == "ranges" and #w.options == 3 + 1, #w.options)
assert(w.options[1]:find("  -  ", 1, true), w.options[1])
m:choose(1)
w = check(m:window())
assert(w.screen == "names" and #w.options == 10 + 1, #w.options)
m:choose(#w.options - 1) -- Back to the ranges
assert(m.screen == "ranges")
m:choose(3) -- Back to the kinds
assert(m.screen == "sections")
-- Anomalies, second part: 75 names in 7 ranges.
m:choose(4)
w = check(m:window())
assert(w.screen == "ranges" and #w.options == 7 + 1, #w.options)
m:choose(6)
w = check(m:window())
local pick = w.options[2]
m:choose(1)
w = check(m:window())
assert(w.screen == "main" and w.focus == 1 and w.options[1] == "Opponent:   " .. pick, w.options[1])
-- Opening the list again puts the cursor on that kind part and range.
m:choose(0)
assert(check(m:window()).focus == 5)
m:choose(4)
assert(check(m:window()).focus == 7)
m:choose(6)
assert(check(m:window()).focus == 2)
m:choose(-1); m:choose(-1); m:choose(-1)
assert(m.screen == "main", m.screen)

-- No "(boss)" anywhere, and one to three copies of anyone (owner, 2026-11-21): a boss flag still sent is ignored.
m:reset(state)
m:set({ opponent = "o5", count = 3 })
assert(m:row_text("opponent") == "Opponent:   " .. m:opponent().name and m:row_text("count") == "Number:   3")
m:choose(1); assert(m.screen == "values" and #check(m:window()).options == 3 + 1, "1, 2, 3 and Back")
m:choose(-1)
m:choose(0); m:choose(1) -- Machines: its names
for _, o in ipairs(check(m:window()).options) do assert(not o:find("boss", 1, true), o) end
m:choose(-1); m:choose(-1)
-- An opponent Custom Training still caps at one copy: Number reads "1" and opens no list; a count of 3 asked for
-- before is handed over as 1.
m:reset(state)
m:set({ count = 3 })
m:set({ opponent = "o6" })
assert(m:row_text("count") == "Number:   1", m:row_text("count"))
assert(m:choose(1).kind == "show" and m.screen == "main", "Number on a capped opponent stays on the main window")
assert(m:changes().count == 1, "the course had 2: handed over as 1")
-- A cap of 2: Number offers 1 and 2; 3 asked for before reads and is handed over as 2.
m.lists.opponents[5].max_count = 2
m:reset(state)
m:set({ count = 3 })
m:set({ opponent = "o5" })
assert(m:row_text("count") == "Number:   2", m:row_text("count"))
m:choose(1); assert(m.screen == "values" and #check(m:window()).options == 2 + 1, "1, 2 and Back")
m:choose(-1)
assert(m:changes().count == nil, "the course had 2")
m.lists.opponents[5].max_count = nil

-- Long names in ranges are cut.
local long = lists()
for i = 1, 30 do long.opponents[6 + i].name = "Extraordinarily Long Beast Name " .. i end
local ml = model.new(long, state)
ml:choose(0); ml:choose(2)
w = check(ml:window())
assert(w.options[1] == "Extraordinarily...  -  Extraordinarily...", w.options[1])
-- Whole when both fit the row; otherwise the longer one gives way, and no label is longer than the row.
assert(model.range_label("Citripine Schoolmaster", "Death Claw") == "Citripine Schoolmaster  -  Death Claw")
assert(model.range_label("Junon Elite Security Officer", "Special Forces Operator") == "Junon Elite...  -  Special Forces Operator",
       model.range_label("Junon Elite Security Officer", "Special Forces Operator"))
for _, pair in ipairs({ { "Bandit", "Elite Grenadier (Junon Ver1 Another Voice)" }, { string.rep("x", 60), string.rep("y", 60) },
                        { "Junon Elite Security Officer", "2-C SOLDIER Operator" } }) do
    local label = model.range_label(pair[1], pair[2])
    assert(#label <= model.ROW_CHARS, label)
end

-- Every kind part and every range fits in one window (the full list's sizes).
for _, size in ipairs({ 1, 12, 13, 144, 145, 155, 240, 300 }) do
    local parts = model.split({ table.unpack((function() local t = {} for i = 1, size do t[i] = i end return t end)()) }, model.PAGE * model.PAGE)
    for _, p in ipairs(parts) do
        assert(#model.split(p, model.PAGE) <= model.PAGE, size .. ": " .. #model.split(p, model.PAGE) .. " ranges")
    end
end
print("model ok")

-- set(): draft values by id (development screenshots).
local m2 = model.new(lists(), state)
m2:set({ opponent = "o7", count = "3", behaviour = "healing", difficulty = "hard" })
assert(m2:opponent().id == "o7" and m2.draft.count == 3)
assert(m2:row_text("behaviour") == "Behaviour:   Healing" and m2:row_text("difficulty") == "Difficulty:   Hard")
m2:set({ opponent = "nope", count = 9 })
assert(m2:opponent().id == "o7" and m2.draft.count == 3, "unknown ids and counts out of range are ignored or clamped")
print("model set ok")
