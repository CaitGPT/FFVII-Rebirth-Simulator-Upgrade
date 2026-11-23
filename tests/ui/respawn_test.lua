-- Respawn (owner 2026-11-21: enemies don't refill; the player brings the same fight back): with a Custom Training that
-- says whether the wave is cleared, Respawn is the main window's first row, where the cursor starts, and acts at once;
-- after a clear the window says "Wave cleared in 1:23". Also the menu and the bridge calling it.
for _, m in ipairs({ "ui_model", "ui_menu", "ui_ct" }) do package.loaded[m] = nil end
local model = require("ui_model")
local ct_module = require("ui_ct")

local lists = {
    opponents = { { id = "o1", name = "Bandit", kind = 1, kind_name = "Humans", needs_m = 12 } },
    behaviours = { { id = "passive", name = "Passive" } },
    difficulties = { { id = "normal", name = "Normal" } },
    max_count = 3, group_max = 3,
    courses = { { id = "c1", tab = 1, tab_name = "Summons", name = "Titan", rounds = { { id = "c1r1", number = 1, name = "Round 1", enemies = "Titan", needs_m = 14 } } } },
}
local fighting = { active = true, group = { "o1" }, behaviour = "passive", difficulty = "normal", wave = 2, cleared = false, last_clear = 83.4, needs_m = 12 }
local m = model.new(lists, fighting, { meter = "damage", visible = true })
local w = m:window()
assert(w.options[1] == "Respawn" and w.focus == 1, "first, and the cursor on it")
assert(w.options[2] == "Mode:   Opponents" and #w.options == 12 and #w.options <= model.PAGE + 1, #w.options)
assert(not w.body:find("cleared", 1, true), "mid-fight: no clear line")
assert(m:choose(0).kind == "respawn", "acts at once")
-- After a clear: the time, as m:ss.
m:reset({ active = true, group = { "o1" }, behaviour = "passive", difficulty = "normal", wave = 2, cleared = true, last_clear = 83.4, needs_m = 12 })
w = m:window()
assert(w.body == "Custom Training\nWave cleared in 1:23\n<button=decide> Change a setting, then Apply", w.body)
m:reset({ active = true, group = { "o1" }, behaviour = "passive", difficulty = "normal", wave = 1, cleared = true, needs_m = 12,
          stage_name = "Cave of the Gi", room_m = 18 })
assert(m:window().body == "Custom Training\nWave cleared\nStage: Cave of the Gi\n<button=decide> Change a setting, then Apply", m:window().body)
-- Back on the main window from a list, the cursor goes to that row, not Respawn; reopened, Respawn again.
m:choose(m:index("behaviour") - 1); m:choose(0)
assert(m:window().focus == m:index("behaviour"))
m:reset(fighting)
assert(m:window().focus == 1)
-- A Custom Training without waves in its state, or without a respawn to call: no Respawn row.
local old = model.new(lists, { active = true, group = { "o1" }, behaviour = "passive", difficulty = "normal" })
assert(old:window().options[1] == "Mode:   Opponents")
local waves_only = model.new(lists, { active = true, group = { "o1" }, behaviour = "passive", difficulty = "normal", wave = 3 },
                             nil, { respawn = false })
assert(waves_only:window().options[1] == "Mode:   Opponents")
-- Not saying cleared (before custom-training adds it): the last clear's time, said as the last one.
local nocleared = model.new(lists, { active = true, group = { "o1" }, behaviour = "passive", difficulty = "normal", wave = 3, last_clear = 61 })
assert(nocleared:window().options[1] == "Respawn")
assert(nocleared:window().body:find("\nLast wave cleared in 1:01\n", 1, true), nocleared:window().body)
-- Mid-fight with cleared = false: no line, though an earlier wave was cleared.
assert(not model.new(lists, fighting):window().body:find("cleared", 1, true))

-- The menu: Respawn closes it and calls Custom Training's respawn.
local menu_module = require("ui_menu")
local game = { windows = {} }
function game.show(body, options) local x = { body = body, options = options, open = true }; game.windows[#game.windows + 1] = x; return x end
function game.closed(x) return not x.open end
function game.selected(x) return x.choice end
function game.hide(x) x.open = false; x.choice = -1 end
function game.rows() return {}, nil, nil end
function game.focused() return 1, "hover" end
function game.focus() return "none" end
function game.paused() return game.paused_now end
function game.pause(on) game.paused_now = on; return true end
function game.in_battle() return true end
function game.keys_down() return {} end
local respawned = 0
local ct = { state = function() return fighting end, lists = function() return lists end,
             apply = function() return true end, respawn = function() respawned = respawned + 1; return true end }
local logged = {}
local menu = menu_module.new({ game = game, ct = ct, keys = require("ui_keys"), log = function(x) logged[#logged + 1] = x end,
                               options = {} })
local now = 0
local function tick() now = now + 0.05; return menu:tick(now) end
menu:request(); tick()
assert(menu.screen == "main" and game.paused_now)
local top = game.windows[#game.windows]
top.open, top.choice = false, 0; tick() -- A on Respawn
assert(menu.screen == nil and not game.paused_now and respawned == 1, "respawned, closed, the fight running")
assert(logged[#logged] == "respawn\ttrue\tnil", logged[#logged])

-- The bridge: "respawn" as a command line; wave, cleared and last_clear parsed.
local files = {}
local b = ct_module.bridge("ct/", { read = function(p) return files[p] end, write = function(p, t) files[p] = t; return true end,
                                    exists = function(p) return files[p] ~= nil end }, function() end, nil)
b.respawn()
assert(files["ct/ct-command.txt"] == "respawn\n")
local s = ct_module.parse_state("what=change\nactive=true\nwave=2\ncleared=true\nlast_clear=83.4\n")
assert(s.cleared == true and s.last_clear == 83.4 and s.wave == 2)
assert(ct_module.direct({ respawn = function() return true end, active = function() end }).respawn() == true)
assert(ct_module.direct({ active = function() end }).respawn == nil, "no respawn in an older Custom Training")

print("respawn ok")
