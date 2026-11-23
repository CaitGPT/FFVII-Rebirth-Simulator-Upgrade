-- settings.txt beside the scripts (Battle Meters' pattern). Keys are prefixed `equipment_` so the integrated
-- Simulator Overhaul can keep every part's settings in one file. Game-free.
local M = {}

M.DEFAULTS = {
    key = "F3",                -- the keyboard key that opens the menu in the simulator (UE4SS Key name)
    course_flow = "course_list", -- course_list: the course list and every screen after choosing a course;
                                 -- after_course: only once a course is chosen; off. Never once a course has started.
    pad_button = "Gamepad_Special_Right", -- the pad button that does the same (an engine key name; off: none)
    hint = "on",               -- on: an "Equipment" entry in the simulator's own key guide while the key works; off
}

-- Older names still read: "always" was the first name of course_list.
local ALIASES = { always = "course_list" }
-- Settings an older build wrote, now ignored without a complaint (the hint now sits in the game's own key guide).
local RETIRED = { battle_mode = true, hint_x = true, hint_y = true }

local NUMBERS = {}
local CHOICES = {
    course_flow = { course_list = true, after_course = true, off = true },
    hint = { on = true, off = true },
}

function M.parse(text)
    local settings, problems = {}, {}
    for k, v in pairs(M.DEFAULTS) do settings[k] = v end
    for line in (text or ""):gmatch("[^\r\n]+") do
        local stripped = line:match("^%s*(.-)%s*$")
        if stripped ~= "" and not stripped:match("^[#;]") then
            local key, value = stripped:match("^equipment_([%w_]+)%s*=%s*(.-)$")
            if not key then
                if stripped:match("^equipment_") then problems[#problems + 1] = "unreadable line: " .. stripped end
            elseif RETIRED[key] then
                -- ignored
            elseif M.DEFAULTS[key] == nil then
                problems[#problems + 1] = "unknown setting: equipment_" .. key
            elseif NUMBERS[key] then
                local n = tonumber(value)
                if n then settings[key] = n else problems[#problems + 1] = "not a number: equipment_" .. key end
            elseif CHOICES[key] then
                local v = ALIASES[value:lower()] or value:lower()
                if CHOICES[key][v] then settings[key] = v else problems[#problems + 1] = "unknown value: equipment_" .. key .. " = " .. value end
            elseif key == "pad_button" then
                if value:lower() == "off" then settings.pad_button = "off"
                elseif value:match("^[%w_]+$") then settings.pad_button = value
                else problems[#problems + 1] = "bad pad button name: " .. value end
            elseif key == "key" then
                if value:match("^[%w_]+$") then settings.key = value:upper() else problems[#problems + 1] = "bad key name: " .. value end
            end
        end
    end
    return settings, problems
end

-- What the pad buttons are called on screen.
local PAD_LABELS = {
    Gamepad_Special_Right = "Start", Gamepad_Special_Left = "View",
    Gamepad_LeftThumbstick = "L3", Gamepad_RightThumbstick = "R3",
}

-- The hint's text, drawn by the game's own guide text. With the default bindings (F3 and Start, which are the game's
-- Options action on keyboard and pad) it is the game's Options button tag, so the game draws its own F3 key or Start
-- button glyph for the device in use. Other bindings: "F5 / View  Equipment", or "F3  Equipment" with the pad off.
function M.hint_text(settings)
    local pad = settings.pad_button
    if settings.key == "F3" and pad == "Gamepad_Special_Right" then return "<button=options> Equipment" end
    if pad == nil or pad == "off" then return settings.key .. "  Equipment" end
    return settings.key .. " / " .. (PAD_LABELS[pad] or pad) .. "  Equipment"
end

return M
