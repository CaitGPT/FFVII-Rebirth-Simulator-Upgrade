"""Write the spawn probe's DataBuilder spec (data/custom-training/probe.json).

The probe asks one question in the game: can a simulator round spawn an arbitrary enemy on demand, and replace it,
through its territory's reinforcement waves? It repurposes one unused simulator territory with one initial enemy
and a wave list longer than any vanilla territory's (vanilla never goes past wave 15), and adds one course that
fights it. Usage: make_probe_spec.py <EnemyTerritoryMob.csv exported by DataBuilder> [wave count]
"""
import csv, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TERRITORY = "terVR_COL30_Gen_00_010"   # unused: only EnemyTerritory and EnemyTerritoryLevel name it
COURSE = "COL99_SimOverhaul_CT_Probe_vr"
POS = "POS_Mod_SimOverhaul_CT_010"


def templates(path):
    seen = []
    with open(path, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["Name"] not in seen:
                seen.append(r["Name"])
    return seen


def main():
    mobs = templates(sys.argv[1])
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    # Leave out props and helpers (traps, crowns, dummies, avatars): they are parts of other enemies.
    usable = [m for m in mobs if not any(s in m for s in ("_WE1", "_FA0052", "Avatar", "Minions"))]
    waves = usable[:count]
    initial = "mobcolvr_EN2001_02_WereRat_Poison_00"
    spec = {"tables": [
        {"asset": "DataObject/Resident/EnemyTerritory.uasset", "rows": [
            {"name": TERRITORY, "set": {
                "FieldAINameList_Array": ["Stay"],
                "MobTemplateList_Array": [initial], "MinPopList_Array": ["1"], "MaxPopList_Array": ["1"],
                "MobLevelList_Array": ["30"],
                "WaveMobTemplateList_Array": waves,
                "WaveMobLevelList_Array": ["30"] * len(waves),
                "WavePopSettingList_Array": ["0"] * len(waves),
                "WaveBattleSceneAerialEnemyFlag_Array": ["0"] * len(waves)}}]},
        {"asset": "DataObject/Resident/ColosseumPositionData.uasset", "rows": [
            {"name": POS, "cloneFrom": "POS_COL30_Sum_00_010", "set": {}}]},
        {"asset": "DataObject/Resident/Colosseum.uasset", "rows": [
            {"name": COURSE, "cloneFrom": "COL30_GRASA_01_Free_vr", "set": {
                "EnemyTerritoryID_Array": [TERRITORY], "BattleScenePosDataID_Array": [POS],
                "UserBattleInSequencerNames_Array": ["CSA_VrCoBattleIn_Common"], "BattleMax": "1",
                "DisplayFlagID_Array": ["stf1210_CHOFA_VROpen_Gras"], "OpenFlagID_Array": ["stf1210_CHOFA_VROpen_Gras"],
                "OpenConditionClearCheckID": "", "OpenConditionTextID": "", "OpenConditionClearCheckID01": "",
                "OpenConditionTextID01": "", "PreNotifyActionOrActionGroupID": "", "CourseSelectStateTriggerID": "",
                "RewardID": "", "ClearFlagID": "", "PlayLogClearFlagID": "",
                "TabCategory": "7", "TimerSaveArrayIndex": "192", "DifficultyHardChangeToNormal": "1"}}]},
    ]}
    out = os.path.join(ROOT, "data", "custom-training", "probe.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(spec, f, indent=1)
    with open(os.path.join(ROOT, "data", "custom-training", "probe-waves.txt"), "w", newline="\n") as f:
        for i, w in enumerate(waves):
            f.write(f"{i}\t{w}\n")
    print(f"{out}: {len(waves)} waves")


if __name__ == "__main__":
    main()
