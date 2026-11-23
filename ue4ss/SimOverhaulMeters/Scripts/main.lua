-- Simulator Overhaul: the meters panel in Custom Training (development build of the meters workstream).
-- Start-up, keys and the loop only. Counting: meters_tracker.lua; what the panel shows: meters_view.lua; drawing:
-- meters_overlay.lua; game calls: meters_game.lua; Custom Training's course: meters_course.lua; settings and
-- controls: meters_controls.lua; the interface for Custom Training's menu: meters_api.lua.
local function mod_dir()
    for entry in (package.path or ""):gmatch("[^;]+") do
        local dir = entry:match("^(.-[\\/]SimOverhaulMeters[\\/])[Ss]cripts[\\/]")
        if dir then return dir end
    end
    return ""
end
-- The integrated mod sets SIM_OVERHAUL_DIR (docs/COORDINATION.md, "The integrated mod"); the offline test its own.
local MOD_DIR = rawget(_G, "SIM_OVERHAUL_DIR") or rawget(_G, "SIMOVERHAUL_METERS_TEST_DIR") or mod_dir()
local MODS_DIR = MOD_DIR:match("^(.*[\\/])[^\\/]+[\\/]$") or ""
local SETTINGS_PATH = MOD_DIR .. "settings.txt"
local LOG_PATH = MOD_DIR .. "meters-log.txt"
local COMMAND_PATH = MOD_DIR .. "meters-command.txt"
local STATE_PATH = MOD_DIR .. "meters-state.txt"
-- Present while a Custom Training course runs, so Battle Meters can stand aside (proposed to the parent, 2026-11-21).
local ACTIVE_PATH = MOD_DIR .. "meters-active.txt"
local COURSE_PATH = MODS_DIR .. "SimOverhaulCustomTraining" .. package.config:sub(1, 1) .. "ct-course.txt"
local MP_PATH = MODS_DIR .. "SimOverhaulCustomTraining" .. package.config:sub(1, 1) .. "ct-mp.txt"
local TICK_MS, IDLE_TICKS = 200, 5      -- 200 ms in a course, once a second elsewhere
local QUIET_SECONDS = rawget(_G, "SIMOVERHAUL_METERS_TEST_DIR") and 0 or 20   -- no game calls this soon after load
local LOADED_AT = os.time()

-- Register this mod's game-thread callback while mods load: a first ExecuteInGameThread during play can crash.
pcall(ExecuteInGameThread, function() end)

local function read(path)
    local f = io.open(path, "rb")
    local text = f and f:read("a") or nil
    if f then f:close() end
    return text
end
local function write(path, text)
    local f = io.open(path .. ".tmp", "wb")
    if not f then return false end
    f:write(text); f:close()
    os.remove(path)
    return os.rename(path .. ".tmp", path) == true
end
local DEV = read(MOD_DIR .. "dev.txt") ~= nil

