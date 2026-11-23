-- Every call into the game. Each function names what it relies on and, where it matters, what was seen in the game
-- (docs/LIVE-RESULTS.md).
--
-- Rules from our other mods (FFVII-Modding skills/create-rebirth-mod/references/cookbook.md):
--   * never name a member an object lacks, even in pcall: the failed lookup leaks the Lua C stack;
--   * FindAllOf costs about 0.2 s on the game thread whatever the class (measured 2026-11-17), so every search is
--     made behind the loading screen and references are kept.
local M = {}

local DATABASE_API = "/Script/EndGame.Default__EndDataBaseAPI"
local WORLD_API = "/Script/EndGame.Default__EndWorldAPI"
local MENU_API = "/Script/EndGame.Default__EndMenuAPI"
local BATTLE_API = "/Script/EndGame.Default__EndBattleAPI" -- GetPartyLeader lives here, not on EndPartyAPI
local MESSAGE_PAUSE_MENU = 2 -- EEndMenuMessageWindowFlags.PauseMenu
local IN_SIMULATOR_FLAGS = { "stfCmn_IsInVR_EASTC", "stfCmn_IsInVR_WESTC" }
local SWITCH_SEAMLESS = 1 -- EEndStreamingSwitchType::Seamless

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end
-- Never ask a kept object whether it is still valid once the game may have destroyed it: UE4SS reads the object's
-- memory to answer, and if the game has freed that memory the game crashes (UE4SS.dll+0x6a8c4f, reading the object's
-- InternalIndex; six crashes on 2026-11-18, two of them at this mod's check of the last visit's simulator levels, and
-- one more at 17:31 the same day a second into an arrival, after objects were no longer kept from one visit to the next:
-- the game can also replace an object within a visit, while it loads).
-- So a level stream is never kept as an object past the moment it was found, not even for a tick: it is kept as a
-- reference, its path and address, and `fresh` finds it again by its path (StaticFindObject never touches the old
-- pointer) and returns it only if it is the same object. Only streams can be found this way: they hang straight off
-- the world (`/Game/Level/Game/EndGame.EndGame:LevelStreamingDynamic_1`). An actor in a level, the level itself, a
-- widget or a volume in a world plan is not found by its path in this game (tried 2026-11-18), so `fresh` returns nil
-- for those: the actors this mod keeps are found only once the loader is idle and used only within that visit, and
-- whatever is put back after a visit is put back only if it can be found (see `set_dressing_hidden`).
local function ref(object)
    local name = safe(function() return object:GetFullName() end)
    return { path = name and name:match("^%S+ (.+)$"), address = safe(function() return object:GetAddress() end) }
end
local function fresh(kept)
    if not (kept and kept.path) then return nil end
    local object = safe(StaticFindObject, kept.path)
    if not valid(object) then return nil end
    if kept.address and safe(function() return object:GetAddress() end) ~= kept.address then return nil end
    return object
end
local function cdo(path)
    local object = safe(StaticFindObject, path)
    if valid(object) then return object end
    return nil
end

-- Story flags: UEndDataBaseAPI.IsStoryFlag(FName), as Junon Colosseum reads them.
function M.flag(name)
    local api = cdo(DATABASE_API)
    if not api then return false end
    return safe(function() return api:IsStoryFlag(FName(name)) end) == true
end

