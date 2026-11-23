-- Runs the real main.lua against a fake UE4SS, fake game objects, a fake native helper and Custom Training's course
-- file, through a Passive course, a change to Healing and the end. It checks the wiring (course events, keys, the
-- command and state files, the anchor left out, stagger, strict counting, hide and the saved setting), not the game.
local sep = package.config:sub(1, 1)
local tmp = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp") .. sep .. "simoverhaul-meters-test-" .. tostring(os.time()) .. tostring(math.random(1e6))
os.execute((sep == "\\" and "mkdir " or "mkdir -p ") .. '"' .. tmp .. sep .. "SimOverhaulMeters" .. '"')
os.execute((sep == "\\" and "mkdir " or "mkdir -p ") .. '"' .. tmp .. sep .. "SimOverhaulCustomTraining" .. '"')
local MOD = tmp .. sep .. "SimOverhaulMeters" .. sep
local COURSE = tmp .. sep .. "SimOverhaulCustomTraining" .. sep .. "ct-course.txt"
SIMOVERHAUL_METERS_TEST_DIR = MOD
local function put(path, text) local f = assert(io.open(path, "wb")); f:write(text); f:close() end
local function get(path) local f = io.open(path, "rb"); if not f then return nil end; local t = f:read("a"); f:close(); return t end
put(MOD .. "dev.txt", "")
-- An older Battle Meters, switched on in mods.txt, with its panel moved to 60,250: ours goes beside it.
os.execute((sep == "\\" and "mkdir " or "mkdir -p ") .. '"' .. tmp .. sep .. "BattleMeters" .. sep .. "Scripts" .. '"')
put(tmp .. sep .. "BattleMeters" .. sep .. "Scripts" .. sep .. "main.lua", "-- Battle Meters 1.1.0\n")
put(tmp .. sep .. "BattleMeters" .. sep .. "Scripts" .. sep .. "config.lua", "overlay_x = 60,\noverlay_y = 250,\n")
put(tmp .. sep .. "mods.txt", "BattleMeters : 1\n")

