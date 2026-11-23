-- What one reading of the fight adds to the meters, without the game (tested offline with made-up fights).
-- meters_game.lua takes the readings; this module only counts. Battle Meters' counting (main.lua's track_enemies,
-- track_party, take_hits), with one change for Custom Training:
--
-- Custom Training writes party HP itself: Healing drops every patient to 1% after each heal, Passive refills the party
-- (owner, 2026-11-21: only Aggressive has real conditions, with no refills). Counted as HP changes those would be damage taken and healing. So when the game's hit events are there
-- (the meters' native helper), party healing and damage taken count only as far as a hit event explains the HP change
-- ("strict": a heal hit for a gain, a damage hit for a loss, capped at the change, as Battle Meters caps its credit).
-- Damage dealt still counts every HP an opponent loses, split by who dealt it as in Battle Meters. Without hit events,
-- three rules leave Custom Training's own writes out: a drop to 2% of max or less in Healing, a rise to full from
-- below half in Passive (it refills a living member under 50% to 100% in one jump), and any rise to full in the
-- first 3 s after a start or change (its clean-up).
--
-- Opponents: only HP an opponent loses while it is in the fight counts. Custom Training removes opponents itself (Apply
-- with another opponent, a new attempt): those leave with their HP, and that is never damage (seen 2026-11-21: a Titan
-- removed on Apply counted 84,186). So an opponent that leaves between two readings counts its last HP only as far as
-- the game's hit events on it explain (a killing blow the readings missed), or without hit events only when at most
-- half its HP was left; and none at all after Custom Training changed or restarted the course (see reset).
local Meters = require("meters_core")
local Attribution = require("meters_attribution")

local M = {}
M.__index = M

-- EPlayerType order (EndDataBase), the names Battle Meters uses.
M.PLAYER_NAMES = { [0] = "Cloud", "Barret", "Tifa", "Aerith", "Red XIII", "Yuffie", "Cait Sith", "Zack", "Sephiroth",
    "Vincent", "Cid" }
M.HEALING_FLOOR = 0.02   -- Healing: a drop to this share of max HP or less is Custom Training's 1% hold
M.REFILL_FROM = 0.5      -- Passive: a rise to full from below this share is Custom Training's refill
M.SETTLE = 3             -- seconds after a start or change: a rise to full is Custom Training's clean-up (Passive
                         -- tops the party up then and 2 s later; leaving Healing sets held members back to full)

function M.new(window)
    local self = setmetatable({ window = window or 5 }, M)
    self:reset()
    return self
end

-- Clears the numbers. The opponents in the fight stay known (their HP), so clearing mid-fight doesn't turn them into new
-- ones. outgoing: Custom Training is replacing the opponents (a course change or a new attempt): those known now, and
-- those first seen in the next reading, are on their way out and count nothing when they leave.
function M:reset(outgoing)
    local kept = self.enemies or {}
    self.meters = Meters.new(self.window)
    local meters = self.meters
    self.dealt = Attribution.new()
    self.healed = Attribution.new(nil, function(who, amount, t) if self.strict then meters:add("heal", amount, t, who) end end)
    self.taken = Attribution.new(nil, function(who, amount, t) if self.strict then meters:add("taken", amount, t, who) end end)
    self.enemies, self.party, self.mp, self.order, self.named = {}, {}, {}, {}, {}
    self.strict, self.last_now = nil, nil
    for key, e in pairs(kept) do
        self.enemies[key] = { hp = e.hp, max = e.max, name = e.name, outgoing = outgoing or e.outgoing }
        self.dealt:track(e.name)
    end
    self.carry = outgoing == true or self.carry == true   -- until the next reading, whatever clears meanwhile
    self.settle = outgoing == true or self.settle == true -- the clean-up window starts at the next reading
end

-- A new wave (Custom Training respawns the chosen set: a key, its menu, or by itself): the numbers keep running, and
-- the opponents in the fight now are on their way out. A respawn mid-fight removes living ones with their HP, which is
-- never damage. Those first seen later are the new wave's, so nothing carries over to the next reading.
function M:outgoing()
    for _, e in pairs(self.enemies) do e.outgoing = true end
end

local function alias_member(self, m)
    if self.named[m.id] then return end
    self.named[m.id] = true
    for _, name in ipairs(m.names or {}) do
        self.dealt:alias(name, m.id); self.healed:alias(name, m.id); self.taken:alias(name, m.id)
    end
    self.dealt:alias(m.id, m.id); self.healed:alias(m.id, m.id); self.taken:alias(m.id, m.id)
end

-- Party changes without hit events: the rules that leave Custom Training's own HP writes out.
local function count_loose(self, m, before, behaviour, now)
    if m.hp < before then
        if behaviour == "healing" and m.max and m.hp <= m.max * M.HEALING_FLOOR then return end
        self.meters:add("taken", before - m.hp, now, m.id)
    elseif m.hp > before then
        if behaviour == "passive" and m.max and m.hp >= m.max and before < m.max * M.REFILL_FROM then return end
        if m.max and m.hp >= m.max and self.settle_until and now <= self.settle_until then return end
        self.meters:add("heal", m.hp - before, now, m.id)
    end
