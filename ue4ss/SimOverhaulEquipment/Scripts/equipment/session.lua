-- One visit to the game's main menu, opened by us. Game-free, so it can be tested offline.
--
-- What it handles (docs/workstreams/equipment.md, seen in game 2026-11-20):
--   * The menu is opened with UEndMenuAPI.ShowPauseMenu(ctx, Normal). Esc's own route also sets bit 0 of
--     AEndGameState.GamePause while the menu is up; without it the close stalls half-way. We set it at open.
--   * If the bit drops while the menu is still up (the battle clears it), the close would stall again, so after
--     STALL seconds at 0 we set it once more.
--   * Once IsPauseMenuClosed() turns true the game normally clears the bit itself. If it is still set LINGER seconds
--     later, we clear it, or the game would stay paused.
--
-- tick() takes plain readings and returns a list of actions for the caller to apply:
--   "set_bit", "clear_bit", "finished".
local M = {}

M.STALL = 0.5        -- seconds the pause bit may read 0 while the menu is up before it is set again
M.LINGER = 0.6       -- seconds the pause bit may stay set after the menu closed before it is cleared
M.APPEAR = 3.0       -- seconds the menu has to appear before we give up on it
M.MAX_REASSERT = 40  -- a safety cap: never fight the game for longer than this

local Session = {}
Session.__index = Session

function M.new(now, mode)
    return setmetatable({
        state = "open",
        mode = mode or "menu",
        opened_at = now,
        seen_open = false,
        zero_since = nil,
        closed_at = nil,
        reasserts = 0,
        cleared = false,
        result = nil,
    }, Session)
end

-- closed: IsPauseMenuClosed() (true/false/nil when unreadable); bit: GamePause & 1 (0/1/nil when unreadable).
function Session:tick(now, closed, bit)
    local actions = {}
    if self.state == "done" then return actions end

    if self.state == "open" then
        if closed == false then
            self.seen_open = true
            if bit == 0 then
                self.zero_since = self.zero_since or now
                if now - self.zero_since >= M.STALL and self.reasserts < M.MAX_REASSERT then
                    actions[#actions + 1] = "set_bit"
                    self.reasserts = self.reasserts + 1
                    self.zero_since = nil
                end
            else
                self.zero_since = nil
            end
        elseif closed == true then
            if self.seen_open then
                self.state = "closing"
                self.closed_at = now
            elseif now - self.opened_at >= M.APPEAR then
                self.state = "done"
                self.result = "never_opened"
                if bit == 1 then actions[#actions + 1] = "clear_bit" end
                actions[#actions + 1] = "finished"
                return actions
            end
        end
    end

    if self.state == "closing" then
        if bit == 1 and not self.cleared then
            if now - self.closed_at >= M.LINGER then
                actions[#actions + 1] = "clear_bit"
                self.cleared = true
                self.state = "done"
                self.result = "closed"
                actions[#actions + 1] = "finished"
            end
        else
            self.state = "done"
            self.result = "closed"
            actions[#actions + 1] = "finished"
        end
    end
    return actions
end

function Session:active() return self.state ~= "done" end

return M
