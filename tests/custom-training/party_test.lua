local party = require("ct_party")
local function M(id, hp, max) return { id = id, hp = hp, max = max or 1000 } end
local function has(actions, id, action)
    for _, a in ipairs(actions) do if a.id == id and a.action == action then return true end end
    return false
end

local p = party.new()
-- Healing: everyone goes to 1% at once
local a = p:step({ M("Cloud", 1000), M("Aerith", 800) }, "healing", 0)
assert(has(a, "Cloud", "low") and has(a, "Aerith", "low"), "patients set low")
a = p:step({ M("Cloud", 10), M("Aerith", 8) }, "healing", 0.2)
assert(#a == 0, "floor read")
-- a heal: left on the bar for 1.5 s, then dropped back
a = p:step({ M("Cloud", 400), M("Aerith", 8) }, "healing", 1.0)
assert(#a == 0, "heal shown")
a = p:step({ M("Cloud", 400), M("Aerith", 8) }, "healing", 2.0)
assert(#a == 0, "still shown")
a = p:step({ M("Cloud", 400), M("Aerith", 8) }, "healing", 2.6)
assert(has(a, "Cloud", "low") and #a == 1, "dropped back")
-- out of Healing: patients refilled
a = p:step({ M("Cloud", 10), M("Aerith", 8) }, "passive", 3.0)
assert(has(a, "Cloud", "full") and has(a, "Aerith", "full"), "restored")
a = p:step({ M("Cloud", 1000), M("Aerith", 800) }, "passive", 3.2)
assert(#a == 0, "passive does nothing")
-- Aggressive: no HP refill (owner 2026-11-21: Auto-Life is enough)
a = p:step({ M("Cloud", 400), M("Aerith", 800) }, "aggressive", 4)
assert(#a == 0, "no refill below half")
-- KO'd members are left alone
a = p:step({ M("Cloud", 0) }, "aggressive", 5)
assert(#a == 0, "KO left alone")
-- restore() for the end of the course
p = party.new(); p:step({ M("Tifa", 900) }, "healing", 0)
a = p:restore({ M("Tifa", 9) })
assert(has(a, "Tifa", "full"), "restore at the end")
-- Passive refills a member below half (owner 2026-11-21: everything refilled there); Aggressive never
p = party.new()
a = p:step({ M("Cloud", 400) }, "passive", 10)
assert(has(a, "Cloud", "full"), "Passive refills below half")
a = p:step({ M("Cloud", 400) }, "aggressive", 11)
assert(#a == 0, "Aggressive does not")
