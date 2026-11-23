"""wave_check.py SET [--clears N] [--respawn key|pad|bridge,...] [--shot NAME]: Aggressive's real conditions, in the game
(owner 2026-11-21): SET is a dev-bridge setting ("group=a,b,c", "round=ID", "opponent=ID count=N"), applied with
behaviour=aggressive. Then N times (default 2):
  1. wait until the setup's own are there (their wave number in state());
  2. bring them to 1% HP (dev "hp 1") and let the harness's autopilot finish them;
  3. wait for the clear: state().cleared true, the round still running and in battle (the anchor), nothing respawned
     by itself; a screenshot; the party's HP and MP from the harness, before and after (nothing refilled);
  4. respawn by the next way in --respawn (key: F4 through press_key; pad: LB+RB opens ui's menu, A on its first row,
     Respawn; bridge: ct-command "respawn"), and see the next wave come.
Prints one line per step; "ok" or the problems. Needs the game lock and a running Custom Training course.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ct_live  # noqa: E402
from ct_live import op, state, command  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SHOTS = os.path.join(REPO, "docs", "workstreams", "custom-training")
FIRST = 0
FIELD = {"field": True, "reason": "Custom Training respawn test in a simulator fight"}


def shot(name):
    p = (op("capture_game_window").get("result") or {}).get("image_path")
    if not p:
        return ""
    out = os.path.join(SHOTS, name + ".jpg")
    subprocess.run(["powershell", "-NoProfile", "-Command",
                    "Add-Type -AssemblyName System.Drawing; $i=[System.Drawing.Image]::FromFile('%s'); "
                    "$b=New-Object System.Drawing.Bitmap $i,1280,720; $b.Save('%s',[System.Drawing.Imaging.ImageFormat]::Jpeg)" % (p, out)],
                   check=False)
    return os.path.basename(out)


def party():
    c = (op("observe_combat").get("result") or {}).get("combat") or {}
    return {p.get("chara_id"): (p.get("hp"), p.get("max_hp"), p.get("mp"), p.get("max_mp"),
                                "reraise" if "BSC_Reraise" in (p.get("status_effects") or []) else "-")
            for p in c.get("party") or []}, c.get("in_battle")


def own(s):
    return [e for e in s.get("enemies", []) if e.get("member") and not e.get("stale") and not e.get("anchor")
            and (e.get("hp") or 0) > 0]


def wait(cond, seconds, step=0.5):
    t0 = time.time()
    while time.time() - t0 < seconds:
        s = state()
        if cond(s):
            return s
        time.sleep(step)
    return None


def respawn(way):
    if way == "key":
        return op("press_key", key="F4", milliseconds=150, **FIELD)
    if way == "pad":
        op("press_pad", button="rb", hold="lb", lead_ms=50, milliseconds=200, tail_ms=50, **FIELD)
        time.sleep(3.5)  # ui's menu takes input a moment after it shows (an A at 1.5 s was not taken)
        return op("press_pad", button="a", milliseconds=150, **FIELD)
    command("respawn")
    return {"ok": True}


def main(argv):
    global FIRST
    clears, ways, name = 2, ["key", "pad"], None
    if "--fight-first" in argv:
        i = argv.index("--fight-first"); FIRST = int(argv[i + 1]); argv = argv[:i] + argv[i + 2:]
    if "--clears" in argv:
        i = argv.index("--clears"); clears = int(argv[i + 1]); argv = argv[:i] + argv[i + 2:]
    if "--respawn" in argv:
        i = argv.index("--respawn"); ways = argv[i + 1].split(","); argv = argv[:i] + argv[i + 2:]
    if "--shot" in argv:
        i = argv.index("--shot"); name = argv[i + 1]; argv = argv[:i] + argv[i + 2:]
    setting = argv[0]
    problems = []
    command("set %s behaviour=aggressive difficulty=normal" % setting)
    for n in range(1, clears + 1):
        s = wait(lambda s: s.get("active") and own(s) and not s.get("cleared"), 40)
        if not s:
            problems.append("wave %d: the set did not come" % n)
            break
        wave = s.get("wave")
        print("wave %s here: %s" % (wave, ", ".join(sorted({str(e.get("model")) for e in own(s)}))), flush=True)
        before, _ = party()
        # A natural fight first, so a round's reinforcements and adds come (FIGHT_FIRST s; 0 skips it).
        adds_seen = set()
        if FIRST > 0:
            job = op("combat_autopilot_async", seconds=FIRST, execute=True, category="simulation").get("job_id")
            t1 = time.time()
            while time.time() - t1 < FIRST + 2:
                x = state()
                adds_seen |= {str(e.get("model")) for e in x.get("enemies", []) if not e.get("member") and not e.get("anchor")
                              and not e.get("stale") and (e.get("hp") or 0) > 0}
                time.sleep(1)
            while job and op("get_combat_autopilot_status", job_id=job).get("state") == "running":
                time.sleep(1)
            print("after %d s of fighting, adds seen: %s" % (FIRST, ", ".join(sorted(adds_seen)) or "none"), flush=True)
        # Fights of 25 s until cleared (a round's reinforcements and adds come during it), each after "hp 1" for the
        # setup's own. The harness refuses input and readings while its autopilot runs (async_combat_in_progress) and
        # has no way to stop it: each job is waited out.
        s, t0 = None, time.time()
        while time.time() - t0 < 150:
            command("hp 1")
            job = op("combat_autopilot_async", seconds=25, execute=True, category="simulation").get("job_id")
            s = wait(lambda s: s.get("cleared"), 27, 1)
            while job and op("get_combat_autopilot_status", job_id=job).get("state") == "running":
                time.sleep(1)
            if s:
                break
        if not s:
            problems.append("wave %s: not cleared in 150 s" % wave)
            break
        time.sleep(3)
        s = state()
        after, in_battle = party()
        print("cleared: wave %s in %.1f s; waiting %s; running %s; in battle %s; own left %d" % (
            s.get("wave"), s.get("cleared_in_s") or -1, s.get("cleared"), s.get("active"), in_battle, len(own(s))), flush=True)
        print("party before %s after %s; mp_refilled %s" % (before, after, s.get("mp_refilled")), flush=True)
        if not (s.get("active") and in_battle):
            problems.append("wave %s: the round did not wait in battle" % s.get("wave"))
        if own(s):
            problems.append("wave %s: something respawned by itself" % s.get("wave"))
        for k, (hp, mx, mp, mmp, rr) in after.items():
            b = before.get(k)
            if b and hp is not None and b[0] is not None and hp > b[0] and rr != "reraise":
                problems.append("%s HP rose without Auto-Life" % k)
        if name:
            print("shot", shot("%s-clear%d" % (name, n)), flush=True)
        way = ways[(n - 1) % len(ways)]
        r = respawn(way)
        s2 = wait(lambda x: (x.get("wave") or 0) > (s.get("wave") or 0) and own(x), 40)
        print("respawn by %s: %s; wave now %s" % (way, "ok" if s2 else "no new wave", s2 and s2.get("wave")), flush=True)
        if not s2:
            problems.append("respawn by %s brought no new wave (%s)" % (way, str(r)[:120]))
            break
    print("ok" if not problems else "problems: " + "; ".join(problems), flush=True)
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
