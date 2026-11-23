-- Custom Training's settings, as the menu sees them: active(), state(), lists(), apply(changes).
-- In the integrated mod this is Custom Training's own ct_api (one Lua state). During development the two mods are
-- separate Lua states, so a bridge reads and writes Custom Training's development files instead (dev.txt in its folder):
--   ct-course.txt   its state, rewritten on every start, end and change (key=value lines)
--   ct-lists.txt    its lists (tab-separated lines: opponent, behaviour, difficulty, max_count; with mixed groups
--                   group_max and conflict; with pre-built rounds course and round), written at each start and on the
--                   "lists" command
--   ct-command.txt  one command for it: "set opponent=ID count=N behaviour=B difficulty=D" (or group=ID,ID,ID,
--                   mode=opponents|round, round=ID) applies through ct_api, "lists" asks for ct-lists.txt
-- The parsing is game-free and tested offline.
local M = {}

function M.parse_state(text)
    if not text or text == "" then return nil end
    local s = {}
    for line in text:gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k then
            if v == "true" then v = true elseif v == "false" then v = false
            elseif v == "nil" then v = nil
            elseif tonumber(v) then v = tonumber(v) end
            s[k] = v
        end
    end
    if s.what == "end" then s.active = false end
    -- group=ID1,ID2,ID3: the opponents in row order.
    if s.group ~= nil then
        local g = {}
        for id in tostring(s.group):gmatch("[^,%s]+") do g[#g + 1] = id end
        s.group = g
    end
    return s
end

local KIND_NAMES = { "Humans", "Machines", "Beasts", "Anomalies", "Summons and others" }

function M.parse_lists(text)
    if not text or text == "" then return nil end
    local l = { opponents = {}, behaviours = {}, difficulties = {}, max_count = 3 }
    local courses = {}
    for line in text:gmatch("[^\r\n]+") do
        local f = {}
        for field in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
        if f[1] == "opponent" and #f >= 6 then
            l.opponents[#l.opponents + 1] = { id = f[2], kind = tonumber(f[3]) or 5, kind_name = f[4] ~= "" and f[4] or nil,
                                              max_count = tonumber(f[5]), name = f[6], needs_m = tonumber(f[7]) }
        elseif f[1] == "behaviour" and #f >= 3 then l.behaviours[#l.behaviours + 1] = { id = f[2], name = f[3] }
        elseif f[1] == "difficulty" and #f >= 3 then l.difficulties[#l.difficulties + 1] = { id = f[2], name = f[3] }
        elseif f[1] == "max_count" then l.max_count = tonumber(f[2]) or 3
        elseif f[1] == "group_max" or f[1] == "max_group" then l.group_max = tonumber(f[2])
        elseif f[1] == "conflict" and #f >= 3 then
            l.conflicts = l.conflicts or {}
            l.conflicts[#l.conflicts + 1] = { f[2], f[3] }
        elseif f[1] == "course" and #f >= 5 then
            -- course, id, tab, tab name, the game's course title (agreed with custom-training, 2026-11-21).
            l.courses = l.courses or {}
            local c = { id = f[2], tab = f[3], tab_name = f[4] ~= "" and f[4] or nil, name = f[5], rounds = {} }
            l.courses[#l.courses + 1] = c
            courses[c.id] = c
        elseif f[1] == "round" and #f >= 7 then
            -- round, course id, round id, number, size, name ("Round 1"), enemies ("Wererat ×2, Elphadunk ×2"), and the
            -- room it needs (metres; empty: any stage).
            local c = courses[f[2]]
            if c then
                c.rounds[#c.rounds + 1] = { id = f[3], number = tonumber(f[4]) or f[4], size = tonumber(f[5]),
                                            name = f[6] ~= "" and f[6] or nil, enemies = f[7], needs_m = tonumber(f[8]) }
            end
        end
    end
    if #l.opponents == 0 or #l.behaviours == 0 then return nil end
    for _, o in ipairs(l.opponents) do o.kind_name = o.kind_name or KIND_NAMES[o.kind] end
    return l
end

function M.format_set(changes)
    local keys = {}
    for k in pairs(changes) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        local v = changes[k]
        if type(v) == "table" then v = table.concat(v, ",") end -- group: ID1,ID2,ID3
        parts[#parts + 1] = k .. "=" .. tostring(v)
    end
    return "set " .. table.concat(parts, " ") .. "\n"
end

-- Lists made here from Custom Training's catalogue, for a development install whose Custom Training doesn't write
-- ct-lists.txt yet: every catalogued opponent, named by the game (lookup), sorted by kind, then name.
function M.lists_from_catalogue(catalogue, lookup)
    local list = {}
    for _, o in ipairs(catalogue.opponents or {}) do
        local name = lookup and lookup(o.label) or nil
        if not name then
            local words = (o.spec or o.id):match("^%u%u%d+_%d+_(.+)$") or o.id
            name = words:gsub("End2", ""):gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
        end
        list[#list + 1] = { id = o.id, kind = o.category or 5, kind_name = KIND_NAMES[o.category or 5], max_count = tonumber(o.cap), name = name }
    end
    local count = {}
    for _, e in ipairs(list) do count[e.name] = (count[e.name] or 0) + 1 end
    for _, e in ipairs(list) do
        if count[e.name] > 1 then
            local variant = e.id:gsub("^mobcolvr_", ""):match("^%u%u%d+_%d+_[^_]+_(.-)_?%d*$") or ""
            variant = variant:gsub("End2$", ""):gsub("(%l)(%u)", "%1 %2")
            if variant ~= "" then e.name = e.name .. " (" .. variant .. ")" end
        end
    end
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return {
        opponents = list,
        behaviours = { { id = "passive", name = "Passive" }, { id = "aggressive", name = "Aggressive" }, { id = "healing", name = "Healing" } },
        difficulties = { { id = "easy", name = "Easy" }, { id = "normal", name = "Normal" }, { id = "dynamic", name = "Dynamic" }, { id = "hard", name = "Hard" } },
        max_count = 3,
    }
end

-- The integrated mod: Custom Training's own module.
function M.direct(api)
    return {
        kind = "ct_api",
        active = function() return api.active() end,
        state = function() return api.state() end,
        lists = function() return api.lists() end,
        apply = function(changes) return api.apply(changes) end,
        respawn = api.respawn and function() return api.respawn() end or nil,
        poll = function() end,
    }
end

-- Development: the bridge. io = { read(path) -> text or nil, write(path, text) -> bool, exists(path) -> bool },
-- ct_dir: Custom Training's mod folder (with the trailing slash), log(message), lookup(key) -> text or nil.
function M.bridge(ct_dir, io, log, lookup)
    local self = { kind = "bridge", queue = {}, lists_cache = nil, asked_lists = false }
    local function send(text)
        self.queue[#self.queue + 1] = text
    end
    function self.poll()
        -- One command at a time: Custom Training removes the file when it has read it.
        if #self.queue > 0 and not io.exists(ct_dir .. "ct-command.txt") then
            local text = table.remove(self.queue, 1)
            local ok = io.write(ct_dir .. "ct-command.txt", text)
            log("bridge\tsent\t" .. text:gsub("%s+$", "") .. "\t" .. tostring(ok))
        end
    end
    function self.state() return M.parse_state(io.read(ct_dir .. "ct-course.txt")) or { active = false } end
    function self.active() return self.state().active == true end
    function self.lists()
        local l = M.parse_lists(io.read(ct_dir .. "ct-lists.txt"))
        if l then self.lists_cache = l; return l end
        if not self.asked_lists then self.asked_lists = true; send("lists\n") end
        if self.lists_cache then return self.lists_cache end
        -- Not written (yet): Custom Training's catalogue, read from its folder.
        local ok, catalogue = pcall(dofile, ct_dir .. "Scripts/ct_catalogue.lua")
        if ok and type(catalogue) == "table" then
            self.lists_cache = M.lists_from_catalogue(catalogue, lookup)
            log("bridge\tlists from the catalogue (" .. #self.lists_cache.opponents .. " opponents)")
            return self.lists_cache
        end
        return nil
    end
    -- Respawn: one command line, "respawn".
    function self.respawn()
        send("respawn\n")
        self.poll()
        return true
    end
    function self.apply(changes)
        if next(changes) == nil then return true end
        send(M.format_set(changes))
        self.poll()
        return true
    end
    return self
end

return M
