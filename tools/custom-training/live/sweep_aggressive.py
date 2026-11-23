"""Every Custom Training opponent in Aggressive: does it attack, and does anything look wrong (owner 2026-11-21).

usage: sweep_aggressive.py [--from N] [--only TEMPLATE ...] [--seconds S]
Needs the game lock, a development install (dev.txt) and the course running with Cloud alone (begin scripts). Cloud
is given no command, so every hit he takes is the opponent's (or its adds'). Results go to
data/custom-training/sweep-aggressive.tsv, one line per opponent, appended as it goes; opponents already there are
skipped, so a crash or a stop can be resumed.

Columns:
  template, boss
  appeared     seconds until it was among the course's enemies (empty: it never came)
  attacks      hits Cloud took while watched, the HP they took, and the seconds to the first one
  attack names what the harness's observe_combat said the enemies were doing, when it said anything
  refills      the course's party refills (Aggressive refills below 50%) and the MP it gave back
  distance     metres from Cloud when it appeared, and at the end
  moved        the furthest it went from where it appeared (metres)
  height       its height against Cloud's at the end (metres; far below: through the floor)
  hidden       the game's own hidden flag on the opponent
  adds         other enemies of ours seen with it (their spec families)
  left behind  enemies of the previous opponent still there 3 s after this one appeared
  course       still running at the end (the round never ended), crash
  result       pass, or what failed
"""
import json, math, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ct_live  # noqa: E402
from ct_live import op, state, command  # noqa: E402
import sweep  # noqa: E402  (catalogue reading, relaunch)

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
OUT = os.path.join(REPO, "data", "custom-training", "sweep-aggressive.tsv")
COLUMNS = ["template", "boss", "appeared", "hits", "damage", "first hit", "attack names", "party refills", "mp given",
           "distance start", "distance end", "moved", "height", "hidden", "adds", "left behind", "course", "result",
           "note"]
APPEAR_SECONDS = 25
FAR_M, BELOW_M, IDLE_M = 40.0, 6.0, 0.5


def done():
    if not os.path.exists(OUT):
        with open(OUT, "w", encoding="utf-8", newline="\n") as f:
            f.write("\t".join(COLUMNS) + "\n")
        return set()
    with open(OUT, encoding="utf-8") as f:
        return {line.split("\t")[0] for line in f.readlines()[1:] if line.strip()}


def record(row):
    with open(OUT, "a", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(str(row.get(c, "")) for c in COLUMNS) + "\n")
    print(row.get("template"), row.get("result"), "hits", row.get("hits"), row.get("note"), flush=True)


def dist(a, b):
    if not a or not b or a.get("x") is None or b.get("x") is None:
        return None
    return math.sqrt((a["x"] - b["x"]) ** 2 + (a["y"] - b["y"]) ** 2 + (a["z"] - b["z"]) ** 2) / 100.0


def attack_words(obs):
    """Strings the harness gives about enemy actions (any key naming an attack, action or skill)."""
    found = set()

    def walk(v, key=""):
        if isinstance(v, dict):
            for k, x in v.items():
                walk(x, k)
        elif isinstance(v, list):
            for x in v:
                walk(x, key)
        elif isinstance(v, str) and re.search(r"attack|action|skill|incoming", key, re.I) and v:
            found.add(v[:40])
        elif v is True and re.search(r"attack_incoming", key, re.I):
            found.add(key)
    walk(obs)
    return found


