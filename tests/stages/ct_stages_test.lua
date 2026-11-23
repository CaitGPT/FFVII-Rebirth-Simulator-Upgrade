-- Simulator Upgrade: Custom Training is offered every stage (owner, 2026-11-21), and stages_api tells the other parts
-- which stage a fight is on.
local stages = require("stages.rules")
local catalogue = require("stages.data")
local api = require("stages_api")

local index = stages.title_index(catalogue, nil)
local by_id = stages.course_by_title(index, "$menu_Colosseum_CourseTitle_COL99_SimOverhaul_CT_Custom_vr")
local by_text = stages.course_by_title(index, "Custom Training")
assert(by_id and by_id.key == "COL99_SimOverhaul_CT_Custom_vr", "Custom Training found by its title id")
assert(by_text == by_id, "and by the title Custom Training puts on screen")
assert(by_id.needs_m == 0 and by_id.excluded == false, "no room limit, not excluded")

-- No stage is too small for it: of the reasons blocked() gives, "too small" never appears.
local context = { continent = "EASTC", flag = function() return true end, progress = 99999, can_stream = true }
local settings = { experimental = false, require_unlock = false }
for _, stage in ipairs(catalogue.stages) do
    local why = stages.blocked(stage, by_id, context, settings)
    assert(why ~= "too small", stage.id .. " offered to Custom Training")
end

-- stages_api: nil until the Stages part sets a provider, nil on the plain arena, the stage's room on a stage.
assert(api.current() == nil, "no provider: nil")
local visiting = nil
api._set_provider(function() return visiting end)
assert(api.current() == nil, "plain arena: nil")
visiting = { id = "space_rock", name = "Edge of Creation", radius_m = 40.0, levels = {} }
local now = api.current()
assert(now.id == "space_rock" and now.name == "Edge of Creation" and now.radius_m == 40.0, "the stage and its room")
api._set_provider(function() error("broken") end)
assert(api.current() == nil, "a failing provider reads as nil")
api._set_provider(nil)
