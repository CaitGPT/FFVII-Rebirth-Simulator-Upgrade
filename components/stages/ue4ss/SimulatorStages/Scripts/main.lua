-- Simulator Stages: Chadley's combat simulator fought on stages the player has unlocked.
-- docs/HOW-IT-WORKS.md describes each step; docs/LIVE-RESULTS.md what was seen in the game.
local MOD_DIR = (debug.getinfo(1, "S").source:match("^@(.*[\\/])[Ss]cripts[\\/]")) or ""
local SETTINGS_PATH = MOD_DIR .. "settings.txt"
local CHOICES_PATH = MOD_DIR .. "choices.txt"
local LOG_PATH = MOD_DIR .. "stages-log.txt"
local TICK_MS = 250
local PICKER_PROMPT = "Choose a stage"
local PICKER_KEY = "F7"

local stages = require("stages")
local catalogue = require("stage_data")
local game = require("game")
local session_module = require("session")

local function log(message)
    print("[SimulatorStages] " .. message .. "\n")
    -- A development install carries dev.txt in the mod folder; only then is a log file kept.
    local marker = io.open(MOD_DIR .. "dev.txt", "rb")
    if not marker then return end
    marker:close()
    local out = io.open(LOG_PATH, "ab")
    if out then
        out:write(os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\t" .. message .. "\n")
        out:close()
    end
end

local function read(path)
    local file = io.open(path, "rb")
    local text = file and file:read("a") or ""
    if file then file:close() end
    return text
end

-- Read again at each use, so an edit to settings.txt applies without a restart.
local function read_settings()
    local settings, problems = stages.parse_settings(read(SETTINGS_PATH))
    for _, problem in ipairs(problems) do log("settings\t" .. problem) end
    return settings
end

local function save_choices(choices)
    local out = io.open(CHOICES_PATH .. ".tmp", "wb")
    if not out then return end
    out:write(stages.format_choices(choices))
    out:close()
    os.remove(CHOICES_PATH)
    os.rename(CHOICES_PATH .. ".tmp", CHOICES_PATH)
end

local session = session_module.new({
    stages = stages,
    catalogue = catalogue,
    game = game,
    choices = stages.parse_choices(read(CHOICES_PATH)),
    save_choices = save_choices,
    log = log,
})

-- The stage picker: the game's own choice window, listing what the selected course can use.
local picker = nil -- { window, course, options }
local last_title = nil

local function offer(title)
    if picker or not title then return end
    local settings = read_settings()
    local course, options, start = session.course_selected(title, settings)
    if not course or #options == 0 then return end
    local labels = {}
    for i, option in ipairs(options) do
        labels[i] = (i == start and "> " or "") .. option.name
    end
    local window = game.open_picker(PICKER_PROMPT, labels)
    if not window then
        log("picker\tnot opened")
        return
    end
    picker = { window = window, course = course, options = options }
end

local function poll_picker()
    if not picker then return end
    local state, index = game.read_picker(picker.window)
    if state == "open" then return end
    local option = index and picker.options[index + 1]
    if option then session.choose(picker.course, option.id) else log("picker\tclosed without a choice") end
    picker = nil
end

-- The simulator's menu is UEndColosseumMenu; Training Dummy hooks the same events.
local function hook_menu(event, callback)
    local ok, err = pcall(RegisterHook, "/Script/EndGame.EndColosseumMenu:" .. event, function(context)
        local fine, problem = pcall(callback, context)
        if not fine then log(event .. "\terror\t" .. tostring(problem)) end
    end)
    if not ok then log("menu hook unavailable: " .. event .. " (" .. tostring(err) .. ")") end
end

-- A course is selected: remember its title and, with picker = select, offer its stages.
hook_menu("OnCourseMenuPressedItem", function(context)
    last_title = game.course_title(context)
    if read_settings().picker == "select" then offer(last_title) end
end)
-- The highlight moved: keep the title for the key.
hook_menu("OnCourseMenuSelectedIndexChanged", function(context)
    last_title = game.course_title(context)
end)
-- The course is confirmed: apply the remembered choice.
hook_menu("OnYesButtonPressed", function(context)
    local settings = read_settings()
    local title = game.course_title(context) or last_title
    if title and not picker then session.course_selected(title, settings) end
    local stage, why = session.course_confirmed(os.time(), settings)
    if not stage then log("course\tvanilla\t" .. tostring(why)) end
end)

-- The picker on a key, for the highlighted course.
local key_pressed = false
pcall(RegisterKeyBind, Key[PICKER_KEY], function() key_pressed = true end)

-- Development installs only (dev.txt in the mod folder): run stages-eval.lua from the mod folder once, on the game
-- thread, and write what it returned to stages-eval.out. This game cannot reload a mod's scripts, so this is how a
-- game call gets tried without a restart. A release has no dev.txt and never looks for the file.
local EVAL_PATH = MOD_DIR .. "stages-eval.lua"
local function is_dev()
    local marker = io.open(MOD_DIR .. "dev.txt", "rb")
    if marker then marker:close() end
    return marker ~= nil
end
local dev = is_dev()
local function eval_waiting()
    if not dev then return false end
    local file = io.open(EVAL_PATH, "rb")
    if file then file:close() end
    return file ~= nil
end
local function run_eval()
    local file = io.open(EVAL_PATH, "rb")
    if not file then return end
    local code = file:read("a")
    file:close()
    os.remove(EVAL_PATH)
    local lines = {}
    local env = setmetatable({
        game = game, stages = stages, catalogue = catalogue, session = session,
        out = function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
            lines[#lines + 1] = table.concat(parts, "\t")
        end,
    }, { __index = _G })
    local chunk, problem = load(code, "@stages-eval", "t", env)
    local ok, result = false, problem
    if chunk then ok, result = pcall(chunk) end
    lines[#lines + 1] = (ok and "ok" or "ERROR") .. "\t" .. tostring(result)
    local report = io.open(MOD_DIR .. "stages-eval.out", "wb")
    if report then
        report:write(table.concat(lines, "\n") .. "\n")
        report:close()
    end
    log("eval\t" .. tostring(ok))
end

-- Register this mod's game-thread callback while mods load: a first ExecuteInGameThread during play can crash.
pcall(ExecuteInGameThread, function() end)

-- Nothing runs on the game thread unless a visit is in progress or still unloading, the picker is open or the key
-- was pressed.
LoopAsync(TICK_MS, function()
    pcall(game.helper_poll, os.time()) -- file reading only: is the level helper alive?
    local eval = eval_waiting()
    if session.busy() or session.unloading() or picker or key_pressed or eval then
        ExecuteInGameThread(function()
            local ok, err = pcall(function()
                if eval then run_eval() end
                if key_pressed then
                    key_pressed = false
                    if read_settings().picker ~= "off" then offer(last_title) end
                end
                poll_picker()
                session.tick(os.time())
            end)
            if not ok then log("tick\terror\t" .. tostring(err)) end
        end)
    end
    return false
end)

log("loaded\t" .. #catalogue.stages .. " stages\t" .. #catalogue.courses .. " courses")
