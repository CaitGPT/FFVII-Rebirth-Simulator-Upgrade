"""Live test helpers for the ui workstream (development install: dev.txt in SimOverhaulUI enables ui-command.txt and
ui-log.txt). Drives the game through the harness (the mod skill's scripts/mcp.py) where it can, and through the
mod's development commands where it can't yet (keys while the game is paused, keyboard keys).

    python ui_live.py install              copy ue4ss/SimOverhaulUI into the game (only while holding the game lock)
    python ui_live.py cmd "<command>"      write one development command (menu, key K, pick N, dump, probe N, ...)
    python ui_live.py log [N]              the last N lines of ui-log.txt
    python ui_live.py dump                 ui-dump.txt
    python ui_live.py shot NAME            capture the game window into docs/workstreams/ui/NAME.png
    python ui_live.py chord                hold RB and press LB in a fight (opens the menu with the pad)
    python ui_live.py pad BUTTON           tap a pad button through the harness (when it allows it)
"""
import json, os, shutil, sys, time

sys.path.insert(0, os.environ.get("REBIRTH_MCP_SCRIPTS", os.path.expanduser("~/.claude/skills/create-rebirth-mod/scripts")))
from mcp import op  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
GAME_MODS = r"D:/Epic Games/FinalFantasyVIIRebirth/End/Binaries/Win64/ue4ss/Mods"
# The integrated build (the game's baseline from 2026-11-21, docs/COORDINATION.md) keeps ui's files in the mod's own
# folder: SimulatorUpgrade since the rename ("The name"), SimulatorOverhaul while an older build is still installed; a
# standalone development install in SimOverhaulUI. UI_MOD overrides.
def _mod_folder():
    for name in ("SimulatorUpgrade", "SimulatorOverhaul"):
        if os.path.exists(os.path.join(GAME_MODS, name, "enabled.txt")):
            return os.path.join(GAME_MODS, name)
    return os.path.join(GAME_MODS, "SimOverhaulUI")


MOD = os.environ.get("UI_MOD") or _mod_folder()
SHOTS = os.path.join(REPO, "docs", "workstreams", "ui")


def command(text, wait=True):
    tmp = os.path.join(MOD, "ui-command.tmp")
    with open(tmp, "w", newline="\n") as f:
        f.write(text + "\n")
    os.replace(tmp, os.path.join(MOD, "ui-command.txt"))
    if not wait:
        return True
    for _ in range(50):
        time.sleep(0.1)
        if not os.path.exists(os.path.join(MOD, "ui-command.txt")):
            return True
    return False


def log(n=20):
    try:
        with open(os.path.join(MOD, "ui-log.txt"), encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()[-n:]
    except OSError:
        return []


def install():
    src = os.path.join(REPO, "ue4ss", "SimOverhaulUI")
    os.makedirs(MOD, exist_ok=True)
    for name in ("enabled.txt", "dev.txt"):
        shutil.copy2(os.path.join(src, name), os.path.join(MOD, name))
    if not os.path.exists(os.path.join(MOD, "settings.txt")):
        shutil.copy2(os.path.join(src, "settings.txt"), os.path.join(MOD, "settings.txt"))
    shutil.copytree(os.path.join(src, "Scripts"), os.path.join(MOD, "Scripts"), dirs_exist_ok=True)
    print("installed", sorted(os.listdir(os.path.join(MOD, "Scripts"))))


def to_jpeg(src, dst, quality=85):
    """The harness captures 1080p BMPs (6 MB); the doc keeps full-size JPEGs (a few hundred KB), through Windows' own
    System.Drawing (no Python packages)."""
    import subprocess
    script = ("Add-Type -AssemblyName System.Drawing; $i = [System.Drawing.Image]::FromFile($env:UI_SRC); "
              "$c = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }; "
              "$p = New-Object System.Drawing.Imaging.EncoderParameters(1); "
              "$p.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$env:UI_Q); "
              "$i.Save($env:UI_DST, $c, $p); $i.Dispose()")
    subprocess.run(["powershell", "-NoProfile", "-Command", script], check=True,
                   env=dict(os.environ, UI_SRC=os.path.abspath(src), UI_DST=os.path.abspath(dst), UI_Q=str(quality)))


def shot(name):
    r = op("capture_game_window")
    res = r.get("result") or r
    path = res.get("image_path") or res.get("path") or res.get("screenshot_path") or (res.get("artifact") or {}).get("path")
    if not path:
        print(json.dumps(res)[:600])
        return None
    os.makedirs(SHOTS, exist_ok=True)
    out = os.path.join(SHOTS, name + ".jpg")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    to_jpeg(path, out)
    print(out)
    return out


if __name__ == "__main__":
    what = sys.argv[1]
    if what == "install":
        install()
    elif what == "cmd":
        print(command(sys.argv[2]))
        time.sleep(0.6)
        print("\n".join(log(8)))
    elif what == "log":
        print("\n".join(log(int(sys.argv[2]) if len(sys.argv) > 2 else 20)))
    elif what == "dump":
        print(open(os.path.join(MOD, "ui-dump.txt"), encoding="utf-8", errors="replace").read())
    elif what == "shot":
        shot(sys.argv[2])
    elif what == "chord":
        print(json.dumps(op("battle_pad_chord", hold="guard", press="shortcut"))[:600])
    elif what == "pad":
        print(json.dumps(op("tap_button", button=sys.argv[2], milliseconds=120))[:600])
    else:
        raise SystemExit(__doc__)
