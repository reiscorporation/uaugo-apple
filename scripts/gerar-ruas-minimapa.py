"""Gera os quadrados de ruas do minimapa do 3D (UauGo2/v2).

O que faz: lê TODAS as ruas extraídas do OpenStreetMap (GeoJSON sequencial do
  `osmium export`), simplifica o traçado (~4 m) e grava um arquivo por
  quadrado de 0,02 grau (~2,2 km): <saida>/<ilat>_<ilng>.json.gz, com
  ilat = floor(lat / 0,02) e ilng = floor(lng / 0,02). O app baixa só os
  quadrados em volta do piloto e desenha as ruas no minimapa do 3D, com as
  travessas (pedido de 08/11).

Formato de cada arquivo: {"v":1,"w":[[classe, lat0, lng0, dlat1, dlng1, ...]]}
  com coordenadas em 1e-5 grau (inteiros) e diferenças a partir do ponto 0.
  Classe: 1 expressa/rodovia, 2 primária, 3 secundária, 4 terciária e alças,
  5 rua local.

Como gerar (rotina no PC; veja scripts/gerar-ruas-minimapa.ps1). Lê o .pbf
direto (pip install osmium), sem Docker:
  python scripts/gerar-ruas-minimapa.py brazil-latest.osm.pbf saida/ [oeste,sul,leste,norte]
Os arquivos vão para a VPS (pasta servida em /ruas/ do motor).
"""
import gzip
import json
import math
import os
import sys
from collections import defaultdict

TILE = 0.02
CLS = {
    'motorway': 1, 'trunk': 1, 'primary': 2, 'secondary': 3, 'tertiary': 4,
    'motorway_link': 4, 'trunk_link': 4, 'primary_link': 4,
    'secondary_link': 4, 'tertiary_link': 4,
    'residential': 5, 'unclassified': 5, 'living_street': 5,
}
TOL = 4e-5  # ~4 m


def simplify(pts, tol=TOL):
    """Douglas-Peucker (sem recursão)."""
    if len(pts) < 3:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = pts[a]
        bx, by = pts[b]
        dx, dy = bx - ax, by - ay
        n = math.hypot(dx, dy) or 1e-12
        best, bi = 0.0, -1
        for i in range(a + 1, b):
            px, py = pts[i]
            d = abs(dy * px - dx * py + bx * ay - by * ax) / n
            if d > best:
                best, bi = d, i
        if best > tol and bi > 0:
            keep[bi] = True
            stack.append((a, bi))
            stack.append((bi, b))
    return [p for p, k in zip(pts, keep) if k]


def tile_of(lat, lng):
    return (math.floor(lat / TILE), math.floor(lng / TILE))


def encode(cls, pts):
    q = [(round(la * 1e5), round(lo * 1e5)) for la, lo in pts]
    out = [cls, q[0][0], q[0][1]]
    for (a, b), (c, d) in zip(q, q[1:]):
        out += [c - a, d - b]
    return out


def flush(buf, out_dir):
    """Acrescenta as ruas guardadas em memória aos arquivos parciais."""
    for t, ways in buf.items():
        with open(os.path.join(out_dir, '%d_%d.part' % t), 'a', encoding='utf-8') as f:
            for w in ways:
                f.write(json.dumps(w, separators=(',', ':')) + '\n')
    buf.clear()


def main(src, out_dir, bbox=None):
    import osmium
    os.makedirs(out_dir, exist_ok=True)
    for name in os.listdir(out_dir):
        if name.endswith('.part'):
            os.remove(os.path.join(out_dir, name))
    buf = defaultdict(list)
    st = {'held': 0, 'n': 0}

    def inside(p):
        return bbox is None or (bbox[1] <= p[0] <= bbox[3] and bbox[0] <= p[1] <= bbox[2])

    def add(cls, coords):
        pts = simplify(coords)
        if len(pts) < 2 or not any(inside(p) for p in pts):
            return
        # Corta a rua em pedaços por quadrado (o pedaço leva o ponto da
        # divisa dos dois lados, para a linha não ficar com buraco).
        piece, cur = [pts[0]], tile_of(*pts[0])
        for p in pts[1:]:
            t = tile_of(*p)
            piece.append(p)
            if t != cur:
                buf[cur].append(encode(cls, piece))
                piece, cur = [piece[-2], p], t
        if len(piece) >= 2:
            buf[cur].append(encode(cls, piece))
        st['n'] += 1
        st['held'] += 1
        if st['held'] >= 200000:
            flush(buf, out_dir)
            st['held'] = 0
            print('  ... %d ruas' % st['n'], flush=True)

    class H(osmium.SimpleHandler):
        def way(self, w):
            cls = CLS.get(w.tags.get('highway'))
            if not cls:
                return
            try:
                coords = [(n.lat, n.lon) for n in w.nodes if n.location.valid()]
            except osmium.InvalidLocationError:
                return
            if len(coords) >= 2:
                add(cls, coords)

    # Índice dos pontos em arquivo (o Brasil inteiro não cabe na memória).
    idx = 'sparse_file_array,' + os.path.join(out_dir, '_pontos.idx')
    H().apply_file(src, locations=True, idx=idx)
    try:
        os.remove(os.path.join(out_dir, '_pontos.idx'))
    except OSError:
        pass
    n = st['n']
    flush(buf, out_dir)
    tiles = total = 0
    for name in os.listdir(out_dir):
        if not name.endswith('.part'):
            continue
        part = os.path.join(out_dir, name)
        with open(part, encoding='utf-8') as f:
            ways = [json.loads(l) for l in f]
        data = json.dumps({'v': 1, 'w': ways}, separators=(',', ':')).encode()
        dst = os.path.join(out_dir, name[:-5] + '.json.gz')
        with gzip.open(dst, 'wb', compresslevel=9) as g:
            g.write(data)
        os.remove(part)
        tiles += 1
        total += os.path.getsize(dst)
    print('ruas: %d, quadrados: %d, total %.1f MB' % (n, tiles, total / 1e6))


if __name__ == '__main__':
    bb = [float(x) for x in sys.argv[3].split(',')] if len(sys.argv) > 3 else None
    main(sys.argv[1], sys.argv[2], bb)
