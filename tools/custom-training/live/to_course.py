"""to_course.py [launch [noenter]] [list]: (launch the game and) load save slot 25 at Costa del Sol, enter the
simulator through Chadley's talk (the harness's enter_combat_simulator_async), and start Custom Training (the last
row) solo as Cloud; with "list", stop at the course list.

Since main 6bb514e (owner, 2026-11-21) the machine is no longer part of Simulator Upgrade: Chadley and the machine stay
where the game puts them and the simulator opens only through Chadley's talk. The old walk to a spot where only his
Talk showed, and the relabel of the machine's prompt, are gone with it.

Always loads slot 25 explicitly: "Continue" loads the newest save, which can be another session's (2026-11-21: one with
Aerith in the party, whom the opponents then chased instead of Cloud)."""
import os
import sys
import time

sys.path.insert(0, os.environ.get("REBIRTH_MCP_SCRIPTS", os.path.expanduser("~/.claude/skills/create-rebirth-mod/scripts")))
from mcp import op  # noqa: E402


def wait(start_op, status_op, **kw):
    j = op(start_op, **kw)["job_id"]
    while True:
        s = op(status_op, job_id=j)
        if s.get("state") != "running":
            return s
        time.sleep(4)


def menu():
    return op("read_combat_simulator_menu").get("result") or {}


def tap(b, w=1.2):
    op("tap_combat_simulator_menu", button=b)
    time.sleep(w)


def enter(tries=3):
    """Talk to Chadley and open the course list. The harness often reports chadley_menu_not_opened while the list
    did open, so the list itself is the test."""
    for k in range(tries):
        s = wait("enter_combat_simulator_async", "get_enter_combat_simulator_status", execute=True, skip_scenes=True)
        r = s.get("response") or {}
        time.sleep(2)
        if menu().get("choices"):
            print("enter ok", k + 1)
            return True
        print("enter", k + 1, r.get("ok"), r.get("error"))
        time.sleep(3)
    return False


def start_custom_training():
    labels = []
    for _ in range(30):  # the last row is Custom Training
        labels = [l for c in menu().get("choices") or [] for l in c["labels"]]
        if "Custom Training" in labels:
            break
        tap("up", 0.9)
    print("course", labels)
    tap("confirm", 2.0)
    op("close_tips", max_tips=3)
    # The Stages part's picker comes between the course and the party (main faf27f5: Custom Training is offered every
    # stage): confirm keeps the stored stage. Until the party screen shows.
    for _ in range(10):
        if menu().get("screen") in ("party", "selection"):
            break
        tap("confirm", 1.5)
    for _ in range(16):
        if (menu().get("choices") or [{}])[0].get("labels") == ["$menu_partyname_0000_0000"]:
            break
        tap("up", 0.9)
    tap("confirm")
    for _ in range(14):
        m = menu()
        ch = [l for c in m.get("choices") or [] for l in c["labels"]]
        if m.get("screen") == "confirmation":
            if m.get("focused_labels") == ["Yes"]:
                tap("confirm", 2)
                break
            tap("up")
            continue
        if any("few_member" in l for l in ch):
            tap("confirm")
            continue
        tap("down", 0.9)
    c = {}
    for _ in range(40):
        c = (op("observe_combat").get("result") or {}).get("combat") or {}
        if c.get("in_battle") and c.get("enemies"):
            break
        time.sleep(1.5)
    print("enemies", [(e.get("chara_id"), e.get("hp"), e.get("max_hp")) for e in c.get("enemies") or []])
    return bool(c.get("in_battle"))


def main(argv):
    if "launch" in argv:
        s = wait("start_and_load_save_slot_async", "get_start_and_load_save_slot_status", slot=25, execute=True,
                 model_id="claude-opus-5-5", reasoning_effort="high")
        print("launch", (s.get("response") or {}).get("ok"))
        op("set_tips_autoclose", mode="always")
        if "noenter" in argv:
            return 0
    else:
        wait("load_save_slot_async", "get_load_save_slot_status", slot=25, execute=True)
    time.sleep(3)
    if not enter():
        print("could not open the course list")
        return 1
    if "list" in argv:
        return 0
    return 0 if start_custom_training() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
