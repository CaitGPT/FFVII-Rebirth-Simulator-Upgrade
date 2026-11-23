"""change_check.py FROM TO [--fight S] [--shot NAME]: a change mid-fight (owner 2026-11-21: an old opponent must get no
attacks in after it is replaced, and nothing it fired may stay). FROM fights the party (the harness's autopilot) for S
seconds (default 30), then TO is chosen while the fight goes on. Reports, from the state file and the log:
  - how long the old enemies took to go (log "gone ... s after it was replaced");
  - what is left of their own damage sources (state damage_sources_left) at 1, 3 and 8 s;
  - whether any of them was still in the fight (not marked as replaced) after the change;
  - the moves of the old opponent the harness logged after the change (its combat log from the change on).
Screenshots before and 3 s after the change. Needs the game lock, a running course and harness PR 791 (input and
captures during a fight, cancel_combat_autopilot).
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ct_live  # noqa: E402
from ct_live import op, state, command  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SHOTS = os.path.join(REPO, "docs", "workstreams", "custom-training")


def shot(name):
    p = (op("capture_game_window").get("result") or {}).get("image_path")
    if not p or not name:
        return ""
    out = os.path.join(SHOTS, name + ".jpg")
    subprocess.run(["powershell", "-NoProfile", "-Command",
                    "Add-Type -AssemblyName System.Drawing; $i=[System.Drawing.Image]::FromFile('%s'); "
                    "$b=New-Object System.Drawing.Bitmap $i,1280,720; $b.Save('%s',[System.Drawing.Imaging.ImageFormat]::Jpeg)" % (p, out)],
                   check=False)
    return os.path.basename(out)


def log_since(mark):
    with open(os.path.join(ct_live.MOD, "ct-log.txt"), encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    return [l for l in lines if l[:20] >= mark]


def main(argv):
    fight, name = 30, None
    if "--fight" in argv:
        i = argv.index("--fight"); fight = int(argv[i + 1]); argv = argv[:i] + argv[i + 2:]
    if "--shot" in argv:
        i = argv.index("--shot"); name = argv[i + 1]; argv = argv[:i] + argv[i + 2:]
    src, dst = argv[0], argv[1]
    command("set opponent=%s count=1 behaviour=aggressive difficulty=normal" % src)
    for _ in range(40):
        s = state()
        if s.get("opponent") == src and any(e.get("member") for e in s.get("enemies", [])):
            break
        time.sleep(1)
    job = op("combat_autopilot_async", seconds=fight + 30, execute=True, category="simulation").get("job_id")
    time.sleep(fight)
    before = state()
    old = {e["key"] for e in before.get("enemies", []) if not e.get("anchor")}
    print("before: %d enemies of ours, damage sources shown %s" % (len(old), before.get("damage_sources")), flush=True)
    print("shot", shot(name and name + "-before"), flush=True)
    mark = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime())
    command("set opponent=%s count=1 behaviour=aggressive" % dst)
    t0 = time.time()
    problems = []
    for t in (1, 3, 8):
        time.sleep(max(0, t - (time.time() - t0)))
        s = state()
        active_old = [e["key"] for e in s.get("enemies", []) if e["key"] in old and not e.get("stale") and not e.get("anchor")]
        print("+%ds: old ones still in the fight %d; left of the damage sources shown at the change %s of %s" % (
            t, len(active_old), s.get("damage_sources_left"), s.get("damage_sources_at_change")), flush=True)
        if t >= 1 and active_old:
            problems.append("%d old one(s) not out of the fight %d s after the change" % (len(active_old), t))
        if t == 3:
            print("shot", shot(name and name + "-after"), flush=True)
        if t >= 3 and (s.get("damage_sources_left") or 0) > 0:
            problems.append("%s of their damage sources left at %d s" % (s.get("damage_sources_left"), t))
    if job:
        op("cancel_combat_autopilot", job_id=job)
        while op("get_combat_autopilot_status", job_id=job).get("state") == "running":
            time.sleep(1)
    for l in log_since(mark):
        if "\tgone\t" in l or "\tremove\t" in l or "\tretire\t" in l:
            print("log", l, flush=True)
    print("ok" if not problems else "problems: " + "; ".join(problems), flush=True)
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
