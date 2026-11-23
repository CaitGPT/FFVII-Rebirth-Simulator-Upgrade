-- What the panel shows, as a plain table (tested offline); meters_overlay.lua draws it. Training Dummy's panel
-- (course header, timer, key hints, member rows with bars) and Battle Meters' (character colours, Unattributed,
-- MP rows), as one.
local controls = require("meters_controls")

local M = {}

M.MAX_ROWS = 5                 -- a party of four at most, plus Unattributed
M.MAX_SUBTITLE = 44            -- Latin characters (a full-width one counts two); longer setups are cut with "..."

-- Battle Meters' colours, in its order (meter_view.lua). Black Tifa is drawn with an edge.
M.CHARACTERS = {
    { name = "Cloud", color = { R = 1.00, G = 0.85, B = 0.10, A = 1 } },
    { name = "Barret", color = { R = 0.10, G = 0.65, B = 0.20, A = 1 } },
    { name = "Tifa", color = { R = 0, G = 0, B = 0, A = 1 } },
    { name = "Aerith", color = { R = 1.00, G = 0.45, B = 0.72, A = 1 } },
    { name = "Red XIII", color = { R = 0.85, G = 0.08, B = 0.08, A = 1 } },
    { name = "Yuffie", color = { R = 0.10, G = 0.35, B = 1.00, A = 1 } },
    { name = "Cait Sith", color = { R = 1, G = 1, B = 1, A = 1 } },
    { name = "Zack", color = { R = 0.40, G = 0.95, B = 1.00, A = 1 } },
    { name = "Sephiroth", color = { R = 0.60, G = 0.30, B = 0.90, A = 1 } },
    { name = "Vincent", color = { R = 0.45, G = 0.05, B = 0.15, A = 1 } },
    { name = "Cid", color = { R = 1.00, G = 0.55, B = 0.10, A = 1 } },
}
M.OTHER = { R = 0.55, G = 0.60, B = 0.65, A = 1 }
M.UNATTRIBUTED = "Unattributed"
local COLOR = {}
for _, c in ipairs(M.CHARACTERS) do COLOR[c.name] = c.color end

local BIGGEST = { damage = "Biggest hit", taken = "Biggest hit taken", heal = "Biggest heal" }
local UNIT = { damage = "Damage per second", taken = "Damage taken per second", heal = "Healing per second" }
local BEHAVIOUR = { passive = "Passive", aggressive = "Aggressive", healing = "Healing" }

function M.format_number(value)
    local text = tostring(math.floor((value or 0) + 0.5))
    local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (grouped:gsub("^,", ""))
end

function M.format_time(seconds)
    local whole = math.floor(seconds or 0)
    if whole >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(whole / 3600), math.floor(whole / 60) % 60, whole % 60)
    end
    return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

