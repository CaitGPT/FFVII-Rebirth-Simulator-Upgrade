"""The meters' rows in the integrated mod's settings menu (ws/ui), with real presses on one device: opens the menu (LB+RB
on the pad, F7 on the keyboard), sets Meter to each value and applies it, then Clear meter and Reset stagger. Uses ui's
walk.py to read the menu from ui's log; screenshots (full frames) land in docs/workstreams/meters/NAME.jpg, and each
step prints what meters-state.txt says afterwards.

Run in a Custom Training fight with the menu closed, the integrated development build installed, holding the game lock.

    python pad_route.py pad|keyboard [step ...]      steps: tanking healing hidden damage clear stagger cancel
"""
import os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "ui", "live"))
sys.path.insert(0, HERE)
import walk  # noqa: E402
import live  # noqa: E402

VALUES = {"damage": "Damage", "tanking": "Tanking", "healing": "Healing", "hidden": "Hidden"}


class Route(walk.Walk):
    def __init__(self, device, prefix):
        super().__init__(device)
        self.prefix = prefix

    def shot(self, name):
        self.n += 1
        return live.shot(f"{self.prefix}-{self.n:02d}-{name}", full=True)


def state():
    return " ".join(live.read(live.MOD + "/meters-state.txt").split())


def opened(w):
    screen, rows, _ = w.open()
    if screen != "main":
        raise SystemExit("the menu did not open: " + "\n".join(walk.ui_live.log(10)))
    return rows


def main():
    device = sys.argv[1]
    steps = sys.argv[2:] or ["tanking", "healing", "hidden", "damage", "clear", "stagger", "cancel"]
    w = Route(device, "40-" + device)
    print("before", state())
    for step in steps:
        rows = opened(w)
        print(step, "menu", rows, "cursor", w.cursor)
        w.shot(f"{step}-menu")
        if step in VALUES:
            w.go(w.row_of("Meter"))
            print("  values", w.rows, "cursor", w.cursor)
            w.shot(f"{step}-values")
            w.go(w.row_of(VALUES[step]))
            print("  main", w.rows)
            w.go(w.row_of("Apply"))
        elif step == "cancel":
            w.go(w.row_of("Cancel"))
        else:
            w.go(w.row_of({"clear": "Clear meter", "stagger": "Reset stagger"}[step]))
            print("  after", w.screen, w.rows)
            w.go(w.row_of("Cancel"))
        time.sleep(1.5)
        print("  state", state())
        print("  meters log", live.read(live.MOD + "/meters-log.txt").splitlines()[-2:])
        w.shot(f"{step}-after")


if __name__ == "__main__":
    main()
