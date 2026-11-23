-- Custom Training's interface for the other parts of Simulator Overhaul (owner 2026-11-20 evening):
--   ui      shows the settings in the game's own UI: it reads state() and lists() and calls apply();
--   meters  picks its meter by the course's behaviour: it registers on_course() (or, from a separate mod during
--           development, reads ct-course.txt, which main.lua writes on every change).
-- The settings logic stays in ct_session; this module only forwards. Calls are made on the game thread.
--
--   local ct = require("ct_api")
--   ct.active()                 -> true while a Custom Training course runs
--   ct.state()                  -> { active, opponent = id, name, count, max_count, behaviour, difficulty, anchor,
--                                  mode = "opponents" | "round", group = { id, ... } (one per enemy), group_names,
--                                  round = territory id, round_name, course = row, setup = the player's words for it }
--                                  (anchor: the object name of the hidden enemy that keeps the round going; not an
--                                  opponent, so meters should leave it out; opponent, name and max_count are the
--                                  setup's first opponent, count is how many enemies it brings)
--   ct.lists()                  -> { opponents = { { id, name, kind = 1..5, kind_name, max_count } ... } (sorted by kind,
--                                  then name), behaviours = { { id, name } ... }, difficulties = { { id, name } ... }
--                                  (only those this install can set), max_count = 3, group_max = 3,
--                                  courses = { { id, name, tab, tab_name, rounds = { { id, number, name, enemies, size } } } }
--                                  (the simulator's courses in its own order, only rounds that work; enemies_list =
--                                  { { name, count } } beside the enemies text), conflicts = { { id_a, id_b } } (pairs
--                                  that can't be in one group: their adds need the same wave) }
--   ct.apply(changes)           -> true, or false and why; changes: any of opponent (id), count (1..3),
--                                  group ({ id, ... } or "id,id,id": 1 to 3, one per enemy), round (territory id),
--                                  mode ("opponents" | "round"), behaviour ("passive" | "aggressive" | "healing"),
--                                  difficulty ("easy" | "normal" | "dynamic" | "hard"). opponent, count or group switch
--                                  to the opponents, round to the round. Applied at once in a running course; saved for
--                                  the next one.
--   ct.on_course(fn)            -> fn(event) on every start, end and change: event = { what = "start" | "end" |
--                                  "change" | "wave", active, behaviour, opponent, name, count, difficulty, wave, ... };
--                                  "clear": the last of a wave fell (clear_time s, cleared_wave = its number); the round
--                                  waits for respawn() unless ct_auto_respawn is on; "wave": a new set came (after a
--                                  clear with auto respawn it also carries clear_time and cleared).
--   ct.respawn()                -> true, or false and why: the last chosen set again, at once (also mid-fight). state() has wave (the current one's number, from 1; 0 only until the first
--                                  spawns, at a start or change), wave_started (session clock, s), wave_time (s it has
--                                  run) and last_clear (s; nil until a wave is cleared, again after a start or change).
--                                  A wave touches neither the party nor mp_refilled(); the battle stays on throughout.
--   ct.mp_refilled()            -> { Cloud = 123, ... }: MP given back to each party member (unlimited MP) since the
--                                  course started or last changed; meters count it as MP spent
-- Development files for separate mods (main.lua): ct-course.txt (format), ct-lists.txt (lists_text), ct-mp.txt
-- (mp_text).
local panel_model = require("ct_panel_model")

local M = { version = 1 }
local session = nil
local listeners = {}

function M.bind(s) session = s end

function M.active() return session ~= nil and session.active == true end

function M.state()
    if not session then return { active = false } end
    local o = session:opponent()
    local setup = session:setup()
    local group, names = {}, {}
    for _, m in ipairs(setup.members) do
        for _ = 1, m.count do group[#group + 1] = m.as; names[#names + 1] = session:name(session.by_id[m.as]) end
    end
    local r = setup.round
    return { active = session.active == true, opponent = o and o.id, name = o and session:name(o), max_count = session.max_count(o),
             count = session:count(), behaviour = session.settings.behaviour, difficulty = session.settings.difficulty,
             anchor = session.anchor_key, mode = r and "round" or "opponents", group = group, group_names = names,
             round = r and r.round.id or nil, round_name = r and session:round_name(r) or nil,
             course = r and r.course.id or nil, setup = session:setup_name(),
             stage_name = session:stage() and session:stage().name or nil, room_m = session:room_m(),
             needs_m = r and session:needs_of_round(r.round.id) or session.needs_of_group(session.by_id, group),
             fallback = session.fallback, wave = session.wave or 0,
             wave_started = session.wave_started,
             wave_time = session.wave_started and (session.clock() - session.wave_started) or nil,
             last_clear = session.last_clear, cleared = session.clear_noted == true,
             cleared_in_s = session.clear_noted and session.last_clear or nil }
end

-- The simulator's tabs (Colosseum TabCategory), named after what their courses' own titles begin with ("Grasslands
-- Battle Intel: ...", "Brutal Challenge: ..."): the tabs' own labels are not read yet. 8 and 9: Shinra Manor's
-- simulator, which shares the numbers 1 and 2 in the table.
M.TAB_NAMES = { [1] = "Summon Entities", [2] = "Battle Intel", [3] = "Region Intel", [4] = "Biological Intel",
                [5] = "Brutal Challenges", [6] = "Legendary Bouts", [8] = "Shinra Manor: Preliminary Trials",
                [9] = "Shinra Manor: Evaluations" }

function M.lists()
    if not session then return nil end
    local list = {}
    for _, e in ipairs(session:menu_catalogue()) do
        local o = session.by_id[e.id]
        list[#list + 1] = { id = e.id, name = e.name, kind = e.category, kind_name = panel_model.KINDS[e.category], max_count = e.max_count or panel_model.MAX_COUNT,
                            needs_m = o and o.needs or nil }
    end
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    local behaviours, difficulties = {}, {}
    for _, b in ipairs(panel_model.BEHAVIOURS) do behaviours[#behaviours + 1] = { id = b, name = panel_model.BEHAVIOUR_LABELS[b] } end
    local allowed = session:difficulties()
    for _, d in ipairs(panel_model.DIFFICULTIES) do
        if not allowed or allowed[d] then difficulties[#difficulties + 1] = { id = d, name = panel_model.DIFFICULTY_LABELS[d] } end
    end
    local courses = {}
    for _, c in ipairs(session.catalogue.courses or {}) do
        local rounds = {}
        for _, r in ipairs(c.rounds) do
            if not session.unspawnable["round:" .. r.id] then
                -- Merged by the name they read as (a round's Ver1 and Ver2 soldiers are one "Security Officer ×2").
                local members, by, size, list = {}, {}, 0, {}
                for _, mob in ipairs(r.mobs) do
                    local m = by[mob[5]]
                    if m then m.count = m.count + mob[2] else m = { as = mob[5], count = mob[2] }; by[mob[5]] = m; members[#members + 1] = m end
                    size = size + mob[2]
                end
                for _, m in ipairs(members) do list[#list + 1] = { name = session:name(session.by_id[m.as]), count = m.count } end
                rounds[#rounds + 1] = { id = r.id, number = r.number, name = "Round " .. r.number,
                                        enemies = session:enemies_text(members), enemies_list = list, size = size,
                                        needs_m = c.needs }
            end
        end
        if #rounds > 0 then
            courses[#courses + 1] = { id = c.id, name = session:course_name(c), tab = c.tab, tab_name = M.TAB_NAMES[c.tab], rounds = rounds }
        end
    end
    return { opponents = list, behaviours = behaviours, difficulties = difficulties, max_count = panel_model.MAX_COUNT,
             group_max = 3, max_group = 3, courses = courses, conflicts = session:conflicts(),
             room_m = session:room_m(), stage_name = session:stage() and session:stage().name or nil }
end

local VALID = {
    behaviour = { passive = true, aggressive = true, healing = true },
    difficulty = { easy = true, normal = true, dynamic = true, hard = true },
}

function M.apply(changes)
    if not session then return false, "Custom Training is not loaded" end
    local clean = {}
    for key, value in pairs(changes or {}) do
        if key == "opponent" then
            if not session.by_id[value] then return false, "unknown opponent " .. tostring(value) end
            clean.opponent = value
        elseif key == "group" then
            local ids = type(value) == "table" and value or session.split_ids(value)
            local ok, why = session:check_group(ids)
            if not ok then return false, why end
            clean.group = table.concat(ids, ",")
        elseif key == "round" then
            if not session.rounds_by_id[value] then return false, "unknown round " .. tostring(value) end
            if session.unspawnable["round:" .. value] then return false, "that round never appeared in this visit" end
            clean.round = value
        elseif key == "mode" then
            if value ~= "opponents" and value ~= "round" then return false, "unknown mode " .. tostring(value) end
            clean.mode = value
        elseif key == "count" then
            local n = tonumber(value)
            if not n or n < 1 or n > panel_model.MAX_COUNT or n ~= math.floor(n) then return false, "count is 1 to 3" end
            clean.count = n
        elseif VALID[key] then
            if not VALID[key][value] then return false, "unknown " .. key .. " " .. tostring(value) end
            clean[key] = value
        else
            return false, "unknown setting " .. tostring(key)
        end
    end
    -- A new opponent without a count keeps the count state() reported, which is what the caller showed: a capped
    -- opponent reports (and fights as) its cap while the stored count may be more (ui's walk, 2026-11-21: Titan, then
    -- capped as a boss, -> Black Bat with Number left at 1 brought two bats).
    if clean.opponent ~= nil and clean.count == nil and session.settings.count ~= session:count() then
        clean.count = session:count()
    end
    local target = session.by_id[clean.opponent or session.settings.opponent]
    if clean.count and target and clean.count > session.max_count(target) then
        return false, "count is 1 to " .. session.max_count(target) .. " for this opponent"
    end
    if clean.mode == "round" and not session.rounds_by_id[clean.round or session.settings.round] then
        return false, "no round chosen"
    end
    -- A group sets the opponent and count the panel shows; an opponent or count alone ends the group (one opponent
    -- repeated). Choosing enemies switches to the opponents, a round to the round.
    if clean.group then
        local ids = session.split_ids(clean.group)
        clean.opponent, clean.count = ids[1], #ids
    elseif clean.opponent ~= nil or clean.count ~= nil then
        clean.group = ""
    end
    if clean.mode == nil then
        if clean.round then clean.mode = "round"
        elseif clean.group or clean.opponent or clean.count then clean.mode = "opponents" end
    end
    -- Room: what doesn't fit the stage the course is on is refused (owner 2026-11-21: filter opponents by stage).
    local mode = clean.mode or session.settings.mode
    local need
    if mode == "round" then
        need = session:needs_of_round(clean.round or session.settings.round)
    elseif clean.group and clean.group ~= "" then -- (an opponent and count set group to "" just above)
        need = session.needs_of_group(session.by_id, session.split_ids(clean.group))
    elseif clean.opponent or clean.count then
        local id = clean.opponent or session.settings.opponent
        local ids = {}
        for i = 1, (clean.count or session:count()) do ids[i] = id end
        need = session.needs_of_group(session.by_id, ids)
    end
    if need then
        local fits, why = session:fits(need)
        if not fits then return false, why end
    end
    session:apply(clean, session.clock())
    return true
end

function M.on_course(fn) listeners[#listeners + 1] = fn end

-- The last chosen set again (ui's Respawn row; the respawn key): true, or false and why.
function M.respawn()
    if not session then return false, "Custom Training is not loaded" end
    return session:respawn()
end

function M.mp_refilled()
    local copy = {}
    if session then for k, v in pairs(session.mp_refilled) do copy[k] = v end end
    return copy
end

-- lists() as tab-separated lines (the ui part's format): opponent id kind kind_name max_count name (max_count was
-- the boss flag until 2026-11-21), behaviour id name, difficulty id name, max_count n, group_max n,
-- course id tab tab_name name, round course_id round_id number size name enemies needs_m; opponent lines end with
-- needs_m (field 7). needs_m: metres of room a pick needs; room_m (state, lists): the stage's, nil on the plain arena.
function M.lists_text(l)
    l = l or M.lists()
    if not l then return "" end
    local lines = {}
    for _, o in ipairs(l.opponents) do
        lines[#lines + 1] = table.concat({ "opponent", o.id, tostring(o.kind), o.kind_name or "", tostring(o.max_count), o.name,
            o.needs_m and string.format("%g", o.needs_m) or "" }, "\t")
    end
    for _, b in ipairs(l.behaviours) do lines[#lines + 1] = "behaviour\t" .. b.id .. "\t" .. b.name end
    for _, d in ipairs(l.difficulties) do lines[#lines + 1] = "difficulty\t" .. d.id .. "\t" .. d.name end
    lines[#lines + 1] = "max_count\t" .. tostring(l.max_count)
    lines[#lines + 1] = "group_max\t" .. tostring(l.group_max or 3)
    for _, c in ipairs(l.conflicts or {}) do lines[#lines + 1] = "conflict\t" .. c[1] .. "\t" .. c[2] end
    for _, c in ipairs(l.courses or {}) do
        lines[#lines + 1] = table.concat({ "course", c.id, tostring(c.tab), c.tab_name or "", c.name }, "\t")
        for _, r in ipairs(c.rounds) do
            lines[#lines + 1] = table.concat({ "round", c.id, r.id, tostring(r.number), tostring(r.size), r.name, r.enemies,
                r.needs_m and string.format("%g", r.needs_m) or "" }, "\t")
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

-- mp_refilled() as mp.<Name>=<total> lines, sorted by name.
function M.mp_text(t)
    t = t or M.mp_refilled()
    local names = {}
    for k in pairs(t) do names[#names + 1] = k end
    table.sort(names)
    local lines = {}
    for _, k in ipairs(names) do lines[#lines + 1] = "mp." .. k .. "=" .. tostring(t[k]) end
    return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

-- Called by ct_session; extra: fields for this event (a "wave" event's clear_time and cleared).
function M.emit(what, extra)
    local event = M.state()
    event.what = what
    for k, v in pairs(extra or {}) do event[k] = v end
    for _, fn in ipairs(listeners) do pcall(fn, event) end
    if M.write_status then pcall(M.write_status, event) end
    return event
end

-- The development file for a separate mod: key=value lines.
function M.format(event)
    local keys = { "what", "active", "behaviour", "opponent", "name", "count", "max_count", "difficulty", "anchor",
                   "mode", "group", "round", "setup", "stage_name", "room_m", "needs_m", "fallback", "wave",
                   "wave_started", "wave_time", "last_clear", "cleared", "cleared_in_s", "clear_time", "cleared_wave" }
    local lines = {}
    for _, k in ipairs(keys) do
        local v = event[k]
        if type(v) == "table" then v = table.concat(v, ",") end
        lines[#lines + 1] = k .. "=" .. tostring(v)
    end
    return table.concat(lines, "\n") .. "\n"
end

return M
