"""Load the integrated build's main.lua offline, with UE4SS's globals stubbed, and check every part starts.

    python tools/integrate/smoke_test.py [build/integrated]

It catches what the build itself can't: a part that requires a module another part also defines, a missing file, a
syntax or load-time error, a part that reads its own folder wrongly. Game calls are stubs that do nothing and return
nothing, so no part gets further than its start-up; the game itself is the real test.
"""
import pathlib
import sys

from lupa import lua54

ROOT = pathlib.Path(__file__).resolve().parents[2]
STUBS = r"""
local function stub_object()
    local o = {}
    return setmetatable(o, {
        __index = function() return stub_object() end,
        __call = function() return nil end,
    })
end
local real = {print = print, string = string, table = table, math = math, os = os, io = io, pairs = pairs,
              ipairs = ipairs, pcall = pcall, type = type, tostring = tostring, tonumber = tonumber, require = require,
              setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset,
              select = select, next = next, error = error, assert = assert, load = load, debug = debug,
              package = package, coroutine = coroutine, utf8 = utf8, xpcall = xpcall, rawequal = rawequal}
PRINTED = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    PRINTED[#PRINTED + 1] = table.concat(parts, " ")
end
-- UE4SS's functions: accept anything, do nothing.
for _, name in ipairs({"RegisterKeyBind", "RegisterHook", "NotifyOnNewObject", "LoopAsync", "ExecuteWithDelay",
                       "ExecuteAsync", "ExecuteInGameThread", "RegisterCustomEvent", "RegisterConsoleCommandHandler",
                       "RegisterLoadMapPreHook", "RegisterLoadMapPostHook", "RegisterInitGameStatePostHook",
                       "RegisterBeginPlayPostHook", "FindFirstOf", "FindAllOf", "StaticFindObject", "FindObject",
                       "LoadAsset", "StaticConstructObject", "IsKeyBindRegistered", "CreateInvalidObject"}) do
    _G[name] = function() return nil end
end
FName = function(s) return {ToString = function() return s end} end
FText = FName
Key = setmetatable({}, {__index = function(_, k) return k end})
ModifierKey = Key
-- Anything else a part reads from the global table at load: a do-nothing object, reported.
UNKNOWN = {}
setmetatable(_G, {__index = function(_, k)
    if real[k] ~= nil then return real[k] end
    UNKNOWN[k] = true
    return stub_object()
end})
"""


def main():
    build = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "build" / "integrated")
    scripts = build / "SimulatorUpgrade" / "Scripts"
    if not (scripts / "main.lua").exists():
        print(f"no build at {build}")
        return 1
    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{scripts.as_posix()}/?.lua;" .. package.path')
    lua.execute(STUBS)
    try:
        lua.execute((scripts / "main.lua").read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"main.lua failed: {exc}")
        return 1
    printed = list(lua.eval("PRINTED").values())
    for line in printed:
        print("  |", line.strip())
    unknown = sorted(lua.eval("UNKNOWN").keys())
    if unknown:
        print("globals read that UE4SS may not have (check):", ", ".join(unknown))
    failed = [line for line in printed if "failed to start" in line]
    # Every part's LoopAsync goes through the shared scheduler (overhaul_tick.lua), none straight to UE4SS.
    status = lua.eval("SIM_OVERHAUL_TICK and SIM_OVERHAUL_TICK.status() or nil")
    print("  scheduler:", status)
    if not status or " loops 0," in status:
        failed.append("the scheduler is missing or no part's loop went through it")
    print("smoke test: " + ("FAILED" if failed else "every part started"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
