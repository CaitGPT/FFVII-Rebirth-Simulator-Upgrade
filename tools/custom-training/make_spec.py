"""Generate Custom Training's opponent list from the game's tables.

Writes:
  data/custom-training/generated.json   the course's territory: 16 reinforcement waves (the first 16 opponents)
  ue4ss/SimOverhaulCustomTraining/Scripts/ct_catalogue.lua   every opponent for the Lua mod (spec, name key,
                                         category, level, spawn slot, the waves its own scripts start)
  data/custom-training/opponents.tsv    the list for people (what is offered, and what was left out and why)
  data/custom-training/rounds.tsv       the simulator's rounds Round mode offers, and those left out and why

usage: make_spec.py <folder with DataBuilder CSV exports of EnemyTerritoryMob, BattleCharaSpec, EnemyTerritory,
       Colosseum> (from the Epic 1.005 export: DataBuilder export <table>.uasset <table>.csv)
"""
import csv, json, os, sys
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TERRITORY = "terVR_COL30_Gen_00_010"
# Parts and props of other enemies: spawning them alone gives a trap, a crown or a dummy, not an opponent.
HELPER_MARKS = ("_WE1", "_FA0052", "Avatar", "Minions", "GilgameshShield", "Adamantaimai_Moss")
# (Gilgamesh's shields and the Adamantoise's moss came out of a wave as props, not enemies: seen 2026-11-20.)
# Templates the in-game sweep (tools/custom-training/live/sweep.py, 2026-11-21) found never to appear when spawned
# alone, twice; data/custom-training/sweep.tsv has the run.
DROPPED = {
    "mobcolvr_EN0008_02_Vice_VariationB_00": "never appeared in the sweep (its SpikedBat template is the same enemy)",
    "mobcolvr_EN0000_07_SecuritySoldier_MidgarEnd2_00": "never appeared in the sweep",
    "mobcolvr_EN0007_01_Soldier3rd_Locche_00": "never appeared in the sweep (LoccheSEnd2 is offered)",
    "mobcolvr_SU2010_00_Odin_Standard_00": "never appeared in the sweep (Odin rides Sleipnir: Sleipnir is offered)",
    "mobcolvr_SU2010_01_Odin_GilQuest_00": "never appeared in the sweep (Sleipnir GilQuest is offered)",
    # No attack in 60 s alone (probe sweep, 2026-11-21), and no simulator course fights it to compare with: the Gi
    # Specter of the story's Cave of the Gi. Its simulator kin (Gi Lancer, Sorcerer, Archer) are offered.
    "mobcolvr_EN2244_00_GiSpector_StandardEnd2_00": "no attack in 60 s alone, and no simulator course fights it (Gi Lancer, Sorcerer and Archer are offered)",
    # Not a real opponent: a test enemy that borrows the Security Officer's name.
    "mobcolvr_EN9999_00_MikataTest_Standard_00": "a test enemy (MikataTest) carrying the Security Officer's name",
}
# Templates the game names exactly as another one and that fight the same, so the list offers one (ui's matrix,
# 2026-11-21: "Security Officer (Standard Ver1)"). BattleCharaSpec compared row by row: Ver1/Ver2 change only the
# model (CharaSpecID), the G2/G3 Citripines and two Elite Grenadiers only the AI slot, Test 0's other one only the
# voice; the Thugs B and C, the Phoenix-fight adds and the Tonberry "VR" are weaker or near copies of the one kept.
SAME_AS = {
    "mobcolvr_EN0000_10_SecuritySoldier_StandardVer1End2_00": "mobcolvr_EN0000_00_SecuritySoldier_Standard_00",
    "mobcolvr_EN0000_11_SecuritySoldier_StandardVer2End2_00": "mobcolvr_EN0000_00_SecuritySoldier_Standard_00",
    "mobcolvr_EN0000_12_SecuritySoldier_SeniorVer1End2_00": "mobcolvr_EN0000_01_SecuritySoldier_Senior_00",
    "mobcolvr_EN0000_13_SecuritySoldier_SeniorVer2End2_00": "mobcolvr_EN0000_01_SecuritySoldier_Senior_00",
    "mobcolvr_EN0000_14_SecuritySoldier_JunonVer1End2_00": "mobcolvr_EN0000_06_SecuritySoldier_JunonEnd2_00",
    "mobcolvr_EN0000_15_SecuritySoldier_JunonVer2End2_00": "mobcolvr_EN0000_06_SecuritySoldier_JunonEnd2_00",
    "mobcolvr_EN0000_21_SecuritySoldier_SeniorJunonVer1End2_00": "mobcolvr_EN0000_08_SecuritySoldier_SeniorJunonEnd2_00",
    "mobcolvr_EN0000_22_SecuritySoldier_SeniorJunonVer2End2_00": "mobcolvr_EN0000_08_SecuritySoldier_SeniorJunonEnd2_00",
    "mobcolvr_EN0001_06_GrenadeSoldier_StandardVer1End2_00": "mobcolvr_EN0001_00_GrenadeSoldier_Standard_00",
    "mobcolvr_EN0001_07_GrenadeSoldier_StandardVer2End2_00": "mobcolvr_EN0001_00_GrenadeSoldier_Standard_00",
    "mobcolvr_EN0001_04_GrenadeSoldier_SeniorVer1End2_00": "mobcolvr_EN0001_01_GrenadeSoldier_Senior_00",
    "mobcolvr_EN0001_05_GrenadeSoldier_SeniorVer2End2_00": "mobcolvr_EN0001_01_GrenadeSoldier_Senior_00",
    "mobcolvr_EN0002_06_ShieldSoldier_StandardVer1End2_00": "mobcolvr_EN0002_00_ShieldSoldier_Standard_00",
    "mobcolvr_EN0002_07_ShieldSoldier_StandardVer2End2_00": "mobcolvr_EN0002_00_ShieldSoldier_Standard_00",
    "mobcolvr_EN0002_13_ShieldSoldier_FlameVer1End2_00": "mobcolvr_EN0002_03_ShieldSoldier_Flame_00",
    "mobcolvr_EN0002_14_ShieldSoldier_FlameVer2End2_00": "mobcolvr_EN0002_03_ShieldSoldier_Flame_00",
    "mobcolvr_EN0002_08_ShieldSoldier_JunonVer1End2_00": "mobcolvr_EN0002_04_ShieldSoldier_JunonEnd2_00",
    "mobcolvr_EN0002_09_ShieldSoldier_JunonVer2End2_00": "mobcolvr_EN0002_04_ShieldSoldier_JunonEnd2_00",
    "mobcolvr_EN2003_02_PuzoCute_TropicalEnd2_G2_00": "mobcolvr_EN2003_02_PuzoCute_TropicalEnd2_00",
    "mobcolvr_EN2003_02_PuzoCute_TropicalEnd2_G3_00": "mobcolvr_EN2003_02_PuzoCute_TropicalEnd2_00",
    "mobcolvr_EN2003_03_PuzoCute_TropicalRareEnd2_G2_00": "mobcolvr_EN2003_03_PuzoCute_TropicalRareEnd2_00",
    "mobcolvr_EN2003_03_PuzoCute_TropicalRareEnd2_G3_00": "mobcolvr_EN2003_03_PuzoCute_TropicalRareEnd2_00",
    "mobcolvr_EN2000_10_GuardHound_TestZeroAnotherVoiceEnd2_00": "mobcolvr_EN2000_10_GuardHound_TestZeroEnd2_00",
    "mobcolvr_EN0009_21_CorneoLackey_GreedBEnd2_00": "mobcolvr_EN0009_20_CorneoLackey_GreedAEnd2_00",
    "mobcolvr_EN0009_22_CorneoLackey_GreedCEnd2_00": "mobcolvr_EN0009_20_CorneoLackey_GreedAEnd2_00",
    "mobcolvr_EN2017_00_Tonberry_Standard_VR": "mobcolvr_EN2017_00_Tonberry_Standard_00",
    "mobcolvr_EN2209_00_ArkDragon_Phoenix_00": "mobcolvr_EN2209_00_ArkDragon_StandardEnd2_00",
    "mobcolvr_EN2015_00_Bomb_Phoenix_00": "mobcolvr_EN2015_00_Bomb_Standard_00",
    "mobcolvr_EN2210_00_Flan_Phoenix_00": "mobcolvr_EN2210_00_Flan_StandardEnd2_00",
    "mobcolvr_EN2201_00_Formula_Phoenix_00": "mobcolvr_EN2201_00_Formula_StandardEnd2_00",
    "mobcolvr_EN2231_00_GrandHorn_Phoenix_00": "mobcolvr_EN2231_00_GrandHorn_StandardEnd2_00",
    "mobcolvr_EN2211_00_Ogre_Phoenix_00": "mobcolvr_EN2211_00_Ogre_StandardEnd2_00",
}
# Same name, different fight: a short plain word after the game's name ("Bandit (Axe)"). Only these carry one.
TAGS = {
    "mobcolvr_EN0008_00_Vice_Standard_Scimitar_00": "Scimitar",
    "mobcolvr_EN0008_00_Vice_Standard_IronPipe_00": "Iron Pipe",
    "mobcolvr_EN0008_01_Vice_VariationA_Axe_00": "Axe",
    "mobcolvr_EN0008_02_Vice_VariationB_SpikedBat_00": "Spiked Bat",
    "mobcolvr_SU2000_01_Titan_GilQuest_00": "Gilgamesh's trial",
    "mobcolvr_SU2015_01_Sleipnir_GilQuest_00": "Gilgamesh's trial",
    "mobcolvr_SU2020_01_Kjata_GilQuest_00": "Gilgamesh's trial",
    "mobcolvr_SU2030_01_Alexander_GilQuest_00": "Gilgamesh's trial",
    "mobcolvr_SU2040_01_Phoenix_GilQuest_00": "Gilgamesh's trial",
    "mobcolvr_SU2050_01_NeoBahamut_GilQuest_00": "Gilgamesh's trial",
    "mobcolvr_SU2060_01_Gilgamesh_Hard_00": "Hard",
}
NAMES = os.path.join(ROOT, "data", "custom-training", "names-en.tsv")
# Every opponent can come 1, 2 or 3 at a time (owner 2026-11-21). Only one shown in the game to break with more gets a
# cap here, with the evidence (the 3-copy run of the former bosses, data/custom-training/sweep-three.tsv).
CAPS = {}
# EnemyCategory (the enemy book's kinds) -> the menu's category (ct_menu.CATEGORY_LABELS).
CATEGORY = {"1": 1, "2": 2, "3": 3, "4": 4, "0": 5}
DEFAULT_LEVEL = 50
SLOTS = 16  # a round can start waves 0-15 only; higher ones crashed the game (2026-11-20)


