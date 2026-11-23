-- The settings panel, without the game (owner's mock-up, 2026-11-20): four sections, Enemy type, Behaviour,
-- Difficulty and Quantity, stacked on the left of the screen. Up and down move between sections; left and right
-- cycle the focused section's value; the enemy section also jumps by kind. Select applies every change at once, Back
-- closes without changing anything. ct_panel.lua draws view(); ct_session.lua feeds it keys. Tested offline.
-- With the meters part present (options.meters), two more sections: the meter shown (Damage, Tanking, Healing or
-- Hidden) and a meter tool (Clear meter, Reset stagger), sent to meters on Select as its act() commands.
local M = {}
M.__index = M

M.SECTIONS = { "enemy", "behaviour", "difficulty", "quantity" }
M.METER_SECTIONS = { "meter", "tool" }
M.TITLES = { enemy = "ENEMY TYPE", behaviour = "BEHAVIOUR", difficulty = "DIFFICULTY", quantity = "QUANTITY",
             meter = "METER", tool = "METER TOOLS" }
M.METERS = { "damage", "taken", "heal", "hidden" } -- meters' own names, and hidden
M.METER_LABELS = { damage = "Damage", taken = "Tanking", heal = "Healing", hidden = "Hidden" }
M.TOOLS = { "none", "clear", "stagger" }
M.TOOL_LABELS = { none = "—", clear = "Clear meter", stagger = "Reset stagger" }
M.BEHAVIOURS = { "passive", "aggressive", "healing" }
M.BEHAVIOUR_LABELS = { passive = "Passive", aggressive = "Aggressive", healing = "Healing" }
M.DIFFICULTIES = { "easy", "normal", "dynamic", "hard" }
M.DIFFICULTY_LABELS = { easy = "Easy", normal = "Normal", dynamic = "Dynamic", hard = "Hard" }
M.KINDS = { "Humans", "Machines", "Beasts", "Anomalies", "Summons and others" }
M.MAX_COUNT = 3

local function index_of(list, value)
    for i, v in ipairs(list) do if v == value then return i end end
    return 1
end

local function wrap(i, n) return ((i - 1) % n) + 1 end

-- list: the opponents offered, { id, category (1-5), name }, in any order; they are shown by kind, then name.
-- options: { difficulties = set of allowed difficulty names or nil for all }
function M.new(list, options)
    local sorted = {}
    for _, e in ipairs(list) do sorted[#sorted + 1] = e end
    table.sort(sorted, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    local self = setmetatable({ list = sorted, options = options or {}, open = false, section = 1 }, M)
    self.sections = {}
    for _, k in ipairs(M.SECTIONS) do self.sections[#self.sections + 1] = k end
    if self.options.meters then
        for _, k in ipairs(M.METER_SECTIONS) do self.sections[#self.sections + 1] = k end
    end
    self.difficulties = {}
    for _, d in ipairs(M.DIFFICULTIES) do
        if not self.options.difficulties or self.options.difficulties[d] then self.difficulties[#self.difficulties + 1] = d end
    end
    return self
end

-- Opens on the current settings; the draft changes until Select. meter: meters' state() when it is there
-- ({ meter = "damage" | "taken" | "heal", visible = bool }).
function M:show(settings, meter)
    local enemy = 1
    for i, e in ipairs(self.list) do if e.id == settings.opponent then enemy = i end end
    self.draft = { enemy = enemy, behaviour = settings.behaviour, difficulty = settings.difficulty, count = settings.count }
    self.meter_was = "damage"
    if meter then
        self.meter_was = meter.visible == false and "hidden" or (M.METER_LABELS[meter.meter] and meter.meter) or "damage"
    end
    self.draft.meter, self.draft.tool = self.meter_was, "none"
    self.open, self.section = true, 1
end

function M:hide() self.open = false end

function M:cycle(dir)
    local s, d = self.sections[self.section], self.draft
    if s == "enemy" then
        d.enemy = wrap(d.enemy + dir, #self.list)
    elseif s == "behaviour" then
        d.behaviour = M.BEHAVIOURS[wrap(index_of(M.BEHAVIOURS, d.behaviour) + dir, #M.BEHAVIOURS)]
    elseif s == "difficulty" then
        d.difficulty = self.difficulties[wrap(index_of(self.difficulties, d.difficulty) + dir, #self.difficulties)]
    elseif s == "meter" then
        d.meter = M.METERS[wrap(index_of(M.METERS, d.meter) + dir, #M.METERS)]
    elseif s == "tool" then
        d.tool = M.TOOLS[wrap(index_of(M.TOOLS, d.tool) + dir, #M.TOOLS)]
    else
        local cur = self.list[d.enemy]
        d.count = wrap(math.min(d.count, (cur and cur.max_count) or M.MAX_COUNT) + dir, (cur and cur.max_count) or M.MAX_COUNT)
    end
end

-- The first opponent of the next (dir 1) or previous (dir -1) kind.
function M:jump_kind(dir)
    local d = self.draft
    local kind = self.list[d.enemy].category
    local i = d.enemy
    for _ = 1, #self.list do
        i = wrap(i + dir, #self.list)
        if self.list[i].category ~= kind then
            if dir < 0 then -- to the start of that kind
                local k = self.list[i].category
                while self.list[wrap(i - 1, #self.list)].category == k and wrap(i - 1, #self.list) ~= d.enemy do
                    i = wrap(i - 1, #self.list)
                end
            end
            d.enemy = i
            return
        end
    end
end

-- A key: "up", "down", "left", "right", "next_kind", "prev_kind", "select", "back".
-- Returns nil, or { kind = "apply", changes = { key = value }, meters = { act() commands } } or { kind = "close" }.
function M:press(key, settings)
    if not self.open then return nil end
    if key == "up" then self.section = wrap(self.section - 1, #self.sections)
    elseif key == "down" then self.section = wrap(self.section + 1, #self.sections)
    elseif key == "left" then self:cycle(-1)
    elseif key == "right" then self:cycle(1)
    elseif key == "next_kind" then self.section = 1; self:jump_kind(1)
    elseif key == "prev_kind" then self.section = 1; self:jump_kind(-1)
    elseif key == "back" then self.open = false; return { kind = "close" }
    elseif key == "select" then
        self.open = false
        local d, changes = self.draft, {}
        local id = self.list[d.enemy] and self.list[d.enemy].id
        if id and id ~= settings.opponent then changes.opponent = id end
        if d.behaviour ~= settings.behaviour then changes.behaviour = d.behaviour end
        if d.difficulty ~= settings.difficulty then changes.difficulty = d.difficulty end
        if d.count ~= settings.count then changes.count = d.count end
        local meters = {}
        if d.meter ~= self.meter_was then
            if d.meter == "hidden" then meters[1] = "hide"
            else meters[1] = "meter=" .. d.meter; meters[2] = "show" end
        end
        if d.tool ~= "none" then meters[#meters + 1] = d.tool end
        return { kind = "apply", changes = changes, meters = meters }
    end
    return nil
end

-- What to draw: sections, each { key, title, focused, cells = { { text, selected } }, note }, and the footer.
function M:view()
    local d, sections = self.draft, {}
    local function section(i, cells, note)
        local key = self.sections[i]
        sections[#sections + 1] = { key = key, title = M.TITLES[key], focused = self.section == i, cells = cells, note = note }
    end
    local n = #self.list
    local cur = self.list[d.enemy]
    local prev, nxt = self.list[wrap(d.enemy - 1, n)], self.list[wrap(d.enemy + 1, n)]
    section(1, { { text = prev.name }, { text = cur.name, selected = true }, { text = nxt.name } },
        string.format("%s  ·  %d / %d", M.KINDS[cur.category] or "", d.enemy, n))
    local b = {}
    for _, v in ipairs(M.BEHAVIOURS) do b[#b + 1] = { text = M.BEHAVIOUR_LABELS[v], selected = v == d.behaviour } end
    section(2, b)
    local df = {}
    for _, v in ipairs(self.difficulties) do df[#df + 1] = { text = M.DIFFICULTY_LABELS[v], selected = v == d.difficulty } end
    section(3, df)
    -- Any opponent 1 to 3; one capped in the catalogue (shown to break with more) shows its cap and no choice.
    section(4, { { text = tostring(math.min(d.count, (cur and cur.max_count) or M.MAX_COUNT)), selected = true } })
    if self.options.meters then
        local m, t = {}, {}
        for _, v in ipairs(M.METERS) do m[#m + 1] = { text = M.METER_LABELS[v], selected = v == d.meter } end
        section(5, m)
        for _, v in ipairs(M.TOOLS) do t[#t + 1] = { text = M.TOOL_LABELS[v], selected = v == d.tool } end
        section(6, t, "Used on Apply")
    end
    -- Both devices, everything (owner 2026-11-21): pad first, then keyboard.
    local footer = "D-pad / Arrows  Move     A / Enter  Apply     B / Esc  Close     X Y / Q E  Kind"
    return { sections = sections, footer = footer }
end

return M
