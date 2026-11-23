-- ui_menu with a fake game and a fake Custom Training: open, change in place, the opponent list, apply, cancel;
-- ui_keys presses; ui_ct parsing.
for _, m in ipairs({ "ui_model", "ui_menu", "ui_keys", "ui_ct" }) do package.loaded[m] = nil end
local menu_module = require("ui_menu")
local keys = require("ui_keys")
local ct_module = require("ui_ct")

-- ui_ct ------------------------------------------------------------------------------------------------------------
local s = ct_module.parse_state("what=change\nactive=true\nopponent=o2\ncount=2\nbehaviour=passive\ndifficulty=normal\nboss=false\n")
assert(s.active == true and s.opponent == "o2" and s.count == 2 and s.boss == false)
assert(ct_module.parse_state("what=end\nactive=true\n").active == false, "an end is not active")
assert(ct_module.parse_state("") == nil)
local text = table.concat({
    "opponent\to1\t1\tHumans\tfalse\tBandit", -- field 5: the opponent's own copy cap ("true"/"false" from before: none)
    "opponent\to2\t3\tBeasts\t1\tBehemoth King",
    "behaviour\tpassive\tPassive", "behaviour\thealing\tHealing",
    "difficulty\tnormal\tNormal", "max_count\t3", "" }, "\n")
