-- The pad chord that opens the menu in a fight: both shoulders held together (Custom Training's chord). Only read
-- while no window is open: an open choice window has the input focus, so held keys can't be read then (seen in the
-- game, 2026-11-21); the window's own cursor, confirm and cancel do everything inside it. Tested offline.
local M = {}

M.OPEN_CHORD = { "Gamepad_LeftShoulder", "Gamepad_RightShoulder" }

-- down: set of engine key names held now.
function M.chord(down)
    for _, name in ipairs(M.OPEN_CHORD) do if not down[name] then return false end end
    return true
end

return M
