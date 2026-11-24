"""Fairness and exploit checks for the duel map (run `lune run build` first).

  python3 -I tools/check_duel.py [image_dir]

  1. Footprint: everything fits in 250 x 250 studs.
  2. Symmetry: every part that collides or stops a raycast has a twin turned 180 degrees about the
     centre, so neither team has a different map.
  3. Movement (on a 1-stud grid, with headroom and a character's width): from Red's spawn you can walk
     to Blue's; listing every surface higher than 7.5 studs that can be reached by jumping
     (jump height 7.2, about 8 studs across) — these are perches you may not want.
  4. Spawn safety: no place outside a team's spawn courtyard (and its three doorways) has a line of
     sight to any of its spawn points, at head or chest height.
  5. Sight lines: the longest clear eye-to-eye lines between places players can stand.

Exits non-zero when 1, 2, the Red-to-Blue walk or 4 fail. Perches and sight lines are reported.
"""
import json
import math
import sys
from collections import deque

import numpy as np

P = json.load(open('build/parts.json'))
OUT = sys.argv[1] if len(sys.argv) > 1 else None
failures = []

HALF = 125
N = 2 * HALF            # 1-stud cells, x and z
Y0, YRES, NY = -6.0, 0.5, 104   # vertical grid for line of sight: -6 .. 46
JUMP = 7.2
STEP = 1.3
HEAD = 5.0


def rot(p):
    return np.array(p['c'][3:]).reshape(3, 3)


def aabb(p):
    R = np.abs(rot(p))
    h = R @ (np.array(p['s']) / 2)
    o = np.array(p['c'][:3])
    return o - h, o + h


# ---------------------------------------------------------------- 1. footprint
lo = np.min([aabb(p)[0] for p in P], axis=0)
hi = np.max([aabb(p)[1] for p in P], axis=0)
print(f'footprint {hi[0] - lo[0]:.1f} x {hi[2] - lo[2]:.1f} studs (x {lo[0]:.1f}..{hi[0]:.1f}, z {lo[2]:.1f}..{hi[2]:.1f})')
if hi[0] - lo[0] > 250.01 or hi[2] - lo[2] > 250.01:
    failures.append('the map is larger than 250 x 250')

# ---------------------------------------------------------------- 2. symmetry
def key(p, twin=False):
    a, b = aabb(p)
    if twin:
        a, b = np.array([-b[0], a[1], -b[2]]), np.array([-a[0], b[1], -a[2]])
    k = [p['k'], *np.round(a, 2), *np.round(b, 2)]
    if p['k'] == 'Wedge':
        R = rot(p)
        down = -R[:, 2]          # direction the slope descends
        up = R[:, 1]
        if twin:
            down = down * np.array([-1, 1, -1])
            up = up * np.array([-1, 1, -1])
        k += [*np.round(down, 2), *np.round(up, 2)]
    return tuple(float(v) if not isinstance(v, str) else v for v in k)


solid = [p for p in P if (p['col2'] or p['q']) and p['t'] < 1 or (p['col2'] and p['path'] != 'MapLimits')]
keys = {}
for p in solid:
    keys.setdefault(key(p), []).append(p)
unmatched = [p for p in solid if key(p, twin=True) not in keys]
print(f'symmetry: {len(solid)} solid parts, {len(unmatched)} without a twin')
for p in unmatched[:10]:
    failures.append(f"no 180-degree twin for {p['n']} in {p['path']} at {np.round(p['c'][:3], 1).tolist()}")


