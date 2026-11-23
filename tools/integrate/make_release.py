"""Build the release zip from a release build, laid out so a player extracts it into the game folder.

    python tools/integrate/make_release.py <version> --build <build folder> --compat-pak-dir <folder>
                                           [--installed <the game's ue4ss/Mods folder>] [--out <folder>]

--build is a folder tools/integrate/build_mod.py wrote without --dev and with --stages-dll, --native-dll and --pak-dir
(its manifest.json names the version). --compat-pak-dir holds SimulatorUpgrade_JunonCompat_9200_P.pak/.ucas/.utoc.
With --installed, every script and native helper must match the copies in the game you tested byte for byte (settings
and paks excepted), or the build stops. Prints the zip's SHA-256 and its contents. Default output: build/release/.
"""
import argparse
import hashlib
import json
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
COMPAT = "SimulatorUpgrade_JunonCompat_9200_P"


def digest(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("version")
    ap.add_argument("--build", required=True)
    ap.add_argument("--compat-pak-dir", required=True)
    ap.add_argument("--installed")
    ap.add_argument("--out", default=str(ROOT / "build" / "release"))
    args = ap.parse_args()

    build = pathlib.Path(args.build)
    manifest = json.loads((build / "manifest.json").read_text(encoding="utf-8"))
    problems = []
    if manifest["version"] != args.version:
        problems.append(f"the build is version {manifest['version']}, not {args.version}: rebuild with --version")
    if f"## {args.version} " not in (ROOT / "CHANGELOG.md").read_text(encoding="utf-8"):
        problems.append(f"CHANGELOG.md has no entry for {args.version}")
    if list(build.rglob("dev.txt")):
        problems.append("the build carries dev.txt: build it without --dev")
    for need in ("SimulatorUpgrade/dlls/main.dll", "SimulatorUpgradeNative/dlls/main.dll",
                 "~mods/SimulatorUpgrade_9200_P.pak"):
        if not (build / need).exists():
            problems.append(f"the build has no {need}")
    parts = set(manifest["parts"])
    missing = {"stages", "ct", "equipment", "meters", "ui"} - parts
    if missing:
        problems.append("the build lacks parts: " + ", ".join(sorted(missing)))
    compat = [pathlib.Path(args.compat_pak_dir) / (COMPAT + ext) for ext in (".pak", ".ucas", ".utoc")]
    problems += [f"{p} missing" for p in compat if not p.exists()]

    if args.installed and not problems:
        mods = pathlib.Path(args.installed)
        for entry in manifest["files"]:
            rel = entry["file"]
            if rel.startswith("~mods/") or rel.endswith("settings.txt"):
                continue
            tested = mods / rel
            if not tested.exists() or digest(tested) != entry["sha256"]:
                problems.append(f"{rel} differs from the tested copy in {mods}")
        if not problems:
            print("scripts and helpers match the tested copies")

    if problems:
        print("release stopped:")
        for p in problems:
            print("  -", p)
        return 1

    mods_base, paks_base = "End/Binaries/Win64/ue4ss/Mods", "End/Content/Paks/~mods"
    files = []
    for path in sorted(build.rglob("*")):
        if path.is_dir() or path.name == "manifest.json":
            continue
        rel = path.relative_to(build).as_posix()
        files.append((path, f"{paks_base}/{path.name}" if rel.startswith("~mods/") else f"{mods_base}/{rel}"))
    files += [(p, f"JunonCompat/{paks_base}/{p.name}") for p in compat]
    readme = (ROOT / "tools" / "integrate" / "README-in-zip.txt").read_text(encoding="utf-8")
    out = pathlib.Path(args.out) / f"SimulatorUpgrade-v{args.version}.zip"
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for src, arc in files:
            z.write(src, arc)
        z.writestr("SimulatorUpgrade-README.txt", readme.replace("{version}", args.version))
        z.write(ROOT / "LICENSE", "SimulatorUpgrade-LICENSE.txt")
        z.write(ROOT / "CHANGELOG.md", "SimulatorUpgrade-CHANGELOG.md")
    print(f"{out}\nsha256 {digest(out)}\n{out.stat().st_size} bytes")
    with zipfile.ZipFile(out) as z:
        for info in z.infolist():
            print(f"  {info.file_size:>10}  {info.filename}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
