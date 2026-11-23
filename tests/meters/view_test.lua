local view = require("meters_view")
local controls = require("meters_controls")

assert(view.format_number(0) == "0" and view.format_number(999.4) == "999" and view.format_number(1234567.6) == "1,234,568")
assert(view.format_time(0) == "0:00" and view.format_time(75.9) == "1:15" and view.format_time(3725) == "1:02:05")

-- Subtitle: Custom Training's words for the setup (state().setup), then the behaviour; long setups cut by characters,
-- never splitting one, the behaviour kept. Names come in the game's language.
local X, DOT = "\195\151", "\194\183"   -- ×, ·  (Custom Training's "Bomb ×3" and "… · Round 1")
assert(view.subtitle(nil) == "Custom Training")
-- Copies of one.
assert(view.subtitle({ active = true, setup = "Bomb " .. X .. "3", name = "Bomb", count = "3", behaviour = "passive" })
    == "Bomb " .. X .. "3, Passive")
-- A mixed group (seen 2026-11-21 as "Tonberry King x3, Aggressive").
assert(view.subtitle({ active = true, setup = "Tonberry King, Mindflayer, Bomb", name = "Tonberry King", count = "3",
    behaviour = "aggressive" }) == "Tonberry King, Mindflayer, Bomb, Aggressive")
-- A round: short ones whole; a long one cuts the course name and keeps the round's number.
local round = "Brutal: Bloodbath " .. DOT .. " Round 2"
assert(view.subtitle({ active = true, setup = round, mode = "round", behaviour = "aggressive" }) == round .. ", Aggressive")
round = view.subtitle({ active = true, setup = "Brutal: Unending Nightmare " .. DOT .. " Round 1", mode = "round",
    behaviour = "aggressive" })
assert(round:find("^Brutal: Unending") and round:find("%.%.%. " .. DOT .. " Round 1, Aggressive$")
    and view.text_width(round) <= view.MAX_SUBTITLE, round)
-- A long group: cut to fit, the behaviour kept.
local long = view.subtitle({ active = true, setup = "Tonberry King " .. X .. "2, Mindflayer, Bomb, Grashtrike Queen",
    behaviour = "aggressive" })
assert(view.text_width(long) <= view.MAX_SUBTITLE and long:find("%.%.%., Aggressive$") and utf8.len(long), long)
-- Without setup (an older Custom Training): the first opponent and the count.
assert(view.subtitle({ active = true, name = "Bomb", count = "3", behaviour = "passive" }) == "Bomb " .. X .. "3, Passive")
assert(view.subtitle({ active = true, name = "Bomb", count = "1", behaviour = "healing" }) == "Bomb, Healing")
-- Other languages kept whole: French, German, Japanese.
local fr = "Roi Tonberry, Flagelleur mental, Bombo, M\195\169canique de pr\195\169cision"
local cut = view.subtitle({ active = true, setup = fr, behaviour = "passive" })
assert(utf8.len(cut) and cut:find("^Roi Tonberry, Flagelleur mental") and cut:find("%.%.%., Passive$")
    and view.text_width(cut) <= view.MAX_SUBTITLE, cut)
assert(view.subtitle({ active = true, setup = "Gro\195\159e Bombe", behaviour = "healing" }) == "Gro\195\159e Bombe, Healing")
local ja = string.rep("\227\131\136\227\131\179\227\131\153\227\131\170", 8)   -- トンベリ x8: 32 full-width characters
cut = view.subtitle({ active = true, setup = ja, behaviour = "aggressive" })
assert(utf8.len(cut) and cut:find("%.%.%., Aggressive$") and view.text_width(cut) <= view.MAX_SUBTITLE, cut)
assert(view.text_width("\227\131\136") == 2 and view.text_width("Bomb") == 4)
-- Broken bytes and control characters are dropped, never passed to the panel.
assert(view.subtitle({ active = true, setup = "Bo\255mb\n", behaviour = "passive" }) == "Bomb, Passive")
assert(view.subtitle({ active = true, setup = "", name = "", behaviour = "passive" }) == "Custom Training, Passive")

-- Custom Training's waves: "Wave N", then the last clear once there is one; nothing without waves or a course.
assert(view.wave({ active = true }) == nil and view.wave(nil) == nil and view.wave({ active = false, wave = 2 }) == nil)
assert(view.wave({ active = true, behaviour = "aggressive", wave = 1 }) == "Wave 1")
assert(view.wave({ active = true, behaviour = "aggressive", wave = 0 }) == nil, "0: starting")
assert(view.wave({ active = true, behaviour = "aggressive", wave = "4", last_clear = "83.9" }) == "Wave 4   Last clear 1:23")
assert(view.wave({ active = true, behaviour = "aggressive", wave = 12, last_clear = 3725 }) == "Wave 12   Last clear 1:02:05")
-- Passive and Healing refill enemies: the line only once a wave has really been cleared.
assert(view.wave({ active = true, behaviour = "passive", wave = 1 }) == nil)
assert(view.wave({ active = true, behaviour = "healing", wave = 2, last_clear = 30 }) == "Wave 2   Last clear 0:30")

local settings = controls.parse("")
local function snapshot(kinds, party, elapsed)
    local s = { elapsed = elapsed or 10, party = party or { "Cloud", "Zack" }, kinds = {} }
    for _, kind in ipairs({ "damage", "taken", "heal", "mp" }) do
        s.kinds[kind] = { average = 0, recent = 0, total = 0, biggest = 0, by_source = {}, attributed = kind ~= "damage" }
    end
    for kind, v in pairs(kinds or {}) do for k2, x in pairs(v) do s.kinds[kind][k2] = x end end
    return s
end

-- Empty: every meter draws with zeros; party rows listed at 0.
local course = { active = true, name = "Bomb", count = "1", behaviour = "passive" }
local v = view.build(snapshot(), "damage", course, settings)
assert(v.value == "0" and v.timer == "0:10" and #v.stats == 3 and #v.rows == 0 and v.note == nil)
assert(v.tabs[1].current and not v.tabs[2].current and v.tabs[1].text == "Damage" and v.tabs[2].text == "Tanking")
assert(v.hint == "F9 Meter   F5 Clear   F6 Stagger   F8 Hide" and v.unit == "Damage per second")
v = view.build(snapshot(), "taken", course, settings)
assert(#v.rows == 2 and v.rows[1].name == "Cloud" and v.rows[1].total == "0" and v.rows[2].name == "Zack")
assert(v.stats[4][1] == "Damage dealt per second" and v.tabs[2].current)
v = view.build(snapshot(), "heal", course, settings)
assert(#v.stats == 5 and v.stats[5][2] == "-")

-- Damage by character, Unattributed last; huge values grouped.
v = view.build(snapshot({ damage = { total = 12345678, average = 123456.7, attributed = true,
    by_source = { Cloud = 10000000, Zack = 2000000, Sephiroth = 300000, Unattributed = 45678 } } },
    { "Cloud", "Zack", "Sephiroth", "Aerith" }, 100), "damage", course, settings)
assert(v.value == "123,457" and #v.rows == 5)
assert(v.rows[1].name == "Cloud" and v.rows[1].total == "10,000,000" and v.rows[1].rate == "100,000")
assert(v.rows[4].name == "Aerith" and v.rows[4].total == "0" and v.rows[5].name == "Unattributed")
assert(math.abs(v.rows[1].share - 10000000 / 12345678) < 1e-9)
assert(v.rows[5].color == view.OTHER and v.rows[2].color.B == 1.00)
-- Damage without the native helper: the total only, and a note.
v = view.build(snapshot({ damage = { total = 500, attributed = false } }), "damage", course, settings)
assert(#v.rows == 0 and v.note:find("native"))
-- Healing without hit events: by who received it, said so.
local s2 = snapshot({ heal = { total = 100, attributed = false, by_source = { Zack = 100 } }, mp = { total = 40 } })
v = view.build(s2, "heal", course, settings)
assert(v.note == "Healing shown by who received it" and v.rows[2].total == "100" and v.stats[5][2] == "3")
-- Someone credited who isn't in the party now still gets a row, before Unattributed.
v = view.build(snapshot({ taken = { total = 10, by_source = { Tifa = 10 } } }, { "Cloud" }), "taken", course, settings)
assert(#v.rows == 2 and v.rows[2].name == "Tifa")

-- Every sample draws in every meter, within the panel's limits (rough Roboto widths: 0.56 of the size per character).
local samples = require("meters_samples")
local function fits(text, size, width) return #text * size * 0.56 <= width end
for name in pairs(samples.SAMPLES) do
    local s = samples.get(name)
    assert(s.sample == name)
    for _, meter in ipairs(controls.METERS) do
        local v2 = view.build(s, meter, { active = true, name = "Gilgamesh, Lord of the Battlefield Extra", count = "3",
            behaviour = "aggressive" }, settings)
        assert(#v2.rows <= view.MAX_ROWS and #v2.stats <= 6, name .. " " .. meter)
        assert(fits(v2.subtitle, 13, 368) and fits(v2.hint, 12, 368) and fits(v2.value, 30, 368 * 0.6 - 10), name)
        for _, r in ipairs(v2.rows) do assert(fits(r.name, 15, 150) and fits(r.total, 15, 110) and fits(r.rate, 15, 92), r.name) end
        for _, st in ipairs(v2.stats) do assert(fits(st[1], 15, 250) and fits(st[2], 17, 220), st[1]) end
    end
end
assert(samples.get("nope") == nil)