# ---------------------------------------------------------------- column intervals of every part
def intervals(p):
    """(cells x, cells z, y-bottom, y-top) arrays of the part's vertical extent over each 1-stud column."""
    a, b = aabb(p)
    x0, x1 = max(int(math.floor(a[0])), -HALF), min(int(math.ceil(b[0])), HALF)
    z0, z1 = max(int(math.floor(a[2])), -HALF), min(int(math.ceil(b[2])), HALF)
    if x1 <= x0 or z1 <= z0:
        return None
    xs, zs = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(z0, z1) + 0.5)
    xs, zs = xs.ravel(), zs.ravel()
    if p['k'] in ('Ball', 'Cylinder'):
        ylo = np.full(xs.shape, a[1])
        yhi = np.full(xs.shape, b[1])
    else:
        c = np.array(p['c'][:3])
        R = rot(p)
        s = np.array(p['s']) / 2
        # local = R^T (world - c) = base + y * dy
        base = np.stack([xs - c[0], -c[1] * np.ones_like(xs), zs - c[2]], axis=1) @ R
        dy = R[1, :]
        ylo = np.full(xs.shape, -1e9)
        yhi = np.full(xs.shape, 1e9)

        def clamp(coef, const, lim_lo, lim_hi):
            # lim_lo <= const + coef * y <= lim_hi
            nonlocal ylo, yhi
            if abs(coef) < 1e-9:
                bad = (const < lim_lo - 1e-6) | (const > lim_hi + 1e-6)
                ylo = np.where(bad, 1e9, ylo)
                return
            l = (lim_lo - const) / coef
            h = (lim_hi - const) / coef
            ylo = np.maximum(ylo, np.minimum(l, h))
            yhi = np.minimum(yhi, np.maximum(l, h))

        for i in range(3):
            clamp(dy[i], base[:, i], -s[i], s[i])
        if p['k'] == 'Wedge':
            # occupied where  ly - (sy/sz) lz <= 0
            k = s[1] / s[2]
            coef = dy[1] - k * dy[2]
            const = base[:, 1] - k * base[:, 2]
            clamp(coef, const, -1e9, 0)
    keep = yhi > ylo + 1e-3
    return (np.floor(xs[keep]).astype(int) + HALF, np.floor(zs[keep]).astype(int) + HALF, ylo[keep], yhi[keep])


col = {}        # (ix, iz) -> list of (bottom, top) for parts that collide
occ = np.zeros((NY, N, N), bool)   # line-of-sight blockers (parts raycasts hit)
for p in P:
    if p['path'] == 'MapLimits':
        continue
    if not (p['col2'] or (p['q'] and p['t'] < 1)):
        continue
    iv = intervals(p)
    if iv is None:
        continue
    ix, iz, yl, yh = iv
    if p['col2']:
        for a, b, l, h in zip(ix, iz, yl, yh):
            col.setdefault((a, b), []).append((l, h))
    if p['q'] and p['t'] < 1:
        j0 = np.clip(np.floor((yl - Y0) / YRES).astype(int), 0, NY)
        j1 = np.clip(np.ceil((yh - Y0) / YRES).astype(int), 0, NY)
        for a, b, u, v in zip(ix, iz, j0, j1):
            occ[u:v, b, a] = True

# standable surfaces per column: tops with 5 studs of headroom
surf = {}
for k, lst in col.items():
    lst.sort()
    merged = []
    for l, h in lst:
        if merged and l <= merged[-1][1] + 0.05:
            merged[-1][1] = max(merged[-1][1], h)
        else:
            merged.append([l, h])
    tops = []
    for i, (l, h) in enumerate(merged):
        nxt = merged[i + 1][0] if i + 1 < len(merged) else 1e9
        if nxt - h >= HEAD:
            tops.append(h)
    surf[k] = tops


def near_surface(ix, iz, y, tol=STEP):
    for t in surf.get((ix, iz), ()):
        if abs(t - y) <= tol:
            return t
    return None


# a node is a place a character can stand: the 3x3 cells around it all have a surface close by
valid = set()
for (ix, iz), tops in surf.items():
    for y in tops:
        ok = True
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                if near_surface(ix + dx, iz + dz, y) is None:
                    ok = False
                    break
            if not ok:
                break
        if ok:
            valid.add((ix, iz, round(y, 3)))
by_cell = {}
for (ix, iz, y) in valid:
    by_cell.setdefault((ix, iz), []).append(y)


def headroom_clear(ix, iz, y0, y1):
    for l, h in col.get((ix, iz), ()):
        if l < y1 and h > y0:
            return False
    return True


def neighbours(node, jump):
    ix, iz, y = node
    for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        for y2 in by_cell.get((ix + dx, iz + dz), ()):
            if y2 - y <= STEP:          # walk, step up or drop down
                yield (ix + dx, iz + dz, y2)
    if not jump:
        return
    R = 8
    for dx in range(-R, R + 1):
        for dz in range(-R, R + 1):
            if dx * dx + dz * dz > R * R or (dx == 0 and dz == 0):
                continue
            for y2 in by_cell.get((ix + dx, iz + dz), ()):
                if STEP < y2 - y <= JUMP:
                    top = max(y, y2)
                    n = max(abs(dx), abs(dz))
                    if all(headroom_clear(ix + round(dx * t / n), iz + round(dz * t / n), top + 0.3, top + HEAD)
                           for t in range(1, n)) and headroom_clear(ix, iz, y + 0.3, y2 + HEAD):
                        yield (ix + dx, iz + dz, y2)


