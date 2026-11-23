"""Live test helpers for the meters panel (development install: dev.txt). Only while this workstream holds the game
lock (docs/COORDINATION.md). Drives the game through the harness (the mod skill's scripts/mcp.py).

    python live.py cmd next|prev|clear|stagger|toggle|show|hide|meter=heal|"sample large"|"sample off"
                                   an action, as Custom Training's menu sends it (meters-command.txt)
    python live.py ct "set behaviour=healing"   a Custom Training development command (ct-command.txt)
    python live.py shot NAME [full]             screenshot: the panel's corner (or the full frame) into
                                                docs/workstreams/meters/NAME.jpg
    python live.py json | log | state           meters.json, the last log lines, meters-state.txt and ct-course.txt
    python live.py key F9 [F5 ...]              press keys through the harness (press_key, in a fight: field=true)
    python live.py pad a [hold]                 press a pad button through the harness (press_pad), e.g. "pad lb rb"
                                                for LB+RB (hold RB, press LB)
    python live.py reserve                      Zack and Sephiroth to reserve status (course list open: the team list
                                                then offers them; the party workstream's finding), via the eval console
    python live.py mp                           Custom Training's MP refill counts beside the meters' MP spent
    python live.py begin ID "objective" "expected" [undefeated] / end    production test events
"""
import json, os, subprocess, sys, time

sys.path.insert(0, os.path.join(os.path.expanduser("~"), ".claude", "skills", "create-rebirth-mod", "scripts"))
from mcp import op  # noqa: E402

MODS = r"D:/Epic Games/FinalFantasyVIIRebirth/End/Binaries/Win64/ue4ss/Mods"
MOD = MODS + "/SimOverhaulMeters"
CT = MODS + "/SimOverhaulCustomTraining"
EVAL = MODS + "/SimulatorStages"
# The integrated mod: every part's files in its one folder. SimulatorUpgrade since the rename (2026-11-21),
# SimulatorOverhaul in a build from before it.
for _name in ("SimulatorUpgrade", "SimulatorOverhaul"):
    if os.path.isdir(MODS + "/" + _name):
        MOD = CT = EVAL = MODS + "/" + _name
        break
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.path.join(ROOT, "docs", "workstreams", "meters")
REPO = "local: FFVII-Rebirth-Simulator-Overhaul, branch ws/meters"


def put(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def wait_gone(path, seconds=8):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if not os.path.exists(path):
            return True
        time.sleep(0.2)
    return False


def cmd(action):
    put(MOD + "/meters-command.txt", action + "\n")
    return wait_gone(MOD + "/meters-command.txt")


def ct(text):
    put(CT + "/ct-command.txt", text + "\n")
    return wait_gone(CT + "/ct-command.txt")


def shot(name, full=False):
    os.makedirs(SHOTS, exist_ok=True)
    path = (op("capture_game_window").get("result") or {}).get("image_path")
    if not path:
        raise SystemExit("no capture")
    out = os.path.join(SHOTS, name + ".jpg")
    crop = [] if full else ["-vf", "crop=840:760:0:0"]
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, *crop, "-q:v", "3", out], check=True)
    return out


def eval_lua(code):
    """Run Lua through Simulator Stages' eval console (stages-eval.lua, development install; only with the game lock)."""
    out = EVAL + "/stages-eval.out"
    if os.path.exists(out):
        os.remove(out)
    put(EVAL + "/stages-eval.lua", code)
    for _ in range(40):
        time.sleep(0.25)
        if os.path.exists(out):
            return read(out)
    return "no answer"


def reserve():
    return eval_lua('local party = StaticFindObject("/Script/EndGame.Default__EndPartyAPI")\n'
                    'party:SetPlayerStatus(7, 5)\nparty:SetPlayerStatus(8, 5)\n'
                    'out(party:GetPlayerStatus(7), party:GetPlayerStatus(8))\nreturn "reserve"\n')


def mp():
    """Custom Training's MP refill counts (ct_api.mp_refilled(), integrated mod) beside the meters' MP spent."""
    ct_mp = eval_lua('local ok, ct = pcall(require, "ct_api")\nif not ok then return "no ct_api" end\n'
                     'local sum = 0\nfor k, v in pairs(ct.mp_refilled()) do out(k, v) sum = sum + v end\n'
                     'return "sum " .. sum\n')
    try:
        ours = (json.loads(read(MOD + "/meters.json")).get("meters") or {}).get("mp")
    except ValueError:
        ours = None
    return "ct_api.mp_refilled: " + " | ".join(ct_mp.strip().split("\n")) + "\nmeters mp: " + json.dumps(ours)