def load(folder, name):
    rows = OrderedDict()
    with open(os.path.join(folder, name + ".csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            rows.setdefault(r["Name"], {})[r["Property"]] = r["Value"]
    return rows


def split(v):
    return v.split("|") if v else []


def main():
    folder = sys.argv[1]
    mobs, specs = load(folder, "EnemyTerritoryMob"), load(folder, "BattleCharaSpec")
    territories, courses = load(folder, "EnemyTerritory"), load(folder, "Colosseum")
    used = {t for c in courses.values() for t in split(c.get("EnemyTerritoryID_Array", ""))}

    # The level each template is fought at in the game's own courses (the lowest), so an opponent feels as it does
    # in the simulator.
    levels = {}
    for tname, t in territories.items():
        if tname not in used:
            continue
        for key, lkey in (("MobTemplateList_Array", "MobLevelList_Array"), ("WaveMobTemplateList_Array", "WaveMobLevelList_Array")):
            ts, ls = split(t.get(key, "")), split(t.get(lkey, ""))
            for i, m in enumerate(ts):
                if m and i < len(ls) and ls[i].isdigit() and int(ls[i]) > 0:
                    levels[m] = min(levels.get(m, 999), int(ls[i]))

    # Flyers: any template a vanilla round marks aerial (AerialEnemyFlag, WaveBattleSceneAerialEnemyFlag). The Lua
    # puts every other spawned enemy on the floor, and leaves these at their height.
    aerial = set()
    for tname, t in territories.items():
        for key, fkey in (("MobTemplateList_Array", "AerialEnemyFlag_Array"),
                          ("WaveMobTemplateList_Array", "WaveBattleSceneAerialEnemyFlag_Array")):
            ts, fs = split(t.get(key, "")), split(t.get(fkey, ""))
            for i, m in enumerate(ts):
                if m and i < len(fs) and fs[i] == "1":
                    aerial.add(m)

    offered, left_out, seen_specs = [], [], set()
    for name, m in mobs.items():
        spec_id = m["BattleCharaSpecID"]
        spec = specs.get(spec_id)
        if any(mark in name for mark in HELPER_MARKS):
            left_out.append((name, "part or prop of another enemy"))
        elif not name.startswith("mobcolvr_"):
            left_out.append((name, "malformed template name"))
        elif spec is None:
            left_out.append((name, "no BattleCharaSpec row"))
        elif spec_id in seen_specs:
            left_out.append((name, "same enemy as an earlier template"))
        else:
            seen_specs.add(spec_id)
            offered.append({
                "id": name, "spec": spec_id, "label": spec.get("TextLabel", ""),
                "hp_percent": float(spec.get("HP", "100") or 100),
                # The model's spec: what GetCharaSpecName answers in the game (the Cactuars answer SU0008_*).
                "chara": spec.get("CharaSpecID", "") or spec_id,
                "category": CATEGORY.get(spec.get("EnemyCategory", "3"), 3),
                "level": levels.get(name, DEFAULT_LEVEL), "fought": name in levels, "air": name in aerial,
            })

    # The adds an opponent's own scripts start as waves (the Tonberry King's crown and minions, Phoenix's eggs, the
    # Mindflayer's avatar...), from the vanilla rounds that fight it: a wave counts as the opponent's own when that
    # round has no other enemy, or when the wave is of the opponent's own family (the same EN/SU number) or names its
    # species (the Devil Ride's trap, the special forces' drone bomb). Of those
    # rounds, the one with the fewest enemies wins. Before the opponent is spawned, the Lua writes these into the same
    # wave slots of our territory.
    def family(template):
        return template.replace("mobcolvr_", "").split("_")[0]
    def species(template):
        parts = template.replace("mobcolvr_", "").split("_")
        return parts[2] if len(parts) > 2 else parts[0]
    for o in offered:
        o["home"] = []
        best = None
        for tname, t in territories.items():
            mob_list = [m for m in split(t.get("MobTemplateList_Array", "")) if m]
            if tname not in used or o["id"] not in mob_list:
                continue
            waves, wlevels = split(t.get("WaveMobTemplateList_Array", "")), split(t.get("WaveMobLevelList_Array", ""))
            home = []
            for i, w in enumerate(waves[:SLOTS]):
                if not w or w not in mobs:
                    continue
                own = family(w) == family(o["id"]) or species(o["id"]) in w  # e.g. WE1209_00_DevilRide_Trap
                if len(set(mob_list)) > 1 and not own:
                    continue
                lv = int(wlevels[i]) if i < len(wlevels) and wlevels[i].isdigit() and int(wlevels[i]) > 0 else o["level"]
                home.append((i, w, lv))
            if home and (best is None or len(set(mob_list)) < best[0]):
                best = (len(set(mob_list)), home)
        if best:
            o["home"] = best[1]
        # "boss" is for the test tools only (the 3-copy run, the sweep's column): the game no longer caps them
        # (owner 2026-11-21). The tables have no boss flag, so: summons and Sephiroth (SU, PC), anything with 1,500% HP
        # or more, and big enemies that summon their own adds.
        kind = o["id"].replace("mobcolvr_", "")[:2]
        o["boss"] = kind in ("SU", "PC") or o["hp_percent"] >= 1500 or (bool(o["home"]) and o["hp_percent"] >= 1000)
        taken = {i for i, _, _ in o["home"]}
        o["slot"] = min(i for i in range(SLOTS) if i not in taken)

    # The territory's own 16 waves: the first 16 opponents as first generated, dropped ones included, so dropping one
    # does not change the course's table (and the pak) or the row the native helper searches for.
    shipped = offered
    offered = [o for o in offered if o["id"] not in DROPPED and o["id"] not in SAME_AS]
    left_out += [(name, why) for name, why in DROPPED.items()]
    left_out += [(name, "named and fought as %s, which is offered" % kept) for name, kept in SAME_AS.items()]
    # The game's English name (the fallback when its text can't be looked up) and the tag; no two may read the same.
    english = {}
    with open(NAMES, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) == 2 and p[0].startswith("mobcolvr_"):
                english[p[0]] = p[1]
    shown = {}
    for o in offered:
        o["name"], o["tag"] = english.get(o["id"], ""), TAGS.get(o["id"], "")
        if not o["name"]:
            sys.exit("no English name for %s in %s" % (o["id"], NAMES))
        full = o["name"] + (" (%s)" % o["tag"] if o["tag"] else "")
        if full in shown:
            sys.exit("two opponents read %r: %s and %s (add one to SAME_AS or TAGS)" % (full, shown[full], o["id"]))
        shown[full] = o["id"]
    for t in list(SAME_AS) + list(TAGS):
        if t not in {s["id"] for s in shipped}:
            sys.exit("%s is not a template" % t)
    # The territory's own 16 waves: the first 16 opponents. The Lua finds the loaded row in memory by exactly this
    # list (and its levels), so it must stay unique: no vanilla territory has it.
    base = shipped[:SLOTS]
    first = shipped[0]["id"]
    spec = {"tables": [{"asset": "DataObject/Resident/EnemyTerritory.uasset", "rows": [{"name": TERRITORY, "set": {
        # The course opens with one copy of the first opponent; the Lua replaces it with the player's choice at once.
        "FieldAINameList_Array": ["Stay"],
        "MobTemplateList_Array": [first], "MinPopList_Array": ["1"], "MaxPopList_Array": ["1"],
        "MobLevelList_Array": [str(shipped[0]["level"])],
        "WaveMobTemplateList_Array": [o["id"] for o in base],
        "WaveMobLevelList_Array": [str(o["level"]) for o in base],
        "WavePopSettingList_Array": ["0"] * SLOTS,
        "WaveBattleSceneAerialEnemyFlag_Array": ["0"] * SLOTS,
        "SummonConditionID": "",
    }}]}]}
    out = os.path.join(ROOT, "data", "custom-training", "generated.json")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("// Generated by tools/custom-training/make_spec.py from the Epic 1.005 tables. Do not edit.\n")
        json.dump(spec, f, indent=1)

    reach, ordinary = stage_rule()
    for o in offered:
        o["needs"] = needs_of([o["id"]] + [h[1] for h in o["home"]], reach, ordinary)
    courses_out, rounds_left = rounds(courses, territories, mobs, specs, {o["id"] for o in offered})

    lua = ["-- Generated by tools/custom-training/make_spec.py from the Epic 1.005 tables. Do not edit.",
           "-- base: the course territory's 16 waves as shipped (template, level), which the native helper searches for.",
           "-- opponents: every opponent offered: template, BattleCharaSpec, name key, the game's English name (when the key",
           "-- can't be looked up), tag (the plain word after the name, for two the game names alike), menu category, level,",
           "-- the wave slot it is spawned from, cap (most copies, only where 3 break), boss (for the test tools only:",
           "-- the game doesn't cap them), air (a flyer: the tables mark it aerial), needs (metres of room around the centre,",
           "-- Stages' rule), and home: the waves its own scripts start, as",
           "-- { slot, template, level }.",
           "-- courses: the simulator's courses for Round mode, in the game's order: row, title key, tab, and the rounds that",
           "-- work: territory, number, the opening enemies { template, count, level, model spec, the offered template it",
           "-- reads as } and the round's own waves { slot, template, level } (the adds its enemies' scripts start).",
           "return {", '    territory = "%s",' % TERRITORY, "    base = {"]
    for o in base:
        lua.append('        { id = "%s", level = %d },' % (o["id"], o["level"]))
    lua += ["    },", "    opponents = {"]
    for o in offered:
        home = ", ".join('{ %d, "%s", %d }' % h for h in o["home"])
        tag = ', tag = "%s"' % o["tag"] if o["tag"] else ""
        if o["id"] in CAPS:
            tag += ", cap = %d" % CAPS[o["id"]]
        if o["air"]:
            tag += ", air = true"
        tag += ", needs = %g" % o["needs"]
        lua.append('        { id = "%s", spec = "%s", chara = "%s", label = "%s", name = "%s"%s, category = %d, level = %d, slot = %d, boss = %s, home = { %s } },'
                   % (o["id"], o["spec"], o["chara"], o["label"], o["name"].replace('"', '\\"'), tag, o["category"], o["level"],
                      o["slot"], "true" if o["boss"] else "false", home))
    lua += ["    },", "    courses = {"]
    for c in courses_out:
        lua.append('        { id = "%s", label = "%s", name = "%s", tab = %d, needs = %g, rounds = {' % (
            c["id"], c["label"], c["name"].replace('"', '\\"'), c["tab"], c["needs"]))
        for r in c["rounds"]:
            mob_text = ", ".join('{ "%s", %d, %d, "%s", "%s" }' % m for m in r["mobs"])
            wave_text = ", ".join('{ %d, "%s", %d }' % w for w in r["waves"])
            lua.append('            { id = "%s", number = %d, mobs = { %s }, waves = { %s } },' % (r["id"], r["number"], mob_text, wave_text))
        lua.append("        } },")
    lua += ["    },", "}", ""]
    with open(os.path.join(ROOT, "ue4ss", "SimOverhaulCustomTraining", "Scripts", "ct_catalogue.lua"), "w",
              encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lua))

    with open(os.path.join(ROOT, "data", "custom-training", "opponents.tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("template\tname\tspec\tname key\tcategory\tlevel\tlevel from\tspawn slot\tboss\tneeds m\tits own waves\n")
        for o in offered:
            f.write("%s\t%s\t%s\t%s\t%d\t%d\t%s\t%d\t%s\t%g\t%s\n" % (
                o["id"], o["name"] + (" (%s)" % o["tag"] if o["tag"] else ""), o["spec"], o["label"], o["category"], o["level"],
                "vanilla course" if o["fought"] else "default", o["slot"], "boss" if o["boss"] else "", o["needs"],
                " ".join("%d:%s" % (i, w.replace("mobcolvr_", "")) for i, w, _ in o["home"])))
        f.write("\nleft out\treason\n")
        for name, why in left_out:
            f.write("%s\t%s\n" % (name, why))
    with open(os.path.join(ROOT, "data", "custom-training", "rounds.tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("course\tname\ttab\tround\tnumber\tenemies\tsize\tits own waves\n")
        for c in courses_out:
            for r in c["rounds"]:
                f.write("%s\t%s\t%d\t%s\t%d\t%s\t%d\t%s\n" % (c["id"], c["name"], c["tab"], r["id"], r["number"],
                    ", ".join("%s x%d (lv %d)" % (english.get(m[4], m[0]), m[1], m[2]) for m in r["mobs"]),
                    sum(m[1] for m in r["mobs"]), " ".join("%d:%s" % (w[0], w[1].replace("mobcolvr_", "")) for w in r["waves"])))
        f.write("\nleft out\tround\treason\n")
        for course, rid, why in rounds_left:
            f.write("%s\t%s\t%s\n" % (course, rid, why))
    n_rounds = sum(len(c["rounds"]) for c in courses_out)
    print("%d opponents, %d left out; %d rounds in %d courses, %d rounds left out" % (
        len(offered), len(left_out), n_rounds, len(courses_out), len(rounds_left)))


# Round mode (owner, 2026-11-21): a vanilla round of any simulator course, spawned as the round defines it. A round
# is its opening enemies (MobTemplateList, MaxPop each) and its waves (WaveMobTemplateList), which in the simulator's
# rounds are the adds its enemies' own scripts start by wave number: the Lua writes them into the same wave numbers of
# our territory, and spawns the opening enemies from free ones. Courses: those fought in the simulator's arena
# (BattleWarpPoint Point_VRBattle), in the table's order.
TUTORIAL_TAB = 7


# Room (owner 2026-11-21: filter opponents by stage, don't limit stages). The Stages part offers Custom Training on
# every stage, and Custom Training refuses what doesn't fit the stage it's on. Stages' own rule, from its generator
# (components/stages/tools/make_courses.py, one source): an ordinary fight needs 12 m of clear floor around the
# centre; an enemy whose scripts use far points needs their reach (Phoenix 28.3, Sephiroth 26.5, Odin 24.9,
# Mindflayer 22.4, Alexander 22.0, 8eye 15.7, any summon 14). An opponent: that rule over its template and its adds.
# A round: its course's needs_m, as Stages keeps it (it also counts fixed pop points, which our spawns don't use, so
# it errs on the side of room).
def stage_rule():
    import importlib.util
    path = os.path.join(ROOT, "components", "stages", "tools", "make_courses.py")
    spec = importlib.util.spec_from_file_location("make_courses", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.REACH, mod.ORDINARY[0]


def needs_of(templates, reach, ordinary):
    import re
    need = ordinary
    for pattern, metres, _ in reach:
        if metres > need and any(re.search(pattern, t) for t in templates):
            need = metres
    return need


def course_needs():
    import re
    with open(STAGES_DATA, encoding="utf-8") as f:
        text = f.read()
    return {k: float(v) for k, v in re.findall(r'key = "([^"]+)",\s*title_id = "[^"]*",\s*title = "[^"]*",\s*needs_m = ([\d.]+)', text)}
# The game's English course titles, as the Stages part keeps them (read in the game for its picker): the fallback when
# a title key can't be looked up.
STAGES_DATA = os.path.join(ROOT, "ue4ss", "SimOverhaulStages", "Scripts", "stages", "data.lua")
# Shinra Manor's simulator (the NIBLS courses) shares tab numbers 1 and 2 with Chadley's: tabs of their own here.
MANOR_TABS = {1: 8, 2: 9}


def course_titles():
    import re
    with open(STAGES_DATA, encoding="utf-8") as f:
        text = f.read()
    return dict(re.findall(r'key = "([^"]+)",\s*title_id = "[^"]*",\s*title = "([^"]*)"', text))
ROUND_MAX = 8  # the most opening enemies of any simulator round that works (Brutal Challenges)


def rounds(courses, territories, mobs, specs, offered_ids):
    def to_offered(template):
        t = SAME_AS.get(template, template)
        return t if t in offered_ids else None
    out, left = [], []
    titles = course_titles()
    room = course_needs()
    for cname, c in courses.items():
        if c.get("BattleWarpPoint") != "Point_VRBattle" or c.get("IsVRMission") != "1":
            continue
        tab = int(c.get("TabCategory") or 0)
        if "_NIBLS_" in cname:
            tab = MANOR_TABS.get(tab, tab)
        terr = [t for t in split(c.get("EnemyTerritoryID_Array", "")) if t]
        kept = []
        for number, tname in enumerate(terr, 1):
            t = territories.get(tname)
            why = None
            round_mobs, waves = [], []
            if tab == TUTORIAL_TAB:
                why = "Combat Training tutorial: a fixed party, and the round runs the tutorial's prompts"
            elif t is None:
                why = "no territory row"
            elif [x for x in split(t.get("BattleConditionTriggerGroupId_Array", "")) if x]:
                why = "the round's own battle triggers (BattleConditionTriggerGroupId)"
            elif t.get("BattleSceneBluePrint") not in ("", "None", None):
                why = "its own battle scene (%s)" % t.get("BattleSceneBluePrint")
            if why is None:
                names = split(t.get("MobTemplateList_Array", ""))
                counts = split(t.get("MaxPopList_Array", ""))
                levels = split(t.get("MobLevelList_Array", ""))
                bad = []
                for i, m in enumerate(names):
                    if not m:
                        continue
                    n = int(counts[i]) if i < len(counts) and counts[i].isdigit() else 1
                    lv = int(levels[i]) if i < len(levels) and levels[i].isdigit() else DEFAULT_LEVEL
                    as_id = to_offered(m)
                    row = mobs.get(m)
                    spec = specs.get(row["BattleCharaSpecID"]) if row else None
                    if as_id is None or spec is None:
                        bad.append(m.replace("mobcolvr_", "") + (": " + DROPPED[m] if m in DROPPED else ": not an opponent"))
                        continue
                    round_mobs.append((m, n, lv, spec.get("CharaSpecID", "") or row["BattleCharaSpecID"], as_id))
                wnames, wlevels = split(t.get("WaveMobTemplateList_Array", "")), split(t.get("WaveMobLevelList_Array", ""))
                for i, w in enumerate(wnames):
                    if w:
                        lv = int(wlevels[i]) if i < len(wlevels) and wlevels[i].isdigit() and int(wlevels[i]) > 0 else DEFAULT_LEVEL
                        waves.append((i, w, lv))
                size = sum(m[1] for m in round_mobs)
                if bad:
                    why = "opening enemy left out: " + "; ".join(bad)
                elif not round_mobs:
                    why = "no opening enemy"
                elif size > ROUND_MAX:
                    why = "%d opening enemies (at most %d)" % (size, ROUND_MAX)
                elif any(w[0] >= SLOTS for w in waves) or len(waves) + len({m[0] for m in round_mobs}) > SLOTS:
                    why = "more waves and enemies than the territory's %d slots" % SLOTS
            if why:
                left.append((cname, tname, why))
            else:
                kept.append({"id": tname, "number": number, "mobs": round_mobs, "waves": waves})
        if kept:
            out.append({"id": cname, "label": c.get("ItemName", ""), "name": titles.get(cname, cname), "tab": tab,
                        "needs": room.get(cname, 12.0), "rounds": kept})
    out.sort(key=lambda c: c["tab"])  # stable: the table's order within a tab
    return out, left


if __name__ == "__main__":
    main()
