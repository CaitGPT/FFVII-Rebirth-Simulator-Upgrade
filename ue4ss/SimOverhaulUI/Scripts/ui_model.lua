-- Custom Training's settings in the game's own choice window, without the game: what each window shows and what a
-- choice in it does. ui_menu.lua shows it through the game (ui_window.lua); tested offline.
--
-- Everything is done with the window's own cursor and confirm, on the keyboard and on the pad alike: while the window
-- is open it has the input focus, so no mod can read held keys then (seen in the game, 2026-11-21). The main window
-- lists the settings, then Apply and Cancel. Confirming a setting opens the list of its values; confirming an opponent
-- row opens the kinds of enemy, then (for a large kind) ranges of names, then the names; confirming Round opens the
-- simulator's tabs, then the tab's courses, then the course's rounds. A value chosen comes back to the main window on
-- the same row; Apply hands every change to Custom Training at once.
--
-- What the main window holds follows what Custom Training offers (lists()):
--   group_max (mixed groups, 2026-11-21): Opponent 1, 2 and 3, the second and third with None; the same opponent in
--     several rows is copies of it, so there is no Number row. Without it: Opponent and Number, as before.
--   courses (pre-built rounds): a first row, Mode (Opponents / Round); in Round mode one Round row instead of the
--     opponent rows.
--
-- The window grows with its rows instead of scrolling: 13 rows fit on a 1080p screen under a short text (seen in the
-- game), so no window here has more than 13.
local M = {}
M.__index = M

M.LABELS = { mode = "Mode", opponent = "Opponent", opponent1 = "Opponent 1", opponent2 = "Opponent 2",
             opponent3 = "Opponent 3", count = "Number", round = "Round", behaviour = "Behaviour",
             difficulty = "Difficulty", meter = "Meter", clear = "Clear meter", stagger = "Reset stagger",
             apply = "Apply", cancel = "Cancel", respawn = "Respawn" }
M.MODES = { { id = "opponents", name = "Opponents" }, { id = "round", name = "Round" } }
-- The meter row's values: meters_api's three meters, then Hidden (its "hide").
M.METERS = { { id = "damage", name = "Damage" }, { id = "taken", name = "Tanking" }, { id = "heal", name = "Healing" },
             { id = "hidden", name = "Hidden" } }
M.SLOTS = 3        -- opponent rows at most (ct group_max)
M.PAGE = 12        -- choices per window, plus Back: 13 rows
M.ROW_CHARS = 44   -- a list row's text is kept to this many characters: a row fits about 45 before the game squeezes it
M.MAIN_CHARS = 50  -- a main-window row (label and value): 49 seen whole in the game (2026-11-21)

local function index_of(list, id)
    for i, e in ipairs(list) do if e.id == id then return i end end
    return nil
end

