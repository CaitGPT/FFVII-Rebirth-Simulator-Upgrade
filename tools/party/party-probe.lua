-- Development probe for Simulator Stages' live Lua console (copy to SimulatorStages\stages-eval.lua; output in
-- stages-eval.out). Reads, never writes: each player type's party status, and the battle members by slot.
-- Calls only EndPartyAPI / EndBattleAPI functions in the header dump.
local party = StaticFindObject("/Script/EndGame.Default__EndPartyAPI")
local battle = StaticFindObject("/Script/EndGame.Default__EndBattleAPI")
local names = {[0]="Cloud","Barret","Tifa","Aerith","RedXIII","Yuffie","CaitSith","Zack","Sephiroth"}
for t = 0, 8 do
    local ok1, status = pcall(function() return party:GetPlayerStatus(t) end)
    local ok2, inBattle = pcall(function() return party:IsBattleMember(t) end)
    local ok3, slot = pcall(function() return party:GetBattleSlotIndex(t) end)
    out("type", t, names[t], "status", ok1 and status or "?", "battle", ok2 and inBattle or "?", "slot", ok3 and slot or "?")
end
local okc, count = pcall(function() return party:GetBattleMemberCount() end)
out("battle_member_count", okc and count or "?")
for i = 0, (okc and count or 0) - 1 do
    local member = party:GetBattleMember(i)
    local kind = party:GetBattleMemberType(i)
    local name, id, hp, hpmax = "?", "?", "?", "?"
    if member and member:IsValid() then
        pcall(function() name = battle:GetActorName(member):ToString() end)
        pcall(function() id = battle:GetCharaID(member):ToString() end)
        pcall(function() hp = battle:GetCharaHP(member) end)
        pcall(function() hpmax = battle:GetHPMax(member) end)
    end
    out("battle_slot", i, "type", kind, "name", name, "chara", id, "hp", hp, hpmax)
end
local okl, leader = pcall(function() return party:GetPartyLeaderType() end)
out("leader", okl and leader or "?")
return "done"