def flood(start, jump):
    seen = {start}
    q = deque([start])
    while q:
        n = q.popleft()
        for m in neighbours(n, jump):
            if m not in seen:
                seen.add(m)
                q.append(m)
    return seen


spawns = [p for p in P if p['path'] == 'Spawns']


def node_at(x, z, y):
    best = None
    for dx in range(-2, 3):
        for dz in range(-2, 3):
            c = (int(math.floor(x)) + HALF + dx, int(math.floor(z)) + HALF + dz)
            for yy in by_cell.get(c, ()):
                if abs(yy - y) < 1.5 and (best is None or abs(dx) + abs(dz) < best[0]):
                    best = (abs(dx) + abs(dz), (c[0], c[1], yy))
    return best and best[1]


red1 = next(p for p in spawns if p['team'] == 'Red' and p['slot'] == 1)
blue1 = next(p for p in spawns if p['team'] == 'Blue' and p['slot'] == 1)
start = node_at(red1['c'][0], red1['c'][2], red1['c'][1] - 0.3)
goal = node_at(blue1['c'][0], blue1['c'][2], blue1['c'][1] - 0.3)
walk = flood(start, jump=False)
reach = flood(start, jump=True)
print(f'movement: {len(walk)} places reachable on foot from Red slot 1, {len(reach)} with jumping')
if goal not in walk:
    failures.append("Blue's spawn cannot be reached on foot from Red's")
for p in spawns:
    n = node_at(p['c'][0], p['c'][2], p['c'][1] - 0.3)
    if n is None or n not in walk:
        failures.append(f"spawn {p['team']} {p['slot']} is not on walkable ground reachable from Red slot 1")

# perches: reachable surfaces above 7.5 studs, grouped by what they stand on
high = sorted({(round(y, 1), ix - HALF, iz - HALF) for (ix, iz, y) in reach if y > 7.5}, reverse=True)
groups = {}
for y, x, z in high:
    key2 = (y, round(x / 6), round(z / 6))
    groups.setdefault(key2, []).append((x, z))
print(f'perches above 7.5 studs reachable by jumping: {len(groups)}')
for (y, _, _), cells in sorted(groups.items(), reverse=True)[:12]:
    xs = [c[0] for c in cells]
    zs = [c[1] for c in cells]
    print(f'  y {y:5.1f}  around x {np.mean(xs):6.1f}, z {np.mean(zs):6.1f}  ({len(cells)} cells)')
outside = [(ix - HALF, iz - HALF, y) for (ix, iz, y) in reach if abs(ix - HALF) > 110 or abs(iz - HALF) > 110]
if outside:
    failures.append(f'{len(outside)} reachable places are outside the play area, e.g. {outside[:3]}')

# ---------------------------------------------------------------- line of sight
def visible(src, targets, step=0.5):
    """Boolean array: can `src` (x, y, z) see each target point (rows of targets)?"""
    d = targets - src
    L = np.linalg.norm(d, axis=1)
    k = max(2, int(L.max() / step))
    t = np.linspace(0, 1, k + 1)[1:-1]
    pts = src[None, None, :] + t[None, :, None] * d[:, None, :]
    ix = np.clip(np.floor(pts[..., 0]).astype(int) + HALF, 0, N - 1)
    iz = np.clip(np.floor(pts[..., 2]).astype(int) + HALF, 0, N - 1)
    iy = np.clip(np.floor((pts[..., 1] - Y0) / YRES).astype(int), 0, NY - 1)
    blocked = occ[iy, iz, ix]
    # ignore samples within 0.8 studs of either end (the viewer's and the target's own cell)
    near = (t[None, :] * L[:, None] < 0.8) | ((1 - t[None, :]) * L[:, None] < 0.8)
    return ~np.any(blocked & ~near, axis=1)


stand = np.array([(ix - HALF + 0.5, y, iz - HALF + 0.5) for (ix, iz, y) in reach])
eyes = stand + np.array([0, 4.6, 0])

