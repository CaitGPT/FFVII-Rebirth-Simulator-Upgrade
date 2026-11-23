"""gimmick_watch.py TEMPLATE [TEMPLATE ...] [--fight S]: a watched run of each gimmick opponent (owner 2026-11-21: every
opponent with phases, adds, pillars, eggs, avatars or ultimates proceeds as in vanilla, and a change mid-gimmick
leaves nothing behind).

For each opponent, alone, Normal:
  1. Aggressive, the harness's autopilot fighting for S seconds (default 60): screenshots at 10 s and S-10 s; the adds
     seen (enemies of ours that are no member), the most damage sources (bullets, orbs) at once.
  2. Its HP phases: the dev command "hp 50", 15 s, then "hp 20", 15 s (Aggressive refills only below 2%, so they
     stay): a screenshot after each; the abilities the harness's log names over the whole run are the evidence that
     phases, ultimates and add waves happened.
  3. A change mid-gimmick: with its adds out, the opponent is replaced by a Bomb; 6 s later the enemies and damage
     sources left from it are counted (only the Bomb and the anchor should remain), and a screenshot.
  4. Passive: the opponent again, held, 20 s: a screenshot (nothing frozen into a broken state).
Results: data/custom-training/gimmicks.tsv (one row per opponent, appended), shots in docs/workstreams/custom-training/
gimmicks/. Needs the game lock and a running Custom Training course with Cloud alone.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ct_live  # noqa: E402
from ct_live import op, state, command  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
OUT = os.path.join(REPO, "data", "custom-training", "gimmicks.tsv")
SHOTS = os.path.join(REPO, "docs", "workstreams", "custom-training", "gimmicks")
BOMB = "mobcolvr_EN2015_00_Bomb_Standard_00"
COLUMNS = ["template", "name", "appeared", "abilities", "adds seen", "most adds", "most damage sources", "hp 50", "hp 20",
           "left after change (enemies)", "left after change (damage sources)", "damage sources before",
           "damage sources at the start", "passive",
           "party caught", "shots", "note"]


def shot(name):
    p = (op("capture_game_window").get("result") or {}).get("image_path")
    if not p:
        return ""
    os.makedirs(SHOTS, exist_ok=True)
    out = os.path.join(SHOTS, name + ".jpg")
    subprocess.run(["powershell", "-NoProfile", "-Command",
                    "Add-Type -AssemblyName System.Drawing; $i=[System.Drawing.Image]::FromFile('%s'); "
                    "$b=New-Object System.Drawing.Bitmap $i,1280,720; $b.Save('%s',[System.Drawing.Imaging.ImageFormat]::Jpeg)" % (p, out)],
                   check=False)
    return os.path.basename(out)


def ours(s, members=None):
    return [e for e in s.get("enemies", []) if not e.get("stale") and not e.get("anchor")
            and (members is None or bool(e.get("member")) == members)]


def watch(seconds, sample):
    t0 = time.time()
    while time.time() - t0 < seconds:
        sample(state())
        time.sleep(1)


def run(template, fight):
    row = {"template": template}
    short = template.replace("mobcolvr_", "")[:40]
    # The enemies there before (the last opponent, its adds): not this one's. Waited for until gone, so neither its
    # members nor its adds are taken for this one's (the first run read "appeared 0.0 s" off the one before).
    old = {e["key"] for e in state().get("enemies", []) if not e.get("anchor")}
    row["damage sources at the start"] = state().get("damage_sources")
    command("set opponent=%s count=1 behaviour=aggressive difficulty=normal" % template)
    t0 = time.time()

    def mine(s):
        return [e for e in ours(s, True) if e["key"] not in old and (e.get("hp") or 0) > 0]

    while time.time() - t0 < 30:
        s = state()
        if s.get("opponent") == template and mine(s):
            break
        time.sleep(1)
    row["appeared"] = round(time.time() - t0, 1) if mine(state()) else "no"
    row["name"] = state().get("name")
    adds, most, ds_most = set(), 0, 0

    def sample(s):
        nonlocal most, ds_most
        a = [e for e in ours(s, False) if e["key"] not in old]
        adds.update(e.get("model") for e in a)
        most = max(most, len(a))
        ds_most = max(ds_most, s.get("damage_sources") or 0)

    job = op("combat_autopilot_async", seconds=fight + 40, execute=True, category="simulation").get("job_id")
    shots = []
    watch(10, sample)
    shots.append(shot(short + "-fight"))
    watch(max(0, fight - 20), sample)
    shots.append(shot(short + "-late"))
    command("hp 50")
    watch(15, sample)
    shots.append(shot(short + "-hp50"))
    row["hp 50"] = "set"
    command("hp 20")
    watch(15, sample)
    shots.append(shot(short + "-hp20"))
    row["hp 20"] = "set"
    abilities = ""
    if job:
        # Harness PR 791: the fight can be ended at once (the older runtime refuses this; then it is waited out).
        op("cancel_combat_autopilot", job_id=job)
        while True:
            st = op("get_combat_autopilot_status", job_id=job)
            if st.get("state") != "running":
                break
            sample(state())
            time.sleep(2)
        res = ((st.get("response") or {}).get("result") or {})
        review = (op("review_combat_log", path=res.get("log_path")).get("result") or {}) if res.get("log_path") else {}
        ab = review.get("enemy_abilities") or {}
        abilities = "; ".join("%s x%d" % (k, v) for k, v in sorted(ab.items()))
    row["abilities"] = abilities
    # 3. change mid-gimmick
    before = state()
    old_keys = {e["key"] for e in ours(before)}
    row["damage sources before"] = before.get("damage_sources")
    command("set opponent=%s count=1 behaviour=aggressive" % BOMB)
    time.sleep(6)
    after = state()
    left = [e for e in after.get("enemies", []) if e.get("key") in old_keys and not e.get("anchor")]
    row["left after change (enemies)"] = len(left)
    time.sleep(2)
    x = state()
    row["left after change (damage sources)"] = "%s of %s" % (x.get("damage_sources_left"), x.get("damage_sources_at_change"))
    shots.append(shot(short + "-after-change"))
    # 4. passive
    command("set opponent=%s count=1 behaviour=passive" % template)
    time.sleep(20)
    p = state()
    row["passive"] = "%d of its own, held" % len(ours(p, True))
    shots.append(shot(short + "-passive"))
    row.update({"adds seen": " ".join(sorted(a for a in adds if a)), "most adds": most, "most damage sources": ds_most,
                "party caught": p.get("caught"), "shots": " ".join(s for s in shots if s)})
    return row


# Every opponent with phases, adds, pillars, eggs, avatars or ultimates (owner 2026-11-21), for "all".
GIMMICKS = [
    "mobcolvr_SU2000_00_Titan_Standard_00", "mobcolvr_SU2040_01_Phoenix_Standard_00",
    "mobcolvr_SU2030_01_Alexander_Standard_00", "mobcolvr_SU2020_01_Kjata_Standard_00",
    "mobcolvr_SU2050_01_NeoBahamut_Standard_00", "mobcolvr_SU2015_00_Sleipnir_Standard_00",
    "mobcolvr_SU2000_01_Titan_GilQuest_00", "mobcolvr_SU2040_01_Phoenix_GilQuest_00",
    "mobcolvr_SU2030_01_Alexander_GilQuest_00", "mobcolvr_SU2020_01_Kjata_GilQuest_00",
    "mobcolvr_SU2050_01_NeoBahamut_GilQuest_00", "mobcolvr_SU2015_01_Sleipnir_GilQuest_00",
    "mobcolvr_SU2060_01_Gilgamesh_Standard_00", "mobcolvr_SU2060_01_Gilgamesh_Hard_00",
    "mobcolvr_PC0010_20_Sephiroth_VRHard_00", "mobcolvr_EN2017_02_Tonberry_KingEnd2_00",
    "mobcolvr_EN2216_00_Mindflayer_StandardEnd2_00", "mobcolvr_EN2244_00_GiSpector_SpearEnd2_00",
    "mobcolvr_EN2243_00_Jabberwock_StandardEnd2_00", "mobcolvr_EN2256_00_Adamantaimai_StandardEnd2_00",
    "mobcolvr_EN2248_00_KillerBee_StandardEnd2_00", "mobcolvr_EN2101_05_HereticRayleigh_SubspeciesEnd2_00",
    "mobcolvr_EN2217_00_Grangalan_StandardEnd2_00", "mobcolvr_EN0200_00_DevilRide_StandardEnd2_00",
    "mobcolvr_EN2003_03_PuzoCute_TropicalRareEnd2_00", "mobcolvr_EN2205_00_Mandragora_StandardEnd2_00",
    "mobcolvr_EN3001_04_VagidPolice_SephirothEnd2_00",
]


def main(argv):
    fight = 60
    if "--fight" in argv:
        i = argv.index("--fight")
        fight = int(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    if argv == ["all"]:
        argv = GIMMICKS
    new = not os.path.exists(OUT)
    with open(OUT, "a", encoding="utf-8", newline="\n") as f:
        if new:
            f.write("\t".join(COLUMNS) + "\n")
        for template in argv:
            row = run(template, fight)
            f.write("\t".join(str(row.get(c, "")) for c in COLUMNS) + "\n")
            f.flush()
            print("\t".join("%s=%s" % (c, str(row.get(c, ""))[:60]) for c in COLUMNS[:12]), flush=True)
    command("set opponent=%s count=1 behaviour=aggressive" % BOMB)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