-- The game sets one of these while a simulator course runs (0000-COMON_VR's level script names both).
function M.in_simulator()
    for _, flag in ipairs(IN_SIMULATOR_FLAGS) do
        if M.flag(flag) then return true end
    end
    return false
end

-- Each world has one AEndStreamingVolume labelled COMMON_VR that streams 0000-COMON_VR at its TargetLocation
-- (1000-EASTC_WorldPlan, 2000-WESTC_WorldPlan_MiniGame). Returns { { name = actor name, object = volume } }.
function M.vr_volumes(label)
    local found = {}
    for _, volume in ipairs(safe(FindAllOf, "EndStreamingVolume") or {}) do
        if valid(volume) and safe(function() return volume.VolumeLabel:ToString() end) == label then
            found[#found + 1] = { name = safe(function() return volume:GetFName():ToString() end) or "?", object = volume }
        end
    end
    return found
end

-- AEndStreamingVolume.TargetLocation (FVector) and TargetRotationDegree (float), both BlueprintReadWrite.
function M.get_target(volume)
    local v = volume.object
    if not valid(v) then return nil end
    local x = safe(function() return v.TargetLocation.X end)
    local y = safe(function() return v.TargetLocation.Y end)
    local z = safe(function() return v.TargetLocation.Z end)
    local yaw = safe(function() return v.TargetRotationDegree end)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
    return { location = { X = x, Y = y, Z = z }, yaw = type(yaw) == "number" and yaw or 0 }
end

-- Writes the target and reads it back. True only when the volume now holds the requested values.
function M.set_target(volume, location, yaw)
    local v = volume.object
    if not valid(v) then return false end
    safe(function() v.TargetLocation = { X = location.X, Y = location.Y, Z = location.Z } end)
    safe(function() v.TargetRotationDegree = yaw or 0 end)
    local now = M.get_target(volume)
    if not now then return false end
    local function near(a, b) return math.abs(a - b) < 1 end
    return near(now.location.X, location.X) and near(now.location.Y, location.Y) and near(now.location.Z, location.Z)
end

-- The simulator volume hides far terrain while it is active (HideLevelsInstead: 45 levels in the east, 117 in the
-- west, the west's including Corel's own terrain). AEndStreamingVolume.ShowHideInsteadLevels(bShow, bHideDrawOnly)
-- shows them again.
function M.show_hidden_levels(volume)
    local v = volume.object
    if not valid(v) then return false end
    return pcall(function() v:ShowHideInsteadLevels(true, false) end)
end

-- The simulator's own look: a floor prop and rotating blocks (actors in 0000-COMON_VR_Terrain_Strip), and the
-- spotlight and floating-cube levels. Actors are hidden one by one; the two levels are hidden as streaming levels.
-- With `sky_too`, the simulator's sky level (0001-WORLD_VRSky) is hidden as well, for a stage that brings its own.
-- The flat collision in 0000-COMON_VR_Terrain_Strip is left alone.
local SIMULATOR_SKY = "0001-WORLD_VRSky"
local hidden_actors, hidden_streams, hidden_components = {}, {}, {}
local hidden_seen = {} -- what is already in those lists, by address, so a repeat does not add it twice
-- The simulator's rim clutter (low blocks, 30 to 50 cm) collides through this actor of its terrain level. Hidden
-- with the rest of the look it would be an invisible obstacle, so its collision goes off with it (measured in the
-- game 2026-11-17: with it off the floor is flat out to the pillars at about 24 m). AActor.SetActorEnableCollision.
local RIM_COLLISION = "Spl_CST"
local collision_off = {}
-- Has the game finished bringing the simulator in? True when its lighting, effect and sky levels all exist and are
-- loaded and visible. The game loads them in turn while the "Get Ready" screen is up, the effect level last, so all
-- three showing means it is done with them. Also returns how many of them exist.
-- The game makes these levels anew on every visit. They are searched for at most once a second (a search every
-- 100 ms during the load slowed it from 8 s to 34 s, 2026-11-17); once all are found, each call only asks the kept
-- levels whether they are loaded and visible, which is cheap enough for every tick. Call only with the loader idle.
local simulator_levels, simulator_searched_at = {}, nil -- { stream, which } for each of the simulator's own levels
local function find_simulator_levels(vr_stage)
    local seen = {}
    simulator_levels = {}
    for _, stream in ipairs(safe(FindAllOf, "LevelStreamingDynamic") or {}) do
        if valid(stream) then
            local package = safe(function() return stream:GetWorldAssetPackageFName():ToString() end) or ""
            local which = package:find(SIMULATOR_SKY, 1, true) and SIMULATOR_SKY or nil
            for _, level in ipairs(vr_stage.dressing_levels) do
                if package:find(level, 1, true) then which = level end
            end
            if which and not seen[which] then
                seen[which] = true
                simulator_levels[#simulator_levels + 1] = { stream = ref(stream), which = which }
            end
        end
    end
    return #simulator_levels
end
function M.simulator_shown(vr_stage, now)
    local expected, have = #vr_stage.dressing_levels + 1, 0
    local streams = {}
    for _, entry in ipairs(simulator_levels) do
        local stream = fresh(entry.stream)
        if stream then
            have = have + 1
            streams[#streams + 1] = stream
        end
    end
    if have < expected then
        if simulator_searched_at == now then return false, have end
        simulator_searched_at = now
        have = find_simulator_levels(vr_stage)
        if have < expected then return false, have end
        streams = {}
        for _, entry in ipairs(simulator_levels) do
            local stream = fresh(entry.stream)
            if not stream then return false, have end
            streams[#streams + 1] = stream
        end
    end
    for _, stream in ipairs(streams) do
        if safe(function() return stream:IsLevelLoaded() end) ~= true
            or safe(function() return stream:IsLevelVisible() end) ~= true then
            return false, have
        end
    end
    return true, have
end

-- A black screen of the game's own (UEndMenuAPI.AddFadeFilter, the overlay its menus fade with) over everything but the
-- HUD of other mods. Without it the Temple's arrival showed the simulator for 3 s, then a darkened simulator and the
-- swap for 6 s (2026-11-18).
-- `on` true puts it up at once; false fades it out over `seconds` and lets the game drop it.
local BLACK_FILTER = "SimStagesBlack"
local black_up = false
function M.black_screen(on, seconds)
    local api = StaticFindObject("/Script/EndGame.Default__EndMenuAPI")
    if not valid(api) then return false end
    local black, clear = { R = 0, G = 0, B = 0, A = 1 }, { R = 0, G = 0, B = 0, A = 0 }
    if on then
        if black_up then return true end
        local context = safe(FindFirstOf, "PlayerController")
        if not valid(context) then return false end
        black_up = pcall(function() api:AddFadeFilter(context, FName(BLACK_FILTER), 9000, black, black, 0.0, false, false) end)
        return black_up
    end
    if not black_up then return false end
    black_up = false
    return pcall(function() api:ChangeFadeFilter(FName(BLACK_FILTER), clear, seconds or 0.4, true, false) end)
end

-- Has the fight begun? UEndBattleAPI.IsInBattle on its default object: no search. Called only after arrival in the
-- simulator (at boot and on the title screen the battle functions crashed Battle Meters).
local BATTLE_API = "/Script/EndGame.Default__EndBattleAPI"
function M.in_battle()
    local api = StaticFindObject(BATTLE_API)
    if not valid(api) then return false end
    return safe(function() return api:IsInBattle() end) == true
end

-- The world's clock held almost still (UGameplayStatics.SetGlobalTimeDilation at the engine's minimum), so a fight
-- that begins behind the black screen waits for the player: players reported fights starting while it was still up
-- on machines that load faster than ours (2026-11-20). Level streaming does not run on the world's clock. `on` false
-- puts back the dilation that was there before. Returns true when it changed something.
local HELD_DILATION = 0.0001
local dilation_before = nil
function M.hold_fight(on)
    local statics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local context = safe(FindFirstOf, "PlayerController")
    if not valid(statics) or not valid(context) then return false end
    if on then
        if dilation_before then return false end
        local before = safe(function() return statics:GetGlobalTimeDilation(context) end)
        if type(before) ~= "number" or before <= HELD_DILATION then before = 1 end
        if pcall(function() statics:SetGlobalTimeDilation(context, HELD_DILATION) end) then
            dilation_before = before
            return true
        end
        return false
    end
    if not dilation_before then return false end
    local before = dilation_before
    dilation_before = nil
    return pcall(function() statics:SetGlobalTimeDilation(context, before) end)
end

-- What makes up the simulator's own look, found ahead of the moment it goes and kept, so that moment only flips
-- kept objects. Each FindAllOf here costs about 0.2 s (it walks the whole object table, measured 2026-11-17); eight
-- of them at the swap froze the screen on the simulator's stage for two seconds. Returns how many things were found
-- (18 when the simulator is fully in: 16 scenery actors, its skyline component and its rim collision).
local dressing_ready = nil
-- Is the simulator's floor there yet? One search (about 0.2 s), to decide when the full look-up is worth making.
function M.scenery_present(vr_stage)
    for _, actor in ipairs(safe(FindAllOf, vr_stage.dressing_classes[1]) or {}) do
        if valid(actor) then return true end
    end
    return false
end
function M.prepare_dressing(vr_stage)
    local found = { actors = {}, components = {}, collision = {}, ground = {} }
    for _, actor in ipairs(safe(FindAllOf, "CollisionAssetActor") or {}) do
        if valid(actor) then
            local name = safe(function() return actor:GetFullName() end) or ""
            if name:find(vr_stage.collision_level, 1, true) then
                if name:find(RIM_COLLISION, 1, true) then
                    found.collision[#found.collision + 1] = actor
                else
                    found.ground[#found.ground + 1] = actor -- the flat floor, kept unless the stage has its own
                end
            end
        end
    end
    -- The block skyline round the simulator is drawn by its terrain level's massive-environment component, which
    -- hiding the actors does not touch (seen in the game 2026-11-17).
    for _, actor in ipairs(safe(FindAllOf, "MassiveEnvironmentActor") or {}) do
        if valid(actor) and (safe(function() return actor:GetFullName() end) or ""):find(vr_stage.collision_level, 1, true) then
            local component = safe(function() return actor.MassiveEnvironmentComponent end)
            if valid(component) then found.components[#found.components + 1] = component end
        end
    end
    for _, class in ipairs(vr_stage.dressing_classes) do
        for _, actor in ipairs(safe(FindAllOf, class) or {}) do
            if valid(actor) then found.actors[#found.actors + 1] = actor end
        end
    end
    dressing_ready = found
    return #found.actors + #found.components + #found.collision
end

-- Level streaming's per-frame budgets. The engine's defaults add and remove a level's components a few at a time in
-- about 1 to 5 ms a frame, which made leaving the Cave of the Gi (66 levels) take 79 s back to the course list against
-- 43 s from the plain simulator; with these raised it took 53 s, and its levels were in 8 s after arrival instead of
-- 11 (measured 2026-11-18). Raised only while a stage loads or unloads, then put back to the game's own values: in
-- the field the game streams all the time, and big budgets there would cost frames.
local FAST_STREAMING = {
    ["s.UnregisterComponentsTimeLimit"] = 20, ["s.LevelStreamingComponentsUnregistrationGranularity"] = 100,
    ["s.LevelStreamingActorsUpdateTimeLimit"] = 20, ["s.LevelStreamingComponentsRegistrationGranularity"] = 100,
    ["s.AsyncLoadingTimeLimit"] = 20,
}
local saved_streaming = nil
function M.fast_streaming(on)
    local library = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    if not valid(library) then return false end
    local context = safe(FindFirstOf, "PlayerController")
    if not valid(context) then return false end
    local function set(name, value)
        return pcall(function() library:ExecuteConsoleCommand(context, name .. " " .. tostring(value), nil) end)
    end
    -- Reading a console variable runs game code that can re-enter this mod: work on local copies only.
    if on then
        if not saved_streaming then
            local saved = {}
            for name in pairs(FAST_STREAMING) do
                saved[name] = safe(function() return library:GetConsoleVariableFloatValue(name) end)
            end
            saved_streaming = saved
        end
        for name, value in pairs(FAST_STREAMING) do set(name, value) end
        return true
    end
    local saved = saved_streaming
    if not saved then return false end
    saved_streaming = nil
    for name, value in pairs(saved) do
        if type(value) == "number" and value > 0 then set(name, value) end
    end
    return true
end

-- Unloading in the background, at the game's own streaming budgets, while the player is back at the course list. With
-- the raised budgets the unload and then the engine's garbage collection of 77 levels at once stalled the game for 1
-- to 1.8 s at a time in the menu (the owner: "laggy with input", 2026-11-18). While on, the engine collects a little
-- every frame while levels wait to be purged (s.ContinuouslyIncrementalGCWhileLevelsPendingPurge) instead of all at
-- once; off puts the game's own value back.
local GC_SPREAD = "s.ContinuouslyIncrementalGCWhileLevelsPendingPurge"
local saved_gc = nil
function M.background_unload(on)
    local library = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    if not valid(library) then return false end
    local context = safe(FindFirstOf, "PlayerController")
    if not valid(context) then return false end
    if on then
        if saved_gc == nil then
            saved_gc = safe(function() return library:GetConsoleVariableFloatValue(GC_SPREAD) end) or 0
        end
        return pcall(function() library:ExecuteConsoleCommand(context, GC_SPREAD .. " 1", nil) end)
    end
    local saved = saved_gc
    if saved == nil then return false end
    saved_gc = nil
    return pcall(function() library:ExecuteConsoleCommand(context, GC_SPREAD .. " " .. tostring(math.floor(saved)), nil) end)
end

-- The simulator's hidden floor, pillars and walls still collide when hidden: its pillars and walls are invisible walls
-- about 24 m out, inside the real edge of a larger stage, and its flat floor runs on past a stage's own edges (owner,
-- 2026-11-18). The game keeps fighters inside the battle area by itself (a fighter put past the Temple's edge was back
-- on it within 1.5 s), so the pillars and walls are dropped for every streamed stage; the floor only for a stage with
-- its own (`with_floor`). Put back with the rest of the look (set_dressing_hidden false). Returns how many actors.
local FLOOR_CLASS = "BG0342_00_Floor_VR_C"
function M.drop_simulator_collision(with_floor)
    if not dressing_ready then return 0 end
    local count = 0
    local function drop(actor)
        if valid(actor) and pcall(function() actor:SetActorEnableCollision(false) end) then
            local key = tostring(safe(function() return actor:GetAddress() end) or actor)
            if not hidden_seen["ground:" .. key] then
                hidden_seen["ground:" .. key] = true
                collision_off[#collision_off + 1] = ref(actor)
            end
            count = count + 1
        end
    end
    for _, actor in ipairs(dressing_ready.actors) do
        local class = safe(function() return actor:GetClass():GetFName():ToString() end) or ""
        if with_floor or class ~= FLOOR_CLASS then drop(actor) end
    end
    if with_floor then
        for _, actor in ipairs(dressing_ready.ground) do drop(actor) end
    end
    return count
end

-- `what`: "scenery" hides only the actors, skyline and rim collision (safe at any time: no level's state changes);
-- nil hides those and the simulator's lighting, effect and sky levels.
function M.set_dressing_hidden(vr_stage, hidden, sky_too, what)
    local count = 0
    if not hidden then
        -- Show exactly what was hidden, from the kept references: no search while the game loads its way out.
        -- From references found again by path: by now the game may have destroyed them (it makes the simulator's
        -- levels anew on every visit), and then there is nothing to put back.
        for _, kept in ipairs(hidden_actors) do
            local actor = fresh(kept)
            if actor and pcall(function() actor:SetActorHiddenInGame(false) end) then count = count + 1 end
        end
        for _, kept in ipairs(hidden_streams) do
            local stream = fresh(kept)
            if stream and pcall(function() stream:SetShouldBeVisible(true) end) then count = count + 1 end
        end
        for _, kept in ipairs(hidden_components) do
            local component = fresh(kept)
            if component and pcall(function()
                component:SetHiddenInGame(false, true)
                component:SetVisibility(true, true)
            end) then count = count + 1 end
        end
        for _, kept in ipairs(collision_off) do
            local actor = fresh(kept)
            if actor and pcall(function() actor:SetActorEnableCollision(true) end) then count = count + 1 end
        end
        hidden_actors, hidden_streams, hidden_components, collision_off = {}, {}, {}, {}
        hidden_seen, dressing_ready = {}, nil
        return count
    end
    -- Hide from what was found beforehand; search now only if nothing was (that is the slow path).
    if not dressing_ready then M.prepare_dressing(vr_stage) end
    if what ~= "scenery" and #simulator_levels == 0 then find_simulator_levels(vr_stage) end
    local function keep(list, object, kept)
        local key = tostring(safe(function() return object:GetAddress() end) or object)
        if not hidden_seen[key] then
            hidden_seen[key] = true
            list[#list + 1] = kept or ref(object) -- put back later from a reference: see `fresh`
        end
    end
    for _, actor in ipairs(dressing_ready.collision) do
        if valid(actor) and pcall(function() actor:SetActorEnableCollision(false) end) then
            keep(collision_off, actor)
            count = count + 1
        end
    end
    for _, component in ipairs(dressing_ready.components) do
        if valid(component) and pcall(function()
            component:SetHiddenInGame(true, true)
            component:SetVisibility(false, true)
        end) then
            keep(hidden_components, component)
            count = count + 1
        end
    end
    for _, actor in ipairs(dressing_ready.actors) do
        if valid(actor) and pcall(function() actor:SetActorHiddenInGame(true) end) then
            keep(hidden_actors, actor)
            count = count + 1
        end
    end
    if what == "scenery" then return count end
    for _, entry in ipairs(simulator_levels) do
        local stream = fresh(entry.stream)
        -- Only a level the game has already shown: one told to hide while the game is still bringing it in
        -- holds up the start of the fight (seen in the game 2026-11-17).
        if stream and (sky_too or entry.which ~= SIMULATOR_SKY)
            and safe(function() return stream:IsLevelVisible() end) == true
            and pcall(function() stream:SetShouldBeVisible(false) end) then
            keep(hidden_streams, stream, entry.stream)
            count = count + 1
        end
    end
    return count
end

-- UEndWorldAPI.SwitchStreamingVolume(VolumeLabel, SwitchLabel, SwitchType). An empty label means the volume's own
-- default (its NoneSwitchLabel), which is the region's daytime sky.
function M.switch_sky(sky)
    local api = cdo(WORLD_API)
    if not api then return false end
    local label = (sky.label and sky.label ~= "") and sky.label or "None"
    return pcall(function() api:SwitchStreamingVolume(FName(sky.volume), FName(label), SWITCH_SEAMLESS) end)
end

-- Chapter progress (12000 = Chapter 12) and whether the game has been finished, as Junon Colosseum reads them.
function M.progress()
    local api = cdo(DATABASE_API)
    local value = api and safe(function() return api:GetChapterProgress() end)
    return type(value) == "number" and value or nil
end
function M.cleared() return M.flag("stfComn_Release_ChapterSelect") end

-- Streamed stages. UE4SS 3.0.1's Lua cannot call LevelStreamingDynamic.LoadLevelInstance (its bool out-parameter
-- breaks the argument stack), so the native helper (native/, dlls/main.dll) makes that call on the game thread.
-- The two sides talk through files in the mod's folder, as Junon Colosseum's do:
--   stages-helper.txt   written by the helper twice a second: tick, ready (its checks on the game's code passed)
--   stages-request.txt  written here: load <tab> name <tab> package <tab> x <tab> y <tab> z <tab> yaw, one per line
--   stages-ack.txt      written by the helper: name <tab> loaded | refused <tab> reason
-- The helper loads each level as a new instance called `name` at that position. Everything after that is plain Lua
-- on the streaming object.
local MOD_DIR = (debug.getinfo(1, "S").source:match("^@(.*[\\/])[Ss]cripts[\\/]")) or ""
local helper = { tick = nil, changed_at = nil, ready = false, loading = true, idle_since = nil }

-- The helper's clock in milliseconds (it moves every half second), for timing notes in the log; nil without a helper.
function M.clock()
    return tonumber(helper.tick)
end

-- Call a few times a second (plain file reading, any thread). The helper counts as present while its tick moves.
function M.helper_poll(now)
    local file = io.open(MOD_DIR .. "stages-helper.txt", "rb")
    if not file then
        helper.tick, helper.changed_at, helper.ready, helper.loading, helper.idle_since = nil, nil, false, true, nil
        return
    end
    local text = file:read("a") or ""
    file:close()
    local tick = text:match("tick\t(%d+)")
    if tick and tick ~= helper.tick then
        if helper.tick then helper.changed_at = now end
        helper.tick = tick
    end
    helper.ready = text:match("ready\t1") ~= nil
    helper.loading = text:match("loading\t0") == nil
    if helper.loading then helper.idle_since = nil else helper.idle_since = helper.idle_since or now end
end

-- Has the game finished loading? Searching the game's objects in the tail of a load crashed Junon Colosseum twice,
-- so nothing here looks for objects until this says so. With the helper: the package loader has been idle for
-- `idle_seconds`. Without it there is no way to ask, so a flat `blind_seconds` since `since` (Junon's old floor).
function M.settled(now, since, idle_seconds, blind_seconds)
    if M.can_stream(now) then
        return helper.idle_since ~= nil and now - helper.idle_since >= idle_seconds
    end
    return now - since >= blind_seconds
end

function M.can_stream(now)
    now = now or os.time()
    return helper.ready and helper.changed_at ~= nil and now - helper.changed_at <= 3
end

-- Appends one line to the request file (written whole, then renamed, so the helper never reads half a line).
local function request(line)
    local path = MOD_DIR .. "stages-request.txt"
    local existing = ""
    local file = io.open(path, "rb")
    if file then
        existing = file:read("a") or ""
        file:close()
    end
    local out = io.open(path .. ".tmp", "wb")
    if not out then return false end
    out:write(existing .. line .. "\n")
    out:close()
    os.remove(path)
    return os.rename(path .. ".tmp", path) == true
end

function M.stream_request(item)
    if not M.can_stream() then return false end
    return request(string.format("load\t%s\t%s\t%.3f\t%.3f\t%.3f\t%.3f", item.name, item.package,
        item.location.X, item.location.Y, item.location.Z, item.yaw or 0))
end

-- What the helper said about an instance: "loaded", "unloaded", "refused" or nil (nothing yet). The last word wins.
-- The file is read once and kept for a fifth of a second: a stage of 77 levels asks about each of them every tick,
-- and reading the whole file for every one of them ran on the game thread.
local acks, acks_read_at = {}, nil
function M.stream_state(name)
    local now = os.clock()
    if not acks_read_at or now - acks_read_at >= 0.2 then
        acks, acks_read_at = {}, now
        local file = io.open(MOD_DIR .. "stages-ack.txt", "rb")
        if file then
            for line in file:lines() do
                local who, what = line:match("^([%w_]+)\t(%a+)")
                if who then acks[who] = what end
            end
            file:close()
        end
    end
    return acks[name]
end

function M.stream_ready(name) return M.stream_state(name) == "loaded" end

-- The helper kept the stream it loaded, and unloads it.
function M.stream_release(name)
    return request("unload\t" .. name)
end

-- A streamed stage arrives with parts switched off. Its sky level's sun and fog are hidden until the game's own sky
-- system selects that sky, and some stages' meshes are hidden until their boss fight shows them (the rock in space:
-- all 41; seen in the game 2026-11-17). This shows them: the sun and fog always, and the classes the stage lists in
-- `show_classes`. Only actors in this stage's own instances ("SimStage_<id>_") are touched. Returns how many.
local shown_actors = {}
-- The stage's lights: what decides how the scene is lit. Switched on while the simulator's own lighting levels are
-- showing, they leave the scene dull once those are hidden (the Lifestream, 2026-11-17), so they wait (see below).
local LIGHT_CLASSES = { DirectionalLight = true, ExponentialHeightFog = true, PrecomputedLightEnvironmentActor = true,
    SphereReflectionCapture = true, VolumetricFogInjectionVolumeActor = true }
local waiting_lights = {}

-- Characters take their ambient light and exposure from the one light environment (PrecomputedLightEnvironment
-- component) that is switched on where they stand. A stage that names `light_environment` (a fragment of its actor's
-- name) gets only that one: its other light environments are switched off, and so is the simulator's own
-- (0000-COMON_VR_Light), which otherwise stays on under the stage and leaves characters near-black (the Temple of
-- the Ancients' second-phase hall, 2026-11-20). The simulator's is put back with the rest of its look
-- (`set_dressing_hidden(false)`). Run once the stage's lights are on. Returns how many components were switched.
function M.apply_light_environment(stage)
    local want = stage and stage.light_environment
    if not want then return 0 end
    local marker = "SimStage_" .. stage.id .. "_"
    local count = 0
    for _, component in ipairs(safe(FindAllOf, "PrecomputedLightEnvironmentComponent") or {}) do
        if valid(component) then
            local name = safe(function() return component:GetFullName() end) or ""
            if name:find(marker, 1, true) then
                local on = name:find(want, 1, true) ~= nil
                if pcall(function() component:SetVisibility(on, true) end) then count = count + 1 end
            elseif name:find("0000-COMON_VR", 1, true) then
                if pcall(function()
                    component:SetHiddenInGame(true, true)
                    component:SetVisibility(false, true)
                end) then
                    hidden_components[#hidden_components + 1] = ref(component)
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- A stage's own look, from its data (both optional), for the visit:
--   `lamp`: one of the stage's own spotlights (`actor`, by name) moved to `offset` from the arena's centre (`centre`), aimed by `pitch`
--     and `yaw`, at the given strength, cone, reach, colour and shadows. The Temple's upside-down hall lets the sun
--     reach only its upper walls, and a streamed copy has no baked lighting; one of its light level's unused lamps,
--     moved inside the colonnade, lights it warmly (owner's choice, 2026-11-20);
--   `render_settings`: console variables set for the visit and put back by `restore_render_settings`.
-- Run whenever the light environment is applied (after the lights are on): repeats are harmless. Returns how many
-- things it set.
local saved_render = nil
local function console(command)
    local system = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local controller = safe(FindFirstOf, "PlayerController")
    if not (valid(system) and valid(controller)) then return false end
    return pcall(function() system:ExecuteConsoleCommand(controller, command, controller) end)
end
function M.apply_stage_look(stage, centre)
    if not stage then return 0 end
    local marker = "SimStage_" .. stage.id .. "_"
    local count = 0
    local lamp = stage.lamp
    if lamp and centre then
        for _, actor in ipairs(safe(FindAllOf, "SpotLight") or {}) do
            if valid(actor) and (safe(function() return actor:GetFullName() end) or ""):find(marker, 1, true)
                and (not lamp.actor or safe(function() return actor:GetFName():ToString() end) == lamp.actor) then
                local light = safe(function() return actor.SpotLightComponent end)
                if valid(light) and pcall(function()
                    actor.RootComponent:SetMobility(2)
                    actor:K2_SetActorLocation({ X = centre.X + lamp.offset[1], Y = centre.Y + lamp.offset[2],
                        Z = centre.Z + lamp.offset[3] }, false, {}, true)
                    actor:K2_SetActorRotation({ Pitch = lamp.pitch, Yaw = lamp.yaw, Roll = 0 }, true)
                    light:SetAttenuationRadius(lamp.radius)
                    light.OuterConeAngle = lamp.outer_cone
                    light.InnerConeAngle = lamp.inner_cone
                    if lamp.color then
                        light:SetLightColor({ R = lamp.color[1], G = lamp.color[2], B = lamp.color[3], A = 1.0 }, true)
                    end
                    light:SetCastShadows(lamp.shadows == true)
                    light:SetIntensity(lamp.intensity)
                    light:SetVisibility(true, true)
                    actor:SetActorHiddenInGame(false)
                end) then count = count + 1 end
                break
            end
        end
    end
    if stage.render_settings then
        local system = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        if not saved_render then
            saved_render = {}
            for name in pairs(stage.render_settings) do
                saved_render[name] = valid(system) and safe(function() return system:GetConsoleVariableIntValue(name) end) or nil
            end
        end
        for name, value in pairs(stage.render_settings) do
            if console(name .. " " .. tostring(value)) then count = count + 1 end
        end
    end
    return count
end

-- Puts back the console variables a stage's `render_settings` changed. Returns how many.
function M.restore_render_settings()
    if not saved_render then return 0 end
    local count = 0
    for name, value in pairs(saved_render) do
        if type(value) == "number" and console(name .. " " .. tostring(math.floor(value))) then count = count + 1 end
    end
    saved_render = nil
    return count
end

-- Brightness environment components keep their probes' places (ExposureDataArray[i].Position) in the map's own
-- coordinates, which do not move with a level streamed elsewhere, so the game would set the exposure from probes
-- 170 km away. For a stage with `move_brightness_probes`, each probe in this visit's copies is moved by its level's
-- offset (the `plan` item's location). Once per visit: every visit streams fresh copies. Returns how many probes.
function M.move_brightness_probes(stage, plan)
    if not (stage and stage.move_brightness_probes and plan) then return 0 end
    local count = 0
    for _, component in ipairs(safe(FindAllOf, "PrecomputedBrightnessEnvironmentComponent") or {}) do
        local name = valid(component) and (safe(function() return component:GetFullName() end) or "") or ""
        for _, item in ipairs(plan) do
            if name ~= "" and name:find(item.name .. ".", 1, true) then
                pcall(function()
                    local probes = component.ExposureDataArray
                    for i = 1, #probes do
                        local p = probes[i].Position
                        p.X = p.X + item.location.X
                        p.Y = p.Y + item.location.Y
                        p.Z = p.Z + item.location.Z
                        count = count + 1
                    end
                end)
                break
            end
        end
    end
    return count
end

-- Is any of the simulator's own lighting, effect or sky levels visible right now? One search.
function M.simulator_lighting_visible(vr_stage)
    find_simulator_levels(vr_stage)
    for _, entry in ipairs(simulator_levels) do
        local stream = fresh(entry.stream)
        if stream and safe(function() return stream:IsLevelVisible() end) == true then return true end
    end
    return false
end

-- `lights_now` false: the stage's lights are found but left off, for `show_stage_lights` to switch on later.
function M.activate_stage(stage, lights_now)
    local marker = "SimStage_" .. stage.id .. "_"
    -- The sun and fog come from the sky level; the ambient light, reflection capture and fog volume from the stage's
    -- light level. Without the ambient light characters are black silhouettes (the Lifestream, 2026-11-17).
    local classes = { "DirectionalLight", "ExponentialHeightFog", "PrecomputedLightEnvironmentActor",
        "SphereReflectionCapture", "VolumetricFogInjectionVolumeActor" }
    for _, class in ipairs(stage.show_classes or {}) do classes[#classes + 1] = class end
    -- Never shown: collision-only meshes ("CL_...") and what the stage lists in `keep_hidden` (cutscene props).
    local keep = { "PersistentLevel.CL_" }
    for _, part in ipairs(stage.keep_hidden or {}) do keep[#keep + 1] = "PersistentLevel." .. part end
    local function kept(name)
        for _, part in ipairs(keep) do
            if name:find(part, 1, true) then return true end
        end
        return false
    end
    local shown = 0
    shown_actors, waiting_lights = {}, {}
    for _, class in ipairs(classes) do
        local later = lights_now == false and LIGHT_CLASSES[class] == true
        for _, actor in ipairs(safe(FindAllOf, class) or {}) do
            if valid(actor) and safe(function() return actor.bHidden end) == true then
                local name = safe(function() return actor:GetFullName() end) or ""
                if name:find(marker, 1, true) and not kept(name) then
                    if later then
                        waiting_lights[#waiting_lights + 1] = actor
                    elseif pcall(function() actor:SetActorHiddenInGame(false) end) then
                        shown_actors[#shown_actors + 1] = actor
                        shown = shown + 1
                    end
                end
            end
        end
    end
    return shown, #waiting_lights
end

-- Switches on the lights `activate_stage` left off. No search.
function M.show_stage_lights()
    local shown = 0
    for _, actor in ipairs(waiting_lights) do
        if valid(actor) and pcall(function() actor:SetActorHiddenInGame(false) end) then
            shown_actors[#shown_actors + 1] = actor
            shown = shown + 1
        end
    end
    waiting_lights = {}
    return shown
end

-- Drops every object this mod kept for a visit: the simulator's levels and look, the stage's shown actors and waiting
-- lights. Called when a course is confirmed and when the visit ends, so nothing kept from one visit is ever touched in
-- the next (where the game has destroyed it): see `fresh`.
function M.forget_visit()
    simulator_levels, simulator_searched_at = {}, nil
    dressing_ready = nil
    shown_actors, waiting_lights = {}, {}
    hidden_actors, hidden_streams, hidden_components, collision_off, hidden_seen = {}, {}, {}, {}, {}
end

-- Shows again whatever `activate_stage` showed and the stage's own set-up has hidden since. No search: this runs a
-- few seconds into the fight, where eight searches would freeze the screen for a second and a half.
function M.reactivate_stage()
    local shown = 0
    for _, actor in ipairs(shown_actors) do
        if valid(actor) and safe(function() return actor.bHidden end) == true
            and pcall(function() actor:SetActorHiddenInGame(false) end) then
            shown = shown + 1
        end
    end
    return shown
end

-- A stage smaller than the simulator's arena (a circle of 24.4 m radius, measured 2026-11-17) leaves invisible floor
-- round it, and one much larger puts the wall in the middle of it. `stage.fit.scale` ({ x, y }, or one number for
-- both) stretches it sideways about the arena's centre: each actor of `scale_classes` moves to centre + scale * (its
-- offset from the centre) and is scaled to match (along its own axes, so a turned actor gets the right mix of the
-- two); `move_classes` only move. Heights are left alone, so bumps do not grow. An actor whose name holds one of
-- `fit.keep`'s names is not stretched: it keeps its true size and place, lowered by that entry's `lower_cm` if set
-- (the Edge of Creation's far-land mesh carries a low-detail copy of the platform that would poke through the real one). Static actors are made movable first (USceneComponent.SetMobility),
-- or the engine will not move them. Only this visit's copies (`plan` names) are touched. Returns how many.
local MOVABLE = 2
function M.fit_stage(stage, plan)
    local fit, centre = stage.fit, plan and plan.centre
    if not (fit and centre and fit.scale) then return 0 end
    local sx, sy
    if type(fit.scale) == "table" then sx, sy = fit.scale[1], fit.scale[2] else sx, sy = fit.scale, fit.scale end
    if type(sx) ~= "number" or type(sy) ~= "number" or (sx == 1 and sy == 1) then return 0 end
    local function ours(name)
        for _, item in ipairs(plan) do
            if name:find(item.name .. ".", 1, true) then return true end
        end
        return false
    end
    local function kept(name)
        for _, entry in ipairs(fit.keep or {}) do
            if name:find(entry.name, 1, true) then return entry end
        end
        return nil
    end
    local count = 0
    local function each(classes, scale_too)
        for _, class in ipairs(classes or {}) do
            for _, actor in ipairs(safe(FindAllOf, class) or {}) do
                local name = valid(actor) and (safe(function() return actor:GetFullName() end) or "") or ""
                local keep = kept(name)
                if name ~= "" and ours(name) and pcall(function()
                    local component = actor.RootComponent
                    if component and component:IsValid() then component:SetMobility(MOVABLE) end
                    local p = actor:K2_GetActorLocation()
                    if keep then
                        if (keep.lower_cm or 0) ~= 0 then
                            actor:K2_SetActorLocation({ X = p.X, Y = p.Y, Z = p.Z - keep.lower_cm }, false, {}, true)
                        end
                        return
                    end
                    actor:K2_SetActorLocation({
                        X = centre.X + sx * (p.X - centre.X),
                        Y = centre.Y + sy * (p.Y - centre.Y),
                        Z = p.Z,
                    }, false, {}, true)
                    if scale_too then
                        local k = actor:GetActorScale3D()
                        local yaw = math.rad(actor:K2_GetActorRotation().Yaw)
                        local c, s = math.cos(yaw), math.sin(yaw)
                        actor:SetActorScale3D({
                            X = k.X * math.sqrt((sx * c) ^ 2 + (sy * s) ^ 2),
                            Y = k.Y * math.sqrt((sx * s) ^ 2 + (sy * c) ^ 2),
                            Z = k.Z,
                        })
                    end
                end) then
                    count = count + 1
                end
            end
        end
    end
    each(fit.scale_classes, true)
    each(fit.move_classes, false)
    return count
end

-- A text by its id in the player's language: UEndMenuAPI.GetString(TextId), as Junon Colosseum's text dump calls it.
function M.text(id)
    local api = cdo(MENU_API)
    if not api then return nil end
    local value = safe(function() return api:GetString(id) end)
    if value ~= nil and type(value) ~= "string" then value = safe(function() return value:ToString() end) end
    return type(value) == "string" and value or nil
end

-- The selected course's title: UEndColosseumMenu.InfoWindow.Txt_CourseTitle, falling back to Txt_TitleCourse, as
-- Training Dummy reads it. `context` is the hook's first argument.
function M.course_title(context)
    local menu = safe(function() return context:get() end)
    if not valid(menu) then return nil end
    local title = safe(function() return menu.InfoWindow.Txt_CourseTitle:GetText():ToString() end)
    if type(title) ~= "string" or title == "" then
        title = safe(function() return menu.Txt_TitleCourse:GetText():ToString() end)
    end
    return type(title) == "string" and title or nil
end

-- The game's own choice window: UEndMenuAPI.ShowMessageWindow(context, text, options, flags). Junon Colosseum uses
-- it in the field and in battle. On top of the simulator's menu it is untested.
function M.open_picker(prompt, labels)
    local menu, battle = cdo(MENU_API), cdo(BATTLE_API)
    if not menu or not battle then return nil end
    local leader = safe(function() return battle:GetPartyLeader() end)
    if not valid(leader) then return nil end
    local window = safe(function() return menu:ShowMessageWindow(leader, prompt, labels, MESSAGE_PAUSE_MENU) end)
    return valid(window) and window or nil
end

-- "open" while the window is up; otherwise "closed" and the zero-based index picked (nil when unreadable).
function M.read_picker(window)
    local menu = cdo(MENU_API)
    if not menu or not valid(window) then return "closed", nil end
    local closed = safe(function() return menu:IsMessageWindowClosed(window) end)
    if closed == false then return "open", nil end
    local index = safe(function() return menu:GetMessageWindowSelectedIndex(window) end)
    return "closed", type(index) == "number" and index or nil
end

return M
