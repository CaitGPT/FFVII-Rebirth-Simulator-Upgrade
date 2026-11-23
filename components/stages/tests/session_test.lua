local stages = require("stages")
local catalogue = require("stage_data")
-- These tests exercise every stage, so they turn the experimental ones on.
local function S(text) return stages.parse_settings("experimental = true\n" .. (text or "")) end
local session_module = require("session")
-- Most tests here are about what happens once the simulator is ready, so they do not wait for it.
session_module.SHOWN_FOR = 0

local function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what, tostring(expected), tostring(actual)), 2)
    end
end
local MU = "Grasslands Battle Intel: Natural Order"           -- needs 18 m (Mu's fixed pop points)
local PLAIN = "Grasslands Battle Intel: Horror on the Range"  -- needs 12 m
local ODIN = "Summon Entity: Odin"                            -- needs 24.9 m
local MANOR = "Preliminary Trial: Aerial Specimens"

-- A stand-in for game.lua that records what was asked of it.
local function fake(options)
    options = options or {}
    local g = { calls = {}, inside = false, accept = options.accept ~= false, requested = {}, released = {}, loaded = {} }
    g.volumes = options.volumes or {
        { name = "2000-StreamingVolume_VR_Battle", target = { location = { X = -200000, Y = -100000, Z = 10000 }, yaw = 0 } },
    }
    local function note(name) g.calls[#g.calls + 1] = name end
    function g.count(name)
        local n = 0
        for _, call in ipairs(g.calls) do if call == name then n = n + 1 end end
        return n
    end
    function g.flag(name) return options.flags == nil or options.flags[name] == true end
    function g.progress() return 15000 end
    function g.cleared() return options.cleared ~= false end
    function g.can_stream() return options.helper ~= false end
    function g.text() return nil end
    function g.in_simulator() return g.inside end
    function g.vr_volumes(label) eq(label, "COMMON_VR", "label asked"); return g.volumes end
    function g.get_target(volume) return volume.target end
    function g.set_target(volume, location, yaw)
        note("set_target")
        if not g.accept then return false end
        volume.target = { location = { X = location.X, Y = location.Y, Z = location.Z }, yaw = yaw }
        return true
    end
    function g.show_hidden_levels() note("unhide"); return true end
    function g.set_dressing_hidden(_, hidden, sky_too, what)
        if what == "scenery" then note("scenery"); return 18 end
        note((hidden and "hide" or "show") .. (sky_too and "+sky" or ""))
        return 7
    end
    function g.scenery_present() note("floor?"); return options.floor ~= false end
    g.blacks = {}
    function g.black_screen(on) g.blacks[#g.blacks + 1] = on; return true end
    g.background = {}
    function g.background_unload(on) g.background[#g.background + 1] = on; return true end
    g.fast = {}
    function g.fast_streaming(on) g.fast[#g.fast + 1] = on; return true end
    function g.drop_simulator_collision(with_floor) note(with_floor and "walls+floor off" or "walls off"); return 9 end
    function g.switch_sky(sky) note("sky:" .. sky.volume); return true end
    function g.stream_request(item)
        if options.refuse_level and item.package:find(options.refuse_level, 1, true) then return false end
        g.requested[#g.requested + 1] = item
        return true
    end
    function g.stream_ready(name) return g.loaded[name] == true or g.loaded.all == true end
    g.unloaded = {}
    function g.stream_state(name)
        if g.unloaded[name] then return "unloaded" end
        if g.stream_ready(name) then return "loaded" end
    end
    function g.stream_release(name) g.released[#g.released + 1] = name; g.unloaded[name] = true; return true end
    function g.activate_stage(stage, lights_now)
        note("activate:" .. stage.id)
        if lights_now == false then note("lights held"); return 3, 5 end
        return 3, 0
    end
    function g.simulator_lighting_visible() return options.sim_lit == true end
    function g.show_stage_lights() note("lights"); return 5 end
    function g.reactivate_stage(stage) note("activate:" .. stage.id); return 0 end
    function g.prepare_dressing() note("prepare"); return options.parts or 18 end
    g.shown = true
    function g.simulator_shown() note("shown?"); return g.shown, g.shown and 3 or 1 end
    function g.fit_stage(stage, plan) note("fit:" .. stage.id .. ":" .. plan[1].name); return 5 end
    function g.settled() return options.settled ~= false end
    return g
end
local function new(game, choices, saved, logged)
    return session_module.new({
        stages = stages, catalogue = catalogue, game = game, choices = choices or {},
        save_choices = function(c) if saved then saved[#saved + 1] = stages.format_choices(c) end end,
        log = function(m) if logged then logged[#logged + 1] = m end end,
    })
end
local defaults = S("")
local move = S("route = move")
local function names(options)
    local list = {}
    for i, option in ipairs(options) do list[i] = option.id end
    return table.concat(list, ",")
end
local function has(log, text)
    for _, line in ipairs(log) do if line:find(text, 1, true) then return true end end
    return false
end

-- ===== Streamed (the default): select a course, pick a stage, confirm, arrive, leave =====
-- (Gi Nattak's cave is indoors, so the simulator's sky goes with its look: "hide+sky".)
local game, saved, logged = fake(), {}, {}
local session = new(game, {}, saved, logged)
local course, options, start = session.course_selected(MU, defaults)
eq(course.key, "COL30_GRASA_03_Free_vr", "course recognised")
eq(names(options), "vanilla,grasslands,gongaga,cosmo,nibel,lifestream,space_rock,grasptropod,gi_nattak,gilgamesh,gilgamesh_garden,midgar_outskirts,red_dragon",
    "every unlocked stage with 18 m of room, from either continent")
eq(start, 1, "picker starts on the simulator")
session.choose(course, "gi_nattak")
eq(saved[1], "COL30_GRASA_03_Free_vr = gi_nattak\nlast = gi_nattak\n", "choice saved, and kept as the last stage for Replay")
local _, again = session.course_selected(MU, defaults)
eq(again[1].name, "Replay: Cave of the Gi", "Replay on top next time")
local stage = session.course_confirmed(100, defaults)
eq(stage.id, "gi_nattak", "chosen stage used")
local gi = stages.find(catalogue, "gi_nattak")
local gi_items = #gi.levels + (gi.sky_level and 1 or 0)
eq(#game.requested, session_module.REQUEST_BATCH, "the first batch requested (the cave has more levels than one batch)")
assert(gi_items > session_module.REQUEST_BATCH, "a stage larger than one batch")
eq(game.count("set_target"), 0, "the simulator itself is not moved")
-- the arena's anchor lands on the simulator's centre
local first = game.requested[1]
assert(math.abs(first.location.X + gi.anchor[1] - -200000) < 0.01, "x offset")
assert(math.abs(first.location.Z + gi.anchor[3] - 10000) < 0.01, "z offset")
session.tick(101)
eq(game.count("hide+sky"), 0, "nothing dressed before the simulator starts")
game.inside = true
session.tick(105)
eq(game.count("hide+sky"), 0, "simulator's look kept while the stage's levels load"); eq(game.count("unhide"), 0, "no far-terrain call when streaming")
eq(session.stream_ready(), false, "levels still loading")
game.loaded.all = true
session.tick(106)
eq(#game.requested, gi_items, "the rest requested as the helper answers")
eq(game.count("hide+sky"), 1, "simulator's look hidden once they are in")
eq(session.stream_ready(), true, "levels loaded"); assert(has(logged, "stream\tready"), "readiness logged")
session.tick(109)
eq(game.count("hide+sky"), 2, "dressed once more after the stage's own set-up")
-- Mid-visit: no picker, no new requests
local _, mid_options = session.course_selected(MU, defaults)
eq(#mid_options, 0, "no picker mid-visit")
local again, why = session.course_confirmed(121, defaults)
eq(again, nil, "no new stage mid-visit"); eq(why, "visit in progress", "mid-visit reason")
eq(#game.requested, gi_items, "nothing more requested")
-- A gap between rounds shorter than the grace does not end the visit
game.inside = false
session.tick(130); session.tick(131)
eq(session.busy(), true, "short gap tolerated")
game.inside = true
session.tick(132)
game.inside = false
session.tick(140); session.tick(143)
eq(session.busy(), false, "visit over")
-- The unloads wait for the game's own trip back (its loader idle a while), then go 48 at a time too (the helper
-- queues 64 requests, unloads included): the rest on the next tick
eq(#game.released, 0, "nothing unloaded while the game goes back")
eq(session.unloading(), true, "unloading to do")
session.tick(144)
eq(#game.released, session_module.REQUEST_BATCH, "the first batch once the loader is idle")
session.tick(145)
eq(#game.released, gi_items, "every level released")
eq(game.fast[#game.fast], false, "the unloads run at the game's own streaming budgets")
eq(game.background[1], true, "in the background, with the engine's purge spread out")
session.tick(146)
eq(session.unloading(), true, "the spread-out purge stays on a while")
session.tick(146 + session_module.GC_SPREAD_SECONDS)
eq(game.background[#game.background], false, "then the game's own setting is put back")
eq(session.unloading(), false, "unloading done")
eq(game.count("show+sky"), 1, "simulator's look back")
eq(game.volumes[1].target.location.X, -200000, "volume never touched")

-- Next visit: the picker starts on the remembered stage, and confirming without picking reuses it
course, options, start = session.course_selected(MU, defaults)
eq(options[start].id, "gi_nattak", "picker starts on the remembered stage")
stage = session.course_confirmed(200, defaults)
eq(stage.id, "gi_nattak", "remembered stage reused")

-- A stage with its own sky: the sky is loaded and the simulator's sky hidden
game = fake()
session = new(game, { COL30_SUMMON_Odin_Free_vr = "lifestream" })
course, options = session.course_selected(ODIN, defaults)
eq(names(options), "vanilla,grasslands,lifestream,space_rock,grasptropod,gilgamesh_garden,midgar_outskirts", "what is big enough for Odin")
stage = session.course_confirmed(0, defaults)
local void = stages.find(catalogue, "lifestream")
eq(#game.requested, #void.levels + 1, "levels plus the sky")
eq(game.requested[#game.requested].package, void.sky_level, "sky requested")
game.inside = true
game.loaded.all = true
session.tick(1)
eq(game.count("hide+sky"), 1, "simulator's sky hidden with its look")
eq(game.count("walls+floor off"), 0, "the Lifestream stands on the simulator's floor")
eq(game.count("walls off"), 1, "but loses its invisible walls")
game.inside = false
session.tick(2); session.tick(6)
eq(game.count("show+sky"), 1, "simulator's sky back")

-- Levels that never load are reported once, and the visit carries on
-- An indoor stage is lit by its region's sky, and the simulator's sky is hidden
game = fake()
session = new(game, { COL30_GRASA_01_Free_vr = "mythril_golem" })
session.course_selected(PLAIN, defaults)
stage = session.course_confirmed(0, defaults)
eq(stage.id, "mythril_golem", "indoor stage chosen")
eq(#game.requested, #stage.levels + 1, "its levels and its region's sky requested")
game.inside = true
game.loaded.all = true
session.tick(1)
eq(game.count("hide+sky"), 1, "simulator's sky hidden indoors")
eq(game.count("walls+floor off"), 1, "a stage with its own floor and walls drops the simulator's floor too")

game, logged = fake(), {}
session = new(game, { COL30_GRASA_03_Free_vr = "nibel" }, nil, logged)
session.course_selected(MU, defaults)
session.course_confirmed(0, defaults)
game.inside = true
session.tick(1); session.tick(20)
assert(not has(logged, "NOT loaded"), "patient at first")
session.tick(31); session.tick(40)
local reports = 0
for _, line in ipairs(logged) do if line:find("NOT loaded", 1, true) then reports = reports + 1 end end
eq(reports, 1, "reported once"); eq(session.busy(), true, "visit carries on")

-- A refused level request: release what was asked and stay on the simulator's stage
game = fake({ refuse_level = "Dungeon_Light" })
session = new(game, { COL30_GRASA_03_Free_vr = "gi_nattak" })
session.course_selected(MU, defaults)
stage, why = session.course_confirmed(0, defaults)
eq(stage, nil, "refused"); eq(why, "level request refused", "refused reason"); eq(session.busy(), false, "idle after refusal")
eq(#game.released, session_module.REQUEST_BATCH, "everything asked for released (the first batch)")

-- Without the helper nothing is offered, and a remembered stage is not used
game = fake({ helper = false })
session = new(game, { COL30_GRASA_03_Free_vr = "gi_nattak" })
course, options = session.course_selected(MU, defaults)
eq(#options, 0, "no helper: no picker")
stage, why = session.course_confirmed(0, defaults)
eq(stage, nil, "no helper: simulator stage"); eq(why, "gi_nattak: needs the level helper", "no helper reason")

-- Locked stages are not offered, and a remembered locked stage is not used
game = fake({ cleared = false, flags = { stfWorldReport_Finish_NIBLA_025 = true } })
session = new(game, { COL30_GRASA_01_Free_vr = "gongaga" })
course, options = session.course_selected(PLAIN, defaults)
eq(names(options), "vanilla,nibel,mythril_golem,grasptropod,anuran_suppressor,gi_nattak,galian_beast,midgar_outskirts,red_dragon",
    "the unlocked arena and the story bosses beaten by this point")
stage, why = session.course_confirmed(0, defaults)
eq(stage, nil, "locked choice not used"); eq(why, "gongaga: locked", "locked reason")

-- Excluded and unrecognised courses
game = fake()
session = new(game, { COL30_NIBLS_01_Free_Colvr = "nibel" })
course, options = session.course_selected(MANOR, defaults)
eq(#options, 0, "Shinra Manor course: no picker")
stage, why = session.course_confirmed(0, defaults)
eq(stage, nil, "Shinra Manor course left alone"); assert(why:find("^excluded"), why)
course, options = session.course_selected("Some other mod's course", defaults)
eq(course, nil, "unrecognised course"); eq(#options, 0, "no picker for it")
stage, why = session.course_confirmed(0, defaults)
eq(stage, nil, "unrecognised course left alone"); eq(why, "course not recognised", "unrecognised reason")
eq(#game.requested, 0, "nothing requested")

-- A new visit confirmed while the last one's unloads still wait for an idle loader sends them first
game = fake({ settled = false })
session = new(game, { COL30_GRASA_03_Free_vr = "nibel" })
session.course_selected(MU, defaults)
session.course_confirmed(0, defaults)
session.tick(91) -- the simulator never started: the visit ends, its unloads wait (the loader is never idle here)
session.tick(95)
eq(#game.released, 0, "held while the loader is busy")
session.course_selected(MU, defaults)
session.course_confirmed(100, defaults)
eq(#game.released, #stages.find(catalogue, "nibel").levels, "sent before the next visit's levels")

-- A streamed stage arrives behind a black screen, lifted once the stage is set up and the simulator's look is gone
game = fake()
session = new(game, { COL30_GRASA_03_Free_vr = "gi_nattak" })
session.course_selected(MU, defaults)
session.course_confirmed(0, defaults)
game.inside = true
session.tick(1)
eq(game.blacks[1], true, "black from arrival")
game.loaded.all = true
session.tick(2)
eq(#game.blacks, 1, "still black just after the swap")
session.tick(2 + session_module.BLACK_AFTER)
eq(game.blacks[#game.blacks], false, "lifted once set up")
eq(#game.blacks, 2, "lifted once")
-- and lifted after the time limit if the stage never comes
game = fake()
session = new(game, { COL30_GRASA_03_Free_vr = "gi_nattak" })
session.course_selected(MU, defaults)
session.course_confirmed(0, defaults)
game.inside = true
session.tick(1); session.tick(30)
eq(#game.blacks, 1, "black while waiting")
session.tick(1 + session_module.HOLD_PATIENCE + session_module.BLACK_AFTER)
eq(game.blacks[#game.blacks], false, "never left in the dark")

-- A fight that begins behind the black screen is held still until the screen lifts, then let go
game = fake()
game.battle, game.holds = false, {}
function game.in_battle() return game.battle end
function game.hold_fight(on) game.holds[#game.holds + 1] = on; return true end
session = new(game, { COL30_GRASA_03_Free_vr = "gi_nattak" })
session.course_selected(MU, defaults)
session.course_confirmed(0, defaults)
game.inside = true
session.tick(1)
eq(#game.holds, 0, "no hold before the fight")
game.battle = true
session.tick(1)
eq(game.holds[1], true, "fight held behind the black screen")
session.tick(1)
eq(#game.holds, 1, "held once")
game.loaded.all = true
session.tick(2); session.tick(2 + session_module.BLACK_AFTER)
eq(game.blacks[#game.blacks], false, "black screen lifted")
eq(game.holds[#game.holds], false, "fight let go with it")
eq(#game.holds, 2, "let go once")
-- and let go when the visit ends while still black
game = fake()
game.holds = {}
function game.in_battle() return true end
function game.hold_fight(on) game.holds[#game.holds + 1] = on; return true end
session = new(game, { COL30_GRASA_03_Free_vr = "gi_nattak" })
session.course_selected(MU, defaults)
session.course_confirmed(0, defaults)
game.inside = true
session.tick(1)
game.inside = false
session.tick(2); session.tick(2 + session_module.LEAVE_GRACE)
eq(game.holds[#game.holds], false, "let go when the visit ends")
-- The simulator never starts: release after the timeout
game = fake()
session = new(game, { COL30_GRASA_03_Free_vr = "nibel" })
session.course_selected(MU, defaults)
session.course_confirmed(0, defaults)
session.tick(60)
eq(session.busy(), true, "still waiting")
session.tick(91)
eq(session.busy(), false, "gave up")
session.tick(92)
eq(#game.released, #stages.find(catalogue, "nibel").levels, "released after timeout, once the loader is idle")
eq(game.count("hide"), 0, "never dressed")

-- No volume, an unsupported world, or two candidate volumes: no picker and the simulator left alone
game = fake({ volumes = {} })
session = new(game, { COL30_GRASA_03_Free_vr = "nibel" })
course, options = session.course_selected(MU, defaults)
eq(#options, 0, "no volume: no picker")
stage, why = session.course_confirmed(0, defaults)
eq(stage, nil, "no volume"); eq(why, "no simulator volume here", "no volume reason")
game = fake({ volumes = { { name = "2350-StreamingVolume_VR_Battle", target = { location = { X = 0, Y = 0, Z = 0 }, yaw = 0 } } } })
session = new(game, { COL30_GRASA_03_Free_vr = "nibel" })
session.course_selected(MU, defaults)
stage = session.course_confirmed(0, defaults)
eq(stage, nil, "gold saucer volume ignored"); eq(#game.requested, 0, "gold saucer: nothing requested")
game = fake({ volumes = {
    { name = "1000-StreamingVolume_VR_Battle", target = { location = { X = 0, Y = 0, Z = 0 }, yaw = 0 } },
    { name = "2000-StreamingVolume_VR_Battle", target = { location = { X = 0, Y = 0, Z = 0 }, yaw = 0 } },
} })
session = new(game, { COL30_GRASA_03_Free_vr = "nibel" })
session.course_selected(MU, defaults)
stage, why = session.course_confirmed(0, defaults)
eq(stage, nil, "ambiguous world"); eq(why, "two simulator volumes loaded", "ambiguous reason")

-- Disabled: no picker, nothing requested
game = fake()
session = new(game, { COL30_GRASA_03_Free_vr = "nibel" })
local off = S("enabled = false")
course, options = session.course_selected(MU, off)
eq(#options, 0, "disabled: no picker")
stage = session.course_confirmed(0, off)
eq(stage, nil, "disabled"); eq(#game.requested, 0, "disabled: nothing requested")

-- ===== Moved (route = move): the simulator goes to a world stage on its own continent, with no helper =====
game = fake({ helper = false })
session = new(game, { COL30_GRASA_03_Free_vr = "gongaga" })
course, options = session.course_selected(MU, move)
eq(names(options), "vanilla,gongaga,cosmo,nibel", "the west's arenas with 18 m of room")
stage = session.course_confirmed(0, move)
eq(stage.id, "gongaga", "moved stage")
local west = game.volumes[1]
eq(west.target.location.X, -19867.688, "volume moved x")
assert(math.abs(west.target.location.Z - 2592.971) < 0.01, "volume moved z")
eq(#game.requested, 0, "nothing streamed")
game.inside = true
session.tick(5)
eq(game.count("unhide"), 1, "far terrain shown"); eq(game.count("hide"), 1, "stage hidden"); eq(game.count("sky:Sky_SouthSea"), 1, "sky")
game.inside = false
session.tick(6); session.tick(10)
eq(west.target.location.X, -200000, "target restored x"); eq(west.target.location.Z, 10000, "target restored z")
eq(game.count("show"), 1, "stage shown again")
-- from the other continent a remembered stage falls back to the simulator's own
game = fake({ helper = false, volumes = { { name = "1000-StreamingVolume_VR_Battle", target = { location = { X = 0, Y = 0, Z = 0 }, yaw = 0 } } } })
session = new(game, { COL30_GRASA_03_Free_vr = "gongaga" })
course, options = session.course_selected(MU, move)
eq(names(options), "vanilla,grasslands", "east: Junon is too small for this course")
stage, why = session.course_confirmed(0, move)
eq(stage, nil, "fallback"); eq(why, "gongaga: other continent", "fallback reason")
-- a write the game does not take: put the original back and stay idle
game = fake({ helper = false, accept = false })
session = new(game, { COL30_GRASA_03_Free_vr = "nibel" })
session.course_selected(MU, move)
stage, why = session.course_confirmed(0, move)
eq(stage, nil, "write refused"); eq(why, "target not accepted", "refused reason"); eq(session.busy(), false, "idle after refusal")
-- steps can be switched off one by one (for the live probes)
game = fake({ helper = false })
session = new(game)
local probe = S("route = move\nforce_stage = corel\nsteps = relocate")
session.course_selected(PLAIN, probe)
session.course_confirmed(0, probe)
game.inside = true
session.tick(1); session.tick(5)
eq(game.count("set_target"), 1, "relocate only: moved")
eq(game.count("hide") + game.count("unhide") + game.count("sky:Sky_SouthSea"), 0, "relocate only: nothing else")
game.inside = false
session.tick(6); session.tick(9)
eq(game.count("show"), 0, "nothing to show again")
eq(game.volumes[1].target.location.X, -200000, "restored")

-- A streamed stage's hidden sun, fog and meshes are shown once it has loaded, and once more a little later
game = fake()
session = new(game, { COL30_SUMMON_Odin_Free_vr = "lifestream" })
session.course_selected(ODIN, defaults)
session.course_confirmed(0, defaults)
game.inside = true
session.tick(1)
eq(game.count("activate:lifestream"), 0, "not before the levels have loaded")
game.loaded.all = true
session.tick(2)
eq(game.count("activate:lifestream"), 1, "shown once loaded")
session.tick(4)
eq(game.count("activate:lifestream"), 1, "not again yet")
session.tick(8)
eq(game.count("activate:lifestream"), 2, "and once more")
session.tick(20)
eq(game.count("activate:lifestream"), 2, "then left alone")

-- A stage with a fit is stretched once per visit, before its hidden parts are shown, and each visit has its own copy
local rock
for _, s in ipairs(catalogue.stages) do if s.id == "space_rock" then rock = s end end
eq(#rock.fit.scale, 2, "the rock has a fit along X and along Y")
game = fake()
session = new(game, { COL30_SUMMON_Odin_Free_vr = "space_rock" })
session.course_selected(ODIN, defaults)
session.course_confirmed(0, defaults)
game.inside = true
game.loaded.all = true
session.tick(1); session.tick(2); session.tick(4); session.tick(9); session.tick(20)
local fits = {}
for _, entry in ipairs(game.calls) do if entry:find("^fit:space_rock") then fits[#fits + 1] = entry end end
eq(#fits, 1, "stretched once in a visit")
game.inside = false
session.tick(21); session.tick(30)
session.course_selected(ODIN, defaults)
session.course_confirmed(31, defaults)
game.inside = true
session.tick(32); session.tick(33); session.tick(35)
local again = {}
for _, entry in ipairs(game.calls) do if entry:find("^fit:space_rock") then again[#again + 1] = entry end end
eq(#again, 2, "and once more on the next visit")
eq(again[1] ~= again[2], true, "on a copy of its own")

-- The stage's own parts are shown as soon as its levels are in; the simulator's look goes only once the game has
-- shown all of its own levels, on the first tick it has
game = fake()
game.shown = false
session = new(game, { COL30_SUMMON_Odin_Free_vr = "lifestream" })
session.course_selected(ODIN, defaults)
session.course_confirmed(0, defaults)
game.inside = true
session.tick(1)
eq(game.count("activate:lifestream"), 0, "not before the stage's levels are in")
game.loaded.all = true
session.tick(2); session.tick(5)
eq(game.count("activate:lifestream"), 1, "the stage's parts as soon as its levels are in")
eq(game.count("hide+sky"), 0, "but not the simulator's look while its own levels are still coming in")
game.shown = true
session.tick(6)
eq(game.count("hide+sky"), 1, "the simulator's look on the first tick it is all showing")
session.tick(7); session.tick(8)
eq(game.count("hide+sky"), 1, "once")
session.tick(9)
eq(game.count("hide+sky"), 2, "and once more three seconds later")

-- With a margin set, the simulator's levels must have shown for that long, and a flicker starts the wait again
session_module.SHOWN_FOR = 2
game = fake()
game.shown = false
session = new(game, { COL30_SUMMON_Odin_Free_vr = "lifestream" })
session.course_selected(ODIN, defaults)
session.course_confirmed(0, defaults)
game.inside = true
game.loaded.all = true
session.tick(1); session.tick(5)
game.shown = true
session.tick(6); session.tick(7)
eq(game.count("hide+sky"), 0, "not after one second")
game.shown = false
session.tick(8)
game.shown = true
session.tick(9); session.tick(10)
eq(game.count("hide+sky"), 0, "a flicker starts the wait again")
session.tick(11)
eq(game.count("hide+sky"), 1, "once they have shown for two seconds")
session_module.SHOWN_FOR = 0

-- What is to be hidden is found once, as soon as the simulator's levels exist, and before the look goes
game = fake()
session = new(game, { COL30_SUMMON_Odin_Free_vr = "lifestream" })
session.course_selected(ODIN, defaults)
session.course_confirmed(0, defaults)
game.inside = true
game.loaded.all = true
session.tick(1); session.tick(2); session.tick(3)
eq(game.count("prepare"), 1, "found once")
eq(game.count("hide+sky"), 1, "then hidden")
-- If the simulator is not all there yet, it is looked for again, and once more at the swap
game = fake({ parts = 3 })
session = new(game, { COL30_SUMMON_Odin_Free_vr = "lifestream" })
session.course_selected(ODIN, defaults)
session.course_confirmed(0, defaults)
game.inside = true
game.loaded.all = true
session.tick(1)
eq(game.count("prepare"), 2, "looked for at the swap as well when the first look found too little")

-- The scenery goes as soon as it exists, before the game has shown the simulator's lighting levels
game = fake()
game.shown = false
session = new(game, { COL30_SUMMON_Odin_Free_vr = "lifestream" })
session.course_selected(ODIN, defaults)
session.course_confirmed(0, defaults)
game.inside = true
game.loaded.all = true
session.tick(1)
eq(game.count("scenery"), 1, "scenery hidden while the lighting levels are still coming in")
eq(game.count("hide+sky"), 0, "the levels not yet")
session.tick(2); session.tick(3)
eq(game.count("scenery"), 1, "once")
eq(game.count("prepare"), 1, "after one full look-up")
game.shown = true
session.tick(4)
eq(game.count("hide+sky"), 1, "the levels once the game has shown them")
-- No floor yet: only the cheap question is asked, once a second
game = fake({ floor = false })
session = new(game, { COL30_SUMMON_Odin_Free_vr = "lifestream" })
session.course_selected(ODIN, defaults)
session.course_confirmed(0, defaults)
game.inside = true
game.loaded.all = true
game.shown = false
session.tick(1); session.tick(1); session.tick(2)
eq(game.count("floor?"), 2, "asked once a second")
eq(game.count("prepare"), 0, "no full look-up before the floor exists")

-- The stage's lights are held even when none of the simulator's lighting levels is showing yet: a cached stage is
-- ready before the game shows them, and they would arrive over the stage's lights (the Lifestream, 2026-11-17)
game = fake()
session = new(game, { COL30_SUMMON_Odin_Free_vr = "lifestream" })
session.course_selected(ODIN, defaults)
session.course_confirmed(0, defaults)
game.inside = true
game.loaded.all = true
game.shown = false
session.tick(1)
eq(game.count("lights held"), 1, "held before the simulator's lighting has shown")
eq(game.count("lights"), 0, "not on yet")
game.shown = true
session.tick(2)
eq(game.count("lights"), 1, "on once the simulator's look is hidden")
-- and wait for those levels to be hidden when one is
game = fake({ sim_lit = true })
session = new(game, { COL30_SUMMON_Odin_Free_vr = "lifestream" })
session.course_selected(ODIN, defaults)
session.course_confirmed(0, defaults)
game.inside = true
game.loaded.all = true
game.shown = false
session.tick(1); session.tick(2)
eq(game.count("lights held"), 1, "held while the simulator's lighting shows")
eq(game.count("lights"), 0, "not on yet")
game.shown = true
session.tick(3)
eq(game.count("hide+sky"), 1, "the simulator's levels hidden")
eq(game.count("lights"), 1, "then the stage's lights")
-- and are not held for ever if the simulator's lighting never all shows
game = fake({ sim_lit = true })
session = new(game, { COL30_SUMMON_Odin_Free_vr = "lifestream" })
session.course_selected(ODIN, defaults)
session.course_confirmed(0, defaults)
game.inside = true
game.loaded.all = true
game.shown = false
session.tick(1); session.tick(5); session.tick(12)
eq(game.count("lights"), 0, "held for a while")
session.tick(13)
eq(game.count("lights"), 1, "then switched on anyway")

-- The simulator's look stays until a streamed stage's levels are in
game = fake()
session = new(game, { COL30_SUMMON_Odin_Free_vr = "lifestream" })
session.course_selected(ODIN, defaults)
session.course_confirmed(0, defaults)
game.inside = true
game.shown = true
session.tick(1); session.tick(2); session.tick(3)
eq(game.count("scenery"), 0, "scenery kept while the stage is loading")
eq(game.count("hide+sky"), 0, "lighting kept while the stage is loading")
game.loaded.all = true
session.tick(4)
eq(game.count("scenery"), 1, "scenery hidden once the stage is in")
eq(game.count("hide+sky"), 1, "and the lighting")