REASON = "meters workstream: testing the meters panel's own keys and Custom Training's LB+RB menu in a Custom Training fight"


def key(*names):
    out = []
    for name in names:
        r = op("press_key", key=name.lower(), field=True, reason=REASON)
        res = r.get("result") or r
        out.append((name, res.get("ok"), res.get("error") or res.get("reason")))
        time.sleep(0.8)
    return out


def pad(button, hold=None):
    args = {"button": button, "field": True, "reason": REASON}
    if hold:
        args["hold"] = hold
    r = op("press_pad", **args)
    res = r.get("result") or r
    return {k: res.get(k) for k in ("ok", "error", "reason", "changes")}


def begin(behaviour, objective, expected, undefeated=False):
    context = {"feature": "Simulator Upgrade: combined meters panel", "featureVersion": "meters-dev",
               "pullRequest": REPO, "behaviorIdentity": behaviour, "testObjective": objective,
               "expectedBehavior": expected}
    if undefeated:
        context["expectUndefeated"] = True
    for name, args in (("register_production_test_context", {"context": context}), ("begin_production_test", {})):
        r = op(name, **args)
        if not (r.get("result") or {}).get("ok"):
            raise SystemExit(f"{name} refused: {json.dumps(r)[:300]}")
    return "begun"


def end():
    r = op("end_production_test").get("result") or {}
    return {k: r.get(k) for k in ("eventId", "result", "intervalUncertain")}


PARTY_KEYS = {"Cloud": "0000", "Barret": "0001", "Tifa": "0002", "Aerith": "0003", "Red XIII": "0004",
              "Yuffie": "0005", "Cait Sith": "0006", "Zack": "0007", "Sephiroth": "0008"}


def menu():
    return op("read_combat_simulator_menu").get("result") or {}


def tap(button, wait=1.2):
    op("tap_combat_simulator_menu", button=button)
    time.sleep(wait)


def start(party, reserve_first=False):
    """From Chadley's Talk prompt: enter the simulator, open Custom Training (the row titled so), pick the party in
    order (the first leads), confirm and begin. reserve_first: Zack and Sephiroth to reserve before the course opens."""
    if menu().get("screen") not in ("selection", "challenge"):
        j = op("enter_combat_simulator_async", execute=True, skip_scenes=True)
        for _ in range(50):
            s = op("get_enter_combat_simulator_status", job_id=j.get("job_id"))
            if s.get("state") != "running":
                break
            time.sleep(4)
        r = (s.get("response") or {})
        print("enter", r.get("ok"), (r.get("result") or {}).get("state") or r.get("error"))
        time.sleep(2)
    for _ in range(40):
        labels = [l for c in menu().get("choices") or [] for l in c["labels"]]
        if "Custom Training" in labels:
            break
        tap("up", 0.9)
    else:
        raise SystemExit("Custom Training row not found")
    if reserve_first:
        print("reserve", reserve().strip())
    time.sleep(1.5)
    tap("confirm", 3)
    w = op("read_message_window").get("result") or {}
    if w.get("open"):   # Simulator Stages' stage picker: the plain simulator
        if w.get("selected") != 0:
            tap("up")
        tap("confirm", 3)
    op("close_tips", max_tips=3)
    for name in party:
        want = "$menu_partyname_%s_0000" % PARTY_KEYS[name]
        for _ in range(14):
            c = menu().get("choices") or []
            if c and (c[0].get("labels") or [None])[0] == want:
                break
            tap("down", 1.0)
        tap("confirm", 2.0)
    m = menu()
    if "Begin challenge?" not in (m.get("prompts") or []):
        for _ in range(12):
            c = [l for ch in menu().get("choices") or [] for l in ch["labels"]]
            if any("few_member" in l for l in c):
                tap("confirm", 2.0)
                break
            tap("down", 1.0)
    for _ in range(6):
        m = menu()
        if m.get("screen") == "confirmation" and m.get("focused_labels") == ["Yes"]:
            break
        tap("up")
    print("party", [p.get("name") for p in m.get("party") or []], m.get("prompts"))
    tap("confirm", 2)
    for _ in range(40):
        c = (op("observe_combat").get("result") or {}).get("combat") or {}
        if c.get("in_battle") and c.get("enemies"):
            return [(e.get("chara_id"), e.get("hp")) for e in c.get("enemies") or []]
        time.sleep(1.5)
    return "no fight"


