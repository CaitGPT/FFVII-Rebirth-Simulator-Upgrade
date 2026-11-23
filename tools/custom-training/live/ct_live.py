"""Live test helpers for Custom Training (development installs only: the mod's dev.txt enables ct-command.txt and
ct-state.json). Drives the game through the harness (the mod skill's scripts/mcp.py).

    python ct_live.py state                     print the mod's state
    python ct_live.py menu                      open the settings menu (as F7 would)
    python ct_live.py choose N                  pick option N (0-based) of the open window, as the mod's dev command
    python ct_live.py press N                   pick option N (0 or 1) with a real press through the harness
    python ct_live.py window                    read the open window through the harness
    python ct_live.py demo <behaviour-id> <objective> <expected> -- <steps...>
                                                wrap steps in a production test event
Steps for demo: "menu", "choose:N", "press:N", "wait:SECONDS", "until:<python expression on state s>".
"""
import json, os, sys, time

sys.path.insert(0, os.environ.get("REBIRTH_MCP_SCRIPTS", os.path.expanduser("~/.claude/skills/create-rebirth-mod/scripts")))
from mcp import op  # noqa: E402

# CT_MOD: the folder the mod writes to (Mods/SimulatorUpgrade for the integrated build).
MOD = os.environ.get("CT_MOD", r"D:/Epic Games/FinalFantasyVIIRebirth/End/Binaries/Win64/ue4ss/Mods/SimOverhaulCustomTraining")
REPO = "https://github.com/CaitGPT/FFVII-Rebirth-Simulator-Overhaul (private, branch ws/custom-training)"


def state():
    # The file is replaced by a rename every tick: a read can land in between, so an empty read is tried again
    # (a single failed read once made the sweep call a running course "ended", 2026-11-21).
    for _ in range(5):
        try:
            with open(os.path.join(MOD, "ct-state.json"), encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            time.sleep(0.1)
    return {}


def command(text):
    tmp = os.path.join(MOD, "ct-command.tmp")
    with open(tmp, "w", newline="\n") as f:
        f.write(text + "\n")
    os.replace(tmp, os.path.join(MOD, "ct-command.txt"))
    for _ in range(50):
        time.sleep(0.2)
        if not os.path.exists(os.path.join(MOD, "ct-command.txt")):
            return True
    return False


def window():
    return (op("read_message_window").get("result") or {})


def press(index):
    # The harness picks by the option's text; it reads only the first two buttons of a window.
    opts = window().get("options") or []
    option = opts[index]["text"] if index < len(opts) else index
    for _ in range(3):
        r = op("choose_message_window", option=option, execute=True)
        res = r.get("result") or {}
        if res.get("ok"):
            return res
        time.sleep(1.5)
    return r


def until(expr, seconds=30):
    deadline = time.time() + seconds
    while time.time() < deadline:
        s = state()
        try:
            if eval(expr, {}, {"s": s}):
                return s
        except Exception:
            pass
        time.sleep(1)
    raise SystemExit("timed out waiting for: " + expr + "\nstate: " + json.dumps(state())[:600])


def step(text):
    if text == "menu":
        command("menu"); time.sleep(1.5)
    elif text.startswith("key:"):
        command("key " + text.split(":", 1)[1]); time.sleep(0.6)
    elif text.startswith("choose:"):
        command("choose " + text.split(":", 1)[1]); time.sleep(1.5)
    elif text.startswith("press:"):
        print("press", json.dumps(press(int(text.split(":", 1)[1])))[:300]); time.sleep(1.5)
    elif text.startswith("wait:"):
        time.sleep(float(text.split(":", 1)[1]))
    elif text.startswith("fight:"):
        # A harness fight job: a production test needs one to end. The menu must be closed first.
        spec = text.split(":", 1)[1]
        guard = spec.endswith("g")
        args = {"seconds": int(spec.rstrip("g")), "execute": True, "category": "simulation", "heal_below": 0.45}
        if guard:
            args["guard_only"] = True
        job = op("combat_autopilot_async", **args)
        r = {}
        while job.get("job_id"):
            r = op("get_combat_autopilot_status", job_id=job["job_id"])
            if r.get("state") != "running":
                break
            time.sleep(0.8)
        res = (r.get("response") or {}).get("result") or r
        print("fight", json.dumps({k: res.get(k) for k in ("outcome", "seconds")}))
    elif text.startswith("until:"):
        until(text.split(":", 1)[1], 40)
    else:
        raise SystemExit("unknown step " + text)


def demo(behaviour, objective, expected, steps):
    context = {"feature": "Simulator Overhaul: Custom Training", "featureVersion": "custom-training-dev",
               "behaviorIdentity": behaviour, "testObjective": objective, "expectedBehavior": expected,
               "pullRequest": REPO, "expectUndefeated": True}
    for name, arguments in (("register_production_test_context", {"context": context}), ("begin_production_test", {})):
        r = op(name, **arguments)
        print(name, json.dumps(r.get("result") or r)[:300])
        if not (r.get("result") or {}).get("ok"):
            raise SystemExit(name + " refused")
    try:
        for s in steps:
            step(s)
    finally:
        ended = op("end_production_test")
        print("end_production_test", json.dumps(ended.get("result") or ended)[:600])
    print("state", json.dumps(state())[:800])


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "state":
        print(json.dumps(state(), indent=1))
    elif a[0] == "menu":
        print(command("menu"))
    elif a[0] == "choose":
        print(command("choose " + a[1]))
    elif a[0] == "press":
        print(json.dumps(press(int(a[1])))[:500])
    elif a[0] == "steps":
        for x in a[1:]:
            step(x)
    elif a[0] == "end":
        print(json.dumps(op("end_production_test").get("result"))[:600])
    elif a[0] == "window":
        print(json.dumps(window())[:800])
    elif a[0] == "demo":
        cut = a.index("--")
        demo(a[1], a[2], a[3], a[cut + 1:])
