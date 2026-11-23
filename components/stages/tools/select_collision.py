"""List the collision grid levels (AutoGenCollision Terrain_Grid_* and GridPhys_*) that lie under an arena.

    python tools/select_collision.py <legacy Field folder of the location> <x> <y> [reach in cm, default 3000]

A location's floor and wall collision is not in its terrain levels but in grid levels named <name>_<L><XXX><YYY>, one
per square cell. Each series (05Mine_Terrain_Grid, 07Bottom_Terrain_Grid, GridPhys, ...) has its own cell size, read
from where its levels put their pieces: a Terrain_Grid level's pieces sit at the cell's centre, so
size = x / (column + 0.5). GridPhys levels are scattered pieces; their cell is read from their own bounds.
Prints the package paths of the cells within `reach` of the arena's centre, for data/stages.json.
Uses tools/dump_level.py from the research scratch tools when present (reads legacy-converted .umap files).
"""
import collections
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
ax, ay = float(sys.argv[2]), float(sys.argv[3])
reach = float(sys.argv[4]) if len(sys.argv) > 4 else 3000.0
dump = pathlib.Path(__file__).with_name("dump_level.py")
if not dump.exists():
    raise SystemExit("needs dump_level.py beside this script")

levels = [p for p in root.rglob("*.umap") if re.search(r"_(Terrain_Grid|GridPhys)_\d{7}$", p.stem)]
series = collections.defaultdict(list)
for p in levels:
    name, cell = p.stem.rsplit("_", 1)
    out = subprocess.run([sys.executable, str(dump), str(p)], capture_output=True, text=True).stdout
    pts = [tuple(map(float, m)) for m in re.findall(r'"RelativeLocation": \[([-\d.e]+), ([-\d.e]+), ([-\d.e]+)\]', out)]
    series[name].append((p, int(cell[1:4]), int(cell[4:7]), pts))

chosen = []
for name, cells in sorted(series.items()):
    sizes = []
    for p, cx, cy, pts in cells:
        if "Terrain_Grid" in name and pts:
            sizes.append(pts[0][0] / (cx + 0.5) if cx >= 0 else None)
    size = sorted(s for s in sizes if s)[len(sizes) // 2] if sizes else None
    for p, cx, cy, pts in cells:
        if size:
            x0, y0 = cx * size, cy * size
            box = (x0, x0 + size, y0, y0 + size)
        elif pts:
            xs, ys = [q[0] for q in pts], [q[1] for q in pts]
            box = (min(xs), max(xs), min(ys), max(ys))
        else:
            continue
        near = box[0] - reach <= ax <= box[1] + reach and box[2] - reach <= ay <= box[3] + reach
        if near:
            rel = p.relative_to(root.parents[3]).with_suffix("")
            chosen.append("/Game/" + str(rel).replace("\\", "/"))
for c in chosen:
    print(c)
