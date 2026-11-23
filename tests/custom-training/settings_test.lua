local settings = require("ct_settings")

-- settings: defaults, parsing, bad values ignored, other lines kept
local s = settings.parse("ct_count = 3\nct_behaviour = aggressive\nct_difficulty = sideways\nstages_x = 1\n")
assert(s.count == 3 and s.behaviour == "aggressive" and s.difficulty == "normal", "parse")
assert(settings.parse("ct_count = 4").count == 1, "count out of range")
local text = settings.render(s, "# comment\nct_count = 1\nstages_x = 1\n")
assert(text:find("# comment", 1, true) and text:find("stages_x = 1", 1, true), "keeps other lines")
assert(text:find("ct_count = 3", 1, true) and not text:find("ct_count = 1", 1, true), "replaces ours")
assert(settings.parse(text).behaviour == "aggressive", "round trip")

-- names: the game's text, else the catalogue's English name; the plain tag after it; no internal tags; a failed lookup
-- is not kept
local session = require("ct_session")
local up = false
local cat = { territory = "t", base = {}, opponents = {
    { id = "mobcolvr_SU2030_01_Alexander_GilQuest_00", spec = "SU2030_01_Alexander_GilQuest", label = "$a", name = "Alexander", tag = "Gilgamesh's trial", category = 5 },
    { id = "mobcolvr_SU2030_01_Alexander_Standard_00", spec = "SU2030_01_Alexander_Standard", label = "$a", name = "Alexander", category = 5 },
    { id = "mobcolvr_EN2250_00_BlackBat_StandardEnd2_00", spec = "EN2250_00_BlackBat_StandardEnd2", label = "$b", name = "Black Bat", category = 3 },
} }
local ns = session.new({ game = { lookup = function(k) return up and ({ ["$a"] = "Alexandre", ["$b"] = "Chauve-souris" })[k] or nil end },
    catalogue = cat, settings = {}, save_settings = function() end, log = function() end })
assert(ns:name(cat.opponents[1]) == "Alexander (Gilgamesh's trial)", ns:name(cat.opponents[1]))
assert(ns:name(cat.opponents[2]) == "Alexander" and ns:name(cat.opponents[3]) == "Black Bat", "English fallback, no tag")
local menu = ns:menu_catalogue()
assert(menu[3].name == "Black Bat" and ns.menu_list == nil, "a fallback list is not kept")
up = true
assert(ns:name(cat.opponents[3]) == "Chauve-souris", "looked up again once the game answers")
menu = ns:menu_catalogue()
assert(menu[1].name == "Alexandre (Gilgamesh's trial)" and menu[2].name == "Alexandre" and ns.menu_list ~= nil, "game's text, kept: " .. menu[1].name .. " / " .. menu[2].name .. " / " .. tostring(ns.menu_list))
for _, o in ipairs(require("ct_catalogue").opponents) do
    assert(o.name and o.name ~= "" and not o.name:find("End2") and not o.name:find("_"), "plain name for " .. o.id)
    assert(not o.id:find("MikataTest"), "test enemy offered")
end

-- the equipment mod's folder beside ours (main.lua's dev bridge pattern)
local dir = ("D:\\Game\\ue4ss\\Mods\\SimOverhaulCustomTraining\\"):gsub("[^\\/]+[\\/]$", "")
assert(dir == "D:\\Game\\ue4ss\\Mods\\", dir)

-- Development-only keys are read but not written into a player's file (shipped settings.txt, 2026-11-22).
do
    local st = require("ct_settings")
    local parsed = st.parse("ct_auto = off\nct_panel = off\n")
    assert(parsed.auto == "off" and parsed.panel == "off", "read when present")
    local text = st.render(st.parse(""), "")
    assert(not text:match("ct_auto =") and not text:match("ct_panel ="), "not written: " .. text)
    assert(text:match("ct_respawn_key = F4") and text:match("ct_auto_respawn = off"), "the new keys are written")
    local kept = st.render(parsed, "ct_auto = off\n")
    assert(kept:match("ct_auto = off"), "kept where a developer set it")
end
