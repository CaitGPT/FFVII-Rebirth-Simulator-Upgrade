"""last_checks.py [autolife] [notice] [reinforcements]: the parent's last open items (2026-11-22), in the game, Aggressive,
Cloud solo, harness PR 791 (captures and input during a fight).
  autolife:       the Tonberry King; Cloud guards (probe); the party's HP is read twice a second until a knockout and
                  a raise (Auto-Life), with screenshots at both; up to 150 s.
  notice:         a Bomb at 1 HP is finished by the autopilot; the moment state() says cleared, a screenshot (the clear
                  notice in the game's message log).
  reinforcements: Gongaga Region Intel: Level 1, round 3 (three Grangalan, whose split brings the child and grandchild
                  waves), fought out by the autopilot with no shortcut; the adds seen; Respawn by F4; fought again and
                  the adds seen again.
Prints what it saw; screenshots in docs/workstreams/custom-training/last/.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ct_live  # noqa: E402
from ct_live import op, state, command  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SHOTS = os.path.join(REPO, "docs", "workstreams", "custom-training", "last")
FIELD = {"field": True, "reason": "Custom Training last checks"}


def shot(name):
    p = (op("capture_game_window").get("result") or {}).get("image_path")
    if not p:
        return ""
    os.makedirs(SHOTS, exist_ok=True)
    out = os.path.join(SHOTS, name + ".jpg")
    subprocess.run(["powershell", "-NoProfile", "-Command",
                    "Add-Type -AssemblyName System.Drawing; $i=[System.Drawing.Image]::FromFile('%s'); "
                    "$b=New-Object System.Drawing.Bitmap $i,1280,720; $b.Save('%s',[System.Drawing.Imaging.ImageFormat]::Jpeg)" % (p, out)],
                   check=False)
    return os.path.basename(out)


def cloud():
    c = (op("observe_combat").get("result") or {}).get("combat") or {}
    for p in c.get("party") or []:
        return p.get("hp"), p.get("max_hp"), p.get("status_effects") or []
    return None, None, []


def wait_member(template, seconds=40):
    for _ in range(seconds):
        s = state()
        if s.get("opponent") == template or s.get("mode") == "round":
            if any(e.get("member") and (e.get("hp") or 0) > 0 for e in s.get("enemies", [])):
                return True
        time.sleep(1)
    return False


def cancel(job):
    if job:
        op("cancel_combat_autopilot", job_id=job)
        while op("get_combat_autopilot_status", job_id=job).get("state") == "running":
            time.sleep(1)


def autolife():
    command("set opponent=mobcolvr_EN2017_02_Tonberry_KingEnd2_00 count=1 behaviour=aggressive difficulty=normal")
    wait_member("mobcolvr_EN2017_02_Tonberry_KingEnd2_00")
    job = op("combat_autopilot_async", seconds=150, execute=True, probe="guard", category="simulation").get("job_id")
    t0, down, raised = time.time(), None, None
    last = None
    while time.time() - t0 < 150:
        hp, mx, st = cloud()
        if hp is not None and hp != last:
            print("%5.1fs Cloud %s/%s %s" % (time.time() - t0, hp, mx, " ".join(st)), flush=True)
            last = hp
        if hp == 0 and down is None:
            down = time.time() - t0
            print("knocked out; shot", shot("autolife-knocked-out"), flush=True)
        if down is not None and hp and hp > 0:
            raised = time.time() - t0
            print("raised at %.1fs, %s HP; shot %s" % (raised, hp, shot("autolife-raised")), flush=True)
            break
        time.sleep(0.5)
    cancel(job)
    s = state()
    print("autolife: knocked out %s, raised %s; course running %s" % (down, raised, s.get("active")), flush=True)


def notice():
    command("set opponent=mobcolvr_EN2015_00_Bomb_Standard_00 count=1 behaviour=aggressive difficulty=normal")
    wait_member("mobcolvr_EN2015_00_Bomb_Standard_00")
    command("hp 1")
    job = op("combat_autopilot_async", seconds=40, execute=True, category="simulation").get("job_id")
    t0 = time.time()
    while time.time() - t0 < 40:
        if state().get("cleared"):
            at = time.time()
            name = shot("notice-at-clear")
            print("cleared; shot %s taken %.1f s after the clear was seen" % (name, time.time() - at), flush=True)
            time.sleep(1.0)
            print("one second on:", shot("notice-at-clear-1s"), flush=True)
            break
        time.sleep(0.2)
    cancel(job)


def reinforcements():
    rid = "terVR_COL30_GONGA_05_030"
    for wave in (1, 2):
        if wave == 1:
            command("set round=%s behaviour=aggressive difficulty=normal" % rid)
        else:
            r = op("press_key", key="F4", milliseconds=150, **FIELD)
            print("F4:", (r.get("result") or {}).get("outcome"), flush=True)
        wait_member(None)
        seen, t0 = set(), time.time()
        job = op("combat_autopilot_async", seconds=300, execute=True, category="simulation").get("job_id")
        took = None
        while time.time() - t0 < 300:
            s = state()
            for e in s.get("enemies", []):
                if not e.get("anchor") and not e.get("stale") and not e.get("member") and (e.get("hp") or 0) > 0:
                    if str(e.get("model")) not in seen:
                        seen.add(str(e.get("model")))
                        print("wave %d: %s came at %.0fs; shot %s" % (wave, e.get("model"), time.time() - t0,
                              shot("reinforcement-wave%d-%s" % (wave, str(e.get("model"))[:24]))), flush=True)
            if s.get("cleared"):
                took = time.time() - t0
                break
            time.sleep(1)
        cancel(job)
        print("wave %d: cleared after %s s; reinforcements seen: %s" % (wave, took and round(took), ", ".join(sorted(seen)) or "none"), flush=True)
        if not took:
            break


if __name__ == "__main__":
    for what in sys.argv[1:] or ["autolife", "notice", "reinforcements"]:
        print("==", what, flush=True)
        globals()[what]()
