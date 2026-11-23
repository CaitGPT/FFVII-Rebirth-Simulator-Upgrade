-- Game calls for the menu: the game's own choice window (UEndMenuAPI.ShowMessageWindow, widget Com_Window_01_C), its
-- rows, the cursor, pausing and the held keys. Game thread only.
--
-- Rule of this game's UE4SS (Junon Colosseum, Custom Training): naming a member an object lacks, or calling a function
-- it doesn't have, breaks the Lua state until a restart, even inside pcall. So every member used here is one the
-- header dump shows on the class checked just before.
local M = {}

local MENU_API = "/Script/EndGame.Default__EndMenuAPI"
local BATTLE_API = "/Script/EndGame.Default__EndBattleAPI"
local SYSTEM_API = "/Script/EndGame.Default__EndSystemAPI"
local STATICS = "/Script/Engine.Default__GameplayStatics"
M.FLAGS = { none = 0, left = 1, pause_menu = 2 } -- EEndMenuMessageWindowFlags (LeftAlignedOptions 1, PauseMenu 2)

local function safe(f, ...)
    local ok, a, b = pcall(f, ...)
    if ok then return a, b end
    return nil
end
M.safe = safe

function M.text(v)
    if type(v) == "string" then return v end
    if v == nil then return nil end
    return safe(function() return v:ToString() end)
end

function M.valid(o) return o ~= nil and safe(function() return o:IsValid() end) == true end

local cdos = {}
local function cdo(path)
    local o = cdos[path]
    if not M.valid(o) then o = StaticFindObject(path); cdos[path] = o end
    return M.valid(o) and o or nil
end
M.cdo = cdo

local classes = {}
local function class(path)
    local c = classes[path]
    if not M.valid(c) then c = StaticFindObject(path); classes[path] = c end
    return M.valid(c) and c or nil
end

function M.class_name(o)
    return safe(function() return o:GetClass():GetFName():ToString() end) or "?"
end

function M.object_name(o)
    return safe(function() return o:GetFName():ToString() end) or "?"
end

local function is_a(o, path)
    local c = class(path)
    return c ~= nil and safe(function() return o:IsA(c) end) == true
end

function M.leader()
    local b = cdo(BATTLE_API)
    return b and safe(function() return b:GetPartyLeader() end) or nil
end

function M.in_battle()
    local b = cdo(BATTLE_API)
    return b ~= nil and safe(function() return b:IsInBattle() end) == true
end

function M.paused()
    local s, leader = cdo(STATICS), M.leader()
    return s ~= nil and leader ~= nil and safe(function() return s:IsGamePaused(leader) end) == true
end

function M.pause(on)
    local s, leader = cdo(STATICS), M.leader()
    if not (s and leader) then return false end
    return safe(function() s:SetGamePaused(leader, on); return true end) == true
end

local controller_cache
function M.controller()
    if M.valid(controller_cache) then return controller_cache end
    local s, leader = cdo(STATICS), M.leader()
    controller_cache = s and leader and safe(function() return s:GetPlayerController(leader, 0) end) or nil
    return controller_cache
end

local fkeys = {}
function M.keys_down(names)
    local down = {}
    local c = M.controller()
    if not c then return down end
    for _, name in ipairs(names) do
        local key = fkeys[name]
        if not key then key = { KeyName = FName(name) }; fkeys[name] = key end
        if safe(function() return c:IsInputKeyDown(key) end) == true then down[name] = true end
    end
    return down
end

