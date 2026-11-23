-- The "Equipment" entry in the simulator's own key guide, shown while the key works. It is a copy of the game's own
-- guide text block (made with that block as its template, so it keeps the game's font, button glyphs and their
-- keyboard/pad switching), added beside it in the same panel:
--   * the course list: left of "Toggle Data" at the bottom of the course info window;
--   * the screens after choosing a course (stage picker, team, summon level, "Begin challenge?"): the menu's
--     bottom-right guide line (Txt_BtnGuide, which the game leaves empty there), left of anything the game puts in it.
-- On each screen the other spot is out of view: the game slides the guide line out on the course list and hides the
-- info window after a course is chosen. Seen 2026-11-21: an EndTextBlock built from nothing, or a game widget made
-- with WidgetBlueprintLibrary.Create, draws nothing; a template copy inside a live game panel draws like the game's.
-- The simulator's menu (VR_Top_C) is built again after a course, so the copies are made again for each new menu.
-- Call on the game thread.
local M = {}

local SHOWN, COLLAPSED = 3, 1 -- ESlateVisibility: HitTestInvisible, Collapsed
local GAP = 36                -- between our entry and the game's own, in the panel's units

-- Where the entry goes: the game's guide text it copies (a path under the menu widget) and the copy's alignment.
local SPOTS = {
    { path = ".WidgetTree.InfoWindow.WidgetTree.Txt_Btn", align = { X = 1, Y = 1 } },
    { path = ".WidgetTree.Txt_BtnGuide", align = { X = 1, Y = 0 } },
}

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end

local menu_path = nil -- the menu widget the copies belong to
local spots = {}      -- per SPOTS entry: { source, copy, slot, text, x, y, shown }
local made = 0        -- copies made this session, for unique names
local retry_at = 0    -- when a menu without its guide texts (not built yet) is looked at again

local function path_of(object)
    return safe(function() return object:GetFullName():match("%S+$") end)
end

-- The game's guide texts of this menu (one walk over the text blocks, ~0.1 s, once per menu).
local function find_sources(base)
    local wanted, found = {}, {}
    for i, spot in ipairs(SPOTS) do wanted[base .. spot.path] = i end
    for _, block in ipairs(safe(FindAllOf, "EndTextBlock") or {}) do
        local i = wanted[path_of(block) or ""]
        if i then found[i] = block end
    end
    return found
end

local function make_copy(source, spot)
    local panel = safe(function() return source:GetParent() end)
    local source_slot = safe(function() return source.Slot end)
    if not (valid(panel) and valid(source_slot)) then return nil, "guide text has no panel" end
    made = made + 1
    local copy = safe(function()
        return StaticConstructObject(source:GetClass(), source:GetOuter(), FName("SimOverhaulEquipmentGuide" .. made),
            0, 0, false, false, source)
    end)
    if not valid(copy) then return nil, "copy not made" end
    local slot = safe(function() return panel:AddChildToCanvas(copy) end)
    if not valid(slot) then return nil, "copy not added" end
    local ok = pcall(function()
        copy:SetVisibility(COLLAPSED)
        slot:SetAnchors(source_slot:GetAnchors())
        slot:SetAlignment(spot.align)
        slot:SetAutoSize(true)
    end)
    if not ok then return nil, "copy not placed" end
    return { copy = copy, slot = slot, source_slot = source_slot }
end

-- Left of the game's own entry, on its line.
local function place(entry, source)
    local at = safe(function()
        local position = entry.source_slot:GetPosition()
        local width = 0
        if source:GetText():ToString() ~= "" then width = source:GetDesiredSize().X end
        return { position.X - (width > 0 and width + GAP or 0), position.Y }
    end)
    if at == nil then return end
    local x, y = at[1], at[2]
    if entry.x ~= x or entry.y ~= y then
        safe(function() entry.slot:SetPosition({ X = x, Y = y }) end)
        entry.x, entry.y = x, y
    end
end

local function hide_all()
    for _, entry in pairs(spots) do
        if entry.shown and valid(entry.copy) then safe(function() entry.copy:SetVisibility(COLLAPSED) end) end
        entry.shown = false
    end
end

-- want: whether the entry should be on screen now; menu: the simulator's menu widget; text: the entry's text.
function M.update(want, menu, text)
    if not want or not valid(menu) then
        hide_all()
        return true
    end
    local base = path_of(menu)
    if not base then return false, "menu path unreadable" end
    for _, entry in pairs(spots) do
        if not valid(entry.source) then menu_path = nil end -- a guide text was rebuilt: look again
    end
    if base ~= menu_path then
        if os.clock() < retry_at then return true end
        hide_all()
        spots = {}
        menu_path = base
        for i, source in pairs(find_sources(base)) do spots[i] = { source = source } end
        if next(spots) == nil then
            menu_path, retry_at = nil, os.clock() + 3
            return false, "no guide text in the menu"
        end
    end
    local problem = nil
    for i, spot in ipairs(SPOTS) do
        local entry = spots[i]
        if entry and valid(entry.source) then
            if not (valid(entry.copy) and valid(entry.slot)) then
                local made_entry, why = make_copy(entry.source, spot)
                if made_entry then
                    entry.copy, entry.slot, entry.source_slot = made_entry.copy, made_entry.slot, made_entry.source_slot
                    entry.text, entry.x, entry.y, entry.shown = nil, nil, nil, false
                else
                    problem = why
                end
            end
            if valid(entry.copy) then
                if entry.text ~= text then
                    safe(function() entry.copy:SetText(text) end)
                    entry.text = text
                end
                place(entry, entry.source)
                if not entry.shown then
                    safe(function() entry.copy:SetVisibility(SHOWN) end)
                    entry.shown = true
                end
            end
        end
    end
    if problem then return false, problem end
    return true
end

function M.is_shown()
    for _, entry in pairs(spots) do
        if entry.shown then return true end
    end
    return false
end

return M
