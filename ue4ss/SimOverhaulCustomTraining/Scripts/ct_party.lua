-- What to do about the party, without the game (Training Dummy's three courses, owner 2026-11-20 evening):
--   Healing: every party member is a patient held at 1% HP; a heal is left on the HP bar for a moment, then the
--            patient is dropped back to 1%.
--   Passive: a member below half HP is refilled (owner 2026-11-21: Passive is for trying things out, everything is
--            refilled for both sides).
--   Aggressive: nothing (owner 2026-11-21: real conditions; only Auto-Life, kept on every member by ct_session,
--            raises a knocked-out one so the round goes on).
-- MP is refilled as it is spent in every behaviour (Training Dummy's unlimited MP). Tested offline.
local M = {}
M.__index = M

M.HEAL_RESET_SECONDS = 1.5
M.REFILL_BELOW = 50

function M.new() return setmetatable({ members = {} }, M) end

function M:reset() self.members = {} end

-- members: list of { id, hp, max }; returns actions: list of { id, action = "low" | "full" }.
function M:step(members, behaviour, now)
    local actions, seen = {}, {}
    for _, m in ipairs(members) do
        seen[m.id] = true
        if m.hp and m.max and m.max > 0 and m.hp > 0 then
            local p = self.members[m.id]
            if behaviour == "healing" then
                if not p or p.behaviour ~= "healing" then
                    -- A new patient: down to 1% at once.
                    p = { behaviour = "healing" }
                    self.members[m.id] = p
                    actions[#actions + 1] = { id = m.id, action = "low" }
                    p.waiting = true
                elseif p.waiting then
                    -- The first reading after setting it low is the patient's floor.
                    p.low, p.waiting = m.hp, nil
                elseif m.hp > p.low and not p.reset_at then
                    -- Healed: leave it on the bar, then drop back.
                    p.reset_at = now + M.HEAL_RESET_SECONDS
                elseif p.reset_at and now >= p.reset_at then
                    actions[#actions + 1] = { id = m.id, action = "low" }
                    p.reset_at, p.waiting = nil, true
                end
            else
                local was_patient = p and p.behaviour == "healing"
                self.members[m.id] = { behaviour = behaviour }
                if was_patient then
                    -- Out of Healing: the patient gets back the HP Healing took.
                    actions[#actions + 1] = { id = m.id, action = "full" }
                elseif behaviour == "passive" and m.hp < m.max * M.REFILL_BELOW / 100 then
                    actions[#actions + 1] = { id = m.id, action = "full" }
                end
            end
        end
    end
    for id in pairs(self.members) do if not seen[id] then self.members[id] = nil end end
    return actions
end

-- Leaving Healing: patients go back to full HP.
function M:restore(members)
    local actions = {}
    for _, m in ipairs(members) do
        local p = self.members[m.id]
        if p and p.behaviour == "healing" then actions[#actions + 1] = { id = m.id, action = "full" } end
    end
    return actions
end

return M
