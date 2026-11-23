-- Offline tests for the game-free parts: the menu session, the course-flow rules and the settings.
local session = require("equipment.session")
local course = require("equipment.course")
local settings = require("equipment.settings")

local function eq(a, b, what)
    if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function has(list, item)
    for _, v in ipairs(list) do if v == item then return true end end
    return false
end

-- Session: the normal visit (field, simulator menus). The bit stays set while open; the game clears it on close.
do
    local s = session.new(0)
    eq(#s:tick(0.1, false, 1), 0, "open, bit set: nothing to do")
    eq(#s:tick(5.0, false, 1), 0, "still open")
    local a = s:tick(5.1, true, 0)
    eq(has(a, "finished"), true, "closed with the bit cleared by the game finishes")
    eq(s.result, "closed")
    eq(s:active(), false)
end

-- Session: the bit drops while the menu is up (seen in a fight): set it again after STALL, once per stall.
do
    local s = session.new(0)
    s:tick(0.1, false, 1)
    eq(#s:tick(1.0, false, 0), 0, "first zero reading starts the stall clock")
    eq(#s:tick(1.3, false, 0), 0, "not yet")
    local a = s:tick(1.6, false, 0)
    eq(has(a, "set_bit"), true, "stalled: set the bit")
    eq(s.reasserts, 1)
    eq(#s:tick(1.7, false, 0), 0, "the stall clock starts again")
end

-- Session: closed but the bit lingers: clear it after LINGER, then finish.
do
    local s = session.new(0)
    s:tick(0.1, false, 1)
    eq(#s:tick(2.0, true, 1), 0, "just closed, bit still set: wait")
    local a = s:tick(2.0 + session.LINGER, true, 1)
    eq(has(a, "clear_bit"), true, "lingering bit cleared")
    eq(has(a, "finished"), true)
    eq(s.result, "closed")
end

-- Session: the menu never appears.
do
    local s = session.new(0)
    eq(#s:tick(0.5, true, 1), 0, "not seen yet: wait")
    local a = s:tick(session.APPEAR + 0.1, true, 1)
    eq(has(a, "clear_bit"), true, "our bit is taken back")
    eq(has(a, "finished"), true)
    eq(s.result, "never_opened")
end

-- Session: unreadable values never trigger writes.
do
    local s = session.new(0)
    eq(#s:tick(1, nil, nil), 0)
    s:tick(1.1, false, nil)
    eq(#s:tick(9, false, nil), 0, "an unreadable bit is never treated as 0")
end

-- Course flow (the owner's rule: the simulator's menus only, never once a course has started).
do
    local cfg = { course_flow = "after_course" }
    local list = { course_flow = "course_list" }
    local c = course.new()
    local ok, why = c:can_open({}, cfg)
    eq(ok, false); eq(why, "no simulator menu")
    c:event("list", 1)
    ok, why = c:can_open({ menu_visible = true, pause_closed = true }, cfg)
    eq(ok, false, "after_course: not on the course list"); eq(why, "no course chosen")
    eq(c:can_open({ menu_visible = true, pause_closed = true }, list), true, "course_list: the course list")
    eq(c:can_open({ menu_visible = true, pause_closed = true }, {}), true, "the default is course_list")
    c:event("chosen", 2)
    eq(c:can_open({ menu_visible = true, pause_closed = true }, cfg), true, "after choosing a course")
    eq(c:can_open({ menu_visible = nil, pause_closed = true }, cfg), true, "unknown visibility does not block")
    ok, why = c:can_open({ menu_visible = true, pause_closed = false }, cfg)
    eq(ok, false); eq(why, "another menu is open")
    ok, why = c:can_open({ menu_visible = true, pause_closed = true, busy = true }, cfg)
    eq(ok, false); eq(why, "already open")
    ok, why = c:can_open({ menu_visible = false }, cfg)
    eq(ok, false); eq(why, "simulator menu hidden")
    ok, why = c:can_open({ in_battle = true }, cfg)
    eq(ok, false); eq(why, "course started", "a fight blocks")
    c:event("team", 3)
    eq(c:can_open({ pause_closed = true }, cfg), true, "team screen")
    eq(c:running({}), false)
    c:event("confirmed", 4)
    eq(c.started, true, "Yes starts the course")
    eq(c:running({}), true)
    c:reset()
    eq(c.started, true, "reset (menu gone, fight) keeps the course started")
    ok, why = c:can_open({ pause_closed = true, menu_visible = true }, list)
    eq(ok, false); eq(why, "course started", "Get Ready, result screen: still started")
    c:event("list", 5)
    eq(c.started, false, "the course list showing again ends it")
    eq(c:can_open({ pause_closed = true }, list), true)
    c:event("confirmed", 6); c:event("chosen", 7)
    eq(c.started, false, "choosing a course again ends it")
    eq(c:can_open({}, { course_flow = "off" }), false, "off")
end

-- Pad button edge detection: once per press.
do
    local b = course.new_button()
    eq(course.pressed(b, false), false)
    eq(course.pressed(b, true), true, "pressed")
    eq(course.pressed(b, true), false, "held: not again")
    eq(course.pressed(b, nil), false, "unreadable counts as up")
    eq(course.pressed(b, true), true, "pressed again")
end

-- Settings.
do
    local s, problems = settings.parse("")
    eq(s.key, "F3"); eq(s.course_flow, "course_list"); eq(s.hint, "on"); eq(s.pad_button, "Gamepad_Special_Right")
    eq(#problems, 0)
    eq(settings.hint_text(s), "<button=options> Equipment", "default bindings: the game's Options glyph")
    s, problems = settings.parse(table.concat({ "# comment", "equipment_key = f5", "equipment_course_flow = Always",
        "equipment_hint_x = 100", "equipment_hint_y = 5", "equipment_hint = maybe", "equipment_bogus = 1", "other_part_key = 2",
        "equipment_battle_mode = direct", "equipment_pad_button = off" }, "\n"))
    eq(s.key, "F5"); eq(s.course_flow, "course_list", "always is read as course_list"); eq(s.hint_x, nil, "retired")
    eq(s.hint, "on", "bad value keeps the default")
    eq(#problems, 2, "bad value and unknown key reported; retired keys and other parts' keys ignored")
    eq(s.pad_button, "off")
    eq(settings.hint_text(s), "F5  Equipment")
    s = settings.parse("equipment_pad_button = Gamepad_Special_Left\nequipment_course_flow = after_course\n")
    eq(settings.hint_text(s), "F3 / View  Equipment"); eq(s.course_flow, "after_course")
    eq(settings.hint_text(settings.parse("equipment_pad_button = off")), "F3  Equipment", "pad off: no Start glyph")
end
