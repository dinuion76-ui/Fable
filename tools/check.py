"""Sanity checks on build/parts.json: footprint, overlapping buildings, ground-level reachability.
usage: python3 tools/check.py [out.png]"""
import json, sys, collections
import numpy as np
from PIL import Image

P = json.load(open('build/parts.json'))

def aabb(p):
    c, s = p['c'], p['s']
    R = np.abs(np.array(c[3:]).reshape(3, 3))
    h = R @ (np.array(s) / 2)
    o = np.array(c[:3])
    return o - h, o + h

boxes = [(p, *aabb(p)) for p in P]
lo = np.min([b[1] for b in boxes], axis=0); hi = np.max([b[2] for b in boxes], axis=0)
print('footprint', (hi - lo).round(1), 'min', lo.round(1), 'max', hi.round(1))
assert hi[0] - lo[0] <= 1000.01 and hi[2] - lo[2] <= 1000.01, 'exceeds 1000x1000'

# 1. big solid boxes that overlap each other substantially (double-built plots / z-fighting)
big = [(p, a, b) for p, a, b in boxes if p['k'] == 'Block' and p['n'] in ('Wall', 'Body') and p['t'] == 0 and np.prod(b - a) > 3000]
bad = 0
for i in range(len(big)):
    for j in range(i + 1, len(big)):
        a0, a1, b0, b1 = big[i][1], big[i][2], big[j][1], big[j][2]
        ov = np.minimum(a1, b1) - np.maximum(a0, b0)
        if (ov > 0.5).all():
            bad += 1
            if bad <= 15: print('OVERLAP', big[i][0]['n'], a0.round(0), a1.round(0), '<->', big[j][0]['n'], b0.round(0), b1.round(0))
print('overlapping building bodies:', bad)

# 2. ground-level walkability at 1 stud resolution
N = 1000
def grid_for(y0, y1):
    g = np.zeros((N, N), bool)
    for p, a, b in boxes:
        if not p['col2'] or p['k'] == 'Wedge': continue
        if a[1] < y1 and b[1] > y0:
            x0, x1 = int(np.floor(a[0] + 500)), int(np.ceil(b[0] + 500))
            z0, z1 = int(np.floor(a[2] + 500)), int(np.ceil(b[2] + 500))
            g[max(z0, 0):min(z1, N), max(x0, 0):min(x1, N)] = True
    return g
blocked = grid_for(1.6, 5.0)                     # anything a standing character would hit
river = np.zeros((N, N), bool); river[:, 610:730] = True
blocked_land = blocked | river
# erode free space by character radius (2 studs)
free = ~blocked_land
r = 2
er = free.copy()
for dz in range(-r, r + 1):
    for dx in range(-r, r + 1):
        er &= np.roll(np.roll(free, dz, 0), dx, 1)
from collections import deque
def flood(seed):
    seen = np.zeros_like(er); q = deque([seed]); seen[seed] = True
    while q:
        z, x = q.popleft()
        for dz, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            zz, xx = z + dz, x + dx
            if 0 <= zz < N and 0 <= xx < N and er[zz, xx] and not seen[zz, xx]:
                seen[zz, xx] = True; q.append((zz, xx))
    return seen
def flood_any(cands):
    for x, z in cands:
        if er[z + 500, x + 500]: return flood((z + 500, x + 500))
    raise SystemExit('no free seed')
west = flood_any([(-200, -100), (-226, -300), (-90, -250)])   # Place du Marché / Hors-Château
east = flood_any([(300, 0), (353, -60), (248, 100), (353, 120)])  # east bank
reach = west | east
orphan = er & ~reach
print('west reach', west.sum(), 'east reach', east.sum(), 'orphan free cells', orphan.sum())
img = np.zeros((N, N, 3), np.uint8)
img[blocked] = (60, 60, 66); img[river] = (40, 70, 90)
img[west] = (90, 170, 90); img[east] = (90, 150, 190); img[orphan] = (230, 60, 60)
Image.fromarray(img).resize((1500, 1500), Image.NEAREST).save(sys.argv[1] if len(sys.argv) > 1 else 'build/walk.png')
# narrowest points: report POIs
pois = {'Marche': (-200, -100), 'StLambert': (-265, 60), 'HorsChateau': (-226, -420), 'Feronstree': (-90, -330), 'QuaiBatte': (90, -300),
        'Cathedrale': (-250, 190), 'Sauveniere': (-200, 341), 'GoodsYard': (-214, 392), 'PalaceCourt': (-430, 20), 'BackYards': (-158, -240),
        'EnNeuvice': (-5, -140), 'NaveInside': (-250, 281), 'Passage': (-44, 102), 'SLcourt': (-152, 86),
        'EastQuay': (248, -330), 'PuitsEnSock': (353, -300), 'EastYards': (430, -200), 'Station': (360, 340), 'CoalYard': (400, 244),
        'Atelier': (378, -140), 'AtelierBack': (396, -148), 'Halle': (52, -214), 'ProofHouse': (420, -350), 'Foundry': (410, 100), 'Estaminet': (275, 40),
        'Platform': (360, 433), 'EALane': (301, -300), 'EALaneS': (301, 200), 'RailW': (-200, 453), 'NorthStreetE': (400, -458)}
for k, (x, z) in pois.items():
    ok = reach[z + 500 - 6:z + 500 + 7, x + 500 - 6:x + 500 + 7].any()   # tolerate a crate sitting on the exact spot
    if not ok: print('UNREACHABLE', k, (x, z))
print('all %d points of interest reachable on foot' % len(pois) if all(reach[z + 494:z + 507, x + 494:x + 507].any() for x, z in pois.values()) else 'SOME POINTS UNREACHABLE')