-- Splits list into the fewest parts of at most size items, as even as they can be.
local function split(list, size)
    local parts = math.max(1, math.ceil(#list / size))
    local each = math.ceil(#list / parts)
    local out = {}
    for p = 1, parts do
        local part = {}
        for i = (p - 1) * each + 1, math.min(p * each, #list) do part[#part + 1] = list[i] end
        if #part > 0 then out[#out + 1] = part end
    end
    return out
end
M.split = split

local function short(name, max)
    if #name <= max then return name end
    local cut = name:sub(1, max - 3)
    -- At a word's end when that keeps most of it ("Elite Grenadier..." rather than "Elite Grenadier (Ju...").
    local words = cut:match("^(.*%S)%s+%S*$")
    if words and #words >= max // 2 then cut = words end
    return (cut:gsub("[%s%(%-,:]+$", "")) .. "..."
end
M.short = short

-- A range's label: both names whole when they fit the row; otherwise the longer one gives way first, and each keeps at
-- least half the room.
local function range_label(first, last)
    local room = M.ROW_CHARS - 5
    if #first + #last <= room then return first .. "  -  " .. last end
    local half = room // 2
    local a = #first <= half and #first or math.max(half, room - math.min(#last, room - half))
    return short(first, a) .. "  -  " .. short(last, room - #short(first, a))
end
M.range_label = range_label

-- A round's enemies as { { name, count } }: Custom Training's enemies_list, or its enemies text ("Wererat ×2,
-- Elphadunk ×2"; a piece without a count is one), or an enemies table.
local TIMES = "\195\151" -- "×" in UTF-8
local function round_enemies(r)
    if type(r.enemies_list) == "table" then return r.enemies_list end
    if type(r.enemies) == "table" then return r.enemies end
    local out = {}
    if type(r.enemies) == "string" then
        for piece in (r.enemies .. ","):gmatch("%s*(.-)%s*,") do
            if piece ~= "" then
                local name, n = piece:match("^(.-)%s*" .. TIMES .. "%s*(%d+)$")
                if not name then name, n = piece:match("^(.-)%s+x%s*(%d+)$") end
                out[#out + 1] = { name = name or piece, count = tonumber(n) or 1 }
            end
        end
    end
    return out
end
M.round_enemies = round_enemies

-- A round's row: "Round 2: 2 Cerulean Drake, Sandworm" (the round's own name, else "Round N", then its enemies, a count
-- only where there are more than one, so the window needs no "×"). Too long for the row (or max): a long name gives
-- way a little first, then the last enemies give way to "+N" (Brutal Challenges have five or six enemies a round:
-- "Round 1: Thunderbird, Frightflower +4" reads better than every name cut to five letters, seen 2026-11-21).
M.NAME_MIN = 12 -- an enemy name is cut to no fewer characters than this
local function round_label(r, max)
    max = max or M.ROW_CHARS
    local head = (r.name and r.name ~= "") and r.name or ("Round " .. tostring(r.number or "?"))
    local enemies = round_enemies(r)
    if #enemies == 0 then return short(head, max) end
    local parts = {}
    for i, e in ipairs(enemies) do
        parts[i] = ((tonumber(e.count) or 1) > 1 and (tostring(e.count) .. " ") or "") .. e.name
    end
    local function text(k, more)
        local shown = {}
        for i = 1, k do shown[i] = parts[i] end
        return head .. ": " .. table.concat(shown, ", ") .. (more > 0 and (" +" .. more) or "")
    end
    local all = text(#parts, 0)
    if #all <= max then return all end
    -- Three or more kinds: at least two whole names and "+N" ("Savage Grandhorn, Grandhorn +1" rather than "Savage...,
    -- Grandhorn, Grandhorn..."). Two kinds: both, the longest cut down to NAME_MIN if that's all it takes (the counts stay).
    if #parts >= 3 then
        for k = #parts - 1, 2, -1 do
            local t = text(k, #parts - k)
            if #t <= max then return t end
        end
    end
    local cut = {}
    for i, p in ipairs(parts) do cut[i] = p end
    for _ = 1, #parts do
        local longest = 1
        for i, p in ipairs(cut) do if #p > #cut[longest] then longest = i end end
        local over = #(head .. ": " .. table.concat(cut, ", ")) - max
        if over <= 0 then return head .. ": " .. table.concat(cut, ", ") end
        if #cut[longest] <= M.NAME_MIN then break end
        cut[longest] = short(cut[longest], math.max(M.NAME_MIN, #cut[longest] - over))
    end
    if #(head .. ": " .. table.concat(cut, ", ")) <= max then return head .. ": " .. table.concat(cut, ", ") end
    -- Fewer names, whole, and "+N" for the rest; at least the first, cut to fit.
    for k = #parts - 1, 1, -1 do
        local t = text(k, #parts - k)
        if #t <= max then return t end
    end
    local tail = " +" .. (#parts - 1)
    return head .. ": " .. short(parts[1], math.max(4, max - #head - 2 - #tail)) .. tail
end
M.round_label = round_label

-- A course's name without the words every course of its tab shares ("Grasslands Battle Intel: Horror on the Range" in
-- Battle Intel -> "Grasslands Horror on the Range"; "Summon Entity: Titan" -> "Titan"), keeping a shared word before a
-- number ("Grasslands Level 1"). others: the tab's course names. For ranges and the main window's Round row, where room
-- is short; the courses window shows the whole name.
local function words_of(s)
    local t = {}
    for w in s:gmatch("%S+") do t[#t + 1] = w end
    return t
end
function M.course_short(name, others)
    if not others or #others < 2 then return name end
    local common
    for _, o in ipairs(others) do
        local set = {}
        for _, w in ipairs(words_of(o)) do set[w] = true end
        if not common then common = set
        else for w in pairs(common) do if not set[w] then common[w] = nil end end end
    end
    local ws, out = words_of(name), {}
    for i, w in ipairs(ws) do
        if not common[w] or (ws[i + 1] and ws[i + 1]:match("^%d")) then out[#out + 1] = w end
    end
    local s = table.concat(out, " "):gsub("[:%s]+$", "")
    return s ~= "" and s or name
end

-- An opponent or round that needs more room than the stage loaded has (owner 2026-11-21: every stage is offered, and
-- what doesn't fit it can't be chosen): marked in the lists, refused when confirmed.
M.MARK = " (larger stage)"

-- lists: ct_api.lists() ({ opponents = { { id, name, kind, kind_name, max_count? } }, behaviours = { { id, name } },
-- difficulties = { { id, name } }, max_count, group_max?, conflicts? = { { id, id } }, tabs? = { { id, name } },
-- courses? = { { id, name, tab, tab_name, rounds = { { id, number, name, enemies, size, needs_m? } } } } }, and each
-- opponent's needs_m?; agreed with custom-training 2026-11-21); state: ct_api.state() (with mode, group, round, and
-- stage_name and room_m while a stage is loaded); meters: meters_api.state() ({ meter,
-- label, visible }) when the meters part is present, else nil.
function M.new(lists, state, meters, opts)
    local self = setmetatable({ lists = lists, meters = meters }, M)
    local most = tonumber(lists.group_max) or tonumber(lists.max_group)
    self.slots = most and math.max(1, math.min(M.SLOTS, most)) or nil
    -- Respawn: a Custom Training that counts waves (state().wave; cleared too once it says so) and has a respawn to call
    -- (opts.respawn false: the caller has none).
    self.can_respawn = (not opts or opts.respawn ~= false) and (state.wave ~= nil or state.cleared ~= nil)
    -- Pairs Custom Training can't put in one group (their own adds need the same wave slot).
    self.conflict = {}
    for _, pair in ipairs(lists.conflicts or {}) do
        local a, b = pair[1], pair[2]
        if a and b then
            self.conflict[a] = self.conflict[a] or {}; self.conflict[a][b] = true
            self.conflict[b] = self.conflict[b] or {}; self.conflict[b][a] = true
        end
    end
    self:build_sections()
    self:build_rounds()
    self:reset(state)
    return self
end

-- The opponent list's first window: one entry a kind of enemy, in the order of the list; a kind too large for the two
-- windows below it (more than PAGE x PAGE names) is cut into parts named by the first letters they cover.
function M:build_sections()
    local by_kind, order = {}, {}
    for i, o in ipairs(self.lists.opponents) do
        if not by_kind[o.kind] then
            by_kind[o.kind] = { name = o.kind_name or ("Kind " .. o.kind), members = {} }
            order[#order + 1] = o.kind
        end
        local k = by_kind[o.kind].members
        k[#k + 1] = i
    end
    table.sort(order)
    self.sections = {}
    for _, kind in ipairs(order) do
        local k = by_kind[kind]
        local parts = split(k.members, M.PAGE * M.PAGE)
        for _, part in ipairs(parts) do
            local label = k.name
            if #parts > 1 then
                local first = self.lists.opponents[part[1]].name:sub(1, 1):upper()
                local last = self.lists.opponents[part[#part]].name:sub(1, 1):upper()
                label = k.name .. " (" .. first .. (first ~= last and ("-" .. last) or "") .. ")"
            end
            self.sections[#self.sections + 1] = { label = label, members = part }
        end
    end
end

-- The round list: the simulator's tabs that have courses, in Custom Training's order (tabs missing from its tab list
-- after them), each with its courses; every round with its course, for finding a round by id.
function M:build_rounds()
    local courses = self.lists.courses
    self.tabs, self.round_index, self.short_course = {}, {}, {}
    if type(courses) ~= "table" or #courses == 0 then return end
    local by_tab, order = {}, {}
    for _, t in ipairs(self.lists.tabs or {}) do
        by_tab[t.id] = { id = t.id, name = t.name, courses = {} }
        order[#order + 1] = t.id
    end
    for c, course in ipairs(courses) do
        local tab = course.tab or "?"
        if not by_tab[tab] then
            by_tab[tab] = { id = tab, name = course.tab_name or tostring(tab), courses = {} }
            order[#order + 1] = tab
        end
        local list = by_tab[tab].courses
        list[#list + 1] = c
        for r, round in ipairs(course.rounds or {}) do
            self.round_index[round.id] = { course = c, round = r }
        end
    end
    for _, id in ipairs(order) do
        if #by_tab[id].courses > 0 then self.tabs[#self.tabs + 1] = by_tab[id] end
    end
    -- Each course's short name, by the words its tab's courses share.
    for _, tab in ipairs(self.tabs) do
        local names = {}
        for i, c in ipairs(tab.courses) do names[i] = courses[c].name end
        for _, c in ipairs(tab.courses) do self.short_course[c] = M.course_short(courses[c].name, names) end
    end
end

function M:has_rounds() return #self.tabs > 0 end

-- The main window's rows for the draft's mode.
function M:build_rows()
    local rows = {}
    -- Respawn first (owner 2026-11-21: enemies don't refill; the player brings the fight back): the menu opens with the
    -- cursor on it, so LB+RB then A respawns.
    if self.can_respawn then rows[#rows + 1] = "respawn" end
    if self:has_rounds() then rows[#rows + 1] = "mode" end
    if self.draft.mode == "round" then
        rows[#rows + 1] = "round"
    elseif self.slots then
        for s = 1, self.slots do rows[#rows + 1] = "opponent" .. s end
    else
        rows[#rows + 1] = "opponent"; rows[#rows + 1] = "count"
    end
    rows[#rows + 1] = "behaviour"; rows[#rows + 1] = "difficulty"
    if self.meters then rows[#rows + 1] = "meter"; rows[#rows + 1] = "clear"; rows[#rows + 1] = "stagger" end
    rows[#rows + 1] = "apply"; rows[#rows + 1] = "cancel"
    self.rows = rows
end

-- The group a state describes, as opponent indexes: its group when Custom Training sends one (a table, or ids
-- separated by commas from the development file), else its opponent, count times (within the rows there are).
function M:state_group(state)
    local l, g = self.lists, {}
    local ids = state.group
    if type(ids) == "string" then
        local t = {}
        for id in ids:gmatch("[^,%s]+") do t[#t + 1] = id end
        ids = t
    end
    if type(ids) == "table" then
        for _, id in ipairs(ids) do
            local i = index_of(l.opponents, id)
            if i and #g < (self.slots or 1) then g[#g + 1] = i end
        end
    end
    if #g == 0 then
        local i = index_of(l.opponents, state.opponent) or 1
        for _ = 1, math.max(1, math.min(tonumber(state.count) or 1, self.slots or 1)) do g[#g + 1] = i end
    end
    return g
end

-- The draft starts from the course's current settings, on the main window's first row.
function M:reset(state)
    self.state = state
    local l = self.lists
    self.draft = {
        mode = (state.mode == "round" and self:has_rounds()) and "round" or "opponents",
        group = self:state_group(state),
        count = math.max(1, math.min(tonumber(state.count) or 1, l.max_count or 3)),
        behaviour = index_of(l.behaviours, state.behaviour) or 1,
        difficulty = index_of(l.difficulties, state.difficulty) or 1,
    }
    if self:has_rounds() then
        local at = self.round_index[state.round]
        if not at then
            local c = self.tabs[1].courses[1]
            at = { course = c, round = (l.courses[c].rounds and #l.courses[c].rounds > 0) and 1 or nil }
        end
        self.draft.course, self.draft.round = at.course, at.round
    end
    if self.meters then self.draft.meter = self:meter_index(self.meters) end
    self.notice, self.picking, self.slot = nil, nil, nil
    self:build_rows()
    self.row, self.screen = 1, "main"
end

-- The stage loaded and its room; nil on the plain arena. state() says (it changes with the stage; a Custom Training
-- with rooms always sends its needs_m), else lists() from when they were built.
function M:stage_info()
    local s = self.state.needs_m ~= nil and self.state or self.lists
    local n = s.stage_name
    return tonumber(s.room_m), (n and n ~= "") and n or nil
end
function M:room() return (self:stage_info()) end
function M:stage_name() return select(2, self:stage_info()) end
M.SPACING_M = 2 -- Custom Training: a group needs the most any member needs, plus this for each enemy beyond the first
-- The room a group of opponent indexes needs.
function M:group_need(group)
    local need, n = 0, 0
    for _, i in ipairs(group) do
        n = n + 1
        need = math.max(need, tonumber(self.lists.opponents[i].needs_m) or 0)
    end
    return need + M.SPACING_M * math.max(0, n - 1)
end
-- The room the draft would need with opponent index i in the picking row (without groups: i, Number times).
function M:pick_need(i)
    if not self.slots then
        return (tonumber(self.lists.opponents[i].needs_m) or 0) + M.SPACING_M * (self:count() - 1)
    end
    local g = {}
    for s, x in ipairs(self.draft.group) do g[s] = x end
    g[self.slot or 1] = i
    return self:group_need(g)
end
-- Whether a need (a number, or an opponent or round with needs_m) fits the stage: no stage, no need, or enough room.
function M:fits(e)
    local need = type(e) == "number" and e or tonumber(e and e.needs_m)
    local room = self:room()
    return not need or not room or need <= room
end
function M:marked(text, e)
    if self:fits(e) then return text end
    return short(text, M.ROW_CHARS - #M.MARK) .. M.MARK
end
function M:too_big()
    local stage = self:stage_name()
    return "Needs a larger stage" .. (stage and (" than " .. stage) or "")
end

-- "\nWave cleared in 1:23" while the round waits after a clear (state().cleared, with last_clear: the cleared wave's
-- seconds). A Custom Training that doesn't say cleared: "\nLast wave cleared in 1:23" once one was (last_clear stays
-- set after a respawn). Else "".
function M:cleared_text()
    local s = self.state
    local t = tonumber(s.cleared_in_s) or tonumber(s.last_clear) -- cleared_in_s: set while the round waits
    local function mmss(x)
        x = math.floor(x + 0.5)
        return string.format("%d:%02d", x // 60, x % 60)
    end
    if s.cleared == true then return t and ("\nWave cleared in " .. mmss(t)) or "\nWave cleared" end
    if s.cleared == nil and t then return "\nLast wave cleared in " .. mmss(t) end
    return ""
end

-- The first opponent row's opponent (the only one without groups).
function M:opponent() return self.lists.opponents[self.draft.group[1]] end
-- How many copies an opponent can have (the draft's first by default): its own max_count when Custom Training caps
-- it, else the list's.
function M:max_count(o)
    o = o or self:opponent()
    return math.max(1, tonumber(o and o.max_count) or tonumber(self.lists.max_count) or 3)
end
-- The number the course would get without groups: the draft's, within the opponent's cap.
function M:count() return math.min(self.draft.count, self:max_count()) end

function M:course() return self.draft.course and self.lists.courses[self.draft.course] or nil end
function M:round()
    local c = self:course()
    return c and c.rounds and self.draft.round and c.rounds[self.draft.round] or nil
end

-- The opponent row (1, 2, 3) a main-window row is, or nil.
function M:slot_of(row)
    if row == "opponent" then return 1 end
    return tonumber(row and row:match("^opponent(%d)$"))
end

function M:now_text()
    if self.picking == "round" then
        local c, r = self:course(), self:round()
        return c and ("\nNow: " .. c.name .. (r and (", round " .. tostring(r.number or self.draft.round)) or "")) or ""
    end
    local i = self.draft.group[self.slot or 1]
    if not i then return "\nNow: None" end
    return "\nNow: " .. self.lists.opponents[i].name
end

function M:meter_index(m)
    if m.visible == false then return #M.METERS end
    return index_of(M.METERS, m.meter) or 1
end

function M:index(name)
    for i, r in ipairs(self.rows) do if r == name then return i end end
    return nil
end

-- Sets draft values by id (development screenshots): { mode, opponent (the first row), opponent1..3 (an id, or "none"
-- for the second and third), count = n, round = id, behaviour = id, difficulty = id, meter = id } (any of them).
function M:set(values)
    local d, l = self.draft, self.lists
    if values.opponent then values.opponent1 = values.opponent1 or values.opponent end
    for s = 1, M.SLOTS do
        local v = values["opponent" .. s]
        if v and s <= (self.slots or 1) then
            if v == "none" and s > 1 then d.group[s] = false
            else d.group[s] = index_of(l.opponents, v) or d.group[s] end
        end
    end
    self:compact()
    if values.count then d.count = math.max(1, math.min(tonumber(values.count) or d.count, l.max_count or 3)) end
    if values.behaviour then d.behaviour = index_of(l.behaviours, values.behaviour) or d.behaviour end
    if values.difficulty then d.difficulty = index_of(l.difficulties, values.difficulty) or d.difficulty end
    if values.meter and d.meter then d.meter = index_of(M.METERS, values.meter) or d.meter end
    if values.round and self.round_index[values.round] then
        local at = self.round_index[values.round]
        d.course, d.round = at.course, at.round
    end
    if values.mode and self:has_rounds() and index_of(M.MODES, values.mode) then d.mode = values.mode end
    self:build_rows()
end

-- A group has no gaps: None in Opponent 2 with Opponent 3 set moves Opponent 3 up.
function M:compact()
    local g, out = self.draft.group, {}
    for s = 1, M.SLOTS do if g[s] then out[#out + 1] = g[s] end end
    self.draft.group = out
end

-- How many times opponent index i is in the group, leaving out row skip.
function M:copies(i, skip)
    local n = 0
    for s, g in ipairs(self.draft.group) do if g == i and s ~= skip then n = n + 1 end end
    return n
end

-- A setting's values ({ { id, name } }) and the draft's index into them; nil for rows without values.
function M:values(row)
    local d, l = self.draft, self.lists
    if row == "mode" then return M.MODES, index_of(M.MODES, d.mode)
    elseif row == "count" then
        local t = {}
        for n = 1, self:max_count() do t[n] = { id = n, name = tostring(n) } end
        return t, self:count()
    elseif row == "behaviour" then return l.behaviours, d.behaviour
    elseif row == "difficulty" and #l.difficulties > 0 then return l.difficulties, d.difficulty
    elseif row == "meter" and d.meter then return M.METERS, d.meter
    end
    return nil
end

function M:value(row)
    local slot = self:slot_of(row)
    if slot then
        local i = self.draft.group[slot]
        return i and self:marked(self.lists.opponents[i].name, self.lists.opponents[i]) or "None"
    end
    if row == "round" then
        local c, r = self:course(), self:round()
        if not c then return "None" end
        local tail = r and (" - Round " .. tostring(r.number or self.draft.round) .. (self:fits(r) and "" or M.MARK)) or ""
        return short(self.short_course[self.draft.course], M.MAIN_CHARS - #M.LABELS.round - 4 - #tail) .. tail
    end
    local list, i = self:values(row)
    return list and list[i] and list[i].name or nil
end

-- One row's text: "Opponent:   Deathclaw" for the settings, the plain label for the rest.
function M:row_text(row)
    local v = self:value(row)
    if not v then return M.LABELS[row] end
    return M.LABELS[row] .. ":   " .. v
end

function M:row_texts()
    local t = {}
    for i, row in ipairs(self.rows) do t[i] = self:row_text(row) end
    return t
end

local function same_list(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- What the draft changes, as ct_api.apply wants it (only what differs from the state the menu opened on; on a change of
-- mode, the mode's own setting too).
function M:changes()
    local d, l, s = self.draft, self.lists, self.state
    local c = {}
    local mode_was = (s.mode == "round") and "round" or "opponents"
    if self:has_rounds() and d.mode ~= mode_was then c.mode = d.mode end
    if d.mode == "round" then
        local r = self:round()
        if r and (r.id ~= s.round or c.mode) then c.round = r.id end
    elseif self.slots then
        local ids, was = {}, {}
        for k, i in ipairs(d.group) do ids[k] = l.opponents[i].id end
        for k, i in ipairs(self:state_group(s)) do was[k] = l.opponents[i].id end
        if not same_list(ids, was) or c.mode then c.group = ids end
    else
        local o = self:opponent()
        if o.id ~= s.opponent then c.opponent = o.id end
        if self:count() ~= tonumber(s.count) then c.count = self:count() end
    end
    local b = l.behaviours[d.behaviour].id
    if b ~= s.behaviour then c.behaviour = b end
    local df = l.difficulties[d.difficulty]
    if df and df.id ~= s.difficulty then c.difficulty = df.id end
    return c
end

-- What the draft asks of the meters (meters_api.act actions, in order), from the meter row.
function M:meter_actions()
    if not self.meters or not self.draft.meter then return {} end
    local was, now = self:meter_index(self.meters), self.draft.meter
    if was == now then return {} end
    local id = M.METERS[now].id
    if id == "hidden" then return { "hide" } end
    local out = { "meter=" .. id }
    if self.meters.visible == false then out[2] = "show" end
    return out
end

function M:ranges(sec) return split(sec.members, M.PAGE) end

-- The section, range and place in it of the picking row's opponent, else of the nearest row above it with one (a new
-- row starts where the last pick was, so another copy is a few confirms away).
function M:where()
    local i
    for s = (self.slot or 1), 1, -1 do
        i = self.draft.group[s]
        if i then break end
    end
    for s, sec in ipairs(self.sections) do
        for r, part in ipairs(self:ranges(sec)) do
            for n, m in ipairs(part) do
                if m == i then return s, r, n end
            end
        end
    end
    return 1, 1, 1
end

-- Whether the picking row may be None (the second and third opponent rows).
function M:offers_none() return (self.slot or 1) > 1 end

local function with_back(options) options[#options + 1] = "Back"; return options end

function M:take_notice()
    local n = self.notice
    self.notice = nil
    return n and ("\n" .. n) or ""
end

-- The window for the current screen: { screen, body, options, focus } (focus: the row to put the cursor on, 1-based).
function M:window()
    local screen = self.screen
    if screen == "main" then
        local stage = self:stage_name()
        return { screen = screen, options = self:row_texts(), focus = self.row,
                 body = "Custom Training" .. self:cleared_text() .. (stage and ("\nStage: " .. stage) or "")
                     .. "\n<button=decide> Change a setting, then Apply" }
    elseif screen == "values" then
        local list, i = self:values(self.value_row)
        local options = {}
        for n, v in ipairs(list) do options[n] = v.name end
        -- The game's window can't be told where to put its cursor (2026-11-21), so the text says which value is set.
        local now = list[i] and ("\nNow: " .. list[i].name) or ""
        return { screen = screen, body = M.LABELS[self.value_row] .. now, options = with_back(options), focus = i }
    elseif screen == "sections" then
        local options = {}
        for n, sec in ipairs(self.sections) do options[n] = sec.label end
        if self:offers_none() then options[#options + 1] = "None" end
        return { screen = screen, body = M.LABELS[self.slot_row] .. ": kind of enemy" .. self:now_text(),
                 options = with_back(options), focus = (self:where()) }
    elseif screen == "ranges" then
        local sec = self.sections[self.section]
        local options = {}
        for n, part in ipairs(self:ranges(sec)) do
            local first, last = self.lists.opponents[part[1]].name, self.lists.opponents[part[#part]].name
            options[n] = range_label(first, last)
        end
        local s, r = self:where()
        return { screen = screen, body = sec.label .. self:now_text(), options = with_back(options), focus = s == self.section and r or 1 }
    elseif screen == "names" then
        local options = {}
        local s, r, n = self:where()
        for k, idx in ipairs(self.names) do
            local o = self.lists.opponents[idx]
            options[k] = self:marked(o.name, self:pick_need(idx)) -- with the rows already filled: a group needs more
        end
        local here = s == self.section and (not self.from_ranges or r == self.range)
        return { screen = screen, body = self.sections[self.section].label .. self:now_text() .. self:take_notice(),
                 options = with_back(options), focus = here and n or 1 }
    elseif screen == "tabs" then
        local options, focus = {}, 1
        for n, t in ipairs(self.tabs) do
            options[n] = t.name
            for _, c in ipairs(t.courses) do if c == self.draft.course then focus = n end end
        end
        return { screen = screen, body = "Round: simulator tab" .. self:now_text(), options = with_back(options), focus = focus }
    elseif screen == "course_ranges" then
        local tab = self.tabs[self.tab]
        local options, focus = {}, 1
        for n, part in ipairs(split(tab.courses, M.PAGE)) do
            options[n] = range_label(self.short_course[part[1]], self.short_course[part[#part]])
            for _, c in ipairs(part) do if c == self.draft.course then focus = n end end
        end
        return { screen = screen, body = tab.name .. self:now_text(), options = with_back(options), focus = focus }
    elseif screen == "courses" then
        local options, focus = {}, 1
        for n, c in ipairs(self.course_list) do
            options[n] = short(self.lists.courses[c].name, M.ROW_CHARS)
            if c == self.draft.course then focus = n end
        end
        return { screen = screen, body = self.tabs[self.tab].name .. self:now_text(), options = with_back(options), focus = focus }
    elseif screen == "round_ranges" then
        local course = self.lists.courses[self.pick_course]
        local options, focus = {}, 1
        for n, part in ipairs(split(course.rounds, M.PAGE)) do
            options[n] = "Rounds " .. tostring(part[1].number or "?") .. " - " .. tostring(part[#part].number or "?")
            for _, r in ipairs(part) do
                if self.pick_course == self.draft.course and r == course.rounds[self.draft.round] then focus = n end
            end
        end
        return { screen = screen, body = short(course.name, M.ROW_CHARS) .. self:now_text(), options = with_back(options), focus = focus }
    elseif screen == "rounds" then
        local course = self.lists.courses[self.pick_course]
        local options, focus = {}, 1
        for n, r in ipairs(self.round_list) do
            options[n] = self:fits(r) and round_label(r) or (round_label(r, M.ROW_CHARS - #M.MARK) .. M.MARK)
            if self.pick_course == self.draft.course and course.rounds[self.draft.round] == r then focus = n end
        end
        return { screen = screen, body = short(course.name, M.ROW_CHARS) .. self:now_text() .. self:take_notice(),
                 options = with_back(options), focus = focus }
    end
end

-- Picks opponent index i for the picking row, unless it needs a larger stage, would be more copies than the opponent
-- allows, or can't be in a group with an opponent in another row: then the names window stays, saying so.
function M:pick_opponent(i)
    local o = self.lists.opponents[i]
    if not self:fits(self:pick_need(i)) then
        self.notice = self:too_big()
        return false
    end
    if self.slots and self:copies(i, self.slot) + 1 > self:max_count(o) then
        local n = self:max_count(o)
        self.notice = "At most " .. n .. " " .. o.name .. (n == 1 and " at a time" or "")
        return false
    end
    if self.slots and self.conflict[o.id] then
        for s, g in ipairs(self.draft.group) do
            local other = self.lists.opponents[g]
            if s ~= self.slot and self.conflict[o.id][other.id] then
                self.notice = o.name .. " can't fight beside " .. other.name
                return false
            end
        end
    end
    self.draft.group[self.slot] = i
    return true
end

function M:back_to_main(row)
    self.picking, self.slot = nil, nil
    self:build_rows()
    self.row, self.screen = self:index(row) or 1, "main"
end

-- The open window closed with choice (0-based index from the game; nil or negative when it was cancelled).
-- Returns { kind = "show" } (show window() next) | { kind = "apply", changes, meters } | { kind = "close" } |
-- { kind = "meters_now", action } (Clear meter, Reset stagger: act, then show window() again).
function M:choose(choice)
    local screen = self.screen
    local pos = (choice ~= nil and choice >= 0) and choice + 1 or nil
    if screen == "main" then
        if not pos then return { kind = "close" } end
        local row = self.rows[pos]
        self.row = pos
        if row == nil or row == "cancel" then return { kind = "close" } end
        if row == "apply" then return { kind = "apply", changes = self:changes(), meters = self:meter_actions() } end
        if row == "respawn" then return { kind = "respawn" } end -- at once, closing the menu; the draft is dropped
        if row == "clear" or row == "stagger" then return { kind = "meters_now", action = row } end
        local slot = self:slot_of(row)
        if slot then
            -- The third row while the second is None is picked as the second: a group has no gaps.
            self.slot = math.min(slot, #self.draft.group + 1)
            self.slot_row = self.slots and ("opponent" .. self.slot) or row
            self.picking, self.screen = "opponent", "sections"
            return { kind = "show" }
        end
        if row == "round" then self.picking, self.screen = "round", "tabs"; return { kind = "show" } end
        if row == "count" and self:max_count() <= 1 then return { kind = "show" } end -- capped at one: no list
        if self:values(row) then self.value_row, self.screen = row, "values" end
        return { kind = "show" }
    elseif screen == "values" then
        local list = self:values(self.value_row)
        local r = self.value_row
        if pos and pos <= #list then
            local d = self.draft
            if r == "count" then d.count = pos elseif r == "behaviour" then d.behaviour = pos
            elseif r == "difficulty" then d.difficulty = pos elseif r == "meter" then d.meter = pos
            elseif r == "mode" then d.mode = M.MODES[pos].id end
        end
        self:back_to_main(r)
        return { kind = "show" }
    elseif screen == "sections" then
        if pos and self:offers_none() and pos == #self.sections + 1 then -- None
            self.draft.group[self.slot] = false
            self:compact()
            self:back_to_main(self.slot_row)
            return { kind = "show" }
        end
        if not pos or pos > #self.sections then self:back_to_main(self.slot_row); return { kind = "show" } end
        self.section = pos
        local sec = self.sections[pos]
        if #sec.members <= M.PAGE then
            self.names, self.range, self.from_ranges, self.screen = sec.members, 1, false, "names"
        else
            self.screen = "ranges"
        end
        return { kind = "show" }
    elseif screen == "ranges" then
        local parts = self:ranges(self.sections[self.section])
        if not pos or pos > #parts then self.screen = "sections"; return { kind = "show" } end
        self.names, self.range, self.from_ranges, self.screen = parts[pos], pos, true, "names"
        return { kind = "show" }
    elseif screen == "names" then
        if pos and pos <= #self.names then
            if self:pick_opponent(self.names[pos]) then self:back_to_main(self.slot_row) end
        else
            self.screen = self.from_ranges and "ranges" or "sections"
        end
        return { kind = "show" }
    elseif screen == "tabs" then
        if not pos or pos > #self.tabs then self:back_to_main("round"); return { kind = "show" } end
        self.tab = pos
        local tab = self.tabs[pos]
        if #tab.courses > M.PAGE then self.screen = "course_ranges"
        else self.course_list, self.courses_from_ranges, self.screen = tab.courses, false, "courses" end
        return { kind = "show" }
    elseif screen == "course_ranges" then
        local parts = split(self.tabs[self.tab].courses, M.PAGE)
        if not pos or pos > #parts then self.screen = "tabs"; return { kind = "show" } end
        self.course_list, self.courses_from_ranges, self.screen = parts[pos], true, "courses"
        return { kind = "show" }
    elseif screen == "courses" then
        if not pos or pos > #self.course_list then
            self.screen = self.courses_from_ranges and "course_ranges" or "tabs"
            return { kind = "show" }
        end
        self.pick_course = self.course_list[pos]
        local rounds = self.lists.courses[self.pick_course].rounds or {}
        if #rounds > M.PAGE then self.screen = "round_ranges"
        else self.round_list, self.rounds_from_ranges, self.screen = rounds, false, "rounds" end
        return { kind = "show" }
    elseif screen == "round_ranges" then
        local parts = split(self.lists.courses[self.pick_course].rounds, M.PAGE)
        if not pos or pos > #parts then self.screen = "courses"; return { kind = "show" } end
        self.round_list, self.rounds_from_ranges, self.screen = parts[pos], true, "rounds"
        return { kind = "show" }
    elseif screen == "rounds" then
        if pos and pos <= #self.round_list and not self:fits(self.round_list[pos]) then
            self.notice = self:too_big() -- the rounds window stays, saying why
        elseif pos and pos <= #self.round_list then
            local at = self.round_index[self.round_list[pos].id]
            self.draft.course, self.draft.round = at.course, at.round
            self:back_to_main("round")
        else
            self.screen = self.rounds_from_ranges and "round_ranges" or "courses"
        end
        return { kind = "show" }
    end
    return { kind = "close" }
end

return M
