-- Every call into the game for the equipment workstream. Only members the Epic 1.005 header dump shows are named
-- (never name a member an object lacks, even inside pcall: it leaks the Lua C stack). Call on the game thread.
local M = {}

local MENU_API = "/Script/EndGame.Default__EndMenuAPI"
local MENU_BP_API = "/Script/EndGame.Default__EndMenuBPAPI"
local BATTLE_API = "/Script/EndGame.Default__EndBattleAPI"
local DATABASE_API = "/Script/EndGame.Default__EndDataBaseAPI"
local STATICS = "/Script/Engine.Default__GameplayStatics"

M.PAUSE_NORMAL = 0       -- EEndMenuPauseMode.Normal: the main menu Esc opens in the field
M.GAME_PAUSE_SYSTEM = 0  -- EGamePause_SYSTEM, bit 0 of AEndGameState.GamePause

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
M.safe = safe

local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end
M.valid = valid

-- Class default objects live for the whole game, so they can be kept.
local cdo_cache = {}
local function cdo(path)
    local object = cdo_cache[path]
    if object ~= nil then return object end
    object = safe(StaticFindObject, path)
    if valid(object) then
        cdo_cache[path] = object
        return object
    end
    return nil
end

function M.leader()
    local battle = cdo(BATTLE_API)
    if not battle then return nil end
    local leader = safe(function() return battle:GetPartyLeader() end)
    return valid(leader) and leader or nil
end

-- AEndGameState. Found once (FindFirstOf costs ~0.1-0.2 s) and kept while it stays the same object: it lives with
-- the persistent level of EndGame, which this game never unloads.
local state_cache = nil
function M.game_state()
    if state_cache and valid(state_cache) then return state_cache end
    local found = safe(FindFirstOf, "EndGameState")
    state_cache = valid(found) and found or nil
    return state_cache
end

function M.pause_bits()
    local gs = M.game_state()
    if not gs then return nil end
    local value = safe(function() return gs.GamePause end)
    return type(value) == "number" and math.floor(value) or nil
end

function M.pause_bit()
    local bits = M.pause_bits()
    if bits == nil then return nil end
    return bits & 1
end

function M.set_pause_bit(on)
    local gs = M.game_state()
    if not gs then return false end
    return safe(function()
        local bits = math.floor(gs.GamePause)
        gs.GamePause = on and (bits | 1) or (bits & ~1)
        return true
    end) == true
end

-- AEndGameState.HideWorld: the full-screen menu hides the world while it is up.
function M.hide_world()
    local gs = M.game_state()
    if not gs then return nil end
    return safe(function() return gs.HideWorld end)
end

function M.set_hide_world(on)
    local gs = M.game_state()
    if not gs then return false end
    return safe(function() gs.HideWorld = on; return true end) == true
end

function M.pause_menu_closed()
    local menu = cdo(MENU_API)
    if not menu then return nil end
    return safe(function() return menu:IsPauseMenuClosed() end)
end

function M.in_battle()
    local battle = cdo(BATTLE_API)
    if not battle then return nil end
    return safe(function() return battle:IsInBattle() end)
end

-- The game's main menu: UEndMenuAPI.ShowPauseMenu(ctx, Normal), then the pause bit Esc's own route sets.
function M.open_main_menu()
    local menu = cdo(MENU_API)
    if not menu then return false, "menu api missing" end
    local ctx = M.leader() or M.game_state()
    if not ctx then return false, "no world context" end
    local ok, problem = pcall(function() menu:ShowPauseMenu(ctx, M.PAUSE_NORMAL) end)
    if not ok then return false, tostring(problem) end
    M.set_pause_bit(true)
    return true
end

-- Whether an engine key (an FKey name such as "Gamepad_Special_Right") is held now, through the player controller's
-- APlayerController.IsInputKeyDown (Custom Training reads the pad the same way; seen working in a fight). UE4SS key
-- binds only see the keyboard. nil when unreadable.
local fkeys = {}
function M.key_down(name)
    local statics = cdo(STATICS)
    local leader = M.leader()
    if not (statics and leader) then return nil end
    local controller = safe(function() return statics:GetPlayerController(leader, 0) end)
    if not valid(controller) then return nil end
    local key = fkeys[name]
    if not key then key = { KeyName = FName(name) }; fkeys[name] = key end
    return safe(function() return controller:IsInputKeyDown(key) end)
end

-- A plain record of what the menu can change, to tell whether the visit changed anything: max HP/MP and the four
-- attack/defence stats of every playable character (EPlayerType 0-8, Zack 7 and Sephiroth 8 included). Materia
-- that change no stat (a spell, a command) are not seen here.
local STATS = { "BPGetPlayerHPMax", "BPGetPlayerMaxMP", "BPGetPlayerPhysicsAttack", "BPGetPlayerMagicAttack",
    "BPGetPlayerPhysicsDefense", "BPGetPlayerMagicDefense" }
function M.loadout_stats()
    local api = cdo(MENU_BP_API)
    if not api then return nil end
    local record = {}
    for member = 0, 8 do
        local row = {}
        for i, name in ipairs(STATS) do
            row[i] = safe(function() return api[name](api, member) end)
        end
        record[member] = row
    end
    return record
end

function M.flag(name)
    local api = cdo(DATABASE_API)
    if not api then return false end
    return safe(function() return api:IsStoryFlag(FName(name)) end) == true
end

-- Whether the simulator's menu widget (kept from a hook's context; it belongs to the game instance and lives for
-- the whole session) is on screen. UWidget.IsVisible: the menu (VR_Top_C) answers IsInViewport() false even while
-- it is on screen (seen 2026-11-20), so that call can't be used. nil when unreadable.
function M.menu_on_screen(widget)
    if widget == nil then return nil end
    if not valid(widget) then return false end
    return safe(function() return widget:IsVisible() end)
end

return M
