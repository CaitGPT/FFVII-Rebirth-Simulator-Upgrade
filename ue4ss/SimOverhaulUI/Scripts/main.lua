-- Simulator Overhaul: Custom Training's settings in the game's own UI (development build of the ui workstream).
-- Start-up and the loop only: ui_menu.lua runs the menu, ui_model.lua decides what it shows, ui_window.lua talks to
-- the game, ui_ct.lua talks to Custom Training (its ct_api, or files during development).
-- The integrated mod sets SIM_OVERHAUL_DIR to the SimulatorOverhaul folder (docs/COORDINATION.md, "The integrated mod").
local MOD_DIR = rawget(_G, "SIM_OVERHAUL_DIR") or (debug.getinfo(1, "S").source:match("^@(.*[\\/])[Ss]cripts[\\/]")) or ""
-- Development only: Custom Training's own folder, for the file bridge (ui_ct.lua) when ct_api can't be required.
local CT_DIR = (MOD_DIR:gsub("[^\\/]+[\\/]$", "")) .. "SimOverhaulCustomTraining/"
local METERS_DIR = (MOD_DIR:gsub("[^\\/]+[\\/]$", "")) .. "SimOverhaulMeters/"
local QUIET_TICKS = 200 -- 10 s of the 50 ms loop
local LOG_PATH = MOD_DIR .. "ui-log.txt"
local COMMAND_PATH = MOD_DIR .. "ui-command.txt"
local DUMP_PATH = MOD_DIR .. "ui-dump.txt"
local TICK_MS, IDLE_TICKS, WATCH_TICKS = 50, 20, 2 -- every 50 ms while the menu is open; the chord every 100 ms in a
                                                    -- Custom Training fight; once a second otherwise

-- Register this mod's game-thread callback while mods load: a first ExecuteInGameThread during play can crash.
pcall(ExecuteInGameThread, function() end)

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close() end
    return f ~= nil
end
local DEV = exists(MOD_DIR .. "dev.txt")

local function log(message)
    print("[SimOverhaulUI] " .. message .. "\n")
    if not DEV then return end
    local out = io.open(LOG_PATH, "ab")
    if out then out:write(os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\t" .. message .. "\n"); out:close() end
end

local function read(path)
    local f = io.open(path, "rb")
    local text = f and f:read("a") or nil
    if f then f:close() end
    return text
end

local function write(path, text)
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "wb")
    if not f then return false end
    f:write(text); f:close()
    os.remove(path)
    return os.rename(tmp, path) == true
end

local settings = { menu_key = "F7", back_keys = "ESCAPE,BACKSPACE", pause = "on", chord = "on" }
for line in (read(MOD_DIR .. "settings.txt") or ""):gmatch("[^\r\n]+") do
    local k, v = line:match("^%s*ui_([%w_]+)%s*=%s*(.-)%s*$")
    if k and settings[k] ~= nil then settings[k] = v end
end

local game = require("ui_window")
local ct_module = require("ui_ct")
local keys = require("ui_keys")
local menu_module = require("ui_menu")
local meters_module = require("ui_meters")

-- Custom Training: its own module in the integrated mod, else (development) its files.
local ct
local api_ok, api = pcall(require, "ct_api")
if api_ok and type(api) == "table" and type(api.apply) == "function" then
    ct = ct_module.direct(api)
else
    ct = ct_module.bridge(CT_DIR, { read = read, write = write, exists = exists }, log, game.lookup)
end

-- The meters part, when present: its own module integrated, else (development) its files; none, no meter rows.
local meters
local m_ok, m_api = pcall(require, "meters_api")
if m_ok and type(m_api) == "table" and type(m_api.act) == "function" then
    meters = meters_module.direct(m_api)
else
    meters = meters_module.bridge(METERS_DIR, { read = read, write = write, exists = exists }, log)
end

local menu = menu_module.new({
    game = game, ct = ct, meters = meters, keys = keys, log = log,
    options = { pause = settings.pause ~= "off", chord = settings.chord ~= "off", debug = DEV },
})

-- The loop's count (50 ms each), declared before the commands that read it.
local ticks, course = 0, false

