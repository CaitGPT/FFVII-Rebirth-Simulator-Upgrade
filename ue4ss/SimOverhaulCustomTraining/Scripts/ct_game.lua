-- Custom Training's game calls. Every call is guarded; the object is checked before a member is named, because
-- naming a member an object lacks breaks the Lua state (cookbook).
local M = {}

local BATTLE_API = "/Script/EndGame.Default__EndBattleAPI"
local FIELD_API = "/Script/EndGame.Default__EndFieldAPI"
local MENU_API = "/Script/EndGame.Default__EndMenuAPI"
local STATICS = "/Script/Engine.Default__GameplayStatics"
local ENEMY_AI_CLASS = "/Script/EndGame.EndAIControllerEnemyBase" -- the class (Training Dummy passes it to IsA)
local STOP_STATUS = "BSC_Stop"
local STATUS_TIME_INFINITY = 64
local WAVE_DIRECT = 1        -- EEndEnemyTerritoryWaveType.ReinforcementsWaveType_Direct
local POP_DEFAULT = 0        -- EEndEnemyTerritoryWavePopSettingOverwrite.Default

local function safe(f, ...)
    local ok, v = pcall(f, ...)
    if ok then return v end
    return nil
end
M.safe = safe

function M.valid(o) return o ~= nil and safe(function() return o:IsValid() end) == true end
local valid = M.valid

local cache = {}
local function cdo(path)
    local o = cache[path]
    if valid(o) then return o end
    o = safe(StaticFindObject, path)
    if valid(o) then cache[path] = o; return o end
    return nil
end
M.cdo = cdo
function M.battle() return cdo(BATTLE_API) end
function M.field() return cdo(FIELD_API) end

local function text(v)
    if type(v) == "string" then return v end
    return safe(function() return v:ToString() end)
end
M.text = text

function M.name_of(o) return text(safe(function() return o:GetFName() end)) or "?" end

