local plan = require("ct_plan")
local function E(key, spec) return { key = key, spec = spec } end

-- course start: one copy of the first opponent; the player wants 2 Orcs
local r = plan.plan({ E("a", "Rat") }, { spec = "Orc", count = 2 }, 0, { a = true })
assert(r.spawn == 2 and #r.remove == 0, "spawn first, keep the old one until a new one is there")
-- one spawn asked for and pending: only one more
r = plan.plan({ E("a", "Rat") }, { spec = "Orc", count = 2 }, 1, { a = true })
assert(r.spawn == 1, "pending counts")
-- the new ones are there: remove the stale one
r = plan.plan({ E("a", "Rat"), E("b", "Orc"), E("c", "Orc") }, { spec = "Orc", count = 2 }, 0, { a = true })
assert(r.spawn == 0 and #r.remove == 1 and r.remove[1] == "a", "remove stale")
-- count down, not stale: extras go
r = plan.plan({ E("b", "Orc"), E("c", "Orc"), E("d", "Orc") }, { spec = "Orc", count = 1 }, 0, {})
assert(r.spawn == 0 and #r.remove == 2, "count down")
-- count up
r = plan.plan({ E("b", "Orc") }, { spec = "Orc", count = 3 }, 0, {})
assert(r.spawn == 2 and #r.remove == 0, "count up")
-- adds an opponent summons are left alone
r = plan.plan({ E("b", "TonberryKing"), E("m", "Minion") }, { spec = "TonberryKing", count = 1 }, 0, {})
assert(r.spawn == 0 and #r.remove == 0, "adds stay")
-- same opponent again after a difficulty change: the stale copies are replaced too
r = plan.plan({ E("b", "Orc"), E("n", "Orc") }, { spec = "Orc", count = 1 }, 0, { b = true })
assert(r.spawn == 0 and #r.remove == 1 and r.remove[1] == "b", "stale same spec replaced")
-- with the anchor holding the round, stale enemies go at once
r = plan.plan({ E("a", "Rat") }, { spec = "Orc", count = 1 }, 1, { a = true }, true)
assert(#r.remove == 1 and r.remove[1] == "a", "immediate removal with an anchor")