-- Development commands (ui-command.txt, one line): "menu" opens or closes the menu; "pick N" closes the open window as
-- if row N (0-based, -1 cancelled) had been confirmed; "draft k=v ..." sets the main window's values; "pause on|off"
-- whether the menu pauses the game; "focus N" puts the cursor on row N of the open window; "inputmode" gives the input
-- back to the game; "keys" logs the chord's keys as read now; "lists" writes ui-lists.txt; "dump" writes the open
-- window's widgets to ui-dump.txt; "probe N" opens a plain window with N rows (dumped a second later), "probe close"
-- closes it; "probe pause" dumps the game's pause menu if it is open; "syskeys" logs B, A, Esc, LB and RB as the game's
-- system input reads them; "hookback" logs every UEndMenuAPI Key_IsVirtualBack/Accept call from then on.
local probe_window, probe_at, hooked_back
local function dump_to_file(w, title)
    local lines = { title }
    game.dump(w, function(line) lines[#lines + 1] = line end)
    write(DUMP_PATH, table.concat(lines, "\n") .. "\n")
    log("dump\t" .. title .. "\t" .. #lines .. " lines")
end

local function command()
    if not DEV or not exists(COMMAND_PATH) then return end
    local text = read(COMMAND_PATH) or ""
    os.remove(COMMAND_PATH)
    log("command\t" .. text:gsub("%s+$", ""))
    if text:match("^%s*menu") then menu:request() end
    local n = text:match("pick%s+(%-?%d+)")
    if n then menu:pick(tonumber(n)) end
    local pz = text:match("^%s*pause%s+(%a+)")
    if pz then menu.options.pause = pz ~= "off"; log("pause\t" .. tostring(menu.options.pause)) end
    local dr = text:match("^%s*draft%s+(.+)")
    if dr then
        local values = {}
        for k, v in dr:gmatch("([%w_]+)=(%S+)") do values[k] = v end
        log("draft\t" .. tostring(menu:set_draft(values)))
    end
    local fr = text:match("^%s*focus%s+(%d+)")
    if fr and menu.rows then
        local i = tonumber(fr)
        local how = game.focus(menu.rows, menu.list, i, 1)
        log("focus\tdev row " .. i .. "\tby " .. tostring(how))
    end
    if text:match("^%s*inputmode") then log("inputmode\tgame only\t" .. tostring(game.reset_input())) end
    if text:match("^%s*keys") then
        local down = game.keys_down(keys.OPEN_CHORD)
        log("keys\tLB " .. tostring(down.Gamepad_LeftShoulder) .. "\tRB " .. tostring(down.Gamepad_RightShoulder)
            .. "\tin battle " .. tostring(game.in_battle()) .. "\tpaused " .. tostring(game.paused())
            .. "\tcontroller " .. tostring(game.valid(game.controller())))
    end
    if text:match("^%s*syskeys") then
        local names = { "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Bottom", "Escape", "Gamepad_LeftShoulder", "Gamepad_RightShoulder" }
        local down = game.system_keys_down(names)
        local parts = {}
        for _, k in ipairs(names) do parts[#parts + 1] = k .. "=" .. tostring(down[k] == true) end
        log("syskeys\t" .. table.concat(parts, " ") .. "\tmenu " .. tostring(menu.screen))
    end
    -- Whether the game's widgets ask UEndMenuAPI which keys are back and accept (B, A, Esc) while the window is open.
    if text:match("^%s*hookback") and not hooked_back then
        hooked_back = true
        for _, fn in ipairs({ "Key_IsVirtualBack", "Key_IsVirtualAccept" }) do
            local ok, err = pcall(RegisterHook, "/Script/EndGame.EndMenuAPI:" .. fn, function(_, key)
                local name = game.safe(function() return key:get().KeyName:ToString() end)
                log("hook\t" .. fn .. "\t" .. tostring(name) .. "\tmenu " .. tostring(menu.screen))
            end)
            log("hookback\t" .. fn .. "\t" .. tostring(ok) .. "\t" .. tostring(err))
        end
    end
    if text:match("^%s*lists") then
        local l = ct.lists()
        local lines = {}
        for _, o in ipairs(l and l.opponents or {}) do
            -- The room it needs (metres, empty for any stage) after the name.
            lines[#lines + 1] = table.concat({ #o.name, o.kind, o.kind_name or "", tostring(o.max_count or ""), o.id, o.name,
                                               tostring(o.needs_m or "") }, "\t")
        end
        write(MOD_DIR .. "ui-lists.txt", table.concat(lines, "\n") .. "\n")
        log("lists\t" .. #lines .. " opponents")
        -- With pre-built rounds: ui-rounds.txt, course and round lines (tab id, course id, round id, the row's text,
        -- the room it needs), and the stage loaded (its name and room; empty on the plain arena).
        local rl = {}
        local st = ct.state() or {}
        rl[#rl + 1] = table.concat({ "stage", tostring(st.stage_name or l and l.stage_name or ""),
                                     tostring(st.room_m or l and l.room_m or "") }, "\t")
        for _, t in ipairs(l and l.tabs or {}) do rl[#rl + 1] = table.concat({ "tab", tostring(t.id), t.name }, "\t") end
        for _, c in ipairs(l and l.courses or {}) do
            rl[#rl + 1] = table.concat({ "course", tostring(c.tab), c.id, c.name }, "\t")
            for _, r in ipairs(c.rounds or {}) do
                rl[#rl + 1] = table.concat({ "round", tostring(c.tab), c.id, r.id, require("ui_model").round_label(r),
                                             tostring(r.needs_m or "") }, "\t")
            end
        end
        write(MOD_DIR .. "ui-rounds.txt", table.concat(rl, "\n") .. "\n")
        log("lists\t" .. #rl .. " stage, course and round lines")
    end
    if text:match("^%s*dump") then
        if menu.window then dump_to_file(menu.window, "menu window " .. tostring(menu.screen))
        elseif probe_window then dump_to_file(probe_window, "probe window") end
    end
    local p = text:match("^%s*probe%s+(%S+)")
    if p == "close" then
        if probe_window then game.hide(probe_window); probe_window = nil; game.pause(false) end
    elseif p == "pause" then
        local w = game.safe(FindFirstOf, "Pause_00_C")
        if game.valid(w) then dump_to_file(w, "pause menu") else log("probe\tno Pause_00_C") end
    elseif p and tonumber(p) then
        local options = {}
        for i = 1, tonumber(p) do options[i] = "Row " .. i end
        probe_window = game.show("Probe window\n<button=decide> Choose", options)
        probe_at = ticks
        game.pause(true)
        log("probe\twindow " .. p .. " rows\t" .. tostring(probe_window ~= nil))
    end
end

local key_pressed = false
pcall(RegisterKeyBind, Key[settings.menu_key] or Key.F7, function() key_pressed = true end)
local back_pressed = false
for name in settings.back_keys:gmatch("[%w_]+") do
    if Key[name:upper()] then pcall(RegisterKeyBind, Key[name:upper()], function() back_pressed = true end) end
end

-- Battle functions only once a party character has been possessed: calls from the title screen have crashed the game
-- (Training Dummy). In battle there is no pawn, so having seen one is remembered.
local armed, engine = false, nil
local function check_armed()
    if armed then return true end
    local statics = game.cdo("/Script/Engine.Default__GameplayStatics")
    if not game.valid(engine) then engine = game.safe(FindFirstOf, "GameEngine") end
    local viewport = game.valid(engine) and game.safe(function() return engine.GameViewport end)
    local pawn = statics and game.valid(viewport) and game.safe(function() return statics:GetPlayerPawn(viewport, 0) end)
    local class = game.valid(pawn) and game.class_name(pawn) or ""
    armed = class:match("^PC%d%d%d%d_") ~= nil
    if armed then log("armed\t" .. class .. "\tct " .. ct.kind) end
    return armed
end

LoopAsync(TICK_MS, function()
    ticks = ticks + 1
    local wanted = menu:is_open() or key_pressed or (course and ticks % WATCH_TICKS == 0) or ticks % IDLE_TICKS == 0
        or (DEV and ticks % WATCH_TICKS == 0 and (exists(COMMAND_PATH) or probe_window ~= nil))
    -- No game call in the first seconds after mods load (docs/COORDINATION.md, "The integrated mod", rule 7).
    if not wanted or ticks < QUIET_TICKS then key_pressed, back_pressed = false, false; return false end
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            if not check_armed() then key_pressed = false; return end
            command()
            if probe_window and probe_at and ticks - probe_at > 20 then
                probe_at = nil
                dump_to_file(probe_window, "probe window")
            end
            if key_pressed then key_pressed = false; menu:request() end
            if back_pressed then back_pressed = false; menu:back() end
            if ticks % IDLE_TICKS == 0 then course = ct.active() end
            ct.poll()
            -- Seconds from the loop's own count: os.clock is the process's CPU time, which runs ahead of the wall clock.
            if course or menu:is_open() or menu.requested then menu:tick(ticks * TICK_MS / 1000) end
        end)
        if not ok then log("tick\terror\t" .. tostring(err)) end
    end)
    return false
end)

log("loaded\tdev " .. tostring(DEV) .. "\tct " .. ct.kind .. "\tmeters " .. meters.kind .. "\tkey " .. settings.menu_key)
