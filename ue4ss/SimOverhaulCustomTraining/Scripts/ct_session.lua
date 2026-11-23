-- One visit to the Custom Training course: notices the course's enemies, puts the player's choices in place,
-- keeps the enemies held or fighting, runs the settings menu, and puts the difficulty back afterwards.
-- main.lua calls tick() on the game thread.
local panel_model = require("ct_panel_model")
local input_module = require("ct_input")
local party_module = require("ct_party")
local plan = require("ct_plan")

local M = {}

local REFILL_BELOW = 90     -- % HP: an enemy below it is refilled in Passive and Healing
-- Waves (owner 2026-11-21; in Aggressive, where enemies can die): the player can kill enemies outright and the dead stay
-- dead; when the last of the chosen enemies falls, the whole set comes back as a new wave at full HP (a round once
-- everything in it is dead, its own reinforcements and adds included). The hidden anchor keeps the round alive in
-- between. Players can see whether they beat a round, which a refilling enemy never let them.
local SPAWN_PATIENCE = 8    -- seconds a requested spawn may take before it is asked for again
local SUMMON_PATIENCE = 20  -- a summon's entrance takes longer (Titan came after 8 s, 2026-11-21)
local SPREAD_BELOW = 150    -- cm: copies nearer than this to another of ours are moved apart
local SPREAD_RADIUS = 450   -- cm from the one they stand on
local GONE_SECONDS = 3
local MAX_EXTRA = 3
local MAX_MISSES = 2        -- spawn requests that came to nothing before an opponent is given up         -- enemies of ours allowed beyond the count while a change is under way      -- no enemy of ours this long, out of battle: the visit is over
local SLOTS = 16            -- a round can start its territory's waves 0-15 only
local GROUP_MAX = 3         -- opponents at once in a group (owner 2026-11-21: up to three different ones)
local OTHERS_MAX = 12       -- enemies of ours that are no member of the setup (adds, or spawns not recognised): no more
                            -- spawns past this
local DIFFICULTY_VALUE = { easy = 0, normal = 1, hard = 2, dynamic = 3 }
local DIFFICULTY_NAME = { [0] = "easy", [1] = "normal", [2] = "hard", [3] = "dynamic" }

-- deps: game (ct_game), catalogue (ct_catalogue), settings (table, changed in place), save_settings(), log(),
-- clock() -> seconds; optional: meters ({ state(), act(name) }: the meters part, or its file bridge),
-- panel_blocked() -> true while the panel must not open (ct_panel = off, or the ui part's own menu is there)
function M.new(deps)
    local self = {
        game = deps.game, catalogue = deps.catalogue, settings = deps.settings, log = deps.log,
        save_settings = deps.save_settings, clock = deps.clock or os.clock, party = party_module.new(),
        emit = deps.emit or function() end, -- ct_api.emit: tells meters and ui about starts, ends and changes
        meters = deps.meters, panel_blocked = deps.panel_blocked or function() return false end,
        mp_refilled = {}, mp_version = 0, -- MP given back per party member since the start or the last change
        active = false, pending = {}, stale = {}, names = {}, by_id = {}, by_spec = {}, unspawnable = {},
        menu_requested = false, gone_since = nil,
        difficulty_saved = nil, status = {}, input = input_module.new(), all_keys = input_module.all_keys(),
    }
    for _, o in ipairs(self.catalogue.opponents) do self.by_id[o.id] = o; self.by_spec[o.spec] = o end
    self.rounds_by_id, self.misses, self.air = {}, {}, {}
    -- Flyers keep their height: the opponents the tables mark aerial in a vanilla round (catalogue air).
    for _, o in ipairs(self.catalogue.opponents) do if o.air then self.air[o.chara or o.spec] = true end end
    for _, c in ipairs(self.catalogue.courses or {}) do
        for _, r in ipairs(c.rounds) do self.rounds_by_id[r.id] = { course = c, round = r } end
    end
    return setmetatable(self, { __index = M })
end

-- The name the player sees: the game's own text for its name key (in the game's language), else the game's English
-- name the catalogue carries, plus the catalogue's plain tag for the few the game names alike ("Bandit (Axe)").
-- Only a looked-up name is kept: a lookup that failed once (2026-11-21, "Black Bat Standard") is tried again.
function M:name(o)
    if not o then return "?" end
    local cached = self.names[o.id]
    if cached then return cached, true end
    local looked = self.game.lookup(o.label)
    local name = looked or o.name
    if not name or name == "" then
        local words = o.spec:match("^%u%u%d+_%d+_(.+)$") or o.spec
        name = words:gsub("End2", ""):gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
    end
    if o.tag then name = name .. " (" .. o.tag .. ")" end
    if looked then self.names[o.id] = name end
    return name, looked ~= nil
end

function M.family(spec)
    return spec and (spec:match("^(%u%u%d+_%d+)") or spec) or nil
end

