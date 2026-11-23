local model = require("ct_panel_model")
local list = {
    { id = "b2", category = 3, name = "Zu" }, { id = "h1", category = 1, name = "Soldier" },
    { id = "b1", category = 3, name = "Ark Dragon" }, { id = "s1", category = 5, name = "Titan" },
    { id = "h2", category = 1, name = "Bandit" },
}
local settings = { opponent = "b1", behaviour = "passive", difficulty = "normal", count = 1 }
local p = model.new(list, {})
assert(p.list[1].name == "Bandit" and p.list[3].name == "Ark Dragon" and p.list[5].name == "Titan", "sorted by kind then name")
p:show(settings)
local v = p:view()
assert(#v.sections == 4 and v.sections[1].focused and v.sections[1].cells[2].text == "Ark Dragon", "opens on the current enemy")
assert(v.sections[1].cells[1].text == "Soldier" and v.sections[1].cells[3].text == "Zu", "neighbours")
assert(v.sections[1].note:find("Beasts", 1, true), "kind shown")
assert(not v.footer:find("Equipment", 1, true), "no equipment entry")
p:press("right", settings)
assert(p:view().sections[1].cells[2].text == "Zu", "right cycles")
p:press("next_kind", settings)
assert(p:view().sections[1].cells[2].text == "Titan", "next kind")
p:press("prev_kind", settings)
assert(p:view().sections[1].cells[2].text == "Ark Dragon", "previous kind goes to its start")
p:press("down", settings); p:press("right", settings)                   -- behaviour -> aggressive
p:press("down", settings); p:press("right", settings); p:press("right", settings) -- difficulty normal -> hard
p:press("down", settings); p:press("left", settings)                    -- quantity 1 -> 3 (wraps)
v = p:view()
assert(v.sections[4].focused and v.sections[4].cells[1].text == "3", "quantity wraps")
assert(v.sections[3].cells[4].selected, "hard selected")
local r = p:press("select", settings)
assert(r.kind == "apply" and r.changes.behaviour == "aggressive" and r.changes.difficulty == "hard" and r.changes.count == 3, "apply")
assert(r.changes.opponent == nil, "unchanged opponent not reported")
assert(not p.open, "closed after apply")
-- back discards
p:show(settings); p:press("right", settings)
r = p:press("back", settings)
assert(r.kind == "close", "back closes")
-- up wraps to the last section
p:show(settings); p:press("up", settings)
assert(p:view().sections[4].focused, "up wraps")
-- difficulty limited
local q = model.new(list, { difficulties = { normal = true } })
q:show(settings); q:press("down", settings); q:press("down", settings); q:press("right", settings)
assert(#q:view().sections[3].cells == 1 and q.draft.difficulty == "normal", "only allowed difficulties")
-- healing is the third behaviour; no "boss" tag; a capped opponent shows its cap and can't go above it
local h = model.new({ { id = "k", category = 3, name = "King", boss = true }, { id = "c", category = 3, name = "Capped", max_count = 1 } }, {})
h:show({ opponent = "k", behaviour = "aggressive", difficulty = "normal", count = 3 })
h:press("down", settings); h:press("right", settings)
assert(h:view().sections[2].cells[3].selected and h.draft.behaviour == "healing", "healing")
assert(h:view().sections[4].cells[1].text == "3", "a former boss comes 3: " .. h:view().sections[4].cells[1].text)
h:show({ opponent = "c", behaviour = "aggressive", difficulty = "normal", count = 3 })
assert(h:view().sections[4].cells[1].text == "1", "a capped one shows its cap")
h:press("down", settings); h:press("down", settings); h:press("down", settings); h:press("right", settings)
assert(h:view().sections[4].cells[1].text == "1", "and stays there")

-- input: arming, edges, repeat
local input = require("ct_input")
local i = input.new()
assert(#i:poll({ Gamepad_LeftShoulder = true, Gamepad_RightShoulder = true }, 0) == 0, "not armed while the chord is held")
assert(#i:poll({}, 0.05) == 0, "arms on release")
local k = i:poll({ Gamepad_DPad_Down = true }, 0.1)
assert(#k == 1 and k[1] == "down", "press")
assert(#i:poll({ Gamepad_DPad_Down = true }, 0.2) == 0, "held, no repeat yet")
k = i:poll({ Gamepad_DPad_Down = true }, 0.55)
assert(#k == 1 and k[1] == "down", "repeat after 0.4 s")
assert(#i:poll({ Gamepad_FaceButton_Bottom = true }, 0.6) == 1, "select")
assert(#i:poll({ Gamepad_FaceButton_Bottom = true }, 1.5) == 0, "select does not repeat")
k = i:poll({ Gamepad_RightShoulder = true }, 1.6)
assert(k[1] == "right", "RB cycles right")
assert(input.chord({ Gamepad_LeftShoulder = true, Gamepad_RightShoulder = true }) and not input.chord({ Gamepad_LeftShoulder = true }), "chord")
assert(#input.all_keys() > 20, "keys listed")

-- With the meters part: the meter shown and a tool, sent on Select
local m = model.new(list, { meters = true })
m:show(settings, { meter = "heal", visible = true })
v = m:view()
assert(#v.sections == 6 and v.sections[5].cells[3].selected and v.sections[6].cells[1].selected, "meters sections")
assert(v.footer:find("Enter", 1, true) and v.footer:find("Esc", 1, true), "keyboard keys in the footer")
m:press("up", settings); m:press("up", settings); m:press("right", settings) -- meter: heal -> hidden
r = m:press("select", settings)
assert(#r.meters == 1 and r.meters[1] == "hide", "hide")
m:show(settings, { meter = "damage", visible = false })
m:press("up", settings); m:press("up", settings); m:press("left", settings) -- hidden -> heal
m:press("down", settings); m:press("right", settings)                     -- tool: clear
r = m:press("select", settings)
assert(r.meters[1] == "meter=heal" and r.meters[2] == "show" and r.meters[3] == "clear", table.concat(r.meters, ","))
