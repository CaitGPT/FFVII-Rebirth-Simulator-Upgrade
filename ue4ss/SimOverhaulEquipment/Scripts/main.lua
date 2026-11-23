-- Simulator Overhaul, equipment part (development build): the game's own main menu, opened from Chadley's
-- simulator menus (the course list and the screens after choosing a course) with a key or a pad button, shown by an
-- on-screen hint; never once a course has started. equipment/api.lua is the interface for the other parts.
-- docs/workstreams/equipment.md has what was seen in the game.

-- Register this mod's game-thread callback while mods load: a first ExecuteInGameThread during play can crash.
pcall(ExecuteInGameThread, function() end)

-- The mod's folder: the integrated mod (SimulatorUpgrade) sets SIM_OVERHAUL_DIR; on its own, from package.path
-- (debug.getinfo doesn't give it under UE4SS; No Popups' way).
local MOD_DIR = rawget(_G, "SIM_OVERHAUL_DIR")
if not MOD_DIR then
    MOD_DIR = ""
    for entry in package.path:gmatch("[^;]+") do
        local dir = entry:match("^(.-[\\/]SimOverhaulEquipment[\\/])[Ss]cripts[\\/]")
        if dir then MOD_DIR = dir; break end
    end
end

local settings_module = require("equipment.settings")
local course_module = require("equipment.course")
local api = require("equipment.api")
local game = require("equipment.game")
local hint = require("equipment.hint")
local devconsole = require("equipment.devconsole")

local function is_dev()
    local marker = io.open(MOD_DIR .. "dev.txt", "rb")
    if marker then marker:close() end
    return marker ~= nil
end
local dev = is_dev()

-- Start-up: no game calls in the first seconds after mods load (the integration rule). The simulator's hooks only
-- fire in play, and the loops below do game work only once these seconds have passed.
local LOADED_AT = os.clock()
local SETTLE_SECONDS = 10
local function settled() return os.clock() - LOADED_AT >= SETTLE_SECONDS end