# ---------------------------------------------------------------- 4. spawn safety
def in_rect(x, z, r):
    return r[0] <= x <= r[2] and r[1] <= z <= r[3]


SAFE = [(-28, -109, 28, -88), (-52, -104, -28, -94), (28, -104, 44, -94), (-5, -88, 5, -80)]  # Red courtyard + doorways
exposure = {}
for p in spawns:
    flip = -1 if p['team'] == 'Blue' else 1
    home = [(-r[2], -r[3], -r[0], -r[1]) if flip < 0 else r for r in SAFE]
    mask = np.array([not any(in_rect(x, z, r) for r in home) for x, _, z in stand])
    viewers = eyes[mask]
    base = np.array(p['c'][:3]) - np.array([0, 0.3, 0])
    seen = np.zeros(len(viewers), bool)
    for h in (4.6, 3.0):
        tgt = base + np.array([0, h, 0])
        seen |= visible(tgt, viewers)
    exposure[(p['team'], p['slot'])] = viewers[seen]
    if seen.any():
        far = viewers[seen]
        failures.append(f"spawn {p['team']} {p['slot']} can be seen from {seen.sum()} places outside its courtyard, "
                        f"e.g. ({far[0][0]:.0f}, {far[0][2]:.0f})")
print('spawn safety: ' + ', '.join(f'{t} {s}: {len(v)} viewers' for (t, s), v in sorted(exposure.items())))

# ---------------------------------------------------------------- 5. sight lines
rng = np.random.default_rng(7)
ground = eyes[(stand[:, 1] > -5.5)]
sample = ground[rng.choice(len(ground), size=min(220, len(ground)), replace=False)]
targets = ground[::3]
longest = []
cover_frac = []
for v in sample:
    vis = visible(v, targets)
    dist = np.linalg.norm(targets - v, axis=1)
    ok = vis & (dist > 1)
    cover_frac.append(ok.mean())
    if ok.any():
        i = np.argmax(np.where(ok, dist, 0))
        longest.append((dist[i], tuple(np.round(v, 0)), tuple(np.round(targets[i], 0))))
longest.sort(reverse=True)
print(f'sight lines: from a typical spot you can see {np.median(cover_frac) * 100:.0f}% of the map '
      f'(most open spot {max(cover_frac) * 100:.0f}%)')
for L, a, b in longest[:5]:
    print(f'  {L:5.1f} studs: ({a[0]:.0f}, {a[2]:.0f}) -> ({b[0]:.0f}, {b[2]:.0f})')

# ---------------------------------------------------------------- images
if OUT:
    from PIL import Image
    img = np.full((N, N, 3), 40, np.uint8)
    for (ix, iz), tops in surf.items():
        img[iz, ix] = (70, 70, 76)
    for (ix, iz, y) in reach:
        g = int(np.clip(110 + y * 9, 40, 255))
        img[iz, ix] = (60, g, 90) if y > -1 else (60, 120, 190)
    for (ix, iz, y) in walk:
        pass
    for y, x, z in high:
        img[z + HALF, x + HALF] = (240, 70, 60)
    for p in spawns:
        x, z = int(p['c'][0]) + HALF, int(p['c'][2]) + HALF
        img[z - 1:z + 2, x - 1:x + 2] = (255, 220, 60) if p['team'] == 'Red' else (120, 200, 255)
    Image.fromarray(img).resize((1000, 1000), Image.NEAREST).save(f'{OUT}/duel_walk.png')
    # what Red's slot-1 spawn can be seen from (should be only its own courtyard)
    img2 = (np.max(occ[12:22], axis=0)[:, :, None] * np.array([70, 70, 76])).astype(np.uint8)
    p = red1
    base = np.array(p['c'][:3]) + np.array([0, 4.3, 0])
    vis = visible(base, eyes)
    for (x, y, z), v in zip(stand, vis):
        if v:
            img2[int(z) + HALF, int(x) + HALF] = (255, 200, 60)
    Image.fromarray(img2).resize((1000, 1000), Image.NEAREST).save(f'{OUT}/duel_spawn_view.png')

if failures:
    print('\n'.join(failures[:30]))
    print(f'{len(failures)} PROBLEM(S)')
    sys.exit(1)
print('duel map OK')
