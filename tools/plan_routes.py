"""Turns rough patrol routes into waypoint lists that walk around the map's clutter.

  python3 tools/plan_routes.py            (after `lune run build`)

Reads the rough routes from build/npc_markers.json, path-finds each leg on a walkable grid at the
route's height (floor present, nothing solid between knee and head height, 2-stud clearance), then
keeps only the corners a straight line cannot skip. Prints a Luau ROUTES table for
src/LiegeNPCPlacements.luau and nearest free spots for any blocked spawn markers.
"""
import heapq
import json
import math

import numpy as np

P = json.load(open('build/parts.json'))
MK = json.load(open('build/npc_markers.json'))
N = 1000

# rough routes: name -> (npc, loop, level, region x0,z0,x1,z1 or None, points)
ROUGH = {
    'PoliceWest': ('PoliceAgent', True, 0.0, None, [(-200, -100), (-90, -100), (-90, -458), (-226, -458), (-226, -110)]),
    'PoliceEast': ('PoliceAgent', False, 0.0, None, [(353, -440), (353, 0), (440, 0)]),
    'QuayWest': ('PoliceAgent', False, 0.2, (70, -446, 106, 440), [(100, -440), (100, 430)]),
    'QuayEast': ('Gendarme', False, 0.2, (234, -446, 262, 440), [(248, -440), (248, 430)]),
    'Feronstree': ('Lamplighter', False, 0.0, None, [(-90, -110), (-90, -440)]),
    'CitadelRampart': ('Soldier', False, 76.0, (-414, -494, -400, -102), [(-411, -488), (-411, -108)]),
    'CitadelParade': ('Soldier', True, 64.3, (-500, -494, -414, -102), [(-470, -460), (-430, -460), (-430, -140), (-470, -140)]),
}


def aabb(p):
    c, s = p['c'], p['s']
    R = np.abs(np.array(c[3:]).reshape(3, 3))
    h = R @ (np.array(s) / 2)
    o = np.array(c[:3])
    return o - h, o + h


boxes = [(p, *aabb(p)) for p in P if p['col2']]


def level_grid(y, region, clearance=2):
    blocked = np.zeros((N, N), bool)
    floor = np.zeros((N, N), bool)
    for p, lo, hi in boxes:
        z0, z1 = max(int(math.floor(lo[2] + 500)), 0), int(math.ceil(hi[2] + 500))
        x0, x1 = max(int(math.floor(lo[0] + 500)), 0), int(math.ceil(hi[0] + 500))
        if p['k'] != 'Wedge' and lo[1] < y + 5 and hi[1] > y + 1:
            blocked[z0:z1, x0:x1] = True
        if y - 0.45 <= hi[1] <= y + 0.1:
            floor[z0:z1, x0:x1] = True
    free = floor & ~blocked
    if region:
        mask = np.zeros_like(free)
        x0, z0, x1, z1 = region
        mask[int(z0 + 500):int(z1 + 500), int(x0 + 500):int(x1 + 500)] = True
        free &= mask
    er = free.copy()
    for dz in range(-clearance, clearance + 1):
        for dx in range(-clearance, clearance + 1):
            er &= np.roll(np.roll(free, dz, 0), dx, 1)
    return er


def nearest_free(g, x, z, rmax=30):
    zi, xi = int(round(z)) + 500, int(round(x)) + 500
    if g[zi, xi]:
        return zi, xi
    for r in range(1, rmax):
        best = None
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dz), abs(dx)) != r:
                    continue
                a, b = zi + dz, xi + dx
                if 0 <= a < N and 0 <= b < N and g[a, b]:
                    d = dz * dz + dx * dx
                    if best is None or d < best[0]:
                        best = (d, a, b)
        if best:
            return best[1], best[2]
    return None


def astar(g, s, t):
    D = math.sqrt(2)
    openh = [(0, s)]
    came = {s: None}
    cost = {s: 0}
    while openh:
        _, cur = heapq.heappop(openh)
        if cur == t:
            break
        for dz, dx, w in ((1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1), (1, 1, D), (1, -1, D), (-1, 1, D), (-1, -1, D)):
            n = (cur[0] + dz, cur[1] + dx)
            if not (0 <= n[0] < N and 0 <= n[1] < N) or not g[n]:
                continue
            c = cost[cur] + w
            if c < cost.get(n, 1e18):
                cost[n] = c
                came[n] = cur
                heapq.heappush(openh, (c + math.hypot(t[0] - n[0], t[1] - n[1]), n))
    if t not in came:
        return None
    path = [t]
    while came[path[-1]] is not None:
        path.append(came[path[-1]])
    return path[::-1]


def visible(g, a, b):
    L = max(abs(b[0] - a[0]), abs(b[1] - a[1])) * 2 + 1
    for i in range(L + 1):
        t = i / L
        z = int(round(a[0] + (b[0] - a[0]) * t))
        x = int(round(a[1] + (b[1] - a[1]) * t))
        if not g[z, x]:
            return False
    return True


def simplify(g, path):
    out = [path[0]]
    i = 0
    while i < len(path) - 1:
        j = len(path) - 1
        while j > i + 1 and not visible(g, path[i], path[j]):
            j -= 1
        out.append(path[j])
        i = j
    return out


lines = []
for name, (npc, loop, y, region, pts) in ROUGH.items():
    g = level_grid(y, region)
    snapped = [nearest_free(g, x, z) for x, z in pts]
    if any(s is None for s in snapped):
        raise SystemExit(f'{name}: a rough point has no free cell nearby')
    legs = list(zip(snapped, snapped[1:] + ([snapped[0]] if loop else [])))
    way = []
    for a, b in legs:
        path = astar(g, a, b)
        if path is None:
            raise SystemExit(f'{name}: no path {a} -> {b}')
        simp = simplify(g, path)
        way.extend(simp if not way else simp[1:])
    if loop and way[-1] == way[0]:
        way = way[:-1]
    pts_out = ', '.join('{ %d, %s, %d }' % (x - 500, ('%g' % y), z - 500) for z, x in way)
    lines.append('\t\t%s = { npc = "%s", loop = %s, points = { %s } },' % (name, npc, 'true' if loop else 'false', pts_out))
    print(f'-- {name}: {len(pts)} rough points -> {len(way)} waypoints')

print('\tlocal ROUTES = {')
print('\n'.join(lines))
print('\t}')

# blocked spawns: suggest the nearest clear spot
street = {}
for s in MK['spawns']:
    lvl = round(s['y'], 1)
    if lvl not in street:
        street[lvl] = level_grid(s['y'], None, clearance=1)
    g = street[lvl]
    zi, xi = int(round(s['z'])) + 500, int(round(s['x'])) + 500
    if not g[zi, xi]:
        nf = nearest_free(g, s['x'], s['z'])
        if nf:
            print(f"-- spawn {s['name']} ({s['x']}, {s['z']}) -> nearest clear ({nf[1] - 500}, {nf[0] - 500})")
