-- A readable name and description for the Custom Training course in the simulator's menu (Training Dummy's
-- course_text.lua, adapted). The course uses its own text keys, which are not in the game's text table, so the menu
-- would show them blank; rather than replace the text table (other mods replace that whole file), the keys are
-- swapped for plain text in the menu's text blocks.
local M = {}

M.NAMES = {
    Custom = {
        title = "Custom Training",
        -- Kept within the old text's length (251), which fits the info panel.
        flavor = "Fight any opponent, up to three at once, or a round from any course, at any difficulty. "
            .. "Passive holds them and refills you; Aggressive is real practice, Auto-Life only; "
            .. "Healing holds your party at 1% HP. F7 or LB+RB changes it all; F4 fights again.",
    },
}

-- Set by main.lua to its debug trace (key, message).
M.trace = function() end

local TITLE = "^%$menu_Colosseum_CourseTitle_COL99_SimOverhaul_CT_(%a+)$"
local FLAVOR = "^%$menu_Colosseum_CourseFlavor_COL99_SimOverhaul_CT_(%a+)$"

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end

-- The mode a title key or a replaced title names, for telling courses apart.
function M.mode_of(text)
    if type(text) ~= "string" then return nil end
    local mode = text:match(TITLE)
    if M.NAMES[mode] then return mode end
    for key, names in pairs(M.NAMES) do
        if text == names.title then return key end
    end
    return nil
end

-- Widgets the menu's hooks reported, kept only for the next few passes:
-- the hooks run before the game fills the text, and transient widgets can't
-- be found again by path.
local PASSES = 8 -- about 1.6 s at the default tick
local pending = {menu = nil, passes = 0}

-- Called from the simulator menu's hooks with the menu.
function M.remember(menu)
    if valid(menu) then pending.menu = menu end
    pending.passes = PASSES
end

-- Called when a battle starts or ends: the menu's text is not ours to touch while the game is tearing its widgets
-- down, and nothing of ours is visible then anyway.
function M.stop()
    pending.menu, pending.passes = nil, 0
end

local function replace(block)
    if not valid(block) then return end
    local text = safe(function() return block:GetText():ToString() end)
    if type(text) ~= "string" then return end
    local mode, field = text:match(TITLE), "title"
    if not M.NAMES[mode] then mode, field = text:match(FLAVOR), "flavor" end
    if M.NAMES[mode] then
        local wanted = M.NAMES[mode][field]
        -- EndTextBlock:SetText takes a string; a plain TextBlock takes FText.
        local ok, err = pcall(function() block:SetText(wanted) end)
        if not ok then
            M.trace("text_set_string", tostring(err))
            ok, err = pcall(function() block:SetText(FText(wanted)) end)
            if not ok then M.trace("text_set_ftext", tostring(err)) end
        end
        return 1
    end
    return 0
end

-- The list rows (VR_ListItem.Txt_Name) and the description
-- (InfoWindow.Txt_Info) are Blueprint widgets with no reflected path to them
-- (UUserWidget:GetWidgetFromName is not exposed in this game), so they are
-- found by scanning the text blocks, at most every SCAN_GAP passes while the
-- menu is reporting events. Only blocks showing one of our keys change.
local SCAN_GAP = 3
local since_scan = SCAN_GAP

local function scan()
    local replaced = 0
    for _, block in ipairs(safe(FindAllOf, "EndTextBlock") or {}) do
        replaced = replaced + (replace(block) or 0)
    end
    return replaced
end

-- One pass over the menu's own title fields, plus a throttled scan; the
-- references are dropped after the last pass.
-- True while the simulator menu has text waiting to be replaced.
function M.has_work()
    return pending.passes > 0
end

function M.apply()
    since_scan = since_scan + 1
    if pending.passes <= 0 then return end
    local menu = pending.menu
    -- Only work while the menu that asked for it is still alive. Giving up a course tears the simulator's widgets
    -- down and builds them again, and scanning every text block through that window read freed memory: the game hung
    -- once and crashed once on 1.005 (2026-11-13, EXCEPTION_ACCESS_VIOLATION reading -1 from SetText). pcall cannot
    -- catch that, because the fault is inside the engine rather than a Lua error.
    if not valid(menu) then
        pending.menu, pending.passes = nil, 0
        return
    end
    pending.passes = pending.passes - 1
    local replaced = 0
    local info = safe(function() return menu.InfoWindow end)
    replaced = (replace(safe(function() return info.Txt_CourseTitle end)) or 0)
        + (replace(safe(function() return menu.Txt_TitleCourse end)) or 0)
    if since_scan >= SCAN_GAP then
        since_scan = 0
        replaced = replaced + scan()
    end
    if replaced > 0 then M.trace("text_apply", "replaced " .. replaced) end
    if pending.passes == 0 then pending.menu = nil end
end

return M
