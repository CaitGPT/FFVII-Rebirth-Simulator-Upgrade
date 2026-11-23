-- The settings menu in the game's own choice window: opens it, shows each window ui_model asks for (each
-- list says its current value in its text), and hands the result to Custom Training (ui_ct) and the meters (ui_meters).
-- deps: game (ui_window, or a fake in tests), ct (ui_ct), meters (ui_meters, optional), keys (ui_keys module),
-- log(message), options { pause = true, chord = true, debug = false, place_cursor = false }. tick(now) runs on the game thread.
local model_module = require("ui_model")

local M = {}
M.__index = M

-- The cursor is put on the current value a moment after the window is built (the window puts it on its first row as
-- it opens), and again until it is seen there: at these seconds after the rows were found.
M.FOCUS_TRIES = { 0.15, 0.4, 0.7, 1.0 }
-- A back key acts this long (seconds) after it went down, and presses meanwhile are the same press (a held key repeats).
M.BACK_DELAY = 0.25
-- Esc pressed in the window still reaches the fight: the game opens its Pause menu once the window has gone
-- (2026-11-21, with Esc released or not). After a back key the mod leaves this long (seconds) with no window of its
-- own, closes that Pause menu if it opens (UEndMenuAPI.IsPauseMenuClosed may count the mod's window too, so it is read
-- only in the gap), then shows its next window or closes.
M.BACK_GAP = 0.5
-- B on the pad is back too. The game's window doesn't close on it, and the player controller reads no key while the
-- window is open, so it is read through the game's system input (game.system_keys_down), pressed after being up.
M.PAD_BACK = { "Gamepad_FaceButton_Right" }

function M.new(deps)
    return setmetatable({
        game = deps.game, ct = deps.ct, meters = deps.meters, log = deps.log or function() end,
        options = deps.options or {}, keys = deps.keys,
        screen = nil, window = nil, rows = nil, list = nil, paused_by_us = false,
        requested = false, picked = nil, chord_seen = nil, backed = nil,
    }, M)
end

function M:is_open() return self.screen ~= nil end

-- F7, the pad chord or a development command: open, or close when open.
function M:request() self.requested = true end
-- Esc or Backspace on the keyboard: back, as B is on the pad, which closes the game's window with no choice (Back on
-- a list, Cancel on the main window). The game's window does not close on these keys itself.
function M:back() if self.screen and not self.backed then self.backed = self.now or 0 end end
-- Development: close the open window as if its row n (0-based) had been confirmed (-1: cancelled).
function M:pick(n) self.picked = n end

