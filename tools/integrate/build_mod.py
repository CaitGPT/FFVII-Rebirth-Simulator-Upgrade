"""Assemble the integrated Simulator Upgrade mod from every part's development mod.

    python tools/integrate/build_mod.py [--out build/integrated] [--stages-dll <main.dll>] [--native-dll <main.dll>]
                                        [--pak-dir <folder with SimulatorUpgrade_P.pak/.ucas/.utoc>] [--dev]

Writes, under --out:

    SimulatorUpgrade/            one UE4SS mod: every part's scripts, the shared settings.txt, enabled.txt,
                                  and Simulator Stages' level helper as dlls/main.dll
    SimulatorUpgradeNative/      Custom Training's native helper as dlls/main.dll (it registers its functions for
                                  the Lua mod named SimulatorUpgrade)
    ~mods/                        the pak, when --pak-dir is given
    manifest.json                 every file with its SHA-256 and the part it came from

The rules the parts follow so this works without edits are in docs/COORDINATION.md ("The integrated mod"). The build
stops on anything that breaks them: two parts shipping the same script path, a part without settings, a part whose
main.lua doesn't honour SIM_OVERHAUL_DIR.
"""
import argparse
import hashlib
import json
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

# Load order: Stages before Custom Training (Custom Training's course is
# a simulator course Stages may dress), then the parts that draw on top.
PARTS = [
    ("stages", "SimOverhaulStages"),
    ("ct", "SimOverhaulCustomTraining"),
    ("equipment", "SimOverhaulEquipment"),
    ("meters", "SimOverhaulMeters"),
    ("ui", "SimOverhaulUI"),
]

# Development-only files a part may keep beside its scripts; never shipped.
DEV_ONLY = {"dev.txt"}

MAIN_TEMPLATE = """-- Simulator Upgrade: Chadley's combat simulator, upgraded. Built by tools/integrate/build_mod.py from the parts
-- listed below; each part is its own module, started in turn, so one failing leaves the others running.
-- Source and docs: the Simulator Upgrade repository.

-- Register this mod's game-thread callback while mods load: a first ExecuteInGameThread during play can crash. Its
-- first run, on the game thread, tells the native pump (SimulatorUpgradeNative) which thread that is.
pcall(ExecuteInGameThread, function()
    if type(SimOverhaulGamePumpBind) == "function" then pcall(SimOverhaulGamePumpBind) end
end)

local MOD_DIR = package.path:match("([^;]*[\\\\/]SimulatorUpgrade[\\\\/])[Ss]cripts[\\\\/]%?%.lua")
if not MOD_DIR then
    local source = debug.getinfo(1, "S").source
    MOD_DIR = source:match("^@(.*[\\\\/])[Ss]cripts[\\\\/]") or ""
end
SIM_OVERHAUL_DIR = MOD_DIR
SIM_OVERHAUL_VERSION = "__VERSION__"

local PARTS = __PARTS__

-- One scheduler for every part's LoopAsync and ExecuteInGameThread (overhaul_tick.lua, docs/workstreams/lua-state.md):
-- UE4SS 3.0.1 makes a Lua thread per ExecuteInGameThread and its unlocked thread map then loses or crashes on a lookup.
local tick_ok, tick = pcall(require, "overhaul_tick")
if tick_ok then
    local function tick_log(line) print("[SimulatorUpgrade] tick\\t" .. line .. "\\n") end
    tick.install(_G, tick_log)
    local dev_file = io.open(MOD_DIR .. "dev.txt", "r")
    if dev_file then dev_file:close() end
    tick.start_reports(MOD_DIR, dev_file ~= nil, tick_log)
    SIM_OVERHAUL_TICK = tick
else
    print(string.format("[SimulatorUpgrade] scheduler failed to load, parts use UE4SS's own loops: %s\\n", tostring(tick)))
end

local started, failed = {}, {}
for _, part in ipairs(PARTS) do
    local ok, err = pcall(require, part .. "_main")
    if ok then
        started[#started + 1] = part
    else
        failed[#failed + 1] = part
        print(string.format("[SimulatorUpgrade] part %s failed to start: %s\\n", part, tostring(err)))
    end
end
print(string.format("[SimulatorUpgrade] %s loaded from %s; started: %s%s\\n", SIM_OVERHAUL_VERSION, MOD_DIR,
    table.concat(started, ", "), #failed > 0 and ("; failed: " .. table.concat(failed, ", ")) or ""))
"""


