"""Checks the NPC markers against the map (run `lune run build` first).

  python3 tools/check_npcs.py [walk.png]

For every spawn marker, patrol waypoint and boss spawn:
  - there is a floor under it (no floating or buried NPCs)
  - nothing solid stands where the character stands (body radius, from knee to head height)
  - ground-level spawns can walk to the rest of their bank
Patrol routes: every leg between waypoints is clear for a walking character.
Boss arenas: the boss fits at its spawn and the player can walk from PlayerEntry to the boss.
Exits non-zero when something fails.
"""
import json
import sys
from collections import deque

import numpy as np

P = json.load(open('build/parts.json'))
MK = json.load(open('build/npc_markers.json'))


def aabb(p):
    c, s = p['c'], p['s']
    R = np.abs(np.array(c[3:]).reshape(3, 3))
    h = R @ (np.array(s) / 2)
    o = np.array(c[:3])
    return o - h, o + h


solid = []   # colliding parts that are not wedges (wedges are roofs, ramps and stair slopes)
floors = []  # every colliding part, for floor support
for p in P:
    if not p['col2']:
        continue
    lo, hi = aabb(p)
    floors.append((lo, hi))
    if p['k'] != 'Wedge':
        solid.append((lo, hi))
S_LO = np.array([s[0] for s in solid])
S_HI = np.array([s[1] for s in solid])
F_LO = np.array([f[0] for f in floors])
F_HI = np.array([f[1] for f in floors])

failures = []


def blocked(x, z, y, r, h=5.0):
    """Solid parts overlapping a box of half-width r around (x, z) from y+1 to y+h."""
    m = ((S_LO[:, 0] < x + r) & (S_HI[:, 0] > x - r) & (S_LO[:, 2] < z + r) & (S_HI[:, 2] > z - r)
         & (S_LO[:, 1] < y + h) & (S_HI[:, 1] > y + 1.0))
    return np.nonzero(m)[0]


def floor_top(x, z, y):
    m = ((F_LO[:, 0] <= x) & (F_HI[:, 0] >= x) & (F_LO[:, 2] <= z) & (F_HI[:, 2] >= z)
         & (F_HI[:, 1] <= y + 0.05) & (F_HI[:, 1] >= y - 0.35))
    return m.any()


# --- walkable grid at street level (same idea as tools/check.py), for reachability
N = 1000
def grid(y0, y1, radius):
    g = np.zeros((N, N), bool)
    for lo, hi in solid:
        if lo[1] < y1 and hi[1] > y0:
            g[max(int(np.floor(lo[2] + 500)), 0):int(np.ceil(hi[2] + 500)), max(int(np.floor(lo[0] + 500)), 0):int(np.ceil(hi[0] + 500))] = True
    g[:, 610:730] = True  # the river, except where a bridge deck crosses it
    g[484:516, 606:734] = False   # Pont des Arches (z -16..16)
    g[660:674, 606:734] = False   # the Passerelle (z 160..174)
    for lo, hi in solid:
        if lo[1] < y1 and hi[1] > y0 and lo[0] < 234 and hi[0] > 106:
            g[max(int(np.floor(lo[2] + 500)), 0):int(np.ceil(hi[2] + 500)), max(int(np.floor(lo[0] + 500)), 0):int(np.ceil(hi[0] + 500))] = True
    free = ~g
    er = free.copy()
    for dz in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            er &= np.roll(np.roll(free, dz, 0), dx, 1)
    return er


def flood(er, x, z):
    seen = np.zeros_like(er)
    seed = (int(round(z)) + 500, int(round(x)) + 500)
    best = None
    for dz in range(-4, 5):
        for dx in range(-4, 5):
            c = (seed[0] + dz, seed[1] + dx)
            if er[c]:
                best = c
                break
        if best:
            break
    if not best:
        return seen
    q = deque([best])
    seen[best] = True
    while q:
        zz, xx = q.popleft()
        for dz, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            a, b = zz + dz, xx + dx
            if 0 <= a < N and 0 <= b < N and er[a, b] and not seen[a, b]:
                seen[a, b] = True
                q.append((a, b))
    return seen


