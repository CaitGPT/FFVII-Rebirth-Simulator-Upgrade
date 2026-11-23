-- One simulator visit: offer stages when a course is selected; when the course is confirmed, bring the chosen stage
-- to the simulator (or, with route = move, the simulator to the stage); dress it once the game is in the simulator;
-- put everything back afterwards. Game calls go through `game` (game.lua), so this file is tested offline with a
-- fake (tests/session_test.lua).
local M = {}

M.ARM_TIMEOUT = 90    -- seconds to wait for the simulator after a course is confirmed
M.LEAVE_GRACE = 3     -- seconds out of the simulator before the visit counts as over
M.REDRESS_AFTER = 3   -- seconds after dressing to do it once more (the stage's own set-up can undo the first)
M.STREAM_PATIENCE = 30 -- seconds in the simulator before unloaded stage levels are reported
M.SHOWN_FOR = 0       -- extra seconds the simulator's own levels must all have been showing before they are touched
M.LIGHTS_PATIENCE = 12 -- seconds to hold the stage's lights for the simulator's lighting to show and be hidden
M.DRESSING_PARTS = 18 -- what the simulator's own look is made of when it is fully in (scenery, skyline, rim collision)
M.LOADER_IDLE = 1     -- seconds the package loader must have been idle before anything searches the game's objects
M.BLIND_SETTLE = 12   -- seconds to wait instead when there is no helper to ask
M.REACTIVATE_AFTER = 5 -- seconds after showing a streamed stage's hidden parts to do it once more
M.REQUEST_BATCH = 48  -- level requests outstanding at once: the helper holds at most 64 unanswered and refuses the
                      -- rest ("queue_full"), which left the Temple's last three levels, its sky among them, unloaded.
                      -- Unloads count too: releasing its 67 at once left those three loaded, and the sky's fog, sun
                      -- and post-process then whitened every stage after it (2026-11-18).
M.RELEASE_PATIENCE = 30 -- seconds an unload may go unanswered before it stops holding a place in the batch
M.RELEASE_IDLE = 4    -- seconds the game's loader must have been idle after a visit before its levels are unloaded
M.GC_SPREAD_SECONDS = 70 -- seconds the spread-out garbage collection stays on after the last unload (the engine purges every 61 s)
M.HOLD_PATIENCE = 40  -- seconds after arrival the black screen may wait for a stage to load and be set up
M.ANSWER_PATIENCE = 10 -- seconds after arrival with no answer at all from the level helper before the visit goes on
                       -- as the plain simulator (two Steam 1.005 players, 2026-11-22: the helper took the requests
                       -- and answered none, and the black screen waited the full HOLD_PATIENCE)
M.ANSWER_IDLE = 3     -- ...and only once the game's loader has been idle this long: the helper may keep an unload
                      -- waiting while the game loads, but answers at once when it is idle
M.BLACK_AFTER = 1     -- seconds after the stage is fully set up before the black screen fades out
M.BLACK_FADE = 0.5    -- seconds the black screen takes to fade out

-- deps: stages, catalogue, game, choices (table, edited in place), save_choices(choices), log(message)
function M.new(deps)
    local stages, catalogue, game = deps.stages, deps.catalogue, deps.game
    local choices = deps.choices or {}
    local log = deps.log or function() end
    local self = { state = "idle" }

    -- The simulator volume of the world that is loaded, and everything the unlock rules ask about.
    local function look()
        local volume, continent
        for _, candidate in ipairs(game.vr_volumes(catalogue.vr_stage.volume_label)) do
            local c = stages.continent_of(candidate.name, catalogue.vr_stage)
            if c == "EASTC" or c == "WESTC" then
                if volume then return nil, nil, "two simulator volumes loaded" end
                volume, continent = candidate, c
            end
        end
        if not volume then return nil, nil, "no simulator volume here" end
        return volume, {
            continent = continent,
            flag = game.flag,
            progress = game.progress(),
            cleared = game.cleared(),
            can_stream = game.can_stream(),
        }
    end

    -- Unloads waiting to be sent, and those sent but not answered yet (name -> when sent). Kept across visits, so a
    -- large stage finishes unloading after the visit is over.
    self.releasing, self.release_sent = {}, {}

    local function releases_outstanding(now)
        now = now or os.time()
        local n = 0
        for name, at in pairs(self.release_sent) do
            if game.stream_state(name) ~= "loaded" or now - at >= M.RELEASE_PATIENCE then
                self.release_sent[name] = nil
            else
                n = n + 1
            end
        end
        return n
    end

    -- Level streaming's budgets are raised while a stage loads or unloads (game.fast_streaming) and put back after.
    local function fast_streaming(on)
        if not game.fast_streaming or (self.streaming_fast == true) == on then return end
        self.streaming_fast = on
        log("fast streaming\t" .. (on and "on" or "off") .. "\t" .. tostring(game.fast_streaming(on)))
    end

    -- Unloads after a visit run in the background (game.background_unload) and stay switched on for GC_SPREAD_SECONDS
    -- after the last one is answered, so the engine's purge of those levels is spread out too.
    local function background(on)
        if not game.background_unload or (self.gc_spread == true) == on then return end
        self.gc_spread, self.gc_off_at = on or nil, nil
        log("background unload\t" .. (on and "on" or "off") .. "\t" .. tostring(game.background_unload(on)))
    end

    local function flush_releases(now)
        if #self.releasing == 0 and (next(self.release_sent) == nil or releases_outstanding(now) == 0) then
            if self.state == "idle" and self.streaming_fast then fast_streaming(false) end
            if self.gc_spread and now then
                self.gc_off_at = self.gc_off_at or now + M.GC_SPREAD_SECONDS
                if now >= self.gc_off_at then background(false) end
            end
            return
        end
        if now and self.released_at == now then return end
        -- After a visit the unloads wait for the game's own trip back to finish (its loader idle a while): sent at once
        -- they slowed it (leaving the Temple: 59 s back to the course list against 43 s from the plain simulator).
        if self.release_hold then
            if not now then return end
            self.release_hold_since = self.release_hold_since or now
            if not game.settled(now, self.release_hold_since, M.RELEASE_IDLE, M.RELEASE_IDLE + 10) then return end
            self.release_hold, self.release_hold_since = nil, nil
            log("unloading\t" .. #self.releasing .. " levels")
            -- In the background, at the game's own budgets: the player is at the course list now.
            fast_streaming(false)
            background(true)
        end
        self.released_at = now
        local outstanding = releases_outstanding(now)
        while #self.releasing > 0 and outstanding < M.REQUEST_BATCH do
            local name = self.releasing[1]
            if not game.stream_release(name) then break end
            table.remove(self.releasing, 1)
            self.release_sent[name] = now or os.time()
            outstanding = outstanding + 1
        end
    end

    local function restore(why)
        if self.plan then
            local sent = self.sent or #self.plan
            for i = 1, sent do self.releasing[#self.releasing + 1] = self.plan[i].name end
            self.release_hold = true
            log("restore\t" .. why .. "\treleased " .. sent .. " levels")
        elseif self.volume and self.original then
            local ok = game.set_target(self.volume, self.original.location, self.original.yaw)
            log("restore\t" .. why .. "\ttarget " .. (ok and "restored" or "NOT restored"))
        else
            log("restore\t" .. why)
        end
        if self.dressed then game.set_dressing_hidden(catalogue.vr_stage, false, self.sky_hidden) end
        if game.forget_visit then game.forget_visit() end
        self.state, self.stage, self.volume, self.original, self.plan = "idle", nil, nil, nil, nil
        self.sent, self.topped_at = nil, nil
        self.dressed, self.sky_hidden, self.left_at, self.redress_at, self.arrived_at, self.ready = nil, nil, nil, nil, nil, nil
        self.dressed_once, self.activated_at, self.reactivated = nil, nil, nil
        self.shown_since, self.shown_checked_at, self.waiting_logged = nil, nil, nil
        self.prepared, self.prepared_at, self.prepare_tries = nil, nil, nil
        self.lights_waiting = nil
        if self.fight_held and game.hold_fight then game.hold_fight(false) end
        if game.restore_render_settings then game.restore_render_settings() end
        if self.blacked and game.black_screen then game.black_screen(false, 0) end
        self.blacked, self.dressed_at, self.fight_held, self.centre = nil, nil, nil, nil
        self.acks_before, self.answered, self.unanswered = nil, nil, nil
    end

    -- The stage's light environment, then its own look (lamp, render settings): after its
    -- lights are on, and again whenever they are shown again.
    local function light_up()
        if self.stage.light_environment and game.apply_light_environment then
            log("light environment\t" .. tostring(game.apply_light_environment(self.stage)))
        end
        if game.apply_stage_look and (self.stage.lamp or self.stage.render_settings) then
            log("look\t" .. tostring(game.apply_stage_look(self.stage, self.centre)))
        end
    end

    local function dress(steps)
        if self.plan then
            -- A streamed stage brings its own sky when it lists one; then the simulator's sky goes too. An indoor stage
            -- has no sky, and the simulator's (its light and post-process) washes it out (the mine, 2026-11-17).
            self.sky_hidden = self.stage.sky_level ~= nil or self.stage.indoors == true
        elseif steps.unhide then
            log("unhide\t" .. tostring(game.show_hidden_levels(self.volume)))
        end
        if steps.dressing then
            log("dressing\t" .. tostring(game.set_dressing_hidden(catalogue.vr_stage, true, self.sky_hidden)))
            self.dressed = true
            -- The simulator's pillars and walls would be invisible walls inside the stage; a stage with its own floor
            -- also stands on that alone, not on the simulator's flat floor running past its edges.
            if self.plan and game.drop_simulator_collision then
                log("collision off\t" .. tostring(game.drop_simulator_collision(self.stage.own_ground == true)))
            end
        end
        if not self.plan and steps.sky and self.stage.sky then
            log("sky\t" .. self.stage.sky.volume .. "\t" .. tostring(game.switch_sky(self.stage.sky)))
        end
    end

    -- The player selected a course in the menu (its title is on the info panel). Returns the course and what the
    -- picker should offer: options ({ id, name }) and the index to start on. No options means no picker.
    function self.course_selected(title, settings)
        if self.state ~= "idle" then return nil, {}, 1 end
        self.titles = self.titles or stages.title_index(catalogue, game.text)
        local course = stages.course_by_title(self.titles, title)
        self.course = course
        if not course then
            log("select\tunrecognised\t" .. tostring(title))
            return nil, {}, 1
        end
        if not settings.enabled or course.excluded then return course, {}, 1 end
        local _, context, why = look()
        if not context then
            log("select\t" .. course.key .. "\t" .. why)
            return course, {}, 1
        end
        local options, left_out = stages.options(catalogue, course, context, settings, choices)
        log("select\t" .. course.key .. "\t" .. #options .. " options\t" .. table.concat(left_out, "; "))
        if #options < 2 then return course, {}, 1 end
        return course, options, stages.selected_index(options, course, choices)
    end

    -- The player picked a stage for a course. Remembered until changed.
    function self.choose(course, id)
        choices[course.key] = id
        if id ~= stages.VANILLA then choices[stages.LAST_KEY] = id end
        if deps.save_choices then deps.save_choices(choices) end
        log("choice\t" .. course.key .. "\t" .. id)
    end

    -- The player confirmed the selected course.
    function self.course_confirmed(now, settings)
        if self.state ~= "idle" then return nil, "visit in progress" end
        if game.forget_visit then game.forget_visit() end
        -- A last visit's levels still waiting to unload go now, whatever comes next: they must not show in this one.
        if self.release_hold then
            self.release_hold, self.release_hold_since = nil, nil
            log("unloading\t" .. #self.releasing .. " levels\tbefore the next visit")
            fast_streaming(true)
            flush_releases(now)
        end
        local volume, context, why = look()
        if not volume then return nil, why end
        local stage
        stage, why = stages.chosen(catalogue, self.course, context, settings, choices)
        log("confirm\t" .. (self.course and self.course.key or "?") .. "\t" .. (stage and stage.id or "vanilla") .. "\t" .. tostring(why))
        if not stage then return nil, why end
        local steps = stages.steps(settings)
        local original = game.get_target(volume)
        if not original then return nil, "simulator volume unreadable" end
        if stages.route_of(stage, settings) == "stream" then
            self.serial = (self.serial or 0) + 1
            local plan, asked = stages.stream_plan(stage, original.location, settings, self.serial), 0
            -- The first batch now; the rest as the helper answers (see top_up).
            local first = math.min(#plan, M.REQUEST_BATCH)
            for i = 1, first do
                if game.stream_request(plan[i]) then asked = asked + 1 end
            end
            if asked < first then
                for i = 1, first do game.stream_release(plan[i].name) end
                return nil, "level request refused"
            end
            self.plan, self.sent = plan, first
            self.acks_before, self.answered, self.unanswered = game.ack_count and game.ack_count() or nil, nil, nil
            log(string.format("stream\t%s\t%d levels\t%.0f\t%.0f\t%.0f", stage.id, #plan,
                plan[1].location.X, plan[1].location.Y, plan[1].location.Z))
        elseif steps.relocate then
            local location, yaw = stages.target(stage, settings)
            if not game.set_target(volume, location, yaw) then
                game.set_target(volume, original.location, original.yaw)
                return nil, "target not accepted"
            end
            self.original = original
            log(string.format("relocate\t%s\t%.0f\t%.0f\t%.0f", stage.id, location.X, location.Y, location.Z))
        end
        self.state, self.stage, self.volume, self.centre = "armed", stage, volume, original.location
        self.armed_at, self.settings = now, settings
        -- Only once armed: raising them runs game code that can re-enter this mod's tick, which while "idle" would
        -- put them straight back (seen 2026-11-18).
        if self.plan then fast_streaming(true) end
        return stage, why
    end

    -- Sends more of a large stage's level requests as the helper answers the earlier ones, keeping at most
    -- REQUEST_BATCH unanswered. Once a second.
    local function top_up(now)
        if not self.plan or self.unanswered or (self.sent or #self.plan) >= #self.plan or self.topped_at == now then return end
        self.topped_at = now
        local waiting = 0
        for i = 1, self.sent do
            if game.stream_state(self.plan[i].name) == nil then waiting = waiting + 1 end
        end
        waiting = waiting + releases_outstanding(now)
        while self.sent < #self.plan and waiting < M.REQUEST_BATCH do
            if not game.stream_request(self.plan[self.sent + 1]) then break end
            self.sent, waiting = self.sent + 1, waiting + 1
        end
    end

    -- Whether every level of a streamed stage is loaded and showing. Reported once each way.
    local function watch_stream(now)
        if not self.plan or self.ready or self.unanswered or self.watched_at == now then return end
        self.watched_at = now -- once a second is plenty: each look reads the helper's file
        -- No answer at all from the level helper: after ANSWER_PATIENCE, with the game's loader idle a while, the visit
        -- goes on as the plain simulator (the black screen lifts below) and the stage is not set up later.
        if not self.answered and self.acks_before and game.ack_count then
            if game.ack_count() > self.acks_before then
                self.answered = true
            elseif now - self.arrived_at >= M.ANSWER_PATIENCE and (game.loader_idle_for(now) or 0) >= M.ANSWER_IDLE then
                self.unanswered = true
                log("stream\tno answer from the level helper after " .. (now - self.arrived_at) .. " s\tplain simulator"
                    .. (game.helper_summary and ("\t" .. game.helper_summary(now)) or ""))
                return
            end
        end
        local missing = {}
        for _, item in ipairs(self.plan) do
            if not game.stream_ready(item.name) then
                -- With the helper's answer, so a player's log says why (2026-11-22: four levels, no reason given).
                local detail = game.stream_detail and (" (" .. game.stream_detail(item.name) .. ")") or ""
                missing[#missing + 1] = item.package .. detail
            end
        end
        if #missing == 0 then
            self.ready = true
            log("stream\tready\t" .. (now - self.arrived_at) .. " s after arrival")
        elseif not self.reported and now - self.arrived_at >= M.STREAM_PATIENCE then
            self.reported = true
            log("stream\tNOT loaded after " .. M.STREAM_PATIENCE .. " s\t" .. table.concat(missing, "; ")
                .. (game.helper_summary and ("\t" .. game.helper_summary(now)) or ""))
        end
    end

    -- Call a few times a second while not idle.
    function self.tick(now)
        flush_releases(now)
        if self.state == "idle" then return end
        top_up(now)
        local inside = game.in_simulator()
        if self.state == "armed" then
            if inside then
                self.arrived_at, self.reported = now, nil
                self.arrived_clock = game.clock and game.clock() or nil
                self.state = "live"
                -- A streamed stage arrives behind a black screen of the game's own, lifted once it is fully set up:
                -- the player never sees the simulator, a half-made stage or the swap (owner, 2026-11-18).
                if self.plan and game.black_screen and game.black_screen(true) then
                    self.blacked = true
                    log("black screen	on")
                end
            else
                if now - self.armed_at > M.ARM_TIMEOUT then restore("simulator never started") end
                return
            end
        end
        if inside then
            self.left_at = nil
            -- Nothing searches the game's objects until the load that brought the party here has finished.
            local settled = game.settled(now, self.arrived_at, M.LOADER_IDLE, M.BLIND_SETTLE)
            local function since_arrival()
                local clock = game.clock and game.clock()
                if clock and self.arrived_clock then return string.format("%.1f s", (clock - self.arrived_clock) / 1000) end
                return (now - self.arrived_at) .. " s"
            end
            watch_stream(now)
            -- (Holding the game's loading screen by keeping one of its levels hidden was tried on 2026-11-18 and dropped:
            -- with it held, one of the Shinra Manor's levels did not load until it was let go, 41 s in. The black screen
            -- below hides the swap by itself.)
            -- The stage's own parts first: stretched, and its sun, fog and hidden meshes shown, as soon as its levels
            -- are in. That is the heavy work, and it touches nothing of the simulator's, so it need not wait for the
            -- simulator; done early, it is not all waiting to happen at the moment the simulator's look goes. Shown
            -- once more a little later in case the stage's own set-up hid something again.
            if settled and self.plan and self.ready then
                if not self.activated_at then
                    self.activated_at = now
                    if self.stage.fit then log("fit\t" .. tostring(game.fit_stage(self.stage, self.plan))) end
                    if self.stage.move_brightness_probes and game.move_brightness_probes then
                        log("brightness probes\t" .. tostring(game.move_brightness_probes(self.stage, self.plan)))
                    end
                    -- The stage's lights go on only once the simulator's lighting levels have been hidden (below), never
                    -- before: on a later visit the stage's levels are cached and ready before the game has even shown
                    -- the simulator's lighting, which then arrives over the stage's lights and leaves it dull (the
                    -- Lifestream, 2026-11-17, ready "0 s after arrival").
                    local lights_now = self.dressed_once == true
                    local shown, waiting = game.activate_stage(self.stage, lights_now)
                    self.lights_waiting = (waiting or 0) > 0
                    log("activate\t" .. tostring(shown) .. (self.lights_waiting and ("\tlights wait: " .. tostring(waiting)) or "")
                        .. "\t" .. since_arrival() .. " after arrival")
                    if not self.lights_waiting then
                        light_up()
                    end
                elseif not self.reactivated and now - self.activated_at >= M.REACTIVATE_AFTER then
                    self.reactivated = true
                    log("activate again\t" .. tostring(game.reactivate_stage(self.stage)))
                    if not self.lights_waiting then
                        light_up()
                    end
                    if #self.releasing == 0 and next(self.release_sent) == nil then fast_streaming(false) end
                end
            end
            -- The simulator's own look goes on the first tick on which the game has all of its own levels showing,
            -- and not before: a level told to hide while the game is still bringing it in holds up the start, and an
            -- idle loader alone does not mean it is in (on a later visit its levels are cached).
            -- The simulator's scenery (floor, blocks, skyline, rim collision) goes as soon as it exists, behind the
            -- loading screen: once a second one cheap search asks whether the floor is there; when it is, everything
            -- is found and hidden. Hiding actors changes no level's state, so it cannot hold the start up.
            -- A streamed stage's own levels must be in first: a large stage (the Shinra Manor's 23 levels) takes longer
            -- to load than the simulator, and hiding the simulator before it is there leaves an empty scene.
            local stage_in = not self.plan or self.ready
            if settled and stage_in and not self.prepared and self.prepared_at ~= now and (self.prepare_tries or 0) < 40 then
                self.prepared_at, self.prepare_tries = now, (self.prepare_tries or 0) + 1
                if game.scenery_present(catalogue.vr_stage) then
                    local found = game.prepare_dressing(catalogue.vr_stage)
                    if found >= M.DRESSING_PARTS then
                        self.prepared = true
                        local steps = stages.steps(self.settings)
                        local hidden = steps.dressing and game.set_dressing_hidden(catalogue.vr_stage, true, false, "scenery") or 0
                        if steps.dressing then self.dressed = true end
                        log("scenery\t" .. tostring(hidden) .. " of " .. tostring(found) .. "\t" .. since_arrival() .. " after arrival")
                    end
                end
            end
            if settled and stage_in and not self.dressed_once then
                local shown, count = game.simulator_shown(catalogue.vr_stage, now)
                if shown then self.shown_since = self.shown_since or now else self.shown_since = nil end
                if not shown and not self.waiting_logged and now - self.arrived_at >= 20 then
                    self.waiting_logged = true
                    log("waiting\tthe simulator's own levels are not all showing\t" .. tostring(count) .. " exist")
                end
                if self.shown_since and now - self.shown_since >= M.SHOWN_FOR then
                    self.dressed_once, self.dressed_at = true, now
                    -- Not everything was found beforehand: look again now (slow, but right).
                    if not self.prepared then game.prepare_dressing(catalogue.vr_stage) end
                    log("settled\t" .. since_arrival() .. " after arrival")
                    dress(stages.steps(self.settings))
                    self.redress_at = now + M.REDRESS_AFTER
                    if self.lights_waiting then
                        self.lights_waiting = nil
                        log("lights\t" .. tostring(game.show_stage_lights()))
                        light_up()
                    end
                end
            elseif self.redress_at and now >= self.redress_at then
                self.redress_at = nil
                dress(stages.steps(self.settings))
            end
            -- The simulator's lighting never all showed: do not leave the stage unlit.
            if self.lights_waiting and self.activated_at and now - self.activated_at >= M.LIGHTS_PATIENCE then
                self.lights_waiting = nil
                log("lights\t" .. tostring(game.show_stage_lights()) .. "\tthe simulator's lighting never all showed")
                light_up()
            end
            -- The black screen lifts once the stage is in, set up and lit, and the simulator's look is gone; or, if that
            -- never happens, after HOLD_PATIENCE plus BLACK_AFTER, so the player is never left in the dark.
            if self.blacked then
                -- A fight that begins behind the black screen is held still until it lifts (players on faster
                -- machines than ours saw the fight start while it was up).
                local fighting = game.in_battle and game.in_battle()
                local done = self.dressed_once and self.activated_at and not self.lights_waiting
                    and now - self.dressed_at >= M.BLACK_AFTER
                if fighting and not self.fight_held and not done and game.hold_fight then
                    self.fight_held = game.hold_fight(true)
                    if self.fight_held then log("fight held\t" .. since_arrival() .. " after arrival") end
                end
                local overdue = now - self.arrived_at >= M.HOLD_PATIENCE + M.BLACK_AFTER or self.unanswered
                if done or overdue then
                    self.blacked = nil
                    log("black screen\toff\t" .. since_arrival() .. " after arrival" .. (done and "" or "\tgave up waiting"))
                    if self.fight_held then
                        self.fight_held = nil
                        log("fight released\t" .. tostring(game.hold_fight(false)))
                    end
                    game.black_screen(false, M.BLACK_FADE)
                end
            end
        else
            self.left_at = self.left_at or now
            if now - self.left_at >= M.LEAVE_GRACE then restore("left the simulator") end
        end
    end

    function self.busy() return self.state ~= "idle" end
    -- Unloads still to send or still unanswered: keep ticking until they are done.
    -- Also true while the streaming budgets are still raised after a visit, so a last tick puts them back.
    function self.unloading()
        return #self.releasing > 0 or releases_outstanding(nil) > 0 or (self.state == "idle" and self.streaming_fast == true)
            or self.gc_spread == true
    end
    function self.stream_ready() return self.ready == true end

    return self
end

return M