local function log(message)
    print("[SimOverhaulMeters] " .. message .. "\n")
    if not DEV then return end
    local f = io.open(LOG_PATH, "ab")
    if f then f:write(os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\t" .. message .. "\n"); f:close() end
end

os.remove(ACTIVE_PATH)   -- left from a game that closed mid-course
local controls_module = require("meters_controls")
local Tracker = require("meters_tracker")
local Course = require("meters_course")
local view_module = require("meters_view")
local game = require("meters_game")
local api = require("meters_api")
local native_ok, native = pcall(require, "meters_native")
local overlay_ok, overlay = pcall(require, "meters_overlay")
local samples = require("meters_samples")
-- In the integrated mod Custom Training is in this Lua state; during development it is read from its file.
local ct_ok, ct = pcall(require, "ct_api")
if not ct_ok or type(ct) ~= "table" then ct = nil end

local settings = controls_module.parse(read(SETTINGS_PATH))
local controls = controls_module.new(settings)

-- Battle Meters, from its installed files once (no game calls): 1.2.0 and later stand aside while meters-active.txt
-- exists; beside an older one that is switched on, our panel moves to the top right, clear of its panel.
local SEP = package.config:sub(1, 1)
local bm_dir = MODS_DIR .. "BattleMeters" .. SEP
local bm = controls_module.battle_meters(read(bm_dir .. "Scripts" .. SEP .. "main.lua"),
    read(bm_dir .. "Scripts" .. SEP .. "config.lua"),
    controls_module.mod_enabled(read(MODS_DIR .. "mods.txt"), "BattleMeters", read(bm_dir .. "enabled.txt") ~= nil))
local panel = {}
panel.x, panel.y, panel.why = controls_module.place(settings, bm)
api.bind(controls)
local tracker = Tracker.new(settings.window)
local course = Course.new()
local state = { linger_until = nil, last_json = 0, keys = {}, in_battle = false, stand = nil, native = nil }

local function save_settings()
    write(SETTINGS_PATH, controls_module.render(settings, read(SETTINGS_PATH)))
end
local function publish_state()
    local text = controls_module.format_state(controls:state())
    if text ~= state.published then
        state.published = text
        write(STATE_PATH, text)
    end
end

-- Keys arrive off the game thread: they only leave a note.
local function bind(key_name, action)
    local key = Key[key_name]
    if not key then log("unknown key " .. tostring(key_name)); return end
    local ok, err = pcall(RegisterKeyBind, key, function() state.keys[#state.keys + 1] = action end)
    if not ok then log("key " .. key_name .. " unavailable: " .. tostring(err)) end
end
bind(settings.next_key, "next")
bind(settings.clear_key, "clear")
bind(settings.stagger_key, "stagger")
bind(settings.toggle_key, "toggle")

if ct then
    ct.on_course(function(event) state.course_event = event end)
end

local function course_state()
    if ct then
        local event = state.course_event or ct.state()
        state.course_event = nil
        if type(ct.mp_refilled) == "function" then event.mp, event.mp_counts = ct.mp_refilled(), true end
        return event
    end
    -- MP refill counts are a separate file (ct-mp.txt, mp.<Name>=<total> lines), so a refill never looks like a change.
    local course_now = Course.parse(read(COURSE_PATH))
    local mp_text = read(MP_PATH)
    if mp_text then course_now.mp, course_now.mp_counts = Course.parse(mp_text).mp, true end
    return course_now
end

-- outgoing: Custom Training is replacing the opponents (the tracker counts nothing for those leaving).
local function clear(why, outgoing)
    tracker:reset(outgoing)
    if native_ok and state.native == "ok" then native.discard() end
    log("meters cleared (" .. why .. ")")
end

-- Every action, from a key, Custom Training's menu (meters_api) or the development command file.
local function actions()
    local list = {}
    for _, a in ipairs(state.keys) do list[#list + 1] = a end
    state.keys = {}
    for _, a in ipairs(api.take()) do list[#list + 1] = a end
    if DEV or not ct then
        -- Renamed before it is read, so a line another part appends meanwhile goes to a new file, not lost.
        local taking = COMMAND_PATH .. ".taking"
        local text = os.rename(COMMAND_PATH, taking) and read(taking) or nil
        if text then
            os.remove(taking)
            for _, a in ipairs(controls_module.commands(text)) do
                -- Development only: "sample <name>" shows made-up numbers for layout screenshots, "sample off" stops.
                local sample = DEV and a:match("^sample%s+(%w+)$")
                if sample then
                    state.sample = samples.get(sample)
                    log("sample " .. sample .. (state.sample and "" or " (none)"))
                else
                    list[#list + 1] = a
                end
            end
        end
    end
    return list
end

local function json_number(v) return string.format("%.3f", v or 0) end
local function write_json(snapshot)
    local parts = {}
    for kind, k in pairs(snapshot.kinds) do
        local sources = {}
        for name, amount in pairs(k.by_source or {}) do
            sources[#sources + 1] = string.format('"%s":%s', (name:gsub('[%c"\\]', "")), json_number(amount))
        end
        table.sort(sources)
        parts[#parts + 1] = string.format('"%s":{"average":%s,"recent":%s,"total":%s,"biggest":%s,"by_source":{%s}}',
            kind, json_number(k.average), json_number(k.recent), json_number(k.total), json_number(k.biggest),
            table.concat(sources, ","))
    end
    local c = course.state
    write(MOD_DIR .. "meters.json", string.format(
        '{"meter":"%s","visible":%s,"strict":%s,"behaviour":"%s","elapsed":%s,"time":%d,"meters":{%s}}',
        controls.meter, tostring(controls.visible), tostring(snapshot.strict == true), tostring(c.behaviour or ""),
        json_number(snapshot.elapsed), os.time(), table.concat(parts, ",")))
end

local function hide()
    if overlay_ok and overlay.shown() then game.safe(overlay.hide) end
end

local function draw(snapshot, world_object)
    state.view = view_module.build(snapshot, controls.meter, course.state, settings)
    if snapshot.sample then state.view.note = "Sample numbers (" .. snapshot.sample .. "), development only" end
    if not (overlay_ok and controls.visible) or game.paused(world_object) then hide(); return end
    local ok, shown = pcall(overlay.show, state.view, panel, world_object)
    if not ok then log("overlay error: " .. tostring(shown)) end
end

-- Battle functions only once a save is loaded ("armed"): calls from the title screen crashed the game.
local armed = false
local function tick()
    -- Custom Training's course: start, change, end.
    local event, behaviour_changed = course:update(course_state())
    if event == "start" or event == "change" then
        if event == "start" or behaviour_changed then controls:follow(course.state.behaviour) end
        -- Opponents Custom Training replaces count nothing when they go; after a behaviour change they stay in the
        -- fight, and their last blow counts (seen 2026-11-21: a Zu's last 2,000 or so lost after Passive to Aggressive).
        clear(event .. " " .. tostring(course.state.behaviour), course.replaced)
        state.linger_until = nil
    elseif event == "end" then
        state.linger_until = os.time() + settings.linger
        log("course ended")
    elseif event == "wave" then
        -- A respawn: the numbers keep running (F5 clears); enemies removed with it count nothing.
        tracker:outgoing()
        log(string.format("wave %s (last clear %s s)", tostring(course.state.wave), tostring(course.state.last_clear)))
    end
    if event == "end" then os.remove(ACTIVE_PATH) end

    local stagger = false
    for _, action in ipairs(actions()) do
        local todo, understood = controls:act(action)
        log("action " .. action .. (understood and "" or " (not understood)"))
        if todo == "clear" then clear("asked") elseif todo == "stagger" then stagger = true
        elseif todo == "save" then save_settings() end
    end
    publish_state()

    if os.time() - LOADED_AT < QUIET_SECONDS then return end
    if not armed then armed = game.gameplay_pawn() ~= nil end
    if not armed then return end
    local battle = game.battle()
    if not battle then return end
    local in_battle = game.in_battle(battle)
    -- A Custom Training fight begins when both are true, in either order: Custom Training writes its start a moment
    -- after the fight begins (seen 2026-11-21), or before it on a Rechallenge. Each one is a new attempt.
    local fighting = course:active() and in_battle
    if fighting and not state.marked then
        if state.native == nil and native_ok then
            state.native = native.status()
            log("hit events: " .. (state.native == "ok" and "the meters' native helper is hooked"
                or ("native helper " .. state.native .. ", so party numbers follow HP rules and damage is a total")))
        end
        clear("fight started")
    end
    -- The marker for Battle Meters: only while a Custom Training fight is on. Custom Training's file can still say
    -- active after a game closed mid-course (seen 2026-11-21), and a field fight must not hide Battle Meters then.
    if fighting ~= state.marked then
        if fighting then write(ACTIVE_PATH, "Custom Training fight running: the Simulator Upgrade meters panel shows\n")
        else os.remove(ACTIVE_PATH) end
        state.marked = fighting
    end
    state.in_battle = in_battle

    if not (course:active() and in_battle) then
        -- After the course the last numbers stay for a moment, as Battle Meters' do after a battle.
        if state.linger_until and os.time() < state.linger_until and state.snapshot then
            -- On the result screen there is no pawn to draw with (seen 2026-11-21): the panel already shows the last
            -- numbers, so it is left as it is until the linger ends.
            local pawn = game.gameplay_pawn()
            if pawn then draw(state.snapshot, pawn) end
        else
            state.linger_until = nil
            hide()
        end
        return
    end

    local readings, actors, any_enemy = game.enemies(battle, course.state.anchor)
    local world = actors[1] or any_enemy
    if stagger then log(string.format("stagger cleared on %d", game.clear_stagger(battle, actors))) end
    local now = game.now(world)
    local hits = (native_ok and state.native == "ok") and native.drain() or nil
    tracker:tick({ now = now, behaviour = course.state.behaviour, native = state.native == "ok" and native_ok,
        party = game.party(battle), enemies = readings, hits = hits,
        mp_spent = course:counts_mp() and course:mp_spent() or nil })
    local snapshot = state.sample or tracker:snapshot(now)
    state.snapshot, state.world = snapshot, world
    if world then draw(snapshot, world) else hide() end
    if settings.json == "on" and now - state.last_json >= 0.5 then
        state.last_json = now
        game.safe(write_json, snapshot)
    end
end

-- Each ExecuteInGameThread allocates a Lua thread UE4SS never frees: full rate only in a course.
local idle = 0
LoopAsync(TICK_MS, function()
    idle = idle + 1
    if course:active() or state.linger_until or #state.keys > 0 or idle >= IDLE_TICKS then
        idle = 0
        ExecuteInGameThread(function()
            local ok, err = pcall(tick)
            if not ok then
                if state.last_error ~= tostring(err) then log("tick error: " .. tostring(err)) end
                state.last_error = tostring(err)
            end
        end)
    end
    return false
end)

if not overlay_ok then log("overlay disabled: " .. tostring(overlay)) end
if not native_ok then log("native hits disabled: " .. tostring(native)) end
log(string.format("loaded: meter keys %s/%s/%s/%s, course %s, panel at %d,%d (%s); Battle Meters %s", settings.next_key,
    settings.clear_key, settings.stagger_key, settings.toggle_key, ct and "through ct_api" or ("file " .. COURSE_PATH),
    panel.x, panel.y, panel.why, not bm.installed and "not installed" or string.format("%s, %s",
    bm.enabled and "on" or "off", bm.stands_aside and "stands aside" or "older (doesn't stand aside)")))
