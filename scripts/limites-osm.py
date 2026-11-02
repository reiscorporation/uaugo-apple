"""Complemento dos limites de velocidade a partir do OpenStreetMap.

O que faz: lê o mapa do Brasil, pega as vias com `maxspeed` (motorway a tertiary
  e as alças) e grava um ponto a cada 100 m, por estado, no mesmo formato de
  public/limites/UF.json.gz. A função updateSpeedLimits junta estes pontos aos
  do Pardal (functions/speedlimits.js).

Uso: python scripts/limites-osm.py <brazil.osm.pbf> <pasta de saída>
Publicar: gcloud storage cp saida/*.json.gz gs://<bucket>/public/limites-osm/
"""
import collections
import gzip
import json
import math
import os
import sys
import urllib.request

import osmium

BASE = 'https://raw.githubusercontent.com/Murkiriel/pardal/main'
CLASSES = {'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'motorway_link',
           'trunk_link', 'primary_link', 'secondary_link', 'tertiary_link'}
STEP = 100.0


def kmh(v):
    """Limite do `maxspeed` em km/h; None se não for um número plausível."""
    v = (v or '').split(';')[0].strip().lower().replace('km/h', '').replace('kph', '').strip()
    if not v.isdigit():
        return None
    n = int(v)
    return n if 10 <= n <= 130 else None


def bearing(a, b):
    k = math.cos(math.radians(a[0]))
    return int(math.degrees(math.atan2((b[1] - a[1]) * k, b[0] - a[0]))) % 360


def dist(a, b):
    k = math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot((a[0] - b[0]) * 111320, (a[1] - b[1]) * 111320 * k)


def sample(pts):
    """Pontos a cada STEP metros, com o sentido da via."""
    out, left = [], 0.0
    for a, b in zip(pts, pts[1:]):
        d = dist(a, b)
        if d < .5:
            continue
        brg = bearing(a, b)
        while left <= d:
            t = left / d
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, brg))
            left += STEP
        left -= d
    return out


class Vias(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.pts = []

    def way(self, w):
        t = w.tags
        if t.get('highway') not in CLASSES or t.get('area') == 'yes':
            return
        both = kmh(t.get('maxspeed'))
        fwd = kmh(t.get('maxspeed:forward')) or both
        back = kmh(t.get('maxspeed:backward')) or both
        if not fwd and not back:
            return
        try:
            pts = [(n.lat, n.lon) for n in w.nodes]
        except osmium.InvalidLocationError:
            return
        oneway = t.get('oneway') == 'yes' or t.get('highway') in ('motorway', 'motorway_link') \
            or t.get('junction') == 'roundabout'
        if t.get('oneway') == '-1':
            pts.reverse()
            oneway = True
        if fwd:
            self.pts += [(a, o, fwd, b) for a, o, b in sample(pts)]
        if back and not oneway:
            self.pts += [(a, o, back, b) for a, o, b in sample(pts[::-1])]


def bboxes():
    cat = json.load(urllib.request.urlopen(BASE + '/catalogo.json', timeout=60))
    return {u: i['bbox'] for u, i in cat['ufs'].items() if len(u) == 2 and u != 'BR' and i.get('bbox')}


def main(pbf, out):
    os.makedirs(out, exist_ok=True)
    h = Vias()
    h.apply_file(pbf, locations=True, idx='flex_mem')
    print('pontos', len(h.pts))
    box = bboxes()
    uf = collections.defaultdict(list)
    for la, lo, lim, brg in h.pts:
        # Na divisa, vale nos dois estados (o app baixa um só).
        for u, b in box.items():
            if b[0] <= la <= b[2] and b[1] <= lo <= b[3]:
                uf[u].append((round(la * 1e5), round(lo * 1e5), lim, 0, brg))
    for u, p in sorted(uf.items()):
        p.sort()
        d, pa, po = [], 0, 0
        for la, lo, lim, est, brg in p:
            d += [la - pa, lo - po, lim, est, brg]
            pa, po = la, lo
        with gzip.open(f'{out}/{u}.json.gz', 'wt', encoding='utf-8', compresslevel=9) as f:
            json.dump({'v': 1, 'uf': u, 'd': d}, f, separators=(',', ':'))
        print(u, len(p), os.path.getsize(f'{out}/{u}.json.gz') // 1024, 'KB')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
