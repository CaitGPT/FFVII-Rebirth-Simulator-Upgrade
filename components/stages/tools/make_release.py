"""Build the release zip, laid out so a player extracts it into the game folder.

    python tools/make_release.py <version> --dll <built main.dll> [--installed <tested mod folder>] [--out <folder>]

Takes the scripts, settings.txt and enabled.txt from ue4ss/SimulatorStages, the helper DLL given, and the readme,
licence and changelog. With --installed (the SimulatorStages folder of the game you tested), every script and the DLL
must match the tested copies byte for byte, or the build stops. settings.txt always comes from this repository: it holds
the release defaults. Prints the zip's SHA-256 and its contents. Default output: build/release/.
"""
import argparse
import hashlib
import pathlib
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MOD = "SimulatorStages"
SOURCE = ROOT / "ue4ss" / MOD


def digest(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


parser = argparse.ArgumentParser()
parser.add_argument("version")
parser.add_argument("--dll", required=True)
parser.add_argument("--installed")
parser.add_argument("--out", default=str(ROOT / "build" / "release"))
args = parser.parse_args()

changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
if f"## {args.version} " not in changelog:
    raise SystemExit(f"CHANGELOG.md has no entry for {args.version}")
settings = (SOURCE / "settings.txt").read_text(encoding="utf-8")
for line in ("require_unlock = true", "experimental = false", "force_stage =\n"):
    if line not in settings:
        raise SystemExit(f"settings.txt is not at the release defaults: missing '{line.strip()}'")

scripts = sorted((SOURCE / "Scripts").glob("*.lua"))
dll = pathlib.Path(args.dll)
if args.installed:
    tested = pathlib.Path(args.installed)
    for lua in scripts:
        if digest(lua) != digest(tested / "Scripts" / lua.name):
            raise SystemExit(f"{lua.name} differs from the tested copy: install it and test again first")
    if digest(dll) != digest(tested / "dlls" / "main.dll"):
        raise SystemExit("main.dll differs from the tested copy")
    print("scripts and helper match the tested copies")

base = f"End/Binaries/Win64/ue4ss/Mods/{MOD}"
files = [(lua, f"{base}/Scripts/{lua.name}") for lua in scripts]
files += [(dll, f"{base}/dlls/main.dll"), (SOURCE / "settings.txt", f"{base}/settings.txt"),
          (SOURCE / "enabled.txt", f"{base}/enabled.txt")]

readme = (ROOT / "tools" / "README-in-zip.txt").read_text(encoding="utf-8").replace("{version}", args.version)
out = pathlib.Path(args.out) / f"{MOD}-v{args.version}.zip"
out.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for src, arc in files:
        z.write(src, arc)
    z.writestr(f"README-{MOD}.txt", readme.replace("\r\n", "\n").replace("\n", "\r\n"))
    z.write(ROOT / "LICENSE", f"LICENSE-{MOD}.txt")
    z.write(ROOT / "CHANGELOG.md", f"CHANGELOG-{MOD}.md")
print(out, out.stat().st_size, digest(out))
with zipfile.ZipFile(out) as z:
    for info in z.infolist():
        print(f"{info.file_size:>10}  {info.filename}")
print("helper", digest(dll))