function M:show()
    local w = self.model:window()
    local window, err = self.game.show(w.body, w.options)
    if not window then self.log("window\t" .. w.screen .. "\tnot shown: " .. tostring(err)); self:close("no window"); return false end
    self.screen, self.window, self.rows, self.list = w.screen, window, nil, nil
    -- Placing the cursor is off unless options.place_cursor: none of the three ways moved the window's cursor, and moving
    -- the keyboard focus off the window let Esc through to the fight's Pause menu (2026-11-21).
    self.body_text, self.focus_wanted, self.rows_at, self.rows_missing_logged = w.body, w.focus, nil, nil
    self.focus_try = self.options.place_cursor and 1 or nil
    self.log("window\t" .. w.screen .. "\t" .. #w.options .. " rows\tfocus " .. tostring(w.focus) .. "\t" .. table.concat(w.options, " | "))
    return true
end

function M:open()
    local state = self.ct.state()
    if not state or not state.active then self.log("open\trefused: no Custom Training course running"); return end
    local lists = self.ct.lists()
    if not lists then self.log("open\trefused: no lists from Custom Training yet"); return end
    local meters = self.meters and self.meters.present() and self.meters.state() or nil
    self.model = model_module.new(lists, state, meters, { respawn = self.ct.respawn ~= nil })
    self.pad_back_was = nil -- a B already held as the menu opens is not a press
    if self.options.pause ~= false and not self.game.paused() then
        self.paused_by_us = self.game.pause(true)
    end
    local group = type(state.group) == "table" and (" group " .. table.concat(state.group, ",")) or ""
    local round = state.mode == "round" and (" round " .. tostring(state.round)) or ""
    self.log("open\t" .. tostring(state.opponent) .. " x" .. tostring(state.count) .. group .. round .. " " .. tostring(state.behaviour)
        .. " " .. tostring(state.difficulty) .. (meters and (" meter " .. tostring(meters.meter) .. " visible " .. tostring(meters.visible)) or "")
        .. "\tpaused " .. tostring(self.paused_by_us))
    self:show()
end

function M:close(why)
    if self.window and not self.game.closed(self.window) then self.game.hide(self.window) end
    self.screen, self.window, self.rows = nil, nil, nil
    if self.paused_by_us then self.game.pause(false); self.paused_by_us = false end
    if self.game.after_close then self.game.after_close() end
    self.log("close\t" .. tostring(why))
end

-- The rows of the open window, found once it has been built (the first ticks after ShowMessageWindow).
function M:find_rows(now)
    if self.rows and #self.rows > 0 then return true end
    self.opened_at = self.opened_at or now
    local rows, _, list = self.game.rows(self.window, self.body_text)
    if #rows == 0 then
        if now - self.opened_at > 2 and not self.rows_missing_logged then
            self.rows_missing_logged = true
            self.log("rows\tnone found in the window after 2 s")
        end
        return false
    end
    self.rows, self.list, self.rows_at, self.opened_at = rows, list, now, nil
    self.log("rows\t" .. #rows .. " found")
    return true
end

-- Puts the cursor on the wanted row, trying again until the window shows it there.
function M:place_cursor(now)
    local want = self.focus_wanted
    if not want or want <= 1 or not self.focus_try then return end
    local at = M.FOCUS_TRIES[self.focus_try]
    if not at then
        self.log("focus\tnot placed on row " .. want .. " (the cursor stays on row 1)")
        self.focus_try = nil
        return
    end
    if now - self.rows_at < at then return end
    local i, how = self.game.focused(self.rows, self.list)
    if i == want then
        self.log("focus\trow " .. want .. " after try " .. (self.focus_try - 1) .. " (read by " .. tostring(how) .. ")")
        self.focus_try = nil
        return
    end
    local method = self.game.focus(self.rows, self.list, want, self.focus_try)
    self.log("focus\ttry " .. self.focus_try .. "\trow " .. want .. "\tby " .. tostring(method) .. "\twas " .. tostring(i))
    self.focus_try = self.focus_try + 1
end

function M:on_closed(choice)
    self.log("chosen\t" .. self.screen .. "\t" .. tostring(choice))
    local r = self.model:choose(choice)
    if r.kind == "show" then return self:show() end
    if r.kind == "meters_now" then
        self.log("meters\t" .. r.action .. "\t" .. tostring(self.meters and self.meters.act(r.action)))
        return self:show()
    end
    if r.kind == "respawn" then
        self:close("respawn")
        local ok, why = false, "Custom Training has no respawn"
        if self.ct.respawn then ok, why = self.ct.respawn() end
        self.log("respawn\t" .. tostring(ok) .. "\t" .. tostring(why))
        return
    end
    if r.kind == "apply" then
        self:close("apply")
        local ok, why = true, nil
        if next(r.changes) ~= nil then ok, why = self.ct.apply(r.changes) end
        local parts = {}
        for k, v in pairs(r.changes) do parts[#parts + 1] = k .. "=" .. (type(v) == "table" and table.concat(v, ",") or tostring(v)) end
        table.sort(parts)
        for _, a in ipairs(r.meters or {}) do
            parts[#parts + 1] = "meters:" .. a
            if self.meters then self.meters.act(a) end
        end
        self.log("apply\t" .. (#parts > 0 and table.concat(parts, " ") or "(nothing changed)") .. "\t" .. tostring(ok) .. "\t" .. tostring(why))
        return
    end
    return self:close(self.closing_why or "cancel")
end

-- Development: sets the draft and shows the main window again (screenshots of every state).
function M:set_draft(values)
    if not self.model then return false end
    self.model:set(values)
    if self.window and not self.game.closed(self.window) then self.game.hide(self.window) end
    self.model.screen = "main"
    return self:show()
end

-- B pressed (up, then down) while a window is open: back.
function M:watch_pad_back()
    if not self.game.system_keys_down then return end
    local down = next(self.game.system_keys_down(M.PAD_BACK)) ~= nil
    if self.options.debug and down ~= self.pad_back_seen then
        self.pad_back_seen = down
        self.log("pad back\tB " .. tostring(down))
    end
    if down and self.pad_back_was == false then self:back() end
    self.pad_back_was = down
end

-- The gap after a back key: the game's Pause menu closed if it opens.
function M:close_pause_menu()
    if self.pause_closed or not (self.game.pause_menu_open and self.game.pause_menu_open()) then return end
    self.game.hide_pause_menu()
    self.pause_closed = true
    self.log("pause menu\tclosed after the back key")
end

function M:tick(now)
    self.now = now
    if not self.screen then
        local want = self.requested
        self.requested = false
        if not want and self.options.chord ~= false and self.game.in_battle() and not self.game.paused() then
            local down = self.game.keys_down(self.keys.OPEN_CHORD)
            if self.options.debug then
                local seen = tostring(down.Gamepad_LeftShoulder == true) .. "/" .. tostring(down.Gamepad_RightShoulder == true)
                if seen ~= self.chord_seen then self.chord_seen = seen; self.log("chord keys\tLB/RB " .. seen) end
            end
            want = self.keys.chord(down)
        end
        if want then self:open() end
        return self.screen ~= nil
    end
    if self.picked then
        local n = self.picked
        self.picked = nil
        self.game.hide(self.window)
        self.log("dev\tpick " .. n .. " (development command, not a press)")
        self:on_closed(n)
        return self.screen ~= nil
    end
    if self.gap_until then
        self:close_pause_menu()
        if now < self.gap_until then return true end
        self.gap_until = nil
        self.closing_why = "back key"
        self:on_closed(nil)
        self.closing_why = nil
        -- Closing the Pause menu lets the fight run again: paused again while the menu stays open.
        if self.screen and self.paused_by_us and not self.game.paused() then self.game.pause(true) end
        return self.screen ~= nil
    end
    if self.game.closed(self.window) then
        self.backed = nil -- the window closed itself (a choice, or B): a back key pressed with it is not another back
        self:on_closed(self.game.selected(self.window))
        return self.screen ~= nil
    end
    self:watch_pad_back()
    if self.backed and now - self.backed >= M.BACK_DELAY then
        self.backed, self.gap_until, self.pause_closed = nil, now + M.BACK_GAP, false
        self.game.hide(self.window)
        self.log("back\tkey")
        return true
    end
    if self.requested then self.requested = false; self:close("toggle"); return false end
    if self:find_rows(now) then self:place_cursor(now) end
    return true
end

return M
