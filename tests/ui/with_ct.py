"""The menu against Custom Training's own ct_api and its whole catalogue, offline (no game): every window the menu can
show for the real lists (at most 13 rows, no list row longer than a row holds), every round chosen and applied, and the
menu's refusals of groups (copies past a cap, clashing adds) matching ct_api.apply's, for every opponent pair and many
triples.

    python tests/ui/with_ct.py [custom-training Scripts folder]

The default is this checkout's ue4ss/SimOverhaulCustomTraining/Scripts. Without groups and rounds there (a Custom
Training from before 2026-11-21), it says so and passes.
"""
import pathlib
import sys

from lupa import lua54

ROOT = pathlib.Path(__file__).resolve().parents[2]
UI = ROOT / "ue4ss" / "SimOverhaulUI" / "Scripts"

LUA = r"""
local session_module = require("ct_session")
local api = require("ct_api")
local model = require("ui_model")
local catalogue = dofile(CT_DIR .. "/ct_catalogue.lua")
if not catalogue.courses then return "no courses in this Custom Training: skipped" end
-- The native wave setter, as in the game (the integrated build has it): every catalogued opponent is listed.
_G.CustomTrainingSetWave = function() return true end
_G.CustomTrainingFindWaves = function() return "found" end

local game = setmetatable({
    enemies = function() return {} end, lookup = function() return nil end, keys_down = function() return {} end,
    party = function() return {} end, in_battle = function() return true end, fname_index = function() return 1 end,
}, { __index = function() return function() end end })
local settings = { opponent = catalogue.opponents[1].id, count = 1, group = "", mode = "opponents", round = "",
                   behaviour = "passive", difficulty = "normal" }
local s = session_module.new({ game = game, catalogue = catalogue, settings = settings, save_settings = function() end,
                               log = function() end, clock = function() return 0 end })
api.bind(s)
s.active = true
local L = api.lists()
local state = api.state()
assert(L.group_max == 3 and #L.courses > 0, "lists() carries groups and rounds")

local windows, longest = 0, 0
local function check(w, where)
    windows = windows + 1
    assert(#w.options <= model.PAGE + 1, where .. ": " .. #w.options .. " rows")
    assert(w.focus >= 1 and w.focus <= #w.options, where .. ": focus " .. tostring(w.focus))
    if w.screen ~= "main" and w.screen ~= "names" then
        for _, o in ipairs(w.options) do
            assert(#o <= model.ROW_CHARS, where .. ": " .. o)
            if #o > longest then longest = #o end
        end
    end
    return w
end

-- Every round window, and every round chosen: the main window's Round row, and ct_api takes it.
local m = model.new(L, state, { meter = "damage", visible = true }, { respawn = api.respawn ~= nil })
assert(#check(m:window(), "main").options <= 13)
-- A Custom Training with respawn(): Respawn first, where the cursor opens.
local has_respawn = api.respawn ~= nil
if has_respawn then assert(m.rows[1] == "respawn" and m:window().focus == 1, "Respawn first: " .. tostring(m.rows[1])) end
m:set({ mode = "round" })
local rounds = 0
local rr = m:index("round") - 1
m:choose(rr)
local tabs = check(m:window(), "tabs")
for t = 1, #tabs.options - 1 do
    m:choose(t - 1)
    local function courses_window()
        local cw = check(m:window(), "tab " .. t .. " courses")
        for c = 1, #cw.options - 1 do
            m:choose(c - 1)
            local function rounds_window()
                local rw = check(m:window(), "rounds")
                for r = 1, #rw.options - 1 do
                    m:choose(r - 1) -- picked: the main window
                    local main = check(m:window(), "main after a round")
                    assert(#main.options[rr + 1] <= model.MAIN_CHARS, main.options[rr + 1])
                    local ok, why = api.apply(m:changes())
                    assert(ok, "apply " .. tostring(why))
                    rounds = rounds + 1
                    m:reset(api.state()); m:set({ mode = "round" })
                    -- back to where we were
                    m:choose(rr); m:choose(t - 1)
                    if m.screen == "course_ranges" then m:choose(CR) end
                    m:choose(c - 1)
                    if m.screen == "round_ranges" then m:choose(RR) end
                end
            end
            if m.screen == "round_ranges" then
                local n = #check(m:window(), "round ranges").options - 1
                for q = 1, n do RR = q - 1; m:choose(q - 1); rounds_window(); m:choose(-1) end
            else
                rounds_window()
            end
            m:choose(-1) -- Back: the courses
        end
    end
    if m.screen == "course_ranges" then
        local n = #check(m:window(), "course ranges").options - 1
        for p = 1, n do CR = p - 1; m:choose(p - 1); courses_window(); m:choose(-1) end
    else
        courses_window()
    end
    m:choose(-1) -- Back: the tabs
end
local all = 0
for _, c in ipairs(L.courses) do all = all + #c.rounds end
assert(rounds == all, rounds .. " of " .. all .. " rounds chosen")

-- Every kind, range and names window of the opponent rows.
m:reset(api.state())
m:set({ mode = "opponents" })
for _, row in ipairs({ "opponent1", "opponent2" }) do
    m:choose(m:index(row) - 1)
    local kinds = check(m:window(), row .. " kinds")
    for k = 1, #m.sections do
        m:choose(k - 1)
        if m.screen == "ranges" then
            local n = #check(m:window(), "ranges").options - 1
            for r = 1, n do m:choose(r - 1); check(m:window(), "names"); m:choose(-1) end
        else
            check(m:window(), "names")
        end
        m:choose(-1)
    end
    m:choose(-1)
end

-- Groups: the menu refuses what ct_api refuses (every pair, and triples of every opponent with copies and others).
local ids = {}
for i, o in ipairs(L.opponents) do ids[i] = o.id end
local here = {} -- the stage's fields in state(), while one is set
local function menu_takes(group)
    m:reset({ active = true, group = { group[1] }, behaviour = "passive", difficulty = "normal",
              stage_name = here.stage_name, room_m = here.room_m, needs_m = here.needs_m })
    for slot = 1, #group do
        m.slot = slot
        if not m:pick_opponent(m.lists_index[group[slot]]) then return false, m.notice end
    end
    return true
end
local idx = {}
for i, o in ipairs(L.opponents) do idx[o.id] = i end
m.lists_index = idx
local pairs_checked, refused, mismatch = 0, 0, {}
local function compare(group)
    local mine, why_mine = menu_takes(group)
    local theirs, why = api.apply({ group = group })
    pairs_checked = pairs_checked + 1
    if not theirs then refused = refused + 1 end
    if mine ~= (theirs and true or false) then
        mismatch[#mismatch + 1] = table.concat(group, ",") .. ": menu " .. tostring(mine) .. " (" .. tostring(why_mine)
            .. "), ct_api " .. tostring(theirs) .. " (" .. tostring(why) .. ")"
    end
end
for a = 1, #ids do
    for b = a, #ids do compare({ ids[a], ids[b] }) end
end
for a = 1, #ids do
    compare({ ids[a], ids[a], ids[a] })
    compare({ ids[a], ids[(a * 7) % #ids + 1], ids[(a * 13) % #ids + 1] })
end
assert(#mismatch == 0, #mismatch .. " mismatches, first: " .. tostring(mismatch[1]))
local plain_compared, plain_refused = pairs_checked, refused

-- On stages (Custom Training's stage_override, as stages_api would give it): the same groups, and every round, the
-- menu's marks and refusals against ct_api.apply's.
local stage_report = {}
if s.room_m then
    for _, st in ipairs({ { name = "Shinra Manor", radius_m = 13 }, { name = "Cave of the Gi", radius_m = 18 },
                          { name = "Gongaga", radius_m = 22 }, { name = "Midgar Outskirts", radius_m = 25 } }) do
        s.stage_override = st
        local sst = api.state()
        here = { stage_name = sst.stage_name, room_m = sst.room_m, needs_m = sst.needs_m or 0 }
        assert(here.room_m == st.radius_m and here.stage_name == st.name, "state() carries the stage")
        pairs_checked, refused = 0, 0
        for a = 1, #ids do
            for b = a, #ids do compare({ ids[a], ids[b] }) end
            compare({ ids[a] })
            compare({ ids[a], ids[a], ids[a] })
            compare({ ids[a], ids[(a * 7) % #ids + 1], ids[(a * 13) % #ids + 1] })
        end
        local round_refused = 0
        for _, c in ipairs(L.courses) do
            for _, r in ipairs(c.rounds) do
                m:reset({ active = true, group = { ids[1] }, behaviour = "passive", difficulty = "normal",
                          stage_name = here.stage_name, room_m = here.room_m, needs_m = here.needs_m })
                local mine = m:fits(r)
                local theirs, why = api.apply({ round = r.id })
                if not theirs then round_refused = round_refused + 1 end
                if mine ~= (theirs and true or false) then
                    mismatch[#mismatch + 1] = st.name .. " round " .. r.id .. ": menu " .. tostring(mine) .. ", ct_api " .. tostring(why)
                end
            end
        end
        assert(#mismatch == 0, #mismatch .. " mismatches, first: " .. tostring(mismatch[1]))
        stage_report[#stage_report + 1] = string.format("%s %g m: %d groups (%d refused), %d of 227 rounds refused",
            st.name, st.radius_m, pairs_checked, refused, round_refused)
    end
    s.stage_override = false
end
return string.format("%d opponents, %d courses, %d rounds applied, %d windows (longest list row %d), %d groups compared (%d refused by both)",
    #L.opponents, #L.courses, rounds, windows, longest, plain_compared, plain_refused)
    .. (has_respawn and "; Respawn first" or "")
    .. (#stage_report > 0 and ("\nagreeing on stages: " .. table.concat(stage_report, "; ")) or "")
"""


def main() -> int:
    ct_dir = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "ue4ss" / "SimOverhaulCustomTraining" / "Scripts"
    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{ct_dir.as_posix()}/?.lua;{UI.as_posix()}/?.lua;" .. package.path')
    lua.globals().CT_DIR = ct_dir.as_posix()
    try:
        print(lua.execute(LUA))
    except Exception as exc:
        print("FAILED", exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
