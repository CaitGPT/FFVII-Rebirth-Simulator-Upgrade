"""place_check.py SET [SECONDS] [--shot NAME]: apply SET through the dev bridge (e.g. "opponent=mobcolvr_SU2030_01_Alexander_Standard_00
count=3 behaviour=passive", or "group=a,b,c behaviour=aggressive", or "round=terVR_..."), then sample ct-state.json for
SECONDS (default 8) and report, per enemy of ours: its height above the floor under it less its capsule's half height
(0 = standing on the floor; flyers marked air), and per pair the centre-to-centre gap against the rule (size A + size
B + 2 m, owner 2026-11-21). --shot NAME saves a game-window capture as NAME.png beside this file's output folder.

Needs the game lock, a development install and a running Custom Training course. Prints one line per enemy and pair,
then "ok" or the problems.
"""
import math, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ct_live  # noqa: E402
from ct_live import op, state, command  # noqa: E402

GAP = 200


def main(argv):
    shot = None
    if "--shot" in argv:
        i = argv.index("--shot")
        shot = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    setting = argv[0]
    seconds = float(argv[1]) if len(argv) > 1 else 8.0
    command("set " + setting)
    held = "behaviour=passive" in setting or "behaviour=healing" in setting
    t0 = time.time()
    worst_ground, worst_gap, placed, last = {}, {}, {}, None
    while time.time() - t0 < seconds:
        s = state()
        ours = [e for e in s.get("enemies", []) if not e.get("stale") and not e.get("anchor")]
        last = ours
        for e in ours:
            # Where the mod put it, once its placing is over (tries 4: 0, 0.5, 1, 1.5 s from its appearance).
            if e.get("placed") and (e.get("placed_tries") or 0) >= 4:
                placed[e["key"]] = dict(e, x=e["placed"]["x"], y=e["placed"]["y"], z=e["placed"]["z"])
        if time.time() - t0 > 3:  # over time: judged only while held (Passive, Healing); in Aggressive they move
            for e in ours:
                if e.get("z") is not None and e.get("floor") is not None and e.get("half") is not None and not e.get("air"):
                    off = e["z"] - e["floor"] - e["half"]
                    worst_ground[e["key"]] = max(worst_ground.get(e["key"], 0), abs(off))
            for i in range(len(ours)):
                for j in range(i + 1, len(ours)):
                    a, b = ours[i], ours[j]
                    if None in (a.get("x"), b.get("x")):
                        continue
                    d = math.hypot(a["x"] - b["x"], a["y"] - b["y"])
                    need = (a.get("radius") or 50) + (b.get("radius") or 50) + GAP
                    k = (a["key"], b["key"])
                    worst_gap[k] = min(worst_gap.get(k, (1e9, need))[0], d), need
        time.sleep(0.5)
    problems = []
    # A state file not written during the run is an old one (2026-11-21: a check after a failed relaunch read the last
    # course's file and passed).
    try:
        fresh = os.path.getmtime(os.path.join(ct_live.MOD, "ct-state.json")) > t0 + 1
    except OSError:
        fresh = False
    if not fresh:
        problems.append("ct-state.json was not written during the run (no course running?)")
    # As placed: on the floor, and apart by both sizes + 2 m.
    now_keys = {e["key"] for e in last or []}
    pl = [e for k, e in placed.items() if k in now_keys]  # this setup's only (the one before is removed as this comes)
    for e in pl:
        off = None if e.get("air") or e.get("floor") is None or e.get("half") is None else e["z"] - e["floor"] - e["half"]
        print("placed	%s	at %d,%d,%d	floor %s	half %s	radius %s	%s	off floor %s cm" % (
            e["key"], e["x"], e["y"], e["z"], e.get("floor"), e.get("half"), e.get("radius"), "air" if e.get("air") else "ground",
            "-" if off is None else round(off)))
        if off is not None and abs(off) > 30:
            problems.append("%s placed %d cm off the floor" % (e["key"], off))
    # Spaced: the setup's own (adds stay where their summoner put them, on the floor).
    own = [e for e in pl if e.get("member")]
    for i in range(len(own)):
        for j in range(i + 1, len(own)):
            a, b = own[i], own[j]
            d = math.hypot(a["x"] - b["x"], a["y"] - b["y"])
            need = (a.get("radius") or 50) + (b.get("radius") or 50) + GAP
            print("placed pair	%s	%s	%d cm	needs %d cm" % (a["key"], b["key"], d, need))
            if d < need - 30:
                problems.append("%s and %s placed %d cm apart (need %d)" % (a["key"], b["key"], d, need))
    if not pl:
        problems.append("nothing placed")
    # Over the run: judged while held, shown otherwise.
    for e in last or []:
        g = worst_ground.get(e["key"])
        print("over time	%s	off floor (worst) %s cm" % (e["key"], "-" if g is None else round(g)))
        if held and g is not None and g > 30:
            problems.append("%s %d cm off the floor while held" % (e["key"], g))
    for (a, b), (d, need) in worst_gap.items():
        print("over time pair	%s	%s	closest %d cm	needs %d cm" % (a, b, d, need))
        if held and d < need - 30:
            problems.append("%s and %s %d cm apart while held (need %d)" % (a, b, d, need))
    s = state()
    kinds = {}
    for e in s.get("enemies", []):
        if not e.get("stale") and not e.get("anchor"):
            kinds[e.get("model")] = kinds.get(e.get("model"), 0) + 1
    print("on the field\t" + ", ".join("%s x%d" % (k, n) for k, n in sorted(kinds.items())))
    print("setup\t%s\tmode %s\tcount %s\thits %s\tdamage %s\tspread %s\tgrounded %s\tno room %s\tfps %s" % (
        s.get("setup"), s.get("mode"), s.get("count"), s.get("hits"), s.get("damage"), s.get("spread"), s.get("grounded"),
        s.get("no_room"), s.get("fps")))
    if s.get("active") is not True:
        problems.append("the course is not running")
    if shot:
        p = op("capture_game_window").get("result", {}).get("image_path")
        print("shot\t%s\t%s" % (shot, p))
    print("ok" if not problems else "problems: " + "; ".join(problems))
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