def give_up():
    j = op("abandon_combat_simulator_fight_async", execute=True)
    s = j
    while j.get("job_id"):
        s = op("get_combat_simulator_fight_status", job_id=j["job_id"])
        if s.get("state") != "running":
            break
        time.sleep(2)
    return ((s.get("response") or {}).get("result") or {}).get("outcome")


def fight(seconds, **kw):
    kw.setdefault("heal_below", 0.45)
    job = op("combat_autopilot_async", seconds=seconds, execute=True, category="simulation", **kw)
    s = {}
    while job.get("job_id"):
        s = op("get_combat_autopilot_status", job_id=job["job_id"])
        if s.get("state") != "running":
            break
        time.sleep(0.8)
    return ((s.get("response") or {}).get("result") or s).get("outcome")


def to_chadley(launch=False):
    """Load save slot 25 (launching the game first if asked) and step to where only Chadley's Talk shows."""
    import math
    job = op("start_and_load_save_slot_async" if launch else "load_save_slot_async", slot=25, execute=True,
             **({"model_id": "claude-opus-5-5", "reasoning_effort": "high"} if launch else {}))
    status = "get_start_and_load_save_slot_status" if launch else "get_load_save_slot_status"
    while job.get("job_id"):
        s = op(status, job_id=job["job_id"])
        if s.get("state") != "running":
            break
        time.sleep(4)
    time.sleep(8)
    op("set_tips_autoclose", mode="always")
    chadley = None
    for a in (op("scan_nearby_actors", radius_m=15).get("result") or {}).get("actors", []):
        if "NP0067" in a.get("id", ""):
            chadley = a["position"]
    if not chadley:
        return "Chadley not found"
    for _ in range(14):
        r = op("observe_map_telemetry").get("result") or {}
        p = (r.get("player") or {}).get("position") or {}
        yaw = ((r.get("camera") or {}).get("rotation") or {}).get("yaw", 0)
        dx, dy = chadley["x"] - p["x"], chadley["y"] - p["y"]
        d = math.hypot(dx, dy)
        y = math.radians(yaw)
        f, rr = (math.cos(y), math.sin(y)), (-math.sin(y), math.cos(y))
        op("move_stick", x=round((dx * rr[0] + dy * rr[1]) / d, 2), y=round((dx * f[0] + dy * f[1]) / d, 2),
           milliseconds=int(min(400, max(120, (d - 120) * 2.2))))
        time.sleep(1.2)
        pr = op("read_field_prompt").get("result") or {}
        if pr.get("talk") and len(pr.get("commands") or []) == 1:
            return "talk"
    return "no clean Talk prompt"


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        raise SystemExit(__doc__)
    if a[0] == "cmd":
        print(cmd(" ".join(a[1:])))
    elif a[0] == "ct":
        print(ct(" ".join(a[1:])))
    elif a[0] == "shot":
        print(shot(a[1], len(a) > 2 and a[2] == "full"))
    elif a[0] == "json":
        print(read(MOD + "/meters.json"))
    elif a[0] == "log":
        print("\n".join(read(MOD + "/meters-log.txt").splitlines()[-15:]))
    elif a[0] == "state":
        print(read(MOD + "/meters-state.txt")); print(read(CT + "/ct-course.txt"))
    elif a[0] == "key":
        print(key(*a[1:]))
    elif a[0] == "pad":
        print(pad(a[1], a[2] if len(a) > 2 else None))
    elif a[0] == "start":
        names = [n.replace("_", " ") for n in a[1:] if n != "reserve"]
        print(start(names or ["Cloud"], "reserve" in a[1:]))
    elif a[0] == "chadley":
        print(to_chadley(len(a) > 1 and a[1] == "launch"))
    elif a[0] == "giveup":
        print(give_up())
    elif a[0] == "fight":
        print(fight(int(a[1])))
    elif a[0] == "reserve":
        print(reserve())
    elif a[0] == "mp":
        print(mp())
    elif a[0] == "begin":
        print(begin(a[1], a[2], a[3], len(a) > 4 and a[4] == "undefeated"))
    elif a[0] == "end":
        print(end())
    else:
        raise SystemExit(__doc__)
