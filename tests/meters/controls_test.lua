local controls = require("meters_controls")

-- Settings: defaults, our keys only, bad values ignored, other lines kept on render.
local s = controls.parse("")
assert(s.x == 48 and s.y == 48 and s.visible == "on" and s.next_key == "F9" and s.window == 5)
s = controls.parse("ct_behaviour = healing\nmeters_x = 100\nmeters_y = 5000\nmeters_visible = off\nmeters_next_key = F11\nmeters_clear_key = bad key\n")
assert(s.x == 100 and s.y == 48 and s.visible == "off" and s.next_key == "F11" and s.clear_key == "F5")
local text = controls.render(s, "ct_behaviour = healing\n# a comment\nmeters_x = 1\n")
assert(text:find("ct_behaviour = healing", 1, true) and text:find("# a comment", 1, true))
assert(text:find("meters_x = 100", 1, true) and not text:find("meters_x = 1\n", 1, true))
assert(text:find("meters_visible = off", 1, true))
local again = controls.parse(text)
assert(again.x == 100 and again.visible == "off")

-- The meter follows the behaviour; cycling wraps both ways.
local c = controls.new(controls.parse(""))
assert(c.meter == "damage" and c.visible == true)
c:follow("aggressive"); assert(c.meter == "taken")
c:follow("healing"); assert(c.meter == "heal")
c:follow("nonsense"); assert(c.meter == "heal")
c:follow("passive"); assert(c.meter == "damage")
assert(select(2, c:act("next")) and c.meter == "taken")
c:act("next"); c:act("next"); assert(c.meter == "damage")
c:act("prev"); assert(c.meter == "heal")
assert(select(2, c:act("meter=taken")) and c.meter == "taken")
assert(not select(2, c:act("meter=mana")) and c.meter == "taken")

-- Actions the game must carry out, and the show/hide choice (saved).
assert(c:act("clear") == "clear" and c:act("stagger") == "stagger")
local todo, ok = c:act("toggle"); assert(todo == "save" and ok and c.visible == false and c.settings.visible == "off")
todo = c:act("hide"); assert(todo == nil and c.visible == false)
todo = c:act("show"); assert(todo == "save" and c.visible == true)
assert(not select(2, c:act("dance")))

-- State for Custom Training's menu and the development files.
local st = c:state()
assert(st.meter == "taken" and st.label == "Tanking" and st.visible == true)
assert(controls.format_state(st) == "meter=taken\nlabel=Tanking\nvisible=true\n")
local list = controls.commands("next\n\n# comment\n  clear  \nmeter=heal\n")
assert(#list == 3 and list[1] == "next" and list[2] == "clear" and list[3] == "meter=heal")

-- Battle Meters alongside: read from its files; an older, enabled one moves our panel beside its own.
local bm_old = controls.battle_meters("local x = 1\n", "    overlay_x = 60,\n    overlay_y = 250,\n", true)
assert(bm_old.installed and bm_old.enabled and not bm_old.stands_aside and bm_old.x == 60 and bm_old.y == 250)
local bm_new = controls.battle_meters('local MARK = "meters-active.txt"\n', nil, true)
assert(bm_new.stands_aside and bm_new.x == 48 and bm_new.y == 240)
local none = controls.battle_meters(nil, nil, false)
assert(not none.installed)
assert(controls.mod_enabled("Keybinds : 0\nBattleMeters : 1\n", "BattleMeters", false))
assert(not controls.mod_enabled("BattleMeters : 0\n", "BattleMeters", false))
assert(not controls.mod_enabled("BattleMetersNative : 1\n", "BattleMeters", false))
assert(controls.mod_enabled("", "BattleMeters", true))
local d = controls.parse("")
local x, y, why = controls.place(d, bm_old)
assert(x == 1920 - 48 - 404 and y == 48 and why:find("clear of Battle Meters"))
x, y = controls.place(d, bm_new); assert(x == 48 and y == 48)
x, y = controls.place(d, none); assert(x == 48 and y == 48)
local old_off = controls.battle_meters("x", nil, false)
x = controls.place(d, old_off); assert(x == 48, "a disabled Battle Meters draws nothing")
local mine = controls.parse("meters_x = 700\n")
x, y, why = controls.place(mine, bm_old); assert(x == 700 and y == 48 and why == "as set")

-- Battle Meters 1.2.0 as written on its branch (stand-aside-simulator-overhaul): it requires sim_overhaul.
assert(controls.battle_meters('local SimOverhaul = require("sim_overhaul")\n', nil, true).stands_aside)

-- Saving the show/hide choice never writes a default position (it would then count as set by the player).
local fresh = controls.parse("# meters_x = 48\nmeters_visible = on\n")
fresh.visible = "off"
local saved = controls.render(fresh, "# meters_x = 48\nmeters_visible = on\n")
assert(not saved:find("\nmeters_x", 1, true) and not saved:find("\nmeters_y", 1, true) and saved:find("meters_visible = off", 1, true), saved)
local reread = controls.parse(saved)
assert(not (reread.chosen and (reread.chosen.x or reread.chosen.y)), "still not chosen")
-- A position the player set is kept.
local set = controls.parse("meters_x = 700\n")
assert(controls.render(set, "meters_x = 700\n"):find("meters_x = 700", 1, true))