-- The same through the game's own UEndSystemAPI.IsInputKeyDown (static), which may still read the pad while a
-- choice window has the input focus (the player controller's reads nothing then).
function M.system_keys_down(names)
    local down = {}
    local sys = cdo(SYSTEM_API)
    if not sys then return down end
    for _, name in ipairs(names) do
        local key = fkeys[name]
        if not key then key = { KeyName = FName(name) }; fkeys[name] = key end
        if safe(function() return sys:IsInputKeyDown(key) end) == true then down[name] = true end
    end
    return down
end

-- The game's text for a text id ("$en_Zuu_StandardEnd2" -> "Zu"), or nil.
function M.lookup(key)
    local menu = cdo(MENU_API)
    if not (menu and key and key ~= "") then return nil end
    local text = M.text(safe(function() return menu:GetString(key) end))
    if type(text) ~= "string" or text == "" or text == key then return nil end
    return text
end

-- The window -------------------------------------------------------------------------------------------------------

function M.show(body, options, flags)
    local menu, leader = cdo(MENU_API), M.leader()
    if not (menu and leader) then return nil, "no menu API or party leader" end
    local w = safe(function() return menu:ShowMessageWindow(leader, body, options, flags or M.FLAGS.pause_menu) end)
    if not M.valid(w) then return nil, "ShowMessageWindow returned nothing" end
    return w
end

-- true when closed (or gone), false while open.
function M.closed(w)
    if not M.valid(w) then return true end
    local menu = cdo(MENU_API)
    local c = menu and safe(function() return menu:IsMessageWindowClosed(w) end)
    return c ~= false
end

function M.selected(w)
    local menu = cdo(MENU_API)
    local i = menu and M.valid(w) and safe(function() return menu:GetMessageWindowSelectedIndex(w) end)
    return type(i) == "number" and i or nil
end

-- The fight's Pause menu (Resume, Give Up): open?, and closing it (UEndMenuAPI.IsPauseMenuClosed, HidePauseMenu).
function M.pause_menu_open()
    local menu = cdo(MENU_API)
    return menu ~= nil and safe(function() return menu:IsPauseMenuClosed() end) == false
end

function M.hide_pause_menu()
    local menu = cdo(MENU_API)
    if menu then safe(function() menu:HidePauseMenu() end) end
end

function M.hide(w)
    local menu = cdo(MENU_API)
    if menu and M.valid(w) then safe(function() menu:HideMessageWindow(w) end) end
end

local PANEL = "/Script/UMG.PanelWidget"
local USER_WIDGET = "/Script/UMG.UserWidget"
local END_TEXT = "/Script/EndGame.EndTextBlock"
local END_BUTTON = "/Script/EndGame.EndButton"
local LIST_BOX = "/Script/EndGame.EndListBox"
local SCROLL_BOX = "/Script/EndGame.EndVirtualScrollBox"
local BUTTON_CLASSES = { Com_Btn_01_C = true, Com_Btn_00_C = true }

-- Walks a widget tree: visit(widget, depth, parent) for every widget, entering panels, user widgets' own trees and the
-- game's list boxes (their ContentWidgets). Returns the number of widgets seen.
function M.walk(root, visit, depth, budget)
    budget = budget or { n = 0, max = 400 }
    depth = depth or 0
    if not M.valid(root) or budget.n >= budget.max then return budget.n end
    budget.n = budget.n + 1
    if visit(root, depth) == "stop" then return budget.n end
    if is_a(root, USER_WIDGET) then
        local tree = safe(function() return root.WidgetTree end)
        local top = M.valid(tree) and safe(function() return tree.RootWidget end)
        if M.valid(top) then M.walk(top, visit, depth + 1, budget) end
    elseif is_a(root, PANEL) then
        local n = safe(function() return root:GetChildrenCount() end) or 0
        for i = 0, n - 1 do
            local child = safe(function() return root:GetChildAt(i) end)
            if M.valid(child) then M.walk(child, visit, depth + 1, budget) end
        end
    elseif is_a(root, LIST_BOX) or is_a(root, SCROLL_BOX) then
        local items = safe(function() return root.ContentWidgets end)
        local n = items and safe(function() return items:GetArrayNum() end) or 0
        for i = 1, n do
            local child = safe(function() return items[i] end)
            if M.valid(child) then M.walk(child, visit, depth + 1, budget) end
        end
    end
    return budget.n
end

-- The window's option rows, in the order the tree holds them: { { widget, button, text } }, and its body text block
-- (the text block that shows body), and the list box holding the rows, if any.
function M.rows(w, body)
    local rows, found = {}, { body = nil, list = nil }
    M.walk(w, function(o, depth)
        local cls = M.class_name(o)
        if depth > 0 and BUTTON_CLASSES[cls] then
            rows[#rows + 1] = { widget = o, button = safe(function() return o.Button_00 end), text = safe(function() return o.Txt end) }
            return "stop"
        end
        if not found.list and (is_a(o, LIST_BOX) or is_a(o, SCROLL_BOX)) then found.list = o end
        if not found.body and body and is_a(o, END_TEXT) then
            local t = M.text(safe(function() return o:GetText() end))
            if t == body then found.body = o end
        end
    end)
    return rows, found.body, found.list
end

-- Which row has the cursor (1-based), or nil when it can't be told. Tried in order: the game's list box, the row
-- whose button is hovered or has keyboard focus.
function M.focused(rows, list)
    if list then
        local i = safe(function() return list:GetSelectedIndex(0) end)
        if type(i) == "number" and i >= 0 then return i + 1, "list" end
    end
    for i, r in ipairs(rows) do
        local b = r.button
        if M.valid(b) and is_a(b, END_BUTTON) then
            if safe(function() return b:HasKeyboardFocus() end) == true then return i, "focus" end
            if safe(function() return b:IsHovered() end) == true then return i, "hover" end
            if safe(function() return b:GetIsForceHovered() end) == true then return i, "force_hover" end
        end
    end
    return nil, "unknown"
end

function M.set_text(block, text)
    if not M.valid(block) then return false end
    return safe(function() block:SetText(text); return true end) == true
end

-- Puts the cursor on row i (1-based): the list box's selection, or focus on the row's button. try (1, 2, ...) picks
-- the way, so a caller that sees no change can try the next: keyboard focus, the player's focus, plain focus.
-- (UWidget's SetKeyboardFocus, SetUserFocus and SetFocus, all in the header dump's UMG.hpp.)
function M.focus(rows, list, i, try)
    if list and is_a(list, SCROLL_BOX) then
        if safe(function() list:SetSelectedIndex(0, i - 1, false, true, nil); return true end) then return "list" end
    elseif list then
        if safe(function() list:SetSelectedIndex(0, i - 1); return true end) then return "list" end
    end
    local r = rows[i]
    if not (r and M.valid(r.button)) then return nil end
    local b = r.button
    local way = ((try or 1) - 1) % 3 + 1
    if way == 2 then
        local pc = M.controller()
        if M.valid(pc) and safe(function() b:SetUserFocus(pc); return true end) then return "user" end
    elseif way == 3 then
        if safe(function() b:SetFocus(); return true end) then return "focus" end
    end
    if safe(function() b:SetKeyboardFocus(); return true end) then return "keyboard" end
    return nil
end

-- Development: gives the input back to the game (UWidgetBlueprintLibrary.SetInputMode_GameOnly), to try whether a
-- closed choice window left it with the UI.
function M.reset_input()
    local lib = cdo("/Script/UMG.Default__WidgetBlueprintLibrary")
    local pc = M.controller()
    if not (lib and M.valid(pc)) then return false end
    return safe(function() lib:SetInputMode_GameOnly(pc); return true end) == true
end

-- Development: every widget of the window, one line each (class, name, depth, visible, text).
function M.dump(w, out)
    local n = M.walk(w, function(o, depth)
        local line = string.rep("  ", depth) .. M.class_name(o) .. " " .. M.object_name(o)
        local vis = safe(function() return o:GetVisibility() end)
        line = line .. " vis=" .. tostring(vis)
        if is_a(o, END_TEXT) then
            line = line .. " text=" .. tostring(M.text(safe(function() return o:GetText() end)))
        end
        if is_a(o, END_BUTTON) then
            line = line .. " focus=" .. tostring(safe(function() return o:HasKeyboardFocus() end))
                .. " hover=" .. tostring(safe(function() return o:IsHovered() end))
        end
        if is_a(o, LIST_BOX) or is_a(o, SCROLL_BOX) then
            line = line .. " selected=" .. tostring(safe(function() return o:GetSelectedIndex(0) end))
        end
        out(line)
    end, 0, { n = 0, max = 600 })
    out("widgets " .. n .. " class " .. (safe(function() return w:GetClass():GetFullName() end) or "?"))
end

return M