def near(seen, x, z, r=4):
    zi, xi = int(round(z)) + 500, int(round(x)) + 500
    return seen[max(zi - r, 0):zi + r + 1, max(xi - r, 0):xi + r + 1].any()


street = grid(1.6, 5.0, 1)
west = flood(street, -200, -100)
east = flood(street, 300, 0)
reach = west | east

# --- spawns
for s in MK['spawns']:
    sc = s.get('scale', 1)
    r = 1.2 * sc
    hits = blocked(s['x'], s['z'], s['y'], r, 4.5 * sc)
    if len(hits):
        failures.append(f"spawn {s['name']} at ({s['x']:.1f}, {s['y']:.2f}, {s['z']:.1f}) blocked by {len(hits)} part(s)")
    if not floor_top(s['x'], s['z'], s['y']):
        failures.append(f"spawn {s['name']} at ({s['x']:.1f}, {s['y']:.2f}, {s['z']:.1f}) has no floor under it")
    if s['y'] < 1.0 and not near(reach, s['x'], s['z']):
        failures.append(f"spawn {s['name']} at ({s['x']:.1f}, {s['z']:.1f}) cannot walk to the rest of the town")

# --- patrol routes
for name, r in MK['routes'].items():
    pts = r['points'] + ([r['points'][0]] if r['loop'] else [])
    bad = 0
    for a, b in zip(pts, pts[1:]):
        L = max(1, int(np.hypot(b[0] - a[0], b[2] - a[2]) / 0.5))
        for i in range(L + 1):
            t = i / L
            x, y, z = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
            if len(blocked(x, z, y, 1.2)):
                bad += 1
                if bad <= 3:
                    failures.append(f"route {name}: leg {a[0]:.0f},{a[2]:.0f} -> {b[0]:.0f},{b[2]:.0f} blocked near ({x:.1f}, {z:.1f})")
        for q in (a, b):
            if not floor_top(q[0], q[2], q[1]):
                failures.append(f"route {name}: waypoint ({q[0]:.0f}, {q[1]:.2f}, {q[2]:.0f}) has no floor")
    if bad > 3:
        failures.append(f"route {name}: {bad} blocked samples in total")

# --- boss arenas
for a in MK['arenas']:
    sc = a['scale']
    hits = blocked(a['x'], a['z'], a['y'], 1.4 * sc, 5.2 * sc)
    if len(hits):
        failures.append(f"arena {a['name']}: boss spawn blocked by {len(hits)} part(s)")
    if not floor_top(a['x'], a['z'], a['y']):
        failures.append(f"arena {a['name']}: boss spawn has no floor")
    reach_entry = flood(street, a['entry'][0], a['entry'][2])
    if not near(reach_entry, a['x'], a['z']):
        failures.append(f"arena {a['name']}: player cannot walk from PlayerEntry to the boss")
    for add in a['adds']:
        if len(blocked(add[1], add[3], add[2], 1.2)):
            failures.append(f"arena {a['name']}: reinforcement {add[0]} blocked")

print(f"{len(MK['spawns'])} spawns, {len(MK['routes'])} routes, {len(MK['arenas'])} arenas checked")
if len(sys.argv) > 1:
    from PIL import Image
    img = np.zeros((N, N, 3), np.uint8)
    img[~street] = (60, 60, 66)
    img[reach] = (90, 150, 110)
    for s in MK['spawns']:
        zi, xi = int(s['z']) + 500, int(s['x']) + 500
        img[max(zi - 2, 0):zi + 3, max(xi - 2, 0):xi + 3] = (255, 210, 60)
    for r in MK['routes'].values():
        for q in r['points']:
            zi, xi = int(q[2]) + 500, int(q[0]) + 500
            img[max(zi - 2, 0):zi + 3, max(xi - 2, 0):xi + 3] = (80, 160, 255)
    for a in MK['arenas']:
        zi, xi = int(a['z']) + 500, int(a['x']) + 500
        img[max(zi - 4, 0):zi + 5, max(xi - 4, 0):xi + 5] = (255, 60, 60)
    Image.fromarray(img).resize((1500, 1500), Image.NEAREST).save(sys.argv[1])
if failures:
    print('\n'.join(failures))
    print(f'{len(failures)} PROBLEM(S)')
    sys.exit(1)
print('all markers, routes and arenas OK')
