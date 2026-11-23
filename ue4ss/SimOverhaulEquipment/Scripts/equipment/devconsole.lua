-- Development installs only (dev.txt in the mod folder): run equipment-eval.lua from the mod folder once, on the game
-- thread, and write what it printed (out(...)) to equipment-eval.out. This game cannot reload a mod's scripts (Ctrl+R
-- crashes it), so this is how a game call is tried without a restart. A release has no dev.txt and never looks.
local M = {}

function M.new(mod_dir, env_extra, log)
    local self = {}
    local eval_path = mod_dir .. "equipment-eval.lua"
    local marker = io.open(mod_dir .. "dev.txt", "rb")
    local dev = marker ~= nil
    if marker then marker:close() end

    function self.enabled() return dev end

    function self.waiting()
        if not dev then return false end
        local file = io.open(eval_path, "rb")
        if file then file:close() end
        return file ~= nil
    end

    function self.run()
        local file = io.open(eval_path, "rb")
        if not file then return end
        local code = file:read("a")
        file:close()
        os.remove(eval_path)
        local lines = {}
        local env = setmetatable({
            out = function(...)
                local parts = {}
                for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
                lines[#lines + 1] = table.concat(parts, "\t")
            end,
        }, { __index = function(_, k) local v = env_extra[k]; if v ~= nil then return v end; return _G[k] end })
        local chunk, problem = load(code, "@equipment-eval", "t", env)
        local ok, result = false, problem
        if chunk then ok, result = pcall(chunk) end
        lines[#lines + 1] = (ok and "ok" or "ERROR") .. "\t" .. tostring(result)
        local report = io.open(mod_dir .. "equipment-eval.out", "wb")
        if report then
            report:write(table.concat(lines, "\n") .. "\n")
            report:close()
        end
        if log then log("eval\t" .. tostring(ok)) end
    end

    return self
end

return M
