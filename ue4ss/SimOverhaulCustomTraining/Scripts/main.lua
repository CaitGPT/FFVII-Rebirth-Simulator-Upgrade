-- Simulator Overhaul: Custom Training (development build of the custom-training workstream).
-- Start-up and the loop only; the work is in ct_session.lua (the visit), ct_panel*.lua (the settings panel),
-- ct_plan.lua (which enemies to spawn and remove) and ct_game.lua (game calls).
-- In the integrated mod (SimulatorOverhaul) the generated main.lua sets SIM_OVERHAUL_DIR to its folder.
local MOD_DIR = rawget(_G, "SIM_OVERHAUL_DIR") or (debug.getinfo(1, "S").source:match("^@(.*[\\/])[Ss]cripts[\\/]")) or ""
if MOD_DIR ~= "" and not MOD_DIR:match("[\\/]$") then MOD_DIR = MOD_DIR .. "/" end
local STARTUP_TICKS = 200 -- no game call in the first 10 s after mods load (docs/COORDINATION.md, integrated mod)
local SETTINGS_PATH = MOD_DIR .. "settings.txt"
local LOG_PATH = MOD_DIR .. "ct-log.txt"
local STATE_PATH = MOD_DIR .. "ct-state.json"
local COMMAND_PATH = MOD_DIR .. "ct-command.txt"
local ACTIVE_MS, IDLE_TICKS = 50, 20 -- the loop runs every 50 ms; the work every 200 ms in the course (every 50 ms
local COURSE_TICKS = 4               -- while the settings panel is open, for its keys), once a second elsewhere

-- Register this mod's game-thread callback while mods load: a first ExecuteInGameThread during play can crash.
pcall(ExecuteInGameThread, function() end)

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close() end
    return f ~= nil
end
local DEV = exists(MOD_DIR .. "dev.txt")