end

local function track_party(self, party, behaviour, now)
    local seen, order = {}, {}
    for _, m in ipairs(party) do
        seen[m.id] = true
        order[#order + 1] = m.id
        alias_member(self, m)
        self.healed:track(m.id)
        self.taken:track(m.id)
        local before = self.party[m.id]
        if m.hp and before then
            if self.strict then
                if m.hp < before then self.taken:change(m.id, before - m.hp, now)
                elseif m.hp > before then self.healed:change(m.id, m.hp - before, now) end
            else
                count_loose(self, m, before, behaviour, now)
            end
        end
        if m.hp then self.party[m.id] = m.hp end
    end
    for id in pairs(self.party) do
        if not seen[id] then
            self.party[id] = nil
            self.healed:forget(id); self.taken:forget(id)
        end
    end
    if #order > 0 then self.order = order end
end

-- Hits are stamped with this reading's time: the HP they took or healed shows in this reading.
local function take_hits(self, hits, now)
    for _, h in ipairs(hits or {}) do
        local amount = type(h.damage) == "number" and h.damage or nil
        if h.heal then
            local member = self.healed:player_of(h.target)
            if member then self.healed:hit(amount, h.causer, member, now) end
        else
            local member = self.taken:player_of(h.target)
            if member then
                self.taken:hit(amount, h.target, member, now)
            else
                self.dealt:hit(amount, h.causer, h.target, now)
            end
        end
    end
end

-- The HP an opponent that left still had, as far as it counts (see the header).
local function departure(self, known, now, battle_over)
    local remaining = known.hp
    if known.outgoing or type(remaining) ~= "number" or remaining <= 0 then return 0 end
    if self.strict then return math.min(remaining, self.dealt:unmatched(known.name, now)) end
    if type(known.max) == "number" and remaining > known.max / 2 then return 0 end
    return Meters.killing_blow(remaining, known.max, battle_over)
end

local function leave(self, key, known, now, battle_over)
    local blow = departure(self, known, now, battle_over)
    self.meters:add("damage", blow, now)
    self.dealt:change(known.name, blow, now)
    self.dealt:forget(known.name)
    self.enemies[key] = nil
end

-- Opponents are told apart by key (their address), so nothing from the game is held. A key that comes back with
-- another name or max HP is a new opponent where an old one was.
local function track_enemies(self, enemies, now, battle_over)
    local present = {}
    local carry = self.carry
    self.carry = false
    for _, e in ipairs(enemies) do
        present[e.key] = true
        local known = self.enemies[e.key]
        if known and (e.name ~= known.name or e.max and known.max and e.max ~= known.max) then
            leave(self, e.key, known, now, battle_over)
            known = nil
        end
        if not known then
            self.enemies[e.key] = { hp = e.hp, max = e.max, name = e.name, outgoing = carry or nil }
            self.dealt:track(e.name)
        elseif e.hp then
            if known.hp and e.hp < known.hp then
                self.meters:add("damage", known.hp - e.hp, now)
                self.dealt:change(known.name, known.hp - e.hp, now)
            end
            known.hp, known.max = e.hp, e.max or known.max
        end
    end
    for key, known in pairs(self.enemies) do
        if not present[key] then leave(self, key, known, now, battle_over) end
    end
end

local function track_mp(self, party, mp_spent, now)
    if mp_spent then
        for who, amount in pairs(mp_spent) do self.meters:add("mp", amount, now, who) end
        return
    end
    for _, m in ipairs(party) do
        if m.mp then
            local before = self.mp[m.id]
            if before and m.mp < before then self.meters:add("mp", before - m.mp, now, m.id) end
            self.mp[m.id] = m.mp
        end
    end
end

-- r: { now, behaviour, native = hit events available, party = { { id, hp, max, mp, names } } in battle-slot order,
--      enemies = { { key, name, hp, max } } (Custom Training's anchor already left out), hits = { { damage, causer,
--      target, heal } }, mp_spent = { [id] = amount } or nil (Custom Training's counts), battle_over }
function M:tick(r)
    if self.strict == nil then self.strict = r.native == true end
    local now = r.now
    self.last_now = now
    if self.settle then self.settle, self.settle_until = false, now + M.SETTLE end
    track_party(self, r.party or {}, r.behaviour, now)
    take_hits(self, r.hits, now)
    track_enemies(self, r.enemies or {}, now, r.battle_over)
    track_mp(self, r.party or {}, r.mp_spent, now)
end

-- The numbers for the view: meters_core's snapshot, damage split by who dealt it once hit events explain any of it,
-- healing by who did it (strict) or who received it, damage taken by who took it; plus the party in slot order.
function M:snapshot(now)
    local snapshot = self.meters:snapshot(now or self.last_now or 0)
    local damage = snapshot.kinds.damage
    local split = self.dealt:split(damage.total)
    damage.by_source, damage.attributed = split or {}, split ~= nil
    snapshot.kinds.heal.attributed = self.strict == true
    snapshot.kinds.taken.attributed = true
    snapshot.strict = self.strict == true
    snapshot.party = self.order
    return snapshot
end

return M
