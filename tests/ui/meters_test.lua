-- The meter rows: shown only with the meters part, chosen from a list like the other settings, Hidden as "hide",
-- Clear meter and Reset stagger done at once; ui_meters' state parsing and its command file.
for _, m in ipairs({ "ui_model", "ui_menu", "ui_keys", "ui_meters" }) do package.loaded[m] = nil end
local model = require("ui_model")
local menu_module = require("ui_menu")
local keys = require("ui_keys")
local meters_module = require("ui_meters")

local lists = {
    opponents = { { id = "o1", name = "Bandit", kind = 1, kind_name = "Humans" },
                  { id = "o2", name = "Behemoth King", kind = 3, kind_name = "Beasts", max_count = 1 } },
    behaviours = { { id = "passive", name = "Passive" }, { id = "healing", name = "Healing" } },
    difficulties = { { id = "normal", name = "Normal" } },
    max_count = 3,
}
local state = { active = true, opponent = "o1", count = 1, behaviour = "passive", difficulty = "normal" }

-- No meters: the six rows as before.
assert(#model.new(lists, state):row_texts() == 6)

-- With the meters: nine rows, the meter shown.
local m = model.new(lists, state, { meter = "taken", label = "Tanking", visible = true })
local rows = m:row_texts()
assert(#rows == 9, #rows)
assert(rows[5] == "Meter:   Tanking", rows[5])
assert(rows[6] == "Clear meter" and rows[7] == "Reset stagger" and rows[8] == "Apply" and rows[9] == "Cancel")
assert(next(m:meter_actions()) == nil, "unchanged: nothing for the meters")
-- The meter's values, the cursor on Tanking; Healing chosen, then applied.
m:choose(4)
local w = m:window()
assert(w.screen == "values" and w.body == "Meter\nNow: Tanking" and #w.options == 5 and w.focus == 2 and w.options[4] == "Hidden")
m:choose(2)
assert(m:row_text("meter") == "Meter:   Healing" and m:window().focus == 5)
local r = m:choose(7)
assert(r.kind == "apply" and r.meters[1] == "meter=heal" and #r.meters == 1, "apply hands the meter over")
-- Hidden.
m:choose(4); m:choose(3)
assert(m:row_text("meter") == "Meter:   Hidden" and m:meter_actions()[1] == "hide" and #m:meter_actions() == 1)
-- Clear meter and Reset stagger.
r = m:choose(5)
assert(r.kind == "meters_now" and r.action == "clear" and m.screen == "main" and m:window().focus == 6)
assert(m:choose(6).action == "stagger")
assert(m:choose(8).kind == "close")

-- Hidden meters: the row shows Hidden; picking a meter shows them again.
local h = model.new(lists, state, { meter = "damage", label = "Damage", visible = false })
assert(h:row_text("meter") == "Meter:   Hidden")
h:set({ meter = "heal" })
local a = h:meter_actions()
assert(a[1] == "meter=heal" and a[2] == "show", table.concat(a, ","))

-- ui_meters: state parsing and the development command file.
local s = meters_module.parse_state("meter=heal\nlabel=Healing\nvisible=false\n")
assert(s.meter == "heal" and s.visible == false)
assert(meters_module.parse_state("") == nil)
local files = {}
local fio = { read = function(p) return files[p] end, write = function(p, t) files[p] = t; return true end,
              exists = function(p) return files[p] ~= nil end }
local b = meters_module.bridge("m/", fio, function() end)
assert(not b.present(), "no state file: not present")
files["m/meters-state.txt"] = "meter=damage\nlabel=Damage\nvisible=true\n"
assert(b.present() and b.state().meter == "damage")
b.act("clear"); b.act("stagger")
assert(files["m/meters-command.txt"] == "clear\nstagger\n", files["m/meters-command.txt"])

-- The menu: Clear meter acts at once and the main window comes back; Apply sends the meter change.
local game = { windows = {}, focus_row = 1, paused_now = false, battle = true, held = {} }
function game.show(body, options) local w = { body = body, options = options, open = true }; game.windows[#game.windows + 1] = w; return w end
function game.closed(w) return not w.open end
function game.selected(w) return w.choice end
function game.hide(w) w.open = false; w.choice = -1 end
function game.rows(w) local t = {}; for i in ipairs(w.options) do t[i] = { text = { w = w, i = i } } end; return t, nil, nil end
function game.focused() return game.focus_row, "hover" end
function game.focus(rows, list, i) game.focus_row = i; return "keyboard" end
function game.paused() return game.paused_now end
function game.pause(on) game.paused_now = on; return true end
function game.in_battle() return game.battle end
function game.keys_down() return game.held end
local acted, applied = {}, nil
local meters = { present = function() return true end, state = function() return { meter = "damage", label = "Damage", visible = true } end,
                 act = function(x) acted[#acted + 1] = x; return true end }
local ct = { state = function() return state end, lists = function() return lists end,
             apply = function(c) applied = c; return true end }
local menu = menu_module.new({ game = game, ct = ct, meters = meters, keys = keys })
local now = 0
local function tick() now = now + 0.05; return menu:tick(now) end
local function top() return game.windows[#game.windows] end
local function confirm(row) top().open, top().choice = false, row - 1; tick() end
menu:request(); tick(); tick(); tick()
assert(menu.screen == "main" and #top().options == 9)
confirm(6) -- Clear meter
assert(acted[1] == "clear" and menu.screen == "main" and #game.windows == 2, "acted, window back")
confirm(5) -- Meter
confirm(4) -- Hidden
assert(top().options[5] == "Meter:   Hidden", top().options[5])
confirm(8) -- Apply
assert(menu.screen == nil and acted[2] == "hide" and applied == nil, "only the meters changed: Custom Training not called")
print("meters ok")
