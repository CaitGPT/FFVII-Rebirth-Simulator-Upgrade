"""Every Custom Training opponent in Aggressive, with the harness's guard probe as the evidence that it attacks.

usage: sweep_probe.py [--from N] [--seconds S] [--count N] [--bosses] [--out FILE] [--only TEMPLATE ...]
Needs the game lock, a development install and the course running with Cloud alone. For each opponent: set it
(Aggressive, Normal, one copy), wait until it is among the course's enemies, then run combat_autopilot_async with
probe=guard for S seconds (Cloud guards and sends no command) and read its combat log. The log names every ability the
enemies used, who they aimed at, the damage Cloud took and the statuses he suffered: an opponent passes on its own
abilities, not on Cloud's HP (a status left by the previous opponent, like poison, keeps taking HP: the first,
HP-only sweep, sweep-aggressive.tsv, was fooled by that).

Also the name: the combat log's name for the enemy that came (the harness's own naming; a difference is a note, as the
menu name is the game's own text), and the hidden anchor must stay away from the party.

Results: data/custom-training/sweep-probe.tsv, appended as it goes; opponents already there are skipped.
"""
import json, math, os, re, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from ct_live import op, state, command  # noqa: E402
import sweep  # noqa: E402  (catalogue, relaunch, game_alive)

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
OUT = os.path.join(REPO, "data", "custom-training", "sweep-probe.tsv")
COLUMNS = ["template", "boss", "menu name", "harness name", "spec row", "model", "anchor", "appeared", "copies",
           "most of ours", "most adds", "closest pair", "fps min", "fps avg", "abilities", "aims at", "damage taken", "statuses", "enemies (log)",
           "distance start", "distance end", "moved", "height", "hidden", "adds", "left behind", "course", "result",
           "note"]
APPEAR_SECONDS = 25
FAR_M, BELOW_M = 40.0, 6.0
ANCHOR_NEAR_M = 10.0  # the anchor is stashed far off, hidden, held and untargetable; this near, it could be bumped into


def done():
    global OUT
    if "--out" in sys.argv:
        OUT = os.path.join(REPO, "data", "custom-training", sys.argv[sys.argv.index("--out") + 1])
    if not os.path.exists(OUT):
        with open(OUT, "w", encoding="utf-8", newline="\n") as f:
            f.write("\t".join(COLUMNS) + "\n")
        return set()
    with open(OUT, encoding="utf-8") as f:
        return {line.split("\t")[0] for line in f.readlines()[1:] if line.strip()}


def record(row):
    with open(OUT, "a", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(str(row.get(c, "")).replace("\t", " ") for c in COLUMNS) + "\n")
    print(row.get("template"), row.get("result"), "|", str(row.get("abilities"))[:90], flush=True)


def dist(a, b):
    if not a or not b or a.get("x") is None or b.get("x") is None:
        return None
    return math.sqrt((a["x"] - b["x"]) ** 2 + (a["y"] - b["y"]) ** 2 + (a["z"] - b["z"]) ** 2) / 100.0


def family(spec):
    m = re.match(r"^([A-Z]{2}\d+_\d+)", spec or "")
    return m.group(1) if m else (spec or "")


def probe(seconds):
    r = op("combat_autopilot_async", seconds=seconds, execute=True, probe="guard", category="simulation")
    job = r.get("job_id")
    return job


def probe_result(job):
    while True:
        s = op("get_combat_autopilot_status", job_id=job)
        if s.get("state") != "running":
            break
        time.sleep(2)
    res = ((s.get("response") or {}).get("result") or {})
    path = res.get("log_path")
    review = (op("review_combat_log", path=path).get("result") or {}) if path else {}
    return res, review