def sha(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "build" / "integrated"))
    ap.add_argument("--version", default="0.0.0-dev")
    ap.add_argument("--stages-dll")
    ap.add_argument("--native-dll")
    ap.add_argument("--pak-dir")
    ap.add_argument("--pak-name", default="SimulatorUpgrade_9200_P")
    ap.add_argument("--dev", action="store_true", help="add dev.txt (logs and development consoles)")
    ap.add_argument("--parts", help="comma-separated subset of parts, for testing")
    args = ap.parse_args()

    out = pathlib.Path(args.out)
    if out.exists():
        shutil.rmtree(out)
    mod = out / "SimulatorUpgrade"
    scripts_out = mod / "Scripts"
    scripts_out.mkdir(parents=True)
    manifest, problems, included = [], [], []
    wanted = set(args.parts.split(",")) if args.parts else None
    owner = {}
    settings_sections = []

    for part, folder in PARTS:
        if wanted and part not in wanted:
            continue
        src = ROOT / "ue4ss" / folder
        if not (src / "Scripts" / "main.lua").exists():
            print(f"skip {part}: no {folder}/Scripts/main.lua yet")
            continue
        included.append(part)
        main_text = (src / "Scripts" / "main.lua").read_text(encoding="utf-8")
        if "SIM_OVERHAUL_DIR" not in main_text:
            problems.append(f"{part}: main.lua doesn't read SIM_OVERHAUL_DIR")
        for file in sorted((src / "Scripts").rglob("*")):
            if file.is_dir():
                continue
            rel = file.relative_to(src / "Scripts").as_posix()
            target_rel = f"{part}_main.lua" if rel == "main.lua" else rel
            if target_rel in owner:
                problems.append(f"{part} and {owner[target_rel]} both ship Scripts/{target_rel}")
                continue
            owner[target_rel] = part
            target = scripts_out / target_rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(file, target)
            manifest.append({"file": f"SimulatorUpgrade/Scripts/{target_rel}", "part": part, "sha256": sha(target)})
        settings = src / "settings.txt"
        if settings.exists():
            text = settings.read_text(encoding="utf-8").strip()
            settings_sections.append(f"# ==== {part} ====\n{text}\n")
        else:
            problems.append(f"{part}: no settings.txt (ship at least a comment saying it has none)")
        for extra in sorted(src.iterdir()):
            if extra.is_file() and extra.name not in DEV_ONLY | {"settings.txt", "enabled.txt"} \
                    and extra.suffix in (".txt", ".json", ".tsv", ".csv"):
                # Data a part reads at runtime (not logs or state, which a development install writes).
                if any(extra.name.startswith(p) for p in ("ct-log", "ct-state", "ct-course", "machine-log", "equip-",
                                                          "stages-", "meters-log", "ui-log")):
                    continue
                problems.append(f"{part}: {extra.name} beside the scripts: ship it under Scripts/ or say why")

    if problems:
        print("build stopped:")
        for p in problems:
            print("  -", p)
        return 1

    # The shared scheduler every part's loops run through (docs/workstreams/lua-state.md).
    tick_src = ROOT / "tools" / "integrate" / "overhaul_tick.lua"
    if "overhaul_tick.lua" in owner:
        print(f"build stopped: {owner['overhaul_tick.lua']} ships Scripts/overhaul_tick.lua, the scheduler's name")
        return 1
    shutil.copyfile(tick_src, scripts_out / "overhaul_tick.lua")
    manifest.append({"file": "SimulatorUpgrade/Scripts/overhaul_tick.lua", "part": "integrate",
                     "sha256": sha(scripts_out / "overhaul_tick.lua")})

    parts_lua = "{" + ", ".join(f'"{p}"' for p in included) + "}"
    main_lua = MAIN_TEMPLATE.replace("__VERSION__", args.version).replace("__PARTS__", parts_lua)
    (scripts_out / "main.lua").write_text(main_lua, encoding="utf-8", newline="\n")
    manifest.append({"file": "SimulatorUpgrade/Scripts/main.lua", "part": "integrate", "sha256": sha(scripts_out / "main.lua")})

    header = ("# Simulator Upgrade settings. Each part reads only its own keys (stages_, ct_, equipment_,\n"
              "# meters_, ui_); lines starting with # are notes.\n\n")
    (mod / "settings.txt").write_text(header + "\n".join(settings_sections), encoding="utf-8", newline="\n")
    (mod / "enabled.txt").write_text("", encoding="utf-8")
    if args.dev:
        (mod / "dev.txt").write_text("development install: logs and consoles on\n", encoding="utf-8")
    for name in ("settings.txt", "enabled.txt"):
        manifest.append({"file": f"SimulatorUpgrade/{name}", "part": "integrate", "sha256": sha(mod / name)})

    if args.stages_dll:
        (mod / "dlls").mkdir()
        shutil.copyfile(args.stages_dll, mod / "dlls" / "main.dll")
        manifest.append({"file": "SimulatorUpgrade/dlls/main.dll", "part": "stages", "sha256": sha(mod / "dlls" / "main.dll")})
    if args.native_dll:
        native = out / "SimulatorUpgradeNative"
        (native / "dlls").mkdir(parents=True)
        shutil.copyfile(args.native_dll, native / "dlls" / "main.dll")
        (native / "enabled.txt").write_text("", encoding="utf-8")
        manifest.append({"file": "SimulatorUpgradeNative/dlls/main.dll", "part": "ct", "sha256": sha(native / "dlls" / "main.dll")})
    if args.pak_dir:
        paks = out / "~mods"
        paks.mkdir()
        for ext in (".pak", ".ucas", ".utoc"):
            src = pathlib.Path(args.pak_dir) / (args.pak_name + ext)
            if not src.exists():
                print(f"build stopped: {src} missing")
                return 1
            shutil.copyfile(src, paks / src.name)
            manifest.append({"file": f"~mods/{src.name}", "part": "pak", "sha256": sha(paks / src.name)})

    # A part's dev.txt (tracked so its development install works) turns on logs, state files and the eval consoles:
    # only a --dev build may carry one.
    stray = [p for p in out.rglob("dev.txt") if not (args.dev and p == mod / "dev.txt")]
    if stray:
        print("build stopped: dev.txt in a release build: " + ", ".join(str(p) for p in stray))
        return 1

    (out / "manifest.json").write_text(json.dumps({"version": args.version, "parts": included, "files": manifest},
                                                  indent=1), encoding="utf-8")
    print(f"built {out} with parts: {', '.join(included)}; {len(manifest)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
