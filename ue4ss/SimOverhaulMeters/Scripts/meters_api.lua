-- The meters' interface for the other parts of Simulator Overhaul (agreed with custom-training, 2026-11-21):
--   local meters = require("meters_api")     -- pcall it: absent when the meters part isn't installed
--   meters.state()     -> { meter = "damage" | "taken" | "heal", label = "Damage" | "Tanking" | "Healing", visible }
--   meters.act(action) -> true, or false when not understood. Actions: "next", "prev", "clear", "stagger", "toggle",
--                         "show", "hide", "meter=damage|taken|heal". Carried out on the meters' next tick.
-- Custom Training's settings menu (LB+RB or F7) offers them, which is how a pad reaches the meters.
-- During development the parts are separate Lua states: Custom Training writes the actions, one per line, to
-- meters-command.txt in this mod's folder, and reads meters-state.txt, which this mod rewrites after every change.
local controls = require("meters_controls")

local M = { version = 1 }
local queue, current = {}, nil

function M.bind(c) current = c end

function M.state()
    if not current then return { meter = "damage", label = controls.LABELS.damage, visible = false } end
    return current:state()
end

local KNOWN = { next = true, prev = true, clear = true, stagger = true, toggle = true, show = true, hide = true }

function M.act(action)
    action = tostring(action or "")
    local meter = action:match("^meter=(%w+)$")
    if not (KNOWN[action] or (meter and controls.LABELS[meter])) then return false end
    queue[#queue + 1] = action
    return true
end

-- main.lua takes the queued actions on the game thread.
function M.take()
    local list = queue
    queue = {}
    return list
end

return M
