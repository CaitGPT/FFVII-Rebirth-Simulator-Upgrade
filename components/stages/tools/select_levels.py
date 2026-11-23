"""Choose which of a location's layout levels a streamed stage loads, and write them into data/stages.json.

    python tools/select_levels.py <stage id> <legacy-converted Layout folder> <cx> <cy> <radius cm> [--write]

The folder is the output of `retoc to-legacy --no-shaders -f "Field/<location>/Layout/"` (game-derived, kept outside
this repository). The reader is FFVII-Modding's FF7R_Indexer/level_layout_points.py: set FF7R_INDEXER to its folder.

A level is chosen when it places something (a mesh, light, effect) within the radius of the arena's centre, or when
it is a 'massive' terrain level (its meshes sit behind a streaming proxy, with no positions in its properties) that
either has no sub-area in its name (the location's base terrain) or shares a named sub-area with a chosen level. Left out on purpose: collision and
navigation levels (the simulator keeps its own flat floor), low-spec twins, music, alternate times of day, cutscene
sets, and Gimmick and Physics levels (interactable and story objects) unless --gimmick is given.

This is a first cut from static data. Expect to trim it in the game.
"""
import json
import math
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, os.environ.get("FF7R_INDEXER", ""))
import level_layout_points as L  # noqa: E402

LOC = re.compile(r'"RelativeLocation": \[([-\d.e]+), ([-\d.e]+), ([-\d.e]+)\]')
SKIP_PATH = ("AutoGenCollision", "GridPhys", "Navigation_Mod", "NavMesh", "/Cut/", "/Before/", "/BeforeFire/", "/NotFire/", "/PastSound/")
SKIP_NAME = ("_Low_", "_Low", "Sound_BGM", "_Sound", "TimeSet_Night", "TimeSet_Sunset", "TimeSet_Morning", "TimeSet_Cloudy",
             "Timeset_None", "_Before_", "_Before", "LocationPoint")
INTERACTIVE = ("Gimmick", "Physics")


def survey(folder, cx, cy, radius):
    rows = []
    for umap in sorted(folder.rglob("*.umap")):
        rel = umap.as_posix()
        if any(s in rel for s in SKIP_PATH):
            continue
        name = umap.stem
        size = sum(f.stat().st_size for f in umap.parent.glob(name + ".*"))
        try:
            p = L.LegacyPackage(umap)
        except Exception:
            continue
        near = total = 0
        massive = False
        for i, _ in enumerate(p.exports, 1):
            cls = p.class_name(i)
            if cls.startswith("MassiveEnvironment"):
                massive = True
            if "Component" not in cls:
                continue
            try:
                m = LOC.search(json.dumps(p.properties(i), default=str))
            except Exception:
                continue
            if not m:
                continue
            total += 1
            if math.hypot(float(m[1]) - cx, float(m[2]) - cy) <= radius:
                near += 1
        package = "/Game/" + rel.split("/End/Content/", 1)[1][: -len(".umap")]
        rows.append({"name": name, "package": package, "bytes": size, "near": near, "placed": total, "massive": massive})
    return rows


def area_words(name):
    """Sub-area words in a level name: '2200-CORLA_23MainAreaTree_Terrain_Strip' -> {'MainArea'}."""
    body = re.sub(r"^\d{4}-[A-Z0-9]+_", "", name)
    words = set()
    for part in body.split("_"):
        part = re.sub(r"^\d+", "", part)
        part = re.sub(r"(NatureMini|Nature|Tree|Grass|Interior|Inside|Structure)$", "", part)
        if part and part not in ("Terrain", "Strip", "Light", "Effect", "Emissive", "FarLand", "TimeSet", "Day", "Water",
                                 "GrassOffs", "Gimmick", "Physics", "Other", "Additional", "Far"):
            words.add(part)
    return words


def choose(rows, gimmick):
    def allowed(row):
        if any(s in row["name"] for s in SKIP_NAME):
            return False
        return gimmick or not any(s in row["name"] for s in INTERACTIVE)

    chosen = [r for r in rows if r["near"] > 0 and allowed(r)]
    words = set()
    for r in chosen:
        words |= area_words(r["name"])
    for r in rows:
        if r in chosen or not allowed(r) or not r["massive"]:
            continue
        mine = area_words(r["name"])
        if not mine or mine & words:
            chosen.append(r)
    return sorted(chosen, key=lambda r: r["name"])


def main() -> int:
    stage_id, folder = sys.argv[1], pathlib.Path(sys.argv[2])
    cx, cy, radius = float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
    rows = survey(folder, cx, cy, radius)
    chosen = choose(rows, "--gimmick" in sys.argv)
    total = sum(r["bytes"] for r in chosen) / 1e6
    print(f"{stage_id}: {len(chosen)} of {len(rows)} levels, {total:.0f} MB")
    for r in sorted(chosen, key=lambda r: -r["bytes"]):
        print(f"  {r['bytes'] / 1e6:7.1f} MB  near {r['near']:4d}/{r['placed']:5d} {'massive' if r['massive'] else '       '} {r['name']}")
    if "--write" in sys.argv:
        path = ROOT / "data" / "stages.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        stage = next(s for s in data["stages"] if s["id"] == stage_id)
        stage["levels"] = [r["package"] for r in chosen]
        stage["levels_mb"] = round(total)
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8", newline="\n")
        print("  written to data/stages.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
