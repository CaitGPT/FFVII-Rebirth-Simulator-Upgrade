"""Compile the meters workstream's runtime scripts with Lua 5.4 and run its pure-Lua tests, each in a fresh state.

    python -m pip install lupa
    python tests/meters/run_tests.py
"""
import pathlib
import sys

from lupa import lua54

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "ue4ss" / "SimOverhaulMeters" / "Scripts"
TESTS = pathlib.Path(__file__).resolve().parent


def runtime():
    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{SCRIPTS.as_posix()}/?.lua;{TESTS.as_posix()}/?.lua;" .. package.path')
    return lua


def main() -> int:
    failures = 0
    check = runtime().eval("function(src, name) local f, e = load(src, name); return f ~= nil, e end")
    for script in sorted(SCRIPTS.glob("*.lua")):
        compiled, error = check(script.read_text(encoding="utf-8"), "@" + script.name)
        if not compiled:
            print(f"syntax error: {error}")
            failures += 1
    for test in sorted(TESTS.glob("*_test.lua")):
        try:
            runtime().execute(test.read_text(encoding="utf-8"))
            print(f"{test.name}: ok")
        except Exception as exc:  # LuaError carries the assertion message
            print(f"{test.name}: FAILED {exc}")
            failures += 1
    print("all passed" if failures == 0 else f"{failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
