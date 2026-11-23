-- Simulator Stages, for the other parts of Simulator Upgrade: which stage the current simulator fight is on.
--
--   local ok, stages_api = pcall(require, "stages_api")
--   local stage = ok and stages_api.current() or nil
--
-- current() returns nil on the plain simulator arena (or when the Stages part is off), otherwise
-- { id = "space_rock", name = "Edge of Creation", radius_m = 40.0 }: radius_m is the room the stage has around the
-- arena's centre, the same figure Stages compares with a course's needs_m. Custom Training uses it to refuse an
-- opponent or round that needs more room than the stage has (owner, 2026-11-21: filter opponents, not stages).
-- File reads and plain Lua only: safe to call from any thread.
local M = {}

local provider = nil

-- Called once by the Stages part (stages_main.lua) with a function returning the stage table or nil.
function M._set_provider(fn) provider = fn end

function M.current()
    if not provider then return nil end
    local ok, stage = pcall(provider)
    if not ok or type(stage) ~= "table" then return nil end
    return { id = stage.id, name = stage.name, radius_m = stage.radius_m }
end

return M
