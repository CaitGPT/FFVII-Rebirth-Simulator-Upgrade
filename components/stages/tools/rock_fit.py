"""Find the centre and the sideways scales that fit the rock's walkable top to the arena's circle most tightly.

  rock_fit.py <uexp> [radius cm] [z floor of the walkable band, mesh units]

The top surface is rasterised at 50 cm. A candidate (cx, cy, sx, sy) covers the arena if every 1 m cell of the disc
maps back onto rock. Among those that cover, the smallest sx * sy leaves the least rock outside the wall.
Plain Python: no numpy on this machine.
"""
import math
import struct
import sys

path = sys.argv[1]
R = float(sys.argv[2]) if len(sys.argv) > 2 else 2475.0
zmin = float(sys.argv[3]) if len(sys.argv) > 3 else 520.0
data = open(path, "rb").read()
best = None
i = 0
while True:
    i = data.find(b"\x0c\x00\x00\x00", i)
    if i < 0 or i + 16 > len(data):
        break
    stride, n, size, n2 = struct.unpack_from("<IIII", data, i)
    if stride == 12 and size == 12 and n == n2 and 100 < n < 2_000_000 and i + 16 + n * 12 <= len(data):
        if best is None or n > best[0]:
            best = (n, i + 16)
    i += 4
n, off = best
flat = struct.unpack_from("<%df" % (n * 3), data, off)
xs, ys, zs = flat[0::3], flat[1::3], flat[2::3]
CELL = 50.0
x0, y0 = min(xs) - 500, min(ys) - 500
w = int((max(xs) + 500 - x0) // CELL) + 1
h = int((max(ys) + 500 - y0) // CELL) + 1
occ = bytearray(w * h)
count = 0
zlist = []
for x, y, z in zip(xs, ys, zs):
    if z > zmin:
        cx_, cy_ = int((x - x0) // CELL), int((y - y0) // CELL)
        for ax, ay in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):      # close pinholes
            occ[(cy_ + ay) * w + cx_ + ax] = 1
        count += 1
        zlist.append(z)
zlist.sort()


def morph(grid, radius, grow):
    """Dilate (grow) or erode a 0/1 grid by a square of the given radius, in two passes."""
    def pass_(g, horizontal):
        out_ = bytearray(w * h)
        for r in range(h):
            for c in range(w):
                hit = not grow
                for d in range(-radius, radius + 1):
                    rr, cc = (r, c + d) if horizontal else (r + d, c)
                    inside = 0 <= rr < h and 0 <= cc < w
                    value = g[rr * w + cc] if inside else 0
                    if grow and value:
                        hit = True
                        break
                    if not grow and not value:
                        hit = False
                        break
                out_[r * w + c] = 1 if hit else 0
        return out_
    return pass_(pass_(grid, True), False)


CLOSE = int(sys.argv[4]) if len(sys.argv) > 4 else 4
occ = morph(morph(occ, CLOSE, True), CLOSE, False)      # close cracks up to CLOSE cells (50 cm each) each side
for r in range(0, h, 4):
    print("".join("#" if occ[r * w + c] else "." for c in range(0, w, 4)))
print("vertices", n, "walkable-band vertices", count, "median z %.0f" % zlist[len(zlist) // 2],
      "5%%..95%% %.0f..%.0f" % (zlist[len(zlist) // 20], zlist[-len(zlist) // 20]))
print("rock top area %.0f m2" % (sum(occ) * CELL * CELL / 1e4))

disc = []
steps = int(R // 100)
for iy in range(-steps, steps + 1):
    for ix in range(-steps, steps + 1):
        if ix * ix + iy * iy <= steps * steps:
            disc.append((ix * 100.0, iy * 100.0))
for k in range(72):                                   # and the rim itself
    a = math.radians(k * 5)
    disc.append((R * math.cos(a), R * math.sin(a)))
disc.sort(key=lambda p: -(p[0] * p[0] + p[1] * p[1]))


def covers(cx, cy, sx, sy):
    for dx, dy in disc:
        lx = int((dx / sx + cx - x0) // CELL)
        ly = int((dy / sy + cy - y0) // CELL)
        if not (0 <= lx < w and 0 <= ly < h and occ[ly * w + lx]):
            return False
    return True


def frange(a, b, step):
    out, v = [], a
    while v <= b + 1e-9:
        out.append(round(v, 4))
        v += step
    return out


def search(cxs, cys, sxs, sys_):
    pairs = sorted(((sx * sy, sx, sy) for sx in sxs for sy in sys_))
    for area, sx, sy in pairs:
        for cx in cxs:
            for cy in cys:
                if covers(cx, cy, sx, sy):
                    return area, cx, cy, sx, sy
    return None


coarse = search(frange(-400, 400, 100), frange(-400, 400, 100), frange(0.90, 1.60, 0.05), frange(1.20, 2.40, 0.05))
print("coarse", coarse)
_, cx, cy, sx, sy = coarse
fine = search(frange(cx - 100, cx + 100, 25), frange(cy - 100, cy + 100, 25),
              frange(sx - 0.06, sx + 0.02, 0.01), frange(sy - 0.06, sy + 0.02, 0.01))
print("fine", fine)
_, cx, cy, sx, sy = fine
out = []
for deg in range(0, 360, 15):
    a = math.radians(deg)
    r = R
    while True:
        lx = int(((r * math.cos(a)) / sx + cx - x0) // CELL)
        ly = int(((r * math.sin(a)) / sy + cy - y0) // CELL)
        if not (0 <= lx < w and 0 <= ly < h and occ[ly * w + lx]):
            break
        r += 25
    out.append("%d:%.1f" % (deg, (r - R) / 100))
print("rock past the wall, metres, by direction:", " ".join(out))
s = 1.2
while s < 2.6 and not covers(cx, cy, s, s):
    s += 0.02
print("one scale for both directions would need %.2f" % s)