local function log(message)
    print("[SimOverhaulEquipment] " .. message .. "\n")
    if not dev then return end
    local out = io.open(MOD_DIR .. "equipment-log.txt", "ab")
    if out then
        out:write(os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\t" .. message .. "\n")
        out:close()
    end
end
api.set_log(log)

local function read_settings()
    local file = io.open(MOD_DIR .. "settings.txt", "rb")
    local text = file and file:read("a") or ""
    if file then file:close() end
    local settings, problems = settings_module.parse(text)
    for _, problem in ipairs(problems) do log("settings\t" .. problem) end
    return settings
end
local settings = read_settings()

local course = course_module.new()
local menu_widget = nil   -- the simulator's menu (UEndColosseumMenu), from a hook's context
local key_pressed = false
api.set_guard(function()
    if course.started then return "course started" end
    return nil
end)

-- The simulator's menu events (native UFunctions, which Lua hooks do catch; Training Dummy hooks the same).
local function hook_menu(event, kind)
    local ok, err = pcall(RegisterHook, "/Script/EndGame.EndColosseumMenu:" .. event, function(context)
        local widget = game.safe(function() return context:get() end)
        if widget ~= nil then menu_widget = widget end
        course:event(kind, os.clock())
    end)
    if not ok then log("menu hook unavailable: " .. event .. " (" .. tostring(err) .. ")") end
end
hook_menu("OnCourseMenuSetupItem", "list")
hook_menu("OnCourseMenuSelectedIndexChanged", "list")
hook_menu("OnCourseMenuPressedItem", "chosen")
hook_menu("OnCharaSelectMenuSelectedIndexChanged", "team")
hook_menu("OnCharaSelectMenuPressedItem", "team")
hook_menu("OnSummonLevelSelectMenuSelectedIndexChanged", "team")
hook_menu("OnSummonLevelSelectMenuPressedItem", "team")
hook_menu("OnNoButtonPressed", "team")
hook_menu("OnYesButtonPressed", "confirmed")

local ok_key, key_err = pcall(RegisterKeyBind, Key[settings.key], function() key_pressed = true end)
if not ok_key then log("key " .. tostring(settings.key) .. " unavailable: " .. tostring(key_err)) end

-- The pad button (key binds don't see a pad): read through the player controller every 50 ms while the simulator's
-- menu is up, once per press.
local pad_button = course_module.new_button()
if settings.pad_button ~= "off" then
    LoopAsync(50, function()
        if course.armed and settled() and not api.is_open() then
            ExecuteInGameThread(function()
                local down = game.key_down(settings.pad_button)
                if course_module.pressed(pad_button, down) then
                    key_pressed = true
                    log("pad	" .. settings.pad_button)
                end
            end)
        else
            pad_button.down = false
        end
        return false
    end)
end

-- What the key and the hint look at. Game thread.
local function view()
    return {
        menu_visible = game.menu_on_screen(menu_widget),
        pause_closed = game.pause_menu_closed(),
        in_battle = game.in_battle(),
        busy = api.is_open(),
    }
end

local hint_problem = nil
local function show_hint(want)
    if settings.hint ~= "on" then return end
    local shown, problem = hint.update(want, menu_widget, settings_module.hint_text(settings))
    problem = shown == false and problem or nil
    if problem and problem ~= hint_problem then log("hint\t" .. tostring(problem)) end
    hint_problem = problem
end

local function course_tick()
    if not course.armed then
        if hint.is_shown() then show_hint(false) end
        return
    end
    local v = view()
    if v.in_battle or v.menu_visible == false then course:reset() end
    local can, why = course:can_open(v, settings)
    if key_pressed then
        key_pressed = false
        if can then
            local opened, problem = api.open()
            log("key\topen\t" .. tostring(opened) .. "\t" .. tostring(problem))
            can = false
        else
            log("key\tignored\t" .. tostring(why))
        end
    end
    show_hint(can)
end

-- Development only: equipment-eval.lua runs once on the game thread (output in equipment-eval.out), and equipment-request.txt
-- ("open") asks for the menu, so Custom Training's development build (a separate Lua state) can try the API.
local console = devconsole.new(MOD_DIR, { api = api, game = game, course = course, hint = hint,
    settings = settings, menu_widget = function() return menu_widget end }, log)
local REQUEST_PATH = MOD_DIR .. "equipment-request.txt"
local function take_request()
    if not dev then return nil end
    local file = io.open(REQUEST_PATH, "rb")
    if not file then return nil end
    local text = file:read("a") or ""
    file:close()
    os.remove(REQUEST_PATH)
    return text:match("^%s*(%S*)")
end

-- The answer to a request, for the caller across the bridge: equipment-result.txt, written to a temporary name and then
-- renamed, one "key=value" per line. status=open when the menu is on its way, then status=done with the on_close info
-- (result, battle, needs_rebuild, stats_changed), or status=refused with why.
local RESULT_PATH = MOD_DIR .. "equipment-result.txt"
local function write_result(fields)
    local lines = {}
    for _, key in ipairs({ "status", "why", "result", "battle", "needs_rebuild", "stats_changed" }) do
        if fields[key] ~= nil then lines[#lines + 1] = key .. "=" .. tostring(fields[key]) end
    end
    local temp = RESULT_PATH .. ".tmp"
    local file = io.open(temp, "wb")
    if not file then return end
    file:write(table.concat(lines, "\n"), "\n")
    file:close()
    os.remove(RESULT_PATH)
    os.rename(temp, RESULT_PATH)
end

local TICK_MS = 200
LoopAsync(TICK_MS, function()
    if not settled() then return false end
    local eval = console.waiting()
    local request = take_request()
    -- hint.is_shown(): Yes on "Begin challenge?" disarms the course, and the entry must still be taken down.
    if course.armed or key_pressed or eval or request or hint.is_shown() then
        ExecuteInGameThread(function()
            local ok, err = pcall(function()
                if eval then console.run() end
                if request == "open" then
                    local opened, problem = api.open()
                    log("request\topen\t" .. tostring(opened) .. "\t" .. tostring(problem))
                    if opened then
                        write_result({ status = "open" })
                        api.on_close(function(info)
                            write_result({ status = "done", result = info.result, battle = info.battle,
                                needs_rebuild = info.needs_rebuild, stats_changed = info.stats_changed })
                        end)
                    else
                        write_result({ status = "refused", why = problem })
                    end
                end
                if key_pressed and not course.armed then
                    key_pressed = false
                end
                course_tick()
            end)
            if not ok then log("tick\terror\t" .. tostring(err)) end
        end)
    end
    return false
end)

log("loaded\tkey=" .. tostring(settings.key) .. "\tcourse_flow=" .. tostring(settings.course_flow) .. "\tdev=" .. tostring(dev))