local function log(message)
    print("[SimOverhaulCustomTraining] " .. message .. "\n")
    if not DEV then return end
    local out = io.open(LOG_PATH, "ab")
    if out then out:write(os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\t" .. message .. "\n"); out:close() end
end

local function read(path)
    local f = io.open(path, "rb")
    local text = f and f:read("a") or ""
    if f then f:close() end
    return text
end

local settings_module = require("ct_settings")
local game = require("ct_game")
local catalogue = require("ct_catalogue")
local course_text = require("ct_course_text")
local session_module = require("ct_session")

local settings = settings_module.parse(read(SETTINGS_PATH))
local function save_settings()
    local text = settings_module.render(settings, read(SETTINGS_PATH))
    local out = io.open(SETTINGS_PATH .. ".tmp", "wb")
    if not out then return end
    out:write(text); out:close()
    os.remove(SETTINGS_PATH)
    os.rename(SETTINGS_PATH .. ".tmp", SETTINGS_PATH)
end

-- A file other mods read: written under a temp name, then renamed, so nobody reads half of it.
local function write_file(path, text)
    local tmp = path:gsub("%.%w+$", "") .. ".tmp"
    local out = io.open(tmp, "wb")
    if not out then return end
    out:write(text); out:close()
    os.remove(path)
    os.rename(tmp, path)
end

local api = require("ct_api")
-- For separate mods during development (meters, ui): the course's state in ct-course.txt on every start, end and
-- change, and the lists ui offers in ct-lists.txt at every start.
api.write_status = function(event)
    write_file(MOD_DIR .. "ct-course.txt", api.format(event))
    if event.what == "start" then write_file(MOD_DIR .. "ct-lists.txt", api.lists_text()) end
end

-- The meters part: its module in the integrated mod, else (development) its files beside this mod's folder:
-- meters-state.txt (meter=, visible=, label=) to read, meters-command.txt (one command per line) to write.
local function meters_part()
    local ok, m = pcall(require, "meters_api")
    if ok and type(m) == "table" and m.act and m.state then return m end
    local dir = (MOD_DIR:match("^(.*[\\/])[^\\/]+[\\/]$") or "") .. "SimOverhaulMeters/"
    return {
        state = function()
            local text = read(dir .. "meters-state.txt")
            if text == "" then return nil end
            local st = {}
            for k, v in text:gmatch("([%w_]+)=([^\r\n]*)") do st[k] = v end
            st.visible = st.visible ~= "false"
            return st
        end,
        act = function(command)
            write_file(dir .. "meters-command.txt", read(dir .. "meters-command.txt") .. command .. "\n")
        end,
    }
end

-- The ui part's menu replaces the panel (and takes F7 and LB+RB) when it is there.
local has_ui_menu = type(select(2, pcall(require, "ui_menu"))) == "table"

local session = session_module.new({
    game = game, catalogue = catalogue, settings = settings, save_settings = save_settings, log = log,
    clock = os.clock, emit = api.emit, meters = meters_part(),
    panel_blocked = function() return settings.panel == "off" or has_ui_menu end,
})
api.bind(session)

local function json_value(v)
    local t = type(v)
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local parts = {}
            for _, x in ipairs(v) do parts[#parts + 1] = json_value(x) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = string.format("%q:%s", tostring(k), json_value(x)) end
        table.sort(parts)
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "string" then return string.format("%q", v)
    elseif t == "number" or t == "boolean" then return tostring(v) end
    return "null"
end

local function write_state(status)
    if not DEV then return end
    -- Temp name, then rename: a reader once caught it half-written and took the course for over (2026-11-21).
    write_file(STATE_PATH, json_value(status))
end

-- Development installs only: ct-command.txt holds one command, so a test can drive the course without a keyboard:
-- "menu" shows or hides the settings panel, "key K" presses panel key K (up, down, left, right, select, back,
-- prev_kind, next_kind); several "key" words may share the line; "set opponent=ID count=N ..." applies settings
-- (also group=a,b,c round=ID mode=opponents|round).
local function command()
    if not DEV or not exists(COMMAND_PATH) then return end
    local text = read(COMMAND_PATH)
    os.remove(COMMAND_PATH)
    if text:match("^%s*menu") then session:request_menu() end
    if text:match("^%s*lists") then write_file(MOD_DIR .. "ct-lists.txt", api.lists_text()) end
    for key in text:gmatch("key%s+([%w_]+)") do session:inject_key(key) end
    if text:match("^%s*respawn") then log("command\trespawn\t" .. tostring(api.respawn())) end
    local hp = text:match("^%s*hp%s+(%d+)")
    if hp then session:set_member_hp(tonumber(hp)) end
    -- "set opponent=ID count=N behaviour=B difficulty=D": straight through ct_api.apply (the opponent sweep)
    local set = text:match("^%s*set%s+(.+)")
    if set then
        local changes = {}
        for k, v in set:gmatch("([%w_]+)=([%w_,]+)") do changes[k] = tonumber(v) or v end
        local ok, why = api.apply(changes)
        log("command	set	" .. tostring(ok) .. (why and ("	" .. why) or ""))
    end
    log("command\t" .. text:gsub("%s+$", ""))
end

local key_pressed = false
pcall(RegisterKeyBind, Key[settings.menu_key] or Key.F7, function() key_pressed = true end)
-- Respawn: the last chosen set again (owner 2026-11-21), in a running course only.
local respawn_pressed = false
pcall(RegisterKeyBind, Key[settings.respawn_key] or Key.F4, function() respawn_pressed = true end)

-- Course names in the simulator's menu (Training Dummy's way: our text keys swapped for text in the widgets).
local function hook_menu(name, fn)
    pcall(RegisterHook, "/Script/EndGame.EndColosseumMenu:" .. name, fn)
end
for _, name in ipairs({ "OnCourseMenuSetupItem", "OnCourseMenuSelectedIndexChanged", "OnCourseMenuPressedItem" }) do
    hook_menu(name, function(context) course_text.remember(game.safe(function() return context:get() end)) end)
end

-- Battle functions are called only once a party character has been possessed: calls from the title screen have
-- crashed the game (Training Dummy). In battle there is no pawn, so having seen one is remembered.
local armed, engine = false, nil
local function check_armed()
    if armed then return true end
    local statics = game.cdo("/Script/Engine.Default__GameplayStatics")
    if not game.valid(engine) then engine = game.safe(FindFirstOf, "GameEngine") end -- FindFirstOf walks every object
    local viewport = game.valid(engine) and game.safe(function() return engine.GameViewport end)
    local pawn = statics and game.valid(viewport) and game.safe(function() return statics:GetPlayerPawn(viewport, 0) end)
    local class = game.valid(pawn) and game.safe(function() return pawn:GetClass():GetFName():ToString() end) or ""
    armed = class:match("^PC%d%d%d%d_") ~= nil
    if armed then log("armed\t" .. class .. "\tnative difficulty: " .. tostring(rawget(_G, "CustomTrainingNativeStatus")
        and CustomTrainingNativeStatus() or "absent") ) end
    return armed
end

local ticks, active, was_active, mp_written = 0, false, false, nil
LoopAsync(ACTIVE_MS, function()
    ticks = ticks + 1
    if ticks < STARTUP_TICKS then key_pressed, respawn_pressed = false, false; return false end
    local panel = session:panel_open()
    local wanted = panel or key_pressed or respawn_pressed or (active and ticks % COURSE_TICKS == 0)
        or (course_text.has_work() and ticks % COURSE_TICKS == 0) or ticks % IDLE_TICKS == 0
        or (DEV and ticks % COURSE_TICKS == 0 and exists(COMMAND_PATH))
    if not wanted then return false end
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            if not check_armed() then return end
            command()
            if key_pressed then key_pressed = false; session:request_menu() end
            if respawn_pressed then
                respawn_pressed = false
                if session.active then session:respawn() end
            end
            if game.in_battle() then course_text.stop() else course_text.apply() end
            active = session:tick()
            if active or was_active then write_state(active and session.status or { active = false }) end
            was_active = active
            if session.mp_version ~= mp_written then
                mp_written = session.mp_version
                write_file(MOD_DIR .. "ct-mp.txt", api.mp_text())
            end
        end)
        if not ok then log("tick\terror\t" .. tostring(err)) end
    end)
    return false
end)

log("loaded\t" .. #catalogue.opponents .. " opponents\tdev " .. tostring(DEV))