local l = ct_module.parse_lists(text)
assert(#l.opponents == 2 and l.opponents[2].max_count == 1 and l.opponents[1].max_count == nil)
assert(l.opponents[2].name == "Behemoth King" and l.opponents[2].kind == 3)
assert(#l.behaviours == 2 and #l.difficulties == 1 and l.max_count == 3)
assert(ct_module.parse_lists("max_count\t3\n") == nil, "no opponents, no lists")
assert(ct_module.format_set({ count = 3, opponent = "o1" }) == "set count=3 opponent=o1\n")
local cl = ct_module.lists_from_catalogue({ opponents = {
    { id = "mobcolvr_SU2030_01_Alexander_GilQuest_00", spec = "SU2030_01_Alexander_GilQuest", label = "$a", category = 5, boss = true, cap = 1 },
    { id = "mobcolvr_SU2030_00_Alexander_Standard_00", spec = "SU2030_00_Alexander_Standard", label = "$a", category = 5, boss = true, cap = 1 },
    { id = "mobcolvr_EN0008_00_Vice_Standard_00", spec = "EN0008_00_Vice_Standard", label = "$v", category = 1 },
} }, function(k) return ({ ["$a"] = "Alexander", ["$v"] = "Bandit" })[k] end)
assert(cl.opponents[1].name == "Bandit" and cl.opponents[1].kind_name == "Humans")
assert(cl.opponents[1].max_count == nil and cl.opponents[2].max_count == 1, "the catalogue's cap, where it has one")
assert(cl.opponents[2].name:find("^Alexander %(") and cl.opponents[2].name ~= cl.opponents[3].name, cl.opponents[2].name)

-- The bridge: one command file at a time.
local files = {}
local fio = {
    read = function(p) return files[p] end,
    write = function(p, t) files[p] = t; return true end,
    exists = function(p) return files[p] ~= nil end,
}
local b = ct_module.bridge("ct/", fio, function() end, nil)
files["ct/ct-course.txt"] = "what=start\nactive=true\nopponent=o1\ncount=1\nbehaviour=passive\ndifficulty=normal\n"
files["ct/ct-lists.txt"] = text
assert(b.active() and b.lists().opponents[1].id == "o1")
b.apply({ count = 2 })
assert(files["ct/ct-command.txt"] == "set count=2\n")
b.apply({ behaviour = "healing" })
assert(files["ct/ct-command.txt"] == "set count=2\n", "waits for the first to be read")
files["ct/ct-command.txt"] = nil
b.poll()
assert(files["ct/ct-command.txt"] == "set behaviour=healing\n")

-- ui_keys ----------------------------------------------------------------------------------------------------------
assert(keys.chord({ Gamepad_LeftShoulder = true, Gamepad_RightShoulder = true }) and not keys.chord({ Gamepad_LeftShoulder = true }))

-- ui_menu ----------------------------------------------------------------------------------------------------------
local log = {}
local game = { windows = {}, focus_row = 1, paused_now = false, battle = true, held = {}, focus_calls = 0, focus_works_on = 2 }
function game.show(body, options)
    local w = { body = body, options = options, open = true }
    game.windows[#game.windows + 1] = w
    game.focus_row = 1 -- the window opens with its cursor on the first row
    return w
end
function game.closed(w) return not w.open end
function game.selected(w) return w.choice end
function game.hide(w) w.open = false; w.choice = -1 end
function game.rows(w)
    local rows = {}
    for i in ipairs(w.options) do rows[i] = { text = { w = w, i = i } } end
    return rows, nil, nil
end
function game.focused() return game.focus_row, "hover" end
-- Like the game: the first way tried does nothing, the second moves the cursor.
function game.focus(rows, list, i, try)
    game.focus_calls = game.focus_calls + 1
    if try >= game.focus_works_on then game.focus_row = i end
    return "way " .. try
end
function game.paused() return game.paused_now end
function game.pause(on) game.paused_now = on; return true end
function game.in_battle() return game.battle end
function game.keys_down() return game.held end

local applied
local ct = {
    state = function() return { active = true, opponent = "o1", count = 1, behaviour = "passive", difficulty = "normal" } end,
    lists = function() return l end,
    apply = function(c) applied = c; return true end,
}
local menu = menu_module.new({ game = game, ct = ct, keys = keys, log = function(m) log[#log + 1] = m end,
                               options = { place_cursor = true } })
local now = 0
local function tick() now = now + 0.05; return menu:tick(now) end
local function ticks(n) for _ = 1, n do tick() end end
local function top() return game.windows[#game.windows] end
local function confirm(row) top().open, top().choice = false, row - 1; tick() end

-- Opened by the chord in a fight; the game pauses.
game.held = { Gamepad_LeftShoulder = true, Gamepad_RightShoulder = true }
assert(tick() == true and menu.screen == "main" and game.paused_now, "opened by the chord")
game.held = {}
assert(top().options[1] == "Opponent:   Bandit", top().options[1])
ticks(4)
-- Behaviour: its values, the cursor put on the current one, then Healing chosen.
confirm(3)
assert(menu.screen == "values" and top().options[1] == "Passive" and top().options[2] == "Healing" and top().options[3] == "Back")
ticks(4)
assert(game.focus_row == 1, "current value is the first: nothing to move")
confirm(2)
assert(menu.screen == "main" and top().options[3] == "Behaviour:   Healing", top().options[3])
-- The cursor comes back to the Behaviour row: the first way does nothing, the second moves it.
ticks(30)
assert(game.focus_row == 3, "cursor back on Behaviour: " .. game.focus_row)
-- The opponent list: kinds, then the names of the second kind; the cursor on the right rows.
confirm(1)
assert(menu.screen == "sections" and top().options[1] == "Humans" and top().options[2] == "Beasts")
confirm(2)
assert(menu.screen == "names" and top().options[1] == "Behemoth King")
confirm(1)
assert(menu.screen == "main" and top().options[1] == "Opponent:   Behemoth King", top().options[1])
assert(top().options[2] == "Number:   1", "capped at one copy")
assert(top().options[3] == "Behaviour:   Healing", "the draft survives the list")
-- Apply: closed, unpaused, changes handed over.
confirm(5)
assert(menu.screen == nil and not game.paused_now)
assert(applied.opponent == "o2" and applied.behaviour == "healing" and applied.count == nil, "applied")

-- When no way moves the cursor, it gives up and says so.
game.focus_works_on = 99
applied = nil
menu:request(); tick()
confirm(3) -- Behaviour values
confirm(2) -- Healing: back on the main window, wanting row 3
ticks(40)
assert(game.focus_row == 1)
local said = false
for _, line in ipairs(log) do if line:find("not placed on row 3", 1, true) then said = true end end
assert(said, "logged that the cursor stayed")
game.focus_works_on = 2

-- Cancel: nothing applied.
confirm(6)
assert(menu.screen == nil and applied == nil, "cancel applies nothing")
-- A development pick, and F7 closing an open menu.
menu:request(); tick()
menu:pick(-1); tick()
assert(menu.screen == nil and applied == nil)
menu:request(); tick(); assert(menu.screen == "main")
menu:request(); tick(); assert(menu.screen == nil and not game.paused_now, "F7 again closes")
-- Esc or Backspace (back): Back on a list, Cancel on the main window. A moment after the press the window goes, and
-- after a gap with no window (where Esc's Pause menu is closed if it opens) the next one shows.
function game.pause_menu_open() return game.pause_menu == true end
function game.hide_pause_menu() game.pause_menu = false; game.paused_now = false end -- closing it lets the fight run
menu:request(); tick()
confirm(3); assert(menu.screen == "values")
menu:back(); menu:back(); tick()
assert(top().open, "the window stays a moment")
ticks(6)
assert(not top().open, "then goes")
game.pause_menu = true; tick()
assert(game.pause_menu == false, "Esc's Pause menu closed in the gap")
ticks(12)
assert(menu.screen == "main" and top().open and game.paused_now, "back on a list: the main window, the fight paused again")
menu:back(); ticks(6)
game.pause_menu = true; ticks(12)
assert(menu.screen == nil and not game.paused_now and applied == nil and game.pause_menu == false,
       "back on the main window: cancel, the Pause menu closed, the fight resumes")
ticks(40); game.pause_menu = true; tick(); assert(game.pause_menu == true, "later: a Pause menu opened afterwards is the player's")
game.pause_menu = false
-- B on the pad, read through the game's system input: back, once per press (held, it doesn't repeat; held as the menu
-- opens, it isn't a press).
game.sys_held = {}
function game.system_keys_down() return game.sys_held end
game.sys_held = { Gamepad_FaceButton_Right = true }
menu:request(); tick(); ticks(3)
assert(menu.screen == "main", "B held as the menu opens: nothing")
game.sys_held = {}; tick()
confirm(3); assert(menu.screen == "values")
game.sys_held = { Gamepad_FaceButton_Right = true }; ticks(20)
assert(menu.screen == "main" and top().open and game.paused_now, "B on a list: the main window, once though held")
game.sys_held = {}; tick()
game.sys_held = { Gamepad_FaceButton_Right = true }; ticks(20)
assert(menu.screen == nil and not game.paused_now and applied == nil, "B on the main window: cancel")
game.sys_held = {}; ticks(2)
-- B closing the game's window itself (seen once by Custom Training): the window closed with no choice, the same as back.
menu:request(); tick()
confirm(3)
top().open, top().choice = false, -1; tick()
assert(menu.screen == "main" and top().open, "B on a list: the main window")
-- A back key pressed as the window closes itself counts once.
confirm(3)
menu:back(); tick(); top().open, top().choice = false, -1; ticks(10)
assert(menu.screen == "main" and top().open, "one back, not two")
menu:back(); ticks(20); assert(menu.screen == nil and not game.paused_now)
menu:back(); tick(); assert(menu.screen == nil, "back with the menu closed does nothing")
-- Not in a course: refused.
ct.state = function() return { active = false } end
menu:request(); tick()
assert(menu.screen == nil)

print("menu ok")
