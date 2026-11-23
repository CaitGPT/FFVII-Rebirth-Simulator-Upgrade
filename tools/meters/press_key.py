"""Press one keyboard key in the game, for testing the meters' keys (the harness has no F keys).

    python tools/meters/press_key.py F9 [F5 ...]

Brings the game to the front through the harness (focus_game_window), then sends the key with Windows SendInput,
as a keyboard would. Only while this workstream holds the game lock (docs/COORDINATION.md).
"""
import ctypes
import os
import sys
import time
from ctypes import wintypes

sys.path.insert(0, os.path.join(os.path.expanduser("~"), ".claude", "skills", "create-rebirth-mod", "scripts"))
from mcp import op  # noqa: E402

VK = {f"F{i}": 0x6F + i for i in range(1, 13)}
INPUT_KEYBOARD, KEYEVENTF_KEYUP = 1, 0x0002


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD), ("dwFlags", wintypes.DWORD),
                ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong))]


class INPUT(ctypes.Structure):
    class _U(ctypes.Union):
        _fields_ = [("ki", KEYBDINPUT), ("pad", ctypes.c_byte * 32)]
    _anonymous_ = ("u",)
    _fields_ = [("type", wintypes.DWORD), ("u", _U)]


def send(vk, up):
    scan = ctypes.windll.user32.MapVirtualKeyW(vk, 0)
    event = INPUT(type=INPUT_KEYBOARD)
    event.ki = KEYBDINPUT(wVk=vk, wScan=scan, dwFlags=KEYEVENTF_KEYUP if up else 0, time=0, dwExtraInfo=None)
    return ctypes.windll.user32.SendInput(1, ctypes.byref(event), ctypes.sizeof(INPUT))


def main():
    keys = [k.upper() for k in sys.argv[1:]]
    if not keys or any(k not in VK for k in keys):
        raise SystemExit("usage: press_key.py F1..F12 ...")
    focus = op("focus_game_window")
    if not (focus.get("ok") and (focus.get("result") or {}).get("ok", True)):
        raise SystemExit(f"could not focus the game: {focus}")
    time.sleep(0.4)
    for key in keys:
        sent = send(VK[key], False)
        time.sleep(0.12)
        sent += send(VK[key], True)
        print(key, "sent" if sent == 2 else f"SendInput returned {sent}")
        time.sleep(0.5)


if __name__ == "__main__":
    main()
