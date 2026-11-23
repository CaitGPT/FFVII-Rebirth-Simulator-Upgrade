-- Which stages a simulator course may use, and which one the player chose for it. No game calls here: everything is
-- tested offline (tests/stages_test.lua).
--
-- The owner's design (2026-11-16): stages unlock; after a course is selected the player picks from the stages that
-- course can use. Beating a region's boss unlocks that region's arena; beating certain story bosses unlocks theirs.
local M = {}

M.VANILLA = "vanilla" -- the simulator's own stage

M.DEFAULTS = {
    enabled = true,
    picker = "select",     -- select: offer stages when a course is selected | key: only on the key | off: no picker
    require_unlock = true, -- false offers every stage, for testing
    lift_cm = 0,           -- raise the simulator's floor above the arena's ground by this much
    steps = "relocate,unhide,dressing,sky",
    force_stage = "",      -- development: use this stage for every course, whatever was chosen
    route = "stream",      -- stream: bring the stage's levels to the simulator | move: move the simulator (own continent only)
    experimental = false,  -- true also offers stages that are not working yet
}
M.PICKERS = { select = true, key = true, off = true }
M.ROUTES = { stream = true, move = true }

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- "key = value" lines; # starts a comment. Unknown keys and bad values are reported, never applied.
function M.parse_settings(text)
    local settings, problems = {}, {}
    for key, value in pairs(M.DEFAULTS) do settings[key] = value end
    for line in (text or ""):gmatch("[^\r\n]+") do
        line = trim((line:gsub("#.*$", "")))
        if line ~= "" then
            local key, value = line:match("^([%w_]+)%s*=%s*(.-)$")
            -- Simulator Overhaul shares one settings.txt between its parts: only stages_ keys are ours, and the
            -- other parts' lines are passed over without a word.
            local ours = key ~= nil and key:sub(1, 7) == "stages_"
            if ours then key = key:sub(8) end
            if key and not ours then
                -- another part's line
            elseif not key or M.DEFAULTS[key] == nil then
                problems[#problems + 1] = "ignored: " .. line
            else
                local default = M.DEFAULTS[key]
                if type(default) == "boolean" then
                    if value == "true" or value == "false" then settings[key] = value == "true"
                    else problems[#problems + 1] = key .. " must be true or false" end
                elseif type(default) == "number" then
                    local n = tonumber(value)
                    if n then settings[key] = n else problems[#problems + 1] = key .. " must be a number" end
                elseif key == "picker" then
                    if M.PICKERS[value] then settings.picker = value
                    else problems[#problems + 1] = "picker must be select, key or off" end
                elseif key == "route" then
                    if M.ROUTES[value] then settings.route = value
                    else problems[#problems + 1] = "route must be stream or move" end
                else
                    settings[key] = value
                end
            end
        end
    end
    return settings, problems
end

function M.steps(settings)
    local on = {}
    for name in (settings.steps or ""):gmatch("[%w_]+") do on[name] = true end
    return on
end

function M.find(catalogue, id)
    for _, stage in ipairs(catalogue.stages) do
        if stage.id == id then return stage end
    end
    return nil
end

-- The menu's title field holds the course's text id ("$menu_Colosseum_CourseTitle_COL30_GRASA_01"; seen in the
-- game 2026-11-17), which is the same in every language. This maps that id to the course. The English title, and
-- the title in the player's language when text(title_id) can supply it, are kept as fallbacks for a menu that
-- shows displayed text instead.
function M.title_index(catalogue, text)
    local index = {}
    for _, course in ipairs(catalogue.courses) do
        index[course.title_id] = course
        index[course.title] = course
        local localised = text and text(course.title_id)
        if type(localised) == "string" and localised ~= "" then index[trim(localised)] = course end
    end
    return index
end

function M.course_by_title(index, title)
    if type(title) ~= "string" then return nil end
    return index[trim(title)]
end

-- context: {
--   continent  = "EASTC" | "WESTC" | ...   the world the simulator was opened in
--   flag       = function(name) -> boolean a story flag
--   progress   = number or nil             chapter progress (12000 = Chapter 12)
--   cleared    = boolean                   the game has been finished (chapter select released)
--   can_stream = boolean                   the level-load helper is present
-- }

-- A stage's unlock is one of: { flag = name } | { progress = n } | { cleared = true }.
-- A finished game unlocks progress-gated stages too: chapter replays lower the progress number.
function M.unlocked(stage, context, settings)
    if settings and settings.require_unlock == false then return true end
    local unlock = stage.unlock or {}
    if unlock.flag then return context.flag(unlock.flag) == true end
    if unlock.progress then
        return context.cleared == true or (type(context.progress) == "number" and context.progress >= unlock.progress)
    end
    if unlock.cleared then return context.cleared == true end
    return true
end

-- How a stage reaches the simulator. Every stage is streamed (its levels are loaded at the simulator's position),
-- so it works wherever the simulator was opened. A stage in the open world can instead have the simulator moved onto
-- it (route = move), which needs no helper but works only on that stage's continent.
function M.route_of(stage, settings)
    if settings and settings.route == "move" and stage.kind == "world" then return "move" end
    return "stream"
end

-- Why a course cannot use a stage right now, or nil when it can.
function M.blocked(stage, course, context, settings)
    if stage.enabled == false then return "not built" end
    if stage.experimental and not (settings and settings.experimental) then return "not working yet" end
    if not M.unlocked(stage, context, settings) then return "locked" end
    if M.route_of(stage, settings) == "move" then
        if stage.continent ~= context.continent then return "other continent" end
    else
        if not stage.levels or #stage.levels == 0 then return "no levels listed" end
        if not context.can_stream then return "needs the level helper" end
    end
    if stage.radius_m < course.needs_m then return "too small" end
    return nil
end

-- What to load for a streamed stage: each level, where to put it, and the name its instance gets. The stage's
-- anchor (its fight centre, at ground height, in its own map's coordinates) lands on the simulator's centre, which
-- is the simulator volume's target position (the stage level's origin, floor at z = 0).
function M.stream_plan(stage, simulator_target, settings, serial)
    local lift = (settings and settings.lift_cm) or 0
    local location = {
        X = simulator_target.X - stage.anchor[1],
        Y = simulator_target.Y - stage.anchor[2],
        Z = simulator_target.Z - stage.anchor[3] + lift,
    }
    -- The height goes into the instance name: a level that was unloaded but not yet collected is reused where it
    -- was, so the same stage at another height (the other continent, a changed lift) needs another name
    -- (seen in the game 2026-11-17).
    -- `serial` (the visit's number) makes each visit's copy its own, so nothing done to one copy (a stretch) is
    -- found already done on the next.
    local tag = "_" .. string.format("%d", math.floor(location.Z + 0.5)):gsub("-", "m")
    if serial then tag = tag .. "_" .. tostring(serial) end
    -- Where the stage's anchor lands: the arena's centre at floor height. Stretching is done about this point.
    local plan = { centre = { X = simulator_target.X, Y = simulator_target.Y, Z = simulator_target.Z + lift } }
    local function add(package)
        plan[#plan + 1] = {
            package = package,
            name = "SimStage_" .. stage.id .. "_" .. (#plan + 1) .. tag,
            location = location,
            yaw = 0,
        }
    end
    for _, level in ipairs(stage.levels) do add(level) end
    if stage.sky_level then add(stage.sky_level) end
    return plan
end

-- The remembered choices also keep the last stage picked on any course, under this key (no course key is this).
M.LAST_KEY = "last"

-- What the picker offers for a course: the simulator's own stage first, then every stage the course can use. When the
-- last stage picked on any course (`choices.last`) is one of those, "Replay: <name>" goes at the very top, so it is one
-- press away (owner, 2026-11-20). Returns options ({ id, name, replay }) and, for the log, the stages left out.
function M.options(catalogue, course, context, settings, choices)
    local options, left_out = {}, {}
    if not course or course.excluded then return options, left_out end
    options[1] = { id = M.VANILLA, name = "Combat Simulator" }
    for _, stage in ipairs(catalogue.stages) do
        local why = M.blocked(stage, course, context, settings)
        if why then left_out[#left_out + 1] = stage.id .. ": " .. why
        else options[#options + 1] = { id = stage.id, name = stage.name } end
    end
    local last = choices and choices[M.LAST_KEY]
    if last and last ~= M.VANILLA then
        for i = 2, #options do
            if options[i].id == last then
                table.insert(options, 1, { id = last, name = "Replay: " .. options[i].name, replay = true })
                break
            end
        end
    end
    return options, left_out
end

-- The stage a course gets when it is confirmed: the player's remembered choice, if the course can still use it.
-- Returns the stage, or nil for the simulator's own stage, and why.
function M.chosen(catalogue, course, context, settings, choices)
    if not settings.enabled then return nil, "disabled" end
    if not course then return nil, "course not recognised" end
    if course.excluded then return nil, "excluded: " .. course.excluded end
    local id = settings.force_stage ~= "" and settings.force_stage or choices[course.key]
    if not id or id == M.VANILLA then return nil, "simulator stage chosen" end
    local stage = M.find(catalogue, id)
    if not stage then return nil, "unknown stage '" .. tostring(id) .. "'" end
    local why = M.blocked(stage, course, context, settings)
    if why then return nil, stage.id .. ": " .. why end
    return stage, settings.force_stage ~= "" and "forced" or "chosen"
end

-- Remembered choices, one "course key = stage id" per line.
function M.parse_choices(text)
    local choices = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local key, id = line:match("^%s*([%w_]+)%s*=%s*([%w_]+)%s*$")
        if key then choices[key] = id end
    end
    return choices
end
function M.format_choices(choices)
    local keys = {}
    for key in pairs(choices) do keys[#keys + 1] = key end
    table.sort(keys)
    local lines = {}
    for _, key in ipairs(keys) do lines[#lines + 1] = key .. " = " .. choices[key] end
    return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

-- Which option the picker should start on: the remembered choice if it is offered, else the first.
function M.selected_index(options, course, choices)
    local id = choices[course.key]
    for i, option in ipairs(options) do
        if option.id == id and not option.replay then return i end
    end
    return 1
end

function M.floor_z(stage) return stage.actor_z + stage.ground_offset_z end

-- Where the simulator's stage level goes so that its centre (the level's origin, floor at z = 0) sits on a world
-- stage's ground at the territory's centre.
function M.target(stage, settings)
    return {
        X = stage.centre[1],
        Y = stage.centre[2],
        Z = M.floor_z(stage) + ((settings and settings.lift_cm) or 0),
    }, stage.stage_yaw or 0
end

-- The continent a simulator volume belongs to, from its actor name ("1000-StreamingVolume_VR_Battle").
function M.continent_of(volume_name, vr_stage)
    for prefix, continent in pairs(vr_stage.volume_tag_prefix) do
        if volume_name:sub(1, #prefix) == prefix then return continent end
    end
    return nil
end

return M
