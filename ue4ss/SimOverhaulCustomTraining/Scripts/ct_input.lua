-- Keys for the settings panel, without the game: which engine keys mean which panel key, presses found from the
-- keys held at each poll, with repeat for the arrows. ct_game.keys_down reads the held keys. Tested offline.
local M = {}
M.__index = M

-- Panel key -> engine keys (FKey names). The test harness can press the shoulders, D-pad up and down and the face
-- buttons in a fight, so the shoulders also cycle.
M.BINDINGS = {
    up = { "Gamepad_DPad_Up", "Gamepad_LeftStick_Up", "Up", "W" },
    down = { "Gamepad_DPad_Down", "Gamepad_LeftStick_Down", "Down", "S" },
    left = { "Gamepad_DPad_Left", "Gamepad_LeftStick_Left", "Gamepad_LeftShoulder", "Left", "A" },
    right = { "Gamepad_DPad_Right", "Gamepad_LeftStick_Right", "Gamepad_RightShoulder", "Right", "D" },
    select = { "Gamepad_FaceButton_Bottom", "Enter", "SpaceBar" },
    back = { "Gamepad_FaceButton_Right", "Escape", "BackSpace" },
    prev_kind = { "Gamepad_FaceButton_Left", "Q" },
    next_kind = { "Gamepad_FaceButton_Top", "E" },
}
-- Opening the panel in a fight with a pad: both shoulders held together.
M.OPEN_CHORD = { "Gamepad_LeftShoulder", "Gamepad_RightShoulder" }
local REPEATS = { up = true, down = true, left = true, right = true }
local REPEAT_AFTER, REPEAT_EVERY = 0.40, 0.12

function M.all_keys()
    local keys, seen = {}, {}
    for _, list in pairs(M.BINDINGS) do
        for _, k in ipairs(list) do if not seen[k] then seen[k] = true; keys[#keys + 1] = k end end
    end
    table.sort(keys)
    return keys
end

function M.new()
    -- armed: nothing counts until every key has been seen up (the opening chord is still held when the panel opens)
    return setmetatable({ held = {}, since = {}, last_repeat = {}, armed = false }, M)
end

function M:reset() self.held, self.since, self.last_repeat, self.armed = {}, {}, {}, false end

-- down: set of engine key names held now; now: seconds. Returns the panel keys pressed since the last poll.
function M:poll(down, now)
    local pressed = {}
    if not self.armed then
        if next(down) == nil then self.armed = true end
        return pressed
    end
    local order = { "up", "down", "left", "right", "select", "back", "prev_kind", "next_kind" }
    for _, key in ipairs(order) do
        local is_down = false
        for _, name in ipairs(M.BINDINGS[key]) do if down[name] then is_down = true end end
        if is_down and not self.held[key] then
            pressed[#pressed + 1] = key
            self.since[key], self.last_repeat[key] = now, now
        elseif is_down and REPEATS[key] and now - self.since[key] >= REPEAT_AFTER
            and now - self.last_repeat[key] >= REPEAT_EVERY then
            pressed[#pressed + 1] = key
            self.last_repeat[key] = now
        end
        self.held[key] = is_down
    end
    return pressed
end

function M.chord(down)
    for _, name in ipairs(M.OPEN_CHORD) do if not down[name] then return false end end
    return true
end

return M
