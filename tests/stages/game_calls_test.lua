-- game.lua cannot run offline (it calls the game), but its shape can be checked: every function that session.lua and
-- main.lua call on it must be defined there. A clean-up once cut four of them off the end of the file, and nothing
-- noticed until the game did (2026-11-17).
local function read(name)
    local file = assert(io.open(SCRIPTS .. "/" .. name, "rb"))
    local text = file:read("a")
    file:close()
    return text
end
local defined = {}
for name in read("stages/game.lua"):gmatch("function M%.([%w_]+)") do defined[name] = true end
local missing = {}
for _, script in ipairs({ "stages/session.lua", "main.lua" }) do
    for name in read(script):gmatch("game%.([%w_]+)") do
        if name ~= "lua" and not defined[name] then missing[#missing + 1] = script .. ": game." .. name end
    end
end
if #missing > 0 then error("not defined in game.lua: " .. table.concat(missing, ", ")) end
assert(defined.course_title and defined.open_picker and defined.stream_request and defined.settled, "expected functions")
