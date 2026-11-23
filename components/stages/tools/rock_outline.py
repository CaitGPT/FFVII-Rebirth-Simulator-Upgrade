"""Read the vertex positions of a cooked skeletal mesh (.uexp) and print its top-down outline.

  rock_outline.py <uexp> [cell cm]

Finds position vertex buffers by their header (stride 12, count N, element size 12, count N), takes the largest, and
prints a grid of which cells hold vertices near the top surface, plus the extents per direction.
"""
import json
import math
import struct
import sys

path = sys.argv[1]
cell = float(sys.argv[2]) if len(sys.argv) > 2 else 200.0
data = open(path, "rb").read()
found = []
i = 0
while True:
    i = data.find(b"\x0c\x00\x00\x00", i)
    if i < 0 or i + 16 > len(data):
        break
    stride, n, size, n2 = struct.unpack_from("<IIII", data, i)
    if stride == 12 and size == 12 and n == n2 and 100 < n < 2_000_000 and i + 16 + n * 12 <= len(data):
        found.append((n, i + 16))
    i += 4
found.sort(reverse=True)
print("position buffers:", [(n, off) for n, off in found[:6]])
n, off = found[0]
verts = struct.unpack_from("<%df" % (n * 3), data, off)
xs, ys, zs = verts[0::3], verts[1::3], verts[2::3]
print("vertices", n, "x %.0f..%.0f y %.0f..%.0f z %.0f..%.0f" % (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
ztop = max(zs)
# The walkable top: vertices within 3 m of the highest point
top = [(x, y) for x, y, z in zip(xs, ys, zs) if z > ztop - 300]
print("top-surface vertices", len(top), "z above %.0f" % (ztop - 300))
x0, x1 = min(xs), max(xs)
y0, y1 = min(ys), max(ys)
cols = int((x1 - x0) // cell) + 1
rows = int((y1 - y0) // cell) + 1
grid = [[0] * cols for _ in range(rows)]
for x, y in top:
    grid[int((y - y0) // cell)][int((x - x0) // cell)] += 1
for r in range(rows):
    print("".join("#" if c else "." for c in grid[r]))
json.dump({"cell": cell, "x0": x0, "y0": y0, "rows": ["".join("#" if c else "." for c in row) for row in grid],
           "top": [[round(x), round(y)] for x, y in top[::max(1, len(top) // 20000)]]},
          open(path + ".outline.json", "w"))