-- Text as UTF-8 (opponent names come in the game's language): control characters out, and bytes that aren't UTF-8
-- dropped, so the text can be measured and cut by characters.
local function clean(text)
    text = tostring(text or ""):gsub("%c", "")
    if utf8.len(text) then return text end
    local good = {}
    local i = 1
    while i <= #text do
        local c = text:byte(i)
        local n = c < 0x80 and 1 or c >= 0xF0 and 4 or c >= 0xE0 and 3 or c >= 0xC2 and 2 or 0
        local piece = n > 0 and text:sub(i, i + n - 1) or ""
        if n > 0 and #piece == n and utf8.len(piece) then good[#good + 1] = piece; i = i + n else i = i + 1 end
    end
    return table.concat(good)
end

-- Width in the panel, in Latin characters: CJK and other full-width characters take two.
local function wide(cp) return cp >= 0x1100 and (cp <= 0x115F or (cp >= 0x2E80 and cp <= 0xA4CF)
    or (cp >= 0xAC00 and cp <= 0xD7A3) or (cp >= 0xF900 and cp <= 0xFAFF) or (cp >= 0xFE30 and cp <= 0xFE4F)
    or (cp >= 0xFF00 and cp <= 0xFF60) or (cp >= 0xFFE0 and cp <= 0xFFE6)) end
function M.text_width(text)
    local w = 0
    for _, cp in utf8.codes(text) do w = w + (wide(cp) and 2 or 1) end
    return w
end

-- Cut to a width, whole characters only, with "..." when anything was cut.
function M.cut(text, room)
    if M.text_width(text) <= room then return text end
    local w, last = 0, 0
    for p, cp in utf8.codes(text) do
        local cw = wide(cp) and 2 or 1
        if w + cw > room - 3 then break end
        w, last = w + cw, utf8.offset(text, 2, p) - 1
    end
    return (text:sub(1, last):gsub("[%s,]+$", "")) .. "..."
end

-- "Bomb ×3, Passive", "Tonberry King, Mindflayer, Bomb, Aggressive", "Brutal: … · Round 1, Healing": Custom Training's
-- own words for the setup (state().setup: a group's members, copies as "×N", a round by its course), cut to fit, never
-- the behaviour. Without them (an older Custom Training) the first opponent and the count.
function M.subtitle(course)
    if not course or course.active ~= true then return "Custom Training" end
    local tail = BEHAVIOUR[course.behaviour] and (", " .. BEHAVIOUR[course.behaviour]) or ""
    local name = clean(course.setup)
    if name == "" then
        name = clean(course.name)
        local count = tonumber(course.count)
        if name ~= "" and count and count > 1 then name = name .. " ×" .. count end
    end
    if name == "" then return "Custom Training" .. tail end
    -- A round keeps its number ("… · Round 1", Custom Training's words): the course name is what gets cut.
    local head, round = name:match("^(.-)(%s*\194\183%s*%S+%s+%d+)$")
    if head and head ~= "" then tail = round .. tail; name = head end
    return M.cut(name, M.MAX_SUBTITLE - M.text_width(tail)) .. tail
end

-- "Wave 3   Last clear 1:23": Custom Training's waves, nil without them. Only Aggressive has real conditions (owner,
-- 2026-11-21: enemies die and stay dead until a respawn); elsewhere enemies refill, so the line shows only once a wave
-- has really been cleared.
function M.wave(course)
    local wave = course and course.active == true and tonumber(course.wave)
    if not wave or wave < 1 then return nil end   -- 0: the first spawn is still coming
    local clear = tonumber(course.last_clear)
    if course.behaviour ~= "aggressive" and not clear then return nil end
    return string.format("Wave %d", wave) .. (clear and ("   Last clear " .. M.format_time(clear)) or "")
end

-- The rows: the party in battle-slot order (everyone, at 0 too), then anyone else credited, then Unattributed.
local function rows_of(kind, k, party, elapsed)
    local rows, listed = {}, {}
    local function add(name, amount)
        if #rows >= M.MAX_ROWS or listed[name] then return end
        listed[name] = true
        amount = amount or 0
        rows[#rows + 1] = { name = name, color = COLOR[name] or M.OTHER, total = M.format_number(amount),
            rate = M.format_number(elapsed > 0 and amount / math.max(elapsed, 1) or 0),
            share = k.total > 0 and amount / k.total or 0, amount = amount }
    end
    local by = k.by_source or {}
    for _, name in ipairs(party or {}) do add(name, by[name]) end
    local others = {}
    for name in pairs(by) do if not listed[name] and name ~= M.UNATTRIBUTED then others[#others + 1] = name end end
    table.sort(others)
    for _, name in ipairs(others) do add(name, by[name]) end
    if (by[M.UNATTRIBUTED] or 0) >= 0.5 then add(M.UNATTRIBUTED, by[M.UNATTRIBUTED]) end
    return rows
end

-- What the rows can't say yet, as a short note under them.
local function note_of(kind, k, snapshot)
    if kind == "damage" and not k.attributed then
        return k.total > 0 and "By character: needs the meters helper (native)" or nil
    end
    if kind == "heal" and not k.attributed then return "Healing shown by who received it" end
    return nil
end

-- snapshot: meters_tracker's; meter: "damage" | "taken" | "heal"; course: Custom Training's state; settings: the
-- panel's. Returns the view.
function M.build(snapshot, meter, course, settings)
    local k = snapshot.kinds[meter]
    local elapsed = snapshot.elapsed or 0
    local tabs = {}
    for _, m in ipairs(controls.METERS) do tabs[#tabs + 1] = { text = controls.LABELS[m], current = m == meter } end
    local stats = {
        { string.format("Last %d seconds", settings.window or 5), M.format_number(k.recent) },
        { "Total", M.format_number(k.total) },
        { BIGGEST[meter], M.format_number(k.biggest) },
    }
    if meter == "taken" then
        stats[#stats + 1] = { "Damage dealt per second", M.format_number(snapshot.kinds.damage.average) }
    elseif meter == "heal" then
        local mp = snapshot.kinds.mp and snapshot.kinds.mp.total or 0
        stats[#stats + 1] = { "MP spent", M.format_number(mp) }
        stats[#stats + 1] = { "Healing per MP", mp > 0 and M.format_number(k.total / mp) or "-" }
    end
    local show_rows = meter ~= "damage" or k.attributed == true
    local rows = show_rows and rows_of(meter, k, snapshot.party, elapsed) or {}
    return {
        tabs = tabs,
        timer = M.format_time(elapsed),
        subtitle = M.subtitle(course),
        wave = M.wave(course),
        unit = UNIT[meter],
        value = M.format_number(k.average),
        stats = stats,
        rows = rows,
        note = note_of(meter, k, snapshot),
        hint = string.format("%s Meter   %s Clear   %s Stagger   %s Hide", settings.next_key, settings.clear_key,
            settings.stagger_key, settings.toggle_key),
        pad_hint = "Pad: LB+RB, then Meters",
    }
end

return M