-- GetEnemyMembersRef fills an out array; UE4SS hands it back as the out table, a table holding one TArray, or a
-- TArray (Training Dummy).
function M.enemies()
    local battle = M.battle()
    if not battle then return {} end
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
        if valid(actor) then list[#list + 1] = actor end
    end
    if type(value) == "table" then
        if #value == 1 and type(value[1]) == "userdata" and safe(function() return value[1]:type() end) == "TArray" then
            safe(function() value[1]:ForEach(function(_, e) add(e) end) end)
        else
            for _, item in ipairs(value) do add(item) end
        end
    elseif type(value) == "userdata" then
        safe(function() value:ForEach(function(_, e) add(e) end) end)
    end
    return list
end

-- The territory an enemy belongs to, from its AI controller (Training Dummy), or nil.
function M.territory_of(actor)
    local controller = safe(function() return actor:GetController() end)
    local enemy_ai = cdo(ENEMY_AI_CLASS)
    if not (valid(controller) and enemy_ai and safe(function() return controller:IsA(enemy_ai) end) == true) then
        return nil
    end
    return text(safe(function() return controller:GetOwnerTerritoryIdBP() end))
end

function M.in_battle()
    local battle = M.battle()
    return battle ~= nil and safe(function() return battle:IsInBattle() end) == true
end

function M.hp(actor)
    local battle = M.battle()
    if not battle then return nil, nil end
    return safe(function() return battle:GetCharaHP(actor) end), safe(function() return battle:GetHPMax(actor) end)
end

-- The enemy's BattleCharaSpec id. GetCharaSpecName answers "CharaSpec_<id>" (seen 2026-11-20), so the prefix goes.
function M.spec(actor)
    local battle = M.battle()
    local name = battle and text(safe(function() return battle:GetCharaSpecName(actor) end))
    return name and (name:match("^CharaSpec_(.+)$") or name)
end

-- The BattleCharaSpec row the enemy fights with (GetBattleCharaSpec_DataTableID): its TextLabel is the name the game
-- shows on it. M.spec answers the model's spec, which eleven templates borrow from another enemy.
function M.battle_spec(actor)
    local battle = M.battle()
    local name = battle and text(safe(function() return battle:GetBattleCharaSpec_DataTableID(actor) end))
    return name ~= "" and name ~= "None" and name or nil
end

-- Out of the player's targeting: no lock-on, no auto-target, no nameplate, and no damage (hitDamage false). The hidden
-- anchor needs it: hidden and 60 m away, it was still the auto-target, its "Zu" plate over empty space (2026-11-21).
function M.untarget(actor)
    local battle = M.battle()
    if not battle then return false end
    local a = safe(function() battle:SetDisableTarget(actor, true, false, true); return true end)
    local b = safe(function() battle:SetHideTargetList(actor, true); return true end)
    return a == true and b == true
end

-- The object's address, for reading the game's own structures from outside while testing.
function M.address(o) return safe(function() return o:GetAddress() end) end

function M.refill(actor) local b = M.battle(); if b then safe(function() b:SetHPPercent(actor, 100) end) end end

-- Passive: an endless Stop holds the enemy still and stops its attacks; Stop also freezes stagger, so it is lifted
-- while the enemy is staggered (Training Dummy). Aggressive: no Stop.
function M.hold(actor, passive)
    local battle = M.battle()
    if not battle then return end
    local stop = FName(STOP_STATUS)
    local staggered = safe(function() return battle:IsBurst(actor) end) == true
    local stopped = safe(function() return battle:HasStatusChangeID(actor, stop) end) == true
    if passive and not staggered and not stopped then
        safe(function() battle:AddStatusChangeID(actor, stop, STATUS_TIME_INFINITY, true, nil, true) end)
    elseif stopped and (staggered or not passive) then
        safe(function() battle:RemoveStatusChangeID(actor, stop, false) end)
    end
end

-- The ailments and debuffs an opponent can leave on the party (BattleStatusChange, Epic 1.005): taken off when the
-- opponent changes or a course starts, so the party starts clean (owner 2026-11-21). Buffs are left alone.
M.BAD_STATUSES = {
    "BSC_Poison", "BSC_Poison_NoUpgrade", "BSC_HighlyPoison", "BSC_Anger", "BSC_Sad", "BSC_Silence", "BSC_Sleep",
    "BSC_Slow", "BSC_Stop", "BSC_PrePetrifaction", "BSC_Petrifaction", "BSC_Berserk", "BSC_HighBerserk", "BSC_Toad",
    "BSC_DeathSentence", "BSC_DeProtes", "BSC_DeShell", "BSC_DeBrave", "BSC_DeFaith", "BSC_Stun", "BSC_Unrecoverable",
    "BSC_GiCurse", "BSC_GiCurse_HP", "BSC_GiCurse_MP", "BSC_GiCurse_ATB", "BSC_GiCurse_Area", "BSC_Karma1",
    "BSC_Karma2", "BSC_Karma3",
}

-- Takes every bad status off an actor; returns the ones it had.
-- The ones that knock a member out whatever the HP: Condemned (death sentence) and stone. Training keeps the party up,
-- and a solo party knocked out ends the round (Iron Man's Condemned, the probe sweep 2026-11-21).
M.LETHAL_STATUSES = { "BSC_DeathSentence", "BSC_PrePetrifaction", "BSC_Petrifaction" }

-- Auto-Life (BSC_Reraise) on a member, with no end, if it is not there already: a blow above the member's whole HP
-- (the Tonberry King's knife, 7,722 at once) revives instead of knocking a solo party out, which ends the round.
-- Returns true when it was given now.
function M.keep_reraise(actor)
    local battle = M.battle()
    if not battle then return false end
    local id = FName("BSC_Reraise")
    if safe(function() return battle:HasStatusChangeID(actor, id) end) == true then return false end
    return safe(function() battle:AddStatusChangeID(actor, id, 64, true, actor, false); return true end) == true
end

function M.clear_bad_status(actor, ids)
    local battle = M.battle()
    local removed = {}
    if not battle then return removed end
    for _, id in ipairs(ids or M.BAD_STATUSES) do
        local name = FName(id)
        if safe(function() return battle:HasStatusChangeID(actor, name) end) == true then
            safe(function() battle:RemoveStatusChangeID(actor, name, false) end)
            removed[#removed + 1] = id
        end
    end
    return removed
end

-- Spawns one enemy from reinforcement wave <index> of <territory>. For the Direct wave type the integer arguments
-- are (count, wave index, 0, 0): seen 2026-11-20, (1, 5) gave one Vice from wave 5 and (5) alone gave five of wave 0.
function M.spawn_wave(territory, index)
    local field = M.field()
    if not field then return nil end
    -- The returned TArray<FName> cannot be read here: its elements' ToString raised "No overload found for function
    -- 'FName'" (2026-11-20), so only whether the call went through is reported.
    local ok = safe(function() field:StartReinforcementsWave(FName(territory), WAVE_DIRECT, POP_DEFAULT, 1, index, 0, 0); return true end)
    return ok and { "requested" } or {}
end

-- Removes one enemy of <territory> (not counted as a kill). The game knows it by its territory spawn name, which
-- GetActorName gives ("mobcolvr_..._001Wave@territoryCmn_VRBattle"), under our own territory row (seen 2026-11-20:
-- the object's FName, or territoryCmn_VRBattle as the territory, did nothing).
function M.remove(territory, actor)
    local field, battle = M.field(), M.battle()
    if not (field and battle) then return false end
    local name = text(safe(function() return battle:GetActorName(actor) end))
    if not name or name == "" then return false end
    -- Everything it fired goes with it (owner 2026-11-21: Bahamut's purple orbs stayed after the change): the game's
    -- own cleanup for one character's bullets, orbs and other damage sources, with their effects, forced.
    M.clear_damage_sources(actor)
    return safe(function() field:RequestDestroyEnemyInTerritory(FName(territory), FName(name), false); return true end) == true
end

-- UEndBattleAPI.DestroyDamageSourceAllCharacter(character, destroy effect, force): every damage source (bullet, orb,
-- area, field object that hurts) the character owns.
function M.clear_damage_sources(actor)
    local battle = M.battle()
    if not battle then return false end
    return pcall(function() battle:DestroyDamageSourceAllCharacter(actor, true, true) end)
end

-- The names of the damage sources (bullets, orbs) a character owns or set off, read before it is removed so what is
-- left of them afterwards can be counted (the pool's total moves with the game's own pooling). The owner and instigator
-- are checked before anything is called on them (a call through a null object faults inside UE4SS).
function M.owned_damage_sources(actor)
    local names = {}
    local list = safe(function() return FindAllOf("EndBattleDamageSourceActor") end)
    local mine = M.address(actor)
    if type(list) ~= "table" or not mine then return names end
    for _, a in ipairs(list) do
        if M.valid(a) then
            local o = safe(function() return a:GetOwner() end)
            local i = safe(function() return a.Instigator end)
            if (M.valid(o) and M.address(o) == mine) or (M.valid(i) and M.address(i) == mine) then
                names[#names + 1] = M.name_of(a)
            end
        end
    end
    return names
end

-- For the log: the owner, instigator and attach parent of the first few shown damage sources (each checked valid first).
function M.damage_source_owners(limit)
    local out = {}
    local list = safe(function() return FindAllOf("EndBattleDamageSourceActor") end)
    if type(list) ~= "table" then return out end
    local function nm(o) return M.valid(o) and M.name_of(o) or "-" end
    for _, a in ipairs(list) do
        if #out >= (limit or 5) then break end
        if M.valid(a) and safe(function() return a.bHidden end) == false then
            local o = safe(function() return a:GetOwner() end)
            local i = safe(function() return a.Instigator end)
            local p = safe(function() return a:GetAttachParentActor() end)
            out[#out + 1] = M.name_of(a) .. " owner " .. nm(o) .. " instigator " .. nm(i) .. " attached " .. nm(p)
        end
    end
    return out
end

-- In play: not hidden, ticking, and not parked at the world's origin. The game's pool keeps idle ones unhidden there
-- with ticking off (read after a Bahamut change, 2026-11-22: 9 "shown", all at 0,0,0, 2.2 km from the party).
function M.damage_source_in_play(a)
    if not M.valid(a) or safe(function() return a.bHidden end) ~= false then return false end
    if safe(function() return a:IsActorTickEnabled() end) == false then return false end
    local l = safe(function() return a:K2_GetActorLocation() end)
    return l ~= nil and not (math.abs(l.X) < 1 and math.abs(l.Y) < 1 and math.abs(l.Z) < 1)
end

-- The names of the damage sources shown now. They carry no owner, instigator or attach parent (Bahamut's, read in the
-- game, 2026-11-22), so a change takes the names of those shown just before it and counts what is left of them.
function M.shown_damage_sources()
    local names = {}
    local list = safe(function() return FindAllOf("EndBattleDamageSourceActor") end)
    if type(list) ~= "table" then return names end
    for _, a in ipairs(list) do
        if M.damage_source_in_play(a) then names[#names + 1] = M.name_of(a) end
    end
    return names
end

-- How many of the named damage sources are still there and shown.
function M.damage_sources_left(names)
    if not next(names) then return 0 end
    local list = safe(function() return FindAllOf("EndBattleDamageSourceActor") end)
    if type(list) ~= "table" then return 0 end
    local n = 0
    for _, a in ipairs(list) do
        if names[M.name_of(a)] and M.damage_source_in_play(a) then n = n + 1 end
    end
    return n
end

-- How many damage-source actors exist (EndBattleDamageSourceActor: the game's bullets and orbs), for the checks:
-- one narrow class, never every actor (a scan of all actors as a course was spawning crashed UE4SS, 2026-11-21).
-- Only those shown: the game keeps a pool of hidden ones (34 before a change and 38 after one, Bahamut, 2026-11-21).
function M.damage_source_count()
    local list = safe(function() return FindAllOf("EndBattleDamageSourceActor") end)
    if type(list) ~= "table" then return 0 end
    local n = 0
    for _, a in ipairs(list) do
        if M.damage_source_in_play(a) then n = n + 1 end
    end
    return n
end

-- An FName's comparison index (the number the game keeps in its tables), or nil.
local fname_cache = {}
function M.fname_index(name)
    local cached = fname_cache[name]
    if cached then return cached end
    local index = safe(function() return FName(name):GetComparisonIndex() end)
    if type(index) == "number" and index > 0 then fname_cache[name] = index; return index end
    return nil
end

-- The anchor: the course's opening enemy, kept alive out of sight so the round always has an enemy (the round ends
-- when every enemy is defeated, and a level 70 party can defeat an opponent with one blow, faster than any refill).
-- It is moved 60 m away, hidden, made solid to nothing, and its HP bar hidden; main.lua's session holds it with Stop.
-- Where an actor is ({ X, Y, Z } in cm), and whether it is hidden (for the opponent sweep's checks).
function M.location(actor)
    local loc = safe(function() return actor:K2_GetActorLocation() end)
    if not loc then return nil end
    return { X = loc.X, Y = loc.Y, Z = loc.Z }
end

-- Placing spawned enemies (owner 2026-11-21): on the floor, and apart by their own size. A line trace on the
-- Visibility channel, ignoring the given actors (the enemies and the party), read in the game: it hit the arena floor
-- exactly under Cloud (Z 10000, his capsule's half height 88 above).
local KSL = "/Script/Engine.Default__KismetSystemLibrary"
local CLEAR = { R = 0, G = 0, B = 0, A = 0 }
local function trace(context, from, to, ignore)
    local ksl = cdo(KSL)
    if not ksl then return nil end
    local hit = {}
    local ok, blocked = pcall(function()
        return ksl:LineTraceSingle(context, from, to, 0, false, ignore or {}, 0, hit, true, CLEAR, CLEAR, 0)
    end)
    if not (ok and blocked) then return nil end
    return safe(function() return { X = hit.Location.X, Y = hit.Location.Y, Z = hit.Location.Z } end)
end
M.trace = trace

-- The floor's height under spot (cm), from 0.5 m above it down to 50 m below; nil when there is none.
function M.floor_z(context, spot, ignore)
    local hit = trace(context, { X = spot.X, Y = spot.Y, Z = spot.Z + 50 }, { X = spot.X, Y = spot.Y, Z = spot.Z - 5000 }, ignore)
    return hit and hit.Z
end

-- Whether nothing (a wall) stands between a and b.
function M.clear_way(context, a, b, ignore) return trace(context, a, b, ignore) == nil end

-- An actor's size: capsule half height and radius, the larger half side of its bounds (cm), and its movement mode
-- (1 walking, 3 falling, 5 flying: Zu, which flies, read 5 with no gravity).
function M.size(actor)
    -- A component is checked before anything is called on it: a call through a null object faults inside UE4SS,
    -- which pcall cannot catch (crash-220 on our 18:09 crash: GetFName on an actor's missing owner).
    local cap = safe(function() return actor.CapsuleComponent end)
    if not M.valid(cap) then cap = nil end
    local half = cap and safe(function() return cap:GetScaledCapsuleHalfHeight() end)
    local radius = cap and safe(function() return cap:GetScaledCapsuleRadius() end)
    local origin, extent = {}, {}
    local ext = nil
    if pcall(function() actor:GetActorBounds(true, origin, extent, false) end) then
        ext = safe(function() return math.max(extent.X, extent.Y) end)
    end
    local move = safe(function() return actor.CharacterMovement end)
    local mode = M.valid(move) and safe(function() return move.MovementMode end) or nil
    return { half = half, radius = radius, extent = ext, mode = mode }
end

-- Moved to spot ({ X, Y, Z } in cm) at once (teleport, no sweep): copies spawned on top of one another.
function M.move_to(actor, spot)
    return pcall(function() actor:K2_SetActorLocation(spot, false, {}, true) end)
end

function M.hidden(actor) return safe(function() return actor.bHidden end) == true end

function M.stash(actor, spot)
    local battle = M.battle()
    local loc = safe(function() return actor:K2_GetActorLocation() end)
    if not loc then return nil end
    spot = spot or { X = loc.X + 6000, Y = loc.Y, Z = loc.Z }
    safe(function() actor:K2_SetActorLocation(spot, false, {}, true) end)
    safe(function() actor:SetActorHiddenInGame(true) end)
    safe(function() actor:SetActorEnableCollision(false) end)
    if battle then safe(function() battle:SetShowEnemyStatusGUI(actor, false) end) end
    return spot
end

-- The party ---------------------------------------------------------------------------------------------------
-- Training Dummy's route: battle members by slot with their EPlayerType (GetPlayerType(actor) fails in this game).
local PARTY_API = "/Script/EndGame.Default__EndPartyAPI"
local MENU_BP_API = "/Script/EndGame.Default__EndMenuBPAPI"
local PLAYER_NAMES = { [0] = "Cloud", "Barret", "Tifa", "Aerith", "Red XIII", "Yuffie", "Cait Sith", "Zack",
    "Sephiroth", "Vincent", "Cid" }

-- list of { id, actor, kind, hp, max }
function M.party()
    local party = cdo(PARTY_API)
    local list = {}
    if not party then return list end
    local count = safe(function() return party:GetBattleMemberCount() end) or 0
    for i = 0, math.min(count, 4) - 1 do
        local member = safe(function() return party:GetBattleMember(i) end)
        local kind = safe(function() return party:GetBattleMemberType(i) end)
        if valid(member) then
            local hp, max = M.hp(member)
            list[#list + 1] = { id = PLAYER_NAMES[kind] or M.name_of(member), actor = member, kind = kind, hp = hp, max = max }
        end
    end
    return list
end

function M.set_hp_percent(actor, percent)
    local battle = M.battle()
    if battle then safe(function() battle:SetHPPercent(actor, percent) end) end
end

-- MP refilled as it is spent (Training Dummy's unlimited MP): the live battle MP, by EPlayerType. Returns the MP
-- given back (the meters count it as MP spent).
function M.refill_mp(kind)
    local menu = cdo(MENU_BP_API)
    if not (menu and kind) then return end
    local mp = safe(function() return menu:BPGetPlayerMP(kind) end)
    local max = safe(function() return menu:BPGetPlayerMaxMP(kind) end)
    if type(mp) == "number" and type(max) == "number" and mp < max then
        safe(function() menu:BPSetPlayerMP(kind, max) end)
        return max - mp
    end
    return 0
end

-- MP to full (unlimited MP or not: a new opponent starts with a full bar).
function M.full_mp(kind)
    local menu = cdo(MENU_BP_API)
    if not (menu and kind) then return end
    local max = safe(function() return menu:BPGetPlayerMaxMP(kind) end)
    if type(max) == "number" then safe(function() menu:BPSetPlayerMP(kind, max) end) end
end

-- A game text key ("$en_Ogre_OrcEnd2") in the game's language, or nil.
function M.lookup(key)
    local menu = cdo(MENU_API)
    local v = menu and text(safe(function() return menu:GetString(key) end))
    if v and v ~= "" and v ~= key then return v end
    return nil
end

-- A line in the game's own message log (top left, as the game's notices): UEndMenuAPI.AddMessageLog_AnyThread with
-- the plain icon, effect, colour and options.
function M.notice(message)
    local menu = cdo(MENU_API)
    if not menu then return false end
    return pcall(function() menu:AddMessageLog_AnyThread(0, message, 0, 0, 0) end)
end

-- Frames per second now (1 / the world's last frame time), for the test tools; nil when it can't be read.
function M.frame_rate(context)
    local statics = cdo(STATICS)
    local dt = statics and context and safe(function() return statics:GetWorldDeltaSeconds(context) end)
    if type(dt) == "number" and dt > 0 then return 1 / dt end
    return nil
end

-- The player controller (looked up through GameplayStatics with the party leader as the world context).
function M.controller()
    local statics, battle = cdo(STATICS), M.battle()
    local leader = battle and safe(function() return battle:GetPartyLeader() end)
    if not (statics and valid(leader)) then return nil end
    local c = safe(function() return statics:GetPlayerController(leader, 0) end)
    return valid(c) and c or nil, leader
end

-- The set of the named engine keys (FKey names such as "Gamepad_DPad_Up", "Enter") held now.
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

local panel_ok, panel = pcall(require, "ct_panel")
function M.show_panel(view)
    if not panel_ok then return false, "ct_panel did not load: " .. tostring(panel) end
    local _, leader = M.controller()
    if not leader then return false, "no party leader" end
    return panel.show(view, leader)
end

function M.hide_panel()
    if panel_ok then panel.hide() end
end

-- The game is paused while the settings panel is open (as Junon Colosseum pauses under its message window).
function M.pause(on)
    local statics, battle = cdo(STATICS), M.battle()
    if not (statics and battle) then return false end
    local context = safe(function() return battle:GetPartyLeader() end)
    return safe(function() statics:SetGamePaused(context, on); return true end) == true
end

return M
