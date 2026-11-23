"""The settings panel from the keyboard alone, then from the pad alone (owner 2026-11-21: every menu works fully from
both). Course running, development install; the harness's press_key / press_pad (harness ca0433c or later).

usage: input_test.py [keyboard|pad|both]
Each device: open the panel, move to every section, change behaviour, difficulty, number and opponent (also by kind),
apply, check the course took every change; open again and close without changes (Back), and close with the open key.
"""
import os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from ct_live import op, state, command  # noqa: E402
import panel_shots  # noqa: E402

FIELD = {"field": True, "reason": "open the Custom Training settings panel in a simulator fight"}
KEYS = {
    "keyboard": {"up": "up", "down": "down", "left": "left", "right": "right", "select": "enter", "back": "esc",
                 "prev_kind": "q", "next_kind": "e"},
    "pad": {"up": "dpad_up", "down": "dpad_down", "left": "dpad_left", "right": "dpad_right", "select": "a",
            "back": "b", "prev_kind": "x", "next_kind": "y"},
}


def press(device, key, field=False):
    if device == "keyboard":
        args = {"key": KEYS[device].get(key, key), "milliseconds": 150}
    else:
        args = {"button": KEYS[device].get(key, key), "milliseconds": 150}
    if field:
        args.update(FIELD)
    r = op("press_key" if device == "keyboard" else "press_pad", **args)
    time.sleep(0.35)
    return r


def open_panel(device):
    if device == "keyboard":
        press(device, "f7", field=True)
    else:
        op("press_pad", button="rb", hold="lb", lead_ms=50, milliseconds=200, tail_ms=50, **FIELD)
    for _ in range(20):
        if state().get("menu_open"):
            time.sleep(0.6)  # the panel takes keys once every key has been seen up
            return True
        time.sleep(0.3)
    return False


def wait_closed():
    for _ in range(20):
        if not state().get("menu_open"):
            return True
        time.sleep(0.3)
    return False


def run(device, results):
    def check(name, ok, detail=""):
        results.append((device, name, "ok" if ok else "FAILED", detail))
        print(device, name, "ok" if ok else "FAILED", detail, flush=True)

    command("set count=1 behaviour=passive difficulty=normal")
    time.sleep(2)
    before = state()
    check("opens", open_panel(device), "F7" if device == "keyboard" else "LB+RB")
    panel_shots.shot(os.path.join(panel_shots.OUTDIR, "panel-%s-2026-11-21.png" % device))
    press(device, "right")                                   # enemy: the next one
    press(device, "next_kind"); press(device, "prev_kind")   # by kind, and back to the start of that kind
    press(device, "down"); press(device, "right")            # behaviour: passive -> aggressive
    press(device, "down"); press(device, "right")            # difficulty: normal -> dynamic (or the next allowed)
    press(device, "down"); press(device, "right")            # number: 1 -> 2
    press(device, "select")
    check("applies and closes", wait_closed())
    time.sleep(3)
    after = state()
    check("behaviour changed", after.get("behaviour") == "aggressive", after.get("behaviour"))
    check("difficulty changed", after.get("difficulty") != before.get("difficulty"), after.get("difficulty"))
    boss = "(boss)" in str(after.get("name"))
    check("number changed", after.get("count") == 2 or after.get("count") == 1 and boss, str(after.get("count")))
    check("opponent changed", after.get("opponent") != before.get("opponent"), str(after.get("opponent")))
    # Back closes without changes
    check("opens again", open_panel(device))
    press(device, "down"); press(device, "left")
    press(device, "back")
    check("back closes", wait_closed())
    time.sleep(1)
    check("back changed nothing", state().get("behaviour") == "aggressive", state().get("behaviour"))
    # the open key closes it too (keyboard: F7; pad: B is the way, tested above)
    if device == "keyboard":
        check("opens a third time", open_panel(device))
        press(device, "f7")
        check("F7 closes", wait_closed())
    up = op("observe_game").get("result") or {}
    check("game not paused after", not up.get("paused"), str(up.get("paused")))


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "both"
    results = []
    for device in (["keyboard", "pad"] if which == "both" else [which]):
        run(device, results)
    failed = [r for r in results if r[2] != "ok"]
    print("%d checks, %d failed" % (len(results), len(failed)))


if __name__ == "__main__":
    main()
