"""Run the integrated mod's pure-Lua tests (the shared scheduler, tools/integrate/overhaul_tick.lua) with Lua 5.4.

    python -m pip install lupa
    python tests/integrate/run_tests.py
"""
import pathlib
import sys

from lupa import lua54

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "tools" / "integrate"
TESTS = pathlib.Path(__file__).resolve().parent


def main() -> int:
    failures = 0
    for test in sorted(TESTS.glob("*_test.lua")):
        lua = lua54.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(f'package.path = "{SCRIPTS.as_posix()}/?.lua;" .. package.path')
        try:
            lua.execute(test.read_text(encoding="utf-8"))
            print(f"{test.name}: ok")
        except Exception as exc:  # LuaError carries the failing test's name and message
            print(f"{test.name}: FAILED {exc}")
            failures += 1
    print("all passed" if failures == 0 else f"{failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