def main():
    args = sys.argv[1:]
    start = int(args[args.index("--from") + 1]) if "--from" in args else 0
    only = set(args[args.index("--only") + 1:]) if "--only" in args else None
    seconds = float(args[args.index("--seconds") + 1]) if "--seconds" in args else 25.0
    # --count N: N copies (the former bosses with 3, owner 2026-11-21); --bosses: only those the generator marks as
    # bosses; --out FILE: another table in data/custom-training (retries, the 3-copy run).
    count = int(args[args.index("--count") + 1]) if "--count" in args else 1
    bosses = "--bosses" in args
    if only:
        only = {x for x in only if x.startswith("mobcolvr_")}
    skip = done()
    previous_keys = set()
    for i, o in enumerate(sweep.opponents()):
        if i < start or o["id"] in skip or (only and o["id"] not in only) or (bosses and not o["boss"]):
            continue
        if not sweep.game_alive() or not state().get("active"):
            print("relaunching", flush=True)
            if not sweep.relaunch():
                print("could not get back into the course; stopping", flush=True)
                return
            previous_keys = set()
        row = {"template": o["id"], "boss": "boss" if o["boss"] else "",
               "menu name": o["name"] + (" (%s)" % o["tag"] if o["tag"] else "")}
        t0 = time.time()
        command("set opponent=%s count=%d behaviour=aggressive difficulty=normal" % (o["id"], count))
        mine, crashed = None, False
        while time.time() - t0 < APPEAR_SECONDS:
            if not sweep.game_alive():
                crashed = True
                break
            s = state()
            hit = [e for e in s.get("enemies", []) if not e.get("stale") and not e.get("anchor") and e.get("spec") == o["family"]]
            if hit and s.get("opponent") == o["id"]:
                mine = hit[0]
                if len(hit) >= count or time.time() - t0 > APPEAR_SECONDS - 1:
                    break
            if s.get("opponent") not in (None, o["id"]):
                break
            time.sleep(0.5)
        if crashed or mine is None:
            row.update(result="crash while spawning" if crashed else "never appeared")
            record(row)
            continue
        row["appeared"] = round(time.time() - t0, 1)
        row["copies"] = len(hit)
        s = state()
        row["harness name"], row["spec row"] = mine.get("shown") or "", mine.get("bspec") or ""
        row["model"] = mine.get("model") or ""
        start_spot = {k: mine.get(k) for k in ("x", "y", "z")}
        d0 = dist(mine, s.get("leader"))
        row["distance start"] = "" if d0 is None else round(d0, 1)
        job = probe(seconds)
        moved, adds, left, inactive, anchor_near = 0.0, set(), "", 0, float("inf")
        most_ours, most_adds, closest, fps = 0, 0, float("inf"), []
        pair_samples, stacked_samples = 0, 0
        while True:
            st = op("get_combat_autopilot_status", job_id=job)
            if st.get("state") != "running":
                break
            if not sweep.game_alive():
                crashed = True
                break
            s = state()
            inactive = inactive + 1 if not s.get("active") else 0
            ours = [e for e in s.get("enemies", []) if not e.get("stale") and not e.get("anchor")]
            for a in [e for e in s.get("enemies", []) if e.get("anchor")]:
                da = dist(a, s.get("leader"))
                if da is not None:
                    anchor_near = min(anchor_near, da)
            me = [e for e in ours if e.get("key") == mine.get("key")]
            if me:
                mine = me[0]
                m = dist(mine, start_spot)
                if m is not None:
                    moved = max(moved, m)
            adds |= {family(e.get("spec")) for e in ours if e.get("key") != mine.get("key")}
            same = [e for e in ours if e.get("spec") == o["family"]]
            most_ours = max(most_ours, len(same))
            most_adds = max(most_adds, len([e for e in ours if e.get("spec") != o["family"]]))
            here = float("inf")
            for a_i in range(len(same)):
                for b_i in range(a_i + 1, len(same)):
                    dd = dist(same[a_i], same[b_i])
                    if dd is not None:
                        here = min(here, dd)
            if here != float("inf"):
                closest = min(closest, here)
                pair_samples += 1
                stacked_samples += here < 0.5
            if s.get("fps"):
                fps.append(s["fps"])
            if left == "" and time.time() - t0 >= 4:
                left = str(len([e for e in s.get("enemies", []) if e.get("key") in previous_keys and not e.get("anchor")]))
            time.sleep(1.5)
        if crashed:
            row.update(course="crash", result="crash while fighting")
            record(row)
            continue
        res, review = probe_result(job)
        abilities = review.get("enemy_abilities") or {}
        last = (review.get("last_tick") or {}).get("enemies") or {}
        aims = sorted({str(v.get("aim", "")).split("_C_")[0].replace("PC0000_00_", "") for v in last.values() if v.get("aim")})
        s = state()
        leader = s.get("leader")
        d1 = dist(mine, leader)
        row.update({
            "abilities": "; ".join("%s x%d" % (k, v) for k, v in sorted(abilities.items())),
            "aims at": " ".join(aims), "damage taken": sum((review.get("damage_taken") or {}).values()),
            "statuses": " ".join(str(x) for x in (review.get("statuses_suffered") or [])),
            "enemies (log)": " ".join(review.get("enemies") or []),
            "distance end": "" if d1 is None else round(d1, 1), "moved": round(moved, 1),
            "height": "" if not leader or mine.get("z") is None else round((mine["z"] - leader["z"]) / 100.0, 1),
            "hidden": "yes" if mine.get("hidden") else "", "adds": " ".join(sorted(a for a in adds if a)),
            "left behind": left, "course": "running" if inactive < 2 and s.get("active") else "ended",
            "note": res.get("outcome", ""),
            "anchor": "" if anchor_near == float("inf") else round(anchor_near, 1),
            "most of ours": most_ours, "most adds": most_adds,
            "closest pair": "" if closest == float("inf") else round(closest, 1),
            "fps min": min(fps) if fps else "", "fps avg": round(sum(fps) / len(fps)) if fps else "",
        })
        problems = []
        # The combat log's names for the enemies in the fight, the anchor's "Zu" among them. They are the harness's
        # (combat_autopilot.enemy_name: the actor class's species word through its own table), not the game's text:
        # "Sweeper" for J-Unit Sweeper, "Cactuar" for Cactrot (the summon's model). So a difference is a note, and the
        # menu's name, the game's own text for the spec's TextLabel, stands. Then the model (CharaSpecID).
        # The game adds " A", " B" when two of a name are out (the anchor's Zu with a Zu opponent): compared without.
        game_names = [re.sub(r" [A-Z]$", "", n) for n in (review.get("enemies") or []) if n]
        game_names = sorted(set(game_names), key=game_names.index)
        row["harness name"] = o["name"] if o["name"] in game_names else " / ".join(game_names)
        if game_names and o["name"] not in game_names:
            row["note"] = ("harness names it %s; " % " / ".join(game_names)) + str(row.get("note", ""))
        if row["spec row"] and row["spec row"] != o["battle_spec"]:
            problems.append("spec row %s, not %s" % (row["spec row"], o["battle_spec"]))
        if row["model"] and row["model"] != o["spec"]:
            # A note, not a failure: some report their fight's spec once out (Titan SU2000_01, Gilgamesh SU2060_02).
            row["note"] = ("model %s; " % row["model"]) + str(row.get("note", ""))
        if anchor_near < ANCHOR_NEAR_M:
            problems.append("anchor %d m from the party" % anchor_near)
        # Attacked: an ability in the harness's log, or damage to the party. The log misses some moves (the Tonberry
        # King's knife took 7,722 with none logged, 2026-11-21); the party is cleaned of statuses at every change, so
        # damage is no longer the last opponent's poison.
        if not abilities and not row.get("damage taken"):
            problems.append("no attack (no ability logged, no damage)")
        elif not abilities:
            row["note"] = "attacked (damage %s), no ability in the harness's log; " % row.get("damage taken") + str(row.get("note", ""))
        if count > 1 and max(row["copies"], most_ours) < count:
            problems.append("only %d of %d appeared" % (max(row["copies"], most_ours), count))
        # Stacked: a pair inside 0.5 m for a third of the samples or more. A moment that close is melee enemies crowding
        # the party (three Goblins at 0.4 m once, moved apart 2 s after they came, 2026-11-21), not one inside another.
        stacked_share = stacked_samples / pair_samples if pair_samples else 0
        if count > 1 and stacked_share >= 1 / 3:
            problems.append("two inside each other (%.1f m apart, %d%% of the time)" % (closest, round(100 * stacked_share)))
        if fps and min(fps) < 20:
            row["note"] = ("frame rate down to %d; " % min(fps)) + str(row.get("note", ""))
        if d1 is not None and d1 > FAR_M:
            problems.append("far away (%d m)" % d1)
        if row["height"] != "" and row["height"] < -BELOW_M:
            problems.append("below the floor")
        if left not in ("", "0"):
            problems.append("previous opponent left behind")
        if row["course"] != "running":
            problems.append("round ended")
        row["result"] = "pass" if not problems else "; ".join(problems)
        record(row)
        previous_keys = {e.get("key") for e in s.get("enemies", [])}


if __name__ == "__main__":
    main()
