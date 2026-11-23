local stages = require("stages")
local catalogue = require("stage_data")
-- These tests exercise every stage, so they turn the experimental ones on.
local function S(text) return stages.parse_settings("experimental = true\n" .. (text or "")) end

local function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what, tostring(expected), tostring(actual)), 2)
    end
end
local function ids(options)
    local list = {}
    for i, option in ipairs(options) do list[i] = option.id end
    return table.concat(list, ",")
end
local function context(overrides)
    local c = { continent = "WESTC", flag = function() return true end, progress = 13000, cleared = true, can_stream = true }
    for k, v in pairs(overrides or {}) do c[k] = v end
    return c
end
local defaults = S("")
local move = S("route = move")
local index = stages.title_index(catalogue)
local function course(key)
    for _, c in ipairs(catalogue.courses) do if c.key == key then return c end end
    error("no course " .. key)
end

-- Catalogue shape
eq(#catalogue.courses, 78, "75 simulator courses and three from Training Dummy")
local in_scope, world, streamed = 0, 0, 0
for _, c in ipairs(catalogue.courses) do
    if not c.excluded then in_scope = in_scope + 1 end
    assert(c.needs_m >= 12, c.key .. " needs")
    assert(c.title_id:sub(1, 1) == "$", c.key .. " title id")
end
eq(in_scope, 70, "all but the eight Shinra Manor courses are in scope (owner, 2026-11-17)")
for _, stage in ipairs(catalogue.stages) do
    if stage.kind == "world" then world = world + 1 else streamed = streamed + 1 end
    assert(stage.radius_m > 0 and stage.unlock, stage.id .. " size and unlock")
    assert(stage.id ~= stages.VANILLA, "reserved id")
end
eq(world, 6, "six open-world stages"); eq(streamed, 11, "eleven stages from other maps")
for _, stage in ipairs(catalogue.stages) do
    assert(#stage.anchor == 3, stage.id .. " anchor")
    assert(stage.enabled == false or #stage.levels > 0, stage.id .. " levels")
    for _, level in ipairs(stage.levels or {}) do assert(level:sub(1, 6) == "/Game/", stage.id .. " level path " .. level) end
end

-- Settings
local s, problems = S("picker = key\nlift_cm = 12 # a little\nrequire_unlock = false\nforce_stage = corel\n")
eq(s.picker, "key", "picker"); eq(s.lift_cm, 12, "lift"); eq(s.require_unlock, false, "unlock off"); eq(s.force_stage, "corel", "force")
eq(#problems, 0, "no problems")
s, problems = S("picker = sideways\nnonsense\nenabled = maybe\nlift_cm = high\nroute = teleport")
eq(s.picker, "select", "bad picker keeps default"); eq(s.enabled, true, "bad bool keeps default")
eq(s.lift_cm, 0, "bad number keeps default"); eq(s.route, "stream", "bad route keeps default"); eq(#problems, 5, "five problems")
eq(move.route, "move", "route read")
eq(S(nil).picker, "select", "defaults")
local steps = stages.steps({ steps = "relocate, sky" })
eq(steps.relocate, true, "step on"); eq(steps.dressing, nil, "step off")

-- Courses by title, in English and in the player's language
eq(stages.course_by_title(index, "Summon Entity: Odin").key, "COL30_SUMMON_Odin_Free_vr", "english title")
eq(stages.course_by_title(index, "  Summon Entity: Odin \n").key, "COL30_SUMMON_Odin_Free_vr", "padded title")
eq(stages.course_by_title(index, "$menu_Colosseum_CourseTitle_COL30_GRASA_01").key, "COL30_GRASA_01_Free_vr", "the text id the menu holds")
eq(stages.course_by_title(index, "Something else"), nil, "unknown title")
eq(stages.course_by_title(index, nil), nil, "no title")
local german = stages.title_index(catalogue, function(id)
    if id == "$menu_Colosseum_CourseTitle_COL30_SUMMON_Odin" then return "Beschwörung: Odin" end
    return nil
end)
eq(stages.course_by_title(german, "Beschwörung: Odin").key, "COL30_SUMMON_Odin_Free_vr", "localised title")
eq(stages.course_by_title(german, "Summon Entity: Odin").key, "COL30_SUMMON_Odin_Free_vr", "english still works")

-- Unlock rules
local corel, void = stages.find(catalogue, "corel"), stages.find(catalogue, "lifestream")
eq(stages.unlocked(corel, context({ flag = function(n) return n == "stfWorldReport_Finish_CORLA_031" end }), defaults), true, "boss beaten")
eq(stages.unlocked(corel, context({ flag = function() return false end }), defaults), false, "boss not beaten")
eq(stages.unlocked(corel, context({ flag = function() return false end }), S("require_unlock = false")), true, "gate off")
eq(stages.unlocked(void, context({ cleared = true }), defaults), true, "game finished")
eq(stages.unlocked(void, context({ cleared = false }), defaults), false, "game not finished")
local story = { unlock = { progress = 6000 } }
eq(stages.unlocked(story, context({ progress = 6000, cleared = false }), defaults), true, "past the boss")
eq(stages.unlocked(story, context({ progress = 5990, cleared = false }), defaults), false, "before the boss")
eq(stages.unlocked(story, context({ progress = 2000, cleared = true }), defaults), true, "chapter replay of a finished game")
local unreadable = context({ cleared = false })
unreadable.progress = nil
eq(stages.unlocked(story, unreadable, defaults), false, "progress unreadable")

-- Why a course cannot use a stage
local ordinary, odin, phoenix = course("COL30_GRASA_01_Free_vr"), course("COL30_SUMMON_Odin_Free_vr"), course("COL30_SUMMON_Phoenix_Free_vr")
local grasslands = stages.find(catalogue, "grasslands")
-- streamed (the default): no continent rule, needs the helper and a level list
eq(stages.route_of(corel, defaults), "stream", "streamed by default"); eq(stages.route_of(corel, move), "move", "moved on request")
eq(stages.route_of(void, move), "stream", "a stage outside the open world is always streamed")
eq(stages.blocked(corel, ordinary, context(), defaults), nil, "ordinary course fits Corel")
eq(stages.blocked(corel, ordinary, context({ continent = "EASTC" }), defaults), nil, "Corel from the east, streamed")
eq(stages.blocked(corel, odin, context(), defaults), "too small", "Odin does not fit Corel")
eq(stages.blocked(corel, ordinary, context({ flag = function() return false end }), defaults), "locked", "locked")
eq(stages.blocked(corel, ordinary, context({ can_stream = false }), defaults), "needs the level helper", "no helper")
eq(stages.blocked(void, phoenix, context({ continent = "EASTC" }), defaults), nil, "the white void takes Phoenix anywhere")
eq(stages.blocked(void, phoenix, context({ cleared = false }), defaults), "locked", "the white void before the game is finished")
eq(stages.blocked({ id = "x", kind = "streamed", radius_m = 50, unlock = {}, levels = {} }, ordinary, context(), defaults),
    "no levels listed", "a stage with no levels")
eq(stages.blocked({ id = "x", kind = "streamed", enabled = false, radius_m = 50, unlock = {} }, ordinary, context(), defaults),
    "not built", "a stage switched off")
-- moved: own continent only, no helper needed
eq(stages.blocked(corel, ordinary, context({ can_stream = false }), move), nil, "Corel moved, no helper")
eq(stages.blocked(corel, ordinary, context({ continent = "EASTC" }), move), "other continent", "Corel from the east, moved")
eq(stages.blocked(grasslands, phoenix, context({ continent = "EASTC" }), move), nil, "Phoenix fits the Grasslands arena")

-- What the picker offers
local options, left_out = stages.options(catalogue, ordinary, context(), defaults)
eq(ids(options), "vanilla,grasslands,junon,corel,gongaga,cosmo,nibel,lifestream,space_rock,mythril_golem,grasptropod,anuran_suppressor,gi_nattak,galian_beast,gilgamesh,gilgamesh_garden,midgar_outskirts,red_dragon", "every stage for an ordinary course, anywhere")
eq(#left_out, 0, "nothing left out")
eq(ids(stages.options(catalogue, odin, context(), defaults)), "vanilla,grasslands,lifestream,space_rock,grasptropod,gilgamesh_garden,midgar_outskirts", "what is big enough for Odin")
eq(ids(stages.options(catalogue, ordinary, context({ cleared = false, progress = 2000, flag = function(n) return n == "stfWorldReport_Finish_NIBLA_025" end }), defaults)),
    "vanilla,nibel,midgar_outskirts", "only what is unlocked (Mt. Nibel from Chapter 2; Midgar Outskirts from the start)")
eq(ids(stages.options(catalogue, ordinary, context({ cleared = false, progress = 7000, flag = function() return false end }), defaults)),
    "vanilla,mythril_golem,grasptropod,midgar_outskirts", "story bosses beaten by Chapter 7")
eq(ids(stages.options(catalogue, ordinary, context({ can_stream = false }), defaults)), "vanilla", "nothing without the helper")
options, left_out = stages.options(catalogue, ordinary, context({ can_stream = false }), move)
eq(ids(options), "vanilla,corel,gongaga,cosmo,nibel", "moved: the west's arenas")
eq(#left_out, 13, "moved: two east arenas and eleven stages that can only be streamed left out")
eq(#stages.options(catalogue, course("COL30_NIBLS_01_Free_Colvr"), context(), defaults), 0, "Shinra Manor course: no picker")
-- Another mod's courses: recognised by the title it puts on screen and by its title id
local index = stages.title_index(catalogue)
local dummy = stages.course_by_title(index, "Training Dummy: DPS")
eq(dummy and dummy.key, "COL99_TrainingDummy_DPS", "Training Dummy's course by its title")
eq(stages.course_by_title(index, "$menu_Colosseum_CourseTitle_COL99_TrainingDummy_Heal").key, "COL99_TrainingDummy_Heal", "and by its title id")
assert(#stages.options(catalogue, dummy, context(), defaults) > 1, "Training Dummy course: offered stages")
assert(#stages.options(catalogue, course("COL11_TutorialBtl_01_Cloud_Vr"), context(), defaults) > 1, "tutorial course: offered stages")
eq(#stages.options(catalogue, nil, context(), defaults), 0, "unknown course: no picker")
-- Replay: the last stage picked on any course goes on top, when this course can use it
options = stages.options(catalogue, ordinary, context(), defaults, { last = "red_dragon" })
eq(options[1].id, "red_dragon", "replay on top")
eq(options[1].name, "Replay: Temple of the Ancients", "replay label")
eq(options[1].replay, true, "marked as the replay row")
eq(options[2].id, "vanilla", "then the simulator's own stage")
eq(#options, 19, "the stage keeps its own row too")
eq(stages.selected_index(options, ordinary, { [ordinary.key] = "red_dragon" }), 19, "the course's own choice is marked on its own row")
eq(ids(stages.options(catalogue, odin, context(), defaults, { last = "red_dragon" })),
    "vanilla,grasslands,lifestream,space_rock,grasptropod,gilgamesh_garden,midgar_outskirts", "no replay where the stage does not fit")
eq(stages.options(catalogue, ordinary, context(), defaults, { last = "vanilla" })[1].id, "vanilla", "no replay of the simulator's own stage")

-- What a streamed stage loads, and where
local plan = stages.stream_plan(corel, { X = -200000, Y = -100000, Z = 10000 }, defaults)
eq(#plan, #corel.levels + (corel.sky_level and 1 or 0), "one item per level, plus the sky")
eq(plan[1].package, corel.levels[1], "first level"); eq(plan[1].name, "SimStage_corel_1_" .. string.format("%d", math.floor(plan[1].location.Z + 0.5)), "instance name carries the height")
-- the arena's anchor lands on the simulator's centre
assert(math.abs(plan[1].location.X + corel.anchor[1] - -200000) < 0.01, "x offset")
assert(math.abs(plan[1].location.Y + corel.anchor[2] - -100000) < 0.01, "y offset")
assert(math.abs(plan[1].location.Z + corel.anchor[3] - 10000) < 0.01, "z offset")
eq(plan[#plan].location, plan[1].location, "every level shares the offset")
local lifted = stages.stream_plan(corel, { X = 0, Y = 0, Z = 0 }, S("lift_cm = 50"))
assert(math.abs(lifted[1].location.Z - (50 - corel.anchor[3])) < 0.01, "lift raises the stage")
plan = stages.stream_plan(void, { X = 0, Y = 0, Z = 0 }, defaults)
eq(plan[#plan].package, void.sky_level, "the sky is loaded last")
local names = {}
for _, item in ipairs(plan) do assert(not names[item.name], "unique instance names"); names[item.name] = true end

-- The stage a confirmed course gets
local stage, why = stages.chosen(catalogue, ordinary, context(), defaults, {})
eq(stage, nil, "no choice yet"); eq(why, "simulator stage chosen", "no choice reason")
stage = stages.chosen(catalogue, ordinary, context(), defaults, { [ordinary.key] = "nibel" })
eq(stage.id, "nibel", "remembered choice")
stage, why = stages.chosen(catalogue, ordinary, context(), defaults, { [ordinary.key] = "vanilla" })
eq(stage, nil, "vanilla chosen")
stage, why = stages.chosen(catalogue, ordinary, context({ continent = "EASTC" }), move, { [ordinary.key] = "nibel" })
eq(stage, nil, "choice not usable here"); eq(why, "nibel: other continent", "not usable reason")
stage = stages.chosen(catalogue, ordinary, context({ continent = "EASTC" }), defaults, { [ordinary.key] = "nibel" })
eq(stage.id, "nibel", "streamed: usable from the other continent")
stage, why = stages.chosen(catalogue, odin, context(), defaults, { [odin.key] = "corel" })
eq(stage, nil, "choice too small"); eq(why, "corel: too small", "too small reason")
stage, why = stages.chosen(catalogue, ordinary, context(), defaults, { [ordinary.key] = "moon" })
eq(stage, nil, "unknown stage"); assert(why:find("unknown stage"), why)
stage, why = stages.chosen(catalogue, course("COL30_NIBLS_01_Free_Colvr"), context(), defaults, { COL30_NIBLS_01_Free_Colvr = "nibel" })
eq(stage, nil, "excluded course"); assert(why:find("^excluded"), why)
stage, why = stages.chosen(catalogue, nil, context(), defaults, {})
eq(stage, nil, "unrecognised course"); eq(why, "course not recognised", "unrecognised reason")
stage, why = stages.chosen(catalogue, ordinary, context(), S("enabled = false"), { [ordinary.key] = "nibel" })
eq(stage, nil, "disabled"); eq(why, "disabled", "disabled reason")
stage, why = stages.chosen(catalogue, ordinary, context(), S("force_stage = corel"), { [ordinary.key] = "nibel" })
eq(stage.id, "corel", "forced stage"); eq(why, "forced", "forced reason")

-- Remembered choices on disk
local choices = stages.parse_choices("COL30_GRASA_01_Free_vr = nibel\n\n  COL30_SUMMON_Odin_Free_vr=grasslands  \nrubbish line\n")
eq(choices.COL30_GRASA_01_Free_vr, "nibel", "choice read"); eq(choices.COL30_SUMMON_Odin_Free_vr, "grasslands", "second choice read")
eq(stages.format_choices(choices), "COL30_GRASA_01_Free_vr = nibel\nCOL30_SUMMON_Odin_Free_vr = grasslands\n", "choices written in order")
eq(stages.format_choices({}), "", "no choices")
eq(next(stages.parse_choices(nil)), nil, "no file")
options = stages.options(catalogue, ordinary, context({ can_stream = false }), move)
eq(stages.selected_index(options, ordinary, { [ordinary.key] = "cosmo" }), 4, "picker starts on the remembered stage")
eq(stages.selected_index(options, ordinary, {}), 1, "picker starts on the simulator")
eq(stages.selected_index(options, ordinary, { [ordinary.key] = "junon" }), 1, "remembered stage not offered here")

-- Target: the simulator's floor (its level's z = 0) lands on the arena's ground
local location, yaw = stages.target(corel, defaults)
eq(location.X, 150267.625, "x"); eq(location.Y, 40601.063, "y")
assert(math.abs(location.Z - 933.726) < 0.01, "floor z " .. location.Z)
eq(yaw, 0, "no stage rotation by default")
location = stages.target(corel, S("lift_cm = 50"))
assert(math.abs(location.Z - 983.726) < 0.01, "lifted z " .. location.Z)

-- Continent from a volume's name
eq(stages.continent_of("1000-StreamingVolume_VR_Battle", catalogue.vr_stage), "EASTC", "east volume")
eq(stages.continent_of("2000-StreamingVolume_VR_Battle", catalogue.vr_stage), "WESTC", "west volume")
eq(stages.continent_of("2350-StreamingVolume_VR_Battle", catalogue.vr_stage), "GOLDS", "gold saucer volume")
eq(stages.continent_of("Something_Else", catalogue.vr_stage), nil, "unknown volume")

-- Experimental stages are not offered unless asked for
local plain = stages.parse_settings("")
eq(plain.experimental, false, "experimental is off by default")
eq(ids(stages.options(catalogue, ordinary, context(), plain)), "vanilla,lifestream,space_rock,mythril_golem,gi_nattak,galian_beast,gilgamesh_garden,midgar_outskirts,red_dragon", "only the working stages by default")
eq(stages.blocked(corel, ordinary, context(), plain), "not working yet", "an arena stage by default")
eq(stages.blocked(void, ordinary, context(), plain), nil, "the white void by default")

-- Each visit's copy has its own name, and the plan says where the stage's anchor lands
local first = stages.stream_plan(corel, { X = -200000, Y = -100000, Z = 10000 }, defaults, 1)
local second = stages.stream_plan(corel, { X = -200000, Y = -100000, Z = 10000 }, defaults, 2)
eq(first[1].name ~= second[1].name, true, "two visits, two names")
eq(first[1].name:sub(-2), "_1", "the visit's number ends the name")
eq(first.centre.X, -200000, "centre x"); eq(first.centre.Z, 10000, "centre z")
eq(stages.stream_plan(corel, { X = 0, Y = 0, Z = 0 }, S("lift_cm = 50"), 1).centre.Z, 50, "the lift raises the centre")
