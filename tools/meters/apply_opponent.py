"""Apply another opponent mid-fight through the integrated settings menu (pad), and watch the meters around it: the
opponent Custom Training removes must not count as damage (seen 2026-11-21 before the fix: a Titan removed on Apply
counted 84,186 unattributed).

    python apply_opponent.py rows [K [R]]          open the menu, go to Opponent, print the rows there, back out
    python apply_opponent.py pick K [R] N          Opponent -> kind row K -> (range row R) -> name row N -> Apply; then
                                                   prints meters.json's damage total every 0.5 s for 12 s
Rows are 1-based, as printed. Screenshots in docs/workstreams/meters/41-apply-*.jpg.
"""
import json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "ui", "live"))
sys.path.insert(0, HERE)
import live  # noqa: E402
from pad_route import Route  # noqa: E402


BM = live.MODS + "/BattleMeters/meters.json"


def damage(path):
    try:
        d = (json.loads(live.read(path)).get("meters") or {}).get("damage") or {}
    except ValueError:
        return None
    return round(d.get("total") or 0), {k: round(v) for k, v in (d.get("by_source") or {}).items()}


def totals():
    """Ours, then Battle Meters' own (1.1.0 doesn't stand aside, so it counts the same fight)."""
    return damage(live.MOD + "/meters.json"), "BM", damage(BM)


def main():
    w = Route("pad", "41-apply")
    screen, rows, _ = w.open()
    if screen != "main":
        raise SystemExit("menu did not open")
    w.go(w.row_of("Opponent"))
    print(w.screen, w.rows)
    if sys.argv[1] == "rows":     # rows [K [R]]: also the rows under those picks, then back out
        for n in [int(x) for x in sys.argv[2:]]:
            w.go(n)
            print(w.screen, w.rows)
        while w.screen != "main":
            w.go(len(w.rows))      # Back
        w.go(w.row_of("Cancel"))
        return
    picks = [int(x) for x in sys.argv[2:]]
    w.shot("kinds")
    for n in picks:
        w.go(n)
        print(w.screen, w.rows)
        w.shot(w.screen)
    before = totals()
    print("before Apply", before, live.read(live.MOD + "/meters-log.txt").splitlines()[-1])
    w.go(w.row_of("Apply"))
    t0 = time.time()
    while time.time() - t0 < 12:
        print(f"{time.time() - t0:5.1f}s", totals())
        time.sleep(0.5)
    w.shot("after")
    print("\n".join(live.read(live.MOD + "/meters-log.txt").splitlines()[-4:]))


if __name__ == "__main__":
    main()
