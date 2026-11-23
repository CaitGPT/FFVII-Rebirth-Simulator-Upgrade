-- What to do about the enemies on screen, without the game: given the enemies of our territory (with the spec each
-- one is), the wanted opponent and count, and the spawns already asked for, say which waves to start and which
-- enemies to remove. Tested offline.
local M = {}

-- enemies: list of { key = unique name, spec = BattleCharaSpec id }
-- want: { spec = id, count = n }
-- pending: spawns asked for that have not appeared yet
-- stale: set of keys to replace (the enemies there were when the choice changed)
-- Returns { spawn = n, remove = {keys} }.
--
-- New enemies are asked for first, and the stale ones removed only once a new one is there, so the round never has
-- zero enemies (which could end it). Enemies that appear later and are not the opponent (adds an opponent summons,
-- like the Tonberry King's minions) are left alone: they belong to the fight.
-- immediate: remove the stale ones at once (when the hidden anchor keeps the round going, nothing has to wait).
function M.plan(enemies, want, pending, stale, immediate)
    stale = stale or {}
    local right = {}
    for _, e in ipairs(enemies) do
        if e.spec == want.spec and not stale[e.key] then right[#right + 1] = e end
    end
    local result = { spawn = 0, remove = {} }
    local have = #right + (pending or 0)
    if have < want.count then result.spawn = want.count - have end
    if #right >= 1 or immediate then
        for _, e in ipairs(enemies) do
            if stale[e.key] then result.remove[#result.remove + 1] = e.key end
        end
    end
    for i = want.count + 1, #right do result.remove[#result.remove + 1] = right[i].key end
    return result
end

-- The same for a setup of several members (a group, or a round's set): members { key, count }, matched: member key ->
-- its enemies (ct_session.match), pending: member key -> spawns asked for. Returns { spawn = { [key] = n }, remove }.
-- whole: a round's set, which comes back whole: nothing is spawned while any of it is there or on its way.
function M.group(enemies, members, matched, pending, stale, immediate, whole)
    stale, pending = stale or {}, pending or {}
    local result = { spawn = {}, remove = {} }
    local any, on_way = false, 0
    for _, m in ipairs(members) do
        if #matched[m.key] > 0 then any = true end
        on_way = on_way + (pending[m.key] or 0)
    end
    for _, m in ipairs(members) do
        local right = matched[m.key]
        if whole then
            result.spawn[m.key] = (not any and on_way == 0) and m.count or 0
        else
            result.spawn[m.key] = math.max(0, m.count - #right - (pending[m.key] or 0))
        end
        for i = m.count + 1, #right do result.remove[#result.remove + 1] = right[i].key end
    end
    if any or immediate then
        for _, e in ipairs(enemies) do
            if stale[e.key] then result.remove[#result.remove + 1] = e.key end
        end
    end
    return result
end

-- The keys of every enemy now, as the stale set for a change of opponent, count or difficulty.
function M.all(enemies)
    local set = {}
    for _, e in ipairs(enemies) do set[e.key] = true end
    return set
end

return M
