-- Development only (dev.txt): made-up numbers, so the panel's layout can be judged from screenshots with values a
-- short test fight doesn't reach (empty, small, very large, four rows with the longest names). The command file's
-- "sample <name>" shows one in place of the live numbers; "sample off" goes back. Never used without dev.txt.
local M = {}

local function kinds(scale, sources, mp)
    local out = {}
    for _, kind in ipairs({ "damage", "taken", "heal", "mp" }) do
        local by = {}
        local total = 0
        for name, share in pairs(sources) do
            by[name] = share * scale
            total = total + by[name]
        end
        out[kind] = { average = total / 100, recent = total / 120, total = total, biggest = scale * 0.07,
            by_source = kind == "mp" and {} or by, attributed = true }
    end
    out.mp.total = mp or 0
    return out
end

M.SAMPLES = {
    empty = function() return { elapsed = 0, party = { "Cloud" }, kinds = kinds(0, {}, 0) } end,
    small = function() return { elapsed = 7, party = { "Cloud", "Tifa" }, kinds = kinds(3, { Cloud = 1, Tifa = 0.5 }, 12) } end,
    large = function()
        return { elapsed = 3725, party = { "Sephiroth", "Zack", "Cait Sith" },
            kinds = kinds(9999999, { Sephiroth = 0.6, Zack = 0.25, ["Cait Sith"] = 0.1, Unattributed = 0.05 }, 99999) }
    end,
    rows = function()
        return { elapsed = 95, party = { "Red XIII", "Sephiroth", "Cait Sith" },
            kinds = kinds(250000, { ["Red XIII"] = 0.3, Sephiroth = 0.4, ["Cait Sith"] = 0.2, Unattributed = 0.1 }, 640) }
    end,
    solo = function() return { elapsed = 42, party = { "Zack" }, kinds = kinds(40000, { Zack = 1 }, 90) } end,
    nonative = function()
        local s = { elapsed = 30, party = { "Cloud", "Aerith", "Barret" }, kinds = kinds(20000, { Cloud = 0.5, Aerith = 0.3, Barret = 0.2 }, 300) }
        s.kinds.damage.by_source, s.kinds.damage.attributed = {}, false
        s.kinds.heal.attributed = false
        return s
    end,
}

function M.get(name)
    local make = M.SAMPLES[name]
    if not make then return nil end
    local s = make()
    s.sample = name
    return s
end

return M
