-- The meters' game calls: readings for meters_tracker, the stagger reset, pause and time. Battle Meters' and Training
-- Dummy's proven calls (their main.lua), unchanged in what they call. Every call is guarded, and only names members and
-- functions in the header dump: naming one an object lacks breaks the Lua state, even inside pcall. Nothing from the
-- game is held between ticks. Called on the game thread.
local tracker = require("meters_tracker")

local M = {}

local BATTLE_API = "/Script/EndGame.Default__EndBattleAPI"
local PARTY_API = "/Script/EndGame.Default__EndPartyAPI"
local MENU_API = "/Script/EndGame.Default__EndMenuBPAPI"
local STATICS = "/Script/Engine.Default__GameplayStatics"
local MAX_ENEMIES, MAX_PARTY = 32, 8

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end
local function cdo(path)
    local object = safe(StaticFindObject, path)
    if valid(object) then return object end
    return nil
end
local function name_of(object)
    local name = safe(function() return object:GetFName():ToString() end)
    return type(name) == "string" and name or "?"
end
local function number(v)
    if type(v) == "number" and v == v then return v end
    return nil
end
M.safe, M.valid, M.cdo, M.name_of = safe, valid, cdo, name_of

function M.battle() return cdo(BATTLE_API) end

-- The controlled pawn once a save is loaded: a party character, or the vehicle they ride. Battle functions are not
-- called before one has been seen: calls from the title screen crashed the game (Training Dummy, Battle Meters).
local engine, controller = nil, nil
function M.gameplay_pawn()
    local pawn
    if not valid(engine) then engine = safe(FindFirstOf, "GameEngine") end
    local viewport = valid(engine) and safe(function() return engine.GameViewport end)
    local statics = cdo(STATICS)
    if valid(viewport) and statics then pawn = safe(function() return statics:GetPlayerPawn(viewport, 0) end) end
    if not valid(pawn) then
        if not valid(controller) then controller = safe(FindFirstOf, "EndPlayerControllerBP_C") end
        pawn = valid(controller) and safe(function() return controller.Pawn end) or nil
    end
    if not valid(pawn) then return nil end
    local class = safe(function() return pawn:GetClass():GetFName():ToString() end) or ""
    if class:match("^PC%d%d%d%d_") or class:match("^VE%d%d%d%d_") then return pawn end
    return nil
end

function M.in_battle(battle) return safe(function() return battle:IsInBattle() end) == true end

-- Game time: it stops while paused, so menus don't dilute the meters.
function M.now(world_object)
    local statics = cdo(STATICS)
    return number(statics and safe(function() return statics:GetTimeSeconds(world_object) end)) or os.time()
end

function M.paused(world_object)
    local statics = cdo(STATICS)
    return statics ~= nil and safe(function() return statics:IsGamePaused(world_object) end) == true
end

-- GetEnemyMembersRef fills an out array; UE4SS hands it back as the out table, a table holding one TArray, or a TArray.
function M.enemy_actors(battle)
    local out = {}
    local returned = safe(function() return battle:GetEnemyMembersRef(out) end)
    local value = returned ~= nil and returned or out
    local list = {}
    local function add(item)
        local actor = item
        if type(item) == "userdata" then
            local kind = safe(function() return item:type() end)
            if kind == "RemoteUnrealParam" or kind == "LocalUnrealParam" then actor = safe(function() return item:get() end) end
        end
        if valid(actor) and #list < MAX_ENEMIES then list[#list + 1] = actor end
    end
    local function walk(array) safe(function() array:ForEach(function(_, element) add(element) end) end) end
    if type(value) == "table" then
        if #value == 1 and type(value[1]) == "userdata" and safe(function() return value[1]:type() end) == "TArray" then
            walk(value[1])
        else
            for _, item in ipairs(value) do add(item) end
        end
    elseif type(value) == "userdata" and safe(function() return value:type() end) == "TArray" then
        walk(value)
    end
    return list
end

-- The opponents, Custom Training's anchor (a hidden enemy that keeps the round going) left out by object name.
-- Returns the readings and the actors (for the stagger reset, used in the same tick only).
function M.enemies(battle, anchor)
    local readings, actors, any = {}, {}, nil
    for _, actor in ipairs(M.enemy_actors(battle)) do
        any = any or actor
        if not (anchor and name_of(actor) == anchor) then
            readings[#readings + 1] = {
                key = safe(function() return actor:GetAddress() end) or name_of(actor),
                name = safe(function() return battle:GetActorName(actor):ToString() end) or name_of(actor),
                hp = number(safe(function() return battle:GetCharaHP(actor) end)),
                max = number(safe(function() return battle:GetHPMax(actor) end)),
            }
            actors[#actors + 1] = actor
        end
    end
    -- any: an enemy actor to draw and read time with, the anchor too: between a cleared wave and the respawn it is the
    -- only one (seen 2026-11-21: the panel went away after a clear).
    return readings, actors, any
end

-- The battle party in slot order, with the names the game's hit events may use for each (read once per battle by
-- the tracker), HP and MP. GetPlayerType(actor) fails on this game, so the type comes by slot.
function M.party(battle)
    local party = cdo(PARTY_API)
    if not party then return {} end
    local menu = cdo(MENU_API)
    local count = number(safe(function() return party:GetBattleMemberCount() end)) or 0
    local list = {}
    for i = 0, math.min(count, MAX_PARTY) - 1 do
        local actor = safe(function() return party:GetBattleMember(i) end)
        local kind = number(safe(function() return party:GetBattleMemberType(i) end))
        if valid(actor) then
            list[#list + 1] = {
                id = tracker.PLAYER_NAMES[kind] or name_of(actor),
                hp = number(safe(function() return battle:GetCharaHP(actor) end)),
                max = number(safe(function() return battle:GetHPMax(actor) end)),
                mp = menu and kind and number(safe(function() return menu:BPGetPlayerMP(kind) end)) or nil,
                names = { safe(function() return battle:GetActorName(actor):ToString() end),
                    safe(function() return battle:GetCharaID(actor):ToString() end), name_of(actor) },
            }
        end
    end
    return list
end

-- Training Dummy's clear stagger: every staggered opponent's stagger ends now. Returns how many.
function M.clear_stagger(battle, actors)
    local cleared = 0
    for _, actor in ipairs(actors or {}) do
        if safe(function() return battle:IsBurst(actor) end) == true then
            safe(function() actor.Controller:EndBurstInstant() end)
            cleared = cleared + 1
        end
    end
    return cleared
end

return M