def main():
    args = sys.argv[1:]
    start = int(args[args.index("--from") + 1]) if "--from" in args else 0
    only = set(args[args.index("--only") + 1:]) if "--only" in args else None
    watch = float(args[args.index("--seconds") + 1]) if "--seconds" in args else 20.0
    skip = done()
    previous_keys = set()
    for i, o in enumerate(sweep.opponents()):
        if i < start or o["id"] in skip or (only and o["id"] not in only):
            continue
        if not sweep.game_alive() or not state().get("active"):
            print("relaunching", flush=True)
            if not sweep.relaunch():
                print("could not get back into the course; stopping", flush=True)
                return
            previous_keys = set()
        row = {"template": o["id"], "boss": "boss" if o["boss"] else ""}
        t0 = time.time()
        command("set opponent=%s count=1 behaviour=aggressive difficulty=normal" % o["id"])
        mine, crashed = None, False
        while time.time() - t0 < APPEAR_SECONDS:
            if not sweep.game_alive():
                crashed = True
                break
            s = state()
            current = [e for e in s.get("enemies", []) if not e.get("stale")]
            hit = [e for e in current if e.get("spec") == o["family"]]
            if hit and s.get("opponent") == o["id"]:
                mine = hit[0]
                break
            if s.get("opponent") not in (None, o["id"]):
                break
            time.sleep(0.5)
        if crashed:
            row.update(course="crash", result="crash while spawning")
            record(row)
            continue
        if mine is None:
            row.update(result="never appeared", note="the mod gave up on it" if state().get("opponent") != o["id"] else "")
            record(row)
            continue
        appeared_at = time.time()
        row["appeared"] = round(appeared_at - t0, 1)
        s = state()
        start_spot = {k: mine.get(k) for k in ("x", "y", "z")}
        d0 = dist(mine, s.get("leader"))
        row["distance start"] = "" if d0 is None else round(d0, 1)
        hits0, dmg0 = s.get("hits", 0), s.get("damage", 0)
        first_hit, moved, names, adds, left = None, 0.0, set(), set(), ""
        while time.time() - appeared_at < watch:
            time.sleep(1.0)
            if not sweep.game_alive():
                crashed = True
                break
            s = state()
            if not s.get("active"):
                time.sleep(1.0)
                s = state()  # a state file read while it was being written looks inactive: ask again
                if not s.get("active"):
                    break
            ours = [e for e in s.get("enemies", []) if not e.get("stale")]
            me = [e for e in ours if e.get("key") == mine.get("key")]
            if me:
                m = dist(me[0], start_spot)
                if m is not None:
                    moved = max(moved, m)
                mine = me[0]
            adds |= {re.match(r"^([A-Z]{2}\d+_\d+)", e.get("spec") or "").group(1) if re.match(r"^([A-Z]{2}\d+_\d+)", e.get("spec") or "") else (e.get("spec") or "")
                     for e in ours if e.get("key") != mine.get("key")}
            if first_hit is None and s.get("hits", 0) > hits0:
                first_hit = round(time.time() - appeared_at, 1)
            if left == "" and time.time() - appeared_at >= 3:
                left = str(len([e for e in s.get("enemies", []) if e.get("key") in previous_keys]))
            try:
                names |= attack_words(op("observe_combat").get("result") or {})
            except Exception:
                pass
            # enough evidence: two hits and some seconds watched
            if s.get("hits", 0) - hits0 >= 2 and time.time() - appeared_at >= 8:
                break
        if crashed:
            row.update(course="crash", result="crash while fighting")
            record(row)
            continue
        s = state()
        leader = s.get("leader")
        d1 = dist(mine, leader)
        row.update({
            "hits": s.get("hits", 0) - hits0, "damage": s.get("damage", 0) - dmg0,
            "first hit": "" if first_hit is None else first_hit, "attack names": "; ".join(sorted(names))[:120],
            "party refills": s.get("party_refills", 0), "mp given": sum((s.get("mp_refilled") or {}).values()),
            "distance end": "" if d1 is None else round(d1, 1), "moved": round(moved, 1),
            "height": "" if not leader or mine.get("z") is None else round((mine["z"] - leader["z"]) / 100.0, 1),
            "hidden": "yes" if mine.get("hidden") else "", "adds": " ".join(sorted(a for a in adds if a)),
            "left behind": left, "course": "running" if s.get("active") else "ended",
        })
        problems = []
        if row["hits"] == 0:
            problems.append("never hit Cloud")
        if d1 is not None and d1 > FAR_M:
            problems.append("far away (%d m)" % d1)
        if row["height"] != "" and row["height"] < -BELOW_M:
            problems.append("below the floor")
        if mine.get("hidden"):
            problems.append("hidden")
        if moved < IDLE_M and row["hits"] == 0:
            problems.append("never moved")
        if left not in ("", "0"):
            problems.append("previous opponent left behind")
        if not s.get("active"):
            problems.append("round ended")
        row["result"] = "pass" if not problems else "; ".join(problems)
        record(row)
        previous_keys = {e.get("key") for e in s.get("enemies", [])}


if __name__ == "__main__":
    main()
