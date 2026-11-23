-- When the equipment key works in Chadley's simulator. Game-free, so it can be tested offline.
--
-- The owner's rule (2026-11-20): equipment changes only from the simulator's menus (the course list, and the screens
-- after choosing a course: team, summon level, "Begin challenge?"), never once a course has started.
--
-- The simulator's menu (UEndColosseumMenu) tells us through its native events, which Lua hooks catch:
--   course list shown      OnCourseMenuSetupItem                                     -> "list"
--   course list moves      OnCourseMenuSelectedIndexChanged                          -> "list"
--   a course is chosen     OnCourseMenuPressedItem                                   -> "chosen"
--   team / level choices   OnCharaSelectMenu* / OnSummonLevelSelectMenu*             -> "team"
--   "Begin challenge?" No  OnNoButtonPressed                                         -> "team"
--   "Begin challenge?" Yes OnYesButtonPressed                                        -> "confirmed"
-- "confirmed" starts the course: from then on nothing opens (the fights, the "Get Ready" between rounds, the result
-- screen) until one of the simulator's menus shows again.
local M = {}

local Course = {}
Course.__index = Course

function M.new()
    return setmetatable({ armed = false, chosen = false, started = false, last_event = nil, last_at = nil }, Course)
end

function Course:event(kind, now)
    self.last_event, self.last_at = kind, now
    if kind == "confirmed" then
        self.armed, self.chosen, self.started = false, false, true
    elseif kind == "chosen" or kind == "team" then
        self.armed, self.chosen, self.started = true, true, false
    elseif kind == "list" then
        self.armed, self.chosen, self.started = true, false, false
    end
end

-- Forget the menu (it was seen gone, or a fight started). A started course stays started.
function Course:reset()
    self.armed, self.chosen = false, false
end

-- Whether a course is running: after "Begin challenge?" Yes, or any fight.
function Course:running(view)
    return self.started or (view ~= nil and view.in_battle == true)
end

-- view = { menu_visible = bool|nil, pause_closed = bool|nil, in_battle = bool|nil, busy = bool }
-- settings = { course_flow = "course_list" | "after_course" | "off" }
-- Returns true, or false and the reason.
function Course:can_open(view, settings)
    local mode = settings and settings.course_flow or "course_list"
    if mode == "off" then return false, "off" end
    if self:running(view) then return false, "course started" end
    if not self.armed then return false, "no simulator menu" end
    if mode == "after_course" and not self.chosen then return false, "no course chosen" end
    if view.menu_visible == false then return false, "simulator menu hidden" end
    if view.pause_closed == false then return false, "another menu is open" end
    if view.busy then return false, "already open" end
    return true
end

-- Edge detection for a held pad button: true once per press (down after up).
function M.new_button()
    return { down = false }
end
function M.pressed(button, down_now)
    local was = button.down
    button.down = down_now == true
    return button.down and not was
end

return M