local logs = {}
local real_print = print
print = function(text) logs[#logs + 1] = tostring(text) end
local function logged(pattern) for _, l in ipairs(logs) do if l:find(pattern) then return l end end end

local next_address, game_time = 0x1000, 0
local function fname(s) return { ToString = function() return s end } end
local function obj(name, fields)
    next_address = next_address + 0x10
    local address = next_address
    fields = fields or {}
    fields.IsValid = function() return true end
    fields.GetAddress = function() return address end
    fields.GetFName = function() return fname(name or ("Obj" .. address)) end
    return fields
end

local world = { in_battle = false, enemies = {}, party = {}, hp = {}, max = {}, burst = {}, ended = {} }
local function actor(object_name, actor_name, hp)
    local a = obj(object_name)
    a.actor_name = actor_name
    a.Controller = { EndBurstInstant = function() world.ended[a] = true end }
    world.hp[a], world.max[a] = hp, hp
    return a
end
local battle = obj("Battle", {
    IsInBattle = function() return world.in_battle end,
    GetEnemyMembersRef = function() return world.enemies end,
    GetCharaHP = function(_, a) return world.hp[a] end,
    GetHPMax = function(_, a) return world.max[a] end,
    GetActorName = function(_, a) return fname(a.actor_name) end,
    GetCharaID = function(_, a) return fname(a.chara_id or "None") end,
    IsBurst = function(_, a) return world.burst[a] == true end,
})
local party_api = obj("Party", {
    GetBattleMemberCount = function() return #world.party end,
    GetBattleMember = function(_, i) return world.party[i + 1].actor end,
    GetBattleMemberType = function(_, i) return world.party[i + 1].kind end,
})
local pawn = obj("Pawn", { GetClass = function() return { GetFName = function() return fname("PC0000_00_Cloud_Standard_C") end } end })
local paused = false
local statics = obj("Statics", {
    GetPlayerPawn = function() return pawn end,
    GetTimeSeconds = function() return game_time end,
    IsGamePaused = function() return paused end,
})
local objects = {
    ["/Script/EndGame.Default__EndBattleAPI"] = battle,
    ["/Script/EndGame.Default__EndPartyAPI"] = party_api,
    ["/Script/EndGame.Default__EndMenuBPAPI"] = obj("Menu", { BPGetPlayerMP = function() return 50 end }),
    ["/Script/Engine.Default__GameplayStatics"] = statics,
}
StaticFindObject = function(path) return objects[path] end
FindFirstOf = function(name) if name == "GameEngine" then return obj("Engine", { GameViewport = obj("Viewport") }) end end
ExecuteInGameThread = function(fn) fn() end
local loop
LoopAsync = function(_, fn) loop = fn end
local keys = {}
RegisterKeyBind = function(key, fn) keys[key] = fn end
Key = { F5 = "F5", F6 = "F6", F8 = "F8", F9 = "F9" }
FName = fname
FText = function(s) return s end

local queue = {}
SimOverhaulMetersHit = function()
    local h = table.remove(queue, 1)
    if h then return h[1], h[2], h[3], h[4] end
end
SimOverhaulMetersStatus = function() return "ok", 0, #queue end
local function hit(damage, causer, target, heal) queue[#queue + 1] = { damage, causer, target, heal == true } end

local shown, hidden, shown_at = nil, 0, nil
package.loaded.meters_overlay = {
    show = function(view, panel) shown = view; shown_at = panel; return true end,
    hide = function() hidden = hidden + 1; shown = nil end,
    shown = function() return shown ~= nil end,
}

local function course(t)
    local lines = {}
    for _, k in ipairs({ "what", "active", "behaviour", "opponent", "name", "boss", "count", "difficulty", "anchor",
            "wave", "wave_started", "last_clear" }) do
        lines[#lines + 1] = k .. "=" .. tostring(t[k])
    end
    for who, n in pairs(t.mp or {}) do lines[#lines + 1] = "mp." .. who .. "=" .. n end
    put(COURSE, table.concat(lines, "\n") .. "\n")
end
local function tick() for _ = 1, 5 do loop() end end   -- idle ticks run every 5th loop

local ok, err = pcall(function()
    package.loaded.main = nil
    require("main")
    assert(keys.F9 and keys.F5 and keys.F6 and keys.F8, "four keys bound")
    assert(logged("loaded: meter keys F9/F5/F6/F8"), "loaded")
    assert(logged("panel at 1468,48 %(top right, clear of Battle Meters"), "placed clear of the older Battle Meters")

    -- No course: nothing drawn.
    tick()
    assert(shown == nil)

    -- A Passive course starts: anchor + one Bomb; Cloud and Zack.
    local cloud = actor("PC0000_00_Cloud_Standard_C_1", "Cloud", 7000)
    local zack = actor("PC0009_00_Zack_Standard_C_2", "ZACK", 6900)
    local anchor = actor("EN9999_Anchor_C_77", "EN9999", 100)
    local bomb = actor("EN2001_00_Bomb_C_3", "EN2001_00", 100000)
    world.party = { { actor = cloud, kind = 0 }, { actor = zack, kind = 7 } }
    world.enemies = { anchor, bomb }
    -- As in the game: the fight begins first, Custom Training writes its start a moment later.
    world.in_battle = true
    tick()
    assert(not logged("native helper"), "not a course fight yet")
    hit(5000, "Cloud", "EN0000_Field")       -- before the course: thrown away
    course({ what = "start", active = true, behaviour = "passive", opponent = "EN2001_00", name = "Bomb", count = 1,
        difficulty = "normal", anchor = "EN9999_Anchor_C_77" })
    tick()
    assert(logged("the meters' native helper is hooked"), "native said")
    assert(#queue == 0, "stale hits discarded")
    assert(shown and shown.tabs[1].current and shown.subtitle == "Bomb, Passive", "Damage first in Passive")
    assert(shown_at.x == 1468 and shown_at.y == 48, "drawn clear of Battle Meters")
    assert(get(MOD .. "meters-state.txt") == "meter=damage\nlabel=Damage\nvisible=true\n", "state published")

    assert(get(MOD .. "meters-active.txt"), "marker for Battle Meters while the course runs")

    -- Cloud hits the Bomb for 700, Zack for 300; the anchor loses HP too (left out).
    hit(700, "Cloud", "EN2001_00"); hit(300, "ZACK", "EN2001_00")
    world.hp[bomb], world.hp[anchor] = 99000, 50
    game_time = 1
    tick()
    local rows = {}
    for _, r in ipairs(shown.rows) do rows[r.name] = r.total end
    assert(shown.stats[2][2] == "1,000", "total excludes the anchor: " .. tostring(shown.stats[2][2]))
    assert(rows.Cloud == "700" and rows.Zack == "300", "split by who dealt it")

    -- F6 clears the stagger of the staggered Bomb, not the anchor's.
    world.burst[bomb], world.burst[anchor] = true, true
    keys.F6()
    tick()
    assert(world.ended[bomb] and not world.ended[anchor], "stagger cleared on the Bomb only")
    assert(logged("stagger cleared on 1"))

    -- Custom Training's menu, through the development command file: next meter, then Healing directly.
    put(MOD .. "meters-command.txt", "next\n")
    tick()
    assert(get(MOD .. "meters-command.txt") == nil, "command taken")
    assert(shown.tabs[2].current and get(MOD .. "meters-state.txt"):find("meter=taken"), "Tanking")

    -- The behaviour changes to Healing: Healing meter, numbers cleared.
    course({ what = "change", active = true, behaviour = "healing", opponent = "EN2001_00", name = "Bomb", count = 1,
        difficulty = "normal", anchor = "EN9999_Anchor_C_77" })
    tick()
    assert(shown.tabs[3].current and shown.stats[2][2] == "0", "Healing, cleared")
    -- Custom Training drops both to 1% (not damage taken), then Cloud heals Zack: 2,000 of a 3,000 Cure lands.
    world.hp[cloud], world.hp[zack] = 70, 69
    game_time = 2
    tick()
    hit(3000, "Cloud", "ZACK", true)
    world.hp[zack] = 2069
    game_time = 3
    tick()
    rows = {}
    for _, r in ipairs(shown.rows) do rows[r.name] = r.total end
    assert(shown.stats[2][2] == "2,000" and rows.Cloud == "2,000", "heal credited to Cloud, capped")
    -- Custom Training's MP refill counts (ct-mp.txt): 12, then 30 in all, so 30 spent; healing per MP 2,000 / 30.
    put(tmp .. sep .. "SimOverhaulCustomTraining" .. sep .. "ct-mp.txt", "mp.Cloud=12\n")
    tick()
    put(tmp .. sep .. "SimOverhaulCustomTraining" .. sep .. "ct-mp.txt", "mp.Cloud=30\n")
    tick()
    assert(shown.stats[4][1] == "MP spent" and shown.stats[4][2] == "30" and shown.stats[5][2] == "67",
        "MP from Custom Training: " .. tostring(shown.stats[4][2]))
    keys.F9()   -- to Damage, then back to Tanking: nothing taken
    tick()
    keys.F9()
    tick()
    assert(shown.tabs[2].current and shown.stats[2][2] == "0", "the 1% hold isn't damage taken")

    -- F5 clears; F8 hides and the choice is saved.
    keys.F5()
    tick()
    assert(logged("meters cleared %(asked%)"))
    keys.F8()
    tick()
    assert(shown == nil and get(MOD .. "settings.txt"):find("meters_visible = off"), "hidden and saved")
    keys.F8()
    tick()
    assert(shown ~= nil, "shown again")

    -- Apply with another opponent mid-fight: Custom Training removes the Bomb (99,000 HP left) and brings a Titan. No
    -- damage from the removal (seen 2026-11-21: 84,186 unattributed), and the Titan's numbers count as usual. Game time
    -- stays at 3 s, so meters.json keeps the Healing tick checked at the end.
    put(MOD .. "meters-command.txt", "meter=damage\n")
    course({ what = "change", active = true, behaviour = "healing", opponent = "EN0100_00", name = "Titan", count = 1,
        difficulty = "normal", anchor = "EN9999_Anchor_C_77" })
    tick()
    assert(logged("meters cleared %(change healing%)") and shown.tabs[1].current, "cleared, on Damage")
    world.enemies = { anchor }
    tick()
    local titan = actor("EN0100_00_Titan_C_4", "EN0100_00", 120000)
    world.enemies = { anchor, titan }
    tick()
    assert(shown.stats[2][2] == "0", "the removed Bomb counted nothing: " .. tostring(shown.stats[2][2]))
    hit(1500, "Cloud", "EN0100_00")
    world.hp[titan] = 118500
    tick()
    rows = {}
    for _, r in ipairs(shown.rows) do rows[r.name] = r.total end
    assert(shown.stats[2][2] == "1,500" and rows.Cloud == "1,500", "the Titan's damage counts")
    assert(shown.wave == nil, "no wave line without Custom Training's waves")

    -- Waves (owner, 2026-11-21; real conditions only in Aggressive, but a wave counts the same anywhere; the line
    -- shows in Healing only once a wave was cleared). The Titan is killed (only the HP it had counts, though the
    -- blow was bigger), Custom Training removes it, a new Titan spawns as wave 2. The numbers keep running; the new
    -- Titan's full HP isn't damage or healing; the panel shows the wave and the last clear time.
    course({ what = "change", active = true, behaviour = "healing", opponent = "EN0100_00", name = "Titan", count = 1,
        difficulty = "normal", anchor = "EN9999_Anchor_C_77", wave = 1, wave_started = 0 })
    tick()
    assert(not logged("wave 1") and shown.wave == nil, "Healing, nothing cleared yet: no line: " .. tostring(shown.wave))
    hit(200000, "Zack", "EN0100_00")
    world.hp[titan] = 0
    tick()
    world.enemies = { anchor }
    tick()
    -- Cleared, waiting for the respawn: only the anchor is left, and the panel stays (seen 2026-11-21: it went away).
    assert(shown ~= nil and shown.stats[2][2] == "120,000", "the panel stays while the round waits")
    local titan2 = actor("EN0100_00_Titan_C_5", "EN0100_00", 120000)
    world.enemies = { anchor, titan2 }
    course({ what = "wave", active = true, behaviour = "healing", opponent = "EN0100_00", name = "Titan", count = 1,
        difficulty = "normal", anchor = "EN9999_Anchor_C_77", wave = 2, wave_started = 83.4, last_clear = 83.4 })
    tick()
    assert(logged("wave 2 %(last clear 83.4 s%)") and not logged("meters cleared %(wave"), "a wave doesn't clear")
    assert(shown.wave == "Wave 2   Last clear 1:23", "wave line: " .. tostring(shown.wave))
    rows = {}
    for _, r in ipairs(shown.rows) do rows[r.name] = r.total end
    assert(shown.stats[2][2] == "120,000" and rows.Cloud == "1,500" and rows.Zack == "118,500",
        "the kill counts the Titan's last 118,500, the new one nothing: " .. tostring(shown.stats[2][2]))
    hit(700, "Cloud", "EN0100_00")
    world.hp[titan2] = 119300
    tick()
    assert(shown.stats[2][2] == "120,700" and shown.wave == "Wave 2   Last clear 1:23", "wave 2 counts on")
    -- Respawned mid-fight (F4 or the menu): wave 3 with no clear time for the wave cut short. The living Titan is
    -- removed with its HP; a hit on it that no reading showed yet would otherwise count as the blow that killed it.
    course({ what = "wave", active = true, behaviour = "healing", opponent = "EN0100_00", name = "Titan", count = 1,
        difficulty = "normal", anchor = "EN9999_Anchor_C_77", wave = 3, wave_started = 120 })
    tick()
    hit(5000, "Cloud", "EN0100_00")
    local titan3 = actor("EN0100_00_Titan_C_6", "EN0100_00", 120000)
    world.enemies = { anchor, titan3 }
    tick()
    assert(logged("wave 3 %(last clear nil s%)") and shown.wave == nil, "cut short, no clear in Healing: " .. tostring(shown.wave))
    assert(shown.stats[2][2] == "120,700", "the removed living Titan counted nothing: " .. tostring(shown.stats[2][2]))
    -- A behaviour change keeps the opponents in the fight: the numbers clear, but the Titan's last blow, landing
    -- between two readings, still counts (seen 2026-11-21: lost after Passive to Aggressive).
    course({ what = "change", active = true, behaviour = "aggressive", opponent = "EN0100_00", name = "Titan", count = 1,
        difficulty = "normal", anchor = "EN9999_Anchor_C_77", wave = 3, wave_started = 120 })
    tick()
    assert(logged("meters cleared %(change aggressive%)") and shown.stats[2][2] == "0", "cleared")
    hit(4000, "Cloud", "EN0100_00")
    world.enemies = { anchor }
    tick()
    put(MOD .. "meters-command.txt", "meter=damage\n")
    tick()
    assert(shown.stats[2][2] == "4,000", "the last blow after a behaviour change counts: " .. tostring(shown.stats[2][2]))

    -- Paused: hidden while paused.
    paused = true
    tick()
    assert(shown == nil, "hidden while paused")
    paused = false
    tick()
    assert(shown ~= nil)

    -- The course ends: the last numbers stay a moment, then go.
    world.in_battle = false
    course({ what = "end", active = false, behaviour = "healing" })
    tick()
    assert(shown ~= nil and logged("course ended"), "lingers")
    assert(get(MOD .. "meters-active.txt") == nil, "marker gone")
    local real_time = os.time
    os.time = function() return real_time() + 60 end
    tick()
    os.time = real_time
    assert(shown == nil, "gone after the linger")
    -- meters.json is written at most twice a second of game time: the last write was the Healing tick at 3 s.
    local json = get(MOD .. "meters.json")
    assert(json:find('"meter":"heal"', 1, true) and json:find('"strict":true', 1, true)
        and json:find('"behaviour":"healing"', 1, true) and json:find('"Cloud":2000.000', 1, true), "meters.json: " .. tostring(json))
end)
print = real_print
for _, f in ipairs({ "dev.txt", "settings.txt", "meters-state.txt", "meters-log.txt", "meters.json" }) do os.remove(MOD .. f) end
os.remove(COURSE)
if not ok then
    for _, l in ipairs(logs) do real_print(l) end
    error(err)
end
