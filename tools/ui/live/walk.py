"""Walks the settings menu with real presses, on one device, through every row: opens it with F7 (keyboard) or LB+RB
(pad), opens each setting's value list and picks another value, goes through the opponent list (kinds, a range, a
name), then Apply; opens it again and leaves with Cancel. Screenshots of every window land in
docs/workstreams/ui/walk-<device>/.

The cursor is moved with the window's own keys (Up/Down and Enter on the keyboard, D-pad and A on the pad) through the
harness's press_key / press_pad (runtime with PR 787). Where the cursor starts in each window is read from the mod's
own log (the row it put the cursor on, or row 1 when it could not).

Run in a Custom Training fight with the menu closed and the ui development install.

    python walk.py keyboard|pad [--no-apply]
"""
import os, re, sys, time

sys.path.insert(0, os.path.dirname(__file__))
import ui_live  # noqa: E402

REASON = "open the Simulator Upgrade settings menu in a Custom Training fight (ui workstream test)"
KEYS = {"keyboard": {"up": "Up", "down": "Down", "confirm": "Enter"},
        "pad": {"up": "dpad_up", "down": "dpad_down", "confirm": "a"}}


class Walk:
    def __init__(self, device):
        self.device, self.keys = device, KEYS[device]
        self.n = 0

    def press(self, what, **kw):
        name = self.keys.get(what, what)
        for _ in range(6):  # the harness refuses while its previous press is still finishing
            if self.device == "keyboard":
                r = ui_live.op("press_key", key=name, **kw)
            else:
                r = ui_live.op("press_pad", button=name, **kw)
            res = r.get("result") or r
            if "another input action" not in str(res.get("refusal") or r.get("error") or ""):
                break
            time.sleep(0.5)
        if not res.get("ok", r.get("ok")):
            print("press refused", what, str(res)[:400])
            raise SystemExit(1)
        time.sleep(0.35)
        return res

    def open(self):
        if self.device == "keyboard":
            self.press("F7", field=True, reason=REASON)
        else:
            self.press("lb", hold="rb", field=True, reason=REASON, lead_ms=300, milliseconds=200)
        return self.settle()

    def settle(self):
        """Waits for the next window, and returns (screen, rows, cursor row) from the mod's log."""
        time.sleep(1.6)
        lines = ui_live.log(40)
        win = None
        for i, line in enumerate(lines):
            if "\twindow\t" in line:
                win = i
        if win is None:
            return None, [], 1
        parts = lines[win].split("\t")
        screen, rows = parts[2], parts[5].split(" | ") if len(parts) > 5 else []
        want = int(re.search(r"focus (\d+)", lines[win]).group(1)) if re.search(r"focus (\d+)", lines[win]) else 1
        cursor = 1
        for line in lines[win + 1:]:
            m = re.search(r"focus\trow (\d+) after", line)
            if m:
                cursor = int(m.group(1))
        if want > 1 and cursor == 1 and any("\tfocus\ttry " in line for line in lines[win + 1:]):
            time.sleep(1.2)  # the mod is still trying (only with ui place_cursor on)
            fresh = ui_live.log(40)
            last = max((i for i, line in enumerate(fresh) if "\twindow\t" in line), default=-1)
            for line in fresh[last + 1:]:
                m = re.search(r"focus\trow (\d+) after", line)
                if m:
                    cursor = int(m.group(1))
        self.screen, self.rows, self.cursor = screen, rows, cursor
        return screen, rows, cursor

    def shot(self, name):
        self.n += 1
        return ui_live.shot(f"walk-{self.device}/{self.n:02d}-{name}")

    def go(self, row):
        """Moves the cursor to row (1-based) and confirms it."""
        steps = row - self.cursor
        for _ in range(abs(steps)):
            self.press("down" if steps > 0 else "up")
        self.press("confirm")
        return self.settle()

    def row_of(self, label):
        for i, r in enumerate(self.rows):
            if r == label or r.startswith(label + ":"):
                return i + 1
        raise SystemExit(f"no row {label!r} in {self.rows}")


def main():
    device = sys.argv[1]
    w = Walk(device)
    screen, rows, _ = w.open()
    print("opened", screen, rows)
    if screen != "main":
        raise SystemExit("the menu did not open: " + "\n".join(ui_live.log(10)))
    w.shot("main")
    # Every setting with a value list: open it, pick the next value, back on the main window.
    for label in ("Number", "Behaviour", "Difficulty", "Meter"):  # Mode comes last: it changes the rows
        if not any(r.startswith(label + ":") for r in w.rows):
            continue
        current = w.rows[w.row_of(label) - 1].split(":", 1)[1].strip()
        w.go(w.row_of(label))
        if w.screen != "values":  # an opponent Custom Training caps at one copy: Number opens no list
            continue
        w.shot(f"values-{label.lower()}")
        target = next(i + 1 for i, r in enumerate(w.rows[:-1]) if r != current)  # another value than the current one
        w.go(target)
        w.shot(f"main-after-{label.lower()}")
    # The opponent list: kinds, the third kind (Beasts: ranges), its second range, a name other than the current one.
    grouped = any(r.startswith("Opponent 1:") for r in w.rows)
    first = "Opponent 1" if grouped else "Opponent"
    current = w.rows[w.row_of(first) - 1].split(":", 1)[1].strip()
    w.go(w.row_of(first))
    w.shot("kinds")
    w.go(min(3, len(w.rows) - 1))
    w.shot(w.screen)
    if w.screen == "ranges":
        w.go(min(2, len(w.rows) - 1))
        w.shot("names")
    w.go(next(i + 1 for i, r in enumerate(w.rows[:-1]) if r != current and i > 0))
    w.shot("main-after-opponent")
    if grouped:
        # Opponent 2: the kinds with None; None (the row before Back), then Opponent 2 again, the first kind's first name.
        w.go(w.row_of("Opponent 2"))
        w.shot("kinds-opponent2")
        w.go(len(w.rows) - 1)
        w.shot("main-after-none")
        w.go(w.row_of("Opponent 2"))
        w.go(1)
        if w.screen == "ranges":
            w.go(1)
        w.go(1)
        w.shot("main-after-opponent2")
    if any(r.startswith("Mode:") for r in w.rows):
        # Round mode: Mode -> Round, then Round -> the first tab -> its first course (range) -> the last round.
        w.go(w.row_of("Mode"))
        w.shot("values-mode")
        w.go(2)
        w.shot("main-round-mode")
        w.go(w.row_of("Round"))
        w.shot("round-tabs")
        w.go(1)
        w.shot("round-" + w.screen)
        if w.screen == "course_ranges":
            w.go(1)
            w.shot("round-courses")
        w.go(1)
        if w.screen == "round_ranges":
            w.shot("round-round-ranges")
            w.go(len(w.rows) - 1)
        w.shot("round-rounds")
        w.go(len(w.rows) - 1)
        w.shot("main-after-round")
    if "--no-apply" in sys.argv:
        w.go(w.row_of("Cancel"))
    else:
        w.go(w.row_of("Apply"))
    time.sleep(1.0)
    print("\n".join(ui_live.log(6)))
    # Again, and out with Cancel.
    time.sleep(2.0)
    screen, rows, _ = w.open()
    w.shot("reopened")
    w.go(w.row_of("Cancel"))
    print("\n".join(ui_live.log(4)))


if __name__ == "__main__":
    main()