-- How many: as set, 1 to 3, for every opponent (owner 2026-11-21: story bosses aren't coming, so no "boss" cap).
-- Only an opponent shown in the game to break with more (catalogue cap, with the evidence in make_spec.py) is held to
-- its cap.
function M.max_count(o) return (o and o.cap) or 3 end

-- How many enemies the setup brings: a group's members, or a round's opening enemies.
function M:count()
    local n = 0
    for _, m in ipairs(self:setup().members) do n = n + m.count end
    return n
end

-- The setup's first opponent (the catalogue entry): what the panel and the old single-opponent fields show.
function M:opponent()
    local first = self:setup().members[1]
    return (first and self.by_id[first.as]) or self.by_id[self.settings.opponent] or self.catalogue.opponents[1]
end

function M.split_ids(text)
    local ids = {}
    for id in tostring(text or ""):gmatch("[%w_]+") do ids[#ids + 1] = id end
    return ids
end

-- The group: one id per enemy, 1 to 3 (owner 2026-11-21: "a Bomb and two Wererats"). Empty ct_group: the opponent
-- and count, as before groups (one entry repeated).
function M:group()
    local ids = {}
    for _, id in ipairs(M.split_ids(self.settings.group)) do
        if self.by_id[id] and not self.unspawnable[id] and #ids < GROUP_MAX then ids[#ids + 1] = id end
    end
    if #ids == 0 then
        local o = self.by_id[self.settings.opponent] or self.catalogue.opponents[1]
        if self.unspawnable[o.id] then o = self.by_id[self.last_good or ""] or self.catalogue.opponents[1] end
        for _ = 1, math.min(self.settings.count, M.max_count(o)) do ids[#ids + 1] = o.id end
    end
    return ids
end

-- Members with their wave slots. fixed: wave -> { template, level, who } that must be in place (a round's own waves,
-- the adds a member's scripts start by wave number); each member is spawned from a free wave of its own, so two
-- members never share one. Fails when two need the same wave for different enemies, or the 16 run out.
function M.assign(members, waves)
    local fixed = {}
    local function claim(slot, template, level, who)
        local f = fixed[slot]
        if f and f.template ~= template then return false, who .. " and " .. f.who .. " both need wave " .. slot end
        if slot >= SLOTS then return false, who .. " needs wave " .. slot end
        fixed[slot] = f or { template = template, level = level, who = who }
        return true
    end
    for _, w in ipairs(waves or {}) do
        local ok, why = claim(w[1], w[2], w[3], "the round")
        if not ok then return nil, why end
    end
    for _, m in ipairs(members) do
        for _, h in ipairs(m.home or {}) do
            local ok, why = claim(h[1], h[2], h[3], m.name or m.as)
            if not ok then return nil, why end
        end
    end
    local used = {}
    for slot in pairs(fixed) do used[slot] = true end
    for _, m in ipairs(members) do
        m.slot = nil
        for slot = 0, SLOTS - 1 do
            if not used[slot] then m.slot = slot; used[slot] = true; break end
        end
        if not m.slot then return nil, "more enemies than the territory's " .. SLOTS .. " waves" end
    end
    return { members = members, fixed = fixed }
end

local function group_members(self, ids, named)
    local members, by = {}, {}
    for _, id in ipairs(ids) do
        local o = self.by_id[id]
        local m = by[id]
        if not m then
            m = { key = id, template = id, as = id, count = 0, level = o.level, chara = o.chara or o.spec, home = o.home or {},
                  name = named and self:name(o) or nil }
            by[id] = m
            members[#members + 1] = m
        end
        m.count = m.count + 1
    end
    return members, by
end

-- Whether ids can be a group: 1 to 3 known opponents, a capped one at most cap times, adds that fit together.
function M:check_group(ids)
    if #ids < 1 or #ids > GROUP_MAX then return false, "a group is 1 to " .. GROUP_MAX .. " opponents" end
    for _, id in ipairs(ids) do
        if not self.by_id[id] then return false, "unknown opponent " .. tostring(id) end
    end
    local members = group_members(self, ids, true)
    for _, m in ipairs(members) do
        local o = self.by_id[m.as]
        if m.count > M.max_count(o) then
            return false, m.name .. " comes at most " .. M.max_count(o) .. " at a time"
        end
    end
    local ok, why = M.assign(members)
    if not ok then return false, why end
    return true
end

-- Pairs of opponents that can't be in one group (their adds need the same wave for different enemies), for the
-- menu to refuse before Apply. Only opponents with adds can clash.
function M:conflicts()
    if self.conflict_list then return self.conflict_list end
    local with = {}
    for _, o in ipairs(self.catalogue.opponents) do if o.home and #o.home > 0 then with[#with + 1] = o end end
    local list = {}
    for i = 1, #with do
        for j = i + 1, #with do
            local a, b = with[i], with[j]
            local ok = M.assign({ { key = a.id, as = a.id, count = 1, home = a.home }, { key = b.id, as = b.id, count = 1, home = b.home } })
            if not ok then list[#list + 1] = { a.id, b.id } end
        end
    end
    self.conflict_list = list
    return list
end

-- What should be on the field now: { members = { { key, template, as, count, level, chara, home, slot } }, fixed,
-- whole, round }. A round's set comes back whole (owner 2026-11-21); a group's members come back one by one.
function M:setup()
    if self.settings.mode == "round" then
        local entry = self.rounds_by_id[self.settings.round]
        if entry and not self.unspawnable["round:" .. entry.round.id] then
            local members, by = {}, {}
            for _, mob in ipairs(entry.round.mobs) do
                local m = by[mob[1]]
                if m then
                    m.count = m.count + mob[2]
                else
                    m = { key = mob[1], template = mob[1], count = mob[2], level = mob[3], chara = mob[4], as = mob[5], home = {} }
                    by[mob[1]] = m
                    members[#members + 1] = m
                end
            end
            local setup = M.assign(members, entry.round.waves)
            if setup then
                setup.whole, setup.round = true, entry
                return setup
            end
        end
    end
    local members = group_members(self, self:group())
    for _, m in ipairs(members) do m.count = math.min(m.count, M.max_count(self.by_id[m.as])) end
    local setup = M.assign(members) or M.assign({ members[1] })
    -- (A group whose adds clash, only from a hand-edited settings.txt since apply refuses one, fights its first alone.)
    setup.whole = true
    return setup
end

-- Room (owner 2026-11-21: filter opponents by stage, don't limit stages). The stage the course is on, from the Stages
-- part (nil on the plain arena: no limit), and what a setup needs: an opponent its catalogue needs (Stages' rule:
-- 12 m, more for enemies whose scripts reach far), a group the most any member needs plus 2 m for each enemy beyond
-- the first (the spacing between them), a round its course's needs.
local SPACING_M = 2

function M:stage()
    if self.stage_override ~= nil then return self.stage_override or nil end
    local ok, stages_api = pcall(require, "stages_api")
    if not ok or type(stages_api) ~= "table" or not stages_api.current then return nil end
    local ok2, stage = pcall(stages_api.current)
    return ok2 and stage or nil
end

function M:room_m()
    local stage = self:stage()
    return stage and stage.radius_m or nil
end

function M.needs_of_group(by_id, ids)
    local need, n = 0, 0
    for _, id in ipairs(ids) do
        local o = by_id[id]
        n = n + 1
        if o and (o.needs or 0) > need then need = o.needs or 0 end
    end
    return need + SPACING_M * math.max(0, n - 1)
end

function M:needs_of_round(id)
    local entry = self.rounds_by_id[id]
    return entry and entry.course.needs or nil
end

-- true, or false and the reason ui shows.
function M:fits(need)
    local room = self:room_m()
    if not room or not need or need <= room then return true end
    local stage = self:stage()
    return false, string.format("needs a larger stage than %s (%g m, has %g m)", stage and stage.name or "this one", need, room)
end

-- At the start of a course on a small stage: a stored setup that doesn't fit falls back to one that does, and says
-- so (log "room", status fallback): the last opponent that appeared if it fits, else the first in the catalogue that
-- does.
function M:fit_to_stage()
    local need
    if self.settings.mode == "round" and self.rounds_by_id[self.settings.round] then
        need = self:needs_of_round(self.settings.round)
    else
        need = M.needs_of_group(self.by_id, self:group())
    end
    local ok, why = self:fits(need)
    if ok then self.fallback = nil; return end
    local was = self:setup_name()
    local pick = self.by_id[self.last_good or ""]
    if not (pick and self:fits(pick.needs)) then
        pick = nil
        for _, o in ipairs(self.catalogue.opponents) do
            if self:fits(o.needs) and not self.unspawnable[o.id] then pick = o; break end
        end
    end
    if not pick then return end
    self.settings.mode, self.settings.group, self.settings.opponent, self.settings.count = "opponents", "", pick.id, 1
    self.save_settings()
    self.fallback = was .. " " .. why .. "; " .. self:name(pick) .. " instead"
    self.log("room\t" .. self.fallback)
end

-- The player's words for the setup: "Bomb, Wererat ×2", or the round: "Grasslands 1 · Round 2".
function M:course_name(c)
    return (self.game.lookup and self.game.lookup(c.label)) or c.name or c.id
end

function M:round_name(entry)
    return self:course_name(entry.course) .. " · Round " .. entry.round.number
end

function M:enemies_text(members)
    local parts = {}
    for _, m in ipairs(members) do
        local o = self.by_id[m.as]
        parts[#parts + 1] = self:name(o) .. (m.count > 1 and (" ×" .. m.count) or "")
    end
    return table.concat(parts, ", ")
end

function M:setup_name()
    local setup = self:setup()
    if setup.round then return self:round_name(setup.round) end
    return self:enemies_text(setup.members)
end

-- The game's own difficulty functions, from the native helper (CustomTrainingNative); nil without it.
local function native(name)
    local f = rawget(_G, name)
    return type(f) == "function" and f or nil
end

function M:difficulties()
    if not native("CustomTrainingSetDifficulty") then return {} end
    return nil -- all
end

function M:apply_difficulty()
    local set = native("CustomTrainingSetDifficulty")
    if not set then return false end
    local ok, done = pcall(set, DIFFICULTY_VALUE[self.settings.difficulty] or 1, 1)
    self.log("difficulty\t" .. self.settings.difficulty .. "\t" .. tostring(ok and done))
    return ok and done == true
end

function M:read_difficulty()
    local get = native("CustomTrainingGetDifficulty")
    if not get then return nil end
    local ok, current, value, set, system = pcall(get)
    if not ok or current == nil then return nil end
    return { current = current, value = value, set = set, system = system }
end

-- Our territory's enemies, as plan entries, without the anchor; and the anchor, if it is still there.
function M:ours()
    local list, anchor = {}, nil
    for _, actor in ipairs(self.game.enemies()) do
        if self.game.territory_of(actor) == self.catalogue.territory then
            local spec = self.game.spec(actor)
            -- Compared by family (EN2225_00, SU2030_01): a summon reports another spec once it is out
            -- (SU2030_01_Alexander_GilQuest came back as SU2030_01_Alexander_Boss, 2026-11-20).
            local e = { key = self.game.name_of(actor), spec = M.family(spec), full_spec = spec, actor = actor }
            if e.key == self.anchor_key then anchor = e else list[#list + 1] = e end
        end
    end
    return list, anchor
end

function M:begin(now)
    self.active, self.gone_since = true, nil
    self.stale, self.pending, self.misses = {}, {}, {}
    self.wave, self.wave_started, self.wave_replaced, self.last_clear = 0, nil, true, nil
    self.difficulty_saved = self:read_difficulty()
    self:apply_difficulty()
    self:fit_to_stage()
    self.slots, self.slot_retries, self.slots_retry_at, self.noslot_said = nil, 0, nil, {} -- looked for (again) on the first ticks
    -- The course's opening enemy becomes the anchor that keeps the round going (ct_game.stash).
    local first = self:ours()[1]
    self.anchor_key = first and first.key
    -- Where the course opened (the opening enemy's spot, before it is stashed): a party member who falls through the
    -- floor is put back here.
    self.arena = first and self.game.location and self.game.location(first.actor) or nil
    self.arena_floor = nil
    self.anchor_at, self.anchor_tries = now, 0
    self:reset_mp()
    self:want_clean(now)
    self.emit("start")
    self.log("begin\t" .. self:setup_name() .. "\tx" .. self:count() .. "\t" .. self.settings.behaviour
        .. "\t" .. self.settings.difficulty .. "\tsaved difficulty " .. tostring(self.difficulty_saved and self.difficulty_saved.value))
end

function M:finish()
    if self:panel_open() then self:close_panel("course over") end
    local saved = self.difficulty_saved
    local set = native("CustomTrainingSetDifficulty")
    if saved and set then pcall(set, saved.value, saved.set) end
    self:restore_slots()
    local members = self.game.party()
    for _, a in ipairs(self.party:restore(members)) do
        for _, m in ipairs(members) do if m.id == a.id then self.game.set_hp_percent(m.actor, 100) end end
    end
    self.party:reset()
    self.active = false
    self.emit("end")
    self.log("end\tdifficulty put back to " .. tostring(saved and saved.value) .. "/" .. tostring(saved and saved.set))
    self.active, self.difficulty_saved, self.pending, self.stale, self.anchor_key, self.anchor_spot = false, nil, {}, {}, nil, nil
end

-- How long a requested spawn may take before it is asked for again.
function M.patience(o)
    if o and (o.category == 5 or (o.spec or ""):match("^SU")) then return SUMMON_PATIENCE end
    return SPAWN_PATIENCE
end

-- Enemies are recognised by their model's spec (GetCharaSpecName answers the CharaSpec; equal to the catalogue's in
-- all 181 opponents the probe sweep saw): eleven templates use another enemy's model, the Cactuars the summon Cactuar's
-- (SU0008_*), the Griffins the Quetzalcoatl's (2026-11-21). A summon reports another spec once it is out
-- (SU2030_01_Alexander_GilQuest came back as SU2030_01_Alexander_Boss, 2026-11-20), so summons also match by family.
-- Exact first, so two members of one family (Bandit Scimitar and Bandit Iron Pipe) are told apart.
-- Returns member key -> its enemies, and the set of keys taken.
function M.match(enemies, members, stale)
    local of, taken = {}, {}
    for _, m in ipairs(members) do of[m.key] = {} end
    for pass = 1, 2 do
        for _, e in ipairs(enemies) do
            if not (stale and stale[e.key]) and not taken[e.key] then
                for _, m in ipairs(members) do
                    local fits
                    if pass == 1 then fits = e.full_spec == m.chara
                    else fits = (m.chara or ""):match("^SU") ~= nil and e.spec == M.family(m.chara) and #of[m.key] < m.count end
                    if fits then
                        of[m.key][#of[m.key] + 1] = e
                        taken[e.key] = true
                        break
                    end
                end
            end
        end
    end
    return of, taken
end

-- A member that never appeared, twice: some templates come out as props, not enemies (Gilgamesh's shields). It is
-- given up for this visit: a group goes on without it (or, alone, the last one that appeared comes back); a round
-- whose set never appeared goes back to the group.
function M:give_up(setup, m)
    if setup.round then
        self.unspawnable["round:" .. setup.round.round.id] = true
        self.settings.mode = "opponents"
        self.log("spawn\tgave up on round " .. setup.round.round.id .. ": none of it appeared as an enemy")
    else
        self.unspawnable[m.as] = true
        self.log("spawn\tgave up on " .. m.as .. ": it never appeared as an enemy")
        local kept = {}
        for _, id in ipairs(M.split_ids(self.settings.group)) do if id ~= m.as then kept[#kept + 1] = id end end
        self.settings.group = table.concat(kept, ",")
        if #kept == 0 and (self.settings.opponent == m.as or self.unspawnable[self.settings.opponent]) then
            self.settings.opponent = self.last_good or self.catalogue.opponents[1].id
        end
    end
    self.misses, self.pending, self.stale, self.menu_list, self.panel_model = {}, {}, {}, nil, nil
    self.save_settings()
end

-- The damage sources shown at a change (the old fight's), by name: what is left of them afterwards is counted.
function M:shown_now()
    local set = {}
    if self.game.shown_damage_sources then
        for _, name in ipairs(self.game.shown_damage_sources()) do set[name] = true end
    end
    return set
end

-- Replaced (owner 2026-11-21: an old opponent got attacks in after it was replaced, Phoenix's and a Flan's moves in
-- Titan's fight): marked at once, held, out of targeting, its damage sources cleared and their names kept so what is
-- left of them can be counted; removed when the new set is in.
function M:retire(e, now)
    if self.stale[e.key] then return end
    self.stale[e.key] = true
    self.retired_at = self.retired_at or {}
    self.retired_at[e.key] = now or self.clock()
    self.game.hold(e.actor, true)
    if self.game.untarget then self.game.untarget(e.actor) end
    if self.game.owned_damage_sources then
        self.watch_ds = self.watch_ds or {}
        local owned = self.game.owned_damage_sources(e.actor)
        for _, name in ipairs(owned) do self.watch_ds[name] = true end
        if #owned > 0 then
            self.log("retire	" .. e.key .. "	" .. #owned .. " damage sources of its own")
        elseif self.game.damage_source_owners and not self.owners_logged then
            -- None matched: say once per visit whose the shown ones are, to see what owns them.
            self.owners_logged = true
            for _, line in ipairs(self.game.damage_source_owners(6)) do self.log("damage source	" .. line .. "	(for " .. e.key .. ")") end
        end
    end
    if self.game.clear_damage_sources then self.game.clear_damage_sources(e.actor) end
    -- Out of the fight at once, as the anchor is: moved away, hidden, solid to nothing. The game took 9 s to remove
    -- Phoenix's set after the request (2026-11-22); until then nothing of it can be seen, hit or hit back.
    if self.game.stash then self.game.stash(e.actor) end
end

local REMOVE_AGAIN_SECONDS = 10 -- a removal asked for and not done by then is asked again

-- The families of what the setup brings: its members' and the adds and waves its scripts start.
local function setup_families(setup)
    local fam = {}
    for _, m in ipairs(setup.members) do fam[M.family(m.chara)] = true end
    for _, f in pairs(setup.fixed or {}) do
        local id = tostring(f.template):gsub("^mobcolvr_", "")
        fam[id:match("^(%u%u%d+_%d+)") or id] = true
    end
    return fam
end

local LATE_ADDS_SECONDS = 8 -- after a change, an enemy that is no member and no add of the new set is the old one's

function M:keep_up(enemies, now, depth)
    -- The dead (HP 0, still there for their death motion) count for nothing: they are not members, adds or stale.
    local alive = {}
    for _, e in ipairs(enemies) do
        local hp = self.game.hp(e.actor)
        if hp == nil or hp > 0 then alive[#alive + 1] = e end
    end
    enemies = alive
    local setup = self:setup()
    -- How long removal takes: an enemy asked to go, until it is gone from the battle.
    if self.removed_at then
        local here = {}
        for _, e in ipairs(enemies) do here[e.key] = true end
        for key, at in pairs(self.removed_at) do
            if not here[key] then
                local since = self.retired_at and self.retired_at[key]
                self.log("gone\t" .. key .. "\t" .. string.format("%.1f", now - at) .. " s after its removal"
                    .. (since and string.format(", %.1f s after it was replaced", now - since) or ""))
                self.removed_at[key], self.stale[key] = nil, nil
                if self.retired_at then self.retired_at[key] = nil end
            end
        end
    end
    -- Adds an old opponent's scripts start while it is being replaced: retired too (a Flan of Phoenix's after a change
    -- to Titan, 2026-11-21).
    if self.change_at and now - self.change_at < LATE_ADDS_SECONDS then
        local fam = setup_families(setup)
        for _, e in ipairs(enemies) do
            if not self.stale[e.key] and not fam[e.spec] and not (self.kept_at_change or {})[e.key] then
                self:retire(e, now)
                self.log("retire\t" .. e.key .. "\tan add of the opponent replaced")
            end
        end
    end
    local members = setup.members
    local of, taken = M.match(enemies, members, self.stale)
    self.member_keys = taken
    self.pending = self.pending or {}
    self.seen = self.seen or {}
    local any_present = false
    for _, m in ipairs(members) do if #of[m.key] > 0 then any_present = true end end
    for _, m in ipairs(members) do
        local list = self.pending[m.key] or {}
        -- A spawn that has appeared settles one request.
        local fresh = 0
        for _, e in ipairs(of[m.key]) do if not self.seen[e.key] then fresh = fresh + 1 end end
        for _ = 1, math.min(fresh, #list) do table.remove(list, 1) end
        -- Requests that expired with nothing to show. Counted once per expiry, not per request: three copies asked
        -- for together once expired together as three misses, and Titan, which simply took longer than the wait, was
        -- given up at once (2026-11-21). A round's member is not counted while the rest of its set is there.
        local kept, patience = {}, M.patience(self.by_id[m.as])
        for _, at in ipairs(list) do if now - at < patience then kept[#kept + 1] = at end end
        local expired = #kept < #list
        self.pending[m.key] = kept
        if #of[m.key] > 0 then
            self.misses[m.key] = 0
            if not setup.round then self.last_good = m.as end
        elseif expired and not (setup.whole and any_present) then
            self.misses[m.key] = (self.misses[m.key] or 0) + 1
            if self.misses[m.key] >= MAX_MISSES and (depth or 0) < 3 then
                self:give_up(setup, m)
                return self:keep_up(enemies, now, (depth or 0) + 1)
            end
        end
    end
    self.seen = {}
    for _, e in ipairs(enemies) do self.seen[e.key] = true end
    self:place(enemies, now, taken)

    local pending_n = {}
    for _, m in ipairs(members) do pending_n[m.key] = #self.pending[m.key] end
    local todo = plan.group(enemies, members, of, pending_n, self.stale, self.anchor_present, setup.whole)
    -- A round comes back only once everything in it is dead, its reinforcements and adds too.
    local others_alive = 0
    for _, e in ipairs(enemies) do if not self.stale[e.key] and not taken[e.key] then others_alive = others_alive + 1 end end
    if setup.round and others_alive > 0 then todo.spawn = {} end
    -- Manual mode (ct_auto = off, for testing): enemies are held, nothing is spawned or removed.
    if self.settings.auto == "off" then todo = { spawn = {}, remove = {} } end
    -- A new wave: the whole set asked for, none of it there. If the last one was cleared (not replaced by a change),
    -- that is a clear: its time goes out as a "wave" event (meters show the wave number and the last clear time).
    local spawning = 0
    for _, m in ipairs(members) do spawning = spawning + (todo.spawn[m.key] or 0) end
    -- After a clear the round waits (owner 2026-11-21: no automatic respawn): the anchor keeps it alive until the
    -- player asks for the same fight again (respawn key, or Respawn in ui's menu) or picks another. ct_auto_respawn = on
    -- brings it back by itself. The first wave of a course or a change always comes.
    -- (A wave none of which ever appeared is no clear: it is asked for again, and given up after two misses.)
    -- Passive and Healing hold and refill their enemies, so none should die there; but one blow from a strong party can
    -- kill an opponent before any refill (2026-11-22: a 5,740 hit took a Passive Zu at Gilgamesh's Garden, and the round
    -- then stood empty, waiting for Respawn). There the set comes back by itself, as a refill would have kept it.
    if any_present then self.wave_seen = true end
    local may = self.settings.auto_respawn == "on" or self.settings.behaviour ~= "aggressive" or self.wave_replaced or self.respawn_requested or (self.wave or 0) == 0
        or not self.wave_seen
    if spawning > 0 and not any_present and not may then
        if not self.clear_noted and self.wave_started then
            self.clear_noted = true
            self.last_clear = now - self.wave_started
            self.log("wave\t" .. self.wave .. " cleared in " .. string.format("%.1f", self.last_clear) .. " s; waiting for Respawn")
            self.emit("clear", { clear_time = self.last_clear, cleared_wave = self.wave })
            if self.game.notice then
                local t = math.floor(self.last_clear + 0.5)
                local shown = self.game.notice(string.format("Wave cleared in %d:%02d. %s or Respawn in the menu (LB+RB) for the same fight.",
                    t // 60, t % 60, self.settings.respawn_key or "F4"))
                self.log("notice	" .. tostring(shown))
            end
        end
        todo.spawn = {}
        spawning = 0
    end
    if spawning > 0 and not any_present and self:slots_ready() then
        -- A clear that respawns by itself (ct_auto_respawn on) is timed here; one that waited was timed at the clear.
        local extra = nil
        if (self.wave or 0) > 0 and self.wave_seen and not self.clear_noted and not self.wave_replaced
            and not self.respawn_requested and self.wave_started then
            self.last_clear = now - self.wave_started
            self.log("wave\t" .. self.wave .. " cleared in " .. string.format("%.1f", self.last_clear) .. " s")
            extra = { clear_time = self.last_clear, cleared_wave = self.wave }
        end
        local first = self.wave_replaced or (self.wave or 0) == 0
        self.wave, self.wave_started, self.wave_replaced = (self.wave or 0) + 1, now, nil
        self.respawn_requested, self.clear_noted, self.wave_seen = nil, nil, nil
        -- Every new set after a setup's first is a "wave" event (meters show the number); the first comes with "start"
        -- or "change".
        if not first then self.emit("wave", extra) end
        -- A group's adds left from the cleared wave go: they come back with the new one.
        if not setup.round then
            for _, e in ipairs(enemies) do if not taken[e.key] then self:retire(e, now) end end
        end
    end
    -- A Respawn's old set goes only once the new wave has started: the "wave" event comes first, so the meters can
    -- mark the old set as outgoing before any of it disappears (meters, 2026-11-21).
    if self.respawn_requested then todo.remove = {} end
    -- Never more than a few extra: a spawn that is not recognised must not repeat without end (2026-11-20: a
    -- mismatched spec name made the first build spawn 76 copies). Counted on the setup's own (present or asked for)
    -- and on enemies of ours that are no member, adds included.
    local want, asked, others = 0, 0, 0
    for _, m in ipairs(members) do want = want + m.count; asked = asked + #of[m.key] + pending_n[m.key] end
    for _, e in ipairs(enemies) do if not self.stale[e.key] and not taken[e.key] then others = others + 1 end end
    for _, m in ipairs(members) do
        local n = todo.spawn[m.key] or 0
        if n > 0 and (asked >= want + MAX_EXTRA or others >= OTHERS_MAX or not self:slots_ready()) then n = 0 end
        for _ = 1, n do
            local slot = self:load_member(setup, m)
            if not slot then
                -- With the built-in slots only, for good: given up, so the course falls back to one that can come.
                if self:slots_final() and (depth or 0) < 3 then
                    self:give_up(setup, m)
                    return self:keep_up(enemies, now, (depth or 0) + 1)
                end
                break
            end
            local names = self.game.spawn_wave(self.catalogue.territory, slot)
            table.insert(self.pending[m.key], now)
            asked = asked + 1
            self.log("spawn\t" .. m.template .. "\tslot " .. slot .. "\t" .. table.concat(names or {}, ","))
        end
    end
    if #todo.remove > 0 then
        local by_key = {}
        for _, e in ipairs(enemies) do by_key[e.key] = e end
        self.removed_at = self.removed_at or {}
        for _, key in ipairs(todo.remove) do
            local e = by_key[key]
            local asked = self.removed_at[key]
            -- Asked once; again only if it is still there 10 s later. It stays marked (held, out of the fight) until
            -- it is gone: the old one was asked again every tick for the 9 s the game took (2026-11-22).
            if e and (not asked or now - asked >= REMOVE_AGAIN_SECONDS) then
                local ok = self.game.remove(self.catalogue.territory, e.actor)
                local since = self.retired_at and self.retired_at[key]
                if ok then self.removed_at[key] = now end
                self.log("remove\t" .. key .. "\t" .. tostring(ok) .. (asked and "\tagain" or "")
                    .. (since and string.format("\t%.1f s after it was replaced", now - since) or ""))
            end
        end
    end
    -- Per behaviour (owner 2026-11-21): Passive and Healing as before, enemies held and refilled below 90% HP (Passive
    -- is for trying things out); Aggressive real: no refill, enemies die, and a cleared wave waits for Respawn.
    local refill = self.settings.behaviour ~= "aggressive"
    for _, e in ipairs(enemies) do
        if refill then
            local hp, max = self.game.hp(e.actor)
            if hp and max and max > 0 and hp < max * REFILL_BELOW / 100 then self.game.refill(e.actor) end
        end
        -- Passive and Healing hold them, once placed (on the floor); none is held before.
        if self.stale[e.key] then
            self.game.hold(e.actor, true) -- replaced: held until it goes
        elseif self:placed_once(e) or not self.game.move_to then
            self.game.hold(e.actor, self.settings.behaviour ~= "aggressive")
        end
    end
end

-- Placing (owner 2026-11-21): enemies came out a couple of metres up and fell; Passive's hold caught them in mid-air,
-- and Alexander, which never moves, stayed up in every behaviour; three Alexanders stood 0.0 m apart. So every new
-- enemy of ours is placed at once and again at 0.5, 1 and 1.5 s (its own set-up can move it, as with the anchor):
--   apart: centre to centre at least its size + the other's + 2 m, size = the larger of its capsule radius and its
--     bounds' half side (at most 15 m); if it stands nearer, it goes to the first spot round the other, a twelfth of a
--     turn at a time, ring by ring, that keeps the gap to all, has floor under it and no wall in the way;
--   on the floor: its capsule's half height above the floor the trace finds, unless the tables mark it aerial
--     (the Zu, bats and other flyers keep their height).
-- Passive and Healing hold an enemy only once it has been placed.
local GAP = 200          -- cm between two enemies' edges
local SIZE_MAX = 1500    -- cm: bounds can take in effects far out
local PLACE_TRIES = 4    -- at 0, 0.5, 1 and 1.5 s
local GROUND_SLACK = 20  -- cm off the floor that is left alone

local function flat(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2) end
local FLOOR_SLACK = 200  -- cm: a trace hit further than this from the party's floor is something else (a stage's
                         -- prop 8 m up held three Alexanders in the air on Inside the Lifestream, 2026-11-21)

-- The floor under spot, judged against the party's (ref): a hit far from it is traced again from just above ref.
function M:floor_at(actor, spot, ignore, ref)
    local f = self.game.floor_z(actor, spot, ignore)
    if ref and (not f or math.abs(f - ref) > FLOOR_SLACK) then
        f = self.game.floor_z(actor, { X = spot.X, Y = spot.Y, Z = ref + 150 }, ignore)
        if f and math.abs(f - ref) > FLOOR_SLACK then f = nil end
    end
    return f
end

function M:size_of(e, p)
    if not p.size then
        local sz = self.game.size and self.game.size(e.actor) or {}
        p.size = { half = sz.half or 0, radius = math.min(SIZE_MAX, math.max(sz.radius or 50, sz.extent or 0)), mode = sz.mode }
    end
    return p.size
end

function M:place_one(e, live, ignore, p)
    local here = self.game.location(e.actor)
    if not here then return end
    local me = self:size_of(e, p)
    local spot = { X = here.X, Y = here.Y, Z = here.Z }
    local function fits(at)
        for _, o in ipairs(live) do
            if o.key ~= e.key then
                local there = self.game.location(o.actor)
                local op = self.placed[o.key]
                local r = o.party and 50 or (op and op.size and op.size.radius or 50)
                if there and flat(at, there) < me.radius + r + GAP then return false, o, there, r end
            end
        end
        return true
    end
    local ok, other, there, r = fits(spot)
    if not ok then
        local found = nil
        for ring = 0, 3 do
            local d = (me.radius + r + GAP) * (1 + ring * 0.5)
            for k = 0, 11 do
                local angle = k * math.pi / 6
                local at = { X = there.X + d * math.cos(angle), Y = there.Y + d * math.sin(angle), Z = here.Z }
                local floor = self.game.floor_z and self:floor_at(e.actor, at, ignore, self.ref_floor)
                local level = self.ref_floor or (here.Z - me.half)
                if fits(at) and (not self.game.floor_z or (floor and math.abs(floor - level) < 300))
                    and (not self.game.clear_way or self.game.clear_way(e.actor, here, at, ignore)) then
                    found = at
                    break
                end
            end
            if found then break end
        end
        if found then
            spot = found
            self.spread_moves = (self.spread_moves or 0) + 1
            self.log("spread\t" .. e.key .. "\tfrom " .. other.key .. "\t" .. math.floor(flat(here, found)) .. " cm")
        elseif not p.no_room then
            p.no_room = true
            self.no_room = (self.no_room or 0) + 1
            self.log("spread\t" .. e.key .. "\tno room beside " .. other.key)
        end
    end
    if not self.air[e.full_spec] and self.game.floor_z then
        local floor = self:floor_at(e.actor, spot, ignore, self.ref_floor)
        if floor then
            p.floor = math.floor(floor)
            self.arena_floor = self.arena_floor or p.floor
            local z = floor + me.half
            if math.abs(spot.Z - z) > GROUND_SLACK then
                if not p.lowered then self.log("ground\t" .. e.key .. "\t" .. math.floor(spot.Z - z) .. " cm up") end
                p.lowered = true
                self.grounded_moves = (self.grounded_moves or 0) + 1
            end
            spot.Z = z
        end
    end
    if spot.X ~= here.X or spot.Y ~= here.Y or math.abs(spot.Z - here.Z) > GROUND_SLACK then
        self.game.move_to(e.actor, spot)
    end
    p.spot = spot -- where it was put (the check reads it: in Aggressive they move off at once)
end

-- members: the set of keys that are the setup's own (spaced); the others (adds) are only put on the floor, where
-- their summoner put them.
function M:place(enemies, now, members)
    if not (self.game.location and self.game.move_to) then return end
    self.placed = self.placed or {}
    local live, spaced, ignore = {}, {}, {}
    for _, e in ipairs(enemies) do
        ignore[#ignore + 1] = e.actor
        if not self.stale[e.key] then
            live[#live + 1] = e
            if not members or members[e.key] then spaced[#spaced + 1] = e end
        end
    end
    -- The party too: an enemy put down on top of Cloud pushed him through the floor (a Brutal round, 2026-11-21).
    local party = {}
    for _, m in ipairs(self.party_members or {}) do
        ignore[#ignore + 1] = m.actor
        party[#party + 1] = { key = "party:" .. tostring(m.id), actor = m.actor, party = true }
    end
    for _, e in ipairs(live) do
        local p = self.placed[e.key]
        if not p then p = { at = now, tries = 0 }; self.placed[e.key] = p end
        if p.tries < PLACE_TRIES and now - p.at >= p.tries * 0.5 then
            p.tries = p.tries + 1
            self:size_of(e, p)
            local others = party
            if not members or members[e.key] then
                others = {}
                for _, o in ipairs(spaced) do others[#others + 1] = o end
                for _, o in ipairs(party) do others[#others + 1] = o end
            end
            -- The party's floor, once per pass: the floor under the first member, who stands on it.
            if not self.ref_at or self.ref_at ~= now then
                self.ref_at, self.ref_floor = now, nil
                local m = (self.party_members or {})[1]
                local at = m and self.game.location(m.actor)
                if at and self.game.floor_z then self.ref_floor = self.game.floor_z(m.actor, at, ignore) end
            end
            self:place_one(e, others, ignore, p)
        end
    end
    self:catch_party()
end

-- A party member more than 5 m below the arena's floor has fallen through it: back on the floor where the course
-- opened (Cloud stood under the floor and nothing could reach him, 2026-11-21).
function M:catch_party()
    if not (self.arena and self.arena_floor) then return end
    for _, m in ipairs(self.party_members or {}) do
        local at = self.game.location(m.actor)
        -- Below the floor, or far from the arena: some fights' scripts put the party where their own battle stood (the
        -- world's origin, 2 km from ours and above our floor's height: no fight reached Cloud there, 2026-11-22).
        local away = at and math.sqrt((at.X - self.arena.X) ^ 2 + (at.Y - self.arena.Y) ^ 2)
        if at and (at.Z < self.arena_floor - 500 or away > 50000) then
            local sz = self.game.size and self.game.size(m.actor) or {}
            local spot = { X = self.arena.X, Y = self.arena.Y, Z = self.arena_floor + (sz.half or 100) + 5 }
            self.game.move_to(m.actor, spot)
            self.party_caught = (self.party_caught or 0) + 1
            self.log("caught\t" .. tostring(m.id) .. "\t" .. math.floor(self.arena_floor - at.Z) .. " cm below the floor, "
                .. math.floor(away / 100) .. " m from the arena")
        end
    end
end

-- Placed once at least: held from then on (an enemy held before it lands stays in the air).
function M:placed_once(e)
    local p = self.placed and self.placed[e.key]
    return p ~= nil and p.tries > 0
end

-- Wave slots -------------------------------------------------------------------------------------------------
-- A round can only start its own territory's waves 0-15, so every opponent is spawned from one slot whose template
-- and level the native helper rewrites first (CustomTrainingSetWave); the helper finds the loaded row by the 16
-- waves it ships with (catalogue.base). Without the helper only those 16 opponents can be spawned, from their own
-- slots.

local function le32(n)
    n = math.floor(n) & 0xffffffff
    return string.format("%02x%02x%02x%02x", n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >> 24) & 0xff)
end

function M:base_index(id)
    for i, b in ipairs(self.catalogue.base) do if b.id == id then return i - 1 end end
    return nil
end

-- true once slots can be written; false while the helper is looking; nil when only the base slots can be used.
local SLOT_RETRIES = 3       -- a "not found" search is asked again this many times, 5 s apart (ui's run on Cave of
local SLOT_RETRY_SECONDS = 5 -- the Gi, 2026-11-21: a stale copy of the level list left only the 16 built-in opponents)

function M:slots_ready()
    if self.slots == "found" then return true end
    local find = native("CustomTrainingFindWaves")
    if not find then self.slots = "base"; return true end
    local now = self.clock()
    if self.slots == "base" then
        if (self.slot_retries or 0) < SLOT_RETRIES and self.slots_retry_at and now >= self.slots_retry_at then
            self.slot_retries = (self.slot_retries or 0) + 1
            self.slots, self.slots_state = nil, nil
            self.log("slots\tsearching again (" .. self.slot_retries .. " of " .. SLOT_RETRIES .. ")")
        else
            return true
        end
    end
    if self.slots_asked and now - self.slots_asked < 1 then return false end
    self.slots_asked = now
    local names, levels = {}, {}
    for _, b in ipairs(self.catalogue.base) do
        local index = self.game.fname_index(b.id)
        if not index then self.slots = "base"; self.log("slots\tno name index for " .. b.id); return true end
        names[#names + 1] = le32(index) .. le32(0)
        levels[#levels + 1] = le32(b.level)
    end
    local ok, state = pcall(find, table.concat(names), table.concat(levels))
    state = ok and state or ("error " .. tostring(state))
    if state ~= self.slots_state then self.log("slots\t" .. tostring(state)) end
    self.slots_state = state
    if state == "found" then self.slots = "found"; return true end
    if state ~= "searching" then
        self.slots = "base"
        self.slots_retry_at = now + SLOT_RETRY_SECONDS
        return true
    end
    return false
end

-- Only the 16 built-in slots, and no more searches to come: an opponent outside them can't be spawned.
function M:slots_final()
    return self.slots == "base" and ((self.slot_retries or 0) >= SLOT_RETRIES or not native("CustomTrainingFindWaves"))
end

-- Writes the setup's fixed waves (a round's own, a member's adds) and member m's own wave; returns the wave to start.
function M:load_member(setup, m)
    if self.slots ~= "found" then
        local i = self:base_index(m.template)
        if not i then
            -- Said once per opponent (it was said several times a second, 2026-11-21).
            self.noslot_said = self.noslot_said or {}
            if not self.noslot_said[m.template] then
                self.noslot_said[m.template] = true
                self.log("spawn\tno slot for " .. m.template .. " (the wave row was not found: only the 16 built-in opponents)")
            end
        end
        return i
    end
    local set = native("CustomTrainingSetWave")
    for slot, f in pairs(setup.fixed) do
        local index = self.game.fname_index(f.template)
        if index then pcall(set, slot, index, 0, f.level) end
    end
    local index = self.game.fname_index(m.template)
    local ok, done = pcall(set, m.slot, index or 0, 0, m.level)
    if not (ok and done) then self.log("spawn\tslot " .. m.slot .. " not written for " .. m.template); return nil end
    self.slots_dirty = true
    return m.slot
end

function M:restore_slots()
    if self.slots ~= "found" or not self.slots_dirty then return end
    local set = native("CustomTrainingSetWave")
    for i, b in ipairs(self.catalogue.base) do
        local index = self.game.fname_index(b.id)
        if index then pcall(set, i - 1, index, 0, b.level) end
    end
    self.slots_dirty = false
end

-- The settings panel (the owner's mock-up) --------------------------------------------------------------------
-- Opened with F7 or, in a fight, both shoulder buttons; it pauses the game while open. ct_panel_model decides,
-- ct_panel draws, ct_input turns held keys into presses.

function M:menu_catalogue()
    if not self.menu_list then
        local list, all_looked = {}, true
        local all = native("CustomTrainingSetWave") ~= nil
        for _, o in ipairs(self.catalogue.opponents) do
            if (all or self:base_index(o.id)) and not self.unspawnable[o.id] then
                local name, looked = self:name(o)
                all_looked = all_looked and looked
                list[#list + 1] = { id = o.id, category = o.category, name = name, max_count = M.max_count(o) }
            end
        end
        -- The catalogue's names are unique in English (make_spec.py checks); a language that names two alike gets a
        -- number on the second.
        local seen = {}
        for _, e in ipairs(list) do
            local n = (seen[e.name] or 0) + 1
            seen[e.name] = n
            if n > 1 then e.name = e.name .. " " .. n end
        end
        -- Built again next time while a name is still the fallback.
        if not all_looked then return list end
        self.menu_list = list
    end
    return self.menu_list
end

function M:meters_state()
    if not self.meters then return nil end
    local ok, st = pcall(self.meters.state)
    if ok and type(st) == "table" then return st end
    return nil
end

function M:panel()
    -- The meters' sections come and go with the meters part (its state file in a development install).
    local with_meters = self:meters_state() ~= nil
    if not self.panel_model or self.panel_meters ~= with_meters then
        -- No Equipment here: the owner wants gear changed only from the simulator's menus (2026-11-20 evening).
        self.panel_model = panel_model.new(self:menu_catalogue(), { difficulties = self:difficulties(), meters = with_meters })
        self.panel_meters = with_meters
    end
    return self.panel_model
end

function M:panel_open() return self.panel_model ~= nil and self.panel_model.open end

function M:open_panel()
    if self.panel_blocked() then return end
    self:panel():show(self.settings, self:meters_state())
    self.input:reset()
    self.game.pause(true)
    self.log("panel\topen")
end

function M:close_panel(why)
    if self.panel_model then self.panel_model:hide() end
    self.game.hide_panel()
    self.game.pause(false)
    self.log("panel\tclosed\t" .. tostring(why))
end

-- F7, the development command, or the shoulder chord: open, or hide when open. Only in a running course: F7 on the
-- simulator's course list belongs to Simulator Stages (stages_picker = key), and must not open the panel later.
function M:request_menu()
    if self.active then self.menu_requested = true end
end
-- Development only: a panel key, standing in for a press the test harness cannot make.
function M:inject_key(key) self.injected = self.injected or {}; self.injected[#self.injected + 1] = key end

function M:changed(key, now)
    self.save_settings()
    self.log("set\t" .. key .. "\t" .. tostring(self.settings[key]))
    if key == "opponent" or key == "group" or key == "mode" or key == "round" or key == "count" or key == "difficulty" then
        self.wave, self.wave_replaced, self.last_clear = 0, true, nil -- a fresh wave, not a clear
    elseif key == "behaviour" and self.wave_started then
        -- The same enemies fight on, under other rules: the wave's clock starts again (meters, 2026-11-21: a clear
        -- 7 s after a change to Aggressive read 106 s, timed from the Passive start).
        self.wave_started, self.last_clear = now or self.clock(), nil
    end
    if key == "opponent" or key == "group" or key == "mode" or key == "round" or key == "count" then
        -- What the new setup doesn't need is replaced; what it does is kept (the same opponent chosen again). A round
        -- starts as a fresh set: everything is replaced (two Bombs left from a group would have stood for its Bomb
        -- and, the set being "there", nothing else came).
        local enemies = self:ours()
        local setup = self:setup()
        local _, taken = M.match(enemies, {}, nil) -- a change starts a fresh wave: all of it new
        self.watch_ds, self.change_at, self.kept_at_change = self:shown_now(), now or self.clock(), {}
        for _, e in ipairs(enemies) do if not taken[e.key] then self:retire(e, now) end end
        self.misses, self.pending = {}, {}
        self:want_clean(now)
    elseif key == "difficulty" then
        self:want_clean(now)
        self:apply_difficulty()
        -- HP, level and stagger are fixed when an enemy appears, so bring them back to take the new difficulty.
        self.watch_ds, self.change_at, self.kept_at_change = self:shown_now(), now or self.clock(), {}
        for _, e in ipairs(self:ours()) do self:retire(e, now) end
    end
end

function M:apply(changes, now)
    -- Difficulty first: the opponents brought back for a new opponent or count then come at the new difficulty.
    for _, key in ipairs({ "difficulty", "mode", "round", "group", "opponent", "count", "behaviour" }) do
        if changes[key] ~= nil then
            self.settings[key] = changes[key]
            self:changed(key, now)
        end
    end
    if next(changes) ~= nil then self:reset_mp(); self.emit("change") end
end

function M:reset_mp()
    self.mp_refilled = {}
    self.mp_version = self.mp_version + 1
    self.hits, self.damage, self.party_refills = 0, 0, 0 -- the sweep's counts, per setup too
end

-- The panel's meter commands, to the meters part (meters_api.act, or its file bridge).
function M:send_meters(commands)
    if not (self.meters and commands) then return end
    for _, c in ipairs(commands) do
        local ok, err = pcall(self.meters.act, c)
        self.log("meters\t" .. c .. (ok and "" or "\t" .. tostring(err)))
    end
end

function M:panel_tick(now)
    if self.menu_requested then
        self.menu_requested = false
        if self:panel_open() then self:close_panel("toggle") else self:open_panel() end
    elseif not self:panel_open() and not self.panel_blocked() and self.game.in_battle()
        and input_module.chord(self.game.keys_down(input_module.OPEN_CHORD)) then
        self:open_panel()
    end
    if not self:panel_open() then return end
    local was_armed = self.input.armed
    local pressed = self.input:poll(self.game.keys_down(self.all_keys), now)
    if self.input.armed and not was_armed then self.log("panel	keys live (every key seen up)") end
    for _, key in ipairs(self.injected or {}) do pressed[#pressed + 1] = key end
    self.injected = nil
    for _, key in ipairs(pressed) do
        local r = self.panel_model:press(key, self.settings)
        if r then
            self.log("panel\t" .. key .. "\t" .. r.kind)
            if r.kind == "apply" then
                self:close_panel("apply")
                self:apply(r.changes, now)
                self:send_meters(r.meters)
            else
                self:close_panel(r.kind)
            end
            return
        end
    end
    local ok, err = self.game.show_panel(self.panel_model:view())
    if not ok and err ~= self.panel_error then self.log("panel\tdraw\t" .. tostring(err)) end
    self.panel_error = err
end

-- The party: Healing holds every member at 1% HP, Aggressive refills anyone below half, MP is refilled always
-- (ct_party.lua, from Training Dummy's three courses).
-- A new opponent (or difficulty) and a new course start with a clean party: no ailment or debuff the last opponent
-- left, HP as the behaviour sets it, MP full (owner 2026-11-21). Done at once and again 2 s later, for a last
-- strike of the opponent being replaced.
function M:want_clean(now)
    now = now or self.clock()
    self.clean_times = { now, now + 2 }
end

function M:clean_party(members)
    for _, m in ipairs(members) do
        local removed = self.game.clear_bad_status and self.game.clear_bad_status(m.actor) or {}
        -- Ailments and debuffs come off in every behaviour; HP (Passive) and MP (Passive, Healing) come back, but not in
        -- Aggressive, where what was spent stays spent (owner 2026-11-21).
        if self.settings.behaviour == "passive" and m.hp and m.max and m.hp < m.max then
            self.game.set_hp_percent(m.actor, 100)
        end
        if self.settings.behaviour ~= "aggressive" and self.game.full_mp then self.game.full_mp(m.kind) end
        if self.party_last then self.party_last[m.id] = nil end
        if #removed > 0 then self.log("clean\t" .. tostring(m.id) .. "\t" .. table.concat(removed, " ")) end
    end
end

function M:party_tick(now)
    local members = self.game.party()
    self.party_members = members
    if self.clean_times and self.clean_times[1] and now >= self.clean_times[1] then
        table.remove(self.clean_times, 1)
        self:clean_party(members)
        members = self.game.party()
    end
    -- Condemned and stone come off as they land, twice a second: they knock out at any HP, and the refills keep the
    -- party up otherwise (a solo party knocked out ends the round: Iron Man, 2026-11-21).
    -- And Auto-Life stays on everyone: a blow above the whole HP (the Tonberry King's knife) revives instead.
    if now >= (self.lethal_at or 0) then
        self.lethal_at = now + 0.5
        for _, m in ipairs(members) do
            if self.game.clear_bad_status and self.game.LETHAL_STATUSES then
                local removed = self.game.clear_bad_status(m.actor, self.game.LETHAL_STATUSES)
                if #removed > 0 then self.log("lethal\t" .. tostring(m.id) .. "\t" .. table.concat(removed, " ")) end
            end
            if self.game.keep_reraise and self.game.keep_reraise(m.actor) then
                self.reraise_given = (self.reraise_given or 0) + 1
                self.log("reraise\t" .. tostring(m.id))
            end
        end
    end
    -- Hits the party took since the start or the last change (HP going down, before any refill): the opponent
    -- sweep's evidence that an opponent attacks.
    self.party_last = self.party_last or {}
    self.party_seen = {}
    for _, m in ipairs(members) do
        local last = self.party_last[m.id]
        if last and m.hp and m.hp < last then
            self.hits = (self.hits or 0) + 1
            self.damage = (self.damage or 0) + (last - m.hp)
        end
        self.party_seen[#self.party_seen + 1] = { id = m.id, hp = m.hp, max = m.max }
    end
    local actions = self.party:step(members, self.settings.behaviour, now)
    for _, a in ipairs(actions) do
        for _, m in ipairs(members) do
            if m.id == a.id then self.game.set_hp_percent(m.actor, a.action == "low" and 1 or 100) end
        end
        if a.action == "full" then self.party_refills = (self.party_refills or 0) + 1 end
    end
    -- After our own writes the next reading starts afresh, so a drop to 1% is not taken for a hit.
    for _, m in ipairs(members) do self.party_last[m.id] = m.hp end
    for _, a in ipairs(actions) do self.party_last[a.id] = nil end
    -- MP refilled as it is spent in Passive and Healing; not in Aggressive (owner 2026-11-21: real conditions).
    if self.settings.unlimited_mp ~= "off" and self.settings.behaviour ~= "aggressive" then
        for _, m in ipairs(members) do
            local given = self.game.refill_mp(m.kind)
            if type(given) == "number" and given > 0 then
                self.mp_refilled[m.id] = (self.mp_refilled[m.id] or 0) + given
                self.mp_version = self.mp_version + 1
            end
        end
    end
end

-- Respawn (owner 2026-11-21): the last chosen set again, at full HP, placed and spaced; at any time: after a clear,
-- or mid-fight to reset it (what is there is replaced by a fresh set). Only in a running course.
function M:respawn(now)
    if not self.active then return false, "no Custom Training course is running" end
    now = now or self.clock()
    self.watch_ds, self.change_at, self.kept_at_change = self:shown_now(), now, {}
    for _, e in ipairs(self:ours()) do self:retire(e, now) end
    self.respawn_requested, self.pending, self.misses = true, {}, {}
    self:want_clean(now)
    self.log("respawn\t" .. self:setup_name())
    return true
end

-- Development: the setup's own enemies to p% HP, so a watched run can start the HP phases (gimmick fights) without
-- waiting for the party to wear them down.
function M:set_member_hp(p)
    local n = 0
    -- Every enemy of ours but the anchor (ours() leaves it out): the setup's own and their adds and reinforcements.
    for _, e in ipairs(self:ours()) do
        if not self.stale[e.key] then self.game.set_hp_percent(e.actor, p); n = n + 1 end
    end
    self.log("hp	" .. p .. "%	" .. n .. " enemies")
    return n
end

-- Damage-source actors in the world (bullets, orbs), every 2 s: the "left behind" check after a change counts them.
function M:damage_sources(now)
    if not self.game.damage_source_count then return nil end
    if not self.ds_at or now - self.ds_at >= 2 then
        self.ds_at, self.ds_count = now, self.game.damage_source_count()
        -- What is left of the replaced enemies' own (owner or instigator), the trustworthy count.
        if self.game.damage_sources_left then self.ds_left = self.game.damage_sources_left(self.watch_ds or {}) end
    end
    return self.ds_count
end

-- The tick -----------------------------------------------------------------------------------------------------

function M:tick()
    local now = self.clock()
    local enemies, anchor = self:ours()
    self.anchor_present = anchor ~= nil
    if #enemies > 0 or anchor then
        if not self.active then self.seen = {}; self:begin(now) end
        self.gone_since = nil
    elseif self.active then
        if self.game.in_battle() then
            self.gone_since = nil
        else
            self.gone_since = self.gone_since or now
            if now - self.gone_since >= GONE_SECONDS then self:finish() end
        end
    end
    if not self.active then return false end
    self:panel_tick(now)
    -- Spawns only into a running round: one of ours is always kept until its replacement is there, so none means the
    -- round is over (given up, or the course is closing) and nothing may be spawned into it.
    if not self:panel_open() and (#enemies > 0 or anchor) then
        self:keep_up(enemies, now)
        self:party_tick(now)
    end
    if anchor then
        -- Stashed 2 s after it appears (its own set-up overwrites anything earlier, as Junon Colosseum found), and
        -- again while it is still in the arena.
        if (self.anchor_tries or 0) < 6 and now - (self.anchor_at or now) >= 2 then
            -- Every second from 2 s in, six times, to the same spot: its own set-up can put it back.
            self.anchor_at, self.anchor_tries = now - 1, (self.anchor_tries or 0) + 1
            self.anchor_spot = self.game.stash(anchor.actor, self.anchor_spot) or self.anchor_spot
            -- Not targetable either: else the player's auto-target picks it ("Zu" over empty space, ui's run).
            local untargeted = self.game.untarget and self.game.untarget(anchor.actor)
            if self.anchor_tries == 1 then self.log("anchor\t" .. anchor.key .. "\tstashed\tuntargetable " .. tostring(untargeted)) end
        end
        local hp, max = self.game.hp(anchor.actor)
        if hp and max and max > 0 and hp < max then self.game.refill(anchor.actor) end
        self.game.hold(anchor.actor, true)
    end
    local o = self:opponent()
    local setup = self:setup()
    local group = {}
    for _, m in ipairs(setup.members) do for _ = 1, m.count do group[#group + 1] = m.as end end
    self.status = { active = true, opponent = o.id, name = self:name(o), count = self:count(),
                    mode = setup.round and "round" or "opponents", round = setup.round and setup.round.round.id or nil,
                    setup = self:setup_name(), group = group,
                    behaviour = self.settings.behaviour, difficulty = self.settings.difficulty,
                    difficulty_now = self:read_difficulty(), menu_open = self:panel_open(), enemies = {},
                    party = self.party_seen or {}, hits = self.hits or 0, damage = self.damage or 0,
                    party_refills = self.party_refills or 0, mp_refilled = self.mp_refilled,
                    spread = self.spread_moves or 0, grounded = self.grounded_moves or 0, no_room = self.no_room or 0,
                    caught = self.party_caught or 0, fallback = self.fallback,
                    stage_name = self:stage() and self:stage().name or nil, room_m = self:room_m(),
                    damage_sources = self:damage_sources(now), damage_sources_left = self.ds_left,
                    damage_sources_at_change = (function() local n = 0; for _ in pairs(self.watch_ds or {}) do n = n + 1 end; return n end)(),
                    wave = self.wave or 0,
                    wave_started = self.wave_started, wave_time = self.wave_started and (now - self.wave_started) or nil,
                    last_clear = self.last_clear, cleared = self.clear_noted == true,
                    cleared_in_s = self.clear_noted and self.last_clear or nil }
    -- For the sweep: each enemy's model spec and, where the game gives it, its own spec row and that row's name (the
    -- anchor too, marked), to set against the opponent's (ui's walk, 2026-11-21: "Bladefin" said to show as "Zu").
    -- GetBattleCharaSpec_DataTableID answered "None" for spawned enemies in the game (2026-11-21): only an override.
    local function shown(bspec)
        local row = bspec and self.by_spec[bspec]
        return row and self:name({ id = "spec:" .. bspec, label = row.label, name = row.name, spec = bspec }) or nil
    end
    local listed = {}
    for _, e in ipairs(enemies) do listed[#listed + 1] = e end
    if anchor then
        listed[#listed + 1] = { key = anchor.key, spec = anchor.spec, full_spec = anchor.full_spec, actor = anchor.actor, anchor = true }
    end
    for _, e in ipairs(listed) do
        local hp, max = self.game.hp(e.actor)
        local loc = self.game.location and self.game.location(e.actor)
        local bspec = self.game.battle_spec and self.game.battle_spec(e.actor)
        local placed = self.placed and self.placed[e.key]
        self.status.enemies[#self.status.enemies + 1] = { key = e.key, spec = e.spec, hp = hp, max = max,
            stale = self.stale[e.key] == true, x = loc and math.floor(loc.X), y = loc and math.floor(loc.Y),
            z = loc and math.floor(loc.Z), hidden = self.game.hidden and self.game.hidden(e.actor) or nil,
            bspec = bspec, shown = shown(bspec), model = e.full_spec, anchor = e.anchor,
            half = placed and placed.size and placed.size.half or nil, radius = placed and placed.size and placed.size.radius or nil,
            air = self.air[e.full_spec] or nil, floor = placed and placed.floor or nil,
            placed = placed and placed.spot and { x = math.floor(placed.spot.X), y = math.floor(placed.spot.Y), z = math.floor(placed.spot.Z) } or nil,
            placed_tries = placed and placed.tries or nil, member = (self.member_keys and self.member_keys[e.key]) or nil }
    end
    local _, leader_actor = (self.game.controller or function() end)()
    local at = leader_actor and self.game.location and self.game.location(leader_actor)
    if at then self.status.leader = { x = math.floor(at.X), y = math.floor(at.Y), z = math.floor(at.Z) } end
    local fps = leader_actor and self.game.frame_rate and self.game.frame_rate(leader_actor)
    if fps then self.status.fps = math.floor(fps + 0.5) end
    return true
end

M.DIFFICULTY_NAME = DIFFICULTY_NAME
return M
