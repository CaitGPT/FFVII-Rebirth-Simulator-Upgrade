"""Spawn every Custom Training opponent once, alone, in a running course, and record what happened.

usage: sweep.py [--from N] [--only TEMPLATE ...]
Needs the game lock, a development install (dev.txt) and the course running (to_course.py). Results go
to data/custom-training/sweep.tsv, one line per opponent, appended as it goes, so a crash or a stop can be resumed:
opponents already in the file are skipped.

Columns: template, boss, result (ok | no_spawn | crash | wrong), seconds to appear, max HP, enemies of ours seen
(the opponent and any adds), note.
"""
import json, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ct_live  # noqa: E402
from ct_live import op, state, command  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))  # tools/custom-training/live -> repo
CATALOGUE = os.path.join(REPO, "ue4ss", "SimOverhaulCustomTraining", "Scripts", "ct_catalogue.lua")
OUT = os.path.join(REPO, "data", "custom-training", "sweep.tsv")
TO_COURSE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "to_course.py")
APPEAR_SECONDS, WATCH_SECONDS = 25, 5


def opponents():
    text = open(CATALOGUE, encoding="utf-8").read()
    text = text[text.index("opponents = {"):]
    out = []
    for m in re.finditer(r'id = "([^"]+)", spec = "([^"]+)", chara = "([^"]+)", label = "[^"]*", name = "((?:[^"\\]|\\.)*)"(?:, tag = "([^"]*)")?.*?boss = (true|false)', text):
        spec = m.group(3)  # the model's spec, which the game reports
        fam = re.match(r"^([A-Z]{2}\d+_\d+)", spec)
        out.append({"id": m.group(1), "battle_spec": m.group(2), "spec": spec, "family": fam.group(1) if fam else spec,
                    "name": m.group(4).replace('\\"', '"'), "tag": m.group(5) or "", "boss": m.group(6) == "true"})
    return out


def done():
    if not os.path.exists(OUT):
        with open(OUT, "w", encoding="utf-8", newline="\n") as f:
            f.write("template\tboss\tresult\tseconds\tmax hp\tenemies seen\tnote\n")
        return set()
    with open(OUT, encoding="utf-8") as f:
        return {line.split("\t")[0] for line in f.readlines()[1:] if line.strip()}


def record(o, result, seconds="", max_hp="", seen="", note=""):
    with open(OUT, "a", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(str(x) for x in (o["id"], "boss" if o["boss"] else "", result, seconds, max_hp, seen, note)) + "\n")
    print(o["id"], result, seconds, max_hp, seen, note, flush=True)


def game_alive():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq ff7rebirth_.exe", "/NH"], capture_output=True, text=True).stdout
    if "ff7rebirth_" not in out:
        return False
    # A crash can leave the process up behind its "Fatal error!" box (2026-11-21): in a running course the status
    # file is written every tick, so one that stopped changing means the game has stopped.
    path = os.path.join(ct_live.MOD, "ct-state.json")
    try:
        if state().get("active") and time.time() - os.path.getmtime(path) > 20:
            return False
    except OSError:
        pass
    return True


def relaunch():
    launched = time.time()
    subprocess.run(["taskkill", "/F", "/IM", "ff7rebirth_.exe"], capture_output=True)
    time.sleep(8)
    op("open_control_session", model_id="claude-opus-5-5", reasoning_effort="high")
    # "Continue" loads the newest save, which can be another session's (2026-11-21: one with Aerith in the party, whom
    # the opponents then chased instead of Cloud): launch only, then load slot 25 (Cloud alone), enter through
    # Chadley's talk and start the course (to_course.py; the machine is no longer part of the mod, main 6bb514e).
    subprocess.run([sys.executable, TO_COURSE, "launch", "noenter"], check=False)
    subprocess.run([sys.executable, TO_COURSE], check=False)
    # Only a state file written after this launch counts (2026-11-21: the last launch's file, still saying "active",
    # made a relaunch that never started the course look done).
    for _ in range(60):
        try:
            fresh = os.path.getmtime(os.path.join(ct_live.MOD, "ct-state.json")) > launched
        except OSError:
            fresh = False
        if fresh and state().get("active") and state().get("difficulty_now"):
            return True
        time.sleep(2)
    return False


def main():
    args = sys.argv[1:]
    start = int(args[args.index("--from") + 1]) if "--from" in args else 0
    only = set(args[args.index("--only") + 1:]) if "--only" in args else None
    skip = done()
    for i, o in enumerate(opponents()):
        if i < start or o["id"] in skip or (only and o["id"] not in only):
            continue
        if not game_alive() or not state().get("active"):
            print("relaunching", flush=True)
            if not relaunch():
                print("could not get back into the course; stopping", flush=True)
                return
        t0 = time.time()
        command("set opponent=%s count=1 behaviour=passive difficulty=normal" % o["id"])
        appeared, max_hp, crashed, family_seen = None, "", False, None
        while time.time() - t0 < APPEAR_SECONDS:
            if not game_alive():
                crashed = True
                break
            s = state()
            current = [e for e in s.get("enemies", []) if not e.get("stale")]
            mine = [e for e in current if e.get("spec") == o["family"]]
            if mine and s.get("opponent") == o["id"]:
                appeared, max_hp = round(time.time() - t0, 1), mine[0].get("max")
                family_seen = mine[0].get("spec")
                break
            if s.get("opponent") not in (None, o["id"]):
                break  # the mod gave up on it and went back
            time.sleep(0.5)
        if crashed:
            record(o, "crash", note="game exited while spawning")
            continue
        if appeared is None:
            s = state()
            gave_up = s.get("opponent") != o["id"]
            record(o, "no_spawn", note="the mod gave up on it" if gave_up else "nothing within %d s" % APPEAR_SECONDS)
            continue
        # watch it for a few seconds: still there, game alive, what else came with it
        time.sleep(WATCH_SECONDS)
        if not game_alive():
            record(o, "crash", appeared, max_hp, note="game exited after it appeared")
            continue
        s = state()
        specs = sorted({e.get("spec") for e in s.get("enemies", []) if not e.get("stale")})
        still = any(e.get("spec") == family_seen for e in s.get("enemies", []))
        note = "" if family_seen == o["family"] else "appears as %s" % family_seen
        if not still:
            note = (note + "; " if note else "") + "gone after %d s" % WATCH_SECONDS
        record(o, "ok" if still else "wrong", appeared, max_hp, " ".join(specs), note)


if __name__ == "__main__":
    main()
