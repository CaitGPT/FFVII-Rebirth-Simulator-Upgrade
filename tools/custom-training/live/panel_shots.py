"""Screenshots of the settings panel for the longest and shortest opponent names and a boss (owner 2026-11-21).

usage: panel_shots.py [outdir]   (course running, development install; the panel is opened with the dev command)
Writes panel-<what>.png (the left part of the screen, where the panel is) and prints what it chose.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ct_live  # noqa: E402
from ct_live import op, state, command  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
OUTDIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "docs", "workstreams", "custom-training")


def lists():
    command("lists")
    time.sleep(2)
    out = []
    with open(os.path.join(ct_live.MOD, "ct-lists.txt"), encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if p[0] == "opponent":
                out.append({"id": p[1], "kind": p[3], "boss": p[4] == "true", "name": p[5]})
    return out


def shot(path):
    src = op("capture_game_window")["result"]["image_path"]
    ps = ("Add-Type -AssemblyName System.Drawing; $i=[System.Drawing.Image]::FromFile('%s'); "
          "$w=[int]($i.Width*0.5); $h=[int]($i.Height*0.86); "
          "$c=New-Object System.Drawing.Bitmap $w,$h; $g=[System.Drawing.Graphics]::FromImage($c); "
          "$g.DrawImage($i,(New-Object System.Drawing.Rectangle 0,0,$w,$h),(New-Object System.Drawing.Rectangle 0,0,$w,$h),"
          "[System.Drawing.GraphicsUnit]::Pixel); $s=New-Object System.Drawing.Bitmap $c,([int]($w*0.75)),([int]($h*0.75)); "
          "$s.Save('%s',[System.Drawing.Imaging.ImageFormat]::Png)") % (src, path)
    subprocess.run(["powershell", "-NoProfile", "-Command", ps], check=True)


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    all_ = lists()
    longest = max(all_, key=lambda o: len(o["name"]))
    shortest = min(all_, key=lambda o: len(o["name"]))
    boss = max((o for o in all_ if o["boss"]), key=lambda o: len(o["name"]))
    for what, o in (("longest", longest), ("shortest", shortest), ("boss", boss)):
        command("set opponent=%s" % o["id"])
        for _ in range(40):
            if state().get("opponent") == o["id"]:
                break
            time.sleep(0.5)
        time.sleep(1.0)
        command("menu")
        for _ in range(20):
            if state().get("menu_open"):
                break
            time.sleep(0.5)
        time.sleep(1.0)
        path = os.path.join(OUTDIR, "panel-%s-2026-11-21.png" % what)
        shot(path)
        print(what, o["id"], repr(o["name"]), len(o["name"]), "->", path, flush=True)
        command("key back")
        time.sleep(1.5)


if __name__ == "__main__":
    main()
